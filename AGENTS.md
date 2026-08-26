# AGENTS.md — contributor & agent guide

Everything needed to safely modify FileBackup. Users who just want to run it should read
[README.md](README.md); this file is the single source for architecture, invariants,
conventions, the test matrix, and history.

---

## 1. What this is

A Windows **PowerShell 7+** content-aware backup tool. `FileBackup.ps1` walks a source
tree, hashes files with xxHash128 (`System.IO.Hashing`), deduplicates by `(hash, size)`,
optionally 7-Zip-compresses, and records `MANIFEST.csv`. A run that supersedes earlier
content preserves it in a dated `Snapshot_<date>` folder (named by the superseded backup's
completion date — see §3) and drops a self-contained restore kit. `Reconstruct.ps1`
rebuilds the tree byte-exact from the backup root (latest state) or any snapshot
(that point in time) alone.

## 2. Architecture & module map

| File | Role | Bundled into backups? |
|---|---|---|
| `Modules/FileBackup.Common.psm1` | **Restore-safe primitives**: `Get-FileXxHash`, `Initialize-XxHashLibrary`, `Get-XxHashDllPath`, `Read-/Write-Manifest`, `Compress-/Expand-FileWithSevenZip`, `Test-ShouldCompress`, short-name encoding, `New-Logger`, `Get-FileBackupDefaults`, `Get-FreeSpaceBytes`/`Get-VolumeIdentity` (SR-052 — both restorer and engine measure capacity through these). | **Yes** |
| `Modules/FileBackup.Engine.psm1` | **Backup-only logic**: `Update-SourceManifest`, `Compare-SourceToBackup`, `Invoke-BackupFileGroup`, `Test-BackupManifest`, `Get-BackupContentIndex`, `Optimize-ChangeFolders`, `Move-RemovedFilesToStaging`, `New-ReconstructScript`, `Complete-ChangeFolder`, `Invoke-BackupSet`, `Test-HashRecalcDue`, `Test-IsInfrastructureFile`, `Assert-BackupCapacity` (+ its two pure demand estimators), … plus the **retention mechanism** (SR-045..047): `Get-SnapshotPrunePlan`, `Get-BackupSnapshot`, `Assert-PrunePrecondition`, `Get-PruneCapacityRefusal`, `Test-PoolResolves`, `Copy-ReHomedDataFile`, `Publish-PruneManifest`, `Remove-CommittedPruneResidue`, `Invoke-PruneEntrySweep`, `Complete-PruneDeletion`, `Remove-BackupSnapshot`; and the **storage-form audit** (SR-049): `Get-StoredFileForm`, `Test-StorageFormAgreement`, `Get-StorageFormFinding`, `Get-BackupKitRevision`, `Test-BackupStorageForm`, `Repair-BackupStorageForm`, `Update-BackupSnapshotKit`; and the **browse view** (SR-062): `New-BrowseViewIndex`. | No |
| `FileBackup.ps1` | Thin entry point: import modules, read config, then either loop `Invoke-BackupSet` (+ optional mail) or, under `-Action Prune`/`-Action Snapshots` (SR-048) / `-Action Verify` (SR-049) / `-Action View` (SR-062), dispatch the one configured set to the retention mechanism, the storage-form audit or a forced browse-view rebuild. | n/a |
| `Reconstruct.ps1` | Standalone restore; imports the **bundled** Common module. | itself |
| `bash/reconstruct.sh` | **Linux/bash standalone restore** (phase `bash-v1`): one self-contained POSIX-shell file (bash 4+, gawk, xxhsum, 7z) that restores byte-exact from a backup folder on a host with no PowerShell, mirroring `Reconstruct.ps1`'s semantics against the *same* MANIFEST.csv contract. It is **not** in the generated map below (that map is PowerShell-AST-only); its internal functions (`hash_file`, `parse_manifest`, `to_posix`) are unit-tested by sourcing it under bats. See §4 for the tooling floor and README "Restore on Linux". | **Yes** |
| `Dockerfile`, `container/`, `scripts/Invoke-Container.ps1` | **Linux container runtime and lifecycle** (phase `container-v1`): digest-pinned non-root image, JSON configuration entrypoint, compressed build/restore smoke test, offline tar export, and optional OCI registry publish/pull. | n/a |

**The Common/Engine split is load-bearing.** `New-ReconstructScript` copies
`Reconstruct.ps1`, `reconstruct.sh`, `FileBackup.Common.psm1`,
`System.IO.Hashing.dll`, and a `RECONSTRUCT.paths.json` sidecar into each backup
folder so a restore needs nothing else. A backup folder additionally holds
`MANIFEST.csv.meta` — the SR-038 manifest witness — which is **not** a copied kit
artifact: `Write-Manifest` stamps each folder's own (see §3).
Therefore:

- Anything `Reconstruct.ps1` calls **must live in Common**, not Engine.
- **Common must never depend on Engine.**

### Backup pipeline (`Invoke-BackupSet`, per set, per run)
1. Resolve `SourcePath`/`BackupPath`/`ChangePath` (+ `ViewPath` when the set asks
   for a browse view — SR-062/SR-063 place it outside both roots, on the backup
   volume).
1.5 The SR-038/SR-039 manifest-witness gate: refuse with exit 3 before any mutation.
2. Open `backup.log` in the change root.
3. Guard against a stale `Temp` staging folder.
4. Read persisted last-hash-run time; decide if a scheduled rehash is due.
5. `Update-SourceManifest` — walk source, (re)hash new/changed/scheduled files.
5.1 Portable-name guard (SR-055): a source name the restore side could not
    reproduce FREEZES that row instead of storing it.
5.2 Unreadable-directory guard (SR-057): rows under a directory the walk could
    not enumerate freeze too, and the set fails loudly rather than silently
    treating them as removed.
6. `Test-BackupManifest` — sanitize the backup manifest: blank a missing
   `DataPath` (SR-053's heal then re-copies it) and warn about unreferenced pool
   files. **There is no layout migration** (SR-061) — nothing already stored is
   ever re-formed, so this step needs no capacity preflight of its own, and this
   is the store's ONLY orphan scan, linear in rows + pool files (SR-064).
7. Snapshot the pre-run manifest into staging (the point-in-time index).
8. `Compare-SourceToBackup` — pure diff (`NewOrChanged` + `RemovedFromSource`).
9. Build the working backup map.
9.4 `Assert-BackupCapacity` — the last point at which nothing has been written.
    A refusal removes the staging folder and fails the SET (status 1), never
    orphaning a `Temp` for the next run's SR-017 guard.
10. `Invoke-BackupFileGroup` per `(hash,size)` — write ONE content-addressed
    object per group (SR-058/SR-060): the group elects an owner whose extension
    and compressibility decide the single physical form, the first member writes
    it, and an in-process memo makes every later member of the same run adopt it.
11. `Move-RemovedFilesToStaging` — evict removed files' data (refcount-aware).
11.5 `Save-SupersededData` — preserve superseded prior bytes into staging. It runs
    AFTER the copy/evict steps, because content addressing never overwrites an
    existing object, and asks the exact question: does any row of the FINAL
    manifest still claim the old object (SR-059/SR-051)? The pre-WP9
    source-based approximation could not see a frozen row or a row whose copy
    failed, and moved out bytes they still claimed — that was D-1's family.
12. Write the final backup manifest, **canonically**: rows in ordinal
    `RelativePath` order, every text column materialized as a string, so an
    unchanged run rewrites byte-identical bytes (G7).
13. `New-ReconstructScript` + `Complete-ChangeFolder` — finalize the staging into a
    dated `Snapshot_<prior-backup-date>`, or discard it when nothing was superseded.
    The kit is copied into staging BEFORE the publish rename, so a `Snapshot_*`
    folder structurally cannot exist without its restore kit (F8).
14. `Optimize-ChangeFolders` — collapse data shared across snapshots.
15. Persist `LastHashRun` (if a rehash ran) + `LastBackupRun` (this run's date).
16. Browse view (SR-062), only when `BrowseView` is `index` and the `.viewstamp`
    is stale. A failure here is a WARNING, never a set failure — the view is
    cosmetic by construction and nothing in the engine or the restorers reads it.

### Generated dependency diagram & function map

The table above is the hand-kept editorial overview; the regions below are
**generated from the source AST** by `scripts/gen_arch_map.ps1` (the Mermaid
call-graph between modules/entry scripts, then per-module summary, internal
cross-module dependencies, and every function with its `Implements:` back-links).
Do not edit them by hand — `check.ps1` fails if they are stale. The same blocks
are mirrored in [docs/architecture.md](docs/architecture.md), which also carries
the generated `Invoke-BackupSet` flow.

<!-- BEGIN GENERATED DEPENDENCY DIAGRAM -->
_Generated by `scripts/gen_arch_map.ps1`: each arrow is a call into another
in-tree module. An arrow from `Common` into `Engine`, or from `Reconstruct.ps1`
into `Engine`, would violate the AGENTS.md §3 invariants. Do not edit by hand._

```mermaid
graph LR
    n_Common["Common — FileBackup shared core — restore-safe primitive…"]
    n_Engine["Engine — FileBackup engine — everything needed to *produ…"]
    n_FileBackup_ps1(["FileBackup.ps1 — Periodic content-aware backup with change track…"])
    n_Reconstruct_ps1(["Reconstruct.ps1 — Reconstructs a source tree from MANIFEST.csv an…"])
    n_Engine --> n_Common
    n_FileBackup_ps1 --> n_Common
    n_FileBackup_ps1 --> n_Engine
    n_Reconstruct_ps1 --> n_Common
```
<!-- END GENERATED DEPENDENCY DIAGRAM -->

<!-- BEGIN GENERATED MODULE MAP -->
_Generated by `scripts/gen_arch_map.ps1` from the modules' AST. Do not edit by hand;
run the generator. Summary = the module's .SYNOPSIS; back-links come from `Implements:` comments._

### `Modules/FileBackup.Common.psm1`

_FileBackup shared core — restore-safe primitives._
Imports (internal): _none_

| Function | Exported | Implements |
|---|:---:|---|
| `Compress-FileWithSevenZip` | yes | SR-004, LLR-004 |
| `Convert-HexToShortName` | yes | SR-003, LLR-003 |
| `Convert-ShortNameToHex` | yes | — |
| `ConvertFrom-ManifestDateString` | yes | — |
| `ConvertTo-ManifestDateString` | yes | SR-025, LLR-025 |
| `Expand-FileWithSevenZip` | yes | SR-008, LLR-008 |
| `Get-FileBackupDefaults` | yes | — |
| `Get-FileXxHash` | yes | SR-002, LLR-002 |
| `Get-FreeSpaceBytes` | yes | SR-052, SR-023, LLR-052, LLR-023 |
| `Get-HashSizeFileName` | yes | SR-003, SR-021, LLR-003, LLR-021 |
| `Get-ManifestWitnessPath` | yes | SR-038, LLR-038 |
| `Get-VolumeIdentity` | yes | SR-052, LLR-052 |
| `Get-XxHashDllPath` | yes | SR-007, LLR-007 |
| `Initialize-XxHashLibrary` | yes | SR-002, SR-019, LLR-002 |
| `New-Logger` | yes | — |
| `New-RelativePathMap` | yes | SR-034, LLR-034 |
| `Read-Manifest` | yes | SR-025, LLR-025 |
| `Resolve-ExistingAncestor` | yes | SR-052, SR-023, LLR-052 |
| `Test-ManifestWitness` | yes | SR-039, LLR-039 |
| `Test-ShouldCompress` | yes | SR-004, LLR-004 |
| `Write-Manifest` | yes | SR-025, SR-038, LLR-025, LLR-038 |
| `Write-ManifestWitness` | yes | SR-038, LLR-038 |

### `Modules/FileBackup.Engine.psm1`

_FileBackup engine — everything needed to *produce* a backup._
Imports (internal): `Common`

| Function | Exported | Implements |
|---|:---:|---|
| `Assert-BackupCapacity` | yes | SR-052, SR-013, SR-014, LLR-052 |
| `Assert-NoUnknownConfigKey` | no | SR-042, LLR-042 |
| `Assert-PrunePrecondition` | yes | SR-046, SR-035, SR-039, LLR-046 |
| `Compare-SourceToBackup` | yes | SR-001, SR-053, LLR-001, LLR-053 |
| `Complete-ChangeFolder` | yes | SR-005, SR-028, LLR-005, LLR-028 |
| `Complete-PruneDeletion` | yes | SR-046, LLR-046 |
| `Copy-ReHomedDataFile` | yes | SR-045, LLR-045 |
| `Copy-SourceFileToBackup` | yes | SR-003, LLR-003 |
| `Get-BackupCapacityDemand` | yes | SR-052, SR-013, LLR-052 |
| `Get-BackupContentIndex` | yes | SR-026, SR-045, SR-047, LLR-047 |
| `Get-BackupKitRevision` | yes | SR-049, LLR-049 |
| `Get-BackupSnapshot` | yes | SR-047, LLR-047 |
| `Get-ConfigValueJsonTypeName` | no | SR-042, LLR-042 |
| `Get-DataFile` | yes | SR-057, LLR-057 |
| `Get-LastBackupRun` | yes | SR-005, SR-028, LLR-005, LLR-028 |
| `Get-LastHashRun` | yes | SR-011, LLR-011 |
| `Get-MediaMBPerSec` | yes | SR-020, LLR-020 |
| `Get-PoolSnapshotFolder` | yes | SR-045, LLR-045 |
| `Get-PruneBatchExitCode` | yes | SR-040, SR-046, SR-048, LLR-046, LLR-048 |
| `Get-PruneCapacityRefusal` | yes | SR-046, SR-052, LLR-046 |
| `Get-ReHomedDataPathName` | no | SR-045, LLR-045 |
| `Get-SnapshotDate` | no | SR-047, LLR-047 |
| `Get-SnapshotPrunePlan` | yes | SR-045, SR-047, LLR-045, LLR-047 |
| `Get-StorageFormFinding` | yes | SR-049, LLR-049 |
| `Get-StoredFileForm` | yes | SR-049, LLR-049 |
| `Import-BackupConfiguration` | yes | SR-042, LLR-042 |
| `Initialize-Dependencies` | yes | SR-019 (required dep), SR-020 (optional deps), SR-016 (non-blocking) |
| `Initialize-StagingFolder` | yes | SR-005, SR-017, LLR-005, LLR-017 |
| `Invoke-BackupFileGroup` | yes | SR-003, SR-013, SR-053, SR-058, SR-060, LLR-003, LLR-053, LLR-058 |
| `Invoke-BackupSet` | yes | SR-014, SR-017, SR-035, SR-036, SR-055, LLR-014, LLR-017, LLR-035, LLR-036, LLR-055 |
| `Invoke-PruneEntrySweep` | yes | SR-046, LLR-046 |
| `Move-RemovedFilesToStaging` | yes | SR-006, SR-041, LLR-006, LLR-041 |
| `New-BrowseViewIndex` | yes | SR-062, LLR-061 |
| `New-ReconstructScript` | yes | SR-007, LLR-007 |
| `Optimize-ChangeFolders` | yes | SR-026, LLR-026 |
| `Publish-PruneManifest` | yes | SR-045, SR-038, LLR-045 |
| `Read-BackupState` | no | SR-011, SR-028, LLR-011, LLR-028 |
| `Remove-BackupSnapshot` | yes | SR-045, SR-046, SR-040, LLR-045, LLR-046 |
| `Remove-CommittedPruneResidue` | yes | SR-046, LLR-046 |
| `Repair-BackupStorageForm` | yes | SR-049, SR-024, SR-038, LLR-049 |
| `Resolve-BackupSetDefaults` | no | SR-042, LLR-042 |
| `Resolve-BackupSetPaths` | yes | SR-014, SR-049, SR-063, LLR-014, LLR-063 |
| `Resolve-OptionalTool` | yes | SR-020 (optional-dependency degradation), SR-016 (non-blocking) |
| `Resolve-ViewRootPath` | no | SR-063, LLR-063 |
| `Save-SupersededData` | yes | SR-010, SR-028, SR-041, SR-059, LLR-010, LLR-028, LLR-041, LLR-059 |
| `Set-BackupStateField` | no | — |
| `Set-LastBackupRun` | yes | SR-005, SR-028, LLR-005, LLR-028 |
| `Set-LastHashRun` | yes | SR-011, LLR-011 |
| `Test-BackupConfigurationShape` | no | SR-042, LLR-042 |
| `Test-BackupManifest` | yes | SR-061, SR-064, LLR-060, LLR-062 |
| `Test-BackupStorageForm` | yes | SR-049, SR-038, SR-040, SR-061, LLR-049, LLR-060 |
| `Test-ConfigValueJsonType` | no | SR-042, LLR-042 |
| `Test-HashRecalcDue` | yes | SR-011, LLR-011 |
| `Test-IsInfrastructureFile` | yes | SR-022, SR-038, LLR-022, LLR-038 |
| `Test-IsJsonNumber` | no | SR-042, LLR-042 |
| `Test-PoolResolves` | yes | SR-046, SR-045, LLR-046 |
| `Test-PortableRelativePath` | yes | SR-055, LLR-055 |
| `Test-StorageFormAgreement` | yes | SR-046, SR-049, LLR-046, LLR-049 |
| `Update-BackupSnapshotKit` | yes | SR-049, SR-007, SR-038, LLR-049 |
| `Update-SourceManifest` | yes | SR-001, SR-024, SR-055, LLR-001, LLR-024, LLR-055 |
<!-- END GENERATED MODULE MAP -->

## 3. Invariants — do not break

> **The 2026-08-24 bench defects are all CLOSED.** D-2 (restore trusted a
> resolvable `DataPath` without hashing), D-3 (exit-code misclassification) and
> D-4 (hidden/dot files never enumerated) were fixed in **kit revision 6**,
> 2026-08-24: both restorers verify every file they write against the row's
> `(Length, xxH2Hash)` and heal from the pool once (`ContentMismatch`, SR-056);
> an unexpandable **pool candidate** is content damage (exit 1), not a host
> problem; every PowerShell-side enumeration carries `-Force` (SR-057).
> **D-1 and D-5 were fixed by WP9 (2026-08-25) by deleting their hazard class:
> ALL storage is content-addressed, the Mirror/`PreserveFolderTree` layout is
> gone, and browsability is a generated view outside the backup root.** Records:
> [docs/defect-review-2026-08-24-mirror-dedup.md](docs/defect-review-2026-08-24-mirror-dedup.md)
> (the findings),
> [docs/plans/option3-content-addressed-storage-plan.md](docs/plans/option3-content-addressed-storage-plan.md)
> (the design ruling) and
> [docs/plans/wp9-content-addressed-storage-workorder.md](docs/plans/wp9-content-addressed-storage-workorder.md)
> (the implementation). The invariants below document the CURRENT code.

- **Manifest schema** (9 columns): `DataPath, RelativePath, Length, LastWriteTimeStr,
  xxH2Hash, Compressed, StoredAsHashSize, Duplicate, MediaMBPerSec`. Round-trip only via
  `Read-Manifest`/`Write-Manifest`.
- **Dedup key is `(xxH2Hash, Length)`** — one physical data file per key, across
  runs *and within a single run* (SR-003/SR-060). Where a group's members
  disagree about the stored form (different extensions, or one compressible and
  one not), the group **elects an owner** — shortest `RelativePath`, ordinal
  tie-break — and the owner's form is the one object every member references.
- **All storage is content-addressed** (SR-058): every data file is named
  `Get-HashSizeFileName(hash, length, ext)` — `"<hash16> <len10><ext>"` — flat at
  the backup root, and every row carries `StoredAsHashSize='Hash'` (SR-013).
  There is no path-addressed (Mirror) layout and no configuration key selects
  one. This is what makes the store safe rather than merely checked: **different
  content yields a different filename, so a stored object can never be
  overwritten in place.**
- **Stored objects are immutable and name-proven** (SR-059). No run changes the
  bytes at a `DataPath` any live manifest row still claims, and an object is only
  ever created at a name its own bytes justify. The two steps that remove bytes
  from the pool — `Move-RemovedFilesToStaging` and `Save-SupersededData` — both
  decide by the same question: does any row of the **final** manifest still claim
  this object (SR-051)? Testing survival against the *source walk* instead was
  D-1: it could not see a frozen row (SR-055/SR-057) or a row whose replacement
  copy had failed, and moved out bytes those rows still claimed.
- **Nothing already stored is ever re-formed** (SR-061). `CompressEnabled`
  governs only content written after the change; a mixed-form store is normal,
  because compression is per-file (SR-004) and every row's `Compressed` describes
  its OWN object. There is no storage-layout migration — a store whose manifest
  carries the legacy `StoredAsHashSize='Original'` fails its backup set before
  any mutation, naming the remedy (a fresh `BackupPath`), and is reported as a
  finding under `-Action Verify`. Reading a legacy store never breaks — only
  writing to one. That claim is regression-guarded for `Reconstruct.ps1`
  (`G4-Sanitization` `Legacy_storeStillRestores`); the bash twin's guard went
  with the Mirror fixtures at WP9 step 5b, so `reconstruct.sh`'s path-addressed
  branch is correct-by-reading but currently uncovered (WP9 review MIN-2, open
  in docs/status.md).
- **The browse view is cosmetic and lives outside both roots** (SR-062). When
  `BrowseView` is `index`, `New-BrowseViewIndex` writes `INDEX.tsv` plus
  per-folder `INDEX.html` pages under `ViewPath` (default `<BackupPath>_View`).
  **Nothing in the engine or either restorer reads it**, no `Snapshot_*` folder
  ever gets one, and a failure to generate it is a warning, never a failed
  backup. It replaces the only real value Mirror had — and is *more* faithful,
  because Mirror omitted borrower paths entirely.
- **Dated snapshots** (`Snapshot_<date>`, matching `^Snapshot_\d{4}_\d{2}_\d{2}_\d{2}_\d{2}_\d{2}`):
  one per *superseded* backup, named by that backup's completion date (persisted
  in `FileBackupState.json` as `LastBackupRun`). The **latest state has no
  snapshot** — the live backup root is it; a **no-op run creates none**. A snapshot
  holds the full point-in-time manifest plus only the bytes superseded at the next
  run (`Save-SupersededData` parks them there once no row of that run's final
  manifest still claims them — see the immutability invariant above).
  **Restore authority (SR-010):** reconstruct from a snapshot uses *that snapshot's
  own manifest* as the sole authority and resolves bytes by `(hash,length)` from
  the data pool (backup root + all snapshots) — it never overlays a newer manifest.
  Clean cutover: no `Pre_*_Changes` reading/writing remains (SR-005/SR-010/SR-028).
- **A `Snapshot_*` folder is removed only by `Remove-BackupSnapshot`** (SR-045/
  SR-046), never by deleting the directory — dedup means a snapshot can hold the
  only physical copy of content other snapshots recover by hash. The mechanism
  re-homes those last-copy bytes into the surviving pool (backup root if it
  demands the key, else the newest surviving snapshot that does), rewrites that
  destination's manifest **through `Write-Manifest`** — never copying a
  `MANIFEST.csv.meta` between folders — proves every surviving row still
  resolves with the target excluded, and only then commits by renaming to
  `Pruning_<name>` (which fails `^Snapshot_` for *both* restorers and Optimize,
  so one atomic rename removes it from every consumer's view) and deleting.
  Only `DataPath`/`Compressed`/`StoredAsHashSize` are ever edited, and only in
  planned rows. Resume is "run it again": no journal. Residue handling is split
  so a refusal never mutates — `Remove-CommittedPruneResidue` finishes only
  `Pruning_<the name being pruned>` before that name is planned (it is past the
  commit point and holds the name), while `Invoke-PruneEntrySweep` clears
  `*.fbprune.tmp` staged copies **inside** the transaction, once the rails have
  passed and the Temp lock is held. **The sweep identifies residue by the
  destination manifest, never by the suffix** — a user file called
  `notes.fbprune.tmp` has a manifest row and is content; a staged copy is
  unreferenced by construction. Deleting by bare suffix destroyed real data
  across root *and* snapshots (WP4 review finding H1). Neither runs under
  `-WhatIf`. The Temp lock is created **without `-Force`**, so creation is the
  atomic test and an existing folder is the staging-busy refusal.
  Retention *policy* is the caller's (IF-001) — the verb takes explicit names,
  never wildcards.
- **The manifest witness is written by `Write-Manifest` only** (SR-038). Every
  `MANIFEST.csv` gets a `MANIFEST.csv.meta` beside it — `Version`, `Rows`,
  `Bytes`, `XxH128`, `Written` as UTF-8/no-BOM/LF `Key=Value` lines, published by
  atomic rename. **The atomic rename covers the WITNESS publish only — `MANIFEST.csv`
  itself is still written in place by `Export-Csv`** (see §4's crash-window note:
  the resulting stale witness fails loud in the safe direction). One writer means backup root, staging, dated snapshots, the
  source hash cache, and every rewrite are covered and cannot drift, so **never
  stamp a witness from a caller.** Each snapshot carries **its own** witness for
  its own manifest — do **not** add the witness to `New-ReconstructScript`'s
  kit-artifact copy list (`Complete-ChangeFolder`'s artifact loop copies from the
  backup root and would overwrite each snapshot's witness with the root's; this
  is the single most dangerous mistake available in this area, pinned by TC-067).
  The witness is **root-level infrastructure** in `Test-IsInfrastructureFile` — a
  nested `sub\MANIFEST.csv.meta` is user data like any other (B6). A test that
  deliberately tampers with a manifest must re-stamp with `Write-ManifestWitness`
  or it will observe exit 3 instead of the failure it meant to exercise.
- **Restore outcome is one shared exit-code table** (SR-040): 0 complete, 1
  incomplete/content, 2 usage or precondition, 3 witness verification failed, 4
  incomplete/host — precedence 2 > 3 > 4 > 1, identical in `Reconstruct.ps1` and
  `bash/reconstruct.sh`. Normative copy lives in README "Restore exit codes".
  `Reconstruct.ps1` keeps throwing for in-process callers and only exits with a
  code under `-ExitCode`; do not make `exit` the default.
- **Reconstruct stays standalone** — no repo, no NuGet install at restore time.
- **Infrastructure files are root-level only** (`Test-IsInfrastructureFile`): a *nested*
  user file named `MANIFEST.csv`/`RECONSTRUCT.ps1`/etc. is real data (regression B6).
  Never filter data files by bare name.
- **Content-addressed data filenames carry the storage extension**: `.7z` when
  compressed, so `Compressed` and the filename agree.
- **A blank-DataPath row is resolved by the form of the file hash recovery
  locates, never by the row's `Compressed`** (SR-050) — that column describes
  only a file in the row's *own* folder, and a blank row has none. The locator
  has already PROVEN the located file's form (it expanded an archive candidate
  and matched its payload, or hashed a raw one), so `Find-DataFileByHash` /
  `find_by_hash` report it as `Form` and the restore loop's decompress decision
  reads that. A row with a non-blank `DataPath` keeps using its own `Compressed`.
  Getting this backwards writes 7z container bytes under the original filename
  and exits 0. It is reachable with no tampering at all: compression is per-file
  and per-run, so a store legitimately holds both forms of nothing-in-common
  content, and a blank row's bytes may live in any snapshot.
- **Exactly one predicate answers "does the index agree with the bytes?"** —
  `Test-StorageFormAgreement`. Both the prune rail (SR-046) and the storage-form
  audit (SR-049) call it, so they cannot drift. It carries the one deliberate
  exemption, keyed on the **payload**, not the name (62fc702): an archive-form
  file under a `Compressed=No` row is exempt only when its *own bytes*
  reproduce the row's `(hash, length)` — that is a genuinely already-compressed
  *source* file, whatever it is called. An archive whose *inner payload*
  matches the row is still a `FlagOverArchive` disagreement.
- **A snapshot keeps the restore kit it was written with, forever.** The
  `# KitRevision: <n>` marker at the top of `Reconstruct.ps1` and
  `bash/reconstruct.sh` names it; bump BOTH together whenever any kit-bundled
  file changes behavior. Revision 2 is the first with the SR-050 fix above;
  revision 3 additionally tests every non-matching `.7z` candidate as RAW bytes,
  without which a blank row for a **genuine `.7z` source file** (which expands
  fine, but to something that is not that row's content) was unrecoverable while
  every checker called the store clean. Revision 4 (2026-08-23 review round)
  honors `RECONSTRUCT.paths.json` only while the kit folder still lives inside
  the roots it records (a copied/moved store auto-detects instead of silently
  reading the original), falls back to `(hash, length)` pool recovery when a
  row's *named* data file is missing, and — in `Reconstruct.ps1` — maps `\`
  separators and keys the manifest dictionary case-sensitively on non-Windows
  hosts. Revision 5 tests a `.7z`-named recovery candidate's raw bytes even
  with no 7-Zip installed (raw needs none), so a restore requiring no actual
  decompression no longer fails demanding it. Revision 6 (2026-08-24, the
  D-2/D-3/D-4 kit bump) makes both restorers **verify every file they write**
  against the row's `(Length, xxH2Hash)` — healing a mismatch from the pool
  once, else failing loudly as `ContentMismatch` (SR-056); reclassifies an
  unexpandable **pool candidate** as content damage (exit 1) instead of a
  host problem (the row's *own* file failing to extract stays exit 4); scans
  the restore pool with `-Force` so dot-named and Hidden data files are
  recoverable by `(hash, length)`; and gives `RECONSTRUCT.ps1` a
  `-NonInteractive` guard (usage + exit 2, matching `reconstruct.sh`'s
  required `--target-root`) instead of a blocking prompt. An older kit still
  carries the defects fixed after it.
  **WP9 (2026-08-25) did not change a single kit byte, so the revision stays
  at 6** — content addressing is entirely engine-side, and both restorers already
  resolve a row by its `DataPath` or by `(hash, length)` without caring how the
  name was chosen. That also means a kit still describes the legacy
  path-addressed store shape in places: correct, because it must go on restoring
  those (SR-061 refuses only *writing* to one).
  `-Action Verify -RefreshKits` is the only mechanism that retires an old kit
  from an existing snapshot, and it copies the six kit artifacts and **never**
  `MANIFEST.csv.meta`.

## 4. Conventions & known gotchas

- **PowerShell 7+ only** (`pwsh`). Do not reintroduce 5.1 support — the hashing dependency's
  Desktop build needs transitive `System.Memory` assemblies.
- **Hashing:** xxHash128 via `System.IO.Hashing` (XXH3-based; faster than XXH64). **Not**
  K4os.Hash.xxHash — its 1.0.8 (final) release has no `XXH128` type. Use `Get-FileXxHash`.
- **Never resolve a volume with `Split-Path -Qualifier`** — it throws on a rooted
  POSIX path (`/backup`), and where the throw sat next to a tolerant `catch` it
  made SR-023's restore capacity check silently inert on Linux for months. Use
  `Get-FreeSpaceBytes` / `Get-VolumeIdentity` (Common, SR-052): cross-platform,
  never throw, and answer `$null` when the volume cannot be measured — at which
  point the caller SKIPS the check rather than refusing.
- **Never `Split-Path -LiteralPath … -Parent` / `-Leaf`** — that flag combination *throws*
  on PS7. Use `[System.IO.Path]::GetDirectoryName/GetFileName` (also wildcard-safe for
  bracketed paths). Positional `Split-Path $x -Parent` is fine.
- A function that returns `@()` yields `$null` when captured — collection params that may
  receive that need `[AllowNull()][AllowEmptyCollection()]` and a null→`@()` guard.
- Use `-LiteralPath` for file ops (paths may contain `[]`, `()`, Unicode).
- `$ErrorActionPreference = 'Stop'` at script top.
- Approved PowerShell verbs (`Get-Verb`); export new functions from the module's
  `Export-ModuleMember`.
- **Comment-based help must be the first thing in a function body.** A plain
  comment line above it (e.g. `# Implements: …`) silently breaks `Get-Help` *and*
  the generated map/flow's summary harvesting. Order: `<# .SYNOPSIS … #>` block
  first, then the `# Implements: SR-###, LLR-###` back-link line. Reference SR
  ids for input ranges instead of restating them (docs/process.md §3).
- **The manifest-witness crash window is deliberate.** `Write-Manifest` writes
  `MANIFEST.csv` *then* the witness. A crash between the two leaves a **stale**
  witness that mismatches — i.e. it fails loud in the safe direction (a refused
  restore, exit 3) rather than silently passing, and the next successful run
  rewrites both. Do not "fix" this by writing the witness first. Note the scope
  of the atomicity claim: **only the witness publish is an atomic rename**; the
  manifest is a plain in-place `Export-Csv`. `MANIFEST.csv.meta.tmp` (a crash
  leftover from that rename) is on the root-level infrastructure allowlist so it
  is never backed up as user data or warned about as an orphan.
- **Restore verification happens before any mutation.** Both restorers check the
  manifest header shape and the witness *before* creating the target folder or
  their log, so a header or witness refusal (exit 3, and the early exit-2s)
  leaves the target byte-for-byte as it was; the *late* code-2 preflights
  (capacity, 7-Zip) run after target+log creation, identically in both
  restorers. `Reconstruct.ps1` buffers the pre-target log lines and flushes
  them once the log exists; do not move the verification below the target
  creation.
- **The digest is authoritative** (`Test-ManifestWitness` / `verify_manifest_witness`).
  Fields are checked `Bytes → Rows → XxH128`, but a **Rows-only** disagreement —
  same byte length, same digest — is a counting-semantics divergence, not damage:
  it warns and restores. Bytes or digest disagreement still refuses.
- `Write-Host` is fine (this is a CLI/automation tool) — excluded in lint settings.
- **Linux restore tooling floor (`bash/reconstruct.sh`, phase `bash-v1`):** bash
  ≥ 4, GNU coreutils, **gawk** (FPAT-based RFC-4180 parsing — plain `awk`/mawk is
  not enough), **xxhsum** (xxHash ≥ 0.8, provides `xxh128sum`), and **7z**
  (`7z`/`7za`/`7zz`, p7zip) — the last needed only when the backup has compressed
  rows. The script checks these up front and fails loudly with remediation
  (SN-015 pattern), degrading only where the PS restorer degrades. It stays
  `shellcheck`-clean (warnings-as-errors, same bar as PSScriptAnalyzer) and is
  LF-only (`.gitattributes` pins `*.sh`/`*.bash`/`*.bats`). Both restorers apply
  the hash-recovery infrastructure-name skip **root-level only** (the contract /
  §3, B6) — `Find-DataFileByHash`'s recursive over-skip was a bug the bash work
  surfaced, fixed 2026-07-03 (TC-058).

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

# container build + compressed byte-exact roundtrip (Docker required)
pwsh -File scripts\Invoke-Container.ps1 -Action BuildAndTest
```

A change to engine/restore code must keep the **whole suite green and lint clean**
(current totals live in §6 "Current automated total"), and add/adjust a test
alongside any behavior change. `pwsh scripts/check.ps1 -Tier Full` runs it all.

## 6. Test matrix

### Axes
| Axis | Values |
|---|---|
| PowerShell edition | pwsh 7+ (only; 5.1 unsupported) |
| Compression | `Plain`, `Compress` (storage is always content-addressed since WP9 deleted Mirror — SR-058) |
| Hash-recalc freq | `A E D W M Y N` (unit-covered, G6 / `Engine.Tests.ps1`) |
| Backend (volumes) | `Subst` (CI), `VHDX` (virtual disks), `RealUSB` (hardware) |
| Suite group | G1–G10 |
| Filesystem (hardware) | NTFS, exFAT, FAT32 (>4 GB limit) |

### Coverage — ✅ automated · 🟡 self-hosted/manual · ⛔ N/A
| | Subst (hosted CI) | VHDX (self-hosted) | RealUSB (hardware) |
|---|:---:|:---:|:---:|
| Lint / Unit                  | ✅ | — | — |
| G1–G5, G7, G10 × 2 modes     | ✅ | 🟡 | 🟡 |
| G6 HashFrequency (7 codes)   | ✅ | ✅ | ✅ |
| G8 RealVolume                | ⛔ SKIP | ⛔ SKIP | 🟡 |
| NTFS free-space / capacity   | — | 🟡 | 🟡 |
| exFAT / FAT32 + >4 GB file   | — | — | 🟡 |
| Standalone restore (no repo) | ✅¹ | 🟡 | 🟡 |
| Container build + roundtrip   | ✅² | — | — |

¹ `RECONSTRUCT.ps1` runs from the backup folder using only bundled files; a "copy backup
elsewhere, restore, byte-compare" check is part of the hardware runbook.

² Linux CI builds the pinned image and drives a real compressed backup plus restore through
`scripts/Invoke-Container.ps1`; local execution requires Docker Desktop/Engine.

**Current automated total** (verified 2026-08-25 on a `-Tier Full -Gate G3` run,
after **WP9**): **236 integration assertions / 0 FAIL / 2 SKIP** over the 2-mode
matrix (G8 SKIPs under Subst) + **405 Pester unit/coverage tests** + **68 bats
tests** on Linux (`tests/bash`, run under WSL/CI); lint and `shellcheck` clean.

The integration figure fell from 372 and then rose again for the same reason:
WP9 deleted the storage-mode axis, halving the sweep from 4 modes to 2, and then
added the **G10-View** suite (SR-062). The unit figure rose 341 → 357 (kit-bump
WP) → 405 (WP9): the D-1/D-5 repro timelines and the exact-survival tests, the
config-v2 battery, `View.Tests.ps1`, and at step 9 the full TC-118 matrix
(`edit={owner,borrower} × copies={2,3}`), TC-135's `copies=3` arms and TC-122's
pool census. Earlier history: WP4 → 324 / 223 / 48; WP5 added `G4.2` and
`StorageForm.Tests.ps1`; the 2026-08-23 review round took it to 372 / 316 / 55.

### Suite groups
| Group | Covers |
|---|---|
| G1 InitialBackup  | Empty source, single file, 200-file bulk, nested `MANIFEST.csv` (B6), Unicode, bracketed paths. |
| G2 Incremental    | Rename, move, modify, delete, re-add identical/different, dedup. |
| G3 Reconstruction | Roundtrip from backup root, hash-fallback (incl. compressed), target-inside-backup rejected. |
| G4 Sanitization   | `G4.1` (TC-124, SR-061): a **constructed** legacy path-addressed store — the only way to get one now — is refused by `-Action Backup` before any mutation and reported as a finding by `-Action Verify`. **Plus `G4.2`** (`Invoke-G4ExtensionMerge`, TC-097/SR-004/SR-049): the already-compressed extension-list merge at scale — a genuine pre-merge store is re-run on the merged list and **nothing already stored is re-formed**; nothing dangles, verification is clean (SR-049), every snapshot and the latest state restore byte-exact, and run 2 onward is idempotent. |
| G5 EdgeCases      | Stale `Temp` aborts, read-only source, idempotent second run. |
| G6 HashFrequency  | `Test-HashRecalcDue` over all 7 codes (deterministic via `-Now`). |
| G7 Determinism    | Identical re-runs ⇒ identical manifest rows; SHA-256 spot check. |
| G8 RealVolume     | USB-only sanity; SKIPs under Subst/VHDX. |
| G10 View          | The generated browse view (SR-062, TC-129/TC-130/TC-131/TC-133): the index matches the manifest exactly including every dedup sibling, a stale `.viewstamp` triggers a rebuild, `-Action View` is idempotent, no `Snapshot_*` folder gets a view, and Verify/prune/both restorers ignore the view root entirely. |
| G9 Rollback       | Dated-snapshot timeline (injected `-BackupTime`): modify/delete/add/rename/no-op over D1–D4; restore as-of each snapshot + latest, byte-exact; mixed content (text/binary/dup/already-compressed); no snapshot for the no-op/latest run. SR-005/SR-010/SR-028. **Plus retention** (`Invoke-G9Prune`, SR-045/SR-046): prune at every timeline position on a four-snapshot store, and TC-049's delete/re-add/delete cycle pruned — every remaining state still restores and content stays stored exactly once. |

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
  PSScriptAnalyzer; `unit` → Pester (NUnit published); `integration-subst` → both
  compression modes, JUnit published. 7-Zip ships on the runner; `System.IO.Hashing` is installed + cached.
- **GitHub `ubuntu-latest` (Docker)** — builds the container and verifies a compressed
  two-file backup, complete seven-artifact restore kit (six copied files plus the
  SR-038 `MANIFEST.csv.meta` witness), and byte-exact containerized restore.
- **Self-hosted VHDX** — gated by repo var `HAS_SELF_HOSTED_HYPERV == 'true'` on a
  `[self-hosted, windows, hyper-v]` runner. `RunAllTests.bat VHDX`.
- **Hardware (RealUSB) runbook** — `Setup-USB.bat` (wipes a USB, makes four GPT/NTFS
  `FBTEST-*` partitions, drops `real-volumes.json`), then `RunAllTests.bat RealUSB`. For
  filesystem coverage, reformat the backup partition exFAT/FAT32 and re-run; on FAT32 check
  the >4 GB single-file limit surfaces cleanly. Finally copy a produced backup folder to a
  machine without this repo, run `RECONSTRUCT.bat`, and byte-compare.

## 7. Removed auxiliary & legacy scripts (2026-07-03 cleanup)

The repo used to carry standalone personal utilities (`Auxilary/`,
`DatabaseDuplicateDeletion/` — SHA-256/`*HashTable.csv`-based ad-hoc tools,
unrelated to the engine) and superseded pre-modularization artifacts
(`Test-Backup.ps1`, `RunTests.bat`, `TestRelated/`, `PrepPropertiesFile.ps1`,
plus old scratch/prompt notes). All were **deleted 2026-07-03 with human
approval** — recover any of them from git history if ever needed
(`git log --diff-filter=D --summary`). Nothing in the maintained tree references
them. Add test coverage in `tests/`, and build configs with `CredSetEx.ps1`.

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
Consolidated the legacy overview into `README.md` (setup & use) and this `AGENTS.md`
(architecture, invariants, tests, history); gated process and integration material now
lives under `docs/`. The earlier `IMPLEMENTATION_SUMMARY.md`,
`CHANGES.md`, `CHANGELOG.md`, `TEST_MATRIX.md`, and `tests/README.md` were folded in here.
