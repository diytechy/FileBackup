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

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub struct ContentKey {
    pub hash: String,
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
    pub hash: String,
    #[serde(rename = "Compressed")]
    pub compressed: String,
    #[serde(rename = "StoredAsHashSize")]
    pub storage: String,
    #[serde(rename = "Duplicate")]
    pub duplicate: String,
    #[serde(rename = "MediaMBPerSec")]
    pub media: String,
}
impl FileRow {
    pub fn key(&self) -> ContentKey {
        ContentKey {
            hash: self.hash.clone(),
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
        hash: format!("{:032X}", hasher.digest128()),
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
    validate_hash(&key.hash)?;
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
        encode(u128::from_str_radix(&key.hash, 16)?, 22)?,
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
        hash: format!("{:032X}", decode(&name[..22])?),
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
        validate_hash(&row.hash)?;
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
        let mut parent = key.as_str();
        while let Some((p, _)) = parent.rsplit_once('/') {
            ensure!(!seen.contains(p), "file ancestor collision");
            parent = p;
        }
    }
    Ok(rows)
}
pub fn read_directories(path: &Path) -> Result<Vec<DirectoryRow>> {
    let mut seen = BTreeSet::new();
    let mut rows = Vec::new();
    for row in reader(path, &DIR_HEADER)?.deserialize::<DirectoryRow>() {
        let row = row?;
        validate_path(&row.relative_path)?;
        ensure!(
            seen.insert(path_key(&row.relative_path)),
            "colliding directory paths"
        );
        match row.kind.as_str() {
            "Directory" => ensure!(row.target.is_empty(), "ordinary directory has link target"),
            "FolderLink" => {
                if row.target != "." {
                    validate_path(&row.target)?;
                }
            }
            _ => bail!("unsupported directory entry kind"),
        }
        rows.push(row);
    }
    Ok(rows)
}
/// Validate the published pair. Readers may still recover independent files
/// from an interrupted checkpoint whose older supplemental table conflicts.
pub fn validate_records(rows: &[FileRow], dirs: &[DirectoryRow]) -> Result<()> {
    let mut files = BTreeSet::new();
    let mut ancestors = BTreeSet::new();
    for row in rows {
        validate_path(&row.relative_path)?;
        validate_hash(&row.hash)?;
        ensure!(
            files.insert(path_key(&row.relative_path)),
            "colliding file paths"
        );
        let key = path_key(&row.relative_path);
        let mut parent = key.as_str();
        while let Some((p, _)) = parent.rsplit_once('/') {
            ancestors.insert(p.to_owned());
            parent = p;
        }
    }
    ensure!(files.is_disjoint(&ancestors), "file ancestor collision");
    let mut directory_keys = BTreeSet::new();
    let mut links = BTreeSet::new();
    for row in dirs {
        validate_path(&row.relative_path)?;
        let key = path_key(&row.relative_path);
        ensure!(
            directory_keys.insert(key.clone()),
            "colliding directory paths"
        );
        ensure!(!files.contains(&key), "file/directory collision");
        let mut parent = key.as_str();
        while let Some((p, _)) = parent.rsplit_once('/') {
            ensure!(!files.contains(p), "directory beneath file");
            parent = p;
        }
        match row.kind.as_str() {
            "Directory" => ensure!(row.target.is_empty(), "ordinary directory has link target"),
            "FolderLink" => {
                ensure!(!ancestors.contains(&key), "file beneath folder link");
                if row.target != "." {
                    validate_path(&row.target)?;
                }
                links.insert(key);
            }
            _ => bail!("unsupported directory kind"),
        }
    }
    for row in dirs {
        let key = path_key(&row.relative_path);
        let mut parent = key.as_str();
        while let Some((p, _)) = parent.rsplit_once('/') {
            ensure!(!links.contains(p), "metadata beneath folder link");
            parent = p;
        }
        if row.kind == "FolderLink" && row.target != "." {
            let target = path_key(&row.target);
            ensure!(
                !links.contains(&target)
                    && (directory_keys.contains(&target) || ancestors.contains(&target)),
                "folder link target not captured"
            );
        }
    }
    Ok(())
}
pub fn paths_conflict(a: &str, b: &str) -> bool {
    let a = path_key(a);
    let b = path_key(b);
    a == b || a.starts_with(&(b.clone() + "/")) || b.starts_with(&(a + "/"))
}
fn csv_bytes<T: Serialize>(header: &[&str], rows: &[T]) -> Result<Vec<u8>> {
    let mut writer = csv::WriterBuilder::new()
        .has_headers(false)
        .quote_style(csv::QuoteStyle::Always)
        .from_writer(Vec::new());
    writer.write_record(header)?;
    for row in rows {
        writer.serialize(row)?;
    }
    Ok(writer.into_inner()?)
}
pub fn manifest_bytes(rows: &[FileRow]) -> Result<Vec<u8>> {
    let mut sorted: Vec<_> = rows.iter().collect();
    sorted.sort_by(|a, b| {
        a.relative_path
            .encode_utf16()
            .cmp(b.relative_path.encode_utf16())
    });
    csv_bytes(&FILE_HEADER, &sorted)
}
pub fn directory_bytes(rows: &[DirectoryRow]) -> Result<Vec<u8>> {
    let mut sorted: Vec<_> = rows.iter().collect();
    sorted.sort_by(|a, b| {
        a.relative_path
            .encode_utf16()
            .cmp(b.relative_path.encode_utf16())
    });
    csv_bytes(&DIR_HEADER, &sorted)
}
