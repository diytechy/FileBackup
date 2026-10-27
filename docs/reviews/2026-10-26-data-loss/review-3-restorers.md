# Review: the standalone restorers (Reconstruct.ps1 / bash/reconstruct.sh, kit 14) — BoundedRebuild @ 7532b86

## 1. What was done

**Read**
- The brief.
- AGENTS.md §1–4.
- `docs/plans/bounded-run-loop.md`: R1–R14 and C1–C35.
- `docs/plans/bounded-run-loop-reviews.md`: reviews 1–5.
- README: Restore, Restore exit codes, Restore on Linux, Older snapshots carry the restore kit, What is not recorded, Notes & troubleshooting.
- All of `Reconstruct.ps1` and all of `bash/reconstruct.sh`.
- In Common: `Get-FileXxHash`, `ConvertFrom-HashSizeFileName`, `Test-LegacyStoredObjectName`, `Expand-FileWithSevenZip`, `Get-StoredObjectForm`, `Get-FreeSpaceBytes`, `Resolve-ExistingAncestor`, `Read-Manifest`, `Write-Manifest`, `New-RelativePathMap`.
- In Engine, to know what the restorers are fed: `New-ReconstructScript`, `Publish-PriorStateSnapshot`, `Get-StoreObjectIndex`, `ConvertFrom-StoredObjectName`, `Get-LatestObject`, `Update-BackupSnapshotKit`, `Copy-ReHomedDataFile`, `Invoke-PruneEntrySweep`, the `Remove-BackupSnapshot` transaction, and `Invoke-BackupSet` steps 2–3.

**Ran** (nothing in the repository; no Pester; no Run-All)
- Exported HEAD with `git archive HEAD Modules Reconstruct.ps1 bash FileBackup.ps1` into `<scratchpad>\fb-head`.
- Built stores with the tool itself (`FileBackup.ps1`, `CompressEnabled=true`, 7-Zip 24) under `%TEMP%\fbrr-*`. Store A: 2 runs. Store B: 3 runs, in a folder named `Backups & Archive`. In store B, `f02.txt` v1 is named by both snapshots and lives in the newer one, so restoring the older snapshot needs a sibling snapshot.
- Restored these stores with the bundled PowerShell kit on Windows and with the bundled `reconstruct.sh` in WSL Fedora (`podman-machine-default`: gawk, xxhsum 0.8.3, p7zip).
- Repro scripts are in `<scratchpad>\tools\`: `mkstore.ps1`, `mkstore3.ps1`, `expA.ps1`, `expC.ps1`, `expD.ps1`. Experiment B and the `#` variant were inline `wsl` commands.

`<scratchpad>` = `C:\Users\Peter\AppData\Local\Temp\claude\c--Projects-FileBackup\a79ce2cf-0cdb-4d8a-bf86-f4dab9fe2166\scratchpad`.

## 2. Where the artifact is

`C:\Users\Peter\AppData\Local\Temp\claude\c--Projects-FileBackup\a79ce2cf-0cdb-4d8a-bf86-f4dab9fe2166\scratchpad\review-restorers.md`

## 3. What was checked and found clean

**Exit 0 with wrong or missing bytes, for an intact tool-made manifest:** no path found.
- Every row that carries a hash is verified after the write: `Reconstruct.ps1:1437-1451` and `reconstruct.sh:362-373`.
- A mismatch deletes the bad file and heals once from the content scan. A second mismatch on a hash-proven source is `WriteMismatch` (4).
- The final classification is the same in both restorers (4 > 1): `Reconstruct.ps1:1678-1689`, `reconstruct.sh:1560-1570`.
- Rows with no hash, or a blank RelativePath, exist only in a damaged manifest (see ruling question 1 and F5).

**Restore damaging the store or anything outside the target:** none found.
- The target is refused inside the backup root or the change root, compared by physical path. bash refuses an indeterminate answer.
- Every row and every DIRECTORIES.csv row is checked against the target (`Reconstruct.ps1:1550, 1580`; `reconstruct.sh:452, 1424`).
- Expand scratch is on the target (`:1169`, `SCRATCH_DIR`). The 7-Zip self-test uses the system temp.
- No `Remove-Item` or `rm` targets the store.
- Bracketed paths work with `New-Item -Path`, `Copy-Item -Destination` and `Move-Item -Destination` (tested on pwsh 7.6).

**Name index**
- The gawk decoder matches the PowerShell alphabet exactly, with the same 128-bit and 2^63 range limits. Keys are upper-case hex plus a decimal length.
- Candidate order is origin, then backup root, then snapshots newest first. The first candidate that exists is used, and it is built lazily.
- An index hit has its form decided from its bytes (SR-068) and is verified after the write.

**Form, expand and timestamps**
- `Get-StoredObjectForm` and `stored_object_form` agree.
- `Expand-FileWithSevenZip` stops on every failure and moves the payload on the destination's volume, so a pre-existing target file survives a failed expand in PowerShell.
- Timestamps are stamped only after verification. `ParseExact('O')` keeps the offset.

**Root detection (C21/C32)**
- The sidecar is honoured only while the origin is inside the roots it records.
- C21 and C32 pick exactly one sibling or child. Zero or several fall back safely: correctness holds because every write is verified.

**Store continued by the new engine, old snapshots restored with their own old kits (4–13)**
- Manifests are write-once, so old witnesses stay valid. Prune and repair delete the `.meta`, and old kits warn.
- Objects leave only folders with kit 4 or later (`Get-LatestObject`, `Engine.psm1:4758-4763`). Kits 4 and later fall back to the content scan.
- An old kit's parent guess (`/store`, or the common parent of the store folders) scans recursively, so moved objects are found, slowly.
- New snapshots always get the current kit.
- `-RefreshKits` and `bash reconstruct.sh --from <Snapshot>` both restore old snapshots correctly (store B: exit 0).

**Torn manifests that read as zeros from byte 0, or are zero-length:** the header check refuses with 2, loudly, in both restorers.

## 4. Findings, most severe first

### F1 — High (restore side; no bytes lost): bash drops every sibling snapshot when the change-root path contains `&`, `#` or `\`, and reports false data loss

- **Where:** `bash/reconstruct.sh:1364-1369`. The snapshot list is prefixed with `sed "s#^#$change_root/#"`.
  - In the replacement, `&` means "the match", so `/x/Backups & Archive/changes` becomes `/x/Backups  Archive/changes/Snapshot_…`.
  - A `#` ends the `s` command: `sed: unknown option to 's'`, and the list is empty.
- **Effect:** `snapshots[]` holds non-existent paths, or nothing.
  - The name index (`:1391`) and `find_by_hash` (`:1369`) skip those folders.
  - A row whose object lives in a sibling snapshot gets `StorageUnreadable`. With C10 every snapshot row is non-blank, and F3 turns that into content-missing.
  - `--change-root` passes through the same `sed`, so it does not help.
- **Steps (run):**
  1. Store B under `…\Backups & Archive\{backup,changes}`, made with 3 runs.
  2. In WSL: `bash <older snapshot>/reconstruct.sh --from <older snapshot> --target-root /tmp/x`.
  3. Result: **exit 1**, "1 content-missing: f02.txt … no pool file matches". `BDNbJ…_AdF.7z` is in the newer snapshot.
  4. Same with a `#` path (`/tmp/Backup #2/…`): exit 1 plus the sed error.
- **Controls:**
  - The same store at `/tmp/plainstore`: exit 0.
  - `Reconstruct.ps1` on the `&` path: exit 0.
- **Permanent or self-healing:** permanent for the Linux restorer while the path holds the character. Moving the store, or using the PowerShell kit, works around it.
- **Why not contrived:**
  - Restoring an older snapshot on Linux from a copied store is a documented supported path.
  - Every older snapshot normally needs objects in a newer one: C23 puts an object in the newest snapshot that names it.
  - `&` and `#` are ordinary in Windows folder names and USB volume labels (`/media/u/Backup #2`).
- **Fix:** build the path in the read loop and drop the last `sed`: `[[ -n "$sn" ]] && snapshots+=("$change_root/$sn")`.

### F2 — Medium: both name indexes treat an interrupted prune's staged copy (`<object>.fbprune.tmp`) as the object; a partial one blocks the intact original (exit 4, retry never helps)

- **Where:**
  - The residue is written by `Copy-ReHomedDataFile` (`Engine.psm1:2560-2561`) into the re-home destination, and it stays until the next prune's sweep (`:2825`).
  - The SR-069 parsers accept `.7z.fbprune.tmp` as an opaque extension:
    - `Reconstruct.ps1:561-571` (`New-StoredObjectNameIndex`)
    - `reconstruct.sh:876-877` (`decode_hash_size_names`)
  - The origin is indexed first, so in the destination folder the residue is the first candidate (`Reconstruct.ps1:607-609`, `reconstruct.sh:896-900`).
  - An archive-shaped partial fails to expand and becomes `CandidateError`, with no further candidate tried (C18): `Reconstruct.ps1:1626-1630`, `reconstruct.sh:1497-1501`.
- **Steps (run, `expD.ps1` and its bash twin):**
  1. In store B, put a half-length copy of `BDNbJ…_AdF.7z` into the older snapshot as `BDNbJ…_AdF.7z.fbprune.tmp`. This is what a prune of the newer snapshot killed mid-copy leaves (the C23 pattern re-homes into the older snapshot that demands the key).
  2. Restore the older snapshot with its own kit.
  3. Result: PowerShell **exit 4**, "resolved by name index to '…\BDNbJ…_AdF.7z.fbprune.tmp' … 7-Zip extraction failed". bash: **exit 4**, the same.
  4. The intact original is still in the newer snapshot.
- **Permanent or self-healing:** it lasts until the next `-Action Prune`. A backup run does not clear it. Until then every restore of that folder's state reports "host problem, retry", which never succeeds.
- **Why not contrived:** prune is normal operation, and a kill, OS crash or power loss mid-copy is in the brief's list. A raw object heals (the length mismatch leads to the content scan); only archive objects, the norm under compression, hit this.
- **Fix:** in both name indexes, skip names whose extension contains a second `.`. An object's extension is a single `GetExtension` segment (`Engine.psm1:4492`), so no real object is lost. The narrower option is to skip `*.fbprune.tmp`.
- **Engine side, not traced (see Q3):** `Get-StoreObjectIndex` (`Engine.psm1:4081-4094`) accepts the same residue.

### F3 — Medium: a non-blank DataPath row turns a host problem into "content missing" (exit 1); since C10 that is nearly every row

- **Where:**
  - `Reconstruct.ps1:1316-1321`: only a blank row keeps the scan's cause; a non-blank row is always `MissingDataFile`, which is content class.
  - `reconstruct.sh:1463-1474`: the same.
- **Effect:**
  - C10 keeps DataPaths in snapshots, and every latest row has one. A stale DataPath is normal (C11).
  - So an unreadable pool folder, or a folder that vanished, now gives exit 1 ("real data loss: check an older backup") where the README table says 4 ("an unreadable search folder"). Examples of the cause: an ACL or uid mismatch on a copied store, a directory the drive cannot read, the USB drive pulled mid-restore.
- **Steps (run, `expC.ps1`):**
  1. In a copy of store B, deny list access on the newer snapshot.
  2. Restore the older snapshot.
  3. Result: **exit 1**, "[MissingDataFile] f02.txt … no pool file matches its (hash,length)". The scan had met `StorageUnreadable`.
- **Permanent or self-healing:** the code is wrong each time; no data is lost.
- **Why not contrived:** a single host problem, the class the brief lists (a volume disappearing, a share dropped).
- **Fix:** for a non-blank row, return the scan's cause and detail unless it is `ContentMissing`. bash: classify `fcause` the same way for a non-blank `own`.

### F4 — Medium: the README's first "way to be safe" for an old snapshot cannot restore it (false data loss)

- **Where:**
  - `README.md:450-455` says: restore an old snapshot with the live root's `RECONSTRUCT.ps1`, pointing it at the snapshot with `-BackupRootOverride` / `-ChangeRootOverride`.
  - With that call the authority folder is the override (`Reconstruct.ps1:1088`), and the real backup root is in neither the index nor the scan (`:1234`, `:1242`).
  - PowerShell has no "origin" parameter separate from the backup root. bash has `--from`.
- **Steps (run):** `pwsh <backup>\RECONSTRUCT.ps1 -TargetRoot T -BackupRootOverride <older snapshot> -ChangeRootOverride <changes>` on store B gives **exit 1, 11 of 13 rows content-missing**.
- **Permanent or self-healing:** not permanent. `-RefreshKits`, and bash `--from`, both work.
- **Why not contrived:** it is the documented recovery for exactly the old-kit case the brief asks about, and it reports data loss.
- **Fix:** in the README, say to copy `RECONSTRUCT.ps1`, `FileBackup.Common.psm1` and `System.IO.Hashing.dll` into the snapshot folder and run it there, or use `-RefreshKits`, or bash `--from`. Alternatively, add `-From` to `Reconstruct.ps1`.

### F5 — Low: case-only-different paths from a Linux store collapse silently on a Windows restore (exit 0, one file missing)

- **Where:** `Reconstruct.ps1:1086-1094`. `$main` comes from `New-RelativePathMap`, which is case-insensitive on Windows (`Common.psm1:1689`), so the second row overwrites the first. SR-055 does not flag case collisions (`Engine.psm1:113-136`).
- **bash:** on a case-insensitive filesystem (macOS APFS) bash writes both rows to one file. Each verifies as it is written, so the exit is 0.
- **Steps (read, not run):**
  1. The container backs up `/source/A.txt` and `/source/a.txt`.
  2. The store is restored on Windows.
  3. One row is never attempted, and the exit is 0.
- **Permanent or self-healing:** permanent for that restore host. The bytes are in the pool.
- **Why low:** these names are rare in a real library. The case is in scope as a store moved to another machine.
- **Fix:** when a key already exists in `$main` under a different spelling, record the row as unrestored with a distinct cause (for example `NameCollision`, content class), so the exit is non-zero and the name is logged.

### F6 — Low: bash deletes a file already in the target when an expand fails; PowerShell keeps it

- **Where:** `reconstruct.sh:349` (`rm -f -- "$dest"` on return code 20). `sevenzip_to_file` replaces `dest` only by its final `mv`, so on failure that `rm` can only remove a file that was there before.
- **Effect:** re-running a restore into the same target after an exit 4, as the README advises, can delete a row that the first run had restored and verified. The same happens when restoring into the source folder.
- **Permanent or self-healing:** self-healing; the store is untouched and a later re-run restores the file.
- **Fix:** drop the `rm` on return code 20.

## 5. What was not done, and why

- **No Pester and no Run-All** (brief). Nothing was written in the repository; `git status` is clean.
- **Power loss was reasoned, not injected.**
  - Experiment A simulates the NTFS outcome by zero-filling a manifest's tail.
  - Experiment D simulates a mid-copy kill by writing a truncated copy.
  - No real power cut or VHD crash test was run.
- **F5 was not run.** It needs a case-sensitive source plus a Windows restore.
- **Not run on these hosts:** bash on macOS or BSD, and the kit inside the container image.
- **Performance at 180,000 objects was not measured.** One observation, kept out of the findings because performance is out of scope here: when C21 or C32 is ambiguous (several sets' store folders under one parent, on a copied store), the latest objects are not in the name index. Then every row runs the content scan, which expands every `.7z` it meets. Correct, but a restore of that shape does not finish at scale. Indexing every candidate sibling would close it, and verification keeps that safe (the C32 argument).
- **Engine, prune and Verify behaviour was not reviewed beyond what the restorers consume.** Those slices are other reviewers'. Items spotted on the way are in §6.

## 6. Open questions for the caller

### Q1 — Ruling question: the accepted gap "a snapshot manifest losing rows", seen through the power-loss lens

**Run (`expA.ps1`):** a snapshot manifest whose tail reads as NUL (header and 3 rows intact) restores **4 of 13 files with exit 0** in `Reconstruct.ps1`. bash parses the same way: NULs are dropped by `read`, and a blank RelativePath is skipped at `reconstruct.sh:1273`.

**How it arises without a hand edit**
1. Step 3 (`Engine.psm1:4974-4985`) writes `Building_D\MANIFEST.csv` and renames the folder to `Snapshot_D` with no flush.
2. NTFS logs the rename and the file size, not the data. Data still in the cache at a crash reads back as zeros past the on-disk valid data length. Confidence: medium-high; this is the familiar "file full of NULs after a crash" symptom. exFAT and FAT32 have no journal. ext4 with delalloc more likely leaves zero length, which the header check refuses (2).
3. A crash or unplug in the seconds after step 3, during the run, leaves `Snapshot_D` torn.
4. The next run keeps an existing `Snapshot_D` as it is (`:4970-4972`), then overwrites the latest manifest, which was the only intact record of state D.
5. Result: state D is permanently a silent partial restore.

**Cheap guards**
- Restorer: refuse a manifest that contains a NUL byte or does not end in a newline. `Write-Manifest` ends every row with a newline (`Common.psm1:1278, 1387`), so this needs no witness.
- Engine: `Flush(true)` the Building manifest before the rename.

### Q2 — Ruling question: C18, and the kit-6 own-file rule, against C22/C28's premise

C22 and C28 keep duplicates because "a restore heals a damaged copy from another one in the pool". It does not do that for archive-shaped damage, which is the normal shape in a compressed store: 7-Zip's CRC check fails the extraction.
- The own file, or the first index hit, failing to expand ends the row as `CandidateError` (4), and no other copy is tried (`Reconstruct.ps1:1404-1410, 1627-1630`; `reconstruct.sh:349, 1500`).
- Only a damaged object with no signature, or an expand that completes with wrong bytes, reaches the heal.
- F2 is one concrete instance.

Should a failed expand, with 7-Zip passing its self-test (as the content scan already checks, `:470-481`), fall through to the next index candidate and then the content scan?

### Q3 — For the engine and prune reviewers (spotted, not traced)

- **(a) Residue taken as the object.** `Get-StoreObjectIndex` accepts `X.7z.fbprune.tmp` as the object for X (`Engine.psm1:4081-4094`). When it is listed before the original (backup root first, then newest snapshot), the engine would treat it as follows:
  - `Get-LatestObject` moves it back under its own name (`:4764`), so a latest row names a partial file.
  - The next prune's sweep then keeps that file, because the latest manifest references it (`:2509`).
  - That prune may then judge the intact original not to be the last copy.
- **(b) Prune and power loss.** `Copy-ReHomedDataFile` publishes by `Move-Item` (`:2592`), then the transaction deletes the source snapshot, with no flush of the copy. A crash in the seconds after a prune can leave the only remaining copy as NULs while the deletion is committed. That would be permanent.
- **(c) Torn kit kept forever.** The latest kit is rewritten on every run (`:6154`) and copied straight into `Building_D` (`:4979-4983`). The same crash window as Q1 leaves a torn kit in a snapshot that is kept as it is. It can be recovered with `-RefreshKits` or bash.
- **(d) Torn objects reused by name.** After a crash, an object at its final name can be zero-length (ext4) or NUL-filled (NTFS). Does any run compare the index's `FileLength` with the content length before reusing an object by name? If not, the content is never stored again while the source still has it. Restores do report it, with 1 or 4.

### Q4 — Clean-up

The test stores are at `%TEMP%\fbrr-A`, `%TEMP%\fbrr-A-A` and `%TEMP%\fbrr-B` (plus its `-C` and `-D` copies), and at `/tmp/plainstore` and `/tmp/rr*` in WSL Fedora. They are left in place so the findings can be re-checked; delete them when done.
