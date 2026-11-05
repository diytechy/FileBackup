"""Observation cadence: closed-work history and declared checkpoint triggers.

Contracts: IF-269 — cadence policy consumed by rejudge.
Contract IF-269: Cadence(root, revision, snapshot, checkpoint, git) reads the committed
    process policy and git history through git(root, *args), whose result has
    returncode and byte stdout. eligible(row, since, checkpoint) returns whether
    the closed-WI floor and declared trigger permit another judgement; since is
    the commit adding the last record. An empty trigger leaves input digest
    comparison to rejudge. observation_rubric_findings(rows) returns missing-reference
    warnings; examples and automated cases are excluded. Invalid policy or
    unreadable history raises ValueError.
"""

import fnmatch
import re
import tomllib
from pathlib import Path

import spine_carrier
import assumption_rules
from kitlib.spine import is_example, norm_module, refs

DEFAULT_FLOOR = 10
ARCHIVE = "docs/archive/work"


def observation_rubric_findings(rows):
    """Warn on pre-existing observations without a fixed judgement reference.

    Implements: SR-215, LLR-294
    """
    return [
        "TC {} is an observation case with no Rubric reference; write a numbered rubric before its first judgement".format(
            row["TC-ID"]
        )
        for row in rows
        if not is_example(row["TC-ID"])
        and assumption_rules.is_observation_tc(row)
        and not str(row.get("Rubric") or "").strip()
    ]


def _floor(value):
    """A nonnegative whole count; zero explicitly disables the floor."""
    if isinstance(value, bool) or not str(value).isdigit():
        raise ValueError("observation work-item floor must be a nonnegative integer")
    return int(value)


class Cadence:
    """One checkpoint's history, cached per result commit, independent of models.

    Implements: SR-215, LLR-293
    """

    def __init__(self, root, revision, snapshot, checkpoint, git):
        self.checkpoint = checkpoint
        self.root, self.revision, self.snapshot, self.git = (
            root,
            revision,
            snapshot,
            git,
        )
        path = Path(snapshot) / "docs/process.toml"
        policy = (
            tomllib.loads(path.read_text(encoding="utf-8-sig")) if path.exists() else {}
        )
        self.floor = _floor(
            policy.get("checks", {}).get("observation_min_work_items", DEFAULT_FLOOR)
        )
        self.history = {}

    def _read(self, *args):
        proc = self.git(self.root, *args)
        if proc.returncode:
            raise ValueError("git could not read observation cadence history")
        return proc.stdout.decode("utf-8", "replace")

    def _history(self, since):
        if since not in self.history:
            span = "{}..{}".format(since, self.revision)
            closed = self._read(
                "log",
                "--format=",
                "--name-only",
                "--no-renames",
                "--diff-filter=A",
                span,
                "--",
                ARCHIVE,
            )
            ids = set(
                re.findall(
                    r"(?m)^docs/archive/work/(?:complete|cancelled|partial)/(WI-\d+)-[^\n]+\.md$",
                    closed,
                )
            )
            changed = self._read(
                "diff", "--name-only", since, self.revision
            ).splitlines()
            self.history[since] = len(ids), changed
        return self.history[since]

    def _component_paths(self, component, revision):
        paths = []
        for rel, column, field in (
            ("docs/requirements/low-level-requirements.toml", "LLR-ID", "Module"),
            ("docs/requirements/interfaces.toml", "IF-ID", "Owner"),
        ):
            for carrier in spine_carrier.carriers(rel):
                proc = self.git(self.root, "show", "{}:{}".format(revision, carrier))
                if proc.returncode:
                    continue
                rows = spine_carrier.rows_seq_from_text(
                    proc.stdout.decode("utf-8", "replace"), column, Path(carrier).suffix
                )
                if rows is None:
                    raise ValueError("component trigger registry does not parse")
                paths += [
                    norm_module(p)
                    for r in rows
                    if component in refs(r.get("Component"))
                    for p in refs(r.get(field))
                ]
        return paths

    def eligible(self, row, since, checkpoint):
        """The floor gates triggers; absence and expiry are the caller's backstops.

        Implements: SR-215, LLR-293
        """
        if not since:
            raise ValueError("latest observation record has no adding commit")
        count, changed = self._history(since)
        floor = max(self.floor, _floor(row.get("MinWorkItems") or self.floor))
        if count < floor:
            return False
        trigger = str(row.get("Trigger") or "").strip()
        if not trigger:
            return True
        if trigger in ("release", "stage-gate"):
            return checkpoint == trigger and since != self.revision
        kind, _, value = trigger.partition(":")
        if kind == "files" and value:
            return any(
                fnmatch.fnmatchcase(p, pattern)
                for p in changed
                for pattern in refs(value)
            )
        if kind == "component" and re.fullmatch(r"CMP-\d+", value):
            paths = self._component_paths(value, since) + self._component_paths(
                value, self.revision
            )
            return any(
                norm_module(p) == module
                or norm_module(p).startswith(module.rstrip("/") + "/")
                for p in changed
                for module in paths
            )
        raise ValueError("unknown observation Trigger {!r}".format(trigger))
