#!/usr/bin/env python3
"""Declared process policy, approval authority, and coordinator dials.

This module owns the ``docs/process.toml`` reading, its conflict findings,
approval-rung comparisons, and the small coordinator dial
resolution built from those declarations. Coordinator locks, Git, subprocess
harnessing, assignment state, and telemetry remain in ``agent_common``.

Contracts: IF-261, IF-291 — the interface seam this file declares (process.md §8; row
of record in docs/requirements/interfaces.toml).

Contract IF-261: ``agent_common`` imports and re-exports this module's policy
readers and findings. A docs path or parsed policy is supplied; normalized dial
values, authority decisions, or explicit refusal strings are returned. The
module writes nothing and launches only the existing derived-stage fallback.

Contract IF-291: blackout_at(docs, t=None) is the single policy-reading boundary for the blackout window. It returns Blackout(window, at, end, last_end): end is the exclusive end of the interval containing at, if any; last_end is the most recent interval end at or before at.
"""

import datetime
import os
import re
import sys
import tomllib
from dataclasses import dataclass
from pathlib import Path

try:
    from kitlib import authority as _kitauthority
    from kitlib import config as _kitconfig
    from kitlib import decisions as _kitdecisions
    from kitlib import git as _kitgit
    from kitlib import ladder as _kitladder
    from kitlib import provenance as _kitprovenance
    from kitlib import stage as _kitstage
except ImportError:  # pragma: no cover - in-process fallback
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from kitlib import authority as _kitauthority
    from kitlib import config as _kitconfig
    from kitlib import decisions as _kitdecisions
    from kitlib import git as _kitgit
    from kitlib import ladder as _kitladder
    from kitlib import provenance as _kitprovenance
    from kitlib import stage as _kitstage

import held_status

_SCRIPTS_DIR = Path(__file__).resolve().parent

# The one-word declared-policy reader (the legacy docs/push-policy, …): the
# first non-empty, non-comment line, or `default` when nothing is declared. ONE
# HOME since WI-448 — this name used to carry its own literal copy of a rule four
# other modules also spelled out (`subagent_gate`, and `_first_declared_line` in
# bootstrap/check_privacy/check_trajectory), pinned equal by tests because D-7
# could only contain the drift, not remove it. Re-exported under its own
# long-standing name; the reader for the LEGACY half of the SN-028 dual-read
# window, while new policy reads go through `declared_policy` below, which
# prefers `docs/process.toml`.
#
# `docs/gate` USED TO HEAD THAT LIST AND WAS NEVER READ THROUGH HERE (corrected
# WI-498 slice 4, the gate schedule map's reader E): it is a deliberate NON-row in
# `PROCESS_KEYS` twenty lines below, and every live gate reader spelled its own
# one-line parse out locally. A documented reader that no call site uses is worse
# than none — it makes a scheduling map of the file look one reader deeper than it
# is.
read_declared = _kitconfig.read_declared


# --- SN-028: docs/process.toml, the one policy home ---------------------------
# THE MIGRATION TABLE, stated once. Each row maps a legacy one-word file under
# docs/ to the `[section] key` in docs/process.toml that replaced it, and the
# type the TOML value carries. Three readers stand on this single statement —
# the value reader, the mixed-config refusal, and bootstrap's converter — so a
# key can never be migrated in one of them and forgotten in another.
#
# NOT here, deliberately (each documented in process.toml.template's header):
# docs/stack.ini (adopter-owned product toolchain), docs/work/pause and
# docs/agents-enabled (presence-as-semantics), docs/stage (a generated cache).
# The six check-enablement toggles USED to be a fourth exception; the owner
# overturned that on 2026-08-11 and they are rows below.
PROCESS_TOML = "process.toml"

PROCESS_KEYS = {
    "push-policy": ("policies", "push", "str"),
    "review-policy": ("policies", "review_rounds", "int"),
    "privacy-check": ("policies", "privacy_check", "bool"),
    "secrets-scan": ("policies", "secrets_scan", "bool"),
    "privacy-review": ("policies", "privacy_review", "str"),
    "guardrails-policy": ("policies", "guardrails", "str"),
    "blackout": ("policies", "blackout", "str"),
    # The gate-authority dial retired into the ORDINAL below at SN-029. The
    # legacy `docs/gate-policy` FILE is still read (an un-migrated repo keeps
    # working), and the enum key is still type-checked if a repo hand-wrote it,
    # but nothing SHIPS it any more — see PROCESS_ONLY_KEYS.
    "gate-policy": ("attestation", "gate_policy", "str"),
    # The six CHECK-ENABLEMENT toggles, folded in by the 2026-08-11 overturn of
    # WI-423 ("far better to tie those into process.toml and key them all to on
    # / true"). They belong in THIS table, not PROCESS_ONLY_KEYS: each had a
    # legacy one-word file, so each can be double-declared, and the mixed-config
    # refusal + `--migrate-config` conversion both key off these rows.
    #
    # Only `live-status` is read through `declared_policy` — the other five are
    # read by scripts that import nothing of this layer and carry their own
    # local `tomllib` read (F5, no shared `_kitcommon.py`). Their rows are here
    # anyway, because the refusal and the migration are this module's job
    # wherever the VALUE is read: a checker that reads its own key must still
    # not run beside a legacy file nobody converted.
    "trajectory-check": ("checks", "trajectory_check", "bool"),
    "interfaces-check": ("checks", "interfaces_check", "bool"),
    "components-check": ("checks", "components_check", "bool"),
    "okf-export": ("checks", "okf_export", "bool"),
    "live-status": ("checks", "live_status", "bool"),
    "subagent-gate": ("checks", "subagent_gate", "str"),
}

# Dials with NO legacy one-word file — born in docs/process.toml, so they can
# never be double-declared and appear here rather than in PROCESS_KEYS. They
# still need the type check: the failure PROCESS_KEYS' check exists to stop (a
# quoted `review_rounds` reading as "no review required") applies verbatim to a
# `human_approval_through`, whose wrong value reads as the conservative
# default with no diagnostic and looks exactly like a repo that never set it.
#
# IT IS A `str` SINCE WI-493: the dial names a `DevStg-*` rung, not a 0-4 tier
# ordinal. The type check alone is therefore much weaker than it was — every
# typo is still a `str` — which is why the VOCABULARY check below exists and
# why it, not the type, is now the arm that catches a bad dial.
PROCESS_ONLY_KEYS = {
    ("attestation", "human_approval_through"): "str",
    ("attestation", "keep_nondependent"): "bool",
    ("attestation", "final_review"): "str",
    ("attestation", "complete_review"): "str",
    ("attestation", "complete_sample_rate"): "int",
    ("attestation", "adjudication_review"): "str",
    ("attestation", "decision_recording"): "str",
    # The reverse back-link coverage bar (OI-42 ruled (e), WI-486). It sits in
    # `[checks]` beside six BOOLEANS and is an INT, which is exactly why it
    # needs the type check: its reader
    # (`gen_arch_map.read_backlink_min`) answers 0 — report-only — for anything
    # it cannot read as an int in range, so a hand-written
    # `backlink_coverage_min = "50"` would silently disarm a bar the repo
    # believes it declared. That reader is deliberately quiet (a threshold has
    # no conservative default to fail toward); this table is where it gets loud.
    ("checks", "backlink_coverage_min"): "int",
    # The test-first order's declared start, a commit id (SR-217). Its reader
    # (`kitlib.config.process_check_text`) refuses a non-string, but only into
    # the warn-only step's own output; a bare `test_first_since = 20260926`
    # would read as an unjudged history nobody is made to look at, so the
    # guarded entry points refuse it here.
    ("checks", "test_first_since"): "str",
    # The integration branch by name (WI-925). The trunk reader refuses an
    # absent, non-string, empty or unknown name itself (`agent_common.trunk_name`),
    # but only on the routes that read the trunk; typed here, a bare
    # `trunk = 1` is refused at every guarded entry point, like every dial.
    ("policies", "trunk"): "str",
}

# Dials whose value must also fall in a RANGE. Out of range is refused rather
# than clamped: `101` is not "the strictest bar", it is a value nobody can
# satisfy, and `-1` reads as a bar that can never fire.
PROCESS_KEY_RANGES = {
    ("checks", "backlink_coverage_min"): (0, 100),
}

# Dials whose value must come from a CLOSED VOCABULARY. This replaced
# `human_approval_through`'s `(0, 4)` range row at WI-493, and it is the
# same guarantee carried on the new value's own terms: the retired range refused
# `-1` because that single input reads as LESS human involvement than the owner
# asked for, and a misspelled rung does exactly the same thing — it is
# unrecognized, so it falls to a default rather than to what was meant. Refused
# here, loudly, and fallen back on conservatively at the reader
# (`approval_through`). Populated lazily below, where the rung vocabulary
# is in scope.
PROCESS_KEY_VOCAB = {}

# THE MIGRATION WINDOW: for a re-keyed dial, the exact set of PREVIOUS values
# the reader still translates. Filled below from the translation table itself,
# so the window and the translation cannot come to disagree about which old
# values are honoured.
#
# WHY A VALUE SET AND NOT A TYPE. Declaring "the old TYPE is still accepted"
# was tried first and was wrong in a way worth recording: it accepted every
# int, so `human_approval_through = -1` — the single input the retired
# `(0, 4)` range row existed to refuse, because it is the one that reads as
# LESS human involvement than the owner asked for — stopped being refused at
# all. A migration window must be exactly as wide as the migration.
#
# Without the window at all, `config_conflicts` — a HARD refusal consulted by
# dispatch, intake and integrate — would refuse an adopter's committed
# `human_approval_through = 4` the moment they took the kit upgrade, on a
# dial `approval_through` reads perfectly well. The signal for a legacy
# value is the reader's WARNING, once per run, naming the migrator; the refusal
# stays reserved for values nothing can honour.
PROCESS_KEY_LEGACY_VALUES = {}


def _process_toml_path(docs):
    return Path(docs) / PROCESS_TOML


def process_config(docs):
    """The parsed `docs/process.toml` as a dict of sections, or `{}` when the
    file is absent, unreadable or malformed.

    FAILS CLOSED on a malformed file in the same shape `tracked_pause` does —
    `except (OSError, UnicodeDecodeError, tomllib.TOMLDecodeError)` — rather
    than `read_declared`'s narrower `except OSError`, which lets a BOM'd or
    mis-encoded policy file crash the coordinator while degrading everywhere
    else. `config_conflicts` reports the malformation loudly; this returns `{}`
    so a caller that only wants a value gets the DEFAULT, never a half-parse.

    Implements: SR-137, SR-139, LLR-155
    """
    data = read_toml(_process_toml_path(docs))
    return data if isinstance(data, dict) else {}


# The TEXT twin of `read_toml` (a caller that already extracted a `+++` block
# has no file left to hand over). ONE HOME since WI-821: `kitlib.config`, which
# `kitlib.spine` and `kitlib.station` read too; bound here under its old name.
read_toml_text = _kitconfig.read_toml_text


def read_toml(path):
    """`tomllib.loads` of `path`, or None when it is absent, unreadable,
    mis-encoded or malformed — the module's ONE tracked-TOML read.

    Extracted because `process_config` and `tracked_pause` had it verbatim, and
    the F5 cross-script sanction covers copies between INDEPENDENTLY COPYABLE
    scripts, never two copies inside one file (WI-347). The union of failure
    modes is deliberate: a caller that cannot tell "absent" from "malformed"
    apart on the return value must not be reading policy, and both callers
    below distinguish them by their own second read."""
    try:
        if not path.is_file():
            return None
        # utf-8-SIG: a BOM is not legal TOML, so `tomllib` would raise on a
        # file some editors write by default. The hooks' parse reads it the
        # same way, so no reader diverges over an invisible byte.
        return tomllib.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeDecodeError, tomllib.TOMLDecodeError):
        return None


def _coerce(value, kind):
    """A TOML value rendered in the STRING vocabulary every legacy consumer
    already speaks, so the migration changes no downstream comparison. A bool
    renders `true`/`false`; an int renders its digits; a string passes through.

    A value of the WRONG TOML type returns None — never a substituted default.
    That distinction is load-bearing: `review_rounds = "2"` (a plausible hand
    edit, since every other value in `[policies]` is quoted) once silently
    became the integrator's `"0"` default, i.e. NO review verdict required, on
    a repo whose owner had just asked for two. A type mismatch is a REFUSAL
    (`config_conflicts` reports it and the three guarded entry points stop),
    not a value."""
    if value is None:
        return None
    if kind == "bool":
        return ("true" if value else "false") if isinstance(value, bool) else None
    if kind == "int":
        if isinstance(value, bool) or not isinstance(value, int):
            return None
        return str(value)
    if isinstance(value, bool) or not isinstance(value, str):
        return None
    return value


def declared_policy(docs, legacy_name, default):
    """The value of one policy dial, `docs/process.toml` first.

    `legacy_name` is the legacy file's basename (`"push-policy"`, …) — the key
    of `PROCESS_KEYS` — so every call site names the dial it already named and
    the migration table does the rest. Returns the value in the same STRING
    vocabulary the legacy file carried, so no comparison downstream changes.

    Precedence, and only two tiers by design: the TOML when the file declares
    that key, else the legacy one-word file, else `default`. There is NO third
    "both" tier — a repo carrying both sources is refused by `config_conflicts`
    at preflight rather than silently resolved (SN-028 / plan §11.8), because a
    mixed config is exactly the state where two readers disagree about the same
    policy and neither is wrong.

    The two privacy keys are read through `kitlib.config.policy_declaration`,
    the one home of their misplaced-key rule: a copy the parse holds under any
    table other than `[policies]` reads the gate on and the reviewer required,
    so this layer and the git hooks never disagree.
    """
    section, key, kind = PROCESS_KEYS[legacy_name]
    data = process_config(docs)
    if key in _kitconfig.MISPLACED_PRIVACY_READING:
        raw = _kitconfig.policy_declaration(data, key)
    else:
        table = data.get(section)
        raw = table.get(key) if isinstance(table, dict) else None
    if raw is not None:
        value = _coerce(raw, kind)
        # A wrong-typed value is NOT silently a default here — `config_conflicts`
        # refuses it upstream, and this fall-through only ever runs on a path
        # that already declined to refuse (a caller outside the three guarded
        # entry points). Falling to the legacy file / default keeps such a
        # caller working rather than crashing it.
        if value is not None:
            return value
    return read_declared(Path(docs) / legacy_name, default)


# --- WI-148 / WI-834: the blackout window, read in ONE place -------------------
# `[policies] blackout`: `HH:MM-HH:MM` UTC, a window that STARTS on each weekday
# (Mon-Fri). Every reader of the dial calls `blackout_at` below and nothing else
# reads it: the loop's pre-session wait, the session service's launch boundary,
# the claim, the coordinator guard's hooks and the retained adjudicator's
# retirement. An absent, empty or malformed value, or `start == end`, disables
# it; a fresh scaffold ships `12:00-12:00`, disabled but in window SHAPE (owner
# ruling 2026-08-11, WI-433).
BLACKOUT_RE = re.compile(r"^\s*(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})\s*$")


def parse_blackout(line):
    """Parse a `HH:MM-HH:MM` blackout line into `(start_min, end_min)`, minutes
    past UTC midnight, or None when absent, empty or malformed (an out-of-range
    hour or minute is malformed). The `start == end` disable rule is
    `blackout_at`'s, so the parse and the policy stay separately testable."""
    m = BLACKOUT_RE.match(line or "")
    if not m:
        return None
    sh, sm, eh, em = (int(g) for g in m.groups())
    if sh > 23 or eh > 23 or sm > 59 or em > 59:
        return None
    return (sh * 60 + sm, eh * 60 + em)


def _utcnow():
    """Now, as a naive UTC datetime (the window's clock)."""
    return datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)


@dataclass(frozen=True)
class Blackout:
    """The blackout window as declared at one instant `at`: the declared value
    (`window`, "" when none), the end of the window `at` is inside (`end`,
    None outside one), and the end of the most recent window that ended AT OR
    BEFORE `at` (`last_end`, None when none has). Times are naive UTC.

    Implements: SR-237, LLR-316
    """

    window: str
    at: datetime.datetime
    end: datetime.datetime | None = None
    last_end: datetime.datetime | None = None

    @property
    def inside(self):
        return self.end is not None

    @property
    def wake_seconds(self):
        """Whole seconds from `at` to the window's end (0 outside one)."""
        return int((self.end - self.at).total_seconds()) if self.end else 0

    @property
    def last_end_epoch(self):
        """`last_end` as epoch seconds, or None."""
        if self.last_end is None:
            return None
        return self.last_end.replace(tzinfo=datetime.timezone.utc).timestamp()


def _windows(span, t):
    """`(start, end)` of every window that starts on a weekday from eight days
    before `t`'s date to that date: enough to hold the one `t` is inside and
    the most recent one that ended. A window whose start is after its end
    wraps past midnight and belongs to its START weekday, so a Friday-night
    window runs into Saturday and no window starts on a weekend."""
    start, end = span
    wrap = datetime.timedelta(days=1 if end < start else 0)
    day0 = datetime.datetime(t.year, t.month, t.day)
    for back in range(8, -1, -1):
        day = day0 - datetime.timedelta(days=back)
        if day.weekday() < 5:
            yield (
                day + datetime.timedelta(minutes=start),
                day + datetime.timedelta(minutes=end) + wrap,
            )


def blackout_at(docs, t=None):
    """The blackout window at instant `t` (default now, naive UTC), read from
    `[policies] blackout` as declared in `docs` AT THIS CALL, so a changed
    value applies from the next call on. The ONE reader of the dial and the
    one window function: it answers both "is `t` inside a window?" (`end`, the
    end being exclusive, `[start, end)`) and "when did the most recent window
    end, at or before `t`?" (`last_end`, inclusive: a call exactly at an end
    sees that window). Disabled (absent, empty, malformed or `start == end`)
    answers neither.

    Implements: SR-237, LLR-316
    """
    t = _utcnow() if t is None else t
    line = declared_policy(docs, "blackout", "")
    span = parse_blackout(line)
    if span is None or span[0] == span[1]:
        return Blackout(window=line, at=t)
    end = last_end = None
    for w_start, w_end in _windows(span, t):
        if w_start <= t < w_end:
            end = w_end
        if w_end <= t:
            last_end = w_end
    return Blackout(window=line, at=t, end=end, last_end=last_end)


# --- SN-029: the human-approval level, as an ORDINAL ----------------------
# THE DIAL, and why it replaces a three-value enum. `attended | single-approve |
# autonomous` answered "who approves" with three words that four independent
# tables then re-interpreted, each with its own fail-safe direction. What the
# dispatcher actually needs is an ORDINAL comparison — is the tier this row sits
# at still human-held? — and an enum cannot express "TCs are human-held but LLRs
# are not", which is the distinction the eight-rung stage ladder exists to make.
#
# THE LEGACY TRANSLATION, stated as all THREE dials rather than as a level.
# The enum's three words were never one axis: each of them bundled a tier hold,
# a drain policy and an end-of-run hold, which is precisely why four tables had
# to re-interpret the same word. Translating to a level alone loses two of the
# three facts — the shape of the original SN-029 bug, where `single-approve`
# became "level 2" and so silently acquired a per-tier hold it never had.
#
#   attended       every tier is the human's; lanes drain at an approval
#   single-approve  LLM review through DevStg-Reqs+DevStg-Tests, ONE human sitting
#                  at the close — so NO per-tier hold (level 0), a final read,
#                  and the non-dependent work kept running that distinguished it
#   autonomous     every bar but the owner's final read closes on a recorded
#                  LLM verdict
LEGACY_APPROVAL = {
    "attended": {
        "human_approval_through": _kitauthority.LEGACY_GATE_DIALS["attended"],
        "keep_nondependent": False,
        "final_review": "always",
    },
    "single-approve": {
        "human_approval_through": _kitauthority.LEGACY_GATE_DIALS["single-approve"],
        "keep_nondependent": True,
        "final_review": "always",
    },
    "autonomous": {
        "human_approval_through": _kitauthority.LEGACY_GATE_DIALS["autonomous"],
        "keep_nondependent": True,
        "final_review": "off",
    },
}

# --- THE RE-KEY (WI-493, OI-21 shape (ii), folded into WI-498 slice 5) ---------
# THE DIAL MOVED, DELIBERATELY, and the block below this one used to say the
# opposite. OI-21 ruled shape (i) — keep the 0-4 ordinal and MAP it onto the
# ladder through a declared `DIAL_HOLDS` table — and named this conversion as
# shape (ii), available to supersede (i). The owner exercised that clause; the
# stage unification is where it lands, because the reason (i) was ever needed is
# the reason it is now unnecessary.
#
# WHY THE MAPPING TABLE COULD RETIRE RATHER THAN BE RE-KEYED. `DIAL_HOLDS`
# existed to bridge TWO vocabularies: an ordinal counting approvable TIERS and a
# ladder of labelled RUNGS. Shape (i)'s own argument against the retired
# `stage < level` arithmetic was that it compared two different ladders that
# happened to line up. Under one vocabulary there is only one ladder, so the
# comparison stops being a coincidence and becomes the definition: the dial names
# the HIGHEST rung a human still approves, and every rung AT OR BELOW it is held.
# That is the exact mirror of the at-or-above rule slice 2 gave check selection.
#
# EQUIVALENCE DRIVEN BEFORE THE TABLE WAS DELETED, not asserted after: all five
# former levels hold precisely the same rung sets under the ordinal rule
# (0 -> 0 rungs, 1 -> 2, 2 -> 4, 3 -> 5, 4 -> 8). The old table's most
# hand-reasoned property — that `DevStg-Boundary` rides `DevStg-Needs` and
# `DevStg-Arch` rides `DevStg-Reqs`, chosen because it errs toward MORE human
# involvement — falls out of the ordering for free, because each inserted rung
# sits immediately above the rung it was made to ride. `tests/test_approval_
# level.py` pins the equivalence permutation by permutation.
#
# WHAT THE RE-KEY BUYS BEYOND THE VOCABULARY: three settings the ordinal could
# not express. `DevStg-Needs`, `DevStg-Reqs`, `DevStg-Tests` and `DevStg-Impl`
# are now legal dial values with obvious meanings (hold Needs but not Boundary;
# hold through Reqs but not the partition; and so on). The old dial had five
# notches for eight rungs and the three it could not name were unreachable
# rather than forbidden.
#
# "NOTHING IS HUMAN-HELD" IS `DevStg-Below`, not a fourth kind of value. It is
# the sentinel `kitlib.stage` already declares for "below every rung", used here
# in exactly that sense: set the dial below the ladder and no rung is at or below
# it. A magic word like `"none"` would have been a second vocabulary in the one
# place this program exists to remove one.
APPROVAL_DIAL_RUNGS = frozenset(_kitladder.LADDER_RUNGS) | {_kitstage.BELOW}

# Declared UP THERE with the other dial tables and filled HERE, because the
# vocabulary is this module's own and the table is read by the shared
# validator. One value, one home.
PROCESS_KEY_VOCAB[("attestation", "human_approval_through")] = APPROVAL_DIAL_RUNGS

# The 0-4 ordinal an unmigrated repo still declares. READ, TRANSLATED AND
# WARNED — not refused: the value is a dial in an adopter's committed
# `process.toml`, and refusing it would stop their loop dead on a kit upgrade
# for a spelling. `bootstrap.py --migrate-config` rewrites it in place, and the
# warning names that command. There is no clamping arm: an int outside 0-4 was
# malformed before the re-key and is malformed after it. The table's one home
# is `kitlib.authority`, whose `read_dial` is the resolution every live reader
# of the dial runs (the loop's writers, the pre-commit step and the merge slot
# read committed trees through it, silently); re-exported here for the migrator
# and the validator.
LEGACY_DIAL_ORDINALS = _kitauthority.LEGACY_DIAL_ORDINALS

PROCESS_KEY_LEGACY_VALUES[("attestation", "human_approval_through")] = frozenset(
    LEGACY_DIAL_ORDINALS
)

# Fail toward MORE human involvement on anything unreadable: a dial nobody can
# parse must not silently hand approval authority to the loop. The top rung
# is the conservative end — it holds every rung there is.
APPROVAL_FALLBACK = _kitladder.STAGE_RELEASE

# The dial's RETIRED KEY NAME (WI-499, owner-ruled 2026-08-21). A repo
# scaffolded before this rename still carries this spelling in
# `[attestation]`; `approval_through` below reads it as a loud fallback,
# mirroring the read-translate-warn shape WI-493 used for the retired 0-4
# ordinal. `bootstrap.py --migrate-config` (`_migrate_dial_key_name`) is the
# one-time fix that ends the warning.
LEGACY_ATTESTATION_KEY = _kitauthority.LEGACY_DIAL_KEY


def legacy_approval(word, key):
    """One dial's value under a legacy `gate-policy` word, or None when the word
    is not one of the three. The single home for the translation, so the
    migrator and the fallback readers cannot disagree about what a word meant."""
    return LEGACY_APPROVAL.get(str(word).strip().lower(), {}).get(key)


def approval_through(docs):
    """`[attestation] human_approval_through` as a `DevStg-*` rung.

    The HIGHEST rung a human still approves; every rung at or below it is held
    (`human_holds`). `DevStg-Below` means nothing is held — the loop approves
    every rung itself. `DevStg-Release`, the shipped default, holds everything.

    Falls back through the legacy `gate-policy` enum, then to `DevStg-Release`.

    A LEGACY 0-4 INT IS TRANSLATED AND WARNED, not refused (WI-493). See
    `LEGACY_DIAL_ORDINALS`: an adopter's committed dial must not stop their loop
    on a kit upgrade, and the warning names the migrator that fixes it. An int
    OUTSIDE 0-4 was malformed before the re-key and stays malformed.

    AN UNRECOGNIZED VALUE IS MALFORMED, NOT COERCED — the same reasoning the
    out-of-range int always took, and it matters more now that the vocabulary is
    open-looking. `"devstg-arch"`, `"Arch"` or a rung from a newer kit takes the
    conservative fallback rather than a best guess, because every wrong guess
    here fails in the direction of LESS human involvement.
    (`config_conflicts` refuses it loudly upstream; this is the behaviour for
    callers that did not run that gate.)

    THE RESOLUTION IS `kitlib.authority.read_dial`, the one the loop's writers,
    the pre-commit step and the merge slot run over a committed tree
    (`authority.dial_at`), so a dial means one thing to every reader. This
    function adds the two things only the LIVE working tree needs: the file
    read, and the migration note, which is presentation and printed here alone.

    Implements: SR-137, SR-139, LLR-155
    """
    rung, legacy = _kitauthority.read_dial(
        process_config(docs),
        lambda: read_declared(Path(docs) / "gate-policy", None),
    )
    if legacy is not None:
        print(_retired_dial_note(legacy, rung), file=sys.stderr)
    return rung


def _retired_dial_note(legacy, rung):
    """The migration note for a retired dial spelling `read_dial` translated:
    the retired key name, the retired 0-4 ordinal, or both.

    ASCII ONLY, deliberately. This prints from a LIBRARY path, so no caller is
    guaranteed to have run `utf8_console()` first; an em-dash here reaches a
    cp1252 console as a replacement character in a message whose whole job is
    to be read and acted on."""
    fix = (
        "Run `python project-trajectory/scripts/bootstrap.py --migrate-config "
        "--dest .` from your kept kit checkout to rewrite {}."
    )
    retired_key = legacy["key"] == LEGACY_ATTESTATION_KEY
    if legacy["ordinal"] is None:
        return (
            "agent_common: [attestation] {} is RETIRED - reading it as "
            "`human_approval_through` (WI-499). ".format(LEGACY_ATTESTATION_KEY)
            + fix.format("the key")
        )
    return (
        "agent_common: [attestation] {} = {} is the RETIRED 0-4 ordinal{} - reading it as `{}` (WI-493{}). ".format(
            legacy["key"],
            legacy["ordinal"],
            " under a RETIRED key name too (WI-499)" if retired_key else "",
            rung,
            "+WI-499" if retired_key else "",
        )
        + fix.format("it")
    )


# --- OI-21 -> WI-493: THE DIAL AND THE LADDER ARE ONE VOCABULARY --------------
# THE DIAL MOVED. It was the APPROVABLE-TIER ORDINAL 0-4 SN-029 defined (0 =
# nothing held, 1 = SNs, 2 = ...and SRs, 3 = ...and LLRs, 4 = ...and TCs), mapped
# onto the eight rungs by a declared `DIAL_HOLDS` table under OI-21 shape (i).
# WI-493 executed shape (ii): it now names a `DevStg-*` rung directly, and the
# table retired because there is no longer a second vocabulary to map from. The
# full argument, the driven equivalence and what the change buys are recorded at
# the re-key block above `APPROVAL_DIAL_RUNGS`.
#
# WHAT DID *NOT* MOVE, and this is the part OI-21 was emphatic about: the dial
# still says WHICH SPINE RUNGS a human approves. It was NOT re-keyed to artifact
# DEPTH. Re-keying approval to the depth and tier of the artifact touched is a
# change to WHEN A HUMAN IS RE-ENGAGED whose wrong-answer direction is silently
# LESS human involvement, so it is decided on its own — once IF/CMP maturity
# joins the approvable fold — and never defaulted here.
#
# WHERE THE TWO INSERTED RUNGS LAND is no longer a decision this module makes.
# `DevStg-Boundary` and `DevStg-Arch` produce artifacts (IF and CMP rows) that
# are not approvable TIERS, so the old ordinal had no notch for them and the
# table had to choose: each was held whenever the rung BELOW it was held —
# Boundary rides Needs, Arch rides Reqs — chosen because it errs toward MORE
# human involvement. Under the at-or-below rule that choice falls out of the
# LADDER ORDER for free, because each inserted rung sits immediately above the
# rung it was made to ride. The hand-reasoned property became a structural one.
#
# `LADDER_RUNGS` names the whole closed vocabulary — not just the held subset —
# because "is this a rung I recognize" and "is this rung held" are different
# questions, and `human_holds` must answer the first CONSERVATIVELY. Without it
# an unrecognized label (`""`, a typo, a rung from a newer kit) would compare as
# an ordinal lookup failure rather than as a hold.
#
# IT USED TO BE A LITERAL RESTATEMENT HERE (WI-498 slice 0 ended that). The
# reason given was the F5 no-shared-module rule — this module could not import
# the derivation engine — so the eight strings were spelled out again and pinned
# equal by tests/test_approval_level.py. F5 was replaced by owner ruling D-8
# (`OI-16`): the vocabulary now has ONE home in `kitlib`, which this module
# already imports, and the pin retired with the restatement it guarded. Drift is
# unrepresentable rather than detected — the WI-448 declared-line precedent.
LADDER_RUNGS = _kitladder.LADDER_RUNGS


# THE OFF-SPINE SIBLING OF THE DIAL (owner ruling OI-30 D3, 2026-08-15).
#
# `human_approval_through` governs the SPINE tiers. The off-spine registries
# that carry an off-spine `status` cell — `interfaces.toml`, `external.toml`,
# `components.toml` — were governed by PROSE ONLY: their headers said the cells
# were the owner's to flip, and at any dial below 4 nothing refused a loop
# session that wrote `approved`.
#
# THE RULED SHAPE IS DERIVED, NOT DECLARED, and the owner's question is why:
# *"I thought this would follow the dev-stage directly? Why build a new enum?"*
# The proposal on the table was a new `[attestation] human_approval_registries`
# list; it was OVERTURNED because the registry-to-rung association ALREADY
# EXISTS in `spine_rules` — `boundary_incomplete` gates DevStg-Boundary on
# `external.toml`'s approvals, and `arch_incomplete` gates DevStg-Arch on the
# component registry. So the association is existing fact, and a second
# declaration of it would be a rival answer that agrees until someone edits one.
#
# NO NEW KEY AND NO NEW ENUM: authority over a status cell in registry R is
# whether R's stage rung is human-held under the EXISTING dial — derived rather
# than declared. WHICH registries that holds is the dial's answer, not a fixed
# list: at a dial holding every rung it is all of them, at this repo's none.
#
# AN UNMAPPED APPROVAL-CARRYING REGISTRY IS HELD. The map is small and the
# registries are optional, so "I do not know which rung governs this" must
# resolve toward more human involvement, exactly as `human_holds` resolves an
# unreadable dial and an unrecognized rung.
#
# THE TABLE LIVES IN `kitlib.authority` NOW (LLR-249) and this is the same
# object, re-exported: the history check reads the rung of a PAST commit's
# status change without importing the coordinator, and one table is what keeps
# the loop's refusal and that report from disagreeing. The assumptions registry
# joined it at the frame's rung (LLR-246).
# Implements: SR-208, LLR-246
APPROVAL_RUNGS = _kitauthority.APPROVAL_RUNGS


# THE SPINE SIBLING OF THE TABLE ABOVE (owner ruling 2026-09-01, WI-572).
#
# Same question, same fail-safe, different registries: which DevStg rung is a
# SPINE row approved INTO, so the dial can answer whether that tier's `Status`
# flip is the loop's act or the owner's. Keyed by registry STEM
# (`spine_carrier.stem`) rather than by tier letter because the two callers
# both hold a registry path and neither holds a tier — and because a stem
# survives a carrier change, which a `.toml` suffix would not.
#
# IT HAS ONE HOME BECAUSE IT HAS TWO CONSUMERS AND THEY MUST NOT DISAGREE. The
# mint (`intake._released_drafted_rows`) uses it to decide which Drafted rows a
# merge hands to an adjudicator; the brief
# (`adjudicate_brief.first_approval_values`) uses it to decide which of the rows
# it re-resolves LIVE that adjudicator may actually flip. It was two tables for
# one commit — a registry-keyed one in `intake` and a tier-keyed one in
# `adjudicate_brief` — and the brief's copy was consulted only for the
# amendment arm's aftermath, so the first-approval arm derived its `--approves`
# argument with no dial filter at all: at any dial holding a spine rung the
# brief rendered the owner's held rows as this session's to approve. One table
# with one predicate is what makes that unrepresentable rather than detected.
#
# Re-exported from `kitlib.authority` with its off-spine sibling (LLR-249).
SPINE_APPROVAL_RUNGS = _kitauthority.SPINE_APPROVAL_RUNGS


def human_holds(docs, stage):
    """Is work at spine `stage` still the HUMAN's to approve?

    The one comparison every consumer makes, stated once. `stage` is
    `spine_rules.spine_stage`'s `DevStg-<Label>` answer — the rung currently in
    work — and a rung the declared level holds surfaces rather than dispatching.

    THE COMPARISON IS AN ORDINAL ON THE ONE LADDER (OI-21 -> WI-493). It reads through
    the ONE ladder. The dial names the highest rung a human still approves, so
    every rung AT OR BELOW it is held — the mirror of the at-or-above rule that
    selects checks. The form retired at OI-21 was `stage < level` over two
    DIFFERENT integer ladders, correct only while they happened to line up, and
    the shape retired at WI-493 was the table that bridged them; what makes the
    comparison sound now is that there is one ladder. That old coincidence is what
    the 2026-08-12 rung insert nearly broke, silently, in the direction of less
    human involvement.

    BOTH ENDS OF THE LADDER ARE ABSOLUTE, and they are now spelled as the values
    they always meant. `DevStg-Release` — the shipped default — holds everything
    including the close, because it is the top rung and everything is at or below
    it. `DevStg-Below` is the sentinel for "nothing is human-held": set below the
    ladder, no rung is at or below it. Only a dial between the two consults the
    stage at all.

    AN UNREADABLE STAGE IS HELD, and so is an UNRECOGNIZED rung label — the same
    conservative direction as an unreadable level. Note the deliberate asymmetry
    with `kitlib.ladder.stage_ord`, which RAISES on an unknown label: there, an
    unknown stage means the ladder moved under a cached value and the operator
    must see it; here, the question is who approves, and the only safe answer to
    "I do not recognize this rung" is "the human does".

    THE COMPARISON ITSELF IS `kitlib.authority.holds_under` (LLR-249), the
    one the history check also makes against a past commit's dial; this
    function supplies the LIVE dial.

    Implements: SR-137, SR-139, LLR-155
    """
    return _kitauthority.holds_under(approval_through(docs), stage)


def human_approves(docs, registry):
    """May only a HUMAN move the `status` cell of this off-spine `registry`?

    True means HELD — the cell is the owner's, in a reviewed Status-change
    commit. The mirror of `human_holds`, and deliberately the same shape: one
    predicate, one home, consulting one table.

    `registry` is the registry's stem as the repo names it — `"interfaces"`,
    `"external"`, `"components"` — or its path, read through
    `kitlib.authority.rung_for`, the one map the held-status judgement reads,
    which also answers the needs file's stakeholder list at `DevStg-Needs`.

    THREE ARMS, and only the third is new thinking:
      * MAPPED and its rung is human-held under `human_approval_through`
        -> True (held). At a `DevStg-Needs` dial that is the needs file alone.
      * MAPPED and its rung is not held -> False (a loop session may write it,
        because the project has declared that rung machine-approvable).
      * UNMAPPED -> True (held), FAIL-SAFE. A status-carrying registry nobody has
        associated with a rung is one nobody has ruled on, and the only safe
        answer to that is "the human does".

    THE WRITER-SIDE CONTRACT, stated here because this predicate is the only
    home for it. Any path that would set an off-spine `status` to `Approved` MUST
    consult this first and refuse when it answers True. Today the kit ships no
    such automated writer — off-spine approvals are hand-edited — so the
    live consumers are the dispatcher's attestation/gate arm (`dispatch.
    _kind_action`, which surfaces rather than dispatching a WI whose action
    would move a held registry's approvals) and `intake`'s snapshot/flip path,
    which is where the first machine writer would land. That is the honest
    statement of scope: the predicate is enforced where a writer exists, and it
    exists so the next writer cannot be added without meeting it."""
    rung = _kitauthority.rung_for(registry)
    if rung is None:
        return True
    return human_holds(docs, rung)


def human_approves_spine(docs, registry):
    """May only a HUMAN flip this SPINE `registry`'s rows `Drafted` ->
    `Approved`? True means HELD.

    The spine mirror of `human_approves`, and deliberately the same three arms
    and the same fail-safe: mapped-and-held -> True, mapped-and-released ->
    False, UNMAPPED -> True. An approval-carrying registry nobody has associated
    with a rung is one nobody has ruled on, and the only safe answer to that is
    "the human does".

    `registry` is the registry's path or stem, read through
    `kitlib.authority.rung_for` — the one map the held-status judgement reads
    too, so the needs file (SN and its stakeholder list) is approved at
    `DevStg-Needs` here as there, not unmapped and held at every dial.

    THE READER-SIDE CONTRACT, the half `human_approves` states for writers.
    Anything that tells a session which rows it may approve MUST filter through
    this — not only the path that mints the row, but every path that later
    re-resolves the population and renders it. The two are separated by a merge
    and a claim (`intake._released_drafted_rows` mints; `adjudicate_brief.
    first_approval_values` re-resolves live at composition time), and a filter
    applied at only one of them is a filter the brief does not have."""
    rung = _kitauthority.rung_for(registry)
    if rung is None:
        return True
    return human_holds(docs, rung)


def loop_held_status_refusal(
    repo, trunk, base="HEAD", head=None, paths=None, trunk_rev="HEAD"
):
    """The held-status refusal a LOOP writer owes before it commits, or None:
    the narrowed marker arm (SR-208).

    None at once for a process the loop did not start (no loop marker): a
    person's own commit is not judged where it is made. None as well inside a
    claimed lane (`kitlib.git.claimed_work_branch(repo)`): the lane's every
    commit is judged when it lands, by the lane rule the merge slot's
    lane-commit walk runs. Otherwise `held_status.marked_refusal` judges the
    tree between `base` and `head` in `repo`: a status move the dial holds,
    off-spine or on the need, requirement, design and test tiers, or a held
    copy claim. The dial is the one COMMITTED at `trunk_rev` in the `trunk`
    checkout (`kitlib.authority.dial_at`, the one silent, legacy-aware
    reader), never the trunk checkout's working file, because an uncommitted
    owner edit there is not the tree the writer commits onto. `head=None` is
    the index (a `git commit` writer); a commit or tree sha is the tree a
    plumbing writer is about to commit; `paths` narrows the judgement to the
    registries a path-scoped commit takes.

    ONE COMPOSITION for every loop writer — the bookkeeping commit, the
    handback commits and the telemetry commit — so the reading of the marker,
    the lane test and the choice of dial cannot drift between them. The
    judgement itself is `held_status`'s, which the pre-commit step reads too.

    Implements: SR-208, LLR-246"""
    if _kitprovenance.loop_session() is None or _kitgit.claimed_work_branch(repo):
        return None
    dial = _kitauthority.dial_at(trunk, trunk_rev)
    return held_status.marked_refusal(repo, base, head, dial, paths)


def final_review(docs):
    """Does the run stop for a FINAL human read even when the level let it
    close? `True` for the declared `"always"`, `False` for anything else.

    The separate end-of-run hold, split out from the ordinal because it is
    flipped far more often than the level is — and because conflating them
    would mean you could not ask for a closing read without also holding every
    tier. Defaults to holding: the shipped template declares `"always"`, and an
    unreadable value takes the same conservative direction every other dial in
    this module takes."""
    table = process_config(docs).get("attestation")
    if isinstance(table, dict):
        value = table.get("final_review")
        if isinstance(value, str):
            return value.strip().lower() != "off"
    legacy = legacy_approval(
        declared_policy(docs, "gate-policy", "attended"), "final_review"
    )
    return legacy != "off"


def complete_review(docs):
    """`(mode, rate)` for adjudicating a CLEAN close — `"off" | "sample" |
    "always"` and the sampling denominator.

    `partial` and `cancelled` closes are ALWAYS adjudicated: each carries a
    claim about what was not delivered, and a claim is what an adjudicator is
    for. A green close already passed the declared bar and the review rounds,
    so gating every one of them would rebuild the verdict gate under a new
    name — but never looking at any of them means the review rounds are the
    only thing that ever judged the work. The sample is the middle.

    An unreadable mode falls to `"sample"` (the shipped default) and a
    non-positive or unreadable rate to 4, because the failure that matters here
    is silently adjudicating NOTHING."""
    table = process_config(docs).get("attestation")
    mode, rate = "sample", 4
    if isinstance(table, dict):
        declared = table.get("complete_review")
        if isinstance(declared, str) and declared.strip().lower() in (
            "off",
            "sample",
            "always",
        ):
            mode = declared.strip().lower()
        n = table.get("complete_sample_rate")
        if isinstance(n, int) and not isinstance(n, bool) and n > 0:
            rate = n
    return mode, rate


# The `adjudication_review` alphabet, named once so the dial reader, the vocab
# refusal and the tests all spell it the same way.
ADJUDICATION_REVIEW_MODES = ("never", "when-minting", "always")

# Refused loudly at preflight rather than swallowed, for the reason the vocab
# table's own header gives: a misspelled `nevr` is a `str`, so the type check
# cannot see it, and the reader below would fall to `when-minting` — silently
# giving a repo that asked for NO adjudication round one after every minting
# verdict, with no diagnostic and no way to tell it from a repo that never set
# the dial. This one is safe to arm at birth: the dial has no legacy value
# anywhere, so nothing an adopter already carries can be refused by it.
PROCESS_KEY_VOCAB[("attestation", "adjudication_review")] = set(
    ADJUDICATION_REVIEW_MODES
)

# The successor classes whose drafting earns a second opinion under
# `when-minting`, and the brief that always does. A verdict that only recommends
# a flip, or drafts ordinary fix rows, moves no scope and creates no exclusive
# work — a fresh session with less context judging the one session that held the
# whole chain buys nothing there.
_REVIEW_OWED_CLASSES = ("spine", "high-risk")
_REVIEW_OWED_BRIEFS = ("consolidate",)


def adjudication_review(docs):
    """The `[attestation] adjudication_review` dial as one of
    `ADJUDICATION_REVIEW_MODES`.

    An unreadable or unrecognized value falls to the shipped `"when-minting"`,
    not to `"never"`: the failure that matters is silently reviewing NOTHING,
    the same fail-direction `complete_review` takes for the same reason."""
    table = process_config(docs).get("attestation")
    if isinstance(table, dict):
        declared = table.get("adjudication_review")
        if isinstance(declared, str) and declared.strip().lower() in (
            ADJUDICATION_REVIEW_MODES
        ):
            return declared.strip().lower()
    return "when-minting"


# The `decision_recording` alphabet is the record's own (`kitlib.decisions`),
# so the dial reader, the merge slot's rung and the session note spell it one
# way. Safe to arm at birth, like `adjudication_review`: no legacy value exists.
# Implements: SR-225, LLR-282
DECISION_RECORDING_MODES = _kitdecisions.MODES
PROCESS_KEY_VOCAB[("attestation", "decision_recording")] = set(DECISION_RECORDING_MODES)


def decision_recording(docs):
    """The `[attestation] decision_recording` dial as one of
    `DECISION_RECORDING_MODES`.

    UNDECLARED reads `"off"`, the template's shipped value: no repo owes a
    record until its owner asks for one. DECLARED BUT UNRECOGNIZED reads
    `"record"`: the owner asked for something, and the failure that matters is
    silently recording nothing — `config_conflicts` refuses the value loudly
    upstream, and this reader keeps the obligation for anyone who did not run
    that gate. The dial allocates the owner's reading; it never moves what must
    reach the owner through the process's exits, at any setting.

    Implements: SR-225, LLR-282
    """
    table = process_config(docs).get("attestation")
    if not (isinstance(table, dict) and "decision_recording" in table):
        return "off"
    declared = mode_word(table.get("decision_recording"))
    return declared if declared in DECISION_RECORDING_MODES else "record"


def adjudication_review_owed(docs, brief, drafts):
    """Does a committing ADJUDICATE session owe a review round — ONE reader for
    the round scheduler and the merge gate, so the two cannot disagree.

    THE POSITION (plan `docs/plans/2026-09-02-backlog-restructure-and-
    consolidation.md` §3, owner direction 2026-09-02). The adjudicator is
    already the cross-family judge by routing: `agent_loop`'s ADJUDICATE arm
    excludes the builder's family, so the judgement is a fresh context by
    construction. A further round is a SECOND fresh session, with less context
    than the first, judging the one session that held the whole chain — and it
    earns its strong-tier cost only where the verdict CREATES WORK OR MOVES
    SCOPE. `when-minting` is that line drawn mechanically: a drafted successor
    at `spine` or `high-risk` runs exclusive and touches the registries, and a
    `consolidate` verdict closes rows it was not minted from.

    `brief` is the adjudicator brief this session was composed from ("" for a
    session that had none) and `drafts` the `safety_class` of each successor its
    `## Dispositions` block drafts. Both are read from committed facts by the
    callers, never from run-state, so a resumed loop and the merge slot see the
    same inputs.

    THE TWO CALLERS AND THEIR SHAPES: the round scheduler asks BEFORE the merge,
    holding the session's own brief and the drafts it just wrote; the merge gate
    asks AFTER, holding the brief from the claimed spec and the drafts on the
    branch. Same question, same answer — which is why the ADJUDICATE phase stays
    in `NON_BUILD_PHASES` (it is still not a build) and this dial, not the
    phase set, decides whether a round is drawn."""
    mode = adjudication_review(docs)
    if mode == "never":
        return False
    if mode == "always":
        return True
    if str(brief or "").strip().lower() in _REVIEW_OWED_BRIEFS:
        return True
    return any(
        str(cls or "").strip().lower() in _REVIEW_OWED_CLASSES for cls in (drafts or ())
    )


# The two homes a branch may carry a work-item spec in, in the order that
# decides WHICH COPY GOVERNS when it carries both. ARCHIVE FIRST: a session that
# ran its close ritual has MOVED the spec to its terminal folder and FILLED it,
# so the terminal copy is what that session actually did, while an `active/`
# copy still standing beside it says only what the row was CLAIMED to do.
SPEC_HOMES = ("docs/archive/work", "docs/work")


def _spec_home_rank(path):
    """`(home precedence, path)` — the key `authoritative_spec` sorts on."""
    for rank, home in enumerate(SPEC_HOMES):
        if path.startswith(home + "/"):
            return (rank, path)
    return (len(SPEC_HOMES), path)


def authoritative_spec(paths):
    """The one repo-relative spec path that governs among `paths`, or None.

    ONE OWNING BOUNDARY for "which copy of this branch's spec answers for it",
    because that answer decides a review round. `agent_loop.dispositions_drafted`
    (does this judgement owe a round?) and `integrate._verdict_owed` (does this
    merge demand one?) read the same `## Dispositions` block through the same
    dial — and each used to walk the homes in its OWN order, the loop
    `docs/work` first and the gate `docs/archive/work` first. A branch
    momentarily carrying the spec in BOTH homes therefore handed the scheduler
    and the gate DIFFERENT drafts: the exact come-apart the shared dial exists
    to prevent, re-entered through the dial's input rather than through the dial.

    The callers legitimately differ in where they read from — the loop globs its
    own working tree, the gate asks `git show` against a branch it has not
    checked out — so what is shared here is the PRECEDENCE and not the read.
    Each caller hands over the candidates it found, in any order, and gets back
    the one the other would also have chosen."""
    ranked = sorted((str(p).replace("\\", "/") for p in paths), key=_spec_home_rank)
    return ranked[0] if ranked else None


def keep_nondependent(docs):
    """The orthogonal dial the ordinal cannot carry: may other lanes keep
    running while an approval is queued? Defaults FALSE — a queued
    approval drains the station, which is what `attended` and `autonomous`
    both did; only the retired `single-approve` level did otherwise."""
    table = process_config(docs).get("attestation")
    if isinstance(table, dict) and isinstance(table.get("keep_nondependent"), bool):
        return table["keep_nondependent"]
    legacy = legacy_approval(
        declared_policy(docs, "gate-policy", "attended"), "keep_nondependent"
    )
    return bool(legacy)


def spine_stage_of(root):
    """This repo's EFFECTIVE stage, through the common reader
    (`kitlib.stage.read_stage`) — the value `human_holds` compares the declared
    approval dial against, i.e. the input to who may approve.

    THE TRUST INVARIANT IS NOW TRUE BY CONSTRUCTION, and that is the whole point
    of this cut-over (WI-498 slice 5, ruled plan §3). The retired form scraped
    `stage=` off a comment on the generated `docs/gate` and justified itself by
    saying the file was freshness-gated, "so the cached value is either current
    or the `derived-gate` step is already red". THAT WAS NOT TRUE IN TWO PLACES
    the gate schedule map measured: the freshness step STANDS DOWN on a claimed
    branch, and `agent_loop`/`dispatch` hoist this value once per run and thread
    it down, so a mid-session approval was invisible to every later consumer.
    Both windows close here rather than being re-documented — the reader
    re-fingerprints the declared inputs on every call and derives fresh in memory
    when they have moved. It still never WRITES: regeneration stays the trunk
    regen points' auditable act.

    Returns None when the stage cannot be established at all — no `docs/stage`,
    an unparseable or hand-edited record, or a derivation that would not run.
    `human_holds` reads None as HUMAN-HELD, so every failure direction here ends
    in MORE human involvement, never less. That fail-safe is why this reader
    swallows the derivation error the CLI callers surface."""
    path = Path(root) / _kitstage.STAGE_FILE
    if not path.exists():
        return None
    try:
        record = _kitstage.read_stage(
            Path(root), lambda r: _kitstage.derive_via_subprocess(_SCRIPTS_DIR, r)
        )
    except (_kitstage.DerivationError, ValueError, OSError):
        return None
    stage = record.get("stage")
    return stage if isinstance(stage, str) and stage.startswith("DevStg-") else None


def _legacy_present(docs, legacy_name):
    return (Path(docs) / legacy_name).is_file()


def _in_legacy_window(value, legacy_values):
    """Is `value` EXACTLY one of the retired values a re-keyed dial still honours?

    A FUNCTION, NOT A BARE `in`, AND AN EXACT TYPE TEST, because Python's
    numeric tower makes the obvious spelling wrong three ways and each one fails
    silently — the migration window would swallow a malformed dial that the type
    check exists to name:

      * `True == 1`, so a `true` dial would pass for the ordinal 1 and take the
        window's silent pass instead of the wrong-type refusal it has earned;
      * `2.0 == 2`, so a float dial would too — a wrong-typed value falling
        through to a default with no diagnostic, which IS the failure this
        table's type check was written for;
      * an unhashable value (`[4]`, an inline table) raises `TypeError` from
        `in` against a set — and `config_conflicts` promises its callers it
        returns a list and never raises, because two of the three call it from
        inside an exit-code contract.

    `type(value) is int` refuses all three at once: `bool` and `float` are not
    `int`, and a non-int never reaches the membership test."""
    if type(value) is not int:
        return False
    return value in legacy_values


def _key_value_findings(data, section, key, kind):
    """Type, range and vocabulary findings for ONE declared dial ([] when absent
    or sound).

    Shared by both halves of `config_conflicts` — the legacy-file dials and the
    process.toml-only ones — because "a wrong-typed dial must never fall through
    to a default" is one rule, not two that happen to agree today."""
    table = data.get(section)
    if not (isinstance(table, dict) and key in table):
        return []
    value = table[key]
    legacy_values = PROCESS_KEY_LEGACY_VALUES.get((section, key))
    if legacy_values is not None and _in_legacy_window(value, legacy_values):
        # A value this dial USED to take, which the reader migrates and warns
        # about; refusing it here would be the kit refusing to start over a
        # spelling it already knows how to read. Anything outside the window —
        # including an out-of-range int — falls through to the findings below.
        return []
    if legacy_values is not None and type(value) is int:
        # AN INT OUTSIDE THE WINDOW: still refused, but by a message that names
        # the migration rather than the type. Whoever meets this is the one
        # person whose 0-4 dial was out of range BEFORE the re-key, and telling
        # them "expected str" while the four lines above silently accept 0-4 is
        # accurate and useless.
        return [
            "docs/{} [{}] {} = {!r} is the RETIRED 0-4 ordinal, out of range. "
            "There is no rung it meant, so it reads as the most conservative "
            "setting. Set it to a DevStg-* rung (or `{}` for 'nothing is "
            "human-held'); `bootstrap.py --migrate-config` converts an "
            "IN-range one for you.".format(
                PROCESS_TOML, section, key, value, _kitstage.BELOW
            )
        ]
    if _coerce(value, kind) is None:
        return [
            "docs/{} [{}] {} = {!r} is a {}, expected {} — a wrong-typed "
            "dial must never fall through to a default (a quoted "
            "`review_rounds` once meant NO review verdict was required).".format(
                PROCESS_TOML, section, key, value, type(value).__name__, kind
            )
        ]
    low_high = PROCESS_KEY_RANGES.get((section, key))
    if low_high and not (low_high[0] <= value <= low_high[1]):
        return [
            "docs/{} [{}] {} = {!r} is outside {}-{}. It falls back to the "
            "most conservative setting rather than being clamped: clamping a "
            "negative value would read as 'nothing is human-held' and "
            "silently disarm every approval hold in the repo.".format(
                PROCESS_TOML, section, key, value, low_high[0], low_high[1]
            )
        ]
    return _vocab_findings(section, key, value)


def _vocab_findings(section, key, value):
    """The VOCABULARY finding for one declared dial, [] when it is in its
    closed alphabet or the dial declares none. Its own function because the
    rung dial and a named-mode dial each need their own words, and the two
    messages together took `_key_value_findings` past its complexity ceiling."""
    vocab = PROCESS_KEY_VOCAB.get((section, key))
    if vocab is None:
        return []
    if vocab is not APPROVAL_DIAL_RUNGS:
        return _mode_vocab_findings(section, key, value, vocab)
    if str(value).strip() in vocab:
        return []
    # THE LEGACY ORDINAL IS NOT A CONFLICT. `approval_through` reads it,
    # translates it and warns; saying it twice — once as a refusal here and
    # once as a warning there — would make a kit upgrade look like a broken
    # config to a repo whose dial is merely old.
    if isinstance(value, int) and not isinstance(value, bool):
        return []
    return [
        "docs/{} [{}] {} = {!r} names no rung. Legal values are {} (and "
        "`{}` for 'nothing is human-held'). It falls back to the most "
        "conservative setting rather than to what was probably meant: an "
        "unrecognized dial that guessed would read as LESS human "
        "involvement than the owner asked for.".format(
            PROCESS_TOML,
            section,
            key,
            value,
            ", ".join("`{}`".format(r) for r in _kitladder.STAGE_ORDER),
            _kitstage.BELOW,
        )
    ]


def mode_word(value):
    """A named-mode dial's value as its readers compare it — trimmed and
    lowercased — or None for a value that is not text. ONE normalization for
    the reader and the validator, so a value the reader honours is never
    refused and a value it would not honour always is.

    Implements: SR-225, LLR-282
    """
    return value.strip().lower() if isinstance(value, str) else None


def _mode_vocab_findings(section, key, value, vocab):
    """A named-mode dial's vocabulary finding, in its own words: the rung
    message would tell its reader to pick a `DevStg-*` rung for a dial that
    takes none."""
    if mode_word(value) in vocab:
        return []
    return [
        "docs/{} [{}] {} = {!r} is not one of {}. An unrecognized value is "
        "refused rather than guessed at.".format(
            PROCESS_TOML,
            section,
            key,
            value,
            ", ".join("`{}`".format(v) for v in sorted(vocab)),
        )
    ]


def config_conflicts(docs):
    """The SN-028 MIXED-CONFIG refusal (plan §11.8): refusal strings naming
    every dial declared in BOTH `docs/process.toml` and its legacy one-word
    file, plus one line when process.toml exists but does not parse.

    Returns a LIST and never raises. Three entry points read policy without
    ever passing through `agent_loop.main` — `dispatch.run`, `intake`'s
    adjudication arm and `integrate`'s verdict gate — so the refusal has to
    live where the value is read, not at five call sites; and `dispatch.run`
    sits in the tick loop's caller, where a raised exception would rewrite an
    exit-code contract. Callers fold these into their own refusal lists.

    A downstream adopter never meets this un-aided: `bootstrap.py
    --migrate-config` converts the legacy files and deletes them, and both
    bootstrap and the documented re-sync run it.

    Implements: SR-137, SR-139, LLR-155
    """
    path = _process_toml_path(docs)
    if not path.is_file():
        return []
    data = read_toml(path)
    if not isinstance(data, dict):
        return [
            "docs/{} does not parse — every policy dial would silently read "
            "its default. Fix the file; do not delete it.".format(PROCESS_TOML)
        ]
    out = []
    for (section, key), kind in sorted(PROCESS_ONLY_KEYS.items()):
        out.extend(_key_value_findings(data, section, key, kind))
    for legacy_name in sorted(PROCESS_KEYS):
        section, key, kind = PROCESS_KEYS[legacy_name]
        table = data.get(section)
        if not (isinstance(table, dict) and key in table):
            continue
        out.extend(_key_value_findings(data, section, key, kind))
        if _legacy_present(docs, legacy_name):
            out.append(
                "policy '{}' is declared TWICE - docs/{} [{}] {} and the legacy "
                "docs/{}. Run `python project-trajectory/scripts/bootstrap.py "
                "--migrate-config --dest .` from your kept kit checkout to fold "
                "the legacy file in and delete it; a mixed config is refused, "
                "never resolved by precedence.".format(
                    legacy_name, PROCESS_TOML, section, key, legacy_name
                )
            )
    return out


# The coordinator dials that live once in docs/stack.ini [agent-loop] instead of
# being duplicated across the agent-resume.{cmd,sh,command} launchers (IF-068,
# WI-274 part B). Each maps a stack.ini key to the AGENT_* env slot it now backs.
# `lanes` (WI-381, concurrency-v2 §A4.3) is the dispatcher's worker-lane
# ceiling: the TEMPLATE seeds 2, but an ABSENT key means 1 — docs/stack.ini is
# adopter-owned, so a re-sync never writes the key and a code default of 2
# would upgrade a long-adopted repo into concurrency silently.
AGENT_LOOP_DIALS = ("jobs", "model", "model-map", "lanes")


def read_agent_loop_config(docs):
    """The declared coordinator dials — the ``[agent-loop]`` section of
    ``docs/stack.ini`` (IF-068, WI-274). Returns a dict of the present dial keys
    (``jobs`` / ``model`` / ``model-map`` / ``lanes``) with surrounding
    whitespace stripped;
    an empty value, absent key/section/file, or an unreadable/malformed stack.ini
    all yield ``{}`` for that key (fail-soft — the AGENT_* env slots and the
    built-in defaults still apply, so a repo without the section behaves exactly
    as before, never-breaking).

    This is the DECLARED-FILE tier of the coordinator-dial precedence
    ``CLI flag > AGENT_* env > declared file > built-in default`` that
    ``agent_loop.main`` applies (so a one-dial owner change edits ONE file, not
    the same value in three launchers)."""
    try:
        # An absent file reads None; an unreadable or malformed one degrades to
        # {} rather than crashing the loop.
        cp = _kitconfig.read_stack_ini(Path(docs) / "stack.ini")
    except _kitconfig.StackIniError:
        return {}
    if cp is None or not cp.has_section("agent-loop"):
        return {}
    out = {}
    for key in AGENT_LOOP_DIALS:
        if cp.has_option("agent-loop", key):
            val = cp.get("agent-loop", key).strip()
            if val:
                out[key] = val
    return out


def resolve_coordinator_dials(args, docs):
    """``(model, model_map)`` for the session engine, each resolved by the
    IF-068 precedence ``CLI flag > AGENT_* env > declared file > built-in
    default`` (WI-274 part B). ``args.model``/``args.model_map`` are ``None``
    when their flag was not passed; an empty env or declared value falls
    through (the launchers' "empty slot = default" convention, so the env path
    keeps working unchanged). Kept OUT of ``agent_loop.main`` so that hot
    function's complexity does not grow (the ratchet's escape hatch). (The
    ``jobs`` dial retired with the parallel dispatcher at
    concurrency-restructure Phase 5; a declared ``[agent-loop] jobs`` value is
    ignored.)"""
    dials = read_agent_loop_config(docs)
    model = (
        args.model
        if args.model is not None
        else (os.environ.get("AGENT_MODEL") or dials.get("model", ""))
    )
    model_map = (
        args.model_map
        if args.model_map is not None
        else (os.environ.get("AGENT_MODEL_MAP") or dials.get("model-map", ""))
    )
    return model, model_map


# What a `docs/work/pause` we cannot parse says. Fail-CLOSED: a broken pause
# file must never read as "not paused", and the message routes the human to the
# only two fixes. gen_trajectory.py carries a byte-identical copy (it does not
# import this coordinator layer); a test pins the two equal.

__all__ = (
    "read_declared",
    "PROCESS_TOML",
    "PROCESS_KEYS",
    "PROCESS_ONLY_KEYS",
    "PROCESS_KEY_RANGES",
    "PROCESS_KEY_VOCAB",
    "PROCESS_KEY_LEGACY_VALUES",
    "_process_toml_path",
    "process_config",
    "read_toml_text",
    "read_toml",
    "_coerce",
    "declared_policy",
    "LEGACY_APPROVAL",
    "APPROVAL_DIAL_RUNGS",
    "LEGACY_DIAL_ORDINALS",
    "APPROVAL_FALLBACK",
    "LEGACY_ATTESTATION_KEY",
    "legacy_approval",
    "approval_through",
    "_retired_dial_note",
    "LADDER_RUNGS",
    "APPROVAL_RUNGS",
    "SPINE_APPROVAL_RUNGS",
    "human_holds",
    "human_approves",
    "human_approves_spine",
    "loop_held_status_refusal",
    "final_review",
    "complete_review",
    "ADJUDICATION_REVIEW_MODES",
    "_REVIEW_OWED_CLASSES",
    "_REVIEW_OWED_BRIEFS",
    "adjudication_review",
    "DECISION_RECORDING_MODES",
    "decision_recording",
    "adjudication_review_owed",
    "SPEC_HOMES",
    "_spec_home_rank",
    "authoritative_spec",
    "keep_nondependent",
    "spine_stage_of",
    "_legacy_present",
    "_in_legacy_window",
    "_key_value_findings",
    "_vocab_findings",
    "mode_word",
    "_mode_vocab_findings",
    "config_conflicts",
    "AGENT_LOOP_DIALS",
    "read_agent_loop_config",
    "resolve_coordinator_dials",
)
