//! IF-008/013: bounded capture with prior-state publication and immutable objects.
use crate::{
    config::{BackupSet, Config},
    format::{self, ContentKey, DirectoryRow, FileRow},
    kit, platform,
    store::{Object, Store, index_object},
    tools,
};
use anyhow::{Context, Result, ensure};
use chrono::{DateTime, Utc};
use serde::Serialize;
use std::{
    collections::{BTreeMap, BTreeSet, BinaryHeap},
    fs::{self, File},
    io::{Read, Seek, SeekFrom, Write},
    path::{Path, PathBuf},
    sync::mpsc,
    thread,
    time::{Duration, Instant},
};

#[derive(Default, Serialize, Debug)]
pub struct Report {
    pub schema_version: u32,
    pub action: String,
    pub set: String,
    pub code: i32,
    pub captured: u64,
    pub reused: u64,
    pub failed: u64,
    pub added: u64,
    pub changed: u64,
    pub removed: u64,
    pub frozen: u64,
    pub elapsed_ms: u128,
    pub findings: Vec<String>,
    pub events: Vec<Finding>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub details: Option<serde_json::Value>,
}
#[derive(Serialize, Debug)]
pub struct Finding {
    pub class: &'static str,
    pub cause: String,
    pub path: Option<String>,
    pub message: String,
}
impl Report {
    pub fn new(action: &str, set: &str) -> Self {
        Self {
            schema_version: 1,
            action: action.into(),
            set: set.into(),
            ..Self::default()
        }
    }
    pub fn finding(&mut self, code: i32, message: String) {
        let cause = match code {
            2 => "request_refused",
            4 => "host_unavailable",
            _ => "content_incomplete",
        };
        self.finding_at(code, cause, None, message);
    }
    pub fn finding_at(&mut self, code: i32, cause: &str, path: Option<&str>, message: String) {
        if rank(code) > rank(self.code) {
            self.code = code;
        }
        self.findings.push(message.clone());
        self.events.push(Finding {
            class: match code {
                2 => "refused",
                4 => "host_stop",
                1 => "incomplete",
                _ => "warning",
            },
            cause: cause.into(),
            path: path.map(str::to_owned),
            message,
        });
    }
}
pub fn rank(code: i32) -> u8 {
    match code {
        2 => 3,
        4 => 2,
        1 => 1,
        _ => 0,
    }
}
#[derive(Default)]
struct Walk {
    files: Vec<(String, PathBuf)>,
    dirs: Vec<DirectoryRow>,
    frozen: Vec<String>,
    complete: bool,
    observed: usize,
}
// Keep unchanged rows borrowed without reserving an entire FileRow in every
// map slot. Only successfully captured replacements need owned row storage.
enum RunRow<'a> {
    Prior(&'a FileRow),
    Captured(Box<FileRow>),
}
impl RunRow<'_> {
    fn as_ref(&self) -> &FileRow {
        match self {
            Self::Prior(row) => row,
            Self::Captured(row) => row,
        }
    }
    fn into_owned(self) -> FileRow {
        match self {
            Self::Prior(row) => row.clone(),
            Self::Captured(row) => *row,
        }
    }
}
fn walk(source: &Path, protected: &[PathBuf]) -> Walk {
    let mut result = Walk {
        complete: true,
        ..Walk::default()
    };
    let mut stack = vec![(source.to_path_buf(), String::new(), BTreeSet::new())];
    while let Some((physical, relative, mut ancestors)) = stack.pop() {
        let identity = match fs::canonicalize(&physical) {
            Ok(p) => p,
            Err(_) => {
                result.complete = false;
                result.frozen.push(relative);
                continue;
            }
        };
        if !ancestors.insert(identity.clone()) {
            result.complete = false;
            result.frozen.push(relative);
            continue;
        }
        let entries = match fs::read_dir(&physical) {
            Ok(v) => v,
            Err(_) => {
                result.complete = false;
                result.frozen.push(relative);
                continue;
            }
        };
        let volume_root = platform::is_volume_root(&identity);
        for entry in entries {
            let entry = match entry {
                Ok(v) => v,
                Err(_) => {
                    result.complete = false;
                    result.frozen.push(relative.clone());
                    continue;
                }
            };
            result.observed += 1;
            let Some(name) = entry.file_name().to_str().map(str::to_owned) else {
                result.complete = false;
                result.frozen.push(relative.clone());
                continue;
            };
            let rel = if relative.is_empty() {
                name.clone()
            } else {
                format!("{relative}/{name}")
            };
            // Exclude only volume-owned names at an actual filesystem root.
            if volume_root && ["System Volume Information", "$RECYCLE.BIN"].contains(&name.as_str())
            {
                continue;
            }
            if format::validate_path(&rel).is_err() {
                result.complete = false;
                result.frozen.push(rel);
                continue;
            }
            let path = entry.path();
            let metadata = match fs::metadata(&path) {
                Ok(v) => v,
                Err(_) => {
                    result.complete = false;
                    result.frozen.push(rel);
                    continue;
                }
            };
            let link = fs::symlink_metadata(&path)
                .map(|m| platform::is_redirect(&m))
                .unwrap_or(true);
            if metadata.is_dir() {
                if link {
                    let target = match fs::canonicalize(&path) {
                        Ok(v) => v,
                        Err(_) => {
                            result.complete = false;
                            result.frozen.push(rel);
                            continue;
                        }
                    };
                    if protected.iter().any(|p| platform::overlaps(p, &target)) {
                        result.complete = false;
                        result.frozen.push(rel);
                        continue;
                    }
                    // Some Windows cloud reparse points resolve to themselves;
                    // they are directories, not symbolic folder mappings.
                    if target != path
                        && let Ok(tail) = target.strip_prefix(source)
                    {
                        let mapping = if tail.as_os_str().is_empty() {
                            ".".into()
                        } else {
                            tail.to_string_lossy().replace('\\', "/")
                        };
                        if mapping != "." && format::validate_path(&mapping).is_err() {
                            result.complete = false;
                            result.frozen.push(rel);
                            continue;
                        }
                        result.dirs.push(DirectoryRow {
                            relative_path: rel,
                            attributes: String::new(),
                            kind: "FolderLink".into(),
                            target: mapping,
                        });
                        continue;
                    }
                }
                let attributes = directory_attributes(&metadata);
                result.dirs.push(DirectoryRow {
                    relative_path: rel.clone(),
                    attributes,
                    kind: "Directory".into(),
                    target: String::new(),
                });
                stack.push((path, rel, ancestors.clone()));
            } else if metadata.is_file() {
                if link
                    && fs::canonicalize(&path).is_ok_and(|target| {
                        protected.iter().any(|p| platform::overlaps(p, &target))
                    })
                {
                    result.complete = false;
                    result.frozen.push(rel);
                    continue;
                }
                result.files.push((rel, path));
            } else {
                result.complete = false;
                result.frozen.push(rel);
            }
        }
    }
    // Borrow names already owned by the walk; don't allocate a Vec per unique path.
    // An occupied None means the group's first path was already frozen.
    let mut groups: BTreeMap<String, Option<&str>> = BTreeMap::new();
    for rel in result
        .files
        .iter()
        .map(|(r, _)| r)
        .chain(result.dirs.iter().map(|r| &r.relative_path))
    {
        match groups.entry(format::path_key(rel)) {
            std::collections::btree_map::Entry::Vacant(entry) => {
                entry.insert(Some(rel));
            }
            std::collections::btree_map::Entry::Occupied(mut entry) => {
                result.complete = false;
                if let Some(first) = entry.get_mut().take() {
                    result.frozen.push(first.to_owned());
                }
                result.frozen.push(rel.clone());
            }
        }
    }
    drop(groups);
    let frozen = result.frozen.clone();
    let blocked = |p: &str| {
        frozen.iter().any(|prefix| {
            prefix.is_empty()
                || p == prefix
                || p.strip_prefix(prefix)
                    .is_some_and(|tail| tail.starts_with('/'))
        })
    };
    result.files.retain(|(rel, _)| !blocked(rel));
    result.dirs.retain(|row| !blocked(&row.relative_path));
    let ordinary: BTreeSet<_> = result
        .dirs
        .iter()
        .filter(|d| d.kind == "Directory")
        .map(|d| format::path_key(&d.relative_path))
        .collect();
    result.dirs.retain(|row| {
        let keep = row.kind != "FolderLink"
            || row.target == "."
            || ordinary.contains(&format::path_key(&row.target));
        if !keep {
            result.complete = false;
            result.frozen.push(row.relative_path.clone());
        }
        keep
    });
    result.files.sort_by(|a, b| a.0.cmp(&b.0));
    result
        .dirs
        .sort_by(|a, b| a.relative_path.cmp(&b.relative_path));
    result
}
fn directory_attributes(metadata: &fs::Metadata) -> String {
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;
        let bits = metadata.file_attributes();
        [
            (2, "Hidden"),
            (4, "System"),
            (1, "ReadOnly"),
            (8192, "NotContentIndexed"),
        ]
        .iter()
        .filter(|(n, _)| bits & n != 0)
        .map(|(_, s)| *s)
        .collect::<Vec<_>>()
        .join("|")
    }
    #[cfg(not(windows))]
    {
        let _ = metadata;
        String::new()
    }
}
fn modified(metadata: &fs::Metadata) -> Result<String> {
    let time: DateTime<Utc> = metadata.modified()?.into();
    Ok(time.to_rfc3339_opts(chrono::SecondsFormat::Nanos, true))
}
fn usable(object: &Object) -> bool {
    fs::metadata(&object.path).is_ok_and(|m| {
        m.is_file()
            && (m.len() == object.key.length
                || (m.len() > 0 && tools::is_archive(&object.path).unwrap_or(false)))
    })
}
fn full_reread(set: &BackupSet, store: &Store) -> bool {
    if set.frequency == "N" {
        return false;
    }
    if ["A", "E"].contains(&set.frequency.as_str()) {
        return true;
    }
    let state = fs::read(store.current.join("FileBackupState.json"))
        .ok()
        .and_then(|v| serde_json::from_slice::<serde_json::Value>(&v).ok());
    let last = state
        .as_ref()
        .and_then(|v| v.get("LastHashRun"))
        .and_then(|v| v.as_str())
        .and_then(|v| DateTime::parse_from_rfc3339(v).ok());
    let seconds = match set.frequency.as_str() {
        "D" => 86400,
        "W" => 7 * 86400,
        "M" => 30 * 86400,
        "Y" => 365 * 86400,
        _ => 0,
    };
    last.is_none_or(|v| Utc::now().signed_duration_since(v).num_seconds() >= seconds)
}
fn should_compress(
    set: &BackupSet,
    path: &Path,
    source_name: &str,
    tool: Option<&Path>,
    incoming: &Path,
    report: &mut Report,
) -> bool {
    if !set.compress {
        return false;
    }
    let ext = Path::new(source_name)
        .extension()
        .and_then(|v| v.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();
    let exempt = [
        "7z", "zip", "gz", "xz", "bz2", "rar", "zst", "jpg", "jpeg", "png", "webp", "mp4", "mkv",
        "mp3", "flac", "pdf",
    ]
    .contains(&ext.as_str());
    let length = fs::metadata(path).map(|m| m.len()).unwrap_or(0);
    if length <= 256 * 1024 || set.probe == "off" || (set.probe == "excluded-extensions" && exempt)
    {
        return !exempt;
    }
    let probe = || -> Result<bool> {
        let tool = tool.context("compressor unavailable")?;
        let mut source = File::open(path)?;
        let mut sample = tempfile::NamedTempFile::new_in(incoming)?;
        let mut buffer = vec![0u8; 256 * 1024];
        let mut total = 0usize;
        let offsets = if length < 3 * 256 * 1024 {
            vec![0]
        } else {
            vec![0, (length - 256 * 1024) / 2, length - 256 * 1024]
        };
        if offsets.len() == 1 {
            total = std::io::copy(&mut source, &mut sample)? as usize;
        } else {
            for offset in offsets {
                source.seek(SeekFrom::Start(offset))?;
                source.read_exact(&mut buffer)?;
                sample.write_all(&buffer)?;
                total += buffer.len();
            }
        }
        sample.flush()?;
        let sample = sample.into_temp_path();
        let archive = incoming.join(format!(
            "{}.7z",
            sample.file_name().unwrap().to_string_lossy()
        ));
        let outcome = tools::compress(tool, &sample, &archive)
            .and_then(|_| Ok(fs::metadata(&archive)?.len() as f64 <= total as f64 * 0.9));
        let _ = fs::remove_file(archive);
        outcome
    };
    match probe() {
        Ok(v) => v,
        Err(_) => {
            report.findings.push(format!(
                "Compression probe unavailable for {source_name}; type fallback used"
            ));
            !exempt
        }
    }
}
fn capture(
    set: &BackupSet,
    store: &Store,
    relative: &str,
    path: &Path,
    index: &mut BTreeMap<ContentKey, Vec<Object>>,
    adapters: &tools::Adapters,
    report: &mut Report,
) -> Result<FileRow> {
    let tool = adapters.seven_zip.as_deref();
    let before = fs::metadata(path)?;
    let stamp = modified(&before)?;
    let incoming = store.root.join("Incoming");
    fs::create_dir_all(&incoming)?;
    platform::ordinary_dir(&incoming)?;
    let capacity = platform::available(&incoming);
    if capacity.is_none()
        && !report
            .events
            .iter()
            .any(|e| e.cause == "capacity_unavailable")
    {
        report.finding_at(
            0,
            "capacity_unavailable",
            None,
            "Staging capacity is unavailable; bounded writes will stop on host failure".into(),
        );
    }
    if let Some(free) = capacity
        && free
            <= before
                .len()
                .saturating_mul(if set.compress { 2 } else { 1 })
                .saturating_add(1024 * 1024)
    {
        return Err(platform::HostStop("insufficient staging capacity").into());
    }
    let mut staged = tempfile::NamedTempFile::new_in(&incoming)?;
    let key = format::copy_hash(File::open(path)?, &mut staged)?;
    staged.as_file().sync_all()?;
    // 7-Zip opens inputs without sharing an existing write handle on Windows.
    let staged = staged.into_temp_path();
    let after = fs::metadata(path)?;
    ensure!(
        before.len() == after.len()
            && before.modified()? == after.modified()?
            && key.length == after.len(),
        "source changed while being copied"
    );
    let media = match tools::media_rate(adapters.ffprobe.as_deref(), &staged, relative, key.length)
    {
        Ok(value) => value.unwrap_or_default(),
        Err(_) => {
            report.finding_at(
                0,
                "media_unavailable",
                Some(relative),
                "Optional media measurement unavailable".into(),
            );
            String::new()
        }
    };
    if let Some(objects) = index.get_mut(&key) {
        for object in objects.iter_mut() {
            if object.verified.is_none() {
                object.verified = tools::verify_form(&object.path, &key, tool, &incoming)?;
            }
            if object.state == store.current && object.verified.is_none() {
                object.path = store.quarantine(&object.path)?;
                object.state = store.root.join("Verify");
                report.finding(
                    1,
                    format!(
                        "Damaged object set aside; source can replace it: {}",
                        object.name
                    ),
                );
            }
        }
        objects.retain(|object| object.state != store.root.join("Verify"));
        for object in objects {
            if let Some(form) = object.verified {
                let destination = store.path(&object.name)?;
                if object.path != destination && !destination.try_exists()? {
                    fs::create_dir_all(destination.parent().unwrap())?;
                    platform::ordinary_dir(destination.parent().unwrap())?;
                    fs::rename(&object.path, &destination)?;
                    platform::sync_directory(object.path.parent().unwrap())?;
                    platform::sync_directory(destination.parent().unwrap())?;
                    object.path = destination.clone();
                    object.state = store.current.clone();
                }
                let form = if object.path != destination {
                    tools::verify_form(&destination, &key, tool, &incoming)?
                        .context("destination object is unusable")?
                } else {
                    form
                };
                let raw = form == tools::StoredForm::Raw;
                return Ok(FileRow {
                    data_path: object.name.clone(),
                    relative_path: relative.into(),
                    length: key.length,
                    modified: stamp,
                    hash: key.hash,
                    compressed: if raw { "No" } else { "Yes" }.into(),
                    storage: "Hash".into(),
                    duplicate: "Duplicate".into(),
                    media,
                });
            }
        }
    }
    let compressed = should_compress(set, &staged, relative, tool, &incoming, report);
    let archive_dir = tempfile::Builder::new()
        .prefix("archive-")
        .tempdir_in(&incoming)?;
    let archive = archive_dir.path().join("content.7z");
    if compressed {
        tools::compress(
            tool.context("required compressor unavailable")?,
            &staged,
            &archive,
        )?;
        ensure!(
            tools::verify(&archive, &key, tool, &incoming)?,
            "compressor output failed round-trip verification"
        );
    }
    let extension = if compressed {
        ".7z".to_owned()
    } else {
        Path::new(relative)
            .extension()
            .map(|v| format!(".{}", v.to_string_lossy()))
            .unwrap_or_default()
    };
    let name = format::object_name(&key, &extension)?;
    let destination = store.path(&name)?;
    fs::create_dir_all(destination.parent().unwrap())?;
    platform::ordinary_dir(destination.parent().unwrap())?;
    if destination.try_exists()? {
        ensure!(
            !tools::verify(&destination, &key, tool, &incoming)?,
            "unexpected usable destination; retry index"
        );
        store.quarantine(&destination)?;
        report.finding(
            1,
            format!("Damaged destination preserved in Verify: {name}"),
        );
    }
    if compressed {
        fs::rename(&archive, &destination)?;
    } else {
        staged.persist_noclobber(&destination)?;
    }
    platform::sync_directory(destination.parent().unwrap())?;
    platform::checkpoint("object");
    index_object(
        index,
        Object {
            path: destination,
            state: store.current.clone(),
            name: name.clone(),
            key: key.clone(),
            verified: Some(if compressed {
                tools::StoredForm::Archive
            } else {
                tools::StoredForm::Raw
            }),
        },
    );
    Ok(FileRow {
        data_path: name,
        relative_path: relative.into(),
        length: key.length,
        modified: stamp,
        hash: key.hash,
        compressed: if compressed { "Yes" } else { "No" }.into(),
        storage: "Hash".into(),
        duplicate: String::new(),
        media,
    })
}
// Implements: LLR-153, LLR-155..167, LLR-180.
pub fn backup(config: &Config, set: &BackupSet) -> Report {
    let start = Instant::now();
    let mut report = Report::new("backup", &set.name);
    if let Err(e) = backup_inner(config, set, &mut report) {
        report.finding(4, format!("{e:#}"));
    }
    report.elapsed_ms = start.elapsed().as_millis();
    if set.view.is_some() && report.code != 2 && report.code != 4 {
        let view = crate::maintenance::view(set);
        if view.code != 0 {
            report.finding_at(
                0,
                "view_unavailable",
                None,
                "Captured content retained; browse view could not be refreshed".into(),
            );
        }
    }
    if let Err(_e) = append_log(set, &report) {
        report.finding_at(
            0,
            "log_unavailable",
            None,
            "Operational log could not be appended".into(),
        );
    }
    report
}
fn append_log(set: &BackupSet, report: &Report) -> Result<()> {
    if report.code == 2 || !set.store.join("CurrentBackup/MANIFEST.csv").is_file() {
        return Ok(());
    }
    platform::ordinary_dir(&set.store)?;
    let path = set.store.join("backup.log");
    if let Some(m) = platform::entry_metadata(&path)? {
        ensure!(
            m.is_file() && !platform::is_redirect(&m),
            "unsafe operational log"
        );
    }
    let mut log = fs::OpenOptions::new()
        .append(true)
        .create(true)
        .open(path)?;
    let mut bytes = serde_json::to_vec(report)?;
    bytes.push(b'\n');
    log.write_all(&bytes)?;
    Ok(())
}
fn record_changes(
    prior: &[FileRow],
    final_rows: &[FileRow],
    prior_dirs: &[DirectoryRow],
    dirs: &[DirectoryRow],
    report: &mut Report,
) {
    let prior_map: BTreeMap<_, _> = prior.iter().map(|r| (&r.relative_path, r)).collect();
    for row in final_rows {
        match prior_map.get(&row.relative_path) {
            None => report.added += 1,
            Some(old)
                if row.hash != old.hash
                    || row.length != old.length
                    || row.modified != old.modified =>
            {
                report.changed += 1
            }
            _ => (),
        }
    }
    let latest_paths: BTreeSet<_> = final_rows.iter().map(|r| &r.relative_path).collect();
    report.removed = prior
        .iter()
        .filter(|r| !latest_paths.contains(&r.relative_path))
        .count() as u64;
    let prior_directories: BTreeMap<_, _> =
        prior_dirs.iter().map(|d| (&d.relative_path, d)).collect();
    for dir in dirs {
        match prior_directories.get(&dir.relative_path) {
            None => report.added += 1,
            Some(old)
                if old.kind != dir.kind
                    || old.target != dir.target
                    || old.attributes != dir.attributes =>
            {
                report.changed += 1
            }
            _ => (),
        }
    }
    let latest_directories: BTreeSet<_> = dirs.iter().map(|d| &d.relative_path).collect();
    report.removed += prior_dirs
        .iter()
        .filter(|d| !latest_directories.contains(&d.relative_path))
        .count() as u64;
}
fn backup_inner(config: &Config, set: &BackupSet, report: &mut Report) -> Result<()> {
    kit::preflight()?;
    let store = Store::new(&set.store);
    if store.root.join("PrunePlan.json").exists() {
        report.finding(
            2,
            "Finish the pending explicit prune selection before backup".into(),
        );
        return Ok(());
    }
    let fresh = match store.admit() {
        Ok(v) => v,
        Err(e) => {
            report.finding(2, format!("{e:#}"));
            return Ok(());
        }
    };
    ensure!(
        set.source.is_dir(),
        "source unavailable; no removals published"
    );
    let tool = if set.compress {
        Some(tools::seven_zip(config.seven_zip.as_deref())?)
    } else {
        config.seven_zip.clone()
    };
    let adapters = tools::Adapters {
        seven_zip: tool,
        ffprobe: config.ffprobe.clone(),
    };
    if adapters.ffprobe.is_none() {
        report.finding_at(
            0,
            "media_disabled",
            None,
            "Optional media measurement disabled".into(),
        );
    }
    fs::create_dir_all(&store.root)?;
    let _lock = platform::StoreLock::acquire(&store.root)?;
    // Re-read after acquiring ownership; another admitted writer may have run.
    ensure!(
        store.admit()? == fresh,
        "store changed during admission; retry"
    );
    if fresh {
        store.initialize()?;
    }
    if let Err(e) = platform::assert_same_store_mount(&store.root, &store.current, &store.history) {
        report.finding(2, format!("Unsupported store mount layout: {e:#}"));
        return Ok(());
    }
    ensure!(
        !store.root.join("PrunePlan.json").exists(),
        "pending prune appeared; complete it before backup"
    );
    for warning in store.cleanup() {
        report.finding_at(0, "residue_retained", None, warning);
    }
    let prior = format::read_manifest(&store.current.join(format::MANIFEST))?;
    let prior_dirs = format::read_directories(&store.current.join(format::DIRECTORIES))?;
    ensure!(
        prior.is_empty() || fs::read_dir(&set.source)?.next().is_some(),
        "previously populated source appears empty; refusing removals"
    );
    let (stop_tx, stop_rx) = mpsc::channel::<()>();
    let set_name = set.name.clone();
    let progress = thread::spawn(move || {
        while stop_rx.recv_timeout(Duration::from_secs(120)) == Err(mpsc::RecvTimeoutError::Timeout)
        {
            eprintln!("Backup still active: {set_name}");
        }
    });
    let work = || -> Result<()> {
        if !fresh {
            store.preserve()?;
        }
        let snapshot = if !fresh {
            Some(store.snapshot(&prior, &prior_dirs)?)
        } else {
            None
        };
        let mut index = store.index()?;
        platform::checkpoint("pool-indexed");
        let protected: Vec<_> = config
            .sets
            .iter()
            .flat_map(|s| std::iter::once(s.store.clone()).chain(s.view.clone()))
            .collect();
        let walked = walk(&set.source, &protected);
        platform::checkpoint("source-walked");
        for prefix in &walked.frozen {
            report.finding_at(1,"source_prefix_unavailable",Some(prefix),format!("Source prefix unavailable, unsupported or cyclic; prior rows retained: {prefix}"));
        }
        report.frozen = walked.frozen.len() as u64;
        let reread = full_reread(set, &store);
        let mut rows: BTreeMap<String, RunRow<'_>> = prior
            .iter()
            .map(|r| (r.relative_path.clone(), RunRow::Prior(r)))
            .collect();
        let mut seen = BTreeSet::new();
        let mut row_keys: BTreeMap<String, String> = rows
            .keys()
            .map(|p| (format::path_key(p), p.clone()))
            .collect();
        let mut checkpoint = Instant::now();
        let mut wait_budget = Duration::from_secs(60);
        let mut queue = BinaryHeap::new();
        let now = Instant::now();
        for i in 0..walked.files.len() {
            queue.push(std::cmp::Reverse((now, i, 0u8)));
        }
        platform::checkpoint("capture-ready");
        while let Some(std::cmp::Reverse((eligible, i, attempt))) = queue.pop() {
            let (relative, path) = &walked.files[i];
            seen.insert(format::path_key(relative));
            let delay = eligible.saturating_duration_since(Instant::now());
            if !delay.is_zero() {
                if delay > wait_budget {
                    report.failed += 1;
                    report.finding(1, format!("Retry wait budget exhausted; prior row retained: {relative}; attempts={attempt}"));
                    continue;
                }
                thread::sleep(delay);
                wait_budget -= delay;
            }
            let current = fs::metadata(path).ok();
            let reusable = attempt == 0
                && rows.get(relative).is_some_and(|row| {
                    let row = row.as_ref();
                    !reread
                        && current.as_ref().is_some_and(|m| {
                            m.len() == row.length && modified(m).is_ok_and(|v| v == row.modified)
                        })
                        && index
                            .get(&row.key())
                            .is_some_and(|objects| objects.iter().any(usable))
                });
            if reusable {
                report.reused += 1;
                continue;
            }
            let outcome = match capture(set, &store, relative, path, &mut index, &adapters, report)
            {
                Ok(row) => Some(row),
                Err(e) => {
                    if platform::is_host_stop(&e) {
                        return Err(e);
                    }
                    if attempt < 2 {
                        let backoff = Duration::from_secs(if attempt == 0 { 1 } else { 5 });
                        queue.push(std::cmp::Reverse((
                            Instant::now() + backoff,
                            i,
                            attempt + 1,
                        )));
                        continue;
                    }
                    report.finding(
                        1,
                        format!(
                            "Capture failed; prior row retained: {relative}; attempts=3: {e:#}"
                        ),
                    );
                    None
                }
            };
            if let Some(row) = outcome {
                // A captured replacement is authoritative even if a different
                // subtree was unreadable. Never checkpoint old conflicting paths.
                let key = format::path_key(relative);
                let prefix = key.clone() + "/";
                let mut conflicts: Vec<_> = row_keys
                    .range(prefix.clone()..)
                    .take_while(|(k, _)| k.starts_with(&prefix))
                    .map(|(k, _)| k.clone())
                    .collect();
                conflicts.push(key.clone());
                let mut parent = key.as_str();
                while let Some((p, _)) = parent.rsplit_once('/') {
                    conflicts.push(p.to_owned());
                    parent = p;
                }
                for conflict in conflicts {
                    if let Some(old) = row_keys.remove(&conflict) {
                        rows.remove(&old);
                    }
                }
                row_keys.insert(key, relative.clone());
                rows.insert(relative.clone(), RunRow::Captured(Box::new(row)));
                report.captured += 1;
            } else {
                report.failed += 1;
                if report.code == 0 {
                    report.code = 1;
                }
            }
            if checkpoint.elapsed() >= Duration::from_secs(60) {
                platform::atomic_write(
                    &store.current.join(format::MANIFEST),
                    &format::manifest_ref_bytes(rows.values().map(RunRow::as_ref))?,
                    true,
                )?;
                checkpoint = Instant::now();
            }
        }
        ensure!(
            set.source.is_dir()
                && (prior.is_empty()
                    || (walked.observed > 0 && fs::read_dir(&set.source)?.next().is_some())),
            "source vanished/emptied; refusing final removals"
        );
        if walked.complete {
            rows.retain(|path, _| seen.contains(&format::path_key(path)));
        }
        platform::checkpoint("capture-finished");
        // Capture-only indexes must not coexist with finalization's fresh indexes.
        drop(index);
        drop(row_keys);
        drop(seen);
        drop(walked.files);
        let mut dirs = walked.dirs;
        if !walked.complete {
            let existing: BTreeSet<_> = dirs
                .iter()
                .map(|d| format::path_key(&d.relative_path))
                .collect();
            for old in &prior_dirs {
                if !existing.contains(&format::path_key(&old.relative_path)) {
                    dirs.push(old.clone());
                }
            }
        }
        let mut final_rows: Vec<_> = rows.into_values().map(RunRow::into_owned).collect();
        platform::checkpoint("final-rows");
        // A checkpoint can legitimately have newer files than the old sidecar.
        // Keep independent file content and exclude conflicting supplemental rows.
        let files: BTreeSet<_> = final_rows
            .iter()
            .map(|r| format::path_key(&r.relative_path))
            .collect();
        let mut ancestors = BTreeSet::new();
        for key in &files {
            let mut parent = key.as_str();
            while let Some((p, _)) = parent.rsplit_once('/') {
                ancestors.insert(p.to_owned());
                parent = p;
            }
        }
        dirs.retain(|dir| {
            let d = format::path_key(&dir.relative_path);
            if files.contains(&d) || (dir.kind == "FolderLink" && ancestors.contains(&d)) {
                return false;
            }
            let mut parent = d.as_str();
            while let Some((p, _)) = parent.rsplit_once('/') {
                if files.contains(p) {
                    return false;
                }
                parent = p;
            }
            true
        });
        drop(files);
        drop(ancestors);
        let links: BTreeSet<_> = dirs
            .iter()
            .filter(|d| d.kind == "FolderLink")
            .map(|d| format::path_key(&d.relative_path))
            .collect();
        dirs.retain(|d| {
            let key = format::path_key(&d.relative_path);
            let mut parent = key.as_str();
            while let Some((p, _)) = parent.rsplit_once('/') {
                if links.contains(p) {
                    return false;
                }
                parent = p;
            }
            true
        });
        let ordinary: BTreeSet<_> = dirs
            .iter()
            .filter(|d| d.kind == "Directory")
            .map(|d| format::path_key(&d.relative_path))
            .collect();
        dirs.retain(|d| {
            d.kind != "FolderLink"
                || d.target == "."
                || ordinary.contains(&format::path_key(&d.target))
        });
        drop(ordinary);
        drop(links);
        let mut owners = BTreeSet::new();
        for row in &mut final_rows {
            row.duplicate = if owners.insert(row.key()) {
                String::new()
            } else {
                "Duplicate".into()
            };
        }
        drop(owners);
        let changed = !format::same_manifest(&prior, &final_rows)
            || !format::same_directories(&prior_dirs, &dirs);
        record_changes(&prior, &final_rows, &prior_dirs, &dirs, report);
        drop(prior);
        drop(prior_dirs);
        store.write(&final_rows, &dirs)?;
        platform::checkpoint("final-definitions");
        let old_state = fs::read(store.current.join("FileBackupState.json"))
            .ok()
            .and_then(|v| serde_json::from_slice::<serde_json::Value>(&v).ok());
        let last_hash = if reread && report.code == 0 {
            Some(Utc::now().to_rfc3339())
        } else {
            old_state
                .as_ref()
                .and_then(|v| v.get("LastHashRun"))
                .and_then(|v| v.as_str())
                .map(str::to_owned)
        };
        platform::atomic_write(
            &store.current.join("FileBackupState.json"),
            &serde_json::to_vec(
                &serde_json::json!({"LastBackupRun":Utc::now().to_rfc3339(),"LastHashRun":last_hash}),
            )?,
            true,
        )?;
        if !changed && let Some(path) = &snapshot {
            store.remove_unneeded_snapshot(path)?;
        }
        // Resolve destinations one manifest at a time, never move a final dependency.
        let required: BTreeSet<_> = final_rows.iter().map(FileRow::key).collect();
        let mut superseded: BTreeMap<ContentKey, Object> = store
            .index()?
            .into_iter()
            .filter(|(k, _)| !required.contains(k))
            .filter_map(|(k, v)| {
                v.into_iter()
                    .find(|o| o.state == store.current)
                    .map(|o| (k, o))
            })
            .collect();
        let mut states = store.states()?;
        states.reverse();
        for state in states.into_iter().filter(|s| *s != store.current) {
            if superseded.is_empty() {
                break;
            }
            for row in format::read_manifest(&state.join(format::MANIFEST))? {
                if let Some(object) = superseded.remove(&row.key()) {
                    let destination = state.join(&object.name);
                    if !destination.try_exists()? {
                        fs::rename(&object.path, destination)?;
                        platform::sync_directory(object.path.parent().unwrap())?;
                        platform::sync_directory(&state)?;
                        platform::checkpoint("superseded");
                    }
                }
            }
        }
        if report.code == 0 {
            for name in [format::MANIFEST, format::DIRECTORIES] {
                let path = store.current.join(format!("{name}.prev"));
                if platform::entry_metadata(&path)?.is_some() {
                    fs::remove_file(path)?;
                    platform::checkpoint("previous-cleanup");
                }
            }
        }
        Ok(())
    };
    let result = work();
    drop(stop_tx);
    let _ = progress.join();
    result
}
