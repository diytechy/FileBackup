# Independent reviews of the bounded run loop (2026-10-24)

Recorded verbatim so the review trail outlives the session. The brief reviews
1 and 2 got comes first; each report follows as its author wrote it (headings
demoted two levels). Adjudication is in [bounded-run-loop.md](bounded-run-loop.md)
section 13 (calls C22-C24 and "Left for the Owner"); the fixes are commit `868adb2`.

| Review | Reviewer | Commit reviewed | Findings | Accepted and fixed |
|---|---|---|---|---|
| 1 | Sol (codex `gpt-6.1-sol`, reasoning low), read-only sandbox | `7a332f8` | 2 | 2 (C22, C23) |
| 2 | Opus (medium), fresh context | `7a332f8` | 6 + 5 questions | F1-F4 (C22-C24); F5, F6, Q1 left for the Owner |
| 3 | Opus (medium), fresh context, the fix commit only | `868adb2` | 1 + 3 questions | F1 (C22 completed: a failed scratch write is Unverified, never Damaged); questions left for the Owner |

## The brief

### Independent review brief: the bounded backup run (FileBackup, branch BoundedRebuild)

You are an independent reviewer of a data-safety change in a PowerShell 7 backup
tool. Repository: `C:\Projects\FileBackup`, branch `BoundedRebuild`, at the commit
`git rev-parse HEAD` shows. Do the work yourself; do not delegate.

#### What to read first

1. `docs/plans/bounded-run-loop.md` — the Owner's rulings R1–R14, the confirmed
   calls C1–C8 (section 11) and the implementation's own calls C9–C20 (section 13).
   These are DECIDED. Do not report a ruling as a defect. If you believe a ruling
   or call loses data in normal operation, report it once as a "ruling question".
2. `AGENTS.md` sections 2–3 (architecture, invariants).

#### The exact delta to review

The implementation of that plan, `git diff 8dddcb0 HEAD`. Concentrate on the
data-integrity surface, in this order:

- `Modules/FileBackup.Engine.psm1`: `Invoke-BackupSet` and its steps
  (`Read-PriorStateForRun`, `Clear-InterruptedRunResidue`, `Get-PriorBackupDate`,
  `Get-StoreObjectIndex`, `Publish-PriorStateSnapshot`, `New-BackupRunContext`,
  `Invoke-LibraryCapture`, `Invoke-SourceFileCapture`, `Get-LatestObject`,
  `Publish-StagedObject`, `ConvertTo-FrozenRow`, `Get-SortedManifestRow`,
  `Publish-LatestState`, `Test-StateChanged`, `Move-SupersededObject`).
- `Modules/FileBackup.Common.psm1`: `Write-Manifest` (and its compiled row writer).
- `Reconstruct.ps1` (kit revision 14): how a row is resolved to bytes
  (`New-StoredObjectNameIndex`, `Find-DataFileByName`, `Resolve-RowDataSource`).
- Where the run's new snapshot shape (DataPaths kept, call C10; stale DataPaths
  tolerated, C11) meets retention and Verify: `Test-PoolResolves`,
  `Get-SnapshotPrunePlan`, `Get-StoreObjectFinding`, `Move-StoreObjectToVerify`.

#### What counts as a finding

Report only a defect that happens in NORMAL operation or under a PLAUSIBLE
failure: a kill at any instant, the backup volume filling up or disappearing, a
source file locked or changing while read, an antivirus scanner holding a file,
a store continued from the previous engine (snapshots made by older engines,
with older restore kits). The consequences that matter:

- a state (the latest backup or a snapshot) that no longer restores, or restores
  wrong bytes;
- content lost (an object deleted, or never captured while the run reports success);
- a run that leaves the store such that later runs fail or wedge;
- a wrong outcome code (0 every file captured, 1 files not captured, 2 refused
  before anything changed, 4 host problem / lock held).

OUT OF SCOPE — do not report:

- Contrived corner cases. Ruling R1: corner conditions only need a warning and the
  run carries on. If a scenario needs a hand-edited store, a name that lies about
  its bytes, two runs at once (unsupported, there is an OS lock), clock skew, or a
  sequence of several independent failures, it is out of scope.
- Style, naming, comments, performance (unless it makes a normal HomeHub-scale
  run — 180,000 files, 1 TB — fail).
- Anything a section-13 call already decided, unless you can show data loss in
  normal operation.

Before you report a finding, write down the concrete steps that produce it from a
store the tool itself made, and check the code path line by line. If you cannot
write those steps, drop it.

#### Limits

- Do not edit, create or delete anything in the repository.
- Do not run Pester or `tests/Run-All.ps1` (another long run may be active). You
  may run small read-only commands and, if needed, a small pwsh repro script whose
  stores live under `$env:TEMP`, never under the repository.
- Stop at 10 findings; rank them.

#### Return

Write your report to the output path you were given, as markdown with exactly
these six sections, compact, facts before judgement:

1. What was done (what you read; what you ran, if anything).
2. Where the artifact is (the report path).
3. What was checked and found clean (so an absence of findings is evidence).
4. Findings, most severe first. For each: severity (High = a state unrestorable
   or content lost in normal operation; Medium = a wrong outcome code, or a
   needed state not kept, under a plausible failure; Low = other), `file:line`,
   the concrete steps, why it is not an R1 corner case, and a suggested fix.
5. What was not done, and why.
6. Open questions for the caller (including any "ruling questions").

The report file at the given path is the deliverable; a summary without the file
is not done.

## Review 1 — Sol (low)

The read-only sandbox could not write the report file; this is its final message,
captured by `codex exec -o`.

#### 1. What was done

Confirmed HEAD is `7a332f88e377a52ff8e2fde823cf5e29ef19dd3a`. Read the bounded-run plan, including R1–R14 and C1–C21, and the architecture/invariants. Inspected the requested backup functions, manifest writers, PowerShell restore resolution, retention, Verify, and relevant diff sections against `8dddcb0`.

Used read-only file reads and Git commands. No delegation or tests.

#### 2. Where the artifact is

**The report file was not written.** The session’s filesystem policy permits reads only, including at the requested destination:

`C:/Users/Peter/AppData/Local/Temp/claude/c--Projects-FileBackup/205fe578-ebf3-4bbe-bc75-5e3f04be7021/scratchpad/review-sol.md`

The deliverable therefore remains incomplete. The report content follows.

#### 3. What was checked and found clean

Static inspection found:

- Prior-state publication precedes progress checkpoints.
- Checkpoints retain prior rows for files not yet processed.
- Copies are hashed while written; changed-source checks precede publication.
- Superseded-object selection uses final manifest references.
- Manifest replacement follows complete temporary-file writing; old witnesses are removed before replacement.
- Both manifest-writer paths escape embedded quotes and preserve column order.
- PowerShell restore name-index hits still undergo byte-form detection and destination hash verification.
- Move-back and duplicate cleanup protect holders with kits older than revision 4.

These are code-inspection results, not runtime verification.

#### 4. Findings, most severe first

**1. High — Deep repair quarantines healthy objects when verification cannot run.**

Locations: `Modules/FileBackup.Engine.psm1:1631`, `:1642`, `:1709`, `:1773`; `FileBackup.ps1:517`.

Concrete steps:

1. Create a compressed backup using the tool.
2. Set `CompressEnabled=false`; existing compressed objects legitimately remain.
3. Run `-Action Verify -Deep -RepairStorage` on a host without the configured 7-Zip executable.
4. Dependency initialization permits a null 7-Zip dependency when compression is disabled (`Engine:358`).
5. `Test-StoredObjectBytes` returns false for each compressed object because 7-Zip is absent (`:1631`).
6. `Get-StoreObjectFinding` converts those results into repairable `DamagedObject` findings.
7. The entry point moves them into `Verify/` **before** `Test-BackupStorageForm` performs its missing-tool refusal.

Healthy content becomes unavailable to both restorers, which exclude `Verify/`. The same false-damage classification occurs when extraction encounters a full temp volume or another host I/O error: the catch returns false.

This is a supported mixed-form store and an ordinary missing dependency or plausible host failure, not an R1 corner case. C4 authorizes moving damaged content; it does not establish that an inability to verify proves damage.

Suggested fix: distinguish verified mismatch from verification failure. Preflight required tools before mutation; propagate dependency, capacity, and I/O failures without quarantining their candidates.

**2. Medium — One kill leaves recoverable content invisible to retention, persistently blocking prune.**

Locations: `Modules/FileBackup.Engine.psm1:716`, `:1123`, `:2154`, `:5482`.

Concrete steps:

1. Complete a backup containing file content A at date D1.
2. Change the source to B and run another backup.
3. The run publishes `Snapshot_D1`, whose row names A.
4. Kill it after final manifest B and `LastBackupRun=D2` are written, before `Move-SupersededObject`.
5. A remains in the backup root; neither the latest manifest B nor `Snapshot_D1` names A in the folder physically holding it.
6. Invoke Verify or prune.

`Get-BackupContentIndex` indexes physical supply only through a manifest row naming a file **in that same folder**. It consequently omits A. `Test-PoolResolves` reports the snapshot broken, although kit 14 finds A by name and restores it. The whole-pool precondition blocks every prune.

An unchanged subsequent backup does not repair this: it removes its newly built, unnecessary snapshot and leaves unused A in latest. Subsequent changes can move A into another snapshot whose manifest also lacks A.

This requires one explicitly supported interruption, without store editing or misleading object names. C10/C11 accept stale DataPaths; the defect is the incompatible supply index.

Suggested fix: derive retention’s physical supply from actual stored-object names independently of local manifest ownership, while retaining manifest rows as demand. Ensure prune re-homes such supply before deleting its holder.

#### 5. What was not done, and why

No Pester, integration suite, repro stores, or repository modifications were performed. Findings were traced statically; runtime reproduction remains outstanding. Bash restore and the complete test delta were not exhaustively reviewed.

The requested report file could not be created under the enforced read-only filesystem policy.

#### 6. Open questions for the caller

No ruling questions. Both findings concern implementation behavior beyond the accepted calls.

A session permitting writes to the specified scratchpad is needed to deliver the report file.
## Review 2 — Opus (medium)

### Independent review: the bounded backup run (BoundedRebuild)

Commit reviewed: `7a332f88e377a52ff8e2fde823cf5e29ef19dd3a` (HEAD of `BoundedRebuild`). Delta: `git diff 8dddcb0 HEAD`.

#### 1. What was done

- **Read:** `docs/plans/bounded-run-loop.md` (R1–R14, C1–C21). In `Modules/FileBackup.Engine.psm1` I read every step of `Invoke-BackupSet` line by line, plus `Get-StoreObjectIndex`, `Copy-FileWithHash`, `Test-BackupDiskFull`, `Publish-StagedObject`, `Invoke-SourceFileCapture`, `Get-LatestObject`, `New-CapturedRow`, `ConvertTo-FrozenRow`, `Get-SortedManifestRow`, `Publish-PriorStateSnapshot`, `Move-SupersededObject` and `Get-PriorBackupDate`. On the retention and audit side I read `Get-FolderFileSet`, `Get-BackupContentIndex`, `Get-SnapshotPrunePlan`, `Test-PoolResolves`, `Get-StorageFormFinding`, `Test-StoredObjectBytes`, `Get-StoreObjectFinding`, `Move-StoreObjectToVerify`, `Repair-BackupStorageForm`, `Assert-PrunePrecondition` and `Remove-BackupSnapshot` with its helpers. I also read `Write-Manifest`, its compiled writer and `Read-Manifest` in Common, and in `Reconstruct.ps1` (kit 14) the root resolution (C21), `New-StoredObjectNameIndex`, `Find-DataFileByName`, `Resolve-RowDataSource`, the restore loop and `Find-DataFileByHash`. I compared against the old engine and kit at `8dddcb0`: snapshot dating, and the missing-DataPath fallback in kit 13. I checked `Invoke-VerifyAction` in `FileBackup.ps1` and the bash restorer's name index (parity only).
- **Ran:** no Pester and no `Run-All.ps1`. I exported HEAD with `git archive 7a332f8 Modules Reconstruct.ps1 bash` to `%TEMP%\fb-head`, outside the repository. I ran three small pwsh repro scripts against that export, with stores under `%TEMP%\fbrev-*`. They drive `Invoke-BackupSet` in-process; a thrown test hook stands in for a kill, the way `BoundedRun.Tests.ps1` does it. The scripts are `repro1.ps1`, `repro2.ps1` and `repro3.ps1` in the same scratchpad folder as this report.
- **Note:** while I was reviewing, the working tree gained uncommitted changes to `Modules/FileBackup.Engine.psm1` and `tests/Unit/BoundedRun.Tests.ps1`: a `Get-StoredObjectVerdict` function, a 7-Zip guard in `Get-StoreObjectFinding`, and placement by the naming snapshot in `Move-SupersededObject`. They appear to target F1 and F2 below. **I did not review them.** Every result here is for HEAD, and every repro ran against the HEAD export.

#### 2. Where the artifact is

`C:\Users\Peter\AppData\Local\Temp\claude\c--Projects-FileBackup\205fe578-ebf3-4bbe-bc75-5e3f04be7021\scratchpad\review-opus.md`

#### 3. What was checked and found clean

- **Kill safety of the run order.**
  - A kill before Publish leaves only `Building_*`, `Incoming` or mount-check residue, and step 1 deletes it.
  - `Snapshot_D` is published before the first checkpoint.
  - A checkpoint holds the prior rows for files the loop has not reached yet, and every object it names is in latest (or in a folder whose kit is older than 4, per C19).
  - After a kill, the existing `Snapshot_D` is kept, and LastBackupRun is unchanged, so D is stable.
  - Step 7 deletes only a snapshot this run built (`BuiltNow`), and that snapshot holds no objects. The index is built before publish, and step 8 runs after step 7.
- **Hash-while-copy.** The stored name always comes from the bytes written. Size and mtime are compared before and after each read. The in-place tier re-copies with a hash check. A sharing violation on a file being written is retried (R12), then frozen with its prior row and counted as exit 1. A frozen row's object is brought back into latest.
- **Disk full.** Both HResults are recognised on Windows and errno 28 on Linux. The check walks inner exceptions and rethrows, so the set stops with 4. A checkpoint that fails leaves the old manifest in place, because the temp file is deleted and nothing is renamed.
- **Write-Manifest.**
  - Header and quoting match Export-Csv.
  - The date column is rebuilt from `LastWriteTime` with `'O'`.
  - `.meta` is deleted before the rename, so a kill between the two leaves the old manifest without a witness (restorable).
  - The compiled writer and the PowerShell loop produce the same 9 columns in the same order.
- **Store continued from the old engine.**
  - The old engine also named a snapshot after the prior run's date (`-SnapshotDate $priorBackupDate`), so the first new run's `Snapshot_<LastBackupRun>` does not collide.
  - An old `Temp` folder is warned about and left alone.
  - Old snapshots keep their `.meta`. Rewrites by prune or repair delete it, and old kits restore a missing witness.
  - Kit 13 falls back to the content scan for a missing non-blank DataPath. In the one-mount layout its parent guess (`/store`) scans the pool recursively, so moved-back objects are still found.
- **Retention safety.** I traced `Get-SnapshotPrunePlan` and `Test-PoolResolves` with C10/C11 snapshots. A stale DataPath is demand. An object that the folder holding it does not name in its manifest is never supply, so prune refuses rather than deleting. I found **no path where prune deletes a needed object.**
- **Kit 14 resolution.** The order is own DataPath, then the name index (authority folder, latest, snapshots newest first), then the content scan. A written file is always verified against its row. C21's sibling detection was checked, and the bash restorer has the same index.
- **Outcome codes:** lock held → 4; refusals → 2; files not captured → 1. I confirmed this by reading.

#### 4. Findings, most severe first

##### F1 — High: `-Action Verify -Deep -RepairStorage` moves the only copy of content into `Verify/` when it could not check the bytes

**Where.** `Modules/FileBackup.Engine.psm1:1631` (`if ($Entry.Extension -ine '.7z' -or -not $SevenZipPath) { return $false }`), `:1643` (any exception returns `$false`), `:1709–1716` (every copy that is not "good" becomes a Repairable `DamagedObject`), and `:1731` (`Move-StoreObjectToVerify`). In `FileBackup.ps1:517–520` the object audit and the move both run **before** the 7-Zip guard in `Test-BackupStorageForm` (`Engine:1548`), which then throws and gives exit 2.

**Steps (confirmed by `repro3.ps1` on HEAD):**
1. Make a store with `CompressEnabled = true` and 7-Zip installed; back up `doc.txt`. The object is `…_D6b.7z` in latest.
2. Run `-Action Verify -Deep -RepairStorage` on a host where 7-Zip did not resolve. That is the normal state after the set's `CompressEnabled` is turned off: `Initialize-Dependencies` then resolves 7-Zip only if it is at the default path. It also happens when `Tools.SevenZipPath` is wrong.
3. Result: `DamagedObject … repairable=True`, and the object is moved to `changes\Verify\backup\`. Verify exits 2. A kit-14 restore of latest, run with 7-Zip present, gives **exit 1: 1 content-missing (doc.txt)**.

Verify's own log line tells the Owner to empty `Verify/` by hand, and once he does, the content is gone.

The same thing happens on two plausible single failures, with 7-Zip present:
- A transient read error, or an antivirus scanner holding the object, makes `Get-FileXxHash` throw.
- 7-Zip fails to expand a large archive into the scratch folder `<ChangePath>/Verify/.expand`, which sits on the backup volume, because that volume is nearly full.

**Why it is not an R1 corner case.** The store is one the tool made, the command is the documented maintenance action (R10, C14), and the trigger is a single condition: no 7-Zip, a read error, or a full volume. C4 rules on objects that are *proven* damaged; here nothing was proven.

**Fix.** Use three verdicts — Good, Damaged, Unverified — and move only proven Damaged objects. Refuse `-Deep` without 7-Zip before any audit or move.

##### F2 — Medium: after an interrupted run, or a superseded move that failed, step 8 puts objects in a snapshot whose own manifest does not name them; Verify then reports false loss and every prune is refused

**Where.** `Move-SupersededObject` (`Engine:4718–4739`) sends every unused latest object to this run's snapshot. "Unused by the final rows" is not the same as "named by the prior manifest" once a run was interrupted. The retention and audit index counts a copy as supply only when its own folder's manifest names it (`Engine:720`). So the content becomes invisible to `Test-PoolResolves` (`:1120–1148`, `BytesSurvive = false`), to the prune plan (`:921`, `UnreferencedData`) and to the storage audit. Restores are unaffected: kit 14 finds the object by name.

**Steps A (confirmed by `repro1.ps1 -Variant killAfterLBR`):**
1. Run 1 backs up `a.txt` (v1) and `b.txt`.
2. Change `a.txt` to v2. Run 2 is killed after `Set-LastBackupRun`, before step 8.
3. Change `a.txt` to v3 and run 3 normally. v1's object (named only by `Snapshot_01_01`) and v2's object both move into `Snapshot_01_02`.
4. Result:
   - `Test-PoolResolves` reports `[broken-pool] 'Snapshot_2026_01_01…': row 'a.txt' points at …, which is not in that folder`.
   - A `Remove-BackupSnapshot -WhatIf` of any snapshot is refused with code 2: "blocks EVERY prune in this store".
   - Verify reports `PoolUnresolvable` ("no bytes for this row anywhere in the pool") and exits 1.
   - The kit restore of `Snapshot_01_01` gives exit 0 with the correct bytes.

The same end state follows from:
- a superseded move that fails (`:4736`, for example because an antivirus scanner holds the file), followed by the next run;
- a kill between the final manifest and LastBackupRun (C17);
- a kill after a move-back but before a checkpoint, with the file then deleted at the source before the next run.

**Steps B (confirmed by `repro1.ps1 -Variant killMidLoop`):** a kill after a checkpoint, then the file changes again before the next run. v2's object lands in `Snapshot_01_01`, which does not name it. Prune of that snapshot is refused (`unreferenced-data`, code 2) and Verify reports `Unreferenced`.

**Why it is not an R1 corner case.** It needs one kill at a plausible instant, or one failed rename, plus ordinary file churn. Snapshots are write-once (R6), so the wedge is permanent and HomeHub's automated retention stops.

**Fix.** Either of these works:
- send each unused object to the newest snapshot whose own manifest names it, falling back to this run's snapshot; or
- make the retention and audit index count supply by object *name*, from the folder listing (consistent with C11 and C12 and kit 14).

The second also covers stores already in this state.

##### F3 — Medium: a source that goes away mid-run empties the latest state and the run reports 0

**Where.** `Engine:4318` and `:4358`: `FileInfo.Exists` is false, so the file is `Gone`. At `:5240`, Gone only removes the path from `$visited`. Nothing is logged or counted, so every remaining row is dropped as a deletion and its objects go to the snapshot. A related variant is at `:5218–5219`: if the source *root* cannot be listed, its error yields an empty prefix, so no rows are frozen and all of them are dropped. That run exits 1.

**Steps (confirmed by `repro2.ps1`):**
1. Back up 5 files.
2. In the next run, the source folder disappears after the walk; the test hook renames it, standing in for a USB source unplugged or an SMB share dropping.
3. Result: **exit 0**. The log says `Files: 1 in the latest state … 4 superseded moved into the snapshot, 0 not captured`.

Nothing is lost: the prior state is in the snapshot, and the next run moves everything back by rename. But the scheduler and NagLight see "every file captured", and the latest state restores 1 of 5 files until the next run.

**Why it is not an R1 corner case.** A source volume vanishing is a plausible single host failure, the same class as the backup volume disappearing, which the C1 table maps to 4.

**Fix.** Before Publish-LatestState, check that the source root still exists and can be listed; if not, stop with 4. Checkpoints still hold the prior rows for Gone paths, so that stop is as safe as a kill. Treat an unlistable root as a refusal or as 4, not as an empty prefix.

##### F4 — Low: step 7's snapshot deletion is unguarded; a lock or kill there reports 4 for a finished run and can leave a partial `Snapshot_D` that no run cleans up

**Where.** `Engine:5486`, `Remove-Item -LiteralPath $snapshot.Path -Recurse -Force`, with no try/catch. This runs on **every unchanged run**, which builds a full kit copy (including `System.IO.Hashing.dll`) and then deletes it.

**Steps.**
1. Run on an unchanged library.
2. An indexer or antivirus scanner holds one of the files just copied into `Snapshot_D`, or the process is killed during the recursive delete.
3. With a lock: the outer catch reports **4** ("did not finish") although the latest state is complete; step 8 and the browse view are skipped.
4. The next run's D is this run's date, so the partial `Snapshot_D` stays for good.
5. If its `MANIFEST.csv` survives but its `RECONSTRUCT.ps1` does not (enumeration order on ext4 is not alphabetical), its stale DataPaths, together with kit revision 0, make `Test-PoolResolves` report `broken-pool`, and every prune is refused.

**Why it is not an R1 corner case.** One kill or one locked file, on the most frequent path through the run.

**Fix.** Rename `Snapshot_D` to `Building_<label>` (one atomic rename), then delete it inside a try/catch that warns. `Clear-InterruptedRunResidue` already removes `Building_*` on the next run.

##### F5 — Low: a failed move-back leaves a latest row whose object is in a snapshot; a restore of latest from a copied store cannot find it

**Where.** `Get-LatestObject`, `Engine:4473–4476`: when the move fails, the snapshot entry is returned and the latest row names an object outside latest. In `Reconstruct.ps1:657`, restoring from the backup root sets `$changeRoot = $null` unless the path sidecar is valid, so the index and the scan cover latest only (`:1215`, `:1223`). The sidecar is ignored for a store that was copied or moved, and for a container store restored on the host (C21's own example).

**Steps.**
1. A restore of `Snapshot_K` is reading object X while the nightly run re-adds that content. On Windows, `File.Copy` shares the file for reading only, so the rename fails and a warning is logged.
2. The latest row names X, which is still in `Snapshot_K`.
3. Before the next run, latest is restored on the host from the container's store, or from a USB copy of it: that row fails with exit 1 (content missing).

**Why it is not an R1 corner case.** It is the documented restore-from-a-copy path, after one failed rename. It is low because it lasts only until the next run and needs a concurrent restore or lock.

**Fix.** When a latest restore has no known change root, auto-detect the change root, as C21 does in the other direction. Or, on a failed move-back, copy the object into latest instead; the duplicate is left for Verify.

##### F6 — Low: a missing backup volume on Windows gives exit 2, not 4

**Where.** `Resolve-BackupSetPaths` creates a missing `BackupPath` or `ChangePath` (`Engine:3588–3597`). If the drive letter is gone, `New-Item` throws, and `Invoke-BackupSet:5433–5436` returns **2**. The C1 table puts "the backup volume disappeared" under 4 (warn and retry). On Linux, an unmounted mount point is silently created on the root filesystem instead. This is older code, but C1 newly assigns the meaning.

**Steps.** USB backup drive `E:` absent at the scheduled time → exit 2, so NagLight shows an error instead of warn-and-retry.

**Fix.** If the volume or parent of an absent root does not exist, return 4. Consider refusing to create a root whose parent is missing.

#### 5. What was not done, and why

- **No Pester or Run-All**, as the brief forbids. The only executions were the three repros, against a HEAD export in `%TEMP%`.
- **The uncommitted working-tree changes were not reviewed.** They appeared during the review and seem aimed at F1 and F2; they need their own review.
- **Not read in depth:**
  - the `bash/reconstruct.sh` restore loop — only the existence of its name index and its revision were checked;
  - `New-BrowseViewIndex`, the container scripts, and `Update-BackupSnapshotKit`;
  - the compression probe internals, which are unchanged (SR-081).
- **Performance at 180,000 files and 1 TB was not measured.**
- **Linux/container behaviour was reasoned from the code, not run.** That covers rename(2) behaviour, ext4 enumeration order (F4) and the tmpfs size.

#### 6. Open questions for the caller

1. **Ruling question (R10/C14):** a non-Deep `-RepairStorage` moves duplicates without checking the copy it keeps (`Get-StoreObjectFinding` keeps `copies[0]`, the latest copy). If that copy has rotted, the only good copy goes to `Verify/`, and the Owner then empties the folder. Should a duplicate move first hash the copy that is kept? That costs one hash per duplicate group, not per object.
2. **F2:** should the fix go in the run (placement), in the audit (supply by name), or both? Only the audit-side fix heals stores that already contain objects their folder does not name.
3. **F3:** stopping with 4 when the source root vanishes mid-run — does the Owner want that, or a warning plus exit 1? Exit 1 still leaves an emptied latest state until the next run.
4. **Retention integration:** does HomeHub's retention call pass `-DiscardUnreferencedData`? If it does, F2 variant B prunes silently; if not, it wedges.
5. **C19:** kit revisions below 4 predate WP12 (kit 9), so their folders hold base-85 names that `ConvertFrom-StoredObjectName` never indexes. C19 then only bites for kit-less snapshot folders (revision 0). Is that the intended scope?

## Review 3 — Opus (medium), the fix commit `868adb2`

Its brief was the same scope rules applied to `git diff 7a332f8 868adb2` of the
engine only (the four fixes C22-C24). Its F1 was fixed in the next commit: a
missing scratch file is Unverified, and `Expand-FileWithSevenZip` stops on a
failed move whatever the caller's error preference. Its three questions are left
for the Owner (see the plan's section 13).

### Independent review of 868adb2: the four engine fixes

#### 1. What was done

I reviewed `git diff 7a332f8 868adb2 -- Modules/FileBackup.Engine.psm1`, reading only. I read the four fixes and what they depend on in the 868adb2 tree:

- `Expand-FileWithSevenZip` and `Get-StoredObjectForm` in Common.
- `Get-StoreObjectIndex`, `Get-PoolSnapshotFolder`, `Publish-PriorStateSnapshot`, `Clear-InterruptedRunResidue`, `Get-SourceFileList`, `Invoke-SourceFileCapture`, `Get-SortedManifestRow` and `Invoke-BackupSet` in Engine.
- `Invoke-VerifyAction` in FileBackup.ps1.
- Plan section 13 (C10, C12, C19, C22 to C24) and the new tests in `tests/Unit/BoundedRun.Tests.ps1`.

I exported the commit with `git archive 868adb2` to `%TEMP%\rv868` and ran one repro script against it in two forms, both on stores under `%TEMP%`. I did not run Pester or Run-All.

#### 2. Where the artifact is

- This report: `C:\Users\Peter\AppData\Local\Temp\claude\c--Projects-FileBackup\205fe578-ebf3-4bbe-bc75-5e3f04be7021\scratchpad\review-opus-2.md`
- Repro scripts:
  - `C:\Users\Peter\AppData\Local\Temp\claude\c--Projects-FileBackup\205fe578-ebf3-4bbe-bc75-5e3f04be7021\scratchpad\repro1.ps1` sets `$ErrorActionPreference='Stop'` at script scope, as FileBackup.ps1 does.
  - `C:\Users\Peter\AppData\Local\Temp\claude\c--Projects-FileBackup\205fe578-ebf3-4bbe-bc75-5e3f04be7021\scratchpad\repro1b.ps1` is the same script without that line.
- The repro stores were deleted afterwards. The export at `%TEMP%\rv868` is still there.

#### 3. What was checked and found clean

**Fix 1, the Verify verdict**
- Under the documented invocation (`pwsh -File FileBackup.ps1 ...`), every failed read or expand ends in the `catch` and gives `Unverified`. Repro1 confirms this: the scratch write failed, the finding was `UnverifiedObject` with `Repairable=False`, nothing moved, and the archive stayed in place.
- `UnverifiedObject` is excluded twice in `Move-StoreObjectToVerify`: by its class and by `Repairable`.
- Duplicates are chosen only among Good copies, so an Unverified copy is never set aside as a duplicate of something.
- The up-front `-Deep` refusal without 7-Zip reaches `Invoke-VerifyAction`'s catch and returns 2. This is no regression: `Test-BackupStorageForm -Deep` already refused that case.
- A raw object of the wrong length, or one that hashes to another key, is Damaged only after a completed read.

**Fix 2, `Move-SupersededObject`**
- The normal superseded case is unchanged: objects named by the prior rows go to this run's snapshot. So is the case where no manifest names an object.
- `$priorRows` hold the same DataPaths as the snapshot manifest. Capture does not change their DataPath (`Get-SortedManifestRow` sets only Duplicate, and frozen rows are new objects).
- The case where the snapshot was not built by this run (it already existed) is handled by reading that snapshot's own manifest in the newest-first loop.
- A path mismatch between `$snapshot.Path` and `FullName` only costs one extra manifest read.
- A destination that already holds the same name makes `File.Move` throw. The object stays in the backup root, still restorable, with a warning.
- Moving an object into an older snapshot whose kit is older than revision 4 does not conflict with C19, which forbids moves out of such a folder, not into one.
- Prune and Verify index the object where its own folder's rows name it. Because the object goes to the newest snapshot that names it, no newer manifest names it.

**Fix 3, the source going away**
- When a drive or a mapped or UNC share goes away, `FileInfo.Exists` is false. The files count as Gone, `Directory.Exists(SrcPath)` is false, and the run throws before `Publish-LatestState`, so `Invoke-BackupSet` returns 4.
- Checkpoints written before the throw keep the prior rows for files not reached (working rows start as prior rows), so the checkpointed latest state is still a valid mix (R13).
- When the root cannot be listed or vanishes before the walk, `Get-ChildItem` reports the root as `TargetObject`. That becomes the `''` prefix, every row is kept, and the run returns 1.

**Fix 4, `Remove-UnchangedSnapshot`**
- The snapshot built in step 3 holds no objects when step 7 runs (step 8 comes later, and `Get-LatestObject` only moves objects out of snapshots), so deleting `Building_<D>` loses nothing.
- `LastBackupRun` is written in step 6, before the rename.
- A leftover `Building_<D>` is removed by `Clear-InterruptedRunResidue`.
- When the rename fails, the snapshot is kept, and step 8 then uses it with the correct `SnapshotRows`.

**Regressions against 7a332f8:** none found. Every changed path is either the earlier behaviour or a stricter one.

#### 4. Findings, most severe first

##### F1 (High consequence, likelihood depends on how Verify is launched). `-Deep -RepairStorage` can still move intact archives into `Verify/` when a host problem stops the scratch write

**Where**
- `Modules/FileBackup.Engine.psm1:1647-1652` (`Get-StoredObjectVerdict`)
- `Modules/FileBackup.Common.psm1:844` and `:873` (`Expand-FileWithSevenZip`)

**Mechanism**
1. `Expand-FileWithSevenZip` extracts into `[IO.Path]::GetTempPath()`. It then uses `Move-Item -Force` to move the payload to the scratch file on the backup volume, `<ChangeRoot>\Verify\.expand\<guid>`.
2. `Move-Item` reports an I/O failure as a non-terminating error. A full destination volume in a cross-volume move is one such failure.
3. Inside a script module, that error becomes terminating only when the global `$ErrorActionPreference` is `Stop`.
4. When it does not terminate, `Expand-FileWithSevenZip` returns normally and the scratch file does not exist. `Get-StoredObjectVerdict` then reaches `return 'Damaged' ('it expands to bytes that are not the content its name records')`, which is the "completed comparison" verdict.
5. The finding is `Repairable=$true`, and `Move-StoreObjectToVerify` moves the object.

**When the preference is `Stop`**
- `pwsh -File FileBackup.ps1` runs the script in the global scope, so its `Stop` becomes global and the bug stays hidden. This is the README's documented form and the container's.
- `& .\FileBackup.ps1 ...` or `.\FileBackup.ps1 ...` from an open pwsh prompt runs it in a child scope. The global preference stays `Continue`. I checked this with a small test script: under `-File` the global preference was `Stop`, under `&` it was `Continue`.

**Concrete steps (reproduced, `repro1b.ps1` against the 868adb2 export)**
1. Make a store with `CompressEnabled=$true` and back up one compressible file with the tool. Result: exit 0 and one `<key>.7z` object in the backup root.
2. Make the scratch write fail. The repro denies write on `<ChangeRoot>\Verify\.expand`, standing in for a full backup volume. In the field: `%TEMP%` on C:, the store on a full external D:, and Verify started from a pwsh prompt.
3. Run `Get-StoreObjectFinding -Deep -SevenZipPath <7z>` and then `Move-StoreObjectToVerify`. These are the calls that `-Action Verify -Deep -RepairStorage` makes.
4. Observed:
   - The console printed `Move-Item: Access to the path is denied.` and the run carried on.
   - The finding was `Class=DamagedObject`, `Repairable=True`.
   - The log read `[DamagedObject] moved '...\Backup\<key>.7z' to '...\Changes\Verify\Backup\<key>.7z'`.
   - Afterwards `Test-PoolResolves` returned `broken-pool` with `BytesSurvive=false` for `big.txt`.
5. The same steps with the script-scope `Stop` (`repro1.ps1`) gave `UnverifiedObject` and moved nothing.

**Effect.** On a full backup volume every archive in the pool expands to a missing scratch file, so every archive is judged Damaged and moved aside.
- Latest-state content still in the source comes back on the next backup (SR-053).
- Superseded content held only in snapshots does not come back. Those snapshot states no longer restore until someone moves the files back by hand.
- The outcome is exactly what C22 was meant to rule out: moving on a host problem.

**Why this is not an R1 corner**
- It needs one plausible failure: a full or unwritable backup volume, which is also exactly when an Owner reaches for `-RepairStorage`.
- It needs one ordinary way of launching the tool: from a pwsh prompt.
- It needs no hand edits; the store was made by the tool.
- It is not a regression: `Test-StoredObjectBytes` at 7a332f8 returned `$false` here too. But it is a gap in what fix 1 claims ("only a completed comparison is evidence of damage").

**Suggested fix** (either works; the first is the most local):
- In `Get-StoredObjectVerdict`, return `Unverified` when the scratch file is missing after the expand ("the expand produced nothing"). Keep `Damaged` only for a scratch file that exists and has the wrong length or hash.
- Or pass `-ErrorAction Stop` to the `Move-Item` and `New-Item` calls in `Expand-FileWithSevenZip`. Setting the preference inside the Engine function does not help: Common's `Move-Item` resolves its preference through Common's module scope and the global scope, not Engine's.

The same helper is used at `Engine.psm1:1434` (storage-form `-Deep`) and `:2423`, which may want the same check. They are outside this delta.

No other findings met the bar.

#### 5. What was not done and why

- **Pester and Run-All:** not run, as the brief instructed (a long run is active).
- **A real full volume:** not reproduced, because that needs an admin-mounted small VHD. A write denial produces the same non-terminating `Move-Item` path.
- **Linux and the container:** not exercised. `pwsh -File` makes the preference global there, so F1 is masked.
- **Other repro scenarios:** fixes 2 to 4 were checked by reading the code against the new tests, not by new repros, because the shipped tests already drive the stated scenarios. I did not run those tests.
- **Repository state:** I edited nothing. `git status` shows `M docs/plans/bounded-run-loop.md` and `?? docs/plans/bounded-run-loop-reviews.md`. Those changes are not mine; they came from another session.

#### 6. Open questions

1. **A coincidence of lengths.** The tool keeps a `.7z` object whatever its size. If one of its own archives happens to be exactly the content's length, everything treats it as raw by length (`Get-StoredObjectCompressedFlag`, and `Get-StoredObjectVerdict` hashes it raw). The new code then gives a "completed" `Damaged` and moves the only copy.
   - This is very rare, it predates this commit, and the restorers may already mis-restore such an object. It is worth one decision.
   - Possible fixes: when a `.7z`'s length matches but the raw hash differs, try expanding it before calling it Damaged; or have the writer re-store such an archive as raw.
2. **The scratch file is not where the docs say.** `Get-StoredObjectVerdict`'s help says the archive is expanded "beside the change root, on the backup volume and never in RAM (the C-12 lesson)". In fact `Expand-FileWithSevenZip` expands into the system temp first, which is tmpfs in the container. A large archive under `-Deep` in the container fills RAM-backed `/tmp`. The verdict then becomes `Unverified`, which is safe but not the C-12 promise, and it risks memory pressure. This predates the commit.
3. **A source mount on Linux.** The source-gone check depends on `Directory.Exists(SrcPath)` being false. On Linux, a source whose mount drops can leave an empty mount-point directory. If the reads then show Gone rather than an I/O error, every file is recorded as removed and the run returns 0. Nothing is lost: the content moves into the snapshot and comes back on the next run. Is that acceptable for HomeHub, or should "every remaining file vanished" also stop the run with 4?
