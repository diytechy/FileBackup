Independent review of the FileBackup design tier and the specified amended SR/SN rows. Reviewed 24 components, 45 interfaces and 128 LLRs against the 123 SR rows, the needs, external frame, assumptions and hats. Part B covers SR-121, SR-137, SR-150, SR-151, SR-152, SR-109, SR-045, SR-017, SR-086 and SN-029. No prior review material or scratchpads were read, and no sub-agents or other reviewers were consulted.

| Severity | Findings |
|---|---:|
| BLOCKER | 9 |
| MAJOR | 17 |
| MINOR | 3 |
| Total | 29 |

The five most important findings are:

1. **R3S-004 — Old content becomes unreachable during publication.** LLR-150 moves content into an unpublished saved state before publishing that state. A kill can strand the only copy needed by an already visible older state. The manifest still verifies, so this produces content loss rather than the permitted damaged-record refusal.
2. **R3S-005 — Capacity planning and claim acquisition require opposite orders.** LLR-052 needs store-dependent demand before creating the claim, while LLR-091 prohibits those reads before acquisition. The preliminary and exact plans need distinct, implementable contracts.
3. **R3S-003 — Required external links are refused as damage.** LLR-141 blocks links that SR-152 and LLR-144 require recreating at their original external destinations. The amended SR-121 already limits the containment rule correctly; its LLR does not.
4. **R3S-001 — The amended SRs disagree on outside ancestor links.** SR-137 says follow an outside link; SR-150 says record an ancestor link even inside a followed outside folder. Their predicates overlap on the cycle case. R3S-002 separately identifies the missing representation for that recorded target.
5. **R3S-009 — The collapse cannot rewrite its normal losing records.** LLR-026 requires blanking redundant references before deleting bytes, but forbids rewriting folders whose referenced copies still exist. That blocks the ordinary two-valid-copy case.

Other material findings cover the amended refusal classification, writes to logs during a configuration refusal, restore-report collisions with user files, removal beside an active reader, stale media measurements, Windows volume identity, age evidence, kit-refresh interruption, interface completeness and dimensional coverage. Each finding in findings.json includes the affected row IDs, governing rule, concrete failure and suggested correction.

The component responsibilities form a coherent backup/restore split; no component-tree finding is raised. All SRs have an LLR path, all explicit constraining LLRs have dimensions, child LLRs carry parent without sr_refs, no LLR uses shall, and the six LLR own-hat records do not duplicate their ancestor SR hats. These structural checks do not establish behavioral coverage: the findings identify the gaps and conflicts that remain. IF-027 has no incoming behavioral constraint.

The retained child-LLR structure generally adds identifiable decisions (encoding, ownership, publication, cleanup, form detection or platform adaptation); no blanket extra decomposition is recommended. R3S-026 identifies the two bundles whose independent decisions still need separating or linking to their existing homes.

This was a static design review, with selected source reads to check current form and feasibility. Only findings.json and summary.md were written in this review folder. No implementation or test changes were made.
