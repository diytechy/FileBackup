"""The best-effort-off-git subprocess pattern — one home for "git, or None".

Most of the kit's git reads are ENRICHMENT, not gating: a commit clock behind a
staleness warn, a short SHA in a stamp, the branch behind a status line. Every
one of them must degrade to "I don't know" rather than crash, because the kit
has to run in three environments where git legitimately answers nothing — no
git binary on PATH, a directory that is not a repository (a tarball adopter,
a scaffold before its first `git init`), and a shallow or detached checkout
where the rev exists but the history does not.

`git_out` is that degrade, stated once. It was copied into `check.py`,
`trace.py` and `trunk_step.py`, each carrying a docstring that pointed at the
others as the pattern's home — three homes and no owner, which is the shape D-8
(`OI-16`) retired. A FOURTH copy survived that pass and is folded in here at
WI-521 slice 1: `check_trajectory._git`, which was the same body plus an
optional `stdin`. The `stdin` argument is the whole reason it was missed — it
looked like a different function — so it is a parameter here rather than a
private variant, and both readers of it (`check_trajectory`, `acceptance_record`)
now alias this one home the way `check.py` already did.

WHAT THIS MODULE DELIBERATELY DOES NOT DO: it never decides what an absent
answer MEANS. `None` is "git had nothing to say"; whether that is benign (skip
the enrichment) or fatal (a gate that requires history) is the caller's
fail-direction to declare, and folding that choice in here would hide it.

TWO READS FOR A TWO-TREE RULE (WI-818). A commit-time rule comparing a commit
with its parent needs two answers `git_out` cannot give losslessly: the paths a
listing prints, which a plain listing quotes and escapes under `core.quotePath`
and `git_out`'s replacing decoder turns into other paths (`git_paths` reads
them NUL-delimited as bytes, decoded without loss), and a blob read that tells
a path the tree does not list from one it lists but cannot read (`git_show`,
raising `UnreadableBlob` for the second, and for a path that is not UTF-8,
which it cannot hand back to git). Neither decides what that MEANS: the ruling
sync and the overrule sync in `acceptance_record` refuse an unreadable blob.

ONE CLAIMED-BRANCH READER. `claimed_work_branch` answers whether the checkout
is a claimed lane. It moved here from `check.py` so every caller that must
tell a lane from the trunk shares one reader; as with `git_out`, None is
"no claim found", and each caller declares what that means for it. Beside
it, `claimed_specs` reads WHICH work items a claim folder holds at a
tree-ish, over the one claimed-spec filename grammar (`SPEC_NAME`), so a
route that keys on a lane's claim at a revision (the hand squash's landing
check, the reserve verb's claim check) never parses the folder itself.

A TREE WRITTEN OUT AS FILES, for the landing's live-id sweep, which reads
files rather than blobs: `write_blobs` writes each blob byte for byte by
object id, so no attribute (`export-ignore`, `export-subst`, a filter or an
eol rule) can drop or rewrite a file, and the sweep judges the committed
registries. Unlike `git_out` it raises (`ArchiveError`): a sweep of a
half-written tree would answer for a tree that does not exist, so the caller
names the failure in its own terms.

THE LANE-COMMIT WALK. Every per-commit rule (text then act, the adoption
record, the plan gate, the held-status step and the merge slot) shares one
traversal, held here below them all: `staged_heads`, the HEAD / MERGE_HEAD read
of the commit being made; `lane_commit_walk`, each listed commit, oldest first,
asked of each rider in turn; and `squash_lines`, a staged squash's HEAD..tip
step. The rules keep what differs: each lists its own range where its order or
ancestry policy differs, keeps its own refusal text, remedy and squash policy,
and registers its rider where it is read (`text_then_act.LANE_COMMIT_RIDERS`).
As with `git_out`, the owner never decides what an unlistable range means:
`squash_lines` hands back the caller's own lines for it, or None.
"""

import re
import subprocess
from pathlib import Path

__all__ = [
    "ACTIVE_DIR",
    "ArchiveError",
    "SPEC_NAME",
    "UnreadableBlob",
    "claimed_specs",
    "claimed_work_branch",
    "git_bytes",
    "git_out",
    "git_paths",
    "git_show",
    "grep_files",
    "lane_commit_walk",
    "lanes_containing",
    "squash_commits",
    "squash_lines",
    "staged_heads",
    "write_blobs",
]


def _git_stdout(root, args, **kwargs):
    """Run one read-only git command and preserve its requested stdout type."""
    try:
        proc = subprocess.run(
            ["git", "-C", str(root), *args], capture_output=True, **kwargs
        )
    except (OSError, ValueError):
        return None
    return proc.stdout if proc.returncode == 0 else None


def git_out(root, args, stdin=None):
    """stdout of `git -C <root> <args>`, or None on ANY failure.

    None covers all of: no git binary (`OSError`), a bad argument vector
    (`ValueError`), not a repository, an unknown rev or path, and any non-zero
    exit. Decoded as UTF-8 with `errors="replace"`, so a commit message or path
    in another encoding degrades to replacement characters instead of raising
    inside a check that only wanted a SHA.

    `stdin` feeds a BATCH command — `cat-file --batch-check` is the live caller
    — which is how a scan asks about many blobs in ONE subprocess instead of two
    per file. It matters where the scan rides an always-on floor rather than a
    gate. `None` (the default) passes nothing, which is byte-for-byte the
    no-input behaviour every other caller already had.

    Not a security boundary and not a general git wrapper: `args` is passed as
    a list to a non-shell `subprocess.run`, so nothing here interpolates into a
    shell, but a caller passing attacker-controlled `args` owns that choice.

    Contract:
      Inputs:  root: path-like repo root; args: sequence of git arguments;
               stdin: str | None — batch input, or nothing
      Outputs: str | None — stdout on success; None on any failure
    """
    return _git_stdout(
        root,
        args,
        text=True,
        encoding="utf-8",
        errors="replace",
        input=stdin,
    )


def git_bytes(root, args, stdin=None):
    """Raw stdout of `git -C <root> <args>`, or None on ANY failure.

    This is the binary counterpart to `git_out` for Git protocols whose bytes
    carry identity rather than display text. Callers parse their ASCII framing
    before deciding whether any field may be decoded. `stdin` (bytes) is fed
    untranslated, so an object written from it (`hash-object --stdin`,
    `mktree`) holds exactly those bytes on every platform, where text-mode
    input would turn each newline into the platform's line ending.
    """
    return _git_stdout(root, args, input=stdin)


def git_paths(root, args):
    """The paths a path-listing git subcommand (`args[0]`: `diff`, `ls-files`,
    `ls-tree`) prints, read LOSSLESSLY: `-z` makes the listing NUL-delimited
    and unquoted, where a plain listing under `core.quotePath` (git's default)
    quotes and escapes any path with a non-ASCII byte, which then matches no
    prefix and names no blob; and the bytes are decoded as UTF-8 with
    `surrogateescape`, so a byte that is not UTF-8 is kept as a lone surrogate
    (`path.encode("utf-8", "surrogateescape")` is git's exact path), never
    replaced by U+FFFD, which would name another path. None when git cannot
    answer. The ruling sync and the overrule sync read every path list
    through it.

    Implements: SR-225, LLR-303
    """
    out = git_bytes(root, [args[0], "-z"] + list(args[1:]))
    if out is None:
        return None
    return [path for path in out.decode("utf-8", "surrogateescape").split("\0") if path]


class UnreadableBlob(Exception):
    """A path its tree lists whose blob git cannot read (a partial clone
    offline, a damaged object store), or whose name is not UTF-8 and so cannot
    be handed back to git as an argument on every platform. The ruling sync
    refuses it by name: a failed read is never an absent file (A1)."""


def _shown(path):
    """`path` printable on any UTF-8 stream: a byte that is not UTF-8 (a lone
    surrogate from `git_paths`) shown as `\\xNN`.

    Implements: SR-225, LLR-303
    """
    return path.encode("utf-8", "surrogateescape").decode("utf-8", "backslashreplace")


def grep_files(root, rev, needle, path):
    """The paths under `path` in the tree `rev` (None: the index) whose text
    holds the fixed string `needle`, read NUL-delimited like `git_paths`; []
    when none does, and None when git cannot answer. `git grep` exits 1 for
    "no match" and higher for a failure, so the two are told apart here: a
    search that could not run is never read as "nothing found".

    Implements: SR-208, LLR-246
    """
    args = ["grep", "-l", "-z", "-F", "-e", needle]
    args += ["--cached"] if rev is None else [rev]
    try:
        proc = subprocess.run(
            ["git", "-C", str(root), *args, "--", path], capture_output=True
        )
    except (OSError, ValueError):
        return None
    if proc.returncode == 1 and not proc.stdout and not proc.stderr.strip():
        return []
    if proc.returncode != 0:
        return None
    prefix = "" if rev is None else rev + ":"
    found = proc.stdout.decode("utf-8", "surrogateescape").split("\0")
    return [p[len(prefix) :] if p.startswith(prefix) else p for p in found if p]


def git_show(root, prefix, path):
    """The text of `prefix + path` (`prefix` a `git show` prefix: `"<rev>:"` or
    `":"` for the index), None when the tree does not list the path; raises
    `UnreadableBlob` when it lists the path but its blob cannot be read, and
    for a path that is not UTF-8 before asking git at all: such a path cannot
    be passed back to git losslessly (a Windows command line re-encodes it to
    another path), so its answer could only be a wrong "absent".

    Implements: SR-148, SR-225, LLR-303
    """
    if _shown(path) != path:
        raise UnreadableBlob(_shown(path) + " (a path that is not UTF-8)")
    text = git_out(root, ["show", prefix + path])
    if text is not None:
        return text
    if prefix == ":":
        listed = git_out(root, ["ls-files", "--", path])
    else:
        listed = git_out(root, ["ls-tree", "--name-only", prefix[:-1], "--", path])
    if listed is None or listed.strip():
        raise UnreadableBlob(prefix + path)
    return None


_HEX = frozenset("0123456789abcdef")


def squash_commits(root):
    """The commits a `git merge --squash` in progress folds in, newest first,
    read off git's own `SQUASH_MSG` (each `commit <full id>` header line); []
    when no squash is in progress or the file cannot be read. One reader for
    every pre-commit step that judges a squash landing by the commits it
    carries (text then act, the adoption record, the held-status step, the
    plan gate): the two-tree rules read no file.

    Implements: SR-140, LLR-302
    """
    rel = (git_out(root, ["rev-parse", "--git-path", "SQUASH_MSG"]) or "").strip()
    path = Path(root) / rel
    try:
        text = path.read_text(encoding="utf-8") if rel and path.is_file() else ""
    except (OSError, UnicodeDecodeError):
        return []
    return [
        ln[7:]
        for ln in text.splitlines()
        if ln.startswith("commit ") and len(ln) >= 47 and set(ln[7:]) <= _HEX
    ]


def staged_heads(root):
    """`(head, merging)` of the commit being made: HEAD's id, `""` before the
    first commit, and MERGE_HEAD's id, `""` when no merge is in progress. Every
    per-commit hook step reads the two here; what an empty HEAD means (nothing
    is judged) is each step's own.

    Implements: SR-148, SR-140, SR-154, SR-208, LLR-302, LLR-345, LLR-337, LLR-246
    """
    head, merging = (
        (git_out(root, ["rev-parse", "--verify", "--quiet", name]) or "").strip()
        for name in ("HEAD", "MERGE_HEAD")
    )
    return head, merging


def lane_commit_walk(root, commits, riders):
    """The ONE lane-commit walk: `(rev, lines)` for each commit of `commits`
    (listed by the caller, oldest first) that a rider in `riders` reports lines
    for, each rider (`rule(root, rev) -> lines`) asked of each commit in turn.
    Lazy, so a caller that stops at the first report judges no commit after it.

    Implements: SR-148, SR-140, SR-154, LLR-298, LLR-302, LLR-345, LLR-337
    """
    return (
        (rev, lines)
        for rev in commits
        for rule in riders
        for lines in (rule(root, rev),)
        if lines
    )


def squash_lines(root, head, tip, riders, unlisted):
    """A staged squash's HEAD..tip step: None when `tip` does not contain
    `head` (the lane was not rebased onto trunk); `unlisted`, the caller's own
    lines or None, when git cannot list `head..tip`; else every line `riders`
    report for those commits, oldest first, through `lane_commit_walk`. Which
    staged paths admit a squash, and what None means, are the caller's.

    Implements: SR-148, SR-140, SR-208, LLR-302, LLR-345, LLR-246
    """
    if git_out(root, ["merge-base", "--is-ancestor", head, tip]) != "":
        return None
    commits = git_out(root, ["rev-list", "--reverse", head + ".." + tip])
    if commits is None:
        return unlisted
    walk = lane_commit_walk(root, commits.split(), riders)
    return [line for _rev, lines in walk for line in lines]


def claimed_work_branch(root, notice=None):
    """The checkout's branch name IF it is a CLAIMED work branch, else None.

    A claimed branch's work-item specs live in `docs/work/active/<branch>/`,
    moved there by the serial trunk commit that cut the branch, so the branch
    itself carries the evidence: in its working tree, or, once the close moves
    the specs to their terminal directory, in its own history. Off git, on a
    detached HEAD, with an implausible branch name, or with neither a matching
    `active/` directory nor a claim in history, the answer is None; what None
    MEANS (the strict bar, a judged commit) is each caller's to declare.

    `notice`, when given, is called with an implausible branch name before the
    reader answers None for it, so a caller can say out loud that something fed
    it a fake ref; the reader itself prints nothing.

    Implements: SR-006, SR-170, LLR-141
    """
    branch = (git_out(root, ["symbolic-ref", "--short", "HEAD"]) or "").strip()
    if not branch:
        return None  # no git, not a repo, or a detached HEAD
    # A branch name is used here as a relative PATH. git's own ref rules already
    # forbid `..` and `\`, but the answer decides whether a gate runs, so it
    # refuses rather than trusts.
    if ".." in branch or "\\" in branch or branch.startswith("/"):
        if notice is not None:
            notice(branch)
        return None
    active = Path(root) / "docs" / "work" / "active"
    spec_dir = active / branch
    try:
        # Belt-and-braces containment: whatever the name, the claim directory
        # must sit UNDER docs/work/active/ for this to be a claimed branch.
        spec_dir.resolve().relative_to(active.resolve())
    except (OSError, ValueError):
        return None
    if spec_dir.is_dir():
        return branch
    # The working tree alone cannot answer this: the close MOVES the claim out
    # of active/, so from the close commit on the tree holds no claim. History
    # outlives the move: the commit that cut the branch added the directory, and
    # that add stays reachable. One path-limited git call, stopped at the first
    # hit. FAIL-DIRECTION: no git, a failing git or an empty answer all read as
    # unclaimed, because a false positive would relax the trunk's own bar.
    # Residual (review-confirmed breadth): ANY branch whose name ever appeared
    # under docs/work/active/ in reachable history reads as claimed forever (a
    # retired WI branch re-cut, or a throwaway reusing its name); bounding the
    # walk would need a configured trunk name this rule deliberately has not.
    # Cost note: on the trunk the pathspec never matches, so the -1 walk pays
    # full history, measured ~0.05 ms/commit (61 ms at 1.2k commits); a caller
    # that asks often memoizes the answer.
    log = git_out(
        root, ["log", "-1", "--format=%H", "--", "docs/work/active/" + branch]
    )
    return branch if (log or "").strip() else None


# The claim folders: a claim moves a queued spec to `ACTIVE_DIR/<lane>/`.
ACTIVE_DIR = "docs/work/active"
# A claimed spec's filename, `WI-<n>-<slug>.md`, the only shape `claim`
# writes; group 1 is the work-item id. Strict on purpose: the `.md` suffix
# and a slug are required, so a handback patch or hand-made residue in a
# claim folder names no work item.
SPEC_NAME = re.compile(r"^(WI-\d+)-.+\.md$")


def claimed_specs(root, rev, lane=None):
    """`[(lane, WI id, filename)]`, sorted, of the claimed specs the tree-ish
    `rev` holds directly in a claim folder `ACTIVE_DIR/<lane>/` (every lane's,
    or only `lane`'s), each filename read by `SPEC_NAME`; None when git cannot
    list `rev`. The listing is lossless (`git_paths`). What an absent or an
    unlistable claim MEANS is each caller's to declare.

    Implements: SR-170, LLR-141
    """
    listed = git_paths(root, ["ls-tree", "-r", "--name-only", rev, "--", ACTIVE_DIR])
    if listed is None:
        return None
    found = []
    for path in listed:
        folder, _sep, name = path.rpartition("/")
        owner = folder[len(ACTIVE_DIR) + 1 :]
        matched = SPEC_NAME.match(name)
        if matched and owner and (lane is None or owner == lane):
            found.append((owner, matched.group(1), name))
    return sorted(found)


class ArchiveError(RuntimeError):
    """git could not write a tree-ish's paths out as files; its `str` names
    the revision and the reason.

    Implements: SR-166, LLR-181
    """


def _listed_blobs(root, rev, paths):
    """`[(object id, path)]` of every blob the tree-ish `rev` holds under
    `paths`, a link or a submodule left out (neither is file content). A path
    `rev` does not hold lists nothing. Raises `ArchiveError` when git cannot
    list the tree.

    Implements: SR-166, LLR-181
    """
    listed = git_bytes(root, ["ls-tree", "-r", "-z", rev, "--", *paths])
    if listed is None:
        raise ArchiveError(
            "git could not list {} at {}".format(", ".join(paths), rev[:10])
        )
    blobs = []
    for entry in filter(None, listed.split(b"\0")):
        meta, _tab, path = entry.partition(b"\t")
        mode, kind, oid = meta.split()
        if kind == b"blob" and mode != b"120000":
            blobs.append((oid, path.decode("utf-8", "surrogateescape")))
    return blobs


def write_blobs(root, rev, paths, dest):
    """Write every file the tree-ish `rev` holds under `paths` to `dest`, each
    at its own relative path and byte for byte as committed: each blob is read
    by object id (`ls-tree`, then one `cat-file --batch`), so no attribute can
    drop or rewrite one. A link or a submodule is not written, and a path
    `rev` does not hold writes nothing. Raises `ArchiveError` when git cannot
    list or read them.

    Implements: SR-166, LLR-181
    """
    blobs = _listed_blobs(root, rev, paths)
    if not blobs:
        return
    out = git_bytes(
        root, ["cat-file", "--batch"], stdin=b"".join(oid + b"\n" for oid, _p in blobs)
    )
    at = 0
    for oid, rel in blobs:
        end = out.find(b"\n", at) if out is not None else -1
        header = out[at:end].split() if end >= 0 else []
        if len(header) != 3 or header[0] != oid or header[1] != b"blob":
            raise ArchiveError("git could not read {} at {}".format(rel, rev[:10]))
        size = int(header[2])
        target = Path(dest) / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(out[end + 1 : end + 1 + size])
        at = end + 2 + size


def lanes_containing(root, tip):
    """The local branches whose history contains `tip` (the lane a squash in
    progress is landing), or None when git cannot list them. A squash's
    pre-commit judgements read the lane's claim through these names.

    Implements: SR-154, LLR-337
    """
    out = git_out(
        root,
        ["for-each-ref", "--format=%(refname:short)", "--contains", tip, "refs/heads/"],
    )
    return None if out is None else out.split()
