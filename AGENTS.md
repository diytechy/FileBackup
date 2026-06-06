# AGENTS.md — contributor & agent guide

Everything needed to safely modify FileBackup. Users who just want to run it should read
[README.md](README.md); this file is the single source for architecture, invariants,
conventions, the test matrix, and history.

---

## 1. What this is

A Windows **PowerShell 7+** content-aware backup tool. `FileBackup.ps1` walks a source
tree, hashes files with xxHash128 (`System.IO.Hashing`), deduplicates by `(hash, size)`,
optionally 7-Zip-compresses, and records `MANIFEST.csv`. Each run snapshots prior versions
into a `Pre_<timestamp>_NNNNNN_Changes` folder and drops a self-contained restore kit.
`Reconstruct.ps1` rebuilds the tree from a backup or change folder alone.

## 2. Architecture & module map

| File | Role | Bundled into backups? |
|---|---|---|
| `Modules/FileBackup.Common.psm1` | **Restore-safe primitives**: `Get-FileXxHash`, `Initialize-XxHashLibrary`, `Get-XxHashDllPath`, `Read-/Write-Manifest`, `Compress-/Expand-FileWithSevenZip`, `Test-ShouldCompress`, short-name encoding, `New-Logger`, `Get-FileBackupDefaults`. | **Yes** |
| `Modules/FileBackup.Engine.psm1` | **Backup-only logic**: `Update-SourceManifest`, `Compare-SourceToBackup`, `Invoke-BackupFileGroup`, `Sync-BackupStorageLayout`, `Optimize-ChangeFolders`, `Move-RemovedFilesToStaging`, `New-ReconstructScript`, `Complete-ChangeFolder`, `Invoke-BackupSet`, `Test-HashRecalcDue`, `Test-IsInfrastructureFile`, … | No |
| `FileBackup.ps1` | Thin entry point: import modules, read config, loop `Invoke-BackupSet`, optional mail. | n/a |
| `Reconstruct.ps1` | Standalone restore; imports the **bundled** Common module. | itself |

**The Common/Engine split is load-bearing.** `New-ReconstructScript` copies
`Reconstruct.ps1`, `FileBackup.Common.psm1`, `System.IO.Hashing.dll`, and a
`RECONSTRUCT.paths.json` sidecar into each backup folder so a restore needs nothing else.
Therefore:

- Anything `Reconstruct.ps1` calls **must live in Common**, not Engine.
- **Common must never depend on Engine.**

### Backup pipeline (`Invoke-BackupSet`, per set, per run)
1. Resolve `SourcePath`/`BackupPath`/`ChangePath`.
2. Open `backup.log` in the change root.
3. Guard against a stale `Temp` staging folder.
4. Read persisted last-hash-run time; decide if a scheduled rehash is due.
5. `Update-SourceManifest` — walk source, (re)hash new/changed/scheduled files.
6. `Sync-BackupStorageLayout` — migrate data files if compress/tree mode changed.
7. Snapshot the pre-run manifest into staging (the point-in-time index).
8. `Compare-SourceToBackup` — pure diff (`NewOrChanged` + `RemovedFromSource`).
9. Build the working backup map.
9.5 `Save-SupersededData` — move superseded prior bytes into staging *before*
    `Invoke-BackupFileGroup` overwrites (Mirror) or orphans (HashAddressed) them.
10. `Invoke-BackupFileGroup` per `(hash,size)` — copy/compress new data once.
11. `Move-RemovedFilesToStaging` — evict removed files' data (refcount-aware).
12. Write the final backup manifest.
13. `New-ReconstructScript` + `Complete-ChangeFolder` — finalize the staging into a
    dated `Snapshot_<prior-backup-date>`, or discard it when nothing was superseded.
14. `Optimize-ChangeFolders` — collapse data shared across snapshots.
15. Persist `LastHashRun` (if a rehash ran) + `LastBackupRun` (this run's date).

## 3. Invariants — do not break

- **Manifest schema** (9 columns): `DataPath, RelativePath, Length, LastWriteTimeStr,
  xxH2Hash, Compressed, StoredAsHashSize, Duplicate, MediaMBPerSec`. Round-trip only via
  `Read-Manifest`/`Write-Manifest`.
- **Dedup key is `(xxH2Hash, Length)`** — one physical data file per key.
- **Dated snapshots** (`Snapshot_<date>`, matching `^Snapshot_\d{4}_\d{2}_\d{2}_\d{2}_\d{2}_\d{2}`):
  one per *superseded* backup, named by that backup's completion date (persisted
  in `FileBackupState.json` as `LastBackupRun`). The **latest state has no
  snapshot** — the live backup root is it; a **no-op run creates none**. A snapshot
  holds the full point-in-time manifest plus only the bytes superseded at the next
  run (`Save-SupersededData` preserves them *before* they're overwritten/orphaned).
  **Restore authority (SR-010):** reconstruct from a snapshot uses *that snapshot's
  own manifest* as the sole authority and resolves bytes by `(hash,length)` from
  the data pool (backup root + all snapshots) — it never overlays a newer manifest.
  Clean cutover: no `Pre_*_Changes` reading/writing remains (SR-005/SR-010/SR-028).
- **Reconstruct stays standalone** — no repo, no NuGet install at restore time.
- **Infrastructure files are root-level only** (`Test-IsInfrastructureFile`): a *nested*
  user file named `MANIFEST.csv`/`RECONSTRUCT.ps1`/etc. is real data (regression B6).
  Never filter data files by bare name.
- **Content-addressed data filenames carry the storage extension**: `.7z` when compressed,
  in *both* Mirror and HashAddressed modes, so `Compressed` and the filename agree.

## 4. Conventions & known gotchas

- **PowerShell 7+ only** (`pwsh`). Do not reintroduce 5.1 support — the hashing dependency's
  Desktop build needs transitive `System.Memory` assemblies.
- **Hashing:** xxHash128 via `System.IO.Hashing` (XXH3-based; faster than XXH64). **Not**
  K4os.Hash.xxHash — its 1.0.8 (final) release has no `XXH128` type. Use `Get-FileXxHash`.
- **Never `Split-Path -LiteralPath … -Parent` / `-Leaf`** — that flag combination *throws*
  on PS7. Use `[System.IO.Path]::GetDirectoryName/GetFileName` (also wildcard-safe for
  bracketed paths). Positional `Split-Path $x -Parent` is fine.
- A function that returns `@()` yields `$null` when captured — collection params that may
  receive that need `[AllowNull()][AllowEmptyCollection()]` and a null→`@()` guard.
- Use `-LiteralPath` for file ops (paths may contain `[]`, `()`, Unicode).
- `$ErrorActionPreference = 'Stop'` at script top.
- Approved PowerShell verbs (`Get-Verb`); export new functions from the module's
  `Export-ModuleMember`.
- `Write-Host` is fine (this is a CLI/automation tool) — excluded in lint settings.

## 5. Build / verify

```powershell
# deps + test tooling (System.IO.Hashing, Pester 5, PSScriptAnalyzer)
pwsh -File tests\Setup.ps1 -InstallDeps -InstallTestTools

# lint (must be clean) — settings live in tests/PSScriptAnalyzerSettings.psd1
Get-ChildItem -Recurse -Include *.ps1,*.psm1 -Path FileBackup.ps1,Reconstruct.ps1,Modules,tests |
    ForEach-Object { Invoke-ScriptAnalyzer -Path $_.FullName -Settings tests\PSScriptAnalyzerSettings.psd1 }

# unit (Pester 5)
Invoke-Pester -Path tests\Unit -Output Detailed

# integration (Subst backend; no admin)
.\RunAllTests.bat
```

A change to engine/restore code must keep **all 160 integration assertions + 27 unit tests
green and lint clean**, and add/adjust a test alongside any behavior change.

## 6. Test matrix

### Axes
| Axis | Values |
|---|---|
| PowerShell edition | pwsh 7+ (only; 5.1 unsupported) |
| Storage mode × compression | `Mirror`, `Mirror+Compress`, `HashAddressed`, `HashAddressed+Compress` |
| Hash-recalc freq | `A E D W M Y N` (unit-covered, G6 / `Engine.Tests.ps1`) |
| Backend (volumes) | `Subst` (CI), `VHDX` (virtual disks), `RealUSB` (hardware) |
| Suite group | G1–G8 |
| Filesystem (hardware) | NTFS, exFAT, FAT32 (>4 GB limit) |

### Coverage — ✅ automated · 🟡 self-hosted/manual · ⛔ N/A
| | Subst (hosted CI) | VHDX (self-hosted) | RealUSB (hardware) |
|---|:---:|:---:|:---:|
| Lint / Unit                  | ✅ | — | — |
| G1–G5, G7 × 4 modes          | ✅ | 🟡 | 🟡 |
| G6 HashFrequency (7 codes)   | ✅ | ✅ | ✅ |
| G8 RealVolume                | ⛔ SKIP | ⛔ SKIP | 🟡 |
| NTFS free-space / capacity   | — | 🟡 | 🟡 |
| exFAT / FAT32 + >4 GB file   | — | — | 🟡 |
| Standalone restore (no repo) | ✅¹ | 🟡 | 🟡 |

¹ `RECONSTRUCT.ps1` runs from the backup folder using only bundled files; a "copy backup
elsewhere, restore, byte-compare" check is part of the hardware runbook.

**Current automated total:** 212 integration assertions (4 modes × G1–G7 = 160, plus
G9 Rollback = 52; G8 SKIP under Subst) + 42 Pester unit/coverage tests, all green; lint clean.

### Suite groups
| Group | Covers |
|---|---|
| G1 InitialBackup  | Empty source, single file, 200-file bulk, nested `MANIFEST.csv` (B6), Unicode, bracketed paths. |
| G2 Incremental    | Rename, move, modify, delete, re-add identical/different, dedup. |
| G3 Reconstruction | Roundtrip from backup root, hash-fallback (incl. compressed), target-inside-backup rejected. |
| G4 Sanitization   | Mirror → HashAddressed migration; `StoredAsHashSize` flips. |
| G5 EdgeCases      | Stale `Temp` aborts, read-only source, idempotent second run. |
| G6 HashFrequency  | `Test-HashRecalcDue` over all 7 codes (deterministic via `-Now`). |
| G7 Determinism    | Identical re-runs ⇒ identical manifest rows; SHA-256 spot check. |
| G8 RealVolume     | USB-only sanity; SKIPs under Subst/VHDX. |
| G9 Rollback       | Dated-snapshot timeline (injected `-BackupTime`): modify/delete/add/no-op over D1–D4; restore as-of each snapshot + latest, byte-exact; mixed content (text/binary/dup/already-compressed); no snapshot for the no-op/latest run. SR-005/SR-010/SR-028. |

### Backends
| Backend | Provisioning | Admin? | CI? |
|---|---|---|---|
| Subst   | `subst` over `%TEMP%` on dynamically-chosen free drive letters | no | yes |
| VHDX    | Dynamic VHDX files mounted as letters (NTFS) | yes | self-hosted only |
| RealUSB | Resolves four `FBTEST-*` labels from `tests\Config\real-volumes.json` | no* | no |

\* Only the initial partitioning (`Setup-USB.bat`) needs admin. The harness refuses any
label not matching `FBTEST-*`, so it can't touch a production volume.

### Environments
- **GitHub `windows-latest` (pwsh)** — `.github/workflows/tests.yml`: `lint` →
  PSScriptAnalyzer; `unit` → Pester (NUnit published); `integration-subst` → all 4 modes,
  JUnit published. 7-Zip ships on the runner; `System.IO.Hashing` is installed + cached.
- **Self-hosted VHDX** — gated by repo var `HAS_SELF_HOSTED_HYPERV == 'true'` on a
  `[self-hosted, windows, hyper-v]` runner. `RunAllTests.bat VHDX`.
- **Hardware (RealUSB) runbook** — `Setup-USB.bat` (wipes a USB, makes four GPT/NTFS
  `FBTEST-*` partitions, drops `real-volumes.json`), then `RunAllTests.bat RealUSB`. For
  filesystem coverage, reformat the backup partition exFAT/FAT32 and re-run; on FAT32 check
  the >4 GB single-file limit surfaces cleanly. Finally copy a produced backup folder to a
  machine without this repo, run `RECONSTRUCT.bat`, and byte-compare.

## 7. Auxiliary & legacy scripts — standalone, don't fold into the engine

These are **personal/ad-hoc utilities, not part of the FileBackup engine**. They use
hardcoded drive paths, **SHA256 `Get-FileHash`** (not xxHash128), and a separate
`*HashTable.csv` schema. They were deliberately **not** modularized into
`FileBackup.Common`: doing so would change their hash algorithm and break their existing
data for no real benefit. Comment/extend them in place; do not couple them to the engine.

| Path | What it does |
|---|---|
| `Auxilary/7z-CreateMultipleArchivesFromDirectory.ps1` | Split a tree into ~equal-size groups, one `.7z` + report per group. |
| `Auxilary/CompressAllSubfolders.ps1` | One `.7z` per immediate subfolder. |
| `Auxilary/MoveDupFilesOnHashOrName.ps1` | Quarantine likely-dupes by date/hash/name against hash-table CSVs. |
| `Auxilary/RenameInvalidFiles.ps1` | Strip `% #`, turn `_`→space in names (in place, no preview). |
| `DatabaseDuplicateDeletion/ListPotDupFilesFromDatabase.ps1` | Step 1: size-collide + SHA256 the candidates. |
| `DatabaseDuplicateDeletion/CreateDelListFromDupDatabase.ps1` | Step 2: choose which dup copies to delete. |
| `DatabaseDuplicateDeletion/RemoveAllFilesFromList.ps1` | Step 3: **DESTRUCTIVE** — delete every file in the list. |

**Legacy (superseded, kept for reference — do not extend):** `Test-Backup.ps1`,
`RunTests.bat`, `TestRelated/FileBackupTestReset.ps1`, `PrepPropertiesFile.ps1`. Add test
coverage in `tests/`, and build configs with `CredSetEx.ps1`.

## 8. History

The first real review of this tool found it had **never actually run** (commits were tagged
"UNTESTED"). The modularization pass made it work and fixed the catalogued bugs.

### Dependency & parser defects (discovered during the work)
- **Hashing was non-functional**: the code called `K4os.Hash.xxHash.XXH128`, a type that
  does not exist in K4os 1.0.8. Switched to `System.IO.Hashing.XxHash128` (XXH3-based,
  benchmarked faster than XXH64). PS7+ now required.
- **`Split-Path -LiteralPath … -Parent` throws on PS7** (it was on line 35 of the test
  runner, so the suite couldn't start). Replaced everywhere with `[System.IO.Path]` calls.
- **Reconstruct generation was unrunnable** — it prepended assignments before `param()`.
  Now uses a `RECONSTRUCT.paths.json` sidecar; the script is copied verbatim.
- **`Write-Manifest` used the invalid `[IEnumerable[object]]` accelerator** → `[object[]]`
  with null/empty tolerance.
- **Mirror+Compress wrote `.7z` bytes without a `.7z` extension** (so the name lied and
  hash-recovery couldn't detect compression) → fixed.
- **Change-folder names could collide** within the same second → collision-safe naming.

### Catalogued review bugs fixed
B2 (`MinValue` = never run, injectable `-Now`), B3 (persisted last-hash-run in
`FileBackupState.json`), B4 (scheduled rehash actually forces a rehash), B6 (nested
`MANIFEST.csv` preserved), B7 (migrate copies + writes manifest *before* deleting old —
crash-safe), B8 (`@()` before indexing), B9 (refcount shared data on eviction), B10/B11
(reconstruct layout + capacity check on compressed rows), B15 (mail optional + `-NoMail`),
B16 (`Test-ShouldCompress` param rename), B17 (`PrepPropertiesFile.ps1` marked legacy).

### Modularization & tests
- Split the monolith into `Common` + `Engine`; thin `FileBackup.ps1`/`Reconstruct.ps1`
  entry points; approved-verb renames (`Run-BackupSet`→`Invoke-BackupSet`,
  `Should-RecalculateHashes`→`Test-HashRecalcDue`, `CalculateFileHash`→`Get-FileXxHash`,
  `GenerateReconstructScript`→`New-ReconstructScript`, `SanitizeBackupDatabase`→
  `Sync-BackupStorageLayout`, `SanitizeChangeDatabase`→`Optimize-ChangeFolders`, …).
- Reconstruct now bundles the Common module + DLL and can hash-recover compressed `.7z`
  data files.
- New modular harness (Subst picks free drive letters), Pester unit suite, lint settings,
  and CI lanes (lint + unit + Subst integration).

### Docs
Consolidated into exactly two files — `README.md` (setup & use) and this `AGENTS.md`
(architecture, invariants, tests, history). The earlier `IMPLEMENTATION_SUMMARY.md`,
`CHANGES.md`, `CHANGELOG.md`, `TEST_MATRIX.md`, and `tests/README.md` were folded in here.
