# FileBackup

Periodic, content-aware backup with change tracking and self-contained reconstruction
scripts. Written in PowerShell for Windows.

`FileBackup.ps1` keeps a manifest (`MANIFEST.csv`) of every file it has seen, hashes
content with **xxHash128**, deduplicates by `(hash, size)`, optionally compresses with
7-Zip, and writes a `Pre_<timestamp>_NNNNNN_Changes` folder on every run that captures
the *previous* state of any file that was changed or removed. Each backup folder gets a
`RECONSTRUCT.ps1` / `RECONSTRUCT.bat` pair that can rebuild the source tree from the
data files alone — no external tooling required at restore time.

---

## Repository layout

```
FileBackup/
├── FileBackup.ps1            Main backup engine (config-driven)
├── Reconstruct.ps1           Restore template — copied into each backup with paths injected
├── CredSetEx.ps1             Example credential / config builder
├── PrepPropertiesFile.ps1    Older config builder (legacy schema)
│
├── RunAllTests.bat           One-click test runner (default backend: Subst)
├── Setup-USB.bat             Elevates → invokes tests\Setup-USB.ps1
├── RunTests.bat              Legacy runner for Test-Backup.ps1
├── Test-Backup.ps1           Legacy single-file test harness
│
├── tests/                    New modular test harness
│   ├── Run-All.ps1               Master driver — sweeps modes × suites
│   ├── Setup.ps1                 Idempotent dependency installer
│   ├── Setup-USB.ps1             Partition + label a USB stick for the RealUSB backend
│   ├── Report.ps1                Console summary
│   ├── Report-JUnit.ps1          JUnit XML emitter (CI)
│   ├── Common/
│   │   ├── Harness.ps1           Result tracking, asserts, file generators
│   │   └── VolumeBackend.ps1     Subst / VHDX / RealUSB backends (same surface)
│   ├── Suites/
│   │   ├── G1-InitialBackup.ps1
│   │   ├── G2-Incremental.ps1
│   │   ├── G3-Reconstruction.ps1
│   │   ├── G4-Sanitization.ps1
│   │   ├── G5-EdgeCases.ps1
│   │   ├── G6-HashFrequency.ps1
│   │   ├── G7-Determinism.ps1
│   │   └── G8-RealVolume.ps1
│   └── Config/
│       └── real-volumes.json.example
│
├── Auxilary/                 Misc utilities (7z multi-archive, dedupe, etc.)
├── DatabaseDuplicateDeletion/  Ad-hoc dedup scripts against the manifest CSV
├── TestRelated/              Legacy test reset helpers (kept for reference)
├── .github/workflows/tests.yml CI: runs Subst backend on every push/PR
└── CHANGES.md / IMPLEMENTATION_SUMMARY.md / RUN_TESTS_README.md   Older docs
```

---

## Quick start

### Run a backup

1. Create your config:
   ```powershell
   .\CredSetEx.ps1     # prompts for SMTP creds and writes $HOME\BackupConfig.xml
   ```
2. Invoke the script:
   ```powershell
   .\FileBackup.ps1                      # uses $HOME\BackupConfig.xml
   .\FileBackup.ps1 -ConfigPath C:\my-config.xml
   ```

### Restore from a backup

Open the backup folder and run `RECONSTRUCT.bat`. It prompts for a target directory and
writes `RECONSTRUCT.log` next to the reconstructed tree. Run from a specific
`Pre_*_Changes` folder to restore the *historical* snapshot represented by that change
folder.

### Run the test suite

```powershell
.\RunAllTests.bat                       # Subst backend (no admin, no USB)
.\RunAllTests.bat VHDX                  # mounts VHDX disks (admin, Hyper-V module)
.\RunAllTests.bat RealUSB               # uses physical USB partitioned by Setup-USB
```

First run prompts once to install the `K4os.Hash.xxHash` NuGet package; subsequent runs
are silent.

---

## Config format

```powershell
@{
    Secrets = @{
        ToEmail    = 'you@example.com'
        FromEmail  = 'backup@example.com'
        SmtpServer = 'smtp.example.com'
        SmtpPort   = 587
        Credential = $cred           # PSCredential, e.g. from Get-Credential
    }
    BackupSets = @(
        [pscustomobject]@{
            Name               = 'MainData'
            SourcePath         = 'D:\Data'
            BackupPath         = 'E:\Backups\DataStore'
            ChangePath         = 'E:\Backups\DataChanges'
            HashRecalcFreq     = 'W'      # A/E/D/W/M/Y/N
            CompressEnabled    = $true
            PreserveFolderTree = $false   # $true = mirror tree, $false = <hash>_<size> filenames
        }
    )
} | Export-Clixml -Path $HOME\BackupConfig.xml
```

| Field | Meaning |
|---|---|
| `HashRecalcFreq` | When to recompute hash for an unchanged file. `A`=always, `E`=every run, `D`=daily, `W`=weekly, `M`=monthly, `Y`=yearly, `N`=never. |
| `CompressEnabled` | If `$true`, files are stored as `.7z` archives (already-compressed extensions are exempt). |
| `PreserveFolderTree` | `$true` mirrors source folder structure under the backup root; `$false` stores data files as `<hashShort>_<sizeShort>.<ext>` and references them via the manifest's `DataPath` column. |

---

## How it works

```
SOURCE                            BACKUP                              CHANGES
------                            ------                              -------
D:\Data\report.docx       -hash-> E:\Backups\Data\Ab92Cd_5K.7z        E:\Backups\DataChanges\
D:\Data\photo.jpg         -hash-> E:\Backups\Data\Xy7Ko_3M.jpg          Pre_2026_03_19_22_50_06_000003_Changes\
                                  MANIFEST.csv  ← (RelativePath, DataPath,                  ← previous data files
                                                  Length, hash, mtime, flags)                that were modified/removed
                                  RECONSTRUCT.ps1, RECONSTRUCT.bat                            on this run, plus a
                                                                                              pre-backup MANIFEST.csv
```

Per run, `FileBackup.ps1` performs **14 ordered steps** (see `Run-BackupSet`):

1. Resolve `SourcePath`, `BackupPath`, `ChangePath`
2. Open `backup.log` in the change root
3. Guard against a stale `Temp` staging folder
4. `UpdateSourceDatabase` — walk source, recompute hashes for new/changed files
5. `SanitizeBackupDatabase` — migrate backup files if config (compress/tree-mode) changed
6. Decide whether `HashRecalcFreq` requires re-hashing untouched files
7. Snapshot pre-backup manifest into the staging folder
8. `Compare-SourceToBackup` — pure diff into `NewOrChanged` + `RemovedFromSource`
9. Build the in-memory updated backup map
10. `Invoke-BackupFileGroup` per `(hash,size)` group — copy/compress new data
11. `Move-RemovedFilesToStaging` — orphan ex-files into the staging folder
12. Write the final backup manifest
13. `GenerateReconstructScript` + `Finalize-ChangeFolder`
14. `SanitizeChangeDatabase` — collapse cross-change duplicates

---

## Manifest schema

| Column | Meaning |
|---|---|
| `DataPath`           | Path of the actual data file, relative to its parent folder (backup root or change folder). Blank means "look up by hash" — `Reconstruct.ps1` handles this. |
| `RelativePath`       | Path of the original file under the source root. The "logical name". |
| `Length`             | Byte length of the original. |
| `LastWriteTimeStr`   | ISO 8601 (`'O'` format). |
| `xxH2Hash`           | xxHash128 hex (16 + 16 hex chars). |
| `Compressed`         | `Yes` / `No` — does the data file have `.7z`? |
| `StoredAsHashSize`   | `Hash` or `Original` — naming convention used for `DataPath`. |
| `Duplicate`          | `1` if another row shares the same `(hash, length)` and was chosen as the keeper. |
| `MediaMBPerSec`      | Optional, from `ffprobe`. Useful for bandwidth/storage reports. |

---

## Test plan

The harness sweeps **storage mode × compression × suite group**, with a backend axis
for *where* the volumes live:

| Mode | PreserveFolderTree | Compression |
|---|---|---|
| `Mirror`                  | true  | false |
| `Mirror+Compress`         | true  | true  |
| `HashAddressed`           | false | false |
| `HashAddressed+Compress`  | false | true  |

Each combination runs 8 suite groups:

| Group | What it covers |
|---|---|
| **G1 InitialBackup** | Empty source, single file, 200-file bulk, Unicode names, nested `MANIFEST.csv` regression (bug B6), bracketed paths. |
| **G2 Incremental**   | Rename, move, modify, delete, re-add identical, re-add different, duplicate detection. |
| **G3 Reconstruction**| Roundtrip from backup root, hash-fallback when `DataPath` is blanked, target inside backup-root rejected. |
| **G4 Sanitization**  | Mirror → HashAddressed migration; manifest `StoredAsHashSize` flips correctly. |
| **G5 EdgeCases**     | Stale `Temp` aborts cleanly, read-only source files, idempotent second run. |
| **G6 HashFrequency** | Unit checks against `Should-RecalculateHashes` for all 7 freq codes × bounded date deltas. |
| **G7 Determinism**   | Identical re-runs produce identical manifest rows; SHA-256 spot check. |
| **G8 RealVolume**    | USB-only: presence/labeling sanity, real-disk single-pass backup. SKIPs under Subst/VHDX. |

### Backends

| Backend | How it provisions volumes | Admin? | Available in CI? | Use it when |
|---|---|---|---|---|
| **Subst**   | `subst X: Y: Z: W:` over `%TEMP%` directories | no  | yes | default; fastest; CI runner. |
| **VHDX**    | Dynamic VHDX files mounted as letters         | yes | self-hosted only | capacity / free-space tests; real NTFS semantics. |
| **RealUSB** | Reads `tests\Config\real-volumes.json` and resolves the four `FBTEST-*` labels via `Get-Volume` | no\* | no | catches real-hardware bugs (FAT32 size limits, slow seek). \* The *initial* partition step needs admin; running tests after doesn't. |

### Real-hardware setup

```cmd
Setup-USB.bat            REM elevates, then runs tests\Setup-USB.ps1
```

Wipes the chosen USB device, creates four GPT/NTFS partitions, labels them
`FBTEST-SRC` / `FBTEST-BKP` / `FBTEST-CHG` / `FBTEST-RCN`, and copies
`real-volumes.json.example` → `real-volumes.json`. The harness refuses any label that
does not match the `FBTEST-*` prefix — a safety net so you can't accidentally point it
at a labeled production volume.

After that, plug in the stick and run:

```cmd
RunAllTests.bat RealUSB
```

### Continuous integration

`.github/workflows/tests.yml` runs the **Subst** backend on `windows-latest` for every
push to `main` / `working` / `Claude` and every PR. Results are uploaded as artifacts
and surfaced as a JUnit report via `dorny/test-reporter`. The **VHDX** job only fires
on a self-hosted runner that exposes the `hyper-v` label and where the repo variable
`HAS_SELF_HOSTED_HYPERV == 'true'`. Real USB is not supported on hosted runners.

### Results

Every run drops:

```
%TEMP%\FileBackupTests\run_YYYYMMDD_HHMMSS\
├── results.csv         Structured rows: Suite, Group, ScenarioId, TestName, Status, Detail, Timestamp
├── results.xml         JUnit (when -EmitJUnit is passed; CI does this automatically)
└── env\                Per-run scratch folders (Source / Backup / Changes / Recon)
```

The console emitter at the end prints a coloured PASS / FAIL / SKIP summary plus a
table of failures.

---

## Known issues & roadmap

Bugs identified in the current review (still open after the syntax + date-format fixes
already applied on this branch):

| ID | Severity | Description |
|---|---|---|
| B2 | low    | `Should-RecalculateHashes` coerces `$null` to `DateTime.MinValue`; guard is partially unreachable. |
| B3 | medium | "Last hash run" derived from manifest `LastWriteTime` — conflated with source mtimes. |
| B4 | low    | `$recalc` computed but unused — `UpdateSourceDatabase` already rehashes on mtime change. |
| B5 | low    | `[IEnumerable[object]]` type accelerator is non-generic; should be `[System.Collections.IEnumerable]`. |
| B6 | medium | `MANIFEST.csv` exclusion is by name only — silently drops any nested user file with that exact name. G1.5 exercises this. |
| B7 | medium | Sanitize step deletes duplicate data files before re-saving manifest; out-of-space mid-step can lose pointers. |
| B8 | low    | `$existingBackupWithHash[0]` not wrapped in `@(...)`; relies on PowerShell array leniency. |
| B9 | medium | `Move-RemovedFilesToStaging` doesn't refcount shared `DataPath`s; can orphan a still-needed data file. |
| B10 | low   | `Reconstruct.ps1` without overrides assumes `CHANGES\` sibling; mismatched with main script's behavior. |
| B11 | low   | Capacity pre-check sums uncompressed lengths even on compressed backups (conservative on big archives, optimistic on temp-decompress headroom). |
| B12 | low   | Subst drives leak on parse failures (legacy `Test-Backup.ps1`). The new harness disposes via `try/finally` *and* an explicit `Dispose` scriptblock per backend. |
| B13 | low   | Legacy `Test-Backup.ps1` EdgeCases group depends on prior-group state. New harness resets between groups. |
| B14 | medium | Legacy harness coverage was thin (~28 assertions, never hit Mirror+Compress, freq codes, or sanitize migration). New harness fills this in. |
| B15 | low   | `Send-MailMessage` is obsoleted in PS 7+. Tests already swallow mail errors. |
| B16 | trivial | `Should-CompressFile`'s `$FullPath` only used for extension; rename for clarity. |
| B17 | trivial | Docs drift: `PrepPropertiesFile.ps1` writes a different schema than `FileBackup.ps1` consumes. |

Use these as issue seeds — fix incrementally with the test suite as the gate.

---

## Dependencies

| What | Where / how | Required? |
|---|---|---|
| PowerShell 5.1 or 7+    | Windows built-in / `winget install Microsoft.PowerShell` | yes |
| K4os.Hash.xxHash 1.0.8  | `Install-Package K4os.Hash.xxHash -RequiredVersion 1.0.8 -Scope CurrentUser` (auto by Setup) | yes |
| 7-Zip                   | `winget install 7zip.7zip` | only when `CompressEnabled = $true` |
| ffmpeg/ffprobe          | `C:\ffmpeg\bin\ffprobe.exe` | optional — populates `MediaMBPerSec` |
| Hyper-V PowerShell      | `Enable-WindowsOptionalFeature -FeatureName Microsoft-Hyper-V-Tools-All` | only for `VHDX` test backend |
