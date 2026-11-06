//! Fresh private corpus: real source files and independent valid stored objects.
//! Bypasses initial capture cost to measure index/unchanged-run cardinality, not durability.
use anyhow::{Context, Result, ensure};
use chrono::{DateTime, Utc};
use filebackup::{format, platform, store::Store};
use std::{fs, io, path::PathBuf};

fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let root = PathBuf::from(args.next().context("fresh absolute root required")?);
    let count: u64 = args.next().context("file count required")?.parse()?;
    ensure!(
        root.is_absolute() && !root.exists(),
        "fresh absolute root required"
    );
    ensure!((1..=1_000_000).contains(&count), "file count must be 1..1M");
    let mut ancestor = root.parent().context("root has no parent")?;
    while !ancestor.exists() {
        ancestor = ancestor.parent().context("no existing ancestor")?;
    }
    ensure!(
        platform::available(ancestor)
            .is_some_and(|free| free > count * 16384 + 5 * 1024 * 1024 * 1024),
        "need corpus allocation plus 5 GiB reserve"
    );
    let source = root.join("source");
    fs::create_dir_all(&source)?;
    fs::write(
        root.join("BENCHMARK.json"),
        serde_json::to_vec(&serde_json::json!({
            "fixture":"FileBackup cardinality", "files":count, "bytes_per_file":8
        }))?,
    )?;
    let store = Store::new(&root.join("store"));
    store.initialize()?;
    let mut writer = csv::WriterBuilder::new()
        .quote_style(csv::QuoteStyle::Always)
        .from_path(store.current.join(format::MANIFEST))?;
    let mut dirs = Vec::new();
    for n in 0..count {
        let dir = format!("d{:05}", n / 1000);
        if n % 1000 == 0 {
            fs::create_dir(source.join(&dir))?;
            dirs.push(format::DirectoryRow {
                relative_path: dir.clone(),
                attributes: String::new(),
                kind: "Directory".into(),
                target: String::new(),
            });
        }
        let relative = format!("{dir}/file-{n:07}.bin");
        let bytes = n.to_le_bytes();
        let key = format::copy_hash(&bytes[..], io::sink())?;
        let name = format::object_name(&key, ".bin")?;
        let object = store.path(&name)?;
        fs::create_dir_all(object.parent().unwrap())?;
        // Independent files: source mutation must not alter immutable stored bytes.
        fs::write(&object, bytes)?;
        let path = source.join(&relative);
        fs::write(&path, bytes)?;
        let time: DateTime<Utc> = fs::metadata(path)?.modified()?.into();
        writer.serialize(format::FileRow {
            data_path: name,
            relative_path: relative,
            length: key.length,
            modified: time.to_rfc3339_opts(chrono::SecondsFormat::Nanos, true),
            hash: key.hash,
            compressed: "No".into(),
            storage: "Hash".into(),
            duplicate: String::new(),
            media: String::new(),
        })?;
        if (n + 1) % 100_000 == 0 {
            eprintln!("Created {} source/object pairs", n + 1);
        }
    }
    writer.flush()?;
    fs::write(
        store.current.join(format::DIRECTORIES),
        format::directory_bytes(&dirs)?,
    )?;
    fs::write(
        root.join("config.json"),
        serde_json::to_vec(&serde_json::json!({
        "ConfigVersion":3,"BackupSets":[{"Name":"cardinality","SourcePath":source,"StorePath":store.root,
        "CompressEnabled":false,"BrowseView":"off","HashRecalcFreq":"N"}]}))?,
    )?;
    println!(
        "{}",
        serde_json::json!({"root":root,"source_files":count,"distinct_objects":count,"logical_bytes":count*8,
        "kind":"valid eight-byte objects; initial store assembled by fixture; not full-volume qualification"})
    );
    Ok(())
}
