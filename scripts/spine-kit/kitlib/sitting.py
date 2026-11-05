"""A COMBINED lane-checkpoint sitting: its scope tokens and its verdict sections.

WHY THIS EXISTS (WI-841). A lane can owe several in-lane judgements at one
checkpoint - drifted approved rows (the amendment kind), Drafted rows (the
first-approval kind) and a changed Done-when - and one sitting judges them
all. Its row's `Adjudicates` cell holds `<kind>:<id>` tokens and its verdict
holds one `## <kind>` section per kind. Three readers ask about that shape and
must not disagree: the brief that composes the sitting
(`adjudicate_brief`), the act scopes the merge reads each section's act against
(`acceptance_record`), and the merge-time mint that reads the Done-when
section's own drafts (`intake`). So the token form and the section form have
one home, here, below all three.

Contracts: IF-287 - the seam this module declares (process.md §8; row of
record in docs/requirements/interfaces.toml).

Contract IF-287: a combined sitting's grammar. `SITTING` is the brief class and
    `KINDS` the kinds it composes, in section order; `scopes(tokens)` returns
    `({kind: [ids]}, [malformed tokens])` for `<kind>:<id>` tokens;
    `sections(text)` returns `[(kind, section text)]` in file order for a
    verdict's `## <kind>` headings, `[]` for a single-kind verdict;
    `claim_scope(meta)` is the ONE reader of a claimed row's brief and scope,
    `(brief, {kind: [ids]}, [malformed tokens])`, normalized by
    `declared_brief`/`scope_tokens` exactly as the adjudication route reads
    them; `brief_scope(meta, kind)` is its ids for one kind, `bounds_acts(meta)`
    whether the row bounds its lane's acts, and `malformed_refusal(metas)` the
    merge's refusal of a malformed combined scope; `own_section(text,
    kind, keyword)` is one kind's own part of a verdict, or None when that is
    ambiguous; `GRAMMAR` holds the machine line of each kind it composes
    and its own `SITTING:` line; `parse(text, brief, kinds)` is the ONE
    parser of a verdict file into `{kind: (label, fields)}` (exactly one
    complete machine line per kind; a combined sitting judged against its
    requested kinds), which the coordinator's verdict check and the Done-when
    holds both consume; `requested_path`/`render_requested`/`read_requested`
    are the binding of a sitting's requested kinds beside its verdict;
    `write_binding` is its one writer and `accepted`/`accepted_at` the one
    reader every consumer of a verdict goes through (round 11). A binding may
    also carry the identity cell, `rows = <ID>=sha256:<16 lowercase hex>`
    joined by `;`, naming each row its brief showed with the digest of that
    row's approved text: `render_requested(..., identities)` and
    `write_binding(..., identities)` write it only when identities are given,
    `read_requested` ignores it, `read_identities(text)` returns
    `({id: digest}, None)`, or `(None, reason)` for no cell, a malformed
    token or a repeated id, and `accepted_identities(root, rev, verdict)` is
    the one reader of an ACCEPTED verdict's bound identities, `(None,
    reason)` for a verdict `accepted_at` does not read as accepted. A dispute
    binding may also carry the findings-file record cell, `findings_file =
    <repo-relative path>`, naming the findings file its brief was composed
    over: `render_requested(..., findings_file)` and `write_binding(...,
    findings_file)` write it only when a path is given, `read_requested`
    ignores it, and `read_findings_file(text)` returns the path, or None for
    no cell or an empty one; `judged_rows(parsed)` is the ONE reader of the
    rows an accepted verdict authorizes an act on - an APPROVE row, a CLARITY
    row, and a MEANING row only with its bless mark - which the merge's
    backing checks and the act assembler both read. `review_line(text)`
    is the ONE reader of a review round's `VERDICT:` line, which the attended
    filing boundary and the merge gate's round reader both consume. Pure
    functions over text, except `write_binding` (one file) and `accepted_at`
    (git reads).
"""

import re

from .git import git_out
from .registry import adjudicates_tokens
from .verdict import blessed_rows, row_rulings

__all__ = [
    "SITTING",
    "KINDS",
    "GRAMMAR",
    "DONE_WHEN_OUTCOMES",
    "scopes",
    "sections",
    "own_section",
    "declared_brief",
    "scope_tokens",
    "claim_scope",
    "brief_scope",
    "bounds_acts",
    "malformed_refusal",
    "line_refusal",
    "REVIEW",
    "review_line",
    "named_kinds",
    "sitting_refusal",
    "parse",
    "requested_path",
    "render_requested",
    "read_requested",
    "read_identities",
    "read_findings_file",
    "REQUESTED_SUFFIX",
    "OUTCOMES",
    "write_binding",
    "accepted",
    "accepted_part",
    "accepted_at",
    "accepted_identities",
    "judged_rows",
    "unaccepted_refusal",
    "REVIEWS",
    "branch_verdicts",
    "uncovered_refusal",
]

SITTING = "combined"
KINDS = ("amendment", "first-approval", "done-when")
# A combined verdict's section heading: a KIND-FORM heading (a lower-case,
# hyphenated brief-class token) alone on its line - any kind, not only the
# composable three, so an unrequested section is seen and refused (round 9).
# Prose headings (`## Dispositions`) are capitalised and never match.
_HEADING_RE = re.compile(r"^## ([a-z][a-z0-9-]*)[ \t]*$", re.M)


def scopes(tokens):
    """`({kind: [ids]}, [malformed tokens])` for a combined row's
    `<kind>:<id>` tokens, a kind being one of `KINDS`.

    Implements: SR-232, LLR-310
    """
    found, bad = {}, []
    for token in tokens:
        kind, sep, rid = str(token).strip().partition(":")
        if sep and kind in KINDS and rid.strip():
            found.setdefault(kind, []).append(rid.strip())
        else:
            bad.append(str(token))
    return found, bad


def sections(text):
    """`[(kind, section text)]` in file order for a combined verdict's
    kind-form `## <kind>` sections (any kind, requested or not), `[]` for a
    verdict that has none; a kind may repeat,
    which the caller refuses as ambiguous.

    Implements: SR-232, LLR-310
    """
    parts = _HEADING_RE.split(text or "")
    return list(zip(parts[1::2], parts[2::2]))


def own_section(text, kind, keyword):
    """`kind`'s own part of a verdict: the whole text for a single-kind
    verdict, its one `## <kind>` section for a combined one; None when that is
    ambiguous - no such section or more than one, or a `<keyword>:` machine
    line under another kind's heading.

    Implements: SR-232, LLR-310
    """
    found = sections(text)
    if not found:
        return text
    own = [body for k, body in found if k == kind]
    stray = [k for k, body in found if k != kind and _keyword_lines(body, keyword)]
    return own[0] if len(own) == 1 and not stray else None


def declared_brief(value):
    """A claimed row's brief cell as the adjudication route reads it: stripped
    and lower-cased, `""` when it declares none. The one normalization the
    route's composition and the merge's admission share (WI-849, Sol r2).

    Implements: SR-232, LLR-310
    """
    return str(value or "").strip().lower()


def scope_tokens(cell):
    """The tokens of a registry row's PARSED `Adjudicates` cell - the column's
    `;`-joined string `kitlib.registry.adjudicates_tokens` produced - each
    stripped, empties dropped. A raw frontmatter value is never read here: it
    is parsed by `adjudicates_tokens` alone (WI-849, Sol r3).

    Implements: SR-232, LLR-310
    """
    return [t.strip() for t in str(cell or "").split(";") if t.strip()]


def claim_scope(meta):
    """THE ONE READER of a claimed row's brief and scope (WI-849, Sol r2):
    `(brief, {kind: [ids]}, [malformed tokens])` from its frontmatter, read
    with the route's normalization; its tokens are
    `kitlib.registry.adjudicates_tokens`', the parser the route's row loader
    uses, so a value it refuses raises here too (Sol r3). A combined sitting
    splits its `<kind>:<id>` tokens and RETURNS the malformed ones, which the
    route refuses to compose and the merge refuses (`malformed_refusal`); any
    other brief scopes its whole token list to itself; no brief scopes nothing.

    Implements: SR-232, LLR-310
    """
    brief = declared_brief(meta.get("brief"))
    tokens = adjudicates_tokens(meta, meta.get("id") or "a claimed row")
    if brief == SITTING:
        return (brief, *scopes(tokens))
    return brief, ({brief: tokens} if brief else {}), []


def brief_scope(meta, kind):
    """The row ids a claimed row's frontmatter scopes to an act of `kind` -
    its whole scope for a row of that brief, its `kind:` tokens for a combined
    sitting - or None when it scopes nothing to `kind` (`claim_scope`).

    Implements: SR-232, LLR-310
    """
    return claim_scope(meta)[1].get(kind)


def bounds_acts(meta):
    """Does this claimed row's frontmatter RECORD a scope that bounds its
    lane's approval acts: an adjudication-kind row (its scope may be empty,
    which bounds every act out), a row scoping a first approval or an
    amendment, or a combined row with a malformed token? The merge slot asks
    it of every claimed row, so one such row bounds the whole lane (WI-849).

    Implements: SR-232, LLR-310
    """
    _brief, found, bad = claim_scope(meta)
    kind = declared_brief(meta.get("safety_class"))
    return (
        kind == "adjudication"
        or bool(bad)
        or any(k in found for k in ("first-approval", "amendment"))
    )


def malformed_refusal(metas):
    """Why a lane's claim cannot be judged, or None: a claimed combined row's
    scope holds a token that is not `<kind>:<id>` with a composable kind. The
    route refuses to compose such a row, so the merge refuses it too rather
    than drop the token and read the lane as unbounded.

    Implements: SR-232, LLR-310
    """
    for name, meta in metas:
        bad = claim_scope(meta)[2]
        if bad:
            return (
                "the claimed row {} scopes {}, not `<kind>:<id>` with a kind of "
                "{}; the merge cannot know which rows its acts may reach; nothing "
                "was merged".format(
                    name, ", ".join(repr(b) for b in bad), ", ".join(KINDS)
                )
            )
    return None


# --- the sitting's verdict grammar and its ONE parser (WI-841 rounds 9, 10) ---
#
# Parse, don't validate: `parse` turns a verdict file into the structured
# verdict every reader consumes - the coordinator's verdict check
# (`adjudicate_brief.verdict_refusal`) and the Done-when holds' covering reader
# (`kitlib.done_when`) - so no reader reads raw machine lines on its own. A
# verdict carries EXACTLY ONE complete machine line per kind, and a combined
# sitting is judged against the kinds its brief REQUESTED, bound beside the
# verdict at reservation (`requested_path`), never against its own claim.
DONE_WHEN_OUTCOMES = ("CLARITY", "BLESSED", "SUCCESSOR")
GRAMMAR = {
    "amendment": ("VERDICT", ("MEANING", "CLARITY"), ("rows",)),
    "first-approval": ("OUTCOME", ("APPROVE", "RETURN"), ("rows",)),
    "done-when": ("DONE-WHEN", DONE_WHEN_OUTCOMES, ("changes", "digest")),
    SITTING: ("SITTING", ("JUDGED",), ("kinds",)),
}
# The binding: a file beside the verdict, written by the entry point at
# reservation, which the adjudicator's rewrite of the verdict cannot touch.
REQUESTED_SUFFIX = ".requested"


def requested_path(verdict_path):
    """The binding file's path for a verdict path.

    Implements: SR-232, LLR-310
    """
    return str(verdict_path) + REQUESTED_SUFFIX


# The OUTCOME a binding records: `pending` from reservation until the route
# that ran the call records `accepted` (its own validation passed) or `failed`.
OUTCOMES = ("pending", "accepted", "failed")


def render_requested(
    brief, kinds, outcome="pending", identities=None, findings_file=None
):
    """The binding's text: the brief class, the kinds it requested and the
    call's recorded outcome; when `findings_file` is given, the record of the
    findings file a dispute brief was composed over; and, when `identities`
    (`{row id: digest}`) is given, the identity cell naming each judged row's
    approved-text digest.

    Implements: SR-232, SR-178, LLR-310, LLR-359
    """
    text = "brief = {}\nkinds = {}\noutcome = {}\n".format(
        brief, ";".join(kinds), outcome
    )
    if findings_file:
        text += "{} = {}\n".format(FINDINGS_FILE_CELL, findings_file)
    if identities:
        text += "{} = {}\n".format(
            IDENTITY_CELL,
            ";".join(
                "{}={}".format(rid, identities[rid]) for rid in sorted(identities)
            ),
        )
    return text


def _cells(text):
    """A binding's `key = value` cells, keyed by the text before each line's
    first ` = `; a line without one is not a cell."""
    return dict(
        line.split(" = ", 1) for line in (text or "").splitlines() if " = " in line
    )


def read_requested(text):
    """`(brief, kinds, outcome)` from a binding's text, or None when it is not
    one; a binding recording no outcome reads `pending`.

    Implements: SR-232, LLR-310
    """
    cells = _cells(text)
    brief, kinds = cells.get("brief", "").strip(), cells.get("kinds", "").strip()
    if not brief or not kinds:
        return None
    outcome = cells.get("outcome", "pending").strip()
    return brief, tuple(k for k in kinds.split(";") if k), outcome


# The binding's identity cell: one `<row id>=sha256:<16 lowercase hex>` token
# per row the brief showed, `;`-joined.
IDENTITY_CELL = "rows"
_IDENTITY_TOKEN = re.compile(r"([A-Z]+-[0-9]+)=(sha256:[0-9a-f]{16})")
# A dispute binding's record of the findings file its brief was composed over.
FINDINGS_FILE_CELL = "findings_file"


def read_findings_file(text):
    """The repo-relative path a dispute binding records as the findings file
    its brief was composed over, or None when it carries no record or an
    empty one. Cells come from `_cells`, the one cell reader it shares with
    `read_requested`.

    Implements: SR-232, LLR-310
    """
    return _cells(text).get(FINDINGS_FILE_CELL, "").strip() or None


def read_identities(text):
    """`({row id: digest}, None)` from a binding's identity cell, or `(None,
    reason)`: no cell, more than one, a token that is not `<ID>=sha256:<16
    lowercase hex>`, or an id named twice. A malformed cell binds no text.

    Implements: SR-178, LLR-359
    """
    prefix = IDENTITY_CELL + " = "
    cells = [
        line[len(prefix) :]
        for line in (text or "").splitlines()
        if line.startswith(prefix)
    ]
    if len(cells) != 1:
        return None, (
            "the binding carries no identity cell"
            if not cells
            else "the binding carries {} identity cells".format(len(cells))
        )
    out = {}
    for token in cells[0].strip().split(";"):
        match = _IDENTITY_TOKEN.fullmatch(token.strip())
        if not match:
            return None, "the identity cell carries a malformed token {!r}".format(
                token
            )
        if match.group(1) in out:
            return None, "the identity cell names {} twice".format(match.group(1))
        out[match.group(1)] = match.group(2)
    return out, None


def line_refusal(grammar, text, where):
    """Why `text` does not carry the machine line `grammar` (keyword, labels,
    fields) declares, or None - the first such line; `parse` is the reader
    that also requires it to be the only one.

    Implements: SR-232, LLR-310
    """
    return _machine_lines(grammar, text, where)[1]


def _keyword_lines(text, keyword):
    """Every PHYSICAL line of `text` whose first token is `keyword:`, as the
    whitespace-split tokens after the colon - complete or not, a bare keyword
    included. Strictly one line at a time: nothing here spans a newline
    (WI-841 round 19), so a label carried onto the next line is a bare keyword
    line followed by prose, never a machine line."""
    out = []
    for line in (text or "").splitlines():
        head, sep, rest = line.strip().partition(":")
        if sep and head == keyword:
            out.append(rest.split())
    return out


def _machine_line(tokens, fields):
    """`(label, {field: value})` for one keyword line's tokens: its first
    token, and each `field=value` token naming a declared field."""
    pairs = [t.partition("=") for t in tokens[1:]]
    values = {k: v for k, sep, v in pairs if sep and v and k in fields}
    return (tokens[0] if tokens else ""), values


def _incomplete(grammar, label, values, where):
    """Why one parsed keyword line is not complete, or None."""
    keyword, labels, fields = grammar
    if label not in labels:
        return "{} says `{}: {}` - its label is not one of {}".format(
            where, keyword, label or "(nothing)", "|".join(labels)
        )
    missing = [f for f in fields if f not in values]
    if missing:
        return "{} says `{}: {}` but omits {}".format(
            where, keyword, label, ", ".join(missing)
        )
    return None


def _machine_lines(grammar, text, where):
    """`([(label, {field: value})], refusal)`: every `grammar` keyword line in
    `text` parsed from its own physical line, and why ANY of them is not
    complete (no line at all, a bare keyword, a label outside the enum, or a
    missing `field=value` token), or None."""
    keyword, _labels, fields = grammar
    parsed = [_machine_line(t, fields) for t in _keyword_lines(text, keyword)]
    if not parsed:
        return [], "{} carries no `{}:` machine line".format(where, keyword)
    refusals = (_incomplete(grammar, *line, where) for line in parsed)
    return parsed, next((r for r in refusals if r), None)


# A review round's verdict line (WI-870): keyword, labels, fields. Not a sitting
# kind, so it is not in `GRAMMAR`; its count is a whole number in ASCII digits.
REVIEW = ("VERDICT", ("APPROVE", "CHANGES-REQUESTED"), ("findings",))
_DIGITS = re.compile(r"[0-9]+")
_REVIEW_FORM = "{}: <{}> {}=<digits>".format(
    REVIEW[0], "|".join(REVIEW[1]), REVIEW[2][0]
)


def _folded_lines(text, keyword):
    """Every physical line of `text` whose keyword, compared case-insensitively
    and stripped, is `keyword`, each stripped."""
    want = keyword.casefold()
    return [
        line.strip()
        for line in (text or "").splitlines()
        if line.partition(":")[1] and line.partition(":")[0].strip().casefold() == want
    ]


def review_line(text, where="it"):
    """THE ONE READER of a review round's verdict line (WI-870): `((label,
    count), None)`, or `(None, refusal)`. Exactly one physical line of `text`
    may name the `VERDICT` keyword, in any case; it is read by the shared
    per-line reader (a label of the enum, `findings` present), and must then
    be exactly `VERDICT: <label> findings=<digits>`; that exact-form comparison
    refuses anything else on the line. The attended filing boundary refuses to file what this
    refuses, and the merge gate reads it as no verdict.

    Implements: SR-232, LLR-310
    """
    keyword = REVIEW[0]
    lines = _folded_lines(text, keyword)
    if len(lines) != 1:
        return None, (
            "{} carries {} {} lines, not exactly one".format(where, len(lines), keyword)
            if lines
            else "{} carries no {} line".format(where, keyword)
        )
    found, refusal = _machine_lines(REVIEW, lines[0], where)
    if found and refusal:
        return None, refusal
    label, fields = found[0] if found else ("", {})
    count = fields.get(REVIEW[2][0], "")
    canonical = "{}: {} {}={}".format(keyword, label, REVIEW[2][0], count)
    if lines[0] != canonical or not _DIGITS.fullmatch(count):
        return None, "{} carries the {} line `{}`, which is not exactly `{}`".format(
            where, keyword, lines[0], _REVIEW_FORM
        )
    return (label, int(count)), None


def _one_line(kind, body, where):
    """`((label, fields), None)` for the ONE complete `kind` machine line in
    `body`, or `(None, refusal)`; a second line of the kind refuses."""
    found, refusal = _machine_lines(GRAMMAR[kind], body, where)
    if refusal:
        return None, refusal
    if len(found) != 1:
        return None, "{} carries {} `{}:` lines; a verdict carries exactly one".format(
            where, len(found), GRAMMAR[kind][0]
        )
    return found[0], None


def named_kinds(text):
    """The kinds a text's `SITTING:` line names, in its order; () when it
    carries no such line or no `kinds=` field. Read off a composed brief, it
    is the kinds the sitting REQUESTED.

    Implements: SR-232, LLR-310
    """
    for tokens in _keyword_lines(text, "SITTING")[:1]:
        pairs = (t.partition("=") for t in tokens[1:])
        named = [v for k, sep, v in pairs if sep and k == "kinds"]
        return tuple(k for k in (named or [""])[0].split(";") if k)
    return ()


def parse(text, brief, kinds, where=""):
    """THE ONE PARSER: `({kind: (label, fields)}, None)` for a valid verdict
    of `brief` requesting `kinds`, or `(None, refusal)`. A single-kind brief's
    verdict carries no kind-form section and exactly one complete machine
    line of its kind. A combined sitting's names exactly the requested kinds
    in its one `SITTING:` line, holds exactly one `## <kind>` section for each
    and no other (an unrequested section refuses), and each section holds
    exactly one complete line of its own kind and none of another's, so one
    invalid section refuses the whole sitting (SR-232).

    Implements: SR-232, LLR-310
    """
    if brief != SITTING and brief not in GRAMMAR:
        return None, "{}: no sitting grammar for brief {!r}".format(where, brief)
    if brief != SITTING:
        if sections(text):
            return (
                None,
                "{}: a single-kind verdict carries no `## <kind>` section".format(
                    where
                ),
            )
        line, why = _one_line(brief, text, where)
        why = why or _keyword_count_refusal(text, {brief: 1}, where)
        return (None, why) if why else ({brief: line}, None)
    return _parse_sitting(text, kinds, where)


def _keyword_count_refusal(text, expected, where):
    """Why `text`'s machine keyword lines are not exactly `expected` -
    `{kind: count}`, every other sitting kind's (and the sitting's own,
    unless named) expected zero - counted per physical line over the WHOLE
    text, complete or not; or None. So a keyword line outside every section,
    or another kind's keyword inside one, invalidates the verdict."""
    for kind, (keyword, _labels, _fields) in GRAMMAR.items():
        found = len(_keyword_lines(text, keyword))
        if found != expected.get(kind, 0):
            return (
                "{} carries {} `{}:` line(s), expected {}: a verdict carries "
                "exactly one complete machine line per kind it judges".format(
                    where, found, keyword, expected.get(kind, 0)
                )
            )
    return None


def _parse_sitting(text, kinds, where):
    """`parse` for a combined sitting judged against requested `kinds`."""
    if not kinds:
        return None, (
            "{}: a combined verdict is judged against the kinds its sitting "
            "requested, and none were given".format(where)
        )
    _line, refusal = _one_line(SITTING, text, where)
    want, named = sorted(set(kinds)), named_kinds(text)
    if refusal or sorted(named) != want:
        return None, refusal or "{} names kinds={} but the sitting requested {}".format(
            where, ";".join(named) or "(none)", ";".join(want)
        )
    found = sections(text)
    headed = sorted(kind for kind, _body in found)
    if headed != want:
        return None, "{} requested {} but carries the section(s) {}".format(
            where, ";".join(want), ", ".join("## " + k for k in headed) or "(none)"
        )
    lines, refusal = _parse_sections(found, where)
    expected = dict.fromkeys([SITTING, *want], 1)
    refusal = refusal or _keyword_count_refusal(text, expected, where)
    return (None, refusal) if refusal else (lines, None)


def _parse_sections(found, where):
    """Each section's one complete own-kind line, none of another kind's."""
    lines = {}
    for kind, body in found:
        at = "{} (## {})".format(where, kind)
        line, refusal = _one_line(kind, body, at) if kind in GRAMMAR else (None, None)
        stray = [
            g[0]
            for k, g in GRAMMAR.items()
            if k not in (kind, SITTING) and _keyword_lines(body, g[0])
        ]
        if refusal or line is None or stray:
            return None, refusal or "{}: carries {} line(s) of another kind".format(
                at, "/".join(stray) or "no sitting grammar for this kind's"
            )
        lines[kind] = line
    return lines, None


def sitting_refusal(text, where, kinds):
    """Why a combined sitting's verdict is not acceptable against its
    requested `kinds`, or None: `parse`'s refusal.

    Implements: SR-232, LLR-310
    """
    return parse(text, SITTING, kinds, where)[1]


# --- acceptance is a RECORDED fact (WI-841 round 11) --------------------------


def write_binding(
    verdict_path,
    brief,
    kinds,
    outcome,
    exclusive=False,
    identities=None,
    findings_file=None,
):
    """THE one writer of a verdict's binding: its brief class, requested kinds
    and recorded outcome, beside the verdict, its identity cell when
    `identities` is given, and its findings-file record when `findings_file`
    is given. `exclusive` creates it (the entry point's
    reservation, which refuses an existing one); otherwise it overwrites,
    which is how the route that ran the call records `accepted` or `failed`.
    Raises OSError as `open` does; the caller says what it means.

    Implements: SR-232, SR-178, LLR-310, LLR-359
    """
    mode = "x" if exclusive else "w"
    with open(requested_path(verdict_path), mode, encoding="utf-8", newline="\n") as fh:
        fh.write(render_requested(brief, kinds, outcome, identities, findings_file))


def accepted(text, binding_text):
    """THE one reader every consumer of a verdict file goes through:
    `{kind: (label, fields, body, rows)}` (`rows`: the part's per-row
    rulings, `kitlib.verdict.row_rulings`) for a verdict whose binding records it
    ACCEPTED by the route that ran the call and which `parse` reads as valid
    against that binding's brief and requested kinds; None for anything else -
    no binding, a pending or failed outcome, an invalid verdict, or a brief
    class this grammar does not cover (which is simply no blessing of these
    kinds, never an error). A verdict's acceptance is the recorded fact, never
    an inference from its text.

    Implements: SR-232, LLR-310
    """
    bound = read_requested(binding_text)
    if not bound or bound[2] != "accepted":
        return None
    brief, kinds, _outcome = bound
    lines, _refusal = parse(text or "", brief, kinds)
    if not lines:
        return None
    bodies = dict(sections(text)) if brief == SITTING else {brief: text}
    return {
        k: (label, fields, bodies.get(k, ""), row_rulings(bodies.get(k, ""), k))
        for k, (label, fields) in lines.items()
    }


def accepted_part(text, binding_text, kind):
    """`kind`'s own text in an accepted verdict (`accepted`), or None.

    Implements: SR-232, LLR-310
    """
    found = accepted(text, binding_text) or {}
    return found[kind][2] if kind in found else None


def accepted_at(root, rev, verdict_path):
    """`accepted` for the verdict file at `verdict_path` and its binding, both
    read at the commit `rev` (None: the index) - the git side of the one
    reader, so no consumer fetches a verdict and decides about it alone.

    Implements: SR-232, LLR-310
    """
    return accepted(*_texts_at(root, rev, verdict_path)) if verdict_path else None


def _texts_at(root, rev, verdict_path):
    """The verdict's text and its binding's, each read at the commit `rev`
    (None: the index), or None where git shows nothing."""
    at = "" if rev is None else rev
    return [
        git_out(root, ["show", "{}:{}".format(at, rel)])
        for rel in (verdict_path, requested_path(verdict_path))
    ]


def accepted_identities(root, rev, verdict_path):
    """`({row id: digest}, None)`: the identities the binding of an ACCEPTED
    verdict records, both read at the commit `rev`, or `(None, reason)`. A
    verdict `accepted` does not read as accepted binds nothing, and a binding
    with no identity cell, or a malformed one, binds no text
    (`read_identities`).

    Implements: SR-178, LLR-359
    """
    texts = _texts_at(root, rev, verdict_path) if verdict_path else [None, None]
    if not accepted(*texts):
        return None, "the verdict {} is not accepted at {}".format(
            verdict_path, "the index" if rev is None else rev
        )
    return read_identities(texts[1])


# The rulings that authorize each kind's act on a row: a first approval's
# APPROVE flips it, an amendment's CLARITY re-attests it, and so does its
# MEANING, but only on a row the part marks `[MEANING+BLESS]` (`judged_rows`).
# The held-rung CLARITY-only rule is acceptance_record's, on top of this.
_AUTHORIZING = {"first-approval": ("APPROVE",), "amendment": ("MEANING", "CLARITY")}
# The sentence a refusal carries when an amendment row it names is
# unauthorized; a refusal naming no such row omits it.
_BLESS_REMEDY = (
    "An amendment's MEANING row authorizes a re-attestation only when its "
    "verdict marks it `[MEANING+BLESS]`: re-sit that row."
)


def judged_rows(parsed):
    """`{(kind, row)}` an accepted parsed verdict (`accepted`) rules in a way
    that authorizes that kind's act on the row: the ONE reader of what an
    accepted verdict authorizes an act on, which the merge's backing checks
    and the act assembler both read. An APPROVE row, a CLARITY row, and an
    amendment's MEANING row only when its part marks it blessed
    (`kitlib.verdict.blessed_rows`, which reads a row tagged two ways as
    unblessed).

    Implements: SR-232, LLR-310
    """
    out = set()
    for kind, part in (parsed or {}).items():
        blessed = blessed_rows(part[2]) if kind == "amendment" else frozenset()
        out |= {
            (kind, rid)
            for rid, ruling in part[3].items()
            if ruling in _AUTHORIZING.get(kind, ())
            and (ruling != "MEANING" or rid in blessed)
        }
    return out


def _named_line(root, rev, act):
    """The refusal line for one act naming a verdict, or None: the verdict is
    not accepted, or it does not authorize a row the act re-attests."""
    verdict = str(act["verdict"]).strip()
    parsed = accepted_at(root, rev, verdict)
    if not parsed:
        return "  {}".format(verdict)
    judged = judged_rows(parsed)
    rows = [str(r) for r in act.get("reattested") or []]
    unjudged = [r for r in rows if ("amendment", r) not in judged]
    if not unjudged:
        return None
    return "  {} (does not authorize {})".format(verdict, ", ".join(unjudged))


def unaccepted_refusal(root, rev, acts):
    """Why a merge must refuse the approval acts it adds, or None: EVERY act
    that names a verdict must name one `accepted_at` reads as accepted at
    `rev` AND that authorizes each row the act re-attests (`judged_rows`;
    round 16). An act naming no verdict is `uncovered_refusal`'s; acts
    already on trunk are never passed here.

    Implements: SR-232, LLR-310
    """
    named = (a for a in acts if isinstance(a, dict) and a.get("verdict"))
    lines = [line for line in (_named_line(root, rev, act) for act in named) if line]
    if not lines:
        return None
    # Only an accepted verdict's "(does not authorize ...)" line names an
    # amendment row a mark could authorize; an unaccepted verdict's does not.
    unmarked = any(" (does not authorize " in line for line in lines)
    return (
        "the adjudication's act names a verdict no route recorded ACCEPTED, or "
        "one that does not authorize the rows it re-attests; nothing was "
        "merged:\n{}\nRemedy: re-sit the adjudication through the loop or the "
        "coordinator's entry point, which records its outcome beside the "
        "verdict, and name the accepted verdict that authorizes those "
        "rows.{}".format("\n".join(lines), " " + _BLESS_REMEDY if unmarked else "")
    )


# The review records a lane's verdicts and their bindings live under.
REVIEWS = "docs/reviews"
# Which adjudication kind an act-ledger entry's key needs: a flip is a first
# approval's act, a re-attestation an amendment's.
_ACT_KINDS = (("approved", "first-approval"), ("reattested", "amendment"))


def branch_verdicts(root, base, rev):
    """The verdict paths whose bindings the branch changed between `base` and
    `rev` - the adjudications this lane ran, through either route.

    Implements: SR-232, LLR-310
    """
    args = ["diff", "--name-only", "--no-renames", base, rev, "--", REVIEWS]
    changed = (git_out(root, args) or "").splitlines()
    return sorted(
        p[: -len(REQUESTED_SUFFIX)] for p in changed if p.endswith(REQUESTED_SUFFIX)
    )


def uncovered_refusal(root, base, rev, acts):
    """Why a merge must refuse the approval acts it adds, or None, WHETHER OR
    NOT an act names a verdict (WI-841 rounds 14, 16): every ROW an added act
    flips must be ruled APPROVE in a first-approval part, and every row it
    re-attests ruled CLARITY, or MEANING with the bless mark, in an amendment
    part (`judged_rows`), of an ACCEPTED
    verdict (`accepted_at`) among the bindings this branch carries
    (`branch_verdicts`), single-kind or combined. An act's authority is the
    judgement of ITS rows: an accepted verdict over other rows authorizes
    nothing here. Each unauthorized row is named with its kind,
    and the bless-mark remedy follows only when one is an amendment row.

    Implements: SR-232, LLR-310
    """
    needed = sorted(
        {
            (kind, str(rid))
            for act in acts
            if isinstance(act, dict)
            for key, kind in _ACT_KINDS
            for rid in act.get(key) or []
        }
    )
    judged = set()
    for verdict in branch_verdicts(root, base, rev) if needed else ():
        judged |= judged_rows(accepted_at(root, rev, verdict))
    missing = [(kind, rid) for kind, rid in needed if (kind, rid) not in judged]
    if not missing:
        return None
    amended = any(kind == "amendment" for kind, _rid in missing)
    return (
        "the adjudication's act takes rows no ACCEPTED verdict in this branch "
        "authorizes (an act's authority is the judgement of its own rows, "
        "named or not); nothing was merged:\n{}\nRemedy: re-sit the "
        "adjudication of those rows through the loop or the coordinator's "
        "entry point, whose binding records it accepted.{}".format(
            "\n".join(
                "  {} ({}) is authorized by no accepted verdict".format(r, k)
                for k, r in missing
            ),
            " " + _BLESS_REMEDY if amended else "",
        )
    )
