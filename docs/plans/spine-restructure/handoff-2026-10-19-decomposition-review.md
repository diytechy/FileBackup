# Handoff 2026-10-19: FileBackup spine restructure, decomposition done, awaiting the Owner's review

*Branch `DirectRebuild`. Nothing is pushed, merged or approved. ai-template is
untouched; findings for it wait in two root files. This handoff replaces
[handoff-2026-10-18-test-cases.md](handoff-2026-10-18-test-cases.md) as the
resume point. That file's method, roles, and "Traps learned" section still
apply, and its round-3 history is still the record for what came before.*

The session of 2026-10-18 (two parts: **d** with the Owner present, **e**
unattended at the Owner's request) did three things:
1. **Ruled every pending question** (P-01..P-13), one at a time with the
   Owner.
2. **Found the planned order was wrong.** Test cases were not next. It then
   finished the design layer: runtime flows, a decomposition pass at every
   scope, an architecture-research pass, and a readiness check.
3. **Finished the component decomposition unattended,** with every call
   recorded for the Owner.

## Start here, in order

1. **The Owner reviews [`DECOMPOSITION-REVIEW.md`](../../../DECOMPOSITION-REVIEW.md)**
   (repo root). It lists every call made unattended, most consequential
   first; flipping one is a row edit. Call 0, the restore kit doing work of
   its own (review finding R3U-010 not taken), is the one most likely to need
   the Owner's input.
2. **The Owner answers the three questions** at the end of
   [`derive/r3s-quality-scenarios.md`](derive/r3s-quality-scenarios.md):
   - is the scenario list complete;
   - should a network-share backup root trigger a warning (a possible new
     requirement);
   - are the stale time (1800 s) and the settle wait (60 s) right for the
     HomeHub host.
3. **Re-anchor the prose** (the gap map's Phase 3 tail, never done):
   `docs/architecture.md`, `docs/interfaces.md`, AGENTS.md §2 and §3.
   - **Decide first:** ai-template's ruled target retires a hand-written
     `architecture.md`, replacing it with a generated view plus
     `runtime-flows.md`. FileBackup's gap map keeps a slim one holding the
     runtime flow and the reason for the restore-safe split. The flows now
     live in `docs/runtime-flows.md`.
   - About 90% of AGENTS.md §3 restates SRs. Its genuine invariants become
     LLRs (gap map Appendix C).
4. **The Owner approves** the need tier, then the SR tier, then the design
   tier. Each is a reviewed Status-change commit, and only the Owner signs.
   (ai-template's target has no approval act for the architecture step itself;
   see `AI-TEMPLATE-NOTES.md` note 6.)
5. **Round 4, the test cases.** Its inputs are ready:
   - the verification approach per external interface, with the Owner's calls
     ([`derive/r3s-verification-approach.md`](derive/r3s-verification-approach.md));
   - the staging table (LLR-162), which becomes cases directly;
   - `harvest/tc.json`, for the old cases' input sets and edges;
   - placement through each case's observed interface, which also places most
     of the unplaced rows.

   The tagging form still wants an ai-template ruling (P8 there, not yet
   filed). The review-churn README says tags may sit on a test function, which
   fits FileBackup's files that verify up to 32 TCs each.
6. **Then the code.** The build list is
   [`derive/r3-merged/design-gaps.md`](derive/r3-merged/design-gaps.md),
   M01..M97. Add the item-8 CI work (below), the `Component:`,
   `Implements:` and `Contract IF-NNN:` headers, and the tooling or a kit
   resync.

## Where it stands

| Tier | File | Rows | State |
|---|---|---|---|
| Needs | `docs/requirements/stakeholder-needs.toml` | 3 STK, 48 SN | Drafted. SN-046 widened (P-02) |
| System requirements | `system-requirements.toml` | 124 SR | Drafted. SR-153 added (P-02); SR-011, 049, 052, 072, 144 rewritten to rulings |
| Components | `components.toml` | 19 CMP | Drafted. 5 leaves folded (Calls 1, 2, 4) |
| Interfaces | `interfaces.toml` | 53 IF (42 boundary, 11 internal) | Drafted. IF-047 split from IF-010; IF-048..054 internal, added in rounds 3t and 3v |
| Low-level requirements | `low-level-requirements.toml` | 142 LLR (111 top, 31 child) | Drafted. LLR-163 (P-02) and LLR-164 (round 3t) added |
| Runtime flows | `docs/runtime-flows.md` | 10 flows (0 to 9), 3 state flows | New. The SRs no flow renders are declared flow-free at the end |
| Test cases | `docs/test/test-cases.csv` | legacy | Round 4 |

**Checks at the last commit:**
- `validate_design.py`: 0 errors.
- `check_design_layer.py`: 0 design-owned findings. It reports 55 placement
  disagreements, which come from ai-template's placement rule, not this
  design (groups A, B and C below).

## Owner rulings made in this session

| Ruling | Decision | Rows |
|---|---|---|
| P-01 | Re-read schedule: calendar periods, as today's code (option (c), added in session) | SR-011, LLR-011 |
| P-02 | Removal dry run specified; it tests the claim the way a reader does | SN-046, SR-153, LLR-163 |
| P-03 | The plain check stays quick (opening bytes); `-Deep` proves content | SR-049, LLR-049, IF-010 |
| P-04 | UNC shares are measured; a backup volume still unmeasurable is refused (2); restore unchanged | SR-052, LLR-052, gap M96 |
| P-05 | A missing run-state record is rebuilt from intact evidence and reported | LLR-035 |
| P-06 | Backslash separator on every host, accepted | LLR-121 |
| P-07 | macOS double-click from the backup's own volume only, plus a kit readme `RECONSTRUCT-README.txt` | SR-072, LLR-074, IF-019 |
| P-08 | The source-side record is renamed `MANIFEST.fb.src.csv`; the backup's `MANIFEST.csv` keeps its name | IF-029 |
| P-09 | A reclaimed run's guarantee is scoped to the store | SR-144 |
| P-10 | A restore that can't settle ends retry later (4), never wrong | SR-106, LLR-123 |
| P-11 | The views folder is a system location (a link into it is recorded, not followed) | SR-151, LLR-109 |
| P-12 | An old state without a folder record restores complete, reported unverified | LLR-138 |
| P-13 | Superseded content is renamed into the saved state on one volume; two hosts or containers writing one backup is **unsupported** | LLR-150, LLR-161, LLR-162, LLR-125, SR-144, DA-03 |
| Call 1 | Source capture folded into change detection (CMP-009) | components |
| Call 2 | Content writer folded into publication (CMP-011) | components |
| Call 3 | IF-010 split: check findings (CMP-014) and saved-state report (IF-047, CMP-013) | interfaces |
| Call 4 | Restore admission, finishing and launch folded into the restore kit as states | components |
| Item 8 | A real `\\localhost\` share in CI; a Linux Pester lane; a macOS restore attest per release; an exFAT target on the VHDX lane; real mail as attest only | r3s-verification-approach.md |

**Principles the Owner stated (apply them going forward):**
- **Components describe FileBackup's own internal behaviour.** An external
  system (the source, the restore target, the desktop session) is an external
  interface, never a component. It doesn't clog the component registry.
- **Backups of one store run in series from one host.** Concurrent writers
  are unsupported. They are detected and reported, and SR-144 bounds the
  damage.

## Session log (records under `derive/` unless noted)

| Round | What | Record |
|---|---|---|
| 3m | Scoped Sol check of the round-3l fixes and the rows rewritten to rulings: 3 BLOCKER | `r3m-convergence-sol/` |
| 3n | Fixes: SR-011 vs LLR-011, LLR-035 under a never schedule, the dry run's claim test | `r3-merged/_r3n_apply.py` |
| 3o | Runtime flows written; a decomposition pass on the backup engine and restore kit; Calls 1-4 posed | `r3o-decomposition.md`, `docs/runtime-flows.md` |
| 3p | Calls 1-4 applied | `r3-merged/_r3p_apply.py` |
| 3q, 3r | Sol double-check (3 MAJOR, 1 MINOR) and fixes | `r3q-convergence-sol/`, `r3-merged/_r3r_apply.py` |
| research | Architecture-breakdown desk research (NASA, DAU, SEBoK, Parnas, ATAM, 42010); key quotes spot-checked | `../architecture-breakdown-research.md` |
| 3s | The eight-item "ready for test cases" check; quality scenarios (item 6) and verification approach (item 8) drafted | `r3s-readiness-check.md`, `r3s-quality-scenarios.md`, `r3s-verification-approach.md` |
| 3t | Unattended top-level pass: flow 0, N2 charts, sibling argument, descend test; IF-048..052, LLR-164; checker | `r3t-root-decomposition.md`, `../check_design_layer.py` |
| 3u, 3v | Sol check (11 MAJOR, 3 MINOR); 13 fixed, R3U-010 not taken | `r3u-convergence-sol/`, `r3-merged/_r3v_apply.py` |
| 3w, 3x | Final scoped check (attempt 1 failed in Codex's sandbox; the retry found 1 MAJOR) and fix | `r3w-convergence-sol/`, `r3-merged/_r3x_apply.py` |

All dispositions are also summarised at the end of `r3-dispositions.md`.

## Outside this branch, worth the Owner's attention

- **A live defect, M96: every backup to a UNC path skips its free-space
  check today.** `Get-FreeSpaceBytes` returns nothing for `\\server\share`;
  this was confirmed on this machine. It's a small, self-contained fix,
  suitable for its own branch off `New_Fix_Batch` without waiting for this
  branch.
- **Possible clarification, not applied:** restores use the non-creating claim
  test (LLR-159), which reads an unreachable claim file as "cannot test" and
  ends with 4. A restore from a copy of just the backup root has no claim file
  at all. Mirroring LLR-163's "an absent claim file means no holder" would fix
  it in one line. It was outside every scoped review, so it's left for the
  Owner.
- **Still unmerged, from before this branch:** `fix-m1-single-probe-pass`
  (see the status banner).

## Tools and how to run them

- **The structural validator:** copy `docs/requirements/*.toml` and
  `derive/r3-merged/design-gaps.md` into a scratch folder, then run
  `py -3.12 docs/plans/spine-restructure/validate_design.py <scratch> .`.
  - Use a scratch folder, not `r3-merged/`: those tracked copies are the
    round-3 merge record and already differ from the live files.
  - Run on `docs/requirements/` directly, it reports the SR-constrains pairs
    as errors.
- **The design-layer checker:** `py -3.12 -X utf8 docs/plans/spine-restructure/check_design_layer.py . --n2`.
  It is advisory. It reports empty leaves, interface consistency, flow
  messages with no interface, each lifeline's citations against placement
  (groups A, B and C), SR coverage, citations, and an N2 chart per scope.
- **An independent review:**
  ```
  codex exec -m gpt-6.1-sol -c 'model_reasoning_effort="high"' -s workspace-write -C <out> -o <out>/last-message.md "$(cat <out>/prompt.txt)" < /dev/null > <out>/run.log
  ```
  - Run it in the background.
  - `derive/r3w-convergence-sol/prompt.txt` is the current prompt template:
    a scope, a convergence stance, deliberate decisions marked as not
    findings, and the judging rules.
  - Grep the run log for the rendered scope line before trusting a run, and
    check it actually read the rows.

## Traps learned in this session

- **Python:** plain `python` is 3.8, which has no `tomllib`; use
  `py -3.12`. `-I` ignores environment variables such as `PYTHONUTF8`, and
  the Windows console is cp1252, so a script printing `—` or `■` crashes or
  writes mojibake. Use `py -3.12 -X utf8`.
- **The validator rejects an interface row carrying both `consumers` and
  `requestors`.** Internal writers to an externally read interface need their
  own row (that's how IF-052 came about).
- **Codex can fail before reading anything:** `helper_unknown_error: setup
  refresh had errors`. It reports "could not run", not "no findings". Retry
  once, then substitute the other family and record it.
- **Bash heredocs holding Python with quotes or markdown tables break.**
  Write the script to the scratchpad and run it. Keep one `_r3X_apply.py` per
  round as the record.
- **Flow-message convention:** a message between two components cites the
  **interface** it travels on; a self-message cites the **LLR** performed. The
  checker credits work by that convention.
- **An unnamed value hides from the N2 chart.** The chart only sees declared
  interfaces. The values a consuming component's LLRs need (budgets,
  timestamps, a recovery folder) are found only by reading those LLRs against
  each form (`ARCHITECTURE-FINDINGS.md` lesson 8).
- **Fixes introduce defects.** Every round's changed rows, including rows
  changed to apply rulings, need a scoped check. Two of this session's checks
  each found defects in the previous round's fixes.

## For ai-template (transfer when that repo is quiet)

- [`ARCHITECTURE-FINDINGS.md`](../../../ARCHITECTURE-FINDINGS.md) (repo root):
  the result of the unattended decomposition run.
  - The 11-step procedure that worked.
  - Ten lessons, each with the rule that prevents it.
  - Ambiguities in the ruled model: siblings as boundaries; consumers versus
    requestors; whether a parent may hold states; shared definitions; where the
    dependency table lives.
  - The prototype checker.
- [`AI-TEMPLATE-NOTES.md`](../../../AI-TEMPLATE-NOTES.md) (repo root): eleven
  process and kit notes, ending with the research's ten ranked
  recommendations.
- [`architecture-breakdown-research.md`](architecture-breakdown-research.md):
  the sourced research behind them.
