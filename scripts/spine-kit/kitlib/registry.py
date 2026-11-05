"""The `docs/work/` spec-folder work-item registry reader — the one read half.

`docs/work/<status>/WI-###-<slug>.md`: one Markdown spec per work item, its
STATUS encoded as the DIRECTORY (docs/concurrency-restructure.md §2.1, Phase
2b). The reader emits rows carrying the SAME 19 keys `csv.DictReader` used to
yield for the retired `work-items.csv`, so consumers past `load_wis` never
learn which home was authoritative. The format's DEFINITION is
`scripts/wi_convert.py` (`parse_spec` / `status_from_location`), which
materializes the folder; this module is its read half.

WHAT THIS REPLACES. Until WI-448 this 270-line block was copied VERBATIM into
`schedule.py`, `check_trajectory.py` and `agent_common.py` under the retired F5
rule, with `tests/test_wi_loader_sync.py` pinning the three parsers equal
because extraction had been refused (owner ruling 2026-07-12). D-8 reversed
that ruling. The extraction also settled a live question the pins could not
see: the three copies were NOT verbatim at the moment they were merged —
`agent_common`'s carried `a DevStg-* value` in the `Bar` comment where the
other two carried the literal `DevStg-Reqs|DevStg-Tests|DevStg-Impl` enum, a
comment-only drift from the 2026-08-18 one-vocabulary rename reaching two homes
of three. Behaviour-equal, so a behavioural pin was structurally blind to it;
the more informative spelling is the one kept below.

The three modules now import from here, so `load_wis`' own POLICY split — the
scheduler skips a malformed row, the validator reports it — stays where it
belongs: in each consumer, over one shared parse.
"""

import re
import tomllib
from pathlib import Path

from . import git as _kitgit

__all__ = [
    "plan_table_rows",
    "WI_COLUMNS",
    "SPEC_SCALARS",
    "SPEC_LISTS",
    "LIST_TOLERANT_SCALARS",
    "scalar_cell",
    "adjudicates_tokens",
    "SPEC_STATUS_DIRS",
    "SPEC_FENCE",
    "SPEC_DELIVERABLE",
    "SPEC_HANDBACK",
    "SPEC_CONTEXT",
    "HEADING_RE",
    "DONE_WHEN_RE",
    "done_when_section",
    "spec_work_dir",
    "spec_archive_dir",
    "spec_roots",
    "spec_files",
    "WORK_SPEC_ROOTS",
    "tree_spec_paths",
    "parse_spec_frontmatter",
    "parse_spec_status",
    "parse_spec_id",
    "parse_spec_deliverable",
    "parse_spec_row",
    "read_spec_rows",
    "spec_id_number",
    "shared_spec",
]

WI_COLUMNS = (
    "WI-ID",
    "Title",
    "Workstream",
    "SR-Refs",
    "Predecessors",
    "Status",
    "Deliverable",
    "SpecRef",
    "BuildTier",
    "CritiqueBudget",
    "CritiqueExhaustion",
    "Priority",
    "Exclusive",
    "EstTokens",
    "SafetyClass",
    "PlanMode",
    "Bar",
    # LLR-161 LINEAGE. Partial work continues by MINTING A SUCCESSOR, never by
    # reviving the closed row — so the successor must be able to say which row
    # it continues, or the thread is lost at the id change. A real column, not
    # a frontmatter-only key, because `intake`'s drafts-not-mints arm writes
    # successors through `wi_convert.write_spec_file`, which serializes from
    # this table: a key that is not here would be silently dropped at the one
    # moment it matters.
    "Supersedes",
    # SN-032 BRIEF ROUTING. Which adjudicator brief this row's session is sent
    # (`amendment` | `disposition` | `conflict` | `red-tc`), empty on every row
    # that is not an adjudication. DECLARED rather than inferred from `SpecRef`
    # because the inference is provably ambiguous: an amendment to a test-case
    # row and a red-TC census row both carry `docs/test/test-cases.toml`, and
    # those two briefs give contradictory instructions. A real column for the
    # `Supersedes` reason above — `intake` writes it through
    # `wi_convert.write_spec_file`, which serializes from this table.
    "Brief",
    # WI-572 SCOPE OF THE ACT. The registry row ids an adjudication was minted
    # OVER, `;`-joined — the population the merge handed it, and the bound the
    # brief's LIVE re-derivation intersects against so the act cannot widen past
    # what was handed over. Empty on every row that is not an adjudication.
    "Adjudicates",
    # THE CONSOLIDATION CENSUS'S RECURSION GUARD (the 2026-09-02 restructure
    # plan §1.3): `<queue sha>|<spine sha>`, the queue state and spine state the
    # census saw when it minted this judgement. The census refuses to mint while
    # a `consolidate` row carrying THIS queue sha is queued, active or ARCHIVED,
    # so the cell has to survive the close — a guard that stops holding when the
    # row goes terminal mints the same judgement forever. Empty on every row that
    # is not a consolidation.
    "Digests",
    # WI-969 THE ADOPTION RECORD. The `;`-joined ids of the already-filed
    # successors an early-close disposition row ADOPTED, written once by the
    # mechanical close (`handback`) after it validated them in the tree the
    # closing commit is made on, and empty on every other row. A real column
    # so the converter carries it and a round trip of the closed spec is
    # byte-stable; this reader grants it nothing beyond the join - the close,
    # the commit check and the sweep read it through the one strict reader,
    # `kitlib.adoption.record_ids`, so a malformed record never breaks every
    # registry read.
    "Adopted",
    # WI-982 THE AUTHORING TAGS. The `;`-joined Workstream and SafetyClass
    # values of the work items a minted first-approval or amendment row was
    # authored under, or empty when no route named one. NOT the routing
    # `SafetyClass`, which stays `adjudication`: the one reader is the hat
    # composer, `hats.context_from_work_item`. A real column for the
    # `Supersedes` reason above: `intake` writes it through this table.
    "AuthoringTags",
)
SPEC_SCALARS = (
    ("Title", "title"),
    ("Workstream", "workstream"),
    ("SpecRef", "specref"),
    ("BuildTier", "buildtier"),
    ("CritiqueBudget", "critique_budget"),
    ("CritiqueExhaustion", "critique_exhaustion"),
    ("Priority", "priority"),
    ("Exclusive", "exclusive"),
    ("EstTokens", "est_tokens"),
    ("SafetyClass", "safety_class"),
    ("PlanMode", "planmode"),
    # WI-388: bar declares verification strictness for this row's lane; it
    # never affects scheduling. (DevStg-Reqs|DevStg-Tests|DevStg-Impl — integrate.refresh passes it to
    # check.py --gate; load_wis deliberately does not parse it.)
    ("Bar", "bar"),
    ("Supersedes", "supersedes"),
    ("Brief", "brief"),
    ("Digests", "digests"),
)
SPEC_LISTS = (
    ("SR-Refs", "sr_refs"),
    ("Predecessors", "needs"),
    ("Adjudicates", "adjudicates"),
    ("Adopted", "adopted"),
    ("AuthoringTags", "authoring_tags"),
)
# The scalars whose frontmatter key may ALSO be written as a TOML list, read
# either way into the same `;`-joined cell. `supersedes` is the one (the
# 2026-09-02 restructure plan §1.5): a consolidation absorbs SEVERAL rows into
# one successor, so the successor's lineage names several predecessors, while
# every other successor names exactly one. Widening the CELL to a list would
# have re-typed a column and every reader of it for a shape most rows never
# carry; widening the FRONTMATTER is the whole change, and a bare string keeps
# reading byte-for-byte as it always did. Deliberately NOT a `SPEC_LISTS` entry:
# those columns are lists in every row, and a `SPEC_LISTS` `supersedes` would
# make `wi_convert` re-emit a one-id cell as a one-element list, changing every
# existing spec file's bytes for nothing.
LIST_TOLERANT_SCALARS = frozenset({"supersedes"})
# Directory -> Status. The directory is the WHOLE statement (WI-384): every
# state owns a folder — including BOTH terminals, `complete/` for work that
# shipped and `cancelled/` for work that never will — so nothing in the
# frontmatter disambiguates a folder and nothing can disagree with one.
# `draft/` is thinking-in-progress, and it is DECLARED rather than left as an
# unscanned folder because an undeclared directory's specs are skipped below:
# they never enter the registry, so the duplicate-id guard and the dashboard go
# blind to an id a draft holds. (The id MINT is safe either way — it reads
# FILENAMES, never this table — so declaring the folder makes the reservation
# CHECKED rather than incidental; driven at WI-384's review.) The two terminal
# WORDS differ for a reason:
# `complete/` renamed a folder whose rows still read `done` (the status word
# every consumer already speaks), while `cancelled` had no folder to rename —
# only the `disposition = "retired"` spelling this row deleted — so the word
# itself moved. `active/<branch>/` sits one level deeper, so the status is the
# FIRST path component, never the file's parent directory.
# `partial/` (SR-144) is the THIRD terminal, and the one that made the outcome
# model honest. A lane that stops early used to move back to `queued/` carrying
# a `## Handback` note and a `blockref` — which meant the return event had no
# artifact of its own, only a mutable, movable, self-referencing spec. Five
# successive dedup mechanisms tried to reconstruct "did a return happen, and was
# it judged?" from that spec, and every one leaked: an owed judgement silently
# not happening. `partial/` is TERMINAL — nothing re-claims it, so nothing
# strands — and the per-close report under docs/handbacks/ IS the event's
# identity. Continuing the work MINTS A SUCCESSOR (carrying `supersedes`),
# because a closed row is never revived and a scope definition never changes to
# mean something else.
# `restructured/` is the FOURTH terminal (2026-09-02 backlog-restructure plan
# §1.6). A consolidation judgement may ABSORB several queued rows into one
# successor; the absorbed row is not refuted (`cancelled` would brief every
# later row on the same SRs that its scope was refuted — `intake.context_block`
# joins exactly that) and it did not stop early (`partial` owes a per-close
# report and mints a disposition). It was carried onward: its scope text stays
# byte-identical, its Deliverable is the one line `Restructured into WI-<n>.`,
# and its inbound hard edges are re-pointed to the successor at the close. It is
# TERMINAL — never re-claimed, never revived, and no lane may close into it.
SPEC_STATUS_DIRS = {
    "draft": "draft",
    "queued": "queued",
    "active": "active",
    "deferred": "deferred",
    "cancelled": "cancelled",
    "partial": "partial",
    "restructured": "restructured",
    "complete": "done",
}
SPEC_FENCE = "+++"
SPEC_DELIVERABLE = "\n## Deliverable\n\n"
# The body's OTHER section (WI-387): a lane that HANDS a WI back writes a
# `## Handback` note after the Deliverable's place, so the returned spec says
# in trunk what remains and where the partial work is. It carries no registry
# cell — nothing here parses it — and is recognised only so an honest
# returned spec does not read as a malformed one.
SPEC_HANDBACK = "\n## Handback\n"
# The body's THIRD section (WI-388): the advisory `## Context` block the
# intake mint writes into every minted row (pure registry joins — precedent,
# open items, the code map, knowledge packs), advisory-never-gating. Like the
# Handback note it carries no registry cell and is read PAST, so a minted row
# whose body is context-only parses with an empty Deliverable rather than as
# a malformation.
SPEC_CONTEXT = "\n## Context\n"

# --- the Done-when SECTION: one home, three readers ---------------------------
#
# A markdown ATX heading, and the "is this the Done-when heading" test. The
# pattern is deliberately TOLERANT: this repo's own live specs spell the heading
# four ways (`## Done-when` x22, `## Done when` x5, `### Done when` x2,
# `### Done-when` x1, measured 2026-09-04 over docs/work + docs/archive/work +
# project-trajectory), and a reader matching only the majority spelling drops
# the criteria of the other eight and reports them as absent.
#
# IT LIVES HERE because three readers want it and a second copy of a tolerant
# pattern is worse than no tolerance at all: `check_trajectory._done_when_boxes`
# counts completion boxes inside the section, `consolidate.absorbed_done_when`
# quotes the section into a consolidation successor, and this module owns the
# spec body's shape. The narrow copy that prompted the extraction dropped 8 of
# 30 live headings and then asserted, in a minted row's Context, that the
# absorbed row "declared no `## Done-when` section" - an affirmative false
# statement about somebody else's acceptance criteria.
HEADING_RE = re.compile(r"^(#{1,6})\s+(.*)$")
DONE_WHEN_RE = re.compile(r"^\s*(?:\d+[.)]\s*)?done[- ]when\b", re.IGNORECASE)


def done_when_section(text):
    """The lines inside a spec body's Done-when section, or `[]` when it has
    none. The heading line itself is not included.

    SECTION, not "everything until the next heading": a Done-when that
    subdivides keeps its subsections, while a SIBLING or shallower heading ends
    it. That distinction is load-bearing and was bought by a real defect -
    `docs/specs/WI-321.md` carries WI-324's remaining boxes under a sibling
    `## Split off, deliberately` heading, and folding those in attributed one
    WI's unfinished work to another.

    Line endings are normalized OFF each line: a CRLF checkout otherwise leaves
    stray `\r` in text a caller writes back with `newline="\n"`.
    """
    out, depth = [], None
    for raw in (text or "").split("\n"):
        line = raw.rstrip("\r")
        heading = HEADING_RE.match(line)
        if heading:
            level = len(heading.group(1))
            if DONE_WHEN_RE.match(heading.group(2)):
                depth = level
                continue
            if depth is not None and level <= depth:
                break
        if depth is not None:
            out.append(line)
    return out


def spec_work_dir(csv_path):
    """The `docs/work` folder that replaces the registry CSV at `csv_path` — its
    `docs/` directory plus `work`, derived from the one path each caller already
    declares rather than from a second constant that could disagree with it."""
    return Path(csv_path).parent.parent / "work"


def spec_archive_dir(work_dir):
    """`docs/work`'s archive sibling, `docs/archive/work` (WI-504): terminal
    history (`complete/`, `cancelled/`, `partial/`, `restructured/`) lives there, one directory
    deeper than the active workspace. Derived from `work_dir` the same way
    `spec_work_dir` derives `work_dir` from the CSV path — one fact, not a
    second constant a caller could let drift."""
    work_dir = Path(work_dir)
    return work_dir.parent / "archive" / "work"


def spec_roots(work_dir):
    """`work_dir` plus its archive sibling — BOTH homes a spec may live in
    while WI-504's relocation is honoured everywhere it must be: the active
    workspace (`draft/queued/active/deferred`, and — until a repo's own move
    commit lands — terminal directories not yet relocated) and the archive
    (`complete/cancelled/partial/restructured`, the new terminal home). Order is stable
    (`work_dir` first) so an id or ordering tie breaks the same way it always
    has."""
    work_dir = Path(work_dir)
    archive_dir = spec_archive_dir(work_dir)
    return (work_dir,) if archive_dir == work_dir else (work_dir, archive_dir)


#: Both homes of a work spec in a tree, from the repository root: the work
#: root and its archive (`spec_roots`' pair, as git paths).
WORK_SPEC_ROOTS = ("docs/work", "docs/archive/work")


def tree_spec_paths(root, rev):
    """Every path under `WORK_SPEC_ROOTS` in the tree of `rev` (None: the
    index) whose file name begins `WI-` and ends `.md`, in git's listing
    order, read NUL-safe through `kitlib.git.git_paths`; None when git cannot
    list it. The one work-spec listing: each caller keeps its own view over
    it (its id reading, its duplicate handling, its error).

    Implements: SR-148, LLR-298, LLR-335, LLR-345
    """
    if rev is None:
        args = ["ls-files", "--"]
    else:
        args = ["ls-tree", "-r", "--name-only", rev, "--"]
    paths = _kitgit.git_paths(root, args + list(WORK_SPEC_ROOTS))
    if paths is None:
        return None
    return [
        path
        for path in paths
        if path.rsplit("/", 1)[-1].startswith("WI-") and path.endswith(".md")
    ]


def _spec_files_under(root):
    root = Path(root)
    if not root.is_dir():
        return []
    return [p for p in root.rglob("WI-*.md") if p.parent != root]


def spec_files(work_dir):
    """Every `<status>/WI-*.md` spec under `work_dir`, sorted by path; `[]` when
    the folder is absent or holds none. An empty answer is what leaves the CSV
    authoritative, so a stray file sitting DIRECTLY in `work_dir` — which has no
    status directory above it — deliberately does not count as a registry.

    Single-root: this is the primitive `read_spec_rows` below builds the
    both-roots union on top of, and the narrower thing a caller that already
    knows which one tree it means (a branch's own claimed set, a status-dir
    census) still wants undiluted."""
    return sorted(_spec_files_under(work_dir))


def parse_spec_frontmatter(text, relpath):
    """`(data, body)` for one spec file: the TOML frontmatter between the `+++`
    fences, parsed, and everything after the closing fence, verbatim."""
    lines = text.split("\n")
    if not lines or lines[0] != SPEC_FENCE or SPEC_FENCE not in lines[1:]:
        raise ValueError(
            "{}: no closed `{}` frontmatter fence".format(relpath, SPEC_FENCE)
        )
    close = lines.index(SPEC_FENCE, 1)
    try:
        data = tomllib.loads("\n".join(lines[1:close]))
    except tomllib.TOMLDecodeError as exc:
        raise ValueError(
            "{}: frontmatter is not valid TOML — {}".format(relpath, exc)
        ) from None
    return data, "\n".join(lines[close + 1 :])


def parse_spec_status(relpath):
    """The Status a spec's LOCATION encodes — the whole of it.

    Each state owns one directory, so there is no attribute to cross-check and
    no way for location and frontmatter to disagree: WI-384 split `archive/`
    into `complete/` + `cancelled/` and with it deleted the `disposition` key,
    the cross-check, and both of its raise paths. One refusal survives, because
    it is the one a folder-as-state model still needs: a directory nobody
    declared. Dropping it into `queued` would silently reclassify work, which
    is the catch-all shape this kit refuses on sight."""
    parts = relpath.split("/")
    status = SPEC_STATUS_DIRS.get(parts[0]) if len(parts) > 1 else None
    if status is None:
        raise ValueError(
            "{}: {!r} is not a status directory (the spec form knows only {})".format(
                relpath, parts[0], ", ".join(sorted(SPEC_STATUS_DIRS))
            )
        )
    return status


def parse_spec_id(relpath, data):
    """The work-item id, which must be a non-empty string AND must be the one
    the filename carries — two homes for one fact, so they are compared here
    rather than trusted apart."""
    wid = data.get("id")
    if not isinstance(wid, str) or not wid:
        raise ValueError("{}: frontmatter carries no string `id`".format(relpath))
    if not relpath.split("/")[-1].startswith(wid + "-"):
        raise ValueError(
            "{}: filename does not carry its own id {!r}".format(relpath, wid)
        )
    return wid


def parse_spec_deliverable(relpath, body):
    """The Deliverable cell a spec body carries, verbatim ("" when absent).

    The long cell lives in the BODY precisely because body text needs no
    escaping: it may hold newlines, quotes and markdown. This format owns the
    whole body shape, so anything that is neither empty nor one
    `## Deliverable` section (optionally joined by the `## Handback` note a
    returned spec carries, or the advisory `## Context` block a minted spec
    carries — both clipped off before the cell is read) is a malformation
    rather than free prose."""
    if not body:
        return ""
    body = body.partition(SPEC_HANDBACK)[0]
    body = body.partition(SPEC_CONTEXT)[0]
    if not body:
        return ""
    if not body.startswith(SPEC_DELIVERABLE) or not body.endswith("\n"):
        raise ValueError(
            "{}: body is neither empty nor one `## Deliverable` section".format(relpath)
        )
    return body[len(SPEC_DELIVERABLE) : -1]


def scalar_cell(key, value):
    """One frontmatter SCALAR as its registry cell.

    A `LIST_TOLERANT_SCALARS` key written as a TOML list reads as the `;`-joined
    cell — the same join `SPEC_LISTS` columns take — so the two spellings of
    `supersedes` (one id as a bare string, several as a list) produce one cell
    shape and every reader downstream sees `;`-joined ids or nothing. Any other
    value is `str()`, exactly as it always was."""
    if key in LIST_TOLERANT_SCALARS and isinstance(value, (list, tuple)):
        return ";".join(str(v) for v in value)
    return str(value)


def adjudicates_tokens(data, where):
    """THE ONE PARSER of a spec's raw `adjudicates` frontmatter value (WI-849,
    Sol r3): its row tokens, `[]` when the key is absent, or a ValueError
    naming `where`. The registry's spec-row parser (the adjudication route's
    input) and `kitlib.sitting.claim_scope` (the merge's) both read the value
    here and nowhere else, so the two cannot read one cell two ways.

    One shape is accepted: a TOML list of strings, each one token - stripped,
    non-empty, carrying no `;` (the column's own join). A bare string, a table,
    a non-string element and an empty or `;`-bearing element are refused,
    never coerced: a coerced scope is a scope nobody declared.

    Implements: SR-166, LLR-181"""
    value = data.get("adjudicates", [])
    if isinstance(value, list) and all(
        isinstance(t, str) and t.strip() and ";" not in t for t in value
    ):
        return [t.strip() for t in value]
    raise ValueError(
        "{}: `adjudicates` is {!r}, not a TOML list of strings each naming one "
        "token (non-empty, no `;`)".format(where, value)
    )


def parse_spec_row(text, relpath):
    """`(row, order)` for one spec file — a 19-key row shaped exactly like the
    CSV's. Raises ValueError NAMING the file on any malformation: invalid TOML, a
    missing or non-string `id`, an id the filename disagrees with, a directory
    that is not a status, a scope cell `adjudicates_tokens` refuses, or a body
    that is not the single `## Deliverable` section this format owns."""
    data, body = parse_spec_frontmatter(text, relpath)
    row = dict.fromkeys(WI_COLUMNS, "")
    row["WI-ID"] = parse_spec_id(relpath, data)
    row["Status"] = parse_spec_status(relpath)
    row["Deliverable"] = parse_spec_deliverable(relpath, body)
    for column, key in SPEC_SCALARS:
        if key in data:
            row[column] = scalar_cell(key, data[key])
    for column, key in SPEC_LISTS:
        if key == "adjudicates":
            row[column] = ";".join(adjudicates_tokens(data, relpath))
        elif key in data:
            row[column] = ";".join(str(v) for v in data[key])
    order = data.get("order")
    return row, order if isinstance(order, int) else None


def read_spec_rows(work_dir, on_error=None):
    """The spec folder's rows in REGISTRY order — by the explicit `order` key,
    then by numeric id, which is the order the converter reproduces.

    Reads BOTH `work_dir` and its archive sibling (`spec_roots`, WI-504): the
    registry is one logical set of rows split across two directory trees — the
    active workspace and the terminal-history archive — and every consumer of
    this function (the scheduler's done-set, the dashboard, the R-A/R-F close
    rules, `intake`'s dedup) wants the UNION, never one half. A relpath is
    computed against whichever root actually holds the file, so `parse_spec_row`
    sees the same `<status>/WI-###-slug.md` shape either way and cannot tell
    which tree it came from — status is the directory, and both trees use the
    identical directory names for it.

    A malformed spec is reported to `on_error` (a callable taking one message)
    and skipped; with no sink it is skipped SILENTLY. That mirrors the split this
    kit already draws over the CSV — a broken registry is the validator's job to
    report, not the scheduler's to crash on. Files are read with universal
    newlines, so a spec checked out CRLF parses identically to one checked out
    LF (the WI-337 lesson: line endings are a property of the checkout)."""
    parsed = []
    for root in spec_roots(work_dir):
        for path in sorted(_spec_files_under(root)):
            relpath = path.relative_to(root).as_posix()
            try:
                row, order = parse_spec_row(path.read_text(encoding="utf-8"), relpath)
            except (ValueError, OSError, UnicodeDecodeError) as exc:
                if on_error is not None:
                    on_error(str(exc))
                continue
            parsed.append(
                (order is None, order or 0, spec_id_number(row["WI-ID"]), row)
            )
    parsed.sort(key=lambda item: item[:3])
    return [item[-1] for item in parsed]


def spec_id_number(wid):
    match = re.search(r"\d+", wid or "")
    return int(match.group()) if match else 0


def shared_spec(ref_a, ref_b):
    """The spec two work items' SpecRefs share, or '' when they name different specs.

    They share one when their files match and either their anchors are equal
    or one of them has none: a whole-document reference covers every section,
    while two different sections of one document are two specs. Items filed
    from one plan's sections cite its sections, and pairing those on the file
    alone made every documented split read as a possible duplicate, which is a
    warning nobody reads. The shared text is the file, or the file and its
    anchor when both name the same section."""
    file_a, _, anchor_a = (ref_a or "").strip().partition("#")
    file_b, _, anchor_b = (ref_b or "").strip().partition("#")
    if not file_a or file_a != file_b:
        return ""
    if anchor_a and anchor_b:
        return ref_a.strip() if anchor_a == anchor_b else ""
    return file_a


def _table_cells(line):
    """A markdown table line's cells, stripped.

    Implements: SR-166, LLR-181
    """
    return [c.strip() for c in line.strip().strip("|").split("|")]


def _plan_header(cells):
    """The lowercased header when `cells` carries a `Plan-WI` column, else None.

    Implements: SR-166, LLR-181
    """
    header = [c.lower() for c in cells]
    return header if "plan-wi" in header else None


def plan_table_rows(text):
    """The proposed work-item rows of a plan: the data rows of the FIRST
    markdown table whose header carries a `Plan-WI` column, each a
    `{lowercased header: cell}` dict, or `[]` when no such table exists.

    A row with an empty `Plan-WI` cell and the `|---|` separator line are not
    rows; a line with no `|` ends the table once it has yielded a row. ONE HOME
    since WI-821: `plan_coverage.parse_plan` (the coverage pre-pass) and
    `plan_artifacts.parse_plan_wis` (the filer) each walked the table with a
    copy of this loop, and each now only picks the cells it needs from it.

    Implements: SR-166, LLR-181
    """
    header, rows = None, []
    for line in text.splitlines():
        if "|" not in line:
            if header is not None and rows:
                break
            continue
        cells = _table_cells(line)
        if header is None:
            header = _plan_header(cells)
            continue
        row = dict(zip(header, cells))
        if row.get("plan-wi") and not set("".join(cells)) <= set("-: "):
            rows.append(row)
    return rows
