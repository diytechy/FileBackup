"""The TEST-EVIDENCE carrier: the `docs/test/evidence` record's format, the
declared source surface its claim is bound to, and the readers of both.

WHY THIS EXISTS (WI-500; the ruled plan `docs/plans/2026-08-21-stage-unification-
plan.md` §5's independently sequenced row). WI-498 slice 3 made `DevStg-Release`
EVIDENCE-GATED with, deliberately, no producer: leaving the Impl rung means
"every declared test case PASSES", and the kit had no machine reading of that, so
the top of the ladder was returned by nothing. This module is that reading. The
rule it carries across unchanged is OI-30 D2: **no Status cell — and no
hand-written file — may be the source of "the evidence passed".** The record here
is written by a driver that RAN the harness and saw its exit, or it is not
written.

WHAT MAKES A COMMITTED FILE BELIEVABLE, which is the whole design (the four
sources the program measured absent all failed on one of these):

  1. **It says what produced it.** `command` and `tier` are the harness
     invocation the driver actually ran, and `revision` is the tree's HEAD at the
     time — the declared-figure (`fig:`) discipline applied to a machine record:
     a measurement is evidence only at the revision it was driven on.
  2. **It is bound to the TREE it was measured on, BY VALUE.** `binding` is a
     digest over the content of everything the claim depends on — the spine
     registries (so a test case added afterwards invalidates it) and the declared
     product source and test trees (so a code edit does). This is the WI-492
     precedent: a claim binds to the value it was made about, never to a space or
     a timestamp, so it cannot survive the thing it describes changing.
  3. **Going stale makes the rung UNREACHABLE AGAIN, loudly.** The verdict below
     answers False on any mismatch, so no Release rung is derived from a stale
     record — and because the evidence file is a DECLARED STAGE INPUT and the
     stage fingerprint folds this source digest whenever the file is present, a
     source edit moves the stage fingerprint too: the committed `docs/stage`
     reads STALE and `derive_stage --check` (the commit-bar and CI freshness
     step) FAILS. Stale evidence is a hard finding in the consumer, never a
     warning and never silently ridden.

WHAT IT DOES NOT CLAIM. This is not a signature: a determined author can compute
a valid binding by hand and write the file. Forgery resistance would need a key
and a verifier, which is a different (and adopter-hostile) mechanism; what is
built here defeats the failure this kit actually has — a claim that was true once
and quietly outlived its tree — and the honest sentence is that one, not
"unforgeable".

THE SPLIT WITH `stage.py`, and why the composition lives THERE. This module is
pure file-and-path work. Its only sibling imports are `config` and
`observation`, and nothing either of them imports reaches `stage`. The BINDING
is a fold over the spine registries too, and the spine's declared input list is
`stage.py`'s — so `stage.evidence_binding` composes the two and
`stage.evidence_passed` is the verdict every consumer calls. The dependency runs
one way only (`stage` imports `evidence`), which is what keeps the package free
of a cycle.
"""

from pathlib import Path

from .config import STACK_INI, StackIniError, read_stack_ini
from .observation import OBSERVATIONS_DIR

# --- THE FILES ----------------------------------------------------------------
EVIDENCE_FILE = "docs/test/evidence"
STACK_FILE = STACK_INI

# THE TIERS A WHOLE-SUITE CLAIM MAY CARRY. `smoke` is deliberately absent: it is
# a declared SUBSET (docs/stack.ini `[tiers]`), so a green smoke run is not the
# sentence "every declared test case passed" and a record carrying it could only
# be a weaker claim wearing the same field. The producer refuses to write one and
# the verdict refuses to read one — two refusals for one rule, because the file
# is committed state and the reader must not have to trust the writer.
WHOLE_SUITE_TIERS = ("full", "release", "all")

# Paths inside the declared source surface that are BUILD RESIDUE, not source. A
# `__pycache__` entry changes on every interpreter run, so folding it would make
# every record stale the moment anything imported the tree.
_SKIP_DIRS = frozenset(
    {"__pycache__", ".pytest_cache", ".ruff_cache", ".mypy_cache", ".git", ".venv"}
)
_SKIP_SUFFIXES = frozenset({".pyc", ".pyo", ".pyd"})


def source_paths(root):
    """The declared product source + test paths from `docs/stack.ini` `[paths]`,
    as `[(declared, Path)]` in declared order; `[]` when nothing is declared.

    ONE HOME, NOT A SECOND LIST. `[paths] src` / `tests` is where the adopter
    already declares what their harness runs over; restating it here would let
    the evidence bind to a surface the bar does not measure, which is the exact
    shape of a claim that is true about the wrong thing.

    An absent or malformed `docs/stack.ini` answers `[]` rather than raising: the
    caller decides the fail-direction, and both do (the producer REFUSES to
    record without a declared surface; the verdict answers False)."""
    stack = Path(root) / STACK_FILE
    if not stack.is_file():
        return []
    try:
        cp = read_stack_ini(stack)
    except StackIniError:
        return []
    out = []
    for option in ("src", "tests"):
        if cp.has_section("paths") and cp.has_option("paths", option):
            value = cp.get("paths", option).strip()
            if value:
                out.append((value, Path(root) / value))
    return out


def source_files(root):
    """Every file of the declared source surface, as `[(relpath, Path)]` sorted by
    relpath — plus `docs/stack.ini` itself, because it DECLARES the bar (a change
    to the test command or the tier expressions changes what a green meant).

    Residue is skipped (`_SKIP_DIRS`/`_SKIP_SUFFIXES`); a declared path that is a
    single file is taken as itself; a declared path that does not exist
    contributes nothing, and its absence is visible in the fold through the
    OTHER files it no longer contributes.

    THE RECORD ITSELF IS EXCLUDED, which matters only for a repo that declares a
    wide surface (`src = .` is legal, and a single-package project may well write
    it). Including it would make the binding a function of a file that must
    CONTAIN that binding — no value could ever satisfy it, so the rung would be
    unreachable for exactly the adopters whose layout is simplest.

    AND SO ARE THE OBSERVATION RECORDS (SR-199), on the same wide surface: a
    sample of a test the harness cannot rerun says nothing about whether the
    suite passed on this tree, and binding the claim to them would make every
    recorded sample stale the release evidence."""
    base = Path(root)
    evidence_path = (base / EVIDENCE_FILE).resolve()
    observations = (base / OBSERVATIONS_DIR).resolve()
    found = {}
    stack = base / STACK_FILE
    if stack.is_file():
        found[STACK_FILE] = stack
    for _declared, path in source_paths(root):
        candidates = [path] if path.is_file() else sorted(path.rglob("*"))
        for item in candidates:
            if not item.is_file():
                continue
            if item.suffix in _SKIP_SUFFIXES:
                continue
            if any(part in _SKIP_DIRS for part in item.parts):
                continue
            resolved = item.resolve()
            if resolved == evidence_path or observations in resolved.parents:
                continue
            try:
                rel = item.relative_to(base).as_posix()
            except ValueError:  # pragma: no cover - declared path outside the root
                rel = item.as_posix()
            found[rel] = item
    return sorted(found.items())


def fold_sources(root, digest, fold):
    """Fold the declared source surface into `fold` (a hashlib object), using
    `digest(path) -> hex` for each file's content.

    THE DIGEST FUNCTION IS INJECTED so the caller's per-process memo covers these
    files too — the same reason `stage.read_stage` takes its deriver as an
    argument rather than importing one. Returns the number of files folded, which
    is what lets a caller report an EMPTY surface as the refusal it is rather than
    as a fold over nothing."""
    files = source_files(root)
    for rel, path in files:
        fold.update(rel.encode("utf-8"))
        fold.update(b"\0")
        fold.update(digest(path).encode("ascii"))
        fold.update(b"\n")
    return len(files)


# --- THE RECORD ---------------------------------------------------------------
# KEY=VALUE ADDRESSED BY NAME, the `docs/stage` idiom (and for its reason: the
# retired `docs/gate` put its machine value on "the first non-comment line", an
# idiom five readers re-implemented and none could validate).
FIELDS = ("outcome", "tier", "command", "revision", "binding")

# The one outcome this file is ever written with. A failing run writes NOTHING —
# there is no `outcome = fail` state, because a record of failure is not evidence
# and an absent record already says everything the consumer needs.
PASS = "pass"

HEADER = [
    "# TEST EVIDENCE — generated by scripts/record_test_evidence.py "
    "(do not hand-edit).",
    "#",
    "# The durable, committed record that the DECLARED test suite ran and every",
    "# case passed. It is written only by the driver, and only when the harness",
    "# it ran exited 0 — no Status cell and no hand-written file may be the",
    "# source of this claim (OI-30 D2).",
    "#",
    "#   outcome   always `pass`; a failing run writes nothing at all.",
    "#   tier      the declared tier that ran; never a partial one (smoke is",
    "#             refused by the writer AND by the reader).",
    "#   command   the harness invocation that produced this verdict.",
    "#   revision  the tree's HEAD when it was driven (informational — the",
    "#             binding below, not this, is what the verdict checks).",
    "#   binding   SHA-256 over the LF-normalized content of the spine",
    "#             registries and the declared product source + test trees.",
    "#             THE CLAIM IS BOUND TO THE TREE IT WAS MEASURED ON: move a",
    "#             byte either side and this record stops holding, the",
    "#             DevStg-Release rung becomes unreachable again, and",
    "#             `derive_stage --check` reds until the suite is re-run or the",
    "#             record is removed. Never edit it to make a red go away.",
    "#",
    "# Regenerate: python scripts/record_test_evidence.py",
    "#",
]


def _fmt(value):
    return "(none)" if value is None else str(value)


def render_fields(record, fields, fmt):
    """`k = v` lines for `fields`, in declared order, each value through `fmt`.

    THE FORMAT `docs/stage` AND `docs/test/evidence` SHARE, stated once (WI-448
    slice 4). Both files are a `#` header, a block of `key = value` lines, and an
    informational stamp that is never compared; both render the parsed cache
    through the same function that wrote it so a round-trip cannot be reported
    stale by a formatting difference. Their FIELDS differ and so does their
    value formatter — `stage` renders bools as `yes`/`no` and dicts as
    `k=v;k=v` — so those two are ARGUMENTS and the line-joining rule is the
    shared part. The two `field_block` bodies were byte-identical and read as
    one duplicate group in the census while binding different module-level
    names, which is a duplicate a reader cannot see by diffing the functions.

    A key that is ABSENT renders `(absent)`, which a present-but-empty field
    never produces: collapsing the two into `(none)` would make a cache missing
    a field compare EQUAL to a derivation that legitimately has none.

    Contract:
      Inputs:  record: mapping; fields: ordered field names; fmt: value -> str
      Outputs: str — the newline-joined block (no trailing newline)
    """
    return "\n".join(
        "{} = {}".format(k, fmt(record[k]) if k in record else "(absent)")
        for k in fields
    )


def field_block(record):
    """The compared field lines. One renderer for both sides of any comparison,
    the `stage.field_block` contract; an absent key renders `(absent)`, which a
    present-but-empty field never produces."""
    return render_fields(record, FIELDS, _fmt)


def render(record, date):
    """The full `docs/test/evidence` text. The trailing stamp is informational and
    never compared — same rule as the stage file's compute stamp."""
    return (
        "\n".join(HEADER + [field_block(record), "# recorded {}".format(date)]) + "\n"
    )


def parse(text):
    """The record a `docs/test/evidence` text carries, or None when it carries no
    `outcome` field at all (absent, empty, or a file this kit did not write).

    UNLIKE `stage.parse`, A BAD VALUE HERE DOES NOT RAISE. The stage file is
    generated from the repo's own registries and a bad value there means a hand
    edit of derived state; this file is a CLAIM, and every way it can be wrong —
    unknown outcome, partial tier, mismatched binding — has the same correct
    answer: the claim does not hold, so the rung is not reached. Raising would
    turn an untrustworthy claim into a crashed reader, which is a worse failure
    for a file whose entire purpose is to be doubted."""
    record = {}
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        key, sep, value = stripped.partition("=")
        if sep and key.strip() in FIELDS:
            record[key.strip()] = value.strip()
    return record if "outcome" in record else None


def read(root):
    """The parsed record committed at `root`, or None when there is none."""
    path = Path(root) / EVIDENCE_FILE
    try:
        return parse(path.read_text(encoding="utf-8", errors="replace"))
    except OSError:
        return None
