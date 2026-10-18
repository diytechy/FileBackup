# Round 2 derivation notes

## Provenance and blindness qualification

This result is a drafted derivation, not a certified blind result. The opening user message supplied a substantial AGENTS.md excerpt before the derivation brief was read. That information cannot be unseen. No AGENTS.md file, implementation source, legacy requirement registry, test material, other plan or other deriver output was opened. The README was read for its vision and stakeholder vocabulary; an overly broad heading/table extraction also returned design-description tables. Those descriptions were not used as derivation authority. A coordinator requiring strict blindness should rerun in a fresh context without the injected guide and with only the permitted manual sections supplied.

Work was performed alone. The authorized needs, frame, assumptions, hats, schema, and rules sections 0 and 2 supplied the derivation basis. Requirements contain no concrete artifact filenames or code identifiers. Declared configuration/action/outcome vocabulary is retained where useful. No implementation facts from the injected guide are evidence for a row.

Only system-requirements.toml and this notes.md were written, both inside the requested output directory. The shell execution service failed to start; Node filesystem access was used instead. Validation used an existing bundled Python 3.13 interpreter with bytecode writing disabled, without installing anything.

## Need coverage

Each line lists all direct and derived links for one need. Shared delivery is explicit in the requirements. No need is omitted or assigned only to an unnamed sibling. A link is not a claim that the unresolved questions below have been settled.

- SN-001: SR-101, SR-102 (2).
- SN-002: SR-110 (1).
- SN-003: SR-111, SR-112 (2).
- SN-004: SR-115, SR-116 (2).
- SN-005: SR-140, SR-143 (2).
- SN-006: SR-141 (1).
- SN-007: SR-121 (1).
- SN-008: SR-155 (1).
- SN-009: SR-109 (1).
- SN-010: SR-162, SR-163 (2).
- SN-011: SR-156 (1).
- SN-012: SR-167 (1).
- SN-013: SR-122, SR-123 (2).
- SN-015: SR-170, SR-171 (2).
- SN-019: SR-131, SR-132 (2).
- SN-021: SR-116 (1).
- SN-022: SR-142, SR-143 (2).
- SN-023: SR-139 (1).
- SN-024: SR-165 (1).
- SN-025: SR-148 (1).
- SN-026: SR-154 (1).
- SN-027: SR-169 (1).
- SN-029: SR-118, SR-119, SR-172 (3).
- SN-030: SR-128 (1).
- SN-031: SR-127 (1).
- SN-032: SR-105, SR-106 (2).
- SN-033: SR-145 (1).
- SN-034: SR-117, SR-173 (2).
- SN-035: SR-144, SR-156 (2).
- SN-036: SR-151, SR-152, SR-153 (3).
- SN-037: SR-107 (1).
- SN-038: SR-108 (1).
- SN-039: SR-124, SR-125, SR-126 (3).
- SN-040: SR-135, SR-136 (2).
- SN-041: SR-137, SR-138 (2).
- SN-042: SR-149, SR-150 (2).
- SN-043: SR-133, SR-134 (2).
- SN-044: SR-159, SR-160, SR-161 (3).
- SN-045: SR-157, SR-158 (2).
- SN-046: SR-120 (1).
- SN-047: SR-129 (1).
- SN-048: SR-130 (1).
- SN-049: SR-164 (1).
- SN-050: SR-168 (1).
- SN-051: SR-113, SR-114 (2).
- SN-052: SR-102, SR-103, SR-104 (3).
- SN-053: SR-146, SR-147 (2).
- SN-054: SR-166 (1).

## Derived rows and their hats

The quantitative selections below are proposed contract decisions, not discovered implementation behavior. The parents demand bounded behavior; the lenses make its proposed limits explicit. Other hat-attributed rows rest directly on their parents and are not separately classed as derived.

- SR-103 — UNATTENDED-OPS: SN-052 rejects both immediate abandonment and unbounded waiting; five seconds is a proposed finite operating budget requiring owner confirmation.
- SR-133 — PERFORMANCE: SN-043 demands finite budgets; PERFORMANCE supplies these provisional acceptance budgets instead of an unmeasurable promise of scalability. The proposed reference host and limits require owner confirmation.
- SR-134 — PERFORMANCE: SN-043 requires change-driven cost; PERFORMANCE supplies provisional limits and an explicit history-growth comparison rather than accepting a linear history penalty. Owner confirmation is required for these budgets.
- SR-160 — UNATTENDED-OPS: SN-044 requires visibility every few minutes; a proposed two-minute bound makes silence distinguishable from continued work instead of leaving frequency subjective.
- SR-172 — SECURITY: SECURITY derives a containment obligation beyond SN-029's surviving-state guarantee: a crafted removal must not reach unrelated data. Trusting request names loses to an explicit boundary on destructive authority.
- SR-173 — INTEGRITY-RECOVERABILITY: INTEGRITY-RECOVERABILITY derives the auxiliary-state failure case of SN-034 across the external working-state boundary. Treating a lost acceleration or presentation artifact as authority to discard content would turn incidental loss into data loss.

## Possible missing needs or frame premises

- Notification receipt is stronger than message submission at B-09. SN-010 asks that a message arrive, but there is no assumption that an accepting relay delivers to the intended mailbox. SR-162 defines submission and SR-163 failure isolation; end-to-end receipt remains conditional on an absent relay-delivery premise. DA-09 concerns reading and acting, not transport delivery. Do not pretend it closes this gap.
- Exact name fidelity on case-folding or Unicode-normalizing targets is conditional on DA-08. A policy for representational collisions (refusal, alternative target, or renaming with consent) is not specified. No silent translation requirement has been invented.
- Missing or invalid working-state output needs an explicit diagnostic policy. SR-173 prevents content loss; the frame says such failures are reported, but no need clearly fixes whether each auxiliary failure must warn or fail the whole run.
- Container delivery is outside the operational frame, yet SN-054 explicitly requires license compliance for it. SR-166 states the intentional frame exception; a delivery crossing would make that portion directly traceable. Setup documentation has a similar frame granularity limitation recorded in SR-167.
- No need defines who is authorized to prune beyond the owner and delegated backup host. SR-172 confines destructive scope, but an authentication or multi-user permission system would require a new need; it is not inferred.
- No requirement is added merely because the frame mentions a kit refresh, a working artifact or a component call. Every retained row has a need link and an observable boundary result. Internal ownership, publication strategy, file layout, hashing algorithm choice, and retry implementation are left for the design tier.

## Questions and proposed interpretations for coordinator review

- Blindness: accept this qualified derivation for comparison, or rerun cleanly? The exposure above must not be hidden by labeling this output blind.
- SR-103 proposes five seconds total deliberate retry waiting per configured source. The need gives no exact definition of briefly unreadable, retry interval, or run-wide wait budget. Five seconds is not a claim about the current product. Blocking filesystem calls are not covered by this deliberate-wait budget; a total execution timeout would require a separate agreed host contract.
- SR-133 and SR-134 propose a two-TiB, one-million-file reference envelope, four-core host, eight GiB available memory, 200 MiB/s local storage, four GiB process memory, eight-hour full operations and thirty-minute small-change backup. These are Drafted owner-review proposals, not measured performance or recovered legacy limits. Hardware CPU class, corpus compressibility, file-size distribution and filesystem overhead need an approved benchmark profile before claiming conformance. The history comparison requires a nonempty baseline and otherwise identical workload.
- SR-160 resolves a few minutes to two minutes. Confirm that interval; no implementation cadence was consulted.
- HashRecalcFreq supplies value names and calendar frequencies but not detailed scheduling semantics. SR-121 proposes elapsed calendar periods from the last completed full reread, host local time and month-end clamping. Confirm first-run behavior, daylight-saving boundaries, clock rollback and whether daily means calendar-day boundary instead. Initial capture still follows SR-101 regardless of a recheck schedule.
- SN-003 requires measurement irrespective of filename, while the manual exposes CompressProbe off and excluded-extensions choices that can choose by filename. The derivation follows the need (SR-111), not the manual design explanation. The owner must reconcile that contradiction rather than copying an exception into the requirement.
- SN-037 forbids any source mutation. The requirements make that unconditional; any operational state placement must satisfy it. No legacy exception is inferred from the manual.
- SN-040 demands continuation of the previous release but also permits retired-form refusal; define the supported release/form set if the previous release can itself write a retired form. SR-135 and SR-136 preserve both statements pending that ruling.
- SN-041 promises old and new kits recover retained states, while SN-025 refuses damaged or substituted state authority. Define the trust rule for authentic older states that predate newer checks. SR-137 preserves the explicit old-state promise and requires reporting unavailable checks; this is not permission to accept proven damage under SR-148.
- SN-045 demands distinct busy-or-state-refused and configuration-refused results. The manual documents backup codes 0/1/2 and a separate removal classification, but does not supply one unambiguous cross-action numeric map satisfying that need. SR-157 keeps known backup tokens and requires a distinguishable refusal class without inventing a numeric value. Coordinator must settle the result vocabulary and mixed-result precedence for non-restore operations.
- SR-154 uses the manual restore outcome numbers and precedence as declared vocabulary; no implementation exception about archive detection was imported. A preflight missing tool is a precondition; a tool failure during attempted recovery is a host failure.
- SN-019 demands no partial space exhaustion, conditional on DA-06. Define the demand envelope including transient storage and concurrent jobs before claiming capacity sufficiency; no internal estimation formula is prescribed here.
- SR-122 states the need's full endpoint guarantee, not merely detect-and-refuse of a partial latest state. DA-01 and DA-15 restrict the physical durability argument. Confirm supported volume behavior when those premises do not hold; this derivation does not silently weaken the need to match an implementation.
- SR-127 follows the broad damaged-content wording of SN-031, not only its deletion example. Confirm whether source-assisted correction of corruption and relocation is intended as well as deletion.
- SN-046 specifies space actually reclaimed. Define logical stored bytes versus allocated filesystem bytes for compressed, sparse or deduplicating filesystems. The draft compares the same store-size measure before and after removal; no artificial equality between payload length and physical allocation is assumed.
- Empty-directory and attribute obligations follow SN-036 as written. Define treatment of older states without that information, corrupt optional metadata and unsupported target timestamp precision; DA-07 records the target limitation but does not authorize silently discarding supported metadata.
- SN-054 is a delivery obligation even though the system boundary is operation. Its conformance requires component-specific legal inspection later; this derivation makes no assertion that current redistributed components already comply.

## Delivery and assumption review

Direct boundary results use coincident; physical-world delivery arguments cite the assumptions they actually need. No sibling imports another sibling's assumptions. DA-17 is a test-surrogate premise and is deliberately not made a product obligation. DA-09 concerns response to results, not the production of unambiguous results, so reporting rows do not require it to pass. No assumption-form row was manufactured merely to populate that classification: the assumptions remain in their own tier.

## Perspective review record

The kit requests a generated perspective record and its check. Its prescribed implementation is under scripts, which this brief forbids reading or running. That command was therefore not invoked. The following manual record accompanies the decomposition in these notes; it is not represented as a schema-validated replacement for that generated artifact. Hat attribution follows listens_for rather than copying every applicable hat onto every row.

- INTEGRITY-RECOVERABILITY: produced SR-119, SR-122, SR-123, SR-125, SR-127, SR-128, SR-145, SR-148, SR-173. Applicable needs with no separately attributed finding: SN-001, SN-052, SN-032, SN-037, SN-038, SN-009, SN-002, SN-003, SN-051, SN-004, SN-046, SN-021, SN-007, SN-047, SN-048, SN-019, SN-043, SN-040, SN-041, SN-023, SN-005, SN-006, SN-022, SN-035, SN-053, SN-042, SN-036, SN-026, SN-008, SN-011, SN-045, SN-044, SN-010, SN-049, SN-024, SN-054, SN-012, SN-050, SN-027, SN-015. No additional durable-state or unchecked-success decision is needed in these decompositions; transaction safety and verified recovery have explicit homes under SN-013, SN-029, SN-033 and SN-034.
- SECURITY: produced SR-107, SR-149, SR-150, SR-164, SR-165, SR-172. Applicable needs with no separately attributed finding: SN-001, SN-052, SN-032, SN-038, SN-009, SN-002, SN-003, SN-051, SN-004, SN-034, SN-046, SN-021, SN-007, SN-013, SN-039, SN-031, SN-030, SN-047, SN-048, SN-019, SN-043, SN-040, SN-041, SN-023, SN-005, SN-006, SN-022, SN-035, SN-033, SN-053, SN-025, SN-036, SN-026, SN-008, SN-011, SN-045, SN-044, SN-010, SN-054, SN-012, SN-050, SN-027, SN-015. No additional credential, privilege or destructive-path rule is derivable for these capabilities; explicit homes are source immutability, restore containment, prune containment, credentials and container privilege.
- SHARED-CONTENT: produced SR-104, SR-110, SR-117, SR-118, SR-120, SR-129. Applicable needs with no separately attributed finding: SN-003, SN-004, SN-021, SN-013, SN-039, SN-031, SN-048. No separate destructive operation is introduced; retained-content preservation remains the cross-operation obligation under SN-034.
- STORE-FORMAT-COMPATIBILITY: produced SR-130, SR-135, SR-136, SR-137, SR-138, SR-139. Applicable needs with no separately attributed finding: SN-047. No further format obligation beyond continued states and restore-kit compatibility was identified.
- FILESYSTEM-SEMANTICS: produced SR-101, SR-124, SR-131, SR-132, SR-151. Applicable needs with no separately attributed finding: SN-052, SN-032, SN-037, SN-007, SN-013. No additional filesystem guarantee is asserted beyond the row's premises; unsupported-world obstacles remain in the assumption questions above.
- UNATTENDED-OPS: produced SR-102, SR-103, SR-108, SR-114, SR-156, SR-157, SR-160, SR-163, SR-169, SR-170, SR-171. Applicable needs with no separately attributed finding: SN-009, SN-013, SN-039, SN-031, SN-019, SN-026, SN-024. No new prompt, unbounded wait or silent degradation was found beyond the explicit outcome and unattended-operation obligations.
- CROSS-PLATFORM: produced SR-105, SR-106, SR-142, SR-143, SR-153, SR-154. Applicable needs with no separately attributed finding: SN-035, SN-025. Portable names, supported tools and consistent outcomes have explicit homes; this capability introduces no additional platform-specific promise.
- PERFORMANCE: produced SR-133, SR-134. Applicable needs with no separately attributed finding: SN-007, SN-030. SN-043 owns the quantitative resource envelope; no separate per-capability budget is invented for this need.
- LEGAL: produced SR-166. Applicable needs with no separately attributed finding: SN-003, SN-051, SN-005, SN-024, SN-012, SN-015. SN-054 owns the redistribution obligation; this capability does not justify a second component-specific legal requirement.

## Validation and totals

Python tomllib parsed the output and all four reference registries. Every sn_refs, boundary_refs, da_refs, hat_refs and delivered_with resolves. Sibling links share at least one need. All 48 needs have coverage; identifiers are sequential from SR-101 to SR-173. Structural checks also passed for one shall, EARS openings, strongest-parent priority, nonempty keys, permitted verification/form/status values, assumption-or-coincident exclusivity, and permutation grammar. These checks do not claim semantic approval.

- SR count: 73.
- Derived rows: SR-103, SR-133, SR-134, SR-160, SR-172, SR-173.
- Rows per form: interface 65; cross-cutting 8; assumption 0.
- Count per need: see the 48 coverage lines above.
