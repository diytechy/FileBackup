---
name: architecture-decomposition
description: Use when breaking a system, or one component scope, into components and interfaces before writing its LLRs; when judging, revising or re-checking a component tree; or when a session must decompose unattended. Gives the ordered procedure, the rules for external systems, interfaces and runtime flows, the "ready for test cases" exit criteria, the advisory checker and validator, and the review loop that made FileBackup's decomposition converge.
stacks: [any]
domains: [any]
phases: [dev, gate]
tags: [architecture, decomposition, components, interfaces, runtime-flows, n2, allocation, review]
scope: project
---

# Architecture decomposition (components, interfaces, flows)

A FileBackup project skill, distilled from the `DirectRebuild` sessions of
2026-10-18 (rounds 3o to 3x), where an unattended session decomposed the system
and two independent review loops converged it. ai-template's own decomposition
skill (review-churn item 12, work item P6) is not built yet. When it ships,
compare it with this one and keep the better rule. The sources behind each rule
are in [references/architecture-breakdown-research.md](references/architecture-breakdown-research.md)
(NASA SE Handbook and NPR 7123.1, DAU, SEBoK, Parnas, ATAM, ISO 42010).
For writing the requirement rows themselves use `spine-authoring`; for
module design inside the code use `deep-module-design`.

**Why.** Sound rules applied from prose were not enough. The agent drew
components by processing phase, put flow steps on the wrong component, and
declared the design done before it was. An ordered procedure, generated views
and a checker run after every pass, plus an independent review each time,
turned it around.

## The model this assumes

- **Components** (`CMP`, nested by `part_of`) describe the system's **own
  internal behaviour**. An external system (a source being read, a restore
  target, a desktop session, an installed tool) is an external interface,
  never a component. The internal component that *faces* an external system is
  a normal component, Parnas's device interface module.
- **Interfaces** (`IF`) state their **form only**: one information kind in one
  direction, with a value domain closed enough to test. The owner is the
  component that produces or defines the value, or an `external:` party. A
  row lists `consumers` or `requestors`, not both.
- **Behaviour** across an interface lives in the LLR (or, at the system
  boundary, the SR) that `constrains` it.
- **Placement is derived:** an LLR sits on the owner of the interface it
  constrains, and an external owner resolves to the system root. An LLR need
  not constrain an interface; an unplaced LLR is counted, not refused.
- **Rows never bind the implementation.** LLR text names no code file,
  function or symbol, and LLRs carry no `module`, `code_symbol` or `component`
  cell (the validator refuses them). Code points *up* to the spine later
  (`Component:`, `Implements:`, `Contract IF-NNN:` headers), so the code stays
  free to be restructured.
- **A parent** may hold states of its own (the owner's choice in FileBackup:
  the restore kit's launch, admission and finishing). It then owns the
  interfaces to its children. A message between a parent and its child is
  composition and needs no interface.

## Procedure, at each component scope, in order

1. **Draw the states first.** Write a state flow (the modes a stakeholder could
   name, the transitions, and the failure endings) and the key sequence flows,
   in `docs/runtime-flows.md`, before naming any child. Phases, modes and steps
   belong to the behaviour view, not the component tree. *Skipping this split a
   restore into five phase-components that each read nearly every input.*
2. **Give each candidate child its secret:** the one decision it hides, in one
   sentence. A candidate with no secret of its own is a state, not a
   component.
3. **Generate the N2 chart** (`check_design_layer.py --n2`), then add the
   values the flows show passing between children. A filled cell with no
   interface row is an **unnamed value**.
4. **Settle every unnamed value:** either name it as an interface (one kind,
   one direction, owned by its producer, a closed form), or fold the two
   components into one. Record which, and why. A value of a kind an existing
   interface already carries becomes a field of that form; mint a new row only
   for a new kind.
   - **4b. Check each form against its readers.** For every interface, read
     the LLRs of each consuming component and check that the form carries
     every value they use: a shared budget, a start time, a source folder, a
     "permitted, not made" result. The N2 chart can't do this, because it only
     sees declared values. *In FileBackup a reviewer found seven such gaps the
     checker could not.*
5. **Make the sibling argument** (Parnas, Clements and Weiss 1985, goal g): no
   two siblings overlap, and together they cover the parent. Record the
   candidates you considered splitting or merging, even when you keep them.
6. **Apply the descend test to each leaf.** Decompose what a stakeholder can
   describe as a state. Stop at an invented number, a paraphrase, or something
   with no pass/fail. A state becomes a component only when it hides a decision
   of its own.
7. **Show quantified rules at the parent.** A rule over all siblings ("summed
   over every configured location") needs a phase in the parent's flow that
   sees them all, before any of them runs.
8. **Complete every consumer and requestor list from the flows.** Each message
   between two components that are not parent and child needs an interface
   linking them or their ancestors.
9. **Run the validator and the checker** (below). Fix every finding the design
   owns, and record the rest as residue with its cause.
10. **Send the pass to an independent reviewer**
    ([references/review-prompt.template.md](references/review-prompt.template.md)).
    - **Scope:** everything the pass changed, *including rows changed to apply
      owner rulings*.
    - **Constraints:** list the owner's decisions, and any architecture the
      owner imposes, as deliberate decisions. The reviewer then checks
      consistency instead of reopening them.
    - **Fixes:** fix what's confirmed, including defects in the previous round's
      fixes, and send substantive fixes back once more. *Two of FileBackup's
      checks each found defects in the previous round's fixes.*
11. **Record each call for the owner:** what was decided, the alternative, and
    why, with "flipping it is a row edit". Unattended, gather them in one file
    the owner reads first.

## Runtime-flow conventions

[references/runtime-flows.template.md](references/runtime-flows.template.md)
has the skeleton. The checker relies on these:
- **Layout:** flows sit under `## Runtime flows`, one `###` per flow.
- **Participants are components,** with one id in each label:
  `participant Pub as Publication (CMP-011)`.
- **Citations:** a message between two components cites the **interface** it
  travels on; a self-message cites the **LLR** performed. A request credits the
  receiver, and a reply (`-->>`) the sender.
- **Coverage:** every SR is in a flow, or listed under
  `## Requirements no flow renders` as a static rule.
- **Maintenance:** update a flow in the same change as its LLRs.
- **Mermaid hazards:** `Note` can't be a participant alias; no `;` in message
  text.

## Ready for test cases: the exit criteria

The design isn't done until all eight hold (research report §6):
1. **Allocation is complete both ways:** every leaf carries a placed row, and
   every SR reaches a placed row or is declared system-level with a reason.
2. **Interfaces are consistent:** each has a consumer and a constraining row,
   each external one a local endpoint, and each holds one information kind.
3. **Behaviour and structure correspond:** every message has an interface, and
   each lifeline's citations match placement, or the gap is recorded.
4. **Every SR is in a flow,** or declared flow-free.
5. **The state flows are disjoint and covering,** failure endings included.
6. **Quality-attribute scenarios are analysed,** ATAM-style: the stimulus and
   the response for each quality, the risks, the sensitivity points and the
   trade-offs.
7. **Decisions are recorded** with their alternatives.
8. **There is a verification approach for each external interface:** real
   fixture, surrogate, mock, or attest.

## Tools

On Windows run them with `py -3.12 -X utf8`: the default `python` is 3.8,
which has no `tomllib`, and the console is cp1252.

- [scripts/validate_design.py](scripts/validate_design.py)
  `[<repo-root>] [--design <dir>] [--pairs <file>]`: structural errors, such as
  unresolved ids, `consumers` with `requestors`, an LLR with both or neither of
  `sr_refs` and `parent`, a forbidden code-binding cell, or an interface nothing
  constrains. `--pairs` is a free-text list of SR-to-interface pairs, for SRs
  that carry no `constrains` cell.
- [scripts/check_design_layer.py](scripts/check_design_layer.py)
  `[<repo-root>] [--n2] [--shared CMP-NNN,...]`: advisory. It reports empty
  leaves, interface consistency, messages with no interface, coverage and
  citations, and lifeline citations against placement, grouped by cause:
  - **A:** placed at the root through an external interface;
  - **B:** unplaced;
  - **C:** placed on another component.

  `--n2` prints an N2 chart per scope. `--shared` names shared-definition
  components (such as a store format), so a write to one is credited to the
  writer.
  Groups A to C are mostly ai-template's placement rule, not the design: rows
  done by one component but placed at the root or the format's owner. Read them,
  don't chase them to zero.

## Failure patterns to watch for

- Components drawn by processing phase (step 1).
- A flow step on the wrong component: a guard doing others' work, a launcher
  taking a lock for every operation (step 8 and the checker).
- Reading a placement artifact as design evidence. A leaf looks empty because
  its rows constrain an *external* interface, which places at the root.
- One interface carrying two document kinds, owned by a third component.
- An interface form missing a value its readers need (step 4b).
- A rule over all siblings drawn per sibling (step 7).
- Declaring done without the exit criteria.
- Trusting a reviewer run that never read the files.
