//! IF-016: built-in 7z codec and bounded optional tools; no shell interpolation.
use crate::format::{ContentKey, hash_file};
use anyhow::{Context, Result, ensure};
use std::{
    fs::File,
    io::Read,
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
    sync::mpsc,
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
pub fn output(cmd: &mut Command, limit: u64, timeout: Duration) -> Result<Vec<u8>> {
    let mut child = ToolChild::spawn(
        cmd.stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::null()),
    )?;
    let pipe = child.stdout.take().context("missing output pipe")?;
    let (send, receive) = mpsc::sync_channel(1);
    thread::spawn(move || {
        let mut bytes = Vec::new();
        let result = pipe
            .take(limit.saturating_add(1))
            .read_to_end(&mut bytes)
            .map(|_| bytes);
        let _ = send.send(result);
    });
    let start = Instant::now();
    let status = loop {
        if let Some(status) = child.try_wait()? {
            break status;
        }
        if start.elapsed() >= timeout {
            return Err(crate::platform::HostStop("tool deadline exceeded").into());
        }
        thread::sleep(Duration::from_millis(20));
    };
    let bytes = receive
        .recv_timeout(timeout.saturating_sub(start.elapsed()))
        .map_err(|_| crate::platform::HostStop("tool output did not close before deadline"))??;
    ensure!(
        status.success() && bytes.len() as u64 <= limit,
        "tool failed or exceeded output budget"
    );
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
    let ext = Path::new(name)
        .extension()
        .and_then(|v| v.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();
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
pub fn run(cmd: &mut Command, timeout: Duration) -> Result<()> {
    let mut child = ToolChild::spawn(
        cmd.stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null()),
    )?;
    let start = Instant::now();
    loop {
        if let Some(status) = child.try_wait()? {
            ensure!(status.success(), "tool exited unsuccessfully: {status}");
            return Ok(());
        }
        if start.elapsed() >= timeout {
            return Err(crate::platform::HostStop("tool deadline exceeded").into());
        }
        thread::sleep(Duration::from_millis(20));
    }
}
// Reuse the executable and existing process deadline/cleanup rather than requiring
// an installed compressor or leaving an uninterruptible codec thread in the engine.
fn codec_command() -> Result<Command> {
    let executable = std::env::current_exe()?;
    #[cfg(feature = "test-hooks")]
    let executable =
        if executable.parent().and_then(Path::file_name) == Some(std::ffi::OsStr::new("deps")) {
            // Cargo integration tests call the library from a test harness. Cargo also
            // builds the actual CLI alongside deps; exercise its real worker route.
            executable
                .parent()
                .unwrap()
                .parent()
                .unwrap()
                .join(format!("filebackup{}", std::env::consts::EXE_SUFFIX))
        } else {
            executable
        };
    let mut command = Command::new(executable);
    command.arg("__codec_worker");
    Ok(command)
}
fn codec_result(command: &mut Command, length: u64) -> Result<Option<ContentKey>> {
    let bytes = output(command, 4096, deadline(length))?;
    let result: std::result::Result<Option<ContentKey>, String> = serde_json::from_slice(&bytes)?;
    result.map_err(|message| {
        anyhow::Error::new(crate::platform::HostStop("codec unavailable")).context(message)
    })
}
pub fn compress(input: &Path, archive: &Path) -> Result<()> {
    codec_result(
        codec_command()?.arg("compress").arg(input).arg(archive),
        std::fs::metadata(input)?.len(),
    )?;
    Ok(())
}
// Internal entry point: only the parent-facing result is written to stdout.
// Verification streams into a hash, never to archive-supplied filesystem paths.
pub fn codec_worker() -> i32 {
    let result = (|| -> Result<Option<ContentKey>> {
        let mut args = std::env::args_os().skip(2);
        let operation = args.next().context("missing codec operation")?;
        let input = PathBuf::from(args.next().context("missing codec input")?);
        let argument = args.next().context("missing codec argument")?;
        ensure!(args.next().is_none(), "unexpected codec argument");
        if operation == "compress" {
            use sevenz_rust2::{ArchiveEntry, ArchiveWriter, encoder_options::Lzma2Options};
            let source = File::open(&input)?;
            let length = source.metadata()?.len();
            // Match 7-Zip 24.09 -mx=5's 32 MiB default dictionary and allow
            // two encoder workers. This library parallelizes independent chunks,
            // not the match-finder pipeline used by 7-Zip's -mmt=2.
            const DICTIONARY: u64 = 32 * 1024 * 1024;
            const CHUNK: u64 = 4 * DICTIONARY;
            let mut options = if length > CHUNK {
                Lzma2Options::from_level_mt(5, 2, CHUNK)
            } else {
                // A single chunk cannot use the second worker; stream it directly.
                Lzma2Options::from_level(5)
            };
            // Like 7-Zip, reduce the dictionary for inputs below its default.
            // LZMA2's header must represent the encoder's complete window.
            options.set_dictionary_size(length.clamp(4096, DICTIONARY).next_power_of_two() as u32);
            let destination = std::fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(PathBuf::from(argument))?;
            let mut writer = ArchiveWriter::new(destination)?;
            writer.set_content_methods(vec![options.into()]);
            writer.push_archive_entry(
                ArchiveEntry::from_path(&input, "content".into()),
                Some(source),
            )?;
            writer.finish()?.sync_all()?;
            Ok(None)
        } else {
            ensure!(operation == "verify", "unknown codec operation");
            let expected: u64 = argument.to_str().context("invalid length")?.parse()?;
            let source = File::open(&input)?;
            match decode_key(source, expected) {
                Ok(key) => Ok(key),
                // Short/corrupt streams are content damage, not a host outage.
                Err(e) => classify_decode_error(e),
            }
        }
    })()
    .map_err(|e| format!("{e:#}").chars().take(1024).collect::<String>());
    match serde_json::to_writer(std::io::stdout(), &result) {
        Ok(()) => 0,
        Err(_) => 4,
    }
}
fn classify_decode_error(error: sevenz_rust2::Error) -> Result<Option<ContentKey>> {
    use sevenz_rust2::Error;
    match error {
        Error::Io(e, _) => {
            let crc_mismatch = matches!(
                e.get_ref().and_then(|inner| inner.downcast_ref::<Error>()),
                Some(Error::ChecksumVerificationFailed)
            );
            if crc_mismatch
                || matches!(
                    e.kind(),
                    std::io::ErrorKind::InvalidData
                        | std::io::ErrorKind::InvalidInput
                        | std::io::ErrorKind::UnexpectedEof
                )
            {
                Ok(None)
            } else {
                Err(e.into())
            }
        }
        // An unavailable decoder is not evidence that stored bytes are damaged.
        e @ (Error::UnsupportedCompressionMethod(_)
        | Error::Unsupported(_)
        | Error::UnsupportedVersion { .. }
        | Error::ExternalUnsupported
        | Error::PasswordRequired
        | Error::MaxMemLimited { .. }
        | Error::FileOpen(_, _)) => Err(e.into()),
        _ => Ok(None),
    }
}
fn decode_key(
    source: File,
    expected: u64,
) -> std::result::Result<Option<ContentKey>, sevenz_rust2::Error> {
    use sevenz_rust2::{ArchiveReader, Password};
    let mut reader = ArchiveReader::new(source, Password::empty())?;
    reader.set_thread_count(1);
    let files = &reader.archive().files;
    if files.len() != 1 || files[0].is_directory || files[0].size != expected {
        return Ok(None);
    }
    let mut key = None;
    reader.for_each_entries(|_, content| {
        key = Some(
            crate::format::copy_hash(content.take(expected.saturating_add(1)), std::io::sink())
                .map_err(|e| {
                    sevenz_rust2::Error::from(
                        e.downcast::<std::io::Error>()
                            .unwrap_or_else(std::io::Error::other),
                    )
                })?,
        );
        Ok(true)
    })?;
    Ok(key.filter(|key| key.length == expected))
}
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
pub fn verify(path: &Path, key: &ContentKey) -> Result<bool> {
    Ok(verify_form(path, key)?.is_some())
}
pub fn verify_form(path: &Path, key: &ContentKey) -> Result<Option<StoredForm>> {
    if std::fs::metadata(path)?.len() == key.length && hash_file(path)? == *key {
        return Ok(Some(StoredForm::Raw));
    }
    if !is_archive(path)? {
        return Ok(None);
    }
    let actual = codec_result(
        codec_command()?
            .arg("verify")
            .arg(path)
            .arg(key.length.to_string()),
        key.length,
    )?;
    Ok((actual == Some(*key)).then_some(StoredForm::Archive))
}
