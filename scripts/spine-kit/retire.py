#!/usr/bin/env python3
"""Retire a spine row and leave its record — the one writer of `docs/log.d/retired/`.

    python scripts/retire.py <ID> --reason "<why>" [--successor <ID>] \\
        [--date YYYY-MM-DD] [--root .]
    python scripts/retire.py --seed [--root .]

WHAT THIS IS (SR-226). A superseded spine row is DELETED, so the registries
state only what is, and its id is never reused, so a reference to it stays
unambiguous. What deletion loses is the reason: a reader who meets a spent id in
a commit message, a log entry or an archived document cannot tell why it went
or what replaced it. This command deletes the row AND writes its record, one
file per id, `docs/log.d/retired/<ID>.md`, holding the id, the date, the
successor (empty when none) and the reason. Both land as working-tree changes
the caller commits together, so the record rides the deletion's commit.

A RECORD IS FOR LOOKUP, NOT BROWSING. A session that meets a spent id reads that
id's file and nothing else; only the dashboard reads the set. The file per id is
what makes the lookup a path rather than a search, and what keeps the write
conflict-free across parallel branches. The directory sits one level below the
log's fragment drop-box because the trunk step folds and deletes every
top-level `docs/log.d/*.md` and its glob does not recurse.

NO COMMIT HASH IN THE RECORD. A commit cannot contain its own hash, so the
record does not name the deleting commit; `records` reads it from git as the
commit that added the record, and says `unknown` where history cannot answer (an
uncommitted record, a shallow clone, a squashed history).

THE CENSUS. Ids spent before the record began have no record and never will;
`--seed` declares them once, per tier, in `before-the-record.toml` beside the
records, so the check below does not report history nobody can now write. An id
reserved by a lane still building is not spent, so `--exclude` keeps it out;
`--replace` regenerates a census that has not yet landed (the merge that brings
it to trunk, where the true reservations are known), and never one that has.

THE TWO REPORTS, WARN-FIRST (`retirement_findings`, printed by `trace.py` as
advisories, outside every exit code): a spent id with neither a record nor a
place in the census, and a file under the directory whose text differs from its
text as it landed, or that was removed after landing. The second compares git
blobs, not the commits that touched the file, so an edit put back clears itself;
in a shallow clone whose history does not reach a file's landing it says the
file's append-only status is unverifiable rather than passing it.

Contracts: IF-257, IF-258 — the seams this module declares (process.md §8; rows
of record in docs/requirements/interfaces.toml).

Contract IF-257: the retirement records, as files. `docs/log.d/retired/<ID>.md`,
    one per retired SN, SR, LLR or TC row: a `+++` TOML front matter holding
    exactly `id` (the file's own name), `date` (a real YYYY-MM-DD date),
    `successor` (a spine id, or empty) and `reason` (non-blank), and nothing
    after the closing fence; a record is never rewritten.
    `docs/log.d/retired/before-the-record.toml`: one optional key per tier, its
    value the ids spent before the record began as comma-separated numbers and
    `a-b` ranges. `retirement_findings(root)` and `records(root)` are the
    readers' calls: advisory lines for the checker, and `{id, date, successor,
    reason, commit}` per readable record, in tier then number order, for the
    dashboard, `commit` being `unknown` where git cannot name a landing commit
    with a parent; `recorded_at(root, rev)` the ids a git tree holds a record
    file for, `{(space, number): relpath}`, for the landing check.
Contract IF-258: the retirement command's arm and its exit protocol.
    `retire.py <ID> --reason <text> [--successor <ID>] [--date <YYYY-MM-DD>]
    [--root <dir>]` deletes the row's table from its registry and writes its
    record; `retire.py --seed [--exclude ID[,ID...]] [--replace] [--root <dir>]`
    writes the census, an excluded id (`ID` or `ID..N`) never declared, and
    refuses an existing census unless `--replace` is given and it has not
    landed. Exit 0 with one `retire:` line on stdout, or exit 1 with one line
    starting `retire: REFUSED` on stderr and nothing written; argparse's own
    usage errors exit 2.

Python 3.11+, stdlib only; Windows + POSIX.
"""

import argparse
import datetime
import re
import sys
import tomllib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import id_carrier  # noqa: E402
import spine_carrier  # noqa: E402
from kitlib import config as kitconfig  # noqa: E402
from kitlib.git import ArchiveError, git_out  # noqa: E402
from kitlib.registry import parse_spec_frontmatter  # noqa: E402
from kitlib.spine import toml_fields  # noqa: E402

# Implements: SR-226, LLR-286
RETIRED_DIR = "docs/log.d/retired"
# Implements: SR-226, LLR-286
CENSUS = "before-the-record.toml"
WATERMARK = "docs/id-watermark"
UNKNOWN = "unknown"
FIELDS = ("id", "date", "successor", "reason")

# The four spine tiers, in the order a reader walks them, with each registry's
# home. The table names are the carrier's own (`spine_carrier.SPINE_TABLE`), so
# a tier's table is spelled once in the kit.
TIERS = (
    ("SN", "docs/requirements/stakeholder-needs.toml"),
    ("SR", "docs/requirements/system-requirements.toml"),
    ("LLR", "docs/requirements/low-level-requirements.toml"),
    ("TC", "docs/test/test-cases.toml"),
)
_TIER_ORDER = {space: n for n, (space, _rel) in enumerate(TIERS)}
_ID_RE = re.compile(r"\A(SN|SR|LLR|TC)-(\d+)\Z")
_RECORD_NAME_RE = re.compile(r"\A((?:SN|SR|LLR|TC)-\d+)\.md\Z")
_DATE_RE = re.compile(r"\A\d{4}-\d{2}-\d{2}\Z")
_HEADER_RE = re.compile(r"^\[[^\[\]]+\]\s*(?:#.*)?$")
_RANGE_RE = re.compile(r"\A(\d+)(?:-(\d+))?\Z")
_EXCLUDE_RE = re.compile(r"\A([A-Z]+)-(\d+)(?:\.\.(\d+))?\Z")
_CAP = 10


class Refused(Exception):
    """A retirement or a seed the command will not perform; nothing was written."""


def _table(space):
    return spine_carrier.SPINE_TABLE[space + "-ID"]


def _split(row_id):
    """`(space, number)` for a spine id, or None."""
    match = _ID_RE.match(row_id or "")
    return (match.group(1), int(match.group(2))) if match else None


def _format_id(space, number):
    return "{}-{:03d}".format(space, number)


def _read(path):
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return None


# --- the record ---------------------------------------------------------------


def fragment_text(row_id, date, successor, reason):
    """One record's text: the four cells as a `+++` TOML front matter.

    Implements: SR-226, LLR-286
    """
    cells = (
        ("id", row_id),
        ("date", date),
        ("successor", successor),
        ("reason", reason),
    )
    return "+++\n" + toml_fields(cells) + "+++\n"


def parse_fragment(text, relpath):
    """The record's four cells, or ValueError naming what is wrong.

    The front matter is read by the work-item spec's own reader, so the fence
    has one grammar in the kit. The id must be the file's own name, since the
    name is how a record is found.

    Implements: SR-226, LLR-286
    """
    data, body = parse_spec_frontmatter(text.replace("\r\n", "\n"), relpath)
    _shape_problem(data, body, relpath)
    cells = {key: data[key].strip() for key in FIELDS}
    name = Path(relpath).name
    if name != cells["id"] + ".md":
        raise ValueError(
            "{}: records `{}`, not the id its name gives".format(relpath, cells["id"])
        )
    if not _is_date(cells["date"]):
        raise ValueError("{}: `date` is not a real YYYY-MM-DD date".format(relpath))
    if not cells["reason"]:
        raise ValueError("{}: `reason` is blank".format(relpath))
    if cells["successor"] and not _split(cells["successor"]):
        raise ValueError("{}: `successor` is not a spine id".format(relpath))
    return cells


def _shape_problem(data, body, relpath):
    """Raise ValueError unless the front matter holds exactly the four text
    cells and nothing follows the closing fence but the file's final newline,
    not even a blank line or a space: a record the reader accepted beyond its
    declared shape would also silence the missing-record report."""
    if set(data) != set(FIELDS):
        raise ValueError(
            "{}: keys {} are not exactly {}".format(
                relpath, sorted(data), ", ".join(FIELDS)
            )
        )
    wrong = [key for key in FIELDS if not isinstance(data[key], str)]
    if wrong:
        raise ValueError("{}: `{}` is not text".format(relpath, wrong[0]))
    if body:
        raise ValueError("{}: text after the closing fence".format(relpath))


def _is_date(value):
    """A real calendar date written YYYY-MM-DD, not merely that shape."""
    if not _DATE_RE.match(value):
        return False
    try:
        datetime.date.fromisoformat(value)
    except ValueError:
        return False
    return True


def record_paths(root):
    """The record files under the directory, by name; the census is not one."""
    folder = Path(root) / RETIRED_DIR
    if not folder.is_dir():
        return []
    return sorted(p for p in folder.iterdir() if _RECORD_NAME_RE.match(p.name))


def recorded_at(root, rev):
    """`{(space, number): relpath}` for each record file the tree-ish `rev`
    holds under the directory, by name, readable or not (`_recorded`'s reading,
    at a git tree); `{}` when it holds none. Raises `ArchiveError` when git
    cannot list the tree.

    Implements: SR-226, LLR-286
    """
    listing = git_out(root, ["ls-tree", "--name-only", rev, "--", RETIRED_DIR + "/"])
    if listing is None:
        raise ArchiveError("git could not list {} at {}".format(RETIRED_DIR, rev[:10]))
    out = {}
    for rel in listing.splitlines():
        name = rel.rsplit("/", 1)[-1]
        if _RECORD_NAME_RE.match(name):
            out[_split(name[:-3])] = rel
    return out


def _recorded(root):
    """`{space: {number}}` named by the record files, readable or not: a record
    that fails to parse is reported on its own, never as a missing one too."""
    out = {}
    for path in record_paths(root):
        space, number = _split(path.name[:-3])
        out.setdefault(space, set()).add(number)
    return out


# --- what is live, spent and declared -----------------------------------------


def live_ids(root):
    """`{space: {number}}` of the rows each spine registry holds now.

    Read through the carrier that trace.py uses, so a legacy CSV or Markdown
    registry and its TOML successor answer the same live-id question.
    """
    out = {}
    for space, rel in TIERS:
        path = Path(root) / rel
        id_col = space + "-ID"
        rows = (
            spine_carrier.load_need_tier(path, id_col)
            if space == "SN"
            else spine_carrier.load(path, id_col)
        )
        for row in rows:
            rid = str(row.get(id_col) or "").strip()
            parsed = _split(rid)
            if parsed and parsed[0] == space:
                out.setdefault(space, set()).add(parsed[1])
    return out


def read_marks(root):
    """`{space: mark}` from the id watermark, read leniently through the one
    mark-line grammar (`id_carrier.parse_marks`); empty when it cannot be
    read, so no id reads as spent. The watermark's own integrity is
    `trace.py`'s."""
    return id_carrier.parse_marks(_read(Path(root) / WATERMARK) or "")


def _ranges(numbers):
    """`[1, 2, 3, 7]` -> `"1-3, 7"`."""
    runs = []
    for n in sorted(numbers):
        if runs and n == runs[-1][1] + 1:
            runs[-1][1] = n
        else:
            runs.append([n, n])
    return ", ".join(str(a) if a == b else "{}-{}".format(a, b) for a, b in runs)


def read_census(root):
    """`({space: {number}}, [finding])` from the census; an absent census is
    empty and no finding, an unreadable one is empty and one finding."""
    rel = "{}/{}".format(RETIRED_DIR, CENSUS)
    text = _read(Path(root) / rel)
    if text is None:
        return {}, []
    out = {}
    try:
        data = tomllib.loads(text)
        for space, value in data.items():
            if space not in _TIER_ORDER or not isinstance(value, str):
                raise ValueError("`{}` is not a tier's list of ids".format(space))
            for part in filter(None, (p.strip() for p in value.split(","))):
                match = _RANGE_RE.match(part)
                if not match:
                    raise ValueError("`{}` is not a number or a range".format(part))
                low = int(match.group(1))
                high = int(match.group(2) or low)
                out.setdefault(space, set()).update(range(low, high + 1))
    except (tomllib.TOMLDecodeError, ValueError) as exc:
        return {}, ["{} is unreadable, so it declares nothing: {}".format(rel, exc)]
    return out, []


def census_text(spent):
    """The census file's text for `{space: {number}}`."""
    lines = [
        "# Ids spent before the retirement record began (scripts/retire.py --seed):",
        "# rows deleted then, and ids allocated but never landed. They have no",
        "# record and never will; history holds whatever is left of why they went.",
        "# Written once, never edited: a later retirement writes its own record",
        "# under this directory instead. Look up one id here; do not survey the set.",
    ]
    for space, _rel in TIERS:
        if spent.get(space):
            lines.append('{} = "{}"'.format(space, _ranges(spent[space])))
    return "\n".join(lines) + "\n"


# --- the writers --------------------------------------------------------------


def _row_span(lines, header):
    """`(start, stop)`: the row's header line and the first line after its own
    cells. Comment and blank lines directly above the next header are left
    out of the span, since they belong to the next row."""
    starts = [i for i, ln in enumerate(lines) if ln.strip() == header]
    if len(starts) != 1:
        raise ValueError("no single `{}` table".format(header))
    start = starts[0]
    stop = next(
        (i for i in range(start + 1, len(lines)) if _HEADER_RE.match(lines[i].strip())),
        len(lines),
    )
    while stop > start + 1 and (
        not lines[stop - 1].strip() or lines[stop - 1].lstrip().startswith("#")
    ):
        stop -= 1
    return start, stop


def _without_row(document, table, row_id):
    """The parsed document minus that one row, and minus its table if emptied."""
    expected = dict(document)
    expected[table] = {k: v for k, v in document[table].items() if k != row_id}
    if not expected[table]:
        del expected[table]
    return expected


def drop_row(text, table, row_id):
    """`text` with the row's table cut out, or ValueError.

    The cut runs from the row's header line to the next table header, keeping
    the comment lines that sit directly above that header (they belong to the
    next row) and one blank line between rows. It is accepted only when the
    result parses to the old document minus exactly that row, so a cut that
    swallowed or damaged a neighbour is never written.

    Implements: SR-226, LLR-286
    """
    lines = text.splitlines(keepends=True)
    header = "[{}.{}]".format(table, row_id)
    start, stop = _row_span(lines, header)
    out = lines[:start] + lines[stop:]
    # The blank line that opened the row goes with it when another blank, or
    # the end of the file, follows.
    after = out[start].strip() if start < len(out) else ""
    if start and not out[start - 1].strip() and not after:
        del out[start - 1]
    out = "".join(out)
    if tomllib.loads(out) != _without_row(tomllib.loads(text), table, row_id):
        raise ValueError("cutting `{}` would change another row".format(header))
    return out


def _judge(root, row_id, reason, successor, date):
    """The record path, the registry path and its new text for a retirement, or
    Refused. Reads only; every refusal is decided before anything is written."""
    parsed = _split(row_id)
    if not parsed or parsed[1] == 0:
        raise Refused(
            "{!r} is not a spine row id (SN, SR, LLR or TC, then its number)".format(
                row_id
            )
        )
    if not reason.strip():
        raise Refused("a retirement needs its reason (--reason)")
    if not _is_date(date):
        raise Refused("--date {!r} is not YYYY-MM-DD".format(date))
    live = live_ids(root)
    if parsed[1] not in live.get(parsed[0], set()):
        raise Refused("{} is not a live row of its registry".format(row_id))
    if successor:
        succ = _split(successor)
        if successor == row_id or not succ or succ[1] not in live.get(succ[0], set()):
            raise Refused(
                "the successor {} is not another live spine row".format(successor)
            )
    record = Path(root) / RETIRED_DIR / (row_id + ".md")
    if record.exists():
        raise Refused(
            "{}/{} exists: a record is written once, never rewritten".format(
                RETIRED_DIR, record.name
            )
        )
    registry = Path(root) / dict(TIERS)[parsed[0]]
    try:
        text = drop_row(_read(registry) or "", _table(parsed[0]), row_id)
    except (ValueError, tomllib.TOMLDecodeError) as exc:
        raise Refused("{}: {}".format(registry.name, exc)) from None
    return record, registry, text


def retire(root, row_id, reason, successor="", date=None):
    """Delete a live spine row and write its record; `[record, registry]`.

    Judged whole before any write; the record is created exclusively, then the
    registry rewritten, and the caller commits both together.

    Implements: SR-226, LLR-286
    """
    date = date or datetime.date.today().isoformat()
    record, registry, text = _judge(root, row_id, reason, successor, date)
    record.parent.mkdir(parents=True, exist_ok=True)
    with record.open("x", encoding="utf-8", newline="\n") as fh:
        fh.write(fragment_text(row_id, date, successor, reason.strip()))
    with registry.open("w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    return [record, registry]


def spent_unrecorded(root, excluded=None):
    """`{space: {number}}`: at or below each tier's mark, neither live nor
    recorded, nor among `excluded` (`{space: {number}}`)."""
    marks, live, recorded = read_marks(root), live_ids(root), _recorded(root)
    excluded = excluded or {}
    out = {}
    for space, _rel in TIERS:
        held = live.get(space, set()) | recorded.get(space, set())
        held = held | excluded.get(space, set())
        gone = {n for n in range(1, marks.get(space, 0) + 1) if n not in held}
        if gone:
            out[space] = gone
    return out


def parse_exclusions(text):
    """`{space: {number}}` from `ID[,ID...]`, an id optionally ending `..N` for
    a run (`LLR-266..270`); Refused on anything else. Any id space is accepted,
    since a reservation list names every space a lane holds, and only the four
    spine tiers are read."""
    out = {}
    for part in filter(None, (p.strip() for p in (text or "").split(","))):
        match = _EXCLUDE_RE.match(part)
        if not match:
            raise Refused("--exclude {!r} is not an id or an id..N run".format(part))
        low = int(match.group(2))
        high = int(match.group(3) or low)
        if high < low:
            raise Refused("--exclude {!r} runs backwards".format(part))
        out.setdefault(match.group(1), set()).update(range(low, high + 1))
    return out


def seed_census(root, excluded=None, replace=False):
    """Write the census of the ids spent with no record now, never naming an
    excluded id (one reserved by a lane still building, which is not retired).

    A second seed is refused unless `replace` is given, and `replace` is
    refused once the census has landed in this checkout's history: from then
    on it is append-only like every record, and a rewrite would be the edit the
    append-only report exists to catch. Before it lands (the merge that brings
    it to trunk) it may be regenerated, and only its own file changes.

    Implements: SR-226, LLR-286
    """
    path = Path(root) / RETIRED_DIR / CENSUS
    rel = "{}/{}".format(RETIRED_DIR, CENSUS)
    if path.exists() and not replace:
        raise Refused(
            "{} exists: the ids retired before the record are declared once "
            "(--replace regenerates it before it lands)".format(rel)
        )
    if replace and rel in landings(root):
        raise Refused(
            "{} has landed in this checkout's history and is append-only".format(rel)
        )
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as fh:
        fh.write(census_text(spent_unrecorded(root, excluded)))
    return path


# --- the readers --------------------------------------------------------------


def missing_findings(marks, live, recorded, census):
    """One advisory naming the spent spine ids that have no record and are not
    declared as retired before the record began; `[]` when there are none.

    Pure: each argument is `{space: ...}`, `marks` holding ints and the rest
    sets of numbers. Spaces other than the four spine tiers are not judged.

    Implements: SR-226, LLR-286
    """
    gone = []
    for space, _rel in TIERS:
        held = live.get(space, set()) | recorded.get(space, set())
        held = held | census.get(space, set())
        top = marks.get(space, 0)
        gone += [_format_id(space, n) for n in range(1, top + 1) if n not in held]
    if not gone:
        return []
    shown = ", ".join(gone[:_CAP]) + (", ..." if len(gone) > _CAP else "")
    return [
        "{} spent spine id(s) have no retirement record under {}/: {} - retire a "
        "row with `retire.py <ID> --reason ...`, which writes it; ids retired "
        "before the record began are declared once with `retire.py --seed`".format(
            len(gone), RETIRED_DIR, shown
        )
    ]


def landings(root):
    """`{relpath: (commit, has_parent, blob)}` for each file git records as
    ADDED under the directory, the oldest addition winning; `{}` off git.

    One `git log` whatever the history's length. `--no-renames` makes a rename
    read as a removal plus an addition, so the old name is judged as removed.
    """
    out = git_out(
        root,
        [
            "log",
            "--diff-filter=A",
            "--no-renames",
            "--no-abbrev",
            "--format=%x00%H %P",
            "--raw",
            "--",
            RETIRED_DIR,
        ],
    )
    found = {}
    for chunk in (out or "").split("\x00")[1:]:
        head, _sep, body = chunk.partition("\n")
        shas = head.split()
        if not shas:
            continue
        for line in body.splitlines():
            meta, _tab, path = line.partition("\t")
            fields = meta.split()
            if len(fields) >= 5 and fields[-1] == "A":
                found[path.strip()] = (shas[0], len(shas) > 1, fields[3])
    return found


def shallow_boundary(root):
    """The commits at this clone's shallow boundary, `set()` in a full clone
    or off git. A boundary commit shows every file it holds as ADDED, because
    its parents are cut away, so an addition read there is not a landing."""
    out = git_out(root, ["rev-parse", "--git-path", "shallow"])
    if not out or not out.strip():
        return set()
    path = Path(out.strip())
    path = path if path.is_absolute() else Path(root) / path
    text = _read(path) or ""
    return {line.strip() for line in text.splitlines() if line.strip()}


def _current_blobs(root, present):
    """`{relpath: blob}` for the files as they stand, in one `git hash-object`,
    which applies the checkout's filters; `{}` when git will not answer."""
    if not present:
        return {}
    out = git_out(root, ["hash-object", "--stdin-paths"], stdin="\n".join(present))
    blobs = (out or "").split()
    return dict(zip(present, blobs)) if len(blobs) == len(present) else {}


def edited_findings(root, landed=None):
    """An advisory per file under the directory whose text differs from its
    text as it landed, or that was removed after it landed; `[]` off git.

    Blobs are compared, so an edit put back clears itself, and a line-ending
    conversion is not an edit. In a shallow clone a file whose only addition
    is read at the boundary has no landing this checkout can see, so its
    append-only status is reported as unverifiable rather than passed.

    Implements: SR-226, LLR-286
    """
    landed = landings(root) if landed is None else landed
    boundary = shallow_boundary(root) if landed else set()
    present = sorted(p for p in landed if (Path(root) / p).is_file())
    current = _current_blobs(root, present)
    found = []
    for path in sorted(landed):
        commit, _parent, blob = landed[path]
        if commit in boundary:
            found.append(
                "{}: append-only status unverifiable - its landing lies past this "
                "shallow clone's history".format(path)
            )
        elif path not in present:
            found.append(
                "{} was removed after it landed in {}: a retirement record is "
                "append-only".format(path, commit[:7])
            )
        elif path in current and current[path] != blob:
            found.append(
                "{} has changed since it landed in {}: a retirement record is "
                "append-only".format(path, commit[:7])
            )
    return found


def retirement_findings(root):
    """Every advisory about the records, for `trace.py` to print: unreadable
    records and census, spent ids with no record, and records moved after they
    landed.

    Implements: SR-226, LLR-286
    """
    found = []
    for path in record_paths(root):
        rel = "{}/{}".format(RETIRED_DIR, path.name)
        try:
            parse_fragment(_read(path) or "", rel)
        except ValueError as exc:
            found.append("unreadable retirement record: {}".format(exc))
    census, problems = read_census(root)
    found += problems
    found += missing_findings(read_marks(root), live_ids(root), _recorded(root), census)
    return found + edited_findings(root)


def records(root):
    """Each readable record with its deleting commit, in tier then number order.

    The deleting commit is the one that added the record, which the writer puts
    in the deletion's working tree. A record not yet committed, or added by a
    commit with no parent (a shallow clone's boundary, a squashed history's
    root), reads `unknown`: a parentless commit deleted nothing.

    Implements: SR-226, LLR-286
    """
    landed = landings(root)
    rows = []
    for path in record_paths(root):
        rel = "{}/{}".format(RETIRED_DIR, path.name)
        try:
            cells = parse_fragment(_read(path) or "", rel)
        except ValueError:
            continue
        commit, has_parent, _blob = landed.get(rel, ("", False, ""))
        cells["commit"] = commit[:7] if commit and has_parent else UNKNOWN
        rows.append(cells)
    return sorted(
        rows, key=lambda r: (_TIER_ORDER[_split(r["id"])[0]], _split(r["id"])[1])
    )


# --- the command --------------------------------------------------------------


def _act(args, root):
    """Perform the one act the arguments name and return what to print, or
    raise Refused. `--exclude` and `--replace` belong to the seed alone."""
    if args.seed == bool(args.id):
        raise Refused("name one row to retire, or pass --seed alone")
    if not args.seed:
        if args.exclude or args.replace:
            raise Refused("--exclude and --replace go with --seed")
        record, registry = retire(
            root, args.id.strip(), args.reason, args.successor.strip(), args.date
        )
        return "removed {} from {} and wrote {}/{}; commit both together".format(
            args.id, registry.name, RETIRED_DIR, record.name
        )
    path = seed_census(root, parse_exclusions(args.exclude), args.replace)
    return "wrote {}/{}".format(RETIRED_DIR, path.name)


def main(argv=None):
    """`retire.py <ID> --reason ...` or `retire.py --seed [--exclude] [--replace]`.

    Implements: SR-226, LLR-286
    """
    kitconfig.utf8_console()
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("id", nargs="?", default=None, help="the spine row to retire")
    ap.add_argument("--reason", default="", help="why the row is retired")
    ap.add_argument("--successor", default="", help="the live row replacing it")
    ap.add_argument("--date", default=None, help="YYYY-MM-DD (default: today)")
    ap.add_argument(
        "--seed",
        action="store_true",
        help="declare the ids spent before the record began, once",
    )
    ap.add_argument(
        "--exclude",
        default="",
        help="with --seed: ids reserved by lanes still building, never declared "
        "spent (ID[,ID...], an id may end ..N for a run, e.g. LLR-266..270)",
    )
    ap.add_argument(
        "--replace",
        action="store_true",
        help="with --seed: regenerate a census that has not yet landed",
    )
    ap.add_argument("--root", default=".", help="repo root (default: .)")
    args = ap.parse_args(argv)
    try:
        done = _act(args, Path(args.root))
    except Refused as exc:
        print("retire: REFUSED - {}. Nothing was written.".format(exc), file=sys.stderr)
        return 1
    print("retire: " + done)
    return 0


if __name__ == "__main__":
    sys.exit(main())
