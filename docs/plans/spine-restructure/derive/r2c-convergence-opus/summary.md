# r2c convergence review (Opus): SR tier, 49 changed rows

| Severity | Count |
|---|---|
| BLOCKER | 0 |
| MAJOR | 1 |
| MINOR | 0 |

- R2C-OPUS-01 (MAJOR): a backup that finds an unidentifiable damaged record is routed through SR-082/SR-110 to SR-017, whose catch-all gives value 2. SR-043, SR-046 and SR-039/SR-040 give 3 for a damaged record, so no row lets a backup return 3.
