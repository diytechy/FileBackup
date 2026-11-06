use filebackup::{config, notify};
use std::fs;
#[test]
fn notification_admission_rejects_secrets_without_echoing_them() {
    let tmp = tempfile::tempdir().unwrap();
    let path = tmp.path().join("config.json");
    for secret in [
        serde_json::json!({"Credential":"super-private-password"}),
        serde_json::json!({"Password":"super-private-password"}),
    ] {
        fs::write(
            &path,
            serde_json::to_vec(
                &serde_json::json!({"ConfigVersion":3,"Secrets":secret,"BackupSets":[]}),
            )
            .unwrap(),
        )
        .unwrap();
        let error = format!("{:#}", config::load(&path).unwrap_err());
        assert!(!error.contains("super-private-password"));
    }
}
#[test]
fn bounded_message_can_be_prepared_without_contacting_a_relay() {
    let settings = notify::Settings {
        to: "recipient@example.invalid".into(),
        from: "sender@example.invalid".into(),
        server: "smtp.example.invalid".into(),
        port: 587,
        credential: Some("credential:fixture".into()),
    };
    let message = notify::message(&settings, "Run complete")
        .unwrap()
        .formatted();
    let text = String::from_utf8(message).unwrap();
    assert!(text.contains("Run complete"));
    assert!(!text.contains("credential:fixture"));
    let mut bad = settings;
    bad.credential = Some("credential:../../secret".into());
    assert!(notify::validate(&bad).is_err());
}

#[test]
fn large_incident_summary_omits_paths_messages_and_remains_bounded() {
    let mut report = filebackup::engine::Report::new("backup", "documents");
    for _ in 0..20_000 {
        report.finding_at(
            1,
            "content_missing",
            Some("private/path"),
            "private error detail".into(),
        );
    }
    let body = notify::summary(&[report]).unwrap();
    assert!(!body.contains("private"));
    assert!(body.contains("20000"));
    assert!(body.len() < 1024);
}
