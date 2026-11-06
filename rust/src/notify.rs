//! IF-017/018: bounded relay submission with host-protected credential lookup.
//! No secret is written to config, logs, argv, recovery kits or worker output.
use anyhow::{Context, Result, ensure};
use lettre::{
    Message, SmtpTransport, Transport, message::Mailbox,
    transport::smtp::authentication::Credentials,
};
use serde::{Deserialize, Serialize};
use std::{
    io::{Read, Write},
    process::{Command, Stdio},
    time::{Duration, Instant},
};

#[derive(Clone, Serialize, Deserialize, Debug)]
pub struct Settings {
    pub to: String,
    pub from: String,
    pub server: String,
    pub port: u16,
    pub credential: Option<String>,
}
#[derive(Serialize, Deserialize)]
struct Request {
    settings: Settings,
    body: String,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Secret {
    username: String,
    password: String,
}

pub fn validate(settings: &Settings) -> Result<()> {
    ensure!(settings.port > 0, "SmtpPort: must be nonzero");
    settings
        .to
        .parse::<Mailbox>()
        .map_err(|_| anyhow::anyhow!("ToEmail: invalid mailbox"))?;
    settings
        .from
        .parse::<Mailbox>()
        .map_err(|_| anyhow::anyhow!("FromEmail: invalid mailbox"))?;
    ensure!(
        !settings.server.is_empty()
            && settings.server.len() <= 253
            && settings
                .server
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || ".-:".contains(c)),
        "SmtpServer: invalid hostname"
    );
    if let Some(reference) = &settings.credential {
        let name = reference
            .strip_prefix("credential:")
            .context("Credential: protected reference required")?;
        ensure!(
            !name.is_empty()
                && name.len() <= 128
                && name
                    .bytes()
                    .all(|c| c.is_ascii_alphanumeric() || b"-_.".contains(&c)),
            "Credential: invalid reference name"
        );
    }
    Ok(())
}
pub fn message(settings: &Settings, body: &str) -> Result<Message> {
    validate(settings)?;
    Ok(Message::builder()
        .from(settings.from.parse()?)
        .to(settings.to.parse()?)
        .subject("FileBackup run result")
        .body(body.to_owned())?)
}
/// Bound incident summaries independently of the number of individual findings.
/// Detailed paths/messages remain in local reports, never in the relay payload.
pub fn summary(reports: &[crate::engine::Report]) -> Result<String> {
    let sets: Vec<_> = reports
        .iter()
        .take(100)
        .map(|r| {
            serde_json::json!({
                "action":r.action,"set":r.set.chars().take(128).collect::<String>(),
                "code":r.code,"captured":r.captured,"reused":r.reused,"failed":r.failed,
                "added":r.added,"changed":r.changed,"removed":r.removed,"frozen":r.frozen,
                "finding_count":r.events.len(),"elapsed_ms":r.elapsed_ms
            })
        })
        .collect();
    Ok(serde_json::to_string(&serde_json::json!({"sets":sets,
        "total_sets":reports.len(),"omitted_sets":reports.len().saturating_sub(100)}))?)
}
/// Execute in a child so even an OS credential/DNS stall has a hard lifetime.
/// Call only after capture finishes; failure cannot change the operation result.
pub fn submit(settings: &Settings, reports: &[crate::engine::Report]) -> Result<()> {
    validate(settings)?;
    let body = summary(reports)?;
    let request = serde_json::to_vec(&Request {
        settings: settings.clone(),
        body,
    })?;
    ensure!(
        request.len() <= 1024 * 1024,
        "notification summary exceeds bounded size"
    );
    let mut child = Command::new(std::env::current_exe()?)
        .arg("__notification_worker")
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()?;
    let mut input = child
        .stdin
        .take()
        .context("notification worker pipe unavailable")?;
    // Pipe writing is bounded by the same parent deadline, not a blocking main-thread write.
    let writer = std::thread::spawn(move || input.write_all(&request));
    let start = Instant::now();
    loop {
        if let Some(status) = child.try_wait()? {
            let _ = writer.join();
            ensure!(
                status.success(),
                "notification submission failed; check relay and execution-account credential access"
            );
            return Ok(());
        }
        if start.elapsed() >= Duration::from_secs(60) {
            let _ = child.kill();
            let _ = child.wait();
            let _ = writer.join();
            anyhow::bail!("notification deadline exceeded");
        }
        std::thread::sleep(Duration::from_millis(25));
    }
}
pub fn worker() -> i32 {
    // Deliberately return only a status. Provider errors may contain secret material.
    let work = || -> Result<()> {
        let mut bytes = Vec::new();
        std::io::stdin()
            .take(1024 * 1024 + 1)
            .read_to_end(&mut bytes)?;
        ensure!(bytes.len() <= 1024 * 1024, "oversized notification request");
        let request: Request = serde_json::from_slice(&bytes)?;
        let message = message(&request.settings, &request.body)?;
        let mut transport = if request.settings.port == 465 {
            SmtpTransport::relay(&request.settings.server)?
        } else {
            SmtpTransport::starttls_relay(&request.settings.server)?
        }
        .port(request.settings.port)
        .timeout(Some(Duration::from_secs(15)));
        if let Some(reference) = &request.settings.credential {
            let secret = credential(
                reference
                    .strip_prefix("credential:")
                    .context("invalid reference")?,
            )?;
            ensure!(
                !secret.username.is_empty() && !secret.password.is_empty(),
                "empty credential"
            );
            transport = transport.credentials(Credentials::new(secret.username, secret.password));
        }
        transport.build().send(&message)?;
        Ok(())
    };
    if work().is_ok() { 0 } else { 1 }
}

#[cfg(target_os = "linux")]
fn credential(name: &str) -> Result<Secret> {
    use secret_service::{EncryptionType, blocking::SecretService};
    let service = SecretService::connect(EncryptionType::Dh)?;
    let items = service.search_items(std::collections::HashMap::from([
        ("service", "FileBackup"),
        ("account", name),
    ]))?;
    // Never call unlock/create/prompt: a locked or ambiguous item is unavailable.
    ensure!(
        items.locked.is_empty() && items.unlocked.len() == 1,
        "credential unavailable without interaction"
    );
    let bytes = items.unlocked[0].get_secret()?;
    ensure!(bytes.len() <= 16 * 1024, "oversized credential");
    Ok(serde_json::from_slice(&bytes)?)
}
#[cfg(windows)]
fn credential(name: &str) -> Result<Secret> {
    use windows_sys::Win32::Security::Credentials::{
        CRED_TYPE_GENERIC, CREDENTIALW, CredFree, CredReadW,
    };
    let target: Vec<_> = format!("FileBackup:{name}")
        .encode_utf16()
        .chain(Some(0))
        .collect();
    let mut pointer: *mut CREDENTIALW = std::ptr::null_mut();
    // SAFETY: valid terminated input and out pointer. Windows owns the allocation until CredFree.
    ensure!(
        unsafe { CredReadW(target.as_ptr(), CRED_TYPE_GENERIC, 0, &mut pointer) } != 0,
        "credential unavailable"
    );
    struct Owned(*mut CREDENTIALW);
    impl Drop for Owned {
        fn drop(&mut self) {
            unsafe {
                CredFree(self.0.cast());
            }
        }
    }
    let owned = Owned(pointer);
    let data = unsafe { &*owned.0 };
    ensure!(
        data.CredentialBlobSize > 0
            && data.CredentialBlobSize <= 16 * 1024
            && !data.CredentialBlob.is_null(),
        "invalid credential blob"
    );
    let bytes = unsafe {
        std::slice::from_raw_parts(data.CredentialBlob, data.CredentialBlobSize as usize)
    };
    if let Ok(secret) = serde_json::from_slice(bytes) {
        return Ok(secret);
    }
    ensure!(
        bytes.len().is_multiple_of(2) && !data.UserName.is_null(),
        "invalid Windows generic credential"
    );
    let units: Vec<_> = bytes
        .chunks_exact(2)
        .map(|b| u16::from_le_bytes([b[0], b[1]]))
        .collect();
    let password = String::from_utf16(&units)?
        .trim_end_matches('\0')
        .to_owned();
    let mut user = Vec::new();
    for i in 0..512 {
        let c = unsafe { *data.UserName.add(i) };
        if c == 0 {
            break;
        }
        user.push(c);
    }
    ensure!(user.len() < 512, "username too long");
    Ok(Secret {
        username: String::from_utf16(&user)?,
        password,
    })
}
#[cfg(target_os = "macos")]
fn credential(name: &str) -> Result<Secret> {
    use std::ffi::c_void;
    #[link(name = "Security", kind = "framework")]
    unsafe extern "C" {
        fn SecKeychainSetUserInteractionAllowed(allowed: u8) -> i32;
        fn SecKeychainFindGenericPassword(
            keychain: *const c_void,
            service_len: u32,
            service: *const u8,
            account_len: u32,
            account: *const u8,
            length: *mut u32,
            data: *mut *mut c_void,
            item: *mut *mut c_void,
        ) -> i32;
        fn SecKeychainItemFreeContent(attributes: *mut c_void, data: *mut c_void) -> i32;
    }
    let mut length = 0u32;
    let mut data = std::ptr::null_mut();
    // This isolated worker never presents Keychain UI or unlocks an account.
    ensure!(
        unsafe { SecKeychainSetUserInteractionAllowed(0) } == 0,
        "cannot disable credential interaction"
    );
    let status = unsafe {
        SecKeychainFindGenericPassword(
            std::ptr::null(),
            10,
            b"FileBackup".as_ptr(),
            name.len() as u32,
            name.as_ptr(),
            &mut length,
            &mut data,
            std::ptr::null_mut(),
        )
    };
    ensure!(
        status == 0 && !data.is_null(),
        "credential unavailable without interaction"
    );
    let result = if length <= 16 * 1024 {
        serde_json::from_slice(unsafe {
            std::slice::from_raw_parts(data.cast::<u8>(), length as usize)
        })
        .map_err(anyhow::Error::from)
    } else {
        Err(anyhow::anyhow!("oversized credential"))
    };
    unsafe {
        SecKeychainItemFreeContent(std::ptr::null_mut(), data);
    }
    result
}
#[cfg(not(any(windows, target_os = "linux", target_os = "macos")))]
fn credential(_name: &str) -> Result<Secret> {
    anyhow::bail!("host credential adapter unavailable")
}
