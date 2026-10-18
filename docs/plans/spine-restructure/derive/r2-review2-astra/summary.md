# System-requirement review

Reviewed all **115 SR rows** against **48 stakeholder needs**, the external frame, all declared assumptions, the hats roster, and sections 0 and 2 of the supplied review rules.

| Severity | Count |
| --- | ---: |
| BLOCKER | 4 |
| MAJOR | 15 |
| MINOR | 2 |
| **Total** | **21** |

The tier needs revision before approval. Findings identify requirement-contract defects, not claims that the current implementation necessarily has those defects.

## Top five

1. **R2A-001 — BLOCKER — SR-043 contradicts SN-045's outcome distinction.** Configuration refusal and busy/not-ready refusal share value 2 although the need requires distinct outcomes. Resolve the contract before implementing scheduler behavior.
2. **R2A-002 — BLOCKER — Capture and exclusion contracts disagree.** SR-001/SR-074 promise complete capture with only two exclusion classes, while SR-055/SR-089/SR-137 require or allow other omissions. Define successful capture, per-entry failures and intentional exclusions consistently.
3. **R2A-003 — BLOCKER — Recovery precedes checks that forbid mutation.** SR-082's unconditional next-run evidence repair conflicts with refusal and exclusivity gates. Establish admission, ownership and trustworthy recovery evidence before authorizing repair.
4. **R2A-004 — BLOCKER — An unchanged source can require a changed backup record.** SR-024/SR-100 prohibit the record change and saved state that SR-053 explicitly requires in its record-changing healing case. Define no-op behavior to account for store damage.
5. **R2A-007 — MAJOR — Restore capacity omits non-content demand.** SR-023 compares expanded lengths with free space, leaving ordinary small-file allocation, directory metadata and working-space costs outside SN-019's no-midway-capacity-failure promise.

## Other material themes

- The source-root working-state write conflicts with the read-only external frame and leaves the containing folder's modification-time effect unresolved.
- Restore admission gates need explicit precedence over per-entry continuation.
- Repair scope and metadata-degradation policies narrow needs without sufficient derivation.
- Container default-action and credential-format restrictions need an upstream obligation or a properly argued derivation.
- Memory and time criteria need a clearer measurement boundary and workload envelope.
- Disabled media measurement has an uncovered reporting obligation.
- Suspended-holder reclamation must be reconciled with whole-operation exclusive ownership.
- Several rows carry independent decisions or conditions only in acceptance or rationale.

## Scope and method

Read only the requested requirement inputs and review-rules source. **No file under docs/plans was read.** No implementation or test code was read; the findings were assessable from the contracts and declared boundaries. The retired perspective-record sidecar was excluded from review.

No concrete file name or code-carrier name was found in an SR row cell. No instrument-naming finding was manufactured from an acceptance criterion merely describing a scenario; measurement concerns above concern the condition or threshold itself.

The JSON contains the complete findings, each with its severity, rule, affected row identifiers, concrete conflict or omission, and suggested fix. Counts are findings, not unique affected rows. Severity follows plausible ordinary use, including interrupted runs, missing content, invalid names, local filesystem behavior and the suspended-container scenario already declared in the requirements.
