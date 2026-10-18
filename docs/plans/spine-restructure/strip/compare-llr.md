# Strip comparison: LLR (astra-llr vs opus-llr)

## Summary

- Rows: 86. Verdicts agree on 82, differ on 4.
- astra-llr verdicts: {'strip': 80, 'keep': 2, 'flag': 2, 'retire': 2}
- opus-llr verdicts: {'strip': 80, 'keep': 3, 'retire': 3}
- Total stripped text: source 98903 chars, astra-llr 51729, opus-llr 79096.

## Verdict disagreements

| id | astra-llr | opus-llr | astra-llr notes | opus-llr notes |
|---|---|---|---|---|
| LLR-006 | strip | keep |  | Already contract voice; (hash,size) and B9 are content-key and edge-case vocabulary. |
| LLR-017 | flag | strip | The 600 s wait bound is retained, not stripped: current code caps the declared cadence at 600 s and then adds a 30 s margin, allowing a 630  | The 8 KB cell is one obligation family (the staging lock's acquire/reclaim/release contract); nothing is re-homed or split. Refusal tokens a |
| LLR-047 | flag | strip | Retained the O(stored objects) claim, but the code keeps a DataPath entry per non-blank manifest row, including duplicate references, so tha | The '.ToArray()' clause is a language pitfall of the implementation, not a contract; it is a coding note (AGENTS.md), not lost. The test-hel |
| LLR-089 | strip | retire | Kept compatibility with older restore kits rather than retiring a row that also contains release history. | The row records one kit-revision bump and its compatibility consequence for one change; that is history (log). Its durable remnants are alre |

## Text distance (lowest similarity first; 1.0 = identical)

| id | similarity | source chars | astra-llr chars | opus-llr chars |
|---|---|---|---|---|
| LLR-034 | 0.00 | 368 | 0 | 368 |
| LLR-044 | 0.00 | 612 | 0 | 612 |
| LLR-042 | 0.01 | 3425 | 1523 | 2076 |
| LLR-051 | 0.02 | 679 | 306 | 486 |
| LLR-089 | 0.02 | 558 | 391 | 558 |
| LLR-062 | 0.03 | 229 | 233 | 285 |
| LLR-087 | 0.04 | 1554 | 763 | 1043 |
| LLR-076 | 0.04 | 1511 | 384 | 552 |
| LLR-067 | 0.04 | 1629 | 776 | 1099 |
| LLR-038 | 0.05 | 1484 | 883 | 1253 |
| LLR-016 | 0.05 | 1153 | 579 | 979 |
| LLR-053 | 0.05 | 640 | 362 | 600 |
| LLR-052 | 0.06 | 1854 | 1070 | 1650 |
| LLR-078 | 0.06 | 1181 | 510 | 1106 |
| LLR-091 | 0.07 | 1809 | 1088 | 1488 |
| LLR-059 | 0.07 | 999 | 476 | 655 |
| LLR-093 | 0.07 | 651 | 294 | 456 |
| LLR-054 | 0.08 | 1155 | 759 | 996 |
| LLR-065 | 0.08 | 1934 | 1251 | 1840 |
| LLR-079 | 0.08 | 612 | 344 | 599 |
| LLR-050 | 0.09 | 1433 | 620 | 1093 |
| LLR-004 | 0.09 | 3773 | 1295 | 1691 |
| LLR-086 | 0.09 | 8085 | 2623 | 4497 |
| LLR-033 | 0.09 | 272 | 263 | 341 |
| LLR-070 | 0.09 | 380 | 243 | 312 |
| LLR-080 | 0.09 | 5876 | 2395 | 4825 |
| LLR-047 | 0.10 | 2400 | 1135 | 1657 |
| LLR-030 | 0.10 | 420 | 278 | 448 |
| LLR-073 | 0.10 | 1136 | 601 | 1089 |
| LLR-057 | 0.10 | 1681 | 563 | 817 |
| LLR-058 | 0.11 | 1156 | 614 | 742 |
| LLR-072 | 0.11 | 762 | 613 | 881 |
| LLR-045 | 0.11 | 1983 | 1114 | 1670 |
| LLR-069 | 0.11 | 1177 | 879 | 1314 |
| LLR-017 | 0.11 | 4751 | 2422 | 4030 |
| LLR-043 | 0.12 | 1268 | 614 | 918 |
| LLR-066 | 0.12 | 880 | 499 | 829 |
| LLR-035 | 0.14 | 364 | 309 | 334 |
| LLR-088 | 0.14 | 1096 | 754 | 1023 |
| LLR-055 | 0.14 | 929 | 496 | 665 |
| LLR-071 | 0.14 | 1083 | 663 | 1124 |
| LLR-094 | 0.15 | 1586 | 793 | 1344 |
| LLR-040 | 0.15 | 2657 | 1252 | 1887 |
| LLR-077 | 0.15 | 664 | 379 | 534 |
| LLR-046 | 0.15 | 3380 | 1866 | 2997 |
| LLR-075 | 0.15 | 573 | 426 | 592 |
| LLR-007 | 0.15 | 601 | 519 | 629 |
| LLR-005 | 0.16 | 500 | 418 | 652 |
| LLR-061 | 0.16 | 640 | 585 | 759 |
| LLR-025 | 0.16 | 331 | 307 | 361 |
| LLR-049 | 0.16 | 5351 | 2122 | 3676 |
| LLR-028 | 0.17 | 783 | 501 | 638 |
| LLR-090 | 0.18 | 1147 | 770 | 885 |
| LLR-063 | 0.19 | 1027 | 602 | 650 |
| LLR-014 | 0.20 | 159 | 153 | 224 |
| LLR-002 | 0.21 | 194 | 195 | 265 |
| LLR-056 | 0.22 | 1031 | 620 | 925 |
| LLR-031 | 0.22 | 633 | 562 | 739 |
| LLR-068 | 0.22 | 1135 | 620 | 1118 |
| LLR-037 | 0.23 | 1245 | 779 | 1322 |
| LLR-074 | 0.26 | 744 | 431 | 737 |
| LLR-092 | 0.26 | 693 | 493 | 674 |
| LLR-060 | 0.26 | 1116 | 487 | 711 |
| LLR-064 | 0.26 | 186 | 156 | 165 |
| LLR-001 | 0.29 | 169 | 190 | 255 |
| LLR-023 | 0.30 | 466 | 301 | 597 |
| LLR-008 | 0.30 | 187 | 232 | 221 |
| LLR-039 | 0.30 | 1174 | 679 | 1089 |
| LLR-026 | 0.30 | 866 | 504 | 712 |
| LLR-011 | 0.33 | 163 | 163 | 221 |
| LLR-003 | 0.35 | 210 | 197 | 233 |
| LLR-029 | 0.36 | 343 | 291 | 341 |
| LLR-041 | 0.37 | 506 | 365 | 431 |
| LLR-021 | 0.38 | 351 | 216 | 385 |
| LLR-010 | 0.42 | 482 | 435 | 512 |
| LLR-018 | 0.45 | 97 | 112 | 188 |
| LLR-032 | 0.46 | 380 | 302 | 352 |
| LLR-048 | 0.51 | 1006 | 626 | 905 |
| LLR-036 | 0.56 | 262 | 225 | 256 |
| LLR-022 | 0.63 | 258 | 228 | 225 |
| LLR-020 | 0.75 | 197 | 155 | 175 |
| LLR-027 | 0.77 | 165 | 204 | 188 |
| LLR-015 | 0.81 | 161 | 146 | 183 |
| LLR-006 | 0.98 | 142 | 137 | 142 |

## Removal kinds only one proposer made

| id | only astra-llr | only opus-llr |
|---|---|---|
| LLR-004 | contradiction, file |  |
| LLR-005 | instrument | file, mechanism |
| LLR-006 | provenance |  |
| LLR-010 | provenance |  |
| LLR-014 | file |  |
| LLR-015 | provenance |  |
| LLR-016 | file |  |
| LLR-017 |  | file |
| LLR-018 |  | contradiction |
| LLR-022 |  | file |
| LLR-023 | code |  |
| LLR-025 |  | mechanism |
| LLR-028 | file, instrument | stale |
| LLR-030 |  | provenance |
| LLR-031 |  | code, stale |
| LLR-032 | file |  |
| LLR-033 |  | code, stale |
| LLR-034 | code, instrument | mechanism |
| LLR-035 |  | file |
| LLR-036 |  | file |
| LLR-037 | file | stale |
| LLR-038 | file |  |
| LLR-040 | file | instrument |
| LLR-042 |  | mechanism, provenance |
| LLR-043 | file |  |
| LLR-045 |  | file, mechanism |
| LLR-046 |  | file, stale |
| LLR-047 | file |  |
| LLR-051 | code |  |
| LLR-052 | contradiction, file | provenance, stale |
| LLR-053 |  | instrument |
| LLR-057 | file | stale |
| LLR-059 | contradiction | code, stale |
| LLR-061 |  | code |
| LLR-062 | file |  |
| LLR-063 | file |  |
| LLR-065 |  | provenance |
| LLR-066 |  | provenance |
| LLR-067 | provenance |  |
| LLR-068 |  | provenance |
| LLR-069 | file |  |
| LLR-074 |  | file, provenance |
| LLR-076 | file |  |
| LLR-079 | file |  |
| LLR-080 | file | mechanism |
| LLR-086 | file, stale | mechanism |
| LLR-087 | instrument | provenance |
| LLR-089 | code, file |  |
| LLR-090 | instrument |  |
| LLR-091 | instrument |  |
| LLR-092 | instrument | file |
| LLR-093 | file | provenance |
| LLR-094 | file | provenance |

