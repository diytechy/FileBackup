//! IF-016: packaged 7-Zip and bounded optional tools; no shell interpolation.
use crate::{
    format::ContentKey,
    progress::{self, Counters, Reading},
};
use anyhow::{Context, Result, ensure};
use std::{
    fs::File,
    io::Read,
    path::{Path, PathBuf},
    process::{Child, ChildStdout, Command, ExitStatus, Stdio},
    sync::{Arc, mpsc},
    thread,
    time::{Duration, Instant},
};
// Own the tool's process group/job so inherited output pipes cannot defeat the
// deadline. A successful direct child may still have left descendants behind.
struct ToolChild {
    child: Option<Child>,
    #[cfg(windows)]
    _job: std::os::windows::io::OwnedHandle,
}
impl std::ops::Deref for ToolChild {
    type Target = Child;
    fn deref(&self) -> &Child {
        self.child.as_ref().unwrap()
    }
}
impl std::ops::DerefMut for ToolChild {
    fn deref_mut(&mut self) -> &mut Child {
        self.child.as_mut().unwrap()
    }
}
impl ToolChild {
    fn spawn(command: &mut Command) -> Result<Self> {
        #[cfg(unix)]
        {
            use std::os::unix::process::CommandExt;
            command.process_group(0);
        }
        #[cfg(windows)]
        let job = {
            use std::os::windows::io::{AsRawHandle, FromRawHandle, OwnedHandle};
            use windows_sys::Win32::System::JobObjects::*;
            let raw = unsafe { CreateJobObjectW(std::ptr::null(), std::ptr::null()) };
            ensure!(
                !raw.is_null(),
                crate::platform::HostStop("cannot create tool lifetime job")
            );
            // SAFETY: successful CreateJobObjectW transfers one owned handle.
            let job = unsafe { OwnedHandle::from_raw_handle(raw) };
            let mut limits: JOBOBJECT_EXTENDED_LIMIT_INFORMATION = unsafe { std::mem::zeroed() };
            limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
            ensure!(
                unsafe {
                    SetInformationJobObject(
                        job.as_raw_handle(),
                        JobObjectExtendedLimitInformation,
                        (&limits as *const JOBOBJECT_EXTENDED_LIMIT_INFORMATION).cast(),
                        std::mem::size_of_val(&limits) as u32,
                    )
                } != 0,
                crate::platform::HostStop("cannot constrain tool lifetime")
            );
            job
        };
        let child = command
            .spawn()
            .map_err(|_| crate::platform::HostStop("tool could not start"))?;
        #[cfg(windows)]
        {
            use std::os::windows::io::AsRawHandle;
            if unsafe {
                windows_sys::Win32::System::JobObjects::AssignProcessToJobObject(
                    job.as_raw_handle(),
                    child.as_raw_handle(),
                )
            } == 0
            {
                let mut child = child;
                let _ = child.kill();
                std::thread::spawn(move || {
                    let _ = child.wait();
                });
                return Err(crate::platform::HostStop("cannot own tool process tree").into());
            }
        }
        Ok(Self {
            child: Some(child),
            #[cfg(windows)]
            _job: job,
        })
    }
}
impl Drop for ToolChild {
    fn drop(&mut self) {
        if let Some(mut child) = self.child.take() {
            #[cfg(unix)]
            unsafe {
                libc::kill(-(child.id() as i32), libc::SIGKILL);
            }
            // The Windows job handle closes after this body, killing its descendants.
            if !matches!(child.try_wait(), Ok(Some(_))) {
                let _ = child.kill();
                thread::spawn(move || {
                    let _ = child.wait();
                });
            }
        }
    }
}
// One lifetime/deadline implementation for bounded text output and streamed hashes.
fn invoke<T: Send + 'static>(
    cmd: &mut Command,
    timeout: Duration,
    read: impl FnOnce(ChildStdout) -> Result<T> + Send + 'static,
) -> Result<(ExitStatus, T, Vec<u8>)> {
    let mut child = ToolChild::spawn(
        cmd.stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped()),
    )?;
    let stdout = child.stdout.take().context("missing output pipe")?;
    let mut stderr = child.stderr.take().context("missing diagnostic pipe")?;
    let (send, receive) = mpsc::sync_channel(1);
    thread::spawn(move || {
        let _ = send.send(read(stdout));
    });
    let (send_error, receive_error) = mpsc::sync_channel(1);
    thread::spawn(move || {
        let mut bytes = Vec::new();
        let result: std::io::Result<Vec<u8>> = (|| {
            stderr.by_ref().take(8192).read_to_end(&mut bytes)?;
            std::io::copy(&mut stderr, &mut std::io::sink())?;
            Ok(bytes)
        })();
        let _ = send_error.send(result);
    });
    let start = Instant::now();
    let mut result = None;
    let status = loop {
        if result.is_none() {
            match receive.try_recv() {
                Ok(value) => result = Some(value?), // A limit violation kills the child immediately.
                Err(mpsc::TryRecvError::Empty) => (),
                Err(mpsc::TryRecvError::Disconnected) => {
                    return Err(crate::platform::HostStop("tool reader unavailable").into());
                }
            }
        }
        if let Some(status) = child.try_wait()? {
            break status;
        }
        if start.elapsed() >= timeout {
            return Err(crate::platform::HostStop("tool deadline exceeded").into());
        }
        thread::sleep(Duration::from_millis(20));
    };
    let result = match result {
        Some(value) => value,
        None => receive
            .recv_timeout(timeout.saturating_sub(start.elapsed()))
            .map_err(|_| {
                crate::platform::HostStop("tool output did not close before deadline")
            })??,
    };
    let diagnostic = receive_error
        .recv_timeout(timeout.saturating_sub(start.elapsed()))
        .map_err(|_| {
            crate::platform::HostStop("tool diagnostics did not close before deadline")
        })??;
    Ok((status, result, diagnostic))
}
fn capture_output(
    cmd: &mut Command,
    limit: u64,
    timeout: Duration,
) -> Result<(ExitStatus, Vec<u8>, Vec<u8>)> {
    invoke(cmd, timeout, move |pipe| {
        let mut bytes = Vec::new();
        pipe.take(limit.saturating_add(1)).read_to_end(&mut bytes)?;
        if bytes.len() as u64 > limit {
            return Err(anyhow::Error::new(OutputLimit)
                .context(crate::platform::HostStop("tool exceeded output budget")));
        }
        Ok(bytes)
    })
}
pub fn output(cmd: &mut Command, limit: u64, timeout: Duration) -> Result<Vec<u8>> {
    let (status, bytes, _) = capture_output(cmd, limit, timeout)?;
    ensure!(status.success(), "tool exited unsuccessfully: {status}");
    Ok(bytes)
}
pub fn parse_media_rate(length: u64, duration: &str) -> Option<String> {
    let seconds: f64 = duration.trim().parse().ok()?;
    if !seconds.is_finite() || seconds <= 0.0 {
        return None;
    }
    Some(format!(
        "{:.3}",
        length as f64 / (1024.0 * 1024.0) / seconds
    ))
}
pub fn media_rate(
    tool: Option<&Path>,
    path: &Path,
    name: &str,
    length: u64,
) -> Result<Option<String>> {
    let Some(tool) = tool else {
        return Ok(None);
    };
    let ext = crate::format::lower_extension(name);
    if ![
        "mp4", "mkv", "mov", "avi", "wmv", "m4v", "mp3", "flac", "wav", "ogg", "m4a", "webm",
    ]
    .contains(&ext.as_str())
    {
        return Ok(None);
    }
    let bytes = output(
        Command::new(tool)
            .args([
                "-v",
                "error",
                "-show_entries",
                "format=duration",
                "-of",
                "csv=p=0",
                "-i",
            ])
            .arg(path),
        4096,
        Duration::from_secs(20),
    )?;
    let duration = std::str::from_utf8(&bytes)?;
    Ok(Some(
        parse_media_rate(length, duration).context("media duration unavailable or nonpositive")?,
    ))
}
pub fn bundled_seven_zip() -> Result<PathBuf> {
    let executable = std::env::current_exe()?;
    let directory = executable
        .parent()
        .context("executable directory unavailable")?;
    #[cfg(feature = "test-hooks")]
    let directory = if directory.file_name() == Some(std::ffi::OsStr::new("deps")) {
        directory
            .parent()
            .context("Cargo output directory unavailable")?
    } else {
        directory
    };
    let name = if cfg!(windows) { "7za.exe" } else { "7zz" };
    let path = directory.join("tools").join("7zip").join(name);
    ensure!(
        path.is_file(),
        crate::platform::HostStop(
            "bundled 7-Zip missing; extract the complete FileBackup package including tools/7zip"
        )
    );
    Ok(path)
}
fn seven_zip_command() -> Result<Command> {
    Ok(Command::new(bundled_seven_zip()?))
}
// Only explicit corruption diagnostics establish damage. Unsupported formats,
// password requirements, allocation failures and OS errors remain unavailable.
fn seven_zip_success(status: ExitStatus, diagnostic: &[u8]) -> Result<bool> {
    if status.success() {
        return Ok(true);
    }
    let message = String::from_utf8_lossy(diagnostic).to_lowercase();
    if status.code() == Some(2)
        && !["wrong password", "unsupported method"]
            .iter()
            .any(|text| message.contains(text))
        && message.lines().any(|line| {
            let line = line.trim();
            matches!(
                line,
                "data error"
                    | "crc failed"
                    | "headers error"
                    | "unexpected end of archive"
                    | "is not archive"
                    | "unavailable data"
            ) || [
                "error: data error",
                "error: crc failed",
                "error: headers error",
                "error: unexpected end",
                "error: unavailable data",
            ]
            .iter()
            .any(|prefix| line.starts_with(prefix))
        })
    {
        return Ok(false);
    }
    Err(anyhow::Error::new(crate::platform::HostStop(
        "bundled 7-Zip could not complete the operation",
    ))
    .context(message))
}
pub fn preflight() -> Result<()> {
    let (status, _, diagnostic) = capture_output(
        seven_zip_command()?.arg("i"),
        256 * 1024,
        Duration::from_secs(10),
    )?;
    ensure!(
        seven_zip_success(status, &diagnostic)?,
        "bundled 7-Zip preflight failed"
    );
    Ok(())
}
pub fn compress(input: &Path, archive: &Path) -> Result<()> {
    ensure!(!archive.exists(), "compression destination already exists");
    let (status, _, diagnostic) = capture_output(
        seven_zip_command()?
            .args([
                "a", "-t7z", "-mx=5", "-mmt=2", "-y", "-bso0", "-bsp0", "-spd", "-sae", "--",
            ])
            .arg(archive)
            .arg(input),
        4096,
        deadline(std::fs::metadata(input)?.len()),
    )?;
    ensure!(
        seven_zip_success(status, &diagnostic)?,
        "compression failed"
    );
    std::fs::OpenOptions::new()
        .write(true)
        .open(archive)?
        .sync_all()?;
    Ok(())
}
#[derive(Debug)]
struct OutputLimit;
impl std::fmt::Display for OutputLimit {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("stored object output exceeds expected limits")
    }
}
impl std::error::Error for OutputLimit {}
// A finite allowance that grows with bytes, including slow external disks.
pub fn deadline(length: u64) -> Duration {
    Duration::from_secs(300u64.saturating_add(length / (1024 * 1024)))
}
pub fn is_archive(path: &Path) -> Result<bool> {
    let mut f = File::open(path)?;
    let mut signature = [0u8; 6];
    let n = f.read(&mut signature)?;
    Ok(n == 6 && signature == [0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c])
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum StoredForm {
    Raw,
    Archive,
}
/// What an object's stored size and signature say it is, reading no content.
pub fn listed_form(path: &Path, stored: u64, length: u64) -> Option<StoredForm> {
    if stored == length {
        Some(StoredForm::Raw)
    } else if stored > 0 && is_archive(path).unwrap_or(false) {
        Some(StoredForm::Archive)
    } else {
        None
    }
}
pub fn verify(path: &Path, key: &ContentKey) -> Result<bool> {
    Ok(verify_form(path, key)?.is_some())
}
pub fn verify_form(path: &Path, key: &ContentKey) -> Result<Option<StoredForm>> {
    verify_form_counted(path, key, &Arc::default())
}
/// As `verify_form`, counting the bytes read: stored bytes for a raw object,
/// expanded bytes for an archive.
pub fn verify_form_counted(
    path: &Path,
    key: &ContentKey,
    counters: &Arc<Counters>,
) -> Result<Option<StoredForm>> {
    if std::fs::metadata(path)?.len() == key.length && progress::hash_file(path, counters)? == *key
    {
        return Ok(Some(StoredForm::Raw));
    }
    if !is_archive(path)? {
        return Ok(None);
    }
    let (status, listing, diagnostic) = match capture_output(
        seven_zip_command()?
            .args(["l", "-slt", "-ba", "-sccUTF-8", "-t7z", "-p-", "-spd", "--"])
            .arg(path),
        32 * 1024,
        deadline(key.length),
    ) {
        Ok(result) => result,
        Err(e) if e.is::<OutputLimit>() => return Ok(None),
        Err(e) => return Err(e),
    };
    if !seven_zip_success(status, &diagnostic)? {
        return Ok(None);
    }
    let listing = String::from_utf8_lossy(&listing);
    let sizes: Vec<_> = listing
        .lines()
        .filter_map(|line| line.strip_prefix("Size = "))
        .collect();
    if sizes.len() != 1
        || sizes[0].trim().parse::<u64>().ok() != Some(key.length)
        || listing
            .lines()
            .any(|line| line.starts_with("Attributes = D") || line == "Folder = +")
    {
        return Ok(None);
    }
    ensure!(
        !listing.lines().any(|line| line == "Encrypted = +"),
        crate::platform::HostStop("encrypted stored object is unsupported")
    );
    let expected = key.length;
    let counters = counters.clone();
    let result = invoke(
        seven_zip_command()?
            .args(["e", "-so", "-t7z", "-mmt=2", "-p-", "-spd", "--"])
            .arg(path),
        deadline(expected),
        move |pipe| {
            let pipe = Reading::new(pipe.take(expected.saturating_add(1)), &counters);
            let actual = crate::format::copy_hash(pipe, std::io::sink())?;
            ensure!(actual.length <= expected, OutputLimit);
            Ok(actual)
        },
    );
    match result {
        Ok((status, actual, diagnostic)) => Ok((seven_zip_success(status, &diagnostic)?
            && actual == *key)
            .then_some(StoredForm::Archive)),
        Err(e) if e.is::<OutputLimit>() => Ok(None),
        Err(e) => Err(e),
    }
}
