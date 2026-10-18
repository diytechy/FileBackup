# Strip comparison: SN (astra-sn-sr vs opus-sn-sr)

## Summary

- Rows: 36. Verdicts agree on 33, differ on 3.
- astra-sn-sr verdicts: {'strip': 27, 'flag': 1, 'keep': 7, 'retire': 1}
- opus-sn-sr verdicts: {'strip': 25, 'keep': 9, 'retire': 2}
- Total stripped text: source 11695 chars, astra-sn-sr 7714, opus-sn-sr 10810.

## Verdict disagreements

| id | astra-sn-sr | opus-sn-sr | astra-sn-sr notes | opus-sn-sr notes |
|---|---|---|---|---|
| SN-005 | flag | keep | Kept “no installs” as an obligation, but the declared restore tool floors require tools that a clean host may lack; this is an obligation/co |  |
| SN-007 | strip | keep |  | `HashRecalcFreq` and its codes are declared configuration vocabulary, kept. |
| SN-024 | strip | retire | The runtime capability survives. Local build, export/import and registry distribution belong to delivery outside the product spine; the roun | Container build and image export/publish tooling is delivery, outside the product spine (owner ruling D3). Its only product residue - a back |

## Text distance (lowest similarity first; 1.0 = identical)

| id | similarity | source chars | astra-sn-sr chars | opus-sn-sr chars |
|---|---|---|---|---|
| SN-034 | 0.01 | 692 | 331 | 618 |
| SN-031 | 0.01 | 965 | 535 | 874 |
| SN-036 | 0.02 | 905 | 526 | 744 |
| SN-035 | 0.03 | 626 | 159 | 381 |
| SN-032 | 0.04 | 679 | 468 | 674 |
| SN-025 | 0.04 | 514 | 396 | 425 |
| SN-029 | 0.05 | 969 | 586 | 925 |
| SN-013 | 0.06 | 234 | 300 | 354 |
| SN-008 | 0.08 | 738 | 296 | 511 |
| SN-003 | 0.13 | 90 | 161 | 229 |
| SN-022 | 0.13 | 524 | 363 | 516 |
| SN-030 | 0.14 | 809 | 427 | 736 |
| SN-026 | 0.18 | 490 | 374 | 500 |
| SN-033 | 0.18 | 558 | 345 | 459 |
| SN-027 | 0.26 | 449 | 365 | 444 |
| SN-024 | 0.28 | 450 | 236 | 450 |
| SN-002 | 0.32 | 127 | 90 | 96 |
| SN-007 | 0.50 | 280 | 316 | 280 |
| SN-004 | 0.50 | 253 | 212 | 197 |
| SN-005 | 0.50 | 130 | 112 | 130 |
| SN-015 | 0.57 | 176 | 162 | 199 |
| SN-018 | 0.58 | 195 | 147 | 200 |
| SN-016 | 0.64 | 85 | 106 | 109 |
| SN-021 | 0.66 | 109 | 97 | 104 |
| SN-001 | 0.80 | 122 | 91 | 117 |
| SN-023 | 0.82 | 303 | 258 | 271 |
| SN-012 | 0.89 | 114 | 153 | 165 |
| SN-011 | 1.00 | 109 | 102 | 102 |

## Removal kinds only one proposer made

| id | only astra-sn-sr | only opus-sn-sr |
|---|---|---|
| SN-003 | contradiction | stale |
| SN-005 | instrument |  |
| SN-007 | mechanism |  |
| SN-008 | mechanism | stale |
| SN-022 |  | file |
| SN-024 | code, instrument, mechanism |  |
| SN-026 | code, instrument | provenance |
| SN-028 | instrument |  |
| SN-029 | contradiction | stale |
| SN-030 |  | provenance |
| SN-031 |  | code, provenance |
| SN-032 | contradiction | code, file |
| SN-033 |  | code, mechanism |
| SN-034 | mechanism | code, file |
| SN-036 | contradiction | stale |
| SN-021 | mechanism | file |

