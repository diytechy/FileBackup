# Owner review: retention, coordination, compatibility and assurance

Owner direction received 2026-11-05 while reviewing the draft needs. This
record supersedes conflicting proposals in the earlier needs review, fresh
derivation and SR alignment. It does not approve the whole tier or change the
implementation. The amended rows remain Drafted for the owner's continued
review.

| Need | Owner ruling applied |
|---|---|
| SN-029 | History removal establishes a recovery cutoff. Removing history at a date may invalidate that date and all older dependent states; only retained later states and the latest state remain within the recovery promise. Older folders may remain without being usable recovery points. Preserving every other date by relocating shared content is not required. |
| SN-046 | Retention information is supplied when requested from the tool. Storage estimates have limits; warnings cannot ensure understanding. Direct folder deletion can bypass the tool and its reporting entirely. |
| SN-039 | Coordination is scoped to a single configuration. Its backup sets must resolve to unique backup roots; duplicate destinations prevent continuation. Cross-configuration and external-writer coordination are outside this need's promise. |
| SN-041 | Compatibility is a reasonable-effort design objective, with commitments only for designated older versions/combinations and supported continuation, upgrade or migration paths. New designs may require migration. **No older versions are currently designated for support.** |
| SN-033 | A successful recovery result means the documented required integrity checks passed. It is reasonable assurance, not absolute proof against every collision, faulty record, hardware fault or corner case. Detected mismatches or inability to complete required verification still prevent a successful-file result. |

SN-034 received a necessary consistency edit: protection of shared content now
applies to the supported recovery window, with the explicit retention cutoff
exception. Otherwise its blanket protection of every older state would negate
the owner's SN-029 ruling. No additional capability was introduced.

## Downstream reconciliation

The existing SRs and candidate derivation are review inputs, not automatically
updated approvals. The following obligations must be reconciled before their
design and test chains are accepted:

| Scope | Existing SRs / follow-through |
|---|---|
| Retention and shared content | SR-045/046/059/101: replace protection of every older state with the explicit cutoff model, while retaining protection of newer states and the latest state. SR-102 confinement remains relevant. Review SR-035/041/063 where they inherit the broader SN-034 promise. |
| Retention reporting | SR-047: requested estimates and disclosed limits, not guaranteed exact reclamation or enforced consultation. SR-103/104 still govern nonmutating, machine-readable reports when requested. |
| Configuration and exclusion | SR-085/086/106/107/144: apply the single-configuration scope and separate reader availability from writer exclusion. Add explicit duplicate-backup-root admission under the configuration requirements (including SR-042); a lock alone does not satisfy that validation obligation. |
| Upgrade and recovery-kit support | SR-084/110/115/116/117: scope promises to designated support paths, not indefinite compatibility of all older kits. Reconcile SN-040's supported-continuation concept with an explicit designation list, which currently contains no older versions. |
| Recovery verification | SR-056/119: retain required checks, error reporting and applicable recovery behavior, while distinguishing a passed check from proof of universal correctness. Content-identity assumptions DA-05/11 remain relevant limits. |

The Rust migration plan's compatibility-first approach and current-layout
continuation tests remain proposals. They do not designate an older version
for support. Its retention and continuation milestones must be reconsidered
against these rulings before being accepted as release gates.

## Implementation boundary

The current managed prune implementation can relocate shared content to
preserve other states. That is stronger than the revised retention need; this
review does not remove or change it. Direct history-folder deletion has a
different mechanism and bypasses that managed operation. The requirements
must not conflate the two or claim the tool controls all deletion.

Likewise, an existing store lock may protect more than one configuration in
some environments. The revised need deliberately makes a narrower commitment;
it does not assert that different configurations always bypass the current
lock. Configuration validation and supported coordination require their own
implementation assessment.
