# FileBackup tests

Two layers, both PowerShell 7+:

| Layer | Where | What | Run |
|---|---|---|---|
| **Unit** (Pester 5) | `tests/Unit/*.Tests.ps1` | Pure functions (hashing, encoding, manifest I/O, diff, hash-recalc schedule, infra-file filter). Fast, no volumes. | `Invoke-Pester tests/Unit` |
| **Integration** | `tests/Run-All.ps1` + `tests/Suites/G1..G8` | End-to-end backups/restores over real volumes (subst/VHDX/USB), sweeping storage modes. | `.\RunAllTests.bat` |
| **Lint** | `tests/PSScriptAnalyzerSettings.psd1` | PSScriptAnalyzer over scripts + modules. | see below |

## Setup

```powershell
pwsh -File tests\Setup.ps1 -InstallDeps -InstallTestTools
```

Installs `System.IO.Hashing` (required), and — with `-InstallTestTools` — Pester 5 and
PSScriptAnalyzer. 7-Zip is detected; if missing, compression paths still run (7-Zip is
present on GitHub `windows-latest`).

## Running

### Unit (Pester)
```powershell
Invoke-Pester -Path tests\Unit -Output Detailed
```

### Lint
```powershell
Import-Module PSScriptAnalyzer
Get-ChildItem -Recurse -Include *.ps1,*.psm1 -Path FileBackup.ps1,Reconstruct.ps1,Modules,tests |
    ForEach-Object { Invoke-ScriptAnalyzer -Path $_.FullName -Settings tests\PSScriptAnalyzerSettings.psd1 }
```

### Integration
```powershell
.\RunAllTests.bat                       # Subst backend (default; no admin, no USB)
.\RunAllTests.bat VHDX                  # VHDX disks (admin + Hyper-V module)
.\RunAllTests.bat RealUSB               # physical USB partitioned by Setup-USB

# or directly, with control over modes/groups:
pwsh -File tests\Run-All.ps1 -Backend Subst `
    -Modes 'Mirror,Mirror+Compress,HashAddressed,HashAddressed+Compress' `
    -Groups 'G1,G2,G3,G4,G5,G6,G7,G8' -EmitJUnit
```

`Run-All.ps1` exits non-zero if any assertion fails. Results land in
`%TEMP%\FileBackupTests\run_<stamp>\` (`results.csv`, optional JUnit `results.xml`, and an
`env\` scratch tree).

## Storage-mode sweep

| Mode | PreserveFolderTree | Compression |
|---|---|---|
| `Mirror`                 | true  | false |
| `Mirror+Compress`        | true  | true  |
| `HashAddressed`          | false | false |
| `HashAddressed+Compress` | false | true  |

## Suite groups

| Group | Covers |
|---|---|
| **G1 InitialBackup** | Empty source, single file, 200-file bulk, nested `MANIFEST.csv` (B6 regression), Unicode names, bracketed paths. |
| **G2 Incremental**   | Rename, move, modify, delete, re-add identical/different, duplicate detection. |
| **G3 Reconstruction**| Roundtrip from backup root, hash-fallback when `DataPath` is blank (incl. compressed), target-inside-backup rejected. |
| **G4 Sanitization**  | Mirror → HashAddressed migration; `StoredAsHashSize` flips. |
| **G5 EdgeCases**     | Stale `Temp` aborts, read-only source files, idempotent second run. |
| **G6 HashFrequency** | Unit checks of `Test-HashRecalcDue` across all 7 freq codes (deterministic via `-Now`). |
| **G7 Determinism**   | Identical re-runs ⇒ identical manifest rows; SHA-256 spot check. |
| **G8 RealVolume**    | USB-only sanity; SKIPs under Subst/VHDX. |

## Backends

| Backend | Provisioning | Admin? | CI? |
|---|---|---|---|
| **Subst**   | `subst` over `%TEMP%` dirs, on dynamically-chosen free drive letters | no  | yes |
| **VHDX**    | Dynamic VHDX files mounted as letters (NTFS) | yes | self-hosted only |
| **RealUSB** | Resolves the four `FBTEST-*` labels from `tests\Config\real-volumes.json` | no* | no |

\* The initial partition step (`Setup-USB.bat`) needs admin; running tests afterward does
not. The harness refuses any label not matching `FBTEST-*` so it can't touch a production
volume.

### Real-hardware setup
```cmd
Setup-USB.bat            REM elevates, then runs tests\Setup-USB.ps1
RunAllTests.bat RealUSB
```

See [../TEST_MATRIX.md](../TEST_MATRIX.md) for the full permutation map (CI / virtual /
hardware) and which cells are automated vs. manual runbooks.
