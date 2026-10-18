# Round-3 design-tier review (reviewer R3O)

Scope:

- **(A)** CMP, IF and LLR rows, checked against the SR and SN tiers, the frame and the hats.
- **(B)** The edited SR rows: SR-121, SR-137, SR-150, SR-151, SR-152, SR-109, SR-045, SR-017 and SR-086, with SN-029.

The rules applied were the pointer rules and spine-questions §0, §2 (part B) and §3. Claims about today's form were checked against the code.

## Counts

| Severity | Count |
|---|---|
| BLOCKER | 3 |
| MAJOR | 21 |
| MINOR | 26 |
| **Total** | **50** |

The full list is in `findings.json`.

### Mechanical checks that passed

- No LLR uses `shall`.
- No child LLR carries `sr_refs`.
- Every `sr_refs`, `parent` and `constrains` reference resolves.
- Every LLR that constrains an IF has `dimensions`, and all of them parse.
- No LLR copies a hat down from its parent.
- Every SR has at least one LLR.
- SR-045 and SN-029 are consistent; no finding.

### Mechanical check that failed

- IF-027 is constrained by no row (R3O-009).

## The five most important findings

1. **R3O-001 (BLOCKER): the claim-lost fence defeats itself.**
   - LLR-125 has the run re-read its owner record before every destructive step.
   - The same row deletes that record just before the saved state is published, and the run state and the collapse come after that (LLR-028, LLR-026).
   - Read literally, every run declares its claim lost. If the check is dropped after publication instead, the collapse's deletes and rewrites run unfenced, which SR-144 forbids.

2. **R3O-002 (BLOCKER): age is excused on non-positive evidence.**
   - LLR-138 treats evidence version 2 as proof that a state predates folder records.
   - The current release already writes DIRECTORIES.csv under version 2.
   - So any existing state whose folder record is lost would restore as 0 instead of SR-146's 1.

3. **R3O-003 (BLOCKER): a removal is refused by its own unfinished work.**
   - LLR-046 refuses a removal whenever a staging area is present.
   - LLR-127 requires a re-run removal to recognise its own marker there and finish it (SR-101).

4. **R3O-005, R3O-006, R3O-004 (MAJOR, part B): refusal outcome values are still ambiguous.**
   - An unreadable owner record gets 4 by one clause of SR-017/LLR-017 and 2 by another (R3O-005).
   - Several leftover and liveness refusals state no value at all (R3O-006).
   - SR-086's requirement says "treat as a live holder", which is busy, while its acceptance gives 2 for access denial and for an unusable claim location (R3O-004).

5. **R3O-012 (MAJOR): derived placement does not follow the component tree.**
   - About 80 of the 128 LLRs land outside the component their own section names.
   - CMP-008 and CMP-018 get none of their rows.
   - Five components own no interface at all.
   - Related: IF-007 puts restore-side variables in a backup-only component (R3O-011).
