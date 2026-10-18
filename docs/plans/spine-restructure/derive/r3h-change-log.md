# Round 3h change log: closing the design tier

Applied by `r3-merged/_r3h_apply.py` (re-runnable from git HEAD) from
`r3-dispositions.md`, "Closing the design tier". The Owner was present and
ruled P-14 (a), P-15 and P-16. The coordinator applied the rest. Structural
check after the edit: `validate_design.py r3-merged` reports 0 errors, 140 LLR
(110 top-level, 30 child), every SR reaching an LLR, and the 14 warnings it
gave before (on-disk names in interface forms).

| Finding or ruling | Rows | What changed |
|---|---|---|
| P-14 (a), R3G-003 | SR-039, SR-082, SR-110, LLR-039, LLR-123 | The SRs admit 4 where the restore cannot test the claim. The 4 message names the remedy and states that the record is damaged unless a changing operation is running. SR-039's permutations gain `claim_test`. |
| R3G-003, second half | LLR-039 | Strict evidence refuses at once (3) only a record that has no evidence and is not of the current form. A current-form record without evidence goes through the wait and the claim test like any mismatch. |
| P-15 | IF-015, LLR-038, LLR-118, LLR-039, LLR-123 | Evidence version 4 carries the folder record's and the link record's digests. Every temporary is written first, then the folder record, the link record, the record, and the evidence last, the commit point for all three. Roll-forward covers all three. A folder or link record of the latest state that cannot be rolled forward is replaced by the run's own publication, derived from the source. |
| P-16 | SR-082, SR-040, LLR-039, LLR-040, LLR-123, LLR-143, LLR-144 | A folder or link record still disagreeing after the wait, with the record of contents agreeing, is left unapplied. Every file is restored, the cause is named (damage, or a publication that may be in progress), and the outcome is part failed (1). |
| R3G-001 | LLR-088, LLR-150, IF-033, IF-044, LLR-017 | A prepared folder is recognised complete or not. Each of its files is written at its temporary and renamed into place, the evidence after the record copies. Whole record copies must be byte-identical, and whole evidence must be valid. LLR-017's dimensions gain `prepared-partial`. |
| R3G-002 | LLR-088, IF-044, LLR-017 | The owner record's deletion entry in an ownerless run folder holds no content. LLR-017's dimensions gain `owner-record-deletion`. |
| R3G-004 | IF-009, IF-044 | IF-009 keeps the names. The publication timing is LLR-161's. IF-044 keeps the request, the verdict variants (one line each) and the evidence payload; the mapping is LLR-017's and LLR-088's. |
| Kit before records | LLR-007, LLR-150 | The latest state's kit is placed before its records are published. |
| Roll-forward search | LLR-118, LLR-124 | An evidence temporary is looked for in every reclaimed-leftover folder of that root. |
| SR-144 | SR-144 | "change no file in the store that its successor wrote or published". |
| The staging table | LLR-162 (new, child of LLR-088, constrains IF-033) | Steps S01 to S26 of a backup and R1 to R5 of a reclaim, each with its leftover shape and its verdict, closed over the steps. Any unlisted shape is content (2). |

Interface versions: IF-015 3 to 4, IF-033 3 to 4, IF-044 3 to 4. IF-009 is
unchanged in form.

Build list: `r3-merged/design-gaps.md` gains M91 to M95.

**Rows in scope for the convergence check (22):** SR-039, SR-040, SR-082,
SR-110, SR-144; LLR-007, LLR-017, LLR-038, LLR-039, LLR-040, LLR-088, LLR-118,
LLR-123, LLR-124, LLR-143, LLR-144, LLR-150, LLR-162; IF-009, IF-015, IF-033,
IF-044.
