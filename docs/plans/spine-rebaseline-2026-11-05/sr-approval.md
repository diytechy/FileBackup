# Owner acceptance of system requirements

Date: 2026-11-05 (America/Chicago).

After reviewing the SR draft, the DeepSeek and Gemini reviews, the smaller
reference host and the portable folder-link preference, the owner directed:

> Okay, I think SRs are sufficient for acceptance. What is next in the breakdown?

This accepts all 121 live system requirements as written at `0a17487`.
Their statuses change from Drafted to Approved without changing requirements,
rationales, acceptance criteria or trace references. The act includes the
2 GB available-memory / 100 MiB/s reference host and the in-root relative
folder-link behavior. The other parameters in the accepted rows are now
requirements to satisfy, not measured claims about existing code.

Only the system-requirements registry is refreshed in the approval snapshot.
The ledger records exactly these 121 newly approved IDs. Other snapshots and
approved upstream records retain their bytes. No LLR, test, interface design,
implementation or performance result is approved by this act. Hooks remain
disabled; accepting the tier does not assert that the full spine gate passes.

Validation: strict reference integrity passed with zero findings; documentation
checks found zero broken links. Moving the SRs out of Drafted exposes their
downstream completeness checks: the report now has 261 orphan findings
(previously 131), one inherited interface finding, and 18 requirement-form
findings. The latter include word-based flags on conditional clauses and the
owner's reasonable-assurance wording; they need adjudication rather than an
automatic change of accepted meaning. These are recorded follow-up work, not
grounds for silently withholding the owner's acceptance. No product tests were
run for this status/snapshot-only change.

The earlier review guides and external reports remain evidence of the review,
not competing approvals. SR-137's external-content capture and SR-150/152's
portable in-root links are accepted as written. Remaining details such as
nested external-link handling and the scale fixture's logical/physical counting
basis must be made explicit during design. Any resolution that changes an
accepted outcome returns as a scoped SR amendment, not a silent reinterpretation.

## Next breakdown: design, contracts and verification

1. **Describe the logical architecture and critical flows.** Allocate capture,
   content storage, state publication, history removal, verification/repair,
   configuration/results and independent recovery responsibilities. Define the
   order and failure behavior of backup, interruption recovery, retention and
   restore before selecting Rust modules. Existing PowerShell code is comparison
   evidence, not the required architecture of the Rust implementation.
2. **Define the contracts those flows use.** Specify configuration and outcomes,
   state/content identity, portable path and directory/link records, store/kit
   versions and the shared contract consumed by the PowerShell and bash
   restorers. Pin the scale corpus and resource measurement rules. Resolve
   high-risk details before relying on an implementation or test design.
3. **Decompose into implementable LLRs.** Each LLR names its parent SRs, owned
   responsibility, inputs/outputs, invariants and failure behavior. Use several
   LLRs where one SR spans distinct responsibilities; one LLR may satisfy several
   SRs. Do not mechanically make one LLR per SR or copy stale code symbols.
4. **Design verification alongside the LLRs.** Link SR/LLR obligations to tests
   and fixtures: interrupted publication, late capacity failures, retention
   cutoffs, link relocation/containment, cross-host/script recovery and scale
   budgets. Keep test design distinct from evidence that a test has passed.
5. **Reconcile existing code and tests, then form Rust work packages.** Read each
   legacy LLR/test rationale and classify it as reusable, partial, conflicting,
   obsolete or missing. Preserve sound behavior and retire invalid trace links
   explicitly. The resulting coverage/gap map determines implementation order;
   approving requirements does not justify relabeling existing tests as proof.

The next reviewable deliverable is a design/decomposition package containing
the architecture/flow decisions, interface contracts, Drafted LLRs and proposed
verification coverage. Begin with the store/recovery contract and publication
invariants, because both the native writer and the independent restore scripts
must agree on them. Review that package before broad Rust implementation.
