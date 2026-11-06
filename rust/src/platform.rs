//! IF-014/015: admission, exclusion and synced publication.
use anyhow::{Context, Result, ensure};
use std::{
    fs::{self, File, OpenOptions},
    io::Write,
    path::{Component, Path, PathBuf},
};

// Implements: LLR-152. Physical existing ancestor plus lexical nonexisting tail.
pub fn resolve(path: &Path) -> Result<PathBuf> {
    ensure!(
        path.to_str()
            .is_some_and(|s| !s.chars().any(char::is_control)),
        "root contains unsupported characters"
    );
    ensure!(path.is_absolute(), "configured paths must be absolute");
    ensure!(
        !path.components().any(|c| matches!(c, Component::ParentDir)),
        "parent components are not accepted in roots"
    );
    let mut ancestor = path;
    let mut tail = Vec::new();
    while entry_metadata(ancestor)?.is_none() {
        #[cfg(windows)]
        {
            let part = ancestor
                .file_name()
                .context("unresolvable root")?
                .to_str()
                .context("non-Unicode root tail")?;
            ensure!(
                !part.ends_with([' ', '.']) && !part.contains(':'),
                "ambiguous Windows root component"
            );
        }
        tail.push(
            ancestor
                .file_name()
                .context("unresolvable root")?
                .to_os_string(),
        );
        ancestor = ancestor.parent().context("missing volume")?;
    }
    let mut resolved = fs::canonicalize(ancestor)?;
    ensure!(
        fs::metadata(&resolved)?.is_dir(),
        "configured root or existing ancestor is not a directory"
    );
    for part in tail.into_iter().rev() {
        resolved.push(part);
    }
    Ok(resolved)
}
pub fn path_identity(path: &Path) -> String {
    let text = path.to_string_lossy().replace('\\', "/");
    // Conservative across NTFS/APFS and case-insensitive mounted volumes.
    crate::format::path_key(&text)
}
pub fn entry_metadata(path: &Path) -> Result<Option<fs::Metadata>> {
    match fs::symlink_metadata(path) {
        Ok(m) => Ok(Some(m)),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(e.into()),
    }
}
pub fn overlaps(a: &Path, b: &Path) -> bool {
    let a = path_identity(a).trim_end_matches('/').to_owned();
    let b = path_identity(b).trim_end_matches('/').to_owned();
    a == b || a.starts_with(&(b.clone() + "/")) || b.starts_with(&(a + "/"))
}
pub fn ordinary_dir(path: &Path) -> Result<()> {
    let metadata = fs::symlink_metadata(path)?;
    ensure!(
        metadata.is_dir() && !is_redirect(&metadata),
        "redirected or non-directory store path: {}",
        path.display()
    );
    Ok(())
}
pub fn is_redirect(metadata: &fs::Metadata) -> bool {
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;
        metadata.file_attributes() & 0x400 != 0
    }
    #[cfg(not(windows))]
    {
        metadata.file_type().is_symlink()
    }
}
pub fn is_volume_root(path: &Path) -> bool {
    let Some(parent) = path.parent() else {
        return true;
    };
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        fs::metadata(path)
            .ok()
            .zip(fs::metadata(parent).ok())
            .is_some_and(|(a, b)| a.dev() != b.dev())
    }
    #[cfg(windows)]
    {
        use std::os::windows::ffi::OsStrExt;
        use windows_sys::Win32::Storage::FileSystem::GetVolumePathNameW;
        let _ = parent;
        let input: Vec<_> = path.as_os_str().encode_wide().chain(Some(0)).collect();
        let mut output = vec![0u16; 32768];
        // SAFETY: terminated input, writable output of the declared length.
        if unsafe { GetVolumePathNameW(input.as_ptr(), output.as_mut_ptr(), output.len() as u32) }
            == 0
        {
            return false;
        }
        let n = output.iter().position(|v| *v == 0).unwrap_or(output.len());
        let volume = PathBuf::from(String::from_utf16_lossy(&output[..n]));
        fs::canonicalize(volume).is_ok_and(|p| path_identity(&p) == path_identity(path))
    }
}
// Implements: LLR-155. Windows sharing exclusion also interoperates with the existing engine.
pub struct StoreLock {
    _file: File,
}
impl StoreLock {
    pub fn acquire(root: &Path) -> Result<Self> {
        ordinary_dir(root)?;
        let path = root.join("Temp.lock");
        if let Some(metadata) = entry_metadata(&path)? {
            ensure!(
                metadata.is_file() && !is_redirect(&metadata),
                "redirected lock"
            );
        }
        let mut opts = OpenOptions::new();
        opts.read(true).write(true).create(true).truncate(false);
        #[cfg(windows)]
        {
            use std::os::windows::fs::OpenOptionsExt;
            opts.share_mode(0).custom_flags(0x00200000); // FILE_FLAG_OPEN_REPARSE_POINT
        }
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            opts.custom_flags(libc::O_NOFOLLOW);
        }
        let file = opts.open(path).context("store busy or lock unavailable")?;
        let metadata = file.metadata()?;
        ensure!(
            metadata.is_file() && !is_redirect(&metadata),
            "redirected or non-file lock"
        );
        file.try_lock().context("store busy or lock unavailable")?;
        Ok(Self { _file: file })
    }
}
pub fn sync_directory(path: &Path) -> Result<()> {
    #[cfg(unix)]
    {
        File::open(path)?.sync_all()?;
    }
    #[cfg(not(unix))]
    {
        let _ = path;
    }
    Ok(())
}
// Implements: LLR-165/166. tempfile persist uses host rename/replace semantics.
pub fn atomic_write(path: &Path, bytes: &[u8], replace: bool) -> Result<()> {
    atomic_write_with(path, replace, |file| Ok(file.write_all(bytes)?))
}
/// Stream into the same atomic publication protocol used by byte-slice callers.
pub fn atomic_write_with(
    path: &Path,
    replace: bool,
    write: impl FnOnce(&mut File) -> Result<()>,
) -> Result<()> {
    let parent = path.parent().context("publication without parent")?;
    ordinary_dir(parent)?;
    if let Some(metadata) = entry_metadata(path)? {
        ensure!(
            metadata.is_file() && !is_redirect(&metadata),
            "redirected publication target"
        );
    }
    let mut tmp = tempfile::NamedTempFile::new_in(parent)?;
    write(tmp.as_file_mut())?;
    #[cfg(unix)]
    if let Some(metadata) = entry_metadata(path)? {
        tmp.as_file().set_permissions(metadata.permissions())?;
    }
    // New metadata is private (0600 on Unix); the backup owner runs the carried kit.
    tmp.as_file().sync_all()?;
    #[cfg(unix)]
    {
        if replace {
            tmp.persist(path)?;
        } else {
            tmp.persist_noclobber(path)?;
        }
        sync_directory(parent).context(
            "metadata is published but directory durability is unknown; re-read before retry",
        )?;
    }
    #[cfg(windows)]
    {
        use std::os::windows::ffi::OsStrExt;
        use windows_sys::Win32::Storage::FileSystem::{
            MOVEFILE_REPLACE_EXISTING, MOVEFILE_WRITE_THROUGH, MoveFileExW,
        };
        let temporary = tmp.into_temp_path();
        let source: Vec<_> = temporary.as_os_str().encode_wide().chain(Some(0)).collect();
        let destination: Vec<_> = path.as_os_str().encode_wide().chain(Some(0)).collect();
        let flags = MOVEFILE_WRITE_THROUGH
            | if replace {
                MOVEFILE_REPLACE_EXISTING
            } else {
                0
            };
        // SAFETY: both buffers are NUL-terminated Windows paths, alive for the synchronous call.
        if unsafe { MoveFileExW(source.as_ptr(), destination.as_ptr(), flags) } == 0 {
            return Err(std::io::Error::last_os_error().into());
        }
    }
    Ok(())
}
pub fn preserve(path: &Path, previous: &Path) -> Result<()> {
    if let Some(metadata) = entry_metadata(previous)? {
        ensure!(
            metadata.is_file() && !is_redirect(&metadata),
            "redirected previous definition"
        );
        return Ok(());
    }
    let bytes = fs::read(path)?;
    atomic_write(previous, &bytes, false)
}
pub fn available(path: &Path) -> Option<u64> {
    fs2::available_space(path).ok()
}
pub fn assert_same_store_mount(root: &Path, current: &Path, history: &Path) -> Result<()> {
    let probe = tempfile::Builder::new()
        .prefix(".mount-probe-")
        .tempdir_in(root)?;
    for folder in [current, history] {
        ordinary_dir(folder)?;
        let target = folder.join(probe.path().file_name().unwrap());
        ensure!(entry_metadata(&target)?.is_none(), "mount probe collision");
        fs::rename(probe.path(), &target)
            .context("store folders must share rename-compatible storage")?;
        fs::rename(&target, probe.path()).context("mount probe could not return")?;
    }
    Ok(())
}
#[derive(Debug)]
pub struct HostStop(pub &'static str);
impl std::fmt::Display for HostStop {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.0)
    }
}
impl std::error::Error for HostStop {}
pub fn is_host_stop(error: &anyhow::Error) -> bool {
    // Typed anyhow context is not necessarily a separate std::error::Error source.
    error.is::<HostStop>()
        || error.chain().any(|e| {
            e.is::<HostStop>()
                || e.downcast_ref::<std::io::Error>().is_some_and(|io| {
                    #[cfg(windows)]
                    let disk_full = matches!(io.raw_os_error(), Some(39 | 112));
                    #[cfg(unix)]
                    let disk_full = matches!(io.raw_os_error(), Some(libc::ENOSPC | libc::EDQUOT));
                    disk_full
                        || matches!(
                            io.kind(),
                            std::io::ErrorKind::NotConnected | std::io::ErrorKind::BrokenPipe
                        )
                })
        })
}
/// Fault injection is absent from release/default builds.
pub fn checkpoint(_name: &str) {
    #[cfg(feature = "test-hooks")]
    if std::env::var("FILEBACKUP_TEST_TRACE").ok().as_deref() == Some("1") {
        eprintln!("Test phase: {_name}");
        #[cfg(target_os = "linux")]
        if let Ok(status) = fs::read_to_string("/proc/self/status") {
            for line in status
                .lines()
                .filter(|s| s.starts_with("VmRSS:") || s.starts_with("VmHWM:"))
            {
                eprintln!("Test memory: {_name} {line}");
            }
        }
    }
    #[cfg(feature = "test-hooks")]
    if std::env::var("FILEBACKUP_TEST_PAUSE").ok().as_deref() == Some(_name) {
        if let Ok(signal) = std::env::var("FILEBACKUP_TEST_SIGNAL") {
            fs::write(signal, _name).expect("test signal");
        }
        loop {
            std::thread::park_timeout(std::time::Duration::from_secs(1));
        }
    }
}
