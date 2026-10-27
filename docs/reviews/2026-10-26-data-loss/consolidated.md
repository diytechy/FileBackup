# Consolidated review — hidden data-loss defects, BoundedRebuild @ 7532b86 (2026-10-26)

**Status (2026-10-27):** every fix and every ruling except C43's second half and C44 is built and merged on
`BoundedRebuild` (plan calls C36-C44 in [bounded-run-loop.md](../../plans/bounded-run-loop.md) section 13).
Open: C43's prune and pool-resolve rework, and C44 (the single-store layout work package). Move this folder
to an archive once those land.

## Outcome

| Item | Outcome |
|---|---|
| A1 durability | Ruled C36, built `8ec15a1` (manifests, state, kit, snapshot files, prune copies) and `3a5f5ac` (every stored object, O1); C37 (damaged objects set aside), built `7228c0b`. |
| A1 torn manifest (review G2) | Ruled C38, built `5b0a986` (both restorers: `[ManifestDamaged]`, at least 1). |
| A2 bash `&`/`#` path | Fixed, `f620c32`. |
| A3 `.fbprune.tmp` taken as an object | Fixed in both restorers `14c548e` and the engine `9f259cf`. |
| A4 kit rewritten in place | Fixed, `ce2096a` (written only when changed, by temp file and rename). |
| A5 `-RepairStorage` without the lock / under `-WhatIf` | Fixed, `ce068bc`. |
| A6 moved store, two sets under one parent | Superseded by C44: one store folder per set ([single-store-layout.md](../../plans/single-store-layout.md)). |
| A7 host problem reported as content missing | Fixed, `4fb7689`. |
| A8 README old-snapshot recipe | Fixed, `c2381af`, `912aa57`. |
| B prune leftover after commit | Ruled C41, built `f74d80a`, `25d7a2d`. |
| B partial file on a failed restore copy | Fixed, `b7477bd` then `db155a5` (the copy lands by rename). |
| B `$RECYCLE.BIN` in `DIRECTORIES.csv` | Fixed, `601272e`. |
| B case-only names on a Windows restore | Ruled C42 (unportable at backup time), built `677b711`. |
| B dependency exit code; prune needing the source | Fixed, `3756974`. Open: prune with the store drive unplugged now exits 2; 4 is the alternative. |
| C1 fsync policy | Ruled C36 (built, see A1). |
| C2 empty source exits 0 | Ruled C39 (stop with 4), built `88dc7e1`, `72a39cb`. |
| C3 damaged archive not healed | Ruled C40 (C18 stands). |
| C4 Verify memory on HomeHub | Ruled C43: the storage-form audit no longer holds whole manifests (`8ab9375`); prune and the pool-resolve check are the open follow-up. HomeHub's store gets a second look before anything runs there. |
| C5 older-engine mislabelled objects | HomeHub's store gets a second look; C37 leaves such objects alone. |

Four independent reviews against one brief ([brief.md](brief.md)), all of commit `7532b86`:

| # | Reviewer | Scope | Report |
|---|---|---|---|
| 1 | opencode `opencode-go/gemini-4-argon`, plan agent, detached worktree | whole repository | [review-1-opencode-argon.md](review-1-opencode-argon.md) |
| 2 | Claude Opus 5.5, main session | the backup run | [review-2-backup-run.md](review-2-backup-run.md) |
| 3 | Claude Opus 5.5, fresh context | the restorers | [review-3-restorers.md](review-3-restorers.md) |
| 4 | Claude Opus 5.5, fresh context | retention, Verify, lock, kit, entry points | [review-4-retention-verify.md](review-4-retention-verify.md) |

Every finding below was re-checked against the code by the main session; "repro" means a reviewer ran it. The
repro scripts are in [repros/](repros/) (paths inside them and in the reports point at the session's scratch
folder, which no longer exists). Reviewer 1's first run spent its whole output budget thinking and wrote nothing;
the same session was resumed with `--variant low` and produced its report ([prompt](repros/opencode-prompt.md)).

## A. Recommended to fix (normal scenario or plausible failure)

### 1. High — nothing is made durable before it is named, renamed over, or relied on (power loss / OS crash) — all four reviewers
No `Flush($true)`/fsync anywhere. Journaling filesystems commit the rename/delete independently of the data:
ext4 (delalloc) returns a file renamed to a NEW name as 0 bytes; NTFS returns it at full length reading NULs.
- **Objects:** `Copy-FileWithHash` (Engine:4371-4387) → `Publish-StagedObject` rename (:4520-4524); 7-Zip output (:4499).
  The run indexes by name only (`Get-StoreObjectIndex` :4080-4094 never compares `FileLength` to the name's length),
  an unchanged source file is `Kept`, so a damaged object is reused forever; `Publish-StagedObject` even drops a good
  re-staged copy when the name exists. Only `Verify -Deep` or a restore notices. **Permanent** once the source changes.
- **Snapshot manifest:** `Publish-PriorStateSnapshot` (:4976-4985) writes `Building_D/MANIFEST.csv` (new name) then
  renames the folder. Torn from byte 0 → restorers refuse (2). **NUL tail → restore exits 0 with a partial tree**
  (restorer reviewer: 4 of 13 files, exit 0, both restorers). The next run keeps the existing `Snapshot_D` as is and
  overwrites the latest manifest, so state D is **permanently** lost or silently partial.
- **Prune:** `Copy-ReHomedDataFile` publishes the last copy (:2592) and the transaction then deletes the source
  snapshot, with no flush → after a crash the only copy can be NULs/0 bytes while the delete has committed. **Permanent.**
  `Publish-PruneManifest`/repair rewrite a snapshot manifest (rename-over; ext4 protected, NTFS/XFS not).
- **Latest manifest:** a 0-byte one is read as an empty backup (`Read-PriorStateForRun` :5713) — self-heals by a full
  re-hash but loses state D; a NUL one is refused with 2 until a person moves it aside.
- **Fix tiers (Owner's cost call):**
  1. Near-free: `Flush($true)` on `MANIFEST.csv.tmp` (Write-Manifest), the state-file temp, the snapshot's files before
     `Building_D` → `Snapshot_D`, and each prune re-homed copy before the commit rename.
  2. Objects: `Flush($true)` in `Copy-FileWithHash` and on the `.7z`. Measured (flush + rename, 64 KiB): NVMe +1.4 ms/file;
     SATA laptop HDD +49 ms/file → ~25 s per 500 new files, ~2.5 h extra on a 180,000-file initial backup to an HDD.
     On Linux one `sync -f` (syncfs) before each manifest publish covers every earlier object for one call.
  3. Zero-cost guards: index skips (and sets aside) a raw object whose length ≠ its name's length or a 0-byte `.7z`;
     restorers refuse a manifest containing NUL or not ending in a newline (Write-Manifest always ends rows with one);
     the engine refuses a 0-byte latest manifest when the store has history.

### 2. High (restore side, no bytes lost) — `reconstruct.sh` loses every sibling snapshot when the change-root path holds `&` or `#` — repro
`bash/reconstruct.sh:1366-1367`: `sed "s#^#$change_root/#"`. `&` inserts the match, `#` ends the command. Restoring an
older snapshot (which normally needs objects C23 put in a newer one) exits 1 "content missing"; `--change-root` goes
through the same sed. Folder names like `Backups & Archive` or a USB label `Backup #2`. PowerShell kit unaffected.
Fix: `snapshots+=("$change_root/$sn")` in the read loop; drop the sed. (Argon flagged this; I wrongly dismissed it
first — my grep was truncated.)

### 3. Medium — a prune killed mid-copy leaves `<object>.fbprune.tmp`, which every name reader accepts as the object — 2 repros
`Copy-ReHomedDataFile` (Engine:2560) stages beside the destination; `.7z.fbprune.tmp` passes the SR-069 extension rule
in Common, Engine and bash. The kit tries the origin folder first → a partial archive → `CandidateError` (4), no
fallback (C18). Lasts until a later prune's sweep, and the killed prune's `Temp/` blocks prunes until a person acts.
Engine side (not traced): `Get-StoreObjectIndex` can adopt it as the object. Fix: the three name readers reject a name
whose extension holds a second `.` (an object's extension is one `GetExtension` segment), or stage under the prune's `Temp/`.

### 4. Medium — every run overwrites the 7 kit files in place — repro (me and retention reviewer independently)
`New-ReconstructScript` (Engine:2915-2966), unguarded at :6154. A restore session started from the backup root keeps
`System.IO.Hashing.dll` loaded → `Copy-Item -Force` fails → every backup exits 4 until that window closes. A kill /
power loss mid-copy leaves a torn kit in the latest root, copied into `Snapshot_D` the same run (a torn kit reads as
revision 1 → prune refuses). Fix: copy only when the bytes differ, via temp + rename.

### 5. Medium — `-RepairStorage` moves objects into `Verify/` without the OS lock, and under `-WhatIf` — repro
`FileBackup.ps1:528` calls `Move-StoreObjectToVerify` before anything takes `Temp.lock` (only `Repair-BackupStorageForm`
takes it, Engine:2017). With the lock held elsewhere it moved the duplicate, then exited 2 "nothing was touched".
Loss path: a prune deletes the kept copy during a long `-Deep` repair; the repair then moves the last copy to `Verify/`,
which the Owner empties. Breaks the AGENTS.md §3 lock invariant. Fix: take the lock before the object audit; honour `-WhatIf`.

### 6. Medium — two sets' store folders under one parent: a snapshot restore of a moved store never finishes — read + restorer observation
`Reconstruct.ps1:645-657` (and bash twin): when the sidecar is ignored (drive letter changed on a new PC, store copied,
Linux restore) and the parent holds two `MANIFEST.csv` siblings, the backup root stays the bare parent. Nearly every
snapshot row (C10 keeps DataPaths into the backup root) then falls to `Find-DataFileByHash`, which re-lists the pool
recursively per row (:399) — rows × pool. README's own example puts `DataStore`/`DataChanges` side by side under
`E:\Backups`. No wrong bytes, no warning. Fix: record the backup root relative to the change root in the sidecar (or
index every candidate sibling — verification keeps it safe), and warn when ambiguous.

### 7. Medium — a host problem on a non-blank row is reported as content missing (exit 1, not 4) — repro
`Reconstruct.ps1:1320` / `reconstruct.sh:1463-1474`: only blank rows keep the scan's cause. Since C10 nearly every row is
non-blank, so an unreadable pool folder reads as "real data loss". Fix: return the scan's cause unless `ContentMissing`.

### 8. Medium (docs) — README's "restore an old snapshot with the live kit" recipe reports false data loss — repro
`README.md:450-455` (`-BackupRootOverride <snapshot>`): exit 1, 11 of 13 rows missing; the real backup root drops out of
the pool. Fix the recipe (copy the kit into the snapshot, `-RefreshKits`, or bash `--from`), or add `-From`.

## B. Low
- Prune: a failed delete after the commit rename is reported "failed before the commit point" (4), and `Pruning_<name>`
  stays until that same name is pruned again — a space leak, no loss (Engine:2657-2659, :2844). (argon)
- Restore copy failure leaves a partial file (bash :351, ps1 :1414); bash deletes a pre-existing target file on a failed
  expand (:349). (argon, restorer)
- Volume-root source: `$RECYCLE.BIN` recorded in `DIRECTORIES.csv` and recreated on restore (`Get-SourceDirectoryRecord`
  never calls `Test-IsVolumeRootPseudoPath`, Engine:524-551). (argon)
- Case-only-different paths from a Linux store collapse silently on a Windows restore, exit 0 (Reconstruct.ps1:1086-1094).
- A missing hashing package / 7-Zip escapes as exit 1 with no mail (FileBackup.ps1:408); Prune/Snapshots use the
  resolver that requires `SourcePath`, so with the source offline they do nothing (FileBackup.ps1:436).

## C. Ruling questions for the Owner
1. **fsync policy** (item A1): which tiers? AGENTS.md accepts "no fsync" only for the latest manifest.
2. **C2 exit code:** a source empty at walk start warns and exits **0**. In the container a dead/unmounted source drive
   looks exactly like this; NagLight stays green while the latest restores empty and age-based retention can later prune
   the only snapshot holding the library. 1 (or 4, like C27)?
3. **C18 vs C22/C28:** keeping duplicates assumes "a restore heals a damaged copy from another one", but a damaged
   *archive* (7-Zip CRC failure) ends the row as `CandidateError` with no other copy tried. Fall through to the next
   candidate when 7-Zip passes its self-test?
4. **Before resume step 3 (plain Verify on HomeHub):** the retention reviewer estimates ~11 GB for whole-manifest indexes
   on a 7.6 GB hub (status.md:233-235 already says prune would OOM). Not verified here — check before running it.
5. Does HomeHub's store hold rename-class (`NameLies`) findings from older engines? If so, a kill mid `-RepairStorage`
   can wedge retention (retention F5, argon F4 — both need such an older-engine object; repro made one by hand).

## D. Checked and rejected
- argon F2 (unreadable-folder prefix): a denied folder's `TargetObject` is its full path under the root (repro), so rows
  are frozen as designed; the case-sensitive variant needs `Docs/` and `docs/` siblings — contrived.
- argon F4 / retention F5 as defects: need an older-engine mislabelled object plus a kill mid-repair → question C5.
- Compiled manifest writer throwing on a row with no `LastWriteTime`: `ParseExact` refuses such a row first (loud 2).
- Case-insensitive collision of base-57 object names: ~110 effective bits; negligible.

The first full gate on the merged fixes surfaced two order-dependent test faults, fixed in `5d8bf00` and `14ad7ea`.
The HomeHub side of the contract is prepared, unmerged, on HomeHub branch `filebackup-review-contract`.
