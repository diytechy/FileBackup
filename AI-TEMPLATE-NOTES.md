# Notes for ai-template, from FileBackup

FileBackup (branch `DirectRebuild`) is running ai-template's ruled-but-unbuilt
design layer: components (`part_of`), interfaces owned by a component or an
`external:` party, LLRs placed through `constrains`, a parent-LLR link. That
makes it a live first user of review-churn items 11 and 12. These are the
gaps and lessons it hit, for transfer into ai-template's queue (P6, P8, and the
Phase 3 migration) when that repo is quiet. Each note says what happened, where
to look in FileBackup, and a suggestion.

Written 2026-10-18. FileBackup paths are relative to its repo root.

A companion file, `ARCHITECTURE-FINDINGS.md`, holds the results of the
unattended decomposition run: the procedure that worked, the lessons, the
model ambiguities and a prototype checker.

## 1. Adopters have no process text for the design layer

**What happened.** FileBackup's `docs/process.md` is the older kit version: it
knows SN → SR → LLR → TC and nothing of CMP or IF. The order of the design
work lived only in a downstream plan (`docs/plans/spine-restructure-gap-map.md`
Phase 3). The plan's closing tasks (runtime flows, re-anchoring the prose) were
skipped, and the handoff went straight from "design tier drafted" to "approve,
then test cases". The Owner caught it.

**Suggestion.** Item 12's `DevStg-Arch` outputs (state flow, boundary
interfaces with value domains, dependency table, descend test) need a home
an adopter actually reads: the planned `spine-questions.md` section, plus a
line in PROCESS.md §4 saying what must exist before the first test case. A
resync note should tell adopters already on the CSV process where the design
layer slots in.

## 2. Rows on an external interface always land at the root

**What happened.** Placement resolves an `external:` interface to the system
root. A component whose job is to consume an external interface therefore
gets nothing, however clearly the rows are its own. In FileBackup that emptied:
- source capture (its rows constrain the source tree view);
- restore admission (the target probe and the tool floor);
- the restore launchers (the host session and the folder dialog).

See `docs/plans/spine-restructure/derive/r3o-decomposition.md`, "Why six leaves
are empty".

**The Owner's principle (FileBackup, 2026-10-18).** Components describe the
system's own internal behaviour. An external system, such as the source tree
a backup reads, is an external interface, never a component, and shouldn't
clog the component registry. FileBackup therefore folded its source-capture
leaf into the internal component that acts on what it reads, and folded its
restore phases into the restore kit as states.

**Suggestion.** Write that principle into the kit (what a component is, and
that an external system is only ever an interface). Then decide and state one
rule for the rows themselves:
- an external interface with exactly one internal consumer places its rows at
  that consumer; or
- such a leaf is legal and shown as "external-facing, placed at root"; or
- such a leaf should be folded into its parent.

F-call 8's notes offer the test-case observed-at route as the second way to
place a row. It doesn't help here, because those tests also drive the
external interface.

## 3. No guidance for a leaf component that owns no interface

**What happened.** Six of FileBackup's 24 components owned no interface, so
nothing could ever be placed on them. No rule, check or rubric anchor says
whether that is a finding. The review-churn plan comes closest with "a
component drawn too coarse", which is the opposite case.

**Suggestion.** Add an advisory dashboard finding, "a leaf owns no interface:
nothing can be placed on it". Name the two remedies:
- draw the real boundary it has (an interface with a value domain); or
- fold it into its parent and keep it as a state in the runtime flow.

FileBackup's worked calls are in `r3o-decomposition.md`, Calls 1 to 4.

## 4. The dependency table has no home or format

**What happened.** Item 12 asks for "a small output × input dependency table"
per scope but doesn't say where it lives or what its columns are. FileBackup
put it in a plan record. The useful convention that emerged was to **name the
values that pass between children with no interface row** ("walked entries",
"change set", "content map") as columns. Those unnamed columns are exactly
where a missing boundary shows.

**Suggestion.** Give the table a home: a per-scope section in
`runtime-flows.md`, or a generated view from the registries plus authored
rows for unnamed values. State the convention that an unnamed passed value
is a column.

## 5. The runtime-flows template still says "planned modules"

**What happened.** `RUNTIME_FLOWS.template.md` and PROCESS.md tell authors to
use "the planned modules (the LLR `Module` column)" as participants. The
target model retires that column (item 5), and the design names components,
not files. FileBackup used components (`docs/runtime-flows.md`).

**Suggestion.** Change the template to "the components (`CMP-NNN`) the flow
crosses", and say whether a state flow (`stateDiagram-v2`) per scope
satisfies item 12's "state flow, as mode classes and transitions". As the
template describes it, `check_flows.py` checks that diagrams exist and cite
real ids, not which kind of diagram renders the states.

## 6. What is approved when, at the design layer

**What happened.** FileBackup's plan assumed one approval per tier, the design
tier included. The ruled target says `DevStg-Arch` has no approval act, and an
interface is approved through the sitting of the row it serves.

**Suggestion.** An adopter migrating from tier approvals needs one paragraph
saying what replaces "approve the design tier": which acts exist, what they
cover, and where a runtime flow and a dependency table are judged.

## 7. Test tags when one file verifies many test cases (P8)

**What happened.** FileBackup's Pester files verify up to 32 test cases each.
The older kit rule says one tag per file. The review-churn README (line 115)
says tags "may sit on a test function", and `history.md` calls granularity
"the lane's design call".

**Suggestion.** When P8 is filed, make the grammar allow per-function tags
explicitly, with one reader. FileBackup's round 4 (test cases) is waiting on
this.

## 8. The descend test separated phases from components, usefully

**What happened.** Applying F-call 6 point 1 ("a describable state earns LLRs
and a runtime flow; whether it becomes a component is a separate question")
showed that FileBackup's restore kit had been split by processing phase
(admission, entries, finishing, outcome, launch). Admission, finishing and
launch hide no decision of their own and became states, not components. The
backup engine's capture, change detection, writer and publication do each
hide a decision, so they stayed, with their boundaries drawn.

**Suggestion.** This is a good worked example for the planned
`architecture-decomposition` skill. Two cuts of one product came out
differently under the same test.

## 9. One interface, two information kinds, owned by a third component

**What happened.** FileBackup's findings document (IF-010) carried both the
check's findings and the saved-state report, and was owned by the launch
component, not by either producer. Two blind derivations, an alignment and
four review rounds didn't flag it. It surfaced only when asking why the check
component was empty.

**Suggestion.** A cheap advisory check: an interface whose constraining LLRs
are mostly placed on components other than its owner, or whose `data`
describes two document kinds, is a candidate for OI-67's split.

## 10. Rulings applied by the coordinator need their own scoped check

**What happened.** After the Owner ruled thirteen pending questions in one
session, a scoped convergence check found three BLOCKERs. All three were in
rows the coordinator had rewritten to apply those rulings: an SR and its LLR
stating different predicates, a rebuild rule that overrode a "never"
schedule, and a dry run claiming it couldn't see a lock the design already
lets readers test. The earlier design rows came back clean.

**Suggestion.** In the process text, name "rows changed to apply rulings" as
a scope that always gets a convergence check before approval, even when the
rulings themselves are behaviour choices nobody disputes.

## 11. Desk research on established practice (the ranked fix list)

**What happened.** At the Owner's request, a research pass checked the design
layer against established systems-engineering practice: NASA SE Handbook and
NPR 7123.1, DAU, SEBoK, Parnas's A-7E module guide, RUP-SE, OOSEM, Arcadia,
ATAM, ISO 42010 via secondary sources, C4. Report:
`docs/plans/spine-restructure/architecture-breakdown-research.md`. The key
quotes from NASA Appendix L and §6.3 and from Parnas, Clements and Weiss
(1985) were spot-checked against the primary texts. The structure matches
practice. The holes are in **allocation** and **checking**.

**Its ranked recommendations, in short** (full text and sources in the
report):
1. Place external-interface rows at the local endpoint, the component on
   our side of the interface plane (NASA Appendix L; Parnas's device
   interface modules). This resolves note 2.
2. Check runtime flows against placement: a lifeline that cites an LLR
   versus where it is placed (42010 correspondence rules, RUP-SE).
3. Flag an empty leaf (DAU: every component meets at least one requirement).
   This is note 3.
4. Give unplaced rows an allocation kind: sole, derived per component,
   budgeted, or system-level with a reason (RUP-SE, DAU, SEBoK).
5. State the order: scenarios before child components (SEBoK pitfall).
6. Make the dependency table a per-scope N2 chart, generated. This is note 4.
7. Write "architecture ready for test cases" entry criteria (NASA SDR/PDR).
   This is notes 1 and 6.
8. Add ATAM-lite quality-attribute scenarios at the depth-0 critique.
9. Require a decision record per decomposition call (NASA, Nygard).
10. Add a designer-side stopping rule: one work assignment, one secret, and
    siblings argued non-overlapping and covering (Parnas goal g).
