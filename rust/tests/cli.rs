use std::{fs, process::Command};
#[test]
fn admitted_sets_continue_after_a_host_failure_and_aggregate_the_result() {
    let tmp = tempfile::tempdir().unwrap();
    let mut sets = Vec::new();
    for n in 0..3 {
        let source = tmp.path().join(format!("source-{n}"));
        if n != 1 {
            fs::create_dir(&source).unwrap();
            fs::write(source.join("file.txt"), b"independent set").unwrap();
        }
        sets.push(
            serde_json::json!({"Name":format!("set-{n}"),"SourcePath":source,
            "StorePath":tmp.path().join(format!("store-{n}")),"CompressEnabled":false}),
        );
    }
    let path = tmp.path().join("config.json");
    fs::write(
        &path,
        serde_json::to_vec(&serde_json::json!({"ConfigVersion":3,"BackupSets":sets})).unwrap(),
    )
    .unwrap();
    let output = Command::new(env!("CARGO_BIN_EXE_filebackup"))
        .args(["backup", "--config"])
        .arg(&path)
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(4));
    let reports: Vec<serde_json::Value> = String::from_utf8(output.stdout)
        .unwrap()
        .lines()
        .map(|line| serde_json::from_str(line).unwrap())
        .collect();
    assert_eq!(reports.len(), 3);
    assert_eq!(reports[0]["code"], 0);
    assert_eq!(reports[1]["code"], 4);
    assert_eq!(reports[2]["code"], 0);
    assert_eq!(reports[2]["captured"], 1);
    assert!(!tmp.path().join("store-1").exists());
}
#[test]
fn wrong_action_options_and_plaintext_secrets_refuse_before_mutation() {
    let tmp = tempfile::tempdir().unwrap();
    let source = tmp.path().join("source");
    fs::create_dir(&source).unwrap();
    let store = tmp.path().join("store");
    let path = tmp.path().join("config.json");
    let mut cfg = serde_json::json!({"ConfigVersion":3,"BackupSets":[{"Name":"refusal",
        "SourcePath":source,"StorePath":store,"CompressEnabled":false}]});
    fs::write(&path, serde_json::to_vec(&cfg).unwrap()).unwrap();
    let output = Command::new(env!("CARGO_BIN_EXE_filebackup"))
        .args(["backup", "--deep", "--config"])
        .arg(&path)
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(2));
    cfg["Secrets"] = serde_json::json!({"Credential":"sensitive-value-never-echo"});
    fs::write(&path, serde_json::to_vec(&cfg).unwrap()).unwrap();
    let output = Command::new(env!("CARGO_BIN_EXE_filebackup"))
        .args(["backup", "--no-mail", "--config"])
        .arg(&path)
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(2));
    assert!(!String::from_utf8_lossy(&output.stderr).contains("sensitive-value-never-echo"));
    assert!(!store.exists());
}
