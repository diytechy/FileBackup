//! IF-006/007: independent, script-readable content and metadata contracts.
use anyhow::{Context, Result, bail, ensure};
use caseless::Caseless;
use serde::{Deserialize, Serialize};
use std::{
    collections::BTreeSet,
    fs::File,
    io::{Read, Write},
    path::Path,
};
use unicode_normalization::UnicodeNormalization;
use xxhash_rust::xxh3::Xxh3;

pub const ALPHABET: &[u8] = b"23456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
pub const MANIFEST: &str = "MANIFEST.csv";
pub const DIRECTORIES: &str = "DIRECTORIES.csv";
pub const STATE: &str = "FileBackupState.json";
pub const FILE_HEADER: [&str; 9] = [
    "DataPath",
    "RelativePath",
    "Length",
    "LastWriteTimeStr",
    "xxH2Hash",
    "Compressed",
    "StoredAsHashSize",
    "Duplicate",
    "MediaMBPerSec",
];
pub const DIR_HEADER: [&str; 4] = ["RelativePath", "Attributes", "EntryKind", "LinkTarget"];

// Keep one binary identity in memory; the carried CSV remains uppercase hex.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(try_from = "String", into = "String")]
pub struct ContentHash([u8; 16]);
impl TryFrom<String> for ContentHash {
    type Error = anyhow::Error;
    fn try_from(value: String) -> Result<Self> {
        validate_hash(&value)?;
        Ok(Self(u128::from_str_radix(&value, 16)?.to_be_bytes()))
    }
}
impl From<ContentHash> for String {
    fn from(value: ContentHash) -> Self {
        format!("{:032X}", u128::from_be_bytes(value.0))
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub struct ContentKey {
    pub hash: ContentHash,
    pub length: u64,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct FileRow {
    #[serde(rename = "DataPath")]
    pub data_path: String,
    #[serde(rename = "RelativePath")]
    pub relative_path: String,
    #[serde(rename = "Length")]
    pub length: u64,
    #[serde(rename = "LastWriteTimeStr")]
    pub modified: String,
    #[serde(rename = "xxH2Hash")]
    pub hash: ContentHash,
    #[serde(rename = "Compressed")]
    pub compressed: String,
    #[serde(rename = "StoredAsHashSize")]
    pub storage: String,
    #[serde(rename = "Duplicate")]
    pub duplicate: String,
    #[serde(rename = "MediaMBPerSec")]
    pub media: String,
}
impl AsRef<FileRow> for FileRow {
    fn as_ref(&self) -> &FileRow {
        self
    }
}
impl FileRow {
    pub fn key(&self) -> ContentKey {
        ContentKey {
            hash: self.hash,
            length: self.length,
        }
    }
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct DirectoryRow {
    #[serde(rename = "RelativePath")]
    pub relative_path: String,
    #[serde(rename = "Attributes")]
    pub attributes: String,
    #[serde(rename = "EntryKind")]
    pub kind: String,
    #[serde(rename = "LinkTarget")]
    pub target: String,
}

// Implements: LLR-159, LLR-163. Hash the same chunks that are copied.
pub fn copy_hash(input: impl Read, output: impl Write) -> Result<ContentKey> {
    copy_hash_sampled(input, output, None)
}
/// `copy_hash` that also hands every chunk it wrote and hashed to a window
/// sampler, so the compressibility probe never re-reads the source.
// Implements: LLR-159, LLR-162, LLR-163.
pub fn copy_hash_sampled(
    mut input: impl Read,
    mut output: impl Write,
    mut sampler: Option<&mut WindowSampler>,
) -> Result<ContentKey> {
    let mut hasher = Xxh3::new();
    let mut length = 0_u64;
    let mut buffer = [0u8; 256 * 1024];
    loop {
        let n = input.read(&mut buffer)?;
        if n == 0 {
            break;
        }
        output.write_all(&buffer[..n])?;
        hasher.update(&buffer[..n]);
        if let Some(sampler) = sampler.as_deref_mut() {
            sampler.feed(&buffer[..n]);
        }
        length = length
            .checked_add(n as u64)
            .context("file length overflow")?;
    }
    Ok(ContentKey {
        hash: ContentHash(hasher.digest128().to_be_bytes()),
        length,
    })
}

/// One probe window: 256 KiB, SR-081's floor.
pub const PROBE_WINDOW: u64 = 256 * 1024;
/// Below nine windows the seven windows would overlap, so the file is one sample.
pub const PROBE_WHOLE_FILE_LIMIT: u64 = 9 * PROBE_WINDOW;
const PROBE_WINDOWS: u64 = 7;

/// The `(start, length)` of each probe window for a file of `length` bytes.
// Implements: LLR-162. Empty at or under the floor; one whole-file sample below
// 2.25 MiB; otherwise seven windows at floor(k * (length - 256 KiB) / 8), k = 1..7.
pub fn probe_plan(length: u64) -> Vec<(u64, usize)> {
    if length <= PROBE_WINDOW {
        return Vec::new();
    }
    if length < PROBE_WHOLE_FILE_LIMIT {
        return vec![(0, length as usize)];
    }
    let span = u128::from(length - PROBE_WINDOW);
    (1..=PROBE_WINDOWS)
        .map(|k| {
            let start = (u128::from(k) * span / 8) as u64;
            (start, PROBE_WINDOW as usize)
        })
        .collect()
}

/// Collects the planned windows from the chunks of one copy.
///
/// The buffer is sized once from the plan, so a file that grows during the copy
/// cannot enlarge it. A stream that ends early leaves the sample incomplete.
pub struct WindowSampler {
    plan: Vec<(u64, usize)>,
    starts: Vec<usize>,
    buffer: Vec<u8>,
    position: u64,
    filled: usize,
    failed: bool,
}
impl WindowSampler {
    pub fn new(length: u64) -> Self {
        let plan = probe_plan(length);
        let mut starts = Vec::with_capacity(plan.len());
        let mut total = 0usize;
        for (_, len) in &plan {
            starts.push(total);
            total += len;
        }
        Self {
            plan,
            starts,
            buffer: vec![0; total],
            position: 0,
            filled: 0,
            // Fault injection is absent from release/default builds.
            failed: cfg!(feature = "test-hooks")
                && std::env::var("FILEBACKUP_TEST_PROBE_FAULT").ok().as_deref() == Some("sampler"),
        }
    }
    /// Take the part of `chunk` that falls in a window; never panics or grows.
    pub fn feed(&mut self, chunk: &[u8]) {
        let Some(end) = self.position.checked_add(chunk.len() as u64) else {
            self.failed = true;
            return;
        };
        for (i, &(start, len)) in self.plan.iter().enumerate() {
            if start >= end {
                break;
            }
            let window_end = start + len as u64;
            let (lo, hi) = (start.max(self.position), window_end.min(end));
            if lo < hi {
                let into = self.starts[i] + (lo - start) as usize;
                let from = (lo - self.position) as usize;
                let count = (hi - lo) as usize;
                self.buffer[into..into + count].copy_from_slice(&chunk[from..from + count]);
                self.filled += count;
            }
        }
        self.position = end;
    }
    /// True when the sample is the whole file rather than seven windows.
    pub fn whole_file(&self) -> bool {
        self.plan.len() == 1
    }
    /// The windows in order, or `None` when the sample failed or is incomplete.
    pub fn windows(&self) -> Option<Vec<&[u8]>> {
        if self.failed || self.plan.is_empty() || self.filled != self.buffer.len() {
            return None;
        }
        Some(
            self.plan
                .iter()
                .zip(&self.starts)
                .map(|(&(_, len), &start)| &self.buffer[start..start + len])
                .collect(),
        )
    }
}
pub fn hash_file(path: &Path) -> Result<ContentKey> {
    copy_hash(File::open(path)?, std::io::sink())
}

pub fn encode(mut n: u128, width: usize) -> Result<String> {
    let mut digits = Vec::new();
    loop {
        digits.push(ALPHABET[(n % 57) as usize]);
        n /= 57;
        if n == 0 {
            break;
        }
    }
    ensure!(width == 0 || digits.len() <= width, "base57 overflow");
    while digits.len() < width {
        digits.push(ALPHABET[0]);
    }
    digits.reverse();
    Ok(String::from_utf8(digits)?)
}
pub fn decode(s: &str) -> Result<u128> {
    ensure!(!s.is_empty(), "empty base57");
    s.bytes().try_fold(0u128, |acc, b| {
        let digit = ALPHABET
            .iter()
            .position(|v| *v == b)
            .context("invalid base57 digit")?;
        acc.checked_mul(57)
            .and_then(|v| v.checked_add(digit as u128))
            .context("base57 overflow")
    })
}
pub fn object_name(key: &ContentKey, extension: &str) -> Result<String> {
    ensure!(
        key.length <= i64::MAX as u64,
        "length exceeds shared script codec"
    );
    ensure!(
        extension.is_empty() || extension.starts_with('.'),
        "extension must begin with dot"
    );
    ensure!(
        !extension.contains(['/', '\\', '\0']),
        "invalid object extension"
    );
    Ok(format!(
        "{}_{}{}",
        encode(u128::from_be_bytes(key.hash.0), 22)?,
        encode(key.length as u128, 0)?,
        extension
    ))
}
pub fn parse_name(name: &str) -> Result<ContentKey> {
    let bytes = name.as_bytes();
    ensure!(
        bytes.len() >= 24 && bytes[22] == b'_',
        "invalid object name"
    );
    ensure!(bytes[..22].is_ascii(), "invalid hash field");
    let tail = &name[23..];
    let end = tail.bytes().take_while(|v| ALPHABET.contains(v)).count();
    ensure!(end > 0, "missing object length");
    let ext = &tail[end..];
    ensure!(
        ext.is_empty() || ext.starts_with('.'),
        "invalid object suffix"
    );
    ensure!(!ext.contains(['/', '\\', '\0']), "invalid object extension");
    Ok(ContentKey {
        hash: ContentHash(decode(&name[..22])?.to_be_bytes()),
        length: i64::try_from(decode(&tail[..end])?)? as u64,
    })
}
pub fn shard(name: &str) -> Result<String> {
    parse_name(name)?;
    Ok(name[..2].to_ascii_lowercase())
}
pub fn validate_hash(hash: &str) -> Result<()> {
    ensure!(
        hash.len() == 32
            && hash
                .bytes()
                .all(|b| b.is_ascii_digit() || (b'A'..=b'F').contains(&b)),
        "invalid canonical hash"
    );
    Ok(())
}
// Implements: LLR-157, LLR-174. Conservative portable profile, exact spelling retained.
pub fn validate_path(path: &str) -> Result<()> {
    ensure!(
        !path.is_empty() && !path.starts_with('/'),
        "empty or rooted recorded path"
    );
    for part in path.split('/') {
        ensure!(
            !part.is_empty() && part != "." && part != "..",
            "invalid relative component"
        );
        ensure!(
            !part.ends_with([' ', '.']),
            "nonportable trailing character"
        );
        ensure!(
            !part
                .chars()
                .any(|c| c.is_control() || "\\:*?\"<>|".contains(c)),
            "nonportable component"
        );
        let stem: String = part
            .split('.')
            .next()
            .unwrap_or("")
            .trim_end()
            .nfkc()
            .flat_map(char::to_uppercase)
            .collect();
        ensure!(
            !["CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$"].contains(&stem.as_str())
                && !(stem.len() == 4
                    && (stem.starts_with("COM") || stem.starts_with("LPT"))
                    && stem.as_bytes()[3].is_ascii_digit()),
            "reserved component"
        );
    }
    Ok(())
}
pub fn path_key(path: &str) -> String {
    path.nfd().default_case_fold().nfd().collect()
}
/// Every parent of a recorded path, nearest first.
pub fn ancestors(path: &str) -> impl Iterator<Item = &str> {
    std::iter::successors(Some(path), |p| p.rsplit_once('/').map(|(head, _)| head)).skip(1)
}
/// Lower-case extension of a recorded name, without its dot.
pub fn lower_extension(name: &str) -> String {
    Path::new(name)
        .extension()
        .and_then(|v| v.to_str())
        .unwrap_or("")
        .to_ascii_lowercase()
}
fn reader(path: &Path, header: &[&str]) -> Result<csv::Reader<File>> {
    let mut reader = csv::ReaderBuilder::new().flexible(false).from_path(path)?;
    ensure!(
        reader.headers()?.iter().eq(header.iter().copied()),
        "unsupported metadata header in {}",
        path.display()
    );
    Ok(reader)
}
// Implements: LLR-164. Strict file-record admission never silently loses a duplicate row.
pub fn read_manifest(path: &Path) -> Result<Vec<FileRow>> {
    let mut seen = BTreeSet::new();
    let mut rows = Vec::new();
    for row in reader(path, &FILE_HEADER)?.deserialize::<FileRow>() {
        let row = row?;
        validate_path(&row.relative_path)?;
        ensure!(row.length <= i64::MAX as u64, "unsupported content length");
        ensure!(row.storage == "Hash", "unsupported storage form");
        ensure!(
            row.compressed == "Yes" || row.compressed == "No",
            "invalid compressed flag"
        );
        if !row.data_path.is_empty() {
            ensure!(
                parse_name(&row.data_path)? == row.key(),
                "object name/identity mismatch"
            );
        }
        ensure!(
            seen.insert(path_key(&row.relative_path)),
            "colliding file paths"
        );
        rows.push(row);
    }
    for key in &seen {
        for parent in ancestors(key) {
            ensure!(!seen.contains(parent), "file ancestor collision");
        }
    }
    Ok(rows)
}
fn validate_directory(row: &DirectoryRow) -> Result<()> {
    validate_path(&row.relative_path)?;
    match row.kind.as_str() {
        "Directory" => ensure!(row.target.is_empty(), "ordinary directory has link target"),
        "FolderLink" => {
            if row.target != "." {
                validate_path(&row.target)?;
            }
        }
        _ => bail!("unsupported directory entry kind"),
    }
    Ok(())
}
pub fn read_directories(path: &Path) -> Result<Vec<DirectoryRow>> {
    let mut seen = BTreeSet::new();
    let mut rows = Vec::new();
    for row in reader(path, &DIR_HEADER)?.deserialize::<DirectoryRow>() {
        let row = row?;
        validate_directory(&row)?;
        ensure!(
            seen.insert(path_key(&row.relative_path)),
            "colliding directory paths"
        );
        rows.push(row);
    }
    Ok(rows)
}
/// Validate the published pair. Readers may still recover independent files
/// from an interrupted checkpoint whose older supplemental table conflicts.
pub fn validate_records(rows: &[impl AsRef<FileRow>], dirs: &[DirectoryRow]) -> Result<()> {
    let mut files = BTreeSet::new();
    let mut parents = BTreeSet::new();
    for row in rows.iter().map(AsRef::as_ref) {
        validate_path(&row.relative_path)?;
        ensure!(
            files.insert(path_key(&row.relative_path)),
            "colliding file paths"
        );
        let key = path_key(&row.relative_path);
        parents.extend(ancestors(&key).map(str::to_owned));
    }
    ensure!(files.is_disjoint(&parents), "file ancestor collision");
    let mut directory_keys = BTreeSet::new();
    let mut links = BTreeSet::new();
    for row in dirs {
        validate_directory(row)?;
        let key = path_key(&row.relative_path);
        ensure!(
            directory_keys.insert(key.clone()),
            "colliding directory paths"
        );
        ensure!(!files.contains(&key), "file/directory collision");
        for parent in ancestors(&key) {
            ensure!(!files.contains(parent), "directory beneath file");
        }
        if row.kind == "FolderLink" {
            ensure!(!parents.contains(&key), "file beneath folder link");
            links.insert(key);
        }
    }
    for row in dirs {
        let key = path_key(&row.relative_path);
        for parent in ancestors(&key) {
            ensure!(!links.contains(parent), "metadata beneath folder link");
        }
        if row.kind == "FolderLink" && row.target != "." {
            let target = path_key(&row.target);
            ensure!(
                !links.contains(&target)
                    && (directory_keys.contains(&target) || parents.contains(&target)),
                "folder link target not captured"
            );
        }
    }
    Ok(())
}
fn write_csv<T: Serialize>(output: impl Write, header: &[&str], rows: &[T]) -> Result<()> {
    let mut writer = csv::WriterBuilder::new()
        .has_headers(false)
        .quote_style(csv::QuoteStyle::Always)
        .from_writer(output);
    writer.write_record(header)?;
    for row in rows {
        writer.serialize(row)?;
    }
    Ok(writer.flush()?)
}
fn sorted_by_path<'a, T: 'a>(
    rows: impl IntoIterator<Item = &'a T>,
    path: fn(&T) -> &str,
) -> Vec<&'a T> {
    let mut sorted: Vec<_> = rows.into_iter().collect();
    sorted.sort_by(|a, b| path(a).encode_utf16().cmp(path(b).encode_utf16()));
    sorted
}
/// Compare the same canonical records as serialization, without two CSV buffers.
pub fn same_manifest(a: &[FileRow], b: &[impl AsRef<FileRow>]) -> bool {
    a.len() == b.len()
        && sorted_by_path(a, |r| &r.relative_path)
            == sorted_by_path(b.iter().map(AsRef::as_ref), |r| &r.relative_path)
}
pub fn same_directories(a: &[DirectoryRow], b: &[DirectoryRow]) -> bool {
    a.len() == b.len()
        && sorted_by_path(a, |r| &r.relative_path) == sorted_by_path(b, |r| &r.relative_path)
}
pub fn manifest_bytes(rows: &[FileRow]) -> Result<Vec<u8>> {
    let mut bytes = Vec::new();
    write_manifest(&mut bytes, rows)?;
    Ok(bytes)
}
pub fn write_manifest<'a>(
    output: impl Write,
    rows: impl IntoIterator<Item = &'a FileRow>,
) -> Result<()> {
    write_csv(
        output,
        &FILE_HEADER,
        &sorted_by_path(rows, |r| &r.relative_path),
    )
}
pub fn directory_bytes(rows: &[DirectoryRow]) -> Result<Vec<u8>> {
    let mut bytes = Vec::new();
    write_csv(
        &mut bytes,
        &DIR_HEADER,
        &sorted_by_path(rows, |r| &r.relative_path),
    )?;
    Ok(bytes)
}

#[cfg(test)]
mod probe_tests {
    use super::*;

    fn data(n: usize) -> Vec<u8> {
        let mut s = 0x2545F4914F6CDD1D_u64;
        (0..n)
            .map(|_| {
                s ^= s << 13;
                s ^= s >> 7;
                s ^= s << 17;
                (s >> 32) as u8
            })
            .collect()
    }
    /// Reads at most `step` bytes at a time, so windows straddle and split reads.
    struct Short<'a>(&'a [u8], usize);
    impl Read for Short<'_> {
        fn read(&mut self, out: &mut [u8]) -> std::io::Result<usize> {
            let n = self.0.len().min(self.1).min(out.len());
            out[..n].copy_from_slice(&self.0[..n]);
            self.0 = &self.0[n..];
            Ok(n)
        }
    }
    fn expected<'a>(bytes: &'a [u8], plan: &[(u64, usize)]) -> Vec<&'a [u8]> {
        plan.iter()
            .map(|&(s, l)| &bytes[s as usize..s as usize + l])
            .collect()
    }

    #[test]
    fn plan_sizes_and_offsets() {
        const W: u64 = PROBE_WINDOW;
        assert!(probe_plan(0).is_empty());
        assert!(probe_plan(W).is_empty());
        assert_eq!(probe_plan(W + 1), vec![(0, W as usize + 1)]);
        assert_eq!(probe_plan(9 * W - 1), vec![(0, 9 * W as usize - 1)]);
        let plan = probe_plan(9 * W);
        let starts: Vec<u64> = plan.iter().map(|p| p.0).collect();
        assert_eq!(starts, (1..=7).map(|k| k * W).collect::<Vec<_>>());
        // Interior, ordered, never touching either end, for any length.
        for length in [
            9 * W + 5,
            16 * 1024 * 1024 + 3,
            u64::MAX / 2,
            i64::MAX as u64,
        ] {
            let plan = probe_plan(length);
            assert_eq!(plan.len(), 7);
            let mut previous_end = 0;
            for &(start, len) in &plan {
                assert!(start > 0 && start >= previous_end, "{length}");
                previous_end = start + len as u64;
                assert!(previous_end < length, "{length}");
            }
        }
        // floor(k * (length - 256 KiB) / 8)
        let length = 16 * 1024 * 1024 + 3;
        assert_eq!(probe_plan(length)[2].0, 3 * (length - W) / 8);
    }

    #[test]
    fn windows_survive_straddling_and_short_reads() {
        let bytes = data(3 * 1024 * 1024 + 17);
        let plan = probe_plan(bytes.len() as u64);
        for step in [1_000_003, 777, 65_537, 256 * 1024, 5 * 1024 * 1024] {
            let mut sampler = WindowSampler::new(bytes.len() as u64);
            let key = copy_hash_sampled(Short(&bytes, step), std::io::sink(), Some(&mut sampler))
                .unwrap();
            assert_eq!(
                key,
                copy_hash(&bytes[..], std::io::sink()).unwrap(),
                "{step}"
            );
            assert!(!sampler.whole_file());
            assert_eq!(
                sampler.windows().unwrap(),
                expected(&bytes, &plan),
                "{step}"
            );
        }
    }

    #[test]
    fn a_small_file_is_one_whole_sample() {
        let bytes = data(300 * 1024);
        let mut sampler = WindowSampler::new(bytes.len() as u64);
        copy_hash_sampled(Short(&bytes, 4096), std::io::sink(), Some(&mut sampler)).unwrap();
        assert!(sampler.whole_file());
        assert_eq!(sampler.windows().unwrap(), vec![&bytes[..]]);
        assert!(WindowSampler::new(PROBE_WINDOW).windows().is_none());
    }

    #[test]
    fn a_shrinking_stream_is_incomplete_and_never_panics() {
        let bytes = data(3 * 1024 * 1024);
        for cut in [0, 1, 700_000, 10 * 256 * 1024] {
            let mut sampler = WindowSampler::new(bytes.len() as u64);
            copy_hash_sampled(
                Short(&bytes[..cut], 99_999),
                std::io::sink(),
                Some(&mut sampler),
            )
            .unwrap();
            assert!(sampler.windows().is_none(), "{cut}");
        }
    }

    #[test]
    fn a_growing_stream_never_enlarges_the_buffer() {
        let bytes = data(6 * 1024 * 1024);
        let planned = 3 * 1024 * 1024;
        let plan = probe_plan(planned as u64);
        let mut sampler = WindowSampler::new(planned as u64);
        let capacity = sampler.buffer.len();
        assert_eq!(capacity, 7 * PROBE_WINDOW as usize);
        copy_hash_sampled(Short(&bytes, 300_000), std::io::sink(), Some(&mut sampler)).unwrap();
        assert_eq!(sampler.buffer.len(), capacity);
        assert_eq!(sampler.windows().unwrap(), expected(&bytes, &plan));
    }

    #[test]
    fn offset_overflow_marks_the_sample_failed() {
        let mut sampler = WindowSampler::new(3 * 1024 * 1024);
        sampler.position = u64::MAX - 1;
        sampler.feed(&[0; 16]);
        assert!(sampler.windows().is_none());
    }
}
