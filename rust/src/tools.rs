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
// `progress`, when given, runs on the calling thread at most once per
// `poll_interval()`, timed with `Instant`; an error from it ends the tool.
fn invoke<T: Send + 'static>(
    cmd: &mut Command,
    timeout: Duration,
    read: impl FnOnce(ChildStdout) -> Result<T> + Send + 'static,
    mut progress: Option<&mut dyn FnMut() -> Result<()>>,
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
    let mut last_poll = start;
    let hold = if progress.is_some() {
        compress_hold()
    } else {
        Duration::ZERO
    };
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
        if let Some(poll) = progress.as_mut()
            && last_poll.elapsed() >= poll_interval()
        {
            last_poll = Instant::now();
            poll()?;
        }
        if let Some(status) = child.try_wait()?
            && start.elapsed() >= hold
        {
            break status;
        }
        if start.elapsed() >= timeout {
            return Err(expired("tool deadline exceeded"));
        }
        thread::sleep(Duration::from_millis(20));
    };
    let result = match result {
        Some(value) => value,
        None => receive
            .recv_timeout(timeout.saturating_sub(start.elapsed()))
            .map_err(|_| expired("tool output did not close before deadline"))??,
    };
    let diagnostic = receive_error
        .recv_timeout(timeout.saturating_sub(start.elapsed()))
        .map_err(|_| expired("tool diagnostics did not close before deadline"))??;
    Ok((status, result, diagnostic))
}
/// Marks a host stop as the tool running out of time, so a caller with its own
/// bound can tell it from the other stops without matching on a message.
#[derive(Debug)]
struct Expired(&'static str);
impl std::fmt::Display for Expired {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.0)
    }
}
fn expired(message: &'static str) -> anyhow::Error {
    anyhow::Error::new(crate::platform::HostStop(message)).context(Expired(message))
}
// Up to `limit` bytes of a tool's output; more is a host stop.
fn read_bounded(pipe: ChildStdout, limit: u64) -> Result<Vec<u8>> {
    let mut bytes = Vec::new();
    pipe.take(limit.saturating_add(1)).read_to_end(&mut bytes)?;
    if bytes.len() as u64 > limit {
        return Err(anyhow::Error::new(OutputLimit)
            .context(crate::platform::HostStop("tool exceeded output budget")));
    }
    Ok(bytes)
}
fn capture_output(
    cmd: &mut Command,
    limit: u64,
    timeout: Duration,
) -> Result<(ExitStatus, Vec<u8>, Vec<u8>)> {
    invoke(cmd, timeout, move |pipe| read_bounded(pipe, limit), None)
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
fn compress_command(input: &Path, archive: &Path) -> Result<Command> {
    ensure!(!archive.exists(), "compression destination already exists");
    let mut command = seven_zip_command()?;
    command
        .args([
            "a", "-t7z", "-mx=5", "-mmt=2", "-y", "-bso0", "-bsp0", "-spd", "-sae", "--",
        ])
        .arg(archive)
        .arg(input);
    Ok(command)
}
fn finish_compress(status: ExitStatus, diagnostic: &[u8], archive: &Path) -> Result<()> {
    ensure!(seven_zip_success(status, diagnostic)?, "compression failed");
    std::fs::OpenOptions::new()
        .write(true)
        .open(archive)?
        .sync_all()?;
    Ok(())
}
/// Compress `input` into `archive` under the compression ceiling and stall bound, and polling the
/// archive's size once a second into the step counter. A poll never fails a run;
/// only the stall bound can end it.
pub fn compress_counted(input: &Path, archive: &Path, counters: &Arc<Counters>) -> Result<()> {
    let mut command = compress_command(input, archive)?;
    let ceiling = compress_ceiling(std::fs::metadata(input)?.len());
    let mut stall = StallWatch::new(stall_window(), Instant::now());
    let script = scripted_sizes();
    let mut polls = 0usize;
    let mut poll = || {
        let size = if script.is_empty() {
            match std::fs::metadata(archive) {
                Ok(meta) => Some(meta.len()),
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => Some(0),
                Err(_) => None,
            }
        } else {
            let value = script[polls.min(script.len() - 1)];
            polls += 1;
            Some(value)
        };
        if let Some(size) = size {
            counters.step_set(size);
        }
        if stall.observe(size, Instant::now()) {
            return Err(crate::platform::HostStop(
                "compression stalled: the archive did not grow within the stall window",
            )
            .into());
        }
        Ok(())
    };
    let result = invoke(
        &mut command,
        ceiling,
        |pipe| read_bounded(pipe, 4096),
        Some(&mut poll),
    );
    let (status, _, diagnostic) = result.map_err(|e| {
        if e.is::<Expired>() {
            crate::platform::HostStop("compression exceeded its time ceiling (300 s + 4 s per MiB)")
                .into()
        } else {
            e
        }
    })?;
    finish_compress(status, &diagnostic, archive)
}
/// Compression is a host stop when the archive has not grown for the window.
pub struct StallWatch {
    window: Duration,
    size: u64,
    grew: Instant,
}
impl StallWatch {
    pub fn new(window: Duration, now: Instant) -> Self {
        Self {
            window,
            size: 0,
            grew: now,
        }
    }
    /// Feed a poll; `None` is a poll that could not read the size. True when the
    /// archive has not grown for the whole window.
    pub fn observe(&mut self, size: Option<u64>, now: Instant) -> bool {
        if let Some(size) = size
            && size > self.size
        {
            self.size = size;
            self.grew = now;
        }
        now.saturating_duration_since(self.grew) >= self.window
    }
}
fn compress_ceiling(length: u64) -> Duration {
    #[cfg(feature = "test-hooks")]
    if let Some(ms) = progress::test_ms("FILEBACKUP_TEST_COMPRESS_CEILING_MS") {
        return Duration::from_millis(ms);
    }
    compress_deadline(length)
}
const STALL_WINDOW: Duration = Duration::from_secs(60 * 60);
const POLL_INTERVAL: Duration = Duration::from_secs(1);
fn stall_window() -> Duration {
    #[cfg(feature = "test-hooks")]
    if let Some(ms) = progress::test_ms("FILEBACKUP_TEST_STALL_MS") {
        return Duration::from_millis(ms);
    }
    STALL_WINDOW
}
fn poll_interval() -> Duration {
    #[cfg(feature = "test-hooks")]
    if let Some(ms) = progress::test_ms("FILEBACKUP_TEST_COMPRESS_POLL_MS") {
        return Duration::from_millis(ms);
    }
    POLL_INTERVAL
}
// Test hooks: keep a finished compression running, so the poll has time to show it.
fn compress_hold() -> Duration {
    #[cfg(feature = "test-hooks")]
    if let Some(ms) = progress::test_ms("FILEBACKUP_TEST_COMPRESS_HOLD_MS") {
        return Duration::from_millis(ms);
    }
    Duration::ZERO
}
// Test hooks: a scripted archive-size source (comma-separated, the last repeats),
// because holding a real compression does not grow its archive.
fn scripted_sizes() -> Vec<u64> {
    #[cfg(feature = "test-hooks")]
    if let Ok(list) = std::env::var("FILEBACKUP_TEST_COMPRESS_SIZES") {
        return list
            .split(',')
            .filter_map(|v| v.trim().parse().ok())
            .collect();
    }
    Vec::new()
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
/// Compression only: a ceiling of 300 s plus 4 s per MiB, a floor of about 0.25 MiB/s.
pub fn compress_deadline(length: u64) -> Duration {
    Duration::from_secs(300u64.saturating_add((length / (1024 * 1024)).saturating_mul(4)))
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
    verify_form_with(path, key, counters, false)
}
/// As `verify_form_counted`, but the expanded bytes (and a raw object's hash bytes)
/// go to the step counter and never to `bytes`.
pub fn verify_form_step(
    path: &Path,
    key: &ContentKey,
    counters: &Arc<Counters>,
) -> Result<Option<StoredForm>> {
    verify_form_with(path, key, counters, true)
}
pub fn verify_step(path: &Path, key: &ContentKey, counters: &Arc<Counters>) -> Result<bool> {
    Ok(verify_form_step(path, key, counters)?.is_some())
}
fn verify_form_with(
    path: &Path,
    key: &ContentKey,
    counters: &Arc<Counters>,
    step: bool,
) -> Result<Option<StoredForm>> {
    let raw = if step {
        progress::hash_file_step
    } else {
        progress::hash_file
    };
    if std::fs::metadata(path)?.len() == key.length && raw(path, counters)? == *key {
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
            let pipe = pipe.take(expected.saturating_add(1));
            let pipe = if step {
                Reading::step(pipe, &counters)
            } else {
                Reading::new(pipe, &counters)
            };
            let actual = crate::format::copy_hash(pipe, std::io::sink())?;
            ensure!(actual.length <= expected, OutputLimit);
            Ok(actual)
        },
        None,
    );
    match result {
        Ok((status, actual, diagnostic)) => Ok((seven_zip_success(status, &diagnostic)?
            && actual == *key)
            .then_some(StoredForm::Archive)),
        Err(e) if e.is::<OutputLimit>() => Ok(None),
        Err(e) => Err(e),
    }
}
