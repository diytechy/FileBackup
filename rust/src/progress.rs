//! LLR-191: timed progress on stderr. The worker only bumps relaxed atomics and one
//! reporter thread prints on a timer, so a line still appears while the worker sits
//! in one huge read, a compressor or a slow disk. A line carries the set name, the
//! phase and numbers, never a path: stderr reaches the system journal.
use crate::format::{self, ContentKey};
use anyhow::Result;
use std::{
    fs::File,
    io::{self, Read, Write},
    path::Path,
    sync::{
        Arc,
        atomic::{
            AtomicU8, AtomicU64,
            Ordering::{Acquire, Relaxed, Release},
        },
        mpsc::{self, RecvTimeoutError},
    },
    thread,
    time::{Duration, Instant},
};

const INTERVAL: Duration = Duration::from_secs(60);
// A reporter blocked on a stalled stderr reader is left behind, never waited for.
const STOP_WAIT: Duration = Duration::from_secs(2);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Phase {
    Preparing,
    IndexingStore,
    WalkingSource,
    Capturing,
    Finishing,
    QuickVerify,
    DeepVerify,
    Compressing,
    CheckingArchive,
}
const PHASES: [(Phase, &str); 9] = [
    (Phase::Preparing, "preparing"),
    (Phase::IndexingStore, "indexing store"),
    (Phase::WalkingSource, "walking source"),
    (Phase::Capturing, "capturing"),
    (Phase::Finishing, "finishing"),
    (Phase::QuickVerify, "quick verify"),
    (Phase::DeepVerify, "deep verify"),
    (Phase::Compressing, "compressing"),
    (Phase::CheckingArchive, "checking archive"),
];

/// Shared run counters: the worker writes them, the reporter only reads them.
#[derive(Default)]
pub struct Counters {
    phase: AtomicU8,
    total: AtomicU64,
    done: AtomicU64,
    bytes: AtomicU64,
    records: AtomicU64,
    // The progress of one step inside a file (archive bytes written, or bytes
    // expanded), kept apart from `bytes` so a file's bytes still count once.
    step_done: AtomicU64,
    step_total: AtomicU64,
}
/// Puts the phase back to `Capturing` and clears the step counters when it drops,
/// on success and on every early return alike.
pub struct StepGuard<'a>(&'a Counters);
impl Drop for StepGuard<'_> {
    fn drop(&mut self) {
        self.0.enter(Phase::Capturing);
        self.0.step_done.store(0, Relaxed);
        self.0.step_total.store(0, Relaxed);
    }
}
impl Counters {
    pub fn enter(&self, phase: Phase) {
        self.phase.store(phase as u8, Release);
    }
    /// The total is published first, so a counted phase never shows a stale one.
    pub fn enter_counted(&self, phase: Phase, total: u64) {
        self.total.store(total, Relaxed);
        self.enter(phase);
    }
    /// Enter a step phase inside a file. The step's total and a zero done are
    /// published first, as `enter_counted` does, so no line shows the previous
    /// file's figures. The phase returns to `Capturing` when the guard drops.
    pub fn enter_step(&self, phase: Phase, total: u64) -> StepGuard<'_> {
        self.step_total.store(total, Relaxed);
        self.step_done.store(0, Relaxed);
        self.enter(phase);
        StepGuard(self)
    }
    /// The step's progress as the tool reports it (an archive's size so far).
    pub fn step_set(&self, done: u64) {
        self.step_done.store(done, Relaxed);
    }
    /// The step's (done, total).
    pub fn step_counts(&self) -> (u64, u64) {
        (self.step_done.load(Relaxed), self.step_total.load(Relaxed))
    }
    /// One finished unit of the phase's total. A retried attempt is not one.
    pub fn item_done(&self) {
        self.done.fetch_add(1, Relaxed);
    }
    pub fn record_seen(&self) {
        self.records.fetch_add(1, Relaxed);
    }
    pub fn bytes_read(&self) -> u64 {
        self.bytes.load(Relaxed)
    }
    /// Take back an abandoned read, so a file counts its bytes once however often
    /// it is attempted. The worker is the only writer while it can abandon one.
    pub fn rewind_bytes(&self, mark: u64) {
        self.bytes.store(mark, Relaxed);
    }
    /// Numbers and the phase only. A total is shown only once it is known.
    pub fn line(&self, set: &str, seconds: u64) -> String {
        let (phase, label) = PHASES[self.phase.load(Acquire) as usize];
        let (done, total) = (self.done.load(Relaxed), self.total.load(Relaxed));
        let read = format_bytes(self.bytes_read());
        let head = format!("Progress: set '{set}', {label}");
        match phase {
            Phase::Preparing | Phase::IndexingStore | Phase::WalkingSource => {
                format!("{head}, {seconds} s\n")
            }
            Phase::Capturing | Phase::Finishing => {
                format!("{head}: {done} of {total} file(s), {read} read, {seconds} s\n")
            }
            Phase::DeepVerify => {
                format!("{head}: {done} of {total} object(s), {read} read, {seconds} s\n")
            }
            Phase::Compressing => {
                let (x, y) = self.step_counts();
                let (x, y) = (format_bytes(x), format_bytes(y));
                format!(
                    "{head}: {done} of {total} file(s), {x} of a {y} file written, {seconds} s\n"
                )
            }
            Phase::CheckingArchive => {
                let (x, y) = self.step_counts();
                let (x, y) = (format_bytes(x), format_bytes(y));
                format!("{head}: {done} of {total} file(s), {x} of {y} expanded, {seconds} s\n")
            }
            Phase::QuickVerify => {
                let records = self.records.load(Relaxed);
                format!("{head}: {done} of {total} state(s), {records} record(s), {seconds} s\n")
            }
        }
    }
}
pub fn format_bytes(bytes: u64) -> String {
    const UNITS: [&str; 5] = ["B", "KiB", "MiB", "GiB", "TiB"];
    let mut value = bytes as f64;
    let mut unit = 0;
    while value >= 1024.0 && unit + 1 < UNITS.len() {
        value /= 1024.0;
        unit += 1;
    }
    if unit == 0 {
        format!("{bytes} B")
    } else {
        format!("{value:.1} {}", UNITS[unit])
    }
}

/// Counts bytes as they pass, with no extra read or stat.
pub struct Reading<R> {
    inner: R,
    counters: Arc<Counters>,
    step: bool,
}
impl<R> Reading<R> {
    pub fn new(inner: R, counters: &Arc<Counters>) -> Self {
        Self {
            inner,
            counters: counters.clone(),
            step: false,
        }
    }
    /// As `new`, but the bytes go to the step counter and never to `bytes`.
    pub fn step(inner: R, counters: &Arc<Counters>) -> Self {
        Self {
            step: true,
            ..Self::new(inner, counters)
        }
    }
}
impl<R: Read> Read for Reading<R> {
    fn read(&mut self, buffer: &mut [u8]) -> io::Result<usize> {
        let n = self.inner.read(buffer)?;
        let target = if self.step {
            &self.counters.step_done
        } else {
            &self.counters.bytes
        };
        target.fetch_add(n as u64, Relaxed);
        #[cfg(feature = "test-hooks")]
        if n > 0
            && let Some(ms) = test_ms("FILEBACKUP_TEST_READ_HOLD_MS")
        {
            thread::sleep(Duration::from_millis(ms));
        }
        Ok(n)
    }
}
/// `format::hash_file` with its bytes counted.
pub fn hash_file(path: &Path, counters: &Arc<Counters>) -> Result<ContentKey> {
    format::copy_hash(Reading::new(File::open(path)?, counters), io::sink())
}

/// `hash_file`, counting into the step counter instead of `bytes`.
pub fn hash_file_step(path: &Path, counters: &Arc<Counters>) -> Result<ContentKey> {
    format::copy_hash(Reading::step(File::open(path)?, counters), io::sink())
}

#[cfg(feature = "test-hooks")]
pub fn test_ms(name: &str) -> Option<u64> {
    std::env::var(name).ok()?.parse().ok()
}
fn interval() -> Duration {
    #[cfg(feature = "test-hooks")]
    if let Some(ms) = test_ms("FILEBACKUP_TEST_PROGRESS_MS") {
        return Duration::from_millis(ms);
    }
    INTERVAL
}

/// Owns the reporter thread. Dropping it stops the thread, so every way out of a
/// run ends it; nothing the thread does can reach the run's result.
pub struct Reporter {
    counters: Arc<Counters>,
    stop: Option<mpsc::Sender<()>>,
    stopped: mpsc::Receiver<()>,
    thread: Option<thread::JoinHandle<()>>,
}
impl Reporter {
    pub fn start(set: &str) -> Self {
        let counters = Arc::new(Counters::default());
        let (stop, stop_wait) = mpsc::channel::<()>();
        let (stopped_signal, stopped) = mpsc::channel::<()>();
        let (shared, set, every) = (counters.clone(), set.to_owned(), interval());
        let start = Instant::now();
        // A thread that cannot start costs the lines, never the run.
        let thread = thread::Builder::new()
            .name("fb-progress".into())
            .spawn(move || {
                let _stopped = stopped_signal;
                while stop_wait.recv_timeout(every) == Err(RecvTimeoutError::Timeout) {
                    let line = shared.line(&set, start.elapsed().as_secs());
                    // Not eprintln: that panics when stderr is gone.
                    let _ = io::stderr().write_all(line.as_bytes());
                }
            })
            .ok();
        Self {
            counters,
            stop: Some(stop),
            stopped,
            thread,
        }
    }
    pub fn counters(&self) -> &Arc<Counters> {
        &self.counters
    }
}
impl Drop for Reporter {
    fn drop(&mut self) {
        drop(self.stop.take());
        if self.stopped.recv_timeout(STOP_WAIT) == Err(RecvTimeoutError::Disconnected)
            && let Some(thread) = self.thread.take()
        {
            let _ = thread.join();
        }
    }
}
