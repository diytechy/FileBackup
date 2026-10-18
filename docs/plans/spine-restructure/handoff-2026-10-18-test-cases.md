# Handoff 2026-10-18 (b): FileBackup spine restructure, design tier done, into round 4

*Branch `DirectRebuild`. Nothing is pushed, merged or approved. ai-template is
untouched by this work. Round 3 ran unattended (the Owner was not present),
under the rules in [handoff-2026-10-18-design-tier.md](handoff-2026-10-18-design-tier.md),
"Round 3 runs unattended". That handoff's method, roles and "Owner rulings in
force" still apply. This one replaces its "Where it stands" and "Open items".*

## Where it stands

| Tier | File | Rows | State |
|---|---|---|---|
| Vision | `README.md` (`PROJECT-VISION`) | — | Owner's wording |
| Stakeholders + needs | `docs/requirements/stakeholder-needs.toml` | 3 STK, 48 SN | Drafted; **not edited in round 3** |
| Frame | `external.toml`, `assumptions.toml` | as before | Drafted. B-01 and B-16 now carry links (a clarity edit) |
| Hats | `hats.toml` | 9 | unchanged |
| System requirements | `system-requirements.toml` | 123 SR | Drafted. 11 rows edited in round 3 (open item 1's set, plus SR-106, SR-144, SR-146) |
| **Components** | `components.toml` | 24 CMP | **Drafted, new** |
| **Interfaces** | `interfaces.toml` | 45 IF (41 boundary, 4 internal) | **Drafted, new**; IF-001 retired |
| **Low-level requirements** | `low-level-requirements.toml` | 140 LLR (110 top-level, 30 child; 73 legacy ids kept) | **Drafted, new**; LLR-162 (the staging table) added 2026-10-18 c |
| Test cases | `docs/test/test-cases.csv` (legacy) | 234 | **next: round 4** |

The legacy `low-level-requirements.csv` and `interfaces.csv` are removed. The
legacy LLRs are in `harvest/llr.json`, and IF-001 and its siblings are in
`harvest/interfaces-legacy.csv`. Every SR reaches an LLR, and every interface
is constrained by an LLR or an SR. The structural check (`derive/r3-merged/`
plus the validator described below) gives 0 errors.

## Round 3, what happened

All records are under `docs/plans/spine-restructure/derive/`.

| Step | Record |
|---|---|
| Two blind derivations: Astra 16 CMP / 40 IF / 85 LLR; Opus 24 / 43 / 128 | `r3-astra/`, `r3-opus/` |
| Alignment: 38 conflicts (K01–K38) | `r3-alignment.md`, `r3-alignment-map.json` |
| Coordinator calls, every disposition, every pending ruling | **`r3-dispositions.md`** (read this first) |
| Merged tier, gap list (90 build items), legacy mapping, placement table | `r3-merged/` (`design-gaps.md`, `mapping.md`, `merge-notes.md`) |
| Full round 1: Sol (high) 9/17/3 and Opus 3/21/26; 78 confirmed, 1 refuted | `r3-review-sol/`, `r3-review-opus/`, `r3b-change-log.md` |
| Full round 2: convergence check 1, 2 BLOCKER and 6 MAJOR | `r3c-convergence-sol/`, `r3d-change-log.md` |
| Full round 3: convergence check 2, 1 BLOCKER and 5 MAJOR | `r3e-convergence-sol/`, `r3f-change-log.md` |
| Final check: 1 BLOCKER, 2 MAJOR, 1 MINOR, **recorded, not fixed** | `r3g-convergence-sol/` |

There were no model substitutions: every route ran on its assigned family.
One prompt defect: in the first Sol review, the output-path placeholder
rendered empty. Sol wrote into its working folder, which was the right place.

The design moved most in two places: the fence and the staging sequence.
- **The fence.** Every store mutation is now a rename through a run-unique
  staging folder (`Run-<RunId>`) that a successor's reclaim moves aside, so a
  resumed former owner's renames fail by themselves (R3C-002).
- **The staging sequence.** Each round found another kill point whose
  leftovers had no recognised shape (R3C-005, R3E-002, R3G-001, R3G-002).
  Open item 1 closes that class at once.

## Open items, in order

1. **DONE (session 2026-10-18 c, the Owner present): the design tier's last
   findings.** Records: `r3-dispositions.md` ("Closing the design tier" and
   "Convergence check of the closing fixes") and `r3h-change-log.md`.
   - P-14 (c) was **not** taken: only a backup writes an owner record, so a
     live kit refresh or repair would have read as damage. The Owner ruled
     (a). The Owner also ruled P-15 (evidence version 4 binds the folder and
     link records by digest, the evidence renamed last) and P-16 (a folder or
     link record still disagreeing after the wait: restore the files, leave
     it unapplied, part failed 1). P-15 was a new hole, found while
     enumerating the staging sequence.
   - LLR-162 (a child of LLR-088) is the staging table: S01..S27 for a backup
     and R1..R6 for a reclaim, each with its leftover shape and verdict.
     R3G-001, R3G-002, R3G-004 and SR-144 are fixed. The build list gains
     M91..M95.
   - The scoped convergence check (`r3i-convergence-sol/`) found 1 BLOCKER and
     2 MAJOR, all confirmed and fixed (round 3j). **Those fixes are not
     re-checked.** One more scoped check of LLR-162, LLR-118, LLR-123,
     LLR-124, SR-082 and SR-106 is the Owner's call.
2. **The Owner's pending rulings** below. Each is written to its default;
   flipping one is a row edit.
3. **Owner approval of the need tier, then the SR tier, then the design
   tier.** Each is a reviewed Status-change commit, and only the Owner signs.
4. **Round 4, the test cases.** Regenerate them from the new LLRs; do not edit
   the legacy rows. Use `harvest/tc.json` for the old cases' input sets and
   edges, keep old TC ids where a case maps one to one, and retire the 9
   overlap clusters (gap map Appendix D). Every LLR that constrains an
   interface has a `dimensions` cell, which is the input space the cases
   come from. Check the declared allowance values (K09) against the
   harvested edges. The staging kill-point table (item 1) becomes cases
   directly. **This needs an ai-template ruling first:** the test-tagging
   form, since FileBackup files verify up to 32 TCs each and the kit rule
   says one tag per file. Run it as before: a brief, two blind derivations,
   alignment, a builder, two reviews, dispositions, convergence.
5. **Then the code:** `r3-merged/design-gaps.md` (90 items) is the build
   list, plus the `Component:`, `Implements:` and `Contract IF-NNN:` headers,
   then the tooling or a kit resync. Downstream-visible build changes flagged
   in round 3:
   - the change-detection record's new name (P-08);
   - the path separator (P-06);
   - kit revision 14, with a revision line in every kit file;
   - IF-010 version 2;
   - the per-run location record;
   - superseded content copied, not renamed (P-13).

## Pending Owner rulings

All of them are written to the default. The full rows, with options and the
rows affected, are in `r3-dispositions.md`.

| # | Question | Default written |
|---|---|---|
| P-01 | Does a version-2 configuration's D/W/M/Y schedule mean elapsed periods (SR-011) or calendar buckets (today's code)? | Elapsed periods, still version 2 |
| P-02 | Keep or retire the removal dry run (no need asks for it)? | Kept working, with no LLR, until ruled |
| P-03 | The check reads every stored object by default (about 3 h at the reference host). Accept? | Accept |
| P-04 | A volume whose free space cannot be measured: refuse, or proceed and record? | Proceed and record |
| P-05 | Does "re-derive and report" also cover a missing run-state record? | Yes, rebuild and report |
| P-06 | The record's path separator becomes the backslash on every host (Linux stores change form at their next real change, with no spurious saved state). Accept? | Accept |
| P-07 | Does SR-072's macOS double-click cover a kit carried in a zip? | No: supported from the backup's own volume; the manual gives the remedy |
| P-08 | The change-detection record shares its name with a backup's own record. Rename it? | Rename it (`FILEBACKUP-CHANGES.csv`), reading the old name once |
| P-09 | SR-144's "changes nothing further" cannot be absolute. Scope it to the store, with the change-detection state and views outside the guarantee? | Scope it to the store (the requirement text still needs "in the store", item 1) |
| P-10 | SR-106's "normal outcome during a writer": exceptions for the very state being removed, a kit refresh outlasting the wait, and a record pair that does not settle within 60 s? | Those cases end with 4, never wrong |
| P-11 | Add the listing location (the views) to the system's own locations for links? | Add it |
| P-12 | A pre-row-count state missing its folder record: complete (unverified) or part failed? | Complete, with the folder record reported unverified |
| P-13 | Superseded content is copied into the saved state, then the original is deleted, so every move is fenced; a large edited file then pays a full copy. Accept? | Accept |
| P-14 | Where the claim cannot be tested (macOS shell route), an unsettled record or mixed kit: 4, a lock tool, or the owner record as the no-writer signal? | **Ruled (a)** by the Owner, 2026-10-18: 4, the message stating that the record is damaged unless a changing operation is running |
| P-15 | Bind the folder and link records to the evidence by digest? | **Ruled**: evidence version 4 |
| P-16 | A folder or link record alone still disagreeing after the wait? | **Ruled**: restore the files, leave it unapplied, part failed (1) |

## Traps learned this round

- **The structural validator** for this tier is
  `docs/plans/spine-restructure/validate_design.py <dir>`. It checks parsing,
  id resolution, parent acyclicity, coverage and code-like tokens. Run it on
  `derive/r3-merged/`, where `design-gaps.md` sits beside the TOML (mirror
  `docs/requirements/` into it first); run on `docs/requirements/` it
  reports the SR-constrains pairs as errors.
- **Prompt templates with placeholders:** sed mangles Windows backslashes.
  Substitute in Python, and grep the rendered prompt in the run log before
  trusting it.
- **A shell heredoc that holds a markdown table with backticks and pipes**
  failed to parse once. Append long text with the editor instead.
- **The convergence checks kept finding new kill points** in the staging
  sequence. A design built around crash windows needs an enumerated table of
  steps, not prose. Ask for the table up front.
- **A builder told "don't mint interfaces to place rows"** drops `constrains`
  cells, so rows show as unplaced (63 of 139). That is allowed, but expect
  the dashboard's component view to be sparse until the code headers exist.
- **Only a backup writes an owner record** (LLR-080). A repair and a kit
  refresh hold only the operating-system claim (LLR-094), and a removal leaves
  its marker. Any "no writer" inference from the owner record alone is wrong
  for those operations. Check which operations produce a signal before
  relying on it.
- **An enumerated table finds what prose hides.** Writing the staging table
  surfaced a hole no review round had named: the folder and link records were
  published apart from the record and evidence, bound by count only (P-15).
  The table's own convergence check then found the version-3-to-4 transition
  and the reclaim rollback missing. Expect a table to need one more pass.
