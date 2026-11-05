"""THE ACCEPTANCE RECORD — what an amendment IS, and the mirror it is measured
against.

The boundary, in one sentence, because a decomposition that cannot say where its
line is has not drawn one: **everything here compares TWO GIT TREES cell by cell
to answer whether attested text has moved away from the copy recording its
acceptance; everything left in `check_trajectory.py` asks what the registries say
TODAY.** Nothing in this module reads the working tree, and the free-name census
proves it rather than the docstring claiming it — the whole module's only
non-builtin dependencies are `spine_carrier` (which carrier a spine registry
uses) and one `git -C <root> … or None` primitive. The held-status readers,
and the held-rung rule with them, live in `held_status.py` (IF-196), which
imports this module one way.

WHAT IT OWNS. `SR-178` (text that has moved away from its acceptance record is
reported) and `SR-179` (the record can only ever be written by copying live
text), plus the staged `Hat-Refs` arm of the same amendment comparison
(`SR-161`, `LLR-202`), which is that comparison applied to one traced cell:

    the cell split      `SPINE_TRACED_CELLS` / `SPINE_APPROVED_CELLS`,
                        `spine_cell_class`, `traced_cells` — the §A5.1 owner
                        ruling that decides which cells arm a re-attest window
    the comparison      `_spine_rows_at`, `_spine_revs`, `split_changed_cells`,
                        `staged_spine_amendments` — the one basis an amendment
                        is measured by (`LLR-158`)
    the warns           `staged_spine_findings`, `staged_hat_refs_findings`
    the mirror          `_snapshot_survives`, `staged_snapshot_findings`,
                        `_snapshot_write_revs`, `committed_snapshot_findings` —
                        the invariant that the record is only ever written by
                        copy (`LLR-178`), in staged AND committed form

WHY IT IS A MODULE (WI-521, slice 1 — and the argument is not line count). The
requirements say so from a direction the size ratchet cannot see. `WI-508`'s two
blind derivations built a minimal module map from the requirement text alone,
neither able to see this tree, and **both** gave the acceptance record a module
of its own (team A's `A2`, team B's `M06`) while the live layout fused it into
the checker — 8 of `check_trajectory`'s 13 fused obligation pairs run through
`SR-178`/`SR-179`. Mechanically, the reach-through was already visible:
`baseline_snapshot.py` (the writer) and `intake.py` (the mint) each imported a
~5,000-line validator to get at the comparison basis and the mirror guard, which
is the same shape `WI-483` slice 1 cut when a render leaf imported a merge
coordinator for two constants.

WHY THE JUDGE IS STILL NOT THE WRITER. `LLR-178`'s attested rationale places the
mirror invariant away from `baseline_snapshot` because "the writer must not also
be the judge of its own writes". That separation is unchanged and is the reason
this module is NOT folded into `baseline_snapshot.py`: it sits beside the writer,
not inside it, and `check_trajectory.main` remains the aggregation that joins its
findings to the failure set.

NOT `kitlib`, on the hard rule that kept `census.py` and `pending.py` out: every
module of that package must stay import-clean of the rest of `scripts/`
(`tests/test_bootstrap.py::test_bootstrap_imports_only_the_common_package`), and
this one imports the `spine_carrier` sibling by construction — resolving a
registry at a revision means asking which carrier that revision used.

`check_trajectory.py` re-exports every name below under its former spelling, so
no caller moved and its CLI behaviour is byte-identical; the `Implements:` tags
travel with the code they annotate.

Stdlib only.

Contracts: IF-091, IF-129, IF-308 — the interface seams this module declares
(process.md §8; rows of record in docs/requirements/interfaces.toml).

Contract IF-091: the staged spine-amendment set, offered as a call.
    `staged_spine_amendments(root, base, head)` returns one record per
    approved-text spine row amended between the two trees WITHOUT its status
    moving — `{"registry", "id", "approved": {cell: (before, after)},
    "traced": {...}}` — and `AMENDMENT_CSVS` names the registries and id
    columns that walk covers: the requirement, design and test tiers, the need
    tier and the assumption registry's two tiers (OI-100, WI-791). Which two trees is a parameter, so the same call answers
    the index-against-HEAD question and the commit-against-commit one. It
    classifies and stops: which traced cells oblige an act is the caller's
    ruling, not this module's. A new row is not an amendment, a row whose
    status moved is a deliberate call this does not second-guess, and any
    missing git context degrades to `[]` rather than raising.
    THE SAME WALK ANSWERS THE APPROVAL-ACT QUESTIONS (owner ruling 2026-09-01).
    `staged_approval_acts(root, base, head)` returns the rows that CROSSED into
    an approval claim or arrived already making one — precisely the set the
    amendment reader exempts, over the WIDER `APPROVAL_ACT_CSVS` universe that
    adds the SN tier — and `staged_drafted_rows` returns the rows a lane
    added, amended, or moved into `Drafted`. `lane_approval_refusal(root, base, head)`
    words the refusal of a delta writing the approval record with no act a
    verdict could back, or None. It fails CLOSED on an unreadable
    snapshot delta, the opposite pole from its readers' silent degrade, because
    a refusal is where the conservative direction belongs. All four share
    `_spine_row_sides`, so no reader can be the only one that sees a row.
    `merge_approval_refusal(root, base, head, metas, *, trunk)`
    is the merge slot's one call: every lane's acts through
    `backed_act_refusal` - each backed by an accepted verdict over its own rows
    (owner ruling 6, 2026-10-07) - a record written with no act through
    `lane_approval_refusal`, and, when any claimed row in `metas` records a
    scope, the flips through its first-approval scope besides, and its
    re-attestations — read from the act ledger entries the delta added — through
    `reattest_scope_refusal`, which refuses by name every re-attested row
    outside the `Adjudicates` scope of the amendment rows the lane claims. A
    held rung is the lane rule's (`held_status`, IF-196), not this call's.
    `settled_amendments(root, base, head, records, routed_cells)` returns
    `(settled ids, refusal)` for the trunk mint: the records whose row an act
    ledger entry the range added re-attests (IF-220) and whose approved and
    routed traced cells at `head` equal the row's snapshot copy there. A
    ledger or copy the tree lists that cannot be read or does not parse is
    the refusal, naming the carrier and revision; nothing else suppresses.
Contract IF-129: the ONE cell-comparison basis.
    `split_changed_cells(registry_path, id_col, before_row, live_row)` returns
    `{"approved": {cell: (before, after)}, "traced": {cell: (before, after)}}`
    for a single row, excluding the id column (a join key, not content) and
    `Status` (the flip the caller is asking about) structurally, at the callee.
    Every reader of "what changed on this row" joins here, so the staged
    amendment guard and a snapshot comparison cannot disagree about which cells
    are content or which half of the remainder arms an act. The dependency runs
    one way only: nothing in this module imports the readers that call it.
    `approved_text_digest(registry_path, id_col, row)` is the row's
    approved-text identity on the same basis: `sha256:` and 16 lowercase hex
    over the row's nonempty cells `spine_cell_class` classes approved, the id
    column and `Status` excluded, serialized as sorted JSON. So a carrier
    change, an empty cell against an absent one, a status move or a traced
    cell's move leaves it unchanged, and any approved cell's move changes it.
Contract IF-308: the parent-first commit judgement, offered as a call.
    `staged_parent_first_lines(root)` judges the index against HEAD (and
    MERGE_HEAD during a merge) and `commit_parent_first_lines(root, rev)` one
    commit against every parent of its commit object; both return refusal
    lines, `[]` when the tree passes, and both read through
    `parent_first_lines(root, bases, head)`. A line names the tree (`the
    index:` or `commit <sha10>:`) and an approved child (`Approved` or
    `Founded`) left under a declared parent that is not approved, where the
    child's or the parent's status differs from that row's status in some
    parent tree (an absent row counting as a value), with its own remedy
    (`kitlib.spine.parent_first_line`). A tree whose name list touches no
    carrier of the need, requirement, design or test registry is not read
    further. A name list git cannot produce, or a commit-side registry that
    is listed but cannot be read or does not parse, is a refusal line naming
    it, never a skip; a parent-side registry that fails either way counts
    every status as moved; an absent registry is no rows. No HEAD yet, or a
    root commit, is not judged. Reads two trees and writes nothing.

THE RULING SYNC (WI-790; OI-102 Q3) is the third two-tree rule here, and the
one with no dial: a commit that takes an open item out of `pending` must, in
the same diff, update the Done-when of every work item open in its PARENT tree
whose `needs` cites that item, or close or remove that row
(`ruling_sync_lines`). It reads one commit and its parent and nothing further,
so it never skips for missing history; the pre-commit hook asks it of HEAD and
the staged tree (`staged_ruling_sync_lines`), and the merge slot of every lane
commit and its first parent (`commit_ruling_sync_lines`) — one function over
two trees in both places. It decides only that mechanical condition: whether
the change carries the ruling, and whether a row's other fields must move, is
the reviewer's judgement.

The same rule couples the owner's OVERRULE of a delegated decision to work
(WI-818): a commit that sets a decisions-record entry `owner = "overruled"`
must, in the same diff, file or amend a queued or active work item whose spec
cites the entry (`kitlib.decisions.overrule_sync_lines`, which owns the
record's format and is handed the two trees as readers; `ruling_sync_lines`
asks it of the same diff, so both places ask it with no second step or rung).
The sync's two git reads, a NUL-delimited path list and a blob read that
refuses a listed but unreadable blob, are `kitlib.git`'s.

TEXT THEN ACT (WI-806) is a separate judgement with its own module,
`text_then_act.py` (WI-892), which shares only `_commit_parents`, the ruling
sync's parent reader, kept here as its one home.
"""

import hashlib
import json
import tomllib
from pathlib import PurePosixPath

try:
    import spine_carrier
    from kitlib import decisions as _kitdecisions
    from kitlib import done_when as _kitdone
    from kitlib import git as _kitgit
    from kitlib import registry as _kitregistry
    from kitlib import sitting as _kitsitting
    from kitlib import verdict as _kitverdict
    from kitlib import spine as _kitspine
except ImportError:  # pragma: no cover - in-process fallback
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import spine_carrier
    from kitlib import decisions as _kitdecisions
    from kitlib import done_when as _kitdone
    from kitlib import git as _kitgit
    from kitlib import registry as _kitregistry
    from kitlib import sitting as _kitsitting
    from kitlib import verdict as _kitverdict
    from kitlib import spine as _kitspine

# `git -C <root> <args>` stdout on success, else None (git absent, not a repo,
# no such object). Every scan below degrades to None so the whole tier is a
# silent no-op outside a git checkout. The alias — rather than a body — is the
# `check.py` idiom: `kitlib.git` is the declared one home for this pattern, and
# the `stdin` batch argument that used to make this look like a different
# function is a parameter there since WI-521 slice 1.
_git = _kitgit.git_out


# The three spine registries the first-approval mint (`staged_drafted_rows`),
# the test-first walk and the retired flip read, each with its id column. The
# amend-without-flip warn (WI-316) and the amendment mint read this set until
# WI-791; extending them to needs was "its own decision rather than a side
# effect", and OI-100 (ruled 2026-10-03) made it — so they read the sibling
# `AMENDMENT_CSVS` below, and this constant keeps its three tiers for the
# readers whose scope did not move. The approval-act readers below are a
# different question and DO cover SN — `APPROVAL_ACT_CSVS`.
SPINE_CSVS = (
    ("docs/requirements/system-requirements.toml", "SR-ID"),
    ("docs/requirements/low-level-requirements.toml", "LLR-ID"),
    ("docs/test/test-cases.toml", "TC-ID"),
)

# THE APPROVAL-ACT RUNG'S OWN SET: the spine three PLUS the need tier
# (WI-572 REVIEW-A round 028). SN is a SPINE tier — `spine_carrier.SPINE_TABLE`
# names it, its rows carry the same `status` vocabulary, and the DevStg-Reqs
# rung the human-approval dial holds for the owner is exactly the SN half — so a
# lane flipping `SN-###` Drafted -> Approved is the WORST case of the act the
# owner's 2026-09-01 ruling moved to the adjudicator, not an exempt one. It was
# excluded only by the older section-as-state reading recorded at
# `baseline_snapshot._claims_approval`, which the `status` cell retired.
#
# A SEPARATE CONSTANT rather than a widened `SPINE_CSVS` because the two
# questions have different scopes on purpose: `SPINE_CSVS` is the amendment
# warn's and the intake mint's universe (`intake.py`, `check_trajectory.py`
# re-export), and silently widening those is the side effect the comment above
# refuses. Only the refusal walk reads this one.
#
# THE ASSUMPTIONS REGISTRY'S TWO TIERS JOIN IT (SR-191, SR-192). An assumption
# or a surrogate is approved content recorded like every other, and approving
# one means reading the requirements that rely on it, which one lane does not
# hold: a lane's merge approving one is refused, and the act that does approve
# one rides its own reviewed commit.
# Implements: SR-191, SR-192, LLR-220
APPROVAL_ACT_CSVS = SPINE_CSVS + (
    ("docs/requirements/stakeholder-needs.toml", "SN-ID"),
    ("docs/requirements/assumptions.toml", "DA-ID"),
    ("docs/requirements/assumptions.toml", "SUR-ID"),
)

# THE OTHER SIDE OF THAT BOUNDARY, DECLARED RATHER THAN LEFT AS AN ABSENCE.
# `baseline_snapshot.SNAPSHOTTED` names eight registries whose `Status` a
# snapshot anchors; `APPROVAL_ACT_CSVS` above names the five the refusal walks.
# The remaining three are OUT OF SCOPE OF THE APPROVAL-ACT RUNG, and that is a
# ruling rather than an oversight: the interface, external-frame and component
# registries are OFF-SPINE, their approval cells are governed by OI-30 D3, and
# the 2026-09-01 ruling scopes this rung to SPINE rows — so a lane moving an
# interface, frame or component row's `status` is not performing the act
# `lane_approval_refusal` refuses, and widening to them is OI-30's call.
#
# WHY A CONSTANT AND NOT A COMMENT. The hazard the review named is a tier that
# joins `SNAPSHOTTED` and reaches NO approval reader — silently, because these
# two lists sit hundreds of lines apart in different modules. Naming the
# exclusions makes the two sets a closed statement:
# `SNAPSHOTTED == APPROVAL_ACT_CSVS + OUTSIDE_THE_APPROVAL_ACT`, pinned by
# `tests/test_acceptance_record.py`. A new tier therefore cannot be added
# without landing on one side or the other by a deliberate edit.
# THE AMENDMENT WALK'S UNIVERSE (OI-100 gap 1, ruled 2026-10-03; WI-791): every
# tier an approval act can bless. An amendment is text moving away from its
# blessing, so the tiers whose text an act blesses are exactly the tiers whose
# amendment owes a meaning-or-clarity judgement — the needs, the assumptions and
# the surrogates among them, which the walk left out until WI-616's need edits
# merged and minted nothing. An ALIAS, not a second literal, so the two sets
# cannot drift apart; a SIBLING of `SPINE_CSVS`, not a widening of it, so that
# constant's other readers keep their three tiers.
#
# THE PRE-COMMIT WARN'S SCOPE IS THIS SET TOO, decided in the same change: the
# warn (`staged_spine_findings`) and the mint (`intake._routed_amendments`) read
# one walk, `staged_spine_amendments`, so the author is warned at the commit
# about exactly the rows the merge will route to an adjudicator. The mint then
# drops the rows the merged range re-attested and left equal to their snapshot
# copies (`settled_amendments`, LLR-364); the warn reads the unfiltered walk,
# because it fires before any act. The hat arm stays structurally silent on
# these tiers: none carries `Hat-Refs`.
# Implements: SR-178, LLR-158
AMENDMENT_CSVS = APPROVAL_ACT_CSVS

OUTSIDE_THE_APPROVAL_ACT = (
    "docs/requirements/interfaces.toml",
    "docs/requirements/external.toml",
    "docs/requirements/components.toml",
)

# --- the spine carrier -------------------------------------------------------
# The vocabulary and both readers live in `spine_carrier.py`, imported as a
# sibling — see that module's docstring for why it is ONE home and how that
# amends the F5 ruling.
SPINE_TABLE = spine_carrier.SPINE_TABLE
SPINE_COLUMN = spine_carrier.SPINE_COLUMN
_spine_stem = spine_carrier.stem
_spine_carriers = spine_carrier.carriers
# A TIER's carrier set and its text reader are `spine_carrier`'s, never listed
# here: the needs file's tiers sit under the need carriers (its legacy `.md`
# included), every other tier under the row carriers (WI-841 round 6).
_tier_carriers = spine_carrier.tier_carriers


def _spine_rows_at(root, rev_prefix, rel_path, id_col):
    """{id: row} of a spine registry on ONE side of the two-tree scan, read
    through whichever carrier that side actually uses (`spine_carrier`'s tier
    carriers, in preference order). `rev_prefix` is a `git show` prefix: `"HEAD:"`,
    `"abc123:"`, or `":"` for the index.

    Each side resolves independently, and that is the point rather than a
    convenience: across the cutover commit the old side is CSV and the new side
    is TOML, so this scan compares the two carriers CELL FOR CELL and reports
    any row whose approved text did not survive. The carrier change is then not
    exempt from the amendment guard — it is checked by it, independently of the
    converter's own round-trip proof. A silent-no-op degrade (`{}`) is kept for
    a side that has neither carrier, which is the pre-registry history case;
    a carrier that cannot be read or does not parse is skipped for the next
    (`_snapshot_copy_rows` is the reader that refuses one)."""
    for _path, rows, _failure in _tier_reads(root, rev_prefix, rel_path, id_col):
        if rows is not None:
            return {r: row for r, row in rows.items() if not str(r).endswith("-000")}
    return {}


def _tier_reads(root, prefix, rel_path, id_col, under=""):
    """Each carrier of one tier the tree at `prefix` lists, in preference
    order, as `(path, rows, failure)`: `rows` its `{id: row}`, or None with
    `failure` "cannot be read" (listed, but its blob cannot be read) or "does
    not parse". `under` is prefixed to each carrier path (the snapshot's
    copies). The one carrier loop: `_spine_rows_at` skips a failed carrier,
    `_snapshot_copy_rows` refuses on it.

    Implements: SR-246, LLR-358"""
    for cand in _tier_carriers(rel_path, id_col):
        path = under + cand
        try:
            text = _kitgit.git_show(root, prefix, path)
        except _kitgit.UnreadableBlob:
            yield path, None, "cannot be read"
            continue
        if text is None:
            continue
        suffix = "." + cand.rsplit(".", 1)[1]
        rows = spine_carrier.tier_rows_from_text(text, id_col, suffix)
        yield path, rows, None if rows is not None else "does not parse"


# The §A5.1 cell split (OWNER RULING 2026-07-31, docs/concurrency-v2.md; WI-380).
# Only what is APPROVED arms the re-attest warn. Traceability is TRACED, not
# approved: re-pointing an LLR at the module the code moved to amends no
# attested prose. WI-280 paid for the conflation — 19 `Module` cells followed
# moved code -> 11 owning SRs flipped off `Approved` -> the gate dropped DevStg-Impl->DevStg-Tests -> a
# approve brief and four review rounds, for a change that altered no requirement.
#
# BOTH halves are declared per registry, and the RESIDUAL RULE FAILS SAFE: a
# column in neither set is treated as APPROVED. A column added to a registry
# after this table was written can therefore only ever be too loud — a spurious
# window someone sees and dismisses — never silently un-approved, which would
# be a MISSED window nobody sees. `tests/test_trajectory_staged.py` pins both
# halves of that: the unknown-column behaviour, and that every column of the
# live and shipped-template headers is classified here (so a new column cannot
# ride in on the residual unnoticed).
#
# `Boundary-Refs` (SR) joins the TRACED half at WI-442, on `SN-Refs`' own argument
# rather than a new one: it is the same SHAPE of pointer — which declared
# boundary crossing does this requirement state an observable at — it carries no
# prose either side, and whether a re-point moved SCOPE is exactly the judgement
# the adjudication kind exists to make. So a changed `Boundary-Refs` ROUTES to
# adjudication (intake.ROUTED_TRACED_CELLS) beside `SN-Refs`; it never arms a
# re-attest window directly. Classifying it approved instead would arm a window
# on every row of the re-tier campaign, which is the noise that gets a window
# ignored — and the campaign's re-statements touch `Requirement` anyway, which
# IS approved, so nothing escapes attestation by this choice.
#
# `Hat-Refs` (SR and LLR) joins the TRACED half at WI-484, and the classification
# is the load-bearing half of shipping the cell rather than a footnote. Three
# reasons, in the order that decides it: (1) it is the same SHAPE of pointer as
# `SN-Refs`/`Boundary-Refs` — which declared row in another registry bears on this
# one — carrying no prose either side; (2) the residual would classify it APPROVED,
# so the phase-2 backfill would arm a re-attest window on every row it touched,
# which is precisely the 148-row noise `Boundary-Refs` was classified out of; and
# (3) the owner's own sequencing note prices this ruling — the cell "is NOT
# anticipated to be an attested cell, so it can be tacked on AFTER the sitting
# without re-opening anything signed", which is only true if it is classified here.
# It is deliberately NOT in `intake.ROUTED_TRACED_CELLS`: re-pointing `SN-Refs`
# may have moved SCOPE, which is a judgement adjudication exists to make, while a
# hat re-point restates which lens the row is attributable to and moves no
# obligation. If phase 5's amend-without-flip arm ever wants that routing, it is
# one line — added on evidence, not in advance.
#
# THE ASSUMPTION TIER'S POINTERS JOIN IT (LLR-225), on the same argument: a
# requirement's `DA-Refs` and a test case's `Assumption-Refs` name rows in
# another registry, and a need's `Stakeholder-Refs` and `Source` name the
# stakeholders it serves and the document it was drawn from. Each re-points
# without moving anything the row asserts.
# Implements: SR-189, SR-190, SR-193, SR-197, LLR-225
SPINE_TRACED_CELLS = {
    "docs/requirements/system-requirements.toml": frozenset(
        {
            "SN-Refs",
            "Boundary-Refs",
            "Hat-Refs",
            "Phase",
            "Aspect",
            "Lifecycle",
            "DA-Refs",
        }
    ),
    # `SR-Refs` is here BY RULING (WI-388, closing WI-380 REVIEW-A finding 3 —
    # the cell §A5.1 left unclassified): it is the same shape of pointer as
    # the ruled-traced `SN-Refs`/`Verifies` — which SR owns this decomposition
    # row — and re-pointing it changes no attested prose on either side.
    # Whether the re-point moved scope is exactly the judgement the
    # adjudication kind exists to make, so a changed `SR-Refs` ROUTES to
    # adjudication (intake.ROUTED_TRACED_CELLS) like its two siblings; it
    # never arms a re-attest window directly.
    "docs/requirements/low-level-requirements.toml": frozenset(
        {
            "Module",
            "CodeSymbol",
            "TestRefs",
            "Component",
            "Phase",
            "SR-Refs",
            "Hat-Refs",
        }
    ),
    "docs/test/test-cases.toml": frozenset(
        {"Verifies", "Evidence", "Automated", "Phase", "Assumption-Refs"}
    ),
    "docs/requirements/stakeholder-needs.toml": frozenset(
        {"Stakeholder-Refs", "Source"}
    ),
}
# The approved half. (The SR tier's `SupersededBy` column — approved by ruling
# at WI-388 — retired with the supersession tombstone class, D-4 ruling
# 2026-08-14b; the CMP registry's own SupersededBy is a separate, still-owed
# item.) The assumption tier's STATEMENTS join it by name rather than by the
# residual (LLR-225): a requirement's `Coincident` waiver and `Form`, and a test
# case's declared `Inputs`, `MaxAge`, `Sampling`, `SampleSize` and
# `AcceptanceRule`, each a claim the row makes. `Delivered-With` joins the
# approved half under LLR-222: changing which siblings jointly deliver the need
# changes the requirement's own argument, rather than merely re-pointing trace.
# An observation case's cadence cells `Trigger`, `Rubric` and `MinWorkItems`
# join by name too (WI-784), keeping the residual's reading: like `MaxAge` and
# `Inputs`, each states how the row's claim is judged or kept current.
# Implements: SR-193, SR-194, SR-198, LLR-222, LLR-225
SPINE_APPROVED_CELLS = {
    "docs/requirements/system-requirements.toml": frozenset(
        {
            "Title",
            "Requirement",
            "Rationale",
            "AcceptanceCriteria",
            "Permutations",
            "Priority",
            "Verification",
            "Delivered-With",
            "Coincident",
            "Form",
        }
    ),
    "docs/requirements/low-level-requirements.toml": frozenset(
        {"Title", "Detail", "Rationale"}
    ),
    "docs/test/test-cases.toml": frozenset(
        {
            "Method",
            "Expected",
            "Parameters",
            "Level",
            "Tier",
            "Inputs",
            "MaxAge",
            "Sampling",
            "SampleSize",
            "AcceptanceRule",
            "Trigger",
            "Rubric",
            "MinWorkItems",
        }
    ),
}

# THE OFF-SPINE REGISTRIES' TRACED HALF (LLR-225). Until this table no
# off-spine registry declared one, so every off-spine cell counted as approved
# through the residual. Two cells are pointers: an interface's `BridgedBy`
# names the assumptions bridging it, and an assumption's `ObstacleHats` names
# the perspectives its obstacle came from. Every other off-spine cell stays
# approved content (an interface's `Coincident`, a stakeholder's name,
# description and party, a crossing's `System`, an entity's `Mediates`, and the
# rest of the assumption and surrogate cells), because each states something
# the row asserts rather than pointing at another row.
# Implements: SR-211, SR-214, LLR-225
OFFSPINE_TRACED_CELLS = {
    "docs/requirements/interfaces.toml": frozenset({"BridgedBy"}),
    "docs/requirements/assumptions.toml": frozenset({"ObstacleHats"}),
}


def spine_cell_class(csv_path, column):
    """`"traced"` for a column §A5.1 rules traceability, else `"approved"`.

    The residual is deliberate and fails SAFE: an unclassified column — one
    added to a registry after the ruling — reads as approved and keeps arming
    the warn. See SPINE_TRACED_CELLS.

    KEYED BY THE REGISTRY, NOT BY ITS FILENAME. The two tables above are keyed
    on paths that carry a carrier SUFFIX, and the callers do not agree on which
    one: a staged-diff scan names whichever file git reported, while a live read
    names the constant. Under the CSV carrier a `.toml`-keyed lookup misses, and
    a miss here does not red — every column reads `approved`, so a traced-only
    edit arms a re-attest window that was ruled not to. `stem` drops the suffix,
    which is what `spine_carrier` exists to make possible.

    Implements: SR-178, LLR-158
    """
    return "traced" if column in traced_cells(csv_path) else "approved"


def traced_cells(csv_path):
    """The §A5.1 traced column set declared for this registry, carrier-suffix
    insensitive — `frozenset()` for a registry that declares none.

    Extracted from `spine_cell_class` (its own body, unchanged) because a second
    caller needs the SET rather than one column's class: the Hat-Refs arm below
    asks whether this TIER carries the column at all, which a per-column class
    cannot answer (an absent column classes `approved`, the fail-safe residual,
    and would make every TC amendment warn about a cell that tier does not
    have)."""
    key = spine_carrier.stem(csv_path)
    tables = SPINE_TRACED_CELLS | OFFSPINE_TRACED_CELLS
    traced = {spine_carrier.stem(k): v for k, v in tables.items()}
    return traced.get(key, frozenset())


# --- the §A5.1 cell comparison ------------------------------------------------
# WHAT WAS HERE AND WHY IT IS GONE (owner directive 2026-08-15). SN-029's digest
# engine — `normative_text`, `sn_normative_text`, `digest`, `current_digests` and
# their two exclusion sets — lived here for ~107 lines, reserved for an on-row
# `TextHash`/`HashedOn` writer (repo-lock D-1's anchor half) that was never
# built. That half is RULED unnecessary complexity: an approval now records what
# it blessed by COPYING the registries to `docs/archive/last_approved/`
# (`baseline_snapshot.py`), and a copy needs no canonical text to hash, no
# separator that cannot occur in a cell, and no second exclusion list.
#
# `split_changed_cells` below is what survived, and it is the better half: it
# answered the same question the digest did — which cells moved, approved or
# traced — while also returning the before/after pairs a brief has to render
# anyway. It is PUBLIC because `baseline_snapshot.is_drifted` reads it as the
# drift basis, so the snapshot comparison and the amend-without-flip warn can
# never disagree about what "normative" means.
#
# A ROW-TEXT IDENTITY CAME BACK, AND IT ANSWERS THAT DIRECTIVE POINT BY POINT
# (`approved_text_digest`). A verdict about one approved text authorizes no
# later text, so a held re-attestation must name the text its verdict judged;
# a copy is written at the act, after the sitting, so it cannot witness what
# the sitting saw. The identity is not an on-row cell: it lives in the
# verdict's binding. It needs no separator, because JSON escapes every cell.
# And it keeps no exclusion list of its own: it hashes exactly the cells
# `spine_cell_class` classes approved, the classes this comparison uses.

# The Status values whose ROW TEXT is approved — the population the
# amend-without-flip guard scans. ONE MEMBER SINCE D-9 STEP 5, and it is a
# CONTRACTION OF SPELLING, NOT OF SCOPE: the set used to hold `verified` and
# `planned` because the pair split one rung ("text blessed, evidence
# established" vs "text blessed, evidence pending"), and OI-30 D1 folded them
# into the single `Approved`. `Drafted` does not belong: nothing has been
# blessed, so there is nothing to amend behind a human's back. `Founded`
# does not either, and its exclusion is DELIBERATE rather than pending: the rung
# is COMPUTED from a row's children existing, so a cell reading it is not a
# second attestation of the row's own text — the `Approved` claim underneath it
# is the one this guard watches. Lowercase, matching the guard's own
# normalisation.
# (`Modified` used to be listed here as excluded-because-the-marker-is-already-set;
# it retired at D-9 step 7 and the exclusion retired with it.)
# Implements: SR-178, LLR-158
_APPROVED_TEXT = frozenset({"approved"})


def split_changed_cells(csv_path, id_col, head, row):
    """One row's changed cells, split into the §A5.1 halves with their
    before/after: `{"approved": {cell: (before, after)}, "traced": {...}}`.
    The id column and `Status` are not content (the id is the join key; Status
    is the flip the caller is asking about), so neither is compared.

    Implements: SR-178, LLR-158
    """
    changed = {"approved": {}, "traced": {}}
    for key in set(head) | set(row):
        if key in (id_col, "Status"):
            continue
        before, after = (head.get(key) or ""), (row.get(key) or "")
        if before != after:
            changed[spine_cell_class(csv_path, key)][key] = (before, after)
    return changed


def approved_text_digest(csv_path, id_col, row):
    """The identity of one row's approved text: `sha256:` and the first 16
    lowercase hex of SHA-256 over its nonempty approved cells, the id column
    and `Status` excluded, serialized as sorted JSON. The cells are classed by
    `spine_cell_class`, as `split_changed_cells` classes them, so the identity
    a verdict binds and the drift that comparison reports read one split; an
    empty cell is dropped, as that comparison reads it like an absent one.

    Implements: SR-178, LLR-359
    """
    cells = {
        str(key): value
        for key, value in row.items()
        if key not in (id_col, "Status")
        and value
        and spine_cell_class(csv_path, key) == "approved"
    }
    text = json.dumps(cells, sort_keys=True, ensure_ascii=True, separators=(",", ":"))
    hexed = hashlib.sha256(text.encode("utf-8")).hexdigest()
    return "sha256:" + hexed[: _kitdone._DIGEST_CHARS]


def _spine_revs(root, base, head, touches=()):
    """`(changed-paths, old-prefix, new-prefix)` for the two trees the spine scan
    compares, or None when git cannot answer (the silent-no-op degrade).

    The prefixes are `git show` arguments: `"HEAD:"`, `"abc123:"`, or `":"` for
    the INDEX. `head=None` means the index — the `--staged` hook case, and the
    default. Any other value is a commit-ish, which is what §A5.2's trigger
    needs: adjudication is minted from *a trunk commit that changed an approved
    cell*, and a commit is not the index.

    `touches` is the caller's applicability test — the registry paths at least
    one of which must appear in the changed set for the scan to have anything to
    say. It lives HERE rather than at each call site because "git could not
    answer" and "git answered, and nothing relevant moved" produce the identical
    `return []` degrade in every consumer, and writing that pair twice is the
    intra-file duplication WI-347 rules a defect."""
    # `--no-renames` so a MOVED registry shows up as its old path too. With
    # rename detection on, `git diff --name-only` reports only the destination,
    # so `git mv docs/test/test-cases.csv elsewhere.csv` was invisible to every
    # `touches` test here. (The append-only ledger guard was the rung that found
    # this; the rule outlives it — D-1 retired the ledger, not the hazard.)
    if head is None:
        names = _git(root, ["diff", "--cached", "--name-only", "--no-renames", base])
        new_prefix = ":"
    else:
        names = _git(root, ["diff", "--name-only", "--no-renames", base, head])
        new_prefix = head + ":"
    if names is None:
        return None
    changed = set(names.splitlines())
    if touches and not any(p in changed for p in touches):
        return None
    return changed, base + ":", new_prefix


def _spine_row_sides(root, base, head, registries=SPINE_CSVS):
    """`(registry, id_col, before_rows, after_rows)` per spine registry the two
    trees actually differ in — THE ONE two-tree spine walk, shared by every
    reader below it.

    `registries` is the walk's UNIVERSE and defaults to `SPINE_CSVS`; the
    approval-act reader passes `APPROVAL_ACT_CSVS`, which adds the SN tier. The
    parameter exists so the two scopes are one walk with one set of carrier and
    `--no-renames` rules rather than two walks that could drift.

    Extracted at WI-572 rather than copied: that row's lane refusal and its
    first-approval trigger ask two more questions of the SAME diff
    `staged_spine_amendments` already reads (which rows FLIPPED, which arrived
    `Drafted`), and a second walk would be a second place for the
    `--no-renames`/carrier-resolution/`-000` rules to drift out of agreement.
    Yields nothing when git cannot answer or nothing relevant moved — the
    silent-no-op degrade `_spine_revs` owns."""
    revs = _spine_revs(
        root,
        base,
        head,
        touches=sorted(c for p, col in registries for c in _tier_carriers(p, col)),
    )
    if revs is None:
        return
    staged_names, old_rev, new_rev = revs
    for csv_path, id_col in registries:
        # The record names the carrier file that ACTUALLY changed, not the
        # constant: the constant carries a suffix, and reporting
        # `system-requirements.toml` for a repo whose staged diff touched
        # `system-requirements.csv` names a file that does not exist — in a
        # record an adjudication row quotes back to a human.
        touched = [c for c in _tier_carriers(csv_path, id_col) if c in staged_names]
        if not touched:
            continue
        before_rows = _spine_rows_at(root, old_rev, csv_path, id_col)
        after_rows = _spine_rows_at(root, new_rev, csv_path, id_col)
        yield touched[0], id_col, before_rows, after_rows, csv_path


# Whether a spine row's `Status` claims approval or above: the PAIR (`Approved`
# and the computed `Founded` above it), so the approval-act readers below ask
# one question instead of each restating which rungs count as blessed. Its one
# home is `kitlib.spine.claims_approval`, which the parent-first rule reads
# too, so the rule and these readers agree on what counts as approved. Note
# the deliberate difference from `_APPROVED_TEXT`, three hundred lines up: that
# set is the amend-without-flip guard's, and excludes `Founded` because a
# computed rung is not a second attestation of the row's own text. Here the
# question is "does this cell CLAIM approval", and `Founded` does.
_claims_approval = _kitspine.claims_approval


def _approval_act(registry, rid, before, row):
    """The approval act ONE row performs across the two sides, or None.

    The per-row half of `staged_approval_acts` below, extracted so the walk
    around it is "visit every row of every changed registry" and the judgement
    is stated once, in one place, for both shapes. The two arms answer the same
    question from two directions — text that was never blessed is now blessed —
    and reading them side by side is how the mirror in that docstring stays
    checkable.

    An id-less row is not a row (the `-000` template placeholder and a blank
    key both land here); a de-approval and an unchanged status both fall
    through to None, which is the subtraction that docstring states."""
    if not rid:
        return None
    if before is None:
        # A row absent on the base side. `before_rows` is `{}` for a newly
        # ADDED registry too, which is why the born arm still answers there: a
        # registry that arrives with approved rows in it is the same
        # unblessed-text-now-blessed event.
        if not _claims_approval(row):
            return None
        act, was = "born", ""
    elif not _claims_approval(before) and _claims_approval(row):
        act, was = "flip", (before.get("Status") or "").strip()
    else:
        return None
    return {
        "registry": registry,
        "id": rid,
        "act": act,
        "before": was,
        "after": (row.get("Status") or "").strip(),
    }


def staged_approval_acts(root, base="HEAD", head=None):
    """Every APPROVAL ACT a spine delta performs between two trees:

        [{"registry": <carrier path>, "id": <row id>, "act": "flip" | "born",
          "before": <status>, "after": <status>}]

    An act is a row crossing INTO an approval claim (`act = "flip"` — `Drafted`
    → `Approved`/`Founded`) or a row that ARRIVES already claiming one
    (`act = "born"`, absent on the base side). Both are the same event seen from
    two directions: text that was never blessed is now blessed, and the
    `docs/archive/last_approved/` copy that anchors it is owed.

    THE READING IS THE MIRROR OF `staged_spine_amendments`, deliberately: that
    one reports rows whose approved text moved while Status stood still and
    EXEMPTS a moved Status ("a deliberate call this does not second-guess"); this
    one reports THE EXEMPTED SET MINUS THE DE-APPROVALS. The two share
    `_spine_row_sides` so they cannot disagree about which rows exist, and the
    subtraction is stated rather than left to the reader because a mirror
    claiming to be exact and then carving out a case is two sentences that
    disagree.

    A DE-APPROVAL IS NOT AN ACT, and that is the subtraction. `Approved` →
    `Drafted` withdraws a claim; it blesses nothing, so it owes no snapshot and
    refuses no merge. It is not dropped on the floor either — `staged_drafted_rows`
    reports it as an amended `Drafted` row, so the first-approval mint raises the
    re-approval it now owes. Same direction as
    `baseline_snapshot._approval_transition`, which asks the live-vs-snapshot
    form of this question.

    ITS UNIVERSE IS `APPROVAL_ACT_CSVS`, the four SPINE registries — SN, SR,
    LLR, TC — and the assumptions registry's two tiers, and not `SPINE_CSVS`,
    which is the amendment warn's three. SN is
    covered because it is a spine tier carrying the same `status` vocabulary and
    is the half of DevStg-Reqs the human-approval dial holds, so a lane flipping
    a need is the worst case of this act rather than an exempt one (round 028).
    The three OFF-SPINE registries stay out; see `OUTSIDE_THE_APPROVAL_ACT`.

    Owner ruling 6, 2026-10-07 (WI-849): the act this reports is an independent
    adjudicator's, in the authoring lane or on trunk. `approval_delta` directly
    below reads it ONCE for `merge_approval_refusal`, which requires every act
    backed by an accepted verdict over its own rows, and an adjudication row's
    recorded scope besides, at `integrate._approval_act_refusal`
    — this reader does not itself cross the `IF-091` seam, and the seam does not
    declare that it does.

    Returns [] when not applicable; any missing git context is a silent no-op,
    like `staged_spine_amendments`."""
    out = []
    for registry, _id_col, before_rows, after_rows, _csv in _spine_row_sides(
        root, base, head, APPROVAL_ACT_CSVS
    ):
        for rid, row in after_rows.items():
            act = _approval_act(registry, rid, before_rows.get(rid), row)
            if act:
                out.append(act)
    return out


def rows_at(root, rev, rel_path, id_col):
    """`{id: row}` of one spine registry at commit `rev`, or `{}` when the
    registry is absent there under either carrier — `_spine_rows_at`, the row
    reader behind every two-tree scan in this module, offered for a walk along
    history (`check_test_first.first_approval_commits`).

    Public so a history reader parses a row the way the approval-act refusal
    does, through the same carrier resolution and the same `-000` filter,
    rather than growing a second reader of the registries at a revision."""
    return _spine_rows_at(root, rev + ":", rel_path, id_col)


def approval_acts_between(registry, before_rows, after_rows):
    """The approval acts `after_rows` perform against `before_rows`, in
    `staged_approval_acts`' record shape: every row that crossed into an
    approval claim (`flip`) or arrived already making one (`born`).

    THE HISTORY FORM OF THE SAME RULE. `staged_approval_acts` reads its two
    sides from two trees; a walk along trunk carries each commit's rows forward
    as the next commit's before side, so it asks the question of two row maps
    instead and reads each registry once per commit that touches it. The act
    itself is `_approval_act` in both, so the history and the lane refusal
    cannot disagree about which change blessed a row."""
    acts = []
    for rid, row in after_rows.items():
        act = _approval_act(registry, rid, before_rows.get(rid), row)
        if act:
            acts.append(act)
    return acts


# How `git diff --name-status` letters read as the ACT a branch performed on the
# snapshot. Worded from the letter rather than assumed, because the record is
# read by a human deciding why their merge stopped, and a branch that DELETES a
# stale `SNAPSHOT_DIR` file reported as one it "wrote" is a false sentence in the
# one artifact that explains the stop. An unrecognised letter is still named —
# the file changed, and which way is the part this does not know.
_SNAPSHOT_ACT = {"A": "wrote", "M": "rewrote", "D": "deleted"}


def _snapshot_acts(name_status):
    """Yields `"<verb> <path>"` for a `--name-status` block: one line per
    `SNAPSHOT_DIR` file the delta touched, worded by its status letter. A line
    with no tab-separated path is skipped — an unparseable line is not an act."""
    for line in name_status.splitlines():
        parts = line.split("\t")
        if len(parts) < 2 or not parts[-1].strip():
            continue
        letter = parts[0].strip()[:1]
        yield "{} {}".format(_SNAPSHOT_ACT.get(letter, "changed"), parts[-1].strip())


def approval_delta(root, base, head):
    """`(row acts, worded snapshot acts, refusal)` for one merge delta."""
    acts = staged_approval_acts(root, base, head)
    out = _git(
        root, ["diff", "--name-status", "--no-renames", base, head, "--", SNAPSHOT_DIR]
    )
    if out is None:
        return (
            [],
            [],
            (
                "cannot read {}'s {} delta against {}, so whether this branch wrote "
                "the approval record is unknowable; nothing was merged".format(
                    head, SNAPSHOT_DIR, str(base)[:10]
                )
            ),
        )
    return acts, sorted(_snapshot_acts(out)), None


def first_approval_scope(metas):
    """The typed scope of claimed first-approval rows (a combined sitting's
    `first-approval:` tokens included), read through `kitlib.sitting`'s one
    claimed-row reader, or None when none scopes one."""
    scopes = [_kitsitting.brief_scope(meta, "first-approval") for _name, meta in metas]
    scopes = [scope for scope in scopes if scope is not None]
    return frozenset(r for s in scopes for r in s) if scopes else None


def _registry_identity(path):
    """The approval-act registry a carrier path belongs to (its tier's
    canonical path, whichever of `spine_carrier.tier_carriers` names it), or
    the path itself for a file of no approval-act tier.

    Implements: SR-178, LLR-278"""
    hits = (rel for rel, col in APPROVAL_ACT_CSVS if path in _tier_carriers(rel, col))
    return next(hits, path)


def lane_acted_set(root, base, head, delta):
    """THE ONE DERIVATION OF A LANE'S ACTED SET (WI-849, Sol r3): `(acted,
    refusal)`, `acted` being `{"approve": {row id: registry}, "reattest": {row
    id: registry}}` - every row the lane approved or re-attested, with the
    registry its id's tier names (a live flip: the registry the two-tree walk
    reports), present at the head or not, so a retired row authorizes its own
    registry's copy. Approvals are the delta's live Status transitions
    (a flip or a row born approved) AND the `approved` rows of the act-ledger
    entries the branch added (`_added_acts`), which name rows the snapshot
    writer carried into approval with no live flip - a row live-approved at
    the base whose recorded copy still read below it. Re-attestations are the
    ledger's (`reattested_between`). The scope check, the backing check and
    the copy authorization all take this one set, so an act seen by one is
    seen by all; "no act" is both kinds empty. An unreadable delta or ledger
    is the refusal, never an empty set.

    Implements: SR-178, LLR-278"""
    acts, _files, refusal = delta
    reattested, added = frozenset(), []
    if not refusal and _wrote_ledger(delta):  # an unwritten ledger added nothing
        reattested, refusal = reattested_between(root, base, head)
        added = _added_acts(root, base, head)
    if refusal:
        return {"approve": {}, "reattest": {}}, refusal
    approve = {act["id"]: act["registry"] for act in acts}
    ledger = {str(r) for a in added for r in a.get("approved") or []} - set(approve)
    approve.update({rid: _tier_of(rid)[0] for rid in ledger})
    return {
        "approve": approve,
        "reattest": {r: _tier_of(r)[0] for r in reattested},
    }, None


def _copy_lines(acted, snapshot_files):
    """THE COPY AUTHORIZATION over the acted set (`lane_acted_set`): a refusal
    line for each registry copy no acted row authorizes (WIDENED) and each
    approved row's registry with no copy (WITHOUT ITS ANCHOR), `[]` when the
    copies match the acts. The record's own files (`SNAPSHOT_OWN_FILES`) are
    not registries. Both sides compare REGISTRY IDENTITY (`_registry_identity`).

    Implements: SR-178, LLR-278"""
    written = {
        line.partition(" ")[2][len(SNAPSHOT_DIR) + 1 :] for line in snapshot_files
    }
    ident = _registry_identity
    held = [reg for kind in acted.values() for reg in kind.values() if reg]
    authorized = {ident(r) for r in held}
    copied = {ident(r) for r in written - SNAPSHOT_OWN_FILES}
    widened = sorted(
        r for r in written - SNAPSHOT_OWN_FILES if ident(r) not in authorized
    )
    approved = acted["approve"].values()
    missing = sorted({r for r in approved if r and ident(r) not in copied})
    return [
        "  snapshot WIDENED to {} without an approved row".format(r) for r in widened
    ] + ["  {} was approved WITHOUT its anchoring snapshot".format(r) for r in missing]


def adjudication_approval_refusal(scope, acted, delta):
    """Judge the ACTED SET (`lane_acted_set`), never a scope on its own
    (WI-849, Sol r2, r3): every approved row - a live flip or a ledger-only
    approval alike - lies in `scope` (an empty scope is OUTSIDE's EMPTY
    wording; `scope` None means the lane records none, so only its copies are
    judged), and every registry copy belongs to an acted registry. A lane with
    no act and no copy meets nothing here. A registry copy is WIDENED unless
    the set holds a row there, approved or re-attested, so the sections of one
    combined sitting each keep their own act (WI-841); an approved row's
    registry with no copy is WITHOUT ITS ANCHOR (`_copy_lines`). Both sides
    compare REGISTRY IDENTITY (`_registry_identity`), so every carrier path of
    an authorized registry is its act's own - the obsolete carrier's copy a
    conversion deletes included."""
    _acts, snapshot_files, refusal = delta
    if refusal:
        return refusal
    approved = acted["approve"]
    outside = sorted(r for r in approved if scope is not None and r not in scope)
    copies = _copy_lines(acted, snapshot_files)
    if not outside and not copies:
        return None
    where = "`Adjudicates` scope ({})".format(";".join(sorted(scope or ())))
    where = where if scope else "an EMPTY `Adjudicates` scope"
    lines = ["  {} is OUTSIDE {}".format(rid, where) for rid in outside] + copies
    # THE REMEDY, PER ARM. The three lines above say what the delta did; a
    # session reading only those learns it is stopped and not what to do — and
    # the WIDENED arm in particular is reached by following the brief exactly
    # (its `--approves` is fixed before the verdict, so a batch that returns a
    # registry's rows in full still names it). Each arm's repair is stated
    # where the stop is read; a lane recording no scope is told of no
    # `Adjudicates` row.
    head = "the approval act's copies do not match its acts: the merge admits"
    if scope is not None:
        head = "first-approval adjudication exceeds the approval act recorded on its `Adjudicates` row: the merge admits only scoped flips and"
    return (
        "{} exactly their registry snapshots; nothing was merged:\n{}\nRemedy — "
        "WIDENED: `--approves` named a registry this act flipped nothing in (its "
        "rows were all RETURNED); drop that token and re-take the snapshot, so "
        "the copy blesses only text this act approved. WITHOUT ITS ANCHOR: the "
        "flip landed with no copy behind it; add that registry to `--approves`."
        "{}".format(
            head,
            "\n".join(lines),
            " OUTSIDE SCOPE: the row is another adjudication's; restore its "
            "`Status` byte-exact."
            if outside
            else "",
        )
    )


def merge_approval_refusal(root, base, head, metas, *, trunk):
    """Apply one derived approval delta to THE ONE ACTOR RULE (owner ruling 6,
    2026-10-07; WI-849): a lane's acts are admitted when every act is backed
    by an accepted verdict judging that act's own rows (`backed_act_refusal`),
    in whatever lane it is taken, and the snapshot copies exactly the
    registries those acts moved. A lane any of whose claimed rows records a
    scope (`kitlib.sitting.bounds_acts`: an adjudication-kind row, or a row
    scoping a first approval or an amendment) is bounded besides, whatever
    else it claims: its flips by the first-approval scope, its re-attestations
    by the amendment scope (`reattest_scope_refusal`). The bound is read off
    `metas`, never off a caller's flag, so a mixed lane keeps its adjudication
    row's scope (Sol r1 MAJOR 1); unreadable claims never reach here, the
    merge slot refuses them. A held rung is not judged here: every lane commit
    is judged against the dial committed on trunk by the lane rule that rides
    the merge slot's lane-commit walk (`held_status.commit_held_approval_lines`),
    so `trunk`, the commit the merge lands on, is read by no rule of this
    function. The scope, backing and copy checks all judge ONE acted set
    (`lane_acted_set`: the ledger's approvals and re-attestations and the live
    transitions), so an act recorded only in the ledger is judged by each.

    Implements: SR-178, LLR-278"""
    delta = approval_delta(root, base, head)
    acted, refusal = lane_acted_set(root, base, head, delta)
    if refusal:
        return refusal
    scope = None
    if any(_kitsitting.bounds_acts(meta) for _name, meta in metas):
        scope = first_approval_scope(metas) or frozenset()
        refusal = _kitsitting.malformed_refusal(metas)
        refusal = refusal or reattest_scope_refusal(acted, metas)
    elif not any(acted.values()):
        return lane_approval_refusal(root, base, head, delta)
    added = _added_acts(root, base, head)
    refusal = refusal or _kitsitting.unaccepted_refusal(root, head, added)
    refusal = refusal or backed_act_refusal(root, base, head, acted, delta)
    return refusal or adjudication_approval_refusal(scope, acted, delta)


def backed_act_refusal(root, base, head, acted, delta):
    """THE ACTOR TEST at the merge slot (owner ruling 6, 2026-10-07; WI-849):
    why a lane's approval acts may not merge, or None. Every act must be backed
    by an ACCEPTED verdict among the bindings the branch carries that judged
    that act's own rows: each row it flips or mints approved ruled APPROVE in a
    first-approval part, each row it re-attests ruled CLARITY, or MEANING with
    the bless mark, in an amendment part (the one reader,
    `kitlib.sitting.judged_rows`). It replaces "is every claimed spec of the adjudication
    kind?" as the test of who may act: the act is an independent
    adjudicator's, taken in the authoring lane or on trunk.

    The acts are the lane's one acted set (`lane_acted_set`): the act-ledger
    entries the branch added AND the delta's own flips, so a flip that wrote no
    ledger entry and a ledger approval no flip shows are judged alike. The judgement
    is WI-841's one reader (`kitlib.sitting.uncovered_refusal` over
    `accepted_at`), so a missing, failed, invalid or other-rows verdict refuses
    alike, worded with the acts by `lane_approval_refusal`. Independence rests
    on that reader: an outcome is recorded accepted only by
    `adjudicate_brief.record_outcome`, which a route calls after it ran the
    adjudication as its own call; no record names the session that authored a
    row, so the merge cannot compare the two sessions itself.

    Implements: SR-178, LLR-158"""
    acts = [
        {"approved": sorted(acted["approve"]), "reattested": sorted(acted["reattest"])}
    ]
    reason = _kitsitting.uncovered_refusal(root, base, head, acts)
    return reason and lane_approval_refusal(root, base, head, delta, reason)


def amendment_scope(metas):
    """The rows the claimed AMENDMENT adjudications ruled: the union of their
    `Adjudicates` cells and of a combined sitting's `amendment:` tokens, empty
    when none is claimed. A first-approval row's scope is its flips, not a
    re-attestation's.

    Implements: SR-178, LLR-278"""
    return frozenset(
        rid
        for _name, meta in metas
        for rid in _kitsitting.brief_scope(meta, "amendment") or ()
    )


def _ledger_read(root, rev):
    """`(acts, failure)`: the act ledger's `[[act]]` entries at `rev` (IF-220 is
    the ledger's shape). `([], None)` when the tree does not list it;
    `(None, "cannot be read")` when it lists it but its blob cannot be read;
    `(None, "does not parse")` when its text is not a ledger. The one reader
    that tells those three apart; `_ledger_acts` is its older two-valued view.

    Implements: SR-178, LLR-364"""
    try:
        text = _kitgit.git_show(root, rev + ":", SNAPSHOT_DIR + "/" + SNAPSHOT_ACTS)
    except _kitgit.UnreadableBlob:
        return None, "cannot be read"
    if text is None:
        return [], None
    try:
        acts = tomllib.loads(text).get("act", [])
    except tomllib.TOMLDecodeError:
        return None, "does not parse"
    return (acts, None) if isinstance(acts, list) else (None, "does not parse")


def _ledger_acts(root, rev):
    """The act ledger's `[[act]]` entries at `rev`, `[]` where it is absent, or
    None when it does not parse (IF-220 is the ledger's shape). A ledger whose
    blob cannot be read reads as absent here, the merge rung's contract;
    `_ledger_read` is the reader that refuses it."""
    acts, failure = _ledger_read(root, rev)
    return [] if failure == "cannot be read" else acts


def _reattested_added(root, base, head):
    """`(entries, failure)`: the ledger entries `head` added over `base`, in
    file order, or the ledger's path, revision and what went wrong when either
    side cannot be read or does not parse.

    Implements: SR-178, LLR-364"""
    sides = []
    for rev in (base, head):
        acts, failure = _ledger_read(root, rev)
        if failure:
            path = SNAPSHOT_DIR + "/" + SNAPSHOT_ACTS
            return [], "{} {} at {}".format(path, failure, rev)
        sides.append(acts)
    return added_ledger_entries(sides[1], [sides[0]]), None


def _latest_reattest(added, rid):
    """The index in the range-added ledger entries `added` of the latest one
    that re-attests `rid`, or None. Entries are in file order, which IF-220
    makes `seq` order.

    Implements: SR-178, LLR-364"""
    marks = [
        i for i, a in enumerate(added) if rid in map(str, a.get("reattested") or ())
    ]
    return marks[-1] if marks else None


def _no_later_writer(later, rel_path):
    """Did none of the ledger entries `later` write `rel_path`? An entry whose
    `copied` names the registry wrote it, and a legacy entry (no `copied`: its
    copy set is unknown, IF-220) may have.

    Implements: SR-178, LLR-364"""
    stem = spine_carrier.stem(rel_path)
    return not any(
        "copied" not in a or stem in {spine_carrier.stem(p) for p in a["copied"] or ()}
        for a in later
    )


def _reattested_ids(before, after):
    """The row ids re-attested by the ledger entries of `after` whose `seq`
    `before` does not hold.

    Implements: SR-178, LLR-278"""
    added = added_ledger_entries(after, [before])
    return frozenset(str(r) for a in added for r in a.get("reattested") or [])


def _snapshot_copy_rows(root, rev, rel_path, id_col):
    """`(rows, failure)`: `{id: row}` of the snapshot's copy of one tier at
    `rev`, through its carriers in preference order. `(None, None)` when the
    tree lists no copy; a listed copy that cannot be read or does not parse is
    a failure naming its path and revision, never an absence (which
    `_spine_rows_at` reads all three as).

    Implements: SR-178, LLR-364"""
    under = SNAPSHOT_DIR + "/"
    for path, rows, failure in _tier_reads(root, rev + ":", rel_path, id_col, under):
        if failure:
            return None, "{} {} at {}".format(path, failure, rev)
        return rows, None
    return None, None


def _row_settled(rel_path, id_col, copy_row, live_row, routed):
    """Does the live row equal its snapshot copy in every approved cell and
    every routed traced cell? A row missing from either side is not settled.

    Implements: SR-178, LLR-364"""
    if copy_row is None or live_row is None:
        return False
    changed = split_changed_cells(rel_path, id_col, copy_row, live_row)
    return not changed["approved"] and not set(changed["traced"]) & set(routed)


def _routed_unmoved(rel_path, id_col, before_row, live_row, routed):
    """Does the live row carry the routed traced cells it carried before the
    range? A row missing from either side has moved.

    Implements: SR-178, LLR-364"""
    if before_row is None or live_row is None:
        return False
    changed = split_changed_cells(rel_path, id_col, before_row, live_row)
    return not set(changed["traced"]) & set(routed)


def _tier_sides(root, base, head, rel_path, id_col):
    """`(sides, failure)`: one tier's `(copy at head, live at head, live at
    base)` row maps, or the snapshot copy's failure (`_snapshot_copy_rows`).

    Implements: SR-178, LLR-364"""
    copy, failure = _snapshot_copy_rows(root, head, rel_path, id_col)
    if failure:
        return None, failure
    live = _spine_rows_at(root, head + ":", rel_path, id_col)
    return (copy or {}, live, _spine_rows_at(root, base + ":", rel_path, id_col)), None


def _settled_row(added, rid, rel_path, id_col, sides, routed):
    """Is `rid` settled by the range-added ledger entries `added`, given its
    tier's `sides` (`_tier_sides`)? It needs an entry re-attesting it and its
    whole approved and routed traced cell set equal to its copy at the range's
    end. That copy is the re-attesting act's own when no later entry wrote the
    registry. A later writer re-attesting another row cannot have absorbed an
    approved-cell change to this one (the snapshot refuses to copy unattested
    approved drift), only a routed traced one, so a later writer still leaves
    it settled when its routed traced cells are the same at the range's two
    ends. That proves equality at the ends, not that no routed cell moved in
    between; its one limit: a routed traced cell moved before the re-attesting
    act and restored after it is re-anchored by the later copy, as any traced
    refresh is, and the row settles.

    Implements: SR-178, LLR-364"""
    mark = _latest_reattest(added, rid)
    copy, live, before = sides
    if mark is None or not _row_settled(
        rel_path, id_col, copy.get(rid), live.get(rid), routed
    ):
        return False
    return _no_later_writer(added[mark + 1 :], rel_path) or _routed_unmoved(
        rel_path, id_col, before.get(rid), live.get(rid), routed
    )


def settled_amendments(root, base, head, records, routed_cells):
    """`(settled ids, refusal)`: which amendment `records` the range
    `base..head` already settled. A record is settled when a ledger entry the
    range added re-attests its row, the row's whole approved and routed traced
    cell set at `head` equals its snapshot copy at `head`, AND either no entry
    the range added after the latest such one wrote (or, a legacy entry, may
    have written) the row's registry, or the row's routed traced cells are the
    same at the range's two ends, `base` and `head` (`_settled_row`). That
    second arm's one limit: a routed traced cell moved before the re-attesting
    act and restored after it is re-anchored by a later act's copy of the
    registry, and the row settles. The test reads what each act
    copied, so it holds on a squashed range whose one commit carries every
    act. The whole row, not the net diff's cells, so a cell edited after the
    act and then restored still differs. `routed_cells` is the caller's
    routing rule, keyed by registry. With no records nothing is read. A
    ledger or copy the tree lists but that cannot be read or does not parse
    is the refusal, naming the carrier, revision and which; a missing copy or
    row is unsettled, so it mints.

    Implements: SR-178, LLR-364"""
    if not records:
        return frozenset(), None
    added, refusal = _reattested_added(root, base, head)
    if refusal:
        return frozenset(), refusal
    routed = {spine_carrier.stem(k): v for k, v in routed_cells.items()}
    settled, tiers = set(), {}
    for rid in sorted({rec["id"] for rec in records}):
        rel, col = _tier_of(rid)
        if rel is None or _latest_reattest(added, rid) is None:
            continue
        if rel + col not in tiers:
            tiers[rel + col], refusal = _tier_sides(root, base, head, rel, col)
            if refusal:
                return frozenset(), refusal
        stem = spine_carrier.stem(rel)
        if _settled_row(added, rid, rel, col, tiers[rel + col], routed.get(stem, ())):
            settled.add(rid)
    return frozenset(settled), None


def reattested_between(root, base, head):
    """`(ids, refusal)`: the row ids the act-ledger entries `head` added over
    `base` re-attested, or a refusal naming the ledger when either side does
    not parse. An entry is added when its `seq` is not in `base`'s ledger.

    Implements: SR-178, LLR-278"""
    before, after = _ledger_acts(root, base), _ledger_acts(root, head)
    if before is None or after is None:
        return frozenset(), (
            "the act ledger {}/{} does not parse at {}, so which rows this "
            "merge re-attests is unknowable; nothing was merged".format(
                SNAPSHOT_DIR, SNAPSHOT_ACTS, base if before is None else head
            )
        )
    return _reattested_ids(before, after), None


def _wrote_ledger(delta):
    """Did the approval delta write the act ledger? A re-attestation moves no
    cell, so the ledger entries are the only trace of one."""
    return any(line.endswith("/" + SNAPSHOT_ACTS) for line in delta[1])


def reattest_scope_refusal(acted, metas):
    """Refuse an adjudication's act re-attesting a row outside the `Adjudicates`
    scope of the amendment rows it claims — by name — or None.

    A re-attestation moves no cell, so the flips the first-approval arm
    judges cannot show it; the acted set (`lane_acted_set`) carries the rows
    the act-ledger entries this branch added re-attested. An amendment
    row's scope is the rows its verdict ruled, so re-anchoring any other row
    re-blesses text nobody judged. A lane claiming no amendment row has no
    re-attestation scope at all.

    Implements: SR-178, LLR-278"""
    scope = amendment_scope(metas)
    outside = sorted(set(acted["reattest"]) - scope)
    if not outside:
        return None
    return (
        "the adjudication's act re-attests rows OUTSIDE the `Adjudicates` scope "
        "of its amendment row(s) ({}); nothing was merged:\n{}\nRemedy: a "
        "re-attestation re-anchors text as judged, so it names only rows the "
        "amendment ruled. Re-take the snapshot with `--reattests` naming those "
        "rows alone; a drifted row outside them is another act's to judge.".format(
            ";".join(sorted(scope)) or "none claimed",
            "\n".join("  {} re-attested OUTSIDE the scope".format(r) for r in outside),
        )
    )


# An amendment verdict's row rulings: the reader lives in `kitlib.verdict`
# (WI-841 round 5); the name stays here for its callers.
verdict_rulings = _kitverdict.verdict_rulings


def _tier_of(rid):
    """`(registry, id column)` of the amendment-walk tier row `rid` belongs to,
    read off its prefix, or `(None, None)`."""
    return next(
        ((r, col) for r, col in AMENDMENT_CSVS if rid.startswith(col[:-2])),
        (None, None),
    )


def _added_acts(root, base, head):
    """The act-ledger entries `head` adds over `base`, `[]` when either side
    does not parse (`reattest_scope_refusal` names that).

    Implements: SR-178, LLR-278"""
    before, after = _ledger_acts(root, base), _ledger_acts(root, head)
    if before is None or after is None:
        return []
    return added_ledger_entries(after, [before])


def added_ledger_entries(entries, parents):
    """The act-ledger `entries` whose `seq` no ledger in `parents` holds: the
    ones a commit adds over its parents (each parent a list of entries, `[]`
    where it has no ledger). Compared by number, never by content, so a second
    act identical to the first is still an act of its own; an entry that is
    not a table is skipped on every side. The one reading of "the entries a
    commit adds", shared by the acceptance record's readers and the snapshot's
    commit rule and accepted-risk anchor.

    Implements: SR-178, LLR-278"""
    held = {a.get("seq") for parent in parents for a in parent if isinstance(a, dict)}
    return [a for a in entries if isinstance(a, dict) and a.get("seq") not in held]


def lane_approval_refusal(root, base, head, delta=None, reason=None):
    """Why a lane's delta may not merge because it performs an APPROVAL ACT no
    verdict was asked to back - the refusal text, or None when it performs no
    act and writes no record. The merge slot words both refusals here: a record
    written with no act behind it, and acts `backed_act_refusal` found unbacked,
    its `reason` appended.

    THE ACT IS AN INDEPENDENT ADJUDICATOR'S, IN THE AUTHORING LANE OR ON TRUNK
    (owner ruling 6, 2026-10-07, superseding the trunk-side clause of the
    2026-09-01 ruling). A lane AUTHORS `Drafted` SN/SR/LLR/TC rows and AMENDS
    cell text on any such row, including approved ones; its acts - a `Status`
    flipped into `Approved`/`Founded`, a row minted already claiming one, a
    re-attestation - merge only when `backed_act_refusal` finds each backed by
    an accepted verdict that judged its own rows. A copy under `SNAPSHOT_DIR`
    with no flip and no re-attestation behind it is an act no verdict can
    back, and this is its refusal. The off-spine three
    (`OUTSIDE_THE_APPROVAL_ACT`) stay outside this rung - their approval cells
    are OI-30 D3's.

    HERE RATHER THAN IN THE MERGE SLOT, on `LLR-178`'s separation - the writer
    must not also be the judge of its own writes, and by the same token the
    coordinator that merges is not the reader that decides what a spine delta
    did. `integrate._approval_act_refusal` supplies the merge base and the rung's
    place in the ladder; the reading and the wording are this module's, beside
    the two-tree walk and the mirror rules they share their material with.

    A DE-APPROVAL IS NOT AN ACT, and neither is an amendment to an approved row:
    the lane may make both, and the amendment adjudication the intake mints at
    this same merge is what judges the second. THE HONEST BOUND is
    `integrate._minted_id_refusal`'s: this defeats the accident and a lane that
    drifts, not a lane that means to - a branch could still write a flip through
    some file nothing here reads.

    Fails closed on an unreadable snapshot delta: an unread diff is not an
    empty one. `staged_approval_acts`' own degrade is the opposite direction
    (silence outside a git checkout) and is deliberate - it is a READER, and the
    refusal that consumes it is where the fail-closed posture belongs.

    Implements: SR-178, LLR-158
    """
    acts, snapshot_files, refusal = delta or approval_delta(root, base, head)
    if refusal or not (acts or snapshot_files):
        return refusal
    lines = [
        "  {} {} in {}".format(
            act["id"],
            "flipped {} -> {}".format(act["before"] or "(absent)", act["after"])
            if act["act"] == "flip"
            else "was minted born {}".format(act["after"]),
            act["registry"],
        )
        for act in acts
    ] + ["  {}".format(name) for name in snapshot_files]
    return (
        "{} performs an APPROVAL ACT no accepted verdict backs. The act is an "
        "independent adjudicator's, never the session's that authored the rows, "
        "in the authoring lane or on trunk (owner ruling 6, 2026-10-07; "
        "PROCESS.md §4): that session leaves SN/SR/LLR/TC, assumption and "
        "surrogate rows `Drafted` and does not write {}/. Leave the rows "
        "`Drafted` for the first-approval adjudication minted at this merge, "
        "or back each act with an adjudicator's accepted verdict over its rows. "
        "Nothing was merged:\n{}\n{}".format(
            head, SNAPSHOT_DIR, "\n".join(lines), reason or ""
        )
    ).rstrip()


def staged_drafted_rows(root, base="HEAD", head=None):
    """Every `Drafted` spine row a delta ADDS or AMENDS between two trees:

        [{"registry": <carrier path>, "id": <row id>, "act": "added" | "amended",
          "changed": {cell: (before, after)}}]

    The first-approval trigger's input (WI-572): a lane authors `Drafted` rows
    and amends their text, and what it hands the adjudicator is exactly this set
    — the rows whose text is now waiting on a first approval nobody has given.
    `changed` is empty on an `added` row (there is no before side to diff) and
    carries BOTH §A5.1 halves on an `amended` one, because below approval the
    split buys nothing: no cell of a `Drafted` row was ever blessed, so none of
    them is "traced-only" relative to a signature.

    A row that is `Drafted` on the after side only. A row that LEFT `Drafted`
    is an approval act (`staged_approval_acts`); every row that ENTERED it is
    reported here as `amended`, even when only Status moved. The withdrawal
    itself still blesses nothing and remains absent from `staged_approval_acts`,
    but the resulting Drafted row now awaits the adjudicator's approval just as
    an authored Drafted row does.

    Returns [] when not applicable; silent no-op on missing git context."""
    out = []
    for registry, id_col, before_rows, after_rows, csv_path in _spine_row_sides(
        root, base, head
    ):
        for rid, row in after_rows.items():
            if not rid or not _kitspine.is_drafted(row):
                continue
            before = before_rows.get(rid)
            if before is None:
                out.append(
                    {"registry": registry, "id": rid, "act": "added", "changed": {}}
                )
                continue
            split = split_changed_cells(csv_path, id_col, before, row)
            changed = dict(split["approved"])
            changed.update(split["traced"])
            entered_drafted = not _kitspine.is_drafted(before)
            if changed or entered_drafted:
                out.append(
                    {
                        "registry": registry,
                        "id": rid,
                        "act": "amended",
                        "changed": changed,
                    }
                )
    return out


def staged_spine_amendments(root, base="HEAD", head=None):
    """The structured amendment set behind the amend-without-flip warn (WI-316,
    narrowed by WI-380) — the seam adjudication (WI-388) consumes.

    One record per APPROVED-TEXT spine row (`_APPROVED_TEXT` — `Approved`, into
    which `Verified` and `Planned` both folded at D-9 step 5) amended between the
    two trees without its status moving, each cell sorted into the §A5.1 halves with its before/after:

        {"registry": <csv path>, "id": <row id>,
         "approved": {cell: (before, after)}, "traced": {cell: (before, after)}}

    WHICH TWO TREES is a parameter, and WI-388 needs it to be: `head=None` (the
    default) compares the INDEX against `base`, which is the hook's `--staged`
    question, but §A5.2 mints adjudication from a **trunk commit**, and a commit
    is not the index — `staged_spine_amendments(root, "HEAD~1", "HEAD")` asks
    the post-commit question the dispatcher actually has to ask. Both arms are
    tested.

    A record may carry a traced change with NO approved change. Only the
    `SN-Refs`/`Verifies`/`SR-Refs` subset of those is the WI-388 case (§A5.1
    routes a re-point of what a requirement answers to, what a test claims to
    cover, or which SR owns an LLR — the last ruled traced at WI-388 — to
    adjudication); a `Module`/`CodeSymbol`/`TestRefs`/`Component`/`Phase`
    change is simply silent — traced, not pending, nothing owed. Rows are parsed
    with the csv module over the full file text on each side (spine cells are
    long; never line-split). Returns [] when not applicable; any missing git
    context is a silent no-op, like staged_findings. A NEW row (id absent on the
    base side) is not an amendment; a row whose Status moved (to `Drafted`,
    `Founded`, anything) made a deliberate call this does not
    second-guess — `staged_approval_acts` is the reader for the half of that
    exemption which BLESSES text, over the same walk.

    THE TWO-TREE WALK IS `_spine_row_sides`, shared since WI-572 rather than
    inlined here, so this reader and the two approval-act readers above it
    cannot disagree about which registries and rows the delta contains. Its
    universe is `AMENDMENT_CSVS` since WI-791 (OI-100 gap 1): the need,
    assumption and surrogate tiers join the three spine tiers."""
    # Each row answers for its OWN cells (owner ruling 2026-08-17m): the
    # sanctioned amend path is flipping the AMENDED row itself in the same
    # commit — a Status that moved is exempted below. The retired chain
    # reading's owning-SR exemption (a parent flip sanctioning a silent
    # child amendment) is gone with the doctrine: a child whose approved
    # cells change while its own Status still claims approval warns,
    # whatever its parent does.

    out = []
    for registry, id_col, head_rows, staged_rows, csv_path in _spine_row_sides(
        root, base, head, AMENDMENT_CSVS
    ):
        if not head_rows or not staged_rows:
            continue  # first commit / newly added registry — nothing attested yet
        for rid, row in staged_rows.items():
            changed = _amended_cells(csv_path, id_col, rid, head_rows.get(rid), row)
            if changed:
                out.append(dict(changed, registry=registry, id=rid))
    return out


def _amended_cells(csv_path, id_col, rid, head, row):
    """One row's `split_changed_cells` when it is an AMENDMENT — present on
    both sides, reading the same approved-text Status on both, with a cell
    moved — else None. `staged_spine_amendments`' per-row judgement, extracted
    unchanged at WI-791 to keep the walk under the complexity bar."""
    if not rid or rid.endswith("-000") or head is None:
        return None
    head_status = (head.get("Status") or "").strip().lower()
    cur_status = (row.get("Status") or "").strip().lower()
    # APPROVED-TEXT STATES, both sides, and the SAME one. Since D-9
    # step 5 that is the single value `Approved`; before the fold it was
    # `Verified` OR `Planned`, and requiring the SAME one on both sides
    # is what kept a legitimate rung move from reading as an amendment.
    # A status that MOVED between the two sides is still exempt,
    # unchanged: that is a deliberate call this does not second-guess.
    if head_status != cur_status or head_status not in _APPROVED_TEXT:
        return None
    changed = split_changed_cells(csv_path, id_col, head, row)
    return changed if changed["approved"] or changed["traced"] else None


def staged_spine_findings(root):
    """The amend-without-flip warn (WI-316; warn-first, `--staged` only), scoped
    by WI-380 to APPROVED cells only.

    A staged diff that changes the approved cells of a spine row whose Status
    reads the same approved-text value (`Approved`, since D-9 step 5) in both
    HEAD and the stage has amended attested prose without re-blessing it — the
    write-time discipline the old RE-ATTESTATION-PENDING commit-message prose
    never had. One warning per amended row, naming the changed cells. A row
    whose only changes are TRACED (§A5.1) is silent here by ruling; it still
    appears in `staged_spine_amendments`, which is where WI-388 picks it up.
    Index-vs-HEAD by construction — this is the hook's question, so it takes no
    rev arguments; the post-commit view is `staged_spine_amendments`'s."""
    return [
        "{}: approved cell(s) {} amended while Status stays put — a "
        "post-attestation amendment owes a fresh human read (process.md §7). "
        "Since D-9 step 7 there is no marker to set: either commit the amendment "
        "on its own and re-attest it in the NEXT commit with `intake.py "
        "snapshot --reattests {}` (text first, the act second: a commit that "
        "writes the record changes no other spine cell), or the change rides "
        "as SNAPSHOT DRIFT until the next sitting — "
        "visible on the re-attest brief and open-items.html, but not "
        "blessed".format(a["id"], ", ".join(sorted(a["approved"])), a["id"])
        for a in staged_spine_amendments(root)
        if a["approved"]
    ]


# The perspective cell the arm below watches. ONE NAME, stated once: the column
# is `Hat-Refs` at both tiers that carry it (WI-484 phase 0's ruling), and the
# arm reads `traced_cells` rather than this constant to decide WHICH tiers those
# are, so adding the column to a third registry extends the guard with it.
HAT_REFS_CELL = "Hat-Refs"


def staged_hat_refs_findings(root):
    """THE AMEND-WITHOUT-FLIP GUARD'S SECOND ARM (OI-32 phase 5, OI-33's
    surviving residue) — warn-first, `--staged` only, never an exit code.

    A row whose APPROVED cells moved while its `Hat-Refs` cell did not has been
    amended without re-examining which perspectives bear on it. The component
    view is DERIVED from these cells (OI-32 ruled (d)), and a derived view is
    only as true as its rows: a generated artifact can be perfectly FRESH and
    still carry a wrong answer, because freshness compares the artifact to its
    regeneration and never asks whether the source was right. This is the one
    thing generation cannot do.

    THE COMPARISON IS BY CELL CLASS, NOT BY FILE OR LINE, and that is the whole
    design. The measured instance is `backlog_staleness_findings`, which blames
    the SR registry by LINE: the phase-2 backfill wrote an INFORMATIVE cell on
    55 rows, re-dated five open WIs' cited rows and raised seven warns, because
    a `git blame` line time cannot tell an approved cell from a traced one.
    `split_changed_cells` can, so this arm reads it — which is why `Hat-Refs`
    was CLASSIFIED traced at both tiers rather than left to the residual.

    THE BASELINE IS THE ONE THE GUARD IT JOINS ALREADY USES: HEAD versus the
    index, via `staged_spine_amendments`, over rows reading the same
    approved-text Status on both sides. Two consequences, both deliberate and
    both HONEST VACUITY rather than coverage:

      * A row with NO baseline is not guarded. A row absent from HEAD (newly
        minted, this commit) has nothing to compare, and a row below approval
        has blessed nothing to amend behind a human's back — the same population
        rule `staged_spine_amendments` documents, inherited rather than
        re-litigated here.
      * A TIER with no `Hat-Refs` column is silent structurally (the TC tier
        today), not by an allowlist.

    NOT THE `last_approved` SNAPSHOT, and the trade is worth recording: that
    baseline would make the finding STAND until answered, where this one is a
    single warn at the commit that earns it. It was declined on OI-33's own
    timing argument — the party who knows whether the perspectives moved is the
    one making the change, at the moment they make it — and on the ruling's
    words, "same shape, same home, warn-first". The standing half of the same
    question is already carried for APPROVED cells by snapshot drift; if this
    warn is measured to be ignored, promoting it to a drift-tier finding is the
    next rung, on evidence.

    AN EMPTY `Hat-Refs` CELL STILL FIRES. A cell that was never filled and a
    cell deliberately left empty (`SR-015`, `SR-040` — both argued and correct)
    are indistinguishable to a reader, and the guard's question is whether the
    set was RE-EXAMINED, which an unchanged empty cell does not answer.

    Implements: SR-161, LLR-202
    """
    return [
        "{}: approved cell(s) {} amended while {} stayed put — the row's "
        "substance moved and its perspective record did not, so the derived "
        "component/knowledge view keeps answering from the old lenses "
        "(process.md §7; OI-32 phase 5). Re-read the row's hats and either "
        "update {} in this commit or leave it deliberately — an unchanged cell "
        "cannot say which".format(
            a["id"], ", ".join(sorted(a["approved"])), HAT_REFS_CELL, HAT_REFS_CELL
        )
        for a in staged_spine_amendments(root)
        if a["approved"]
        and HAT_REFS_CELL in traced_cells(a["registry"])
        and HAT_REFS_CELL not in a["traced"]
    ]


# The `last_approved` snapshot's root, repo-relative. RESTATED rather than
# imported from `baseline_snapshot`: the import edge runs the other way (that
# module reads `split_changed_cells` from here), and a back-import would make
# the pair un-loadable. One string, pinned equal by
# tests/test_baseline_snapshot.py — the F5 plumbing-duplication sanction, with
# the behavioural pin the D-7 ruling requires.
SNAPSHOT_DIR = "docs/archive/last_approved"

# The snapshot's prose stamp: rendered for a human, PARSED BY NOTHING, and with
# no live counterpart to mirror.
SNAPSHOT_README = "README.md"

# The snapshot's act ledger (`baseline_snapshot.ACTS`, restated for the reason
# the directory is, and pinned equal by tests/test_baseline_snapshot.py): the
# typed record of each approval act, and like the README a file with no live
# counterpart. These two are the snapshot's own files; every other file under
# the root is a registry copy the mirror rules compare with live.
SNAPSHOT_ACTS = "acts.toml"
SNAPSHOT_OWN_FILES = frozenset({SNAPSHOT_README, SNAPSHOT_ACTS})


def _snapshot_survives(root, new_rev):
    """True when ANYTHING at all remains under the snapshot root in the new tree.

    The two arms are the two things `new_rev` can be (`_spine_revs`' contract):
    `":"` is the INDEX, which `ls-files --cached` reads and where a staged
    deletion has already removed the entry; anything else is `"<rev>:"`, whose
    tree `ls-tree -r` reads. Degrades to False on any git failure, which is the
    quiet direction — an unanswerable question must not manufacture a finding.

    Implements: SR-179, LLR-178
    """
    if new_rev == ":":
        out = _git(root, ["ls-files", "--cached", "--", SNAPSHOT_DIR])
    else:
        out = _git(
            root, ["ls-tree", "-r", "--name-only", new_rev[:-1], "--", SNAPSHOT_DIR]
        )
    return bool(out and out.strip())


def _mirror_repair(live_rel):
    """The repair a snapshot-mirror finding prescribes, for the registry whose
    copy diverged.

    A bare `intake.py snapshot` is no repair here: it copies only a registry
    the act authorises, so with no `Status` move it copies nothing, and it
    refuses any approved row whose text differs from the recorded copy unless
    `--reattests` names it. So the finding names the two repairs that work:
    put the blessed copy back, or take a fresh act whose arguments carry the
    authority for this registry and name the rows it re-attests. The
    `--approves` token is the registry's STEM: `baseline_snapshot.
    resolve_registry` takes a canonical rel, filename or stem, and a CSV
    carrier's live path is none of those, so the path itself would refuse."""
    return (
        "Repair: restore the copy that was blessed, or take a fresh reviewed "
        'approval act that re-copies it — `intake.py snapshot --approves "{}=<REF>" '
        "--reattests <ROW-ID>[,<ROW-ID>...]`, naming each approved row whose "
        "text differs from the copy; a bare `intake.py snapshot` copies nothing "
        "here or refuses the drift".format(PurePosixPath(live_rel).stem)
    )


def staged_snapshot_findings(root, base="HEAD", head=None):
    """THE MIRROR INVARIANT (snapshot design §F3), as warn strings.

    > In any commit that touches a file under `docs/archive/last_approved/`,
    > that file must be byte-identical to its live counterpart in that same
    > commit.

    The snapshot is the record of what a human blessed, and it is just files —
    nothing about a text file stops someone editing it. This is the guard, and
    it is exact rather than heuristic: a legitimate `copy_live` satisfies it
    ALWAYS, by construction, because the copy is byte-for-byte and rides the
    same commit as the write. FOUR failures fail it — a hand edit (snapshot
    differs from live), a partial copy (one file mirrored, its sibling not), a
    copy-then-amend-live (the copy landed but the live file moved on before the
    commit closed), and a partial DELETION (one registry removed from the record
    while the rest of it stands — added at adversarial round 2, 2026-08-15,
    which found the deletion path exiting silently and so left as an erasure the
    invariant did not watch).

    The consequence worth stating plainly: **the only way to write text into
    the snapshot is to write it into the live registry first** — an approval,
    in a reviewed commit, exactly as ruled.

    Index-vs-HEAD by default (the hook's question); `head` takes a commit-ish
    for the post-commit view, matching `staged_spine_amendments`' shape. Silent
    no-op when git cannot answer or no snapshot file moved — the same degrade
    every other scan here takes.

    **TWO SEVERITIES SINCE D-9 MIGRATION STEP 7, which is what the design asked
    for** (§F3 risk 3: *"warn at the staged hook, ERROR on the integrity
    floor"*). This producer is unchanged and returns plain strings; the
    `--staged` loop below still prints them as warns, AND `trace.py` appends
    them to `findings.integrity`, so they fail `--strict-integrity` — the
    always-on floor the pre-commit hook runs at every gate. The staged warn is
    kept rather than replaced because it is the EARLIER of the two reads: it
    names the file while the author is still in the commit, where the fix is one
    `intake.py snapshot` away. The pre-commit hook invokes the staged pass with
    `|| true`, so the warn alone never blocked anything — which is exactly why
    the arming had to add a second severity rather than raise this one.

    Implements: SR-179, LLR-178
    """
    revs = _spine_revs(root, base, head)
    if revs is None:
        return []
    staged_names, _old_rev, new_rev = revs
    prefix = SNAPSHOT_DIR + "/"
    out = []
    for name in sorted(n for n in staged_names if n.startswith(prefix)):
        live_rel = name[len(prefix) :]
        # The README is PROSE (design §F8) — a stamp for a human, parsed by
        # nothing — and the act ledger is the snapshot's own record of its
        # acts; neither has a live counterpart to mirror. Excluding them by
        # name rather than by "no counterpart exists" keeps a genuinely missing
        # registry loud.
        if live_rel in SNAPSHOT_OWN_FILES:
            continue
        snap_text = _git(root, ["show", new_rev + name])
        live_text = _git(root, ["show", new_rev + live_rel])
        if snap_text is None:
            # DELETED from the snapshot in this commit. Silent ONLY when the
            # whole record went with it — retiring the mechanism, or the
            # wholesale replacement §A1 describes, are both legitimate and
            # neither leaves a hole. A single registry deleted while the rest of
            # the record stands IS a hole, and it is the cheapest possible
            # laundering: `unanchored_findings` reports a row whose copy reads
            # below it, so removing the copy outright removed the evidence
            # instead. (Adversarial round 2, 2026-08-15.)
            if _snapshot_survives(root, new_rev):
                out.append(
                    "{} was DELETED from the {} snapshot while the rest of the "
                    "record still stands — a registry removed from the record of "
                    "what was approved is not a smaller record, it is a missing "
                    "one; the snapshot is replaced WHOLESALE at a signing, never "
                    "trimmed a file at a time".format(name, SNAPSHOT_DIR)
                )
            continue
        if live_text is None:
            out.append(
                "{} is in the {} snapshot but {} does not exist in this commit — "
                "a snapshot file with no live counterpart is a record of text "
                "the repo no longer has".format(name, SNAPSHOT_DIR, live_rel)
            )
        elif snap_text != live_text:
            out.append(
                "{} is NOT byte-identical to {} in this commit — the snapshot is "
                "the record of what a human blessed, so it may only ever be "
                "written by copying the live file (`intake.py snapshot`). A hand "
                "edit, a partial copy and a copy-then-amend-live all land "
                "here. {}".format(name, live_rel, _mirror_repair(live_rel))
            )
    return out


def _snapshot_write_revs(root):
    """`{snapshot path: the rev that last wrote it}` over the COMMITTED history,
    or None when git cannot answer.

    One `git log --name-only` over the snapshot root answers for every file at
    once: history is walked newest-first, so the FIRST commit that names a path
    is the one that last wrote it. `--no-renames` for the reason `_spine_revs`
    gives — a moved registry must show up under its old path too."""
    log = _git(
        root,
        ["log", "--format=%x01%H", "--name-only", "--no-renames", "--", SNAPSHOT_DIR],
    )
    if log is None:
        return None
    out, rev = {}, None
    for line in log.splitlines():
        if line.startswith("\x01"):
            rev = line[1:].strip()
            continue
        name = line.strip()
        if name and rev and name not in out:
            out[name] = rev
    return out


def committed_snapshot_findings(root):
    """THE MIRROR INVARIANT OVER THE COMMITTED TREE — the half `staged_snapshot_
    findings` cannot reach (adversarial round, 2026-08-20: ROUND-OPUS CRITICAL-3
    / ROUND-SOL MAJOR-2).

    The staged rule is keyed on a snapshot file being IN THE COMMIT. That makes
    it exact and cheap, and it makes its blind spot exact too: once a forged or
    stale copy has LANDED — hooks bypassed, or a commit made outside them — no
    later run stages a snapshot file, so nothing ever looks at it again. The
    divergence is silent forever, which is the opposite of what a record of what
    a human blessed is for.

    So this asks the same question of history rather than of the index: for every
    file under the snapshot root, **was it a copy of its live counterpart at the
    commit that last wrote it?** That framing is what makes the rule safe to run
    ALWAYS, and the alternative shape — comparing the snapshot to live in the
    WORKING TREE — is the one to refuse: the snapshot is deliberately behind live
    while an amendment is pending, and that lag IS the signal (see
    `baseline_snapshot`'s header). A rule that redded every pending amendment
    would be switched off within a day. Here, live moving on afterwards changes
    nothing: the comparison is pinned to the snapshot's own writing commit, so a
    legitimate copy stays green forever and a forgery stays red forever.

    Blob-identity via `git cat-file --batch-check` rather than two `git show`s
    per file: git names identical content with the identical object id, so
    comparing object ids IS the byte comparison, at two subprocesses total.

    Degrades to `[]` off git, on any git failure, and for an untracked snapshot
    (a scaffold that has committed nothing has no committed state to judge)."""
    revs = _snapshot_write_revs(root)
    if not revs:
        return []
    prefix = SNAPSHOT_DIR + "/"
    pairs, specs = [], []
    for name, rev in sorted(revs.items()):
        if not name.startswith(prefix):
            continue
        live_rel = name[len(prefix) :]
        # The README and the act ledger have no live counterpart, exactly as in
        # the staged rule — excluded by name so a genuinely missing registry
        # stays loud.
        if live_rel in SNAPSHOT_OWN_FILES:
            continue
        pairs.append((name, live_rel, rev))
        specs += ["{}:{}".format(rev, name), "{}:{}".format(rev, live_rel)]
    if not pairs:
        return []
    batch = _git(
        root, ["cat-file", "--batch-check=%(objectname)"], stdin="\n".join(specs) + "\n"
    )
    if batch is None:
        return []
    ids = batch.splitlines()
    if len(ids) != len(specs):
        return []  # unparseable batch: an unanswerable question makes no finding
    out = []
    for i, (name, live_rel, rev) in enumerate(pairs):
        snap_id, live_id = ids[2 * i].strip(), ids[2 * i + 1].strip()
        if snap_id.endswith("missing"):
            # The commit that last named this path DELETED it. That is the
            # staged rule's subject (a partial deletion is caught in the commit
            # that does it) and not a mirror question — there is no copy left to
            # compare.
            continue
        if live_id.endswith("missing"):
            out.append(
                "{} was written into the {} snapshot at {} where {} did not "
                "exist — a snapshot file with no live counterpart in its own "
                "writing commit is a record of text the repo never had".format(
                    name, SNAPSHOT_DIR, rev[:8], live_rel
                )
            )
        elif snap_id != live_id:
            out.append(
                "{} is NOT byte-identical to {} at {}, the commit that last "
                "wrote it — the snapshot is the record of what a human blessed, "
                "so it may only ever be written by copying the live file "
                "(`intake.py snapshot`). This divergence has LANDED. {}".format(
                    name, live_rel, rev[:8], _mirror_repair(live_rel)
                )
            )
    return out


def _empty_tree(root):
    """The empty tree's id in this repository's hash, or None off git — what a
    ROOT commit is compared with."""
    out = _git(root, ["hash-object", "-t", "tree", "--stdin"], stdin="")
    return out.strip() if out and out.strip() else None


# --- THE RULING SYNC: a ruling updates the rows that cite it (WI-790) ---------
# OI-102 Q3, ruled 2026-10-03: a commit-time block over ONE diff, a commit
# against its own parent, with no history walk and no second path. The
# trigger is the registry state (a row going from `pending` to anything else,
# a deleted pending row included), never page membership; the citing set is
# read from the PARENT tree, so dropping the `needs` token in the ruling's own
# commit discharges nothing. Every terminal state discharges the obligation —
# a closed row has no criteria left to update — because a terminal row lives
# under the archive, so a row the commit moved there or removed is satisfied.
OPEN_ITEMS_REGISTRY = "docs/requirements/open-items.toml"
WORK_DIR = "docs/work"
ARCHIVE_WORK_DIR = "docs/archive/work"
_PENDING = "pending"


# The ruling sync's two git reads, homed in `kitlib.git` (WI-818): every
# path list read NUL-delimited, and a blob read that refuses a listed path
# whose blob cannot be read rather than reading it as absent.
_git_paths = _kitgit.git_paths
_show = _kitgit.git_show


def _tree_specs(root, rev):
    """`{WI id: path}` of every spec in a tree (`rev` None is the index), or
    None when git cannot list it: a view over `kitlib.registry`'s one
    work-spec listing, the id being the file name's first two dash fields. A
    `-000` example is never a row, and of two paths carrying one id the later
    listed wins.

    Implements: SR-148, LLR-298
    """
    paths = _kitregistry.tree_spec_paths(root, rev)
    if paths is None:
        return None
    specs = {}
    for path in paths:
        wid = "-".join(path.rsplit("/", 1)[-1].split("-")[:2])
        if not wid.endswith("-000"):
            specs[wid] = path
    return specs


def _registry_states(root, prefix):
    """`{OI id: status}` of the open-items registry in ONE tree (`prefix` a
    `git show` prefix), read through whichever carrier that tree uses (TOML,
    else CSV — `spine_carrier`'s resolution, as `_spine_rows_at` reads a spine
    registry): `{}` when the tree has neither, None when it does not parse.
    `-000` example rows are dropped.

    Implements: SR-148, LLR-298
    """
    for cand in _spine_carriers(OPEN_ITEMS_REGISTRY):
        text = _show(root, prefix, cand)
        if text is None:
            continue
        rows = spine_carrier.rows_from_text(text, "OI-ID", "." + cand.rsplit(".", 1)[1])
        if rows is None:
            return None
        return {
            rid: (row.get("Status") or "").strip()
            for rid, row in rows.items()
            if not str(rid).endswith("-000")
        }
    return {}


def _ruled_items(before, after):
    """The open items `pending` in `before` and not in `after` (two
    `_registry_states` maps), or None when either side does not parse
    (unreadable is not unchanged).

    Implements: SR-148, LLR-298
    """
    if before is None or after is None:
        return None
    return sorted(
        oid
        for oid, state in before.items()
        if state.lower() == _PENDING and after.get(oid, "").lower() != _PENDING
    )


def _citing_rows(root, base, specs, ruled):
    """`[(WI id, [ruled OI ids it cites], spec text)]` for every row OPEN in
    the `base` tree (under `docs/work/`) whose `needs` cites a ruled item.

    Implements: SR-148, LLR-298
    """
    rows = []
    for wid, path in sorted(specs.items()):
        if not path.startswith(WORK_DIR + "/"):
            continue  # under the archive: terminal, nothing owed
        text = _show(root, base + ":", path)
        try:
            data, _body = _kitregistry.parse_spec_frontmatter(text or "", path)
        except ValueError:
            continue  # a malformed spec is the validator's finding, not this rule's
        needs = ";".join(str(t) for t in data.get("needs") or [])
        cited = [o for o in _kitspine.split_pred_edges(needs)[1] if o in ruled]
        if cited:
            rows.append((wid, cited, text))
    return rows


def _sync_gap(root, new_prefix, head_path, before_text):
    """Why one citing row is out of sync in the new tree, or None when it is
    satisfied: removed, closed (moved under the archive), or open with a
    non-empty Done-when section whose RAW text differs from the parent's (A1:
    read from the raw spec text; whether the change carries the ruling is the
    reviewer's judgement, not this rule's).

    Implements: SR-148, LLR-298
    """
    if head_path is None or not head_path.startswith(WORK_DIR + "/"):
        return None
    after = _raw_done_when(_show(root, new_prefix, head_path))
    if not after:
        return "it keeps no Done-when"
    if after == _raw_done_when(before_text):
        return "its Done-when is unchanged"
    return None


def _raw_done_when(text):
    """A spec's Done-when section as raw text, outer blank lines trimmed."""
    return "\n".join(_kitregistry.done_when_section(text or "")).strip()


def ruling_sync_lines(root, base, head=None):
    """One line per (row, item) the diff `base` -> `head` leaves out of sync
    (`head` None is the index): an open item leaves `pending` while a work item
    open in `base` cites it in `needs`, and the same diff neither updates that
    row's Done-when (non-empty afterwards, and its raw section changed) nor
    closes or removes the row. The registry is read through either carrier.
    `[]` when nothing leaves `pending`. A diff git cannot read is a line,
    never a skip. The diff's overrules are judged too
    (`kitlib.decisions.overrule_sync_lines`, reading both trees through `_show`).

    Implements: SR-148, LLR-298
    """
    args = ["diff", "--name-only", "--no-renames"]
    args += ["--cached", base] if head is None else [base, head]
    changed = _git_paths(root, args)
    if changed is None:
        return [
            "cannot read the diff against {}, so whether it rules an open item "
            "is unknown".format(base)
        ]
    try:
        lines = []
        if set(_spine_carriers(OPEN_ITEMS_REGISTRY)) & set(changed):
            lines = _judged_lines(root, base, head)
        new_prefix = ":" if head is None else head + ":"
        return lines + _kitdecisions.overrule_sync_lines(
            changed,
            lambda rel: _show(root, base + ":", rel),
            lambda rel: _show(root, new_prefix, rel),
        )
    except _kitgit.UnreadableBlob as exc:
        return [
            "{} is listed in its tree but its contents cannot be read, so whether "
            "this commit rules an open item or overrules a decision is unknown: "
            "fetch it (a partial clone offline or a damaged object store), or "
            "name it in UTF-8, and retry".format(exc)
        ]


def _judged_lines(root, base, head):
    """`ruling_sync_lines` once the diff touches the registry: the ruled items,
    then each citing row. Every blob it reads goes through `_show`.

    Implements: SR-148, LLR-298
    """
    new_prefix = ":" if head is None else head + ":"
    ruled = _ruled_items(
        _registry_states(root, base + ":"), _registry_states(root, new_prefix)
    )
    if ruled is None:
        return [
            "the open-items registry does not parse on one side of the diff, "
            "so whether it rules an open item is unknown"
        ]
    if not ruled:
        return []
    return _sync_lines(root, base, head, ruled)


def _sync_lines(root, base, head, ruled):
    """The per-row half of `ruling_sync_lines`, once the ruled items are known.

    Implements: SR-148, LLR-298
    """
    base_specs, head_specs = _tree_specs(root, base), _tree_specs(root, head)
    if base_specs is None or head_specs is None:
        return ["cannot list the work items on both sides of the diff"]
    new_prefix = ":" if head is None else head + ":"
    lines = []
    for wid, cited, text in _citing_rows(root, base, base_specs, ruled):
        gap = _sync_gap(root, new_prefix, head_specs.get(wid), text)
        if gap:
            lines.append(
                "{} cites {}, which this commit takes out of pending, and {}: "
                "the ruling's commit updates the row's Done-when with the decided "
                "criteria, citing the item, or closes or removes the row".format(
                    wid, ", ".join(cited), gap
                )
            )
    return lines


def staged_ruling_sync_lines(root):
    """`ruling_sync_lines` for the commit being made: the index against HEAD,
    or against the empty tree before the first commit (which closes nothing).

    Implements: SR-148, LLR-298
    """
    head = _git(root, ["rev-parse", "--verify", "--quiet", "HEAD"])
    base = head.strip() if head and head.strip() else _empty_tree(root)
    if base is None:
        return ["cannot read HEAD or the empty tree, so the commit is unjudged"]
    return ruling_sync_lines(root, base)


def commit_ruling_sync_lines(root, rev):
    """`ruling_sync_lines` for one commit against its FIRST parent, read off
    the commit object itself (not `rev^1`, which a shallow boundary hides). A
    true root commit — no parent in its object — has nothing to close and
    answers `[]`; a parent the repository cannot read (a shallow clone, a
    missing object) is refused by name, never read as a root (A1).

    Implements: SR-148, LLR-298
    """
    parents, unread = _commit_parents(root, rev, "it rules an open item", first=True)
    if unread or not parents:
        return unread
    return ruling_sync_lines(root, parents[0], rev)


# The parent-first rule's registries: the four spine tiers of the approval-act
# set (the need, requirement, design and test tiers), read by `_tree_tiers`.
PARENT_FIRST_CSVS = tuple(
    (path, col) for path, col in APPROVAL_ACT_CSVS if col in SPINE_TABLE
)


def _tree_tiers(root, prefix):
    """`({label: rows}, failures)` of the parent-first registries at the tree
    `prefix`: each tier from the first carrier the tree lists, an absent
    registry no rows, and one `"<path> cannot be read"` or `"<path> does not
    parse"` failure per registry that fails.

    Implements: SR-246, LLR-358"""
    tiers, failures = {}, []
    for path, col in PARENT_FIRST_CSVS:
        tiers[col[:-3]] = []
        for cand, rows, failure in _tier_reads(root, prefix, path, col):
            if failure:
                failures.append("{} {}".format(cand, failure))
            else:
                tiers[col[:-3]] = list(rows.values())
            break
    return tiers, failures


def _parent_first_names(root, base, head):
    """The parent-first carriers the tree `head` (the index when None) changes
    against `base`, or None when git cannot list them.

    Implements: SR-246, LLR-358"""
    watched = [c for path, col in PARENT_FIRST_CSVS for c in _tier_carriers(path, col)]
    side = [head] if head else ["--cached"]
    return _kitgit.git_paths(
        root, ["diff", "--name-only", "--no-renames", base, *side, "--", *watched]
    )


def _status_moved(entry, statuses):
    """Whether the child's or the parent's status in `entry` differs from that
    row's status in one parent tree's `statuses` (`{id: status}`, an absent
    row reading None); a parent tree that failed to read (None) moved all.

    Implements: SR-246, LLR-358"""
    child, child_status, parent, parent_status = entry
    side = statuses or {}
    moved = (side.get(child), side.get(parent)) != (child_status, parent_status)
    return statuses is None or moved


def _parent_statuses(root, base):
    """`{id: status}` of the parent-first tiers at `base`, or None when any of
    its registries cannot be read or does not parse.

    Implements: SR-246, LLR-358"""
    tiers, failures = _tree_tiers(root, base + ":")
    if failures:
        return None
    return {
        str(r.get(label + "-ID") or "").strip(): (r.get("Status") or "").strip()
        for label, rows in tiers.items()
        for r in rows
    }


def parent_first_lines(root, bases, head=None):
    """The parent-first refusal lines for the tree `head` (the index when
    None) against each tree of `bases`: one per approved child its tree leaves
    under an unapproved parent where either status moved against some base
    (`_status_moved`), or one per failed read. Not read further when no base
    sees a parent-first carrier change.

    Implements: SR-246, LLR-358"""
    tree = "the index" if head is None else "commit " + head[:10]
    touched = False
    for base in bases:
        names = _parent_first_names(root, base, head)
        if names is None:
            return [
                "{}: git cannot list what it changes against {}, so whether it "
                "leaves an approved row under an unapproved parent is "
                "unknown".format(tree, base[:10])
            ]
        touched = touched or bool(names)
    if not touched:
        return []
    tiers, failures = _tree_tiers(root, ":" if head is None else head + ":")
    if failures:
        return [
            "{}: {} in {}, so whether it leaves an approved row under an "
            "unapproved parent is unknown".format(tree, failure, tree)
            for failure in failures
        ]
    entries = _kitspine.parent_first_findings(tiers)
    sides = [_parent_statuses(root, base) for base in bases] if entries else []
    return [
        "{}: {}".format(tree, _kitspine.parent_first_line(entry))
        for entry in entries
        if any(_status_moved(entry, side) for side in sides)
    ]


def staged_parent_first_lines(root):
    """`parent_first_lines` for the commit being made: the index against HEAD,
    and against MERGE_HEAD during a merge. No HEAD yet judges nothing.

    Implements: SR-246, LLR-358"""
    shas = [
        _git(root, ["rev-parse", "--verify", "--quiet", ref + "^{commit}"])
        for ref in ("HEAD", "MERGE_HEAD")
    ]
    bases = [sha.strip() for sha in shas if sha and sha.strip()]
    return parent_first_lines(root, bases) if shas[0] and shas[0].strip() else []


def commit_parent_first_lines(root, rev):
    """`parent_first_lines` for one lane commit against every parent of its
    commit object; a root commit is not judged, and a parent the repository
    cannot read is `_commit_parents`' line.

    Implements: SR-246, LLR-358"""
    parents, unread = _commit_parents(
        root, rev, "it leaves an approved row under an unapproved parent"
    )
    if unread or not parents:
        return unread
    return parent_first_lines(root, parents, rev)


def _commit_parents(root, rev, question, first=False):
    """`(parents, lines)` for one commit, read off the commit object itself
    (not `rev^1`, which a shallow boundary hides): its parents, or only the
    first when `first`, with `[]` lines when each is readable. A commit git
    cannot read, or a parent missing from the repository (a shallow clone, a
    missing object), is one line naming it and `question`, never read as a
    root (A1). A true root commit is `([], [])`. The one parent reader of the
    two per-commit rules the merge slot walks a lane with.

    Implements: SR-148, SR-140, LLR-298, LLR-302
    """
    body = _git(root, ["cat-file", "commit", rev])
    if body is None:
        return [], ["cannot read commit {}, so it is unjudged".format(rev)]
    head = body.split("\n\n", 1)[0].splitlines()
    parents = [line.split()[1] for line in head if line.startswith("parent ")]
    parents = parents[:1] if first else parents
    for parent in parents:
        if _git(root, ["cat-file", "-e", parent + "^{commit}"]) is None:
            return [], [
                "commit {}'s parent {} cannot be read in this repository (a "
                "shallow clone or a missing object), so whether {} is unknown; "
                "fetch the parent and retry".format(rev[:10], parent[:10], question)
            ]
    return parents, []
