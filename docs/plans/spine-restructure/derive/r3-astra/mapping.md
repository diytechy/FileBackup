# Legacy design disposition

All destination rows are Drafted. Numbers absent from the supplied 83-row carrier remain reserved; none is reused. Form and behavior are deliberately separate. New IDs start at LLR-095.

- LLR-001 — Kept as LLR-001: Diff remains a capture decision, with healing in LLR-053.
- LLR-002 — Kept as LLR-002: Digest spelling moves to IF-009; capability acquisition is LLR-020.
- LLR-003 — Kept as LLR-003: One object per content key.
- LLR-004 — Kept as LLR-004: Archive form moves to IF-010; sampled policy to LLR-086/109 and effort to LLR-037.
- LLR-005 — Kept as LLR-005: Layout form moves to IF-011; injection seams move to the test tier.
- LLR-006 — Merged into LLR-051: removed and superseded content use the same final-claim rule.
- LLR-007 — Kept as LLR-007: Kit form moves to IF-033; no implementation carrier is prescribed.
- LLR-008 — Kept as LLR-008: Recovered form, lookup, accounting and verification become independent child decisions.
- LLR-009 — Kept as LLR-009: Absorbs platform twins LLR-072/079; per-entry confinement is new LLR-101.
- LLR-010 — Kept as LLR-010 (child of LLR-008): Pool lookup independent of authority.
- LLR-011 — Kept as LLR-011: Elapsed-period and completion semantics follow the rebuilt parent, not calendar-boundary implementation.
- LLR-012 — Absent from the supplied legacy carrier; reserved and not reused because there is no source row to carry forward.
- LLR-013 — Absent from the supplied legacy carrier; reserved and not reused because there is no source row to carry forward.
- LLR-014 — Kept as LLR-014: Retained as independent orchestration; numeric aggregation moves to LLR-043.
- LLR-015 — Kept as LLR-015: Notification follows the backup outcome.
- LLR-016 — Kept as LLR-016: Restore interaction is LLR-073, avoiding repeated policy.
- LLR-017 — Kept as LLR-017: Liveness and reclaim details become LLR-080/088 children.
- LLR-018 — Merged into LLR-042: a missing document is one configuration-admission refusal, not a separate design.
- LLR-019 — Absent from the supplied legacy carrier; reserved and not reused because there is no source row to carry forward.
- LLR-020 — Kept as LLR-020: Required acquisition and optional degradation replace the retired dependency SR division.
- LLR-021 — Kept as LLR-021: Literal path preservation remains observable and independently testable, not merely a coding style.
- LLR-022 — Kept as LLR-022: Source exclusions are narrowed to the new parent; publication leaves are child LLR-110.
- LLR-023 — Kept as LLR-023: The parent now requires expanded content and allocation/scratch allowances.
- LLR-024 — Kept as LLR-024: Canonical form moves to IF-007.
- LLR-025 — Kept as LLR-025: Record form moves to IF-007; atomic publication remains LLR-087.
- LLR-026 — Kept as LLR-026: Memory implementation detail moves to LLR-114.
- LLR-027 — Kept as LLR-027: Kept for the helper/example agreement decision; a user demonstration still verifies the parent.
- LLR-028 — Kept as LLR-028: Run-state form moves to IF-017; recovery is strengthened by LLR-113/115.
- LLR-029 — Kept as LLR-029 (child of LLR-008): Made a child of LLR-008 for per-entry accounting.
- LLR-030 — Merged into LLR-002, with digest form in IF-009; runtime-specific wrapper and sourceability details belong to tests.
- LLR-031 — Merged into LLR-008 and its recovery children; a runtime route is not a second recovery contract.
- LLR-032 — Split into IF-007 form and LLR-025 decoding; timestamp handling is LLR-066, replacing the obsolete opaque-time rule.
- LLR-033 — Retired as a shell-engine prescription; interoperable writers are covered by LLR-021/024 and container delivery by LLR-048/112. The parent does not require a second engine.
- LLR-034 — Absent from the supplied legacy carrier; reserved and not reused because there is no source row to carry forward.
- LLR-035 — Split: prior-completion safety survives in LLR-028; the old refuse-on-working-state-damage rule is replaced by new LLR-113 under rebuilt SR-035.
- LLR-036 — Kept as LLR-036: Refusal timing and code follow current parent acceptance.
- LLR-037 — Kept as LLR-037: Environment form moves to IF-024; restores remain independent of backup policy.
- LLR-038 — Kept as LLR-038: Witness form moves to IF-008; publication responsibility remains here.
- LLR-039 — Kept as LLR-039: Missing witness now needs positive age evidence under LLR-111.
- LLR-040 — Kept as LLR-040: Value set moves to IF-006/004; current metadata and traversal classification follows rebuilt SR-040.
- LLR-041 — Kept as LLR-041: Adds explicit prior-state retention when preservation cannot succeed.
- LLR-042 — Kept as LLR-042: Form moves to IF-002; both supported forms require version and closed validation.
- LLR-043 — Kept as LLR-043: Opt-in-only classification is replaced by current parent requirements.
- LLR-044 — Absent from the supplied legacy carrier; reserved and not reused because there is no source row to carry forward.
- LLR-045 — Kept as LLR-045: Typed pool form moves to IF-018.
- LLR-046 — Kept as LLR-046: Commit/resume becomes LLR-098; shared admission proof remains.
- LLR-047 — Kept as LLR-047: Inventory form moves to IF-028; bounded index work is LLR-114.
- LLR-048 — Kept as LLR-048: Boundary form moves to IF-023; no single-set host restriction is copied.
- LLR-049 — Kept as LLR-049: Finding form moves to IF-029; repair becomes LLR-099.
- LLR-050 — Kept as LLR-050 (child of LLR-008): Made a child of LLR-008: verified located form is a recovery result.
- LLR-051 — Kept as LLR-051: Absorbs LLR-006/059 as one final-claim decision.
- LLR-052 — Kept as LLR-052: Aggregates the whole invocation before writes, not only one set.
- LLR-053 — Kept as LLR-053: Preserves missing-content reentry and actual-supply adoption.
- LLR-054 — Merged into LLR-049 (whole-pool findings) and LLR-060/076 (supported-kit compatibility); no separate opt-in pool audit.
- LLR-055 — Kept as LLR-055: Platform injection seams move to tests; portable refusal remains.
- LLR-056 — Kept as LLR-056 (child of LLR-008): Made a child of LLR-008: read-back verification is separate from lookup.
- LLR-057 — Merged into LLR-001, LLR-047, LLR-062 and LLR-010; hidden enumeration is required by each responsibility, and the old do-not-follow-links restriction is superseded by LLR-105/106.
- LLR-058 — Kept as LLR-058: Retains deterministic owner election and memoization; private publication prevents overwriting claimed supply.
- LLR-059 — Merged into LLR-051: it duplicated the final-live-claims rule; interruption ordering is strengthened separately in LLR-115.
- LLR-060 — Kept as LLR-060: Profile form is IF-014; supported/current/retired behavior remains.
- LLR-061 — Kept as LLR-061: View form moves to IF-030; forced generation absorbs LLR-064.
- LLR-062 — Kept as LLR-062: Retained for the linear reference-set decision; whole-operation budgets are LLR-114.
- LLR-063 — Split into IF-002 form, LLR-042 validation and LLR-095 placement; configuration history is not rationale.
- LLR-064 — Merged into LLR-061: forced rebuild is the same view-generation obligation with a different trigger.
- LLR-065 — Kept as LLR-065: Folder form moves to IF-012; damaged current metadata follows rebuilt SR-146.
- LLR-066 — Kept as LLR-066: Current malformed timestamps now contribute partial failure while bytes count restored.
- LLR-067 — Kept as LLR-067: The same retry bound also covers initial content reads demanded by SR-067.
- LLR-068 — Kept as LLR-068 (child of LLR-008): Made a child of LLR-008: raw source archives are distinguished by identity.
- LLR-069 — Kept as LLR-069: Grammar moves to IF-010; lossless rejection and decoding remain.
- LLR-070 — Moved to IF-010 form, constrained by LLR-069/021; empty and opaque extensions are not a separate mechanism.
- LLR-071 — Kept as LLR-071: Keeps validated host observations; platform-specific commands are removed.
- LLR-072 — Merged into LLR-009: one physical containment contract covers both routes and indeterminate paths.
- LLR-073 — Kept as LLR-073: Session form is IF-039; target choice follows rebuilt SR-073, not an explicit-picker-only shell exception.
- LLR-074 — Kept as LLR-074: Launcher composition is an implementation choice; origin, hold and passthrough remain observable.
- LLR-075 — Split into IF-033 kit form and LLR-007 delivery; old artifact recognition stays under LLR-022. Carrier-count tests move to the test tier.
- LLR-076 — Kept as LLR-076: Kit revision form is IF-033; compatibility and coherent refresh remain.
- LLR-077 — Retired as a separate design obligation: file read-only attributes are outside the rebuilt fidelity contract. Writable output needed for verification is covered by LLR-056/066; retain regression tests only where they verify those outcomes.
- LLR-078 — Kept as LLR-078: Retains context-sensitive volume exclusion, not a bare-name filter.
- LLR-079 — Merged into LLR-009: physical ancestor resolution is shared across runtime routes.
- LLR-080 — Kept as LLR-080 (child of LLR-017): Made a child of LLR-017; owner form moves to IF-016, test seams move to test tier.
- LLR-081 — Absent from the supplied legacy carrier; reserved and not reused because there is no source row to carry forward.
- LLR-082 — Absent from the supplied legacy carrier; reserved and not reused because there is no source row to carry forward.
- LLR-083 — Absent from the supplied legacy carrier; reserved and not reused because there is no source row to carry forward.
- LLR-084 — Absent from the supplied legacy carrier; reserved and not reused because there is no source row to carry forward.
- LLR-085 — Absent from the supplied legacy carrier; reserved and not reused because there is no source row to carry forward.
- LLR-086 — Kept as LLR-086: Sampling becomes child LLR-109; at-floor behavior follows current SR-081.
- LLR-087 — Kept as LLR-087: Adds durability and linked metadata generations; publication recovery is LLR-115.
- LLR-088 — Kept as LLR-088 (child of LLR-017): Made a child of LLR-017 for safe aside cleanup; infrastructure part becomes child LLR-110.
- LLR-089 — Absent from the supplied legacy carrier; reserved and not reused because there is no source row to carry forward.
- LLR-090 — Kept as LLR-090: Artifact form moves to IF-015; acquisition failure classes follow current SR-086.
- LLR-091 — Kept as LLR-091 (child of LLR-090): Made a child of LLR-090 and absorbs LLR-092/094; read sessions are separate LLR-116.
- LLR-092 — Merged into child LLR-091 under LLR-090; removal is one participant in the common exclusion contract.
- LLR-093 — Merged into LLR-090 (persistent identity) and LLR-022 (invisibility); implementation-site enumeration belongs to the test tier.
- LLR-094 — Merged into child LLR-091 under LLR-090; repair and refresh acquire at their own operation boundary.

## IF-001 retirement

IF-001 is retired as a bundled contract, not reused. Its configuration goes to IF-002/LLR-042; invocation to IF-003/LLR-014; outcome values to IF-004/006 and LLR-043/040; container actions, mounts and default to IF-023/LLR-048; image delivery to IF-034/LLR-112; inventories and findings to IF-028/029 with LLR-047/049; store layout, digest, naming and records to IF-007…014 with LLR-002/005/025/038/060/069/111; kits to IF-033/LLR-007/076; effort and tool overrides to IF-024/LLR-037; capacity to IF-019/020 and LLR-052/023; removal mechanism to LLR-045/046/098. Host scheduling, retention policy and alert translation remain external responsibilities already described by EXT-03 and its relationships; they are not copied into behavioral interface text. The one-set-only convention is dropped because SR-095 requires accepted multi-location configurations without a count warning. Versionless native configuration, absent-witness permissiveness and old busy/capacity codes are superseded by the current SRs. Browse/space views have their own IF-030 rather than being hidden in a container carve-out.

## Decomposition stopping boundary

The child rows each add an independent decision: selected-pool lookup, verified located form, terminal entry accounting, post-write verification, byte-derived form, liveness sampling, safe reclamation, mutation participant scope, bounded compression sampling and root-scoped publication leftovers. Separate runtime implementations do not get duplicate contracts. Further subdivision of individual field codecs, individual refusal messages or individual filesystem calls would repeat their parent decision; those distinctions belong in test dimensions. LLR-114 gives a resource strategy, while the parent SRs retain the end-to-end measured budgets. No test results or historical implementation claims have been promoted to approval.
