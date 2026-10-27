# Review: retention, Verify, the OS lock, the kit copy and the entry points (BoundedRebuild @ 7532b86)

## 1. What was done

**Read:**
- The brief. AGENTS.md §1–4. Plan `docs/plans/bounded-run-loop.md` (R1–R14, C1–C35). `bounded-run-loop-reviews.md` (reviews 1–5). README: Restore, retention, Verify, container, "What is not recorded", "Notes & troubleshooting".
- `docs/defect-review-2026-10-05-content-index-memory.md` and the M-1/M-4 entries in `docs/status.md`.
- **Engine, line by line:**
  - Retention: `Get-FolderFileSet`, `Test-FolderHoldsFile`, `Get-BackupContentIndex`, `Get-PoolSnapshotFolder`, `Get-SnapshotPrunePlan`, `Test-StorageFormAgreement`, `Test-PoolResolves`, `Get-PruneCapacityRefusal`, `Assert-PrunePrecondition`, `Get-BackupSnapshot`, `Remove-CommittedPruneResidue`, `Invoke-PruneEntrySweep`, `Copy-ReHomedDataFile`, `Publish-PruneManifest`, `Complete-PruneDeletion`, `Remove-BackupSnapshot`, `Get-PruneBatchExitCode`.
  - Verify: `Get-StorageFormFinding`, `Get-BackupKitRevision`, `Test-BackupStorageForm`, `Get-StoredObjectVerdict`, `Get-StoreObjectFinding`, `Move-StoreObjectToVerify`, `Measure-DuplicateRepairCost`, `Remove-VerifyScratch`, `Repair-BackupStorageForm`, `Update-BackupSnapshotKit`.
  - Kit and lock: `New-ReconstructScript`, `Enter-/Exit-StagingOsLock`, `Enter-StoreMutationLock`.
  - Read for context: `Resolve-BackupSetPaths`, `Assert-StoreVolumePresent`, `Initialize-Dependencies`, `Get-StoreObjectIndex`, `ConvertFrom-StoredObjectName`, `Get-LatestObject`, `Invoke-SourceFileCapture`, `Publish-PriorStateSnapshot`, `Move-SupersededObject`, `Clear-InterruptedRunResidue`, `Invoke-BackupSet`.
- **Common:** `Write-Manifest`, `Read-Manifest`, the date (de)serialisers, `ConvertFrom-HashSizeFileName`, `Initialize-XxHashLibrary`, `Get-XxHashDllPath`.
- **Restorers, where my slice's artifacts meet them:** in `Reconstruct.ps1`, the root/sidecar resolution, the name index, `Resolve-RowDataSource`, `Restore-OneRow`, the restore loop and `Wait-BeforeClosing`; in `bash/reconstruct.sh`, `decode_hash_size_names`, the name index and the restore loop.
- **Entry points:** all of `FileBackup.ps1`, `container/entrypoint.sh` and the `Dockerfile`.

**Ran** (no Pester, no Run-All). Seven small pwsh repros. Each one builds its store under `%TEMP%` by driving `FileBackup.ps1 -File` and deletes it afterwards. `git status` was clean after every run. Scripts:

- `C:\Users\Peter\AppData\Local\Temp\claude\c--Projects-FileBackup\a79ce2cf-0cdb-4d8a-bf86-f4dab9fe2166\scratchpad\dll-lock-repro.ps1` (F4)
- `C:\Users\Peter\AppData\Local\Temp\claude\c--Projects-FileBackup\a79ce2cf-0cdb-4d8a-bf86-f4dab9fe2166\scratchpad\restore-blocks-backup.ps1` (F4)
- `C:\Users\Peter\AppData\Local\Temp\claude\c--Projects-FileBackup\a79ce2cf-0cdb-4d8a-bf86-f4dab9fe2166\scratchpad\prune-residue-repro.ps1` (F2)
- `C:\Users\Peter\AppData\Local\Temp\claude\c--Projects-FileBackup\a79ce2cf-0cdb-4d8a-bf86-f4dab9fe2166\scratchpad\verify-lock-repro.ps1` (F3)
- `C:\Users\Peter\AppData\Local\Temp\claude\c--Projects-FileBackup\a79ce2cf-0cdb-4d8a-bf86-f4dab9fe2166\scratchpad\verify-whatif-repro.ps1` (F3)
- `C:\Users\Peter\AppData\Local\Temp\claude\c--Projects-FileBackup\a79ce2cf-0cdb-4d8a-bf86-f4dab9fe2166\scratchpad\repair-kill-repro.ps1` (F5)
- `C:\Users\Peter\AppData\Local\Temp\claude\c--Projects-FileBackup\a79ce2cf-0cdb-4d8a-bf86-f4dab9fe2166\scratchpad\entry-codes-repro.ps1` (F6)

## 2. Where the artifact is

`C:\Users\Peter\AppData\Local\Temp\claude\c--Projects-FileBackup\a79ce2cf-0cdb-4d8a-bf86-f4dab9fe2166\scratchpad\review-retention-verify.md`

## 3. What was checked and found clean

**Prune under a process kill at each step**
- Before the commit point nothing is deleted. The sweep, the copies and the manifest publishes all run inside the transaction, after the rails pass and with the OS lock held.
- The final `Test-PoolResolves` runs with the target excluded, after the destination manifests are published (Engine:2832).
- One rename takes the target out of `^Snapshot_` for every consumer.
- `Remove-CommittedPruneResidue` is scoped to the name being pruned.
- A re-run resumes: an identical destination file is accepted at plan time (Engine:974–980) and skipped by the copy (Engine:2555).
- `-WhatIf` mutates nothing: no lock, no residue completion, no sweep.

**Prune never deletes the last copy of content a surviving row needs (normal operation)**
- Supply counts only files that their own folder's manifest names (Engine:714–720).
- Every demanded key whose only named copies are in the target is re-homed (Engine:938–999).
- A demanded key with no named supply at all makes `Test-PoolResolves` refuse the whole pool (Engine:1120–1166). So `-DiscardUnreferencedData` cannot discard an object that some surviving row needs by key.
- Destination election, `destName = sourceRow.DataPath` and the row edits are as documented.
- Manifest round-trip: `ParseExact 'O'` followed by `ToString('O')` keeps the instant, so a rewritten snapshot manifest's logical columns are unchanged.
- The capacity rail sums per volume and adds the C34 scratch. An unmeasurable volume is skipped.

**Verify**
- Only `Damaged` objects and duplicates whose kept copy is confirmed move. `Unverified` never moves.
- A duplicate held in a folder with a kit below 4 is not repairable.
- The scratch is removed when empty.
- `Update-BackupSnapshotKit` copies the seven kit artifacts and never `.meta`.
- `Get-BackupKitRevision` uses `ReadAllLines`, so it leaks no handle.

**OS lock**
- Backup, prune, `Repair-BackupStorageForm` and `Update-BackupSnapshotKit` each take it.
- Any open failure counts as a live holder.
- The lock file is never deleted.
- One exception: the Verify object moves (F3).

**Entry points**
- Backup set codes fold 2 > 4 > 1 (FileBackup.ps1:660). A set that throws is 4.
- `-WhatIf` on Backup is refused with 2.
- The container `exec`s pwsh, so the exit code passes straight through. An unknown action word gives 2. Repair needs the explicit `FILEBACKUP_REPAIR`. Prune takes explicit names only.
- With the store mount missing, the non-root container cannot create `/store`, so the run gives 2 rather than backing up into the container layer.

## 4. Findings, most severe first

### F1. High: nothing in prune, repair or the kit refresh is flushed before it is relied on; a power loss, OS crash or write-cached unplug in the seconds afterwards can permanently lose a snapshot or the last copy of content

**Where**
- `Copy-ReHomedDataFile` copies (Engine:2561) and hashes the copy (Engine:2568, read back from the page cache, so it proves nothing about the disk). It publishes by rename (Engine:2592) with no flush.
- `Complete-PruneDeletion` then renames the target and deletes it (Engine:2657–2659).
- `Publish-PruneManifest` (Engine:2630) and `Repair-BackupStorageForm` (Engine:2102) rewrite **snapshot** manifests through `Write-Manifest`, which does `StreamWriter.Dispose` and then `File.Move(tmp, dst, overwrite)` with no flush (Common:1365–1406).
- `Remove-CommittedPruneResidue` deletes a `Pruning_<name>` folder unconditionally (Engine:2451).

**Steps (two mechanisms)**

(a) **A snapshot manifest becomes NULs (NTFS).**
1. GFS thinning prunes `Snapshot_T`, the newest snapshot naming content K. An older `Snapshot_S` still names K, so K is re-homed into S and S's MANIFEST.csv is rewritten by rename over the old one.
2. Power fails within the lazy writer's window (seconds) after that rename.

NTFS journals metadata only. The rename and the deletion of the old manifest can be on disk while the new file's data is not, and the unwritten range of the new file then reads as zeros. The result is a NUL-filled `MANIFEST.csv` for S.

S is write-once, and that manifest was its only record. Both restorers refuse S at the header check (exit 2), so **every state S held is permanently lost**. `Repair-BackupStorageForm` exposes any snapshot it rewrites in the same way.

(b) **The re-homed copy is lost after the source is deleted** (ext4 delalloc, or NTFS).
1. Same prune. The copy `S/<K>` is created and renamed to a name that did not exist before.
2. On ext4 the rename-over heuristic (`auto_da_alloc`) does not apply to a new name. The new file's data is written back only after about 30 s (dirty expiry), while the unlinks of T's files commit with the next journal commit, within about 5 s.
3. Crash in between: `S/<K>` is zero-length (NUL-filled on NTFS), and T's copy is gone.

**K is permanently lost** for every surviving state, because it was endangered, meaning that was the only copy. If only the commit rename survived, `Pruning_T` still holds K. But the retry of the same prune (HomeHub retries a prune that never returned) deletes that folder without looking (Engine:2451).

**Confidence**
- ext4 delalloc and NTFS lazy-written user data: high on the mechanism.
- ext4 protects (a), because `auto_da_alloc` covers rename-over. XFS does not. On exFAT nothing is ordered at all.
- Windows' default **Quick removal** policy for USB disks writes through, which mostly closes the unplug variant there.

**Likelihood is low**
- (a) The window is a few seconds per rewritten manifest, whatever the store size.
- (b) `Test-PoolResolves` sits between the copy and the delete. On a small or medium store it takes seconds, so the window is open. At HomeHub scale it takes minutes and usually closes the window, but prune OOMs there anyway (§6).

**Permanent.** No later run rewrites a snapshot, and the source no longer holds superseded content.

**Why not R1 or accepted:** it takes one power loss, and the brief names power loss "including in the seconds after a run has returned". AGENTS.md §4 accepts an unflushed rename only for the **latest** manifest, which the next run repairs from the source. A snapshot manifest and a re-homed last copy have no such repair. The accepted "snapshot manifest losing rows" gap is media damage to a file written once; here the tool's own rewrite causes the loss.

**Smallest fix**
1. `Flush($true)` the staged copy (open a `FileStream` on the `.fbprune.tmp` and flush it) before `Move-Item` (Engine:2592).
2. Flush `MANIFEST.csv.tmp` before `File.Move` in `Write-Manifest` (use a `FileStream` with `Flush($true)` under the writer).

Both journals then order the later rename and unlinks after durable data. Revision 14 never shipped, so the Common change needs no kit bump (plan §13). Optionally, run `sync -f <store>` on Linux before `Complete-PruneDeletion`.

### F2. Medium (reproduced, with the kill's leftovers recreated): a prune killed while copying a re-homed archive leaves `<object>.fbprune.tmp` in the destination snapshot. Both restorers take it as the object, so a restore of that snapshot fails with exit 4, and the killed prune's `Temp/` keeps every later prune (and so the cleanup) from running

**Where**
- The staged copy is named `<dest>.fbprune.tmp` **inside the destination pool folder** (Engine:2560–2561).
- The SR-069 grammar takes any extension that starts with `.`, so `<hash22>_<len>.7z.fbprune.tmp` parses as key K in the engine (Engine:3970–3972, 3996–3999), in Common (Common:658–682, used by `Reconstruct.ps1`) and in bash (`reconstruct.sh:796–861`).
- The kit-14 name index lists the restore origin first (Reconstruct.ps1:1242–1245) and returns the first candidate that exists (Reconstruct.ps1:1304–1307).
- An archive-shaped candidate that will not expand becomes `hostfail`/`CandidateError` with no pool fallback (Reconstruct.ps1:1404–1410, 1627–1629; `reconstruct.sh:1500`).
- A hard kill skips the `finally` that removes `Temp/` (Engine:2850–2852). The next prune is refused as staging-busy (Engine:2310–2314), so `Invoke-PruneEntrySweep` (Engine:2825) never runs. Each backup run only warns about `Temp` (Engine:4228–4233).

**Steps (prune-residue-repro.ps1)**
1. A compressed store with three runs. `Snapshot_D2` holds the only copy of `f.txt` v1, and `Snapshot_D1` names it under a stale DataPath.
2. Before any prune, a restore of `Snapshot_D1` with its own kit gives **0**, resolving the row by name to D2's object.
3. Prune `Snapshot_D2`; it is hard-killed (SIGKILL, container stop, power) during the `Copy-Item` of that archive. The repro recreates exactly what that leaves: `changes\Temp\PRUNE.inprogress` and a half-written `D1\<obj>.7z.fbprune.tmp`.
4. A restore of `Snapshot_D1` now gives **exit 4**. The log shows `resolved by name index to '...\Snapshot_2026_01_01_01_00_00\<obj>.7z.fbprune.tmp'`, then `[CandidateError] f.txt — 7-Zip extraction failed`. The good copy in D2 is never tried.
5. Pruning again gives **2** (`[2/staging-busy]`). A backup run gives 0 and warns that `Temp` "may hold the only copy of superseded content".

**Permanence and scope**
- Self-healing only after a person moves `Temp` aside (README's procedure) and prunes again. `-RepairStorage` also happens to move the residue into Verify/ as a duplicate.
- Until then that snapshot does not restore that file, with a "host problem, retry" code that a retry cannot clear. No content is lost.
- A complete residue (a kill during verification) restores correctly. A NUL or zero-length residue (power loss) falls back to the content scan.

**Why not R1:** one kill of a normal retention prune. Re-homing into an older snapshot is the ordinary GFS-thinning case.

**Smallest fix:** stage the copy where no index looks, inside the prune's own `Temp/` (one mount by R8, so the publish is still a rename), or give it a name the grammar rejects (a leading `.fbprune-`). Also let the prune, while holding the OS lock, remove a `Temp/` that holds only `PRUNE.inprogress` and `.fbexpand-*`.

### F3. Medium (reproduced): `-Action Verify -RepairStorage` moves objects out of the pool without the OS lock, and also under `-WhatIf`

**Where**
- `Invoke-VerifyAction` runs `Get-StoreObjectFinding` and then `Move-StoreObjectToVerify` with no lock (FileBackup.ps1:520–535; Engine:1831–1885). The lock is first taken later, inside `Repair-BackupStorageForm` (Engine:2015–2018).
- Under `-Deep`, a duplicate's kept copy is not re-checked before the move (`KeptVerified`, Engine:1778 and 1852).
- `Move-StoreObjectToVerify` does not honour `-WhatIf`.

**Steps**
- `verify-lock-repro.ps1`: another process holds `Temp.lock`, standing in for a running prune or backup. `Verify -RepairStorage` still **moved the duplicate into `Verify\`**, then logged "Refusing to repair the storage form: ... **Nothing was touched.**" and exited 2.
- `verify-whatif-repro.ps1`: `Verify -RepairStorage -WhatIf` **moved it** and exited 0.

**How content leaves the pool**
1. `-Deep -RepairStorage` runs for hours on a large store. It keeps copy A of K (in the newest snapshot holding it) and will move duplicate B, which is in an older snapshot that names it.
2. Meanwhile a prune of A's snapshot plans with B as supply, so it re-homes nothing and deletes A.
3. Verify then moves B. K is now only in `Verify/`, which no restore reads, and the same Verify's final pool audit reports `PoolUnresolvable`.

This can be recovered by hand until the Owner empties `Verify/`, as the log tells him to.

**Why not R1:** the brief rules out concurrent runs *because there is an OS lock*. This path does not take it, so the exclusion that AGENTS.md §3 and README promise ("-RepairStorage ... holds an exclusive lock for as long as it runs") does not hold. A dry run that moves objects is a wrong outcome on its own.

**Smallest fix:** take `Enter-StoreMutationLock` in `Invoke-VerifyAction` before the object audit whenever `-RepairStorage` is set, and hold it through the moves and the repair. Skip the moves under `-WhatIf`. Check `Test-Path $f.Kept.Path` right before each move.

### F4. Medium (reproduced): every backup fails with 4 while a restore started from the backup root is still open, because `New-ReconstructScript` rewrites the loaded `System.IO.Hashing.dll` in place

**Where**
- `New-ReconstructScript` runs at step 3 of every run (Engine:6154) and `Copy-Item -Force`s all seven kit files over themselves, identical or not (Engine:2915–2965).
- A restore imports the bundled Common and loads the bundled DLL from the backup root (Common:345–351, called by `Get-FileXxHash`).
- The README's restore is to double-click `RECONSTRUCT.cmd` in the backup folder, which "holds the window" (README:125–127; Reconstruct.ps1:200–226, 1692). Windows will not overwrite a mapped DLL.

**Steps**
- `dll-lock-repro.ps1`: overwriting the loaded DLL fails with "being used by another process".
- `restore-blocks-backup.ps1`:
  - run 1 gives 0;
  - with a process holding the backup root's DLL as the restorer does, run 2 gives **4**: "did not finish because it stopped: The process cannot access the file '...\backup\System.IO.Hashing.dll'";
  - once that process ends, run 3 gives 0.

**Effect:** no backup is made while a restore window is left open, which can be days. Self-healing.

**Related:** the copy is truncate-then-write. A truncated or NUL-filled `RECONSTRUCT.ps1` in a snapshot can come from power loss after step 3, which copies the kit into `Building_D`, or from `-RefreshKits`, which overwrites in place (Engine:2169). `Get-BackupKitRevision` then reads 1 (Engine:1500–1509), and two things follow:
- `Test-PoolResolves` refuses every prune for that snapshot's stale rows (kit below 4, Engine:1139–1148);
- Verify counts the same rows only as an INFO line (FileBackup.ps1:559–568) and exits 0, so prune refuses while Verify reports clean. Only `-RefreshKits` clears it, and nothing tells the user to run it.

**Why not R1:** a documented restore path plus a scheduled backup. The restorers deliberately take no lock.

**Smallest fix:** copy a kit file only when its bytes differ (compare length and hash), write it through a temp file and a rename, and log a failed overwrite of an identical file as a warning rather than stopping the run.

### F5. Medium (reproduced; the precondition stands in for an older engine's mislabelled object): a kill between `-RepairStorage`'s rename and its manifest rewrite permanently wedges retention and makes Verify report false data loss

**Where**
- Objects are renamed per DataPath group (Engine:2065–2078); the folder's manifest is written once, after all of them (Engine:2099–2103).
- After a kill, the renamed object is named by no row, so it is not supply (Engine:714–720). Its rows become `broken-pool` with `BytesSurvive=False` (Engine:1112–1149), `DanglingDataPath` (Engine:1355–1362) and `Unreferenced` (Engine:1464–1476). None of those is repairable.

**Steps (`repair-kill-repro.ps1`)**
1. A snapshot row whose name and `Compressed` column claim the archive form over raw bytes (`FlagOverRaw`). That is the class `-RepairStorage` exists for, in stores continued from older engines.
2. The repair is killed (by the manifest-write seam) after the rename and before the publish.
3. Then:
   - `Test-PoolResolves` reports 2 rows `broken-pool BytesSurvive=False`;
   - re-running the repair gives "repaired 0; skipped DanglingDataPath, Unreferenced";
   - a backup run changes nothing;
   - `Prune -WhatIf` of another snapshot gives **2**;
   - Verify reports `PoolUnresolvable` ("no bytes for this row anywhere in the pool") and exits 1;
   - a restore of that snapshot gives **0** with the right bytes.

**Window:** each folder with rename findings, from the first rename to the end of a roughly 20 s manifest write at 180k rows. A power loss in the same window does the same, or worse (F1).

**Permanent** for a snapshot folder, until someone edits it by hand. The latest state heals on the next run (C20).

**Why not R1:** one kill of the documented repair, on a store continued from an older engine (in scope).

**Smallest fix:** let a row whose DataPath is missing take a same-prefix file (`<hash22>_<len>*`) in its own folder as supply (`Get-BackupContentIndex`), and have `Repair-BackupStorageForm` re-point such a row. That makes the repair idempotent across a kill.

### F6. Low (reproduced): wrong exit codes, and no mail, when the entry point fails before or around the set

**Where**
- `Initialize-Dependencies` runs unguarded (FileBackup.ps1:408). Its throw for a missing 7-Zip when a set compresses, or a missing hashing package under `-NonInteractive` (Engine:311, 345–348; Common:365), escapes, so `pwsh -File` exits **1**. The help says 2 (FileBackup.ps1:203–210).
- The mail block is never reached, so the Windows Owner gets no "Failed" mail.
- `Invoke-RetentionAction` resolves paths with the backup resolver, which requires `SourcePath` (FileBackup.ps1:436, outside any try; Engine:3811–3813).

**Steps (`entry-codes-repro.ps1`)**

| Situation | Exit | What the code claims |
|---|---|---|
| Backup with 7-Zip missing | 1 | "files not captured" |
| Verify with 7-Zip missing | 1 | "findings" |
| `Snapshots` with the source offline | 1 | |
| `Prune` with the source offline | 1 | "batch incomplete, no data lost"; the snapshot was not removed |

A missing store drive under Prune also gives 1 rather than 4.

**Plausible triggers:**
- a scheduled task under an account with no `System.IO.Hashing` package;
- a library drive offline at retention time;
- a HomeHub maintenance container that does not mount `/source`. In that case every prune does nothing and reports 1.

**Smallest fix**
- Wrap `Initialize-Dependencies`: log it, attempt the mail, `exit 2`.
- Use `Resolve-BackupSetPaths -ReadOnly` for Prune and Snapshots, inside a try that maps `DriveNotFoundException` to 4 and anything else to 2.

## 5. What was not done, and why

- Pester and Run-All were not run, per the brief.
- No real power cut, OS crash or VM crash test was run for F1. The claims rest on the documented behaviour of NTFS (metadata-only journal, lazily written data, valid-data-length zeros) and of ext4 (data=ordered, delalloc, `auto_da_alloc` only for rename-over and truncate). The confidence in each is stated there.
- F2's and F5's kills were simulated. F2 recreates the files a SIGKILL during `Copy-Item` leaves. F5 throws the Common manifest-write seam, as the suite does. F5's precondition (a name that lies about its form) was made by hand, standing in for an older engine's output, which the current engine does not produce.
- F3's loss interleaving with a concurrent prune was reasoned, not timed. The repros prove only the missing lock and the `-WhatIf` mutation.
- No container or Linux run was made.
- Performance and memory at HomeHub scale were not measured (see §6).
- The backup-run and restorer internals were read only where they consume my slice's artifacts.

## 6. Open questions for the caller

1. **Outside my slice, for the run reviewers.**
   - The F1 mechanism also hits `Publish-PriorStateSnapshot`. It writes `Building_D/MANIFEST.csv` as a **new** file (ext4: no `auto_da_alloc`; NTFS: lazy write), renames the folder to `Snapshot_D`, and the run goes on (Engine:4975–4985). If power fails in the following ~5–30 s, `Snapshot_D` survives with an empty or NUL manifest.
   - The next run then keeps "an existing Snapshot_D" as is (Engine:4970–4973) and overwrites the latest manifest. State D is lost permanently.
   - A NUL **latest** manifest is refused with 2 ("foreign header"), not "repaired by the next run" as AGENTS.md §4 says.
   - Did the run reviews cover this?
2. **Known, still open, and on the resume path.** `docs/status.md:233–235` already records that prune and the other `-IncludeManifests` callers hold every manifest whole, and that prune would OOM on the hub. On top of that:
   - `Remove-BackupSnapshot` holds two such indexes at once: the plan's, and `Test-PoolResolves`' inside `Assert-PrunePrecondition`.
   - A plain `-Action Verify` holds one (about 11 GB at the measured 26 manifests).
   - Resume item 3 in status.md ("run a plain `-Action Verify` once" on HomeHub's continued store) would therefore swap-thrash the 7.6 GB hub, which was the 2026-10-04 outage mechanism. Should that step wait for the lean index?
3. **F5's precondition:** does HomeHub's continued store contain any rename-class findings (`FlagOverRaw`, `FlagOverArchive`, `NameLies`) in snapshot folders? A plain Verify answers this, but see question 2.
4. **F6:** does HomeHub's retention or maintenance container mount `/source`? If not, every prune is a no-op that exits 1.
5. **F1 scope (ruling question):** is "no fsync" accepted for the operations that rewrite write-once snapshots or delete a last copy? AGENTS.md §4 accepts it only for the latest manifest, where the next run self-heals.
