"""THE VERDICT RECORD: which artifact carries a lane's governing review verdict,
and what binds that verdict to the tree it judged.

WHY THIS EXISTS (OI-76, ruled 2026-08-31 — "B with C and the generated rollup;
governing = TREE IDENTITY"). The merge gate used to read a hand-authored
`docs/reviews/WI-<n>-REVIEW-A.md` rollup that **nothing in the kit wrote**, and
it judged that rollup's freshness by comparing commit TIMES. Three defects rode
together: nobody wrote it, so every mechanized lane stopped at a human; it
paraphrased evidence that already existed; and the trust was inverted — the
round files carry the anti-forgery story and the gate ignored them. The ruling
re-points the gate at the evidence and replaces the time comparison with an
identity: **a verdict counts only if it names the tree it judged.**

ONE DEFINITION, TWO READERS, and that is the whole reason this is a module
rather than two private helpers. `integrate._verdict_gate` (may this branch
merge?) and `agent_loop.review_owed_by_evidence` (does this lane still owe a
round?) are the same question asked from two sides, and they used to answer it
with two different rules over two different exclusion sets — which is how one
lane drew two identical `APPROVE findings=0` rounds because the loop's own
telemetry commits had moved HEAD past a verdict that was never invalidated.

THE SAME QUESTION HAS A SECOND DIMENSION: not only WHICH tree a verdict names
but HOW MANY of the declared phases have spoken about it. The two readers
diverged there too, and later — the gate was taught to require every phase the
`review_rounds` dial declares while the loop still read "any verdict at this
tree means the round was served", so a run that died between REVIEW-A and
REVIEW-B (the phase queue is in-memory) resumed scheduling nothing against a
gate refusing the missing phase. `declared_phases` is the span both slice;
`phases_owed` is what a resume still has to draw.

THE IDENTITY, and why it is not a git tree sha. `tree_identity` folds
`git ls-tree -r <rev>` with the RECORD paths removed — `docs/reviews/`,
`docs/log.d/`, `docs/iteration/`. Those three are the process writing about
itself: a round file, a log fragment and a session log are records OF the work
under review, never the work, so a commit that only touches them cannot
invalidate a verdict. The digest is a truncation-free SHA-256 over the filtered
listing, 64 hex — deliberately NOT 40, because a 40-hex `tree=` beside the
`Bar-Green: tree=<40 hex>` trailer (which IS a git tree object id) would read as
the same kind of value and it is not one.

WHAT CANNOT INVALIDATE A VERDICT HAS TWO HALVES, AND ONE OWNER. The record
PATHS above are the first; the station's REFRESH COMMIT is the second, and it is
here for the same reason rather than in the merge slot. A refresh merges the
trunk in and re-runs the compile/regen: it moves the tree without the lane
having changed its work, so a verdict is governed by the tree at the peeled work
tip (`governing_rev`), not at the branch tip. WI-560 Done-when 1 asks for ONE
definition of "the last commit that could invalidate a verdict" — that sentence
covers which commit as much as which paths, so `governing_identity` is the
single answer BOTH readers are handed. When the peel lived in `integrate` and
the loop measured at `HEAD` instead, the two readers disagreed across exactly
one refresh commit and a resumed lane drew a round the gate would not read
(REVIEW-A round 007, finding 2).

THE TWO HALVES INTERACT, which is the part that had to be driven to be believed.
The peel is written twice on purpose: `work_tip` peels only a refresh sitting
literally on the tip, because it feeds a `reset --hard` where peeling one commit
too far destroys committed work, and `governing_rev` walks THROUGH any commit
whose identity equals its parent's to reach a refresh it would otherwise hide.
While the identity used the tip-only peel, a single telemetry commit — a record
path, which the fold is built to ignore — moved the identity anyway, by burying
the refresh under it. A read-only question can afford an answer a destructive
one cannot. The walk's step condition is the module's own sentence rather than a
proxy for it ("a commit that cannot invalidate a verdict"), which is why the
empty attestation carrier `commit_telemetry` writes needs no case of its own.

THE TRAILER is the machine half, the `Bar-Green:` pattern applied to a verdict:

    Review-Verdict: APPROVE|CHANGES-REQUESTED rounds=<N> tree=<64 hex>

It rides the commit that RECORDS the round, is written by the coordinator (never
by a session; OI-76's ruling as corrected by OI-95, 2026-09-28), and is additive — an adopter whose loop does not write one yet
pays nothing, because the round file's own filename carries the reviewed sha and
resolves to the same identity.

THE LOGGED-SESSION RESTRICTION closes the plan's finding K: a BUILD session once
wrote `010-REVIEW-A-e26ab03.md` into the review path — an implementer authoring
its own approval. A file in `docs/reviews/` is a ROUND only when the coordinator's
own committed session log for that (train, ordinal) declares a REVIEW phase.
The session log is written and committed by the loop, so the join is evidence a
session cannot forge for itself without also forging the coordinator's telemetry.
The same log records the session's exact commit range (`# commits:`), and that
closes the two ways a round could still be changed by someone other than its
reviewer: a round is READ at the end of that range, as its session committed it,
so a later session rewriting the file changes nothing the gate counts; and a
REVIEW session's range may change exactly its own verdict file
(`scope_offenders`), which the merge slot re-derives from the committed logs
(`review_scope_refusal`) as the loop checked it right after the session.

WHAT THIS MODULE DELIBERATELY DOES NOT DO: it never decides what an absent answer
MEANS (`kitlib.git`'s rule, inherited). `None` is "git had nothing to say"; the
merge gate reads that as a refusal and the loop's derivation reads it as "assume
a round is owed" — both fail toward more review, and each says so at its own
call site.

Contracts: IF-175 — the seam this module declares (process.md §8; row of record
in docs/requirements/interfaces.toml).

Contract IF-175: the verdict record, as functions two independent readers call
    to reach ONE answer. `tree_identity` (and its pure half `fold_listing`)
    gives the non-record tree identity a verdict names, and
    `governing_identity` — over `governing_rev` / `refresh_attestation` — gives
    the rev that identity is measured at, so neither reader chooses its own
    (`work_tip` is the tip-only peel the `reset --hard` shares, deliberately
    NOT the same walk);
    `format_trailer` / `parse_trailer` the `Review-Verdict:` machine half;
    `round_file` / `session_log` the two name grammars `docs/reviews/` and
    `docs/iteration/`
    carry, and `ROLLUP_DIR` the one directory under `docs/reviews/` that is no
    review scope; `branch_paths` / `log_history` / `review_logs` / `logged_rounds` /
    `round_entries`
    the round evidence a branch holds, restricted to FULL-LANE rounds a fresh
    logged reviewer session produced over the lane's claim base to its reviewed
    commit (`format_scope` / `gating_span`, WI-884), or in persisted-final-
    reviewer mode a `final` round the loop drew under the final reviewer's
    own stage (WI-887), and COMMITTED, read as it
    committed them, and to the tree under judgement, a round the filing check
    (`filing_refusal`) refuses read as invalid evidence; `parse_range` /
    `session_range` / `range_paths` a session's
    recorded range and what it changed, and `scope_offenders` /
    `session_scope_offenders` / `review_scope_refusal` what a REVIEW session
    may change - its own verdict file and nothing else, one rule for the live
    loop and the merge slot; `declared_phases` / `phases_owed` the phase span
    a review policy declares and which of those phases a tree has no verdict
    for (never drawn, or whose latest round is invalid evidence) — the resume's
    question, weaker than the gate's demand for an APPROVE only on a dissent,
    so the two readers share a span without pretending to share a threshold;
    `branch_trailers` the verified attestations on
    the branch's own commits, in commit order;
    `read_bar_attestation` / `bar_attestation` / `tests_digest` the bar
    attestation grammar, its verifier and the one tests digest; and
    `review_attestation` the review walk: a verified `review` record whose
    tests digest matches, at the commit or beneath it through commits whose
    non-record identity is unchanged (the step `governing_rev` takes), the
    first verified record deciding, so another bar or another digest refuses
    rather than being walked past; `format_red_record` / `parse_red_record`
    the red record a build's session log header carries, keyed by the build
    sha a red review bar refused, `red_record` whether a build already has
    one, and `red_rounds` the count: the distinct red builds since the last
    verified `review` attestation, an unreadable log counting toward the cap,
    never away from it; and `mechanical_close` the one close-shape reader,
    whose optional relink oracle (injected by the adoption-record rule)
    admits only the close's byte-exact inbound relinks outside `docs/work/`,
    while the peel (`mechanical_close_attestation`) calls it without that
    oracle. Pure functions plus thin reads through
    `kitlib.git`, so nothing here writes and nothing imports a sibling service —
    the verdict parser arrives as an ARGUMENT rather than an import, which is
    what keeps this leaf free of an edge back into the scoring layer. Every
    function answers `None` where git had nothing to say and NEVER decides what
    that means: the merge slot reads it as a refusal, the loop's review-owed
    derivation as "assume a round is owed", and both directions are toward more
    review. The contract this row exists to hold is the SINGULARITY — a second
    reader of round evidence anywhere else is a finding against this row.
"""

import hashlib
import os
import re
from typing import NamedTuple

from .config import FINAL_PERSISTED, reviewer_dials
from .git import git_bytes, git_out
from .station import (
    BAR_GREEN,
    mechanical_close_subject,
)

__all__ = [
    "verdict_rulings",
    "row_rulings",
    "blessed_rows",
    "BLESS_TAG",
    "ROW_RULINGS",
    "RECORD_PREFIXES",
    "REVIEW_PHASES",
    "TRAILER_LABEL",
    "MINOR",
    "UNCHANGED_REWORK",
    "UNCHANGED_PAGE",
    "effective_verdict",
    "format_trailer",
    "parse_trailer",
    "is_record_path",
    "fold_listing",
    "tree_identity",
    "refresh_subject",
    "refresh_attestation",
    "BAR_NAMES",
    "LANDING_BARS",
    "BarAttestation",
    "tests_digest",
    "format_bar_green",
    "bar_attestation",
    "mechanical_close_attestation",
    "mechanical_close",
    "work_tip",
    "governing_rev",
    "governing_identity",
    "round_file",
    "session_log",
    "parse_range",
    "session_range",
    "FULL",
    "NARROW",
    "FINAL",
    "format_scope",
    "gating_span",
    "filing_refusal",
    "range_paths",
    "scope_offenders",
    "session_scope_offenders",
    "branch_paths",
    "log_history",
    "review_logs",
    "RED_KEYS",
    "format_red_record",
    "parse_red_record",
    "RedCount",
    "red_rounds",
    "logged_rounds",
    "round_entries",
    "branch_entries",
    "tree_already_judged",
    "declared_phases",
    "phases_owed",
    "round_count",
    "format_branch_trailer",
    "branch_trailers",
    "review_scope_refusal",
]

# The process writing about itself. A commit touching only these cannot
# invalidate a verdict — see the module docstring for why each one is here.
RECORD_PREFIXES = ("docs/reviews/", "docs/log.d/", "docs/iteration/")

REVIEW_PHASES = ("REVIEW-A", "REVIEW-B")

TRAILER_LABEL = "Review-Verdict"

# The one severity that cannot, by itself, refuse a lane.
MINOR = "MINOR"

# What `tree_already_judged` answering True MEANS to whoever asked, in the words
# the operator reads. Here rather than at the caller so the loop's console line
# and the merge slot's vocabulary cannot drift apart.
UNCHANGED_REWORK = (
    "rework changed no non-record path; a round on the same tree would be "
    "refused as a reroll"
)
UNCHANGED_PAGE = "PAGE-HUMAN — rework left the reviewed tree unchanged"

# The machine half. Anchored per-line (`re.M`) exactly like the `Bar-Green:`
# reader, and the verdict word is a CLOSED alternation rather than `\S+`: an
# unrecognized word must fail to parse (and so read as no verdict at all) rather
# than arrive downstream as a third outcome nobody wrote a rule for.
TRAILER_RE = re.compile(
    r"^{}:[ \t]+(APPROVE|CHANGES-REQUESTED)[ \t]+rounds=(\d+)[ \t]+"
    r"tree=([0-9a-f]{{64}})[ \t]*$".format(TRAILER_LABEL),
    re.M,
)

# `<ordinal>-<phase>-<reviewed sha7>[-<tag>].md`, the name `agent_loop` composes
# in `fresh_verdict_path`. The optional tag is `-relaxed` today (C5's recorded
# heterogeneity relaxation) and any later marker; it is captured by nobody here
# because the NAME's job is only to say which round this is and what it read.
ROUND_FILE_RE = re.compile(
    r"^(?P<ordinal>\d+)-(?P<phase>REVIEW-[A-Z])-(?P<sha>[0-9a-f]{7,40})"
    r"(?:-[A-Za-z0-9._-]+)?\.md$"
)

# `[<train>-]<ordinal>-<YYYYMMDD>-<HHMMSS>.log`, written by
# `agent_common.write_session_log`. The train prefix is optional because the
# attended (single-lane) layout has none.
SESSION_LOG_RE = re.compile(r"^(?:(?P<train>.+)-)?(?P<ordinal>\d+)-\d{8}-\d{6}\.log$")

_PHASE_HEADER_RE = re.compile(r"^# phase:[ \t]*(.*)$", re.M)

# The session's exact commit range, `before..after`, as the coordinator took it
# right after the session and wrote it into the log it commits. Empty when the
# session committed nothing; the loop's `(root)` / `?` placeholders for an
# unborn or unreadable head parse as no range at all.
_COMMITS_HEADER_RE = re.compile(r"^# commits:[ \t]*(.*)$", re.M)
# A REVIEW session's scope, as the coordinator that ROUTED the round recorded it
# (WI-884): `full <claim base>..<reviewed sha>` for the fresh full-lane round a
# merge is judged on, `narrow <base>..<sha>` for an iteration round. A base the
# coordinator could not name is `?`, which `parse_range` reads as no range. The
# service records a RETAINED session's generation in `# session-gen:`, so a
# present, empty value is the session minted for its round. WI-887 adds
# `final <claim base>..<reviewed sha>`: a full-lane round the loop drew under
# the persisted final reviewer's own stage, the one retained round that gates.
_SCOPE_HEADER_RE = re.compile(r"^# review-scope:[ \t]*(.*)$", re.M)
_GEN_HEADER_RE = re.compile(r"^# session-gen:[ \t]*(.*)$", re.M)
FULL, NARROW, FINAL = "full", "narrow", "final"
_RANGE_RE = re.compile(r"^([0-9a-f]{7,64})\.\.([0-9a-f]{7,64})$")

_REVIEWS = "docs/reviews"
# The rollup generator owns this directory and prunes what it did not write.
ROLLUP_DIR = _REVIEWS + "/rollup"
_ITERATION = "docs/iteration"


# --- what a verdict word MEANS once its findings are read ---------------------


def effective_verdict(word, findings):
    """`word`, except that a CHANGES-REQUESTED whose findings are ALL `[MINOR]`
    routes as an APPROVE.

    WHY THIS EXISTS (measured 2026-09-03/04). Four review rounds refused a lane
    on a single MINOR finding each (WI-586 rounds 006 and 010, WI-590 round
    013). Each refusal cost a rework session AND another round — two agent
    sessions and a full harness re-run — to land a wording nit that no reviewer
    called a defect. A MINOR is by construction a finding whose remedy the
    reviewer did not think worth blocking on; spending the block on it inverts
    the severity scale the brief asks reviewers to use.

    THE RECORD IS NEVER REWRITTEN. This transforms what the READERS do with a
    verdict, never the round file: the reviewer's `VERDICT:` line stays exactly
    what the reviewer wrote, the findings stay carried, and a later reader can
    still see that changes were requested. Only routing and the merge slot read
    the word through here.

    ONE HOME, BOTH READERS — the same reason the rest of this module exists.
    `agent_loop.complete_review_round` (route this round) and
    `round_entries`, which feeds `integrate._round_refusal` (may this branch
    merge?), must apply it identically: a loop that routed a MINOR-only round as
    APPROVE while the gate still read the file's own word would send the lane
    to a merge slot that refuses it, which is the wasted round again with an
    extra hop.

    ZERO FINDINGS IS NOT MINOR-ONLY. A CHANGES-REQUESTED with no findings at all
    stays a refusal: a reviewer who blocks without naming anything is a
    different defect (a garbled or lazy round), and silently promoting it to
    APPROVE would clear a gate on nobody's judgement. `all()` over an empty
    sequence is True, so the emptiness is tested first and on purpose.

    A finding is anything carrying a `severity` (a `score_reviews.Finding`);
    a bare string is read as the severity itself, so a caller holding only the
    words needs no adapter."""
    if word != "CHANGES-REQUESTED":
        return word
    severities = [
        str(getattr(f, "severity", f) or "").strip().upper() for f in findings or ()
    ]
    if not severities:
        return word
    return "APPROVE" if all(sev == MINOR for sev in severities) else word


# --- the trailer --------------------------------------------------------------


def format_trailer(word, rounds, tree):
    """The `Review-Verdict:` line for a round whose merged verdict is `word`."""
    return "{}: {} rounds={} tree={}".format(TRAILER_LABEL, word, int(rounds), tree)


def parse_trailer(message):
    """`(word, rounds, tree)` from the LAST `Review-Verdict:` line in `message`,
    or None when it carries none.

    The last, not the first: a commit message that quotes an earlier trailer
    (a rework commit citing the round it answers) must not have the quotation
    read as its own attestation, and the kit's convention puts a commit's own
    trailers at the end."""
    matches = TRAILER_RE.findall(message or "")
    if not matches:
        return None
    word, rounds, tree = matches[-1]
    return word, int(rounds), tree


# --- the identity -------------------------------------------------------------


def is_record_path(path):
    """Is `path` one of the process's records of itself, rather than work?"""
    if isinstance(path, bytes):
        norm = path.replace(b"\\", b"/").lstrip(b"./")
        return any(
            norm.startswith(prefix.encode("ascii")) for prefix in RECORD_PREFIXES
        )
    norm = str(path).replace("\\", "/").lstrip("./")
    return any(norm.startswith(prefix) for prefix in RECORD_PREFIXES)


def fold_listing(entries):
    """The identity of `git ls-tree -r` ENTRIES, with record paths dropped.

    Each entry is one raw `<mode> <type> <sha>\\t<path>` byte record. It takes
    a split SEQUENCE rather than git's complete stdout deliberately: without
    `-z` git QUOTES any path holding a non-ASCII or special character
    (`"docs/reviews/002-REVIEW-A-abcdef\\303\\251.md"`), the leading quote
    defeats every `RECORD_PREFIXES` test, and a single accented filename under
    `docs/log.d/` folds into the identity and silently stales every governing
    verdict on the branch (REVIEW-A round 007, finding 3, driven both ways).
    Splitting is the caller's job so no reader here ever sees git's DISPLAY
    encoding. The record-prefix boundary and hash are byte-native: decoding
    before either one collapses distinct invalid-UTF-8 paths onto the same
    replacement character (REVIEW-A round 019, driven on `\\200` -> `\\201`).

    Pure, so the rule is testable without a repository — which matters because
    this is the one function that decides whether two trees are "the same work".
    Each surviving entry is folded whole (mode, type, blob sha and path), so a
    mode change or a rename is as invalidating as an edit."""
    fold = hashlib.sha256()
    for line in entries or ():
        if not line.strip():
            continue
        # `<mode> <type> <sha>\t<path>` — split on the TAB, since a path may
        # contain spaces and the fields before it never do.
        _meta, _tab, path = line.partition(b"\t")
        if not _tab or is_record_path(path):
            continue
        fold.update(line)
        fold.update(b"\n")
    return fold.hexdigest()


def tree_identity(root, rev):
    """The verdict-relevant tree identity of `rev`, or None when git cannot say.

    `--full-tree` so the answer does not depend on the caller's cwd inside the
    repository, and `-z` because it is the ENCODING BOUNDARY: NUL-delimited
    output is never quoted or escaped, so `fold_listing` is handed raw bytes and
    the record-path test cannot be defeated by a filename (see its docstring).
    A NUL split also survives a path containing a newline, which the line split
    it replaced could not. No decode sits in this path: path bytes are part of
    the identity, not display text."""
    if rev is None:
        return None
    listing = git_bytes(root, ["ls-tree", "-r", "-z", "--full-tree", rev])
    if listing is None:
        return None
    return fold_listing(listing.split(b"\0"))


# --- the rev the identity is measured at --------------------------------------


# The `Bar-Green:` attestation, VERIFIED against git. The label comes from
# `station` so the writer (`format_bar_green`) and this verifier share one
# spelling rather than two literals that must agree. The bar set is closed:
# `review` is a build round's record of green, `landing` and `no-bar` are the
# station refresh's (the adjudication arm runs no bar and says so).
BAR_NAMES = ("review", "landing", "no-bar")
LANDING_BARS = ("landing", "no-bar")
_ATTEST_RE = re.compile(
    r"^{}\s+tree=([0-9a-f]{{40}})\s+work=([0-9a-f]{{40}})\s+bar=(\S+)"
    r"\s+tests=([0-9a-f]{{64}}|none)(?:\s+(\S.*))?$".format(BAR_GREEN)
)


class BarAttestation(NamedTuple):
    """The verified fields of one `Bar-Green:` line."""

    tree: str
    work: str
    bar: str
    tests: str
    summary: str


# How far back `work_tip` will peel refresh commits. The disposable-commit rule
# means at most ONE can ever sit on the tip, so this is a guard against a
# hand-made pathological history, not an expected depth.
_MAX_REFRESH_PEEL = 8


def refresh_subject(branch):
    """The refresh commit's subject prefix for `branch` - one home, because the
    writer and the verifier must agree on it exactly."""
    return "refresh: {} onto trunk ".format(branch)


def refresh_attestation(root, branch, rev=None):
    """`(work_tip_sha, bar summary)` if `rev` is a GENUINE refresh commit for
    `branch`, else None. `rev` defaults to the branch tip.

    The bar is attested to a TREE, and this is where that sentence is made
    true rather than merely written down. A commit message is not evidence: it
    can be copied, hand-written, amended onto different content, cherry-picked
    or rebased, and every one of those carries the words onto a tree nobody
    barred (REVIEW-A round 1, driven both ways - a forged trailer on an
    ordinary work commit, and `commit --amend` adding a file to a real one).

    So the trailer NAMES what it attests, and `bar_attestation` verifies it
    against git (the grammar and its one writer are `format_bar_green`'s):

        Bar-Green: tree=<40 hex> work=<40 hex> bar=<review|landing|no-bar> tests=<64 hex|none> <summary>

      * `bar=` must be `landing` or `no-bar` here: a `review` attestation is a
        build round's record of green, never a refresh, so it is never peeled
        and never satisfies the merge slot. The old line without `bar=` is not
        read at all.
      * `tree=` must equal the commit's OWN tree. This is the load-bearing one:
        no edit that changes content can keep it, because the tree sha IS the
        content. `git write-tree` is what lets the refresh know the value
        before it commits - the index it barred is the tree it commits.
      * `work=` must equal the commit's first parent, so the disposable-commit
        peel below has a stated target rather than a guessed one, and a
        cherry-pick or rebase (new parent) is rejected.
      * the SUBJECT must be this branch's own `refresh: <branch> onto trunk`,
        so a refresh commit merged in from elsewhere is not read as this
        branch's.

    THE HONEST BOUND: this defeats ACCIDENT, not INTENT. Every accidental
    carrier refuses - a copied message, an amend, a rebase, a cherry-pick, a
    trailer quoted in an ordinary commit. But forging one deliberately is FOUR
    git invocations in the lane worktree and no bar at all: `add -A`, `T=$(git
    write-tree)`, `P=$(git rev-parse <branch>)`, and the `commit` that carries
    those two values in the trailer. REVIEW-A round 2 drove exactly that and landed an
    unbarred file on trunk. The format is printed in every refresh commit, so
    the cost is reading, not reverse-engineering.

    That is accepted, deliberately. The only structural closure is a bar the
    slot itself runs and cannot skip, and DECISION 3 (owner ruling 2026-07-31)
    deleted the merge bar outright: a kept-just-in-case bar is exactly the
    shape §0's governing principle warns against. So the threat model here is
    the same one the rest of the coordinator holds - bugs, drift and a lane that
    goes wrong, not a lane that lies on purpose. A lane is trusted code the
    operator chose to run. If that ever stops being true, the answer is a
    slot-side bar and a reopened DECISION 3, not a longer trailer.
    """
    rev = rev or branch
    message = git_out(root, ["log", "-1", "--format=%B", rev]) or ""
    lines = message.splitlines()
    if not lines or not lines[0].strip().startswith(refresh_subject(branch)):
        return None
    attested = bar_attestation(root, rev)
    if attested is None or attested.bar not in LANDING_BARS:
        return None  # a `review` attestation is never a refresh, so never peeled
    return attested.work, attested.summary


def tests_digest(paths):
    """The digest of a set of named test paths: `none` for the empty set, else
    the SHA-256 of the sorted, de-duplicated paths, one per line. A path is
    normalised (a backslash to `/`, a leading `./` dropped) so one set has one digest
    whatever its order or spelling. One home, so the producer that writes it and
    any reader that compares it compute the same value.

    Implements: SR-156, LLR-207
    """
    normalized = set()
    for path in paths or ():
        text = str(path).replace("\\", "/")
        while text.startswith("./"):
            text = text[2:]
        normalized.add(text)
    if not normalized:
        return "none"
    joined = "\n".join(sorted(normalized)) + "\n"
    return hashlib.sha256(joined.encode("utf-8")).hexdigest()


def format_bar_green(tree, work, bar, tests, summary):
    """The one writer of the `Bar-Green:` line:

        Bar-Green: tree=<40 hex> work=<40 hex> bar=<bar> tests=<64 hex|none> <summary>

    It raises on a bar outside `BAR_NAMES`, so the writer cannot emit a line
    the verifier refuses.

    Implements: SR-156, LLR-207
    """
    if bar not in BAR_NAMES:
        raise ValueError("unknown bar {!r}; the set is {}".format(bar, BAR_NAMES))
    return "{} tree={} work={} bar={} tests={} {}".format(
        BAR_GREEN, tree, work, bar, tests, summary
    ).rstrip()


def read_bar_attestation(root, rev):
    """`(BarAttestation, None)` for `rev`'s verified `Bar-Green:` attestation,
    else `(None, cause)`: the one verifier, with the reason it refused named.

    An attestation is the message's ONE line starting with the label at column
    0 (a quoted or indented line is a quotation, two lines attest no single
    bar), matching the grammar in full, naming a bar in `BAR_NAMES`, and whose
    `tree=` and `work=` are `rev`'s own tree and first parent. An unreadable
    commit, or the old grammar without `bar=`, is not one: no legacy path. The
    cause names the first of those checks that failed, with both values for a
    tree or parent that does not match, so a refusing reader can say why.

    Implements: SR-241, LLR-341
    """
    message = git_out(root, ["log", "-1", "--format=%B", rev])
    if not message:
        return None, "the commit's message cannot be read"
    labelled = [line for line in message.splitlines() if line.startswith(BAR_GREEN)]
    if len(labelled) != 1:
        return None, "it carries {} `{}` lines at column 0, not one".format(
            len(labelled), BAR_GREEN
        )
    matched = _ATTEST_RE.match(labelled[0])
    if not matched:
        return None, "its `{}` line is outside the grammar `{}`".format(
            BAR_GREEN, "tree=<40 hex> work=<40 hex> bar=<bar> tests=<64 hex|none>"
        )
    if matched.group(3) not in BAR_NAMES:
        return None, "its `{}` line names bar {!r}, outside {}".format(
            BAR_GREEN, matched.group(3), ", ".join(BAR_NAMES)
        )
    attested = BarAttestation(
        *matched.group(1, 2, 3, 4), (matched.group(5) or "").strip()
    )
    tree = _rev(root, rev + "^{tree}")
    if tree != attested.tree:  # the message rode onto a tree it does not describe
        return None, "its `{}` line names tree {}, but the commit's tree is {}".format(
            BAR_GREEN, attested.tree, tree
        )
    parent = _rev(root, rev + "^1")
    if parent != attested.work:  # ...or onto another parent than the one it names
        return None, "its `{}` line names work {}, but its first parent is {}".format(
            BAR_GREEN, attested.work, parent
        )
    return attested, None


def bar_attestation(root, rev):
    """The verified fields of `rev`'s `Bar-Green:` attestation as a
    `BarAttestation`, or None: `read_bar_attestation` without its cause.

    Implements: SR-156, LLR-207
    """
    return read_bar_attestation(root, rev)[0]


# The one non-record tree the MACHINERY itself moves. See
# `mechanical_close_attestation` for why it is peeled and what bounds that.
_WORK_PREFIX = b"docs/work/"
_ACTIVE_SPEC = re.compile(rb"^docs/work/active/([^/]+)/((WI-[0-9]+)-[^/]+[.]md)$")
_COMPLETE_SPEC = re.compile(rb"^docs/work/complete/(WI-[0-9]+-[^/]+[.]md)$")


def _closed_wi_ids(fields, relinked=None, blobs=None):
    """The one id moved from active/ to complete/, as `[wi_id]`, or None.

    THE ONE CLOSE SHAPE, read two ways (WI-969). With no `relinked` oracle it
    is the peel's reading: every changed path must live under `docs/work/`.
    With one (the adoption-record rule passes `spec_move.exact_relink`; this
    leaf imports no script, so the oracle is injected), a path outside
    `docs/work/` is admitted only as an `M` entry whose blobs
    (`blobs(path) -> (old bytes, new bytes)`, at the parent and at the commit)
    are exactly the inbound relink of the commit's own paired moves
    (`_outside_relinked`). Everything else in the shape is the same for both.

    ONLY THE MOVE ITSELF MAY CREATE OR DESTROY. An `A` or `D` entry this
    function does not RECOGNISE is a refusal, not an entry it skips: while they
    were skipped, one close deleted the pre-existing terminal record
    `docs/work/complete/WI-300-terminal.md` and added a brand-new
    `docs/work/queued/WI-999-smuggled.md` and STILL peeled, so a judged row's
    destruction and a new spec's injection were both measured at the parent and
    never judged (REVIEW-A round 3, driven on a real repository). `M` stays
    unrestricted because `spec_move`'s inbound relink genuinely rewrites other
    rows in place, and a relink only ever modifies.

    THE ONE-ROW CLAUSE: a lane claims one work item, so its close moves
    exactly one row, and any other count of `active/` deletions declines to
    peel, failing toward more review. It also owns two shapes a separate
    clause once held. The empty close (no deletion) and a close reaching into
    a second lane's `active/` (a second deletion) both fail it, and with
    exactly one deletion there is exactly one source branch, so a
    one-source-branch clause beside it could never fire and is not written.
    """
    if len(fields) % 2:
        return None
    deleted, added, branches, outside = [], [], set(), []
    for status, path in zip(fields[::2], fields[1::2]):
        if not path.startswith(_WORK_PREFIX):
            outside.append((status, path))
            continue
        active = _ACTIVE_SPEC.match(path) if status == b"D" else None
        complete = _COMPLETE_SPEC.match(path) if status == b"A" else None
        if active:
            branches.add(active.group(1))
            deleted.append((active.group(2), active.group(3).decode("ascii")))
        elif complete:
            added.append(complete.group(1))
        elif status != b"M":
            return None
    if len(deleted) != 1 or [deleted[0][0]] != added:
        return None
    if not _outside_relinked(outside, branches, deleted, relinked, blobs):
        return None
    return [deleted[0][1]]


def _outside_relinked(outside, branches, deleted, relinked, blobs):
    """Whether every changed path outside `docs/work/` (`outside`, its
    `(status, path bytes)` entries) is exactly the inbound relink the close's
    own moves write: never without an oracle (the peel's reading), and with
    one only an `M` entry with a UTF-8 path whose two blobs
    `relinked(old, new, path, remap)` accepts, `remap` mapping each paired
    `active/<branch>/` path (the one branch of `branches`, the names of
    `deleted`) to its `complete/` path, re-derived from the commit's own A/D
    entries. An `A` or `D` outside, an undecodable path and an unreadable blob
    (which the oracle reads as not a relink) all refuse. No path outside is
    trivially true, oracle or none.

    Implements: SR-148, LLR-345
    """
    if not outside:
        return True
    if relinked is None or blobs is None:
        return False
    try:
        (branch,) = (b.decode("utf-8") for b in branches)
        names = [name.decode("utf-8") for name, _ in deleted]
    except UnicodeDecodeError:
        return False
    remap = {
        "docs/work/active/{}/{}".format(branch, name): "docs/work/complete/" + name
        for name in names
    }
    for status, raw in outside:
        if status != b"M":
            return False
        try:
            path = raw.decode("utf-8")
        except UnicodeDecodeError:
            return False
        old, new = blobs(path)
        if not relinked(old, new, path, remap):
            return False
    return True


def mechanical_close_attestation(root, rev):
    """The first parent of `rev` if `rev` is the machinery's OWN adjudication
    close (`handback.close_adjudication`), else None.

    THE SECOND DISPOSABLE COMMIT, and it is here for the refresh commit's
    reason. `docs/work/` is deliberately IN the identity — a spec's
    `safety_class`, `needs` and `Deliverable` are claims a verdict is ABOUT —
    and the ordering rule that keeps the price low is "close before the final
    verdict round". An adjudication lane CANNOT follow that rule: the round is
    drawn while the row is still in `active/`, and the close is performed
    afterwards by the machinery, at the worker's DONE. So the very next commit
    after an APPROVE moved the spec and staled the round that had just judged
    it — measured 2026-09-03 on WI-586, whose merge slot then refused "no
    logged review round names its current tree" and needed a hand-compiled
    legacy rollup (`docs/reviews/WI-586-REVIEW-A.md`).

    WHAT MAKES IT PEELABLE is the same argument the refresh commit makes, not a
    weaker one. The commit is MACHINE-authored end to end: no agent writes it,
    its subject is composed by `station.mechanical_close_subject`, and the
    `## Deliverable` it inserts is a fixed literal
    (`handback._ADJUDICATION_CLOSE_DELIVERABLE`), so nothing a reviewer could
    conclude differently about enters the tree. The row's own claims — its
    `## Dispositions`, which is what the verdict judged — are carried through
    unchanged.

    VERIFIED AGAINST GIT, not read off the message. The changed-path stream is
    read with rename detection disabled; it must contain exactly one deletion
    from `docs/work/active/<branch>/` and the addition of that same spec name
    to `docs/work/complete/`, and NOTHING ELSE may create or destroy — an
    unrecognised `A` or `D` refuses the whole commit, so unreviewed data loss
    and unreviewed new content cannot ride the peel (`_closed_wi_ids`). A
    close moving any other number of rows declines to peel. The one row's
    filename id is composed through the writer's `mechanical_close_subject`,
    and the result must equal the subject exactly.
    The commit must also have exactly ONE parent (a merge
    is never this), and every changed path must live under `docs/work/`, which
    stops a close whose inbound-link relink reached into product or requirement
    files from being peeled. Each check FAILS TOWARD REVIEW: declining to peel
    measures at a later rev, so the gate asks for MORE review, never less. The
    honest bound is `refresh_attestation`'s — this defeats accident and drift,
    not a lane that lies on purpose, which is the threat model the coordinator
    holds throughout.

    THE RECORD (WI-969). The close may also add one thing to the row's front
    matter: its `adopted` record, the request's validated result, which the
    adoption-record rule verifies (`adoption_record`). The peel reads the
    shared close shape (`mechanical_close`) with NO relink oracle, so a close
    whose relink reaches outside `docs/work/`, which that rule admits when
    the relink is exact, is still not peeled here. What it verifies is
    unchanged.

    Implements: SR-156, SR-148, LLR-207, LLR-345
    """
    closed = mechanical_close(root, rev)
    return closed[0] if closed else None


def mechanical_close(root, rev, relinked=None):
    """`(parent, closed ids)` when `rev` is the machinery's own adjudication
    close, else None: the ONE reading of the close shape, shared by the peel
    (`mechanical_close_attestation`, no oracle) and the adoption-record rule
    (`relinked=spec_move.exact_relink`, injected because this leaf imports no
    script). One parent (a merge is never a close), the
    `--name-status --no-renames -z` stream judged by `_closed_wi_ids` (with
    the oracle, a changed path outside `docs/work/` is admitted only as the
    exact inbound relink of the commit's own moves, its blobs read at the
    parent and at `rev`), and the one id composed through
    `mechanical_close_subject` equal to the subject. A read git cannot make is
    None, never a close.

    Implements: SR-148, LLR-345
    """
    message = git_out(root, ["log", "-1", "--format=%B", rev]) or ""
    lines = message.splitlines()
    subject = lines[0].strip() if lines else ""
    parent = _rev(root, rev + "^1")
    if parent is None or _rev(root, rev + "^2") is not None:
        return None
    listing = git_bytes(
        root, ["diff", "--name-status", "--no-renames", "-z", parent, rev]
    )
    if listing is None:
        return None
    fields = [field for field in listing.split(b"\0") if field]

    def blobs(path):
        return tuple(
            git_bytes(root, ["cat-file", "blob", "{}:{}".format(at, path)])
            for at in (parent, rev)
        )

    wi_ids = _closed_wi_ids(fields, relinked, blobs)
    if wi_ids is None or subject != mechanical_close_subject(wi_ids[0]):
        return None
    return parent, wi_ids


def _peel_target(root, branch, rev):
    """The rev a DISPOSABLE commit at `rev` peels to, or None when `rev` is not
    one. TWO commits are disposable and this is their one home, so
    `governing_rev`'s walk asks the question once: the station's REFRESH (which
    re-merges trunk and regenerates) and the machinery's own ADJUDICATION CLOSE
    (which archives a judged row terminal). Both are machine-authored, both move
    the tree without the lane having changed what it is claiming, and both are
    admitted by verification against git rather than by measurement."""
    attested = refresh_attestation(root, branch, rev)
    if attested is not None:
        return attested[0]
    return mechanical_close_attestation(root, rev)


def work_tip(root, branch):
    """The branch's last WORK commit as a sha: the tip, with any refresh commit
    peeled off at the work sha that refresh ITSELF recorded.

    Two callers, one meaning. `integrate.refresh` resets here before it merges
    (the §A2.1 disposable-commit rule: a retry never stacks a second merge on
    the first, because docs/log.md is append-compiled and the stack would
    conflict on the file end). `governing_identity` measures code-time here,
    because the refresh is MECHANICAL bookkeeping - it rewrites the compiled log
    and the generated artifacts, and if that counted as code it would stale the
    honest APPROVE that had to precede it.

    The peel is why `refresh_attestation` had to become a verification rather
    than a substring test: this function feeds a `reset --hard`, so peeling one
    commit too far DESTROYS committed work. A work commit whose message merely
    quoted the trailer used to be peeled, and its file left the branch (REVIEW-A
    round 1, driven). Now nothing is peeled that does not carry its own tree and
    parent, which an ordinary commit cannot do by accident.
    """
    rev = branch
    for _ in range(_MAX_REFRESH_PEEL):
        attested = refresh_attestation(root, branch, rev)
        if attested is None:
            return _rev(root, rev)
        rev = attested[0]
    return _rev(root, rev)


# How far `governing_rev` will walk. Deeper than `_MAX_REFRESH_PEEL` because
# what it walks THROUGH is identity-preserving commits, and a lane accumulates
# one telemetry commit per session. Hitting the bound stops the walk, which
# measures at a later rev and so can only ask for MORE review, never less.
_MAX_GOVERNING_WALK = 64


def _identity_step(root, rev, identity):
    """`(parent, parent identity)` when `rev`'s non-record identity `identity`
    equals its first parent's, else None: the one step a walk takes through a
    commit that cannot invalidate a verdict (see `governing_rev`). None also
    when git had nothing to say, or `rev` is a root commit with nothing under it.

    Implements: SR-241, LLR-341
    """
    parent = _rev(root, rev + "^1")
    if identity is None or parent is None:
        return None
    parent_identity = tree_identity(root, parent)
    if parent_identity != identity:
        return None
    return parent, parent_identity


def governing_rev(root, branch, rev=None):
    """The commit whose tree governs a verdict on `branch`: `rev` (default: the
    tip), with refresh commits peeled AND identity-preserving commits walked
    through.

    `rev` IS A PARAMETER BECAUSE THE ROUND EVIDENCE ASKS THE SAME QUESTION AT A
    DIFFERENT COMMIT. `round_entries` must decide which tree a round NAMES, and
    the only honest answer is the one this function gives for the sha that round
    read — measuring the reviewed sha raw while the gate measured the tip
    composed left two rev-choices for one definition, and a round drawn after a
    station refresh matched neither reader forever (REVIEW-A round 015). The
    `branch` argument stays separate from `rev` because the peel VERIFIES a
    refresh commit against the branch it names, which is a property of the
    branch and not of the commit being measured.

    WHY THIS IS NOT `work_tip`. Both peel a refresh, and they must not share an
    implementation, because `work_tip` feeds a `reset --hard` and may only ever
    peel a refresh sitting literally on the tip — peeling one commit further
    there DESTROYS committed work. This function only ever reads, so it can
    afford the honest question: is there a refresh commit under here that
    nothing invalidating has been stacked on?

    That gap was a live defect, driven. The fold already ignores
    `RECORD_PREFIXES`, so a telemetry commit cannot move the identity — but a
    telemetry commit landing ON TOP of a refresh made the tip stop being a
    refresh commit, the tip-only peel stopped applying, and the identity flipped
    from the pre-refresh work tree to the post-refresh one. An APPROVE served
    before the refresh then named a tree nothing governed: the loop answered
    `owed=True` and the merge slot refused "no logged review round names its
    current tree" — both readers agreeing on the WRONG answer, and an honest
    approval parked at a supervisor stop by the coordinator's own telemetry.
    That is the OI-76 failure mode this row exists to eliminate, surviving one
    commit further down than the round-007 fix reached.

    THE STEP CONDITION IS THE DEFINITION ITSELF, not a proxy for it. A commit
    may be walked through exactly when its non-record identity EQUALS its first
    parent's — which is, in as many words, "a commit that cannot invalidate a
    verdict", the sentence this whole module is built around. Measuring it
    directly is what makes every WALK step provably identity-neutral: stepping
    can only ever reach a rev carrying the identity it stepped from, so the walk
    cannot invent an answer, only see PAST commits to a refresh they would
    otherwise hide. The PEEL is the one step that does move the identity, and
    deliberately — that is the whole job of a refresh, and it is admitted by
    verification against git rather than by measurement — so the returned rev
    carries the tip's identity only on a branch with no refresh under it.

    It replaces a predicate that CLASSIFIED THE PATHS a commit touched, and the
    replacement is the fix for round 012's finding 1 rather than a tidy-up. That
    predicate had to answer for every commit shape whose paths it could not
    read — a merge, an empty commit — and it answered "stop", which reads as
    "this might have invalidated the verdict" for a commit that provably did
    not. `agent_common.commit_telemetry` then began writing exactly that shape:
    a `Review-Verdict:` attestation must land even when the bookkeeping it rides
    is unchanged, so it commits EMPTY, and the very commit that RECORDS an
    approval buried the refresh underneath it. Asking the identity question
    directly makes the empty carrier, the merge commit and the quoted-path trap
    (`is_record_path` against git's display encoding, round 007's finding 3
    pointed the more dangerous way round) all unrepresentable at once, because
    no path is classified here at all."""
    rev = rev or branch
    identity = tree_identity(root, rev)
    for _ in range(_MAX_GOVERNING_WALK):
        peeled = _peel_target(root, branch, rev)
        if peeled is not None:
            rev = peeled
            identity = tree_identity(root, rev)
            continue
        step = _identity_step(root, rev, identity)
        if step is None:
            break  # this commit changed the work, so it is where the walk ends
        rev, identity = step
    return _rev(root, rev)


def review_attestation(root, rev, tests):
    """`(attested sha, None)` when `rev`, or a commit beneath it that only
    record-only commits separate from it, carries a verified `review`
    attestation whose tests digest is `tests_digest(tests)`; else `(None,
    cause)`.

    The walk looks at `rev`, then steps to the first parent only while the
    non-record identity is unchanged (`_identity_step`, the step
    `governing_rev` takes), so a round file, a telemetry fragment or an empty
    commit above an attested commit needs no new bar. The first verified record
    it meets decides: another bar, a refresh's `landing` included, is refused
    as one, and so is another tests digest. It never peels a disposable commit
    and never runs the bar: it reads the record.

    Implements: SR-241, LLR-341
    """
    want = tests_digest(tests)
    rev = _rev(root, rev) or rev
    identity = tree_identity(root, rev)
    for _ in range(_MAX_GOVERNING_WALK):
        attested, cause = read_bar_attestation(root, rev)
        if attested is not None:
            return _review_record_answer(rev, attested, want)
        step = _identity_step(root, rev, identity)
        if step is None:
            return None, (
                "{} has no verified attestation ({}), and it changes non-record "
                "paths over its parent, so no commit beneath it stands for "
                "it".format(rev, cause)
            )
        rev, identity = step
    return None, "no verified attestation within {} record-only commits".format(
        _MAX_GOVERNING_WALK
    )


def _review_record_answer(rev, attested, want):
    """`review_attestation`'s answer at the first verified record it meets."""
    if attested.bar != "review":
        return (
            None,
            "{} carries a verified `{}` attestation, not a `review` one".format(
                rev, attested.bar
            ),
        )
    if attested.tests != want:
        return None, (
            "{}'s review attestation is for tests={}, but the round's tests "
            "digest to {}".format(rev, attested.tests, want)
        )
    return rev, None


def governing_identity(root, branch, rev=None):
    """The non-record tree identity a verdict at `rev` on `branch` governs, or
    None. `rev` defaults to the branch tip: the identity a verdict must NAME.

    THE ONE ANSWER EVERY READER IS HANDED (WI-560 Done-when 1). The merge slot
    asks "may this branch merge?" and the loop asks "does this lane still owe a
    round?"; they are the same question from two sides, and each computing its
    own rev is how they came to disagree across a refresh commit. Composing the
    two halves HERE — the record-path fold and the refresh peel — leaves the
    callers nothing to choose.

    "EVERY READER" INCLUDES THE ONES THAT ASK ABOUT A COMMIT rather than about
    the branch — `round_entries` for the sha a round file cites, and
    `branch_trailers` for the commit an attestation rides. They used to call
    `tree_identity` directly, which is the same composition with the peel left
    out, and the two answers part company across exactly one refresh commit:
    a round drawn AFTER a refresh named the post-refresh tree while the gate
    governed by the pre-refresh one, so the round was invisible to BOTH readers
    and no commit on the branch could ever make them agree (REVIEW-A round 015).
    One function, one rev rule, asked at whichever commit the caller holds."""
    return tree_identity(root, governing_rev(root, branch, rev))


def _rev(root, rev):
    """`rev` resolved to a full sha, or None."""
    out = git_out(root, ["rev-parse", "--verify", "--quiet", rev])
    return out.strip() if out and out.strip() else None


# --- the round evidence -------------------------------------------------------


def round_file(path):
    """`(train, ordinal, phase, reviewed_sha)` for a round file, else None.

    `train` is the `docs/reviews/<train>/` directory, or "" for the flat
    pre-train layout. The ordinal is an int so "latest" is a numeric comparison,
    which is what `score_reviews.latest_phase_verdicts` sorts on."""
    norm = str(path).replace("\\", "/")
    if not norm.startswith(_REVIEWS + "/"):
        return None
    rest = norm[len(_REVIEWS) + 1 :]
    train, _sep, name = rest.rpartition("/")
    if "/" in train:
        return None  # nested deeper than one train directory: not a round file
    matched = ROUND_FILE_RE.match(name)
    if not matched:
        return None
    return (
        train,
        int(matched.group("ordinal")),
        matched.group("phase"),
        matched.group("sha"),
    )


def session_log(path):
    """`(train, ordinal)` for a coordinator session log, else None."""
    norm = str(path).replace("\\", "/")
    if not norm.startswith(_ITERATION + "/"):
        return None
    name = norm[len(_ITERATION) + 1 :]
    if "/" in name:
        return None
    matched = SESSION_LOG_RE.match(name)
    if not matched:
        return None
    return matched.group("train") or "", int(matched.group("ordinal"))


# --- the session's recorded range, and what a REVIEW session may change -------


def parse_range(text):
    """`(before, after)` for a `before..after` commit range, or None.

    None for an empty range (the session committed nothing) and for the loop's
    placeholders when a head could not be read: neither names commits a reader
    could diff or show, and a range that names nothing contributed nothing.

    Implements: SR-154, LLR-262
    """
    matched = _RANGE_RE.match((text or "").strip())
    return (matched.group(1), matched.group(2)) if matched else None


def session_range(blob):
    """The `(before, after)` range a session log's `# commits:` header records,
    or None when it records none.

    THE ONE RECORD NO COMMIT CARRIES FOR ITSELF. Every commit has the same
    author, subjects are free-form and a reviewer carries no trailer, so nothing
    on a commit reliably names the role that made it. The coordinator does know:
    it takes the session's exact range right after the session ends and before
    it commits anything of its own, and writes it here beside the phase.

    Implements: SR-154, LLR-262
    """
    header = _COMMITS_HEADER_RE.search((blob or "")[:4000])
    return parse_range(header.group(1)) if header else None


def format_scope(kind, base, sha, stage=""):
    """The `# review-scope:` value the loop records for a REVIEW session of
    `kind` (`FULL` or `NARROW`) over `base..sha`; a base it could not name
    renders `?`, which no reader takes for a range.

    `stage` is the keep stage the round's draw settled
    (`session_keep.review_retention`, WI-887): a FULL round drawn under the
    `final` stage renders the distinct kind `final`, the coordinator's record
    that this round ran on the persisted final reviewer's own scope. The kind
    is derived here from the drawn stage, never composed by a caller, so a
    narrow round, or a full round drawn under no stage, cannot carry it.

    Implements: SR-156, LLR-207
    """
    final = kind == FULL and stage == FINAL
    return "{} {}..{}".format(FINAL if final else kind, base or "?", sha or "?")


def gating_span(blob, persisted=False):
    """`(claim base, reviewed sha)` when a REVIEW session log records the scope
    a merge may be judged on, else None.

    THE TWO FACTS ARE THE COORDINATOR'S, never the reviewer's: the FULL scope
    it routed the round under, over a readable range, and a session minted for
    that round (an empty `# session-gen:`; a retained session records its
    generation there). A narrow round, a missing or malformed scope, or a
    retained session yields None, which every reader of round evidence turns
    into no gate authority: a narrow verdict steers iteration and nothing else
    (WI-884's Trust ruling).

    `persisted` is the resolved persisted-final-reviewer mode (WI-887,
    `kitlib.config.reviewer_dials`: `final_reviewer = "persisted"` with
    review retention on). In it, and only in it, a `final` round also gates:
    the kind the coordinator recorded for a full round its draw kept under
    the final reviewer's own stage (`format_scope`). The mode word never
    promotes a `full` round: a retained session's `full` round holds in both
    modes, so an iteration reviewer's session cannot clear the gate.

    Implements: SR-156, LLR-207
    """
    head = (blob or "")[:4000]
    scope = _SCOPE_HEADER_RE.search(head)
    generation = _GEN_HEADER_RE.search(head)
    kind, _sep, span = (scope.group(1).strip() if scope else "").partition(" ")
    if generation is None:
        return None
    fresh_full = kind == FULL and not generation.group(1).strip()
    admitted = fresh_full or (kind == FINAL and persisted)
    return parse_range(span) if admitted else None


def filing_refusal(text, sha, parse):
    """Why `text` is not a review of the full commit `sha` in the kit's verdict
    format, or None: THE FILING CHECK, stated once.

    `review_brief.review_refusal` files nothing this refuses, and
    `round_entries` reads a committed round this refuses as INVALID EVIDENCE,
    never as a verdict of either kind, so a partial write or a garbled round
    cannot clear the gate the filing boundary would have kept it from. It must
    open with `Reviewed: <sha>` as its FIRST PHYSICAL LINE, exactly — the text
    up to its first LF, less a CR ending it, with no line skipped and nothing
    stripped, as the brief tells the reviewer — carry exactly one canonical
    VERDICT line (the shared review-line reader inside `parse`) whose count
    matches its finding lines, and name a finding when it requests changes.
    `parse` is `score_reviews.parse_verdict`, injected as everywhere in this
    module.

    Implements: SR-156, LLR-207
    """
    first = (text or "").split("\n", 1)[0]
    if first.removesuffix("\r") != "Reviewed: " + sha:
        return "its first line is not `Reviewed: {}`".format(sha)
    parsed = parse(text)
    if parsed.verdict is None:
        return parsed.refusal or "it carries no VERDICT line"
    found = len(parsed.findings)
    if parsed.declared_n != found:
        return "its VERDICT line says findings={} but it carries {}".format(
            parsed.declared_n, found
        )
    if parsed.verdict == "CHANGES-REQUESTED" and not found:
        return "it requests changes but names no finding"
    return None


def range_paths(root, span):
    """Every path the commits `before..after` changed, sorted, or None when git
    cannot answer. `--no-renames`, so a moved file names BOTH ends: a session
    that renamed something changed two paths, and the check must see both.

    Implements: SR-154, LLR-262
    """
    out = git_out(root, ["diff", "--name-only", "--no-renames", span[0], span[1]])
    if out is None:
        return None
    return sorted({ln.strip() for ln in out.splitlines() if ln.strip()})


def scope_offenders(changed, train, ordinal, phase):
    """The paths in `changed` that are NOT the REVIEW session's own verdict
    file, sorted - [] when the session changed nothing else.

    ITS OWN VERDICT FILE is the round file named for the session's
    `(train, ordinal)` AND the phase its log declares, under any reviewed sha
    and tag. Record paths are not exempt, and that is the point of stating it
    as one path rather than as "anything under docs/reviews/": a second round
    file is a verdict this session had no business writing, a scoreboard is the
    coordinator's, and a log fragment is a builder's. The live loop and the
    merge slot both ask THIS function, so the check right after the session and
    its re-derivation at merge cannot drift into two rules.

    Implements: SR-154, LLR-262
    """
    own = (train, ordinal, phase)
    return sorted(
        path
        for path in changed
        if (round_file(path) or (None, None, None, None))[:3] != own
    )


def session_scope_offenders(root, commits, verdict_path):
    """The live loop's half of S9: the paths a REVIEW session's just-taken
    range `commits` (`before..after`, "" when it committed nothing) changed
    beside `verdict_path`, the verdict file it was handed - [] when none.

    The session's (train, ordinal, phase) are read off that path, the name the
    loop composed for it, and the rule is `scope_offenders`, the one the merge
    slot re-derives from the logs. A range that cannot be read is named rather
    than passed: unread commits are not clean ones.

    Implements: SR-154, LLR-262
    """
    if not commits:
        return []
    rel = os.path.relpath(str(verdict_path), str(root)).replace(os.sep, "/")
    span = parse_range(commits)
    changed = range_paths(root, span) if span else None
    parsed = round_file(rel)
    if changed is None or parsed is None:
        return ["(the range {} could not be read)".format(commits)]
    return scope_offenders(changed, *parsed[:3])


def log_history(root, branch, base):
    """`(added, rewritten)` over the session logs `base..branch`'s own commits
    touched, or None when git cannot answer: `added` maps each log to the
    commit that ADDED it (the oldest, should it be added twice), `rewritten`
    lists `(sha, "M"|"D", path)` for every commit that modified or deleted one.

    A SESSION LOG IS APPEND-ONLY EVIDENCE. The coordinator writes each one once,
    in its own telemetry commit, and nothing in the loop edits it again; so a
    later commit touching one is rewriting the record the checks key on - the
    phase, and the range a round is read at and a review's scope is judged by.
    Merge commits list no paths here, so a refresh bringing trunk's own logs
    in rewrites nothing.

    Implements: SR-154, SR-156, LLR-262
    """
    out = git_out(
        root,
        [
            "log",
            "--no-renames",
            "--name-status",
            "--format=%x00%H",
            "{}..{}".format(base, branch),
            "--",
            _ITERATION,
        ],
    )
    if out is None:
        return None
    added, rewritten = {}, []
    for sha, status, path in _log_changes(out):
        if status == "A":
            added.setdefault(path, sha)
        elif status in ("M", "D"):
            rewritten.append((sha, status, path))
    return added, rewritten


def _log_changes(out):
    """`(sha, status, path)` for each session-log change in a `--name-status`
    listing whose records open with `\\x00<sha>`, OLDEST commit first."""
    changes = []
    for record in reversed(out.split("\x00")):
        lines = [ln for ln in record.splitlines() if ln.strip()]
        for line in lines[1:]:
            status, _tab, path = line.partition("\t")
            if session_log(path) is not None:
                changes.append((lines[0].strip(), status, path))
    return changes


def review_logs(root, branch, base, paths):
    """Every coordinator session log among `paths` that declares a REVIEW
    phase, as `(log_path, (train, ordinal), phase, span, gate)`, read AS THE
    COMMIT THAT ADDED IT recorded it (`log_history`), never at the branch tip.

    `span` is the log's recorded range, or None when it records none; `gate`
    is its `gating_span` under the repository's resolved final-reviewer mode
    (`kitlib.config.reviewer_dials`, both dials, read once here so every
    reader of round evidence applies the same mode), None for every round
    that carries no
    gate authority. A log
    that cannot be read, or that no commit in `base..branch` added, is left
    out, which every reader of this list turns toward more review: no round
    comes from it, and the scope check at merge has nothing to clear it with
    either (and refuses the rewrite itself, by name).

    Implements: SR-154, SR-156, LLR-207, LLR-262
    """
    history = log_history(root, branch, base)
    added = history[0] if history else {}
    persisted = reviewer_dials(root)[1] == FINAL_PERSISTED
    found = []
    for path in paths:
        key = session_log(path)
        if key is None or path not in added:
            continue
        blob = git_out(root, ["show", "{}:{}".format(added[path], path)])
        if blob is None:
            continue
        header = _PHASE_HEADER_RE.search(blob[:4000])
        phase = header.group(1).strip() if header else ""
        if phase in REVIEW_PHASES:
            gate = gating_span(blob, persisted)
            found.append((path, key, phase, session_range(blob), gate))
    return found


# --- the red record: a review bar that refused a build, and the count -----------

# A red result is written into a session log's header, keyed by the build
# commit whose tip the bar refused:
#
#     # bar-red: <40-hex build sha>
#     # bar-summary: <one line>
#
# `format_red_record` is the one writer of the two fields (the loop hands them
# to `agent_common.write_session_log`) and `parse_red_record` the one reader.
# Only the header counts: a transcript quoting the line is no record.
RED_KEYS = ("bar-red", "bar-summary")
_SHA40_RE = re.compile(r"^[0-9a-f]{40}$")
_BAR_RED_RE = re.compile(r"^# bar-red:[ \t]*([0-9a-f]{40})[ \t]*$", re.M)
_BAR_SUMMARY_RE = re.compile(r"^# bar-summary:[ \t]*(.*)$", re.M)
_SUMMARY_MAX = 240
_SUMMARY_GAP = " ... "
_SUMMARY_HEAD = 80


def format_red_record(sha, summary):
    """`{"bar-red": sha, "bar-summary": one line}`, the header fields of a red
    record. The summary's whitespace folds to single spaces; a longer line
    keeps its first `_SUMMARY_HEAD` characters (the refusal's cause) and its
    tail (where a bar prints its final diagnostic), joined by `_SUMMARY_GAP`,
    within `_SUMMARY_MAX` characters. This line is the only copy a resumed
    build is handed, so the tail is the part it cannot lose. A sha that is not
    40 lowercase hex raises, so the writer cannot emit a record the reader
    refuses.

    Implements: SR-242, LLR-343
    """
    if not _SHA40_RE.match(str(sha)):
        raise ValueError("a red record names a 40-hex build sha, not {!r}".format(sha))
    line = " ".join(str(summary).split())
    if len(line) > _SUMMARY_MAX:
        tail = _SUMMARY_MAX - _SUMMARY_HEAD - len(_SUMMARY_GAP)
        line = line[:_SUMMARY_HEAD] + _SUMMARY_GAP + line[-tail:]
    return dict(zip(RED_KEYS, (sha, line or "(no summary)")))


def parse_red_record(blob):
    """`(build sha, summary)` for a session log's red record, else None. Read
    from the header alone, the lines before the log's `# ---` separator.

    Implements: SR-242, LLR-343
    """
    header = blob.split("\n# ---", 1)[0]
    matched = _BAR_RED_RE.search(header)
    if matched is None:
        return None
    summary = _BAR_SUMMARY_RE.search(header)
    return matched.group(1), summary.group(1).strip() if summary else ""


class RedCount(NamedTuple):
    """The lane's consecutive red review-bar rounds and the last bar summary."""

    count: int
    last_summary: str


def red_rounds(root, branch, base):
    """The consecutive red review-bar rounds `base..branch` records, as a
    `RedCount`, or None when git cannot list that history.

    The newest commit in the range carrying a verified `review` attestation is
    the last green, and it resets the count. Every session log the range's
    commits added is read as the commit that added it (`log_history`, so a
    later rewrite changes nothing), and each red record whose build sha is not
    an ancestor of that green counts. DISTINCT shas give the count, so a red
    recorded twice for one build counts once, and the last summary is the
    newest counted record's. A log git cannot show counts as one red keyed by
    its path (unless the commit that added it is beneath the green): an
    unreadable record counts toward the cap, never away from it. Both callers
    read None as "at the cap" for the same reason.

    Implements: SR-242, LLR-343
    """
    history = log_history(root, branch, base)
    green = _last_review_green(root, branch, base)
    if history is None or green is None:
        return None
    reds, last = set(), ""
    for path, added in history[0].items():
        red = _logged_red(root, path, added)
        if red is None or (green and _is_ancestor(root, red[2], green)):
            continue
        reds.add(red[0])
        last = red[1]
    return RedCount(len(reds), last)


def red_record(root, branch, base, sha):
    """The summary of the red record `base..branch`'s session logs hold for the
    build commit `sha`, or None when none does: whether a review bar already
    refused that build, so a draw over it rebuilds without running the bar
    again. A log git cannot show names no build, so it answers nothing here.

    Implements: SR-242, LLR-343
    """
    history = log_history(root, branch, base)
    found = None
    for path, added in (history[0] if history else {}).items():
        red = _logged_red(root, path, added)
        if red is not None and red[0] == sha:
            found = red[1]
    return found


def _logged_red(root, path, added):
    """`(key, summary, dated by)` for the red one session log records, read at
    the commit `added` that added it, else None. A readable log keys its red
    by the build sha and is dated by it; a log git cannot show keys one red by
    its path and is dated by the commit that added it.

    Implements: SR-242, LLR-343
    """
    blob = git_out(root, ["show", "{}:{}".format(added, path)])
    if blob is None:
        return path, "(session log {} could not be read)".format(path), added
    record = parse_red_record(blob)
    return None if record is None else (record[0], record[1], record[0])


def _last_review_green(root, branch, base):
    """The newest commit in `base..branch` carrying a verified `review`
    attestation, "" when none does, None when git cannot list the range.

    Implements: SR-242, LLR-343
    """
    out = git_out(root, ["log", "--format=%x00%H%n%B", "{}..{}".format(base, branch)])
    if out is None:
        return None
    for record in out.split("\x00")[1:]:
        sha, _sep, message = record.partition("\n")
        if not any(ln.startswith(BAR_GREEN) for ln in message.splitlines()):
            continue
        attested = bar_attestation(root, sha.strip())
        if attested is not None and attested.bar == "review":
            return sha.strip()
    return ""


def _is_ancestor(root, rev, of):
    """True when `rev` is `of` or an ancestor of it; False when it is not, or
    git cannot say.

    Implements: SR-242, LLR-343
    """
    return git_out(root, ["merge-base", "--is-ancestor", rev, of]) is not None


def review_scope_refusal(root, branch, base):
    """S9 AT THE MERGE SLOT: the first REVIEW session in `base..branch` whose
    recorded range changed anything but its own verdict file, as a refusal
    naming the session log and the paths - or None.

    RE-DERIVED FROM THE COMMITTED LOGS, not trusted from the loop's live check
    right after the session, which is what makes it evidence: a crashed or
    resumed run, or a lane some other process drove, reaches the slot all the
    same. On a build lane nothing else stands between a reviewer's own edit
    and trunk, so this is that lane's final pass. Unreadable evidence refuses.

    Implements: SR-154, SR-156, LLR-262
    """
    paths = branch_paths(root, branch, base)
    history = log_history(root, branch, base)
    if paths is None or history is None:
        return "cannot read the session logs {} committed".format(branch)
    for sha, status, log in history[1]:
        return (
            "commit {} {} the session log {} after it was committed - a "
            "session log is append-only evidence, so the lane's review record "
            "cannot be trusted".format(
                sha[:10], "modified" if status == "M" else "deleted", log
            )
        )
    for log, (train, ordinal), phase, span, _gate in review_logs(
        root, branch, base, paths
    ):
        if span is None:
            continue
        changed = range_paths(root, span)
        if changed is None:
            return "cannot read the range {}..{} that {} records".format(
                span[0][:10], span[1][:10], log
            )
        extra = scope_offenders(changed, train, ordinal, phase)
        if extra:
            return (
                "the {} session logged at {} committed outside its verdict "
                "file in {}..{}: {}".format(
                    phase, log, span[0][:10], span[1][:10], ", ".join(extra)
                )
            )
    return None


def branch_paths(root, branch, base):
    """Every path `base..branch`'s OWN commits touched under the two record
    directories, or None when git cannot answer.

    Scoped to the branch's own commits on purpose: a lane branch carries every
    historical train's round files inherited from the trunk, and resolving a
    tree identity for each of them would cost hundreds of git calls to reject
    hundreds of rounds that could not name this tree anyway."""
    out = git_out(
        root,
        [
            "log",
            "--format=",
            "--name-only",
            "{}..{}".format(base, branch),
            "--",
            _REVIEWS,
            _ITERATION,
        ],
    )
    if out is None:
        return None
    return sorted({ln.strip() for ln in out.splitlines() if ln.strip()})


def logged_rounds(root, branch, base, paths):
    """The rounds among `paths` that a LOGGED REVIEWER SESSION produced, as
    `(ordinal, phase, reviewed_sha, path, read_at, reviewed)` — the plan's
    finding K, closed. `reviewed` is the full commit the round's gating span
    names.

    ONLY A ROUND THAT MAY GATE A MERGE (WI-884): its log records the FULL scope
    from a session minted for the round (`gating_span`), and that span runs
    from `base`, which every caller passes as the lane's recorded claim base,
    to the commit the round file names. A narrow round, or a full one over any
    other range, is no round here, so no reader of this evidence can fall back
    to it.

    A round file with no coordinator session log for its (train, ordinal), or
    one whose log declares a non-review phase, is NOT a round: it is a file
    somebody wrote in the review path. An unreadable log is treated the same
    way, which is the fail-toward-more-review direction.

    THE PHASE IS THE LOG'S, NEVER THE FILENAME'S, and that is why the name's
    `phase` group is not read here at all. A round's phase had TWO sources —
    the FILENAME a session chooses for itself and the coordinator's committed
    session log — joined on (train, ordinal) alone, so one logged REVIEW-A
    session admitted a `REVIEW-B` file written in the same commit and at
    `review_rounds = 2` the gate cleared on a SINGLE reviewer, which is the
    whole content of the policy (driven end-to-end: `branch_entries` returned
    both phases, `round_count` agreed, and the merge was allowed). Deleting the
    session-chosen source leaves one owning boundary, validated once, after
    which a file's name cannot claim a phase its session did not serve — the
    name's remaining job is only to say which round this is and what it read.

    A (train, ordinal) whose logs declare MORE THAN ONE review phase is
    ambiguous and yields no round: the fail-closed answer, and the reason this
    reads a set rather than letting the last path scanned win.

    A ROUND IS WHAT ITS SESSION COMMITTED, so each carries the rev it is READ
    at: the end of the range the session's own log records, and only when that
    range changed the round file. The files live under `docs/reviews/`, a record
    path, so a later session rewriting one moves neither the governing identity
    nor the implementer-touch tripwire; read at the branch tip, a later session
    could turn a reviewer's refusal into an approval the gate counted (driven:
    WI-608, review pack C4). Read at the session's own commit, a later edit has
    nothing to change. The same rule makes a file its session wrote and never
    committed no round at all, which is the loop's rule too - it routes only on
    a verdict as committed. A key whose logs disagree on the range is the
    ambiguity above, answered the same way.

    Implements: SR-154, SR-156, LLR-207, LLR-262
    """
    declared = {}
    for _log, key, phase, span, gate in review_logs(root, branch, base, paths):
        declared.setdefault(key, set()).add((phase, span, gate))
    reviewer = {key: rec.pop() for key, rec in declared.items() if len(rec) == 1}
    touched = {}
    rounds = set()
    for path in paths:
        parsed = round_file(path)
        if parsed is None:
            continue
        train, ordinal, _name_phase, sha = parsed
        phase, span, gate = reviewer.get((train, ordinal), (None, None, None))
        if span is None or not _binds(gate, base, sha):
            continue
        if span not in touched:
            touched[span] = range_paths(root, span) or []
        if path in touched[span]:
            rounds.add((ordinal, phase, sha, path, span[1], gate[1]))
    return sorted(rounds)


def _binds(gate, base, sha):
    """Whether a log's gating span runs from `base`, the lane's recorded claim
    base, to the reviewed commit its round file names."""
    return gate is not None and gate[0] == base and gate[1].startswith(sha)


def round_entries(root, branch, rounds, want, parse):
    """The `(phase, ordinal, verdict)` entries `score_reviews.latest_phase_verdicts`
    reads, restricted to the rounds that NAME the tree `want`.

    The tree a round names is the GOVERNING identity of the commit its FILENAME
    cites — the reviewed head, which the reviewer session did not author. That
    is the binding; the `Review-Verdict:` trailer is the same name spelled for a
    machine (see `branch_trailers`), never a second source of truth.

    GOVERNING, not raw: through `governing_identity` and not `tree_identity`,
    because `want` is composed that way and a binding must be computed by the
    same definition it is compared against. A reviewer that read the branch
    right after a station refresh cites the POST-refresh sha, while the gate
    governs by the peeled PRE-refresh tree — so the raw fold made the two
    permanently unequal, the round invisible to the merge slot AND to
    `agent_loop.review_owed_by_evidence`, and the lane re-drew an identical
    round every tick: the double-identical-round class WI-560 Done-when 1 exists
    to make unrepresentable, re-entered through the binding rather than through
    the rev (REVIEW-A round 015). It is reachable on the shipped path because
    `dispatch._advance` spawns a lane's refresh as soon as its worker is DONE
    and BEFORE `integrate.integrate` runs, so any slot refusal parks the branch
    with a refresh commit and no round, and the next launch draws the round on
    top of it.

    `parse` is `score_reviews.parse_verdict`, injected rather than imported so
    this leaf keeps no edge back into the scoring layer. An entry whose verdict
    is None is invalid evidence (`filing_refusal`), never a verdict."""
    entries = []
    resolved = {}
    for ordinal, phase, sha, path, read_at, reviewed in rounds:
        if sha not in resolved:
            resolved[sha] = governing_identity(root, branch, sha)
        if resolved[sha] != want:
            continue
        # AT THE SESSION'S OWN COMMIT (`logged_rounds`), never at the tip. An
        # unreadable file, or one the filing check refuses (a partial write, a
        # garble), is INVALID EVIDENCE: an entry with no verdict, so it is the
        # phase's last word and no older APPROVE governs past it.
        text = git_out(root, ["show", "{}:{}".format(read_at, path)])
        if text is None or filing_refusal(text, reviewed, parse):
            entries.append((phase, ordinal, None))
            continue
        parsed = parse(text)
        # THROUGH `effective_verdict`, the same call `agent_loop` routes on: a
        # MINOR-only CHANGES-REQUESTED is an APPROVE for both readers or for
        # neither (see there). The FILE is untouched — this reads it.
        entries.append(
            (phase, ordinal, effective_verdict(parsed.verdict, parsed.findings))
        )
    return entries


def branch_entries(root, branch, base, want, parse):
    """Tree-bound entries from logged rounds in `base..branch`, or None when
    the branch's committed path set cannot be read."""
    paths = branch_paths(root, branch, base)
    if paths is None:
        return None
    rounds = logged_rounds(root, branch, base, paths)
    return round_entries(root, branch, rounds, want, parse)


def tree_already_judged(root, branch, base, parse):
    """Has a logged round ALREADY named the branch's CURRENT governing tree?

    The question `integrate._round_refusal` asks at the merge slot, asked by
    `agent_loop.schedule_review_round` BEFORE a round is drawn instead of after
    it is wasted — which is why it lives here beside the readers rather than in
    either of them.

    WHY (measured 2026-09-03). A rework session that DECLINED a finding
    committed only its answer under `docs/reviews/` — a record path this module
    is built to ignore — so `governing_identity` did not move. The loop armed
    another round, the reviewer approved the very tree it had refused, and the
    slot read the pair as a reroll-until-green and refused the lane. Two
    reviewer sessions and a merge attempt bought nothing.

    Unreadable git, or an unreadable path set, answers False: a lane whose
    evidence cannot be read has not been SHOWN to be unchanged, and refusing to
    draw a round on git's silence would stop every first build in a repo these
    readers cannot see into.

    ONLY A VERDICT THAT COULD GATE COUNTS (WI-884): `base` is the lane's claim
    base, so a narrow round is no entry, and an entry with no verdict is
    invalid evidence. Paging on either would stop the lane before the fresh
    full-lane round the gate needs, so neither answers True; nor does a lane
    with no claim base.

    Implements: SR-156, LLR-207"""
    want = governing_identity(root, branch)
    if want is None or not base:
        return False
    entries = branch_entries(root, branch, base, want, parse) or ()
    return any(verdict for _phase, _ordinal, verdict in entries)


def declared_phases(required):
    """The review phases a policy of `required` declares, in dispatch order.

    THE SPAN BOTH READERS SLICE, and it is here because they must slice it
    identically: the merge slot demands a verdict for each of these phases and
    the loop schedules each of them, so a policy the two read to different
    lengths is a lane that draws what will not clear or refuses what will never
    be drawn. The clamp is the whole content — a policy above `REVIEW_PHASES`
    asks for a phase no reviewer can be routed to (`agent_loop.
    _clamped_review_rounds` clamps the dial to the same span), and a NEGATIVE
    one slices from the END, so a bare `REVIEW_PHASES[:required]` would answer
    a policy of -1 with `("REVIEW-A",)` — a wrong answer rather than an empty
    one. Both callers guard the negative case today; neither should have to."""
    return list(REVIEW_PHASES[: max(0, required)])


def phases_owed(entries, required):
    """The declared phases whose LATEST entry among `entries` is missing or
    invalid evidence — the phases this tree has never had drawn with a verdict,
    which is `agent_loop.resume_owed_round`'s question.

    THE WEDGE THIS CLOSES. The merge slot began requiring every declared phase
    (round 022's finding — `review_rounds = 2` had been collapsed to a boolean,
    so a lone REVIEW-A cleared the gate) while `review_owed_by_evidence` still
    read "any entry at this tree means the round was served". A run that died
    between REVIEW-A and REVIEW-B left exactly that state — the phase queue is
    in-memory run state and does not survive the run — so the resumed lane
    scheduled nothing while the gate refused the merge for a phase nobody would
    ever draw. Answering with the MISSING PHASES rather than a yes/no is what
    lets the resume redraw only those, which matters as much as the fix: a
    resume that redrew the whole round would re-run a phase already served at
    this identity, and if that phase had DISSENTED the redraw would read as a
    reroll-until-green and be escalated — the gate's own `flipped` rule firing
    on an honest crash recovery.

    NOT THE GATE'S QUESTION. This asks whether a phase was drawn with a
    verdict; the gate asks whether that verdict is an APPROVE
    (`score_reviews.latest_phase_verdicts`), so a dissent is served here and
    refused there. An UNREADABLE, partial or refusable round file is owed on
    both sides (WI-884's Trust ruling): it is invalid evidence, never a verdict
    of either kind, so the full-lane round is still owed and is drawn again,
    and an older verdict at the same tree never stands in for it. What the two
    may NOT differ on is the phase span, which is why both slice
    `declared_phases`.

    Implements: SR-156, LLR-207"""
    latest = {}
    for phase, _ordinal, verdict in sorted(entries or (), key=lambda e: e[1]):
        latest[phase] = verdict
    return [ph for ph in declared_phases(required) if not latest.get(ph)]


def round_count(entries):
    """Completed review cycles represented by the entries for ONE tree.

    A cycle contributes one entry per configured phase (REVIEW-A and, at
    policy 2, REVIEW-B), so the cycle count is the largest per-phase count —
    not the raw number of reviewer files. Callers first restrict `entries` to
    one tree through `round_entries`; rework therefore starts this count over.
    """
    per_phase = {}
    for phase, _ordinal, _verdict in entries:
        per_phase[phase] = per_phase.get(phase, 0) + 1
    return max(per_phase.values(), default=0)


def format_branch_trailer(root, branch, base, word, parse):
    """The tree-bound trailer derived from logged branch evidence, or None.

    Stamped at `governing_identity`, the value both readers key on. Naming the
    branch's RAW tree instead filed the attestation under a key
    `integrate._round_refusal` never looks up, so on a refreshed branch the
    cross-check silently stood down instead of cross-checking (REVIEW-A round
    015). `branch` must therefore be the lane's BRANCH NAME and not `HEAD`: the
    peel verifies a refresh commit against the branch it names, and `HEAD`
    matches no refresh subject."""
    if not word:
        return None
    tree = governing_identity(root, branch)
    if tree is None:
        return None
    entries = branch_entries(root, branch, base, tree, parse)
    if entries is None:
        return None
    count = round_count(entries)
    return format_trailer(word, count, tree) if count else None


def branch_trailers(root, branch, base):
    """`{reviewed tree: [(word, rounds), ...]}` from every VERIFIED
    `Review-Verdict:` trailer on the branch's own commits, or None when git
    cannot answer. Each list is in COMMIT ORDER, oldest first, so `[-1]` is the
    newest attestation for that tree.

    A SEQUENCE, not one attestation per tree, and the type is the fix. One tree
    carries more than one attestation whenever a round is re-drawn without the
    work changing — `score_reviews.latest_phase_verdicts` exists precisely
    because "a phase was re-run at the same commit" — and a last-write-wins map
    fed from `git log` (which is NEWEST-first) handed its reader the OLDEST
    stamp. Driven: two honest rounds at one governing tree, stamped `rounds=1`
    then `rounds=2`, made the merge slot report the evidence and the attestation
    as disagreeing and park an approved lane at a supervisor stop — the OI-76
    failure mode, re-created by the cross-check meant to prevent it (REVIEW-A
    round 007, finding 1). The order of a git history is not this module's to
    own, so the shape that let a superseded stamp arrive SILENTLY is gone rather
    than guarded.

    VERIFIED means the trailer names the GOVERNING identity of the commit that
    CARRIES it — the `Bar-Green` verification applied to a verdict, through the
    one rev rule rather than beside it. The record commit only touches record
    paths, so the tree it governs IS the reviewed tree, and a trailer amended
    onto a commit that changed the work names a tree that is not its carrier's.
    Verifying with the raw fold instead would reject every honest attestation on
    a refreshed branch, because the writer must stamp the value the READERS key
    on and that value is the peeled one.

    THIS IS NOT AN ACCEPT PATH, and the distinction is the whole anti-forgery
    story. Anyone with commit access can type a trailer onto their own commit
    and it will verify, because it is their tree. What a trailer cannot forge is
    the coordinator's committed session log, which is why the ROUND EVIDENCE
    decides and the trailer is read as a CROSS-CHECK: a trailer that names the
    tree under judgement and contradicts the rounds is a signal, not a verdict."""
    log = git_out(root, ["log", "--format=%H%x1f%B%x1e", "{}..{}".format(base, branch)])
    if log is None:
        return None
    by_tree = {}
    # `git log` is newest-first; reversed() makes each list oldest-first, which
    # is the order a reader means by "the latest attestation".
    for record in reversed(log.split("\x1e")):
        sha, _sep, message = record.partition("\x1f")
        sha = sha.strip()
        if not sha:
            continue
        parsed = parse_trailer(message)
        if parsed is None:
            continue
        word, rounds, tree = parsed
        if governing_identity(root, branch, sha) != tree:
            continue  # the words rode onto a tree they do not describe
        by_tree.setdefault(tree, []).append((word, rounds))
    return by_tree


# --- an AMENDMENT verdict's row rulings ----------------------------------------
#
# The two row tags of an amendment verdict, in the brief's own grammar
# (`prompts/adjudicate-amendment.template.md`): `- [MEANING|CLARITY] <row-id> ...`.
# Moved here from `acceptance_record` (WI-841 round 5), which keeps the name as
# an alias and stays under the module-size ratchet's threshold: a pure reader of
# a verdict's text, beside this module's other verdict readers.
# Each sitting kind's row tags, and the ruling that wins when a row is tagged
# both ways (its brief's fail-toward rule): the ONE row reader of a verdict.
# The amendment's `- [MEANING+BLESS]` tag is the bless mark (WI-912, Q2 of
# coordinator-2026-10-14 D-003): a MEANING row whose new text the adjudicator
# would bless. It reads MEANING here, so every reader of the rulings is
# unchanged; `blessed_rows` is the one reader of the mark itself.
BLESS_TAG = "- [MEANING+BLESS]"
ROW_RULINGS = {
    "amendment": (
        {"- [MEANING]": "MEANING", "- [CLARITY]": "CLARITY", BLESS_TAG: "MEANING"},
        "MEANING",
    ),
    "first-approval": ({"- [APPROVE]": "APPROVE", "- [RETURN]": "RETURN"}, "RETURN"),
}


def _ruled_row(line, tags):
    """`(word, row id)` for one verdict row line, else None."""
    head = line.strip()
    for tag, word in tags.items():
        rest = head[len(tag) :].split() if head.startswith(tag) else []
        if rest:
            return word, rest[0]
    return None


def row_rulings(text, kind):
    """`{row id: ruling}` read off a `kind` verdict part's row lines (an
    amendment's MEANING/CLARITY, a first approval's APPROVE/RETURN); a row
    ruled both ways reads the kind's fail-toward ruling; `{}` for a kind with
    no row lines.

    Implements: SR-232, LLR-310"""
    tags, wins = ROW_RULINGS.get(kind, ({}, None))
    out = {}
    for line in (text or "").splitlines():
        ruled = _ruled_row(line, tags)
        if ruled and out.get(ruled[1]) != wins:
            out[ruled[1]] = ruled[0]
    return out


def blessed_rows(text):
    """The row ids an amendment verdict part marks `- [MEANING+BLESS]`: the
    MEANING rows whose new text the adjudicator would bless (WI-912, Q2 of
    coordinator-2026-10-14 D-003). An absent mark reads as not blessed, and so
    does a row that is also tagged plain `[MEANING]` or `[CLARITY]`: a row
    ruled two ways fails toward no act.

    Implements: SR-232, LLR-310"""
    tags, _wins = ROW_RULINGS["amendment"]
    blessed, other = set(), set()
    for line in (text or "").splitlines():
        ruled = _ruled_row(line, tags)
        if ruled:
            mark = line.strip().startswith(BLESS_TAG)
            (blessed if mark else other).add(ruled[1])
    return frozenset(blessed - other)


def verdict_rulings(text):
    """`{row id: "MEANING" | "CLARITY"}` read off an amendment verdict's row
    lines; a row ruled both ways reads MEANING, the brief's fail-toward-meaning
    rule.

    Implements: SR-178, LLR-278"""
    return row_rulings(text, "amendment")
