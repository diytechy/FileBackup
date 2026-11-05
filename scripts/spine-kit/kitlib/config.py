"""Declared policy readers: process toggles, stack-step selectors and console encoding.

TWO READERS, ONE THEME: `first_declared_line` (and its two adapters) for the
one-word `docs/<dial>` files, and `process_check` for a `[checks]` toggle in
`docs/process.toml` (with `process_check_text` beside it for a `[checks]` key
whose value is text, such as a declared start commit). They are the two halves
of the SN-028 dual-read window — the same question asked of the legacy file
and of the TOML that supersedes it — so a caller resolving a dial reaches for
exactly one module. `assumption_gate_enabled` reads one more `[checks]` toggle,
the one that ships off and so fails off rather than on. Under all of them sits
`read_toml_text`, the one "TOML text, or None when it does not parse" step a
caller holding text rather than a file reaches for (WI-821).

THE BEHAVIOUR THAT HAD FIVE HOMES (census 2026-08-12, `repo-lock.md` §8.2;
confirmed independently by the 2026-08-19 review, H-09). A declared-policy file
under `docs/` — `docs/subagent-gate` and the legacy one-word dials — states
ONE word, and every reader answers the same question: what is the first
line that is neither blank nor a comment? That question was answered by
`agent_common.read_declared`, `subagent_gate.read_declared`, and three separate
`_first_declared_line` copies in `bootstrap.py`, `check_privacy.py` and
`check_trajectory.py`. The copies carried a prose claim of equivalence that was
FALSE in two of the five, and `tests/test_rule_sync.py` had to pin them equal
by value to contain the drift.

`first_declared_line` below is that rule, stated once. The two other signatures
are kept as THIN ADAPTERS rather than harmonized away, because both of their
divergences are deliberate contracts their call sites depend on:

  * `read_declared(path, default)` substitutes a caller-supplied default for the
    absent/empty case instead of `None`.
  * `read_declared_lower(path)` lowercases and answers `""` — not `None` — for
    absent, so it composes with a closed, case-folded vocabulary without a
    None-check at every call site.

Making them adapters over one rule is what the pins were standing in for: the
copies can no longer disagree, so drift is UNREPRESENTABLE rather than detected.
"""

import configparser
import re
import sys
import tomllib

from . import ladder as _kitladder
from pathlib import Path

__all__ = [
    "assumption_gate_enabled",
    "first_declared_line",
    "MISPLACED_PRIVACY_READING",
    "policy_declaration",
    "process_check",
    "process_check_text",
    "read_declared",
    "read_declared_lower",
    "read_stack_ini",
    "read_toml_text",
    "red_rounds_max",
    "reviewer_dials",
    "utf8_console",
    "step_paths",
    "RETIRED_STAGE_ALIASES",
    "STACK_INI",
    "StackIniError",
    "step_threshold",
]

# The declared product toolchain's one named location, repo-relative and in
# POSIX form. Each site keeps its own constant's name and type, derived from it.
STACK_INI = "docs/stack.ini"


class StackIniError(Exception):
    """`docs/stack.ini` exists but could not be read or parsed. The message is
    the parser's or the OS's, and names the file. Deliberately not a
    `ValueError`, so no reader's broad `except` catches it by accident: each
    one maps it onto the outcome it already has for a malformed file."""


def read_stack_ini(path, *, fold_keys=True):
    """The one parse of `docs/stack.ini`: the parsed profile, or None when the
    path names no file.

    The parse options, stated here and nowhere else: interpolation is off, so
    a `%` in a value is literal; `=` and `:` both delimit a key; `#` and `;`
    comment whole lines only, so `src = lib ; note` reads `lib ; note`; a
    duplicate section or key is an error; a `[DEFAULT]` section's keys appear
    in every section; and keys are folded to lower case unless `fold_keys` is
    false, for a section keyed by paths or names. The bytes are UTF-8 with an
    optional byte-order mark, and a stray byte reads as U+FFFD.

    No cache, no defaults and no value checks: each call reads the file, and
    each reader keeps its own defaults and failure direction. Anything that is
    neither absent nor parsed (a directory or unreadable file at the path, any
    parse error) raises `StackIniError`.

    Implements: SR-007
    """
    path = Path(path)
    if not path.exists():
        return None
    cp = configparser.ConfigParser(interpolation=None)
    if not fold_keys:
        cp.optionxform = str
    try:
        text = path.read_text(encoding="utf-8-sig", errors="replace")
        cp.read_string(text, source=str(path))
    except (configparser.Error, OSError) as exc:
        raise StackIniError(str(exc)) from exc
    return cp


def read_toml_text(text):
    """`tomllib.loads(text)`, or None when it does not parse.

    The TEXT step: for a caller that already holds the document (a `+++`
    frontmatter block, a registry read as one string) and so has no file left
    to hand a path reader. ONE HOME since WI-821: `agent_policy.read_toml_text`,
    `kitlib.spine`'s needs-file reader and `kitlib.station.parse_frontmatter`
    each carried this guard as a copy.

    Implements: SR-166, LLR-181
    """
    try:
        return tomllib.loads(text)
    except tomllib.TOMLDecodeError:
        return None


def first_declared_line(path):
    """The first non-empty, non-comment line of a declared-policy file, or None.

    None means NOTHING IS DECLARED — the file is absent, unreadable, empty, or
    holds only blanks and `#` comments. It never means "the file declares the
    empty string": a policy file with nothing to say and a policy file that does
    not exist are the same statement to every caller, which is why one sentinel
    covers both.

    Reads with `errors="replace"` and catches `OSError`, so an unreadable or
    mis-encoded dial degrades to "undeclared" rather than crashing a check —
    the fail-direction each caller then decides for itself.

    Contract:
      Inputs:  path: path-like to a declared-policy file (may not exist)
      Outputs: str | None — the declared token, stripped; None if undeclared
    """
    try:
        text = Path(path).read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None
    for line in text.splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            return line
    return None


def process_check(root, key):
    """One `[checks]` toggle out of `docs/process.toml`, or None when that file
    has nothing to say about `key` (the caller falls through to its legacy
    one-word file — the SN-028 dual-read window).

    THE SECOND BEHAVIOUR THIS MODULE COLLECTS, and the copies' own stated reason
    for staying apart did not describe them. `check_trajectory._process_check`
    and `gen_okf._process_check` each argued that the `[checks]` POLICY — "which
    key, which fail-direction, which residual" — was the caller's and not a
    library's. Only the first of those three is the caller's, and it is a
    PARAMETER; the fail-direction and the residual were hardcoded identically in
    both bodies, so nothing module-specific was ever being encoded. What the
    duplication actually bought was a `tests/test_rule_sync.py` pin holding two
    identical bodies equal (WI-448 slice 4 retires it).

    `subagent_gate.read_process_policy` is deliberately NOT a third copy folded
    in here: its dial is a WORD, not a bool, and it answers a distinct
    `UNPARSEABLE` sentinel so `decide()` can fail closed. Same file, different
    question.

    A file that exists but does not parse, or a key whose value is not a bool,
    reads ON: a check that silently stops running is the failure worth avoiding,
    so the residual is loud rather than permissive.

    Contract:
      Inputs:  root: path-like repo root; key: the `[checks]` key to read
      Outputs: bool | None — the declared toggle; None if undeclared
    """
    path = Path(root) / "docs" / "process.toml"
    if not path.is_file():
        return None
    try:
        # utf-8-sig: a BOM is not legal TOML but is invisible to a shell read.
        data = tomllib.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeDecodeError, tomllib.TOMLDecodeError):
        return True  # unparseable but present: fail loud, never a quiet opt-out
    table = data.get("checks")
    value = table.get(key) if isinstance(table, dict) else None
    if value is None:
        return None
    return value if isinstance(value, bool) else True


# The two privacy keys, and the reading each takes when the parse holds it
# under any table other than [policies]: the gate on, the reviewer required.
# A privacy gate a person declared, misplaced by hand, must never read off.
MISPLACED_PRIVACY_READING = {"privacy_check": True, "privacy_review": "require"}


def policy_declaration(data, key):
    """`[policies] key`'s value in one parse `data` of `docs/process.toml`
    (a dict, or None when there is no parse), or None when it declares none.

    THE ONE HOME of the misplaced-privacy-key rule, which every reader of the
    two privacy keys takes: the privacy checker's gates, the git hooks' policy
    answer and the agent layer's `declared_policy`. A privacy key the parse
    holds under any other table (another section, a `[policies]` sub-table,
    the root, an array of tables) reads `MISPLACED_PRIVACY_READING`, whatever
    its value and whatever `[policies]` or the legacy file says. The parse
    alone answers: a key's name inside a string is text, not a key, and
    declares nothing.

    Implements: SR-031, LLR-031"""
    if key in MISPLACED_PRIVACY_READING and _held_elsewhere(data, key):
        return MISPLACED_PRIVACY_READING[key]
    table = _policies_table(data)
    return table.get(key) if table is not None else None


def _policies_table(data):
    """The `[policies]` table of one parse `data`, or None when there is none."""
    table = data.get("policies") if isinstance(data, dict) else None
    return table if isinstance(table, dict) else None


def _held_elsewhere(data, key):
    """Whether the parse `data` holds `key` in any table but directly in
    `[policies]` (whose own sub-tables count as elsewhere)."""
    if not isinstance(data, dict):
        return False
    table = _policies_table(data)
    nodes = [v for v in data.values() if v is not table]
    nodes += list(table.values()) if table is not None else []
    return key in data or any(_holds_key(node, key) for node in nodes)


def _holds_key(node, key):
    """Whether `key` names a key in any table within one parsed value."""
    if isinstance(node, dict):
        return key in node or any(_holds_key(v, key) for v in node.values())
    if isinstance(node, list):
        return any(_holds_key(v, key) for v in node)
    return False


def assumption_gate_enabled(docs):
    """Whether `[checks] assumption_gate` in `<docs>/process.toml` turns the
    assumption gate on: true only when the key reads `true`.

    THE THIRD FAIL-DIRECTION, and deliberately not `process_check`'s. That
    reader answers ON for a file it cannot parse, because the checks it
    toggles are on by default and a silent opt-out is the failure it guards
    against. This gate is OFF by default: it asks every requirement for a
    written argument, a cost a project opts into. So an absent file, an
    unparseable one, an absent key and any value but `true` all read off, and
    the gate's steps print their findings as advisories instead of failing.

    Implements: SR-205, LLR-242

    Contract:
      Inputs:  docs: path-like to the project's `docs/` directory
      Outputs: bool — True only for a readable `assumption_gate = true`
    """
    try:
        data = tomllib.loads(
            (Path(docs) / "process.toml").read_text(encoding="utf-8-sig")
        )
    except (OSError, UnicodeDecodeError, tomllib.TOMLDecodeError):
        return False
    table = data.get("checks")
    return isinstance(table, dict) and table.get("assumption_gate") is True


# `[reviewer] final_reviewer`'s two words (WI-887). Any other present value is
# a malformed setting: retention off and fresh.
FINAL_FRESH, FINAL_PERSISTED = "fresh", "persisted"


def reviewer_dials(root):
    """`(context_reset_pct, final_reviewer)` from `[reviewer]` in
    `<root>/docs/process.toml`, the ONE reader of that table: the keep
    operation retains a loop review session by it (`session_keep.keep_config`),
    and the merge gate's evidence readers admit the persisted final reviewer's
    round by it (`kitlib.verdict.review_logs`), so the two cannot disagree on
    the mode.

    `context_reset_pct` is an int in 0..100, and 0, the shipped value, is OFF:
    no review session is retained. `final_reviewer` is `"persisted"` or
    `"fresh"`, the shipped value. THE MODE IS RESOLVED HERE, FROM BOTH DIALS:
    a persisted final reviewer is a retained session, so `"persisted"` reads
    `"fresh"` while retention is off, and no reader can admit a retained
    final round the keep operation would never have kept. A MALFORMED DIAL
    READS OFF: an absent, unreadable or unparseable file, a missing table, a
    percent that is not an int in range (a bool is not one), and a final
    value present but neither `"fresh"` nor `"persisted"` (another word or
    another type) read `0` and `"fresh"`, so a malformed dial can only leave
    review retention off and the final reviewer fresh. An absent final value
    is the shipped `"fresh"`.

    Implements: SR-227, SR-239, LLR-270
    """
    try:
        text = (Path(root) / "docs" / "process.toml").read_text(encoding="utf-8-sig")
        table = tomllib.loads(text).get("reviewer")
    except (OSError, UnicodeDecodeError, tomllib.TOMLDecodeError):
        table = None
    table = table if isinstance(table, dict) else {}
    pct = table.get("context_reset_pct")
    pct_ok = isinstance(pct, int) and not isinstance(pct, bool) and 0 <= pct <= 100
    final = table.get("final_reviewer", FINAL_FRESH)
    if not pct_ok or final not in (FINAL_FRESH, FINAL_PERSISTED):
        return 0, FINAL_FRESH
    persisted = pct > 0 and final == FINAL_PERSISTED
    return pct, FINAL_PERSISTED if persisted else FINAL_FRESH


# `[build] red_rounds_max`'s shipped value: read only for an absent `[build]`
# table or an absent key, never for a value this reader cannot use.
RED_ROUNDS_MAX_DEFAULT = 3
_TOML_HEADER_RE = re.compile(r"^\s*\[\[?\s*([A-Za-z0-9_-]+)\s*\]\]?\s*(#.*)?$")


def _process_toml_at(text, section, key):
    """`docs/process.toml:<line>` for `key` as the file declares it: a
    `key = ...` line under `[section]` (`section` None: before any header),
    or a `[key]` / `[[key]]` header. Plain `docs/process.toml` when no line
    matches, such as a dotted key or an inline table, which the parse reads
    but no single line names.

    Implements: SR-242, LLR-343
    """
    current = None
    assign = re.compile(r"^\s*{}\s*=".format(re.escape(key)))
    for lineno, raw in enumerate(text.splitlines(), 1):
        head = _TOML_HEADER_RE.match(raw)
        if head and section is None and head.group(1) == key:
            return "docs/process.toml:{}".format(lineno)
        if head:
            current = head.group(1)
        elif current == section and assign.match(raw):
            return "docs/process.toml:{}".format(lineno)
    return "docs/process.toml"


def red_rounds_max(root):
    """`(maximum, None)` for `<root>/docs/process.toml`'s
    `[build] red_rounds_max`, or `(None, refusal)`. THE ONE READER of the key:
    the worker's preflight and the dispatcher's pre-claim rung both call it,
    so a setting one of them refuses never starts a session through the other.

    An absent `[build]` table or key reads the shipped 3. Everything else this
    reader cannot use is refused, naming the file and the cause: an absent,
    unreadable or unparseable file, a `build` that is not a table (naming its
    line), and a value that is not an int, is a bool, or is below 1 (naming
    its line and the key). Never read as off: an unbounded cap is the
    fail-open side. tomllib reports no position for a valid key, so the line
    is found by scanning the text.

    Implements: SR-242, LLR-343
    """
    try:
        text = (Path(root) / "docs" / "process.toml").read_text(encoding="utf-8-sig")
        data = tomllib.loads(text)
    except (OSError, UnicodeDecodeError) as exc:
        return None, "docs/process.toml cannot be read: {}".format(exc)
    except tomllib.TOMLDecodeError as exc:
        return None, "docs/process.toml does not parse: {}".format(exc)
    table = data.get("build", {})
    if not isinstance(table, dict):
        return None, "{}: `build` is a {}, not a table".format(
            _process_toml_at(text, None, "build"), type(table).__name__
        )
    value = table.get("red_rounds_max", RED_ROUNDS_MAX_DEFAULT)
    if type(value) is int and value >= 1:
        return value, None
    return None, (
        "{}: [build] red_rounds_max = {!r} is refused; it must be an integer "
        "of at least 1 (an absent key reads {})".format(
            _process_toml_at(text, "build", "red_rounds_max"),
            value,
            RED_ROUNDS_MAX_DEFAULT,
        )
    )


def process_check_text(root, key):
    """One text-valued `[checks]` key out of `docs/process.toml` — a commit id,
    say — or None when the file declares nothing for it.

    A SECOND READER BESIDE `process_check`, NOT A MODE OF IT, because the two
    fail in opposite directions. A toggle has a conservative answer to fall back
    on when it cannot be read (ON: the check keeps running). A declared text
    has none: a start commit the file meant but this reader cannot see is not
    "no start", and treating it as one would judge a different history than the
    one declared. So an unparseable file, or a value that is not a string,
    RAISES and the caller says what it could not do; it never guesses.

    An empty or blank string is the same statement as an absent key: the
    shipped template declares the key visibly at `""`, and that must read as
    "nothing declared" rather than as a value to act on.

    Contract:
      Inputs:  root: path-like repo root; key: the `[checks]` key to read
      Outputs: str | None — the declared text, stripped; None if undeclared
               or empty
      Raises:  ValueError — the file is present but does not parse, or the
               key holds something other than a string
    """
    path = Path(root) / "docs" / "process.toml"
    if not path.is_file():
        return None
    try:
        data = tomllib.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeDecodeError, tomllib.TOMLDecodeError) as exc:
        raise ValueError("{} does not parse: {}".format(path, exc)) from exc
    table = data.get("checks")
    value = table.get(key) if isinstance(table, dict) else None
    if value is None:
        return None
    if not isinstance(value, str):
        raise ValueError(
            "{} [checks] {} = {!r} is not a string".format(path, key, value)
        )
    return value.strip() or None


def read_declared(path, default):
    """`first_declared_line`, with `default` for the undeclared case.

    The reader for the LEGACY half of the SN-028 dual-read window; new policy
    reads go through `agent_common.declared_policy`, which prefers
    `docs/process.toml`.

    NOT A READER OF `docs/gate`, though this docstring said so until WI-498
    slice 4 (the gate schedule map's reader E). No call site has ever put it to
    that file — `docs/gate` is a deliberate NON-row in `PROCESS_KEYS`, and every
    live gate reader spelled its own one-line parse out locally. The function is
    unchanged and undeprecated; only the claim was false.

    Contract:
      Inputs:  path: path-like; default: value to answer when undeclared
      Outputs: str | type(default) — the declared token, else `default`
    """
    value = first_declared_line(path)
    return default if value is None else value


def read_declared_lower(path):
    """`first_declared_line` lowercased, with `""` for the undeclared case.

    The subagent-gate reader's contract: it compares the token against a closed,
    case-folded vocabulary and documents its own `policy` parameter as
    `"" = off`, so the empty string has to be the sentinel for it to compose
    without a None-check at every call site. Deliberate divergence, not a bug to
    harmonize away — and now expressed as an adapter over the shared rule rather
    than as a fifth copy of it.

    Contract:
      Inputs:  path: path-like to a declared-policy file (may not exist)
      Outputs: str — the declared token, lowercased; `""` if undeclared
    """
    return (first_declared_line(path) or "").lower()


def utf8_console():
    """Emit UTF-8 on stdout/stderr whatever the OS console codepage is.

    A non-ASCII work-item title, path or box-drawing character must not raise
    `UnicodeEncodeError` on a legacy Windows cp1252 console. Python 3.7+ streams
    expose `.reconfigure`; the guard covers a stream that does not (a captured
    or already-wrapped stream), where there is nothing to do and nothing to fail.

    Contract:
      Inputs:  none
      Outputs: None — best-effort, never raises
    """
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8")
        except (AttributeError, ValueError):
            pass


def step_paths(profile):
    """Declared repo-relative fnmatch patterns, keyed by step; blanks opt out.

    Commas or whitespace separate patterns. Values belong to the adopter's
    stack, so the reader never infers paths from an executable or baseline.

    Implements: SR-006, LLR-291
    """
    if profile is None:
        return {}
    return {
        section[5:].strip(): tuple(
            profile.get(section, "paths").replace(",", " ").split()
        )
        for section in profile.sections()
        if section.startswith("step:")
        and profile.get(section, "paths", fallback="").strip()
    }


# THE LEGACY `gates =` TRANSLATION, and it preserves an adopter's effective
# behavior rather than the tag's face value (WI-498 slice 2). A `gates =` list
# named the BARS a step ran at, and the bar was a MIN over every in-scope row:
# `DevStg-Reqs` is the floor every repo sits at, while `DevStg-Tests` was reached
# only by a spine already fully decomposed and TC'd — which is the DevStg-Impl
# RUNG — and `DevStg-Impl` was never reached at all under the OI-30 D2 ceiling.
# So the rung that reproduces each listed bar under an at-or-above rule is:
RETIRED_STAGE_ALIASES = {  # check_vocab: allow
    # The Reqs bar IS the floor every repo sits at.
    "G1": _kitladder.STAGE_REQS,  # check_vocab: allow
    # The Tests bar was reached ONLY by a spine already fully decomposed and
    # TC'd, which on the ladder is the DevStg-Impl RUNG — three above the word
    # it shares with the bar.
    "G2": _kitladder.STAGE_IMPL,  # check_vocab: allow
    "G3": _kitladder.STAGE_IMPL,  # check_vocab: allow
    # The retired bar prefix (2026-08-18): its release alias resolves to
    # `DevStg-Impl`, NOT to `DevStg-Release`: that bar never certified the
    # Release rung, and the alias carries the correction.
    "DevBar-Reqs": _kitladder.STAGE_REQS,  # check_vocab: allow
    "DevBar-Tests": _kitladder.STAGE_IMPL,  # check_vocab: allow
    "DevBar-Release": _kitladder.STAGE_IMPL,  # check_vocab: allow
}

_LEGACY_BAR_THRESHOLD = {
    _kitladder.STAGE_REQS: _kitladder.STAGE_NEEDS,
    _kitladder.STAGE_TESTS: _kitladder.STAGE_IMPL,
    _kitladder.STAGE_IMPL: _kitladder.STAGE_IMPL,
}

# Sections already warned about, so the notice is ONCE PER RUN as promised and
# not once per `steps()` call — the plan is built two or three times in a single
# invocation (the lane map resolves at ALL; `--list` and the run each rebuild),
# and a migration notice repeated per rebuild reads as a malfunction.
_LEGACY_GATES_WARNED = set()


def step_threshold(profile, section):
    """The rung a declared `[step:<name>]` becomes relevant at.

    `from-stage = <rung>` is the declared spelling: any of the eight ladder rungs,
    and the step runs whenever the repo is AT OR ABOVE it. Default `DevStg-Impl`,
    unchanged in value from the retired `gates =` default — a project-specific
    gate grades a built thing.

    `gates = <space/comma list>` IS ACCEPTED AND TRANSLATED, with one stderr line
    per run. It is the retired membership spelling, and unlike the `--stage` CLI
    aliases the FILE can be named here, so the notice says which section to fix
    rather than leaving an adopter to guess. The lowest listed bar picks the rung
    (`_LEGACY_BAR_THRESHOLD`); the retired `G1|G2|G3` tags translate first,  check_vocab: allow
    exactly as they always did. Both spellings at once is an authoring error and
    fails LOUDLY, like every other profile error — silently preferring one would
    make a step's real threshold unreadable from the file.

    Implements: SR-006, LLR-291
    """
    has_new = profile.has_option(section, "from-stage")
    has_old = profile.has_option(section, "gates")
    if has_new and has_old:
        sys.exit(
            "check: docs/stack.ini [{}] declares both `from-stage` and the "
            "retired `gates` — keep `from-stage` and delete `gates`".format(section)
        )
    if has_new:
        value = profile.get(section, "from-stage").strip()
        if value not in _kitladder.LADDER_RUNGS:
            sys.exit(
                "check: docs/stack.ini [{}] from-stage is {!r}; expected one of "
                "{}".format(section, value, "|".join(_kitladder.STAGE_ORDER))
            )
        return value
    if not has_old:
        return _kitladder.STAGE_IMPL
    bars = []
    for tok in profile.get(section, "gates").replace(",", " ").split():
        tok = RETIRED_STAGE_ALIASES.get(tok, tok)
        if tok not in _LEGACY_BAR_THRESHOLD:
            sys.exit(
                "check: docs/stack.ini [{}] gates has {!r}; expected a "
                "space/comma list of {}".format(
                    section, tok, "|".join(_LEGACY_BAR_THRESHOLD)
                )
            )
        bars.append(tok)
    if not bars:
        return _kitladder.STAGE_IMPL
    threshold = min((_LEGACY_BAR_THRESHOLD[b] for b in bars), key=_kitladder.stage_ord)
    if section not in _LEGACY_GATES_WARNED:
        _LEGACY_GATES_WARNED.add(section)
        print(
            "check: docs/stack.ini [{}] uses the RETIRED `gates =` membership "
            "list — reading it as `from-stage = {}`. Selection is now AT OR "
            "ABOVE one rung (OI-51); update the section to say so.".format(
                section, threshold
            ),
            file=sys.stderr,
        )
    return threshold
