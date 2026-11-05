#!/usr/bin/env python3
"""Spine-row TEXT rules and the row primitives they share (WI-329).

Split out of `trace.py`, which owns the JOIN — this module owns the question
"is this one row readable and decidable on its own?", asked nine ways:

| function                    | tier     | what it catches                        |
|-----------------------------|----------|----------------------------------------|
| `provenance_findings`       | gating   | the row carries its own history        |
| `provenance_advisories`     | advisory | a living cell carries a citation frame |
| `off_spine_advisories`      | advisory | the same, on CMP/EXT living cells      |
| `form_findings`             | gating   | the row is not one testable obligation |
| `paraphrase_advisories`     | advisory | the child re-words its parent          |
| `ac_advisories`             | advisory | a comparative with no named predicate  |
| `sr_artifact_advisories`    | advisory | a requirement cell names an artifact   |
| `sn_artifact_advisories`    | advisory | a need's acceptance names an artifact  |
| `sr_fanout_advisories`      | advisory | an SR's direct-LLR fan-out is merged   |
| `ears_advisories`           | advisory | a condition stated outside EARS        |

They are PURE predicates — rows in, findings out. No I/O, no git, no
filesystem, no argv — which is the pure-core / I-O-shell split process.md §3
asks for, and what makes them cheap to test in isolation.

The row primitives (`refs`, `is_example`, `is_drafted`) are RE-EXPORTED here from
`kitlib.spine`, their one home since WI-448 slice 3. They used to be DEFINED here
and duplicated in `spine_rules.py`; `trace.py` still imports them back from this
module by name, so the dependency runs one way and there is no cycle.

The shared-`_kitcommon` shape this module's split once avoided is no longer ruled
out — owner ruling D-8 (`OI-16`) replaced F5, and `kitlib` IS that home, shipped
as a whole directory so a partial copy ImportErrors rather than degrading. What
stays true of this file is the narrower claim: it is one module's own TEXT core,
imported by that one module (ADOPTING.md §6).

Contracts: IF-076, IF-143 — the seams this module declares (process.md §8; rows
of record in docs/requirements/interfaces.toml).

Contract IF-076: the spine-row TEXT predicate surface `trace.py` imports. Rows in,
    findings out, and nothing else: no I/O, no git, no filesystem, no argv.
    `provenance_findings(srs, llrs, tcs)` and `form_findings(srs, llrs, tcs)`
    return GATING findings that join `trace.py --strict`'s exit code;
    `ac_advisories`, `paraphrase_advisories`, `provenance_advisories`,
    `off_spine_advisories`, `sr_artifact_advisories`, `sn_artifact_advisories`,
    `sr_fanout_advisories` and `ears_advisories` return warn-only advisories
    that never join a failure set. `refs`, `is_example` and `is_drafted` are the
    shared row primitives, re-exported from `kitlib.spine` so the dependency
    runs one way. The finding STRINGS are part of this promise — the golden
    files assert them byte for byte, so a reworded finding is a deliberate,
    reviewed change.
Contract IF-143: `norm_module(endpoint)` — the naming-convention-neutral module
    key, re-exported here from `kitlib.spine`: a leading `project-trajectory/`,
    any source extension and a trailing `/__init__` are stripped, so
    `scripts/x` on a seam endpoint and `project-trajectory/scripts/x.py` on a
    design row reduce to one key. It is the SAME normalizer
    `trace.interface_findings` joins on, so a component placement and the
    advisory that reports an unresolvable endpoint can never answer
    differently.

Requirements: LLR-004 (ac_advisories), LLR-133 (provenance_findings),
LLR-134 (form_findings), LLR-135 (paraphrase_advisories),
LLR-179 (ears_advisories).
"""

import re
import sys
from pathlib import Path

# THE SHIPPED SHARED-HELPER PACKAGE (owner ruling D-8, `OI-16`). Same guarded
# idiom the other scripts use: run as a subprocess this file's own dir is
# sys.path[0], so the plain import resolves; the fallback covers an in-process
# import whose sys.path does not yet carry scripts/.
try:
    from kitlib import spine as _spine
except ImportError:  # pragma: no cover - in-process fallback
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from kitlib import spine as _spine

# THE ROW PRIMITIVES, RE-EXPORTED FROM THEIR ONE HOME (WI-448 slice 3). They were
# DEFINED here and duplicated in `spine_rules.py` under the retired F5 rule; the
# rule now lives in `kitlib/spine.py`, and these names stay because `trace.py`
# imports all three from this module by name. `is_drafted` in particular was the
# copy `tests/test_rule_sync.py` pinned against `spine_rules`' — the pin is gone
# because there is nothing left to hold equal.
#
# The tier claim this module used to make about `is_drafted` — "the pure text/row
# predicates live here, while `is_approved`/`is_founded` live in trace.py and
# spine_rules.py as the F5-duplicated pair" — EXPIRED with the pair. All three
# Status predicates now sit at the same tier, below every reader, which is what
# the claim was reaching for and could not have while F5 stood.
refs = _spine.refs
is_example = _spine.is_example
is_drafted = _spine.is_drafted


# Source-file extensions stripped when normalizing a module path so the two
# module-naming conventions in play align: an LLR `Module` cell carries the full
# repo path with extension (`project-trajectory/scripts/check.py`) while the
# arch-map / an IF endpoint may use the shorter map form (`scripts/check`).
# ONE HOME since WI-448 slice 4 — `kitlib.spine`, alongside the other cell rules
# this module already re-exports; the name stays because `trace.py` imports it
# back from here.
MODULE_EXTS = _spine.MODULE_EXTS

# The ONE declared way an IF row says "this endpoint is deliberately outside this
# tree" (2026-08-15 interface rework, plan step 2). A controlled PREFIX on the
# endpoint value, not a new column, and the shape was chosen for three reasons a
# column does not have: it needs no schema change so it rides the carrier and the
# CSV fallback unaltered, it reads at the point of use (the cell that is
# unresolvable is the cell that says why), and it cannot drift out of sync with
# the endpoint it qualifies the way a parallel `external = true` flag would.
#
# Before it existed, an external actor and a rotted path were INDISTINGUISHABLE:
# the classifier guessed from spelling — anything without a slash or an extension
# "read as an external actor" — so `docs/subagent-gate` (a real path, dead since
# the policy moved to docs/process.toml) was a finding while `agent CLI` was
# silently fine, and a rot that happened to look like a name would have been
# silently fine too. The marker replaces the guess with a claim someone made.
EXTERNAL_ENDPOINT_PREFIX = "external:"

# MODULE_EXTS, EXTERNAL_ENDPOINT_PREFIX and `norm_module` MOVED HERE FROM trace.py
# at re-tier v2 S5 (WI-464): `if_provider_advisories` below asks the same
# endpoint-vs-module question and is a PURE predicate, so the choice was a
# fourth copy of the normalizer or ONE home in the lower layer. trace.py imports
# all three back — the same direction it already imports `refs`/`is_example`, so
# no cycle — and keeps `_norm_module` as a local alias, leaving its call sites
# untouched. WI-448 slice 4 finished the job that WI comment deferred:
# check_trajectory.py's and gen_arch_map.py's copies are gone, and the two names
# below now re-export `kitlib.spine` like the rest of this block.
#
# THE FOURTH COPY WAS INVISIBLE TO THE CENSUS, and the reason is worth keeping:
# this module spelled the constant `MODULE_EXTS` where the other two spelled it
# `_MODULE_EXTS`, and the census hashes the body AST including the loaded NAME —
# so a copy that renamed the constant it reads scores as a different function.
# The group only appeared once the shared home settled on one spelling.


# A module path reduced to a naming-convention-neutral key (see MODULE_EXTS):
# strip a leading `project-trajectory/`, any source extension, and `/__init__`.
# ONE HOME since WI-448 slice 4 (`kitlib.spine.norm_module`).
norm_module = _spine.norm_module


# Comparative/absolute terms that demand a predicate. Matched on word
# boundaries, case-insensitive ("schema-identical" matches "identical";
# "mismatches" does not match "matches").
COMPARATIVE_TERMS = (
    "identical",
    "indistinguishable",
    "equivalent",
    "interchangeable",
    "same as",
    "matches",
    "cannot distinguish",
    "cannot be distinguished",
    "no difference",
)
_TERM_RES = {
    t: re.compile(r"(?<!\w)" + re.escape(t).replace(r"\ ", r"\s+") + r"(?!\w)", re.I)
    for t in COMPARATIVE_TERMS
}

# Markers that (heuristically) pin a predicate in the same cell: an explicit
# definition/enumeration, a measurement/tolerance, or an exact-comparison basis.
# Word markers match on a WORD BOUNDARY, so "per"/"within" pin "as per the list"
# / "within 1 ULP" but NOT "proper"/"wrapper"/"notwithstanding" — a bare
# substring silently over-suppressed the advisory (warn-only, so this only
# sharpens lint quality). Symbol/abbreviation markers carry their own boundaries
# and match literally.
_PREDICATE_WORDS = (
    "namely",
    "defined",
    "specified",
    "listed",
    "enumerated",
    "per",
    "measured",
    "within",
    "tolerance",
    "predicate",
    "byte-for-byte",
    "bit-for-bit",
    # Self-pinning comparatives: "byte-identical"/"bit-identical" *name* their
    # predicate (the comparison basis is raw bytes/bits), exactly like
    # "byte-for-byte" — the bare comparative "identical" alone still warns.
    "byte-identical",
    "bit-identical",
    "golden",
    "regex",
    "checksum",
)
_PREDICATE_SYMBOLS = ("i.e.", "e.g.", "±", "==")
_PREDICATE_RE = re.compile(
    "|".join(
        [r"\b" + re.escape(w) + r"\b" for w in _PREDICATE_WORDS]
        + [re.escape(s) for s in _PREDICATE_SYMBOLS]
    ),
    re.IGNORECASE,
)


def _inspects_critique_record(row):
    """True for an Inspection row whose requirement's SUBJECT is a Critique
    record: the text before its first `shall` (the EARS subject, with any
    fronted condition) names both "Critique" and a "record". A requirement with
    no `shall` has no subject to read, so nothing is exempt."""
    if (row.get("Verification") or "").strip() != "Inspection":
        return False
    requirement = row.get("Requirement") or ""
    shall = _SHALL_RE.search(requirement)
    if shall is None:
        return False
    subject = requirement[: shall.start()]
    return bool(_CRITIQUE_WORD_RE.search(subject) and _RECORD_WORD_RE.search(subject))


def verification_coherence_advisories(srs):
    """Warn-only: a real SR row whose PROSE names a critique instrument while its
    `Verification` field declares some other method.

    **Two cells describing one thing, compared by nothing.** A row states its
    verification method twice — once as the `Verification` enum, once in the
    prose that says how anyone would know the row is satisfied. Nothing checked
    that the two agreed, and the failure is silent by construction: the enum
    still validates, the joins still resolve, every strict gate passes at rc=0
    while the row instructs a reader to obtain a verdict its own method does not
    produce. Measured occasion (kit meta-repo, log `2026-08-16p`): SR-052/053
    flipped `Critique`->`Test` on 2026-07-26 when their anchors were bound to
    tests, and their AcceptanceCriteria went on demanding an APPROVE verdict
    from rubrics whose headers by then read RETIRED. Three weeks, several
    reviews and a full re-tier pass read those rows without the mismatch
    surfacing mechanically.

    Scanned cells: `Rationale` and `AcceptanceCriteria` — the defect is not the
    AC's alone. A `Rationale` arguing that acceptance *is* adjudicated by an
    independent eye rots exactly as hard on a row carrying twenty passing tests,
    and lives one cell over from where anyone looks.

    `Requirement` is NOT scanned, and the exclusion is measured rather than
    assumed: scanning it fired on SR-040, whose shall enumerates the session
    phases a coordinator routes (`PLAN/BUILD/REVIEW-A/REVIEW-B/DESIGN-CHECK/
    CRITIQUE`) — the word there NAMES a phase, it does not claim a verdict. The
    distinction is not cosmetic: a requirement cell states the obligation, while
    the METHOD claim this lint hunts lives in the two cells that say how anyone
    would know the obligation is met. Widening back to `Requirement` would put a
    standing false accusation on a correct row, which is the fastest way to
    teach an author to skip this pipe.

    NOT ON AN INSPECTION ROW WHOSE SUBJECT IS A CRITIQUE RECORD. Measured on
    SR-184: its requirement obliges Critique acceptance records, and a person
    inspecting such a record reads its rubric and its verdicts, so naming them
    states WHAT is inspected, not a second method. The subject is the
    `Requirement` cell's text before its first `shall`, where the EARS form puts
    what the row obliges: an Inspection row whose subject names both "Critique"
    and a "record" is exempt, while one naming them only after the `shall` ("the
    view shall link to its Critique record") is about something else and still
    warns, as does a requirement with no `shall`. Any other Inspection row warns
    too, because one whose acceptance directs an independent CRITIQUE or APPROVE
    verdict does state two methods. The subject test is lexical; a subject that
    names a Critique record without being about one would be exempted, an
    under-detect accepted knowingly.

    ONE DIRECTION ONLY. A `Verification=Critique` row that names no instrument is
    NOT reported: the rubric it is judged against is the `docs/rubrics/`
    convention's business and a row may legitimately leave the naming to its TC,
    so the reverse check would fire on correct rows. Warn-only, never the exit
    code — the fix is a re-worded cell, which is an amendment on the author's
    schedule, not a gate's.

    Known and accepted under-detect, stated so it is never implied as covered:
    detection is the token AS WRITTEN, so a cell that describes a critique
    without using the vocabulary ("judged by a fresh independent session")
    passes. Warn-only makes an under-detect cost a missed hint, while a looser
    match would put false accusations in the report."""
    out = []
    for rid, r in _real(srs, "SR-ID"):
        method = (r.get("Verification") or "").strip()
        if not method or method == "Critique" or _inspects_critique_record(r):
            continue
        hits = [
            cell
            for cell in ("Rationale", "AcceptanceCriteria")
            if _CRITIQUE_INSTRUMENT_RE.search(r.get(cell) or "")
        ]
        if hits:
            out.append(
                "SR {} {} names a CRITIQUE instrument (a CRITIQUE, an APPROVE, a "
                "VERDICT or a rubric) while Verification is {!r} — one row must "
                "not state two verification methods: a reader told to obtain a "
                "verdict cannot, and the row's real acceptance is invisible. "
                "Re-word the cell to the method the row actually uses, or flip "
                "Verification to Critique (warn-only, never the exit code)".format(
                    rid, "/".join(hits), method
                )
            )
    return out


def ac_advisories(srs):
    """Warn-only findings: real SR rows whose AcceptanceCriteria uses a
    comparative term with no pinning marker anywhere in the cell.

    Implements: SR-157, LLR-004
    """
    out = []
    for r in srs:
        cell = (r.get("AcceptanceCriteria") or "").strip()
        if not cell:
            continue
        terms = [t for t, rx in _TERM_RES.items() if rx.search(cell)]
        if terms and not _PREDICATE_RE.search(cell):
            out.append(
                "SR {} AcceptanceCriteria uses {} without a named predicate — "
                "say identical/equivalent *in what*, judged *how* (process.md "
                "§4 consistency review; heuristic, warn-only)".format(
                    r["SR-ID"], ", ".join(repr(t) for t in sorted(terms))
                )
            )
    return out


# Case-INSENSITIVE since WI-523 (OI-65 ruled (iv)): `IF-082`/`IF-083`/`IF-084`
# carried `wI-280` for three rounds because a shift key defeated the detector.
# The token SHAPE is unchanged - this only stops the case of the two letters
# deciding whether provenance is seen at all.
_WI_TOKEN_RE = re.compile(r"\bWI-\d+", re.IGNORECASE)
_PROCESS_DOC_RE = re.compile(r"\bprocess(?:-options)?\.md\b", re.IGNORECASE)

# --- The wider provenance vocabulary (owner ruling: NO provenance citation in
# any living registry cell) --------------------------------------------------
#
# The two shapes above are the GATING class and keep that severity. These are the
# rest of the citation frame the ruling names — ruling, sitting, review-round and
# open-item references, decision ids, edit-history verbs and date stamps — and
# they are WARN-FIRST, always. Severity is not a taste call here: the population
# is ~300 tokens over ~150 live rows, so a gate would wedge the harness on work
# the repo has scheduled rather than skipped, and a rule that stops the build to
# demand prose rewriting is one a session routes around.
#
# EVERY PATTERN IS A STRUCTURED SHAPE, never a bare English word, and that is the
# whole design. Four false-positive hazards are on record and every one of them
# is MEASURED over the live registries rather than argued:
#
#   1. A general `<LETTER>-<n>` id pattern was TRIED AND REVERTED once (see the
#      `_IF_DECISION_RE` note in trace.py) because it read the data pack's own
#      `M-10` crossing ids as rulings. So the id shapes here are enumerated
#      literally — `OI-`, `D-`, `RULING-` — and nothing generalises over them.
#      Re-measured at each widening: `M-10` is matched by none of them.
#   2. `ruling` / `retired` / `attestation` / `amended` are SUBJECT NOUNS in the
#      rows that specify the approval machinery itself — 217 occurrences over
#      108 live SR/LLR/TC rows, with SR-149, SR-165 and LLR-118 the worked
#      instances. A verb grep would destroy every one of them. `_EDIT_STAMP_RE`
#      therefore requires the verb to be followed WITHIN ONE CLAUSE by an ISO
#      date: a row *about* amendment never carries one, a row *recording its own*
#      amendment always does. Measured: 0 of those 217 are flagged.
#   3. THE SAME SUBJECT-NOUN HAZARD RECURRED, in an arm that was never measured.
#      A `C-<HAT>-<n>` "review-round code" arm shipped 2026-08-18 and was
#      MEASURED AT 20 HITS, 20 OF THEM FALSE — a 100% false-positive rate. Every
#      live occurrence names a hat-charter CLAUSE as the thing the row answers
#      ("C-MNT-3 gives every declared vocabulary value exactly one normative
#      definition", "C-PRF-1 wants a declared improvement", "…the MAINTAINER
#      clause this row answers"), which is a standing constraint cited like a
#      standard's clause — the row's REASON, not its history. The arm is GONE,
#      not narrowed: the token carries no signal about which use it is, the
#      distinguishing signal is the FRAME around it, and a frame is what the two
#      edit-stamp arms below already detect. Where a clause code genuinely rides
#      inside a stamp ("REWORDED 2026-08-17 (C-PRF-1, applied)") the stamp is
#      reported and the whole frame is what gets stripped.
#   4. AN ALL-CAPS EDIT VERB IS A STAMP ONLY WHERE A CLAUSE OPENS. `APPROVED`,
#      `RETIRED`, `DELETED`, `RULED` and `AMENDED` are also ordinary
#      participles mid-sentence — "an APPROVED SN cited by zero SRs", "an AMENDED
#      requirement drops the derived stage", "a stale file is DELETED in the same
#      act" — so `_CAPS_EDIT_STAMP_RE` fires only at the start of the cell or of
#      a clause. Measured over every live spine + IF cell: 36 hits, 36 of them
#      genuine stamps, 0 false; the mid-clause participles are all silent.
#
# A bare ISO date is read as provenance in a REASON cell only. A normative cell
# may legitimately carry a date as DATA (a fixture, a declared cutover value), so
# there it reports only behind an edit verb.
_OI_TOKEN_RE = re.compile(r"\bOI-\d+\b")
_SITTING_RE = re.compile(r"\bsitting-\d+\b", re.IGNORECASE)
_DECISION_ID_RE = re.compile(r"\bD-\d+\b")
_RULING_ID_RE = re.compile(r"\bRULING-\d+\b", re.IGNORECASE)
_EDIT_VERBS = (
    r"amended|reworded|minted|renumbered|retired|narrowed|revised|superseded|"
    r"restated|added|deleted|moved|extended|clarified|ruled|raised|split|landed|"
    r"reopened|struck|introduced|widened|promoted|demoted|approved|corrected|"
    r"absorbs|settled|confirmed|investigated|resolved|reverted|joined|"
    r"re-?voiced|re-?based|re-?pointed|re-?affirmed|provisional"
)
# THE DATE, WITH ITS RULING SUFFIX. This repo — and the kit's own convention —
# writes a ruling as the date plus a serial letter (`2026-08-13u`, `2026-08-16q`),
# which is the CANONICAL citation shape and was invisible to a bare `\d{4}-\d{2}-\d{2}`:
# `provenance_tokens("The owner ruling 2026-08-13u settled this.")` returned []
# while the plain-date form beside it reported. The optional `[a-z]` closes that,
# and it cannot over-reach — `\b` after it refuses `2026-08-13until`, because the
# suffix must end the token.
_ISO_DATE = r"\d{4}-\d{2}-\d{2}[a-z]?"
_EDIT_STAMP_RE = re.compile(
    r"\b(?:" + _EDIT_VERBS + r")\b[^.;]{0,24}?\b(?P<date>" + _ISO_DATE + r")\b",
    re.IGNORECASE,
)
_ISO_DATE_RE = re.compile(r"\b(?P<date>" + _ISO_DATE + r")\b")

# THE STAMP THAT LOST ITS DATE. The 2026-08-18 sweep used `_EDIT_STAMP_RE` as its
# definition of done and deleted the DATES, which left the verbs standing:
# "MINTED 2026-08-17 (Sol F18, applied) out of SR-170" became "MINTED out of
# SR-170" and went silent. 33 such tokens survived on 31 live rows. This arm reads
# the corpus's own stamp convention — an ALL-CAPS verb opening a clause, optionally
# behind a short all-caps subject ("OWNER RE-POINTED:", "CROSSING ATTRIBUTION
# EXAMINED AND CONFIRMED:") — which is what separates a stamp from the mid-sentence
# participles hazard 4 above names. `provisional` is deliberately NOT in this arm's
# verb set: it is an adjective, never an edit, and the corpus writes it as a
# label's status ("PROVISIONAL, unsigned") on 17 rows.
_CAPS_STAMP_VERBS = (
    r"AMENDED|REWORDED|MINTED|RENUMBERED|RETIRED|NARROWED|REVISED|SUPERSEDED|"
    r"RESTATED|DELETED|EXTENDED|CLARIFIED|RULED|SPLIT|LANDED|REOPENED|STRUCK|"
    r"INTRODUCED|WIDENED|PROMOTED|DEMOTED|APPROVED|CORRECTED|ABSORBS|SETTLED|"
    r"CONFIRMED|INVESTIGATED|RESOLVED|REVERTED|JOINED|RE-?VOICED|RE-?BASED|"
    r"RE-?POINTED|RE-?AFFIRMED"
)
_CAPS_EDIT_STAMP_RE = re.compile(
    r"(?:^|(?<=[.;:!?)\]—–\n]))\s*"
    # The subject prefix is LAZY: with a greedy `{0,4}`, "ABSORBS THE RETIRED
    # LAUNCHER ROW'S HALF" reported as `'ABSORBS THE RETIRED'` — the longest
    # prefix wins and the token names the wrong verb. Lazy takes the FIRST verb
    # in the run, so the reported token is the stamp's own head word.
    #
    # A prefix word is TWO letters or more, which is not cosmetic: with `*` the
    # article in "An APPROVED SN cited by zero SRs caps the bar" read as an
    # all-caps subject whenever the sentence opened a cell, turning the
    # participle hazard this arm exists to avoid back on. The negative test is
    # what found it.
    r"(?P<token>(?:[A-Z][A-Z'’-]+\s+){0,4}?(?:" + _CAPS_STAMP_VERBS + r")\b)"
)

# (label, regex, reason-cells-only). Order is report order, and it is also
# PRECEDENCE order: an overlapping later shape is dropped, so a dated stamp
# ("CORRECTED 2026-08-16") is reported once as an edit-history stamp rather than
# twice with its bare-verb head.
_PROVENANCE_SHAPES = (
    ("work-item id", _WI_TOKEN_RE, False),
    ("process-doc citation", _PROCESS_DOC_RE, False),
    ("open-item reference", _OI_TOKEN_RE, False),
    ("sitting reference", _SITTING_RE, False),
    ("decision id", _DECISION_ID_RE, False),
    ("ruling id", _RULING_ID_RE, False),
    ("edit-history stamp", _EDIT_STAMP_RE, False),
    ("edit-history stamp", _CAPS_EDIT_STAMP_RE, False),
    ("date stamp", _ISO_DATE_RE, True),
)

# The cells whose whole job is argument. A date is provenance in these outright;
# elsewhere it needs an edit verb in front of it.
REASON_CELLS = frozenset({"Rationale", "why", "Notes"})


def _in_path_token(cell, start, end):
    """True when the match sits inside a slash-joined path token.

    `docs/plans/2026-08-16-blind-derivation-c-hats.md` is a POINTER, not a date
    stamp, and reporting "cites 2026-08-16" about it names the wrong thing. 12 of
    the 76 measured date matches were this shape."""
    left = cell.rfind(" ", 0, start) + 1
    right = cell.find(" ", end)
    return "/" in cell[left : right if right >= 0 else len(cell)]


def provenance_tokens(cell, reason=False):
    """The citation-frame tokens in one cell, de-overlapped, in report order.

    `reason` selects the reason-cell reading (a bare date counts). Pure: the
    caller decides which cells are reason cells and what severity the result
    carries.

    TWO NAMED GROUPS CARRY THE SHAPES' CONTRACT with this loop, so a pattern
    declares its own reading rather than being special-cased by identity:

      * `token` — the text to REPORT and to span-reserve, where that is narrower
        than the whole match. `_CAPS_EDIT_STAMP_RE` has to match the clause
        boundary in front of the verb, and reporting that punctuation back to an
        author would name the wrong thing.
      * `date` — the ISO date inside the match, for the path-suppression test.
        It is on BOTH date-bearing arms deliberately. Suppression used to be
        keyed on `rx is _ISO_DATE_RE`, which left the edit-stamp arm unguarded:
        "restated in docs/plans/2026-08-16-blind-derivation.md" REPORTED (the
        verb is inside the 24-character window) while the longer
        "moved to docs/archive/specs/parallel-wi-dispatch.2026-07-20.md" went
        silent — hit or miss decided by how long the filename was. A dated path
        is a pointer under every arm that can see one."""
    text = (cell or "").strip()
    if not text:
        return []
    out, spans = [], []
    for label, rx, reason_only in _PROVENANCE_SHAPES:
        if reason_only and not reason:
            continue
        groups = rx.groupindex
        for m in rx.finditer(text):
            start, end = m.span("token") if "token" in groups else m.span()
            if any(start < e and s < end for s, e in spans):
                continue
            if "date" in groups and _in_path_token(text, *m.span("date")):
                continue
            spans.append((start, end))
            out.append((label, text[start:end]))
    return out


def allow_key(rid, col, token):
    """The token-scoped allow key for one reported token, normalized.

    Whitespace-collapsed and case-folded so a cell that wraps mid-token, or an
    entry typed in a different case, still matches the thing it names."""
    return " ".join("{} {} {}".format(rid, col, token).split()).casefold()


def is_allowed(allow, rid, col, token):
    """Is this ONE token a reviewed exception (`docs/provenance-allow`)?

    TOKEN-SCOPED, and that is the whole rule. Suppression used to be keyed on the
    ROW or the ROW+CELL, while every entry in the live file justifies exactly one
    token — 15 of them read "unsigned derived-requirement label", which is the
    `(Derived-requirement label, added <date> — PROVISIONAL, unsigned.)`
    parenthetical and nothing else. Measured on 2026-08-18: re-running detection
    with the list ignored exposed 67 tokens over 22 rows that no entry had
    adjudicated, including `RE-VOICED 2026-08-17` and
    `Minted at the owner's 2026-08-15` — the banned shape itself, riding a
    carve-out written for a label. An exception now silences what it NAMES and
    nothing else, so a frame that appears beside an allowed one still reports,
    and re-wording an allowed cell re-opens the question rather than laundering
    a new frame through an old entry."""
    return allow_key(rid, col, token) in allow


# Requirement FORM (process.md §3). The stand-alone rule below says a row must not
# carry its own history; these say it must be ONE testable obligation. They are
# 29148's individual-requirement characteristics restricted to the half a checker
# can decide with no judgement — singular, unambiguous, verifiable. Every pattern
# was measured across all three registries before it shipped, and five of the six
# fire on 0-1 rows: these are guards, not a cleanup schedule.
_SHALL_RE = re.compile(r"\bshall\b", re.IGNORECASE)
# Non-`shall` modals in a REQUIREMENT only. An AcceptanceCriteria legitimately
# says "may" (a permitted outcome) and a Rationale says "would" (the consequence
# of the alternative), so widening this cries wolf on correct prose.
# `must` is deliberately ABSENT. 29148 reserves `shall`, but a project that uses
# `must` as its obligation keyword is following a different convention, not making
# an error — and this rule ships downstream, where flagging it would red every SR
# in such a repo on their first re-sync. The kit does not adjudicate that choice;
# it flags the modals that are ambiguous ALONGSIDE an obligation keyword.
_MODAL_RE = re.compile(
    r"\b(?:should|may|might|could|would|can|will|ought to)\b", re.IGNORECASE
)
# Unfalsifiable adjectives: a criterion no test can settle. `ac_advisories` warns
# on a comparative with no predicate; this gates on the terms that have no
# predicate to name.
# `etc\.` leads the alternation and carries NO trailing \b: a word boundary after
# a period only exists mid-sentence, so `\betc\.\b` silently never fires. The
# first version had it inside the \b-wrapped group and matched nothing; the test's
# positive half is what caught it.
_VAGUE_RE = re.compile(
    r"\betc\.|"
    r"\b(?:as appropriate|as needed|if possible|where practical|user-friendly|"
    r"efficient(?:ly)?|robust|flexible|sufficient(?:ly)?|adequate(?:ly)?|"
    r"reasonable|state of the art|seamless(?:ly)?|intuitive|easy to use|"
    r"minimal|optimal|appropriate(?:ly)?|and so on|TBD|TBC)\b",
    re.IGNORECASE,
)
# Open-ended clauses: the scope cannot be closed, so the row cannot be completed.
_ESCAPE_RE = re.compile(
    r"(?:including but not limited to|at a minimum|among others|such as)",
    re.IGNORECASE,
)
# "shall be logged" names no logger. Passive with a `by <actor>` is fine.
_ACTORLESS_RE = re.compile(r"\bshall be\s+\w+(?:ed|en)\b(?!\s+by\b)", re.IGNORECASE)


# Every spine cell whose text a reader treats as the SPECIFICATION — the columns
# a downstream adopter reads to learn what the system does and why. `Module`,
# `CodeSymbol`, `TestRefs`, `Evidence`, a need's `source` and the id/status
# columns are pointers by design and are deliberately out of scope.
PROVENANCE_COLS = (
    ("SR", "SR-ID", ("Title", "Requirement", "Rationale", "AcceptanceCriteria")),
    ("LLR", "LLR-ID", ("Title", "Detail", "Rationale")),
    ("TC", "TC-ID", ("Method", "Expected", "Parameters")),
)


def provenance_findings(srs, llrs, tcs):
    """A spine row whose text carries its own PROVENANCE — a work-item id, or a
    citation of the process doc the row obeys (the rule in process.md §3).

    **A requirement states the system, not its own history.** A reader — human,
    agent, or a downstream adopter with none of this project's history — must read
    one row and know what the system does and why, without resolving a work item
    they cannot see. Both facts have ONE better home: which WI delivered or amended
    a row, and why it was decided that way, live in the log — and the row OBEYS the
    process rather than citing it. (The finding text used to send an author to
    `work-items.csv` as well. That carrier is RETIRED and its presence is itself an
    integrity finding, so the message was naming a dead file as the place to move
    provenance TO; the three neighbouring messages were re-pointed at the log in
    the same-day sweep and this one was missed.)

    Applied to every SPINE registry, not just the SR. The rule shipped SR-only and
    that was the wrong scope: measured across the whole spine afterwards, 2 SRs
    carried a WI id in their normative text — and **26 LLRs, 8 TCs and 9 more SR
    Title/Rationale cells did too**, none of them watched. The largest pocket was
    the layer the SR-only rule could not see, and it kept growing while the rule
    was green (an `LLR` written the same week the lint landed carried three).

    Narrow BY MEASUREMENT, not by taste. It flags exactly two token shapes. A
    SCRIPT name (65 SR rows), an ARTIFACT PATH (6) and a RUBRIC (5) are NOT
    flagged and must never be: this kit's product IS its scripts, so the name is
    the system under specification, and for a `Verification=Critique` row the
    rubric is the acceptance instrument. A rule that cries wolf on 65 legitimate
    rows is a rule that gets scrolled past — the `check_doc_refs` lesson.

    GATING under `--strict` (owner ruling 2026-07-27, raised at the first
    re-attestation sitting on finding `LLR-050`'s `WI-316:` changelog prefix). It
    shipped warn-only on the argument that cleaning a `Verified` row flips it
    `Modified` and owes a re-attestation, so the checker should not pick the
    owner's schedule. The counter-argument won and is the stronger one: a warn
    nobody must act on is how 43 rows accumulated, and the whole population was
    cleaned in one pass at the same sitting, so the rule now guards zero-to-zero
    rather than dictating a cleanup.

    KNOWN COST, accepted deliberately: a WI id is forbidden even where it is the
    DATA rather than a citation — a row describing the dashboard's own rendered
    nodes cannot name one. That case is real (it occurred once, in a measurement
    of which node box a wire grazed) and the row was reworded to describe the node
    instead of naming it, with the specific id kept in the log. A carve-out would
    cost more than it buys: any exemption a checker cannot distinguish from the
    defect is one an author can reach for.

    Implements: SR-157, LLR-133
    """
    out = []
    for rows, (label, key, cols) in zip((srs, llrs, tcs), PROVENANCE_COLS):
        for r in rows:
            rid = (r.get(key) or "").strip()
            if not rid or is_example(rid):
                continue
            for col in cols:
                cell = (r.get(col) or "").strip()
                cited = sorted(set(_WI_TOKEN_RE.findall(cell))) + sorted(
                    {m.group(0).lower() for m in _PROCESS_DOC_RE.finditer(cell)}
                )
                if cited:
                    out.append(
                        "{} {} {} cites {} — a spine row states the system, not "
                        "its own history: move provenance to the log, and obey "
                        "the process rather than citing it".format(
                            label, rid, col, ", ".join(repr(c) for c in cited)
                        )
                    )
    return out


# The SN tier's cells, and the widened scope of the SR/LLR/TC ones. The need tier
# joins by owner ruling: the rule was written naming three tiers and the need tier
# then accumulated the worked examples of exactly the defect it forbids.
# The need's three PROSE cells only: its `source` cell (SR-190) is a pointer to
# the document the need was drawn from, a repository path by design, and
# `stakeholder_refs` points at rows, so neither is scanned.
# Implements: SR-190, LLR-217
PROVENANCE_ADVISORY_COLS = (
    ("SN", "id", ("need", "why", "acceptance")),
    ("SR", "SR-ID", ("Title", "Requirement", "Rationale", "AcceptanceCriteria")),
    ("LLR", "LLR-ID", ("Title", "Detail", "Rationale")),
    ("TC", "TC-ID", ("Method", "Expected", "Parameters")),
)

# The OFF-SPINE LIVING registries, guarded by the same ruling for the same reason.
# `components.toml` and `external.toml` were SWEPT in the 2026-08-18 pass and then
# left unwatched, which is a guard with the shape of an accident: the cells are
# clean today and nothing would say when they stopped being. The ruling names
# "any living registry cell" and these rows are living — an adopter reads a
# component's `notes` and an entity's `description` to learn what the system's
# neighbourhood IS, with no more access to this repo's sittings than they have to
# its SRs.
#
# `Description` is scanned as a NORMATIVE cell (a bare date there may be data)
# while `Notes` is the reason cell, the same split the spine tiers use. B-## and
# REL-### carry no reason cell at all — `Carries` and `Flow` state what crosses,
# which is content — so they are deliberately absent rather than silently
# forgotten.
OFF_SPINE_ADVISORY_COLS = (
    ("CMP", "CMP-ID", ("Name", "Notes")),
    ("EXT", "EXT-ID", ("Name", "Description", "Notes")),
)


def provenance_advisories(needs, srs, llrs, tcs, allow=()):
    """Warn-only: a living spine cell carrying a CITATION FRAME (process.md §3).

    The gating rule above forbids two token shapes in three tiers. This is the
    rest of the same ruling: **no provenance citation in any living registry
    cell** — no ruling, sitting, review-round or open-item reference, no decision
    id, no edit-history verb, no date stamp — on all FOUR spine tiers, and in the
    REASON cell as loudly as in the normative ones.

    The reason cell is the point. It is the one cell whose job is argument, which
    is why every citation drifts into it, and the repealed reading let a citation
    ride along as "optional context on top of a sentence that stands alone". What
    it produced, measured on the live registries, is `Rationale` cells that are
    mostly changelog: `REWORDED <date> (<round code>, <hat>; <sitting> item 8
    ruling): …`. A reader with none of this history cannot resolve any of it, and
    the durable half — what breaks without the row, which alternative lost —
    is buried in the middle of it.

    THE REWRITE IS NOT A DELETION. Drop the frame, KEEP the reason, restated as
    standing prose; where the block has no forward-looking half at all, the log
    already holds it and the block goes. Deleting the citation and the argument
    together is the failure the rationale rule exists to prevent, and it is the
    likelier failure now that the frame is forbidden — which is why this reports
    a worklist and never a gate.

    WARN-FIRST, ALWAYS, and that is a severity ruling rather than a stage. The
    population is ~300 tokens over ~150 live rows; a gate would stop the harness
    on a prose-rewriting campaign, and the rows that matter most — the ones whose
    frame is the only record of an unresolved question — need a reviewed
    exception, not a red build. `allow` carries those, TOKEN-SCOPED: each key is
    `<ROW-ID> <Cell> <token>` and silences that token alone (see `is_allowed`).

    Rows arrive in two shapes. The SN tier comes from `spine_carrier.load_needs`
    (lower-case keys, id under `id`); the other three carry `<TIER>-ID` and
    Title-case cells. One table, keyed by the id field, rather than a second
    function for the need tier — the scoping error this rule already made once
    was having a tier the check could not see."""
    return cite_advisories(
        zip((needs, srs, llrs, tcs), PROVENANCE_ADVISORY_COLS), allow
    )


def off_spine_advisories(cmps, exts, allow=()):
    """Warn-only: the same citation-frame ruling over the LIVING OFF-SPINE
    registries — `components.toml` and `external.toml` (`OFF_SPINE_ADVISORY_COLS`).

    A SEPARATE ENTRY POINT rather than four more rows in the spine table, because
    these tiers are optional: a project may declare no components and no external
    frame, and folding them in would make the spine rule's signature demand two
    registries most adopters do not have. The predicate is identical — same
    shapes, same reason-cell reading, same token-scoped exception list — so the
    two share `cite_advisories` and there is no second copy of the rule to
    drift."""
    return cite_advisories(zip((cmps, exts), OFF_SPINE_ADVISORY_COLS), allow)


# The citation-frame advisory's sentence, a `str.format` template over the
# tier label, the row id, the cell and the shown tokens. The spine and off-spine
# tiers read it; the IF sweep passes `IF_CITE_MESSAGE`.
CITE_MESSAGE = (
    "{label} {rid} {col} carries a citation frame ({shown}) — a living cell "
    "states the system and its standing reason, never its own history: drop "
    "the frame, KEEP the reason as prose that stands alone, and move the "
    "account to the log (process.md §3; warn-only, never the exit code)"
)
# The IF tier's sentence, which `trace.if_note_advisories` passes: an IF row
# states a seam, not the system, and its findings have always closed with a
# period. Derived from the one sentence above so the two cannot drift apart.
IF_CITE_MESSAGE = CITE_MESSAGE.replace("states the system", "states the seam") + "."


def cite_advisories(tiers, allow=(), message=CITE_MESSAGE):
    """The citation-frame sweep over `(rows, (label, id-key, cells))` pairs,
    each finding worded by `message` (a `CITE_MESSAGE`-shaped template).

    The ONE engine every caller of this ruling shares — the spine tiers, the
    off-spine registries, and (through trace.py) the IF reason cells. Extracted
    when the second caller arrived: three copies of "iterate rows, skip
    placeholders, ask `provenance_tokens`, de-duplicate, format" is three places
    for the exception semantics to diverge, and the exception semantics are
    exactly what was found wrong once already."""
    out = []
    for rows, (label, key, cols) in tiers:
        for r in rows or []:
            rid = str(r.get(key) or "").strip()
            if rid and not is_example(rid):
                out.extend(
                    message.format(label=label, rid=rid, col=col, shown=shown)
                    for col, shown in _cited_cells(r, rid, cols, allow)
                )
    return out


def _cited_cells(row, rid, cols, allow):
    """`(cell, shown tokens)` for each of `cols` in `row` that carries a
    citation frame the exception list does not silence, token by token.

    Implements: SR-157, LLR-133
    """
    for col in cols:
        cited = [
            (k, t)
            for k, t in provenance_tokens(row.get(col), reason=col in REASON_CELLS)
            if not is_allowed(allow, rid, col, t)
        ]
        if cited:
            # One entry per distinct token: a citation repeated inside one
            # cell is one frame to strip, not two findings.
            yield col, ", ".join(dict.fromkeys(f"{k} {t!r}" for k, t in cited))


def _real(rows, key):
    """The non-placeholder rows of one registry, with their id."""
    for r in rows:
        rid = (r.get(key) or "").strip()
        if rid and not is_example(rid):
            yield rid, r


def form_findings(srs, llrs, tcs):
    """A spine row whose text is not ONE testable obligation (process.md §3).

    The stand-alone rule says a row must not carry its own HISTORY. This says the
    part that is left must be *decidable*: 29148's individual-requirement
    characteristics — singular, unambiguous, verifiable — restricted to the half a
    checker settles without judgement. What it deliberately cannot see is whether
    the requirement is NECESSARY, CORRECT or FEASIBLE; those stay the consistency
    review's, and no proxy metric is offered for them (the readability-score
    refusal, kept).

    Narrow BY MEASUREMENT over all three registries, the discipline the SR-only
    scoping error taught: five of the six patterns fire on 0-1 rows and the sixth
    (one `shall` per requirement) on 13 of 110, so every one of them lands as a
    guard rather than a cleanup schedule. The negative half matters as much: a
    multi-clause `AcceptanceCriteria` is legitimate and untouched — an AC
    enumerates the ways ONE obligation is checked, which is the opposite of a row
    holding two obligations.

    Implements: SR-157, LLR-134
    """
    out = []
    for rid, r in _real(srs, "SR-ID"):
        if is_drafted(r):
            continue
        req = (r.get("Requirement") or "").strip()
        if not req:
            continue
        # MORE than one, never zero. A row with no `shall` is not necessarily
        # wrong — a placeholder, or a project whose obligation keyword is not the
        # English word "shall" — and flagging it would red a legitimate scaffold.
        # The measured defect was two-obligations-in-one-row, and that is what
        # this catches.
        n = len(_SHALL_RE.findall(req))
        if n > 1:
            out.append(
                "SR {} Requirement carries {} 'shall' — one row states one "
                "obligation, or a partial pass has no id to report against: "
                "split it".format(rid, n)
            )
        weak = sorted({w.lower() for w in _MODAL_RE.findall(req)})
        if weak:
            out.append(
                "SR {} Requirement uses {} in normative text — 'shall' is the "
                "obligation; 'should'/'may'/'will' are a goal, a permission and "
                "a statement of fact, and a reader cannot tell which is "
                "binding".format(rid, ", ".join(repr(w) for w in weak))
            )
        passive = _ACTORLESS_RE.search(req)
        if passive:
            out.append(
                "SR {} Requirement says {!r} with no actor — name what performs "
                "it, or the row cannot say who failed".format(rid, passive.group(0))
            )
    for rows, (label, key, cols) in zip((srs, llrs, tcs), PROVENANCE_COLS):
        for rid, r in _real(rows, key):
            # A `Draft` row is pre-approval and process.md §4 already exempts
            # it from the decomposition rules. "TBD" in a Draft acceptance
            # criterion is what Draft MEANS; flagging it would make the state
            # unusable for the drafting it exists to allow.
            if is_drafted(r):
                continue
            for col in cols:
                cell = (r.get(col) or "").strip()
                for rx, why in (
                    (_VAGUE_RE, "no test can settle it — name the measurable"),
                    (
                        _ESCAPE_RE,
                        "the scope cannot be closed, so the row cannot"
                        " be completed — enumerate it",
                    ),
                ):
                    hits = sorted({h.lower() for h in rx.findall(cell)})
                    if hits:
                        out.append(
                            "{} {} {} uses {} — {}".format(
                                label,
                                rid,
                                col,
                                ", ".join(repr(h) for h in hits),
                                why,
                            )
                        )
                if label == "LLR" and col == "Detail" and _SHALL_RE.search(cell):
                    out.append(
                        "LLR {} Detail uses 'shall' — the SR states the "
                        "obligation and the LLR decomposes it; a 'shall' here is "
                        "either a restatement of the parent or a requirement "
                        "hiding a tier below where it is traced".format(rid)
                    )
    return out


# --- EARS statement pattern (process.md §3, "The statement pattern is EARS") ---
# The five EARS keywords that may open a requirement's condition clause. A row
# opening with any of them (or with its bare subject, the ubiquitous pattern) is
# conforming; only a condition dressed in some OTHER keyword is reported.
_EARS_OPENING_RE = re.compile(r"^\s*(?:when|while|if|where)\b", re.IGNORECASE)
# The openings that ARE a condition but are not one of the five. Measured over
# this repo's 70 SRs before shipping: two rows matched ("Before unattended work
# integrates…", "For work declared as contested planning…") and both were
# re-worded onto the pattern in the same change, so the rule guards zero-to-zero
# rather than handing anyone a cleanup list.
_NON_EARS_OPENING_RE = re.compile(
    r"^\s*(?:before|after|during|upon|following|prior to|once|whenever|unless|"
    r"except|given|throughout|for|on|in|at|with|without)\b",
    re.IGNORECASE,
)


def ears_advisories(srs):
    """Warn-only: an SR whose opening states a condition OUTSIDE the EARS
    patterns (process.md §3).

    EARS puts the condition in front of the subject so a reader learns *when the
    requirement applies* before *what it obliges* — which is also what makes the
    opening scannable by eye and by tool. A row that opens "Before X, the system
    shall…" carries exactly the same condition in a place nothing looks.

    ADVISORY, and it stays advisory. Which pattern a row *is* — ubiquitous with a
    qualified response, or event-driven with the trigger fronted — is a judgement
    about the obligation, not a defect a regex settles; the same sentence can be
    honest in either shape. A gating version would be a script overruling the
    author on the one question the author is better placed to answer.

    Scope is the SR `Requirement` cell alone. An LLR carries no obligation to
    pattern (it decomposes one, and `form_findings` already refuses a `shall`
    there), and a TC states a method rather than a requirement.

    A `Drafted` row is IN scope, unlike the gating form rules beside it. Those
    skip Draft because an unfinished acceptance criterion is what Draft means;
    a sentence's opening is finished the moment it is written, and a warn-only
    reading costs a drafter nothing while the row is still cheap to re-shape.
    Both rows this rule found at landing were Drafted, so skipping them would
    have shipped a guard that had never once fired.

    Implements: SR-157, LLR-179
    """
    out = []
    for rid, r in _real(srs, "SR-ID"):
        req = (r.get("Requirement") or "").strip()
        if not req or _EARS_OPENING_RE.match(req):
            continue
        m = _NON_EARS_OPENING_RE.match(req)
        if m:
            out.append(
                "SR {} Requirement opens {!r} — a condition stated outside the "
                "EARS patterns (When/While/If/Where): re-open it on the keyword "
                "that fits, or move the qualifier into the response so the row "
                "reads as ubiquitous (warn-only, never the exit code)".format(
                    rid, m.group(0).strip()
                )
            )
    return out


def paraphrase_advisories(srs, llrs):
    """Warn-only: a child cell that mostly RE-WORDS its parent (process.md §3
    'decompose, don't paraphrase'). Lexical overlap is a heuristic and is labelled
    as one — it never gates. Measured at 38 of 118 LLRs, which is exactly why: a
    short `Detail` legitimately shares vocabulary with the SR it decomposes, so a
    gating version would cry wolf on correct rows and get scrolled past.

    Implements: SR-157, LLR-135
    """
    out = []

    def words(s):
        return {w for w in re.findall(r"[a-z_]{4,}", (s or "").lower())}

    for rid, r in _real(srs, "SR-ID"):
        req, rat = words(r.get("Requirement")), words(r.get("Rationale"))
        if rat and len(req & rat) / len(rat) > 0.55:
            out.append(
                "SR {} Rationale mostly re-words its own Requirement — a "
                "rationale says WHY the requirement exists (what breaks without "
                "it, which alternative lost), not what it says again".format(rid)
            )
    by_id = {rid: r for rid, r in _real(srs, "SR-ID")}
    for rid, r in _real(llrs, "LLR-ID"):
        det = words(r.get("Detail"))
        for p in refs(r.get("SR-Refs")):
            parent = by_id.get(p)
            if parent and det:
                req = words(parent.get("Requirement"))
                if len(req & det) / len(det) > 0.6:
                    out.append(
                        "LLR {} Detail mostly re-words {} — a child adds "
                        "detail (module, mechanism, the decomposition choice); "
                        "if it would repeat the parent, link instead".format(rid, p)
                    )
                    break
    return out


# --- Re-tier v2 R2/R3: the warn-first tiering detectors ------------------------
# All three are ADVISORY and stay advisory. They report a TIERING smell — a row
# that decided which artifact carries a capability, or a row that merged several
# decisions and grew a fan of children to cover them — and a smell is exactly
# what a human decides. None ever joins the exit code under any flag. R2's
# no-concrete-artifact rule reaches the SN tier too (`sn_artifact_advisories`,
# owner directive 2026-08-18); the fan-out rule is SR-only by construction.

# A concrete Python artifact named in a cell: a bare script (`trace.py`) or a
# path-qualified one (`scripts/trace.py`). Anchored on the literal `.py`
# extension with a word boundary each side, so "numpy", "happy" and "occupy" —
# words that merely END in "py" — cannot match: the dot is the whole signal.
# The CRITIQUE-instrument vocabulary, for the verification-coherence lint below.
# UPPERCASE-only on the three words, deliberately: the corpus writes the
# instrument and its verdict in caps ("a fresh CRITIQUE session ... returns
# APPROVE"), while lowercase "approve"/"critique"/"verdict" are ordinary prose an
# SR may legitimately use — SR-137 and SR-148 both say "the integrator's verdict
# gate" about a subsystem. Matching those case-insensitively would cry wolf on
# the common word and train an author to skip the pipe.
#
# `rubric` IS case-insensitive and needs no path, and that half was measured
# rather than guessed. Across all 63 SR rows of the kit's own registry the bare
# word appears in exactly the three that carried the defect and nowhere else,
# while the path-anchored form (`rubrics/`) missed all three — the rot had shed
# the path and kept the claim ("adjudicated ... against a written rubric").
# `adjudicat\w*` was measured too and REJECTED: it adds SR-137 and SR-148, both
# naming the loop's work-item adjudication arm, so it buys two false accusations
# for no additional catch.
_CRITIQUE_INSTRUMENT_RE = re.compile(
    r"(?<!\w)(?:CRITIQUE|APPROVE|VERDICT)(?!\w)|(?i:\brubrics?\b)"
)

# The subject test's two words (`_inspects_critique_record`), whole-word and
# case-insensitive: the requirement cell spells them as prose, not as markers.
_CRITIQUE_WORD_RE = re.compile(r"\bcritique\b", re.IGNORECASE)
_RECORD_WORD_RE = re.compile(r"\brecords?\b", re.IGNORECASE)

_PY_ARTIFACT_RE = re.compile(r"\b[A-Za-z_][\w./-]*\.py\b")

# THE RECORDED PER-ROW WAIVER MARKER: `recorded waiver: <reason>`, written in the
# row's reason cell. Case-insensitive SUBSTRING, exactly like `_FANOUT_RESTAMP`
# below — one declared-marker grammar in this module, not two.
#
# RENAMED FROM `13v` (2026-08-18), which was a DECISION ID, and that made the kit
# contradict itself in four places at once: `provenance_advisories` bans a
# decision reference from every living reason cell, while `sr_artifact_advisories`
# and `sn_artifact_advisories` INSTRUCTED an author to write one into that same
# cell to record a waiver. Three arguments, any one of which is sufficient:
#
#   1. IT SHIPS DOWNSTREAM. The token names log decision 2026-08-13v of THIS
#      repo. An adopting project has no such decision, so the kit was telling
#      every adopter to cite a ruling they have never been able to read — the
#      exact defect the provenance rule exists to prevent, shipped as an
#      instruction.
#   2. THE MARKER IS MACHINERY, AND MACHINERY SHOULD READ AS ITSELF. A declared
#      token an author writes to claim an exception is a control word, like
#      `fan-out re-stamp:`; naming it after the meeting that authorized it makes
#      a reader resolve a citation to learn what a keyword means.
#   3. THE COLON EARNS ITS KEEP. `\b13v\b` matched prose ABOUT a waiver as
#      readily as a claim of one — measured on the live registry, its only two
#      hits were SR-140 and SR-147, whose rationales say the waiver is SPENT. A
#      stale sentence was standing as a live valve. `recorded waiver:` demands
#      the marker be followed by the reason it exists.
#
# NOTE: `form_findings` does not itself suppress on this marker — a recorded
# one-`shall` waiver's finding still fires, accepted knowingly. The artifact
# advisories are its readers, and so is the absolute-term rule in the sibling
# `absolute_terms.py`, which imports this pattern rather than restating it.
_WAIVER_RE = re.compile(r"recorded waiver:", re.IGNORECASE)

# The declared SR->direct-LLR fan-out bound (re-tier v2 R3). A DIAL of the
# `TOP_VIEW_MAX` family — a declared number the project may re-stamp per row with
# a stated reason — and deliberately NOT a hard cap: a cap on children invites
# merging two LLRs into one to slip under it, which hides the very defect the
# number exists to surface. Measured basis: 48 of 60 SRs have children and 39 of
# those carry <= 5, so 7 sits above the honest population and flags the merged
# rows rather than scheduling a cleanup.
SR_FANOUT_MAX = 7

# The per-row fan-out escape, written in `Rationale` as
# "fan-out re-stamp: <reason>". Matched as a case-insensitive SUBSTRING (not a
# word-boundary token) because the phrase is multi-word and authors punctuate it
# freely.
_FANOUT_RESTAMP = "fan-out re-stamp"


def sr_artifact_advisories(srs):
    """Warn-only: an SR `Requirement` cell that names a concrete artifact
    (re-tier v2 R2, which SUPERSEDES sitting-1 ruling 2.7(a)'s license).

    **The SR tier says what is delivered, not which file delivers it.** A
    requirement that names `trace.py` has decided two things in one row — that
    the capability exists, and that *this artifact* carries it — so the row
    cannot be re-carried without re-writing an obligation, and the binding is
    stated in a tier that has no business holding it. The concrete name has three
    better homes: `AcceptanceCriteria` as rewritable current-carrier evidence
    ("read off the current carrier, as the current set: ..."), the LLR `Module`
    cell (who implements), and the shipped-file inventory (why it ships).

    Two independent censuses, deliberately not folded together:

      * PER ROW — a `*.py` token in `Requirement`, unless the row's `Rationale`
        carries the declared marker `recorded waiver: <reason>`. The waiver is
        the same valve the one-`shall` rule declares, not a second grammar.

      * PER ARTIFACT — more than one SR naming the same artifact token, WAIVED
        ROWS INCLUDED. A waiver excuses one row from stating a binding; it says
        nothing about two rows sharing one artifact identity, which is the
        tiering defect R1 names ("one home per method") and a strictly different
        finding. Counting waived rows here is what keeps the second census
        honest.

    PRESENCE ONLY. Whether the surviving wording is genuine capability or
    artifact-CLASS voice is judgement, and stays the consistency review's — this
    reports a token, never a voice. Known and accepted under-detect: identity is
    the token AS WRITTEN, so `trace.py` and `scripts/trace.py` read as two
    artifacts. Warn-only, so an under-detect costs a missed hint, while guessing
    that two spellings mean one file would put a false accusation in the report.
    """
    out = []
    by_artifact = {}
    for rid, r in _real(srs, "SR-ID"):
        req = (r.get("Requirement") or "").strip()
        if not req:
            continue
        named = sorted(set(_PY_ARTIFACT_RE.findall(req)))
        if not named:
            continue
        for token in named:
            by_artifact.setdefault(token, []).append(rid)
        if _WAIVER_RE.search(r.get("Rationale") or ""):
            continue
        out.append(
            "SR {} Requirement names concrete artifact {} — an SR states the "
            "delivered capability or the artifact CLASS ('the delivered "
            "harness', 'the launchers at the repository root'); move the "
            "concrete name to AcceptanceCriteria as current-carrier evidence, "
            "or to the LLR Module cell (process.md §3 'a requirement cell never "
            "names a concrete artifact'; warn-only, never the exit code)".format(
                rid, ", ".join(repr(t) for t in named)
            )
        )
    for token in sorted(by_artifact):
        owners = by_artifact[token]
        if len(owners) > 1:
            out.append(
                "SRs {} all name {!r} in Requirement — two rows sharing one "
                "artifact identity is a tiering defect (one decision per row, "
                "one home per method), not a naming style: decide which row "
                "owns the capability and decompose the rest, or re-carry the "
                "binding at the LLR Module cell (process.md §3; a recorded "
                "waiver excuses a row's own naming, never a shared identity; "
                "warn-only, never the exit code)".format(", ".join(owners), token)
            )
    return out


# The SN tier's artifact vocabulary (owner directive 2026-08-18, which extends
# R2's no-concrete-artifact rule from SR up to SN). Deliberately WIDER than
# `_PY_ARTIFACT_RE` above, and deliberately narrower than "anything with a dot",
# both for measured reasons taken over the kit's own 27 live needs:
#
#   * WIDER, because the SN tier's instruments are mostly NOT scripts. Anchoring
#     on `.py` alone catches 9 of the 14 rows that name a carrier and misses
#     `docs/stack.ini`, `docs/process.toml`, `docs/agents.toml` and
#     `PROJECT_STATE.html` — which are the acceptance-cell instruments a need
#     most often reaches for.
#   * WITHOUT `.md`, which was measured and REJECTED. Adding it buys four tokens
#     across three rows, and two of those (SN-027's "Spec of record: …") are
#     PROVENANCE citations that §3's provenance clause explicitly sanctions —
#     so the extension would charge an author a waiver for doing the right
#     thing. A markdown document named in a spine cell is overwhelmingly a
#     citation, not an instrument.
#
# Known and accepted under-detects, all in the warn-only direction this module
# prefers (a missed hint costs less than a false accusation): an extension-less
# carrier (`docs/agents-enabled`, `docs/next-wi`), a bare directory
# (`docs/rubrics/`), and a TOOL name that is not a filename (`pytest`,
# `tomllib`). Those stay the consistency review's to catch — the rule is wider
# than any regex for it, which is why this reports a token and never a voice.
_SN_ARTIFACT_RE = re.compile(
    r"\b[A-Za-z_][\w./-]*\.(?:py|toml|ini|csv|html|ya?ml|sh|cmd|ps1|bat|json)\b"
)


def sn_artifact_advisories(needs):
    """Warn-only: an SN `acceptance` cell that names a concrete artifact
    (owner directive 2026-08-18, extending re-tier v2 R2 from SR to SN).

    **A need states the observable condition, never the instrument that observes
    it.** An acceptance cell reading "`trace.py --strict` reports zero orphans"
    has fixed a stakeholder outcome to one script, so re-carrying the check means
    re-writing what the stakeholder asked for — and the stakeholder, who is the
    only reader this tier exists for, cannot validate a sentence naming a file
    they have never opened. The condition ("the strict traceability check reports
    zero orphans") survives every re-carry; the carrier's name belongs at SR
    `AcceptanceCriteria` as rewritable current-carrier evidence, at the LLR
    `Module` cell, or in the shipped-file inventory.

    SCANS `acceptance` ONLY, and that is a division of labour rather than an
    oversight. The `need` cell already has a stronger, more specific enforcer in
    `check_need_form.py`, which reports internal paths, implementation-only
    identifiers and process citations there on SN-033's commission; scanning it
    here too would report one token from two checks, which is the anti-duplication
    rule this kit states about its own documents applied to its own detectors.
    `why` is exempt for the reason `Rationale` is exempt at SR: it is the reason
    cell, and it is where this rule's waiver is recorded.

    THE WAIVER LIVES IN `why` — the same `recorded waiver: <reason>` marker the
    one-`shall` and SR artifact valves use, never a second grammar. `why` is the SN tier's reason
    cell (the schema carries no `Rationale`: `SPINE_TIER_KEYS["SN-ID"]` is
    `status | tags | need | why | priority | acceptance`), so it is the field
    that already answers "why is this row the way it is", which is exactly what
    a waiver has to say.

    NO PER-ARTIFACT CENSUS, unlike the SR arm. "Two rows sharing one artifact
    identity" is R1's *one home per method* defect, and a method is a requirement
    -tier thing: two needs may honestly describe outcomes the same file happens
    to serve without either of them deciding anything about it. Reporting that as
    a tiering defect would be inventing a rule the ruling does not contain.

    Rows arrive from `spine_carrier.load_needs`, so the id key is `id` and the
    cells are lower-case — NOT the `<TIER>-ID`/Title-case shape `_real` reads.
    """
    out = []
    for need in needs:
        nid = str(need.get("id") or "").strip()
        if not nid or is_example(nid):
            continue
        cell = (need.get("acceptance") or "").strip()
        if not cell:
            continue
        named = sorted(set(_SN_ARTIFACT_RE.findall(cell)))
        if not named:
            continue
        if _WAIVER_RE.search(need.get("why") or ""):
            continue
        out.append(
            "SN {} acceptance names concrete artifact {} — a need states the "
            "observable CONDITION, not the instrument that observes it ('the "
            "strict traceability check reports zero orphans', not "
            "'`trace.py --strict` reports zero orphans'); move the concrete "
            "name to the SR AcceptanceCriteria as current-carrier evidence, or "
            "record the reason it is unavoidable as `recorded waiver: <reason>` "
            "in `why` "
            "(process.md §3 'a requirement cell never names a concrete "
            "artifact'; warn-only, never the exit code)".format(
                nid, ", ".join(repr(t) for t in named)
            )
        )
    return out


def sr_fanout_advisories(srs, llrs, bound=SR_FANOUT_MAX):
    """Warn-only: an SR whose DIRECT LLR children outnumber the declared bound
    (re-tier v2 R3, `SR_FANOUT_MAX`).

    A DETECTOR, NOT A CAP. The number does not say "an SR may have at most seven
    children"; it says "a row this many children deep is usually a row that
    merged several decisions", which is R1's defect ("one decision per row, one
    home per method") seen from the child side. Treating it as a cap would be
    actively harmful — the cheapest way under a cap is to merge two LLRs into
    one, which destroys the evidence and leaves the merged SR untouched.

    So the escape is per row and it is a re-stamp, not a suppression list: an
    author who has read the row and judged the fan legitimate writes
    "fan-out re-stamp: <reason>" in `Rationale`, and the reason is the artifact a
    later reader argues with. Bound is a parameter so a downstream project can
    declare its own without editing the rule.

    Counted over the JOIN this module otherwise leaves to `trace.py`, but only
    the trivial half — an LLR's `SR-Refs` naming this SR. No resolution, no
    transitive walk, no filesystem: still a pure row predicate."""
    out = []
    counts = {}
    for _, lr in _real(llrs, "LLR-ID"):
        for parent in refs(lr.get("SR-Refs")):
            counts[parent] = counts.get(parent, 0) + 1
    for rid, r in _real(srs, "SR-ID"):
        n = counts.get(rid, 0)
        if n <= bound:
            continue
        if _FANOUT_RESTAMP in (r.get("Rationale") or "").lower():
            continue
        out.append(
            "SR {} has {} direct LLR children, over the declared bound of {} — "
            "a DETECTOR for a row that merged several decisions, not a cap "
            "(capping children invites merging LLRs to slip under it): split "
            "the row by observable class, or record a per-row 'fan-out "
            "re-stamp: <reason>' in Rationale (process.md §3 'one decision per "
            "row'; warn-only, never the exit code)".format(rid, n, bound)
        )
    return out


def _module_shaped(endpoint):
    """Is this endpoint a MODULE reference at all — the only class the
    reachability question (`trace.interface_findings`: does a module-shaped
    owner reach a requirement?) ranges over?

    Everything else in the endpoint grammar (module-or-path-or-`external:`) is
    wi455's counterpart-TRANSFORM business, not a disagreement: 45 of 122
    counterparts are non-module facts (B2, measured), and reading a data file or a
    named external actor as "the module the owner should have named" would put a
    false accusation in the report for every one of them.

    So: an `external:` claim is out (someone declared it outside this tree), a
    `docs/` path is out (the documentation tree holds no modules), an endpoint
    carrying WHITESPACE is out (`agent CLI`, `downstream adopter` — prose names an
    actor, never a path), and a path whose extension is not a source extension is
    out (`.csv`, `.toml`, `.md`). A path with no extension stays IN, because the
    short arch-map form (`scripts/check_perf`) is spelled exactly that way.

    KNOWN OVER-DETECT, accepted: a bare DIRECTORY endpoint is indistinguishable
    from a short-form module path without touching the filesystem, and this
    predicate is pure. Warn-only, so the cost is one hint to argue with."""
    e = (endpoint or "").strip().replace("\\", "/")
    if not e or e.startswith(EXTERNAL_ENDPOINT_PREFIX) or e.startswith("docs/"):
        return False
    if any(ch.isspace() for ch in e):
        return False
    if "." not in e.rsplit("/", 1)[-1]:
        return True
    return e.endswith(MODULE_EXTS)


def module_endpoints(cell):
    """The MODULE-shaped endpoints of one `;`-joined endpoint cell.

    Split on `;` ONLY — an endpoint may legitimately contain a space or a comma,
    and reading a multi-endpoint cell as one string is how a real seam gets
    reported as a disagreement (IF-097 names three modules)."""
    parts = (p.strip() for p in (cell or "").split(";"))
    return [p for p in parts if _module_shaped(p)]
