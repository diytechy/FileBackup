use filebackup::{config, engine, format, maintenance, store::Store};
use std::fs;
fn fixture() -> (tempfile::TempDir, config::Config) {
    let tmp = tempfile::tempdir().unwrap();
    let source = tmp.path().join("source");
    fs::create_dir(&source).unwrap();
    let path = tmp.path().join("config.json");
    fs::write(&path, serde_json::to_vec(&serde_json::json!({"ConfigVersion":3,"BackupSets":[{"Name":"maint","SourcePath":source,"StorePath":tmp.path().join("store"),"CompressEnabled":false,"BrowseView":"index","HashRecalcFreq":"A"}]})).unwrap()).unwrap();
    let cfg = config::load(&path).unwrap();
    (tmp, cfg)
}
#[test]
fn retention_protects_latest_and_later_but_does_not_promise_older_states() {
    let (_tmp, cfg) = fixture();
    let set = &cfg.sets[0];
    fs::write(set.source.join("x"), b"shared old bytes").unwrap();
    assert_eq!(engine::backup(&cfg, set).code, 0);
    fs::create_dir(set.source.join("empty")).unwrap();
    assert_eq!(engine::backup(&cfg, set).code, 0); // oldest snapshot borrows x
    fs::write(set.source.join("x"), b"new bytes").unwrap();
    assert_eq!(engine::backup(&cfg, set).code, 0); // x moves into second snapshot
    let names = maintenance::snapshots(set).unwrap();
    assert_eq!(names.len(), 2);
    assert_eq!(maintenance::refresh(set).code, 0);
    let report = maintenance::prune(set, &[names[1].clone()], true);
    assert_eq!(report.code, 0, "{report:?}");
    assert!(set.store.join("BackupHistory").join(&names[1]).exists());
    let report = maintenance::prune(set, &[names[1].clone()], false);
    assert_eq!(report.code, 0, "{report:?}");
    let store = Store::new(&set.store);
    let pool = store.index().unwrap();
    let latest = format::read_manifest(&store.current.join(format::MANIFEST)).unwrap();
    assert!(pool.contains_key(&latest[0].key()));
    let old = format::read_manifest(&store.history.join(&names[0]).join(format::MANIFEST)).unwrap();
    assert!(
        !pool.contains_key(&old[0].key()),
        "older states may depend on removed history"
    );
    assert!(
        store.history.join(&names[0]).exists(),
        "unselected folder must survive"
    );
    assert_eq!(maintenance::verify(set, true, false).code, 1);
}
#[test]
fn prune_protects_previous_definitions_and_refuses_unknown_contents() {
    let (_tmp, cfg) = fixture();
    let set = &cfg.sets[0];
    fs::write(set.source.join("x"), b"old").unwrap();
    assert_eq!(engine::backup(&cfg, set).code, 0);
    let store = Store::new(&set.store);
    let previous = fs::read(store.current.join(format::MANIFEST)).unwrap();
    fs::write(set.source.join("x"), b"new").unwrap();
    assert_eq!(engine::backup(&cfg, set).code, 0);
    fs::write(store.current.join("MANIFEST.csv.prev"), previous).unwrap();
    let names = maintenance::snapshots(set).unwrap();
    let unknown = store.history.join(&names[0]).join("owner-note.txt");
    fs::write(&unknown, b"keep").unwrap();
    assert_eq!(maintenance::prune(set, &names, false).code, 2);
    fs::remove_file(unknown).unwrap();
    let r = maintenance::prune(set, &names, false);
    assert_eq!(r.code, 0, "{r:?}");
    let previous = format::read_manifest(&store.current.join("MANIFEST.csv.prev")).unwrap();
    assert!(store.index().unwrap().contains_key(&previous[0].key()));
    // A re-homed object takes the store's creation mode, like any other.
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mode = |p: &std::path::Path| fs::metadata(p).unwrap().permissions().mode() & 0o777;
        let rehomed = &store.index().unwrap()[&previous[0].key()][0].path;
        assert_eq!(mode(rehomed), mode(&store.current.join(format::MANIFEST)));
    }
}
#[test]
fn view_never_adopts_an_unrelated_index_and_escapes_names() {
    let (_tmp, cfg) = fixture();
    let set = &cfg.sets[0];
    fs::write(set.source.join("a&b.txt"), b"x").unwrap();
    assert_eq!(engine::backup(&cfg, set).code, 0);
    let view = set.view.as_ref().unwrap();
    fs::create_dir_all(view).unwrap();
    fs::remove_file(view.join(".viewstamp")).unwrap();
    fs::write(view.join("index.html"), b"owned by someone else").unwrap();
    assert_ne!(maintenance::view(set).code, 0);
    assert_eq!(
        fs::read(view.join("index.html")).unwrap(),
        b"owned by someone else"
    );
    fs::remove_file(view.join("index.html")).unwrap();
    assert_eq!(maintenance::view(set).code, 0);
    assert!(
        fs::read_to_string(view.join("index.html"))
            .unwrap()
            .contains("a&amp;b.txt")
    );
}
#[test]
fn repair_reports_form_mismatch_duplicates_and_misplaced_bytes() {
    let (_tmp, cfg) = fixture();
    let set = &cfg.sets[0];
    fs::write(set.source.join("file"), b"usable content").unwrap();
    assert_eq!(engine::backup(&cfg, set).code, 0);
    let store = Store::new(&set.store);
    let manifest = store.current.join(format::MANIFEST);
    let mut rows = format::read_manifest(&manifest).unwrap();
    rows[0].compressed = "Yes".into();
    fs::write(&manifest, format::manifest_bytes(&rows).unwrap()).unwrap();
    let object = store
        .index()
        .unwrap()
        .into_values()
        .next()
        .unwrap()
        .remove(0);
    let twin = object.path.with_extension("copy");
    fs::copy(&object.path, &twin).unwrap();
    let misplaced = store.current.join(&object.name);
    fs::copy(&object.path, &misplaced).unwrap();
    let before = fs::read(&manifest).unwrap();
    let r = maintenance::verify(set, true, false);
    assert_eq!(r.code, 1, "{r:?}");
    assert_eq!(fs::read(&manifest).unwrap(), before);
    let r = maintenance::verify(set, true, true);
    assert_eq!(r.code, 1, "{r:?}");
    assert_eq!(maintenance::verify(set, true, false).code, 0);
    assert_eq!(
        format::read_manifest(&manifest).unwrap()[0].compressed,
        "No"
    );
    assert!(!misplaced.exists());
    assert_eq!(
        store.index().unwrap().into_values().next().unwrap().len(),
        1
    );
}
#[test]
fn kit_refresh_preserves_previous_inventory_and_bytes() {
    let (_tmp, cfg) = fixture();
    let set = &cfg.sets[0];
    fs::write(set.source.join("file"), b"x").unwrap();
    assert_eq!(engine::backup(&cfg, set).code, 0);
    let store = Store::new(&set.store);
    let before = fs::read(store.current.join(filebackup::kit::INDEX)).unwrap();
    assert_eq!(maintenance::refresh(set).code, 0);
    assert_eq!(
        fs::read(
            store
                .current
                .join("RECOVERY.previous")
                .join(filebackup::kit::INDEX)
        )
        .unwrap(),
        before
    );
    for name in filebackup::kit::members() {
        assert_eq!(
            fs::read(store.current.join(name)).unwrap(),
            fs::read(store.current.join("RECOVERY.previous").join(name)).unwrap()
        );
    }
}

#[test]
fn compressed_prune_rehome_verifies_closed_staging_file() {
    let (_tmp, mut cfg) = fixture();
    cfg.sets[0].compress = true;
    cfg.sets[0].probe = "off".into();
    let set = &cfg.sets[0];
    fs::write(set.source.join("text.txt"), vec![b'x'; 300_000]).unwrap();
    assert_eq!(engine::backup(&cfg, set).code, 0);
    let store = Store::new(&set.store);
    let previous = fs::read(store.current.join(format::MANIFEST)).unwrap();
    let old = format::read_manifest(&store.current.join(format::MANIFEST)).unwrap();
    assert_eq!(old[0].compressed, "Yes");
    fs::write(set.source.join("text.txt"), b"new").unwrap();
    assert_eq!(engine::backup(&cfg, set).code, 0);
    fs::write(store.current.join("MANIFEST.csv.prev"), previous).unwrap();
    let names = maintenance::snapshots(set).unwrap();
    let result = maintenance::prune(set, &names, false);
    assert_eq!(result.code, 0, "{result:?}");
    let pool = store.index().unwrap();
    assert!(filebackup::tools::verify(&pool[&old[0].key()][0].path, &old[0].key(),).unwrap());
}

#[test]
fn verify_continues_past_a_state_with_missing_manifest() {
    let (_tmp, cfg) = fixture();
    let set = &cfg.sets[0];
    fs::write(set.source.join("x"), b"first").unwrap();
    assert_eq!(engine::backup(&cfg, set).code, 0);
    fs::write(set.source.join("x"), b"second").unwrap();
    assert_eq!(engine::backup(&cfg, set).code, 0);
    let store = Store::new(&set.store);
    fs::remove_file(store.current.join(format::MANIFEST)).unwrap();
    let report = maintenance::verify(set, true, false);
    assert_eq!(report.code, 1, "{report:?}");
    assert_eq!(report.reused, 1, "remaining history was not inspected");
    assert!(
        report
            .events
            .iter()
            .any(|e| e.cause == "file_records_unavailable")
    );
}

#[test]
fn repair_returns_an_only_copy_to_its_shard() {
    let (_tmp, cfg) = fixture();
    let set = &cfg.sets[0];
    fs::write(set.source.join("file"), b"the only copy").unwrap();
    assert_eq!(engine::backup(&cfg, set).code, 0);
    let store = Store::new(&set.store);
    let object = store
        .index()
        .unwrap()
        .into_values()
        .next()
        .unwrap()
        .remove(0);
    let misplaced = store.current.join(&object.name);
    fs::rename(&object.path, &misplaced).unwrap();
    assert_eq!(maintenance::verify(set, true, false).code, 1);
    assert_eq!(maintenance::verify(set, true, true).code, 1);
    assert!(object.path.exists(), "the only copy was set aside");
    assert!(!misplaced.exists());
    assert_eq!(maintenance::verify(set, true, false).code, 0);
}
