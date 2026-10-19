# Architecture and decomposition findings, for ai-template

FileBackup's `DirectRebuild` branch tested one question: **can an unattended
session decompose a system into components and interfaces, given context rules
about architecture and decomposition?** This file records what that showed, for
transfer into ai-template (the planned `architecture-decomposition` skill and
rubric, review-churn items 11 and 12, the P6 work item). It complements
`AI-TEMPLATE-NOTES.md` (process and kit gaps) and
`docs/plans/spine-restructure/architecture-breakdown-research.md` (what
established practice says).

Written 2026-10-18. Paths are relative to the FileBackup repo root.

## The short answer

**Yes, with a procedure and a checker; no, with rules alone.** The rules in
force (ai-template's pointer rules, the descend test, "a state is not yet a
component") were sound. But an agent applying them from prose drew components
by processing phase, put steps on the wrong component, and declared the design
done when it wasn't. What turned the result around was an ordered procedure,
generated views (N2 charts) and a correspondence checker run after every pass,
plus an independent reviewer per pass. The procedure below is what finally
worked.

## The procedure that worked (proposed for the skill)

At each component scope, in this order:

1. **Draw the states first:** one state flow (modes and transitions) and the
   key sequence flows, before naming any child component. Phases, modes and
   steps belong to the behaviour view. *Without this, the restore kit was first
   split into five phase-components that each read nearly every input.*
2. **Name each candidate child's secret:** the one decision it hides, in a
   sentence. A child with no secret of its own is a state, not a component.
3. **Generate the N2 chart** from the interface rows, plus the values the flows
   show passing between children. Any filled cell with no interface row is an
   *unnamed value*.
4. **Settle every unnamed value:** name it as an interface (one information
   kind, one direction, owned by its producer), or fold the two components into
   one. Record which, and why.
   - **4b. Check each form against its readers:** for every interface, read
     the LLRs of each component that consumes it, and check that the form
     carries every value they use. The N2 chart can't do this, because it only
     sees declared values (lesson 8).
5. **Make the sibling argument** (Parnas, Clements and Weiss 1985, goal g):
   siblings don't overlap, and together they cover the parent. Record the
   candidates you considered splitting or merging, even when you keep them.
6. **Apply the descend test to each leaf.** Stop where no leaf hides a
   describable decision another component doesn't own.
7. **Treat external systems as interfaces, never components.** (FileBackup
   Owner ruling. It matches C4, OOSEM and NASA practice.) The internal
   component that *faces* an external system is a normal component (Parnas's
   device interface module).
8. **Complete consumer and requestor lists from the flows:** every message
   between two components must have an interface whose owner and consumer are
   those two (or their ancestors).
9. **Run the correspondence checker** (below). Fix everything the design owns.
   Record the rest as residue with its cause.
10. **Send the pass to an independent reviewer,** scoped to what changed, and
    fix what's confirmed, *including defects in the previous fixes* (see
    lesson 6).
11. **Record each call for the owner:** what was decided, the alternative, and
    why, with "flipping it is a row edit".

## Lessons: what an unattended agent got wrong, and the rule that prevents it

1. **It skipped the architecture step.** It went from "design drafted" to
   "approve, then test cases", because no process text said what had to exist
   first.
   - *Rule:* written entry criteria for test cases. The eight-item list in the
     research report §6 worked well as a gate.
2. **It drew components by processing phase.** The restore kit's admission,
   entries, finishing, outcome and launch became five components.
   - *Rule:* procedure steps 1 and 2. A phase is a state until it has a secret.
3. **It drew flow steps on the wrong component.** The lock-holding component
   was shown reading run state and opening logs for others, and the launcher
   was shown taking the lock for every operation.
   - *Rule:* checker 3 (lifeline against placement), plus the convention in
     lesson 7.
4. **It read a placement artifact as design evidence.** Leaves looked empty
   because their rows constrained *external* interfaces, which place at the
   root. The owner's fold calls were partly judged on that misleading signal.
   - *Rule:* place external-interface rows at the local endpoint (research
     rec. 1), or at least report "empty because external" apart from "empty".
5. **It missed incomplete consumer lists and two-kind interfaces.** One
   interface carried two document kinds and was owned by a third component.
   Four review rounds didn't flag it.
   - *Rule:* procedure step 8, and an N2 cell check: owner equals producer, one
     kind per cell.
6. **Its fixes introduced defects.** A fix written to satisfy one reviewer
   introduced the next reviewer's finding (FileBackup R3M-003 → R3Q-003). In
   another round, rows rewritten to apply the owner's rulings held all three
   BLOCKERs of the following check, while the untouched rows were clean.
   - *Rule:* every pass's changed rows, including rows changed to apply
     rulings, get a scoped check before approval.
7. **Flow messages were ambiguous.** It was unclear whether a message is a
   request (the receiver works) or a handoff (the sender produced the data).
   - *Convention that made the checker work:* a message between two components
     cites the **interface** it travels on; a self-message cites the **LLR**
     being performed. A checker can then credit work correctly.

8. **The generated N2 chart can't see what the interfaces leave out.** It is
   built from the interface rows, so it only shows values someone already
   declared. The round-3u reviewer found the values a component's *LLRs need*
   but no interface carries: a location's wait budget shared between the scan
   and storage, a full re-read's start time needed by the run-state publisher,
   a recovery's source folder needed by the report. It found 11 of these,
   against 0 left by the checker.
   - *Rule:* procedure step 4b: for every interface, read each consuming
     component's LLRs and check that the form carries every value they use.
     This is the one check here that only reading can do.
9. **Planning across scopes is easy to lose.** A rule summing space demand
   across *all* locations before any runs (FileBackup LLR-052) was drawn
   per location in the flows, so it could never refuse early.
   - *Rule:* when an LLR quantifies over siblings ("every configured
     location"), the flows must show a phase at the parent that sees them all.
10. **Interface count grows fast once every crossing must be named.** The
    tree went from 4 internal interfaces to 11 in one pass.
    - *Open question for the kit:* when is a passed value an interface, and
      when is it a parameter of an existing one? FileBackup folded
      parameters into existing forms where the information kind matched
      (the plan request into IF-048) and minted new rows only for new kinds.

## Ambiguities in the ruled model that this run hit

- **May a parent component do work of its own?** FileBackup's owner folded the
  restore kit's phases into the parent as *states*, keeping two child
  components. A reviewer applying Parnas's coverage rule argued that all of a
  parent's work must lie in its children. Both readings are defensible. The
  kit should say whether a parent may hold states (and own interfaces to its
  children), or must be pure composition.

- **"Interfaces at every boundary, optional inside a component."** Is the edge
  between two *siblings* a boundary, or "inside" their parent? FileBackup
  treated it as a boundary (procedure step 4). The kit should say so.
- **`consumers` versus `requestors`, and the rule that a row may not carry
  both.** The run record's readers are external consumers, while its writers
  are internal requestors. The rule forced a second interface (IF-052) for the
  writing side. Either bless that pattern or allow both cells.
- **A parent's own states.** When phases fold into a parent (the restore kit),
  a message between the parent and its child needs no interface. The checker
  had to exempt parent-child pairs; the kit should state it.
- **Shared definitions.** One component owns the store format, and every writer
  and reader uses it. Rows describing how writers *use* the format place at the
  format's owner, not at the writer (group C residue). This is research rec. 2
  (place by performer) from the other side.
- **Where the dependency table lives.** Item 12 asks for it but gives it no
  home. FileBackup generates N2 charts into the decomposition record, from the
  registries.

## A prototype checker

`docs/plans/spine-restructure/check_design_layer.py` (stdlib, advisory, about
200 lines) implements checks the research recommends:
- leaf components with nothing placed (rec. 3);
- interface consistency: no consumer, an external interface with no local
  endpoint, or no constraining row;
- flows against the registries: messages between components with no
  interface, and each LLR cited on a lifeline against its placement, grouped by
  cause A, B or C (rec. 2);
- every SR in a flow or declared flow-free (entry criterion 4);
- every cited id exists;
- `--n2`, which generates an N2 chart at each decomposed scope (rec. 6).

It takes the repo root and reads only `docs/requirements/*.toml` and
`docs/runtime-flows.md`, so it should port to the kit with path changes.

## Numbers, for calibration

- **Starting point:** a design tier of 24 components, 45 interfaces and 140
  LLRs, drafted by two blind derivations, an alignment and four review rounds.
- **Six leaves** were empty. **Three** of the 24 components were later found to
  be states, not components.
- **The decomposition pass and its follow-ups** produced the final tree of 19
  components, 53 interfaces (11 internal) and 142 LLRs.
- **Scoped checks** after each pass found:
  - 3 BLOCKERs, in rows rewritten to apply rulings;
  - 3 MAJOR and 1 MINOR, from the restructuring and the new flows;
  - 11 MAJOR and 3 MINOR in the top-level pass, mostly forms missing what
    consuming LLRs need (lesson 8);
  - a final check of those fixes found 1 MAJOR, again a form missing
    something its readers need (a 'permitted, not made' disposition):
    lesson 8 once more.
- **Tool note:** a Codex reviewer run once failed before reading anything (a
  sandbox start-up error). The process rule "retry once, then substitute the
  other family" handled it; the retry succeeded. Always check a reviewer's log
  for evidence it read the files before trusting "no findings".
- **The correspondence checker** ended with 0 design-owned findings and 55
  placement disagreements due to the kit's placement rule.
