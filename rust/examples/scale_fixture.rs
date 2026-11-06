//! Synthetic metadata-cardinality probe, NOT a full-volume qualification corpus.
use anyhow::{Context, Result, ensure};
use filebackup::{config, engine, format, store::Store};
use std::{fs, path::PathBuf};
fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let root = PathBuf::from(
        args.next()
            .context("fresh absolute fixture directory required")?,
    );
    let rows: usize = args.next().context("row count required")?.parse()?;
    let states: usize = args.next().unwrap_or_else(|| "0".into()).parse()?;
    ensure!(
        root.is_absolute() && !root.exists(),
        "choose a fresh absolute directory"
    );
    ensure!(
        rows > 0 && rows <= 1_000_000 && states <= 365,
        "probe bounds exceeded"
    );
    fs::create_dir_all(root.join("source"))?;
    fs::write(root.join("source/seed"), b"metadata probe payload")?;
    let config_path = root.join("config.json");
    fs::write(
        &config_path,
        serde_json::to_vec(&serde_json::json!({
        "ConfigVersion":3,"BackupSets":[{"Name":"metadata-probe",
        "SourcePath":root.join("source"),"StorePath":root.join("store"),
        "CompressEnabled":false,"BrowseView":"off"}]}))?,
    )?;
    let cfg = config::load(&config_path)?;
    ensure!(
        engine::backup(&cfg, &cfg.sets[0]).code == 0,
        "fixture seed failed"
    );
    let store = Store::new(&cfg.sets[0].store);
    let mut row = format::read_manifest(&store.current.join(format::MANIFEST))?.remove(0);
    let mut writer = csv::WriterBuilder::new()
        .quote_style(csv::QuoteStyle::Always)
        .from_path(store.current.join(format::MANIFEST))?;
    for n in 0..rows {
        row.relative_path = format!("file-{n:07}.txt");
        writer.serialize(&row)?;
    }
    writer.flush()?;
    drop(writer);
    for n in 0..states {
        let date =
            chrono::NaiveDate::from_ymd_opt(2025, 1, 1).unwrap() + chrono::Duration::days(n as i64);
        let state = store
            .history
            .join(date.format("%Y_%m_%d_00_00_00").to_string());
        fs::create_dir(&state)?;
        // Immutable hard-linked definitions save test disk; readers still parse each state.
        fs::hard_link(
            store.current.join(format::MANIFEST),
            state.join(format::MANIFEST),
        )?;
        fs::copy(
            store.current.join(format::DIRECTORIES),
            state.join(format::DIRECTORIES),
        )?;
    }
    println!(
        "{}",
        serde_json::json!({"fixture":root,"rows_per_state":rows,
        "historical_states":states,"distinct_objects":1,"physical_source_files":1,
        "kind":"synthetic metadata cardinality; not 2 TiB qualification"})
    );
    Ok(())
}
