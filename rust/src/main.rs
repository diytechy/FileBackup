use clap::{Parser, ValueEnum};
use filebackup::{
    config,
    engine::{self, Report},
    maintenance,
};
use std::path::PathBuf;
#[derive(Clone, Copy, ValueEnum)]
enum Action {
    Backup,
    Snapshots,
    Verify,
    Prune,
    View,
    RefreshKits,
    Validate,
    Configure,
}
#[derive(Parser)]
#[command(
    version,
    about = "Native FileBackup with independent PowerShell/bash recovery"
)]
struct Args {
    #[arg(value_enum, default_value = "backup")]
    action: Action,
    #[arg(long)]
    config: PathBuf,
    #[arg(long)]
    deep: bool,
    #[arg(long, requires = "deep")]
    repair_storage: bool,
    #[arg(long)]
    snapshot: Vec<String>,
    #[arg(long)]
    dry_run: bool,
    /// Required only by configure. Uses absolute paths and never overwrites a file.
    #[arg(long)]
    source: Option<PathBuf>,
    #[arg(long)]
    store: Option<PathBuf>,
    #[arg(long)]
    name: Option<String>,
    #[arg(long)]
    no_compress: bool,
    /// Select named sets after validating the complete configuration.
    #[arg(long = "set")]
    sets: Vec<String>,
    #[arg(long)]
    no_mail: bool,
}
fn main() {
    if std::env::args().nth(1).as_deref() == Some("__notification_worker") {
        std::process::exit(filebackup::notify::worker());
    }
    let args = Args::parse();
    if matches!(args.action, Action::Configure) {
        if let Err(e) = configure(&args) {
            eprintln!("Configuration not written: {e:#}");
            std::process::exit(2);
        }
        return;
    }
    if args.source.is_some() || args.store.is_some() || args.name.is_some() || args.no_compress {
        eprintln!("Configuration helper flags require configure");
        std::process::exit(2);
    }
    if (args.deep || args.repair_storage) && !matches!(args.action, Action::Verify)
        || (!args.snapshot.is_empty() || args.dry_run) && !matches!(args.action, Action::Prune)
    {
        eprintln!("Options do not apply to this action");
        std::process::exit(2);
    }
    let config = match config::load(&args.config) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("Configuration refused: {e:#}");
            std::process::exit(2)
        }
    };
    if args
        .sets
        .iter()
        .any(|n| !config.sets.iter().any(|s| s.name == *n))
    {
        eprintln!("Unknown set selector");
        std::process::exit(2);
    }
    let selected: Vec<_> = config
        .sets
        .iter()
        .filter(|s| args.sets.is_empty() || args.sets.contains(&s.name))
        .collect();
    if matches!(args.action, Action::Prune) && selected.len() != 1 {
        eprintln!("Prune requires exactly one --set when the configuration has multiple sets");
        std::process::exit(2);
    }
    let mut exit = 0;
    let mut reports = Vec::new();
    for set in selected {
        let report = match args.action {
            Action::Backup => engine::backup(&config, set),
            Action::Verify => maintenance::verify(set, args.deep, args.repair_storage),
            Action::Prune => maintenance::prune(set, &args.snapshot, args.dry_run),
            Action::View => maintenance::view(set),
            Action::RefreshKits => maintenance::refresh(set),
            Action::Validate => Report::new("validate", &set.name),
            Action::Configure => unreachable!(),
            Action::Snapshots => maintenance::inventory(set),
        };
        if engine::rank(report.code) > engine::rank(exit) {
            exit = report.code;
        }
        println!("{}", serde_json::to_string(&report).unwrap());
        reports.push(report);
    }
    if matches!(args.action, Action::Backup)
        && !args.no_mail
        && let Some(settings) = &config.notification
    {
        let accepted = filebackup::notify::submit(settings, &reports).is_ok();
        println!(
            "{}",
            serde_json::json!({"schema_version":1,"action":"notification","class":if accepted {"submitted"} else {"warning"},"cause":if accepted {"relay_accepted"} else {"submission_unavailable"},"message":if accepted {"Relay accepted the run summary; delivery is not asserted"} else {"Notification unavailable; backup outcome unchanged. Check relay and execution-account credential access."}})
        );
    }
    std::process::exit(exit);
}
fn configure(args: &Args) -> anyhow::Result<()> {
    use anyhow::{Context, ensure};
    ensure!(
        args.sets.is_empty(),
        "set selectors do not apply to configure"
    );
    ensure!(
        !args.deep && !args.repair_storage && args.snapshot.is_empty() && !args.dry_run,
        "action options cannot be combined with configure"
    );
    let source =
        filebackup::platform::resolve(args.source.as_deref().context("--source required")?)?;
    let store = filebackup::platform::resolve(args.store.as_deref().context("--store required")?)?;
    ensure!(
        !filebackup::platform::overlaps(&source, &store),
        "source and store overlap"
    );
    let name = args.name.as_deref().unwrap_or("default");
    ensure!(!name.trim().is_empty(), "name is empty");
    let bytes = serde_json::to_vec_pretty(
        &serde_json::json!({"ConfigVersion":3,"BackupSets":[{"Name":name,"SourcePath":source,"StorePath":store,"HashRecalcFreq":"W","CompressEnabled":!args.no_compress,"CompressProbe":"always","BrowseView":"off"}],"Tools":{},"Secrets":{}}),
    )?;
    let output = std::path::absolute(&args.config)?;
    filebackup::platform::atomic_write(&output, &bytes, false)?;
    eprintln!("Configuration written. Use validate, then backup with this --config path.");
    Ok(())
}
