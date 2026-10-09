# Design note: recovering a killed run's staging folder (Temp)

Status: REVISED 2026-10-09 after adversarial review; recommendation replaced. Design only.
No code, no repo change. All facts read with `git show New_Fix_Batch:<path>` on
C:\Projects\FileBackup; that working tree was not touched.

Cite key (branch New_Fix_Batch, line numbers from that blob): `E:` = Modules/FileBackup.Engine.psm1,
`C:` = Modules/FileBackup.Common.psm1, `F:` = FileBackup.ps1, `DR` = docs/defect-review-2026-10-05-content-index-memory.md.
Line numbers marked `~` were read by context, not exact.

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
  E:6504 copies the prior DIRECTORIES.csv into Temp.
- E:6573 step 10: `Invoke-BackupFileGroup` writes new objects directly at content-addressed
  final names: 7-Zip direct (E:811), `Copy-Item -Force` (E:824). No temp-and-rename.
- E:6587 step 11: `Move-RemovedFilesToStaging` (E:5720) MOVES removed files' pool objects into Temp.
- E:6605 step 11.5: `Save-SupersededData` (E:5798) MOVES superseded objects into Temp.
- E:6533: `$manifestChanged` is computed from the SOURCE diff (NewOrChanged or RemovedFromSource),
  not from a comparison of manifests.
- E:6636 step 12: backup root manifest rewritten IN PLACE (`Export-Csv -LiteralPath`, C:1233).
  The witness follows: tmp write (C:1327) then `Move-Item` (C:1328). C:1291 says atomicity covers
  the witness only.
- E:~6650 step 12.5: root DIRECTORIES.csv overwritten (the root copy is now the new state).
- E:6666 step 12.9: `Assert-StagingLockOwned` (fence), E:6667 heartbeat stop, E:6669
  `File.Delete` of RUN.inprogress. **After E:6669 there is no assert, no heartbeat and no marker
  until the rename.**
- E:6681 step 13: `Complete-ChangeFolder` (E:5813). If no-op or first run, E:5853 deletes Temp.
  Otherwise E:5859 reads the Temp manifest, E:5865 blanks absent DataPaths and rewrites the Temp
  manifest IN PLACE, E:5873-5882 copies the kit, E:5895 `Rename-Item` Temp -> Snapshot_*.
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

### 3.2 Split recovery, keyed on the marker

The marker deletion at E:6669 is the commit record. No separate journal is needed.

**Marker present** (killed or thrown in steps 7-12.9, before E:6669). The Temp manifest is the
PRISTINE prior manifest: nothing rewrites it before E:5865, which runs only after the marker is gone.
Roll BACK:
1. Move every Temp data file back to `BkpPath/<DataPath>`. The DataPath comes from the prior
   manifest row that names the file. Verify each by name-proof (SR-059) before the rename (3.3).
   Do this first: restoring objects is additive, and it leaves the new root manifest unchanged.
2. Restore the root manifest from the Temp copy (verified copy, then rename; 3.3).
3. Restore the root DIRECTORIES.csv from the Temp copy (E:6504). Step 12.5 overwrote it.
4. Delete the marker LAST. A kill before this step leaves the marker, so the next recovery repeats
   the same rollback. Nothing else inspects a half-finished state.

If the Temp manifest does not verify against its own witness, refuse loudly and move nothing.

**Marker absent** (killed after E:6669, before or during step 13). Step 12 has completed, so the
root manifest IS the new state. Roll FORWARD by re-running the idempotent `Complete-ChangeFolder`
(blank, kit copy, rename). Two preconditions are open. See G1 and G2 in section 4.

**Invariant, tested:** rollback never sees a blanked manifest. The blanking at E:5865 runs only
after the marker is gone. A rollback that restores a blanked manifest would orphan bytes. The
first draft's table wrongly called the step-13 Temp manifest "prior". It is snapshot form.

### 3.3 Verified, re-entrant moves

Every restore copies to `<name>.recover.tmp` in the destination directory, verifies, then renames.
- On a collision where the destination differs: if the destination fails its own name-proof and
  the Temp copy passes, quarantine the torn destination (rename aside, never delete) and replace it.
  Otherwise refuse.
- A crash during recovery must leave a state the next recovery completes. Every step is idempotent
  under the hash check.
- Keep the aside folder until a final non-recursive empty check passes.
- Cost: a compressed 7-Zip object cannot be verified without decompressing it. The verification
  cost model is an open engineering question (E1).

### 3.4 Runs that threw, not only killed

Recovery also covers a run that threw and left the same Temp. A `finally` releases the OS lock.
The marker state then decides rollback or roll-forward exactly as for a kill.

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

## 5. Separate items (P is now a build prerequisite — see the resolution above; A1 is not a gate)

**P. Atomic `Write-Manifest`.** `Test-BackupManifest` calls `Write-Manifest` unconditionally on
success (E:922). `Write-Manifest` writes the final path directly (`Export-Csv -LiteralPath`,
C:1233). Only the witness uses tmp plus rename (C:1327-1328). Change `Write-Manifest` to write
`MANIFEST.csv.tmp` and `Move-Item -Force`. Consequences:
- Common is bundled into restore kits (AGENTS §2), so a kit revision and
  `Update-BackupSnapshotKit` (E:2020) are needed on existing stores (E4).
- `MANIFEST.csv.tmp` must be whitelisted by the Temp and pool classifiers.
- Reminder: P closes the step-6 index loss, the step-12 torn index and the G2 window.

**A1. Audit: torn step-10 objects.** Step 10 writes final content-addressed names directly
(E:811, E:824). A kill mid-write leaves a torn object at a name it does not hash to. Audit whether
any reader trusts a name without checking. Treat as an orphan (O2 default: report, do not delete).

## 6. Interruption table (corrected)

"Only copy" means the bytes or index exist in Temp and nowhere else. "Recovery" is the 3.2 branch.

| Kill point (cite) | Root | Temp | Recovery | Only copy in Temp? |
|---|---|---|---|---|
| Before E:6371 | untouched | nothing | none | no |
| Step 6, mid-write (E:922, C:1233) | manifest torn; witness prior, so Mismatch | no copy | refuse (1.5); index loss; P closes it | no copy exists anywhere |
| Step 6, after write | sanitized, complete | marker only | delete Temp (no content) | no |
| Step 7 (E:6498) | prior, complete | prior manifest (maybe torn) + witness + DIRECTORIES | rollback; torn Temp manifest refuses | duplicates |
| Steps 8-10 (E:811, E:824) | prior | prior copy; torn orphans in pool | rollback (restores nothing new); orphans reported | no |
| Step 11 mid-loop (E:5720) | prior manifest claims moved objects | moved removed-file objects | rollback moves them back | **yes** |
| Step 11.5 mid-loop (E:5798) | prior manifest claims moved objects | moved superseded objects | rollback moves them back | **yes** |
| Step 12 during Export (C:1233) | torn | complete prior manifest + witness + moved objects | rollback | **yes** |
| Step 12 after Export, before witness (C:1327-1328) | new, complete; witness prior (Mismatch) | prior manifest + moved objects | rollback | **yes** |
| Step 12.5 after DIRECTORIES write (E:~6650) | new | prior manifest + moved objects | rollback, which restores DIRECTORIES too | **yes** |
| 12.9 after Assert (E:6666), before delete | new, complete | marker present | rollback | **yes** |
| 12.9 after delete (E:6669), before rename | new, complete | prior manifest + objects; **no marker** | roll forward (G1) | **yes** |
| Step 13, before E:5865 rewrite | new, complete | prior manifest, unblanked | roll forward (G1) | **yes** |
| Step 13, during E:5865 rewrite | new, complete | manifest torn | refuse (G2) | **yes; torn** |
| Step 13, after E:5865, before rename (E:5895) | new, complete | blanked manifest + partial kit | roll forward; blank and kit copy are idempotent | yes |
| After rename (E:5895) | Snapshot_* published | none | none; steps 14-15 out of scope | n/a |

Summary:
- Temp holds the only copy from step 11 through step 13, in every sub-point.
- Kills at steps 7-10 leave Temp redundant. Deleting it loses nothing.
- Steps 6, 12 and 13 have in-place index writes. Only P closes them fully (G2 for step 13).

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
- README "A run refuses because Temp exists" is rewritten on ship. Step (4) is removed.

## 9. Open questions

Engineering (decidable without the Owner):
- E1. Whitelist for Temp: MANIFEST.csv, its .meta, DIRECTORIES.csv, RUN.inprogress, the kit files,
  and data files whose names hash-verify. Is re-hashing every Temp object affordable? Superseded
  data can be large. Cost not measured.
- E2. Operate on the aside folder (proven) or in place? Proposed: aside. Recovery must then find the
  aside folder on the next run, using the same marker rules.
- E3. Prove with a test that the OS lock and the identity sample each catch a live
  Complete-ChangeFolder rename in the no-marker window.
- E4. Scope of P: Write-Manifest callers; kit revision; whether Update-BackupSnapshotKit must run on
  existing stores.
- E5. Same-volume moves are renames (E:6474 SameVolume); cross-volume they are copy-then-delete.
  Confirm a mid-copy kill is safe.
- E6. Watchdog contract (P4): a recovered run must report a status distinct from a refusal.
- G1 and G2 (section 4) block roll-forward. Both need a decision before build.

Engineering defaults (were Owner questions; now decided here):
- O1. Never lose. Rollback to the pre-run state, with the backup one cycle behind until the next run.
  Freshness cost accepted; D8 already rules this.
- O2. No deletion of step-10 orphans. They are reported, not removed, per the README.

Genuine Owner decisions:
- (a) Retire the README's manual recovery procedure and its step (4).
- (b) How long the aside folder is kept, and its disk cost.
- (c) Whether recovery runs automatically at the start of every backup, or as an explicit action the
  HomeHub watchdog invokes.

## 10. Not determined

- The cost of re-hashing Temp (E1) is not measured.
- Whether the in-place Export-Csv tear can leave a row-count-consistent truncated file on the
  production store. The analysis assumes it can.
- Whether the step-13 tear (G2) occurs in practice. The window is real in the code; its frequency is not measured.
- Behaviour under a container memory limit (DR §5), which can move where a kill lands.
- Steps 14-15 (Optimize-ChangeFolders rewrites snapshot manifests in place, E:1062-1083) are out of
  scope but carry the same in-place-write hazard.
