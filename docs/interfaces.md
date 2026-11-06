# FileBackup interfaces

The [interface registry](requirements/interfaces.toml) records each owning
surface, its requestors or consumers, the channel, boundary crossings and
verification links. Contract bodies live in the definition documents below.
All rows are Drafted for this rebaseline; no new implementation or approval is
implied by a trace link.

- [Native contract definitions](interfaces/native-contracts.md): IF-002..025,
  including configuration/actions, outcome/reporting, records/content, previous
  definitions, recovery, filesystem/tool boundaries, maintenance and delivery.
- [Interface → LLR → SR → test map](interfaces/trace-map.md): derived parent
  coverage and direct planned test-case links, plus approved boundary coverage.
- [Legacy cleanup decision](plans/native-design-2026-11-05/legacy-cleanup.md):
  retirement of IF-001 and the imported design/test baseline, with history lookup.
- [Interface adoption and review](plans/native-design-2026-11-05/interfaces-review.md):
  migration scope, unresolved design details, validation and Gemini review.

`verified_by` points to the LLRs whose tests cover the interface. Those LLRs carry
the authoritative `sr_refs`; planned cases additionally name IF IDs in `verifies`.
The trace map renders that chain without introducing a second manually authored
SR list in the interface registry. Planned logical module owners are not yet
Rust files. Definition bodies move into their owning implementation when that
binding is established; the documentation must not become a competing copy.

The active registry contains 24 native contracts. IF-001's former HomeHub OCI v1
agreement is available in git at `a184d9a:docs/interfaces/legacy-homehub.md`.
Its retirement here does not change deployed PowerShell/container behavior;
native integration is governed by Drafted IF-019 and its parents.
