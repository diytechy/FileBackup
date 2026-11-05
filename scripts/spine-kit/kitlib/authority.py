"""Approval authority: which rung a registry's status cells are approved into,
whether a declared approval level holds that rung for a human, and what the
dial a chosen tree declares is.

WHY IT IS A MODULE OF ITS OWN (LLR-249). Every reader that asks "does the dial
hold this rung" asks it here: the loop's own writers before they commit, the
pre-commit `held-status` step, the merge slot, and the HISTORY CHECK, which
reads each past commit's own tree. None of them may reach for the coordinator's
primitives to ask a question about a string and a table, and none may print a
migration note per commit or per hook run, so the comparison, the rung tables
and the dial readers live here, below all of them, and `agent_common`
re-exports the tables under the names every caller already uses. One table and
one comparison, so the loop's refusal and the history's report cannot disagree
about which rung is held.

THE RUNG MAPS, and the fail-safe they share:

  * `APPROVAL_RUNGS` keys the OFF-SPINE registries that carry a status cell by
    their stem. The association is existing fact (`spine_rules` gates the
    Boundary rung on the frame and the Arch rung on the components), not a new
    declaration. The assumptions registry sits at the frame's rung: an
    assumption lands on a boundary crossing, and is approved with the frame it
    lands on.
  * `SPINE_APPROVAL_RUNGS` keys the spine registries by path stem. It is also
    the mint's table (which Drafted rows a merge hands an adjudicator), so it
    names only what the mint asks about.
  * `NEEDS_REGISTRY` is the one file that carries two tiers: the needs (a spine
    tier) and the stakeholder list (an off-spine one). Both are approved at
    `DevStg-Needs` - `spine_rules` derives that rung while a need is still
    drafted - so `rung_for` answers it for the file without widening the
    mint's table.
  * A registry none of them names is held (`rung_for` answers None and every
    caller reads None as the human's), because a status nobody has associated
    with a rung is one nobody has released.

THE DIAL, READ TWO WAYS, for two different questions:

  * `dial_at(root, rev)` is THE LIVE READER: the dial a chosen commit's tree,
    or the index, declares, with every legacy spelling the live loop has ever
    accepted translated exactly as `agent_common.approval_through` translates
    it (`read_dial` is the one resolution both run), printing nothing. The
    writers, the pre-commit step and the merge slot all read the dial through
    it, from a tree they name, never from a primary checkout's working file,
    where an uncommitted owner edit could strengthen or weaken the judgement
    of a tree built from HEAD. The migration note a legacy spelling deserves
    is presentation, printed only by `agent_common.approval_through` for the
    one working tree a person can migrate.
  * `dial_from_config(policy)` is THE HISTORY READER: an absent, legacy or
    unrecognised value reads as the MOST-held rung. Applied to a past commit,
    translation would guess, in the less-held direction, what a dial that
    predates the ladder meant for the rows of its day; the history check only
    ever reports, so the conservative end costs a line, never a refusal.

Pure data and comparisons over `kitlib.ladder`, plus one git read (`dial_at`,
through `kitlib.git`); no argv, and nothing printed.

Contracts: IF-195 — the interface seam this module declares (process.md §8;
row of record in docs/requirements/interfaces.toml).

Contract IF-195: the approval-authority vocabulary, by importer.
    `APPROVAL_RUNGS` (off-spine registry stem -> rung) and
    `SPINE_APPROVAL_RUNGS` (spine registry path stem -> rung) are the one pair
    of tables; `rung_for(registry)` maps a registry path, stem or bare name to
    its rung - the needs file, both of its tiers, to `DevStg-Needs` - or None
    when nothing maps it, which every caller reads as held.
    `read_dial(policy, gate_policy)` resolves a parsed policy (and, only when
    no dial is declared, the retired one-word gate-policy value, given as a
    string or a zero-argument callable) to `(rung, legacy)`, where `legacy` is
    None or a dict naming the retired `key` read and the `ordinal` translated
    (None when only the key name was retired); `dial_at(root, rev="HEAD")`
    returns that rung for `rev`'s tree, or the index's when `rev` is None,
    printing nothing, and the most-held rung when nothing is declared or git
    cannot answer. `dial_from_config(policy)` returns the `[attestation]
    human_approval_through` rung of a parsed policy, `DevStg-Below` included,
    or the most-held rung for anything absent, legacy or unrecognised,
    printing nothing. `holds_under(dial, rung)` is True when the dial holds the
    rung for a human: never at `DevStg-Below`, always for an unrecognised dial
    or rung, otherwise when the rung sits at or below the dial on the ladder.
"""

import tomllib

from . import git as _git
from . import ladder, stage

# THE OFF-SPINE MAP (owner ruling OI-30 D3, 2026-08-15; moved here from
# agent_common by LLR-249, which re-exports it). Keyed by the registry's stem.
APPROVAL_RUNGS = {
    "external": ladder.STAGE_BOUNDARY,
    "interfaces": ladder.STAGE_ARCH,
    "components": ladder.STAGE_ARCH,
    "assumptions": ladder.STAGE_BOUNDARY,
}

# THE SPINE MAP (owner ruling 2026-09-01, WI-572; moved here with its sibling).
# Keyed by the registry's path stem, the key `spine_carrier.stem` produces.
SPINE_APPROVAL_RUNGS = {
    "docs/requirements/system-requirements": ladder.STAGE_REQS,
    "docs/requirements/low-level-requirements": ladder.STAGE_LLREQS,
    "docs/test/test-cases": ladder.STAGE_TESTS,
}

# The needs file's path stem: both of its tiers, the needs and the stakeholder
# list, are approved at the needs rung.
NEEDS_REGISTRY = "docs/requirements/stakeholder-needs"

DIAL_KEY = "human_approval_through"

# Every rung at or below the top one is held: the conservative end.
MOST_HELD = ladder.STAGE_RELEASE

# Where a tree declares its dial, and the retired one-word file that declared
# it before `docs/process.toml` existed.
POLICY_PATH = "docs/process.toml"
GATE_POLICY_PATH = "docs/gate-policy"

# THE LEGACY SPELLINGS the live loop still reads, one home each (agent_common
# re-exports them for the migrator and the config validator):
#   * the retired 0-4 ordinal, which holds exactly the rung set it always held;
#     an int outside 0-4 was malformed before the re-key and stays malformed;
LEGACY_DIAL_ORDINALS = {
    0: stage.BELOW,
    1: ladder.STAGE_BOUNDARY,
    2: ladder.STAGE_ARCH,
    3: ladder.STAGE_LLREQS,
    4: ladder.STAGE_RELEASE,
}
#   * the retired key name, read as the live key when the live key is absent;
LEGACY_DIAL_KEY = "human_ratification_through"
#   * the retired `gate-policy` enum (`[attestation] gate_policy`, else the
#     one-word file), whose dial half lives here and whose other two halves are
#     `agent_common.LEGACY_APPROVAL`'s. Undeclared reads as "attended".
LEGACY_GATE_KEY = "gate_policy"
LEGACY_GATE_DIALS = {
    "attended": ladder.STAGE_RELEASE,
    "single-approve": stage.BELOW,
    "autonomous": stage.BELOW,
}
LEGACY_GATE_DEFAULT = "attended"


def rung_for(registry):
    """The rung `registry`'s status cells are approved into, or None when no
    map names it — which every caller reads as HELD. Accepts a path under
    either carrier, a path stem, or a bare stem such as `"external"`."""
    path = str(registry or "").strip().replace("\\", "/")
    stem = path[: -len(".toml")] if path.endswith(".toml") else path
    stem = stem[: -len(".csv")] if stem.endswith(".csv") else stem
    if stem in SPINE_APPROVAL_RUNGS:
        return SPINE_APPROVAL_RUNGS[stem]
    name = stem.rsplit("/", 1)[-1].lower()
    if name == NEEDS_REGISTRY.rsplit("/", 1)[-1]:
        return ladder.STAGE_NEEDS
    return APPROVAL_RUNGS.get(name)


def _is_dial(value):
    return isinstance(value, str) and (
        value.strip() in ladder.LADDER_RUNGS or value.strip() == stage.BELOW
    )


def dial_from_config(policy):
    """`[attestation] human_approval_through` from a parsed policy file, as a
    rung or `DevStg-Below`; the most-held rung for anything else, silently.
    The HISTORY reader (see the module docstring for why it does not
    translate).

    Implements: SR-210, LLR-249
    """
    table = policy.get("attestation") if isinstance(policy, dict) else None
    value = table.get(DIAL_KEY) if isinstance(table, dict) else None
    return value.strip() if _is_dial(value) else MOST_HELD


def read_dial(policy, gate_policy=None):
    """`(rung, legacy)`: the dial a parsed policy declares, every legacy
    spelling translated, and which legacy spelling was read. THE resolution
    every live reader runs (`dial_at`, `agent_common.approval_through`), so the
    pre-commit step, the writers, the slot and the coordinator cannot disagree
    about what a dial means.

    `[attestation] human_approval_through` names a rung or `DevStg-Below`; a
    retired 0-4 ordinal is translated (`LEGACY_DIAL_ORDINALS`); the retired key
    name is read when the live key is absent. Any other declared value is
    MALFORMED and reads as the most-held rung, never a best guess, because
    every wrong guess fails toward less human involvement. With no dial
    declared, the retired gate-policy enum decides: `[attestation] gate_policy`
    when it is a string, else `gate_policy` - the one-word file's value, or a
    zero-argument callable returning it, called only then, so a caller reads
    that file only when it matters - else "attended". An unknown word is the
    most-held rung.

    `legacy` is None, or `{"key": ..., "ordinal": ...}` naming the key that was
    read and the ordinal translated (None when only the key name was retired):
    what a caller that PRESENTS a migration note needs. Prints nothing.

    Implements: SR-208, LLR-246
    """
    table = policy.get("attestation") if isinstance(policy, dict) else None
    table = table if isinstance(table, dict) else {}
    value, key = table.get(DIAL_KEY), DIAL_KEY
    if value is None and DIAL_KEY not in table and LEGACY_DIAL_KEY in table:
        value, key = table.get(LEGACY_DIAL_KEY), LEGACY_DIAL_KEY
    if _is_dial(value):
        retired = {"key": key, "ordinal": None} if key == LEGACY_DIAL_KEY else None
        return value.strip(), retired
    if isinstance(value, int) and not isinstance(value, bool):
        rung = LEGACY_DIAL_ORDINALS.get(value)
        if rung is None:
            return MOST_HELD, None
        return rung, {"key": key, "ordinal": value}
    if value is not None:
        return MOST_HELD, None
    word = table.get(LEGACY_GATE_KEY)
    if not isinstance(word, str):
        word = gate_policy() if callable(gate_policy) else gate_policy
    word = LEGACY_GATE_DEFAULT if word is None else str(word)
    return LEGACY_GATE_DIALS.get(word.strip().lower(), MOST_HELD), None


def _first_declared(text):
    """The first non-blank, non-comment line of a one-word policy text, or None:
    `kitlib.config.first_declared_line`, over a blob instead of a file."""
    for line in (text or "").splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            return line
    return None


def dial_at(root, rev="HEAD"):
    """THE LIVE DIAL OF A CHOSEN TREE: the rung `rev`'s committed tree declares,
    or the INDEX's when `rev` is None, every legacy spelling translated
    (`read_dial`), printing nothing.

    Read from git, never from a working file, because every live question about
    the dial is a question about a TREE: the tree a writer is about to commit
    onto, the commit a hook is about to make, the trunk a lane merges into. An
    uncommitted edit in a primary checkout is none of those, and reading it let
    an owner's half-made edit release (or hold) a commit built from HEAD. A
    policy file git cannot show, or that does not parse, declares nothing, so
    the retired gate-policy file in the same tree decides; with neither the
    answer is the most-held rung, so no git, no repository and an unknown rev
    all fail toward the human.

    Implements: SR-208, LLR-246
    """
    prefix = ":" if rev is None else "{}:".format(rev)
    text = _git.git_out(root, ["show", prefix + POLICY_PATH])
    try:
        policy = tomllib.loads(text.lstrip("﻿")) if text else {}
    except tomllib.TOMLDecodeError:
        policy = {}

    def gate_policy():
        return _first_declared(_git.git_out(root, ["show", prefix + GATE_POLICY_PATH]))

    return read_dial(policy, gate_policy)[0]


def holds_under(dial, rung):
    """Does `dial` hold `rung` for a human? Nothing at `DevStg-Below`; every
    rung at or below the dial otherwise; and an unrecognised dial or rung is
    HELD, because the only safe answer to "I do not recognise this" is "the
    human approves it".

    Implements: SR-210, LLR-249
    """
    if dial == stage.BELOW:
        return False
    if dial not in ladder.LADDER_RUNGS or rung not in ladder.LADDER_RUNGS:
        return True
    return ladder.stage_ord(rung) <= ladder.stage_ord(dial)
