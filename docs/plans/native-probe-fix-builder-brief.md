# Builder brief, 2026-11-07: the native probe fix

**For:** one builder agent, working alone. **Spec:**
[native-probe-fix-design-2026-11-07.md](native-probe-fix-design-2026-11-07.md), revision 4, approved
by the Owner on 2026-11-07. Read that whole design and AGENTS.md before writing code. Where this
brief and the design disagree, stop and report; do not choose.

## Where you work

- **Repository:** `C:\Projects\FileBackup`, branch **`native-probe-fix`**, already checked out. Do
  not use a git worktree.
  - Confirm `git branch --show-current` prints `native-probe-fix` and that `git log -1` is
    `a8e2917` or a descendant of it.
  - Commit only on this branch, in small green steps. Never commit on `Rust-Rewrite` or `main`,
    never merge, never push.
  - End every commit message with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Build and test only through** `pwsh -NoProfile -File scripts/Invoke-Native.ps1 -Action <Test|Lint|Format>`.
  - It keeps Cargo's caches and output on `D:\FileBackupBuild`.
  - `Test` runs `cargo test --features test-hooks`; `Lint` runs clippy with `-D warnings`;
    `Format` runs rustfmt.
  - Never run two test runs at once.
- **Python is 3.8 by default** on this machine. Run Python tooling as `py -3.12 -X utf8 …`.
- **The baseline:** the full Rust suite was run on `a8e2917` before you started. Its result is in
  `D:\FileBackupBuild\tmp\baseline-test.log`. Read it first. If it is not green, report that
  instead of building.

## The exact delta

Each item names where it lands. "Design §n" means the approved design.

1. **Dependency** (`rust/Cargo.toml`, `rust/Cargo.lock`): add the pure-Rust `brotli` crate at an
   exact pinned version (`=x.y.z`). Choose a release at least two weeks old, with only the
   features the encoder needs. Measuring only; nothing stored ever depends on it (design §5).
2. **Window sampler** (`rust/src/format.rs`):
   - Add an optional sampler that `copy_hash` feeds with exactly the chunks it has written and
     hashed (design §6).
   - The plan is computed from the pre-copy length:
     - **above 256 KiB and below 2.25 MiB** (9 × 256 KiB): one whole-file sample;
     - **2.25 MiB or more:** seven 256 KiB windows starting at `floor(k × (length − 256 KiB) / 8)`
       for k = 1 … 7.
   - The buffer is fixed at the plan's size. A window may straddle reads or arrive in short reads.
   - The offset arithmetic is checked. A stream that ends early marks the sample incomplete and
     never panics.
   - `hash_file` and every other caller keep today's behaviour, with no sampler.
3. **The decision** (`rust/src/engine.rs`, `should_compress` and `capture`):
   - Replace the 7-Zip probe. Delete its temporary sample, its archive and its `tools::compress`
     call.
   - Compress each window as its own finished Brotli stream at **quality 1, window (lgwin) 22**
     and count the compressed bytes (design §5).
   - Combine with **one constant switch** for mean, trimmed mean and median:
     - the default is **mean** = Σ compressed / Σ raw;
     - trimmed mean drops the highest and lowest window ratio and averages the other five;
     - median is the 4th of 7 sorted.
   - Compress when the combined ratio is **≤ 0.90**.
   - Measure **lazily**: only after the dedup lookup misses (design §6).
   - Floors, modes and the exempt list behave exactly as today (SR-081, SR-096).
   - A sampler or coder failure means type fallback plus the existing warning, and it is counted
     as `fallback`. Copy, write and hash failures keep today's meaning.
4. **Counters** (`Report` in `rust/src/engine.rs`): add one `probe` object (design §7 item 1).
   - **Fields:** `measured`, `compressed`, `raw`, `whole_file`, `unmeasured`, `fallback`,
     `bytes_compressed_in`, `bytes_compressed_out`.
   - **`unmeasured`:** a new file reached the decision with compression on, but no measurement
     was taken (at or under 256 KiB, or excluded by the probe mode).
   - **`bytes_compressed_in` / `bytes_compressed_out`:** the source length and the archive size of
     each object stored compressed.
   - No existing field changes. When compression is off the object holds all zeros; do not omit it.
5. **Decision log** (`<StorePath>/compress-decisions/`), per design §7 item 2, with these exact rules:
   - **Creation:** the file is created lazily, at the first measured decision of a run. The store
     is then initialized and the run holds the store lock.
   - **Name:** `YYYY_MM_DD_HH_MM_SS.log`, from the run's start time in UTC, created exclusively
     (`create_new`). On a collision use `_1`, `_2` and so on.
   - **Folder:** must be an ordinary directory (`platform::ordinary_dir`). Otherwise skip logging
     with one warning.
   - **Lines:** one per measured or fallback decision, tab-separated, in this order:
     - the RFC 3339 UTC time;
     - the relative path;
     - the length;
     - `compress` or `raw`;
     - the reason: `mean`, `trimmed` or `median` as configured, `whole-file` or `fallback`;
     - the combined ratio to 4 decimals, or `-`;
     - the window ratios, comma-separated to 4 decimals, or `-`.
   - **Flushing:** flushed after each line.
   - **Retention: 30.** Right after creating a run's file, delete the oldest ordinary files whose
     names match `^\d{4}_\d{2}_\d{2}_\d{2}_\d{2}_\d{2}(_\d+)?\.log$` beyond the newest 30. Never
     touch anything else in the folder.
   - **Failures:** any logging or rotation failure is at most one code-0 warning per run, and
     never fails a capture or the run.
   - **Admission:** check that `store.rs` admission and `cleanup()` leave the folder alone, and add
     a test that a second run on a store holding the folder succeeds.
6. **.NET reference table** (new `scripts/gen_brotli_reference.ps1` plus a checked-in table under
   `rust/tests/fixtures/`):
   - A deterministic generator, defined identically in the pwsh script (C# via `Add-Type` is
     fine) and in the Rust test, builds about 12 buffers of 256 KiB:
     - all zeros;
     - pure pseudo-random;
     - repetitive text;
     - WP17's `longrange` shape: a 64 KiB pseudo-random block repeated four times;
     - at least five mixtures whose .NET ratio lands between 0.85 and 0.95.
   - The script records .NET `BrotliEncoder.TryCompress(…, quality 1, window 22)` sizes.
   - The Rust test asserts that its ratio is within 0.005 of each.
   - The table records how it was generated, including the generator constants.
7. **Tests** (`rust/tests/`, plus in-module unit tests). Every case in design §8.2:
   - **The shaped fixtures, 16-64 MiB each**, built in a temp directory at test time:
     - disc image → raw;
     - remux → raw;
     - `1, 1, 0.27` → raw;
     - phone video → raw;
     - screen recording → compress;
     - sparse (random to 42%, then zeros) → compress;
     - `mixed-third` → compress under the mean;
     - longrange → compress;
     - text → compress;
     - random → raw.
   - **Each shape test** asserts the manifest's `Compressed` value, the decision-log line and the
     counters.
   - **Combinations:** a unit test shows all three combinations' verdicts on the shapes.
   - **Sizes:** exactly 256 KiB is unmeasured; just above 256 KiB, just under 2.25 MiB and exactly
     2.25 MiB measure as planned.
   - **The stream:** straddling reads, short reads, a file that grows or shrinks during the copy
     (windows discarded, no panic, buffer bounded), and a dedup hit (no measurement, no line, no
     counter).
   - **Modes:** all three probe modes; compression off (no measurement at all, all-zero counters).
   - **Forced failures:** a forced sampler failure and a forced coder failure through the existing
     `test-hooks` feature (see the `#[cfg(feature = "test-hooks")]` pattern in
     `rust/src/platform.rs`): type fallback, a warning, and the capture unaffected.
   - **The log:** retention keeps exactly 30 and spares a non-matching file, and an unwritable log
     folder produces a warning and a successful run.
   - Keep `backup::compression_probe_policy_and_disabled_new_compression_reuse` passing, adapting
     it only where it relied on the 7-Zip probe.
8. **Requirements and traceability** (TOML registries; never edit between `GENERATED` markers):
   - **`docs/requirements/low-level-requirements.toml`, LLR-162 `detail`:** state the interior
     offsets at eighths, the 2.25 MiB whole-file cutoff, Brotli quality 1 window 22 measured per
     window, the combination switch (mean by default, Σ compressed / Σ raw), lazy measurement
     after a dedup miss, and the decision log and counters. Keep its status `Drafted`.
   - **`docs/test/test-cases.toml`:** add **TC-303** for these tests, verifying LLR-162 and SR-081,
     with status `Drafted`. Fill `notes` with the binding (test file and test names), as the
     neighbouring rows do. Link it from LLR-162's `test_refs`.
   - **The binding:** update `docs/plans/native-design-2026-11-05/implementation-map.md` for
     LLR-162.
   - **Check:** `py -3.12 -X utf8 scripts/trace.py --strict` must stay at `orphans=0 integrity=0`
     with no new form findings (the baseline is 18).
9. **Documentation** (`docs/native-usage.md`): one short section on the decision log (where it is,
   its line format, its retention) and the `probe` counters.

## The exclusions — do not touch or decide

- **Not in this change:**
  - `rust/src/tools.rs` compression, verification and deadline code: the 7-Zip deadline is a
    separate change;
  - `rust/src/progress.rs`: the progress freeze is a separate change;
  - the exempt extension list;
  - the full copy into `Incoming`;
  - sparse-file handling.
- **Never touch:**
  - `recovery/`, `bash/`, `Reconstruct.ps1`, `Modules/`, `FileBackup.ps1`, the SR registry
    (`system-requirements.toml`) or AGENTS.md generated blocks;
  - any remote host.
- **Do not change** the default combination, the threshold, the window count or the cutoffs. If
  one looks wrong, report it.
- **No restore change:** a change that alters stored bytes, a manifest column or what a restore
  needs is outside scope. Stop and report.

## The stopping condition

- **Done means all of these hold:**
  - every item above is committed on `native-probe-fix`;
  - `Invoke-Native.ps1 -Action Test`, `-Action Lint` and `-Action Format` each pass on the final
    commit;
  - the trace check holds;
  - `git status` is clean.
- **Stop early and report when:**
  - two consecutive attempts at the same failure have not fixed it; or
  - the work needs anything listed under the exclusions.

## No further delegation

Do the work yourself. Do not start subagents or other sessions.

## Completion is the artifact

The commits on `native-probe-fix` are the result. A report of work that is not committed there is
not done. Paste real command output for every pass you claim, as the closing lines of each
`Invoke-Native.ps1` run and of the trace check; never report a pass you did not run.

## Return, in this order, compactly

1. What was done: the commits, as hash and subject.
2. Where it is: files changed per commit.
3. What was checked and found clean, with the pasted closing output of Test, Lint, Format and the
   trace check.
4. Findings: anything surprising in the code, each with `file:line`.
5. What was not done, and why.
6. Open questions for the caller.
