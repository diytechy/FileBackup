//! IF-007/008: one immutable pool, bounded metadata publication.
use crate::{
    format::{self, ContentKey, DirectoryRow, FileRow},
    kit, platform,
};
use anyhow::{Context, Result, ensure};
use chrono::{DateTime, Duration, NaiveDateTime, Utc};
use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
    sync::Arc,
};
#[derive(Clone, Debug)]
pub struct Object {
    pub path: PathBuf,
    pub state: Arc<Path>,
    pub name: String,
    pub key: ContentKey,
    pub verified: Option<crate::tools::StoredForm>,
}
/// A file any state folder may hold, stored objects aside.
pub fn is_state_file(name: &std::ffi::OsStr) -> bool {
    name == format::MANIFEST
        || name == format::DIRECTORIES
        || name == format::STATE
        || kit::members().any(|k| name == k)
}
/// Most identities have one supply. Avoid reserving four large Object slots for
/// every key; retain a growable list for the duplicate candidates readers support.
pub fn index_object(index: &mut BTreeMap<ContentKey, Vec<Object>>, object: Object) {
    index
        .entry(object.key)
        .or_insert_with(|| Vec::with_capacity(1))
        .push(object);
}
#[derive(Clone, Debug)]
pub struct Store {
    pub root: PathBuf,
    pub current: Arc<Path>,
    pub history: PathBuf,
}
impl Store {
    pub fn new(root: &Path) -> Self {
        Self {
            root: root.into(),
            current: root.join("CurrentBackup").into(),
            history: root.join("BackupHistory"),
        }
    }
    pub fn admit(&self) -> Result<bool> {
        if !self.root.try_exists()? {
            return Ok(true);
        }
        platform::ordinary_dir(&self.root)?;
        if !self.current.try_exists()? {
            for entry in fs::read_dir(&self.root)? {
                let entry = entry?;
                let name = entry.file_name();
                if name == "Temp.lock" {
                    continue;
                }
                if name.to_string_lossy().starts_with("Initializing_") {
                    platform::ordinary_dir(&entry.path())?;
                    ensure!(
                        fs::read_dir(entry.path())?.all(|e| e.is_ok_and(|e| {
                            let n = e.file_name();
                            is_state_file(&n) || n.to_string_lossy().starts_with(".tmp")
                        })),
                        "unknown initialization residue"
                    );
                    continue;
                }
                if name == "BackupHistory" && fs::read_dir(entry.path())?.next().is_none() {
                    platform::ordinary_dir(&entry.path())?;
                    continue;
                }
                anyhow::bail!(
                    "store is nonempty without CurrentBackup; retain its old kit or choose a new empty StorePath"
                );
            }
            return Ok(true);
        }
        platform::ordinary_dir(&self.current)?;
        platform::ordinary_dir(&self.history)?;
        format::read_manifest(&self.current.join(format::MANIFEST))?;
        format::read_directories(&self.current.join(format::DIRECTORIES))
            .context("native metadata v1 required; old stores keep their own kits")?;
        Ok(false)
    }
    pub fn initialize(&self) -> Result<()> {
        fs::create_dir_all(&self.root)?;
        fs::create_dir_all(&self.history)?;
        // Publish a fully initialized directory. An interrupted first run must
        // not strand an empty CurrentBackup that looks like damaged history.
        let staged = platform::store_temp_dir("Initializing_", &self.root)?;
        kit::publish(staged.path())?;
        platform::atomic_write(
            &staged.path().join(format::MANIFEST),
            &format::manifest_bytes(&[])?,
            false,
        )?;
        platform::atomic_write(
            &staged.path().join(format::DIRECTORIES),
            &format::directory_bytes(&[])?,
            false,
        )?;
        // A first run hashes everything it captures, so the schedule starts here.
        // Without this, a killed first run would re-read all it had stored.
        platform::atomic_write(
            &staged.path().join(format::STATE),
            &serde_json::to_vec(&serde_json::json!({"LastHashRun":Utc::now().to_rfc3339()}))?,
            false,
        )?;
        fs::rename(staged.path(), &self.current)?;
        platform::sync_directory(&self.root)
    }
    /// The latest state's run dates; absent or unreadable reads as none.
    pub fn state(&self) -> Option<serde_json::Value> {
        serde_json::from_slice(&fs::read(self.current.join(format::STATE)).ok()?).ok()
    }
    pub fn states(&self) -> Result<Vec<PathBuf>> {
        platform::ordinary_dir(&self.current)?;
        platform::ordinary_dir(&self.history)?;
        let mut states = vec![self.current.to_path_buf()];
        for entry in fs::read_dir(&self.history)? {
            let entry = entry?;
            if snapshot_order(&entry.file_name().to_string_lossy()).is_some() {
                platform::ordinary_dir(&entry.path())?;
                states.push(entry.path());
            }
        }
        states[1..].sort_by_key(|p| snapshot_order(&p.file_name().unwrap().to_string_lossy()));
        Ok(states)
    }
    pub fn index(&self) -> Result<BTreeMap<ContentKey, Vec<Object>>> {
        let mut map: BTreeMap<ContentKey, Vec<Object>> = BTreeMap::new();
        for state in self.states()? {
            let state: Arc<Path> = state.into();
            let folders = if state.as_ref() == self.current.as_ref() {
                let mut shards = Vec::new();
                for entry in fs::read_dir(&state)? {
                    let entry = entry?;
                    let name = entry.file_name();
                    let text = name.to_string_lossy();
                    if text.len() == 2
                        && text
                            .bytes()
                            .all(|b| b.is_ascii_lowercase() || (b'2'..=b'9').contains(&b))
                    {
                        platform::ordinary_dir(&entry.path())?;
                        shards.push(entry.path());
                    }
                }
                shards
            } else {
                vec![state.to_path_buf()]
            };
            for folder in folders {
                for entry in fs::read_dir(&folder)? {
                    let entry = entry?;
                    let metadata = entry.metadata()?;
                    if !metadata.is_file()
                        || platform::is_redirect(&fs::symlink_metadata(entry.path())?)
                    {
                        continue;
                    }
                    let name = entry
                        .file_name()
                        .into_string()
                        .map_err(|_| anyhow::anyhow!("non-Unicode stored filename"))?;
                    if let Ok(key) = format::parse_name(&name) {
                        if state.as_ref() == self.current.as_ref()
                            && folder.file_name().and_then(|v| v.to_str())
                                != Some(format::shard(&name)?.as_str())
                        {
                            continue;
                        }
                        index_object(
                            &mut map,
                            Object {
                                path: entry.path(),
                                state: state.clone(),
                                name,
                                key,
                                verified: None,
                            },
                        );
                    }
                }
            }
        }
        Ok(map)
    }
    pub fn cleanup(&self) -> Vec<String> {
        let mut warnings = Vec::new();
        let clean_files = |folder: &Path, archive: bool| -> Result<()> {
            platform::ordinary_dir(folder)?;
            let entries: Vec<_> = fs::read_dir(folder)?.collect::<std::io::Result<_>>()?;
            for entry in &entries {
                let name = entry.file_name();
                let m = fs::symlink_metadata(entry.path())?;
                ensure!(platform::is_ordinary_file(&m), "unknown residue entry");
                ensure!(
                    if archive {
                        name == "content.7z"
                    } else {
                        is_state_file(&name) || name.to_string_lossy().starts_with(".tmp")
                    },
                    "unknown residue preserved"
                );
            }
            for entry in entries {
                fs::remove_file(entry.path())?;
            }
            fs::remove_dir(folder)?;
            Ok(())
        };
        for parent in [&self.root, &self.history] {
            let result = || -> Result<()> {
                for entry in fs::read_dir(parent)? {
                    let entry = entry?;
                    let name = entry.file_name();
                    let name = name.to_string_lossy();
                    if ((parent == &self.root && name.starts_with("Initializing_"))
                        || (parent == &self.history && name.starts_with("Building_")))
                        && let Err(e) = clean_files(&entry.path(), false)
                    {
                        warnings.push(format!(
                            "Residue retained: {}: {e:#}",
                            entry.path().display()
                        ));
                    }
                }
                Ok(())
            }();
            if let Err(e) = result {
                warnings.push(format!("Residue inspection incomplete: {e:#}"));
            }
        }
        let incoming = self.root.join("Incoming");
        if incoming.exists() {
            let result = || -> Result<()> {
                platform::ordinary_dir(&incoming)?;
                for entry in fs::read_dir(&incoming)? {
                    let entry = entry?;
                    let name = entry.file_name();
                    let name = name.to_string_lossy();
                    let m = fs::symlink_metadata(entry.path())?;
                    if name.starts_with(".tmp") && platform::is_ordinary_file(&m) {
                        fs::remove_file(entry.path())?;
                    } else if name.starts_with("archive-") {
                        if let Err(e) = clean_files(&entry.path(), true) {
                            warnings.push(format!("Archive residue retained: {e:#}"));
                        }
                    } else {
                        warnings.push(format!(
                            "Unknown Incoming entry retained: {}",
                            entry.path().display()
                        ));
                    }
                }
                Ok(())
            }();
            if let Err(e) = result {
                warnings.push(format!("Incoming cleanup incomplete: {e:#}"));
            }
        }
        warnings
    }
    pub fn path(&self, name: &str) -> Result<PathBuf> {
        Ok(self.current.join(format::shard(name)?).join(name))
    }
    pub fn misplaced(&self) -> Result<Vec<PathBuf>> {
        platform::ordinary_dir(&self.current)?;
        let mut found = Vec::new();
        for entry in fs::read_dir(&self.current)? {
            let entry = entry?;
            let m = fs::symlink_metadata(entry.path())?;
            if platform::is_redirect(&m) {
                continue;
            }
            let name = entry.file_name().to_string_lossy().into_owned();
            if m.is_file() && format::parse_name(&name).is_ok() {
                found.push(entry.path());
            }
            if m.is_dir() && name.len() == 2 {
                for member in fs::read_dir(entry.path())? {
                    let member = member?;
                    let m = fs::symlink_metadata(member.path())?;
                    let n = member.file_name().to_string_lossy().into_owned();
                    if platform::is_ordinary_file(&m) && format::shard(&n).is_ok_and(|s| s != name)
                    {
                        found.push(member.path());
                    }
                }
            }
        }
        Ok(found)
    }
    pub fn quarantine(&self, path: &Path) -> Result<PathBuf> {
        ensure!(
            path.starts_with(&self.current) || path.starts_with(&self.history),
            "quarantine outside pool"
        );
        let root = self.root.join("Verify");
        fs::create_dir_all(&root)?;
        platform::ordinary_dir(&root)?;
        let folder = platform::store_temp_dir("object-", &root)?.keep();
        let target = folder.join(path.file_name().context("missing object name")?);
        fs::rename(path, &target)?;
        platform::sync_directory(path.parent().unwrap())?;
        platform::sync_directory(&folder)?;
        Ok(target)
    }
    pub fn write(&self, rows: &[impl AsRef<FileRow>], dirs: &[DirectoryRow]) -> Result<()> {
        format::validate_records(rows, dirs)?;
        platform::atomic_write_with(&self.current.join(format::MANIFEST), true, |file| {
            format::write_manifest(file, rows.iter().map(AsRef::as_ref))
        })?;
        platform::checkpoint("final-manifest");
        platform::atomic_write(
            &self.current.join(format::DIRECTORIES),
            &format::directory_bytes(dirs)?,
            true,
        )
    }
    pub fn preserve(&self) -> Result<()> {
        // Never fill an existing partial set from a different generation.
        // Default restore ignores .prev; explicit previous recovery reports a
        // missing companion as unavailable metadata and can recover its files.
        let mut existing = false;
        for name in [format::MANIFEST, format::DIRECTORIES] {
            if let Some(m) = platform::entry_metadata(&self.current.join(format!("{name}.prev")))? {
                ensure!(platform::is_ordinary_file(&m), "unsafe previous definition");
                existing = true;
            }
        }
        if existing {
            return Ok(());
        }
        for name in [format::MANIFEST, format::DIRECTORIES] {
            platform::preserve(
                &self.current.join(name),
                &self.current.join(format!("{name}.prev")),
            )?;
            if name == format::MANIFEST {
                platform::checkpoint("previous-manifest");
            }
        }
        Ok(())
    }
    pub fn snapshot(&self, rows: &[FileRow], dirs: &[DirectoryRow]) -> Result<PathBuf> {
        let latest = self
            .states()?
            .iter()
            .filter_map(|p| snapshot_time(&p.file_name()?.to_string_lossy()))
            .max();
        let now = self
            .state()
            .and_then(|v| {
                v.get("LastBackupRun")
                    .and_then(|v| v.as_str())
                    .and_then(|v| DateTime::parse_from_rfc3339(v).ok())
            })
            .map(|v| v.with_timezone(&Utc))
            .or_else(|| {
                fs::metadata(self.current.join(format::MANIFEST))
                    .ok()?
                    .modified()
                    .ok()
                    .map(DateTime::<Utc>::from)
            })
            .unwrap_or_else(Utc::now);
        let date = latest.map_or(now, |last| std::cmp::max(now, last + Duration::seconds(1)));
        let name = date.format("%Y_%m_%d_%H_%M_%S").to_string();
        let target = self.history.join(&name);
        ensure!(!target.try_exists()?, "snapshot identity collision");
        let staged = platform::store_temp_dir("Building_", &self.history)?;
        kit::publish(staged.path())?;
        platform::atomic_write_with(&staged.path().join(format::MANIFEST), false, |file| {
            format::write_manifest(file, rows)
        })?;
        platform::atomic_write(
            &staged.path().join(format::DIRECTORIES),
            &format::directory_bytes(dirs)?,
            false,
        )?;
        if let Ok(bytes) = fs::read(self.current.join(format::STATE)) {
            platform::atomic_write(&staged.path().join(format::STATE), &bytes, false)?;
        }
        fs::rename(staged.path(), &target)?;
        platform::checkpoint("snapshot");
        platform::sync_directory(&self.history)?;
        Ok(target)
    }
    pub fn remove_unneeded_snapshot(&self, path: &Path) -> Result<()> {
        ensure!(
            path.parent() == Some(self.history.as_path()),
            "invalid snapshot cleanup path"
        );
        // No recursive deletion: only this run's known metadata/kit files; unexpected content survives.
        for entry in fs::read_dir(path)? {
            let entry = entry?;
            let name = entry.file_name();
            ensure!(
                is_state_file(&name),
                "unexpected content prevents snapshot cleanup"
            );
        }
        for entry in fs::read_dir(path)? {
            fs::remove_file(entry?.path())?;
        }
        fs::remove_dir(path)?;
        Ok(())
    }
}
pub fn snapshot_order(name: &str) -> Option<(DateTime<Utc>, u64)> {
    let date = snapshot_time(name)?;
    let suffix = if name.len() == 19 {
        0
    } else {
        name.get(20..)?.parse().ok()?
    };
    Some((date, suffix))
}
pub fn snapshot_time(name: &str) -> Option<DateTime<Utc>> {
    if name.len() < 19 {
        return None;
    }
    let base = name.get(..19)?;
    if name.len() > 19 {
        let suffix = name.get(19..)?.strip_prefix('_')?;
        if suffix.is_empty() || !suffix.bytes().all(|b| b.is_ascii_digit()) {
            return None;
        }
    }
    NaiveDateTime::parse_from_str(base, "%Y_%m_%d_%H_%M_%S")
        .ok()
        .map(|d| d.and_utc())
}
