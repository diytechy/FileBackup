# Design gaps

All design rows are Drafted. These are static comparisons against the permitted code inputs, not executed test results. A gap names the required outcome and the differing implementation; a grouped gap can require changes in both restore routes. Code symbols appear here for build navigation, never in design carriers.

## G-01 — Source-root exclusions exceed the declared domain

SR: SR-001, SR-074. Design: LLR-001, LLR-022, LLR-078.

Get-DataFile in Modules/FileBackup.Engine.psm1 applies the whole backup infrastructure allowlist when the cache is at the source root. With external cache, Update-SourceManifest bypasses that helper and also bypasses its volume-root pseudo-folder/error filtering. Restrict exclusions by source role and apply the volume exception in both branches.

## G-02 — Links are neither classified nor reconstructed

SR: SR-137, SR-150, SR-151, SR-152. Design: LLR-105, LLR-106, LLR-107.

The recursive source enumeration has no outside-target traversal policy, ancestor stack or link records; README explicitly says links are not followed or recorded. Neither restorer applies link metadata. Add bounded external traversal, internal/owned-location recording and last-phase reconstruction.

## G-03 — The cache has no source/store generation binding

SR: SR-035. Design: LLR-113.

Update-SourceManifest reads cached rows and reuses identity on matching size/time without verifying a cache generation or ownership. Read-BackupState separately refuses malformed run state or missing completion time with populated backup rows. These guards do not implement the required cache reconstruction/reporting from authoritative backup state.

## G-04 — Reread cadence is calendar-based and incomplete scans can advance it

SR: SR-011, SR-105. Design: LLR-011, LLR-028.

Test-HashRecalcDue compares date/week/month/year boundaries and returns true for missing history before testing N. Invoke-BackupSet stamps LastHashRun whenever recalc is true after the scan path, including a scan reporting unreadable directories. Use elapsed periods and successful full-reread completion.

## G-05 — Retry does not cover the initial content read

SR: SR-067, SR-089, SR-091. Design: LLR-001, LLR-067.

Update-SourceManifest calls the hasher directly without a per-file retry/catch; the bounded attempt rounds are later in Invoke-BackupFileGroup. A locked file needing a new digest can abort the set before the group retry/frozen-row behavior is available. Apply the bound to identity acquisition and continue independent files.

## G-06 — Directory-only changes do not cause a saved state

SR: SR-005, SR-065. Design: LLR-005, LLR-065.

Snapshot completion is driven by Compare-SourceToBackup’s file-row diff. Directory metadata is separately written, and there is no directory/link-state comparison in the publication decision. Include metadata identity in state-change detection so old empty-folder states survive. Timestamp-only file changes are already compared and are not this gap.

## G-07 — Restore capacity omits expanded content and runs after target mutation

SR: SR-023, SR-145. Design: LLR-023, LLR-102.

Both legacy capacity paths count raw rows only. Reconstruct.ps1 creates the target and log before its capacity calculation; it also checks the archive dependency later. Add the declared allocation/metadata/scratch allowance, all expanded lengths and one pre-write admission barrier.

## G-08 — Backup capacity is per set, content-only and after early writes

SR: SR-052. Design: LLR-052, LLR-095.

Get-BackupCapacityDemand counts content and cross-volume history, but not all records, kits, allocation or scratch. Invoke-BackupSet creates roots, lock, log, cache and staging before its capacity rail; the entry loops sets rather than summing the invocation by volume. Plan all locations read-only, aggregate by volume and revalidate under exclusion.

## G-09 — Native configuration bypasses version, closed-key and credential admission

SR: SR-018, SR-042, SR-123, SR-129, SR-135. Design: LLR-042, LLR-104.

Import-BackupConfiguration’s native branch is explicitly unversioned and skips the JSON version/closed-key/credential rules. The published description covers JSON only. Implement equivalent closed validation for both forms, account-protected credential checks, and supported-version meaning tables. JSON v2 is the only accepted numeric version today; design v3 and predecessor semantics need publication together.

## G-10 — Configuration refusal can still alter an existing log

SR: SR-018. Design: LLR-042.

The configuration-error path in FileBackup.ps1 appends to an existing global log. SR-018 requires creating and changing nothing. Buffer/emit the refusal outside stored logs until admission rather than changing a previous run record.

## G-11 — Several accepted JSON locations emit a warning

SR: SR-095. Design: LLR-014, LLR-048.

Import-BackupConfiguration warns that multi-set JSON is outside IF-001. SR-095 explicitly requires no warning merely for the number of locations. Retire that convention while keeping per-set failure isolation.

## G-12 — Location admission is incomplete and occurs after creation

SR: SR-063, SR-138, SR-140, SR-149. Design: LLR-095.

Resolve-BackupSetPaths creates roots before cache placement checks, checks only a set’s own paths, lacks backup/history-versus-source overlap guards and a pre-write read-only-source gate. Resolve-ViewRootPath uses lexical per-set paths; foreign-view-content protection runs in generation after backup work. Validate all physical relations and foreign view content before any writes.

## G-13 — Process result classes still depend on opt-in and lossy aggregation

SR: SR-043, SR-040. Design: LLR-043, LLR-040.

FileBackup.ps1 and Reconstruct.ps1 use ExitCode to select classified process exits rather than making them unconditional at the process boundary. Backup aggregates a success boolean plus witness failure; this cannot express the all-refused 2/3/4 versus mixed-progress 1 rules. Preserve classified per-location outcomes and distinguish process from in-process APIs.

## G-14 — Lock refusals do not carry the required classes and holder identity

SR: SR-017, SR-085, SR-086, SR-107. Design: LLR-017, LLR-090, LLR-091.

Backup lock refusal marks its set failed; prune returns staging-busy code 2 and repair/refresh surface 2. Current code does not implement contention/I/O=4 versus denied/unusable-location=2, nor reliably identify the operation holding the marker-free lock. Use a holder description independent of the disappearing staging marker and retain the persistent lock identity.

## G-15 — Ownership fences leave object writes between phase checks

SR: SR-144. Design: LLR-108.

The backup checks ownership at five phase boundaries, not at every object publication or after every long blocked copy. A former owner resuming during the storage phase can mutate before reaching the next fence. Extend ownership-bound publication to each destructive/write operation and preserve successor work during failure cleanup.

## G-16 — Absence is treated as age without positive evidence

SR: SR-039, SR-116, SR-146. Design: LLR-039, LLR-065, LLR-111.

Both restorers accept a missing witness by default and treat absent/malformed directory metadata as advisory. The nine-column record has no immutable writer-feature profile; the kit revision can change on refresh. Add bound state-age evidence and explicit current empty metadata, then distinguish old absence from current damage. Do not infer age from the current kit.

## G-17 — Bad current file times do not affect the result

SR: SR-066, SR-040. Design: LLR-066, LLR-040.

The timestamp paths warn and retain a restored count for blank or unparsable time, but do not contribute partial failure. Keep the restored byte count and add value 1 for current-form time damage.

## G-18 — Target name collisions have no reject-both admission pass

SR: SR-092. Design: LLR-100.

The runtime restore builds a path map using host comparison, which can collapse case twins before processing. Neither inspected route performs a complete target-normalization/case collision grouping that leaves every colliding member unwritten. Detect groups before entry writes without losing the original row identities.

## G-19 — Traversal handling and parent-component refusal are incomplete

SR: SR-121, SR-141, SR-040. Design: LLR-009, LLR-101, LLR-040.

The runtime physical-path helper begins with lexical normalization, so a syntactic parent component is not unconditionally refused. Escaping file entries enter the general unrestored collection, and escaping directory entries only warn; neither implements all of the damaged-record value-3 behavior. Apply explicit parent-component admission and per-entry physical containment with correct classification in both routes.

## G-20 — Direct archive failures are still host-class without proving the host failed

SR: SR-040, SR-068, SR-119. Design: LLR-040, LLR-050, LLR-068.

Restore-OneRow treats direct expansion failure as CandidateError/hostfail. The pool candidate path has a tool usability probe, but that distinction does not cover the direct-object path. Prove extraction capability, attempt other intact copies and classify unrecoverable content as 1 when tools work.

## G-21 — Supported-state admission has no complete version profile

SR: SR-061, SR-114, SR-115. Design: LLR-060, LLR-111.

Current guards recognize Original, separators and older witness/name forms, but not a complete supported/future whole-state profile. Positive retired checks are good and remain; unknown whole-state forms need a named refusal, while damaged single entries must still reach recovery. Establish a supported-version inventory before implementing new state metadata.

## G-22 — Default check does not verify every payload

SR: SR-049. Design: LLR-049.

Test-BackupStorageForm hashes all payloads only under Deep; normal scans use signature/form checks and exemptions that permit same-length altered content to pass. Make the SR-049 check payload-complete while caching verification per distinct object to meet the scale envelope.

## G-23 — Repair leaves missing-local content report-only

SR: SR-109. Design: LLR-099.

Repair-BackupStorageForm explicitly excludes DanglingDataPath and blank-row findings from correction and only repairs local form/name evidence. Add read-and-hash verified copying from elsewhere back to the same local location, preserving the source folder and all logical fields.

## G-24 — Interrupted precommit removal can remain wedged by its own staging marker

SR: SR-101, SR-017. Design: LLR-098.

Remove-BackupSnapshot handles committed Pruning_ residue and unreferenced staged copies, but Assert-PrunePrecondition refuses any existing Temp. A killed precommit removal leaves PRUNE.inprogress, so repeating that removal cannot necessarily pass its own staging rail. Add operation-identified safe resumption before ordinary staging refusal.

## G-25 — Removal safety rails are lexical and permit proof bypasses

SR: SR-046, SR-102. Design: LLR-046.

Target planning uses direct-child name/path tests rather than a complete physical-link containment proof. Public options can waive unreferenced-data and evidence checks or content verification. The rebuilt SR-046 requires refusal when safe preservation cannot be established; retain any legacy flags only where they do not waive that proof, and resolve linked targets before mutation.

## G-26 — Atomic record replacement has no positive interruption recovery protocol

SR: SR-082, SR-110. Design: LLR-087, LLR-115.

The record writer stages and renames then writes the witness, but performs no explicit durable flush and persists no old/new publication intent. A later run encountering the stale witness refuses rather than completing a positively identified publication. Add durable generation evidence; never repair an arbitrary mismatch by guessing a new witness.

## G-27 — Content can leave the visible pool before its authority is replaced

SR: SR-082, SR-059, SR-041. Design: LLR-041, LLR-115.

Removed/superseded objects move into unpublished Temp before the new live authority and dated state are published. A kill in that window can leave a witnessed old live record whose bytes are only in staging, which restore pool discovery excludes. Keep old supply visible until the replacement generations are recoverable; if preservation cannot succeed, retain the prior live state.

## G-28 — Lock-free readers are not pinned to a complete generation

SR: SR-106, SR-103. Design: LLR-116.

Readers take no mutation lock, but no read-generation session pins authority and object supply. A concurrent rename, repair or witness publication can expose an inconsistent observation despite the requirement to operate against a complete state. Add non-writing read coordination and writer-side retention of pinned inputs.

## G-29 — Kit refresh copies individual live files without coherent activation

SR: SR-110, SR-117. Design: LLR-076, LLR-115.

Update-BackupSnapshotKit copies the live root’s kit into snapshots and assumes the root kit is current. The refresh dispatch in FileBackup.ps1 calls it without first refreshing the root, so stale live-root artifacts can be recopied. Copies occur leaf by leaf; a kill can leave a mixed or torn executable bundle. Refresh the root from the installed distribution and stage coherent revisions before activation, with positive interrupted-refresh evidence.

## G-30 — Space-view toggle and explicit availability are absent

SR: SR-097, SR-098, SR-099, SR-147. Design: LLR-097.

The source scan invokes media measurement while hashing when the tool is available; the schema has no SpaceView control. The browse view does not implement the complete independent largest-first physical-size/shared-marking and unavailable-measurement contract. Add the feature control, precision and explicit off/failure reporting without changing stored content.

## G-31 — Progress is not independently bounded during long work

SR: SR-125. Design: LLR-103.

Inspected backup logging is phase/per-file driven; the independent timer updates liveness metadata, not operator progress. A long hash, copy or finalization can exceed 120 seconds between visible entries. Add a progress publisher independent of those blocking operations.

## G-32 — Kit deposition does not include dependency notices

SR: SR-131. Design: LLR-007.

New-ReconstructScript and the snapshot artifact copy loop include the digest library but no associated licence/notice artifact. Add the required notices to kit delivery and refresh; this is separate from whether the licence itself permits redistribution.

## G-33 — Scratch is not confined to declared writable container locations

SR: SR-130. Design: LLR-112.

Shared extraction and other scratch paths use the host temporary directory; the container adapter does not redirect the temporary workspace into a writable state mount. The new parent requires writes only to backup, working-state and log locations, not arbitrary container paths. Route all scratch there and prove the no-network unprivileged run.

## G-34 — macOS delivery does not always retain launcher executability

SR: SR-072. Design: LLR-074.

README documents that a Windows-written kit after zip transfer onto APFS needs manual executable permission before Finder launches it. That is outside the unconditional double-click acceptance. Provide a delivery path preserving launchability or resolve the support-boundary discrepancy explicitly; do not present the fallback shell command as meeting double-click.

## G-35 — Current pool work is not bounded to the declared whole-operation envelope

SR: SR-064, SR-112, SR-113. Design: LLR-062, LLR-114.

The content index has a lean default, but prune/audit retain complete state records and restore recovery scans candidates per unresolved row. There is no spill threshold, reader generation index, verified-object memo across the whole operation or demonstrated aggregate-process 4 GiB bound. Implement bounded indexing and retain direct end-to-end time/memory verification; static inspection alone does not establish a measured budget failure.

## G-36 — The probe includes the exact minimum-size boundary

SR: SR-081. Design: LLR-004, LLR-086, LLR-109.

Resolve-CompressionDecision exempts lengths strictly less than ProbeMinBytes, while Resolve-GroupStorageForm selects candidates greater than or equal to that value. A 262144-byte file therefore reaches the default probe; the SR exempts files at or below 256 KiB.

## Uncovered SRs

None. Every one of the 123 current SRs reaches at least one top-level LLR; child obligations inherit those links. Direct boundary constraints below additionally preserve obligations that need no separate behavioral decomposition. Coverage means a traceable design obligation, not implemented or tested compliance.

## SR constrains

These are proposed upward links for the coordinator to add to the SR tier; this derivation does not edit that tier.

| SR | Boundary interface | Reason |
|---|---|---|
| SR-148 | IF-036 | External plain working-state records and their location. |
| SR-139 | IF-037 | The permitted source-root cache boundary. |
| SR-132 | IF-038 | Required dependency acquisition boundary. |
| SR-073 | IF-039 | Supported host and session observations. |

## Design choices requiring alignment

- IF-002 proposes configuration version 3 for the new SpaceView control and uniformly versioned admission. The supported JSON version-2 meaning table must be captured before release. In particular, preserving calendar-boundary scheduling and unconditional media probing as predecessor semantics conflicts with applying the rebuilt elapsed-schedule and opt-in measurement requirements to every version. SR-123 compatibility and SR-011/SR-097/SR-147 need an explicit version-scoped ruling; silently reinterpreting an older document is not a solution. This is a parent-tier interpretation question, not an authorization to change those SRs.
- IF-007 adopts canonical UTF-8/no-BOM/LF, quoted fields and a header-only empty state. The existing platform CSV writer and empty-input path need review against that exact form (LLR-024/025); the design is stronger than merely preserving same-host no-op bytes.
- IF-014, LLR-111 and LLR-115 introduce immutable state-format evidence and publication intent. Existing states cannot be assigned invented old-age evidence. Define the supported predecessor profile from positive existing evidence; unknown missing witness/metadata cases stay refusals. Kit revision alone is not writer-format evidence.
- IF-040 and LLR-116 specify stable read generations while writers proceed. The exact host implementation of pinned handles or retained immutable supply remains an implementation choice; it cannot depend on readers creating store artifacts. This design must work for the shell recovery route as well as the runtime route.
- Components follow responsibilities, with one logical restore component spanning the two runtime routes. Interfaces express form using artifact roles; literal shipped leaf names appear only in LLRs. The root component alone omits part_of.

## Evidence limits

The gap list contains only differences supported by the permitted source inspection. No product code or tests were run. End-to-end scale, resident memory, throughput, crash durability, network-filesystem exclusion, permissions and platform compatibility still require measured validation; G-35 explicitly distinguishes missing bounds from measured failure. The image build definition and dependency licences were outside the enumerated code inputs, so image redistribution compliance (SR-143 / LLR-112) is not claimed proved or disproved. Existing-kit compatibility needs actual released fixtures, not merely today’s kit against today’s writer.
