# Design note: recovering a killed run's staging folder (Temp)

Status: REVISED 2026-10-09 after adversarial review; recommendation replaced. REVISED AGAIN
2026-10-09 after an independent review (two findings, below), and on 2026-10-10 after a second
review (six items, below). Design only. No code, no repo
change. All facts read with `git show <branch>:<path>` on C:\Projects\FileBackup; that working
tree was not touched.

Cite key (branch New_Fix_Batch, line numbers from that blob): `E:` = Modules/FileBackup.Engine.psm1,
`C:` = Modules/FileBackup.Common.psm1, `F:` = FileBackup.ps1, `DR` = docs/defect-review-2026-10-05-content-index-memory.md.
`E′:` = Engine re-verified against `fix-staging-os-lock` (058ffc5, which carries P as well);
`C′:` = Common re-verified against `fix-p-atomic-write-manifest` (23793f3; byte-identical on
`fix-staging-os-lock`). Line numbers marked `~` were read by context, not exact.
`PS:` = PowerShell `src/System.Management.Automation/namespaces/FileSystemProvider.cs` at tag
v7.5.0; `NET:` = dotnet/runtime at tag v9.0.0, under `src/libraries/System.Private.CoreLib/src/System/IO/`
(`File.cs`, `FileSystem.Unix.cs`, `FileSystem.Windows.cs`), plus
`src/libraries/Common/src/Interop/Windows/Kernel32/Interop.MoveFileEx.cs`. Line numbers are from
the raw files at those tags.

### Revision 2026-10-10 (round 4, review of a935023)

The review confirmed the rest and raised two items. Both are valid, both were applied, and both
cost something in recovery only.
1. **G11's check was unsound** (3.2 row 2).
   - The flaw: power loss can keep step 12's new root manifest and lose the root's witness
     replace. The OLD witness then still equals Temp's, and round 3 discarded the only prior
     index.
   - Now: the root manifest is verified against its own witness, the same check as the 1.5
     gate, before any discard that relies on the root. Temp's `.meta` must then equal the root
     witness. When Temp has no `.meta`, Temp's `MANIFEST.csv` is hashed against the root's
     digest instead.
   - A Temp with no manifest at all is discarded without a check.
   - The `Written` variant for G8 (c) is withdrawn and replaced by a pre-run digest in the owner
     record.
   - Cost: one manifest read and hash on that branch, plus a second one only when Temp's `.meta`
     is absent.
2. **The barrier now covers retained destinations** (3.2 step 3a, 3.3; G13).
   - The flaw: an "already exists" destination may be an earlier pass's unflushed copy.
   - Now, on Windows, it joins the flush set whatever the current probe says, and a failed
     flush keeps RECOVERY.done unpublished. On Linux the single `syncfs` already covered it.
   - Cost: recovery only, bounded by Temp's data-file count.

### Revision 2026-10-10 (round-3 confirmation, a6fb66d)

The round-3 confirmation found all six round-2 fixes consistent for kills and throws. It raised
three items, applied as the coordinator triaged them under the Owner's balance rule: protect
against real data loss, add no I/O to normal runs, and do not design for vanishingly narrow
windows.
1. **Durability: accepted narrowly (G10).**
   - ONE batched barrier per rollback, after every restore and before RECOVERY.done (3.2 step
     3a). On Linux it is `sync -f <BkpPath>`, which is `syncfs`. On Windows it is
     `FlushFileBuffers`, on the volume or on the restored files.
   - Rejected: a per-file fsync on Linux, and any fsync on normal runs. The round-2 flush of
     RUN.state is therefore WITHDRAWN.
   - Verifying the "tamper guard catches a lost RUN.state" reasoning found a real hole (G11).
     For a run that moved nothing there are no data files for the guard to see. Row 2 now also
     checks the root witness against Temp's: two small reads, in recovery only.
2. **P2 under power loss on ntfs-3g: documented as an accepted residual (§10), not redesigned.**
   - The residue pattern was read from the driver source: `<name>.ntfs-3g-<10 digits>`.
   - Classification recognises the residue and names it, and never deletes it.
   - The hub's driver (ntfs3 or ntfs-3g) must be confirmed at build time.
3. **Probe residue: accepted (G12).**
   - The probe has a fixed name, and every row of classification accepts it as residue.
   - Both exact probe paths are removed on success, on failure, and in cleanup before
     RECOVERY.done is deleted, whatever the saved enumeration says.
   - A §6.2 row and a §7 test are added.

### Revision 2026-10-10 (second review, d4a95b3)

A second review of d4a95b3 returned MERGE AFTER FIXES. Each item was checked against the code and
the runtime sources before it was applied. All six were applied; none was pushed back.
1. **G8 is now a BUILD BLOCKER** (§4, §6.1). The recovery build may not start until the Owner
   decides G8. Option (c) is recommended, and what it changes about healing is listed. This
   design does not decide it.
2. **An interrupted no-op discard failed row 4's witness checks** (§3.2 row 4). Row 4 now acts on
   RUN.state's complete discard decision BEFORE it reads Temp's manifest or witness.
3. **`RECOVERY.done.tmp` was missing** from row 2's set and from cleanup's set (§3.2, §3.5). It is
   now in both, as an unpublished record, with no extra filesystem pass.
4. **P2, a new prerequisite** (§5). Atomic witness replacement. `Move-Item -Force` overwrites by
   deleting the destination and then moving (PS:5980-5993). So a kill between the two leaves NO
   witness, and at step 13 row 4 would refuse beside only-copy data. The boundary is added to §6
   and §7.
5. **Runtime-level probes are counted** (§3.3, §7). "No additional application probe" is now
   kept apart from "no probe". Verifying this item found a further defect: both runtimes' file
   move silently degrades to copy-then-delete across volumes (NET Interop.MoveFileEx.cs:35,
   `MOVEFILE_COPY_ALLOWED`; NET FileSystem.Unix.cs:197-201 and 235, EXDEV and link fallbacks). A
   kill during that copy can leave a torn object at its FINAL root name, which 3.3's "exists ⇒
   redundant" rule would then treat as safe. Fixed in 3.3 with a one-time rename probe, run once
   per recovery.
6. **RUN.state publication is fail-closed** (§3.2): a failed publish aborts the run before any
   mutation. The SchemaVersion-1 refusal is marked as conditional on Owner decision (d)
   everywhere it appears.

### Revision 2026-10-09 (review)

An independent review raised two findings. Both are valid; both are fixed here.

1. **Rollback had no durable end state.** §3.2 rollback deleted RUN.inprogress last, and the
   marker-absent branch then read "marker gone" as "step 12 completed". Worse than the review
   stated: the rollback had no step that removed Temp at all, so even an uninterrupted rollback
   was followed by a roll-forward that published a spurious Snapshot_* of the rolled-back root.
   Fix (§3.2, §3.5): recovery never deletes a marker inside Temp. A rollback ends by publishing
   a `RECOVERY.done` record, and only then deletes Temp's leaves, the record last. The pipeline's
   own no-op discard (E′:6209) has the same window and gets the same record-last order.
2. **Step 7's manifest/witness pair under P.** With P, a kill between the manifest rename
   (C′:1284) and the witness publish (C′:1293, C′:1385-1386) leaves a complete Temp manifest with
   no witness. §3.2 refused that, which sends it to a person; D8 forbids that. Fix (§3.2): the
   G1 record (`RUN.state`) moves to just before step 10. With the marker present and no
   RUN.state, the run died before any pool mutation, so Temp is redundant and is discarded.
   This needs no witness and no hash. The same gap exists at step 12 and step 13 (handled, G7)
   and at step 6 (flagged, G8). The coordinator's line "with P, roll-forward can always proceed"
   was wrong for step 13 and is corrected.

Also folded in: the Owner's speed constraint (store behind an NTFS translation layer; no repeated
path probing). Every design change below has a **Cost** line, and §3.3 drops the per-object
re-hash the earlier draft implied. Two existing probing patterns are flagged: E2's aside folder
and the per-row `Test-Path` at E′:6219 (E7). §2.2 is corrected: one Remove-OwnStagingFolder
caller runs after step 7. New gaps G5-G9 are in section 4. §6 gains the P-era pipeline rows and
a table for recovery's own kill points. §7, §8, §9 and §10 are extended to match.

## 1. Problem

Owner ruling, DR §4 item 6 (lines 180-187): "recovering this by hand every time is not
acceptable. FileBackup must recover a killed run's staging cleanly by itself." A killed run
"must never lose the superseded bytes it was preserving." It gates the HomeHub watchdog's
reboot phase (P4).

A run killed after step 7 leaves Temp with content. `Get-StagingLockState` classes any entry
other than RUN.inprogress as HoldsContent (E:3296-3299), tested before the age test, so a stale
marker does not help. Only Empty and OwnerStale are reclaimable (E:3259). Every later run refuses
until a person follows the manual README procedure.

## 2. Facts found

### 2.1 What each step writes

- E:6371 `Initialize-StagingFolder` (E:5231) takes the marker lock and creates Temp. Nothing
  before it mutates the store.
- E:6482 step 6: `Test-BackupManifest` (E:837) throws on a legacy, pre-WP12 or retired-grammar
  store before any write. On success it writes the BACKUP ROOT manifest unconditionally (E:922).
  No Temp copy exists yet.
- E:6498 step 7: sanitized prior manifest written into Temp (`Write-Manifest`, in place).
  E:6504 copies the prior DIRECTORIES.csv into Temp. Re-verified against fix-staging-os-lock:
  E′:6874 and E′:6878-6880. Under P the write is: Export-Csv to `MANIFEST.csv.tmp` (C′:1275),
  `[IO.File]::Move(tmp, MANIFEST.csv, $true)` (C′:1284), then the witness (C′:1293), itself
  `.meta.tmp` (C′:1385) then `Move-Item -Force` (C′:1386). Temp is created fresh by step 3,
  so before C′:1386 Temp has **no** `MANIFEST.csv.meta` at all. A kill there reads as witness
  `Absent`, not Mismatch.
- E′:6909 (E:6533) computes `$manifestChanged`. It is final there, before step 9.4 (E′:6916-6929)
  and before step 10. Nothing later reassigns it.
- Step 9.4's capacity refusal (`$refuseCapacity`, defined E:6469, invoked E:6553; E′:6845, E′:6929)
  calls `Remove-OwnStagingFolder` AFTER step 7. That routine deletes the leaves by exact name,
  the marker LAST, then a non-recursive rmdir (E′:4527-4542).
- E:6573 step 10: `Invoke-BackupFileGroup` writes new objects directly at content-addressed
  final names: 7-Zip direct (E:811), `Copy-Item -Force` (E:824). No temp-and-rename.
- E:6587 step 11: `Move-RemovedFilesToStaging` (E:5720) MOVES removed files' pool objects into Temp.
- E:6605 step 11.5: `Save-SupersededData` (E:5798) MOVES superseded objects into Temp.
- E:6533: `$manifestChanged` is computed from the SOURCE diff (NewOrChanged or RemovedFromSource),
  not from a comparison of manifests.
- E:6636 step 12: backup root manifest rewritten IN PLACE (`Export-Csv -LiteralPath`, C:1233).
  The witness follows: tmp write (C:1327) then `Move-Item` (C:1328). C:1291 says atomicity covers
  the witness only. Re-verified against fix-staging-os-lock: E′:7012. Under P the manifest is
  published by rename (C′:1284) and the witness still follows it (C′:1293). The order is kept on
  purpose (C′:1349-1354; AGENTS §4). So a kill between the two leaves a COMPLETE new root
  manifest beside the prior run's witness: Mismatch, and the 1.5 gate (E′:6711-6718) refuses it.
- E:~6650 step 12.5: root DIRECTORIES.csv overwritten (the root copy is now the new state).
- E:6666 step 12.9: `Assert-StagingLockOwned` (fence), E:6667 heartbeat stop, E:6669
  `File.Delete` of RUN.inprogress. **After E:6669 there is no assert, no heartbeat and no marker
  until the rename.**
- E:6681 step 13: `Complete-ChangeFolder` (E:5813). If no-op or first run, E:5853 deletes Temp.
  Otherwise E:5859 reads the Temp manifest, E:5865 blanks absent DataPaths and rewrites the Temp
  manifest IN PLACE, E:5873-5882 copies the kit, E:5895 `Rename-Item` Temp -> Snapshot_*.
  Re-verified against fix-staging-os-lock: call E′:7061, function E′:6169. The no-op discard is
  E′:6209: `Remove-Item -Recurse -Force -ErrorAction SilentlyContinue`, so it is non-atomic and
  silent on failure. Read E′:6215; the blank loop runs one `Test-Path` **per manifest row**
  (E′:6216-6220); rewrite E′:6221 (under P: rename, then witness); kit E′:6229-6239; rename E′:6254.
- E:~6334: `priorBackupDate` is read before any write; LastBackupRun is written only after finalize.

### 2.2 Owner record, heartbeat, fence

- Marker E:2826; stale floor 1800 s (E:2831); heartbeat 60 s (E:2837); confirmation sample 90 s (E:2851).
- `Write-StagingOwnerRecord` E:2916 (CreateNew, written once). Heartbeat E:3512 / E:3567.
- `Assert-StagingLockOwned` (E:4459) is called before steps 7, 11, 11.5, 12, 12.9
  (E:6496, 6586, 6604, 6635, 6666). **It is not called after E:6669.**
- `Get-StagingLockState` (E:3195-3346) is pure. `Invoke-StagingLockReclaim` (E:4015-4170) is the
  I/O shell: second sample after the wait (E:4100-4101), aside move (E:4128), identity re-check (E:4146).
- `Get-StagingEvidenceSignature` (E:3796) compares state, reparse flag, enumeration failure,
  directory mtime, marker mtime and entry names. A live run that is quiet for 90 s (huge
  Read-Manifest or Export-Csv in place, suspended VM, AV stall) looks identical to a dead one.
- `Remove-OwnStagingFolder` (E:4275) keeps any folder holding data; its callers (E:6411, 6457,
  6471, 6487) all run BEFORE step 7. After step 7 nothing removes Temp on failure.
  **Corrected (review, G9):** E:6471 sits lexically before step 7, but it is the body of
  `$refuseCapacity`, which is invoked at step 9.4 (E:6553), after step 7. So a capacity refusal
  after step 7 deletes Temp's manifest, witness, sidecar and `MANIFEST.csv.tmp`, then the marker,
  then the folder (E′:4480-4542). What stays true is that nothing removes Temp on failure after
  step 9.4.
- Owner record `SchemaVersion = 1` (E′:3063).
- Under P the Temp classifier ignores `MANIFEST.csv.tmp` by exact name (E′:3389). It does NOT
  ignore `MANIFEST.csv.meta.tmp`, which a kill inside C′:1385-1386 leaves.
- The change-root consumers filter by `ChangeFolderRegex` (E′:1041-1043, E′:1114-1116). A
  `Temp*` name is invisible to them.

### 2.3 Other facts that bear on the design

- The change-folder root is scanned for DIRECTORIES only (`Get-ChildItem -Directory`, E:1034,
  E:1107). A plain lock file at the ChgPath root is invisible to those enumerators.
- Prune takes the same Temp lock and writes PRUNE.inprogress (E:2673). Everything before its
  commit is additive. Its commit is the Rename-Item to Pruning_ (E:2535). **Prune never moves the
  only copy of anything before commit. Backup steps 11 and 11.5 do.**
- `-Action` values (F:230) and `-RepairStorage` (F:236) cannot recover a killed Temp.
  `Repair-BackupStorageForm` (E:1874-2020) never references Temp or staging.

### 2.4 Requirements and tests

- SR-017: a Temp with content "shall remain a refusal, unchanged." Changing it needs an SR amendment.
- SR-075 (owner record, heartbeat, classifier); SR-038 (witness); SR-059 (objects are name-proven).
- LLR-017 and LLR-080 list the functions above.
- TC-188 asserts refusal of a stale marker plus data, hashes unchanged ("the only physical copy").
  It flips to "recovered". TC-186, TC-187 (live owner), TC-202 (finalize), TC-204 (RunId swap) are re-read.
- No test covers a kill inside steps 7-13 with a recovery expectation.
- README manual step (4) copies moved-aside data "under any non-colliding names". That conflicts
  with SR-059 and must not be automated.

## 3. Adopted design

### 3.1 Liveness by OS lock, not folder content

A run holds an exclusive lock file OUTSIDE Temp, e.g. `<ChgPath>\Temp.lock`, opened with
`FileShare.None`, for its whole lifetime:
- taken BEFORE `Initialize-StagingFolder` (before E:6371);
- released only after `Complete-ChangeFolder`'s rename returns (E:5895), or in `finally`.

A kill releases it automatically, because the OS closes the handle. Recovery opens the lock
non-blocking. Any failure, including a sharing violation from AV, means LIVE, and recovery refuses.
The existing heartbeat, owner record and ~90 s sample remain as a fallback where locking is
unavailable.

Reason: from E:6669 to E:5895 nothing signals liveness (see 2.1 and 2.2), so a live run can look
dead. Recovery would then move Temp aside under a live run. That run would publish a Snapshot_*
holding the successor's content while recovery rolled the root back.

Prune and reclaim must take the same OS lock. Otherwise it excludes only recovery, not prune.

Re-verified against fix-staging-os-lock: the lock is taken at step 2.9 (E′:6736), before
`Initialize-StagingFolder` (E′:6746), and released last in the `finally` (E′:~7113). It is
taken AFTER the 1.5 witness gate (E′:6711-6718); see "Ordering against the 1.5 gate" in 3.2.
This revision does not change the lock.

### 3.2 Split recovery, keyed on the marker and two Temp-only records

*Revised 2026-10-09 (review).* The marker deletion at E′:7045 (E:6669) is still the pipeline's
commit record. The first draft also let the ROLLBACK delete it, and that is finding 1. Two small
Temp-only records now carry the states the marker cannot: `RUN.state` (the G1 record, moved) and
`RECOVERY.done` (new). Both are published like the witness, `.tmp` then rename, so a reader sees
each one either absent or complete. A torn `.tmp` counts as absent. The names are provisional.

Recovery runs only while it holds the OS lock (3.1) and Temp exists. It uses the ONE enumeration
of Temp the classifier already makes (E′:3283) and reads at most two small records. It never
enumerates the pool and never re-hashes an object. The first matching row wins:

| # | Temp shows | Which means, by program order | Action |
|---|---|---|---|
| 1 | `RECOVERY.done` | an earlier recovery committed a rollback or discard; every leaf is redundant | cleanup only (3.5) |
| 2 | marker, no `RUN.state`, more than the marker | killed at or before step 9.4. Nothing in the pool has moved and the root manifest is step 6's | **discard** (below; 3.5) |
| 3 | marker + `RUN.state` | killed or threw in steps 10-12.9 | **roll back** |
| 4 | no marker, not empty | E′:7045 has run | **roll forward** |
| 5 | empty | — | existing Empty reclaim (E:3259) |

A marker alone, or with `MANIFEST.csv.tmp` only (E′:3389), stays the existing OwnerStale reclaim,
unchanged.

**Residue accepted by classification in every row (added 2026-10-10, round 3).**
- **Probe residue.** An empty directory with the exact name `.fbrecover-probe` (3.3) is set aside
  before any row's set test. A Temp holding nothing else is row 5: remove the probe
  non-recursively, then the folder. A NON-empty `.fbrecover-probe` was not made by recovery: keep
  it and refuse loudly.
- **ntfs-3g rename residue.** It matches `^<whitelisted name>\.ntfs-3g-\d{10}$`, for example
  `MANIFEST.csv.meta.ntfs-3g-0000000042` (§10). It is never set aside and never deleted
  automatically, because it can be the only name left for the OLD file. A row that meets it
  refuses, and NAMES it as ntfs-3g rename residue instead of reporting an unknown entry.
- Both are recognised by name within the enumeration already in hand.

**Missing RUN.state never leads to a discard unguarded (verified 2026-10-10).**
- Row 2 is the only row that discards on RUN.state's absence. It is guarded by the data-name
  check and by the root-verification check below (round 4: the root manifest verified against
  its own witness, not merely two witnesses compared).
- Row 3 requires RUN.state.
- Row 4, with RUN.state absent, PUBLISHES, so it deletes nothing.
- Row 4's discard branch acts only on a PRESENT RUN.state, and it refuses if a data-named entry
  appears.
- Row 1 acts only on a published RECOVERY.done.

**RUN.state (G1's record, now written before step 10).** The record is written ONCE, after the
step 9.4 capacity preflight (E′:6916-6929) and before step 10's first write. It holds `RunId`
(it must equal the marker's), `ManifestChanged` (final at E′:6909) and `SnapshotDate`
(`priorBackupDate`, so that roll-forward does not depend on FileBackupState.json).
- After 9.4, so `$refuseCapacity`'s `Remove-OwnStagingFolder` never meets it (G9).
- Before step 10, so its absence is a proof: marker present and no RUN.state means no step-10,
  11 or 11.5 write has happened, and no step-12 root rewrite.
- **Fail-closed (added 2026-10-10).** "Written before step 10" means *successfully published*.
  The publication goes in this order:
  1. Write `RUN.state.tmp`.
  2. `[IO.File]::Move(tmp, RUN.state, $true)`. That is a same-directory rename, never a
     cross-volume copy (3.3).
  3. Only after that returns does step 10 begin.

  Any failure along the way (a write error or a rename error) throws out of the set before step
  10, leaving Temp in the pre-mutation shape, which row 2 then discards. There is no fallback
  that continues without the record. If there were, the absence of RUN.state would prove
  nothing.
- **No fsync of RUN.state (revised 2026-10-10, round 3).** a6fb66d added `FileStream.Flush($true)`
  at step 1. That is an fsync on every normal run, and it is withdrawn.
  - A process kill or throw does not need it: the OS cache outlives the process, so a returned
    rename is visible to the next run.
  - Power loss is the only case it would serve. There, a RUN.state that never became durable
    while later Temp moves did is caught by the guards in row 2: the data-name guard, plus the
    root-verification check (round 3, corrected in round 4) for a run that moved nothing. Both refuse rather than
    discard. That needs a person but loses nothing, which is accepted for a power-loss-only
    window (§10).
- It is deleted only by `Complete-ChangeFolder` (3.5) and by recovery cleanup, never while the
  marker exists.
- Upgrade: the owner record's `SchemaVersion` (E′:3063) goes to 2 when RUN.state ships, and RUN.state's absence means
  "pre-mutation" ONLY under a SchemaVersion-2 marker. A SchemaVersion-1 Temp, left by an older
  engine, is rolled back when its Temp manifest verifies (row 3 without the record). **What
  happens otherwise is Owner decision (d), still open.** The proposed answer is today's
  refusal. Nothing in this design prescribes it until (d) is decided.
- Cost: on a normal run, one ~200-byte write, one rename and one delete at finalize. There is no
  flush. In runtime calls, the rename adds one existence check of the source (NET File.cs:1050).
  For recovery, one small read.

**Row 2: discard (pre-mutation). Finding 2's step-7 case.** A kill between C′:1284 and C′:1386
inside step 7 leaves a complete `MANIFEST.csv`, no `MANIFEST.csv.meta`, and possibly a
`MANIFEST.csv.meta.tmp`. The same row covers kills in steps 8-9.4. It also covers a kill part-way
through the 9.4 refusal's `Remove-OwnStagingFolder`.
- Condition: every entry in the enumeration is in the pre-mutation set: `RUN.inprogress`,
  `MANIFEST.csv`, `MANIFEST.csv.tmp`, `MANIFEST.csv.meta`, `MANIFEST.csv.meta.tmp`,
  `DIRECTORIES.csv`, `RUN.state.tmp`, `RECOVERY.done.tmp`. Any other entry, such as a data file,
  contradicts program order. That is not a kill state, so recovery refuses loudly and moves
  nothing.
- `RECOVERY.done.tmp` (added 2026-10-10) is an UNPUBLISHED record: a discard or rollback was
  killed after writing it and before renaming it. It carries no meaning. The next publication
  overwrites it (`File.Move(tmp, RECOVERY.done, $true)` from a freshly written `.tmp`), and
  cleanup deletes it by name. It is recognised by name in the enumeration already in hand, so
  there is no extra filesystem pass. The same applies in row 3: a leftover `RECOVERY.done.tmp`
  is not a data file and is never moved.
- **Root-witness check (added 2026-10-10, round 3: a real hole, power loss only).** The
  data-name guard does NOT stand between a missing RUN.state and a discard in every case.
  - The case it misses: a run whose steps 11 and 11.5 moved nothing has no data files in Temp.
    If power loss lost RUN.state's rename while step 12's later root rewrite survived, row 2
    would see a pre-mutation shape and discard. Temp's manifest is then the only copy of the
    prior index, so the discard loses a restore point. No bytes are lost.
  - This can happen only where metadata is not committed in order. ntfs-3g, which has no
    journal, is the realistic case (§10).
  - **Revised 2026-10-10, round 4: the round-3 check was unsound.**
    - The sequence: an additions-only run reaches step 12, and P renames the new root manifest
      in. Power loss then keeps that rename, but loses RUN.state and the root's witness replace.
    - What remains: the root's OLD witness sits beside a NEW root manifest. That is the
      `Mismatch` pair §6.1 already lists. Temp's witness equals that old witness.
    - So round 3's test (b), "Temp's `.meta` equals the root's", passed and discarded the only
      prior index, though the root manifest differs.
    - Comparing two witnesses never looks at the root manifest. The round-3 `Written`
      alternative for G8(c) has the same flaw.
  - **The rule now.** Before a row-2 discard that relies on the root, verify the actual root
    manifest against its own witness, with the same `Test-ManifestWitness` the 1.5 gate runs on
    every normal run. Then:

    | Temp holds | Discard only if | Why |
    |---|---|---|
    | no `MANIFEST.csv` at all (killed before the step-7 rename, or after the 9.4 refusal deleted it) | always: no root check | Temp holds no index, so a discard cannot lose one |
    | `MANIFEST.csv` and its `.meta` | the root is `Verified` AND Temp's `.meta` carries the root witness's `Bytes` and `XxH128` | `Verified` proves those values describe the root's ACTUAL bytes. Equality then proves the root is byte-identical to what step 7 copied, so Temp is a redundant copy. |
    | `MANIFEST.csv`, no `.meta` (the step-7 kill, which is the common case) | the root is `Verified` AND the hash of Temp's `MANIFEST.csv` equals the root's verified `XxH128` | see the next paragraph |

    Anything else refuses loudly and moves nothing: the root is `Mismatch`, `Absent` or
    `Malformed`, or the digests differ. With P2, `Absent` cannot come from a kill after step 6.
  - **The no-`.meta` row, precisely.**
    - Under process kills and throws, which follow program order, a missing Temp `.meta` means
      the kill landed inside step 7's witness publish, so step 12 has not run. A `Verified` root
      is then the untouched step-6 manifest. Temp's `MANIFEST.csv` is a complete copy of it (P),
      so the discard is safe on the root check alone.
    - Under power loss, which can reorder, Temp's `.meta` can be lost while a LATER step 12
      survived COMPLETE. The new manifest and new witness are then `Verified` as well, and the
      root check alone would discard the only prior index.
    - Hashing Temp's `MANIFEST.csv` against the root's digest closes that. It costs one more
      manifest hash, on this sub-branch only.
    - Steps 6 and 7 write byte-identical files from the same `$backupDb` (E′:929, E′:6874), so a
      legitimate kill always passes.
  - **Under G8 option (c)** step 6 does not write the root, so the root keeps its PRE-RUN bytes
    while Temp holds the sanitized rows. The equalities above would then refuse legitimate kills
    on a healing run.
    - Under (c) the rule becomes: the root is `Verified` AND its `XxH128` equals a pre-run digest
      recorded in the owner record at step 3.
    - Recording it costs no I/O: the 1.5 gate (E′:6712) has already read the root witness, and
      the owner record is written anyway (E′:3063-3071). `Test-ManifestWitness` would have to
      return the digest.
    - A root that had no witness at run start (a pre-SR-038 store) records none. Row 2 then
      refuses, once, until a run completes.
    - G8 must carry this change. It replaces round 3's `Written` comparison, which is withdrawn.
  - Cost, recovery only and on this branch only: one read and hash of the root manifest, the
    same cost as the normal run's 1.5 gate. Add a second manifest hash, of Temp's copy, only when
    Temp's `.meta` is absent. Plus two reads of files of about 150 bytes. Nothing on a normal
    run.
- Action: publish `RECOVERY.done` (Outcome=Discarded), then clean up (3.5). The root is not
  touched. A discard restores nothing, so it needs no durability barrier (row 3, step 3a).
- Why no witness is needed: the Temp manifest is a copy of the root's. Step 6 wrote the same
  `$backupDb` object to the root one statement earlier (E′:929 returning to E′:6858, then
  E′:6874), and nothing mutates it in between. Temp holds no bytes, and the root has not been
  rewritten since. So Temp is redundant whatever state its manifest/witness pair is in. Temp's
  OWN witness verdict never enters the decision. The ROOT's verdict does (round 4, above),
  because it is what proves "rewritten since" did not happen.
- **Is data-file absence alone a sound signal? No.** (i) A run whose steps 11 and 11.5 move
  nothing keeps Temp data-free all the way through step 13. Step 12 has replaced the root by
  then, and Temp's manifest is the ONLY copy of the prior index; discarding there would lose a
  restorable point in time. (ii) A cross-volume move killed mid-copy (E5) leaves a data-named
  partial file although no move completed. Absence of data proves only "Temp holds no only-copy
  bytes". RUN.state's absence is what proves "the root is still the index Temp copied". The
  name check stays as a tamper guard, not as the signal.
- Rejected: a separate "step 7 complete" marker. It would be a second write with its own kill
  window, and RUN.state already dates every kill before step 10.
- Cost: the classifier's enumeration and marker read, plus the root-verification cost above
  (round 4). That is one root-manifest hash, and a second hash only when Temp has no `.meta`.
  Then one record write, at most 9 deletes (the 8 names of the set plus RECOVERY.done) and one
  rmdir. Recovery only.

**Row 3: roll back.** Precondition: the Temp manifest verifies against its own witness. With
RUN.state present, the step-7 witness was published before the record, by program order. So
`Absent` or `Mismatch` here is not a kill state: refuse loudly and move nothing. That is the
first draft's rule, now correctly scoped. The steps:
1. Move every Temp data file back to `BkpPath\<leaf>` (3.3). The pool is flat and Temp keeps the
   DataPath as the leaf name (E′:6068-6076, E′:6148-6154). A data file must be named by a Temp
   manifest row; that manifest is read once, for step 2 anyway.
2. Restore the root manifest with `Write-Manifest -FolderPath <BkpPath> -Records <Temp records>`.
   The root is then published atomically (P) and witnessed by the sole writer. AGENTS §3 forbids
   copying a `.meta` between folders. Copying MANIFEST.csv alone would leave the killed run's
   witness beside it. **Rollback never reads the root witness.** The root is replaced, not
   trusted. That is what makes step 12's manifest/witness gap, and this step's own, harmless
   (G7).
3. Restore the root DIRECTORIES.csv from Temp (tmp then rename). If Temp has none, because the
   root had none at step 7, delete the root's: step 12.5 may have written one.

   3a. **Durability barrier: ONE per recovery (added 2026-10-10, round 3).** It runs after every
   restore in steps 1-3, and before RECOVERY.done is published, and so before cleanup deletes
   any Temp source.
   - The case it closes: the copy branch (3.3) writes an object's bytes to the root. Cleanup
     then deletes the Temp source. Power loss before the copied bytes are durable would lose the
     only copy. The same reasoning applies to the root manifest, which cleanup's deletion of the
     Temp manifest leaves as the only copy of the prior index.
   - Linux: one `sync -f <BkpPath>`, run as a process. That is `syncfs(2)` on the store's
     filesystem (coreutils 8.24 and later) and covers every restored file, its directory entries
     and the root manifest, witness and sidecar. .NET has no `syncfs`, and `Add-Type` to
     P/Invoke it costs a compile. The container image must ship a `sync` that accepts `-f`;
     that is checked at build time (§10).
   - Windows: `FlushFileBuffers`, via `FileStream.Flush($true)` on a handle opened for write.
     There are two ways to apply it:
     - On the volume of BkpPath, where the account may open the volume handle. This needs
       administrator rights, which are not assumed.
     - Otherwise, on the FLUSH SET. That is: each file the copy branch restored in this pass;
       each destination RETAINED through the "already exists" branch in this pass, whatever
       the probe said this time (round 4, below); and the root `MANIFEST.csv`, its `.meta` and
       `DIRECTORIES.csv`. Windows has no unprivileged whole-volume barrier, so this is the
       coordinator's "FlushFileBuffers on the restored files".
     - If any flush fails, including a destination that cannot be opened for write, RECOVERY.done
       is NOT published. The Temp sources are kept, and the next pass retries. The barrier fails
       closed.
   - A plain rename needs no flush of its own. A rename that power loss undoes leaves the object
     in Temp, where it is still present.
   - **Retained destinations are NOT "long durable" (revised 2026-10-10, round 4).** Round 3
     argued that "exists" always meant the root original. That is wrong across passes:
     1. A transient probe failure, such as an antivirus handle on the probe, selects the copy
        branch.
     2. A copied object is published at its root name.
     3. A kill lands before the barrier.
     4. The next pass's probe succeeds. Its rename meets the existing destination and retains
        it.
     5. A Windows flush set holding only this pass's copies would skip that file. Cleanup would
        then delete the Temp source, and a later power loss could lose the unflushed copy.

     So every destination retained through "already exists" in this pass joins the flush set.
     The pass cannot tell an earlier pass's unflushed copy from an old original without
     recording something, and flushing an already durable file is cheap.
     - On Linux the single `syncfs` already covers every file on the store's filesystem,
       retained destinations included, so Linux needs no change.
   - Rejected: a per-file fsync on Linux, and any fsync on normal runs, including RUN.state's
     (see above).
   - A kill or power loss before the barrier completes leaves no RECOVERY.done, so row 3
     repeats, and the repeat runs the barrier again.
   - Cost:
     - Linux: one process spawn and one `syncfs` per rollback. Nothing per object. Its time
       scales with the dirty data on that filesystem, which here is mostly the restored copies.
     - Windows: one volume flush. Or else one open-for-write plus one `FlushFileBuffers` for each
       copy-branch object and each retained destination, plus 3 for the root files. Recovery
       only, and bounded by Temp's data-file count, since each Temp data file produces at most
       one restored or retained destination. A retained destination that is already durable
       costs an open and an empty flush.
     - Normal runs: nothing.
4. Publish `RECOVERY.done` (Outcome=RolledBack, RunId). This is the rollback's commit. **The
   marker is NOT deleted here.**
5. Clean up (3.5).

A kill anywhere in steps 1-4 leaves the marker and RUN.state, with no RECOVERY.done. The next
recovery lands on row 3 again and repeats steps 1-4. Each step is idempotent: moves per 3.3, the
root Write-Manifest is a fixed point, and the barrier can be repeated.
- Cost: one read and hash of the Temp manifest (the witness check) plus one `Read-Manifest` of
  it; sharing that read is E8. Then, when N > 0, the one rename probe of 3.3, followed by N
  renames or N copies plus N same-directory renames, where N is the number of data files in Temp.
  Then one manifest write at the root, one sidecar copy, the step-3a barrier and one record
  write. The runtime calls under each move are counted in 3.3. No pool enumeration, no
  per-object hash, no application-level per-row probe.

**Row 4: roll forward, or finish the run's own discard.** A marker-less, non-empty Temp means
E′:7045 ran. After this revision nothing else deletes the marker of a non-empty Temp. Recovery
keeps it until RECOVERY.done exists (rows 1-3). `Remove-OwnStagingFolder` deletes it last, after
every other leaf (E′:4527), which leaves an empty folder (row 5).

**Read RUN.state FIRST, and branch on its complete decision before reading anything else
(revised 2026-10-10, second review).** RUN.state is published by rename, so it is complete or
absent, never partial.
- **RUN.state says DISCARD** (`ManifestChanged = false`, or `SnapshotDate` null): finish the
  discard exactly as 3.5 specifies, deleting leaves by exact name with RUN.state LAST. **Neither
  the Temp manifest nor its witness is read.**
  - Reason: the interrupted no-op discard may already have deleted `MANIFEST.csv` or its
    `.meta`. The witness checks below would then report `Absent` or `Malformed` and refuse,
    sending it to a person.
  - Why the discard depends on neither: `ManifestChanged = false` means both
    `$diff.NewOrChanged` and `$diff.RemovedFromSource` are empty. Those are exactly the inputs
    of steps 11.5 and 11 (E′:6909, E′:6963, E′:6981), so neither step moved anything.
  - `SnapshotDate` null is reachable only on a store whose root manifest has no rows: E′:6694-6700
    refuses a null `LastBackupRun` beside a non-empty manifest. So nothing existed to move.
  - Guard (round 3): it deletes only the fixed infrastructure names and the kit. An entry whose
    name parses by the SR-069 grammar contradicts the record's decision, so it refuses rather
    than deleting. The check uses the same enumeration.
  - Cost: one RUN.state read and the leaf deletes. No manifest read, no hash.
- **RUN.state says PUBLISH, or is absent** (absent means publish, by the coordinator rule G1):
  re-run `Complete-ChangeFolder` with the record's values, after these witness checks:
- Temp witness `Verified`: proceed.
- Temp witness `Mismatch`: by program order, the only writer of the Temp manifest after E′:7045
  is E′:6221, and P makes that write complete. So this is the BLANKED manifest beside the step-7
  witness: a kill between C′:1284 and C′:1386 inside E′:6221 (G7).
  - Accept it only if the witness's `Rows` equals the row count `Read-Manifest` returns. Blanking
    never changes the row count, and the check is free because roll-forward reads the manifest
    anyway.
  - Then re-run. The blank is a fixed point, and Write-Manifest re-stamps the witness.
  - `Rows` disagreeing, `Absent` or `Malformed` is not a kill state: refuse loudly. The residual
    risk is in §10.
  - `Absent` is "not a kill state" ONLY GIVEN P2 (§5). Today's `Move-Item -Force` deletes the
    old witness before moving the new one in (PS:5992-5993). Without P2, a kill between those
    two calls at E′:6221 leaves the blanked manifest, NO `.meta` and a complete `.meta.tmp`. This
    row would refuse that, beside only-copy data, which sends it to a person.
  - P2 removes that window, and that is why P2 is a build prerequisite and not a recovery rule.
    Accepting `Absent` here instead was rejected. Absent-plus-`.meta.tmp` cannot tell a complete
    witness from a torn one, so accepting it would mean re-hashing the manifest to judge the
    witness.
- Root witness: it must be `Verified`, because step 12 completed before E′:7045. Anything else
  is not a kill state: refuse.
- Cost: one RUN.state read and one witness check of the Temp manifest (read and hash), plus
  `Complete-ChangeFolder`'s own cost. Its per-row `Test-Path` (E′:6219) is exactly the repeated
  probing the Owner ruled out. E7 replaces it with membership in the one enumeration.

**Ordering against the 1.5 gate.** The 1.5 witness gate (E′:6711-6718) runs before the OS lock
(E′:6736) and before step 3. A step-12 kill leaves the root `Mismatch`: under P, a complete new
manifest with the prior witness; before P, a tear. The gate would then refuse every later run
before recovery could start, which sends it to a person. The first draft's step-12 rows said
"rollback" without noticing this.
- Rule: on `Mismatch`/`Malformed`, the gate tests whether Temp exists (one stat, on that path
  only). If Temp exists, it defers the refusal; the run takes the OS lock, recovers, and re-runs
  the gate on the recovered root. With no Temp, it refuses exactly as today.
- Restorers and `-Action Verify` keep refusing with exit 3 until that next run. That is the safe
  direction.
- Cost on a normal run: nothing. A `Verified` root never makes the stat.

**Invariant, tested:** rollback never sees a blanked manifest. The blanking at E′:6221 runs only
after the marker is gone. A rollback that restored a blanked manifest would orphan bytes. The
first draft's table wrongly called the step-13 Temp manifest "prior". It is snapshot form.

**Invariant, tested (new):** in a non-empty Temp, RUN.inprogress is deleted only at E′:7045.
Recovery deletes it only after RECOVERY.done is published (3.5).

### 3.3 Re-entrant moves without re-hashing

*Revised 2026-10-09 for the Owner's speed constraint.* The first draft name-proved every object
before each rename, and E1 asked to re-hash every Temp object. That is a full re-read of
everything Temp holds, through the translation layer. It also proves nothing a rename could have
broken:
- **What a Temp data file is.** It is a PRIOR pool object, moved out at step 11 or 11.5
  (`Move-Item -Force`, E′:6076, E′:6154). It was name-proven when created (SR-059), and objects
  are immutable.
- **A file move is not always a rename (added 2026-10-10, found while verifying the second
  review's item 5).** `[IO.File]::Move` quietly degrades to copy-then-delete across volumes.
  - On Windows, .NET always passes `MOVEFILE_COPY_ALLOWED` (NET Interop.MoveFileEx.cs:35).
  - On Unix it falls back to copying on `EXDEV` (NET FileSystem.Unix.cs:197-201), or through
    `LinkOrCopyFile` (L235, L75-99).
  - Either way the copy goes to the FINAL name. A kill mid-copy leaves a torn object at
    `BkpPath\<leaf>` while the source is still in Temp. The next pass's "dst exists" rule would
    then call the intact Temp copy redundant, and cleanup would delete the only good copy.
  - `$sameVolume` (E′:6850; Get-VolumeIdentity is a longest-prefix match over
    `DriveInfo.GetDrives()`, C′:~1135-1161) cannot be trusted to predict this. A folder mount
    point on Windows, a container bind mount (Linux `rename` returns EXDEV across mount points
    even on one filesystem) or the Owner's translation layer can each read "same" where the OS
    will copy.
- **Branch by a rename probe, once per rollback.** This runs only when Temp holds data files to
  move.
  The probe's name is FIXED, `.fbrecover-probe`, so its two possible paths are known without
  enumerating: `Temp\.fbrecover-probe` and `BkpPath\.fbrecover-probe`.
  1. Remove any leftover at both exact paths, non-recursively.
  2. Create an empty `Temp\.fbrecover-probe`.
  3. `[IO.Directory]::Move` it to `BkpPath\.fbrecover-probe`.
  4. **On success AND on failure**, remove both exact paths, non-recursively. On failure the probe
     is still in Temp.

  Revised 2026-10-10, round 3: the probe is created AFTER Temp was enumerated, so no step may
  rely on the saved enumeration to find it. Cleanup (3.5) removes both exact paths again before
  it deletes RECOVERY.done.

  `Directory.Move` never copies:
  - On Windows it checks the path root, then calls MoveFileEx, which cannot move a directory
    across volumes (NET FileSystem.Windows.cs:176-~200).
  - On Unix it calls `rename` and throws on EXDEV (NET FileSystem.Unix.cs:397-462).

  So success proves that file moves between those two directories are real renames. Failure
  selects the cross-volume branch. The probe never holds data, so a kill leaves only an empty
  directory, which the next pass removes.
- **Rename branch** (the probe succeeded): move back with
  `[IO.File]::Move(src, dst, overwrite: $false)`. A rename cannot change bytes.
  - If the move fails because dst exists, the root already holds that object. It is either the
    original whose forward delete never ran, or this rollback's own earlier pass. A forward
    copy-then-delete (E5) copies INTO Temp, so it never tears a root object.
  - Step 10 cannot have created dst: content addressing never writes over a name the pool
    already held, and this object was in the pool at step 10.
  - The Temp copy is then redundant and is left for cleanup. The failed call is the existence
    test, so the application makes no additional probe.
  - **The destination is still added to this pass's flush set (round 4).** "Exists" can be an
    EARLIER pass's copy-branch output that was published but never made durable, so it is not
    necessarily long durable. On Windows it is flushed with the rest at step 3a; on Linux the
    one `syncfs` already covers it. The set is kept in memory, one path per retained file, so it
    needs no extra filesystem call to build.
- **Copy branch** (the probe failed): `File.Copy(src, BkpPath\<leaf>.recover.tmp, $true)`, which
  overwrites a torn leftover from a killed pass. Compare the copy's length with the source length
  from the Temp enumeration, with no extra stat. Then `File.Move(tmp, dst, overwrite: $false)`.
  That is a same-directory move, so it is always a rename and is never degraded. "Exists" is
  handled as above, and the destination joins the flush set. The source stays in Temp, and
  cleanup deletes it after RECOVERY.done.
- **The first draft's "collision with different bytes, quarantine the destination" branch** is
  unreachable by the argument above. If it is ever hit (dst exists and one stat shows a length
  different from the Temp source), refuse loudly: it is not a kill state.
- **Hashing** stays available as an explicit audit (`-Action Verify`), not as a recovery step.
- **Cost (revised 2026-10-10: runtime calls counted).** "No additional application probe" is
  not the same as "no probe". The runtime's own metadata calls are listed here.

| Operation | Application calls | Runtime calls underneath |
|---|---|---|
| Probe, once per rollback that has data to move | create dir, `Directory.Move`, remove dir; plus up to 2 leftover removals | Unix: `LStat(dst)` + `rename`. Windows: string root check + `MoveFileEx` |
| Rename branch, per data file | one `File.Move` | Windows: source existence check (`GetFileAttributesEx`, NET File.cs:1050) + `MoveFileEx`. Unix: `stat` (File.cs:1050) + `LStat(src)` + `LStat(dst)` + `rename` (FileSystem.Unix.cs:225-229). On "exists", Unix skips the rename and calls `link()` instead, which fails `EEXIST` (L235, L77) |
| Copy branch, per data file | one `File.Copy`, one `File.Move` | the copy's own opens and data transfer, then the same-directory move as above |

  No hash, no pool scan, no per-row probe. Every count is linear in Temp's data-file count.

### 3.4 Runs that threw, not only killed

Recovery also covers a run that threw and left the same Temp. A `finally` releases the OS lock.
The marker state then decides rollback or roll-forward exactly as for a kill.

### 3.5 Ending a recovery, and the pipeline's own discard (finding 1)

*New 2026-10-09 (review).* **Cleanup** is entered from row 1, or straight after a rollback or a
discard publishes RECOVERY.done:
1. Delete every leaf except RECOVERY.done, in any order and each by exact name. That covers the
   marker, `RUN.state` and `RUN.state.tmp`, `RECOVERY.done.tmp` (an unpublished record, see row
   2), the manifest set (`.csv`, `.meta` and both `.tmp`), DIRECTORIES.csv, the kit files and
   the data files. The names come from the enumeration the classifier already made, so there is
   no extra pass. A data file is a name that parses by the SR-069 grammar, which is a pure check
   with no I/O. Every one of these leaves is redundant: RECOVERY.done is published only after the
   rollback put each byte back at the root (or found it already there) and the step-3a barrier
   made it durable, or after the discard proved that none was ever moved.
   1a. **Remove BOTH exact probe paths, `Temp\.fbrecover-probe` and `BkpPath\.fbrecover-probe`,
   non-recursively, whatever the saved enumeration says** (revised 2026-10-10, round 3).
   - Why: the probe is created after the enumeration, so a cleanup driven by that enumeration
     used to miss it. It deleted RECOVERY.done, the rmdir then failed on the probe, and what
     remained was a Temp with no marker, no record and only the probe.
   - Removing an absent path is a no-op. A probe that cannot be removed (non-empty, or in use)
     keeps RECOVERY.done in place, logs loudly and stops, so the next recovery is still on row 1.
   - Cost: two non-recursive directory deletes per cleanup. In runtime calls on Unix, each
     `Directory.Delete` makes one `rmdir`. Nothing on a normal run.
2. Delete RECOVERY.done LAST, then `Directory.Delete(Temp, recursive: $false)`.

An entry outside that set keeps the folder, and recovery logs it loudly. It is not a kill state.
ntfs-3g rename residue is named as such (3.2) and is never deleted by cleanup.

| Cleanup kill point | Next recovery sees | Does |
|---|---|---|
| after RECOVERY.done is published, before any delete | row 1 | cleanup from the start |
| part-way through step 1 (any subset gone, marker included) | row 1 | resumes deleting |
| step 1 done, before or during 1a | row 1 | 1a again: both probe paths, then the record |
| step 1 done, RECOVERY.done not yet deleted | row 1 | deletes the record, then rmdir |
| RECOVERY.done deleted, rmdir not done | row 5 (empty) | existing Empty reclaim |
| after rmdir | no Temp | nothing |

Why a record inside Temp rather than renaming Temp to a residue name: a residue folder would need
every NORMAL run to look for it, which costs an extra stat or an enumeration of the ChgPath, every
time. A record inside Temp is found by the Temp existence test the run already makes. The
Owner's constraint decides it.
- Cost: one small write and one delete per recovery, plus the leaf deletes Temp already implies.
  On a normal run, nothing.

**The pipeline's own no-op / first-run discard has the same window.** E′:6209 runs
`Remove-Item -Recurse -ErrorAction SilentlyContinue` on a marker-less Temp. A kill part-way
through can leave a remainder with no manifest or no record. Row 4 would then try to publish it,
or would meet a Temp with no manifest at all.
- Replace it with the same shape: delete the leaves by exact name, RUN.state LAST, then a
  non-recursive rmdir.
  - A kill before RUN.state is deleted lands on row 4 with ManifestChanged=false (or SnapshotDate
    null). Row 4 reads that decision FIRST and discards again, without reading the manifest or
    witness this discard may already have deleted (second review, item 2).
  - A kill after it leaves an empty Temp: row 5.
- The failure is no longer silent.
- Cost: no more operations than today, since the recursive delete enumerates and deletes the same
  leaves.

**The finalize path deletes RUN.state** after the kit copy and immediately before the rename
(E′:6254). So the record never reaches a Snapshot_*, where prune's unreferenced-file rail would
refuse it (SR-046).
- A kill between that delete and the rename lands on row 4 with no record, and the rule is
  "publish". That is correct here: ManifestChanged was true to reach that line.
- Cost: one delete per finalizing run.

## 4. Gaps found while revising (flagged, not papered over)

- **G1. ManifestChanged cannot be recomputed from manifests.** Roll-forward needs the value that
  `Complete-ChangeFolder` takes (E:6681). The code computes it from the source diff (E:6533), not
  from the manifests. A manifest diff is not equivalent: prior and new rows differ in more than
  content. After E:5865 the Temp manifest also differs from the root in DataPath blanks. Fix
  options: (a) persist `ManifestChanged` in a Temp-only record written before step 12, while the
  record is still whitelisted; (b) prove equivalence against E:6533 and ignore DataPath when
  diffing. Option (a) is the safer default. Not decided.
- **G2. The Temp prior manifest is the only copy of the prior index after step 12, and E:5865 can tear it.**
  The rewrite is a plain in-place `Write-Manifest` (C:1233), not atomic. If it tears, roll-forward
  cannot publish a correct Snapshot_*, and nothing recovers the prior index. Recovery must refuse
  in that case. This loss window remains until P (section 5) ships. The adopted design says P is
  not a gate, so this is an accepted-until-P risk that the coordinator must state explicitly.
- **G3. The first draft's claim "no Assert before Complete-ChangeFolder" was half wrong.** The
  fence at E:6666 precedes the E:6669 delete. There is no assert between E:6669 and E:5895. The
  window is real; its description is corrected.
- **G4.** The first draft's step-13 row called the Temp manifest "prior". It is blanked snapshot
  form after E:5865. Corrected in section 6.

Found by the 2026-10-09 independent review, and while answering it:

- **G5. Rollback had no durable end state (review finding 1). Valid.**
  - The first draft's rollback ended with "delete the marker LAST", and its marker-absent branch
    read a missing marker as "step 12 has completed".
  - No rollback step removed Temp. So even an UNINTERRUPTED rollback left a marker-less Temp
    holding the prior manifest, its witness, DIRECTORIES.csv and the G1 record.
  - The next recovery would roll it forward. With `ManifestChanged=True` persisted,
    Complete-ChangeFolder (E′:6214-6254) blanks every DataPath (the bytes are back at the root),
    copies the kit and publishes `Snapshot_<priorBackupDate>`. That snapshot's manifest equals
    the live root's.
  - No bytes are lost. But it is a snapshot of a state that was never superseded, against SR-005
    ("one per superseded backup"; "the latest state has no snapshot"). The next real run then
    collides on the same date and gets `_001`.
  - A kill part-way through any recursive cleanup of a marker-less Temp is worse. It can leave no
    manifest at all, and nothing specified what recovery does then.
  - Fixed by 3.2 rows 1 and 3 and by 3.5. RECOVERY.done is the rollback's commit; the marker
    goes only during cleanup, after the record; the record goes last.
  - The pipeline's own no-op discard (E′:6209) had the same window and is fixed the same way.
- **G6. Step 7's manifest/witness pair under P (review finding 2). Valid.**
  - Under P, step 7 publishes the Temp manifest by rename (C′:1284) and only then the witness
    (C′:1293, C′:1385-1386). Temp is new each run, so a kill between them leaves a complete
    manifest and NO witness (`Absent`), possibly with a `.meta.tmp`.
  - The first draft refused any Temp manifest that "does not verify against its own witness".
    That sends this case to a person, which D8 forbids.
  - Before P it was already a D8 violation: §6's old step-7 row said "torn Temp manifest refuses".
  - Fixed by row 2: RUN.state's absence dates the kill before any mutation, so Temp is discarded
    without consulting the witness.
  - Also: `MANIFEST.csv.meta.tmp` is not on the Temp classifier's ignore list (E′:3389 ignores
    only `MANIFEST.csv.tmp`). It joins the recovery whitelist (E1).
- **G7. The same pair gap at step 12, step 13 and rollback step 2. All three exist under P, and
  all three are handled.**
  - *Step 12* (E′:7012): a complete new root manifest beside the prior witness. Rollback (row 3)
    replaces the root through Write-Manifest and never reads the root witness. The 1.5 gate
    defers when Temp exists (3.2). Without that deferral the gate refused before recovery could
    run. The first draft's step-12 rows had this gap too.
  - *Rollback step 2*: the same shape. The marker and RUN.state survive and RECOVERY.done is not
    yet published, so row 3 repeats, and the repeat rewrites both files.
  - *Step 13* (E′:6221): the blanked manifest beside the step-7 witness, which reads `Mismatch`.
    Row 4 accepts it by program order. The only writer after E′:7045 is E′:6221. Rows must
    agree, and the blank is a fixed point. It is re-witnessed on the re-run.
  - Rejected for step 13: pinning the blanked manifest's digest in a second record before the
    rename. That costs a second record write per finalizing run, and Common would have to expose
    the digest before the rename (a kit revision). It would buy only the residual named in §10.
- **G8. The same pair gap at step 6. It exists under P, and it is NOT handled. BUILD BLOCKER
  (raised 2026-10-10): the recovery build may not start until the Owner decides G8.**
  - `Test-BackupManifest` rewrites the root unconditionally (E′:929). A kill between the rename
    and the witness leaves a complete sanitized root beside the pre-run witness: `Mismatch`.
    Temp then holds only the marker.
  - The 1.5 deferral lets the next run reach recovery. But the existing marker-only reclaim does
    not touch the root, so the gate then refuses, and that is a person.
  - **Reachable through the supported healing path.** When sanitization blanks a missing
    DataPath (E′:915-917, the SR-053 heal input), the rewritten bytes differ from what the stale
    witness describes, so the kill reads `Mismatch`.
    - If sanitization blanked nothing, the rewrite may be byte-identical, in which case the stale
      witness still verifies. Not verified here; it does not matter, because the healing case
      certainly reaches the gap.
    - Before P2, a kill between `Move-Item -Force`'s delete and its move (PS:5992-5993) leaves
      the root witness `Absent` instead. The gate refuses only `Mismatch` and `Malformed` (E′:6712-6713), so that
      variant heals itself on the next run. The `Mismatch` variant does not.
  - Options:
    - (a) Recognise it by program order. The marker is present, there is no Temp manifest, and
      this run's own 1.5 gate passed before the marker existed. Then re-run sanitization, which
      re-stamps the witness. Same residual class as G7's step 13.
    - (b) Write the root at step 6 only when sanitization blanked a row. That narrows the window
      but does not close it.
    - (c) Drop the step-6 root write. Step 12, or a rollback from the Temp copy, persists the
      sanitized rows, and a failed run leaves the pre-run root, which the next run re-sanitizes.
      Row 2's argument still holds: the root is then the pre-run manifest rather than step 6's,
      and either way Temp is redundant.
  - **Recommendation: (c). This design does NOT decide it.** It changes how healing persists,
    so it is the Owner's decision (§9, Owner decision (e)).
  - Rationale for (c): it closes the window, where (b) only narrows it and (a) re-witnesses an
    unverified root. It also removes one full manifest write, and the witness's re-read and hash
    of it, from EVERY run, which suits the Owner's speed constraint.
  - **What (c) changes about healing persistence:**
    1. The step-6 blanks of missing DataPaths reach the root only when the run gets to step 12,
       or when a rollback restores the Temp copy, which carries them. Today they reach it at
       step 6.
    2. A run that fails or refuses between step 6 and step 12 (the 9.4 capacity refusal, any
       throw) leaves the root still NAMING the missing DataPaths. Today those are blanked. A
       restorer or `-Action Verify` that runs before the next completed run then sees a named,
       missing file rather than a blank row.
       - The restorers' hash fallback for a missing named file is AGENTS §3, kit revision 4.
       - Whether that path's form decision matches SR-050's blank-row path is NOT verified here.
       - Whether `Test-StorageFormAgreement` and `Test-PoolResolves` classify the two the same
         way is NOT verified here.

       Both must be checked before (c) is built.
    3. The "Datapath missing in backup DB" warning (E′:916) repeats on each failed run until a
       run completes. Today the persisted blank silences it after the first step 6.
    4. Unchanged: the heal itself (SR-053's re-copy at step 10 of the same run, which works from
       the in-memory sanitized `$backupDb`); the orphan scan and its warnings (SR-064); the
       step-7 Temp copy, so snapshots; and row 2's argument (the root becomes the pre-run
       manifest instead of step 6's, and Temp is redundant either way).
    5. The spine text that says step 6 writes the root (SR-061/SR-064 wording, AGENTS §2 step 6)
       and any TC asserting that write must be revised.
  - §6.1 shows the step-6 pair row as **BLOCKED ON G8**.
- **G9. §2.2's "all callers run BEFORE step 7" was wrong.** `$refuseCapacity` (E:6469) runs at
  step 9.4 (E:6553). That is why RUN.state is written after 9.4 rather than at step 7.

Found by the round-3 confirmation (2026-10-10), triaged under the Owner's balance rule: protect
against real data loss, add no I/O to normal runs, and do not design for vanishingly narrow
windows.

- **G10. Durability of cross-volume restores. Accepted narrowly.**
  - The defect: cleanup deleted a Temp source whose copy might not yet be durable at the root.
  - Fixed by ONE batched barrier per rollback (3.2, step 3a).
  - A per-file fsync on Linux, and any fsync on normal runs, are rejected. That includes the
    RUN.state flush a6fb66d had added, which is withdrawn.
- **G11. A missing RUN.state could reach a discard unguarded. A real hole, power loss only,
  found while verifying G10.**
  - The case: a run that moved nothing, with RUN.state's rename lost and step 12's survived. The
    data-name guard sees no data and discards the only copy of the prior index.
  - Fixed by row 2's root-witness check (3.2). It costs two small reads in recovery only.
  - It must change if G8 (c) is adopted (3.2).
  - **Round 4 (2026-10-10): that fix was unsound.**
    - Power loss can keep step 12's new root manifest and lose the root's witness replace, so
      the OLD witness still matches Temp's.
    - Comparing witnesses never checks the root manifest itself.
    - Now: verify the root manifest against its own witness first, then require Temp's `.meta`
      to equal it. When Temp has no `.meta`, hash Temp's `MANIFEST.csv` instead. A Temp with no
      manifest is discarded with no check.
    - Cost: one root-manifest hash in recovery only, plus one more hash when Temp's `.meta` is
      absent.
    - The `Written` variant for G8 (c) is withdrawn and replaced by a pre-run digest kept in
      the owner record (3.2).
- **G13. The barrier missed retained destinations (round 4, Windows).** Across passes, an
  "already exists" destination can be an earlier pass's unflushed copy. It now joins the
  Windows flush set; Linux's `syncfs` already covered it (3.2 step 3a, 3.3). Recovery only, and
  bounded by Temp's data-file count.
- **G12. Probe residue. Accepted.**
  - The defect: cleanup derived its names from an enumeration taken before the probe existed.
  - Fixed: the probe's name is fixed, residue is accepted in classification, and both exact
    paths are removed on success, on failure, and in cleanup before RECOVERY.done (3.3, 3.5).
- **P2 under power loss on ntfs-3g. Documented, not redesigned: §10.**

### Coordinator resolution of G1 and G2 (2026-10-09)

- **G1 → option (a).** Write `ManifestChanged` into a small Temp-only record before step 12
  (whitelisted alongside the run marker by the Temp classifier), and have roll-forward read it.
  An exact value is better than an inferred one. If the record is absent or unreadable,
  roll-forward **publishes** the snapshot: an unneeded snapshot costs disk and loses nothing,
  while discarding a staging folder that held superseded bytes is the loss D8 forbids.
- **G2 → P becomes a prerequisite of the BUILD (not of this design).** With P, the E:5865
  rewrite is temp+rename, so a kill leaves either the pristine prior manifest or the complete
  blanked one, and roll-forward can always proceed. Without P that window would need a person,
  which D8 does not allow. The kit-revision cost of changing Common is accepted. Build order:
  P → OS lock → split recovery. Section 5's "not gates" therefore applies to A1 only.

**Amended 2026-10-09 (review).** These amendments refine the two resolutions above; neither is
reversed.
- G1: the record is now written after step 9.4 and before step 10. That is still "before
  step 12", so the resolution's intent holds.
  - Its absence while the marker is present now MEANS something: the run had not yet mutated
    anything (row 2).
  - "Absent ⇒ publish" applies to the marker-absent case (row 4) only.
- G2: "roll-forward can always proceed" was too strong. P removes the tear, but the witness still
  follows the manifest. A kill between them leaves the complete blanked manifest beside the
  step-7 witness, which reads `Mismatch`. Roll-forward proceeds through row 4's acceptance rule,
  not unconditionally (G7).
- Build order (2026-10-10): P2 joins P as a prerequisite, and G8 blocks the build until the Owner
  decides it (§5).

## 5. Separate items (P and P2 are build prerequisites; G8 is a build blocker; A1 is not a gate)

Build order, revised 2026-10-10: **the Owner decides G8 → P and P2 (one kit revision) → OS lock
→ split recovery.** The recovery build does not start while G8 is open.

**P. Atomic `Write-Manifest`.** `Test-BackupManifest` calls `Write-Manifest` unconditionally on
success (E:922). `Write-Manifest` writes the final path directly (`Export-Csv -LiteralPath`,
C:1233). Only the witness uses tmp plus rename (C:1327-1328). Change `Write-Manifest` to write
`MANIFEST.csv.tmp` and `Move-Item -Force`. Consequences:
- Common is bundled into restore kits (AGENTS §2), so a kit revision and
  `Update-BackupSnapshotKit` (E:2020) are needed on existing stores (E4).
- `MANIFEST.csv.tmp` must be whitelisted by the Temp and pool classifiers.
- Reminder: P closes the step-6 index loss, the step-12 torn index and the G2 window.
- Re-verified against fix-p-atomic-write-manifest: P closes the TEARS, not the manifest/witness
  pair window. It uses `[IO.File]::Move(..., $true)` (C′:1284), not `Move-Item`, and the witness
  still follows it (C′:1293). That pair window is G6/G7/G8. P also whitelists only
  `MANIFEST.csv.tmp` (E′:78, E′:3389); recovery adds `MANIFEST.csv.meta.tmp` (G6).

**P2. Atomic witness replacement. A build PREREQUISITE beside P (added 2026-10-10, second
review).**
- What happens now: `Write-ManifestWitness` publishes the witness with
  `Move-Item -LiteralPath $tempPath -Destination $witnessPath -Force` (C′:1386). Over an EXISTING
  witness, PowerShell's provider does this (PS:5908-5993, `MoveFileInfoItem`):
  1. It first tries `FileInfo.MoveTo(dest)` without overwrite (PS:5925), which fails because the
     destination exists.
  2. In the `IOException` handler it checks `File.Exists(dest)` (PS:5983), clears attributes,
     `Delete()`s the destination (PS:5992), and only then calls `MoveTo` again (PS:5993).

  A kill between 5992 and 5993 leaves NO witness beside a complete manifest. That window exists
  at every witness REPLACE: step 6 and step 12 at the root, step 13 in Temp (E′:6221), and
  rollback step 2. It does not exist at step 7, because Temp has no prior witness there, so the
  first `MoveTo` succeeds.
- Change: `[IO.File]::Move($tempPath, $witnessPath, $true)`, the same call P uses for the
  manifest (C′:1284). That is `MoveFileEx(REPLACE_EXISTING)` on Windows and `rename(2)` on Unix
  (NET FileSystem.Unix.cs:193-195, overwrite branch). It is same-directory, so it never takes
  the copy fallback. The witness is then the old file or the new one, never absent.
- Why it matters: step 13 is the only place where `Absent` would strand data. Without P2, row
  4 refuses there, beside only-copy data, and that sends it to a person. At step 12 and in
  rollback step 2 an `Absent` root witness is harmless: Temp exists, so row 3 rewrites both
  files. At step 6 `Absent` passes the gate and heals itself (G8).
- Consequences:
  - Common changes, so there is a kit revision (AGENTS §3). It should ride P's revision if the
    two ship together (E4).
  - The restorers' and the gate's reading of the witness is unchanged, and so is the
    manifest-then-witness ORDER (AGENTS §4: do not stamp the witness first). P2 does not change
    the order; it removes only the moment with no witness at all.
- No verification pass is needed. The `.meta.tmp` left by a kill BEFORE the rename is already
  covered: it reads `Absent` at step 7 (row 2) and `Mismatch` at step 13 (row 4).
- Cost: fewer calls than today. Today, a replace costs a failed `MoveTo`, `File.Exists`, an
  attribute write, `Delete` and a second `MoveTo`. P2 costs one source-existence check
  (NET File.cs:1050) and one rename.

**A1. Audit: torn step-10 objects.** Step 10 writes final content-addressed names directly
(E:811, E:824). A kill mid-write leaves a torn object at a name it does not hash to. Audit whether
any reader trusts a name without checking. Treat as an orphan (O2 default: report, do not delete).

## 6. Interruption table (corrected; revised 2026-10-09 for P and the review)

P and P2 are build prerequisites, so the table assumes both: no manifest is ever torn, and no
witness is ever absent mid-replace (6.3 shows the P2 window). The old pre-P rows
("mid-Export, torn") are therefore replaced by the manifest/witness PAIR windows, written "after
rename, before witness" (C′:1284 to C′:1386). "Only copy" means the bytes or the index exist in
Temp and nowhere else. "Row" is the 3.2 classification. Cites are E′ (fix-staging-os-lock).

**6.1 Pipeline kill points**

| Kill point (cite) | Root | Temp | Recovery | Only copy in Temp? |
|---|---|---|---|---|
| Before E′:6746 | untouched | nothing | none | no |
| Step 6, before rename (E′:929 → C′:1275) | prior; maybe a root `MANIFEST.csv.tmp` (infrastructure, E′:78) | marker only | existing reclaim | no |
| Step 6, after rename, before witness | sanitized, complete; witness pre-run, so **Mismatch** | marker only | **BLOCKED ON G8** (build blocker; Owner decision (e)). Today: 1.5 defers, the marker-only reclaim runs, the root is still Mismatch, so the run refuses: a person | no |
| Step 7, before rename (C′:1275-1284) | sanitized, Verified | marker + `MANIFEST.csv.tmp` | existing reclaim (E′:3389) | no |
| **Step 7, after rename, before witness (C′:1284-1386)** | sanitized, Verified | marker + complete MANIFEST.csv, **no .meta**, maybe `.meta.tmp` | **row 2: discard** (was: refuse, a person) | no |
| Step 7, after witness, before or mid DIRECTORIES copy (E′:6878-6880) | sanitized, Verified | marker + manifest + witness (+ partial sidecar) | row 2: discard | no |
| Steps 8-9.4 | sanitized, Verified | as above | row 2: discard | no |
| 9.4 refusal, mid `Remove-OwnStagingFolder` (E′:4527-4542) | sanitized, Verified | marker + a subset of the step-7 set | row 2: discard | no |
| 9.4 refusal, after its marker delete | sanitized, Verified | empty | row 5: existing Empty reclaim | no |
| RUN.state publish, `.tmp` only | sanitized, Verified | step-7 set + `RUN.state.tmp` | row 2: discard | no |
| Step 10 (E:811, E:824), RUN.state present | sanitized; torn orphans in pool | prior copy + RUN.state | row 3: rollback (moves nothing); orphans reported | no |
| Step 11 mid-loop (E′:6076) | prior manifest claims moved objects | moved removed-file objects | row 3: rollback moves them back | **yes** |
| Step 11.5 mid-loop (E′:6154) | prior manifest claims moved objects | moved superseded objects | row 3: rollback moves them back | **yes** |
| Step 12, before rename (E′:7012) | prior, Verified | prior manifest + witness + objects + RUN.state | row 3: rollback | **yes** |
| **Step 12, after rename, before witness** | new, complete; prior witness, **Mismatch** | same | 1.5 defers; **row 3: rollback**, never reading the root witness (G7) | **yes** |
| Same, plus power loss that lost RUN.state (round 4) | new, complete; old witness, Mismatch | no data, prior manifest + witness, no RUN.state | row 2: the root does not verify, so it REFUSES (was: discarded, G11) | **yes** (index) |
| Step 12.5, after DIRECTORIES write (E′:7023) | new | same | row 3: rollback, which restores DIRECTORIES too | **yes** |
| 12.9 after fence (E′:7042), before delete | new, complete | marker present | row 3: rollback | **yes** |
| 12.9 after delete (E′:7045), before E′:6221 | new, Verified | prior manifest + objects + RUN.state; **no marker** | row 4: roll forward | **yes** |
| **Step 13, E′:6221 after rename, before witness** | new, Verified | **blanked** manifest + step-7 witness (**Mismatch**) | row 4: accepted when Rows agree; re-run re-witnesses (G7) | **yes** |
| Step 13, after witness, kit copy partial (E′:6229-6239) | new, Verified | blanked + Verified + partial kit | row 4: roll forward; blank and kit copy are idempotent | yes |
| Step 13, after RUN.state delete, before rename (E′:6254) | new, Verified | complete, no record | row 4: no record, so publish (correct here) | yes |
| No-op / first-run discard, part-way (E′:6209 as replaced, 3.5) | new, Verified | leaves remaining + RUN.state (deleted last) | row 4: RUN.state's discard decision is read FIRST, so it discards again without reading the manifest or witness (which may be gone) | no |
| No-op discard, after RUN.state delete | new, Verified | empty | row 5 | no |
| After rename (E′:6254) | Snapshot_* published | none | none; steps 14-15 out of scope | n/a |

**6.2 Recovery's own kill points (new: finding 1 and the cleanup)**

| Kill point | Root | Temp | Next recovery | Only copy in Temp? |
|---|---|---|---|---|
| Rollback step 1, after k of n moves (same volume) | k objects back | n−k objects, marker, RUN.state | row 3: repeat; each moved one fails "exists" | **yes** for the n−k |
| Rollback step 1, cross-volume mid-copy | torn `<leaf>.recover.tmp` | source intact | row 3: repeat, overwriting the `.recover.tmp` | **yes** |
| Rollback step 2, before rename | step-12 state (new or Mismatch) | unchanged | row 3: repeat | **yes** (index) |
| Rollback step 2, after rename, before witness | prior manifest, killed run's witness: Mismatch | unchanged | 1.5 defers; row 3: repeat, rewriting both | no (the root holds it) |
| Rollback step 3, mid-sidecar | sidecar torn (advisory) | unchanged | row 3: repeat | no |
| RECOVERY.done `.tmp` written, not renamed | restored | unchanged + `.tmp` | row 3: repeat (all no-ops), then publish | no |
| RECOVERY.done published, before any delete | restored | full | row 1: cleanup | no |
| Cleanup mid-deletes (marker possibly gone) | restored | subset + RECOVERY.done | **row 1** (it used to be roll forward, **G5**) | no |
| Cleanup, RECOVERY.done deleted, before rmdir | restored | empty | row 5 | no |
| Discard (row 2), `RECOVERY.done.tmp` written, not renamed | untouched | step-7 set + `RECOVERY.done.tmp` | row 2 again: the `.tmp` is in its set, and the next publication overwrites it | no |
| Discard (row 2), RECOVERY.done published or mid-deletes | untouched | subset + record | row 1 | no |
| Rollback rename probe (3.3), probe dir left in Temp or in BkpPath | partly restored, or not | unchanged + empty `.fbrecover-probe` | row 3: remove the leftover probe, probe again, repeat | as before the probe |
| Rollback step 3a, kill or power loss before the barrier completes | restored, possibly not durable | unchanged, sources intact | row 3: repeat, including the barrier | **yes** (the sources are kept until after RECOVERY.done) |
| Copy-branch pass killed before the barrier; the next pass's probe succeeds (round 4) | earlier pass's copy published, maybe not durable | sources intact | row 3: the rename meets "exists" and RETAINS the destination, which joins the flush set; the barrier, then RECOVERY.done | **yes**, until the barrier |
| Cleanup ran on a saved enumeration that lacked a probe left after it (the pre-round-3 order) | restored | ONLY an empty `.fbrecover-probe`: no marker, no record | set aside by name, so row 5: remove the probe, then rmdir. 1a now prevents this state | no |
| Roll forward, anywhere in the re-run | new, Verified | as in the step-13 rows of 6.1 | row 4 again | as 6.1 |

**6.3 The witness-replace window (P2, added 2026-10-10)**

This is the kill between `Move-Item -Force`'s `Delete()` of the old witness and its `MoveTo` of
the new one (PS:5992-5993). It exists only without P2. With P2 every row below reads "the old
or the new witness; no Absent state exists".

| Witness replace | Without P2 | With P2 |
|---|---|---|
| Step 6, root | complete root, NO witness. The gate accepts `Absent` (E′:6712-6713), so it heals itself on the next run | old or new witness; the `Mismatch` case is G8 |
| Step 12, root | new root, NO witness. Temp exists, so row 3 rolls back and rewrites both | old or new; 6.1 rows |
| **Step 13, Temp (E′:6221)** | blanked manifest, NO witness, complete `.meta.tmp`. **Row 4 refuses beside only-copy data: a person** | old witness (Mismatch, accepted when Rows agree) or new (Verified) |
| Rollback step 2, root | prior root, NO witness. Marker and RUN.state remain, so row 3 repeats | old or new; 6.2 rows |
| Step 7, Temp | not reachable: Temp has no prior witness, so the first `MoveTo` succeeds (PS:5925) | same |

Summary:
- Temp holds the only copy from step 11 through step 13, in every sub-point.
- Kills up to step 10 leave Temp redundant; deleting it loses nothing. Through step 9.4 the
  absence of RUN.state proves it without reading the witness.
- Under P no manifest is torn. Every remaining index window is a manifest/witness pair. Steps
  7, 12 and 13 and rollback step 2 resolve automatically (G6, G7), given P2 for step 13.
  **Step 6 does not: G8 is a build blocker.**
- No row of 6.2 asks a person. Every kill inside recovery lands on a row that resumes.

## 7. Test plan

Seams follow the existing `Invoke-StagingTestHook` (E:2890) pattern: one hook per boundary that
throws to simulate the kill, plus truncation hooks for mid-write cases.
- Kill points: step 6 mid-write; 7; 10 mid-object; 11 after k of n moves; 11.5 after k of n;
  12 mid-Export; 12 after Export before witness; 12.5; 12.9 before and after delete; 13 mid-rewrite;
  13 mid-kit-copy.
- One out-of-process SIGKILL per boundary, using the TC-194/195 system-test pattern.
- **Kill DURING recovery** at every move boundary, including a cross-volume torn copy (E5).
  Re-run recovery; the result must match the single-pass result.
- **Suspended live run in the 12.9-13 window** racing recovery. Assert the OS lock refuses, and that
  pool and manifest hashes are unchanged.
- **Kill after the step-13 rewrite and before the rename.** Assert roll-forward, not rollback.
- **Negative test:** rollback never restores a blanked manifest.
- Assert BYTES: SHA-256 of every file under BkpPath and ChgPath before the run and after recovery.
  For rollback, the result is byte-identical to the pre-run store, minus the killed run's orphans.
  Then run Reconstruct.ps1 for latest and each snapshot, and compare with the fixture tree.
- Negative cases, hashes unchanged: live owner (heartbeat running); PRUNE.inprogress present;
  RunId swap at each recovery fence; an unrecognised entry (hidden or user file); a torn Temp prior
  manifest; a name collision with different bytes.

Added 2026-10-09 (review). Each case is asserted on BYTES, as above. Each one also re-runs
recovery a second time and asserts that the result equals the single-pass result.
- **Kill during rollback cleanup (finding 1).** Kill at every 6.2 boundary: after RECOVERY.done is
  published; after each single leaf delete, including immediately after the marker delete; after
  the last leaf and before the record delete; after the record delete and before the rmdir.
  - Assert the next recovery takes row 1 or row 5, never row 4.
  - Assert no Snapshot_* is created.
  - Assert ChgPath's set of `Snapshot_*` names is unchanged.
  - **Mutation check:** make cleanup delete RECOVERY.done first, or make rollback delete the
    marker as the first draft did. The test must then see a Snapshot_* appear.
- **Uninterrupted rollback leaves no Temp.** The first draft failed this one with no kill at all.
- **Kill during rollback steps 1-4.** After k of n moves, same and cross volume. Between rollback
  step 2's rename and its witness. After `RECOVERY.done.tmp` and before its rename.
- **Step 7 manifest/witness pair (finding 2).** Use the P seam (`$script:ManifestWriteTestHook`,
  `AfterRename`, C′:~1290) on the STAGING write, plus an external kill inside
  Write-ManifestWitness between C′:1385 and C′:1386.
  - Assert row 2 (discard), the root byte-identical, Temp gone, and NO refusal.
  - Repeat with a `MANIFEST.csv.meta.tmp` present.
  - Repeat with a data-named file added by hand: it must refuse, with hashes unchanged.
- **Data-file absence is not the signal.** Use a run whose steps 11 and 11.5 move nothing (only
  adds), and kill it after step 12.
  - Assert row 3 (RUN.state present) and a rollback that restores the prior index, never a
    discard.
  - **Mutation check:** keying row 2 on "no data files" instead of "no RUN.state" must fail this
    test.
- **Step 12 pair, under P:** kill between the root rename and the root witness.
  - Assert the 1.5 gate defers, the rollback runs, and the gate then passes.
  - **Mutation check:** a gate that refuses without testing for Temp must fail.
- **Step 13 pair, under P:** kill between E′:6221's rename and its witness.
  - Assert roll-forward publishes a Snapshot_* whose witness Verifies and whose rows equal the
    blank of the prior manifest.
  - Negative: the same state with a row deleted from the blanked manifest must refuse.
- **No-op discard killed part-way** (3.5): no Snapshot_*, and the next run is not blocked.
  - Added 2026-10-10: kill it after `MANIFEST.csv` is deleted, again after `.meta` is deleted,
    while RUN.state remains each time.
  - Assert row 4 discards without reading the manifest or witness: no `Read-Manifest` and no
    `Test-ManifestWitness` call through the seams.
  - **Mutation check:** moving the RUN.state branch after the witness checks must make this
    refuse.
- **`RECOVERY.done.tmp` left by a killed discard** (2026-10-10): assert row 2 discards and
  cleanup removes the `.tmp`. The same check applies to a killed rollback in row 3.
- **RUN.state is fail-closed** (2026-10-10): make the RUN.state write or rename throw.
  - Assert the set fails before step 10, with nothing moved and no step-10 object written.
  - Assert the next recovery takes row 2.
- **P2, the witness replace** (2026-10-10): put a seam between the old-witness removal and the
  new witness's arrival, at step 13 (Temp), step 12 (root) and rollback step 2.
  - With P2, assert the witness is the old or the new file at every instant, never absent, and
    that row 4 publishes at step 13.
  - **Mutation check:** restoring `Move-Item -Force` must reproduce `Absent` at step 13, and
    row 4 must then refuse there.
- **Silent copy degrade (3.3)** (2026-10-10): put Temp and BkpPath on different volumes where
  `$sameVolume` still says "same". A folder mount point on Windows does this, and so do two bind
  mounts of one filesystem in the container.
  - Assert the probe selects the copy branch.
  - Then kill mid-copy. Assert no torn object ever appears at a final root name, and that the
    Temp source survives until after RECOVERY.done.
  - **Mutation check:** branching on `$sameVolume` instead must fail this test.
- **Probe residue** (2026-10-10, round 3). Leave `Temp\.fbrecover-probe` behind after Temp was
  enumerated, by killing between probe steps 2 and 4.
  - Then run cleanup. Assert it removes both exact probe paths before deleting RECOVERY.done,
    and that Temp is gone.
  - Separately, construct a Temp holding ONLY an empty `.fbrecover-probe`. Assert row 5 (probe
    removed, folder removed), never row 4.
  - A NON-empty `.fbrecover-probe` must refuse, with hashes unchanged.
  - **Mutation check:** cleanup driven only by the saved enumeration must leave the probe-only
    Temp.
- **Durability barrier** (2026-10-10, round 3). Count barrier calls through a seam.
  - Assert exactly one barrier per rollback, after the step-1 to step-3 restores and before
    RECOVERY.done is published.
  - Assert none on a discard, a roll-forward or a normal run, and none on RUN.state.
  - Run on both platforms, with the copy branch forced: Linux, one `sync -f`; Windows, the volume
    flush or the per-file flushes of 3a.
  - **Mutation check:** moving the barrier after RECOVERY.done must fail the ordering assertion.
  - **Retained destinations, round 4 (Windows):**
    1. Pass 1: force the probe to fail, copy one object, then kill before the barrier.
    2. Pass 2: let the probe succeed.
    3. Assert that the retained destination is in the flush set, and is flushed BEFORE
       RECOVERY.done.
    4. Assert that a failed flush keeps RECOVERY.done unpublished and the Temp source in place.
    - **Mutation check:** flushing only this pass's copies must fail.
  - Power loss itself is not simulated. The test pins the ORDER, not durability.
- **Power-loss reorder in row 2** (2026-10-10, round 3). Construct: marker present, no RUN.state,
  no data files, and a root manifest and witness rewritten as step 12 would leave them, while
  Temp holds the step-7 copy with its witness.
  - Assert row 2 REFUSES, with hashes unchanged.
  - With Temp's `.meta` absent, assert it discards.
  - **Round 4, added cases:**
    - (i) A NEW root manifest beside the OLD root witness, with Temp's `.meta` equal to that old
      witness. This is the case round 3 discarded. Assert a REFUSAL.
      **Mutation check:** comparing the witnesses without verifying the root must discard here
      and fail the test.
    - (ii) A complete new root (manifest and witness, `Verified`) with Temp's `.meta` absent.
      Assert a refusal by the Temp-manifest hash.
    - (iii) The step-7 process-kill case, with the root untouched and no Temp `.meta`. Assert a
      discard.
    - (iv) A Temp with no `MANIFEST.csv` at all. Assert a discard with no root hash, counted
      through the seam.
- **ntfs-3g residue** (2026-10-10, round 3). Place `MANIFEST.csv.meta.ntfs-3g-0000000001` in
  Temp, and separately at the root.
  - Assert the refusal names it as ntfs-3g rename residue, and that it is not deleted.
- **SchemaVersion-1 Temp** (upgrade): with a verifying Temp manifest it rolls back. Without a
  witness, the expectation is set by Owner decision (d), which is still open. The proposed
  expectation is today's refusal; the test is written once (d) is decided.
- **Cost assertions** (the Owner's speed constraint). Count calls through the seams at the
  APPLICATION level, and count runtime calls separately, for example with `strace -c` in the
  container or ProcMon on Windows. Do not merge the two counts.
  - Application level, normal run with no Temp: zero existence tests added over today. Exactly
    one record write, one rename and one delete are added, with NO flush (round 3). The witness
    publish costs fewer calls than today (P2, §5).
  - Runtime level, same run: the RUN.state rename adds one source-existence check plus the
    rename (NET File.cs:1050).
  - Application level, recovery: no pool enumeration, no per-object hash, at most one rename
    probe, and a call count linear in Temp's entry count.
  - Runtime level, recovery: per moved file, 2 calls on Windows and 4 on Unix. On "exists",
    Unix still makes 4 calls: `link()` replaces the rename. See 3.3's table.
- P: at every Write-Manifest kill point, MANIFEST.csv is the old or new complete file, never
  zero-length or torn. Mutation check: reverting P must fail this test.
- TC-188 is rewritten to the recovered expectation, not weakened. A new test keeps the
  unrecognised-entry refusal.
- **M-4 interaction:** the fix-m4 branch (commit f09641d) persists state right after step 13.
  Re-check the M-4 ordering against the 13 boundaries above before either branch merges.

## 8. Spine impact

Numbering is not assigned here. Build-time rule: take the next free ID when the item is written.
At the time of writing, TC-233 is taken (commit f09641d on `fix-m4-persist-state-before-dedupe`),
and TC-234 to TC-236 are reserved by another branch in progress.
- SR-017: "shall remain a refusal, unchanged" is amended to: recover a Temp whose entries are
  exactly the pipeline's recoverable set with a verified prior copy; everything else still refuses.
- SR-075: new classifier state; the no-marker window (12.9-13) and the OS lock must be stated.
- SR-038: "atomicity covers the witness publish only" (C:1291) changes under P.
- SR-059: recovery restores bytes only to their own name-proven DataPath. State it.
- New SR for the recovery behaviour. New LLR for the classifier state, the restore routine and
  atomic Write-Manifest (LLR-025 and LLR-038 are the current Write-Manifest rows; not re-verified here).
- TC-188 changes expectation. TC-186, TC-187 and TC-202 are re-read against the new classifier.
- Added 2026-10-09 (review):
  - SR-075 states the marker invariant (deleted only at E′:7045, or after RECOVERY.done).
  - SR-075 also states the owner record's SchemaVersion 2 and the two records' names and
    publication.
  - SR-039/SR-040's 1.5 gate gains the Temp-present deferral.
  - SR-017's recoverable set gains `RUN.state`, `RECOVERY.done`, their `.tmp`s and
    `MANIFEST.csv.meta.tmp`.
  - SR-059's "name-proven" restore is stated as preserved by rename, not re-hashed (3.3).
- Added 2026-10-10 (second review):
  - SR-038's witness-publish wording changes under P2: the replace is atomic, `File.Move` with
    overwrite; the LLR-038 row is not re-verified here.
  - SR-075 states that RUN.state publication is fail-closed.
  - Whatever G8 decides changes SR-061/SR-064's step-6 wording.
- README "A run refuses because Temp exists" is rewritten on ship. Step (4) is removed.

## 9. Open questions

Engineering (decidable without the Owner):
- E1. Whitelist for Temp: MANIFEST.csv, its .meta, DIRECTORIES.csv, RUN.inprogress, the kit files,
  and data files whose names hash-verify. Is re-hashing every Temp object affordable? Superseded
  data can be large. Cost not measured.
  **Revised 2026-10-09 (Owner speed constraint): no re-hash.**
  - The whitelist adds `RUN.state`, `RECOVERY.done`, their `.tmp`s and `MANIFEST.csv.meta.tmp`.
  - Added 2026-10-10, round 3: the empty probe directory `.fbrecover-probe` is accepted residue
    (set aside, then removed).
  - Added 2026-10-10, round 3: ntfs-3g rename residue, `^<whitelisted name>\.ntfs-3g-\d{10}$`,
    is RECOGNISED, by the Temp and pool classifiers alike, so that a refusal names it. It is
    never whitelisted for deletion.
  - A data file is accepted when its name parses by the SR-069 grammar (pure) and a Temp manifest
    row names it. Both checks use only data already in hand: the one enumeration and the one
    manifest read.
  - 3.3 gives the reason a re-hash adds nothing to a rename. The re-hash cost question is
    therefore withdrawn, not answered.
- E2. Operate on the aside folder (proven) or in place? Proposed: aside. Recovery must then find the
  aside folder on the next run, using the same marker rules.
  **Flagged 2026-10-09: the aside option implies repeated probing.**
  - "Find the aside folder on the next run" means every normal run must enumerate ChgPath, or
    stat a pattern, for `Temp.stale-*`. That is the cost class the Owner ruled out.
  - The aside move existed to race a frozen owner. The OS lock (3.1) now proves there is no live
    owner before recovery starts.
  - Proposed default, flipped: recover IN PLACE. Temp keeps its name until cleanup, so the Temp
    existence test the run already makes finds every interrupted recovery.
  - The existing reclaim's own `Temp.stale-*` move (E′:4233-4240) is unchanged.
- E3. Prove with a test that the OS lock and the identity sample each catch a live
  Complete-ChangeFolder rename in the no-marker window.
- E4. Scope of P: Write-Manifest callers; kit revision; whether Update-BackupSnapshotKit must run on
  existing stores.
- E5. Same-volume moves are renames (E:6474 SameVolume); cross-volume they are copy-then-delete.
  Confirm a mid-copy kill is safe.
  (2026-10-10: for the FORWARD moves of steps 11 and 11.5 this is safe, because the copy goes
  INTO Temp. For the REVERSE moves of rollback it was NOT safe, so 3.3 now branches on a rename
  probe instead of `$sameVolume`.)
- E6. Watchdog contract (P4): a recovered run must report a status distinct from a refusal.
- G1 and G2 (section 4) block roll-forward. Both need a decision before build.
  (Both were decided by the coordinator, and amended in §4.)
- E7. **Existing per-row probing in the roll-forward path** (flagged for the Owner's speed
  constraint). Complete-ChangeFolder's blank loop runs one `Test-Path` per manifest row
  (E′:6216-6220). Every finalizing run pays that, and so does every roll-forward. Proposed:
  enumerate Temp once, put the leaf names in a set, and blank on non-membership. The cost drops
  from O(rows) stats to one listing whose size is bounded by Temp. This is a pipeline change, so
  it ships with the build, or alone as a speed fix.
- E8. Rollback reads the Temp manifest twice: `Test-ManifestWitness` hashes it, and
  `Read-Manifest` parses it. Can one streamed read serve both? Not required for correctness.
- E9. G8, the step-6 pair gap. Moved to the Owner decisions as (e) on 2026-10-10. It is a BUILD
  BLOCKER (§4, §5).

Engineering defaults (were Owner questions; now decided here):
- O1. Never lose. Rollback to the pre-run state, with the backup one cycle behind until the next run.
  Freshness cost accepted; D8 already rules this.
- O2. No deletion of step-10 orphans. They are reported, not removed, per the README.

Genuine Owner decisions:
- (a) Retire the README's manual recovery procedure and its step (4).
- (b) How long the aside folder is kept, and its disk cost.
- (c) Whether recovery runs automatically at the start of every backup, or as an explicit action the
  HomeHub watchdog invokes. Either way, the 1.5 gate's Temp-present deferral (3.2) is needed.
  Without it, a step-12 kill refuses the next backup before any recovery can run.
- (d) Added 2026-10-09: the upgrade boundary. Should a Temp left by a pre-RUN.state engine
  (owner record SchemaVersion 1) that cannot be rolled back keep today's refusal? That happens
  only on a one-time state, at the first run after the upgrade. Proposed: yes, keep the refusal.
  The alternative is guessing the kill point without the record. Until this is decided, 3.2 and
  §7 treat that refusal as PROPOSED, not adopted.
- (e) Added 2026-10-10: **G8, a BUILD BLOCKER.** Should step 6 stop writing the root manifest
  (option (c))? That changes when healing blanks persist. §4 lists exactly what it changes and
  what must be verified first. The recommendation is (c). Alternatives (a) and (b) are in §4.
  The recovery build does not start until this is decided.

## 10. Not determined

- The cost of re-hashing Temp (E1) is not measured. (Withdrawn 2026-10-09: recovery no longer
  re-hashes; 3.3.)
- Whether the in-place Export-Csv tear can leave a row-count-consistent truncated file on the
  production store. The analysis assumes it can.
- Whether the step-13 tear (G2) occurs in practice. The window is real in the code; its frequency is not measured.
  (Under P it is a pair window rather than a tear, and it is handled: G7.)
- **Residual (G7, step 13).** Row 4 accepts a `Mismatch` Temp manifest after E′:7045 when Rows
  agree, and re-witnesses it. Damage that is not a kill, preserves the row count and lands inside
  that window would be re-witnessed rather than refused. It is accepted because the only
  alternative available without a second record is a person, which D8 forbids. Its frequency is
  not measured. G8 option (a) would carry the same residual at step 6.
- That `[IO.File]::Move(..., overwrite: $false)` reports "destination exists" distinguishably on
  NTFS through the Owner's translation layer, and on the Linux container's filesystem. 3.3 relies
  on it, and it is not tested here.
- Whether a durable record write (RUN.state, RECOVERY.done) through the translation layer is
  durable at rename time. It is assumed to be as durable as the witness rename it copies. Not
  measured.
- Added 2026-10-10:
  - **The rename probe.** 3.3 assumes that, through the Owner's NTFS translation layer, a
    directory rename succeeding between Temp and BkpPath implies file renames there are true
    renames. That holds for NTFS and for Linux mount semantics, read from the .NET sources cited.
    It is not tested through the translation layer, and a layer that emulates directory rename by
    copying would defeat it.
  - **P2 through the translation layer.** P2 assumes `MoveFileEx(REPLACE_EXISTING)` and
    `rename(2)` are atomic through the layer. They are treated as being as atomic as P's manifest
    rename; neither is measured.
  - **Accepted residual: P2 (and P) under power loss on ntfs-3g** (round 3).
    - What ntfs-3g does: it emulates a rename over an existing file with links, in
      `ntfs_fuse_safe_rename` (ntfs-3g 2022.10.3, `src/ntfs-3g.c` L2587-2633, called from
      `ntfs_fuse_rename_existing_dest` L2635-2677). The sequence is `link(new → tmp)`,
      `unlink(new)`, `link(old → new)`, `unlink(old)`, `unlink(tmp)`.
    - The residue name is `<new>.ntfs-3g-<10-digit sequence>`: L2639 sets `".ntfs-3g-"`,
      and L2651 formats it with `"%s%s%010d"`. The round-3 review cited ~L2478-2485; in the
      2022.10.3 file the code is at the lines above.
    - The window: power loss inside that sequence can leave the witness, or under P the
      manifest, ABSENT, with the old file surviving only under the residue name.
    - The outcome: a refusal that names the residue, not a loss. The residue is never deleted
      automatically (3.2).
    - Scope: power loss only. A process kill does not interrupt the sequence, because it runs in
      the FUSE daemon, so P and P2 still cover kills. The window is a few metadata operations
      during a power cut, and it is not redesigned.
  - **The hub's NTFS driver must be confirmed at build time.** If it is the kernel `ntfs3`
    rather than FUSE `ntfs-3g`, ntfs3's rename-over-existing and its metadata ordering under
    power loss were not read here, and may behave differently. The same check covers whether
    `sync -f` reaches the store through that driver (3.2 step 3a).
  - **Metadata ordering under power loss.** The design assumes a journaled filesystem (NTFS on
    Windows, ext4) commits metadata in order. ntfs-3g has no journal, so G11's check exists. No
    stronger guarantee is designed for.
  - **`sync -f` in the container.** It needs coreutils 8.24 or later, or a BusyBox with `-f`. The
    image's `sync` is not checked here. If it lacks `-f`, the fallback is `FileStream.Flush($true)`
    on each copy-branch file plus the 3 root files: per object, and still only during a
    recovery.
  - **Source revisions.** The runtime behaviour cited (PS v7.5.0, .NET v9.0.0) was read from
    source. This dev PC runs pwsh 7.6.6 on .NET 10.0.12, and the production container's versions
    were not checked. The two cited paths should be re-read at the versions that ship. Note that
    the second review's PS line cite (L5504-5517) does not match the v7.5.0 file read here: the
    same code is at PS:5980-5993.
- Behaviour under a container memory limit (DR §5), which can move where a kill lands.
- Steps 14-15 (Optimize-ChangeFolders rewrites snapshot manifests in place, E:1062-1083) are out of
  scope but carry the same in-place-write hazard.
