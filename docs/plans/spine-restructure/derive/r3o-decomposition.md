# Round 3o: the decomposition pass (session 2026-10-18 d)

The design tier had its component tree, interfaces and LLRs, but not the
architecture step's own outputs. ai-template's ruled method (review-churn
plan, item 12, not yet built or filed as a work item there) asks, at each
component scope and before the LLRs: the state flow, the scope's boundary
interfaces with their value domains, and an output × input dependency table.
Then it applies the descend test (F-call 6) to each candidate child. This
record does that for FileBackup's two decomposed scopes, the backup engine
(CMP-007) and the restore kit (CMP-017), and turns the six empty leaf
components into calls for the Owner.

The state flows and the sequence flows are in
[../../../runtime-flows.md](../../../runtime-flows.md) (flows 1 and 5 are the
state flows).

## Why six leaves are empty

Placement is derived: an LLR lands on the component that owns the interface it
constrains (or, from round 4, the interface its test case observes at). An
interface owned by an external party resolves to the system root. So a leaf
gets nothing when its rows constrain only:

- an external interface (source capture on the source tree view; restore
  admission on the target probe and tool floor; the launchers on the host
  session and folder dialog); or
- an interface its parent or a sibling owns (the content writer's stored
  objects belong to the store format; the check's findings document belongs to
  the launch component).

Round 3's builder was told not to mint interfaces just to place rows, and
ai-template discourages that too. The question is therefore not "how do we
place these rows" but, per leaf: **is there a real boundary the tree has not
drawn, or is the leaf drawn finer than the design needs?**

## Backup engine (CMP-007)

**States** (flow 1): admitted, planned, claimed, staged, published or
unchanged, collapsed, released; refused, busy and reclaimed as the endings.
The claimed-to-released span is the exclusive-use guard's; the planned state
runs as a reader.

**Boundary interfaces at this scope.** In: the source tree view (IF-028),
volume space (IF-031), the archive tool (IF-035), the media probe (IF-036),
the environment (IF-007), the configuration (IF-004). Out: the store
(IF-013..IF-018, IF-030), the change-detection record (IF-029), the views
(IF-041, IF-042), the findings document (IF-010). Shared with the restore kit
through the store format (CMP-016).

**Output × input dependency table** (✓ = the output depends on that input;
"walked entries", "change set" and "content map" are values that pass between
children today with no interface row):

| Output (owner) | Source tree | Config | Walked entries | Change-det. record | Latest record + evidence | Run state | Change set | Space | Archive tool | Content map | Run folders, verdict | Content index |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Walked entries (CMP-008) | ✓ | ✓ | | | | | | | | | | |
| Change set (CMP-009) | | | ✓ | ✓ | ✓ | ✓ | | | | | | |
| Change-detection record IF-029 (CMP-009) | | ✓ | | | | | ✓ | | | | | |
| Stored objects IF-016 + content map (CMP-010) | | ✓ | | | | | ✓ | ✓ | ✓ | | | ✓ |
| Published states IF-013..018, IF-030 (CMP-011) | | | ✓ | | ✓ | | ✓ | | | ✓ | ✓ | ✓ |
| Claim, staging, verdict IF-032, IF-033, IF-044 (CMP-012) | | | | | ✓ | | | | | | | |
| Removal, report (CMP-013) | | | | | ✓ | | | ✓ | ✓ | | ✓ | ✓ |
| Findings, repair, kit refresh (CMP-014) | | | | | ✓ | | | | ✓ | | ✓ | ✓ |
| Views IF-041, IF-042 (CMP-015) | | ✓ | | | ✓ | | | | | | | |

**What the table shows.** The capture → change detection → writer →
publication chain passes three narrow values (walked entries, change set,
content map), each with a small, closed shape, and each crossing between two
components that hide different decisions: how the OS walk behaves (links,
names, retries), how change is judged (the comparison and the re-read
schedule), how content is stored (one owner per content key, the compression
decision, object naming), and how a state is published safely (the staging
order). Those are sparse-dependency, narrow-value boundaries, the kind item 12
says interfaces belong on. Separately, the findings document carries two
distinct information kinds (the check's findings and the saved-state report),
produced by two components and owned by a third.

### Call 1: Source capture (CMP-008)

- **(a) Keep it, and draw its real boundary** *(recommended)*: an internal
  interface, the walked source entries (owner CMP-008; consumers CMP-009 and
  CMP-011), whose form is each entry's path, size, time, attributes and kind
  from a closed set (file, folder, folder link followed, folder link recorded,
  file link, name refused, not captured, with cause). The rows about what the
  walk yields constrain it (LLR-055, LLR-109, LLR-110, LLR-111, LLR-065); the
  rows about behaviour across the source itself stay on IF-028 (LLR-001,
  LLR-078, LLR-112, LLR-067, LLR-151, LLR-152).
- **(b) Fold it into change detection** as one "source scan" component; both
  consume IF-028 today.

### Call 2: Content writer (CMP-010)

- **(a) Keep it, and draw its real boundary** *(recommended)*: an internal
  interface, the stored-content map (owner CMP-010; consumer CMP-011): per
  content key, the stored name, the stored form and whether it was newly
  written, adopted or stored again. LLR-003, LLR-058, LLR-086 (with LLR-004
  and LLR-116) and LLR-053 constrain it. The compression decision is a
  decision worth hiding (and gap D7 already notes its policy sits in the wrong
  module today).
- **(b) Fold it into state publication.**

### Call 3: Check, repair and kit refresh (CMP-014)

- **(a) Split the findings document** *(recommended)*: IF-010 becomes two
  rows, the check findings (owner CMP-014) and the saved-state report (owner
  CMP-013), since they are distinct information kinds with distinct producers.
  LLR-049, LLR-054 and LLR-129 constrain the check findings; LLR-047 the
  report. LLR-096 (one machine-readable document form for both) stays as the
  shared rule.
- **(b) Move IF-010's ownership to CMP-014 whole**, leaving the report a
  consumer of its form.

## Restore kit (CMP-017)

**States** (flow 5): launched, admitting, waiting, restoring, finishing,
reported; refused as the ending before anything is written.

**Boundary interfaces at this scope.** In: the restore request (IF-020), the
host session and folder dialog (IF-026, IF-027), the target probe (IF-025),
the tool floor (IF-024), the store (IF-013..IF-018, through CMP-016), the
claim test (IF-032). Out: the kit artifact set (IF-019), the restored tree
(IF-023), the outcome and report (IF-021, IF-022).

**Output × input dependency table:**

| Output (owner) | Request | Session, dialog | Target probe | Tool floor | Kit files | Record + evidence | Claim test | Stored objects | Folder, link records | Admission verdict | Entry results |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Request and target (CMP-022) | ✓ | ✓ | | | | | | | | | |
| Admission verdict (CMP-018) | ✓ | | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | | | |
| Restored files, entry results (CMP-019) | | | ✓ | ✓ | | ✓ | | ✓ | | ✓ | |
| Finished tree IF-023 (CMP-020) | | | ✓ | | | ✓ | | | ✓ | | ✓ |
| Outcome, report IF-021, IF-022 (CMP-021) | | | | | | | | | ✓ | ✓ | ✓ |

**What the table shows.** The restore's children are its phases in order:
admission, entries, finishing, outcome. Each phase reads nearly every input
the restore has, and passes the next only a verdict or a list of results. A
phase split is decomposition by processing step, which the method's descend
test (F-call 6, point 1) separates from decomposition into components: a
state earns LLRs and a runtime flow, and becomes a component only where it
hides a decision of its own. Admission and finishing are states. Entry
restoration (content search by key, IF-045) and the outcome classification
(IF-021, IF-022) do hide decisions and already own interfaces. The launchers
are kit artifacts whose form IF-019 already states.

### Call 4: Restore admission (CMP-018), Tree finishing (CMP-020), Launch and target choice (CMP-022)

- **(a) Fold all three into the restore kit (CMP-017) as states**
  *(recommended)*. The restore kit's children become entry restoration
  (CMP-019) and outcome and report (CMP-021). The admission, finishing and
  launch rows are placed at CMP-017 where they constrain IF-019, IF-020 or
  IF-023, and at the root where they constrain an external interface, exactly
  as today; flows 5 and 6 keep the phases visible.
- **(b) Keep them and mint internal interfaces** for the admission verdict and
  the entry results, plus a launcher interface. That draws boundaries inside
  one script per route, and the launcher interface would restate what IF-019
  already says (one meaning carried by two interfaces, a failure pattern the
  method names).

## What stays unplaced after these calls

Rows that constrain an external interface still resolve to the system root:
the source-tree behaviour rows, the target probe and tool floor rows, the
session and dialog rows, provisioning's floor rows. In round 4, each one's
test case names the interface it observes at, which places it where that
interface's owner is. Rows constraining no interface (the 28 counted in this
session) are placed the same way, and the remainder is counted, not refused.

## The Owner's calls (applied in round 3p, `r3-merged/_r3p_apply.py`)

| Call | Ruling | Applied |
|---|---|---|
| 1, Source capture | **(b) fold into change detection.** The Owner's principle: components describe FileBackup's own internal behaviour; the source belongs to an external system and is an external interface (IF-028), never a component, so it does not earn a component of its own here. | CMP-008 retired into CMP-009, renamed "Source scan and change detection". The walk's rows still constrain IF-028 and show at the system root. |
| 2, Content writer | **(b) fold into state publication.** | CMP-010 retired into CMP-011, renamed "Content storage and state publication". Its rows stay unplaced (stored objects are the store format's). |
| 3, Findings document | **(a) split IF-010.** | IF-010 is now "Check findings" (owner CMP-014, constrained by LLR-049 and LLR-096); new IF-047 "Saved-state report" (owner CMP-013, constrained by LLR-047). |
| 4, Restore phases | **(a) fold into the restore kit as states.** | CMP-018, CMP-020 and CMP-022 retired into CMP-017; flows 5 and 6 keep admitting, finishing and launch visible as states. |

The tree is now 19 components. The analysis above is kept as written before
the calls.
