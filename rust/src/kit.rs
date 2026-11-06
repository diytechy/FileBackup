//! IF-009/025: independent recovery resources, sourced once from maintained files.
use crate::platform;
use anyhow::{Result, ensure};
use sha2::{Digest, Sha256};
use std::path::Path;
pub const INDEX: &str = "KIT.sha256";
pub fn members() -> impl Iterator<Item = &'static str> {
    FILES
        .iter()
        .map(|(name, _)| *name)
        .chain(std::iter::once(INDEX))
}
pub const FILES: &[(&str,&[u8])] = &[
    ("RECONSTRUCT.ps1",include_bytes!("../../recovery/Reconstruct.ps1")),
    ("reconstruct.sh",include_bytes!("../../recovery/reconstruct.sh")),
    ("reconstruct-core.sh",include_bytes!("../../bash/reconstruct.sh")),
    ("path-keys.awk",include_bytes!("../../recovery/path-keys.awk")),
    ("path-keys.tsv",include_bytes!("../../recovery/path-keys.tsv")),
    ("THIRD-PARTY-NOTICES.txt",include_bytes!("../../recovery/THIRD-PARTY-NOTICES.txt")),
    ("FileBackup.Common.psm1",include_bytes!("../../Modules/FileBackup.Common.psm1")),
    ("System.IO.Hashing.dll",include_bytes!(concat!(env!("OUT_DIR"),"/System.IO.Hashing.dll"))),
    ("RECONSTRUCT.cmd",include_bytes!("../../recovery/RECONSTRUCT.cmd")),
    ("RECONSTRUCT.command",include_bytes!("../../recovery/RECONSTRUCT.command")),
    ("RECOVERY.txt",b"Native metadata v1 / kit 17. Preserve the whole store.\nPowerShell 7: pwsh -File RECONSTRUCT.ps1 -TargetRoot TARGET -ExitCode\nBash 4+: bash reconstruct.sh --target-root /absolute/target\nBash needs gawk, xxhsum >=0.8, coreutils; compressed content needs 7-Zip and timeout.\nUse an exclusively controlled target outside the store. Recovery never needs Rust/network.\n--previous / -Previous selects .prev records explicitly; missing required metadata is reported.\nA junction may become a relative folder symlink; privileges vary. External folder aliases restore as duplicate ordinary trees.\nHash checks prove content agreement, not provenance or completeness.\n"),
];
pub fn preflight() -> Result<()> {
    ensure!(
        FILES.iter().all(|(_, bytes)| !bytes.is_empty()),
        "complete recovery kit unavailable: provision FILEBACKUP_HASH_DLL before building"
    );
    Ok(())
}
pub fn publish(folder: &Path) -> Result<()> {
    preflight()?;
    for (name, bytes) in FILES {
        platform::atomic_write(&folder.join(name), bytes, true)?;
        #[cfg(unix)]
        if name.ends_with(".sh") || name.ends_with(".command") {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(folder.join(name), std::fs::Permissions::from_mode(0o700))?;
        }
    }
    let inventory: String = FILES
        .iter()
        .map(|(name, bytes)| {
            let digest: String = Sha256::digest(bytes)
                .iter()
                .map(|b| format!("{b:02x}"))
                .collect();
            format!("{digest}  {name}\n")
        })
        .collect();
    // Commit last: an interrupted mixed kit fails its check and points to the
    // complete preserved route; it never silently executes a mixed helper set.
    platform::atomic_write(&folder.join(INDEX), inventory.as_bytes(), true)?;
    Ok(())
}
