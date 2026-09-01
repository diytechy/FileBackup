# WP16 — A healthy long run must be distinguishable from a dead one

Plan owner: driver. Raised by the Owner 2026-08-31 from
[defect-review-2026-08-31-run-observability.md](../defect-review-2026-08-31-run-observability.md),
**as corrected by that document's §8 cross-review** — the §8 rulings are binding and
override §5 wherever they conflict — and shaped by that same document's §9 live-run addendum from the
Owner's working operator channels on the production hub.

**Scope, as ruled by the Owner:** the review's **B** (time-based progress heartbeat),
**A** (phase banners), **C** (`ChangePath/RUN.status.json`), the **O-3 verbosity
contract**, and **E** (expectations text, including the two-pass first-run read
behaviour). Option **D** (percentage / ETA) is out of scope and deferred (§7) —
§5 D concedes its denominator is unknown during exactly the phase that is silent
longest. O-4 is **not** in scope: §8 C-3 resolved it as working-as-designed and its
one surviving README line shipped as WP14 Part D **N-3**.

**Status: PROPOSED — awaiting Owner approval; no code may be written under it.**
Nothing in this plan is implemented, and no registry row is added, until the Owner
approves. The active gate is **G3**. The decision dial is **HIGH**.

**Revision 2:** this draft folds the plan-stage cross-review of 2026-08-31 (two
independent fresh-context reviewers; 4 P0, 16 P1, 12 P2 raised, composited into 28
dispositions). Every disposition is recorded in **§9**. Six open questions (**Q1–Q6**)
remain for the Owner; everything else is decided.

**This package does not touch the data-integrity surface**, with one qualification the
review forced into the open: §2.3's restorer-fallback finding (**Q6**) is the single
place where a WP16 artifact can be *seen* by restore code, and the Owner must choose its
disposition. Apart from that, WP16 writes one telemetry file outside `Temp`, adds log
lines, and adds a level filter in Engine. It changes no hashing, no dedup, no
atomic-write path, no restore decision, and nothing in the restore kit. §8 sizes the
independent review to that fact honestly, rather than copying WP14's dual round out of
habit — under a constraint (§2.1) that keeps it true.

---

## 0. The one-paragraph version

On the first whole-library production pass — 2.1 TB, every file hashed — the engine
said three lines and then nothing for hours, and the review's §1 measurement proved
that **no external side channel moves either**: the state folder does not grow while
the source is hashed, and the store stays at zero until the copy phase begins. So a
healthy multi-hour run and a run wedged on a stale lock look identical from outside,
which is a large part of why the WP14 wedge went ~18 hours unnoticed. WP16 makes the
run **say what it is doing**: a delimited `INFO` banner at every phase boundary with
an elapsed time on exit, and — during the long silent phases — a **time-based**
progress line carrying the current relative path plus running file and byte counts,
written by a **compiled** timer callback because the pipeline that would carry a
PowerShell scriptblock is exactly what a 100 GB hash is blocking. The same callback
rewrites `ChangePath/RUN.status.json`, a **telemetry-only** artifact outside `Temp`,
correlated to the lock by `RunId`, that a wrapper can poll without scraping logs. The
live-progress channel is therefore the **files** — `ChangePath/backup.log` and
`RUN.status.json` — not the container's stdout, because a compiled callback has no
runspace and cannot write to the host (§2.6). And because none of that detail is
reachable today at any setting, the log finally gets a **level contract**: a threshold,
a documented meaning per level, and a stated disposition for the per-physical-write
`DEBUG` line that option B makes redundant for liveness. Nothing here is authoritative
about anything: a stale `RUN.status.json` is inert, and every safety mechanism in the
product ignores it.

---

## 1. What must remain true

The first four rows are inherited constraints, not new invention: **I-1 and I-2 are
the WP14 §7 deferral row's Owner ruling verbatim in intent**, with both plan-stage
reviewers concurring, and I-3/I-4 are AGENTS.md §3 and the coordinator's I-5-style
constraint.

| # | Invariant | How this plan holds it |
|---|---|---|
| **I-1** | **The telemetry artifact never rides inside `Temp`.** A file rewritten every few seconds is semantically incompatible with `RUN.inprogress`'s write-once safety argument (obs review §8, *Why not merged*), and **inside `Temp` it would classify as `HoldsContent` under SR-017's guard and block the very reclaim WP14 shipped.** | The artifact is `ChangePath/RUN.status.json` — a sibling of the already-present `ChangePath/backup.log`, one level *above* `Temp`. Its scratch file (§2.3) is written in the same directory, never in `Temp`. TC-213 asserts that **neither the status file nor its scratch ever appears beneath `Temp`** — it does **not** claim `Temp` is otherwise empty, because ordinary staging content (the prior manifest and sidecar, evicted and superseded data, the restore kit) is exactly what `Temp` is for. |
| **I-2** | **The artifact is telemetry only, and no safety mechanism reads it.** Reclaim, the §2.5 fences, prune, snapshot finalize, the pool scans and the capacity guard neither read it nor are affected by it, and **neither restorer's snapshot-selection or candidate-election logic knows it exists**. A stale file left by a killed run is **inert**, and the next run that successfully acquires the staging lock simply overwrites it. | No reclaim/fence/prune/finalize/pool-scan function gains a reference to it — asserted by a **region-scoped** inspection over the named functions (TC-217) as well as behaviourally (TC-214, TC-215). The one place a WP16 file can be *enumerated* by restore code is the T2 error fallback (§2.3, **Q6**); TC-215 forces that path either way. Correlation to the lock is one-way: the status file *carries* the lock's `RunId` so a human or wrapper can join the two; the lock never carries anything of the status file's. |
| **I-3** | **`Common` never depends on `Engine`, and `Common.psm1` stays byte-identical** (AGENTS.md §3). | `New-Logger` is not edited and remains in use, unchanged, by `FileBackup.ps1`'s global orchestrator log and by `Remove-BackupSnapshot`'s own logger. The **set** log is built by Engine from step 2 onward on top of a compiled sink (§2.2/§2.4): Engine owns that sink's per-run truncation, line format, host echo and level threshold. That is a re-implementation of `New-Logger`'s behaviour inside Engine, not a wrapper around it, and the plan says so rather than pretending otherwise — but it is **entirely Engine-side**. Common is bundled into every restore kit, so any behavioural change there would force both `KitRevision` markers to bump; there is none. |
| **I-4** | **Nothing acquires a new exit code.** | IF-001 is a cross-project contract and HomeHub owns alarm policy. WP16 emits facts; it does not renumber exits. IF-001 needs no revision for `-LogLevel`, which passes through its existing `-arguments` channel (§6 Q2). **The restore kit does not change — subject to Q6**: if the Owner takes Q6's option (a), the two restorers' skip lists gain one name and both `KitRevision` markers bump from 10 to 11 in that same commit, which is the only way this plan can affect the kit. |
| **I-5** | **A healthy run's *data* path is not slowed or made failure-prone by telemetry.** The hot loop must not become logger-bound (obs review §5 B, *Against*), and a telemetry write that fails must never fail the run. | Progress state is updated by **volatile field writes** in the hot loop — no I/O, no formatting, no allocation per file; all emission happens on the timer thread. Every telemetry write is wrapped: failures increment an error counter, are reported once at stop, and are **never** propagated (§2.2). A failed status **replace** is likewise counted and never fatal (§2.3). |
| **I-6** | **WP16 claims no WP14-style safety property.** Nothing in this plan's acceptance says the status file proves liveness, ownership, or completion. | `RUN.inprogress`'s mtime remains the *only* authoritative liveness signal (obs review §8: *"Consumers read `RUN.inprogress` mtime for authoritative liveness and the status file for phase/counters"*). SR-078's acceptance text states the non-claim explicitly, and §2.6 lists what an operator must **not** conclude from the file — including that telemetry stops updating at step 12.9, well before the run ends. |

---

## 2. Design

### 2.1 Phase banners (option A)

**The phase list is derived from the code, not from the review's prose.**
`Invoke-BackupSet` (`Modules/FileBackup.Engine.psm1:5724`) carries **twenty-four**
numbered comment-steps, not sixteen: `1, 1.5, 2, 3, 4, 5, 5.1, 5.2, 5.5, 6, 7, 8, 9,
9.4, 10, 11, 11.5, 12, 12.5, 12.9, 13, 14, 15, 16`. The fractional steps are not
trivia: 5.1 is the portable-name guard (SR-055, can fail the set), 5.2 the
unreadable-directory guard (SR-057), 9.4 the capacity preflight (SR-052), 11.5
`Save-SupersededData` (SR-059, pool-mutating), 12.9 the marker release (SR-075).

**Banners exist only where a sink exists.** The set log is created at step 2
(`Engine.psm1:5781`). Steps **1** (path resolve, `:5744`) and **1.5** (the witness
gate, `:5762`, which *can fail the set*) run before any sink and keep today's
behaviour: they surface through `Write-Warning` / `Write-Error` and the global
orchestrator log, exactly as they do now. Banners therefore cover **step 3 onward**.

**Step 5.5 gets no banner**: it declares the shared capacity-refusal scriptblock and
`$sameVolume` and performs no work. It folds into step 5's span for reporting
purposes.

**The twenty bannered phases**, with the code's own step label:

| label | phase | label | phase |
|---|---|---|---|
| `3` | Guard staging folder, take lock | `11` | Evict removed files |
| `4` | Hash-recalc decision | `11.5` | Preserve superseded bytes |
| `5` | Update source manifest | `12` | Save backup manifest |
| `5.1` | Portable-name guard | `12.5` | Directory sidecar |
| `5.2` | Unreadable-directory guard | `12.9` | Release owner marker |
| `6` | Sanitize backup manifest | `13` | Finalize dated snapshot |
| `7` | Pre-backup snapshot into staging | `14` | Cross-snapshot de-duplication |
| `8` | Diff | `15` | Record state |
| `9` | Working backup map | `16` | Browse view |
| `9.4` | Capacity preflight | | |

Each is a pair of `INFO` lines through a single helper, so the format cannot drift
step to step:

```
2026-08-31 09:25:29.364 [INFO] ===== [5] Update source manifest — start =====
2026-08-31 11:47:03.118 [INFO] ===== [5] Update source manifest — done in 02:21:33.754 (files=418113, bytes=2.10 TiB) =====
```

- **Bounded output**: **at most 40 banner lines** per run regardless of set size — two
  per executed or failed phase, one per skipped phase. "At most", not "exactly": a
  skipped phase emits a single line, and a run that refuses at step 3 emits two lines
  in total. The bound is what makes A safe to leave on unconditionally at the default
  level; it is not a claim that all twenty phases always run.
- **The `done` line carries the phase's elapsed time**, which is the whole point:
  it builds the per-phase duration baseline that §4 of the review says does not exist
  anywhere, and which option E (§2.5) needs numbers for.
- **Three outcome forms**, and the banner sequence is a complete account of *the
  phases that ran under a sink* — no more than that:
  - `done in <elapsed> (<counters>)` — the phase completed;
  - `skipped — <reason>` (one line, no `start`) — the phase did not run;
  - `failed after <elapsed> — <reason>` — the phase exited by a throw.
  The old draft's unqualified "complete account of the run" claim is **withdrawn**:
  steps 1, 1.5 and 2 are structurally outside it.
- **Emission form is constrained in the fenced and pool-mutating phases.** For steps
  **7, 11, 11.5, 12, 12.5 and 12.9**, the `done`/`failed` banner is emitted from the
  **existing** control flow — after the existing final statement, or inside the
  existing `catch`. **No new `try`/`finally` nesting may be introduced in those
  phases.** They sit behind `Assert-StagingLockOwned` fences whose placement was
  rewritten days ago (WP14 §11 R-1/R-2), inside a function whose `catch` blocks call
  `Remove-OwnStagingFolder`; wrapping them in new frames is a control-flow change on
  the WP14 surface, which is precisely what "does not touch the data-integrity
  surface" — and the single-reviewer sizing in §8 that rests on it — must keep true.
  Phases outside that set may use a `finally`-based `done` line. **This constraint is
  the stated justification for §8's sizing**, and §8's escalation clause stands: a
  reviewer who finds WP14-surface impact escalates to the dual round.
- **The obs review §9's ruling honoured:** the disks already make the phase externally inferable from
  the read/write ratio, so banners at phase boundaries "make the log agree with what
  the disks already show" — which is why boundaries, and not per-item output, are the
  right place for A even after B lands.

### 2.2 The progress heartbeat (option B)

**Time-based, never per-N-items.** §5 B is explicit: item-based emission leaves a
stall on one huge file silent, and the production evidence is a single `.z7` archive
occupying minutes of a 69 MB/s read. Cadence: **one line every 30 s**, and only while
a phase that has registered progress state is running.

```
2026-08-31 10:35:14.882 [INFO] [5] hashing: files=214771 bytes=1.42 TiB (52.7 MiB/s avg) current='NonDocs/MC Server Backups/MC_SERV_BACKUP_20250914.z7'
```

The line carries the **current relative path** plus running file and byte counts, per
the obs review §9's design consequence: the `/proc/<pid>/fd` trick worked because *the engine already
holds the current path in hand and never emits it*. Turning an external `/proc` hack
into a supported signal is the single highest-value line in this package.

**`CurrentPath` is a current-item signal, not a position indicator.** The old draft
claimed the walk is ordered and therefore the path is a position. It is not:
`Update-SourceManifest` enumerates with `Get-ChildItem -Recurse -File -Force`
(`Engine.psm1:496-517`) and processes that output directly; the only sort in the
function happens *after* hashing and is by path length. So the plan claims **liveness
and identity of the item in hand**, nothing about progress through an ordering, and
**WP16 adds no sorting** — sorting the walk would be a change to the hot data path
well outside this package.

Instrumented phases: **step 5** (`Update-SourceManifest` — the core finding, fully
verified) and **step 10** (the copy loop). **Steps 13 and 14 register nothing** — the
binding option B names steps 5 and 10, and the old draft's "they get it for free" was
scope creep that also contradicted LLR-084. Their banners remain, and they are the
phases the telemetry timer no longer covers at all (see the lifetime rule below); §7
records revisiting that as deferred.

**The writer must be compiled .NET, for the WP14 reason, and for one more.** A
PowerShell scriptblock on `Timer.Elapsed` has no runspace on the threadpool thread,
and `Register-ObjectEvent` queues the handler to the pipeline — the very pipeline a
multi-hour hash is blocking. WP14 §2.2 established this and one reviewer reproduced
the non-firing callback under PowerShell 7.6/.NET 10; LLR-073 records that the bare
background-`Thread` alternative terminates the whole process. The consequences
specific to WP16: **the callback cannot call `& $log`**, and **it cannot
`Write-Host`** — both are PowerShell constructs needing a runspace. The compiled
writer formats and appends its own line, and writes `RUN.status.json` itself.

**One compiled file sink, created at step 2** (Codex R-7's shape, adopted). The
background thread and the pipeline would otherwise both append to
`ChangePath/backup.log` — two writers, one file, no lock. The design:

1. **Step 2** constructs the `FileBackup.RunObserver` instance with its log path and
   level threshold. It performs the **per-run truncation** (today `New-Logger`'s
   `New-Item -ItemType File -Force`, `Common.psm1:201`) and owns the line format
   `yyyy-MM-dd HH:mm:ss.fff [LEVEL] msg` from that point on. **Its timer is inactive
   and it writes no status file yet**, because there is no `RunId` before the lock.
2. Engine's `New-SetLogger` returns a PowerShell scriptblock closing over the
   instance. That scriptblock applies the **level threshold** (short-circuiting before
   any formatting or I/O), calls the sink for the file append, and does its own
   `Write-Host` so the **host-stream behaviour of `New-Logger` is preserved exactly**
   (`Common.psm1:206-207`). Everything `Invoke-BackupSet` logs from step 2 onward —
   including step 3's staging-guard refusal and every `[SR-075/*]` token — goes
   through it.
3. **Step 3, after the lock is taken**, binds `RunId` from the staging lock, writes
   the first `RUN.status.json`, and **arms the timer**. Telemetry begins here; the
   file sink was already live.
4. **A sink failure cannot report itself through the sink.** `ErrorCount`/`LastError`
   are surfaced on an **independent host path** (`Write-Warning` from the PowerShell
   side at stop, plus the global orchestrator log), never only into the file that just
   failed.

This makes the achievable property precise: **from step 2 onward there is exactly one
serialized writer of the set log**, so no line can be torn or interleaved mid-line.
It is *not* "one writer for the whole run" — steps 1 and 1.5 precede any sink — and
TC-211 asserts the achievable property, not the old one.

**Observer lifetime — pinned against the landed WP14 lifecycle.** The old draft said
"stop in the same `finally` that stops the staging heartbeat"; the landed code does
that at **step 12.9** (`Engine.psm1:6058-6072`), whose order is *fence → stop
heartbeat → delete marker leaf → finalize*, and step 13 then renames `Temp` wholesale.
So:

- **Telemetry stops in the same step-12.9 block, immediately after
  `Stop-StagingHeartbeat` and before `[System.IO.File]::Delete($stagingLock.MarkerPath)`.**
  That stop is idempotent, never throws, **drains** in-flight callbacks, writes a
  terminal status record from the per-set outcome flag as it then stands, and removes
  the scratch file. It adds no new `try`/`finally` (§2.1's constraint).
- **The file sink lives on** through steps 13–16 and is closed in the outer `finally`.
  Banners for 13–16 are written by it; no status update accompanies them.
- **A final status write happens in the outer `finally`** with the settled per-set
  outcome, covering abort paths that never reach 12.9. **Last write wins** — there is
  no reconciliation, no ordering proof and no consistency obligation between the two,
  because the file is telemetry (I-6).
- **Consequence, stated rather than discovered:** `RUN.status.json`'s `RunId` can be
  joined to `Temp/RUN.inprogress` only in the window **lock take → step 12.9**. After
  12.9 the marker is gone by design. TC-208 and TC-213 name that window.

Progress state lives in the compiled object as `volatile`/`Interlocked` fields the hot
loop assigns (`Files`, `Bytes`, `CurrentPath`, `PhaseStep`, `PhaseName`) — **no I/O,
no string formatting and no allocation per item on the data path** (I-5). Emission,
formatting and rate arithmetic happen only on the timer thread.

**Sibling class, not a generalized `StagingHeartbeat`.** The obs review §8 says WP16
"can share WP14 Part A's compiled `StagingHeartbeat` class"; the WP14 §7 row repeats
it. Read as permission rather than as a mandate, and this plan proposes a **sibling
compiled class `FileBackup.RunObserver`** instead, for one reason: every branch of
`StagingHeartbeat.Beat()` is safety-critical and was hardened finding-by-finding in
WP14 §11 — the identity-guarded touch through a single `SafeFileHandle` (R-7), the
synchronous first-beat proof (R-5), the drain barrier. Parameterizing it with a
telemetry callback would place telemetry failure modes inside the lock-liveness code
path and reopen a just-closed review, for the sake of ~40 lines of timer scaffolding —
and `RunObserver` additionally has to be a *log sink*, which `StagingHeartbeat` is not
and must not become. **What is reused is the *pattern*, deliberately and
line-for-line**: `Add-Type` compiled once per session with an idempotent guard, a
rooted handle held for the observer's whole lifetime (an unrooted timer is collectable
and stops silently), `AutoReset` timer, a `volatile` cancellation flag, an in-flight
counter enlisted *before* the flag is read, `Stop()` that is idempotent, never throws,
and **drains**, and `ErrorCount`/`LastError` fields because `System.Timers.Timer`
swallows handler exceptions. This is recorded as an Owner-visible deviation in §6 Q1;
it is low-risk either way.

### 2.3 `ChangePath/RUN.status.json` (option C)

```json
{
  "SchemaVersion": 1,
  "Kind": "telemetry",
  "RunId": "b3f1…-guid",
  "SetName": "library",
  "Host": "homehub",
  "StartedUtc": "2026-08-31T09:25:29Z",
  "UpdatedUtc": "2026-08-31T10:35:14Z",
  "PhaseStep": "5",
  "PhaseOrdinal": 3,
  "PhaseCount": 20,
  "Phase": "Update source manifest",
  "PhaseStartedUtc": "2026-08-31T09:25:29Z",
  "Files": 214771,
  "Bytes": 1561803849728,
  "CurrentPath": "NonDocs/MC Server Backups/MC_SERV_BACKUP_20250914.z7",
  "Outcome": "running"
}
```

`PhaseStep` is the code's own label (`"5.1"`, `"12.9"`); `PhaseOrdinal`/`PhaseCount`
position it in §2.1's twenty-phase bannered sequence. Both are advisory.

Binding constraints, each traceable to a ruling:

- **Outside `Temp`** (I-1; WP14 §7 row; obs review §8). It sits beside `backup.log`,
  which is precedent: a file at the `ChangePath` root is already normal.
- **Correlated by `RunId`** — the same GUID the run published in `RUN.inprogress`, so
  a wrapper can join telemetry to the authoritative lock, in the window §2.2 names.
  One-way, per I-2.
- **Rewritten freely** on the observer's cadence and at every phase boundary. There is
  no write-once claim, no torn-read proof obligation, and no reader that must not be
  fooled — because no safety decision depends on it.
- **Best-effort same-directory replace, explicitly *not* an atomicity guarantee.** The
  protocol is: write `RUN.status.json.tmp` **in `ChangePath`** (same directory, so the
  rename is intra-volume; **never in `Temp`**, which would be I-1's violation), then
  `File.Move(src, dst, overwrite: true)` onto `RUN.status.json`. This is the *opposite*
  operation from WP14 §11 R-4 — R-4 needed **exclusive create** for the lock marker,
  and non-overwriting `File.Move` is check-then-rename on Unix — so R-4's reasoning
  does not transfer, and the choice here is sound. But the old draft's "atomic
  replacement on every supported store, exFAT included" **overclaimed**: WP14 §6 Q1 and
  §11 R-12 leave rename behaviour on the hub's stack unproven pending TC-195, and on
  Windows `MoveFileEx(REPLACE_EXISTING)` fails with a sharing violation while a reader
  holds the target open. The contract is therefore:
  - the replace is atomic **where the platform makes rename atomic**, and the design
    depends on nothing stronger;
  - **a failed replace increments `ErrorCount` and is never fatal** — the previous,
    valid document simply remains;
  - **readers must tolerate a missing, stale or malformed document.** That obligation
    is stated in §2.6, in SR-078's acceptance, and in the README field reference.
  - The scratch file is removed at stop; a leftover scratch file is inert (§2.6's
    reader rules and I-2 cover it), and it is the one WP16 artifact besides the status
    file itself that Q6 and TC-215 must account for.
- **Structural JSON serialization, never string interpolation.** `CurrentPath` on
  Windows contains backslashes, and set names, host names and paths can contain quotes
  and non-ASCII. The compiled class writes through **`System.Text.Json.Utf8JsonWriter`**
  and emits **UTF-8 without BOM**. *Verified on this tree*: a class compiled by
  `Add-Type -ReferencedAssemblies System.Text.Json, System.Memory, System.Runtime`
  under PowerShell 7.6.5 / .NET 10.0.11 serialized the relative path
  `sub\alpha"q".txt` correctly to
  `{"CurrentPath":"sub\\alpha\u0022q\u0022.txt"}` — backslash doubled, quotes
  escaped. `System.Text.Json` has shipped in
  the shared framework since .NET Core 3.0, so the reference is available on every
  runtime this product supports; the plan names it explicitly rather than assuming
  `Add-Type`'s default reference set. TC-208 carries an escaped nested path.
- **`Outcome` has one per-set source of truth.** `Invoke-BackupSet` receives a
  *process-wide* `[ref]$OverallSuccess` (`Engine.psm1:5737`) that a non-throwing copy
  failure sets false (`:5054`) and that a *previous* set may already have set false.
  Deriving `Outcome` from it would let a clean set inherit a sibling's failure;
  deriving it from exceptions alone would call a non-throwing copy failure
  `succeeded`. So: a **local per-set outcome flag**, initialised `running`, set
  `failed` at every non-throwing failure site and every `catch`/early-`return` path,
  set `succeeded` only on the normal completion path — and merged into
  `$OverallSuccess` **separately**, exactly as today. A status test arm covers both
  directions (TC-210's sibling-set arm).
- **A stale file is inert.** A run killed from outside leaves the last-written status
  with `Outcome: "running"` and a frozen `UpdatedUtc`. Nothing detects it, nothing
  refuses on it, nothing cleans it up; **the next run that successfully acquires the
  staging lock overwrites it at step 3 as a matter of course.** The qualifier is not
  decoration: a kill during step 5 leaves `Temp/RUN.inprogress` and staged content, and
  `Initialize-StagingFolder` (`Engine.psm1:4712`) will correctly refuse the successor
  under SR-017 — *before* any observer exists. That refusal is WP14 working, not a
  telemetry defect, and TC-210's arms keep the two apart.
- **Terminal write.** Per §2.2's lifetime rule, at step 12.9 and again in the outer
  `finally`; last write wins. This is a courtesy for post-mortems; it is not a
  completion signal, because the *exit code* is the completion signal (I-4).

**Who can see the file — the corrected claim.** The old draft asserted that *every*
`ChangePath` scanner enumerates with `-Directory` and a `Snapshot_…` pattern, making a
root-level file structurally invisible. That is true of the engine and prune —
change-folder sanitation (`Engine.psm1:1034`), the pool/prune inventory (`:1107`),
`Test-BackupStorageForm` (`:1791`), `Invoke-PruneEntrySweep` — and it is true of both
restorers' **normal** snapshot selection. It is **not universally true**. On the
2026-08-25 Terra T2 error path, when snapshot enumeration reports errors,
`Reconstruct.ps1:1126` adds **`$changeRoot` itself** to `$searchFolders`, and
`bash/reconstruct.sh:1288` does the same. The candidate scan is then
`Get-ChildItem -File -Recurse -Force` (`Reconstruct.ps1:386`) / `find -type f`
(`reconstruct.sh:726`), filtered by a fixed prefix regex —
`^(MANIFEST|RECONSTRUCT|DIRECTORIES|FileBackup\.Common|System\.IO\.Hashing|FileBackupState)`
(`Reconstruct.ps1:366`, `reconstruct.sh:127`) — which cannot match `RUN.status.json`.
A status file rewritten or locked mid-restore could therefore record
`StorageUnreadable` and turn an intact backup's restore into exit 4.

Two facts bound the severity, and both belong in the Owner's hands rather than in a
silent decision here: the fallback is an **error path only** (an unlistable snapshot
tree — already a host problem), and the exposure class **already exists** —
`Temp/RUN.inprogress` is likewise not in that skip regex and is likewise reachable
under the same fallback today. **The fix choice is Q6.** TC-215 gains an arm that
forces the enumeration-error fallback either way, because the happy path cannot
detect this.

### 2.4 The O-3 verbosity contract

O-3 stands exactly as written and was re-confirmed by §8 C-2: `New-Logger` performs
**no level comparison anywhere** — no threshold, no `-Verbose` bridge, no knob — so
raising verbosity is not a configuration change, the detail does not exist. WP16
creates the detail; the contract says who sees it.

| level | meaning | at the default threshold |
|---|---|---|
| `ERROR` | The set has failed, or a file is not in the backup. | emitted |
| `WARN` | Something was recovered from, or a degradation the operator should know about. | emitted |
| `INFO` | Normal progress an operator should see unprompted: phase banners (§2.1), progress heartbeats (§2.2), the existing 15-ish explicit `INFO` sites and the ~32 sites relying on the default (§8 C-2's corrected census). | emitted |
| `DEBUG` | Per-item or per-check detail, proportional to the size of the set. | **suppressed** |
| `TRACE` | Reserved; nothing emits at this level in WP16. | suppressed |

**Default threshold: `INFO`.** Selectable per run by a `-LogLevel` parameter on
`FileBackup.ps1`, threaded to `Invoke-BackupSet`. The threshold is applied in the
Engine set-logger scriptblock (§2.2 step 2), short-circuiting *before* any formatting
or I/O.

**SR-079's scope, stated honestly.** There are exactly **three** `DEBUG` call sites in
the product, all in `Engine.psm1`:

| site | reaches | disposition |
|---|---|---|
| `Invoke-BackupFileGroup` — `Stored object '<DataPath>' for hash=… (group of N).` | the **set log** | suppressed by default; §2.4's trade below |
| `Assert-BackupCapacity` — `Capacity check passed for the <label> volume …` (SR-052, reached from step 9.4) | the **set log** | **also suppressed by default.** Named here so the loss is executed, not discovered; step 9.4's banner (§2.1) carries the phase's occurrence, and the refusal path is `ERROR`, which still emits. |
| `Remove-BackupSnapshot`'s plan line | **prune's own logger**, built outside `Invoke-BackupSet` | **out of scope.** It keeps emitting unconditionally. SR-079's threshold governs the set log only. |

The **global orchestrator log** needs no wrapper: it has zero `DEBUG` sites, so the
contract is satisfied there vacuously and `FileBackup.ps1`'s use of Common's
`New-Logger` is untouched. Extending the threshold to prune's logger is **WP15's
natural home**, and SR-079's acceptance text says so rather than claiming a
product-wide contract it does not enforce.

**The per-object line — cited by name, not by line number.** It lives in
`Invoke-BackupFileGroup` (currently `Modules/FileBackup.Engine.psm1:5062`, moved twice
already; the name is the stable citation). §8 C-1 is the reason it matters: because
there is no level filter today, that line **always emits**, which is why O-1's claim
that step 10 is silent was half-withdrawn — on a first pass nearly every object is a
new physical write, so the copy phase does produce regular output. Introducing a
threshold therefore **takes something away**, and the contract must say so out loud:

- **The line stays at `DEBUG` and is suppressed by default.** Step 10's liveness and
  current item are then carried by the §2.2 heartbeat, which is strictly better: it is
  time-based (so a stall inside one enormous file is visible, which a per-object line
  can never be), bounded in volume, and it names a *relative path* rather than a
  content-addressed pool name. Net first-pass log volume falls by roughly one line per
  stored object.
- **The line is not deleted and not demoted further**, because it is load-bearing
  evidence: it is what makes SR-060's "one copy/compress operation" observable at all.
  Under content addressing a second write lands on the same name with the same bytes,
  so the *result* cannot distinguish one write from two — WP9 review MAJ-2 found the
  intra-run memo could be deleted outright with the whole suite still green.
- **Consequence that must be executed, not discovered:** `tests/Unit/Coverage.Tests.ps1:3320`
  counts `Stored object` lines in the set log to prove exactly that. That test must run
  its store at `-LogLevel DEBUG`; SR-079's acceptance requires the per-physical-write
  evidence to remain obtainable, and TC-212 is the regression that keeps it so.

Deliberately **not** in this contract: a `LogLevel` **config key**. SR-027's config
contract refuses unrecognized keys by name, so adding one is a config-contract change
with its own validation, example-file and version consequences — cost out of
proportion to a knob whose default is right for every scheduled run. Deferred (§7).

### 2.5 Expectations text (option E)

README + `docs/` prose, no code, setting operator expectations. It exists because §5 E
is right about the concrete harm: *on 2026-08-30 not knowing whether to intervene is
what led to a run being stopped.*

1. **A first whole-library pass is long, and silence is not a defect.** Give the
   measured shape: `LastHashRun=` empty ⇒ every file is hashed, and the observed hub
   figures (2.1 TB, ~69 MB/s sustained source read).
2. **The two-pass first-run read behaviour — required by the coordinator's scope, and
   the single most load-bearing sentence in E.** A first pass reads the source
   **roughly twice**: once in step 5, which hashes every file to build the source
   manifest, and again in step 10, which copies (and optionally compresses) from the
   source. Dividing library size by disk throughput therefore **understates a first
   run by about half**, and a run that takes twice a naive estimate is behaving
   correctly. Later runs re-read only what `HashRecalcFreq` schedules plus what
   actually changed.
3. **How to tell alive from stuck** — the banner and heartbeat cadence first, **read
   from `ChangePath/backup.log`, not from the container's console** (§2.6); then
   the obs review §9's channels that genuinely work (`/proc/diskstats` two samples, whose read/write
   *ratio identifies the phase*; the container's open fd on `/source`); and explicitly
   the channels that **do not**, so nobody chases them: `du` on the state folder or
   the store (flat throughout step 5), and `/proc/<pid>/io` on the container's
   top-level PID (reported a 0 MB read delta while the disk moved 1.4 GB).
4. **Where to look:** `ChangePath/backup.log`, plus `ChangePath/RUN.status.json` and
   its field meanings, plus the statement that the status file is telemetry that may
   be **missing, stale or malformed**, and that `RUN.inprogress`'s mtime is the
   authoritative liveness signal. This *extends* WP14 Part D's N-3 pointer; it does not
   restate or replace it.
5. **A duration baseline table**, seeded from the banners' own `done` timings.

**E cannot be finished from this repo alone.** The obs review's §9 records two artefacts
still pending from the hub — a tree-size map and the completed first pass's total
duration — and its §7 lists the same duration as a "useful baseline" item. §6 Q3
carries this as an open question rather than inventing numbers.

### 2.6 What an operator must **not** conclude (the I-6 non-claim)

Stated in the plan, in SR-078's acceptance text, and in the README section §2.5 adds:

- **Progress is a file channel, not a console channel.** Banners and every line the
  pipeline emits still reach the host exactly as today, because they go through the
  PowerShell wrapper's `Write-Host` (§2.2). **The timer-driven progress lines do not**:
  the compiled callback has no runspace and cannot write to a host stream. So during a
  multi-hour step 5, `docker logs` still shows nothing new between banners — the live
  channel is `ChangePath/backup.log` and `ChangePath/RUN.status.json`, both on the bind
  mount. This is a deliberate, stated limitation, not an oversight; the queue-drain
  alternative was considered and rejected (§9 below, R-3).
- **Telemetry stops before the run does.** The last status update is written at step
  12.9; steps 13–16 (snapshot finalize, cross-snapshot dedup, state, browse view)
  advance the **log** but not the status file. A status file that has stopped moving
  while banners continue is a run in its final phases, not a wedge.
- A fresh `UpdatedUtc` **is not proof the run holds the staging lock.** WP14's fences
  can abort a run that lost its lock; the last telemetry write may precede that.
- A stale `UpdatedUtc` **is not proof the run is dead** — a store that rejects the
  telemetry write, a failed replace, or a phase without progress state all stall it
  while the run is perfectly healthy. `RUN.inprogress`'s mtime is the liveness signal.
- **The document may be missing, stale or malformed.** A reader must tolerate all
  three (§2.3); none of them means anything about the run.
- `Outcome: "succeeded"` **is not the run's result.** The exit code is (I-4).
- `Files`/`Bytes` are **progress counters, not an audit**. `MANIFEST.csv` is the index.
- `CurrentPath` is **the item in hand, not a position**. The walk is unordered (§2.2);
  a path "earlier in the alphabet" than the last one means nothing.

---

## 3. Requirements deltas

Registry rows land **before** the code, in their own commit, with
`python scripts/trace.py --strict` green and orphans 0. Ids below are the next free
block as of this drafting: **SR-075, LLR-080 and TC-204 are the current high-water
marks**, and **WP15 holds no reserved rows** (its only trace is the WP14 §7 deferral
row), so WP16 starts immediately after each.

| id | change |
|---|---|
| **SN-037** *(new)* | *"Tell me a long run is alive and roughly where it is, without host-level forensics."* No progress, observability or heartbeat need exists in `stakeholder-needs.md` today — searched by the review's §0 and re-confirmed against the registries by both cross-reviewers. Every SR below hangs off it (SR-076…SR-079 also ref **SN-011**, unattended runs with a clear signal; SR-080 also refs **SN-012**, discoverable docs). |
| **SR-076** *(new)* | **Phase banners and per-phase timings.** A delimited `INFO` banner at the start and end of each of the **twenty bannered phases** (§2.1 — step 3 onward, 5.5 excluded), the end line carrying elapsed time; the three outcome forms `done`/`skipped`/`failed`; **at most 40 banner lines** per run; acceptance states that steps 1, 1.5 and 2 are outside the contract because no set-log sink exists yet. Verification: `Test`. |
| **SR-077** *(new)* | **Long-phase progress heartbeat.** During instrumented phases (steps 5 and 10), a line at a fixed **time** cadence carrying current relative path, file count, byte count and average rate, emitted from a compiled callback that does not depend on the PowerShell pipeline; **the line is written to the set log file only and does not reach the host stream**; `CurrentPath` names the current item and carries no ordering claim; the data path performs no telemetry I/O. Verification: `Test`. Permutations cell below. |
| **SR-078** *(new)* | **Run status telemetry artifact.** `ChangePath/RUN.status.json`, schema as §2.3, outside `Temp`, `RunId`-correlated **in the window lock-take → step 12.9**, rewritten by best-effort same-directory replace whose failure is counted and never fatal, serialized structurally as UTF-8 no BOM, and **telemetry-only**: acceptance states that reclaim, fencing, prune, snapshot finalize, pool scans and capacity accounting neither read it nor change behaviour because of it; that neither restorer's snapshot selection or candidate election references it (with the §2.3 T2-fallback qualification, per Q6); that a stale file is inert and overwritten by the next run that successfully takes the lock; that readers must tolerate missing/stale/malformed content; and — per I-6 — that it proves neither liveness, nor ownership, nor completion. Verification: `Test`. Permutations cell below. |
| **SR-079** *(new)* | **Log verbosity contract.** Levels and their meanings, the default `INFO` threshold, the `-LogLevel` selector, filtering in Engine with `Common.psm1` byte-identical, and the explicit disposition of both set-log `DEBUG` sites: the per-physical-write line and the capacity-check line remain at `DEBUG`, are suppressed by default, and the per-physical-write SR-060 evidence remains obtainable at `-LogLevel DEBUG`. **Scope: the set log.** The global orchestrator log has no `DEBUG` site; `Remove-BackupSnapshot`'s logger is explicitly out of scope. Verification: `Test`. Permutations cell below. |
| **SR-080** *(new)* | **Documented run expectations.** README/docs state the first-pass duration shape, the **two-pass first-run read behaviour**, the working and non-working liveness channels, **that live progress is a file channel and not the console**, where the logs and status file live, and the §2.6 non-claims. Verification: **`Inspection`** (registry precedent: 2 of the 74 SRs verify by Inspection, 2 by Demonstration). |
| **SR-017 / SR-075** | *Untouched.* WP16 adds no condition to the staging guard and no field to `RUN.inprogress`. |
| **SR-060 / TC-119** | *Untouched as requirements*; §2.4 preserves their evidence, and TC-212 is the regression. |
| **LLR-081** *(new)* | The compiled `FileBackup.RunObserver` class: **the serialized file sink** (per-run truncation, line format, level-agnostic append), timer, volatile progress fields, line formatter, `Utf8JsonWriter` status writer, error counters, rooted handle, idempotent draining `Stop()`; and the §2.2 ruling that it is a **sibling of** rather than a generalization of `StagingHeartbeat`, with the reason. |
| **LLR-082** *(new)* | Engine's `New-SetLogger`: applies the level threshold before any formatting or I/O, delegates the file append to the single `RunObserver` sink, performs its own `Write-Host` to preserve `New-Logger`'s host-stream behaviour, and reports sink errors on an independent host path. Records that Engine — not Common — owns the set log's truncation and line format from step 2 onward, and that `Common.psm1` is byte-identical (I-3, no `KitRevision` bump). |
| **LLR-083** *(new)* | Banner emission points in `Invoke-BackupSet` — the twenty-phase table (§2.1), the start/done/skipped/failed forms, and the **no-new-`try`/`finally` constraint in the fenced phases 7, 11, 11.5, 12, 12.5, 12.9**. `CodeSymbol` extended. |
| **LLR-084** *(new)* | Progress registration seams: in `Update-SourceManifest`, and **inside `Invoke-BackupFileGroup` immediately before each candidate copy attempt** (not in the outer step-10 loop — the elected owner is not necessarily the file being read when a twin supplies the bytes). File and byte increments are applied **after one successful physical group write**. Records the prohibition on any I/O, formatting or allocation on that path (I-5) and the absence of any ordering claim. |
| **LLR-085** *(new)* | `RUN.status.json` schema, the scratch-then-replace protocol and its best-effort contract, the scratch file's placement in `ChangePath` and never in `Temp`, the per-set `Outcome` flag, the 12.9 + outer-`finally` terminal writes with last-write-wins, and the enumerated list of mechanisms that must not reference it (I-2). |
| **LLR-017 / LLR-080** | *Untouched.* WP14's classifier, reclaim protocol and heartbeat are not edited. |

**LLR → TC map** (so no LLR orphans under `trace.py`'s rule that an LLR needs at least
one TC, and so §8's commit rows can name their tests):

| LLR | TCs |
|---|---|
| LLR-081 | TC-221 (class unit tests), TC-206, TC-209 |
| LLR-082 | TC-211, TC-212 |
| LLR-083 | TC-205 |
| LLR-084 | TC-207, TC-218 |
| LLR-085 | TC-208, TC-209, TC-210, TC-213, TC-214, TC-215, TC-217 |

**SR → TC map:** SR-076 → TC-205, TC-219 · SR-077 → TC-206, TC-207, TC-218, TC-219,
TC-221 · SR-078 → TC-208, TC-209, TC-210, TC-213, TC-214, TC-215, TC-217, TC-219 ·
SR-079 → TC-211, TC-212, TC-216 · SR-080 → TC-220.

**Permutations cells for `python scripts/gen_cases.py`.** The `SR-###:` label is prose,
**outside** the parseable text — `parse_spec` (`gen_cases.py:56-80`) splits on `;` then
`=`, so a pasted `SR-077: phase=set{…}` yields a dimension literally named
`SR-077: phase`. Each fenced block below is the cell content verbatim.

SR-076:

```
outcome=set{done,skipped,failed}
```

SR-077:

```
phase=set{hash,copy}; duration=set{short,long-single-file}; platform=set{windows,container}
```

SR-078:

```
prior=set{none,stale-running,stale-succeeded,scratch-leftover}; consumer=set{reclaim,prune,restore-ps,restore-bash}
```

SR-079:

```
level=set{ERROR,WARN,INFO,DEBUG}; threshold=set{INFO,DEBUG}
```

**The generated matrix is illustrative, not landed.** SR-078's cell alone expands to 16
rows; these expansions document each requirement's input space for review and are
**not** added on top of the hand-assigned TC-205…TC-221. `sink` was dropped from
SR-077's cell: there is one sink (§2.6).

**No `Common` change ⇒ no `KitRevision` bump. No kit template change ⇒ no restore-kit
consequence at all** (I-3, I-4) — **unless the Owner takes Q6 option (a)**, in which
case both markers bump 10 → 11 in that commit. If review ever forces a helper into
Common, both kit markers bump in that same commit — AGENTS.md makes that non-optional.

---

## 4. Work parts

### Part A — Engine: the compiled observer and file sink (LLR-081)

`FileBackup.RunObserver`, compiled by an idempotent `Initialize-RunObserverType`, plus
`New-RunObserver` / `Start-RunObserverTelemetry` / `Stop-RunObserverTelemetry` /
`Close-RunObserver` wrappers. Each PowerShell function carries comment-based help as
the **first** thing in its body and an `# Implements:` back-link.

- The **serialized file sink**: per-run truncation on construction, the
  `yyyy-MM-dd HH:mm:ss.fff [LEVEL] msg` format, whole-line appends behind one lock.
- Volatile/`Interlocked` progress fields; setters cheap enough for the hot loop.
- Timer callback: format one progress line, append it through the sink lock, write the
  status file via `Utf8JsonWriter` + scratch-then-replace (§2.3), catch everything,
  count errors, propagate nothing.
- `Stop-RunObserverTelemetry` is idempotent, never throws, **drains** in-flight
  callbacks, writes the terminal status record, removes the scratch file, and surfaces
  `ErrorCount`/`LastError` on the independent host path when either is nonzero —
  WP14 §11 R-5's lesson applied without R-5's severity: a telemetry beat that dies must
  be *visible*, not fatal. `Close-RunObserver` releases the sink in the outer `finally`.
- **Deliberately absent**, and the reviewer should check for their absence: no identity
  guard, no confirmation sample, no exclusive create, no first-beat-must-land throw.
  Those are `StagingHeartbeat`'s obligations because it carries a safety claim (I-6).

### Part B — Engine: the verbosity contract (LLR-082, SR-079)

`New-SetLogger` in Engine returns the threshold-applying, host-echoing scriptblock over
the Part A sink, and `Invoke-BackupSet` builds its logger through it at step 2. Thread
`-LogLevel` from `FileBackup.ps1`. `Common.psm1` is not edited — **a diff over it is a
step of this commit's gate** (that is the mechanism; TC-216 asserts the kit markers,
not the file's history). `Coverage.Tests.ps1`'s `Stored object` store runs at
`-LogLevel DEBUG`.

### Part C — Engine: banners and progress seams (LLR-083, LLR-084, SR-076, SR-077)

The twenty-phase table and the banner helper, honouring §2.1's no-new-`try`/`finally`
constraint in the fenced phases; observer telemetry armed immediately after the staging
lock is taken (so `RunId` is available to correlate) and stopped inside the existing
step-12.9 block between `Stop-StagingHeartbeat` and the marker delete; the two progress
seams (`Update-SourceManifest`, and inside `Invoke-BackupFileGroup`).

### Part D — Engine + tests: the status artifact (LLR-085, SR-078)

Schema, `Utf8JsonWriter` writer, scratch placement, per-set `Outcome` flag, terminal
writes; the region-scoped inspection assertion that no named safety function references
the artifact (TC-217); **and, in the same commit that first writes the file**, adding
`RUN.status.json` and `RUN.status.json.tmp` to `Get-ByteInventory`'s infrastructure list
(`tests/Unit/StagingLock.Tests.ps1:217`) and to any other whole-tree comparison helper.
Without that, TC-204 hashes the first run's terminal status into its protected inventory
and then reports destroyed stored content when the second run overwrites it. **This is a
named deliverable of the commit, not a follow-up.**

### Part E — Docs (SR-080)

README expectations section per §2.5 (including the two-pass read paragraph, the
file-channel statement and the §2.6 non-claims), the `-LogLevel` documentation, and the
`RUN.status.json` field reference. `AGENTS.md` gains one line naming the artifact in its
on-disk inventory, so the next reader does not have to rediscover that a file at the
`ChangePath` root is deliberate. **No `docs/status.md` decision is recorded until the
Owner approves.**

---

## 5. Test cases (TC-205 onward)

Ids are assigned now, so §4/§8 cannot drift from a counting convention — WP14 §10's
last P2 was exactly that drift. TC-221 is the new high-water mark.

| id | Case | Level / Tier | Why it is not optional |
|---|---|---|---|
| TC-205 | A run emits start/done banner pairs, in code order, for the phases that execute, each `done` carrying a plausible elapsed time; **three arms exercise `outcome=done|skipped|failed`** (a skipped phase — e.g. `BrowseView=off` skipping step 16 — emits one `skipped` line and no `start`; a forced failure emits `failed after <elapsed>`); total banner lines are **≤ 40**; **no banner is emitted for steps 1, 1.5 or 2** | Integration / Full | SR-076's whole claim, with the outcome dimension the old "all sixteen pairs" wording made unsatisfiable. |
| TC-206 | Progress lines appear at the **time** cadence during a phase blocked on **one large file**, observed while the pipeline is blocked; a callback made to throw neither kills the run nor stops the beat unnoticed (`ErrorCount` observable) | Integration / Full | The §2.2 certainty. An inline or per-item beat passes a naive test and fails exactly here; `Timers.Timer` swallows handler exceptions. **Negative control required.** |
| TC-207 | The emitted line carries the **current relative path** — a path that exists in the source tree and changes over successive lines — and monotonically non-decreasing file/byte counts | Integration / Full | SR-077's liveness-and-identity claim. **No ordering assertion**: the walk is unordered (§2.2), and the old monotonic-path assertion would have been flaky by construction. |
| TC-208 | `RUN.status.json` appears at the `ChangePath` root, parses as UTF-8-no-BOM JSON, validates against the §2.3 schema, its `RunId` **equals** the `RunId` in `Temp/RUN.inprogress` **while sampled between lock acquisition and step 12.9**, and `UpdatedUtc` advances. One arm uses a source file whose relative path requires JSON escaping (backslash-separated nested path containing a quote and a non-ASCII character) and asserts the document still parses and round-trips that path | Integration / Smoke | SR-078's core, the correlation the wrapper depends on, and the escaping the serializer exists for. |
| TC-209 | Over many rewrites while a reader polls continuously: **forward progress** — `UpdatedUtc` advances at least N times and the observer's successful-replace count is ≥ N — **and** every successful read yields a complete, valid document (no torn read) | Integration / Full | §2.3's real contract. The old wording passed vacuously if every replace failed. **Negative control required**: with scratch-then-replace removed in favour of an in-place truncating write, the reader must observe at least one invalid document. |
| TC-210 | Two arms. **(a)** A stale `RUN.status.json` with `Outcome: "running"` and **no `Temp`**: the next run starts normally, overwrites it, and produces a byte-identical store to a run started with no status file. **(b)** A legitimately reclaimable marker-only `Temp` plus a stale status file: the SR-017 reclaim proceeds as TC-186 does and the successor overwrites the status. A third arm asserts the per-set `Outcome` flag: a failing set followed by a clean set writes `succeeded` for the clean one | Integration / Full | "A stale status file is inert" — phrased as **the next run that successfully acquires the staging lock**, so WP14 correctly refusing a run over staged content is not mistaken for a telemetry defect. |
| TC-211 | In a run producing both concurrently, lines written by the observer thread and by the pipeline appear in the set log as **whole, well-formed lines with no interleaving or truncation**, all in the §2.2 format, **from step 2 onward** | Integration / Full | The achievable single-writer property. Not "matches Common's format character-for-character" and not "one writer for the whole run" — Engine owns the format, and steps 1/1.5 precede any sink. |
| TC-212 | At the default threshold no `DEBUG` line reaches the set log (both sites: `Stored object` and the capacity-check line); at `-LogLevel DEBUG` the per-physical-write line reappears and the SR-060 one-write count still holds; `ERROR`/`WARN`/`INFO` emit at both thresholds | Integration / Smoke | §2.4's ruling, and the regression that keeps WP9 MAJ-2's evidence obtainable (`Coverage.Tests.ps1:3320`). **Negative control required.** |
| TC-213 | Throughout a full run, **neither `RUN.status.json` nor `RUN.status.json.tmp` ever appears beneath `Temp`** at any sampling point, including after step 7 and during step 12.x. Ordinary staging content under `Temp` (prior manifest, sidecar, evicted/superseded data, the restore kit) is **explicitly permitted** | Integration / Smoke | **I-1**, mechanically. The old "`Temp` contains nothing but `RUN.inprogress`" would have failed every ordinary changed run right after step 7 — `Temp` holding content is what `Temp` is for. |
| TC-214 | With a stale `RUN.status.json` **and** a leftover `RUN.status.json.tmp` present at the `ChangePath` root: a stale-`Temp` reclaim proceeds exactly as TC-186 does, prune's inventory is unchanged, and change-folder sanitation ignores both | Integration / Full | **I-2** against the WP14 surface — a status file must never become the thing that blocks a reclaim. |
| TC-215 | Both restorers restore byte-exact from a backup whose `ChangePath` holds a status file and a scratch file — from the backup root and from a dated snapshot; no `Snapshot_*` folder contains either file. **Plus a fallback arm that forces the T2 snapshot-enumeration-error path** (`Reconstruct.ps1:1126` / `reconstruct.sh:1288`) with both files present, asserting the restore's exit code and output are what the Owner's Q6 ruling requires | Integration / Full | **I-2** across the kit boundary; the WP14 TC-202 analogue. The happy path alone cannot see the §2.3 exposure — that is exactly how it was missed. |
| TC-216 | Both `KitRevision` markers (`Reconstruct.ps1`, `bash/reconstruct.sh`) hold the value this package expects — **10** under Q6 option (b), **11** under option (a) — and no restore-kit template is modified beyond what that option allows | Unit / Smoke, `Inspection` | **I-3/I-4**, in the form a *shipped* test can actually hold. The old "`Common.psm1` byte-identical to pre-WP16" is unknowable to a shipped test and would redden on every future legitimate Common change; the diff stays a **commit-gate step** in Part B. |
| TC-217 | **Region-scoped**: the bodies of the named safety functions — `Initialize-StagingFolder`, `Remove-OwnStagingFolder`, `Assert-StagingLockOwned`, `Complete-ChangeFolder`, `Remove-BackupSnapshot`, `Invoke-PruneEntrySweep`, `Test-BackupStorageForm`, and the change-folder sanitation and pool-inventory helpers — contain **no** reference to `RUN.status.json`, asserted by extracting each function's text by name rather than grepping the file. Backed behaviourally by TC-214 and TC-215 | Unit / Smoke, `Inspection` | **I-2** structurally. File-granularity grep cannot express the rule: the observer and every safety path live in the same `Engine.psm1`, so a file-level assertion fails on the observer itself. |
| TC-218 | Hot-loop cost: a run over a large synthetic tree performs no telemetry I/O on the data path (the observer is the only writer of progress lines), and total set-log line count with banners+heartbeat at the default threshold is **lower** than the pre-WP16 baseline for the same tree. **Precondition, asserted in the fixture**: the tree yields more than 40 stored objects (so the suppressed per-object lines outnumber the banners) and the run is short enough that heartbeats number fewer than the suppressed lines | Integration / Full | **I-5**, and the honest check on §2.4's volume claim — which holds only under that precondition, and would otherwise be a test that fails for being run on a small fixture. |
| TC-219 | Container acceptance in `filebackup:local`: banners, progress lines and the status file are all present and correct in `ChangePath/backup.log` and `ChangePath/RUN.status.json` against a bind-mounted `ChangePath`, and both files are visible to the host at the mount. **Asserted explicitly: banners and pipeline lines appear on the container's console; timer-driven progress lines do not** (§2.6) | System / Release | The deployment the finding came from, and the form HomeHub would actually consume — with the channel limitation pinned so it cannot be quietly "fixed" into a blocked pipeline. |
| TC-220 | Doc rows: the README expectations section states the two-pass first-run read behaviour, names the working and non-working liveness channels, says live progress is a **file** channel, documents every `RUN.status.json` field, and carries the §2.6 non-claims; `-LogLevel` is documented | Integration / Smoke, `Inspection` | SR-080. Its verification method is `Inspection` per the registry's existing convention. |
| TC-221 | `RunObserver` unit tests in isolation: timer cadence; `Stop()` idempotent, non-throwing and draining; `ErrorCount`/`LastError` set when the callback throws; sink line format; serialized append under concurrent writers; `Utf8JsonWriter` output is UTF-8 without BOM and escapes backslashes/quotes/non-ASCII | Unit / Smoke | LLR-081 would otherwise be a `trace.py` orphan, and every property above is cheaper to pin here than through a full run. |

**Negative controls required** for **TC-206**, **TC-209** and **TC-212** — each must be
shown to fail with its mechanism removed (respectively: make the beat item-based rather
than time-based; replace scratch-then-replace with an in-place truncating write; remove
the threshold check). WP13's T4 is the precedent: two tests that could not fail shipped
as green. TC-209 was added to this list because a ~400-byte in-place write almost never
tears, which is the textbook shape of a test that cannot fail. The remaining cases
assert presence or absence of observable artifacts and fail naturally when the feature
is absent.

---

## 6. Open questions to close before or during implementation

| # | Question | Fallback / proposed default |
|---|---|---|
| Q1 | **Sibling class vs. generalizing `StagingHeartbeat`.** The obs review §8 and the WP14 §7 row both say WP16 "can share" WP14's compiled class; §2.2 proposes a **sibling** so telemetry failure modes stay out of the lock-liveness path — reinforced by the review round, since `RunObserver` must also be a log sink, which `StagingHeartbeat` must not become. | Proceed with the sibling. If the Owner prefers one class, it is parameterized by a mode flag with the identity guard and the first-beat-must-land throw enabled only for the lock — no other section of this plan changes. |
| Q2 | **`FILEBACKUP_LOG_LEVEL` on the container surface — the env var only.** *Narrowed by the review*: IF-001 needs **no revision** for the CLI parameter, because it already passes arbitrary `-arguments` through to `FileBackup.ps1`. The only question left is whether HomeHub wants an `FILEBACKUP_LOG_LEVEL` environment variable (an additive IF-001 note), and whether it wants `RUN.status.json` listed in IF-001 as a provided artifact. | Ship the `-LogLevel` **CLI parameter only** — no IF-001 change at all. Add the env var and its additive IF-001 row only on an explicit Owner ruling. WP16 writes the status file either way. |
| Q3 | **The numbers option E needs do not exist in this repo.** The review's §9 records two artefacts pending from the hub: a tree-size map (to convert path-position into a percentage) and the completed first pass's **total duration**. | Ship E's *shape* — the two-pass explanation, the channels, the non-claims — with the duration table seeded from whatever banner timings the acceptance runs produce, and mark the production baseline row as pending. Never invent a figure. |
| Q4 | **Is 30 s the right heartbeat cadence, and does it want to differ per phase?** 30 s is chosen so a stall is visible in under a minute while a multi-hour phase adds only a few hundred lines. | Keep it a module-scope constant, **not** a config knob (WP14's precedent for `StagingHeartbeatIntervalSeconds`), so the suite can compress it and production cannot drift. Revisit only with evidence. |
| Q5 | **Registry-integrity observation, outside this plan's scope.** `stakeholder-needs.md` currently carries **two different needs both numbered `SN-031`** (`stakeholder-needs.md:39,40` — the restore-fidelity need and the externally-damaged-store need). Adding `SN-036` does not disturb it, but a future `trace.py` change or an SN-031 back-reference will resolve ambiguously. | Raise separately; **do not fix it inside WP16**, where it would be an unrelated edit to a shared registry in a package whose diff should stay reviewable. Recorded here so it is not lost. **RESOLVED 2026-08-31, outside WP16, by Owner request:** the restore-fidelity need (`stakeholder-needs.md:39`, the later of the two, minted 2026-08-26) was renumbered `SN-036` and its children SR-065/SR-066 re-pointed; `SN-031` now means only the externally-damaged-store need. **WP16's proposed new need therefore becomes `SN-037`** (next-free SN, high-water now `SN-036`). |
| Q6 | **The restorers' T2 error-path fallback can enumerate `RUN.status.json` — fix it in the kit, or document the exposure?** *(New; raised by both reviewers, §2.3.)* On the 2026-08-25 Terra T2 path, when snapshot enumeration reports errors, both restorers add the `ChangePath` **root** to the candidate search pool (`Reconstruct.ps1:1126`, `reconstruct.sh:1288`) and then walk it recursively (`Reconstruct.ps1:386`, `reconstruct.sh:726`), filtered only by the fixed prefix regex at `Reconstruct.ps1:366` / `reconstruct.sh:127`, which cannot match `RUN.status.json`. A status file being rewritten or locked at that moment can register as an unreadable candidate and turn an intact backup's restore into **exit 4**. Two bounding facts: the path is an **error path only** (an unlistable snapshot tree is already a host fault), and the exposure class **already exists** — `Temp/RUN.inprogress` is equally unmatched by that regex and equally reachable under the same fallback today. **(a) Fix it**: add `RUN\.status\.json` (and the scratch suffix) to both restorers' skip regexes and **accept the `KitRevision` bump 10 → 11**, taken in that same commit for both kits. **(b) Document it**: record the exposure as benign-but-possible-exit-4 in `AGENTS.md` and the README, change no kit file, and leave `KitRevision` at 10. | **The coordinator recommends (a).** Restore correctness is this product's headline claim, and "an intact backup failed to restore because of a telemetry file" is exactly the sentence the product exists to make impossible — even on an error path. The bump is mechanical, the regex edit is one token in each restorer, and it also closes the pre-existing `RUN.inprogress` case in the same stroke. The cost is real and must be owned: it re-opens the restore kit that I-4 promised not to touch, it pulls kit-bundled code into WP16's diff, and per §8 it would **trigger the escalation clause** — a change on the restore surface earns the second reviewer. Option (b) keeps the package as sized but ships a known way for a restore to fail on an intact store. **Owner's call. TC-215's fallback arm is written either way** — it asserts a clean restore under (a), and the documented exit-4 behaviour under (b). |

---

## 7. Deliberately deferred, with reasons

| item | why not now |
|---|---|
| **Option D — percentage and ETA** | §5 D's own *Against* is decisive: the denominator is known only *after* hashing, so step 5 — the phase that is silent longest on a first run, and the entire core finding — is exactly the one that cannot have a percentage. It solves the smaller half of the problem at the highest cost. Revisit once the review §9's tree-size map exists (Q3), which would give step 5 an approximate denominator from the *previous* run's manifest. |
| **Progress telemetry for steps 13–16** | Telemetry stops at 12.9 by §2.2's lifetime rule, because after the marker release there is no lock to correlate to and the `Temp` folder is being renamed wholesale. Cross-snapshot dedup (step 14) can still be long, so this is a real residual gap — but closing it means telemetry outliving the lock, which is a lifetime question this package should not open. Banners cover the phases; revisit with evidence that 13–16 are where a run appears to hang. |
| **Progress lines on the host stream** | Rejected on the mechanism, not on the value (§9 below, R-3): a compiled callback has no runspace, and the only way to reach the host is to queue work back onto the pipeline that a multi-hour hash is blocking — which is the exact failure the design exists to avoid. Files are the channel. |
| **A `LogLevel` config key** | SR-027's config contract refuses unrecognized keys by name, so a new key drags in validation, the shipped example file, and a version consideration — disproportionate to a knob whose default is right for every scheduled run (§2.4). The `-LogLevel` parameter covers the operator case. |
| **Structured (JSON-lines) logging** | A genuinely better machine surface than parsing `backup.log`, and a much larger change to a file format HomeHub already consumes. `RUN.status.json` gives wrappers a machine-readable surface *without* touching the log format at all, which is the whole reason option C was chosen. |
| **A level threshold for `Remove-BackupSnapshot`'s logger** | Prune builds its own logger outside `Invoke-BackupSet`, so SR-079's threshold does not reach it and its one `DEBUG` line keeps emitting (§2.4). Bringing it in means either a second sink or a Common change; **WP15 is its natural home**, since WP15 already proposes instrumenting prune. |
| **Progress for `Remove-BackupSnapshot`** | The prune verb is human-invoked and minutes-long; its silence is a fraction of the backup path's exposure. See the WP15 paragraph below. |
| **A `PB-###` perf budget for logger throughput** | `performance-budgets.csv` holds only the `PB-000` example, so the harness's perf step is inert. TC-218 asserts the *direction* (line count falls, no hot-path I/O), which is what I-5 actually requires. Turning that into a numeric budget means being the project that switches the perf machinery on, and that decision is bigger than this package. |
| **Sorting the source walk** | It would make `CurrentPath` a true position indicator, which is what the obs review §9's `/proc` observation made tempting. It is also a change to the enumeration on the hottest data path in the product, for a presentation benefit. Explicitly out (§2.2). |
| **Anything that makes telemetry authoritative** | Alarm thresholds, "run is stuck" detection, exit codes for stalls: HomeHub owns alarm policy under IF-001 (I-4), and WP14 Part D's branch tokens already give it what it needs for the *stale lock* case. WP16's job is to make a *healthy long run* visible; deciding what to do about an unhealthy one is the wrapper's. |

**WP15's relationship to this package — presented, not decided.** WP15 (a heartbeat and
owner record for `Remove-BackupSnapshot`, from WP14 §7) is a deferred package that today
holds **no registry rows of its own**. It overlaps WP16 in two places now: both add new
rows around run-lifetime instrumentation and would plausibly reuse the same compiled
class WP16 declines to generalize (§2.2, Q1), and §2.4 hands WP15 the prune logger's
level threshold explicitly. *Merging* WP15's registry work into WP16 would mean one id
block, one `trace.py` pass and one review round instead of two, and would settle the
class-generalization question once rather than twice. *Keeping them separate* preserves a
clean severity boundary — WP15 is a **data-availability** package (a killed prune
permanently wedges backups, and SR-017's acceptance is currently scoped to exclude it)
and would therefore drag WP16's purely operational work back into a data-integrity
independent-review scope, which is precisely the argument the Owner accepted for not
merging WP16 into WP14. **The coordinator decides; this plan takes no position and
neither reserves nor consumes ids on WP15's behalf.**

---

## 8. Sequencing

Each row is one small green commit (CLAUDE.md commit cadence).

**Gate flag, stated once because the default is wrong here.** `docs/gate` reads `G3`, and
`scripts/check.ps1:122` adds `--require-verified --phase …` at G3. The registries
currently exit 1 on that path with two status findings (Draft `SR-017`/`SR-075`, blank
`Phase`), and commit 2 *adds four more* `Verification=Test` Draft SRs. So **commits 2–7
run `pwsh scripts/check.ps1 -Gate G2 …`**, which is what `check.ps1`'s own help prescribes
mid-decomposition. **Commit 8 is where `SR-076`…`SR-079` flip to `Verified` with their TC
statuses, and where the full `-Gate G3` run must be green** and pasted.

**Every code commit regenerates the maps.** `scripts/gen_arch_map.ps1` renders the module
map and the `Invoke-BackupSet` flow into `AGENTS.md` and `docs/architecture.md`, and
`check.ps1:132` fails Smoke when they are stale. Twenty banner calls, the observer
lifecycle and every new function change that flow, so `pwsh scripts/gen_arch_map.ps1`
plus committing both regenerated files is **part of the gate for commits 3–7**, not a
later documentation chore.

| # | Commit | TCs landed | Gate on |
|---|---|---|---|
| 1 | This plan | — | *(the commit carrying this file)* |
| 2 | Registry deltas (§3): SN-037, SR-076…SR-080, LLR-081…LLR-085, TC-205…TC-221 | — | `python scripts/trace.py --strict` green, orphans 0; `check.ps1 -Tier Smoke -Gate G2` |
| 3 | Part A — `RunObserver` compiled class (sink + timer + status writer), no call sites yet | TC-221 | `-Tier Smoke -Gate G2`; maps regenerated |
| 4 | Part B — verbosity contract: `New-SetLogger` over the Part A sink, `-LogLevel`, `Coverage.Tests.ps1` store at `DEBUG`, `Common.psm1` diff clean | TC-211, TC-212 (+ TC-212's negative control), TC-216 | `-Tier Smoke -Gate G2`; **the whole existing suite still green**, since every log assertion in it now runs through the new sink; maps regenerated |
| 5 | Part C — banners + progress seams | TC-205, TC-206 (+ negative control), TC-207, TC-218 | `-Tier Full -Gate G2`; maps regenerated |
| 6 | Part D — `RUN.status.json` + the `Get-ByteInventory` infrastructure classification | TC-208, TC-209 (+ negative control), TC-210, TC-213, TC-214, TC-215, TC-217 | `-Tier Full -Gate G2`; **WP14's TC-185…TC-204 re-run green**; maps regenerated |
| 7 | Part E — README/AGENTS.md expectations text; Q6's chosen disposition applied | TC-220 | `-Tier Smoke -Gate G2`; maps regenerated |
| 8 | Container acceptance + registry statuses to `Verified` + `docs/status.md` entry | TC-219 | **`-Tier Release -Gate G3`**, real output pasted |

Commit 3 precedes commit 4 because the sink must exist before the wrapper that delegates
to it — the old ordering built the delegation first. Commit 4 is nevertheless still
**first among the behaviour-changing commits**: commit 3 adds inert new code with no call
sites, while the level filter is the one change that touches every existing log assertion
in the suite, so it stays isolated where a regression is unambiguous, before any new
emission exists to confuse the diagnosis.

**Independent review (process.md §6) — one reviewer, after commit 6, before the gate.**
Justified honestly rather than by imitation: WP14 ran a *dual* adversarial round because
it edited the staging lock, the reclaim protocol and the fence points — the
data-integrity surface, where the last two independent reviews each found P0s. **WP16
touches none of it, and §2.1's no-new-`try`/`finally` constraint in the fenced phases is
what keeps that true** — the plan-stage review correctly noted that a `finally`-per-phase
banner design would have wrapped new control flow around steps 7, 11, 11.5 and 12.x and
forfeited this sizing. Its worst realistic failure is a noisy or absent log line, or a
telemetry file nobody reads. A single fresh-context reviewer is proportionate, and the
brief should point them at the four places where this package *could* still hurt
something real:

1. **I-1/I-2 in practice** — that nothing was written inside `Temp` and no safety path
   learned to read the status file (the failure that would break WP14's reclaim).
2. **The single sink for the set log** (§2.2) — the one place existing behaviour is
   re-plumbed rather than extended, and the one place a concurrency bug could corrupt an
   artifact operators depend on. Engine now owns the truncation and the format.
3. **The §2.4 trade** — that suppressing the per-object `DEBUG` line by default did not
   quietly cost SR-060 its evidence (§8 C-1's correction is the reason this is a trade at
   all, not a free win), and that the capacity-check line's loss is acceptable.
4. **§2.1's constraint, verified in the diff** — no new `try`/`finally` frame in phases
   7, 11, 11.5, 12, 12.5 or 12.9.

**Escalation, decided in advance rather than under time pressure.** If that reviewer
finds anything on the WP14 surface, the review escalates to the dual round by default.
**Q6 option (a) triggers the same escalation automatically**, because it edits
kit-bundled restore code.

---

## 9. Plan-stage review round, 2026-08-31 — composite disposition

Two independent fresh-context reviewers examined revision 1 in parallel: a fresh Opus
context (4 P0, 8 P1, 6 P2) and a Codex CLI context (0 P0, 8 P1, 6 P2). The two overlap
substantially; overlapping findings are composited into one row naming both sources. Every
claim acted on below was re-verified against the working tree before folding — the phase
count, the logger and 12.9 line numbers, the three `DEBUG` sites, the restorer fallback
and its skip regex, `Get-ByteInventory`'s infrastructure list, `gen_cases.py`'s parser,
`check.ps1`'s G3 branch, and the `Utf8JsonWriter`-under-`Add-Type` probe are all confirmed
facts, not accepted assertions. Style follows WP14 §10.

| # | Finding (source · severity) | Disposition | Folded into |
|---|---|---|---|
| **R-1** | Banners for steps 1, 1.5 and 2 are impossible — the set logger does not exist until `Engine.psm1:5781`, and step 1.5 can fail the set with no sink at all. SR-076's bound, its "complete account" claim and TC-205 were unachievable. *(Opus 1 · P0)* | **Accepted.** Banners scoped to **step 3 onward**; the "complete account of the run" claim **withdrawn** and replaced with an explicit statement that steps 1/1.5/2 are outside the contract, keeping today's `Write-Warning`/`Write-Error` behaviour. | §2.1, SR-076, TC-205 |
| **R-2** | "Sixteen numbered steps" is false: the code carries **twenty-four** (`1, 1.5, 2, 3, 4, 5, 5.1, 5.2, 5.5, 6, 7, 8, 9, 9.4, 10, 11, 11.5, 12, 12.5, 12.9, 13, 14, 15, 16`), and the omitted fractional steps include the SR-055 and SR-057 guards, the SR-052 preflight, pool-mutating `Save-SupersededData` and the SR-075 marker release. *(Opus 2 · P0)* | **Accepted; verified independently** (`Engine.psm1:5744-6095`). The phase list is now **derived from the code**. Fractional steps are enumerated explicitly: **5.1, 5.2, 9.4, 11.5, 12.5 and 12.9 get banners**; **5.5 folds into step 5** because it declares a scriptblock and does no work. Twenty bannered phases; `[n/16]` replaced by the code's own step label. | §2.1, §2.3 schema, SR-076, LLR-083 |
| **R-3** | Progress lines can never reach stdout/journald — the compiled callback has no runspace and cannot `Write-Host`, while every existing engine line reaches both the file and the host (`Common.psm1:206-207`). Contradicts SR-077's `sink=set{file,stdout}`, TC-219 and the channel the finding was measured on. Alternative offered: have the pipeline drain a queue the callback fills. *(Opus 3 · P0)* | **Accepted as file-only.** Timer-driven progress lines are **file-only**; `sink` dropped from SR-077's Permutations cell; §2.6 and option E state plainly that the live-progress channel is `ChangePath/backup.log` and `RUN.status.json`, **not** `docker logs`. Banners and every pipeline-emitted line still reach the host as today, through the wrapper's `Write-Host`. **The queue-drain alternative is REJECTED**: draining a queue means queueing work back onto the pipeline, which reintroduces the blocked-pipeline problem the compiled design exists to avoid. | §0, §2.2, §2.6, §2.5(3), §7, SR-077, SR-080, TC-219 |
| **R-4** | The observer's lifetime contradicts the landed WP14 lifecycle: the marker is released and the heartbeat stopped at step **12.9** (`Engine.psm1:6058-6072`), and step 13 renames `Temp` wholesale — so TC-208's `RunId` correlation is unassertable after 12.9 and TC-213's "`Temp` holds only `RUN.inprogress`" is false for steps 13-16 by WP14's own design. **Merged with:** TC-213 also contradicts `Temp`'s purpose outright — the engine stages the prior manifest and sidecar (`:5915`) and evicted/superseded data (`:5992`) there, so every ordinary changed run fails it right after step 7. *(Opus 4 · P0 + Codex 2 · P1)* | **Accepted.** Lifetime pinned: the sink is created at step 2; **telemetry arms after the lock at step 3 and stops in the same step-12.9 block, immediately after `Stop-StagingHeartbeat` and before the marker delete** (verified ordering: fence → stop → delete → finalize); the file sink lives on to step 16 and closes in the outer `finally`; a terminal record is written at 12.9 **and** again in the outer `finally` for abort paths, with **last write wins**, explicitly because the file is telemetry. TC-208 names the valid window; **TC-213 is reworded to assert only that `RUN.status.json` and its scratch never appear beneath `Temp`, with normal staging content explicitly allowed.** | §2.2, §2.6, SR-078, LLR-085, TC-208, TC-213 |
| **R-5** | §2.3's "every `ChangePath` scanner is directory-only" is false for **both restorers**, and the hole is kit-bundled: on the 2026-08-25 Terra T2 path, `Reconstruct.ps1:1126` and `reconstruct.sh:1288` add the `ChangePath` root to the search pool, then walk it recursively (`Reconstruct.ps1:386` / `reconstruct.sh:726`) filtered only by a fixed prefix regex that cannot match `RUN.status.json` — a locked or rewriting status file can turn an intact backup's restore into exit 4. TC-215 tests only the happy path. Any fix bumps `KitRevision`, which I-4 says will not happen. *(Opus 5 · P1 + Codex 10 · P2)* | **Factual correction accepted; the fix choice escalated.** §2.3's universal-scanner claim is **narrowed** — the engine and prune scanners and both restorers' *normal* snapshot selection are directory-and-pattern based, and the T2 fallback is named as the exception with verified citations (`Reconstruct.ps1:366/386/1126`, `reconstruct.sh:127/726/1288`). Two bounding facts recorded: it is an **error path only**, and the exposure class already exists (`Temp/RUN.inprogress` is equally unmatched by that regex). **The remedy is a new Owner question, Q6**, with the coordinator recommending option (a) — add the name to both restorers' skip logic and take the `KitRevision` 10 → 11 bump, because restore correctness is the product's headline and the bump is mechanical — against option (b), documenting the exposure as benign-but-possible-exit-4. I-4 is qualified accordingly, and **TC-215 gains a fallback arm that forces the enumeration-error path either way.** | §2.3, I-2, I-4, §3 kit note, **Q6**, TC-215, TC-216, §8 escalation |
| **R-6** | The atomic-replace argument overreaches: WP14 §6 Q1 / §11 R-12 leave rename behaviour on the hub's stack unproven pending TC-195, `MoveFileEx(REPLACE_EXISTING)` fails on a sharing violation while a reader holds the target open, and Microsoft/.NET do not promise crash atomicity per filesystem. **TC-209 as worded passes vacuously if every replace fails** — the poller simply re-reads the same valid old document. **Merged with:** TC-209 is the textbook cannot-fail test; a ~400-byte in-place write almost never tears, so it would pass with the mechanism removed. *(Opus 6 · P1 + Codex 4 · P1 + Opus 11 · P1)* | **Accepted.** Restated as **best-effort same-directory replace**: atomic where the platform makes rename atomic, and the design depends on nothing stronger; **a failed replace increments `ErrorCount` and is never fatal**; **readers must tolerate missing, stale or malformed telemetry**, stated in §2.6, SR-078 and the README field reference. The R-4-does-not-transfer argument is kept (it is correct — R-4 needed exclusive create, this needs overwrite) but no longer carries a universal-atomicity claim. **TC-209 now asserts forward progress** (`UpdatedUtc` advanced ≥ N, successful-replace count ≥ N) **plus** no-torn-read on successful reads, **and gains a negative control** (in-place truncating write must produce an observable invalid read). | §2.3, §2.6, I-5, SR-078, LLR-085, TC-209 |
| **R-7** | §2.2, §2.4 and LLR-082 contradict each other: a wrapper cannot both *call* Common's `New-Logger` closure and *be* the single writer, because that closure does its own `Add-Content` **and** `Write-Host` and exposes no append seam (`Common.psm1:201-208`). **Merged with:** nothing serializes the first three steps' output — the sink was to be built at step 2 but the observer only after the lock at step 3, so a run refusing at step 3 never has one, and commit 3 built the delegation before commit 4 created the class. **Merged with:** Codex's proposed shape — one compiled sink at step 2 with its timer inactive, `Write-Host` preserved in the PowerShell wrapper, `RunId` bound and telemetry armed after the lock, an independent host path for sink errors, commits reordered. *(Opus 7 · P1 + Opus 8 · P1 + Codex 1 · P1)* | **Accepted with Codex's shape.** **ONE compiled file sink created at step 2**, timer inactive until the lock arms it at step 3. The PowerShell wrapper applies the level filter and preserves `Write-Host` host-stream behaviour. **Engine owns the per-run truncation and line format from step 2 onward** — named as a re-implementation inside Engine, not a wrapper, because that is what it is. Common's `New-Logger` stays **byte-identical** and remains in use by `FileBackup.ps1`'s global log and `Remove-BackupSnapshot`'s logger. Sink errors surface on an independent host path. **TC-211 reworded to the achievable property**: a single serialized file writer **from step 2 onward**, no interleaved or torn lines — not "matches Common's format character-for-character", not "one writer for the whole run". §8 reorders: class (commit 3) before wrapper (commit 4). | I-3, §2.2, §2.4, LLR-081, LLR-082, Part A, Part B, TC-211, §8 |
| **R-8** | The commit-2 gate is unrunnable as specified and fails today: `docs/gate` is `G3`, `check.ps1:122` adds `--require-verified --phase …` at G3, the registries already exit 1 with two status findings, and commit 2 adds four more Draft `Verification=Test` SRs. `check.ps1`'s own help prescribes `-Gate G2` mid-decomposition; the plan never said so. *(Opus 9 · P1)* | **Accepted; verified against `check.ps1:122` and `docs/gate`.** §8 now states **`-Gate G2` for commits 2–7** in a standing note and in every gate cell, and names **commit 8** as the point where SR-076…SR-079 flip to `Verified` and the full **`-Gate G3`** run must be green and pasted. | §8 |
| **R-9** | TC-216 and TC-217 are not implementable as specified. A shipped test cannot know "`Common.psm1` byte-identical to *pre-WP16*"; a pinned hash reddens on every future legitimate Common change. And TC-217's file-granularity rule cannot be expressed by grep — the observer and every safety path live in the same `Engine.psm1`, so the assertion fails on the observer itself. *(Opus 10 · P1)* | **Accepted.** **TC-216 reduces to the `KitRevision`-marker assertion** (value 10 under Q6(b), 11 under Q6(a)) plus "no kit template modified beyond that"; the `Common.psm1` diff stays a **commit-gate step in Part B**, which is where a historical comparison actually belongs. **TC-217 becomes behavioural + region-scoped**: the named safety functions — `Initialize-StagingFolder`, `Remove-OwnStagingFolder`, `Assert-StagingLockOwned`, `Complete-ChangeFolder`, `Remove-BackupSnapshot`, `Invoke-PruneEntrySweep`, `Test-BackupStorageForm`, plus the sanitation and pool-inventory helpers — are extracted **by name** and asserted to contain no reference, backed by TC-214 and TC-215. | TC-216, TC-217, Part B, Part D |
| **R-10** | Risk sizing does not survive §2.1's own design: a `done` banner from a `finally` per phase wraps **new control flow** around step 7 (fence-first), step 11 (evict, fence-first) and step 11.5, inside a function whose catches call `Remove-OwnStagingFolder` and whose fence placement was rewritten days ago (WP14 §11 R-1/R-2). Either constrain the emission form in the fenced phases or accept the dual round. *(Opus 12 · P1)* | **Accepted as a constraint, not a resize.** Banner emission in the fenced and pool-mutating phases — **7, 11, 11.5, 12, 12.5, 12.9** — uses the **existing** control flow (emit `done` after the existing final statement or from the existing `catch`); **no new `try`/`finally` nesting** there. Phases outside that set may use a `finally`-based `done` line. The single-reviewer sizing is kept **with this constraint stated as its explicit justification**, it is added as review-brief item 4, and the escalation clause stands (and now also fires automatically on Q6 option (a)). | §2.1, LLR-083, §8 |
| **R-11** | TC-210 conflates inert telemetry with WP14's authoritative stale lock: a kill during step 5 leaves `Temp/RUN.inprogress` and staged content, and `Initialize-StagingFolder` (`:4712`) will correctly refuse the successor — so the "next run" never reaches an observer and TC-210 fails for the wrong reason. *(Codex 3 · P1)* | **Accepted.** Overwrite is phrased throughout as "**the next run that successfully acquires the staging lock**", with the SR-017 refusal named as WP14 working rather than a telemetry defect. TC-210 gets two arms: **(a)** a stale status file with **no `Temp`**, and **(b)** a legitimately reclaimable **marker-only `Temp`** whose reclaim proceeds as TC-186 does. | §2.3, TC-210 |
| **R-12** | The ordered-walk claim is false in current code: `Update-SourceManifest` enumerates unsorted `Get-ChildItem` output (`Engine.psm1:496-517`) and its only sort is by path length, *after* hashing. TC-207's path-monotonicity assertion would be flaky by construction and the advertised "position indicator" is not one. *(Codex 5 · P1)* | **Accepted; verified.** `CurrentPath` is now a **current-item signal only**. The stable-position and non-decreasing-path claims are dropped from §2.2 and from the obs review §9's design-consequence paragraph as quoted there; **TC-207's monotonicity assertion is removed** (counts stay monotonic; paths do not). §2.6 tells operators the same. **No sorting is added under WP16** — stated explicitly, and recorded in §7 as deliberately out. | §2.2, §2.6, §7, SR-077, LLR-084, TC-207 |
| **R-13** | The step-10 progress seam cannot report the file actually being read: the real source candidate is elected **inside `Invoke-BackupFileGroup`**, whose fallback/retry loop iterates candidates and copies from whichever is readable — so telemetry would keep naming the owner while a twin supplies the bytes. *(Codex 6 · P1)* | **Accepted; verified in the candidate loop.** `CurrentPath` is assigned **immediately before each candidate copy attempt inside `Invoke-BackupFileGroup`**, not in the outer step-10 loop; file and byte increments are defined **after one successful physical group write**. LLR-084 rewritten accordingly. | §2.2, LLR-084, Part C |
| **R-14** | SR-076 and TC-205 are internally unsatisfiable: "exactly 32 lines" against "a skipped phase emits one line", and "all sixteen start/done pairs" against a normal set with `BrowseView=off` skipping step 16. The failed-phase form has no test arm, and §3's "no Permutations cell needed" overlooks the variable `done|skipped|failed` outcome. *(Codex 7 · P1)* | **Accepted; merged into R-1/R-2's rewrite.** The bound is restated from the real phase count as "**at most 40** banner lines"; the three outcome forms are defined explicitly; SR-076 **gains** a Permutations cell `outcome=set{done,skipped,failed}`; and **TC-205 is reworded with one arm per outcome**, using `BrowseView=off` as the natural skip case. | §2.1, §3, SR-076, TC-205 |
| **R-15** | The existing **TC-204** will fail: `Get-ByteInventory` (`tests/Unit/StagingLock.Tests.ps1:217`) excludes known infrastructure but not the new files, so the first run's terminal status hash enters the protected inventory and vanishes when the second run overwrites it — reported as destroyed stored content. *(Codex 8 · P1)* | **Accepted; verified against the `$infra` list.** The plan now states that `Get-ByteInventory` **and any whole-tree comparison helper** must classify `RUN.status.json` and `RUN.status.json.tmp` as infrastructure, **in the same commit that introduces the file**, and names it as a **commit deliverable** of Part D / §8 row 6 rather than a follow-up. | Part D, §8 |
| **R-16** | Steps 13/14 progress registration is scope creep — the binding option B names steps 5 and 10 — and contradicts LLR-084, which listed only those two. *(Codex 9 · P2)* | **Accepted.** Step-13/14 progress registration is **removed**. Their **banners remain** in scope. The residual gap (a long cross-snapshot dedup with no telemetry) is recorded honestly in §7 rather than papered over, since R-4's lifetime rule stops telemetry at 12.9 anyway. | §2.2, §7, LLR-084 |
| **R-17** | The `Stored object` line's cited location is wrong: `Engine.psm1:5002` is an owner-form comment; the call is at `:5062`, and it has already moved twice. *(Codex 11 · P2 + Opus 13 · P2)* | **Accepted.** The line is cited **by function name — `Invoke-BackupFileGroup`** — with the current line number given only parenthetically and flagged as drifting. | §2.4 |
| **R-18** | §2.4 accounts for one of **three** `DEBUG` sites. The capacity-check line (SR-052, set log) also goes dark by default, unmentioned; and the third is inside `Remove-BackupSnapshot`, which builds its own logger outside `Invoke-BackupSet` — so SR-079's product-wide level table is enforced on one sink only. *(Opus 14 · P2)* | **Accepted; all three verified** (`Engine.psm1:2592`, `:5063`, `:5487` — the review's `:5427` was stale). §2.4 now carries a three-row site table: the capacity-check line in `Assert-BackupCapacity` is **named as also suppressed by default**, with step 9.4's banner and the still-emitting `ERROR` refusal path noted as what remains. **SR-079 is scoped honestly to the set log**; the global orchestrator log needs no wrapper (zero `DEBUG` sites); **prune's logger is explicitly out of scope**, with WP15 named as its natural home in §7. | §2.4, SR-079, §7 |
| **R-19** | Permutations hygiene: `parse_spec` (`gen_cases.py:56-80`) splits on `;` then `=`, so a literal paste of `SR-077: phase=set{…}` yields a dimension named `SR-077: phase`. And SR-078's cell expands to 16 rows with no statement of how they relate to the hand-assigned TCs. *(Opus 15 · P2)* | **Accepted; verified against the parser.** Each `SR-###:` label is moved **out of the fenced block** into the prose above it, one fence per SR carrying only parseable text. A sentence states that the **generated matrix is illustrative and is not landed on top of** TC-205…TC-221. | §3 |
| **R-20** | §5 claims ids are assigned so §4/§8 cannot drift, but §8's `RunObserver` commit carries **no TC ids**, `trace.py`'s orphan rule requires every LLR to have at least one TC, and no LLR→TC mapping is stated anywhere. *(Opus 16 · P2)* | **Accepted.** An explicit **LLR→TC map** (and an SR→TC line) is added to §3; **TC-221** is created for the class's unit tests so LLR-081 cannot orphan; and **every §8 commit row names its TC ids**, including TC-221 on the class commit. | §3, §5 (TC-221), §8 |
| **R-21** | The "green small commits" sequence omits mandatory generated-map updates: Smoke always runs the architecture freshness check (`check.ps1:132`), and every new Engine function changes the generated maps in both `AGENTS.md` and `docs/architecture.md` — so each code commit would fail its own gate as stale. *(Codex 12 · P2 + Opus 17 · P2)* | **Accepted.** §8 carries a standing note that **regenerating and committing both maps is part of the gate for every code commit (3–7)**, and each gate cell says "maps regenerated". | §8 |
| **R-22** | JSON escaping and encoding are unspecified: the compiled class is told to write JSON itself with no serializer named, while `CurrentPath` on Windows is backslash-laden and set/host names may need escaping — interpolation would emit invalid JSON that simple fixtures still pass. *(Codex 13 · P2)* | **Accepted, and the reference verified rather than assumed.** **Structural serialization via `System.Text.Json.Utf8JsonWriter`, UTF-8 without BOM, never string interpolation.** The plan states the explicit `Add-Type -ReferencedAssemblies System.Text.Json, System.Memory, System.Runtime` reference and records the probe run on this tree (PowerShell 7.6.5 / .NET 10.0.11) that serialized `sub\alpha"q".txt` to `{"CurrentPath":"sub\\alpha\u0022q\u0022.txt"}`; `System.Text.Json` has been in the shared framework since .NET Core 3.0. **TC-208 gains an escaped nested-path arm**, and TC-221 pins the encoding. | §2.3, LLR-081, LLR-085, TC-208, TC-221 |
| **R-23** | Terminal `Outcome` has no per-set source of truth: `Invoke-BackupSet` receives a **process-wide** `[ref]$OverallSuccess` (`:5737`) that a previous set may already have falsified and that a non-throwing copy failure sets false (`:5054`) — so a clean set could write `failed`, while deriving from exceptions alone would call a non-throwing copy failure `succeeded`. *(Codex 14 · P2)* | **Accepted; verified.** A **local per-set outcome flag**, initialised `running`, set `failed` at every non-throwing failure site and every `catch`/early-`return` path, `succeeded` only on normal completion, and **merged into the aggregate separately** exactly as today. **TC-210 gains a status arm** covering a failing set followed by a clean one. | §2.3, LLR-085, TC-210 |
| **R-24** | TC-218's "total set-log line count is **lower** than the pre-WP16 baseline" holds only when the tree has more stored objects than there are banners, and the run is short enough for few heartbeats. *(Opus 18 · P2)* | **Accepted.** TC-218 now states the **tree-size precondition** and asserts it in the fixture: more than 40 stored objects, and a run short enough that heartbeats number fewer than the suppressed per-object lines. | TC-218 |
| **R-25** | Q2 is over-cautious rather than wrong: IF-001 already passes arbitrary `-arguments` through to `FileBackup.ps1`, so `-LogLevel` needs **no** IF-001 revision — the Owner should not be asked to rule on a non-question. *(Opus, sound-areas note)* | **Accepted.** **Q2 is narrowed to the environment-variable question only** (`FILEBACKUP_LOG_LEVEL`, plus whether HomeHub wants `RUN.status.json` listed as a provided artifact). I-4 now states that IF-001 needs no revision for the CLI parameter. | I-4, Q2 |
| **R-26** | **Sound areas, recorded so the next reviewer need not re-derive them.** Both reviewers independently confirmed: the id high-water marks and next-free blocks (`SN-035/SR-075/LLR-080/TC-204` → `SN-036/SR-076/LLR-081/TC-205`; the SN half is now `SN-036` → `SN-037` after the Q5 renumber below) and that **WP15 reserves nothing**; the Q5 `SN-031` duplication is real (`stakeholder-needs.md:39,40`); the Inspection/Demonstration counts are exact and SR-080 correctly carries no LLR (`trace.py` exempts Inspection SRs); the **non-restorer** scanners do enumerate `-Directory -Force` with `ChangeFolderRegex` as claimed (`Engine.psm1:1034, :1107, :1791`), and the engine/prune snapshot selectors are directory-and-pattern based — **only the restore fallback (R-5) invalidates the universal claim**; I-1's `HoldsContent` reasoning matches WP14 §2.3; the LLR-073 citation is accurate; the `Coverage.Tests.ps1:3320` dependency is real and threading `-LogLevel DEBUG` is a sufficient remedy; every reused pattern element matches the landed `StagingHeartbeat` (`Engine.psm1:3305-3560`) and the sibling-class deviation is honestly surfaced; placement outside `Temp`, the one-way `RunId` correlation and the Engine/Common separation are correct; and **scope discipline holds** — option D and the `LogLevel` config key are deferred with reasons matching SR-027's closed schema, and the WP15 paragraph correctly takes no position. **One alternative was considered and rejected**: R-3's queue-drain route to stdout, because it reintroduces the blocked pipeline the compiled design exists to avoid. | *(no change required)* | — |

**Net effect on scope:** nothing was added to the package's surface except the
`Get-ByteInventory` classification (R-15, test-side) and TC-221 (R-20). Three things were
**removed** — step-13/14 progress registration (R-16), the stdout channel (R-3) and the
walk-ordering claim (R-12) — and one thing was escalated to the Owner rather than decided
(**Q6**, R-5). The A/B/C/O-3/E scope ruling is unchanged.

---

## 10. Later review rounds

*(Empty by design. The implementation-stage review round — one reviewer after §8's
commit 6, or two if either escalation trigger fires — is appended here with per-finding
dispositions in the style of §9 and WP14 §11: finding, severity, disposition, and for
rejected findings the recorded reason.)*
