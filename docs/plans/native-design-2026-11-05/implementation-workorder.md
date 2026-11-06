# Native implementation workorder

The owner authorized continued design review followed by implementation of the
Rust transition on this branch. Gemini Argon on low reviews design decisions;
DeepSeek 4.1 Flash and Claude Opus on low review implementation changes.
Authoring and review do not manufacture approval or executed evidence in the spine.

## Owner review and implementation guidance

If OpenCode reaches its usage limit, continue with Claude Opus 5.5 alone through
the installed Claude CLI, at low effort. Do not block progress waiting for a
second reviewer or repeat exhausted calls. Reviewer suggestions are inputs for
judgment, not instructions to apply automatically.

Keep the core design simple. Adopt feedback when it identifies a concrete defect
or an unmet accepted requirement in a plausible supported workflow. Assess the
likely impact and the complexity of the proposed fix. Prefer a small correction
or an explicit support boundary to new machinery for contrived scenarios. A rare
but credible data-loss defect still warrants consideration; rarity alone is not
a reason to dismiss it. Record why consequential findings are adopted or rejected.

Keep functions focused and reuse existing behavior within each runtime. Before
adding a helper, look for an existing implementation of the same operation;
consolidate actual duplication when it makes the code easier to follow. Avoid
speculative abstraction layers and broad rewrites solely to satisfy a reviewer.
The standalone PowerShell and Bash recovery routes remain independent of Rust;
shared contracts and fixtures keep their intentionally separate implementations
aligned.

## Decisions for N1

- One Cargo package under `rust/`, library plus CLI. ConfigVersion 3 JSON keeps
  `BackupSets`, `Tools`, `Secrets` and `StorePath`. A new executable refuses unsupported
  features/configuration explicitly rather than silently ignoring a setting.
- Preserve the existing unseeded XXH3-128 canonical uppercase hex, base-57 object
  codec, nine-column manifest, sharded latest and flat dated history. Golden vectors
  come from the existing independently generated hash/name corpora.
- The native metadata schema is identified by the exact four-column directory
  header `RelativePath,Attributes,EntryKind,LinkTarget`, carried by kit revision 17.
  No completion marker is introduced. The native engine requires this schema for
  continuation; absent metadata is damage, never inferred to mean an old format.
  A new empty store is supported; older stores retain their existing kits and need
  an explicit transition. No older version is designated supported.
- Required metadata is header-only when empty. All represented directories are
  recorded, making empty-folder and link-only changes observable. Links resolving
  inside the source map to root-relative directory destinations; external folder
  links expand under each alias. File links carry ordinary file bytes. An active
  ancestor identity stack detects cycles without suppressing acyclic aliases.
- Current and explicitly selected `.prev` are separate record sets. Preserve existing
  previous copies without replacement before current metadata changes; retain them
  on incomplete runs; delete only after successful finalization. Files remain
  independently recoverable when supplemental metadata is damaged.
- Snapshot identity uses a UTC date/time name with a numeric collision suffix,
  allocated without replacement under the store lock. Completion dates are metadata;
  allocate order monotonically beyond the greatest retained state identity when
  the wall clock goes backward. Never keep an unrelated existing snapshot merely
  because a proposed folder name exists. Resumption compares identity and definitions.
- Publish the previous selected state before changing latest records. Each latest
  checkpoint contains captured successes plus prior protected rows, not an implicit
  deletion list. Only a completed walk/source check authorizes final removals.
  Finalization includes directory/link records before moving superseded objects.
- Atomic replacement uses a synced same-directory temporary file and host rename
  semantics. New objects publish without replacement; an existing candidate must
  be checked as usable. Lock lifetime covers every mutator, including view/kit refresh.
  No lease/heartbeat/age reclamation. Network filesystems require qualification.
- Standalone recovery remains PowerShell/bash with local tools. The new writer is
  not enabled for an extended metadata format until both readers accept its fixtures.
  Recovery writes verified temporary output before replacing a destination, detects
  target redirects/collisions, and creates relative folder links after ordinary files.
  User-controlled exclusive restore targets are the supported script profile;
  no claim of protection against a hostile concurrent target-directory modifier.
- Kit refresh preserves a complete prior kit in a dedicated recovery subdirectory
  before replacing any member. That copy must be runnable with explicit store/record
  selection; interruption retains it. Refresh cannot change metadata or `.prev`.
- Prune protects latest and retained later identities, verifies required supply
  outside the entire deletion set, rehomes before `Pruning_` commit and deletes only
  explicitly selected folders. Unknown content blocks removal. Read-only verify and
  inventory create no store-side logs, locks or scratch.
- JSON events carry `schema_version`, `action`, `set`, `class`, `cause`, `path`,
  `message` and counters; JSON stdout is separate from progress stderr. Exits are
  0/1/2/4 with 2 > 4 > 1. Configuration errors never echo values/secrets.
- The reference performance topology and 2 GB available RAM remain acceptance
  targets. Small script restore and native indexing probes run early; full 2 TiB
  qualification is not simulated by sparse-file creation or estimated arithmetic.

## Implementation sequence and evidence

1. N1: pure format/configuration fixtures; both script readers; unsupported-format
   refusals; run/metadata identity and interruption fixtures. Gemini design review
   resolves concrete high-risk contradictions before enabling mutation.
2. N2/N3: filesystem primitives and bounded native backup; real hash/CSV script
   interoperability, no-op/change/failure/retry/link/collision tests, subprocess
   termination checkpoints, and source/store containment.
3. N4/N5: inventory, check/repair, dependency-preserving prune, views, resumable kit
   refresh, and both independent recovery routes with byte and metadata checks.
4. N6: native build/test workflow for Windows/Linux/macOS, container packaging,
   configuration helper, notifications/tool adapters and offline guidance/notices.
5. N7: exercised support matrix, memory/time measurements and release readiness.
   Untested combinations and incomplete obligations remain explicit in the status.

Use DeepSeek and Opus for concrete code defects, resolve findings and re-review
affected code. Do not mark broad LLR/TC rows implemented/verified merely because
one fixture passes. Attach real symbols and cases as work becomes reviewable.

## Local resources

Rust 1.96 is already installed. Use `D:/FileBackupBuild/cargo-home` for new Cargo
downloads, `D:/FileBackupBuild/target` for outputs and `D:/FileBackupBuild/tmp` for
test scratch. Keep the existing toolchain in place; do not migrate or delete other
projects' caches. Install only dependencies needed by the next executable check.
Keep all product and review source in this checkout and check C: headroom before
large jobs. Disk availability does not justify destructive cleanup of user files.

## Review and progress

Gemini Argon on low returned READY FOR IMPLEMENTATION without high-risk findings.
The owner already authorized implementation; the review is advisory and does not
change approval statuses. The native Cargo package, both carried script readers,
backup/maintenance actions and delivery workflow now exist. See the
[code-review record](implementation-reviews.md), [native usage](../../native-usage.md)
and [support/evidence limits](../../native-support.md).

Local native checks exercise the format corpora, deduplication, compressed script
recovery, folder-only history, incomplete runs, failed case-only renames, seven
forced process-termination stages, retention cutoff, previous-definition demand,
view ownership, storage-form repair and notification admission. Their exact final
counts and commands are in the [validation record](implementation-validation.md).
Windows and Ubuntu WSL have executed tests. The Linux OCI image built and passed
an unprivileged offline compressed round trip; macOS CI is configured but has not
run here. No production store, real credential or mail relay has
been used by these checks.

The existing PowerShell engine remains a working regression reference. Its full
check on 2026-11-06 passed 997 Pester tests (3 skipped) and 274 integration
assertions (2 skipped), with zero failures. The harness remains red for the known
spine form debt; actual bindings now have zero orphan/integrity findings.
Implementation does not manufacture approval or complete
verification for every drafted LLR/TC.

Additional implementation decisions within the allocated contracts:

- `KIT.sha256` checks the carried executable/helper inventory, committed after
  its members. Interrupted refresh can use the complete `RECOVERY.previous` kit
  with explicit record/store roots. The state record lifecycle still uses `.prev`.
- Both scripts carry the same generated Unicode decomposition/case-fold data as
  the locked Rust codec. This avoids locale-dependent disagreement on valid names.
- Native prune includes a valid current previous manifest in conservative rehome
  demand while it exists. It does not make manual folder deletion safe or turn
  previous definitions into a separate content store.
- Notification work runs in a child with a 60-second total deadline. Windows
  Credential Manager, Linux Secret Service and macOS Keychain adapters resolve
  opaque references without unlock prompts; relay failure leaves backup exits
  unchanged. Live credential/relay and macOS validation remain qualification work.
- Compressor output is round-trip verified before publication. Native archive
  inspection hashes bounded extractor output directly, avoiding a second
  uncompressed scratch copy. Compression uses the accepted SR-081 probe policy,
  including the inclusive 256 KiB floor; there is no unapproved final-size override.

Full resource/host qualification remains N7 work. In particular, process-kill
fixtures do not establish power-loss durability, and a small metadata/capture
probe does not establish the 2 TiB/365-state restore/check budgets.
