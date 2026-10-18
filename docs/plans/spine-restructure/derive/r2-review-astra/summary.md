# Independent review of the merged system-requirement tier

Reviewed all 107 rows against the 48 stakeholder needs, the external boundary registry, all declared assumptions and the hat roster, using spine-questions sections 0 and 2.

| Severity | Count |
|---|---:|
| BLOCKER | 4 |
| MAJOR | 25 |
| MINOR | 1 |
| Total | 30 |

The tier is not ready for approval. Findings are in `findings.json`; identifiers below refer to that array.

## Five most important findings

1. **R2-001 — BLOCKER: contradictory crash contract (SR-082, SR-110).** Every visible state must remain restorable, yet acceptance permits refusal when publication interrupts matching completeness evidence. Individual atomic renames do not close this gap. Decide whether committed states remain available or a detected unavailable state is permitted, and align the need and requirements.
2. **R2-002 — BLOCKER: completing partial history (SR-041 versus SR-005/SR-059).** A preservation failure is allowed to produce a completed saved state that restores only what it kept. That contradicts complete prior-state preservation. Preserve the committed state or obtain an explicit incomplete-state policy.
3. **R2-006 — BLOCKER: missing prerequisite has opposite outcomes (SR-019/SR-132).** The same absent hashing component mandates refusal in one row and permits automatic acquisition and success in another. Define acquisition and validation phases.
4. **R2-007 — BLOCKER: preservation becomes mandatory repair (SR-059 versus SR-103/SR-109).** Requiring no missing recorded content after every operation contradicts leaving existing damage unchanged during read-only checks and uncertain repairs. Require no newly introduced loss instead.
5. **R2-005 — MAJOR: collision protection is conditioned away (SR-092, SR-031).** The collision safeguard cites an assumption that excludes collisions, while the cross-platform fidelity row lacks its own name-compatibility premise. Separate successful fidelity from mandatory refusal/reporting on incompatible targets.

## Scope and treatment

The seven Pending Owner rulings in merge-notes were treated as known open choices, not defects. Findings concerning those rows address independent issues: for example, the performance predicate and envelope, repeated configuration policies, and source mutation observability. The acknowledged SN-024/SR-048 trace defect remains reportable because it is outside that pending list.

No concrete code-file or shipped-file names were found in the 107 SR row cells. No acceptance cell was rejected merely for describing a test scenario; the report distinguishes observable fit criteria from internal mechanisms and undefined predicates. All named hats resolve to the roster, but the accompanying perspective record required by section 2(c3) is missing.

Coverage was checked by obligation, not merely by citation count. In particular, source-based healing of present-but-corrupt content is absent from SN-031's children, and source-tree membership at links/junctions remains unresolved. Some findings expose need/frame defects that require upward correction rather than an SR-only rewrite.

Code was read only to clarify observation limits and the record/evidence publication interval. Existing code divergence alone was not treated as an SR defect: for example, SR-049's requirement to report altered content is demanded by SN-030 even though the existing default form audit is narrower. This is a requirements review, not a full implementation or test-case audit; no runtime tests were run.
