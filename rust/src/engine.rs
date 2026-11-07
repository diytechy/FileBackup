//! IF-008/013: bounded capture with prior-state publication and immutable objects.
use crate::{
    config::{BackupSet, Config},
    format::{self, ContentKey, DirectoryRow, FileRow},
    kit, platform,
    progress::{self, Counters, Phase, Reading, Reporter},
    store::{Object, Store, index_object},
    tools,
};
use anyhow::{Context, Result, ensure};
use chrono::{DateTime, Utc};
use serde::Serialize;
use std::{
    collections::{BTreeMap, BTreeSet, BinaryHeap},
    fs::{self, File},
    io::Write,
    path::{Path, PathBuf},
    sync::Arc,
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
    /// Compression probe counters; present on backup reports only.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub probe: Option<ProbeCounters>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub details: Option<serde_json::Value>,
}
/// What the compression decision did this run (LLR-162).
#[derive(Default, Serialize, Debug, Clone, PartialEq, Eq)]
pub struct ProbeCounters {
    /// Files whose saving was measured; always `compressed + raw`.
    pub measured: u64,
    pub compressed: u64,
    pub raw: u64,
    /// Measured files that were small enough to sample whole.
    pub whole_file: u64,
    /// New files that reached the decision with compression on but no measurement.
    pub unmeasured: u64,
    /// The measurement failed, so the type list decided.
    pub fallback: u64,
    /// Source length of each object stored compressed.
    pub bytes_compressed_in: u64,
    /// Archive size of each object stored compressed.
    pub bytes_compressed_out: u64,
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
    files: Vec<String>,
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
impl AsRef<FileRow> for RunRow<'_> {
    fn as_ref(&self) -> &FileRow {
        match self {
            Self::Prior(row) => row,
            Self::Captured(row) => row,
        }
    }
}
impl std::ops::Deref for RunRow<'_> {
    type Target = FileRow;
    fn deref(&self) -> &FileRow {
        self.as_ref()
    }
}
impl RunRow<'_> {
    fn make_mut(&mut self) -> &mut FileRow {
        if let Self::Prior(row) = self {
            *self = Self::Captured(Box::new((*row).clone()));
        }
        match self {
            Self::Captured(row) => row,
            Self::Prior(_) => unreachable!(),
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
                // Freeze this entry alone; a lossy name matches no real path.
                let lossy = entry.file_name().to_string_lossy().into_owned();
                result.complete = false;
                result.frozen.push(if relative.is_empty() {
                    lossy
                } else {
                    format!("{relative}/{lossy}")
                });
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
                result.files.push(rel);
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
    result.files.retain(|rel| !blocked(rel));
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
    result.files.sort();
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
        m.is_file() && tools::listed_form(&object.path, m.len(), object.key.length).is_some()
    })
}
/// True when size and time stayed put across a read of the source.
fn unmoved(before: &fs::Metadata, after: &fs::Metadata) -> bool {
    before.len() == after.len() && before.modified().ok() == after.modified().ok()
}
fn full_reread(set: &BackupSet, store: &Store) -> bool {
    if set.frequency == "N" {
        return false;
    }
    if ["A", "E"].contains(&set.frequency.as_str()) {
        return true;
    }
    let last = store
        .state()
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
#[cfg(feature = "test-hooks")]
static RETRY_FAULT_SPENT: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
/// SR-081: compress when the measured saving is at least 10%.
const PROBE_THRESHOLD: f64 = 0.90;
/// How the per-window ratios become one verdict. The Owner's scoring run sets
/// this constant before the change is merged; it is not configuration.
#[allow(dead_code)]
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Combination {
    /// Sum of compressed bytes over sum of raw bytes.
    Mean,
    /// Drop the highest and lowest window ratio, average the rest.
    Trimmed,
    /// The middle window ratio.
    Median,
}
const COMBINATION: Combination = Combination::Mean;
impl Combination {
    fn reason(self) -> &'static str {
        match self {
            Self::Mean => "mean",
            Self::Trimmed => "trimmed",
            Self::Median => "median",
        }
    }
    /// The combined ratio from each window's (raw, compressed) byte counts.
    fn combine(self, windows: &[(usize, usize)]) -> f64 {
        let mut ratios: Vec<f64> = windows
            .iter()
            .map(|&(raw, packed)| packed as f64 / raw as f64)
            .collect();
        ratios.sort_by(f64::total_cmp);
        match self {
            Self::Mean => {
                let raw: usize = windows.iter().map(|w| w.0).sum();
                let packed: usize = windows.iter().map(|w| w.1).sum();
                packed as f64 / raw as f64
            }
            Self::Trimmed if ratios.len() > 2 => {
                let kept = &ratios[1..ratios.len() - 1];
                kept.iter().sum::<f64>() / kept.len() as f64
            }
            Self::Median | Self::Trimmed => ratios[ratios.len() / 2],
        }
    }
}
/// A finished Brotli stream's size at quality 1, window 22, matching .NET's
/// `BrotliEncoder`: the coder SR-081's threshold was calibrated on. Measuring
/// only; nothing stored depends on it.
///
/// The whole window must reach the encoder in one call. `brotli::BrotliCompress`
/// reads its input through a 4 KiB buffer, and the quality 0/1 fast path
/// compresses whatever it is handed per call, so a 256 KiB window would be
/// compressed as 4 KiB pieces and miss repeats longer than that (a 64 KiB
/// repeat reads 1.0 instead of 0.25). Never feed it in small pieces.
pub fn brotli_size(data: &[u8]) -> Result<usize> {
    struct Count(usize);
    impl Write for Count {
        fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
            self.0 += bytes.len();
            Ok(bytes.len())
        }
        fn flush(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }
    #[cfg(feature = "test-hooks")]
    ensure!(
        std::env::var("FILEBACKUP_TEST_PROBE_FAULT").ok().as_deref() != Some("coder"),
        "forced coder failure"
    );
    let params = brotli::enc::BrotliEncoderParams {
        quality: 1,
        lgwin: 22,
        ..Default::default()
    };
    let mut count = Count(0);
    {
        let mut encoder = brotli::CompressorWriter::with_params(&mut count, 1 << 20, &params);
        encoder.write_all(data)?;
        encoder.flush()?;
    }
    Ok(count.0)
}
/// One measured decision: the combined ratio and each window's ratio.
#[derive(Debug)]
struct Measurement {
    combined: f64,
    ratios: Vec<f64>,
}
fn measure(how: Combination, windows: &[&[u8]]) -> Result<Measurement> {
    let sizes = windows
        .iter()
        .map(|w| Ok((w.len(), brotli_size(w)?)))
        .collect::<Result<Vec<_>>>()?;
    ensure!(!sizes.is_empty(), "no probe windows");
    Ok(Measurement {
        combined: how.combine(&sizes),
        ratios: sizes.iter().map(|&(r, p)| p as f64 / r as f64).collect(),
    })
}
/// Window ratios, then (name, value, compresses) per combination.
pub type ProbeSummary = (Vec<f64>, Vec<(&'static str, f64, bool)>);
/// Each window's ratio and every combination's value and verdict, for the
/// `probe_windows` example; the decision itself never calls this.
pub fn probe_summary(windows: &[&[u8]]) -> Result<ProbeSummary> {
    let sizes = windows
        .iter()
        .map(|w| Ok((w.len(), brotli_size(w)?)))
        .collect::<Result<Vec<_>>>()?;
    ensure!(!sizes.is_empty(), "no probe windows");
    let all = [Combination::Mean, Combination::Trimmed, Combination::Median].map(|c| {
        let v = c.combine(&sizes);
        (c.reason(), v, v <= PROBE_THRESHOLD)
    });
    Ok((
        sizes.iter().map(|&(r, p)| p as f64 / r as f64).collect(),
        all.to_vec(),
    ))
}
const EXEMPT: [&str; 16] = [
    "7z", "zip", "gz", "xz", "bz2", "rar", "zst", "jpg", "jpeg", "png", "webp", "mp4", "mkv",
    "mp3", "flac", "pdf",
];
fn exempt_type(source_name: &str) -> bool {
    EXEMPT.contains(&format::lower_extension(source_name).as_str())
}
/// True when this file's saving is measured rather than decided by type.
/// Implements: SR-081, SR-096 (floor, modes and exempt list as before).
fn wants_probe(set: &BackupSet, source_name: &str, length: u64) -> bool {
    set.compress
        && length > format::PROBE_WINDOW
        && set.probe != "off"
        && !(set.probe == "excluded-extensions" && exempt_type(source_name))
}
/// Per-run record of why each measured file was or was not compressed.
struct DecisionLog {
    dir: PathBuf,
    started: DateTime<Utc>,
    file: Option<File>,
    dead: bool,
    warned: bool,
}
/// Runs of decisions kept; older logs are deleted when a new one starts.
const DECISION_LOGS_KEPT: usize = 30;
/// `YYYY_MM_DD_HH_MM_SS.log` or `..._N.log` as (stamp, N); anything else is not ours.
fn decision_log_name(name: &str) -> Option<(&str, u64)> {
    let stem = name.strip_suffix(".log")?;
    let stamp = stem.get(..19)?;
    let shape = b"dddd_dd_dd_dd_dd_dd";
    let fits = stamp.bytes().zip(shape).all(|(b, s)| match s {
        b'd' => b.is_ascii_digit(),
        _ => b == *s,
    });
    if !fits {
        return None;
    }
    match &stem[19..] {
        "" => Some((stamp, 0)),
        tail => {
            let digits = tail.strip_prefix('_')?;
            if digits.is_empty() || !digits.bytes().all(|b| b.is_ascii_digit()) {
                return None;
            }
            Some((stamp, digits.parse().ok()?))
        }
    }
}
impl DecisionLog {
    fn new(store_root: &Path, started: DateTime<Utc>) -> Self {
        Self {
            dir: store_root.join("compress-decisions"),
            started,
            file: None,
            dead: false,
            warned: false,
        }
    }
    fn warn(&mut self, report: &mut Report, what: &str) {
        if !self.warned {
            self.warned = true;
            report.finding_at(
                0,
                "decision_log_unavailable",
                None,
                format!("Compression decision log unavailable: {what}"),
            );
        }
    }
    /// Create this run's file exclusively, then trim older ones. A rotation
    /// failure keeps the new log and comes back beside it.
    fn open(&self) -> Result<(File, Option<anyhow::Error>)> {
        match fs::create_dir(&self.dir) {
            Ok(()) => {}
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => {}
            Err(e) => return Err(e.into()),
        }
        platform::ordinary_dir(&self.dir)?;
        let stamp = self.started.format("%Y_%m_%d_%H_%M_%S");
        let mut attempt = 0u32;
        let (file, name) = loop {
            let name = if attempt == 0 {
                format!("{stamp}.log")
            } else {
                format!("{stamp}_{attempt}.log")
            };
            match fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(self.dir.join(&name))
            {
                Ok(file) => break (file, name),
                Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists && attempt < 1000 => {
                    attempt += 1;
                }
                Err(e) => return Err(e.into()),
            }
        };
        Ok((file, self.rotate(&name).err()))
    }
    /// Delete the oldest ordinary files of this log's own name shape beyond the
    /// newest `DECISION_LOGS_KEPT`; anything else in the folder is left alone.
    fn rotate(&self, own: &str) -> Result<()> {
        let mut logs = Vec::new();
        for entry in fs::read_dir(&self.dir)? {
            let entry = entry?;
            let Some(name) = entry.file_name().to_str().map(str::to_owned) else {
                continue;
            };
            let Some((stamp, n)) = decision_log_name(&name) else {
                continue;
            };
            if fs::symlink_metadata(entry.path()).is_ok_and(|m| platform::is_ordinary_file(&m)) {
                logs.push(((stamp.to_owned(), n), name));
            }
        }
        // This run's own file is never a candidate and takes one of the slots.
        logs.retain(|(_, n)| n != own);
        logs.sort();
        #[cfg(feature = "test-hooks")]
        ensure!(
            std::env::var("FILEBACKUP_TEST_PROBE_FAULT").ok().as_deref() != Some("rotate"),
            "forced rotation failure"
        );
        let surplus = logs.len().saturating_sub(DECISION_LOGS_KEPT - 1);
        for (_, name) in logs.into_iter().take(surplus) {
            fs::remove_file(self.dir.join(name))?;
        }
        Ok(())
    }
    /// Append one flushed line, creating the file on first use. Any failure is
    /// one code-0 warning per run; it never fails a capture.
    fn append(&mut self, report: &mut Report, line: &str) {
        if self.dead {
            return;
        }
        if self.file.is_none() {
            match self.open() {
                Ok((file, rotation)) => {
                    self.file = Some(file);
                    if let Some(e) = rotation {
                        self.warn(report, &format!("rotation failed: {e}"));
                    }
                }
                Err(e) => {
                    self.dead = true;
                    self.warn(report, &format!("{e}"));
                    return;
                }
            }
        }
        let wrote = self.file.as_mut().is_some_and(|f| {
            f.write_all(line.as_bytes())
                .and_then(|_| f.write_all(b"\n"))
                .and_then(|_| f.flush())
                .is_ok()
        });
        if !wrote {
            self.dead = true;
            self.warn(report, "write failed");
        }
    }
}
fn log_line(
    relative: &str,
    length: u64,
    compress: bool,
    reason: &str,
    measurement: Option<&Measurement>,
) -> String {
    let (combined, windows) = match measurement {
        Some(m) => (
            format!("{:.4}", m.combined),
            m.ratios
                .iter()
                .map(|r| format!("{r:.4}"))
                .collect::<Vec<_>>()
                .join(","),
        ),
        None => ("-".into(), "-".into()),
    };
    // A path may legally hold a tab or a newline; keep one decision per line.
    let path = relative.replace(['\t', '\n', '\r'], "?");
    format!(
        "{}\t{path}\t{length}\t{}\t{reason}\t{combined}\t{windows}",
        Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Millis, true),
        if compress { "compress" } else { "raw" },
    )
}
/// What the decision did, carried to the point where the object is published
/// so a retried capture counts once (LLR-162).
#[derive(Clone, Copy, Debug)]
enum Outcome {
    Unmeasured,
    Measured { compress: bool, whole: bool },
    Fallback,
}
impl ProbeCounters {
    /// Count one published object; `packed` is its archive size when stored compressed.
    fn record(&mut self, outcome: Outcome, compressed: bool, length: u64, packed: u64) {
        match outcome {
            Outcome::Unmeasured => self.unmeasured += 1,
            Outcome::Fallback => self.fallback += 1,
            Outcome::Measured { compress, whole } => {
                self.measured += 1;
                self.whole_file += u64::from(whole);
                if compress {
                    self.compressed += 1;
                } else {
                    self.raw += 1;
                }
            }
        }
        if compressed {
            self.bytes_compressed_in += length;
            self.bytes_compressed_out += packed;
        }
    }
}
/// Decide whether a new file is stored compressed.
///
/// `sample` holds the windows taken from the copy that was hashed; it is
/// `None` when no measurement was planned. Implements: SR-081, SR-096, LLR-162.
fn should_compress(
    set: &BackupSet,
    source_name: &str,
    length: u64,
    sample: Option<&format::WindowSampler>,
    log: &mut DecisionLog,
    report: &mut Report,
) -> (bool, Option<Outcome>) {
    if !set.compress {
        return (false, None);
    }
    let exempt = exempt_type(source_name);
    let Some(sample) = sample.filter(|_| wants_probe(set, source_name, length)) else {
        return (!exempt, Some(Outcome::Unmeasured));
    };
    match sample
        .windows()
        .context("probe sample unavailable")
        .and_then(|w| measure(COMBINATION, &w))
    {
        Ok(m) => {
            let compress = m.combined <= PROBE_THRESHOLD;
            let whole = sample.whole_file();
            let reason = if whole {
                "whole-file"
            } else {
                COMBINATION.reason()
            };
            let line = log_line(source_name, length, compress, reason, Some(&m));
            log.append(report, &line);
            (compress, Some(Outcome::Measured { compress, whole }))
        }
        Err(_) => {
            report.findings.push(format!(
                "Compression probe unavailable for {source_name}; type fallback used"
            ));
            let line = log_line(source_name, length, !exempt, "fallback", None);
            log.append(report, &line);
            (!exempt, Some(Outcome::Fallback))
        }
    }
}
#[allow(clippy::too_many_arguments)]
fn capture(
    set: &BackupSet,
    store: &Store,
    relative: &str,
    path: &Path,
    index: &mut BTreeMap<ContentKey, Vec<Object>>,
    ffprobe: Option<&Path>,
    report: &mut Report,
    log: &mut DecisionLog,
    counters: &Arc<Counters>,
) -> Result<FileRow> {
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
    let mut staged = platform::store_temp_file(&incoming)?;
    // The windows come from the very chunks that are hashed and staged.
    let mut sampler =
        wants_probe(set, relative, before.len()).then(|| format::WindowSampler::new(before.len()));
    let key = format::copy_hash_sampled(
        Reading::new(File::open(path)?, counters),
        &mut staged,
        sampler.as_mut(),
    )?;
    staged.as_file().sync_all()?;
    // Close the staging writer before another process reads the file on Windows.
    let staged = staged.into_temp_path();
    let after = fs::metadata(path)?;
    ensure!(
        unmoved(&before, &after) && key.length == after.len(),
        "source changed while being copied"
    );
    let media = match tools::media_rate(ffprobe, &staged, relative, key.length) {
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
                object.verified = tools::verify_form(&object.path, &key)?;
            }
            if object.state == store.current && object.verified.is_none() {
                object.path = store.quarantine(&object.path)?;
                object.state = store.root.join("Verify").into();
                report.finding(
                    1,
                    format!(
                        "Damaged object set aside; source can replace it: {}",
                        object.name
                    ),
                );
            }
        }
        objects.retain(|object| object.state.as_ref() != store.root.join("Verify"));
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
                    tools::verify_form(&destination, &key)?
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
    let (compressed, outcome) =
        should_compress(set, relative, key.length, sampler.as_ref(), log, report);
    drop(sampler);
    // Fault injection is absent from release/default builds: fail the first
    // capture after its decision, to prove a retry counts once.
    #[cfg(feature = "test-hooks")]
    ensure!(
        std::env::var("FILEBACKUP_TEST_PROBE_FAULT").ok().as_deref() != Some("retry")
            || RETRY_FAULT_SPENT.swap(true, std::sync::atomic::Ordering::SeqCst),
        "forced capture failure"
    );
    let archive_dir = tempfile::Builder::new()
        .prefix("archive-")
        .tempdir_in(&incoming)?;
    let archive = archive_dir.path().join("content.7z");
    if compressed {
        tools::compress(&staged, &archive)?;
        ensure!(
            tools::verify(&archive, &key)?,
            "compressor output failed round-trip verification"
        );
    }
    // Read for the counters only; a failure here must not fail the capture.
    let packed = if compressed {
        fs::metadata(&archive).map_or(0, |m| m.len())
    } else {
        0
    };
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
            !tools::verify(&destination, &key)?,
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
            key,
            verified: Some(if compressed {
                tools::StoredForm::Archive
            } else {
                tools::StoredForm::Raw
            }),
        },
    );
    if let Some(outcome) = outcome {
        report
            .probe
            .get_or_insert_with(Default::default)
            .record(outcome, compressed, key.length, packed);
    }
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
// Implements: LLR-153, LLR-155..167, LLR-180, LLR-191.
pub fn backup(config: &Config, set: &BackupSet) -> Report {
    let start = Instant::now();
    let reporter = Reporter::start(&set.name);
    let mut report = Report::new("backup", &set.name);
    report.probe = Some(ProbeCounters::default());
    if let Err(e) = backup_inner(config, set, &mut report, reporter.counters()) {
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
        ensure!(platform::is_ordinary_file(&m), "unsafe operational log");
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
    final_rows: &[impl AsRef<FileRow>],
    prior_dirs: &[DirectoryRow],
    dirs: &[DirectoryRow],
    report: &mut Report,
) {
    let prior_map: BTreeMap<_, _> = prior.iter().map(|r| (&r.relative_path, r)).collect();
    for row in final_rows.iter().map(AsRef::as_ref) {
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
    let latest_paths: BTreeSet<_> = final_rows
        .iter()
        .map(|r| &r.as_ref().relative_path)
        .collect();
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
// A checkpoint can legitimately have newer files than the old sidecar. Keep
// independent file content and drop supplemental rows that conflict with it.
fn reconcile_directories(
    rows: &[impl AsRef<FileRow>],
    mut dirs: Vec<DirectoryRow>,
) -> Vec<DirectoryRow> {
    let files: BTreeSet<_> = rows
        .iter()
        .map(|r| format::path_key(&r.as_ref().relative_path))
        .collect();
    let mut parents = BTreeSet::new();
    for key in &files {
        parents.extend(format::ancestors(key).map(str::to_owned));
    }
    dirs.retain(|dir| {
        let d = format::path_key(&dir.relative_path);
        let conflicts = files.contains(&d)
            || (dir.kind == "FolderLink" && parents.contains(&d))
            || format::ancestors(&d).any(|p| files.contains(p));
        !conflicts
    });
    // Release the per-file sets before building the per-directory ones.
    drop(files);
    drop(parents);
    let links: BTreeSet<_> = dirs
        .iter()
        .filter(|d| d.kind == "FolderLink")
        .map(|d| format::path_key(&d.relative_path))
        .collect();
    dirs.retain(|d| {
        !format::ancestors(&format::path_key(&d.relative_path)).any(|p| links.contains(p))
    });
    let ordinary: BTreeSet<_> = dirs
        .iter()
        .filter(|d| d.kind == "Directory")
        .map(|d| format::path_key(&d.relative_path))
        .collect();
    dirs.retain(|d| {
        d.kind != "FolderLink" || d.target == "." || ordinary.contains(&format::path_key(&d.target))
    });
    dirs
}
// Resolve destinations one manifest at a time, never move a final dependency.
fn move_superseded(store: &Store, required: &BTreeSet<ContentKey>) -> Result<()> {
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
    for state in states
        .into_iter()
        .filter(|s| s.as_path() != store.current.as_ref())
    {
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
    Ok(())
}
fn backup_inner(
    config: &Config,
    set: &BackupSet,
    report: &mut Report,
    counters: &Arc<Counters>,
) -> Result<()> {
    kit::preflight()?;
    if set.compress {
        tools::preflight()?;
    }
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
    if config.ffprobe.is_none() {
        report.finding_at(
            0,
            "media_disabled",
            None,
            "Optional media measurement disabled".into(),
        );
    }
    fs::create_dir_all(&store.root)?;
    let _lock = platform::StoreLock::acquire(&store.root)?;
    #[allow(unused_mut)]
    let mut run_start = Utc::now();
    #[cfg(feature = "test-hooks")]
    if let Some(fixed) = std::env::var("FILEBACKUP_TEST_RUN_STAMP")
        .ok()
        .and_then(|v| DateTime::parse_from_rfc3339(&v).ok())
    {
        run_start = fixed.with_timezone(&Utc);
    }
    let mut log = DecisionLog::new(&store.root, run_start);
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
    let work = || -> Result<()> {
        if !fresh {
            store.preserve()?;
        }
        let snapshot = if !fresh {
            Some(store.snapshot(&prior, &prior_dirs)?)
        } else {
            None
        };
        counters.enter(Phase::IndexingStore);
        let mut index = store.index()?;
        platform::checkpoint("pool-indexed");
        let protected: Vec<_> = config
            .sets
            .iter()
            .flat_map(|s| std::iter::once(s.store.clone()).chain(s.view.clone()))
            .collect();
        counters.enter(Phase::WalkingSource);
        let walked = walk(&set.source, &protected);
        platform::checkpoint("source-walked");
        for prefix in &walked.frozen {
            report.finding_at(1,"source_prefix_unavailable",Some(prefix),format!("Source prefix unavailable, unsupported or cyclic; prior rows retained: {prefix}"));
        }
        report.frozen = walked.frozen.len() as u64;
        let reread = full_reread(set, &store);
        let mut rows: BTreeMap<String, RunRow<'_>> = prior
            .iter()
            .map(|r| (format::path_key(&r.relative_path), RunRow::Prior(r)))
            .collect();
        let mut checkpoint = Instant::now();
        #[cfg(feature = "test-hooks")]
        if std::env::var("FILEBACKUP_TEST_CHECKPOINT").ok().as_deref() == Some("1") {
            checkpoint -= Duration::from_secs(60);
        }
        let mut wait_budget = Duration::from_secs(60);
        let mut queue = BinaryHeap::new();
        let mut first_attempts = 0..walked.files.len();
        counters.enter_counted(Phase::Capturing, walked.files.len() as u64);
        platform::checkpoint("capture-ready");
        while let Some((eligible, i, attempt)) = first_attempts
            .next()
            .map(|i| (Instant::now(), i, 0u8))
            .or_else(|| queue.pop().map(|std::cmp::Reverse(item)| item))
        {
            let relative = &walked.files[i];
            let path = set.source.join(relative.split('/').collect::<PathBuf>());
            let key = format::path_key(relative);
            let read_mark = counters.bytes_read();
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
            let current = fs::metadata(&path).ok();
            let recorded = attempt == 0
                && rows.get(&key).is_some_and(|row| {
                    let row = row.as_ref();
                    row.relative_path == *relative
                        && current.as_ref().is_some_and(|m| {
                            m.len() == row.length && modified(m).is_ok_and(|v| v == row.modified)
                        })
                        && index
                            .get(&row.key())
                            .is_some_and(|objects| objects.iter().any(usable))
                });
            if recorded {
                // A scheduled re-read hashes a recorded file in place and writes
                // nothing. Changed bytes fall through to a staged capture, so an
                // object is still named after the bytes written. Stored objects
                // are the deep verify's job, on its own cadence.
                let found = reread.then(|| progress::hash_file(&path, counters));
                let same = match &found {
                    None => true,
                    // As in a staged capture: a file written during the read proves nothing.
                    Some(Ok(found)) => {
                        rows.get(&key).is_some_and(|r| r.as_ref().key() == *found)
                            && current
                                .as_ref()
                                .zip(fs::metadata(&path).ok())
                                .is_some_and(|(before, after)| unmoved(before, &after))
                    }
                    Some(Err(_)) => false,
                };
                if same {
                    report.reused += 1;
                    counters.item_done();
                    continue;
                }
                counters.rewind_bytes(read_mark);
                if matches!(found, Some(Ok(_))) {
                    report.finding_at(
                        0,
                        "content_changed_on_reread",
                        Some(relative),
                        "Content changed during or behind an unchanged size and time; capturing it"
                            .into(),
                    );
                }
            }
            let outcome = match capture(
                set,
                &store,
                relative,
                &path,
                &mut index,
                config.ffprobe.as_deref(),
                report,
                &mut log,
                counters,
            ) {
                Ok(row) => Some(row),
                Err(e) => {
                    if platform::is_host_stop(&e) {
                        return Err(e);
                    }
                    counters.rewind_bytes(read_mark);
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
                let prefix = key.clone() + "/";
                let mut conflicts: Vec<_> = rows
                    .range(prefix.clone()..)
                    .take_while(|(k, _)| k.starts_with(&prefix))
                    .map(|(k, _)| k.clone())
                    .collect();
                conflicts.push(key.clone());
                conflicts.extend(format::ancestors(&key).map(str::to_owned));
                for conflict in conflicts {
                    rows.remove(&conflict);
                }
                rows.insert(key, RunRow::Captured(Box::new(row)));
                report.captured += 1;
                counters.item_done();
            } else {
                report.failed += 1;
                if report.code == 0 {
                    report.code = 1;
                }
            }
            if checkpoint.elapsed() >= Duration::from_secs(60) {
                platform::atomic_write_with(&store.current.join(format::MANIFEST), true, |file| {
                    format::write_manifest(file, rows.values().map(RunRow::as_ref))
                })?;
                platform::checkpoint("manifest-checkpoint");
                checkpoint = Instant::now();
            }
        }
        counters.enter(Phase::Finishing);
        ensure!(
            set.source.is_dir()
                && (prior.is_empty()
                    || (walked.observed > 0 && fs::read_dir(&set.source)?.next().is_some())),
            "source vanished/emptied; refusing final removals"
        );
        platform::checkpoint("capture-finished");
        // Only retries need queue storage. Release capture supply before removal checks.
        drop(queue);
        drop(index);
        if walked.complete {
            let seen: BTreeSet<_> = walked.files.iter().map(|p| format::path_key(p)).collect();
            rows.retain(|key, _| seen.contains(key));
        }
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
        let mut final_rows: Vec<_> = rows.into_values().collect();
        // Portable lookup order must not change which recorded path owns a duplicate.
        final_rows.sort_unstable_by(|a, b| a.relative_path.cmp(&b.relative_path));
        platform::checkpoint("final-rows");
        let dirs = reconcile_directories(&final_rows, dirs);
        let mut owners = BTreeSet::new();
        for row in &mut final_rows {
            let duplicate = if owners.insert(row.key()) {
                ""
            } else {
                "Duplicate"
            };
            if row.duplicate != duplicate {
                row.make_mut().duplicate = duplicate.into();
            }
        }
        drop(owners);
        let changed = !format::same_manifest(&prior, &final_rows)
            || !format::same_directories(&prior_dirs, &dirs);
        record_changes(&prior, &final_rows, &prior_dirs, &dirs, report);
        drop(prior_dirs);
        store.write(&final_rows, &dirs)?;
        platform::checkpoint("final-definitions");
        let last_hash = if reread {
            Some(Utc::now().to_rfc3339())
        } else {
            store
                .state()
                .as_ref()
                .and_then(|v| v.get("LastHashRun"))
                .and_then(|v| v.as_str())
                .map(str::to_owned)
        };
        platform::atomic_write(
            &store.current.join(format::STATE),
            &serde_json::to_vec(
                &serde_json::json!({"LastBackupRun":Utc::now().to_rfc3339(),"LastHashRun":last_hash}),
            )?,
            true,
        )?;
        if !changed && let Some(path) = &snapshot {
            store.remove_unneeded_snapshot(path)?;
        }
        // Resolve destinations one manifest at a time, never move a final dependency.
        let required: BTreeSet<_> = final_rows.iter().map(|row| row.key()).collect();
        drop(final_rows);
        drop(prior);
        move_superseded(&store, &required)?;
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
    work()
}

#[cfg(test)]
mod probe_tests {
    use super::*;

    // A 64 KiB random block repeated four times: fed whole it compresses to
    // about a quarter; fed in 4 KiB pieces it would read 1.0.
    #[test]
    fn the_window_is_presented_to_the_encoder_whole() {
        let mut s = 0x9E3779B97F4A7C15_u64;
        let block: Vec<u8> = (0..65536)
            .map(|_| {
                s ^= s << 13;
                s ^= s >> 7;
                s ^= s << 17;
                (s >> 32) as u8
            })
            .collect();
        let window = block.repeat(4);
        let ratio = brotli_size(&window).unwrap() as f64 / window.len() as f64;
        assert!(ratio < 0.30, "longrange measured {ratio:.4}");
    }

    /// (raw, packed) pairs for seven windows from their ratios in thousandths.
    fn windows(thousandths: [usize; 7]) -> Vec<(usize, usize)> {
        thousandths.iter().map(|&t| (1000, t)).collect()
    }
    fn verdicts(shape: [usize; 7]) -> [bool; 3] {
        let w = windows(shape);
        [Combination::Mean, Combination::Trimmed, Combination::Median]
            .map(|c| c.combine(&w) <= PROBE_THRESHOLD)
    }

    // Design 4.2: each shape's verdict under mean, trimmed mean and median.
    #[test]
    fn the_three_combinations_on_the_known_shapes() {
        let table = [
            ("remux / disc image / phone video", [1000; 7], [false; 3]),
            (
                "screen recording",
                [1000, 80, 80, 80, 80, 80, 80],
                [true; 3],
            ),
            ("sparse 42%", [1000, 1000, 1000, 0, 0, 0, 0], [true; 3]),
            (
                "mixed-third",
                [1000, 1000, 0, 0, 0, 1000, 1000],
                [true, true, false],
            ),
            (
                "one interior padding window",
                [0, 1000, 1000, 1000, 1000, 1000, 1000],
                [true, false, false],
            ),
            ("already compressed", [990; 7], [false; 3]),
        ];
        for (shape, ratios, expected) in table {
            assert_eq!(verdicts(ratios), expected, "{shape}");
        }
    }

    #[test]
    fn combinations_are_exact() {
        let w = windows([100, 200, 300, 400, 500, 600, 700]);
        assert!((Combination::Mean.combine(&w) - 0.4).abs() < 1e-12);
        assert!((Combination::Trimmed.combine(&w) - 0.4).abs() < 1e-12);
        assert!((Combination::Median.combine(&w) - 0.4).abs() < 1e-12);
        // The mean is sum over sum, not a mean of ratios, when windows differ.
        let uneven = [(100usize, 100usize), (300, 0)];
        assert!((Combination::Mean.combine(&uneven) - 0.25).abs() < 1e-12);
        // One window (a whole-file sample) is its own ratio under every rule.
        for c in [Combination::Mean, Combination::Trimmed, Combination::Median] {
            assert!((c.combine(&[(1000, 123)]) - 0.123).abs() < 1e-12);
        }
        assert_eq!(COMBINATION, Combination::Mean);
    }

    #[test]
    fn only_our_own_log_names_match() {
        let ours = [
            ("2026_11_07_12_30_59.log", ("2026_11_07_12_30_59", 0)),
            ("2026_11_07_12_30_59_1.log", ("2026_11_07_12_30_59", 1)),
            ("2026_11_07_12_30_59_12.log", ("2026_11_07_12_30_59", 12)),
        ];
        for (name, parsed) in ours {
            assert_eq!(decision_log_name(name), Some(parsed), "{name}");
        }
        for other in [
            "notes.txt",
            "2026_11_07_12_30_59.log.bak",
            "2026_11_07_12_30_59_.log",
            "2026_11_07_12_30_59_x.log",
            "2026_11_07_12_30_59_+1.log",
            "2026-11-07_12_30_59.log",
            "x2026_11_07_12_30_59.log",
            "2026_11_07_12_30_5.log",
            "2026_11_07_12_30_599.log",
            "",
            ".log",
            "\u{e9}2026_11_07_12_30_59.log",
        ] {
            assert_eq!(decision_log_name(other), None, "{other}");
        }
    }
}
