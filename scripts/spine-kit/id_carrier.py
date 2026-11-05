#!/usr/bin/env python3
"""The id carrier: the one allocation authority parallel lanes reserve spine ids from.

WHY IT EXISTS (SR-174). A lane drafts registry rows at its own base, so two
lanes cut from different trunk commits each read "the next number" off their
own copy of `docs/id-watermark` and draw the same one. The carrier is one ref
shared by every worktree of a repository, `refs/heads/id-carrier`, whose every
commit's tree is the single file `docs/id-watermark`. A reservation reads its
tip, raises the marks of the spaces it asks for, appends one record per space,
and moves the ref by compare-and-swap, so two reservations taken one after
another, from any bases, receive disjoint ranges, and a reservation that lost
the race writes nothing.

THE SPACES. Every watermark space is a carrier space except the three minted
on the trunk (`TRUNK_SPACES`: WI, OI and DP keep their trunk writers). The
split is computed from the caller's one space list, so a space added there
later joins the carrier by default.

THE RECORD. `# reservation: <SPACE> <low>-<high> (<WI-NNN>)`, a comment line
of the watermark, matched whole on the stripped line, with `1 <= low <= high`
and SPACE a carrier space. A line that does not match is not a record and
justifies nothing. Only a reservation writes one, on the carrier; only the
fold copies one, into a working file.

THE FOLD. Over any number of watermark texts: each space's maximum mark, the
union of reservation records (sorted by space, then low) and the union of the
correction records. The fold lag asks whether folding a carrier text into a
file would change the file's marks or records, so it cannot drift from the
fold.

WHAT THIS MODULE DOES NOT OWN. The watermark's rendering, its live-id sweep,
its basis line and its integrity rules stay in `trace.py`, which composes this
module the way it composes `retire.py` and hands it a render callable; this
module imports nothing from `trace.py`. The retirement records the landing
judgement reads are `retire.py`'s, handed in by `trace.py` as a reader. The
plumbing writes no worktree and no checkout, and its lock is git's own ref lock.
"""

import re
import tempfile
from pathlib import Path

try:
    from kitlib import git as _kitgit
    from kitlib import provenance as _provenance
except ImportError:  # pragma: no cover - in-process fallback
    import sys

    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from kitlib import git as _kitgit
    from kitlib import provenance as _provenance

CARRIER_REF = "refs/heads/id-carrier"
WATERMARK = "docs/id-watermark"
TRUNK_SPACES = ("DP", "OI", "WI")
MAX_COUNT = 50
LOST_RACE = "another reservation moved the carrier; re-run"
RESERVE_VERB = "trace.py --reserve-ids"
# Where every carrier-space id lives: a landing's ids are swept at a git tree
# by writing these two directories out.
LANDING_DIRS = ("docs/requirements", "docs/test")

# `<SPACE> = <int>`, matched against the stripped line: the one mark-line
# grammar. `parse_marks` reads it leniently; `trace.read_watermark` and the
# committed readers read it strictly, refusing a line it does not match.
MARK_LINE = re.compile(r"^([A-Z]+)\s*=\s*(\d+)\s*$")
# `# correction: <SPACE> <old> -> <new> (<ruling id>)`, matched against the
# STRIPPED line, `#` included: the ruled one-shot raise `--correct-mark` writes.
CORRECTION_LINE = re.compile(
    r"^#\s*correction:\s+([A-Z]+)\s+(\d+)\s*->\s*(\d+)\s*\((.+)\)\s*$"
)
_RESERVATION_LINE = re.compile(r"^# reservation: ([A-Z]+) (\d+)-(\d+) \((WI-\d+)\)$")


class Refused(ValueError):
    """A reservation or fold the carrier refuses before any write; its `str`
    is the one line the verb prints.

    Implements: SR-174, LLR-362
    """


def carrier_spaces(all_spaces):
    """Every space of `all_spaces` except the trunk-minted three, in order.

    Implements: SR-174, LLR-362
    """
    return tuple(s for s in all_spaces if s not in TRUNK_SPACES)


def parse_marks(text):
    """`{space: int}` of the `<SPACE> = <int>` lines of a watermark text;
    comment and blank lines are skipped, as is any other line (the strict
    reader, which refuses one, is `trace.read_watermark`).

    Implements: SR-174, LLR-362
    """
    marks = {}
    for line in (text or "").splitlines():
        m = MARK_LINE.match(line.strip())
        if m:
            marks[m.group(1)] = int(m.group(2))
    return marks


def parse_corrections(text):
    """`{space: [(old, new, ruling_id), ...]}` for one watermark text, in file
    order. APPENDS, never overwrites: a dict keyed by space would let a second
    correction line for a space ERASE the first from the parsed record, so a
    chained forgery would destroy the audit trail inside the reader every rule
    consults. A list per space keeps both, which is what lets
    `trace._correction_record_findings` report the second as the one-shot
    breach it is.

    Implements: SR-174, LLR-362
    """
    out = {}
    for line in (text or "").splitlines():
        m = CORRECTION_LINE.match(line.strip())
        if m:
            space, was, now, ruling = m.groups()
            out.setdefault(space, []).append((int(was), int(now), ruling.strip()))
    return out


def parse_reservations(text):
    """`[(space, low, high, wi), ...]`, in file order, of the well-formed
    reservation records of a watermark text. A line that does not match whole,
    names a trunk space, starts at 0 or runs low above high is not a record.

    Implements: SR-174, LLR-362
    """
    out = []
    for line in (text or "").splitlines():
        m = _RESERVATION_LINE.match(line.strip())
        if not m or m.group(1) in TRUNK_SPACES:
            continue
        low, high = int(m.group(2)), int(m.group(3))
        if 1 <= low <= high:
            out.append((m.group(1), low, high, m.group(4)))
    return out


def record_line(record):
    """The canonical line of one `(space, low, high, wi)` record.

    Implements: SR-174, LLR-362
    """
    return "# reservation: {} {}-{} ({})".format(*record)


def _count(pair, spaces, seen):
    """One `SPACE=N` pair as `(space, n)`, or `Refused` naming it.

    Implements: SR-174, LLR-362
    """
    space, eq, value = pair.partition("=")
    space = space.strip()
    if not eq:
        raise Refused("counts: {!r} is not a SPACE=N pair".format(pair))
    if space in TRUNK_SPACES:
        raise Refused(
            "counts: {} ids are minted on trunk, never reserved".format(space)
        )
    if space not in carrier_spaces(spaces):
        raise Refused("counts: {} is not a carrier space".format(space))
    if space in seen:
        raise Refused("counts: {} is named more than once".format(space))
    if not re.fullmatch(r"[0-9]+", value.strip()) or not 1 <= int(value) <= MAX_COUNT:
        raise Refused(
            "counts: {}={} is not an integer from 1 to {}".format(
                space, value.strip(), MAX_COUNT
            )
        )
    return space, int(value)


def parse_counts(text, spaces):
    """`{space: n}` from `SPACE=N[,SPACE=N...]`: each SPACE a carrier space of
    `spaces` named once, each N an integer from 1 to 50; anything else is
    `Refused` with one line.

    Implements: SR-174, LLR-362
    """
    if not (text or "").strip():
        raise Refused("counts: no SPACE=N pair given")
    counts = {}
    for pair in text.split(","):
        space, n = _count(pair, spaces, counts)
        counts[space] = n
    return counts


def fold(sides):
    """`(marks, reservations, corrections)` over watermark texts: each space's
    maximum mark; the union of reservation records, de-duplicated and sorted by
    space then low; the union of correction records per space, in order of
    first appearance. A `None` side is skipped.

    Implements: SR-174, LLR-362
    """
    marks, reservations, corrections = {}, set(), {}
    for text in sides:
        if text is None:
            continue
        for space, value in parse_marks(text).items():
            marks[space] = max(marks.get(space, 0), value)
        reservations.update(parse_reservations(text))
        for space, records in parse_corrections(text).items():
            kept = corrections.setdefault(space, [])
            kept += [r for r in records if r not in kept]
    ordered = sorted(reservations, key=lambda r: (r[0], r[1], r[2], r[3]))
    return marks, ordered, corrections


def carried(carrier_text):
    """What the carrier contributes to a working watermark's fold: its
    reservation records, and each recorded space marked at the highest number
    those records reserve in it; None when there is no carrier.

    The carrier's own mark lines are the allocation floor, not content to copy:
    they hold trunk's committed marks as of each reservation, so a trunk-minted
    space's mark, or a mark trunk raised with no record, would reach a lane
    cut before it as a raise nothing in the lane's history justifies. Every
    number carried here is one a record in the same file justifies, and at a
    landing or a refresh trunk is a parent, so its marks are already the
    receiving side's.

    Implements: SR-174, LLR-362
    """
    if carrier_text is None:
        return None
    records = parse_reservations(carrier_text)
    highs = {}
    for space, _low, high, _wi in records:
        highs[space] = max(highs.get(space, 0), high)
    lines = [record_line(r) for r in records]
    lines += ["{} = {}".format(space, high) for space, high in sorted(highs.items())]
    return "".join(line + "\n" for line in lines)


def fold_lag(carrier_text, file_text):
    """The lines naming how `file_text` lags the carrier's contribution
    (`carried`): each space whose carried mark stands above the file's, and
    each carrier record the file lacks. Empty when folding the carrier into
    the file would change neither its marks nor its records, and when there is
    no carrier (`None`).

    Implements: SR-174, LLR-362
    """
    if carrier_text is None:
        return []
    marks, records, _corrections = fold([carried(carrier_text), file_text])
    held_marks, held = parse_marks(file_text), set(parse_reservations(file_text))
    out = [
        "the carrier marks {} at {}, the watermark at {}".format(
            space, marks[space], held_marks.get(space, 0)
        )
        for space in sorted(marks)
        if marks[space] > held_marks.get(space, 0)
    ]
    out += [
        "the carrier holds {} {}-{} ({}), the watermark does not".format(*r)
        for r in records
        if r not in held
    ]
    return out


def plan_reservation(carrier_marks, trunk_marks, counts, wi):
    """`[(space, low, high, wi), ...]` sorted by space: each range starts one
    above the larger of the carrier's mark and trunk's committed mark for its
    space, so a ruled correction on trunk raises the floor.

    Implements: SR-174, LLR-362
    """
    out = []
    for space in sorted(counts):
        low = max(carrier_marks.get(space, 0), trunk_marks.get(space, 0)) + 1
        out.append((space, low, low + counts[space] - 1, wi))
    return out


def _ref_value(root):
    """Implements: SR-174, LLR-362"""
    out = _kitgit.git_out(root, ["rev-parse", "-q", "--verify", CARRIER_REF])
    return (out or "").strip() or None


def carrier_tip(root):
    """The carrier ref's commit id, or None when the repository has none.

    Implements: SR-174, LLR-362
    """
    return _ref_value(root)


def carrier_text(root, tip):
    """The watermark text the carrier commit `tip` holds, or None.

    Implements: SR-174, LLR-362
    """
    if not tip:
        return None
    return _kitgit.git_out(root, ["show", "{}:{}".format(tip, WATERMARK)])


def _plumb(root, args, stdin=None):
    """stdout of one plumbing call, `stdin` written as UTF-8 bytes with no
    newline translation, or `Refused` naming it.

    Implements: SR-174, LLR-362
    """
    data = None if stdin is None else stdin.encode("utf-8")
    out = _kitgit.git_bytes(root, args, stdin=data)
    if out is None:
        raise Refused("the carrier could not be written: git {} failed".format(args[0]))
    return out.decode("ascii", "replace").strip()


def write_carrier(root, text, old_tip, message):
    """Write one carrier commit holding `text` as the one file, parented on
    `old_tip` (none on first use), and move the ref only if it still stands at
    `old_tip` (absent on first use). Returns the new tip; a lost swap is
    `Refused` with `LOST_RACE`, the new objects left loose and inert.

    Implements: SR-174, LLR-362
    """
    folder, name = WATERMARK.rsplit("/", 1)
    blob = _plumb(root, ["hash-object", "-w", "--stdin"], stdin=text)
    sub = _plumb(root, ["mktree"], "100644 blob {}\t{}\n".format(blob, name))
    tree = _plumb(root, ["mktree"], "040000 tree {}\t{}\n".format(sub, folder))
    parent = ["-p", old_tip] if old_tip else []
    body = _provenance.with_loop_trailer(message)
    new = _plumb(root, ["commit-tree", tree, *parent, "-m", body])
    moved = _kitgit.git_out(
        root, ["update-ref", "-m", message, CARRIER_REF, new, old_tip or ""]
    )
    if moved is None:
        if _ref_value(root) != old_tip:
            raise Refused(LOST_RACE)
        raise Refused("the carrier ref {} could not be moved".format(CARRIER_REF))
    return new


def reserve(root, wi, counts_text, spaces, render, trunk_name):
    """Reserve `counts_text` ids for the work item `wi` (one id, already
    checked by the caller) on the carrier; returns the ranges. Every refusal
    is raised before any write. `trunk_name()` answers the declared trunk's
    name or raises `Refused`; it is asked only once the counts are admitted.
    The trunk's tip must hold `wi`'s spec in a claim folder
    (`kitlib.git.claimed_specs`). The carrier file is the fold of the carrier
    tip (or, on first use, nothing) and trunk's committed watermark, with the
    reserved spaces raised and the records appended, rendered by
    `render(marks, reservations, corrections)`.

    Implements: SR-174, LLR-362
    """
    counts = parse_counts(counts_text, spaces)
    trunk = trunk_name()
    claimed = _kitgit.claimed_specs(root, trunk) or []
    if not any(claimed_wi == wi for _lane, claimed_wi, _name in claimed):
        raise Refused(
            "work item: {} has no claimed spec under {}/ on {}".format(
                wi, _kitgit.ACTIVE_DIR, trunk
            )
        )
    trunk_text = _kitgit.git_out(root, ["show", "{}:{}".format(trunk, WATERMARK)])
    tip = carrier_tip(root)
    current = carrier_text(root, tip)
    ranges = plan_reservation(parse_marks(current), parse_marks(trunk_text), counts, wi)
    marks, records, corrections = fold([current, trunk_text])
    for space, _low, high, _wi in ranges:
        marks[space] = high
    records = sorted(set(records) | set(ranges))
    message = "id carrier: reserve {} for {}".format(
        ", ".join("{} {}-{}".format(s, lo, hi) for s, lo, hi, _w in ranges), wi
    )
    write_carrier(root, render(marks, records, corrections), tip, message)
    return ranges


def receiving_sides(root):
    """The receiving watermark's texts: index stages 2 and 3 while the path is
    conflicted, else the working file; [] when there is neither.

    Implements: SR-174, LLR-362
    """
    if (_kitgit.git_out(root, ["ls-files", "-u", "--", WATERMARK]) or "").strip():
        stages = (
            _kitgit.git_out(root, ["show", ":{}:{}".format(n, WATERMARK)])
            for n in (2, 3)
        )
        return [t for t in stages if t is not None]
    path = Path(root) / WATERMARK
    if not path.is_file():
        return []
    return [path.read_text(encoding="utf-8-sig", errors="replace")]


def record_history_findings(current, committed):
    """A finding per committed record `current` no longer holds unchanged:
    `committed` is the union over every baseline, so a merge dropping one
    side's record is caught. Empty when `committed` is None (no baseline).

    Implements: SR-174, LLR-362
    """
    held = set(current)
    return [
        "id watermark: the COMMITTED reservation record `{}` was altered or "
        "deleted — a record is append-only across every parent; restore it "
        "(`trace.py --fold-ids` folds every side's records back)".format(record_line(r))
        for r in committed or ()
        if r not in held
    ]


def _id_name(space, number):
    """Implements: SR-174, LLR-363"""
    return "{}-{:03d}".format(space, number)


def _retired_lines(added, retired):
    """Row 3's re-used retired number: each added id a retirement record names,
    inside a reservation or outside it, naming the record.

    Implements: SR-174, LLR-363
    """
    return [
        "{} is a retired number ({} records it) and is never issued again — "
        "author the row under a new reserved number".format(
            _id_name(s, n), retired[(s, n)]
        )
        for s, n in added
        if (s, n) in retired
    ]


def _outside_lines(added, carrier_records, wi_ids, carrier_present):
    """Rows 3 and 4: each added id no record naming the work item covers.

    Implements: SR-174, LLR-363
    """
    who = ", ".join(wi_ids)
    own = [r for r in carrier_records if r[3] in wi_ids] if carrier_present else []
    outside = [
        (s, n)
        for s, n in added
        if not any(r[0] == s and r[1] <= n <= r[2] for r in own)
    ]
    if not outside:
        return []
    why = "no id carrier exists" if not carrier_present else "no carrier record of its"
    return [
        "{} is added outside every reservation of {} ({}) — reserve it first with "
        "`{} {} {}=N`".format(_id_name(s, n), who, why, RESERVE_VERB, wi_ids[0], s)
        for s, n in outside
    ]


def landing_lines(
    added,
    carrier_records,
    wi_ids,
    landing_records,
    parent_records,
    carrier_present,
    claim_problem,
    retired=None,
    reissued=None,
):
    """The landing judgement's refusal lines; [] when the landing passes.

    `reissued` (`{(space, number): record path}`) holds the ids live in the
    landing that a retirement record the landing brings names, added or not:
    each refuses, naming its record, whatever else the landing adds.
    `added` holds `(space, number)` ids live in the landing and not in its
    parent; number 0 (the `-000` placeholder) is never judged. No other id
    added passes. Ids added with the work item unreadable from the claim
    refuse, naming `claim_problem`. Otherwise each added id `retired`
    (`{(space, number): record path}`) names refuses, naming its record,
    whatever reservation covers it; each other added id outside every carrier
    record naming one of `wi_ids` refuses (with no carrier, all of them);
    and a landing record that neither the carrier nor the parent holds
    refuses, naming its line.

    Implements: SR-174, LLR-363
    """
    reissued = {k: v for k, v in (reissued or {}).items() if k[1] > 0}
    out = _retired_lines(sorted(reissued), reissued)
    added = sorted((s, n) for s, n in added if n > 0 and (s, n) not in reissued)
    if not added:
        return out
    if not wi_ids:
        return out + [
            "ids added ({}) but the landing's work item cannot be read from its "
            "claim ({})".format(
                ", ".join(_id_name(s, n) for s, n in added), claim_problem
            )
        ]
    retired = retired or {}
    out += _retired_lines(added, retired)
    fresh = [a for a in added if a not in retired]
    out += _outside_lines(fresh, carrier_records, wi_ids, carrier_present)
    known = set(carrier_records) | set(parent_records)
    out += [
        "the landing's watermark carries `{}`, which neither the carrier nor "
        "the parent holds — only a reservation writes a record".format(record_line(r))
        for r in landing_records
        if r not in known
    ]
    return out


def _watermark_at(root, rev):
    """The watermark text the tree-ish `rev` holds, or "" when it holds none.

    Implements: SR-174, LLR-363
    """
    return _kitgit.git_out(root, ["show", "{}:{}".format(rev, WATERMARK)]) or ""


def ids_at(root, rev, sweep):
    """`sweep(directory)` over the `LANDING_DIRS` the tree-ish `rev` holds,
    written out to a temporary directory byte for byte as committed
    (`kitlib.git.write_blobs`, so no attribute hides or rewrites a registry):
    the caller's live-id sweep, read at a git tree. Raises
    `kitlib.git.ArchiveError` when git cannot write them.

    Implements: SR-174, LLR-363
    """
    with tempfile.TemporaryDirectory() as scratch:
        _kitgit.write_blobs(root, rev, LANDING_DIRS, scratch)
        return sweep(scratch)


def _added_ids(root, landing_rev, parent_rev, sweep, spaces):
    """The `spaces` ids `sweep` finds at `landing_rev` and not at
    `parent_rev`; none when git reports no change under `LANDING_DIRS`.

    Implements: SR-174, LLR-363
    """
    changed = _kitgit.git_out(
        root, ["diff", "--name-only", parent_rev, landing_rev, "--", *LANDING_DIRS]
    )
    if changed is not None and not changed.strip():
        return set()
    added = ids_at(root, landing_rev, sweep) - ids_at(root, parent_rev, sweep)
    return {(s, n) for s, n in added if s in spaces}


def _reissued_ids(root, pair, sweep, spaces, records):
    """`{(space, number): record path}`: the `spaces` ids `sweep` finds live
    at the pair's landing tree that a retirement record names which that
    tree holds and its parent does not (`records`: `{rev: {id: path}}`). A
    record both trees hold judges nothing here; the landing tree is swept
    only when the landing brings a record.

    Implements: SR-174, LLR-363
    """
    landing_rev, parent_rev = pair
    brought = {
        k: v
        for k, v in records[landing_rev].items()
        if k not in records[parent_rev] and k[0] in spaces
    }
    if not brought:
        return {}
    live = ids_at(root, landing_rev, sweep)
    return {k: v for k, v in brought.items() if k in live}


def _read_landing(root, revs, lane_tip, sweep, spaces, retired):
    """`(added, spent, reissued)`: the `spaces` ids `sweep` finds added over
    `revs` (`(landing, parent)`) and, with `lane_tip`, over the lane's own
    delta (its tip over its merge base with the parent), united; the
    retirement records `retired(root, rev)` reads at every tree those pairs
    name, united; and, over each pair, the ids `_reissued_ids` finds, united.
    Raises `kitlib.git.ArchiveError` when the merge base cannot be read.

    Implements: SR-174, LLR-363
    """
    pairs = [revs]
    if lane_tip:
        base = (_kitgit.git_out(root, ["merge-base", revs[1], lane_tip]) or "").strip()
        if not base:
            raise _kitgit.ArchiveError(
                "the merge base of {} and the lane's tip {} cannot be read".format(
                    revs[1][:10], lane_tip[:10]
                )
            )
        pairs.append((lane_tip, base))
    records = {rev: retired(root, rev) for pair in pairs for rev in pair}
    added, spent, reissued = set(), {}, {}
    for pair in pairs:
        added |= _added_ids(root, *pair, sweep, spaces)
        reissued.update(_reissued_ids(root, pair, sweep, spaces, records))
    for found in records.values():
        spent.update(found)
    return added, spent, reissued


def landing_refusal(root, revs, wi_ids, claim_source, sweep, spaces, retired, lane_tip):
    """The landing judgement over git, or None when the landing passes:
    `landing_lines` over the `spaces` ids `sweep` finds live in the landing
    tree and not in its parent (`revs`, the tree-ishes `(landing, parent)`)
    and, when the landing tree is not the lane's tip, those `lane_tip` holds
    and its merge base with the parent does not (the lane's own delta, the
    reading the merge slot's `revs` already are); the ids live in the landing
    side of either pair that a retirement record that side holds and its
    parent does not names (`_reissued_ids`), whether added or not; the
    retirement records `retired(root, rev)` reads (`{(space, number): path}`)
    at every tree judged; the carrier tip's records; and the records each of `revs`'
    watermarks carries; joined into one refusal. `claim_source` names where
    `wi_ids` were read. A tree or merge base that cannot be read refuses,
    naming why.

    Implements: SR-174, LLR-363
    """
    landing_rev, parent_rev = revs
    try:
        added, spent, reissued = _read_landing(
            root, revs, lane_tip, sweep, set(spaces), retired
        )
    except (_kitgit.ArchiveError, SystemExit) as exc:
        # A registry the sweep refuses to read (it exits naming the file)
        # refuses the landing by the same name: fail closed, never crash.
        return "the landing's registry ids cannot be read: {}".format(exc)
    tip = carrier_tip(root)
    lines = landing_lines(
        added,
        parse_reservations(carrier_text(root, tip)),
        list(wi_ids),
        parse_reservations(_watermark_at(root, landing_rev)),
        parse_reservations(_watermark_at(root, parent_rev)),
        tip is not None,
        claim_source,
        spent,
        reissued,
    )
    if not lines:
        return None
    return "the landing's registry ids are not all reserved on the id carrier: " + (
        "; ".join(lines)
    )


def rev_fold_lag(root, rev):
    """`fold_lag` of the watermark the tree-ish `rev` holds (a commit, or the
    index's tree) behind the carrier tip; [] with no carrier.

    Implements: SR-174, LLR-363
    """
    return fold_lag(carrier_text(root, carrier_tip(root)), _watermark_at(root, rev))
