"""The OBSERVATION RECORD: one result of a test the harness cannot rerun, kept
apart from its test case — the file's format, its strict reader and the write
that never leaves half of one where a reader looks.

WHY A RECORD OF ITS OWN (SR-199). An observation test case is a judgment the
harness cannot rerun: a person reading a render, a measurement across an
adopter's first week. Its result cannot live on the approved test case, which
would mix what the test IS with what it last FOUND and force the row's
re-attestation after every sample. So each result is one file here, naming its
case, its outcome, when it was observed, who or what observed it, when it
expires and a digest of the inputs it judged. The digest is what lets a later
change to those inputs make the result stale without a clock, and the expiry
is what keeps it from standing forever. Automated tests need no such record:
their results are the harness's tree-bound evidence record (`evidence.py`).

ONE FILE PER RECORD, NAMED BY ITS CASE AND ITS INSTANT
(`<TC id>.<observed-at in UTC, colon-free>.toml`), so records written on
different lanes never collide in a merge, and the directory is append-only by
construction: a new sample is a new file, never an edit of an old one.

WHAT MAKES A FILE A RECORD is `problem` returning nothing: every field present
as a string, both instants in the ONE canonical UTC form (`parse_utc`), an
expiry not before the observation, an outcome in the closed pair, a
provenance that says something and, for a file read from the directory, the
name its case and instant give it. A truncated or hand-mangled file therefore
reads as no result at all, never as a wrong one — the same fail-direction
`evidence.parse` takes, since every way a record can be wrong has the same
answer: it evidences nothing. Whether a well-formed record keeps its case's
POLICY (a declared observation case, an expiry within its lifetime) is a join
against the test-case registry, which this module does not read; that judge is
`assumption_rules.record_policy_problem`.

THE WRITE IS ATOMIC because a crash mid-write must leave nothing a reader takes
for a result: the text goes to a leading-dot temporary name beside the target,
which `read_files` never reads, and one `os.replace` puts it in place. On
Windows that replace can be refused while another process (a scanner, an
indexer, an editor) holds the target, so it is retried a bounded number of
times and then raised; the temporary file is removed rather than left.

A kitlib module, in the pattern of `evidence.py`: it imports no sibling script,
only the package's own TOML string emitter, so the writer and the checker read
one format.

Contracts: IF-214 — the seam this module declares (process.md §8; row of record
in docs/requirements/interfaces.toml).

Contract IF-214: the observation record, as a file and as a call.
    One TOML file per result under `OBSERVATIONS_DIR`, named
    `record_name(tc, observed_at)`, holding exactly the `FIELDS` as strings:
    `tc`, `outcome` (one of `OUTCOMES`), `observed_at` and `expires` (the
    canonical `YYYY-MM-DDTHH:MM:SSZ`, `expires` not earlier), `provenance`
    (non-blank) and `judged` (the inputs digest, `""` for a case declaring no
    inputs). `render(record)` writes one and `write_atomic(path, text)` puts
    it in place; `problem(text, name=None)` names why a text is not a record,
    judging the file `name` against `record_name` when one is given, and
    `parse(text, name=None)` returns the record or None. `read_files(root)` returns
    `{name: text}` for every `*.toml` file in the directory whose name does not
    start with a dot, `read_records(root, files=None)` the parsed records of
    those files whose names are their own, each carrying its `file` name, and `latest(records, tc)` the
    newest by `observed_at`. No reader raises on a bad file; an absent
    directory reads as no records.
"""

import datetime
import os
import re
import time
import tomllib
from pathlib import Path

from .spine import toml_string

# Where the records live, repo-relative. NOT a declared stage input
# (`stage.DECLARED_INPUTS`) and outside the release evidence's source surface
# (`evidence.source_files` skips it), so recording a sample never makes the
# stage's fingerprint or a release claim stale.
# Implements: SR-199, LLR-234
OBSERVATIONS_DIR = "docs/test/observations"

# THE FIELDS EVERY RECORD CARRIES, in the order they are written. `judged` is
# the digest of the inputs the case declares it reads, as they stood when
# judged; it is the empty string for a case declaring none.
# Implements: SR-199, LLR-234
FIELDS = ("tc", "outcome", "observed_at", "provenance", "expires", "judged")

# The closed pair. A failing record is kept: it is falsification evidence
# against what the case evidences, which is exactly what a later reader needs.
# Implements: SR-199, LLR-234
OUTCOMES = ("pass", "fail")

# How many times the final replace is attempted, and the pause between. Five
# tries over a fifth of a second outlasts the brief lock a scanner or indexer
# takes on Windows; a lock held longer is a real conflict, and it is raised.
REPLACE_ATTEMPTS = 5
REPLACE_PAUSE = 0.05

# THE ONE CANONICAL INSTANT: UTC, whole seconds, a literal `T` and `Z`. One
# form, so two records compare by text and a file name derived from the
# instant is the same on every machine.
_UTC = re.compile(r"\A(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})Z\Z")

_HEADER = (
    "# OBSERVATION RECORD, written by scripts/record_observation.py. Do not edit:\n"
    "# a new sample is a new record, and a record that fails to parse, or whose\n"
    "# case or lifetime does not allow it, fails the traceability check.\n"
)


def parse_utc(text):
    """The instant a canonical UTC string names, as an aware datetime, or None
    for anything else: another offset, fractional seconds, a missing `Z`, a
    date that does not exist.

    Implements: SR-199, LLR-234
    """
    match = _UTC.match(text) if isinstance(text, str) else None
    if match is None:
        return None
    try:
        return datetime.datetime(
            *(int(part) for part in match.groups()), tzinfo=datetime.timezone.utc
        )
    except ValueError:
        return None


def format_utc(moment):
    """`moment` (an aware datetime) in the canonical form, to the second."""
    return moment.astimezone(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def record_name(tc, observed_at):
    """The file name of a record: its case and its instant, colon-free, since a
    colon is not a legal file-name character on Windows."""
    return "{}.{}.toml".format(tc, observed_at.replace(":", ""))


def problem(text, name=None):
    """Why `text` is not a whole record, or None when it is one. The one
    statement of what a record is: `parse` returns nothing whenever this
    returns a reason, and the checker names the reason beside the file.

    `name`, when given, is the file the text was read from, and it must be the
    name the record's own case and instant give it (`record_name`): a record
    is found by its name, so a whole record saved as `notes.toml`, or under
    another case's or another instant's name, would otherwise evidence
    something no reader looking for that case's records expects. With no name
    the content alone is judged, which is the writer's case: it names the
    file from the record."""
    try:
        data = tomllib.loads(text)
    except tomllib.TOMLDecodeError as exc:
        return "not TOML ({})".format(exc)
    why = _content_problem(data)
    if why is not None or name is None:
        return why
    expected = record_name(data["tc"], data["observed_at"])
    if name != expected:
        return "the file is named {}, but its case and instant name it {}".format(
            name, expected
        )
    return None


def _content_problem(data):
    """Why a parsed TOML table is not a whole record's content, or None."""
    missing = [f for f in FIELDS if f not in data]
    if missing:
        return "missing {}".format(", ".join(missing))
    not_text = [f for f in FIELDS if not isinstance(data[f], str)]
    if not_text:
        return "{} not written as text".format(", ".join(not_text))
    if not data["tc"].strip():
        return "tc names no test case"
    if data["outcome"] not in OUTCOMES:
        return "outcome {!r} is not one of {}".format(
            data["outcome"], " | ".join(OUTCOMES)
        )
    observed, expires = parse_utc(data["observed_at"]), parse_utc(data["expires"])
    for field, value in (("observed_at", observed), ("expires", expires)):
        if value is None:
            return "{} {!r} is not canonical UTC (YYYY-MM-DDTHH:MM:SSZ)".format(
                field, data[field]
            )
    if expires < observed:
        return "expires {} before it was observed at {}".format(
            data["expires"], data["observed_at"]
        )
    if not data["provenance"].strip():
        return "provenance is empty: a record names who or what observed"
    return None


def parse(text, name=None):
    """The record `text` carries, as `{field: str}` over `FIELDS`, or None when
    it is not a whole record (`problem`, which also judges `name`, the file it
    was read from, when given). A truncated, hand-mangled or misnamed file is
    never a result.

    Implements: SR-199, LLR-234
    """
    if problem(text, name) is not None:
        return None
    data = tomllib.loads(text)
    return {f: data[f] for f in FIELDS}


def render(record):
    """The record's file text: a comment header, then each of `FIELDS` as a
    TOML basic string in declared order. It validates nothing; the writer
    judges a record before writing it."""
    lines = ["{} = {}".format(f, toml_string(str(record[f]))) for f in FIELDS]
    return _HEADER + "\n".join(lines) + "\n"


def read_files(root):
    """`{name: text}` for every record file under `OBSERVATIONS_DIR`, in name
    order: each `*.toml` whose name does not start with a dot. A leading dot is
    the temporary name `write_atomic` writes before its replace, so a write
    caught halfway is never read. `{}` when the directory does not exist.
    """
    folder = Path(root) / OBSERVATIONS_DIR
    if not folder.is_dir():
        return {}
    out = {}
    for path in sorted(folder.glob("*.toml")):
        if path.name.startswith(".") or not path.is_file():
            continue
        try:
            out[path.name] = path.read_text(encoding="utf-8-sig", errors="replace")
        except OSError:
            continue
    return out


def read_records(root, files=None):
    """The whole records among the record files, each `parse`d and carrying its
    `file` name; a file that does not parse, or whose name is not the one its
    case and instant give it, is left out, so no consumer ever reads half a
    record, or a record filed where no one looks, as a result. `files`, when given, is a `read_files`
    result to parse instead of reading the directory again.

    Implements: SR-199, LLR-234
    """
    if files is None:
        files = read_files(root)
    out = []
    for name, text in files.items():
        record = parse(text, name)
        if record is not None:
            record["file"] = name
            out.append(record)
    return out


def latest(records, tc):
    """The newest of `tc`'s records by `observed_at`, or None. The canonical form
    makes the text order the time order; the file name breaks a tie, so the
    answer never depends on the order the records were read in.

    Implements: SR-199, LLR-234
    """
    mine = [r for r in records if r.get("tc") == tc]
    if not mine:
        return None
    return max(mine, key=lambda r: (r["observed_at"], r.get("file", "")))


def write_atomic(
    path, text, *, replace=os.replace, attempts=REPLACE_ATTEMPTS, pause=REPLACE_PAUSE
):
    """Write `text` to `path` so no reader ever sees part of it: to a
    leading-dot temporary name beside it first, flushed to disk, then moved
    into place by one replace.

    A PermissionError from the replace, which Windows raises while another
    process holds the target, is retried up to `attempts` times in all with
    `pause` seconds between, then raised; on POSIX the same error is permanent
    and the retries cost only the pauses. On any failure the temporary file is
    removed. `replace` is the one step a test substitutes.

    Implements: SR-199, LLR-234
    """
    path = Path(path)
    temp = path.with_name("." + path.name)
    try:
        with open(temp, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        for attempt in range(1, attempts + 1):
            try:
                replace(temp, path)
                return
            except PermissionError:
                if attempt == attempts:
                    raise
                time.sleep(pause)
    finally:
        if temp.exists():
            try:
                temp.unlink()
            except OSError:  # pragma: no cover - the name is never read anyway
                pass
