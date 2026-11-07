# Builder brief, 2026-11-07: the 7-Zip deadline and progress fixes

**For:** one builder agent, working alone. **Spec:**
[native-restart-fixes-design-2026-11-07.md](native-restart-fixes-design-2026-11-07.md), revision 2,
reviewed. Read it whole, with AGENTS.md and LLR-191 / TC-302 in the registries. Where this brief and
the design disagree, stop and report.

## Where you work

- **Repository:** `C:\Projects\FileBackup`, branch **`native-restart-fixes`**, already checked out,
  cut from `native-probe-fix` at `1a9031a`. Confirm `git branch --show-current` before any edit. No
  worktree.
  - Commit only on this branch, in small green steps. Never commit elsewhere, never merge, never
    push.
  - End every commit message with your own `Co-Authored-By:` trailer.
- **Build and test only through** `pwsh -NoProfile -File scripts/Invoke-Native.ps1 -Action <Test|Lint|Format>`.
  Never run two test runs at once.
- **Python:** run it as `py -3.12 -X utf8 …`.
- **Baseline:** `native-probe-fix` at `70b7e83` passed 94 tests on Windows, 0 failed, with Lint and
  Format clean. Re-run Test once before your first edit to confirm it here.

## The exact delta (design §1 and §2)

1. **Compression deadline** (`rust/src/tools.rs`).
   - Leave `deadline()` exactly as it is; the listing and the expand keep it.
   - Add `compress_deadline(length) = 300 s + 4 s per MiB`, with saturating arithmetic.
   - Add a **stall bound**: compression is a host stop if the archive's size has not grown for
     **60 minutes**. Use the same poll as item 2. Make the window shorter only under `test-hooks`,
     for example through an environment variable.
   - The host-stop message names which bound tripped.
2. **Compression poll** (`rust/src/tools.rs`).
   - Add `compress_counted(input, archive, counters)` that runs 7-Zip like `compress`, with the
     same arguments and the same flush of the archive.
   - Give `invoke` an optional progress callback, called at most once a second (timed with
     `Instant`). Callers that pass none behave exactly as today.
   - The callback stats the archive. `NotFound` counts as 0, any other error is ignored, and a
     poll never fails a run.
   - It stores the size into the step counter and feeds the stall bound.
   - `capture` uses `compress_counted`. If `compress` then has no caller, remove it rather than
     silence the dead-code lint.
3. **Progress phases** (`rust/src/progress.rs`).
   - Append `Compressing` / `"compressing"` and `CheckingArchive` / `"checking archive"`, in that
     order, after the existing seven. Update the array length.
   - Add the `step_done` and `step_total` counters, separate from `bytes`, and a method that enters
     a step phase with **publish-first** ordering: totals and a zero done are stored before the
     phase, following `enter_counted`.
   - Add a **drop guard** that restores `Capturing` and clears both step counters when dropped.
   - The exact lines (design §2):

     - `Progress: set '<set>', compressing: <done> of <total> file(s), <X> of a <Y> file written, <s> s`
     - `Progress: set '<set>', checking archive: <done> of <total> file(s), <X> of <Y> expanded, <s> s`

     `<X>` and `<Y>` use `format_bytes`. Neither line may contain a path or file name.
4. **Counting archive check** (`rust/src/tools.rs`). Add a variant of `verify_form_counted` whose
   expanded bytes, and its raw-branch hash bytes, go to `step_done` and never to `bytes`.
   - It keeps the `FILEBACKUP_TEST_READ_HOLD_MS` hook.
   - Deep verify keeps today's counting, unchanged.
5. **Capture** (`rust/src/engine.rs`). Wrap each of these in a step phase and its guard:
   - the compression;
   - the read-back check after compression;
   - the dedup check of an existing object (`tools::verify_form(&object.path, &key)`);
   - the destination check, near `verify_form(&destination, &key)`.

   The step total is the file's length. Behaviour, return values and errors are otherwise unchanged.
6. **Requirements** (TOML; never edit between `GENERATED` markers; do not edit SR rows):
   - **LLR-191 `detail`:**
     - add the two phases, their lines and the step counters;
     - change "with no lock, stat or extra read" to allow one archive stat a second during
       compression, outside the read loop;
     - state the drop-guard restoration.
   - **TC-302:** `parameters` gains `hold=compress` and `hold=check`, and `expected` gains the
     moving step count and the no-path rule for the new lines. Update `notes` with the new tests.
   - **The compression deadline:** add it to an existing LLR that covers tool deadlines, if one
     does. Otherwise report it as an open question; do not mint an LLR.
   - **Check:** `py -3.12 -X utf8 scripts/trace.py --strict` stays at `orphans=0 integrity=0` with
     18 form findings.
7. **Tests** (design §1 and §2):
   - unit tests that pin `compress_deadline` at 1 MiB, 1 GiB and 21,000,000,000 bytes, and that
     `deadline` is unchanged;
   - the stall bound, through a scripted archive-size source under `test-hooks`: a source that
     stops growing trips a host stop that names the stall, and a growing one does not;
   - the `checking archive` phase, held through the read-hold hook: its count rises between lines;
   - the `compressing` phase, through the scripted size source: its count rises between lines;
   - no line contains a path, `archive-` or `content.7z`;
   - "bytes read" still equals the fixture's source bytes;
   - the phase returns to `capturing`, with cleared step counters, after success and after a forced
     failure;
   - all existing tests stay green.
8. **Docs** (`docs/native-usage.md`): the two new progress lines, and the compression deadline and
   stall bound.

## Exclusions

- **Not in this change:** the probe decision code from the previous change, beyond what item 5's
  wrapping needs; the decision log; the exempt list; the copy into `Incoming`.
- **Never touch:** `recovery/`, `bash/`, `Reconstruct.ps1`, `Modules/`, `FileBackup.ps1`, the SR
  registry, AGENTS.md's generated blocks, or any remote host.
- **No restore change:** nothing that changes stored bytes, a manifest column, the report's JSON
  fields, `backup.log` or what a restore needs. If that becomes necessary, stop and report.
- **Constants:** do not change the 60-minute stall window, the 4 s/MiB ceiling or the 60 s progress
  interval. Report instead.

## Stopping condition

- **Done means all of these hold:**
  - every item is committed;
  - Test, Lint and Format pass on the final commit;
  - the trace check holds;
  - the tree is clean.
- **Stop early and report** after two failed attempts at the same failure, or if the work needs an
  excluded change.

## No further delegation; completion is the artifact

Do the work yourself, with no subagents. The commits on `native-restart-fixes` are the result. Paste
real closing output for every pass you claim.

## Return, in this order, compactly

1. What was done: the commits.
2. Where it is: files per commit.
3. What was checked clean, with pasted output.
4. Findings, with `file:line`.
5. What was not done, and why.
6. Open questions.
