"""The eight-rung DevStg STAGE LADDER — the closed vocabulary, its order, and
the only legal way to compare two rungs.

WHY THIS IS A MODULE (WI-498 slice 0, the stage unification program; the shape
is design-record §3's single-owner verdict and plan §5 item 0). The ladder's
SEMANTICS were defined in FOUR code homes: `spine_rules` (the intended SSOT),
`agent_common.LADDER_RUNGS` (a literal frozenset, restated because the retired
F5 no-shared-module rule forbade the import and held equal by a test pin),
`traj_status._STAGE_LABELS` (a byte-identical copy of `STAGE_DESC`, pinned by
NOTHING — free to drift silently), and the descriptions again in prose. The
VALUES being consumed in ~60 files is unavoidable and fine; the DEFINITION
living in four places, held together by equality tests, is the accreted
duplication this repo's doctrine refuses. It predates `kitlib`; the D-7-era
pins-over-extraction choice is what left it this way.

`kitlib` is the sanctioned landing (owner ruling D-8, `OI-16`), and the pins
retire because drift becomes UNREPRESENTABLE rather than DETECTED — the same
move WI-448 already made for the five-way declared-line reader
(`tests/test_rule_sync.py`, "the declared-line reader: WAS 5-way, now ONE home",
whose deleted equality tests are the precedent this one follows).

THE LADDER IS ITS OWN THEME, not a corner of a bigger module — the package's
"themed modules, never one generic `common.py`" constraint. It is the `station`
shape rather than the `config` shape: the vocabulary was correctly SINGLE and
wrongly PLACED. Every reader of the rung names had to import `spine_rules` — a
1,400-line derivation engine that parsed registries and wrote `docs/gate` — in
order to read a table of eight strings. `traj_status`, a RENDER leaf, was one of
those readers, which is why it kept a private copy instead. The vocabulary
depends on nothing, so it belongs below every one of them.

WHY `ladder` AND NOT `stage`. The name is the one the repo already uses for
exactly this table (`LADDER_RUNGS`, `tests/test_stage_ladder.py`, PROCESS.md §4
"The stage ladder"), so no new word enters the lexicon; it leaves `stage` free
for the derivation-and-reader module the ruled plan §2 names for slice 1 (the
declared input set, the fingerprint, the common reader), keeping the pure
vocabulary strictly BELOW the thing that derives over it; and `stage.py` sitting
beside `station.py` is a confusable pair at a glance, which a package this small
should not create.

PURE DATA, IMPORTING NOTHING — not even stdlib. That is deliberate and it is the
strongest form of the `kitlib` rule that every module here stays import-clean of
the rest of `scripts/` (`tests/test_bootstrap.py`
`::test_bootstrap_imports_only_the_common_package`): a table of strings with an
index lookup has no reason to reach for anything, and having nothing to reach
for is what makes it safe for a render leaf and the scaffolder alike.

WHAT IS DELIBERATELY NOT HERE. The BAR axis — `BAR_*` ordinals, `BAR_NAMES`,
`BAR_ORDER`, `STAGE_BAR` — was left in `spine_rules`/`check` at slice 0. The
ruled plan deleted that axis outright, and slice 0 only extracted what SURVIVED
the unification: hauling a dying vocabulary into the new home would have been
work performed twice. The axis is gone repo-wide as of slice 5.
"""

# --- THE LADDER (SN-029 / OI-21, ruled 2026-08-13; moved here WI-498) ----------
# THE RULED MODEL (owner, 2026-08-12; the ladder re-ruled 2026-08-13 as OI-21):
# **stages are the rungs of the decomposition — a repo is IN one; bars are the
# subset of rung boundaries a human must certify — you CLEAR one.** The stage is
# state, the bar is an event.
#
# THE LADDER — REQUIREMENTS BEFORE ARCHITECTURE. Architecture is a RESPONSE to
# requirements: a scope is partitioned in the way that best satisfies its
# obligations, so partitioning first means partitioning against nothing but the
# frame. The boundary happens ONCE (only the system's own frame comes from the
# needs and the context; every boundary below it is PRODUCED BY a partition),
# rungs 2 and 3 RECURSE as the decomposition descends, and rung 4 is TERMINAL by
# OI-20's binding rule — a requirement that still needs allocating to sub-parts is
# a rung-2 requirement for that sub-scope; one that BINDS to a realization
# artifact is an LLR, and that is the bottom.
#
#   0 DevStg-Needs      vision and stakeholder needs in work
#   1 DevStg-Boundary   the system's frame: what is outside, what crosses,
#                       each crossing typed.  HAPPENS ONCE.
#   2 DevStg-Reqs       the obligations at the current level's boundaries,
#                       system and component alike.  RECURSES.
#   3 DevStg-Arch       partition each scope into sub-boundaries.  RECURSES;
#                       exits when no child needs partitioning.
#   4 DevStg-LLReqs     the inside of a leaf, bound to a realization artifact
#                       (a code symbol, or a part source).  TERMINAL.
#   5 DevStg-Tests      the test set for those obligations in work
#   6 DevStg-Impl       IMPLEMENTATION in work
#   7 DevStg-Release    all complete; release checklist and version tagging
#
# (Which of those rung boundaries a HUMAN must certify is the bar axis, and it is
# `spine_rules`'s until slice 2 retires it. The crossings it names today —
# DevStg-Reqs, DevStg-Tests, DevStg-Impl — are stated there, once.)
#
# THE LABEL IS THE IDENTIFIER; POSITION IS DERIVED. A stage is `DevStg-<Label>`
# over a CLOSED vocabulary — not a minted id, so it takes no `docs/id-watermark`
# space and no retire-never-remint rule applies. The ordinal is NOT in the key,
# because position changes when the ladder changes and this kit's standing rule is
# that derived facts are generated and rendered, never authored into a key: the
# basis line carries `stage=DevStg-LLReqs stage-ord=4 stage-of=8` and renderers
# show "stage 4 of 8, <description>", so inserting a rung self-corrects every
# ordinal with no citation moved. That is exactly the failure an integer ladder
# produced here on 2026-08-12: an inserted rung shifted every cached number
# silently, in the direction of LESS human involvement.
#
# THE LADDER IS NOT MONOTONIC, and that is the truth about iterative
# decomposition rather than a defect in the report. Rungs 2 and 3 oscillate as
# the recursion descends: a newly identified sub-component landing a drafted CMP
# row, or an untyped seam landing an experimental IF row, DROPS the reported
# stage back to Arch or Boundary at a lower scope with nobody deciding to. That
# is what makes the recursion self-reporting and needs no ladder machinery at
# all. If a monotonic reading is ever wanted it is a SECOND derived number (a
# high-water mark) shown BESIDE the honest one, never instead of it.
STAGE_NEEDS = "DevStg-Needs"
STAGE_BOUNDARY = "DevStg-Boundary"
STAGE_REQS = "DevStg-Reqs"
STAGE_ARCH = "DevStg-Arch"
STAGE_LLREQS = "DevStg-LLReqs"
STAGE_TESTS = "DevStg-Tests"
STAGE_IMPL = "DevStg-Impl"
STAGE_RELEASE = "DevStg-Release"

# THE CLOSED VOCABULARY, in ladder order. Every comparison routes through
# `stage_ord` below; ordering operators on the raw value are BANNED (pinned by
# tests/test_stage_ladder.py, which greps the kit's scripts — this package
# included — for them).
STAGE_ORDER = [
    STAGE_NEEDS,
    STAGE_BOUNDARY,
    STAGE_REQS,
    STAGE_ARCH,
    STAGE_LLREQS,
    STAGE_TESTS,
    STAGE_IMPL,
    STAGE_RELEASE,
]
STAGE_OF = len(STAGE_ORDER)

# The whole closed vocabulary as a SET, for the "is this a rung I recognize"
# question. `agent_common` used to restate this as its own `LADDER_RUNGS`
# frozenset because it could not import `spine_rules`; it now imports this name.
# The membership question is genuinely different from "is this rung held" and
# only the first can be answered from the held sets — without it an unrecognized
# label (`""`, a typo, a rung from a newer kit) falls through the membership test
# and reads NOT HELD, which is the permissive direction.
LADDER_RUNGS = frozenset(STAGE_ORDER)

# One-line descriptions, for renderers that show "stage N of 8, <description>".
# The ORDINAL is not in this table, and that is the whole point of the label
# carrier (OI-21): a renderer reads `stage-ord=`/`stage-of=` off the derived
# basis line, so inserting a rung self-corrects every rendered "stage N of M"
# with no edit here. This map holds only the human sentence each label expands
# to.
STAGE_DESC = {
    STAGE_NEEDS: "vision and stakeholder needs in work",
    STAGE_BOUNDARY: "system boundary interfaces in work",
    STAGE_REQS: "requirement definition in work",
    STAGE_ARCH: "architecture (partition) in work",
    STAGE_LLREQS: "LLR definition in work",
    STAGE_TESTS: "test-case definition in work",
    STAGE_IMPL: "implementation in work",
    STAGE_RELEASE: "nothing in work; release checklist available",
}

__all__ = [
    "STAGE_NEEDS",
    "STAGE_BOUNDARY",
    "STAGE_REQS",
    "STAGE_ARCH",
    "STAGE_LLREQS",
    "STAGE_TESTS",
    "STAGE_IMPL",
    "STAGE_RELEASE",
    "STAGE_ORDER",
    "STAGE_OF",
    "STAGE_DESC",
    "LADDER_RUNGS",
    "stage_ord",
]


def stage_ord(stage):
    """The 0-based position of a stage label on STAGE_ORDER.

    THIS IS THE ONLY LEGAL WAY TO COMPARE TWO STAGES, and it RAISES on an unknown
    label rather than degrading to a default. The reason is the whole argument for
    the label carrier: an unknown stage means the ladder moved under a cached
    value, and the wrong-answer direction of a silent default is LESS human
    involvement (`human_holds` compares against this axis). Failing loudly turns a
    silent policy change into a visible one.

    It lives WITH the data rather than beside it: a closed vocabulary and the one
    operator its readers are permitted to order it with are a single concern, and
    splitting them across two modules is the same split this extraction exists to
    close.

    Ordering operators on the raw label are banned for the same reason they were
    wrong on the retired tags: `DevStg-Arch < DevStg-Boundary` lexically, which
    inverts rungs 1 and 3."""
    try:
        return STAGE_ORDER.index(stage)
    except ValueError:
        raise ValueError(
            "kitlib.ladder: {!r} is not a rung on the stage ladder — expected one "
            "of {}".format(stage, ", ".join(STAGE_ORDER))
        ) from None
