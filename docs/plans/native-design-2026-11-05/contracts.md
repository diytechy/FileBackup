# Draft native contracts and targeted extensions

Read with the [review guide](review.md) and [flows](flows.md). The accepted
[system requirements](../../requirements/system-requirements.toml) control
outcomes; these decisions propose their implementation. The current
[single-store design](../single-store-layout.md) is the baseline.

## Store and identity: retain

```text
StorePath/
  CurrentBackup/
    MANIFEST.csv
    DIRECTORIES.csv
    MANIFEST.csv.prev       (when prior definitions are being preserved)
    DIRECTORIES.csv.prev    (same previous record set)
    <two-character-shard>/<content-name>
    <carried recovery kit>
  BackupHistory/<date>/
    MANIFEST.csv
    DIRECTORIES.csv
    <content-name>
    <carried recovery kit>
  Incoming/  Verify/  Temp.lock  backup.log  View/
```

The pool is latest plus dated history. A state folder's metadata describes a
whole logical state, but its content may be elsewhere in that pool. Preserve the
whole store for recovery/handoff. Building/Pruning folders are protocol work,
not extra selected states. Keep the current hash/length name codec and shard
rules. A cached index is disposable and never required by the recovery scripts.

Keep the manifest's nine columns:
`DataPath, RelativePath, Length, LastWriteTimeStr, xxH2Hash, Compressed,
StoredAsHashSize, Duplicate, MediaMBPerSec`. Golden vectors must pin CSV escaping,
Unicode, numeric/hash encoding, timestamp precision and slash separators before
Rust and either script share a writer/reader contract. Stored identity is the
hash and length of captured bytes. A filename is a lookup aid, not verification.

No older version is designated supported merely because the new engine reuses
its layout. Explicitly declare tested format/kit pairs. An old store can retain
its own kits; conversion or starting a new store is an explicit transition.

## Directory/link sidecar: extend

Proposed revised header:
`RelativePath,Attributes,EntryKind,LinkTarget`. `EntryKind` is `Directory` or
`FolderLink`; ordinary directories have an empty `LinkTarget`. `LinkTarget` is
a normalized source-root-relative path, with `.` reserved for the root itself.
These are metadata values, never shell commands. The final revision number and
admission mechanism are an N1 decision. The new revision writes a header-only
sidecar when there are no entries; header guessing cannot silently treat a
missing current sidecar as empty or as an older format. This is a proposed
extension: the current PowerShell writer removes an empty advisory sidecar.

Capture resolves the destination. If it is a supported directory inside the
configured source root, record its root-relative destination without traversing
it again through the alias. The original spelling may be absolute or a junction.
For a link at `photos/latest` to `archive/2026`, restore computes
`../archive/2026` from the restored link's parent. It validates both the mapping
and destination ancestry, creates ordinary directories/files first, then links.
Moving the entire restored tree preserves that relative relationship.

Missing/invalid required link metadata makes recovery incomplete. A host lacking
link privilege/capability reports a metadata limitation; otherwise complete file
content can remain complete with that warning. Never silently copy an internal
link's subtree, recreate an absolute external destination or write content
through a restored link. Reject file/directory/link path conflicts and report
the conflicting metadata while preserving independently recoverable file bytes.

External folder links implement SR-137's capture-under-alias policy; this is
required new traversal work, not a claim that the current walk implements it.
The restored alias is an ordinary folder containing duplicate output files,
while identical stored content remains deduplicated. Follow nested
links using an ancestor-identity stack to stop cycles; do not globally suppress
another acyclic alias to the same external folder. Each logical alias contributes
output paths/bytes even when content is stored once. Links into protected system
locations are not followed. Targets inside the configured root use the portable
link rule. An unsupported external cycle is reported, not called complete.
Single-file links are captured/restored as ordinary file content under their
alias path, whether their targets are inside or outside the source, subject to
protected-location exclusions. Unreachable targets use bounded access/retry
handling and retain previously recorded content under that prefix. A source
junction can become a relative directory symlink on recovery; the host's link
capability/privilege applies. Valid links require an available captured target
within the restored root. They never retain an external absolute destination.

## Publication and maintenance: retain ordering, check failure edges

LLR-163..171 retain the prior snapshot before latest checkpoints, staged object
publication, final directory record and dates, and superseded moves last. This
is bounded progress, not a coherent instant of an entire live source tree.
Before latest records change, copy the pre-run definitions to `MANIFEST.csv.prev`
and `DIRECTORIES.csv.prev` in CurrentBackup, using staged, synced copies published
without replacement. These are infrastructure metadata, not stored content.
Existing copies are never overwritten by a later run. A fresh store has no
previous definitions. Initial preservation failure stops before latest mutation.

Interrupted or incomplete backups retain existing copies unchanged. Delete them
only after a successful replacement state and backup finalization. The ordering
is the protection: interruption while initially copying leaves both old current
definitions untouched; interruption while deleting leaves both successful new
current definitions available. A lone `.prev` file is housekeeping residue, not
a failed current state. Cleanup and kit refresh leave it alone until successful
backup completion can remove it.

Recovery defaults to the selected current records. Previous definitions are an
explicit inspection/recovery choice, never an automatic fallback or a mixture
with newer metadata. If that explicit choice lacks a required member, diagnose
the missing record while recovering independent files where possible. This does
not change default current recovery. Copies preserve definitions, not content
or an extra retention guarantee; dated snapshots and the shared pool remain the
normal history/recovery mechanism.

There is no incomplete-run marker. Restore success means the selected recorded
definitions were recovered, not that the last backup completed its source scan.
Valid recorded directories and relative links remain eligible after interruption.
Actual missing/malformed/conflicting required metadata is still reported; a
failed required sidecar write prevents a successful backup result. Source-scan
completion and recoverability of a recorded checkpoint are different outcomes.

Change detection includes the represented directory tree, directory attributes,
and folder-link kind/destination alongside file definitions. Adding/removing only
an empty folder, changing only an attribute, or adding/removing/retargeting only a
link retains the preceding dated state. Operational copies and serialization
order are not source changes. This corrects the current file-row-only comparison.

If a selected directory/link record conflicts with valid file-manifest paths,
reject that supplemental metadata and report it while recovering the independent
file bytes through safe ordinary directories. This rule uses record roles, not
timestamps or `.prev` presence. Impossible/colliding file rows and pre-existing
unsafe target redirects still refuse the affected writes. Thus a checkpointed
file replacing a former folder need not be discarded because the sidecar is older.

Prune keeps the existing dependency planning, rehoming and resumable deletion.
Latest and retained later states are protected; dates at/before removal can be
invalidated under the accepted policy. Read-only inspection still checks every
remaining state, including older states. A failed/incomplete protected dependency
scan cannot authorize deletion. External manual deletion bypasses this protocol.
Invalidating older records does not delete their folders. Only explicitly selected
and analyzed folders are removed; a batch tests survivor supply outside its entire
deletion set. Rehomed copies and survivor records are synced before Pruning commit.
Uncommitted work is replanned; committed resumption never expands the deletion set.

Similarly, missing-object recapture is a repair only when the fresh content
identity matches the prior one. A different hash is a source change even if
size/time matched, and the missing historical bytes are separately reported.

Kit refresh keeps staged writes, but preflights the whole version-matched kit.
A prior usable kit must survive until the replacement is committed. Define and
test a kit-local interruption mechanism if per-file replacement can expose an
unusable mix. Do not redesign the data pool to solve a kit publication problem.

## Configuration, results and host adapters

Retain versioned JSON and `StorePath`; declare any needed field/version additions.
Resolve and validate all configured root relationships before set execution.
Within an admitted configuration, process independent sets despite an individual
failure. Mutators hold one OS-lifetime store lock; suspended owners are not evicted
by age. Legacy IF-001 is retired from this branch's active baseline (see [cleanup](legacy-cleanup.md)); native container integration is allocated to IF-019. Existing deployments are unchanged. The [formal interface definitions](../../interfaces/native-contracts.md) and [trace map](../../interfaces/trace-map.md) allocate these contracts; the registry is [interfaces.toml](../../requirements/interfaces.toml).

Proposed CLI result codes retain `0` complete, `1` incomplete/content findings,
`2` invalid request/configuration, `4` busy/host stop, with aggregate precedence
`2 > 4 > 1 > 0`. Structured events separately retain set/action, reason, path,
counts and metadata warnings. A permission failure, corrupt archive and missing
extractor need distinct reasons even when two share a broad exit class. Pin
exact event field names in N1 before consumers rely on them.

Optional-tool failure reports the skipped feature. Required action dependencies
refuse with local provisioning guidance; recovery never downloads its engine.
Direct argument arrays, bounded output and redaction apply to tool/notification
adapters. Platform scope includes GNU/BSD utility differences and Windows link
privileges; current Linux bash support does not itself prove macOS support.

## Capacity, scale and evidence

Recovery estimates expanded logical file allocation, per-file temporary output
and metadata overhead by destination volume. Deduplicated source objects can
produce many independent output files. Known insufficient capacity refuses;
unmeasurable capacity warns and remains subject to bounded writes/late-failure
handling. Preflight cannot reserve space against unrelated concurrent writers.

Proposed reference interpretation for LLR-189: up to one million logical file
paths and 2 TiB expanded bytes per selected state, 365 saved states plus latest,
and a reference whole-store pool capped at 2 TiB distinct uncompressed content.
Record historical row count, alias factor, compressed/raw mix and physical bytes
separately. That pool cap resolves an otherwise unbounded history workload but
is a **review decision**, not an implicit amendment of SR-064/112/113. Run larger
history pools as characterization and do not claim the same time guarantee.

Use four cores, 2,000,000,000 bytes available RAM and 100 MiB/s local SSD, as
accepted. Peak memory is simultaneous resident use of the engine/scripts and
their child processes; independent peak values are not added. Record cache
conditions, actual I/O, scratch demand and repeat trials. The 8-hour check/restore,
30-minute routine backup and 182/364-state growth comparisons require measured
evidence. A process-kill test is not power-loss evidence, and passed byte checks
do not authenticate provenance or completeness of substituted records.
