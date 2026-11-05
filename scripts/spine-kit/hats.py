#!/usr/bin/env python3
"""hats.py — the HATS ROSTER reader: which declared expert perspectives apply to
a decomposition, and the block a brief embeds so the session has to face them.

Stack-agnostic, standard-library only (Python 3.11+, Windows/POSIX).

WHY THIS MODULE EXISTS (SN-036, ruled at OI-19 on 2026-08-13). SN-036 requires
that a need turned into detailed requirements is examined from every relevant
expert and downstream-user perspective. Before this module those roles lived in
prose and column headers and had NO mechanical existence at all: nothing put a
perspective to a decomposition, and nothing could say whether one had ever been
applied. The roster (`docs/requirements/hats.toml`) declares the perspectives;
this module decides which of them a given decomposition must face; the brief
composer embeds their questions. Coverage is discharged by the review path: a
decomposition round's sitting brief carries each applicable hat's question, and
the sitting's verdict names each hat's outcome. No file beside a decomposition
records it, and no check counts it: a missing outcome is a finding for the
review. Nothing gates on a hat today: every report here is warn-first.

ABSENT IS OPT-OUT, MALFORMED IS A REFUSAL. An adopter who deletes the roster
gets composers that proceed without hats — the roster is a layer, not a floor.
A roster that EXISTS and does not parse, or carries a row missing a required
key, or an `applies_when` this module cannot evaluate, raises `HatsError`: a
broken roster reported as an empty one is a decomposition that silently faced
no perspective at all, which is the most expensive way for this machinery to be
wrong. (The same absent-vs-malformed split `spine_carrier.load` draws for the
spine registries.)

`applies_when` IS A CLOSED GRAMMAR, NOT PROSE — because a condition a composer
cannot evaluate is a comment:

    always
    scope == "template"          scope != "this-repo"
    kind == "core"               kind != "draft"
    tags contains "unattended"

Clauses join with `or` OR with `and`; MIXING THEM IN ONE EXPRESSION IS REFUSED,
so no reader ever has to guess a precedence the author did not write. The split
is on the bare keywords, so a VALUE containing ` or ` / ` and ` breaks its
clause and the roster refuses — loudly, naming the clause, which is the right
trade for not carrying a quote-aware tokenizer for values that are tags and
enum words. Scalar
fields (`scope`, `kind`) take `==` / `!=` only; the list field (`tags`) takes
`contains` only — an operator that would need a defined answer for "a list
equals a word" never parses. And the rule that keeps the roster honest as it
ships to projects whose registries carry different facts:

    A FIELD THE COMPOSER DID NOT DECLARE SATISFIES NO CONDITION.

An undeclared fact is not a true one, and it is not a false one either — so
`scope != "template"` over a context with no `scope` is FALSE, not true. A hat
keyed on a fact this project does not yet record stays silent rather than
firing on every decomposition; the fix is to declare the fact (or edit the
roster), never to let the absence read as a match.

WHY tomllib DIRECTLY AND NOT `spine_carrier`. The carrier owns the SPINE's
vocabulary — a stated key->column map, the id-column tier table, and the
migrate_carrier inverse that `tests/test_rule_sync.py` pins. The roster shares
none of it: its rows are keyed by NAME rather than by a numeric id space, it
has three keys of its own, and it is not a tier anything traces through.
Registering it there would grow the map every spine reader consults for a
registry none of them read. Forty lines of `tomllib` here is the smaller change.

Usage (the CLI is a documentation aid; the module is library-first):

    python scripts/hats.py [--root .] list
    python scripts/hats.py [--root .] applicable [--scope S] [--kind K] [--tag T]...
    python scripts/hats.py [--root .] audit [--strict]

(`--root` is the shared option and precedes the subcommand — it was written the
other way round here until the `audit` command was added and the usage line was
run.)
"""

from __future__ import annotations

import argparse
import difflib
import re
import sys
import tomllib
from pathlib import Path

# The console guard's one home is the shipped package (WI-448 / D-8);
# aliased to the module-local name so no call site changes.
from kitlib.config import utf8_console as _utf8_console
from kitlib.spine import clip_line

# Sibling: the spine's registry CARRIER (the check_need_form.py idiom). The
# `audit` subcommand reads the STAKEHOLDER-NEED tier, and that tier's vocabulary
# — which carrier is live, TOML vs the CSV-era markdown, what an unreadable
# registry means — has one home and it is not this file. (The docstring's "why
# tomllib directly" argument is about the ROSTER, which the carrier does not
# know: it is not a tier anything traces through. A need row is.) Run as a
# subprocess this script's own dir is sys.path[0] so a plain import resolves;
# the guard covers an in-process import (a test) whose sys.path does not yet
# carry scripts/.
try:
    import spine_carrier
except ImportError:  # pragma: no cover - in-process fallback
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import spine_carrier

# The roster's home, relative to the repo root.
ROSTER_REL = "docs/requirements/hats.toml"

# The stakeholder-need registry, named under EITHER carrier: `spine_carrier`
# strips the suffix and resolves whichever of `.toml` / `.md` is live (and
# refuses both at once). Written WITH the suffix, the way `baseline_snapshot`
# names it — the carrier's `stem()` cuts at the last dot in the whole path, so a
# suffix-less constant joined onto an absolute root that contains a dot in any
# directory component resolves to nonsense.
NEEDS_REL = "docs/requirements/stakeholder-needs.toml"

# Rosters BEYOND the live one whose tag tokens still count as KNOWN to the
# audit's typo check. A repo may legitimately carry more than one roster: this
# kit keeps the SHIPPED TEMPLATE beside its own instance, and the dogfood rule
# expects their VALUES to diverge (the template gates the UX pair on
# `render`/`ui`; here that pair is `always`), so a need deliberately tagged to
# read correctly under BOTH carries a token the instance roster never names.
# Reporting that as a typo would be a false alarm on a documented divergence —
# so the tokens join the KNOWN universe, and the audit says which of them reach
# nothing here. Absent paths contribute nothing (`load` returns `[]` for a file
# that is not there), so a scaffold carrying only its own roster is unaffected.
COMPANION_ROSTER_RELS = ("project-trajectory/registries/hats.template.toml",)

# Tag tokens that DELIBERATELY route to nothing, with the reason each does.
#
# When a charter is ruled UNCONDITIONAL, the tag it used to key on stops being
# evaluable anywhere: `applies_when = "always"` carries no clause, so the token
# leaves the known universe entirely — it is not in this roster and not in a
# companion one either. The need row keeps the tag, because the tag was always
# two things at once (routing AND subject metadata) and only the routing half
# went away. Left alone, the audit's typo check would report exactly the rows
# whose lens is now MOST reachable, which is the opposite of what that finding
# means; and the roster cannot say so itself, because a hat has three keys and
# none of them is "the tag I used to answer to".
#
# So the retirements are named here, each with the ruling behind it. They stay
# out of the MECHANICAL class and are reported as their own note instead — the
# adjudicator still learns the token routes nothing, which is the fact worth
# knowing. Both entries below track the SHIPPED roster, not just this repo's
# copy: hats.template.toml carries the same two charters as `always`, so an
# adopter who keeps the shipped roster and tags a need `a11y` gets the same
# correct reading. Retire a tag of your own here when you rule its hat `always`.
NON_ROUTING_TOKENS = {
    "a11y": "hat.ACCESSIBILITY is `always` (owner ruling 2026-08-16)",
    "perf": "hat.PERFORMANCE is `always` (owner ruling 2026-08-16)",
}

# The one top-level table; a roster declaring anything else is malformed.
TABLE = "hat"

# Every key a hat row must carry. `listens_for` is required for a reason worth
# stating: a hat that names no FAILURE CLASS is ceremony, and the cheapest way
# to refuse ceremony is to make its absence unparseable.
REQUIRED_KEYS = ("applies_when", "asks", "listens_for")

# Keys a hat row MAY carry, beyond the three required ones. Declaring one here
# does two things at once: it is no longer an "unknown key" refusal (the strict
# posture is otherwise unchanged — a key in neither set still refuses loudly),
# and its presence is validated by `OPTIONAL_KEY_VALIDATORS` below. ABSENT stays
# fine on every row — an optional key never becomes mandatory by being declared,
# which is the whole point of this set existing rather than widening
# REQUIRED_KEYS (WI-511, unblocking WI-484 phase 4 / OI-32 (d)).
#
# `knowledge` — the knowledge packs this hat's perspective draws on: a list of
# repo-relative paths or pack names (`docs/knowledge/...` by convention, not
# enforced), e.g. `knowledge = ["docs/knowledge/security-review.md"]`. Minimal
# shape deliberately: a list of non-empty strings, nothing richer, because
# nothing downstream yet reads more than "which packs does this hat cite."
#
# `speaks_for` — the ONE stakeholder (`STK-##`, the needs file's stakeholder
# list) whose voice this perspective is, e.g. `speaks_for = "STK-01"`. Some
# perspectives are a stakeholder's question used as a lens, and recording whose
# lets the hat be re-pointed or retired when that stakeholder changes; most
# voice no one, so the key is optional. The shape is judged here; whether the
# stakeholder is DECLARED is `trace.py`'s resolution (`hat_findings`).
OPTIONAL_KEYS = ("knowledge", "speaks_for")


def _validate_knowledge(value, where):
    """`knowledge` is a non-empty list of non-empty strings, or absent
    entirely — never present-and-empty (that is indistinguishable from a typo
    that dropped the intended entries) and never a bare string (a common typo
    for a one-item list, and silently accepting it would iterate its
    characters everywhere else a list is expected)."""
    if not isinstance(value, list) or isinstance(value, str):
        raise HatsError(
            "{}: `knowledge` must be a list of non-empty strings (got {!r})".format(
                where, value
            )
        )
    if not value:
        raise HatsError(
            "{}: `knowledge` is present but empty — omit the key rather than "
            "declaring a list with nothing in it".format(where)
        )
    cleaned = []
    for item in value:
        if not isinstance(item, str) or not item.strip():
            raise HatsError(
                "{}: `knowledge` entries must be non-empty strings (got {!r})".format(
                    where, item
                )
            )
        cleaned.append(item.strip())
    return cleaned


# One stakeholder id, as the needs file spells its stakeholder tables.
_STK_ID_RE = re.compile(r"^STK-\d+$")


def _validate_speaks_for(value, where):
    """`speaks_for` is ONE well-formed stakeholder id (`STK-##`), returned
    stripped, or absent entirely. A list is refused even when it holds one id,
    and so is a `;`-joined pair: a perspective is one stakeholder's voice, and a
    lens speaking for several speaks for none of them in particular. An empty
    value is refused for `knowledge`'s reason — indistinguishable from a typo
    that dropped the id.

    Implements: SR-213, LLR-251"""
    text = value.strip() if isinstance(value, str) else None
    if not text or not _STK_ID_RE.match(text):
        raise HatsError(
            "{}: `speaks_for` must be one stakeholder id, `STK-##` (got {!r}) — "
            "omit the key for a perspective that voices no stakeholder".format(
                where, value
            )
        )
    return text


# One validator per optional key, keyed the same way REQUIRED_KEYS' loop reads
# them — the row-level split (`_hat_from_row`) is the only caller.
OPTIONAL_KEY_VALIDATORS = {
    "knowledge": _validate_knowledge,
    "speaks_for": _validate_speaks_for,
}

# The context fields `applies_when` may name, split by the operators they admit.
SCALAR_FIELDS = ("scope", "kind")
LIST_FIELDS = ("tags",)
FIELDS = SCALAR_FIELDS + LIST_FIELDS

ALWAYS = "always"

# `<field> <op> <value>`; the value is quoted (either quote) or a bare token.
_CLAUSE_RE = re.compile(
    r"""^(?P<field>[a-z_]+)\s+(?P<op>==|!=|contains)\s+"""
    r"""(?:"(?P<dq>[^"]*)"|'(?P<sq>[^']*)'|(?P<bare>\S+))$"""
)
# The join keywords, as whole words between clauses.
_JOIN_RE = re.compile(r"\s+(or|and)\s+")


class HatsError(Exception):
    """A roster that exists and cannot be trusted — the loud half of
    absent-is-opt-out. Never raised for an absent file."""


# --- reading ------------------------------------------------------------------
def roster_path(root, rel=ROSTER_REL):
    """The roster file for a repo root."""
    return Path(root) / rel


def load(root, rel=ROSTER_REL):
    """The roster as a list of hat dicts in DECLARED ORDER — each
    `{"name", "applies_when", "asks", "listens_for"}` with `applies_when`
    already parsed (so a condition nobody can evaluate fails at load, where
    there is a file to fix, rather than at the composition it would have
    silently skipped).

    `[]` when the file is absent — the adopter opted out. `HatsError` when it
    exists and is not a usable roster."""
    path = roster_path(root, rel)
    try:
        raw = path.read_bytes()
    except FileNotFoundError:
        return []
    except OSError as exc:
        raise HatsError("{}: cannot be read ({})".format(path, exc)) from exc
    try:
        data = tomllib.loads(raw.decode("utf-8-sig"))
    except (tomllib.TOMLDecodeError, UnicodeDecodeError) as exc:
        raise HatsError(
            "{} does not parse as TOML ({}) — refusing to report an unreadable "
            "roster as an empty one".format(path, exc)
        ) from exc

    extra = sorted(k for k in data if k != TABLE)
    if extra:
        raise HatsError(
            "{}: unknown top-level table(s) {} — a roster declares only "
            "[{}.<NAME>]".format(path, ", ".join(extra), TABLE)
        )
    # `.get(TABLE, {})`, never `or {}`: a falsey non-table (`hat = ""`,
    # `hat = false`, `hat = []`) is a MALFORMED roster and must refuse loudly —
    # coercing it to an empty roster is the silent opt-out this loader exists
    # to forbid (review finding). Only true ABSENCE reads as opt-out.
    table = data.get(TABLE, {})
    if not isinstance(table, dict):
        raise HatsError("{}: [{}] is not a table of hats".format(path, TABLE))

    return [
        _hat_from_row(name, row, "{}: [{}.{}]".format(path, TABLE, name))
        for name, row in table.items()
    ]


def _hat_from_row(name, row, where):
    """One validated hat, or HatsError naming exactly which key is wrong.

    Split out of `load` so the file-level rules (does it exist, does it parse,
    does it declare only `[hat.*]`) and the row-level ones (three keys, all
    present, all non-empty, a condition that parses) read as two jobs rather
    than one nested loop."""
    if not isinstance(row, dict):
        raise HatsError("{} is not a table".format(where))
    unknown = sorted(
        k for k in row if k not in REQUIRED_KEYS and k not in OPTIONAL_KEYS
    )
    if unknown:
        raise HatsError(
            "{} declares unknown key(s) {} — a hat carries {} (plus the "
            "optional {} where present)".format(
                where,
                ", ".join(unknown),
                ", ".join(REQUIRED_KEYS),
                ", ".join(OPTIONAL_KEYS),
            )
        )
    hat = {"name": name}
    for key in REQUIRED_KEYS:
        value = row.get(key)
        if not isinstance(value, str) or not value.strip():
            raise HatsError(
                "{} has no `{}` — every hat must name its condition, its "
                "question and the FAILURE CLASS it catches (a hat naming "
                "no failure is ceremony)".format(where, key)
            )
        # Whitespace is COLLAPSED at load: `asks`/`listens_for` render inside
        # a one-line markdown bullet in the composed brief, and a multi-line
        # value would put its later lines at column 0 — where `## ...` becomes
        # a top-level heading that can override the brief's own structure
        # (review finding). Inline text cannot mint a heading.
        hat[key] = " ".join(value.split())
    hat["condition"] = parse_condition(hat["applies_when"], where)
    # Optional keys: ABSENT stays absent (never defaulted to "" or []), so a
    # row that never mentions `knowledge` yields a hat dict with no such key —
    # the same "declared vs not" honesty REQUIRED_KEYS gives, one tier down.
    for key in OPTIONAL_KEYS:
        if key in row:
            hat[key] = OPTIONAL_KEY_VALIDATORS[key](row[key], where)
    return hat


# --- the applies_when grammar -------------------------------------------------
def parse_condition(expr, where="applies_when"):
    """`(join, [(field, op, value), ...])` for a condition, or `("always", [])`.

    Raises HatsError on anything outside the closed grammar — including a mixed
    `or`/`and` expression, an operator a field does not admit, and a field name
    no context can carry."""
    text = (expr or "").strip()
    if text == ALWAYS:
        return (ALWAYS, [])
    # A capturing split interleaves clause, join, clause, join, ... — the even
    # slots are the clauses and the odd ones the joins.
    parts = _JOIN_RE.split(text)
    clauses, joins = parts[0::2], parts[1::2]
    if len(set(joins)) > 1:
        raise HatsError(
            "{}: {!r} mixes `or` and `and` — write one or the other, so no "
            "reader has to guess a precedence you did not state".format(where, expr)
        )
    join = joins[0] if joins else "or"
    parsed = []
    for clause in clauses:
        matched = _CLAUSE_RE.match(clause.strip())
        if matched is None:
            raise HatsError(
                "{}: {!r} is not an evaluable clause — expected `always` or "
                "`<field> <op> <value>` with field in {} and op in "
                "==/!=/contains".format(where, clause.strip(), "/".join(FIELDS))
            )
        field, op = matched.group("field"), matched.group("op")
        value = matched.group("dq")
        if value is None:
            value = matched.group("sq")
        if value is None:
            value = matched.group("bare")
        if field not in FIELDS:
            raise HatsError(
                "{}: unknown field {!r} — a composer can declare {}".format(
                    where, field, ", ".join(FIELDS)
                )
            )
        if field in LIST_FIELDS and op != "contains":
            raise HatsError(
                "{}: `{}` is a list, so it takes `contains` only (got {!r})".format(
                    where, field, op
                )
            )
        if field in SCALAR_FIELDS and op == "contains":
            raise HatsError(
                "{}: `{}` is a single value, so it takes == / != only".format(
                    where, field
                )
            )
        parsed.append((field, op, value))
    return (join, parsed)


def evaluate(condition, context):
    """Whether a parsed condition holds for `context` — a dict that may carry
    `scope`, `kind` (strings) and `tags` (an iterable of strings).

    A FIELD THE CONTEXT DOES NOT DECLARE SATISFIES NO CLAUSE, `!=` included:
    an undeclared fact is not a true one, and reading its absence as a match
    would fire a hat on every decomposition in a project that never records
    that fact."""
    join, clauses = condition
    if join == ALWAYS:
        return True
    results = [_clause_holds(c, context) for c in clauses]
    return all(results) if join == "and" else any(results)


def _clause_holds(clause, context):
    field, op, value = clause
    have = (context or {}).get(field)
    if have is None:
        return False  # an undeclared fact satisfies nothing
    if field in LIST_FIELDS:
        tags = [str(t).strip() for t in have if str(t).strip()]
        return value in tags
    have = str(have).strip()
    if not have:
        return False
    return have == value if op == "==" else have != value


def applicable(roster, context):
    """The hats whose `applies_when` holds for `context`, in declared order."""
    return [h for h in roster if evaluate(h["condition"], context)]


# --- the contexts a composer builds -------------------------------------------
def context_from_need(row):
    """The decomposition context for ONE stakeholder-need row: its declared
    `scope` and `kind`, plus any declared `tags`.

    Reads only TYPED cells, under either the TOML key or the column name the
    carrier reports. A cell the row does not carry is simply absent from the
    context, which (see `evaluate`) means no clause keyed on it fires — the
    honest reading of a fact the registry has not recorded yet."""
    ctx = {}
    for field in SCALAR_FIELDS:
        value = _first(row, field, field.capitalize())
        if isinstance(value, str) and value.strip():
            ctx[field] = value.strip()
    tags = _first(row, "tags", "Tags")
    tags = _as_tags(tags)
    if tags:
        ctx["tags"] = tags
    return ctx


def context_from_work_item(row):
    """The decomposition context for a WORK-ITEM row — the shape the dual-plan
    decomposition round actually has in hand.

    `tags` are the row's `AuthoringTags` cell when it is non-empty, in place of
    its two typed classification cells, never beside them: a minted row's own
    `process` and `adjudication` say how it routes, not what its authoring work
    item was. An empty cell reads those two cells, `Workstream` and
    `SafetyClass`. `scope` and `kind` are left UNDECLARED because a work item
    carries neither, so a roster clause keyed on them stays silent here instead
    of matching by accident. A need-level composer supplies those two through
    `context_from_need` once the need registry carries them as fields.

    Implements: SR-161, LLR-360
    """
    # The scope FIELD that would make the scope-keyed hats fire is the subject
    # of stakeholder need SN-039 (a declared scope value, not prose to infer).
    # Named in a comment rather than the docstring so the arch-map harvest does
    # not read a POINTER to a need as a claim to implement one.
    authoring = _as_tags(_first(row, "AuthoringTags", "authoring_tags"))
    if authoring:
        return {"tags": authoring}
    tags = []
    for key in ("Workstream", "workstream", "SafetyClass", "safety_class"):
        value = (row or {}).get(key)
        if isinstance(value, str) and value.strip() and value.strip() not in tags:
            tags.append(value.strip())
    return {"tags": tags} if tags else {}


def _first(row, *keys):
    for key in keys:
        if key in (row or {}):
            return row[key]
    return None


def _as_tags(value):
    if isinstance(value, str):
        return [t.strip() for t in value.replace(",", ";").split(";") if t.strip()]
    if isinstance(value, (list, tuple)):
        return [str(t).strip() for t in value if str(t).strip()]
    return []


# --- what a brief embeds ------------------------------------------------------
# The line a brief carries when no hat applies (or the roster is absent). It is
# a STATED opt-out, not a placeholder: the reader can tell "no perspective was
# declared for this" from "the section did not get filled".
NO_HATS = (
    "_(no declared perspective applies to this decomposition — "
    "docs/requirements/hats.toml is absent, or no hat's `applies_when` "
    "matched.)_"
)


def brief_block(hats):
    """The markdown block a decomposition brief embeds: one entry per applicable
    hat carrying its NAME, its question, and the failure class it listens for.

    The question is what the session must answer; `listens_for` rides along
    because a perspective stated without its failure class is an invitation to
    write a paragraph of reassurance."""
    if not hats:
        return NO_HATS
    out = []
    for hat in hats:
        out.append("- **{}** — {}".format(hat["name"], hat["asks"]))
        out.append("  - listens for: {}".format(hat["listens_for"]))
        if "knowledge" in hat:
            out.append("  - knowledge: {}".format(", ".join(hat["knowledge"])))
    return "\n".join(out)


def questions(hats):
    """Just the `asks` texts, in order — for a caller that lays out its own
    block (and for tests that assert a brief faced every applicable hat)."""
    return [h["asks"] for h in hats]


# --- the SN x hat audit -------------------------------------------------------
# WHY THIS EXISTS (owner framing, 2026-08-16). ~27 stakeholder needs against ~8
# tag-gated hats is ~200 applicability permutations, and nobody wades through
# 200 permutations by hand — so the question the `spine-authoring` skill puts at
# SN intake ("which hats should derive from this need, and do its declared tags
# reach them?") gets answered by assumption instead of by looking. The
# arithmetic under that question is mechanical; the answer per row is not. This
# subcommand does the arithmetic and hands the judgement back: it prints the
# reachability matrix as a WORKSHEET, and it reports separately the one class
# that is a DEFECT rather than a question — a tag token no hat's `applies_when`
# anywhere can evaluate, which is the silent typo that makes a need invisible to
# the lens that governs it (the R-2 shape, WI-467).
#
# WARN-FIRST, and the split is deliberate: `--strict` exits nonzero on the
# MECHANICAL findings only. A need waking no conditional hat and a hat reaching
# no need are both PROMPTS — often the right answer is "deliberate" — and a
# check that failed a build over them would be answered by tagging rows to
# silence it, which is the opposite of what the roster is for.
#
# Everything below is private: this module's PUBLIC surface is the contract a
# brief composer calls (`load` / `applicable` / `brief_block` / `questions` /
# the two `context_from_*`), and the audit is a CLI-side reader built on top of
# it, like `_cmd_list`.

# How much of a need's own text the matrix carries. A worksheet needs enough to
# recognise the row, not the row itself.
_NEED_TEXT_WIDTH = 58

# Cell/column stride in the matrix — wide enough for a two-digit column number.
_CELL = "%-3s"


def _clip(text, width):
    """One line of at most `width` characters (`kitlib.spine.clip_line`); a
    missing value reads as empty."""
    return clip_line(str(text or ""), width)


def _needs_path(root, rel=NEEDS_REL):
    """The LIVE needs registry, or the suffix-less stem with its candidate
    carriers spelled out when none is present — so an absent registry names
    both files a reader could create."""
    live = spine_carrier.resolve(Path(root) / rel, spine_carrier.NEED_CARRIERS)
    return live or "{} ({})".format(
        spine_carrier.stem(Path(root) / rel), "/".join(spine_carrier.NEED_CARRIERS)
    )


def _audit_needs(root, rel=NEEDS_REL):
    """Every non-example stakeholder need, through whichever carrier is live.
    `[]` when the registry is absent — a bootstrapped scaffold has a roster
    before it has needs, and an audit with nothing to audit is vacuous, not
    wrong."""
    rows = spine_carrier.load_needs(Path(root) / rel)
    return [r for r in rows if not str(r.get("id") or "").endswith("-000")]


def _need_id(need):
    return str((need or {}).get("id") or "(unnamed)")


def _tag_tokens(roster):
    """Every tag token any hat in `roster` can evaluate — the clause-token
    universe, derived from the roster and never listed by hand."""
    return {
        value
        for hat in roster
        for field, _op, value in hat["condition"][1]
        if field in LIST_FIELDS
    }


def _triggers(hat):
    """The tag tokens that wake ONE hat, sorted. Empty for a hat keyed only on
    scalar fields — which the caller renders as its raw condition instead."""
    return sorted({v for f, _op, v in hat["condition"][1] if f in LIST_FIELDS})


def _split_roster(roster):
    """`(always, conditional)` — the hats every decomposition faces, and the
    ones a need's tags have to reach."""
    always = [h for h in roster if h["condition"][0] == ALWAYS]
    return always, [h for h in roster if h["condition"][0] != ALWAYS]


def _unknown_tag_findings(needs, known):
    """`[(need id, token, nearest known token)]` for every SN tag no clause in
    the known universe can evaluate. The caller passes the roster's clause
    tokens PLUS `NON_ROUTING_TOKENS` as that universe, so a tag retired by an
    `always` ruling is not reported as the typo it is not.

    Scoped to SN tags against the roster's clause tokens, ONE WAY ONLY. The
    mirror scan — roster tokens no need supplies — is deliberately not a finding
    here: work items carry tags too (`context_from_work_item`), so a clause with
    no need behind it is still reachable, and reporting it would be wrong more
    often than right. What the roster's own silence costs is reported instead as
    the per-hat reach count, where it reads as the prompt it is."""
    pool = sorted(known)
    out = []
    for need in needs:
        for token in context_from_need(need).get("tags", []):
            if token in known:
                continue
            near = difflib.get_close_matches(token, pool, n=1, cutoff=0.5)
            out.append((_need_id(need), token, near[0] if near else ""))
    return out


def _audit_columns(always, conditional):
    lines = [
        "ALWAYS — put to every decomposition regardless of tags ({}):".format(
            len(always)
        ),
        "  " + (", ".join(h["name"] for h in always) or "(none)"),
        "",
        "CONDITIONAL HATS — the matrix columns, and the tags that wake each:",
    ]
    for i, hat in enumerate(conditional, 1):
        woken_by = ", ".join(_triggers(hat)) or "(no tag clause) " + hat["applies_when"]
        lines.append("  %2d  %-26s %s" % (i, hat["name"], woken_by))
    return lines


def _audit_matrix(needs, conditional):
    """The worksheet itself: one row per need, one column per conditional hat,
    each cell the REAL evaluation of that hat's condition against that need's
    declared context (never a token intersection — `and`/`or` and the
    scalar-field clauses have to answer as the composer would)."""
    idw = max([len(_need_id(n)) for n in needs] + [6])
    lines = [
        "",
        'MATRIX — "x" = this need\'s declared tags wake that hat; "." = they do not',
        " " * idw
        + "  "
        + "".join(_CELL % i for i in range(1, len(conditional) + 1))
        + " need",
    ]
    for need in needs:
        context = context_from_need(need)
        cells = "".join(
            _CELL % ("x" if evaluate(h["condition"], context) else ".")
            for h in conditional
        )
        lines.append(
            "%-*s  %s %s"
            % (
                idw,
                _need_id(need),
                cells,
                _clip(spine_carrier.folded(need).get("need"), _NEED_TEXT_WIDTH),
            )
        )
    return lines


def _audit_prompts(needs, conditional):
    """The two judgement sections — a need no conditional hat can see, and a hat
    no need can wake. Neither is a finding; both are questions with a name on
    them."""
    silent = [
        n
        for n in needs
        if not any(evaluate(h["condition"], context_from_need(n)) for h in conditional)
    ]
    lines = [
        "",
        "NEEDS WAKING ZERO CONDITIONAL HATS ({}) — deliberate? the adjudicator "
        "answers per row:".format(len(silent)),
    ]
    if not silent:
        lines.append("  (none)")
    for need in silent:
        lines.append(
            "  %-8s %s"
            % (_need_id(need), _clip(spine_carrier.folded(need).get("need"), 66))
        )

    lines += ["", "REACH PER CONDITIONAL HAT (of {} needs):".format(len(needs))]
    for hat in conditional:
        reach = sum(
            1 for n in needs if evaluate(hat["condition"], context_from_need(n))
        )
        flag = (
            "   <- reaches NO need: the R-2 shape — either this repo files no "
            "work in its subject, or the needs it governs are untagged"
            if not reach
            else ""
        )
        lines.append("  %-26s %3d%s" % (hat["name"], reach, flag))
    return lines


def _audit_lines(root):
    """`(lines, hard_findings)` — the whole report, and the count that `--strict`
    keys on."""
    roster = load(root)
    always, conditional = _split_roster(roster)
    needs = _audit_needs(root)

    title = "SN x HAT AUDIT — {} x {}".format(roster_path(root), _needs_path(root))
    if not roster:
        return (
            [
                title,
                "No roster at {}: hats are opted out here (absence IS the "
                "opt-out), so there is nothing to audit.".format(roster_path(root)),
            ],
            0,
        )
    if not needs:
        return (
            [
                title,
                "No stakeholder-need rows: the audit is VACUOUS, not clean — {} "
                "hat(s) are declared and no need row exists to face them.".format(
                    len(roster)
                ),
            ],
            0,
        )

    known = _tag_tokens(roster)
    companions = {
        rel: load(root, rel=rel)
        for rel in COMPANION_ROSTER_RELS
        if roster_path(root, rel).exists()
    }
    elsewhere = set()
    for other in companions.values():
        elsewhere |= _tag_tokens(other)
    findings = _unknown_tag_findings(needs, known | elsewhere | set(NON_ROUTING_TOKENS))

    lines = [
        title,
        "{} need(s); {} hat(s): {} always, {} conditional.".format(
            len(needs), len(roster), len(always), len(conditional)
        ),
        "",
        "UNKNOWN TAG TOKENS — a tag no hat's `applies_when` can evaluate ({}):".format(
            len(findings)
        ),
    ]
    if not findings:
        # Not "every tag reaches a clause": a retired routing token reaches none
        # and is still not a finding. What the zero means is that no tag is
        # UNACCOUNTED for — the notes below say which ones route nothing.
        lines.append("  (none — every declared need tag is accounted for)")
    for nid, token, near in findings:
        lines.append(
            "  %-8s %-18s %s"
            % (nid, token, "nearest known: " + near if near else "no near match")
        )
    # Tokens the LIVE roster cannot evaluate but a companion roster can. Not a
    # finding (see COMPANION_ROSTER_RELS) — but silence about it would hide a
    # tag that is inert HERE, which the adjudicator is entitled to know.
    inert = sorted(
        {
            t
            for n in needs
            for t in context_from_need(n).get("tags", [])
            if t not in known and t in elsewhere
        }
    )
    if inert:
        lines.append(
            "  note: {} declared on need rows but INERT in this roster — "
            "evaluable only in {}.".format(
                ", ".join(inert), ", ".join(sorted(companions))
            )
        )
    # The other inert class (see NON_ROUTING_TOKENS): a tag whose hat was ruled
    # `always`, so it routes nothing ANYWHERE and is subject metadata only. Said
    # out loud for the same reason as the note above — a token doing nothing is
    # the adjudicator's business even when it is not a finding.
    for token, why in sorted(NON_ROUTING_TOKENS.items()):
        rows = [
            _need_id(n) for n in needs if token in context_from_need(n).get("tags", [])
        ]
        if rows and token not in known:
            lines.append(
                "  note: `{}` on {} ROUTES NOTHING — {}; the lens reaches every "
                "need unconditionally and the tag is subject metadata.".format(
                    token, ", ".join(rows), why
                )
            )
    lines.append("")

    lines += _audit_columns(always, conditional)
    lines += _audit_matrix(needs, conditional)
    lines += _audit_prompts(needs, conditional)
    lines += [
        "",
        "The matrix is arithmetic; the tiering is not. A blank row and a "
        "zero-reach hat are QUESTIONS for the adjudicator (spine-authoring "
        "§1(a)), never findings — only the unknown tokens above are.",
    ]
    return lines, len(findings)


# --- CLI (documentation aid; the module is library-first) ---------------------
def _context_from_args(args):
    ctx = {}
    if args.scope:
        ctx["scope"] = args.scope
    if args.kind:
        ctx["kind"] = args.kind
    if args.tag:
        ctx["tags"] = list(args.tag)
    return ctx


def _cmd_list(args):
    roster = load(args.root)
    if not roster:
        print("(no roster at {})".format(roster_path(args.root)))
        return 0
    for hat in roster:
        print(
            "{}\n  when: {}\n  asks: {}\n  listens for: {}".format(
                hat["name"], hat["applies_when"], hat["asks"], hat["listens_for"]
            )
        )
        if "knowledge" in hat:
            print("  knowledge: {}".format(", ".join(hat["knowledge"])))
    return 0


def _cmd_applicable(args):
    chosen = applicable(load(args.root), _context_from_args(args))
    print(brief_block(chosen))
    return 0


def _cmd_audit(args):
    lines, hard = _audit_lines(args.root)
    print("\n".join(lines))
    # WARN-FIRST: the report is informational unless the caller asked for the
    # mechanical class to bite, and even then ONLY that class does.
    return 1 if (args.strict and hard) else 0


def main(argv=None):
    _utf8_console()
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("--root", default=".", help="repo root holding docs/ (default: .)")
    sub = ap.add_subparsers(dest="cmd")

    lst = sub.add_parser("list", help="print the declared roster")
    lst.set_defaults(func=_cmd_list)

    app = sub.add_parser("applicable", help="print the hats a context must face")
    app.add_argument("--scope", default="", help="the decomposition's declared scope")
    app.add_argument("--kind", default="", help="the decomposition's declared kind")
    app.add_argument(
        "--tag", action="append", default=[], help="a declared tag (repeatable)"
    )
    app.set_defaults(func=_cmd_applicable)

    aud = sub.add_parser(
        "audit",
        help="the SN x hat worksheet: which needs reach which conditional hats",
    )
    aud.add_argument(
        "--strict",
        action="store_true",
        help=(
            "exit nonzero on the MECHANICAL findings only (a need tag no clause "
            "can evaluate); the judgement prompts never fail"
        ),
    )
    aud.set_defaults(func=_cmd_audit)

    args = ap.parse_args(argv)
    if not getattr(args, "cmd", None):
        ap.print_help()
        return 2
    try:
        return args.func(args)
    except HatsError as exc:
        print("hats: {}".format(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
