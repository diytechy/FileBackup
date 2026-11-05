"""Loop provenance: the trailer every commit the unattended loop makes carries,
and the marker that tells a commit floor a commit is the loop's.

WHY IT EXISTS. A status change on a rung the approval level holds for a human
is supposed to mean a human judged. The one observation that would show
otherwise is such a change arriving in a commit the loop made, and that is
observable only if every loop-made commit says it is one. Trailers the loop
wrote before this module appeared on some of its commits and nothing checked
them, so a missing one proved nothing. Two facts make the mark total:

  * THE MARKER (`LOOP_SESSION_ENV`) is set in the loop's OWN process
    environment, once per run (`mark_loop_process`), by the dispatcher and by
    the loop's main entry outside interactive mode. Every process the loop
    starts inherits it — worker sessions, refresh subprocesses, the hooks their
    commits trigger — and a person's shell does not, because no launcher script
    sets it. So "who made this commit" is answered by the process, not by the
    clock: a person committing in another checkout while the loop runs is not
    the loop.
  * THE TRAILER (`Loop-Session: <session>`) is what a marked commit must carry,
    and a commit floor refuses a marked commit without a valid one
    (`loop_trailer_refusal`). With the floor in place, a commit WITHOUT the
    trailer is a person's, and a later check may treat the absence as meaning
    something.

WHERE THE FLOOR RUNS, and why more than once: the commit-msg hook checks a
marked commit as it is made, but hooks are opt-in per checkout, and plumbing
(`commit-tree`) and `--no-verify` commits never reach a hook at all. So the
merge slot re-checks every commit of a LOOP lane before it lands
(`integrate._loop_trailer_refusal`), under the same validity rule, whoever runs
the slot.

WHOSE LANE IT IS is read off the lane's commits, because the slot sees commits,
not processes (`loop_lane_window`). A lane is the loop's when its claim, or any
commit one of the loop's OWN WRITERS made in its range, carries the trailer -
the writers whose subjects `LOOP_WRITER_SUBJECTS` names, never a session's own
commit, which can sit in a person's lane. Once the loop's, every commit of the
lane is judged, and a person's commit there must carry the trailer or move to
the person's own lane; the commits BEFORE the lane's first marked loop-writer
commit (a lane a person claimed and started, which the loop later built) are
exempt from the trailer rule alone, since nothing then could have marked them.

A RE-CLAIM closes that window again (revision 36 of the review-churn plan's
rulings, "Headless coordinator legs are marked now"; D-015 and D-017 of
docs/decisions/coordinator-2026-10-14.toml): a lane a headless leg marked
lands headless, or the attended coordinator re-claims it before its own first
commit there. The re-claim is an empty commit in the lane - exactly one
parent, and the parent's tree - whose subject is `reclaim_subject(branch)` and
which carries no `Loop-Session` trailer at all. The commits after it are
exempt from the trailer rule until a loop-writer commit marks the lane again;
the commits before it stay judged, and the held-status rule still judges the
lane whole. A forged loop-writer subject still only makes a lane MORE
governed; the re-claim is the one record that makes a lane less governed, so
it is held to that one rule, to the commits after it, and to a shape checked
against its parent at every read. Where the commit-msg hook runs (hooks are
opt-in per checkout), a marked process cannot write a trailerless commit
through porcelain, because that hook refuses it; and a commit with the
trailer is never a re-claim, whatever wrote it.

VALID MEANS PRESENT AND WELL-FORMED. A trailer is a self-assertion, and there
is no record of the sessions a run started to check one against; at the slot,
where a lane spans runs, any well-formed session is accepted.

THE TRAILER IS A GIT TRAILER, so it lives in the message's final trailer block:
git reads trailers from the last paragraph only, and a trailer quoted in a
commit's body is not one. `with_loop_trailer` extends an existing block rather
than opening a second paragraph, because a second paragraph would hide the
block before it — the `WI:` trailers the loop's own evidence readers parse.

Pure and stdlib-only; importing no sibling script, only the process
environment, which is the one input the marker is. Windows and POSIX.

Contracts: IF-194 — the interface seam this module declares (process.md §8;
row of record in docs/requirements/interfaces.toml).

Contract IF-194: the loop's provenance vocabulary, by importer. `LOOP_TRAILER`
    and `LOOP_SESSION_ENV` name the trailer key and the marker variable.
    `format_loop_trailer(session)` renders the trailer line and raises
    ValueError on a session the grammar refuses; `parse_loop_trailer(message)`
    returns the session the message's LAST `Loop-Session` trailer names, or
    None when it carries none or the last is malformed;
    `loop_trailer_refusal(message, session)` returns a refusal naming the
    commit's subject when the trailer is missing, malformed, or (with a
    session given) names another session, else None. `loop_session()` reads the
    marker, `mark_loop_process()` sets it once per run keeping a well-formed
    inherited one, and `with_loop_trailer(message, session=None)` returns the
    message with the trailer appended to its trailer block when a session is
    given or the marker is set, and unchanged otherwise.
    `loop_writer_commit(message, branch)` is True when the message carries a
    well-formed trailer and a subject one of the loop's own writers composes
    (`LOOP_WRITER_SUBJECTS`) for `branch`; `reclaim_subject(branch)` composes
    the attended re-claim's subject, `reclaim: <branch> (attended)`;
    `loop_lane_window(commits, claimed, branch, boundary)` takes a lane's
    `(sha, message, parents, tree)` records oldest first, whether its claim
    carries the trailer, and a map of each parent outside the range to its
    tree, and returns None for a lane never marked or the records the trailer
    rule judges: those inside the open window, which opens at a loop claim or
    a loop-writer commit and closes at a re-claim (one parent, an unchanged
    tree, this branch's subject, no `Loop-Session` trailer).
"""

import os
import re
import secrets
import time

# The trailer key and the marker variable: ONE home each, read by every writer,
# every floor and the history check.
# Implements: SR-209, LLR-247
LOOP_TRAILER = "Loop-Session"
# Implements: SR-209, LLR-247
LOOP_SESSION_ENV = "KIT_LOOP_SESSION"

# A session id: a letter or digit, then up to 63 of letters, digits, `.`, `_`
# and `-`. Narrow on purpose — one token, no spaces, nothing a shell or a git
# trailer parser could split — so a value the floor accepts is one every reader
# reads the same way.
_SESSION = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}")
# One git trailer line: a token key, a colon, a value (possibly empty, which
# is what makes an empty `Loop-Session:` MALFORMED rather than absent).
_TRAILER_LINE = re.compile(r"^([A-Za-z0-9][A-Za-z0-9-]*)[ \t]*:[ \t]*(.*?)[ \t]*$")


def _lines(message):
    """The message's lines with git's comment lines dropped: a commit-msg hook
    is handed the message before git strips them."""
    text = str(message or "").replace("\r\n", "\n")
    return [ln for ln in text.split("\n") if not ln.startswith("#")]


def _subject(message):
    return next((ln.strip() for ln in _lines(message) if ln.strip()), "(no subject)")


def _trailer_block(message):
    """The `(key, value)` pairs of the message's final trailer block, in order:
    the last paragraph, when every line of it is trailer-shaped and it is not
    the subject. `[]` when there is none."""
    lines = _lines(message)
    while lines and not lines[-1].strip():
        lines.pop()
    block = []
    while lines and lines[-1].strip():
        block.insert(0, lines.pop())
    if not lines:  # the only paragraph is the subject's
        return []
    matches = [_TRAILER_LINE.match(ln) for ln in block]
    if not matches or not all(matches):
        return []
    return [(m.group(1), m.group(2)) for m in matches]


def _last_loop_value(message):
    """The value of the last `Loop-Session` trailer, or None when there is none.
    Keys compare case-insensitively, as git's do."""
    values = [
        v for k, v in _trailer_block(message) if k.lower() == LOOP_TRAILER.lower()
    ]
    return values[-1] if values else None


def format_loop_trailer(session):
    """The trailer line naming `session`; ValueError on a session the grammar
    refuses, so no writer can emit a trailer its own reader calls malformed.

    Implements: SR-209, LLR-247
    """
    session = str(session or "").strip()
    if not _SESSION.fullmatch(session):
        raise ValueError("not a loop session id: {!r}".format(session))
    return "{}: {}".format(LOOP_TRAILER, session)


def parse_loop_trailer(message):
    """The session the message's LAST `Loop-Session` trailer names, or None
    when it carries none or the last one is malformed. The last wins because a
    message is read the way git reads trailers, top to bottom, and a later line
    is the later statement.

    Implements: SR-209, LLR-247
    """
    value = _last_loop_value(message)
    return value if value is not None and _SESSION.fullmatch(value) else None


def loop_trailer_refusal(message, session=None):
    """A refusal naming the commit's subject, or None.

    Refused when the message carries no `Loop-Session` trailer, when its last
    one is malformed, or — `session` given — when it names another session.
    With no `session` (the merge slot, where a lane's commits may span runs)
    any well-formed trailer is the loop's.

    Implements: SR-209, LLR-247
    """
    subject = _subject(message)
    value = _last_loop_value(message)
    if value is None:
        return (
            "commit '{}' carries no {} trailer - a commit the loop makes ends "
            "with `{}: <session>`".format(subject, LOOP_TRAILER, LOOP_TRAILER)
        )
    if not _SESSION.fullmatch(value):
        return "commit '{}' carries a malformed {} trailer ({!r})".format(
            subject, LOOP_TRAILER, value
        )
    if session and value != str(session).strip():
        return "commit '{}' names loop session {}, not this run's {}".format(
            subject, value, str(session).strip()
        )
    return None


# THE SUBJECTS THE LOOP'S OWN WRITERS COMPOSE, one pattern each, `{branch}`
# standing for the lane's escaped name: the claim (on trunk), the refresh, the
# handback's partial close, its as-is residue commit, its quarantine, the
# mechanical adjudication close, and the telemetry commit. The writers keep
# their own format strings; `tests/test_loop_provenance.py` drives each real
# writer's message through `loop_writer_commit`, which is what holds the two
# together.
# Implements: SR-209, LLR-248
LOOP_WRITER_SUBJECTS = (
    r"claim: .+ -> active/{branch} \(bookkeeping\)",
    r"refresh: {branch} onto trunk .+",
    r"partial: .+ -> partial/ \(.*",
    r".+: the work so far, committed as-is \(partial close\)",
    r"handback: revert {branch} to a bar-inert artefact",
    r"adjudicate: .+ -> complete/ \(mechanical close\)",
    r"telemetry: session .+",
)


def loop_writer_commit(message, branch):
    """Did one of the loop's OWN WRITERS make this commit in `branch`'s lane? A
    well-formed trailer AND a subject a loop writer composes. A session's own
    commit carries the trailer too, but a session can work in a person's lane;
    only the loop's writers make a lane the loop's.

    Implements: SR-209, LLR-248
    """
    if parse_loop_trailer(message) is None:
        return False
    subject = _subject(message)
    name = re.escape(str(branch))
    return any(
        re.fullmatch(pattern.replace("{branch}", name), subject)
        for pattern in LOOP_WRITER_SUBJECTS
    )


def reclaim_subject(branch):
    """The subject of the attended coordinator's re-claim of `branch`: this is
    its one home, which the coordinator-cycle recipe calls when it writes one.
    It carries no claim suffix, so no claim reader matches it, and it matches
    no `LOOP_WRITER_SUBJECTS` pattern, so it never marks a lane.

    Implements: SR-209, LLR-248
    """
    return "reclaim: {} (attended)".format(branch)


def _reclaim(record, branch, trees):
    """Is this lane record `branch`'s re-claim? Deny by default: all four must
    hold, its tree checked against its parent's at every read (D-017).

    Implements: SR-209, LLR-248
    """
    _sha, message, parents, tree = record
    return (
        len(parents) == 1
        and parents[0] in trees
        and trees[parents[0]] == tree
        and _subject(message) == reclaim_subject(branch)
        and _last_loop_value(message) is None
    )


def loop_lane_window(commits, claimed, branch, boundary):
    """The lane records the trailer rule judges, or None for a person's lane.

    `commits` are the lane's `(sha, message, parents, tree)` records, OLDEST
    FIRST, `parents` a tuple of shas; `boundary` maps each parent outside the
    range to its tree; `claimed` is whether the lane's claim commit carries the
    trailer. The window is open from the claim when the loop claimed the lane,
    and opens at each loop-writer commit; what came before the first mark is
    the window a person worked in before the loop took the lane over, exempt
    from the trailer rule only (the held-status rule judges such a lane whole).
    A re-claim met while the window is open closes it, and is not judged
    itself; the commits after it are exempt until a loop writer marks the lane
    again. No mark at all: a person's lane, None. A lane ever marked returns a
    list, possibly empty.

    Implements: SR-209, LLR-248
    """
    commits = list(commits)
    trees = dict(boundary)
    trees.update((record[0], record[3]) for record in commits)
    marked = is_open = bool(claimed)
    window = []
    for record in commits:
        if loop_writer_commit(record[1], branch):
            marked = is_open = True
        elif is_open and _reclaim(record, branch, trees):
            is_open = False
            continue
        if is_open:
            window.append(record)
    return window if marked else None


def loop_session(environ=None):
    """The marker's value when set and non-empty, else None. Presence is what
    arms a floor, so a malformed marker still arms it (and then no trailer can
    satisfy it, which is the loud direction)."""
    value = (os.environ if environ is None else environ).get(LOOP_SESSION_ENV, "")
    return value.strip() or None


def new_loop_session():
    """A fresh session id: the UTC start time, then six random hex digits, so
    two runs started in the same second still differ and a reader of history
    can date a run from its trailer."""
    return "{}-{}".format(
        time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()), secrets.token_hex(3)
    )


def mark_loop_process(environ=None):
    """Set the marker in this process's environment, once per run, and return
    it. A well-formed inherited marker is KEPT: the dispatcher's worker is the
    same run as the dispatcher, and its commits must name the same session."""
    env = os.environ if environ is None else environ
    current = loop_session(env)
    if current and _SESSION.fullmatch(current):
        return current
    env[LOOP_SESSION_ENV] = new_loop_session()
    return env[LOOP_SESSION_ENV]


def with_loop_trailer(message, session=None):
    """`message` with the trailer appended to its trailer block, when `session`
    is given or the marker is set; unchanged otherwise, which is a person's
    commit. The block is extended through `append_trailer`."""
    session = session or loop_session()
    if not session:
        return message
    return append_trailer(message, format_loop_trailer(session))


def append_trailer(message, line):
    """`message` with the trailer `line` appended to its final trailer block.
    An existing block is EXTENDED, never followed by a new paragraph, because
    git reads only the last paragraph's trailers; without one, the line opens
    a block of its own. The one joiner for a trailer a kit writer appends.

    Implements: SR-209, LLR-247
    """
    text = str(message).rstrip("\n")
    joiner = "\n" if _trailer_block(text) else "\n\n"
    return text + joiner + line
