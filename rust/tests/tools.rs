use std::{
    process::{Command, Stdio},
    time::{Duration, Instant},
};

#[test]
fn pipe_holder_helper() {
    if std::env::var_os("FILEBACKUP_PIPE_HOLDER").is_some() {
        std::thread::sleep(Duration::from_secs(20));
    }
}
#[test]
#[allow(clippy::zombie_processes)] // Intentionally orphan a pipe holder; ToolChild must kill its group/job.
fn pipe_parent_helper() {
    if std::env::var_os("FILEBACKUP_PIPE_PARENT").is_some() {
        // Deliberately keep inherited stdout open after this direct child exits.
        let _child = Command::new(std::env::current_exe().unwrap())
            .args(["--exact", "pipe_holder_helper", "--nocapture"])
            .env_remove("FILEBACKUP_PIPE_PARENT")
            .env("FILEBACKUP_PIPE_HOLDER", "1")
            .stdin(Stdio::null())
            .stdout(Stdio::inherit())
            .stderr(Stdio::null())
            .spawn()
            .unwrap();
    }
}
#[test]
fn inherited_output_pipe_cannot_extend_tool_deadline() {
    let start = Instant::now();
    let error = filebackup::tools::output(
        Command::new(std::env::current_exe().unwrap())
            .args(["--exact", "pipe_parent_helper", "--nocapture"])
            .env("FILEBACKUP_PIPE_PARENT", "1"),
        4096,
        Duration::from_millis(500),
    )
    .unwrap_err();
    assert!(filebackup::platform::is_host_stop(&error), "{error:#}");
    assert!(start.elapsed() < Duration::from_secs(5));
}

fn external_seven_zip() -> Command {
    #[cfg(windows)]
    let executable = "C:/Program Files/7-Zip/7z.exe";
    #[cfg(unix)]
    let executable = "7z";
    Command::new(executable)
}

#[test]
fn embedded_codec_reads_external_archives_and_rejects_damage() {
    use filebackup::{format, tools};
    use std::fs;
    let tmp = tempfile::tempdir().unwrap();
    // An executable also exercises the filters external 7-Zip selects for code.
    let input = tmp.path().join("program.exe");
    fs::copy(env!("CARGO_BIN_EXE_filebackup"), &input).unwrap();
    let key = format::hash_file(&input).unwrap();
    for method in ["default", "LZMA2", "LZMA", "Copy"] {
        let archive = tmp.path().join(format!("{method}.7z"));
        let mut command = external_seven_zip();
        command.args(["a", "-t7z", "-mx=5", "-mmt=2"]);
        if method != "default" {
            command.arg(format!("-m0={method}"));
        }
        assert!(
            command
                .arg(&archive)
                .arg(&input)
                .output()
                .unwrap()
                .status
                .success()
        );
        assert!(tools::verify(&archive, &key).unwrap(), "{method}");
        let mut wrong = key;
        wrong.length += 1;
        assert!(!tools::verify(&archive, &wrong).unwrap());
        let mut bytes = fs::read(&archive).unwrap();
        if method == "LZMA2" {
            // Invalid LZMA2 control byte; the decoder reports InvalidInput.
            bytes[32] = 3;
            fs::write(&archive, &bytes).unwrap();
            assert!(
                !tools::verify(&archive, &key).unwrap(),
                "LZMA2 damage is not a host outage"
            );
        }
        if method == "Copy" {
            // Data begins after the 32-byte signature header. Keep headers valid
            // and corrupt only content so the CRC reader reports this failure.
            bytes[40] ^= 1;
            fs::write(&archive, &bytes).unwrap();
            assert!(
                !tools::verify(&archive, &key).unwrap(),
                "CRC damage is not a host outage"
            );
        }
        bytes.truncate(bytes.len() / 2);
        fs::write(&archive, bytes).unwrap();
        assert!(
            !tools::verify(&archive, &key).unwrap(),
            "truncated {method}"
        );
    }
}

#[test]
fn unsupported_archive_is_unavailable_not_damaged() {
    use filebackup::{format, platform, tools};
    let tmp = tempfile::tempdir().unwrap();
    let input = tmp.path().join("text");
    std::fs::write(&input, vec![b'x'; 10_000]).unwrap();
    let archive = tmp.path().join("unsupported.7z");
    assert!(
        external_seven_zip()
            .args(["a", "-t7z", "-m0=BZip2"])
            .arg(&archive)
            .arg(&input)
            .output()
            .unwrap()
            .status
            .success()
    );
    let error = tools::verify(&archive, &format::hash_file(&input).unwrap()).unwrap_err();
    assert!(platform::is_host_stop(&error), "{error:#}");
}

#[test]
fn embedded_archives_extract_with_external_seven_zip_including_empty_files() {
    use filebackup::{format, tools};
    use std::fs;
    let tmp = tempfile::tempdir().unwrap();
    let mut state = 123456789u32;
    let mut distant: Vec<u8> = (0..280_000)
        .map(|_| {
            state ^= state << 13;
            state ^= state >> 17;
            state ^= state << 5;
            state as u8
        })
        .collect();
    distant.extend_from_within(..20_000);
    for (name, bytes) in [
        ("empty", vec![]),
        ("text", vec![b'x'; 300_000]),
        ("distant", distant),
    ] {
        let input = tmp.path().join(name);
        let archive = input.with_extension("7z");
        fs::write(&input, &bytes).unwrap();
        let key = format::hash_file(&input).unwrap();
        tools::compress(&input, &archive).unwrap();
        assert!(tools::verify(&archive, &key).unwrap());
        let extracted = external_seven_zip()
            .args(["e", "-so"])
            .arg(&archive)
            .output()
            .unwrap();
        assert!(extracted.status.success());
        assert_eq!(extracted.stdout, bytes);
    }
    // The store contract is one file per object, not concatenated archive members.
    let archive = tmp.path().join("multiple.7z");
    assert!(
        external_seven_zip()
            .args(["a", "-t7z"])
            .arg(&archive)
            .arg(tmp.path().join("empty"))
            .arg(tmp.path().join("text"))
            .output()
            .unwrap()
            .status
            .success()
    );
    assert!(
        !tools::verify(
            &archive,
            &format::hash_file(&tmp.path().join("text")).unwrap()
        )
        .unwrap()
    );
}

#[test]
fn native_compressed_backup_and_verify_need_no_external_tools() {
    use filebackup::{format, store::Store};
    use std::fs;
    let tmp = tempfile::tempdir().unwrap();
    let source = tmp.path().join("source");
    let root = tmp.path().join("store");
    fs::create_dir(&source).unwrap();
    fs::write(source.join("text.txt"), vec![b'x'; 300_000]).unwrap();
    let config = tmp.path().join("config.json");
    fs::write(
        &config,
        serde_json::to_vec(&serde_json::json!({
            "ConfigVersion":3,"Tools":{"SevenZipPath":"nonexistent-legacy-setting"},
            "BackupSets":[{"Name":"standalone","SourcePath":source,"StorePath":root,
                "CompressEnabled":true}]
        }))
        .unwrap(),
    )
    .unwrap();
    for action in ["backup", "verify"] {
        let mut command = Command::new(env!("CARGO_BIN_EXE_filebackup"));
        command
            .arg(action)
            .arg("--config")
            .arg(&config)
            .env("PATH", "");
        if action == "verify" {
            command.arg("--deep");
        }
        let result = command.output().unwrap();
        assert!(
            result.status.success(),
            "{} {}",
            String::from_utf8_lossy(&result.stdout),
            String::from_utf8_lossy(&result.stderr)
        );
    }
    let rows = format::read_manifest(&Store::new(&root).current.join(format::MANIFEST)).unwrap();
    assert_eq!(rows[0].compressed, "Yes");
}
