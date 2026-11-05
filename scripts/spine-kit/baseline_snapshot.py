#!/usr/bin/env python3
"""baseline_snapshot.py — the `last_approved` snapshot: what the spine looked
like when a human last blessed it.

Stack-agnostic, standard-library only (Python 3.11+, Windows/POSIX).

WHY THIS EXISTS (owner directive 2026-08-15; design:
docs/plans/2026-08-15-baseline-snapshot-design.md). Every "has this attested row
changed?" question in the kit used to be answered by DERIVING a baseline from
git — `trace._attested_baseline` walked the registry's history for the newest
commit at which the row read `Verified` (now `Approved`). That derivation is correct only while
every amendment flips its row's Status in the same commit, and D-9 deletes the
flip: under the new ladder an approved row STAYS approved while its text is
amended, so the newest-approved revision is HEAD and the diff is empty BY
CONSTRUCTION. The brief would return a clean bill forever, at exit 0, on exactly
the rows a sitting exists to judge.

So the baseline moves OUT of git history and onto disk: when an approval lands,
the registries are COPIED, byte for byte, into `docs/archive/last_approved/`.
Every comparison — the adjudicator, the human re-attest read, the HTML
generators — diffs the live registries against that copy. No hashes, no anchor
columns, no commit-id walk. The baseline becomes something a human can open in
an editor and diff with `git diff`, which is itself an argument for the design.

THREE PROPERTIES DO THE WORK, and each is worth stating because each replaces a
piece of machinery that no longer needs to exist:

  1. **Whole files, never extracted rows.** The copy is byte-for-byte, so
     "snapshot file == live file at the copy commit" is a DECIDABLE property —
     `check_trajectory.staged_snapshot_findings` is the guard that makes a
     hand-edited or partial snapshot fail loudly. Row extraction would destroy
     that, would re-serialise TOML (normalising away comments and authored
     ordering, which is the whole reason `intake._flip_status_lines` exists),
     and would silently drop the normative prose that lives OUTSIDE the rows.
  2. **The snapshot keeps each row's own `Status` cell.** That is what makes
     the UNANCHORED rule decidable: a live row claiming approval whose snapshot
     copy reads *below* approval is an approval that never rode a copy — the
     precise laundering this mechanism exists to catch.
  3. **Vacuous by absence, never by silence.** No directory means "this repo
     has approved nothing yet", which is honest and free for a fresh adopter.
     But once the directory exists, a missing registry INSIDE it is an error,
     and a snapshot file that does not parse RAISES rather than reading as
     empty — `{}` and `None` are opposite claims, and the empty one means
     "re-bless everything with no diff shown".

REPO-RELATIVE PATHS ARE PRESERVED UNDER THE SNAPSHOT ROOT
(`<root>/docs/archive/last_approved/docs/requirements/...`). `spine_carrier`'s
`resolve`/`carriers`/`stem` all take a registry path, so `snapshot_root / rel`
reuses every existing resolver verbatim, carrier fallback included. Flattening
would need a second path vocabulary and would give the resolver nothing to
resolve.

WHY `docs/archive/` IS THE RIGHT HOME, despite "archive is design history, not
a working surface": the placement is ACTIVELY load-bearing.
`check_vocab.EXEMPT_GLOBS` exempts `docs/archive/*`, and the snapshot
legitimately holds the PREVIOUS vocabulary — so anywhere else would red the
vocabulary enforcer on every signing. `check_docs._in_archive` exempts it from
orphan/stale findings and `check_doc_refs.RECORD_PREFIXES` keeps its inherited
citations from dangling. `check_trajectory.ARCHIVE_SPECS_DIR` already reads
archive as live machinery input, so the class is not new.

STATUS OF THIS MODULE, 2026-08-20: LIVE AND ARMED. It shipped reader-first and
advisory (2026-08-15) with every function vacuous by absence; the owner's
signing act seeded `docs/archive/last_approved/` in the post-rename vocabulary
(migration step 6), and step 7 promoted `unanchored_findings` to an
INTEGRITY-class ERROR on the always-on `--strict-integrity` floor plus the
pre-commit hook. The order was the safety property, not ceremony: run against a
pre-seed snapshot (there was none) or a pre-rename one (it spoke the retired
vocabulary), this rule reds every row in the repo, and a check that reds
everything is a check that gets switched off. It stays VACUOUS BY ABSENCE for a
repo that has approved nothing, which is a fresh adopter's honest state.

VOCABULARY NOTE — THE TRANSITIONAL MAPPING IS GONE (D-9 step 5, 2026-08-15).
This module was written against `Approved` before the value existed, and read
the two pre-rename values that together carried the claim (`Verified` and
`Planned`). Step 5 renamed both into `Approved`, so the spine arm of
`_claims_approval` collapsed to the single value its own docstring promised —
deleted, not re-keyed. THE SKEW THIS LEAVES IS REAL AND IS THE DESIGN'S §B6
axis 3: a snapshot copied BEFORE the rename speaks the retired words and would
read as unanchored everywhere, which is why the snapshot is ONE GENERATION,
replaced wholesale at each signing and never migrated in place, and why the
first seed happens AFTER the rename (step 6) and the UNANCHORED rule is armed
only after that (step 7).

Contracts: IF-123, IF-124, IF-125, IF-126, IF-217, IF-220 — the seams this module
declares (process.md §8; rows of record in docs/requirements/interfaces.toml).

Contract IF-123: the `last_approved` baseline, write side and whole read side.
    `copy_live(root, seed=False, approves=None, reattests=None, verdict=None)`
    mirrors ONLY
    the registries an act authorises byte-for-byte into
    `docs/archive/last_approved/` — the seed copies the whole tree once, a
    refresh copies the registry a `Status` move happened in, every registry
    `approves` names and every registry holding a row `reattests` names, and
    leaves the rest byte-identical to what they were (WI-571: the whole-tree
    copy re-sealed off-spine drift on every spine-only approval). It deletes
    any other-carrier copy of the same stem for a registry it copies, and
    returns the sorted repo-relative paths written. It REFUSES to create the
    directory without `seed=True`, and refuses a refresh while any row of a
    registry it would copy has approved text drifted from its recorded copy (a
    recorded approved row deleted from live counts, as REMOVED) and is neither
    flipped by the act nor named in `reattests` — ROW BY ROW, so naming a
    registry in `approves` clears none of its rows — because the copy it takes
    is the text a signature blesses. That refusal judges THIS ACT'S
    WRITE SET and not the whole ledger, so an approval is not blocked by drift
    in a registry the copy leaves alone; an act whose write set is empty is
    judged over the whole ledger, so a refresh that would copy nothing in a
    drifted tree refuses rather than exiting 0 in silence. It lists every such
    row and cell, uncapped. `approves` is `{registry rel: ref}`
    (`parse_approves` builds it from a `REGISTRY=REF` CLI value) and `reattests`
    a set of row ids (`parse_reattests`, from comma-joined ids of the
    `SNAPSHOT_TIERS` tiers); `verdict` is the repo path of the verdict file
    that ruled the re-attested rows, refused without `reattests` or when no
    such file is in the tree. Before every copy, a seed included, an id naming
    neither a live row nor a recorded one is refused, and so is any id at all
    on a first signing, which copies the whole tree and writes no stamp. The
    refs and re-attested ids land in the snapshot's prose stamp, every act that
    copied a registry appends its entry to the act ledger (IF-220), and
    `act_summary` is the one line the CLI prints for the act. `load_all(root)`
    parses the snapshot into
    `{(stem, id column): {id: row}}`, returns None — never `{}` — when there is
    no snapshot, and RAISES on a file that exists and will not parse;
    `rows_for` is the ONE place that None collapses to `{}`. `exists`, `stamp`,
    `is_drifted`/`drifted_cells` over approved cells only, and
    `unanchored_findings` complete the read side. Nothing may wire `copy_live`
    into a freshness step: the snapshot is deliberately behind live while an
    amendment is pending, and that lag IS the signal.
Contract IF-124: the anchor read a composed brief takes — `exists`, `stamp` and
    `SNAPSHOT_DIR` — so an amendment is measured against text that is not the
    text under judgement. `exists` answers the vacuous case truthfully rather
    than conveniently: before the first signing there is no anchor at all, and
    the honest response is a held first-approval question, never a before/after
    rendered with an empty before. `stamp` is ADVISORY and derived from git; off
    a checkout it returns empty strings rather than raising, so a missing date
    costs a reader one line and nothing more. Named a registry, it answers for
    that registry's copy alone, because a refresh copies only what its act
    authorises and the directory's newest write is one copy's provenance, not
    every copy's.
Contract IF-125: the drift read — `load_all`, `rows_for`, `is_drifted` and
    `SNAPSHOT_DIR`, and never `copy_live`. Drift is asked only of a row that
    CLAIMS approval-or-above and is present in the snapshot; a row below
    approval answers False because it has made no claim to fall from, and a
    claiming row absent from the snapshot answers False because that is the
    harder unanchored finding, owned elsewhere. With no snapshot `load_all`
    returns None and `rows_for` collapses it to `{}`, so a reader reports
    nothing approved rather than everything drifted.
Contract IF-126: the stamp read — `registry_stamps(root)` and `SNAPSHOT_DIR` —
    and the needs read, `needs_owing(root)`: one `(id, why, cells, row)` per
    stakeholder need or stakeholder owing an act, the rows the owner page's
    approval and re-attestation section lists. The stamp lets a generated
    surface name WHICH baseline the reader is being shown and where it lives:
    each registry the record holds a committed copy of, with the commit that
    last wrote THAT copy, since a refresh copies only what its act authorises
    and the copies were written at different commits. Advisory and read-only in
    both directions: the stamp is derived from git and degrades to empty
    strings off a checkout, and this side never calls `copy_live`, because a
    generator that refreshed the baseline would erase the very lag it exists to
    report.
Contract IF-217: the accepted risk's anchor, read from history.
    `risk_acceptance_act(root, da_id)` returns `(commit, reason)`: the latest
    commit whose approval act names the assumption — an act ledger entry that
    commit added listing it approved or re-attested (IF-220) — while the
    record's copy of the row there carries a non-empty `accepted_risk`; where no act names the row at
    all, the first commit at which its live `accepted_risk` took its current
    value. `(None, reason)` when no anchor can be read: history too shallow
    (the repository is a shallow clone and the window holds no such act), acts
    naming the row with no risk recorded, a value in no commit yet, or no git.
    `risk_acceptance_view(root, da_id)` adds what the pure rule
    (`assumption_rules.accepted_risk_state`) compares, as a dict: `act`,
    `reason`, and at that commit the `assumption` row, the requirement rows
    `srs`, the `needs` keyed by id and the `known` observation record names.
    Read-only; no clock is read, and ancestry, not a timestamp, orders a record.
Contract IF-220: the act ledger, `ACTS` under `SNAPSHOT_DIR`. A TOML file of
    `[[act]]` entries, one appended by each `copy_live` that copied a registry
    (the seed included) and none by an act that copied nothing: `seq`, an
    integer one above the highest already present, so identical acts stay
    distinct; `date`, the ISO day; `approved`, the sorted ids of the compared
    tiers' rows the act carried into approval (a live row claiming approval
    whose prior recorded copy did not, or that the record did not hold), the
    needs file's need and stakeholder tiers among them (`NEED_TIERS`); and
    `reattested`, the sorted ids its `reattests` named; and, only when the act
    named one, `verdict`, the verdict file that ruled those rows — the record a
    held rung's CLARITY re-attestation carries (OI-100, WI-791); and `copied`,
    the sorted canonical `SNAPSHOTTED` paths of the registries the act
    actually wrote, so a traced re-anchor naming no row, a mixed act and a
    re-seed each name every file they copied. A copied file is no evidence
    that its rows were judged. An entry written before `copied` existed is a
    legacy entry: it parses unchanged, with no `copied` key, and its copy set
    is unknown, never empty, never inferred or backfilled. FAILS CLOSED:
    `acts_problems(text)` lists every fault (text that does not parse, a field
    missing or mistyped, an id not of the kit's syntax, a `verdict` that is
    not a non-empty string, a `copied` that is not a non-empty sorted list of
    distinct paths, an entry omitting `copied` after one that carries it,
    `seq` values not
    unique and increasing in file order), and `parse_acts(text)` returns the
    entries as dicts in file order, `[]` for no text, or raises
    `ActLedgerError` — it never returns the entries it could read.
    The commit is the boundary for the rest: `added_acts_problems(text,
    parent_texts)` judges only the entries a commit adds (their `seq` in no
    parent's ledger, against HEAD and MERGE_HEAD during a merge, as
    `added_acts_findings(root)` reads the index), which must carry `copied`
    naming only `SNAPSHOTTED` files. A malformed parent and a hand-edited
    ledger are outside the coverage bound (PROCESS.md §6): no supported route
    produces either.
    `read_acts(root)` reads the working tree's; `acts_findings(root)` reports
    its faults as integrity findings, which `record_findings(root)` joins to
    the unanchored ones and the added-entry ones for
    `trace.py --strict-integrity`; a
    snapshot act on a malformed ledger is refused before it moves any byte of
    the record, and `risk_acceptance_act` reads no anchor through one. The
    README beside it stays prose; nothing parses it.
"""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path

# Sibling imports, the sanctioned idiom (see trace.py): run as a subprocess this
# script's own dir is sys.path[0], and the guard covers an in-process import (a
# test) whose sys.path does not yet carry scripts/.
try:
    import acceptance_record
    import check_trajectory
    import spine_rules
    import spine_carrier
except ImportError:  # pragma: no cover - in-process fallback
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import acceptance_record
    import check_trajectory
    import spine_rules
    import spine_carrier

from kitlib import git as _kitgit
from kitlib.observation import OBSERVATIONS_DIR
from kitlib.spine import is_drafted, toml_fields

# The snapshot's root, repo-relative. One generation only, never migrated in
# place — git holds the history, and a snapshot edited forward would be a second
# ledger of what was blessed. SCOPED SINCE WI-571: the seed copies the whole
# tree once, and a refresh REPLACES ONLY the registries the act authorises (the
# registry a `Status` move happened in, every registry `approves` names and
# every registry holding a row `reattests` names), leaving a registry outside
# the act's scope untouched — see `copy_live`.
SNAPSHOT_DIR = "docs/archive/last_approved"

# The prose stamp's filename. Rendered for a human (design §F8, repo-lock
# D-10's tripwire) and parsed by nothing: every machine fact comes from the
# copied files, from the act ledger below, or from git, so this file can never
# quietly become a ledger a reader depends on.
README = "README.md"

# THE ACT LEDGER, beside the copies: one typed entry per approval act that
# copied a registry, naming the rows it carried into approval, the rows it
# re-attested and the registries it copied (`copied`, absent on a legacy entry
# written before it existed, whose copy set is unknown). Re-accepting a risk is
# re-attesting its row, and a re-attestation moves no cell a later reader could
# find in the copies, so the act has to say which rows it named somewhere a
# reader may parse (SR-202, LLR-239); and a traced re-anchor, a mixed act or a
# re-seed copies files its row lists never name, so it records those too
# (SR-178). Each entry carries its own sequence number, so two acts naming the
# same rows on the same day are two entries and the later one is never read as
# the earlier. Appended by `copy_live`; read by `risk_acceptance_act`, the
# acceptance record, the sitting rules and the open-items audit list. An entry
# a commit adds must carry `copied` (`added_acts_findings`). It mirrors no
# live file, so the mirror rules skip it by name
# (`acceptance_record.SNAPSHOT_ACTS`, pinned equal by the snapshot tests).
ACTS = "acts.toml"

_ACTS_HEADER = (
    "# APPROVAL ACTS, appended by `intake.py snapshot` (baseline_snapshot.copy_live).\n"
    "# One entry per act that copied a registry: the rows it carried into approval,\n"
    "# the rows it re-attested and the registries it copied. Do not edit; accepted\n"
    "# risks are anchored to these entries, and git holds the commit each act\n"
    "# landed in.\n"
)

# The registries a signing copies. FOUR SPINE plus THREE OFF-SPINE, and the
# second group is not padding: `interfaces.toml` and `external.toml` carry
# `approval` cells and `components.toml` a `state` cell that only a human may
# move. A human-only approval cell with no baseline reopens the
# "approved text moved and nobody saw" hole exactly one tier down from the one
# this mechanism closes.
#
# **THE OFF-SPINE HALF IS COPIED AND, IN THIS REPO TODAY, COMPARED BY NO RULE**
# (2026-08-20, the batch review's MINOR-13, measured: 130 of 534 snapshotted rows
# are IF/CMP and every one of them reads `Drafted`). That is not a defect and it
# is not a gap to close: both `is_drifted` and `unanchored_findings` ask their
# question only of rows that CLAIM approval, and a row below approval has made no
# claim to fall from. So the protection those tiers get is currently ZERO, and it
# begins — with no code change at all — at their first approval. The copy is
# taken at the SEED so that the day a human moves one of those cells, the
# record of what they blessed already exists to compare against. Stated here
# because "we snapshot the off-spine tiers" reads like live protection, and for
# one more registry-approval cycle it is not.
#
# SCOPED SINCE WI-571: after the seed, an off-spine registry's snapshot copy is
# refreshed ONLY when a `Status` cell moves in it (a human approval — the exact
# event this baseline exists to record), `--approves` names it or `--reattests`
# names one of its rows. A spine-only approval no longer re-copies these files,
# so it can no longer re-seal whatever off-spine drift happened to be live at
# that moment.
#
# THE ASSUMPTIONS REGISTRY JOINED LAST (SR-191, SR-192), and its copy is not
# seeded early: a record signed before the registry existed holds no copy of
# it, and the first copy is written by the approval act that approves the
# registry's first row (`FIRST_COPY_AT_APPROVAL` below).
# Implements: SR-191, SR-192, LLR-220
SNAPSHOTTED = (
    "docs/requirements/stakeholder-needs.toml",
    "docs/requirements/system-requirements.toml",
    "docs/requirements/low-level-requirements.toml",
    "docs/test/test-cases.toml",
    "docs/requirements/interfaces.toml",
    "docs/requirements/external.toml",
    "docs/requirements/components.toml",
    "docs/requirements/assumptions.toml",
)

# The registries whose FIRST COPY rides the act approving their first row
# (LLR-220): they joined `SNAPSHOTTED` after records were already signed, so a
# signed record may lawfully lack them. `unanchored_findings` excuses such a
# registry's absence from the record only while no live row of it claims
# approval; every other registry missing from a standing record is a hole,
# whatever its live rows claim, because a registry deleted together with its
# copy leaves no row claiming anything. Nothing else may join this tuple.
FIRST_COPY_AT_APPROVAL = ("docs/requirements/assumptions.toml",)

# The needs registry reads through its own carrier pair (`.toml`/`.md`) and has
# no id COLUMN — needs are dicts keyed `id`. Named separately so the row-keyed
# loop below never has to special-case a path.
NEEDS_REL = SNAPSHOTTED[0]

# THE NEEDS FILE'S TWO TIERS: its needs and the stakeholder list whose rows
# those needs cite. A need's text moving away from the copy that recorded its
# acceptance is the drift SR-178 names "stakeholder needs included", and a
# stakeholder is approved content in the same file. Both carry `status` in the
# spine's words, so both are compared tiers like every other (`SNAPSHOT_TIERS`
# below): drift is asked of them, the refresh refusal holds an act carrying a
# drifted one, `--reattests SN-###` or `STK-##` re-anchors one, the act ledger
# names them, and the unanchored rule reports an approval with no copy behind
# it. Named on its own for the readers that ask about the needs file alone (the
# approval brief's need section, `needs_owing`).
#
# Read through `_tier_rows`, the one carrier-aware need-tier loader, so a needs
# file still on the legacy markdown carrier is compared like a TOML one.
# Implements: SR-178, SR-207, LLR-271, LLR-245
NEED_TIERS = (
    ("docs/requirements/stakeholder-needs.toml", "SN-ID"),
    ("docs/requirements/stakeholder-needs.toml", "STK-ID"),
)

# `(registry path, id column)` for every ROW-KEYED tier. Twelve tiers over
# seven files: `external.toml` carries entities, boundary crossings and
# relationships in one file because they are one statement, and each is its own
# tier with its own id column (`spine_carrier.OFFSPINE_TABLE`);
# `assumptions.toml` carries the assumptions and the surrogates the same way,
# and the needs file its needs and stakeholders (`NEED_TIERS`).
# Implements: SR-191, SR-192, LLR-220
SNAPSHOT_TIERS = (
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
) + NEED_TIERS


# The Status value that CLAIMS approval-or-above. ONE MEMBER since D-9 step 5
# (it held `verified` and `planned` before the fold). Lowercase, matching every
# other Status comparison in the kit (the one casing rule, process.md §4). Kept
# as a set rather than an `is_approved` call because this module must not import
# `trace` (`trace` imports IT), and a set is the honest way to say "the values
# that claim" in a module that owns no predicate copy.
_APPROVAL_CLAIMED = frozenset({"approved"})

# The OFF-SPINE tiers claim on the SAME CELL as the spine since 2026-08-17 —
# `interfaces.toml`, `external.toml` and `components.toml` spell it `status`,
# where they used to spell it `approval` and `state`. The three-cell read this
# replaced was found by adversarial round 2 (2026-08-15): reading only `Status`
# meant those four snapshotted tiers could never claim approval and so were never
# drift-compared, defeating the reason `SNAPSHOTTED` copies them at all.
#
# THE SETS STAY SEPARATE THOUGH THE CELL IS ONE, because they answer for
# different tiers and are not the same set: only CMP reaches `founded`. Unioning
# them into a hand-written literal would re-introduce exactly the rival answer
# the derivation below exists to prevent.
#
# DERIVED FROM `spine_rules`'s ONE RULED LADDER TABLE rather than restated as a
# literal set here, and that is the whole point of deriving it: spine_rules.py's
# `BIF_MATURITY`/`CMP_MATURITY` are where each vocabulary's ladder semantics are
# "stated here and nowhere else", so a second hand-written set would be a rival
# answer to "is this row settled" that agrees until someone edits one of them.
# `Approved` and `Founded` both claim — `Founded` is `Approved` plus a
# demonstration, and this predicate asks about the TEXT being blessed.
_CLAIMED_MATURITY = (spine_rules.APPROVED, spine_rules.FOUNDED)
_APPROVAL_CELL_CLAIMED = frozenset(
    k for k, v in spine_rules.BIF_MATURITY.items() if v in _CLAIMED_MATURITY
)
_STATE_CELL_CLAIMED = frozenset(
    k for k, v in spine_rules.CMP_MATURITY.items() if v in _CLAIMED_MATURITY
)


def resolve_registry(name):
    """The `SNAPSHOTTED` rel a `--approves` registry token names — its full
    repo-relative path, its filename, or its carrier-less stem all resolve to
    the one rel. Raises with the valid names on anything else: a `--approves`
    that silently matched nothing would mute no gate while reading as though it
    had, which is exactly the false authorisation this scoping exists to stop."""
    want = str(name).strip().replace("\\", "/")
    for rel in SNAPSHOTTED:
        p = Path(rel)
        if want in (rel, p.name, p.stem):
            return rel
    raise SystemExit(
        "baseline_snapshot: --approves names an unknown registry {!r}. Name one "
        "of: {}".format(name, ", ".join(Path(r).name for r in SNAPSHOTTED))
    )


def parse_approves(spec):
    """A `--approves` CLI value into `{registry rel: ref}` — the NAMED-list form
    that lets a ref authorise the ONE registry it names (WI-571).

    The value is `;`-joined `REGISTRY=REF` pairs, the kit's CLI list idiom
    (`adjudicate --rows`); `None` or empty is `{}`. REGISTRY resolves through
    `resolve_registry`, and a pair with no `=` or an empty ref RAISES rather than
    passing a half-formed authorisation. A ref that names no registry cannot
    exist by construction, which is the whole point: the old bare `--approves
    <ref>` muted the gate for all seven files at once."""
    out = {}
    for item in (spec or "").split(";"):
        item = item.strip()
        if not item:
            continue
        registry, sep, ref = item.partition("=")
        ref = ref.strip()
        if not sep or not ref:
            raise SystemExit(
                "baseline_snapshot: --approves takes REGISTRY=REF pair(s) "
                "(e.g. low-level-requirements.toml=WI-568-sitting); got "
                "{!r}".format(item)
            )
        out[resolve_registry(registry)] = ref
    return out


def format_approves(approves):
    """The deterministic CLI inverse of `parse_approves`.

    Producers pass the canonical `{registry rel: ref}` mapping they derived;
    this boundary owns the kit's `;`-joined list syntax so no caller has to
    duplicate the delimiter that the parser consumes.
    """
    return ";".join("{}={}".format(rel, approves[rel]) for rel in sorted(approves))


# The shape of one row id: an upper-case prefix, a hyphen, a number. What makes
# the prefix a TIER is `SNAPSHOT_TIERS` (`_reattested_registry`); this only keeps
# a mistyped separator — `;`, the `--approves` idiom — from reading as one id.
_ROW_ID = re.compile(r"[A-Z]+-\d+")


def _reattested_registry(rid):
    """The `SNAPSHOT_TIERS` registry holding row `rid`, read off its prefix
    (`LLR-061` -> the design registry), or None when no compared tier owns it.

    By prefix rather than by searching the live rows, because every compared
    tier's id column is spelled `<PREFIX>-ID` and a tier added to
    `SNAPSHOT_TIERS` is then resolvable with no edit here. Tiers sharing a file
    resolve to that one file, which is the unit the copy moves."""
    for rel, id_col in SNAPSHOT_TIERS:
        if rid.startswith(id_col[: -len("ID")]):
            return rel
    return None


def parse_reattests(spec):
    """A `--reattests` CLI value into the frozenset of row ids it names.

    Comma-joined ids; `None` or empty is the empty set. Each id must name a row
    of a tier compared with its recorded copy (a need or a stakeholder among
    them) — a work item or a `;`-joined pair RAISES rather than passing a
    re-attestation that matched
    nothing while reading as though it had (`resolve_registry`'s reason, one
    flag over).

    Implements: SR-207, LLR-245"""
    out = set()
    for item in (spec or "").split(","):
        rid = item.strip()
        if not rid:
            continue
        if not _ROW_ID.fullmatch(rid) or _reattested_registry(rid) is None:
            raise SystemExit(
                "baseline_snapshot: --reattests takes comma-joined row ids of a "
                "row-compared tier ({}); got {!r}".format(
                    ", ".join(
                        col[: -len("ID")] + "###" for _rel, col in SNAPSHOT_TIERS
                    ),
                    rid,
                )
            )
        out.add(rid)
    return frozenset(out)


def act_summary(written, seed, approves, reattests, verdict=None):
    """The one line `intake.py snapshot` prints for an act that landed: how many
    files it copied and, when named, the refs and re-attested rows it recorded
    into the snapshot's stamp, and the verdict it recorded in the act ledger.
    Kept beside the parsers that build its inputs so the CLI edge stays a
    call."""
    return "snapshot: {} registry file(s) copied to {}{}{}{}{}".format(
        len(written),
        SNAPSHOT_DIR,
        " (SEEDED — this is the first snapshot; it blesses the text you just ruled)"
        if seed
        else "",
        " (APPROVED BY: {} — recorded in the snapshot's stamp)".format(
            "; ".join("{}={}".format(Path(r).name, approves[r]) for r in approves)
        )
        if approves
        else "",
        " (RE-ATTESTED: {} — recorded in the snapshot's stamp)".format(
            ", ".join(sorted(reattests))
        )
        if reattests
        else "",
        " (VERDICT: {} — recorded in the act ledger)".format(verdict)
        if verdict
        else "",
    )


def snapshot_root(root):
    """The snapshot's directory as a path. Does not create it and does not
    check that it exists — `load_all` and `copy_live` each have their own,
    different, answer to absence."""
    return Path(root) / SNAPSHOT_DIR


def exists(root):
    """True when this repo has a snapshot at all — the vacuous-by-absence test.

    The MECHANICAL writer (`intake._apply_flips`) guards on this rather than
    letting `copy_live` refuse: before the first signing there is no directory,
    and a mechanical flip that HARD-FAILED for want of a snapshot would break
    the adjudication path in every repo that has not signed yet, including a
    fresh adopter's. `copy_live`'s refusal is for the HUMAN path, where "you
    meant `--seed`" is the useful answer."""
    return snapshot_root(root).is_dir()


# Every carrier a registry's copy can sit under: the spine pair and the needs
# registry's markdown. A copy that moved carrier is still that registry's copy,
# and a suffix a registry never had matches no commit.
_COPY_SUFFIXES = tuple(
    dict.fromkeys(spine_carrier.CARRIERS + spine_carrier.NEED_CARRIERS)
)


def stamp(root, registry=None):
    """`(short rev, date)` of the commit that last wrote the snapshot — or, named
    a `registry` (its live path, either carrier), the commit that last wrote
    THAT registry's copy — or `("", "")` when there is none, git cannot answer,
    or this is not a checkout.

    PER REGISTRY WHEN A READER SHOWS ROWS OF ONE. A refresh copies only the
    registries its act authorises (WI-571), so the copies in the directory were
    written at different commits, and the directory's newest write names ONE
    copy's provenance for all of them: an amendment brief judging requirement
    rows named a commit that had copied the needs file alone. Unnamed, this
    still answers for the directory, which is the right answer for a reader
    naming the snapshot as a whole.

    ADVISORY, AND FROM GIT RATHER THAN FROM A FILE — deliberately. The stamp is
    a courtesy for a human reading a brief ("the baseline you are diffing
    against is from this date"), and it is derived, so it can never be the
    ledger the README's first line promises it is not. Every arm degrades to
    `("", "")` rather than raising: a missing stamp costs a reader one line of
    context, and nothing computes anything from it."""
    if not exists(root):
        return "", ""
    paths = (
        [SNAPSHOT_DIR]
        if registry is None
        else [
            "{}/{}".format(SNAPSHOT_DIR, rel)
            for rel in spine_carrier.carriers(registry, _COPY_SUFFIXES)
        ]
    )
    try:
        proc = subprocess.run(
            [
                "git",
                "-C",
                str(root),
                "log",
                "-1",
                "--format=%h %cs",
                "--",
                *paths,
            ],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    except (OSError, ValueError):
        return "", ""
    if proc.returncode != 0:
        return "", ""
    parts = proc.stdout.strip().split()
    return (parts[0], parts[1]) if len(parts) >= 2 else ("", "")


def registry_stamps(root, rels=SNAPSHOTTED):
    """`[(registry, short rev, date)]`: `stamp` asked once per registry the
    record holds a copy of, in `rels` order — the provenance an owner's surface
    names beside the rows it shows. A refresh copies only what its act
    authorises, so the copies were written at different commits, and one
    directory-wide stamp named one copy's commit for all of them. A registry
    with no committed copy is left out rather than given another's commit.

    Implements: SR-178, LLR-273"""
    out = []
    for rel in rels:
        rev, date = stamp(root, rel)
        if rev:
            out.append((rel, rev, date))
    return out


def approval_stamp(root):
    """`(short rev, date)` of the last commit that MOVED A STATUS CELL in a
    snapshotted registry, or `("", "")` when git cannot say.

    THE COMPANION TO `stamp`, AND THE ONE A READER ACTUALLY WANTS (adversarial
    round, 2026-08-20: ROUND-OPUS MAJOR-4). `stamp` answers "when was this record
    last WRITTEN", which is a fact about the copy and nothing more — a
    traced-cell refresh moves it while approving nothing. The provenance question
    a brief's reader is asking is "when did an approval last happen here", and
    the only mechanical trace of an approval is a `status` line moving in a
    registry the snapshot covers.

    `-G` over the status-line regex rather than `-S`: a pickaxe on the STRING
    counts occurrences, and an approval changes a status line's VALUE without
    changing how many there are, so `-S` is blind to exactly the commit being
    looked for. `-G` matches the added/removed lines of the diff, where BOTH
    sides of a maturity edit land — the removed line carrying the old value and
    the added line carrying the new one.

    ADVISORY, like `stamp`, and degrades the same way: it is rendered for a human
    and computed by nothing. A row addition also moves a status line into
    existence and will be named here — that is a first approval or a new draft,
    and either way it is the honest answer to "what last touched a status cell".

    **CARRIER-SHAPED, AND IT SAYS SO WHEN IT CANNOT ANSWER.** A status cell has a
    LINE of its own under the TOML carrier and none under CSV, where it is one
    field of a row line that changes for a dozen unrelated reasons. So this
    derivation answers for TOML and returns the empty stamp for a CSV-carrier
    repo, which the brief renders as "or git cannot say" — the degrade stated
    rather than a wrong commit named. Widening it to CSV would mean claiming an
    approval from any row edit, which is the overclaim this function exists to
    replace."""
    try:
        proc = subprocess.run(
            [
                "git",
                "-C",
                str(root),
                "log",
                "-1",
                "--format=%h %cs",
                "-G",
                r'^[[:space:]]*(status|Status)[[:space:]]*=[[:space:]]*"',
                "--",
                *SNAPSHOTTED,
            ],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    except (OSError, ValueError):
        return "", ""
    if proc.returncode != 0:
        return "", ""
    parts = proc.stdout.strip().split()
    return (parts[0], parts[1]) if len(parts) >= 2 else ("", "")


def _claims_approval(row):
    """True when this row claims approval or above, on the ONE cell every tier
    now uses: `Status`, spine and off-spine alike.

    IT READ THREE CELLS UNTIL 2026-08-17 — `Status`, `Approval`, `State` — not
    as a design but because three registries spelled one axis three ways, and
    the cost was concrete: a predicate that read `Status` alone answered False
    for every off-spine row, so the copies `SNAPSHOTTED` takes precisely because
    those cells move only by human hand were never compared to anything. The
    registry status unification collapsed the spellings, so the OR over three
    cells collapses with them.

    Still an OR over the two VOCABULARY sets rather than a dispatch on tier:
    they differ (only CMP reaches `founded`), and a tier table here would be a
    second place to keep that mapping right.

    THE SPINE HALF COLLAPSED AT D-9 STEP 5, as this docstring said it would: the
    ladder has ONE word for the claim (`Approved`) and the two pre-rename values
    that split it (`Verified`, `Planned`) folded into it under OI-30 D1. The two
    off-spine arms were never transitional and are unchanged, except that
    `BIF_MATURITY`'s below-approval key is spelled `drafted` since 5b — which
    this reads through `spine_rules` rather than restating, so the re-spelling
    needed no edit here at all.

    **THE NEEDS FILE'S TIERS REACH IT LIKE EVERY OTHER.** Needs used to carry
    no maturity key, so there was no cell to read; they carry `status` now, in
    the spine's words, and so does the stakeholder list beside them, so
    `SNAPSHOT_TIERS` lists both (`NEED_TIERS`) and every compared-tier reader
    asks this predicate of them."""
    return (
        (row.get("Status") or "").strip().lower() in _APPROVAL_CLAIMED
        or (row.get("Status") or "").strip().lower() in _APPROVAL_CELL_CLAIMED
        or (row.get("Status") or "").strip().lower() in _STATE_CELL_CLAIMED
    )


def _approval_transition(before, after):
    """True only when an existing row crosses INTO an approval claim.

    This is the maturity boundary that authorises a refresh: a `Drafted` row
    becoming `Approved` blesses its registry's current text. A Status difference
    by itself is not authority — in particular `Approved` -> `Drafted` revokes
    a claim and cannot carry an unrelated approved amendment into the snapshot.
    Keep the meaning here beside `_claims_approval`, rather than making each
    refresh caller remember which direction a Status move went (WI-571,
    Review-A round 004). New approved rows are handled by their absence from the
    prior snapshot, not by this existing-row predicate."""
    return not _claims_approval(before) and _claims_approval(after)


def load_all(root):
    """Every snapshotted registry, parsed off the snapshot tree.

    `{(stem, id_col): {row id: row}}` for the row-keyed tiers, plus
    `{(stem, "SN-ID"): {need id: need}}` for the needs tier — keyed on the
    carrier-STRIPPED path so a snapshot taken under one carrier and read under
    another still joins.

    **None when the snapshot directory does not exist at all**, which is the
    only vacuous state and is the true pre-approval one. Callers test for None
    and skip; they must NOT treat it as an empty dict, because an empty dict
    says "the snapshot recorded no rows" and that reads as "everything drifted"
    or "nothing is anchored" depending on which way the caller leans.

    **Raises on a file that exists and does not parse.** `spine_carrier.load`
    already refuses rather than returning `[]`, and that refusal is the right
    one here for the reason its own docstring gives one level up: unlike git
    history, a snapshot file is on disk and a person can fix it. The
    advisory-print-and-fall-back degrade that a GIT-HISTORY reader is right to
    use (`check_trajectory._spine_rows_at`, reading a revision nobody can now
    edit) is wrong here.

    Implements: SR-178, LLR-271"""
    base = snapshot_root(root)
    if not base.is_dir():
        return None
    out = {}
    for rel, id_col in SNAPSHOT_TIERS:
        rows = _tier_rows(base, rel, id_col)
        out[(spine_carrier.stem(rel), id_col)] = {
            str(r.get(id_col) or "").strip(): r
            for r in rows
            if str(r.get(id_col) or "").strip()
        }
    return out


def rows_for(snapshot, rel, id_col):
    """One tier's snapshot rows, or `{}` when there is no snapshot at all.

    The ONE place the None-means-absent sentinel is collapsed, so a caller that
    genuinely wants "compare against nothing" writes it once here instead of
    each caller inventing its own `or {}` — which is how the absent/empty
    distinction gets lost."""
    if snapshot is None:
        return {}
    return snapshot.get((spine_carrier.stem(rel), id_col), {})


def _copy_file(base, rel):
    """Registry `rel`'s live file under `base` — a repository root, or the
    snapshot root for its copy — or None. The needs registry may sit under its
    legacy markdown carrier, which is that registry all the same, not a hole.

    Implements: SR-147, LLR-277"""
    suffixes = (
        spine_carrier.NEED_CARRIERS if rel == NEEDS_REL else spine_carrier.CARRIERS
    )
    return spine_carrier.resolve(Path(base) / rel, suffixes)


def _tier_rows(base, rel, id_col):
    """One compared tier's rows under `base` (a repository root or the snapshot
    root), example rows dropped: the needs file's tiers through the one
    carrier-aware need-tier loader, so a markdown needs file is compared on
    both sides like a TOML one, and every other tier through `load`.

    Implements: SR-147, LLR-277"""
    if (rel, id_col) in NEED_TIERS:
        return spine_carrier.load_need_tier(Path(base) / rel, id_col, False)
    return spine_carrier.load(Path(base) / rel, id_col, keep_examples=False)


# The one "cell" a REMOVED row is absorbed under (`refresh_ledger`). Worded as
# the refusal line prints it — `<registry> <row id>: removed from the live
# registry` — and not a column name any registry can carry.
ROW_REMOVED = "removed from the live registry"


def _removed_rows(before_rows, live_rows, id_col):
    """`{row id: {ROW_REMOVED: ("recorded", "absent")}}` for each recorded row
    that claims approval and that the live registry no longer carries — the
    removals `refresh_ledger` absorbs beside the amendments. Split out so the
    ledger's walk stays under the complexity bar. A recorded row below approval
    is not here: its text was never blessed, so dropping it re-blesses
    nothing."""
    live_ids = {str(row.get(id_col) or "").strip() for row in live_rows}
    return {
        rid: {ROW_REMOVED: ("recorded", "absent")}
        for rid, before in before_rows.items()
        if rid not in live_ids and _claims_approval(before)
    }


def removed_rows(root, ids, snapshot):
    """`(removed, unknown)` over the row ids `ids`, against `snapshot`
    (`load_all`'s): `removed` is `[(registry, id column, row id, cells,
    recorded row)]`, in `SNAPSHOT_TIERS` order, for each id the record holds
    claiming approval that the live registry no longer carries (`_removed_rows`'
    rule, the removals `refresh_ledger` absorbs), `cells` the recorded row's
    approved cells as `(name, recorded value, "")` triples, sorted; and
    `unknown` the sorted ids that no live row of a compared tier carries and
    the record does not hold.

    The one reading of which ids name a row at all: `--reattests` refuses an
    unknown id with it, and the amendment brief briefs a removed scoped row and
    refuses an unknown scope token with it.

    Implements: SR-178, LLR-271"""
    ids, removed, known = set(ids), [], set()
    for rel, id_col in SNAPSHOT_TIERS:
        recorded = rows_for(snapshot, rel, id_col)
        live = _tier_rows(root, rel, id_col)
        known |= {str(row.get(id_col) or "").strip() for row in live}
        known |= set(recorded)
        for rid in sorted(ids & set(_removed_rows(recorded, live, id_col))):
            cells = check_trajectory.split_changed_cells(rel, id_col, recorded[rid], {})
            cells = [(n, b, a) for n, (b, a) in sorted(cells["approved"].items())]
            removed.append((rel, id_col, rid, cells, recorded[rid]))
    return removed, sorted(ids - known)


def refresh_ledger(root, snapshot=None):
    """What a refresh WOULD ABSORB, per registry:
    `{rel: {"absorbed": {row id: {cell: (before, after)}}, "flips": [row id]}}`.

    The two halves are the two sides of the authority question `copy_live` asks
    below. `absorbed` is the approved text a copy would silently re-bless: rows
    whose SNAPSHOT copy claims approval (that is the record that would be
    overwritten) whose approved cells have moved, OR which the live registry no
    longer carries at all. `flips` is the authorising act — an existing row that
    crossed into an approval claim in the reviewed commit, which authorises THAT
    row and no other (SR-207). A reverse Status move is a de-approval, not
    authority to re-bless anything. Tiers that share a file share one entry,
    because the file is the unit the copy moves.

    A REMOVED ROW IS ABSORBED TOO, keyed by the single pseudo-cell
    `ROW_REMOVED`. The copy is the whole file, so refreshing it after a recorded
    approved row was deleted drops the text a human blessed from the record as
    surely as rewriting it would — and a ledger that walked the live rows alone
    could not see a row that is not there, so a flip elsewhere in the file
    carried the deletion in unnamed. The recorded rows are walked as well, and a
    whole registry file deleted from live reads as every one of its rows removed.
    No flip can clear a removal (there is no row left to flip); naming the row
    in `--reattests` is how an act blesses it.

    A FLIPPED ROW IS NEVER ABSORBED, and that is no allowance: its copy reads
    below approval, so its text was never blessed and copying it re-blesses
    nothing (the rule two paragraphs down). Amend-plus-flip is NOT approval
    (WI-806, retiring it with OI-101 Q2): the text a flip blesses is committed
    first, on its own, and the act that flips and copies it is a second commit
    changing no other spine cell, which `text_then_act.text_then_act_lines`
    enforces at the hook and per lane commit at the merge slot.

    Rows the snapshot does not carry are not here at all — an approval with no
    copy is UNANCHORED, a louder finding `unanchored_findings` owns. Rows below
    approval in the record are not here either: a `Drafted` row's text was never
    blessed, so copying it re-blesses nothing.

    `{}` when the repo has no snapshot (nothing to absorb)."""
    if snapshot is None:
        snapshot = load_all(root)
    if snapshot is None:
        return {}
    ledger = {}
    for rel, id_col in SNAPSHOT_TIERS:
        entry = ledger.setdefault(rel, {"absorbed": {}, "flips": []})
        before_rows = rows_for(snapshot, rel, id_col)
        live_rows = _tier_rows(root, rel, id_col)
        entry["absorbed"].update(_removed_rows(before_rows, live_rows, id_col))
        _ledger_live_rows(entry, rel, id_col, before_rows, live_rows)
    return ledger


def _ledger_live_rows(entry, rel, id_col, before_rows, live_rows):
    """`refresh_ledger`'s walk of one tier's LIVE rows into its file's `entry`:
    a row crossing into approval against its copy is a flip, and a row whose
    copy claims approval and whose approved cells moved is absorbed. A row the
    copy does not carry, or whose copy reads below approval (a flipped row's
    included), is neither absorbed nor judged here. Split out so the ledger's
    walk stays under the complexity bar (WI-806).

    Implements: SR-207, LLR-245"""
    for row in live_rows:
        rid = str(row.get(id_col) or "").strip()
        before = before_rows.get(rid) if rid else None
        if before is None:
            continue
        if _approval_transition(before, row):
            entry["flips"].append(rid)
        if not _claims_approval(before):
            continue
        changed = check_trajectory.split_changed_cells(rel, id_col, before, row)
        if changed["approved"]:
            entry["absorbed"][rid] = changed["approved"]


def refresh_refusal(root, approves=None, snapshot=None, *, seed=False, reattests=()):
    """The refusal text for an unauthorised refresh, or `""` when the copy is
    authorised — THE AUTHORITY CHECK THE WRITER SHIPPED WITHOUT (adversarial
    round, 2026-08-20: ROUND-OPUS CRITICAL-2 / ROUND-SOL CRITICAL-1).

    The hole was exact and was executed end to end: `copy_live` refused only to
    CREATE the directory, so once a repo had signed, `intake.py snapshot`
    re-blessed whatever text happened to be in the tree. Two commits — rewrite an
    Approved requirement, then refresh — left every check green with the record
    rewritten to match, and the drift the mechanism exists to render had been
    absorbed into the baseline.

    DECIDED ROW BY ROW (SR-207). The act is refused while any row of a registry
    it would copy has approved text drifted from its recorded copy and the act
    does not itself bless that row (`_unattested_rows`). A row is blessed in one
    of three ways, and the first two need no flag at all:

      1. **It absorbs nothing approved.** Traced-cell refreshes (a `Module`,
         `CodeSymbol`, `TestRefs` or ref pointer re-point) and Drafted-row work
         stay exactly as cheap as they were — this is the common case, and the
         review verified the WI-482/WI-452 class of the same day was clean.
      2. **Its own `Status` moved into approval.** A human moved THAT row's
         maturity cell in the reviewed commit the copy rides, over text an
         earlier commit already carried (WI-806: text first, the act second;
         amend-plus-flip is no longer approval). It blesses that row and no
         other.
      3. **`--reattests <ROW-ID>` names it.** The escape for the shape the ladder
         genuinely has — an amendment to an Approved row that a sitting ruled
         without moving its Status (the D-9 ladder's own case, and what the
         2026-08-20 17-cell amendment batch was). The ids land in the snapshot's
         prose stamp, so the record says which rows the act re-read.

    `--approves <registry>=<ref>` NAMES THE ACT AND CLEARS NO ROW. It still puts
    its registry in the act's scope and records the ref — a HUMAN's citation of
    the sitting, log fragment or commit, not validated because nothing can
    validate it. What it no longer does is pass the registry's drift: the record
    is a copy of the whole file, so refreshing it for one row copies every row
    as it stands, and a registry-wide pass let one row's approval silently bless
    another row's unreviewed edit. Before WI-571 a bare `--approves` muted the
    gate for all seven files; WI-571 narrowed it to the one registry it names;
    SR-207 narrows it to none.

    PER ROW RATHER THAN PER REGISTRY, reversing the choice this docstring used to
    defend — that a row-level pairing would demand a flip for each amended row,
    which is the flip the D-9 ladder deleted. `--reattests` names a row without
    flipping it, so the row-level rule costs no flip. And it holds for any
    number of tiers in one file: `external.toml`'s three tiers share one ledger
    entry, so one tier's approval can no longer carry another tier's drift, and
    a tier added to `SNAPSHOT_TIERS` is covered with no edit here — the needs
    file's needs and stakeholders included (`NEED_TIERS`), so an act copying the
    needs registry is refused while an approved need's text moved unread.
    A recorded approved row deleted from live is absorbed as REMOVED
    (`refresh_ledger`) and cleared only by naming it in `--reattests`. Whether
    each re-attested id names a row at all is `_refuse_reattests`'s question,
    asked before EVERY copy — this gate is skipped on a first signing.

    AND SCOPED TO THE ACT, LIKE THE WRITER (WI-584 ruling (a)). Only registries
    this act would WRITE are judged. WI-571 scoped `copy_live` and left this
    gate global, so a per-registry approval was refused by drift in registries
    the copy would never touch: naming the one registry a sitting ruled listed
    only the ones it did not, under a header claiming nothing authorised the
    act. A registry the write set excludes cannot be absorbed by the act being
    refused, so blocking on it protects nothing — it keeps both its stale bytes
    and its visible drift either way, which is what the re-attestation brief is
    for. A registry reaches the list by being WRITTEN — a flip, a ref, a
    re-attested row or a row arriving already approved puts it in scope — or
    under `seed`, which rewrites all seven.

    ONE ARM STAYS UNSCOPED, deliberately: when the act would write NOTHING and
    approved text has drifted, it is still refused. A refresh that copies
    nothing is a no-op, and a no-op exiting 0 in a tree where an Approved row's
    text was quietly rewritten is the laundering scenario answered with silence.
    The drift survives either way — the writer is already scoped — but the
    caller is told, which is the whole job of this text.

    Implements: SR-207, LLR-245"""
    reattests = frozenset(reattests or ())
    try:
        if snapshot is None:
            # Loaded HERE rather than left to `refresh_ledger`, because the scope
            # decision below reads it too and a `None` would read every approved
            # row as newly arrived — which is the widest possible scope, exactly
            # the direction this function must not fail in.
            snapshot = load_all(root)
        ledger = refresh_ledger(root, snapshot)
    except SystemExit:
        # AN UNREADABLE RECORD CANNOT BE COMPARED, and `copy_live` is the repair
        # path for exactly that state (a stale other-carrier file, a snapshot
        # that does not parse). Refusing here would brick the only tool that
        # fixes it. The bypass this leaves is real and is bounded: corrupting the
        # record first means COMMITTING the corruption, which reds both mirror
        # rules — the staged one in the commit that does it, and the committed
        # one on every strict run afterwards.
        return ""
    # The act's write scope, the same set the writer uses. A `seed` over a
    # standing record really does rewrite all seven, so its scope is total.
    scope = (
        set(SNAPSHOTTED)
        if seed
        else _authorised_registries(root, approves, snapshot, reattests)
    )
    unattested = _unattested_rows(ledger, reattests)
    # Scoped when the act writes something; whole-ledger when it writes nothing,
    # so a no-op refresh over drifted approved text is refused rather than silent.
    blocked = [pair for pair in unattested if pair[0] in scope] if scope else unattested
    if not blocked:
        return ""
    return _refusal_text(blocked, scope)


def _unattested_rows(ledger, reattests=frozenset()):
    """`[(registry rel, {row id: {cell: (before, after)}})]`, sorted by registry:
    for each registry, the absorbed rows (approved text drifted from the
    recorded copy) minus the rows `reattests` names. What is left is every row
    the copy would re-bless that nobody in this act read, which is exactly what
    the act must not carry; a registry left with none is dropped.

    A flipped row is never absorbed (its copy reads below approval), so no flip
    is subtracted here: a flip clears no drift, it only puts its registry in
    the act's scope (WI-806 retired amend-plus-flip as approval).

    Implements: SR-207, LLR-245"""
    out = []
    for rel, entry in sorted(ledger.items()):
        owed = {
            rid: cells
            for rid, cells in entry["absorbed"].items()
            if rid not in reattests
        }
        if owed:
            out.append((rel, owed))
    return out


def _refusal_text(blocked, scope):
    """The refusal a caller reads: EVERY unattested row and its cells, what this
    act writes, and the two ways forward.

    UNCAPPED (SR-207). It used to print five rows per registry and a count of
    the rest, which hid the rows past the cap until the first five were dealt
    with — and the list is the work a person has to do before the act can land.

    A sibling of `refresh_refusal` rather than a tail inside it, because the
    scoped rule gave that function a second decision to make and the rendering
    was what pushed it over the cognitive bar — the check names decomposing
    OUTWARD as the first escape, and a message builder is the seam that comes
    apart cleanly (WI-584)."""
    lines = [
        "baseline_snapshot: REFUSED — this refresh would ABSORB approved text "
        "into the record of what a human blessed, for rows this act neither "
        "approves nor re-attests:"
    ]
    for rel, rows in blocked:
        for rid, cells in sorted(rows.items()):
            lines.append("  {} {}: {}".format(rel, rid, ", ".join(sorted(cells))))
    lines.append(
        "This act would copy NOTHING — no registry is named, no `Status` moved "
        "and no row is re-attested — so the drift above simply stands, and this "
        "refresh is not what clears it."
        if not scope
        else "This act WRITES {}, and each row above sits in a registry it would "
        "copy: a `Status` move approves only its own row and an `--approves` ref "
        "names the act without clearing any row, so these amendments would ride "
        "along unread. Registries OUTSIDE the act's scope are not judged here at "
        "all: they keep their prior snapshot bytes and their visible "
        "drift.".format(", ".join(sorted(Path(rel).name for rel in scope)))
    )
    lines.append(
        "A snapshot copy IS the approval record, so approved text reaches it only "
        "through an act that names its row, taken in a commit after the one that "
        "carried the text. Two ways forward: having read its changed cells, "
        "re-run with `intake.py snapshot --reattests "
        "<ROW-ID>[,<ROW-ID>...]` naming EACH row above (the ids are recorded into "
        "the snapshot's README stamp and act ledger, and `--approves "
        "<registry>=<ref>` may ride "
        "beside them to cite the sitting, log fragment or commit that ruled "
        "them — a row marked removed is blessed as a removal the same way); or "
        "revert the amendment or restore the removed row and leave the drift "
        "standing, which is what the re-attestation brief is for. Traced cells "
        "(Module/CodeSymbol/TestRefs and the ref pointers) are never blocked here."
    )
    return "\n".join(lines)


def _record_approval(base, approves, copied_rels, reattests=frozenset()):
    """Append this act's SCOPE to the snapshot's prose stamp, creating the stamp
    when the repo has none: the registries it copied and, for EACH, the
    `--approves` ref that named it and the rows `--reattests` named in it, or
    the `Status` move that put it in scope when neither did (WI-571 — the stamp
    records the act's scope, so the next reader sees WHICH registries an
    approval touched instead of a whole-tree claim; SR-207 — and which rows it
    re-attested beside the approvals, since a re-attestation moves no cell a
    later reader could find).

    STILL PROSE (design §F8, repo-lock D-10's tripwire) — the line is a
    sentence a human reads, and nothing parses it. The machine facts stay in
    the copied files, in git, and in the act ledger `_record_act` appends to
    beside it, which names the same re-attested rows in typed fields."""
    path = base / README
    reasons = []
    for rel in copied_rels:
        named = ["ref: " + approves[rel]] if approves.get(rel) else []
        rows = sorted(r for r in reattests if _reattested_registry(r) == rel)
        named += ["re-attested: " + ", ".join(rows)] if rows else []
        reasons.append(
            "{} ({})".format(Path(rel).name, "; ".join(named) or "Status move")
        )
    stamped = (
        "- {} — refresh under approval. Copied: {}. Registries not named by this "
        "act keep their prior snapshot bytes.\n".format(
            _today(), "; ".join(reasons) if reasons else "(none)"
        )
    )
    if not path.is_file():
        path.write_text(
            "# `last_approved` — the approval stamp\n\n"
            "**This file is prose. Nothing parses it.** Every machine fact about "
            "the snapshot comes from the copied registry files beside it, from "
            "the act ledger `acts.toml`, or from `git log` over this "
            "directory.\n\n"
            "## Refreshes recorded under an explicit approval\n\n"
            "Each line below records a refresh that copied a registry under "
            "authority — a `--approves` ref, rows named by `--reattests`, or a "
            "`Status` move in the copied registry (`intake.py snapshot "
            "[--approves <REGISTRY=REF>] [--reattests <ROW-ID,...>]`) — and "
            "names, for each registry copied, the ref and the re-attested rows, "
            "or the Status move when neither named it. The seed and a refresh "
            "that copied nothing (a traced-only re-point) write no line.\n\n" + stamped,
            encoding="utf-8",
            newline="\n",
        )
        return
    text = path.read_text(encoding="utf-8")
    if not text.endswith("\n"):
        text += "\n"
    path.write_text(text + stamped, encoding="utf-8", newline="\n")


def _today():
    """Today, ISO. Its own function so the stamp writer has one clock and the
    tests have one thing to read."""
    import datetime

    return datetime.date.today().isoformat()


def _authorised_registries(root, approves, snapshot, reattests=frozenset()):
    """The `SNAPSHOTTED` rels whose snapshot copy a refresh MAY rewrite: every
    registry `approves` names, every registry holding a row `reattests` names,
    plus every registry an approving `Status` move happened in. Everything else keeps the bytes it already has, so a spine-only
    approval no longer drags off-spine drift into the record (WI-571) — and both
    mirror rules stay green because each is pinned to the file it judges (an
    untouched registry is not "written", so `staged_snapshot_findings` never sees
    it in the commit and `committed_snapshot_findings` still compares it to live
    at its own writing commit).

    An approving `Status` move is a transition INTO an approval claim on an
    existing row, or a NEW row that arrives already claiming approval — the
    maturity act that blesses text in the reviewed commit this copy rides, and
    leaving its registry uncopied would strand the row as an
    `unanchored_findings` ERROR. A de-approval is not an approving transition:
    its Status differs but cannot authorise an unrelated amendment. An amendment
    that moved no `Status` is deliberately NOT here: that is the case
    `refresh_refusal` gates, and naming its row in `--reattests` is how a human
    re-attests it — which puts the row's registry in scope here, or a
    re-attestation would copy nothing and exit 0 over the drift it names.
    Being IN scope clears no row; `refresh_refusal` still judges every row of
    every registry this returns."""
    out = set(approves or ()) | {_reattested_registry(r) for r in reattests}
    out.discard(None)
    for rel, id_col in SNAPSHOT_TIERS:
        if rel in out or _copy_file(Path(root), rel) is None:
            continue
        before_rows = rows_for(snapshot, rel, id_col)
        for row in _tier_rows(root, rel, id_col):
            rid = str(row.get(id_col) or "").strip()
            if not rid:
                continue
            before = before_rows.get(rid)
            if before is None:
                if _claims_approval(row):  # a new row that arrives approved
                    out.add(rel)
                    break
            elif _approval_transition(before, row):
                out.add(rel)
                break
    return out


def _refuse_reattests(root, reattests, snapshot, first_signing):
    """Raise when this act's `--reattests` cannot stand; return when it can.

    ASKED BEFORE EVERY COPY, the seed and the repair path included, because both
    skip `refresh_refusal`: a genuine seed never reaches it, and an unreadable
    record makes it answer "" so the repair can run. Two refusals, in order:

      1. **An id that names no row.** Known ids are every live row of a compared
         tier, plus — when the record reads — every recorded row, since naming
         a REMOVED row is how an act blesses its removal. Checked against the
         live registries whatever state the record is in, so a typo never lands
         a row nobody read in the stamp.
      2. **Any id on a first signing** — a seed, a re-seed over a standing
         record, a repair of a record that does not parse, a scaffold whose
         record holds no registry. Each copies the whole tree and writes no
         stamp, so there is nothing to re-attest and nowhere to record it, and
         `act_summary` would otherwise claim a record that was never written."""
    if not reattests:
        return
    unknown = removed_rows(root, reattests, snapshot)[1]
    if unknown:
        raise SystemExit(
            "baseline_snapshot: REFUSED — --reattests names {}, which no live row "
            "of a compared registry carries and the record does not hold; a "
            "re-attestation is recorded into the snapshot's stamp, so it must "
            "name a row someone read".format(", ".join(unknown))
        )
    if first_signing:
        raise SystemExit(
            "baseline_snapshot: REFUSED — --reattests {} on a first signing (a "
            "seed, or a repair of a record that does not read): it copies the "
            "whole tree and writes no stamp, so there is nothing to re-attest "
            "and nowhere to record it. Drop --reattests".format(
                ",".join(sorted(reattests))
            )
        )


def verdict_rel(root, verdict):
    """The verdict path as the act ledger records it: repo-relative, forward
    slashes, no `./` — the one spelling `git show <rev>:<path>` resolves at the
    merge slot (Sol review 1, WI-791: a Windows-spelt path named the file here
    and was refused there). Every path, relative or absolute, is resolved
    against `root`, so `..` segments are canonicalized (Sol final review): one
    resolving inside the tree comes back repo-relative, and one resolving
    outside it comes back ABSOLUTE, for `_refuse_verdict` to refuse. None for
    no verdict.

    Implements: SR-207, LLR-245"""
    if not verdict:
        return None
    text = str(verdict).strip().replace("\\", "/")
    full = (Path(root) / text).resolve()
    try:
        return full.relative_to(Path(root).resolve()).as_posix()
    except ValueError:
        return full.as_posix()


def _refuse_verdict(root, verdict, reattests):
    """Raise when this act's `verdict` cannot stand; return when it can.

    A verdict is the ruling that carried the named rows' signature over, so it
    needs rows to rule (`reattests`) and must name a file in the tree: the
    ledger records the path, and a typo would land a ruling nobody can open.
    The ledger records it for audit; no rule requires it. Whether a held
    re-attestation lands is the merge slot's lane rule
    (`held_status.commit_held_approval_lines`): an accepted verdict ruling
    the row CLARITY whose binding records the row's text.

    Implements: SR-207, LLR-245"""
    if not verdict:
        return
    if not reattests:
        raise SystemExit(
            "baseline_snapshot: REFUSED — --verdict {} names no re-attested row; "
            "a verdict records the ruling that re-anchored the rows "
            "--reattests names".format(verdict)
        )
    if Path(verdict).is_absolute() or not (Path(root) / verdict).is_file():
        raise SystemExit(
            "baseline_snapshot: REFUSED — --verdict {} is not a file in the tree; "
            "the act ledger records the verdict's path, so it must name the "
            "verdict the session wrote".format(verdict)
        )


def _refresh_targets(root, approves, seed, base, reattests=frozenset()):
    """`(targets, first_signing)`: the registries a REFRESH of a standing
    snapshot copies, and whether this refresh is a first signing — or a raised
    refusal when the copy is unauthorised.

    The whole tree on a first signing (a `--seed`, an unreadable record being
    repaired, or a scaffold that still holds no registry — the vacuous state
    `unanchored_findings` reads, so `intake.py snapshot --seed` on a bootstrap's
    README-only directory still copies everything); otherwise only the act's
    authorised scope (`_authorised_registries`). The `first_signing` flag rides
    back so `copy_live` stamps the approval only on a genuine refresh, never on
    the initial blessing. Split from `copy_live` so the scope decision — a
    self-contained job with its own refusal — does not push the writer's branch
    count over the C901 bar (WI-571). `seed` rides into the refusal because a
    re-seed over a standing record writes all seven registries, and the gate is
    scoped to what the act writes (WI-584); `reattests` rides into both, since
    it is both a scope and a blessing (SR-207)."""
    try:
        snapshot = load_all(root)
    except SystemExit:
        snapshot = None  # unreadable record: copy_live is the repair path
    first_signing = (
        seed
        or snapshot is None
        or not any(spine_carrier.resolve(base / rel) for rel in SNAPSHOTTED)
    )
    _refuse_reattests(root, reattests, snapshot, first_signing)
    refusal = refresh_refusal(root, approves, snapshot, seed=seed, reattests=reattests)
    if refusal:
        raise SystemExit(refusal)
    if first_signing:
        return set(SNAPSHOTTED), True
    return _authorised_registries(root, approves, snapshot, reattests), False


def copy_live(root, *, seed=False, approves=None, reattests=None, verdict=None):
    """Mirror the registries an act AUTHORISES into `docs/archive/last_approved/`;
    the sorted list of repo-relative paths written.

    SCOPED TO THE ACT SINCE WI-571. The seed copies the whole tree once; a
    refresh copies ONLY the registry a `Status` move happened in, every registry
    `approves` names and every registry holding a row `reattests` names
    (`_authorised_registries`), and leaves every other
    registry byte-identical to what it already was. The whole-tree copy this
    replaced re-sealed whatever off-spine drift was live at the moment of a
    spine-only approval, silently zeroing the off-spine census the snapshot is
    the only basis for. An untouched file is not "written", so both mirror rules
    stay satisfied without touching it.

    Byte-for-byte (`shutil.copyfile`), the LIVE carrier only — and for a registry
    it copies, any OTHER-carrier file for the same stem is DELETED in the same
    act, or `spine_carrier.resolve` raises "exists under BOTH carriers" on the
    very next read of the snapshot. A copied registry with no live carrier is
    skipped and its stale snapshot copies removed; a registry OUTSIDE the act's
    scope is not touched at all.

    **REFUSES to CREATE the directory unless `seed=True`.** That refusal is the
    bootstrap guard: the FIRST snapshot blesses whatever text it copies, so it
    must ride the owner's own reviewed signing commit and nothing else.
    `--seed` is reachable only from `intake.py snapshot --seed`, and
    `tests/test_baseline_snapshot.py` pins that no loop module, hook or
    `check.py` contains the flag.

    **AND REFUSES TO REFRESH ONE WITHOUT AUTHORITY** (`refresh_refusal`, 2026-08-20).
    Creating was guarded and rewriting was not, which made the second act the
    cheap one: after the first signing this function re-blessed any text it was
    pointed at. Since SR-207 a refresh that would absorb a row's drifted
    APPROVED text needs that row's own `Status` flip or its id in `reattests`;
    an `approves` ref names the act and its registry and clears no row. Refs and
    re-attested ids are recorded into the snapshot's prose stamp. Traced-cell
    refreshes are unaffected and need no flag. Since WI-584 that gate is scoped
    to THIS act's
    write set, so a per-registry approval is no longer refused by drift in a
    registry the copy leaves alone — with one unscoped arm: an act that would
    copy nothing in a tree carrying drifted approved text is still refused, so
    the laundering attempt meets a message and not a silent exit 0.

    **NOTHING SHOULD EVER WIRE THIS INTO A FRESHNESS STEP.** Exactly two callers
    are sanctioned: `intake._apply_flips` (the mechanical path, called AFTER the
    status write so the copy captures the flip — which is what makes the
    unanchored rule decidable) and `intake.py snapshot` (the human path). Not
    `agent_loop`, not `dispatch`, not the hooks, not `check.py`. A step that
    REGENERATED the snapshot would defeat the whole mechanism: the snapshot is
    deliberately behind live whenever an amendment is pending, and that lag IS
    the signal.

    `verdict`, when given, is the verdict file that ruled the re-attested rows;
    the act's ledger entry records it (`_refuse_verdict` judges it first)."""
    verdict = verdict_rel(root, verdict)
    _refuse_verdict(root, verdict, reattests)
    base = snapshot_root(root)
    if not base.is_dir():
        standing, to_copy, first_signing = _seed_targets(root, base, seed, reattests)
    else:
        # The authority gate and the scope decision, keyed on the directory
        # EXISTING rather than on `seed`: creating is seeding and rewriting is
        # refreshing, whatever flag the caller passed. `--seed` against a
        # standing record is a mistake, and a mistake is exactly the thing that
        # must not sail past the check. `_refresh_targets` raises on refusal.
        # The ledger first: a refusal must leave the record untouched.
        standing = _standing_acts(root)
        to_copy, first_signing = _refresh_targets(
            root, approves, seed, base, frozenset(reattests or ())
        )
    prior = _prior_record(root)
    written = []
    copied_rels = []
    for rel in (r for r in SNAPSHOTTED if r in to_copy):
        dest = _copy_registry(root, base, rel)
        if dest:
            written.append(dest)
            copied_rels.append(rel)
    written = sorted(written)
    # Every non-seed refresh that copied a registry is stamped, so the act's
    # scope is auditable whether a `--approves` ref or a `Status` move authorised
    # it (WI-571 rework: a Status-move-only refresh copied its registry but wrote
    # no stamp, leaving that approval unauditable). `approves or {}` makes the
    # per-registry reason read "Status move" when neither a ref nor a
    # re-attested row named it. The seed and a refresh that copied nothing (a
    # traced-only re-point) write no line.
    if not first_signing and copied_rels:
        _record_approval(base, approves or {}, copied_rels, frozenset(reattests or ()))
    # Every act that copied a registry, the seed included, is an entry in the
    # typed ledger: the one record of which rows it named that a reader parses.
    if copied_rels:
        _record_act(
            base,
            standing,
            _approved_by_act(root, copied_rels, prior),
            reattests or (),
            copied_rels,
            verdict,
        )
    return written


def _seed_targets(root, base, seed, reattests):
    """`(standing acts, registries to copy, first_signing)` for an act on a
    repo with no record yet: refused unless `seed`, then the whole tree, once.
    Extracted from `copy_live` unchanged (WI-791)."""
    if not seed:
        raise SystemExit(
            "baseline_snapshot: REFUSED — {} does not exist, and creating it "
            "would bless whatever text happens to be in the tree right now. "
            "The first snapshot rides the owner's signing commit: run "
            "`intake.py snapshot --seed` there, after every pending row has "
            "been ruled.".format(base)
        )
    # Before the directory exists, so a refused seed leaves no trace.
    _refuse_reattests(root, frozenset(reattests or ()), None, True)
    base.mkdir(parents=True, exist_ok=True)
    return [], set(SNAPSHOTTED), True  # the seed blesses the whole tree, once


def _copy_registry(root, base, rel):
    """Copy one registry's live carrier into the record under `base`; the
    repo-relative path written, or None when the registry has no live carrier.
    Extracted from `copy_live`'s loop body unchanged (WI-791), so the writer
    stays under the complexity bar as it grows its verdict argument."""
    suffixes = (
        spine_carrier.NEED_CARRIERS if rel == NEEDS_REL else spine_carrier.CARRIERS
    )
    live = spine_carrier.resolve(Path(root) / rel, suffixes)
    dest_dir = base / Path(rel).parent
    # Every carrier path for this stem, so the STALE one is removed whether
    # or not a live file is being written over it. Done before the copy, so
    # a carrier change lands as delete-then-write rather than leaving both.
    for cand in spine_carrier.carriers(rel, suffixes):
        stale = base / cand
        if stale.is_file() and (live is None or stale.name != live.name):
            stale.unlink()
    if live is None:
        return None
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / live.name
    shutil.copyfile(live, dest)
    return dest.relative_to(Path(root)).as_posix()


def _prior_record(root):
    """The record as it stood before this act copied anything, or None when it
    does not read (the repair path): every approved row the act copies is then
    one it carried into approval, as it is on a seed."""
    try:
        return load_all(root)
    except SystemExit:
        return None


def _approved_by_act(root, copied_rels, prior):
    """The ids of the compared tiers' rows, in the registries this act copied,
    that it carried into approval: live rows claiming approval whose prior
    recorded copy did not, or that the prior record did not hold. The needs
    file's two tiers are compared tiers here, so an act approving a need or a
    stakeholder names it in a typed field and not only in the prose stamp.

    Implements: SR-178, LLR-271"""
    out = set()
    for rel, id_col in SNAPSHOT_TIERS:
        if rel not in copied_rels:
            continue
        before = rows_for(prior, rel, id_col)
        for row in _tier_rows(root, rel, id_col):
            rid = str(row.get(id_col) or "").strip()
            if (
                rid
                and _claims_approval(row)
                and not _claims_approval(before.get(rid) or {})
            ):
                out.add(rid)
    return out


class ActLedgerError(ValueError):
    """The act ledger is malformed: `problems` names each fault. Raised by
    `parse_acts` rather than returning the entries it could read, because an
    act left out or misnumbered is an act a reader would silently miss."""

    def __init__(self, problems):
        super().__init__("; ".join(problems))
        self.problems = list(problems)


def _date_problem(value):
    """Why `value` is not an act's ISO day, or "" when it is: a TOML date, or a
    `YYYY-MM-DD` string as `_record_act` writes it."""
    import datetime

    if isinstance(value, datetime.datetime):
        return "a date-time, not a day"
    if isinstance(value, datetime.date):
        return ""
    if isinstance(value, str) and re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
        try:
            datetime.date.fromisoformat(value)
            return ""
        except ValueError:
            pass
    return "{!r} is not an ISO day".format(value)


def _entry_problems(n, entry, last_seq):
    """The faults of the `n`th `[[act]]` entry, given the `seq` before it."""
    where = "act entry {}".format(n)
    if not isinstance(entry, dict):
        return ["{} is not a table".format(where)]
    out = []
    seq = entry.get("seq")
    if type(seq) is not int or seq < 1:
        out.append("{}: `seq` must be a positive integer, got {!r}".format(where, seq))
    elif last_seq is not None and seq <= last_seq:
        out.append(
            "{}: `seq` {} does not follow {} — numbers must be unique and "
            "increase in file order".format(where, seq, last_seq)
        )
    if "date" not in entry:
        out.append("{}: `date` is missing".format(where))
    elif _date_problem(entry["date"]):
        out.append("{}: `date` {}".format(where, _date_problem(entry["date"])))
    return out + _named_rows_problems(where, entry) + _copied_problems(where, entry)


def _copied_problems(where, entry):
    """The faults of an act entry's `copied`, when it has one: a non-empty list
    of distinct path strings in sorted order. Membership in `SNAPSHOTTED` is
    judged only for the entries a commit adds (`added_acts_problems`), so a
    later change to the registry universe never turns committed history
    malformed. An entry without `copied` is a legacy entry and no fault here.

    Implements: SR-178, LLR-361"""
    if "copied" not in entry:
        return []
    copied = entry["copied"]
    if not (
        isinstance(copied, list)
        and copied
        and all(isinstance(c, str) and c.strip() for c in copied)
    ):
        return ["{}: `copied` must be a non-empty list of registry paths".format(where)]
    if copied != sorted(set(copied)):
        return [
            "{}: `copied` must be sorted with no repeats, got {!r}".format(
                where, copied
            )
        ]
    return []


def _copied_order_problems(entries):
    """The entries that omit `copied` after an earlier entry carried it: the
    writer records it on every act once it records it on one, so a legacy
    entry only ever precedes the first recorded one.

    Implements: SR-178, LLR-361"""
    tables = [(n, e) for n, e in enumerate(entries, 1) if isinstance(e, dict)]
    first = next((n for n, e in tables if "copied" in e), None)
    return [
        "act entry {}: `copied` is missing after act entry {} carried it; every "
        "entry after the first that records its copied registries records "
        "them".format(n, first)
        for n, e in tables
        if first is not None and n > first and "copied" not in e
    ]


def _named_rows_problems(where, entry):
    """The faults of an act entry's row lists and its optional `verdict`:
    `approved` and `reattested` lists of row ids, and a `verdict`, when the
    entry has one, naming a file (a non-empty string; OI-100, WI-791)."""
    out = []
    for key in ("approved", "reattested"):
        ids = entry.get(key)
        if not isinstance(ids, list) or not all(isinstance(r, str) for r in ids):
            out.append("{}: `{}` must be a list of row ids".format(where, key))
            continue
        bad = [r for r in ids if not _ROW_ID.fullmatch(r)]
        if bad:
            out.append("{}: `{}` holds non-ids {}".format(where, key, bad))
    verdict = entry.get("verdict", "x")
    if not isinstance(verdict, str) or not verdict.strip():
        out.append("{}: `verdict` must name a verdict file".format(where))
    return out


def acts_problems(text):
    """Every fault of an act ledger's text, `[]` for a well-formed one or for
    no text at all (no ledger). Fails CLOSED: text that does not parse, an
    `act` that is not a list of tables, a missing or mistyped field (`seq` a
    positive integer, `date` an ISO day, `approved` and `reattested` lists of
    row ids, `copied`, when present, a sorted list of distinct paths), `seq`
    values that are not unique and increasing in file order, since acts are
    told apart by number alone, and an entry omitting `copied` after one that
    carries it.

    Implements: SR-202, LLR-239, SR-178, LLR-361"""
    try:
        data = tomllib.loads(text or "")
    except tomllib.TOMLDecodeError as exc:
        return ["does not parse as TOML ({})".format(exc)]
    entries = data.get("act", [])
    if not isinstance(entries, list):
        return ["`act` is not a list of `[[act]]` entries"]
    out = []
    last_seq = None
    for n, entry in enumerate(entries, 1):
        out += _entry_problems(n, entry, last_seq)
        if isinstance(entry, dict) and type(entry.get("seq")) is int:
            last_seq = entry["seq"] if last_seq is None else max(last_seq, entry["seq"])
    return out + _copied_order_problems(entries)


def parse_acts(text):
    """The act ledger's entries as `{seq, date, approved, reattested}` dicts in
    file order, with `verdict` on an entry that names one and `copied` on an
    entry that records it; `[]` for no text. A legacy entry has no `copied`
    key, never `[]`: its copy set is unknown, and nothing here infers one.
    RAISES `ActLedgerError` on a malformed ledger (`acts_problems`) rather
    than returning the entries it could read.

    Implements: SR-178, LLR-361"""
    problems = acts_problems(text)
    if problems:
        raise ActLedgerError(problems)
    return [
        dict(
            {
                "seq": entry["seq"],
                "date": str(entry["date"]),
                "approved": list(entry["approved"]),
                "reattested": list(entry["reattested"]),
            },
            **({"verdict": entry["verdict"]} if "verdict" in entry else {}),
            **({"copied": list(entry["copied"])} if "copied" in entry else {}),
        )
        for entry in tomllib.loads(text or "").get("act", [])
    ]


def _ledger_text(root):
    """The working tree's act ledger text, or None without one."""
    try:
        return (snapshot_root(root) / ACTS).read_text(encoding="utf-8")
    except OSError:
        return None


def read_acts(root):
    """The working tree's act ledger entries (`parse_acts`); `[]` without one.
    Raises `ActLedgerError` on a malformed ledger."""
    return parse_acts(_ledger_text(root))


def acts_findings(root):
    """The working tree's act ledger faults as INTEGRITY findings, each naming
    the file: `trace.py` joins them to the record's other integrity rules on
    the always-on `--strict-integrity` floor. `[]` without a ledger."""
    path = "{}/{}".format(SNAPSHOT_DIR, ACTS)
    return [
        "{}: {} — the act ledger is refused whole until it is fixed".format(path, p)
        for p in acts_problems(_ledger_text(root))
    ]


def added_acts_problems(text, parent_texts):
    """Every fault of the entries the ledger `text` adds over the ledgers in
    `parent_texts` (each None where that parent has none): an added entry
    without `copied`, or one naming a path outside `SNAPSHOTTED` in its
    canonical `.toml` spelling. Entries a parent holds are never judged, so a
    legacy history stays readable. `[]` when `text` is malformed, which the
    whole-file rule reports, and when a parent is, which no supported route
    commits.

    Implements: SR-178, LLR-361"""
    try:
        parents = [parse_acts(t) for t in parent_texts]
        added = acceptance_record.added_ledger_entries(parse_acts(text), parents)
    except ActLedgerError:
        return []
    out = []
    for entry in added:
        where = "act entry seq {}".format(entry["seq"])
        foreign = [c for c in entry.get("copied", []) if c not in SNAPSHOTTED]
        if "copied" not in entry:
            out.append(
                "{}: the commit adds it without `copied`, the registries its "
                "act copied".format(where)
            )
        elif foreign:
            out.append(
                "{}: `copied` names {} outside the snapshot's registry files".format(
                    where, ", ".join(foreign)
                )
            )
    return out


def added_acts_findings(root):
    """`added_acts_problems` for the commit being made, as INTEGRITY findings:
    the index's ledger against HEAD's, and against MERGE_HEAD's too while a
    merge is in progress. `[]` off git and before the first commit; on a
    clean tree the index is HEAD and nothing is added.

    Implements: SR-178, LLR-361"""
    head, merging = _kitgit.staged_heads(root)
    if not head:
        return []
    path = "{}/{}".format(SNAPSHOT_DIR, ACTS)
    parents = [
        _git(root, ["show", "{}:{}".format(rev, path)])
        for rev in (head, merging)
        if rev
    ]
    return [
        "{}: {} — abandon the unfinished act: restore the uncommitted ledger "
        "and snapshot copies to their committed state (`git checkout HEAD -- "
        "{}/`), keep the live registry edits it was authorised for, and take "
        "the act again with the current `intake.py snapshot`; never add "
        "`copied` to an entry by hand or edit a committed entry".format(
            path, p, SNAPSHOT_DIR
        )
        for p in added_acts_problems(_git(root, ["show", ":" + path]), parents)
    ]


def record_findings(root):
    """The record's own integrity findings, as `trace.py` joins them to the
    always-on floor: every unanchored approval (`unanchored_findings`), every
    fault of the act ledger (`acts_findings`) and every fault of the entries
    the commit being made adds to it (`added_acts_findings`).

    Implements: SR-178, LLR-361"""
    return unanchored_findings(root) + acts_findings(root) + added_acts_findings(root)


def _standing_acts(root):
    """The standing ledger's entries, or REFUSED: an act must not start on a
    ledger it cannot number its entry in. Called before the act moves any byte
    of the record, so a refusal leaves the record exactly as it stood."""
    try:
        return read_acts(root)
    except ActLedgerError as exc:
        raise SystemExit(
            "baseline_snapshot: REFUSED — {}/{} is malformed ({}); fix it before "
            "recording another act in it. Nothing was copied.".format(
                SNAPSHOT_DIR, ACTS, exc
            )
        ) from None


def _record_act(base, standing, approved, reattested, copied, verdict=None):
    """Append one act's entry to the ledger, numbered one above the `standing`
    entries `_standing_acts` read before the act began, creating the file with
    its header when the record has none. `copied` is the registries the act
    actually wrote, by their canonical `SNAPSHOTTED` paths, never a set
    reconstructed from row ids. `verdict` is written only when the act named
    one, so an entry without it keeps the shape it always had.

    Implements: SR-178, LLR-361"""
    path = base / ACTS
    text = path.read_text(encoding="utf-8") if path.is_file() else _ACTS_HEADER
    seq = max((a["seq"] for a in standing), default=0) + 1
    entry = toml_fields(
        [
            ("seq", seq),
            ("date", _today()),
            ("approved", sorted(approved)),
            ("reattested", sorted(reattested)),
            ("copied", sorted(copied)),
        ]
        + ([("verdict", verdict)] if verdict else [])
    )
    path.write_text(
        text.rstrip("\n") + "\n\n[[act]]\n" + entry, encoding="utf-8", newline="\n"
    )


def is_drifted(rel, id_col, live_row, snapshot_rows):
    """True when this row claims approval-or-above AND its APPROVED cells differ
    from its copy in the snapshot.

    A row BELOW approval is never drifted — it has made no claim to fall from,
    and a `Drafted` row differing from its snapshot copy is just work in progress.
    A claiming row ABSENT from the snapshot is not drifted either; it is
    UNANCHORED, a harder finding that `unanchored_findings` owns, and conflating
    the two would report "re-attest owed" for a row that was never approved at
    all.

    The comparison basis is `check_trajectory.split_changed_cells`, which
    already excludes the id (a join key, not content) and `Status` (the marker,
    not the amendment — folding it in would make every flip look like an
    amendment and every amendment invisible behind its own flip), and which
    already splits the remainder into the §A5.1 approved/traced halves. Only the
    APPROVED half arms drift: a re-pointed `SN-Refs`/`Verifies`/`SR-Refs` routes
    to adjudication and never arms a re-attest window (the WI-388 ruling,
    unchanged)."""
    if not _claims_approval(live_row):
        return False
    rid = str(live_row.get(id_col) or "").strip()
    before = snapshot_rows.get(rid)
    if before is None:
        return False  # unanchored, not drifted — a different finding entirely
    changed = check_trajectory.split_changed_cells(rel, id_col, before, live_row)
    return bool(changed["approved"])


def drifted_cells(rel, id_col, live_row, snapshot_rows):
    """`{cell: (before, after)}` for the approved cells `is_drifted` fired on,
    `{}` otherwise — the same call, kept beside its predicate so a renderer
    never re-derives the comparison with a second set of exclusions."""
    if not is_drifted(rel, id_col, live_row, snapshot_rows):
        return {}
    rid = str(live_row.get(id_col) or "").strip()
    return check_trajectory.split_changed_cells(
        rel, id_col, snapshot_rows[rid], live_row
    )["approved"]


def owing_rows(rel, id_col, rows, snapshot_rows):
    """`[(id, why, cells, row)]` for each row of one tier owing an act: a
    `Drafted` row, a row with no `Status` cell at all, and a row claiming
    approval whose approved cells differ from its recorded copy
    (`drifted_cells`, whose `(name, before, after)` triples `cells` carries).

    THE ROW WITH NO STATUS OWES TOO. It claims no approval, so no drift arm can
    fire on it, and it is not `Drafted`, so the first-approval arm missed it: a
    row authored without the cell reached no surface a signer reads. Its
    missing cell is also an integrity finding; this is the half that keeps the
    brief from omitting it.

    Pure: the caller loads the live rows and the recorded ones.

    Implements: SR-178, SR-157, LLR-271, LLR-272"""
    out = []
    for row in rows:
        rid = str(row.get(id_col) or "").strip()
        if not rid:
            continue
        moved = drifted_cells(rel, id_col, row, snapshot_rows)
        if is_drafted(row):
            why = "Drafted, never approved"
        elif not (row.get("Status") or "").strip():
            why = "no Status cell, never approved"
        elif moved:
            why = "DRIFTED"
        else:
            continue
        cells = [(name, b, a) for name, (b, a) in sorted(moved.items())]
        out.append((rid, why, cells, row))
    return out


def needs_owing(root, snapshot=None):
    """`owing_rows` over the needs file's two tiers (`NEED_TIERS`), needs
    first: every need or stakeholder owing an act against the recorded copy.

    Implements: SR-178, LLR-271"""
    return tier_owing(root, NEED_TIERS, snapshot)


def tier_owing(root, tiers, snapshot=None):
    """`owing_rows` over each `(registry, id column)` of `tiers`, in order:
    every row of those tiers owing an act against the recorded copy. The
    amendment brief reads it for the tiers the requirement-chain model does
    not hold — the needs, the assumptions and the surrogates (OI-100, WI-791).

    Implements: SR-178, LLR-271"""
    if snapshot is None:
        snapshot = load_all(root)
    out = []
    for rel, id_col in tiers:
        live = _tier_rows(root, rel, id_col)
        out += owing_rows(rel, id_col, live, rows_for(snapshot, rel, id_col))
    return out


def _missing_registry_findings(rel, live):
    """The finding for a registry the record lacks, as a list.

    Always one line for an established registry. For a registry in
    `FIRST_COPY_AT_APPROVAL`, none while no live row of it claims approval: its
    first copy is the approval act's to write, so its absence before then is
    the record's honest state. Split out of `unanchored_findings`, whose walk
    it would otherwise push past the complexity bar."""
    first_copy_pending = rel in FIRST_COPY_AT_APPROVAL and not any(
        _claims_approval(row) for row in live
    )
    if first_copy_pending:
        return []
    return [
        "{} is missing from the {} snapshot — the snapshot exists, so a "
        "registry absent from it is a gap in the record of what was "
        "approved, not a repo that has approved nothing".format(rel, SNAPSHOT_DIR)
    ]


def unanchored_findings(root, snapshot=None):
    """The successor to repo-lock D-9's "approved-with-no-anchor is an ERROR" —
    and, since migration step 7, an ERROR in fact.

    A row whose live maturity claims approval-or-above is UNANCHORED when the
    snapshot does not contain its id, or contains it at a maturity that makes no
    such claim. The second half is the one that matters and it is only decidable
    because the copy is a WHOLE FILE: a live row reading approved whose snapshot
    copy reads `Drafted` is an approval that never rode a copy. Row extraction
    would have deleted the very evidence this reads.

    VACUOUS UNTIL THE SNAPSHOT HOLDS A REGISTRY. Once it holds one, a registry
    MISSING from beside it is itself reported here — a half-copied record is a
    record with a hole, which is the state worth being loud about. The one
    exception is a registry that joined the record after it was first signed
    (`FIRST_COPY_AT_APPROVAL`: the assumptions registry, SR-191): its first
    copy is written by the act approving its first row, so until a live row of
    it claims approval its absence is not reported, since reporting it would
    demand a copy no act may write.

    The vacuum is "no registry" rather than "no directory", and the distinction
    is not academic: `bootstrap.py` SCAFFOLDS `docs/archive/last_approved/` with
    its README and nothing else, deliberately ("an empty snapshot is the HONEST
    state for a repo that has approved nothing yet"), so a directory test would
    report every tier missing in EVERY fresh adopter repo on day one — the
    reds-everything failure the arming note below exists to avoid, shipped
    downstream. Caught when this producer was first wired to `trace.py`
    (adversarial round 2, 2026-08-15): until then nothing called this, so
    nothing could notice. The deletion half is not lost with it — the mirror
    invariant refuses a registry deleted from a standing record in the commit
    that does it (`check_trajectory.staged_snapshot_findings`).

    **ARMED (migration step 7).** `trace.py` appends these to
    `findings.integrity`, so they fail the always-on `--strict-integrity` floor —
    and the pre-commit hook that runs exactly that command — at every gate.
    INTEGRITY rather than SCHEMA because `--strict-schema` runs at DevStg-Impl
    alone (correction C1): an approval that never rode a copy is wrong at any
    stage, exactly like a duplicated id. Nothing in this producer changed at the
    arming; what moved is the pipe it joins one level up, which is the whole
    value of having run it warn-first since step 4 — the promotion was a one-line
    change to a rule already proven quiet, not a rule nobody had seen fire.
    Arming it EARLIER would have redded every row: before the seed there was no
    snapshot, and before the rename it spoke the retired vocabulary."""
    if snapshot is None:
        snapshot = load_all(root)
    if snapshot is None:
        return []
    base = snapshot_root(root)
    if not any(spine_carrier.resolve(base / rel) for rel in SNAPSHOTTED):
        return []  # scaffolded-but-unsigned: the pre-signing state, honestly
    out = []
    for rel, id_col in SNAPSHOT_TIERS:
        live = _tier_rows(root, rel, id_col)
        if _copy_file(base, rel) is None:
            out += _missing_registry_findings(rel, live)
            continue
        before = rows_for(snapshot, rel, id_col)
        for row in live:
            rid = str(row.get(id_col) or "").strip()
            if not rid or not _claims_approval(row):
                continue
            snap = before.get(rid)
            if snap is None:
                out.append(
                    "{} reads Status={} but is ABSENT from the {} snapshot — "
                    "an approval that never rode a copy (adding a row and "
                    "approving it must be one act)".format(
                        rid, (row.get("Status") or "").strip(), SNAPSHOT_DIR
                    )
                )
            elif not _claims_approval(snap):
                out.append(
                    "{} reads Status={} but its {} copy reads Status={} — the "
                    "approval was written without copying the text it blessed".format(
                        rid,
                        (row.get("Status") or "").strip(),
                        SNAPSHOT_DIR,
                        (snap.get("Status") or "").strip() or "(unset)",
                    )
                )
    return sorted(out)


# --- THE ACCEPTED RISK'S ANCHOR (SR-202) ---------------------------------------
# A recorded accepted risk is a judgment about one assumption serving particular
# needs, made in an approval act, so it is bound to their texts as the act saw
# them. The act is found in the history of the record this module writes: the
# act ledger's entries name the acts, and the record's copy of the assumptions
# registry at each says what risk it recorded. The comparison itself is
# `assumption_rules.accepted_risk_state`, a pure rule; this side only reads git.

ASSUMPTIONS_REL = "docs/requirements/assumptions.toml"
_REQUIREMENTS_REL = "docs/requirements/system-requirements.toml"
# The two readers the acceptance record's two-tree comparison already uses,
# through the re-exports this module reads `split_changed_cells` by.
_git = check_trajectory._git


def _shallow_commits(root):
    """The commits a shallow clone cut the parents from, as a set; empty for a
    whole history. Their diff reads as if every file were added there, so no act
    can be judged at one."""
    path = _git(root, ["rev-parse", "--git-path", "shallow"])
    if not path:
        return frozenset()
    shallow = Path(root) / path.strip()
    try:
        return frozenset(shallow.read_text(encoding="utf-8").split())
    except OSError:
        return frozenset()


def _recorded_assumption(root, rev, da_id):
    """The assumption's row in the record's copy at `rev`, or None."""
    rows = check_trajectory._spine_rows_at(
        root, rev + ":", SNAPSHOT_DIR + "/" + ASSUMPTIONS_REL, "DA-ID"
    )
    return rows.get(da_id)


def _acts_at(root, sha):
    """The act ledger entries the commit `sha` added: those whose `seq` its
    parent's ledger does not hold, every entry at a root commit. Compared by
    number, never by content, so a second act identical to the first is still
    an act of its own."""
    path = "{}/{}".format(SNAPSHOT_DIR, ACTS)
    new = parse_acts(_git(root, ["show", "{}:{}".format(sha, path)]))
    old = parse_acts(_git(root, ["show", "{}^:{}".format(sha, path)]))
    return acceptance_record.added_ledger_entries(new, [old])


def _act_names(root, sha, da_id):
    """Whether an act that landed at `sha` names the assumption, as approved or
    as re-attested."""
    return any(
        da_id in act["approved"] or da_id in act["reattested"]
        for act in _acts_at(root, sha)
    )


def _risk_first_written(root, da_id):
    """The fallback anchor: the first commit at which the live row's
    `accepted_risk` took its current value, walking back until it differs."""
    live = {
        str(r.get("DA-ID") or "").strip(): r
        for r in spine_carrier.load(Path(root) / ASSUMPTIONS_REL, "DA-ID")
    }.get(da_id) or {}
    current = (live.get("AcceptedRisk") or "").strip()
    log = _git(
        root, ["log", "--format=%H", "--", *spine_carrier.carriers(ASSUMPTIONS_REL)]
    )
    anchor = None
    for sha in (log or "").split():
        row = check_trajectory._spine_rows_at(
            root, sha + ":", ASSUMPTIONS_REL, "DA-ID"
        ).get(da_id)
        if row is None or (row.get("AcceptedRisk") or "").strip() != current:
            break
        anchor = sha
    if anchor is None:
        return None, (
            "{}'s accepted risk is in no commit yet; commit it, or accept it in "
            "an approval act".format(da_id)
        )
    return anchor, (
        "no approval act names {}, so its risk is bound to {}, the first commit "
        "at which it took its current value".format(da_id, anchor[:12])
    )


def risk_acceptance_act(root, da_id):
    """`(commit, reason)`: the act an assumption's accepted risk is bound to.

    The latest commit whose approval act names the assumption while its
    recorded `accepted_risk` is non-empty. An act names it when the act ledger
    entry it added lists the row approved or re-attested (`_acts_at`):
    re-accepting a risk IS re-attesting the row in an act, so it moves the
    anchor even when no byte of the row changes, and each act is its own entry,
    so the latest act moves it even when an earlier one the same day named the
    same rows in the same words. The README beside the ledger is prose and is
    never read. Only where no act names the row at all does the anchor fall
    back to the first commit at which its live `accepted_risk` took its current
    value (`_risk_first_written`).

    `(None, reason)` when no anchor can be read, each a reason the caller
    states: a shallow clone whose window holds no such act, since the act may
    lie beyond it; acts naming the row but none recording a risk, since
    accepting one is an act of its own; an act ledger on the walk that is
    malformed (`acts_problems`), since which acts it holds would be a guess;
    or no git at all. Time is never read.

    Implements: SR-202, LLR-239
    """
    log = _git(root, ["log", "--format=%H", "--", SNAPSHOT_DIR + "/" + ACTS])
    if log is None:
        return None, "git cannot read this repository's history"
    shallow = _shallow_commits(root)
    named = False
    for sha in log.split():
        if sha in shallow:
            continue
        # Every ledger on the walk is read whole: a malformed one cannot say
        # which acts its commit added, so the anchor is refused, not guessed.
        try:
            names = _act_names(root, sha, da_id)
        except ActLedgerError as exc:
            return None, (
                "the act ledger {}/{} at commit {} or its parent is malformed "
                "({}); no approval act can be read until it is repaired".format(
                    SNAPSHOT_DIR, ACTS, sha[:12], exc
                )
            )
        row = _recorded_assumption(root, sha, da_id) if names else None
        if row is None:
            continue
        named = True
        if (row.get("AcceptedRisk") or "").strip():
            return sha, "the approval act {} accepted its risk".format(sha[:12])
    if shallow:
        return None, (
            "history too shallow to find the approval act accepting {}'s risk: "
            "this is a shallow clone, and the act may lie beyond its window; "
            "fetch the full history".format(da_id)
        )
    if named:
        return None, (
            "the approval acts naming {} recorded no accepted risk; accepting "
            "one is re-attesting the row in an act".format(da_id)
        )
    return _risk_first_written(root, da_id)


def _needs_at(root, sha):
    """`{need id: need}` as the needs registry stood at `sha`, either carrier,
    read under the carrier of the file that commit held and refusing, naming the
    commit and the file, a `.toml` one that does not parse: an unreadable file
    must not read as a need set a risk was accepted against.

    Implements: SR-147, LLR-277"""
    for cand in spine_carrier.carriers(NEEDS_REL, spine_carrier.NEED_CARRIERS):
        text = _git(root, ["show", "{}:{}".format(sha, cand)])
        if text is not None:
            needs = spine_carrier.needs_or_refuse("{}:{}".format(sha, cand), text)
            return {str(n.get("id") or ""): n for n in needs if n.get("id")}
    return {}


def _records_at(root, sha):
    """The observation record names the tree at `sha` held."""
    out = _git(root, ["ls-tree", "-r", "--name-only", sha, "--", OBSERVATIONS_DIR])
    return {Path(line).name for line in (out or "").splitlines() if line.strip()}


def risk_acceptance_view(root, da_id):
    """What `assumption_rules.accepted_risk_state` compares for one assumption,
    as a dict: the anchor `act` and its `reason` (`risk_acceptance_act`), and,
    at that commit, the `assumption` row, the requirement rows `srs` its served
    needs are derived through, the `needs` keyed by id, and the observation
    record names the tree held (`known`), which is what orders a failed sample
    by ancestry rather than by the instant it names. Only `act` and `reason`
    when there is no anchor.
    """
    act, reason = risk_acceptance_act(root, da_id)
    if act is None:
        return {"act": None, "reason": reason}
    return {
        "act": act,
        "reason": reason,
        "assumption": check_trajectory._spine_rows_at(
            root, act + ":", ASSUMPTIONS_REL, "DA-ID"
        ).get(da_id),
        "srs": list(
            check_trajectory._spine_rows_at(
                root, act + ":", _REQUIREMENTS_REL, "SR-ID"
            ).values()
        ),
        "needs": _needs_at(root, act),
        "known": _records_at(root, act),
    }
