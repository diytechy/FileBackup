# WP4 — Snapshot retention mechanism (Remove-BackupSnapshot): work order

Drafted 2026-08-22 by an independent Opus planning agent (read-only pass at
ba1ee48), adopted by the driver under the human's 2026-08-22 grind
authorization (batch ratification). Covers Open-items row **I** (re-ruled:
HomeHub owns retention *policy*, FileBackup owns the *mechanism*). Ids
allocated: **SN-029, SR-045..048, LLR-045..048, TC-081..090.** Driver
decisions on the open questions are in §5.

## 0. Findings that change the shape of the work

- **F1 — `Prune-Snapshot` cannot be the function name.** `PSUseApprovedVerbs`
  is active and `Prune` is unapproved — lint would fail. The exported
  function is **`Remove-BackupSnapshot`**; "prune" survives as the concept
  word in IF-001/status/README. IF-001's "planned `Prune-Snapshot` verb"
  sentence gets a one-word edit.
- **F2 — cross-folder references are always blank-DataPath.** A non-blank
  `DataPath` resolves inside its own folder with NO hash fallback (both
  restorers). So deleting snapshot S can only break blank-DataPath rows
  elsewhere, and those are location-agnostic: re-homing S's bytes anywhere in
  the surviving pool keeps every surviving manifest true without editing a
  row.
- **F3 — but "anywhere" is not enough, because of `Compressed`.** After a
  hash recovery the restorer branches on the ROW's `Compressed`, not the
  found file's form — a `.7z` found for a `No` row restores archive bytes
  under the original name. The hazard already exists after a compress-mode
  flip (Sync-BackupStorageLayout migrates only the backup root). Prune must
  not widen it and can detect it — hence explicit destination `DataPath`s.
- **F4 — pruning the OLDEST snapshot is usually free; the NEWEST is the
  expensive case** (Save-SupersededData parks superseded bytes in the newest
  snapshot; Optimize's keeper election is backup-root-first-else-newest). The
  mechanism exists precisely for the newest case → NO refuse-the-newest rail.
- **F5 — Optimize-ChangeFolders already contains the reference scan** (its
  `$globalMap`: "<hash>|<len>" → locations, root at FolderOrder -1, then
  snapshots in name order). Extract once, use twice.

## 1. Design

### 1.1 What gets re-homed

Pool = backup root + every `Snapshot_*` folder. Physical index P = every
non-blank-DataPath row whose file exists (Optimize's map construction, same
blank-guards). Demand set D = every row in a folder ≠ S with blank DataPath
OR a non-blank DataPath whose file is absent (defensive — Test-BackupManifest
can blank root DataPaths in a damaged store). Endangered set E = keys in D
whose every location in P lies inside S. Re-home exactly one file per key in
E (S's own copy). Everything else in S — content only S references plus S's
root-level infrastructure copies (`Test-IsInfrastructureFile -Root S`,
root-level only per B6/SN-018) — dies with S.

**Orphan check:** a data file in S unreferenced by S's own manifest is
unexplained bytes (the pipeline never creates one) → refuse by default
(exit 2, nothing mutated); `-DiscardUnreferencedData` opts in.

**Cost:** n+1 CSV reads, O(rows) hashtable inserts, one Test-Path per
non-blank row, no hashing — same order as one Optimize pass, which already
runs on every backup. Copy cost is 0 for the common oldest-first policy (F4).

### 1.2 Destination rule and the one row edited per file

**Re-home to where Optimize would have elected the keeper had S never
existed:** backup root if the root manifest demands the key, else the newest
surviving snapshot that demands it. (Makes the next Optimize pass a no-op;
matches the restorers' newest-first search; guarantees the destination
already holds a manifest row for that content.)

At destination T, the demanding row gets `DataPath` ← synthesized name,
`Compressed`/`StoredAsHashSize` ← copied from S's row (the physical form
travels with the bytes; never re-pack). The six logical columns
(RelativePath, Length, LastWriteTimeStr, xxH2Hash, Duplicate, MediaMBPerSec)
are untouched; no row added/removed/reordered. This avoids orphan bytes
(no per-run WARNs, no GC bait), closes F3 for that row, and makes resume
trivially checkable. Name synthesis mirrors Invoke-BackupFileGroup /
Sync-BackupStorageLayout driven by S's form: `Get-HashSizeFileName` when
StoredAsHashSize='Hash' ('.7z' ext when compressed, else RelativePath's),
else RelativePath (+'.7z' when compressed). **Refuse (exit 2) if the
synthesized name would classify as root-level infrastructure at T** (it
would be invisible to Find-DataFileByHash's root-level skip).

Every touched manifest is rewritten through **Write-Manifest** (never bare
Export-Csv) so the SR-038 witness is re-stamped. Other demanding manifests
keep their blank rows and hash-recover as before.

Rejected alternative (zero manifest edits, copy at S-relative path):
unreferenced pool bytes, F3 left open, completion undecidable.

### 1.3 Transaction (invariant: the pool goes redundant, then S disappears — never deficient)

```
Phase 0  PREFLIGHT (no mutation): rails (§1.5), read manifests + witnesses,
         build P/D/E + plan, capacity + orphan checks. -WhatIf stops here.
Phase 1  MATERIALIZE: Copy-Item S-file -> <dest>/<name>.fbprune.tmp (same
         volume), verify, Move-Item -Force -> final name (atomic rename).
Phase 2  PUBLISH: Write-Manifest each touched destination folder (re-stamps
         its witness). Pool now redundant.
Phase 3  PROVE: rebuild the index over pool minus S; assert EVERY surviving
         row resolves — non-blank: file exists in its own folder, form
         matches Compressed; blank: key present AND located file's form
         matches the row's Compressed (F3 guard). Any failure → ABORT,
         S intact, nothing lost.
Phase 4  COMMIT+DELETE: Rename-Item Snapshot_<d> -> Pruning_Snapshot_<d>
         (COMMIT POINT — fails the ^Snapshot_ pattern used by
         Reconstruct.ps1, reconstruct.sh AND Optimize, so one atomic rename
         removes it from every consumer's view), then Remove-Item -Recurse.
```

Copy verification: stored-form identity always (length + Get-FileXxHash
dest==source); content identity by default (raw: hash==row xxH2Hash at
Length; .7z: expand-to-temp and hash — exactly Find-DataFileByHash's check);
`-SkipContentVerify` weakens. Compressed plan without 7-Zip → exit 2 before
any mutation.

Half-pruned states are all harmless or loud: `*.fbprune.tmp` is skipped or a
correct raw recovery source; a final-named unreferenced file is a WARN-only
orphan until resume; the Write-Manifest crash window is the documented exit-3
stale-witness refusal on that folder only; `Pruning_*` is invisible to all
consumers. **Resume = run it again**: no journal (rejected — a second source
of truth that can itself be stale); the plan is recomputed from disk; entry
sweep finishes `Pruning_*` deletions and removes `*.fbprune.tmp`.

Concurrency: prune holds `<ChangeRoot>/Temp` (with a `PRUNE.inprogress`
marker) for its duration — a concurrent backup aborts on the existing SR-017
stale-staging guard with zero new code in the backup path; prune symmetrically
refuses when Temp exists.

### 1.4 Interface

```powershell
Remove-BackupSnapshot     # Engine, exported
    -BackupRoot <string> -ChangeRoot <string> -Name <string[]>  # no wildcards
    [-SevenZipPath <string>] [-SkipContentVerify]
    [-AllowUnverifiedIndex] [-DiscardUnreferencedData]
    [-NonInteractive] [-Log <scriptblock>]
    # CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')
Get-BackupSnapshot -BackupRoot -ChangeRoot   # read-only inventory
```

- `-WhatIf` = full preflight; prints per-snapshot {Name, Date, Rows,
  PhysicalBytes, BytesReclaimed, BytesReHomed, ReHomeDestinations,
  Refusals}; mutates nothing; returns the classification the real run would.
- `ConfirmImpact='Medium'` — never prompts at the default preference
  (automation-safe); `-Confirm` still available interactively.
- **Explicit names only** — no -KeepLast/-OlderThan (that is policy =
  HomeHub's). Multiple names oldest-first, each an independent atomic
  transaction; batch outcome = worst code, precedence 2 > 3 > 4 > 1.
- **Exit codes: SR-040's table verbatim** — 0 pruned; 1 batch incomplete,
  NO DATA LOST (message must say so); 2 usage/precondition (nothing
  mutated); 3 witness failure (nothing mutated); 4 host I/O (retriable,
  aborted before the commit point).
- **No bash prune** — reconstruct.sh stays restore-only; prune must re-stamp
  witnesses and bash has no writer; pruning is never required to restore.
  Stated in the SR rationale and IF-001.

### 1.5 Safety rails

- Refuse newest? **No** (F4). Refuse last/only? **No** (retention-to-zero is
  legitimate).
- **Witness: verify every pool manifest.** Mismatch/unparseable → exit 3.
  **Absent → refuse by default**, `-AllowUnverifiedIndex` overrides — the
  deliberate inverse of the restore default: restoring against an unverified
  index is recoverable; deleting against one is not.
- **Require the SR-035 run-state gate.**
- **Pool already broken → refuse (exit 2)** naming the unresolvable rows.
  (`-RepairFromPruned` healing deferred — §5.4.)
- **F3 form disagreement → refuse (exit 2)** — prune doubles as a detector
  for the finding-C family and hands WP5 a repro.
- Containment: `^Snapshot_` name, direct child of resolved ChangeRoot,
  normalized path check, no wildcards. Capacity preflight per destination
  volume (mirrors SR-023).

### 1.6 IF-001 / HomeHub boundary

`container/entrypoint.sh` dispatches on `FILEBACKUP_ACTION` (default
`backup`) or a leading positional word in {backup, prune, snapshots};
anything starting with `-` passes through exactly as today (TC-060/TC-076
unaffected). `prune` → `FileBackup.ps1 -Action Prune -Snapshot <name>[,...]
[-WhatIf]` (FILEBACKUP_SNAPSHOT / FILEBACKUP_DRY_RUN mapped); `snapshots` →
`-Action Snapshots` (JSON inventory on stdout). Paths come from the mounted
config; one-set-per-invocation makes "the set" unambiguous. HomeHub runs
retention as a separate one-shot invocation per directory.

IF-001 Contract addition (SR-Refs += SR-045;SR-046;SR-047;SR-048):

> Retention: HomeHub owns the policy, FileBackup owns the mechanism. HomeHub
> must never delete a `Snapshot_*` folder directly — dedup means one
> snapshot's bytes can be the only physical copy other snapshots recover by
> hash. The container exposes `snapshots` (read-only inventory: name, date,
> row count, physical bytes, and bytes-reclaimed-if-pruned, which only
> FileBackup can compute because of dedup) and `prune --snapshot <name>
> [--dry-run]`, which re-homes still-referenced bytes into the surviving
> pool, proves every surviving manifest still resolves, and only then deletes
> the folder. Prune reports through the same table as backup and restore:
> 0 pruned / 1 batch incomplete but no data lost / 2 usage or precondition
> (nothing mutated) / 3 manifest-witness verification failed (nothing
> mutated) / 4 host I/O failure, retriable — precedence 2 > 3 > 4 > 1. There
> is no bash prune: reconstruct.sh stays restore-only and pruning is never
> required in order to restore.

NagLight translation: 0 ok; 1 warn (partial, no data lost, retry); 2 error,
do not retry; 3 error, ESCALATE (a backup-integrity alarm, not a retention
alarm); 4 warn + retry.

## 2. Registry rows

### 2.1 stakeholder-needs.md — Core needs table (one row)

```
| SN-029 | Remove old snapshots to bound backup growth, **without ever destroying content a surviving snapshot still needs** — and be told, before removing anything, what each removal would actually reclaim. | Snapshot retention is unbounded today, so the backup volume eventually fills. But snapshots share bytes: a folder that looks like old history can hold the only physical copy of content other snapshots recover by hash, so deleting it from outside the tool is silent data loss. The wrapper that decides *what* to keep needs the tool to do the *removing* — and needs real reclaim numbers, which only the tool can compute because of dedup. *(HomeHub cross-check finding I, re-ruled 2026-08-21.)* | M | Asking the tool to remove a named snapshot leaves every remaining dated state — and the latest state — restorable byte-exact in all four storage modes, including when the removed folder held the only copy of shared content; a dry run first reports the same reclaim figure the real removal achieves; anything that would lose content is refused before a single byte is touched, with a distinct exit status; a run interrupted at any point loses nothing and can simply be run again. |
```

### 2.2 system-requirements.csv — the planner's verbatim rows, apply as-is

- **SR-045** "Snapshot pruning re-homes still-referenced bytes before
  deletion" — SN-Refs `SN-029;SN-004;SN-006;SN-002`; Requirement: the §1.1/1.2
  mechanism verbatim (identify endangered (xxH2Hash,Length) keys whose only
  surviving copy lies in S; copy byte-for-byte into the elected destination
  BEFORE deleting S; point that destination row at the file adopting the
  source row's Compressed/StoredAsHashSize; every rewrite via Write-Manifest;
  only DataPath/Compressed/StoredAsHashSize ever change, no row
  added/removed/reordered; correct in all four modes; never re-pack).
  AcceptanceCriteria per §1 (byte-exact restores of every surviving state in
  all 4 modes; re-homed content hashes to row values; column-diff confined to
  the storage-form triple; every rewritten witness verifies; no-op prune
  copies nothing). Permutations
  `mode=set{Mirror,Mirror+Compress,HashAddressed,HashAddressed+Compress};
  target=set{oldest,middle,newest,only};
  demand=set{snapshot-blank-row,backup-root-blank-row,none}`. M,Test,Draft,
  phase core.
- **SR-046** "Snapshot pruning is transactional and refuses loudly" —
  SN-Refs `SN-029;SN-013;SN-025;SN-026`; the §1.3 ordering + §1.5 refusal
  set, each refusal with its SR-040 code (precedence 2 > 3 > 4 > 1), Temp
  mutual exclusion, journal-free idempotent resume, -WhatIf full-preflight
  contract. Permutations
  `phase=set{after-copy,after-manifest,after-commit-rename};
  refusal=set{witness-mismatch,witness-absent,run-state,staging-busy,bad-target,unreferenced-data,broken-pool,form-mismatch,capacity,no-7zip};
  mode=set{Mirror,HashAddressed}`. M,Test,Draft, phase core.
- **SR-047** "Snapshot inventory with dedup-aware reclaim figures" — SN-Refs
  `SN-029;SN-011;SN-026`; the §1.4 Get-BackupSnapshot record set
  ({Name,Date,Rows,PhysicalBytes,BytesReclaimed,BytesReHomed}), computed from
  pooled manifests, mutating nothing, objects in-process + one JSON document
  at the process boundary. Permutations `snapshots=set{1,3};
  sharing=set{none,shared-with-root,shared-between-snapshots};
  mode=set{Mirror,HashAddressed}`. S,Test,Draft, phase core.
- **SR-048** "Retention is invocable at the container boundary" — SN-Refs
  `SN-029;SN-024;SN-011;SN-026`; the §1.6 entrypoint dispatch
  (FILEBACKUP_ACTION default backup / positional word / '-' pass-through),
  FileBackup.ps1 -Action/-Snapshot, SR-040 codes under -ExitCode, explicit
  "no prune in bash/reconstruct.sh" clause. Permutations
  `action=set{backup,prune,snapshots,legacy-flags-only};
  outcome=set{clean,unknown-snapshot,dry-run}`. S,Test,Draft,
  **Phase=container-v1**.

### 2.3 low-level-requirements.csv

- **LLR-045** → SR-045; Module FileBackup.Engine; CodeSymbols
  `Remove-BackupSnapshot;Get-SnapshotPrunePlan;Copy-ReHomedDataFile`; Detail:
  plan object {Key, SourceFullPath, SourceRow, DestinationFolder,
  DestinationDataPath, Compressed, StoredAsHashSize, Bytes} per endangered
  key; destination election mirroring Optimize; name synthesis from the
  SOURCE row's form via Get-HashSizeFileName / RelativePath(+'.7z');
  infrastructure-name refusal at the destination; copy to
  `<dest>.fbprune.tmp` with -LiteralPath, verify, Move-Item -Force; row
  mutation in place; persist via Write-Manifest never Export-Csv. TestRefs
  `TC-081;TC-082;TC-085;TC-086;TC-090`.
- **LLR-046** → SR-046;SR-035;SR-039; CodeSymbols
  `Remove-BackupSnapshot;Assert-PrunePrecondition;Test-PoolResolves;Complete-PruneDeletion`;
  Detail: the full rail set (witnesses via Test-ManifestWitness, Absent
  refused unless -AllowUnverifiedIndex; Read-BackupState + SR-035 condition;
  Temp absence; ^Snapshot_ + containment; unreferenced-bytes check via
  Get-DataFile vs own manifest; capacity; 7-Zip when needed) throwing
  classified {Code,Message} on the SR-040 codes; Test-PoolResolves rebuilds
  the index minus the target and checks resolution + form agreement;
  Complete-PruneDeletion renames to `Pruning_<name>` (fails
  $Def.ChangeFolderRegex and both restorers' patterns) as commit point, then
  deletes; entry sweep of `Pruning_*` + `*.fbprune.tmp`; Temp +
  PRUNE.inprogress held for the duration, removed in finally. TestRefs
  `TC-083;TC-084;TC-085`.
- **LLR-047** → SR-047;SR-026;SR-045; CodeSymbols
  `Get-BackupContentIndex;Get-BackupSnapshot;Optimize-ChangeFolders`; Detail:
  literal lift of Optimize's inline map ('<hash>|<len>' →
  {LocationType,Folder,DataPath,FullPath,IsBackup,FolderOrder}, root at
  FolderOrder -1 then snapshots in name order, skipping blank
  DataPath/blank hash/missing files) into one exported helper; Optimize
  refactored to consume it byte-identically; Get-BackupSnapshot joins index +
  snapshot manifests; BytesReHomed reuses Get-SnapshotPrunePlan so reported =
  actual by construction. TestRefs `TC-087;TC-089`.
- **LLR-048** → SR-048;SR-043; Modules FileBackup.ps1;container/entrypoint.sh;
  Detail: `[ValidateSet('Backup','Prune','Snapshots')]$Action='Backup'` +
  `[string[]]$Snapshot`; resolve the single set via Import-BackupConfiguration
  + Resolve-BackupSetPaths; dispatch to Remove-BackupSnapshot (-WhatIf
  through) or Get-BackupSnapshot | ConvertTo-Json; SR-040 codes under
  -ExitCode; entrypoint reads FILEBACKUP_ACTION or shifts a leading
  positional word, '-' args flow to "$@" unchanged; FILEBACKUP_SNAPSHOT /
  FILEBACKUP_DRY_RUN map to -Snapshot/-WhatIf; bash/reconstruct.sh not
  modified. TestRefs `TC-088`.

### 2.4 test-cases.csv (Expected texts per the summaries below; all Automated=Yes, Status=Draft)

- **TC-081** (SR-045;LLR-045, Integration, Full,
  `mode=all-four; demand=set{snapshot-blank-row,backup-root-blank-row}`):
  re-home to the elected destination with adopted form; every remaining state
  restores byte-exact exit 0 in all four modes; re-homed content hashes to
  the row's values. Describe 'Prune re-homes the last copy before deleting
  (SR-045)'.
- **TC-082** (SR-045;SR-028;SR-010;LLR-045, Integration, Full): TC-049's
  delete/reintroduce-identical/delete-again timeline extended with prunes of
  the keeper snapshot then an older one; content exists exactly ONCE on
  quiescent states; all states restore; reverse (oldest-first) order copies
  zero bytes. In G9-Rollback.
- **TC-083** (SR-046;LLR-046, Integration, Full): interrupt at each phase
  boundary; every state still restores; residue invisible to both restorers;
  re-invocation completes and sweeps; no journal. Describe 'Prune is
  idempotent and resumable (SR-046)'.
- **TC-084** (SR-046;SR-035;SR-039;SR-040;LLR-046, Unit, Smoke): ten induced
  refusals each returning its documented code (3 for the witness pair, 2 for
  the rest, 4 for induced copy I/O) with a recursive file-hash-identical
  tree; -AllowUnverifiedIndex and -DiscardUnreferencedData convert their
  refusals to warned successes; tampered manifests re-stamped so the intended
  failure is observed. Describe 'Prune refuses before mutating (SR-046)'.
- **TC-085** (SR-046;SR-038;SR-045;LLR-045;LLR-046, Unit, Smoke): after
  prunes re-homing into root and into a snapshot, Test-ManifestWitness =
  Verified for EVERY pool manifest and Reconstruct.ps1 -RequireWitness exits
  0 from each origin; AST/source guard: no Export-Csv and no direct
  Write-ManifestWitness call in the prune path. Describe 'Prune re-stamps
  every manifest it rewrites (SR-038)'.
- **TC-086** (SR-045;SR-005;SR-010;LLR-045, Unit, Smoke, all four modes):
  before/after column-wise manifest comparison — row sets identical; the six
  logical columns unchanged everywhere; only DataPath/Compressed/
  StoredAsHashSize differ and only in planned rows. Describe 'Prune changes
  only the storage-form columns (SR-045)'.
- **TC-087** (SR-047;LLR-047, Unit, Smoke): BytesReclaimed equals the
  measured change-root size drop after actually removing each snapshot;
  BytesReHomed equals measured copied bytes; the report itself modifies
  nothing (pre/post hash of every file); JSON parses to one object per
  snapshot with all six fields. Describe 'Snapshot inventory reports true
  dedup-aware reclaim (SR-047)'.
- **TC-088** (SR-048;SR-043;SR-034;LLR-048, Integration, Release,
  in-container): snapshots action emits parseable JSON exit 0 modifying
  nothing; prune of a valid name exits 0 with every remaining state
  restoring byte-exact in-container; unknown name exits 2 tree unchanged;
  dry-run exits 0 changing nothing; default action and flags-only invocation
  byte-identical to today (TC-060/TC-076 re-run unchanged); grep guard: no
  removal path in bash/reconstruct.sh. Runs in the Docker CI job.
- **TC-089** (SR-026;SR-045;LLR-047, Unit, Smoke): regression pin for the
  index extraction — Optimize's post-conditions identical before/after the
  refactor (backup copy always keeper; newest snapshot wins absent a root
  copy; no backup-root file deleted; removed files' rows blanked); TC-049's
  stored-exactly-once holds. Describe 'Optimize-ChangeFolders is unchanged by
  the shared index (SR-026)'.
- **TC-090** (SR-045;SR-046;LLR-045, Integration, Full): prune at every
  timeline position in a four-snapshot timeline — oldest copies zero bytes;
  newest re-homes its superseded bytes; middle and sole-remaining both
  succeed; every case leaves each remaining state restorable and exactly one
  physical copy per live (hash,length); no refusal for newest or last.
  Describe 'Prune at every timeline position (SR-045)' in G9-Rollback.

The normative content, summarized:

- **SR-045** (mechanism): re-home last-copy bytes to the elected keeper
  destination before deletion; adopt source row's form at the destination
  row; only DataPath/Compressed/StoredAsHashSize ever change in any
  manifest; all rewrites via Write-Manifest; correct in all 4 modes; never
  re-pack. Verified by TC-081 (re-home + restore across 4 modes),
  TC-082 (TC-049's adversarial timeline extended with prunes; content stored
  exactly once on quiescent states; oldest-first prunes copy zero bytes),
  TC-086 (column-wise manifest diff confined to the storage-form triple),
  TC-090 (prune at every timeline position incl. newest and only).
- **SR-046** (transaction + refusals): the phase ordering above; idempotent
  journal-free resume; the full refusal set each with its SR-040 code and a
  byte-identical tree on refusal; kill-at-each-phase-boundary recovery;
  -WhatIf reports what the real run then achieves; Temp mutual exclusion.
  Verified by TC-083 (interrupt/resume), TC-084 (ten induced refusals,
  tree byte-identical), TC-085 (every rewritten manifest's witness verifies;
  AST guard: no Export-Csv / no direct Write-ManifestWitness in the prune
  path).
- **SR-047** (inventory): Get-BackupSnapshot emits {Name, Date, Rows,
  PhysicalBytes, BytesReclaimed, BytesReHomed} per snapshot, dedup-aware,
  mutating nothing; objects in-process, JSON at the boundary. Verified by
  TC-087 (reported reclaim equals measured reclaim; no file modified).
- **SR-048** (container boundary, Phase=container-v1): entrypoint action
  dispatch (backward-compatible), FileBackup.ps1 -Action/-Snapshot, SR-040
  codes under -ExitCode, no bash prune (grep/AST guard). Verified by TC-088
  (in-container actions incl. unknown-snapshot exit 2 and dry-run;
  legacy invocations byte-identical behavior).
- **LLR-047 / TC-089**: Get-BackupContentIndex extracted from
  Optimize-ChangeFolders as a literal lift; TC-089 pins Optimize's
  post-conditions before the refactor lands.

## 3. Ordered implementation plan

- **Phase A — index extraction, zero behavior change.** TC-089 lands FIRST as
  the regression pin; then the literal lift of Get-BackupContentIndex;
  Optimize consumes it; full tier re-runs incl. TC-049. Commit alone (the
  only step touching Verified data-destroying code).
- **Phase B — planning + inventory (pure/read-only):** Get-SnapshotPrunePlan,
  Get-BackupSnapshot; TC-087.
- **Phase C — rails:** Assert-PrunePrecondition, Test-PoolResolves; TC-084.
- **Phase D — the transaction:** Copy-ReHomedDataFile,
  Complete-PruneDeletion, Remove-BackupSnapshot as a short ordered list of
  named steps; TC-081, TC-085, TC-086, TC-090.
- **Phase E — adversarial + resume:** TC-082 (extend G9-Rollback), TC-083.
- **Phase F — boundary:** FileBackup.ps1 -Action/-Snapshot, entrypoint
  dispatch, TC-088, README, IF-001 rewrite, AGENTS.md §2 module-map row + §3
  invariant ("a Snapshot_* folder is removed only by Remove-BackupSnapshot,
  which re-homes last-copy bytes first"), arch-map regen, status.md audit,
  flip Open-items row I.

Untouched by design: FileBackup.Common.psm1, Reconstruct.ps1,
bash/reconstruct.sh.

## 4. Regression risks

- **TC-049 "stored exactly once":** re-homing temporarily creates a second
  copy (phases 1–4); post-delete it returns to one; an aborted prune leaves
  two until re-invoked — the property is asserted on QUIESCENT states, and
  the next Optimize pass collapses the duplicate (self-healing; assert in
  TC-082).
- **SR-005 supersession:** prune never touches FileBackupState.json; its only
  rename moves OUT of the Snapshot_ namespace; TC-084 asserts the state file
  byte-identical after refusals.
- **SR-026 / Optimize keeper election:** TC-089 lands before the refactor;
  literal lift; four-mode sweep after.
- **Witness (SR-038):** prune never copies MANIFEST.csv.meta between folders
  (the TC-067 "most dangerous mistake"); every rewrite via Write-Manifest;
  TC-085 pins both halves.
- **B6/SN-018:** Test-IsInfrastructureFile at the correct root in both
  directions; destination-name refusal; a nested MANIFEST.csv in TC-082's
  fixture.
- **F3:** explicit DataPath + form adoption; phase-3 form check; refuse on
  disagreement.
- **Suites enumerating the change root:** filter by $Def.ChangeFolderRegex;
  grep suites for bare Get-ChildItem -Directory during phase E.

## 5. Driver decisions on the planner's open questions (2026-08-22 — flagged for batch ratification)

1. **Function name `Remove-BackupSnapshot`** (`Prune` fails approved-verbs
   lint); "prune" stays the concept word; IF-001 gets the one-word edit.
2. **Absent witness on the destructive path: refuse by default**,
   `-AllowUnverifiedIndex` to override — deliberate inverse of the restore
   default; backups predating WP1 need the flag. *(Decision-dial HIGH item —
   flag prominently in the ratification batch.)*
3. **Unreferenced bytes in the target: refuse by default**,
   `-DiscardUnreferencedData` to override (no hashing them into the plan, no
   silent discard).
4. **`-RepairFromPruned` deferred to WP5** (belongs with finding C's repair
   story); WP4 refuses on a broken pool.
5. **One SN (SN-029)** covers mechanism + inventory.
6. `Get-BackupSnapshot` naming accepted (PSUseSingularNouns is excluded).
7. **Latent defect recorded as a new Open-items row (→ WP5):** a
   blank-DataPath row whose `Compressed` disagrees with the .7z-ness of the
   file hash recovery locates restores archive bytes under the original
   name — reachable today after a compression-mode flip because
   Sync-BackupStorageLayout migrates only the backup root, never snapshots.
   WP4's phase-3 check makes prune a detector; WP5 inherits the repro.
