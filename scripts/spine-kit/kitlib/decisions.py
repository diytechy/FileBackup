"""The DELEGATED-DECISIONS RECORD: what one delegated run tells the owner about
the calls it made on the owner's behalf — its path, its format, which closes
owe one, and the note a delegated session is handed.

WHY A RECORD AND NOT AN EXIT (SR-225). A delegated session decides things the
owner would want a second look at: too settled for a pending open item, which
blocks by design, and not settled enough for the log, which records settled
decisions. Such calls had no home, and a prose "decisions for review" file
degraded within one session: the fields it asked for were left out as soon as
nothing read them. So the record is structural — one table per decision, each
carrying four REQUIRED disclosure fields — and it is a RECORD of calls already
made, never a route for work: a call the owner must make, or an act that cannot
be undone, still goes to the owner through the process's exits.

ONE FILE PER RUN (`DECISIONS_DIR/<run>.toml`), named by the lane's branch, so
the directory is never a merge-conflict surface, the way the log's per-branch
fragments are not. A branch name's `/` becomes `-`, so a run is always ONE
file, never a directory; nothing else is rewritten. A name carrying `#` (the
citation's delimiter) or a character git refuses has NO record: `record_path`
raises rather than fold it into another name's file, and the merge slot reads
that as an absent record (WI-818 dispute 1). The residue is stated, not
claimed away: `a/b` and `a-b`, and a branch name reused by a second lane,
share one record.

THE OWNER'S VERDICT IS ONE KEY, AND AN OVERRULE IS ACTED ON (WI-818). A
decision is a direction already taken, so the owner does not approve it: the
owner CONFIRMS it or OVERRULES it (owner, 2026-10-04). Each entry may carry
`owner`, set in place to `confirmed` or `overruled`; an absent key is NOT YET
SEEN. `owner_state` is the one reading, and any other value reads as not yet
seen AND is a format finding, so a typo never hides a decision. The retired
`reviewed` key (WI-790) is a format finding wherever it appears and is never
read: an entry still carrying it reads as not yet seen, whatever `owner` says.
The migrator (`migrate_text`, run by `migrate_decisions.py`) rewrites it, and
no reader keeps a legacy path. An
overrule states the direction instead in the `review` note, so an overruled
entry with a blank note is a finding. The generated owner surface lists every
entry not yet seen under "Decisions to review" and every overruled entry
under its own heading beside the work item citing it (`review_queue`).

An overrule is coupled to work at the COMMIT, the way a ruled open item is
coupled to its citing row (OI-102 Q3): the commit that sets an entry
`overruled` files or amends, in the same diff, a queued or active work item
whose spec cites the entry as `docs/decisions/<run>.toml#D-NNN` (`citation`,
`citations`, `newly_overruled`, and the coupling itself, `overrule_sync_lines`,
handed the two trees as readers; the git read is the ruling sync's, in
`acceptance_record`, which asks it of the same diff). Amending the queued row the decision was scoped to is
enough; nothing has to be minted. The coupling reads the `owner` key as
written, and FAILS CLOSED: a record the commit's tree carries but cannot parse
is refused, since an unreadable verdict is never "no overrule". Who sets the key stays a convention: git
cannot tell the owner's commit from an agent's without a marker, which the
owner has ruled out.

WHAT IS JUDGED, AND HOW LOUDLY. The merge slot refuses a close that OWES a
record and carries none (`owed`), because a missing record is silence about
every call the run made. Every close owes one, a partial close included: a lane
the machinery closed with no session present is refused too, and the refusal is
a hold for a person to write the record. A malformed entry — a missing or blank
disclosure field, a non-text value, a hoist naming an entry the record lacks —
is REPORTED and never refused (`record_findings`; the one refusal is the
overrule sync's unparseable record above): the record exists, the owner
can read what is there, and refusing the merge over one field would strand
finished work for a reporting defect. An entry numbered `-000` is the template's
example and is never judged, so the template stays copy-ready.

A kitlib module: stdlib only, importing nothing.

Contracts: IF-255, IF-256 — the seams this module declares (process.md §8; rows
of record in docs/requirements/interfaces.toml).

Contract IF-255: the delegated-decisions record, as a FILE. One TOML file per
    delegated run at `docs/decisions/<run>.toml`, a `/` in the run's name
    becoming `-` and no other character rewritten (a name carrying `#` or a
    character git refuses has no record), committed on the lane's branch by the
    session that made the calls and read off that branch's tree by the merge
    slot. A top-level `high_risk` list of entry ids names the entries the
    writer judges deserve the owner's eyes first (empty when none). Each
    decision is a table
    `[decision.D-<digits>]` carrying `decided`, `alternative`, `reversal_cost`
    and `why_not_escalated` as non-blank text and `review` as text, empty until
    the owner writes a note in place, and may carry `owner`, the owner's
    verdict: `confirmed` or `overruled`, absent meaning not yet seen
    (`owner_state` reads it). An overruled entry's `review` note states the
    direction instead and is not blank. `reviewed` is retired: a format
    finding wherever it appears, never read, and the entry carrying it reads
    as not yet seen. A work item cites an entry as
    `docs/decisions/<run>.toml#D-<digits>`. Other keys are the writer's and
    are not judged; an entry id ending `-000` is inert.

Contract IF-256: the delegated-decisions record, as a CALL. `MODES` is the
    dial's alphabet (`off`, `record`, `escalate-first`); `REQUIRED_KEYS` the
    entry's required keys; `record_path(run)` the file's repo-relative path,
    raising `ValueError` for a run name no record can carry (`#` or a
    character git refuses);
    `record_findings(text)` one finding per defect IF-255 names, `[]` for a
    sound record, never raising; `owed(mode, outcomes)` whether a close under
    the dial `mode`, with at least one claimed row closed, owes a record;
    `missing_record_refusal(mode, run)` the merge slot's refusal of such a
    close with no record at its run's path, or with a run name no record
    can carry;
    `session_note(mode, run)` the instruction a delegated session is handed,
    `""` under `off`; `owner_state(value)` `confirmed`, `overruled`, `""` for
    the absent key (not yet seen), or None for a value it does not recognize;
    `review_queue(text)` the entries not yet seen and the entries overruled,
    each high-risk first, and the count confirmed; `citation(rel, entry_id)`
    the token a work item cites an entry by and `citations(text)` every such
    token in a text; `newly_overruled(before, after)` the entries overruled in
    `after` and not in `before`, raising `ValueError` when `after` does not
    parse; `overrule_sync_lines(changed, before, after)` one refusal line per
    entry a diff (`changed`, its paths) newly overrules with no queued or
    active work item spec among `changed` citing it in its `after` text, and
    one per changed record whose `after` text does not parse, `before(path)`
    and `after(path)` reading the parent and resulting tree (None for an absent
    path); `migrate_text(text)` the record with the retired key rewritten
    (complete top-level assignments only, the result re-parsed and refused
    unless only the verdict keys changed), and the ids it could not rewrite.
    Pure functions of
    their arguments: no file, git or environment read (the readers
    `overrule_sync_lines` is handed are the caller's).
"""

import re
import tomllib

# Where the records live, repo-relative.
# Implements: SR-225, LLR-283
DECISIONS_DIR = "docs/decisions"

# The `[attestation] decision_recording` alphabet, in order of how much it asks:
# no obligation; a delegated run's close owes the record; and, beyond recording,
# prefer the process's exits over deciding.
# Implements: SR-225, LLR-283
MODES = ("off", "record", "escalate-first")

# The keys every entry carries. The first four are the DISCLOSURE, and must say
# something; `review` is the owner's cell, empty until the owner writes in it.
# Implements: SR-225, LLR-283
REQUIRED_KEYS = (
    "decided",
    "alternative",
    "reversal_cost",
    "why_not_escalated",
    "review",
)
_DISCLOSURE = REQUIRED_KEYS[:4]

_ENTRY_ID_RE = re.compile(r"^D-\d+$")

# The owner's verdict (WI-818; the owner, 2026-10-04: a decision is "either
# confirmed by the user or overruled (or empty / ignored)"). Exact words: the
# vocabulary is closed and the migrator writes it, so any other value is a
# format finding and reads as not yet seen.
# Implements: SR-225, LLR-283
OWNER_KEY = "owner"
CONFIRMED = "confirmed"
OVERRULED = "overruled"
OWNER_VALUES = (CONFIRMED, OVERRULED)

# WI-790's key, retired by WI-818: a format finding wherever it appears, never
# read as a verdict. `migrate_text` is the one place its vocabulary survives.
# Implements: SR-225, LLR-283
RETIRED_KEY = "reviewed"
_RETIRED_TRUE = frozenset({"true", "yes", "y", "1", "reviewed", "done"})
_RETIRED_FALSE = frozenset({"false", "no", "n", "0", ""})

# THE RUN-NAME ALPHABET, one definition for the path's producer and the
# citation's reader: the characters a run name can NOT keep in its record's
# filename. They are exactly what git refuses in any branch name, one
# character at a time (git-check-ref-format(1): the ASCII control characters,
# space and DEL, and `~ ^ : ? * [ \`), plus the two delimiters a branch may
# carry: `/`, which `record_path` maps to `-` (a run is one file, never a
# directory), and `#`, the citation's delimiter, which it REFUSES with the
# rest (WI-818 dispute 1: folding `#` into `-` would hand a `#`-named branch
# another branch's record), so no record name carries `#` and a citation
# splits only one way. An explicit ASCII class, never `\s`: git permits
# Unicode whitespace (U+00A0), so `record_path` keeps it. Every other
# character a valid branch carries (`+`, `@`, `.`, non-ASCII) is kept by
# `record_path` and matched by the citation reader.
# Implements: SR-225, LLR-283
_RUN_EXCLUDED = r"/#\x00-\x20\x7f~^:?*\[\\"
_NOT_RUN_CHAR_RE = re.compile("[" + _RUN_EXCLUDED + "]")

# How a work item cites one entry: the record's repo-relative path, `#`, and
# the entry id, a digit never following (so `#D-01` does not match `#D-012`).
# The path's class excludes `#`, so the first `#` after `docs/decisions/` ends
# the path: one parse, whatever the run's name.
_CITATION_RE = re.compile(
    r"(docs/decisions/[^" + _RUN_EXCLUDED + r"]+?\.toml)#(D-\d+)(?!\d)"
)


def record_path(run):
    """The repo-relative path of one run's record: `DECISIONS_DIR/<run>.toml`,
    the run's `/` becoming `-` and no other character rewritten. A run name
    carrying any other character outside the run-name alphabet (`#`, or one
    git refuses) has no record: ValueError, naming the run and each such
    character, rather than a lossy rewrite into another name's file.

    Implements: SR-225, LLR-283
    """
    name = str(run).replace("/", "-")
    bad = sorted(set(_NOT_RUN_CHAR_RE.findall(name)))
    if bad:
        raise ValueError(
            "run name {!r} carries {}, which no decisions record can be named "
            "by: rename the branch".format(str(run), ", ".join(map(repr, bad)))
        )
    return "{}/{}.toml".format(DECISIONS_DIR, name)


def _inert(entry_id):
    return str(entry_id).endswith("-000")


def owner_state(value):
    """The owner's verdict on one entry: `CONFIRMED`, `OVERRULED`, `""` for
    the absent key (`None` as the argument: not yet seen), or None for a value
    the `owner` key does not recognize (which the caller reads as not yet seen
    and reports).

    Implements: SR-225, LLR-283
    """
    if value is None:
        return ""
    if isinstance(value, str) and value in OWNER_VALUES:
        return value
    return None


def _owner_findings(entry_id, entry):
    """The verdict's findings for one entry: an unrecognized `owner`, the
    retired key, and an overrule with no stated direction.

    Implements: SR-225, LLR-283
    """
    out = []
    state = owner_state(entry.get(OWNER_KEY))
    if state is None:
        out.append(
            "{}: `{}` = {!r} is not `{}` or `{}`, so the entry reads as not "
            "yet seen".format(
                entry_id, OWNER_KEY, entry.get(OWNER_KEY), CONFIRMED, OVERRULED
            )
        )
    if RETIRED_KEY in entry:
        out.append(
            "{}: `{}` is retired and never read; the entry reads as not yet "
            "seen, whatever `{}` says, until it is gone (migrate_decisions.py "
            "rewrites it)".format(entry_id, RETIRED_KEY, OWNER_KEY)
        )
    if state == OVERRULED and not str(entry.get("review") or "").strip():
        out.append(
            "{}: overruled with a blank `review`: an overrule states the "
            "direction instead in the note".format(entry_id)
        )
    return out


def _entry_findings(entry_id, entry):
    if not _ENTRY_ID_RE.match(entry_id):
        return ["{}: an entry id is D-<number>".format(entry_id)]
    if not isinstance(entry, dict):
        return ["{}: an entry is a table of its fields".format(entry_id)]
    out = _owner_findings(entry_id, entry)
    for key in REQUIRED_KEYS:
        value = entry.get(key)
        if value is None:
            out.append("{}: no `{}`".format(entry_id, key))
        elif not isinstance(value, str):
            out.append("{}: `{}` is not text".format(entry_id, key))
        elif key in _DISCLOSURE and not value.strip():
            out.append("{}: `{}` is blank".format(entry_id, key))
    return out


def record_findings(text):
    """Every defect in one record's text, as findings naming the entry and the
    field — `[]` for a sound record. Never raises.

    Implements: SR-225, LLR-283
    """
    try:
        data = tomllib.loads(text)
    except tomllib.TOMLDecodeError as exc:
        return ["the record does not parse as TOML ({})".format(exc)]
    entries = data.get("decision", {})
    if not isinstance(entries, dict):
        return ["`decision` is not a table of entries"]
    out = []
    for entry_id, entry in entries.items():
        if not _inert(entry_id):
            out.extend(_entry_findings(entry_id, entry))
    hoist = data.get("high_risk")
    if not isinstance(hoist, list) or not all(isinstance(h, str) for h in hoist):
        out.append(
            "no top-level `high_risk` list of entry ids (empty when no entry "
            "deserves the owner's eyes first)"
        )
        return out
    out.extend(
        "`high_risk` names {}, which the record does not carry".format(h)
        for h in hoist
        if h not in entries and not _inert(h)
    )
    return out


def _entries(data):
    """`(entries, hoisted ids)` of a parsed record: `-000` and non-table
    entries dropped, `({}, set())` when it carries no table of entries.

    Implements: SR-225, LLR-283
    """
    entries = data.get("decision")
    if not isinstance(entries, dict):
        return {}, set()
    hoist = data.get("high_risk")
    # A malformed hoist is `record_findings`' to report; the queue still lists
    # every entry, so the owner page shows the finding beside them.
    hoisted = (
        {h for h in hoist if isinstance(h, str)} if isinstance(hoist, list) else set()
    )
    kept = {
        eid: e for eid, e in entries.items() if not _inert(eid) and isinstance(e, dict)
    }
    return kept, hoisted


def _parsed(text):
    """`_entries` of a record's text, `({}, set())` when it does not parse."""
    try:
        return _entries(tomllib.loads(text or ""))
    except tomllib.TOMLDecodeError:
        return {}, set()


def review_queue(text):
    """`(unseen, overruled, confirmed)` for one record's text: the entries NOT
    YET SEEN (an absent or unrecognized `owner`) and the entries OVERRULED,
    each `{"id", "high_risk", "fields", "owner"}` (`fields` the entry's table,
    `owner` the raw value), each list the record's `high_risk` entries first
    and then id order; and how many entries are confirmed. An entry still
    carrying the retired key is not yet seen whatever its `owner` says. A
    `-000` entry is never listed or counted, and a text that does not parse
    lists nothing (`record_findings` reports it). Never raises.

    Implements: SR-225, LLR-283
    """
    entries, hoisted = _parsed(text)
    unseen, overruled, confirmed = [], [], 0
    for entry_id, entry in entries.items():
        state = None if RETIRED_KEY in entry else owner_state(entry.get(OWNER_KEY))
        if state == CONFIRMED:
            confirmed += 1
            continue
        shown = {
            "id": entry_id,
            "high_risk": entry_id in hoisted,
            "fields": entry,
            "owner": entry.get(OWNER_KEY),
        }
        (overruled if state == OVERRULED else unseen).append(shown)
    for listed in (unseen, overruled):
        listed.sort(key=lambda e: (not e["high_risk"], _id_number(e["id"])))
    return unseen, overruled, confirmed


def citation(rel, entry_id):
    """The token a work item cites one entry by: `<record path>#<entry id>`,
    e.g. `docs/decisions/wi-818.toml#D-002`.

    Implements: SR-225, LLR-283
    """
    return "{}#{}".format(rel, entry_id)


def citations(text):
    """Every entry a text cites, as the set of its `citation` tokens.

    Implements: SR-225, LLR-283
    """
    return {citation(m.group(1), m.group(2)) for m in _CITATION_RE.finditer(text or "")}


def _overruled_ids(entries):
    """The ids whose `owner` key, as written, is `overruled`: the coupling
    reads the key alone, so neither the retired key beside it nor a blank note
    lets an overrule skip its work.
    """
    return {
        eid for eid, e in entries.items() if owner_state(e.get(OWNER_KEY)) == OVERRULED
    }


def newly_overruled(before, after):
    """The entry ids overruled in the record text `after` and not in `before`
    (either None or "" for a record absent on that side), in id order. FAILS
    CLOSED: an `after` that does not parse raises `ValueError` naming the
    parse error, since an unreadable verdict is never "no overrule". An
    unparseable `before` overrules nothing, so the commit that makes the
    record readable owes the work for every overrule it then shows.

    Implements: SR-225, LLR-283
    """
    try:
        now, _hoisted = _entries(tomllib.loads(after or ""))
    except tomllib.TOMLDecodeError as exc:
        raise ValueError("does not parse as TOML ({})".format(exc))
    was, _hoisted = _parsed(before)
    return sorted(_overruled_ids(now) - _overruled_ids(was), key=_id_number)


# --- THE OVERRULE SYNC: an overrule files or amends its work (WI-818) --------
# The owner's overrule of a delegated decision is coupled to work the way a
# ruling is coupled to its citing row: one commit against its parent. The
# trigger is the record's state (an entry overruled in the new tree and not in
# the parent's); the act is a queued or active spec this same diff adds or
# changes whose new text cites the entry. A citation in a row the diff leaves
# untouched discharges nothing, and an archived row is not work to do. The two
# trees arrive as readers, so this module still reads no git itself.
_OPEN_WORK_DIRS = ("docs/work/queued/", "docs/work/active/")


def _open_spec(path):
    """Is `path` a queued or active work item spec (not the `-000` example)?

    Implements: SR-225, LLR-303
    """
    name = path.rsplit("/", 1)[-1]
    return (
        path.startswith(_OPEN_WORK_DIRS)
        and name.startswith("WI-")
        and name.endswith(".md")
        and not "-".join(name.split("-")[:2]).endswith("-000")
    )


def _owed_overrules(changed, before, after):
    """`(owed citations, refusal lines)` over the diff's decisions records:
    each entry the new tree overrules and the parent's does not, and one
    refusal per record the new tree carries but cannot parse — FAIL CLOSED, as
    the ruling sync refuses an unparseable open-items registry: an unreadable
    verdict is never "no overrule". The parent side unparseable overrules
    nothing, so the repair owes every overrule it shows.

    Implements: SR-225, LLR-303
    """
    owed, refusals = [], []
    for rel in changed:
        if not (rel.startswith(DECISIONS_DIR + "/") and rel.endswith(".toml")):
            continue
        try:
            ids = newly_overruled(before(rel), after(rel))
        except ValueError as exc:
            refusals.append(
                "{} {}, so whether this commit overrules a decision is unknown: "
                "the commit leaves the record parseable".format(rel, exc)
            )
            continue
        owed += [citation(rel, eid) for eid in ids]
    return owed, refusals


def overrule_sync_lines(changed, before, after):
    """One line per entry a diff overrules without filing or amending a queued
    or active work item that cites it as `docs/decisions/<run>.toml#D-NNN`.
    `changed` is the diff's repo-relative paths; `before(path)` and
    `after(path)` read a path's text in the parent and the resulting tree, None
    when that tree lacks it, and whatever they raise propagates. `[]` when no
    record in the diff gains an overrule. A record the new tree carries but
    cannot parse is a line, never a skip (`_owed_overrules`).

    Implements: SR-225, LLR-303
    """
    owed, refusals = _owed_overrules(changed, before, after)
    if not owed:
        return refusals
    cited = set()
    for path in filter(_open_spec, changed):
        cited |= citations(after(path))
    return refusals + [
        "{} is overruled by this commit, and no queued or active work item it "
        "files or amends cites it: the overrule's commit files a work item, or "
        "amends the queued one the decision was scoped to, citing {}".format(c, c)
        for c in owed
        if c not in cited
    ]


# A table header, the one shape `migrate_text` reads entry ids from (a quoted
# id included); any other header ends the entry.
_TABLE_RE = re.compile(r"^\s*\[\s*decision\.([^\]\s]+)\s*\]")
_HEADER_RE = re.compile(r"^\s*\[")
_RETIRED_LINE_RE = re.compile(r"""^(\s*)(?:reviewed|"reviewed"|'reviewed')\s*=""")


def _retired_verdict(value):
    """The retired key's reading, kept for the migrator alone: True, False, or
    None for a value outside its vocabulary.

    Implements: SR-225, LLR-304
    """
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value != 0
    word = value.strip().lower() if isinstance(value, str) else None
    if word in _RETIRED_TRUE:
        return True
    if word in _RETIRED_FALSE:
        return False
    return None


def _verdict_action(entry):
    """What the migration does to one entry's retired key: `"drop"` beside an
    `owner` key already set or for a not-reviewed value, `"confirm"` for a
    reviewed value, `"keep"` for a value outside the retired vocabulary.

    Implements: SR-225, LLR-304
    """
    if OWNER_KEY in entry:
        return "drop"
    verdict = _retired_verdict(entry.get(RETIRED_KEY))
    if verdict is None:
        return "keep"
    return "confirm" if verdict else "drop"


def _string_end(text, i):
    """The index just past the TOML string opening at `text[i]` — basic,
    literal, or either multiline form (whose closing delimiter may follow up
    to two quotes of its content). A basic string's backslash escapes the next
    character; a literal string has no escapes.

    Implements: SR-225, LLR-304
    """
    quote = text[i]
    delim = quote * 3 if text.startswith(quote * 3, i) else quote
    j = i + len(delim)
    while j < len(text):
        if quote == '"' and text[j] == "\\":
            j += 2
        elif text.startswith(delim, j):
            j += len(delim)
            extra = 0
            while len(delim) == 3 and extra < 2 and text.startswith(quote, j):
                j, extra = j + 1, extra + 1
            return j
        else:
            j += 1
    return j


def _statements(text):
    """The text cut into its TOP-LEVEL statements, as `(start, end)` spans:
    each runs from a line start to just past the newline that ends it outside
    every string, comment and bracket, so a multiline string or array is one
    statement and nothing inside a string ever starts one.

    Implements: SR-225, LLR-304
    """
    spans, start, depth, i = [], 0, 0, 0
    while i < len(text):
        ch = text[i]
        if ch in "\"'":
            i = _string_end(text, i)
            continue
        if ch == "#":
            newline = text.find("\n", i)
            i = len(text) if newline < 0 else newline
            continue
        depth += (ch in "[{") - (ch in "]}")
        if ch == "\n" and depth <= 0:
            spans.append((start, i + 1))
            start, depth = i + 1, 0
        i += 1
    if start < len(text):
        spans.append((start, len(text)))
    return spans


def _comment_start(statement):
    """The index of a statement's trailing comment (its first `#` outside
    every string), or None when it carries none.

    Implements: SR-225, LLR-304
    """
    i = 0
    while i < len(statement):
        if statement[i] in "\"'":
            i = _string_end(statement, i)
        elif statement[i] == "#":
            return i
        else:
            i += 1
    return None


def _migrated_statement(statement, entry):
    """What one top-level `reviewed = <value>` statement becomes, its whole
    value span included: `owner = "confirmed"` (keeping its indent, its
    trailing comment and the space before it, and its line ending); when
    dropped, its trailing comment alone on the line, or "" with none; or the
    statement itself when kept.

    Implements: SR-225, LLR-304
    """
    action = _verdict_action(entry)
    if action == "keep":
        return statement
    indent = _RETIRED_LINE_RE.match(statement).group(1)
    ending = statement[len(statement.rstrip("\r\n")) :]
    at = _comment_start(statement)
    if at is None:
        tail = ending
    else:
        tail = statement[len(statement[:at].rstrip()) :]
    if action == "drop":
        return "" if at is None else indent + tail.lstrip()
    return '{}{} = "{}"{}'.format(indent, OWNER_KEY, CONFIRMED, tail)


def _expected_parse(data, entries):
    """The parse a correct migration of `data` yields: each entry's retired
    key dropped, or replaced by `owner = "confirmed"`, or kept, and nothing
    else changed.

    Implements: SR-225, LLR-304
    """
    if not entries:
        return data
    want = dict(data)
    want["decision"] = dict(data["decision"])
    for eid, entry in entries.items():
        action = _verdict_action(entry) if RETIRED_KEY in entry else "keep"
        if action == "keep":
            continue
        new = {k: v for k, v in entry.items() if k != RETIRED_KEY}
        if action == "confirm":
            new[OWNER_KEY] = CONFIRMED
        want["decision"][eid] = new
    return want


def _same(a, b):
    """Are two parsed TOML values the same value: equal tables (key order
    aside), arrays and scalars of one type, with a NaN the same as a NaN
    (TOML's `nan`, `+nan` and `-nan` are one value that Python's `==` never
    finds equal to itself).

    Implements: SR-225, LLR-304
    """
    if type(a) is not type(b):
        return False
    if isinstance(a, dict):
        return a.keys() == b.keys() and all(_same(a[k], b[k]) for k in a)
    if isinstance(a, list):
        return len(a) == len(b) and all(map(_same, a, b))
    if isinstance(a, float) and a != a:
        return b != b
    return a == b


def _checked(new_text, want):
    """`new_text` when it re-parses to exactly `want` (`_same`); else
    `ValueError`, so a rewrite that touched anything but the verdict keys is
    never written.

    Implements: SR-225, LLR-304
    """
    try:
        got = tomllib.loads(new_text)
    except tomllib.TOMLDecodeError as exc:
        raise ValueError("the rewrite does not re-parse as TOML ({})".format(exc))
    if not _same(got, want):
        raise ValueError(
            "the rewrite's re-parse differs from the record in more than the "
            "verdict keys (a retired key the migrator cannot rewrite in place)"
        )
    return new_text


def migrate_text(text):
    """`(new_text, left)`: one record with the retired key rewritten in place —
    `reviewed = true` (or any word that read as reviewed) becomes
    `owner = "confirmed"`, a not-reviewed value or one beside an `owner` key
    is dropped — and the ids whose value is outside the retired vocabulary,
    left as they are (still a format finding). It rewrites complete top-level
    assignments only (`_statements`), never a string's contents, so every
    other byte, each `review` note and every comment included, is kept; and it
    re-parses the result, raising `ValueError` unless every other key and
    value is unchanged. Idempotent. Raises `ValueError` for a text that does
    not parse as TOML.

    Implements: SR-225, LLR-304
    """
    try:
        data = tomllib.loads(text)
    except tomllib.TOMLDecodeError as exc:
        raise ValueError("the record does not parse as TOML ({})".format(exc))
    entries, _hoisted = _entries(data)
    out, current = [], None
    for start, end in _statements(text):
        statement = text[start:end]
        if _HEADER_RE.match(statement):
            table = _TABLE_RE.match(statement)
            current = table.group(1).strip("\"'") if table else None
        elif current in entries and _RETIRED_LINE_RE.match(statement):
            statement = _migrated_statement(statement, entries[current])
        out.append(statement)
    left = [
        eid
        for eid, entry in entries.items()
        if RETIRED_KEY in entry and _verdict_action(entry) == "keep"
    ]
    return _checked("".join(out), _expected_parse(data, entries)), left


def _id_number(entry_id):
    tail = str(entry_id).rsplit("-", 1)[-1]
    return int(tail) if tail.isdigit() else 0


def owed(mode, outcomes):
    """Does a close owe a record — the dial at `record` or `escalate-first`,
    and at least one claimed row closed. EVERY close owes one, a partial close
    included: every delegated run closes with its record. A lane the machinery
    closed partial with no session present is therefore refused too, and that
    refusal is a hold for a person to write the record, never a strand.

    Implements: SR-225, LLR-283
    """
    return str(mode) in MODES[1:] and bool(list(outcomes or ()))


def missing_record_refusal(mode, run):
    """The merge slot's refusal of a close that owes a record and has none at
    its run's path, naming that path. A run name `record_path` refuses is an
    absent record too (WI-818 dispute 1): the refusal names the run and the
    reason, so the branch is renamed rather than handed another name's file.

    Implements: SR-225, LLR-283
    """
    try:
        rel = record_path(run)
    except ValueError as exc:
        return "{} closed with no decisions record: {}; nothing was merged".format(
            run, exc
        )
    return (
        "{} closed without its decisions record ({}): [attestation] "
        "decision_recording = {!r} makes the record owed at every "
        "close, even with no entries - write it on the branch; nothing "
        "was merged".format(run, rel, mode)
    )


def session_note(mode, run):
    """The instruction a delegated session is handed under a recording dial, or
    `""` under `off`. It names the exact path, so the session is told where its
    record belongs rather than asked to derive it.

    Implements: SR-225, LLR-283
    """
    if str(mode) not in MODES[1:]:
        return ""
    note = (
        "\n\nDECISIONS RECORD (docs/process.toml [attestation] "
        'decision_recording = "{mode}"): this run owes one record of the calls '
        "it made on the owner's behalf, at {path} — the format and the routing "
        'rules are the process options\' "Delegated decisions record" layer. '
        "Write one [decision.D-<n>] table per call that touched a registry, the "
        "spine or a kit file, or that you are unsure of, each carrying "
        "{keys} (leave review empty and set no owner key — the owner "
        'confirms or overrules each entry in place: owner = "confirmed" or '
        '"overruled"), and a top-level '
        "high_risk list naming the entries the owner should read first (empty "
        "when none). The record is not an exit: a call that is the owner's to "
        "make, or an act that cannot be undone, still goes to the owner through "
        "the process's exits, never only into this file. Commit it on this "
        "branch before your close commit, even with no entries: a lane that "
        "closes its work without it is refused at the merge."
    ).format(mode=mode, path=record_path(run), keys=", ".join(REQUIRED_KEYS))
    if str(mode) == "escalate-first":
        note += (
            " The dial is at escalate-first: where a call could go either way, "
            "prefer the exits over deciding it yourself."
        )
    return note
