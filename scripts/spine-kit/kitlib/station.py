"""The station's TERMINAL-OUTCOME vocabulary — the lane-close read model.

`SR-144`: every lane close is a terminal state with an immutable record. A lane
declares its outcome by the DIRECTORY it moved its claimed specs into —
`complete/` asserts the work is done, `cancelled/` asserts it never will be,
`partial/` asserts it stopped early. There is no fourth answer and no state file
that could hold one, which is what makes "every lane ends in a merge, branches
never hang" a property of the tree rather than a rule someone has to remember.

EVERY OUTCOME IS TERMINAL. Before `SR-144` a close into any OPEN folder
(`queued`/`draft`/`deferred`) read as a handback, so the returned row went
straight back on the frontier and needed a `blockref` to stop the driver
claiming, closing and re-claiming it forever. Those three are absent from
`OUTCOME_DIRS` on purpose: a lane that closes into an open folder names NO
outcome, and the merge refuses "exactly ONE declared state directory" — the
correct fail-closed posture, because under this contract stopping early is a
state with a name and a report, not a return to the queue.

WHY THIS IS A MODULE AND NOT A CONSTANT IN THE MERGE COORDINATOR (WI-483).
Until this module the table lived in `integrate.py`, and every reader of the
vocabulary imported the 2,500-line merge coordinator to reach it. The dashboard
was one of those readers: `traj_panels` — a render leaf that writes nothing and
must not be able to — imported the module that claims lanes, merges branches and
moves specs, for two constants. That import was an edge of the seven-module
cycle the 2026-08-19 repository review recorded (H-02), and the direction it ran
is the one a layered system forbids outright: a VIEW reaching into a MUTATION
service. The vocabulary itself depends on nothing, so it belongs below both.

The POLICY lives here too, not just the table. `outcome_of` answers "which
single terminal outcome do these status directories name?" — including the two
ways the answer is *none*: a spec that landed in no declared folder names none of
the three, and a spec left in TWO declared folders names two. Resolving the
second silently is worse than either (a dict keyed on basename once let the last
`ls-tree` line win, which is plain alphabetical precedence and put `queued` ahead
of `complete`). Reading the git tree stays with the coordinator, where the effect
belongs; deciding what the tree MEANS is a pure function over a set of strings,
and it is testable without a repository.

THE PER-CLOSE REPORT IS THE SAME OBLIGATION'S OTHER HALF (WI-483 slice 2, and
`SR-144` again). "Every lane close is a terminal state WITH AN IMMUTABLE RECORD"
is one sentence, and until this slice its two clauses lived in two modules: the
outcome table here, the record's path, format, read and refusal in the module
that WRITES the record (`handback.py`). That split cost an import edge in the
wrong direction — the merge coordinator refuses a `partial` merge whose report
omits the keep/discard split, so `integrate` reached UP into `handback` for
`report_path` and `report_refusal`, a deferred function-body import that was a
back edge of the five-module strongly connected component the 2026-08-19 review
recorded (H-02). The writes stay in `handback` (they are effects); the report's
SHAPE — where it lives, what it must say, and why a silent one is refused — is a
decision over strings and a dict, so it sits here with the vocabulary it
describes. `handback` re-exports every former name.

Stdlib only, and import-clean of the rest of `scripts/`, like every `kitlib`
module. The frontmatter read below parses through `kitlib.config.read_toml_text`,
the package's one home for "TOML text, or None" (WI-821) — a sibling inside the
package, so the rule costs no import edge out of it.

Contracts: IF-093 — the seam this module declares (process.md §8; row of record
in docs/requirements/interfaces.toml).

Contract IF-093: the terminal-outcome vocabulary as CONSTANTS a render may
    import. `OUTCOME_DIRS` is the immutable mapping of declaring `docs/work/`
    status directory to the outcome it asserts — `complete` -> MERGED,
    `cancelled` -> CANCELLED, `partial` -> PARTIAL — and only those three: the
    open folders are absent on purpose, so a lane closing into one names no
    outcome and the merge slot refuses it. `BAR_GREEN` is the one attestation
    label the refresh and `attest` share. Constants only — no call into a
    service, no write — and the module depends on nothing else in `scripts/`, which is what
    lets a view read the vocabulary without importing the coordinator that
    claims lanes, merges branches and moves specs. It is the same table the
    merge slot classifies a finished lane by, so the picture and the decision
    cannot drift apart.
"""

from __future__ import annotations

import enum
import re
from types import MappingProxyType

from . import config as _kitconfig

__all__ = [
    "Outcome",
    "OUTCOME_DIRS",
    "BAR_GREEN",
    "outcome_of",
    "REPORTS",
    "CLAIMED_OUTCOMES",
    "SUGGESTED_TIERS",
    "SPLIT_DECIDERS",
    "report_path",
    "render_report",
    "read_report",
    "read_toml_block",
    "report_refusal",
]


class Outcome(enum.StrEnum):
    """The three terminal states a lane can close into.

    A `str` subclass on purpose: the outcome is written into handback records,
    merge audit lines and the dashboard, and every existing reader compares it
    against a literal. Being an enum adds the closed set and the name; being a
    `str` means no caller had to change to gain it.
    """

    MERGED = "merged"
    CANCELLED = "cancelled"
    PARTIAL = "partial"


#: The declaring `docs/work/` status directory -> the outcome it asserts. Read
#: off the branch's own tree, so the outcome is derived from the same move that
#: made the branch FINISHED — one fact, read twice, never two facts to keep in
#: agreement. Immutable: a mutation here would be a bug in every consumer at
#: once, and there has never been a caller that wanted one.
OUTCOME_DIRS = MappingProxyType(
    {
        "complete": Outcome.MERGED,
        "cancelled": Outcome.CANCELLED,
        "partial": Outcome.PARTIAL,
    }
)

#: The one attestation label the refresh and `attest` share, carried as a git
#: trailer in the commit each writes, NAMING
#: the tree and the work commit it attests so both can be checked against git.
#: (`verdict.refresh_attestation` is why the names are the whole point: a
#: message alone rides through amend, rebase and cherry-pick onto trees nobody
#: barred.) It lives here because the station render draws the label and must
#: not import the coordinator to learn it.
BAR_GREEN = "Bar-Green:"

#: The MECHANICAL adjudication close's commit subject — `handback` writes it and
#: `verdict.mechanical_close_peel` verifies it, so the two must not hold two
#: spellings. It is here for the same reason `BAR_GREEN` is: a vocabulary the
#: writer and the reader share belongs below both.
MECHANICAL_CLOSE_PREFIX = "adjudicate: "
MECHANICAL_CLOSE_SUFFIX = " -> complete/ (mechanical close)"


def mechanical_close_subject(wi_id):
    """The subject line of the machinery's own adjudication-close commit, which
    moves the lane's ONE work item `wi_id`.

    A close moves one row, so the composer takes one id and refuses anything
    else by type: a list caller left behind would otherwise write a subject
    the attestor's recomposition no longer matches, and the close would stop
    peeling without a word.
    """
    if not isinstance(wi_id, str):
        raise TypeError(
            "a mechanical close names one work item id, got {!r}".format(wi_id)
        )
    return "{}{}{}".format(MECHANICAL_CLOSE_PREFIX, wi_id, MECHANICAL_CLOSE_SUFFIX)


def outcome_of(status_dirs):
    """The ONE `Outcome` the given status directories name, or `None`.

    `None` covers both failures on purpose, because the caller refuses on
    either: a set naming no declared directory, and a set naming two. Unknown
    directory names are ignored rather than raising — the caller passes whatever
    the tree held, and an undeclared folder simply asserts nothing.
    """
    seen = {OUTCOME_DIRS[d] for d in status_dirs if d in OUTCOME_DIRS}
    return next(iter(seen)) if len(seen) == 1 else None


# --- the per-close report: the immutable record SR-144 requires ----------------

# THE PER-CLOSE REPORT'S HOME, and the one constraint that fixes it.
# `agent_common.spec_files` is `work_dir.rglob("WI-*.md")` filtered only on "not
# directly in work_dir" — so a report at `docs/work/handbacks/WI-413-x.md` WOULD
# be walked, `parse_spec_status("handbacks")` would raise, and `read_spec_rows`
# would SILENTLY SKIP it, while `intake.next_wi_id` counted its id as taken.
# That is the invisible-spec trap that earned `draft/` its declaration. Putting
# the reports outside `docs/work/` entirely avoids the question.
REPORTS = "docs/handbacks"

# The claimed outcomes a lane may assert. `complete` is here for completeness of
# the vocabulary — a clean finish needs no report and never reaches the writer —
# so that the report schema names every state rather than only the sad ones.
# Deliberately NOT `OUTCOME_DIRS`' keys reordered: that table maps a DIRECTORY to
# the outcome it declares and is read off a git tree, while this is the set of
# words a report's own `claimed_outcome` field may carry. They agree today and
# nothing requires them to stay identical, since one is a tree fact and the other
# is a claim.
#
# THREE, and the fourth terminal status is deliberately not a fourth outcome:
# `restructured` (2026-09-02 restructure plan §1.6) is filed by a consolidation
# judgement on TRUNK, never by a lane closing. A lane that could claim it would
# be asserting that another row's scope had been absorbed — a judgement it is
# structurally not holding. `integrate.Outcome` is unchanged for the same reason.
CLAIMED_OUTCOMES = ("complete", "partial", "cancelled")

# The review tier a close SUGGESTS for its disposition — a TYPED field, which is
# the whole point. Before LLR-161 this rode as the magic substring `NEEDS-HUMAN`
# inside a free-prose reason, and `tier_signal` case-folded a search for it: so
# `NEEDS_HUMAN`, `needs human`, or a typo silently downgraded the judgement, with
# no constant, no validation and no refusal on a miss. Prose that carries control
# flow must be a typed field.
SUGGESTED_TIERS = ("quick", "medium", "strong")

# WHO DECIDES THE KEEP/DISCARD SPLIT, and the reason this is a field rather than
# an assumption. A `partial` close merges its work-so-far onto trunk, and on
# 2026-08-03 that merged code a lane had REJECTED, because nothing had asked
# which commits should survive. The rung that answers it has to hold for BOTH
# closers, and they know different things:
#
#   "lane"        the closing party judged its own work and says which commits
#                 to keep. `keep_commits` / `discard_commits` are authoritative.
#   "adjudicator" the closer COULD NOT judge — the dispatcher closing a lane
#                 whose worker exited or crashed has no view of the work at all.
#                 The split is explicitly OWED, and the disposition row minted
#                 for this close is what owes it.
#
# What is refused is a report that declares NEITHER: silence about the split is
# how the incident happened, and "I could not judge" is a different statement
# from saying nothing. Both are actionable; only silence is not.
SPLIT_DECIDERS = ("lane", "adjudicator")


def report_path(branch, wi_id):
    """The repo-relative path of one close's report.

    `<wi>-<branch>.md`, and that pair is the EVENT IDENTITY the old contract
    lacked. It is well-defined because a WI is claimed on exactly one branch at
    a time and `partial/` is terminal, so the same (wi, branch) pair cannot
    close twice; and it is STABLE, which is what lets a disposition's dedup be
    "does a disposition citing this report exist?" — a positive-provenance
    question — instead of the five reconstructions that leaked."""
    return "{}/{}-{}.md".format(REPORTS, wi_id, branch)


def render_report(wi_id, branch, claimed_outcome, reason, span, fields=None):
    """The report TEXT: TOML frontmatter carrying every typed field, then the
    prose sections a human reads.

    Typed, not prose, for the fields anything downstream keys off — the
    disposition's review tier reads `suggested_tier`, not a substring of
    `reason`. `keep_commits` / `discard_commits` exist because a green handback
    once merged REJECTED code onto trunk as-is (2026-08-03, live): under this
    contract a `partial` close must say which commits are keep and which are
    discard, and the integrator refuses one that does not. The revert decision
    becomes the adjudicator's explicit call instead of a hand cleanup.
    """
    fields = dict(fields or {})
    tier = fields.pop("suggested_tier", "medium")
    if tier not in SUGGESTED_TIERS:
        tier = "medium"
    keep = fields.pop("keep_commits", [])
    discard = fields.pop("discard_commits", [])
    decider = fields.pop(
        "split_decided_by", "lane" if (keep or discard) else "adjudicator"
    )
    if decider not in SPLIT_DECIDERS:
        decider = "adjudicator"
    delivered = fields.pop("delivered", "")
    not_delivered = fields.pop("not_delivered", "")
    front = [
        "+++",
        'wi = "{}"'.format(wi_id),
        'branch = "{}"'.format(branch),
        'claimed_outcome = "{}"'.format(claimed_outcome),
        "reason = {}".format(_toml_str(reason)),
        'commit_range = "{}"'.format(span),
        'suggested_tier = "{}"'.format(tier),
        "keep_commits = [{}]".format(", ".join(_toml_str(c) for c in keep)),
        "discard_commits = [{}]".format(", ".join(_toml_str(c) for c in discard)),
        'split_decided_by = "{}"'.format(decider),
        "+++",
    ]
    body = [
        "",
        "## What happened",
        "",
        "Lane `{}` closed `{}` as **{}**: {}".format(
            branch, wi_id, claimed_outcome, reason
        ),
        "",
        "The work so far is in trunk, not on a branch — the lane merges like any",
        "other. Read it with `git log --oneline {span}` / `git diff {span}`.".format(
            span=span
        ),
        "",
        "## Delivered",
        "",
        delivered or "_(the close named nothing as delivered)_",
        "",
        "## Not delivered",
        "",
        not_delivered or "_(the close named nothing as outstanding)_",
        "",
        "## Keep / discard",
        "",
        _split_lines(keep, discard, decider),
        "",
    ]
    return "\n".join(front + body)


def _toml_str(value):
    """A TOML basic string — the reason is free prose and may carry quotes."""
    text = str(value).replace("\\", "\\\\").replace('"', '\\"')
    text = text.replace("\n", " ").replace("\r", " ")
    return '"{}"'.format(text)


def _split_lines(keep, discard, decider):
    lines = []
    for label, commits in (("keep", keep), ("discard", discard)):
        lines.append("- **{}**: {}".format(label, ", ".join(commits) or "(none)"))
    lines.append("- **decided by**: {}".format(decider))
    if decider == "adjudicator":
        lines.append("")
        lines.append(
            "The closing party could not judge this work — a dispatcher closing "
            "a lane whose worker exited or crashed has no view of it. The split "
            "is therefore OWED, and the disposition row minted for this close is "
            "what owes it: read the commit range, decide which commits survive, "
            "and mint a corrective successor for anything that should not."
        )
    return "\n".join(lines)


#: The report's frontmatter fence. A `+++` block, the same shape every spec
#: carries, so one parser answers both.
FRONT_RE = re.compile(r"\+\+\+\n(.*?)\n\+\+\+", re.S)


def read_toml_block(text):
    """The first `+++` frontmatter block of `text`, parsed, or None.

    None covers all three ways it fails — no fence, unparseable TOML, a
    non-mapping document — because every caller refuses on any of them.
    """
    match = FRONT_RE.search(text or "")
    if match is None:
        return None
    data = _kitconfig.read_toml_text(match.group(1))
    return data if isinstance(data, dict) else None


def read_report(path):
    """One report's frontmatter as a dict, or None when it is unreadable or
    carries no `+++` block."""
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return None
    return read_toml_block(text)


def report_refusal(meta):
    """Why a report is not actionable, or None.

    The integrator's rung: a `partial` close whose report omits the keep/discard
    split refuses the MERGE. That is deliberately strict — the alternative is
    the live defect this contract closes, where a close merged rejected code
    onto trunk because nobody had said which commits were which."""
    if not isinstance(meta, dict):
        return "the close report is missing or has no +++ frontmatter"
    outcome = str(meta.get("claimed_outcome") or "").strip()
    if outcome not in CLAIMED_OUTCOMES:
        return "the close report claims outcome {!r}, not one of {}".format(
            outcome, "/".join(CLAIMED_OUTCOMES)
        )
    if outcome == "partial":
        decider = str(meta.get("split_decided_by") or "").strip()
        declared = bool(meta.get("keep_commits") or meta.get("discard_commits"))
        if not declared and decider not in SPLIT_DECIDERS:
            return (
                "the `partial` close report is SILENT about the keep/discard "
                "split — no keep_commits, no discard_commits, and no "
                "split_decided_by. A close that says nothing about which of its "
                "commits should survive leaves the revert decision to a hand "
                "cleanup, which is exactly how a rejected diff once merged onto "
                'trunk as-is. Declaring split_decided_by = "adjudicator" is a '
                "valid answer — the disposition row then owes it; saying "
                "nothing is not"
            )
    return None
