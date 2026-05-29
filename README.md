# FileBackup

Periodic, content-aware backup with change tracking and self-contained
reconstruction scripts. Written in PowerShell for Windows (**PowerShell 7+**).

`FileBackup.ps1` keeps a manifest (`MANIFEST.csv`) of every file it has seen, hashes
content with **xxHash128** (`System.IO.Hashing`), deduplicates by `(hash, size)`,
optionally compresses with 7-Zip, and writes a `Pre_<timestamp>_NNNNNN_Changes` folder
on every run that captures the *previous* state of any file that was changed or removed.
Each backup folder gets a self-contained `RECONSTRUCT.ps1` / `RECONSTRUCT.bat` pair —
plus the bundled hashing module and DLL — that can rebuild the source tree from the data
files alone, with no repository or NuGet install needed at restore time.

> **Status:** the engine is functional and gated by a green test suite (160 integration
> assertions across 4 storage modes + 27 Pester unit tests). See [CHANGELOG.md](CHANGELOG.md)
> for the history, including the dependency and correctness fixes that made the tool run
> for the first time.

---

## Repository layout

```
FileBackup/
├── FileBackup.ps1            Thin entry point (parses config, runs each backup set)
├── Reconstruct.ps1           Restore script — deployed standalone into each backup folder
├── Modules/
│   ├── FileBackup.Common.psm1    Restore-safe primitives (hashing, manifest I/O, 7-Zip,
│   │                             short-name encoding, logging). Bundled into backups.
│   └── FileBackup.Engine.psm1    Backup engine (source walk, diff, dedup copy, storage
│                                 migration, change folders, reconstruct generation)
│
├── CredSetEx.ps1             Example config builder (writes $HOME\BackupConfig.xml)
├── PrepPropertiesFile.ps1    Legacy/alternate config builder (see header note)
│
├── RunAllTests.bat           One-click test runner (default backend: Subst)
├── Setup-USB.bat             Elevates → invokes tests\Setup-USB.ps1
│
├── tests/                    Test harness (see tests/README.md)
│   ├── Run-All.ps1               Master driver — sweeps modes × suites
│   ├── Setup.ps1                 Idempotent dependency installer
│   ├── Setup-USB.ps1             Partition + label a USB stick for the RealUSB backend
│   ├── Report.ps1 / Report-JUnit.ps1
│   ├── PSScriptAnalyzerSettings.psd1  Lint configuration
│   ├── Common/Harness.ps1, Common/VolumeBackend.ps1
│   ├── Suites/G1..G8-*.ps1        Integration suites
│   └── Unit/*.Tests.ps1          Pester 5 unit tests (pure functions)
│
├── Auxilary/, DatabaseDuplicateDeletion/   Misc utilities
├── .github/workflows/tests.yml             CI: lint + unit + Subst integration
└── AGENTS.md · CHANGELOG.md · TEST_MATRIX.md · README.md
```

Legacy `Test-Backup.ps1` / `RunTests.bat` are superseded by `tests/` and kept only for
reference (see [AGENTS.md](AGENTS.md)).

---

## Quick start

### Run a backup

1. Create your config:
   ```powershell
   .\CredSetEx.ps1     # prompts for SMTP creds and writes $HOME\BackupConfig.xml
   ```
2. Invoke the script (under **pwsh**):
   ```powershell
   pwsh -File .\FileBackup.ps1                      # uses $HOME\BackupConfig.xml
   pwsh -File .\FileBackup.ps1 -ConfigPath C:\my-config.xml
   pwsh -File .\FileBackup.ps1 -NoMail              # skip the notification email
   ```

On first use the script installs the `System.IO.Hashing` NuGet package per-user (prompts
unless already present).

### Restore from a backup

Open the backup folder and run `RECONSTRUCT.bat`. It prompts for a target directory and
writes `RECONSTRUCT.log` next to the reconstructed tree. Run from a specific
`Pre_*_Changes` folder to restore the *historical* snapshot represented by that change
folder. The backup folder is self-contained — it carries `RECONSTRUCT.ps1`,
`FileBackup.Common.psm1`, `System.IO.Hashing.dll`, and a `RECONSTRUCT.paths.json` sidecar.

### Run the tests

```powershell
.\RunAllTests.bat                       # Subst backend (no admin, no USB)
.\RunAllTests.bat VHDX                  # mounts VHDX disks (admin, Hyper-V module)
.\RunAllTests.bat RealUSB               # uses a physical USB partitioned by Setup-USB
```

See [tests/README.md](tests/README.md) for the unit suite, lint, and backend details, and
[TEST_MATRIX.md](TEST_MATRIX.md) for the full permutation map.

---

## Config format

```powershell
@{
    Secrets = @{
        ToEmail    = 'you@example.com'
        FromEmail  = 'backup@example.com'
        SmtpServer = 'smtp.example.com'
        SmtpPort   = 587
        Credential = $cred           # PSCredential (optional; mail is skipped if absent)
    }
    BackupSets = @(
        [pscustomobject]@{
            Name               = 'MainData'
            SourcePath         = 'D:\Data'
            BackupPath         = 'E:\Backups\DataStore'
            ChangePath         = 'E:\Backups\DataChanges'
            HashRecalcFreq     = 'W'      # A/E/D/W/M/Y/N
            CompressEnabled    = $true
            PreserveFolderTree = $false   # $true = mirror tree, $false = "<hash> <size>" filenames
        }
    )
} | Export-Clixml -Path $HOME\BackupConfig.xml
```

| Field | Meaning |
|---|---|
| `HashRecalcFreq` | When to recompute the hash of an *unchanged* file. `A`/`E`=always, `D`=daily, `W`=weekly, `M`=monthly, `Y`=yearly, `N`=never. |
| `CompressEnabled` | If `$true`, files are stored as `.7z` archives (already-compressed extensions are exempt). |
| `PreserveFolderTree` | `$true` mirrors the source tree under the backup root; `$false` stores data files as `<hashShort> <sizeShort>.<ext>` referenced via the manifest's `DataPath`. |

---

## How it works

```
SOURCE                            BACKUP                              CHANGES
------                            ------                              -------
D:\Data\report.docx       -hash-> E:\Backups\Data\Ab92Cd 5K.7z       E:\Backups\DataChanges\
D:\Data\photo.jpg         -hash-> E:\Backups\Data\Xy7Ko 3M.jpg         Pre_2026_03_19_22_50_06_000003_Changes\
                                  MANIFEST.csv                          ← previous data files
                                  RECONSTRUCT.ps1/.bat                    modified/removed this run,
                                  FileBackup.Common.psm1                  plus a pre-backup MANIFEST.csv
                                  System.IO.Hashing.dll
                                  FileBackupState.json (last hash run)
```

Per run, for each set, `Invoke-BackupSet` (in `FileBackup.Engine.psm1`) performs an
ordered pipeline:

1. Resolve `SourcePath` / `BackupPath` / `ChangePath`.
2. Open `backup.log` in the change root.
3. Guard against a stale `Temp` staging folder.
4. Read the persisted last-hash-run time and decide if a scheduled rehash is due.
5. `Update-SourceManifest` — walk source, (re)hash new/changed/scheduled files.
6. `Sync-BackupStorageLayout` — migrate backup files when compress/tree mode changed.
7. Snapshot the pre-backup manifest into staging.
8. `Compare-SourceToBackup` — pure diff into `NewOrChanged` + `RemovedFromSource`.
9. Build the in-memory updated backup map.
10. `Invoke-BackupFileGroup` per `(hash,size)` group — copy/compress new data once.
11. `Move-RemovedFilesToStaging` — evict removed files' data (refcount-aware).
12. Write the final backup manifest.
13. `New-ReconstructScript` + `Complete-ChangeFolder` (collision-safe naming).
14. `Optimize-ChangeFolders` — collapse cross-change duplicates.
15. Persist the last-hash-run timestamp if a rehash ran.

---

## Manifest schema

| Column | Meaning |
|---|---|
| `DataPath`         | Path of the data file relative to its parent folder. Blank means "recover by hash". |
| `RelativePath`     | Path of the original file under the source root (the logical name). |
| `Length`           | Byte length of the original. |
| `LastWriteTimeStr` | ISO 8601 (`'O'`). |
| `xxH2Hash`         | xxHash128, 32 uppercase hex chars. |
| `Compressed`       | `Yes` / `No` — is the data file a `.7z`? |
| `StoredAsHashSize` | `Hash` or `Original` — naming convention used for `DataPath`. |
| `Duplicate`        | `1` if another row shares the same `(hash, length)` and was the chosen keeper. |
| `MediaMBPerSec`    | Optional, from `ffprobe`. |

---

## Dependencies

| What | Where / how | Required? |
|---|---|---|
| PowerShell 7+          | `winget install Microsoft.PowerShell` | yes |
| System.IO.Hashing 8.0  | `Install-Package System.IO.Hashing -RequiredVersion 8.0.0 -Scope CurrentUser` (auto on first use / `tests\Setup.ps1`) | yes (xxHash128) |
| 7-Zip                  | `winget install 7zip.7zip` | only when `CompressEnabled = $true` |
| ffmpeg/ffprobe         | `C:\ffmpeg\bin\ffprobe.exe` | optional — populates `MediaMBPerSec` |
| Pester 5, PSScriptAnalyzer | `tests\Setup.ps1 -InstallTestTools` | tests/lint only |

> **Windows PowerShell 5.1 is not supported.** The hashing library's Desktop build pulls
> transitive `System.Memory` assemblies that aren't present in a stock 5.1 session; the
> tool targets `pwsh` 7+, which is also what CI runs.

---

## Known issues & roadmap

The correctness bugs catalogued in earlier reviews (B2–B11, B15–B17) and the dependency /
parser defects discovered during the modularization have been fixed and are gated by the
test suite — see [CHANGELOG.md](CHANGELOG.md). Remaining ideas:

- Hash-based recovery decompresses every `.7z` candidate when scanning; fine as a rare
  fallback, but could be indexed for large compressed stores.
- `Send-MailMessage` is obsolete in PS 7+; it still works for a local notifier but a
  modern transport (e.g. MailKit) would be more future-proof.
- A self-hosted VHDX CI lane and the RealUSB hardware lane are documented runbooks rather
  than automated gates (see [TEST_MATRIX.md](TEST_MATRIX.md)).

Contributing conventions and invariants live in [AGENTS.md](AGENTS.md).
