# Audit, 2026-11-07: defects found but never fixed, in either engine

**For:** the Owner. **Status:** read-only audit, step 1 of
[the 2026-11-07 brief](plans/2026-11-07-native-probe-fix-brief.md). No code was changed, nothing
was built or run, and the hub was not touched. Audited at `ef3ab06` on `Rust-Rewrite`.

**How it was done.** Six independent read-only passes, one per area: the compression probe,
run observability, staging and kill safety, scale (memory, file checks, prune), the restore kits,
and the native rewrite's scope. The claims that carry the most weight were then re-read at the
cited lines: the restart behaviour, Incoming cleanup, checkpoints, the probe, the 7-Zip call,
prune, the vanished-file path and the PowerShell second walk. Every claim is marked:

- **[read]**: someone read the code, document or commit at the place cited.
- **[estimate]**: worked out from code or arithmetic, not measured or run.

**Terms used throughout.**

- **PowerShell engine:** the reference engine in `Modules/FileBackup.Engine.psm1` and
  `Modules/FileBackup.Common.psm1`. This is what ran on the hub until 2026-10-05.
- **Rust engine:** the native rewrite in `rust/src/` (2026-11-05/06). Its first real library run
  is the one stopped on 2026-11-07.
- **Probe:** the test that decides whether a file is worth compressing. It compresses a few
  256 KiB **windows** (samples) of the file. If those shrink to 90% or less, the whole file is
  compressed with 7-Zip.
- **SR / LLR / TC:** a system requirement, a low-level (design) requirement, a test case. These
  are the rows in `docs/requirements/` that the native port was built from.
- **WP:** a numbered work package (a plan for one change).
- **Kit:** the restore scripts written into every backup so a restore needs nothing else.
- **Store folders:** `CurrentBackup` is the latest state, `BackupHistory/<date>` holds one folder
  per older state, and `Incoming` is the engine's scratch area inside the store.

---

## 1. Short answer

**Why the reviews did not reach the Rust engine.** The rewrite carried what the requirement
rows said, and nothing else (§3). A defect-review fix reached Rust only if someone had written it
into a requirement that survived the 2026-11-05 rebaseline. Fixes that lived only in PowerShell
code, in design rows retired that day, or in a plan never approved were invisible to it. None of
the documents that defined the native scope names a defect review. The probe-placement defect is
a special case: it was never fixed in PowerShell either, so the port copied the defect faithfully.

**What it costs on the hub, ranked.** Hours are per first pass of the 1.1 TiB library unless
stated.

| # | Item | Fixed in PowerShell? | In Rust? | Hub cost |
|---|---|---|---|---|
| 1 | The probe samples the start and end of a file, where container headers and padding sit, so it misjudges media (§4.5) | No, never built anywhere | No | About 31 of 52 hours of 7-Zip work is avoidable for about 6.5 GiB of saving, by the 2026-09-07 measurements [estimate] |
| 2 | Each Rust probe starts 7-Zip and writes and flushes temporary files on the backup disk; PowerShell measured in memory (§7.1) | n/a | Regressed | About 5-7 h of probing against about 1.9 h [estimate] |
| 3 | Rust logs nothing about why a file was compressed: no decision line, no probe counters, no step timings, no timestamps in `backup.log` (§4.3, §7.2) | Yes | No | The stopped run could only be diagnosed by running 7-Zip by hand on the hub |
| 4 | The Rust progress count stops moving during compression and its read-back check (§7.2) | Partly | No | Hours of an unchanged progress line on each large video |
| 5 | Rust copies every new or changed file in full into `Incoming` before checking whether that content is already stored. When it is, Rust then reads the stored copy in full again and fully expands a compressed one (§7.3) | Yes | No | A moved folder or restarted file costs about 3 times its size in disk work; a sparse file is written out in full, zeros included [estimate] |
| 6 | A 7-Zip run gets 300 s plus 1 s per MiB. Running past that stops the **whole run** as a host failure (§7.1) | n/a | New risk | Any file that compresses slower than about 1 MiB/s ends the night (the hub measured 2.4 MiB/s) |
| 7 | Rust prune fully reads, and expands where compressed, every object the kept states need, on every prune, dry run included (§7.3) | No | New | About the whole library read per prune, at least 3 h plus 7-Zip time [estimate]. The hub does not prune today |
| 8 | Per-file checks that PowerShell had removed came back: one check of each unchanged file's stored object per night, and the whole store listed twice per run (§4.6) | Yes | Regressed | Up to an hour or more a night through ntfs-3g; unmeasured on the sharded layout [estimate] |
| 9 | Rust ignores every `FILEBACKUP_*` environment variable without a warning, including the 7-Zip level and the container's action, dry-run and repair switches (§7.5) | n/a | Missing | An env-driven verify or prune silently runs a backup instead |
| 10 | Rust's own list of already-compressed file types drops `.z7`, the library's largest type (43%, 881 GB), and nine other media types (§4.2) | Yes | No | None under the default probe mode `always`; the nine-day `.z7` defect returns under `off` or `excluded-extensions` |

**Correctness items** (wrong outcome or wrong state, not just slowness):

- **Torn-manifest restore:** the native restore kit restores nothing from a manifest with damaged
  (NUL) bytes and exits 2. The PowerShell-era kits restore every row before the damage (§7.4).
- **Restarting the stopped run** turns its partial checkpoint into a permanent dated snapshot of
  a part-captured library (§2).
- **A killed Rust prune** blocks every backup (exit 2) until the same prune is run again
  (§6, Owner's queue).
- **A file deleted during a long Rust run** makes the run report a failure (exit 1). PowerShell
  counts it as a removal (§7.5).
- **Stored objects no manifest names** are never reported or cleaned by Rust (§4.6).
- **Ruling C40 reversed:** the native restore kit drops the Owner's ruling (2026-10-27) that an
  archive which fails to open is a host failure (exit 4). It now tries every other copy, then
  exits 1. That is arguably better and matches the native interface draft, but nobody recorded a
  ruling to change it (§6).

**The restart question** (§2). A restart reuses nearly all the stored data without reading or
compressing it again. It cleans `Incoming` and recaptures only the files stored after the last
checkpoint, which is at most the last minute, plus the 21 GB ESB file. That file needs about
42.4 GB free on the store, or the run stops at once. Before deploying, decide whether to fix the
probe first: otherwise the restart repeats the same hours on every remaining video.

---

## 2. The restart question

The Owner asked: does a restarted run reuse the 87 GB already stored, and does it reclaim
`Incoming` cleanly? Answered from the Rust code at `ef3ab06` [read unless marked].

**What the stopped run left behind.**

- **A manifest checkpoint.** During the library loop the whole manifest is rewritten into
  `CurrentBackup/MANIFEST.csv` once 60 s have passed since the last write, after each file
  (`rust/src/engine.rs:1027-1033`). The write is safe against power loss: a temporary file,
  flushed, renamed and the folder flushed (`platform.rs:191-218`). So every object stored more
  than a minute before the stop has a manifest row. A test kills a first run at a checkpoint and
  confirms reuse (`rust/tests/interruption.rs:154-178`; [read], not run).
- **The re-read date.** A first run records `LastHashRun` = the run's start, about 2026-11-07
  03:01 (`store.rs:107-113`). It records no `LastBackupRun`.
- **`Incoming/.tmpVJASFU`** (21 GB): the staged copy of the ESB `.mkv`. Rust copied all of it,
  zeros included, before deciding to compress (`engine.rs:486-488`).
- **`Incoming/archive-AJ18zx/`**: that file's compression folder. 7-Zip writes `content.7z`
  inside it (`engine.rs:560-569`).

**What a restart does, in order.**

1. **It cleans `Incoming`** after taking the store lock (`engine.rs:857` → `store.rs:241-268`).
   - `.tmpVJASFU` is deleted: an ordinary file whose name starts `.tmp`.
   - `archive-AJ18zx/` is deleted only if it holds nothing but a file named `content.7z`. Any
     other name, such as a 7-Zip temporary file, keeps the whole folder with a
     "residue retained" warning. The run still goes on with exit 0.
   - No test seeds this residue and checks the cleanup, so this rests on reading the code.
2. **It snapshots the checkpoint** (`engine.rs:867-874`, `store.rs:353-396`). The store is no
   longer new, so the run first saves the current manifest as `BackupHistory/<date>`, named from
   the manifest's modification time (about 10:38 on 2026-11-07 [estimate]). The restart then
   changes rows, so the snapshot is kept for good. **The result is a permanent dated state that
   restores as a part-captured library.** No data is lost, but anyone reading the history later
   must know what it is. PowerShell's design never snapshots a checkpoint mixture this way.
3. **It reuses checkpointed files without reading them** (`engine.rs:925-958`). A file with a
   row, the same size and time, and a stored object that looks right (correct length, or a 7-Zip
   signature in the first 6 bytes) is kept with no read.
   - Exception: a scheduled re-read falls due 7 days after `LastHashRun` (the hub configuration
     has `HashRecalcFreq: "W"` in MiniPC-Deployer `stack/backup/filebackup-store.json`; that the
     deployed copy matches is [estimate]).
   - A restart after about 2026-11-14 03:01 would therefore read every recorded file once more:
     read-only, with no writes and no compression.
4. **It finds stored objects that no row names, by name.** An object stored in the last minute
   before the stop has no row. The store is indexed by listing its folders (`store.rs:136-194`),
   so a match is reused, never compressed again (`engine.rs:505-557`). But reaching that match
   costs a full read of the source file, a full copy into `Incoming`, and a full read (or 7-Zip
   expand) of the stored object.
5. **It starts the ESB `.mkv` from scratch.**
   - Another full 21 GB copy into `Incoming`, then the probe, then compression of about 8.8 GiB
     of real data (about 1 h at 2.4 MiB/s [estimate]), then a full read-back check.
   - Staging refuses to start unless free space exceeds twice the file plus 1 MiB, about
     42.4 GB (`engine.rs:477-485`). If it is short, the **whole run stops** with exit 4.
6. **Everything not yet captured runs exactly as before,** with the same probe. Every remaining
   large video pays the same hours as in the first run.

**What a restart does not do.**

- It does not move or delete objects no manifest names; nothing in Rust ever does
  (`engine.rs:768-801`). This matters only if the checkpoint were lost.
- It does not clean `.tmp*` files outside `Incoming`. A kill in the middle of a checkpoint write
  can leave a manifest-sized `.tmp*` in `CurrentBackup` for good (`store.rs:195-270` covers only
  `Incoming`, `Initializing_*` and `Building_*`).

**Read-only checks the Owner may want on the hub before deciding** (not run by this audit):

- `stat -c '%y %s' CurrentBackup/MANIFEST.csv`, and `wc -l` of it: the checkpoint's time and
  row count. `find CurrentBackup -mindepth 2 -type f | wc -l` counts the stored objects for
  comparison.
- `ls -la Incoming/archive-AJ18zx/`: whether cleanup will remove it or keep it with a warning.
- `pgrep -a 7zz`: should print nothing. On Linux, 7-Zip runs in its own process group and is
  killed only by Rust's normal clean-up path (`tools.rs:36-40, 95-110`). Removing the container
  will have killed it [estimate].
- Free space on `/mnt/backup-drive`: the ESB file needs about 42.4 GB.
- **A figure to reconcile:** "92.3 GiB read" against "87 GB stored". If the 92.3 GiB includes
  the 21 GB ESB copy, the stored objects came from about 71 GiB yet occupy 87 GB, which cannot
  be. Either "87 GB" counts something else, such as allocated space, or the read counter
  includes more than the brief assumed. `du -sb` and `du -sh` of `CurrentBackup` would settle it.

---

## 3. Why the defect reviews did not reach the Rust engine

The native engine was built from a chain of documents. Each one names its inputs, and none names
a defect review [read]:

| Step | Document | What it says its inputs were |
|---|---|---|
| Implementation audit | `docs/requirements-audit-2026-11-05.md:4-5` | "the requirement registries, current backup and restore code, selected test sources, checking scripts, container contract and layout rulings" |
| Rebaseline | `docs/plans/spine-rebaseline-2026-11-05.md:55-59` | "It does not make current code the authority for what users need. Existing owner rulings in the bounded-run and single-store plans are inputs." Only those two plans are named |
| Fresh requirement derivation | `spine-rebaseline-2026-11-05/fresh-derivation.md` | "used only the project vision in the first 20 lines of the README, the stakeholder-needs, external, assumptions and hats registries … No current SR, LLR or TC registry, source implementation, audit, migration plan or implementation evidence was opened" |
| Native design | `native-design-2026-11-05/review.md:14-16` | "Port their contracts; change a mechanism only where an accepted obligation or measured limitation requires it", built against the 121 accepted requirements |
| Legacy cleanup | `native-design-2026-11-05/legacy-cleanup.md` | 127 design rows cut to 40 new ones (LLR-151..190); the old test definitions retired from the active plan |
| Workorder | `native-design-2026-11-05/implementation-workorder.md` | The work is the LLR-151..190 allocation |

A search of all of these for `defect-review`, `resolved-items`, `WP18`, `probe-window` and
`representativ` finds nothing outside the retired test list. All seven defect reviews predate
the audit commit `92268f9` [read].

**Three steps removed the fixes:**

1. **Code was treated as evidence, not as a requirement.** A behaviour that existed only in
   `FileBackup.Engine.psm1` was not carried forward as an obligation.
2. **The design rows that held the fixes were retired with no successor.**
   - The row for the already-compressed extension list, LLR-004, which held the 2026-08-31
     `.z7` fix, maps to nothing (`allocation.md`, "Retired legacy design crosswalk").
   - The full probe specification, LLR-086, maps to the new probe row LLR-162 only by a shared
     parent requirement, and the crosswalk itself says "That intersection is not equivalence".
     LLR-086 also required the per-file decision line and the probe counters.
   - The tests that pinned review fixes were retired with the rest: the `.z7` list, the probe's
     mixed-head case, and run state saved before cleanup.
3. **The new probe row states policy, not mechanism.** LLR-162 says only "bounded deterministic
   sample offsets" with a 256 KiB floor and a 10% saving threshold. It names no window placement,
   no measuring codec, no extension list and no log line. Rust's 7-Zip probe with three windows
   at start, middle and end therefore complies with it.

**The probe-placement defect was not dropped by the port.** Its fix, WP18, was never approved or
started (`docs/status.md:6158`, "NOT approved and NOT started"). The migration plan told Rust to
"preserve the existing compression-probe policy" (`docs/plans/rust-migration.md:173-174`). The
2026-09-07 corpus study that superseded WP18's premise never reached `status.md` or the Owner at
all [read: no status entry mentions it].

**The same mechanism explains the 2026-11-06 progress regression.** The requirement asked only
for "progress … at intervals of no more than two minutes". Rust met it with a bare
`Backup still active` line, and the hub found the gap (commit `e3f7fe7`, which added the
progress requirements SR-159 and LLR-191).

**What did get through** is what a requirement states as an outcome:

- content-addressed dedup;
- hidden and dot files;
- the store lock and clean-up after a killed run;
- verification after restore;
- memory and time budgets;
- progress lines, after the repair.

**What did not** is what lived only in mechanism:

- probe placement;
- the extension list;
- "list the folder once, don't check each row";
- the local temporary area for files probably already stored;
- the decision log and counters;
- the checkpoint throttle.

---

## 4. The seven defect reviews, item by item

### 4.1 Mirror-layout deduplication, 2026-08-24 (`docs/defect-review-2026-08-24-mirror-dedup.md`)

The old mirror layout could point a manifest row at a file another path later overwrote. Fixed by
deleting the layout: all storage became content-addressed (WP9).

| Finding | PowerShell | Rust | Cost |
|---|---|---|---|
| D-1 / D-5: a stale reference across paths; duplicates within one run | Fixed by WP9 [read] | Carried: content-addressed pool, written into requirement SR-003 [read] | None |
| D-2: restore trusted a stored file's path without hashing it | Fixed in kit revision 6 [read] | Impossible by construction: the native kit verifies every candidate before using it [read] | None |
| D-3: some restore failures got the wrong exit code | Fixed in kit revision 6 [read] | Gone in its old form. A different set of misclassifications appears in the native kit (§7.4) | Wrong exit code, never wrong bytes |
| D-4: hidden and dot files were never backed up | Fixed [read] | Carried (requirement SR-001) [read] | None |

### 4.2 Compressibility by extension, 2026-08-31 (`docs/defect-review-2026-08-31-compressibility-by-extension.md`)

The first production run spent days compressing already-compressed archives. The extension list
of "do not compress" types lacked `.z7`, which is 43% of the library (880.6 GB in 649 files).

| Finding | PowerShell | Rust | Cost on the hub |
|---|---|---|---|
| C-1: `.z7` missing from the list | Fixed, `deb0d65` (WP17 Part A, 12 extensions added) [read] | **Not carried.** Rust has its own 16-entry list (`engine.rs:396-399`). It lacks `.z7`, `.mov`, `.avi`, `.mpg`, `.m2ts`, `.m4v`, `.heic`, `.opus`, `.m4a`, `.gif` and others. It adds `.pdf`, which PowerShell deliberately left off [read] | About none under the default probe mode `always`, because the probe catches `.z7` [estimate]. Under `off` or `excluded-extensions`, the nine-day `.z7` defect returns |
| C-2: 7-Zip saves space, not time | Answered by the measured probe (WP17 Part B) | Same | — |
| C-3: HomeHub's own list also lacks `.z7` | Outside this repo | n/a | Not checked |
| Option B, measure instead of trusting the name | Built: `5795391`, `03e628e`, `7764596` [read] | Carried in shape, measured differently (§7.1) [read] | See §7.1 |
| Option C, measure while hashing | Deferred | Not built | Now nearly free: both engines copy and hash each new file just before probing it [estimate] |
| Option D, a size gate | Rejected | Not built (by decision) | — |
| `FILEBACKUP_7Z_LEVEL` (7-Zip level setting, default 9) | Shipped, `710bd4b` [read] | **Ignored**: hard-coded `-mx=5 -mmt=2` (`tools.rs:321-323`) [read] | Matches the hub's setting of 5 by coincidence |

### 4.3 Run observability, 2026-08-31 (`docs/defect-review-2026-08-31-run-observability.md`)

A run was silent for hours and nobody could tell whether it was alive or what it was doing.

| Finding | PowerShell | Rust | Cost on the hub |
|---|---|---|---|
| O-1: long phases silent | Mostly fixed by the 2026-10-24 rewrite: a `Progress:` line every 60 s and a line per stored object. The check runs between files, so one 20 GB file is still silent [read] | Partly. A timer line every 60 s since `e3f7fe7`, including the walk and indexing. No per-object lines, and the counts freeze during compression and read-back [read] | The Owner could see "alive" but never "compressing X" |
| O-2: no side channel showing progress | The manifest checkpoint every ~60 s [read] | Same [read] | Low |
| O-3: log detail cannot be raised | Not built; everything, DEBUG included, is always written [read] | No levels and no detail lines to raise [read] | Nothing explains a slow run |
| O-4: global log empty during a run | Resolved by design [read] | Different design: one JSON line per run in `StorePath/backup.log`, with **no timestamp** [read] | Rust's run history cannot be dated from the log |
| WP16, the observability plan (phase banners, a heartbeat naming the current file, a `RUN.status.json` file, a run id, a log-level setting) | **Never approved** ("PROPOSED — awaiting Owner approval", `wp16-run-observability-plan.md:17`). Built only partly, by another route [read] | Not built. The new progress requirement SR-159 forbids file paths in the progress line, reversing the review's advice [read] | — |

### 4.4 Stale `Temp` lock, 2026-08-31 (`docs/defect-review-2026-08-31-stale-temp-lock.md`)

A killed run left a `Temp` folder and every later run refused to start.

| Finding | PowerShell | Rust | Cost on the hub |
|---|---|---|---|
| A killed run blocks every later backup | Fixed for backup: leftover files deleted at start, and one OS-held lock file (WP14 was built and then replaced by the bounded run loop's ruling R2) [read] | Carried, more narrowly: only known names are deleted, and anything else is kept with a warning (`store.rs:195-270`) [read] | None |
| The lock never measured on Linux, in the container or over ntfs-3g | Windows evidence only (`docs/status.md:342-345`) [read] | Carried as `flock`. One in-process test, which Linux CI also runs [read] | It is the only guard against two writers, and it has never been shown to exclude anything on the hub [estimate] |
| A killed prune blocks later prunes | Not fixed: a leftover `Temp` needs a person [read] | Worse: a kill after the prune's plan file is written makes **backups** refuse with exit 2 until the same prune runs again (`engine.rs:813-819`) [read] | The hub does not prune today. This matters once retention is switched on |

### 4.5 Probe sample representativeness, 2026-09-02 ([review](defect-review-2026-09-02-probe-sample-representativeness.md))

This is the defect that stopped the 2026-11-07 run. The probe measures windows at the start, the
middle and the end of a file. Video containers keep compressible headers and padding at both ends,
so the average says "compressible" while the content is not. On the PowerShell engine's first
production pass, 4.56 h of the first 8 h went on compressing, to save 1.88 GiB.

| Finding | PowerShell | Rust | Cost on the hub |
|---|---|---|---|
| P-1: windows at the start and end of the file | Not fixed (`Engine.psm1:3884, 4015-4024`) [read] | Not fixed (`engine.rs:405-415`) [read] | e.g. ROTJ about 2.3 h for about 1.5% [estimate] |
| P-2: the average overrides a middle window that says "incompressible" | Not fixed [read] | Not fixed. Rust compresses the three windows together, so it has no per-window ratios at all (`engine.rs:406-436`) [read] | About 31 of 52 hours of 7-Zip time avoidable for about 6.5 GiB forgone (corpus §6a at 2.4 MiB/s) [estimate] |
| P-3: the cost sits in a few huge files | Not fixed | Not fixed | as P-1 |
| P-4: start and middle windows incompressible but the tail compressible (pattern `1, 1, 0.x`) gives nothing | Not fixed | Cannot even be detected (no window ratios) | About 32 GiB of such files compressed for nothing (corpus §4a) [read] |
| P-5: the probe must stay cheap | Honoured: Brotli, about 90 ms a probe [read] | **Regressed**: see §7.1 | About 5-7 h a first pass [estimate] |
| Options A-D and the review's recommendation | Not built | Not built | — |
| WP18 (window count grows with file size: 9 windows at 1 GiB, 13 at 20 GiB) | DRAFT, never approved (`docs/status.md:6158`) [read] | Not built | — |
| The 2026-09-07 corpus rule (§5 below) | Not built, never put to the Owner [read] | Not built | — |

**The three hub files under the 2026-09-07 rule** ("store raw when the median window ratio is
above 0.95, or the middle window is 0.98 or more"), using today's three windows [read]:

| File | Windows (start / middle / end) | Median | Rule says | Right answer |
|---|---|---|---|---|
| ESB AVCHD `.iso`, 8.43 GB | 0.003 / 0.963 / 0.017 | 0.017 | compress | raw (realised 0.934). **The rule fails here**: padding at both ends makes the median a padding window, and the middle sits between 0.95 and 0.98 |
| ROTJ `.mkv`, 20.6 GB | 0.59 / 0.985 / 0.55 | 0.59 | raw, saving about 2.3 h | raw |
| ESB `.mkv`, 21.2 GB (sparse) | 0.56 / 0.001 / 0.001 | 0.001 | compress | compress (zeros) |

With windows at 25/50/75% of the file instead of 0/50/100, ROTJ and ESB likely decide the same.
The ISO is unknown, because interior windows were never measured on it [estimate].

The ESB file matches a 2026-09-07 corpus row by size (21,165,363,450 B, windows `0.586, 0, 0`,
realised 0.430). If it is the same file, **its zero tail already existed in September**, which
bears on the Owner's question about whether the source was always incomplete [estimate: matched
by size only].

### 4.6 `Optimize-ChangeFolders` file-check storm, 2026-09-06 (`docs/defect-review-2026-09-06-optimize-changefolders-stat-storm.md`)

Through ntfs-3g each file-existence check cost about 10 ms. The old engine checked one stored
file per manifest row, for 51 of a 108-minute night. The 10 ms figure was measured on the old
flat layout. The store is now split into two-character sub-folders, so today's cost per check is
unknown.

| Finding | PowerShell | Rust | Cost on the hub |
|---|---|---|---|
| C-1: one check per manifest row | Fixed: answered from one folder listing (`Engine.psm1:754, 888`) [read] | **Back**: `usable()` checks each unchanged row's stored object every night, and opens compressed ones to read 6 bytes (`engine.rs:354-358`, `tools.rs:364-371`) [read] | About 180,000 extra checks a night: 3-30 min [estimate] |
| C-2: list once instead of checking each | Fixed [read] | Partly: two checks per object while building the index (`store.rs:159-173`) [read] | About 320,000 checks per index build [estimate] |
| C-4 / C-7: the listing rebuilt instead of reused | Fixed [read] | **Back**: the store is indexed at the start (`engine.rs:876`), dropped, then indexed again to move superseded content (`engine.rs:768-800`) [read] | About 320,000 more checks a night [estimate] |
| C-5: duplicate rows check the same object again | Fixed [read] | Back, in `usable()` and in quick verify [read] | Small |
| C-6: unused objects never reclaimed | Partly moot; nothing deletes a true orphan [read] | Same, and Rust never reports one either [read] | Space only |
| C-8: the source walked twice | **Not fixed.** A second recursive directory walk remains (`Get-SourceDirectoryRecord`, `Engine.psm1:657`, called at `:7143`). HomeHub's 2026-10-26 audit calls it fixed, which is wrong [read] | Fixed: one walk (`engine.rs:131`) [read] | PowerShell about 9 min a night (measured 2026-09-06) |
| C-9 / C-10: slow object writes, slow snapshot finish | Never diagnosed [read] | Every capture flushes and checks free space; cost on ntfs-3g unknown [read] | Unknown |
| C-11: deep verify gives no progress | **Not fixed** [read] | Fixed by `e3f7fe7` [read] | — |
| C-12: deep verify fails good data when the RAM disk fills | Fixed: scratch on the backup drive [read] | Designed away: 7-Zip output streams straight into the hasher (`tools.rs:420-433`) [read] | — |

### 4.7 Content-index memory, 2026-10-05 (`docs/defect-review-2026-10-05-content-index-memory.md`)

The engine held every snapshot's manifest in memory at once, 6.6 GB on the hub, and ran out of
memory.

| Finding | PowerShell | Rust | Cost on the hub |
|---|---|---|---|
| Fix 1: the backup's index keeps every manifest | Fixed (`1ecbd05`, then `15ed359` removed the option entirely) [read] | Designed away: the index is built from folder listings only (`store.rs:136`) [read] | None |
| Fix 2, prune half ("prune fix 2"): prune holds every manifest | **Fixed** by `15ed359` and `8512ed2` (2026-10-27). HomeHub's queue and audit predate this and still list it open [read] | One manifest at a time (`maintenance.rs:485-507`) [read] | PowerShell peak about one manifest (about 420 MB) [estimate]. But see item 7 in §1 for a new Rust prune cost |
| Verify holds every manifest | Fixed by `15ed359` [read] | One at a time [read] | None |
| Fix 3: save run state earlier | Fixed [read] | Fixed: state written right after the final manifest (`engine.rs:1096`) [read] | None |
| Fix 4: a memory test | Built (three tests, the largest with 30 × 180,000 rows) [read] | Measured once (973 MB for a million files), but no test enforces it [read] | A regression would go unnoticed |
| An unchanged night writes and then deletes a whole snapshot | **Not fixed** (`Engine.psm1:7279-7300`) [read] | Same, and Rust also writes and deletes a `.prev` copy of the manifest and directory record (`engine.rs:867-874, 1103-1118`) [read] | About two 37 MB manifests plus a kit written, flushed and deleted every unchanged night [estimate] |
| Quick verify checks each row of every state | Same pattern [read] | Same: one check per row per state (`maintenance.rs:184`) [read] | 30 nights of history: about 5.5 million checks [estimate]. Never measured |

---

## 5. Plans never approved or never started

| Plan | Status | What it would fix | Built? |
|---|---|---|---|
| WP18, probe window geometry ([plan](plans/wp18-probe-window-geometry-plan.md)) | "DRAFT, pre-gate. Not approved, not started" | §4.5. The window count grows with file size: `clamp(3, 24, 3 + floor(log2(size / 16 MiB)))` | Neither engine |
| The 2026-09-07 corpus findings ([probe-sampling-corpus-2026-09-07.md](probe-sampling-corpus-2026-09-07.md), `experiments/probe-window-*.py`, commits `e7afc1b`, `9b5eaff`, `e3042bc`) | An experiment record. **No status entry, never put to the Owner** | Measured on 166 real files, as correlation with the real outcome: the start window +0.06 (noise), today's start/middle/end +0.65, the middle window alone +0.80, windows at 25/50/75% +0.89. Gains stop at about 9 windows. Its rule ("raw when the median is above 0.95 or the middle is 0.98 or more") avoids 60% of 7-Zip's input | Neither |
| WP16, run observability (`plans/wp16-run-observability-plan.md`) | "PROPOSED — awaiting Owner approval" | §4.3: phase banners, the current file in the heartbeat, a `RUN.status.json`, a log-level setting | PowerShell: progress lines only, by another route. Rust: progress lines only |
| WP14, stale lock (`plans/wp14-stale-temp-lock-recovery-plan.md`) | Header still says PROPOSED, but it was carried out (`docs/status.md:599-621`) | §4.4 | Yes, later replaced by the OS lock |
| Killed-staging recovery design (`plans/killed-staging-recovery-design-2026-10-09.md`) | Design only | Recover a killed run's `Temp` without a person | Replaced by the bounded run loop's clean-up; Rust has the equivalent |
| WP3, WP4, WP9 | Historical "Drafted"; the WP1-WP9 queue is recorded complete (`docs/status.md:953`) | Container release, retention, content-addressed storage | Yes. Not ported to Rust: WP9's browse view as a TSV plus one page per folder (§7.5) |

**WP18's open questions (its §7), none ruled:**

1. Should a hub experiment gate the code change, or run beside it? Without one, the change ships
   on the review's arithmetic, not on measured interior windows.
2. The formula's three constants (base 16 MiB, floor 3, ceiling 24) come from the review, not
   from measurement. Are they acceptable?
3. Is about 37 minutes of extra probing per full run acceptable for the roughly 27 hours it
   recovers? That probe cost is seven times the review's own figure, so it needs an explicit
   ruling.
4. The work-package number (WP18 was assumed).

The 2026-09-07 corpus undercuts WP18's premise: it says to stop sampling the start and the end,
while WP18 keeps both and adds more windows between them. WP18 was never revised. Step 2 of the
brief brings this choice to the Owner.

---

## 6. The Owner's queue

The queue was recorded in HomeHub (`FOLLOWUPS.md` ~4560, 2026-10-09) and re-checked by HomeHub's
read-only audit of 2026-10-26 (`docs/FILEBACKUP_BOUNDEDREBUILD_AUDIT_2026-10-26.md`). Several of
that audit's rows are now out of date.

| Item | What it is | PowerShell now | Rust | Cost on the hub |
|---|---|---|---|---|
| Split staging recovery | Recover a killed run's staging folder automatically (design step 3) | **Not built, by ruling**: the bounded run loop's rulings R1 and R2 say a killed run gets a warning and the next run deletes the leftovers, never a recovery path [read] | Not needed: same model, `store.rs:195-270` [read] | None |
| Prune fix 2 | Prune holds every manifest in memory | **Fixed** 2026-10-27 (`15ed359`, `8512ed2`); the queue predates it [read] | One manifest at a time [read] | None for memory. Rust adds a whole-library read per prune (§7.3) |
| Step-10 `.fbwrite.tmp` hardening | A kill during a copy could leave a torn object under its final name | **Fixed by design**: copy into `Incoming`, flush, then rename [read] | Carried: the same order (`engine.rs:486-488, 594-599`) [read] | None |
| Reconstruct's torn-`.7z` fallback | A stored archive that fails to open is reported as a host failure (exit 4, "retry later"), and a good copy elsewhere is never tried | **Not fixed, by ruling**: Owner ruling C40 (2026-10-27, `87f6554`) confirmed the exit 4 [read] | **Reversed without a ruling**: the native kit tries every copy, then exits 1 (`recovery/Reconstruct.ps1:313-332`, `recovery/reconstruct.sh:222-249`). This matches the native interface draft IF-007 [read] | PowerShell-era kits: a damaged archive with a good twin reports "retry" and is not restored. Native: correct, but the ruling record is now contradicted |
| P2, atomic witness | The old witness file was replaced by delete-then-move | Moot: nothing writes a witness any more [read] | No witness [read] | None |
| Per-row check in `Complete-ChangeFolder` | One file check per row when finishing | Moot: the function is gone [read] | **The same pattern is back** in `usable()` (§4.6 C-1) [read] | See §4.6 |
| The OS lock on Linux and in the container | The lock was proven on Windows only | Still Windows-only evidence [read] | `flock`; one in-process test on Linux CI [read] | Never shown to exclude a second writer on the hub [estimate] |
| A killed prune leaves `Temp` | Later prunes refuse until a person acts | Not fixed [read] | Worse: backups refuse with exit 2 (§4.4) [read] | Once retention is switched on |
| No periodic check of stored objects | A wrong-bytes object is caught only by a deep verify | Not built (ruling R10) [read] | Same; a deduplication match does check the matched object in full [read] | Damaged objects are reused until a deep verify [estimate] |
| The two restorers disagree on symbolic links | Listed "not fixed" in HomeHub's audit | **Fixed** 2026-08-28 (`d302899`), HomeHub's row is wrong. A narrow gap remains on the PowerShell side: only the deepest existing folder's own link is resolved [read code; the gap is an estimate] | Refuses any link anywhere in the paths; both native kits agree [read] | Low |
| `interfaces.md` names the wrong launcher | Documentation nit | Moot: that interface table was retired [read] | n/a | None |
| Rebuild the hub image | — | — | — | The Owner's call (brief, Constraints) |

---

## 7. Gaps between the ports, and new Rust behaviour

Items not tied to a defect review. **Deliberate changes approved through the requirements** are
listed separately in §7.6, so they are not mistaken for defects.

### 7.1 Probe and compression

All [read] unless marked.

- **Window placement:** identical in both engines: three windows at the start, the middle and
  the end. Below 768 KiB the whole file is one sample.
- **Measuring codec:** PowerShell compressed each window with Brotli at its fastest setting into
  a byte counter in memory. Rust joins the three windows into one temporary file in `Incoming`,
  runs `7zz -mx=5 -mmt=2` on it, and flushes the result (`engine.rs:406-436`, `tools.rs:335`).
  The cost is a process start plus writes on the backup disk for every probed file: about 0.3 s
  against about 90 ms [estimate]. Rust has **no per-window ratios**, so the median and middle
  rules need the measurement itself rewritten.
- **Requirement:** the Brotli requirement (LLR-086) was retired on 2026-11-06
  (`docs/log.d/retired/LLR-086.md`). The live LLR-162 names no codec, so the 7-Zip probe
  complies. The brief calls this a deviation from the requirement; it is a deviation from the
  retired one.
- **Threshold, modes, floor:** both compress at a measured size of 90% or less. Both honour the
  modes `off`, `excluded-extensions` and `always` (default `always`). PowerShell probes files of
  256 KiB or more; Rust only files above 256 KiB, which matches requirement SR-081.
- **When the probe runs:** both probe the staged copy, after the whole file has been copied into
  `Incoming` (`engine.rs:486-559`, `Engine.psm1:5656-5658`). Neither handles sparse files, so
  the ESB file's zeros are written out in full before any decision. PowerShell only began staging
  first on 2026-10-24 (`71fe963`). Both defect reviews measured the earlier pipeline, which
  probed and compressed straight from the source.
- **Read-back check:** only Rust does it. After compressing, it lists and fully expands the
  archive and hashes the output (`tools.rs:380-444`). No requirement asks for it; it is a design
  choice (`implementation-workorder.md:154`). On a 20 GB video it adds a full expand, and the
  progress count does not move during it.
- **Level and threads:** PowerShell used the `FILEBACKUP_7Z_LEVEL` setting (default 9; the hub
  ran 5) and 7-Zip's default thread count. Rust is fixed at level 5 with 2 threads, a baseline
  the Owner requested (`embedded-codec-2026-11-06.md`).
- **The 7-Zip deadline:** Rust allows `300 s + 1 s per MiB` (`tools.rs:349-351`). Running past
  it is a host stop, which **ends the whole run with exit 4**. That deadline implies a floor of
  about 1 MiB/s. The hub measured 2.4 MiB/s on two cores, so a busier night or a less
  compressible file can come close.
- **Probe failure:** both fall back to the extension list. PowerShell logs a WARN. Rust adds a
  plain message to the report that the run's finding count does not include (`engine.rs:440`).
- **An archive as large as its content:** PowerShell stores such a file raw (`Engine.psm1:5515`).
  Rust does not; its workorder forbids overriding the decision on final size. The case is rare.
- **Tests:** Rust's only probe test uses files of about 300 KiB, so the three-window path, where
  every one of these defects lives, is untested.

### 7.2 Observability (PowerShell has it, Rust does not)

| What | PowerShell | Rust | Who relies on it |
|---|---|---|---|
| `compress-decision: <file> <reason> ratio=… windows=w1,w2,w3 -> <object>`, one line per stored object | `Engine.psm1:5572` | Absent | The Owner, to see why a file was compressed |
| `Probe stored raw / compressed / reads` counters | `Engine.psm1:4342-4344` | Absent | — |
| `Stored object …` lines | `Engine.psm1:5570` | Absent | — |
| `Timings:`, `Work:` (compress count, bytes in and out, MB/s), `Slowest files:`, a `metrics {…}` JSON line | `Engine.psm1:6650-6715` | Absent. The report holds counts and one elapsed time. A killed run leaves nothing | Nobody parses them today; the loss is diagnosis |
| Start and end banners, the re-read decision, `Indexed N objects`, snapshot kept or dropped, object moved back, checkpoint saved | `Engine.psm1:6815, 6027, 6079, 5800, 7018, 7254, 7273, 7331` | Absent | — |
| A timestamp on every log line | Every line | Absent from `backup.log` and from the progress lines | Rust's run history cannot be dated |
| The `[DamagedObject]` warning token | `Engine.psm1:2340` | A plain JSON message | The PowerShell-era hub wrapper searched for this token. HomeHub's native readiness record says the wrapper was adapted, but the wrapper itself (MiniPC-Deployer) was not read here |
| Mail | The subject says the outcome; the body lists the log paths | A fixed subject, "FileBackup run result", with counts only (`notify.rs:74-94`) | — |
| Verify's elapsed time | Logged | Always 0: only backup sets it (`engine.rs:635`) | — |
| The progress counter during compression and read-back | n/a, PowerShell is silent within a file | Frozen: bytes are counted only while the source is copied. A counting version of the read-back check (`verify_form_counted`) already exists and deep verify uses it, but the capture path passes an empty counter | The Owner. HomeHub's runbook calls a still counter for "10 minutes or more" normal (`FOLLOWUPS.md:66-68`); on the real library it was hours |

`README.md:117-135` still describes `Timings:`, `Work:`, `Slowest files:` and `metrics` as
current behaviour. None of it is true for the Rust engine the hub runs.

### 7.3 Disk work per file

All [read] unless marked.

- **No local temporary area.** PowerShell hashes a file that is probably already stored on the
  host, or in place if it is large, and writes nothing to the backup disk unless the content
  turns out to be new (`Engine.psm1:5640-5672`). Rust copies every file it captures in full into
  `Incoming` on the backup disk, then checks the index. A match then reads the stored copy in
  full, expanding an archive (`engine.rs:484-543`). A moved 20 GB folder costs about 20 GB
  written plus 20 GB read and expanded, where PowerShell costs no store I/O [estimate].
- **Checks per unchanged night.**
  - Rust: three checks of each source file, one of each row's stored object, and two of each
    stored object per index build, with two builds per night. That totals about 1.37 million
    round trips through ntfs-3g.
  - PowerShell: about 0.35-0.5 million, plus its second directory walk.
  - At 10 ms a check that is about 3.8 h against 1.4 h; at 1 ms, about 23 min against 9 min.
    Both are [estimate], and nobody has measured the sharded layout.
- **Checkpoint frequency.** PowerShell rewrites the manifest only when rows changed, and no more
  often than ten times the last write's duration (`Engine.psm1:7010-7017`). Rust rewrites it every
  60 s after any file. Over a multi-day first pass, with the manifest growing towards about 40 MB,
  that is tens of GB of manifest writes, each flushed [estimate].
- **Prune reads the library.** To prove that the states it keeps still have their content, Rust
  prune fully hashes, or expands, one surviving copy of every object those states need. It does
  this on every prune, dry run included (`maintenance.rs:519-532`). PowerShell hashes only the
  copies it moves.

### 7.4 Restore kits

The native kit in `recovery/` (revision 17) is a rewrite, not a port. It finds content by
`(hash, length)` alone, tries every candidate copy, verifies the bytes before renaming them into
place, and has no fallback scan of file contents. It restores native stores only, by design
(`docs/native-support.md:58-60`). All rows [read] unless marked.

| Behaviour | PowerShell-era kit (revision 16) | Native kit (revision 17) | Cost |
|---|---|---|---|
| A manifest with NUL bytes, from a write cut short by power loss | Restores every row before the damage and exits 1 or more | **Restores nothing, exits 2** (`recovery/Reconstruct.ps1:93`, `recovery/reconstruct.sh:93-108`) | The objects are in the store, but the kit will not read the manifest. Only the `.prev` copy remains as a fallback |
| Not enough space at the target | Exit 2; counts uncompressed rows only | Exit 4; counts all bytes | The exit code differs between kit generations |
| Exit-code edge cases | One table, both kits agree | The two native kits disagree: a write failure at the target inside the candidate loop is exit 1 in PowerShell and 4 in bash; an unreadable store folder is skipped silently by bash (exit 1) and is 4 in PowerShell. A timeout followed by a later success still exits 4 (`recovery/Reconstruct.ps1:253, 325-326`; `recovery/reconstruct.sh:150-161, 212-226`) | Wrong exit code, never wrong bytes |
| `DIRECTORIES.csv` (empty and hidden folders) | Advisory; missing means old behaviour | Required: missing, or a PowerShell-era file, gives exit 1 | By design |
| Folder names in root detection | Compared the way the host compares them | PowerShell kit compares case-sensitively on Windows (`-ceq`); a differently cased path is refused with 2 [estimate] | Usability only |
| Per-file timestamps | Applied | Applied. Rust writes 9 fractional digits, and whether .NET parses that is unverified; a failure only warns | Low |
| A stored object not at its canonical name or place | Found by a content scan | Not found (exit 1) | Low for native stores [estimate] |

AGENTS.md §3 still says "Bump to 16 for the next behaviour change" and never mentions revision 17.

### 7.5 Commands, configuration and outcomes

All [read] unless marked.

- **Environment variables.**
  - PowerShell and its container honour `FILEBACKUP_7ZIP_PATH`, `FILEBACKUP_FFPROBE_PATH`,
    `FILEBACKUP_7Z_LEVEL`, `FILEBACKUP_LOG_PATH`, and in the container `FILEBACKUP_ACTION`,
    `FILEBACKUP_SNAPSHOT`, `FILEBACKUP_DRY_RUN` and `FILEBACKUP_REPAIR` (`FileBackup.ps1:182-206`,
    `container/entrypoint.sh`).
  - Rust reads none of them and does not warn. `container/native.entrypoint.sh` only adds
    `--config`, so an action passed by variable runs a backup instead.
  - This contradicts the workorder's own rule (`implementation-workorder.md:33-34`): "refuses
    unsupported features/configuration explicitly rather than silently ignoring a setting".
- **A file deleted during the run.** PowerShell drops its row as a removal
  (`Engine.psm1:5623, 7008`). Rust retries it after 1 s and 5 s, then reports "Capture failed;
  prior row retained" with exit 1 and keeps the old row until the next run (`engine.rs:985-1001`).
  On a multi-day first pass any file the user deletes turns the run's outcome into a failure.
- **Exit codes for a missing source root or a missing tool:** 2 in PowerShell ("a person must
  act"), 4 in Rust ("retry later") (`engine.rs:808-811, 826-829`).
- **An unplugged store drive on Windows:** PowerShell refuses that set with 4 and runs the others.
  Rust refuses every set with 2 at configuration admission [estimate]. This does not affect the
  Linux hub.
- **Verify options.** There is no "latest state only" pass, and repair always requires a full deep
  read (`main.rs:31`). Repair has no dry run.
- **Configuration keys.** `AllowEmptySource` and `SourceStatePath`, which PowerShell accepts and
  ignores, are refused (exit 2). A lowercase `HashRecalcFreq` is refused.
- **Browse view.** PowerShell writes a searchable `INDEX.tsv` plus one page per folder, and above
  50,000 rows points to the TSV. Rust writes one `index.html` holding every row and no TSV
  (`maintenance.rs:655-730`). On the hub that is one page of about 180,000 rows rebuilt after
  every run, if the view is switched on, which was not checked.
- **Snapshot inventory:** Rust reports logical counts only, with no dedup-aware reclaim figures.
- **Prune** takes repeated `--snapshot` flags with cutoff meaning; the PowerShell comma list is
  refused.

### 7.6 Deliberate changes, approved through the requirements (listed so they are not taken for defects)

- **The prune recovery window.** Rust prune protects only the latest state, states newer than the
  cutoff, and the `.prev` copy. It states "Older unselected states may become unrestorable"
  (`maintenance.rs:582`). This follows the approved need on the recovery window
  (`docs/requirements/stakeholder-needs.toml:108`, approved 2026-11-05). PowerShell proved that
  every surviving row still resolved.
- **Retry spacing:** waits of 1 s then 5 s, with 60 s in all per set, instead of 60 s between
  attempts (requirements SR-090 and LLR-160).
- **The re-read schedule** runs on elapsed time since the last re-read, not on calendar weeks, so
  a weekly re-read falls about every 8 days (SR-011, LLR-158).
- **Old stores are refused.** A new, empty store is required (`docs/native-usage.md:4-7`); the hub
  already has one.

---

## 8. Corrections to earlier records

- **The brief swaps two line references:** the `compress-decision:` line is at
  `Engine.psm1:5572` and the probe counters at `:4342-4344`.
- **The brief calls the 7-Zip probe a deviation from the requirement.** The Brotli requirement
  (LLR-086) was retired on 2026-11-06; the live LLR-162 permits the 7-Zip probe (§7.1).
- **Stale rows in HomeHub's 2026-10-26 audit:**
  - "Prune holds every manifest" and "Verify holds every manifest" were fixed the day after
    (`15ed359`, `8512ed2`).
  - "The two restorers disagree on symlinks" was fixed on 2026-08-28 (`d302899`).
  - "Source walked twice: Fixed" is wrong: PowerShell still walks the directories a second time
    (§4.6 C-8).
  - "Torn-`.7z` fallback: not fixed" is right for the PowerShell-era kits, but by ruling C40,
    which that audit did not cite.
- **AGENTS.md §3** describes kit revision 16 as current; the native kit is revision 17.
- **README.md:117-135** describes PowerShell log lines as current behaviour (§7.2).

---

## 9. What this audit did not establish

- **Nothing on the hub:** the checkpoint's actual time and row count, what is in
  `archive-AJ18zx`, whether a `7zz` is still running, the deployed `HashRecalcFreq`, free space,
  and whether the browse view or mail are on. §2 lists read-only checks.
- **No measured Rust figure through ntfs-3g.** Every hub time in §4.6 and §7.3 is arithmetic from
  the 10 ms per check measured in September on the old flat layout.
- **The probe hour figures** (the 31 of 52 hours, and the 5-7 h of probing) are arithmetic from
  2.4 MiB/s and the 2026-09-07 corpus. The hub files were matched to corpus rows by size only.
- **Interior window ratios** for the three hub files were never measured.
- **How MiniPC-Deployer's `library-backup.sh` drives the Rust image:** which variables it passes,
  and how it parses the output. It was not read.
- **No test, build or kit was run.** Kit edge cases are read from the code.
