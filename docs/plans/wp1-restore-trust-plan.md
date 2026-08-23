# WP1 — Restore trust & diagnostics bundle: work order (G1→G2 package)

Drafted 2026-08-22 by an independent Opus planning agent (read-only pass over
the real code), adopted by the driver under the human's 2026-08-22 grind
authorization (batch ratification — see status.md audit log). Covers Open-items
rows **E / corrupt-manifest / D+exit-codes / J**. Registry ids allocated here:
**SN-025..026, SR-038..041, LLR-038..041, TC-066..073.**

## 0. Grounding: what the code actually does today

| Fact | Where |
|---|---|
| `Write-Manifest` = `Export-Csv` straight to `<folder>/MANIFEST.csv`, no atomicity, no witness | `Modules/FileBackup.Common.psm1:496-532` |
| Manifest writers (all of them): source hash-cache, `Test-BackupManifest`, `Sync-BackupStorageLayout`, `Optimize-ChangeFolders`, staging pre-snapshot, staging blank-and-finalize, final backup manifest | Engine `:419, :489, :591, :722, :1152, :1270, :1311` |
| Snapshot's manifest is rewritten *in staging* then the folder is renamed; the kit artifacts are copied in afterwards | `Complete-ChangeFolder` Engine `:1146-1174` |
| Infra allowlist (root-level only, B6) — 10 names incl. `RECONSTRUCT.paths.json` | Engine `:47-61` |
| PS restorer: `Read-RawManifest` = bare `Import-Csv`; **no** header/shape validation ⇒ garbage manifest restores 0 rows and exits 0 | `Reconstruct.ps1:143-150` |
| PS restorer signals failure by `throw` only (all in-repo callers use `& $recon` in-process: `tests/Common/Harness.ps1:184`, 6 × `Should -Throw` in `Coverage.Tests.ps1`) | `Reconstruct.ps1:131,147,188,218,288` |
| `Find-DataFileByHash` returns `$null` for 4 distinct causes; caller logs one message | `Reconstruct.ps1:48-89` + `:253` |
| bash restorer already has the exit scheme **0 / 1 / 2** and a header-shape guard (`die` ⇒ 2) | `bash/reconstruct.sh:39-41, 71-76, 321-330, 440-447` |
| bats already pins those codes: 0 clean, 1 incomplete/traversal, 2 corrupt-manifest | `tests/bash/fail_loudly.bats:16,22,40,61,72` |
| Failure-aggregation precedent already in the engine: log `'ERROR'` + `$OverallSuccess.Value=$false` + `continue` | `Invoke-BackupFileGroup` Engine `:983-987` |
| The two move loops have **no** try/catch: a `Move-Item` throw escapes `Invoke-BackupSet`, aborting the pipeline *and leaving the `Temp` staging folder*, which then trips the SR-017 stale-Temp guard on the next run | Engine `:1049`, `:1095` |
| Kit-artifact lists that must stay in sync | Engine `:1169`, `scripts/Invoke-Container.ps1:145`, `scripts/gen_bash_fixtures.ps1:162`, `tests/Unit/Coverage.Tests.ps1:54`, `tests/Unit/Engine.Tests.ps1:78` |

Registry maxima observed 2026-08-22: **SN-024, SR-037, LLR-037, TC-065**
(trace: SN=24 SR=37 LLR=36 TC=64). Next free ids: **SN-025, SR-038, LLR-038,
TC-066**.

## 1. Registry rows (CSV-ready, real headers)

### 1.1 `docs/requirements/stakeholder-needs.md`

Append to the **Edge-case expectations** table (columns `| SN-ID | Scenario | Expected behavior |`):

```
| SN-025 | The backup's index itself is damaged — `MANIFEST.csv` truncated, partially written, or replaced by an unrelated/garbage file | The restore refuses to run rather than "succeeding" against a shrunken job: the backup carries a witness of its own index (row count + digest) written whenever the manifest is written and duplicated into every snapshot, and both restorers check it before restoring anything. A backup written by an older version (no witness) still restores, with a clearly logged "unverified index" warning. |
```

Append to the **Core needs** table (columns `| SN-ID | Need (plain language) | Why it matters | Priority | Acceptance intent (how we'd know it's met) |`):

```
| SN-026 | When a restore fails, a script (and I) can tell *what kind* of failure it was without reading the log. | A wrapper (HomeHub/NagLight, a scheduled task) has to decide between "your bytes are gone", "fix this host and retry", and "you pointed me at the wrong folder" — one generic failure forces a human into the log every time. | S | Both restorers return the same documented exit code per failure class; deliberately induced instances of each class (clean, content missing, host/dependency problem, bad invocation/precondition, damaged index) each return their own code, identical on Windows and Linux. |
```

### 1.2 `docs/requirements/system-requirements.csv`

Header: `SR-ID,Title,SN-Refs,Requirement,Rationale,AcceptanceCriteria,Permutations,Priority,Verification,Status,Phase`

```
SR-038,Manifest witness sidecar,SN-025;SN-018,"Every MANIFEST.csv the system writes shall be accompanied by a witness sidecar MANIFEST.csv.meta in the same folder, written after the manifest and published by atomic rename, carrying a format version, the manifest's data-row count, its byte length, and the xxHash128 of its bytes exactly as written; the sidecar shall be produced by the single Write-Manifest code path (so backup root, staging, dated snapshots, the source hash cache, and every manifest rewrite are covered), and shall be classified as root-level infrastructure per SR-022 — an identically named nested user file remains data (B6).","A restore can only verify the rows its manifest still contains, so a truncated or replaced manifest shrinks the job and still reports success (HomeHub cross-check finding E); a dedup-aware physical file census cannot close this. One writer, one witness, so it cannot drift.","After any run, every folder holding a MANIFEST.csv also holds a MANIFEST.csv.meta whose Rows equals the manifest's data-row count, Bytes its file length, and XxH128 the Get-FileXxHash of its bytes; a dated snapshot carries its OWN witness (not the backup root's); a root-level MANIFEST.csv.meta produces no orphan/not-in-DB warning while a nested sub\MANIFEST.csv.meta is backed up and restored as data.","origin=set{backup-root,snapshot,staging,source-state}; mode=set{Mirror,HashAddressed}",M,Test,Draft,
SR-039,Restore verifies the manifest witness,SN-025;SN-005;SN-022,"Before restoring any file, Reconstruct.ps1 and bash/reconstruct.sh shall validate the restore origin's manifest: the CSV header shall carry the schema's key columns, and when a MANIFEST.csv.meta is present the manifest's byte length, data-row count, and xxHash128 shall match it — a mismatch, or an unparseable sidecar, shall abort with the witness exit code before any file is written. A missing sidecar (a backup written before this contract) shall log an explicit unverified-index warning and continue, unless the caller opts into strict mode (-RequireWitness / --require-witness), which makes absence an abort. An unrecognized sidecar format version shall verify only the fields it understands and warn.","Realizes SN-025 and subsumes the 2026-07-03 reviewer MINOR (a corrupt non-CSV MANIFEST.csv restored nothing yet exited 0 in Reconstruct.ps1): a garbage manifest fails the digest, and a legacy garbage manifest fails the header check. Refusing legacy backups outright would strand every backup written before this change.","A backup whose MANIFEST.csv is truncated, byte-edited, or replaced by unrelated text aborts both restorers with the documented witness exit code, writing no file into the target; re-stamping the witness makes the same manifest restore cleanly; an origin with no sidecar restores byte-exact and logs 'unverified'; the same origin under strict mode aborts.","damage=set{truncated,byte-edited,replaced-garbage,intact,absent-sidecar}; restorer=set{powershell,bash}",M,Test,Draft,
SR-040,Shared restore exit-code contract,SN-026;SN-013;SN-011,"Both restorers shall report outcome through one documented exit-code table — 0 complete; 1 incomplete because content is unrecoverable; 2 usage or precondition failure (bad arguments, missing or unrecognizable manifest, target inside the backup, missing required tool, insufficient capacity); 3 manifest-witness verification failure; 4 incomplete because of the host (an unreadable or absent search folder, 7-Zip unavailable for an archive candidate, an extraction or copy I/O error) — applying the precedence 2 > 3 > 4 > 1. Hash recovery shall report its failure cause distinctly (content not found, dependency unavailable, storage unreadable, candidate error) rather than one warning for all four, and the terminating summary shall name the count per class. Reconstruct.ps1 shall keep its terminating-error behavior for in-process callers and additionally exit with the table's code when invoked as a process entry point (RECONSTRUCT.bat).","Realizes SN-026 and IF-001's promise of a translatable exit status: today Find-DataFileByHash collapses four causes into one warning and Reconstruct.ps1 throws one generic failure for every cause (HomeHub cross-check finding D). Adopting bash/reconstruct.sh's existing 0/1/2 scheme avoids a competing numbering. Prerequisite for IF-001 leaving Experimental.","cause=set{clean,content-missing,precondition,witness-mismatch,host-dependency}; restorer=set{powershell,bash}",M,Test,Draft,
SR-041,Backup-side failure aggregation,SN-013;SN-004,"Move-RemovedFilesToStaging and Save-SupersededData shall not abort the run on the first failed move: each failure shall be caught, logged as an ERROR naming the file and cause, and recorded, the loop shall continue with the remaining entries, and the run shall report overall failure (non-zero exit) with a summary count — mirroring Invoke-BackupFileGroup's existing per-entry handling and the restore side's unrestored aggregation.","One failed move currently escapes Invoke-BackupSet, hiding every other failure, skipping snapshot finalization, and leaving the Temp staging folder behind so the NEXT run aborts on the SR-017 stale-staging guard (HomeHub cross-check finding J).","With two data files made unmovable during one run, the log records an ERROR per failure plus a summary count, every movable entry is still staged, the snapshot is still finalized, the run exits non-zero, no Temp staging folder survives, and the next run proceeds normally.","loop=set{removed-eviction,superseded-preservation}; failures=set{1,2}",S,Test,Draft,
```

### 1.3 `docs/requirements/low-level-requirements.csv`

Header: `LLR-ID,SR-Refs,Title,Module,CodeSymbol,Detail,TestRefs,Status`

```
LLR-038,SR-038;SR-022,Witness sidecar writer,FileBackup.Common;FileBackup.Engine,Write-Manifest;Write-ManifestWitness;Get-ManifestWitnessPath;Test-IsInfrastructureFile,"Write-Manifest writes MANIFEST.csv then calls Write-ManifestWitness, which computes Get-FileXxHash over the written file, emits Version/Rows/Bytes/XxH128/Written as UTF-8 (no BOM) LF key=value lines to MANIFEST.csv.meta.tmp in the same folder and publishes it with Move-Item -Force (atomic rename over any prior sidecar). Both helpers live in Common because Reconstruct.ps1 may call only Common (AGENTS.md sec.3, guarded by TC-048). WitnessFilename is added to Get-FileBackupDefaults and to Test-IsInfrastructureFile's root-level allowlist beside RECONSTRUCT.paths.json. Snapshots inherit their own witness because Complete-ChangeFolder rewrites the staging manifest through Write-Manifest before the rename; the sidecar is deliberately NOT added to the kit-artifact copy list (that would overwrite the snapshot's witness with the backup root's) (SR-038).",TC-066;TC-067,Draft
LLR-039,SR-039,Restore-side witness verification,FileBackup.Common;Reconstruct.ps1;bash/reconstruct.sh,Test-ManifestWitness;verify_manifest_witness,"Test-ManifestWitness (Common) parses MANIFEST.csv.meta, compares Bytes/Rows/XxH128 against the manifest on disk and returns a verdict object (Verified|Absent|Mismatch|Malformed) plus the failing field. Reconstruct.ps1 calls it inside Read-RawManifest's replacement, after the manifest-exists check and before the capacity pre-check, and adds the CSV header-shape check that bash already performs; bash/reconstruct.sh gains verify_manifest_witness (grep/cut key=value, wc via parse_manifest, xxh128sum) at the same point in main(), immediately after the existing header guard. Absent sidecar = WARN and continue unless -RequireWitness/--require-witness (SR-039).",TC-068;TC-069,Draft
LLR-040,SR-040,Restore exit-code taxonomy,Reconstruct.ps1;bash/reconstruct.sh,Find-DataFileByHash;Exit-Reconstruct;die_code,"Find-DataFileByHash returns [pscustomobject]@{Path;Cause;Detail} with Cause in Found|ContentMissing|DependencyMissing|StorageUnreadable|CandidateError (search folders are probed for existence/readability, an archive candidate met without a usable 7-Zip yields DependencyMissing, a caught extraction error yields CandidateError); the restore loop records {RelativePath;Cause;Detail} per unrestored row and the summary classifies them into the content class (exit 1) and the host class (exit 4). Exit-Reconstruct centralizes logging plus, under -ExitCode (passed by RECONSTRUCT.bat), 'exit <code>'; otherwise it throws, preserving the existing message wording so in-process callers and the harness keep working. reconstruct.sh keeps die()=2 and gains die_code() for 3 and the 1-vs-4 split at the end of main(); its usage text and header comment carry the table (SR-040).",TC-070;TC-071;TC-072,Draft
LLR-041,SR-041,Move-loop failure aggregation,FileBackup.Engine,Move-RemovedFilesToStaging;Save-SupersededData;Invoke-BackupSet,"Both move loops take [ref]$OverallSuccess (as Invoke-BackupFileGroup already does), wrap the Move-Item plus its destination-directory creation in try/catch, and on failure log 'Failed to <evict|preserve> ...: <message>' at ERROR, add the entry to a local failure list, set OverallSuccess to false and continue; each returns/logs a summary count so a partially staged snapshot is explicit. Invoke-BackupSet passes the ref and proceeds to Complete-ChangeFolder so staging is never orphaned (SR-017) (SR-041).",TC-073,Draft
```

### 1.4 `docs/test/test-cases.csv`

Header: `TC-ID,Verifies,Level,Method,Tier,Parameters,Expected,Automated,Status`

```
TC-066,SR-038;LLR-038,Unit,Test,Smoke,"records=set{rows,empty,rewrite}","Write-Manifest emits MANIFEST.csv.meta beside the manifest with Version=1, Rows equal to the data-row count, Bytes equal to the file length, and XxH128 equal to Get-FileXxHash of the manifest; an empty record set yields Rows=0; rewriting the manifest replaces the sidecar atomically (no .tmp survives) (SR-038). Pester: Describe 'Manifest witness sidecar (SR-038)'.",Yes,Draft
TC-067,SR-038;SR-022;LLR-038,Integration,Test,Smoke,"path=set{root-witness,nested-same-name}; origin=set{backup-root,snapshot}","After two runs, backup.log contains no orphan/not-in-DB WARN for MANIFEST.csv.meta, a nested sub\MANIFEST.csv.meta is backed up and restored as user data (B6), and each Snapshot_<date> folder carries its OWN witness matching its own manifest rather than the backup root's (SR-038/SR-022). Pester: Describe 'Manifest witness is infrastructure (SR-022, SR-038)'.",Yes,Draft
TC-068,SR-039;LLR-039,Unit,Test,Smoke,"damage=set{truncated,byte-edited,replaced-garbage,absent-sidecar,restamped}","RECONSTRUCT.ps1 aborts with the witness failure before writing any file when the origin manifest is truncated, byte-edited, or replaced by non-CSV text, restores normally once the witness is re-stamped, and restores a sidecar-less legacy origin while logging 'unverified'; -RequireWitness turns that absence into the same abort (SR-039). Pester: Describe 'Manifest witness verification on restore (SR-039)'.",Yes,Draft
TC-069,SR-039;SR-031;LLR-039,Unit,Test,Smoke,"damage=set{truncated,byte-edited,replaced-garbage,absent-sidecar}","reconstruct.sh is the bash twin of TC-068 over a writable fixture copy: each damaged manifest exits 3 with nothing written into the target, the re-stamped copy exits 0, a sidecar-less origin exits 0 with an 'unverified' warning, and --require-witness makes it exit 3 (SR-039/SR-031). bats: tests/bash/witness.bats.",Yes,Draft
TC-070,SR-040;LLR-040,Unit,Test,Smoke,"cause=set{clean,content-missing,precondition,witness-mismatch,host-dependency}","Invoked as a child process (pwsh -File RECONSTRUCT.ps1 -ExitCode), the PowerShell restorer returns 0 clean, 1 when a row's only data source was deleted, 2 for a target inside the backup and for a missing MANIFEST.csv, 3 for a witness mismatch, and 4 when an archive row's recovery needs an unavailable 7-Zip; the in-process invocation still throws with the existing wording (SR-040). Pester: Describe 'Restore exit-code table (SR-040)'.",Yes,Draft
TC-071,SR-040;SR-031;LLR-040,Unit,Test,Smoke,"cause=set{clean,content-missing,precondition,witness-mismatch,host-dependency}","reconstruct.sh returns the same five codes for the same five induced conditions as TC-070, and the pre-existing TC-055 expectations (0 clean, 1 incomplete, 1 traversal, 2 corrupt/unrecognized manifest header) are unchanged (SR-040/SR-031). bats: tests/bash/exit_codes.bats + tests/bash/fail_loudly.bats.",Yes,Draft
TC-072,SR-040;LLR-040,Unit,Test,Smoke,"cause=set{ContentMissing,DependencyMissing,StorageUnreadable,CandidateError}","Find-DataFileByHash returns a distinct Cause for each of the four collapsed failures and RECONSTRUCT.log carries a distinct message per cause, with the terminating summary naming the count per class instead of one 'cannot recover by hash' line (SR-040, HomeHub finding D). Pester: Describe 'Hash-recovery failure causes are distinguishable (SR-040)'.",Yes,Draft
TC-073,SR-041;LLR-041,Integration,Test,Smoke,"loop=set{removed-eviction,superseded-preservation}; failures=2","With two data files held unmovable during one run, backup.log records an ERROR per failure plus a summary count, every other entry is still staged, the dated snapshot is still finalized, the run exits 1, no Temp staging folder survives, and the following run completes normally instead of tripping the SR-017 stale-staging guard (SR-041). Pester: Describe 'Move loops aggregate failures (SR-041)'.",Yes,Draft
```

Post-change trace expectation: **SN=26 SR=41 LLR=40 TC=72, 0 orphans**,
phase-deferred unchanged (bash-v2, container-v1). All four SRs carry an empty
`Phase` (core), so the G3 `--require-verified --phase core,bash-v1` ratchet
will demand them Verified — which is the intent.

### 1.5 `docs/requirements/interfaces.csv` (IF-001 edit, no new IF)

Amend the `Contract` cell (append): *"Restore outcome is reported through the
exit-code table documented in README 'Restore exit codes' (0 complete; 1
content unrecoverable; 2 usage/precondition; 3 manifest-witness verification
failure; 4 host/dependency failure — retriable), identical for RECONSTRUCT.bat
and reconstruct.sh; a restore origin's MANIFEST.csv is witnessed by
MANIFEST.csv.meta which both restorers verify before writing anything
(SR-038/SR-039/SR-040)."* Add `SR-038;SR-039;SR-040` to `SR-Refs`. Leave
`Version=v1`, `Stability=Experimental` — WP2's config contract is the
remaining blocker.

## 2. The exit-code table

Normative home: **README.md, new `### Restore exit codes` subsection under
"3. Restore"** (referenced by `Reconstruct.ps1`'s `.NOTES`,
`reconstruct.sh`'s header comment and `usage()`, IF-001, and AGENTS.md §2).
Codes 0/1/2 are exactly what `bash/reconstruct.sh:39-41` already ships; 3 and
4 are the new distinctions.

| Code | Class | Meaning | Emitted when |
|---|---|---|---|
| **0** | Complete | Every manifest row restored; witness verified (or explicitly reported unverified) | end of the restore loop with an empty unrestored list |
| **1** | Incomplete — content | Everything salvageable was restored; the remaining rows' bytes do not exist in the data pool | `ContentMissing`, `NoDataPathOrHash`, missing data file at a resolvable `DataPath`, path-traversal refusal |
| **2** | Precondition / usage | Nothing was attempted; the invocation or environment is wrong | bad/missing arguments; no `MANIFEST.csv` in the origin; manifest header unrecognizable (legacy corrupt-file guard); target inside the backup or change root; insufficient free space; 7-Zip absent while the manifest has `Compressed=Yes` rows; bundled Common module absent (PS) |
| **3** | Witness verification failed | The index itself is untrustworthy; **no file is written to the target** | `MANIFEST.csv.meta` present and `Bytes`/`Rows`/`XxH128` disagree with the manifest; sidecar unparseable; sidecar absent **under strict mode** |
| **4** | Incomplete — host | Rows failed for reasons on this machine, not in the backup; **retry after fixing the host** | `DependencyMissing` (an archive candidate met with no usable 7-Zip during hash recovery), `StorageUnreadable` (a search folder absent/unreadable), `CandidateError` (extraction or copy I/O error) |

**Precedence when several apply: 2 > 3 > 4 > 1.** Rationale: 2 and 3 abort
before mutation; 4 outranks 1 because it is the actionable one (a wrapper
should retry, not alarm the user about lost data). The summary line names both
counts regardless, e.g. `Reconstruction INCOMPLETE: 3 file(s) could not be
restored (2 content-missing, 1 host).`

**Wording that must not change** (existing assertions depend on it):
`*file(s) could not be restored*` (`Coverage.Tests.ps1:397,492`;
`fail_loudly.bats:23`), `*free space*` (`:109`), `*MANIFEST.csv not found*`
(`:413`), `*7-Zip is required*` (`:436`), `not a FileBackup manifest`
(`fail_loudly.bats:73`), `path traversal`, `INCOMPLETE`.

## 3. Sidecar format spec

**Name** `MANIFEST.csv.meta` (`Get-FileBackupDefaults` → new `WitnessFilename`
key, so no literal is duplicated; the same pattern as `DatabaseFilename`).
**Encoding** UTF-8, **no BOM**, **LF** line endings, exactly five `Key=Value`
lines, trailing newline. Deliberately *not* JSON: the bash side already had to
parse `RECONSTRUCT.paths.json` with a `sed` hack (`reconstruct.sh:304-306`);
key=value keeps the bash reader a two-line `grep`/`cut` with no new tool.

```
Version=1
Rows=<data-row count, header excluded>
Bytes=<length of MANIFEST.csv in bytes, as written>
XxH128=<32-char UPPERCASE hex, Get-FileXxHash of the manifest file's bytes>
Written=<ISO 8601 'O' timestamp>
```

- `XxH128` is the authoritative check; `Bytes` is a cheap pre-check that names
  truncation precisely; `Rows` is the operator-legible number ("expected 412
  rows, found 118"). All three are compared; the report names which failed.
- Digest is over the **file bytes exactly as on disk** (so `Export-Csv`'s CRLF
  and quoting are included) — computable identically by `Get-FileXxHash` and
  `xxh128sum`, i.e. **no new tool on either side** (`hash_file` at
  `reconstruct.sh:87`).
- Unknown keys are ignored. `Version` > 1 ⇒ verify only the understood keys
  and WARN (never refuse a restore because the witness is *newer*).

**Atomic write.** The repo's atomicity idiom is publish-by-rename
(`Complete-ChangeFolder`'s `Rename-Item`, Engine `:1165`; B7's
copy-then-write-then-delete). Apply the same: `Write-Manifest` writes
`MANIFEST.csv` (unchanged), then `Write-ManifestWitness` hashes the written
file, writes `MANIFEST.csv.meta.tmp` in the same folder, and publishes with
`Move-Item -Force` (same-volume rename). Ordering is manifest-then-witness on
purpose: a crash between them leaves a *stale* witness that mismatches, i.e.
it fails loud in the safe direction, and the next successful run rewrites
both. Document that in the function's `.NOTES` and in AGENTS.md §3.

**Where each copy comes from.**

| Folder | Source of its witness |
|---|---|
| Backup root | `Write-Manifest` at Engine `:1311` (and `:489`/`:591` on the sanitize/migrate paths) |
| Staging `Temp` | `Write-Manifest` at Engine `:1270` |
| `Snapshot_<date>` | the staging witness, regenerated by the blank-DataPaths rewrite at Engine `:1152`, then carried through the folder `Rename-Item` at `:1165` |
| Snapshot after `Optimize-ChangeFolders` blanks more DataPaths | regenerated at Engine `:722` |
| Source hash cache (`SrcStatePath`, defaults to the source root, `Resolve-BackupSetPaths:822`) | `Write-Manifest` at Engine `:419` |

**Do not** add `MANIFEST.csv.meta` to the kit-artifact copy list at Engine
`:1169` — that list copies from `$BkpPath` into the snapshot and would
overwrite the snapshot's own witness with the backup root's. This is the
single most dangerous mistake available in this change.

## 4. Implementation plan (ordered)

**Phase A — write side (PS only, no restorer changes yet).**
1. `Modules/FileBackup.Common.psm1`: add `$script:WitnessFilename =
   'MANIFEST.csv.meta'` (near `:27`), expose it from `Get-FileBackupDefaults`
   (`:94`); add `Get-ManifestWitnessPath`, `Write-ManifestWitness`,
   `Test-ManifestWitness`; call the writer at the end of `Write-Manifest`
   (`:531`); extend `Export-ModuleMember` (`:536`). Comment-based help
   **first**, then `# Implements: SR-038, LLR-038` (AGENTS.md §4 — a leading
   comment silently breaks `Get-Help` and the generated map).
2. `Modules/FileBackup.Engine.psm1`: add `$script:Def.WitnessFilename` to the
   `$infra` list at `:47-60` with the same one-line rationale comment the
   sidecar carries. **Do not** touch the root-level-only rule at `:46` — that
   is B6/TC-011/TC-052/TC-058.
3. Tests: TC-066, TC-067. Run `Coverage.Tests.ps1` and `Engine.Tests.ps1`
   immediately — TC-052's "no `RECONSTRUCT.paths.json` warning" test is the
   template for TC-067's first assertion.

**Phase B — exit-code taxonomy (PS restorer).**
4. `Reconstruct.ps1`: add `[switch]$ExitCode` and `[switch]$RequireWitness` to
   `param()` (`:24-29`); add `Exit-Reconstruct` (log → `exit <code>` when
   `-ExitCode`, else `throw` with today's wording); rewrite
   `Find-DataFileByHash` (`:48-89`) to return `@{Path;Cause;Detail}` and to
   probe folder readability before enumerating; convert the five existing
   `throw`s (`:131,147,188,218,288`) and the four `$unrestored.Add` sites
   (`:234,254,259,268`) to carry a cause; classify and emit at `:285-289`.
5. `Modules/FileBackup.Engine.psm1:777` — `RECONSTRUCT.bat` body gains
   `-ExitCode` before `%*`.
6. `bash/reconstruct.sh`: `die_code()`; witness/`1`-vs-`4` classification at
   `:440-447`; update the header comment `:39-41` and `usage()` `:241`.
7. Tests: TC-070, TC-071, TC-072.

**Phase C — witness verification (both restorers).**
8. `Reconstruct.ps1`: replace `Read-RawManifest` (`:143-150`) with
   manifest-exists → header-shape check (mirroring `reconstruct.sh:326-330`,
   exit 2) → `Test-ManifestWitness` (exit 3) → `Import-Csv`. Placement is
   **before** the capacity pre-check at `:167`, so nothing is written on a bad
   index.
9. `bash/reconstruct.sh`: `verify_manifest_witness()` inserted directly after
   the existing header guard at `:330`; `--require-witness` flag in the arg
   loop `:251-261`.
10. Tests: TC-068, TC-069 (new `tests/bash/witness.bats`).

**Phase D — backup-side aggregation (item J).**
11. `Move-RemovedFilesToStaging` (`:1005-1053`) and `Save-SupersededData`
    (`:1055-1098`): add `[Parameter(Mandatory)][ref]$OverallSuccess`,
    try/catch around the `New-Item`/`Move-Item` pairs (`:1046-1050`,
    `:1094-1095`), log at `'ERROR'`, aggregate, continue, summary line. Copy
    the shape from `Invoke-BackupFileGroup:983-987` verbatim so the two loops
    read the same.
12. `Invoke-BackupSet:1304` and `:1289` pass `-OverallSuccess
    $OverallSuccess`. Do **not** early-return: step 13 must still run so the
    staging folder is finalized or discarded (otherwise the next run trips the
    SR-017 stale-`Temp` guard).
13. Test: TC-073 (hold a file open with `[IO.File]::Open(..., Read, None)` to
    force the move failure; assert both failures logged, snapshot present,
    exit 1, no `Temp` left, next run clean).

**Phase E — kit, fixtures, docs, harness.**
14. Kit/artifact lists: `scripts/Invoke-Container.ps1:145` (six → seven
    artifacts; also update the "six-artifact" phrasing in
    status.md/`homehub-integration.md` where it appears),
    `scripts/gen_bash_fixtures.ps1:162` if the witness should be copied like a
    kit artifact — **it should not**; instead confirm the generator's
    normalization step (`:171-176`) leaves each folder's own `.meta` intact
    and consistent with its manifest.
15. **Regenerate `tests/fixtures/bash-restore/**` with
    `scripts/gen_bash_fixtures.ps1`** so every fixture manifest gains a
    matching witness; keep at least one deliberately witness-less origin (the
    hand-built manifest in `fail_loudly.bats:56-59` already is one) to pin the
    legacy path.
16. Docs: README `### Restore exit codes` + witness mention in "3. Restore"
    and "Restore on Linux"; AGENTS.md §2 (bundled-artifact list), §3 (new
    invariant: *the manifest witness is written by `Write-Manifest` only,
    snapshots carry their own, root-level infrastructure*), §4 (crash-window
    note); `docs/requirements/interfaces.csv` IF-001;
    `docs/plans/bash-variant-plan.md` contract table.
17. Regenerate the generated blocks: `pwsh scripts/gen_arch_map.ps1` (new
    Common functions appear in AGENTS.md + `docs/architecture.md`), then
    `python scripts/trace.py --strict`, then `pwsh scripts/check.ps1 -Tier
    Full`, then bats + shellcheck on Linux/WSL.

## 5. Regression risks (enumerated, with the exact call sites)

| Risk | Site | Handling |
|---|---|---|
| **B6 / TC-052 / TC-011 / TC-058** — adding a name to the allowlist | Engine `:47-61` | The name goes in the list only; the root-level-only guard at `:46` is untouched. TC-067 asserts *both* halves (root = infra, `sub\MANIFEST.csv.meta` = data). |
| **Tests that tamper with `MANIFEST.csv` directly now trip the witness** | `Coverage.Tests.ps1:428-431` (TC-063 compressed-row case), `:485-488` (TC-064 traversal case) | Export `Write-ManifestWitness` from Common and have those tests re-stamp after tampering — the intended failure (7-Zip / traversal) must still be what the test observes, not exit 3. |
| **Snapshot witness overwritten by the backup root's** | Engine `:1169` artifact loop | Explicitly excluded; TC-067 asserts each snapshot's witness matches its own manifest. |
| **`Optimize-ChangeFolders` rewrites snapshot manifests post-finalization** | Engine `:710-723` | Covered automatically because `Write-Manifest` owns the witness — this is the reason the writer must live there and not in the callers. |
| **`throw` → `exit` would silently break every in-process caller** | `tests/Common/Harness.ps1:184`, `tests/Suites/G3-Reconstruction.ps1:23`, `G9-Rollback.ps1:60`, 6 × `Should -Throw` in `Coverage.Tests.ps1` | Default stays `throw`; `exit` only under `-ExitCode`, which only `RECONSTRUCT.bat` and the new child-process tests pass. |
| **bats expectations on codes 0/1/2** | `fail_loudly.bats:16,22,40,61,72` | Unchanged by design: the corrupt-header guard keeps exit 2; only new conditions get 3/4. |
| **Legacy backups (no sidecar) must still restore** | committed fixtures under `tests/fixtures/bash-restore/**`, plus every backup a user already owns | Absent sidecar = WARN + continue; strict mode is opt-in. TC-068/TC-069 pin it. |
| **Container smoke's artifact assertion** | `scripts/Invoke-Container.ps1:145` | Add the witness to the list in the same change, or the Linux Docker CI job fails on the next run. |
| **A per-run write into the user's source tree** | Engine `:419` with `SrcStatePath` defaulting to `SrcPath` (`:822`) | Already true for `MANIFEST.csv`; note it in README's "How it works" so it is not a surprise. |
| **Performance** | `Write-ManifestWitness` re-hashes the manifest on every write; `Invoke-BackupSet` writes 2–3 manifests per set per run | xxHash128 over a manifest is negligible; no PB row exists, so nothing to breach. |

## 6. Design decisions on the planner's open questions (driver, 2026-08-22 — flagged for batch ratification)

1. **PowerShell exit-code delivery:** the `-ExitCode` switch — default stays
   `throw` (preserves every in-process caller and the six `Should -Throw`
   assertions); `RECONSTRUCT.bat` and the child-process TCs pass `-ExitCode`.
2. **Engine-side witness verification before mutating a backup:** deferred out
   of WP1; revisit with WP5's `-VerifyStorage`.
3. **`Rows` semantics:** record count as `Import-Csv`/`parse_manifest` count
   them (not raw line count); `XxH128` stays authoritative so a counting
   divergence can never alone condemn a good manifest.
4. **SN placement** (SN-025 edge-case table, SN-026 core-needs table): as
   proposed.
