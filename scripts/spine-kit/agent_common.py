#!/usr/bin/env python3
"""Shared coordinator primitives, extracted VERBATIM from agent_loop.py
(WI-218 slice C — a file split, not a rewrite; behaviors and WI history
unchanged). The session engine (agent_loop) and the serial integrator
(integrate.py) both stand on this layer:

  - the typed exit codes + `END_STATES`;
  - `git`/`head_sha`/`head_sha_full` and the dirty-tree family (owner-only
    scratchpad exemption, WI-203);
  - the declared-surface reads — `read_declared`, `pause_reason`, the WI-148
    blackout window — and the stop banner + Current State excerpt;
  - the per-worktree coordinator lock (kernel advisory lock; the held
    descriptor lives HERE, in this module's `_LOCK_FD`, so every caller
    shares one lock namespace);
  - worker-assignment primitives (`WI_TOKEN_RE`, `sanitize_train`,
    `parse_wi_id`, `load_wi_registry`, `train_evidence`)
    and the small CSV/ref readers;
  - `parse_map`, `preflight` (launchability refusal, SR-027), and the
    session-log family (size-bounded logs, the regenerated iteration index,
    the telemetry commit).

agent_loop re-exports the names it historically exposed, so its public
surface is unchanged. Stdlib only, Python 3.11+, Windows/POSIX.

Contracts: IF-065, IF-189, IF-224 — the interface seams this module declares (process.md
§8; rows of record in docs/requirements/interfaces.toml).

Contract IF-065: the shared coordinator primitives the session engine and the
    serial integrator both stand on. The typed exit codes and `END_STATES`; the
    `git` / `head_sha` / `head_sha_full` wrappers and the dirty-tree family; the
    declared-surface reads (`declared_policy`, `read_agent_loop_config`,
    `pause_reason`, the blackout window) and `stop_banner`; the per-worktree
    kernel advisory lock, whose held descriptor lives HERE so every caller in a
    process shares one lock namespace and `acquire_lock` / `release_lock` cannot
    disagree about what is held; the worker-assignment primitives
    (`WI_TOKEN_RE`, `sanitize_train`, `parse_wi_id`, `load_wi_registry`,
    `train_evidence`); `loop_claimed`, the one reader of whether the loop
    claimed a lane, which the integrator's merge slot reads a lane's claim
    through and which answers a claim log it cannot read as unreadable, never
    unclaimed; `parse_map`; `preflight`, the launchability refusal; and
    the session-log family — every log through one shared writer, with
    planner/probe/interactive launches through one durable invocation boundary,
    the regenerated iteration index and telemetry commit — with the generated
    run-state write. The names
    were extracted verbatim and `agent_loop` re-exports every historical one, so
    this layer adds a home without changing a public surface.
Contract IF-189: `default_base(root)`, the integration base a claimed branch's
    change is read from by the per-change readability report: the merge base of
    HEAD with the declared trunk, in a single checkout as in a linked worktree;
    HEAD on an unrelated history, None on an unborn HEAD — which the caller
    treats as an unreadable change rather than an empty one; and
    `TrunkUndeclared` when the trunk's declaration cannot be read.
Contract IF-224: `human_approves_spine(docs, registry)`, read by the owner's
    approval brief to set apart the owing chains the human-approval dial
    releases to an adjudicator: True (held) for a spine registry whose rung the
    dial holds and for one no rung map names, False for a released one. The
    brief asks it once per spine tier per rendering and keeps no rung table of
    its own.
"""

import hashlib
import errno
import os
import re
import shutil
import socket
import subprocess
import sys
import time
from pathlib import Path

# THE SHIPPED SHARED-HELPER PACKAGE (owner ruling D-8, `OI-16`, executed
# WI-448): one home for behaviours this module used to spell out itself — the
# declared-policy line reader, the `docs/work/` spec-folder registry reader, and
# (WI-498 slice 0) the stage ladder's closed rung vocabulary.
# It replaces the F5 rule, which had licensed those copies unbounded and left
# `tests/test_rule_sync.py` pinning them equal by value. Run as a subprocess
# this script's own dir is sys.path[0] so a plain import resolves; the guard
# covers an in-process import (a test) whose sys.path does not yet carry
# scripts/ — the same sanctioned-sibling idiom the engines use for each other.
try:
    from kitlib import config as _kitconfig
    from kitlib import provenance as _kitprovenance
    from kitlib import registry as _kitregistry
    from kitlib import secret_classes as _kitsecrets
    from kitlib import spine as _kitspine
except ImportError:  # pragma: no cover - in-process fallback
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from kitlib import config as _kitconfig
    from kitlib import provenance as _kitprovenance
    from kitlib import registry as _kitregistry
    from kitlib import secret_classes as _kitsecrets
    from kitlib import spine as _kitspine

# This module's own directory, so `spine_stage_of` can spawn the sibling
# `derive_stage.py` on a fingerprint miss without importing it.
_SCRIPTS_DIR = Path(__file__).resolve().parent

# Sibling scripts (the WI-218 split): preflight validates the AGENT_CMD
# template through the headless session layer. The guard covers an in-process
# import (a test) whose sys.path doesn't yet carry scripts/ — the same
# sanctioned-sibling-import idiom agent_loop uses.
try:
    from agent_session import build_argv, split_cmd
except ImportError:  # pragma: no cover - in-process fallback
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from agent_session import build_argv, split_cmd

# The held-status judgement the loop's writers owe before they commit
# (`loop_held_status_refusal`): a leaf reader of two git trees, importing
# nothing of the coordinator's, so the edge runs one way.

try:
    import agent_policy
except ImportError:  # pragma: no cover - in-process fallback
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import agent_policy

# The declared-policy and approval subsystem moved as one behavior cluster;
# retain the historical shared-primitives surface for existing consumers.
read_declared = agent_policy.read_declared
PROCESS_TOML = agent_policy.PROCESS_TOML
PROCESS_KEYS = agent_policy.PROCESS_KEYS
PROCESS_ONLY_KEYS = agent_policy.PROCESS_ONLY_KEYS
PROCESS_KEY_RANGES = agent_policy.PROCESS_KEY_RANGES
PROCESS_KEY_VOCAB = agent_policy.PROCESS_KEY_VOCAB
PROCESS_KEY_LEGACY_VALUES = agent_policy.PROCESS_KEY_LEGACY_VALUES
_process_toml_path = agent_policy._process_toml_path
process_config = agent_policy.process_config
read_toml_text = agent_policy.read_toml_text
read_toml = agent_policy.read_toml
_coerce = agent_policy._coerce
declared_policy = agent_policy.declared_policy
parse_blackout = agent_policy.parse_blackout
blackout_at = agent_policy.blackout_at
LEGACY_APPROVAL = agent_policy.LEGACY_APPROVAL
APPROVAL_DIAL_RUNGS = agent_policy.APPROVAL_DIAL_RUNGS
LEGACY_DIAL_ORDINALS = agent_policy.LEGACY_DIAL_ORDINALS
APPROVAL_FALLBACK = agent_policy.APPROVAL_FALLBACK
LEGACY_ATTESTATION_KEY = agent_policy.LEGACY_ATTESTATION_KEY
legacy_approval = agent_policy.legacy_approval
approval_through = agent_policy.approval_through
_retired_dial_note = agent_policy._retired_dial_note
LADDER_RUNGS = agent_policy.LADDER_RUNGS
APPROVAL_RUNGS = agent_policy.APPROVAL_RUNGS
SPINE_APPROVAL_RUNGS = agent_policy.SPINE_APPROVAL_RUNGS
human_holds = agent_policy.human_holds
human_approves = agent_policy.human_approves
human_approves_spine = agent_policy.human_approves_spine
loop_held_status_refusal = agent_policy.loop_held_status_refusal
final_review = agent_policy.final_review
complete_review = agent_policy.complete_review
ADJUDICATION_REVIEW_MODES = agent_policy.ADJUDICATION_REVIEW_MODES
_REVIEW_OWED_CLASSES = agent_policy._REVIEW_OWED_CLASSES
_REVIEW_OWED_BRIEFS = agent_policy._REVIEW_OWED_BRIEFS
adjudication_review = agent_policy.adjudication_review
DECISION_RECORDING_MODES = agent_policy.DECISION_RECORDING_MODES
decision_recording = agent_policy.decision_recording
adjudication_review_owed = agent_policy.adjudication_review_owed
SPEC_HOMES = agent_policy.SPEC_HOMES
_spec_home_rank = agent_policy._spec_home_rank
authoritative_spec = agent_policy.authoritative_spec
keep_nondependent = agent_policy.keep_nondependent
spine_stage_of = agent_policy.spine_stage_of
_legacy_present = agent_policy._legacy_present
_in_legacy_window = agent_policy._in_legacy_window
_key_value_findings = agent_policy._key_value_findings
_vocab_findings = agent_policy._vocab_findings
mode_word = agent_policy.mode_word
_mode_vocab_findings = agent_policy._mode_vocab_findings
config_conflicts = agent_policy.config_conflicts
AGENT_LOOP_DIALS = agent_policy.AGENT_LOOP_DIALS
read_agent_loop_config = agent_policy.read_agent_loop_config
resolve_coordinator_dials = agent_policy.resolve_coordinator_dials


def scripts_fingerprint(scripts_dir=None):
    """Content identity of the Python implementation this process imported.

    The source directory, relative paths and LF-normalized bytes all join one
    digest, so adding, deleting, renaming or editing a ``*.py`` file moves it.
    The default is this module's actual directory rather than the project root:
    a dispatched worker targets a linked worktree but imports the coordinator
    from the dispatcher's checkout. An entry that is not a regular file (an
    editor's dangling lock symlink, a directory named ``x.py``) is skipped;
    a real file that cannot be read still raises, since its content is unknown.
    """
    scripts_dir = Path(scripts_dir).resolve() if scripts_dir else _SCRIPTS_DIR
    fold = hashlib.sha256()
    for path in sorted(scripts_dir.rglob("*.py")):
        if not path.is_file():
            continue
        fold.update(path.relative_to(scripts_dir).as_posix().encode("utf-8"))
        fold.update(b"\0")
        fold.update(path.read_bytes().replace(b"\r\n", b"\n"))
        fold.update(b"\n")
    return fold.hexdigest()


def _launch_fingerprint():
    """The import-time capture. A scan failure must not crash the twelve entry
    points that import this module: it warns once and returns None. Generic
    importers may continue; agent_loop refuses that unknown identity before it
    enters a coordinator role."""
    try:
        return scripts_fingerprint()
    except OSError as exc:
        print(
            "agent_common: coordinator code-drift detection unavailable ({}); a "
            "coordinator launch must refuse this unknown source identity.".format(exc),
            file=sys.stderr,
        )
        return None


# Captured once, after the shared layer's imports resolve and before either
# coordinator loop starts. Later comparisons always read disk afresh.
LAUNCHED_SCRIPTS_FINGERPRINT = _launch_fingerprint()


def running_scripts_moved():
    """Whether the Python source this process launched from has moved. False
    when the launch capture failed (None): agent_loop refuses that state at
    startup, so a missing baseline never becomes a restart loop."""
    launched = LAUNCHED_SCRIPTS_FINGERPRINT
    try:
        return launched is not None and scripts_fingerprint() != launched
    except OSError:
        # If the implementation is being replaced while the tree is scanned,
        # continuing is the unsafe answer. The caller turns True into the same
        # typed restart used for an ordinary content change.
        return True


# Size bounds for the tracked per-session log (the Q13d "size-bounded" cap):
# the head shows how the session started, the capped tail how it ended — the
# part that explains the outcome. The raw unbounded stream goes to the
# gitignored out/run-logs/ for local debugging.
LOG_HEAD_LINES = 60


LOG_TAIL_LINES = 400


LOG_MAX_BYTES = 65536


# The terminal end states a session/loop outcome may carry. (Their old durable
# home, the dispatcher-generated `docs/run-state` file, retired with the
# dispatcher at concurrency-restructure Phase 5 — the stop banner and exit
# codes carry the outcome now.) NEEDS-HUMAN's one-line ask is the stop
# banner's headline (WI-127).
END_STATES = ("DONE", "BLOCKED", "NEEDS-HUMAN")


EXIT_DONE = 0


EXIT_PREFLIGHT = 2


EXIT_BLOCKED = 3


EXIT_STALL = 4


EXIT_WAITING = 5


EXIT_BUDGET = 6


EXIT_NEEDS_HUMAN = 7


EXIT_PAUSED = 8


# REVIEW OWED (C2, docs/plans/2026-08-30-stall-guard-plan.md): the build is
# committed but a review verdict could not be drawn — every route on the
# reviewer ladder errored, hung or was cooled. Deliberately NOT a decided
# worker outcome (dispatch._WORKER_OUTCOMES): the lane parks with its work,
# like a crash, and the next cycle resumes it to draw the round — finished
# work is never handed back over a reviewer outage (owner direction
# 2026-08-30). Appended at the END of the exit alphabet; 10 stays retired.
EXIT_REVIEW_OWED = 9


# (EXIT_TRAIN_END = 10 retired with session grouping — WI-383, §A6.1: it ended a
# PACKED assignment early when the §7 continuation re-check refused the next
# constituent, and nothing packs. The number stays retired rather than reused —
# an exit code is a contract with every launcher and log that ever read it.)


# The running coordinator's imported Python source moved. This is a resumable
# process outcome, never a work outcome: the caller starts a fresh coordinator,
# which reconstructs the active assignment and evidence from the existing tree.
# Appended after the permanently retired 10 rather than reusing it.
EXIT_RESTART = 11


# RED CAP: the lane's build stayed red at its review bar for the declared
# `[build] red_rounds_max` consecutive rounds. A decided worker outcome, after
# the permanently retired 10 and RESTART.
EXIT_RED_CAP = 12


# The FB3 owner-only path(s): OWNER_SCRATCHPAD.md is free-form owner notes the
# human edits continuously (check_docs.py drops it from doc discovery the same
# way — check_docs.SCRATCHPAD). Because it is tracked and perpetually edited, an
# owner-only-dirty tree is NOT interrupted-session residue: it must not fire the
# WI-076 resume note or flip the done detection (WI-203). Mirrored, not imported
# — importing the doc-checker into the coordinator would add a CMP-008→CMP-007
# edge + an IF seam for one fixed filename; the name is a bootstrap contract
# (test_bootstrap asserts the scaffold ships it), so the mirror cannot drift.
OWNER_ONLY_PATHS = ("OWNER_SCRATCHPAD.md",)


PAUSE_MALFORMED = "<malformed docs/work/pause — fix or delete it>"


def tracked_pause(docs_dir):
    """The **tracked** pause declaration — `docs/work/pause`
    (`docs/concurrency-restructure.md` §5.6). One meaning, and no scope field
    because one meaning needs none: **pause = stop claiming.** Everything in
    flight finishes, integrates, and archives — a traincar always unloads, so a
    pause never strands finished work on a branch; the only thing that stops an
    unload is the integrator's own refusal (red bar, missing verdict), which is
    the gate working, not the pause.

    Presence pauses. An **unpause is a tracked deletion commit** — which is the
    point of tracking the file: it survives clones, the reason is diffable
    history instead of a stale local note, and resuming is auditable.

    TOML, two keys: `reason` (free text) and `since` (a declared stamp, carried
    verbatim — never an age computed from a clock). Returns
    ``{"reason": ..., "since": ...}``, or ``None`` when the file is absent;
    `since` missing renders ``""``. Unparseable TOML or a missing `reason`
    returns a paused dict carrying `PAUSE_MALFORMED` — see above."""
    path = Path(docs_dir) / "work" / "pause"
    if not path.is_file():
        return None
    # `read_toml` folds absent into unreadable; the `is_file` guard above is
    # what keeps "no pause declared" (None) apart from "a pause declared in a
    # file we cannot parse" (PAUSED, malformed) — the fail-closed direction.
    data = read_toml(path)
    if not isinstance(data, dict) or not isinstance(data.get("reason"), str):
        return {"reason": PAUSE_MALFORMED, "since": ""}
    since = data.get("since")
    if since is None:
        since = ""
    elif not isinstance(since, str):
        since = str(since)  # a bare TOML date/int stamps as its ISO/decimal text
    return {"reason": data["reason"], "since": since}


def pause_reason(lane):
    """A declared **graceful-pause** request: pause the loop at the next session
    boundary. Return contract, unchanged and depended on by every caller:
    `None` = not paused; a string = paused, `""` when the declaration carries no
    reason. Presence is the whole contract — an unpause is a reviewed deletion
    commit of the one home, the TRACKED `lane/work/pause` (concurrency-
    restructure §5.6), read via `tracked_pause`. (The legacy untracked
    `lane/pause` half, WI-147, retired with the dispatcher at Phase 5.)

    Implements: SR-156, LLR-138
    """
    tracked = tracked_pause(lane)
    return None if tracked is None else tracked["reason"]


# --- WI-286: the harness interpreter (shared root .venv, floor-checked) --------
# A dispatcher train worktree has no .venv of its own, so a bare `python`/`pytest`
# run there resolves whatever is ambient on PATH (run 20260723T0202 inherited
# Python 3.8, below the floor): a below-floor idiom then passes locally and only
# fails in CI, and the pinned dev tools (requirements-dev.txt) may be absent. The
# fix is to run the harness under the repo's OWN .venv — the pinned ≥3.11
# toolchain — shared into each worktree by absolute path (the dispatcher points a
# worker's PATH at it and sets the integrator bar's {py} to it), plus a preflight
# so a below-floor interpreter is caught before it can produce a false green.

# The kit's Python floor (WI-262/WI-270; the setup scripts enforce the same
# `sys.version_info >= (3, 11)`). An adopter deliberately targeting an older
# product runtime lowers this alongside setup.{sh,ps1}'s own check.
MIN_PYTHON = (3, 11)


def venv_python(root):
    """Absolute path (a Path) to the repo's own .venv interpreter, or None when
    absent. Probes both layouts the kit's launchers do (check.sh, the pre-commit
    hook): POSIX `.venv/bin/python` and a Windows-created `.venv/Scripts/
    python.exe`, so a venv created on either OS is found from either (WI-286)."""
    root = Path(root)
    for rel in ("bin/python", "Scripts/python.exe"):
        cand = root / ".venv" / rel
        if cand.is_file():
            return cand
    return None


def harness_python(root):
    """The interpreter the test harness (pytest + the pinned dev tools) should run
    under for a worktree session: the repo's own .venv when present (shared by
    absolute path — one pinned ≥3.11 toolchain, no per-worktree install).
    Returns a str path — a bar runner substitutes it for {py} so the bar runs
    under the floor-satisfying interpreter even when the caller was itself
    launched on ambient Python (WI-286).

    The ambient `sys.executable` fallback is a DEFENSIVE default only (a
    stdlib-only resolver must return SOMETHING), and it is the honest answer
    ONLY for a repo that has not declared the pinned toolchain. A repo that has
    is refused UPSTREAM by `harness_floor_failures` below - integrate.py calls
    it before the bar - so a declared repo never reaches this fallback
    (WI-361; the dispatcher-era gate this replaces died at Phase 5)."""
    py = venv_python(root)
    return str(py) if py else sys.executable


def interpreter_version(exe):
    """(major, minor) of the interpreter at `exe`, or None when it cannot be run.
    `exe` None or equal to this process's own sys.executable reads sys.version_info
    directly (no subprocess); any other path is probed by RUNNING it, so a stale
    .venv reports its real version rather than this process's (WI-286)."""
    if exe is None or str(exe) == sys.executable:
        return sys.version_info[:2]
    try:
        proc = subprocess.run(
            [
                str(exe),
                "-c",
                "import sys;print(sys.version_info[0],sys.version_info[1])",
            ],
            capture_output=True,
            text=True,
            stdin=subprocess.DEVNULL,
        )
    except OSError:
        return None
    if proc.returncode != 0:
        return None
    parts = proc.stdout.split()
    try:
        return (int(parts[0]), int(parts[1]))
    except (ValueError, IndexError):
        return None


def harness_floor_failures(root):
    """WI-286/WI-361: a singleton list with a floor message when the interpreter
    the harness would run under is not a floor-satisfying, PINNED root .venv,
    else []. A tree without the repo's own .venv resolves ambient PATH (run
    20260723T0202 inherited 3.8), so a below-floor idiom passes locally and only
    fails in CI - and an ambient-MODERN interpreter is the worse half, clearing
    the version floor while lacking the pinned dev tools the bar assumes, which
    makes its green FALSE. integrate.py is the refusing seam: it calls this
    before the composed-tree bar rather than running the bar on ambient Python.

    ARMING BOUNDARY: the floor guards only a repo that DECLARES the pinned
    toolchain - concretely, one carrying `requirements-dev.txt` at its root. A
    repo without that declaration (a fresh scaffold, a test fixture, an adopter
    on another stack) never sees this refusal and keeps `harness_python`'s
    ambient fallback: there is no pin to hold it to, so refusing would enforce a
    contract it never opted into.

    Once armed it FAILS CLOSED on three shapes:

    - **no runnable root .venv at all** - absent, or a present-but-incomplete/
      corrupt layout (`venv_python` finds no interpreter). This must NOT fall
      back to the ambient interpreter (REVIEW-A MAJOR on WI-286);
    - a .venv whose interpreter cannot be run to report a version;
    - a below-floor .venv (< MIN_PYTHON).

    Returned as a LIST so a caller folds it into existing refusals with `+`."""
    if not (Path(root) / "requirements-dev.txt").is_file():
        return []
    floor = "{}.{}".format(*MIN_PYTHON)
    py = venv_python(root)
    if py is None:
        return [
            "no runnable ./.venv interpreter found under {} (absent, or an "
            "incomplete/corrupt .venv layout). This repo declares a pinned "
            "toolchain (requirements-dev.txt), so the harness - tests plus those "
            "pinned dev tools - must run under the repo's OWN Python {}+ .venv, "
            "NOT the ambient interpreter, which may clear the version floor yet "
            "lack the pinned tools and produce a false green. Run scripts/"
            "dev-setup --install to create ./.venv (WI-286/WI-361).".format(root, floor)
        ]
    ver = interpreter_version(py)
    if ver is None:
        return [
            "the ./.venv interpreter ({}) could not be run to check its version "
            "- recreate it (scripts/dev-setup --install; WI-286/WI-361).".format(py)
        ]
    if ver < MIN_PYTHON:
        return [
            "the repo ./.venv is Python {}.{} - below the {} floor. The harness "
            "(tests plus pinned dev tools) must run under a floor-satisfying "
            "interpreter, or a below-floor idiom passes locally and only fails in "
            "CI. Run scripts/dev-setup --install to (re)create ./.venv at Python "
            "{}+ (WI-286/WI-361).".format(ver[0], ver[1], floor, floor)
        ]
    return []


def _declared_test_command(ini, py=None):
    """The repo's declared test command as a tokenized argv, read from a
    docs/stack.ini path — the stack-schema home a bar runner reads so it runs
    the bar the repo actually declares. Mirrors check.py's stack schema rather
    than importing it — the OWNER_ONLY_PATHS precedent above: a CMP-008→CMP-007
    import for one small read would owe an IF seam; the tests pin it against
    drift. The kit schema is `[product] test` (with {py}/{src}/{tests} the same
    placeholders check.py fills), with the legacy raw `[stack] test` as a
    fallback. Returns None only when NEITHER key is present (a genuinely
    stackless profile → the caller legitimately skips); otherwise the argv —
    possibly [] for a declared-but-empty command, which the caller treats as a
    misconfiguration, not a skip (WI-285: a declared-but-unread key must not
    silently pass). Raises ValueError, naming the file, on an absent or
    unreadable profile; the parse is `kitlib.config.read_stack_ini`'s. `{py}` is
    `py` when given (the integrator points it at the repo's floor-satisfying
    .venv — WI-286), else this process's own interpreter."""
    try:
        cp = _kitconfig.read_stack_ini(ini)
    except _kitconfig.StackIniError as exc:
        raise ValueError(str(exc)) from exc
    if cp is None:
        raise ValueError("{}: no such file".format(ini))
    if cp.has_section("product") and cp.has_option("product", "test"):
        subs = {
            "py": py or sys.executable,
            "src": cp.get("paths", "src", fallback="src"),
            "tests": cp.get("paths", "tests", fallback="tests"),
        }
        argv = []
        for tok in split_cmd(cp.get("product", "test")):
            for key, val in subs.items():
                tok = tok.replace("{" + key + "}", val)
            argv.append(tok)
        return argv
    if cp.has_section("stack") and cp.has_option("stack", "test"):
        return split_cmd(cp.get("stack", "test"))  # legacy raw: no substitution
    return None


# --- WI-261: blackout pause feedback (banner + countdown heartbeat) --------------
# The window SEMANTICS live in agent_policy.blackout_at; these render the WAIT so a
# walk-away launch reads as deliberately paused, not hung. All three are pure /
# injectable so the terminal feedback is testable without a real multi-second
# sleep. The scaffold's default cadence between countdown heartbeats (seconds).
BLACKOUT_HEARTBEAT_SEC = 300


def _fmt_hms(seconds):
    """Whole seconds as a compact `Hh Mm Ss`, dropping leading zero units but
    always keeping seconds: 25200 -> '7h 0m 0s', 90 -> '1m 30s', 45 -> '45s'."""
    seconds = int(seconds)
    hours, rem = divmod(seconds, 3600)
    minutes, secs = divmod(rem, 60)
    if hours:
        return "{}h {}m {}s".format(hours, minutes, secs)
    if minutes:
        return "{}m {}s".format(minutes, secs)
    return "{}s".format(secs)


def blackout_banner(window, resume_at, wake_seconds, policy_file="docs/blackout"):
    """The multi-line terminal banner shown when the coordinator holds a NEW
    session for the declared blackout window (WI-261). Pure: names the policy
    file, the raw `HH:MM-HH:MM` UTC `window`, its weekday-only scope, the resume
    time (`resume_at`, a naive UTC datetime), and how long the wait is
    (`wake_seconds`), so an unattended launch reads as deliberately WAITING, not
    hung. Returns the banner as one string (no trailing newline)."""
    bar = "=" * 70
    return "\n".join(
        [
            bar,
            "agent_loop: BLACKOUT — holding; no new session starts yet.",
            "  policy file : {}".format(policy_file),
            "  window      : {} UTC  (starts on weekdays, Mon–Fri)".format(
                (window or "").strip()
            ),
            "  resuming at : {} UTC  (in ~{})".format(
                resume_at.strftime("%H:%M"), _fmt_hms(wake_seconds)
            ),
            "  honored by  : the agent-resume -> agent_loop path (waits in place)",
            "The loop is WAITING, not hung; it resumes automatically.",
            bar,
        ]
    )


def blackout_countdown_line(remaining_seconds, resume_at):
    """One countdown-heartbeat line emitted every BLACKOUT_HEARTBEAT_SEC while
    waiting out a blackout, so an unattended launch visibly ticks down rather
    than looking hung (WI-261). Pure: names the remaining wait and the UTC resume
    time (`resume_at`, a naive UTC datetime)."""
    return "agent_loop: blackout — ~{} remaining, resuming {} UTC.".format(
        _fmt_hms(remaining_seconds), resume_at.strftime("%H:%M")
    )


def blackout_wait(
    wake_seconds, window, resume_at, emit, sleep, interval=BLACKOUT_HEARTBEAT_SEC
):
    """Emit the blackout banner, then wait `wake_seconds` in `interval`-second
    steps, emitting a countdown heartbeat after each step (never a redundant one
    at zero, where the loop resumes). `emit(line)` prints a line and
    `sleep(secs)` waits — both injected so the feedback is deterministic under
    test with a captured `emit` and a no-op `sleep` (no real multi-second delay).
    The WAIT itself is unchanged: the total time slept is exactly `wake_seconds`
    (an interval <= 0 degenerates to a single full-length sleep, never a spin)."""
    emit(blackout_banner(window, resume_at, wake_seconds))
    remaining = int(wake_seconds)
    while remaining > 0:
        step = interval if 0 < interval < remaining else remaining
        sleep(step)
        remaining -= step
        if remaining > 0:
            emit(blackout_countdown_line(remaining, resume_at))


# --- WI-181: explicit worker assignment (LLR-061) --------------------------------
# A worker is one agent_loop process driving one claimed assignment on one
# branch in one worktree (the §2.3 claim model since concurrency-restructure
# Phase 5). Its inputs are explicit CLI arguments (never a lane file) and its
# result is committed evidence read back through git trailers.


WI_TOKEN_RE = re.compile(r"^WI-\d+$")

# (SANCTIONED_TRAIN_SUBJECT_PREFIXES and the WI-282 commit-msg trailer floor
# retired with the dispatcher at concurrency-restructure Phase 5.)

# The terminal work-item Statuses — no further build is owed (WI-267; the
# won't-build half respelled `cancelled` and given its own folder by WI-384).
# Mirrors check_trajectory.TERMINAL_STATUSES, kept inline here rather than
# imported: the F5 self-contained-script rule keeps agent_common stdlib-only (it
# never pulls a sibling engine). A worker must never build a WI in either state.
# SR-144 adds `partial`: a worker must refuse an assignment whose spec has
# already closed early exactly as it refuses one that shipped or was cancelled.
# The 2026-09-02 restructure plan §1.6 adds `restructured` — a row absorbed into
# a successor. A worker must refuse it for the same reason and more plainly: the
# scope it names is being built under another id.
TERMINAL_STATUSES = ("done", "cancelled", "partial", "restructured")


def sanitize_train(name):
    """A session tag becomes a log-file prefix and a reviews/ subdirectory,
    so restrict it to a safe slug (alnum + `.`/`-`/`_`, starts alphanumeric)
    — `--train` can then never traverse the tree. Returns the name or raises
    ValueError (preflight surfaces the message)."""
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", name or ""):
        raise ValueError(
            "session tag {!r} must be a slug matching [A-Za-z0-9][A-Za-z0-9._-]* "
            "(starts alphanumeric; no path separators)".format(name)
        )
    return name


def parse_wi_id(value, source):
    """The one work-item id a lane's input names: the worker's assignment and
    the claim's work item both read it here. A lane claims and builds exactly
    one work item, so anything but a str that is exactly one WI-### token
    (empty, separator-only, a list in any separator, a list or tuple of any
    length, a repeated id, a malformed token) raises ValueError naming
    `source` (the input's name in its caller's words) and the value's repr; a
    broken input must refuse before any state changes, never half-run. A
    command line normalizes its own argument (case, outer whitespace) at its
    boundary before calling.

    Implements: SR-026, LLR-061
    """
    if isinstance(value, str) and WI_TOKEN_RE.fullmatch(value):
        return value
    why = "{} takes exactly one WI-### id; got {!r} (a lane takes one work item)"
    raise ValueError(why.format(source, value))


# --- the spec-folder registry reader: ONE home since WI-448 -------------------
# `docs/work/<status>/WI-###-<slug>.md` — one Markdown spec per work item, its
# STATUS encoded as the DIRECTORY (docs/concurrency-restructure.md §2.1). The
# 270-line reader that used to sit here VERBATIM, and identically in the other
# two of schedule.py, check_trajectory.py and agent_common.py, now lives once in
# `kitlib/registry.py`: owner ruling D-8 (`OI-16`, inversion confirmed
# 2026-08-13) retired the F5 no-shared-module rule that had licensed the copies.
#
# RE-EXPORTED under the names this module has always carried, so no call site
# and no test that reads `agent_common.<name>` changes with the move. The names are
# listed one per line rather than star-imported because this module's public
# surface is a fact its readers check, not a wildcard.
WI_COLUMNS = _kitregistry.WI_COLUMNS
SPEC_SCALARS = _kitregistry.SPEC_SCALARS
SPEC_LISTS = _kitregistry.SPEC_LISTS
SPEC_STATUS_DIRS = _kitregistry.SPEC_STATUS_DIRS
SPEC_FENCE = _kitregistry.SPEC_FENCE
SPEC_DELIVERABLE = _kitregistry.SPEC_DELIVERABLE
SPEC_HANDBACK = _kitregistry.SPEC_HANDBACK
SPEC_CONTEXT = _kitregistry.SPEC_CONTEXT
spec_work_dir = _kitregistry.spec_work_dir
spec_files = _kitregistry.spec_files
parse_spec_frontmatter = _kitregistry.parse_spec_frontmatter
parse_spec_status = _kitregistry.parse_spec_status
parse_spec_id = _kitregistry.parse_spec_id
parse_spec_deliverable = _kitregistry.parse_spec_deliverable
parse_spec_row = _kitregistry.parse_spec_row
read_spec_rows = _kitregistry.read_spec_rows


def load_registry_rows(root):
    """The work-item rows from the one registry home, `docs/work/` (the spec
    folder; status = directory). The CSV home retired at concurrency-
    restructure Phase 5 (RULING-4: no CSV in any form); an absent folder reads
    as an empty registry, the non-adopter posture."""
    work_dir = spec_work_dir(Path(root) / "docs" / "requirements" / "work-items.csv")
    return read_spec_rows(work_dir) if work_dir.is_dir() else []


def load_wi_registry(root):
    """{WI-ID: raw row dict} from the worktree's tracked WI registry — the
    checked-out copy on the train branch, so a worker reads the same registry
    state its base commit fixed. Malformed/duplicate ids are skipped (the
    validator's finding, not the worker's crash). Reads whichever home is
    authoritative via `load_registry_rows`; the rows are the same 18 keys either
    way, so every caller of this map is unaffected by the migration."""
    rows = load_registry_rows(root)
    out = {}
    for r in rows:
        wid = (r.get("WI-ID") or "").strip()
        if WI_TOKEN_RE.match(wid) and wid not in out:
            out[wid] = r
    return out


# The trailer-evidence log format (shared by the worker- and dispatcher-side
# readers). The leading "T" sentinel keeps the first field intact through
# git()'s stdout .strip() — a commit whose WI field is empty would otherwise
# lose its leading tab and shift every field left.
TRAILER_EVIDENCE_FMT = (
    "T%x09"
    "%(trailers:key=WI,valueonly,separator=;)%x09"
    "%(trailers:key=Blocked-WI,valueonly,separator=;)%x09"
    "%(trailers:key=BlockRef,valueonly,separator=;)"
)


def latest_trailer_evidence(log_out):
    """Fold a newest-first trailer log (TRAILER_EVIDENCE_FMT) into
    (built:set, blocked:map) where each WI is claimed by its LATEST trailer
    ONLY — the two buckets are disjoint. A newer `WI:` completion supersedes an
    older `Blocked-WI:` for the same id (a CURED blocker), and a newer
    `Blocked-WI:` supersedes an older `WI:` (the block is newer truth). `git
    log` emits newest-first, so the FIRST commit that names a WI (in either
    trailer) fixes its verdict; within one commit a completion wins. `blocked`
    maps a still-blocked WI to its committed BlockRef ('' when omitted)."""
    built, blocked, seen = set(), {}, set()
    for line in log_out.splitlines():
        parts = (line.split("\t")[1:] + ["", "", ""])[:3]
        for tok in (x.strip() for x in parts[0].split(";")):
            if WI_TOKEN_RE.match(tok) and tok not in seen:
                seen.add(tok)
                built.add(tok)
        refs = [t.strip() for t in parts[2].split(";")]
        for j, tok in enumerate(t.strip() for t in parts[1].split(";")):
            if WI_TOKEN_RE.match(tok) and tok not in seen:
                seen.add(tok)
                blocked[tok] = refs[j] if j < len(refs) else ""
    return built, blocked


def train_evidence(root, base):
    """(built, blocked) read from the train branch's committed trailers in
    base..HEAD: `built` is the set of WI ids whose LATEST trailer is the `WI:`
    completion; `blocked` maps a still-blocked `Blocked-WI:` id to its
    `BlockRef:` value (empty string when the commit omitted one). Per WI the
    newest trailer wins, so a resumed worker whose gate now passes supersedes
    its own earlier block by committing `WI:` (WI-239). This is the worker's
    one result channel — recovery reconstructs the same facts from git alone."""
    code, out = git(
        root, "log", "--format=" + TRAILER_EVIDENCE_FMT, "{}..HEAD".format(base)
    )
    if code != 0:
        return set(), {}
    return latest_trailer_evidence(out)


def _clip(text, limit):
    """Bound a prompt block: head lines up to `limit`, with an elision marker."""
    lines = (text or "").splitlines()
    if len(lines) <= limit:
        return "\n".join(lines)
    return "\n".join(lines[:limit] + ["… ({} more lines)".format(len(lines) - limit)])


# The per-worktree coordinator lock is a kernel ADVISORY lock (fcntl.flock on
# POSIX, msvcrt.locking on Windows) held on out/agent-loop.lock for this
# process's lifetime. The OS releases it automatically when the process exits —
# INCLUDING a crash or SIGKILL — so there is no stale-pid file to reason about
# and no PID-reuse hazard: the freed lock is simply available to the next run.
# The pid/host/stamp written into the file are human-readable DIAGNOSTICS only,
# never the liveness signal. The held descriptor lives in a module global so it
# (and thus the lock) stays open until release_lock / process exit.
_LOCK_FD = None


def _host():
    """This machine's name, for the lock file's human-readable diagnostics."""
    try:
        return socket.gethostname()
    except OSError:
        return ""


# On Windows the CRT lock is MANDATORY — it blocks other processes from reading
# the locked bytes — so we lock a single byte far beyond any real content. The
# human-readable diagnostics in bytes 0..N stay readable (e.g. git staging this
# file if a repo forgot to gitignore out/), while two coordinators still contend
# on the same byte range. POSIX flock is advisory and whole-descriptor, so it
# needs no offset games.
_WIN_LOCK_OFFSET = 1 << 40


def _take_os_lock(fd):
    """Take a non-blocking exclusive advisory lock on `fd`, raising OSError when
    another process already holds it. Platform-split, stdlib only."""
    if os.name == "nt":
        import msvcrt

        os.lseek(fd, _WIN_LOCK_OFFSET, os.SEEK_SET)
        try:
            msvcrt.locking(fd, msvcrt.LK_NBLCK, 1)
        finally:
            os.lseek(fd, 0, os.SEEK_SET)
    else:
        import fcntl

        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)


# Errnos that mean "this filesystem cannot do advisory locks" (a network / exotic
# mount — flock returns these) as opposed to "the lock is held" (EWOULDBLOCK /
# EAGAIN / EACCES). On these we degrade to a warning instead of failing closed;
# every other error stays a refusal, so an unknown failure never silently drops
# the guard (fail-safe). Built via getattr so a name absent on a platform is just
# skipped.
_UNSUPPORTED_LOCK_ERRNOS = frozenset(
    getattr(errno, name)
    for name in ("ENOLCK", "ENOSYS", "EOPNOTSUPP", "ENOTSUP")
    if hasattr(errno, name)
)


def _read_holder(lock_path):
    """The holder's diagnostic line (pid host stamp) for an error message, or ''
    — best-effort; a mandatory Windows lock may block the read, which is fine."""
    try:
        return lock_path.read_text(encoding="utf-8").strip().replace("\n", " ")
    except OSError:
        return ""


def dispatch_lock_path(root):
    """The DISPATCH lock's one home: ``out/agent-loop.lock`` under `root`.

    The per-checkout coordinator lock the plain-launch dispatcher holds for its
    process lifetime (agent_loop `_coordinator_lock`) — and, since WI-381
    (concurrency-v2 §A4.1), the lock `integrate claim` REQUIRES: admission is
    the dispatcher's scheduling decision, so a hand claim while a dispatcher's
    lanes are live is unrepresentable (the lock cannot be taken), while a hand
    claim on an idle station still works. One path builder, because the holder
    and the requirer must name the same file by construction."""
    return Path(root) / "out" / "agent-loop.lock"


def _open_lock_fd(lock_path):
    """Open the lock file and try the kernel advisory lock, non-blocking:
    `(fd, None)` when locked, `(fd, exc)` when NOT — with the descriptor left
    OPEN either way, because the two callers disagree about what a failure
    keeps: `acquire_lock`'s degraded-filesystem arm writes diagnostics through
    it, while integrate.py's dispatch-lock rung (WI-381) closes it and
    refuses. One home for the open flags (O_BINARY keeps the diagnostic
    newlines untranslated on Windows)."""
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    flags = os.O_RDWR | os.O_CREAT
    if hasattr(os, "O_BINARY"):
        flags |= os.O_BINARY
    fd = os.open(str(lock_path), flags, 0o644)
    try:
        _take_os_lock(fd)
    except OSError as exc:
        return fd, exc
    return fd, None


def acquire_lock(lock_path):
    """Take the per-worktree coordinator lock, or return an error string.

    Prevents two coordinators grinding the same checkout — a double-launch or a
    cron overlap — the one collision the branch guard can't catch (both would
    sit on the same llm/<track> branch in one worktree). The lock is a kernel
    advisory lock the OS grants atomically and releases on exit *or crash*, so a
    dead run never wedges the next one (no pid reasoning, no timer). Cross-host
    on a shared filesystem is best-effort only: flock over NFS is unreliable, so
    this guards one checkout on one host — the common and important case. A
    filesystem that cannot lock at all (ENOLCK/ENOTSUP) degrades to a warning and
    runs unguarded rather than fail-closed on a legitimate run.

    Implements: SR-027, LLR-029, LLR-030
    """
    global _LOCK_FD
    fd, exc = _open_lock_fd(lock_path)
    if exc is not None:
        if os.name != "nt" and exc.errno in _UNSUPPORTED_LOCK_ERRNOS:
            # This filesystem cannot do advisory locks (a network / exotic mount).
            # Degrade to a warning and proceed WITHOUT the guard rather than block
            # a legitimate run: the single-checkout guarantee is only lost on a
            # mount that never supported it, and the branch guard + git history
            # still backstop. Keep fd open (diagnostics written below) so the file
            # still records who is here.
            print(
                "agent_loop: WARNING - {} is on a filesystem that does not "
                "support advisory locks (errno {}); running WITHOUT the "
                "one-coordinator-per-checkout guard.".format(lock_path, exc.errno),
                file=sys.stderr,
            )
        else:
            os.close(fd)
            return (
                "another coordinator holds {} — refusing to run two in one "
                "worktree (held by: {}). It clears itself when that run exits; "
                "wait for it, or delete the file only if you are sure that run "
                "is gone.".format(lock_path, _read_holder(lock_path) or "unknown")
            )
    # We hold the lock: overwrite the diagnostics (a crashed predecessor may have
    # left its own). Best-effort — the OS lock, not this content, is the guard.
    try:
        os.ftruncate(fd, 0)
        os.write(
            fd,
            "{}\n{}\n{}\n".format(
                os.getpid(), _host(), time.strftime("%Y-%m-%d %H:%M:%S")
            ).encode("utf-8"),
        )
    except OSError:
        pass
    _LOCK_FD = fd
    return None


def release_lock(lock_path=None):
    """Drop the coordinator lock: closing the descriptor releases the OS lock.
    Idempotent, and a no-op if we never held it; the OS would release on exit
    regardless (the crash path relies on exactly that). `lock_path` is accepted
    for the atexit call signature but unused — the held descriptor is the
    authority, so a reclaimed-then-exited predecessor never disturbs a successor."""
    global _LOCK_FD
    if _LOCK_FD is not None:
        try:
            os.close(_LOCK_FD)
        except OSError:
            pass
        _LOCK_FD = None


def parse_map(spec):
    """Parse a KEY=value phase map — shared by --model-map/--cmd-map/--prompt-map/
    --tier-map/--prefer-map: "P0=model-a,strong=model-b" -> {"P0": "model-a",
    "strong": "model-b"}."""
    mapping = {}
    for pair in (spec or "").replace(";", ",").split(","):
        pair = pair.strip()
        if not pair:
            continue
        if "=" not in pair:
            raise ValueError("--model-map entry without '=': {}".format(pair))
        phase, _, model = pair.partition("=")
        mapping[phase.strip()] = model.strip()
    return mapping


_SPLIT_RE = re.compile(r"[;,\s]+")


def _read_csv_rows(path):
    """CSV rows of `path` as dicts, or [] (absent/unreadable). utf-8-sig so an
    Excel-written BOM can't rename the first header key (a BOM'd
    work-items.csv split the dispatcher's and the worker's view of the same
    registry, and a BOM'd system-requirements.csv silently vacated the
    critique gate — repo-review 2026-07-21 M-23); errors=replace so a stray
    byte degrades, never crashes (the declared-reader idiom). A real file
    handle (newline="") also keeps quoted multi-line cells parseable, unlike
    the old splitlines() feed."""
    try:
        text = Path(path).read_text(encoding="utf-8-sig", errors="replace")
    except OSError:
        return []
    return _kitspine.csv_rows(text)


def _refs(cell):
    return [t for t in _SPLIT_RE.split((cell or "").strip()) if t]


def git(root, *args):
    """Run git in the repo; returns (returncode, text).

    On success `text` is stdout-stripped and byte-identical to the raw call —
    every success-path caller parses stdout (`rev-parse`, `status --porcelain`,
    trailer reads). But git reports hook rejections and fatal errors on STDERR,
    so on a NONZERO exit the stripped stderr is appended to stdout (newline-joined
    when both are non-empty); otherwise every failure detail a failed call feeds
    a park/quarantine reason (via `_failure_tail`) would be blank (WI-233)."""
    proc = subprocess.run(
        ["git", "-C", str(root)] + list(args),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        stdin=subprocess.DEVNULL,
    )
    out = (proc.stdout or "").strip()
    if proc.returncode != 0:
        err = (proc.stderr or "").strip()
        if err:
            out = out + "\n" + err if out else err
    return proc.returncode, out


# WI-240 -> WI-398: the harness/hook banner shape a structured failure prints —
# a `=== <step> : <cmd> ===` banner per step, then that step's output, then a
# `  {STATUS}  <step>  <detail>` line — PLUS check.py's closing summary block,
# which re-prints every step's status after a bare `====...` rule at any --jobs.
_FAILTAIL_FAIL_RE = re.compile(r"^\s*FAIL\s")
_FAILTAIL_BANNER_RE = re.compile(r"^\s*=== ")
_FAILTAIL_RULE_RE = re.compile(r"^\s*={8,}\s*$")


def _failure_tail(out, budget=600):
    """The FAILING part of a harness/git output, bounded to `budget` chars.

    Park/quarantine/journal details once kept only the leading 200 chars — the
    HEAD — so a multi-step hook failure journaled the FIRST (passing) banner and
    cut the actual error (the WI-229 blocked-disposition loop). WI-240's answer
    — the LAST `  FAIL  <step>` line, walked back to the nearest banner — broke
    on a full check.py run: the closing summary RE-prints every step's status,
    so the last FAIL was always the summary copy, the nearest banner above it
    the LAST step's, and the extracted window was summary rows — the failing
    step's own output structurally never reached a refusal, at any --jobs
    (WI-398; the WI-387 refresh red cost three lost diagnoses of one failure).

    Now the FIRST `  FAIL  <step>` line names the failing step, and the window
    is that step's OWN `=== <step> :` banner down to the next banner or the
    summary rule, with the anchoring FAIL line appended when it sits outside
    the window (the --jobs 1 shape, where statuses print only in the summary).
    No banner names the step -> the nearest banner above that FAIL line; no
    FAIL marker at all -> the TAIL of the output; always tail-bounded, so the
    error survives even when the window is long."""
    text = (out or "").rstrip()
    if not text:
        return ""
    lines = text.splitlines()
    fail_idx = next(
        (i for i, ln in enumerate(lines) if _FAILTAIL_FAIL_RE.match(ln)), None
    )
    if fail_idx is None:
        return text[-budget:].lstrip()
    block = _own_step_window(lines, fail_idx)
    if block is None:
        # No banner names the step (a bare git/tool failure): the WI-240
        # window, anchored on the FIRST FAIL rather than the summary's copy.
        start = 0
        for j in range(fail_idx - 1, -1, -1):
            if _FAILTAIL_BANNER_RE.match(lines[j]):
                start = j
                break
        block = lines[start : fail_idx + 1]
    return "\n".join(block)[-budget:].lstrip()


def _own_step_window(lines, fail_idx):
    """The failing step's OWN banner-to-end block, or None (`_failure_tail`).

    `lines[fail_idx]` is a `  FAIL  <step>  <detail>` line; the window is the
    first `=== <step> : ` banner (startswith, not an interpolated regex — step
    names carry regex metacharacters, "tests+coverage") down to the next banner
    or the summary rule, with the anchoring FAIL line appended when it sits
    outside the window (the --jobs 1 shape). None when the line carries no step
    name or no banner names it, so the caller keeps its bounded fallback.

    Known limit (WI-398 REVIEW-A finding 1, pinned by WI-405): both anchors
    trust line SHAPE, so bar-shaped text EMBEDDED in a step's own captured
    output — a quoted FAIL row, a quoted banner, a nested scaffold bar naming
    another step — can silently misanchor the window onto a passing step's
    text; deliberately not parsed away (WI-398's scope guard), and on the
    refresh path the kept full log (out/run-logs/refresh-refused-<branch>.log)
    is the authority."""
    parts = lines[fail_idx].split()
    if len(parts) < 2:
        return None
    marker = "=== {} : ".format(parts[1])
    start = next(
        (j for j, ln in enumerate(lines) if ln.lstrip().startswith(marker)), None
    )
    if start is None:
        return None
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if _FAILTAIL_BANNER_RE.match(lines[j]) or _FAILTAIL_RULE_RE.match(lines[j]):
            end = j
            break
    block = lines[start:end]
    if not start <= fail_idx < end:
        block = block + [lines[fail_idx]]
    return block


def head_sha(root):
    """Short HEAD sha, or None on a zero-commit repo (guarded rev-parse)."""
    code, out = git(root, "rev-parse", "--short", "HEAD")
    return out if code == 0 and out else None


class TrunkUndeclared(ValueError):
    """The trunk's declaration cannot be read as one local branch's name: THE
    refusal every trunk reader raises or reports, its `str` the message each
    caller prints. It names the line and what to write there."""


_TRUNK_KEY = "docs/process.toml [policies] trunk"


def _trunk_refusal(shape):
    return TrunkUndeclared(
        "{} {}: declare the integration branch by name, one line under "
        '[policies]: trunk = "<your integration branch>"'.format(_TRUNK_KEY, shape)
    )


def trunk_name(root):
    """The integration trunk's NAME: the branch `docs/process.toml [policies]
    trunk` declares, in any worktree, or `TrunkUndeclared`. Absent (a file that
    does not parse included), not a string, empty, or naming no
    `refs/heads/<name>`, each is refused, naming the line to add; nothing is
    guessed from the branch a checkout is on.

    HERE RATHER THAN IN `agent_loop` because two readers need it and they must
    not disagree: the loop composes the review brief and picks a worker's
    integration base with it, and the worker PREFLIGHT below asks the same
    question to tell a row THIS branch closed from one that was terminal before
    the lane began.

    Implements: SR-156, LLR-339
    """
    policies = agent_policy.process_config(Path(root) / "docs").get("policies")
    name = policies.get("trunk") if isinstance(policies, dict) else None
    if name is None:
        raise _trunk_refusal("is absent")
    if not isinstance(name, str):
        raise _trunk_refusal("is not a string ({!r})".format(name))
    if not name.strip():
        raise _trunk_refusal("is empty")
    code, _out = git(root, "rev-parse", "--verify", "--quiet", "refs/heads/" + name)
    if code != 0:
        raise _trunk_refusal("names {!r}, which is no local branch".format(name))
    return name


def claim_subject(wi_id, branch):
    """The one commit-subject grammar for a claim's durable Git record: one
    work item per lane, so one id. A list is a caller error and raises
    TypeError rather than writing a joined subject no writer may compose."""
    if not isinstance(wi_id, str):
        raise TypeError("claim_subject takes one work item id; got {!r}".format(wi_id))
    return "claim: {} -> active/{} (bookkeeping)".format(wi_id, branch)


def name_status(out):
    """Parse no-renames Git name-status output for claim/integration readers.

    Each record is status + tab + path; normalize paths once so callers cannot
    disagree about the same committed delta.
    """
    for line in out.splitlines():
        parts = line.strip().split("\t")
        if len(parts) < 2:
            continue
        yield parts[0], parts[-1].replace("\\", "/")


def _is_claim_move(root, commit, branch, wi_ids):
    """Whether `commit` carries every queued-to-active move its subject names.

    Returns None when its committed delta cannot be read, so a caller can
    refuse rather than treating an unreadable claim as a manual assignment.
    """
    flags = ("--root", "--no-commit-id", "-r", "--name-status", "--no-renames")
    code, delta = git(root, "diff-tree", *flags, commit)
    if code != 0:
        return None
    active = {wi: "docs/work/active/{}/{}-".format(branch, wi) for wi in wi_ids}
    queued = {wi: "docs/work/queued/{}-".format(wi) for wi in wi_ids}
    added, removed = set(), set()
    for status, path in name_status(delta):
        for wi, prefix in active.items():
            if status.startswith("A") and path.startswith(prefix):
                added.add(wi)
        for wi, prefix in queued.items():
            if status.startswith("D") and path.startswith(prefix):
                removed.add(wi)
    return added == set(wi_ids) and removed == set(wi_ids)


def claim_base(root, branch=None):
    """`branch`'s claim commit (default: the current branch's), if its
    committed claim record is readable.  `integrate.claim` writes the exact
    subject below before it cuts the branch, so its first-parent history keeps
    the integration boundary even when the checkout later becomes that branch
    itself, and a trunk refresh merged into the lane leaves it an ancestor on
    that first-parent line.  It is THE claim base the merge gate binds a
    full-lane review to (WI-884), read from trunk by branch name.

    Returns ``(base, readable)``.  `base is None` means this is a manual or
    pre-claim worker.  `readable is False` means Git could name the branch but could
    not read its history; that is deliberately distinct so the caller does not
    silently turn an unreadable claim into an empty HEAD..HEAD evidence range.

    A reader of history, so it does not compose through the one-id writer: a
    subject `claim: <ids> -> active/<branch> (bookkeeping)` whose `;`-split
    ids are all WI tokens is a claim, so the historical joined subjects of the
    multi-item claims made before one work item per lane still read as one.
    """
    if branch is None:
        code, out = git(root, "branch", "--show-current")
        branch = out.strip() if code == 0 else ""
    if not branch:
        return None, True
    prefix, suffix = "claim: ", " -> active/{} (bookkeeping)".format(branch)
    grep = ("--first-parent", "--fixed-strings", "--grep=" + suffix)
    code, history = git(root, "log", *grep, "--format=%H%x09%s", branch, "--")
    if code != 0:
        return None, False
    for line in history.splitlines():
        # `%H<TAB>%s`: a line with no tab leaves an empty subject, which is
        # not claim-shaped, so the one test below rules on it too.
        sha, _sep, subject = line.partition("\t")
        shaped = subject.startswith(prefix) and subject.endswith(suffix)
        wi_ids = subject[len(prefix) : len(subject) - len(suffix)].split(";")
        if not shaped or not all(WI_TOKEN_RE.fullmatch(wi) for wi in wi_ids):
            continue
        valid_move = _is_claim_move(root, sha, branch, wi_ids)
        if valid_move is None:
            return None, False
        if valid_move:
            return sha, True
    return None, True


_CLAIM_SHA_RE = re.compile(r"[0-9a-f]{40}(?:[0-9a-f]{24})?")


def loop_claimed(root, branch, trunk_tip):
    """Did the LOOP claim `branch`? `(claimed, unreadable)`.

    Claimed when the claim commit on `trunk_tip`'s first-parent line - the
    newest whose subject is the claim grammar for this branch - carries a
    well-formed `Loop-Session` trailer, which the claim writes under the loop
    marker and never otherwise (SR-209): `(True, None)`. No such claim, or a
    newest claim with no trailer or a malformed one: `(False, None)`.

    A claim log git cannot read, or a record in it with no commit id, is
    UNREADABLE, never unclaimed: `(None, why)`, where `why` names the read.
    It is the one reader of a lane's claim, and every caller refuses on an
    unreadable answer.

    Implements: SR-209, LLR-248
    """
    suffix = " -> active/{} (bookkeeping)".format(branch)
    grep = ("--first-parent", "--fixed-strings", "--grep=" + suffix)
    args = ("log", *grep, "--format=%H%x00%B%x1e", trunk_tip)
    code, out = git(root, *args)
    if code != 0:
        detail = out.strip().splitlines()
        return None, "git {} failed (exit {}){}".format(
            " ".join(args), code, ": " + detail[0] if detail else ""
        )
    for record in out.split("\x1e"):
        record = record.lstrip("\r\n")
        if not record.strip():
            continue
        sha, nul, message = record.partition("\x00")
        if not nul or not _CLAIM_SHA_RE.fullmatch(sha):
            return None, "unparseable record {!r} from git {}".format(
                record[:60], " ".join(args)
            )
        subject = (message.strip().splitlines() or [""])[0]
        if subject.startswith("claim: ") and subject.endswith(suffix):
            return _kitprovenance.parse_loop_trailer(message) is not None, None
    return False, None


def default_base(root):
    """The integration base a worker assumes when --base is not given: the
    merge base of HEAD with the declared trunk, in a single checkout as in a
    linked worktree. The `base..HEAD` evidence readers walk without
    --first-parent, so after the lane merges trunk in only that boundary keeps
    trunk's own commits, and their `WI:` trailers, out of this lane's evidence.
    With no merge base (an unrelated history) it is HEAD, None only on an
    unborn HEAD; an undeclared trunk raises `TrunkUndeclared`.

    Implements: SR-156, LLR-339
    """
    trunk = trunk_name(root)
    code, out = git(root, "merge-base", trunk, "HEAD")
    if code == 0 and out.strip():
        return out.strip()
    return head_sha(root)


def worker_base(root, given=None):
    """`(base, None)`: the integration base a worker builds from, `given` (its
    --base) when non-blank, else `default_base`; or `(None, why)` when there is
    none, an undeclared trunk's refusal or an unborn HEAD named in `why`.

    Implements: SR-156, LLR-339
    """
    try:
        base = (given or "").strip() or default_base(root)
    except TrunkUndeclared as exc:
        return None, str(exc)
    if not base:
        return None, (
            "no resolvable --base (no HEAD commit) — a worker builds from an "
            "integration base; commit first."
        )
    return base, None


def working_tree_dirty(root):
    """The `git status --porcelain` lines — one per uncommitted path (a rename is
    a single 'R  old -> new' entry, an untracked file a single '?? path' entry),
    or [] on a clean tree or a non-repo. Read through git() (text,
    errors=replace) so an odd byte in a path degrades rather than crashes (the
    sibling encoding-safe idiom). Used once at loop start to surface
    interrupted-session residue (WI-076)."""
    code, out = git(root, "status", "--porcelain")
    if code != 0:
        return []
    return [ln for ln in out.splitlines() if ln.strip()]


def _porcelain_path(line):
    """The repo-relative path a `git status --porcelain` line names — the
    destination side of a rename/copy (`R  old -> new`), surrounding quotes
    stripped — used to match a dirty line against OWNER_ONLY_PATHS. Splits the
    XY status token off the front rather than assuming a fixed column width (a
    leading blank status column may or may not survive to here)."""
    body = line.strip()
    if " -> " in body:
        return body.split(" -> ", 1)[1].strip().strip('"')
    parts = body.split(None, 1)  # status token, then the path
    return (parts[1] if len(parts) == 2 else body).strip().strip('"')


def substantive_working_tree_dirty(root):
    """`working_tree_dirty` minus the FB3 owner-only paths (OWNER_ONLY_PATHS) —
    the view the loop's WI-076 resume note (loop start) and done detection use,
    so a tree whose ONLY changes are the owner scratchpad (perpetually edited,
    never the loop's or a worker's deliverable) reads clean and the interrupted-
    residue signal fires only on genuine residue. The raw primitive stays
    available for a caller that wants every uncommitted path (WI-203)."""
    return [
        ln
        for ln in working_tree_dirty(root)
        if _porcelain_path(ln) not in OWNER_ONLY_PATHS
    ]


def current_state_excerpt(status_path, max_lines=40):
    """The '## Current State' section of a status.md — the root dispatcher's or
    a track lane's own — the pending asks a stopping coordinator must surface in
    its exit banner."""
    try:
        lines = status_path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return "({} not found — no asks to surface)".format(status_path)
    section, collecting = [], False
    for ln in lines:
        if ln.startswith("## "):
            if collecting:
                break
            collecting = ln.strip().lower().startswith("## current state")
            continue
        if collecting:
            section.append(ln)
    if not section:
        return "({} has no '## Current State' section)".format(status_path)
    section = [ln for ln in section if ln.strip()][:max_lines]
    return "\n".join(section)


def bounded_transcript(output):
    """Head + capped tail of a session transcript (the tracked-log bound)."""
    lines = output.splitlines()
    if len(lines) > LOG_HEAD_LINES + LOG_TAIL_LINES:
        elided = len(lines) - LOG_HEAD_LINES - LOG_TAIL_LINES
        lines = (
            lines[:LOG_HEAD_LINES]
            + [
                "",
                "[... {} line(s) elided — full stream in out/run-logs/ ...]".format(
                    elided
                ),
                "",
            ]
            + lines[-LOG_TAIL_LINES:]
        )
    text = "\n".join(lines)
    encoded = text.encode("utf-8", "replace")
    if len(encoded) > LOG_MAX_BYTES:
        keep = LOG_MAX_BYTES // 2
        text = (
            encoded[:keep].decode("utf-8", "ignore")
            + "\n[... byte cap hit — full stream in out/run-logs/ ...]\n"
            + encoded[-keep:].decode("utf-8", "ignore")
        )
    return text


# THE CREDENTIAL CLASS VOCABULARY'S ONE HOME (WI-520). Derived from
# `kitlib.secret_classes.SECRET_CLASSES` — the same table
# `check_privacy.py`'s enforcement floor reads — so a class this redactor
# claims can no longer silently diverge from what the floor scans for. This
# closes the measured gap: a PEM private-key block used to reach this tuple
# as an "unknown token shape" (this function's own licensed gap, below) when
# it is in fact a known, compiled class one sibling module over; it is now
# `private key header`'s entry in the shared table, redacted here like every
# other declared class.
_SECRET_RES = tuple(
    cls.redact_pattern
    for cls in _kitsecrets.SECRET_CLASSES
    if cls.redact_pattern is not None
)


def redact_secrets(text):
    """Best-effort redaction of well-known credential shapes, applied before a
    transcript is committed to tracked history (docs/iteration/*.log): a CLI
    auth error echoing a key otherwise lands in permanent history with only
    push-policy between it and publication (repo-review 2026-07-21 M-19).
    The shapes are `kitlib.secret_classes`' redact-side classes (WI-520).
    Deliberately imperfect — unknown token shapes pass through, and the raw
    unredacted stream stays in gitignored out/run-logs/ for debugging."""
    hits = 0
    for rx in _SECRET_RES:
        text, n = rx.subn("[REDACTED]", text)
        hits += n
    return text, hits


def prompt_fingerprint(text):
    """A short, stable fingerprint of a rendered prompt — `sha256:` + 12 hex.

    Identification, not authentication: it answers "did these two sessions see
    the same instruction?" and "did the template change between these rows?"
    without keeping every rendered prompt on disk. Taken over the text as
    launched, so a slot fill that changed the prompt shows even when the
    template did not."""
    if text is None:
        return ""
    digest = hashlib.sha256(text.encode("utf-8", "replace")).hexdigest()
    return "sha256:" + digest[:12]


def write_session_log(iter_dir, meta, transcript):
    """Write the tracked, size-bounded per-session log: a `# key: value`
    metadata header (what the index is regenerated from) + the transcript
    (credential shapes redacted — see redact_secrets).

    Implements: SR-176, LLR-177, SR-244, LLR-354
    """
    transcript, redacted = redact_secrets(transcript)
    iter_dir.mkdir(parents=True, exist_ok=True)
    header = ["# agent session log — written by scripts/agent_common.py"]
    for key in (
        "session",
        "date",
        "train",
        "base",
        "phase",
        "wi",
        "model",
        "guardrails",
        "outcome",
        "commits",
        # WI-884: a REVIEW session's scope as the loop routed it,
        # `full|narrow <base>..<reviewed sha>` (kitlib.verdict.gating_span):
        # the reviewed range, base and tip.
        "review-scope",
        # WI-958: a red review bar's record, keyed by the build commit it
        # refused (kitlib.verdict.format_red_record); empty on every other log.
        "bar-red",
        "bar-summary",
        "tokens",
        "cost-usd",
        "wall-secs",
        "api-secs",
        "turns",
        "ttft-secs",
        "cache-read",
        "cache-create",
        "effort",
        "fast",
        "prompt-chars",
        # SN-026 (plan §11.7): WHICH TEMPLATE, and WHAT IT RENDERED TO.
        # `prompt-chars` alone answers "how big was it", which is the least
        # interesting question about a prompt. A prompt is now a reviewable
        # FILE (§8's externalization), so the useful telemetry is a pointer to
        # the source and a fingerprint of the result: two sessions that
        # disagree can be compared without keeping every rendered prompt on
        # disk, and a template edit becomes visible as a hash change across
        # otherwise identical rows. Truncated sha256 — this identifies, it does
        # not authenticate, and a full digest per row would dominate the header.
        "prompt-template",
        "prompt-sha",
        # Which deadline ended a TIMEOUT session — "wall" or "idle" (C3), ""
        # for every session that finished on its own. The label makes the two
        # kill classes distinguishable in telemetry without a transcript read.
        "timeout",
        # "relaxed" when a review verdict was drawn same-family under the C5
        # fallback rung (heterogeneity relaxed, recorded, never silent); ""
        # for every other session.
        "heterogeneity",
        "exit-code",
        # The CLI's own session id and the context occupancy of the call's
        # LATEST request over the model's window (session_adapters' context
        # readers) — "" wherever the CLI does not report it. Billed tokens are
        # the usage record below, never this.
        "session-id",
        "context-used",
        "context-window",
        "context-pct",
        # Retention accounting: generation, reset reason and codex compaction
        # with its reported or inferred source; blank where not observed.
        "session-gen",
        "reset-reason",
        # WI-887, an audit record no gate reads: minted fresh or resumed, and
        # the scope a retained session is kept under.
        "session-mode",
        "keep-scope",
        "compacted",
        "compaction-source",
        "invocation-id",
        "attempt-id",
        "source-event",
        "role",
        "provider",
        "tier",
        "roster-row",
        "started-at",
        "ended-at",
        # S8, the usage record (session_adapters.USAGE_KEYS): the OpenTelemetry
        # GenAI usage names at the pinned revision `semconv` names, input
        # counted inclusive of cached input, fresh input derived, the CLI that
        # produced the row, and its raw usage verbatim. The same columns for
        # every CLI; a count it does not report is empty, never 0.
        "cli",
        "semconv",
        "gen_ai.provider.name",
        "gen_ai.request.model",
        "gen_ai.response.model",
        "gen_ai.conversation.id",
        "gen_ai.usage.input_tokens",
        "gen_ai.usage.cache_read.input_tokens",
        "gen_ai.usage.cache_write.input_tokens",
        "gen_ai.usage.output_tokens",
        "gen_ai.usage.reasoning.output_tokens",
        "fresh-input-tokens",
        "raw-usage",
        "usage-scope",
        "usage-source",
        "usage-status",
        # A usage ingest's contribution (usage_ingest.py): the transcript's
        # agent identity, and the messages it counted, as a count, the last
        # one's id (the cursor the next ingest resumes after) and the
        # immutable key of the range; empty on every other log.
        "agent-id",
        "parent-agent-id",
        "spawn-depth",
        "agent-type",
        "message-count",
        "message-cursor",
        "contribution-key",
    ):
        # Header values occupy one physical line, including provider metadata,
        # and pass the same credential redaction the transcript does: a raw
        # usage line can carry the result text.
        value = str(meta.get(key, "")).replace("\r", "\\r").replace("\n", "\\n")
        value, hits = redact_secrets(value)
        redacted += hits
        header.append("# {}: {}".format(key, value).rstrip())
    if redacted:
        header.append("# redacted: {} credential-shaped token(s)".format(redacted))
    header.append("# ---")
    # A worker's log name is prefixed with its train id (WI-181): two parallel
    # workers' committed session logs must never collide at integration.
    name = "{}-{}.log".format(meta["session"], meta["stamp"])
    if meta.get("train"):
        name = "{}-{}".format(meta["train"], name)
    path = iter_dir / name
    path.write_text(
        "\n".join(header) + "\n" + bounded_transcript(transcript) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    return path


def log_meta_text(text):
    """`(meta, terminated)` of one session log's `# key: value` metadata
    header: the fields read up to the `# ---` terminator or the first line
    that is not a header line, and whether the terminator was reached (a log
    whose write was cut short has none). `text` is the log's text or an
    iterable of its lines (an open file is read only as far as its header).
    The one header grammar: `read_log_meta` reads through it.

    Implements: SR-243, LLR-346
    """
    meta = {}
    for line in text.splitlines() if isinstance(text, str) else text:
        if line.startswith("# ---"):
            return meta, True
        if not line.startswith("#"):
            break
        m = re.match(r"#\s*([\w.-]+):\s*(.*)", line)
        if m:
            meta[m.group(1)] = m.group(2).strip()
    return meta, False


def read_log_meta(path):
    """Parse the `# key: value` metadata header of one session log."""
    try:
        with open(str(path), encoding="utf-8", errors="replace") as fh:
            return log_meta_text(fh)[0]
    except OSError:
        return {}


def per_turn_pace(meta):
    """API seconds per turn from a log's header meta — the like-for-like speed
    number across sessions of different lengths (a 100-turn build and a
    25-turn review compare honestly here, not on wall time). Empty when either
    field is absent (pre-WI-119 logs, errored sessions)."""
    try:
        api, turns = float(meta.get("api-secs", "")), float(meta.get("turns", ""))
    except ValueError:
        return ""
    return "{:.1f}".format(api / turns) if turns else ""


def per_turn_context(meta):
    """Average context carried per turn (cache-read tokens / turns, humanized
    to k) — the "how much is it re-reading every step" complexity number the
    per-session totals hide. Empty when the fields are absent."""
    try:
        read, turns = float(meta.get("cache-read", "")), float(meta.get("turns", ""))
    except ValueError:
        return ""
    return "{:.0f}k".format(read / turns / 1000.0) if turns else ""


def regenerate_index(docs_dir):
    """Rebuild docs/iteration_index.md from the docs/iteration/*.log metadata
    headers — generated, never hand-maintained (the kit's standing rule), so
    it survives manual log pruning and answers "which session did this"."""
    iter_dir = docs_dir / "iteration"
    rows = []
    for log in sorted(iter_dir.glob("*.log")):
        meta = read_log_meta(log)
        if not meta.get("session"):
            continue
        rows.append(
            "| {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} | {} "
            "| {} | [{}](iteration/{}) |".format(
                meta.get("session", ""),
                meta.get("date", ""),
                meta.get("phase", "") or "—",
                meta.get("wi", "") or "—",
                meta.get("model", "") or "—",
                meta.get("outcome", ""),
                meta.get("commits", "") or "—",
                meta.get("tokens", "") or "—",
                meta.get("cost-usd", "") or "—",
                meta.get("wall-secs", "") or "—",
                meta.get("api-secs", "") or "—",
                meta.get("turns", "") or "—",
                per_turn_pace(meta) or "—",
                per_turn_context(meta) or "—",
                # WI-535: the adjudicator-retention plan's telemetry-first
                # column — the CLI's own reported context occupancy, "—" on
                # every family/CLI call that doesn't report it yet.
                "{}%".format(meta["context-pct"]) if meta.get("context-pct") else "—",
                log.name,
                log.name,
            )
        )
    text = (
        "# Iteration index\n\n"
        "_Generated by `scripts/agent_common.py` from the `docs/iteration/*.log`\n"
        "metadata headers — regenerated every session, never hand-edited. The\n"
        "collated human-review record is `log.md`; this index is the quick\n"
        '"which session did this" pointer (process-options.md "Unattended\n'
        'operation")._\n\n'
        "| # | Date | Phase | WI | Model | Outcome | Commits | Tokens | Cost USD "
        "| Wall s | API s | Turns | s/turn | Ctx/turn | Ctx % | Log |\n"
        "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n"
        + "\n".join(rows)
        + "\n"
    )
    (docs_dir / "iteration_index.md").write_text(text, encoding="utf-8", newline="\n")


def commit_telemetry(root, session, label, paths, trailer=None):
    """Commit the coordinator's own bookkeeping in its own `telemetry:` commit,
    right after it is written — so it never rides the next session's work commit
    or dangles in the tree (WI-137, the session-021 defect-shape). Stages only
    the named bookkeeping paths (the iteration log + regenerated index, the
    review scoreboard); the reviewer's verdict files commit themselves. Honors
    the hooks and is best-effort: nothing staged, or a hook veto, leaves the
    files in the tree exactly as before — never fatal, so the fix can only help
    (a walk-away run that today dangles telemetry keeps working either way).

    `trailer` is the round's `Review-Verdict:` ATTESTATION (OI-76 alternative C,
    the `Bar-Green:` pattern), and it changes one rule: an attestation must land
    even when the bookkeeping it rides did not change, so a trailer commits
    EMPTY rather than not at all. That is the same trade `Bar-Green` makes: the
    commit's value is the words, not the diff. "An empty commit changes no tree"
    is only HALF of what makes that free, and the missing half was a defect: the
    identity is read through `verdict.governing_rev`, whose walk used to step by
    CLASSIFYING the paths a commit touched — and a zero-path commit is one it
    could not classify, so it stopped there, and the very commit recording an
    approval buried the station refresh under it (REVIEW-A round 012, finding
    1). That walk now steps on identity equality, which makes the claim true of
    the READER and not only of the tree, and
    `test_a_record_commit_stacked_on_a_refresh_does_not_bury_the_peel` drives
    this function's own empty carrier through it. Without a trailer the old rule
    stands unchanged: no empty commits for bookkeeping.

    UNDER THE LOOP MARKER the commit carries the loop's provenance trailer
    (SR-209), and a tree that would change a status the dial holds for a human
    is refused before it is written (SR-208) — telemetry names its paths, so
    that tree is HEAD plus exactly those paths. A refused commit, that way or
    by a hook's veto, is RETURNED as well as printed, so a caller can tell the
    telemetry did not land; None means committed, or nothing to commit.

    Implements: SR-208, SR-209, LLR-246, LLR-248
    """
    rels = []
    for p in paths:
        try:
            rels.append(os.path.relpath(str(p), str(root)))
        except ValueError:
            continue  # a path on another drive (Windows) — skip, never crash
    if not rels and not trailer:
        return None
    code, out = git(root, "status", "--porcelain", "--", *rels) if rels else (0, "")
    dirty = code == 0 and bool(out.strip())
    if not dirty and not trailer:
        return None  # unchanged bookkeeping — no empty commit
    code, staged = git(root, "diff", "--cached", "--name-only", "--", *rels)
    pre_staged = set(staged.splitlines()) if code == 0 else set()
    if dirty:
        git(root, "add", "--", *rels)
    held = loop_held_status_refusal(root, root, paths=rels)
    if held:
        return _telemetry_veto(root, session, rels, pre_staged, held)
    code, out = git(root, *_telemetry_argv(session, label, trailer, dirty, rels))
    if code != 0:
        return _telemetry_veto(root, session, rels, pre_staged, out)
    return None


def _telemetry_argv(session, label, trailer, dirty, rels):
    """The `git commit` argv for one telemetry commit — the message, and the
    scope the commit is allowed to sweep up.

    THE INDEX IS NEVER A SOURCE THIS COMMIT READS. A `git commit` with no
    pathspec commits THE INDEX, so a single unrelated staged file (the caller's
    own `pre_staged` restore proves a non-empty index here is a state the
    authors already expect) lands inside a commit labelled `telemetry:`,
    carrying a `Review-Verdict:` attestation on a commit that changed the work
    tree. Round 015 closed that for `--allow-empty` REPLACING the pathspec, but
    left the scope itself conditional on `rels` — and a scope that exists only
    when its input is non-empty is no scope at all on the arm that matters:
    `commit_telemetry(root, s, l, [], trailer=…)` went on sweeping a staged
    `src.py` into the attestation's carrier, driven. So the scope is STATED, by
    `--only`, and holds on every arm instead of on the arms that happen to carry
    paths. With paths that is what `-- <paths>` already implied; with none,
    git-commit(1) documents `--only` together with `--allow-empty` as needing no
    paths and creating the empty commit — and empty `rels` always reaches that
    arm, because `dirty` is only ever computed from a non-empty `rels`."""
    msg = "telemetry: session {} {}".format(session, label)
    if trailer:
        msg += "\n\n" + trailer
    msg = _kitprovenance.with_loop_trailer(msg)  # the loop's own mark, when marked
    argv = ["commit", "-q", "-m", msg, "--only"] + ([] if dirty else ["--allow-empty"])
    return argv + (["--", *rels] if rels else [])


def _telemetry_veto(root, session, rels, pre_staged, out):
    """A refused telemetry commit, left exactly as it was found.

    "Exactly as before" covers the index too: a veto must not leave the
    bookkeeping staged for the next session's work commit to swallow. Unstage
    only what this run's `add` staged; anything already staged stays."""
    fresh = [r for r in rels if r.replace(os.sep, "/") not in pre_staged]
    if fresh:
        git(root, "reset", "-q", "--", *fresh)
    why = _failure_tail(out) or "hook veto or nothing staged"
    msg = "agent_loop: telemetry commit skipped (session {}): {}"
    print(msg.format(session, why), file=sys.stderr)
    return why


def next_session_number(iter_dir, train=None):
    """Next NNN, continuing across coordinator restarts. A worker's numbering
    is scoped to its train prefix (WI-181) — parallel session numbers cannot
    collide because the (train, session) pair is the aggregation key."""
    pattern = re.compile(r"{}-(\d+)-".format(re.escape(train)) if train else r"(\d+)-")
    highest = 0
    if iter_dir.is_dir():
        for log in iter_dir.glob("*.log"):
            m = pattern.match(log.name)
            if m:
                highest = max(highest, int(m.group(1)))
    return highest + 1


def _iter_dir_list(iter_dirs):
    """Normalize the phase_draw_ordinal argument to a list of Paths — a single
    Path/str (the attended single-dir case) or an already-assembled iterable
    (the cross-train `draw_iter_dirs` list)."""
    if isinstance(iter_dirs, (str, Path)):
        return [Path(iter_dirs)]
    return [Path(d) for d in iter_dirs]


def phase_draw_ordinal(iter_dirs, phase):
    """The 0-based CROSS-TRAIN draw ordinal for `phase` (WI-263, repo-review
    M-31): how many PRIOR sessions — across EVERY train, not just this one —
    already ran this exact phase, counted from the durable session-log
    `# phase:` headers and de-duplicated by log filename across `iter_dirs`.
    This keys the weighted-rotation draw so each phase advances its OWN rotation
    (the global per-train session counter strides — a round is BUILD + REVIEW-A +
    REVIEW-B [+ CRITIQUE] — and would alias against the weight sum, starving
    weight-1 candidates) AND so the long-run provider frequency converges to the
    declared weights ACROSS trains (advertised weight 4 drawn ~4x as often — true
    across trains, not only within one multi-round train). WI-236 counted only
    THIS train's prefix, so a freshly minted train drew slot 0 deterministically
    and the weights were inert across trains (M-31); the caller now passes the
    durable aggregate — the PRIMARY worktree's committed docs/iteration plus this
    worker's own in-flight logs (see `draw_iter_dirs`). Reads existing state only
    (the logs already record the phase); no new durable store, no randomness.
    Empty phase / absent dirs -> 0 (the first draw)."""
    if not phase:
        return 0
    seen = set()
    count = 0
    for iter_dir in _iter_dir_list(iter_dirs):
        if not iter_dir.is_dir():
            continue
        for log in iter_dir.glob("*.log"):
            # De-dup by filename: the same committed log can appear in both the
            # primary aggregate and the local worktree (a train branched from the
            # development checkout carries its history); a session's log name is
            # unique ((train, session, stamp)), so first sighting counts it once.
            # Standalone invocations have no worker draw ordinal, even when
            # their role happens to share a worker phase name.
            if log.name.startswith("call_") or log.name in seen:
                continue
            seen.add(log.name)
            if read_log_meta(log).get("phase", "") == phase:
                count += 1
    return count


def worktree_records(root):
    """Parsed `git worktree list --porcelain` records as (path, branch) pairs,
    in git's own order — the MAIN checkout always first (WI-263); branch is
    None when that worktree is detached. [] when git cannot answer (not a
    repo, git missing) — each caller chooses its own fail direction. The one
    porcelain walk, shared so the primary-checkout reader and the
    integrator's holder lookup cannot drift apart."""
    code, out = git(root, "worktree", "list", "--porcelain")
    if code != 0:
        return []
    records, path, branch = [], None, None
    for line in out.splitlines():
        if line.startswith("worktree "):
            if path is not None:
                records.append((path, branch))
            path = line[len("worktree ") :].strip()
            branch = None
        elif line.startswith("branch refs/heads/"):
            branch = line[len("branch refs/heads/") :].strip()
    if path is not None:
        records.append((path, branch))
    return records


def worktree_index(records, root):
    """The index of `root` among git's worktree records (0 is the primary
    checkout), or None when it is not the top of one. Shared by the
    adjudicator's lane check and the session service's lane reading, so the
    two cannot disagree on which checkout is the primary."""
    want = os.path.normcase(str(Path(root).resolve()))
    for index, (path, _branch) in enumerate(records):
        if path and os.path.normcase(str(Path(path).resolve())) == want:
            return index
    return None


def primary_worktree_root(root):
    """The MAIN (primary) worktree of `root`'s repo — the FIRST entry of
    `git worktree list --porcelain`, which git always lists ahead of the linked
    worktrees (WI-263). A dispatched worker runs agent_loop inside a linked TRAIN
    worktree; this is how it reaches the durable cross-train iteration aggregate
    that lives on the primary checkout. Returns a Path, or None when git can't
    answer (not a repo, git missing) — the caller then falls back to its local
    dir, so a draw never crashes."""
    records = worktree_records(root)
    if not records or not records[0][0]:
        return None
    return Path(records[0][0])


def draw_iter_dirs(root, local_iter_dir):
    """The iteration directories `phase_draw_ordinal` must union for a cross-train
    draw (WI-263, repo-review M-31). The old draw filtered same-phase logs by this
    train's own filename PREFIX, so the ordinal counted only the current train and
    reset every train — the declared weights never materialized across trains. A
    train branches from `integration_head`, so its LOCAL `docs/iteration` (in the
    linked worktree) already carries prior INTEGRATED trains' logs; dropping the
    prefix filter counts those. But the local dir is frozen at the branch base, so
    it MISSES a sibling train that integrates mid-flight (past this base), and the
    first-ever trains have no prior logs at all. The DURABLE cross-train aggregate
    that closes both gaps is the PRIMARY worktree's committed `docs/iteration` —
    the development checkout every INTEGRATED train's logs land on disk in
    (materialized by `publish_integration` -> `_sync_worktree`). Return that
    primary dir FIRST (its committed history is the authority for the filename
    de-dup) plus the local dir, whose not-yet-integrated in-flight logs keep the
    WITHIN-train rotation advancing between integrations. When the primary IS this
    root (an attended single-repo run, no linked worktree) the two coincide and
    only the one dir is returned."""
    local = Path(local_iter_dir)
    primary = primary_worktree_root(root)
    if primary is None:
        return [local]
    shared = primary / "docs" / "iteration"
    if _same_dir(shared, local):
        return [local]
    return [shared, local]


def _same_dir(a, b):
    """Whether two paths name the same directory, tolerant of symlinks and a
    not-yet-created dir (macOS /tmp -> /private/tmp; a fresh worktree). A wrong
    answer is only a lost optimization — `phase_draw_ordinal` de-dups by filename
    regardless — so any error just answers "different"."""
    try:
        return a.resolve() == b.resolve()
    except OSError:
        return a == b


def preflight(root, template, args):
    """Refuse to start iteration 1 on a broken footing. Returns the list of
    failures (empty = go).

    Implements: SR-027, LLR-027
    """
    failures = []
    if not template.strip():
        failures.append(
            "no agent command wired yet: fill the AGENT_CMD slot in "
            "agent-resume.cmd + agent-resume.sh (or pass --agent-cmd / set "
            "the AGENT_CMD env var). Example:\n"
            "    claude -p --model {model} --output-format json "
            "--dangerously-skip-permissions\n"
            "  (no {prompt} = the prompt is piped to the CLI's stdin — immune "
            "to OS command-line caps and Windows batch-shim shell re-parsing; "
            "a .cmd/.bat shim with {prompt} is refused, so use stdin or a "
            "native executable).\n"
            "  The permission-bypass flag is YOUR consent to unattended "
            "edits; leave it out to be prompted."
        )
        return failures  # nothing else is checkable without a command
    try:
        argv, _ = build_argv(template, "model", "prompt")
    except ValueError as exc:
        failures.append("cannot parse AGENT_CMD: {}".format(exc))
        return failures
    exe = argv[0]
    if not (shutil.which(exe) or Path(exe).exists()):
        failures.append(
            "agent CLI not found: {!r} is not on PATH. Install it (or fix "
            "AGENT_CMD), then re-run.".format(exe)
        )
    code, _ = git(root, "rev-parse", "--git-dir")
    if code != 0:
        failures.append(
            "{} is not a git repository — the loop reads commits as its "
            "progress signal.".format(root)
        )
    else:
        # SN-028: the mixed-config refusal rides the launchability preflight —
        # the one rung EVERY coordinator launch passes. The three entry points
        # that bypass agent_loop.main (dispatch, intake, integrate) each fold
        # `config_conflicts` into their own refusal, so no reader can be
        # reached through a half-migrated config.
        failures.extend(config_conflicts(root / "docs"))
        enabled = (
            declared_policy(root / "docs", "privacy-check", "false").lower() == "true"
        )
        if enabled:
            # Single-source the exempt allowlist: let check_privacy.py judge the
            # author email (it self-skips when the gate is off, so this fails
            # only on a genuinely private author on a privacy-checked repo).
            proc = subprocess.run(
                [
                    sys.executable,
                    str(Path(__file__).resolve().parent / "check_privacy.py"),
                    "--root",
                    str(root),
                    "--author",
                ],
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
            )
            if proc.returncode != 0:
                failures.append(
                    "privacy-check author identity violated: an unattended run "
                    "would commit every session under a private identity. "
                    + (proc.stderr or proc.stdout or "").strip()
                )
    # --- worker assignment preflight (WI-181, LLR-061) -----------------------
    # Re-grounded on the §2.3 claim model at concurrency-restructure Phase 5:
    # --wi alone is a full assignment (the session tag defaults to the current
    # branch name); --train survives as the optional explicit tag. A worker
    # still fails CLOSED off a branch — a claim is a branch, so a detached
    # HEAD is an unverifiable checkout.
    wi_spec = getattr(args, "wi", None)
    train = getattr(args, "train", None)
    if train is not None and wi_spec is None:
        failures.append(
            "--train is the worker session tag and needs the assignment; "
            "got --train without --wi"
        )
    if getattr(args, "interactive", False) and (wi_spec, train) != (None, None):
        failures.append(
            "--wi/--train is an unattended worker assignment; it cannot be "
            "combined with --interactive."
        )
    # An empty --wi is an assignment too, so it reaches the parse and refuses
    # by name rather than reading as "not a worker".
    if wi_spec is not None and not failures:
        try:
            wid = parse_wi_id(wi_spec, "--wi")
            if train:
                sanitize_train(train)
        except ValueError as exc:
            failures.append(str(exc))
        else:
            code, branch = git(root, "branch", "--show-current")
            if code != 0 or not branch:
                failures.append(
                    "a worker assignment runs on its claimed branch "
                    "(`integrate.py claim`), but this worktree's branch could "
                    "not be determined (detached HEAD, or git older than "
                    "2.22) — check the branch out first."
                )
            row = load_wi_registry(root).get(wid)
            if row is None:
                failures.append(
                    "assigned {} is not in the docs/work/ registry on "
                    "this branch — a worker never builds an untracked "
                    "WI.".format(wid)
                )
            elif stale_terminal_assignment(root, wid, row):
                # WI-267: a WI CANCELLED mid-assignment is terminal too — a
                # worker must never build a WON'T-BUILD row. The scheduler
                # never freshly dispatches a cancelled WI, but an owner can
                # cancel one already leased to a worker; this closes that
                # narrow mid-flight race the done-only check missed.
                status = (row.get("Status") or "").strip().lower()
                failures.append(
                    "assigned {} is already {} — a terminal status "
                    "(done/cancelled); a stale assignment, so the dispatcher "
                    "must re-derive the frontier.".format(wid, status)
                )
    return failures


def stale_terminal_assignment(root, wid, row):
    """Is `wid`'s TERMINAL registry status a STALE assignment — terminal for
    some reason other than this branch's own committed `WI:` trailer for it, in
    `merge-base(trunk, HEAD)..HEAD`?

    THE REFUSAL ABOVE IS ABOUT A STALE ASSIGNMENT, and a lane resuming its own
    work is not one. A finished lane that still owes a review round is resumed
    with its one row already `done` on the lane, terminal precisely BECAUSE this
    lane made it so; refusing it as "a stale assignment, so the dispatcher must
    re-derive the frontier" would strand the lane. The status alone cannot tell
    the two apart; the trailer can, and it is the same evidence channel
    `train_evidence` gives the walk. A row terminal on the TRUNK carries no
    trailer in this branch's own range, so it still refuses.

    Fails toward the REFUSAL at every unreadable step (no branch, git silent, an
    unborn HEAD, an undeclared trunk): a preflight that cannot prove the lane
    closed the row keeps the guard it had."""
    if (row.get("Status") or "").strip().lower() not in TERMINAL_STATUSES:
        return False
    try:
        base = default_base(root)
    except TrunkUndeclared:
        return True
    if not base:
        return True
    built, _blocked = train_evidence(root, base)
    return wid not in built


def stop_banner(status_path, label, detail=""):
    print("\n=== coordinator stopping: {} ===".format(label))
    if detail:
        print(detail)
    print("--- pending state ({} Current State) ---".format(status_path))
    print(current_state_excerpt(status_path))
    print(
        "--- end-of-run evidence: {0} | {1} | {2} ---".format(
            status_path,
            status_path.parent / "log.md",
            status_path.parent / "iteration_index.md",
        )
    )


# The console guard's one home is the shipped package (WI-448 / D-8); this
# module already imports `kitlib.config` under its guard above, so the alias
# rides that import rather than adding an unguarded second one.
_utf8_console = _kitconfig.utf8_console


def head_sha_full(root):
    """Full HEAD sha (reservation bases are exact, never abbreviated)."""
    code, out = git(root, "rev-parse", "HEAD")
    return out if code == 0 else ""
