# Requirements audit: current implementation and Rust migration

Review date: 2026-11-05. Baseline: branch `Rust-Rewrite`, commit `45c9a4d`.
Scope: the requirement registries, current backup and restore code, selected
test sources, checking scripts, container contract and layout rulings.

**The requirements cannot currently be treated as an implemented acceptance
baseline.** They combine a deliberately unfinished requirements rewrite with
contracts superseded by the bounded run loop and the single-store layout.
Some rows request additional behavior; making every row match the code would
silently discard those requests. This audit proposes dispositions and leaves
the normative registries and their approval statuses unchanged.

Read alongside the [user flow](backup-flow.md),
[Rust migration plan](plans/rust-migration.md),
[current project status](status.md), and the
[spine restructure gap map](plans/spine-restructure-gap-map.md).

## What was checked

| Artifact | Observed state |
|---|---|
| [Stakeholder needs](requirements/stakeholder-needs.toml) | 48 needs in TOML. |
| [System requirements](requirements/system-requirements.toml) | 123 rows; all `Drafted`. Requirement statements and acceptance criteria reviewed. |
| [Low-level requirements at audit time](plans/spine-rebaseline-2026-11-05/legacy/low-level-requirements.csv) | 87 rows: 25 Planned, 13 Implemented, 40 Verified, 9 Draft. Several still describe removed functions. |
| [Test-case registry at audit time](plans/spine-rebaseline-2026-11-05/legacy/test-cases.csv) | 240 records. A normal CSV dictionary reader sees 181 Pass, 53 Draft and 6 Yes in the Status column; the last six records have an extra field. These are registry values, not new test-run results. |
| [Interface registry at audit time](plans/native-design-2026-11-05/legacy/interfaces.csv) | One implemented IF-001 contract, with current layout text mixed with older kit wording. |
| [Performance budgets](requirements/performance-budgets.csv) | Only the PB-000 example; no enforceable budget records. |
| [Active gate](gate) | G3, despite the documented unfinished trace-tool migration. |

Reproduced checks on this checkout:

- `python scripts/trace.py --strict --require-verified --phase core,bash-v1,container-v1,kitbump-v6,ca-v1,fidelity-v1,robust-v1,form-v1,name-v1,probe-v1`
  exits **1**: `SN=0 SR=0 LLR=87 TC=240 orphans=499 integrity=0 status-findings=0 phase-deferred=0`.
  Zero status findings here is not evidence of verification: the SR loader read
  no system requirements.
- `python scripts/check_docs.py --ignore docs/test/report.md --ignore "docs/releases/*"`
  passed before these additions: 0 broken links and 28 existing orphan warnings.
- `pwsh -NoProfile -File scripts/gen_arch_map.ps1 -Check` passed for both
  generated documents.
- CSV record-width inspection found ten fields under the nine-column test
  header for TC-255 through TC-260.

After the documentation additions, link checking still passes with 0 broken
links and the same 28 existing orphan warnings. `git diff --check` passes. The
five generated blocks in AGENTS.md and architecture.md were compared with HEAD
and are unchanged. These checks do not validate Mermaid rendering or runtime
behavior.

No backup, prune or repair was run against a user store. Runtime suites were
not rerun: this environment exposes Pester 3.4, while the suite requires Pester
5. The 2026-11-05 entry in `status.md` records earlier results on `753d88b`
(999 Pester passes, 274 integration passes, 154 bats passes); those are
historical evidence, not results from this review.

## Priority findings

### A01 — The traceability gate reads the retired registry format

**High: verification tooling.** [trace.py](../scripts/trace.py) still loads
`system-requirements.csv` and the older needs representation. The actual top
tiers are TOML. This is already acknowledged in `status.md`; it is not a new
runtime regression. The old loader also cannot establish the new boundary and
assumption links.

Update the loader and schema checks to the approved spine shape, fail explicitly
when a required registry is absent or empty, and preserve draft status until
review and evidence justify promotion. Do not create a second authoritative
CSV copy or mark every row Verified merely to make G3 pass. Reconcile the active
gate with the actual phase of the rewrite.

### A02 — Old IDs, old symbols and malformed test records weaken trace evidence

**High: specification integrity.** A scan of `Implements:` lines in the two
modules, two PowerShell entry scripts and bash restorer found 17 referenced SR
IDs absent from the new registry. LLR parent references contain 22 absent SR
IDs; TC references contain 23. This is not proof those behaviors disappeared:
many were intentionally moved below the system tier.

Examples: hashing SR-002, compression SR-004, manifest SR-025, content addressing
SR-058 and name grammar SR-069 no longer have SR rows, although the code still
implements them. LLR-001 names `Update-SourceManifest` and
`Compare-SourceToBackup`; LLR-003 names `Invoke-BackupFileGroup`; LLR-052 names
`Assert-BackupCapacity`. Those functions are gone. LLR-017/080/088/091 retain
owner-marker and heartbeat machinery. Back-links also include `LLR-150`, which
has no row in the current LLR CSV.

TC-255..260 add separate description and outcome fields without extending the
header. Their parsed `Automated` becomes outcome prose, `Status` becomes `Yes`,
and `Pass` becomes an unnamed extra field. Correct the schema or combine those
fields, then make row-width mismatches a hard checker error. Reconcile links
through an explicit old-to-new disposition map, following the approved spine
design rather than restoring every retired SR ID.

### A03 — Source-side change-detection state has been removed

**High: superseded design.** SR-035, SR-093/094 and SR-139/140/148/149 describe a
source-root record or configurable external cache. `Invoke-LibraryCapture`
uses the latest backup manifest as its comparison record and warns that
`SourceStatePath` is unused. Nothing is written to the source. The setting is
accepted for compatibility and still influences exclusion of an old root-level
source manifest; it is not an active state destination.

Rewrite the cache-specific requirements around read-only source access and
backup-side state. Remove the source-write exception from SR-093. Retain an
explicit rule for legacy root-record exclusions in SR-074 so a user's nested
`MANIFEST.csv` remains data. Evidence:
[Invoke-LibraryCapture / Get-SourceFileList](../Modules/FileBackup.Engine.psm1)
and bounded-loop ruling R3.

### A04 — Restore witness and outcome requirements describe retired behavior

**High: superseded design.** SR-038 requires completeness evidence, SR-039
requires exit 3 for absent or mismatching evidence, and SR-043 describes a
shared distinct damaged-record outcome. Current restorers, kit revision 16,
ignore witnesses; from revision 14 they return `0/1/2/4`, precedence `2 > 4 > 1`.
They salvage complete rows before NUL damage and report at least 1. Atomic
manifest replacement prevents a process interruption from exposing a partially
written replacement; it does not detect every syntactically valid truncation
or substituted manifest.

Preserve the current restore contract in the new baseline, or explicitly
design and approve a new integrity protocol with both restorers. Do not claim
the old witness guarantee is still supplied. **Operation distinction:** prune
still checks an older witness in `Assert-PrunePrecondition`, and
`Get-PruneBatchExitCode` still includes 3 (`2 > 3 > 4 > 1`). Code 3 cannot simply
be deleted from every public operation's documentation. SR-040/043 need an
operation/version-specific outcome table. Related rows: SR-116/121/145 and the
damaged-record alternatives in SR-082/110.

Evidence: [Write-Manifest](../Modules/FileBackup.Common.psm1),
[PowerShell restore](../Reconstruct.ps1), [bash restore](../bash/reconstruct.sh),
and [prune preconditions](../Modules/FileBackup.Engine.psm1).

### A05 — Exclusion is an OS lock, with no stale-time or reclaim protocol

**High: superseded design and unsupported deployment.** SR-017/075 can still
express safe recovery outcomes, but their liveness-based interpretation and
SR-144's stale-claim takeover no longer describe the engine. Backup and
maintenance hold the never-deleted `Temp.lock`; process death releases the
handle. New-version `Incoming` and `Building_*` residue can then be discarded;
older `Temp` residue is warned about and left alone. There is no heartbeat,
owner identity or fencing token. SR-085's promise to name the holding operation
is therefore stronger than the diagnostic supplied.

Rewrite the lock requirements for the same-host/same-kernel deployment and
update the [assumptions](requirements/assumptions.toml) accordingly. Mark
SR-144 out of scope unless a separately designed multi-host protocol is wanted.
Keep all lock-open failures as refusal, the permanent lock pathname/inode, and
read-only operations' ability to proceed without a lock (SR-086/106/107).
Availability during mutation is not a promise of a transactionally isolated
read. SR-086's acceptance also assigns access-denied/unusable-lock failures to
2; the current engine treats all lock-open failures as busy/4. SR-107 retains
an unfinished-prune admission rule that must be reconciled with the current
residue/commit design. Evidence: `Enter-StagingOsLock`, `Clear-InterruptedRunResidue`,
[bounded loop](plans/bounded-run-loop.md), and
[lock tests](../tests/Unit/StagingOsLock.Tests.ps1).

### A06 — Empty-source refusal ignores the old allow-empty switch

**High: superseded policy.** SR-036 promises refusal 2 unless the owner enables
emptying. The engine accepts but ignores `AllowEmptySource`, and stops with 4
when a formerly populated source now appears empty. The early check prevents
publishing a snapshot; the later check handles empty-folder-only walks and a
source that disappears during capture. A first backup of an empty source is
allowed. Update SR-036 and LLR-036/TC-062 to that ruled policy. A mid-run stop
can retain already published checkpoints; “nothing changed” must not be
promised for every late stop.

Evidence: `Assert-SourceNotEmpty`, `Get-EmptySourceMessage`,
`Invoke-LibraryCapture`, and [BoundedRun tests](../tests/Unit/BoundedRun.Tests.ps1).

### A07 — Capacity promises exceed both backup and restore behavior

**High: superseded backup rule; stronger restore request.** SR-052 still
requires a pre-run demand estimate across sets and a no-write refusal. Backup
no longer estimates demand: a full-volume write stops the set with 4. The
one-mount requirement also removes its cross-volume superseded-copy case.

SR-023 requires expanded content plus overhead and scratch allowances. Both
restorers estimate only rows not marked compressed, exclude compressed rows
with a warning, and skip the check when free space cannot be measured. In
PowerShell, the target and log already exist before the capacity check;
extraction also needs target-volume scratch. Consequently SR-118/145's absolute
no-write admission promise is not fully supplied either.

Rewrite SR-052 to match bounded writes. For restore, either retain and document
the approximate estimate, or schedule improved admission as a separate feature
with both-script tests. Do not sell the current estimate as a guarantee that
restore cannot run out of space. Evidence: `Test-BackupDiskFull`,
`Reconstruct.ps1` capacity pre-check, and bash `main`.

### A08 — Recoverable checkpoints are not an atomic whole-run tree

**High: contract conflict.** SR-082 says the latest tree after interruption is
the tree before or after the run. `Invoke-LibraryCapture` publishes working rows
between files, combining captured rows with prior rows. The retained snapshot
preserves the old state; the checkpoint is an intermediate recoverable state.

Rewrite SR-082 to require every published row to resolve correctly, preservation
of the prior state, atomic individual manifest publication, and recovery on the
next run. Retain flush-before-publish for objects, manifests, state, kits and
prune copies. Process-kill tests do not establish arbitrary power-loss
durability on every filesystem. Evidence: checkpoint code,
[BoundedRun.Tests.ps1](../tests/Unit/BoundedRun.Tests.ps1),
[Durability.Tests.ps1](../tests/Unit/Durability.Tests.ps1), and DA-01.

### A09 — Link capture and recreation are proposed functionality

**High: unimplemented scope.** SR-137/150/151/152 require following selected
outside directory links, recording others and rebuilding them. The current
directory walk does not follow them, and neither manifest nor directory sidecar
records link targets. [README](../README.md#what-is-not-recorded--read-this-before-relying-on-a-restore)
explicitly excludes that fidelity. SR-001/074 also depend on the proposed policy.

Mark link preservation as deferred scope or plan a versioned record extension
and matching changes to both restorers. It cannot enter a Rust-only writer while
claiming compatibility with unchanged script kits.

### A10 — Upgrade support needs an explicit version window

**High: policy conflict / undefined scope.** SR-114 promises continuation of the
previous released store; the C44 rulings explicitly refuse old layouts and
require a fresh store. SR-115's current kit restores only supported layouts,
while older layouts retain their own kits. SR-123 needs a declared list of
supported older config versions: JSON v1/v2 are refused, v3 accepted. SR-135
requires a version in every form, but CLIXML remains unversioned.

Define a matrix for configuration versions, store layouts and kit revisions.
Clarify whether the pre-C44 layout was a released format; the audit cannot infer
that from branch history alone. Recommend Rust first support only the current
C44/L9 layout, while preserving old stores with their own original tools. Treat
CLIXML as a deliberate legacy adapter decision. Evidence:
[single-store rulings](plans/single-store-layout.md), configuration loader and
both restorers' root detection.

### A11 — Metadata problems do not currently fail an otherwise intact restore

**Medium: contract conflict.** SR-146 requires exit 1 for a missing or malformed
current directory record; the current restorers warn or ignore it and can
return 0. A missing sidecar is also valid for a tree needing no directory rows,
so its absence alone cannot identify loss. SR-065/122 describe useful existing
fidelity, but cannot imply mandatory metadata validation. Keep the advisory
policy or introduce explicit metadata-presence/version evidence in a separate
change. Evidence: `Restore-DirectorySidecar`, bash directory handling and
[RestoreFidelity tests](../tests/Unit/RestoreFidelity.Tests.ps1).

SR-066 similarly requires exit 1 for a blank or malformed file timestamp.
PowerShell's `Set-RestoredLastWriteTime` silently skips a blank value and warns
on a parse/set failure without incrementing unrestored counts. Reconcile the
timestamp failure policy together with the directory policy, rather than
promoting all of SR-066 because valid timestamps are correctly restored.

### A12 — Retry timing differs from the drafted total-wait budget

**Medium: contract conflict.** SR-067 and SR-090 bound total additional waiting
to 60 seconds per location. The implementation waits at least 60 seconds
between attempts for each file, with three attempts total; a persistently
unreadable file can require about 120 seconds of waiting by itself. There is no
global 60-second retry budget. Keep the current ruled behavior in the baseline,
or design a separately approved total deadline without accidentally dropping
earlier rows. Evidence: retry constants and `Invoke-LibraryCapture`.

### A13 — Logging does not guarantee a two-minute heartbeat

**Medium: partially implemented request.** SR-124 asks for named additions,
changes and removals plus category counts; current logs emphasize stored,
moved, kept and failed work, not a complete semantic per-path change ledger.
SR-125 promises progress at most 120 seconds apart during all phases. The
capture progress check runs between files; one large hash/compression or an
expensive listing/publication can exceed that interval. Either narrow these
claims or add timed progress callbacks and semantic change reporting. Evidence:
`Invoke-LibraryCapture`, `Write-RunMetric`, and `Invoke-BackupSet` summary.

SR-041 additionally requires part-failed status when superseded moves fail.
`Move-SupersededObject` warns and keeps the bytes available; the final set code
is based on not-captured entries and detected damaged objects. A move warning
alone does not supply SR-041's failure outcome. Keep this deliberate warning
policy explicit in the reconciled contract.

### A14 — The exact probe size boundary disagrees

**Medium: precise acceptance mismatch.** SR-081 says files **of 256 KiB or less**
use the extension list without measurement. `Resolve-CompressionDecision` uses
`Length < 262144` as the fallback: exactly 262144 is eligible for measurement.
The rest of the ordered compression policy is substantially present. Align the
wording to the current inclusive probe boundary, or explicitly change and test
that boundary; do not alter the default policy incidentally during the port.
Evidence: `Resolve-CompressionDecision`, `Resolve-GroupStorageForm`, and
[CompressProbe tests](../tests/Unit/CompressProbe.Tests.ps1).

### A15 — Cross-platform correctness needs a tested support matrix

**High for Rust release: coverage gap.** SR-031/033/071/092/136 ask for portable
restores, host continuation and collision handling. Existing bash portability
shims and corpus tests are valuable; they do not establish every target
filesystem's case and Unicode behavior. The engine now rejects case-only
source collisions, beyond SR-055's invalid-character wording. macOS recovery
requires the documented tools; a `.command` launcher does not make the default
shell/tool set sufficient. No native macOS CI lane is defined in
[tests.yml](../.github/workflows/tests.yml).

Add named platform/filesystem cases, target name-collision fixtures and
Windows-to-Linux-to-macOS continuation tests. Clarify that normalizing Unicode
or lowercasing manifest names would change identity. Retain exact names or
report them; never merge them. Acceptance of all SR-092/121/141 adversarial
cases remains unestablished by this review.

### A16 — The store layout and its recovery semantics need a formal contract

**High for Rust write compatibility: missing design detail.** The newest layout
is documented in plans, Common constants and LLR-095..098/TC-256..260, but not
coherently across the higher tiers. Capture one explicit, versioned design
contract for ConfigVersion 3; `CurrentBackup`; `BackupHistory/<date>`; latest
sharding versus flat history; `/` separators; a bare-name DataPath; name grammar;
six required kit files; root detection; one mount; and old-layout refusal.

Technical details such as xxHash128 canonical bytes, base-57 encoding and CSV
serialization belong in the design/interface layer if removed from SR. They
must not vanish from the port's acceptance criteria. Also state plainly that
a snapshot's **kit** is standalone but its **data** can depend on the whole
store. Evidence: Common's object-path/name functions, the
[layout plan](plans/single-store-layout.md) and both kit generators/readers.

### A17 — IF-001 contains a concrete root-detection error

**Medium: external contract drift.** The interface row names the new layout but
still calls the kit revision 15 and says the store is the origin folder's
parent for both latest and history. Revision 16 takes a history state's
**grandparent** as the store. It also mixes older launcher names and historical
behavior into the current contract. Separate the current contract from history;
preserve prune's legacy-witness outcome described in A04.

`status.md` explicitly records that HomeHub has not yet followed L9. Updating
this repository alone does not establish counterpart compatibility. Rust
packaging must retain IF-001's action words, environment variables, mount shape,
JSON output and operation-specific outcomes until a coordinated revision.

### A18 — Quantitative requirements have no enforceable budget evidence

**Medium: unverified acceptance targets.** SR-064/112/113 now specify up to
1,000,000 files, 2 TiB, 365 states, 4 GiB peak resident memory, eight-hour check
and restore limits, and a 30-minute bounded-change run. PB-000 is still the
only budget entry. The one-manifest-at-a-time change and production-shape unit
test are useful but do not prove these complete operation-plus-child-process
limits. A run still lists snapshot objects, so do not infer sublinear history
scaling merely because snapshot manifests are not read.

Create real budgets, reference hardware, repeatable corpora and measured
artifacts before any Verified promotion or Rust performance claim. Distinguish
cold/warm caches, raw/compressed objects, HDD/SSD/FUSE and checkpoint/flush cost.

### A19 — Redistribution and credentials need retained acceptance work

**Medium: evidence incomplete.** SR-131/143 require redistribution permission
and notices. No tracked LICENSE/NOTICE/COPYING-named file was found in this
checkout; `New-ReconstructScript` copies six runtime artifacts without a notice
artifact. This is an evidence gap, not a legal conclusion: inspect the DLL's
and image packages' actual terms/notices and complete the distribution record.

SR-128/129 rely on CLIXML credential handling and JSON's Credential ban.
These do not automatically transfer to a Rust JSON serializer or a different
mail library. Preserve the existing secure Windows path behind an adapter, or
define and test a replacement before claiming feature parity. No plaintext
credential migration should be inferred from this plan. Evidence:
[CredSetEx.ps1](../CredSetEx.ps1), configuration checks, `New-ReconstructScript`
and [Dockerfile](../Dockerfile).

### A20 — The optional space/media view is not fully specified by existing UI

**Medium: partial scope.** SR-097/098/099/147 describe a switchable space view,
ordering by space, explicit unavailable measurements and a record when it is
off. Current functionality is `BrowseView` plus the optional `MediaMBPerSec`
column and ffprobe calls during capture; measurement is not controlled by a
separate space-view feature switch. Missing measurements can be blank. Do not
equate an HTML browse index with all four acceptance claims. Define the intended
feature, or narrow the requirements to the delivered browse/metrics behavior.

### A21 — Same-second completed states lack distinct snapshot identities

**High: static defect candidate, needs a disposable-store regression.** SR-005
requires distinct identifiers for states completed within one second. Snapshot
names are derived from `LastBackupRun` using second precision.
`Publish-PriorStateSnapshot` treats any existing destination as an interrupted
run's snapshot and keeps it without checking that its state is the state now
being superseded. Distinct successful runs completed in the same second are
therefore not distinguished from a resume by this branch of the code.

Reproduce three changing runs with controlled subsecond completion times, then
assert that every distinct prior tree has its own restorable snapshot. Decide
a compatible identity/disambiguation rule before freezing the Rust contract;
do not carry over the old “collision-safe naming” history note as proof. This
finding is based on source inspection, not a newly executed data-loss repro.

### A22 — Check depth and repair scope are narrower than the drafted promises

**High: acceptance scope mismatch.** SR-049 says a check reports altered stored
content; ordinary Verify does not hash every payload. Same-length corruption
can require `-Deep`. SR-109 requires restoring a missing own-place object from
a proven pool copy while leaving its row's location unchanged. The current
audit/repair path is centered on storage-form corrections and setting aside
duplicate, damaged or misplaced objects; pool-based restore recovery is not
equivalent to that specified repair operation.

Declare shallow versus deep check guarantees and the actual certain repair
classes. Keep any broader re-homing repair as separate requested functionality.
Evidence: `Get-ListedObjectDamage`, `Get-StoredObjectVerdict`,
`Test-BackupStorageForm`, `Repair-BackupStorageForm` and the README Verify guide.

### A23 — Re-read schedules use calendar boundaries, not elapsed periods

**Medium: acceptance mismatch.** SR-011's acceptance says periodic schedules
become due once their period has elapsed since the last completed full re-read.
`Test-HashRecalcDue` compares calendar day, week, month and year boundaries. A
daily run just after midnight can be due minutes after the previous one; it
does not wait 24 hours. Preserve and document calendar semantics, or deliberately
change the policy and its deterministic vectors. Include the missing-last-hash
date and never/every-run choices in that review.

### A24 — Multi-set warning and aggregation contracts differ

**Medium: acceptance mismatch.** SR-095 requires no warning about several
locations, but `Import-BackupConfiguration` warns for multi-set JSON because it
is outside IF-001's one-set container contract, even though native use is
accepted. SR-014/043's acceptance says a mixed run with at least one completed
set reports 1 when another failed/refused. `FileBackup.ps1` always aggregates
by precedence `2 > 4 > 1`, so a successful set plus a refused set returns 2.

Reconcile the native multi-set promise with the container's narrower contract,
and retain the ruled precedence unless an explicit caller-contract change is
wanted. Do not substitute the drafted mixed-run rule during the Rust CLI port.

## Disposition of the remaining rows

The findings above cover the known contradictions and stronger promises. The
following rows have corresponding behavior in the inspected implementation and
remain candidates for evidence reconciliation. This is **not** a Verified
status, a complete execution of their permutations, or a replacement trace matrix.

| Family | SR IDs | Evidence to reuse or strengthen |
|---|---|---|
| File capture and deduplication | 001, 003, 011, 021, 024, 053, 055, 056, 088, 089, 091, 095, 096, 105, 108, 111 | Capture/index/copy functions; Common, Engine, BoundedRun and RestoreVerify unit sources; G1/G2/G6/G7. Subject to the exclusions, collisions and logging qualifications above. |
| History and safe mutation | 005, 007, 010, 041, 045, 046, 047, 049, 059, 061, 062, 063, 084, 100, 101, 102, 103, 104, 106, 107, 109, 110, 117 | Snapshot/prune/audit/kit/view functions; ContentIndex, StorageForm, View, lock and durability tests; G9/G10. SR-041's failure outcome and SR-110's damaged-record alternative need explicit reconciliation. |
| Recovery behavior | 008, 009, 029, 065, 066, 068, 072, 073, 118, 119, 120, 121, 122, 141 | Both restorers; RestoreFidelity, RestoreIndex, RestoreVerify, TargetContainment, RestoreLaunchers, bats, G3. See A04/A07/A11/A15 before retaining absolute acceptance wording. |
| Configuration and operation | 014, 015, 016, 018, 019, 027, 034, 042, 126, 127, 128, 129, 130, 132, 133, 134, 138, 142 | Entry point, dependency/configuration helpers, CredSetEx and container entry point; Engine/Coverage tests and container smoke. A stronger unconditional no-write promise or notification/tool-floor permutation still needs targeted evidence. |

## Recommended reconciliation order

1. Repair registry loading and TC record shape without changing acceptance
   outcomes. Add explicit format/empty-input checks. Produce a new trustworthy
   diagnostic report while leaving pending approvals visible.
2. Apply already ruled bounded-loop and layout changes to the requirements and
   assumptions. Update LLRs, test descriptions and back-links together; preserve
   ID history in dispositions. Correct IF-001's revision/root text with its
   counterpart work tracked separately.
3. Decide the stronger requests: link preservation, strict restore admission,
   metadata completeness, global retry budget, support windows, progress
   deadlines, same-second state identity and space-view behavior. Record each as retained, deferred or
   withdrawn with its reason. Do not implement them accidentally inside a
   language migration.
4. Approve a current-format compatibility contract and fixtures for the Rust
   plan. Retain independent PowerShell and bash recovery as a release gate.
5. Run the required existing suites on a provisioned host; add native macOS and
   quantitative evidence. Promote statuses only for requirements whose full
   acceptance is supported.

This change records an audit and migration proposal. It does not change backup
behavior, claim the requirements rewrite approved, or repair the existing
traceability tool in passing.
