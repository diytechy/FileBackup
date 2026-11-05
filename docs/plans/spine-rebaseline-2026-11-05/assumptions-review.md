# Environmental assumptions review

Status: draft for owner review. The 22 assumptions and two test surrogates in
[assumptions.toml](../../requirements/assumptions.toml) remain Drafted. The
[approved needs](../../requirements/stakeholder-needs.toml) and
[approved external frame](boundary-approval.md) are unchanged.

An assumption describes what must be true outside the tool for a particular
claim to hold. It does not grant permission to skip required checks, erase an
earlier captured copy, omit a failure or claim success when recovery failed.
The `holds_when` field scopes the claim; `obstacle` identifies what can break
it; `falsifier` describes evidence that would contradict it. A falsifier is not
necessarily something the running tool can detect by itself.

## Main changes to review

- A live source need not be wholly quiet. A coherent version of an individual
  file requires a stable read interval or a consistent view supplied by the
  environment. Size and time comparisons cannot prove that concurrent writes
  were absent. Required retries, preservation of earlier captures and visible
  failures remain product obligations.
- Size and modification time are a detection heuristic. Same-metadata changes
  remain the reason for the owner's configurable content re-read schedule.
- Capacity is an estimate, not reserved space. Safe handling of later exhaustion
  is still required.
- Target names, timestamps, attributes and links have declared limits. Cases
  outside those limits must still be identified and reported; assumptions do
  not exclude collision cases from the requirements.
- Passed integrity checks do not authenticate the origin or completeness of a
  record. An internally consistent but wrong record may result from ordinary
  mistakes as well as deliberate tampering. Content-identity collisions remain
  a disclosed residual risk, not an impossibility claim.
- A complete-store transfer preserves what was available in a coherent source
  store. It cannot recreate content previously removed by retention, and copying
  a live changing store is not automatically a coherent transfer.
- Windows fixtures and Linux restore fixtures establish only their exercised
  cases. They are not evidence of all native hosts, filesystems, removable-drive
  events, network behavior or power-loss durability.

## Row-by-row scope

| Rows | Proposed scope and disposition |
|---|---|
| DA-01 | Retained: namespace publication and power-loss durability are distinct; same-filesystem placement alone is not enough to declare every mount supported. |
| DA-02/03 | Owner-death release and mutual exclusion are conditional on the declared host/store combination. DA-03 retains the approved single-configuration scope. No blanket network-share guarantee. |
| DA-04 | Individual-file consistency limit; no assumption that a complete production tree is quiescent. |
| DA-05 | Residual identity collisions and method/workload suitability, without skipping required checks. Its `accepted_risk` field is proposed until this row is approved. |
| DA-06 | Capacity readings support estimates; they do not reserve space or excuse unsafe failure. |
| DA-07/08 | Metadata, link and name behavior is specific to the target; unsupported cases and collisions remain product reporting obligations. |
| DA-09 | The tool cannot ensure a human or automation recipient acts on results. Its existing risk statement remains proposed, not an approval to make outcomes ambiguous. |
| DA-10 | Recovery prerequisites can be present or provisioned online/offline; no guaranteed package-manager access and no dependence on the native engine. Missing-tool diagnostics remain required. |
| DA-11 | Record provenance and completeness limits apply to accidental as well as adversarial substitution. This does not exempt detected damage from reporting. |
| DA-12 | Documented capture scope must match the owner's intended protection. A familiar system-folder name is not itself authorization to exclude wanted files. |
| DA-13 | Container enforcement depends on the actual launch and platform. A writable mount does not authorize FileBackup to write to the source. |
| DA-14 | Metadata updates are a useful heuristic; content re-reading remains independently required on the configured schedule. |
| DA-15 | Retained: persistence depends on the declared host stack honoring the required operations. Process-kill evidence alone does not establish power-loss durability. |
| DA-16 | Dates aid human interpretation; identity, ordering and equal-date handling cannot rely on a perfectly monotonic or unique clock. |
| DA-17 / SUR-01 | Windows local-NTFS fixture scope only; separate evidence is needed for other claimed environments. |
| SUR-02 | Linux recovery fixture scope only; not evidence for native Linux engine operation or macOS. |
| DA-18 | External tools have declared conformance limits. Embedded implementations remain FileBackup's own verification responsibility. |
| DA-19 | Coherent complete-store handoff within the retained recovery window; remaining older records are not promises of available content. |
| DA-20 | Credential facilities enforce a declared access policy for the execution identity; no unsupported owner-account-only or same-host-only mechanism is imposed. |
| DA-21 | A controlled source-nonmutation test needs attribution of changes. This is a test condition, not a quiet-source prerequisite in production. |
| DA-22 | A suspended process cannot report progress. Timing claims need a declared execution basis and cannot simply ignore delays during available execution. |

Nineteen assumptions and both surrogates were revised; DA-01, DA-03 and DA-15
were retained after review. IDs, statuses, existing boundary references and
surrogate links were preserved. No assumption has been added to the approval
ledger or copied over the standing approval baseline.

## What your review decides

Please check whether these conditions and stated limits are an acceptable
basis for the product you want to support. In particular, consider the
individual-file consistency limit, residual identity/record-integrity limits,
recovery prerequisites, and the distinction between real environment support
and fixture evidence. Their presence in this draft is not a claim that every
listed condition has been measured or that the current implementation meets
every approved need.

Specific supported host/filesystem/tool combinations, timestamp tolerances,
link classes, resource budgets and conformance cases still need to be named
and verified in the system requirements and their design/test breakdown. A
dependency that cannot reasonably be satisfied on an intended host is a
design or support decision to resolve, not a reason to hide an unmet need.

After assumption review, reconcile the existing system requirements with the
approved needs and frame, carrying each accepted dependency into the relevant
requirements and verification evidence. Implementation and legacy test results
will then be compared with that chain.
