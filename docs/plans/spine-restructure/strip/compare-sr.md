# Strip comparison: SR (astra-sn-sr vs opus-sn-sr)

## Summary

- Rows: 81. Verdicts agree on 78, differ on 3.
- astra-sn-sr verdicts: {'strip': 76, 'keep': 2, 'flag': 2, 'retire': 1}
- opus-sn-sr verdicts: {'strip': 77, 'keep': 2, 'retire': 2}
- Total stripped text: source 141940 chars, astra-sn-sr 68558, opus-sn-sr 125921.

## Verdict disagreements

| id | astra-sn-sr | opus-sn-sr | astra-sn-sr notes | opus-sn-sr notes |
|---|---|---|---|---|
| SR-033 | flag | strip | The current engine uses unconditional content addressing and probe-based compression; the named bash backup engine does not exist in bash/.  | No Linux backup engine exists yet (Draft, SN-023 priority C); the HashAddressed mode and extension-only compression it cited are gone, so th |
| SR-034 | strip | retire | Container build, offline export and registry distribution are delivery, outside the product spine. The non-root runtime, portable configurat | Container build, offline-tar export and registry publish/pull are delivery tooling, outside the product spine (owner ruling D3); their proof |
| SR-052 | flag | strip | The no-mutation obligation is retained and flagged: source scanning, backup-index sanitation and staging the prior index visibly precede the | The acceptance had a provenance frame spliced mid-clause ('created; ... (WP7 review ...) or modified'); the two clauses are separated withou |

## Text distance (lowest similarity first; 1.0 = identical)

| id | similarity | source chars | astra-sn-sr chars | opus-sn-sr chars |
|---|---|---|---|---|
| SR-072 | 0.01 | 1561 | 876 | 1455 |
| SR-017 | 0.01 | 4402 | 1454 | 3734 |
| SR-050 | 0.01 | 2339 | 892 | 2044 |
| SR-087 | 0.01 | 2071 | 858 | 1726 |
| SR-081 | 0.01 | 9761 | 3363 | 8650 |
| SR-005 | 0.02 | 1275 | 843 | 1130 |
| SR-083 | 0.02 | 1645 | 1123 | 1674 |
| SR-071 | 0.02 | 1710 | 1180 | 1652 |
| SR-053 | 0.02 | 1740 | 872 | 1686 |
| SR-039 | 0.02 | 2127 | 1216 | 2033 |
| SR-040 | 0.02 | 3767 | 1780 | 3144 |
| SR-052 | 0.02 | 2564 | 1225 | 2200 |
| SR-075 | 0.02 | 16839 | 3798 | 12098 |
| SR-004 | 0.02 | 2683 | 1296 | 2418 |
| SR-057 | 0.02 | 1610 | 761 | 1411 |
| SR-019 | 0.03 | 477 | 501 | 512 |
| SR-086 | 0.03 | 2608 | 1456 | 2512 |
| SR-003 | 0.03 | 1145 | 565 | 1081 |
| SR-068 | 0.03 | 1978 | 828 | 1958 |
| SR-074 | 0.03 | 2937 | 1086 | 2728 |
| SR-085 | 0.03 | 6320 | 2047 | 5358 |
| SR-042 | 0.03 | 5518 | 2856 | 5056 |
| SR-056 | 0.03 | 1461 | 1023 | 1361 |
| SR-067 | 0.03 | 1096 | 702 | 1072 |
| SR-061 | 0.04 | 4345 | 1688 | 3987 |
| SR-046 | 0.04 | 5734 | 2451 | 5506 |
| SR-045 | 0.04 | 2864 | 1323 | 2602 |
| SR-051 | 0.04 | 1087 | 795 | 985 |
| SR-055 | 0.04 | 2252 | 1172 | 2107 |
| SR-028 | 0.04 | 715 | 564 | 746 |
| SR-049 | 0.04 | 2991 | 1442 | 2604 |
| SR-065 | 0.04 | 1760 | 1154 | 1767 |
| SR-082 | 0.05 | 2386 | 1022 | 1659 |
| SR-007 | 0.05 | 1553 | 730 | 1214 |
| SR-084 | 0.05 | 886 | 481 | 759 |
| SR-063 | 0.06 | 2156 | 1262 | 2220 |
| SR-043 | 0.06 | 1821 | 850 | 1830 |
| SR-038 | 0.07 | 1576 | 971 | 1338 |
| SR-064 | 0.07 | 706 | 427 | 620 |
| SR-062 | 0.08 | 1002 | 762 | 960 |
| SR-054 | 0.08 | 1632 | 851 | 1555 |
| SR-073 | 0.09 | 1405 | 920 | 1189 |
| SR-070 | 0.10 | 1185 | 449 | 737 |
| SR-009 | 0.10 | 1392 | 801 | 1268 |
| SR-069 | 0.11 | 2172 | 1180 | 1931 |
| SR-023 | 0.11 | 338 | 346 | 345 |
| SR-013 | 0.12 | 723 | 375 | 731 |
| SR-034 | 0.12 | 970 | 474 | 970 |
| SR-037 | 0.12 | 1714 | 1076 | 1611 |
| SR-047 | 0.12 | 698 | 383 | 702 |
| SR-033 | 0.12 | 671 | 464 | 649 |
| SR-059 | 0.13 | 566 | 463 | 584 |
| SR-031 | 0.13 | 1099 | 838 | 1081 |
| SR-066 | 0.14 | 804 | 407 | 615 |
| SR-022 | 0.15 | 383 | 349 | 366 |
| SR-024 | 0.15 | 346 | 269 | 271 |
| SR-015 | 0.16 | 57 | 84 | 51 |
| SR-010 | 0.19 | 649 | 440 | 638 |
| SR-016 | 0.21 | 1032 | 591 | 939 |
| SR-008 | 0.26 | 206 | 269 | 250 |
| SR-006 | 0.26 | 401 | 450 | 385 |
| SR-029 | 0.28 | 762 | 447 | 730 |
| SR-041 | 0.30 | 948 | 572 | 880 |
| SR-058 | 0.30 | 576 | 393 | 493 |
| SR-048 | 0.33 | 1958 | 1249 | 1873 |
| SR-021 | 0.33 | 251 | 217 | 253 |
| SR-025 | 0.33 | 600 | 527 | 612 |
| SR-011 | 0.36 | 477 | 394 | 494 |
| SR-032 | 0.36 | 703 | 629 | 695 |
| SR-030 | 0.39 | 577 | 361 | 537 |
| SR-035 | 0.43 | 569 | 416 | 522 |
| SR-060 | 0.43 | 331 | 216 | 271 |
| SR-002 | 0.49 | 426 | 394 | 375 |
| SR-026 | 0.53 | 173 | 131 | 148 |
| SR-020 | 0.63 | 367 | 410 | 412 |
| SR-001 | 0.66 | 559 | 345 | 471 |
| SR-036 | 0.67 | 397 | 303 | 312 |
| SR-027 | 0.80 | 355 | 380 | 378 |

## Removal kinds only one proposer made

| id | only astra-sn-sr | only opus-sn-sr |
|---|---|---|
| SR-002 | provenance | file |
| SR-003 | mechanism | file |
| SR-006 | mechanism |  |
| SR-007 |  | code |
| SR-008 |  | file |
| SR-009 | mechanism | code, file, stale |
| SR-010 | mechanism |  |
| SR-011 |  | file |
| SR-013 |  | instrument |
| SR-016 |  | file |
| SR-017 |  | code, file |
| SR-019 |  | file |
| SR-020 |  | file |
| SR-021 | mechanism, provenance | code |
| SR-022 |  | code |
| SR-023 | code |  |
| SR-024 |  | file |
| SR-025 | instrument, provenance | file |
| SR-028 | mechanism, provenance | code, file |
| SR-027 |  | code |
| SR-029 |  | file |
| SR-030 |  | code |
| SR-031 |  | contradiction |
| SR-032 | instrument | file |
| SR-034 | instrument, mechanism, provenance |  |
| SR-036 |  | file |
| SR-038 | mechanism | code |
| SR-039 | mechanism | code |
| SR-040 | mechanism | code, file, stale |
| SR-042 |  | file |
| SR-043 |  | stale |
| SR-044 | instrument |  |
| SR-045 | mechanism | code, file |
| SR-046 | instrument | code, file |
| SR-047 | mechanism | file |
| SR-048 |  | file, stale |
| SR-049 |  | file, stale |
| SR-050 |  | code, file, instrument, stale |
| SR-051 |  | code, file |
| SR-052 |  | code, file |
| SR-053 | mechanism | file |
| SR-054 |  | file |
| SR-055 |  | code, file |
| SR-056 | mechanism | file |
| SR-058 | contradiction | stale |
| SR-059 | instrument, mechanism |  |
| SR-060 | mechanism |  |
| SR-061 |  | file |
| SR-062 |  | code, file |
| SR-063 |  | stale |
| SR-064 | code | file, stale |
| SR-065 | mechanism | code |
| SR-066 | stale | file |
| SR-067 | contradiction | code |
| SR-068 | mechanism | code |
| SR-069 |  | code |
| SR-070 | stale |  |
| SR-071 |  | file |
| SR-073 | provenance | code |
| SR-074 | file | code |
| SR-075 | instrument | code, file |
| SR-081 |  | code, file, stale |
| SR-082 | mechanism | code, file |
| SR-083 | instrument | code |
| SR-084 |  | file |
| SR-085 | mechanism | code, file |
| SR-086 | mechanism | code, file, stale |
| SR-087 |  | code, file |

