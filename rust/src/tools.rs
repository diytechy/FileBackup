//! IF-016: direct bounded subprocess adapters; no shell interpolation.
use crate::format::{ContentKey, hash_file};
use anyhow::{Context, Result, ensure};
use std::{
    fs::{File, OpenOptions},
    io::Read,
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
    sync::mpsc,
    thread,
    time::{Duration, Instant},
};
pub struct Adapters {
    pub seven_zip: Option<PathBuf>,
    pub ffprobe: Option<PathBuf>,
}
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
pub fn seven_zip(configured: Option<&Path>) -> Result<PathBuf> {
    let candidates = if let Some(p) = configured {
        vec![p.to_path_buf()]
    } else {
        let c = vec![
            PathBuf::from("7z"),
            PathBuf::from("7zz"),
            PathBuf::from("7za"),
        ];
        #[cfg(windows)]
        let c = {
            let mut c = c;
            c.push(PathBuf::from("C:/Program Files/7-Zip/7z.exe"));
            c
        };
        c
    };
    for path in candidates {
        if run(Command::new(&path).arg("i"), Duration::from_secs(10)).is_ok() {
            return Ok(path);
        }
    }
    Err(crate::platform::HostStop(
        "required 7-Zip unavailable; provision it locally or disable new compression",
    )
    .into())
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
pub fn compress(tool: &Path, input: &Path, archive: &Path) -> Result<()> {
    run(
        Command::new(tool)
            .args(["a", "-t7z", "-mx=5", TOOL_THREADS, "-y", "--"])
            .arg(archive)
            .arg(input),
        deadline(std::fs::metadata(input)?.len()),
    )?;
    OpenOptions::new().write(true).open(archive)?.sync_all()?;
    Ok(())
}
// Leave memory for the live file/object indexes instead of letting 7-Zip select
// a separate compression/decompression buffer set for every host CPU.
const TOOL_THREADS: &str = "-mmt=2";
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
pub fn verify(path: &Path, key: &ContentKey, tool: Option<&Path>, scratch: &Path) -> Result<bool> {
    Ok(verify_form(path, key, tool, scratch)?.is_some())
}
pub fn verify_form(
    path: &Path,
    key: &ContentKey,
    tool: Option<&Path>,
    _scratch: &Path,
) -> Result<Option<StoredForm>> {
    if std::fs::metadata(path)?.len() == key.length && hash_file(path)? == *key {
        return Ok(Some(StoredForm::Raw));
    }
    if !is_archive(path)? {
        return Ok(None);
    }
    let discovered;
    let tool = if let Some(tool) = tool {
        tool
    } else {
        discovered = seven_zip(None).context("compressed candidate requires local 7-Zip")?;
        &discovered
    };
    let mut child = ToolChild::spawn(
        Command::new(tool)
            .args(["e", "-so", TOOL_THREADS, "-y", "--"])
            .arg(path)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::null()),
    )?;
    let stdout = child.stdout.take().context("missing extractor pipe")?;
    // Reader holds only bounded chunks and stops after the expected bytes plus one.
    let expected = key.length;
    let (send, receive) = mpsc::sync_channel(1);
    thread::spawn(move || {
        let _ = send.send(crate::format::copy_hash(
            stdout.take(expected.saturating_add(1)),
            std::io::sink(),
        ));
    });
    let start = Instant::now();
    let status = loop {
        if start.elapsed() > deadline(key.length) {
            return Err(crate::platform::HostStop(
                "extractor deadline exceeded; content verdict unavailable",
            )
            .into());
        }
        if let Some(status) = child.try_wait()? {
            break status;
        }
        thread::sleep(Duration::from_millis(20));
    };
    let actual = receive
        .recv_timeout(deadline(key.length).saturating_sub(start.elapsed()))
        .map_err(|_| {
            crate::platform::HostStop("extractor output did not close before deadline")
        })??;
    Ok((status.success() && actual == *key).then_some(StoredForm::Archive))
}
