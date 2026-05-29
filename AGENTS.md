# AGENTS.md — working in this repo

Guidance for AI agents and contributors. Read this before changing engine or restore code.

## What this is

A Windows **PowerShell 7+** content-aware backup tool. `FileBackup.ps1` (entry point)
walks a source tree, hashes files with xxHash128, deduplicates by `(hash, size)`,
optionally 7-Zip-compresses, and records everything in `MANIFEST.csv`. Each run snapshots
prior versions into a `Pre_<timestamp>_NNNNNN_Changes` folder and drops a self-contained
restore kit. `Reconstruct.ps1` rebuilds the tree from a backup/change folder alone.

## Module map

| File | Role | Deployed into backups? |
|---|---|---|
| `Modules/FileBackup.Common.psm1` | Restore-safe primitives: `Get-FileXxHash`, `Initialize-XxHashLibrary`, `Get-XxHashDllPath`, `Read-/Write-Manifest`, `Compress-/Expand-FileWithSevenZip`, `Test-ShouldCompress`, short-name encoding, `New-Logger`, `Get-FileBackupDefaults`. | **Yes** |
| `Modules/FileBackup.Engine.psm1` | Backup-only logic: `Update-SourceManifest`, `Compare-SourceToBackup`, `Invoke-BackupFileGroup`, `Sync-BackupStorageLayout`, `Optimize-ChangeFolders`, `Move-RemovedFilesToStaging`, `New-ReconstructScript`, `Complete-ChangeFolder`, `Invoke-BackupSet`, `Test-HashRecalcDue`, … | No |
| `FileBackup.ps1` | Thin: import modules, read config, loop `Invoke-BackupSet`, optional mail. | n/a |
| `Reconstruct.ps1` | Standalone restore; imports the bundled Common module. | itself |

**The Common/Engine split is load-bearing.** `New-ReconstructScript` copies
`Reconstruct.ps1`, `FileBackup.Common.psm1`, `System.IO.Hashing.dll`, and a
`RECONSTRUCT.paths.json` sidecar into each backup folder so a restore needs nothing else.
Anything `Reconstruct.ps1` calls must live in **Common**, not Engine. Do not make Common
depend on Engine.

## Invariants — do not break

- **Manifest schema** (9 columns): `DataPath, RelativePath, Length, LastWriteTimeStr,
  xxH2Hash, Compressed, StoredAsHashSize, Duplicate, MediaMBPerSec`. Round-trip via
  `Read-Manifest`/`Write-Manifest` only.
- **Dedup key is `(xxH2Hash, Length)`.** Same key ⇒ one physical data file.
- **Change-folder name** matches `^Pre_\d{4}_\d{2}_\d{2}_\d{2}_\d{2}_\d{2}_.*_Changes$`.
  Keep that shape (the `.*` tail absorbs the count + collision disambiguator).
- **Reconstruct must stay standalone** — no repo, no NuGet install at restore time.
- **Infrastructure files are root-level only** (`Test-IsInfrastructureFile`): a nested
  user file named `MANIFEST.csv`/`RECONSTRUCT.ps1`/etc. is real data (B6). Never filter
  data files by bare name.
- **Content-addressed data filenames carry the storage extension**: `.7z` when compressed,
  in *both* Mirror and HashAddressed modes, so `Compressed` and the filename agree.

## Conventions

- PowerShell **7+ only** (`pwsh`). Do not reintroduce Windows PowerShell 5.1 support; the
  hashing dependency's Desktop build needs transitive `System.Memory` assemblies.
- xxHash128 via `System.IO.Hashing` — **not** K4os (which has no XXH128). Use
  `Get-FileXxHash`.
- **Never use `Split-Path -LiteralPath … -Parent/-Leaf`** — that parameter combination
  throws on PS7. Use `[System.IO.Path]::GetDirectoryName/GetFileName` (also wildcard-safe).
- Use `-LiteralPath` for file ops (paths may contain `[]` / `()` / Unicode).
- `$ErrorActionPreference = 'Stop'` at script top; collection params that may receive a
  captured `@()` need `[AllowNull()][AllowEmptyCollection()]`.
- Approved PowerShell verbs (`Get-Verb`). New functions: export them from the module's
  `Export-ModuleMember` list.
- `Write-Host` is fine here (CLI tool); it's excluded in the lint settings.

## Build / verify commands

```powershell
# deps + test tooling
pwsh -File tests\Setup.ps1 -InstallDeps -InstallTestTools

# lint (must be clean)
Invoke-ScriptAnalyzer -Path Modules\FileBackup.Engine.psm1 -Settings tests\PSScriptAnalyzerSettings.psd1

# unit (Pester 5)
Invoke-Pester -Path tests\Unit

# integration (Subst; no admin)
.\RunAllTests.bat
```

A change to engine/restore logic should keep **all 160 integration assertions + 27 unit
tests green and lint clean.** Add or update a suite/unit test alongside any behavior
change. See [TEST_MATRIX.md](TEST_MATRIX.md) for coverage and [CHANGELOG.md](CHANGELOG.md)
for the fix history.

## Legacy / do not extend

`Test-Backup.ps1`, `RunTests.bat`, and `TestRelated/` predate the `tests/` harness and are
kept only for reference. Add coverage in `tests/`, not there. `PrepPropertiesFile.ps1` is a
legacy config builder — use `CredSetEx.ps1` for the current CLIXML schema.
