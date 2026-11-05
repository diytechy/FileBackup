#!/usr/bin/env python3
"""THE SPINE RULES: what a registry row means, and which stage rung a row set
stands at. A pure library — it derives, it never writes.

WHAT THIS MODULE IS, AND WHY IT IS NAMED THIS (WI-498 slice 5). It was
`derive_gate.py`, and it derived a three-value BAR that it cached to `docs/gate`.
That axis is gone: the ruled stage unification (OI-51) made the eight-rung ladder
the one answer to "where is this repo", so the bar, its ordinals, its
per-artifact rules, the cache it was written to and this module's whole CLI were
DELETED — 1,523 lines to 807. What survived is the half every caller actually
wanted: the row predicates, the maturity tables, and the rung fall-through.

The old name was defended in this very docstring — "the FILE keeps its name;
`docs/gate` and `derive_gate.py` are paths adopters invoke literally" — and that
argument expired with the file. A module named for a value it no longer derives,
shipped beside a path that no longer exists, is the accreted dishonesty this
program exists to remove. `spine_rules` pairs with `spine_carrier`: the carrier
LOADS registry rows, these rules JUDGE them.

THE LAYERING, top to bottom:

  * `kitlib/ladder.py`  the eight rung labels and their order. Imports nothing.
  * `kitlib/spine.py`   the ROW vocabulary: the Status predicates, the
                        LLR-exemption set, the phase parse and the SN id scrapes.
  * `spine_rules.py`    (here) the predicates over rows, and `spine_stage` — the
                        fall-through that decides which rung a row set stands at.
  * `derive_stage.py`   the per-phase fold, the record, the file, the CLI.
  * `kitlib/stage.py`   the `docs/stage` format, the input fingerprint, and THE
                        COMMON READER every consumer of the stage calls.

WHO CALLS IT: `derive_stage` (for `load_spine` + `spine_stage`) and
`baseline_snapshot` (for the maturity vocabulary). Nothing else imports it, and
nothing runs it — there is no `main()`.

THE RUNG FALL-THROUGH, in one sentence each. `spine_stage` returns the LOWEST
rung anything still holds open, so the answer is "what is in work":

  0 `DevStg-Needs`      a Drafted need, an approved need no SR answers, or a
                        Drafted stakeholder once one stakeholder is approved.
  1 `DevStg-Boundary`   a declared external frame with an unsettled crossing,
                        or a Drafted assumption or surrogate once one row of
                        that tier is approved (`tier_active`).
  2 `DevStg-Reqs`       a Drafted SR.
  3 `DevStg-Arch`       a declared partition with an unsettled component.
  4 `DevStg-LLReqs`     an SR with no LLR (unless its Verification is
                        LLR-exempt: Analysis / Inspection / Attest).
  5 `DevStg-Tests`      an SR with no TC, or a Drafted LLR/TC.
  6 `DevStg-Impl`       everything above is settled. THE FALL-THROUGH LANDS HERE.
  7 `DevStg-Release`    RETURNED BY NO CELL, EVER. Leaving Impl means the
                        declared tests PASS, so the rung's one input is the
                        `evidence_passed` verdict over the harness-written
                        `docs/test/evidence` record (WI-500) — a value bound to
                        the tree it was measured on, never an approximation.

The two INSERTED frame rungs (1 and 3) read REPO-WIDE registries even when this
is called with one phase's rows, so a per-phase caller must treat them as
unattributable — `kitlib.stage.REPO_GLOBAL_RUNGS` declares the set and
`check_trajectory`'s phase-drop detector abstains on it.

Rungs 2 and 3 RECURSE as the decomposition descends; rung 4 is TERMINAL by
OI-20's binding rule. Requirements come before architecture because architecture
is a RESPONSE to requirements (process.md §4).

HOW THIS COMPOSES WITH `trace.py`. Trace ENFORCES structure — orphans,
decomposition, approval — at the selected stage; these rules DERIVE the stage
from the same rows. A Drafted row is exempt from trace's orphan rule (so it can
live in the live spine) yet holds its rung open here (so it is visible as work in
progress). Auditing correctness is the whole point, so every rule is
fixture-tested (`tests/test_spine_rules.py`).

Stack-agnostic, standard-library only. The row vocabulary this module used to
duplicate from `trace.py` under the retired F5 rule now has ONE home,
`kitlib.spine`, and is re-exported below (WI-448 slice 3) — this still never
imports the joined-spine engine.
"""

import sys
from pathlib import Path

# Sibling: the spine's registry CARRIER — the one home for
# the TOML tier tables, the key->column vocabulary and both readers. Run as a
# subprocess this script's own dir is sys.path[0] so a plain import resolves;
# the guard covers an in-process import (a test) whose sys.path does not yet
# carry scripts/ — the sanctioned-sibling idiom trace.py uses for trace_text.
try:
    import spine_carrier
except ImportError:  # pragma: no cover - in-process fallback
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import spine_carrier

# THE SHIPPED SHARED-HELPER PACKAGE (owner ruling D-8, `OI-16`): `kitlib.ladder`
# is the ONE home for the eight-rung stage vocabulary this module used to define
# (WI-498 slice 0), and `kitlib.spine` is the ONE home for the ROW vocabulary it
# used to duplicate against trace.py (WI-448 slice 3). Same guarded idiom as the
# sibling import above.
try:
    from kitlib import ladder as _ladder
    from kitlib import spine as _spine
except ImportError:  # pragma: no cover - in-process fallback
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from kitlib import ladder as _ladder
    from kitlib import spine as _spine

# --- THE ROW VOCABULARY, RE-EXPORTED FROM ITS ONE HOME (WI-448 slice 3) --------
# These nine names were DUPLICATED between this module and trace.py under the
# retired F5 rule and held equal by nine `tests/test_rule_sync.py` pins. They are
# POLICY — what a Status word means, which Verification methods decompose to a TC
# but no LLR, what a Phase cell parses to, which SN ids exist and which are cited
# — and a policy disagreement between the module that ENFORCES the spine and the
# module that DERIVES its stage is a false green or false red AT A GATE (WI-099).
# D-8 replaced the pins with one home: `kitlib/spine.py`. The names are
# RE-EXPORTED here, exactly as the ladder's were at WI-498 slice 0, because
# `spine_rules.is_approved` is the spelling `derive_stage` and the test suite
# already read, and re-pointing every citation is churn this slice does not need.
# The rules' own rationale travelled with them and is NOT restated here.
#
# `LLR_EXEMPT` WAS A `set` HERE AND A `tuple` IN trace.py — behaviour-equal under
# `in`, so the value pin was blind to it. The one home is a `frozenset`; see its
# comment there for why immutability is the right answer for a shared kernel's
# closed vocabulary.
LLR_EXEMPT = _spine.LLR_EXEMPT
load_csv = _spine.load_csv
refs = _spine.refs
is_example = _spine.is_example
is_drafted = _spine.is_drafted
is_approved = _spine.is_approved
is_founded = _spine.is_founded
llr_exempt = _spine.llr_exempt
phase_num = _spine.phase_num
sn_all_ids = _spine.sn_all_ids
sn_cited_ids = _spine.sn_cited_ids

# THE TENTH DUPLICATE, RETIRED THE OTHER WAY. `sn_draft_ids` was a one-line
# delegation to `spine_carrier.draft_ids_from_text` in BOTH modules, and it is
# the one member of the pair that cannot move into `kitlib`: the package's single
# asserted rule is that it imports no sibling of `scripts/`, and a `kitlib`
# module reaching for `spine_carrier` would smuggle the whole script graph into
# the scaffolder (`tests/test_bootstrap.py`). So the copy is deleted rather than
# relocated — both modules now BIND the sibling function directly under the same
# local name, which is what the two wrapper bodies were worth.
#
# What the wrapper's docstring carried is the carrier's own claim and lives on
# `spine_carrier.draft_ids_from_text`: under TOML draft-ness is a FIELD, under
# legacy markdown it was SECTION-AS-STATE, and the dispatch between them is
# load-bearing rather than tidy — a heading scan over a TOML file finds no
# headings, reports zero drafts, and floats the derived stage upward.
sn_draft_ids = spine_carrier.draft_ids_from_text

# `is_founded` and `is_approved` have HAD NO CALLER IN THIS MODULE since WI-498
# slice 3 — the Impl->Release discriminator was the last one, and it retired when
# Release stopped being derivable from a cell. They stay re-exported because they
# are SHARED VOCABULARY this module's readers spell `spine_rules.is_approved`,
# not private helpers of a rung. Under the pins that was an argument that had to
# be made; now it is just what a re-export is for.
# `is_approved` has a caller here again since `tier_active` (SR-204): the first
# APPROVED row is what switches a first-approval tier on.


# `is_planned` WAS DELETED AT D-9 STEP 5 (not re-keyed) with the word it read:
# OI-30 D1 folded `Planned` into `Approved`, so `is_approved` answers for those
# rows and the `planned=` basis counter goes with the predicate. It was step-2
# insurance against a value no predicate recognized, and its own docstring said
# it would be deleted here rather than migrated.
#
# `is_modified` WAS DELETED AT D-9 STEP 7 on the same terms, as its own docstring
# promised. It marked "approved text that has since moved" and survived step 5
# only so the kit never had a commit with NO drift detector; its successor (the
# `docs/archive/last_approved/` comparison) ran alongside it through the signing.
# `modified=N` went with it, for `planned=`'s reason: a count of a value the
# closed enum cannot hold counts integrity errors, not pending rows.


# --- SN-029 / OI-21: THE EIGHT-RUNG STAGE LADDER, the one derived axis --------
# IT WAS THE SECOND OF TWO until WI-498 slice 5, and the history is worth one
# paragraph because the same mistake was made three times. A separate BAR axis
# answered "how strict is the harness right now" while this one answered "how far
# has the decomposition got", and before that a single G-numbering tried to carry
# both and could express neither: its middle tag meant "LLRs and TCs exist" AND
# doubled as the pull an amended row applied, so no tag meant "TCs are in
# process". Forcing one token to carry two questions is how a dial comes to mean
# something subtly different at each of its reading sites; splitting the token
# without splitting the question just moves the ambiguity.
#
# THE RULED MODEL (owner 2026-08-12, re-ruled 2026-08-13 as OI-21, unified at
# OI-51): **stages are the rungs of the decomposition, and a repo is IN exactly
# one.** Certification is an EVENT at a rung boundary — a named human's reviewed
# Status-change commit — recorded where events are, not as a rival value. The
# stage is state; approval is what moves it.
#
# THE VOCABULARY ITSELF MOVED OUT (WI-498 slice 0, plan §5 item 0). The rung
# strings, their order, `STAGE_OF`, `STAGE_DESC` and the `stage_ord` lookup are
# `kitlib.ladder`'s — one home, imported by everyone, so the equality pins that
# used to hold `agent_common`'s restatement in step retire: the drift is now
# UNREPRESENTABLE rather than DETECTED (the WI-448 declared-line precedent,
# `tests/test_rule_sync.py`). The names are RE-EXPORTED below because
# `spine_rules.STAGE_*` is the spelling six modules and the test suite already
# read, and re-pointing every citation is churn this slice does not need.
# The ladder's own design rationale — why requirements precede architecture, why
# the label and not the ordinal is the identifier, why it is not monotonic —
# travelled with it and is NOT restated here.
STAGE_NEEDS = _ladder.STAGE_NEEDS
STAGE_BOUNDARY = _ladder.STAGE_BOUNDARY
STAGE_REQS = _ladder.STAGE_REQS
STAGE_ARCH = _ladder.STAGE_ARCH
STAGE_LLREQS = _ladder.STAGE_LLREQS
STAGE_TESTS = _ladder.STAGE_TESTS
STAGE_IMPL = _ladder.STAGE_IMPL
STAGE_RELEASE = _ladder.STAGE_RELEASE
STAGE_ORDER = _ladder.STAGE_ORDER
STAGE_OF = _ladder.STAGE_OF
STAGE_DESC = _ladder.STAGE_DESC
stage_ord = _ladder.stage_ord


# --- THE MATURITY MAPPING TABLE — ONE HOME (OI-21 question 5b) -----------------
# THE PROBLEM IT SOLVES. The min-fold folded over SN/SR/LLR/TC only, which is why
# rung 1 (Boundary) had no machine-readable state and rung 3's `CMP.State` was
# read by nothing that gates. Folding IF and CMP in is what makes the recursion
# self-reporting — but those two registries carry their OWN maturity vocabularies,
# and the spine carries a third — which, since D-9 migration steps 5/7/8, is
# `Drafted`/`Approved`/`Founded` and therefore SPEAKS THIS TABLE'S OWN WORDS.
#
# So every vocabulary maps onto ONE set of ladder semantics, stated here and
# nowhere else:
#
#   DRAFTED   the row exists but is not settled — it CAPS its rung (work in flight)
#   APPROVED  the row is settled at its tier — it does not cap
#   FOUNDED   the row is settled AND demonstrated — it does not cap
#
# The migration promised this would be a TABLE EDIT rather than a predicate
# rewrite, and step 5 is that edit landing: `SPINE_MATURITY` below is the spine's
# row of this one table, and it is DECLARED rather than inferred — the previous
# revision had every other tier in the table and the spine only in prose.
DRAFTED, APPROVED, FOUNDED = "Drafted", "Approved", "Founded"

# THE SPINE (SR/LLR/TC `Status`) — the row D-9 step 5 added. Keys lower-cased,
# like every other table here (`_maturity` lowercases before the lookup), so this
# is the closed `STATUS_VALUES` vocabulary spelled in the ladder's own terms.
#
# THE TRANSITIONAL `modified` ROW LEFT AT STEP 7, as this comment's previous
# revision said it would; the state it named is now read by comparing the row
# against its `docs/archive/last_approved/` copy, which is not a maturity.
# `founded` JOINED AT STEP 8 under the rule that governed the rename: it maps to
# FOUNDED, which does not cap, so a row at the top rung cannot read as work in
# flight and hold a rung open. Its demonstration is computed per tier (migration
# plan C4), never asserted by this table. `DevStg-Release` still does not follow
# from a `Founded` cell — that is the harness's answer, and OI-30 D2's ceiling is
# now enforced by the rung having NO PRODUCER at all (slice 3) rather than by a
# cap on a per-artifact bar rule.
SPINE_MATURITY = {
    "drafted": DRAFTED,
    "approved": APPROVED,
    "founded": FOUNDED,
}

# `SPINE_TRANSITIONAL` AND `SPINE_MATURITY_READ` ARE DELETED (WI-498 slice 5).
# They named the retired SPINE spellings — `modified`, `implemented`, `verified`,
# `planned` (all read as APPROVED) and `draft` (read as DRAFTED) — and existed so
# `maturity_bar` could tell a mid-migration registry from a typo. `maturity_bar`
# was the ONLY reader of the composed table, and it retired with the bar axis, so
# what was left was a lookup nothing looked up.
#
# WHAT THAT CHANGES, STATED RATHER THAN ASSUMED: the spine tiers are read by
# `is_drafted`/`is_approved`, which compare the cell against the LIVE words. An
# unmigrated `modified` or `implemented` cell is therefore "not drafted" and does
# not hold its rung open — the same answer the deleted table gave it. Only
# `draft` changes hands: it used to CAP, and now reads as settled. That is a real
# tolerance lost, and it is recorded here rather than left for a reader to
# discover, because the closed-enum integrity rule (`trace.py --strict-schema`)
# is what names such a cell now, and it names it LOUDLY instead of quietly
# absorbing it. The off-spine tables below keep their own transitional readings;
# only the spine's went.

# BOUNDARY CROSSINGS — the depth-0 frame's `[boundary.B-##]` rows in
# `external.toml` (rung 1). `Status` is the tier's ONE maturity field — the name
# it carries since the 2026-08-17 registry status unification, which retired the
# transitional `Approval` spelling this table was first keyed on.
#
# THIS TABLE REPLACED AN `IF_MATURITY` KEYED ON `Stability` AT WI-442, and the
# swap is the whole reason that commit could not be split. `Stability` was the
# sole input to `boundary_incomplete`; deleting the column without re-keying the
# predicate in the same commit would have left every IF row reading an
# unrecognized value, which `_maturity` maps to DRAFTED — rung 1 pinned open
# forever by a column that no longer exists, reporting the right stage for
# entirely the wrong reason.
#
# NOT Founded on `approved`, for the reason the old table gave and which
# survives the re-key unchanged: an approval says the crossing is agreed, it says
# nothing about the crossing having been demonstrated.
# `drafted` (not `draft`) since D-9 step 5b: the off-spine approval vocabulary
# moved with the spine's so ONE word means one thing across every registry —
# `interfaces.toml` and `external.toml` cells, both file headers, and the two
# shipped templates changed in the same commit.
BIF_MATURITY = {
    "drafted": DRAFTED,
    "approved": APPROVED,
}

# CMP rows — the partition (rung 3).
# CMP now speaks the ONE enum (registry status unification, 2026-08-17), and
# that collapses this table to the identity over it. What it used to hold was
# two axes at once: `planned`/`built`/`verified` were maturity spelled in
# regenerated retired spine words, while `has-gap`/`deprecated` were LIFECYCLE
# facts folded onto maturity — exactly the conflation SN's `kind` was. The
# lifecycle half moved to its own `standing` field, which this table does not
# map because it is not a maturity — but ONE of its values still answers a
# rung-3 question, and `CMP_STANDING_CLEARS` below is where it answers it.
#
# CMP KEEPS ITS OWN TABLE rather than sharing `SPINE_MATURITY`, RE-EXAMINED at
# D-9 step 8 rather than inherited: the two are byte-identical as of that step,
# so collapsing them is the obvious move. Declined on the unification plan's own
# §7(c) recommendation — two registries' vocabularies that HAPPEN to coincide,
# not one with two names. They have already diverged in both directions (CMP
# reached `founded` first; the spine carried `modified` and CMP never did), and
# one shared table would make the next per-registry subset (which decision 12
# provides for) a change to the OTHER registry's ladder.
#
# `founded` is REACHABLE HERE and nowhere else off-spine: a demonstrated
# partition is a claim something computes, which is the whole test for whether a
# tier may carry the word.
CMP_MATURITY = {
    # (Keys lower-cased — see `_maturity`.)
    "drafted": DRAFTED,
    "approved": APPROVED,
    "founded": FOUNDED,
}

# CMP `standing` — the LIFECYCLE axis, and the one value on it that rung 3 must
# still read. Restores, on its new home, the protection the pre-split
# `CMP_MATURITY` entry stated verbatim and `6f39b2ed` deleted without citing:
#
#   `has-gap` is an explicit statement that the partition does NOT yet hold —
#   the strongest possible DRAFTED signal, and the one place a lenient mapping
#   would let a known-broken partition report a finished architecture rung.
#
# The split was right — `has-gap` is not a maturity — but it is a direct
# statement ABOUT the partition, which is exactly what rung 3 asks, so it has to
# be read SOMEWHERE. Without this, `Status = "Founded"` + `standing = "has-gap"`
# (a demonstrated partition that also records a gap: precisely the combination
# the new axis was created to make expressible) closes rung 3 (2026-08-17 desk
# round, F1). `deprecated` does NOT hold the rung — a decided state, not work in
# flight, which is the reading the pre-split table also gave it (APPROVED).
#
# Stated as what CLEARS rather than what holds, so the fail-honest direction is
# the default: an unreadable standing holds the rung open, the same choice
# `_maturity` makes and for the same reason (the tier's schema is ADVISORY, so a
# typo really can arrive here). An ABSENT cell is not unreadable — `omit =
# active` is the declared shorthand — so it clears.
CMP_STANDING_CLEARS = frozenset({"active", "deprecated"})

# THE THREE TIERS READ FROM THEIR FIRST APPROVAL (SR-204): the domain
# assumptions and the surrogates in `assumptions.toml`, read at the boundary
# rung, and the stakeholders in the needs file, read at the needs rung. Each is
# its own table rather than a share of `SPINE_MATURITY`, for `CMP_MATURITY`'s
# reason: three registries whose vocabularies coincide today, not one with
# three names. They speak the spine's closed `Status` words, which the checker
# enforces on each (`ENUM_FIELDS["STK"]`, and `assumption_rules` for the two
# tiers of the assumptions registry).
# Implements: SR-204, LLR-241
DA_MATURITY = {
    "drafted": DRAFTED,
    "approved": APPROVED,
    "founded": FOUNDED,
}
# Implements: SR-204, LLR-241
SUR_MATURITY = {
    "drafted": DRAFTED,
    "approved": APPROVED,
    "founded": FOUNDED,
}
# Implements: SR-204, LLR-241
STK_MATURITY = {
    "drafted": DRAFTED,
    "approved": APPROVED,
    "founded": FOUNDED,
}


def _standing_holds_rung(value):
    """Does this CMP `standing` cell hold the architecture rung open?

    Not a maturity lookup: `standing` answers a lifecycle question, and only its
    `has-gap` value (plus anything unreadable) bears on whether the partition
    holds. See `CMP_STANDING_CLEARS` for why the polarity is inverted."""
    text = str(value or "").strip().lower()
    if not text:
        return False
    return text not in CMP_STANDING_CLEARS


def _maturity(value, table, default=DRAFTED):
    """A registry cell's ladder semantic through `table`, matched case-insensitively.

    An UNRECOGNIZED value reads DRAFTED — the fail-honest direction — unless the
    caller overrides `default`. No caller does today (`maturity_bar`, the one
    that did, retired with the bar axis at slice 5); its reason is recorded
    here: the spine's `Status` is a closed INTEGRITY enum whose unknown values
    are already an always-on error, so holding the rung open for them would
    punish the same fault twice and would have made D-9's rename lower the
    derived stage. Every ADVISORY-schema tier keeps the fail-honest default. These two
    tiers are schema-ADVISORY (WI-443 ruled the enums warn-first, so a typo never
    fails the harness), which means an unknown value genuinely can reach here; the
    choice is between "an unreadable row reports finished" and "an unreadable row
    holds its rung open", and only the second is safe on an axis the automation
    dial reads.

    The case-insensitive match is real, not aspirational: the tables are keyed
    lower-cased below. It used to be a docstring claim only — every key happened
    to be spelled exactly as the registries spelled it, so the claim cost nothing
    and bought nothing. WHAT THE FOLD ACTUALLY BUYS, stated accurately after an
    adversarial round caught the first version overclaiming: it defends against a
    hand-authored `Approved`/`Drafted`, which no other check validates — the enums
    are schema-ADVISORY, so a capitalized cell reaches here and would otherwise
    read DRAFTED. It does NOT fix any live or shipped value; every one of those
    already matched exactly."""
    return table.get((value or "").strip().lower(), default)


def _caps(semantic):
    """True when a ladder semantic means work is still in flight at its rung."""
    return semantic == DRAFTED


def _decomposed_sr_ids(llrs, tcs):
    """`(SR ids some LLR answers, SR ids some TC verifies)` — the decomposition
    index both the stage axis and the gate arithmetic ask for.

    One home because two copies of a join rule is exactly how the two axes would
    drift apart while still agreeing on the day they were written (WI-347: the
    cross-SCRIPT duplication F5 sanctions never licensed intra-file copies)."""
    return (
        {x for r in llrs for x in refs(r.get("SR-Refs"))},
        {x for r in tcs for x in refs(r.get("Verifies"))},
    )


def _frame_rows(docs, filename, id_key):
    """`(real_rows, applies)` for one off-spine frame registry.

    `applies` is the rungs' APPLIES-WHEN, and it answers "has this project
    ADOPTED this tier?" rather than the narrower "does the file exist?" — which
    is the correction WI-498's close made (ROUND-SOL-RAW 2). Three states, and
    the middle one is the whole point:

      * **no file** — not adopted. `applies` False, the rung is skipped, and a
        project that never declares a boundary is not held at DevStg-Boundary
        forever. Unchanged.
      * **the file as `bootstrap.py` SHIPS IT — `-000` example rows and nothing
        else** — not adopted either, and this is the state that was being read
        as "adopted but empty". `trace.py` ignores every id ending `-000` and
        BOTH shipped templates promise in their own prose that the example rows
        are "inert until deleted" / "never blocks a gate". They were not inert:
        the placeholder rows filter out, the row list comes back empty, and an
        empty-but-present registry caps the rung. Because both rungs are
        repo-global and sit BELOW every spine rung, that pinned EVERY adopting
        repo at DevStg-Boundary permanently — measured on a real bootstrap: a
        spine with every SN/SR/LLR/TC row `Founded` still read
        `settled-stage = DevStg-Boundary`, so `format`, `lint` and
        `tests+coverage` could never be selected from the derived value. The
        kit's own acceptance tests only ever saw the rungs work because their
        `_no_frame` helper DELETES both files first, and that helper's docstring
        had recorded the symptom without it being read as a defect.
      * **a file with rows of its own** (or one an adopter deliberately
        EMPTIED, having deleted the examples) — adopted. `applies` True and the
        rung reads it, including the honest "declared no crossing yet" cap.

    The discriminator is therefore "did anything but placeholders ever get
    written here", not "is the row list empty": deleting the `-000` rows is an
    adopter ACT and keeps the tier, which is why an emptied file still caps."""
    path = spine_carrier.resolve(
        docs / "requirements" / filename, spine_carrier.CARRIERS
    )
    if path is None:
        return [], False
    loaded = [
        r
        for r in spine_carrier.load(docs / "requirements" / filename, id_key)
        if r.get(id_key)
    ]
    real = [r for r in loaded if not is_example(r[id_key])]
    placeholder_only = bool(loaded) and not real
    return real, not placeholder_only


def boundary_incomplete(bifs, have_registry):
    """Rung 1's predicate — is the BOUNDARY INVENTORY still in work?

    READS `external.toml`'s `[boundary.B-##]` ROWS. Until WI-442 it read the IF
    registry's `Stability` column and nothing else, which was the honest best
    available: nothing in the schema typed a crossing as external, so the rung
    could only report whether the INTERNAL seam inventory had settled and call it
    the boundary. Sitting 2 ruled the frame into its own tier (§1R.5, decision 3),
    so the predicate now reads the thing it always claimed to.

    APPLIES-WHEN (OI-14's ruled A6 shape, warn-first): the rung applies only when
    an `external.toml` FILE exists. A project that never declares a boundary is
    NOT held at DevStg-Boundary forever — `have_registry` is False and the rung is
    skipped. That is the whole difference between a rung that ships to every
    adopter and one that ships to the adopters who declared a boundary. The
    applies-when MOVED with the predicate: a repo that carries interfaces.toml and
    no external.toml now skips rung 1 rather than being held by its internal
    seams, which is the correction, not a loosening.

    WARN-HONEST WHEN IT DOES APPLY. A registry that exists but declares NO real
    crossing is honestly incomplete: the file says the project intends to type its
    frame and has not. And any crossing at DRAFTED maturity (`approval = "draft"`)
    is a frame declared and not yet approved. Both cap the rung.

    APPROVAL, NOT REALIZATION COVERAGE — the two readings of the ruling, resolved
    rather than assumed. 13u's wording gates on BIF *approval*; §1R.5's wording
    ("every declared BIF settled, every BIF realized or explicitly deferred")
    names approval AND a second conjunct. They are different predicates, and this
    is the first: whether each declared crossing carries a realizing IF row is
    DECISION 6, deferred BY RULING to post-schema (sitting-2 §4.0), and gating on
    it here would take a decision nobody has. It is not a hypothetical gap — four
    of the six locked crossings are realized by no IF row today, so the second
    conjunct would hold rung 1 down on work decision 6 has not yet scoped, and it
    would do so under a predicate that reads like approval. When decision 6
    lands, adding the conjunct is a two-line change HERE, with the coverage rule
    stated in its own docstring.

    NOTE WHAT THIS STILL DOES *NOT* CLAIM. An approved crossing is agreed, not
    demonstrated. Nothing here reports that anything was built."""
    if not have_registry:
        return False
    if not bifs:
        return True
    return any(_caps(_maturity(r.get("Status"), BIF_MATURITY)) for r in bifs)


def arch_incomplete(cmps, have_registry):
    """Rung 3's predicate — is the PARTITION still in work?

    Same applies-when shape as `boundary_incomplete`: no components registry, no
    rung. With one, a partition of nothing is incomplete, and a component at
    DRAFTED maturity (`Status = "Drafted"`) is a scope proposed and not yet
    realized.

    TWO AXES ARE READ, not one. The registry status unification (2026-08-17)
    split CMP's single field into `Status` (maturity) and `standing`
    (lifecycle), and `standing = "has-gap"` is a direct statement that the
    partition does not hold — a rung-3 fact wherever it is spelled. It is read
    through `_standing_holds_rung`, whose comment carries the restored
    rationale; without it a `Founded` row could record a known gap and still
    report a finished rung.

    THIS IS THE RUNG THAT MAKES THE RECURSION SELF-REPORTING. Rungs 2 and 3
    oscillate as the decomposition descends, and the mechanism is exactly this
    predicate reading a newly minted `Drafted` CMP row: identifying a
    sub-component DROPS the reported stage back to Arch with nobody deciding to,
    which is the honest report."""
    if not have_registry:
        return False
    if not cmps:
        return True
    return any(
        _caps(_maturity(r.get("Status"), CMP_MATURITY))
        or _standing_holds_rung(r.get("Standing"))
        for r in cmps
    )


def tier_active(rows):
    """Is this tier READ by the stage yet? True once any of its rows reads
    Approved, matched case-insensitively. A row reading Founded, or anything
    else, does not switch the tier on: the requirement names the first
    APPROVED row as the switch, and widening it to another status would be an
    amendment of that requirement, not a reading of it.

    THE SWITCH IS THE ROWS, AND NO SETTING EXISTS (SR-204). A tier holding only
    Drafted rows reads, to its rung, as a frame declared and not approved, so
    reading it before its first approval would lower the derived stage of every
    committed tree between the registry's arrival and its first signing.
    Reading it from its first approved row puts the switch in the commit that
    approves the first batch, and there is nothing beside the rows that could
    disagree with them: `docs/process.toml` is kept out of the stage's inputs,
    and no registry carries a file-level key.

    Implements: SR-204, LLR-241"""
    return any(is_approved(r) for r in rows)


def _tier_holds(rows, table):
    """An ACTIVE tier with a row at DRAFTED maturity: the tier is read, and a
    row of it is still in work at its rung."""
    return tier_active(rows) and any(
        _caps(_maturity(r.get("Status"), table)) for r in rows
    )


def assumption_incomplete(das, surs):
    """The boundary rung's reading of the assumptions registry: an active
    assumption tier or an active surrogate tier holding a Drafted row.

    EACH TIER IS READ ON ITS OWN, though the two share one file. An approved
    assumption beside a Drafted surrogate leaves the surrogate tier inactive,
    and the reverse: the first approval in a shared file must not answer for
    every other tier in it, or two readers of one file would disagree about
    what a status covers. The rows arrive already split by id column
    (`load_spine`), so this never sees one tier's rows as the other's.

    Implements: SR-204, LLR-241"""
    return _tier_holds(das, DA_MATURITY) or _tier_holds(surs, SUR_MATURITY)


def stakeholders_incomplete(stks):
    """The needs rung's reading of the stakeholder list: an active stakeholder
    tier holding a Drafted row. The stakeholders share the needs file and are
    loaded by their own id column, so a stakeholder's status never joins the
    needs' draft set, and a need's status never activates this tier.

    Implements: SR-204, LLR-241"""
    return _tier_holds(stks, STK_MATURITY)


def spine_stage(
    srs,
    llrs,
    tcs,
    sn_ids,
    sn_draft,
    bifs=None,
    cmps=None,
    have_bifs=False,
    have_cmps=False,
    cited_srs=None,
    evidence_passed=False,
    das=(),
    surs=(),
    stks=(),
):
    """The rung currently IN WORK — the STATE axis (a repo is *in* a stage), and
    the one a human-approval level is compared against. Returns a
    `DevStg-<Label>` from STAGE_ORDER.

    Read as the LOWEST unfinished rung — the one work is happening at, and
    therefore the one a human boundary has to be compared against.

      DevStg-Needs      a need is a draft, none is approved, or an approved one
                        has no SR answering it
      DevStg-Boundary   ...and the declared boundary inventory is in work
      DevStg-Reqs       ...and a requirement is Drafted
      DevStg-Arch       ...and the declared partition is in work
      DevStg-LLReqs     ...and an LLR is missing or Drafted
      DevStg-Tests      ...and a TC is missing or Drafted
      DevStg-Impl       ...and every SR is decomposed and every TC is authored
                        and non-Drafted: the tests are LAID, and making them pass
                        is the work in progress. THE TERMINAL RUNG of this
                        function.
      DevStg-Release    ...and the HARNESS-PRODUCED test-evidence record holds
                        for this exact tree: every declared test case passed.
                        Reached ONLY through `evidence_passed`, see below

    THE `Modified` ARM OF THE Reqs RUNG RETIRED AT D-9 STEP 7 — no cell records
    "amended after attestation" any more, and the successor (the snapshot
    comparison) is deliberately NOT read here; see the rung itself.

    THE TWO INSERTED RUNGS (OI-21) read from the IF and CMP registries, which
    joined the fold here — see `boundary_incomplete` / `arch_incomplete` for the
    applies-when that keeps them free for a project that adopts neither.

    THE SPINE RUNGS STILL READ PREDICATES (`is_drafted`/`is_approved`/
    `is_founded`) rather than `SPINE_MATURITY`, and that is not an oversight:
    the rungs need distinctions finer than the three-way ladder (which child is
    Drafted, which SR has not been blessed), while the ladder answers only "does
    this cap its rung". Since `maturity_bar` retired with the bar axis (slice 5)
    the spine's own table has no reader left in this module; it stays because it
    is a shared VOCABULARY, pinned by `test_rule_sync` and read by
    `baseline_snapshot`, not because a rung consults it.

    DevStg-Release IS REACHED FROM EXACTLY ONE INPUT, AND IT IS NOT A CELL
    (WI-500; WI-498 slice 3 left the rung deliberately unreachable and named this
    row as the only thing that could change that). `evidence_passed` is the
    verdict of `kitlib.stage.evidence_verdict` over the committed, HARNESS-WRITTEN
    `docs/test/evidence` record: the declared suite ran, every case passed, and
    the record is still bound BY VALUE to this exact tree. No combination of
    Status cells reaches the rung, the parameter defaults False so every caller
    that does not supply harness evidence gets the honest Impl reading, and a
    caller CANNOT synthesize it from rows — the only production supplier is
    `derive_stage`, reading the file.

    THIS DISCHARGES THE OLD Impl->Release CAVEAT AND CARRIES OI-30 D2's GUARD
    ACROSS. That caveat read: "DevStg-Impl ends when every SR reads `Approved`,
    which is a registry CELL, not a harness run ... nothing here should be read
    as proof the tests passed." The swap it owed is made — not by finding a
    better cell, but by ruling that NO cell may make the claim, and then by
    building the non-cell reading the ruling implied. D2's ceiling said the same
    thing on the bar axis by capping `sr_bar`; here the guard is structural in a
    stronger way: **a Status cell can never claim the evidence passed**, because
    the rung's one producer is a parameter no row can set.

    WHICH RUNG OWNS A MISSING ARTIFACT: the rung the artifact belongs to, not its
    parent. An SR with no LLR yet is DevStg-LLReqs, because what is being written
    is an LLR. Reading it as DevStg-Reqs (the older shape) made the lower rungs
    unreachable during exactly the period they describe — every SR had to be fully
    decomposed before a Drafted child could be seen at all — which left the axis
    unable to express "TCs are human-held but LLRs are not", the distinction the
    axis exists for.

    WHICH RUNG OWNS AN UNBLESSED SR: it is checked LAST, after the children. An
    SR reaches `Approved` only once its LLRs and TCs are green, so while a child
    is still in flight the child's rung is the honest answer. (A two-case rule
    until step 7, which retired the `Modified` case that was checked FIRST.)

    `cited_srs` IS THE SCOPE OF THE NEED-COVERAGE RUNG, and it exists for the
    PER-PHASE call (WI-498 slice 1). The coverage question — "does every approved
    need have a requirement answering it" — is repo-global: a need answered only
    by phase 1's requirements is answered. Running this function over one phase's
    rows with the default would read every OTHER phase's needs as uncovered and
    report DevStg-Needs for every phase but the first. So a per-phase caller passes
    the repo's whole (settled) SR set here while `srs` stays the phase's own rows.
    Default `None` means "the rows I was given", which is the repo-wide call and
    is byte-for-byte what this function did before the parameter existed.

    Two corners are explicit. A repo with no real SRs at all is DevStg-Needs, NOT
    DevStg-Release — the vacuous-lowest-bar short circuit in `_raw_level` exists
    for the bar's own arithmetic and would read as "everything is finished" here,
    which is precisely backwards. And an APPROVED-BUT-UNCITED SN is DevStg-Needs,
    applying WI-401's coverage rung on the same subset `_raw_level` uses: a need
    with no requirement answering it is unfinished work at the needs rung.

    `das`, `surs` and `stks` ARE THE THREE TIERS READ FROM THEIR FIRST APPROVAL
    (SR-204), repo-global like the frame rows: an active stakeholder tier with
    a Drafted row holds DevStg-Needs, and an active assumption or surrogate
    tier with a Drafted row holds DevStg-Boundary. A tier with no approved row
    holds nothing (`tier_active`). All three default empty, which is every
    caller's reading before the tiers existed."""
    bifs = bifs or []
    cmps = cmps or []
    if any(u in sn_draft for u in sn_ids) or not sn_ids:
        return STAGE_NEEDS
    if not srs or stakeholders_incomplete(stks):
        return STAGE_NEEDS
    if boundary_incomplete(bifs, have_bifs) or assumption_incomplete(das, surs):
        return STAGE_BOUNDARY
    if any(is_drafted(r) for r in srs):
        return STAGE_REQS
    if any(
        u not in sn_cited_ids(cited_srs if cited_srs is not None else srs)
        for u in sn_ids
    ):
        return STAGE_NEEDS
    # THE `Modified` RUNG RETIRED AT STEP 7 with the word it read (owner ruling
    # 2026-08-17m). NOT re-keyed onto drift: this axis reads CELLS, and reaching
    # into `docs/archive/` would make a pure row computation read the filesystem.
    if arch_incomplete(cmps, have_cmps):
        return STAGE_ARCH
    llr_sr_refs, tc_refs = _decomposed_sr_ids(llrs, tcs)
    if any(
        not llr_exempt(sr) and sr.get("SR-ID") not in llr_sr_refs for sr in srs
    ) or any(is_drafted(r) for r in llrs):
        return STAGE_LLREQS
    if any(sr.get("SR-ID") not in tc_refs for sr in srs) or any(
        is_drafted(r) for r in tcs
    ):
        return STAGE_TESTS
    # THE Impl RUNG, AND IT IS THE LAST ONE THIS FUNCTION RETURNS (WI-498
    # slice 3). Falling through every rung above means every SR is decomposed
    # and every TC is authored and non-Drafted — the test set is WRITTEN, so
    # "TCs in work" is false. What remains is making them pass, and that is
    # DevStg-Impl. The owner's semantics, ruled 2026-08-21: Founded through the
    # test tier = broken down with test cases laid = implementation is the work
    # in progress.
    #
    # WHAT WAS HERE BEFORE, AND WHY THE ARM IS GONE. Until this slice the line
    # read `if not all(is_approved(r) or is_founded(r) for r in srs): return
    # STAGE_IMPL` / `return STAGE_RELEASE` — a POLARITY INVERSION from what
    # stands now: Impl meant "the spine is not yet blessed", so a fully blessed
    # spine reported DevStg-Release, "nothing in work; release checklist
    # available", for the entire implementation period. That is the wrong
    # sentence for the longest stretch of a project (OI-51) and it made rung 6
    # reachable only by an out-of-vocabulary cell — a rung no legal spine could
    # occupy. Both arms now land on Impl, so the test collapses away rather
    # than being re-polarized: an unmigrated `Modified` row still reads Impl,
    # by falling here rather than by being singled out.
    #
    # Release is STILL NOT the else-branch of anything (WI-500). It is the
    # affirmative branch of one input, and that input is a harness verdict rather
    # than a cell: the fall-through below remains Impl, so every caller that
    # cannot show evidence gets the honest answer without having to know this
    # parameter exists.
    if evidence_passed:
        return STAGE_RELEASE
    return STAGE_IMPL


# THE BAR AXIS IS GONE, IN TWO ACTS. Slice 2 deleted the STAGE -> BAR CROSSING
# TABLE (`STAGE_BAR`, `stage_to_bar`), whose own docstring recorded that nothing
# derived the bar from the stage in production — it was a reader's
# reconciliation between two axes, and selection had stopped needing it. What it
# could NOT delete was the bar itself, because `docs/gate` was still written for
# two detectors that read the file's committed history.
#
# Slice 5 cut those detectors over and retired the file, and the rest went with
# it: the ordinals, `BAR_NAMES`/`BAR_ORDER`, the retired-tag alias table,
# `bar_label` and the release-ceiling note, the per-artifact rules
# (`sr_bar`/`maturity_bar`/`sn_bar`), `_raw_level`, `compute`, the per-phase bar
# fold, `basis_line`, the cache reader/writer and this module's whole CLI. The
# module was renamed `spine_rules` in the same act, because what remains derives
# no gate and writes no file.


def load_spine(docs):
    """Every registry row both derivations read, loaded once through the carrier.

    EXTRACTED FROM `compute` (WI-498 slice 1) so the STAGE derivation
    (`derive_stage.py`) reads the same rows through the same resolution rules
    rather than re-implementing the load. It is a pure read: no filtering beyond
    dropping the `-000` example rows, and the `have_*` applies-when flags travel
    with the rows they qualify, because a caller that separated them would have to
    remember that an ABSENT registry and an EMPTY one mean opposite things at the
    two inserted rungs.

    Returns exactly the keyword arguments `spine_stage` takes."""
    # The three spine tiers read through the CARRIER, which resolves TOML or CSV
    # and hands back rows under today's column names — so both derivations are
    # untouched by the migration. `load_csv` stays for the off-spine registries,
    # which do not move.
    raw_srs = spine_carrier.load(
        docs / "requirements" / "system-requirements.toml", "SR-ID"
    )
    raw_llrs = spine_carrier.load(
        docs / "requirements" / "low-level-requirements.toml", "LLR-ID"
    )
    raw_tcs = spine_carrier.load(docs / "test" / "test-cases.toml", "TC-ID")
    srs = [r for r in raw_srs if r.get("SR-ID") and not is_example(r["SR-ID"])]
    llrs = [r for r in raw_llrs if r.get("LLR-ID") and not is_example(r["LLR-ID"])]
    tcs = [r for r in raw_tcs if r.get("TC-ID") and not is_example(r["TC-ID"])]

    # THE NEEDS FILE RESOLVES THROUGH THE CARRIER, and this is the one place in
    # the kit where a literal suffix would be worst: an existence test on `.toml`
    # alone answers False for a repo still on markdown, `sn_ids` and `sn_draft`
    # both come back EMPTY, and an empty draft set makes every draft need read as
    # approved — the derived value RISES on a registry the reader simply could not
    # find. Absent must mean absent, never "no drafts".
    sn_md = spine_carrier.resolve(
        docs / "requirements" / "stakeholder-needs.toml", spine_carrier.NEED_CARRIERS
    )
    sn_ids, sn_draft = set(), set()
    if sn_md is not None:
        text = sn_md.read_text(encoding="utf-8-sig", errors="replace")
        sn_ids = sn_all_ids(text, sn_md.suffix)
        # An unreadable needs file REFUSES the run, naming the file: answering
        # "no drafts" for it would read every need as approved.
        sn_draft = spine_carrier.draft_ids_or_refuse(sn_md, text)

    # THE TWO OFF-SPINE REGISTRIES THE LADDER'S INSERTED RUNGS READ (OI-21). Both
    # are resolved through the carrier and both are APPLIES-WHEN — a project that
    # adopts neither registry simply never sits at DevStg-Boundary or
    # DevStg-Arch. They feed the STAGE axis only — `_raw_level` is untouched, so
    # the runnable bar is computed from exactly the rows it always was.
    bifs, have_bifs = _frame_rows(docs, "external.toml", "B-ID")
    cmps, have_cmps = _frame_rows(docs, "components.toml", "CMP-ID")
    # THE THREE TIERS READ FROM THEIR FIRST APPROVAL (SR-204), each loaded by
    # its OWN id column: the two tiers of the assumptions registry apart, and
    # the stakeholders apart from the needs whose draft set is read above, so no
    # tier's status ever answers for another sharing its file. No applies-when
    # flag travels with them: an absent registry and one holding no approved
    # row mean the same thing here, a tier the stage does not read yet.
    assumptions = docs / "requirements" / "assumptions.toml"
    das = spine_carrier.load(assumptions, "DA-ID", keep_examples=False)
    surs = spine_carrier.load(assumptions, "SUR-ID", keep_examples=False)
    stks = spine_carrier.load(
        docs / "requirements" / "stakeholder-needs.toml", "STK-ID", keep_examples=False
    )
    return {
        "srs": srs,
        "llrs": llrs,
        "tcs": tcs,
        "sn_ids": sn_ids,
        "sn_draft": sn_draft,
        "bifs": bifs,
        "cmps": cmps,
        "have_bifs": have_bifs,
        "have_cmps": have_cmps,
        "das": das,
        "surs": surs,
        "stks": stks,
    }
