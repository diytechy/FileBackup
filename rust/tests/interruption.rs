#![cfg(feature = "test-hooks")]
use filebackup::{config, engine, format, store::Store};
use std::{
    fs,
    process::Command,
    time::{Duration, Instant},
};

#[test]
fn killed_writer_leaves_recoverable_pool_and_next_run_repairs() {
    for stage in [
        "previous-manifest",
        "snapshot",
        "object",
        "manifest-checkpoint",
        "final-manifest",
        "final-definitions",
        "superseded",
        "previous-cleanup",
    ] {
        let tmp = tempfile::tempdir().unwrap();
        let source = tmp.path().join("source");
        fs::create_dir(&source).unwrap();
        fs::write(source.join("file"), b"previous").unwrap();
        let path = tmp.path().join("config.json");
        fs::write(&path, serde_json::to_vec(&serde_json::json!({"ConfigVersion":3,"BackupSets":[{"Name":"kill","SourcePath":source,"StorePath":tmp.path().join("store"),"CompressEnabled":false,"HashRecalcFreq":"A"}]})).unwrap()).unwrap();
        let cfg = config::load(&path).unwrap();
        assert_eq!(engine::backup(&cfg, &cfg.sets[0]).code, 0);
        fs::write(source.join("file"), b"new captured bytes").unwrap();
        let signal = tmp.path().join("signal");
        let mut child = Command::new(env!("CARGO_BIN_EXE_filebackup"))
            .args(["backup", "--config"])
            .arg(&path)
            .env("FILEBACKUP_TEST_PAUSE", stage)
            .env("FILEBACKUP_TEST_CHECKPOINT", "1")
            .env("FILEBACKUP_TEST_SIGNAL", &signal)
            .spawn()
            .unwrap();
        let start = Instant::now();
        while !signal.exists() && start.elapsed() < Duration::from_secs(30) {
            assert!(
                child.try_wait().unwrap().is_none(),
                "writer ended before {stage}"
            );
            std::thread::sleep(Duration::from_millis(20));
        }
        child.kill().unwrap();
        child.wait().unwrap();
        assert!(signal.exists(), "did not reach {stage}");
        let store = Store::new(&cfg.sets[0].store);
        let index = store.index().unwrap();
        for state in store.states().unwrap() {
            for row in format::read_manifest(&state.join(format::MANIFEST)).unwrap() {
                assert!(
                    index[&row.key()]
                        .iter()
                        .any(|o| format::hash_file(&o.path).unwrap() == row.key()),
                    "unrecoverable at {stage}"
                );
            }
        }
        let r = engine::backup(&cfg, &cfg.sets[0]);
        assert_eq!(r.code, 0, "{stage}: {r:?}");
        assert!(!store.current.join("MANIFEST.csv.prev").exists());
        assert!(!store.current.join("DIRECTORIES.csv.prev").exists());
    }
}

#[test]
fn killed_prune_resumes_original_selection_after_a_folder_is_gone() {
    let tmp = tempfile::tempdir().unwrap();
    let source = tmp.path().join("source");
    fs::create_dir(&source).unwrap();
    let path = tmp.path().join("config.json");
    fs::write(&path, serde_json::to_vec(&serde_json::json!({"ConfigVersion":3,"BackupSets":[{"Name":"prune-kill","SourcePath":source,"StorePath":tmp.path().join("store"),"CompressEnabled":false,"HashRecalcFreq":"A"}]})).unwrap()).unwrap();
    let cfg = config::load(&path).unwrap();
    let set = &cfg.sets[0];
    for bytes in [b"one", b"two", b"end"] {
        fs::write(source.join("file"), bytes).unwrap();
        assert_eq!(engine::backup(&cfg, set).code, 0);
    }
    let names = filebackup::maintenance::snapshots(set).unwrap();
    assert_eq!(names.len(), 2);
    let signal = tmp.path().join("signal");
    let mut child = Command::new(env!("CARGO_BIN_EXE_filebackup"))
        .args(["prune", "--config"])
        .arg(&path)
        .arg("--snapshot")
        .arg(&names[0])
        .arg("--snapshot")
        .arg(&names[1])
        .env("FILEBACKUP_TEST_PAUSE", "prune-deleted")
        .env("FILEBACKUP_TEST_SIGNAL", &signal)
        .spawn()
        .unwrap();
    let start = Instant::now();
    while !signal.exists() && start.elapsed() < Duration::from_secs(30) {
        assert!(child.try_wait().unwrap().is_none());
        std::thread::sleep(Duration::from_millis(20));
    }
    child.kill().unwrap();
    child.wait().unwrap();
    assert!(signal.exists());
    assert!(set.store.join("PrunePlan.json").exists());
    assert_ne!(engine::backup(&cfg, set).code, 0);
    let result = filebackup::maintenance::prune(&cfg, set, &names, false);
    assert_eq!(result.code, 0, "{result:?}");
    assert!(!set.store.join("PrunePlan.json").exists());
    assert!(filebackup::maintenance::snapshots(set).unwrap().is_empty());
    assert_eq!(
        filebackup::maintenance::verify(&cfg, set, true, false).code,
        0
    );
}

#[test]
fn killed_prune_before_journal_reuses_the_verified_rehome() {
    let tmp = tempfile::tempdir().unwrap();
    let source = tmp.path().join("source");
    fs::create_dir(&source).unwrap();
    let path = tmp.path().join("config.json");
    fs::write(&path, serde_json::to_vec(&serde_json::json!({"ConfigVersion":3,"BackupSets":[{"Name":"rehome-kill","SourcePath":source,"StorePath":tmp.path().join("store"),"CompressEnabled":false,"HashRecalcFreq":"A"}]})).unwrap()).unwrap();
    let cfg = config::load(&path).unwrap();
    let set = &cfg.sets[0];
    let store = Store::new(&set.store);
    fs::write(source.join("file"), b"old supply").unwrap();
    assert_eq!(engine::backup(&cfg, set).code, 0);
    let previous = fs::read(store.current.join(format::MANIFEST)).unwrap();
    fs::write(source.join("file"), b"new supply").unwrap();
    assert_eq!(engine::backup(&cfg, set).code, 0);
    fs::write(store.current.join("MANIFEST.csv.prev"), previous).unwrap();
    let names = filebackup::maintenance::snapshots(set).unwrap();
    let signal = tmp.path().join("signal");
    let mut child = Command::new(env!("CARGO_BIN_EXE_filebackup"))
        .args(["prune", "--config"])
        .arg(&path)
        .arg("--snapshot")
        .arg(&names[0])
        .env("FILEBACKUP_TEST_PAUSE", "prune-rehome")
        .env("FILEBACKUP_TEST_SIGNAL", &signal)
        .spawn()
        .unwrap();
    let start = Instant::now();
    while !signal.exists() && start.elapsed() < Duration::from_secs(30) {
        assert!(child.try_wait().unwrap().is_none());
        std::thread::sleep(Duration::from_millis(20));
    }
    child.kill().unwrap();
    child.wait().unwrap();
    assert!(signal.exists());
    assert!(!store.root.join("PrunePlan.json").exists());
    let report = filebackup::maintenance::prune(&cfg, set, &names, false);
    assert_eq!(report.code, 0, "{report:?}");
    let prior = format::read_manifest(&store.current.join("MANIFEST.csv.prev")).unwrap();
    assert!(
        store.index().unwrap()[&prior[0].key()]
            .iter()
            .any(|o| o.state == store.current
                && format::hash_file(&o.path).unwrap() == prior[0].key())
    );
}
