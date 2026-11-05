"""THE HELD STATUS — which status cells a delta moves, and whether the dial
holds them (SR-208, SR-210).

Moved here whole from `acceptance_record.py`, unchanged, so that module stays
under the size ratchet while this judgement grows. It reads the acceptance
record's two-tree spine walk (`_spine_revs`, `_spine_row_sides`), its
approval-act registries, its empty-tree reader and its one `git, or None`
alias; the import runs one way, and nothing in `acceptance_record` imports this
module.

Stdlib only.

Contracts: IF-196 — the interface seam this module declares
(process.md §8; rows of record in docs/requirements/interfaces.toml).

Contract IF-196: the held status, read from a delta. `staged_status_moves(root,
    base, head, paths)` returns every change to a status cell of an off-spine
    registry in `HELD_STATUS_REGISTRIES` between two trees, or between `base`
    and the index when `head` is None - a changed cell, and a row added or
    removed with a status - as `{"registry", "id", "before", "after"}`,
    an absent side reading ""; `head` may be a tree, and `paths` narrows the
    registries to those among them. The needs file is read for its stakeholder
    tier alone (`STATUS_TABLES`). `merge_status_moves(root, parents)` is the
    index's moves against the first of `parents` that differ from EVERY one of
    them - a staged merge result's own - and `pending_status_moves(root)` the
    moves of the commit in progress, merge or not. `committed_status_moves(root,
    rev)` is the same as `staged_status_moves` for one commit against its first
    parent, or the empty tree for a root commit, across the spine registries
    too, the needs tier included, each row once. `held_status_lines(dial,
    moves)` returns one line naming the registry, the row and the rung of every
    move whose rung the dial holds, a registry the rung map does not name read
    as held; `held_status_refusal(dial, moves)` joins them into the refusal,
    or returns None. A delta git cannot read is `[]`; a registry
    side that does not parse is one move naming the registry.
    THE HELD-RUNG RULE. `HELD_TIERS` is every tier of the snapshotted
    registries and `registry_held(dial, registry)` the dial test, an unmapped
    registry held. `held_claims(after, before, held)` returns `{(row id,
    registry, id column): "a" | "b"}` for each approval claim one side makes
    against another, each side `{(registry, id column): (live rows, copy
    rows)}`: (a) a live move into approval, a row born approved included; (b)
    a copy that claims approval and entered, or moved in an approved cell or
    `Status`, or that retired a row it held approved. `held_approval_lines(root,
    bases, head, dial)` returns one line per claim the tree `head` (None: the
    index) makes against EVERY tree of `bases` on a held rung, naming the tree,
    the row, its rung and the dial, except a (b) claim whose live row is
    unchanged, approving on both sides and equal to its copy, ruled CLARITY by
    an accepted amendment verdict in the tree whose binding records the row's
    approved-text digest (IF-287, IF-129); a carrier listed but unreadable or
    unparseable on the head side, a list git cannot produce and a search git
    cannot run are lines naming them, and a base side that fails counts every
    approving row as a claim. `commit_held_approval_lines(root, rev)` is that
    rule for one commit against every parent of its commit object, under the
    dial committed at HEAD: the rider of the merge slot's lane-commit walk.
    `marked_refusal(root, base, head, dial, paths)` is the narrowed marker arm:
    the refusal for a held status move, off-spine or on the need, requirement,
    design and test tiers, or a held copy claim, with no exception, or None.
    `HELD_PATHS` are the carriers the rule reads, live and under the record.
"""

import functools

try:
    import acceptance_record
    import spine_carrier
    from kitlib import authority as _kitauthority
    from kitlib import git as _kitgit
    from kitlib import sitting as _kitsitting
    from kitlib import spine as _kitspine
except ImportError:  # pragma: no cover - in-process fallback
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import acceptance_record
    import spine_carrier
    from kitlib import authority as _kitauthority
    from kitlib import git as _kitgit
    from kitlib import sitting as _kitsitting
    from kitlib import spine as _kitspine

# The kit's one `git, or None` read, as the acceptance record aliases it.
_git = acceptance_record._git


# The approval level names the rungs a human still approves, and the approval
# act (`acceptance_record`) is already refused for the SPINE. The off-spine
# registries carry status cells of their own that no automated path was stopped from changing,
# so a declared hold on their rung was a claim rather than a control. The two
# readers below make it a control: the same two-tree comparison as the spine
# walk, read over the status cell of every row of every off-spine registry, and
# the judgement of the result against a dial. The loop's writers and the
# pre-commit step refuse on it outside a lane (`marked_refusal`, below); the
# history check reports on it (`check_trajectory.loop_held_status_findings`).
#
# THE UNIVERSE IS DECLARED, separately from the rung map, and that separation
# is load-bearing: a registry here that the map does not name is HELD (an
# unmapped status is one nobody has released), which a universe derived FROM
# the map could never express. The frame carries three tiers in one file and
# the assumptions registry two, so the reader walks every table of the file
# rather than one tier by id column. The off-spine registries are TOML only
# (each was converted, or born, under that carrier), and the example `-000`
# rows are never statuses anyone approved.
#
# THE NEEDS FILE IS SHARED: it carries the stakeholder list (off-spine, so
# here) beside the needs (a spine tier, walked by the spine half of
# `committed_status_moves` through `APPROVAL_ACT_CSVS`). `STATUS_TABLES` narrows
# its read to the stakeholder table, so each tier is read by exactly one walk
# and no need is reported twice; both tiers are judged at the needs rung
# (`kitlib.authority.rung_for`).
NEEDS_REGISTRY = "docs/requirements/stakeholder-needs.toml"
HELD_STATUS_REGISTRIES = (
    "docs/requirements/external.toml",
    "docs/requirements/interfaces.toml",
    "docs/requirements/components.toml",
    "docs/requirements/assumptions.toml",
    NEEDS_REGISTRY,
)
STATUS_TABLES = {NEEDS_REGISTRY: (spine_carrier.OFFSPINE_TABLE["STK-ID"],)}


def _status_cells(text, tables=None):
    """`{row id: status}` of a registry text (of its `tables` only, when named),
    the `-000` example rows dropped (never statuses anyone approved), or None
    when it does not parse: `{}` is a registry with no status rows, None one
    that cannot be read, and the two are opposite claims."""
    cells = spine_carrier.status_cells(text, tables)
    if cells is None:
        return None
    return {rid: status for rid, status in cells.items() if not rid.endswith("-000")}


def _status_delta(path, before_text, after_text):
    """The status moves one registry makes between two sides: a changed cell,
    and a row added or removed WITH a status. A side that does not parse is
    ONE move naming the registry, never an empty delta: a delta nobody can read
    is not a delta that moved nothing."""
    tables = STATUS_TABLES.get(path)
    before = {} if before_text is None else _status_cells(before_text, tables)
    after = {} if after_text is None else _status_cells(after_text, tables)
    if before is None or after is None:
        return [{"registry": path, "id": "(unparseable)", "before": "", "after": ""}]
    return [
        {
            "registry": path,
            "id": rid,
            "before": before.get(rid, ""),
            "after": after.get(rid, ""),
        }
        for rid in sorted(set(before) | set(after))
        if before.get(rid) != after.get(rid)
    ]


def _offspine_status_moves(root, base, head, watched):
    """Every status move in `watched` between the two sides `_spine_revs` names
    (`head=None` is the index)."""
    revs = acceptance_record._spine_revs(root, base, head, touches=watched)
    if revs is None:
        return []
    changed, old, new = revs
    moves = []
    for path in watched:
        if path in changed:
            moves += _status_delta(
                path, _git(root, ["show", old + path]), _git(root, ["show", new + path])
            )
    return moves


def staged_status_moves(root, base="HEAD", head=None, paths=None):
    """Every change to a status cell of an off-spine registry between two trees,
    or between `base` and the index when `head` is None — rows added or removed
    with a status included, as `{"registry", "id", "before", "after"}` (an
    absent side is ""). `head` may be a commit or a TREE: a plumbing writer asks
    about the tree it is about to commit, before any commit names it. `paths`,
    when given, narrows the registries to those among them (a path-scoped
    commit takes nothing else). `[]` when git cannot answer.

    Implements: SR-208, LLR-246
    """
    watched = list(HELD_STATUS_REGISTRIES)
    if paths is not None:
        named = {str(p).replace("\\", "/").strip() for p in paths}
        watched = [p for p in watched if p in named]
    return _offspine_status_moves(root, base, head, watched) if watched else []


def merge_status_moves(root, parents):
    """The status moves a STAGED MERGE RESULT makes of its own: each move of the
    index against the first of `parents` whose new value also differs from
    every other parent's. A status the merged side already carried was judged
    in the commit that made it and arrives with it; a value NEITHER side
    carried - a conflict resolution, a hand edit mid-merge - was written by
    this commit, and is judged here. `[]` when git cannot answer.

    Implements: SR-208, LLR-246
    """
    own = None
    for parent in parents:
        moves = staged_status_moves(root, parent)
        keys = {(m["registry"], m["id"]) for m in moves}
        own = (
            moves
            if own is None
            else [m for m in own if (m["registry"], m["id"]) in keys]
        )
    return own or []


def pending_status_moves(root):
    """The status moves the commit being made in `root` makes of its OWN: the
    index against HEAD, or, while a merge is in progress, `merge_status_moves`
    against HEAD and MERGE_HEAD. Read through git alone. An octopus merge's
    further heads are not read, so a status only they carried reads as the
    merge's own: the held direction.

    Implements: SR-208, LLR-246
    """
    merging = _git(root, ["rev-parse", "-q", "--verify", "MERGE_HEAD"])
    if merging and merging.strip():
        return merge_status_moves(root, ["HEAD", merging.strip()])
    return staged_status_moves(root)


def held_status_lines(dial, moves):
    """One line per move whose registry's rung `dial` holds for a human, naming
    the registry, the row, the move and the rung — THE judgement both the
    refusal below and the history check read, so the two cannot disagree about
    which move is held.

    A registry the rung map does not name is HELD whatever the dial says:
    nobody has ruled which rung governs it, and the only safe answer to that is
    the human's (the `agent_common.human_approves` fail-safe, applied to a
    delta instead of an intent)."""
    lines = []
    for move in moves:
        rung = _kitauthority.rung_for(move["registry"])
        if rung is None or _kitauthority.holds_under(dial, rung):
            lines.append(
                "{} {} {} -> {} (rung {})".format(
                    spine_carrier.stem(move["registry"]).rsplit("/", 1)[-1],
                    move["id"],
                    move["before"] or "(absent)",
                    move["after"] or "(removed)",
                    rung or "unmapped, so held",
                )
            )
    return lines


def held_status_refusal(dial, moves):
    """The refusal naming every move `held_status_lines` holds, or None.

    Implements: SR-208, LLR-246
    """
    held = held_status_lines(dial, moves)
    if not held:
        return None
    return (
        "the loop may not change a status the approval level holds for a human "
        "(human_approval_through = {}): {} - a held status moves only in a "
        "person's own reviewed commit".format(dial, "; ".join(held))
    )


def committed_status_moves(root, rev):
    """Every status move `rev` made against its FIRST parent — or against the
    empty tree when it has none — across the spine registries and the off-spine
    ones, in `staged_status_moves`' shape. A merge commit's first-parent delta
    is the merged work's, which is why the history check skips merges and
    visits the merged commits instead.

    Implements: SR-210, LLR-249
    """
    parent = _git(root, ["rev-parse", "--verify", "--quiet", rev + "^1"])
    base = (
        parent.strip()
        if parent and parent.strip()
        else acceptance_record._empty_tree(root)
    )
    if base is None:
        return []
    moves = _offspine_status_moves(root, base, rev, list(HELD_STATUS_REGISTRIES))
    return moves + _spine_status_moves(
        root, base, rev, acceptance_record.APPROVAL_ACT_CSVS
    )


# --- THE HELD-RUNG RULE: what lands from a lane is judged by state -------------
# A held-rung spine row's approval lands from a lane only as a CLARITY
# re-attestation bound to the text its verdict judged. Every lane commit is
# judged against each of its parents by the merge slot's lane-commit walk
# (`commit_held_approval_lines`, a rider of `text_then_act.LANE_COMMIT_RIDERS`),
# whoever built the lane; the pre-commit `held-status` step judges a squash
# landing by its lane commits, and a commit made under the loop marker outside
# a claimed lane by `marked_refusal`. An unmarked plain trunk commit is not
# judged: the ruled residual, left to review.
#
# THE HELD SET is every tier of the snapshotted registries, declared here and
# pinned equal to `baseline_snapshot.SNAPSHOT_TIERS` by the tests, beside the
# off-spine universe above. A registry the rung map does not name is held.
#
# A CLAIM is read off two trees (`held_claims`): the row's live `Status` moved
# into approval, a row born approved included (a), or its approval-record copy
# claims approval and entered the copy, or moved in an approved cell or in
# `Status`, or the copy retired a row it held approved (b). A claim counts only
# when it is one against EVERY parent, so a refresh merge bringing in trunk's
# own approvals claims nothing. A Drafted sibling a whole-registry copy carries,
# a demotion, a move below approval, a traced-only copy move, a released rung
# and an example row are not claims.
#
# THE ONE EXCEPTION is a (b) claim whose live row is unchanged and approving on
# both sides and equal to its copy at the commit, ruled CLARITY by an accepted
# amendment verdict committed in the commit's tree whose binding records the
# row's approved-text digest, equal to the row's at the commit. A missing
# exception refuses the row; it never stops the walk.
HELD_TIERS = (
    ("docs/requirements/system-requirements.toml", "SR-ID"),
    ("docs/requirements/low-level-requirements.toml", "LLR-ID"),
    ("docs/test/test-cases.toml", "TC-ID"),
    ("docs/requirements/interfaces.toml", "IF-ID"),
    ("docs/requirements/components.toml", "CMP-ID"),
    ("docs/requirements/external.toml", "EXT-ID"),
    ("docs/requirements/external.toml", "B-ID"),
    ("docs/requirements/external.toml", "REL-ID"),
    ("docs/requirements/assumptions.toml", "DA-ID"),
    ("docs/requirements/assumptions.toml", "SUR-ID"),
    ("docs/requirements/stakeholder-needs.toml", "SN-ID"),
    ("docs/requirements/stakeholder-needs.toml", "STK-ID"),
)
_RECORD = acceptance_record.SNAPSHOT_DIR + "/"
# Every carrier the rule reads: each held tier's live carriers and their copies
# under the approval record. A squash is admitted only when the index holds
# these byte-equal to the squashed tip's.
HELD_PATHS = tuple(
    dict.fromkeys(
        under + cand
        for rel, col in HELD_TIERS
        for cand in acceptance_record._tier_carriers(rel, col)
        for under in ("", _RECORD)
    )
)
# Where a binding beside an accepted verdict is looked for.
_REVIEWS = "docs/reviews"
# The spine tiers whose status moves the narrowed marker arm reads beside the
# off-spine walk: the need, requirement, design and test tiers.
MARKED_SPINE = acceptance_record.PARENT_FIRST_CSVS
HELD_REMEDY = (
    "a held-rung row's approval lands from a lane only as a CLARITY "
    "re-attestation whose accepted verdict binds the row's approved text; "
    "leave the approval to the owner, or re-sit the row and take the act "
    "from that verdict"
)


def registry_held(dial, registry):
    """Does `dial` hold the rung `registry`'s status cells are approved into?
    A registry the rung map does not name is held whatever the dial says.

    Implements: SR-208, LLR-246
    """
    rung = _kitauthority.rung_for(registry)
    return rung is None or _kitauthority.holds_under(dial, rung)


def _approves(row):
    return row is not None and _kitspine.claims_approval(row)


def _copy_claim(registry, id_col, rid, copy_after, copy_before):
    """Is row `rid`'s copy movement a (b) claim: the copy claims approval and
    the row entered it, or moved in an approved cell or in `Status`; or the
    copy held it approved and holds it no more."""
    now, was = copy_after.get(rid), copy_before.get(rid)
    if now is None:
        return _approves(was)
    if not _approves(now):
        return False
    if was is None or (now.get("Status") or "") != (was.get("Status") or ""):
        return True
    cells = acceptance_record.split_changed_cells(registry, id_col, was, now)
    return bool(cells["approved"])


def held_claims(after, before, held):
    """`{(row id, registry, id column): "a" | "b"}`: every approval claim one
    side `after` makes against one side `before`, on a registry `held(registry)`
    holds. Each side maps `(registry, id column)` to `(live rows, copy rows)`.
    (a) is a live move into approval, a row born approved included; (b) a copy
    movement `_copy_claim` reads as one. Example `-000` rows are skipped.

    Implements: SR-208, LLR-246
    """
    out = {}
    for key in set(after) | set(before):
        registry, id_col = key
        if not held(registry):
            continue
        live_a, copy_a = after.get(key, ({}, {}))
        live_b, copy_b = before.get(key, ({}, {}))
        for rid in set(live_a) | set(copy_a) | set(copy_b):
            if str(rid).endswith("-000"):
                continue
            if _approves(live_a.get(rid)) and not _approves(live_b.get(rid)):
                out[(rid, registry, id_col)] = "a"
            elif _copy_claim(registry, id_col, rid, copy_a, copy_b):
                out[(rid, registry, id_col)] = "b"
    return out


def _side(root, prefix):
    """`({(registry, id column): (live rows, copy rows)}, failures)` of every
    held tier in the tree `prefix`, each read from the first carrier the tree
    lists (an absent one is no rows); one `"<path> cannot be read"` or
    `"<path> does not parse"` failure per carrier that fails."""
    side, failures = {}, []
    for rel, col in HELD_TIERS:
        pair = []
        for under in ("", _RECORD):
            rows = {}
            reads = acceptance_record._tier_reads(root, prefix, rel, col, under)
            for path, found, failure in reads:
                if failure:
                    failures.append("{} {}".format(path, failure))
                rows = found or {}
                break
            pair.append(rows)
        side[(rel, col)] = tuple(pair)
    return side, failures


def _bound_clarity(root, rev, rid, digest):
    """True when an accepted amendment verdict committed in the tree `rev`
    (None: the index) rules row `rid` CLARITY and its binding records `digest`
    for it; False when none does; None when git cannot search the tree. The
    candidates are the bindings under `docs/reviews/` that name the row."""
    found = _kitgit.grep_files(root, rev, rid + "=", _REVIEWS)
    if found is None:
        return None
    for path in found:
        if not path.endswith(_kitsitting.REQUESTED_SUFFIX):
            continue
        verdict = path[: -len(_kitsitting.REQUESTED_SUFFIX)]
        part = (_kitsitting.accepted_at(root, rev, verdict) or {}).get("amendment")
        if not part or part[3].get(rid) != "CLARITY":
            continue
        identities, _why = _kitsitting.accepted_identities(root, rev, verdict)
        if identities and identities.get(rid) == digest:
            return True
    return False


def _excepted(root, head, key, after, befores):
    """`(True, None)` when the (b) claim `key` is a CLARITY re-attestation
    bound to the row's text at `head`; `(False, None)` when it is not; and
    `(False, line)` when git cannot search for its verdict."""
    rid, registry, id_col = key
    live, copy = after[(registry, id_col)]
    row = live.get(rid)
    if not _approves(row) or copy.get(rid) != row:
        return False, None
    for before in befores:
        was = before.get((registry, id_col), ({}, {}))[0].get(rid)
        if not _approves(was) or (was.get("Status") or "") != row.get("Status"):
            return False, None
    digest = acceptance_record.approved_text_digest(registry, id_col, row)
    bound = _bound_clarity(root, head, rid, digest)
    if bound is None:
        return False, "git cannot search {} for the verdict binding {}".format(
            _REVIEWS, rid
        )
    return bound, None


def _touched(root, bases, head):
    """`(touched, line)`: whether the tree `head` (None: the index) changes a
    held carrier against any of `bases`, or a line when git cannot list it."""
    side = [head] if head else ["--cached"]
    touched = False
    for base in bases:
        args = ["diff", "--name-only", "--no-renames", base, *side, "--"]
        names = _kitgit.git_paths(root, args + list(HELD_PATHS))
        if names is None:
            return False, "git cannot list what it changes against {}".format(base[:10])
        touched = touched or bool(names)
    return touched, None


def _claims_against(root, bases, head, dial):
    """`(claims, after, befores, lines)`: the held claims the tree `head`
    (None: the index) makes against EVERY base, its own side, each base's
    side, and the refusal lines for a list git cannot produce or a carrier of
    the head side that cannot be read or does not parse. A base side that
    fails reads as no rows, so every approval-claiming row of the head side
    counts as a claim."""
    touched, line = _touched(root, bases, head)
    if line or not touched:
        return {}, {}, [], [line] if line else []
    after, failures = _side(root, ":" if head is None else head + ":")
    if failures:
        return (
            {},
            after,
            [],
            [f + ", so its held approval claims are unknown" for f in failures],
        )
    claims, befores = _every_base(root, bases, after, dial)
    return claims, after, befores, []


def _every_base(root, bases, after, dial):
    """`(claims, befores)`: the held claims the side `after` makes against
    every base, kept only when made against each, and each base's side; a
    base side that fails reads as no rows."""
    held = functools.partial(registry_held, dial)
    claims, befores = None, []
    for base in bases:
        before, failed = _side(root, base + ":")
        before = {} if failed else before
        befores.append(before)
        found = held_claims(after, before, held)
        claims = (
            found if claims is None else {k: v for k, v in claims.items() if k in found}
        )
    return claims or {}, befores


def _claim_line(key, kind, dial):
    rid, registry, _id_col = key
    rung = _kitauthority.rung_for(registry) or "unmapped, so held"
    what = (
        "its Status moved into approval"
        if kind == "a"
        else "its approval record copy moved"
    )
    return "{} {} claims approval on a held rung ({}; human_approval_through = {}): {}".format(
        spine_carrier.stem(registry).rsplit("/", 1)[-1], rid, rung, dial, what
    )


def held_approval_lines(root, bases, head, dial):
    """THE LANE RULE over one tree: the refusal lines for every held approval
    claim the tree `head` (None: the index) makes against every tree of
    `bases`, judged under `dial`, each naming the tree, the row, its rung and
    the dial and carrying `HELD_REMEDY`, a (b) claim the one exception admits
    excepted; or one line per carrier that cannot be read or does not parse,
    naming it. `[]` when the tree touches no held carrier.

    Implements: SR-208, LLR-246
    """
    tree = "the index" if head is None else "commit " + head[:10]
    claims, after, befores, lines = _claims_against(root, bases, head, dial)
    for key, kind in sorted(claims.items()):
        excepted, line = (False, None)
        if kind == "b":
            excepted, line = _excepted(root, head, key, after, befores)
        if not excepted:
            lines.append(
                line or "{} - {}".format(_claim_line(key, kind, dial), HELD_REMEDY)
            )
    return ["{}: {}".format(tree, line) for line in lines]


def commit_held_approval_lines(root, rev):
    """The lane rule for one lane commit, the rider the merge slot's
    lane-commit walk runs: `held_approval_lines` against every parent of its
    commit object (`acceptance_record._commit_parents`, so an unreadable
    parent is a line), under the dial committed at HEAD, which is trunk at
    the slot and at a squash landing. A root commit is not judged.

    Implements: SR-208, LLR-246
    """
    parents, unread = acceptance_record._commit_parents(
        root, rev, "it makes a held approval claim"
    )
    if unread or not parents:
        return unread
    return held_approval_lines(root, parents, rev, _kitauthority.dial_at(root, "HEAD"))


def _spine_status_moves(root, base, head, registries):
    """Every `Status` move of the spine rows in `registries` between `base`
    and `head` (None: the index), in `staged_status_moves`' shape: the one
    spine status walk the history check and the marker arm share.

    Implements: SR-208, SR-210, LLR-246, LLR-249
    """
    moves = []
    for registry, _id_col, before, after, _csv in acceptance_record._spine_row_sides(
        root, base, head, registries
    ):
        for rid in sorted(set(before) | set(after)):
            was = ((before.get(rid) or {}).get("Status") or "").strip()
            now = ((after.get(rid) or {}).get("Status") or "").strip()
            if was != now:
                moves.append(
                    {"registry": registry, "id": rid, "before": was, "after": now}
                )
    return moves


def _named(paths):
    return None if paths is None else {str(p).replace("\\", "/").strip() for p in paths}


def _own_moves(root, bases, head, paths):
    """The status moves `head` makes against every base, off-spine and on the
    marker arm's spine tiers, narrowed to `paths` when given: each move of the
    first base whose row also moved against every other base."""
    named, own = _named(paths), None
    for base in bases:
        moves = staged_status_moves(root, base, head, paths)
        spine = _spine_status_moves(root, base, head, MARKED_SPINE)
        moves += [m for m in spine if named is None or m["registry"] in named]
        keys = {(m["registry"], m["id"]) for m in moves}
        own = (
            moves
            if own is None
            else [m for m in own if (m["registry"], m["id"]) in keys]
        )
    return own or []


def _commit_bases(root, base, head):
    """The trees the commit being judged is compared with: `base`, and, for
    the index against HEAD while a merge is in progress, MERGE_HEAD too."""
    if head is not None or base != "HEAD":
        return [base]
    merging = (_git(root, ["rev-parse", "-q", "--verify", "MERGE_HEAD"]) or "").strip()
    return ["HEAD"] + ([merging] if merging else [])


def marked_refusal(root, base, head, dial, paths=None):
    """THE NARROWED MARKER ARM: the refusal for a commit made under the loop
    marker outside a claimed lane (the caller tests both) that moves a held
    status or makes a held approval claim, or None. The tree `head` (None: the
    index, judged against HEAD and MERGE_HEAD during a merge) is judged
    against `base` under `dial`: every status move of the off-spine registries
    and of the need, requirement, design and test tiers whose rung the dial
    holds (`held_status_lines`), and every held copy claim (b) of
    `held_claims`, with no exception; a live move into approval is already a
    status move. `paths` narrows both to the registries a path-scoped commit
    takes.

    Implements: SR-208, LLR-246
    """
    bases = _commit_bases(root, base, head)
    lines = held_status_lines(dial, _own_moves(root, bases, head, paths))
    claims, _after, _befores, failures = _claims_against(root, bases, head, dial)
    named = _named(paths)
    for key, kind in sorted(claims.items()):
        carriers = acceptance_record._tier_carriers(key[1], key[2])
        if kind == "b" and (
            named is None or any(c in named or _RECORD + c in named for c in carriers)
        ):
            lines.append(_claim_line(key, kind, dial))
    lines += failures
    if not lines:
        return None
    return (
        "the loop may not change a status or claim an approval the approval "
        "level holds for a human (human_approval_through = {}): {} - a held "
        "status moves only in a person's own reviewed commit, and a held "
        "approval lands from a lane only as a CLARITY re-attestation bound to "
        "its judged text".format(dial, "; ".join(lines))
    )
