#![cfg(feature = "test-hooks")]
//! LLR-191 / TC-302. Runs go through the binary, because the lines are its stderr.
//! A short injected interval and held reads stand in for an hours-long file.
use filebackup::{
    format,
    progress::{Counters, Phase, Reading, format_bytes},
    store::Store,
};
use std::{
    fs,
    io::{BufRead, BufReader, Read},
    path::{Path, PathBuf},
    process::{Command, Output, Stdio},
    sync::Arc,
    time::{Duration, Instant},
};

const SET: &str = "progress-set";
const NAME: &str = "private-name";
const REPORT_KEYS: [&str; 14] = [
    "action",
    "added",
    "captured",
    "changed",
    "code",
    "elapsed_ms",
    "events",
    "failed",
    "findings",
    "frozen",
    "removed",
    "reused",
    "schema_version",
    "set",
];

struct Fixture {
    tmp: tempfile::TempDir,
    source: PathBuf,
    config: PathBuf,
}
fn fixture(set: &str, compress: bool) -> Fixture {
    fixture_every(set, compress, "W")
}
fn fixture_every(set: &str, compress: bool, frequency: &str) -> Fixture {
    let tmp = tempfile::tempdir().unwrap();
    let source = tmp.path().join("source");
    fs::create_dir(&source).unwrap();
    let config = tmp.path().join("config.json");
    fs::write(&config, serde_json::to_vec(&serde_json::json!({"ConfigVersion":3,"BackupSets":[{"Name":set,"SourcePath":source,"StorePath":tmp.path().join("store"),"CompressEnabled":compress,"HashRecalcFreq":frequency}]})).unwrap()).unwrap();
    Fixture {
        tmp,
        source,
        config,
    }
}
fn command(config: &Path, action: &[&str], env: &[(&str, &str)]) -> Command {
    let mut command = Command::new(env!("CARGO_BIN_EXE_filebackup"));
    command.args(action).arg("--config").arg(config);
    command.envs(env.iter().copied());
    command
}
fn run(f: &Fixture, action: &[&str], env: &[(&str, &str)]) -> Output {
    command(&f.config, action, env).output().unwrap()
}
fn stderr(output: &Output) -> String {
    String::from_utf8(output.stderr.clone()).unwrap()
}
fn report(output: &Output) -> serde_json::Value {
    let text = String::from_utf8(output.stdout.clone()).unwrap();
    assert_eq!(text.lines().count(), 1, "stdout is one report: {text}");
    serde_json::from_str(text.trim()).unwrap()
}
fn keys(report: &serde_json::Value) -> Vec<String> {
    report.as_object().unwrap().keys().cloned().collect()
}
// Every line is a progress line, with no path, file name or store location in it.
fn assert_only_numbers(text: &str, f: &Fixture) {
    let root = f.tmp.path().to_string_lossy();
    assert!(!text.is_empty());
    for line in text.lines() {
        assert!(
            line.starts_with(&format!("Progress: set '{SET}', ")),
            "{line}"
        );
        assert!(!line.contains(NAME), "file name in: {line}");
        assert!(!line.contains(root.as_ref()), "path in: {line}");
        assert!(
            !line.contains('/') && !line.contains('\\'),
            "path in: {line}"
        );
        assert!(!line.contains("0 of 0"), "unknown total shown: {line}");
    }
}

#[test]
fn a_line_says_its_phase_and_only_shows_a_known_total() {
    let c = Arc::new(Counters::default());
    assert_eq!(c.line("s", 1), "Progress: set 's', preparing, 1 s\n");
    c.enter(Phase::IndexingStore);
    assert_eq!(c.line("s", 2), "Progress: set 's', indexing store, 2 s\n");
    c.enter(Phase::WalkingSource);
    assert_eq!(c.line("s", 3), "Progress: set 's', walking source, 3 s\n");
    c.enter_counted(Phase::Capturing, 197000);
    for _ in 0..5120 {
        c.item_done();
    }
    let mut read = Reading::new(&[7u8; 2048][..], &c);
    std::io::copy(&mut read, &mut std::io::sink()).unwrap();
    assert_eq!(
        c.line("s", 3600),
        "Progress: set 's', capturing: 5120 of 197000 file(s), 2.0 KiB read, 3600 s\n"
    );
    c.enter(Phase::Finishing);
    assert!(c.line("s", 4).contains("finishing: 5120 of 197000 file(s)"));
    assert_eq!(format_bytes(512), "512 B");
    assert_eq!(format_bytes(90_409_061_581), "84.2 GiB");
}

#[test]
fn a_held_file_keeps_printing_with_right_counts_and_no_names() {
    let f = fixture(SET, false);
    fs::write(f.source.join(format!("{NAME}-a.bin")), vec![1u8; 1024]).unwrap();
    fs::write(
        f.source.join(format!("{NAME}-b.bin")),
        vec![2u8; 600 * 1024],
    )
    .unwrap();
    let output = run(
        &f,
        &["backup"],
        &[
            ("FILEBACKUP_TEST_PROGRESS_MS", "20"),
            ("FILEBACKUP_TEST_READ_HOLD_MS", "200"),
            (
                "FILEBACKUP_TEST_HOLD",
                "pool-indexed=200,source-walked=200,capture-finished=300",
            ),
        ],
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    let text = stderr(&output);
    assert_only_numbers(&text, &f);
    assert!(text.contains("indexing store, "), "{text}");
    assert!(text.contains("walking source, "), "{text}");
    // One file is finished and the other is inside its read: the timer does not care.
    let held = |read: &str| {
        text.lines()
            .filter(|l| l.contains(&format!("capturing: 1 of 2 file(s), {read} read")))
            .count()
    };
    assert!(held("257.0 KiB") >= 2, "{text}");
    assert!(held("513.0 KiB") >= 2, "{text}");
    assert!(
        text.contains("finishing: 2 of 2 file(s), 601.0 KiB read"),
        "{text}"
    );
    let r = report(&output);
    // A backup report also carries the compression probe counters (LLR-162).
    let mut backup_keys = REPORT_KEYS.map(String::from).to_vec();
    backup_keys.insert(10, "probe".into());
    assert_eq!(keys(&r), backup_keys, "the report gained or lost a field");
    assert_eq!(r["captured"], 2);
    assert_eq!(r["failed"], 0);
    let log = fs::read_to_string(f.tmp.path().join("store/backup.log")).unwrap();
    assert_eq!(log.lines().count(), 1, "{log}");
    assert_eq!(
        keys(&serde_json::from_str(log.trim()).unwrap()),
        backup_keys
    );
}

#[test]
fn a_retried_file_is_counted_once() {
    let f = fixture(SET, false);
    let path = f.source.join(format!("{NAME}.bin"));
    fs::write(&path, vec![3u8; 600 * 1024]).unwrap();
    let mut child = command(
        &f.config,
        &["backup"],
        &[
            ("FILEBACKUP_TEST_PROGRESS_MS", "20"),
            ("FILEBACKUP_TEST_READ_HOLD_MS", "500"),
            ("FILEBACKUP_TEST_HOLD", "capture-finished=300"),
        ],
    )
    .stdout(Stdio::piped())
    .stderr(Stdio::piped())
    .spawn()
    .unwrap();
    let mut text = String::new();
    let mut changed = false;
    for line in BufReader::new(child.stderr.take().unwrap()).lines() {
        let line = line.unwrap();
        // Change the file under its first read, so that attempt fails and is retried.
        if !changed && line.contains("256.0 KiB read") {
            fs::write(&path, vec![4u8; 300 * 1024]).unwrap();
            changed = true;
        }
        text.push_str(&line);
        text.push('\n');
    }
    let output = child.wait_with_output().unwrap();
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(changed, "{text}");
    assert_only_numbers(&text, &f);
    // While it waits for its retry the failed attempt counts for nothing.
    let attempt = text.find("256.0 KiB read").unwrap();
    assert!(
        text[attempt..].contains("capturing: 0 of 1 file(s), 0 B read"),
        "{text}"
    );
    assert!(
        text.contains("finishing: 1 of 1 file(s), 300.0 KiB read"),
        "{text}"
    );
    let r = report(&output);
    assert_eq!(r["captured"], 1);
    assert_eq!(r["failed"], 0);
}

#[test]
fn a_scheduled_reread_counts_its_bytes_and_a_changed_file_once() {
    let f = fixture_every(SET, false, "A");
    let (keep, swap) = (f.source.join("keep"), f.source.join("swap"));
    fs::write(&keep, vec![1u8; 1024]).unwrap();
    fs::write(&swap, vec![2u8; 2048]).unwrap();
    assert_eq!(run(&f, &["backup"], &[]).status.code(), Some(0));
    // Same size and time, other bytes: only the re-read can notice, then it captures.
    let stamp = fs::metadata(&swap).unwrap().modified().unwrap();
    fs::write(&swap, vec![3u8; 2048]).unwrap();
    let file = fs::File::options().write(true).open(&swap).unwrap();
    file.set_modified(stamp).unwrap();
    drop(file);
    let output = run(
        &f,
        &["backup"],
        &[
            ("FILEBACKUP_TEST_PROGRESS_MS", "20"),
            ("FILEBACKUP_TEST_HOLD", "capture-finished=300"),
        ],
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    let text = stderr(&output);
    assert!(
        text.contains("finishing: 2 of 2 file(s), 3.0 KiB read"),
        "{text}"
    );
    let r = report(&output);
    assert_eq!(r["reused"], 1);
    assert_eq!(r["captured"], 1);
}

fn two_states(f: &Fixture) {
    fs::write(f.source.join("a"), vec![5u8; 300 * 1024]).unwrap();
    fs::write(f.source.join("b"), vec![6u8; 1024]).unwrap();
    assert_eq!(run(f, &["backup"], &[]).status.code(), Some(0));
    fs::write(f.source.join("a"), vec![7u8; 300 * 1024]).unwrap();
    assert_eq!(run(f, &["backup"], &[]).status.code(), Some(0));
}

#[test]
fn deep_verify_counts_each_object_once_during_a_held_read() {
    let f = fixture(SET, false);
    two_states(&f); // Two old and one new object; "b" appears in both states.
    let output = run(
        &f,
        &["verify", "--deep"],
        &[
            ("FILEBACKUP_TEST_PROGRESS_MS", "20"),
            ("FILEBACKUP_TEST_READ_HOLD_MS", "200"),
            ("FILEBACKUP_TEST_HOLD", "verify-objects-checked=300"),
        ],
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    let text = stderr(&output);
    assert_only_numbers(&text, &f);
    assert!(
        text.contains("deep verify: 0 of 3 object(s), 256.0 KiB read"),
        "{text}"
    );
    assert!(
        text.contains("deep verify: 3 of 3 object(s), 601.0 KiB read"),
        "{text}"
    );
    let r = report(&output);
    let mut expected = REPORT_KEYS.map(String::from).to_vec();
    expected.insert(5, "details".into());
    assert_eq!(keys(&r), expected, "the report gained or lost a field");
    assert_eq!(r["details"]["inspection_mode"], "verified_content");
}

#[test]
fn deep_verify_counts_expanded_bytes_of_an_archive() {
    let f = fixture(SET, true);
    fs::write(f.source.join("a.txt"), vec![b'x'; 600 * 1024]).unwrap();
    assert_eq!(run(&f, &["backup"], &[]).status.code(), Some(0));
    let output = run(
        &f,
        &["verify", "--deep"],
        &[
            ("FILEBACKUP_TEST_PROGRESS_MS", "20"),
            ("FILEBACKUP_TEST_HOLD", "verify-objects-checked=300"),
        ],
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    let text = stderr(&output);
    assert!(
        text.contains("deep verify: 1 of 1 object(s), 600.0 KiB read"),
        "{text}"
    );
}

#[test]
fn deep_verify_counts_an_object_no_record_names() {
    let f = fixture(SET, false);
    assert_eq!(run(&f, &["backup"], &[]).status.code(), Some(0));
    let bytes = vec![9u8; 2048];
    let key = format::copy_hash(&bytes[..], std::io::sink()).unwrap();
    let name = format::object_name(&key, "").unwrap();
    let object = Store::new(&f.tmp.path().join("store")).path(&name).unwrap();
    fs::create_dir_all(object.parent().unwrap()).unwrap();
    fs::write(&object, bytes).unwrap();
    let output = run(
        &f,
        &["verify", "--deep"],
        &[
            ("FILEBACKUP_TEST_PROGRESS_MS", "20"),
            ("FILEBACKUP_TEST_HOLD", "verify-objects-checked=300"),
        ],
    );
    let text = stderr(&output);
    assert!(
        text.contains("deep verify: 1 of 1 object(s), 2.0 KiB read"),
        "{text}"
    );
}

#[test]
fn quick_verify_counts_states_and_records() {
    let f = fixture(SET, false);
    two_states(&f);
    let output = run(
        &f,
        &["verify"],
        &[
            ("FILEBACKUP_TEST_PROGRESS_MS", "20"),
            ("FILEBACKUP_TEST_HOLD", "verify-objects-checked=300"),
        ],
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    let text = stderr(&output);
    assert_only_numbers(&text, &f);
    assert!(
        text.contains("quick verify: 2 of 2 state(s), 4 record(s)"),
        "{text}"
    );
    assert_eq!(
        report(&output)["details"]["inspection_mode"],
        "metadata_only"
    );
}

#[test]
fn a_stalled_stderr_reader_cannot_hold_a_run() {
    // Long lines fill the pipe within the run; nothing below ever reads it.
    let f = fixture(&"long-set-name-".repeat(30), false);
    fs::write(f.source.join("a.bin"), vec![8u8; 600 * 1024]).unwrap();
    let start = Instant::now();
    let mut child = command(
        &f.config,
        &["backup"],
        &[
            ("FILEBACKUP_TEST_PROGRESS_MS", "1"),
            ("FILEBACKUP_TEST_READ_HOLD_MS", "800"),
        ],
    )
    .stdout(Stdio::piped())
    .stderr(Stdio::piped())
    .spawn()
    .unwrap();
    let held = child.stderr.take().unwrap();
    let status = loop {
        if let Some(status) = child.try_wait().unwrap() {
            break status;
        }
        if start.elapsed() > Duration::from_secs(30) {
            child.kill().unwrap();
            child.wait().unwrap();
            panic!("the run hung on its reporter");
        }
        std::thread::sleep(Duration::from_millis(50));
    };
    assert_eq!(status.code(), Some(0));
    // The reporter really was stuck: the run paid the bounded wait for it.
    assert!(start.elapsed() >= Duration::from_millis(2400 + 1900));
    let mut text = String::new();
    child
        .stdout
        .take()
        .unwrap()
        .read_to_string(&mut text)
        .unwrap();
    assert_eq!(
        serde_json::from_str::<serde_json::Value>(text.trim()).unwrap()["captured"],
        1
    );
    drop(held);
}

// In process, because a child's threads end with it whether or not they were stopped.
#[cfg(target_os = "linux")]
#[test]
fn the_reporter_ends_on_success_and_every_error_path() {
    use filebackup::{config, engine, maintenance, progress::Reporter};
    fn reporters() -> usize {
        fs::read_dir("/proc/self/task")
            .unwrap()
            .flatten()
            .filter(|task| {
                fs::read_to_string(task.path().join("comm"))
                    .is_ok_and(|name| name.trim() == "fb-progress")
            })
            .count()
    }
    let reporter = Reporter::start("direct");
    let start = Instant::now(); // The new thread names itself as it starts.
    while reporters() == 0 && start.elapsed() < Duration::from_secs(5) {
        std::thread::sleep(Duration::from_millis(5));
    }
    assert_eq!(reporters(), 1, "the thread must be findable by its name");
    let shared = reporter.counters().clone();
    drop(reporter);
    assert_eq!(reporters(), 0);
    assert_eq!(Arc::strong_count(&shared), 1);

    let f = fixture(SET, false);
    fs::write(f.source.join("a"), b"bytes").unwrap();
    let cfg = config::load(&f.config).unwrap();
    let set = &cfg.sets[0];
    let finish = |code: i32, r: engine::Report, what: &str| {
        assert_eq!(r.code, code, "{what}: {r:?}");
        assert_eq!(reporters(), 0, "{what} left its reporter running");
    };
    finish(0, engine::backup(&cfg, set), "a backup");
    finish(0, maintenance::verify(set, false, false), "a quick verify");
    finish(0, maintenance::verify(set, true, false), "a deep verify");

    // A failure inside the capture work itself, after the store is open.
    let previous = set.store.join("CurrentBackup/MANIFEST.csv.prev");
    fs::create_dir(&previous).unwrap();
    finish(4, engine::backup(&cfg, set), "a failure inside the work");
    fs::remove_dir(&previous).unwrap();

    let plan = set.store.join("PrunePlan.json");
    fs::write(&plan, b"[]").unwrap();
    finish(2, engine::backup(&cfg, set), "an early refusal");
    fs::remove_file(&plan).unwrap();

    let moved = f.tmp.path().join("moved");
    fs::rename(&f.source, &moved).unwrap();
    finish(4, engine::backup(&cfg, set), "a missing source");
    fs::rename(&moved, &f.source).unwrap();

    fs::rename(&set.store, f.tmp.path().join("gone")).unwrap();
    finish(4, maintenance::verify(set, true, false), "a failed verify");
}

#[test]
fn the_step_lines_publish_first_and_carry_no_path() {
    let c = Arc::new(Counters::default());
    c.enter_counted(Phase::Capturing, 4);
    c.item_done();
    {
        let _step = c.enter_step(Phase::Compressing, 600 * 1024);
        assert_eq!(
            c.line("s", 7),
            "Progress: set 's', compressing: 1 of 4 file(s), 0 B of a 600.0 KiB file written, 7 s\n"
        );
        c.step_set(2048);
        assert_eq!(
            c.line("s", 8),
            "Progress: set 's', compressing: 1 of 4 file(s), 2.0 KiB of a 600.0 KiB file written, 8 s\n"
        );
    }
    {
        let _step = c.enter_step(Phase::CheckingArchive, 1024);
        assert_eq!(
            c.line("s", 9),
            "Progress: set 's', checking archive: 1 of 4 file(s), 0 B of 1.0 KiB expanded, 9 s\n"
        );
    }
}

#[test]
fn a_step_counts_into_its_own_counter_and_the_guard_restores_on_every_way_out() {
    fn failing(c: &Arc<Counters>) -> anyhow::Result<()> {
        let _step = c.enter_step(Phase::CheckingArchive, 4096);
        let mut read = Reading::step(&[1u8; 4096][..], c);
        std::io::copy(&mut read, &mut std::io::sink())?;
        anyhow::ensure!(false, "forced failure");
        Ok(())
    }
    let c = Arc::new(Counters::default());
    c.enter_counted(Phase::Capturing, 1);
    let mut read = Reading::new(&[2u8; 1000][..], &c);
    std::io::copy(&mut read, &mut std::io::sink()).unwrap();
    {
        let _step = c.enter_step(Phase::Compressing, 99);
        c.step_set(50);
        assert_eq!(c.step_counts(), (50, 99));
    }
    assert_eq!(c.step_counts(), (0, 0));
    assert!(
        c.line("s", 1)
            .contains("capturing: 0 of 1 file(s), 1000 B read")
    );
    assert!(failing(&c).is_err());
    assert_eq!(c.step_counts(), (0, 0), "cleared after a forced failure");
    assert!(
        c.line("s", 2)
            .contains("capturing: 0 of 1 file(s), 1000 B read")
    );
    // The step's bytes never reached "bytes read".
    assert_eq!(c.bytes_read(), 1000);
}

// A compressible file above the probe floor, so the set stores it as an archive.
fn compressible(f: &Fixture) -> usize {
    let bytes = vec![b'x'; 600 * 1024];
    fs::write(f.source.join(format!("{NAME}.txt")), &bytes).unwrap();
    bytes.len()
}

#[test]
fn a_held_compression_shows_a_rising_archive_and_no_names() {
    let f = fixture(SET, true);
    let source = compressible(&f);
    let output = run(
        &f,
        &["backup"],
        &[
            ("FILEBACKUP_TEST_PROGRESS_MS", "20"),
            ("FILEBACKUP_TEST_COMPRESS_POLL_MS", "30"),
            ("FILEBACKUP_TEST_COMPRESS_HOLD_MS", "1500"),
            (
                "FILEBACKUP_TEST_COMPRESS_SIZES",
                "1024,2048,3072,4096,5120,6144,7168,8192",
            ),
            ("FILEBACKUP_TEST_HOLD", "capture-finished=300"),
        ],
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    let text = stderr(&output);
    assert_only_numbers(&text, &f);
    let shown = |written: &str| {
        text.contains(&format!(
            "compressing: 0 of 1 file(s), {written} of a 600.0 KiB file written"
        ))
    };
    assert!(shown("1.0 KiB"), "{text}");
    assert!(shown("3.0 KiB") || shown("2.0 KiB"), "{text}");
    assert!(shown("5.0 KiB") || shown("6.0 KiB"), "{text}");
    for banned in ["archive-", "content.7z"] {
        assert!(!text.contains(banned), "{banned} in: {text}");
    }
    // Bytes read is still the one pass over the source, and the phase came back.
    assert!(
        text.contains(&format!(
            "finishing: 1 of 1 file(s), {} read",
            format_bytes(source as u64)
        )),
        "{text}"
    );
    assert_eq!(report(&output)["captured"], 1);
}

#[test]
fn a_compression_that_stops_growing_is_a_host_stop_naming_the_stall() {
    let f = fixture(SET, true);
    compressible(&f);
    let output = run(
        &f,
        &["backup"],
        &[
            ("FILEBACKUP_TEST_COMPRESS_POLL_MS", "30"),
            ("FILEBACKUP_TEST_COMPRESS_HOLD_MS", "5000"),
            ("FILEBACKUP_TEST_STALL_MS", "300"),
            ("FILEBACKUP_TEST_COMPRESS_SIZES", "1024,2048,2048"),
        ],
    );
    assert_eq!(output.status.code(), Some(4), "{output:?}");
    let all = format!("{}{}", stderr(&output), report(&output));
    assert!(all.contains("compression stalled"), "{all}");
    assert!(!all.contains("time ceiling"), "{all}");
}

#[test]
fn a_growing_compression_is_not_stopped_by_the_stall_bound() {
    let f = fixture(SET, true);
    compressible(&f);
    // Growth on every poll for far longer than the 300 ms window.
    let sizes: Vec<String> = (1..=200).map(|n| (n * 100).to_string()).collect();
    let output = run(
        &f,
        &["backup"],
        &[
            ("FILEBACKUP_TEST_COMPRESS_POLL_MS", "30"),
            ("FILEBACKUP_TEST_COMPRESS_HOLD_MS", "1200"),
            ("FILEBACKUP_TEST_STALL_MS", "300"),
            ("FILEBACKUP_TEST_COMPRESS_SIZES", &sizes.join(",")),
        ],
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert_eq!(report(&output)["captured"], 1);
}

#[test]
fn a_held_archive_check_shows_a_rising_count_and_no_names() {
    let f = fixture(SET, true);
    let source = compressible(&f);
    let output = run(
        &f,
        &["backup"],
        &[
            ("FILEBACKUP_TEST_PROGRESS_MS", "20"),
            ("FILEBACKUP_TEST_READ_HOLD_MS", "150"),
            ("FILEBACKUP_TEST_HOLD", "capture-finished=300"),
        ],
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    let text = stderr(&output);
    assert_only_numbers(&text, &f);
    let counts: Vec<&str> = text
        .lines()
        .filter(|l| l.contains("checking archive: 0 of 1 file(s), "))
        .filter_map(|l| l.split(", ").nth(2))
        .collect();
    let mut distinct = counts.clone();
    distinct.dedup();
    assert!(distinct.len() >= 2, "the count did not move: {text}");
    assert!(
        counts.iter().all(|c| c.ends_with("of 600.0 KiB expanded")),
        "{counts:?}"
    );
    for banned in ["archive-", "content.7z"] {
        assert!(!text.contains(banned), "{banned} in: {text}");
    }
    // The archive check counted into its own counter: bytes read is the source once.
    assert!(
        text.contains(&format!(
            "finishing: 1 of 1 file(s), {} read",
            format_bytes(source as u64)
        )),
        "{text}"
    );
}

#[test]
fn a_held_dedup_check_of_an_existing_object_shows_checking_archive() {
    let f = fixture(SET, true);
    let source = compressible(&f);
    assert_eq!(run(&f, &["backup"], &[]).status.code(), Some(0));
    fs::copy(
        f.source.join(format!("{NAME}.txt")),
        f.source.join(format!("{NAME}-copy.txt")),
    )
    .unwrap();
    let output = run(
        &f,
        &["backup"],
        &[
            ("FILEBACKUP_TEST_PROGRESS_MS", "20"),
            ("FILEBACKUP_TEST_READ_HOLD_MS", "150"),
            ("FILEBACKUP_TEST_HOLD", "capture-finished=300"),
        ],
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    let text = stderr(&output);
    assert_only_numbers(&text, &f);
    assert!(
        text.contains("checking archive: 0 of 2 file(s), "),
        "{text}"
    );
    assert!(
        text.contains(&format!(
            "finishing: 2 of 2 file(s), {} read",
            format_bytes(source as u64)
        )),
        "{text}"
    );
    assert_eq!(report(&output)["captured"], 1);
}
