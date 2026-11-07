//! LLR-162 / SR-081 (TC-303): the compression probe measures seven interior
//! windows (or the whole file below 2.25 MiB) taken from the staging stream,
//! logs every measured decision and counts the outcomes.
use filebackup::{
    config,
    engine::{self, Report},
    format,
    store::Store,
};
use std::{fs, path::Path, sync::Mutex};

// The fault hooks are process-wide environment variables, so every test that
// runs a backup takes this lock and the tests in this file run one at a time.
static SERIAL: Mutex<()> = Mutex::new(());
fn serial() -> std::sync::MutexGuard<'static, ()> {
    SERIAL.lock().unwrap_or_else(|e| e.into_inner())
}

const MIB: usize = 1024 * 1024;
const WINDOW: usize = 256 * 1024;

fn fixture(compress: bool, probe: &str) -> (tempfile::TempDir, config::Config) {
    let tmp = tempfile::tempdir().unwrap();
    let source = tmp.path().join("source");
    fs::create_dir(&source).unwrap();
    let path = tmp.path().join("config.json");
    fs::write(
        &path,
        serde_json::to_vec(&serde_json::json!({
            "ConfigVersion": 3,
            "BackupSets": [{
                "Name": "fixture",
                "SourcePath": source,
                "StorePath": tmp.path().join("store"),
                "CompressEnabled": compress,
                "CompressProbe": probe,
                "HashRecalcFreq": "A"
            }]
        }))
        .unwrap(),
    )
    .unwrap();
    (tmp, config::load(&path).unwrap())
}

// The generator shared with scripts/gen_brotli_reference.ps1.
struct Rng(u64);
impl Rng {
    fn next(&mut self) -> u8 {
        self.0 ^= self.0 << 13;
        self.0 ^= self.0 >> 7;
        self.0 ^= self.0 << 17;
        (self.0 >> 32) as u8
    }
    fn bytes(&mut self, n: usize) -> Vec<u8> {
        (0..n).map(|_| self.next()).collect()
    }
}
const PHRASE: &[u8] = b"The quick brown fox jumps over the lazy dog. ";
fn text(n: usize) -> Vec<u8> {
    PHRASE.iter().copied().cycle().take(n).collect()
}
fn random(seed: u64, n: usize) -> Vec<u8> {
    Rng(seed).bytes(n)
}
fn cat(parts: Vec<Vec<u8>>) -> Vec<u8> {
    parts.concat()
}

/// A named 256 KiB buffer of the .NET reference table (LLR-162).
fn reference_buffer(index: usize, name: &str) -> Vec<u8> {
    const SIZE: usize = 256 * 1024;
    let mut rng = Rng(0x123456789ABCDEF0_u64 + index as u64);
    let mut b = vec![0u8; SIZE];
    match name {
        "zeros" => {}
        "random" => b = rng.bytes(SIZE),
        "text" => b = text(SIZE),
        "longrange-64KiB-x4" => {
            let block = rng.bytes(65536);
            b = block.repeat(4);
        }
        "interleaved-9of10" => {
            for blk in 0..SIZE / 4096 {
                if blk % 10 != 9 {
                    b[blk * 4096..(blk + 1) * 4096].copy_from_slice(&rng.bytes(4096));
                }
            }
        }
        "head-text-12" => {
            let cut = SIZE * 12 / 100;
            b[..cut].copy_from_slice(&text(cut));
            b[cut..].copy_from_slice(&rng.bytes(SIZE - cut));
        }
        _ if name.starts_with("block-mix-") => {
            let p: usize = name["block-mix-".len()..].parse().unwrap();
            let cut = SIZE * p / 100;
            b[..cut].copy_from_slice(&rng.bytes(cut));
        }
        _ if name.starts_with("alpha-") => {
            let m: u8 = name["alpha-".len()..].parse().unwrap();
            b = (0..SIZE).map(|_| rng.next() % m).collect();
        }
        _ => panic!("unknown reference buffer {name}"),
    }
    b
}

#[test]
fn brotli_sizes_match_the_dotnet_reference_table() {
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/brotli-reference.json");
    let table: serde_json::Value = serde_json::from_slice(&fs::read(path).unwrap()).unwrap();
    let entries = table["entries"].as_array().unwrap();
    assert!(entries.len() >= 12);
    let mut near_threshold = 0;
    let mut off = Vec::new();
    for (index, entry) in entries.iter().enumerate() {
        let name = entry["name"].as_str().unwrap();
        let (raw, size) = (
            entry["raw"].as_u64().unwrap() as f64,
            entry["size"].as_u64().unwrap() as f64,
        );
        let buffer = reference_buffer(index, name);
        assert_eq!(buffer.len() as f64, raw, "{name}");
        let ours = engine::brotli_size(&buffer).unwrap() as f64 / raw;
        let theirs = size / raw;
        if (ours - theirs).abs() > 0.005 {
            off.push(format!("{name}: rust {ours:.4} vs .NET {theirs:.4}"));
        }
        near_threshold += usize::from((0.85..=0.95).contains(&theirs));
        // The verdict at SR-081's threshold must agree as well.
        assert_eq!(ours <= 0.90, theirs <= 0.90, "{name} verdict");
    }
    assert!(off.is_empty(), "outside 0.005 of .NET: {off:?}");
    assert!(near_threshold >= 5, "table needs mixtures near 0.90");
}

fn shape(name: &str, n: usize) -> Vec<u8> {
    match name {
        // Padding at both ends, random body.
        "disc-image" => cat(vec![
            vec![0; n / 20],
            random(1, n - 2 * (n / 20)),
            vec![0; n / 20],
        ]),
        // Compressible index at both ends, random body.
        "remux" => cat(vec![
            text(n / 50),
            random(2, n - 2 * (n / 50)),
            text(n / 50),
        ]),
        // Random body with a compressible tail.
        "one-one-027" => cat(vec![random(3, n - n / 20), text(n / 20)]),
        // Zeroed preamble, then random.
        "phone-video" => cat(vec![vec![0; n / 100], random(4, n - n / 100)]),
        // Random opening tenth, then a compressible body.
        "screen-recording" => cat(vec![random(5, n / 10), text(n - n / 10)]),
        // Random to 42%, then zeros.
        "sparse" => cat(vec![random(6, n * 42 / 100), vec![0; n - n * 42 / 100]]),
        // One third compressible, in the middle.
        "mixed-third" => cat(vec![
            random(7, n / 3),
            text(n / 3),
            random(8, n - 2 * (n / 3)),
        ]),
        // WP17 longrange: a 64 KiB block repeated.
        "longrange" => random(9, 64 * 1024).repeat(n / (64 * 1024)),
        "text" => text(n),
        "random" => random(10, n),
        _ => panic!("unknown shape {name}"),
    }
}

fn manifest(set: &config::BackupSet) -> Vec<format::FileRow> {
    format::read_manifest(&Store::new(&set.store).current.join(format::MANIFEST)).unwrap()
}
fn compressed_of(rows: &[format::FileRow], name: &str) -> String {
    rows.iter()
        .find(|r| r.relative_path == name)
        .unwrap_or_else(|| panic!("no row for {name}"))
        .compressed
        .clone()
}
fn log_dir(set: &config::BackupSet) -> std::path::PathBuf {
    set.store.join("compress-decisions")
}
/// Every line of every decision log of the store, split into its seven fields.
fn decisions(set: &config::BackupSet) -> Vec<Vec<String>> {
    let mut lines = Vec::new();
    let Ok(dir) = fs::read_dir(log_dir(set)) else {
        return lines;
    };
    let mut files: Vec<_> = dir.map(|e| e.unwrap().path()).collect();
    files.sort();
    for file in files {
        for line in fs::read_to_string(file).unwrap().lines() {
            let fields: Vec<String> = line.split('\t').map(str::to_owned).collect();
            assert_eq!(fields.len(), 7, "{line}");
            lines.push(fields);
        }
    }
    lines
}
fn probe(report: &Report) -> engine::ProbeCounters {
    report.probe.clone().expect("backup reports carry probe")
}

#[test]
fn shaped_fixtures_decide_as_designed() {
    let _serial = serial();
    let n = 16 * MIB;
    let cases = [
        ("disc-image", false),
        ("remux", false),
        ("one-one-027", false),
        ("phone-video", false),
        ("screen-recording", true),
        ("sparse", true),
        ("mixed-third", true),
        ("longrange", true),
        ("text", true),
        ("random", false),
    ];
    for (name, expect_compress) in cases {
        let (_tmp, cfg) = fixture(true, "always");
        let set = &cfg.sets[0];
        let file = format!("{name}.bin");
        fs::write(set.source.join(&file), shape(name, n)).unwrap();
        let report = engine::backup(&cfg, set);
        assert_eq!(report.code, 0, "{name}: {report:?}");
        let rows = manifest(set);
        assert_eq!(
            compressed_of(&rows, &file),
            if expect_compress { "Yes" } else { "No" },
            "{name}"
        );
        let p = probe(&report);
        assert_eq!(p.measured, 1, "{name}: {p:?}");
        assert_eq!(p.compressed, u64::from(expect_compress), "{name}: {p:?}");
        assert_eq!(p.raw, u64::from(!expect_compress), "{name}: {p:?}");
        assert_eq!(
            (p.whole_file, p.unmeasured, p.fallback),
            (0, 0, 0),
            "{name}"
        );
        if expect_compress {
            assert_eq!(p.bytes_compressed_in, n as u64, "{name}");
            assert!(
                (1..n as u64).contains(&p.bytes_compressed_out),
                "{name}: {p:?}"
            );
        } else {
            assert_eq!((p.bytes_compressed_in, p.bytes_compressed_out), (0, 0));
        }
        let lines = decisions(set);
        assert_eq!(lines.len(), 1, "{name}: {lines:?}");
        let line = &lines[0];
        assert_eq!(line[1], file);
        assert_eq!(line[2], n.to_string());
        assert_eq!(line[3], if expect_compress { "compress" } else { "raw" });
        assert_eq!(line[4], "mean", "{name}");
        let combined: f64 = line[5].parse().unwrap();
        assert_eq!(combined <= 0.90, expect_compress, "{name}: {combined}");
        assert_eq!(line[6].split(',').count(), 7, "{name}: seven windows");
        assert!(chrono::DateTime::parse_from_rfc3339(&line[0]).is_ok());
    }
}

#[test]
fn sizes_around_the_floor_and_the_whole_file_cutoff() {
    let _serial = serial();
    let (_tmp, cfg) = fixture(true, "always");
    let set = &cfg.sets[0];
    let sizes = [
        ("floor.bin", WINDOW, 11),
        ("above.bin", WINDOW + 1, 12),
        ("under.bin", 9 * WINDOW - 1, 13),
        ("exact.bin", 9 * WINDOW, 14),
    ];
    for (name, size, seed) in sizes {
        fs::write(set.source.join(name), random(seed, size)).unwrap();
    }
    let report = engine::backup(&cfg, set);
    assert_eq!(report.code, 0, "{report:?}");
    let p = probe(&report);
    assert_eq!((p.unmeasured, p.measured, p.whole_file), (1, 3, 2), "{p:?}");
    let lines = decisions(set);
    let by = |name: &str| lines.iter().find(|l| l[1] == name).cloned();
    assert!(by("floor.bin").is_none(), "exactly 256 KiB is not measured");
    for (name, reason, windows) in [
        ("above.bin", "whole-file", 1),
        ("under.bin", "whole-file", 1),
        ("exact.bin", "mean", 7),
    ] {
        let line = by(name).unwrap_or_else(|| panic!("{name} unmeasured"));
        assert_eq!(line[4], reason, "{name}");
        assert_eq!(line[6].split(',').count(), windows, "{name}");
    }
    // Under the type list a file at the floor is stored compressed.
    assert_eq!(compressed_of(&manifest(set), "floor.bin"), "Yes");
}

#[test]
fn a_dedup_hit_is_not_measured_logged_or_counted() {
    let _serial = serial();
    let (_tmp, cfg) = fixture(true, "always");
    let set = &cfg.sets[0];
    let content = text(300 * 1024);
    fs::write(set.source.join("a.txt"), &content).unwrap();
    fs::write(set.source.join("b.txt"), &content).unwrap();
    let report = engine::backup(&cfg, set);
    assert_eq!(report.code, 0, "{report:?}");
    let p = probe(&report);
    assert_eq!((p.measured, p.unmeasured, p.fallback), (1, 0, 0), "{p:?}");
    assert_eq!(decisions(set).len(), 1);
    // A later alias of stored content is also a hit.
    fs::write(set.source.join("c.txt"), &content).unwrap();
    let report = engine::backup(&cfg, set);
    assert_eq!(report.code, 0, "{report:?}");
    assert_eq!(probe(&report), engine::ProbeCounters::default());
    assert_eq!(decisions(set).len(), 1);
}

#[test]
fn the_three_probe_modes() {
    let _serial = serial();
    let random_file = || random(21, 300 * 1024);
    for (mode, measured_names, unmeasured) in [
        ("always", vec!["a.mkv", "b.bin"], 0),
        ("excluded-extensions", vec!["b.bin"], 1),
        ("off", vec![], 2),
    ] {
        let (_tmp, cfg) = fixture(true, mode);
        let set = &cfg.sets[0];
        fs::write(set.source.join("a.mkv"), random_file()).unwrap();
        fs::write(set.source.join("b.bin"), random(22, 300 * 1024)).unwrap();
        let report = engine::backup(&cfg, set);
        assert_eq!(report.code, 0, "{mode}: {report:?}");
        let p = probe(&report);
        assert_eq!(p.measured as usize, measured_names.len(), "{mode}: {p:?}");
        assert_eq!(p.unmeasured, unmeasured, "{mode}: {p:?}");
        let mut logged: Vec<_> = decisions(set).into_iter().map(|l| l[1].clone()).collect();
        logged.sort();
        assert_eq!(logged, measured_names, "{mode}");
        assert_eq!(log_dir(set).exists(), !measured_names.is_empty(), "{mode}");
        let rows = manifest(set);
        // Random content measures raw; an unmeasured exempt type stays raw.
        assert_eq!(compressed_of(&rows, "a.mkv"), "No", "{mode}");
        let b = compressed_of(&rows, "b.bin");
        assert_eq!(b, if mode == "off" { "Yes" } else { "No" }, "{mode}");
    }
}

#[test]
fn compression_off_measures_nothing() {
    let _serial = serial();
    let (_tmp, cfg) = fixture(false, "always");
    let set = &cfg.sets[0];
    fs::write(set.source.join("big.txt"), text(3 * MIB)).unwrap();
    let report = engine::backup(&cfg, set);
    assert_eq!(report.code, 0, "{report:?}");
    assert_eq!(probe(&report), engine::ProbeCounters::default());
    assert!(serde_json::to_value(&report).unwrap()["probe"].is_object());
    assert!(!log_dir(set).exists());
    assert_eq!(compressed_of(&manifest(set), "big.txt"), "No");
}

#[cfg(feature = "test-hooks")]
mod forced_failures {
    use super::*;
    struct Fault;
    impl Fault {
        fn set(kind: &str) -> Self {
            // SAFETY: every test touching the variable holds SERIAL.
            unsafe { std::env::set_var("FILEBACKUP_TEST_PROBE_FAULT", kind) };
            Self
        }
    }
    impl Drop for Fault {
        fn drop(&mut self) {
            // SAFETY: as above.
            unsafe { std::env::remove_var("FILEBACKUP_TEST_PROBE_FAULT") };
        }
    }
    struct Stamp;
    impl Stamp {
        fn set(value: &str) -> Self {
            // SAFETY: every test touching the variable holds SERIAL.
            unsafe { std::env::set_var("FILEBACKUP_TEST_RUN_STAMP", value) };
            Self
        }
    }
    impl Drop for Stamp {
        fn drop(&mut self) {
            // SAFETY: as above.
            unsafe { std::env::remove_var("FILEBACKUP_TEST_RUN_STAMP") };
        }
    }
    fn log_names(set: &config::BackupSet) -> Vec<String> {
        let mut names: Vec<String> = fs::read_dir(log_dir(set))
            .unwrap()
            .map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
            .collect();
        names.sort();
        names
    }

    #[test]
    fn runs_starting_in_the_same_second_get_numbered_names() {
        let _serial = serial();
        let _stamp = Stamp::set("2030-01-02T03:04:05Z");
        let (_tmp, cfg) = fixture(true, "always");
        let set = &cfg.sets[0];
        for (i, name) in ["one.txt", "two.txt", "three.txt"].iter().enumerate() {
            fs::write(set.source.join(name), text(300 * 1024 + i)).unwrap();
            let report = engine::backup(&cfg, set);
            assert_eq!(report.code, 0, "{report:?}");
        }
        assert_eq!(
            log_names(set),
            [
                "2030_01_02_03_04_05.log",
                "2030_01_02_03_04_05_1.log",
                "2030_01_02_03_04_05_2.log"
            ]
        );
        // Each run wrote only its own decision.
        for name in log_names(set) {
            let body = fs::read_to_string(log_dir(set).join(name)).unwrap();
            assert_eq!(body.lines().count(), 1, "{body}");
        }
    }

    #[test]
    fn a_rotation_failure_keeps_the_log_and_warns_once() {
        let _serial = serial();
        let _fault = Fault::set("rotate");
        let (_tmp, cfg) = fixture(true, "always");
        let set = &cfg.sets[0];
        fs::write(set.source.join("a.txt"), text(300 * 1024)).unwrap();
        fs::write(set.source.join("b.txt"), text(301 * 1024)).unwrap();
        fs::write(set.source.join("c.txt"), text(302 * 1024)).unwrap();
        let report = engine::backup(&cfg, set);
        assert_eq!(report.code, 0, "{report:?}");
        let warnings = report
            .events
            .iter()
            .filter(|e| e.cause == "decision_log_unavailable")
            .count();
        assert_eq!(warnings, 1, "{report:?}");
        assert_eq!(decisions(set).len(), 3, "the log kept working");
        assert!(manifest(set).iter().all(|r| r.compressed == "Yes"));
    }

    #[test]
    fn a_retried_capture_counts_once_in_the_probe_counters() {
        let _serial = serial();
        let _fault = Fault::set("retry");
        let (_tmp, cfg) = fixture(true, "always");
        let set = &cfg.sets[0];
        let content = text(300 * 1024);
        fs::write(set.source.join("doc.txt"), &content).unwrap();
        let report = engine::backup(&cfg, set);
        assert_eq!(report.code, 0, "{report:?}");
        let p = probe(&report);
        assert_eq!((p.measured, p.compressed, p.raw), (1, 1, 0), "{p:?}");
        assert_eq!(p.bytes_compressed_in, content.len() as u64);
        assert!(p.bytes_compressed_out > 0 && p.bytes_compressed_out < p.bytes_compressed_in);
        // The decision line is written at decision time, so the retry repeats it.
        assert_eq!(decisions(set).len(), 2);
    }

    #[cfg(unix)]
    #[test]
    fn a_symlinked_log_folder_is_refused_with_one_warning() {
        let _serial = serial();
        let (_tmp, cfg) = fixture(true, "always");
        let set = &cfg.sets[0];
        fs::write(set.source.join("one.txt"), text(300 * 1024)).unwrap();
        assert_eq!(engine::backup(&cfg, set).code, 0);
        let elsewhere = set.store.parent().unwrap().join("elsewhere");
        fs::create_dir(&elsewhere).unwrap();
        fs::remove_dir_all(log_dir(set)).unwrap();
        std::os::unix::fs::symlink(&elsewhere, log_dir(set)).unwrap();
        fs::write(set.source.join("two.txt"), text(302 * 1024)).unwrap();
        fs::write(set.source.join("three.txt"), text(303 * 1024)).unwrap();
        let report = engine::backup(&cfg, set);
        assert_eq!(report.code, 0, "{report:?}");
        let warnings = report
            .events
            .iter()
            .filter(|e| e.cause == "decision_log_unavailable")
            .count();
        assert_eq!(warnings, 1, "{report:?}");
        assert_eq!(
            fs::read_dir(&elsewhere).unwrap().count(),
            0,
            "nothing followed the link"
        );
        assert_eq!(manifest(set).len(), 3);
    }

    #[test]
    fn a_sampler_or_coder_failure_falls_back_to_the_type_list() {
        let _serial = serial();
        for kind in ["sampler", "coder"] {
            let _fault = Fault::set(kind);
            let (_tmp, cfg) = fixture(true, "always");
            let set = &cfg.sets[0];
            fs::write(set.source.join("doc.txt"), text(300 * 1024)).unwrap();
            fs::write(set.source.join("clip.mkv"), random(31, 300 * 1024)).unwrap();
            let report = engine::backup(&cfg, set);
            assert_eq!(report.code, 0, "{kind}: {report:?}");
            let p = probe(&report);
            assert_eq!((p.fallback, p.measured), (2, 0), "{kind}: {p:?}");
            assert_eq!(
                report
                    .findings
                    .iter()
                    .filter(|f| f.contains("type fallback used"))
                    .count(),
                2,
                "{kind}: {report:?}"
            );
            let rows = manifest(set);
            assert_eq!(compressed_of(&rows, "doc.txt"), "Yes", "{kind}");
            assert_eq!(compressed_of(&rows, "clip.mkv"), "No", "{kind}");
            let lines = decisions(set);
            assert_eq!(lines.len(), 2, "{kind}");
            for line in lines {
                assert_eq!(line[4], "fallback");
                assert_eq!((line[5].as_str(), line[6].as_str()), ("-", "-"));
            }
        }
    }
}

#[test]
fn log_retention_keeps_thirty_and_spares_everything_else() {
    let _serial = serial();
    let (_tmp, cfg) = fixture(true, "always");
    let set = &cfg.sets[0];
    fs::write(set.source.join("one.txt"), text(300 * 1024)).unwrap();
    assert_eq!(engine::backup(&cfg, set).code, 0);
    let dir = log_dir(set);
    for i in 0..35 {
        fs::write(dir.join(format!("2000_01_01_00_00_{i:02}.log")), "old\n").unwrap();
    }
    fs::write(dir.join("2000_01_01_00_00_00_7.log"), "old\n").unwrap();
    for spared in [
        "notes.txt",
        "2000_01_01_00_00_00.log.bak",
        "x2000_01_01_00_00_00.log",
        "2000_01_01_00_00_00_.log",
    ] {
        fs::write(dir.join(spared), "keep\n").unwrap();
    }
    fs::create_dir(dir.join("2000_01_01_00_00_99.log")).unwrap();
    fs::write(set.source.join("two.txt"), text(301 * 1024)).unwrap();
    let report = engine::backup(&cfg, set);
    assert_eq!(
        report.code, 0,
        "second run on a store holding the folder: {report:?}"
    );
    assert!(
        report
            .events
            .iter()
            .all(|e| e.cause != "decision_log_unavailable")
    );
    let names: Vec<String> = fs::read_dir(&dir)
        .unwrap()
        .map(|e| e.unwrap())
        .filter(|e| e.file_type().unwrap().is_file())
        .map(|e| e.file_name().to_string_lossy().into_owned())
        .collect();
    let ours = |n: &&String| {
        n.len() >= 23
            && n.ends_with(".log")
            && n.as_bytes()[..4].iter().all(u8::is_ascii_digit)
            && !n.ends_with("_.log")
            && n.as_bytes()[0] != b'x'
    };
    assert_eq!(names.iter().filter(ours).count(), 30, "{names:?}");
    for spared in [
        "notes.txt",
        "2000_01_01_00_00_00.log.bak",
        "x2000_01_01_00_00_00.log",
        "2000_01_01_00_00_00_.log",
    ] {
        assert!(names.iter().any(|n| n == spared), "{spared} was touched");
    }
    assert!(dir.join("2000_01_01_00_00_99.log").is_dir());
    // Both real runs survive; the oldest fillers went.
    let real = names
        .iter()
        .filter(|n| n.starts_with("20") && !n.starts_with("2000"))
        .filter(|n| fs::read_to_string(dir.join(n)).unwrap().contains(".txt\t"))
        .count();
    assert_eq!(real, 2, "{names:?}");
    assert!(!dir.join("2000_01_01_00_00_00.log").exists());
}

#[test]
fn an_unusable_log_folder_is_one_warning_and_a_good_run() {
    let _serial = serial();
    let (_tmp, cfg) = fixture(true, "always");
    let set = &cfg.sets[0];
    fs::write(set.source.join("one.txt"), text(300 * 1024)).unwrap();
    assert_eq!(engine::backup(&cfg, set).code, 0);
    // A plain file where the folder belongs.
    fs::remove_dir_all(log_dir(set)).unwrap();
    fs::write(log_dir(set), "not a folder").unwrap();
    fs::write(set.source.join("two.txt"), text(302 * 1024)).unwrap();
    fs::write(set.source.join("three.txt"), text(303 * 1024)).unwrap();
    let report = engine::backup(&cfg, set);
    assert_eq!(report.code, 0, "{report:?}");
    assert_eq!(
        report
            .events
            .iter()
            .filter(|e| e.cause == "decision_log_unavailable")
            .count(),
        1,
        "{report:?}"
    );
    let rows = manifest(set);
    assert_eq!(rows.len(), 3);
    assert!(rows.iter().all(|r| r.compressed == "Yes"));
    assert_eq!(probe(&report).measured, 2);
    assert_eq!(fs::read_to_string(log_dir(set)).unwrap(), "not a folder");
}
