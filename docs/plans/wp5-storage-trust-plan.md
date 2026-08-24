# WP5 — Storage-form trust: work order

Drafted 2026-08-22 by an independent Opus planning agent (read-only, pinned at
`18e4c98` — all line references are that commit's coordinates), adopted by the
driver under the human's 2026-08-22 grind authorization (batch ratification).
Covers Open-items rows **C**, **ext-list merge**, **backup-side capacity**,
and the WP4-surfaced latent form defect. Ids allocated: **SN-030,
SR-049..052, LLR-049..052, TC-091..102.** Driver decisions on the open
questions are in §8. **WP5 must not start before WP4 has merged** (it consumes
WP4's Get-BackupContentIndex, Test-PoolResolves, and the -Action dispatch).

> **Two NEW defects surfaced by this planning pass (not in any disposition):**
> **G10** — layout migration is not refcount-aware: dedup'd rows sharing one
> DataPath can be transformed apart and the shared file deleted while still
> referenced (data loss; the ext-list merge is the trigger; captured as
> SR-051, sequenced before the merge). **G9** — SR-023's restore capacity
> check is silently inert on Linux (`Split-Path -Qualifier` errors on a POSIX
> path, swallowed by the adjacent catch): the container restore has no
> capacity guard (folded into SR-052). Both get Open-items rows.

## 1. Grounding table (@ 18e4c98)

| # | Fact | Location |
|---|---|---|
| G1 | Sync's migration decision compares manifest metadata to config only: `$needsTransform = ($row.StoredAsHashSize -ne $expectedStoredAs) -or (($row.Compressed -eq 'Yes') -ne $shouldCompress)` — finding C VERIFIED | Engine.psm1:529 (fn :501) |
| G2 | Phase 1 copy/compress + row mutation; Phase 2 unconditional delete of `$oldPathsToDelete` → G10 | Engine.psm1:535, :587-590, :602-608 |
| G3 | Test-ShouldCompress = extension-only vs `$script:NonCompressibleExtensions` (17 entries) | Common.psm1:383-398; list :57-63 |
| G4 | bash has NO extension list (restore never calls Test-ShouldCompress) — the merge is backup-side-only; restore-kit impact nil; "bash's list" = HomeHub MiniPC-Deployer list quoted in homehub §2 | grep: 0 hits |
| G5 | PS restorer branches on THE ROW after hash recovery: `if ($row.Compressed -eq 'Yes')` — WP4 §5.7 VERIFIED | Reconstruct.ps1:548-563 |
| G6 | bash identical: `if [[ "${d_comp[i]}" == "Yes" ]]` after find_by_hash — BOTH restorers in scope | reconstruct.sh:583 |
| G7 | Find-DataFileByHash already PROVES the located file's form (archive: expand+payload match :225-238; raw: hash match :243-249; bash :224-245) — the fix is zero extra I/O | Reconstruct.ps1:225-249 |
| G8 | Backup side has NO capacity preflight anywhere (grep: 0 hits for free-space APIs in Engine/Common/FileBackup.ps1/entrypoint) | — |
| G9 | SR-023's restore check inert on Linux: `Split-Path -Qualifier '/backup'` errors, caught, check silently skipped; bash's `df -P -B1` works | Reconstruct.ps1:441-455; reconstruct.sh:508 |
| G10 | Migration not refcount-aware: rows share DataPath (Invoke-BackupFileGroup :965-977), per-row transform decision (:526-532), unconditional delete (:602-608) — contrast refcount-aware Move-RemovedFilesToStaging (B9) | Engine.psm1 |
| G11 | Migration coverage today: 2 assertions, tree-mode only; no compression flip tested anywhere; no unit test calls Sync directly | G4-Sanitization.ps1 |
| G12 | Optimize keys on content hash (form-agnostic), keeps root copy, blanks snapshot DataPaths leaving Compressed untouched — makes F3 reachable with no tampering | Engine.psm1:662-731 |
| G13 | SN-003's acceptance says a `.docx`/`.txt` IS stored as `.7z` — constrains the merge (no Office extensions) | stakeholder-needs.md |
| G14 | SR-042's config schema is closed — no cheap `MinFreeBytes` key | Engine.psm1 $setKeys |
| G15 | -Action dispatch is WP4's (LLR-048); WP5 extends it, never invents a parallel one | FileBackup.ps1 |

## 2. The §5.3 claim — verified, corrected

**True, under-specified, and the frontier row's framing is stale.** Four
malformed shapes:

| Shape | Sync's behavior | Restore consequence |
|---|---|---|
| (a) Compressed=Yes, name `.7z`, bytes raw | untouched (metadata agrees with config) | expand fails → exit 4, misfiled as a HOST problem |
| (b) Compressed=No, no `.7z` name, bytes ARE an archive | untouched | plain-copies archive bytes under the original name → **exit 0, silent corruption** |
| (c) Compressed=Yes but config says No, bytes raw | transform attempted, Expand throws, ERROR logged, `continue` — **set still succeeds** | as (a) |
| (d) StoredAsHashSize wrong, form fine | name repaired, form never checked | none |

Corrections: (1) the claim must widen to "…or is subjected to a
transformation whose failure is swallowed into a log line" (shape c,
:552-556/:594-596); (2) the repro must assert both the silent (b) and
loud-but-misclassified (a/c) shapes plus exit codes; (3) status.md's "with B
fixed, new malformed rows can't be created" is stale — G10 and the
compression-flip sequence below create form-disagreeing rows today with no
tampering.

**The no-tampering repro (TC-092, write FIRST):** run N with
CompressEnabled=false → supersede a file → snapshot S full of blank-DataPath
rows carrying Compressed=No; run N+1 with CompressEnabled=true → Sync
migrates ONLY the backup root (`-BackupRoot`, :1318) → restore S: blank row →
hash recovery finds the root's `.7z`, proves the payload, returns the archive
path → row says No → **Copy-Item writes 7z container bytes under the original
filename, exit 0**. Reverse flip and every ext-merge migration produce the
loud exit-4 direction.

## 3. Registry rows (CSV-ready — apply verbatim)

### 3.1 stakeholder-needs.md — Core needs

```
| SN-030 | Trust that what is actually stored matches what the index says about it — and that turning compression on or off, or changing which file types get compressed, never quietly damages an older snapshot's restore. | The index records how each file was stored (compressed or not); nothing ever checks that against the bytes on disk, so a wrong entry validates itself forever and a restore can write archive bytes under the original filename and report success. Changing the compression policy re-forms the live backup but not the snapshots, which is enough to trigger it during ordinary use. I also need to be told before a backup starts that the destination has room, the way a restore already tells me. *(HomeHub cross-check finding C + the WP4-surfaced latent defect + the backup-side half of the capacity guard.)* | M | An on-demand check reports every place the stored form and the index disagree, across the live backup and every snapshot, without changing anything, and a repair mode fixes the ones that are unambiguously wrong; restoring any state after a compression-policy change reproduces the original bytes exactly, or fails loudly, but never writes archive bytes under a real filename; a backup run that would not fit refuses before writing anything. |
```

### 3.2 system-requirements.csv

```csv
SR-049,Storage-form verification and repair,SN-030;SN-005;SN-025,"The system shall provide an opt-in verification action, never invoked by a normal backup run, that audits every manifest row in the backup root and in every Snapshot_* folder against the physical bytes: the DataPath extension, the Compressed column and the actual stored form of the file must agree; a blank-DataPath row's Compressed must agree with the form of the file the shared restore hash-recovery locates for its (xxH2Hash,Length); and every non-blank DataPath must exist. Verification shall mutate nothing and report each finding with its row, folder and class. An explicit repair mode shall correct only findings that are unambiguous from bytes in the row's own folder - taking the physical bytes as ground truth, rewriting the Compressed column and renaming the data file so name and form agree, never re-packing or re-compressing content, never editing the six logical columns, and persisting every touched folder through Write-Manifest so its SR-038 witness is re-stamped. Findings about blank-DataPath rows shall be reported, never silently repaired. Outcome shall be reported through the SR-040 exit-code table.","Realizes SN-030 and closes HomeHub cross-check finding C: Sync-BackupStorageLayout's migration decision (Engine.psm1:529) compares manifest metadata with configuration and never with the bytes, so a malformed row validates itself, and a transformation that fails on a malformed row is swallowed into a log line without failing the run. A physical verify inside every migration would fight SR-024 idempotence and run-time cost, so the check is a separate opt-in action.","A backup seeded with each malformed shape (Compressed=Yes over raw bytes; Compressed=No over archive bytes; a .7z name over raw bytes; a dangling DataPath) is reported by the verification action with one finding per row and a non-zero status, with the tree byte-identical afterwards; repair mode makes each unambiguous case agree and a subsequent verification reports clean; a clean backup verifies clean and exits 0 in all four storage modes; a normal backup run never invokes verification (source-level guard) and a backup run immediately after a repair is idempotent (SR-024).","mode=set{Mirror,Mirror+Compress,HashAddressed,HashAddressed+Compress}; defect=set{flag-over-raw,flag-over-archive,name-lies,dangling-datapath,blank-row-form-disagreement,clean}; action=set{verify,repair}; scope=set{root,root+snapshots}",M,Test,Draft,
SR-050,Restore resolves storage form from the located file,SN-030;SN-005;SN-006,"When a manifest row's DataPath is blank and its bytes are recovered by (xxH2Hash,Length) from elsewhere in the data pool, both restorers shall decide whether to decompress from the FORM OF THE FILE THEY LOCATED - which the hash-recovery search has already proven, by expanding an archive candidate and matching its payload - and not from the row's Compressed column. A row with a non-blank DataPath shall continue to be resolved by its own Compressed column, which describes the file in its own folder. Where an archive candidate fails to expand, the candidate shall additionally be considered as raw bytes before being recorded as a candidate error. Both restorers shall behave identically and keep the SR-040 exit-code contract.","Realizes SN-030. A blank-DataPath row's Compressed column describes the form the byte had in another folder at another time; consulting it for a file found elsewhere in the pool is reading the wrong field. Reachable today with no tampering: Sync-BackupStorageLayout migrates only the backup root (Engine.psm1:1318), so after a compression-policy flip an untouched snapshot row says No while the only surviving copy is a .7z - Reconstruct.ps1:558 then plain-copies archive bytes under the original filename and exits 0 (WP4 retention plan finding F3; homehub cross-check finding C family). The located file's form costs nothing to report: Reconstruct.ps1:225-249 and reconstruct.sh:224-245 have already proven it.","In every storage mode, a snapshot restored after a compression-policy flip that leaves only the opposite-form copy in the pool reproduces the original bytes exactly and exits 0 in BOTH restorers; the same holds in the reverse direction; a non-blank DataPath row's behaviour is unchanged (TC-023, TC-021, G3 remain green); a genuinely unrecoverable row still exits 1 and a host-class failure still exits 4.","direction=set{row-says-No-file-is-archive,row-says-Yes-file-is-raw,agreeing}; restorer=set{powershell,bash}; origin=set{backup-root,snapshot}; mode=set{Mirror,HashAddressed}",M,Test,Draft,
SR-051,Layout migration never deletes a still-referenced data file,SN-030;SN-002;SN-008,"Storage-layout migration shall not delete a superseded data file that any manifest row still references after the migration, and shall migrate rows that share one physical data file consistently, so a partial transformation cannot leave a row pointing at a deleted path. Where a migration cannot be completed for a row, the row and its data file shall be left mutually consistent and the condition shall be surfaced as a failure of the backup set rather than a log line only.","Dedup makes several rows share one DataPath (Invoke-BackupFileGroup, Engine.psm1:965-977). Sync-BackupStorageLayout selects rows for transformation per row (Engine.psm1:526-532) and then deletes every superseded path unconditionally (Engine.psm1:602-608) with none of the reference counting Move-RemovedFilesToStaging already performs for the same hazard (B9). Two rows with identical content but different extensions - which the SR-004 extension-list merge creates at scale - are transformed apart, and the untouched row is left dangling. A transformation failure is currently swallowed by a continue (Engine.psm1:552-556, 594-596) and the set still reports success.","A backup containing two rows with identical content and different extensions, migrated so that only one of them changes form, leaves both rows resolvable and every state restorable byte-exact with exit 0; no data file referenced by the post-migration manifest is deleted; a forced transformation failure fails the backup set (non-zero) instead of passing silently; dedup is preserved across a migration (content stored once per (hash,length) on the quiescent state).","mode=set{Mirror,Mirror+Compress,HashAddressed,HashAddressed+Compress}; sharing=set{shared-datapath-split-decision,shared-datapath-same-decision,unshared}; failure=set{none,forced-transform-error}",M,Test,Draft,
SR-052,Backup-side capacity preflight,SN-030;SN-019;SN-013,"Before writing any backup or staging bytes, the engine shall estimate the bytes the run will add to the backup volume (new deduplicated content, sized by uncompressed length, plus any storage-layout migration copies) and to the change volume (superseded and removed content that must be copied rather than renamed because it crosses a volume), compare each against that volume's free space measured cross-platform, and refuse the backup set before mutation when either is insufficient, naming the volume, the requirement and the free space. The same free-space measurement shall be used by Reconstruct.ps1, replacing the drive-qualifier lookup that cannot resolve a POSIX path and therefore silently skips the SR-023 check on Linux and in the container.","Realizes SN-030 and the backup half of SN-019. SR-023 is restore-only and there is no free-space logic anywhere in the engine (verified at 18e4c98). The destination is a HomeHub-controlled bind mount, so a full volume is a realistic failure mode, and a run that fills the volume mid-way leaves the manifest and the bytes out of step. Reconstruct.ps1:443 resolves capacity through Split-Path -Qualifier, which errors on a rooted POSIX path and is caught by the adjacent handler, so the container restore has no capacity guard at all while bash/reconstruct.sh:508 does.","A backup set whose new content exceeds the destination's free space refuses before any file is created or modified, with the tree byte-identical, a message naming volume/required/free, and a non-zero status; a set that fits proceeds unchanged; the measurement returns a plausible non-zero value for a rooted POSIX path on Linux and for a drive-qualified path on Windows; the restore capacity check demonstrably fires on Linux (container) where it previously skipped.","volume=set{backup,change}; platform=set{windows,linux}; fit=set{fits,does-not-fit}; migration=set{none,pending}",S,Test,Draft,
```

(Empty trailing Phase = core. SR-052's container evidence rides the existing
Docker job — core row with container evidence, no ratchet debate.)

### 3.3 low-level-requirements.csv

```csv
LLR-049,SR-049;SR-038;SR-040,Storage-form audit and repair,FileBackup.Engine,Test-BackupStorageForm;Get-StorageFormFinding;Repair-BackupStorageForm;Get-StoredFileForm,"Get-StoredFileForm classifies one file as Archive or Raw from its first six bytes (7z magic 37 7A BC AF 27 1C) plus its extension, with no hashing. Test-BackupStorageForm walks the pool through WP4's Get-BackupContentIndex (LLR-047) - backup root at FolderOrder -1 then Snapshot_* in name order - and emits one finding record {Folder, RelativePath, DataPath, Class, Observed, Expected, Repairable} per disagreement; classes NameLies, FlagOverRaw, FlagOverArchive, DanglingDataPath, BlankRowFormDisagreement, Unreferenced. -Deep additionally verifies payload identity (raw: length+Get-FileXxHash vs the row; archive: expand to temp and hash) and requires 7-Zip. Repair-BackupStorageForm acts only on findings whose evidence is a file in the row's own folder, rewrites Compressed and renames the data file so name and form agree, never re-packs, never touches the six logical columns, and persists each folder with Write-Manifest (never Export-Csv, never a direct Write-ManifestWitness call). Blank-row findings are reported only. Enumeration uses Get-DataFile/Test-IsInfrastructureFile at each folder's own root (root-level only, B6/SN-018). Outcome mapped to the SR-040 table; no call site inside Invoke-BackupSet.",TC-091;TC-093;TC-094;TC-102,Planned
LLR-050,SR-050;SR-040;SR-029,Hash recovery reports the located file's form,Reconstruct.ps1;bash/reconstruct.sh,"Find-DataFileByHash;find_by_hash","Find-DataFileByHash's Found result gains a Form field (Archive when the match was proven by expanding a .7z candidate at Reconstruct.ps1:225-238, Raw when proven by hashing the file itself at :243-249); find_by_hash's tuple becomes Found\037<form>\037<path>. The restore loop's hash-recovery branch (Reconstruct.ps1:522-533 / reconstruct.sh:550-575) records the form and the decompress decision at Reconstruct.ps1:548 / reconstruct.sh:583 consults it; the non-blank DataPath branch keeps using the row's Compressed. When expanding an archive candidate fails, the candidate is re-tested as raw bytes (length + hash) before a CandidateError is recorded. No new tool, state or manifest column; kit-bundled files change, so this is a restore-kit revision.",TC-092;TC-098;TC-099,Planned
LLR-051,SR-051;SR-012;SR-013;SR-026,Refcount-safe layout migration,FileBackup.Engine,Sync-BackupStorageLayout,"After Phase 1, the set of DataPaths still referenced by the post-transformation manifest is computed once (the same map already built for the orphan warning at Engine.psm1:609-617) and Phase 2 (Engine.psm1:602-608) skips any old path present in it, logging the retention reason - mirroring Move-RemovedFilesToStaging's B9 refcounting. Rows sharing one physical DataPath are decided together: the transformation set is grouped by (xxH2Hash,Length) and a group is transformed only when every member agrees, otherwise the group is reported as a form conflict. A failed transformation (Engine.psm1:552-556, 594-596) sets the set's OverallSuccess to false instead of only logging.",TC-095;TC-097,Planned
LLR-052,SR-052;SR-023;SR-043,Cross-platform free-space preflight,FileBackup.Common;FileBackup.Engine;Reconstruct.ps1,"Get-FreeSpaceBytes;Assert-BackupCapacity;Invoke-BackupSet","Get-FreeSpaceBytes (Common, so the restore kit stays self-contained) resolves a path's containing volume with System.IO.DriveInfo over the resolved full path and falls back to Get-PSDrive on a drive-qualified path, returning $null only when neither can answer - it never throws. Reconstruct.ps1:441-455 consumes it in place of Split-Path -Qualifier + Get-PSDrive, so the SR-023 check works for a rooted POSIX path. Assert-BackupCapacity (Engine) sums the run's additions per volume - new (hash,length) groups not already in the backup manifest at uncompressed Length, plus Sync's pending transformation bytes, plus staging bytes only when ChangePath resolves to a different volume than BackupPath - and throws a classified precondition failure before any mutation. Invoke-BackupSet calls it after the diff (step 8) and before Save-SupersededData (step 9.5), with the migration component checked before step 6; a refusal fails the set (entry-point status 1) and leaves the tree byte-identical. No new configuration key (SR-042's schema is closed).",TC-100;TC-101,Planned
```

### 3.4 test-cases.csv

```csv
TC-091,SR-049;LLR-049,Unit,Test,Smoke,"defect=set{flag-over-raw,flag-over-archive,name-lies,dangling-datapath}; sevenzip=present","REPRO-FIRST (red before any WP5 code): with 7-Zip present, each malformed row survives a full backup run untouched by Sync-BackupStorageLayout - the metadata-only comparison at Engine.psm1:529 leaves flag-over-raw and flag-over-archive rows byte-identical and reports the set as successful, and a Compressed=Yes-over-raw row whose configuration now says No produces only a logged ERROR while the set still succeeds. Manifests are re-stamped with Write-ManifestWitness after tampering so the intended failure is observed, not exit 3. Pester: Describe 'Sync-BackupStorageLayout trusts metadata over bytes (SR-049)'.",Yes,Draft
TC-092,SR-050;SR-049;LLR-050,Integration,Test,Full,"direction=set{compression-on-after-snapshot,compression-off-after-snapshot}; mode=set{Mirror,HashAddressed}","REPRO-FIRST for the WP4-surfaced latent defect, with NO tampering: run with compression off, supersede a file to create a snapshot, then re-run with compression on so only the backup root migrates. Before the fix, restoring that snapshot writes 7z container bytes under the original filename and exits 0; after the fix the restored bytes equal the original exactly and the exit is 0. The reverse flip, which before the fix exits 4 with a misfiled host-class cause, likewise restores byte-exact. Both restorers. In G9-Rollback plus a bats counterpart.",Yes,Draft
TC-093,SR-049;LLR-049,Unit,Test,Smoke,"mode=4-modes; scope=set{root,root+snapshots}; defect=set{each,clean}","The verification action reports one finding per disagreeing row across the backup root and every snapshot, mutates nothing (pre/post hash of every file in the tree, including MANIFEST.csv and its witness), and maps its outcome onto the SR-040 table: 0 clean, 1 findings, 2 precondition (missing manifest, -Deep without 7-Zip), 3 witness failure, 4 host. A clean backup in each of the four modes reports zero findings. Describe 'Storage-form verification reports without mutating (SR-049)'.",Yes,Draft
TC-094,SR-049;SR-024;SR-038;LLR-049,Unit,Test,Smoke,"action=repair; mode=4-modes","Repair mode makes every unambiguous finding agree, leaves the six logical columns byte-identical, re-stamps every rewritten folder's witness (Test-ManifestWitness = Verified for every pool manifest; Reconstruct.ps1 -RequireWitness exits 0 from each origin), never re-packs content (data-file payload hashes unchanged), and reports blank-row form disagreements without repairing them. A backup run immediately after a repair is idempotent (SR-024): its manifest rows are byte-identical to a run with no repair in between. Source guard: no verification or repair symbol is reachable from Invoke-BackupSet, and the repair path contains no Export-Csv and no direct Write-ManifestWitness call.",Yes,Draft
TC-095,SR-051;SR-002;LLR-051,Unit,Test,Smoke,"mode=set{Mirror,Mirror+Compress,HashAddressed,HashAddressed+Compress}; sharing=shared-datapath-split-decision","Two rows with identical content and different extensions share one DataPath; a configuration change that flips only one of them to 'wrong' must not delete the file the other still references: after the migration every manifest row resolves, the latest state restores byte-exact with exit 0, and the content is still stored exactly once per (hash,length) on the quiescent state. A forced transformation failure fails the backup set instead of being logged only. Describe 'Layout migration is refcount-safe (SR-051)'.",Yes,Draft
TC-096,SR-004;LLR-004,Unit,Test,Smoke,"ext=set{original-17,merged-8,unlisted}","Test-ShouldCompress returns false for every extension in the merged already-compressed list - the original seventeen plus .jar .tgz .zst .gif .webm .ogg .sav .pack - is case-insensitive, inspects the extension and not the path, and still returns true for compressible extensions including .docx and .txt (SN-003's acceptance line). Parity guard: the list is defined in exactly one place and its documented form in README/AGENTS matches it. Amends TC-002 rather than replacing it.",Yes,Draft
TC-097,SR-004;SR-012;SR-051;SR-049;LLR-051,Integration,Test,Full,"mode=4-modes; corpus=merged-extensions-plus-snapshots","The extension-list merge at scale: a compression-enabled backup seeded with .gif .webm .jar .tgz .zst .ogg .sav .pack content plus text, run to produce two snapshots on the pre-merge list, is re-run on the merged list. The triggered migration decompresses every affected root row, leaves no dangling reference, and afterwards EVERY state - both snapshots and the latest - restores byte-exact with exit 0 in both restorers; a third run is idempotent (SR-024) and the storage-form verification reports zero findings. Suite case G4.2.",Yes,Draft
TC-098,SR-050;SR-040;LLR-050,Unit,Test,Smoke,"direction=set{row-says-No-file-is-archive,row-says-Yes-file-is-raw}; origin=set{backup-root,snapshot}","Reconstruct.ps1: a blank-DataPath row whose only pool match is the opposite form restores the true original bytes and exits 0 in both directions; an archive candidate that cannot be expanded but whose raw bytes match (hash,length) is recovered rather than reported as a candidate error; a row with a non-blank DataPath is still resolved by its own Compressed column; genuinely missing content still exits 1 and a genuine host failure still exits 4. Describe 'Hash recovery trusts the located file's form (SR-050)'.",Yes,Draft
TC-099,SR-050;SR-031;SR-040;LLR-050,Unit,Test,Smoke,"direction=set{row-says-No-file-is-archive,row-says-Yes-file-is-raw}","bash/reconstruct.sh mirrors TC-098 exactly under bats: find_by_hash reports the located form, the restore loop consults it, byte-exact output in both directions, unchanged exit codes for content-missing and host classes, shellcheck clean. In tests/bash.",Yes,Draft
TC-100,SR-052;SR-013;LLR-052,Unit,Test,Smoke,"volume=set{backup,change}; fit=set{fits,does-not-fit}; migration=set{none,pending}","A backup set whose estimated additions exceed the destination volume's free space (induced by a stubbed free-space probe) refuses before any mutation: the backup root, change root and FileBackupState.json are byte-identical to before the run, the message names volume, required and free bytes, and the entry point reports a failed set. A set that fits proceeds unchanged, and a pending storage-layout migration is included in the estimate. Describe 'Backup capacity preflight refuses before mutating (SR-052)'.",Yes,Draft
TC-101,SR-052;SR-023;LLR-052;LLR-023,Unit,Test,Smoke,"platform=set{windows,linux}","Get-FreeSpaceBytes returns a plausible non-zero value for a drive-qualified Windows path and never throws for an unresolvable one; run inside the container against a rooted POSIX path it returns non-zero, and an inflated manifest length makes the containerized Reconstruct.ps1 abort with the SR-023 precondition code - the check that Split-Path -Qualifier silently skipped on Linux. Windows half in Pester, Linux half in the Docker CI job.",Yes,Draft
TC-102,SR-049;SR-048;SR-043;LLR-049,Integration,Test,Release,"action=set{verify,verify-repair}; outcome=set{clean,findings}","In-container: the verification action emits a parseable report and exits 0 on a clean backup while modifying nothing; against a seeded malformed row it exits non-zero per the SR-040 table; repair mode fixes it and a re-verify exits 0; the default backup action and a flags-only invocation remain byte-identical in behaviour (TC-060/TC-076/TC-088 re-run unchanged). Runs in the Docker CI job.",Yes,Draft
```

**Amendments to existing rows (not new ids):** LLR-004 (merged list, single
definition site, +TC-096); LLR-012 (refcount clause, +TC-095;TC-097, SR-Refs
+= SR-051); LLR-023 (Get-FreeSpaceBytes, +TC-101); TC-002 (note TC-096
supersedes list coverage; keep the extension-not-path property); IF-001
(SR-Refs += SR-049;SR-052; one sentence: container exposes `verify` /
`verify --repair` via the SR-040 table; a full destination refuses before
mutation); AGENTS.md §3 new invariant: *"A blank-DataPath row is resolved by
the form of the file hash recovery locates, never by the row's Compressed —
that column describes only a file in the row's own folder."*

## 4. Design — the Verify action

- **Surface:** `FileBackup.ps1 -Action Verify [-RepairStorage] [-Deep]
  [-IncludeSnapshots:$false] [-ExitCode]`, extending WP4's ValidateSet;
  entrypoint gains the positional word `verify`. `-VerifyStorage` kept as an
  alias so the disposition wording resolves. Engine exports
  Test-BackupStorageForm / Repair-BackupStorageForm.
- **Default scope: root + every snapshot** (the defect lives in snapshots);
  `-BackupRootOnly` for a fast pass.
- **Checks:** R1 name/flag (0 I/O), R2 physical form via the 6-byte 7z magic,
  R3 existence, R4 blank-row form via the shared hash-recovery predicate
  (each key resolved once per pool via Get-BackupContentIndex), R5 orphans,
  R6 `-Deep` payload identity (needs 7-Zip).
- **Report vs repair:** repair acts only where ground truth is a file in the
  row's OWN folder — rewrite Compressed from the observed form, rename so the
  name stops lying; never re-pack, never touch the six logical columns, never
  migrate layout. **Blank-row (R4) findings are reported, never repaired** —
  the "correct" value is location-dependent; the durable fix is SR-050.
  All persistence via Write-Manifest; the witness is never copied between
  folders.
- **Exit codes:** SR-040's table; findings = **1** (a content statement, not a
  usage error). Absent witness: warn-and-continue (the restore default —
  verify is non-destructive, so prune's inverse default doesn't apply).
- **Why not inside every migration:** Sync runs at step 6 of every run; R4/R6
  would add pool-wide scans and worsen failure semantics. Guard: TC-094's
  source-level assertion that no verify symbol is reachable from
  Invoke-BackupSet.

## 5. Design — the hash-recovery form fix (SR-050)

**Fix the restorers; do NOT teach Sync to migrate snapshots; verify is the
detector.** The row's Compressed describes only its own folder's file; the
locator has already proven the located file's form at zero cost; the fix is
~5 symmetric lines per restorer and closes both the silent (exit 0
corruption) and misclassified (exit 4) directions. Teaching Sync to migrate
snapshots cannot work (most snapshot rows are blank — nothing to migrate),
violates snapshot immutability (AGENTS §3), fights SR-024, and would be wrong
again at the next flip. Included extension (Q4): an archive candidate that
fails to expand is re-tested as raw bytes before CandidateError — makes
legacy finding-B artifacts recoverable, costs nothing on the happy path.

**Old kits in old snapshots — the honest statement:** the root kit is fixed
after one post-WP5 run and new snapshots carry it, but **every snapshot
created before the upgrade keeps its defective kit permanently** (including
copies moved off-volume). Therefore: (1) document the exact exposure in
README + AGENTS §4 (remedy: restore old snapshots with the root's current
kit, or run Verify); (2) the verifier reports each R4 finding with that
snapshot's kit revision (`# KitRevision: <n>` marker line in both restorers —
Q5); (3) opt-in **`-RefreshKits`** re-copies the current kit artifacts into
every snapshot folder — the only mechanism that retires the exposure; never
copies MANIFEST.csv.meta; never default-on (Q3, decision-dial HIGH flag).

**WP4's deferred -RepairFromPruned (§5.4):** the diagnosis half lands in WP5
(R3/R4/R5 findings + a -WhatIf-shaped statement of what a repair would do);
the byte-materialization half stays deferred (build it on WP4's plan/copy/
prove primitives once they are Verified; SR-050 removes the correctness
motive; no SN/SR yet). Record as a named Open-items row targeted WP6-or-later.

## 6. Ordered implementation plan

| Phase | Content |
|---|---|
| A — rebase onto WP4 | Confirm Get-BackupContentIndex/Test-PoolResolves/-Action dispatch as landed; extract WP4's phase-3 form predicate + WP5's R4 into ONE shared Test-StorageFormAgreement so prune and verify cannot drift. Re-run WP4's TC-083/084/089. |
| B — REPRO, RED | TC-091 (four malformed shapes survive Sync, incl. the swallowed-ERROR shape) + TC-092 (compression-flip repro, both restorers). Land failing/xfail-marked with the real red output pasted in status.md. Commit alone — the evidence that C and WP4 §5.7 are real. |
| C — SR-050 restorer fix (kit revision) | Form field in both locators, decompress decisions consult it, raw-fallback on failed expand. TC-092 goes green; TC-098/099; re-run TC-021/023, G3, all bats, shellcheck. Commit alone — THE data-integrity commit for review. |
| D — SR-051 refcount-safe migration | Retained-path filter in Phase 2, group-consistent transforms, failure → set failure. TC-095. Four-mode sweep. Commit alone. Must precede F. |
| E — SR-049 verify + repair | Get-StoredFileForm → Test-BackupStorageForm → Repair-BackupStorageForm → -Action Verify → entrypoint word. TC-091 goes green, TC-093/094. Two commits (engine, boundary). |
| F — ext-list merge | Add .jar .tgz .zst .gif .webm .ogg .sav .pack to Common's list. TC-096, TC-097 (the merge-triggered migration at scale). Commit alone, last of the storage-form items. |
| G — SR-052 capacity | Get-FreeSpaceBytes (Common), Reconstruct.ps1 rewire (fixes the Linux inert check), Assert-BackupCapacity + call sites. TC-100/101. Commit after C (shares the kit revision). |
| H — boundary/docs/registries | TC-102 in Docker job; README (verify + old-kit warning + merged list); AGENTS §2/§3/§4; arch-map regen; IF-001; status.md audit; flip rows C / ext-list / capacity / WP4-latent-defect; add -RepairFromPruned row. Full tier + Linux evidence pasted. |

Untouched by design: Optimize-ChangeFolders, Complete-ChangeFolder,
Save-SupersededData, the 9-column schema, the config schema.

## 7. Regression risks

- **SR-024:** the first post-merge run is by design non-idempotent (it
  migrates) — TC-097 asserts run2 ≡ run3, never run1 ≡ run2; TC-094 asserts
  post-repair idempotence; verify never runs inside Invoke-BackupSet.
- **TC-052/B6/SN-018:** enumerate only via Get-DataFile/
  Test-IsInfrastructureFile at each folder's own root; renames that would
  produce a root-level infra name are refused; nested MANIFEST.csv fixture.
- **TC-067:** all persistence via Write-Manifest; -RefreshKits copies the
  five kit artifacts and explicitly NOT the witness; source guard forbids
  Export-Csv / direct Write-ManifestWitness in WP5 code.
- **Four modes:** TC-093/094/095/097 four-mode; TC-092/098 two-mode × two
  origins (today only 2 migration assertions exist — G11).
- **Old kits:** never claim WP5 closes F3 for pre-existing snapshots restored
  by their own kit — it does not (§5).
- **Two-restorer drift:** TC-098/099 deliberate mirrors + the bash-interop CI
  job.
- **Find-DataFileByHash shape:** add Form, never remove/reorder — WP1's
  assertions keep passing.
- **Capacity refusal exit semantics:** per-set refusal is status 1 (a set
  failed), not 2 — other sets may have run. Asserted in TC-100.
- **Split-Path -Qualifier removal:** TC-040 re-run unchanged; TC-101 adds the
  Linux half that never worked.

## 8. Driver decisions on the planner's open questions (2026-08-22 — flagged for batch ratification)

1. **`-Action Verify` is the surface; `-VerifyStorage` an alias** — one
   dispatch; wording change recorded so disposition and code agree.
2. **Default scope includes snapshots**; `-BackupRootOnly` for the fast pass.
3. **Ship `-RefreshKits`, opt-in, never default** — the only mechanism that
   retires the old-kit exposure. *(Decision-dial HIGH item — flag in batch.)*
4. **Adopt the raw-fallback on failed expand** — free on the happy path,
   makes legacy finding-B artifacts recoverable.
5. **`# KitRevision: <n>` marker line** in both restorers; bump when any
   kit-bundled file changes.
6. **Adopt the eight extensions verbatim**; do NOT add Office extensions
   (SN-003's acceptance line is a stakeholder decision).
7. **G10 gets its own Open-items row immediately** — it is a live data-loss
   defect on Verified code, captured as SR-051, visible even if WP5 slips.
8. **No config key for capacity margin** — refuse when free < required;
   revisit only on operator request (schema is closed).
9. **Verify findings machine-readable (JSON) at the process boundary**, same
   pattern as WP4's snapshots action.
