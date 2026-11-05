#!/usr/bin/env python3
"""Derive the EFFECTIVE STAGE from artifact states and cache it to `docs/stage`.

Stack-agnostic, standard-library only. This is the stage axis's own producer
(WI-498 slice 1, ruled plan `docs/plans/2026-08-21-stage-unification-plan.md`
§§1-3). It is now the ONLY derived-state producer: the transitional dual state
this module was born beside ended at slice 5, when `docs/gate` was deleted, its
`derive_gate.py` became the import-only `spine_rules.py`, and the retired axis's
one surviving CLI (`--next-phase`) was rehomed HERE — so the printed number and
the recorded `phase =` field are derived from the same rows by the same rule.

WHAT THIS ADDED THAT THE RETIRED `docs/gate` DID NOT HAVE.

1. **A per-phase stage.** `spine_stage` took no phase argument and `_per_phase`
   folded BARS, so "the current phase's stage" did not exist — the sharpest gap
   the deep-check found (Q2(iv)). It exists here.
2. **A draft-excluded reading.** `ex-draft=` is a bar and validating it against
   the stage ladder would type-check and return a wrong ordinal (Q2(v-d),
   refuted as a shortcut), so the counterfactual is computed here on its own axis.
   This is what stops one ordinary Drafted row from dropping a mature repo to
   what a fresh scaffold reads — C-01 on the new axis.
3. **A floor.** The bar axis floors at DevStg-Reqs and the stage axis did not, so
   the stage could reach ord 0, below every runnable rung. Under the at-or-above
   selection slice 2 lands, that is a repo where nothing runs and the run goes
   green because of it.
4. **A fingerprint of the declared inputs**, which is what lets any reader tell a
   current record from a stale one without parsing the registries.

THE DIVISION OF LABOUR. The pure half — the input list, the fingerprint, the file
format, the ordering, the floor and the fold — is `kitlib/stage.py`, because
`kitlib` may not import a sibling and the registry parse cannot go there. This
module is the half that needs the carrier: it loads the spine through
`spine_rules.load_spine`, groups the rows by phase, and calls `spine_rules`'s own
rung predicates so that the two axes can never disagree about what a Drafted row
is. When slice 3 re-discriminates the ladder it edits ONE fall-through
(`spine_rules.spine_stage`) and both files follow.

Contracts: IF-050, IF-165 — the interface seams this module declares
(process.md §8; rows of record in docs/requirements/interfaces.toml).

Contract IF-050: the derived stage RECORD at `docs/stage`. A plain run writes the
    effective rung, its ordinal, the unfloored settled and live readings, the
    per-phase and per-phase-live breakdowns, the drafted count and a SHA-256
    FINGERPRINT of the declared derivation inputs, one `key = value` per line
    under a comment header. Every field is addressed BY NAME, so a reordered
    record can never hand a reader the wrong value. The fingerprint is the
    contract for the two reading postures: a selection or approval consumer
    reads through `kitlib.stage.read_stage`, which recomputes the fingerprint
    and trusts the recorded values only on a match, deriving fresh in memory
    otherwise, so none can act on a stale rung; a render leaf parses the
    committed record as it stands, so the page and the file it cites describe
    one commit. The record is DERIVED and never hand-set: it moves by approving
    artifacts in a reviewed commit, and a hand-edited or cross-ladder value
    raises rather than reading as a rung.
Contract IF-165: the verdict every arm of this CLI answers in, 0 and 1 alone.
    `--check` returns 1 on an ABSENT `docs/stage` and on a record the recompute
    no longer reproduces, and 0 both on a record that still holds and on a file
    carrying no stage field — the scaffold placeholder, never derived and stale
    relative to nothing. The write run, `--print` and `--next-phase` return 0
    having done their work; `--phase-rule` returns 0 on a warned finding and 1
    only under `--strict`.
"""

import argparse
import datetime
import sys
import tempfile
from pathlib import Path

# Sibling: the derivation engine. This module reads its ROW PREDICATES and its
# rung fall-through rather than restating them — the two axes must never disagree
# about what a Drafted row is, and slice 3 re-discriminates the ladder in exactly
# one place because of it. Same guarded idiom the rest of the kit uses: run as a
# subprocess this script's own dir is sys.path[0], and the fallback covers an
# in-process import (a test) whose sys.path does not yet carry scripts/.
#
# And `assumption_rules`, for its one derivation of an assumption's citing
# requirements, which is what places a test case evidencing assumptions in its
# phases (SR-197; IF-201).
try:
    import assumption_rules
    import spine_rules
except ImportError:  # pragma: no cover - in-process fallback
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import assumption_rules
    import spine_rules

try:
    from kitlib import config as kitconfig
    from kitlib import git as kitgit
    from kitlib import ladder as kitladder
    from kitlib import stage as kitstage
except ImportError:  # pragma: no cover - in-process fallback
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from kitlib import config as kitconfig
    from kitlib import git as kitgit
    from kitlib import ladder as kitladder
    from kitlib import stage as kitstage

STAGE_FILE = kitstage.STAGE_FILE


def _git(root, args):
    """`git -C root <args>` stdout, STRIPPED, or None on any failure.

    A four-line wrapper over `kitlib.git.git_out` rather than a call to it,
    because `git_out` does NOT strip and every call here wants a bare token (a
    short SHA, a date) or a file body this module writes into a temp tree the
    same way its predecessor did. The strip is behaviour, not tidiness: it moved
    here VERBATIM when `derive_gate` became `spine_rules` (WI-498 slice 5) and
    shed its CLI, and changing it silently would change what the before-side
    tree contains.
    """
    out = kitgit.git_out(root, list(args))
    return out.strip() if out is not None else None


def _phase_label(row):
    """The phase bucket a row belongs to — the same `(default)` convention
    `spine_rules._per_phase` uses, so the two per-phase lines name the same
    buckets and a consumer can join them."""
    return (row.get("Phase") or "").strip() or "(default)"


def _phase_groups(srs, llrs, tcs, da_srs=None):
    """`{phase-label: (srs, llrs, tcs)}` — the rows each phase's stage is derived
    from.

    ASSOCIATION IS BY REFERENCE, NOT BY THE CHILD'S OWN `Phase` CELL, matching
    `spine_rules._per_phase`. The rungs ask "does THIS SR have an LLR, and is that
    LLR settled" — so an LLR belongs to the phase of the SR it decomposes, whatever
    its own cell says, and a mislabelled child cannot hide a phase's undecomposed
    requirement. A TC that cites only its LLR (a legal shape) is resolved back to
    that LLR's SRs for the same reason: otherwise a Drafted TC in that shape lands
    in no phase at all.

    AN ASSUMPTION HAS NO PHASE OF ITS OWN (SR-197). `da_srs` is
    `assumption_rules.da_citing_srs` over the requirements: a TC naming
    assumptions in `Assumption-Refs` joins the phase of every requirement citing
    one of them, so a case evidencing only an assumption sits in each phase whose
    argument relies on it, as a case citing several requirements already can.
    `None` places a TC by `Verifies` alone.

    Implements: SR-197, LLR-230"""
    by_phase = {}
    sr_phase = {}
    for row in srs:
        label = _phase_label(row)
        sr_phase[row["SR-ID"]] = label
        by_phase.setdefault(label, ([], [], []))[0].append(row)

    llr_srs = {}
    for row in llrs:
        cited = spine_rules.refs(row.get("SR-Refs"))
        llr_srs[row.get("LLR-ID") or ""] = cited
        for label in {sr_phase[s] for s in cited if s in sr_phase}:
            by_phase.setdefault(label, ([], [], []))[1].append(row)

    for row in tcs:
        labels = set()
        for ref in spine_rules.refs(row.get("Verifies")):
            for s in llr_srs.get(ref, [ref]):
                if s in sr_phase:
                    labels.add(sr_phase[s])
        for did in spine_rules.refs(row.get("Assumption-Refs")):
            labels.update(
                sr_phase[s] for s in (da_srs or {}).get(did, ()) if s in sr_phase
            )
        for label in labels:
            by_phase.setdefault(label, ([], [], []))[2].append(row)
    return by_phase


def _settled_off_spine(rows, table):
    """The off-spine rows a SETTLED reading keeps: everything not at DRAFTED
    maturity.

    Only the maturity arm is filtered. A `Founded` component whose `Standing`
    records a known gap stays IN — that is a settled row honestly reporting that
    the partition does not hold, which is a real rung-3 fact, not a pending
    draft."""
    return [
        r
        for r in rows
        if not spine_rules._caps(spine_rules._maturity(r.get("Status"), table))
    ]


# THE THREE TIERS THE STAGE READS FROM THEIR FIRST APPROVAL (SR-204), each
# with the maturity table its settled reading filters by: the settled branch
# drops their Drafted rows as it does every tier's, so a settled reading is
# never held by them, and the live reading holds a rung once a tier is active.
_FIRST_APPROVAL_TIERS = {
    "das": spine_rules.DA_MATURITY,
    "surs": spine_rules.SUR_MATURITY,
    "stks": spine_rules.STK_MATURITY,
}


def _stage_map(spine, settled, evidence_passed=False):
    """`(global-stage, {phase: stage})` over the live rows or the settled subset.

    A phase whose rows are ALL drafts disappears from the settled subset and is
    recorded as the `DevStg-Below` sentinel rather than dropped: the phase exists
    (its drafts say so) and has earned nothing, and those are different facts from
    "there is no such phase". `effective_stage` then ignores it, which is exactly
    how a brand-new phase is stopped from lowering the whole repo's reading."""
    srs, llrs, tcs = spine["srs"], spine["llrs"], spine["tcs"]
    sn_ids, sn_draft = spine["sn_ids"], spine["sn_draft"]
    bifs, cmps = spine["bifs"], spine["cmps"]
    # The three tiers read from their first approval (SR-204). A spine built
    # before they existed carries none of them, and reads as an empty tier.
    tiers = {key: spine.get(key, []) for key in _FIRST_APPROVAL_TIERS}
    live_labels = set(_phase_groups(srs, llrs, tcs))

    if settled:
        srs = [r for r in srs if not spine_rules.is_drafted(r)]
        llrs = [r for r in llrs if not spine_rules.is_drafted(r)]
        tcs = [r for r in tcs if not spine_rules.is_drafted(r)]
        sn_ids = sn_ids - sn_draft
        sn_draft = set()
        bifs = _settled_off_spine(bifs, spine_rules.BIF_MATURITY)
        cmps = _settled_off_spine(cmps, spine_rules.CMP_MATURITY)
        tiers = {
            key: _settled_off_spine(rows, _FIRST_APPROVAL_TIERS[key])
            for key, rows in tiers.items()
        }

    frame = dict(
        sn_ids=sn_ids,
        sn_draft=sn_draft,
        bifs=bifs,
        cmps=cmps,
        have_bifs=spine["have_bifs"],
        have_cmps=spine["have_cmps"],
        **tiers,
        # THE TEST-EVIDENCE VERDICT TRAVELS WITH THE FRAME (WI-500), for the same
        # reason the need/boundary/component rows do: it is a REPO-WIDE fact, and
        # a per-phase call must see the same one the global call did. A phase
        # whose own rows are all settled reads Release exactly when the repo's
        # suite is green on this tree — never on its own say-so.
        evidence_passed=evidence_passed,
    )
    overall = spine_rules.spine_stage(srs, llrs, tcs, **frame)
    groups = _phase_groups(srs, llrs, tcs, assumption_rules.da_citing_srs(srs))
    per_phase = {}
    for label in sorted(live_labels):
        group = groups.get(label)
        if not group or not group[0]:
            per_phase[label] = kitstage.BELOW
            continue
        per_phase[label] = spine_rules.spine_stage(
            group[0], group[1], group[2], cited_srs=srs, **frame
        )
    return overall, per_phase


def derive(root):
    """The stage record for the tree at `root` — the deriver the common reader
    calls on a fingerprint miss, and the value `--check` compares."""
    docs = Path(root) / "docs"
    spine = spine_rules.load_spine(docs)
    # THE ONE READ OF THE EVIDENCE CARRIER (WI-500). It is a property of the TREE,
    # not of the rows, so it is established once here and handed to both folds —
    # the live reading and the settled one answer the same question about the same
    # suite, and a mid-derivation change cannot make them disagree.
    passed = kitstage.evidence_passed(root)
    live, live_per_phase = _stage_map(spine, settled=False, evidence_passed=passed)
    _, settled_per_phase = _stage_map(spine, settled=True, evidence_passed=passed)

    effective, floored = kitstage.effective_stage(settled_per_phase)
    earned = [v for v in settled_per_phase.values() if v != kitstage.BELOW]
    settled_stage = min(earned, key=kitstage.order) if earned else kitstage.BELOW

    rows = spine["srs"] + spine["llrs"] + spine["tcs"]
    # The three first-approval tiers' drafts are counted too, whether or not
    # their tier is read yet: the count is of rows in work, not a rung.
    tier_rows = [r for key in _FIRST_APPROVAL_TIERS for r in spine.get(key, [])]
    drafted = sum(1 for r in rows + tier_rows if spine_rules.is_drafted(r)) + len(
        spine["sn_draft"]
    )
    phases = [spine_rules.phase_num(r) for r in rows if not spine_rules.is_drafted(r)]
    phases = [p for p in phases if p is not None]

    return {
        "stage": effective,
        "stage-ord": kitstage.order(effective),
        "stage-of": kitladder.STAGE_OF,
        "floored": floored,
        "settled-stage": settled_stage,
        "live-stage": live,
        "phase": max(phases) if phases else None,
        "per-phase": settled_per_phase,
        "per-phase-live": live_per_phase,
        "drafted": drafted,
    }


def read(root):
    """THE COMMON READER, wired. Every consumer that needs the current stage
    calls THIS — one line, so the deriver is named once in the kit rather than at
    each call site, and `kitlib.stage` stays free of the sibling import."""
    return kitstage.read_stage(root, derive)


# --- THE PHASE RULE (ruled plan §4 + owner answer §6.1/§6.2) ------------------
# EVERY ROW THIS RULE CAN ATTRIBUTE A DECREASE TO, as
# `(id-column, spine key, the cells the DERIVATION reads)`.
#
# WIDENED AT THE WI-498 CLOSE (ROUND-SOL-RAW 3), and the old shape is worth
# stating because it looked complete. This was three SR/LLR/TC entries compared
# on `Status` alone — so an edit that lowered the effective stage through any
# OTHER input produced `changed_rows=[]` and the rule went silent on a
# non-exempt decrease. Sol drove it: a settled DevStg-Impl spine with
# `CMP-001 Standing=""` changed only to `Standing="has-gap"` gave
# `was=DevStg-Impl`, `now=DevStg-Arch`, `changed_rows=[]`, `findings=[]` — a
# three-rung drop, undeclared and unreported. The kit's own Impl->Arch test did
# not catch it because that test moves the component AND adds an SR, and the SR
# is the only reason its finding exists.
#
# Two independent blind spots, both closed here: the frame REGISTRIES were not
# walked at all, and the cell set was `Status` only, while the derivation also
# reads a CMP's `Standing` (a lifecycle fact that holds rung 3 on its own), an
# SR's `SN-Refs` (the coverage rung) and `Verification` (the LLR exemption), and
# the child rows' parent refs (the decomposition rungs). A rule that reads a
# narrower input set than the derivation it polices can always be walked past.
#
# The BEFORE side already carried these rows — `_spine_at` materializes the
# whole declared input set at `rev` — so this is an attribution fix, not a new
# read.
#
# A TEST CASE'S `Assumption-Refs` IS ONE OF THOSE CELLS (SR-197): it places the
# case in the phases of the requirements citing its assumptions (`_phase_groups`),
# so a change to it is attributed like a change to `Verifies`.
# Implements: SR-197, LLR-230
_ATTRIBUTED_ROWS = (
    ("SR-ID", "srs", ("Status", "SN-Refs", "Verification")),
    ("LLR-ID", "llrs", ("Status", "SR-Refs")),
    ("TC-ID", "tcs", ("Status", "Verifies", "Assumption-Refs")),
    ("B-ID", "bifs", ("Status",)),
    ("CMP-ID", "cmps", ("Status", "Standing")),
)

# The two of those that carry no `Phase` cell. The boundary and partition rungs
# are REPO-GLOBAL — which is precisely how they drop every phase at once — so a
# decrease attributed to one of them cannot be answered by tagging a phase, and
# its finding says so rather than asking for something the row cannot carry.
_PHASELESS_KEYS = frozenset({"bifs", "cmps"})

# THE EXEMPTION, and it is exactly one permutation (owner answer §6.2): a
# decrease landing precisely on DevStg-LLReqs -> DevStg-Arch is the PERMITTED
# DECOMPOSITION CYCLE — architecture rework surfaced by breaking a requirement
# down is within-phase churn, and any deeply decomposed problem would otherwise
# run the phase counter up. The owner declined a wider Arch-tier exemption, so
# this is a pair, not a predicate over the Arch rung: a two-rung drop that
# happens to END at Arch is NOT exempt, and neither is Arch -> anything.
_EXEMPT_DECREASE = (kitladder.STAGE_LLREQS, kitladder.STAGE_ARCH)


def _spine_at(root, rev):
    """`load_spine` over the DECLARED INPUTS as they stood at `rev`, or None when
    git cannot answer — the kit's silent-no-op degrade, not an error.

    THE INPUTS ARE MATERIALIZED INTO A TEMP TREE AND THE LIVE LOADER IS RUN OVER
    IT, rather than parsing each `git show` into rows here. Three things come
    free that a re-implementation would have to get right and could drift on:
    carrier resolution (`.toml` before `.csv`, and `.md` for needs), the `-000`
    example filter, and — the one that actually bites — the `have_bifs`/
    `have_cmps` applies-when, where an ABSENT registry and an EMPTY one mean
    opposite things at the two inserted rungs. Materializing only the files that
    existed at `rev` preserves absence as a value.

    THE WHOLE FRAME IS READ AT `rev`, NOT HELD AT THE LIVE TREE. Holding it
    constant was tried first and is wrong: the ruled exemption is
    `DevStg-LLReqs -> DevStg-Arch`, and the Arch rung is derived from the
    COMPONENT registry, so a frame pinned to the live tree makes the owner's one
    permitted decrease unreachable — the rule would be unable to see the very
    transition it is required to forgive."""
    if _git(root, ["rev-parse", "--verify", "--quiet", rev]) is None:
        return None  # no git, or no such revision: nothing to compare against
    with tempfile.TemporaryDirectory() as tmp:
        found = False
        for declared, suffixes in kitstage.DECLARED_INPUTS:
            for suffix in suffixes:
                text = _git(root, ["show", "{}:{}{}".format(rev, declared, suffix)])
                if text is None:
                    continue
                dest = Path(tmp) / (declared + suffix)
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_text(text, encoding="utf-8", newline="\n")
                found = True
                break
        if not found:
            return None
        return spine_rules.load_spine(Path(tmp) / "docs")


def _by_id(spine):
    """`{spine-key: {id: row}}` — the before-side lookup `_changed_rows` joins on."""
    return {
        key: {r[id_col]: r for r in spine.get(key, []) if r.get(id_col)}
        for id_col, key, _cells in _ATTRIBUTED_ROWS
    }


def _effective(spine):
    """The headline value for a spine dict — the settled, per-phase, floored fold,
    i.e. exactly what `derive()` puts in the `stage` field.

    THE TEST-EVIDENCE VERDICT IS DELIBERATELY LEFT AT ITS DEFAULT (False) HERE,
    on BOTH sides of the phase rule's before/after comparison (WI-500). The rule
    polices SPINE AUTHORING — an edit that lowers the reading must surface as a
    phase change — and evidence is not an authored row: a suite that went red, or
    a record that went stale, would otherwise read as an un-phased authoring
    decrease and demand a phase tag nobody can supply. Symmetric omission keeps
    the comparison about the rows, which is what the rule is for."""
    _live, settled_per_phase = _stage_map(spine, settled=True)
    return kitstage.effective_stage(settled_per_phase)[0]


def _changed_rows(live, before_rows):
    """Every row this edit ADDED, or whose STAGE-AFFECTING CELLS it moved, as
    `[(id, key, row, before-status-or-None)]` over `_ATTRIBUTED_ROWS`.

    THE TRIGGER SET IS WIDER THAN THE PLAN'S WORDS, and the measurement is why.
    Plan §4 says "a newly drafted/redrafted row"; driven on a frame-free spine
    (slice 3), a newly DRAFTED row cannot decrease the effective stage AT ALL —
    slice 1 excludes drafts from the settled fold, so that half of the phrase is
    inert by construction. What actually decreases it is a redrafted child
    (Impl -> LLReqs for an LLR, Impl -> Tests for a TC) and a newly APPROVED
    parent with no children yet (Impl -> LLReqs). Narrowing to the literal words
    would have shipped a rule that cannot fire on the two shapes that matter, so
    the trigger is "added, or a stage-affecting cell moved" — which CONTAINS the
    plan's set.

    IT IS THE DERIVATION'S CELLS, not `Status` alone — see `_ATTRIBUTED_ROWS`
    for what was walked past while this compared one cell in three registries."""
    out = []
    for id_col, key, cells in _ATTRIBUTED_ROWS:
        prior = before_rows.get(key, {})
        for row in live.get(key, []):
            rid = row.get(id_col)
            if not rid:
                continue
            was = prior.get(rid)
            if was is None:
                out.append((rid, key, row, None))
                continue
            moved = [
                "{} {} -> {}".format(
                    c,
                    (was.get(c) or "").strip() or "(blank)",
                    (row.get(c) or "").strip() or "(blank)",
                )
                for c in cells
                if (was.get(c) or "").strip().lower()
                != (row.get(c) or "").strip().lower()
            ]
            if moved:
                out.append((rid, key, row, "; ".join(moved)))
    return out


def phase_rule_findings(root):
    """The authoring-time decrease rule (plan §4, owner answer §6.1).

    **An edit that LOWERS the effective stage must surface as a phase change.**
    When the effective stage decreased, every row this edit added or moved a
    stage-affecting cell on must carry a `Phase` tag that is NOT the phase the
    settled work was standing in — a NEW (higher) phase, or an already-open
    LOWER one. Both readings of "the scope moved" satisfy it; quietly adding
    regressing work to the phase you are standing in does not.

    THE ATTRIBUTED SET IS EVERY STAGE-AFFECTING INPUT, not the spine tiers
    alone (`_ATTRIBUTED_ROWS`, widened at the WI-498 close). A frame row has no
    phase to tag, so its finding reports the decrease and names the cause
    instead of demanding a cell the row cannot carry.

    WHY THIS SHAPE AND NOT A STORED COUNTER (plan §4, alternative (ii) rejected):
    phase stays a pure function of the registries. The derived `phase=` still
    increments BECAUSE the rows say so, so there is no second phase concept to
    drift against the row tags, and `docs/stage` records the derived value
    exactly as `docs/gate` did.

    WARN TIER, AND THE ARMING PATH IS THE POINT. This returns findings; `main`
    prints them and exits 0 unless `--strict`. New rules arm warn-first here
    unless a ruling says otherwise, and OI-51's ruling establishes that the rule
    EXISTS, not that it hard-fails on day one. It promotes by being wired into
    `check.py`'s `--strict` trio at a threshold — deliberately NOT done in this
    slice, because a rule whose fire has never been observed on real authoring
    should not be able to block a commit. The promotion is one call-site edit:
    the predicate and its vocabulary do not change (`trace.schema_advisories`'s
    warn-first twin idiom).

    DEGRADES SILENTLY WITHOUT GIT, like every other two-tree rule in the kit: no
    HEAD means no before-state, and a rule that cannot see the past has nothing
    to say rather than something to complain about.

    Implements: SR-181

    RE-POINTED AT WI-501 (OI-53 (b), 2026-08-22). This carried
    `Implements: SR-139` until the WI-498 close, which was a mis-trace: SR-139
    is "Approval as an ordinal over a derived spine stage" — it governs the
    `human_approval_through` dial — while this rule's obligation is "a
    spine edit that LOWERS the effective stage must surface as a phase change"
    (ruled plan §4, owner answer §6.1). Unrelated obligations at different
    tiers, so `backlink-coverage` was crediting a requirement about
    approval authority with a realization edge from a function that does
    not realize it — inflating its coverage with a false edge while leaving
    this rule rowless (ROUND-OPUS 12). WI-501 removed the false edge and
    minted SR-181, which states this obligation directly; the declaration
    above now points at the row that actually owns it."""
    root = Path(root)
    live = spine_rules.load_spine(root / "docs")
    before = _spine_at(root, "HEAD")
    if before is None:
        return []
    before_rows = _by_id(before)

    was, now = _effective(before), _effective(live)
    if kitstage.order(now) >= kitstage.order(was):
        return []
    if (was, now) == _EXEMPT_DECREASE:
        return []

    # The phase the SETTLED work was standing in, on the BEFORE side — the value
    # a new tag has to differ from. Max over non-Drafted rows, which is `phase=`
    # itself, so the rule and the recorded field can never mean different things.
    prior_phases = [
        spine_rules.phase_num(r)
        for key in ("srs", "llrs", "tcs")
        for r in before.get(key, [])
        if not spine_rules.is_drafted(r)
    ]
    prior_phases = [p for p in prior_phases if p is not None]
    standing = max(prior_phases) if prior_phases else None

    findings = []
    for rid, key, row, changed in sorted(
        _changed_rows(live, before_rows), key=lambda t: (t[0], t[1])
    ):
        moved = (
            "The row is new."
            if changed is None
            else "Its {} moved ({}).".format(
                "cells" if ";" in changed else "cell", changed
            )
        )
        if key in _PHASELESS_KEYS:
            # A FRAME row. The boundary and partition rungs are repo-global, so
            # there is no phase to tag and no per-phase remedy to offer: the
            # finding reports the decrease and names its cause. This arm is the
            # one that was missing entirely — the registries were not walked.
            findings.append(
                "{} lowers the effective stage ({} -> {}). {} It is a FRAME row, "
                "so it carries no phase and the decrease cannot be answered by "
                "tagging one: the boundary and partition rungs are repo-global "
                "and drop every phase at once. A stage decrease is a scope "
                "change and must surface as one — record it, or restore the "
                "row.".format(rid, was, now, moved)
            )
            continue
        phase = spine_rules.phase_num(row)
        if standing is None or phase != standing:
            continue
        findings.append(
            "{} lowers the effective stage ({} -> {}) and carries no new phase: "
            "it is tagged phase {}, the phase the settled spine was already "
            "standing in. {} A stage decrease is a scope change and must surface "
            "as one — tag the row into a new phase ({}) or into an already-open "
            "lower phase.".format(
                rid,
                was,
                now,
                phase,
                moved,
                standing + 1,
            )
        )
    return findings


# Implements: SR-049, LLR-148
def main():
    kitconfig.utf8_console()
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("--root", default=".", help="repo root (default: .)")
    ap.add_argument(
        "--check",
        action="store_true",
        help="recompute and compare to the cached docs/stage; exit 1 on drift",
    )
    ap.add_argument(
        "--print",
        dest="print_only",
        action="store_true",
        help="compute and print the derived record; do not write docs/stage",
    )
    ap.add_argument(
        "--next-phase",
        dest="next_phase",
        action="store_true",
        help="print the next delivery phase number — max(Phase over non-draft "
        "spine rows) + 1, i.e. the record's phase=N plus one; an unphased spine "
        "is the implicit foundation (1), so it prints 2. Output mode only: "
        "docs/stage is not written",
    )
    ap.add_argument(
        "--phase-rule",
        action="store_true",
        help="check the authoring-time stage-decrease rule against HEAD (warn-first)",
    )
    ap.add_argument(
        "--strict",
        action="store_true",
        help="with --phase-rule: exit 1 on a finding instead of warning",
    )
    args = ap.parse_args()
    root = Path(args.root)

    if args.next_phase:
        # The one derived answer to "a confirmed scope change opens a new phase —
        # what number does it take?" (owner ruling 2026-08-01, WI-402: a phase
        # increments on an adjudication-confirmed scope change or an approved
        # draft-SN batch, NEVER on a raw derived-value drop — a spurious window
        # must not burn a phase number). Printed bare so the intake mint helper
        # (WI-388) can int() the output. A Drafted row's phase is not yet scope,
        # so it never bumps the answer.
        #
        # REHOMED FROM `derive_gate.py` AT WI-498 slice 5, when that module's CLI
        # retired with `docs/gate`. It lands HERE rather than anywhere else
        # because this module already derives `phase` from exactly the same rows
        # by the same rule — so the printed number and the recorded `phase =`
        # field cannot come to mean different things, which is the whole reason
        # the old one reused the basis line instead of parsing again.
        cur = derive(root)["phase"]
        print((cur if cur is not None else 1) + 1)
        return 0

    if args.phase_rule:
        findings = phase_rule_findings(root)
        for f in findings:
            print("{} - {}".format("FAIL" if args.strict else "WARN", f))
        if not findings:
            print("derive_stage: phase rule clean (no un-phased stage decrease).")
        return 1 if (findings and args.strict) else 0

    record = derive(root)
    record["fingerprint"] = kitstage.fingerprint(root)
    block = kitstage.field_block(record)

    if args.print_only:
        print(block)
        return 0

    path = root / STAGE_FILE
    if args.check:
        # THE FINGERPRINT IS NOT ENOUGH ON ITS OWN, and this is why `--check`
        # recomputes rather than comparing digests: a change to the DERIVATION
        # moves the recorded values while every input byte stays put. The
        # fingerprint answers "do the inputs still match", the recompute answers
        # "does the whole record still hold", and only the second is a freshness
        # guard. The same asymmetry `spine_rules --check` has always had.
        if not path.exists():
            print(
                "derive_stage: {} is absent — run `python scripts/derive_stage.py` "
                "to generate it".format(STAGE_FILE),
                file=sys.stderr,
            )
            return 1
        cached = kitstage.parse(path.read_text(encoding="utf-8", errors="replace"))
        if cached is None:
            # THE SCAFFOLD / MIGRATION FORM, and it PASSES — the same
            # smooth-transition path `spine_rules --check` gives a legacy
            # hand-set marker. A file with no stage field has never been
            # derived: it is `stage.template` as `bootstrap.py` copied it, or an
            # adopter's tree between the resync and the first regeneration.
            # There is nothing to compare it against and nothing it can be
            # stale relative to, so failing here would red every freshly
            # scaffolded repo — the shipped promise is that such a repo is
            # green. It is a NOTE, not a silent pass: the message names the one
            # command that ends the state, and `trunk_step --regen` runs it
            # unprompted at the next trunk regeneration point.
            print(
                "derive_stage: {} is not yet in derived form — run "
                "`python scripts/derive_stage.py` once to generate it.".format(
                    STAGE_FILE
                ),
                file=sys.stderr,
            )
            return 0
        cached_block = kitstage.field_block(cached)
        if cached_block == block:
            print(
                "derive_stage: {} up to date ({}).".format(STAGE_FILE, record["stage"])
            )
            return 0
        # THE CAUSE IS BRANCHED, because one message was false in the case the
        # design calls NORMAL (ROUND-OPUS 14). An input edit that moves no rung
        # still reds `--check` — correctly, and the fragment banks that as the
        # intended direction — but the message said "the derived stage moved"
        # precisely when it had not, and the `cached:`/`now:` blocks printed
        # underneath REFUTE it: every derived value byte-identical, only the
        # fingerprint differing. A reader comparing the two blocks (which are
        # printed side by side to be compared) concludes the check is lying.
        only_fingerprint = [
            key
            for key in set(cached) | set(record)
            if key != "fingerprint" and cached.get(key) != record.get(key)
        ] == []
        cause = (
            "the derivation INPUTS changed, so the recorded fingerprint has "
            "become a false claim — every derived value below is unchanged"
            if only_fingerprint
            else "the derived stage moved but the cache did not"
        )
        print(
            "derive_stage: {} STALE — {}.\n  cached:\n{}\n  now:\n{}\n"
            "  run `python scripts/derive_stage.py` and commit the result.".format(
                STAGE_FILE, cause, cached_block, block
            ),
            file=sys.stderr,
        )
        return 1

    as_of = _git(root, ["rev-parse", "--short", "HEAD"]) or "no-git"
    date = (
        _git(root, ["log", "-1", "--format=%cs"]) or datetime.date.today().isoformat()
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        kitstage.render(record, as_of, date), encoding="utf-8", newline="\n"
    )
    print("derive_stage: wrote {} -> {}.".format(STAGE_FILE, record["stage"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
