# Owner approval of stakeholder needs

Date: 2026-11-05 (America/Chicago).

The owner reviewed the stakeholder-needs registry, requested the corrections
recorded in [owner review 01](owner-review-01.md), then explicitly directed:

> This looks good, stakeholder needs can be approved, boundaries are next?

The approved text is the need-tier content at commit `3363994`. This approval
changes only the 49 need statuses from Drafted to Approved; no normative need
text changed in the approval act. The IDs are listed below to make its scope
explicit. This records the owner's decision, not an agent self-approval.

`SN-001`, `SN-002`, `SN-003`, `SN-004`, `SN-005`, `SN-006`, `SN-007`, `SN-008`, `SN-009`, `SN-010`, `SN-011`, `SN-012`, `SN-013`, `SN-015`, `SN-019`, `SN-021`, `SN-022`, `SN-023`, `SN-024`, `SN-025`, `SN-026`, `SN-027`, `SN-029`, `SN-030`, `SN-031`, `SN-032`, `SN-033`, `SN-034`, `SN-035`, `SN-036`, `SN-037`, `SN-038`, `SN-039`, `SN-040`, `SN-041`, `SN-042`, `SN-043`, `SN-044`, `SN-045`, `SN-046`, `SN-047`, `SN-048`, `SN-049`, `SN-050`, `SN-051`, `SN-052`, `SN-053`, `SN-054`, `SN-055`.

The three stakeholder records in the same file retain their existing Drafted
statuses. The external frame, assumptions, system requirements, design rows and
test cases are not approved by this act. Product behavior and hook activation
are unchanged. Approval of needs is not a claim that current code satisfies them.

The initial approval baseline is seeded through the pinned snapshot writer so
later changes to approved need text can be detected. It copies the live registry
set as context; each copied row retains its own status. Drafted rows in that
baseline are not approvals. The generated act ledger must name exactly these
49 SN IDs and no other row as newly approved.

## Next review

Review [external.toml](../../requirements/external.toml): external entities,
boundary crossings and relationships outside the system. Check the system's
scope and the information crossing it, rather than internal modules or methods.
Then review [assumptions.toml](../../requirements/assumptions.toml), which states
what the environment must supply for those outcomes to hold. The design of
interfaces and implementation components comes after the system requirements.

Known frame items to reconcile during that review:

- B-04 must reflect coordination within one configuration with unique roots.
- B-13 and the backup-folder description must account for the retention cutoff;
  surviving older folders need not be supported recovery points.
- B-16 should describe link information consistently with the approved fidelity
  need, leaving exact supported link classes to decomposition.
- B-24 is a retired source-write placeholder awaiting removal with its stale
  SR references. It is not an active boundary to approve.
- Tool provisioning, container access and restore capacity entries should state
  exchanges with the environment without introducing guarantees beyond the
  approved needs.
