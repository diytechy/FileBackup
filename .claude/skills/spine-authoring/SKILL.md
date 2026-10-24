---
name: spine-authoring
description: Use when breaking down or developing the SN → SR → LLR → TC spine — the adjudicator's question list per tier: what a need must carry before it is approved, what belongs at SR versus LLR versus the trace tier, when an obligation is a labelled derived requirement, and which instruments catch a distorted breakdown. Also use when authoring or judging a lane's spine change for a found defect or new scope.
stacks: [python, node, powershell, go, rust, any]
domains: [any]
phases: [dev, gate]
tags: [requirements, decomposition, tiering, derivation, hats, derived-requirements, acceptance-criteria]
scope: kit
---

# Spine authoring (breaking down SN → SR → LLR → TC)

You are the **adjudicator**: the one deciding what a row says and which tier it
says it at. Every mechanized check on the spine is a *detector* — it reports a
smell after the fact. The tiering itself is a judgement, and this is the question
list to put to a row **before** it lands (the questions themselves have one
shipped home, named under §1–3 below).

**Authoring is not approving** (owner rulings 2026-09-01 and 2026-10-07;
`docs/process.md` §4). The authoring session writes its rows `Drafted` and may
amend any cell of any row, approved ones included. It never flips a `Status` to
`Approved`/`Founded`, never writes a row already claiming one, and never writes
`docs/archive/last_approved/` — that act is an independent adjudicator's, never
the session's that authored the rows, taken in the authoring lane or on trunk
after reading the row's whole chain, and a lane's merge is refused by name for
any act no accepted verdict judging its own rows backs. So use the question list to make a row *ready*; the answer to "is
it approved" comes from elsewhere.

**Authority, not restated here:** `docs/process.md` §3 (one fact one home;
decompose don't paraphrase; one decision per row, one home per method; one
`shall`; the eight quality characteristics and the EARS statement pattern; a
need or requirement cell names a concrete artifact only where its reason cell
records why that artifact must be constrained; a rationale carries its own
reason and no citation frame) and §4
(gates, verification methods). Read the rule there; use this file to decide
whether your row obeys it.

## The frame: solution-freedom is tier-relative

The rule that stops most arguments: **keep the SR independent of filenames.**
Record where a capability currently lives in the trace fields that already
exist for it — the LLR `Module` cell, the TC `Evidence` cell, the `Implements:`
back-links in code, or a registry id (an interface row, a component row) — not
in requirement text and not in acceptance criteria. A registry **id** is a safe
anchor where a filename is not: the id is stable while its contents are
rewritable.

And no published body *bans* concrete names — every one gates them on **recorded
justification** (INCOSE R31 "unless there is rationale for constraining the
design"; ISO 29148's "*unnecessary* constraints"; NASA's "if the requirement
states a method of implementation, the rationale should state why"). DO-178C puts
low-level requirements in the Design Description beside the architecture and
defines them as directly implementable — **naming design elements at LLR tier is
the expected shape, not an exception**. So: SR = delivered-capability voice,
LLR = solution-specific by design, and the artifact's identity belongs in the
trace fields listed above. Route and justify leakage; a rule that forbids it
just gets bent silently.

## At adoption or a material project change

Review the project's own vision, stakeholders, domain, operating environment
and changed assurance obligations before relying on its existing hats or spine.
Apply this at initial adoption and to the affected scope of an upgrade or
project change. A tooling-only upgrade may record "no semantic impact" with
its reason in the resync commit; routine commits do not require a whole-spine
rederivation.

Use the ordinary scoped change/review record for the following decisions:

1. **Reassess hats against purpose.** Keep, refine, combine, condition or propose
   retirement by each hat's question and failure class. Add a hat only when an
   important distinct question has no suitable owner. A seed roster, a preserved
   custom file or zero attributed rows does not establish relevance. When
   changing or removing a hat, review its inbound Hat-Refs and preserve valid
   obligations.
2. **Check the real brief.** Inspect applicability on representative need/WI
   contexts, including missing context and not-applicable cases. `hats.py audit`
   is a worksheet; confirm that the actual decomposition receives every relevant
   question. The roster lives in `docs/requirements/hats.toml`; the audit shows
   the SN × conditional-hat matrix, needs reaching no conditional hat and each
   hat's reach count. Repair unreachable predicates or missing declared tags through the
   ordinary authoring/review route, without inferring context from arbitrary prose.
3. **Revisit needs, then affected SRs.** A missing stakeholder outcome warrants
   a new-SN proposal with purpose and observable acceptance intent. An existing
   sound need with a missing perspective-derived constraint warrants an SR
   amendment instead. Use a fresh derivation before comparing implementation-led
   legacy text where independence matters; read legacy rationales before declaring
   an obligation unsupported. A sound requirement violated by code needs a fix,
   not another need.
4. **Reconcile and review the affected chain.** Identify changed LLRs, TCs,
   interfaces, evidence and queued/active work. Keep IDs where meaning remains;
   preserve previous approvals as history and submit the scoped amendments under
   the current authority. Rejected proposals leave authoritative content intact.
   Do not automatically re-seed snapshots, cancel work or copy the kit's own
   objectives, hats or needs into another product.

Syntax checks prove reference integrity and preservation; independent judgment
assesses relevance and adequacy. Optional prose objective anchors explain
purpose without adding a registry tier, approval stage or completion percentage.

## Three ways a spine grows

Choose the mode before writing. The `human_approval_through` dial in
`docs/process.toml` holds rungs at or below it for the owner (`docs/process.md`
§4).

| Mode | What it is | How it is judged |
|---|---|---|
| **From the vision** | The first breakdown | Tier by tier: approve each tier before deriving the next (§1–§3) |
| **In a lane, released rungs** | A defect or new scope whose changed rows are all on released rungs | One change set, authored whole and judged in one sitting |
| **In a lane, a held rung** | The change touches a held rung | Split at the dial: held first drafts and MEANING changes wait for the owner; the sitting may re-attest only held amendments ruled CLARITY in its verdict |

**In every mode, a child is approved only after its parent.** An SR waits for
every SN it cites, an LLR for every SR, and a TC for every SR and LLR it
verifies. An approved child under a `Drafted` parent claims a chain nobody has
blessed. The enforcers: `check.py`'s `parent-first` step refuses the commit
that moves either status into such a case, the merge slot's lane-commit walk
refuses it on each lane commit, and `trace.py --strict-integrity` reports a
standing case. Approve parent and child in one act, or the parent first.

Before authoring or judging a lane's change, read
[references/in-lane.md](references/in-lane.md) for closure and held-rung rules.

## 1–3. The tier questions — one home, shipped with the kit

The questions to put to a row live in one file the kit ships beside its
prompt templates: `prompts/spine-questions.md` (in the kit's own repository,
`project-trajectory/prompts/spine-questions.md`). §0 applies to every row, §1
at SN intake, §2 at SR derivation and §3 at LLR and TC; the `§N(x)` references
in this skill point there. Read the section for the tier you are authoring or
judging. The adjudication briefs compose the same sections at render time, so
the adjudicator and this skill read one text. Do not copy a question into this
file: change it there.

## 4. Validation instruments

- **Blind re-derivation.** The strongest instrument, and it is a *validation
  exercise, not a rewrite*: independent sessions derive a breakdown from the
  stakeholder needs + the boundary frame + **the hats roster** (the roster is a
  derivation input — a lens that is not in the blind input set cannot produce its
  obligations), never reading the current SR/LLR/TC rows or the code. A separate
  alignment pass — the only role permitted to read both sides — builds a map with
  three buckets: **matched / orphaned-in-legacy / orphaned-in-fresh**. Every
  orphan is **adjudicated** as a finding, never silently merged or deleted; the
  legacy row's own rationale is read *first*. Two teams with **different
  decomposition axes** beat two teams with the same one. Classify each
  legacy orphan: **(i)** implementation-born (a derived-requirement candidate —
  label it), **(ii)** a genuine need the blind teams missed because the *need*
  understates it (a needs defect, not an SR defect), **(iii)** true accretion.
- **The authoring advisories** (§2d) read as a cheap standing sweep over an
  existing registry: run `scripts/trace.py` and read the artifact,
  shared-artifact, fan-out and EARS sections as a worklist of rows to
  re-adjudicate. The
  **verification-coherence** section joins the same sweep: it names a row whose
  prose claims an instrument its `Verification` field contradicts.
- **The method-flip sweep — do this by hand, no checker covers it whole.** When
  a row's `Verification` changes, EVERY prose cell it owns is suspect, not just
  the one you came for. A row mechanized out of `Critique` typically leaves the
  claim in three places: the AC (the instrument), the rationale (the argument
  that the instrument was *necessary* — often phrased as "a mechanized
  verification would assert a green nothing checks", which the row's own passing
  tests then refute), and the retired instrument's own header. Sweep the row,
  its children, and anything citing the retired instrument, in the same commit
  as the flip.
- **The approve brief.** `scripts/trace.py --approve <scope>` renders the batch's
  SN→SR→LLR→TC hierarchy with prose for the acceptor to read, and
  `--approve modified` renders the per-cell before/after re-attestation brief.
  Link the brief; never hand-copy rows into it. (Running the bar itself: the
  `gate-advance` skill. Orphans, integrity and schema findings:
  `registry-hygiene`.)

## 5. Known failure modes

One line each, each one seen in a real spine:

- **Implementation-mirroring** — the "fresh" breakdown re-describes the code
  rather than the need. Guard: blind derivation; a requirement must hold for all
  acceptable products, not just the built one.
- **False constraints** — solutions masquerading as constraints (Volere §3a's
  own name for it). Guard: every constraint carries a rationale *and* a fit
  criterion, both challengeable.
- **The why-cell trap** — a need's load-bearing half (safety, bounds, authority)
  lives only in its `why` cell, so the SR realizing it reads need-less and looks
  like accretion. The defect is in the need. (Seen: a subagent-spawn bound whose
  need stated only *resumable*, with the *safe* half in `why`.)
- **The untagged need / blind hat** — the governing perspective evaluates tags
  the need does not carry, so the hat that most obviously governs it is
  guaranteed not to see it. (Seen: the data-protection, accessibility and
  performance lenses unable to read the very needs they govern.)
- **The buried condition** — the row's condition sits after the `shall` ("shall,
  during an unattended run, refuse…") or opens on a near-miss keyword ("Before
  X…", "For declared…"). Every reader who scans openings to learn *when a row
  applies* misses it, and so does every tool. Guard: the EARS advisory catches
  the opening; the buried-in-the-middle case is yours to catch, because a
  qualifier that describes the RESPONSE legitimately lives there.
- **Colour-only signals** — an obligation naming the system's most important
  signal by its **colour** ("a reader can believe a green") does not exist for a
  substantial class of readers; state the channel, not the hue.
- **Switched-off hats orphaning obligations silently** — a row derivable only
  through an OFF hat looks like accretion to every later reader. It must say so
  in its rationale (§2c).
- **Underivable-from-any-input rows** — when needs-only, frame-only *and*
  hat-aware derivations all fail to produce a row, the missing thing is a need or
  a hat charter. Say which; do not quietly keep the subtree. (Seen: a
  cross-view-uniformity requirement with eight LLRs and eight TCs behind it and
  no declared input demanding it.)
- **Package-wide properties with no home** — an obligation cited as a secondary
  clause in many rows and as the subject of none is uncovered, however many
  citations it has.
- **Acceptance rot after a method flip** — a row states one verification method
  in its `Verification` field and a different one in its prose. Every strict
  gate passes at rc=0 while the row instructs a reader to obtain a verdict its
  own method cannot produce. (Seen: two rows mechanized out of `Critique`, whose
  acceptance went on demanding an APPROVE verdict from rubrics whose own headers
  by then read RETIRED — three weeks and several reviews before it surfaced,
  because nothing compared the two cells.)
- **A citation that outlives its instrument** — retire-don't-delete is right for
  the instrument and wrong for the rows citing it. Retiring a rubric without
  sweeping its citers converts every one of them into an undischargeable
  criterion.
- **The unwired marker** — a state field nobody reads. Adding it is not the same
  as wiring it, and a marker with no consumer is the original gap with a better
  name. Ask, at the moment you add it: which checker, gate or brief changes
  behaviour because of this cell? If the answer is none, say so in the row.
- **A rule that names only some of its tiers** — and the tier quietly left out
  is usually `SN`, the one a stakeholder actually reads. Seen twice: the
  artifact-voice rule shipped governing `SR` alone and the provenance rule
  governing `SR`/`LLR`/`TC`, and each had to be extended to the need tier
  afterwards. Guard: writing or amending a spine rule, enumerate all four tiers
  and say why each one is in or out.
- **A row amended without its own re-attest** — a row's `Status` answers for
  its OWN cells (`docs/process.md` §4; owner ruling 2026-08-17): re-read the
  row whose text changed, and only that row — a child LLR/TC amendment never
  touches its parent SR. There is no marker to set (`Modified` retired
  2026-08-20); EVERY post-approval amendment is the snapshot-drift arm's find
  (`docs/archive/last_approved/`), never the parent signature's, and the
  chain-completeness claim belongs to the derived `Founded` state (D-9).
  The amendment is yours to make; the RE-COPY is the approval act and belongs
  to the adjudication (the preamble above; `docs/process.md` §4), which takes it
  in the same commit as its own ruling on the amendment.

## 6. Cell hygiene — a registry holds living truth

Tiering decides *which row* says a thing. These decide *what a cell may hold at
all*, and they cut across every tier. Each is cheap to violate and expensive to
find later, because the mechanized detectors mostly read PROSE and these
failures hide in FIELDS.

- **A cell states what is true now — never when it changed.** Provenance has
  homes that cannot drift: git, the log's decisions, the archive. A field
  recording an amendment date is the same defect the stand-alone rule forbids in
  prose, and it survives only because the checker reads text, not schema. If you
  are about to add `amended`, `updated`, `since` or a version stamp to a
  registry row, the fact already exists somewhere better.
- **The reason cell is not a changelog.** `Rationale` (`why` at `SN`) is the one
  cell whose whole job is argument, which is why every citation drifts into it —
  and it is covered by the rule above, on all four spine tiers. It states **what
  breaks without the row** and **which alternative lost**, and carries no citation
  frame: no work-item id, no ruling, sitting, review-round or open-item reference,
  no decision id, no `AMENDED`/`REWORDED`/`MINTED` verb, no date stamp. Those
  belong in the log, which can hold the full account and cannot rot into the
  specification.
- **When you strip a frame, keep the reason.** The failure mode is deleting
  `AMENDED 2026-03-04 (round 2, finding F7): the cell claimed a speedup nothing
  measures` in one stroke — frame *and* argument — leaving a bare assertion.
  Restate the durable half as standing prose ("this states a structural property,
  not a throughput claim: no instrument here measures speedup") and send the rest
  to the log. If deleting the frame leaves nothing, the cell was a changelog and
  the log already holds it; delete the whole block. `scripts/trace.py` reports
  what is left as a **worklist**, warn-first — a row whose frame is the only
  record of an unresolved question gets a reviewed entry in the detector's
  allow file rather than a silent deletion.
- **A cell is not a receipt — test it on a reader with no history.** A cell
  written just after a correction tends to answer the version it replaced ("no
  longer counts drafts", "now read from the registry", "only the declared
  set"): it is a receipt for the fix, and it reads as a rule only to someone
  who saw the fix. The test is cheap: hand the cell alone to a fresh context
  and ask it to restate what the row requires. If its restatement reconstructs
  the correction ("so it used to count drafts"), the cell carries provenance;
  rewrite it as what holds, and put the correction in the log.
- **One vocabulary per axis, across every tier.** If three tiers say `Drafted`
  and the fourth says something else for the same state, a reader must learn a
  different field per tier and every cross-tier query grows a special case.
  Reach for the vocabulary that exists before minting a parallel one — a new
  marker for a state the spine already names is a synonym, not a feature.
- **Do not declare what the row already derives.** If a field's value is a
  function of the other cells — a type implied by which fields are present, an
  owner implied by a link — it is a second source that can disagree with the
  first. A redundant cell can be deleted; a *disagreeing* one cannot, and you
  will not know which you have until it disagrees.
- **One question per field.** A field answering two unrelated questions (a
  maturity state and a row type in one `kind`) cannot be queried for either
  without knowing the other, and neither half can change vocabulary
  independently.
- **Prefer the smallest closed vocabulary that stays honest.** Enum values are
  cheap to add and near-impossible to remove once rows carry them; a value whose
  meaning overlaps an existing one will be applied inconsistently from the day
  it lands.
