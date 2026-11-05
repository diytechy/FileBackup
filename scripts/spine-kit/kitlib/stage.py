"""The STAGE carrier: the declared derivation inputs, their fingerprint, the
`docs/stage` file format, and THE COMMON READER every consumer of "what stage is
this repo in" calls.

WHY THIS IS A MODULE (WI-498 slice 1, the stage unification program; the shape is
the ruled plan `docs/plans/2026-08-21-stage-unification-plan.md` §§1-3 and the
design record's §4.2). Until now the only machine reader of the stage was
`agent_common.spine_stage_of`, which REGEX-SCRAPED the value out of a comment on
a generated cache — a reader that could not tell a fresh value from a stale one,
and whose `\\b`-terminated pattern truncated a hyphenated label to a DIFFERENT
VALID RUNG (the deep-check's Q2(v-b), driven). This module replaces that seam
with a contract: **recompute the fingerprint of the declared inputs on every
call; return the recorded value only when it still holds; otherwise derive fresh
in memory.** Freshness stops being something a schedule has to arrange and
becomes something each call establishes.

`ladder` (slice 0) is the pure vocabulary this derives OVER; it sits strictly
below and imports nothing. This module imports stdlib and `ladder`, nothing else.

THE BOUNDARY, AND WHY IT IS A CALLBACK (the deliberate choice this slice owes a
record). The derivation proper — load the spine registries through the carrier,
fall through the eight rungs, group by phase — is ~600 lines that live in
`spine_rules` today and are REWRITTEN by slices 2 and 3 (the ladder
re-discriminates; the bar axis is deleted out from under them). Hauling that into
`kitlib` now would (a) drag `spine_carrier` and the whole registry-parsing graph
into a package whose one asserted rule is that it imports no sibling
(`tests/test_bootstrap.py::test_bootstrap_imports_only_the_common_package`), and
(b) move code that is about to be rewritten, which is work performed twice — the
same argument slice 0 gave for leaving the bar axis where it was. So the split
is by PURITY, not by subject:

  * HERE: everything that is a pure function of paths, bytes and rung labels —
    the declared input list, the fingerprint, the file format, the ordering
    (including the sentinel), the floor, the per-phase fold, and the reader's
    control flow.
  * IN `derive_stage.py`: the parse of the registries into per-phase rung
    labels, which needs the carrier.

The reader therefore takes `derive` as an ARGUMENT. It is not a plugin registry
and not a lazy import: a caller that wants the self-healing path names the
deriver it trusts, and the fresh-derivation branch is visible at every call site
instead of hidden behind a module global. `derive_stage.read()` is the one-line
wiring every production consumer calls.

WHO THE FRESHNESS GUARANTEE COVERS, stated once so no surface has to overclaim
it. `read_stage` recomputes the fingerprint on every call and derives fresh on a
mismatch, so no SELECTION or APPROVAL consumer can read a stale stage, on
any lane — and those are exactly the three call sites that reach it (`check.py`,
`agent_common`, `check_trajectory`). The DISPLAY surfaces deliberately do not:
`traj_parse._stage_value` and `traj_status._stage_facts` parse the recorded file
directly, so a generated artifact describes the commit it ships with. That is
coherent with READERS NEVER WRITE below, and it means the honest sentence names
the consumer class rather than saying "no consumer, on any lane" — an
unqualified universal the dashboard and the status block are standing
counterexamples to (ROUND-OPUS 6, on the one property this program is named
for).

READERS NEVER WRITE (plan §3). Nothing in this module opens a file for writing.
The committed `docs/stage` is load-bearing history — the phase-drop and tier
signals (slice 4) are deltas of the COMMITTED file — so regeneration stays an
auditable act at the trunk regen points and the commit-bar `--check` still
refuses a commit whose committed copy is stale. A reader that healed the file on
disk would rewrite that history from whichever process happened to look first,
and would do it on claimed branches and in CI where the freshness step is
deliberately stood down.
"""

import hashlib
import re
import subprocess
import sys
from pathlib import Path

from . import evidence, ladder

# --- THE FILE -----------------------------------------------------------------
STAGE_FILE = "docs/stage"

# THE SELECTION FLOOR. The effective stage is never reported below this rung, for
# the reason the BAR axis floors at the same place (`spine_rules`'s
# `max(BAR_REQS, raw)`): a value below it selects NOTHING under an at-or-above
# rule, so a fresh scaffold would go green because no check ran — the silent green
# SN-008 forbids, and the exact promise `ci/check.yml` makes ("a freshly-scaffolded
# DevStg-Reqs repo is green"). The floor is a SELECTION guarantee, not a claim
# about the repo: `live-stage=` beside it carries the honest, unfloored reading,
# and `floored=yes` says plainly that the two differ. This is the direction
# process.md §4 mandates — a derived reading shown BESIDE the honest one, never
# instead of it.
FLOOR = ladder.STAGE_REQS

# THE SENTINEL, WHICH IS NOT A RUNG. `DevStg-Below` means "this phase has nothing
# settled to have earned a rung with" — the per-phase analogue of the arithmetic
# sentinel the bar axis folds through. It is legal in a per-phase VALUE and
# nowhere else: `stage=` may never carry it, because the ladder deliberately has
# no rung you sit at below Needs (process.md §4). `order()` places it below every
# rung so it participates in comparisons without raising; `require_rung()` refuses
# it, so it can never become the headline by an unnoticed fall-through.
BELOW = "DevStg-Below"

# THE RUNGS A PER-PHASE READING CANNOT OWN (WI-498 slice 4). Three of the eight
# rungs are decided by REPO-WIDE inputs even when `spine_stage` is called with one
# phase's rows: `DevStg-Needs` (the need registry and — through `cited_srs` — the
# repo's whole settled SR set; slice 1 added that seam precisely because coverage
# is a repo-global question), `DevStg-Boundary` (`boundary_incomplete` over the
# repo's external registry) and `DevStg-Arch` (`arch_incomplete` over the repo's
# component registry). The frame arguments are passed WHOLE to every per-phase
# call, so when a per-phase value lands on one of these it is a repo-wide fact
# wearing a phase's label: every phase reads the same rung, and none of them is
# reporting anything about its own content.
#
# WHAT THIS IS FOR: an event detector comparing a phase's reading against a
# recorded reach must ABSTAIN on these values rather than conclude a drop — the
# reading is dominated, so "below the recorded reach" is true of the repo and
# unattributable to the phase. The other five rungs (`Reqs` via the phase's own
# Drafted SRs, `LLReqs`/`Tests`/`Impl` via its own children) ARE the phase's, and
# a comparison against them is sound.
REPO_GLOBAL_RUNGS = frozenset(
    {ladder.STAGE_NEEDS, ladder.STAGE_BOUNDARY, ladder.STAGE_ARCH}
)

# --- THE DECLARED DERIVATION INPUTS -------------------------------------------
# THE ONE LIST (plan §2). The derivation is a pure function of exactly these
# files; adding an input (the test-evidence carrier, when the Release rung is
# evidence-gated) is an edit HERE and the fingerprint covers it automatically.
#
# The owner's concern was that fingerprinting "the repository" is expensive and
# duplicates other scans. It dissolves with the inventory: the input set is not
# the repository, it is under a dozen files totalling a few hundred KB. Every
# current consumer already PARSES these same files wholesale, which costs far more
# than hashing them, so the fingerprint is a fast path that lets a fresh reader
# SKIP the parse — the net scan count goes DOWN.
#
# Each row is (declared path relative to the repo root, carrier suffixes). A
# logical input resolves to whichever carrier is present, in the declared order;
# ABSENCE IS PART OF THE FINGERPRINT, because a registry appearing or disappearing
# changes the derivation (a repo that adopts no component registry simply never
# sits at the Arch rung — so the file's absence is an input value, not a gap).
DECLARED_INPUTS = (
    ("docs/requirements/stakeholder-needs", (".toml", ".md")),
    ("docs/requirements/system-requirements", (".toml", ".csv")),
    ("docs/requirements/low-level-requirements", (".toml", ".csv")),
    ("docs/requirements/external", (".toml", ".csv")),
    ("docs/requirements/components", (".toml", ".csv")),
    ("docs/test/test-cases", (".toml", ".csv")),
    # THE ASSUMPTIONS REGISTRY (SR-204): the derivation reads its assumption
    # and surrogate tiers from their first approval. TOML is its one carrier.
    # The stakeholder tier needs no line: it lives in the needs file above.
    ("docs/requirements/assumptions", (".toml",)),
    # `process.toml` is DELIBERATELY NOT an input (owner ruling 2026-08-21,
    # amending the plan's §2 list): the derivation does not read it, and the
    # original "over-inclusion costs milliseconds" argument priced the wrong
    # cost — the real price was a RED commit bar after every policy-dial edit,
    # because the committed fingerprint went stale over a file whose value never
    # reaches the stage. Dials govern who may approve, not what stage is derived.
    # If a dial ever DOES enter the derivation, add its file here in the same
    # change that reads it.
    #
    # THE TEST-EVIDENCE CARRIER (WI-500) — the promised one-list edit, made. The
    # derivation now reads it (`DevStg-Release` is returned only when the record
    # holds), so a record appearing, changing or vanishing moves the fingerprint
    # exactly as a registry edit does. Its suffix tuple is `("",)` because the
    # file has no carrier variants: the declared path IS the file.
    (evidence.EVIDENCE_FILE, ("",)),
)


def input_paths(root):
    """`[(declared, resolved-Path-or-None)]` for every declared input, in
    declared order. `resolved` is the live carrier, or None when none exists.

    REFUSES A DUAL-CARRIER STATE, exactly as `spine_carrier.resolve` does, and
    for the same reason — two homes for one fact is the state the carrier
    migration exists to leave, and a precedence rule that silently picks one is
    how a half-finished migration keeps working while reading the stale half.

    IT USED TO TAKE THE FIRST HIT AND STOP, which made this fingerprint blind to
    the one input change that matters most (ROUND-SOL-RAW 6). Start from a
    fingerprinted `.toml` registry and add a conflicting `.csv` beside it: only
    the TOML was ever hashed, so the fingerprint did not move, so `read_stage`
    matched it and returned the RECORDED stage — without ever invoking the
    derivation that would have refused the two-home state. The forbidden state
    was reachable AND invisible, which is worse than either alone.

    A CARRIER MIGRATION (one home to the other) still moves the fingerprint
    without any of this, because the fold covers `resolved.name`; what needed
    fixing was only the state where BOTH exist."""
    out = []
    base = Path(root)
    for declared, suffixes in DECLARED_INPUTS:
        live = [
            base / (declared + suffix)
            for suffix in suffixes
            if (base / (declared + suffix)).is_file()
        ]
        if len(live) > 1:
            raise SystemExit(
                "kitlib.stage: REFUSED — {} exists under BOTH carriers ({}). "
                "Two homes for one fact is the state the migration exists to "
                "leave; delete the stale one in the same commit that wrote the "
                "other rather than letting a precedence rule pick. (The derived "
                "stage reads this file, so the refusal is the same one "
                "spine_carrier.resolve raises.)".format(
                    Path(declared).name, ", ".join(p.name for p in live)
                )
            )
        out.append((declared, live[0] if live else None))
    return out


# Per-process digest memo, keyed by (path, size, mtime-ns). MTIME IS A MEMO KEY,
# NEVER THE FRESHNESS TRUTH: `git checkout` rewrites mtimes wholesale and clocks
# skew, so a changed mtime over identical bytes costs one harmless re-hash. The
# residual is a same-size, same-nanosecond rewrite inside one process, which no
# filesystem this kit runs on can produce; a caller that wants no memo at all
# passes `memo=None`.
_DIGEST_MEMO = {}
_DEFAULT = object()


def _digest(path, memo):
    stat = path.stat()
    key = (str(path), stat.st_size, stat.st_mtime_ns)
    if memo is not None and key in memo:
        return memo[key]
    # LF-NORMALIZED, because a Windows working tree carries CRLF where the index
    # holds LF (the byte-cap and commit-probe episodes both measured it). A
    # fingerprint that flips on line endings reports stale-noise on every
    # cross-platform checkout, and the derivation itself cannot see the
    # difference — every consumer parses these files as text.
    data = path.read_bytes().replace(b"\r\n", b"\n")
    value = hashlib.sha256(data).hexdigest()
    if memo is not None:
        memo[key] = value
    return value


def _fold_inputs(root, memo, fold, skip=()):
    """Fold the declared inputs into `fold`, skipping the declared names in
    `skip`; answers `{declared: resolved-or-None}` so a caller can see what was
    present without walking the list twice.

    The fold covers the DECLARED name, the carrier actually resolved, and the
    content digest of each input in declared order — so a registry migrating from
    CSV to TOML, or vanishing, moves the fingerprint exactly as an edit does."""
    resolved_map = {}
    for declared, resolved in input_paths(root):
        resolved_map[declared] = resolved
        if declared in skip:
            continue
        fold.update(declared.encode("utf-8"))
        fold.update(b"\0")
        if resolved is None:
            fold.update(b"(absent)")
        else:
            fold.update(resolved.name.encode("utf-8"))
            fold.update(b"\0")
            fold.update(_digest(resolved, memo).encode("ascii"))
        fold.update(b"\n")
    return resolved_map


def fingerprint(root, memo=_DEFAULT):
    """`sha256:<hex>` over the LF-normalized content of the declared inputs —
    AND, when a test-evidence record is present, over the declared source surface
    that record's claim is bound to.

    WHY THE SOURCE SURFACE JOINS THE FOLD, AND ONLY THEN (WI-500). Without it the
    silent-ride the whole unification exists to prevent is reachable: a committed
    `docs/stage` reading `DevStg-Release`, a product edited afterwards, and an
    evidence file whose BYTES never moved — so the fingerprint matched, the
    recorded rung was returned, and no consumer ever asked whether the evidence
    still held. Folding the source digest makes a code edit move this value, so
    `read_stage` derives fresh (and derives Impl, because the binding no longer
    matches) and `derive_stage --check` reds on the committed copy.

    THE COST IS PAID ONLY BY A REPO THAT MAKES THE CLAIM. With no evidence file —
    every adopter below the Release rung, and every fresh scaffold — the extra
    fold is skipped entirely and this is byte-for-byte the pre-WI-500 value over
    the pre-WI-500 inputs plus one `(absent)` row."""
    if memo is _DEFAULT:
        memo = _DIGEST_MEMO
    fold = hashlib.sha256()
    resolved = _fold_inputs(root, memo, fold)
    if resolved.get(evidence.EVIDENCE_FILE) is not None:
        evidence.fold_sources(root, lambda p: _digest(p, memo), fold)
    return "sha256:" + fold.hexdigest()


# --- THE TEST-EVIDENCE VERDICT ------------------------------------------------
def evidence_binding(root, memo=_DEFAULT):
    """`sha256:<hex>` — the value a test-evidence record must carry to still hold
    for the tree at `root`: the declared spine inputs (MINUS the evidence file
    itself, which would otherwise have to contain its own digest) folded together
    with the declared product source and test surface.

    Both halves are load-bearing and each covers what the other cannot. Without
    the spine half, a test case authored after the run would ride a green that
    never executed it; without the source half, any code edit would."""
    if memo is _DEFAULT:
        memo = _DIGEST_MEMO
    fold = hashlib.sha256()
    _fold_inputs(root, memo, fold, skip=(evidence.EVIDENCE_FILE,))
    count = evidence.fold_sources(root, lambda p: _digest(p, memo), fold)
    fold.update("sources={}".format(count).encode("ascii"))
    return "sha256:" + fold.hexdigest()


def evidence_verdict(root, memo=_DEFAULT):
    """`(holds, reason)` for the committed test-evidence record.

    `holds` is True only when a record exists, records the `pass` outcome at a
    whole-suite tier, and carries the binding this tree currently computes.
    `reason` names the single failing condition, so the ONE place the rung is
    decided is also the one place that can explain itself — a caller printing the
    reason and a caller acting on the boolean cannot come to disagree.

    EVERY FAILURE IS THE SAME ANSWER, DELIBERATELY: no record, an unreadable one,
    a partial tier, a stale binding — all of them mean the claim "every declared
    test case passes on THIS tree" is unsupported, and the honest rung is the one
    below. The loudness lives in `fingerprint` above, which makes a stale record
    red the freshness check rather than letting it sit quietly unread."""
    record = evidence.read(root)
    if record is None:
        return False, "no test-evidence record at {}".format(evidence.EVIDENCE_FILE)
    if record.get("outcome") != evidence.PASS:
        return False, "the record's outcome is {!r}, not {!r}".format(
            record.get("outcome"), evidence.PASS
        )
    tier = record.get("tier")
    if tier not in evidence.WHOLE_SUITE_TIERS:
        return False, (
            "the record was driven at tier {!r}, which is not a whole-suite tier "
            "({}) — a partial tier cannot carry the claim".format(
                tier, ", ".join(evidence.WHOLE_SUITE_TIERS)
            )
        )
    current = evidence_binding(root, memo)
    if record.get("binding") != current:
        return False, (
            "STALE — the record is bound to a tree that no longer exists "
            "(recorded {}, now {}). Re-run the suite through "
            "scripts/record_test_evidence.py; never edit the binding.".format(
                record.get("binding"), current
            )
        )
    return True, "the declared suite passed at {} on this exact tree".format(tier)


def evidence_passed(root, memo=_DEFAULT):
    """The boolean half of `evidence_verdict` — the ONE input that makes
    `DevStg-Release` derivable."""
    return evidence_verdict(root, memo)[0]


# --- ORDERING, AND THE GUARD --------------------------------------------------
def order(value):
    """The stage-axis ordinal, WITH the per-phase sentinel: `DevStg-Below` is -1,
    every rung is its `ladder.stage_ord`, and anything else RAISES.

    This is the ordering per-phase values need and `ladder.stage_ord` deliberately
    refuses to provide — the ladder has no sentinel and must not grow one. Keeping
    the degradation here, in exactly one function, is what stops each consumer
    from inventing its own `-1` (the bar axis grew three such tables)."""
    if value == BELOW:
        return -1
    return ladder.stage_ord(value)


# A rung is `DevStg-` plus a single alphabetic segment. The pattern is ANCHORED AT
# BOTH ENDS on purpose: the reader this replaces used `\b` after the label, which
# matches at a hyphen, so `DevStg-Impl-2` returned `DevStg-Impl` — a confident
# wrong answer on a label the kit had never defined (deep-check Q2(v-b)). Membership
# in the closed vocabulary is the real test; this pattern exists only so the
# refusal message can tell a malformed label from an unknown one.
_RUNG_RE = re.compile(r"\ADevStg-[A-Za-z]+\Z")


def require_rung(value, where="stage"):
    """`value` if it is a rung on the ladder; ValueError otherwise. Never
    truncates, never defaults, never accepts the sentinel.

    WHAT THIS CAN AND CANNOT GUARD. It refuses every token that is not one of the
    eight rungs — which covers the sentinel, the harness's `all`, a retired tag,
    and a hyphenated label that a prefix-matching reader would have truncated into
    a different valid rung. It CANNOT distinguish the three spellings the retired
    BAR vocabulary shares with this ladder, because they are the same strings with
    different ordinals, and no value-level guard can exist while that is true (the
    deep-check's Q2(iii-b)). What contains it is carriage, not validation: the two
    axes live in different files under different keys, so a value arrives here
    having been read from `stage =` in `docs/stage` and never from a bar's line —
    and slice 2 removes the other axis entirely, which is the only real fix."""
    if value in ladder.LADDER_RUNGS:
        return value
    if value == BELOW:
        raise ValueError(
            "kitlib.stage: {} may not carry {!r} — that is the per-phase "
            "sentinel for 'nothing settled', not a rung a repo sits at".format(
                where, value
            )
        )
    shape = "" if _RUNG_RE.match(value or "") else " (not even rung-shaped)"
    raise ValueError(
        "kitlib.stage: {} carries {!r}, which is not a rung on the stage "
        "ladder{} — expected one of {}".format(
            where, value, shape, ", ".join(ladder.STAGE_ORDER)
        )
    )


# --- THE EFFECTIVE STAGE ------------------------------------------------------
def effective_stage(per_phase):
    """`(rung, floored)` — the headline value, folded from the per-phase SETTLED
    stages (drafts already excluded by the deriver).

    THE FOLD IS A MIN OVER THE PHASES THAT HAVE EARNED ANYTHING, then the floor.
    Three decisions, each against a driven corner case:

    * **Min, not max.** A max over phases is a HIGH-WATER reading, and process.md
      §4 rules that a monotonic reading may only be shown beside the honest one,
      never as it. The min is what "the settled spine is at rung X" honestly
      means; a phase that has genuinely not been decomposed yet does lower the
      answer, exactly as it lowers the bar axis today.
    * **Phases with nothing settled are IGNORED, not folded as the sentinel.**
      This is where the draft collapse is actually stopped. A brand-new phase
      holding one Drafted row has earned no rung, so it contributes no opinion;
      folding its sentinel in would drop the whole repo to the floor on the
      arrival of a single draft — C-01 reproduced on the new axis, which is the
      first of the nine corner cases this slice had to answer.
    * **An empty fold is the FLOOR, not a raise.** A fresh scaffold, an empty
      spine, and an all-draft repo all reach this branch, and all three need a
      defined selection meaning rather than an exception thrown at the reader."""
    earned = [v for v in per_phase.values() if v != BELOW]
    if not earned:
        return FLOOR, True
    low = min(earned, key=order)
    if order(low) < order(FLOOR):
        return FLOOR, True
    return low, False


# --- THE FILE FORMAT ----------------------------------------------------------
# THE COMPARED FIELDS, in file order. KEY=VALUE, NOT POSITION: the retired
# `docs/gate` put its machine value on "the first non-comment line" and its
# stage inside a comment, an idiom re-implemented in five readers and silent on
# mis-order. Every field here is addressed by name, so slice 2's consumers
# re-pointed at a key instead of a line number, and a field added later is
# invisible to a reader that does not know it.
FIELDS = (
    "stage",
    "stage-ord",
    "stage-of",
    "floored",
    "settled-stage",
    "live-stage",
    "phase",
    "per-phase",
    "per-phase-live",
    "drafted",
    "fingerprint",
)

HEADER = [
    "# DERIVED STAGE — generated by scripts/derive_stage.py (do not hand-edit).",
    "#",
    "# `stage` is the EFFECTIVE stage: the rung the SETTLED spine has earned,",
    "# folded as the min over the phases that have earned one, then floored to",
    "# DevStg-Reqs so that a repo below the floor still selects its integrity",
    "# checks. It is a SELECTION value and it is not the only truth here:",
    "#   live-stage   the honest reading over ALL rows, drafts included and",
    "#                unfloored — what is actually in work right now.",
    "#   settled-stage the same fold as `stage`, before the floor.",
    "#   per-phase    each phase's settled stage; DevStg-Below means that phase",
    "#                has nothing settled yet (it is a sentinel, never a rung).",
    "#   per-phase-live the same over all rows — where the drafts are.",
    "#   drafted      how many rows are pending, i.e. how much `live-stage` and",
    "#                `stage` are allowed to differ by.",
    "#",
    "# `fingerprint` is a SHA-256 over the LF-normalized content of the declared",
    "# derivation inputs (kitlib/stage.py DECLARED_INPUTS). A reader recomputes",
    "# it and trusts the values above ONLY on a match, deriving fresh in memory",
    "# otherwise — so no SELECTION or APPROVAL consumer can read a stale",
    "# stage, on any lane. THE DISPLAY SURFACES ARE THE NAMED EXCEPTION and read",
    "# the recorded values directly, on purpose: PROJECT_STATE.html and the",
    "# generated block in docs/status.md describe the commit they ship with, so",
    "# on a tree whose inputs have moved they render THIS file's rung while the",
    "# harness derives fresh. That is the design; it is not a guarantee, so the",
    "# sentence above says which consumers it covers.",
    "#",
    "# HOW IT MOVES: by approving artifacts in a reviewed commit, never by editing",
    "# this file. Regenerate: python scripts/derive_stage.py",
    "# Freshness is guarded by `--check` (a pre-commit + gate step).",
    "#",
]


def _fmt(value):
    if value is None:
        return "(none)"
    if isinstance(value, bool):
        return "yes" if value else "no"
    if isinstance(value, dict):
        return ";".join("{}={}".format(k, v) for k, v in value.items()) or "(none)"
    return str(value)


def field_block(record):
    """The compared field lines — everything `--check` byte-compares.

    ONE RENDERER FOR BOTH SIDES OF THAT COMPARISON: `--check` renders the parsed
    cache through this same function rather than re-formatting it, so a record
    that round-trips cannot be reported stale by a formatting difference. That is
    only sound because `parse` coerces back to the deriver's types — the two
    halves are a matched pair and must move together.

    A key that is ABSENT renders `(absent)`, which a present-but-empty field
    never produces. Collapsing the two into `(none)` would make a cache missing a
    field compare EQUAL to a derivation that legitimately has none.

    THE LINE-JOINING RULE IS `evidence.render_fields` (WI-448 slice 4) — the
    same block format `docs/test/evidence` carries. What differs is this
    module's FIELDS and its `_fmt` (bools as `yes`/`no`, dicts as `k=v;k=v`), so
    those are what it passes; the two former bodies were byte-identical and read
    as one census group while binding different module-level names."""
    return evidence.render_fields(record, FIELDS, _fmt)


def render(record, as_of, date):
    """The full `docs/stage` text: header, the compared field block, then the
    informational compute stamp. THE STAMP IS NEVER COMPARED — it carries the
    as-of revision, which moves on every commit, so comparing it would report the
    file stale the moment it was committed."""
    return (
        "\n".join(
            HEADER
            + [field_block(record), "# computed {} (as-of {})".format(date, as_of)]
        )
        + "\n"
    )


_FIELD_RE = re.compile(r"\A([a-z-]+)\s*=\s*(.*?)\s*\Z")


def parse(text):
    """The record recorded in a `docs/stage` text, or None if the file carries no
    stage field at all.

    THE TWO FAILURE DIRECTIONS ARE DELIBERATELY DIFFERENT. A file with no
    recognizable `stage` field is a file this kit did not write — a scaffold that
    has never derived, or a pre-migration tree — and returns None so the reader
    derives fresh and the `--check` step asks for the one-time generation. A file
    that DOES carry a stage but carries something that is not a rung RAISES:
    the file is generated and marked do-not-hand-edit, so a bad value there means
    either a hand edit or a ladder that moved under a cached value, and the ruled
    direction for both (`ladder.stage_ord`'s own docstring) is to fail loudly
    rather than degrade toward less human involvement."""
    record = {}
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        match = _FIELD_RE.match(stripped)
        if match and match.group(1) in FIELDS:
            record[match.group(1)] = match.group(2)
    if "stage" not in record:
        return None
    _refuse_non_rungs(record)
    return _coerce(record)


def _coerce(record):
    """The parsed record with its non-string fields read back to the TYPES the
    deriver produces.

    THE READER RETURNS ONE SHAPE, WHICHEVER PATH IT TOOK. Without this a
    consumer's `record["floored"]` is `False` on the derived path and the
    non-empty string `"no"` on the recorded path — which is TRUE — and
    `record["phase"]` is an int or a numeral. A contract whose type depends on
    whether a cache happened to be fresh is worse than no cache: the wrong branch
    is the one that almost always runs, so the bug would surface only after a
    spine edit, which is the least convenient moment for it.

    Anything unrecognized is left as the string it was read as, so a field added
    by a newer kit round-trips instead of raising."""
    out = dict(record)
    for key in ("stage-ord", "stage-of", "drafted"):
        if key in out:
            out[key] = int(out[key])
    if "phase" in out:
        out["phase"] = None if out["phase"] == "(none)" else int(out["phase"])
    if "floored" in out:
        out["floored"] = out["floored"] == "yes"
    for key in ("per-phase", "per-phase-live"):
        if key not in out:
            continue
        if out[key] == "(none)":
            out[key] = {}
            continue
        out[key] = dict(entry.partition("=")[::2] for entry in out[key].split(";"))
    return out


def _refuse_non_rungs(record):
    """Every rung-valued field of a parsed record, put to `require_rung`.

    Split out of `parse` rather than baselined: reading a key=value block and
    judging what the values may say are two jobs, and the second is the one that
    grows — the sentinel is legal in a per-phase value and illegal as a headline,
    which is a rule about POSITIONS, not about the syntax above."""
    require_rung(record["stage"], where="docs/stage `stage =`")
    for key in ("settled-stage", "live-stage"):
        if record.get(key, BELOW) != BELOW:
            require_rung(record[key], where="docs/stage `{} =`".format(key))
    for key in ("per-phase", "per-phase-live"):
        if record.get(key, "(none)") == "(none)":
            continue
        for entry in record[key].split(";"):
            _, _, value = entry.partition("=")
            if value != BELOW:
                require_rung(value, where="docs/stage `{} =`".format(key))


# --- THE DERIVER SEAM ---------------------------------------------------------
class DerivationError(Exception):
    """`derive_via_subprocess` could not produce a record.

    RAISED, NOT HANDLED HERE, because the two production callers want OPPOSITE
    failure policies and both are right: `check.py` exits with a message (a CLI
    that cannot select its plan must not guess one), while
    `agent_common.spine_stage_of` answers None, which `human_holds` reads as
    HUMAN-HELD (a coordinator that cannot establish the stage must not let an
    agent approve). One mechanism, one home; the policy stays at the call site."""


def derive_via_subprocess(scripts_dir, root):
    """The deriver `read_stage` calls on a fingerprint miss, run as a SUBPROCESS.

    WHY A SUBPROCESS AND NOT AN IMPORT (WI-498 slices 2 and 5). The derivation
    proper is `derive_stage.py`, a SIBLING SCRIPT; `check.py` and `agent_common`
    are both wholesale drop-ins that never import a sibling (the F5 rule), and
    `kitlib` itself may not. Spawning is the coupling those modules already have
    with every kit script they run, so the rule is kept without duplicating a
    600-line derivation. The cost lands only on a MISS — a fresh scaffold whose
    `docs/stage` is still the placeholder, or a tree edited since the last
    regeneration — never on the fast path.

    HOMED HERE BY THE SECOND CONSUMER (slice 5). Slice 2 wrote this body inside
    `check.py`; slice 5 cut `spine_stage_of` onto the same reader, and copying it
    would have minted exactly the kind of F5 duplicate this package exists to
    retire — with the sharper edge that the copies would be a plan selector and an
    approval authority drifting apart in silence."""
    script = Path(scripts_dir) / "derive_stage.py"
    if not script.exists():
        raise DerivationError(
            "docs/stage needs re-deriving and {} is missing — re-sync the kit "
            "scripts".format(script.name)
        )
    proc = subprocess.run(
        [sys.executable, str(script), "--root", str(root), "--print"],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise DerivationError(
            "could not derive the current stage ({} --print exited {}):\n{}".format(
                script.name, proc.returncode, proc.stderr.strip()
            )
        )
    record = parse(proc.stdout)
    if record is None:
        raise DerivationError(
            "{} --print emitted no stage field — the derivation and this reader "
            "disagree about the record format".format(script.name)
        )
    return record


# --- THE COMMON READER --------------------------------------------------------
def read_stage(root, derive, memo=_DEFAULT):
    """THE ONE FUNCTION every consumer of "what stage is this repo in" calls.

    Recomputes the fingerprint over the declared inputs, returns the RECORDED
    record when it still holds (no parse of the registries at all), and otherwise
    calls `derive(root)` and returns that — in memory. The returned record carries
    `source` = `"recorded"` or `"derived"` so a caller that wants to report which
    path it took can, and so the fast path is observable to a test.

    IT NEVER WRITES. On a mismatch the file on disk is left exactly as it was; the
    trunk regen points and the human's post-approval run are the only writers,
    and the commit-bar `--check` is what stops a stale copy from being committed.

    THIS CLOSES BOTH STALE WINDOWS THE SCHEDULE MAP FOUND, BY CONSTRUCTION rather
    than by scheduling. The branch-lane window (`derived-stage` stands down on a
    claimed branch, so a green run over a stale cache is reachable there) closes
    because a reader no longer trusts a cache the freshness step cannot police —
    it verifies per call, and on a claimed branch derives from that branch's OWN
    registries, which is the trust model the owner confirmed. The read-once-per-run
    window (a value hoisted at the top of `agent_loop`/`dispatch` and threaded
    down for the rest of the run) closes because verification is per CALL, so a
    mid-session approval is visible to the next consumer that asks."""
    if memo is _DEFAULT:
        memo = _DIGEST_MEMO
    current = fingerprint(root, memo)
    path = Path(root) / STAGE_FILE
    try:
        recorded = parse(path.read_text(encoding="utf-8", errors="replace"))
    except OSError:
        recorded = None
    if recorded is not None and recorded.get("fingerprint") == current:
        recorded["source"] = "recorded"
        return recorded
    fresh = dict(derive(root))
    fresh["fingerprint"] = current
    fresh["source"] = "derived"
    return fresh
