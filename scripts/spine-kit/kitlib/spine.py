"""The SPINE ROW vocabulary — what one registry row's cells MEAN, stated once.

THE PAIR THAT HAD TWO HOMES (WI-448 slice 3; census 2026-08-12, `repo-lock.md`
§8.2). `trace.py` ENFORCES the spine and `spine_rules.py` DERIVES its stage from
the same rows, so every question either one asks of a single cell was asked
twice: what `Drafted`/`Approved`/`Founded` mean, which `Verification` methods
decompose to a TC but no LLR, what integer a free-form `Phase` cell parses to,
which `SN-###` tokens a needs registry mentions, and which of them the SRs cite.
Nine duplicated function bodies, held equal by nine `tests/test_rule_sync.py`
pins, because the retired F5 rule licensed the duplication and D-7 could only
CONTAIN the drift rather than remove it.

Those questions are POLICY, not plumbing, and a policy disagreement between
those two modules is a false green or a false red AT A GATE — the exact failure
class the kit exists to prevent (repo-review-2026-07-12b M1 -> WI-099). Owner
ruling D-8 (`OI-16`) replaced F5: the rule lives here, once, and both modules
import it under their existing local names, so no call site moved.

WHY ITS OWN MODULE, AND NOT `registry.py` (the choice, recorded). `registry.py`
is the `docs/work/` SPEC-FOLDER reader — a different registry, a different
carrier, a different consumer set. Folding two unrelated registries into one
file is how a themed package acquires the generic bucket the 2026-08-19 review
(H-09) explicitly forbade this package, and it would have grown the package's
largest module instead of the smallest sensible new one. This module is the
`ladder.py` shape one tier over: a CLOSED VOCABULARY as near-pure data, below
every axis that reads it.

WI-448 SLICE 4 ADDED THE CELL-SHAPE RULES THE PAIR'S NEIGHBOURS ALSO ASKED.
`refs` (the multi-ref cell split) had six homes and `is_example` a third one
outside the pair; `norm_module` — what an IF `Endpoint`, an LLR `Module` cell
and an arch-map node name all reduce to — had two. They are the same KIND of
statement as the rules above (what one cell MEANS), asked by `gen_okf.py`,
`plan_coverage.py`, `plan_artifacts.py`, `schedule.py`, `check_trajectory.py`,
`gen_arch_map.py` and `gen_release_checklist.py` rather than only by the pair.

WI-448 SLICE 5 ADDED THE ROW-WHOLE STATEMENTS THE SCAFFOLDER ALSO HAD TO MAKE.
The per-tier SCHEMA OF RECORD (`REGISTRY_KEYS`) moved down from
`spine_carrier.py`, which now binds it, and the TOML value/line emitter moved
down from `wi_convert.py`, which does the same. Both are the module's one
sentence stated for the ROW rather than for a cell — which keys a row declares,
and how its cells are spelled in the carrier — and both had a reader the carrier
could not serve: `bootstrap.py` may import this package and no other sibling, so
while they lived up there the scaffolder RESTATED them and a `test_rule_sync`
pin held the restatement equal. It now reads them.

WHAT IS DELIBERATELY NOT HERE:

  * `sn_draft_ids` — the tenth duplicate of the pair, and the one that CANNOT
    move. Both copies were a one-line delegation to
    `spine_carrier.draft_ids_from_text`, and this package's one asserted rule is
    that it imports no sibling of `scripts/` (a `kitlib` module reaching for
    `spine_carrier` would smuggle the whole graph into the scaffolder). So the
    duplicate is retired the other way: both modules now BIND the sibling
    function directly, under the same local name, and the copy disappears
    without a home here.
  * `is_drifted`, the maturity tables, and the rung fall-through — each has
    exactly one home already, and `tests/test_rule_sync.py` pins that they keep
    it.

Stdlib only, and import-clean of the rest of `scripts/`, like every module here.
"""

import csv
import io
import re

from . import config as _kitconfig

__all__ = [
    "LLR_EXEMPT",
    "MODULE_EXTS",
    "load_csv",
    "csv_body",
    "csv_reader",
    "csv_rows",
    "norm_module",
    "refs",
    "clip_line",
    "open_items_at",
    "registry_row_hint",
    "is_example",
    "is_drafted",
    "is_approved",
    "is_founded",
    "STATUS_VALUES",
    "llr_exempt",
    "phase_num",
    "sn_all_ids",
    "sn_cited_ids",
    "evidence_items",
    "resolve_modules",
    "module_tests",
    "tier_findings",
    "missing_cell_findings",
    "SPINE_TIER_KEYS",
    "OFFSPINE_KEYS",
    "HISTORICAL_KEYS",
    "REGISTRY_KEYS",
    "split_pred_edges",
    "open_item_queue",
    "SYSTEM_VALUES",
    "FORM_VALUES",
    "SAMPLING_VALUES",
    "MAX_AGE_FLOOR_DAYS",
    "toml_string",
    "toml_value",
    "toml_fields",
]

# SR Verification methods with no code to decompose, so they need a TC but no
# LLR: the orphan rule exempts them and the LLReqs rung does not hold open for
# them. Critique is NOT here — its artifact is produced by code, only its
# acceptance is subjective.
#
# A FROZENSET, WHICH SETTLES A REAL DISAGREEMENT BETWEEN THE TWO COPIES: this
# was a `set` in `spine_rules.py` and a `tuple` in `trace.py`. Both answer `in`
# identically, so the value pin (`set(TRACE.LLR_EXEMPT) == set(GATE.LLR_EXEMPT)`)
# was structurally blind to it — the same shape as the comment-only drift the
# spec-folder extraction found. Immutable is the right answer for a closed
# vocabulary a shared kernel hands out: a caller that mutated the `set` copy
# would have moved the gate for every other reader in the process.
LLR_EXEMPT = frozenset({"Analysis", "Inspection", "Attest"})


def csv_body(text):
    """The CSV text with its leading `#`-comment PREAMBLE removed — the header
    ROW is the first line that is neither a comment nor blank.

    A registry CSV may open with the same `#` declaration header a TOML or INI
    registry carries (the `Contracts:` marker and `Contract IF-###:` bodies of
    the interface shape): `performance-budgets.csv` is such an owner.
    `csv.DictReader` knows nothing of comments and would take the first `#`
    line as the header row, which makes every real column — `PB-ID` first —
    unaddressable in every reader at once. Only LEADING comment lines are
    dropped: a `#` opening a data line, or one inside a quoted multi-line
    cell, is data and stays. A BOM is stripped first, for the reason
    `spine_carrier.rows_from_text` states: a BOM'd header glues to the first
    column name and every row hides.

    A BLANK LINE BELONGS TO THAT PREAMBLE, and dropping it is the same rule
    rather than a second one: a hand-written header block ends with a blank
    line before the columns, and leaving it in hands `csv.DictReader` the BLANK
    line as its header row — every real column unaddressable again, the exact
    failure this function exists to prevent, one line further down. Only the
    LEADING run is dropped: a blank line AFTER the header row is `csv`'s own
    business and is untouched. An all-comment, all-blank or empty file still
    yields no rows."""
    lines = text.lstrip("\ufeff").splitlines(keepends=True)
    i = 0
    while i < len(lines) and (
        not lines[i].strip() or lines[i].lstrip().startswith("#")
    ):
        i += 1
    return "".join(lines[i:])


def csv_reader(text):
    """`csv.DictReader` over `csv_body(text)` — the ONE way a kit reader turns
    registry CSV text into rows, so a header-carrying registry reads
    identically everywhere; callers that need `fieldnames` take this one."""
    return csv.DictReader(io.StringIO(csv_body(text)))


def csv_rows(text):
    """`csv_reader(text)` as a list."""
    return list(csv_reader(text))


def load_csv(path):
    """A registry CSV as a list of dict rows, or `[]` when the file is absent.

    `utf-8-sig` because a spreadsheet round-trip leaves a BOM on the first
    header cell, which would otherwise make the id column unaddressable, and
    `errors="replace"` so one mis-encoded cell degrades to a visible replacement
    character rather than crashing a check. Read through `csv_rows`, so a
    leading `#` declaration header is a header and never the header row.

    Contract:
      Inputs:  path: `pathlib.Path` to a registry CSV (may not exist)
      Outputs: list[dict] — the data rows; `[]` if the file does not exist
    """
    if not path.exists():
        return []
    return csv_rows(path.read_text(encoding="utf-8-sig", errors="replace"))


def refs(value):
    """Split a multi-ref cell (';', ',' or whitespace separated) into ids.

    SIX HOMES BEFORE WI-448 SLICE 4, and one of them had drifted: this exact
    body stood in `check_trajectory._split_refs`, `gen_okf.split_refs`,
    `plan_coverage.split_refs`, `plan_artifacts._split_tokens`,
    `schedule._split_refs` and here. `plan_coverage`'s copy had split on `[;,]`
    alone (B10, part-A census 2026-08-13), so a whitespace-separated pair in an
    LLM-authored plan cell read as ONE garbage token and matched nothing — the
    same splitting defect class as the SN-001/SN-002 orphan bug OI-12 records.
    A pin repaired that copy; this module retires the copies instead."""
    return [t for t in re.split(r"[;,\s]+", (value or "").strip()) if t]


def registry_row_hint(ids, frag):
    """Why `frag` names no row of a carrier exposing `ids`: the table-path
    spelling (`need.SN-1`) gets its bare id back; anything else is unknown."""
    bare = frag.rpartition(".")[2]
    if bare in ids:
        return "did you mean #" + bare + "?"
    return "no row carries that id — cite the bare row id"


#: A hard, gating open-item edge token — an `OI-###` id in a `Predecessors`
#: cell. Nothing mints OI edges in `needs` now; TC-253 requires the legacy
#: reader, so an existing open-item edge still gates readiness without any bare
#: WI id changing meaning.
_OI_TOKEN_RE = re.compile(r"^OI-\d+$")


def split_pred_edges(value):
    """Split a `Predecessors` cell into `(hard_wi, hard_oi, soft_wi)`.

    The `needs` token grammar. An `OI-###` token is THE edge between a work
    item and the open item it waits on (WI-790, reversing WI-746's `wi_refs`
    pointer): a work item cites the decision, and an open item carries no
    pointer back. Bare WI ids keep meaning exactly what they meant:

      `WI-###`   a HARD (blocking) edge — satisfied only when that WI integrates
                 `done`, the acyclicity rule's node set.
      `~WI-###`  a SOFT (advisory-ordering) edge — must resolve, never blocks.
      `OI-###`   a HARD edge on an OPEN-ITEM ruling — satisfied when that open
                 item leaves `pending` (`schedule.hard_preds_satisfied`); while
                 it is pending the row reads `blocked`, the item named. An OI
                 edge is hard
                 BY RULING, so a `~` prefix on one is ignored rather than making
                 a soft OI edge — there is no such thing. OI ids are NOT graph
                 nodes (an open item never integrates), so they stay out of the
                 WI hard-edge cycle set and the downstream-count walk.

    Returned as three lists so every reader — the scheduler's readiness gate,
    the validator's predecessor resolution, the dashboard — reads the same
    partition of one cell rather than re-deriving the grammar."""
    hard_wi, hard_oi, soft = [], [], []
    for tok in refs(value):
        bare = tok.lstrip("~")
        if _OI_TOKEN_RE.match(bare):
            hard_oi.append(bare)
        elif tok.startswith("~"):
            soft.append(bare)
        else:
            hard_wi.append(bare)
    return hard_wi, hard_oi, soft


def open_item_queue(work_rows, oi_rows):
    """THE ONE QUEUE PROJECTION of the owner's pending decisions (WI-790): which
    pending open items a QUEUED work item cites in its `needs`, and which no
    queued row cites.

    Returns `{"cards": [(oi_row, [citing ids])], "uncited": [OI ids],
    "held": {WI id: [OI ids]}}`, every list in id order. `cards` is what the
    owner surface renders and counts, `held` is the status snapshot's Blocked
    list, and `uncited` is the integrity finding and the owner surface's notice:
    a pending decision nothing on the queue cites is invisible to the queue.
    One function feeds all of them, so the page, the snapshot and the checker
    cannot disagree about what the owner owes.

    `work_rows` are registry rows (`WI-ID`, `Status`, `Predecessors`) and
    `oi_rows` open-item rows (`OI-ID`, `Status`); `-000` example rows on either
    side are inert. A row that is not `queued` (drafted, deferred, claimed or
    closed) surfaces nothing: the decision reaches the owner through the queue.

    Implements: SR-148, LLR-299
    """
    pending = dict(open_items_at(oi_rows, "pending"))
    held = _held_rows(work_rows, pending)
    citers = {}
    for wid in sorted(held, key=_id_number):
        for oid in held[wid]:
            citers.setdefault(oid, []).append(wid)
    order = sorted(pending, key=_id_number)
    return {
        "cards": [(pending[o], citers[o]) for o in order if o in citers],
        "uncited": [o for o in order if o not in citers],
        "held": held,
    }


def open_items_at(oi_rows, status):
    """`[(OI id, row)]` for every real (non-example) open item whose status is
    `status` (lower case), in row order, a duplicated id once per row.

    THE SHARED STAGE of every open-items reader that filters by status (WI-821,
    the A->B->C / A->B->D shape PROCESS.md §3 names): the owner queue reads the
    `pending` items here, `check_trajectory.approval_brief_findings` the
    `pending` briefs and `trace.ruled_open_item_texts` the `ruled` prose. Each
    had carried its own skip-and-filter loop. A row whose id is not `OI-###`
    shaped, or is the `-000` example, is never returned.

    A SEQUENCE, not a map: the carrier keeps two rows sharing an id, and the
    brief lint reads each of them, as its own loop did. A reader that wants a
    by-id map builds it with `dict(...)`, so the last row wins there exactly as
    it did in the owner queue's and the ruled-prose reader's own loops.

    Implements: SR-148, LLR-299
    """
    out = []
    for row in oi_rows:
        oid = (row.get("OI-ID") or "").strip()
        state = (row.get("Status") or "").strip().lower()
        if oid.startswith("OI-") and not is_example(oid) and state == status:
            out.append((oid, row))
    return out


def _held_rows(work_rows, pending):
    """`{WI id: [pending OI ids its needs cite]}` for every real queued row
    citing at least one item in `pending`.

    Implements: SR-148, LLR-299
    """
    held = {}
    for row in work_rows:
        wid = (row.get("WI-ID") or "").strip()
        if is_example(wid) or (row.get("Status") or "").strip() != "queued":
            continue
        cited = {
            o for o in split_pred_edges(row.get("Predecessors"))[1] if o in pending
        }
        if cited:
            held[wid] = sorted(cited, key=_id_number)
    return held


def _id_number(rid):
    """`OI-98` -> 98: the numeric order ids are read in, never the lexical one."""
    tail = rid.rsplit("-", 1)[-1]
    return int(tail) if tail.isdigit() else 0


# Source-file extensions stripped when normalizing a module path, so an IF
# endpoint written with the full repo path
# (`project-trajectory/scripts/check.py`), an LLR `Module` cell and an arch-map
# node name (`scripts/check`) all collapse to one key.
MODULE_EXTS = (".py", ".sh", ".ps1", ".ts", ".js", ".go", ".rs", ".cmd")


def norm_module(path):
    """A module path reduced to a naming-convention-neutral key: strip a leading
    `project-trajectory/`, any source extension, and a trailing `/__init__`.

    A CELL RULE, which is why it is here rather than in a module-identity home
    of its own. Every call site normalizes a registry cell or a path it is about
    to compare against one — an IF row's `Endpoint`/`ThisProject`/`Counterpart`,
    an LLR row's `Module`, or the source file those cells are claiming. THREE
    modules asked it — `check_trajectory.py`, which enforces those rows,
    `gen_arch_map.py`, which draws them, and `trace_text.py`, whose endpoint
    predicate WI-464 had already pulled out of `trace.py` — and
    `check_trajectory`'s copy carried a comment promising it was "kept in sync
    with `trace.py._MODULE_EXTS`", a home that DOES NOT EXIST, so the promise
    named nobody while its real partners went unmentioned. That is the
    declared-line pattern again: a prose claim of equivalence with no referent.

    The `MODULE_EXTS` spelling above is `trace_text.py`'s, not the two private
    `_MODULE_EXTS` ones, and that is deliberate: the census hashes a body's AST
    including the NAME it loads, so the third copy scored as a different
    function for as long as it spelled the constant differently.

    Contract:
      Inputs:  path: str | None — a module path in any of the three spellings
      Outputs: str — the normalized key ('' for an empty/None input)
    """
    p = (path or "").strip().replace("\\", "/")
    if p.startswith("project-trajectory/"):
        p = p[len("project-trajectory/") :]
    for ext in MODULE_EXTS:
        if p.endswith(ext):
            p = p[: -len(ext)]
            break
    if p.endswith("/__init__"):
        p = p[: -len("/__init__")]
    return p


def seam_endpoints(cell):
    """The endpoints of one IF endpoint cell, split on `;` ONLY.

    An endpoint may legitimately contain a space (`external:downstream
    adopter`) or a comma, so `;` is the only separator — and a `Consumers` cell
    is a LIST in the carrier, joined on `;` by `spine_carrier.value_to_cell`,
    so the same split reads it back. It is the carrier's ONE list-cell split:
    `frame_rules` reads a need's pointer cells (`stakeholder_refs`, `source`)
    through it too, under its local name `_entries` (WI-821)."""
    return [e.strip() for e in (cell or "").split(";") if e.strip()]


# The closed `channel` vocabulary (OI-67 ruled (a)): what crosses the seam,
# typed. `exit-code` and `env` are the finite-alphabet kinds; the rest are
# unbounded. A dial read from a config file is `file` (the medium is the
# file; `data` names the key); a source tree walked by AST is `file`.
IF_CHANNELS = frozenset(
    {"cli", "exit-code", "stdout", "file", "call", "env", "git", "bytes"}
)


def seam_owner(row):
    """An IF row's OWNER-side endpoint — the providing thing, read off the cell
    (OI-67 ruled (a), 2026-08-29).

    ONE SPELLING, the same one `consumers` uses: a module path, a file or
    directory path, or an `external:` party. Nothing is derived — the
    `owner` -> LLR -> `Module` join that `seam_provider` ran until this ruling
    retired with the id-typed owner it read, because a design row's module IS
    the providing thing and a derivable cell was a second spelling of it.

    Contract:
      Inputs:  row: dict — one IF row under today's column names
      Outputs: str — the owner endpoint, or '' when the cell is absent (the
               required-field rule's finding, never this reader's)
    """
    return (row.get("Owner") or "").strip()


def seam_requestors(row):
    """The sides that put information INTO the surface the owner defines —
    they call the function, invoke the CLI, set the env var, write the file."""
    return seam_endpoints(row.get("Requestors"))


def seam_consumers(row):
    """The sides that take what the owner emits — they read the file, the exit
    code, the stdout."""
    return seam_endpoints(row.get("Consumers"))


def seam_far_side(row):
    """`(inbound, endpoints)` — the row's far side and which way the
    information runs. THE KEY NAME IS THE DIRECTION: a row names `requestors`
    (information flows far side -> owner) or `consumers` (owner -> far side),
    exactly one, so one row is one direction by construction rather than by
    discipline. A row naming both or neither is `trace.py`'s finding; this
    reader answers the requestors first so a malformed row still draws one
    way rather than none."""
    requestors = seam_requestors(row)
    if requestors:
        return True, requestors
    return False, seam_consumers(row)


def clip_line(text, width):
    """`text` as ONE line of at most `width` characters: whitespace collapsed,
    and an over-long line cut to `width - 1` characters plus `…`.

    THE SHARED STAGE of the kit's one-line clips (WI-821): `hats._clip`,
    `intake._clip` and `check_trajectory._clip_title` each carried this body.
    It takes text; what a missing cell reads as (`""` or `"None"`) stays each
    caller's own choice, because the copies differed there and a brief's
    `'None' -> 'x'` line is how an absent cell shows.

    Implements: SR-157, LLR-197
    """
    text = " ".join(text.split())
    return text if len(text) <= width else text[: width - 1] + "…"


def is_example(rid):
    """The `-000` placeholder-row convention: a template row, nobody's finding."""
    return (rid or "").endswith("-000")


# THE SPINE'S CLOSED STATUS VOCABULARY — the three words the predicates below
# read, and the one ladder every tier's `Status` is held to (D-9's Drafted ->
# Approved -> Founded; its history is recorded where `trace.py` binds it). Its
# home is here rather than in the checker so a pure sibling of the checker can
# hold a tier to it without importing the checker: `frame_rules` holds the
# stakeholder list to it.
STATUS_VALUES = frozenset({"Drafted", "Approved", "Founded"})


def is_drafted(row):
    """A row in the pre-approval `Drafted` state.

    Exempt from the child-completeness orphan rules (a Drafted SR needs no
    LLR/TC) and from the `--require-verified` criterion, so a requirement can
    live in the live spine while it is being drafted — and it HOLDS ITS RUNG
    OPEN on the derivation side, which is the same fact seen from the other end.

    `Status` is a CLOSED vocabulary since D-9 step 1 and reached the ruled ladder
    at steps 7/8: `{Drafted, Approved, Founded}`. Matched case-insensitively on
    the stripped cell — the one Status-casing rule (process.md §4) — which all
    three predicates here share.

    Contract:
      Inputs:  row: a registry row mapping (a missing `Status` reads as absent)
      Outputs: bool
    """
    return (row.get("Status") or "").strip().lower() == "drafted"


def is_approved(row):
    """The `Approved` state: the row's TEXT is blessed by a human.

    RENAMED FROM `is_verified` AT D-9 STEP 5, and the rename carries a RULING.
    `Verified` made TWO claims at once — the text is approved AND the evidence
    passed — and the second was a hand-set cell asserting a test run nobody
    re-ran. `Approved` says only that the text is blessed; whether the tests
    pass is the harness's answer (`kitlib.evidence`). `Planned` folded into this
    same value at the same act (OI-30 D1).

    Contract:
      Inputs:  row: a registry row mapping
      Outputs: bool
    """
    return (row.get("Status") or "").strip().lower() == "approved"


def is_founded(row):
    """The ladder's TOP rung: settled AND the artifacts the row calls for EXIST.

    Armed for the spine at D-9 step 8 the way it armed for CMP at the registry
    status unification — the word becomes legal, no live cell moves to it. It
    reads ABOVE `Approved`, so arming it can never LOWER a derived reading. The
    DISCHARGE is computed per tier elsewhere; this reads the cell, like its two
    siblings.

    Contract:
      Inputs:  row: a registry row mapping
      Outputs: bool
    """
    return (row.get("Status") or "").strip().lower() == "founded"


def claims_approval(row):
    """True when a row's `Status` claims approval or above: `Approved`, or the
    computed `Founded` above it. A missing `Status`, or a word outside the
    vocabulary, claims nothing. The one home of the pair the approval-act
    readers and the parent-first rule both ask.

    Implements: SR-245, LLR-357

    Contract:
      Inputs:  row: a registry row mapping
      Outputs: bool
    """
    return is_approved(row) or is_founded(row)


def llr_exempt(row):
    """SR `Verification` method in `LLR_EXEMPT`, matched on the STRIPPED cell.

    The stripping is load-bearing and was once a live divergence: review 017
    caught the two former copies disagreeing on a whitespace-padded valid method
    (one stripped, one did not), which is a false green on one surface and a
    false red on the other for one registry state.

    Contract:
      Inputs:  row: an SR row mapping
      Outputs: bool
    """
    return (row.get("Verification") or "").strip() in LLR_EXEMPT


def phase_num(row):
    """The integer a row's free-form `Phase` cell digit-parses to (`v2`->2).

    None when the cell is blank or holds no digits. The ONE phase-parse the kit
    uses, so a downstream repo that kept `vN` labels parses identically wherever
    the phase doctrine (process.md §4) is applied.

    Contract:
      Inputs:  row: a registry row mapping
      Outputs: int | None
    """
    m = re.search(r"\d+", (row.get("Phase") or ""))
    return int(m.group()) if m else None


def sn_all_ids(text, carrier=None):
    """The SN id UNIVERSE: every `SN-###` token in a needs registry's NEED TABLES.

    A TOKEN scrape, so a prose mention inside a need counts exactly like a table
    row — the sharp edge `registry-machinery-reference` §2.1 records (an
    approved, uncited prose mention caps the derived stage through the coverage
    rung). `-000` placeholders excluded. This scrape decides which ids BOTH the
    gate derivation and the itemized orphan listing run their rules over, which
    is why it may have only one definition.

    THE NEED TABLES ONLY, under the TOML carrier. The needs file also carries
    the stakeholder list (`[stakeholder.STK-##]`), whose descriptions may name
    the needs a stakeholder owns; scraping the whole file would turn each such
    mention into a need of its own, which then reads as approved and uncited
    and caps the stage. So the scrape reads the `[need.*]` tables' ids and
    cells and nothing else, and an id named only in a comment is not a need.
    The legacy markdown carrier, which has no stakeholder list, keeps the
    whole-text scrape it was written under.

    THE CARRIER COMES FROM THE FILE, NOT FROM THE TEXT. `carrier` is the
    resolved registry's suffix (`.toml` or `.md`), which every caller that read
    a file knows. Sniffing cannot decide it: an empty or comment-only TOML file
    parses to nothing, exactly like a markdown file of headings, and read as
    markdown its comments would join the universe. A text-only caller (None)
    still gets the sniff, where only a non-empty TOML document reads as TOML. A
    `.toml` text that does not parse keeps the whole-text scrape, which can only
    count more ids, never hide one; the carrier's own loader refuses the file.

    Contract:
      Inputs:  text: the needs registry's raw text, under EITHER carrier;
               carrier: its file suffix, or None when only the text is known
      Outputs: set[str]

    Implements: SR-189, LLR-215
    """
    tables = _kitconfig.read_toml_text(text)
    is_toml = carrier == ".toml" if carrier else bool(tables)
    if is_toml and tables is not None:
        text = "\n".join(
            "{} {}".format(rid, " ".join(str(v) for v in cells.values()))
            for rid, cells in (tables.get("need") or {}).items()
        )
    return {u for u in re.findall(r"\bSN-\d+\b", text) if not is_example(u)}


def sn_cited_ids(srs):
    """Every SN id cited by >=1 SR row's `SN-Refs` cell — the coverage set.

    No filtering here, deliberately: `-000` rows are excluded by the CALLER's
    row filter, and a Drafted SR's citation is IN the set (the raw view; the
    ex-draft counterfactual re-runs this on the non-draft subset rather than
    special-casing it here).

    Contract:
      Inputs:  srs: iterable of SR row mappings
      Outputs: set[str]
    """
    # THE `Implements: SR-049, LLR-147` TAG CAME WITH THIS BODY AND WAS REMOVED
    # ON ARRIVAL. LLR-147's CodeSymbol is `spine_stage/sn_cited_ids` on
    # `spine_rules.py`, and `spine_stage` — the rung fall-through that reads this
    # set — did NOT move; carrying the tag here would claim a row about the
    # coverage rung for the primitive it consumes, and `check_trajectory`'s
    # symbol check says so. No sibling module in this package carries a tag:
    # `LLR-197` claims the whole module, which is the right grain for a
    # vocabulary whose eleven names are one decision. The evidence join below
    # is the one exception: two separate decisions with design rows of their
    # own, the tier rule (`LLR-260`) and the module listing (`LLR-263`), so
    # each of its functions carries its row's tag.
    return {x for r in srs for x in refs(r.get("SN-Refs"))}


# ---------------------------------------------------------------------------
# THE EVIDENCE JOIN — what a test case's `Evidence` cell names, and what joins
# through it.
#
# The cell is the spine's one pointer into the test tree, and two readers need
# the same reading of it: `trace.py --tests-for`, which prints the tests the
# spine links to a module (the module's design rows, the cases verifying them,
# their evidence) for a builder's inner loop, and a project's binding of
# `tier_findings` to its own harness. The cell's grammar is a statement of the
# kind this module makes, beside `refs` and `norm_module`; the two joins over it
# read rows only, so the package stays import-clean of `scripts/`.

# One Evidence item, or a parenthetical note ("(to be extended at
# implementation)"), which is never a path. `;` and whitespace separate items
# only outside a node's bracketed parametrization, so `test_x[param one]` stays
# one node.
_EVIDENCE_TOKEN = re.compile(r"\([^)]*\)|(?:[^\s;\[(]|\[[^\]]*\])+")


def evidence_items(cell):
    """An `Evidence` cell as `[(path, node)]`, in cell order.

    The live cells separate items by `;` or whitespace, name a whole file or one
    node (`path::test`, a parametrized id included, spaces inside its brackets
    kept), and may cite a document section (`doc.md#anchor`, read as the
    document). `node` is `""` for a whole file.

    Implements: SR-157, LLR-260

    Contract:
      Inputs:  cell: str | None — one TC row's `Evidence` cell
      Outputs: list[tuple[str, str]] — `(path, node)`, paths `/`-separated
    """
    items = []
    for token in _EVIDENCE_TOKEN.findall(cell or ""):
        if token.startswith("("):
            continue
        path, _sep, node = token.partition("::")
        path = path.split("#", 1)[0].replace("\\", "/")
        if path:
            items.append((path, node))
    return items


def resolve_modules(llrs, wanted):
    """The sorted distinct `Module` paths the design rows declare that `wanted`
    names: the path or a trailing part of it, with or without its extension,
    compared through `norm_module` so a stem names it too.

    Implements: SR-221, LLR-263

    Contract:
      Inputs:  llrs: iterable of LLR row mappings; wanted: str
      Outputs: list[str] — every declared module `wanted` matches, sorted
    """
    key = norm_module(wanted).strip("/")
    declared = {m for r in llrs for m in refs(r.get("Module"))}
    return sorted(
        m
        for m in declared
        if key and (norm_module(m) == key or norm_module(m).endswith("/" + key))
    )


def module_tests(llrs, tcs, module, test_root="tests"):
    """The sorted test files the spine links to the declared module path
    `module`: the design rows whose `Module` names it, the test cases whose
    `Verifies` names one of them, and the paths under `test_root` in those
    cases' `Evidence`. Every status is read, a drafted case included: a builder
    iterating runs the case being written.

    Implements: SR-221, LLR-263

    Contract:
      Inputs:  llrs, tcs: iterables of LLR and TC row mappings; module: a path
               exactly as a `Module` cell spells it; test_root: the declared
               test root
      Outputs: list[str] — test file paths, sorted and distinct
    """
    design = {r.get("LLR-ID") for r in llrs if module in refs(r.get("Module"))}
    prefix = test_root.strip().replace("\\", "/").strip("/") + "/"
    return sorted(
        {
            path
            for r in tcs
            if design.intersection(refs(r.get("Verifies")))
            for path, _node in evidence_items(r.get("Evidence"))
            if path.startswith(prefix)
        }
    )


def tier_findings(tcs, tier_of):
    """`(errors, advisories)` for the approved test cases whose `Tier` cell
    disagrees with the tier their evidence runs in.

    WHICH TIER A TEST RUNS IN IS THE HARNESS'S ANSWER, so the rule takes it as
    `tier_of(path)` -> `"smoke"`, `"slow"`, or None for a path that is no test
    the harness runs, and gates wherever a project binds it: a harness that
    tiers whole modules binds that table, one that marks single tests binds its
    marks, and a binding run inside the per-commit tier gates every commit. A
    `Smoke` case none of whose evidence runs in the smoke tier is an
    error: its cell claims a per-commit run that does not happen. A `Full` case
    none of whose evidence is slow is an advisory: either it runs per commit
    after all, or it names no test the harness runs (a document, a workflow),
    and the full tier runs everything, so the cell understates where its
    evidence runs and is never false. A row below approval is not judged; its
    tier is a proposal.

    Implements: SR-157, LLR-260

    Contract:
      Inputs:  tcs: iterable of TC row mappings; tier_of: callable(path) ->
               "smoke" | "slow" | None
      Outputs: (list[str], list[str]) — error and advisory lines, each naming
               the case and its evidence paths
    """
    errors, advisories = [], []
    for r in tcs:
        if not is_approved(r):
            continue
        tier = (r.get("Tier") or "").strip()
        paths = sorted({p for p, _node in evidence_items(r.get("Evidence"))})
        tiers = {tier_of(p) for p in paths}
        if tier == "Smoke" and "smoke" not in tiers:
            errors.append(
                "{}: tier Smoke, but none of its evidence runs in the smoke tier "
                "({})".format(r.get("TC-ID"), ", ".join(paths) or "no evidence")
            )
        elif tier == "Full" and "slow" not in tiers:
            advisories.append(
                "{}: tier Full, but none of its evidence is slow ({})".format(
                    r.get("TC-ID"), ", ".join(paths) or "no evidence"
                )
            )
    return errors, advisories


# The spine tiers a `Phase` cell is owed on once the spine is phased. The need
# tier declares no phase: a need is delivered through the requirements citing it.
# Implements: SR-157, LLR-272
PHASED_TIERS = ("SR", "LLR", "TC")


def missing_cell_findings(tiers):
    """One integrity line per spine row missing a cell every reader keys on:
    its `Status`, on every tier, and its `Phase`, on the phased tiers once any
    of their rows is phased.

    AN ABSENT CELL WAS THE ONE SHAPE THE VOCABULARY CHECKS COULD NOT SEE. They
    judge a value that is present, so a row authored with no `status` passed
    every one of them while reading, to each surface that asks what it owes, as
    neither `Drafted` nor approved: no first-approval arm and no drift arm
    fires on it, and the approval brief omitted it. A row with no `phase` in a
    phased spine falls outside every `--phase` scope the same silent way. Both
    are wrong at any stage, so both are integrity-class. The phase half arms as
    the numeric-phase rule does, on the first phased row, so an unphased
    project is not asked for a cell it does not use.

    Implements: SR-157, LLR-272

    Contract:
      Inputs:  tiers: {label: rows} over "SN", "SR", "LLR", "TC", each row a
               registry row mapping keyed `<label>-ID`; `-000` rows and rows
               with no id are skipped
      Outputs: list[str] — one line per row and missing cell, naming both
    """
    rows = [
        (label, str(r.get(label + "-ID") or "").strip(), r)
        for label, tier in tiers.items()
        for r in tier
    ]
    rows = [(label, rid, r) for label, rid, r in rows if rid and not is_example(rid)]
    phased = any(
        phase_num(r) is not None for label, _rid, r in rows if label in PHASED_TIERS
    )
    out = []
    for label, rid, r in rows:
        if not (r.get("Status") or "").strip():
            out.append(
                "{} {} has no Status cell — a row stating no maturity is neither "
                "Drafted nor approved to every reader that asks what it owes; "
                'give it status = "Drafted"'.format(label, rid)
            )
        if phased and label in PHASED_TIERS and not (r.get("Phase") or "").strip():
            out.append(
                "{} {} has no Phase cell — the spine is phased, and a row with no "
                "phase falls outside every phase scope; give it the phase it is "
                "delivered in".format(label, rid)
            )
    return out


# THE PARENT-FIRST RULE: a spine row is approved only after the rows
# it hangs from are. Each child tier, the cell naming its parents, and the
# tiers a parent is read from: an SR's needs, an LLR's SRs, and a TC's SRs and
# LLRs. Any other id a cell cites (an IF, B or DA row, or an id no row
# declares) is not a parent here: unresolved parentage is the orphan rules'.
PARENT_EDGES = {
    "SR": ("SN-Refs", ("SN",)),
    "LLR": ("SR-Refs", ("SR",)),
    "TC": ("Verifies", ("SR", "LLR")),
}


def _status_cell(row):
    """A row's stripped `Status` cell, "" when it has none.

    Implements: SR-245, LLR-357"""
    return (row.get("Status") or "").strip()


def _declared_rows(tiers):
    """`{label: {id: row}}` over `tiers`, `-000` example rows and rows with no
    id left out, the first row of a duplicated id kept.

    Implements: SR-245, LLR-357"""
    out = {}
    for label, rows in tiers.items():
        byid = out.setdefault(label, {})
        for row in rows:
            rid = str(row.get(label + "-ID") or "").strip()
            if rid and not is_example(rid):
                byid.setdefault(rid, row)
    return out


def _unapproved_parents(declared, row, column, parent_tiers):
    """The `(id, row)` of each declared parent `row` cites in `column` that
    does not claim approval, in citation order, once each.

    Implements: SR-245, LLR-357"""
    for ref in dict.fromkeys(refs(row.get(column))):
        for label in parent_tiers:
            parent = declared.get(label, {}).get(ref)
            if parent is not None and not claims_approval(parent):
                yield ref, parent


def parent_first_findings(tiers):
    """One entry `(child, child status, parent, parent status)` per approved
    child (`claims_approval`: `Approved` or `Founded`) citing a declared parent
    that is not approved, over `PARENT_EDGES`. A parent with no `Status`, or a
    word outside the vocabulary, is not approved. Statuses are the stripped
    cells, "" for a missing one. Pure: the standing finding and the commit
    judgement both read it.

    Implements: SR-245, LLR-357

    Contract:
      Inputs:  tiers: {label: rows} over "SN", "SR", "LLR", "TC", each row
               keyed `<label>-ID`, `Status` and its tier's parent column; a
               missing tier reads as no rows
      Outputs: list[tuple[str, str, str, str]], child tiers in SR, LLR, TC
               order and rows in registry order
    """
    declared = _declared_rows(tiers)
    out = []
    for label, (column, parent_tiers) in PARENT_EDGES.items():
        for rid, row in declared.get(label, {}).items():
            if not claims_approval(row):
                continue
            out += [
                (rid, _status_cell(row), ref, _status_cell(parent))
                for ref, parent in _unapproved_parents(
                    declared, row, column, parent_tiers
                )
            ]
    return out


def parent_first_line(entry):
    """The one message for a parent-first entry, carrying its own remedy: the
    standing finding and the commit judgement each prefix it.

    Implements: SR-245, LLR-357
    """
    child, child_status, parent, parent_status = entry
    return (
        "{} ({}) is approved under {} ({}), which is not: approve {} in its own "
        "approval act, or return {} to Drafted".format(
            child, child_status, parent, parent_status or "no status", parent, child
        )
    )


# ---------------------------------------------------------------------------
# THE SCHEMA OF RECORD — which keys each registry tier declares.
#
# MOVED HERE FROM `spine_carrier.py` at WI-448 slice 5, unchanged. It is the
# same KIND of statement as everything above — what one registry row's cells
# MEAN — stated for the row as a whole instead of for one cell, and its readers
# are the whole kit rather than the carrier: `tests/test_dogfood_sync.py` checks
# every template and live registry against it, and the SCAFFOLDER writes a row
# under it (`bootstrap.append_stack_checklist` files the non-Python profile's
# `OI-3` brief). That last reader is why the move was owed rather than merely
# tidy: `bootstrap.py` may import this package and no other sibling, so while
# the schema lived in the carrier the scaffolder could only RESTATE the keys and
# have a test hold the restatement equal. Now it reads them.

# THE PER-TIER SCHEMA: which keys each tier declares, keyed by its id column.
# STATED, never derived — and the reason is the one the ordered CSV header used
# to provide for free.
#
# Under CSV the live file declared its own schema in a header, so a template
# that quietly dropped a column diverged from something. TOML has no header and
# an absent key IS an empty cell, so a column no row happens to use does not
# exist in the file at all — and a rule that compares only the template against
# the live registry cannot see the template DROP such a key. `permutations` is
# exactly that today: declared by the template, used by no live SR. Deriving
# this map from either side would re-create the hole, because the side that
# dropped the key would also drop it from the derivation.
#
# So it is a third leg, and it is the DURABLE one: the schema of record that
# both the template and the live registry are checked against
# (tests/test_dogfood_sync.py). Adding a column to a tier is a reviewed edit
# here first — which is the same discipline `spine_carrier.SPINE_COLUMN` (the
# key -> column-name map, which stays with the carrier that reads columns)
# already carries, for the same reason.
# Implements: SR-189, SR-193, SR-197, SR-198, LLR-215, LLR-222, LLR-232
SPINE_TIER_KEYS = {
    # THE NEED TIER, post-unification. `status` is the ONE maturity field (the
    # `kind`/`attestation`/`amended` trio it replaced is deleted, not renamed).
    # `tags` is OPTIONAL — ten of twenty-seven live rows carry none, and an
    # `always` hat reaches a need without one — but it is DECLARED, which is
    # the whole point: the template shipped without it precisely because no
    # schema named the tier.
    # `stakeholder_refs` (SR-189) names the declared stakeholders whose outcome
    # the need is, resolved against the same file's `[stakeholder.STK-##]`
    # list; `source` (SR-190) points at the document the need was drawn from,
    # as `path#anchor` targets. Both are optional POINTERS: the relation lives
    # on the need, and neither is part of the need's approved text.
    "SN-ID": (
        "status",
        "tags",
        "stakeholder_refs",
        "source",
        "need",
        "why",
        "priority",
        "acceptance",
    ),
    # `hat_refs` is OPTIONAL on both row tiers that declare it, and the absence
    # semantics are stated here because they are the whole difference between a
    # useful cell and a lie: an ABSENT `hat_refs` means NOT RECORDED, never "no
    # perspective reached this row". Nothing may read a blank as a negative claim,
    # which is why the checker's coverage arm is a warn-only count and never a
    # finding (WI-484 / OI-32 phase 1).
    "SR-ID": (
        "title",
        "sn_refs",
        "boundary_refs",
        "hat_refs",
        "requirement",
        "rationale",
        "acceptance_criteria",
        "permutations",
        "priority",
        "verification",
        "status",
        "phase",
        "aspect",
        # The requirement's assumption citations (SR-193): `da_refs` names the
        # assumptions its argument relies on, a POINTER into the assumptions
        # registry; `delivered_with` names the sibling requirements that join
        # it in delivering its needs; `coincident` records why its own
        # specification alone delivers its needs, and `form` (SR-194) says how
        # it is met, one of FORM_VALUES below. The latter three are statements
        # the row makes.
        "da_refs",
        "delivered_with",
        "coincident",
        "form",
    ),
    "LLR-ID": (
        "sr_refs",
        "hat_refs",
        "title",
        "module",
        "code_symbol",
        "detail",
        "rationale",
        "test_refs",
        "status",
        "component",
        "phase",
    ),
    "TC-ID": (
        "verifies",
        "level",
        "method",
        "tier",
        "parameters",
        "expected",
        "automated",
        "evidence",
        "status",
        "phase",
        # The assumptions the case can falsify (SR-197), a POINTER into the
        # assumptions registry beside `verifies`, which keeps naming only the
        # requirements and design rows it verifies.
        "assumption_refs",
        # An OBSERVATION case's declaration (SR-198), one recorded as not
        # automated: the repository paths or row ids its judgment reads, how
        # many days its result holds, and, citing an assumption, whether it
        # is `sampled` or `monitored`. A sampled one may declare its sampling
        # model as two flat cells, since the carrier refuses a nested table. All
        # five are statements the row makes.
        "inputs",
        "max_age",
        "rubric",
        "trigger",
        "min_work_items",
        "sampling",
        "sample_size",
        "acceptance_rule",
    ),
}

# The same third leg for the batch-2 registries — the SAME rule, not a second
# one (repo-lock §8.1: "reuse that shape rather than invent a second one").
# `tests/test_dogfood_sync.py` checks template, live registry and this schema
# against each other for every entry of REGISTRY_KEYS, so adding a column to
# `open-items` or `agents` is a reviewed edit HERE first, exactly as it is for a
# spine tier.
# Implements: SR-189, SR-191, SR-192, LLR-215, LLR-218
OFFSPINE_KEYS = {
    "OI-ID": (
        "title",
        "status",
        "raised",
        "one_line",
        "decision",
        "blast_radius",
        "options",
        "recommendation",
        "wi_refs",
        "ruled_date",
        "ruling_ref",
    ),
    "Id": (
        "family",
        "model",
        "version",
        "tier",
        "cmd_template",
        "env",
        "notes",
    ),
    # WI-443 / OI-14 part B. `signal` and `rationale` are NEW (nothing in the
    # registry typed a signal at all before this pass, and the why had nowhere
    # in the row to go, so it squatted in `contract`); `status` is GONE.
    # WI-442: `stability` is GONE and `approval` is the one maturity field; the
    # two `interface_*_external` keys are the DIRECTIONAL tie-back an IF row
    # carries ONLY when it realizes a boundary crossing (owner naming, 13m). An
    # IF row that realizes nothing carries neither — which is how the registry
    # says "internal seam" without a column claiming it.
    # WI-455 executed the held removal (OI-60 ruled (a), 2026-08-23):
    # `direction` is GONE (flow is provider→consumers, read off the two cells
    # below), `this_project`/`counterpart` are GONE, and the seam's two sides
    # are `provider` (OPTIONAL — omitted wherever `owner`→LLR→`module` derives
    # it uniquely) and `consumers` (a LIST, required).
    # THE ROW IS ONE OWNER, ITS CONSUMERS AND A TYPED STATEMENT (OI-67 ruled
    # (a), 2026-08-29): `owner` is the providing THING — a module path, a file
    # or directory path, or an `external:` party, the same spelling `consumers`
    # uses — never a requirement id; `channel` is the closed vocabulary of what
    # crosses; `data` the optional short alphabet. `provider`, `req_refs`,
    # `signal` and `signal_note` LEFT the row at that ruling, and `contract`
    # left with them once every definition had moved into its owner's
    # `Contract IF-###:` body: a row still carrying any of the five is
    # `trace.py`'s strict finding.
    "IF-ID": (
        "owner",
        "requestors",
        "consumers",
        "channel",
        "data",
        "rationale",
        # OPTIONAL, and its EMPTINESS is the ordinary answer: "this seam is
        # verified in its own right". Filled, it names the parent whose tests
        # cover a low-level seam — a `TC-###` or an `LLR-###` — which is the
        # position the `Verification` vocabulary cannot state (OI-61's
        # sub-question, sanctioned 2026-08-23). Warn-first that it resolves.
        "verified_by",
        "carried_by",
        "version",
        "status",
        "interface_from_external",
        "interface_to_external",
        # A boundary interface's bridging (SR-211): `bridged_by` names the
        # assumptions carrying its reading to an outcome, a POINTER into the
        # assumptions registry; `coincident` records why its reading IS the
        # outcome, a statement the row makes (the requirement tier's key, one
        # column repo-wide). Read only on a row with a tie-back above.
        "bridged_by",
        "coincident",
        "component",
        "notes",
    ),
    "CMP-ID": (
        "name",
        "category",
        "knowledge",
        "status",
        "standing",
        "superseded_by",
        "part_of",
        "notes",
    ),
    # WI-442 — the depth-0 frame's three tiers, all on `external.toml`. Each
    # gets its own schema entry for the same reason every other tier does: the
    # three-leg drift rule (tests/test_dogfood_sync.py) compares template, live
    # registry and THIS map per id column, so a column added to crossings
    # cannot leak into entities.
    # `mediates` (SR-195): the ONE entity this party acts for, carrying its
    # writes into the system and showing it the system's verdicts, as a
    # development session does for its operator. Optional; its one reader is
    # the assumption tier's reach check, and it grants no authority.
    "EXT-ID": (
        "name",
        "class",
        "description",
        "status",
        "absorbs",
        "notes",
        "mediates",
    ),
    # `system` (WI-627, SR-187): which system of interest the crossing belongs
    # to, from the closed pair SYSTEM_VALUES below. Optional on the row; a
    # crossing without it is an advisory (`frame_rules.frame_system_findings`).
    "B-ID": ("entity", "direction", "carries", "system", "status", "absorbs", "notes"),
    "REL-ID": ("from", "to", "kind", "flow", "status", "absorbs", "notes"),
    # THE STAKEHOLDER LIST (SR-189), a second tier on the NEEDS file: who owns
    # an outcome, and which declared frame entity they are (`party`, optional).
    # Keyed by its own id column, as the frame's three tiers share
    # `external.toml`, so its rows never mix with the needs' own.
    "STK-ID": ("name", "description", "party", "status"),
    # THE ASSUMPTIONS REGISTRY (SR-191, SR-192), two tiers on one path the way
    # the frame's three share `external.toml`. An assumption states where its
    # outcome lands (`effect_at`, crossing ids), what it assumes, when it holds,
    # the obstacle under which it fails and what would show it false; `status`
    # is the spine's maturity and `standing` its validity, active or falsified,
    # because an approved assumption can later be shown false. `realized_by`
    # names the one surrogate a fidelity assumption is about, `obstacle_hats`
    # the perspectives its obstacle came from. A surrogate is a stand-in for
    # outside parties in tests, and `emulates` names them (entity ids). Neither
    # tier records needs: an assumption's needs are derived from the
    # requirements citing it.
    "DA-ID": (
        "effect_at",
        "assumption",
        "holds_when",
        "obstacle",
        "falsifier",
        "accepted_risk",
        "realized_by",
        "obstacle_hats",
        "status",
        "standing",
    ),
    "SUR-ID": ("name", "emulates", "description", "status"),
}
REGISTRY_KEYS = dict(SPINE_TIER_KEYS, **OFFSPINE_KEYS)

# DECLARED HISTORICAL METADATA (WI-790): keys a registry still CARRIES on rows
# filed before a format change, which no new row authors. They stay in the
# schema above, so the carrier preserves them byte-for-byte, but no reader
# derives a relationship from them, and the shipped template's rows no longer
# set them. `wi_refs` is the open-item registry's work-item pointer: since
# WI-790 a work item's `needs` cites the open item it waits on, and an open
# item points at nothing. `tests/test_dogfood_sync.py` reads this to tell a
# historical key from a key a new row authors.
# Implements: SR-189, LLR-215
HISTORICAL_KEYS = {"OI-ID": ("wi_refs",)}

# THE TWO SYSTEMS OF INTEREST one frame holds (SR-187, LLR-211): the system in
# OPERATION, and the system that builds and DELIVERS it. A boundary crossing's
# `system` cell names one of them. Declared once, here, because the frame's
# schema tier is warn-only and judges no vocabulary for this cell: the one
# judge is `frame_rules.frame_system_findings`, which reads this tuple.
# Implements: SR-187, LLR-211
SYSTEM_VALUES = ("operation", "delivery")

# THE THREE FORMS A REQUIREMENT TAKES (SR-194): met at an interface, resting on
# an assumption, or a property of the whole system that no single seam meets.
# Declared here beside the tier schema that carries the `form` cell; the one
# judge is `assumption_rules.sr_form_findings`, which reads this tuple.
# Implements: SR-194, LLR-224
FORM_VALUES = ("interface", "assumption", "cross-cutting")

# HOW AN OBSERVATION TEST CASE CITING AN ASSUMPTION SAMPLES (SR-198): a
# `sampled` result was taken over a sample of the population the assumption
# speaks about, and a `monitored` one is read continuously in operation. Each
# says how the case looks, never how well the assumption holds: an assumption
# carries no evidence level (owner ruling 2026-10-02). And
# THE LIFETIME FLOOR, in whole days: a judgment the harness cannot rerun is
# trusted only for a declared time, and a lifetime under a week would demand it
# more often than it can honestly be taken. The one judge of both is
# `assumption_rules.observation_tc_findings`.
# Implements: SR-198, LLR-232
SAMPLING_VALUES = ("sampled", "monitored")
# Implements: SR-198, LLR-232
MAX_AGE_FLOOR_DAYS = 7


# ---------------------------------------------------------------------------
# HOW A ROW'S CELLS ARE SPELLED IN THE TOML CARRIER — the emitter, once.
#
# `tomllib` is read-only by design (PEP 680 omitted a writer), so the kit writes
# its own; before WI-448 slice 5 it wrote its own THREE TIMES. Two of those were
# the same rule with different blast radii — `wi_convert`, which writes a
# `docs/work/` spec's `+++` frontmatter (that registry's row), and
# `bootstrap._toml_scalar`, which writes `docs/process.toml` keys and the
# scaffolded `OI-3` brief row. `bootstrap`'s copy escaped the backslash and the
# quote and stopped there, so a cell carrying a TAB or any other control
# character would have emitted a basic string `tomllib` then REFUSES — a
# scaffold writing a file it cannot read back. The one home is the careful one;
# the careless copy is gone rather than pinned equal to it.
#
# THE THIRD HOME STAYS, and the difference is real rather than tolerated:
# `migrate_carrier.toml_scalar` promotes a long or newline-bearing cell to a
# MULTI-LINE basic string, which is what makes the spine's prose cells readable
# in the file at all. That is a different rule about the same syntax, with one
# home and one caller (the one-shot CSV -> TOML conversion), and folding it in
# here would put a line-length policy inside the emitter every writer shares.

# Escapes exactly what TOML basic strings require: the backslash, the closing
# quote, and every control character. The named shorthands are used where TOML
# defines them and the \\uXXXX form covers the rest, so nothing is left to the
# parser's discretion. Verified by re-parsing every emitted file with tomllib.
_TOML_ESCAPES = {
    "\\": "\\\\",
    '"': '\\"',
    "\b": "\\b",
    "\t": "\\t",
    "\n": "\\n",
    "\f": "\\f",
    "\r": "\\r",
}


def toml_string(value):
    """`value` as a TOML basic string, escaped so tomllib reads it back exactly.

    Contract:
      Inputs:  value: str
      Outputs: str — the quoted literal, escapes included
    """
    out = ['"']
    for ch in value:
        escaped = _TOML_ESCAPES.get(ch)
        if escaped is not None:
            out.append(escaped)
        elif ord(ch) < 0x20 or ord(ch) == 0x7F:
            out.append("\\u{:04x}".format(ord(ch)))
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def toml_value(value):
    """`value` as TOML: bool, int, an array of basic strings, or a basic string.

    Contract:
      Inputs:  value: bool | int | list | tuple | anything str-able
      Outputs: str — the TOML literal
    """
    if isinstance(value, bool):  # guard: bool is an int subclass in Python
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, (list, tuple)):
        return "[" + ", ".join(toml_string(v) for v in value) + "]"
    return toml_string(value)


def toml_fields(pairs):
    """One row's cells as `key = value` lines, in the order given.

    Contract:
      Inputs:  pairs: iterable of (key, value)
      Outputs: str — the block, every line newline-terminated
    """
    return "".join("{} = {}\n".format(k, toml_value(v)) for k, v in pairs)
