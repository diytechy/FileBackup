#!/usr/bin/env python3
"""Traceability join + orphan report for the SN->SR->LLR->TC registries.

Stack-agnostic reference implementation (Python 3, standard library only — no
pip installs). Drop it in a new repo as `scripts/trace.py` and wire it into the
check harness / CI. It is the generated "traceability matrix" referenced by
PROCESS.md: it never needs hand-maintaining.

Usage:
    python scripts/trace.py [--strict] [--strict-integrity] [--require-verified]
                            [--phase LIST] [--no-placeholders] [--strict-schema]
                            [--html] [--approve SCOPE [--out FILE]]
                            [--root DIR] [--docs DIR]

Reads (under --docs, default "<root>/docs"; --root defaults to "."): the spine —
    requirements/{stakeholder-needs,system-requirements,low-level-requirements}.toml
    and test/test-cases.toml — id-keyed TOML read through `spine_carrier`, which
    still resolves the legacy stakeholder-needs.md / *.csv carriers for a repo
    that has not migrated (a need is unapproved per its `status` field, or, on
    the markdown carrier, under a heading containing "draft", §4a) — plus the
    OPTIONAL off-spine registries requirements/{components,interfaces}.toml and
    requirements/{performance-budgets,repos,procurement,assets}.csv
    (CMP/IF + PB/REPO/PART/ASSET, each documented on its own *.template.* and in
    process.md §8/§9 + process-options.md; the legacy modules.csv/MOD- form is
    still read). Absent optional files and "-000" example rows are ignored, so a
    fresh scaffold is green.

Writes:
    test/report.md — counts, the SR->LLR->TC matrix, the orphan/integrity/
        advisory sections, and two rendered views of the same join: a
        line-reviewable SN->SR->LLR->TC outline and a small, diff-friendly Mermaid
        DAG colored by orphan/draft state.
    test/report.html (only with --html) — a dependency-free, collapsible <details>
        tree of the full graph (inline CSS, zero JS). A gitignored composite
        artifact, never the review surface — review the registries themselves
        (process.md §3 "Reviewability").

Exit: 0 normally; --strict -> 1 on any orphan / status / off-spine finding;
--strict-integrity -> 1 on an integrity finding ONLY (the always-valid floor the
pre-commit hook runs on every commit — a duplicate/malformed id is wrong at any
stage, while orphans are a DevStg-Tests+ gate criterion).

The method rules this script mechanizes are stated ONCE elsewhere — they are NOT
restated here (the kit's decompose-don't-paraphrase rule applied to itself):
    - the orphan rules (an SR needs an LLR unless Verification is
      Analysis/Inspection/Attest, a TC, and — when a needs file exists — an SN;
      LLR/TC parentage), the Drafted child-completeness exemption, and the
      Drafted->Approved ladder: process.md §4 + the derived-gate model
      (docs/archive/specs/derived-gate-model.2026-07-20.md §3, and §4a for section-as-state SN
      maturity).
    - the always-on structural-integrity floor (a CSV data row whose column count
      differs from its header, a duplicate/malformed SR/LLR/TC/PB/REPO/CMP/IF id,
      and the SR;LLR citation-coherence rule) and the off-spine back-link rules
      (every PB/REPO/CMP/IF row resolves to the spine): process.md §4/§8/§9 +
      process-options.md.
    - phased delivery (--phase scopes --require-verified to listed/blank-Phase
      SRs and reports the rest as phase-deferred; orphan rules stay phase-blind)
      and the closed vocabularies --strict-schema enforces (SR Verification, TC
      Tier): process.md §4.

Flags in brief: --require-verified adds the DevStg-Impl criterion "an SR is
Status=Approved" — any Verification method (Drafted SRs exempt); --no-placeholders flags leftover "-000"
example rows (wire in from DevStg-Tests on); --strict-schema adds required-field,
closed-vocabulary, and "Automated=Yes cites Evidence" checks over the real rows;
--approve SCOPE emits ONLY the batch-scoped approval hierarchy (a phase tag or
an SR-id list) to stdout or --out and runs no checks (WI-146); the reserved scope
`modified` (WI-316) emits the re-attestation brief instead — per-cell
before/after for every row owing a human act, against its copy in the
`docs/archive/last_approved/` snapshot (`baseline_snapshot.py`); regenerate it
to `docs/ratify/CURRENT.md`, the one file this path ever rewrites; the
reserved scope `assumptions`, or a DA-/SUR-id list, emits the assumption
section alone, the one both briefs carry (SR-203). `--mint-
approval-brief SLUG` (WI-503) copies CURRENT.md to a dated, IMMUTABLE
`docs/ratify/<date>-SLUG.md` — the only sanctioned writer of a dated brief;
`check.py --approval-immutable` refuses any other commit that touches one. Warn-only
advisories (loud on stdout + in the report, never gating): an unpinned
comparative acceptance-criterion, an LLR reading below Approved while every
citing TC is Approved (WI-129), a missing knowledge pack, and an interface
endpoint that resolves to no LLR Module. The report always carries the
attested-vs-mechanized approval split (process.md §4 "Attest") and, when the SR
registry tags Aspect, a per-aspect count.

Contracts: IF-001, IF-042, IF-075, IF-089, IF-101, IF-141, IF-145, IF-146, IF-166, IF-176, IF-233
— the interface seams this module declares (process.md §8; rows of record in
docs/requirements/interfaces.toml).

Contract IF-001: SR-157's obligation delivered as a CLI here. Joins the
    SN -> SR -> LLR -> TC spine with the off-spine registries under `--docs`
    and prints the orphan, integrity, status and advisory findings on stdout
    for the harness to capture and print whole, never summarised away. An
    absent optional registry and a `-000` example row are ignored, so a fresh
    scaffold reports clean instead of failing.
Contract IF-042: the always-valid integrity floor, run over staged content.
    `--strict-integrity` exits 1 when an integrity finding exists — a duplicate
    or malformed id, a data row whose column count differs from its header, an
    incoherent SR;LLR citation pair, an id-watermark breach — and 0 otherwise.
    Orphan and status findings are gate-scoped and never gate this flag, so the
    floor is safe to run on every commit at any stage.
Contract IF-075: `reattest_model(root, srs, llrs, tcs, snapshot=...)`, reached
    through `load_registries(docs)` — the ONE computation of what a spine row
    owing a human act looks like against its copy in
    `docs/archive/last_approved/`: the chain rows, each row's changed cells
    before and after, and the baseline revision and date. It returns structured
    entries rather than text, so every renderer consumes this model and none
    re-derives it; `reattest_lines` renders the same entries as the markdown
    brief. `snapshot=None` compares against nothing and falls back to the
    first-approval arm alone. An EMPTY model is a real answer, not a failure —
    no row differing from its snapshot copy and none awaiting a first approval
    means there is nothing to judge — and the caller is handed that emptiness
    to refuse on instead of a fabricated brief.
Contract IF-089: `load_registries(docs)` then `analyze(reg, AnalysisFlags(...))`
    — the single orphan/status engine offered as a library call.
    `load_registries` loads and analyses nothing; `analyze` is pure over the
    loaded bag, does no I/O, and returns the findings bag whose `orphans` and
    `status_findings` name the registry gaps. Absent optional registries load
    empty, so a scaffold with no spine yields no findings rather than an error.
Contract IF-101: `read_watermark(root) -> {space: int}` reads
    `docs/id-watermark`, the only record of which ids have ever been allocated,
    and RAISES on an absent or malformed file rather than degrading to zero —
    the degrade would free every id space at once. It supplies the floor a mint
    counts from: the next id in a space is `max(mark, live maximum) + 1`, so an
    id held anywhere is an id taken. `bump_watermark(root) -> (marks, raised)`
    records the result, raising every mark to the live maximum, propagating a
    malformed file's error and starting from zero only on the file's first
    creation, so a mark only ever rises and a deleted id is never re-minted. It
    reads the LIVE tree, so a minting caller may only call it once the minted
    artifact is on disk, or it records a number nothing holds. It carries every
    `# reservation: <SPACE> <low>-<high> (<WI-NNN>)` record verbatim, as every
    writer of the file does. `reserve_ids(root, wi, counts) -> ranges` reserves
    ids for a work item the trunk claim holds on the id carrier
    (`refs/heads/id-carrier`, one commit per reservation, moved by
    compare-and-swap), for every watermark space except WI, OI and DP, which
    stay trunk-minted; each range starts one above the larger of the carrier's
    mark and trunk's committed mark, and every refusal writes nothing.
    `fold_watermark(root)` folds the carrier tip's records, and the marks they
    justify, into the working file, both sides of a conflicted one included:
    each space's maximum, the union of the records, and the basis from the
    live ids. `landing_id_refusal(root,
    landing_rev, parent_rev, wi_ids, claim_source=...) -> refusal or None` is
    the one landing check both landing routes ask (the merge slot passes the
    lane's base, its merge base with trunk, as the parent; a hand squash,
    HEAD). A landing adding no carrier-space id passes. Otherwise the ids live in the landing tree and
    not in its parent must sit in a carrier record naming one of the claimed
    work items, and the landing's watermark may carry no record that neither
    the carrier nor the parent holds; ids added with no carrier, or with no
    claimed work item (`claim_source` names the claim read), refuse.
    `landing_fold_lag(root, rev) -> lines` names how the watermark at a
    commit or the index's tree lags the carrier's fold: a recorded carrier
    mark above its own, or a carrier record it lacks; [] with no carrier.
Contract IF-141: `effective_hats(row, sr_by_id) -> sorted hat names` — one
    design row's effective perspective set: its own `Hat-Refs` unioned with
    those of its SR parents, derived on every read instead of copied down at
    authoring time, so a re-ruled parent propagates with no child edit. A
    dangling `SR-Refs` contributes nothing and does not raise; unresolved
    parentage is the orphan pass's finding, not this derivation's.
Contract IF-145: the gate verdict the harness reads back from this CLI. Every
    checking arm answers in 0 and 1: `--strict` exits 1 when any orphan,
    status, integrity, placeholder, schema or off-spine finding exists;
    `--strict-integrity` exits 1 on an integrity finding alone, leaving the
    gate-scoped classes ungated; `--approve modified --check` exits 1 only when
    a brief exists, a row still owes a human act, and the rendered text differs
    from the file. Without a strict flag a checking run exits 0 having still
    printed every finding, so a harness reading the code alone must pass one.
    The writer arms (`--bump-ids`, `--reserve-ids`, `--fold-ids`,
    `--correct-mark`, `--mint-approval-brief`) and the `--tests-for` listing
    run no checks and exit on their own refusal instead.
Contract IF-146: `docs/test/report.md`, rewritten whole on every checking run
    under `--docs`. It carries the metric counts, the SR -> LLR -> TC matrix,
    the orphan, integrity, status and advisory sections, the flag-gated
    off-spine, draft, area and status sections, the attested-vs-mechanized
    approval split, and two renderings of one join: a line-reviewable
    SN -> SR -> LLR -> TC outline and a small, diff-friendly Mermaid DAG
    coloured by orphan and draft state. It is a composite artifact written for
    reading, never a parsing surface: no reader is promised a stable grammar,
    and the reviewed truth stays the registries it joins.
Contract IF-166: `docs/test/report.html`, written only under `--html` and
    rewritten whole on every run that passes it — a run without the flag leaves
    whatever the last one wrote. One self-contained page, inline CSS and zero
    JS, carrying the SN -> SR -> LLR -> TC forest as a collapsible `<details>`
    tree: every node labelled with its status, its orphan flag and its title,
    orphan and draft nodes coloured. It renders the join `docs/test/report.md`
    states and promises no parser a grammar.
Contract IF-176: `open_item_states(root) -> {OI-###: status} | None` — the
    one reading of `docs/requirements/open-items.toml` the scheduler's
    readiness gate shares with the spine checks. Each minted row maps to its
    `status` stripped and lowercased; a `-000` example row, and a row whose id
    does not start `OI-`, is left out. An absent registry answers None, never
    `{}`: None means there is nothing to resolve an open-item edge against,
    while an empty map means every named id is unresolved. The caller reads the
    answer and writes nothing back.

Contract IF-233: `--tests-for MODULE` prints, one per line and sorted, the test
    files the spine links to a module: the design rows whose `Module` cell
    names it, the test cases whose `Verifies` names one of those rows, and the
    paths under the declared test root (`stack.ini` `[paths] tests` in the docs
    directory, default `tests`) in those cases' `Evidence`. The registries and
    `stack.ini` are read from the directory `--docs` names, else
    `<root>/docs`. MODULE is a declared module
    path, a trailing part of one, or a stem. It runs no checks and exits 0 with
    the listing, possibly empty; 1 when no design row names a module MODULE
    matches; 2, naming the candidates, when it matches more than one.
"""

import argparse
import csv
import io
import datetime
import re
import sys
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

# The console guard's one home is the shipped package (WI-448 / D-8);
# aliased to the module-local name so no call site changes.
from kitlib.config import assumption_gate_enabled, read_stack_ini
from kitlib.config import utf8_console as _utf8_console

# THE SHIPPED SHARED-HELPER PACKAGE (owner ruling D-8, `OI-16`, executed
# WI-448): the best-effort-off-git subprocess pattern this module used to spell
# out itself. Run as a subprocess this script's own dir is sys.path[0] so a
# plain import resolves; the guard covers an in-process import (a test) whose
# sys.path does not yet carry scripts/.
#
# `kitlib.spine` joined at WI-448 slice 3: the ROW vocabulary this module used to
# duplicate against `spine_rules.py` — the Status predicates, the LLR-exemption
# set, the phase parse, the SN id scrapes and the registry CSV loader. Nine
# duplicated bodies held equal by nine `tests/test_rule_sync.py` pins; one home
# instead, so the drift is unrepresentable rather than detected.
try:
    from kitlib import git as _kitgit
    from kitlib import registry as _registry
    from kitlib import spine as _spine
except ImportError:  # pragma: no cover - in-process fallback
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from kitlib import git as _kitgit
    from kitlib import registry as _registry
    from kitlib import spine as _spine

# Sibling: the spine-row TEXT layer (WI-329). Run as a subprocess this script's
# own dir is sys.path[0] so a plain import resolves; the guard covers an
# in-process import (a test) whose sys.path does not yet carry scripts/ — the
# same sanctioned-sibling-import idiom agent_loop and gen_trajectory use.
#
# `baseline_snapshot` and (through it) `check_trajectory` joined at D-9 step 4:
# the re-attestation model's baseline is the `last_approved` snapshot, and its
# cell comparison is `check_trajectory.split_changed_cells` — the SAME function
# the amend-without-flip warn reads, which is what stops the brief and the warn
# from ever disagreeing about which cells are normative. This is the one new
# import edge the snapshot design declares.
try:
    import baseline_snapshot
    import check_trajectory
    import spine_carrier
    from coherence import (
        PhaseScope,
        _repo_id,
        budget_backlink_findings,
        component_membership_findings,
        delegation_findings,
        knowledge_pack_advisories,
        llr_module_ids,
        spine_orphan_findings,
        status_criterion_findings,
    )
    from frame_rules import frame_system_findings, sr_system_advisories
    from frame_rules import need_source_findings, source_documents, stakeholder_findings
    from assumption_rules import assumption_tier_findings
    from frame_rules import mediation_findings
    from assumption_rules import assumption_reach_advisories, need_frame_gap_advisories

    from assumption_rules import observation_tc_findings

    from assumption_rules import interface_bridge_findings, obstacle_hat_findings
    from assumption_rules import observation_evidence_findings
    from assumption_rules import assumption_chain
    import id_carrier
    import record_observation
    import retire
    from absolute_terms import absolute_advisories, absolute_report_lines
    from absolute_terms import absolute_summary
    from trace_text import (
        EXTERNAL_ENDPOINT_PREFIX,
        IF_CITE_MESSAGE,
        ac_advisories,
        allow_key,
        cite_advisories,
        ears_advisories,
        form_findings,
        is_allowed,
        is_drafted,
        is_example,
        module_endpoints,
        norm_module,
        off_spine_advisories,
        paraphrase_advisories,
        provenance_advisories,
        provenance_findings,
        provenance_tokens,
        refs,
        sn_artifact_advisories,
        sr_artifact_advisories,
        sr_fanout_advisories,
        verification_coherence_advisories,
    )
except ImportError:  # pragma: no cover - in-process fallback
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import baseline_snapshot
    import check_trajectory
    import spine_carrier
    from coherence import (
        PhaseScope,
        _repo_id,
        budget_backlink_findings,
        component_membership_findings,
        delegation_findings,
        knowledge_pack_advisories,
        llr_module_ids,
        spine_orphan_findings,
        status_criterion_findings,
    )
    from frame_rules import frame_system_findings, sr_system_advisories
    from frame_rules import need_source_findings, source_documents, stakeholder_findings
    from assumption_rules import assumption_tier_findings
    from frame_rules import mediation_findings
    from assumption_rules import assumption_reach_advisories, need_frame_gap_advisories

    from assumption_rules import observation_tc_findings

    from assumption_rules import interface_bridge_findings, obstacle_hat_findings
    from assumption_rules import observation_evidence_findings
    from assumption_rules import assumption_chain
    import id_carrier
    import record_observation
    import retire
    from absolute_terms import absolute_advisories, absolute_report_lines
    from absolute_terms import absolute_summary
    from trace_text import (
        EXTERNAL_ENDPOINT_PREFIX,
        IF_CITE_MESSAGE,
        ac_advisories,
        allow_key,
        cite_advisories,
        ears_advisories,
        form_findings,
        is_allowed,  # noqa: F401 - re-exported: the allow-key tests read it here
        is_drafted,
        is_example,
        module_endpoints,
        norm_module,
        off_spine_advisories,
        paraphrase_advisories,
        provenance_advisories,
        provenance_findings,
        provenance_tokens,  # noqa: F401 - re-exported: the provenance tests read it here
        refs,
        sn_artifact_advisories,
        sr_artifact_advisories,
        sr_fanout_advisories,
        verification_coherence_advisories,
    )

# Sibling: the arch-map AST walk (`gen_arch_map.implements_report`), the ONE home
# for "does this name exist in the declared source surface" (WI-486/WI-502).
# `if_contract_advisories`' named-symbol tripwire reads it; a second AST walk in
# a second module is the duplication that home was consolidated to prevent.
# OPTIONAL, on check_trajectory's own reasoning: a fixture that copies trace.py
# without its siblings simply has no surface, and the rule is then vacuous —
# which is the same answer a repo declaring `[arch-map] mode = files` gets.
try:
    import gen_arch_map
except ImportError:  # pragma: no cover - in-process fallback
    try:
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        import gen_arch_map
    except ImportError:
        gen_arch_map = None


# --- THE ROW VOCABULARY, RE-EXPORTED FROM ITS ONE HOME (WI-448 slice 3) --------
# `load_csv`, `is_approved`, `is_founded`, `LLR_EXEMPT`/`llr_exempt`, `phase_num`,
# `sn_all_ids` and `sn_cited_ids` were DUPLICATED between this module and
# `spine_rules.py` under the retired F5 rule, held equal by
# `tests/test_rule_sync.py` pins. They are POLICY — this module ENFORCES the
# spine, that one DERIVES its stage, and a disagreement between them is a false
# green or false red AT A GATE (WI-099). Owner ruling D-8 (`OI-16`) replaced the
# pins with one home, `kitlib/spine.py`; the names are re-exported here so no
# call site in this 5,000-line module moved. Each rule's own rationale travelled
# with it and is NOT restated here.
#
# `LLR_EXEMPT` WAS A `tuple` HERE and a `set` there — behaviour-equal under `in`,
# so the value pin (`set(TRACE.LLR_EXEMPT) == set(GATE.LLR_EXEMPT)`) could not
# see the difference. The one home is a `frozenset`.
#
# `is_drafted`, `is_example` and `refs` are NOT in this block: they arrive from
# `trace_text` above, which re-exports the same objects from the same home.
load_csv = _spine.load_csv
is_approved = _spine.is_approved
is_founded = _spine.is_founded
LLR_EXEMPT = _spine.LLR_EXEMPT
llr_exempt = _spine.llr_exempt
phase_num = _spine.phase_num
sn_all_ids = _spine.sn_all_ids
sn_cited_ids = _spine.sn_cited_ids

# THE TENTH DUPLICATE, RETIRED THE OTHER WAY. `sn_draft_ids` was a one-line
# delegation to `spine_carrier.draft_ids_from_text` in BOTH modules, and it is
# the one member of the pair that cannot move into `kitlib`: that package may
# import no sibling of `scripts/`, or the whole script graph follows it into the
# scaffolder. So the wrapper is deleted rather than relocated and the sibling
# function is bound directly, under the same local name. Its claim — that
# draft-ness is a FIELD under TOML and was SECTION-AS-STATE under legacy
# markdown, and that choosing the carrier is load-bearing because a heading scan
# over TOML reports zero drafts and floats the derived stage upward — is the
# carrier's own and lives on `spine_carrier.draft_ids_from_text`.
sn_draft_ids = spine_carrier.draft_ids_from_text


# `is_planned` WAS DELETED AT D-9 MIGRATION STEP 5, not re-keyed — the deletion
# its own docstring promised. It was step-2 INSURANCE: `Planned` sat on 14 live
# spine rows while no predicate in the kit recognized it (it read identically to
# `Bananas`), so it was surfaced for the interval between the closure and the
# ruling. OI-30 D1 ruled the fold — `Planned` IS `Approved` — so every site that
# read the predicate now reads `is_approved` or `is_drafted`, and the word itself
# is out of `STATUS_VALUES`.
#
# `is_modified` WAS DELETED AT D-9 MIGRATION STEP 7 on the same terms, for the
# reason its own docstring stated in advance. It was the TRANSITIONAL marker for
# "approved text that has since moved", kept past step 5's rename only so the kit
# never had a commit with no drift detector at all; its successor — the
# `docs/archive/last_approved/` comparison — ran live beside it through the
# owner's signing act (step 6), which cleared the last `Modified` row and seeded
# the snapshot. Owner ruling 2026-08-17m states the replacement in one line:
# *"modified means nothing because it is caught by comparing to the snapshot"*.
#
# `tests/test_rule_sync.py` asserts NEGATIVELY that no predicate in any shipped
# script honours `Draft`, `Planned`, `Verified` or `Modified` again — the
# assertion that makes these four deletions checkable rather than remembered.


def structure_findings(path, display=None):
    """Column-count structural check over one registry CSV: every data row must
    parse (RFC-4180 quoting) to exactly the header's column count. This is the
    integrity-class guard for the misquoted-cell failure mode (an unquoted comma
    shifts every later column and the join silently reads the wrong cells), so
    it fails --strict and --strict-integrity — wrong at any stage, like a
    duplicated id. Fully blank rows are skipped (a trailing newline is not a
    finding); '-000' example rows are NOT skipped, because a template row must
    parse correctly too.

    Implements: SR-157, LLR-002
    """
    if not path.exists():
        return []
    name = display or path.name
    out = []
    # The same reader every other CSV consumer uses: a leading `#` declaration
    # header is a header, never the header row — else the comment lines would
    # count as one-column rows against a one-column "header".
    text = path.read_text(encoding="utf-8-sig", errors="replace")
    skipped = len(text.splitlines()) - len(_spine.csv_body(text).splitlines())
    reader = csv.reader(io.StringIO(_spine.csv_body(text)))
    header = next(reader, None)
    if header is None:
        return out
    expected = len(header)
    for row in reader:
        if not any(cell.strip() for cell in row):
            continue
        if len(row) != expected:
            rid = (row[0].strip() if row else "") or "(no id)"
            out.append(
                "{}: row {} (line {}) parses to {} column(s); header has "
                "{} — quote any cell containing a comma".format(
                    name, rid, reader.line_num + skipped, len(row), expected
                )
            )
    return out


# Id syntax per registry (for the always-on integrity check).
ID_PATTERNS = {
    "SR": re.compile(r"^SR-\d+$"),
    "LLR": re.compile(r"^LLR-\d+$"),
    "TC": re.compile(r"^TC-\d+$"),
    "PB": re.compile(r"^PB-\d+$"),  # optional performance-budgets registry (§9)
    "REPO": re.compile(
        r"^REPO-\d+$"
    ),  # optional coordinator repo-delegation registry (MULTI_REPO.md)
    "MOD": re.compile(
        r"^MOD-\d+$"
    ),  # legacy name for REPO (pre-rename modules.csv rows, still read)
    "PART": re.compile(
        r"^PART-\d+$"
    ),  # optional purchased/external parts registry (process-options.md)
    "ASSET": re.compile(
        r"^ASSET-\d+$"
    ),  # optional binary/large-asset provenance registry (process-options.md)
    "CMP": re.compile(
        r"^CMP-\d+$"
    ),  # optional domain-neutral component registry (process-options.md)
    "IF": re.compile(
        r"^IF-\d+$"
    ),  # optional intra-repo/cross-project interface registry (process.md §8)
}

# Fields that must be non-empty under --strict-schema. Omits the optional columns
# (Permutations, Phase, TestRefs, Parameters) and the LLR's `Rationale`: a short
# decomposition row's why IS its parent SR's, so requiring one everywhere would
# manufacture the restatement the column exists to prevent. The SR's `Rationale`
# IS required — every row already carries one, so it guards zero-to-zero. A legacy
# CSV without the column reads as empty (the ADOPTING.md §6 migration adds it).
REQUIRED_FIELDS = {
    "SR": [
        "SR-ID",
        "Title",
        "SN-Refs",
        "Requirement",
        "Rationale",
        "AcceptanceCriteria",
        "Priority",
        "Verification",
        "Status",
    ],
    "LLR": ["LLR-ID", "SR-Refs", "Title", "Module", "CodeSymbol", "Detail", "Status"],
    # `Verifies` is required CONDITIONALLY, so it lives in `schema_findings`
    # beside the other conditional rule (`_tc_verifies_required`, SR-197).
    "TC": [
        "TC-ID",
        "Level",
        "Method",
        "Tier",
        "Expected",
        "Automated",
        "Status",
    ],
    # IF and CMP joined at WI-443 (OI-14 part B), and their tier is ADVISORY:
    # `schema_advisories` reads these same two dicts and never joins a failure
    # set, so the exit code is untouched at any gate. That is the ruled
    # warn-first sequencing, not a softer rule — the vocabularies are closed the
    # moment they are stated, and the promotion to ERROR is a later, separate
    # decision taken once the corpus has converged.
    #
    # `Rationale` is deliberately NOT required on an IF row: B1 migrates cells as
    # rows are touched, so demanding one everywhere would manufacture 113 rushed
    # sentences — the bulk rewrite the ruling refused. `SignalNote`, `Component`
    # and `Notes` are optional by design.
    # WI-442 replaced `Stability` → `Approval` → `Status` (2026-08-17). The two
    # `Interface*External` tie-backs are deliberately NOT required — a row
    # carries one only when it realizes a boundary crossing, and requiring them
    # would demand every internal seam claim to be a boundary.
    # WI-455 executed the held removal (OI-60 ruled (a), 2026-08-23):
    # `Direction`/`ThisProject`/`Counterpart` are GONE and `Consumers` is the
    # required endpoint cell. OI-67 (ruled (a), 2026-08-29) took the row to ONE
    # OWNER, ITS CONSUMERS AND A TYPED STATEMENT: `Owner` is the providing
    # thing (a path or an `external:` party, required), `Channel` the closed
    # vocabulary of what crosses (required), `Data` the optional alphabet.
    # `Provider`, `Req-Refs`, `Signal`, `SignalNote` and `Contract` LEFT the
    # row — a row still carrying one is `interface_findings`' strict finding.
    # `Requestors`/`Consumers` are NOT in this list: exactly one of the two is
    # required, which is `interface_findings`' rule, not a per-cell one.
    "IF": [
        "IF-ID",
        "Owner",
        "Channel",
        "Version",
        "Status",
    ],
    "CMP": ["CMP-ID", "Name", "Category", "Status"],
    # WI-442 — the depth-0 frame's three tiers (docs/requirements/external.toml).
    # `Absorbs` and `Notes` are optional provenance and are not required.
    "EXT": ["EXT-ID", "Name", "Class", "Description", "Status"],
    "B": ["B-ID", "Entity", "Direction", "Carries", "Status"],
    "REL": ["REL-ID", "From", "To", "Kind", "Flow", "Status"],
}

# The only *closed* vocabularies the method defines (process.md §4). `Priority`
# is intentionally left open, so it is not validated here.
#
# `Status` CLOSED AT ITS LIVE TRUTH (D-9 migration step 1, 2026-08-15) and
# NARROWED TO THE LADDER AT STEP 5 (the rename). It was open-vocabulary until
# step 1, and the cost was measurable: a value no predicate recognizes —
# `Planned` was exactly that, and `Bananas` would have read identically — sat in
# the registry announcing nothing. The enum-close-first rule is stated
# executably: *at every commit, the declared Status enum equals exactly the set
# of values at least one live predicate recognizes, narrowing monotonically*.
#
# `Draft`→`Drafted`, `Verified`/`Planned`→`Approved` (OI-30 D1: the two
# approved-text rungs are ONE once the pass claim leaves the vocabulary).
#
# NARROWED AGAIN AT STEP 7 + ARMED AT STEP 8, in ONE act, because the enum must
# equal the set of values at least one live predicate recognizes at EVERY commit:
# `Modified` leaves (snapshot drift, live beside it since step 4, is now the only
# detector — owner ruling 2026-08-17m) and `Founded` enters. D-9's ruled ladder,
# whole: Drafted -> Approved -> Founded.
#
# The VALUE lives in `kitlib.spine` beside the predicates that read its words,
# and is bound here under its old name, so a pure sibling of this checker
# (`frame_rules`, holding the stakeholder list to it) reads the same set without
# importing the checker.
STATUS_VALUES = _spine.STATUS_VALUES

# The enum columns whose out-of-vocabulary findings are INTEGRITY-class, not
# schema-class (D-9 migration correction C1). `schema_findings` only runs under
# `--strict-schema`, which `check.py` appends at DevStg-Impl alone — so a
# Status vocabulary declared there would be INERT for every repo below the top
# bar, which is every repo the migration is being run for. A retired Status word
# is wrong at ANY stage, exactly like a duplicated id, so it joins the always-on
# `--strict-integrity` floor instead. The vocabulary still has ONE home —
# `ENUM_FIELDS` below — and this names only which pipe reads it.
INTEGRITY_ENUM_COLS = frozenset({"Status"})

ENUM_FIELDS = {
    "SN": {"Status": STATUS_VALUES},  # home for the need tier (2026-08-17k)
    "SR": {
        "Status": STATUS_VALUES,
        # The ruled aspect vocabulary (sitting-2 decision 10, executed by the
        # WI-451 re-tier). `Area` was a 31-value free-text column of which 25
        # values were a component by another name; those were DROPPED at
        # conversion rather than remapped, and the six SPANNING values — the
        # cross-cutting concerns no partition can express — became this closed
        # set. An aspect is a REVIEW grouping, not an ownership claim, so a row
        # carrying none is normal and never a finding (only a non-empty
        # out-of-vocabulary value is). NOT the D-9/D12 Status vocabulary, which
        # is held for its own atomic act (2026-08-14e).
        "Aspect": {
            "process",
            "trajectory",
            "unattended-loop",
            "connectivity",
            "perf",
            "portability",
        },
        "Verification": {
            "Test",
            "Demonstration",
            "Manual",
            "Analysis",
            "Inspection",
            "Attest",
            "Critique",
        },
    },
    # The LLR tier had NO entry here at all until the Status closure — its
    # `Status` cell was the one spine vocabulary nothing declared and nothing
    # validated, which is how seven LLR amendments came to ride `Planned`
    # (WI-458) with no surface reading them.
    "LLR": {"Status": STATUS_VALUES},
    "TC": {"Status": STATUS_VALUES, "Tier": {"Smoke", "Full", "Release"}},
    # WI-443 / OI-14 part B — the IF tier's first closed vocabularies, advisory
    # like its required fields above.
    #
    # `Signal` is the owner's ruled discrete-vs-variable typing and is NEW: all
    # 113 live rows were searched before the ruling and NOTHING in the registry
    # typed a signal at all, in any column. `Stability` was DECLARED by
    # process.md §8 from the start and validated nowhere, which is how four rows
    # came to carry `Provisional` — a value that was never in the shipped
    # vocabulary.
    #
    # `Status` BELOW IS THE TIER'S ONE MATURITY FIELD, reached by two
    # retirements: `Stability` left at WI-442 for a transitional `Approval`,
    # which became `Status` at the 2026-08-17 registry unification — decision
    # 12's "one shared status vocabulary, per-registry subsets", so one word
    # means one thing across every registry. An EARLIER, UNDECLARED `Status`
    # retired at OI-14 part B for overlapping `Stability` (`Stable` read in both
    # on one row, meaning different things). The subset here is the two-value
    # one, no longer provisional — D-9's ladder LANDED — and `Founded` is
    # excluded on merit: settled AND DEMONSTRATED, not merely AGREED.
    #
    # `Direction` joined at the 2026-08-15 interface rework (plan step 1) and
    # LEFT at WI-455 (OI-60 ruled (a), 2026-08-23) — so this tier now closes one
    # vocabulary, not two. The column stated FLOW, and flow is no longer stated:
    # it is READ, provider→consumers, off the two endpoint cells. The
    # coverage half a `Consumes` row carried is unharmed — `_declared_seam_pairs`
    # reads the endpoint pair, which the header always said it took both ways.
    "IF": {
        "Channel": set(check_trajectory._kitspine.IF_CHANNELS),
        "Status": {"Drafted", "Approved"},
    },
    "CMP": {
        "Status": {"Drafted", "Approved", "Founded"},
        "Standing": {"active", "has-gap", "deprecated"},
    },
    # WI-442 — the depth-0 frame. `Class` is the entity vocabulary §1R.7 item 2
    # confirmed (`deliverable` was the ruled addition); `Direction` is read from
    # the SYSTEM's point of view, in|out|inout — and since WI-455 retired the IF
    # tier's Provides/Consumes reading, this is the carrier's ONLY `Direction`.
    "EXT": {
        "Class": {"operational", "enabling", "interoperating", "deliverable"},
        "Status": {"Drafted", "Approved"},
    },
    "B": {
        "Direction": {"in", "out", "inout"},
        "Status": {"Drafted", "Approved"},
    },
    "REL": {"Status": {"Drafted", "Approved"}},
    # The stakeholder list (SR-189) holds the spine's own ladder, since it is
    # the needs file's second approvable tier; the always-on integrity floor
    # reads it through `enum_integrity_findings` like every tier's Status.
    "STK": {"Status": STATUS_VALUES},
}

# --- the IF `Contract` negative rules (WI-443, warn-first) --------------------
# Whether a sentence is a specification or a story CANNOT be mechanized — no
# check reads intent. These four read FORM instead, and between them they make
# it impossible for a `Contract` cell to be a CHANGELOG, which is the failure the
# census actually measured (requirement voice 1% -> 7.1%, cross-registry
# citations 14% -> 24%, median cell 260 -> 325 characters, all in three days
# while the rule existed only as prose).
#
# The first two are REFUSE-CLASS — they name what may never appear, and they
# read as errors that have not been promoted yet. The last two are genuinely
# advisory: a long cell may be honest, and `since` has a temporal sense.
_IF_WI_RE = re.compile(r"\bWI-\d+\b")
#
# The decision pattern is `D-<n>` EXACTLY, not a general `<LETTER>-<n>`: the
# broader shape was tried and it read the data pack's own crossing ids (`M-10`)
# as rulings, which is a check inventing a rule nobody wrote. What was ruled is
# the repo-lock decision citation, and that is what this matches.
_IF_DECISION_RE = re.compile(r"\bD-\d+\b")
# `(?<!-)`: a FLAG spelled `--since` is an argv token, not an argument — a cli
# row's `Data` cell legitimately lists it, and the form rule reads form only.
_IF_CONNECTIVE_RE = re.compile(r"(?<!-)\b(because|rather than|so that|since)\b", re.I)
IF_DATA_MAX = 160

# --- the FIFTH rule: does the surviving prose name anything that is GONE? ------
# The four rules above read FORM only, which is why a contract can name a
# deleted constant for months and stay green — the measured exhibit is a live
# row still naming `SCHED_*` classification constants that the concurrency
# program deleted, with the presence-only module back-link reporting 27/27
# complete over it. This rule reads CONTENT, at the one resolution a grammar
# honestly can: a token that CLAIMS to be a code symbol or a repository path
# must resolve. It is warn-first like its four siblings and never joins a
# failure set.
#
# THE THREE SYMBOL SHAPES, and they are the shapes contracts actually use:
_IF_CALL_RE = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)\(\)")
_IF_DOTTED_RE = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*)\b")
# A SCREAMING_SNAKE constant, with an optional `*` glob tail — the tail is not a
# nicety, it is the exhibit's own spelling (`SCHED_*` names a FAMILY of deleted
# constants, and a rule that only read whole names would have missed it).
_IF_CONST_RE = re.compile(r"\b([A-Z][A-Z0-9]*(?:_(?:[A-Z0-9]+|\*))+)")
# A repo path. THE FIRST SEGMENT MUST BE A REAL DIRECTORY before the token is
# judged at all — that one test is what separates `docs/privacy-check` from the
# English slashes a contract legitimately writes (`identity/PII`,
# `claim/work/merge`, `library/CLI`), and it needs no extension list to do it.
# The cost is stated rather than hidden: a path whose top-level directory was
# deleted OUTRIGHT is not judged, only one whose neighbourhood still exists.
_IF_PATH_RE = re.compile(r"\b([A-Za-z0-9_.\-]+(?:/[A-Za-z0-9_.\-]+)+)")
# A dotted token whose tail is one of these is a FILENAME, not an attribute
# access — `trace.py`, `stack.ini`, `report.md`. The list is deliberately the
# suffixes `_resolves_in_tree` already probes, so the two readers of "is this
# text a file" agree.
_IF_FILE_TAILS = frozenset(
    "py md toml csv ini html yml yaml json txt cmd sh ps1 command bat js ts".split()
)

# --- Acceptance-criteria testability advisory (warn-only) --------------------
# A comparative/absolute claim in an AcceptanceCriteria cell is untestable until
# it names its predicate: identical *in what*, judged *how*. (Gilbert's LLR-013
# shipped "cannot distinguish source by schema" through DevStg-Reqs and had to be pinned
# by hand at DevStg-Tests.) Both lists are heuristics — the advisory WARNS and never joins
# a failure set; the DevStg-Reqs consistency review (process.md §4) makes the call.


# Verification methods whose approval rests on a recorded human judgment,
# not a runnable check (process.md §4 "Attest"). --require-verified accepts these
# as legitimately approved but the report surfaces them distinctly (the
# verification-basis split), so an audit can always see how much rests on trust.
ATTESTED_METHODS = {"Attest"}
# The one method whose approval rests on a runnable, re-executable check
# (process.md §4 "Test"). Everything that is neither Test nor an ATTESTED_METHOD
# (Demonstration/Manual/Analysis/Inspection/Critique) rests on a human observing
# an outcome — repeatable, but not a runnable check — and is reported as its own
# "demonstrated/observed" category, so the audit never over-counts what rests on
# runnable checks (WI-259: the split is three-way, not attested-vs-everything-else).
MECHANIZED_METHODS = {"Test"}


def id_key(label):
    return label + "-ID"


def id_sort_key(rid):
    """Numeric-then-lexical sort key for a registry id, so SR-9 orders before
    SR-10: ids are `<TIER>-<digits>` with no zero-padding contract, so a plain
    string sort mis-orders once a tier crosses a digit width."""
    m = re.search(r"\d+", rid or "")
    return (0, int(m.group()), rid) if m else (1, 0, rid or "")


def integrity_findings(label, raw_rows):
    """Duplicated or malformed ids in one registry (example '-000' rows skipped —
    those are the placeholder check's job, never an integrity error).

    Implements: SR-157, SR-159, LLR-002, LLR-041
    """
    key, pattern = id_key(label), ID_PATTERNS[label]
    found, seen = [], set()
    for r in raw_rows:
        rid = r.get(key)
        if not rid or not rid.strip():
            # A row with content but a blank id is a live requirement that just
            # vanished from every join (a one-cell edit slip) — integrity-class,
            # wrong at any stage. Fully blank rows stay a non-finding.
            if any((v or "").strip() for k, v in r.items() if k != key):
                found.append(f"{label} row with non-empty cells but no {key}")
            continue
        if is_example(rid):
            continue
        # Duplication is checked FIRST so a repeated id reports "duplicated" even
        # when it is also malformed — otherwise a malformed id seen twice
        # re-reported "malformed" and never "duplicated" (both are integrity
        # failures, but the second occurrence's fact is that it repeats).
        if rid in seen:
            found.append(f"{label} id {rid} is duplicated")
        elif not pattern.match(rid):
            found.append(f"{label} id {rid!r} is malformed (expected {label}-<digits>)")
        seen.add(rid)
    return found


def enum_integrity_findings(label, rows):
    """Out-of-vocabulary values in the INTEGRITY_ENUM_COLS columns of one
    registry — today that is `Status` and nothing else.

    THE SAME `ENUM_FIELDS` TABLE `schema_findings` reads, deliberately: a tier's
    vocabulary has ONE home whatever pipe enforces it, so this is a change to
    *which list a value's finding is appended to*, never a second copy of the
    allowed set that can drift from the first. The split exists because the two
    pipes run at different gates — schema at DevStg-Impl only, integrity
    always — and a retired Status word is wrong at every stage (D-9 correction
    C1).

    Placeholder `-000` rows are skipped, like every other rule here: a shipped
    template's example row is the placeholder check's business."""
    key = id_key(label)
    out = []
    for r in rows:
        rid = (r.get(key) or "").strip()
        if not rid or is_example(rid):
            continue
        for col in sorted(INTEGRITY_ENUM_COLS):
            allowed = ENUM_FIELDS.get(label, {}).get(col)
            if not allowed:
                continue
            val = (r.get(col) or "").strip()
            if val and val not in allowed:
                out.append(
                    "{} {} has {}={!r}, which is not in the closed vocabulary "
                    "(allowed: {})".format(
                        label, rid, col, val, ", ".join(sorted(allowed))
                    )
                )
    return out


# --- the id watermark: an id is allocated once, for the life of the repo -------
# Duplicate ids already error (integrity_findings above, sn_integrity_findings for
# the prose tier, check_trajectory.load_wis for WI). REUSE does not: every one of
# those checks reads only the LIVE tree, so an id freed by deleting its row is
# invisible and can be minted again. That matters because a reused id silently
# re-points history — every commit message, log entry and archived document that
# cites it now names a different thing — and no check can see it after the fact.
#
# The mark closes that. It is machine-written, machine-read, never hand-authored
# (the §6 F-3 `anchor` class), and it is the SOURCE a mint counts from, rather
# than `max(live) + 1`.
WATERMARK = id_carrier.WATERMARK
# Every id space in the repo: the ten this module already patterns, plus the
# seven it does not (SN is the prose tier, WI is directory-as-state, OI is the
# owner queue, DP is a plan-round directory, and B/EXT/REL are the depth-0 frame
# tiers in external.toml — added by the sitting-3 item-17 ruling after the
# 2026-08-16q cut spent B-06/B-07/EXT-004 with nothing mechanical to stop a
# later re-mint). STK is the stakeholder list on the needs file (SR-189), hand-
# authored like the frame's, and DA/SUR the assumptions registry's two tiers
# (SR-191, SR-192), hand-authored the same way. Keyed off ID_PATTERNS so a space
# added there cannot be silently exempt here — tests/test_id_watermark.py pins
# the set.
WATERMARK_SPACES = tuple(
    sorted(
        set(ID_PATTERNS)
        | {"SN", "WI", "OI", "DP", "B", "EXT", "REL", "STK", "DA", "SUR"}
    )
)
_ANY_ID = re.compile(r"^([A-Z]+)-(\d+)$")
# A mark rises by ALLOCATION (the ordinary path above) or, exactly once per
# space, by a RULED correction — OI-47 (e): a mis-seeded mark corrected by the
# ruling that authorized it, recorded in the header rather than hand-edited.
# `# correction: <SPACE> <old> -> <new> (<ruling id>)` — a comment line, so it
# is invisible to `read_watermark` (comments are skipped there) and visible to
# `read_corrections` below. The line grammars (this one, the mark line and the
# reservation record) live in `id_carrier`, whose fold unions them; the strict
# readers here match its `MARK_LINE`, and `parse_corrections` is that module's
# reader, named here for its callers.
parse_corrections = id_carrier.parse_corrections


def _csv_ids(docs):
    """`(space, number)` for the id cell of every row in every registry CSV.

    Swept by LOCATION, not by a known-file list: a registry this script never
    joins, a project's own addition, and a legacy `work-items.csv` no reader
    looks at all still HOLD their numbers."""
    for sub in ("requirements", "test"):
        directory = docs / sub
        if not directory.is_dir():
            continue
        for path in sorted(directory.glob("*.csv")):
            rows = load_csv(path)
            if not rows:
                continue
            # The row's OWN id is its FIRST column, never "the first id-shaped
            # cell". Those differ the moment a registry puts a reference column
            # first (`SN-Refs` before `SR-ID`): the scan would then yield the
            # CITATION and skip the id, leaving that row's number unmarked and
            # therefore free — an UNDER-count, the one direction this scan must
            # not fail in. Surplus cells land under the `None` key as a list, so
            # only the named first column is read.
            id_col = next(iter(rows[0]))
            for row in rows:
                match = _ANY_ID.match((row.get(id_col) or "").strip())
                if match:
                    yield match.group(1), int(match.group(2))


def _spine_ids(docs):
    """`(space, number)` per SR/LLR/TC row, through the CARRIER.

    `_csv_ids` above sweeps by LOCATION, and that caught the three row tiers only
    while they were CSVs. The D-5 carrier cutover moved them to TOML and the
    glob then matched NOTHING for them — silently — so rule 2 ("no live id
    exceeds its mark") went VACUOUS on three of the four spine tiers, which are
    precisely the tiers with NO minter: a hand-authored id arriving past the
    mark is the only signal there is. It was already false-green when found
    (LLR-167 and TC-161 stood above their marks, zero findings reported).

    So this reads through `spine_carrier` — the sanctioned reader, which
    resolves whichever carrier is live — instead of assuming a suffix. A path
    glob can be un-wired by moving a file; a carrier resolve cannot.

    `SPINE_FILES` is defined further down the module and referenced at CALL
    time, which is deliberate: the paths belong beside the joins that use them,
    and duplicating them here is exactly the second home this scan is being
    fixed for."""
    for rel, id_col in SPINE_FILES:
        # `SPINE_FILES` holds repo-root-relative paths; `docs` is <root>/docs.
        for row in spine_carrier.load(docs.parent / rel, id_col):
            match = _ANY_ID.match(str(row.get(id_col) or "").strip())
            if match:
                yield match.group(1), int(match.group(2))


def _offspine_ids(docs):
    """`(space, number)` per row of the numbered OFF-SPINE registries.

    The same hole `_spine_ids` documents, one carrier batch later and found the
    same way — by minting past the mark and getting no finding. Batch-2 moved
    `open-items` off CSV, so `_csv_ids`' `requirements/*.csv` glob stopped
    matching it and rule 2 went VACUOUS for the `OI` space: OI-26 was live
    against a mark of 14 with `--strict` reporting nothing. That space has no
    minter either, so a hand-authored id past the mark is again the only signal.

    Read through `spine_carrier` for the same reason `_spine_ids` does — a glob
    is un-wired by moving a file, a carrier resolve is not. `agents` is
    deliberately absent: its ids are names (`ANTHROPIC-FABLE`), not numbers, so
    it holds no watermark space to lose.

    The stakeholder list (`STK-##`) joined with the tier itself: it shares the
    needs file, and is read here by its own id column exactly as the frame's
    three tiers share `external.toml`. The assumptions registry's two tiers
    (`DA-###`, `SUR-###`) joined with the registry, on one path the same way.

    Implements: SR-189, LLR-215"""
    # interfaces + components joined the TOML carrier at WI-443, which un-wired
    # them from `_csv_ids`' glob exactly as batch-2 did to open-items — found
    # the same way again (WI-454 minted IF-121/122 past a mark of 120 and got
    # no finding). external.toml's three frame tiers (B/EXT/REL) joined at the
    # sitting-3 item-17 ruling: the 2026-08-16q cut deleted B-06/B-07/EXT-004
    # and nothing mechanical stopped a later session re-minting a spent id —
    # the exact vacuous-space class the IF-121/122 mint hit. The frame is
    # LOCKED (its rows change only by recorded ruling), so a mint past the
    # mark is again the only signal there is.
    for rel, id_col in (
        ("docs/requirements/open-items.toml", "OI-ID"),
        ("docs/requirements/interfaces.toml", "IF-ID"),
        ("docs/requirements/components.toml", "CMP-ID"),
        ("docs/requirements/external.toml", "EXT-ID"),
        ("docs/requirements/external.toml", "B-ID"),
        ("docs/requirements/external.toml", "REL-ID"),
        ("docs/requirements/stakeholder-needs.toml", "STK-ID"),
        ("docs/requirements/assumptions.toml", "DA-ID"),
        ("docs/requirements/assumptions.toml", "SUR-ID"),
    ):
        for row in spine_carrier.load(docs.parent / rel, id_col):
            match = _ANY_ID.match(str(row.get(id_col) or "").strip())
            if match:
                yield match.group(1), int(match.group(2))


def _sn_ids(docs):
    """`("SN", number)` per declared stakeholder need, through the CARRIER.

    Was a markdown-row regex, which over the TOML carrier matches NOTHING —
    silently, and the id-watermark check it feeds would then never see an SN at
    all: the mark could not rise, and a retired number could be handed out
    again with nothing to say so. `load_needs` answers whichever
    carrier is live and yields the same ids the markdown rows did."""
    path = docs / "requirements" / "stakeholder-needs.toml"
    for need in spine_carrier.load_needs(path):
        match = re.match(r"SN-(\d+)$", str(need.get("id") or "").strip())
        if match:
            yield "SN", int(match.group(1))


def _wi_ids(docs):
    """`("WI", number)` per spec FILENAME under docs/work AND its archive
    sibling `docs/archive/work` (WI-504 relocated terminal history one
    directory deeper; `kitlib.registry.spec_roots` is the one home for "both
    are the same registry") — filenames, never row contents, because
    `read_spec_rows` drops a malformed spec silently while its id stays
    taken. Scanning only the active workspace would let a mark for an id
    minted and closed to the archive in one commit read as unjustified."""
    for work in _registry.spec_roots(docs / "work"):
        if not work.is_dir():
            continue
        for path in work.rglob("WI-*.md"):
            match = re.match(r"^WI-(\d+)-", path.name)
            if match:
                yield "WI", int(match.group(1))


def _dp_ids(docs):
    """`("DP", number)` per dual-plan round directory."""
    plans = docs / "plans"
    if not plans.is_dir():
        return
    for path in plans.iterdir():
        match = re.match(r"^DP-(\d+)-", path.name) if path.is_dir() else None
        if match:
            yield "DP", int(match.group(1))


def live_max_ids(root):
    """`{space: highest id number currently present}` over the WHOLE repo.

    Deliberately broader than any loader, and `-000` placeholders are COUNTED:
    for a mark that is the safe direction, since counting something extra only
    raises the floor while missing something lowers it and frees an id.
    (`intake.next_wi_id` states the same rule for its own mint: "for a MINT, an
    id held anywhere is an id taken".)"""
    top = {}
    for space, num in live_ids(root):
        if num > top.get(space, 0):
            top[space] = num
    return top


def live_ids(root):
    """`{(space, number)}` of every id present in the repo at `root`, every
    watermark space, `-000` placeholders included: the one definition of
    "live" that `live_max_ids` and the landing check both read.

    Implements: SR-174, LLR-363"""
    docs = Path(root) / "docs"
    readers = (_csv_ids, _spine_ids, _offspine_ids, _sn_ids, _wi_ids, _dp_ids)
    return {
        (space, num)
        for reader in readers
        for space, num in reader(docs)
        if space in WATERMARK_SPACES
    }


def live_ids_at(root, rev):
    """`live_ids` of the tree-ish `rev` (a commit, or the index's tree), over
    the registry directories it holds (`id_carrier.ids_at`).

    Implements: SR-174, LLR-363"""
    return id_carrier.ids_at(root, rev, live_ids)


def landing_id_refusal(
    root, landing_rev, parent_rev, wi_ids, claim_source="the claim folder", lane=None
):
    """The landing check both landing routes ask (the merge slot and a hand
    squash): the carrier-space ids live at `landing_rev` and not at
    `parent_rev`, and those the lane's tip `lane` holds and its merge base
    with `parent_rev` does not (a hand squash's staged tree is not the tip),
    judged against the retirement records (`retire.recorded_at`) and the
    carrier tip's records naming one of `wi_ids` (`id_carrier.
    landing_refusal`). A refusal, or None.

    Implements: SR-174, LLR-363"""
    spaces = id_carrier.carrier_spaces(WATERMARK_SPACES)
    revs, retired = (landing_rev, parent_rev), retire.recorded_at
    return id_carrier.landing_refusal(
        root, revs, wi_ids, claim_source, live_ids, spaces, retired, lane
    )


def landing_fold_lag(root, rev):
    """How the watermark at the tree-ish `rev` lags the id carrier's fold
    (`id_carrier.rev_fold_lag`); [] with no carrier. Both landing routes ask
    it: the slot refreshes a lagging tip, the squash step refuses one.

    Implements: SR-174, LLR-363"""
    return id_carrier.rev_fold_lag(root, rev)


def read_watermark(root):
    """`{space: int}` from `docs/id-watermark`. RAISES on absent or malformed.

    Every other declared-file reader in this kit degrades to empty on a missing
    file, and that is right for a floor, an allowlist or a census — the absence
    means "nothing declared". Here it would mean "no id is taken", which frees
    every space at once and is exactly the failure the mark exists to prevent.
    So this one fails LOUD, and a malformed line is refused rather than skipped:
    a line nobody can parse is a space with no mark, which is the same hole."""
    path = Path(root) / WATERMARK
    if not path.is_file():
        raise ValueError(
            "{} is missing — the id watermark is the only record of which ids "
            "have ever been allocated, and without it a deleted id can be "
            "re-minted. Regenerate with `trace.py --bump-ids`.".format(WATERMARK)
        )
    marks = {}
    for lineno, line in enumerate(
        path.read_text(encoding="utf-8-sig", errors="replace").splitlines(), 1
    ):
        text = line.strip()
        if not text or text.startswith("#"):
            continue
        m = id_carrier.MARK_LINE.match(text)
        if not m:
            raise ValueError(
                "{}:{}: not a `<SPACE> = <int>` line: {!r}".format(
                    WATERMARK, lineno, line
                )
            )
        marks[m.group(1)] = int(m.group(2))
    return marks


def read_corrections(root):
    """`{space: [(old, new, ruling_id), ...]}` — the RECORDED CORRECTIONS lines
    in `docs/id-watermark`'s header, if any. Unlike `read_watermark` this
    degrades to `{}` on a missing file or on a file with no correction lines:
    the common case is "no space was ever hand-corrected," which is not the same
    failure as a missing mark (there the ABSENCE of a record means "nothing is
    taken"; here it means "nothing was ruled," a true and unremarkable state).

    A malformed correction line is silently not a correction — the writer
    (`correct_watermark`) is the only thing that emits this line, so a reader
    that cannot parse one is looking at either an unrelated comment or a
    hand-edit already outside what this file promises to protect."""
    path = Path(root) / WATERMARK
    if not path.is_file():
        return {}
    return parse_corrections(path.read_text(encoding="utf-8-sig", errors="replace"))


def ruled_open_item_texts(root):
    """`{OI-###: <the row's prose, joined>}` for every open item whose status is
    `ruled` — or None when the repo carries no open-items registry at all.

    NONE IS NOT `{}`, the same distinction `open_item_states` draws: an absent
    registry means the authority of a recorded correction CANNOT BE ESTABLISHED,
    and (unlike the deferral rules, which go vacuous) that is refused rather than
    waved through — a correction is the one act in this file that overrides the
    guard, so "I could not check the ruling" must not read as "the ruling
    checked out"."""
    path = Path(root) / OPEN_ITEMS_REL
    if spine_carrier.resolve(path) is None:
        return None
    ruled = dict(_spine.open_items_at(spine_carrier.load(path, "OI-ID"), "ruled"))
    return {
        rid: "\n".join(str(v) for v in row.values() if isinstance(v, (str, int, float)))
        for rid, row in ruled.items()
    }


def _ruling_names(text, space, value):
    """Does a ruling's prose name `space` AT `value` — `B = 8`, `B=8`, `B-08`?

    THE VALUE, not merely the space, and the tightening is measured rather than
    fastidious: OI-47's own prose mentions `SR=999` and `WI=4010` as illustrative
    census noise, so "the ruling mentions this space" would have authorized the
    review's forged `SR 180 -> 500` on the strength of a sentence about a
    different number entirely. A ruling that authorizes a hand-raise names the
    value it authorizes; that is the whole content of the authority."""
    pattern = r"(?<![A-Za-z0-9_]){}\s*[-=]\s*0*{}(?![0-9])".format(
        re.escape(space), int(value)
    )
    return re.search(pattern, text) is not None


def _mark_covers_live_findings(marks, live):
    """Rules 1 and 2, read from the working tree alone: every space is marked,
    and no live id stands above its mark."""
    out = []
    for space in WATERMARK_SPACES:
        if space not in marks:
            out.append(
                "id watermark declares no mark for {} — every id space must be "
                "marked, or that space is unguarded; add it with "
                "`trace.py --bump-ids` (existing marks are kept, never "
                "lowered)".format(space)
            )
        elif live.get(space, 0) > marks[space]:
            out.append(
                "{}-{:03d} exists but the id watermark stands at {} — in a lane, "
                "reserve the ids before drafting (`trace.py --reserve-ids WI-NNN "
                "{}=N`, which folds the reservation into this file); on the trunk, "
                "record it with `trace.py --bump-ids` (the mark is what stops the "
                "number being handed out again after the row is "
                "deleted)".format(space, live[space], marks[space], space)
            )
    return out


def _mark_history_findings(marks, live, previous, corrections=None, reservations=()):
    """Rules 3 and 4, which need the COMMITTED mark: it never falls, and it never
    rises past what history justifies — ALLOCATION history, a RESERVATION
    record in the commit's own file, or (OI-47 (e)) a RULED correction recorded
    in the header, and nothing else.

    A reservation record (`reservations`, `(space, low, high, wi)` from
    `id_carrier.parse_reservations`, so a malformed line is no record) justifies
    a rise up to the highest `high` any record names for that space, never
    past it; a fall is refused regardless. With no records the rule is the
    allocation-and-correction rule alone.

    Both directions matter and for opposite reasons. A mark that FALLS re-opens
    every id above the new value. A mark that RISES by hand retires that space's
    guard permanently and silently — it would still pass "every space is marked"
    and still pass "the mark rose". Headroom left by a DELETED row stays legal,
    because the committed mark is what carries it.

    A lowered mark is refused REGARDLESS of `corrections`: the check below runs
    and `continue`s before `corrections` is ever consulted, so a correction
    record — which only ever authorizes a RAISE — cannot be misread as cover
    for a fall. `corrections` (`{space: [(old, new, ruling), ...]}`) matches the
    observed transition EXACTLY (`was == recorded old`, `now == recorded new`);
    a record present for the space but naming a different jump does not excuse
    this one, which is what keeps the one-shot verb from being replayed into a
    second, unrecorded raise.

    THIS ARM ONLY ASKS WHETHER THE RECORD FITS THE RAISE. Whether the record is
    ITSELF legitimate — one per space, citing a ruling that exists, is ruled, and
    names this space at this value, and not overwriting a committed record — is
    `_correction_record_findings`, which runs whether or not a mark moved. The
    split matters: a forged raise self-justifies from the commit AFTER it lands
    (`previous` becomes the forged value), so a check that only ran at the
    raising commit would go quiet exactly one commit too early."""
    corrections = corrections or {}
    reserved = _reserved_highs(reservations)
    out = []
    for space in WATERMARK_SPACES:
        now = marks.get(space)
        if now is None:
            continue
        if space not in previous:
            # A space's FIRST committed mark is a SEED with no baseline to
            # justify it, and it may legally stand above max(live): the ids it
            # must cover include rows deleted BEFORE the space was guarded
            # (B-06/B-07, cut by the 2026-08-16q ruling while B was not yet a
            # watermark space — seeding B at the live max of 5 would hand
            # those two numbers back out). The hand-raise rule below defends a
            # committed mark; from this file's next commit on, this space has
            # one. Over-seeding is the fail-safe direction — a too-high mark
            # wastes numbers, it never re-points history.
            continue
        was = previous.get(space, 0)
        if now < was:
            out.append(
                "id watermark for {} moved DOWN {} -> {}; a mark only ever "
                "rises, or a retired id becomes mintable again".format(space, was, now)
            )
            continue
        justified = max(was, live.get(space, 0), reserved.get(space, 0))
        if now > justified:
            records = corrections.get(space) or []
            # EXACTLY ONE record may justify a raise. Two is the chained
            # forgery (`_correction_record_findings` reports it in its own
            # voice); zero is a plain hand-raise. Both fall through to the
            # refusal below rather than being excused by the newest line.
            if len(records) == 1 and records[0][0] == was and records[0][1] == now:
                continue
            out.append(
                "id watermark for {} stands at {} but nothing justifies more than "
                "{} (the highest committed mark, live id or reservation record) — "
                "a mark rises by allocating or reserving an id, never by hand (the "
                "one exception is a RULED correction recorded via "
                "`--correct-mark`, and none is recorded for this exact "
                "raise)".format(space, now, justified)
            )
    return out


def _reserved_highs(reservations):
    """`{space: the highest number any record reserves in it}`.

    Implements: SR-174, LLR-362"""
    highs = {}
    for space, _low, high, _wi in reservations or ():
        highs[space] = max(highs.get(space, 0), high)
    return highs


def _one_correction_findings(space, records, rulings):
    """The authority arms for ONE space's recorded corrections."""
    out = []
    if len(records) > 1:
        out.append(
            "id watermark for {} carries {} recorded corrections ({}) — the "
            "correction verb is ONE-SHOT per space: one ruling authorizes the "
            "one correction it made, never a standing licence to keep "
            "raising".format(
                space,
                len(records),
                ", ".join("{} -> {} ({})".format(*r) for r in records),
            )
        )
    for was, now, ruling in records:
        where = "id watermark correction {} {} -> {} ({})".format(
            space, was, now, ruling
        )
        if rulings is None:
            out.append(
                "{}: {} carries no open-items registry, so the authorizing "
                "ruling cannot be resolved — a correction overrides the "
                "hand-raise refusal and may not rest on an unverifiable "
                "citation".format(where, OPEN_ITEMS_REL)
            )
        elif ruling not in rulings:
            out.append(
                "{}: names no RULED row of {} — the record's whole authority is "
                "the ruling it cites, so the id must resolve to a row whose "
                "status is `ruled`".format(where, OPEN_ITEMS_REL)
            )
        elif not _ruling_names(rulings[ruling], space, now):
            out.append(
                "{}: {} is ruled but its text never names {} at {} (`{} = {}` or "
                "`{}-{:03d}`) — a ruling authorizes the correction it describes, "
                "not every correction that cites it".format(
                    where, ruling, space, now, space, now, space, now
                )
            )
    return out


def _correction_record_findings(corrections, rulings, committed=None):
    """Are the RECORDED CORRECTIONS themselves legitimate — independent of
    whether any mark moved this commit (OI-47 (e), hardened 2026-08-21).

    Three arms, one per attack the review executed against the first cut:
    ONE-SHOT (a space carrying two records chained a second, unruled raise onto
    the first), RESOLVES (the cited ruling must be a `ruled` open item — the
    review's forgery cited `OI-999`, which does not exist), and NAMES (that
    ruling's text must name this space at this value — see `_ruling_names`).
    `committed` adds the fourth: a record already in git may not be edited or
    deleted, which is what stops a chained raise being laundered by REPLACING
    the previous line instead of appending to it.

    `committed` is None when git supplied no baseline; that arm then does not
    run, the same convention `previous` follows in `watermark_findings`."""
    out = []
    for space in sorted(corrections):
        out += _one_correction_findings(space, corrections[space], rulings)
    for space in sorted(committed or {}):
        old = (committed or {})[space]
        new = corrections.get(space) or []
        if new[: len(old)] != old:
            out.append(
                "id watermark for {}: a COMMITTED correction record was altered "
                "or deleted (committed {}; now {}) — the record is the audit "
                "trail the correction verb exists to leave, and a raise that "
                "rewrites it is the forgery the one-shot rule refuses".format(
                    space,
                    ", ".join("{} -> {} ({})".format(*r) for r in old) or "none",
                    ", ".join("{} -> {} ({})".format(*r) for r in new) or "none",
                )
            )
    return out


def committed_corrections(root):
    """The RECORDED CORRECTIONS as committed — HEAD and every other parent,
    per space the LONGEST list any of them carries.

    Read from git for the same reason `committed_watermark` is: the working tree
    cannot tell an original record from a rewritten one. Longest-wins across
    parents so resolving a watermark conflict `--ours` cannot drop the other
    side's ruled record. None when git can supply no baseline at all."""
    texts = _baseline_texts(root)
    best = {}
    for text in texts:
        for space, records in parse_corrections(text).items():
            if len(records) > len(best.get(space, ())):
                best[space] = records
    return best if texts else None


def _baseline_texts(root):
    """The committed watermark text of every baseline a commit is judged
    against: HEAD, MERGE_HEAD while a merge is in progress, and HEAD's other
    parents; a baseline with no readable file is left out. The one parent walk
    the three committed readers share.

    Implements: SR-174, LLR-362"""
    revs = ["HEAD"]
    merge_head = _git_out(root, ["rev-parse", "--verify", "--quiet", "MERGE_HEAD"])
    if merge_head:
        revs.append(merge_head.strip())
    parents = _git_out(root, ["rev-list", "--parents", "-n", "1", "HEAD"]) or ""
    revs.extend(parents.split()[1:])
    texts = (_git_out(root, ["show", "{}:{}".format(rev, WATERMARK)]) for rev in revs)
    return [text for text in texts if text]


def committed_reservations(root):
    """The reservation records as committed: the UNION over every baseline
    `_baseline_texts` walks, never longest-wins, so a merge resolution that
    keeps one side's records cannot drop the other's. None when git can supply
    no baseline at all.

    Implements: SR-174, LLR-362"""
    texts = _baseline_texts(root)
    if not texts:
        return None
    return id_carrier.fold(texts)[1]


def watermark_findings(
    root, previous=None, previous_corrections=None, previous_reservations=None
):
    """The id-watermark rules, integrity-class.

    `previous` is the committed mark (see `committed_watermark`),
    `previous_corrections` the committed correction records (see
    `committed_corrections`) and `previous_reservations` the committed
    reservation records (see `committed_reservations`). When git cannot supply
    one, the history rules DO NOT RUN and the caller says so — an unrun rule
    that prints nothing is indistinguishable from one that passed."""
    try:
        marks = read_watermark(root)
    except ValueError as exc:
        return [str(exc)]
    live = live_max_ids(root)
    text = (Path(root) / WATERMARK).read_text(encoding="utf-8-sig", errors="replace")
    corrections = parse_corrections(text)
    reservations = id_carrier.parse_reservations(text)
    out = _mark_covers_live_findings(marks, live)
    if corrections or previous_corrections:
        out += _correction_record_findings(
            corrections, ruled_open_item_texts(root), previous_corrections
        )
    out += id_carrier.record_history_findings(reservations, previous_reservations)
    if previous is not None:
        out += _mark_history_findings(marks, live, previous, corrections, reservations)
    return out


def render_watermark(marks, basis="", corrections=None, reservations=()):
    """The file's text. One `<SPACE> = <int>` per line, deliberately: a merge
    conflicts per SPACE rather than per file, and a bump can be a line rewrite.

    `corrections` — `{space: [(old, new, ruling_id), ...]}` from
    `read_corrections` —
    is rendered back verbatim as `# correction: …` lines so a plain
    `--bump-ids` regeneration (which calls this with whatever corrections the
    file already carried) never drops a ruled record; only `correct_watermark`
    ever ADDS one. `reservations` — `(space, low, high, wi)` records — are
    rendered back verbatim and in the order given, in a block of their own
    that appears only when one exists, so a file with none renders
    byte-identical to one written before records existed; only a reservation
    writes one and only the fold copies one.

    Implements: SR-174, LLR-362"""
    head = [
        "# ID WATERMARK — generated by scripts/trace.py --bump-ids (do not hand-edit).",
        "#",
        "# The highest id ever allocated in each space. A mint counts from HERE,",
        "# never from max(live): deleting a row frees its number in the live tree,",
        "# and re-using it silently re-points every commit message, log entry and",
        "# archived document that cites that id at a different thing.",
        "#",
        "# A mark only ever RISES. Lowering one is refused by trace.py's integrity",
        "# pass, which also refuses a live id above its mark and a missing space.",
        "# The one exception is a RULED correction (`--correct-mark`), which may",
        "# raise a single space PAST what allocation justifies — ONE TIME, citing",
        "# the ruling that authorized it, recorded below when used. Never by hand.",
        "#",
        "# SCOPE: a mark covers the id space AS CURRENTLY NUMBERED. If a space was",
        "# ever renumbered, ids from the superseded numbering are NOT covered and",
        "# may be re-pointed by a mint — record those at the registry instead.",
        "#",
    ]
    if corrections:
        head.append(
            "# RECORDED CORRECTIONS — ruled, one-shot, applied by --correct-mark:"
        )
        for space in sorted(corrections):
            for was, now, ruling in corrections[space]:
                head.append(
                    "# correction: {} {} -> {} ({})".format(space, was, now, ruling)
                )
        head.append("#")
    if reservations:
        head.append("# RESERVATIONS — written on the id carrier by --reserve-ids:")
        head += [id_carrier.record_line(r) for r in reservations]
        head.append("#")
    if basis:
        head.append("# basis: {}".format(basis))
        head.append("#")
    body = ["{} = {}".format(space, marks.get(space, 0)) for space in WATERMARK_SPACES]
    return "\n".join(head + body) + "\n"


def _committed_marks(text):
    """The marks one committed watermark text records, or None when a line
    is one the reader would refuse.

    Implements: SR-174, LLR-362
    """
    marks = {}
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        m = id_carrier.MARK_LINE.match(stripped)
        if not m:
            # A line the reader would REFUSE must not be dropped here. Skipping
            # it silently disables monotonicity for that space alone, which is
            # the per-space version of the hole this rule exists to close.
            return None
        marks[m.group(1)] = int(m.group(2))
    return marks or None


def committed_watermark(root):
    """The highest mark per space across HEAD **and every other parent**.

    Monotonicity cannot be read from the working tree — a lowered mark looks
    exactly like a correct one — so it is read from git. But `HEAD:` alone is
    FIRST-PARENT ONLY, and a merge is exactly where marks get lost: two branches
    each allocate ids, `docs/id-watermark` conflicts (by design, one line per
    space), and resolving it `--ours` discards the other side's marks while
    every commit message on that branch still cites them. Comparing against the
    max over all parents makes that resolution a finding instead of a silent
    re-issue.

    `MERGE_HEAD` covers the in-progress case (the conflict is being resolved
    right now); `HEAD^1..^n` covers the commit after it landed. Returns None
    only when git can supply NO baseline at all — off-git, a shallow clone, or
    before the file's first commit — and the caller then reports the rule as
    SKIPPED rather than passing it quietly."""
    best = {}
    seen_any = False
    for text in _baseline_texts(root):
        marks = _committed_marks(text)
        if marks is None:
            continue
        seen_any = True
        for space, value in marks.items():
            best[space] = max(best.get(space, 0), value)
    return best if seen_any else None


def bump_watermark(root):
    """Raise every mark to the live maximum. Returns `(marks, raised)`.

    A MALFORMED file propagates its error. Only an ABSENT one starts from zero,
    and only because that is the file's first creation. The distinction is the
    whole safety of the writer: this is the one artifact in the repo whose
    content cannot be recomputed, so "I could not read it" must never become "I
    will replace it with the live maximum" — that discards every mark for an id
    already deleted, which is precisely the record the file exists to keep. The
    trap is real rather than theoretical, because `read_watermark`'s own error
    text sends the reader here to regenerate."""
    live = live_max_ids(root)
    path = Path(root) / WATERMARK
    marks = read_watermark(root) if path.is_file() else {}
    # A regeneration must not DROP a ruled correction just because this run's
    # allocation-driven raises had nothing to do with it — the record's only
    # writer is `correct_watermark`; this one only carries it forward unchanged.
    text = (
        path.read_text(encoding="utf-8-sig", errors="replace") if path.is_file() else ""
    )
    corrections = parse_corrections(text)
    reservations = id_carrier.parse_reservations(text)
    raised = {}
    for space in WATERMARK_SPACES:
        was = marks.get(space, 0)
        now = max(was, live.get(space, 0))
        if now != was:
            raised[space] = (was, now)
        marks[space] = now
    (Path(root) / WATERMARK).write_text(
        render_watermark(marks, _basis(live), corrections, reservations),
        encoding="utf-8",
        newline="\n",
    )
    return marks, raised


def _basis(live):
    """The `# basis:` line's value: each space's highest live id.

    Implements: SR-174, LLR-362
    """
    return " ".join(
        "{}={}".format(s, live.get(s, 0)) for s in WATERMARK_SPACES if live.get(s)
    )


def correct_watermark(root, space, new_value, ruling_id):
    """`--correct-mark`: the one-shot RECORDED-CORRECTION verb (OI-47 (e)).

    The only other way a mark may rise, besides allocation: a NAMED space is
    raised to a NAMED value on a NAMED ruling's authority, and the ruling id is
    recorded in the header so `_mark_history_findings` can tell this raise
    apart from an unrecorded (hand-edited) one. ONE-SHOT: a space that already
    carries a recorded correction refuses a second one — replaying the verb,
    even citing the same ruling, would let one ruling authorize an unbounded
    climb instead of the single correction it actually made. Returns
    `(marks, corrections)`, the file's new state.

    Deliberately narrower than `bump_watermark`: it touches ONE space, never
    reads `live_max_ids` (a correction is not an allocation and must not be
    justified by one), and preserves the file's existing `basis` line
    untouched — that line records the last ALLOCATION-driven bump, and a
    correction is not one."""
    path = Path(root) / WATERMARK
    if not path.is_file():
        raise ValueError(
            "{} is missing — a correction needs a mark to correct. Regenerate "
            "with `trace.py --bump-ids` first.".format(WATERMARK)
        )
    if space not in WATERMARK_SPACES:
        raise ValueError(
            "{!r} is not a watermark space ({})".format(
                space, ", ".join(WATERMARK_SPACES)
            )
        )
    marks = read_watermark(root)
    corrections = read_corrections(root)
    if corrections.get(space):
        was, now, ruling = corrections[space][0]
        raise ValueError(
            "{} already carries a recorded correction ({} -> {} by {}) — the "
            "correction verb is ONE-SHOT and refuses to replay".format(
                space, was, now, ruling
            )
        )
    was = marks.get(space, 0)
    if new_value <= was:
        raise ValueError(
            "correction must RAISE {} above its current mark of {} (asked for "
            "{}) — a mark never falls, and a correction that does not raise "
            "corrects nothing".format(space, was, new_value)
        )
    # THE WRITER CHECKS THE AUTHORITY TOO, and not because the checker is in
    # doubt: `_correction_record_findings` is the authority, but a verb that
    # writes an unresolvable record and leaves the repo red at the NEXT run has
    # taught the operator nothing at the moment they could still fix it.
    refusals = _one_correction_findings(
        space, [(was, new_value, str(ruling_id))], ruled_open_item_texts(root)
    )
    if refusals:
        raise ValueError(refusals[0])
    text = path.read_text(encoding="utf-8-sig", errors="replace")
    basis_match = re.search(r"^#\s*basis:\s*(.*)$", text, re.MULTILINE)
    basis = basis_match.group(1).strip() if basis_match else ""
    marks[space] = new_value
    corrections[space] = [(was, new_value, str(ruling_id))]
    reservations = id_carrier.parse_reservations(text)
    path.write_text(
        render_watermark(marks, basis, corrections, reservations),
        encoding="utf-8",
        newline="\n",
    )
    return marks, corrections


def reserve_ids(root, wi, counts):
    """`--reserve-ids WI SPACE=N[,...]`: reserve on the id carrier
    (`check_work_item`, then `id_carrier.reserve`, every refusal raised as
    `id_carrier.Refused` before any write), then fold the moved carrier into
    the working watermark, left for the caller to commit. Returns the
    reserved ranges.

    Implements: SR-174, LLR-362"""
    ranges = id_carrier.reserve(
        root,
        check_work_item(wi),
        counts,
        WATERMARK_SPACES,
        lambda marks, records, corr: render_watermark(marks, "", corr, records),
        lambda: _trunk_name(root),
    )
    fold_watermark(root)
    return ranges


def check_work_item(text):
    """The one work-item id the reserve verb's argument names, read by the
    kit's one lane-input parser (`agent_common.parse_wi_id`) once the verb's
    own normalization (outer whitespace) is applied; anything else is
    `id_carrier.Refused`, one line naming the value.

    Implements: SR-174, LLR-362
    """
    import agent_common as ac  # IF-224; deferred: only a reservation asks

    try:
        return ac.parse_wi_id((text or "").strip(), "work item")
    except ValueError as exc:
        raise id_carrier.Refused(str(exc)) from None


def _trunk_name(root):
    """The declared trunk's name, through the kit's one trunk reader, or
    `id_carrier.Refused` naming the declaration.

    Implements: SR-174, LLR-362
    """
    import agent_common as ac  # IF-224; deferred: only a reservation asks

    try:
        return ac.trunk_name(root)
    except ac.TrunkUndeclared as exc:
        raise id_carrier.Refused("the trunk claim cannot be read: {}".format(exc))


def fold_watermark(root):
    """`--fold-ids`: write the fold of the receiving watermark (index stages 2
    and 3 while it is conflicted, else the working file) and the carrier tip's
    records with the marks they justify (`id_carrier.carried`; no carrier: the
    working sides alone) into the working `docs/id-watermark`, with the basis
    recomputed from the working tree's live ids. Refused when there is nothing
    to fold. Returns the folded marks.

    Implements: SR-174, LLR-363"""
    sides = id_carrier.receiving_sides(root)
    tip = id_carrier.carrier_tip(root)
    sides.append(id_carrier.carried(id_carrier.carrier_text(root, tip)))
    if not any(sides):
        raise id_carrier.Refused(
            "nothing to fold: no {} and no id carrier".format(WATERMARK)
        )
    marks, records, corrections = id_carrier.fold(sides)
    text = render_watermark(marks, _basis(live_max_ids(root)), corrections, records)
    (Path(root) / WATERMARK).write_text(text, encoding="utf-8", newline="\n")
    return marks


def triangle_findings(tcs, llrs):
    """SR/LLR citation coherence. A TC may cite an
    SR and an LLR together so one test discharges both the "SR needs a TC" and
    "LLR needs a TC" rules; the SR<->LLR relationship itself is recorded
    canonically on the LLR's SR-Refs. This keeps the derived citation honest: when
    a TC cites both an SR and an LLR, each cited LLR must descend from one of the
    SRs the same TC cites (its SR-Refs must intersect them). An incoherent pairing
    (a TC citing LLR-1 next to SR-2 when LLR-1 decomposes SR-1) is wrong at any
    stage, so it joins the integrity floor, not the gate-scoped orphan set. A TC
    that cites only LLRs (no SR) has no SR to contradict — the orphan rules cover
    it. An LLR with no SR-Refs is already an orphan, so it is not double-reported.

    Implements: SR-157, LLR-002
    """
    llr_parents = {
        r["LLR-ID"]: set(refs(r.get("SR-Refs"))) for r in llrs if r.get("LLR-ID")
    }
    out = []
    for r in tcs:
        tid = r.get("TC-ID")
        if not tid:
            continue
        cited = refs(r.get("Verifies"))
        cited_srs = {x for x in cited if ID_PATTERNS["SR"].match(x)}
        if not cited_srs:
            continue
        for x in cited:
            parents = llr_parents.get(x)
            if parents and not (parents & cited_srs):
                out.append(
                    "TC {} cites {} alongside SR {} but {} decomposes {} (its "
                    "SR-Refs) — an SR/LLR pair in one TC must share the parent "
                    "link recorded on the LLR".format(
                        tid,
                        x,
                        ", ".join(sorted(cited_srs)),
                        x,
                        ", ".join(sorted(parents)),
                    )
                )
    return out


# The module-path normalizer MOVED TO trace_text.py at re-tier v2 S5 (WI-464),
# unchanged: `module_endpoints` and the endpoint classifier there read the same
# two naming conventions this module's seam rules do, so one home there beat a
# fourth copy here. Aliased back under the private name so this module's call
# sites read as before.
_norm_module = norm_module


def interface_findings(ifs, module_ids, root=None):
    """The IF-### seam tier's own integrity rules (process.md §8), as
    ``(findings, advisories)``.

    *findings* join the --strict failure set: an `Owner` cell that names a
    requirement or design ID, or several endpoints, is the wrong SHAPE — since
    OI-67 (ruled (a), 2026-08-29) the owner is the providing THING, in the one
    spelling `Consumers` uses (a module path, a file or directory path, or an
    `external:` party), and the requirement it answers to is REACHED through
    it, never stated on the row. *advisories* are warn-only: a row naming both
    `Requestors` and `Consumers`, or neither, has no direction (incomplete, as
    an empty required cell is — warn-first for the same migration reason); a
    module-shaped owner that no design row's `Module` names and whose header
    declares no `Implements:` line traces to no requirement — reported, never gated,
    because a file- or external-owned seam legitimately has no design row and
    the class that does is a debt list, not a gate.

    A row whose owner is `external:` and whose far side names no in-tree
    endpoint is a finding of the same strict class: it is not a seam of THIS
    system at all — a crossing between two external parties lives in
    `external.toml` — and, mechanically, a row with no kit module on either
    side has nowhere to put its definition, since the definition's one home is
    an owner's header and an external party's header is not ours to write.

    The `Req-Refs` back-link this function once policed left with the cell;
    seam-to-test coverage was never on it (it joins on a TC's `Verifies`). A
    registry still carrying one of the five RETIRED cells (`Contract`,
    `Provider`, `Req-Refs`, `Signal`, `SignalNote`) is a finding too — the
    wrong SHAPE, as an id-shaped owner is: the definition lives in the owner's
    `Contract IF-###:` body and the other four are derived or subsumed, so a
    value in any of them is a second, unread copy of a fact that has one home.
    Detected by PRESENCE, per registry — see `_retired_cell_findings`.

    Implements: SR-159, LLR-041
    """
    findings, advisories = [], []
    norm_modules = {_norm_module(m) for m in module_ids}
    norm_modules.discard("")
    implementers = _implementing_modules(root)
    findings.extend(_retired_cell_findings(ifs, root))
    for r in ifs:
        iid = r["IF-ID"]
        has_req = bool((r.get("Requestors") or "").strip())
        has_con = bool((r.get("Consumers") or "").strip())
        if has_req == has_con:
            # Warn-first like the required-cell rule it is a form of: a row
            # with no far side is INCOMPLETE (an adopter mid-migration), where
            # an id-shaped owner below is WRONG — the retired meaning, stated.
            advisories.append(
                f"IF {iid} names {'both' if has_req else 'neither'} Requestors "
                "and Consumers — the far side names the DIRECTION (requestors "
                "put information into the owner's surface, consumers take what "
                "it emits), so a row carries exactly one of the two"
            )
        cell = (r.get("Owner") or "").strip()
        if not cell:
            continue  # the required-field rule already says this
        ends = [e.strip() for e in cell.split(";") if e.strip()]
        if len(ends) != 1:
            findings.append(
                f"IF {iid} Owner={cell!r} names {len(ends)} endpoints — one row "
                "has ONE owner, the thing the information plugs into"
            )
            continue
        owner = ends[0]
        if _ID_SHAPED_RE.match(owner):
            findings.append(
                f"IF {iid} Owner={owner!r} names a requirement or design id — the "
                "owner is the providing THING (a module path, a file or "
                "directory path, or `external:<party>`); the requirement is "
                "reached through it, never stated on the row"
            )
            continue
        if owner.startswith(EXTERNAL_ENDPOINT_PREFIX):
            # NO IN-TREE ENDPOINT ON EITHER SIDE. The external arm of the
            # definition gate states our reading of an external surface in the
            # header of the kit module that FACES it — so a row whose far side
            # is external too has no such module, owes its definition nowhere,
            # and passed every rule on this tier (adversarial review
            # 2026-08-29, F2). A row with NO far side at all is deliberately
            # left to the warn-first advisory above: that is one incompleteness
            # and it is reported once, at the severity the migration was ruled.
            far = _far_endpoints(r)
            if far and all(e.startswith(EXTERNAL_ENDPOINT_PREFIX) for e in far):
                findings.append(
                    f"IF {iid} has no in-tree endpoint — owner {owner!r} and "
                    "its far side are all `external:`; a crossing between two "
                    "external parties is not a seam of this system "
                    "(external.toml), and a row with no kit module on either "
                    "side has no home for its definition"
                )
            continue
        if owner.endswith("/") or not module_endpoints(owner):
            continue  # a file or directory medium: no design row is expected
        norm = _norm_module(owner)
        if norm_modules and norm not in norm_modules and norm not in implementers:
            advisories.append(
                f"IF {iid} owner {owner!r} is named by no design row's Module and "
                "declares no `Implements:` line — this seam traces to no "
                "requirement (warn-only; name the module on a design row, or "
                "declare its parents in the module header)"
            )
    return findings, advisories


# An `Owner` cell that is an ID rather than a thing: the shape OI-67 retired.
_ID_SHAPED_RE = re.compile(r"^(?:SN|SR|LLR|TC|IF|CMP|B|EXT|REL)-\d+$")

# The five cells OI-67 took off the row, as (carrier column, TOML key): a
# carrier that still maps the column hands the row the column name, one that
# no longer maps it hands the key back as itself, and both spellings are the
# same retired cell.
_IF_RETIRED_CELLS = (
    ("Contract", "contract"),
    ("Provider", "provider"),
    ("Req-Refs", "req_refs"),
    ("Signal", "signal"),
    ("SignalNote", "signal_note"),
)


def _far_endpoints(row):
    """A row's far side as a list of endpoints — `Requestors` or `Consumers`,
    whichever is set, in that order (the row carries exactly one; a row
    carrying both is the advisory's finding, and reading the first is enough
    to answer "is anything in-tree on the other side").

    BOTH CARRIERS ARRIVE HERE AS A `;`-JOINED STRING, measured rather than
    assumed: the far side is a LIST under TOML, but `spine_carrier.load` maps
    every value through `value_to_cell`, which joins an array on `;` — the
    separator the CSV cells already used. So one split reads both, and no
    list-shaped arm is written for a shape that cannot arrive (the two
    `Requestors`/`Consumers` reads directly above already assume the string,
    and a second, more tolerant reader here would only disagree with them)."""
    for key in ("Requestors", "Consumers"):
        ends = [e.strip() for e in (row.get(key) or "").split(";") if e.strip()]
        if ends:
            return ends
    return []


def _retired_cell_findings(ifs, root):
    """One finding per RETIRED cell the interface registry still carries — by
    the KEY'S PRESENCE, not by its value, and once per registry rather than
    once per row.

    THE RETIRED SHAPE IS THE KEY, NOT ITS VALUE. The rule until the 2026-08-29
    adversarial review (F7) tested the value, per row, and that asks the wrong
    question twice: a key can be present and empty, and presence is a property
    of the REGISTRY rather than of any one row. On the legacy CSV carrier that
    is a live hole — a retired column sits in the HEADER of every row, so a
    value test reads it as absent for as long as nobody fills it in, and the
    registry can carry it indefinitely by keeping it blank.
    `spine_carrier.columns` is the one reader that answers "which columns does
    this registry use" for both carriers — the union of the keys rows set under
    TOML, the header row under CSV — so the rule is stated once and cannot
    answer differently per carrier.

    TWO SHAPES ARE DELIBERATELY NOT RE-CHECKED HERE, because `spine_carrier`
    already refuses them over every TOML registry it loads, this tier included:
    an explicit `provider = ""` (`empty_value_findings` — under that carrier an
    unset cell is an ABSENT key, and an explicit empty is the third state the
    readers disagree about) and a cell that is itself a table,
    `[interface.IF-002.legacy]` (`nested_table_findings`). Both land as a hard
    refusal carrying their own text, so `--strict` reds either way; a second
    copy of a rule that already fires is what the 0→A→B rule forbids.

    `root` is None only for a caller passing rows with no tree behind them; the
    union of the rows' own keys is then the honest answer (it is exactly what
    `columns` computes under TOML, and a CSV row carries every header column)."""
    live = None
    if root is not None:
        live = spine_carrier.resolve(Path(root) / "docs/requirements/interfaces.toml")
    if live is None:
        present, header_carrier = {c for r in ifs for c in r}, False
    else:
        present = set(spine_carrier.columns(live, "IF-ID"))
        header_carrier = live.suffix != ".toml"
    out = []
    for column, key in _IF_RETIRED_CELLS:
        spellings = {column, key} & present
        if not spellings:
            continue
        if header_carrier:
            where = "the header column `{}`".format("`, `".join(sorted(spellings)))
        else:
            rows = sorted(str(r.get("IF-ID") or "") for r in ifs if spellings & set(r))
            where = "set on " + (", ".join(rows) if rows else "an example row only")
        out.append(
            f"the interface registry carries the retired `{key}` cell ({where}) "
            "— the definition lives in the owner's `Contract IF-###:` body and "
            "the row is one owner, its far side, a channel and an optional "
            "`data`; delete the cell (process.md §8)"
        )
    return out


def _implementing_modules(root):
    """The normalized module keys whose header declares an `Implements:` line —
    the second way an owner reaches the spine — or an empty set when there is
    no source surface to read (no root, `files` mode, a copied script).

    The report keys each file relative to the source root's PARENT (its paths
    open with the root's own last segment), so a key is rebuilt from that
    parent: joined to the whole declared root it names `scripts/scripts/<mod>`
    under the kit's own profile, and matches no owner."""
    if gen_arch_map is None or root is None:
        return set()
    try:
        src, mode = check_trajectory._arch_scan_profile(root)
    except (OSError, ValueError):  # pragma: no cover - not this rule's finding
        return set()
    if mode == "files":
        return set()
    src_dir = root / src.strip().replace("\\", "/").rstrip("/")
    if not src_dir.exists():
        return set()
    sites, _known = gen_arch_map.implements_report([src_dir])
    base = src_dir.parent
    return {_norm_module((base / rel).relative_to(root).as_posix()) for rel in sites}


def placeholder_findings(label, raw_rows):
    """Leftover template example rows (ids ending '-000') in one registry.

    Implements: SR-157, LLR-003
    """
    key = id_key(label)
    return [
        f"{label} placeholder row {r[key]} still present "
        "(replace the template example before this gate)"
        for r in raw_rows
        if r.get(key) and is_example(r[key])
    ]


def scan_sn_placeholders(sn_md):
    """Sorted unique '-000' SN ids still present in the needs registry.

    `sn_md` is the CARRIER-RESOLVED path the loader found, so None here means
    the registry is genuinely absent rather than "not under the suffix I
    guessed"."""
    if sn_md is None or not sn_md.exists():
        return []
    text = sn_md.read_text(encoding="utf-8-sig", errors="replace")
    return sorted({u for u in re.findall(r"\bSN-\d+\b", text) if is_example(u)})


# SN maturity lives in section-as-state (derived-gate model §4a): a stakeholder-
# needs.md heading whose text contains "draft" (case-insensitive, e.g. `## Draft
# needs (unapproved)`) marks the SNs under it as Draft (unapproved, DevStg-Below); SNs under
# any other heading are approved (DevStg-Reqs). No new column — the state IS the section,
# and the approval date is git-derived (the commit that moved the row out of
# the draft section). This is the SN analogue of the `Status=Draft` bit on
# SR/LLR/TC rows.
_HEADING_RE = re.compile(r"^\s{0,3}#{1,6}\s+(.*)")


def sn_integrity_findings(sn_text):
    """Duplicate-id protection for the SN tier — the one tier stored as prose,
    and until now the one tier without it (every CSV tier gets
    integrity_findings). Two shapes are wrong at any stage: an SN id on more
    than one `|SN-###|` table row (a copy-pasted row; _sn_prose last-wins
    silently otherwise), and an id under BOTH a draft and a non-draft heading
    (simultaneously exempt from the child rules and approved — sn_draft_ids
    marks it draft, silently exempting an approved need)."""
    row_counts = {}
    draft_rows, approved_rows = set(), set()
    in_draft = False
    for line in sn_text.splitlines():
        m = _HEADING_RE.match(line)
        if m:
            in_draft = "draft" in m.group(1).lower()
            continue
        rm = re.match(r"\|\s*(SN-\d+)\s*\|", line)
        if not rm or is_example(rm.group(1)):
            continue
        rid = rm.group(1)
        row_counts[rid] = row_counts.get(rid, 0) + 1
        (draft_rows if in_draft else approved_rows).add(rid)
    out = []
    for rid in sorted(row_counts, key=id_sort_key):
        if row_counts[rid] > 1:
            out.append(f"SN id {rid} is duplicated ({row_counts[rid]} table rows)")
    for rid in sorted(draft_rows & approved_rows, key=id_sort_key):
        out.append(f"SN id {rid} appears under both a draft and a non-draft heading")
    return out


def _tc_verifies_required(row):
    """Whether a test case must name what it verifies: unless its
    `Assumption-Refs` names an assumption it evidences instead.

    A test of an assumption can stand alone where no requirement is its subject,
    so requiring `Verifies` everywhere would force it to cite a requirement it
    does not test. A case naming neither is still refused, and the citation
    rule (`coherence.tc_citation_findings`) reports it as verifying nothing.

    Implements: SR-197, LLR-229
    """
    return not refs(row.get("Assumption-Refs"))


def schema_findings(label, rows):
    """Empty required fields and out-of-vocabulary Verification/Tier values, over
    the real (non-placeholder) rows of one registry.

    Implements: SR-157, LLR-003
    """
    key = id_key(label)
    out = []
    for r in rows:
        rid = r[key]
        for col in REQUIRED_FIELDS[label]:
            if not (r.get(col) or "").strip():
                out.append(f"{label} {rid} has empty required field {col}")
        for col, allowed in ENUM_FIELDS.get(label, {}).items():
            if col in INTEGRITY_ENUM_COLS:
                continue  # `enum_integrity_findings` owns these — see that name
            val = (r.get(col) or "").strip()
            if val and val not in allowed:
                out.append(
                    f"{label} {rid} has {col}={val!r} (allowed: "
                    f"{', '.join(sorted(allowed))})"
                )
        # A TC names what it verifies unless it evidences assumptions instead.
        verifies = (r.get("Verifies") or "").strip()
        if label == "TC" and not verifies and _tc_verifies_required(r):
            out.append(f"TC {rid} has empty required field Verifies")
        # A TC claiming Automated=Yes must
        # cite its Evidence (pytest node / path / procedure link) — a
        # claimed-automated test with no cited location is a soft false-green.
        # Conditional on the claim, so it can't live in REQUIRED_FIELDS; a
        # legacy CSV without the column reads as empty and is flagged the same
        # way (the ADOPTING §6 migration adds the column).
        if label == "TC" and (r.get("Automated") or "").strip().lower() == "yes":
            if not (r.get("Evidence") or "").strip():
                out.append(
                    f"TC {rid} is Automated=Yes but cites no Evidence "
                    "(name the test: a pytest node, script path, or "
                    "procedure-doc link)"
                )
    return out


def schema_advisories(label, rows):
    """`schema_findings`' warn-first twin, for the tiers whose schema is stated
    but not yet promoted to a gate (IF, CMP — WI-443 / OI-14 part B).

    SAME two dictionaries, deliberately: the vocabulary of a tier has ONE home
    whatever the enforcement level reads it at, so promoting IF to ERROR later is
    a change to which list a caller appends to, never a second copy of the
    allowed values that can drift from this one. Returns advisory strings; the
    caller routes them into the warn pipe, and nothing here reaches an exit
    code.

    An adversarial round proposed HARDENING the required-field half to match
    the CSV era and the proposal was REFUTED on measurement: the IF tier had
    NO cell-level guarantee on CSV (no schema tier existed at all — the OI-14
    finding), and the structural floor's TOML equivalent is the carrier parse
    error plus the dual-carrier refusal, both already hard. Hardening
    cell-emptiness here would red every migrating adopter for a guarantee the
    registry never had; the ruled warn-first-then-promote path stands."""
    key = id_key(label)
    out = []
    for r in rows:
        rid = r.get(key) or "(unnamed row)"
        for col in REQUIRED_FIELDS[label]:
            if not (r.get(col) or "").strip():
                out.append(f"{label} {rid} has empty required field {col}")
        for col, allowed in ENUM_FIELDS.get(label, {}).items():
            val = (r.get(col) or "").strip()
            if val and val not in allowed:
                out.append(
                    f"{label} {rid} has {col}={val!r}, which is not in the closed "
                    f"vocabulary (allowed: {', '.join(sorted(allowed))})"
                )
    return out


def frame_findings(exts, bifs, rels):
    """Reference resolution inside `external.toml` (WI-442, §1R.5) as a list of
    finding strings — the frame's own join rules.

    PLAIN STRINGS, not the `(at_fault_id, finding)` pairs the spine's older rules
    return. The pair shape was written here first and NO caller ever read the id,
    which documents a contract that does not exist; `tc_citation_findings` keeps
    its pairs because its caller genuinely keys on them.

    It checks three reference fields — a boundary row's `Entity`, and a
    relationship's `From` and `To` — and they are the only structural claims the
    ruled schema makes. Everything else about the frame — is it the RIGHT frame,
    are the crossings complete — is a human ruling, and a check that pretended
    otherwise would be inventing a rule nobody wrote.

    FAILURE CLASS, not advisory, unlike the schema tier beside it. A tie-back to
    an entity that does not exist is not a maturing corpus converging on a
    vocabulary; it is a dangling reference, exactly like an SR citing an SN that
    was deleted, and the spine's other reference rules have been hard since they
    shipped. Note what it does NOT check: a relationship carries no interface
    vocabulary by design, so there is nothing here that could grow one.

    NO ENTITIES IS ONLY VACUOUS WHEN NOTHING REFERENCES THEM, and getting that
    wrong was a false green — the one failure this file exists to prevent. The
    first version returned `[]` on an empty entity set, reasoning that the rules
    below had nothing to resolve against. They did: 6 crossings referencing 5
    entities that do not exist resolved to silence, and `_frame_report_section`
    then printed "every crossing Entity ... resolves" over the top of it. That is
    the natural state of a half-authored frame (you draw the boundary, then name
    who is on the far side) and of a refactor that drops an entity block. An
    empty frame is still vacuous; an empty entity set under a non-empty crossing
    or relationship set is a finding of its own."""
    out = []
    ext_ids = {r["EXT-ID"] for r in exts}
    if not ext_ids:
        if bifs or rels:
            out.append(
                "external.toml declares {} crossing(s) and {} relationship(s) "
                "but NO entity — every reference in them resolves to "
                "nothing".format(len(bifs), len(rels))
            )
        return out
    for r in bifs:
        bid = r["B-ID"]
        for x in refs(r.get("Entity")):
            if x not in ext_ids:
                out.append(f"boundary {bid} Entity references unknown {x}")
    for r in rels:
        rid = r["REL-ID"]
        for col in ("From", "To"):
            for x in refs(r.get(col)):
                if x not in ext_ids:
                    out.append(f"relationship {rid} {col} references unknown {x}")
    return out


def sr_boundary_findings(srs, bifs, ifs):
    """SN-037's SR->boundary rule (WI-442), as `(findings, advisories)` — both
    plain lists of strings, per `frame_findings`' note on the pair shape.

    SN-037's approved acceptance asks that *"every system-requirement input and
    output references a declared interface"* and that *"unresolved references ...
    are mechanical findings"*. Those are two obligations at two severities, and
    conflating them is what would make this check either useless or unshippable:

      * RESOLUTION IS HARD. An SR whose `Boundary-Refs` names a crossing that is not
        declared is a dangling reference, exactly like an SR citing a deleted SN,
        and it joins the --strict failure set with the spine's other reference
        rules. It is also the only half that can be true today.

      * COVERAGE IS ADVISORY, and deliberately so. Making "every SR names a
        crossing" an error would red 148 rows the moment the column existed, for
        work that belongs to the re-tier campaign (WI-451 slice 2) and under a
        form rule that is itself a GUIDELINE with recorded per-row waivers
        (2026-08-13v). A gate that is 100% red on the day it ships is a gate
        someone turns off. So the uncovered count is reported as ONE summary
        line — the number the campaign has to move — and never as 148 findings.

    THE THIRD CLAUSE IS NOT ENFORCED HERE. "Every declared component-boundary
    crossing has an interface row" is decision 6 (a BIF with no realizing IF),
    deferred BY RULING to post-schema, so this reports the realization gap as an
    advisory and gates nothing on it. `ifs` is read for exactly that count, and
    the same restraint is why `spine_rules.boundary_incomplete` reads approval
    and not realization.

    Vacuous with no frame registry: a project that declares no boundary has no
    crossing an SR could name."""
    findings, advisories = [], []
    bif_ids = {r["B-ID"] for r in bifs}
    if not bif_ids:
        return findings, advisories
    named = set()
    for r in srs:
        sid = r["SR-ID"]
        cited = refs(r.get("Boundary-Refs"))
        named.update(x for x in cited if x in bif_ids)
        for x in cited:
            if x not in bif_ids:
                findings.append(
                    f"SR {sid} Boundary-Refs references unknown crossing {x}"
                )
    uncovered = sum(1 for r in srs if not refs(r.get("Boundary-Refs")))
    if uncovered:
        advisories.append(
            "SR->boundary coverage: {} of {} requirement(s) name no crossing in "
            "Boundary-Refs (SN-037; the re-tier campaign is what moves this number, "
            "and a row that legitimately states no boundary observable records "
            "its reason rather than leaving a blank cell)".format(uncovered, len(srs))
        )
    unnamed = sorted(bif_ids - named)
    if unnamed:
        advisories.append(
            "boundary crossing(s) named by NO requirement: {} — a crossing with "
            "no SR is a frame nobody has stated an observable at".format(
                ", ".join(unnamed)
            )
        )
    realized = {
        x
        for r in ifs
        for col in ("InterfaceFromExternal", "InterfaceToExternal")
        for x in refs(r.get(col))
    }
    unrealized = sorted(bif_ids - realized)
    if unrealized:
        advisories.append(
            "boundary crossing(s) realized by NO interface row: {} — decision 6's "
            "question, deferred by ruling; reported, never gated".format(
                ", ".join(unrealized)
            )
        )
    return findings, advisories


HAT_ROSTER_REL = "docs/requirements/hats.toml"


def load_hat_names(root):
    """`(names, speaks_for)` from `docs/requirements/hats.toml`: the declared
    hat NAMES as a set, and `{hat name: stakeholder id}` for each hat recording
    the stakeholder it speaks for (SR-213). Most hats record none, so the map
    is usually empty; it rides this read because the checker may not import
    `hats` (below), and a third reader of the roster would be one too many.

    A SECOND READER OF THAT FILE, DELIBERATELY, AND THE SPLIT IS WHAT MAKES IT
    SAFE. `hats.py` is the roster's owner and the only validator of its CONTENT —
    the three required keys, the closed `applies_when` grammar, the unknown-key
    refusal. This reads exactly one thing that module does not answer for anybody
    else: IS THIS NAME DECLARED. Two readers of one file are a drift hazard only
    when they answer the SAME question two ways; these answer different questions,
    and `tests/test_trace_hats.py` pins this path against `hats.ROSTER_REL` so
    the two cannot separate silently. (A test may import both modules; this one may not —
    `hats.py` is CMP-008 and `trace.py` is CMP-006, and the declared crossing
    between them already runs the other way, IF-133. Importing it here would mint
    a component-level cycle to save a `tomllib.load`.)

    ABSENT IS OPT-OUT, exactly as the roster's own header states: no file, no
    declared names, and `hat_findings` goes vacuous rather than reporting every
    `Hat-Refs` in the repo as dangling. A file that exists and will not parse
    yields the empty set too — LOUDLY WRONG IS NOT AVAILABLE HERE, because this
    is an advisory-and-findings pass, not the roster's load path, and `hats.py`
    raises `HatsError` on that same file the moment any composer touches it.
    The `speaks_for` SHAPE is that module's to judge too: a non-blank value is
    carried here as text, stripped, and resolving it is `hat_findings`' job.

    Implements: SR-213, LLR-251"""
    path = Path(root) / HAT_ROSTER_REL
    if not path.exists():
        return set(), {}
    try:
        data = tomllib.loads(path.read_text(encoding="utf-8"))
    except (OSError, tomllib.TOMLDecodeError):
        return set(), {}
    table = data.get("hat")
    if not isinstance(table, dict):
        return set(), {}
    speaks_for = {
        name: row["speaks_for"].strip()
        for name, row in table.items()
        if isinstance(row, dict)
        and isinstance(row.get("speaks_for"), str)
        and row["speaks_for"].strip()
    }
    return set(table), speaks_for


def effective_hats(row, sr_by_id):
    """One design row's EFFECTIVE hat set: its own `Hat-Refs` unioned with those
    of its SR parents. Returns a sorted list.

    THIS FUNCTION IS THE ANTI-STALENESS DECISION, and it is the whole reason the
    LLR cell is defined as "raised AT this decomposition" rather than "everything
    that bears on this row". The alternative — copying the parent's hats down at
    authoring time — makes re-ruling ONE requirement a sweep over every child it
    has, which is the hand-maintenance this design exists to escape, one tier down
    and multiplied by the fan-out. Deriving means an SR-tier change propagates on
    the next read and corrects no LLR cell at all.

    A dangling `SR-Refs` contributes nothing rather than raising: parentage is
    already a reported finding of its own, and a derivation that crashed on it
    would report the same defect twice, the second time as a stack trace."""
    own = set(refs(row.get("Hat-Refs")))
    for pid in refs(row.get("SR-Refs")):
        parent = sr_by_id.get(pid)
        if parent:
            own.update(refs(parent.get("Hat-Refs")))
    return sorted(own)


def _speaks_for_findings(speaks_for, stakeholders):
    """Each hat whose `speaks_for` names a stakeholder the list does not
    declare, naming the hat and the stakeholder. Vacuous with no stakeholder
    list: a project that declares no stakeholders has none to resolve."""
    if not stakeholders:
        return []
    return [
        f"hat {name} speaks_for names {stk}, which is not a declared stakeholder"
        for name, stk in sorted((speaks_for or {}).items())
        if stk not in stakeholders
    ]


def hat_findings(
    srs, llrs, hat_names, sr_by_id=None, speaks_for=None, stakeholders=None
):
    """SR/LLR `Hat-Refs` resolution, as `(findings, advisories)` — the pair shape
    `frame_findings` documents.

    The severity split is `sr_boundary_findings`' and is taken for its stated
    reason rather than a new one:

      * RESOLUTION IS A FINDING. A `Hat-Refs` naming a hat the roster does not
        declare is a dangling reference in the same class as an SR citing a
        deleted SN, and it joins the --strict failure set. This is the arm that
        stops the cell rotting when a hat is retired, and it is EXISTENCE
        checking rather than meaning checking, which is what keeps it inside
        what D-4 permits.

      * COVERAGE IS AN ADVISORY, and never anything else. `Hat-Refs` is absent on
        almost every row the day it ships, because the backfill is its own work
        item; making presence an error would red the whole spine on day one,
        which is how a gate becomes a gate somebody turns off. So the uncovered
        count is ONE summary line — the number the backfill has to move.

    COVERAGE IS COUNTED OVER EFFECTIVE SETS, NOT OVER CELLS, and the distinction
    is the design's own: a design row whose parent requirement carries hats IS
    attributable to them, so counting its blank cell as "unattributed" would
    report the derived half of this feature as if it did not exist — and would
    push an author toward the copy-down the derivation exists to forbid.
    `sr_by_id` is what makes that reading available; without it (a caller with no
    parent index) the count degrades to the cell reading, which is the same
    answer for the SR tier and an over-report for the LLR tier.

    Vacuous with no roster: absence is opt-out for the whole hats layer, so a
    project that declares no perspectives has no name a row could fail to cite.

    A PERSPECTIVE'S `speaks_for` RESOLVES HERE TOO (SR-213): `speaks_for` maps
    each hat to the stakeholder it voices, as `load_hat_names` read it, and
    `stakeholders` is the declared stakeholder ids. One naming an undeclared
    stakeholder is a finding in this same class, the same existence check one
    registry over; with no stakeholder list it is vacuous.

    Implements: SR-213, LLR-251"""
    findings, advisories = [], []
    if not hat_names:
        return findings, advisories
    parents = sr_by_id or {}
    named = set()
    for label, id_col, rows in (("SR", "SR-ID", srs), ("LLR", "LLR-ID", llrs)):
        for r in rows:
            cited = refs(r.get("Hat-Refs"))
            named.update(x for x in cited if x in hat_names)
            for x in cited:
                if x not in hat_names:
                    findings.append(
                        f"{label} {r[id_col]} Hat-Refs references unknown hat {x}"
                    )
    findings += _speaks_for_findings(speaks_for, stakeholders)
    rows = list(srs) + list(llrs)
    total = len(rows)
    uncovered = sum(
        1
        for r in rows
        # An SR has no parent tier here, so `effective_hats` reduces to its own
        # cell; an LLR picks its parents' up. One expression, both tiers.
        if not effective_hats(r, parents)
    )
    # BOTH advisories below are gated on the cell being IN USE — at least one row
    # carrying an attribution — and that gate is not a convenience. A freshly
    # bootstrapped project ships the roster (16 hats) and no `Hat-Refs` anywhere,
    # so an ungated pair greets a first-run adopter with "every row records
    # nothing" plus sixteen named perspectives called "unrecorded or ceremony",
    # about a layer they have not opted into yet. That is this kit's own
    # FIRST-RUN-ADOPTER failure class — noise a stranger cannot act on — and it
    # is how an advisory pipe stops being read. Fill one cell and both lines
    # light up, which is exactly when the question becomes answerable.
    if not any(refs(r.get("Hat-Refs")) for r in rows):
        return findings, advisories
    # (The in-use gate reads CELLS, not effective sets, deliberately: "has anyone
    # opted into this layer" is a question about what was authored, and an
    # effective-set reading of it would be circular — no cell filled anywhere
    # means no effective set anywhere.)
    if uncovered:
        advisories.append(
            "hat coverage: {} of {} requirement/design row(s) are attributable "
            "to no declared perspective — counted over EFFECTIVE sets, so a "
            "design row inheriting its parent's hats is covered; an unattributed "
            "row reads as NOT RECORDED and never as 'no perspective applied'".format(
                uncovered, total
            )
        )
    unnamed = sorted(hat_names - named)
    if unnamed:
        advisories.append(
            "declared hat(s) attributed to NO row: {} — a perspective every "
            "decomposition faces and no requirement is traceable to is either "
            "unrecorded or ceremony".format(", ".join(unnamed))
        )
    return findings, advisories


def tieback_findings(ifs, bifs):
    """An IF row's directional tie-back must name a DECLARED crossing (WI-442,
    owner naming 13m), as a list of finding strings.

    Vacuous with no frame registry, which is the applies-when: a project without
    `external.toml` has no crossings to name, and a stray tie-back there is a
    schema question, not a resolution one.

    WHAT THIS CANNOT CATCH, said out loud because the template says it too: a
    tie-back that RESOLVES but does not belong — an internal seam claiming to
    realize B-05 — is indistinguishable from a correct one to any check. That
    judgment is the re-tier's and the reviewer's."""
    out = []
    bif_ids = {r["B-ID"] for r in bifs}
    if not bif_ids:
        return out
    for r in ifs:
        iid = r["IF-ID"]
        for col in ("InterfaceFromExternal", "InterfaceToExternal"):
            for x in refs(r.get(col)):
                if x not in bif_ids:
                    out.append(f"IF {iid} {col} references unknown crossing {x}")
    return out


def _hat_report_section(hat_names, findings):
    """The report's declared-perspectives section, or nothing when the project
    declares no roster and nothing names a hat (an assumption's obstacle
    perspectives still fail with no roster, and are listed). A HELPER rather than a branch inside `render_report` for
    the reason `_frame_report_section` below is one: that assembler is already at
    the complexity ratchet's ceiling, and a section that renders conditionally is
    exactly the shape this file has agreed to lift out of it."""
    if not (hat_names or findings):
        return []
    body = (
        [f"- {f}" for f in findings]
        if findings
        else [
            "{} declared hat(s); every Hat-Refs on an SR or LLR resolves to one "
            "of them.".format(len(hat_names))
        ]
    )
    return ["", "## Declared perspectives (hats; process.md §1)", ""] + body


def _frame_report_section(exts, bifs, rels, findings):
    """The report's depth-0 frame block (WI-442), or `[]` when no frame is
    declared — a named helper rather than another arm inside `render_report`,
    which the complexity ratchet holds at its committed count and which is
    already a long list-builder."""
    if not (exts or bifs or rels or findings):
        return []
    body = (
        [
            "{} entity, {} boundary-crossing and {} relationship row(s); every "
            "crossing Entity, relationship From/To and IF tie-back "
            "resolves.".format(len(exts), len(bifs), len(rels))
        ]
        if not findings
        else ["- {}".format(f) for f in findings]
    )
    return ["", "## The depth-0 frame (external.toml resolution)", ""] + body


def need_source_anchors(root, sn_needs):
    """Each document the needs' `source` cells name -> the anchors it exposes,
    or None when it is not a file inside the repository (SR-190).

    The FILE READ half of the source-pointer rule, kept here because
    `frame_rules` reads no file. Each document is read once, through the kit's
    one markdown anchor reader (`check_docs.parse_doc`, behind
    `check_trajectory.doc_anchors`), so a pointer and a markdown link agree on
    what an anchor is. A file that is not markdown exposes no anchors. A target
    outside the repository does not resolve, because the pointer is
    repository-relative by definition."""
    base = Path(root).resolve()
    out = {}
    for doc in source_documents(sn_needs):
        path = (base / doc).resolve()
        found = path.is_file() and path.is_relative_to(base)
        out[doc] = (
            (check_trajectory.doc_anchors(path) or frozenset()) if found else None
        )
    return out


def contract_symbol_surface(root):
    """The declared source surface as three name sets — `(names, tails,
    modules)` — or `(None, None, None)` when there is no surface to read.

    `names` is `gen_arch_map.implements_report`'s `known_names`: every dotted
    def/class qualname plus every module-scope binding under `[paths] src`.
    `tails` is the last dotted segment of each, which is what lets a contract
    write `check_doc_refs.doc_files` (a MODULE-qualified name, and a module is
    not a def, so the full token is never in `names`) and still resolve.
    `modules` is every module and package name in that surface — the set that
    decides whether a dotted token is even OURS to judge.

    `(None, None, None)` — not three empty sets — for the three vacuous cases,
    and the distinction is the whole safety of the rule: an EMPTY surface would
    report every named symbol in the registry as dead, which is the loudest
    possible false positive. The cases are a repo declaring `[arch-map] mode =
    files` (no parser for its language), a missing source directory, and a
    fixture that copied this script without its siblings."""
    if gen_arch_map is None or root is None:
        return None, None, None
    try:
        src, mode = check_trajectory._arch_scan_profile(root)
    except (
        OSError,
        ValueError,
    ):  # pragma: no cover - a broken profile is not this rule's finding
        return None, None, None
    if mode == "files":
        return None, None, None
    src_dir = root / src.strip().replace("\\", "/").rstrip("/")
    if not src_dir.exists():
        return None, None, None
    _sites, known = gen_arch_map.implements_report([src_dir])
    if not known:
        return None, None, None
    modules = {p.stem for p in src_dir.rglob("*.py")}
    modules |= {p.parent.name for p in src_dir.rglob("__init__.py")}
    return known, {n.rsplit(".", 1)[-1] for n in known}, modules


def _symbol_resolves(token, names, tails, modules):
    """True when `token` names something the source surface really has, or is a
    token this rule declines to judge.

    A `*`-tailed token is a FAMILY and resolves on any prefix match — the live
    rot exhibit's own shape. A DOTTED token is judged only when its head names a
    module, a package or a real class in the surface: `csv.DictReader`,
    `sys.executable` and the registry's own `LLR.Module` notation are not this
    tree's symbols, and a rule that reported them would be inventing a finding
    about somebody else's code. Everything judged resolves on the whole token or
    on its last dotted segment — the same CONTAINMENT posture the `CodeSymbol`
    crosscheck takes, since a contract naming a real symbol by a shorter path
    than the registry spells it is not the defect this rule is for."""
    if token.endswith("*"):
        prefix = token[:-1].rstrip("_") + "_"
        return any(t.startswith(prefix) for t in tails)
    head, _dot, _rest = token.partition(".")
    if _dot and head not in modules and head not in names:
        return True
    tail = token.rsplit(".", 1)[-1]
    return token in names or tail in names or tail in tails or tail in modules


def contract_named_tokens(cell):
    """`(symbols, paths)` — the tokens one `Contract` cell CLAIMS resolve.

    PATHS ARE READ FIRST AND MASKED OUT, which is not an optimization: without
    it `docs/log.d/` yields the "attribute" `log.d` and every `<file>.md` in a
    contract becomes a symbol. What survives the mask is scanned for the three
    symbol shapes, with a filename-tailed dotted token dropped (`trace.py` is a
    file, not an attribute) and a call's `()` stripped. Both lists are
    order-preserving and de-duplicated, so one dead name written twice in one
    cell is one finding."""
    paths = {}
    for m in _IF_PATH_RE.finditer(cell):
        # Prose punctuation abutting a path is not part of it: a sentence-final
        # `docs/kit-version.` names `docs/kit-version`.
        paths[m.group(1).rstrip(".,;:)")] = None
    masked = _IF_PATH_RE.sub(" ", cell)
    symbols = {}
    for m in _IF_CALL_RE.finditer(masked):
        symbols[m.group(1)] = None
    for m in _IF_DOTTED_RE.finditer(masked):
        token = m.group(1)
        if token.rsplit(".", 1)[-1].lower() not in _IF_FILE_TAILS:
            symbols[token] = None
    for m in _IF_CONST_RE.finditer(masked):
        symbols[m.group(1)] = None
    return list(symbols), list(paths)


def _if_named_symbol_advisories(iid, cell, root, surface, absences):
    """The fifth rule for ONE row: every symbol and path the cell names must
    resolve. A separate function from `if_contract_advisories`' loop body so the
    four form rules and the one content rule stay separately readable (and the
    complexity ratchet stays where it is).

    A path this repo has DECLARED it does not carry is resolved, not dangling —
    the same reading `if_endpoint_class_advisories` and `check_doc_refs` already
    give `docs/declared-absences`, whose whole point is that the fact is stated
    once."""
    names, tails, modules = surface
    out = []
    symbols, paths = contract_named_tokens(cell)
    if names is not None:
        for token in symbols:
            if not _symbol_resolves(token, names, tails, modules):
                out.append(
                    f"IF {iid} Data names {token} — no such symbol exists "
                    "in the declared source surface. A contract that names code "
                    "that is gone reads as authority and is not: re-point it at "
                    "what the module has now, or drop the name."
                )
    for token in paths:
        if token in absences or token + "/" in absences:
            continue
        # The first segment must be a real directory before the token is judged
        # at all — see `_IF_PATH_RE`.
        if not _resolves_in_tree(root, token.split("/", 1)[0]):
            continue
        if not _resolves_in_tree(root, token):
            out.append(
                f"IF {iid} Data names path {token} — nothing at that path "
                "exists. Re-point it, or drop it."
            )
    return out


def if_data_advisories(ifs, root=None):
    """The four ruled negative rules (WI-443) plus the named-symbol/named-path
    tripwire (OI-61 ruled (d)), on the IF `Data` cell since OI-67 — the short
    alphabet or schema pointer that replaced the prose `Contract`. All
    warn-first. See the `_IF_*` constants above for why form is what the first
    four can honestly read, and why the fifth needs the AST surface.

    `root=None` keeps the four form rules runnable with no tree — the shape a
    row-level unit test wants — and makes the content rule vacuous there."""
    out = []
    surface = contract_symbol_surface(root)
    absences = _declared_absences(root) if root is not None else frozenset()
    for r in ifs:
        iid = r.get("IF-ID") or "(unnamed row)"
        cell = (r.get("Data") or "").strip()
        if not cell:
            continue
        out += _if_named_symbol_advisories(iid, cell, root, surface, absences)
        for token in dict.fromkeys(_IF_WI_RE.findall(cell)):
            out.append(
                f"IF {iid} Data names {token} — a work-item id belongs in the "
                "log, not in a live seam cell: it ages, and a cancelled id "
                "still reads as authority. Drop it; the log holds the account."
            )
        for token in dict.fromkeys(_IF_DECISION_RE.findall(cell)):
            out.append(
                f"IF {iid} Data cites decision {token} — the cell states what "
                "crosses, not which ruling shaped it. Drop the citation; the "
                "log's Decisions is its home."
            )
        connective = _IF_CONNECTIVE_RE.search(cell)
        if connective:
            out.append(
                f"IF {iid} Data argues ({connective.group(0)!r}) — that "
                "sentence is a rationale; move the ARGUMENT to the Rationale "
                "column, and any citation inside it to the log (process.md §8)."
            )
        if len(cell) > IF_DATA_MAX:
            out.append(
                f"IF {iid} Data is {len(cell)} characters (ceiling "
                f"{IF_DATA_MAX}) — the alphabet or the schema pointer, typed; "
                "the definition belongs in the owner's `Contract IF-###:` body."
            )
    return out


# The IF tier's three REASON cells. `Notes` records why a crossing is shaped as
# it is; `SignalNote` the discrete/variable call; `Rationale` the argument.
IF_REASON_CELLS = ("Notes", "Rationale")

# The reviewed exception list for the citation-frame advisory, in the same
# one-entry-per-line ` — <reason>` idiom `docs/need-form-allow` established. The
# key is `<ROW-ID> <Cell> <token>` — THREE fields, and the third is what makes
# the entry mean anything (see `load_provenance_allow`).
PROVENANCE_ALLOW = "docs/provenance-allow"
PROVENANCE_ALLOW_SEP = " — "

# An `OI-###` id, anchored: the allow-file field is a WHOLE token in first
# position, never a substring somewhere in the prose (see `parse_provenance_allow`).
OI_ID_RE = re.compile(r"^OI-\d+$")
OPEN_ITEMS_REL = "docs/requirements/open-items.toml"


def load_provenance_allow(root):
    """The reviewed exception keys from `docs/provenance-allow`, normalized.

    Absent file: empty set. A line with no separator declares nothing — the
    declared-absences fail-soft rule in the LOUD direction, so the worst a
    malformed entry can do is leave a finding reported.

    TOKEN-SCOPED, NOT CELL-SCOPED, and the change was forced by measurement. The
    key used to be a row id or an id + cell, which suppressed the WHOLE cell —
    while every entry in the file justifies exactly one token. On 2026-08-18 the
    list held 15 `SR-### Rationale` entries all reasoned "unsigned
    derived-requirement label"; re-running detection with the list ignored
    exposed 67 tokens over 22 rows, including `RE-VOICED 2026-08-17` and
    `Minted at the owner's 2026-08-15`. Those are the banned shape itself, riding
    a carve-out written for a parenthetical label — and `docs/test/report.md` was
    meanwhile asserting that no living spine cell carried a frame. A key is now
    `<ROW-ID> <Cell> <token>`, matched against the token the detector reports,
    whitespace-collapsed and case-folded; a two-field key declares NOTHING and is
    dropped, which is what makes the migration self-enforcing rather than
    optional.

    THE LIST IS NOT A SECOND HOME FOR PROVENANCE. It exists for one measured
    class: a cell whose citation frame is the only record of an UNRESOLVED
    tension — an open question the sitting owes a ruling on, a flagged
    contradiction between two rows, a provisional label nothing mechanical
    carries. Stripping those would delete the repo's only note that the question
    is open, which is a worse outcome than the frame. Each entry says so, and
    NAMES the `OI-###` row that carries the question (`parse_provenance_allow`);
    when the ruling's execution lands, the marker and the entry go together."""
    return {
        allow_key(e["rid"], e["cell"], e["token"]) for e in parse_provenance_allow(root)
    }


def parse_provenance_allow(root):
    """The ENTRIES of `docs/provenance-allow`, one dict per declaring line:
    `{line, rid, cell, token, oi, reason}` (`oi` is None when the entry names no
    row). `load_provenance_allow` is the key-set view of the same parse — ONE
    parser, so the grammar the finding reports and the grammar the suppression
    honours can never drift apart.

    THE `OI-###` IS A REQUIRED FIELD (OI-41 ARM 1, ruled 2026-08-20). It is the
    FIRST token of the reason — a position, not a mention — so an id merely
    discussed later in the sentence is not mistaken for the entry's row. Before
    this, 19 entries PROMISED an open-item row in prose ("owes an open-item row
    at the sitting") and not one of them had one: the promise and the queue were
    two unconnected artifacts, which is a mechanizable gap rather than a cultural
    one. As a field it has no false positives — there is no third state between
    "the detector fires" and "an entry silences it" — which is why it ships hard
    at birth where the sibling arms ship warn-first (`provenance_allow_findings`).

    Fail-soft in the LOUD direction, unchanged: a line with no separator, or with
    fewer than three key fields, declares NOTHING and is dropped here, so the
    worst a malformed entry can do is leave a finding reported — **and, since
    2026-08-20, is REPORTED as dropped** (`read_provenance_allow`), because the
    other half of "declares nothing" is that it also COUNTS as nothing, and the
    arms that reason about how many exceptions stand were reading that silence as
    an empty surface."""
    return read_provenance_allow(root)[0]


def read_provenance_allow(root):
    """`(entries, unparsed)` — the whole parse, both halves.

    `unparsed` is `[(lineno, line)]` for every DECLARING line the grammar
    dropped: not blank, not a comment, and not parseable as an entry. It exists
    because "fail-soft in the loud direction" was only half true (2026-08-20, the
    batch review's MAJOR-6). Dropping a malformed entry does un-silence the
    finding it was written to silence, which is the loud direction — but it also
    removes the entry from every COUNT, and OI-41's vacuity arm is a count: it
    contradicts an empty queue with the exceptions still standing. So a
    mistyped separator (`--` for ` — `) made an exception vanish from the count
    while still reading, to a human, exactly like a live entry, and the arm then
    printed an all-clear. One character, and the surface reports empty.

    The counting rule is deliberately the CHEAP one — non-blank, non-comment — so
    it cannot itself be evaded by a subtler malformation: anything a human would
    read as an entry counts as one, and the parser must agree or say so."""
    path = Path(root) / PROVENANCE_ALLOW
    if not path.is_file():
        return [], []
    out, unparsed = [], []
    text = path.read_text(encoding="utf-8-sig", errors="replace")
    for lineno, raw in enumerate(text.split("\n"), start=1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if PROVENANCE_ALLOW_SEP not in line:
            unparsed.append((lineno, line))
            continue
        head, reason = line.split(PROVENANCE_ALLOW_SEP, 1)
        key = head.split()
        if len(key) < 3:
            unparsed.append((lineno, line))
            continue
        first = reason.split()[0].strip(":;,.") if reason.split() else ""
        out.append(
            {
                "line": lineno,
                "rid": key[0],
                "cell": key[1],
                "token": " ".join(key[2:]),
                "oi": first if OI_ID_RE.match(first) else None,
                "reason": reason.strip(),
            }
        )
    return out, unparsed


def provenance_allow_parse_findings(root):
    """PARSE HONESTY: a declaring line the grammar could not read is an INTEGRITY
    finding naming it, not a silent drop.

    Integrity-class for the same reason ARM 1 is: it is a field-shaped fact about
    a file this repo maintains, with no false positives — the line either parses
    or it does not — and the always-on floor is the only pipe that runs at every
    gate. Reported at the FIRST unparsed line rather than all of them, with the
    count, because the fix is the same edit for every one and a wall of identical
    findings is how a real one gets skipped over."""
    _entries, unparsed = read_provenance_allow(root)
    if not unparsed:
        return []
    lineno, line = unparsed[0]
    return [
        "{}:{}: this line DECLARES an exception and the grammar cannot read it "
        "({} such line(s)) — `{}`. An entry is `<ROW-ID> <Cell> <token>` then "
        "`{}OI-###: <reason>` (the separator is an em dash with a space each "
        "side). A dropped line still reads like a live exception to a human, "
        "while counting as none — which is how the deferral count reports an "
        "empty surface that is not empty".format(
            PROVENANCE_ALLOW,
            lineno,
            len(unparsed),
            line[:80],
            PROVENANCE_ALLOW_SEP,
        )
    ]


def open_item_states(root):
    """`{OI-###: status}` from the open-items registry, `-000` example rows
    dropped, or None when the repo carries no registry at all.

    NONE IS NOT `{}`, and the distinction is the whole reason this returns two
    kinds of empty: an absent registry means the resolution rules below cannot
    run (they would demand ids from a file the repo does not have), while an
    empty one means every named id is genuinely unresolved. The D-5 rule."""
    path = Path(root) / OPEN_ITEMS_REL
    if spine_carrier.resolve(path) is None:
        return None
    return {
        (r.get("OI-ID") or "").strip(): (r.get("Status") or "").strip().lower()
        for r in spine_carrier.load(path, "OI-ID")
        if (r.get("OI-ID") or "").strip().startswith("OI-")
        and not (r.get("OI-ID") or "").strip().endswith("-000")
    }


def provenance_allow_findings(entries, states):
    """ARM 1 of OI-41, HARD AT BIRTH: every allow entry names an `OI-###` that
    RESOLVES to a row of the open-items registry.

    `docs/provenance-allow` is not merely where deferrals are densest — it is the
    DECLARED-EXCEPTION SURFACE: every knowingly-unsatisfied mechanized rule has
    an entry here or the detector fires. So for the whole class "a rule this repo
    mechanizes is knowingly not satisfied", the question *did the deferral reach
    open-items?* collapses into *does every entry name a row?* — a field check,
    integrity-class like a duplicate id, reported on the always-on
    `--strict-integrity` floor.

    TWO ARMS, BOTH FIELDS: the id is present, and the id exists. The row's
    STATE is deliberately not an arm here — a row that is ruled but whose
    execution has not landed is a legal, transient state (the entry retires with
    the execution, and `tests/test_trace.py` already fails a dead entry), and the
    count contradiction it can hide — *the queue reports empty while entries
    still stand* — is ARM 3's, which names the same entries once rather than
    twice (`gen_open_items.deferral_findings`).

    VACUOUS when the repo carries no open-items registry (`states is None`):
    demanding a row from a file that does not exist is not a finding, it is a
    migration, and the always-on layer's own S-3 says so in words
    (`check_docs.check_status_surface`)."""
    if states is None:
        return []
    out = []
    for e in entries:
        where = "{}:{} ({} {})".format(PROVENANCE_ALLOW, e["line"], e["rid"], e["cell"])
        if not e["oi"]:
            out.append(
                "{}: the entry names no OI-### — an exception is a DEFERRED "
                "decision, so the reason opens with the open-items row that "
                "carries it (`… {} OI-###: <reason>`)".format(
                    where, PROVENANCE_ALLOW_SEP.strip()
                )
            )
        elif e["oi"] not in states:
            out.append(
                "{}: names {}, which has no row in {} — the field must resolve, "
                "or it records a queue entry nobody made".format(
                    where, e["oi"], OPEN_ITEMS_REL
                )
            )
    return out


def if_note_advisories(ifs, allow=()):
    """Warn-only: an IF `Notes`/`SignalNote` cell carrying a citation frame.

    The same ruling the spine tiers get (`trace_text.provenance_advisories`),
    applied where the IF tier keeps its reasoning. The Contract arm above was
    scoped to `Contract` because that is the cell a CONSUMER reads — but the
    measured population went the other way: 216 provenance tokens over 76 IF
    rows, 118 of them in `Notes`, on a cell nothing was watching. That is the
    same "the largest pocket is the layer the rule cannot see" shape the SR-only
    scoping error already made once, one tier over.

    A SEPARATE FUNCTION rather than another cell in the loop above: the Contract
    arm's other two rules (the connective and the 500-character ceiling) say
    "this cell is not the place to argue", and a `Notes` cell arguing is that
    cell working correctly. Folding the cells together would apply a rule to a
    cell whose whole job it contradicts.

    THE SWEEP IS `trace_text.cite_advisories`, the one engine the spine and
    off-spine tiers share (WI-821): this was a near-copy of its loop, differing
    only in its message's wording, which it passes as a value
    (`trace_text.IF_CITE_MESSAGE`), so its output is the copy's to the byte. Every IF
    reason cell is in its `REASON_CELLS`, so the reason-cell reading is the
    same, and the exception list is read token-scoped by the same `is_allowed`."""
    return cite_advisories(
        [(ifs, ("IF", "IF-ID", IF_REASON_CELLS))], allow, IF_CITE_MESSAGE
    )


# `EXTERNAL_ENDPOINT_PREFIX` (the declared "deliberately outside this tree" marker
# and the reasoning for a value-prefix over a column) MOVED TO trace_text.py at
# re-tier v2 S5 (WI-464), unchanged and imported back above: `_module_shaped` has
# to skip a marked endpoint too, and the endpoint value GRAMMAR is a text rule.


def if_endpoint_class_advisories(ifs, module_ids, root):
    """Classify every IF endpoint that is NOT an arch-map module, warn-first.

    THIS EXISTS BECAUSE THOSE ROWS WERE POLICED BY NOTHING, measured at
    `81a142c2`: 45 of 113 IF rows have at least one endpoint carrying no
    component tag, which makes `check_trajectory.cross_component_findings`
    VACUOUS for them — and the containment rule that was assumed to cover them
    cannot, because the two rules range over disjoint object classes. Containment
    tests that every arch-map MODULE is in some CMP; the untagged endpoints are
    data files, directories and external actors, which are never arch-map
    modules. So a green from either rule said nothing at all about these rows.

    THE RULE, since the 2026-08-15 rework (plan step 2): an endpoint — in
    `Owner`, `Requestors` **or** `Consumers` (`ThisProject`/`Counterpart` until WI-455,
    `Provider` until OI-67) — that resolves to no module, no file and
    no directory AND carries no `external:` marker is a NAMED finding. A
    file/directory endpoint and a marked external one are both legitimate and
    stay counted-not-named; the summary still reports every class, because the
    vacuity it records is real whatever the endpoint turns out to be.

    Warn-first, like every rule in this pipe: it never joins a failure set at any
    gate. Promotion is a later, separate decision, and the reason to hold is that
    the marker is a NEW convention — an adopter mid-migration would be red for a
    vocabulary their registry predates."""
    norm_modules = {_norm_module(m) for m in module_ids}
    norm_modules.discard("")
    absences = _declared_absences(root)
    files, external, unknown, rows_hit = [], [], [], set()
    for r in ifs:
        iid = r.get("IF-ID") or "(unnamed row)"
        for col in ("Owner", "Requestors", "Consumers"):
            # A `;`-joined cell is SEVERAL endpoints, and reading it as one is
            # how a real seam gets reported as a dangling path (IF-097 names
            # three modules). Split on `;` only — an endpoint may legitimately
            # contain a space (`downstream adopter`) or a comma.
            cell = (r.get(col) or "").strip()
            for endpoint in [e.strip() for e in cell.split(";") if e.strip()]:
                if endpoint.startswith(EXTERNAL_ENDPOINT_PREFIX):
                    rows_hit.add(iid)
                    named = endpoint[len(EXTERNAL_ENDPOINT_PREFIX) :].strip()
                    if named:
                        external.append(named)
                    else:
                        # A bare marker names nobody, which is the one way this
                        # convention can be worse than the guess it replaced.
                        unknown.append((iid, col, endpoint))
                    continue
                if _norm_module(endpoint) in norm_modules:
                    continue
                rows_hit.add(iid)
                if _resolves_in_tree(root, endpoint) or endpoint in absences:
                    files.append(endpoint)
                else:
                    unknown.append((iid, col, endpoint))
    if not rows_hit:
        return []
    out = [
        "IF endpoint coverage: {} of {} row(s) carry an endpoint that is not an "
        "arch-map module, so the cross-component rules are VACUOUS for them — "
        "{} resolve to a file or directory in the tree, {} are marked "
        "`external:`, {} resolve to nothing".format(
            len(rows_hit), len(ifs), len(files), len(external), len(unknown)
        )
    ]
    for iid, col, endpoint in unknown:
        out.append(
            "IF {} {}={!r} resolves to no module, file or directory — name a "
            "real endpoint, or mark it `{}<actor>` if it is deliberately "
            "outside this tree".format(iid, col, endpoint, EXTERNAL_ENDPOINT_PREFIX)
        )
    return out


def if_verified_by_advisories(ifs, tc_ids, llr_ids):
    """`VerifiedBy` — the OPTIONAL seam-tier verification pointer, warn-first
    (OI-61's sub-question, sanctioned 2026-08-23).

    THE POSITION IT MAKES SAYABLE did not exist anywhere in the vocabulary
    before. `Verification` is `Test | Demonstration | Manual | Analysis |
    Inspection | Attest | Critique`, its only exemption is LLR-exemption on an
    SR, process.md states "Every SR needs >=1 TC row regardless of method", and
    an IF row carries no `Verification` cell at all — so a low-level seam whose
    honest answer is *verified by the parent functionality's tests* could only
    be silent about it, or invent a per-seam test nobody wanted.

    THE CELL IS OPTIONAL AND ITS EMPTINESS MEANS SOMETHING: empty is "this seam
    is verified in its own right", which is the ordinary case and needs no
    ceremony. A FILLED cell names the parent whose tests cover it — a `TC-###`
    (the test itself) or an `LLR-###` (the parent design row that carries one) —
    and the only thing checked is that the pointer RESOLVES. That is the whole
    mechanism, deliberately: a pointer that must resolve is stronger than the
    silence it replaces, and nothing here asks whether the named test actually
    exercises the seam, which no grammar can read.

    Warn-first, matching every other content rule on this tier."""
    out = []
    for r in ifs:
        iid = r.get("IF-ID") or "(unnamed row)"
        cell = (r.get("VerifiedBy") or "").strip()
        if not cell:
            continue  # "verified in its own right" — the meaning of empty
        for pid in refs(cell):
            if ID_PATTERNS["TC"].match(pid):
                known, tier = tc_ids, "test-cases"
            elif ID_PATTERNS["LLR"].match(pid):
                known, tier = llr_ids, "low-level-requirements"
            else:
                out.append(
                    "IF {} VerifiedBy={!r} is not a TC-### or LLR-### id — the "
                    "pointer names the test that covers the seam, or the parent "
                    "design row that carries one".format(iid, pid)
                )
                continue
            if pid not in known:
                out.append(f"IF {iid} VerifiedBy references unknown {pid} ({tier})")
    return out


# The carriage depth this repo warns past. PROVISIONAL, and stated as a number
# rather than left implicit because Q3 created the obligation ("the carriage
# graph must be acyclic and its depth bounded") without fixing the bound. Two is
# the depth the ruling's own worked shape needs — *"6 IFs could have a
# destination of a larger IF"* is one carrier over its constituents — so a third
# level is a bundle inside a bundle, which may be right and should be looked at.
IF_CARRIAGE_MAX_DEPTH = 2


def if_carriage_advisories(ifs):
    """`CarriedBy` — interface composition, warn-first (Q3, ruled 2026-08-15a;
    plan step 7).

    *"An IF could feasibly have a destination of another IF, so 6 IFs could have
    a destination of a larger IF to carry them in a single definable signal."*
    A constituent names its carrier; several constituents riding one bundle name
    the same carrier id. Granularity stops being a forced choice — declare the
    bundle AND its parts, related by this link, and decompose only as far as is
    useful.

    THE OBLIGATION THE RULING CREATED is checked here, because a link that may
    point at another row of its own tier is representable as `IF-A carried by
    IF-B carried by IF-A`: the carriage graph must RESOLVE, must be ACYCLIC, and
    its depth is bounded. A cycle is reported once per row on it rather than once
    per traversal, so a two-row cycle reads as two findings and not as an
    infinite one.

    A row carrying itself is called out separately: it is a cycle, but the useful
    sentence is not "there is a cycle", it is "this cell should be empty"."""
    out = []
    ids = {r.get("IF-ID") for r in ifs if r.get("IF-ID")}
    carrier = {}
    for r in ifs:
        iid = r.get("IF-ID")
        cell = (r.get("CarriedBy") or "").strip()
        if not iid or not cell:
            continue
        named = refs(cell)
        if len(named) != 1:
            out.append(
                "IF {} CarriedBy={!r} names {} carriers — one constituent rides "
                "one bundle (Q3, 2026-08-15)".format(iid, cell, len(named))
            )
            continue
        cid = named[0]
        if not ID_PATTERNS["IF"].match(cid):
            out.append(f"IF {iid} CarriedBy={cid!r} is not an IF-### id")
            continue
        if cid == iid:
            out.append(f"IF {iid} CarriedBy names itself — leave the cell empty")
            continue
        if cid not in ids:
            out.append(f"IF {iid} CarriedBy references unknown {cid}")
            continue
        carrier[iid] = cid
    for start in sorted(carrier):
        seen, node, depth = {start}, carrier[start], 1
        while node in carrier:
            if node in seen:
                out.append(
                    "IF {} sits on a CarriedBy CYCLE — a bundle cannot be "
                    "carried by something it carries".format(start)
                )
                break
            seen.add(node)
            node, depth = carrier[node], depth + 1
        else:
            if depth > IF_CARRIAGE_MAX_DEPTH:
                out.append(
                    "IF {} is {} carriers deep (bound {}) — a bundle inside a "
                    "bundle may be right, but say why in Rationale (the bound "
                    "is provisional, Q3 2026-08-15)".format(
                        start, depth, IF_CARRIAGE_MAX_DEPTH
                    )
                )
    return out


def _declared_absences(root):
    """The paths `docs/declared-absences` says this repo deliberately does NOT
    carry — the THIRD reader of a file whose whole point is that the fact is
    stated once (`test_dogfood_sync` and `check_doc_refs` are the other two).

    An endpoint naming one of them is neither rot nor external: the layer is
    opt-in and switched off, and the row is honest about what the module would
    read if it were on. This repo's worked case is
    `docs/requirements/assets.csv` — the off-spine asset registry, absent
    because a meta-repo ships no binary assets, with the reason already written
    down one directory up. Reporting it as a dangling endpoint would have been
    the checker demanding the repo delete a true statement.

    RE-POINTED 2026-08-20 (the batch review's MINOR-19). The example here was
    `docs/requirements/performance-budgets.csv` for as long as this repo's perf
    layer was off — and WI-481 seeded that registry and deleted its
    declared-absence line in the same act, leaving two readers teaching a worked
    case that is now present. A worked example naming a live file teaches the
    opposite of the rule.

    Fail-soft in the quiet direction (no file -> no declarations), because that
    is the state of every repo that has never needed one."""
    try:
        text = (root / "docs" / "declared-absences").read_text(encoding="utf-8")
    except (OSError, ValueError, UnicodeDecodeError):
        return frozenset()
    out = set()
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        # `<path> — <reason>`, the em-dash separator the file's own header
        # declares; a line with no separator is a path with no reason and is
        # deliberately NOT honoured (the file requires the reason).
        path, sep, _reason = line.partition("—")
        if sep:
            out.add(path.strip())
    return frozenset(out)


def _resolves_in_tree(root, endpoint):
    """True when an IF endpoint names something that exists under `root`.

    Tries the endpoint verbatim and under the kit's own script home, then with
    each source suffix appended — `scripts/trace` is how the registry spells
    `project-trajectory/scripts/trace.py`, and a classifier that could not see
    that would report every module endpoint as missing."""
    if not endpoint or root is None:
        return False
    bases = (endpoint, "project-trajectory/" + endpoint)
    for base in bases:
        for suffix in ("", ".py", ".md", ".toml", ".csv", ".ini", ".html", ".yml"):
            try:
                if (root / (base + suffix)).exists():
                    return True
            except (OSError, ValueError):  # pragma: no cover - exotic path text
                return False
    return False


def phase_approved_findings(real):
    """The approved-phase NUMERIC-ONLY rule (process.md §4 "Phased delivery"; owner
    ruling 2026-08-01, WI-402): once the project phases ANY spine row (digit-parse
    arming — a legacy `v2` cell arms it too), every APPROVED (non-`Drafted`) SR/LLR/TC
    must carry a `Phase` that is a BARE INTEGER — digits only, full cell. Numeric-
    only because two joins match the cell LITERALLY, not by parse: the `--phase` /
    `--approve` scope filters (`in_phase` / `_scope_srs`) and check_trajectory's
    phase-drop join of docs/gate's `per-phase=` labels against `[phase]-[g<N>]` WI
    anchors — a prefixed cell like `P1`/`v2` goes silently vacuous there, a
    disarmed warn no one is told about, which is worse than a crash. The digit-
    extract parsers (phase_num + its F5 copies) stay lenient on purpose —
    grandfathering, so historical labels still parse in the filters and the
    derived max while this rule migrates the live cells. The rule is **vacuous
    until >=1 artifact is phased** — the arming idiom the component checks use —
    so a fully-blank downstream registry stays green (a `Drafted` row may always
    leave `Phase` blank). SN is covered transitively: at DevStg-Reqs+ every approved SN
    has >=1 SR (the orphan rule) and SRs are phased; pre-DevStg-Reqs it is vacuously
    exempt. Part of --strict-schema; extends the schema tier rather than forking
    it.

    Implements: SR-157, LLR-003
    """
    all_rows = [r for label in real for r in real[label]]
    if not any(phase_num(r) is not None for r in all_rows):
        return []  # unarmed: nothing is phased yet
    out = []
    for label in ("SR", "LLR", "TC"):
        key = id_key(label)
        for r in real.get(label, []):
            cell = (r.get("Phase") or "").strip()
            if is_drafted(r) or re.fullmatch(r"[0-9]+", cell):
                continue
            shown = f"={cell!r}" if cell else " (blank)"
            out.append(
                f"{label} {r[key]} is approved but its Phase{shown} is not a bare "
                "integer — an approved row's phase is digits only, full cell; a "
                "prefixed label silently misses the literal --phase/--approve and "
                "phase-drop joins (process.md §4 'Phased delivery')"
            )
    return out


# --- Generated traceability views --------------------------------------------
# The registries are the reviewed source of truth; everything below is a
# *rendering* of the same join, regenerated every run (process.md §3
# "Reviewability"). Three views because none is both line-reviewable and
# big-graph-scalable: the text outline reviews line-by-line and scales to any
# size; the Mermaid DAG is small and diff-friendly; the HTML tree browses the
# full graph at any size. All are stdlib string-building — no dependency.


def _cell(row, col):
    return (row.get(col) or "").strip()


def _node_class(rid, status, orphan_ids):
    """A node's view class: orphan (a trace finding) outranks drafted (a status).
    The returned token is a CSS/mermaid CLASS NAME, not a Status value — it stays
    `draft` across D-9's rename because the stylesheet and the mermaid classDef
    key off it, while the cell it reads is now `Drafted`."""
    if rid in orphan_ids:
        return "orphan"
    if status.lower() == "drafted":
        return "draft"
    return ""


def _node(rid, status, title, orphan_ids, children=None):
    return {
        "id": rid,
        "status": status,
        "title": title,
        "cls": _node_class(rid, status, orphan_ids),
        "children": children or [],
    }


def _group(label, children):
    """A synthetic, unflagged parent for rows with no valid parent, so both tree
    views surface the same orphan tails the Orphans section lists."""
    return {"id": label, "status": "", "title": "", "cls": "", "children": children}


def _bucket_by_ref(rows, ref_col):
    """Index rows by each id named in their `ref_col` cell — parent-id -> [rows
    that reference it], child rows kept in input order, each cell parsed once.
    Replaces the per-parent refs() rescans that made the report joins quadratic
    (WI-081, M8: O(SR×LLR + SR×TC + LLR×TC) -> O(N))."""
    index = {}
    for row in rows:
        for parent in refs(row.get(ref_col)):
            index.setdefault(parent, []).append(row)
    return index


def chain_buckets(llrs, tcs):
    """`(llrs_by_sr, tcs_by_ref)` — the two indexes `spine_chain` reads.

    Built ONCE by a caller that walks many SRs, because bucketing inside the
    per-SR call is exactly the quadratic join `_bucket_by_ref` exists to
    replace."""
    return _bucket_by_ref(llrs, "SR-Refs"), _bucket_by_ref(tcs, "Verifies")


def spine_chain(sr_id, srs, llrs_by_sr, tcs_by_ref):
    """One SR's WHOLE CHAIN as `[(kind, id, row)]` — the SR itself, its child
    LLRs in id order, then every TC that verifies the SR or one of those LLRs,
    deduped and in id order.

    THE ONE ANSWER TO "WHAT IS THIS REQUIREMENT'S CHAIN", public since WI-572
    rather than a closure inside `reattest_model`. Two readers need it now and
    they must not disagree: the re-attest model asks it of the live registries
    and of the snapshot's, and `adjudicate_brief.first_approval_values` asks it
    to render the chain a first-approval adjudicator reads — the whole chain,
    not the changed rows, because holding the chain is the owner's stated reason
    the approval act is the adjudicator's and not the authoring lane's."""
    out = []
    sr_row = next((r for r in srs if r.get("SR-ID") == sr_id), None)
    if sr_row is not None:
        out.append(("SR", sr_id, sr_row))
    child_llrs = sorted(llrs_by_sr.get(sr_id, []), key=lambda r: r.get("LLR-ID", ""))
    for lr in child_llrs:
        out.append(("LLR", lr["LLR-ID"], lr))
    seen_tcs = {}
    for key in [sr_id] + [lr["LLR-ID"] for lr in child_llrs]:
        for t in tcs_by_ref.get(key, []):
            seen_tcs.setdefault(t.get("TC-ID"), t)
    for tid in sorted(k for k in seen_tcs if k):
        out.append(("TC", tid, seen_tcs[tid]))
    return out


def assumption_evidence_rows(tcs):
    """`(requirement evidence, assumption evidence)`: the test cases naming
    something in `Verifies`, and those naming something in `Assumption-Refs`,
    each in input order. A case citing both is counted once in each; one citing
    neither is in neither.

    THE ONE PARTITION every evidence count reads (SR-197). Evidence that an
    assumption holds is not evidence that the system does what its requirements
    say, so a count merging the two would answer neither question; and two views
    splitting the same case differently would disagree about what it proves.
    The readers that ask whether a requirement is verified (the orphan rules,
    the matrix, the triangle rule) read `Verifies` alone and never come here.

    Implements: SR-197, LLR-231
    """
    requirement = [t for t in tcs if refs(t.get("Verifies"))]
    assumption = [t for t in tcs if refs(t.get("Assumption-Refs"))]
    return requirement, assumption


def evidence_metric_rows(tcs):
    """The report's two evidence counts, requirement and assumption evidence,
    as metric-table lines; `[]` when no case evidences an assumption, so a
    project that never adopts the tier renders the report it always did."""
    requirement, assumption = assumption_evidence_rows(tcs)
    if not assumption:
        return []
    return [
        f"| Test cases — requirement evidence | {len(requirement)} |",
        f"| Test cases — assumption evidence | {len(assumption)} |",
    ]


def build_forest(sn_ids, srs, llrs, tcs, orphan_ids, sn_draft=frozenset()):
    """The SN -> SR -> LLR -> TC chain as nested nodes, plus synthetic groups for
    rows with no valid parent. Shared by the text outline and the HTML tree.
    `sn_draft` (section-as-state, §4a) labels those SNs `Drafted` so the views
    flag them like a `Status=Drafted` SR/LLR/TC row.

    A case evidencing only assumptions has no requirement to hang under, and it
    is not verifying nothing: it gets a group of its own (SR-197).

    Implements: SR-197, LLR-231"""
    llrs_by_sr = _bucket_by_ref(llrs, "SR-Refs")
    tcs_by_ref = _bucket_by_ref(tcs, "Verifies")
    srs_by_sn = _bucket_by_ref(srs, "SN-Refs")
    tc_verifies = {t["TC-ID"]: set(refs(t.get("Verifies"))) for t in tcs}

    def tc_node(t):
        return _node(t["TC-ID"], _cell(t, "Status"), _cell(t, "Method"), orphan_ids)

    def llr_node(lr):
        lid = lr["LLR-ID"]
        kids = [tc_node(t) for t in tcs_by_ref.get(lid, [])]
        return _node(lid, _cell(lr, "Status"), _cell(lr, "Title"), orphan_ids, kids)

    def sr_node(s):
        sid = s["SR-ID"]
        own = llrs_by_sr.get(sid, [])
        own_llrs = {lr["LLR-ID"] for lr in own}
        kids = [llr_node(lr) for lr in own]
        # TCs verifying the SR directly but none of its LLRs (so a TC that already
        # appears under an LLR of this SR is not also repeated under the SR).
        for t in tcs_by_ref.get(sid, []):
            if not tc_verifies[t["TC-ID"]] & own_llrs:
                kids.append(tc_node(t))
        return _node(sid, _cell(s, "Status"), _cell(s, "Title"), orphan_ids, kids)

    sr_ids = {s["SR-ID"] for s in srs}
    llr_ids = {lr["LLR-ID"] for lr in llrs}
    roots = []
    for sn in sorted(sn_ids):
        kids = [sr_node(s) for s in srs_by_sn.get(sn, [])]
        roots.append(
            _node(sn, "Drafted" if sn in sn_draft else "", "", orphan_ids, kids)
        )
    rootless_srs = [s for s in srs if not sn_ids & set(refs(s.get("SN-Refs")))]
    if rootless_srs:
        label = (
            "(SRs with no linked stakeholder need)"
            if sn_ids
            else "(system specifications)"
        )
        roots.append(_group(label, [sr_node(s) for s in rootless_srs]))
    rootless_llrs = [lr for lr in llrs if not sr_ids & set(refs(lr.get("SR-Refs")))]
    if rootless_llrs:
        roots.append(
            _group("(LLRs with no SR parent)", [llr_node(lr) for lr in rootless_llrs])
        )
    for label, rows in _unheld_tc_groups(tcs, sr_ids | llr_ids):
        roots.append(_group(label, [tc_node(t) for t in rows]))
    return roots


def _unheld_tc_groups(tcs, valid):
    """The test cases no valid requirement or design row holds, as the forest's
    synthetic groups `[(label, rows)]`, an empty group dropped. A case evidencing
    only assumptions is not verifying nothing, so it has a group of its own."""
    _requirement, assumption = assumption_evidence_rows(tcs)
    assumed_only = [t for t in assumption if not refs(t.get("Verifies"))]
    nothing = [
        t
        for t in tcs
        if not valid & set(refs(t.get("Verifies"))) and t not in assumed_only
    ]
    groups = (
        ("(assumption evidence)", assumed_only),
        ("(TCs verifying nothing valid)", nothing),
    )
    return [(label, rows) for label, rows in groups if rows]


def _flag_suffix(node):
    """The inline ` [Status] [orphan] — Title` tail shared by both tree views."""
    bits = []
    if node["status"]:
        bits.append("[{}]".format(node["status"]))
    if node["cls"] == "orphan":
        bits.append("[orphan]")
    suffix = (" " + " ".join(bits)) if bits else ""
    if node["title"]:
        suffix += " — " + node["title"]
    return suffix


def outline_lines(roots):
    """Indented Markdown list of the forest — pure text, so it reviews line-by-
    line and scales to any project size."""
    out = []

    def walk(node, depth):
        out.append("{}- {}{}".format("  " * depth, node["id"], _flag_suffix(node)))
        for child in node["children"]:
            walk(child, depth + 1)

    for r in roots:
        walk(r, 0)
    return out or ["_(no requirements yet)_"]


# --- approval hierarchy view (WI-146) --------------------------------------
# A batch-scoped SN->SR->LLR->TC tree that, unlike the whole-spine outline above,
# carries the *prose* an approver needs (SR Requirement/AC, LLR Detail, TC
# Method/Expected, and any rubric it cites) so a DevStg-Reqs/DevStg-Tests approval brief can
# *link* the generated view instead of hand-copying registry rows. Generated, so
# it never drifts from the CSVs — review the CSVs, not this render (process.md §3).

RUBRIC_RE = re.compile(r"[\w./-]*rubrics/[\w./-]+\.md")


def _rubrics_cited(*cells):
    """Sorted unique `docs/rubrics/*.md` paths named anywhere in the given SR
    prose cells — the approve view names the rubric a Critique/Attest SR is judged
    against (there is no dedicated Rubric column; the path lives in the prose)."""
    found = set()
    for c in cells:
        found.update(RUBRIC_RE.findall(c or ""))
    return sorted(found)


# The `--approve` scopes that are NOT a phase tag or an id list — a CLOSED set,
# routed to the re-attestation brief instead of the hierarchy view. Held as a set
# rather than as a literal comparison so a scope that is neither reserved nor
# resolvable cannot fall through to an empty brief, and so re-spelling one is a
# single edit here plus `check.py`'s `approval-fresh` step in the same commit.
#
# THE SCOPE NAME IS A CLI WORD, NOT A STATUS VALUE, and it deliberately did NOT
# move when `Modified` retired at step 7. The snapshot design proposed re-spelling
# it `drifted`; that renames a published command surface (`check.py`'s
# `approval-fresh`, the `gate-advance` skill, adopters' muscle memory) and buys
# nothing the migration needed — the COUPLING the plan named was `reattest_model`
# SELECTING on the literal, and that was cut at step 4.
_RESERVED_APPROVAL_SCOPES = frozenset({"modified"})


def _scope_srs(scope, srs):
    """Resolve a `--approve` scope to an ordered SR-row list. The scope is either a
    comma/space list of `SR-###` ids (used verbatim) or one-or-more phase tags
    (every SR whose `Phase` cell is one of them). Detection: if *any* token looks
    like an SR id the whole scope is treated as ids, else as phases.

    RAISES on a scope that resolves to NOTHING (migration plan §F2). Until now
    an unmatched scope fell through to an empty brief at exit 0 — a typo, a
    retired phase tag, or a reserved word this function does not know produced a
    document that reads "there is nothing to approve", which is the most
    expensive way for this tool to be wrong: an owner reads a short brief and
    blesses a batch they were never shown. An empty resolution is a REFUSAL, not
    an output."""
    tokens = refs(scope)
    as_ids = any(re.fullmatch(r"SR-\d+", t, re.IGNORECASE) for t in tokens)
    if as_ids:
        want = {t.upper() for t in tokens}
        matched = [s for s in srs if s.get("SR-ID", "").upper() in want]
    else:
        phases = {t.lower() for t in tokens}
        matched = [s for s in srs if _cell(s, "Phase").lower() in phases]
    if not matched:
        raise SystemExit(
            "trace: --approve {!r} matches no SR — refusing to emit an empty "
            "brief. A scope is an SR-id list, a DA/SUR-id list, a phase tag, or "
            "one of the reserved scopes ({}); an empty brief reads as 'nothing "
            "to approve' to the human about to sign it.".format(
                scope, ", ".join(sorted(_RESERVED_APPROVAL_SCOPES | {ASSUMPTION_SCOPE}))
            )
        )
    return matched


_SN_EMPHASIS = re.compile(r"\*\*|`")


def _sn_prose(sn_text, carrier):
    """Parse each SN row's prose (Need / Why it matters / Acceptance intent) from
    stakeholder-needs.md so the approve view renders the *top* of the chain, not a
    bare SN id (WI-146 REVIEW-A). Reads `spine_carrier`, the ONE home the fold
    now has — it was the third copy of a rule three modules
    promised in a docstring to change together, and did not. Takes TEXT rather
    than a path because the approve view already holds the registry's contents,
    and the CARRIER its caller resolved the file under, so the text is never
    read by a guess; example `-000` rows are skipped."""
    needs = spine_carrier.needs_from_text(sn_text, carrier)
    return {
        row["id"]: {k: v for k, v in row.items() if k != "id"}
        for row in (
            {
                k: _SN_EMPHASIS.sub("", v).strip()
                for k, v in spine_carrier.folded(n).items()
            }
            for n in needs
            if not is_example(n.get("id", ""))
        )
    }


# --- the re-attestation brief (--approve modified, WI-316) ----------------------
# A sitting cannot bless a delta it cannot see: for each SR owing a human act the
# brief shows every chain row's changed cells as BEFORE (the row in the
# `docs/archive/last_approved/` snapshot) vs AFTER (the working tree).
#
# THE BASELINE STOPPED BEING GIT ARCHAEOLOGY AT D-9 STEP 4 (owner directive
# 2026-08-15). It used to be the newest commit at which the SR row read
# `Verified` (now `Approved`), which is correct only while every amendment flips its row in the
# same commit — and D-9 deletes the flip, so that walk returns HEAD and the diff
# is empty by construction. The snapshot is a baseline OUTSIDE the live file,
# which is what the walk could never be.
#
# `_rows_at` and `_toml_rows_text` — the carrier-aware history readers that
# survived step 4 with no caller — ARE GONE (2026-08-15, log 2026-08-15h). The
# previous revision named them DEAD rather than describing them as reserved,
# which is the mistake the retired `current_digests` docstring made ("do not
# delete them for being unreferenced"), and this is that note being honoured:
# the only readers left were their own three tests. Nothing is lost by the
# deletion — `check_trajectory._spine_rows_at` is the surviving carrier-aware
# `git show` reader, still exercised by the cutover suite, so the D-5 hazard
# those tests guarded (a baseline read that knows only the live carrier reports
# every pre-migration revision as an EMPTY baseline, and the owner re-blesses
# full text with no diff) is still covered where the reader actually lives.

SPINE_FILES = (
    ("docs/requirements/system-requirements.toml", "SR-ID"),
    ("docs/requirements/low-level-requirements.toml", "LLR-ID"),
    ("docs/test/test-cases.toml", "TC-ID"),
)

# --- the spine carrier (repo-lock D-5/D-6) -----------------------------------
# The vocabulary and both readers live in `spine_carrier.py`, imported as a
# sibling. The full argument for that home — and why it AMENDS the F5 ruling
# rather than ignoring it (owner ruling 2026-08-10) — is in that module's
# docstring; the short version is that a duplicated VOCABULARY fails
# silently, by returning a row with a cell missing, which every consumer reads
# as "the cell is empty".
SPINE_TABLE = spine_carrier.SPINE_TABLE
SPINE_COLUMN = spine_carrier.SPINE_COLUMN
_spine_stem = spine_carrier.stem


# stdout of a git command under `root`, or None on ANY failure (no git binary,
# not a repo, unknown rev/path, non-zero exit) — the house best-effort-off-git
# pattern. ONE HOME since WI-448 (`kitlib.git`): it was written out three times,
# in check.py, trace.py and trunk_step.py, each docstring pointing at the others
# as though one of them were the original. Kept under its own long-standing
# private name so no call site below moves.
_git_out = _kitgit.git_out


# The reviewable-text threshold, shared by both re-attestation renderers
# (this module's markdown brief and `gen_open_items.py`'s HTML, which imports
# `truncate_cell` rather than re-deriving its own limit — one number, not a
# pair a future edit could let drift). Generous on purpose: this gates a
# handful of genuinely long prose cells (a Detail or a Rationale paragraph),
# not the common case, so a normal cell never crosses it.
CELL_TRUNCATE_LIMIT = 1500


def truncate_cell(text, limit=CELL_TRUNCATE_LIMIT):
    """`text` clipped to `limit` characters with an EXPLICIT marker naming how
    much was dropped — never a silent cut. The brief this feeds is an owner
    approval surface: a cell trimmed without saying so reads identically to a
    cell that was always short, which is exactly the false-green shape the
    rest of this kit refuses. Below the limit, `text` is returned unchanged —
    the common case pays nothing, not even a length check past the compare."""
    text = text or ""
    if len(text) <= limit:
        return text
    return "{}… [{} more chars — read the registry row]".format(
        text[:limit], len(text) - limit
    )


def _full_row_bullets(row):
    """The `- **Cell**: value` bullets for a WHOLE registry row, non-empty cells
    only — how the re-attestation brief renders a row it has no baseline to diff
    against. Both arms that need it (no attested baseline, and a row ADDED since
    the baseline) rendered it identically in place (WI-347); same file, so the
    cross-script F5 sanction never covered the copy."""
    return [
        "- **{}**: {}".format(k, truncate_cell(v.strip()))
        for k, v in row["full"].items()
        if (v or "").strip()
    ]


def _anchor_lines(sr_row):
    """The anchor SR's OWN reviewable text — Requirement verbatim, Rationale
    truncated the same way — as quoted markdown lines, rendered UNCONDITIONALLY
    for every entry regardless of whether the SR row itself appears among its
    chain rows.

    THE GAP THIS CLOSES: an `Approved`, undrifted SR whose amendment lives
    entirely in a `Drafted` child never appeared in `entry["rows"]` at all (see
    `reattest_model`'s `if cells or drafted:` gate) — so the brief showed the
    chain row a human must bless with no statement of the requirement it hangs
    from. The owner's report, verbatim (2026-08-24): opening the surface and
    looking at an owing SR, the requirement text itself was nowhere on the
    page. `_full_row_bullets`/`_cell_diff_lines` already rendered a CHANGED or
    ADDED chain row's own text in full; this is the one row shape — SR
    unchanged, chain amended beneath it — that rendered nothing."""
    if not sr_row:
        return []
    out = []
    req = (sr_row.get("Requirement") or "").strip()
    rat = (sr_row.get("Rationale") or "").strip()
    if req:
        out += ["> **Requirement.** {}".format(truncate_cell(req)), ""]
    if rat:
        out += ["> **Rationale.** {}".format(truncate_cell(rat)), ""]
    return out


def _cell_diff_lines(changed, approved=frozenset(), drafted=False):
    """The per-cell before/after bullets, split into the §A5.1 two groups.

    The split is a capability the snapshot comparison hands the reader for free
    (D-9 step 4): an APPROVED cell that moved owes an attestation, a TRACED one
    routes to adjudication and arms no window. Rendering them in one
    undifferentiated list asked the owner to make that judgement per cell, from
    memory, mid-sitting. Headings appear only when BOTH groups are present —
    a lone heading over the only group is noise.

    `drafted` COLLAPSES THE SPLIT (OI-71 defect 1). The two group labels are a
    property of a row that HAS been approved: an approved cell of it "owes a
    re-attestation", a traced one "routes to adjudication". A `Drafted` row was
    never approved — none of its cells owes a re-attestation and none arms a
    window; the whole row owes a FIRST approval, which its own section heading
    already states. Keyed on the cell's COLUMN class alone, the split rendered a
    Drafted row's approved-class cells under "approved — re-attestation owed" —
    the exact false label round 019 of the wi508 lane caught. For a Drafted row
    the cells therefore render in one plain list, no group heading.

    The before/after render WHOLE, never through `truncate_cell` (OI-71 defect
    2). A changed cell is the one thing the reader must see entire: clipping it
    to a fixed prefix rendered before and after identically whenever the
    divergence sat past the cutoff, hiding the very change under review. The
    generous cap stays on the CONTEXT surfaces — the anchor Requirement /
    Rationale and the whole-row `_full_row_bullets` dumps — not on the targeted
    diff a signer rules from."""
    if drafted:
        groups = [(None, changed)]
    else:
        groups = [
            (
                "approved — re-attestation owed",
                [c for c in changed if c[0] in approved],
            ),
            (
                "traced — routes to adjudication",
                [c for c in changed if c[0] not in approved],
            ),
        ]
    show_headings = not drafted and all(rows for _label, rows in groups)
    lines = []
    for label, rows in groups:
        if not rows:
            continue
        if show_headings:
            lines.append("_{}_".format(label))
        for cell, b, a in rows:
            lines.append("- **{}**".format(cell))
            lines.append("  - before: {}".format(b or "(empty)"))
            lines.append("  - after: {}".format(a or "(empty)"))
    return lines


def _entry_kind(sr_drafted, chain_has_drafted):
    """What the model's entry OWES: a first approval, or a re-attestation of
    text that moved after it was blessed.

    BACK TO TWO ARMS AT D-9 STEP 5. The third (`plan`, for a `Planned` row whose
    text was approved and whose evidence was never established) went out with the
    word: OI-30 D1 ruled `Planned` IS `Approved`, so there is no longer a state
    that means "blessed text, no evidence" — evidence is the harness's answer,
    not a cell's. A `Drafted` row owes a first approval and has no baseline to
    diff against; anything else in the model is here because its text moved after
    it was blessed.

    AND THE SECOND ARM HAS ONE SOURCE SINCE STEP 7, where it used to have two: a
    row said so itself (`Modified`) OR the snapshot said so (drift). The marker
    retired with the word, so the snapshot is the whole answer — which is the
    point of the mechanism rather than a loss (owner ruling 2026-08-17m). This
    function is unchanged by that: it already returned `reattest` for everything
    that is not `drafted`.

    WIDENED (the OI-61-sitting gap, `docs/log.d/2026-08-23-oi61-rule-and-spine-
    approval.md`): `state` used to be read off the SR's own `Status` alone, which
    is exactly the discriminator that let nineteen `Drafted` LLR/TC rows sit
    under `Approved`, undrifted SRs and never reach the brief's pill. The pill
    now answers "does ANYTHING in this chain owe a first approval" — the SR
    itself, or any LLR/TC beneath it — because that is the action the reader
    actually owes; a card whose only drafted content is a child would otherwise
    wear "re-attest owed" and mislead about what act closes it."""
    if sr_drafted or chain_has_drafted:
        return "approve"
    return "reattest"


# "the caller passed nothing" vs "the caller passed None". `None` is a REAL
# argument here — it means "compare against no snapshot at all", which is the
# pre-signing state and a legitimate thing to ask for — so the default cannot
# also be None or a caller could never express the difference.
_UNSET = object()


def sr_chain_drifts(sid, chain, snapshot):
    """True when ANY row in this SR's chain has drifted from the snapshot.

    The brief GROUPS by owning SR for reading — a drifted LLR or TC surfaces
    under its owning SR's section — but the grouping is presentation, never
    attestation scope: a row's Status answers for its OWN cells, and a child
    amendment never flips the parent SR (owner ruling 2026-08-17m; the
    chain-completeness claim belongs to the derived `Founded` state, D-9 step
    8). This drift arm catches a child amended while still claiming approval —
    which, since step 7 retired the `Modified` marker, is EVERY post-approval
    amendment rather than only the unmarked ones. There is no longer a marked
    case to split off: a cell cannot record an amendment the ladder does not
    flip, so the comparison against the snapshot is the whole detector.

    THE ORPHANED CHILD IS NOT THIS ARM'S GAP, though it reads like one. When
    `modified_chain_advisories` was retired at that ruling it also took its
    "no resolvable owning SR" arm, and this docstring's "never counts as
    drifted" concession made that look like a class left undetected. Measured
    on a planted tree (2026-08-17 desk round, F12): the ORPHAN rules already
    report every sub-case, and report it HARDER than the retired advisory did —
    an unknown parent id is "LLR-### references unknown SR-###", an absent one
    is "LLR-### has no SR parent", the TC arm is the same pair on `Verifies`,
    and an explicitly EMPTY ref cell is refused outright by the carrier. Those
    are orphan findings, so they GATE under `--strict`, where the retired arm
    only warned. No successor detector is owed here."""
    return any(
        baseline_snapshot.is_drifted(
            rel, id_col, row, baseline_snapshot.rows_for(snapshot, rel, id_col)
        )
        for kind, _rid, row in chain
        for rel, id_col in (SPINE_FILES[_KIND_IX[kind]],)
    )


# `chain_of`'s row kinds -> their index in SPINE_FILES. Stated rather than
# derived from the id prefix: the prefix is data and this is a lookup into a
# constant, and a mis-derived index would compare an LLR against the SR
# registry's snapshot rows — which reads as "every cell changed".
_KIND_IX = {"SR": 0, "LLR": 1, "TC": 2}


def _owes_first(row):
    """Does this row owe a FIRST approval: it is `Drafted`, or it carries no
    `Status` cell at all, which claims no approval for a drift arm to judge and
    is not `Drafted` either, so no arm read it and the brief omitted it.

    Implements: SR-157, LLR-272"""
    return is_drafted(row) or not (row.get("Status") or "").strip()


def _spine_stamps(root, snapshot):
    """`{tier: (short rev, date)}`: the commit that last wrote EACH spine
    registry's own copy — a refresh copies only what its act authorises, so one
    directory-wide stamp named one copy's commit for all three. Empty stamps
    when the model compares against no record.

    Implements: SR-178, LLR-273"""
    return {
        kind: baseline_snapshot.stamp(root, SPINE_FILES[ix][0])
        if snapshot
        else ("", "")
        for kind, ix in _KIND_IX.items()
    }


def reattest_model(root, srs, llrs, tcs, snapshot=_UNSET):
    """The STRUCTURED attestation model: one entry per SR owing a human act,
    with its chain rows and each row's changed cells.

    Split out of `reattest_lines` (WI-322) so the computation runs ONCE and two
    renderers consume it — the markdown brief here, and the generated
    `open-items.html` owner view in `gen_open_items.py`.

    THE SELECTOR IS NO LONGER A LIST OF STATUS WORDS (D-9 step 4). It used to
    be `statuses=("modified",)` — the "hard coupling" the migration plan named,
    because a brief that selects a literal returns a clean bill forever once
    that literal is retired, at exit 0, with nothing to notice. A row now owes
    an act when it is `Drafted` (a first approval is owed) — or when its chain
    has DRIFTED from `docs/archive/last_approved/`, which is a property of two
    files rather than of a word, and which no rename can silence.

    THE `Drafted` ARM IS CHAIN-WIDE, NOT SR-ONLY (the OI-61-sitting widening,
    `docs/log.d/2026-08-23-oi61-rule-and-spine-approval.md`). The selector used
    to read `Drafted` off the SR row alone, so a `Drafted` LLR or TC hanging off
    an `Approved`, undrifted SR reached no surface: the drift arm cannot catch
    it either, since a row below approval has made no claim to fall from, and one
    absent from the snapshot is unanchored rather than drifted. The docstring
    said "a row" from the start; the code now matches it — `owes()` tests every
    row in the SR's chain, not just the SR.

    THE `Modified` ARM LEFT AT STEP 7: the selector now reads ONE status word,
    for the one thing a word can honestly answer — "this row has never been
    approved". Everything post-approval is the snapshot's answer (owner ruling
    2026-08-17m). The arm was deleted only after its successor had run live
    beside it through the signing, which is why the migration ordered steps 4, 6
    and 7 as it did.

    `snapshot` defaults to reading the live one. Pass an explicit `None` to
    compare against nothing (the vacuous state, which is also every
    pre-signing repo's): drift then answers False everywhere and the selector
    falls back to the `Drafted` arm alone.

    Returns `[{id, title, kind, baseline, baseline_date, baselines,
    no_baseline_reason, rows:[{kind, id, state, cells, approved, full,
    drafted}]}]` where `baselines` is `{tier: (short rev, date)}`, the commit
    that last wrote EACH spine registry's copy (`baseline`/`baseline_date` are
    the requirement registry's), `state` is
    `changed` | `added` | `removed` | `current` | `drafted` (the last: a
    `Drafted` row with no cell diff against the snapshot — it owes only because
    it was never approved, not because its text moved), `cells` is the
    `(name, before, after)` triples ORDERED approved-first, `approved` is the
    subset of those names §A5.1 rules approved (so a renderer groups by one
    membership test rather than re-deriving the split), `full` is the row dict
    for the states that render whole rows, and `drafted` is whether THIS row
    (independent of `state`) is in the pre-approval `Drafted` state — the
    per-row "why" a renderer needs to say "Drafted, never approved" rather than
    leave that reason implicit in `state` alone; a row with no `Status` cell
    reads as owing its first approval the same way (`_owes_first`). `kind`
    answers for the whole chain: `approve` if the SR or any chain row owes a
    first approval, `reattest` otherwise (drift only). Deterministic given the working tree and the
    snapshot."""
    if snapshot is _UNSET:
        snapshot = baseline_snapshot.load_all(root)

    llrs_by_sr, tcs_by_ref = chain_buckets(llrs, tcs)
    chain_of = spine_chain

    def owes(sr):
        if _owes_first(sr):
            return True
        chain = chain_of(sr.get("SR-ID", ""), srs, llrs_by_sr, tcs_by_ref)
        # WIDENED: a `Drafted` LLR/TC owes a first approval in its own right,
        # regardless of what its owning SR's Status says — `is_drafted(sr)`
        # above tests the SR row ONLY, and `sr_chain_drifts` below cannot see
        # this case either (a row below approval has made no claim to fall
        # from, and one absent from the snapshot is unanchored, not drifted).
        # Without this arm the row is invisible to the brief a human approves
        # from (the OI-61-sitting finding).
        if any(_owes_first(row) for _kind, _rid, row in chain):
            return True
        return sr_chain_drifts(sr.get("SR-ID", ""), chain, snapshot)

    pending_srs = sorted((r for r in srs if owes(r)), key=lambda r: r.get("SR-ID", ""))
    if not pending_srs:
        return []
    stamps = _spine_stamps(root, snapshot)

    snap_rows = {
        kind: baseline_snapshot.rows_for(snapshot, *SPINE_FILES[ix])
        for kind, ix in _KIND_IX.items()
    }
    base_srs = list(snap_rows["SR"].values())
    base_llrs_by_sr = _bucket_by_ref(list(snap_rows["LLR"].values()), "SR-Refs")
    base_tcs_by_ref = _bucket_by_ref(list(snap_rows["TC"].values()), "Verifies")

    model = []
    for sr in pending_srs:
        sid = sr.get("SR-ID", "")
        current_chain = chain_of(sid, srs, llrs_by_sr, tcs_by_ref)
        entry = {
            "id": sid,
            "title": (sr.get("Title") or "").strip(),
            # WIDENED: the pill answers for the whole chain, not the SR row
            # alone — see `_entry_kind`'s docstring for why.
            "kind": _entry_kind(
                _owes_first(sr),
                any(_owes_first(row) for _k, _i, row in current_chain),
            ),
            "baseline": "",
            "baseline_date": stamps["SR"][1],
            "baselines": stamps,
            "no_baseline_reason": "",
            "rows": [],
        }
        # A row ABSENT from the snapshot has no baseline to diff against — and
        # under the snapshot that is a statement about a FILE, checkable by
        # opening it, rather than the old "the row was never approved in
        # committed history", which was a claim about a git walk.
        if snapshot is None or sid not in snap_rows["SR"]:
            entry["no_baseline_reason"] = (
                "no {} snapshot exists yet — this repo has approved nothing, so "
                "every row awaits a first approval".format(
                    baseline_snapshot.SNAPSHOT_DIR
                )
                if snapshot is None
                else "absent from the {} snapshot — awaiting its first approval".format(
                    baseline_snapshot.SNAPSHOT_DIR
                )
            )
            entry["rows"] = [
                {
                    "kind": k,
                    "id": i,
                    "state": "current",
                    "cells": [],
                    "approved": frozenset(),
                    "full": r,
                    "drafted": _owes_first(r),
                }
                for k, i, r in current_chain
            ]
            model.append(entry)
            continue
        entry["baseline"] = stamps["SR"][0]
        base_chain = chain_of(sid, base_srs, base_llrs_by_sr, base_tcs_by_ref)
        base_by_id = {(k, i): r for k, i, r in base_chain}
        cur_by_id = {(k, i): r for k, i, r in current_chain}
        for kind, rid, row in current_chain:
            before = base_by_id.get((kind, rid))
            drafted = _owes_first(row)
            if before is None:
                entry["rows"].append(
                    {
                        "kind": kind,
                        "id": rid,
                        "state": "added",
                        "cells": [],
                        "approved": frozenset(),
                        "full": row,
                        "drafted": drafted,
                    }
                )
                continue
            rel, id_col = SPINE_FILES[_KIND_IX[kind]]
            split = check_trajectory.split_changed_cells(rel, id_col, before, row)
            # APPROVED FIRST, then traced — the reader's question is "what do I
            # have to re-bless?", and the §A5.1 split answers it: an approved
            # cell owes attestation, a traced one routes to adjudication and
            # arms no window (the WI-388 ruling).
            cells = [
                (name, split[half][name][0], split[half][name][1])
                for half in ("approved", "traced")
                for name in sorted(split[half])
            ]
            # WIDENED: a `Drafted` row present in the snapshot with no cell
            # diff (the snapshot copies every registry wholesale, not only
            # approved rows — `intake.py snapshot` — so a never-approved row
            # can sit there byte-identical) still owes its first approval.
            # Without this arm it would silently drop out here: `cells` is
            # empty and the old code only appended on a non-empty diff.
            if cells or drafted:
                entry["rows"].append(
                    {
                        "kind": kind,
                        "id": rid,
                        "state": "changed" if cells else "drafted",
                        "cells": cells,
                        "approved": frozenset(split["approved"]),
                        "full": row,
                        "drafted": drafted,
                    }
                )
        for kind, rid, row in base_chain:
            if (kind, rid) not in cur_by_id:
                entry["rows"].append(
                    {
                        "kind": kind,
                        "id": rid,
                        "state": "removed",
                        "cells": [],
                        "approved": frozenset(),
                        "full": row,
                        "drafted": False,
                    }
                )
        model.append(entry)
    return model


# WI-503: the brief SPLITS into an undated live surface and immutable dated
# history. `docs/ratify/CURRENT.md` is the one file a regeneration ever
# touches — a FIXED name, not derived by "newest by filename" the way the
# pre-split brief was. That derivation existed because every sitting picked a
# fresh date-stamped filename and a regeneration had to find whichever one was
# newest to rewrite it IN PLACE — which is exactly the defect: a dated file,
# named and read as the record of one sitting, kept being rewritten until a
# newer date appeared (measured: `docs/ratify/2026-08-13-wi444.md`, ten
# rewrites, none of them about WI-444). Under the split there is nothing to
# search for — the live surface has one name — and a dated brief is written
# exactly once, by `--mint-approval-brief`, never touched again by this path.
CURRENT_APPROVAL_BRIEF = "CURRENT.md"


def current_approval_brief(root):
    """The live re-attestation brief — `docs/ratify/CURRENT.md` — or None when
    it does not exist. The fixed counterpart of the retired
    `newest_approval_brief`; see `CURRENT_APPROVAL_BRIEF` for why a fixed name
    replaced a derived one."""
    path = Path(root) / "docs" / "ratify" / CURRENT_APPROVAL_BRIEF
    return path if path.is_file() else None


# --- WI-325: the re-attestation brief gets the freshness gate everything else has
# Every other generated surface here is freshness-gated (`gen_trajectory --check`,
# the status snapshot, `gen_okf --check`, `gen_open_items --check`); the brief was
# generated the same way and gated by nothing, so it silently drifted behind the
# registry it summarizes. Observed twice in one day: at 121-CRITIQUE it was
# missing LLR-105/TC-108 and SR-054's later amendment (an owner would have blessed
# six rows having seen four), and again at 123-CRITIQUE it was three chain rows
# short. Both were caught by a human noticing — the weakest enforcement tier
# `docs/enforcement-audit.md` names.
#
# THE CONSTRAINT THAT MADE THIS HARDER THAN ITS SIBLINGS IS GONE (D-9 step 4).
# The brief used to SELF-STAMP a git-derived baseline, so `--check` had to
# compare against the baseline the FILE declared and must not re-derive one —
# because re-deriving was the WI-322 review BLOCKER, a regeneration that
# silently collapsed 43 chain-row diffs to 18 while `--check` certified the
# loss. `_DECLARED_BASELINE_RE` and `declared_since` existed only to read that
# self-stamp back.
#
# Under the snapshot there is nothing to re-derive: the baseline is a directory
# of files that a regeneration cannot move. So this is now the plain
# regenerate-and-compare its siblings always were, and the WI-325 blocker
# dissolves rather than being guarded against.


# The two lines `reattest_lines` derives from git rather than from the registry.
# Excluded from the freshness comparison, and named ONCE here so the renderer and
# the gate can never disagree about which lines are derived (the renderer's own
# note points back at this constant).
_DERIVED_STAMP_PREFIXES = (
    "_Baseline: ",
    "_Approval provenance: ",
)


def _without_derived_stamps(text):
    """`text` with the derived stamp lines dropped — the comparable half of a
    re-attestation brief."""
    return "\n".join(
        line
        for line in text.splitlines()
        if not line.startswith(_DERIVED_STAMP_PREFIXES)
    )


def approval_check(root, srs, llrs, tcs, out_path):
    """`(code, message)` for `--approve modified --check` — a plain
    regenerate-and-compare, like every other freshness gate in the kit.

    Fails CLOSED on a difference — a stale brief is read by a human about to
    attest, and the cost of a false green here is an owner blessing rows they
    were never shown.

    Two silences, both the arming idiom the component checks use rather than
    exceptions carved for this repo:

      - **no file at `--out`** — a project with no `docs/ratify/` pays nothing;
      - **no row owes an act** — the window is CLOSED, so the committed brief is
        a historical record of a finished sitting rather than a surface that can
        go stale. Checking it against a registry whose rows have since been
        blessed would fail forever, which is how a check earns its own ignore.

    THE `--since` / `declared_since` MACHINERY IS GONE (D-9 step 4). It existed
    because the brief self-stamped a git-derived baseline that a re-derivation
    could move, so `--check` had to read the file's own declaration back rather
    than compute one. The snapshot is a directory of files; regenerating cannot
    move it, so the comparison is honest without the self-stamp — and the WI-325
    "a gate that re-derives its own expectation" blocker dissolves.

    THE DERIVED STAMP LINES ARE EXCLUDED, and that is the same blocker in a
    smaller shape (2026-08-20, the batch review's MAJOR-11). `reattest_lines`
    renders two lines that come from `git log`, not from the registry: the
    snapshot's write commit and the last status-cell move. Both change on commits
    that move no row the brief renders, so comparing them made the brief STALE on
    a clean checkout — and a guard that fires on every commit is learned as noise
    and then ignored, which costs exactly the reads this gate exists to force. The
    comparison now covers the CONTENT: the rows, their cells, and the prose around
    them."""
    if not out_path.exists():
        return 0, "no brief at {} — nothing to gate".format(out_path)
    model = reattest_model(root, srs, llrs, tcs)
    # An assumption owing an approval keeps the window open (SR-203), so a
    # batch holding only assumptions is freshness-checked like any other.
    if (
        not model
        and not assumptions_owing(root, *_assumption_rows(root))
        and not baseline_snapshot.needs_owing(root)
    ):
        return 0, "no row owes an approval or a re-attest — the window is closed"
    try:
        with out_path.open("r", encoding="utf-8", newline="") as fh:
            existing = fh.read()
    except OSError as exc:
        return 1, "cannot read {}: {}".format(out_path, exc)
    rendered = "\n".join(reattest_lines(root, srs, llrs, tcs)) + "\n"
    if _without_derived_stamps(rendered) == _without_derived_stamps(existing):
        return 0, "{} is current".format(out_path)
    return 1, (
        "{} is STALE against the registry and the {} snapshot. Regenerate it "
        "with `trace.py --approve modified --out {}` and re-read it BEFORE "
        "attesting — an owner blessing a short brief blesses rows they were "
        "never shown.".format(out_path, baseline_snapshot.SNAPSHOT_DIR, out_path)
    )


# --- WI-518: the off-spine census ---------------------------------------------
# `intake.py snapshot` may copy any of the SEVEN `SNAPSHOTTED` registries (all
# of them on a `--seed`; since WI-571 a refresh copies only the ones the act
# authorises), but `reattest_lines` renders one section per SR — the off-spine tiers
# (`interfaces.toml`, `external.toml`, `components.toml`) never reach it, so a
# row changed there since the last snapshot enters the signed baseline with no
# owner-visible before/after at all (found by the OI-62-sitting adversarial
# round, `docs/log.d/2026-08-24-oi62-rule-and-spine-approval.md`, its MAJOR-2).
#
# THIS IS A DISCLOSURE SURFACE, NOT A NEW GATE — it changes nothing `owes()`
# tests; the off-spine tiers carry their own approval machinery, one status
# cell per row, per the OI-30 D3 rung map. It answers one question only: "if a
# re-seed happens right now, how much off-spine text rides along with no
# per-row rendering anywhere?" — at FILE grain, the grain `SNAPSHOTTED` copies
# at, not the fuller per-row diff that is explicitly a possible follow-on.
#
# NO-CHANGE TIERS RENDER NOTHING (no standing noise a reader learns to ignore,
# the same reason the spine's own unchanged chain rows emit no section above).
OFFSPINE_CENSUS_TIERS = (
    ("docs/requirements/interfaces.toml", ("IF-ID",)),
    ("docs/requirements/external.toml", ("EXT-ID", "B-ID", "REL-ID")),
    ("docs/requirements/components.toml", ("CMP-ID",)),
)

# WI-/OI- tokens in a commit subject — the same house pattern `agent_loop.py`'s
# `build_scope_wis` uses to read a WI id back off a commit range, aimed here at
# whichever ruling(s) a reader would cite for an off-spine change.
_RULING_TOKEN_RE = re.compile(r"\b(?:WI|OI)-\d+\b")


def _offspine_row_diff(root, rel, id_cols, snapshot):
    """`(changed, added, removed)` row counts for one off-spine FILE (which may
    key several id-keyed tables, `external.toml`'s three) between the live
    tree and the snapshot copy. Plain whole-row equality, unlike the spine's
    approved/traced cell split (`check_trajectory.split_changed_cells`) —
    that split's table is keyed to the spine tiers, and this is a COUNT for a
    signer's attention, not a cell-level attestation surface."""
    live_by_key = {}
    for id_col in id_cols:
        for r in spine_carrier.load(Path(root) / rel, id_col, keep_examples=False):
            rid = str(r.get(id_col) or "").strip()
            if rid:
                live_by_key[(id_col, rid)] = r
    changed = added = removed = 0
    seen = set()
    for id_col in id_cols:
        for rid, before in baseline_snapshot.rows_for(snapshot, rel, id_col).items():
            key = (id_col, rid)
            seen.add(key)
            after = live_by_key.get(key)
            if after is None:
                removed += 1
            elif after != before:
                changed += 1
    added = sum(1 for key in live_by_key if key not in seen)
    return changed, added, removed


def _offspine_ruling_pointer(root, rel, stamp_rev):
    """One-line pointer at the ruling(s) whose commits touched `rel` since the
    snapshot was written — the `WI-###`/`OI-###` tokens in those commits'
    subjects, deduplicated — or `"none cited"` when git cannot say or names
    nothing. Advisory, like every other git-derived line in this brief
    (`baseline_snapshot.stamp`'s docstring): a reader loses one line of
    context on the degrade, and nothing computes from it."""
    if not stamp_rev:
        return "none cited"
    out = _git_out(
        root, ["log", "--format=%s", "{}..HEAD".format(stamp_rev), "--", rel]
    )
    if not out:
        return "none cited"
    ids = sorted(set(_RULING_TOKEN_RE.findall(out)), key=id_sort_key)
    return ", ".join(ids) if ids else "none cited"


def offspine_census_rows(root, snapshot=_UNSET):
    """`[{rel, changed, added, removed, ruling}]` — one entry per off-spine
    FILE with a nonzero delta since the snapshot, `ruling` being the
    `_offspine_ruling_pointer` string. `[]` when every off-spine tier is
    unchanged (including when there is no snapshot at all — nothing to
    disclose about a re-seed that has never happened).

    Split out (WI-518, the `reattest_model`/`reattest_lines` shape) so the
    comparison runs ONCE and two renderers consume it — this module's
    markdown brief (`offspine_census_lines`) and `gen_open_items.py`'s HTML
    owner view."""
    if snapshot is _UNSET:
        snapshot = baseline_snapshot.load_all(root)
    if snapshot is None:
        return []
    rows = []
    for rel, id_cols in OFFSPINE_CENSUS_TIERS:
        changed, added, removed = _offspine_row_diff(root, rel, id_cols, snapshot)
        if not (changed or added or removed):
            continue
        rows.append(
            {
                "rel": rel,
                "changed": changed,
                "added": added,
                "removed": removed,
                # Since THIS registry's copy was written, not the directory's
                # newest write, which may be another registry's copy.
                "ruling": _offspine_ruling_pointer(
                    root, rel, baseline_snapshot.stamp(root, rel)[0]
                ),
            }
        )
    return rows


def offspine_census_lines(root, snapshot=_UNSET):
    """Markdown lines for the off-spine census (WI-518): per off-spine
    registry that changed since the snapshot, rows changed/added/removed and a
    pointer at the ruling(s) whose commits touched it. `[]` — no heading, no
    lines — when every off-spine tier is unchanged, so a clean re-seed costs
    the reader nothing to read past. The markdown RENDERER over
    `offspine_census_rows`: the rows own the comparison, this owns the
    prose."""
    rows = offspine_census_rows(root, snapshot)
    if not rows:
        return []
    return [
        "## Off-spine census",
        "",
        "_Off-spine registries get no per-row rendering here; `intake.py snapshot`"
        " copies one only when a row in it moves into approval or arrives approved,"
        " `--approves` names it or `--reattests` names one of its rows; a re-SEED"
        " still blesses the whole tree. What it would absorb:_",
        "",
    ] + [
        "- `{rel}` — {changed} changed, {added} added, {removed} removed"
        " since the snapshot; ruling(s): {ruling}.".format(**r)
        for r in rows
    ]


# THE LABEL OF THE COLLAPSED BLOCK, in the owner's own words (OI-82 ruling).
WAITING_FOR_ADJUDICATION = "Waiting for automated adjudication"

# The row states that owe an act on their own: changed or added text, a row
# leaving the chain, and a `Drafted` row with no diff. A `current` row (the
# no-baseline arm) owes only when it is itself `Drafted`, the per-row flag.
_OWING_STATES = frozenset(("changed", "added", "removed", "drafted"))


def released_tiers(root):
    """The spine tiers (`SR`, `LLR`, `TC`) whose rows the dial `root` declares
    RELEASES to an adjudicator — the rows the owner no longer signs.

    The dial is read ONLY through `agent_common.human_approves_spine`, the
    predicate the mint (`intake._released_drafted_rows`) and the adjudicator's
    brief (`adjudicate_brief.first_approval_values`) filter through: a copy of
    the rung table here would be a third answer to one question. Each tier's
    registry is `SPINE_FILES`, the tier-to-file join this module already owns.
    Asked once per rendering, not once per row, so a legacy dial's migration
    note prints once per tier rather than once per chain row.

    Implements: SR-139, LLR-259
    """
    import agent_common as ac  # IF-224; deferred: only a rendered brief asks

    docs = Path(root) / "docs"
    return frozenset(
        kind
        for kind, ix in _KIND_IX.items()
        if not ac.human_approves_spine(docs, SPINE_FILES[ix][0])
    )


def dial_releases_chain(entry, released):
    """Is this owing chain an ADJUDICATOR's to approve rather than the owner's?

    True only when the chain has at least one row owing an act and EVERY such
    row's tier is in `released` (`released_tiers`). One held row keeps the
    whole chain on the owner's section: the owner's signature is still owed on
    it, and a row is read with its chain. A chain with no owing row is held
    too: nothing released it, and the conservative answer to "who approves" is
    the human.

    Implements: SR-139, LLR-259
    """
    owing = [
        row
        for row in entry["rows"]
        if row.get("drafted") or row["state"] in _OWING_STATES
    ]
    return bool(owing) and all(row["kind"] in released for row in owing)


def _waiting_lines(entries, srs_by_id):
    """The collapsed block of chains the dial releases: a heading, one line
    saying why they are set apart, then every chain in full inside a
    `<details>` block that is closed until the reader opens it. The ids go in
    the summary so the collapsed block still says what it holds."""
    ids = ", ".join(entry["id"] for entry in entries)
    lines = [
        "",
        "## {}".format(WAITING_FOR_ADJUDICATION),
        "",
        "_Every owing row of these chains sits on a rung"
        " `[attestation] human_approval_through` releases, so an adjudication"
        " session approves them and this sitting does not. Shown in full for"
        " sight; collapsed by default._",
        "",
        "<details>",
        "<summary>{} — {} chain(s): {}</summary>".format(
            WAITING_FOR_ADJUDICATION, len(entries), ids
        ),
    ]
    for entry in entries:
        lines += _entry_lines(entry, srs_by_id)
    return lines + ["", "</details>"]


def _entry_lines(entry, srs_by_id):
    """The markdown section for ONE owing chain of `reattest_model`: the
    anchor SR's own text, then each chain row as its state renders it.

    One function for both places a chain renders — the owner's section and the
    collapsed block of chains the dial releases to an adjudicator — so a chain
    reads the same wherever the dial puts it (the OI-82 ruling: released
    chains render in full, not as ids)."""
    sid, title = entry["id"], entry["title"]
    out = ["", "## {} — {}".format(sid, title or "(untitled)"), ""]
    # UNCONDITIONAL, unlike every other block below: the anchor SR's own
    # Requirement/Rationale render here regardless of whether the SR row
    # appears in `entry["rows"]` — see `_anchor_lines`'s docstring for the
    # gap this closes.
    out += _anchor_lines(srs_by_id.get(sid))
    if entry["no_baseline_reason"]:
        out.append(
            "_No approved baseline — {}; current state only._".format(
                entry["no_baseline_reason"]
            )
        )
        for row in entry["rows"]:
            out += ["", "### {} {} (current)".format(row["kind"], row["id"])]
            out += _full_row_bullets(row)
        return out
    for row in entry["rows"]:
        # WIDENED: a `Drafted` row that carries no cell diff against the
        # snapshot (it sat there byte-identical, never approved) still
        # renders — its own section, tagged with WHY, rather than being
        # dropped for lack of a diff.
        first = "Drafted" if _cell(row["full"], "Status") else "no Status cell"
        suffix = ", {} — never approved".format(first) if row.get("drafted") else ""
        if row["state"] == "added":
            out += [
                "",
                "### {} {} — ADDED since the snapshot{}".format(
                    row["kind"], row["id"], suffix
                ),
            ]
            out += _full_row_bullets(row)
        elif row["state"] == "drafted":
            out += [
                "",
                "### {} {} — {}, never approved".format(row["kind"], row["id"], first),
                "_No cell differs from the approved snapshot; this row owes"
                " because its own `Status` has never been `Approved`._",
            ]
            out += _full_row_bullets(row)
        elif row["state"] == "changed":
            out += [
                "",
                "### {} {}{}".format(row["kind"], row["id"], suffix),
            ]
            out += _cell_diff_lines(
                row["cells"], row["approved"], drafted=row.get("drafted", False)
            )
        elif row["state"] == "removed":
            out += [
                "",
                "### {} {} — REMOVED since the snapshot".format(row["kind"], row["id"]),
                "_In this SR's chain in the snapshot, out of it in the working"
                " tree — the row was deleted, re-parented, or superseded"
                " (a superseded row keeps existing; it leaves the chain)._",
            ]
    if not entry["rows"]:
        out.append(
            "_No cell differs from the approved snapshot. The row is here"
            " because its own `Status` asks for a human, not because its"
            " text moved._"
        )
    return out


# --- the assumption section of the approval brief (SR-203) --------------------
# An assumption is approved for what it lets the requirements claim, so its
# section leads with the requirements citing it and the needs they reach. It
# owes an approval the way a spine row does: it is `Drafted`, or it claims
# approval and its approved cells moved from the snapshot copy. The chain is
# `assumption_rules.assumption_chain`'s (IF-226), so the approver reads the rows
# the checker judges; what is here is the owing test and the markdown.

ASSUMPTIONS_REL = "docs/requirements/assumptions.toml"
# The reserved `--approve` scope that renders the assumption section alone.
ASSUMPTION_SCOPE = "assumptions"
_ASSUMPTION_ID = re.compile(r"(?:DA|SUR)-\d+", re.IGNORECASE)
# The cells each tier's section shows in a line of their own rather than in its
# cell list (SR-203 "shows its cells": every other non-empty cell is listed).
_DA_SHOWN = frozenset({"DA-ID", "EffectAt", "Falsifier"})
_SUR_SHOWN = frozenset({"SUR-ID", "Name", "Emulates", "Description"})


def _cell_bullets(row, shown):
    """`**Cell**: value` for every non-empty cell of `row` not in `shown`, in
    the row's own order, status and pointer cells included."""
    return [
        "**{}**: {}".format(c, _cell(row, c))
        for c in row
        if c not in shown and _cell(row, c)
    ]


def _assumption_rows(root):
    """`(das, surs)`: the assumptions registry's two tiers, examples dropped."""
    path = Path(root) / ASSUMPTIONS_REL
    return (
        spine_carrier.load(path, "DA-ID", keep_examples=False),
        spine_carrier.load(path, "SUR-ID", keep_examples=False),
    )


def assumptions_owing(root, das, surs, snapshot=_UNSET):
    """`[(id, why, drifted cells)]` for each assumption and surrogate owing an
    approval, assumptions first: a `Drafted` row, one with no `Status` cell,
    and one claiming approval whose approved cells differ from its snapshot
    copy — `baseline_snapshot.owing_rows`, the one owing rule the need section
    reads too."""
    if snapshot is _UNSET:
        snapshot = baseline_snapshot.load_all(root)
    return [
        (rid, why, cells)
        for id_col, rows in (("DA-ID", das), ("SUR-ID", surs))
        for rid, why, cells, _row in baseline_snapshot.owing_rows(
            ASSUMPTIONS_REL,
            id_col,
            rows,
            baseline_snapshot.rows_for(snapshot, ASSUMPTIONS_REL, id_col),
        )
    ]


def _listed(label, items):
    """A bold label, then one bullet per item, or `(none)`, each block set off
    by a blank line so no renderer folds the next one into the list."""
    bullets = ["- " + i for i in items] or ["- (none)"]
    return ["**{}**".format(label), ""] + bullets + [""]


def _assumption_lines(chain):
    """An assumption's body: citing requirements and the needs they reach
    first, then its landing crossings, its cells (status and standing among
    them), the cases that can falsify it and its falsifier, and a fidelity
    assumption's surrogate beside it. No evidence level: an assumption
    carries none (owner ruling 2026-10-02)."""
    row, sur = chain["row"], chain["surrogate"]
    out = _listed("Relied on by.", ["{} — {}: {}".format(*c) for c in chain["citing"]])
    out += _listed("Serving.", ["{} — {}".format(*n) for n in chain["needs"]])
    out += _listed(
        "Lands on.",
        ["{} — {} ({})".format(b, e or "no entity", n) for b, e, n in chain["landing"]],
    )
    # `RealizedBy` is shown by the surrogate line when it resolves to one
    # declared surrogate, and listed as a cell otherwise.
    shown = _DA_SHOWN | ({"RealizedBy"} if sur else set())
    out += _listed("Cells.", _cell_bullets(row, shown))
    out += [
        "**Can be falsified by.** {}".format(
            ", ".join(chain["cases"]) or "no test case"
        ),
        "",
        "**Falsifier.** {}".format(chain["falsifier"] or "(none declared)"),
    ]
    if sur:
        parties = ", ".join("{} ({})".format(*e) for e in sur["emulates"])
        out += [
            "",
            "**Surrogate.** {} — {}, emulating {}".format(
                sur["id"], _cell(sur["row"], "Name"), parties or "no party"
            ),
        ]
    return out


def _surrogate_lines(chain):
    """A surrogate's body: what it is, whom it answers for, and the assumptions
    stating its fidelity."""
    row = chain["row"]
    return (
        ["**Name.** {}".format(_cell(row, "Name")), ""]
        + _listed("Emulates.", ["{} ({})".format(*e) for e in chain["emulates"]])
        + ["**Description.** {}".format(_cell(row, "Description")), ""]
        + _listed("Cells.", _cell_bullets(row, _SUR_SHOWN))
        + _listed("Named by.", ["{} — {}".format(*d) for d in chain["named_by"]])
    )


def assumption_brief_lines(root, srs, tcs, ids=None):
    """The approval brief's section for assumptions and surrogates (SR-203):
    one `###` block per row owing an approval (`assumptions_owing`), or per row
    `ids` names, each built from `assumption_rules.assumption_chain`. `[]` when
    none is owed, so a brief for a batch without one is unchanged. A named id
    the registry does not declare REFUSES the run, as an unmatched scope does.

    Implements: SR-203, LLR-240"""
    das, surs = _assumption_rows(root)
    if not das and not surs:
        owing = []
    elif ids is None:
        owing = assumptions_owing(root, das, surs)
    else:
        owing = [(rid, "", []) for rid in ids]
    if not owing:
        return []
    reg = {"srs": srs, "tcs": tcs, "das": das, "surs": surs}
    reg["exts"], reg["bifs"] = (
        spine_carrier.load(Path(root) / "docs/requirements/external.toml", c, False)
        for c in ("EXT-ID", "B-ID")
    )
    reg["needs"] = spine_carrier.needs_for_root(Path(root))
    lines = [
        "## Assumptions and surrogates {}".format(
            "owing an approval" if ids is None else "named in the scope"
        ),
        "",
    ]
    for rid, why, cells in owing:
        chain = assumption_chain(rid, reg)
        if chain is None:
            raise SystemExit(
                "trace: --approve names {}, which the assumptions registry does "
                "not declare — refusing to emit a brief without it".format(rid)
            )
        lines += ["### {}{}".format(rid, " — " + why if why else ""), ""]
        if cells:
            lines += _cell_diff_lines(cells, frozenset(c[0] for c in cells)) + [""]
        body = _surrogate_lines if chain["kind"] == "surrogate" else _assumption_lines
        lines += body(chain) + [""]
    return lines


def _approval_body(scope, reserved, root, reg):
    """The `--approve` view's lines: the re-attestation brief for a reserved
    scope; the assumption section for the `assumptions` scope or a list of
    `DA-`/`SUR-` ids, after the hierarchy of any other ids in the list; and
    the hierarchy view otherwise. An assumption scope with nothing to render is
    REFUSED, as an unmatched SR scope is."""
    if reserved:
        return reattest_lines(root, reg.srs, reg.llrs, reg.tcs)
    named = [t.upper() for t in refs(scope) if _ASSUMPTION_ID.fullmatch(t)]
    rest = [t for t in refs(scope) if not _ASSUMPTION_ID.fullmatch(t)]
    if scope.strip().lower() != ASSUMPTION_SCOPE and not named:
        return approval_lines(
            scope, reg.sn_ids, reg.srs, reg.llrs, reg.tcs, reg.sn_meta
        )
    head = [
        "# Approval hierarchy — scope: {}".format(scope),
        "",
        "_GENERATED by `trace.py --approve {}` from the registries — do not"
        " hand-edit._".format(scope),
        "",
    ]
    if rest and scope.strip().lower() != ASSUMPTION_SCOPE:
        head = approval_lines(
            ",".join(rest), reg.sn_ids, reg.srs, reg.llrs, reg.tcs, reg.sn_meta
        ) + [""]
    section = assumption_brief_lines(root, reg.srs, reg.tcs, ids=named or None)
    if not section:
        raise SystemExit(
            "trace: --approve {!r}: no assumption or surrogate owes an approval — "
            "refusing to emit an empty brief".format(scope)
        )
    return head + section


def _baseline_lines(root):
    """The brief's `_Baseline: ` lines: the record, then each registry's copy
    with the commit that last wrote it (`registry_stamps`) — the provenance of
    the text each section is measured against, since a refresh copies only
    what its act authorises and the copies were written at different commits.
    Derived from git, so every line carries the prefix the freshness check
    drops (`_DERIVED_STAMP_PREFIXES`).

    Implements: SR-178, LLR-273"""
    stamps = baseline_snapshot.registry_stamps(root)
    if not stamps:
        return [
            "_Baseline: `{}` — no snapshot exists yet, so every row below awaits"
            " a FIRST approval and renders its current text in full._".format(
                baseline_snapshot.SNAPSHOT_DIR
            )
        ]
    return [
        "_Baseline: `{}` — each registry's copy, named by the commit that last"
        " wrote it:_".format(baseline_snapshot.SNAPSHOT_DIR),
        "",
    ] + [
        "_Baseline: `{}` copied {} ({})._".format(rel, date, rev)
        for rel, rev, date in stamps
    ]


def need_brief_lines(root):
    """The brief's section for the needs file's two tiers: one block per need
    or stakeholder owing an act (`baseline_snapshot.needs_owing`), a drifted
    one with its moved cells before and after, the rest with their cells in
    full. `[]` when none owes, so a brief with nothing here is unchanged.

    Implements: SR-178, LLR-271"""
    owing = baseline_snapshot.needs_owing(root)
    if not owing:
        return []
    lines = [
        "## Stakeholder needs and stakeholders owing an act",
        "",
        "_A drifted row's approved text moved from its `{}` copy: once its"
        " meaning is ruled, re-anchor it with `intake.py snapshot --reattests"
        " <ROW-ID>`; until then an act copying the needs registry is refused. A"
        " row with no `Status` cell, or a `Drafted` one, owes its first"
        " approval._".format(baseline_snapshot.SNAPSHOT_DIR),
        "",
    ]
    for rid, why, cells, row in owing:
        lines += ["### {} — {}".format(rid, why), ""]
        if cells:
            lines += _cell_diff_lines(cells, frozenset(c[0] for c in cells))
        else:
            lines += _full_row_bullets({"full": row})
        lines.append("")
    return lines


def reattest_lines(root, srs, llrs, tcs):
    """Markdown for the re-attestation brief (`--approve modified`, WI-316): one
    section per SR owing a human act (grouped by SR for reading) with per-cell
    before/after for every chain row (the SR + its LLRs + their/its TCs) that
    differs from the `docs/archive/last_approved/` snapshot, plus rows ADDED to
    or REMOVED from the chain.

    THE BASELINE IS A DIRECTORY, NOT A REVISION (D-9 step 4). It used to be the
    newest commit at which the SR row still read `Verified` (now `Approved`), with `--since` as
    the escape hatch for a streak that walk could not see. Both are gone: the
    walk dies by construction once an approved row stops flipping on amendment,
    and a snapshot cannot sit after the amendment it is supposed to precede.

    Each changed row renders its APPROVED cells first and its TRACED cells
    after, under their own heading — the capability the split buys a reader:
    approved cells owe an attestation, traced cells route to adjudication and
    arm no window (§A5.1, the WI-388 ruling).

    Deterministic given the working tree and the snapshot; a generator mode like
    `approval_lines` — runs no checks. The markdown RENDERER over `reattest_model`
    (WI-322): the model owns the comparison, this owns the prose.

    Implements: SR-139, LLR-259
    """
    model = reattest_model(root, srs, llrs, tcs)
    srs_by_id = {r.get("SR-ID"): r for r in srs if r.get("SR-ID")}
    appr_rev, appr_date = baseline_snapshot.approval_stamp(root)
    lines = [
        "# Re-attestation brief — spine rows owing an approval",
        "",
        "_GENERATED by `trace.py --approve modified` (WI-316) — do not"
        " hand-edit; cite the spine registries, not this rendering. One section"
        " per SR that is itself `Drafted`, has a `Drafted` LLR or TC anywhere"
        " in its chain, or whose chain has DRIFTED from the approved snapshot;"
        " each chain row shows only its CHANGED cells, before (the snapshot) vs"
        " after (the working tree), approved cells first — or, for a `Drafted`"
        " row with no cell diff, its full current content, since it owes only"
        " because it was never approved. `Status` itself is never listed — the"
        " marker is not the amendment. Rule on each section outside the"
        " collapsed `{}` block (every section, when none renders): bless → set"
        " a `Drafted` row's `Status` to `Approved` (process.md §7), and from the"
        " first signing onward run `intake.py snapshot` in the SAME commit —"
        " `intake.py snapshot --reattests <ROW-ID>` for a DRIFTED row, which no"
        " flip carries since it already reads `Approved` — or the record of"
        " what was blessed does not move. A chain inside that block is an"
        " adjudication session's to approve, not this sitting's._".format(
            WAITING_FOR_ADJUDICATION
        ),
        "",
        # TWO DERIVED LINES, AND THEY ANSWER DIFFERENT QUESTIONS (2026-08-20, the
        # batch review's MAJOR-4). This said "the reviewed commit that last moved
        # an approval" of a stamp that is nothing of the kind: `stamp` is a
        # `git log` over the snapshot DIRECTORY, so any write moves it — at the
        # time of the review it named a commit that moved zero approvals. The
        # line now says what the stamp IS, and the provenance the reader was
        # actually being promised is derived beside it, from the only mechanical
        # trace an approval leaves: a status line moving in a snapshotted
        # registry. Both are EXCLUDED from `approval_check`'s comparison
        # (`_DERIVED_STAMP_PREFIXES`) — a brief that goes stale because its own
        # stamp moved is a guard that fires on every commit.
    ]
    lines += _baseline_lines(root) + [
        "",
        "_Approval provenance: {}._".format(
            "the last commit to move a `Status` cell in a snapshotted registry is"
            " {} ({}) — the record's maturity cells have not moved since".format(
                appr_rev, appr_date
            )
            if appr_rev
            else "no commit in this checkout moved a `Status` cell in a"
            " snapshotted registry (or git cannot say)"
        ),
        "",
    ]
    # WI-518: rendered here — before the per-SR sections, after the derived
    # stamps — so it reaches the reader in BOTH arms below: the spine window
    # can be closed while an off-spine registry still changed since the last
    # snapshot, which is exactly the disclosure gap this closes.
    census = offspine_census_lines(root)
    if census:
        lines += census + [""]
    # SR-203: the assumptions and surrogates owing an approval, rendered in both
    # arms for the census's reason: a batch holding only assumptions still has
    # something to sign while the spine window is closed.
    lines += assumption_brief_lines(root, srs, tcs)
    lines += need_brief_lines(root)
    if not model:
        lines.append(
            "_No spine row differs from its `{}` copy, and no row awaits a first"
            " approval._".format(baseline_snapshot.SNAPSHOT_DIR)
        )
        return lines
    # THE DIAL SPLITS THE POPULATION, IT DOES NOT NARROW IT (OI-82, ruled (a)
    # as the owner refined it): every owing chain is still rendered, and a
    # chain whose every owing row sits on a rung the dial releases goes to a
    # collapsed block below the owner's section, in full.
    tiers = released_tiers(root)
    held, released = [], []
    for entry in model:
        (released if dial_releases_chain(entry, tiers) else held).append(entry)
    for entry in held:
        lines += _entry_lines(entry, srs_by_id)
    if released and not held:
        lines += [
            "",
            "_No chain on a rung the human-approval dial holds owes an act;"
            " every chain in this brief waits for automated adjudication._",
        ]
    if released:
        lines += _waiting_lines(released, srs_by_id)
    return lines


def approval_lines(scope, sn_ids, srs, llrs, tcs, sn_meta=None):
    """Markdown for the batch-scoped approval hierarchy (WI-146a). Groups the
    in-scope SRs under their primary (first-listed) stakeholder need — rendering
    that need's own prose (Need/Why/Acceptance from `sn_meta`, WI-146 REVIEW-A) —
    then nests each SR's LLRs and TCs with their prose. Deterministic, stdlib-only."""
    sn_meta = sn_meta or {}
    in_scope = _scope_srs(scope, srs)
    # Bucketed joins (WI-081's _bucket_by_ref), not per-parent refs() rescans —
    # a phase-scoped approve over a large registry was the one path still doing
    # the quadratic O(SR×LLR + LLR×TC) scans the report path already dropped.
    llrs_by_sr = _bucket_by_ref(llrs, "SR-Refs")
    tcs_by_ref = _bucket_by_ref(tcs, "Verifies")

    def tc_block(t):
        auto = " · Automated" if _cell(t, "Automated").lower() in ("yes", "y") else ""
        out = ["##### {} [{}]{}".format(t["TC-ID"], _cell(t, "Status") or "?", auto)]
        if _cell(t, "Method"):
            out.append("**Method.** {}".format(_cell(t, "Method")))
        if _cell(t, "Expected"):
            out.append("**Expected.** {}".format(_cell(t, "Expected")))
        return out

    def llr_block(lr):
        out = [
            "#### {} — {} [{}]".format(
                lr["LLR-ID"],
                _cell(lr, "Title") or "(untitled)",
                _cell(lr, "Status") or "?",
            )
        ]
        meta = []
        if _cell(lr, "Module"):
            meta.append("Module: {}".format(_cell(lr, "Module")))
        if _cell(lr, "Component"):
            meta.append("Component: {}".format(_cell(lr, "Component")))
        if meta:
            out.append("_({})_".format(" · ".join(meta)))
        if _cell(lr, "Detail"):
            out.append(_cell(lr, "Detail"))
        for t in tcs_by_ref.get(lr["LLR-ID"], []):
            out += tc_block(t)
        return out

    def sr_block(s):
        sid = s["SR-ID"]
        out = [
            "### {} — {} [{}] [{}]".format(
                sid,
                _cell(s, "Title") or "(untitled)",
                _cell(s, "Status") or "?",
                _cell(s, "Verification") or "?",
            )
        ]
        if _cell(s, "Requirement"):
            out.append("**Requirement.** {}".format(_cell(s, "Requirement")))
        if _cell(s, "AcceptanceCriteria"):
            out.append(
                "**Acceptance criteria.** {}".format(_cell(s, "AcceptanceCriteria"))
            )
        rubrics = _rubrics_cited(
            _cell(s, "Requirement"),
            _cell(s, "AcceptanceCriteria"),
            _cell(s, "Rationale"),
        )
        if rubrics:
            out.append("**Rubrics.** {}".format("; ".join(rubrics)))
        own_llrs = llrs_by_sr.get(sid, [])
        own_ids = {lr["LLR-ID"] for lr in own_llrs}
        for lr in own_llrs:
            out += llr_block(lr)
        # TCs verifying the SR directly (not via one of its LLRs).
        for t in tcs_by_ref.get(sid, []):
            if not set(refs(t.get("Verifies"))) & own_ids:
                out += tc_block(t)
        if not own_llrs and not tcs_by_ref.get(sid):
            out.append("_(no LLR/TC yet)_")
        return out

    lines = [
        "# Approval hierarchy — scope: {}".format(scope),
        "",
        "_GENERATED by `trace.py --approve {}` from the registries — do not"
        " hand-edit — {} SR(s). Review the registry CSVs, not this render"
        " (process.md §3)._".format(scope, len(in_scope)),
        "",
    ]
    if not in_scope:
        lines.append("_(no SR matched this scope)_")
        return lines
    # Group under the SR's primary (first) SN ref; SRs with no SN ref group last.
    by_sn = {}
    for s in sorted(in_scope, key=lambda r: id_sort_key(r["SR-ID"])):
        sn_refs = [x for x in refs(s.get("SN-Refs")) if x in sn_ids]
        key = sn_refs[0] if sn_refs else None
        by_sn.setdefault(key, []).append(s)
    ordered = sorted((k for k in by_sn if k), key=id_sort_key) + (
        [None] if None in by_sn else []
    )
    for sn in ordered:
        lines.append("## {}".format(sn if sn else "(no linked stakeholder need)"))
        prose = sn_meta.get(sn) if sn else None
        if prose:
            if prose.get("need"):
                lines.append("**Need.** {}".format(prose["need"]))
            if prose.get("why"):
                lines.append("**Why it matters.** {}".format(prose["why"]))
            if prose.get("acceptance"):
                lines.append("**Acceptance intent.** {}".format(prose["acceptance"]))
        for s in by_sn[sn]:
            extra = [x for x in refs(s.get("SN-Refs")) if x != sn]
            block = sr_block(s)
            if extra:
                block.insert(1, "_(also realizes {})_".format("; ".join(extra)))
            lines += block
    return lines


MERMAID_CLASSDEFS = [
    "    classDef orphan fill:#ffd6d6,stroke:#cc0000,color:#000;",
    "    classDef draft fill:#fff3cd,stroke:#cc9900,color:#000;",
]


def _mermaid_id(rid):
    # Mermaid node ids can't carry '-'/'.'-style separators — sanitize to '_'.
    return re.sub(r"\W", "_", rid)


def _mermaid_label(rid, title):
    if not title:
        return rid
    short = title if len(title) <= 40 else title[:39] + "…"
    return "{} — {}".format(rid, short).replace('"', "'")


def mermaid_graph(sn_ids, srs, llrs, tcs, orphan_ids, sn_draft=frozenset()):
    """A `graph LR` DAG of the chain (a TC verifies its SR *and* its LLR), colored
    by orphan/draft state via classDef. Kept small/diff-friendly on purpose — the
    HTML view is the one that scales. `sn_draft` colors unapproved SNs (§4a)."""
    sr_ids = {s["SR-ID"] for s in srs}
    llr_ids = {lr["LLR-ID"] for lr in llrs}
    nodes = {}  # rid -> (label, cls); dict insertion order keeps output stable
    edges = set()

    def add(rid, label, cls):
        nodes[rid] = (label, cls)

    for sn in sorted(sn_ids):
        add(
            sn,
            sn,
            "orphan" if sn in orphan_ids else ("draft" if sn in sn_draft else ""),
        )
    for s in srs:
        sid = s["SR-ID"]
        add(sid, _mermaid_label(sid, _cell(s, "Title")),
            _node_class(sid, _cell(s, "Status"), orphan_ids))  # fmt: skip
        for u in refs(s.get("SN-Refs")):
            if u in sn_ids:
                edges.add((u, sid))
    for lr in llrs:
        lid = lr["LLR-ID"]
        add(lid, _mermaid_label(lid, _cell(lr, "Title")),
            _node_class(lid, _cell(lr, "Status"), orphan_ids))  # fmt: skip
        for p in refs(lr.get("SR-Refs")):
            if p in sr_ids:
                edges.add((p, lid))
    for t in tcs:
        tid = t["TC-ID"]
        add(tid, tid, _node_class(tid, _cell(t, "Status"), orphan_ids))
        for x in refs(t.get("Verifies")):
            if x in sr_ids or x in llr_ids:
                edges.add((x, tid))

    lines = ["```mermaid", "graph LR"] + MERMAID_CLASSDEFS
    if not nodes:
        lines.append("    empty[No requirements yet]")
    for rid, (label, _cls) in nodes.items():
        lines.append('    {}["{}"]'.format(_mermaid_id(rid), label))
    for a, b in sorted(edges):
        lines.append("    {} --> {}".format(_mermaid_id(a), _mermaid_id(b)))
    for rid, (_label, cls) in nodes.items():
        if cls:
            lines.append("    class {} {};".format(_mermaid_id(rid), cls))
    lines.append("```")
    return lines


def _esc(text):
    return (
        text.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


HTML_HEAD = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Traceability map</title>
<style>
  body { font: 14px/1.5 system-ui, sans-serif; margin: 2rem; color: #222; }
  h1 { font-size: 1.3rem; }
  details { margin: 0.15rem 0 0.15rem 1.1rem; }
  summary { cursor: pointer; }
  .leaf { margin: 0.15rem 0 0.15rem 1.1rem; }
  .orphan { color: #b00020; font-weight: 600; }
  .draft { color: #8a6d00; }
  .note { color: #666; }
</style>
</head>
<body>
<h1>Traceability map</h1>
<p class="note">Generated by <code>scripts/trace.py --html</code>. Do not edit by
hand; review the registry CSVs, not this render (process.md §3 "Reviewability").</p>
"""

HTML_TAIL = "</body>\n</html>\n"


def html_document(roots):
    """A dependency-free, collapsible <details> tree of the full graph — inline
    CSS, zero JS, self-contained — for browse/onboard/audit at any size."""

    def walk(node, depth):
        pad = "  " * depth
        label = _esc(node["id"]) + _esc(_flag_suffix(node))
        if node["children"]:
            cls = ' class="{}"'.format(node["cls"]) if node["cls"] else ""
            out = ["{}<details open><summary{}>{}</summary>".format(pad, cls, label)]
            for child in node["children"]:
                out += walk(child, depth + 1)
            out.append("{}</details>".format(pad))
            return out
        leaf_cls = ("leaf " + node["cls"]).strip()
        return ['{}<div class="{}">{}</div>'.format(pad, leaf_cls, label)]

    body = []
    for r in roots:
        body += walk(r, 0)
    if not body:
        body = ['<p class="note">No requirements yet.</p>']
    return HTML_HEAD + "\n".join(body) + "\n" + HTML_TAIL


@dataclass(frozen=True)
class Registries:
    """Loaded spine + off-spine registries: raw rows (kept for the integrity/
    placeholder sweeps), example-filtered working sets for the join, and the SN
    ids/draft/prose scraped from stakeholder-needs.md. Produced by
    load_registries; consumed by --approve, analyze, and the report render.

    TYPED AND FROZEN at WI-483 (program shape item 5: typed immutable config +
    explicit mutable runtime state). It was an EMPTY class populated as an
    attribute bag, which is why `analyze` had to read two of its fields through
    `getattr(reg, ..., [])` — the bag gave no way to know whether the loader had
    set them. A frozen record answers that at construction: every field exists,
    the loader fills all of them in one call, and nothing downstream may mutate
    what LOADING produced. It is the immutable half of the pair; `Findings`
    below is the mutable half."""

    docs: Path
    raw_srs: list
    raw_llrs: list
    raw_tcs: list
    raw_pbs: list
    raw_repos: list
    raw_mods: list
    raw_parts: list
    raw_assets: list
    raw_cmps: list
    raw_ifs: list
    raw_exts: list
    raw_bifs: list
    raw_rels: list
    raw_sns: list
    raw_stks: list
    srs: list
    llrs: list
    tcs: list
    pbs: list
    mods: list
    parts: list
    assets: list
    cmps: list
    ifs: list
    exts: list
    bifs: list
    rels: list
    stks: list
    das: list
    surs: list
    sn_ids: set
    sn_draft: set
    sn_meta: dict
    sn_md: object  # Path to the resolved needs carrier, or None when absent.
    sn_needs: list
    sn_integrity: list
    provenance_allow: tuple
    hat_names: set
    hat_speaks_for: dict


@dataclass(frozen=True)
class AnalysisFlags:
    """The four delivery-filter/severity switches `analyze` reads, as a record
    rather than as whatever object the caller happened to have.

    WHY IT EXISTS (WI-483). `analyze(reg, args)` read `args.phase`,
    `args.require_verified`, `args.no_placeholders` and `args.strict_schema`
    off the argparse namespace, so a non-CLI caller had to FORGE one:
    `census.gap_census` imported `argparse` purely to build a four-field
    Namespace. The engine's configuration is four values, and this states them.
    `of()` accepts either this record or any object carrying the four
    attributes, so the CLI still passes its parsed args unchanged."""

    phase: str = ""
    require_verified: bool = False
    no_placeholders: bool = False
    strict_schema: bool = False

    @classmethod
    def of(cls, args):
        """Normalize a caller's config to this record (idempotent)."""
        if isinstance(args, cls):
            return args
        return cls(
            phase=getattr(args, "phase", "") or "",
            require_verified=bool(getattr(args, "require_verified", False)),
            no_placeholders=bool(getattr(args, "no_placeholders", False)),
            strict_schema=bool(getattr(args, "strict_schema", False)),
        )


@dataclass
class Findings:
    """The analyze() output — every finding list + derived set the report,
    console summary, and exit policy read. Produced by analyze().

    THE MUTABLE HALF, and deliberately not frozen (WI-483). Two of its fields
    are filled AFTER analyze returns, because the rules behind them read the
    filesystem and git and analyze's contract is purity — that is real mutable
    runtime state, and the honest shape for it is a declared field with an empty
    default, not an attribute that springs into existence at the call site."""

    orphans: list = field(default_factory=list)
    orphan_ids: set = field(default_factory=set)
    integrity: list = field(default_factory=list)
    placeholders: list = field(default_factory=list)
    schema: list = field(default_factory=list)
    advisories: list = field(default_factory=list)
    # Filled after analyze() returns: the id-watermark rules read the
    # filesystem and git, which analyze()'s pure contract forbids.
    watermark_advisories: list = field(default_factory=list)
    # Filled after analyze() returns, for the same reason: the snapshot's
    # unanchored rule reads the `docs/archive/last_approved/` tree. INTEGRITY
    # class since migration step 7 — it is also appended to `findings.integrity`
    # there, and kept as its own list so the console can name the rule.
    snapshot_findings: list = field(default_factory=list)
    # Filled after analyze() returns: the retirement records are files read
    # against git. Warn-first, so never in an exit code.
    retired_advisories: list = field(default_factory=list)
    provenance: list = field(default_factory=list)
    form: list = field(default_factory=list)
    paraphrase: list = field(default_factory=list)
    ears: list = field(default_factory=list)
    sr_artifact_advis: list = field(default_factory=list)
    sn_artifact_advis: list = field(default_factory=list)
    provenance_advis: list = field(default_factory=list)
    sr_fanout_advis: list = field(default_factory=list)
    verif_coherence_advis: list = field(default_factory=list)
    absolute_advis: list = field(default_factory=list)
    budget_findings: list = field(default_factory=list)
    module_findings: list = field(default_factory=list)
    component_findings: list = field(default_factory=list)
    knowledge_advisories: list = field(default_factory=list)
    interface_backlink_findings: list = field(default_factory=list)
    frame_backlink_findings: list = field(default_factory=list)
    hat_dangling: list = field(default_factory=list)
    interface_advisories: list = field(default_factory=list)
    status_findings: list = field(default_factory=list)
    phase_deferred: list = field(default_factory=list)
    phases: set = None
    mechanized_verified: list = field(default_factory=list)
    demonstrated_verified: list = field(default_factory=list)
    attested_verified: list = field(default_factory=list)
    draft_srs: list = field(default_factory=list)
    draft_llrs: list = field(default_factory=list)
    draft_tcs: list = field(default_factory=list)
    n_draft: int = 0
    area_counts: dict = field(default_factory=dict)


def _working_set(rows, id_col):
    """One tier's working set: the rows that carry an id, less the `-000`
    template examples, so a fresh scaffold has nothing to orphan. Stated once
    because every tier filters the same way; the raw list keeps both kinds of
    row for the placeholder and integrity checks."""
    return [r for r in rows if r.get(id_col) and not is_example(r[id_col])]


def load_registries(docs):
    """Load the spine + off-spine registries under docs (loading only — no analysis)."""
    # The three spine tiers read through the CARRIER — as do the IF and CMP
    # tiers since WI-443 (OI-14 part B). `load_csv` stays for the off-spine
    # registries below that have not moved yet (PB/REPO/PART/ASSET).
    raw_srs = spine_carrier.load(
        docs / "requirements" / "system-requirements.toml", "SR-ID"
    )
    raw_llrs = spine_carrier.load(
        docs / "requirements" / "low-level-requirements.toml", "LLR-ID"
    )
    raw_tcs = spine_carrier.load(docs / "test" / "test-cases.toml", "TC-ID")
    # Optional, off-spine coordination registry (process.md §9); absent file -> [].
    raw_pbs = load_csv(docs / "requirements" / "performance-budgets.csv")
    # Optional coordinator repo-delegation registry (REPO-###, MULTI_REPO.md, the
    # multi-repo layer). Formerly MOD-### in modules.csv — a delegated *repo* was
    # never a component, so the id freed "module" for other uses; the legacy
    # file + ids are still read (never breaking). Absent files -> [].
    raw_repos = load_csv(docs / "requirements" / "repos.csv")
    raw_mods = load_csv(docs / "requirements" / "modules.csv")
    # Optional purchased/external parts registry (process-options.md); absent
    # file -> []. Integrity-checked only (IF-Ref points at the off-spine IF-###
    # tier, which trace.py does not read).
    raw_parts = load_csv(docs / "requirements" / "procurement.csv")
    # Optional binary/large-asset provenance registry (process-options.md "Binary
    # assets"); absent file -> []. Integrity-checked only (its Refs back-link the
    # SR/LLR the asset realizes, but like PART it is off the joined spine — the
    # asset's provenance/license/hash is what matters, tracked in text even when
    # the binary itself can't be diffed).
    raw_assets = load_csv(docs / "requirements" / "assets.csv")
    # Optional domain-neutral component registry (CMP-###, process-options.md
    # "Component layer"): the set-grained knowledge + lifecycle home. Structure
    # is derived — membership is a `Component` tag on the primitive rows
    # (LLR/IF/ASSET/PART), never restated on the CMP row; absent file -> [].
    raw_cmps = spine_carrier.load(docs / "requirements" / "components.toml", "CMP-ID")
    # Optional interface-definition registry (IF-###, process.md §8): one row per
    # interface, stating what it concretely IS. Off the joined spine like
    # PART/ASSET, but its Req-Refs back-link and its endpoint join keep it
    # traceable (WI-056 closed the LLR-002-era gap). Absent file -> [].
    raw_ifs = spine_carrier.load(docs / "requirements" / "interfaces.toml", "IF-ID")
    # Optional depth-0 FRAME registry (WI-442, sitting-2 §1R.5): three tiers in
    # one file — who is outside (EXT-###), what crosses the system boundary
    # (B-##), and the external-to-external flows the system is not a party to
    # (REL-###). One `load` per tier; the carrier keys by ID COLUMN, so the
    # shared path needs no new loader. It is NOT free, and saying so beats an
    # unbacked "costs nothing": `load` reads and parses the file twice per call
    # (once for the rows, once for the nested-table check), so three tiers is six
    # reads and six parses of one small file per run — negligible at this size,
    # and the number to revisit if the frame ever stops being small. Absent
    # file -> [] three times, and every rule below is then vacuous, which is the
    # applies-when a project that declares no boundary needs.
    raw_exts = spine_carrier.load(docs / "requirements" / "external.toml", "EXT-ID")
    raw_bifs = spine_carrier.load(docs / "requirements" / "external.toml", "B-ID")
    raw_rels = spine_carrier.load(docs / "requirements" / "external.toml", "REL-ID")
    # Optional STAKEHOLDER LIST (SR-189), the needs file's second tier, loaded by
    # its OWN id column so a stakeholder's status never joins the needs' draft
    # set. Absent table -> [] and every stakeholder rule below is vacuous.
    raw_stks = spine_carrier.load(
        docs / "requirements" / "stakeholder-needs.toml", "STK-ID"
    )
    # Optional ASSUMPTIONS REGISTRY (SR-191, SR-192): its two tiers, one `load`
    # each by id column like the frame's, the `-000` examples dropped. Absent
    # file -> [] twice, and the tier is silent.
    assumptions = docs / "requirements" / "assumptions.toml"
    das = spine_carrier.load(assumptions, "DA-ID", keep_examples=False)
    surs = spine_carrier.load(assumptions, "SUR-ID", keep_examples=False)

    # The working sets exclude template example rows (ids ending "-000") so a
    # fresh scaffold has nothing to orphan; the raw lists above keep them for the
    # placeholder and integrity checks below.
    srs = _working_set(raw_srs, "SR-ID")
    llrs = _working_set(raw_llrs, "LLR-ID")
    tcs = _working_set(raw_tcs, "TC-ID")
    pbs = _working_set(raw_pbs, "PB-ID")

    mods = [
        r for r in raw_repos + raw_mods if _repo_id(r) and not is_example(_repo_id(r))
    ]
    parts = _working_set(raw_parts, "PART-ID")
    assets = _working_set(raw_assets, "ASSET-ID")
    cmps = _working_set(raw_cmps, "CMP-ID")
    ifs = _working_set(raw_ifs, "IF-ID")
    exts = _working_set(raw_exts, "EXT-ID")
    bifs = _working_set(raw_bifs, "B-ID")
    rels = _working_set(raw_rels, "REL-ID")
    stks = _working_set(raw_stks, "STK-ID")

    sn_ids = set()
    sn_draft = set()
    sn_meta = {}
    sn_integrity = []
    sn_rows = []
    sn_needs = []
    # Resolved through the CARRIER, not by literal suffix: a
    # `.toml`-only existence test reads a markdown needs registry as ABSENT, and
    # an absent needs tier makes every SR orphan-clean, every draft need
    # approved, and the whole SN half of `--strict` vacuous.
    sn_md = spine_carrier.resolve(
        docs / "requirements" / "stakeholder-needs.toml", spine_carrier.NEED_CARRIERS
    )
    if sn_md is not None:
        # utf-8-sig + replace: a BOM must not glue to line 1 (defeating the
        # heading regexes) and one stray cp1252 byte must degrade, not crash
        # the gate chain (the C8 convention, applied to content reads too).
        sn_text = sn_md.read_text(encoding="utf-8-sig", errors="replace")
        sn_ids = sn_all_ids(sn_text, sn_md.suffix)
        # Section-as-state maturity (derived-gate §4a): SNs under a "draft" heading
        # are unapproved (DevStg-Below) and exempt from the "SN with no SR" child rule below.
        # An unreadable needs file REFUSES the run, naming the file: answering
        # "no drafts" for it would read every need as approved.
        sn_draft = spine_carrier.draft_ids_or_refuse(sn_md, sn_text)
        sn_meta = _sn_prose(sn_text, sn_md.suffix)
        sn_integrity = sn_integrity_findings(sn_text)
        # The need tier's rows in the SAME `<TIER>-ID`/`Status` shape the CSV-era
        # tiers carry, so the ONE `ENUM_FIELDS` table can be read over SN too
        # (the enum floor in analyze()). NOT `spine_carrier.folded_needs`: that
        # fold projects onto `SN_CORE`, which has no `status` key at all, so a
        # Status check reading it would see a blank cell on every row and pass
        # vacuously — the silent-green shape this whole tier keeps re-learning.
        # Loaded ONCE and kept whole: `sn_rows` is the two-key projection the
        # enum floor reads, while `sn_needs` keeps every cell for the text rules
        # (`sn_artifact_advisories` reads `acceptance` and `why`). Same trap, one
        # level over: a text rule fed the projection above — or `folded_needs`,
        # which drops `status` — would scan a blank cell on every row and report
        # a clean tier it never looked at.
        sn_needs = list(spine_carrier.load_needs(sn_md))
        sn_rows = [
            {
                "SN-ID": str(n.get("id") or "").strip(),
                "Status": str(n.get("status") or "").strip(),
            }
            for n in sn_needs
        ]
    hat_names, hat_speaks_for = load_hat_names(docs.parent)
    return Registries(
        docs=docs,
        raw_srs=raw_srs,
        raw_llrs=raw_llrs,
        raw_tcs=raw_tcs,
        raw_pbs=raw_pbs,
        raw_repos=raw_repos,
        raw_mods=raw_mods,
        raw_parts=raw_parts,
        raw_assets=raw_assets,
        raw_cmps=raw_cmps,
        raw_ifs=raw_ifs,
        raw_exts=raw_exts,
        raw_bifs=raw_bifs,
        raw_rels=raw_rels,
        raw_sns=sn_rows,
        raw_stks=raw_stks,
        srs=srs,
        llrs=llrs,
        tcs=tcs,
        pbs=pbs,
        mods=mods,
        parts=parts,
        assets=assets,
        cmps=cmps,
        ifs=ifs,
        exts=exts,
        bifs=bifs,
        rels=rels,
        stks=stks,
        das=das,
        surs=surs,
        sn_ids=sn_ids,
        sn_draft=sn_draft,
        sn_meta=sn_meta,
        sn_md=sn_md,
        sn_needs=sn_needs,
        sn_integrity=sn_integrity,
        # The citation-frame advisory's reviewed exception list, read HERE rather
        # than in analyze(): analyze is the pure pass over loaded rows, and an
        # exception file is an input to load, not a finding.
        provenance_allow=load_provenance_allow(docs.parent),
        # The hats ROSTER's name set, read here for the same reason the allow file
        # is: analyze() is the pure pass over loaded rows, and a registry a cell
        # resolves AGAINST is an input to load, not a finding (WI-484). Each
        # hat's `speaks_for` rides the same read (SR-213).
        hat_names=hat_names,
        hat_speaks_for=hat_speaks_for,
    )


def verification_basis(srs):
    """Verification-basis audit surface (process.md §4): of the SRs the project
    reports Approved, how was each reached? Three kinds, most-to-least runnable —
    Test rests on a runnable check (mechanized); Demonstration/Manual/Analysis/
    Inspection/Critique rest on a human observing an outcome (demonstrated/
    observed — repeatable, but not a runnable check); Attest rests on a named
    human's recorded judgment (attested — trust-based). Split three ways, not
    binary (WI-259): once non-Test methods are gate-required, folding them into
    "mechanized" would overstate how much rests on runnable checks. Independent
    of --require-verified so the footprint is always visible. The cell is
    stripped once per row (M-1) before every classification. A blank or
    unrecognized method falls to the demonstrated/observed else-bucket — the
    conservative default, so an unknown method is never counted as a runnable
    check (--strict-schema separately flags an out-of-vocabulary method).

    Returns `(mechanized, demonstrated, attested)` id lists. Pure; extracted
    outward from `analyze` at WI-483."""
    mechanized_verified, demonstrated_verified, attested_verified = [], [], []
    for r in srs:
        if not is_approved(r):
            continue
        method = (r.get("Verification") or "").strip()
        if method in MECHANIZED_METHODS:
            mechanized_verified.append(r["SR-ID"])
        elif method in ATTESTED_METHODS:
            attested_verified.append(r["SR-ID"])
        else:
            demonstrated_verified.append(r["SR-ID"])
    return mechanized_verified, demonstrated_verified, attested_verified


def integrity_sweep(reg, raw):
    """The always-on integrity floor: CSV row structure, per-tier id integrity,
    the closed `Status` vocabulary, the SN tier's own duplicate protection, the
    parent-first rule's standing cases, the SR/LLR/TC citation triangle, and
    the off-spine registries' ids.

    Extracted outward from `analyze` at WI-483. `raw` is the three-tier
    `{label: rows}` map the caller also feeds the placeholder/schema sweeps, so
    the two readings of "the raw spine" cannot drift apart.

    Implements: SR-245, LLR-357
    """
    docs = reg.docs
    # CSV structure first (a misaligned row can make every later finding
    # misleading): every registry CSV — spine, off-spine, and project-added —
    # must have each data row parse to the header's column count. Swept by
    # location, not by a known-file list, so a registry this script never joins
    # (a project's own additions) is still guarded. `interfaces.csv` USED TO BE
    # the worked example here and is now wrong twice over — the IF tier moved to
    # `interfaces.toml` at WI-443, which this glob does not see at all, and the
    # tier IS joined now (`raw_ifs`) — so the example is dropped rather than
    # re-spelled: a sweep that guards CSVs cannot illustrate itself with a TOML.
    integrity = [
        f
        for d in (docs / "requirements", docs / "test")
        if d.is_dir()
        for p in sorted(d.glob("*.csv"))
        for f in structure_findings(p, p.relative_to(docs.parent).as_posix())
    ]
    integrity += [f for label in raw for f in integrity_findings(label, raw[label])]
    # The closed `Status` vocabulary (D-9 step 1). INTEGRITY-class rather than
    # schema-class on purpose: `--strict-schema` runs at DevStg-Impl only, so
    # a Status closure routed there would never execute in the repos this rule
    # exists for. A row carrying a word no predicate recognizes is invisible to
    # every surface — the re-attest brief, the pending projection, the basis
    # counters — which is a silent, not a loud, failure.
    integrity += [
        f for label in raw for f in enum_integrity_findings(label, raw[label])
    ]
    # SN is folded in SEPARATELY rather than joining `raw` above, because `raw`
    # also feeds the id-integrity and placeholder sweeps and the need tier owns
    # those already (`sn_integrity_findings` reads the registry as PROSE, since a
    # bare `SN-###` token in a paragraph is part of that tier's id universe).
    # Only the Status vocabulary was owed — and it was MISSING: `ENUM_FIELDS`
    # declared the SN entry (2026-08-17k) while `raw` named three tiers, so
    # `status = "Bananas"` on a need produced no finding at any bar. That is the
    # exact defect the LLR comment above records, one tier up.
    integrity += enum_integrity_findings("SN", reg.raw_sns)
    # ...and the stakeholder list, the needs file's other approvable tier.
    integrity += enum_integrity_findings("STK", reg.raw_stks)
    # A spine row with NO Status cell (or, once phased, no Phase cell) is the
    # shape the vocabulary check above cannot see: it judges present values.
    integrity += _spine.missing_cell_findings(dict(raw, SN=reg.raw_sns))
    # A spine row is approved only after the rows it hangs from are: a standing
    # approved child under an unapproved parent, named with both statuses. The
    # commit-time half (`check.py --parent-first`, the slot's lane-commit walk)
    # refuses the commit that moves either status into such a case.
    integrity += [
        "parent-first: " + _spine.parent_first_line(entry)
        for entry in _spine.parent_first_findings(dict(raw, SN=reg.raw_sns))
    ]
    # The SN tier's duplicate protection (prose registry — see
    # sn_integrity_findings): integrity-class like a duplicated CSV id.
    integrity += reg.sn_integrity
    # SR/LLR citation coherence: a TC that cites an SR and an LLR
    # together must not pair an LLR with an SR it does not decompose. Integrity-
    # class (wrong at any stage), so it joins the --strict-integrity floor.
    integrity += triangle_findings(reg.tcs, reg.llrs)
    # PB ids are integrity-checked too, but PB is kept out of the placeholder/
    # schema sweeps above: the budgets registry is optional (like interfaces.csv),
    # so a leftover PB-000 must never block a gate the project doesn't use.
    integrity += integrity_findings("PB", reg.raw_pbs)
    # The coordinator repo-delegation registry (REPO-###, MULTI_REPO.md) is the
    # same kind of optional off-spine registry — integrity-checked, but out of the
    # placeholder/schema sweeps, so a REPO-000 placeholder never blocks it. The
    # legacy modules.csv (MOD-###) rows are integrity-checked under their own key.
    integrity += integrity_findings("REPO", reg.raw_repos)
    integrity += integrity_findings("MOD", reg.raw_mods)
    # The purchased/external parts registry (PART-###, process-options.md) is the
    # same kind of optional off-spine registry — integrity-checked (malformed/
    # duplicate id), but out of the placeholder/schema sweeps and with no back-link
    # resolution (its IF-Ref points at the IF-### tier trace.py doesn't read), so a
    # project that buys nothing keeps its PART-000 placeholder without blocking a gate.
    integrity += integrity_findings("PART", reg.raw_parts)
    # The binary-asset provenance registry (ASSET-###, process-options.md) is the
    # same optional off-spine kind — integrity-checked (malformed/duplicate id),
    # out of the placeholder/schema sweeps and with no back-link resolution, so a
    # project with no binary assets keeps its ASSET-000 placeholder without
    # blocking a gate.
    integrity += integrity_findings("ASSET", reg.raw_assets)
    # The component registry (CMP-###, process-options.md "Component layer") is
    # the same optional off-spine kind — integrity-checked (malformed/duplicate
    # id), out of the placeholder/schema sweeps, so a CMP-000 placeholder never
    # blocks a gate; its PartOf/SupersededBy/membership joins are checked above.
    integrity += integrity_findings("CMP", reg.raw_cmps)
    # The interface-seam registry (IF-###, process.md §8) is the same optional
    # off-spine kind — integrity-checked (malformed/duplicate id), out of the
    # placeholder/schema sweeps, so an IF-000 placeholder never blocks a gate; its
    # Req-Refs back-link and endpoint join are checked below.
    integrity += integrity_findings("IF", reg.raw_ifs)
    return integrity


def placeholder_sweep(raw, sn_md):
    """The `--no-placeholders` sweep: leftover `-000` example rows across the
    three raw spine tiers plus the need registry's prose placeholders. Stated
    unconditionally here; the caller owns the flag."""
    return [f for label in raw for f in placeholder_findings(label, raw[label])] + [
        f"SN placeholder {u} still present" for u in scan_sn_placeholders(sn_md)
    ]


def schema_sweep(real):
    """The `--strict-schema` sweep over the example-filtered spine tiers. Stated
    unconditionally here; the caller owns the flag."""
    return [
        f for label in real for f in schema_findings(label, real[label])
    ] + phase_approved_findings(real)


def aspect_counts(srs):
    """Optional Aspect column (the ruled cross-cutting review grouping): count
    real SRs per aspect so coverage is visible. Report-only — never a finding,
    never an exit-code change; a registry without the column contributes
    nothing. The VALUE set is closed and checked by --strict-schema
    (ENUM_FIELDS); this is only the count."""
    counts = {}
    for r in srs:
        area = (r.get("Aspect") or "").strip()
        if area:
            counts[area] = counts.get(area, 0) + 1
    return counts


def _assumption_findings(reg, srs, tcs, ifs, exts, bifs):
    """The assumption tier's findings as `analyze` composes them, returned as
    `(frame, integrity, interface, advisories)`: each list joins the class of
    the same name there.

    Split out of `analyze` so it stays a composer within its line budget
    (`test_trace_coherence`). Every rule is the pure siblings' (D21); this only
    routes each result to its class: the tier entry point where the frame
    declares a crossing (SR-191..SR-196), each cited assumption's reach need by
    need (SR-195) and a need met in operation that nothing answers at an
    operation crossing (SR-188), both warn-only; an observation test case's
    declaration (SR-198), with or without a frame; and a boundary interface's
    bridging assumptions or waiver (SR-211), an undeclared assumption joining
    the interface class.
    """
    frame, integrity, advisories = assumption_tier_findings(
        srs, reg.das, reg.surs, exts, bifs
    )
    advisories = (
        advisories
        + assumption_reach_advisories(
            reg.das, srs, reg.sn_needs, reg.stks, exts, bifs, reg.surs
        )
        + need_frame_gap_advisories(reg.sn_needs, reg.stks, srs, bifs, reg.das)
    )
    observation_failures, observation_advisories = observation_tc_findings(tcs)
    bridge_failures, bridge_advisories = interface_bridge_findings(ifs, reg.das)
    return (
        frame,
        integrity + observation_failures,
        bridge_failures,
        advisories + observation_advisories + bridge_advisories,
    )


def analyze(reg, args):
    """The whole checker pass over loaded registries: orphan rules, off-spine
    back-link/membership checks, the --require-verified status criterion
    (phase-scoped), the integrity/placeholder/schema sweeps, and the always-on
    advisories. Pure — reads reg + flags, returns a Findings bag. No I/O.

    THE COMPOSER, since WI-483 (program shape item 5). Each rule family above
    states what it IS; this function states which ones RUN, on what, and where
    each result lands in the bag. What is left here that is not a call is the
    POLICY: the four flags (`AnalysisFlags`), the phase scope, and the reasons a
    finding class rides one pipe rather than another.

    Implements: SR-157, SR-015, LLR-015
    """
    flags = AnalysisFlags.of(args)
    srs, llrs, tcs = reg.srs, reg.llrs, reg.tcs
    cmps, ifs = reg.cmps, reg.ifs
    exts, bifs, rels = reg.exts, reg.bifs, reg.rels
    docs = reg.docs
    prov_allow = reg.provenance_allow
    sr_ids = {r["SR-ID"] for r in srs}
    llr_ids = {r["LLR-ID"] for r in llrs}

    da_ids = {r["DA-ID"] for r in reg.das}
    orphans, orphan_ids = spine_orphan_findings(
        srs, llrs, tcs, ifs, sr_ids, llr_ids, reg.sn_ids, reg.sn_draft, da_ids
    )
    module_ids = llr_module_ids(llrs)
    budget_findings = budget_backlink_findings(reg.pbs, sr_ids | llr_ids | module_ids)
    module_findings = delegation_findings(reg.mods, sr_ids)
    component_findings = component_membership_findings(
        cmps, llrs, ifs, reg.parts, reg.assets
    )
    knowledge_advisories = knowledge_pack_advisories(cmps, docs)

    # Interface seams (IF-###, process.md §8): an owner of the wrong SHAPE joins
    # the --strict failure set; an owner that reaches no requirement is a
    # warn-only advisory (module_ids reused from the PB back-link check above).
    interface_backlink_findings, interface_advisories = interface_findings(
        ifs, module_ids, docs.parent
    )
    # The depth-0 FRAME's own resolution rules (WI-442): a crossing's Entity and
    # a relationship's From/To must name declared entities, and an IF row's
    # directional tie-back must name a declared crossing. Its own class rather
    # than folded into the interface findings above, because the report reads
    # them out by name and "Interface findings: relationship REL-002 From
    # references unknown EXT-009" would be a label lying about its contents.
    sr_frame, sr_frame_advisories = sr_boundary_findings(srs, bifs, ifs)
    # The SR/LLR -> hats-roster resolution (WI-484 / OI-32 phase 1). It rides the
    # frame bundle rather than a sixth pipe on the same argument the frame rules
    # took: this is a row citing a declared row in a NON-SPINE registry, resolved
    # by existence, and the report reads the bundle out by name. The coverage and
    # unattributed-hat halves are advisories and never gate.
    # The SR/LLR -> hats-roster resolution (WI-484 / OI-32 phase 1). ITS OWN CLASS
    # rather than folded into the frame bundle below, on that bundle's own stated
    # rule: the report reads these lists out by NAME, and "Frame findings: SR-146
    # Hat-Refs references unknown hat SECRUITY" would be a label lying about its
    # contents. The coverage and unattributed-hat halves are advisories and never
    # gate.
    hat_dangling, hat_advisories = hat_findings(
        srs,
        llrs,
        reg.hat_names,
        {r["SR-ID"]: r for r in srs},
        speaks_for=reg.hat_speaks_for,
        stakeholders={r["STK-ID"] for r in reg.stks},
    )
    # An assumption's obstacle perspectives (SR-214) resolve against the same
    # roster, and an undeclared one joins this same class.
    hat_dangling += obstacle_hat_findings(reg.das, reg.hat_names)
    # A crossing's system of interest (SR-187) and a requirement's derived one
    # (SR-219): an out-of-pair value joins the frame class, the rest warn.
    system_failures, system_advisories = frame_system_findings(bifs)
    # The stakeholder list and the needs' references into it (SR-189): an
    # incomplete stakeholder or a dangling reference joins the frame class too.
    stk_failures, stk_advisories = stakeholder_findings(reg.sn_needs, reg.stks, exts)
    frame_backlink_findings = (
        frame_findings(exts, bifs, rels) + tieback_findings(ifs, bifs) + sr_frame
    ) + (system_failures + stk_failures)
    # A recorded mediation (SR-195) resolves like the frame's other references.
    frame_backlink_findings += mediation_findings(exts)
    # The IF/CMP schema tier and the IF `Contract` negative rules (WI-443 / OI-14
    # part B) — ALWAYS ON and ALWAYS WARN. They ride the interface advisory pipe
    # rather than `schema` on purpose: `schema` joins the --strict failure set,
    # and the ruled sequencing is warn-first until the corpus converges. Not
    # gated behind --strict-schema either, because a rule nobody runs is the
    # state this item spent three days measuring the drift of.
    interface_advisories += (
        schema_advisories("IF", ifs)
        + schema_advisories("CMP", cmps)
        + schema_advisories("EXT", exts)
        + schema_advisories("B", bifs)
        + schema_advisories("REL", rels)
        + sr_frame_advisories
        + system_advisories
        + sr_system_advisories(srs, bifs)
        + stk_advisories
        + hat_advisories
        + if_data_advisories(ifs, docs.parent)
        + if_note_advisories(ifs, prov_allow)
        + if_endpoint_class_advisories(ifs, module_ids, docs.parent)
        + if_verified_by_advisories(ifs, {t["TC-ID"] for t in tcs}, llr_ids)
        + if_carriage_advisories(ifs)
    )

    # The delivery filter and the two rules scoped by it. `verification_basis`
    # runs unconditionally (the footprint is always visible); the status
    # criterion is what `--require-verified` turns on.
    scope = PhaseScope.of(srs, flags.phase)
    mechanized_verified, demonstrated_verified, attested_verified = verification_basis(
        srs
    )
    status_findings, phase_deferred = (
        status_criterion_findings(srs, scope) if flags.require_verified else ([], [])
    )

    raw = {"SR": reg.raw_srs, "LLR": reg.raw_llrs, "TC": reg.raw_tcs}
    real = {"SR": srs, "LLR": llrs, "TC": tcs}
    integrity = integrity_sweep(reg, raw)
    tier_frame, tier_integrity, tier_interface, tier_advisories = _assumption_findings(
        reg, srs, tcs, ifs, exts, bifs
    )
    frame_backlink_findings += tier_frame
    integrity += tier_integrity
    interface_backlink_findings += tier_interface
    interface_advisories += tier_advisories
    placeholders = placeholder_sweep(raw, reg.sn_md) if flags.no_placeholders else []
    schema = schema_sweep(real) if flags.strict_schema else []
    # Warn-only, always on: comparative AcceptanceCriteria terms with no pinned
    # predicate (see the module docstring). Never joins a failure set below.
    advisories = ac_advisories(srs)
    # GATING (owner ruling 2026-07-27): a spine row whose text carries its own
    # provenance. Its own pipe, not folded into the AC advisories above — that
    # counter names the acceptance-criteria lint, and a shared count would say
    # "ac-advisories" about a finding that is not one. Joins exit_code.
    provenance = provenance_findings(srs, llrs, tcs)
    # GATING (WI-328): requirement FORM — one `shall` per requirement, no weak
    # modal, no actorless passive, no unfalsifiable term, no open-ended clause, no
    # `shall` in an LLR. Same pipe as provenance: both are "is this row readable
    # and decidable on its own", and splitting them across two counters would make
    # a reader check two places for one answer. Joins exit_code.
    form = form_findings(srs, llrs, tcs)
    # Warn-only, always on: an SR whose opening states a condition outside the
    # EARS patterns (process.md §3, "The statement pattern is EARS"). Its own
    # pipe, like the tiering detectors below — this is a STATEMENT-PATTERN
    # finding, and reporting it under the form counter would say "gating" about
    # a class that never gates. Never joins a failure set below.
    ears = ears_advisories(srs)
    # Warn-only, always on (WI-328): a child cell that re-words its parent. A
    # heuristic (lexical overlap), so it warns FOREVER — 38 of 118 LLRs trip it
    # and most are legitimate. Never joins a failure set below.
    paraphrase = paraphrase_advisories(srs, llrs)
    # Warn-only, always on (re-tier v2 R2/R3, owner ruling 2026-08-15): an SR
    # `Requirement` naming a concrete artifact, and an SR whose direct-LLR fan-out
    # is over the declared bound. Their own pipes — they are TIERING detectors,
    # not prose lints, and folding them into the AC/paraphrase counters would
    # report a tiering defect under a wording heading. Never joins a failure set
    # below: warn-first by ruling, cleared by the re-tier campaign, not by a gate.
    sr_artifact_advis = sr_artifact_advisories(srs)
    # The same rule one tier up (owner directive 2026-08-18): a need's
    # `acceptance` naming the instrument rather than the observable condition.
    # Its own pipe for the same reason — a tiering finding reported under a
    # wording heading is a mis-named finding — and warn-only on the same terms.
    sn_artifact_advis = sn_artifact_advisories(reg.sn_needs)
    # Warn-first, always on (owner ruling: no provenance citation in a living
    # registry cell). The same subject as the gating `provenance` pipe above and
    # deliberately NOT the same counter: that one names two token shapes in three
    # tiers and joins the exit code, this one names the rest of the citation frame
    # across four tiers and never can. One counter for two severities would report
    # "gating" about ~300 findings the harness must not stop for.
    # The off-spine LIVING registries (CMP, EXT) join this SAME list rather than
    # taking a pipe of their own: it is one ruling, one message shape and one
    # worklist, and a second counter would invite a reader to clear the spine and
    # call the ruling discharged. Those two tiers were swept in the same pass and
    # then left unguarded — a clean state nothing was watching.
    provenance_advis = provenance_advisories(
        reg.sn_needs, srs, llrs, tcs, prov_allow
    ) + off_spine_advisories(cmps, exts, prov_allow)
    sr_fanout_advis = sr_fanout_advisories(srs, llrs)
    # Warn-only, always on: a row whose prose names a critique instrument while
    # its Verification says otherwise. Its own pipe for the same reason the two
    # above have theirs — this is a METHOD-coherence finding, not a wording one,
    # and reporting it under the acceptance-criteria counter would mis-name it
    # (it scans Requirement and Rationale too). Never joins a failure set.
    verif_coherence_advis = verification_coherence_advisories(srs)
    # Warn-only, its own pipe (never the ac-advisories counter): open-world
    # absolutes in needs, SRs and LLRs; absolute_terms states the predicate.
    absolute_advis = absolute_advisories(reg.sn_needs, srs, llrs)

    # Drafted artifacts (derived-gate model §3): the rows exempted from the
    # child-completeness orphan rules + the --require-verified criterion. Listed
    # so the exemption stays auditable (the whole point of the model is that a
    # Drafted row lives in the live spine while being drafted, not silently).
    draft_srs = [r for r in srs if is_drafted(r)]
    draft_llrs = [r for r in llrs if is_drafted(r)]
    draft_tcs = [r for r in tcs if is_drafted(r)]
    n_draft = len(draft_srs) + len(draft_llrs) + len(draft_tcs) + len(reg.sn_draft)

    return Findings(
        orphans=orphans,
        orphan_ids=orphan_ids,
        integrity=integrity,
        placeholders=placeholders,
        schema=schema,
        advisories=advisories,
        provenance=provenance,
        form=form,
        paraphrase=paraphrase,
        ears=ears,
        sr_artifact_advis=sr_artifact_advis,
        sn_artifact_advis=sn_artifact_advis,
        provenance_advis=provenance_advis,
        sr_fanout_advis=sr_fanout_advis,
        verif_coherence_advis=verif_coherence_advis,
        absolute_advis=absolute_advis,
        budget_findings=budget_findings,
        module_findings=module_findings,
        component_findings=component_findings,
        knowledge_advisories=knowledge_advisories,
        interface_backlink_findings=interface_backlink_findings,
        frame_backlink_findings=frame_backlink_findings,
        hat_dangling=hat_dangling,
        interface_advisories=interface_advisories,
        status_findings=status_findings,
        phase_deferred=phase_deferred,
        phases=scope.phases,
        mechanized_verified=mechanized_verified,
        demonstrated_verified=demonstrated_verified,
        attested_verified=attested_verified,
        draft_srs=draft_srs,
        draft_llrs=draft_llrs,
        draft_tcs=draft_tcs,
        n_draft=n_draft,
        area_counts=aspect_counts(srs),
    )


def render_report(reg, findings, args, forest):
    """Assemble the full report.md text (the metric table, the SR->LLR->TC matrix, the outline + mermaid views over `forest`, the orphan/integrity/advisory sections, and the flag-gated off-spine/draft/area/status sections). Pure — returns the text; the caller writes it."""
    srs, llrs, tcs = reg.srs, reg.llrs, reg.tcs
    pbs, mods, parts = reg.pbs, reg.mods, reg.parts
    assets, cmps, ifs = reg.assets, reg.cmps, reg.ifs
    exts, bifs, rels = reg.exts, reg.bifs, reg.rels
    sn_ids, sn_draft = reg.sn_ids, reg.sn_draft
    hat_names = reg.hat_names
    hat_dangling = findings.hat_dangling
    orphans = findings.orphans
    orphan_ids = findings.orphan_ids
    integrity = findings.integrity
    placeholders = findings.placeholders
    schema = findings.schema
    advisories = findings.advisories
    provenance = findings.provenance
    form = findings.form
    paraphrase = findings.paraphrase
    ears = findings.ears
    sr_artifact_advis = findings.sr_artifact_advis
    sn_artifact_advis = findings.sn_artifact_advis
    provenance_advis = findings.provenance_advis
    sr_fanout_advis = findings.sr_fanout_advis
    verif_coherence_advis = findings.verif_coherence_advis
    budget_findings = findings.budget_findings
    module_findings = findings.module_findings
    component_findings = findings.component_findings
    knowledge_advisories = findings.knowledge_advisories
    interface_backlink_findings = findings.interface_backlink_findings
    frame_backlink_findings = findings.frame_backlink_findings
    interface_advisories = findings.interface_advisories
    status_findings = findings.status_findings
    phase_deferred = findings.phase_deferred
    phases = findings.phases
    mechanized_verified = findings.mechanized_verified
    demonstrated_verified = findings.demonstrated_verified
    attested_verified = findings.attested_verified
    draft_srs = findings.draft_srs
    draft_llrs = findings.draft_llrs
    draft_tcs = findings.draft_tcs
    n_draft = findings.n_draft
    area_counts = findings.area_counts

    lines = (
        [
            "# Coverage & Traceability Report",
            "",
            "_Generated by `scripts/trace.py`. Do not edit by hand._",
            "",
            "| Metric | Count |",
            "|---|---|",
            f"| Stakeholder needs (SN) | {len(sn_ids)} |",
            f"| System specifications (SR) | {len(srs)} |",
            f"| Design expectations (LLR) | {len(llrs)} |",
            f"| Test cases (TC) | {len(tcs)} |",
        ]
        + evidence_metric_rows(tcs)
        + [
            f"| Orphans | {len(orphans)} |",
            f"| Integrity findings | {len(integrity)} |",
            f"| Approved SRs — mechanized (Test) | {len(mechanized_verified)} |",
            f"| Approved SRs — demonstrated/observed | {len(demonstrated_verified)} |",
            f"| Approved SRs — attested (human, §4) | {len(attested_verified)} |",
        ]
        + (
            [f"| Drafted artifacts (decomposition-exempt) | {n_draft} |"]
            if n_draft
            else []
        )
        + (
            [f"| Status findings | {len(status_findings)} |"]
            if args.require_verified
            else []
        )
        + (
            [f"| Placeholder findings | {len(placeholders)} |"]
            if args.no_placeholders
            else []
        )
        + ([f"| Schema findings | {len(schema)} |"] if args.strict_schema else [])
        + (
            [
                f"| Performance budgets (PB) | {len(pbs)} |",
                f"| Budget findings | {len(budget_findings)} |",
            ]
            if pbs
            else []
        )
        + (
            [
                f"| Delegated repos (REPO) | {len(mods)} |",
                f"| Delegation findings | {len(module_findings)} |",
            ]
            if mods
            else []
        )
        + ([f"| Purchased parts (PART) | {len(parts)} |"] if parts else [])
        + ([f"| Binary assets (ASSET) | {len(assets)} |"] if assets else [])
        + (
            [
                f"| Components (CMP) | {len(cmps)} |",
                f"| Component findings | {len(component_findings)} |",
            ]
            if cmps
            else []
        )
        + (
            [
                f"| Interface seams (IF) | {len(ifs)} |",
                f"| Interface findings | {len(interface_backlink_findings)} |",
            ]
            if ifs
            else []
        )
        + (
            [
                f"| Frame: entities/crossings/relationships | "
                f"{len(exts)}/{len(bifs)}/{len(rels)} |",
                f"| Frame findings | {len(frame_backlink_findings)} |",
            ]
            if exts or bifs or rels
            else []
        )
        + (
            [
                f"| Declared hats | {len(hat_names)} |",
                f"| Hat findings | {len(hat_dangling)} |",
            ]
            # A hat finding is counted even with no roster: an assumption's
            # obstacle perspectives fail then, and a strict failure must not
            # stand without its summary line.
            if hat_names or hat_dangling
            else []
        )
        + [
            "",
            "## SR -> LLR -> TC matrix",
            "",
            "| SR | LLRs | TCs | Status |",
            "|---|---|---|---|",
        ]
    )
    llrs_by_sr = _bucket_by_ref(llrs, "SR-Refs")
    tcs_by_sr = _bucket_by_ref(tcs, "Verifies")
    for r in srs:
        sid = r["SR-ID"]
        kids = " ".join(x["LLR-ID"] for x in llrs_by_sr.get(sid, []))
        tests = " ".join(x["TC-ID"] for x in tcs_by_sr.get(sid, []))
        lines.append(f"| {sid} | {kids} | {tests} | {r.get('Status', '')} |")

    lines += [
        "",
        "## Traceability outline",
        "",
        "_`SN -> SR -> LLR -> TC`; `[Status]` and `[orphan]` flags are inline._",
        "",
    ]
    lines += outline_lines(forest)
    lines += [
        "",
        "## Traceability graph",
        "",
        "_The chain as a DAG, colored by state (orphan/draft stand out). Small and "
        "diff-friendly; run `--html` for the scalable full-graph view._",
        "",
    ]
    lines += mermaid_graph(sn_ids, srs, llrs, tcs, orphan_ids, sn_draft)

    lines += ["", "## Orphans", ""]
    lines += ["None. Full coverage."] if not orphans else [f"- {o}" for o in orphans]
    lines += ["", "## Integrity", ""]
    lines += (
        ["None. Ids are unique and well-formed."]
        if not integrity
        else [f"- {f}" for f in integrity]
    )
    # Warn-only advisory section (never a failure): comparative acceptance-
    # criteria wording that names no predicate. The DevStg-Reqs consistency review
    # (process.md §4) decides — pin the predicate or accept it knowingly.
    lines += ["", "## Acceptance-criteria advisories (warn-only)", ""]
    lines += (
        ["None. No unpinned comparative terms."]
        if not advisories
        else [f"- {f}" for f in advisories]
    )
    # GATING section: a spine row states the system, not its own history. Failing
    # under --strict rather than warning, because a warn nobody must act on is how
    # 43 rows accumulated before anyone looked below the SR layer.
    lines += ["", "## Spine stand-alone findings (gating under --strict)", ""]
    lines += (
        ["None. No spine row cites a work item or a process doc in its text."]
        if not provenance
        else [f"- {f}" for f in provenance]
    )
    # GATING section (WI-328): requirement form — one testable obligation per row.
    lines += ["", "## Requirement form findings (gating under --strict)", ""]
    lines += (
        ["None. Every requirement states one obligation in decidable terms."]
        if not form
        else [f"- {f}" for f in form]
    )
    # Warn-only section: an SR opening on a condition outside the EARS patterns.
    lines += ["", "## EARS statement-pattern advisories (warn-only)", ""]
    lines += (
        ["None. Every requirement opens on its subject or an EARS keyword."]
        if not ears
        else [f"- {f}" for f in ears]
    )
    # Warn-only section: a child cell re-wording its parent. Heuristic, never gates.
    lines += ["", "## Paraphrase advisories (warn-only heuristic)", ""]
    lines += (
        ["None flagged by the overlap heuristic."]
        if not paraphrase
        else [f"- {f}" for f in paraphrase]
    )
    # Warn-only sections (re-tier v2 R2/R3): the two tiering detectors. Never a
    # failure under any flag — a merged row and a mis-tiered artifact name are
    # cleared by re-writing requirements, which is the campaign's schedule, not
    # the checker's.
    lines += ["", "## Artifact-naming advisories (warn-only)", ""]
    lines += (
        ["None. No requirement cell names a concrete artifact."]
        if not sr_artifact_advis
        else [f"- {f}" for f in sr_artifact_advis]
    )
    lines += ["", "## Need artifact-naming advisories (warn-only)", ""]
    lines += (
        ["None. No need's acceptance names a concrete artifact."]
        if not sn_artifact_advis
        else [f"- {f}" for f in sn_artifact_advis]
    )
    # Warn-first by ruling and never a gate: this is a prose-rewriting WORKLIST
    # over the live registries, and the rewrite it asks for is a judgement (drop
    # the frame, keep or restate the reason) that no checker can make.
    lines += ["", "## Provenance-citation advisories (warn-only)", ""]
    lines += (
        ["None. No living spine cell carries a citation frame."]
        if not provenance_advis
        else [f"- {f}" for f in provenance_advis]
    )
    lines += ["", "## Verification-coherence advisories (warn-only)", ""]
    lines += (
        ["None. No requirement states two verification methods."]
        if not verif_coherence_advis
        else [f"- {f}" for f in verif_coherence_advis]
    )
    lines += absolute_report_lines(findings.absolute_advis)
    lines += ["", "## Fan-out advisories (warn-only)", ""]
    lines += (
        ["None. No SR's direct-LLR fan-out exceeds the declared bound."]
        if not sr_fanout_advis
        else [f"- {f}" for f in sr_fanout_advis]
    )
    # Verification-basis surface (process.md §4): make the project's trust
    # footprint auditable — of what is `Approved`, how much rests on a runnable
    # check (Test), on a human observing an outcome (Demonstration/Manual/Analysis/
    # Inspection/Critique), or on a named human's recorded judgment (Attest)? Split
    # three ways (WI-259) so non-Test approval claims are never folded into
    # "mechanized"; the demonstrated and attested ids are listed so an audit can
    # see exactly which rows rest on something other than a runnable check.
    lines += ["", "## Verification basis (mechanized / demonstrated / attested)", ""]
    lines += [
        "_Of the SRs reported `Approved`: `Test` rows rest on a runnable, "
        "re-executable check (mechanized); `Demonstration`/`Manual`/`Analysis`/"
        "`Inspection`/`Critique` rows rest on a human observing an outcome "
        "(demonstrated/observed — repeatable, but not a runnable check); `Attest` "
        "rows rest on a named human's recorded judgment (trust-based — the box can "
        "be checked without the work having happened, process.md §4). Only the "
        "first is a runnable check. A row whose method is blank or unrecognized is "
        "counted as demonstrated/observed, never as mechanized (the conservative "
        "default — it does not rest on a runnable check unless proven so)._",
        "",
        f"- Mechanized (Test): {len(mechanized_verified)}",
        "- Demonstrated/observed (Demonstration/Manual/Analysis/Inspection/"
        f"Critique, or unspecified): {len(demonstrated_verified)}"
        + (f" — {', '.join(demonstrated_verified)}" if demonstrated_verified else ""),
        f"- Attested (Attest): {len(attested_verified)}"
        + (f" — {', '.join(attested_verified)}" if attested_verified else ""),
    ]
    if n_draft:
        lines += ["", "## Drafted artifacts (decomposition-exempt)", ""]
        lines += [
            "_`Drafted` rows are exempt from the child-completeness orphan rules and "
            "the DevStg-Impl approval criterion (derived-gate model §3): a requirement lives "
            "in the live spine while it is drafted. Listed so the exemption is "
            "auditable._",
            "",
        ]
        lines += [f"- {u} (SN, unapproved section)" for u in sorted(sn_draft)]
        lines += [
            f"- {r[id_key(label)]} — {_cell(r, 'Title') or _cell(r, 'Method')}"
            for label, rows_ in (
                ("SR", draft_srs),
                ("LLR", draft_llrs),
                ("TC", draft_tcs),
            )
            for r in rows_
        ]
    if area_counts:
        untagged = len(srs) - sum(area_counts.values())
        lines += [
            "",
            "## SRs by aspect (report-only)",
            "",
            "_The ruled cross-cutting review grouping. Counts only — never a "
            "gate; a row carrying no aspect is simply not cross-cutting, which "
            "is normal rather than a gap._",
            "",
        ]
        lines += [f"- {a}: {n}" for a, n in sorted(area_counts.items())]
        if untagged:
            lines.append(f"- (no aspect): {untagged}")
    if pbs:
        lines += ["", "## Performance budgets (§9 back-links)", ""]
        lines += (
            [f"{len(pbs)} budget row(s); every Refs resolves to a real SR/LLR/Module."]
            if not budget_findings
            else [f"- {f}" for f in budget_findings]
        )
    if mods:
        lines += ["", "## Delegated repos (MULTI_REPO.md delegation back-links)", ""]
        lines += (
            [
                f"{len(mods)} delegated-repo row(s); every DelegatedSRs resolves "
                "to a real SR."
            ]
            if not module_findings
            else [f"- {f}" for f in module_findings]
        )
    if parts:
        lines += ["", "## Purchased parts (process-options.md)", ""]
        lines += [
            f"{len(parts)} part row(s); each IF-Ref names its owning interface row "
            "of record (MULTI_REPO.md §3.3), integrity-checked only."
        ]
    if assets:
        lines += ["", "## Binary assets (process-options.md)", ""]
        lines += [
            f"{len(assets)} asset row(s); provenance/license/hash tracked in text "
            "(the ideal-not-requirement stance), integrity-checked only."
        ]
    if cmps:
        lines += ["", "## Components (process-options.md component layer)", ""]
        lines += (
            [
                f"{len(cmps)} component row(s); PartOf/SupersededBy resolve and "
                "every primitive `Component` tag names a real CMP row."
            ]
            if not component_findings
            else [f"- {f}" for f in component_findings]
        )
        if knowledge_advisories:
            lines += ["", "### Knowledge-pack advisories (warn-only)", ""]
            lines += [f"- {a}" for a in knowledge_advisories]
    if ifs:
        lines += ["", "## Interface seams (process.md §8)", ""]
        lines += (
            [f"{len(ifs)} interface-seam row(s); every Owner is one providing thing."]
            if not interface_backlink_findings
            else [f"- {f}" for f in interface_backlink_findings]
        )
        if interface_advisories:
            lines += ["", "### Interface endpoint advisories (warn-only)", ""]
            lines += [f"- {a}" for a in interface_advisories]
    lines += _frame_report_section(exts, bifs, rels, frame_backlink_findings)
    lines += _hat_report_section(hat_names, hat_dangling)
    if args.no_placeholders:
        lines += ["", "## Placeholders (--no-placeholders)", ""]
        lines += (
            ["None. No '-000' template rows remain."]
            if not placeholders
            else [f"- {f}" for f in placeholders]
        )
    if args.strict_schema:
        lines += ["", "## Schema findings (--strict-schema)", ""]
        lines += (
            ["None. Required fields present; Verification/Tier in vocabulary."]
            if not schema
            else [f"- {f}" for f in schema]
        )
    if args.require_verified:
        scope = f" — phase scope: {args.phase}" if phases else ""
        lines += ["", f"## Status findings (--require-verified{scope})", ""]
        lines += (
            ["None. Every in-scope approved SR is Approved (any method)."]
            if not status_findings
            else [f"- {s}" for s in status_findings]
        )
        if phase_deferred:
            lines += ["", "### Phase-deferred (explicitly out of scope)", ""]
            lines += [f"- {s}" for s in phase_deferred]
    return "\n".join(lines) + "\n"


def render_console(reg, findings, args, out, html_out):
    """Print the warn-only advisory lines and the one-line Traceability summary to stdout (loud but never gating)."""
    sn_ids = reg.sn_ids
    srs, llrs, tcs = reg.srs, reg.llrs, reg.tcs
    pbs, mods, parts = reg.pbs, reg.mods, reg.parts
    assets, cmps, ifs = reg.assets, reg.cmps, reg.ifs
    orphans = findings.orphans
    integrity = findings.integrity
    advisories = findings.advisories
    provenance = findings.provenance
    form = findings.form
    paraphrase = findings.paraphrase
    ears = findings.ears
    interface_advisories = findings.interface_advisories
    knowledge_advisories = findings.knowledge_advisories
    sr_artifact_advis = findings.sr_artifact_advis
    sn_artifact_advis = findings.sn_artifact_advis
    provenance_advis = findings.provenance_advis
    sr_fanout_advis = findings.sr_fanout_advis
    verif_coherence_advis = findings.verif_coherence_advis
    watermark_advis = findings.watermark_advisories
    snapshot_findings = findings.snapshot_findings
    mechanized_verified = findings.mechanized_verified
    demonstrated_verified = findings.demonstrated_verified
    attested_verified = findings.attested_verified
    status_findings = findings.status_findings
    n_draft = findings.n_draft
    placeholders = findings.placeholders
    schema = findings.schema
    phases = findings.phases
    phase_deferred = findings.phase_deferred
    budget_findings = findings.budget_findings
    module_findings = findings.module_findings
    component_findings = findings.component_findings
    interface_backlink_findings = findings.interface_backlink_findings
    frame_backlink_findings = findings.frame_backlink_findings
    hat_dangling = findings.hat_dangling

    # Advisories are loud (stdout, not just the report) but never fail the run.
    # One loop over the ordered concatenation, not one loop per pipe: the pipes
    # stay separate where it matters (their own report sections and counters) and
    # a fifth lint no longer costs this routine a branch.
    for a in (
        advisories
        + interface_advisories
        + knowledge_advisories
        + paraphrase
        + ears
        + sr_artifact_advis
        + sn_artifact_advis
        + provenance_advis
        + sr_fanout_advis
        + verif_coherence_advis
        + absolute_summary(findings.absolute_advis)
        + watermark_advis
        + findings.retired_advisories
    ):
        print(f"WARNING (advisory): {a}")
    # ARMED AT MIGRATION STEP 7: the UNANCHORED rule left the advisory loop above
    # and joined the INTEGRITY class (snapshot design §B4), so it prints as a
    # finding and `exit_code` gates on it through `findings.integrity`. It kept
    # its own loop rather than folding into the integrity cap below because the
    # message only makes sense under its own name — "approved with no copy
    # recording it" is a claim about the RECORD, not about a malformed row.
    for f in snapshot_findings:
        print(f"FINDING (approval record): {f}")
    for f in provenance:
        print(f"FINDING (spine stand-alone): {f}")
    for f in form:
        print(f"FINDING (requirement form): {f}")
    # Gating findings print here too, not only as counts: the report file is
    # gitignored, and the harness bar is "print the real output — never
    # summarize a failure away" (check.py). Mirrors exit_code()'s composition;
    # capped per class, the report holds the full lists.
    cap = 10
    if args.strict:
        failing = [
            ("orphan", orphans),
            ("integrity", integrity),
            ("status", status_findings),
            ("placeholder", placeholders),
            ("schema", schema),
            ("budget", budget_findings),
            ("delegation", module_findings),
            ("component", component_findings),
            ("interface", interface_backlink_findings),
            ("frame", frame_backlink_findings),
            ("hat", hat_dangling),
        ]
    elif args.strict_integrity:
        failing = [("integrity", integrity)]
    else:
        failing = []
    for label, items in failing:
        for f in items[:cap]:
            print(f"FINDING ({label}): {f}")
        if len(items) > cap:
            print(f"... +{len(items) - cap} more {label} finding(s) in the report")
    print(
        f"Traceability: SN={len(sn_ids)} SR={len(srs)} LLR={len(llrs)} "
        f"TC={len(tcs)} orphans={len(orphans)} integrity={len(integrity)}"
        + (
            f" verified-mechanized={len(mechanized_verified)}"
            f" verified-demonstrated={len(demonstrated_verified)}"
            f" verified-attested={len(attested_verified)}"
            # WI-466: the guard used to read `(demonstrated_verified or
            # attested_verified)`, so a nonzero mechanized-only count (the
            # common case) silently dropped the whole triple the moment the
            # other two legs drained to zero (re-tier v2 S3, log
            # 2026-08-16e). Any nonzero leg now prints all three.
            if (mechanized_verified or demonstrated_verified or attested_verified)
            else ""
        )
        + (f" status-findings={len(status_findings)}" if args.require_verified else "")
        + (f" drafts={n_draft}" if n_draft else "")
        + (f" placeholders={len(placeholders)}" if args.no_placeholders else "")
        + (f" schema-findings={len(schema)}" if args.strict_schema else "")
        + (f" phase-deferred={len(phase_deferred)}" if phases else "")
        + (f" budgets={len(pbs)} budget-findings={len(budget_findings)}" if pbs else "")
        + (
            f" repos={len(mods)} delegation-findings={len(module_findings)}"
            if mods
            else ""
        )
        + (f" parts={len(parts)}" if parts else "")
        + (f" assets={len(assets)}" if assets else "")
        + (
            f" components={len(cmps)} component-findings={len(component_findings)}"
            if cmps
            else ""
        )
        + (
            f" knowledge-advisories={len(knowledge_advisories)}"
            if knowledge_advisories
            else ""
        )
        + (
            f" interfaces={len(ifs)} "
            f"interface-findings={len(interface_backlink_findings)}"
            if ifs
            else ""
        )
        + (f" ac-advisories={len(advisories)}" if advisories else "")
        + (f" provenance-findings={len(provenance)}" if provenance else "")
        + (f" form-findings={len(form)}" if form else "")
        + (f" ears-advisories={len(ears)}" if ears else "")
        + (f" paraphrase-advisories={len(paraphrase)}" if paraphrase else "")
        + (f" watermark-advisories={len(watermark_advis)}" if watermark_advis else "")
        + (f" approval-record={len(snapshot_findings)}" if snapshot_findings else "")
        + f". Report -> {out}"
        + (f" + {html_out}" if html_out else "")
    )


def exit_code(findings, args):
    """The gate exit code: 1 under --strict if any orphan/status/integrity/placeholder/schema/off-spine finding exists; 1 under --strict-integrity if any integrity finding exists; else 0."""
    if args.strict and (
        findings.orphans
        or findings.status_findings
        or findings.integrity
        or findings.placeholders
        or findings.schema
        or findings.budget_findings
        or findings.module_findings
        or findings.component_findings
        or findings.interface_backlink_findings
        or findings.frame_backlink_findings
        or findings.hat_dangling
        or findings.provenance
        or findings.form
    ):
        return 1
    if args.strict_integrity and findings.integrity:
        return 1
    return 0


def _cmd_tests_for(docs, wanted):
    """`--tests-for MODULE` (IF-233): the test files the spine links to a
    module, for a builder's inner loop.

    Matching file names (`test_<module>`) finds a fraction of a module's tests:
    its cases are named for the behaviour they drive, and a driven suite for the
    script it runs. The spine already records the link, so this reads it
    through `kitlib.spine.module_tests` and keeps no second map. Everything is
    read from `docs`, the directory `--docs` resolves to, the declared test
    root included (`stack.ini` `[paths] tests`, default `tests`).

    Implements: SR-221, LLR-263
    """
    llr_path = docs / "requirements" / "low-level-requirements.toml"
    llrs = spine_carrier.load(llr_path, "LLR-ID", keep_examples=False)
    matched = _spine.resolve_modules(llrs, wanted)
    if len(matched) != 1:
        why = "; ".join(matched) or "no module a design row declares"
        print("trace: --tests-for {!r} names {}".format(wanted, why), file=sys.stderr)
        return 2 if matched else 1
    tcs = spine_carrier.load(docs / "test" / "test-cases.toml", "TC-ID")
    cp = read_stack_ini(docs / "stack.ini")  # an unreadable profile raises
    declared = cp.get("paths", "tests", fallback="") if cp is not None else ""
    test_root = declared.strip() or "tests"
    for path in _spine.module_tests(llrs, tcs, matched[0], test_root):
        print(path)
    return 0


def _cmd_bump_ids(root):
    """`--bump-ids`: raise every mark to the live maximum and report what moved."""
    marks, raised = bump_watermark(root)
    for space, (was, now) in sorted(raised.items()):
        print("trace: id watermark {} {} -> {}".format(space, was, now))
    print(
        "trace: id watermark written -> {} ({} space(s), {} raised)".format(
            WATERMARK, len(marks), len(raised)
        )
    )
    return 0


def _cmd_correct_mark(root, space, new_value_text, ruling_id):
    """`--correct-mark SPACE NEW RULING`: the one-shot recorded-correction verb
    (OI-47 (e)). A WRITER, like `--bump-ids` — exits before any check runs."""
    space = space.strip().upper()
    try:
        new_value = int(new_value_text)
    except ValueError:
        print(
            "trace: --correct-mark NEW must be an integer, got {!r}".format(
                new_value_text
            ),
            file=sys.stderr,
        )
        return 2
    try:
        correct_watermark(root, space, new_value, ruling_id)
    except ValueError as exc:
        print("trace: {}".format(exc), file=sys.stderr)
        return 1
    print(
        "trace: id watermark {} corrected -> {} (recorded, authorized by {})".format(
            space, new_value, ruling_id
        )
    )
    return 0


def _cmd_reserve_ids(root, wi, counts):
    """`--reserve-ids`'s CLI body: one line per reserved range, or one refusal
    line and exit 1 with nothing written.

    Implements: SR-174, LLR-362
    """
    try:
        ranges = reserve_ids(root, wi, counts)
    except id_carrier.Refused as exc:
        print("trace: --reserve-ids refused: {}".format(exc), file=sys.stderr)
        return 1
    for record in ranges:
        print("trace: reserved {}".format(id_carrier.record_line(record)[2:]))
    print("trace: folded into {}; commit it with the rows".format(WATERMARK))
    return 0


def _cmd_fold_ids(root):
    """`--fold-ids`'s CLI body.

    Implements: SR-174, LLR-362
    """
    try:
        fold_watermark(root)
    except id_carrier.Refused as exc:
        print("trace: --fold-ids refused: {}".format(exc), file=sys.stderr)
        return 1
    print("trace: id carrier folded into {}".format(WATERMARK))
    return 0


def mint_approval_brief(root, slug, date=None):
    """`--mint-approval-brief SLUG` (WI-503): copy `docs/ratify/CURRENT.md` to a
    dated, IMMUTABLE `docs/ratify/<date>-<slug>.md` — the one act the
    immutability enforcer (`check.py --approval-immutable`) ever permits,
    because it only ever CREATES a fresh filename; it never rewrites one that
    already exists. Home chosen here rather than a new script or a
    intake.py flag: the mint is a plain file copy over machinery trace.py
    already owns (`current_approval_brief`, the CURRENT.md path), so this is
    the smallest-total-code seam — a sibling script would duplicate that path
    knowledge, and intake.py's writers are all registry-shaped, not a byte
    copy of a rendered view.

    `date` is a testability seam (ISO `YYYY-MM-DD`); the CLI leaves it None,
    which defaults to today.

    Returns the minted `Path`. Raises `ValueError` on every refusal — no
    `CURRENT.md` to mint from, a slug that is empty or carries a character
    other than `[A-Za-z0-9-]`, or a destination that already exists (minting
    twice at the same date+slug would be exactly the in-place rewrite this
    split exists to stop)."""
    slug = (slug or "").strip()
    if not slug or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]*", slug):
        raise ValueError(
            "trace: --mint-approval-brief SLUG must be non-empty and contain "
            "only letters, digits and '-', got {!r}".format(slug)
        )
    root = Path(root)
    current = current_approval_brief(root)
    if current is None:
        raise ValueError(
            "trace: no docs/ratify/{} to mint from — regenerate it first "
            "with `trace.py --approve modified --out docs/ratify/{}`".format(
                CURRENT_APPROVAL_BRIEF, CURRENT_APPROVAL_BRIEF
            )
        )
    stamp = date or datetime.date.today().isoformat()
    dest = root / "docs" / "ratify" / "{}-{}.md".format(stamp, slug)
    if dest.exists():
        raise ValueError(
            "trace: {} already exists — a dated brief is IMMUTABLE once "
            "minted; choose a different slug or wait for the date to roll "
            "over".format(dest)
        )
    dest.write_bytes(current.read_bytes())
    return dest


def _cmd_mint_approval_brief(root, slug, date):
    """`--mint-approval-brief`'s CLI body: report and exit rather than raise, the
    same shape `_cmd_correct_mark` uses."""
    try:
        dest = mint_approval_brief(root, slug, date)
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    print("trace: minted re-attestation brief -> {}".format(dest))
    return 0


def _writer_mode(args, docs):
    """`None` when no act-and-exit flag is set, else the exit code of the one
    that is: the writer arms, and the `--tests-for` listing, which writes
    nothing but likewise runs no checks. Split out of `main()` so the
    mutually-exclusive early-return branches cost that function ONE call, not
    one `if` each — the same reason `resolve_plan` left `check.py`'s `main` in
    the WI-473 entry below."""
    if args.bump_ids:
        return _cmd_bump_ids(args.root)
    if args.reserve_ids:
        return _cmd_reserve_ids(args.root, *args.reserve_ids)
    if args.fold_ids:
        return _cmd_fold_ids(args.root)
    if args.correct_mark:
        return _cmd_correct_mark(args.root, *args.correct_mark)
    if args.mint_approval_brief:
        return _cmd_mint_approval_brief(
            args.root, args.mint_approval_brief, args.mint_date
        )
    if args.tests_for:
        return _cmd_tests_for(docs, args.tests_for)
    return None


# Implements: SR-157, LLR-001
def main():
    _utf8_console()
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--strict", action="store_true", help="exit 1 if any orphan / status finding"
    )
    ap.add_argument(
        "--bump-ids",
        action="store_true",
        help="raise every id-watermark mark to the live maximum and exit — the "
        "regeneration workflow for docs/id-watermark (a mark only ever rises)",
    )
    ap.add_argument(
        "--reserve-ids",
        nargs=2,
        metavar=("WI", "COUNTS"),
        default=None,
        help="reserve spine and off-spine registry ids for the claimed work "
        "item WI on the shared id carrier (COUNTS: SPACE=N[,SPACE=N...], N 1 "
        "to 50; WI, OI and DP are minted on trunk), then fold the carrier into "
        "docs/id-watermark for the caller to commit, and exit",
    )
    ap.add_argument(
        "--fold-ids",
        action="store_true",
        help="fold the id carrier into docs/id-watermark (both sides of a "
        "conflicted file included) and exit",
    )
    ap.add_argument(
        "--correct-mark",
        nargs=3,
        metavar=("SPACE", "NEW", "RULING"),
        default=None,
        help="one-shot RULED raise of a single id-watermark mark to NEW, "
        "recording RULING (e.g. OI-47) in the header — the only other way a "
        "mark may rise besides allocation (OI-47 (e)); refuses to replay a "
        "space that already carries a recorded correction",
    )
    ap.add_argument(
        "--mint-approval-brief",
        metavar="SLUG",
        default=None,
        help="WI-503: copy docs/ratify/CURRENT.md to a dated, IMMUTABLE "
        "docs/ratify/<date>-SLUG.md and exit — the only sanctioned writer of "
        "a dated brief (check.py --approval-immutable refuses any OTHER commit "
        "that modifies one). Refuses when CURRENT.md is absent or the "
        "destination already exists; --mint-date overrides today's date",
    )
    ap.add_argument(
        "--mint-date",
        metavar="YYYY-MM-DD",
        default=None,
        help="with --mint-approval-brief: use this date instead of today (testing/"
        "backfill; the mint itself does not validate the calendar)",
    )
    ap.add_argument(
        "--strict-integrity",
        action="store_true",
        help="exit 1 only on integrity findings (duplicate/malformed ids) — the "
        "always-valid floor the pre-commit hook runs; orphans stay gate-scoped",
    )
    ap.add_argument(
        "--require-verified",
        action="store_true",
        help="DevStg-Impl criterion: flag non-Drafted SRs not Status=Approved "
        "(any Verification method)",
    )
    ap.add_argument(
        "--phase",
        default=None,
        help="comma-separated phases in scope (e.g. v1 or v1,v2): scopes "
        "--require-verified to SRs whose Phase is blank or listed",
    )
    ap.add_argument(
        "--no-placeholders",
        action="store_true",
        help="flag any leftover '-000' template example row (use from DevStg-Tests on)",
    )
    ap.add_argument(
        "--strict-schema",
        action="store_true",
        help="also require non-empty required fields and valid "
        "Verification/Tier values on the real rows",
    )
    ap.add_argument(
        "--html",
        action="store_true",
        help="also write test/report.html — a dependency-free collapsible tree "
        "of the full graph (gitignored composite artifact)",
    )
    ap.add_argument(
        "--approve",
        metavar="SCOPE",
        default=None,
        help="emit ONLY the batch-scoped approval hierarchy (SN->SR->LLR->TC "
        "with prose) for SCOPE — a phase tag (e.g. v3) or an SR-id list "
        "(e.g. 'SR-052,SR-053'); a DevStg-Reqs/DevStg-Tests brief links this instead of hand-copying "
        "rows (WI-146). The reserved scope 'modified' (WI-316) emits the "
        "RE-ATTESTATION brief instead: per-cell before/after for every row owing "
        "a human act, against its copy in docs/archive/last_approved/. The "
        "reserved scope 'assumptions', or a DA-/SUR-id list, emits the "
        "assumption section: each assumption or surrogate owing an approval, "
        "or each one named, with the requirements citing it first. A scope "
        "matching nothing is REFUSED, never rendered empty. Prints to stdout "
        "unless --out is given; runs no checks",
    )
    ap.add_argument(
        "--check",
        action="store_true",
        help="with --approve modified: FRESHNESS mode. Re-render the brief and "
        "compare it against the committed file (--out, else "
        "docs/ratify/CURRENT.md), exiting nonzero when they differ. A plain "
        "regenerate-and-compare — the baseline is a directory of files, so "
        "there is nothing a re-render could move (WI-325's blocker dissolved "
        "with the git-derived baseline). Silent no-op when there is no brief, "
        "or when no row owes an act (the window is closed and the brief is a "
        "record, not a live surface)",
    )
    ap.add_argument(
        "--out",
        metavar="FILE",
        default=None,
        help="with --approve, write the view to FILE (parent dirs created) instead "
        "of stdout, so a brief can link a stable path",
    )
    ap.add_argument(
        "--tests-for",
        metavar="MODULE",
        default=None,
        help="print the test files the spine links to MODULE (a module path, a "
        "trailing part of one, or a stem) and exit; runs no checks",
    )
    # --root/--docs path flags: here and in check_perf.py an explicit --docs is
    # a PATH used as-is (--root ignored); check_docs.py instead treats --docs as
    # a name joined under --root (absolute paths still win via pathlib join).
    # The three agree for the default and for absolute --docs; they differ for a
    # relative explicit --docs — state it rather than claim a uniformity that
    # isn't there (repo-review 2026-07-21 L-1; full unification is a
    # coordinated change across check_flows/gen_release_checklist too).
    ap.add_argument("--root", default=".", help="repo root (default: .)")
    ap.add_argument(
        "--docs",
        default=None,
        help="docs directory path, used as-is (default: <root>/docs)",
    )
    args = ap.parse_args()
    docs = Path(args.docs) if args.docs else Path(args.root) / "docs"

    # --bump-ids, --correct-mark and --mint-approval-brief are WRITERS, not
    # checkers: they act and exit before any pass runs, so none depends on the
    # tree already being clean.
    # Folded into one call rather than two `if`s at this level, which is
    # main()'s own complexity ceiling (`resolve_plan`/`floor_notice`'s WI-473
    # precedent: lift a branch OUT rather than let a dispatcher grow past it).
    writer_code = _writer_mode(args, docs)
    if writer_code is not None:
        # `main()` is called bare at the bottom of this module (like the
        # --approve --check path above), so a plain `return` sets no process
        # exit status — a WRITER's failure (e.g. --mint-approval-brief refusing
        # a bad slug) must `sys.exit` or the CLI reports success regardless.
        sys.exit(writer_code)

    reg = load_registries(docs)

    # --approve is a generator mode, not a checker: emit the batch-scoped
    # approval hierarchy and exit 0 without running any orphan/integrity pass
    # (WI-146a). It reuses the loaded, example-filtered working sets above.
    # A RESERVED scope (`_RESERVED_APPROVAL_SCOPES` — `modified` today) emits the
    # re-attestation brief instead: per-cell before/after for every row owing a
    # human act, against its copy in the `last_approved` snapshot. Anything else
    # is a phase tag or an id list, and `_scope_srs` REFUSES one that matches
    # nothing rather than rendering an empty brief.
    if args.approve is not None:
        reserved = args.approve.strip().lower() in _RESERVED_APPROVAL_SCOPES
        if reserved and args.check:
            # WI-325: freshness, not generation. A plain regenerate-and-compare
            # now that the baseline is a directory rather than a self-stamp.
            code, message = approval_check(
                Path(args.root),
                reg.srs,
                reg.llrs,
                reg.tcs,
                Path(args.out)
                if args.out
                else (
                    current_approval_brief(Path(args.root))
                    or Path(args.root) / "docs" / "ratify" / CURRENT_APPROVAL_BRIEF
                ),
            )
            print("trace: approval-check — {}".format(message), file=sys.stderr)
            # `main()` is called bare at the bottom of this module, so a plain
            # `return` sets no exit status — this check must sys.exit like the
            # analyze path does, or it reports STALE and exits 0. (It did.)
            if code:
                sys.exit(code)
            return 0
        body = _approval_body(args.approve, reserved, Path(args.root), reg)
        text = "\n".join(body) + "\n"
        if args.out:
            out_path = Path(args.out)
            out_path.parent.mkdir(parents=True, exist_ok=True)
            out_path.write_text(text, encoding="utf-8", newline="\n")
            print("trace: wrote approval view -> {}".format(out_path))
        else:
            sys.stdout.write(text)
        return 0

    findings = analyze(reg, args)
    # A need's source pointers (SR-190): the documents they name are read HERE,
    # once each, because analyze() reads no file; the rule itself is pure.
    findings.frame_backlink_findings += need_source_findings(
        reg.sn_needs, need_source_anchors(docs.parent, reg.sn_needs)
    )
    # The observation records and what they can falsify (SR-199, SR-201,
    # SR-202): the records and acts are read here, once, for the same reason; a
    # malformed or out-of-policy record joins the integrity floor, the rest the
    # warn pipe.
    # With the assumption gate on, a falsified assumption fails through the
    # gate's boundary step instead of riding the worklist too (SR-201).
    inputs = record_observation.evidence_inputs(docs.parent, reg.das, reg.bifs)
    gate = assumption_gate_enabled(docs)
    observed, observed_advisories = observation_evidence_findings(
        reg.srs, reg.das, reg.tcs, reg.sn_needs, reg.bifs, gate=gate, **inputs
    )
    findings.integrity += observed
    findings.interface_advisories += observed_advisories
    # The id-watermark rules read the FILESYSTEM and GIT, so they cannot live in
    # analyze() — that function's contract is "Pure … No I/O", and the whole
    # value of the contract is that it stays true. Integrity-class all the same:
    # appended here so --strict-integrity (the always-on pre-commit floor) gates
    # on it exactly like a duplicated id.
    # Follow --docs. `WATERMARK` is docs-relative, so a run pointed at another
    # docs tree must read THAT tree's mark; using args.root regardless would
    # check an unrelated (often empty) tree and then report integrity=0 about a
    # spine it never looked at.
    wm_root = docs.parent if args.docs else Path(args.root)
    committed = committed_watermark(wm_root)
    findings.integrity += watermark_findings(
        wm_root,
        committed,
        committed_corrections(wm_root),
        committed_reservations(wm_root),
    )
    # ARM 1 of OI-41, for the same reason and on the same floor: the allow file
    # and the open-items registry are FILES, so the rule cannot live in the pure
    # pass either. `docs.parent` — the root `load_provenance_allow` already read
    # the entries from, so the file that is CHECKED is the file that SUPPRESSES.
    # TWO PRODUCERS OVER ONE FILE: the FIELD rule (every entry names a row that
    # resolves) and the PARSE rule (every declaring line is readable). The second
    # is not pedantry — a line the grammar drops still reads as a live exception
    # to a human while counting as none, which is precisely how the vacuity arm
    # was made to print an all-clear over a surface that still deferred.
    findings.integrity += provenance_allow_findings(
        parse_provenance_allow(docs.parent), open_item_states(docs.parent)
    ) + provenance_allow_parse_findings(docs.parent)
    if committed is None:
        # SILENCE IS NOT SUCCESS. "A mark only ever rises" cannot be read from the
        # working tree — a lowered mark looks exactly like a correct one — so with
        # no committed baseline the rule did not run. Say so: an unrun rule that
        # prints nothing is indistinguishable from one that passed.
        # ITS OWN PIPE, for the reason stated where `advisories` is built:
        # that counter names the acceptance-criteria lint, and folding an
        # unrelated notice into it reports "ac-advisories=1" about a row whose
        # AcceptanceCriteria is fine — which is exactly what it did until now.
        findings.watermark_advisories.append(
            "id-watermark monotonicity NOT checked — no committed {} to compare "
            "against (first commit, shallow clone, or off a work tree); the "
            "live-id and complete-space rules still ran".format(WATERMARK)
        )
    # THE APPROVAL-RECORD RULES — **ARMED AS INTEGRITY ERRORS AT MIGRATION STEP
    # 7**, the successor to repo-lock D-9's "Approved-with-no-anchor is an ERROR".
    # UNANCHORED (design §B4): a row whose live maturity claims approval-or-above
    # with no copy in `docs/archive/last_approved/` recording it — or a copy that
    # reads below it — is an approval that never rode a copy. THE MIRROR
    # INVARIANT (§F3 risk 3, which asks for exactly this pair of severities:
    # *"warn at the staged hook, ERROR on the integrity floor"*): a snapshot file
    # that is not byte-identical to its live counterpart in the same commit. The
    # staged warn is unchanged and still fires in `check_trajectory --staged`;
    # what is new is that it no longer prints past a `|| true`.
    #
    # ONE PIPE because they are one property read from two directions — "every
    # approval rode a copy" and "every copy is a copy". Split, a reader has to
    # hold both to know whether the record can be trusted.
    #
    # THE ARMING ORDER WAS THE POINT: these ran warn-first from step 4, because
    # against a pre-seed snapshot (there was none) or a pre-rename one (it spoke
    # the retired vocabulary) they would have redded every row, and a check that
    # reds everything gets switched off. The signing seeded the snapshot in the
    # post-rename vocabulary (step 6); only then was the promotion a one-line
    # change to rules already proven quiet.
    #
    # INTEGRITY, NEVER SCHEMA (correction C1): `--strict-schema` runs at
    # DevStg-Impl alone, so a laundering rule routed there would be inert for
    # every repo below the top bar. Still VACUOUS BY ABSENCE for a repo that has
    # approved nothing, and off git. `wm_root` rather than `args.root`, for the
    # reason stated just above it.
    #
    # THREE PRODUCERS SINCE 2026-08-20, not two: the staged mirror answers for
    # the commit being made, and `committed_snapshot_findings` answers for the
    # commits already made. The gap between them was a working laundering step —
    # a forged copy committed with the hook bypassed was seen once, in a run
    # nobody had to make, and never again. Same pipe, because it is still one
    # property: every approval rode a copy, and every copy is a copy. The
    # record's own producer also reports a malformed act ledger (WI-632).
    # The retirement records (SR-226): a spent id with none, one moved after it
    # landed. Beside the watermark because both read the spent ids.
    findings.retired_advisories = retire.retirement_findings(wm_root)
    findings.snapshot_findings = (
        baseline_snapshot.record_findings(wm_root)
        + check_trajectory.staged_snapshot_findings(wm_root)
        + check_trajectory.committed_snapshot_findings(wm_root)
    )
    findings.integrity += findings.snapshot_findings
    forest = build_forest(
        reg.sn_ids, reg.srs, reg.llrs, reg.tcs, findings.orphan_ids, reg.sn_draft
    )

    out = docs / "test" / "report.md"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(
        render_report(reg, findings, args, forest), encoding="utf-8", newline="\n"
    )

    html_out = None
    if args.html:
        html_out = docs / "test" / "report.html"
        html_out.write_text(html_document(forest), encoding="utf-8", newline="\n")

    render_console(reg, findings, args, out, html_out)

    code = exit_code(findings, args)
    if code:
        sys.exit(code)


if __name__ == "__main__":
    main()
