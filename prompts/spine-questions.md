<!-- MAINTAINER NOTES (stripped before composition)

     THE ONE HOME of the questions an adjudicator puts to a spine row, per
     tier. Two readers, and neither holds a copy:
       - scripts/adjudicate_brief.py composes the sections whose tiers match
         the rows a first-approval or amendment brief judges (and each combined
         section composing those briefs) into that brief's {questions} slot at
         render time, so the brief stays self-contained in a repo with no
         skills installed;
       - the spine-authoring skill points here for its tier questions.

     GRAMMAR. A section is a `## ` heading followed, on the next line, by a
     tiers line naming the tiers it serves, space-separated (SN SR LLR TC DA
     SUR), or `*` for every tier. A section with no tiers line refuses every
     render, as does an absent or unreadable file, or a file declaring no
     section for a tier a brief judges: there is no fallback text. Text before
     the first `## ` heading is not composed. Keep the section numbers: other
     kit text cites them (e.g. "§2(c)").

     §3's first bullet (WI-911) is ruling 5 of the review-churn plan's owner
     rulings of 2026-10-11, as revisions 35 and 36 refine it: an LLR in
     contract voice, no implementation carrier in row text, and the traced
     `module` and `code_symbol` cells kept filled and binding until the plan's
     item 5 schema lane removes them. §0's naming rule (WI-911) is ruling 5's
     file-naming clause, held once where tier_questions composes it into every
     tier's brief, so an SN or SR sitting reads the same rule as an LLR or TC
     one; §1(e), §2(b), §2(d) and §3 point at it.
-->

# The adjudicator's questions, per spine tier

## 0. Every row — read the chain, not the row
<!-- tiers: * -->

- For each row, state to yourself the obligation it imposes: what a builder
  must do, what a test must check. A row you cannot restate as an obligation is
  not ready.
- Read UPWARD. Does the parent it points at actually call for this? A
  decomposition row that answers a requirement nobody made is scope, not
  detail.
- Read SIDEWAYS. Do the siblings together cover what the parent asks, without
  overlapping into each other's decisions? One decision per row.
- Read DOWNWARD. Do the test cases that claim to verify this row verify what it
  actually says — and does anything it says go unverified?
- Read the wording as a closed obligation: a "should" that means "must", a
  threshold with no units, an actor left unnamed, an acceptance condition
  nobody could observe. Each is a finding that sends the row back, not a note.
- **Name only what the row's tier may name.** No row's text names an
  implementation carrier (a code file, function or symbol). A shipped boundary
  artifact (a registry, template, config file or launcher) may be named at the
  LLR and TC tiers only; SN and SR rows name no file in any cell, acceptance and
  rationale included. An approved cell keeps its approved text verbatim, names
  included, until it is amended through its authority, and an amendment adds no
  name the rule forbids.

## 1. At SN intake — answer these before the need is approved
<!-- tiers: SN -->

A defect admitted here becomes a whole subtree of need-less requirements later.
Questions:

- **(a) Does this need carry the TAGS that reach its governing perspective?**
  Hats fire on declared fields; an undeclared field satisfies no condition.
  Use `python scripts/hats.py applicable --tag <tag> ...` and a check of the
  actual brief to verify the intended questions reach this need. The audit's
  strict finding detects unknown predicate tags, not adequacy of decomposition.
- **(b) Is every load-bearing clause in the NORMATIVE text?** A safety or bound
  or authority clause living in the `why`/rationale cell is not derivable: a
  deriving team reads the need and the acceptance, produces nothing for that
  clause, and the SR that *does* carry it reads need-less forever. Ask of each
  clause: **if a stranger derived only from `need` + `acceptance`, would this
  obligation appear?** If not, move it up into the normative text.
- **(c) Is the quality bar written down, or is it in someone's head?** "A reader
  can see progress" is not "the view is legible, uniform and operable". If a
  perceptual or quality obligation is wanted, **the need that wants it has to
  exist**; otherwise the requirements built on it are underivable from every
  declared input, and no amount of downstream rigour will rescue them.
- **(d) Would a blind reader recover the intended obligations from the text
  alone?** The honest test of a need. Where the answer is no, the defect is in
  the need — file it as a needs defect, not as an SR problem.
- **(e) Does the acceptance intent name an INSTRUMENT?** The no-concrete-artifact
  rule reaches this tier too (owner directive 2026-08-18, extending it from SR up
  to SN), and it bites hardest here: the SN `acceptance` cell is where a need
  quietly becomes a sentence about a file. "`trace.py --strict` reports zero
  orphans" fixes a *stakeholder outcome* to one script — it cannot survive the
  script being re-carried, and the stakeholder it exists for cannot validate a
  claim about a file they have never opened. Write the observable **condition**
  ("the strict traceability check reports zero orphans") and let the carrier be
  named where carriers belong: no SN cell names a file, `why` included (§0's
  naming rule), so a carrier the need seems to require is named at the LLR or
  TC tier, or cited by a registry **id**. A **declared vocabulary** token (a dial
  name, a status word, a flag) is NOT waivable naming and needs no token, because
  it is not a carrier. A **provenance** citation is not a carrier either — and it
  does not belong in the cell at all (§6).

## 2. At SR derivation — per row
<!-- tiers: SR -->

- **(a) One decision per row; one home per method** (`docs/process.md` §3). A row
  that decides both *which artifact* carries a capability and *what it does* is a
  tiering defect, not a style choice. Two rows sharing one interface identity is
  the same defect seen from the other side.
- **(b) Voice.** SN and SR alike state the delivered capability or the artifact
  **class** ("the delivered harness", "the launchers at the repository root") —
  one rule, two tiers, since the 2026-08-18 directive. The concrete
  name belongs one tier down — LLR `Module`, TC `Evidence` — and never in an SR
  cell, acceptance included (§0's naming rule); where acceptance genuinely needs
  an anchor, it cites a registry **id**. Acceptance criteria carry the **observable condition and its
  threshold** (Volere's *fit criterion*: an objective measure of the
  requirement's meaning) — *what would be observed and where the pass/fail line
  falls*, while *where and how* it is observed is the TC's.
- **(b2) Pick the EARS pattern from the OBLIGATION, then write the row.** The
  question is not "which keyword sounds right" but *what makes this requirement
  apply*: always (ubiquitous) · a discrete event starts it (`When`) · it holds
  for the duration of a state (`While`) · the trigger is a fault or misuse
  (`If … then`) · it applies only where an optional feature or declaration is
  present (`Where`). Three traps, all seen here:
  - **The buried condition.** `shall, during an unattended run, refuse…` states
    the same condition where no reader and no tool looks for it. Front it.
  - **A near-miss keyword.** "Before X…", "For work declared…", "During…" are
    conditions outside the pattern; `trace.py` warns on the opening, and the
    fix is to name which of the four it actually is (a *Before* is almost
    always a `When`; a *For <declared kind of work>* is almost always a
    `Where`).
  - **A condition that is really a response qualifier.** "fail that gate when a
    required tool is missing" belongs after the `shall` — it says *what the
    response is*, not *when the row applies*. Fronting it would change the
    obligation. This is why the checker warns rather than gates: only you can
    tell those two apart.
- **(b3) Does a joint-delivery row still state behaviour at a BOUNDARY?** Read
  every requirement named in `Delivered-With` and the assumptions each sibling
  cites directly. Check that their obligations and premises align around the
  shared need; never import one sibling's assumptions into another. Then apply
  the tier test: a row whose own output crosses a boundary is a real SR even
  when siblings complete the need with it, while a row whose output crosses no
  boundary and is consumed only by a sibling is a design decision and belongs
  at LLR. The shared-need checker is a detector; alignment and tier remain the
  adjudicator's judgement.
- **(c) If the obligation arrived through a lens rather than the need's text,
  RECORD the lens.** This is DO-178C's **derived requirement** class: content
  beyond what the parent demands, legitimate *because* it is (i) recorded as
  derived in a cell something reads, (ii) carrying a rationale that argues the
  deriving lens — the hat, the design
  constraint, the implementation fact — and (iii) fed back upward so the
  need owner sees it. Name the deriving hat in **`Hat-Refs`** (roster names; the
  cell IS the row's perspective record, and a name the roster does not declare is a
  finding) and argue it in `Rationale`. A prose label alone is not the record: it
  resolves against nothing, so nothing can tell a retired hat from a live one.
  **Never silently trace a derived row to a
  parent whose text does not demand it**: that is the single most common way a
  spine acquires structure nobody asked for and nobody can audit.
  - A row derivable **only** through a hat that ships switched OFF must say so.
    An obligation whose only lens is unreachable is a roster finding, not a
    licence — the label makes it reviewable; it does not make the row wanted.
- **(c2) Fill `Hat-Refs` as you mint the row, by the `listens_for` test — and
  leave it EMPTY when nothing passes.** (c) is the strongest case for the cell,
  not the whole population: a row can be attributable to a perspective without
  having been *derived* through one. The one test, stated so a later reader can
  falsify a cell rather than re-argue it: **attribute a hat only where THAT
  hat's own `listens_for` names a failure THIS row prevents.** The reading it
  displaces is "which lens could be held up to this row" — under that one a
  roster whose hats are mostly `always` puts every name in every cell and the
  column discriminates nothing. So read the failure classes instead of
  recalling them: `python scripts/hats.py list` prints each hat's `asks` and
  the `listens_for` it exists to catch, and `hats.py applicable --tag <tag> …`
  narrows to the ones a given context must face.
  - **An empty cell is an answer, and often the right one** — it reads *not
    recorded*, never *no perspective applied*, so it claims nothing. Two shapes
    earn it after you have looked: a row that names a hat in order to **refuse**
    it as a basis (the refusal is `Rationale`'s job — writing the name into
    `Hat-Refs` would assert the opposite), and a row whose attribution's
    **subject is gone**, where re-pointing the cell at a deleted mechanism is
    exactly the staleness the cell exists to make mechanical.
  - **Calibrate against the row's own argument.** One name is the common case.
    If a cell is heading for three, check whether the row really states three
    failures or whether the extras are stated by sibling rows — the hat belongs
    with the row that carries the obligation, not with every row nearby.
  - **Coverage is warn-only forever, in both directions**, and neither advisory
    is a quota: rows attributable to no declared perspective can be honest, and
    a hat attributable to no row is evidence about the ROSTER — a charter this
    project files no work in — not a hole to fill by attributing it somewhere.
  - **Which tiers carry it:** `SR` and `LLR` only. `SN` states the need a hat is
    a lens *on*, and `TC` records how a claim is checked; neither is a place an
    obligation is attributed, and neither schema declares the key.
- **(c3) Leave the decomposition's perspective record beside it, and review
  from it.** `Hat-Refs` cannot say that a perspective was weighed and found
  nothing. The decomposing session runs `python scripts/hats.py record
  <record-stem>.perspectives.toml --row <id> ... --by <who>` next to its
  decomposition record. That derives which hats applied and what each produced (own
  `Hat-Refs`), and the session writes a one-line `no_finding` for each applicable
  hat that produced nothing. As adjudicator, read that file, not the authoring
  transcript, and run `record <file> --check`. MISSING, STALE or CONFLICT goes
  back for a fix. Whether each no-finding is adequate is your judgement; the
  check only proves that every applicable hat has an answer.
- **(d) The advisories are detectors, not caps.** `scripts/trace.py` warns —
  never gates — on (i) an SR `Requirement` naming a concrete `.py` artifact,
  (ii) two SRs naming the same artifact token, (iii) an SN `acceptance` naming a
  concrete artifact (a wider vocabulary than the SR arm's — scripts, configs,
  generated pages — because the need tier's instruments are mostly not scripts;
  `.md` is deliberately excluded, since a document named in a cell is usually a
  citation), (iv) a direct-LLR fan-out over the declared bound (`SR_FANOUT_MAX`,
  default 7), (v) an opening that states a condition outside the four EARS
  keywords, and (vi) an absolute in a need, requirement or design cell whose
  domain names nothing from a closed list (below). There is no shared-artifact
  census at SN: two needs may honestly
  describe outcomes one file happens to serve without either deciding anything
  about it. A bound is deliberately
  not a cap: a hard cap invites merging two LLRs into one to slip under it,
  hiding the defect the number exists to surface. Clearing one is a **recorded
  per-row re-stamp** — the waiver token in the tier's reason cell (`Rationale`
  at SR, `why` at SN) for an approved cell's kept name (§0), never for a new
  one, the
  `fan-out re-stamp: <reason>` phrase for fan-out — and the reason must be one a
  later reader can **argue with**. "Accepted" is not a reason.
- **(d2) Is every absolute's domain really closed?** An absolute ("never",
  "always", "every", "any", a clause-opening "no") is a promise every child keeps
  under every condition. The advisory is silent when the words after it name a
  registry, an id or a declared set, and that silence is lexical: ask whether the
  named domain is one the system controls and someone actually declares, and
  whether an unnamed one ("every commit", "each session") is closed anyway. Over
  the open world or open time ("in every repo", "never silently") it is a premise
  that can be sampled, not tested: bound it, or carry it as an assumption row. In
  a need, a prohibited MECHANISM ("never from prose") is a design decision; move
  it down a tier. Only then waive, as `recorded waiver: <reason>` in the reason
  cell. Test cases are out: they state a method, not an obligation.
- **Also ask:** does this row state a *package-wide property* (right-sizing,
  proportionality, one-definition-of-passing, refusal legibility)? Those are the
  rows a per-capability decomposition systematically misses — they end up as
  secondary clauses in nine rows and the subject of none.

## 3. At LLR and TC
<!-- tiers: LLR TC -->

- **An LLR states its contract in words that survive a refactor.** Its text
  states the observable obligation: the inputs it takes, the outcome it
  produces and where it refuses, so a refactor that keeps the behaviour keeps
  the row true. It names no implementation carrier (a code file, function or
  symbol), and §0's naming rule says which tiers may name a shipped boundary
  artifact. Do not launder a concrete name upward
  into the SR to keep the LLR abstract. The traced `module` and `code_symbol`
  cells are trace homes, not row text: they stay filled and binding while the
  schema requires them (`trace.py --strict-schema` requires both;
  `check_doc_refs --strict` binds the symbol), so never return a row for
  keeping them. No `shall` in an LLR — the SR states the obligation, the child
  decomposes it.
- **A child adds detail.** If the LLR would merely re-word its parent, link
  instead. `trace.py`'s paraphrase advisory is lexical and warns forever; the
  judgement stays yours.
- **Replace an unsuitable design through the normal amendment route.** If the
  parent outcome remains sound but the LLR's mechanism causes the problem,
  compare the old/new design, retained parent clauses and behavioral regressions,
  affected trace/evidence/work references, and the code that becomes removable.
  Amend the LLR and its mechanism-specific verification together; an Approved
  LLR does not require keeping an obsolete shim. Preserve unchanged parent
  approval, re-attest changed child content through the applicable authority,
  and let the derived stage expose incomplete evidence. A changed stakeholder
  outcome, justified SR constraint or active WI scope returns to its own intake
  and approval path; it cannot be hidden as a design-only replacement.
- **An LLR's `Hat-Refs` holds only what its OWN decomposition raised — never a
  copy of its parent's.** The row's EFFECTIVE set is derived (own refs unioned
  with its `SR-Refs` parents'), so an own ref is earned only where the design
  row bears a hat **no parent carries**: a platform quirk in the mechanism, a
  keyboard path, an atomicity the requirement never states. Everything else is
  the copy-down the derivation exists to prevent — it turns re-ruling one SR
  into a sweep over its children, and the copies are what go stale. The `§2(c2)`
  test (a hat only where its own `listens_for` names a failure this row
  prevents) decides the rest: most design rows correctly carry nothing, because their
  parent already says why they exist.
- **Acceptance criteria hold the observable condition + threshold.** True of
  every cell that states acceptance, SN `acceptance` included — the tier changes
  what the condition is *about*, never that it must be a condition. Artifact
  identity lives at the trace homes: the LLR `Module` cell, the TC `Evidence`
  cell, `Implements:` back-links, registry ids. Trace media are explicitly open
  — code-comment back-links are a legitimate trace carrier, not a lesser one.
  **An artifact the TC already lists has no second home in the AC**: the second
  copy is the one that goes stale, and it goes stale silently because nothing
  joins the two cells.
- **State acceptance as the CONDITION, never as the instrument** — at SN
  acceptance-intent as much as here, and at SN it is enforced by an advisory
  (§2(d) iii). "A CRITIQUE
  session returns APPROVE against `<rubric>`" names a machine; "each clause of
  the requirement is bound to a child whose TC names the test holding it, and
  that binding set is closed over the clauses" names a condition. The second
  survives the instrument being replaced — which it will be, every time a
  subjective clause is mechanized. For a decomposed row the honest AC is
  usually *the chain, passing, closed over the clauses*.
- **Descend only where a mechanized check earns its keep** (`docs/process.md`
  §3, "over-aggressive traceability is a failure mode in its own right"). Where
  the honest floor is a human's judgement, name the verification `Attest` rather
  than inflate a subjective call into a false `Test`.
- **Record the stopping boundary in the existing scoped review.** For every
  retained child, state the independent decision or verification purpose it adds;
  when further splitting would only paraphrase or duplicate, record why the
  decomposition stops there. Keep the `SN→SR→LLR→TC` tiers required by the
  selected verification method and real verification links intact; this is a
  review judgment, not a row-count quota or a new schema.
- **Coverage by children is earned, not assumed** (the kit repository's ruling
  of record: `OI-72`). An LLR may be satisfied by its parent's coverage. An SR
  may be satisfied by its children only when the children span the SR's full
  dimensional space and are not interdependent; otherwise the honest states are
  a recorded orphan or a direct TC. No validator settles this, and none is
  likely to be efficient: it rests on the author's and the reviewer's reading.
