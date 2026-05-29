# Changelog

All notable changes to FileBackup. This file consolidates the earlier
`IMPLEMENTATION_SUMMARY.md` and `CHANGES.md` refactor notes.

## [Unreleased] — Modularization, real hashing, and a green test suite

This pass made the tool **actually run** for the first time (prior commits were tagged
"UNTESTED"), modularized the codebase, and fixed the catalogued bugs. PowerShell **7+**
is now required.

### Architecture
- Split the monolithic `FileBackup.ps1` into modules:
  - `Modules/FileBackup.Common.psm1` — restore-safe primitives (hashing, manifest I/O,
    7-Zip compress/expand, short-name encoding, logging, shared defaults). Bundled into
    every backup folder.
  - `Modules/FileBackup.Engine.psm1` — the backup engine (source walk, diff, dedup copy,
    storage-layout migration, change folders, reconstruct generation, `Invoke-BackupSet`).
- `FileBackup.ps1` and `Reconstruct.ps1` are now thin entry points that import the modules.
- Functions renamed to approved PowerShell verbs (e.g. `Run-BackupSet`→`Invoke-BackupSet`,
  `UpdateSourceDatabase`→`Update-SourceManifest`, `Should-RecalculateHashes`→
  `Test-HashRecalcDue`, `CalculateFileHash`→`Get-FileXxHash`, `GenerateReconstructScript`→
  `New-ReconstructScript`, `SanitizeBackupDatabase`→`Sync-BackupStorageLayout`,
  `SanitizeChangeDatabase`→`Optimize-ChangeFolders`).

### Fixed — dependency & parser defects (discovered during this work)
- **xxHash was non-functional.** The code referenced `K4os.Hash.xxHash.XXH128`, but that
  type does not exist in K4os.Hash.xxHash 1.0.8 (its newest release ships only XXH32/64).
  Replaced with Microsoft's `System.IO.Hashing.XxHash128` (XXH3-based; benchmarked
  *faster* than XXH64). `Get-FileXxHash` now produces real 128-bit hashes.
- **`Split-Path -LiteralPath … -Parent` throws** on PowerShell 7 (`-Parent`/`-Leaf` are
  not in the `-LiteralPath` parameter set). Replaced every occurrence with
  `[System.IO.Path]::GetDirectoryName/GetFileName` (also wildcard-safe for bracketed paths).
- **Reconstruct generation produced an unrunnable script** — it prepended
  `$BackupRootOverride = …` lines *before* the `param()` block. Paths are now passed via a
  `RECONSTRUCT.paths.json` sidecar; the script is copied verbatim.
- **`Write-Manifest` declared `[IEnumerable[object]]`**, which is not a valid type
  accelerator. Now `[object[]]` with null/empty tolerance (a function returning `@()`
  yields `$null` when captured).
- **Mirror + compression wrote `.7z` bytes to a file with no `.7z` extension**, so
  `Compressed=Yes` but the name lied and hash-recovery couldn't detect it. Fixed to append
  `.7z`, matching `Sync-BackupStorageLayout`.
- **Change-folder names could collide** when two runs landed in the same second. Naming is
  now collision-safe (appends a disambiguator).

### Fixed — catalogued review bugs
- **B2** `Test-HashRecalcDue` treats `DateTime.MinValue` as "never run"; added an
  injectable `-Now` for deterministic testing.
- **B3** Last-hash-run time is persisted in `FileBackupState.json`, no longer inferred from
  source mtimes.
- **B4** The scheduled-rehash decision now actually forces a rehash (`-ForceRehash`).
- **B6** Only the *root* `MANIFEST.csv` is skipped during the source walk; nested files
  named `MANIFEST.csv` are backed up (see `Test-IsInfrastructureFile`).
- **B7** Storage migration copies new files and writes the manifest *before* deleting old
  files (crash-safe ordering).
- **B8** Hash-group lookups are wrapped with `@()` before indexing.
- **B9** Removed-file eviction refcounts shared data files; a file still referenced by a
  surviving entry stays in place (reconstruct recovers it by hash).
- **B10** Standalone `Reconstruct.ps1` no longer assumes a `CHANGES\` sibling; uses the
  sidecar/override or true layout.
- **B11** Reconstruct's capacity pre-check excludes compressed rows (their uncompressed
  lengths over-/under-state the need) and notes this in the log.
- **B15** `Send-MailMessage` runs only when SMTP is configured; added `-NoMail`. Failures
  are logged, not fatal.
- **B16** `Test-ShouldCompress` parameter renamed `$FileName` (extension-only use).
- **B17** `PrepPropertiesFile.ps1` documented as legacy; points to `CredSetEx.ps1` for the
  current schema.

### Features (completed from prior stubs)
- Decompression on restore and during storage migration (`Expand-FileWithSevenZip`).
- Hash-based recovery in `Reconstruct.ps1`, now able to decompress `.7z` candidates so it
  works for compressed backups.
- Safe switching between storage modes (Mirror ↔ HashAddressed, compress on/off) via
  `Sync-BackupStorageLayout`.

### Tests & tooling
- New modular harness sweeps **4 storage modes × G1–G8** across Subst / VHDX / RealUSB
  backends; **160 integration assertions pass** under the Subst backend (G8 SKIPs).
- Subst backend now picks free drive letters dynamically (no X/Y/Z/W collision on dev
  machines).
- New Pester 5 unit suite (`tests/Unit`, **27 tests**) for the pure functions.
- `PSScriptAnalyzer` lint is clean against `tests/PSScriptAnalyzerSettings.psd1`.
- CI runs lint + unit + the Subst integration suite on `windows-latest` under `pwsh`.

### Removed
- `IMPLEMENTATION_SUMMARY.md`, `CHANGES.md` (folded into this changelog).
- `RUN_TESTS_README.md` (moved to `tests/README.md`).
