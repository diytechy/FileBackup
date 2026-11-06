use filebackup::{config, engine, format, store::Store};
use std::fs;
fn fixture(compress: bool) -> (tempfile::TempDir, config::Config) {
    let tmp = tempfile::tempdir().unwrap();
    let source = tmp.path().join("source");
    fs::create_dir(&source).unwrap();
    let path = tmp.path().join("config.json");
    fs::write(&path,serde_json::to_vec(&serde_json::json!({"ConfigVersion":3,"BackupSets":[{"Name":"fixture","SourcePath":source,"StorePath":tmp.path().join("store"),"CompressEnabled":compress,"HashRecalcFreq":"A"}]})).unwrap()).unwrap();
    let config = config::load(&path).unwrap();
    (tmp, config)
}
#[test]
fn backup_dedup_noop_history_and_empty_folder_changes() {
    let (_tmp, config) = fixture(false);
    let set = &config.sets[0];
    fs::write(set.source.join("one.txt"), b"same bytes").unwrap();
    fs::write(set.source.join("two.bin"), b"same bytes").unwrap();
    let report = engine::backup(&config, set);
    assert_eq!(report.code, 0, "{report:?}");
    let store = Store::new(&set.store);
    assert_eq!(store.index().unwrap().len(), 1);
    let report = engine::backup(&config, set);
    assert_eq!(report.code, 0, "{report:?}");
    assert_eq!(store.states().unwrap().len(), 1, "no-op made a snapshot");
    fs::create_dir(set.source.join("only-empty-folder")).unwrap();
    let report = engine::backup(&config, set);
    assert_eq!(report.code, 0, "{report:?}");
    assert_eq!(
        store.states().unwrap().len(),
        2,
        "folder-only change lost history"
    );
    fs::write(set.source.join("one.txt"), b"new bytes").unwrap();
    let report = engine::backup(&config, set);
    assert_eq!(report.code, 0, "{report:?}");
    assert_eq!(store.states().unwrap().len(), 3);
    for state in store.states().unwrap() {
        for row in format::read_manifest(&state.join(format::MANIFEST)).unwrap() {
            assert!(store.index().unwrap().contains_key(&row.key()));
        }
    }
    assert!(!store.current.join("MANIFEST.csv.prev").exists());
}
#[test]
fn missing_source_and_invalid_old_store_do_not_replace_state() {
    let (_tmp, config) = fixture(false);
    let set = &config.sets[0];
    fs::write(set.source.join("one"), b"kept").unwrap();
    assert_eq!(engine::backup(&config, set).code, 0);
    let path = set.store.join("CurrentBackup/MANIFEST.csv");
    let before = fs::read(&path).unwrap();
    fs::remove_file(set.source.join("one")).unwrap();
    assert_eq!(engine::backup(&config, set).code, 4);
    assert_eq!(fs::read(&path).unwrap(), before);
    fs::write(
        set.store.join("CurrentBackup/DIRECTORIES.csv"),
        b"RelativePath,Attributes\n",
    )
    .unwrap();
    assert_eq!(engine::backup(&config, set).code, 2);
    assert_eq!(fs::read(path).unwrap(), before);
}
#[test]
fn preserved_definitions_are_not_overwritten_on_incomplete_runs() {
    let (_tmp, config) = fixture(false);
    let set = &config.sets[0];
    fs::write(set.source.join("one"), b"kept").unwrap();
    assert_eq!(engine::backup(&config, set).code, 0);
    let previous = set.store.join("CurrentBackup/MANIFEST.csv.prev");
    fs::write(&previous, b"original previous definitions").unwrap();
    // Canonical Windows roots use verbatim paths, allowing a literal reserved name
    // to exercise the portable-name refusal without opening a device.
    fs::write(set.source.join("NUL.txt"), b"nonportable").unwrap();
    let r = engine::backup(&config, set);
    assert_eq!(r.code, 1, "{r:?}");
    assert_eq!(
        fs::read(previous).unwrap(),
        b"original previous definitions"
    );
}
#[test]
fn compressed_native_store_restores_with_independent_script() {
    let (tmp, config) = fixture(true);
    let set = &config.sets[0];
    let source = set.source.join("compressible.txt");
    fs::write(&source, vec![b'x'; 2 * 1024 * 1024]).unwrap();
    let report = engine::backup(&config, set);
    assert_eq!(report.code, 0, "{report:?}");
    let store = Store::new(&set.store);
    let rows = format::read_manifest(&store.current.join(format::MANIFEST)).unwrap();
    assert_eq!(rows[0].compressed, "Yes");
    let object = store
        .index()
        .unwrap()
        .into_values()
        .next()
        .unwrap()
        .remove(0);
    // Correct identity with another extension must still be found by both kits.
    let alternate = object.path.with_extension("opaque");
    fs::rename(object.path, &alternate).unwrap();
    let target = tmp.path().join("restored");
    #[cfg(windows)]
    let status = std::process::Command::new("pwsh")
        .args(["-NoProfile", "-File"])
        .arg(tmp.path().join("store/CurrentBackup/RECONSTRUCT.ps1"))
        .arg("-TargetRoot")
        .arg(&target)
        .args([
            "-SevenZipPath",
            "C:/Program Files/7-Zip/7z.exe",
            "-NonInteractive",
            "-ExitCode",
        ])
        .status()
        .unwrap();
    #[cfg(unix)]
    let status = std::process::Command::new("bash")
        .arg(store.current.join("reconstruct.sh"))
        .arg("--target-root")
        .arg(&target)
        .status()
        .unwrap();
    assert!(status.success(), "restore failed: {status}");
    assert_eq!(
        format::hash_file(&source).unwrap(),
        format::hash_file(&target.join("compressible.txt")).unwrap()
    );
}
#[test]
fn changed_case_during_incomplete_walk_and_damaged_object_heal() {
    let (_tmp, config) = fixture(false);
    let set = &config.sets[0];
    fs::write(set.source.join("Foo.txt"), b"bytes").unwrap();
    assert_eq!(engine::backup(&config, set).code, 0);
    fs::rename(set.source.join("Foo.txt"), set.source.join("foo.txt")).unwrap();
    fs::write(set.source.join("NUL.txt"), b"blocked").unwrap();
    let r = engine::backup(&config, set);
    assert_eq!(r.code, 1, "{r:?}");
    let store = Store::new(&set.store);
    let rows = format::read_manifest(&store.current.join(format::MANIFEST)).unwrap();
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].relative_path, "foo.txt");
    fs::remove_file(set.source.join("NUL.txt")).unwrap();
    let object = store
        .index()
        .unwrap()
        .into_values()
        .next()
        .unwrap()
        .remove(0);
    fs::write(object.path, b"damaged").unwrap();
    let r = engine::backup(&config, set);
    assert_eq!(r.code, 1, "quarantine must warn: {r:?}");
    assert_eq!(engine::backup(&config, set).code, 0);
    let objects = store.index().unwrap();
    assert!(
        objects[&rows[0].key()]
            .iter()
            .any(|o| format::hash_file(&o.path).unwrap() == rows[0].key())
    );
}
#[test]
fn compression_probe_policy_and_disabled_new_compression_reuse() {
    let (_tmp, mut cfg) = fixture(true);
    cfg.sets[0].probe = "excluded-extensions".into();
    let set = &cfg.sets[0];
    fs::write(set.source.join("misnamed.jpg"), vec![b'x'; 300 * 1024]).unwrap();
    let mut seed = 0x123456789abcdef_u64;
    let random: Vec<u8> = (0..300 * 1024)
        .map(|_| {
            seed ^= seed << 13;
            seed ^= seed >> 7;
            seed ^= seed << 17;
            seed as u8
        })
        .collect();
    fs::write(set.source.join("random.bin"), random).unwrap();
    fs::write(set.source.join("text.txt"), vec![b'x'; 300 * 1024 + 1]).unwrap();
    let r = engine::backup(&cfg, set);
    assert_eq!(r.code, 0, "{r:?}");
    let store = Store::new(&set.store);
    let rows = format::read_manifest(&store.current.join(format::MANIFEST)).unwrap();
    for name in ["misnamed.jpg", "random.bin"] {
        assert_eq!(
            rows.iter()
                .find(|r| r.relative_path == name)
                .unwrap()
                .compressed,
            "No"
        );
    }
    assert_eq!(
        rows.iter()
            .find(|r| r.relative_path == "text.txt")
            .unwrap()
            .compressed,
        "Yes"
    );
    fs::copy(
        set.source.join("text.txt"),
        set.source.join("new-alias.txt"),
    )
    .unwrap();
    cfg.sets[0].compress = false;
    let r = engine::backup(&cfg, &cfg.sets[0]);
    assert_eq!(r.code, 0, "{r:?}");
    let rows = format::read_manifest(&store.current.join(format::MANIFEST)).unwrap();
    assert_eq!(rows.len(), 4);
    assert_eq!(
        rows.iter()
            .find(|r| r.relative_path == "new-alias.txt")
            .unwrap()
            .compressed,
        "Yes"
    );
}
#[cfg(windows)]
#[test]
fn failed_case_rename_keeps_previous_row_after_complete_walk() {
    use std::os::windows::fs::OpenOptionsExt;
    let (_tmp, cfg) = fixture(false);
    let set = &cfg.sets[0];
    fs::write(set.source.join("Foo.txt"), b"keep on failed capture").unwrap();
    assert_eq!(engine::backup(&cfg, set).code, 0);
    fs::rename(set.source.join("Foo.txt"), set.source.join("foo.txt")).unwrap();
    let _held = fs::OpenOptions::new()
        .read(true)
        .share_mode(0)
        .open(set.source.join("foo.txt"))
        .unwrap();
    let report = engine::backup(&cfg, set);
    assert_eq!(report.code, 1, "{report:?}");
    let rows = format::read_manifest(&set.store.join("CurrentBackup/MANIFEST.csv")).unwrap();
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].relative_path, "Foo.txt");
}
#[cfg(unix)]
#[test]
fn folder_to_link_during_incomplete_walk_excludes_stale_descendants() {
    let (_tmp, cfg) = fixture(false);
    let set = &cfg.sets[0];
    fs::create_dir_all(set.source.join("a/x")).unwrap();
    fs::create_dir(set.source.join("b")).unwrap();
    assert_eq!(engine::backup(&cfg, set).code, 0);
    fs::remove_dir(set.source.join("a/x")).unwrap();
    fs::remove_dir(set.source.join("a")).unwrap();
    std::os::unix::fs::symlink("b", set.source.join("a")).unwrap();
    fs::write(set.source.join("NUL.txt"), b"blocked").unwrap();
    let r = engine::backup(&cfg, set);
    assert_eq!(r.code, 1, "{r:?}");
    let dirs = format::read_directories(&set.store.join("CurrentBackup/DIRECTORIES.csv")).unwrap();
    assert!(
        dirs.iter()
            .any(|d| d.relative_path == "a" && d.kind == "FolderLink")
    );
    assert!(!dirs.iter().any(|d| d.relative_path == "a/x"));
}
#[cfg(unix)]
#[test]
fn folder_links_expand_external_aliases_but_never_ingest_stores() {
    use std::os::unix::fs::symlink;
    let (tmp, config) = fixture(false);
    let set = &config.sets[0];
    fs::create_dir(set.source.join("inside")).unwrap();
    fs::write(set.source.join("inside/file"), b"inside").unwrap();
    let external = tmp.path().join("external");
    fs::create_dir(&external).unwrap();
    fs::write(external.join("file"), b"outside").unwrap();
    symlink("inside", set.source.join("relative")).unwrap();
    symlink(&external, set.source.join("alias")).unwrap();
    assert_eq!(engine::backup(&config, set).code, 0);
    let store = Store::new(&set.store);
    let dirs = format::read_directories(&store.current.join(format::DIRECTORIES)).unwrap();
    assert!(
        dirs.iter()
            .any(|d| d.kind == "FolderLink" && d.target == "inside")
    );
    let rows = format::read_manifest(&store.current.join(format::MANIFEST)).unwrap();
    assert!(rows.iter().any(|r| r.relative_path == "alias/file"));
    symlink(&set.store, set.source.join("forbidden")).unwrap();
    assert_eq!(engine::backup(&config, set).code, 1);
    let rows = format::read_manifest(&store.current.join(format::MANIFEST)).unwrap();
    assert!(
        !rows
            .iter()
            .any(|r| r.relative_path.starts_with("forbidden/"))
    );
}
