#!/usr/bin/env python3
"""rejudge.py — the CHECKPOINT RE-JUDGE decision: which observation test cases
are due for a fresh judgment at a work-item merge or at release preparation,
and the one re-judge work item each would be filed as.

Stack-agnostic, standard-library only (Python 3.11+, Windows/POSIX).

WHY THIS MODULE EXISTS (SR-215). An observation test case is one recorded as
not automated (`assumption_rules.is_observation_tc`): a judgment the harness
cannot rerun, like a person reading a render. Its result is a record of its own
(`kitlib/observation.py`) carrying an expiry and a digest of the inputs the
case declares it reads, as they stood when judged. That judgment holds only for
the state it looked at, and nothing re-fires it once that state moves. So at
the checkpoints, committed policy and inputs are read without a model. Cadence
and explicit triggers are decided by observation_cadence; the rule's home is
PROCESS.md "Observation judgement". First judgement and expiry are backstops.

THE CHECK RUNS NO MODEL. It reads git and hashes files; the expensive part,
the re-judgment itself, runs only when the filed item is picked up. And one
open item per case keeps a busy week of merges touching one case's inputs from
filing the same judgment many times.

THE INPUTS ARE READ AT A REVISION, NEVER FROM THE WORKING TREE. A checkpoint
is a commit: the merge slot judges the merged trunk commit, release
preparation the commit being released. An uncommitted edit in the checkout is
not what merged or what ships, so it must neither make a case due nor hide one.
The registry, the result records and every declared input are extracted from
that commit into a scratch directory, once per revision whatever the number
of cases, and the digest is taken there by the one
function the observation writer stamps a record with
(`record_observation.inputs_digest`), so the writer and this check can never
disagree about what a digest of the same inputs is.

WHAT CHANGED is named, not just that something did. A result's commit is the
commit that added its record; the declared inputs are digested one by one at
that commit and at the checkpoint, and the ones that differ are named. Where
the record's digest is not that commit's (it was judged against edits that
were never committed), no single input can be blamed, so every declared input
is named.

AN OPEN ITEM IS FOUND BY ITS TYPED CELLS, NEVER BY TITLE (`_open_rejudge`): a
work item whose `Brief` is `rejudge`, whose `Adjudicates` names the case and
whose status is still open. A title match would also find the closed items in
the archive — the registry reader unions both halves — and so would suppress
a case forever after its first re-judgment.

THE DECISION AND NOT THE EFFECT, as `consolidate.py` is for its census. This
module drafts and writes nothing: `intake.mint_rejudge` and the merge-slot arm
file the drafts through `intake._mint`, the one allocator of a work-item id,
and the arrow between the two modules runs one way.

Contracts: IF-228 — the seam this module declares (process.md §8; row of record
in docs/requirements/interfaces.toml).

Contract IF-228: the checkpoint re-judge decision, as calls.
    `observation_test_cases(root, rev)` returns the test-case rows at the
    commit `rev` names whose `Automated` reads No, the `-000` example excluded.
    `checkpoint_for(root, rev, tc)` selects the case's explicit checkpoint,
    or merge for file/component triggers and a missing case.
    `due_cases(root, rev, now=None, *, checkpoint="merge")` returns, per due case in registry order, a
    dict of `tc`, `row`, `why` (one of `WHY_NEVER`, `WHY_CHANGED`,
    `WHY_EXPIRED`, `WHY_TRIGGER`), `digest` (the inputs digest at `rev`, `""` for none),
    `record` (the latest record or None) and `changed` (the declared inputs
    named as changed). `checkpoint_drafts(root, rev, checkpoint, now=None,
    rows=None)` returns the intake drafts for the due cases that have no open
    re-judge item in the work-item registry (`rows`, read from `root` when not
    given): one per case, kind `adjudication`, brief `rejudge`, `adjudicates`
    the case, its title carrying the case id, the digest prefix, the
    checkpoint and the commit. `checkpoint` is one of `CHECKPOINTS` (merge, release, stage-gate), else
    ValueError. `now` is the instant a result's expiry is compared with (the
    clock when not given). Every call reads git only, extracting each revision
    it reads once, streamed and in pathspec chunks; an input is read at its
    normalized path, one naming a path outside the repository is never read,
    and a committed link is excluded as the writer excludes it. A revision git
    cannot resolve, or a registry at it that does not parse, raises
    RejudgeError.
"""

from __future__ import annotations

import datetime
import re
import subprocess
import tarfile
import tempfile
from pathlib import Path

import assumption_rules
import observation_cadence
import record_observation
import spine_carrier
from kitlib import observation as kitobservation
from kitlib import registry as kitregistry
from kitlib.spine import is_example, refs

# The work-item registry, and the test-case registry named by its TOML carrier
# (the CSV carrier is resolved beside it).
WORK = "docs/work"
TC_REGISTRY = "docs/test/test-cases.toml"

# The declared `Brief` a re-judge item carries, and the kind that routes it.
# An adjudication runs no build bar and is briefed as a judge: re-judging is a
# judgment, and the brief (`adjudicate_brief`) is filled from this module's
# live decision rather than from the item's own prose.
# Implements: SR-215, LLR-254
BRIEF = "rejudge"
KIND = "adjudication"

# Explicit checkpoint kinds; Tier alone never manufactures a trigger.
# Implements: SR-215, LLR-254
CHECKPOINTS = ("merge", "release", "stage-gate")

# Why a case is due, in the order the decision asks.
WHY_NEVER = "no result recorded"
WHY_CHANGED = "declared inputs changed"
WHY_EXPIRED = "result expired"
WHY_TRIGGER = "declared trigger fired"

# Statuses a work item occupies while it is still somebody's to run.
OPEN_STATUSES = frozenset({"draft", "queued", "active", "deferred"})

# How many hex characters of the digest a title carries: enough to tell two
# judged states apart at a glance, the width `consolidate` uses.
DIGEST_CHARS = 12
# How many paths one `git archive` is handed. A declared input list has no
# upper bound, and Windows caps a command line near 32 KB.
PATHSPEC_CHUNK = 200
BUILDTIER = "medium"
WORKSTREAM = "process"

_ROW_ID = re.compile(r"\A([A-Z]+)-\d+\Z")


class RejudgeError(RuntimeError):
    """Git could not answer a question the decision needs. The caller refuses
    rather than reading an unanswerable checkpoint as one with nothing due."""


def _run_git(root, *args):
    try:
        return subprocess.run(
            ["git", "-C", str(root), *args],
            capture_output=True,
            stdin=subprocess.DEVNULL,
        )
    except OSError as exc:
        raise RejudgeError("git could not run ({})".format(exc)) from exc


def _commit_of(root, rev):
    """The full sha `rev` names, or RejudgeError."""
    proc = _run_git(
        root, "rev-parse", "--verify", "--quiet", "{}^{{commit}}".format(rev)
    )
    sha = proc.stdout.decode("ascii", "replace").strip()
    if proc.returncode != 0 or not sha:
        raise RejudgeError("{!r} names no commit".format(rev))
    return sha


def _exists_at(root, sha, rel):
    return _run_git(root, "cat-file", "-e", "{}:{}".format(sha, rel)).returncode == 0


def _registry_at(root, sha):
    """`(relpath, text)` of the test-case registry at `sha` under whichever
    carrier it holds, or `(None, None)` when it holds none."""
    found = [
        rel for rel in spine_carrier.carriers(TC_REGISTRY) if _exists_at(root, sha, rel)
    ]
    if len(found) > 1:
        raise RejudgeError(
            "the test-case registry exists under both carriers at {}".format(sha[:7])
        )
    if not found:
        return None, None
    proc = _run_git(root, "show", "{}:{}".format(sha, found[0]))
    if proc.returncode != 0:
        raise RejudgeError("could not read {} at {}".format(found[0], sha[:7]))
    return found[0], proc.stdout.decode("utf-8", "replace")


def _cases_at(root, sha):
    """`(registry relpath, observation case rows)` at `sha`."""
    rel, text = _registry_at(root, sha)
    if rel is None:
        return None, []
    rows = spine_carrier.rows_seq_from_text(text, "TC-ID", Path(rel).suffix)
    if rows is None:
        raise RejudgeError("{} at {} does not parse".format(rel, sha[:7]))
    return rel, [
        r
        for r in rows
        if not is_example(str(r.get("TC-ID") or "").strip())
        and assumption_rules.is_observation_tc(r)
    ]


def _support_paths(inputs):
    """Every path digesting `inputs` reads: each path input itself, and for a
    registry row id the registries the digest resolves it from. An input
    naming a path outside the repository contributes nothing: the digest
    never reads it (`assumption_rules.input_escape`)."""
    paths = []
    for name in inputs:
        if assumption_rules.input_escape(name):
            continue
        match = _ROW_ID.match(name)
        if match is None:
            # The normalized spelling, the one the digest reads: git resolves
            # no `..` in a tree path, so `docs/../src/a.txt` is asked for as
            # `src/a.txt`.
            paths.append(assumption_rules.input_path(name))
            continue
        # The needs registry lives under these directories too.
        paths += list(record_observation.REGISTRY_DIRS)
        if match.group(1) == "WI":
            paths += [p.as_posix() for p in kitregistry.spec_roots(Path(WORK))]
    return [p for p in dict.fromkeys(paths) if p and p != "."]


def _present_paths(root, sha, paths):
    """Which of `paths` the commit holds, asked of ONE `git cat-file
    --batch-check` over stdin, so neither the number of git calls nor the
    length of a command line grows with the inputs declared."""
    if not paths:
        return []
    query = "".join("{}:{}\n".format(sha, p) for p in paths).encode("utf-8")
    try:
        proc = subprocess.run(
            ["git", "-C", str(root), "cat-file", "--batch-check"],
            input=query,
            capture_output=True,
        )
    except OSError as exc:
        raise RejudgeError("git could not run ({})".format(exc)) from exc
    answers = proc.stdout.decode("utf-8", "replace").splitlines()
    if proc.returncode != 0 or len(answers) != len(paths):
        raise RejudgeError("git could not list the paths at {}".format(sha[:7]))
    return [p for p, line in zip(paths, answers) if not line.endswith(" missing")]


def _archive_chunk(root, sha, chunk, dest):
    """Extract one chunk of paths at `sha` under `dest`, streaming the archive
    through a pipe rather than holding it in memory. A committed link is not
    content (`record_observation.is_link`): it is never written, and its path
    is returned so the digest reads it as the writer does."""
    links = set()
    safe = {"filter": "data"} if hasattr(tarfile, "data_filter") else {}
    try:
        proc = subprocess.Popen(
            ["git", "-C", str(root), "archive", "--format=tar", sha, "--", *chunk],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except OSError as exc:
        raise RejudgeError("git could not run ({})".format(exc)) from exc
    try:
        with tarfile.open(fileobj=proc.stdout, mode="r|") as tar:
            for member in tar:
                if member.issym() or member.islnk():
                    links.add(member.name)
                else:
                    tar.extract(member, dest, **safe)
    except tarfile.TarError as exc:
        proc.kill()
        proc.communicate()
        raise RejudgeError(
            "git archive at {} was unreadable: {}".format(sha[:7], exc)
        ) from exc
    _out, err = proc.communicate()
    if proc.returncode != 0:
        raise RejudgeError(
            "git archive failed at {}: {}".format(
                sha[:7], err.decode("utf-8", "replace").strip()
            )
        )
    return links


def _extract(root, sha, paths, dest):
    """Write the files `paths` name at `sha` under `dest`, each at its own
    relative path: ONE snapshot of the revision. A path the commit does not
    hold is skipped, so it digests as absent exactly as a missing file does
    in the working tree. The pathspec goes to git in chunks of
    `PATHSPEC_CHUNK`, so a long input list never meets the Windows
    command-line limit. Returns the committed links met, never written."""
    present = _present_paths(root, sha, list(dict.fromkeys(paths)))
    links = set()
    for at in range(0, len(present), PATHSPEC_CHUNK):
        links |= _archive_chunk(root, sha, present[at : at + PATHSPEC_CHUNK], dest)
    return links


def _snapshot(root, sha, paths, scratch):
    """`(directory, links)`: a fresh directory under `scratch` holding
    `paths` as the commit `sha` has them, and the committed links among them,
    which are never written and which the digest excludes."""
    dest = Path(scratch) / sha
    dest.mkdir(parents=True, exist_ok=True)
    return dest, frozenset(_extract(root, sha, paths, dest))


def _digest(snap, names):
    """The inputs digest of `names` in the snapshot `snap`."""
    dest, links = snap
    return record_observation.inputs_digest(dest, names, links)


def _added_at(root, sha, record):
    """The commit, reachable from `sha`, that added `record`'s file, or ""."""
    rel = "{}/{}".format(kitobservation.OBSERVATIONS_DIR, record["file"])
    proc = _run_git(root, "log", "-1", "--format=%H", "--diff-filter=A", sha, "--", rel)
    if proc.returncode != 0:
        return ""
    return proc.stdout.decode("ascii", "replace").strip()


def _changed_inputs(here, then, record, inputs):
    """The declared inputs that moved between the snapshot `then`, of the
    commit that added `record`, and `here`, the checkpoint's; every input when
    no commit added it, or when that commit's digest is not the one the record
    judged (it judged uncommitted edits)."""
    if then is None or _digest(then, inputs) != record["judged"]:
        return list(inputs)
    return [n for n in inputs if _digest(then, [n]) != _digest(here, [n])]


def _expired(record, now):
    expires = kitobservation.parse_utc(record["expires"])
    return expires is None or expires <= now


def observation_test_cases(root, rev):
    """The observation test cases the registry holds at the commit `rev`
    names: rows whose `Automated` reads No, the template's `-000` example
    excluded, in registry order.

    Implements: SR-215, LLR-254
    """
    return _cases_at(root, _commit_of(root, rev))[1]


def checkpoint_for(root, rev, tc):
    """Select the case's explicit checkpoint; file/component triggers use merges.

    Implements: SR-215, LLR-254
    """
    case = next((r for r in observation_test_cases(root, rev) if r["TC-ID"] == tc), {})
    trigger = case.get("Trigger")
    return trigger if trigger in CHECKPOINTS else "merge"


def _judge(row, names, here, records, now, cadence):
    """One case's judgement against the checkpoint snapshot `here`, or None
    when it is not due."""
    tc = str(row.get("TC-ID") or "").strip()
    latest = kitobservation.latest(records, tc)
    digest = _digest(here, names) if names else ""
    judgement = {"tc": tc, "row": row, "digest": digest, "record": latest}
    if latest is None:
        return dict(judgement, why=WHY_NEVER, changed=[])
    if _expired(latest, now):
        return dict(judgement, why=WHY_EXPIRED, changed=[])
    since = _added_at(cadence.root, cadence.revision, latest)
    try:
        eligible = cadence.eligible(row, since, cadence.checkpoint)
    except ValueError as exc:
        raise RejudgeError(str(exc)) from exc
    if not eligible:
        return None
    if row.get("Trigger"):
        return dict(judgement, why=WHY_TRIGGER, changed=[row["Trigger"]])
    if names and digest != latest["judged"]:
        return dict(judgement, why=WHY_CHANGED, changed=list(names))
    return None


def _cadence(root, sha, snapshot, checkpoint):
    try:
        return observation_cadence.Cadence(root, sha, snapshot, checkpoint, _run_git)
    except ValueError as exc:
        raise RejudgeError(str(exc)) from exc


def _checkpoint(checkpoint):
    if checkpoint not in CHECKPOINTS:
        raise ValueError("unknown checkpoint {!r}".format(checkpoint))


def due_cases(root, rev, now=None, *, checkpoint="merge"):
    """Cases due at the committed checkpoint under the observation cadence rule
    in PROCESS.md. Absence and expiry bypass cadence; triggers and input-change
    fallback obey the floor. The open-item guard is applied by checkpoint_drafts.

    ONE SNAPSHOT PER REVISION: the checkpoint's commit is extracted once, with
    the records and every case's inputs; then each OTHER commit a changed
    case's result was judged at is extracted once, with the inputs of the
    cases judged there, however many cases and inputs there are. A result
    committed in the checkpoint's own commit reads the checkpoint's snapshot.

    Implements: SR-215, LLR-254
    """
    sha = _commit_of(root, rev)
    _checkpoint(checkpoint)
    now = now or datetime.datetime.now(datetime.timezone.utc)
    _rel, cases = _cases_at(root, sha)
    if not cases:
        return []
    named = [(row, refs(row.get("Inputs"))) for row in cases]
    with tempfile.TemporaryDirectory(prefix="rejudge-") as scratch:
        union = [kitobservation.OBSERVATIONS_DIR, "docs/process.toml"]
        for _row, names in named:
            union += _support_paths(names)
        here = _snapshot(root, sha, union, Path(scratch) / "at")
        records = kitobservation.read_records(here[0])
        cadence = _cadence(root, sha, here[0], checkpoint)
        due, judged_at = [], {}
        for row, names in named:
            item = _judge(row, names, here, records, now, cadence)
            if item is None:
                continue
            due.append(item)
            if item["why"] == WHY_CHANGED:
                then_sha = _added_at(root, sha, item["record"])
                judged_at.setdefault(then_sha, []).append((item, names))
        for then_sha, group in judged_at.items():
            then = here if then_sha == sha else None
            if then_sha and then is None:
                paths = [p for _item, names in group for p in _support_paths(names)]
                then = _snapshot(root, then_sha, paths, Path(scratch) / "then")
            for item, names in group:
                item["changed"] = _changed_inputs(here, then, item["record"], names)
    return due


def _cell(row, name):
    return str(row.get(name) or "").strip()


def _open_rejudge(rows, tc):
    """The open re-judge work item for case `tc`, or None — found by its typed
    cells: `Brief` is `rejudge`, `Adjudicates` names the case, and its status
    is still open. Never by title, because the registry reader unions the
    archive, and a title match would find the closed items there and suppress
    the case forever after its first re-judgment.

    Implements: SR-215, LLR-254
    """
    for row in rows:
        if (
            _cell(row, "Brief").lower() == BRIEF
            and tc in refs(row.get("Adjudicates"))
            and _cell(row, "Status").lower() in OPEN_STATUSES
        ):
            return row
    return None


def _digest_label(digest):
    return digest[: len("sha256:") + DIGEST_CHARS] if digest else "no inputs"


def explain(due):
    """What changed for one due case, as the one sentence a draft and the
    re-judge brief both carry."""
    record = due["record"]
    if due["why"] == WHY_NEVER:
        return "no result has been recorded for it"
    if due["why"] == WHY_CHANGED:
        return "its declared inputs changed since its result {} was judged: {}".format(
            record["file"], "; ".join(due["changed"]) or "(none named)"
        )
    if due["why"] == WHY_TRIGGER:
        return "its declared trigger {} fired after its work-item floor".format(
            due["row"]["Trigger"]
        )
    return "its result {} expired at {}".format(record["file"], record["expires"])


def _context(due, checkpoint, sha):
    row, record = due["row"], due["record"]
    inputs = refs(row.get("Inputs"))
    latest = (
        "{} ({}, observed {}, expires {})".format(
            record["file"], record["outcome"], record["observed_at"], record["expires"]
        )
        if record
        else "none"
    )
    return "\n".join(
        [
            "The {} checkpoint at {} found observation test case {} due for "
            "re-judging.".format(checkpoint, sha[:7], due["tc"]),
            "",
            "- What changed: {}.".format(explain(due)),
            "- Method: {}".format(_cell(row, "Method") or "(not declared)"),
            "- Expected: {}".format(_cell(row, "Expected") or "(not declared)"),
            "- Rubric: {}".format(_cell(row, "Rubric") or "(not declared)"),
            "- Declared inputs: {}".format(
                "; ".join(inputs) if inputs else "none, so it is judged by expiry alone"
            ),
            "- Result lifetime: {} days".format(
                _cell(row, "MaxAge") or "(not declared)"
            ),
            "- Latest result: {}".format(latest),
            "- Inputs digest at {}: {}".format(sha[:7], due["digest"] or "(no inputs)"),
            "",
            "The check that filed this hashed the declared inputs and ran no "
            "model. Re-judge the case by its Method and record the result with "
            "`python scripts/record_observation.py --tc {} --outcome pass|fail "
            '--by "<who or what observed>"`.'.format(due["tc"]),
        ]
    )


def _draft(due, checkpoint, sha, specref):
    return {
        "title": "re-judge {}: {} [{}] at {} {}".format(
            due["tc"], due["why"], _digest_label(due["digest"]), checkpoint, sha[:7]
        ),
        "kind": KIND,
        "brief": BRIEF,
        "adjudicates": [due["tc"]],
        "workstream": WORKSTREAM,
        "buildtier": BUILDTIER,
        "specref": specref,
        "sr_refs": [v for v in refs(due["row"].get("Verifies")) if v.startswith("SR-")],
        "context": _context(due, checkpoint, sha),
    }


def checkpoint_drafts(root, rev, checkpoint, now=None, rows=None):
    """The re-judge drafts a checkpoint at the commit `rev` names would file:
    one per due case (`due_cases`) that has no open re-judge item in the
    work-item registry. Each names its case and what changed, and its title
    carries the case id, why it is due, the digest prefix, the checkpoint and
    the commit, so a recovery re-run of the same checkpoint is the same title
    and the mint's exact-title dedup answers it.

    Implements: SR-215, LLR-254
    """
    _checkpoint(checkpoint)
    sha = _commit_of(root, rev)
    due = due_cases(root, sha, now, checkpoint=checkpoint)
    if not due:
        return []
    if rows is None:
        rows = kitregistry.read_spec_rows(Path(root) / WORK)
    specref = _registry_at(root, sha)[0] or TC_REGISTRY
    return [
        _draft(d, checkpoint, sha, specref)
        for d in due
        if _open_rejudge(rows, d["tc"]) is None
    ]
