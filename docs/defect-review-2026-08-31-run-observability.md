# Review — a long run emits nothing, and "working" is indistinguishable from "dead"

**Found:** 2026-08-31, on the real HomeHub production hub (Ubuntu, `filebackup:local`
container, real 4 TB library / 8 TB backup drives), during the **first whole-library
pass this product has ever completed against production disks** — 2.1 TB, `LastHashRun=`
empty, so every file is hashed.

**This is a companion document, not an edit.** It is filed separately from
`defect-review-2026-08-31-stale-temp-lock.md` because that review is under active
cross-referenced review in another session; **nothing here modifies it, and it can be
read and ruled on independently.** The two are related in one specific way, stated in §3:
the stale-lock defect cost ~18 hours *because* of what this document describes, and any
"make it visible" option there depends on there being something to make visible.

**Nothing here is a defect against a stated requirement.** `docs/requirements/` contains
no progress, observability, or heartbeat requirement — searched. So this is a **new ask
with evidence**, not a regression, and it may legitimately be ruled "working as
intended, and that is acceptable." It is written up because the evidence was gathered
live and will be expensive to reproduce: the bench box is gone and this is a first-run
condition that, by definition, happens once.

**Severity:** operability. No data is lost or corrupted by anything here.

---

## Summary

| | Finding | One line |
|---|---|---|
| **O-1** | The two longest phases emit **nothing** | Step 5 (hash the whole source) logs one line on entry and nothing after. Step 10 (copy) logs nothing per file or per group. On a 2.1 TB first pass that is hours of total silence. |
| **O-2** | **No side channel works either** | The obvious external proxies — the state folder growing, the store growing — do **not** move during step 5. The only signal that the run is alive at all is container CPU/block-IO. |
| **O-3** | Verbosity cannot be turned up | `New-Logger` applies **no level filter** — there is no quiet/verbose knob to raise. The whole engine has **15 `INFO` call sites**; there is no more detail available at any setting. |
| **O-4** | The log the guard names is empty *(mechanism unconfirmed)* | `Backup_Global.log` — the file the stale-`Temp` error tells the operator to read — was **0 bytes** while the run was mid-flight. The lines exist in `ChangePath/backup.log` instead. Reported as an observation; see §6. |

---

> **Corrected 2026-08-31 by the §8 cross-review:** O-1 is **half-withdrawn** — step 10
> does emit one line per stored physical object; step 5's silence stands and is the core
> finding. The §2 census was undercounted. O-4 is **resolved as working-as-designed**;
> what remains of it is a one-line README pointer, carried in WP14 Part D as N-3.

## 1. The measurement

A single uninterrupted observation of the live production run:

| clock | event |
|---|---|
| 09:25:26 | wrapper preflight (capacity, write-probes, drive spin-up) — 14 lines |
| 09:25:29.364 | `----- Backup set 'library' starting -----` |
| 09:25:29.429 | `HashRecalcFreq=W, LastHashRun=, Recalculate=True` |
| 09:25:29.435 | `Updating source manifest cache at '/state'.` |
| 09:30:40 | **silent** — 3 container lines total, none since 09:25:29 |
| 09:31:19 | **silent** — set log still 228 bytes, mtime still 09:25 |

**Five and a half minutes of total silence at the point of observation, on a run whose
hashing phase alone is expected to take hours.** The third line is, as far as an operator
can tell, the last thing the product will ever say.

### What the side channels showed at 09:30:40–09:31:19

| probe | value | usable as progress? |
|---|---|---|
| `du -sh /var/lib/homehub-filebackup/state` | **12 K** — unchanged from before the run started | **No.** The manifest is not flushed incrementally; the folder does not grow during hashing. |
| `du -sh /mnt/backup-drive/library` | **0** | **No** — stays 0 until step 10 begins. Useful only as a phase-boundary edge, not progress. |
| `ChangePath/backup.log` size / mtime | 228 bytes, mtime 09:25 | **No** — frozen with the log. |
| `Backup_Global.log` | **0 bytes** | **No.** See O-4. |
| `docker stats` on the run container | **38.82% CPU, 762 MiB, 43.1 MB block-IO** | **Liveness only** — proves it is alive, says nothing about how far along. |

**This is the finding that matters most, and it is why O-1 is not merely cosmetic.**
I went looking for an external proxy so the operator would have *something*, and the
obvious one does not work: **the state folder does not grow while the source is being
hashed.** The only thing distinguishing "hashing 2.1 TB" from "hung on a dead NFS
handle" is container CPU — which requires host-level access, knowing to look, and
knowing what number is normal.

---

## 2. Where it is in the code

**Step 5 — the hashing phase.** The one line is emitted by the *caller*, before entry
(`Modules/FileBackup.Engine.psm1:3979`):

```powershell
& $log "Updating source manifest cache at '$($paths.SrcStatePath)'."
```

`Update-SourceManifest` itself contains **no log calls at all** — it walks and hashes the
entire source with no emission. Everything it will ever say has already been said before
it starts.

**Step 10 — the copy phase** (`:4133-4141`). The loop over hash groups calls
`Invoke-BackupFileGroup` per group and logs nothing per group or per file. Only problems
speak — `WARN` on a retry, `ERROR` on a failure. **A perfectly healthy copy of 2.1 TB is
silent by construction.**

**Total log surface of the engine**, by level:

| level | call sites |
|---|---|
| `ERROR` | 17 |
| `WARN` | 16 |
| `INFO` | **15** |
| `DEBUG` | 3 |

**51 log statements in a ~4,200-line engine, and only 15 of them describe normal
progress.** The distribution is diagnostic-heavy and progress-light: the product is well
instrumented for *what went wrong* and almost silent on *what is happening*.

**And it cannot be turned up.** `New-Logger`
(`Modules/FileBackup.Common.psm1:190-209`) timestamps, appends, and `Write-Host`s
**every** message with **no level comparison anywhere** — there is no threshold, no
`-Verbose` gate, no config knob. Raising verbosity is not a configuration change; the
detail does not exist to be enabled.

---

## 3. Why this compounds the stale-`Temp` defect

Filed separately, but they meet here — and the interaction is the strongest argument
that O-1 is worth money:

- The stale-lock wedge went unnoticed for **~18 hours** across two scheduled
  opportunities. It was noticed only when a *different*, louder failure was fixed and
  stopped masking it.
- A wedged run and a healthy run are **both silent**. A wedged run fails in one second
  and says one thing; a healthy 2.1 TB run says one thing and then nothing for hours.
  **From outside, at the moment you look, these are hard to tell apart** without knowing
  to compare a timestamp against an expected phase duration nobody publishes.
- Option **E** in the stale-lock review — *"leave the lock, make a stale one loud"* —
  presumes a surface on which "loud" is possible. **Today there is no such surface**:
  no phase state, no heartbeat, no last-progress timestamp. E is not implementable
  without something from §5 here.

**This document takes no position on the stale-lock options.** It only records that one
of them has a dependency that is currently unmet.

---

## 4. What an operator can actually do today

Documented so the answer exists somewhere, since it is currently folklore:
*(Superseded in part by the live-run addendum in §9, which found two stronger channels
and one trap.)*

| question | best available answer today |
|---|---|
| Is the run alive? | `docker stats` on the run container — CPU > 0 and block-IO climbing. |
| What phase is it in? | Infer from the last log line, plus whether the store is still empty. |
| How far through? | **Unavailable.** No percentage, count, or ETA exists at any layer. |
| How long should it take? | **Unpublished.** No baseline is recorded for a first pass of a given size. |
| Where do I look? | `ChangePath/backup.log` — **not** `Backup_Global.log` (O-4). |

The last row is worth noting on its own: the set log lives at `ChangePath/backup.log`,
which is *inside the same directory the stale-`Temp` guard is about*. An operator
following the guard's advice to move `Temp` aside is working in the same folder as the
log they need, and nothing points them at it.

---

## 5. Options — trade-offs only, nothing recommended

Roughly increasing cost. Not mutually exclusive.

### A. Phase banners

Emit one `INFO` on entry and exit of each of the 16 numbered steps, with elapsed time on
exit. The step boundaries already exist as code comments.

- **For:** cheapest possible change; makes phase and per-phase duration answerable;
  builds the duration baseline nobody has. Bounded, predictable output (~32 lines/run).
- **Against:** still silent *within* a multi-hour phase, which is where the problem
  actually lives. Improves post-mortem more than live monitoring.

### B. Heartbeat with counters

During steps 5 and 10, emit one line every N seconds or every N items: files seen, bytes
hashed/copied, current relative path.

- **For:** directly answers "is it moving, and how fast"; makes hangs visible in minutes;
  enables the "loud" surface option E in the other review needs.
- **Against:** must be time-based, not item-based, or a stall on one huge file is still
  silent. Adds output volume (tunable). Touches the hot loop — needs care not to make the
  logger a bottleneck at high file counts, since every write is `Add-Content` + `Write-Host`
  with no buffering.

### C. A machine-readable status file

Write `ChangePath/RUN.status.json` (phase, started-at, items done/total, bytes, updated-at),
rewritten atomically every few seconds.

- **For:** consumable by the HomeHub wrapper, NagLight, and any health check without
  scraping logs. `updated-at` doubles as the liveness/staleness signal the stale-`Temp`
  guard lacks — **one artifact serves both reviews.** Keeps the log quiet.
- **Against:** a new on-disk contract inside `ChangePath`, which must not collide with
  the change-folder scanners or be mistaken for a snapshot. Needs the same care as any
  new file in that root.

### D. Percentage / ETA

Total the work in step 5, report percent complete through step 10.

- **For:** what a human actually wants.
- **Against:** the denominator is only known *after* hashing, so step 5 — the phase that
  is silent longest on a first run — is exactly the one that cannot have a percentage.
  Solves the smaller half of the problem.

### E. Document the expectations only

No code change. Publish "a first pass of N TB takes roughly H hours; it is silent; here
is how to confirm it is alive."

- **For:** free; removes the worst operator harm (not knowing whether to intervene) —
  which, on 2026-08-30, is what led to a run being stopped.
- **Against:** does not make anything observable; relies on the reader finding the doc.

---

## 6. O-4 — reported as an observation, mechanism NOT established

**What was seen, and it is reliable:** at 09:30:56, mid-run,
`/var/log/homehub-filebackup/Backup_Global.log` was **0 bytes**, created 09:25. The three
`INFO` lines existed in `ChangePath/backup.log` (228 bytes) and on stdout/journald. At
08:15 the same file held exactly one line — `Skipping email notification (-NoMail).` —
and `New-Logger` opens with `New-Item -Force`, which truncates, so per-run truncation is
consistent with both observations.

**What is NOT established:** whether the global log is *supposed* to carry set-level
lines, whether the two loggers are intentionally separate sinks, and whether anything is
actually lost. `Backup_Global.log` is what `FILEBACKUP_LOG_PATH` names and what the
stale-`Temp` guard's own failure message directs the operator to read — so if the answer
is "that file is not where set detail goes", the **error message** is pointing at the
wrong file, which is a small doc fix rather than a logging defect.

**This is deliberately not filed as a defect.** The previous review in this pair had a
finding withdrawn for asserting a negative from an incomplete search; that lesson applies
here, and one observation across two runs is not enough to claim a mechanism. **It needs
someone who knows the intended split between the two sinks to say which it is** — the
answer may well be "working as designed, message needs rewording."

---

## 7. Verified / not verified

**Verified directly** — live on the production hub, and in this working tree:

- The timings, silence intervals, and every side-channel value in §1.
- `Update-SourceManifest` contains no log calls; the entry line is the caller's at `:3979`.
- Step 10's loop logs nothing per group or per file (`:4133-4141`).
- Log-level census (17/16/15/3) across `Modules/FileBackup.Engine.psm1`.
- `New-Logger` performs no level filtering (`Common.psm1:190-209`).
- `docs/requirements/` contains no progress/observability/heartbeat requirement.
- Set log location `ChangePath/backup.log`, contents and mtime as quoted.

**Not verified:**

- The intended relationship between `Backup_Global.log` and the set log (§6).
- Whether any phase other than 5 and 10 is long enough to matter on a large set — the
  run was still inside step 5 at the time of writing, so steps 10–16 were **not observed
  under production load** and their emission is read from source, not measured.
- The actual duration of a 2.1 TB first pass. **Still running at time of writing** — the
  figure will be a useful baseline for option E and should be appended when it lands.

**Nothing was changed on the hub for this document**; it is observation only. The run
described here is the live production first pass and was left undisturbed.

---

## 8. Cross-review, 2026-08-31 — corrections and scope ruling

Cross-reviewed the same day by the driver and an independent OpenAI Codex CLI pass
(read-only over the repo); both verified every correction below against the code, and
both reached the scope recommendation independently. The Owner ruled the same day.

### Corrections

| # | correction |
|---|---|
| **C-1** | **O-1 is half-wrong: step 10 is not silent.** `Invoke-BackupFileGroup` logs one line per **physical write** — `"Stored object '<DataPath>' for hash=… "` at `Engine.psm1:3235`, level `DEBUG` — and since `New-Logger` applies no level filter (O-3, which stands), that line always emits. On a first pass nearly every object is a new physical write, so the copy phase produces regular output. The doc read the outer loop (`:4133-4141`, which indeed logs nothing) and missed the callee. Step 10's duration was also inferred, not measured (§7 admitted this). **Step 5's silence stands, fully verified, and is the core finding.** |
| **C-2** | **The §2 census is undercounted.** 65 `& $log` call sites in the engine, not 51: ~32 are effectively `INFO` because the doc counted only explicit `'INFO'` literals and missed calls relying on `New-Logger`'s default level. The qualitative O-3 point — no threshold, no `-Verbose` bridge, no knob — is confirmed exactly as written. |
| **C-3** | **O-4 is resolved: working as designed, both sinks intentional.** The global log is the orchestrator's sink — config/dependency lines, cross-set failure summaries (`FileBackup.ps1:570`), mail notices (`:583`, written only after all sets finish, which explains the earlier run's single line). `Invoke-BackupSet` never receives `$globalLog`; it builds its own logger at `ChangePath/backup.log` (`Engine.psm1:3955`). A 0-byte global log mid-run on a healthy pass is therefore **correct**. One framing error in this doc's own O-4: the stale-`Temp` guard message directs the operator to the **README**, not to `Backup_Global.log` — the "read the global log" pointer is HomeHub-side folklore, not this repo's text. What survives is one README line naming where the set log lives. |

### Scope ruling (Owner, 2026-08-31)

**Separate work package — WP16 — not folded into WP14**, with one carve-out:

- **Into WP14:** only C-3's README pointer, as Part D item **N-3** (same one-line-doc
  category as N-1/N-2, same files).
- **WP16 (after WP14):** the corrected, narrower ask — step-5 visibility, phase
  banners/timings (option A), and whatever of B/C the Owner selects, against new SRs
  (no observability requirement exists today — §0's search confirmed against the
  registries by both reviewers).
- **Why not merged**, despite the shared container/hub origin: WP14's `RUN.inprogress`
  is safety-authoritative and **write-once** — torn writes are impossible by
  construction, liveness rides on mtime alone, and reclaim/fencing depend on exactly
  that. Option C's status file is telemetry rewritten every few seconds. One shared
  artifact would reopen WP14's just-hardened write-once proof and couple telemetry
  failures to lock reclamation; and any extra file **inside** `Temp` would classify as
  content under WP14's guard and block the very reclaim it ships. Merging also drags
  operability work into WP14's G3 data-integrity independent-review scope, delaying
  the fix the hub is blocked on.
- **The reuse that is real:** WP16's artifact is `ChangePath/RUN.status.json` —
  outside `Temp`, correlated to the lock marker by `RunId`, telemetry-only, ignored by
  reclaim, fencing, snapshots, prune, and both restorers — and it can share WP14
  Part A's compiled `StagingHeartbeat` class. Consumers read `RUN.inprogress` mtime
  for authoritative liveness and the status file for phase/counters.
- §3's dependency note is thereby answered: WP14 Part D's branch tokens make a *stale
  lock* loud; making a *healthy long run* visible is WP16's job.

---

## 9. Live-run addendum, 2026-08-31 10:35 — the channels that actually work

Second observation of the same production first pass, 70 minutes in, still step 5 —
confirming §1's core finding at scale. Currently hashing
`/source/NonDocs/MC Server Backups/MC_SERV_BACKUP_20250914.z7`; source (`sdb`) reading
69 MB/s sustained; target (`sda`) writing 0; store/state still 0 / 12 K; dmesg clean.
Two probes 44 s apart advanced one archive filename; a 20 s window on a single file at
69 MB/s ≈ 1.4 GB read — **moving, not stuck**. `sda` at zero write confirms step 10 has
not begun; per §8 C-1, when it does the log starts emitting per stored object, so the
silence ends at the phase boundary.

**Channels that work** (superseding parts of §4's table):

| channel | what it gives |
|---|---|
| the container process's **open fd on `/source`** (`/proc/<pid>/fd`) | The exact file being hashed *right now* — and since the walk is **ordered**, position in the tree is position in the run. The closest thing to a progress bar that exists today, at zero cost. |
| `/proc/diskstats`, two samples, (sectors × 512)/interval per device | Distinguishes working from hung in ~20 s, and the read/write **ratio identifies the phase**: source-read-only = hashing, target-write = copying. |
| `docker stats` | Liveness only, as §4 said. |

**Channels that do NOT work**, so nobody chases them:

| channel | why not |
|---|---|
| `/proc/<pid>/io` on the container's top-level PID | Reported a **0 MB** read delta while the disk moved 1.4 GB — that PID is not the accounting point for this I/O. diskstats is authoritative. |
| `du` on state/store | Still flat during step 5, exactly as §1 measured. |

**Design consequences for WP16** (recorded here so the plan inherits them):

- The fd trick **proves the information exists** — the engine holds the current path in
  hand and never emits it. Option B's heartbeat line should carry the **current relative
  path plus running file/byte counts**, turning an external `/proc` hack into a
  supported signal; because the walk is ordered, that line is a position indicator, not
  merely a liveness one.
- The phase being externally inferable from the read/write ratio confirms option A's
  banners belong at **phase boundaries** — they make the log agree with what the disks
  already show, even if per-item output stays off.
- Pending from the hub: a tree-size map to convert path-position into a percentage, and
  the completed pass's total duration — both feed §7's "useful baseline" item and
  option E's expectations text. Append them here when they land.
