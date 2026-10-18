# R3E convergence review

Reviewed all 44 scoped rows against their parents, interface forms and the surrounding tier. No earlier review records or OWNER_SCRATCHPAD.md were read. Requirement registries were not changed.

Counts: BLOCKER 1; MAJOR 5; MINOR 0. Total: 6.

- **R3E-001 — BLOCKER** (LLR-125, LLR-161, SR-144, IF-009, IF-013): Reclaim fencing excludes the store’s location record and leaves a check/write race against successor files.
- **R3E-002 — MAJOR** (LLR-080, LLR-088, LLR-161, IF-044, SR-075): A torn owner without RunId turns empty run folders into content and prevents promised automatic recovery.
- **R3E-003 — MAJOR** (IF-033, LLR-088, LLR-150, LLR-038): Prepared saved states must copy evidence that the shared writer rule forbids copying.
- **R3E-004 — MAJOR** (LLR-159, LLR-130, LLR-040, SR-106, IF-024): A live kit refresh on a supported host with an untestable claim is assigned both retry later (4) and damaged record (3).
- **R3E-005 — MAJOR** (LLR-123, LLR-118, LLR-039, SR-106): Three record/evidence rereads cannot guarantee the promised quiet-store outcome during two-file publication.
- **R3E-006 — MAJOR** (LLR-157, LLR-073, SR-073): The shell route’s desktop prompt and refusal policy contradicts its SR’s desktop folder-choice obligation.
