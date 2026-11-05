"""Record one observation result — the one writer of `docs/test/observations/`.

    python scripts/record_observation.py --tc TC-### --outcome pass|fail \\
        --by "<who or what observed>" [--expires YYYY-MM-DDTHH:MM:SSZ] [--root .]

WHAT THIS IS (SR-199). An observation test case is one recorded as not
automated: a judgment the harness cannot rerun, like a person reading a render
or a measurement over an adopter's first week. Its result is not written on
the test case, which would mix what the test IS with what it last FOUND and
force the row's re-attestation after every sample. This command writes it as a
record of its own (`kitlib/observation.py`): the case, the outcome, the moment
it was observed (now, in UTC), who or what observed it, when it expires and a
digest of the inputs the case declares it reads, as they stand now.

WHAT IT REFUSES, WRITING NOTHING: a case the registry does not declare, a case
that is automated (its results are the harness's own evidence record), an
outcome outside pass | fail, a missing provenance, a case declaring no usable
lifetime (`max_age`), a case declaring an input outside the repository, and
an expiry that is not canonical UTC, precedes the
observation, or lies further than the case's lifetime after it. With no
`--expires` the record expires one lifetime after the observation. The format
is judged by the record module's own reader and the policy by
`assumption_rules.record_policy_problem`, the rule the traceability check
applies to a record it finds on disk, so the writer and the checker cannot
disagree about what may stand.

WHY THE DIGEST (`inputs_digest`). A result is trusted only while what it judged
is unchanged. Each declared input is folded in declared order as its name, a
NUL and the SHA-256 of its LF-normalized bytes, the fold `kitlib/stage.py`
uses for the stage fingerprint, so a checkout's line endings never make a
result stale. A registry row id among the inputs is digested as that row's
cells as the carrier reads them, so an edit to the row moves the digest and an
edit to its neighbours does not.

AND WHAT JUDGING THEM READS. The checker's rules read no file, so the reads
they need live beside the writer that produces the records:
`evidence_inputs` reads the record files and each accepted risk's approval
act, once per run, and `trace.py` hands them to the rules.

WHAT IT NEVER DOES. It never opens the test-case registry for writing, so
recording a sample re-opens no approval. And the records' directory is not a
declared stage input and lies outside the release evidence's source surface,
so recording a sample never makes the stage's fingerprint or a release claim
stale.

Contracts: IF-215 — the seam this module declares (process.md §8; row of record
in docs/requirements/interfaces.toml).

Contract IF-215: the observation writer, as a command and as a call.
    `record_observation.py --tc <id> --outcome pass|fail --by <provenance>
    [--expires <canonical UTC>] [--root <dir>]` writes one record under
    `docs/test/observations/` through `kitlib.observation.write_atomic` and
    exits 0, or prints a line starting `record_observation: REFUSED` to stderr,
    writes nothing and exits nonzero. It reads the test-case registry through
    the carrier and never writes it. `inputs_digest(root, inputs, links=None)`
    is the digest a record's `judged` is compared with to decide whether it is
    current (`links`: the paths git records as links, read from the index when
    not given):
    `""` for no inputs, else `sha256:<hex>` over each input in declared order
    as its name, NUL, the SHA-256 of its LF-normalized bytes (a directory as
    the fold of its files, a missing path or a link as `(absent)`, a link inside
    a directory contributing nothing (`is_link`, the one link predicate), a
    path outside the repository as `(outside the repository)`, never read),
    and newline, with a
    registry row id (`<PREFIX>-<digits>` of any tier a registry holds: the
    carrier's tiers, the needs, the work items and the registry CSVs) digested
    as that row's cells as its reader reads them, `(absent)` when the tier
    holds no such row. And
    `evidence_inputs(root, das, bifs, framed=None)` is the checker's read of
    everything judging the records needs, returned as the keyword arguments of
    `assumption_rules.observation_evidence_findings`: `records`, `raw_files`
    and `views`.

Python 3.11+, stdlib only; Windows + POSIX.
"""

import argparse
import datetime
import hashlib
import json
import re
import subprocess
import sys
import tomllib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import assumption_rules  # noqa: E402
import baseline_snapshot  # noqa: E402
import spine_carrier  # noqa: E402
from kitlib import config as kitconfig  # noqa: E402
from kitlib import observation as kitobservation  # noqa: E402
from kitlib import registry as kitregistry  # noqa: E402
from kitlib.spine import load_csv, refs  # noqa: E402

TC_REGISTRY = "docs/test/test-cases.toml"

# WHERE A ROW ID AMONG A CASE'S INPUTS IS READ is derived from the registry
# machinery rather than listed here, so a tier the kit adds is digested by its
# cells the day it exists instead of silently reading as a missing path: the
# carrier's tiers (`spine_carrier.REGISTRY_TABLE`) at the homes the snapshot
# records them in (`baseline_snapshot.SNAPSHOT_TIERS`), or else in the registry
# file under these directories holding their table; the needs through their own
# loader; the work items through the spec folder's reader; and any other id
# through the registry CSV whose first column is its id column, the rule the
# id watermark sweeps by.
REGISTRY_DIRS = ("docs/requirements", "docs/test")
WORK_DIR = "docs/work"
_ROW_ID = re.compile(r"\A([A-Z]+)-\d+\Z")

# Build residue a directory input never folds: it changes on every run.
_SKIP_DIRS = frozenset({"__pycache__", ".pytest_cache", ".ruff_cache", ".git"})


def _file_digest(path):
    """SHA-256 of a file's LF-normalized bytes, the stage fingerprint's rule."""
    return hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()


# What a declared input naming a path outside the repository digests as. It
# is never read, so no file the repository does not hold can move a result.
OUTSIDE = "(outside the repository)"
# What a declared input digests as when it names nothing readable: no such
# path, or a committed link.
ABSENT = "(absent)"


def link_paths(root):
    """The repo-relative paths git records as links (mode 120000) in the
    index at `root`, or an empty set where git cannot say. The half of the
    link predicate a checkout needs: a platform that cannot create a link
    checks one out as a plain file of its target, which only git still knows
    is a link."""
    try:
        proc = subprocess.run(
            ["git", "-C", str(root), "ls-files", "-s", "-z"],
            capture_output=True,
            stdin=subprocess.DEVNULL,
        )
    except OSError:
        return frozenset()
    if proc.returncode != 0:
        return frozenset()
    return frozenset(
        e.partition(b"\t")[2].decode("utf-8", "replace")
        for e in proc.stdout.split(b"\0")
        if e.startswith(b"120000 ")
    )


def is_link(root, path, links):
    """THE LINK PREDICATE, one statement for the writer and the checkpoint: a
    path is a link when it, or a directory on the way to it, is a link on
    disk or among `links` (repo-relative paths git records as links). A
    committed link is not content: its target is never read, so it
    contributes nothing to a digest and a change to its target moves no
    result. Following links instead would read different bytes wherever the
    platform checks a link out differently, and could loop or leave the
    repository."""
    base = Path(root)
    rel = path.relative_to(base).as_posix()
    parts = [] if rel == "." else rel.split("/")
    for depth in range(1, len(parts) + 1):
        prefix = "/".join(parts[:depth])
        if prefix in links or (base / prefix).is_symlink():
            return True
    return False


def _directory_digest(root, folder, links):
    """The fold of every file under a directory input, by relative name; a
    link, and anything reached through one, contributes nothing."""
    fold = hashlib.sha256()
    for item in sorted(folder.rglob("*")):
        if any(p in _SKIP_DIRS for p in item.parts) or is_link(root, item, links):
            continue
        if not item.is_file():
            continue
        fold.update(item.relative_to(folder).as_posix().encode("utf-8"))
        fold.update(b"\0")
        fold.update(_file_digest(item).encode("ascii"))
        fold.update(b"\n")
    return fold.hexdigest()


def _toml_home(root, id_col):
    """The registry file under `REGISTRY_DIRS` holding `id_col`'s table, as a
    repo-relative path, or None. Where the snapshot records the tier, that is
    its home; otherwise the one TOML file whose top level carries the table."""
    homes = {col: rel for rel, col in baseline_snapshot.SNAPSHOT_TIERS}
    if id_col in homes:
        return homes[id_col]
    table = spine_carrier.REGISTRY_TABLE[id_col]
    for folder in REGISTRY_DIRS:
        for path in sorted((Path(root) / folder).glob("*.toml")):
            try:
                data = tomllib.loads(path.read_text(encoding="utf-8-sig"))
            except (OSError, UnicodeDecodeError, tomllib.TOMLDecodeError):
                continue
            if isinstance(data.get(table), dict):
                return "{}/{}".format(folder, path.name)
    return None


def _csv_rows(root, id_col):
    """The rows of the registry CSV whose first column is `id_col`, or None
    when no such registry exists."""
    for folder in REGISTRY_DIRS:
        for path in sorted((Path(root) / folder).glob("*.csv")):
            rows = load_csv(path)
            if rows and next(iter(rows[0])) == id_col:
                return rows
    return None


def _rows(root, prefix):
    """`{id: row}` of the tier whose ids carry `prefix`, as its reader reads
    it, or None when no registry holds such a tier: the id is then a path."""
    id_col = prefix + "-ID"
    if id_col == "SN-ID":
        path = Path(root) / baseline_snapshot.NEEDS_REL
        return {str(n.get("id") or ""): n for n in spine_carrier.load_needs(path)}
    if prefix == "WI":
        rows = kitregistry.read_spec_rows(Path(root) / WORK_DIR) or None
    else:
        home = None
        if id_col in spine_carrier.REGISTRY_TABLE:
            home = _toml_home(root, id_col)
        rows = (
            spine_carrier.load(Path(root) / home, id_col)
            if home is not None
            else _csv_rows(root, id_col)
        )
    if rows is None:
        return None
    return {str(r.get(id_col) or "").strip(): r for r in rows}


def _row_digest(rows, rid):
    """SHA-256 of one row's cells, sorted by column, line endings normalized;
    `(absent)` when the registry holds no such row."""
    row = rows.get(rid)
    if row is None:
        return "(absent)"
    cells = {k: str(v).replace("\r\n", "\n") for k, v in row.items()}
    text = json.dumps(cells, sort_keys=True, ensure_ascii=False)
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _input_digest(root, name, links):
    """One declared input's digest: a registry row, a file, a directory, or
    `ABSENT` for a path that does not exist or is a link (`is_link`). A path
    is read at its normalized spelling (`assumption_rules.input_path`), so
    `docs/../src/a.txt` reads `src/a.txt` wherever it is digested. A path
    outside the repository by its name (`assumption_rules.input_escape`) is
    never read: it digests as `OUTSIDE`."""
    if assumption_rules.input_escape(name):
        return OUTSIDE
    match = _ROW_ID.match(name)
    rows = _rows(root, match.group(1)) if match else None
    if rows is not None:
        return _row_digest(rows, name)
    path = Path(root) / assumption_rules.input_path(name)
    if is_link(root, path, links):
        return ABSENT
    if path.is_file():
        return _file_digest(path)
    if path.is_dir():
        return _directory_digest(root, path, links)
    return ABSENT


def inputs_digest(root, inputs, links=None):
    """The digest of a case's declared inputs as they stand now: `""` for a
    case declaring none, else `sha256:<hex>` folding each input in declared
    order as its name, a NUL, its digest and a newline. `links` are the
    repo-relative paths git records as links; read from the index at `root`
    (`link_paths`) when not given, and handed in by a caller digesting a tree
    git does not index, such as a checkpoint's extracted snapshot.

    Implements: SR-199, LLR-235
    """
    if not inputs:
        return ""
    if links is None:
        links = link_paths(root)
    fold = hashlib.sha256()
    for name in inputs:
        fold.update(name.encode("utf-8"))
        fold.update(b"\0")
        fold.update(_input_digest(root, name, links).encode("utf-8"))
        fold.update(b"\n")
    return "sha256:" + fold.hexdigest()


def evidence_inputs(root, das, bifs, framed=None):
    """What judging the observation records reads from disk and git
    (SR-199, SR-201, SR-202), read once, as the keyword arguments of
    `assumption_rules.observation_evidence_findings`.

    The FILE READ half of those rules, which read no file: the record files
    and their parsed records always; and where the frame declares a crossing
    and the registry an assumption, each accepted risk's approval act
    (`baseline_snapshot.risk_acceptance_view`). No digest and no suite record
    is read: an assumption carries no evidence level, so nothing asks whether
    a result is current. `framed` overrides whether a crossing is declared:
    the release gate judges standing whatever the frame declares (SR-206), so
    it reads as framed.
    """
    raw = kitobservation.read_files(root)
    tier = bool((bool(bifs) if framed is None else framed) and das)
    return {
        "records": kitobservation.read_records(root, raw),
        "raw_files": raw,
        "views": {
            d["DA-ID"]: baseline_snapshot.risk_acceptance_view(root, d["DA-ID"])
            for d in das
            if tier and (d.get("AcceptedRisk") or "").strip()
        },
    }


def record_refusal(record, tc):
    """Why the writer refuses `record` for the case row `tc` (None when the
    registry does not declare it), or None when it may be written: first the
    record's own format, read by the record module's strict reader, then its
    case's policy, the rule the checker applies to a record found on disk.

    Implements: SR-199, LLR-235
    """
    why = kitobservation.problem(kitobservation.render(record))
    if why is None:
        why = assumption_rules.record_policy_problem(
            record["tc"], tc, record["observed_at"], record["expires"]
        )
    if why is None:
        why = _escaping_input(tc)
    return why


def _escaping_input(tc):
    """Why the case declares an input outside the repository, or None: the
    declaration check's own rule, so the writer never records a result the
    checker fails the case for."""
    for name in refs((tc or {}).get("Inputs")):
        escape = assumption_rules.input_escape(name)
        if escape:
            return (
                "{} declares input `{}`, {}; a declared input is read inside "
                "the repository only".format((tc or {}).get("TC-ID"), name, escape)
            )
    return None


def _case(root, tid):
    """The declared test case `tid`, or None; the template's `-000` example is
    never a case."""
    for row in spine_carrier.load(Path(root) / TC_REGISTRY, "TC-ID", False):
        if str(row.get("TC-ID") or "").strip() == tid:
            return row
    return None


def _default_expiry(tc, observed_at):
    """One lifetime after the observation, or the observation itself when the
    case declares no usable lifetime; the refusal then names the lifetime."""
    max_age = str((tc or {}).get("MaxAge") or "").strip()
    if not max_age.isdigit():
        return observed_at
    moment = kitobservation.parse_utc(observed_at)
    return kitobservation.format_utc(moment + datetime.timedelta(days=int(max_age)))


def build_observation(root, tid, outcome, provenance, expires=None, now=None):
    """The record to write for case `tid`, observed `now` (the current instant
    by default), or SystemExit naming the refusal, with nothing written.

    Implements: SR-199, LLR-235
    """
    now = now or datetime.datetime.now(datetime.timezone.utc)
    observed_at = kitobservation.format_utc(now)
    tc = _case(root, tid)
    record = {
        "tc": tid,
        "outcome": outcome,
        "observed_at": observed_at,
        "provenance": provenance or "",
        "expires": expires if expires is not None else _default_expiry(tc, observed_at),
        "judged": "",
    }
    why = record_refusal(record, tc)
    if why:
        raise SystemExit(
            "record_observation: REFUSED — {}. Nothing was written.".format(why)
        )
    record["judged"] = inputs_digest(root, refs(tc.get("Inputs")))
    return record


def main(argv=None):
    """The command: judge, then write one record atomically.

    Implements: SR-199, LLR-235
    """
    kitconfig.utf8_console()
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("--tc", required=True, help="the observation test case, TC-###")
    ap.add_argument("--outcome", required=True, help="pass | fail")
    ap.add_argument(
        "--by", default="", help="who or what observed: a person, a role, a process"
    )
    ap.add_argument(
        "--expires",
        default=None,
        help="when the result stops holding, YYYY-MM-DDTHH:MM:SSZ; at most the "
        "case's max_age after now (default: exactly that)",
    )
    ap.add_argument("--root", default=".", help="repo root (default: .)")
    args = ap.parse_args(argv)
    root = Path(args.root)
    record = build_observation(
        root, args.tc.strip(), args.outcome.strip(), args.by, args.expires
    )
    name = kitobservation.record_name(record["tc"], record["observed_at"])
    path = root / kitobservation.OBSERVATIONS_DIR / name
    if path.exists():
        raise SystemExit(
            "record_observation: REFUSED — {} already exists: one record per case "
            "per second. Nothing was written.".format(name)
        )
    path.parent.mkdir(parents=True, exist_ok=True)
    kitobservation.write_atomic(path, kitobservation.render(record))
    print(
        "record_observation: wrote {}/{} ({}, expires {})".format(
            kitobservation.OBSERVATIONS_DIR, name, record["outcome"], record["expires"]
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
