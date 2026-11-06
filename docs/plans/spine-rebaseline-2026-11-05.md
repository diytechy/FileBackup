# Requirements spine rebaseline and staged template resync

Status: **needs, active external frame, assumptions and SRs approved; design/LLR decomposition next**.

The [needs approval record](spine-rebaseline-2026-11-05/needs-approval.md)
records the owner's approval of all 49 needs on 2026-11-05, without changing
their normative text. The [boundary approval](spine-rebaseline-2026-11-05/boundary-approval.md)
records approval of 18 entities, 23 active crossings and five external
relationships. B-24 is excluded. The owner has also
[accepted the assumptions](spine-rebaseline-2026-11-05/assumptions-approval.md).
The [SR review guide](spine-rebaseline-2026-11-05/sr-generation-review.md) covers the 121 requirements, their policy choices and legacy dispositions.
The [SR acceptance](spine-rebaseline-2026-11-05/sr-approval.md) records owner
approval and the next design/contracts/LLR/verification breakdown.

The [assumptions review guide](spine-rebaseline-2026-11-05/assumptions-review.md)
explains the revised conditions, residual risks and limits of the test fixtures.
No assumption is approved by its drafting or independent cross-review.

The [boundary review guide](spine-rebaseline-2026-11-05/boundary-review.md)
summarizes the accepted frame corrections and the assumptions worklist.
The inactive B-24 placeholder was removed during SR reconciliation after
SR-093 lost its source-write exception and SR-139 was retired. Approved frame
rows and the standing approval snapshot were not changed by that cleanup.

**Latest owner review:** [Review 01](spine-rebaseline-2026-11-05/owner-review-01.md)
revises SN-029, SN-046, SN-039, SN-041 and SN-033, with a consistency edit to
SN-034. History removal can invalidate all dates at or before its cutoff;
retention reporting does not control external deletion or operator understanding;
coordination is scoped to one configuration with unique backup roots;
legacy support is explicitly designated, with no older versions currently
designated; recovery success reports passed integrity checks, not absolute proof.
Earlier analysis artifacts are marked as review snapshots where these rulings
supersede them.

The owner authorized this work on 2026-11-05, prioritizing the requirements
spine while ai-template is still changing. General hooks remain disabled.
Spine checks can be activated incrementally after they check the intended
records without hiding inherited debt.

## Scope and authority

The product remains trustworthy, space-efficient personal file history with
unattended operation and independent recovery. The new delivery objective is
native backup and maintenance on Windows, Linux and macOS. PowerShell and
bash recovery remain carried with the store and usable without a Rust backup
executable, repository, build toolchain or restore-time download. This is a
target requirement, not a claim that native builds or macOS validation exist.

The three existing stakeholder roles remain: owner, restorer and automation
host. A native installer or a maintainer is not a new stakeholder merely because
the implementation language changes. Container operation remains in scope;
container build/export machinery remains delivery engineering rather than a
new end-user need.

The [implementation audit](../requirements-audit-2026-11-05.md) supplies
evidence of discrepancies. It does not make current code the authority for
what users need. Existing owner rulings in the bounded-run and single-store
plans are inputs to reconciliation. Other mismatches stay visible as unmet
requirements or open decisions.

## Resync completed in this slice

| Surface | Disposition |
|---|---|
| Template source | Committed `e3e399b8d1a0ba0d6e5b27e280eb9e18e7766b54`, extracted with `git archive`; unrelated uncommitted edits in the source checkout excluded. No remote freshness claim. |
| Trace, hats, carrier conversion and release-checklist tools | Exact upstream import closure in `scripts/spine-kit`, hashes in `UPSTREAM.json`; root CLI wrappers use Python 3.11+. |
| Tier questions and four registry templates | Pinned questions in `prompts/spine-questions.md`; examples under this plan's `templates` folder, outside live registries. |
| Existing product harness, PowerShell architecture generator | Preserved; upstream Python architecture helpers are dependencies only. |
| LLR and TC carriers | Converted to TOML with the upstream lossless round-trip check; only one live carrier per tier. |
| TC-255..260 | Repaired the 10-cell/9-column mismatch by retaining both narrative cells in Expected. No scenario or expected outcome discarded. |
| LLR/TC maturity | All Drafted, with historic statuses preserved in the evidence harvest. No old Pass/Verified becomes Approved or Founded. |
| Full-kit policy/process/stage/hooks | Deferred. No full adoption stamp advanced; `docs/kit-version` still describes the earlier whole-kit adoption. |

The trace dependency closure is larger than its four user commands because the
current upstream engine imports shared frame, assumption, snapshot and review
helpers. Keeping it isolated avoids replacing the project's existing harness
and architecture generation with partially configured upstream machinery.

The [legacy evidence harvest](spine-rebaseline-2026-11-05/legacy/evidence-harvest.json)
retains every original LLR row and each corrected TC row, including scenarios,
thresholds, mutation/negative-control instructions, code symbols and historical
statuses. Original CSV bytes are also retained there. These are historical
inputs, not parallel live registries or fresh test results.

Two incoherent trace edges were corrected separately from conversion. TC-226
now reaches system obligations through its two design parents rather than a
redundant SR-081 edge which did not parent both. TC-257 remains attached to
the recovery-location contract LLR-098; the unrelated configuration-admission
LLR-095 and its reciprocal test reference were removed. This repairs the
claimed scope of those links; it does not establish that their old test prose
or removed implementation symbols are current.

## Needs and frame review

The live needs remain in
[stakeholder-needs.toml](../requirements/stakeholder-needs.toml).
There are now 49 Approved needs. SN-055 adds native backup/maintenance; SN-023
owns store interchangeability and SN-022 owns engine-independent shell recovery.
That separation keeps an available restorer from being mistaken for an
available native backup product.

An independent read-only needs review considered all 48 preceding needs. It
used the audit and architecture and is therefore not a blind derivation.
The [needs review](spine-rebaseline-2026-11-05/needs-review.md) records every
row's disposition. The owner subsequently reviewed the amended need text and
approved it in the needs approval record; those earlier analyses remain
historical review inputs.

The frame now distinguishes native release delivery, source reads, store-side
operational records and whole-store handoff. CROSS-PLATFORM reaches
`backup-host` as well as `restore-host`. Assumptions distinguish process
interruption from power loss, local coordination from unsupported multi-host
writers, and display dates from unique state identity. B-24 remains explicitly
retired while its legacy SR references are reconciled; it authorizes no write.

## Downstream decisions after needs approval

The need-level text, including owner review 01, is approved. The following
worklist now guides frame, requirement and design review; it is not a request
to approve the needs again. A proposed change to an approved need must be
identified as an amendment rather than silently introduced downstream.

| Decision | Proposed baseline | Remaining choice / evidence |
|---|---|---|
| N1 — interrupted run (SN-013) | Preserve prior saved states and complete per-file checkpoints; latest may contain partial run progress. | Derive interruption cases and evidence for the approved bounded-run outcome. This does not promise whole-source transactional capture. |
| N2 — space exhaustion (SN-019) | Safe failure and recoverability; useful admission estimates without an impossible future-capacity guarantee. | Whether stronger restore preflight is a required enhancement, and its scope for compressed data. |
| N3 — record integrity (SN-025/026) | Structural validation and verified recovered file content; no claim to detect every well-formed truncation/substitution. | Whether stronger completeness/authenticity evidence is wanted as a future format change. Current R5 removes the witness. |
| N4 — names and links (SN-001/032/036) | No silent omission, aliasing or overwrite. Preserve the requested link-fidelity outcome for explicit disposition. | Portable name/collision policy and exact link-follow/recreate scope; unsupported cases must be explicit. |
| N5 — version support (SN-040/041) | Owner ruled: reasonable-effort compatibility, with commitments only for designated older versions and supported upgrade/migration paths. No older versions are currently designated. | Designate actual version/store/kit combinations and transition paths when support is undertaken; newer designs need not preserve all legacy compatibility. |
| N6 — configuration and concurrency (SN-039) | Owner ruled: one configuration must use unique resolved backup roots and refuse duplicate destinations; coordination is promised within that configuration. | Separate configurations sharing a root are outside the promise. Assess duplicate-root validation and within-configuration exclusion; holder-identification detail remains a downstream choice. |
| N7 — measurable scale (SN-043) | Retain the large-library outcome. | Reference corpus, hardware, RAM and time budgets, and which operations must fit a scheduled window. |
| N8 — repair and metadata (SN-036/047) | Preserve recoverable states and report unfulfilled repairs/metadata. | Closed supported repair classes and whether metadata loss makes recovery incomplete or warning-only. |

Other important unmet outcomes remain requested: semantic change/progress
reporting (SN-044), space/media analysis (SN-051), and redistribution notices
(SN-054). No source change is implied by the wording edits in this slice.

## Decomposition and code attachment sequence

1. The owner has approved the needs, active external frame and assumptions.
   Preserve existing IDs where their outcome survives;
   track retirements and splits explicitly. Authoring does not approve its own rows.
2. Use the input-restricted derivation as a **validation proposal**, then align
   every candidate and all 123 existing SRs: matched, legacy-only or fresh-only.
   Read each legacy rationale before retiring an obligation. A valid unmet
   obligation becomes implementation work, not a weaker need.
3. Reconcile SRs against the accepted scope and operating frame. Resolve the
   audit's A01–A24 individually. Keep current PowerShell behavior, native Rust
   targets and unresolved policy choices distinguishable in the work record.
4. Re-decompose into design contracts and stable interfaces. Keep the current
   schema's `module` and `code_symbol` trace fields until its replacement is
   actually adopted. The older restructure plan's proposed removal of those
   fields is not a shipped schema migration.
5. Reattach existing tests and implementation symbols only after comparing
   behavior with the revised contract. A textual TC mention is a discovery
   lead, not proof. Preserve useful legacy negative controls and thresholds.
6. Run implementation-specific tests and cross-host recovery/continuation
   checks. Approve parents before children through the chosen authority;
   neither syntax checks nor old suite counts approve amended rows.

The scope includes all lifecycle stages: provisioning, configuration/admission,
capture, interrupted work, retention/verification/repair, upgrade, store handoff
and recovery. The Rust plan's R0 exit depends on this work; it is not satisfied
by copying the current engine's function list into requirements.

Review artifacts:

- [Fresh candidate derivation](spine-rebaseline-2026-11-05/fresh-derivation.md):
  82 candidate obligations covering all 49 needs. Its author did not open the
  existing SR/LLR/TC registries or code, but inherited architecture instructions
  were visible; it is input-restricted, not claimed fully blind.
- [Code and test attachment audit](spine-rebaseline-2026-11-05/code-attachment-audit.md):
  all 87 design rows, missing symbols/parents and production back-references.
- [SR alignment](spine-rebaseline-2026-11-05/sr-alignment.md): every existing
  system requirement compared by obligation with the fresh candidates, including
  legacy-only safeguards and fresh-only native/platform proposals. The review
  finds 42 matched outcomes, 63 partial matches/conflicts and 18 legacy-only
  rows; six of the 82 fresh candidates have no direct legacy match.

## Validation of this authoring slice

- The target checker at the pinned revision reads **49 SN / 123 SR / 87 LLR /
  240 TC**. `--strict-integrity` exits 0. All 499 rows are Drafted.
- `--strict --strict-schema` exits 1 with **118 orphan relationships, 235 schema
  findings and one legacy interface-shape finding**. These are inherited
  reconciliation work, not waived or silently hidden. Most schema debt is the
  absent explicit TC evidence field; text naming a historical test is not a new
  executed result.
- The carrier conversion's round-trip oracle passed. A second comparison of
  converted versus final rows confirmed every cell survived except the recorded
  status and three trace-field edits. Original bytes and the evidence harvest
  remain available. UTF-8 is explicit in the validation; an intermediate encoding
  error was detected and corrected before this record.
- All 46 vendored file hashes match the committed source. The hats audit parses
  all nine hats with no unknown tag tokens; CROSS-PLATFORM reaches 24 of 49 needs,
  compared with seven of 48 before the revision. Reach is not adequacy approval.
- The ID watermark starts above live rows and IDs already claimed by production
  annotations, including LLR-150. It does not manufacture missing rows. Historical
  retirement records remain a separate warning and require an ID-history review
  before further allocation.
- The release-checklist CLI runs against the TOML spine. Its IF count is zero
  while the interface registry remains in its old shape: it is not a complete
  release approval artifact until that migration is reconciled.
- Documentation links and whitespace checks pass. The changed PowerShell
  harness parses, and the generated architecture regions remain identical to
  the committed baseline. The Python 3.8 entry-point probe refuses explicitly
  with the 3.11 prerequisite instead of misreading the registries.

No product runtime suite or platform benchmark was rerun: no engine or recovery
implementation changed. Earlier suite results remain historical evidence.
The full product gate is not claimed green while the strict spine check is red.

## Checks and staged hook activation

Manual commands are in the [pinned tooling guide](../../scripts/spine-kit/README.md).
The imported checker now reads all four live tiers. Full strict/schema checks
remain diagnostic until inherited broken references and design/test debt are
resolved; they must not be described as passing because all rows are Drafted.

| Check | Activation condition |
|---|---|
| TOML/carrier and ID integrity | Clean parse, one carrier, preserved IDs, coherent parent links and watermark. |
| Needs/frame/hats review | Relevant perspectives reach actual needs; a zero-error matrix alone does not establish adequacy. |
| Full trace/schema | No unresolved broken parents or fabricated evidence; required fields have meaningful content. |
| Code/test binding | Current symbols and actual test blocks discharge the selected contracts. |
| Product and platform evidence | Existing product gates and native/cross-host matrix run on suitable hosts. |

General git/agent hooks stay disabled. Do not install the current upstream
pre-commit hook wholesale: it also expects the full process/harness adoption.
When the integrity floor is ready, enable a spine-only hook as a separate,
reviewable wiring change. The old whole-kit process documents remain historical
adoption guidance where this staged plan explicitly defers a newer mechanism.
