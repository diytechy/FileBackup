# Design note: recovering a killed run's staging folder (Temp)

Status: REVISED 2026-10-09 after adversarial review; recommendation replaced. REVISED AGAIN
2026-10-09 after an independent review (two findings, below). Design only. No code, no repo
change. All facts read with `git show <branch>:<path>` on C:\Projects\FileBackup; that working
tree was not touched.

Cite key (branch New_Fix_Batch, line numbers from that blob): `E:` = Modules/FileBackup.Engine.psm1,
`C:` = Modules/FileBackup.Common.psm1, `F:` = FileBackup.ps1, `DR` = docs/defect-review-2026-10-05-content-index-memory.md.
`E′:` = Engine re-verified against `fix-staging-os-lock` (058ffc5, which carries P as well);
`C′:` = Common re-verified against `fix-p-atomic-write-manifest` (23793f3; byte-identical on
`fix-staging-os-lock`). Line numbers marked `~` were read by context, not exact.

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

**RUN.state (G1's record, now written before step 10).** The record is written ONCE, after the
step 9.4 capacity preflight (E′:6916-6929) and before step 10's first write. It holds `RunId`
(it must equal the marker's), `ManifestChanged` (final at E′:6909) and `SnapshotDate`
(`priorBackupDate`, so that roll-forward does not depend on FileBackupState.json).
- After 9.4, so `$refuseCapacity`'s `Remove-OwnStagingFolder` never meets it (G9).
- Before step 10, so its absence is a proof: marker present and no RUN.state means no step-10,
  11 or 11.5 write has happened, and no step-12 root rewrite.
- It is deleted only by `Complete-ChangeFolder` (3.5) and by recovery cleanup, never while the
  marker exists.
- Upgrade: the owner record's `SchemaVersion` (E′:3063) goes to 2 when RUN.state ships, and RUN.state's absence means
  "pre-mutation" ONLY under a SchemaVersion-2 marker. A SchemaVersion-1 Temp, left by an older
  engine, is rolled back when its Temp manifest verifies (row 3 without the record). Otherwise it
  refuses as it does today. That is a one-time upgrade boundary; Owner decision (d).
- Cost: on a normal run, one ~200-byte write plus one rename, and one delete at finalize. For
  recovery, one small read.

**Row 2: discard (pre-mutation). Finding 2's step-7 case.** A kill between C′:1284 and C′:1386
inside step 7 leaves a complete `MANIFEST.csv`, no `MANIFEST.csv.meta`, and possibly a
`MANIFEST.csv.meta.tmp`. The same row covers kills in steps 8-9.4. It also covers a kill part-way
through the 9.4 refusal's `Remove-OwnStagingFolder`.
- Condition: every entry in the enumeration is in the pre-mutation set: `RUN.inprogress`,
  `MANIFEST.csv`, `MANIFEST.csv.tmp`, `MANIFEST.csv.meta`, `MANIFEST.csv.meta.tmp`,
  `DIRECTORIES.csv`, `RUN.state.tmp`. Any other entry, such as a data file, contradicts program
  order. That is not a kill state, so recovery refuses loudly and moves nothing.
- Action: publish `RECOVERY.done` (Outcome=Discarded), then clean up (3.5). The root is not
  touched.
- Why no witness is needed: the Temp manifest is a copy of the root's. Step 6 wrote the same
  `$backupDb` object to the root one statement earlier (E′:929 returning to E′:6858, then
  E′:6874), and nothing mutates it in between. Temp holds no bytes, and the root has not been
  rewritten since. So Temp is redundant whatever state its manifest/witness pair is in. The
  witness verdict never enters the decision.
- **Is data-file absence alone a sound signal? No.** (i) A run whose steps 11 and 11.5 move
  nothing keeps Temp data-free all the way through step 13. Step 12 has replaced the root by
  then, and Temp's manifest is the ONLY copy of the prior index; discarding there would lose a
  restorable point in time. (ii) A cross-volume move killed mid-copy (E5) leaves a data-named
  partial file although no move completed. Absence of data proves only "Temp holds no only-copy
  bytes". RUN.state's absence is what proves "the root is still the index Temp copied". The
  name check stays as a tamper guard, not as the signal.
- Rejected: a separate "step 7 complete" marker. It would be a second write with its own kill
  window, and RUN.state already dates every kill before step 10.
- Cost: recovery reads nothing beyond the classifier's enumeration and its marker read. It does
  one record write, at most 8 deletes and one rmdir: no hash, no manifest read.

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
4. Publish `RECOVERY.done` (Outcome=RolledBack, RunId). This is the rollback's commit. **The
   marker is NOT deleted here.**
5. Clean up (3.5).

A kill anywhere in steps 1-4 leaves the marker and RUN.state, with no RECOVERY.done. The next
recovery lands on row 3 again and repeats steps 1-4. Each step is idempotent: moves per 3.3, and
the root Write-Manifest is a fixed point.
- Cost: one read and hash of the Temp manifest (the witness check) plus one `Read-Manifest` of
  it; sharing that read is E8. Then N renames on the same volume, or N copies across volumes,
  where N is the number of data files in Temp. Then one manifest write at the root, one sidecar
  copy and one record write. No pool enumeration, no per-object hash, no per-row probe.

**Row 4: roll forward.** A marker-less, non-empty Temp means E′:7045 ran. After this revision
nothing else deletes the marker of a non-empty Temp. Recovery keeps it until RECOVERY.done exists
(rows 1-3). `Remove-OwnStagingFolder` deletes it last, after every other leaf (E′:4527), which
leaves an empty folder (row 5). Re-run `Complete-ChangeFolder` with RUN.state's values. If
RUN.state is absent, publish (coordinator rule, G1). Then check the witnesses:
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
- **Same volume** (`$sameVolume`, E′:6850): move back with
  `[IO.File]::Move(src, dst, overwrite: $false)`. A rename cannot change bytes.
  - If the move fails because dst exists, the root already holds that object. It is either the
    cross-volume original whose delete never ran, or this rollback's own earlier pass. Step 10
    cannot have created it: content addressing never writes over a name the pool already held,
    and this object was in the pool at step 10.
  - The Temp copy is then redundant and is left for cleanup. The failed call IS the existence
    test, so there are no extra probes.
- **Cross volume:** copy to `BkpPath\<leaf>.recover.tmp`, deleting any leftover first. Compare
  the copy's length with the source length from the Temp enumeration (no stat). Then
  `File.Move(tmp, dst, overwrite: $false)`; "exists" is handled as above. The source stays in
  Temp, and cleanup deletes it after RECOVERY.done. A torn `.recover.tmp` from a killed pass is
  overwritten by the next pass.
- **The first draft's "collision with different bytes, quarantine the destination" branch** is
  unreachable by the argument above. If it is ever hit (dst exists and one stat shows a length
  different from the Temp source), refuse loudly: it is not a kill state.
- **Hashing** stays available as an explicit audit (`-Action Verify`), not as a recovery step.
- **Cost:** per Temp data file, one rename (same volume), or one copy plus one rename (cross
  volume). No hash, no pool scan, no per-object probe.

### 3.4 Runs that threw, not only killed

Recovery also covers a run that threw and left the same Temp. A `finally` releases the OS lock.
The marker state then decides rollback or roll-forward exactly as for a kill.

### 3.5 Ending a recovery, and the pipeline's own discard (finding 1)

*New 2026-10-09 (review).* **Cleanup** is entered from row 1, or straight after a rollback or a
discard publishes RECOVERY.done:
1. Delete every leaf except RECOVERY.done, in any order and each by exact name. That covers the
   marker, `RUN.state` and `RUN.state.tmp`, the manifest set (`.csv`, `.meta` and both `.tmp`),
   DIRECTORIES.csv, the kit files and the data files. A data file is a name that parses by the
   SR-069 grammar, which is a pure check with no I/O. Every one of these leaves is redundant:
   RECOVERY.done is published only after the rollback put each byte back at the root (or found it
   already there), or after the discard proved that none was ever moved.
2. Delete RECOVERY.done LAST, then `Directory.Delete(Temp, recursive: $false)`.

An entry outside that set keeps the folder, and recovery logs it loudly. It is not a kill state.

| Cleanup kill point | Next recovery sees | Does |
|---|---|---|
| after RECOVERY.done is published, before any delete | row 1 | cleanup from the start |
| part-way through step 1 (any subset gone, marker included) | row 1 | resumes deleting |
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
    null), which discards again.
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
- **G8. The same pair gap at step 6. It exists under P, and it is NOT handled. Flagged.**
  - `Test-BackupManifest` rewrites the root unconditionally (E′:929). A kill between the rename
    and the witness leaves a complete sanitized root beside the pre-run witness: `Mismatch`.
    Temp then holds only the marker.
  - The 1.5 deferral lets the next run reach recovery. But the existing marker-only reclaim does
    not touch the root, so the gate then refuses, and that is a person.
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
  - (c) closes the window and also removes one full manifest write from EVERY run, which suits
    the Owner's speed constraint. Recommended; not decided. It needs the coordinator, because it
    changes step 6's contract (SR-061/SR-064 wording).
- **G9. §2.2's "all callers run BEFORE step 7" was wrong.** `$refuseCapacity` (E:6469) runs at
  step 9.4 (E:6553). That is why RUN.state is written after 9.4 rather than at step 7.

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

## 5. Separate items (P is now a build prerequisite — see the resolution above; A1 is not a gate)

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

**A1. Audit: torn step-10 objects.** Step 10 writes final content-addressed names directly
(E:811, E:824). A kill mid-write leaves a torn object at a name it does not hash to. Audit whether
any reader trusts a name without checking. Treat as an orphan (O2 default: report, do not delete).

## 6. Interruption table (corrected; revised 2026-10-09 for P and the review)

P is a build prerequisite, so the table assumes it: no manifest is ever torn. The old pre-P rows
("mid-Export, torn") are therefore replaced by the manifest/witness PAIR windows, written "after
rename, before witness" (C′:1284 to C′:1386). "Only copy" means the bytes or the index exist in
Temp and nowhere else. "Row" is the 3.2 classification. Cites are E′ (fix-staging-os-lock).

**6.1 Pipeline kill points**

| Kill point (cite) | Root | Temp | Recovery | Only copy in Temp? |
|---|---|---|---|---|
| Before E′:6746 | untouched | nothing | none | no |
| Step 6, before rename (E′:929 → C′:1275) | prior; maybe a root `MANIFEST.csv.tmp` (infrastructure, E′:78) | marker only | existing reclaim | no |
| Step 6, after rename, before witness | sanitized, complete; witness pre-run, so **Mismatch** | marker only | 1.5 defers, reclaim; root still Mismatch, so the run **refuses**: **G8, open** | no |
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
| Step 12.5, after DIRECTORIES write (E′:7023) | new | same | row 3: rollback, which restores DIRECTORIES too | **yes** |
| 12.9 after fence (E′:7042), before delete | new, complete | marker present | row 3: rollback | **yes** |
| 12.9 after delete (E′:7045), before E′:6221 | new, Verified | prior manifest + objects + RUN.state; **no marker** | row 4: roll forward | **yes** |
| **Step 13, E′:6221 after rename, before witness** | new, Verified | **blanked** manifest + step-7 witness (**Mismatch**) | row 4: accepted when Rows agree; re-run re-witnesses (G7) | **yes** |
| Step 13, after witness, kit copy partial (E′:6229-6239) | new, Verified | blanked + Verified + partial kit | row 4: roll forward; blank and kit copy are idempotent | yes |
| Step 13, after RUN.state delete, before rename (E′:6254) | new, Verified | complete, no record | row 4: no record, so publish (correct here) | yes |
| No-op / first-run discard, part-way (E′:6209 as replaced, 3.5) | new, Verified | leaves remaining + RUN.state (deleted last) | row 4: ManifestChanged=false or no date, so discard again | no |
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
| Discard (row 2), RECOVERY.done published or mid-deletes | untouched | subset + record | row 1 | no |
| Roll forward, anywhere in the re-run | new, Verified | as in the step-13 rows of 6.1 | row 4 again | as 6.1 |

Summary:
- Temp holds the only copy from step 11 through step 13, in every sub-point.
- Kills up to step 10 leave Temp redundant; deleting it loses nothing. Through step 9.4 the
  absence of RUN.state proves it without reading the witness.
- Under P no manifest is torn. Every remaining index window is a manifest/witness pair. Steps
  7, 12 and 13 and rollback step 2 resolve automatically (G6, G7). **Step 6 does not, G8.**
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
- **SchemaVersion-1 Temp** (upgrade): with a verifying Temp manifest it rolls back. With no
  witness it refuses as today.
- **Cost assertions** (the Owner's speed constraint): count filesystem calls through the seams.
  - A normal run with no Temp adds zero existence tests over today, and exactly one record write,
    one rename and one delete.
  - A recovery makes no pool enumeration and no per-object hash, and its call count is linear in
    Temp's entry count.
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
- README "A run refuses because Temp exists" is rewritten on ship. Step (4) is removed.

## 9. Open questions

Engineering (decidable without the Owner):
- E1. Whitelist for Temp: MANIFEST.csv, its .meta, DIRECTORIES.csv, RUN.inprogress, the kit files,
  and data files whose names hash-verify. Is re-hashing every Temp object affordable? Superseded
  data can be large. Cost not measured.
  **Revised 2026-10-09 (Owner speed constraint): no re-hash.**
  - The whitelist adds `RUN.state`, `RECOVERY.done`, their `.tmp`s and `MANIFEST.csv.meta.tmp`.
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
- E9. G8, the step-6 pair gap. Option (c) is recommended; it needs a decision before build,
  because D8 forbids a person.

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
  The alternative is guessing the kill point without the record.

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
- Behaviour under a container memory limit (DR §5), which can move where a kill lands.
- Steps 14-15 (Optimize-ChangeFolders rewrites snapshot manifests in place, E:1062-1083) are out of
  scope but carry the same in-place-write hazard.
