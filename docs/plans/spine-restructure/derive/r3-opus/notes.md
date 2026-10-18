# Round 3 notes (Opus derivation)

## What I read

- The brief, the target `pointer-rules.md` in full, and `spine-questions.md` sections 0 and 3 (ai-template, read only).
- `README.md` and `AGENTS.md` (sections 1 and 2 directly; the rest through a sub-agent's survey), `system-requirements.toml` (all 123 rows: requirement, acceptance and permutations), `external.toml`, `assumptions.toml`, `hats.toml`, `interfaces.csv` (IF-001), `low-level-requirements.csv` (all 83 rows), `strip/final/llr.json`, the LLR and IF pieces of `strip/final/sr.json` and `sn.json`, `r2-merged/merge-notes.md` ("Moved to the design tier" onward), the gap map's Appendix C, the handoff for round 3, and the parameter cells of `harvest/tc.json`.
- The code, through three read-only sub-agent surveys (backup engine and entry point; both restore routes and the launchers; the container, the configuration schema, the helper and the user manual), each answering fixed questions with line evidence, plus my own spot checks (the logger's line format, the base-57 alphabet, how relative paths are built, the refusal tokens, the run record's lines).
- Nothing under `docs/plans/spine-restructure/derive/` except this folder, and no OWNER_SCRATCHPAD.md. The handoff is outside `derive/` and I read it.

## Counts

| Item | Count |
|---|---|
| Components | 24 (one root, depth up to 3) |
| Interfaces | 43: 40 boundary, 3 internal (IF-030 run-state record, IF-043 content-location index, IF-044 leftover verdict) |
| LLRs | 128: 106 top-level, 22 child |
| Legacy LLR ids kept | 73 (of 83 rows in the CSV; 3 more were already retired at the strip) |
| New LLR ids | 55 (LLR-095 to LLR-149) |
| Legacy ids merged, moved or retired | 13: merged LLR-006, 030, 031, 032, 033, 057, 064, 072, 075; moved to IF LLR-070; retired (at the strip) LLR-034, 044, 089 |
| IF-001 | retired, split over IF-003, 004-006, 007, 010, 019, 021, 029, 038, 039 (mapping.md) |
| Design gaps | 50 (G-01 to G-50), plus 6 items of code beyond the design |
| SRs reaching no LLR | 0 (all 123 are in a top-level LLR's `sr_refs`) |
| Interfaces with no constraining LLR | 0; 10 SR-constrains pairs listed as supplementary |

## Validation

`_validate.py` in this folder. It checks: each TOML parses with `tomllib`; every `sr_refs`, `parent`, `constrains`, `part_of`, `owner`, `consumers`, `requestors`, `interface_*_external`, `bridged_by`, `carried_by` and `hat_refs` id resolves against this folder and `docs/requirements/`; exactly one of `consumers`/`requestors`; a boundary interface has `bridged_by` or `coincident` and an internal one has neither; `parent` and `part_of` are acyclic; no LLR has both `sr_refs` and `parent`, or neither; a hat on an LLR is not already carried by its (derived) parent SRs; an LLR with `constrains` has `dimensions`, and every dimensions term matches the grammar; no `module`, `code_symbol`, `component` key and no "shall"; every interface is constrained by an LLR or listed under "SR constrains"; every SR reaches an LLR or is listed in design-gaps section 3; no component, interface or LLR text names a code file (by extension), a Verb-Noun function or cmdlet, a `$variable`, a snake_case identifier or any token of the legacy `Module`/`CodeSymbol` cells; no rationale or detail carries a date, WP, OI, review or defect token; mapping.md has a line for every legacy row in the strip; no kept id is a retired one and no id below LLR-095 is a non-legacy id. It also warns (prose check, LLRs only) when an LLR carries an interface-form word (layout names, settings, switches, variables); there are none.

Two false-positive classes were whitelisted after reading them: the plain words "container" and "marker" (they appear in the legacy `Module`/`CodeSymbol` cells only as parts of a path and a phrase), and two names that are interface form in IF rows only: the retired launcher name in the layout (IF-013) and the kit-revision marker text and findings field (IF-019, IF-010).

Output of the final run (`python _validate.py`, exit 0):

```
PARSE OK  components.toml
PARSE OK  interfaces.toml
PARSE OK  low-level-requirements.toml

components: 24
interfaces: 43 (boundary 40, internal 3)
LLRs: 128 (top-level 106, child 22)
legacy LLR ids kept: 73
new LLR ids minted: 55
design gaps: 50
SRs reached by an LLR: 123/123
interfaces constrained by an LLR: 43/43
SR constrains pairs listed: 10


VALIDATION PASSED: 0 problems
```

The first run failed on 25 problems: three SRs (SR-102, SR-116, SR-131) reached only through child rows whose derived SR was their parent's, so I made those three rows top-level with their own `sr_refs`; one rationale said "defect"; the rest were the false positives above.

## Conventions I chose where the brief is silent

- **Lists for crossings.** `interface_from_external` / `interface_to_external` hold a list where one interface sits on two crossings (for example B-05 and B-07 for the launch request). The brief says "a B-NN crossing"; if the tooling wants a scalar, the second crossing moves to the rationale.
- **`carried_by` is a list** (IF-004 rides in both IF-005 and IF-006).
- **Root component** carries no `part_of`.
- **Form names in IF data.** Store-layout names, record columns, settings, switches and variables are written in `data` because they are the form both sides spell identically. The kit's own code files (the two restorers, the shared library, the hashing library) are named by role only; the two launchers are named, as the shipped boundary artifacts a restorer double-clicks. LLRs refer to all of these by role, so a rename touches only the interface row.
- **Children serve their parent's SR.** A row that serves a different SR from its would-be parent is top-level, even where it reads as a refinement (LLR-119, LLR-126, LLR-138).

## Calls I was unsure of

1. **LLR-035, the run-state record.** SR-035 speaks of the change-detection state. I read the run-state record (last completion and last full re-read) as part of the same working state and designed a rebuild from the evidence's written time instead of today's refusal; the legacy id is kept with that narrowed meaning (G-09). The alternative is to keep refusing (value 3 or 2) and say SR-035 does not cover it.
2. **LLR-121, one path separator on every host.** Records written from Linux today use '/', from Windows '\'. SR-033 and SR-136 need one form; I chose the backslash (unambiguous, since a backslash inside a name is refused off Windows, and the Windows-written stores need no change). Existing Linux-written stores (the container deployments) would then see one full rewrite of their latest record and one extra saved state on the first run after the change; this is a downstream migration to flag (G-46).
3. **Positive age evidence (LLR-138, IF-015 version 3, LLR-143).** SR-116 and SR-146 need a way to tell an older state from a damaged current one. I used the state's own kit revision for the completeness evidence, and new `DirRows`/`LinkRows` keys in a version-3 evidence file for the folder and link records (absence of a folder record is otherwise normal, so nothing could tell damage from "no empty folders"). This changes the evidence form; it relies on today's kits verifying a newer evidence version on the fields they know, with a warning, which keeps SR-084 true. The revision numbers that introduced each record kind still have to be read from the release history.
4. **LLR-049, the full check by default.** SR-049 asks the check to report altered content; today only an opt-in deep pass does. I made reading every distinct stored object once the check's default and dropped the deep switch from the request form. At the reference host (2 TiB at 200 MiB/s) that is about three hours of reading, inside SR-064's eight, but it is a large change in what a routine check costs an owner.
5. **IF-018 and LLR-109/110, links.** The link record is a new separate file (named LINKS.csv in IF-013) rather than rows in the record of contents, so kits already in a backup ignore it (SR-084); the classification includes "an ancestor of the link in the walk", which needs the walk to track resolved ancestors. Both the record's columns and its name are my design, not anything in the code.

Smaller calls worth a second look: the evidence-before-record write order (LLR-118) that lets the next run complete an interrupted publication; the writability access query of LLR-104 (no probe file, which would itself alter the source); keeping the refusal tokens as they are although they embed requirement ids (IF-009); the new SpaceView setting and SPACE.tsv (IF-004, IF-042), since SR-097 needs a switch and a listing and none exists; the THIRD-PARTY-NOTICES.txt name (IF-019, IF-040); leaving the removal dry run, the removal overrides and the strict-evidence restore out of (or, for the last, only in the form of) the design, listed under "code beyond the design"; and the HashRecalcFreq calendar meanings in IF-004, which follow today's code (calendar buckets in host-local time) rather than elapsed periods.
