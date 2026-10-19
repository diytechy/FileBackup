# Decomposition review: the calls made while you were away

On 2026-10-18 you asked me to finish the component decomposition unattended,
by best judgement, and to record every call that deserves a closer look. This
file is that list, in the order I'd review them. Each says what I decided, the
alternative, and why. Flipping one is a row edit.

**Where the working is:**
- `docs/plans/spine-restructure/derive/r3t-root-decomposition.md`: the
  top-level pass, with the N2 charts and the sibling argument.
- `docs/runtime-flows.md`: flows 0 to 9.
- `docs/plans/spine-restructure/check_design_layer.py`: the checker. Run
  `py -3.12 -X utf8 docs/plans/spine-restructure/check_design_layer.py . --n2`.

The independent review of this pass (Codex Sol, round 3u) and anything it
changed is recorded at the end.

## Calls to review, most consequential first

### 0. The restore kit keeps its phases as its own states (review finding R3U-010 not taken)

- **What:** the round-3u reviewer argued, from Parnas's coverage rule, that a
  parent's work should all lie in its children. So the restore kit's launch,
  admission and finishing would be assigned to entry restoration or the
  outcome component.
- **Decided:** not taken, because it contradicts your Call 4, which made those
  phases states of the restore kit itself. As a consequence, the restore kit
  owns two interfaces to its children: IF-053 (the admitted restore) and
  IF-054 (the whole-restore results).
- **Look at:** whether you want the parent to do work of its own. If not, the
  cleanest alternative is to fold entry restoration and the outcome into the
  restore kit as well, making it one leaf. Its internal interfaces (IF-045,
  IF-050, IF-053, IF-054) would then become optional.

### 1. Seven internal interfaces were added (IF-048 to IF-054)

- **What:** each names a value that already passed between two components
  with no interface row:
  - IF-048: the launch dispatching each operation and taking its value; also
    the launch-wide space plan (a reader's pass per location, added after the
    review);
  - IF-049: the change set, source scan → publication;
  - IF-050: the entry results, entry restoration → outcome;
  - IF-051: the tools resolved at launch;
  - IF-052: entries written to the run record;
  - IF-053 and IF-054: the restore kit's own states handing the admitted
    restore to entry restoration, and the whole-restore results to the
    outcome (added after the review; see call 0).
- **Alternative:** your Calls 1 and 2 folded components rather than drawing a
  boundary between them. The same choice was open here: fold source scan into
  publication, entry restoration into the outcome, and so on.
- **Why I drew them:** folding these would merge components that each hide a
  different decision, and you kept those components apart in Calls 1 to 4. The
  architecture research says an unnamed value between two components is either
  an interface or a sign the two are one. Since they stay two, they're
  interfaces.
- **Look at:** whether seven extra rows is more structure than you want. IF-052
  (record entry) is the most debatable: logging is a cross-cutting service.

### 2. A new LLR was written: LLR-164 (dependencies resolved once per launch)

- **What:** a child of LLR-020. It says the runtime check, the tool locations
  and the hashing component are resolved once for each launch, every location
  uses them, and an absent extra is reported once, not per location.
- **Why:** IF-051 needed a constraining row, and neither existing provisioning
  row could move without leaving its own interface unconstrained. It describes
  what the entry point does today: it resolves tools once and passes them to
  every location.
- **Look at:** it is new requirement text written without you. The facts are
  today's code, but it's still a new obligation.

### 3. The exclusive-use guard (CMP-012) stays one component

- **What:** it holds four secrets: the operating-system claim, the owner
  record's liveness, the staging layout and the reclaim protocol.
- **Alternative:** split the claim from the staging and reclaim.
- **Why kept:** they change together. Your rulings P-14 to P-16 moved all of
  them at once. Splitting would cut one shared protocol, the failure the method
  warns of.
- **Look at:** if code mapping shows the guard is too big, the split point is
  the claim (IF-032) versus staging (IF-033, IF-044).

### 4. Content storage and publication (CMP-011) is the largest leaf

- **What:** it holds two decisions, how content is stored once and how a state
  is published safely, by your Call 2.
- **Why kept:** your ruling. The descend test would split it at the content
  map.
- **Look at:** revisit only if the code mapping shows it too large to work in.

### 5. Volume measurement sits in the store format (CMP-016)

- **What:** free-space and volume-identity measurement is a host-facing
  service, not a store-format decision. It sits in the store format because
  the restore kit needs it too, and the code keeps it in the restore-safe
  module.
- **Alternative:** a small "host volume" component that both sides consume.
- **Why kept:** it only affects code mapping. Its rows constrain an external
  interface, so they sit at the root either way.

### 6. The content-location index stays with removal (CMP-013)

- **What:** the check and the cross-state collapse also read it (IF-043).
- **Alternative:** its own shared-services component, in Parnas's sense.
- **Why kept:** removal is its main user, and nothing else in the tree is
  drawn as a shared service.

### 7. Consumer lists were completed

- **What changed:**
  - the container requests IF-002 (the launch request);
  - the launch requests IF-004 (the admitted settings);
  - notification consumes IF-003 (the run's value) and IF-009 (the record,
    for the mail body);
  - the guard consumes IF-014 and IF-015 (its reclaim reads and republishes
    records and evidence).
- **Look at:** low risk. Each change came from a flow message with nothing
  behind it.

## What I did not decide

- **The placement residue: 55 rows.** Rows placed at the root, left unplaced,
  or placed at the owner of a shared definition while a clear component does
  the work. This is ai-template's placement rule, not the design.
  `AI-TEMPLATE-NOTES.md` and `ARCHITECTURE-FINDINGS.md` carry it there. Round
  4's test cases will place some of these rows.
- **Your earlier open items still stand:**
  - the quality-scenarios page's three questions
    (`derive/r3s-quality-scenarios.md`);
  - the prose re-anchoring (`architecture.md`, `interfaces.md`, AGENTS.md
    sections 2 and 3);
  - your approval of the tiers.

### 8. The backup's order was corrected (from the review)

- **What:** the flows had the change set decided before the lock was taken.
  It's now:
  1. take the lock;
  2. read the store state and handle any leftovers;
  3. blank references to stored copies that have gone missing;
  4. only then make the change set the run acts on.
- **Two related changes:**
  - a comparison before the lock is a reader's estimate, used only for the
    launch-wide space plan;
  - the launch now plans every location before any location runs, which
    LLR-052 already required.
- **Look at:** this matches the rows (LLR-052, LLR-053, LLR-091, LLR-113). It
  may differ from today's code order, which the build will reconcile.

## Independent reviews of this pass

- **Round 3u** (Codex Sol, high, fresh session) on round 3t: 0 BLOCKER, 11
  MAJOR, 3 MINOR. 13 were confirmed and fixed in round 3v, mostly gaps in the
  new interfaces' forms plus three ordering faults in the flows. R3U-010 was
  not taken (call 0). It also noted that several code paths write records
  directly rather than through the shared logger: new build gap M97.
- **Round 3w** (final scoped check of round 3v): the first attempt failed
  before reading anything (a Codex sandbox error), and the retry completed:
  0 BLOCKER, 1 MAJOR. IF-054 could not say "this check was permitted not to be
  made" (for example, a target whose free space can't be measured, which a
  restore may proceed past). The form was fixed in round 3x and isn't
  re-checked.

**End state:**
- 19 components, 53 interfaces (11 internal), 142 LLRs;
- the validator reports 0 errors;
- the checker reports 0 design-owned findings. Its 55 placement disagreements
  are ai-template's placement rule.
