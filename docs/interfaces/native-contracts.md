# Draft native interface definitions

These are design-owned contract bodies for planned logical modules. The module
paths name responsibilities, not implemented Rust files. Until implementation
exists, this document is their definition home; move a body with its owning module
when binding code rather than copying a second normative definition. Both recovery
scripts implement shared on-disk/result contracts independently, without loading
the native executable. All new records are Drafted. See the [interface index](../interfaces.md)
and [store/record design](../plans/native-design-2026-11-05/contracts.md).

## Contract IF-002: Configuration admission

Owner: `native/config`. Channel: `file`. Coverage: LLR-151, LLR-152.

Accept the versioned JSON document, resolve declared source/store/view roots and materialize defaults before any store mutation. Reject unknown/retired keys, wrong types, unsupported versions and unsafe/duplicate locations with nonsecret field/set diagnostics. Reject readable notification secrets at this admission boundary, accepting only declared protected credential references without echoing values; enforce this before mutation even for disabled notifications or non-notifying actions. Produce one validated configuration for action dispatch. The published schema and examples describe the same accepted input; no new configuration family is introduced for Rust. Exact version additions are pinned with schema fixtures in N1.

## Contract IF-003: Action invocation

Owner: `native/cli`. Channel: `cli`. Coverage: LLR-153.

Accept the requested action, configuration location and action-specific set/state selectors. Validate the complete configuration before dispatch, then attempt independent admitted sets despite one set failure. Omitted container action means backup; unknown actions refuse rather than becoming backup. Commands include backup, inventory, check, explicit repair, refresh, prune and view; exact native flags and argument schema are an N1 freeze item. Read-only actions may not acquire mutation by default.

## Contract IF-004: Exit outcome vocabulary

Owner: `native/results`. Channel: `exit-code`. Coverage: LLR-153, LLR-178, LLR-179.

Return 0 complete, 1 incomplete/content findings, 2 invalid request/configuration and 4 busy/host stop, with multi-set precedence 2 > 4 > 1 > 0. Preserve the underlying operation result when notification fails. Host metadata limitations can accompany otherwise complete content with warnings; missing required recorded metadata is incomplete. A complete restore describes required checks on selected definitions, not completion of the most recent source scan. Both carried scripts implement this vocabulary independently; ownership of its definition does not introduce a native-engine dependency. Legacy IF-001 keeps its historical versioned exit table.

## Contract IF-005: Progress and machine-readable findings

Owner: `native/reporting`. Channel: `stdout`. Coverage: LLR-168, LLR-178, LLR-180.

Emit action/set/state identity, outcome and reason, affected path when known, captured/recovered/skipped counts and metadata warnings. Inventory and verification include every requested state, findings and qualified retention estimates. Progress remains bounded during active execution without inventing completed work; redact secrets. Read-only actions send results to the caller without store-side logs/scratch. Version the structured event schema and pin its exact fields before integrations consume it. Restore scripts emit equivalent meanings without calling the native engine.

## Contract IF-006: State-record format

Owner: `native/format`. Channel: `file`. Coverage: LLR-164, LLR-185.

Write/read the retained nine-column file manifest and the proposed typed directory/link sidecar in the single-store layout. The declared new revision requires a header-only directory record for an empty set; missing required metadata is not an older-format exemption. Validate quoted UTF-8 fields, slash paths, identities, types and conflicts. Valid file rows outrank conflicting supplemental metadata for safe file recovery; report metadata damage. Format/kit admission and exact revision are pinned in N1, before any writer enables links. No historical version is designated supported automatically. The detailed field meanings live in the store/record design, not a duplicate registry cell.

## Contract IF-007: Stored-content pool

Owner: `native/store`. Channel: `bytes`. Coverage: LLR-159, LLR-162, LLR-163, LLR-173.

Address captured bytes by xxHash128 and length using the retained name codec, latest shards and flat history objects. Publish complete staged bytes without overwriting valid objects; reuse/move-back shared content and move superseded objects only after final latest dependencies are known. Lookup spans the shared pool; names locate candidates but do not prove content. Recovery verifies required length/hash before publishing output and tries distinct supply on damage. Missing/damaged supply and host/tool failures remain distinguishable. A state folder alone is not a complete content export.

## Contract IF-008: Checkpoint and previous-definition lifecycle

Owner: `native/state`. Channel: `call`. Coverage: LLR-158, LLR-165, LLR-166.

Accept prior definitions, admitted run context and captured progress. Finish initial .prev preservation before touching current definitions; publish the normal prior dated snapshot before the first checkpoint. Existing .prev files survive unsuccessful runs unchanged. Delete them only after successful replacement/finalization. Copy interruption leaves old current definitions available; cleanup interruption leaves new current definitions available. A lone copy is residue, not a current-state failure or an automatic restore selector. Compare file/folder/link semantics for history retention. Return published progress/final outcome with actual errors; do not infer whole-source completion from valid records. This internal orchestrator uses IF-006 record codecs, IF-014 sync/rename primitives and IF-007 pool operations. Pass final latest dependencies to superseded relocation only after latest publication; endpoint lists do not relax that ordering.

## Contract IF-009: Complete store and independent recovery kit handoff

Owner: `native/package`. Channel: `file`. Coverage: LLR-184, LLR-186, LLR-190.

Carry the selected state records, shared pool, matched PowerShell/bash kit dependencies, launchers, local provisioning/recovery guidance and required notices with the complete store. Kit selection respects declared format support and needs neither native engine, repository nor network once local prerequisites exist. Handoff preserves the complete shared store, not just one state folder. Retention may leave older states outside the supported window. .prev copies are auxiliary definitions, not a separate content supply or extra retention promise.

## Contract IF-010: Recovery invocation and record selection

Owner: `recovery/admission`. Channel: `cli`. Coverage: LLR-172, LLR-179.

Accept selected latest or exact dated identity, store location and target; default to the selected canonical records. Previous definitions require explicit selection and never silently replace or merge with current metadata. Validate required structure, tools, capacity and target before avoidable writes; diagnose unavailable required previous members only for that explicit selection. Interactive launchers keep results readable; scripted invocations require no prompt. Pin PowerShell/bash flag parity with shared fixtures; preserve independent implementations.

## Contract IF-011: Recovered tree publication

Owner: `recovery/content`. Channel: `file`. Coverage: LLR-173, LLR-174, LLR-175, LLR-176.

Publish verified file bytes through safe ordinary paths, preserve per-file times, recreate empty directories and supported attributes, then create supported in-root folder links relative to their parents. External folder aliases restore ordinary duplicate trees; file links restore ordinary bytes. Reject escaping/colliding file paths and unsafe pre-existing target redirects. Conflicting supplemental records are reported without discarding independent valid files. Missing target mappings are not guessed; unavailable link capability produces the declared metadata limitation. No writes follow restored links.

## Contract IF-012: Restore location and host capability observations

Owner: `recovery/paths`. Channel: `call`. Coverage: LLR-174, LLR-175, LLR-176, LLR-179.

Read resolved target ancestry, naming/case/normalization behavior, attribute/link capabilities and host/tool flavor. Return supported, unsupported, unsafe or unresolvable observations with causes. Revalidate actual write paths and never turn unknown ancestry into permission to write. Host capability warnings do not claim missing required records were recovered. Metadata precision and link privilege remain qualified by the declared support matrix.

## Contract IF-013: Source enumeration and capture observations

Owner: `native/capture`. Channel: `call`. Coverage: LLR-156, LLR-157, LLR-158, LLR-159, LLR-160, LLR-161, LLR-177.

Read source entries including hidden/system/dot names and return complete, partial or unavailable enumeration plus captured identity and metadata. Source operations are read-only. Preserve prior rows for unreadable prefixes; unavailable or unexpectedly empty populated sources do not become deletion lists. Internal folder links become root-relative records, external folder aliases expand under their paths, file links become file bytes, and active-ancestor checks stop cycles. Bound unreachable-target waits/retries. Changes in folder/link metadata participate in state comparison, independent of stored-byte deduplication.

## Contract IF-014: Store ownership and publication primitives

Owner: `native/platform`. Channel: `call`. Coverage: LLR-155, LLR-163, LLR-166.

Provide OS-lifetime exclusive ownership, same-store rename/publication and sync outcomes, including the filesystem effects requested by IF-008 for previous copies, snapshots and current records. Hold ownership across mutation/finalization; never unlink/reclaim a live lock by age. Report contention, unsupported operation and host I/O causes. Persist data before publication that depends on it; power-loss guarantees depend on the qualified storage stack. Scope is one validated configuration with unique resolved roots; independent external writers are not coordinated by this promise.

## Contract IF-015: Volume identity and capacity estimates

Owner: `native/capacity`. Channel: `call`. Coverage: LLR-167.

Return measured available bytes and volume identity or explicit unknown, without double-counting one volume. Estimate expanded output per logical path plus temporary/publication demand, including external aliases; recreated relative links do not duplicate their target bytes. Known shortfall refuses the affected unit, unknown warns and uses bounded writes. Late capacity/disconnection failures preserve valid earlier work. Observations are not reservations.

## Contract IF-016: Local tool invocation and results

Owner: `native/tools`. Channel: `call`. Coverage: LLR-154, LLR-162, LLR-187.

Admit action-dependent local tools and execute direct argument arrays with bounded output, diagnostic classification and no path interpolation through a shell. Required absence refuses with provisioning guidance; optional tools report skipped features. Native embedded libraries are implementation, not external prerequisites. PowerShell/bash recovery implements the same documented tool semantics locally without loading native code. Declare supported tool floors/flavors and distinguish byte damage from host inability. Automatic package download is not offered in the initial design, so B-11 remains conditional and unrealized.

## Contract IF-017: Notification relay submission

Owner: `native/notify`. Channel: `call`. Coverage: LLR-181.

Submit the configured bounded run summary using credentials supplied by the host facility and return relay acceptance/failure. Bound attempts/timeouts and redact secret material. Record notification failure without changing the underlying backup/maintenance outcome. Relay acceptance is not recipient delivery or evidence that an operator acted.

## Contract IF-018: Protected credential access

Owner: `native/notify`. Channel: `call`. Coverage: LLR-181.

Use the declared host credential facility for setup/reference and authorized runtime retrieval; keep secret values out of readable config, carried store and logs. Report access/unavailable-facility failures without exposing values. Portability and execution-account requirements are explicit in host guidance; do not invent a portable plaintext fallback.

## Contract IF-019: Native container invocation

Owner: `native/container`. Channel: `call`. Coverage: LLR-153, LLR-183.

Accept the container launch environment, configuration, action, read-only source/config access and writable single store, under a declared unprivileged identity. Default omitted action to backup; process admitted configured sets independently under the native product contract. Return the same action results and leave source read-only. Internal store folders stay on a rename-compatible mount. This is a new Drafted native contract; it does not silently widen legacy IF-001, which remains one set per invocation. Qualify image/host combinations and supply offline delivery guidance.

## Contract IF-020: Operational records and derived views

Owner: `native/view`. Channel: `file`. Coverage: LLR-180, LLR-182.

Build the browse view only in its admitted owned location, publish permitted operational records and report space/media measures with their limits. Views are disposable and never content authority. No read-only check/inventory action writes a view, lock, log or scratch inside the store. Disabled optional measures say they were not taken, rather than reporting zero. Failures identify the affected derived feature without disguising content capture results.

## Contract IF-021: Native and container release artifacts

Owner: `native/package`. Channel: `file`. Coverage: LLR-183, LLR-184, LLR-190.

Deliver native executables for the explicitly supported Windows/Linux/macOS CPU matrix and optional container image, with embedded engine dependencies, matched recovery assets and required license notices. No compiler, language runtime or repository is required for native operation. Recovery keeps its separately documented local tool floor. Designated supported combinations require evidence; do not label a build artifact itself as tested platform support.

## Contract IF-022: Shipped guidance and configuration support

Owner: `delivery/guidance`. Channel: `file`. Coverage: LLR-151, LLR-185, LLR-190.

Ship schema/examples/helper guidance, supported host/tool matrix, offline recovery instructions, result meanings, complete-store dependence, retention cutoff and verification limits. State explicit designated migration/continuation routes; currently no older version is designated supported. The material travels with release/store where required and does not depend on a web page. Readability does not guarantee that an operator read or understood it.

## Contract IF-023: Retention planning and execution

Owner: `native/retention`. Channel: `call`. Coverage: LLR-169, LLR-170.

Accept explicit state selection or inventory-only request. Compute protected latest/later dependencies before deletion; keep unknown/incomplete analysis from authorizing removal. For a batch, survivor supply excludes every selected folder. Rehome and sync required last copies and metadata before committing resumable Pruning. Resume only the selected checked deletion set. Invalidating older records does not authorize sweeping their folders. Preview leaves the entire store unchanged; execution returns findings/estimates and result classes through IF-004/005.

## Contract IF-024: Whole-store inspection and explicit repair

Owner: `native/verify`. Channel: `call`. Coverage: LLR-168, LLR-171, LLR-188.

Inspect selected/all remaining state records one at a time with bounded scratch outside the store. Include older out-of-window records; report incomplete scans and damaged/missing/form-inconsistent content. Read-only inspection never mutates the store. Repair is a separate explicit mutation under ownership, revalidates candidates, preserves usable historical supply and quarantines uncertain bytes. Current source bytes are not substituted for missing historical identities; results remain distinct from a claim of provenance.

## Contract IF-025: Explicit kit refresh

Owner: `native/kit`. Channel: `call`. Coverage: LLR-186.

Admit the supported state-format/kit pair and the complete version-matched inventory before replacement. Preserve a usable prior or new route through interrupted refresh; select the smallest kit-local staging/commit mechanism with tests. Keep state records/content and previous-definition copies unchanged. Return actual maintenance outcome; partial kit staging is not an instruction to discard valid captured data.
