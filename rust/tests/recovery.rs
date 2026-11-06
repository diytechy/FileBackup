use filebackup::{config, engine, format, maintenance, store::Store, tools};
use std::{fs, path::Path, process::Command};

fn fixture(compress: bool) -> (tempfile::TempDir, config::Config) {
    let tmp = tempfile::tempdir().unwrap();
    fs::create_dir(tmp.path().join("source")).unwrap();
    fs::write(tmp.path().join("source/file.txt"), vec![b'x'; 300_000]).unwrap();
    let path = tmp.path().join("config.json");
    fs::write(
        &path,
        serde_json::to_vec(&serde_json::json!({"ConfigVersion":3,
        "BackupSets":[{"Name":"restore","SourcePath":tmp.path().join("source"),
        "StorePath":tmp.path().join("store"),"CompressEnabled":compress}]}))
        .unwrap(),
    )
    .unwrap();
    let cfg = config::load(&path).unwrap();
    let report = engine::backup(&cfg, &cfg.sets[0]);
    assert_eq!(report.code, 0, "{report:?}");
    (tmp, cfg)
}
fn restore(kit: &Path, store: &Store, target: &Path, previous: bool, bad_tool: bool) -> i32 {
    restore_from(kit, &store.current, store, target, previous, bad_tool)
}
fn restore_from(
    kit: &Path,
    records: &Path,
    store: &Store,
    target: &Path,
    previous: bool,
    bad_tool: bool,
) -> i32 {
    #[cfg(windows)]
    let mut command = {
        let mut c = Command::new("pwsh");
        // PowerShell's AuthorizationManager rejects verbatim-prefixed script paths;
        // launch the same local file using its ordinary DOS spelling.
        let script = kit.join("RECONSTRUCT.ps1").to_string_lossy().into_owned();
        let script = script.strip_prefix("\\\\?\\").unwrap_or(&script);
        c.args(["-NoProfile", "-File"])
            .arg(script)
            .arg("-TargetRoot")
            .arg(target)
            .arg("-RecordRoot")
            .arg(records)
            .arg("-StoreRootOverride")
            .arg(&store.root)
            .args(["-NonInteractive", "-ExitCode"]);
        if previous {
            c.arg("-Previous");
        }
        if bad_tool {
            c.arg("-SevenZipPath")
                .arg(target.with_extension("missing-tool"));
        }
        c
    };
    #[cfg(unix)]
    let mut command = {
        let mut c = Command::new("bash");
        c.arg(kit.join("reconstruct.sh"))
            .arg("--target-root")
            .arg(target)
            .arg("--record-root")
            .arg(records)
            .arg("--store-root")
            .arg(&store.root)
            .arg("--non-interactive");
        if previous {
            c.arg("--previous");
        }
        if bad_tool {
            c.arg("--seven-zip")
                .arg(target.with_extension("missing-tool"));
        }
        c
    };
    command
        .stdin(std::process::Stdio::null())
        .status()
        .unwrap()
        .code()
        .unwrap()
}
#[test]
fn mixed_live_kit_refuses_and_preserved_kit_still_recovers() {
    let (tmp, cfg) = fixture(false);
    let store = Store::new(&cfg.sets[0].store);
    assert_eq!(maintenance::refresh(&cfg.sets[0]).code, 0);
    fs::write(store.current.join("path-keys.tsv"), b"partial replacement").unwrap();
    let target = tmp.path().join("refused");
    assert_eq!(restore(&store.current, &store, &target, false, false), 2);
    assert!(!target.exists());
    let previous = store.current.join("RECOVERY.previous");
    let target = tmp.path().join("recovered");
    assert_eq!(restore(&previous, &store, &target, false, false), 0);
    assert_eq!(
        format::hash_file(&target.join("file.txt")).unwrap(),
        format::hash_file(&cfg.sets[0].source.join("file.txt")).unwrap()
    );
    assert_eq!(maintenance::refresh(&cfg.sets[0]).code, 0);
    assert_eq!(
        restore(&previous, &store, &tmp.path().join("again"), false, false),
        0
    );
}
#[test]
fn explicit_previous_does_not_mix_in_current_directory_metadata() {
    let (tmp, cfg) = fixture(false);
    let store = Store::new(&cfg.sets[0].store);
    fs::copy(
        store.current.join(format::MANIFEST),
        store.current.join("MANIFEST.csv.prev"),
    )
    .unwrap();
    assert_eq!(
        restore(
            &store.current,
            &store,
            &tmp.path().join("current"),
            false,
            false
        ),
        0
    );
    assert_eq!(
        restore(
            &store.current,
            &store,
            &tmp.path().join("previous"),
            true,
            false
        ),
        1
    );
    assert!(tmp.path().join("previous/file.txt").exists());
}
#[test]
fn missing_extractor_precedes_writes_and_oversized_archive_keeps_existing_target() {
    let (tmp, cfg) = fixture(true);
    let store = Store::new(&cfg.sets[0].store);
    let target = tmp.path().join("missing-tool");
    assert_eq!(restore(&store.current, &store, &target, false, true), 4);
    assert!(!target.exists());
    let object = store
        .index()
        .unwrap()
        .into_values()
        .next()
        .unwrap()
        .remove(0);
    let big = tmp.path().join("big.txt");
    let archive = tmp.path().join("wrong.7z");
    fs::write(&big, vec![b'y'; 600_000]).unwrap();
    tools::compress(&big, &archive).unwrap();
    fs::copy(&archive, &object.path).unwrap();
    let target = tmp.path().join("damaged");
    fs::create_dir(&target).unwrap();
    fs::write(target.join("file.txt"), b"existing owner bytes").unwrap();
    assert_eq!(restore(&store.current, &store, &target, false, false), 1);
    assert_eq!(
        fs::read(target.join("file.txt")).unwrap(),
        b"existing owner bytes"
    );
    assert_eq!(
        fs::read_dir(&target).unwrap().count(),
        1,
        "failed staging residue"
    );
}

#[test]
fn existing_directory_cannot_be_reported_as_a_restored_file() {
    let (tmp, cfg) = fixture(false);
    let store = Store::new(&cfg.sets[0].store);
    let target = tmp.path().join("occupied");
    fs::create_dir_all(target.join("file.txt")).unwrap();
    assert_eq!(restore(&store.current, &store, &target, false, false), 4);
    assert_eq!(fs::read_dir(target.join("file.txt")).unwrap().count(), 0);
    assert_eq!(fs::read_dir(&target).unwrap().count(), 1);
}
#[test]
fn verified_raw_supply_does_not_require_an_extractor_for_a_bad_duplicate() {
    let (tmp, cfg) = fixture(false);
    let store = Store::new(&cfg.sets[0].store);
    let object = store
        .index()
        .unwrap()
        .into_values()
        .next()
        .unwrap()
        .remove(0);
    fs::write(
        object.path.with_extension("bad"),
        [0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c, 0],
    )
    .unwrap();
    let target = tmp.path().join("raw-only");
    assert_eq!(restore(&store.current, &store, &target, false, true), 0);
    assert_eq!(
        format::hash_file(&target.join("file.txt")).unwrap(),
        object.key
    );
}
#[test]
fn relative_target_is_refused_before_any_write() {
    let (_tmp, cfg) = fixture(false);
    let store = Store::new(&cfg.sets[0].store);
    assert_eq!(
        restore(
            &store.current,
            &store,
            Path::new("relative-target"),
            false,
            false
        ),
        2
    );
}

#[test]
fn target_cannot_contain_detached_records_or_the_executing_kit() {
    let (tmp, cfg) = fixture(false);
    let store = Store::new(&cfg.sets[0].store);
    let target = tmp.path().join("output");
    let records = target.join("records");
    fs::create_dir_all(&records).unwrap();
    let mut rows = format::read_manifest(&store.current.join(format::MANIFEST)).unwrap();
    rows[0].relative_path = "records/DIRECTORIES.csv".into();
    fs::write(
        records.join(format::MANIFEST),
        format::manifest_bytes(&rows).unwrap(),
    )
    .unwrap();
    fs::copy(
        store.current.join(format::DIRECTORIES),
        records.join(format::DIRECTORIES),
    )
    .unwrap();
    let before = fs::read(records.join(format::DIRECTORIES)).unwrap();
    assert_eq!(
        restore_from(&store.current, &records, &store, &target, false, false),
        2
    );
    assert_eq!(fs::read(records.join(format::DIRECTORIES)).unwrap(), before);
    let detached_kit = target.join("kit");
    fs::create_dir(&detached_kit).unwrap();
    filebackup::kit::publish(&detached_kit).unwrap();
    assert_eq!(restore(&detached_kit, &store, &target, false, false), 2);
    assert!(!target.join("file.txt").exists());
}

#[cfg(unix)]
#[test]
fn unreadable_candidate_can_fall_back_but_target_write_failure_is_a_host_error() {
    use std::os::unix::fs::PermissionsExt;
    let (tmp, cfg) = fixture(false);
    let store = Store::new(&cfg.sets[0].store);
    let object = store
        .index()
        .unwrap()
        .into_values()
        .next()
        .unwrap()
        .remove(0);
    let history = store.history.join("2025_01_01_00_00_00");
    fs::create_dir(&history).unwrap();
    fs::copy(&object.path, history.join(&object.name)).unwrap();
    let bin = tmp.path().join("bin");
    fs::create_dir(&bin).unwrap();
    // Model a source read error independently of user/root permission profiles.
    for tool in ["cp", "xxh128sum", "xxhsum"] {
        let real = Command::new("which").arg(tool).output().unwrap();
        assert!(real.status.success());
        let real = String::from_utf8(real.stdout).unwrap();
        let script = format!(
            "#!/usr/bin/env bash\nif [[ $FAIL_SOURCE == 1 ]]; then\n  for arg in \"$@\"; do [[ $arg == \"$BAD_OBJECT\" ]] && exit 1; done\nelif [[ {} == cp ]]; then exit 1; fi\nexec {} \"$@\"\n",
            tool,
            real.trim()
        );
        fs::write(bin.join(tool), script).unwrap();
        fs::set_permissions(bin.join(tool), fs::Permissions::from_mode(0o755)).unwrap();
    }
    for (label, source_error, expected) in [("source-error", "1", 0), ("target-error", "0", 4)] {
        let target = tmp.path().join(label);
        let status = Command::new("bash")
            .arg(store.current.join("reconstruct.sh"))
            .arg("--target-root")
            .arg(&target)
            .env(
                "PATH",
                format!("{}:{}", bin.display(), std::env::var("PATH").unwrap()),
            )
            .env("BAD_OBJECT", &object.path)
            .env("FAIL_SOURCE", source_error)
            .status()
            .unwrap();
        assert_eq!(status.code(), Some(expected));
        if expected == 0 {
            assert_eq!(
                format::hash_file(&target.join("file.txt")).unwrap(),
                object.key
            );
        } else {
            assert!(!target.join("file.txt").exists());
        }
    }
}
