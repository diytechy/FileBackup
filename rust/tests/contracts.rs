use filebackup::{config, format::*, platform};
use std::{fs, path::PathBuf};

fn fixtures() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../tests/fixtures")
}

#[test]
fn independently_generated_hash_vectors() {
    let base = fixtures().join("hash-conformance");
    let mut reader = csv::Reader::from_path(base.join("expected-hashes.csv")).unwrap();
    for row in reader.records() {
        let row = row.unwrap();
        assert_eq!(
            String::from(hash_file(&base.join(&row[0])).unwrap().hash),
            row[1],
            "{}",
            &row[0]
        );
    }
}
#[test]
fn existing_name_decoder_corpus() {
    let mut reader = csv::ReaderBuilder::new()
        .delimiter(b'\t')
        .from_path(fixtures().join("name-grammar/decode.tsv"))
        .unwrap();
    for row in reader.records() {
        let row = row.unwrap();
        if &row[1] == "-" {
            assert!(parse_name(&row[0]).is_err(), "{}", &row[0]);
            continue;
        }
        let key = parse_name(&row[0]).unwrap();
        assert_eq!(String::from(key.hash), row[1]);
        assert_eq!(key.length, row[2].parse::<u64>().unwrap());
        let tail = &row[0][23..];
        let end = tail.bytes().take_while(|b| ALPHABET.contains(b)).count();
        let canonical = object_name(&key, &tail[end..]).unwrap();
        assert_eq!(parse_name(&canonical).unwrap(), key);
        // Readers accept zero-padded length fields; writers emit canonical unpadded fields.
        assert_eq!(
            &canonical[23..],
            format!("{}{}", encode(key.length as u128, 0).unwrap(), &tail[end..])
        );
    }
}
#[test]
fn malformed_names_are_not_content() {
    for name in [
        "",
        "data.bin",
        "zzzzzzzzzzzzzzzzzzzzzz_3.bin",
        "2222222222222222222222_3/escape",
        "2222222222222222222222_.bin",
    ] {
        assert!(parse_name(name).is_err(), "{name}");
    }
}
#[test]
fn manifest_roundtrip_and_metadata_required() {
    let dir = tempfile::tempdir().unwrap();
    let key = copy_hash(&b"hello"[..], std::io::sink()).unwrap();
    let row = FileRow {
        data_path: object_name(&key, ".txt").unwrap(),
        relative_path: "ué/hello, world.txt".into(),
        length: key.length,
        modified: "2026-11-06T10:00:00.0000000Z".into(),
        hash: key.hash,
        compressed: "No".into(),
        storage: "Hash".into(),
        duplicate: "".into(),
        media: "".into(),
    };
    let path = dir.path().join(MANIFEST);
    fs::write(&path, manifest_bytes(std::slice::from_ref(&row)).unwrap()).unwrap();
    let expected = fs::read(&path).unwrap();
    platform::atomic_write_with(&path, true, |file| write_manifest(file, [&row])).unwrap();
    assert_eq!(fs::read(&path).unwrap(), expected);
    let failed = platform::atomic_write_with(&path, true, |file| {
        std::io::Write::write_all(file, b"partial new manifest")?;
        anyhow::bail!("injected writer failure")
    });
    assert!(failed.is_err());
    assert_eq!(fs::read(&path).unwrap(), expected);
    assert_eq!(read_manifest(&path).unwrap(), vec![row]);
    assert!(read_directories(&dir.path().join(DIRECTORIES)).is_err());
    fs::write(dir.path().join(DIRECTORIES), directory_bytes(&[]).unwrap()).unwrap();
    assert!(
        read_directories(&dir.path().join(DIRECTORIES))
            .unwrap()
            .is_empty()
    );
}
#[test]
fn portable_paths_and_previous_publication() {
    for p in [
        "../x", "/x", "a//b", "a/./b", "C:/x", "a\\b", "NUL.txt", "x.", "a\nb",
    ] {
        assert!(validate_path(p).is_err(), "{p}");
    }
    let dir = tempfile::tempdir().unwrap();
    let current = dir.path().join("current");
    let previous = dir.path().join("previous");
    platform::atomic_write(&current, b"old", false).unwrap();
    platform::preserve(&current, &previous).unwrap();
    platform::atomic_write(&current, b"new", true).unwrap();
    platform::preserve(&current, &previous).unwrap();
    assert_eq!(fs::read(previous).unwrap(), b"old");
    assert_eq!(fs::read(current).unwrap(), b"new");
}
#[test]
fn config_admission_is_nonmutating_and_rejects_shared_store() {
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("source");
    fs::create_dir(&source).unwrap();
    let store = dir.path().join("store");
    let set = serde_json::json!({"Name":"one","SourcePath":source,"StorePath":store,"CompressEnabled":false});
    let path = dir.path().join("config.json");
    fs::write(
        &path,
        serde_json::to_vec(&serde_json::json!({"ConfigVersion":3.0,"BackupSets":[set.clone()]}))
            .unwrap(),
    )
    .unwrap();
    assert!(config::load(&path).is_ok());
    assert!(!store.exists());
    let mut other = set.clone();
    other["Name"] = "two".into();
    fs::write(
        &path,
        serde_json::to_vec(&serde_json::json!({"ConfigVersion":3,"BackupSets":[set,other]}))
            .unwrap(),
    )
    .unwrap();
    assert!(config::load(&path).is_err());
    assert!(!store.exists());
}

#[test]
fn unicode_collision_profile_covers_sigma_and_normalization() {
    assert_eq!(path_key("Σ.txt"), path_key("ς.txt"));
    assert_eq!(path_key("é"), path_key("e\u{301}"));
    assert_eq!(path_key("Straße"), path_key("STRASSE"));
    for name in ["COM0", "COM¹.txt", "NUL .txt", "CONIN$"] {
        assert!(validate_path(name).is_err(), "{name}");
    }
}

#[test]
fn exclusive_lock_and_nonreplacement_publication() {
    let dir = tempfile::tempdir().unwrap();
    let first = platform::StoreLock::acquire(dir.path()).unwrap();
    assert!(platform::StoreLock::acquire(dir.path()).is_err());
    drop(first);
    assert!(platform::StoreLock::acquire(dir.path()).is_ok());
    let path = dir.path().join("state");
    platform::atomic_write(&path, b"first", false).unwrap();
    assert!(platform::atomic_write(&path, b"second", false).is_err());
    assert_eq!(fs::read(path).unwrap(), b"first");
}

#[cfg(windows)]
#[test]
fn ambiguous_windows_root_tail_is_refused() {
    let dir = tempfile::tempdir().unwrap();
    assert!(platform::resolve(&dir.path().join("store.")).is_err());
    assert!(platform::resolve(&dir.path().join("store ")).is_err());
}

#[cfg(unix)]
#[test]
fn dangling_roots_and_lock_redirects_are_refused() {
    use std::os::unix::fs::symlink;
    let dir = tempfile::tempdir().unwrap();
    let missing = dir.path().join("missing");
    let link = dir.path().join("link");
    symlink(&missing, &link).unwrap();
    assert!(platform::resolve(&link).is_err());
    symlink(&missing, dir.path().join("Temp.lock")).unwrap();
    assert!(platform::StoreLock::acquire(dir.path()).is_err());
    assert!(!missing.exists());
}
#[test]
fn media_measurements_do_not_invent_zero_for_missing_duration() {
    assert_eq!(
        filebackup::tools::parse_media_rate(10485760, "2\n"),
        Some("5.000".into())
    );
    for value in ["0", "-1", "NaN", "inf", "", "N/A"] {
        assert!(filebackup::tools::parse_media_rate(10, value).is_none());
    }
}
#[test]
fn carried_shell_and_unicode_data_have_lf_endings() {
    for (name, bytes) in filebackup::kit::FILES {
        if name.ends_with(".sh")
            || name.ends_with(".command")
            || name.ends_with(".awk")
            || name.ends_with(".tsv")
        {
            assert!(!bytes.contains(&b'\r'), "CRLF breaks carried helper {name}");
        }
    }
}
