#!/usr/bin/env python3
"""Convert the requirement registries from their `.md` + `.csv` carriers to one
TOML carrier (OI-12), losslessly and reversibly.

WHY ONE CARRIER. The spine shipped two: stakeholder needs as markdown prose
tables, SR/LLR/TC as CSV. The split has no recorded rationale anywhere, and it
costs. Reading 32 SN rows takes ~166 code lines across 14 functions in 8
modules; reading all 436 SR+LLR+TC rows takes `csv.DictReader`. TOML is stdlib
at the kit's 3.11 floor (`tomllib`), is already sanctioned in two homes here
(`docs/process.toml`, the `+++` frontmatter of every work-item spec), and holds
the cells that ACTUALLY exist rather than the cells CSV wishes existed: the
comma-bearing cells, the ones holding a literal `|`, the 1,500-character ones,
and the embedded newline CSV cannot represent at all.

WHAT THE CARRIER BUYS THAT A CHECK USED TO. Three integrity rules stop being
code and become properties of the parse:
  * a DUPLICATE ID is a `TOMLDecodeError` — the id is the table key, and TOML
    forbids declaring one twice;
  * a REF LIST is a typed array, retiring the split-on-whitespace rule and with
    it the `SN-001 and SN-002` -> "`and` is an orphan" defect;
  * an EMPTY CELL is an ABSENT KEY, so "unset" and "set to empty" stop being
    the same string.

WHAT THIS DELIBERATELY DOES NOT DO. Carrier only. `Status` keeps whatever
vocabulary the tree it converts already uses — `Drafted` / `Approved` /
`Founded` since D-9 steps 5/7/8 — and a value this converter does not recognize
is COPIED, never mapped. That is the rule, not an omission: a downstream tree
still carrying `Modified` (or `Draft`, or `Verified`) owes a human ruling on
each such row, and a carrier conversion that stamped them clean would launder
exactly the re-blessing they owe (repo-lock Q11). The always-on integrity floor
names them after the conversion, which is where they should be named. No anchor
cells, no `Priority` float, no `SupersededBy` deletion, no SN `Status`. Those
land once, on this carrier, in the D-3/D-4 pass.

REVERSIBILITY IS THE POINT OF `--check`. It re-reads what it wrote and asserts
the round-trip is cell-for-cell identical to the source, so a conversion that
silently drops a cell fails here rather than in a gate three commits later.

Contracts: IF-103 — the seam this module declares (process.md §8; row of record
in docs/requirements/interfaces.toml).

Contract IF-103: this CLI rewrites the registries under
    `docs/requirements` in place, and the bytes it writes are the whole seam —
    it reads them and writes beside them, consuming no other kit module. The
    default arm converts each `.md`/`.csv` registry to its `.toml` carrier;
    `--if-shape` rewrites an old-shape `interfaces.toml` to the owner /
    requestors-or-consumers / channel / data shape. EVERY conversion is
    round-tripped against an oracle built from the RAW source, never from the
    converter's own parse: each cell that does not survive is printed as a
    `migrate_carrier: LOSSY - ...` line on stderr and the run exits 1, so a
    dropped cell is named at the conversion rather than in a gate three commits
    later. `--check` performs that same conversion and comparison in memory and
    writes nothing. Carrier only: a Status word the converter does not
    recognize is COPIED, never mapped, so a conversion can never launder a
    re-blessing a human still owes.

Requirements: SR-147 (one machine-parseable carrier for the spine).
"""

import argparse
import csv
import io
import re
import sys
import tomllib
from pathlib import Path

from kitlib import spine as _kitspine

# The id prefix stays in the key (`[requirement.SR-137]`, bare — TOML allows
# `-` in a bare key). It is redundant inside a file already named
# system-requirements.toml, and that redundancy is exactly the point: the
# prefixed token is the join key ~6,400 hand-authored citations use, so the
# registry must remain findable by the same string every commit message,
# log entry and archived document cites.
SPINE = {
    "docs/requirements/system-requirements.csv": ("requirement", "SR-ID"),
    "docs/requirements/low-level-requirements.csv": ("design", "LLR-ID"),
    "docs/test/test-cases.csv": ("test", "TC-ID"),
}

# BATCH-2 (repo-lock.md §8.1): the off-spine registries the same ruling covers.
# Same converter, one `KEY` map, because a SECOND converter is the D-6 hazard
# exactly — two writers for one carrier drift, and their divergence is silent
# content loss on the registries the kit exists to make trustworthy.
#
# `interfaces.csv` and `components.csv` JOINED at WI-443, and the wait was the
# point: §8.1 sequenced the first behind OI-14 (which rewrites what a `Contract`
# cell may hold) and the second behind the components ruling (which is ABOUT CMP
# rows). Both are ruled now — OI-14 part B, 2026-08-13 — so each converts ONCE,
# carrying its new columns (`Signal`, `SignalNote`, `Rationale`) and its retired
# one (`Status`, undeclared since it shipped; `Stability` is the one maturity
# field) in the same pass rather than in a second migration of the same rows.
#
# The TEMPLATE paths ride the same map rather than a second pass. They exist
# only in the kit repo — a scaffold gets the filled `docs/` copy, never the
# `*.template.*` — so `convert`'s missing-file skip makes their presence here
# free for an adopter and keeps the kit's own conversion on the one code path
# the round-trip check covers.
OFFSPINE = {
    "docs/requirements/open-items.csv": ("open_item", "OI-ID"),
    "docs/agents.csv": ("agent", "Id"),
    "docs/requirements/interfaces.csv": ("interface", "IF-ID"),
    "docs/requirements/components.csv": ("component", "CMP-ID"),
    "project-trajectory/registries/open-items.template.csv": ("open_item", "OI-ID"),
    "project-trajectory/agents.template.csv": ("agent", "Id"),
    "project-trajectory/registries/interfaces.template.csv": ("interface", "IF-ID"),
    "project-trajectory/registries/components.template.csv": ("component", "CMP-ID"),
}

# Cells that are REFERENCE LISTS become typed arrays. Everything else stays a
# string: this is a carrier change, not a schema change.
#
# `TestRefs` is DELIBERATELY NOT HERE, and it was until the cutover measured it.
# The column's conventional value is `(see TC-017)` — a prose pointer, which
# check_doc_refs names as such where it declines to read a path out of it — and
# only one row of 141 holds a bare id list. Splitting prose on whitespace made
# `test_refs = ["(see", "TC-017)"]`, which re-joins as `(see; TC-017)`: a
# TEXT CHANGE to 140 design rows, smuggled into a carrier-only migration, and
# the very defect the typed array exists to retire (`SN-001 and SN-002` ->
# "`and` is an orphan") committed in the other direction. As a plain string
# every shape round-trips byte-exact and every consumer keeps the split rule it
# already applied to this cell under CSV.
#
# `WI-Refs` (open-items) JOINS THEM and `Version` (agents) DOES NOT, both by the
# same measurement the `TestRefs` paragraph above describes. Every live and
# shipped `WI-Refs` cell is empty or a bare `WI-###`, so the typed array is
# what the cell already meant. (Since WI-790 the cell is declared historical
# metadata, `kitlib.spine.HISTORICAL_KEYS`: carried byte-for-byte on the rows
# that have it, read by no consumer; a work item's `needs` cites its open item.) `Version` reads numeric — `4.8`,
# `5.6` — and is exactly the trap: as a TOML float it stops being the text the
# registry stores, and `agent_route._version_key` parses its dotted-numeric
# tuple out of that text. A carrier change has no licence to renormalise a
# version string.
REF_COLS = {
    "SN-Refs",
    "SR-Refs",
    "Boundary-Refs",
    # WI-484: a typed array like every other multi-ref cell. A hat NAME carries no
    # comma or semicolon (`hats.py` keys are upper-case, `-`-joined), so the
    # `trace_text.refs` split reads it back exactly as written.
    "Hat-Refs",
    # SR-189: a need's stakeholders, STK ids, which hold no separator.
    "Stakeholder-Refs",
    # SR-193: a requirement's assumptions and joint-delivery siblings;
    # SR-191/SR-192: an assumption's landing crossings and obstacle
    # perspectives, a surrogate's emulated parties. Every entry is an id or a
    # hat name, which holds no separator.
    "DA-Refs",
    "Delivered-With",
    "EffectAt",
    "ObstacleHats",
    "Emulates",
    # SR-197: the assumptions a test case evidences; SR-198: the repository
    # paths and row ids an observation case's judgment reads. Neither holds a
    # separator.
    "Assumption-Refs",
    "Inputs",
    "Verifies",
    "SupersededBy",
    "WI-Refs",
    # WI-455: an IF row's consuming side is a LIST — it always held several
    # `;`-joined endpoints on the rows that have several, and the reader
    # (`kitlib.spine.seam_endpoints`) splits on `;` alone, so the typed array is
    # what the cell already meant.
    "Requestors",
    "Consumers",
    # SR-211: an interface's bridging assumptions, DA ids, which hold no
    # separator.
    "BridgedBy",
}
# SR-198: an observation case's lifetime in days and its sample size are whole
# numbers. A value that does not parse is preserved as text, as for `Phase`, so
# `assumption_rules.observation_tc_findings` can name it rather than the
# conversion dropping it.
INT_COLS = {"Phase", "MaxAge", "SampleSize", "MinWorkItems"}

# column -> TOML key. EXPLICIT, never derived: a derivation turns `SR-ID` into
# `s_r_i_d`, and the column name is a repo-wide term (D-3) that deserves a
# stated mapping rather than a regex nobody can predict.
# Implements: SR-193, SR-197, SR-198, LLR-222
KEY = {
    "Title": "title",
    "SN-Refs": "sn_refs",
    "Boundary-Refs": "boundary_refs",
    "Hat-Refs": "hat_refs",
    "SR-Refs": "sr_refs",
    "Verifies": "verifies",
    "Requirement": "requirement",
    "Rationale": "rationale",
    "AcceptanceCriteria": "acceptance_criteria",
    "Permutations": "permutations",
    "Priority": "priority",
    "Verification": "verification",
    "Status": "status",
    "Need": "need",
    "Why": "why",
    "Acceptance": "acceptance",
    "Tags": "tags",
    "Phase": "phase",
    "Aspect": "aspect",
    "SupersededBy": "superseded_by",
    "Lifecycle": "lifecycle",
    "Detail": "detail",
    "Module": "module",
    "CodeSymbol": "code_symbol",
    "TestRefs": "test_refs",
    "Level": "level",
    "Method": "method",
    "Expected": "expected",
    "Parameters": "parameters",
    "Automated": "automated",
    "Evidence": "evidence",
    "Tier": "tier",
    "Component": "component",
    "Notes": "notes",
    # batch-2 (repo-lock §8.1). `Title`/`Status`/`Tier`/`Notes` are ALREADY
    # above and are deliberately not repeated: D-3 rules that a column name
    # means one thing repo-wide, so one map serves every registry and a second
    # entry for the same column would be the drift the map exists to prevent.
    # open-items:
    "Raised": "raised",
    "OneLine": "one_line",
    "Decision": "decision",
    "BlastRadius": "blast_radius",
    "Options": "options",
    "Recommendation": "recommendation",
    "WI-Refs": "wi_refs",
    "RuledDate": "ruled_date",
    "RulingRef": "ruling_ref",
    # agents:
    "Family": "family",
    "Model": "model",
    "Version": "version",
    "CmdTemplate": "cmd_template",
    "Env": "env",
    # interfaces (WI-443 / OI-14 part B). `Rationale`/`Component`/`Notes`/
    # `Version` are ALREADY above and deliberately not repeated — D-3's
    # one-name-one-meaning rule again. `Req-Refs` IS repeated-looking but is not:
    # it is a DIFFERENT column from the spine's `SR-Refs`, split out at the
    # 2026-08-15 rework because the one name carried two relationships (an LLR's
    # parent requirement; an interface's realizing/relying requirements). D-3 is
    # what forced the split. `Status` has NO entry because the column
    # RETIRES here (undeclared since it shipped, overlapping `Stability` on the
    # same row); a stray `Status` cell would therefore key as `Status` and be
    # caught by the schema tier rather than silently absorbed.
    # `Stability` LEFT this block at WI-442, replaced by `Approval`.
    # `ThisProject`/`Counterpart` LEFT AT WI-455 (OI-60 ruled (a)), replaced by
    # `Provider`/`Consumers`, and the IF tier's `Direction` reading went with
    # them — the `Direction` entry below is now the BOUNDARY tier's alone. A
    # legacy CSV still carrying the retired columns keys them as themselves
    # (`KEY.get(col, col)`) and the schema tier names them, exactly as a stray
    # `Status` cell is handled: convert the carrier first, then rename the cells
    # (RESYNC_PACK.md).
    # `Req-Refs`, `Provider`, `Signal` and `SignalNote` LEFT this block at OI-67
    # (ruled (a), 2026-08-29) with the row shape they described; a legacy CSV
    # still carrying them keys them as themselves and the schema tier names
    # them. `Owner` is the providing thing now, a path, and `Channel`/`Data`
    # are the typed statement beside it.
    "Owner": "owner",
    "Channel": "channel",
    "Data": "data",
    # The optional seam-tier verification pointer (OI-61's sub-question,
    # sanctioned 2026-08-23). A legacy CSV will not carry it; a converter that
    # did not map it would silently drop the cell on the one repo that did.
    "VerifiedBy": "verified_by",
    "CarriedBy": "carried_by",
    "Requestors": "requestors",
    "Consumers": "consumers",
    "InterfaceFromExternal": "interface_from_external",
    "InterfaceToExternal": "interface_to_external",
    # SR-211: a boundary interface's bridging assumptions (its waiver is the
    # shared `Coincident`, above). Never converted from a legacy carrier.
    "BridgedBy": "bridged_by",
    # components (WI-443). `Notes`/`SupersededBy` are ALREADY above.
    "Name": "name",
    "Category": "category",
    "Knowledge": "knowledge",
    "Standing": "standing",
    "PartOf": "part_of",
    # external — the depth-0 frame (WI-442). This registry never had a CSV
    # carrier and so is never CONVERTED by this script; the entries exist
    # because this map is the writer half of the ONE column vocabulary, pinned
    # as an exact bijection against `spine_carrier.REGISTRY_COLUMN`
    # (tests/test_rule_sync.py). A tier the vocabulary knows and this map does
    # not would be a column the reader can name and the writer cannot.
    # `Approval`/`Notes`/`Name` are ALREADY above. `Direction` is DECLARED HERE
    # since WI-455: the IF tier's Provides|Consumes reading is gone, so the
    # column now carries the boundary tier's in|out|inout alone and belongs in
    # this block — the collision spine_carrier's note watched is closed.
    "Direction": "direction",
    "Class": "class",
    "Description": "description",
    "Entity": "entity",
    "Carries": "carries",
    "System": "system",
    "Mediates": "mediates",
    "From": "from",
    "To": "to",
    "Kind": "kind",
    "Flow": "flow",
    "Absorbs": "absorbs",
    # the stakeholder list and the need's two pointers (SR-189, SR-190). Never
    # converted from a legacy carrier (neither existed before TOML); declared
    # because this map is the writer half of the one pinned bijection.
    "Party": "party",
    "Stakeholder-Refs": "stakeholder_refs",
    "Source": "source",
    # the requirement's assumption citations, joint-delivery siblings, waiver
    # and form (SR-193, SR-194), and the assumptions registry's own cells
    # (SR-191, SR-192). Never
    # converted from a legacy carrier; declared as the writer half of the one
    # pinned bijection.
    "DA-Refs": "da_refs",
    "Delivered-With": "delivered_with",
    "Coincident": "coincident",
    "Form": "form",
    "EffectAt": "effect_at",
    "Assumption": "assumption",
    "HoldsWhen": "holds_when",
    "Obstacle": "obstacle",
    "Falsifier": "falsifier",
    "AcceptedRisk": "accepted_risk",
    "RealizedBy": "realized_by",
    "ObstacleHats": "obstacle_hats",
    "Emulates": "emulates",
    # the test case's assumption evidence (SR-197) and an observation case's
    # declaration (SR-198). Never converted from a legacy carrier; declared as
    # the writer half of the one pinned bijection.
    "Assumption-Refs": "assumption_refs",
    "Inputs": "inputs",
    "MaxAge": "max_age",
    "Rubric": "rubric",
    "Trigger": "trigger",
    "MinWorkItems": "min_work_items",
    "Sampling": "sampling",
    "SampleSize": "sample_size",
    "AcceptanceRule": "acceptance_rule",
}


def toml_scalar(value):
    """A Python str/int/list as a TOML value.

    Multi-line basic strings for anything long or newline-bearing, which is
    what makes the prose cells representable at all. `tomllib` is read-only by
    design (PEP 680 omitted a writer), so the kit emits its own — as it already
    does twice, in `wi_convert.toml_string` and `bootstrap.set_process_key`.
    """
    if isinstance(value, list):
        return "[" + ", ".join(toml_scalar(v) for v in value) + "]"
    if isinstance(value, int) and not isinstance(value, bool):
        return str(value)
    text = str(value)
    if "\n" in text or len(text) > 88:
        body = text.replace("\\", "\\\\").replace('"""', '\\"\\"\\"')
        # A value ending in `"` would glue to the closing delimiter.
        if body.endswith('"'):
            body = body[:-1] + '\\"'
        return '"""' + body + '"""'
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def cell_to_value(col, raw):
    """One CSV cell as the value its column means. Empty -> None (key omitted).

    A plain cell is carried VERBATIM, not stripped. Stripping looks harmless and
    is not: the conversion advertises "cell for cell", and a cell whose leading
    or trailing whitespace is content — an indented code fragment, a padded
    fixed-width note — silently lost it. Worse, the loss detector stripped BOTH
    sides, so it compared the converter's output against the converter's own
    reading and reported `findings=[]` on a real change. `.strip()` survives
    only where it decides EMPTINESS (a whitespace-only cell is an empty cell,
    which is an absent key), and in the ref/int parses where the surrounding
    whitespace is separator syntax rather than content."""
    text = (raw or "").strip()
    if not text:
        return None
    if col in REF_COLS:
        return [t for t in re.split(r"[;,\s]+", text) if t]
    if col in INT_COLS:
        try:
            return int(text)
        except ValueError:
            return text  # a non-integer Phase is data to preserve, not to crash on
    return raw


# A TOML BARE key is `[A-Za-z0-9_-]+`. A DOT is the table-path separator, so an
# id carrying one must be QUOTED or it silently becomes nested tables: written
# bare, `[agent.ANTHROPIC-OPUS-4.8]` declares `agent.ANTHROPIC-OPUS-4` with a
# child table `8`, and the row's id disappears from the registry while the file
# still parses. The spine never met this because `SR-137` has no dot;
# `agents.csv` ids are model versions (`ANTHROPIC-OPUS-4.8`, `OPENAI-GPT-5.2`)
# and routinely do.
_BARE_KEY_RE = re.compile(r"^[A-Za-z0-9_-]+$")


def toml_key(rid):
    """One row id as a TOML table key — bare where TOML allows it (so the file
    reads like the spine's and the id greps as itself), quoted where it does
    not. `raw_id_findings` is the leg that proves the choice was made
    correctly, by reading ids off the RAW source and demanding each one back as
    a key."""
    if _BARE_KEY_RE.match(rid):
        return rid
    return '"' + rid.replace("\\", "\\\\").replace('"', '\\"') + '"'


def rows_to_toml(table, id_col, rows, header, comments=()):
    """The whole registry as TOML text, source order preserved.

    `comments` is `[(row_index, raw_line)]` — a source comment line and the
    index of the row it preceded (`len(rows)` for a trailing one). COMMENTS ARE
    CARRIED, not dropped, and one of them is executable: `agents.csv` holds a
    `# tag-rank: ga>preview>beta>exp` line that `agent_route.load_tag_rank`
    parses, so dropping comments would silently reset the maturity vocabulary
    used to resolve a version-less model token. TOML's comment is native and
    identical in syntax to the CSV convention these files already used, so each
    line survives BYTE-FOR-BYTE and in place — the prose that documents a
    registry stays next to the rows it documents."""
    pending = {}
    for index, raw in comments:
        pending.setdefault(index, []).append(raw)
    out = io.StringIO()

    def flush(index):
        block = pending.pop(index, [])
        for raw in block:
            out.write(raw + "\n")
        if block:
            out.write("\n")

    for position, row in enumerate(rows):
        rid = (row.get(id_col) or "").strip()
        if not rid:
            continue
        flush(position)
        out.write("[{}.{}]\n".format(table, toml_key(rid)))
        for col in header:
            if col == id_col:
                continue
            value = cell_to_value(col, row.get(col))
            if value is None:
                continue
            out.write("{} = {}\n".format(KEY.get(col, col), toml_scalar(value)))
        out.write("\n")
    for index in sorted(pending):
        for raw in pending[index]:
            out.write(raw + "\n")
    return out.getvalue()


def read_csv_records(text, id_col):
    """`(header, rows, comments)` for one CSV registry.

    `rows` is the row dicts in file order; `comments` is `[(row_index, raw)]`,
    the raw comment lines keyed to the row each preceded.

    WHY NOT `csv.DictReader`. A comment is a RECORD in these files, not noise:
    `docs/agents.csv` opens with three `#` lines, one of which
    (`# tag-rank: ...`) is parsed by `agent_route.load_tag_rank`. DictReader has
    no comment concept, so it splits
    `# The ai-template META-repo's own routing registry (WI-107; ...` on its
    commas and returns a nine-cell row whose `Id` is the first clause — which is
    how a comment becomes a row, and then a row becomes a model the router might
    try to launch. The spine's registries carry no comments, which is why its
    branch never needed this.

    The raw line is recovered through `csv.reader.line_num`, NEVER by splitting
    the file on newlines: a quoted cell may legally span lines, and a
    line-splitting reader would read a `#` inside one as a comment and cut the
    row in half."""
    lines = text.split("\n")
    reader = csv.reader(io.StringIO(text))
    header, rows, comments, findings, prev = [], [], [], [], 0
    for record in reader:
        raw = "\n".join(lines[prev : reader.line_num]).rstrip("\r")
        prev = reader.line_num
        if not header:
            header = list(record)
            continue
        if not any(cell.strip() for cell in record):
            continue
        if record[0].lstrip().startswith("#"):
            comments.append((len(rows), raw))
            continue
        if len(record) > len(header):
            # Silently dropped by `zip` otherwise. A cell past the header is
            # either a stray comma inside an unquoted cell or a column nobody
            # declared; both are content, and content is not this conversion's
            # to lose.
            findings.append(
                "{!r}: {} cell(s) past the {}-column header".format(
                    record[0], len(record) - len(header), len(header)
                )
            )
        row = dict(zip(header, record))
        if (row.get(id_col) or "").strip():
            rows.append(row)
    return header, rows, comments, findings


def raw_comment_findings(rel, comments, text):
    """Findings for a source comment line absent from the emitted TOML.

    One of the two INDEPENDENT legs for the off-spine branch. `compare` is a
    self-oracle for comments by construction — it is handed the same record
    split the emitter used — so it is silent about a comment the splitter
    mis-filed. This one reads the source's own bytes back out of the result."""
    return [
        "{}: comment line {!r} is in the source and absent from the conversion".format(
            rel, raw[:60]
        )
        for _index, raw in comments
        if raw not in text
    ]


# An id at the head of a CSV record, read off the RAW source with no reference
# to how the record splitter chose to interpret the line. `#` cannot start the
# match, so a genuine comment is correctly not demanded back as a row.
_RAW_ID_RE = re.compile(r'^"?([A-Za-z0-9][A-Za-z0-9._-]*)"?\s*,', re.MULTILINE)


def raw_id_findings(rel, table, raw, text):
    """Findings for an id present in the RAW CSV and absent from the emitted
    TOML's table keys — the second independent leg. `raw` is the whole source;
    its FIRST LINE is dropped, because the header's first cell (`OI-ID`, `Id`)
    heads a record but names a column rather than a row.

    THIS IS THE LEG THAT CATCHES THE DOTTED ID. `[agent.ANTHROPIC-OPUS-4.8]`
    written bare parses cleanly as two nested tables, so the emitted file is
    valid TOML, `compare` finds the row under a key it constructed the same
    wrong way, and nothing reds — while the registry has quietly lost a model
    row. Reading the ids off the source and demanding each one back as a
    top-level key is the only check that does not inherit the mistake."""
    try:
        got = tomllib.loads(text).get(table, {})
    except tomllib.TOMLDecodeError:
        return []  # `compare` reports the decode error; one finding is enough
    body = raw.split("\n", 1)[1] if "\n" in raw else ""
    missing = [
        rid
        for rid in dict.fromkeys(_RAW_ID_RE.findall(body))
        if not isinstance(got.get(rid), dict)
    ]
    return [
        "{}: {} heads a record in the source and is not a table in the "
        "conversion — the row was dropped, or its id was written as a bare key "
        "TOML read as a table path".format(rel, rid)
        for rid in missing
    ]


def value_to_cell(col, value):
    """The inverse of `cell_to_value`, for the round-trip check.

    A ref array re-joins on `;` — the separator the registry ACTUALLY USES, not
    a prettier one. Measured over this repo's own spine at the cutover: 271 of
    271 multi-ref cells wrote `A;B`, none wrote `A; B`. Joining on `"; "`
    therefore rewrote every one of them, which put ~40 spurious "cell changed"
    entries into the re-attestation brief the owner is about to work — the
    carrier migration manufacturing amendments in the one view that must show
    only real ones. The separator is not the meaning (`_cells_differ` compares
    token lists either way), which is exactly why the conversion has no licence
    to change it."""
    if value is None:
        return ""
    if isinstance(value, list):
        return ";".join(str(v) for v in value)
    return str(value)


REF_KEYS = {KEY[c] for c in REF_COLS}


def _cells_differ(key, before, after):
    """Did this cell survive? Ref cells compare on the TOKEN LIST, because the
    conversion re-joins them with the canonical separator and the original
    spacing is not part of the meaning."""
    if key in REF_KEYS:
        split = lambda t: [x for x in re.split(r"[;,\s]+", t) if x]  # noqa: E731
        return split(before) != split(after)
    return before != after


# Every markdown line that IS a need row, read off the RAW source with no
# reference to how `read_sn` chose to interpret it. `^| SN-### |` is the shape
# the tier has always used, and it is the one thing about the legacy carrier
# that can be asserted without re-implementing the reader.
_RAW_SN_ROW = re.compile(r"^\|\s*(SN-\d+)\s*\|", re.MULTILINE)


def raw_need_findings(rel, raw, text):
    """Findings for any need present in the RAW markdown and absent from the
    emitted TOML — the oracle `compare` cannot be, because `compare` is handed
    the reader's output as its expectation.

    THIS IS THE SECOND, INDEPENDENT LEG. The self-oracle answers "did every cell
    the reader saw survive"; it is silent by construction about a row the reader
    never saw. A heading it did not recognise used to make a whole table
    invisible and still report `findings=[]` — a converter certifying its own
    blind spot. An adopter with locally edited registries is exactly who runs
    this, and they have no other way to find out."""
    try:
        got = tomllib.loads(text).get("need", {})
    except tomllib.TOMLDecodeError:
        return []  # `compare` reports the decode error; one finding is enough
    missing = sorted({rid for rid in _RAW_SN_ROW.findall(raw)} - set(got))
    return [
        "{}: {} is a need row in the source and is absent from the conversion "
        "— the reader did not recognise it (an unfamiliar heading?), so the "
        "round-trip check never saw it either".format(rel, rid)
        for rid in missing
    ]


def compare(rel, table, expected, text):
    """Findings for one converted registry. `expected` is {id: {key: text}} —
    built from CSV columns or from markdown cells, so ONE comparison serves
    both carriers instead of a second copy that drifts from the first."""
    try:
        got = tomllib.loads(text).get(table, {})
    except tomllib.TOMLDecodeError as exc:
        return ["{}: emitted TOML does not parse — {}".format(rel, exc)]
    findings = []
    if len(got) != len(expected):
        findings.append(
            "{}: {} rows in, {} tables out".format(rel, len(expected), len(got))
        )
    for rid, cells in expected.items():
        if rid not in got:
            findings.append("{}: {} missing after conversion".format(rel, rid))
            continue
        for key, before in cells.items():
            after = value_to_cell(key, got[rid].get(key))
            if _cells_differ(key, before, after):
                findings.append(
                    "{} {}.{}: {!r} -> {!r}".format(
                        rel, rid, key, before[:60], after[:60]
                    )
                )
    return findings


# --- the SN tier: markdown prose tables, three shapes -------------------------
# The edge-case table has its OWN columns (Lifecycle | Scenario | Expected), and
# they are kept as themselves here rather than folded onto the core four. The
# fold that spine_carrier.folded performs is a PRESENTATION rule for the
# exports — an edge row's Scenario reads as the need, its Lifecycle as the why —
# and presentation belongs in the exporter, not baked into the carrier. TOML can
# hold both shapes; the markdown table could not, which is why the fold existed.
SN_REL = "docs/requirements/stakeholder-needs.md"
SN_CORE = ("need", "why", "priority", "acceptance")
SN_EDGE = ("lifecycle", "scenario", "expected")


def read_sn(path):
    """[(id, kind, {field: text})] in document order.

    A ROW IS NEVER DROPPED FOR ITS HEADING. `kind` comes from the heading when
    the heading is one this reader knows, and from the table's SHAPE when it is
    not — the same fallback `spine_carrier.needs_from_markdown` applies, for a
    sharper reason on this side: a heading the vocabulary does not recognise
    ("## Miscellaneous", "## Deferred") used to make every need under it
    invisible, and because the loss oracle was built from THIS function's
    output, a whole table could vanish with `findings=[]`. An unrecognised
    heading is a naming choice; it is not a statement that the rows below are
    not needs (the review's B2).

    Cells are stripped here and that is correct: the padding around `|` is the
    markdown table's SYNTAX, not content — unlike a CSV cell, where whitespace
    inside the quotes is data."""
    kind, out = None, []
    for line in path.read_text(encoding="utf-8").split("\n"):
        heading = re.match(r"^#{2,}\s+(.*)$", line)
        if heading:
            title = heading.group(1).lower()
            kind = (
                "draft"
                if "draft" in title
                else "edge"
                if "edge" in title
                else "core"
                if "core" in title or "need" in title
                else None
            )
            continue
        row = re.match(r"^\|\s*(SN-\d+)\s*\|", line)
        if not row:
            continue
        cells = [c.strip() for c in line.split("|")[1:-1]]
        # No heading, or one this reader does not name: resolve by the table's
        # width, exactly as the live reader does — the edge table is three cells
        # wide beside its id, the core table four.
        row_kind = kind or ("edge" if len(cells) - 1 == len(SN_EDGE) else "core")
        names = SN_EDGE if row_kind == "edge" else SN_CORE
        out.append((cells[0], row_kind, dict(zip(names, cells[1 : 1 + len(names)]))))
    return out


def sn_status(kind):
    """The heading-derived `kind` as the ONE spine maturity word.

    Section-as-state carried exactly two maturities — a row sat under a draft
    heading or it did not — so this mapping is TOTAL and loses nothing. `kind`
    itself does not survive the conversion: it conflated maturity with row TYPE,
    and the type half (`edge`) is retired (owner ruling 2026-08-17j).

    ONE HOME because the LOSS ORACLE compares against it. If the emitter and the
    oracle each derived the word, a drift between them would make the oracle
    agree with the bug — an oracle built from the thing under test cannot
    fail, which is the defect the raw-source oracle beside it exists to avoid."""
    return "Drafted" if kind == "draft" else "Approved"


def sn_to_toml(needs):
    out = io.StringIO()
    for rid, kind, fields in needs:
        out.write("[need.{}]\n".format(rid))
        out.write('status = "{}"\n'.format(sn_status(kind)))
        for name in SN_EDGE if kind == "edge" else SN_CORE:
            text = (fields.get(name) or "").strip()
            if text:
                out.write("{} = {}\n".format(name, toml_scalar(text)))
        out.write("\n")
    return out.getvalue()


def _emit(root, src, text, count, noun, write, written):
    """Write one converted registry beside its source and report it.

    Shared by both carriers rather than repeated per branch: the tail is
    identical, so a change to the report line cannot land in one branch only."""
    dest = src.with_suffix(".toml")
    if write:
        dest.write_text(text, encoding="utf-8", newline="\n")
        written.append(dest)
    print(
        "migrate_carrier: {} -> {} ({} {}, {} bytes)".format(
            src.relative_to(root).as_posix(),
            dest.relative_to(root).as_posix(),
            count,
            noun,
            len(text),
        )
    )
    return dest


def convert(root, write):
    """Convert every spine registry. Returns (findings, written_paths)."""
    findings, written = [], []
    sn_src = root / SN_REL
    if sn_src.is_file():
        raw = sn_src.read_text(encoding="utf-8")
        needs = read_sn(sn_src)
        text = sn_to_toml(needs)
        expected = {
            rid: dict(
                {"status": sn_status(kind)},
                **{k: v.strip() for k, v in f.items() if v.strip()},
            )
            for rid, kind, f in needs
        }
        findings += raw_need_findings(SN_REL, raw, text)
        findings += compare(SN_REL, "need", expected, text)
        _emit(root, sn_src, text, len(needs), "needs", write, written)
    for rel, (table, id_col) in sorted(SPINE.items()):
        src = root / rel
        if not src.is_file():
            continue
        reader = _kitspine.csv_reader(
            src.read_text(encoding="utf-8-sig", errors="replace")
        )
        header = list(reader.fieldnames or [])
        rows = [r for r in reader if (r.get(id_col) or "").strip()]
        text = rows_to_toml(table, id_col, rows, header)
        # THE ORACLE READS THE RAW SOURCE, never the converter's own parse.
        # The cell text here is exactly what `csv` handed back — unstripped, so
        # a conversion that trimmed content is a FINDING rather than a match
        # against its own trimming. An oracle built from the thing under test
        # cannot fail, and this one did not (the review's B2).
        expected = {
            (r.get(id_col) or "").strip(): {
                KEY.get(c, c): (r.get(c) or "")
                for c in header
                if c != id_col and (r.get(c) or "").strip()
            }
            for r in rows
        }
        findings += compare(rel, table, expected, text)
        _emit(root, src, text, len(rows), "rows", write, written)
    findings += _convert_offspine(root, write, written)
    return findings, written


def _convert_offspine(root, write, written):
    """The batch-2 registries (repo-lock §8.1). Findings; appends to `written`.

    Its own function rather than a third arm of the spine loop, because it
    carries a record split the spine does not need (comments) and two extra
    oracle legs — and because a reader arriving at `convert` should be able to
    see which registries §8.1 sequences here and which two it deliberately
    holds back."""
    findings = []
    for rel, (table, id_col) in sorted(OFFSPINE.items()):
        src = root / rel
        if not src.is_file():
            continue
        # `newline=""` and NOT `read_text`: universal-newline translation would
        # rewrite a CRLF inside a quoted cell to LF, which is a content change
        # smuggled into a carrier conversion — and the one the open-items view
        # already had to grow `gen_open_items.normalize` for.
        with src.open(newline="", encoding="utf-8-sig", errors="replace") as fh:
            raw = fh.read()
        header, rows, comments, findings_shape = read_csv_records(raw, id_col)
        findings += ["{}: {}".format(rel, f) for f in findings_shape]
        text = rows_to_toml(table, id_col, rows, header, comments)
        # THE ORACLE READS WHAT `csv` HANDED BACK — unstripped, so a conversion
        # that trimmed content is a finding rather than a match against its own
        # trimming (the spine branch's B2, and the same rule here).
        expected = {
            (r.get(id_col) or "").strip(): {
                KEY.get(c, c): (r.get(c) or "")
                for c in header
                if c != id_col and (r.get(c) or "").strip()
            }
            for r in rows
        }
        findings += compare(rel, table, expected, text)
        findings += raw_comment_findings(rel, comments, text)
        findings += raw_id_findings(rel, table, raw, text)
        _emit(root, src, text, len(rows), "rows", write, written)
    return findings


# --- the IF row's SHAPE change (OI-67 ruled (a), 2026-08-29) -------------------
# Not a carrier change: the registry is already TOML. A row that carried
# `provider` / `req_refs` / `signal` / `signal_note` and an id-typed `owner`
# becomes one owner, its far side and a typed statement. The mechanical half is
# done here IN PLACE — comments, order and every other cell kept — and the
# judgement half (which far side, which channel, the owner no cell ever named)
# is REPORTED beside its row rather than guessed silently.
IF_REL = "docs/requirements/interfaces.toml"
LLR_REL = "docs/requirements/low-level-requirements.toml"
IF_RETIRED = ("provider", "req_refs", "signal", "signal_note")
_ID_OWNER_RE = re.compile(r'^owner = "((?:SR|LLR)-\d+)"$')
_KEY_RE = re.compile(r"^([a-z_]+)\s*=\s*(.*)$")


def _short_module(module):
    m = module.strip().replace("\\", "/")
    if m.startswith("project-trajectory/"):
        m = m[len("project-trajectory/") :]
    return m[:-3] if m.endswith(".py") else m


def _llr_single_modules(root):
    """`{LLR-###: module}` for the design rows naming exactly ONE module — the
    only ones an id-typed owner can be folded through without guessing."""
    path = root / LLR_REL
    if not path.is_file():
        return {}
    out = {}
    for rid, row in (
        tomllib.loads(path.read_text(encoding="utf-8")).get("design", {}).items()
    ):
        mods = [
            m.strip()
            for m in (row.get("module") or "").replace(";", ",").split(",")
            if m.strip()
        ]
        if len(mods) == 1:
            out[rid] = _short_module(mods[0])
    return out


def _seed_channel(owner):
    if owner.startswith("external:"):
        return "bytes"
    if owner.endswith("/") or "." in owner.rsplit("/", 1)[-1]:
        return "file"
    return "call"


def _if_block_cells(lines):
    """`{key: (start, end)}` line spans of one `[interface.IF-###]` block,
    multi-line strings included."""
    cells, i = {}, 1
    while i < len(lines):
        km = _KEY_RE.match(lines[i])
        if km:
            start, val = i, km.group(2)
            if val.startswith('"""') and val.count('"""') == 1:
                i += 1
                while '"""' not in lines[i]:
                    i += 1
            cells[km.group(1)] = (start, i)
        i += 1
    return cells


def _fold_owner(raw, rid, llr_modules, report):
    """The new `owner` for one old-shape row, or None when nothing derives it:
    the stated `provider` wins, else the owner design row's single module; an
    id-typed owner with neither is REPORTED for the adopter to name by hand."""
    owner = (raw.get("owner") or "").strip()
    provider = (raw.get("provider") or "").strip()
    if provider:
        return provider
    if owner in llr_modules:
        return llr_modules[owner]
    if re.match(r"^(SR|LLR)-\d+$", owner):
        report.append(
            "{}: owner {!r} could not be derived (no provider, no single-module "
            "design row) — name the medium this seam plugs into by hand".format(
                rid, owner
            )
        )
    return None


def _rewrite_if_lines(lines, cells, new_owner, channel):
    """The block's lines with the retired cells dropped, the owner replaced
    and `channel` inserted after the far side (or after the owner when the
    row names none)."""
    skip = set()
    for key in IF_RETIRED:
        if key in cells:
            s, e = cells[key]
            skip.update(range(s, e + 1))
    owner_at = cells.get("owner", (-1, -1))[0]
    far_at = cells.get("consumers", (-1, -1))[0]
    channel_line = 'channel = "{}"\n'.format(channel)
    out = []
    for idx, line in enumerate(lines):
        if idx in skip:
            continue
        out.append(
            'owner = "{}"\n'.format(new_owner)
            if new_owner and idx == owner_at
            else line
        )
        if idx == far_at or (far_at < 0 and idx == owner_at):
            out.append(channel_line)
    return out


def _convert_if_block(blk, rid, llr_modules, report):
    """One row's rewrite, or the block unchanged when it already has the shape."""
    raw = tomllib.loads(blk)["interface"][rid]
    if raw.get("contract"):
        # Not dropped: its content has no mechanical home. Reported, and the
        # armed gate names the row under `trace.py --strict` until it moves.
        report.append(
            "{}: still carries a `contract` cell — move its definition into the "
            "owner's `Contract IF-###:` body and delete the cell; `trace.py "
            "--strict` names the row until then".format(rid)
        )
    if "channel" in raw and not any(k in raw for k in IF_RETIRED):
        return blk
    lines = blk.splitlines(keepends=True)
    new_owner = _fold_owner(raw, rid, llr_modules, report)
    if raw.get("req_refs"):
        report.append(
            "{}: req_refs {} dropped — the requirement is reached through the "
            "owner, never stated on the row".format(rid, list(raw["req_refs"]))
        )
    channel = _seed_channel(new_owner or (raw.get("owner") or "").strip())
    report.append(
        "{}: channel seeded {!r} from the owner's kind — confirm it, and move "
        "`consumers` to `requestors` where the far side puts information INTO "
        "the owner".format(rid, channel)
    )
    return "".join(_rewrite_if_lines(lines, _if_block_cells(lines), new_owner, channel))


def convert_if_shape(root, write):
    """Rewrite an old-shape `interfaces.toml` in place. Returns
    `(report_lines, written_paths)`; the report is informational (every
    judgement the converter did NOT make), never a refusal — an unparsable
    registry is the one hard failure, raised."""
    path = root / IF_REL
    if not path.is_file():
        return [], []
    text = path.read_text(encoding="utf-8")
    llr_modules = _llr_single_modules(root)
    blocks = re.split(r"(?m)^(?=\[interface\.)", text)
    report, out, changed = [], [], 0
    for blk in blocks:
        m = re.match(r"\[interface\.(IF-\d+)\]", blk)
        if not m or m.group(1).endswith("-000"):
            out.append(blk)
            continue
        new = _convert_if_block(blk, m.group(1), llr_modules, report)
        changed += new != blk
        out.append(new)
    new_text = "".join(out)
    tomllib.loads(new_text)  # the rewrite must still parse, or nothing is written
    written = []
    if changed and write:
        path.write_bytes(new_text.encode("utf-8").replace(b"\r\n", b"\n"))
        written.append(path)
    report.insert(
        0,
        "{}: {} row(s) rewritten to the owner / far side / channel shape".format(
            IF_REL, changed
        ),
    )
    return report, written


def main(argv=None):
    ap = argparse.ArgumentParser(description="CSV/markdown registries -> TOML (OI-12)")
    ap.add_argument("--root", default=".")
    ap.add_argument(
        "--check",
        action="store_true",
        help="convert in memory and verify the round-trip; write nothing",
    )
    ap.add_argument(
        "--if-shape",
        action="store_true",
        help="rewrite an old-shape interfaces.toml in place (OI-67): owner / "
        "requestors|consumers / channel / data; --check reports without writing",
    )
    args = ap.parse_args(argv)
    root = Path(args.root).resolve()
    if args.if_shape:
        report, written = convert_if_shape(root, write=not args.check)
        for line in report:
            print("migrate_carrier: " + line)
        print(
            "migrate_carrier: {}".format(
                "wrote " + written[0].as_posix() if written else "nothing written"
            )
        )
        return 0
    findings, _ = convert(root, write=not args.check)
    for f in findings:
        print("migrate_carrier: LOSSY - {}".format(f), file=sys.stderr)
    if findings:
        print(
            "migrate_carrier: REFUSED - {} cell(s) did not survive the "
            "round-trip".format(len(findings)),
            file=sys.stderr,
        )
        return 1
    print("migrate_carrier: round-trip clean.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
