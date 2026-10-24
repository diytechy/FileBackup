<!-- Provenance: research sub-agent (Claude Opus 5.5), 2026-10-18. Desk research only; nothing else was edited. Kit inputs read first: ai-template docs/knowledge/system-decomposition-methods.md, review-churn item-11-value-domain-research.md, README.md items 11 and 12, pointer-rules.md; FileBackup AI-TEMPLATE-NOTES.md, derive/r3o-decomposition.md, docs/runtime-flows.md. All web sources retrieved 2026-10-18. -->

# How established practice breaks an architecture down before implementation

*Gap research for ai-template's design layer (CMP, IF, derived LLR placement, descend test), measured against what FileBackup hit in round 3o. It doesn't repeat the partitioning maths (system-decomposition-methods.md) or value domains, SCR and the descend test's sources (item-11 research).*

## Summary

The kit's design layer agrees with established practice on more points than it differs. It keeps one structural tree, puts interfaces on every boundary, keeps form apart from behaviour, closes value domains and ties every interface to a test. The holes are about **allocation** and **checking**, not structure. In order of importance:

1. **Placement looks at only one side of an external interface.** NASA's interface requirements document sets requirements "on each side of the interface plane", and Parnas builds an *internal* module whose secret is each external device. So a row about reading the source tree belongs to the component on our side of that interface. The kit sends it to the root. That one rule emptied three of FileBackup's six empty leaves; the other three were emptied by interfaces owned by a parent or a third component (gap 2).
2. **Allocation follows interface ownership only, never who does the work.** RUP-SE, OOSEM, Arcadia and NASA allocate functions and requirements by walking white-box scenarios: which element performs each step. The kit already has those scenarios (runtime flows whose participants are components and which cite LLR ids). It neither uses them for placement nor checks them against placement. FileBackup's flow 2 puts LLR-001, LLR-109 and LLR-112 on CMP-009's lifeline while the registry places them at the root.
3. **Completeness is checked one way only.** Practice checks both directions: every requirement is allocated (NASA SDR: "All technical requirements are allocated to the architectural elements"), and every element carries at least one requirement (DAU: each component "meets at least one (or part of one) functional requirement"). The kit counts unplaced rows and never flags an empty component.
4. **Cross-cutting requirements have no allocation kind.** Budgets and apportionment (SEBoK, DAU, NASA TPMs), RUP-SE's *derived* (per-collaborator) requirements and Parnas's *shared services* module give "every writer does X" or a performance figure a definite home. The kit's "unplaced, counted" lumps those in with rows that are simply misallocated.
5. **There is no entry criterion between "architecture drafted" and test cases.** NASA gates with SDR and PDR success criteria, ATAM evaluates quality-attribute scenarios before code, and 42010 wants correspondence rules between views. The kit has a critique cadence but no written list of what must be true.
6. **Behaviour and structure aren't sequenced or linked.** SEBoK warns that static decomposition "should be established only when scenarios have been created". FileBackup drew components first and flows afterwards, and the restore kit got split by phase.

Smaller gaps: no N2-style format for the dependency table, no designer-side stopping criterion, and no required decision record with alternatives (FileBackup's "Calls" already have that shape).

---

## 1. Functional, logical and physical architecture

**What the sources say.**
- **SEBoK, Logical Architecture.** The logical architecture has functional, behavioural and temporal parts. Behaviour is "a set of inter-related scenarios of functions and/or operational modes". The logical model is kept "independent" of implementation as far as possible. Pitfall: static decomposition "should be established only when scenarios have been created".
- **SEBoK, Functional Architecture.** The functional architecture is "an architectural 'view' or 'perspective'", not a separate sub-unit of the system.
- **SEBoK, System Architecture Design Definition.** The order runs requirements → functions → logical elements (platform-independent) → physical elements. "Each logical configuration item has a set of allocated functions and subfunctions."
- **NASA SE Handbook, §4.3.** Functional analysis has three steps: translate requirements into functions; "decompose and allocate the functions to lower levels of the product breakdown structure"; then identify interfaces.
- **DAU, *Systems Engineering Fundamentals*.** DoD recognizes "functional, physical, and system architectures". The physical architecture comes from the functional one through design synthesis.
- **OOSEM** (Estefan survey). The steps run: system as a black box, then *Define Logical Architecture* (logical components, partitioned "based on partitioning criteria such as cohesion, coupling, design for change…"), then *Synthesize Allocated Architectures*.
- **Arcadia.** The order is operational analysis → system need analysis → logical architecture ("each function being allocated to one component") → physical architecture.

Every method separates *what is done* (functions, modes, scenarios) from *what does it* (logical components) and from *what realizes it* (physical parts, files). Most draft behaviour first or alongside structure, never after it.

**How ai-template compares.** The CMP tree "drawn by responsibility" is a **logical architecture**. Files are mapped to it later by `Component:` headers, which is the physical allocation. There is no functional view as such. The runtime flows (state flows plus sequence flows) are the behavioural view, but they are required only "before the test-case review", after the tree is drawn.

**HOLE.** Without a behaviour-first step, process steps get drawn as components. That is what happened to FileBackup's restore kit: admission, entries, finishing, outcome and launch became five components, each reading nearly every input. The descend test's "a state is not yet a component" caught it afterwards. Practice prevents it up front: phases are *functions or modes* in the behavioural view, and components come from allocating those functions by information hiding. The kit has both halves but doesn't sequence them or state that they are two views of one design.

## 2. Requirement allocation

**What the sources say.**
- **SEBoK, System Requirements Definition.** "Allocation is the process by which the requirements at one level of the physical architecture are assigned to those entities." Lower-level requirements are "child requirements of an allocated parent". A budget is "the total value of a parameter defined at the system level", split across elements.
- **NASA SE Handbook.**
  - §4.3: "Both the baselined and derived requirements are allocated to the system architecture and functions." Derived requirements "arise from the definitions of the selected architecture".
  - §6.2: "ensure that all top-level parent document requirements have been allocated to the lower level requirements". A requirement with no parent is a traceability flaw or gold plating.
  - TPMs track the critical budgeted parameters.
- **DAU.**
  - Allocated requirement: one "established by dividing or otherwise allocating a high-level requirement into multiple lower-level requirements", for example 100 lb split into 70 and 30.
  - The Requirements Allocation Sheet links functions, allocated performance and the physical item.
  - Each component "meets at least one (or part of one) functional requirement".
- **RUP-SE** (Estefan survey). A subsystem requirement is **allocated** "if a … subsystem is assigned sole responsibility for fulfilling a system requirement", and **derived** "if it is identified by studying how the subsystem … collaborates with others to meet a system requirement". RUP-SE adds a white-box flow of events "to make decisions about where events are hosted".
- **Parnas, Clements and Weiss (1985), A-7E module guide.** Each *Function Driver* is "the sole controller of a set of closely related outputs". A *Shared Services* module "hides an aspect of the behavior that applies to two or more of the outputs": one home for cross-cutting behaviour.

**Is allocation authored or derived?** In every source above it is **authored**: a design decision, recorded in a matrix or sheet and traced. What gets derived is the *consequence*, such as child requirements, interface requirements and budgets per element.

**How ai-template compares.** Placement is **derived** from one relation, the owner of the interface a row constrains (or the interface its test observes at). Rows constraining nothing are "counted, not refused". The LLR parent tree is the right tool for derived and apportioned children, but nothing ties it to the component tree.

**HOLE.**
- **No allocation kinds.** Practice gives a spanning requirement one of four kinds:
  - *sole*: one element;
  - *derived per collaborator*: children per component;
  - *budgeted*: apportioned values whose sum is checked;
  - *system-level emergent*: verified only at the boundary, with a reason.

  "Unplaced" in the kit mixes all four with plain misallocation, so the count tells an owner nothing.
- **The derivation key isn't the performer.** Interface ownership is a proxy for "who does this". It fails exactly where the performer consumes an interface it doesn't own: an external one, or one owned by a parent or a third component.

## 3. The system boundary and external systems

**What the sources say.**
- **C4, System Context and Container diagrams.** External people and systems "sit outside the scope or boundary" of the system. Only the system in scope is decomposed; externals stay single supporting elements.
- **OOSEM.** "The system is modeled as a black box that interacts with the external systems and users." Its logical components include "a user interface that is realized by a web browser, or an environmental monitor that is realized by a particular sensor", which are internal components facing external things.
- **RUP-SE model levels.** Context is "System black box — the system and its actors".
- **Arcadia / Capella.** System analysis is a black-box analysis of the system and its actors. Forum guidance warns against modelling the system itself as an actor. (Forum sources, see "Not verified".)
- **Parnas, Clements and Weiss 1985.**
  - The *Hardware-Hiding Module* "implements virtual hardware that is used by the rest of the software"; its secrets are "the hardware/software interfaces described in … the requirements document".
  - The *Device Interface Module* "provides virtual devices to be used by the rest of the software".
  - Information relevant to one device is "a secret of a Device Interface Module".
- **NASA SE Handbook, Appendix L (Interface Requirements Document outline).** "Define the interface requirements on each side of the interface plane." Each subsection derives interface requirements "based on the allocated requirements contained in the applicable specification pertaining to that side of the interface". §3.1.2 "Interface Responsibilities" defines "interface boundary responsibilities".
- **Parnas and Madey's four-variable model** (secondary sources). Requirements (REQ) relate environment quantities. The mapping from those quantities to device inputs and outputs (IN, OUT) is a separate, design-side relation.

**Does any method model an external system as a component?** No. All of them keep externals outside, which matches the FileBackup Owner's principle. **But all of them put an internal element at each external interface.** Parnas's device interface modules, OOSEM's "environmental monitor" and NASA's per-side interface requirements say the same thing: what *our system* must do at an external interface is a requirement on *our side*, allocated to the internal element that meets it.

**How ai-template compares.** An `external:` interface resolves to the system root, so every row constraining it lands there, "however clearly the rows are its own" (AI-TEMPLATE-NOTES §2). The IF row already records consumers and requestors, and the kit already speaks of "an authorized local endpoint" for an external-owned contract body. The local side is known; placement ignores it.

**HOLE, and the rule that would have prevented the empty leaves.**
- **Rule:** a row constraining an external interface is placed at the interface's **local endpoint(s)**, the component(s) on our side of the interface plane. It goes to the root only when no local endpoint is declared, and that case is a finding.
- **FileBackup under that rule:** source capture (IF-028), restore admission (IF-024, IF-025) and the launchers (IF-026, IF-027) would each have held their rows.
- **What it wouldn't change:** whether those components *should* exist. That is still the Parnas question of what decision each hides. r3o's analysis says source capture hides "how the OS walk behaves (links, names, retries)", which is a device-interface secret in Parnas's sense. The Owner folded it on the principle that an external system isn't a component. The literature supports that principle, but it doesn't say the *internal component facing* an external system should be folded. Call 1 was judged partly through the placement artifact. The ruling stays the Owner's; the point is that the emptiness was produced by the kit, not evidence about the design.

## 4. Interfaces

**What the sources say.**
- **N2 chart** (Lano, TRW 1977; listed as a tool by NASA and DAU; the layout from Wikipedia, see "Not verified").
  - Elements sit on the diagonal.
  - Off-diagonal cells hold the interface *from* one element *to* another, so each cell is one direction.
  - A blank cell means no interface.
- **NASA SE Handbook.**
  - §6.3: "During project Formulation, the ConOps of the product is analyzed to identify both external and internal interfaces … As the system structure and architecture emerges, interfaces will be added." The analysis establishes "the origin, destination, stimuli, and special characteristics" of each interface.
  - §4.3: interfaces are identified as step 3 of functional analysis, together with decomposition, not after it.
  - Interface types: Interface Requirements Document (requirements per side), Interface Control Document or Drawing and Interface Definition Document (the agreed definition).
  - "Interface requirements verification is a critical aspect of the overall system verification."
- **NPR 7123.1D, Table G-6 (PDR success criteria).** "Definition of the system interfaces (both external entities and between internal elements) is consistent" with the design's maturity.
- **Ownership.** NASA assigns responsibility organizationally (interface working groups, board structure; Appendix L §1.3 "Responsibility and Change Authority"). In software, Parnas's access programs belong to the module that holds the data: the provider owns the interface.

**How ai-template compares.** The kit is well aligned here:
- One IF per information kind and direction (OI-67) matches N2's directed cells.
- The owner is the producing component.
- Form on the IF row, behaviour on the constraining LLR, maps onto definition versus requirement (ICD/IDD versus IRD).
- Every IF must reach an executable test, which matches NASA's interface-verification emphasis.

**HOLE.**
- **Behaviour isn't stated per side.** "The LLR that constrains it" doesn't say which side the LLR binds. An IRD always does, and that side is what should drive placement (§3).
- **The dependency table has no defined format.** An N2 per scope is the established one. It shows what FileBackup found by hand:
  - unnamed values passing between children ("walked entries", "change set", "content map") are filled cells with no IF row;
  - IF-010 is a cell whose *owner* is neither its producer nor one information kind.
- **Interfaces are drawn after components.** NASA finds interfaces from the ConOps first and refines them with the structure. The kit draws boundary interfaces after components (item 12's order puts the state flow first, but FileBackup's tree predated it).

## 5. When to stop decomposing, and phases versus components

**What the sources say.**
- **NASA §4.4.1.2.5.** "When do we stop refining the design?" Answer: when it can "allow analytical validation of the design to the requirements and ConOps" and "convince a review team of a feasible design with performance, cost, and risk margins". NASA §4.3: continue until requirements are "viable, verifiable, and internally consistent".
- **SEBoK Logical Architecture.** Decompose until functions map to elements "for which physical solutions are known, feasible, or possible to imagine". It warns against going "too deep".
- **Parnas, Clements and Weiss 1985.**
  - "A module is a work assignment for a programmer or programmer team."
  - The number of branches should be "small enough that the designers can prepare convincing arguments that the submodules have no overlapping responsibilities and that they cover all of the responsibilities".
  - "Processes are not programs; there is no simple relation between modules and processes."
- **Parnas 1972** (already in the kit). Decomposition by processing step is the weaker criterion.
- **Harmony-SE** (Estefan survey). Its stated objectives include "Identify associated system states and modes" and "Allocate system functionality / modes to a physical architecture". Modes are *allocated* to structure; they are not structure themselves.
- **Kruchten 4+1.** Scenarios serve "as a driver to discover the architectural elements" and "a validation and illustration role after this architecture design is complete".

**How ai-template compares.**
- The descend test is a good *requirement-side* stopping rule (item-11 research): stop at an invented number, a paraphrase, or no pass/fail.
- Its point 1 ("a state earns LLRs and a runtime flow; whether it becomes a component is separate") is Parnas's module-versus-process distinction. FileBackup's restore fold shows it working.

**HOLE.**
- **No designer-side criterion.** "One work assignment hiding one secret" and Parnas's "argue no overlap and full coverage among siblings" are missing.
- **No sequencing.** Nothing says the scope's state flow and at least one sequence flow come *before* its children are drawn.
- **No correspondence between the two structures.** Modes and steps should be allocated to components and checked; today runtime flows and the tree are independent artifacts with only id citations between them.

## 6. Checking the architecture before implementation

**What the sources say.**
- **NPR 7123.1D, Table G-5 (MDR/SDR success criteria).**
  - "All technical requirements are allocated to the architectural elements."
  - "The architecture tradeoffs are completed."
  - Entrance criteria include "Preliminary system interface definitions" and "Preliminary Verification and Validation Plans".
- **NPR 7123.1D, Table G-6 (PDR).**
  - "The flow down of verifiable requirements is complete and proper."
  - The interface definitions are consistent.
  - A V&V plan is baselined at entry.
- **DAU, Verification** (adapted from IEEE 1220). Tasks include "Verify Architectural Completeness" and "Verify Functional and Performance Measures". "The verification list should have a direct relationship to the requirements allocation sheet."
- **ATAM** (Kazman, Klein, Clements 2000).
  - "The purpose of the ATAM is to assess the consequences of architectural decisions in light of quality attribute requirements."
  - "The ATAM can be done early in the software development life cycle."
  - A utility tree turns quality goals into scenarios with stimuli and responses.
  - Outputs: risks, sensitivity points, tradeoff points.
- **ISO/IEC/IEEE 42010** (via Emery and Hilliard 2008). Views are kept consistent by *correspondence rules*, for example "Every software element identified in the Logical View must be allocated to at least one computational element in the Deployment View". The 2000 edition already required an architecture description to "record any known inconsistencies among its views".
- **Kruchten.** Scenarios validate the finished architecture "on paper".

**How ai-template compares.** The kit has a critique at depth 0, every second depth level and once over the whole tree, gated at LLR sittings and DevStg-Tests entry. There is no architecture approval act, and runtime flows are required before the test-case review. FileBackup went from "design tier drafted" straight to "approve, then test cases" (AI-TEMPLATE-NOTES §1, §6).

**HOLE.** No written **entry criteria** for test-case work. What should exist between "architecture drafted" and test cases, drawn from the sources above:

1. **Allocation complete, both ways.** Every SR reaches a placed top-level LLR, or a declared system-level kind with a reason. Every leaf component carries at least one placed row.
2. **Interfaces consistent.** Every IF has a producer that is its owner, at least one consumer, and one information kind. Every external IF has a local endpoint.
3. **Behaviour and structure correspond.** Every runtime-flow participant is a component. Every message between two components is an IF row. Each LLR cited on a lifeline is placed on that component, or the gap is recorded.
4. **Scenario coverage.** Each SR appears in at least one flow, or is declared flow-free (for example, static format rules).
5. **Modes checked.** State flows are disjoint and covering (SCR, already in the kit's vocabulary).
6. **Quality-attribute scenarios analysed.** For FileBackup that means crash consistency, concurrent readers and stale-claim reclaim, with risks and sensitivity points listed.
7. **Decisions recorded,** with alternatives and rationale.
8. **Verification approach per external IF,** meaning how a test stimulates or observes it (surrogate, fixture, attest). This shapes test-case design.

## 7. Other things practice treats as essential that the method lacks

- **Decision records with rationale.**
  - NASA §4.3.1.2.3: capture "key decisions made, supporting decision rationale and assumptions".
  - NASA §6.3: capture "rationale for interface decisions made".
  - Nygard's ADR (Context, Decision, Status, Consequences): "One of the hardest things to track … is the motivation behind certain decisions."
  - The kit has rulings in status and log files, but no artifact attached to a component or interface. FileBackup's r3o "Calls" are ADR-shaped and could be the template.
- **Trade studies.** DAU: the physical architecture "is justified by trade studies". OOSEM's trade criteria are "traceable to the system requirements". NASA SDR requires trades completed. The kit's ranker (hypergraph cut) is a trade instrument, but no step requires alternatives to be compared and recorded.
- **Non-functional requirements shape structure.** SEBoK Physical Architecture: the physical architecture "is determined more strongly by non-functional requirements". Rozanski and Woods treat qualities as *perspectives* applied across all views. The kit's descend test and value domains are functional in character, and qualities enter only as SRs.
- **Technical performance measures.** NASA tracks budgeted, critical parameters across levels. The kit has a perf-budget mechanism (`PB-###`, inert in FileBackup) that isn't linked to components.
- **Viewpoints and correspondence rules** (42010). The kit has the views (registries, runtime flows, generated maps), but no stated rules between them (see §6, item 3).
- **Interface-to-verification traceability.** Already a kit strength: every IF must reach an executable test. Keep it.

---

## Recommendations for ai-template, ranked

Costs: **text** = wording in PROCESS.md, spine-questions or the planned rubric and skill; **check** = new advisory finding or derivation code; **cell** = registry schema change (downstream migration).

1. **Place external-interface rows at the local endpoint.** *(check: a derivation change; no new cell)*
   - **Change:** a row constraining an `external:` IF is placed at its declared local consumer or requestor component(s), not the root. No local endpoint declared is a finding.
   - **Rests on:** NASA Appendix L (requirements per side of the interface plane), Parnas's device interface module, OOSEM's logical components facing externals.
   - **FileBackup:** three of the six empty leaves (source capture, restore admission, the launchers) would have held their rows. The other three (content writer, tree finishing, check) were emptied by parent- or third-owned interfaces, which recs 2 and 6 catch. Calls 1 and 4 would have been judged on the decisions each hides, not on emptiness.
2. **Check runtime flows against placement.** *(check)*
   - **Change:** read the component lifeline on which each LLR id is cited and compare it with the derived placement. Report disagreements, components on no lifeline, and messages between components with no IF row. Advisory first.
   - **Rests on:** 42010 correspondence rules, RUP-SE's white-box flow of events, OOSEM logical scenarios, Kruchten.
   - **FileBackup:** flags LLR-001, LLR-109 and LLR-112 (on CMP-009 in flow 2, at the root in the registry) and the empty leaves, before any Owner call.
3. **Flag an empty leaf.** *(check, cheap)*
   - **Change:** a leaf component with no placed row, or one that neither owns nor faces an interface, is a finding. Name the two remedies (draw its real boundary, or fold it into its parent as a state).
   - **Rests on:** DAU ("each … component meets at least one … requirement"), NPR 7123.1 G-5 item 4.
   - **FileBackup:** the six empty leaves surface automatically instead of in round 3o (AI-TEMPLATE-NOTES §3).
4. **Give every unplaced row an allocation kind.** *(text, plus an optional cell)*
   - **Change:** sole / derived per component (child LLRs under a root parent) / budgeted (apportioned values, sum checked) / system-level emergent (root, with a reason). Count by kind. A cross-cutting behaviour gets either a shared-service component (one home) or a root parent with per-component children.
   - **Rests on:** RUP-SE allocated versus derived, DAU apportionment, SEBoK budgets, NASA TPMs, Parnas's shared services.
   - **FileBackup:** the 28 rows constraining no interface stop being one undifferentiated count. "Every writer does X" rows get a home.
5. **State the order: scenarios before children.** *(text)*
   - **Change:** at each scope, draft the state flow and at least one sequence flow *before* drawing child components. Say plainly that phases, modes and steps live in the behavioural view and components in the structural view, linked by allocation (rec. 2).
   - **Rests on:** SEBoK's logical-architecture pitfall, NASA functional analysis, Harmony-SE (modes allocated to structure).
   - **FileBackup:** the restore kit's five phase-components would have been drawn as states from the start.
6. **Make the dependency table a per-scope N2.** *(text, plus a generated view)*
   - **Change:** rows are producers, columns are consumers, and each cell holds an IF id or a named "unnamed value". Generate it from IF rows plus flow messages. An unnamed value is a finding, and so is a cell whose owner isn't its producer.
   - **Rests on:** the N2 chart (NASA and DAU tool lists), DSM.
   - **FileBackup:** answers AI-TEMPLATE-NOTES §4. It would have flagged IF-010 (two kinds, owned by a third component) and the three unnamed values in one table.
7. **Write the "architecture ready for test cases" entry criteria.** *(text in PROCESS.md §4; most items become checks via recs 1 to 3 and 6)*
   - **Change:** the eight-item list in §6.
   - **Rests on:** NPR 7123.1D Tables G-5 and G-6, DAU "verify architectural completeness", ATAM.
   - **FileBackup:** closes the skipped step between "design drafted" and test cases (AI-TEMPLATE-NOTES §1, §6).
8. **Add quality-attribute scenarios at the depth-0 critique.** *(text)*
   - **Change:** an ATAM-lite step: the data-integrity qualities as stimulus/response scenarios, with risks, sensitivity points and tradeoff points listed against the drawn architecture.
   - **Rests on:** ATAM, Rozanski and Woods.
   - **FileBackup:** flows 3 and 4 (concurrent readers, stale reclaim) become analysed scenarios with stated responses, not only diagrams.
9. **Require a decision record per decomposition call.** *(text)*
   - **Change:** context, alternatives, decision, consequences, and the decision each candidate component hides. Attach it to the scope.
   - **Rests on:** NASA §4.3.1.2.3 and §6.3, Nygard, OOSEM and DAU on trade studies.
   - **FileBackup:** r3o's Calls 1 to 4 already have this shape; this makes it standard.
10. **Add a designer-side stopping criterion to the descend test.** *(text)*
    - **Change:** stop when a component is one work assignment hiding one secret, and its siblings can be argued non-overlapping and covering. Beyond that, a further split must name the decision it hides.
    - **Rests on:** Parnas, Clements and Weiss 1985 (goal g), NASA §4.4.1.2.5, SEBoK.
    - **FileBackup:** gives the "fold or keep" calls a second, independent test beside the stakeholder-side one.

## Not verified

- **ISO/IEC/IEEE 15288** (Architecture Definition 6.4.4, Design Definition 6.4.5): paywalled. Only the process names (Wikipedia) and the Design Definition purpose as quoted by a GfSE process-model page were seen. Nothing above rests on clause text.
- **ISO/IEC/IEEE 42010:2022** normative text on correspondences and rationale: paywalled; iso-architecture.org refused connections. The correspondence-rule example is from Emery and Hilliard's 2008 working-session paper on the revision draft, not the standard.
- **INCOSE SE Handbook (5th ed.) and Needs and Requirements Manual:** paywalled. Named allocation types (equivalence, apportionment, synthesis) were not confirmed. The allocation kinds above rest on RUP-SE, DAU and SEBoK instead.
- **Arcadia's rule for allocating functions to actors versus the system:** only Capella forum posts and webinar slides, no method guide text. Treat §3's Arcadia lines as secondary.
- **N2 chart layout:** the NASA Rev 2 PDF only lists "N-squared diagrams" as a tool. The cell conventions come from Wikipedia's N2 chart article, which cites the 1977 TRW report (not seen).
- **OOSEM and Harmony-SE:** read through Estefan's 2008 INCOSE survey only, not Friedenthal et al. or the Harmony deskbook.
- **Parnas and Madey's four-variable model:** secondary descriptions only, as in the item-11 research.
- **SysML v2 allocation:** vendor documentation and tutorial summaries only; not used for any recommendation.
- **SEBoK "System Architecture Definition" article:** not found (404). The SEBoK Logical, Physical, Functional and System Architecture Design Definition pages were used instead.
- **NASA SDR/PDR criteria:** read from NPR 7123.1D Appendix G as rendered by WebFetch (summarized quotes). Check the exact table wording on NODIS before citing it verbatim in kit text.

## Sources (all retrieved 2026-10-18)

- SEBoK, *Logical Architecture*. https://sebokwiki.org/wiki/Logical_Architecture
- SEBoK, *Physical Architecture*. https://sebokwiki.org/wiki/Physical_Architecture
- SEBoK, *Functional Architecture*. https://sebokwiki.org/wiki/Functional_Architecture
- SEBoK, *System Architecture Design Definition*. https://sebokwiki.org/wiki/System_Architecture_Design_Definition
- SEBoK, *System Requirements Definition*. https://sebokwiki.org/wiki/System_Requirements_Definition
- NASA, *Systems Engineering Handbook*, NASA/SP-2016-6105 Rev 2: §4.3, §4.4.1.2.5, §6.2, §6.3, Appendix L. https://www.nasa.gov/wp-content/uploads/2018/09/nasa_systems_engineering_handbook_0.pdf ; §4.3 web page https://www.nasa.gov/seh/4-3-logical-decomposition ; §6.3 https://www.nasa.gov/seh/6-3-interface-management
- NASA, NPR 7123.1D, Appendix G (Tables G-5, G-6). https://nodis3.gsfc.nasa.gov/displayDir.cfm?Internal_ID=N_PR_7123_001D_&page_name=AppendixG
- Defense Acquisition University, *Systems Engineering Fundamentals*, January 2001 (chapters 4 to 7). https://ocw.mit.edu/courses/16-885j-aircraft-systems-engineering-fall-2005/6128a102c1a9b6dbd30f2fb18c12aa64_sefguide_01_01.pdf
- J. A. Estefan, *Survey of Model-Based Systems Engineering (MBSE) Methodologies*, INCOSE MBSE Initiative, Rev B, 2008 (Harmony-SE, OOSEM, RUP-SE). https://www.omgsysml.org/MBSE_Methodology_Survey_RevB.pdf
- Capella / Arcadia method overview. https://mbse-capella.org/arcadia.html ; Capella forum threads (secondary). https://forum.mbse-capella.org/t/mission-capabilities-and-functions/3105
- D. L. Parnas, P. C. Clements, D. M. Weiss, *The Modular Structure of Complex Systems* (A-7E module guide; IEEE TSE SE-11(3), 1985). https://john.cs.olemiss.edu/~hcc/csci555/notes/localcopy/Parnas_Modular_Structure.pdf
- R. Kazman, M. Klein, P. Clements, *ATAM: Method for Architecture Evaluation*, CMU/SEI-2000-TR-004. https://www.sei.cmu.edu/documents/629/2000_005_001_13706.pdf
- D. Emery, R. Hilliard, *Updating IEEE 1471: architecture frameworks and other topics*, WICSA 2008. https://www.mit.edu/~richh/writings/emery-hilliard2008.pdf
- P. Kruchten, *Architectural Blueprints: The "4+1" View Model of Software Architecture*, IEEE Software 12(6), 1995. https://www.ics.uci.edu/~michele/Teaching/INF117-S08/Krutchten%204+1View%20SWArch.pdf
- S. Brown, *The C4 model*: System Context and Container diagrams. https://c4model.com/diagrams/system-context ; https://c4model.com/diagrams/container
- N. Rozanski, E. Woods, *Perspectives*. https://www.viewpoints-and-perspectives.info/home/perspectives/
- M. Nygard, *Documenting Architecture Decisions*, Cognitect blog, 2011-11-15. https://www.cognitect.com/blog/2011/11/15/documenting-architecture-decisions
- Wikipedia, *N2 chart*. https://en.wikipedia.org/wiki/N2_chart
- Wikipedia, *ISO/IEC 15288* (process list only). https://en.wikipedia.org/wiki/ISO/IEC_15288
