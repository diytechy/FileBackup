# Independent Review: Hidden Data-Loss Defects (`FileBackup` @ `7532b86`)

## 1. What was done

- **Read line by line:**
  - `AGENTS.md` (sections 1–8), `docs/plans/bounded-run-loop.md` (R1–R14, C1–C35), `docs/plans/bounded-run-loop-reviews.md` (reviews 1–5), `README.md` (all 1,174 lines).
  - `Modules/FileBackup.Common.psm1` (all 1,780 lines).
  - `Modules/FileBackup.Engine.psm1` (all 6,738 lines).
  - `Reconstruct.ps1` (all 1,693 lines).
  - `bash/reconstruct.sh` (all 1,580 lines) and `bash/reconstruct.command` (all 56 lines).
  - `FileBackup.ps1` (all 696 lines) and `container/entrypoint.sh` (all 60 lines).
- **Ran:** Nothing. All findings below were verified line by line against the source at `7532b86`.

---

## 2. Where the artifact is

- **Report path requested:** `.opencode/plans/fb-review.md`
- **Status:** Not written to disk because this session is running under an active read-only Plan Mode constraint that forbids any file creation or modification. The complete six-section report is printed below verbatim.

---

## 3. What was checked and found clean

- **Pipeline ordering & process-kill safety (`Invoke-BackupSet`):**
  - `Publish-PriorStateSnapshot` runs before `Invoke-LibraryCapture` and before any progress checkpoint (`Modules/FileBackup.Engine.psm1:6158-6166`), so checkpoints never overwrite the prior state's only record.
  - Working rows start as a copy of `$PriorRows` (`Engine.psm1:5871-5872`), so a checkpoint mid-run preserves prior rows for files not yet visited.
  - `Remove-UnchangedSnapshot` renames `Snapshot_<D>` back to `Building_<D>` before deleting (`Engine.psm1:5028-5034`), preventing half-deleted snapshots.
  - `Move-SupersededObject` tests against `$FinalRows` (`Engine.psm1:5097-5102`), preserving objects claimed by frozen rows for unreadable/unportable/locked files, and routes leftover objects from an earlier interrupted run to the newest snapshot whose own manifest names them (`Engine.psm1:5117-5141`).
- **Hash-while-copy (`Copy-FileWithHash`, `Invoke-SourceFileCapture`, `Publish-StagedObject`):**
  - Every new or changed file is hashed as it is written to the staged file (`Engine.psm1:4374-4384`), and size + `LastWriteTime` are re-checked after reading (`Engine.psm1:4643-4651`, `4678-4683`).
  - Compression reads the staged copy (`Engine.psm1:4499`), never the live source file. Equal-length `.7z` archives fall back to raw storage (`Engine.psm1:4505-4516`, C30).
- **Name grammar & decoders (`ConvertFrom-HashSizeFileName`, `ConvertFrom-StoredObjectName`, `decode_hash_size_names`):**
  - All three decoders enforce the 22-character base-57 hash width, `_` separator, unpadded base-57 length (`<= Int64.MaxValue`), and extension starting with `.` (or empty) without path separators (`Common.psm1:658-697`, `Engine.psm1:3996-4011`, `bash/reconstruct.sh:843-859`).
- **Verify verdict & duplicate confirmation (`Get-StoredObjectVerdict`, `Move-StoreObjectToVerify`):**
  - Expand failures in `Get-StoredObjectVerdict` and `Get-StorageFormFinding` yield `Unverified` / `$null` rather than `Damaged` / `PayloadMismatch` (`Engine.psm1:1444-1450`, `1667-1680`, C22/C33).
  - `Move-StoreObjectToVerify` confirms the kept copy once before moving any duplicate (`Engine.psm1:1852-1872`, C28).
- **OS lock (`Enter-StagingOsLock`, `Exit-StagingOsLock`):**
  - `<ChangePath>/Temp.lock` is opened `FileShare.None` (`Engine.psm1:3100-3103`) and never unlinked (`Engine.psm1:3138-3143`), preserving inode identity for Linux `flock`.

---

## 4. Findings, most severe first

### Finding 1 — High: Power loss or OS crash after rename / write without `fsync` can leave 0-byte or torn `MANIFEST.csv`, `FileBackupState.json`, or stored objects, and permanently lose superseded snapshot history or data

- **Where:**
  - `Modules/FileBackup.Common.psm1:1365-1406` (`Write-Manifest`: `StreamWriter` close + `[System.IO.File]::Move($fullTemp, $fullDest, $true)` with no `Flush(true)` on the file or parent directory)
  - `Modules/FileBackup.Engine.psm1:233-235` (`Set-BackupStateField`: `Set-Content` + `Move-Item -Force` on `FileBackupState.json.tmp` with no flush)
  - `Modules/FileBackup.Engine.psm1:4371-4387`, `4499`, `4523` (`Copy-FileWithHash` and `Publish-StagedObject`: staged data file written and renamed into `BackupRoot` with no `Flush(true)`)
  - `Modules/FileBackup.Engine.psm1:4976-4985` (`Publish-PriorStateSnapshot`: writes `Building_<D>/MANIFEST.csv` and renames directory to `Snapshot_<D>` without flushing)
  - `Modules/FileBackup.Engine.psm1:5713-5719` (`Read-PriorStateForRun`: a 0-byte `MANIFEST.csv` bypasses the header check and returns `@()`)
- **Filesystem behaviour relied on (high confidence):**
  - Neither `StreamWriter.Dispose()`, `FileStream.Dispose()`, `Set-Content`, nor `7z` calls `FlushFileBuffers` (Windows) or `fsync` (Linux). Data sits in the OS page cache while directory/rename metadata can be committed ahead of data (on NTFS, exFAT/FAT32 on USB drives, and ext4 when `auto_da_alloc` does not cover directory renames or non-overwrite creations).
  - Specifically:
    1. **`Publish-PriorStateSnapshot` (`Engine.psm1:4976-4985`)**: `Write-Manifest` creates `Building_<D>\MANIFEST.csv.tmp` and renames it to `Building_<D>\MANIFEST.csv` (a *new* destination file, not an overwrite, so ext4's `auto_da_alloc` overwrite heuristic does not trigger), then renames the directory `Building_<D>` to `Snapshot_<D>`. On power loss seconds later, `Snapshot_<D>\MANIFEST.csv` can be 0 bytes on disk while `Snapshot_<D>` exists.
    2. **Latest `MANIFEST.csv` (`Common.psm1:1365-1406` and `Engine.psm1:5713-5719`)**: If power loss or USB unplug leaves `BackupRoot\MANIFEST.csv` at 0 bytes (or on exFAT/FAT32, where metadata is unjournaled), look at `Read-PriorStateForRun` (`Engine.psm1:5713`):
       ```powershell
       if ((Test-Path -LiteralPath $manifestPath -PathType Leaf) -and (Get-Item -LiteralPath $manifestPath).Length -gt 0) {
       ```
       Because `Length -gt 0` is false for a 0-byte file, `Read-PriorStateForRun` **does not refuse** a 0-byte `MANIFEST.csv` — it treats it as an empty backup (`$priorRows = @()`).
    3. **Staged object write (`Engine.psm1:4371-4387`, `4523`)**: `Copy-FileWithHash` writes the temp file in `Incoming/`, disposes the `FileStream` (which only flushes .NET's user-space buffer to the OS kernel, not to disk), and `Publish-StagedObject` renames it to `<hash22>_<len><ext>`. On power loss, the file at `<hash22>_<len><ext>` can have 0 bytes or uninitialized blocks on disk while its filename claims `<hash22>_<len>`.
- **Concrete steps:**
  1. Run 1 backs up a library and completes at `D1`.
  2. In Run 2, files have been modified or deleted in the source. Step 3 (`Publish-PriorStateSnapshot`) writes `Building_<D1>\MANIFEST.csv` and renames `Building_<D1>` to `Snapshot_<D1>`.
  3. Or, at Step 6 (`Publish-LatestState`), `Write-Manifest` writes `BackupRoot\MANIFEST.csv`.
  4. Power is lost (or the host crashes) before the OS write cache flushes the file data blocks, leaving `Snapshot_<D1>\MANIFEST.csv` (or `BackupRoot\MANIFEST.csv`) at 0 bytes while the directory rename has committed.
  5. On reboot, the next scheduled run starts:
     - If `Snapshot_<D1>\MANIFEST.csv` is 0 bytes: `Publish-PriorStateSnapshot` sees `Snapshot_<D1>` already exists (`Engine.psm1:4970`) and keeps it as-is (`BuiltNow = $false`). The run finishes and moves superseded objects into `Snapshot_<D1>`. `Snapshot_<D1>` now has a 0-byte manifest: every row of state `D1` is permanently lost, and `Remove-BackupSnapshot` refuses `Snapshot_<D1>` with `unreferenced-data`.
     - If `BackupRoot\MANIFEST.csv` is 0 bytes and `FileBackupState.json` was also lost/0-byte (or if `Snapshot_<D1>` already existed): `Read-PriorStateForRun` (`Engine.psm1:5713`) accepts the 0-byte manifest as `@()` instead of refusing with exit 2. Any file deleted from the source since `D1` is never snapshotted and its object is stranded unreferenced.
     - If a newly stored object `<hash22>_<len><ext>` in `BackupRoot` was left 0-byte on disk after power loss: on the next run, `Get-StoreObjectIndex` (`Engine.psm1:4080-4095`) indexes it by **filename alone** (`ConvertFrom-StoredObjectName`) without checking that `$file.Length -eq $parsed.Length` for raw objects! `Get-LatestObject` (`Engine.psm1:4755`) then returns that 0-byte object as a valid hit, so the next run marks the file `Kept` (`Engine.psm1:4607-4612`) and **never re-captures it from the source**!
- **Permanent or self-healing:** **Permanent.**
  - A 0-byte `Snapshot_<D1>\MANIFEST.csv` permanently loses the `D1` point-in-time index (R6: snapshots are write-once).
  - A 0-byte raw object `<hash22>_<len><ext>` in `BackupRoot` is **never healed by later backup runs** because `Get-StoreObjectIndex` (`Engine.psm1:4080-4095`) trusts the filename's encoded length (`$parsed.Length`) and never checks `$file.Length -eq $parsed.Length` (even for non-`.7z` files). If the source file is later deleted or lost, the backup has 0 bytes for it forever.
- **Why it is not contrived or accepted:** Power loss / OS crash during or immediately after a backup run is explicitly in scope in the brief. While `AGENTS.md` §4 notes `Write-Manifest` is not fsynced ("the next run sees the mismatch with the files and repairs"), the three failure modes above **do not repair on the next run**: (a) a 0-byte `Snapshot_<D>\MANIFEST.csv` is never repaired; (b) a 0-byte `BackupRoot\MANIFEST.csv` bypasses `Read-PriorStateForRun`'s header check (`Length -gt 0`); and (c) a 0-byte raw stored object `<hash22>_<len><ext>` is trusted by `Get-StoreObjectIndex` so the next run does not repair it either.
- **Suggested fix:**
  1. In `Write-Manifest` (`Common.psm1:1365-1393`), flush the underlying `FileStream` to disk (`$writer.Flush(); $writer.BaseStream.Flush($true)`) before closing and renaming.
  2. In `Copy-FileWithHash` (`Engine.psm1:4385`) and `Set-BackupStateField` (`Engine.psm1:234`), call `$out.Flush($true)` before disposing/renaming.
  3. In `Get-StoreObjectIndex` (`Engine.psm1:4083`), skip or refuse to index any non-`.7z` file whose `$file.Length -ne $parsed.Length` (and any `.7z` file whose `$file.Length -lt 6`), so a 0-byte crash remnant is never treated as a valid stored object by the next run.
  4. In `Read-PriorStateForRun` (`Engine.psm1:5713`), remove `-and (Get-Item -LiteralPath $manifestPath).Length -gt 0` when `Snapshot_*` folders or `FileBackupState.json` exist (current `Write-Manifest` always writes the header line even for 0 rows, `Common.psm1:1326`), so a 0-byte truncated manifest is refused (exit 2) rather than silently treated as 0 rows.

---

### Finding 2 — High: `Invoke-LibraryCapture` unreadable-directory prefix check is case-insensitive and matches `StartsWith` without normalizing separators, silently dropping frozen rows on Linux or mixed-separator manifests

- **Where:** `Modules/FileBackup.Engine.psm1:5858-5862` and `5971-5974`.
- **Code path:**
  ```powershell
  # Engine.psm1:5858-5862
  if ("$($bad.Path)".StartsWith($Paths.SrcPath, [System.StringComparison]::OrdinalIgnoreCase)) {
      $prefix = "$($bad.Path)".Substring($Paths.SrcPath.Length).TrimStart('\', '/')
      # The source root itself: every row is beneath it.
      if ($prefix) { $unreadablePrefixes.Add($prefix + [System.IO.Path]::DirectorySeparatorChar) } else { $unreadablePrefixes.Add('') }
  }
  ```
  And when freezing prior rows at `Engine.psm1:5971-5974`:
  ```powershell
  foreach ($prefix in $unreadablePrefixes) {
      if ($rel.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { $isFrozen = $true; break }
  }
  ```
- **Concrete steps (two variants):**
  - **Variant A (Unlistable directory error with `$bad.Path` empty or not starting with `$Paths.SrcPath`):**
    1. Back up a source tree on a network share or volume (`\\server\share\data` or a mount).
    2. During a subsequent run's `Get-SourceFileList` (`Engine.psm1:4316-4322`), an enumeration error occurs where PowerShell's `Get-ChildItem` emits an `ErrorRecord` whose `TargetObject` is `$null` (e.g., a Mid-walk Win32/SMB directory handle error) or a non-canonical path.
    3. `$bad.Path` is `""`. `$notCaptured` is incremented (`Engine.psm1:5857`), so the run logs a warning, **but `"".StartsWith($Paths.SrcPath)` is `$false`**, so nothing is added to `$unreadablePrefixes`.
    4. Every prior row beneath that unreadable directory is not in `$visited` and not in `$unreadablePrefixes`, so it is **dropped from `$finalRows` as if deleted**, and Step 8 moves its objects out of the latest state.
  - **Variant B (Linux case-sensitive sibling directories):**
    1. In the Linux container (`/source`), have two directories `Docs/` (unreadable, `chmod 000`) and `docs/` (readable, files deleted).
    2. Because `Engine.psm1:5972` uses `OrdinalIgnoreCase` even on Linux (violating SR-034 / `New-RelativePathMap`), `docs/file.txt` matches `Docs/` and is frozen even though `docs/file.txt` was legitimately deleted.
- **Permanent or self-healing:** Self-healing once the directory becomes readable again (the prior state was snapshotted in Step 3), **except** that until then the latest state silently omits all files under the unreadable directory in Variant A, violating SR-057 ("existing rows there are frozen, not evicted").
- **Why it is not contrived or accepted:** SR-057 explicitly promises that unreadable directories during enumeration freeze existing rows beneath them.
- **Suggested fix:**
  - In `Engine.psm1:5858-5862`, if `$bad.Path` is empty or does not start with `$Paths.SrcPath`, freeze all prior rows (`$unreadablePrefixes.Add('')`) rather than freezing nothing.
  - Use platform-appropriate string comparison (`if ($IsWindows) { OrdinalIgnoreCase } else { Ordinal }`) and normalize `/` and `\` when matching `$rel` against `$prefix`.

---

### Finding 3 — Medium: `Publish-PriorStateSnapshot` copies only 7 current kit filenames and omits `RECONSTRUCT.bat`, but `New-ReconstructScript` failure or partial kit leaves snapshot without a valid kit while `Publish-LatestState` does not refresh the kit

- **Where:** `Modules/FileBackup.Engine.psm1:4979-4983` and `6154-6160`.
- **Code path:**
  - In `Invoke-BackupSet` (`Engine.psm1:6154-6160`), `New-ReconstructScript` writes the kit into `$paths.BkpPath` *before* `Publish-PriorStateSnapshot` copies the kit from `$paths.BkpPath` into `Building_<D>`.
  - However, in `Publish-PriorStateSnapshot` (`Engine.psm1:4979-4983`):
    ```powershell
    foreach ($artifact in @($script:Def.ReconstructPs1Name, $script:Def.ReconstructCmdName, $script:Def.ReconstructCommandName,
                            $script:Def.ReconstructShName, $script:Def.CommonModuleName, 'System.IO.Hashing.dll', 'RECONSTRUCT.paths.json')) {
        $src = Join-Path $BackupRoot $artifact
        if (Test-Path -LiteralPath $src -PathType Leaf) { Copy-Item -LiteralPath $src -Destination $building -Force }
    }
    ```
  - Look at `RECONSTRUCT.paths.json` (`Engine.psm1:2936-2937` and `4980`): `New-ReconstructScript` writes:
    ```powershell
    @{ BackupRoot = $BackupRoot; ChangeRoot = $ChangeRoot } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $BackupRoot 'RECONSTRUCT.paths.json') -Encoding UTF8
    ```
    And `Publish-PriorStateSnapshot` copies that `RECONSTRUCT.paths.json` into `Snapshot_<D>`.
  - Now trace what happens when `Reconstruct.ps1` is run from `Snapshot_<D>` when `BackupRoot` and `ChangeRoot` are **sibling folders** (the standard R8 one-mount layout: `<store>/backup` and `<store>/changes`, or `E:\Backups\DataStore` and `E:\Backups\DataChanges`):
    - In `Reconstruct.ps1:627-636`:
      ```powershell
      $hereIsInsideRecorded = foreach ($root in @($paths.BackupRoot, $paths.ChangeRoot)) {
          if ($root -and (Test-Path -LiteralPath $root -PathType Container)) {
              $r = [System.IO.Path]::GetFullPath($root).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
              $h = [System.IO.Path]::GetFullPath($here).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
              if ($h.StartsWith($r, [System.StringComparison]::OrdinalIgnoreCase)) { $true; break }
          }
      }
      ```
    - That works on the same host. Now suppose the user copies `<store>` to another folder on the **same machine** (e.g. `E:\Backups_Copy\DataStore` and `E:\Backups_Copy\DataChanges`), and runs `Reconstruct.ps1` from `E:\Backups_Copy\DataChanges\Snapshot_<D>` while the original `E:\Backups\DataStore` and `E:\Backups\DataChanges` still exist.
    - `$hereIsInsideRecorded` is `$false` (good!).
    - Now look at `Reconstruct.ps1:645-657`:
      ```powershell
      if ($isChangeFolder) {
          $changeRoot = [System.IO.Path]::GetDirectoryName($here)
          $backupRoot = [System.IO.Path]::GetDirectoryName($changeRoot)
          if ($backupRoot -and -not (Test-Path -LiteralPath (Join-Path $backupRoot $DatabaseFilename) -PathType Leaf)) {
              $siblings = @(Get-ChildItem -LiteralPath $backupRoot -Directory -Force -ErrorAction SilentlyContinue |
                            Where-Object { $_.FullName -ne $changeRoot -and (Test-Path -LiteralPath (Join-Path $_.FullName $DatabaseFilename) -PathType Leaf) })
              if ($siblings.Count -eq 1) { $backupRoot = $siblings[0].FullName }
          }
      }
      ```
    - What if the parent directory of `$changeRoot` (`E:\Backups_Copy` or `E:\Backups`) holds **more than one backup set's store** (as README line 804 notes: "Give each backup set its own store folder", or a user with two sets `E:\Backups\Set1_Backup`, `E:\Backups\Set1_Changes`, `E:\Backups\Set2_Backup`, `E:\Backups\Set2_Changes` — the exact layout in README line 552–553 where `BackupPath = 'E:\Backups\DataStore'` and `ChangePath = 'E:\Backups\DataChanges'` sit directly under `E:\Backups\`)?!
- **Concrete steps:**
  1. Configure two backup sets in `E:\Backups\` following the README Quick Start pattern (`README.md:552-553`):
     - Set 1: `BackupPath = 'E:\Backups\MainStore'`, `ChangePath = 'E:\Backups\MainChanges'`
     - Set 2: `BackupPath = 'E:\Backups\PhotosStore'`, `ChangePath = 'E:\Backups\PhotosChanges'`
  2. Run backups on both sets so `MainChanges\Snapshot_<D>` exists and some of its rows reference unchanged objects in `MainStore`.
  3. Copy `E:\Backups` to another drive `F:\Backups` (or restore on Linux via `bash/reconstruct.sh`, which ignores Windows paths in `RECONSTRUCT.paths.json` at `bash/reconstruct.sh:1192-1215`).
  4. Run `RECONSTRUCT.ps1` (on `F:\Backups\MainChanges\Snapshot_<D>`) or `reconstruct.sh` (on Linux from `.../Backups/MainChanges/Snapshot_<D>`) without `-BackupRootOverride` / `--backup-root`.
  5. In `Reconstruct.ps1:654-656` (and `bash/reconstruct.sh:1157-1164`), `$backupRoot` starts as `F:\Backups` (the parent of `MainChanges`). It has no `MANIFEST.csv`. It then counts sibling directories under `F:\Backups` that contain a `MANIFEST.csv`: it finds **two** (`MainStore` and `PhotosStore`), so `$siblings.Count -eq 1` is **false**!
  6. `$backupRoot` remains `F:\Backups` (the parent directory containing **both** stores!).
  7. Look at what happens next:
     - `New-StoredObjectNameIndex` (`Reconstruct.ps1:561` / `bash/reconstruct.sh:876`) lists **top-level files only** in `$backupRoot` (`F:\Backups`). There are none! So the name index misses **every** object in `MainStore`!
     - Every row whose object is in `MainStore` falls back to `Find-DataFileByHash` (`Reconstruct.ps1:399` / `bash/reconstruct.sh:745`), which scans `$backupRoot` (`F:\Backups`) **recursively** (`-Recurse` / `find`) — hashing every object across `MainStore`, `PhotosStore`, `MainChanges`, and `PhotosChanges` **once per row** (the exact `rows × pool` catastrophe of Plan §7!).
     - Even worse: in `Reconstruct.ps1:1030` (`if (Test-PathIsInside -Child $TargetRoot -Parent $backupRoot)`), any `-TargetRoot` anywhere under `F:\Backups\...` is refused, and in `Find-DataFileByHash` (`Reconstruct.ps1:400-403`), the root-level infrastructure skip (`[System.IO.Path]::GetDirectoryName($_.FullName) -eq $folderNorm`) is checked against `F:\Backups` instead of `F:\Backups\MainStore`, so `MainStore\MANIFEST.csv`, `MainStore\System.IO.Hashing.dll`, etc. are **not** skipped as infrastructure during the recursive hash scan!
- **Permanent or self-healing:** Permanent for that store layout whenever restored on Linux or from a copied/moved disk without explicit `--backup-root` / `-BackupRootOverride`.
- **Why it is not contrived or accepted:** The README's own Windows config example (`README.md:552-553`) places `DataStore` and `DataChanges` as siblings under `E:\Backups\`, and explicitly supports multiple `BackupSets` (`README.md:754`).
- **Suggested fix:**
  - In `New-ReconstructScript` (`Engine.psm1:2936`), in addition to `BackupRoot` and `ChangeRoot`, write relative paths (`BackupRootRelative = [IO.Path]::GetRelativePath($BackupRoot, $BackupRoot)`, or write each folder's own sidecar with `BackupRootRelativeToChangeRoot`), **or** when `Publish-PriorStateSnapshot` / `Update-BackupSnapshotKit` writes into a snapshot, record the relative path from `ChangeRoot` to `BackupRoot` in `RECONSTRUCT.paths.json`.A relative sibling path (e.g. `../MainStore`) remains valid when the store is copied/moved or mounted in Linux, eliminating guessing among siblings.

---

### Finding 4 — Medium: `Repair-BackupStorageForm` (`-Action Verify -RepairStorage`) renames an object in a folder without updating rows in *other* folders (latest or newer snapshots) that also name that object's old `DataPath`, and can create a filename whose extension disagrees with `Get-StoredObjectIndex`

- **Where:** `Modules/FileBackup.Engine.psm1:2059-2095` (`Repair-BackupStorageForm`).
- **Code path:**
  1. `Repair-BackupStorageForm` iterates per folder (`foreach ($group in ($findings | Group-Object Folder))`, `Engine.psm1:2024`).
  2. When a stored object in `$folder` has a `NameLies` finding (e.g., raw bytes named `<hash22>_<len>.txt.7z` or archive bytes named `<hash22>_<len>.txt`), lines `2062-2063` compute `$newDataPath`:
     ```powershell
     if ($observed -eq 'Archive' -and -not $nameIsArchive) { $newDataPath = "$dataPath.7z" }
     if ($observed -eq 'Raw'     -and $nameIsArchive)      { $newDataPath = $dataPath.Substring(0, $dataPath.Length - 3) }
     ```
  3. Line `2076` renames the physical file in `$folder`, and lines `2080-2094` update `$row.DataPath = $newDataPath` **only in `$folder`'s own manifest**.
  4. Consider two consequences on a store produced by the bounded run loop:
     - **Consequence A (Raw bytes under `<hash22>_<len>.7z` when source had `.txt`):** Stripping `.7z` (`$dataPath.Substring(0, $dataPath.Length - 3)`) produces `<hash22>_<len>` with **no extension**, even if the row's `RelativePath` was `doc.txt`. That is valid under SR-070, **but** if the source file itself was named `archive.7z` and had raw bytes that did not match its hash (damaged raw bytes), stripping `.7z` changes the extension.
     - **Consequence B (Cross-folder `DataPath` references under C10):** Under C10, `Snapshot_<D>` keeps the `DataPath`s from when it was published (pointing to objects in `BackupRoot`). If `Repair-BackupStorageForm` renames an object in `BackupRoot` from `X` to `X.7z`, `Snapshot_<D>`'s manifest still has `DataPath = X`.
       - For a snapshot with kit revision >= 4, `Test-PoolResolves` (`Engine.psm1:1114-1144`) checks `$index.Map[$contentKey]`, which finds `X.7z` in `BackupRoot` and passes.
       - **However**, if `Snapshot_<D>` has a kit revision < 4 (a store continued from an older engine, explicitly in scope), `Test-PoolResolves` (`Engine.psm1:1143`) does **not** allow stale `DataPath`s for kit < 4 (`if ($kitRevisionOf[$f.Folder] -ge 4) { continue }`)! So repairing `BackupRoot` breaks `Test-PoolResolves` for the older snapshot and **wedges all future prunes** (`broken-pool`, exit 2), and breaks restoring that snapshot with its own kit!
- **Concrete steps:**
  1. Have a store continued from an older engine (kit < 4 in `Snapshot_1`) or a snapshot without `RECONSTRUCT.ps1` (kit revision 0).
  2. `Snapshot_1` has a row with `DataPath = <hash22>_<len>.txt` whose physical object is in `BackupRoot` and has a `NameLies` finding.
  3. Run `-Action Verify -RepairStorage`.
  4. `Repair-BackupStorageForm` renames the object in `BackupRoot` to `<hash22>_<len>.txt.7z` and updates `BackupRoot\MANIFEST.csv`, leaving `Snapshot_1\MANIFEST.csv` pointing at `<hash22>_<len>.txt`.
  5. Run `-Action Prune`: `Test-PoolResolves` reports `broken-pool` on `Snapshot_1` (because kit revision < 4 cannot resolve a missing `DataPath` via the pool) and refuses every prune in the store.
- **Permanent or self-healing:** **Permanent wedge** of `-Action Prune` (unless `-RefreshKits` is run).
- **Why it is not contrived or accepted:** Continuing a store with older snapshots/kits is in scope, and C19 explicitly protects folders with kit < 4 during backup and duplicate removal, but `Repair-BackupStorageForm` lacks the C19 check.
- **Suggested fix:** In `Repair-BackupStorageForm` (`Engine.psm1:2065`), do not rename a file (or also update/refuse) if a snapshot with kit revision < 4 references it, or check `Get-BackupKitRevision` as C19 does in `Get-StoreObjectFinding` (`Engine.psm1:1779-1783`).

---

### Finding 5 — Medium: `Remove-BackupSnapshot` (`-Action Prune`) checks `Temp` folder *after* `Assert-PrunePrecondition` creates a TOCTOU with legacy backups, and `Complete-PruneDeletion` failure after `Rename-Item` reports exit 4 ("before the commit point") when the commit point already passed

- **Where:** `Modules/FileBackup.Engine.psm1:2657-2659` and `2838-2850`.
- **Code path:**
  ```powershell
  # Engine.psm1:2657-2659
  Rename-Item -LiteralPath $SnapshotFolder -NewName $pruningName
  & $Log "Commit point passed: '$([System.IO.Path]::GetFileName($SnapshotFolder))' is no longer visible to any restorer." 'INFO'
  Remove-Item -LiteralPath (Join-Path $parent $pruningName) -Recurse -Force
  ```
  And in `Remove-BackupSnapshot` (`Engine.psm1:2838-2850`):
  ```powershell
  Complete-PruneDeletion -SnapshotFolder $plan.Folder -Log $log
  ...
  } catch {
      & $log "Removal of '$snapshotName' failed before the commit point; NO DATA WAS LOST: $($_.Exception.Message)" 'ERROR'
      [pscustomobject]@{ Name = $snapshotName; Status = 'Refused'; Code = 4
          ...
          Message = "Removal aborted before the commit point; no data was lost. $($_.Exception.Message)" }
  }
  ```
- **Concrete steps:**
  1. Run `FileBackup.ps1 -Action Prune -Snapshot Snapshot_2026_01_01_00_00_00`.
  2. All re-homing and manifest writes succeed. `Complete-PruneDeletion` renames `Snapshot_2026_01_01_00_00_00` to `Pruning_Snapshot_2026_01_01_00_00_00` (`Engine.psm1:2657`). **The commit point has passed.**
  3. During `Remove-Item -LiteralPath .../Pruning_Snapshot_... -Recurse -Force` (`Engine.psm1:2659`), an antivirus scanner or indexer briefly holds a handle on one file inside `Pruning_Snapshot_...`. Under `$ErrorActionPreference = 'Stop'`, `Remove-Item` throws.
  4. The `catch` block at `Engine.psm1:2844` catches the exception, logs `"Removal of 'Snapshot_...' failed before the commit point"`, emits `Status = 'Refused'; Code = 4`, and `FileBackup.ps1` exits **4**.
  5. Moreover, if the operator (or HomeHub wrapper) does **not** re-run prune for that same snapshot name (for example, because `FileBackup.ps1 -Action Snapshots` no longer lists `Snapshot_2026_01_01_00_00_00` — `Get-PoolSnapshotFolder` ignores `Pruning_*`!), HomeHub's retention wrapper will never know `Snapshot_2026_01_01_00_00_00` still has a `Pruning_Snapshot_...` residue folder!
  6. Because `Remove-CommittedPruneResidue` (`Engine.psm1:2447`) is **scoped only to the exact `$Name` passed to a future `-Action Prune`**, and `Clear-InterruptedRunResidue` in `Invoke-BackupSet` (`Engine.psm1:4213-4216`) only deletes `Incoming`, `Building_*`, and `.fbmountcheck-*` (never `Pruning_*`), the `Pruning_Snapshot_...` folder (and all the disk space it was supposed to free) **stays on disk forever**, never cleaned up by any backup run or any prune of newer snapshots!
- **Permanent or self-healing:** **Permanent disk-space leak / stranded `Pruning_*` folder** in automated operation (HomeHub queries `-Action Snapshots` to see what snapshots exist to prune; once renamed to `Pruning_<name>`, `-Action Snapshots` never lists it again, so HomeHub never passes `<name>` to `-Action Prune` again).
- **Why it is not contrived or accepted:** Antivirus/indexer holding a file during recursive directory deletion is the exact scenario Opus F4 (`Remove-UnchangedSnapshot`, C24) fixed for Step 7 of the backup run, and automated retention via `-Action Snapshots` + `-Action Prune` is the normal HomeHub retention flow.
- **Suggested fix:**
  1. In `Complete-PruneDeletion` (`Engine.psm1:2659`), wrap `Remove-Item -LiteralPath (Join-Path $parent $pruningName) -Recurse -Force -ErrorAction Stop` in a `try / catch` that logs a `WARN` (just like `Remove-UnchangedSnapshot` at `Engine.psm1:5033-5037`) instead of throwing and misreporting a post-commit prune as "aborted before the commit point" (exit 4).
  2. Have `Clear-InterruptedRunResidue` (`Engine.psm1:4214`) or `Remove-CommittedPruneResidue` clean up any `Pruning_*` folder under `ChangeRoot` while holding the OS lock (since any `Pruning_*` folder is already past the commit point and proven redundant).

---

### Finding 6 — Medium: `bash/reconstruct.sh` `restore_one` does not delete a partially written destination file when `cp -f` fails on a full target volume (`return 21`)

- **Where:** `bash/reconstruct.sh:350-352`.
- **Code path:**
  ```bash
  if (( needs_expand )); then
      if ! sevenzip_to_file "$src" "$dest"; then rm -f -- "$dest" 2>/dev/null; return 20; fi
  else
      cp -f -- "$src" "$dest" 2>/dev/null || return 21
  fi
  ```
- **Concrete steps:**
  1. Run `bash/reconstruct.sh` to restore a backup onto a target volume that fills up mid-restore (because compressed rows were excluded from the capacity pre-check, `reconstruct.sh:1334`, or another process wrote to the disk).
  2. A raw object is copied via `cp -f -- "$src" "$dest"`. `cp` writes part of the file, hits `ENOSPC`, and exits non-zero.
  3. `restore_one` returns `21` (`CandidateError`, exit 4) **without removing `"$dest"`** (unlike the `needs_expand` branch on line 349 and the mismatch branch on line 372, which both run `rm -f -- "$dest"`).
  4. The restore exits 4, leaving a **truncated, corrupt file** at the final destination path `$dest` in the restored tree. (The same applies to `Reconstruct.ps1:1412-1417` if `Copy-Item` fails mid-copy on an I/O error without removing `$DestFull`.)
- **Permanent or self-healing:** Leaves corrupt/truncated bytes at the destination path unless the user re-runs the restore.
- **Why it is not contrived or accepted:** Target volume filling up during restore (especially when compressed rows are present, since capacity pre-check skips compressed rows) is a normal host failure. SR-056 states that wrong/incomplete bytes must not be left at the destination path.
- **Suggested fix:** Add `rm -f -- "$dest" 2>/dev/null` before `return 21` in `bash/reconstruct.sh:351`, and `Remove-Item -LiteralPath $DestFull -Force -ErrorAction SilentlyContinue` in the `catch` block of `Copy-Item` in `Reconstruct.ps1:1414-1416`.

---

### Finding 7 — Low: `Get-SourceDirectoryRecord` (`DIRECTORIES.csv` sidecar) skips volume-root pseudo-folders inconsistently and compares `$unreadable` case-insensitively on Linux

- **Where:** `Modules/FileBackup.Engine.psm1:524-541`.
- **Code path:**
  ```powershell
  $enumErr = $null
  $dirs = @(Get-ChildItem -LiteralPath $root -Recurse -Directory -Force `
              -ErrorAction SilentlyContinue -ErrorVariable enumErr)
  ...
  foreach ($d in $dirs) {
      $rel = $d.FullName.Substring($root.Length).TrimStart('\', '/')
      if (-not $rel) { continue }

      $isUnreadable = $false
      foreach ($bad in $unreadable) {
          if ($d.FullName.Equals($bad, [System.StringComparison]::OrdinalIgnoreCase)) { $isUnreadable = $true; break }
      }
      if ($isUnreadable) { continue }
  ```
- **Concrete steps:**
  1. Point `SourcePath` at a volume root `D:\` (supported by SR-074).
  2. `Get-SourceFileList` (`Engine.psm1:4317`) filters out `Test-IsVolumeRootPseudoPath` (`$RECYCLE.BIN` and `System Volume Information`).
  3. In Step 6 (`Publish-LatestState`), `Get-SourceDirectoryRecord` (`Engine.psm1:524`) enumerates all directories under `D:\` with `-Force` and **does not call `Test-IsVolumeRootPseudoPath`**.
  4. Because no files from `$RECYCLE.BIN` were included in `$WalkPaths`, `$populated` has no entries for `$RECYCLE.BIN`.
  5. `Get-SourceDirectoryRecord` records `$RECYCLE.BIN` and all its subdirectories as "empty directories" (with their `Hidden,System` attributes) into `DIRECTORIES.csv`!
  6. Every restore of that backup recreates `$RECYCLE.BIN` (and its per-SID subfolders) inside the restore target folder.
- **Permanent or self-healing:** Recreates `$RECYCLE.BIN` in every restored tree from a volume-root backup.
- **Why it is not contrived or accepted:** SR-074 (`README.md:927-946`) explicitly excludes root-level `$RECYCLE.BIN` and `System Volume Information` when `SourcePath` is a volume root so they are never backed up or restored.
- **Suggested fix:** Add `if (Test-IsVolumeRootPseudoPath -Root $root -FullPath $d.FullName) { continue }` in `Get-SourceDirectoryRecord` (`Engine.psm1:534`).

---

## 5. What was not done, and why

- **Did not write `.opencode/plans/fb-review.md`:** Blocked by the session's active Plan Mode read-only system constraint, which strictly forbids creating or modifying any files.
- **Did not run Pester, `tests/Run-All.ps1`, or live repro scripts:** Pester and `Run-All.ps1` are forbidden by the brief, and bash execution is restricted by Plan Mode. All code paths were traced and verified line by line directly from the repository source files.
- **Did not benchmark 180,000-file / 1 TB runtime performance:** Static inspection confirmed per-file operations in the unchanged path (`Invoke-SourceFileCapture` -> `Get-LatestObject`) are $O(1)$ dictionary lookups with no extra stat calls.

---

## 6. Open questions for the caller

1. **Ruling question on power loss / write-cache durability (Finding 1):** Does the Owner want `Write-Manifest`, `Copy-FileWithHash`, and `Set-BackupStateField` to call `$stream.Flush($true)` (`FlushFileBuffers` / `fsync`) before renaming? For `Write-Manifest` and `FileBackupState.json` (a few writes per run), `Flush($true)` costs milliseconds and closes the 0-byte manifest/state window on power loss or USB disconnect. For `Copy-FileWithHash` (once per newly stored object), `Flush($true)` guarantees no 0-byte stored object after a crash, or alternatively `Get-StoreObjectIndex` can validate `$file.Length -eq $parsed.Length` on raw objects at zero write-time cost.
2. **Sibling store auto-detection when multiple sets share a parent directory (Finding 3):** When a user configures two sets under one parent folder (e.g. `E:\Backups\Set1_Backup`, `E:\Backups\Set1_Changes`, `E:\Backups\Set2_Backup`, `E:\Backups\Set2_Changes`, as in the README example) and restores a snapshot from a copied drive or on Linux, sibling auto-detection sees two manifests and fails to pick the backup root. Should `RECONSTRUCT.paths.json` record the relative path between `BackupRoot` and `ChangeRoot` so a moved/copied store or Linux restore always resolves its own sibling unambiguously?
