# FileBackup

Periodic, content-aware backup with change tracking and self-contained
reconstruction scripts. PowerShell **7+**, Windows.

FileBackup walks a source tree, hashes every file with **xxHash128**, deduplicates
identical content by `(hash, size)`, optionally compresses with 7-Zip, and records
everything in a `MANIFEST.csv`. When a run supersedes earlier content it preserves a
**dated point-in-time snapshot** (`Snapshot_<date>`) of the prior state, and drops a
**self-contained restore kit** into the backup so you can rebuild *any* point in time —
the latest from the backup folder, or an earlier state from its dated snapshot — with
nothing but that folder. No repository, no installs.

> **Status:** functional and covered by a green test suite — 212 integration assertions
> across all four storage modes (incl. the G9 rollback matrix) plus 42 unit tests.
> Contributors and agents modifying the tool should read **[AGENTS.md](AGENTS.md)**
> (architecture, invariants, test matrix, history).

---

## Requirements

| What | How | Needed for |
|---|---|---|
| **PowerShell 7+** (`pwsh`) | `winget install Microsoft.PowerShell` | everything (Windows PowerShell 5.1 is **not** supported) |
| **System.IO.Hashing** (NuGet) | auto-installed on first run, or `Install-Package System.IO.Hashing -RequiredVersion 8.0.0 -Scope CurrentUser` | xxHash128 hashing (required) |
| **7-Zip** | `winget install 7zip.7zip` | only when `CompressEnabled = $true` |
| **ffmpeg/ffprobe** | put `ffprobe.exe` at `C:\ffmpeg\bin\` | optional media bitrate column |

---

## Quick start

### 1. Create a config

Edit and run the example builder (writes `$HOME\BackupConfig.xml`):

```powershell
pwsh -File .\CredSetEx.ps1     # prompts for the SMTP account (mail is optional)
```

### 2. Run a backup

```powershell
pwsh -File .\FileBackup.ps1                       # uses $HOME\BackupConfig.xml
pwsh -File .\FileBackup.ps1 -ConfigPath C:\my.xml
pwsh -File .\FileBackup.ps1 -NoMail               # skip the success/failure email
```

First run installs `System.IO.Hashing` per-user (prompts unless already present).

### 3. Restore

Open the backup folder and run **`RECONSTRUCT.bat`**. It asks for a target directory and
writes a `RECONSTRUCT.log` next to the restored tree. To restore a *historical* state,
run the `RECONSTRUCT.bat` inside a specific dated `Snapshot_<date>` folder instead — it
reproduces exactly the state as of that backup. The backup
folder is self-contained — it carries `RECONSTRUCT.ps1`, the hashing module, the
`System.IO.Hashing.dll`, and a path sidecar — so restore works on a machine without this
repo.

---

## Config format

```powershell
@{
    Secrets = @{                          # entire block optional → no email is sent
        ToEmail    = 'you@example.com'
        FromEmail  = 'backup@example.com'
        SmtpServer = 'smtp.example.com'
        SmtpPort   = 587
        Credential = $cred                # PSCredential (e.g. Get-Credential)
    }
    BackupSets = @(
        [pscustomobject]@{
            Name               = 'MainData'
            SourcePath         = 'D:\Data'
            BackupPath         = 'E:\Backups\DataStore'
            ChangePath         = 'E:\Backups\DataChanges'
            HashRecalcFreq     = 'W'      # A/E/D/W/M/Y/N
            CompressEnabled    = $true
            PreserveFolderTree = $false   # $true = mirror tree; $false = "<hash> <size>" names
        }
    )
} | Export-Clixml -Path $HOME\BackupConfig.xml
```

| Field | Meaning |
|---|---|
| `HashRecalcFreq` | When to re-hash an *unchanged* file. `A`/`E`=always, `D`=daily, `W`=weekly, `M`=monthly, `Y`=yearly, `N`=never. |
| `CompressEnabled` | `$true` stores data files as `.7z` (already-compressed extensions are exempt). |
| `PreserveFolderTree` | `$true` mirrors the source tree under the backup root; `$false` stores content-addressed `<hashShort> <sizeShort>.<ext>` files referenced via the manifest. |

You can list multiple `BackupSets`; each is processed independently.

---

## How it works

```
SOURCE                      BACKUP (latest state)                 SNAPSHOTS (older states)
------                      ---------------------                 ------------------------
D:\Data\report.docx  -hash→ E:\…\DataStore\Ab92Cd 5K.7z          E:\…\DataChanges\
D:\Data\photo.jpg    -hash→ E:\…\DataStore\Xy7Ko 3M.jpg            Snapshot_2026_03_19_22_50_06\
                            MANIFEST.csv                            ← full point-in-time MANIFEST.csv
                            RECONSTRUCT.ps1/.bat                       + only the superseded bytes
                            FileBackup.Common.psm1                     + a restore kit
                            System.IO.Hashing.dll                  Snapshot_2026_02_10_08_00_00\  …
                            FileBackupState.json
```

Identical content is stored once (keyed on `(xxHash128, length)`); extra logical names just
point at the same data file. The backup root is always the **latest** state. Each older
state is a `Snapshot_<date>` folder named for the backup whose state it preserves — it holds
that point's full manifest plus only the bytes superseded afterward, and resolves everything
else by hash from the backup root. The **most recent run has no snapshot** (it *is* the live
backup), and a run that changes nothing creates none.

### Manifest columns

`DataPath` · `RelativePath` · `Length` · `LastWriteTimeStr` · `xxH2Hash` · `Compressed` ·
`StoredAsHashSize` · `Duplicate` · `MediaMBPerSec`. A blank `DataPath` means "recover by
content hash" — the restore script scans for a matching file (decompressing `.7z`
candidates as needed).

---

## Repository layout

```
FileBackup.ps1            Entry point (reads config, runs each backup set)
Reconstruct.ps1          Restore script (deployed standalone into each backup folder)
Modules/
  FileBackup.Common.psm1   Restore-safe primitives (hashing, manifest I/O, 7-Zip, …)
  FileBackup.Engine.psm1   Backup engine (walk, diff, dedup, migrate, change folders)
CredSetEx.ps1            Example config builder  ·  PrepPropertiesFile.ps1 (legacy)
RunAllTests.bat          Test runner  ·  Setup-USB.bat  (RealUSB provisioning)
tests/                   Test harness — Run-All.ps1, Suites/G1..G9, Unit/*.Tests.ps1
Auxilary/                Standalone personal utilities (see AGENTS.md)
DatabaseDuplicateDeletion/  Standalone ad-hoc dedup pipeline (see AGENTS.md)
.github/workflows/tests.yml CI: lint + unit + Subst integration
AGENTS.md                Contributor/agent guide (architecture, invariants, tests, history)
```

---

## Testing

```powershell
.\RunAllTests.bat            # Subst backend — no admin, no USB (the default)
.\RunAllTests.bat VHDX       # virtual disks (admin + Hyper-V)
.\RunAllTests.bat RealUSB    # physical USB partitioned by Setup-USB.bat
```

Unit tests: `Invoke-Pester tests\Unit`. The full backend/mode/hardware matrix and the
suite breakdown live in **[AGENTS.md](AGENTS.md)**.

---

## Notes & troubleshooting

- **PowerShell 5.1 is unsupported.** The hashing library's Desktop build needs transitive
  `System.Memory` assemblies absent from a stock 5.1 session. Use `pwsh`.
- **Email is optional.** Omit the `Secrets` SMTP fields (or pass `-NoMail`); mail failures
  are logged, never fatal.
- **Stale `Temp` folder error.** A prior run aborted mid-flight; remove the leftover `Temp`
  folder under your `ChangePath` and re-run.
- The **Auxilary/** and **DatabaseDuplicateDeletion/** scripts are standalone personal
  tools with hardcoded paths — not part of the backup engine. See [AGENTS.md](AGENTS.md).
