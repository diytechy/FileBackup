"""THE ABSOLUTE-TERM RULE — an absolute in a spine row's obligation that names
no closed domain.

A sibling of `trace_text.py`, and built the same way: a pure text rule, rows in
and advisories out, no file read, and `trace.analyze` its only caller. It lives
beside that module rather than inside it because it carries its own vocabulary
tables and tokenization, and `trace_text.py` is held to an exact size ratchet.

WHY THE RULE EXISTS. An absolute ("never", "always", "every", "any", "no ...")
in a need or a requirement is a promise every child must keep under every
condition. Over a closed domain the system controls ("every row in the registry
resolves", "an id is never re-issued") that is exactly the invariant, finite and
checkable. Over the open world or open time ("in every repo", "never silently")
it is a hidden premise that can be sampled but not tested, and it over-constrains
every design beneath it. The rule cannot tell those apart by meaning, so it
reports the absolutes whose domain the row does not NAME from a closed list, and
the author or reviewer decides: bound it, name the domain, carry the premise as
an assumption row, or record a waiver.

THE MATRIX, one tier per row of `ABSOLUTE_CELLS`:

| tier | cells scanned             | waiver lives in |
|------|---------------------------|-----------------|
| SN   | need, acceptance          | why             |
| SR   | Requirement, AcceptanceCriteria | Rationale |
| LLR  | Detail                    | Rationale       |

A TEST CASE IS NEVER SCANNED: it states a method, not an obligation, and it has
no reason cell a waiver could live in. The reason cells are never scanned
either, because they hold the argument, and an argument may name an absolute in
order to refuse it.

THE WAIVER is the kit's one per-row marker, `recorded waiver: <reason>`, in the
tier's reason cell (`trace_text._WAIVER_RE`, imported rather than restated), so
there is no second grammar. It excuses the whole row, as it does for the
artifact-naming advisories.

THE TOKENIZATION, stated so a finding can be reproduced by hand:

1. A cell is cut into CLAUSES at `;`, `:`, `(`, `)`, `?`, `!`, an em or en dash,
   and a full stop followed by whitespace or the end of the cell (so the dot
   inside `trace.py` or `3.11` cuts nothing). A comma does not end a clause; it
   cuts the clause into SEGMENTS.
2. A segment is cut into WORDS: runs of letters, digits and underscores, joined
   by single hyphens, lower-cased. A hyphenated compound is ONE word, so
   "always-on", "never-by-value" and "all-or-nothing" name a mode and are not
   absolutes; an apostrophe splits ("step's" is "step", "s").
3. An ABSOLUTE is one of the words in `UNIVERSAL_TERMS`, `NEGATIVE_TERMS` or
   `TEMPORAL_TERMS`, matched as a whole word. A negative counts only when it
   OPENS a clause ("No information is encoded by colour alone"): inside one it
   describes one case's input or outcome ("a repo with no commits produces no
   report"), which is a condition, not a universal, and after a comma it is
   usually a list continuing that description ("with no inputs, no lifetime").
   "no" followed by a word in `BOUND_WORDS` ("no more than", "no later than")
   is a bound, and "all" after "at" ("not at all") is emphasis; neither is an
   absolute.
4. Its DOMAIN is, for a universal or a negative, the next `DOMAIN_WINDOW` words of
   its own segment (the noun phrase it quantifies); for "never" and "always",
   which quantify over time and have no following noun, the whole clause, whose
   subject is what the absolute is about ("an id is never re-issued", "a missing
   tool fails, never silently skips").

THE SUPPRESSION PREDICATE. An absolute is satisfied, and not reported, when its
domain contains a word of `CLOSED_DOMAIN_WORDS` or a spine-id-shaped token
(`SR-101`, `IF-252`). That list is the closed one the ruling asks for, in three
kinds: a registry (the registry and its rows and cells, and the spine and
off-spine row nouns every adopter's registries carry: need, requirement,
interface, component, assumption, surrogate, crossing, stakeholder, perspective,
hat, dial, tier, and the two-word "test case" and "work item" from
`CLOSED_DOMAIN_PAIRS`, read as adjacent words), an id space (`id`, and the id
tokens themselves), and a declared set (`declared`, `listed`, `enumerated`,
`registered`, `inventory`).
It is deliberately the kit's vocabulary, not a project's: "every commit" or
"each session" may well be closed in a given project, and saying so is a
one-line classification by a reader, not a word this list should learn.

WHAT STAYS A REVIEW QUESTION. Whether a named domain is really closed — whether
"every declared step" ranges over a list someone actually declares — cannot be
decided mechanically; the spine-authoring skill carries that question. The rule
under-detects a universal phrased without one of its words ("whatever",
"wherever") and a negative buried in a clause or opened after a comma; it is warn-only, so an under-detect costs a missed hint while a looser
match would put standing false accusations in the report.

Contracts: IF-252 — the seam this module declares (process.md §8; row of record
in docs/requirements/interfaces.toml).

Contract IF-252: the absolute-term rule surface `trace.py` imports. Rows in,
    advisories out, and nothing else: no I/O, no git, no filesystem, no argv.
    `absolute_advisories(needs, srs, llrs)` returns warn-only advisory strings,
    one per row and scanned cell, each opening `<tier> <id> <cell> ` and naming
    every unsuppressed absolute with the words that follow it; they never join a
    failure set. `absolute_summary(advisories)` returns zero lines or one: the
    console's count per tier, the list itself being the report's, whose section
    `absolute_report_lines(advisories)` returns as lines. `absolutes(cell)`
    returns one cell's unsuppressed `(term, context)` pairs, the tokenization and
    predicate above. Needs are `spine_carrier.load_needs`' lower-case dicts keyed
    `id`; requirement and design rows are the carrier's column-keyed dicts.
    `ABSOLUTE_CELLS` is the tier matrix, and it has no test-case entry.
"""

import re

try:
    from kitlib.spine import is_example
    from trace_text import _WAIVER_RE
except ImportError:  # pragma: no cover - in-process fallback
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from kitlib.spine import is_example
    from trace_text import _WAIVER_RE

# THE TIER MATRIX: tier -> (id key, scanned cells, reason cell). No test-case
# entry: a test case states a method and has no reason cell to hold a waiver.
# Implements: SR-157, LLR-274
ABSOLUTE_CELLS = {
    "SN": ("id", ("need", "acceptance"), "why"),
    "SR": ("SR-ID", ("Requirement", "AcceptanceCriteria"), "Rationale"),
    "LLR": ("LLR-ID", ("Detail",), "Rationale"),
}

# THE ABSOLUTES, in three kinds by where their domain is read (module docstring,
# tokenization step 3). "each" is here beside "every": the two are one universal
# quantifier, and leaving either out would let a row dodge the rule by synonym.
UNIVERSAL_TERMS = frozenset(
    {"every", "each", "all", "any", "everything", "anything", "everyone", "anyone"}
)
NEGATIVE_TERMS = frozenset({"no", "none", "nothing", "nobody"})
TEMPORAL_TERMS = frozenset({"always", "never"})
BOUND_WORDS = frozenset(
    {
        "more",
        "less",
        "fewer",
        "later",
        "earlier",
        "longer",
        "sooner",
        "greater",
        "larger",
        "smaller",
        "higher",
        "lower",
    }
)

# THE CLOSED LIST the suppression predicate reads (module docstring). Singular
# and plural are both listed rather than stemmed: a stemmer is a second
# tokenization to document, and the list is short.
# Implements: SR-157, LLR-274
CLOSED_DOMAIN_WORDS = frozenset(
    {
        # a registry, its rows and cells
        "registry",
        "registries",
        "row",
        "rows",
        "cell",
        "cells",
        "entry",
        "entries",
        "need",
        "needs",
        "requirement",
        "requirements",
        "interface",
        "interfaces",
        "component",
        "components",
        "assumption",
        "assumptions",
        "surrogate",
        "surrogates",
        "crossing",
        "crossings",
        "stakeholder",
        "stakeholders",
        "perspective",
        "perspectives",
        "hat",
        "hats",
        "dial",
        "dials",
        "tier",
        "tiers",
        # an id space
        "id",
        "ids",
        # a declared set
        "declared",
        "registered",
        "listed",
        "enumerated",
        "inventory",
        "inventoried",
    }
)
# The registry row nouns that take two words, matched as an adjacent pair.
# Implements: SR-157, LLR-274
CLOSED_DOMAIN_PAIRS = frozenset(
    {("test", "case"), ("test", "cases"), ("work", "item"), ("work", "items")}
)
DOMAIN_WINDOW = 6

# How many words of context a finding quotes, the absolute included.
_CONTEXT_WORDS = 4
_CLAUSE_RE = re.compile(r"[;:()?!–—]|\.(?=\s|$)")
_WORD_RE = re.compile(r"[A-Za-z0-9_]+(?:-[A-Za-z0-9_]+)*")
_ID_RE = re.compile(r"\A[a-z]+-\d+\Z")


def _closed(domain):
    """True when a domain's words name a closed list or an id."""
    if any(pair in CLOSED_DOMAIN_PAIRS for pair in zip(domain, domain[1:])):
        return True
    return any(w in CLOSED_DOMAIN_WORDS or _ID_RE.match(w) for w in domain)


def _segments(clause):
    """A clause's comma-separated segments, each a list of lower-cased words."""
    return [[w.lower() for w in _WORD_RE.findall(seg)] for seg in clause.split(",")]


def _domain(segments, s, i):
    """The words absolute `segments[s][i]` ranges over, or None when the word
    is not an absolute where it stands (module docstring, steps 3 and 4)."""
    words = segments[s]
    term = words[i]
    after = words[i + 1] if i + 1 < len(words) else ""
    if term in TEMPORAL_TERMS:
        return [w for seg in segments for w in seg]
    if term in NEGATIVE_TERMS:
        if s != 0 or i != 0 or (term == "no" and after in BOUND_WORDS):
            return None
    elif term not in UNIVERSAL_TERMS or (term == "all" and i and words[i - 1] == "at"):
        return None
    return words[i + 1 : i + 1 + DOMAIN_WINDOW]


def absolutes(cell):
    """One cell's absolutes that name no closed domain, as `(term, context)`
    pairs in reading order, `context` being the term and the words after it.

    Implements: SR-157, LLR-274
    """
    out = []
    for clause in _CLAUSE_RE.split(cell or ""):
        segments = _segments(clause)
        for s, words in enumerate(segments):
            for i, term in enumerate(words):
                domain = _domain(segments, s, i)
                if domain is None or _closed(domain):
                    continue
                out.append((term, " ".join(words[i : i + _CONTEXT_WORDS])))
    return out


def _advisory(tier, rid, cell, found, reason):
    """One row and cell's advisory text, naming each absolute in context."""
    return (
        "{} {} {} states an absolute over no closed domain: {} — bound it, "
        "name its domain from a closed list (a registry, an id space, a "
        "declared set), carry the premise as an assumption, or record "
        "`recorded waiver: <reason>` in `{}` (process.md §4 consistency "
        "review; heuristic, warn-only)".format(
            tier,
            rid,
            cell,
            "; ".join("{!r} ({})".format(t, c) for t, c in found),
            reason,
        )
    )


def _row_advisories(tier, row):
    """One row's advisories, one per scanned cell stating an open absolute;
    none for an id-less row, a placeholder, or a row whose reason cell records
    a waiver."""
    key, cells, reason = ABSOLUTE_CELLS[tier]
    rid = str(row.get(key) or "").strip()
    if not rid or is_example(rid) or _WAIVER_RE.search(row.get(reason) or ""):
        return []
    found = [(cell, absolutes(row.get(cell))) for cell in cells]
    return [_advisory(tier, rid, cell, hits, reason) for cell, hits in found if hits]


def absolute_advisories(needs, srs, llrs):
    """Warn-only: each scanned cell of a real row that states an absolute over
    no closed domain, one advisory per row and cell, unless the row's reason
    cell records a waiver.

    Implements: SR-157, LLR-274
    """
    out = []
    for tier, rows in (("SN", needs), ("SR", srs), ("LLR", llrs)):
        for row in rows:
            out += _row_advisories(tier, row)
    return out


def absolute_report_lines(advisories):
    """The report's section for these advisories: its heading, then one bullet
    per advisory, or a line saying there are none.

    Implements: SR-157, LLR-274
    """
    body = ["- " + a for a in advisories] or ["None. No absolute names an open domain."]
    return ["", "## Absolute-term advisories (warn-only)", ""] + body


def absolute_summary(advisories):
    """The console's one line for the absolute-term advisories, or none.

    Implements: SR-157, LLR-274
    """
    if not advisories:
        return []
    counts = {tier: 0 for tier in ABSOLUTE_CELLS}
    for a in advisories:
        counts[a.split(" ", 1)[0]] += 1
    return [
        "{} absolute-term advisories ({}) — each row and cell is listed in the "
        "report's 'Absolute-term advisories' section".format(
            len(advisories), ", ".join("{} {}".format(t, n) for t, n in counts.items())
        )
    ]
