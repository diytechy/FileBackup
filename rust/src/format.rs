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
pub fn copy_hash(mut input: impl Read, mut output: impl Write) -> Result<ContentKey> {
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
        length = length
            .checked_add(n as u64)
            .context("file length overflow")?;
    }
    Ok(ContentKey {
        hash: ContentHash(hasher.digest128().to_be_bytes()),
        length,
    })
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
