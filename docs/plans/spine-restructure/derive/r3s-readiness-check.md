# Round 3s: is the architecture ready for test cases? (session 2026-10-18 d)

The eight-item entry list from
[../architecture-breakdown-research.md](../architecture-breakdown-research.md)
§6 (drawn from NASA NPR 7123.1 SDR/PDR criteria, DAU, ATAM and ISO 42010's
correspondence rules), applied to FileBackup's design tier at `850f8a6`.
Items 1 to 4 were computed from the registries and `docs/runtime-flows.md`.
Items 5 to 8 were judged. Fixes that were the design's own are applied
(`r3-merged/_r3s_apply.py`). What remains is either waiting on an
ai-template rule or is the Owner's call.

| # | Item | Result | Fixed in round 3s | Remaining |
|---|---|---|---|---|
| 1 | Allocation complete both ways | Every one of the 12 leaf components now carries a placed row (after the Owner's folds). 41 SRs have no LLR row landing on a component. | None needed on the component side. | The 41 SRs, which split into groups A and B under item 3. **Kit rule needed.** |
| 2 | Interfaces consistent | IF-017 (folder record) and IF-018 (link record) were constrained by no LLR. Every external interface has a local consumer. | LLR-065 now constrains IF-017; LLR-110 constrains IF-018. | None. The store format's interfaces are owned by the one shared definition (CMP-016), not by the writers; that is the design's stated choice. |
| 3 | Behaviour and structure correspond | Every flow participant is a component. Five flow steps were drawn on the wrong component. 56 citations disagree with placement after the fixes. | Flow 2: the run-state read moved to publication, the location record noted as opened, not done by the guard, a mis-cited LLR removed. Flows 3 and 7: the claim test is made by the reader or the removal, not the guard. | **A (21):** rows constraining an external interface, done by a clear component, placed at the root. **B (23):** rows constraining no interface, done by a clear component, unplaced. **C (12):** rows placed at the owner of the interface they constrain while another component does the work: publication rows at the store format (LLR-087, LLR-118, LLR-068), the reader rule at the claim's owner (LLR-123), the dry run at the launch component (LLR-163). All three groups are ai-template's placement rule, not this design (research recs 1, 2 and 4). |
| 4 | Scenario coverage | 37 SRs appeared in no flow. | Flows now render the empty-source refusal, retries, the change-detection record's location, healing lost content, the space view's media rate, the run's reads, credential handling and the shell route's tool flavour. The 23 that are static rules are declared flow-free in `runtime-flows.md`. | None: every SR is in a flow or declared flow-free. |
| 5 | Modes checked | Neither state flow had the mid-work failure ending (a host fault gives 4, a location failure 1). | Both state flows gain a Failed ending. | Disjointness is by inspection only; no condition table exists (SCR check B is unbuilt in the kit). |
| 6 | Quality-attribute scenarios analysed | Crash consistency is enumerated (LLR-162's staging table), and concurrent readers and stale reclaim are drawn (flows 3 and 4). No list of risks, sensitivity points or trade-offs exists. | Nothing yet. | **Owner's call:** an ATAM-lite page for the data-integrity qualities. Its trade-offs are already decided (P-03, P-04, P-13); this would record them as one analysed set. |
| 7 | Decisions recorded with alternatives | `r3-dispositions.md` (K01..K38, P-01..P-16, every review finding) and `r3o-decomposition.md` (Calls 1 to 4) record context, alternatives, decision and consequences. | None needed. | They live in the plan records, not beside the component or interface they shape; acceptable until the kit says otherwise. |
| 8 | A verification approach per external interface | Not written. 13 external interfaces (the source tree, the restore target, the host session and dialog, the tool floors, volume space, the archive tool, the media probe, the package source, the credential facility) have no stated way for a test to drive or observe them. | Nothing yet. | **Owner's call, and a round-4 prerequisite:** one line per external interface saying how a test stimulates or observes it (a real fixture, a surrogate, a mock, or attest). |

## What this means for the order

- **Items 2, 4 and 5 are closed.** Item 3's own errors are fixed.
- **Items 1 and 3's residue (groups A, B and C) is ai-template's placement
  rule.** Round 4 places most of group B through each test case's observed
  interface; groups A and C need the kit to place by local endpoint and by
  performer (research recs 1 and 2). FileBackup can state its intended
  placement now, in the flows, which is what they already show.
- **Items 6 and 8 are new work.** Item 8 must exist before round 4; item 6 is
  recommended at the same point.
