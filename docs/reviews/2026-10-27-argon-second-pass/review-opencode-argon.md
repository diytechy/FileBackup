# Independent Review Report — FileBackup @ `df830ee` (`BoundedRebuild`)

## 1. What was done

- **Read in full:**
  - `AGENTS.md` (sections 1–8), `README.md` (lines 1–1202), `docs/interfaces.md` (lines 1–136), `docs/status.md` (lines 1–120, "Current State" header).
  - `docs/plans/bounded-run-loop.md` (rulings R1–R14, calls C1–C44), `docs/plans/bounded-run-loop-reviews.md` (reviews 1–5), `docs/reviews/2026-10-26-data-loss/consolidated.md`, `docs/plans/single-store-layout.md`.
  - `Modules/FileBackup.Common.psm1` (lines 1–1853), `Modules/FileBackup.Engine.psm1` (lines 1–7439), `FileBackup.ps1` (lines 1–724), `Reconstruct.ps1` (lines 1–1809), `bash/reconstruct.sh` (lines 1–1682), `container/entrypoint.sh` (lines 1–60).
- **Ran:**
  - Read-only git inspection: `git log --oneline 7532b86..HEAD` (41 commits) and `git diff 7532b86..HEAD -- Modules FileBackup.ps1 Reconstruct.ps1 bash container`.
  - No Pester, no `tests/Run-All.ps1`, and no repository modifications.

## 2. Where the artifact is

This final message.

## 3. What was checked and found clean

- **Flush-before-rename durability (C36):**
  - `Write-Manifest` (`Common.psm1:1461–1478`) flushes the `StreamWriter` and calls `Sync-FileToDisk -Stream` on `MANIFEST.csv.tmp` before deleting any legacy `.meta` and calling `[System.IO.File]::Move(..., $true)`.
  - `Set-BackupStateField` (`Engine.psm1:330–332`) calls `Sync-FileToDisk` on `FileBackupState.json.tmp` before `Move-Item`.
  - `Write-KitFile` (`Engine.psm1:3288–3296`, shared by `New-ReconstructScript` and `Update-BackupSnapshotKit`) writes `<kit>.tmp`, calls `Sync-FileToDisk -Stream`, and renames only when bytes differ; all seven `.tmp` names are in `Test-IsInfrastructureFile` (`Engine.psm1:85–87`).
  - `Publish-PriorStateSnapshot` (`Engine.psm1:5587–5600`) writes `MANIFEST.csv` via `Write-Manifest` and calls `Sync-FileToDisk` on every copied sidecar/kit file in `Building_<D>` before `Directory::Move`.
  - `Copy-ReHomedDataFile` (`Engine.psm1:2900–2936`) calls `Sync-FileToDisk` on `<dest>.fbprune.tmp`, verifies length/hash (and expanded payload when compressed), and renames into place before `Publish-PruneManifest` and `Complete-PruneDeletion`.
  - `Publish-StagedObject` (`Engine.psm1:5127–5128`) calls `Sync-FileToDisk -LiteralPath $from` on every newly created object (raw or `.7z`) before `File::Move`.
- **Damaged-object quarantine and non-reuse (C37):**
  - `Get-StoreObjectIndex` (`Engine.psm1:4646–4653`) routes 0-byte objects (where `ContentLength > 0`) and wrong-length non-`.7z` objects lacking a 7-Zip signature (`Get-ListedObjectDamage`, `Engine.psm1:4554–4564`) to `$index.Damaged`, excluding them from `Objects` and `Duplicates`.
  - `Move-DamagedStoreObject` (`Engine.psm1:2174–2194`, called at `:6849`) moves them into `<ChangeRoot>/Verify/<folder>/` before capture and sets the backup outcome to at least `1` (`:6901`). If a move fails, `Publish-StagedObject` (`:5113–5117`) re-checks `Get-ListedObjectDamage` on an existing destination file and throws rather than adopting the damaged file.
- **Torn manifest NUL detection in both restorers (C38):**
  - `Get-ManifestNulDamage` (`Reconstruct.ps1:1130–1157`) and `manifest_intact_lines` (`bash/reconstruct.sh:461–468`) both count complete newline-terminated lines before the first NUL byte, restore only those rows, log `[ManifestDamaged]`, and force exit code `1` (or `4` when a host error also occurred). A NUL in the header line fails the header check with exit `2` before target creation.
- **Empty or vanishing source (C24, C27, C39):**
  - `Assert-SourceNotEmpty` (`Engine.psm1:6437–6475`, called at `:6838`) stops the set with `4` before `Publish-PriorStateSnapshot` when the source root lists no non-pseudo entries while `$priorRows.Count -gt 0`. `Invoke-LibraryCapture` (`:6633–6651`) stops with `4` before `Publish-LatestState` if the source root vanished or emptied mid-run, or if the walk found only empty directories while `$priorRows.Count -gt 0`.
- **Case-only path collisions (C42):**
  - `Get-CaseOnlyCollision` (`Engine.psm1:189–216`) flags all members of any `OrdinalIgnoreCase` collision group in both `Get-SourceFileList` (`:4901–4912`) and `Get-SourceDirectoryRecord` (`:634, :655`). In `Invoke-LibraryCapture` (`:6532–6536`), unportable paths are added to `$frozen`, preserving any prior row and returning exit `1`.
- **Prune residue and `.fbprune.tmp` handling (C41, A3):**
  - `Remove-CommittedPruneResidue` (`Engine.psm1:2728–2792`, called at `:3128`) runs under `Temp.lock` (and not under `-WhatIf`) before planning or capacity rails. `Complete-PruneDeletion` (`:3011–3021`) treats the rename to `Pruning_<name>` as the commit point and warns (returning `0`) if the subsequent delete fails.
  - `Get-StoreObjectIndex` (`:4631`), `New-StoredObjectNameIndex` (`Reconstruct.ps1:576`), and `build_name_index` (`bash/reconstruct.sh:944–945`) all skip `*.fbprune.tmp`.
- **Store path failure codes across all actions (C25, C26):**
  - `Resolve-BackupSetPaths` (`Engine.psm1:4257–4305`) checks `Assert-StoreVolumePresent` on missing backup/change paths in both normal and `-ReadOnly` modes, throwing `DriveNotFoundException`, which `Get-StorePathFailureCode` maps to exit `4` across `Backup`, `Prune`, `Snapshots`, `Verify`, and `View`.

## 4. Findings, most severe first

### Finding 1 — Medium: `Write-DirectorySidecar` overwrites `DIRECTORIES.csv` in place without temp-plus-rename or `Sync-FileToDisk`, so a kill or power loss leaves a truncated sidecar that is also copied into `Snapshot_<D>`

- **Where:** `Modules/FileBackup.Engine.psm1:709` (`$out | Export-Csv -LiteralPath $path -NoTypeInformation`), called from `Publish-LatestState` (`Engine.psm1:6716`), and then copied into `Building_<D>` on the next run by `Publish-PriorStateSnapshot` (`Engine.psm1:5589–5595`).
- **Concrete steps:**
  1. Back up a source tree containing empty directories and/or `Hidden`/`System` folders (e.g., 50 empty or attributed folders).
  2. On a subsequent backup run that changes at least one file, `Publish-LatestState` writes `MANIFEST.csv` atomically (`Engine.psm1:6713`), then calls `Write-DirectorySidecar` (`:6716`), which runs `Export-Csv -LiteralPath <BackupRoot>\DIRECTORIES.csv` directly in place (`:709`) with no `.tmp` file and no `Sync-FileToDisk`.
  3. The process is killed (or power is lost on NTFS/ext4) after `Export-Csv` truncates `DIRECTORIES.csv` and writes the header + first 5 rows, or before data blocks flush.
  4. On the next backup run, `Publish-PriorStateSnapshot` (`Engine.psm1:5589–5595`) copies that truncated (or NUL-tailed) `DIRECTORIES.csv` from `BackupRoot` into `Building_<D>` and renames it to `Snapshot_<D>`.
  5. Restoring `Snapshot_<D>` (with `Reconstruct.ps1:1647` or `bash/reconstruct.sh:521`) reads the valid CSV lines at the start of `DIRECTORIES.csv` (or stops at NUL/EOF without error), silently omitting the remaining empty directories and folder attributes forever in that snapshot, and exiting `0`.
- **Permanent or self-healing:** Self-healing for the latest state on the next completed run, **permanent** for `Snapshot_<D>` (snapshots are write-once, R6).
- **Why it is not contrived, accepted, or already adjudicated:**
  - Empty directories and the four directory attributes are explicitly IN contract (SR-065, README "What FileBackup records, and where" and "What is **not** recorded").
  - While `DIRECTORIES.csv` is unwitnessed and advisory so a corrupt file does not abort a restore, `Write-DirectorySidecar` is the only metadata writer in `Publish-LatestState` that still writes in place rather than via temp-file + `Sync-FileToDisk` + rename (unlike `Write-Manifest`, `Set-BackupStateField`, and `Write-KitFile`), and `Test-IsInfrastructureFile` (`Engine.psm1:81`) does not list `DIRECTORIES.csv.tmp`.
- **Smallest fix:** In `Write-DirectorySidecar` (`Engine.psm1:698–710`), write to `$path.tmp`, call `Sync-FileToDisk -LiteralPath "$path.tmp"`, and rename with `[System.IO.File]::Move("$path.tmp", $path, $true)`; add `"$($script:Def.DirectorySidecarName).tmp"` to `Test-IsInfrastructureFile` (`Engine.psm1:81`).

---

### Finding 2 — Medium: `-Action Verify` with `-RepairStorage` or `-RefreshKits` returns exit code `2` ("precondition/do not retry") instead of `4` ("retriable") when `Temp.lock` is held by a running backup or prune

- **Where:** `FileBackup.ps1:536, 556, 564, 598–601` (`Invoke-VerifyAction`), `Modules/FileBackup.Engine.psm1:3608–3672` (`Enter-StoreMutationLock`), and `Modules/FileBackup.Engine.psm1:4186–4211` (`Get-StorePathFailureCode`).
- **Concrete steps:**
  1. Start a scheduled or manual backup (or prune) on a store; it holds `<ChangePath>/Temp.lock`.
  2. While it is running, invoke `pwsh -File FileBackup.ps1 -ConfigPath config.json -Action Verify -RepairStorage -ExitCode` (or `docker run ... -e FILEBACKUP_REPAIR=1 filebackup:local verify`).
  3. `Move-StoreObjectToVerify` (`Engine.psm1:2007`) or `Repair-BackupStorageForm` (`:2320`) or `Update-BackupSnapshotKit` (`:2465`) calls `Enter-StoreMutationLock`, which throws a `RuntimeException` with message `[SR-075/lock-held] ...`.
  4. `Invoke-VerifyAction`'s `catch` block (`FileBackup.ps1:598–601`) passes the error to `Get-StorePathFailureCode`, which checks only `if ($ErrorRecord.Exception -is [System.IO.DriveNotFoundException]) { return 4 }` and otherwise returns **`2`**.
  5. By contrast, `docs/interfaces.md:108–110` (IF-001 exit-code table) maps code `2` to `error — do not retry` ("Usage or precondition error; nothing mutated") and code `4` to `warn — retry` when "another run holds the lock". (Note: `Remove-BackupSnapshot` at `Engine.psm1:3110–3118` also returns `Code = 2` (`staging-busy`) when `Enter-StagingOsLock` throws on a held lock.)
- **Permanent or self-healing:** Transient (nothing is mutated), but causes HomeHub / NagLight to classify a normal lock contention during maintenance as a non-retriable configuration/precondition error (`2`) rather than a retriable busy state (`4`).
- **Why it is not contrived, accepted, or already adjudicated:**
  - Consolidated item A5 added the OS lock to `Move-StoreObjectToVerify` (`ce068bc`), and commit `df830ee` wired `Get-StorePathFailureCode` into `Invoke-VerifyAction`. The mismatch between IF-001 (`docs/interfaces.md:110`, lock held → 4) and `Invoke-VerifyAction` / `Remove-BackupSnapshot` returning `2` on `[SR-075/lock-held]` was not adjudicated in `consolidated.md`.
- **Smallest fix:** If IF-001's "another run holds the lock → 4" applies to all store-mutating actions (`Prune` and `Verify -RepairStorage`/`-RefreshKits`), map `[SR-075/lock-held]` (or a typed lock exception) to `4` in `Get-StorePathFailureCode` and `Remove-BackupSnapshot:3115`; if `2` is intended for non-backup actions (as `README.md:1167` parenthetically notes for Verify), update `docs/interfaces.md:108–110` so the IF-001 contract and HomeHub's wrapper agree.

---

### Finding 3 — Low: `Invoke-PruneEntrySweep` uses `Get-ChildItem -Filter '*.fbprune.tmp'`, which misses a damaged `*.fbprune.tmp` leftover when `Remove-BackupSnapshot` later checks `UnreferencedData` on a subsequent run if the sweep did not run

- **Where:** `Modules/FileBackup.Engine.psm1:1029–1033` (`Get-SnapshotPrunePlan`), `Modules/FileBackup.Engine.psm1:1607–1616` (`Get-StorageFormFinding`).
- **Concrete steps:**
  1. Start `-Action Prune` on `Snapshot_D1`, which re-homes a last-copy object into `BackupRoot` (or a surviving `Snapshot_D2`).
  2. Kill the prune process while `Copy-ReHomedDataFile` (`Engine.psm1:2900`) is writing `<destFolder>/<object>.fbprune.tmp`. Both `<ChangeRoot>/Temp` and `<destFolder>/<object>.fbprune.tmp` remain on disk.
  3. Run `-Action Verify` (as `README.md:1159` instructs when recovering from a stale `Temp` folder after moving `Temp` aside).
  4. `Get-StorageFormFinding` (`Engine.psm1:1607–1616`) enumerates `Get-DataFile -Root $Folder` and reports `<object>.fbprune.tmp` as `Class = 'Unreferenced'` (exit `1`), even though `Get-SnapshotPrunePlan` (`:1031`), `Get-StoreObjectIndex` (`:4631`), and both restorers explicitly ignore `*.fbprune.tmp` as prune staging residue.
- **Permanent or self-healing:** Self-healing once the next real `-Action Prune` runs `Invoke-PruneEntrySweep`, but causes `-Action Verify` during the documented `Temp` recovery steps (`README.md:1159`) to report false `Unreferenced` findings and exit `1`.
- **Why it is not contrived, accepted, or already adjudicated:**
  - Consolidated item A3 (`9f259cf`, `14c548e`) excluded `*.fbprune.tmp` from the engine's `Get-StoreObjectIndex` and both restorers' name indexes, and `Get-SnapshotPrunePlan` (`:1031`) already had `$rel -notlike '*.fbprune.tmp'`, but `Get-StorageFormFinding` (`:1609`) was not given the same exclusion.
- **Smallest fix:** In `Get-StorageFormFinding` (`Engine.psm1:1609`), skip unreferenced files ending in `.fbprune.tmp` (or log them distinctly as prune staging residue) when they are not in `$referenced`, matching `Get-SnapshotPrunePlan` (`:1031`).

## 5. What was not done, and why

- Did not run Pester (`Invoke-Pester`) or the integration suite (`tests/Run-All.ps1`), per the brief's limits.
- Did not review items explicitly marked out of scope or open in `docs/status.md` (C43's second half for prune/pool-resolve memory, C44's single-store layout and L7 `/` path normalization, `FileBackupState.json.tmp` not in `Test-IsInfrastructureFile`, and the Verify two-pass `.7z` wrong-length item).

## 6. Open questions for the caller

1. **Lock-held exit code for `Prune` and `Verify -RepairStorage`/`-RefreshKits` (Finding 2):** `docs/interfaces.md:110` puts "another run holds the lock" under code `4` ("warn — retry"), whereas `Remove-BackupSnapshot` (`Engine.psm1:3115`) and `Invoke-VerifyAction` (`FileBackup.ps1:600`, noted in `README.md:1167`) return `2` ("error — do not retry"). Should non-backup store mutators return `4` when `Temp.lock` is held, or should `IF-001` specify `2` for them?
