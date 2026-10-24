# Spine authoring in a lane

Use the mode table and parent rule in [../SKILL.md](../SKILL.md), "Three ways a
spine grows". The tier questions in §1–§3 apply in both lane modes.

## In a lane, released rungs: one change set, authored and judged whole

Why closed and whole: an open set converges one missing link per sitting (a
child returned for want of a parent, then a TC for an arm its LLR states).

- **Name the anchor first.** This is the approved need or requirement the
  change hangs from. An additional obligation derived through a lens needs a
  labelled derived SR (§2(c)); a missing stakeholder outcome needs an SN
  proposal, not an unrelated parent.
- **Author the subtree in one pass.** Include every new and amended row from
  the anchor down (SRs, LLRs, TCs and interface rows) and each approved row
  whose text the change makes untrue. New rows stay `Drafted`; interface rows
  carry no approval status. Leave existing statuses unchanged while authoring.
- **Author it before the build.** TC rows are authored with their LLRs before
  the build, so the build's first deliverable is the tests they name. Their
  trace fields (TC `Evidence`, LLR `Module` and symbols) name the tests and
  symbols the build will create, and bind when the set is reconciled. Row
  text is still reconciled and judged against settled code, as below.
- **Map the arms.** For each LLR, list what it states (each outcome, refusal
  and exemption) and the TC clause that verifies each. Structural checks do
  not establish this coverage.
- **Amend the row text against settled code.** While the code is still
  changing, keep only the trace fields current (`Implements:`, LLR `Module`
  and symbols, TC `Evidence`) and list the row-text changes the code implies.
  Write and judge them once the code stops moving: each text change made
  after a sitting owes another (`docs/process.md` §4, "sequence
  requirement-text work *into* an open window"). A Done-when edit is the
  exception: it holds the lane's next build until its exact text is blessed.
- **Reconcile before judgement.** Check the whole set against the code and
  its trace fields before the sitting.
- **Close the edges before the sitting.**
  - Each row's parent is in the set or already approved.
  - Each TC names its LLR and that LLR's SR.
  - Each interface row the change adds or alters has a citing TC.
  - `scripts/check_trajectory.py --strict` passes, and so does
    `scripts/trace.py --strict` from DevStg-Impl. Below that rung
    `trace.py --strict-integrity` stands in, because an SR still lacking its
    LLR or TC is the rung's own open work; that is also why the harness's
    traceability step starts at DevStg-Impl. They check the whole repo, so
    judge arm coverage separately using the map.
- **Judge it in one sitting, top-down.** One combined adjudication (the
  `combined` brief) takes the set's amendments, first approvals and any
  Done-when change together. Keep each kind's verdict lines in its own section
  of one verdict file; commit it before each kind's act, taken in its own
  reviewed commit. Read parents before children and approve parents first.
  If a parent is returned, withhold its children's approval and distinguish
  chain-only returns from defects in the children's own text.

## In a lane, a held rung: split the set at the dial

Use the same authoring and closure checks, then split approval authority:

- **Held first drafts stay `Drafted`.** Include them as chain evidence; their
  approval stays with the owner through the approval brief.
- **Judge held amendments for CLARITY or MEANING.** CLARITY means the obligation
  is unchanged. Only an independent sitting that rules the amendment CLARITY
  may re-attest it, and that verdict, bound to the text it was shown, is what
  permits the act: edit the row after the sitting and the act is refused, so
  re-sit it. Naming the verdict in the act's `--verdict` is for audit.
  A MEANING change awaits the owner. Leave existing statuses unchanged.
- **Released children wait for their held parent.** They may be judged in the
  same sitting, but approved only after the parent is approved for its current
  text. The status half is checked at the commit (the `parent-first` step and
  the merge slot); the text half is the drift report's (the amendment walk and
  the re-attestation).

If the snapshot refuses because another approved row in the registry still
drifts, leave it unanchored and report the refusal; do not widen the act to
include text you have not judged (`docs/process.md` §4; amendment brief).
