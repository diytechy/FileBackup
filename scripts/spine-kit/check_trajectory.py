#!/usr/bin/env python3
"""Validate the work-item registry — stdlib only.

The registry home is the spec folder `docs/work/` (one file per work item,
status = directory; the CSV home retired at concurrency-restructure Phase 5,
RULING-4). Every rule below reads the same 18-key rows `read_registry_rows`
emits. A stray resurrected `work-items.csv` is itself an integrity ERROR here
— a second, unread encoding of the registry — which is the difference between
this copy of the reader and the scheduler's silent one.

The `SN->SR->LLR->TC` spine answers *what must be true*. A **work item**
(`WI-###`) decomposes *how the work executes*: it delivers SR(s), belongs to a
**workstream** (a mutable grouping category — the legacy `Track` header is still
read), and depends on **predecessor** work items (the DAG edges), moving
`queued -> active -> done`. This is the validation half of the trajectory layer;
the offline dashboard that renders the same registry is generated separately (a
*view*, never a source of truth — the `trace.py` / `gen_arch_map.py` idiom).

Checks (integrity, in the spirit of `trace.py`):
  - `WI-###` id shape + uniqueness — a malformed or duplicated id is an ERROR.
  - every `Predecessors` id resolves to a real work item — an ERROR (a DAG edge
    to a work item that does not exist).
  - the work-item graph is ACYCLIC over its **hard** edges — a cycle is an
    ERROR (a trajectory that depends on itself can never start).
  - a predecessor may be marked **soft** with a `~` prefix (`~WI-013`): an
    advisory-ordering hint, not a blocker. A soft edge must still resolve
    (ERROR if not), but it is excluded from the cycle rule — a cycle that
    exists only through soft edges is a WARN (conflicting hints), never an
    error — and it never constrains readiness.
  - every `SR-Refs` id exists in `system-requirements.toml` — a WARN, not a
    failure (a draft SR referenced ahead of its registry row is legitimate).
  - an OPEN work item's `Title` over `_TITLE_CONCISE_MAX` characters is a WARN,
    never a failure and never a suggestion to reword what is already filed
    (repo-review 2026-08-19 M-03): a Title is a UI label everywhere the
    dashboard renders it, so keep it a concise name and put the rationale in
    the body. Closed rows are excluded (a historical record); findings are
    summarised, not one line per row.

**The registry SSOT rules** (S1; process-options.md "Trajectory /
work-items layer"). The WI `Deliverable` is **backward-only** (what shipped) and
the per-WI `SpecRef` is the forward bridge that lives while the WI is open and
clears at close. Cross-reading the `docs/work/` registry and its SpecRefs
mechanizes two rules:
  - **R-A** — a WI's `Deliverable` is non-empty **iff** its `Status` is
    **terminal** (`done` or `cancelled`; WI-267). An open (draft/queued/active/deferred)
    WI with a filled Deliverable, or a terminal WI with an empty one, is a hard
    **ERROR at every run** (no flag needed): a commit is the agent handoff point,
    so an incoherent WI state launches the next session wrong. (`done` records
    what shipped; `cancelled` records why it never will.)
  - **R-E** — every open WI carries a non-empty `SpecRef` resolving to an in-repo
    target (`path` or `path#anchor`; the path part must exist). A terminal WI is
    exempt (its SpecRef is cleared — R-F).
  - **R-F** (WI-251; WI-267) — the close side R-E leaves unstated: a **terminal**
    (`done`/`cancelled`) WI's `SpecRef` is **empty**, and every live `docs/specs/`
    file (scaffold README/`-000` boilerplate excluded) is cited by at least one
    *open* WI — otherwise it belongs in `docs/archive/specs/` (the specs README
    lifecycle).
R-E and R-F are **WARN by default, ERROR under `--strict`** (wired at DevStg-Tests+). R-B/R-C —
every *open* WI repeated as a token in `status.md` — stay **retired** (WI-180):
status becomes an integrator-generated snapshot, so open-id currency is enforced
by generated freshness, not by copying the registry back into prose. **R-D is
RESTORED, mode-aware (WI-200):** `status.md` is forward-only, so a `done` WI id
lingering there is a finding — WARN plain, ERROR under `--strict` — *except* when
the file carries the kit's generated-block marker (`<!-- BEGIN GENERATED ... -->`,
the `gen_arch_map`/`gen_trajectory` idiom), where it is an integrator snapshot
that cannot accrete prose and the successor freshness check applies. IMPLEMENTED
since WI-234 — `status_forward_only_findings` below, and the stand-down is scoped
to the marked block, not the whole file. `--staged` adds the warn-first **no-validation-delta** checks: the
follow-up-on-a-done-SR ratchet, the **critique-loop ratchet** (WI-068) — a WI
closing on a `Verification=Critique` SR while the latest `docs/reviews/*-CRITIQUE.md`
verdict is CHANGES-REQUESTED, without the staged set touching the TC registry, the
tests dir, or a `docs/rubrics/` file (harden the TC or add a rubric anchor) — and
the **amend-without-flip** warn (WI-316): a staged diff changing the **approved**
cells of an `Approved` spine row without re-blessing it in the same commit
(process.md §7), the write-time discipline commit-message prose never had.
*Approved*, not every cell — the §A5.1 cell split (owner ruling 2026-07-31;
WI-380) rules traceability **traced, not approved**, so a `Module`/`CodeSymbol`/
`TestRefs`/`SN-Refs`/`Verifies` pointer following code that moved does **not**
arm the marker. The traced half is not discarded: it is carried structurally by
`staged_spine_amendments`, which returns both halves per amended row.

**Opt-out and vacuous by default** — the posture of the always-on
`secrets_scan` floor. The check is on unless `docs/process.toml` `[checks]
trajectory_check` reads `false` (or, for the SN-028 migration window, the
legacy `docs/trajectory-check` reads the one word `off`); and an *absent* or *placeholder-only* registry (nothing but
the inert `WI-000` example row) passes vacuously. So a fresh scaffold and a repo
that never adopts the layer both stay green for free — WI is an off-spine
optional registry, like procurement / assets, whose placeholder never blocks a
gate (`trace.py` does not read WI ids at all).

**Architecture-connectivity coverage** (S5/WI-056; process.md §8). This step is
also the views-checker for the interface layer: every module in the arch-map
inventory (`docs/architecture.md`'s generated block) should appear as ≥1 IF-###
endpoint, and a `Contracts: IF-###` docstring citation should match the
registry — both stay **warn-first forever** (never the exit code, at any gate)
and print at the hook. The ruled posture is **opt-out, default-on**: the
coverage warn fires even when `interfaces.csv` is empty or absent — a
multi-module arch-map with no declared seams reads "connectivity undeclared"
instead of passing vacuously. Silenced only by `[checks] interfaces_check =
false`, or a ≤1-module inventory (nothing to connect). The honesty valve for a
deliberate source/sink is a `source`/`sink` token in that module's IF row Notes
(below).

**Seam-TC coverage — WARN plain, ERROR under `--strict` (DevStg-Tests+) since
WI-488 (OI-43 ruled (a)).** Every declared IF seam should be cited by a TC
(`interface_findings` still reports the total uncited count, informationally,
warn-first at every gate); `if_tc_coverage_findings` is the promotable half — it
reports only the seams NOT on the migration allowlist `docs/if-tc-coverage-allow`
(seeded at the population measured when the ruling executed, with a declared
burn-down expectation — never a permanent exemption). Shares the
`interfaces_check` opt-out; `if_tc_allow_hygiene_findings` reports (never
blocks) an allowlist entry that has gone stale (its seam gained a TC, or its id
no longer resolves), so the burn-down is visible rather than silently absorbed.

**Test-file tags — WARN plain, ERROR under `--strict`.** A test file names the
test cases it runs on the back-link line, in its module docstring or a test's
docstring (`gen_arch_map.read_test_tags`). `tc_tag_findings` reports a tag that
is misplaced, malformed or unknown, and a file under the declared tests root
that is unreadable, each by file, line and shape. It reads no tag as a pass: an
untagged file is no finding, and with no tests root or no TC registry it is
vacuous. An adopter's gate refuses from `DevStg-Impl`, where `check.py` first
adds `--strict`.

**How-SW top-view right-sizing** (WI-073/FB5; process-options.md "Component
layer"). The software-architecture diagram's *first view* must show at most
``TOP_VIEW_MAX`` (10) items: top-level components (a `CMP-###` with no `PartOf`
that contains ≥1 arch-map module) plus **uncontained** modules (a module with no
`Component`-tagged LLR). Exceeding the bound is a **finding** — WARN at the
plain/hook run, **ERROR under `--strict` (DevStg-Tests+)** — that drives right-sizing of
the component designations. Membership derives from the AXES join: a `Component`
tag on an LLR row joins its `Module` → `CMP-###`; nesting via the CMP registry's
`PartOf` (a module counts only at its top-level root). Opt-out is the one word
`[checks] components_check = false` (the `interfaces_check` idiom); a repo with ≤10
modules — or no arch-map inventory — passes trivially (the bound, not the
registry, is the rule), so a small or non-adopting repo is never broken.

**Knowledge⇒component coupling** (WI-153; research-knowledge.md §3a, owner-ruled
2026-07-14). The same finding is *armed independent of the bound* once
`docs/knowledge/` holds a real pack: an uncontained arch-map module is then a
finding even below the 10-item bound, because a knowledge pack ties the *what* to
the knowledge behind the *how*, so that web must be robust wherever packs are
enabled. It reuses the existing `Component`-tag join (no new join) and the same
`components_check` opt-out, and is dormant — costing a non-adopter nothing —
until a pack (any `docs/knowledge/*.md` but the `README.md` index) exists.

**Phase archetype + phase-drop detector** (WI-093; derived-gate model §7/§9.3;
re-keyed to the stage axis by WI-498 slice 4). A phase's pre-dev batch is a
first-class WI whose Title carries a phase-anchor tag recording the LADDER RUNG
the phase stands at once it closes (`[v2]-[DevStg-LLReqs]` = requirement
structuring, `[v2]-[DevStg-Impl]` = decomposition + TCs; the retired
`[v2]-[reqs|tests|g1|g2]` spellings are translated on read, never authored).
This step recognizes those anchors and, reading the LIVE per-phase stage through
the common reader (`derive_stage.read` over `docs/stage`), warns when a phase has
**dropped below** the reach its own closed anchor recorded — the signal that new
or reopened content entered and a new phase-anchor WI is due. It ABSTAINS where a
phase's reading is a repo-global rung (`kitlib.stage.REPO_GLOBAL_RUNGS`), saying
so once rather than going silently vacuous. All **warn-first** (never an
exit-code change, at any stage); vacuous on a single-phase repo with no anchors
(the meta case) or where the stage axis cannot be read.

Usage:  python scripts/check_trajectory.py [--root .] [--strict] [--staged]
Exit codes: 0 clean / vacuous / opted-out, 1 a hard error, 2 usage/environment.

Contracts: IF-009, IF-056, IF-082, IF-083, IF-084, IF-177 — the interface seams
this module declares (process.md §8; rows of record in
docs/requirements/interfaces.toml).

Contract IF-009: the work-item registry's verdict, delivered as a CLI. Exit 0 when
    the registry is clean, absent, placeholder-only or opted out; 1 on a hard
    integrity error — a malformed or duplicated `WI-###`, a predecessor that
    resolves to nothing, a cycle over the hard edges, a stray `work-items.csv`,
    or a `Deliverable` that disagrees with `Status` (R-A); 2 on usage or
    environment. R-A gates every run. R-D, R-E, R-F, the promotable seam-TC
    coverage half, the test-file tag rule and the How-SW top-view bound are WARN
    plain and ERROR under `--strict`. Architecture-connectivity coverage, allowlist hygiene, the
    soft-edge cycle warn, the long-Title warn and the phase-drop detector are
    advisory at every stage and never reach the exit code.
Contract IF-056: the derivation-loader surface the dashboard renders THROUGH.
    `gen_trajectory` imports this module and takes `validate`,
    `read_registry_rows`, `load_wis`, `load_known_srs`,
    `read_trajectory_enabled`, `WI_CSV` and `TOP_VIEW_MAX` from it, so the
    registry parse, the validity verdict and the right-sizing bound have one
    home and the render can never disagree with the check. The loaders are
    importable without side effects and the two modules are re-synced together.
Contract IF-082: the same loader surface as taken by `traj_parse`, the dashboard's
    registry/doc/git source layer: `read_rows`, `spine_carrier`, `SR_CSV` and
    `_arch_scan_profile` — the declared source-root profile the How-SW scan
    walks. One parse of the spine registries feeds both validation and the view.
Contract IF-083: the same loader surface as taken by `traj_views`, the
    What/When/How-SW renderer: `read_rows`, `load_seams`, `component_top_view`,
    `_norm_module`, `_split_refs`, `SR_CSV` and `TOP_VIEW_MAX`. The picture and
    the top-view bound this module enforces are computed by one join, so a
    diagram that renders cannot contradict the finding that would fail it.
Contract IF-084: the same loader surface as taken by `traj_status`, the `--status`
    snapshot layer: `load_ifs`, `IF_CSV` and `spine_carrier`. The seam rows the
    generated status block reports are the rows validation reads.
Contract IF-177: `queue_conflict_pairs(wis) -> [(first_id, second_id, finding)]`,
    the queue-conflict detector's overlaps as edges rather than warn lines, read
    by the consolidation census as its cluster seeds. `wis` is the loader's row
    shape (`id`, `title`, `status`, `srs`, `specref`), and only rows in an open
    status pair. Three signals, a near-identical title, a shared `SR-Refs` id and
    a shared anchor-stripped `SpecRef`, each give one finding per pair, the ids
    in sorted order, and the list is sorted. Pure and warn-only: no I/O, and the
    validator's own rendering of the same pairs never reaches the exit code.
"""

import argparse
import difflib
import re
import sys
import tomllib
from pathlib import Path

# The console guard's one home is the shipped package (WI-448 / D-8);
# aliased to the module-local name so no call site changes.
from kitlib.config import utf8_console as _utf8_console
from observation_cadence import observation_rubric_findings

# THE SHIPPED SHARED-HELPER PACKAGE (owner ruling D-8, `OI-16`, executed
# WI-448): one home for behaviours this module used to spell out itself — the
# declared-policy line reader and the `docs/work/` spec-folder registry reader.
# It replaces the F5 rule, which had licensed those copies unbounded and left
# `tests/test_rule_sync.py` pinning them equal by value. Run as a subprocess
# this script's own dir is sys.path[0] so a plain import resolves; the guard
# covers an in-process import (a test) whose sys.path does not yet carry
# scripts/ — the same sanctioned-sibling idiom the engines use for each other.
try:
    from kitlib import authority as _kitauthority
    from kitlib import config as _kitconfig
    from kitlib import git as _kitgit
    from kitlib import ladder as _kitladder
    from kitlib import provenance as _kitprovenance
    from kitlib import registry as _kitregistry
    from kitlib import spine as _kitspine
    from kitlib import stage as _kitstage
except ImportError:  # pragma: no cover - in-process fallback
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from kitlib import authority as _kitauthority
    from kitlib import config as _kitconfig
    from kitlib import git as _kitgit
    from kitlib import ladder as _kitladder
    from kitlib import provenance as _kitprovenance
    from kitlib import registry as _kitregistry
    from kitlib import spine as _kitspine
    from kitlib import stage as _kitstage

# Sibling: the spine's registry carrier. Run as a
# subprocess this script's own dir is sys.path[0] so a plain import resolves;
# the guard covers an in-process import (a test) whose sys.path does not yet
# carry scripts/ — the same sanctioned-sibling idiom trace.py uses for
# trace_text.
try:
    import spine_carrier
except ImportError:  # pragma: no cover - in-process fallback
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import spine_carrier

# Sibling: THE ACCEPTANCE RECORD (WI-521 slice 1) — the two-tree spine
# comparison and the snapshot mirror, which used to live in this file. Required,
# not optional like `gen_arch_map` below: its findings join the failure set at
# `main`'s aggregation, so a copy of this checker without it would silently stop
# reporting that attested text had drifted, which is the opposite of a vacuity.
# `bootstrap.MAPPING` carries it, so a scaffold gets both or neither. The
# held-status readers the history check reads (`held_status`, IF-196) moved out
# of it whole; they import it one way and ride the same guard and MAPPING.
try:
    import acceptance_record
    import held_status
except ImportError:  # pragma: no cover - in-process fallback
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import acceptance_record
    import held_status

# Sibling: the arch-map AST walk (`gen_arch_map.scan_inventory`) —
# `arch_inventory`'s source since WI-455 retired the committed
# docs/architecture.md block it used to parse back. OPTIONAL like traj_parse's
# schedule import: a fixture that copies check_trajectory.py alone (the
# hook-scaffold tests) simply has no inventory, which is the same vacuity the
# absent committed map produced before.
try:
    import gen_arch_map
except ImportError:
    try:  # pragma: no cover - in-process fallback
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        import gen_arch_map
    except ImportError:
        gen_arch_map = None

try:
    import trajectory_arch as _trajectory_arch
except ImportError:  # pragma: no cover - in-process fallback
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import trajectory_arch as _trajectory_arch

_first_declared_line = _trajectory_arch._first_declared_line
_process_check = _trajectory_arch._process_check
_split_refs = _trajectory_arch._split_refs
TC_CSV = _trajectory_arch.TC_CSV
IF_CSV = _trajectory_arch.IF_CSV
LLR_CSV = _trajectory_arch.LLR_CSV
CMP_CSV = _trajectory_arch.CMP_CSV
SPECS_DIR = _trajectory_arch.SPECS_DIR
TOP_VIEW_MAX = _trajectory_arch.TOP_VIEW_MAX
IF_ID_RE = _trajectory_arch.IF_ID_RE
KERNEL_ALLOW = _trajectory_arch.KERNEL_ALLOW
KERNEL_ALLOW_SEP = _trajectory_arch.KERNEL_ALLOW_SEP
IF_TC_ALLOW = _trajectory_arch.IF_TC_ALLOW
IF_TC_SEED_RE = _trajectory_arch.IF_TC_SEED_RE
CMP_ID_RE = _trajectory_arch.CMP_ID_RE
read_interfaces_check_enabled = _trajectory_arch.read_interfaces_check_enabled
read_components_check_enabled = _trajectory_arch.read_components_check_enabled
_MODULE_EXTS = _trajectory_arch._MODULE_EXTS
_norm_module = _trajectory_arch._norm_module
load_ifs = _trajectory_arch.load_ifs
load_seams = _trajectory_arch.load_seams
_contracts_grammar_findings = _trajectory_arch._contracts_grammar_findings
_owner_files = _trajectory_arch._owner_files
_file_owner_declarations = _trajectory_arch._file_owner_declarations
arch_inventory = _trajectory_arch.arch_inventory
interface_findings = _trajectory_arch.interface_findings
_owner_exact_findings = _trajectory_arch._owner_exact_findings
_declaration_sites = _trajectory_arch._declaration_sites
contract_body_findings = _trajectory_arch.contract_body_findings
_external_body_findings = _trajectory_arch._external_body_findings
_stray_declaration_findings = _trajectory_arch._stray_declaration_findings
_parse_if_tc_allow_full = _trajectory_arch._parse_if_tc_allow_full
parse_if_tc_allow = _trajectory_arch.parse_if_tc_allow
read_if_tc_allow = _trajectory_arch.read_if_tc_allow
if_tc_allow_growth = _trajectory_arch.if_tc_allow_growth
if_tc_coverage_findings = _trajectory_arch.if_tc_coverage_findings
if_tc_allow_hygiene_findings = _trajectory_arch.if_tc_allow_hygiene_findings
if_tc_allow_parse_findings = _trajectory_arch.if_tc_allow_parse_findings
_CODESYMBOL_SPLIT_RE = _trajectory_arch._CODESYMBOL_SPLIT_RE
_codesymbol_candidates = _trajectory_arch._codesymbol_candidates
_codesymbol_site_finding = _trajectory_arch._codesymbol_site_finding
codesymbol_crosscheck_findings = _trajectory_arch.codesymbol_crosscheck_findings
tc_tag_findings = _trajectory_arch.tc_tag_findings
load_cmps = _trajectory_arch.load_cmps
_cmp_roots = _trajectory_arch._cmp_roots
module_components = _trajectory_arch.module_components
component_top_view = _trajectory_arch.component_top_view
knowledge_packs = _trajectory_arch.knowledge_packs
_stack_ini_get = _trajectory_arch._stack_ini_get
_arch_scan_profile = _trajectory_arch._arch_scan_profile
_declared_seam_pairs = _trajectory_arch._declared_seam_pairs
_norm_endpoints = _trajectory_arch._norm_endpoints
_parse_kernel_allow = _trajectory_arch._parse_kernel_allow
read_kernel_modules = _trajectory_arch.read_kernel_modules
kernel_allow_parse_findings = _trajectory_arch.kernel_allow_parse_findings
_classifiable_edges = _trajectory_arch._classifiable_edges
_SCAN_CACHE = _trajectory_arch._SCAN_CACHE
_cross_component_scan = _trajectory_arch._cross_component_scan
cross_component_findings = _trajectory_arch.cross_component_findings
cross_component_advisories = _trajectory_arch.cross_component_advisories
component_findings = _trajectory_arch.component_findings
_IF_TOKEN_RE = _trajectory_arch._IF_TOKEN_RE
_INTERFACES_HEADING_RE = _trajectory_arch._INTERFACES_HEADING_RE
_INTRA_MODULE_RE = _trajectory_arch._INTRA_MODULE_RE
_spec_interfaces_section = _trajectory_arch._spec_interfaces_section
_armed_specs = _trajectory_arch._armed_specs
spec_interface_findings = _trajectory_arch.spec_interface_findings

WI_CSV = "docs/requirements/work-items.csv"
# The spec-folder home the CSV above gives way to (Phase 2b of
# docs/concurrency-restructure.md). Declared as a repo-relative POSIX path
# because the git plumbing below passes it as a PATHSPEC; the reader derives
# the same folder from the CSV path via `spec_work_dir`.
WI_WORK = "docs/work"
# Terminal history's home since WI-504 (OI-55 ruled (a)): `complete/`,
# `cancelled/`, `partial/` moved one directory deeper, under the archive. HEAD
# tree reads that must recognise a terminal status (`_head_spec_status_map`)
# scan both prefixes; the CSV-era readers above stay unchanged because they
# already delegate to `kitlib.registry.read_spec_rows`, which unions the two
# roots itself (`spec_roots`).
WI_ARCHIVE_WORK = "docs/archive/work"
SN_CSV = "docs/requirements/stakeholder-needs.toml"
SR_CSV = "docs/requirements/system-requirements.toml"
# Where R-F sends a spec at close ("close date appended, WI ids noted"), so the
# WI-352 reconciler can still find a terminal WI's spec after its SpecRef clears.
ARCHIVE_SPECS_DIR = "docs/archive/specs"
STATUS_MD = "docs/status.md"

# A well-formed work-item id: `WI-` then digits (`WI-001`). The `-000` example
# row matches this shape but is inert (skipped from the graph — see load_wis).
WI_ID_RE = re.compile(r"^WI-\d+$")

# The work-item lifecycle vocabulary (S1). `draft` is thinking-in-progress — the
# ABSENCE of a decision (WI-384); `deferred` is a first-class, queued-but-not-next
# state carrying the decision's recorded reason; `blocked` is parked on a
# named external dependency. `cancelled` (WI-267, spelled `retired` until WI-384)
# is a TERMINAL won't-build row that
# stays in the registry forever with its reason in the `Deliverable` column — a
# deliberate dead-end, NOT an overload of `done` (a `done` WI shipped something; a
# `cancelled` WI deliberately never will). Since Phase 5 status is the spec's
# DIRECTORY (an unknown one is a loader refusal) `blocked` was never a directory:
# it had been DERIVED (queued + blockref), and with the blockref vocabulary
# retired at WI-553/OI-70 nothing produces it at all now — the literal stays in
# these sets as defensive S1 vocabulary so an in-memory caller that constructs it
# keeps its meaning, but no loader or derivation reaches it.
# "Open" = anything still in flight (not one of the two TERMINAL states).
OPEN_STATUSES = ("draft", "queued", "active", "deferred", "blocked")
# The terminal states: no further build/trace work is owed. Both require a filled
# `Deliverable` (the shipped record for `done`; the cancellation reason for
# `cancelled`) and both must clear their `SpecRef` (R-A + R-F below). `cancelled`
# is deliberately NOT in OPEN_STATUSES / BACKLOG_STALE_STATUSES / the frontier.
# `restructured` (2026-09-02 restructure plan §1.6) is the fourth: a row ABSORBED
# into a successor. Terminal on every rung the other three are — out of
# OPEN_STATUSES, out of BACKLOG_STALE_STATUSES, out of the frontier — and it owes
# a Deliverable, the one line naming the successor that carries its scope.
TERMINAL_STATUSES = ("done", "cancelled", "partial", "restructured")
# The terminal states R-F does NOT make clear their `SpecRef` — the two whose
# work CONTINUES in a successor carrying `supersedes` (see the reason stated in
# full at `spec_ref_findings`). Both spellings are accepted for these: a set cell
# keeps its spec alive for the successor's reader, a cleared one asserts nothing.
_SPECREF_MAY_STAY = ("partial", "restructured")
# What each terminal state's Deliverable is FOR — the clause R-A quotes when the
# cell is empty. A table rather than a chain of conditionals so a fifth terminal
# word cannot be added without saying what its record means. (`partial` is absent
# on purpose: its per-close report under docs/handbacks/ IS the record, so R-A
# exempts it from the cell entirely — see the rule below.)
_TERMINAL_DELIVERABLE_REASON = {
    "done": "records what shipped",
    "cancelled": "records the reason it will not be built",
    "restructured": "names the successor that absorbed its scope",
}

# Backlog-staleness (WI-205) applies to genuinely-in-flight WIs: the open set
# minus `deferred` and `draft` (both re-enter via an owner look — an un-defer, or
# the thinking finishing — which is itself the driven review, so both are
# EXEMPT), plus `blocked` (a WI parked on an external
# dependency is still live work whose cited requirements can drift under it).
# `done`/`cancelled` are terminal and need no re-validation.
BACKLOG_STALE_STATUSES = ("queued", "active", "blocked")

# WI-479 (repo-review 2026-08-19 M-03): a WI Title is a UI label everywhere the
# dashboard renders it — the landing hero's active-work line, the Next-work
# card — and both already clip/disclose past ~140 raw characters rather than
# trust the registry to stay short (gen_trajectory's `_NEXT_WORK_TITLE`). This
# bound is the OTHER half: nudge a Title toward concise AT THE SOURCE, without
# ever failing a gate or asking anyone to reword what is already filed — ten of
# the eleven live (open) titles measured at this WI's filing were multi-sentence
# program narratives, so a validation-only fix would have forced a mass reword
# of owner-authored text. Set a shade under the dashboard's own bound so the
# advisory fires before a reader ever meets the clipped render.
_TITLE_CONCISE_MAX = 120

# The clause both backlog-staleness warns end with. The clock it must clear
# reads the WI's OWN registry spec under docs/work/ (`_spec_row_times`), never
# the SpecRef target — editing the cited doc pushes ITS clock further ahead and
# can never clear the warn. It names the SAME FILENAME because "any reviewed
# edit re-affirms" is false for a Title edit: the Title drives the spec
# filename, and the row clock filters renames out on purpose
# (`_path_commit_time`, row-history mode), so a re-title does not re-date the
# row even when the same commit changed content. WI-362.
BACKLOG_REAFFIRM_HINT = (
    "re-validate the WI against the amended requirement (or re-affirm with a "
    "content edit to the WI's own spec file under docs/work/, keeping its "
    "filename: editing the Title renames the file, and a rename does not "
    "re-date the clock)"
)


# The first non-empty, non-comment line of a declared-policy file, or None
# (absent/empty) — the parse every kit reader shares (hooks, check_privacy.py,
# agent_loop.py). ONE HOME since WI-448: this was one of FIVE literal copies of
# that rule, and `tests/test_rule_sync.py` had to pin them equal by value
# because D-7's F5 ruling licensed the duplication rather than removing it.
# Kept under its own long-standing private name so no call site below moves.
_first_declared_line = _kitconfig.first_declared_line


# One `[checks]` toggle out of `docs/process.toml`, or None when that file has
# nothing to say (fall through to the legacy one-word dial). ONE HOME since
# WI-448 slice 4, and the copy's own stated reason for existing did not describe
# it: this docstring used to argue that the shared package owned the declared-
# LINE rule but not "this module's `[checks]` POLICY — which key, which
# fail-direction, which residual". Only the key is this module's, and it is a
# PARAMETER; the fail-direction and the residual were hardcoded identically in
# `gen_okf.py`'s copy, so nothing module-specific was being encoded and the
# `tests/test_rule_sync.py` equality pin was holding two identical bodies equal.
# Kept under its own long-standing private name so no call site below moves.
_process_check = _kitconfig.process_check


def read_trajectory_enabled(root):
    """Whether the trajectory check is on. `docs/process.toml` `[checks]
    trajectory_check = false` opts out; else (migration window)
    `docs/trajectory-check` with the one word `off`; absent or any other value
    reads on (the safe default), so an ordinary repo runs it without declaring
    anything — opt-out, like `docs/secrets-scan`."""
    declared = _process_check(root, "trajectory_check")
    if declared is not None:
        return declared
    return (
        _first_declared_line(root / "docs" / "trajectory-check") or ""
    ).lower() != "off"


# Ref cells hold ids separated by ; , or whitespace; empty -> []. ONE HOME since
# WI-448 slice 4 (`kitlib.spine.refs`); this was one of SIX copies of the split,
# one of which had drifted to `[;,]` alone.
_split_refs = _kitspine.refs


def read_rows(path):
    """The CSV rows of `path` as dicts, or [] when the file is absent. Read
    utf-8-sig (adversarial-review F4): a BOM'd registry — the realistic Excel
    round-trip on a Windows-first kit — would otherwise glue the BOM to the
    first column name and silently hide EVERY row from every consumer of this
    loader (the WI graph, the pending projection's spine lines). utf-8-sig
    reads plain utf-8 unchanged."""
    if not path.exists():
        return []
    return _kitspine.csv_rows(path.read_text(encoding="utf-8-sig"))


# --- the spec-folder registry reader: ONE home since WI-448 -------------------
# `docs/work/<status>/WI-###-<slug>.md` — one Markdown spec per work item, its
# STATUS encoded as the DIRECTORY (docs/concurrency-restructure.md §2.1). The
# 270-line reader that used to sit here VERBATIM, and identically in the other
# two of schedule.py, check_trajectory.py and agent_common.py, now lives once in
# `kitlib/registry.py`: owner ruling D-8 (`OI-16`, inversion confirmed
# 2026-08-13) retired the F5 no-shared-module rule that had licensed the copies.
#
# RE-EXPORTED under the names this module has always carried, so no call site
# and no test that reads `check_trajectory.<name>` changes with the move. The names are
# listed one per line rather than star-imported because this module's public
# surface is a fact its readers check, not a wildcard.
WI_COLUMNS = _kitregistry.WI_COLUMNS
SPEC_SCALARS = _kitregistry.SPEC_SCALARS
SPEC_LISTS = _kitregistry.SPEC_LISTS
SPEC_STATUS_DIRS = _kitregistry.SPEC_STATUS_DIRS
SPEC_FENCE = _kitregistry.SPEC_FENCE
SPEC_DELIVERABLE = _kitregistry.SPEC_DELIVERABLE
SPEC_HANDBACK = _kitregistry.SPEC_HANDBACK
SPEC_CONTEXT = _kitregistry.SPEC_CONTEXT
spec_work_dir = _kitregistry.spec_work_dir
spec_files = _kitregistry.spec_files
parse_spec_frontmatter = _kitregistry.parse_spec_frontmatter
parse_spec_status = _kitregistry.parse_spec_status
parse_spec_id = _kitregistry.parse_spec_id
parse_spec_deliverable = _kitregistry.parse_spec_deliverable
parse_spec_row = _kitregistry.parse_spec_row
read_spec_rows = _kitregistry.read_spec_rows


def read_registry_rows(path, errors=None):
    """The work-item rows from the one registry home — the spec folder beside
    `path` (`docs/work/`; the CSV home retired at concurrency-restructure
    Phase 5, RULING-4). An absent folder reads as an empty registry.

    This module is the VALIDATOR, so it is the one copy of the reader that
    SPEAKS. Two findings only it raises, both deliberate:

      * **a stray `work-items.csv` is itself a finding.** No reader consumes
        the CSV form any more, so a resurrected file is a second, silently
        ignored encoding of the registry — name it and route to the fix.
      * **a malformed spec is reported, not skipped silently** — the same
        split `load_wis` already draws for a malformed id.

    Findings append to `errors` when a list is given; with none, this degrades
    to the quiet read every other caller wants."""
    if errors is not None and Path(path).exists():
        errors.append(
            "{} present but the CSV registry home retired (concurrency-"
            "restructure Phase 5) — {} is the registry; convert stray rows "
            "with wi_convert.py and delete the file".format(WI_CSV, WI_WORK)
        )
    work_dir = spec_work_dir(path)
    if not work_dir.is_dir():
        return []
    return read_spec_rows(work_dir, on_error=None if errors is None else errors.append)


def registry_home(root):
    """The repo-relative path of the registry home — `docs/work/`, the one
    home since the CSV retired."""
    return WI_WORK


def load_wis(rows):
    """Parse work-item rows into `(wis, integrity_errors)`.

    `wis` are the real, well-formed items that form the graph; the inert `-000`
    example row is skipped (the `trace.py` placeholder rule — an off-spine
    optional registry's placeholder never blocks a gate). Integrity errors
    (malformed or duplicated ids) are collected on the raw rows so a broken id is
    *reported*, never silently dropped.

    Implements: SR-157, LLR-034
    """
    wis, integrity, seen = [], [], set()
    for r in rows:
        wid = (r.get("WI-ID") or "").strip()
        if not wid.startswith("WI-"):
            continue  # blank line / non-WI row
        if not WI_ID_RE.match(wid):
            integrity.append(
                "malformed work-item id {!r} (expected WI-<digits>)".format(wid)
            )
            continue
        if wid in seen:
            integrity.append("duplicate work-item id {}".format(wid))
            continue
        seen.add(wid)
        if wid.endswith("-000"):
            continue  # inert template example row (like trace.py)
        # A `~` prefix marks a soft (advisory-ordering) predecessor edge; a bare
        # WI id is a hard (blocking) edge; a bare `OI-###` id is a hard
        # OPEN-ITEM edge (OI-73), resolved against the open-items registry rather
        # than the WI graph — see `kitlib.spine.split_pred_edges`.
        preds, oi_preds, soft = _kitspine.split_pred_edges(r.get("Predecessors", ""))
        wis.append(
            {
                "id": wid,
                "title": (r.get("Title") or "").strip(),
                "workstream": (r.get("Workstream") or r.get("Track") or "").strip()
                or "other",
                "srs": _split_refs(r.get("SR-Refs", "")),
                "preds": preds,
                "oi_preds": oi_preds,
                "soft": soft,
                "status": (r.get("Status") or "queued").strip().lower(),
                # Backward-only summary (R-A) and the forward bridge (R-E). A
                # legacy CSV without the column reads as "" (DictReader -> None).
                "deliverable": (r.get("Deliverable") or "").strip(),
                "specref": (r.get("SpecRef") or "").strip(),
                # The lineage cell (`;`-joined, one id or several): R-A's
                # restructured arm reads it BOTH ways — this row's, to say what
                # it was absorbed into, and the named successor's, to check the
                # claim is mutual. (No `or ""` guard: `kitlib.spine.refs` already
                # reads a missing column's None as the empty cell, and the second
                # copy of that guard is what pushed this function off its
                # complexity baseline.)
                "supersedes": _split_refs(r.get("Supersedes")),
            }
        )
    return wis, integrity


def _cycles(wis, pred_map):
    """Cycle strings found by DFS colouring over `pred_map` ([] = acyclic).

    Iterative (explicit stack), not recursive: a work-item registry may encode an
    arbitrarily long dependency chain, and a recursive DFS would raise a raw
    ``RecursionError`` past CPython's ~1000-frame limit — the kit fails on bad
    data with a clear message, never an uncaught traceback. ``stack`` holds
    ``[node, next-pred-index]`` frames and ``path`` mirrors
    their nodes, so a back-edge to a GREY (on-path) node reconstructs the cycle
    exactly as the former recursion did."""
    WHITE, GREY, BLACK = 0, 1, 2
    colour = {w["id"]: WHITE for w in wis}
    found = []
    for w in wis:
        if colour[w["id"]] != WHITE:
            continue
        stack = [[w["id"], 0]]
        path = [w["id"]]
        colour[w["id"]] = GREY
        while stack:
            node, i = stack[-1]
            preds = pred_map[node]
            if i < len(preds):
                stack[-1][1] += 1
                p = preds[i]
                if colour[p] == GREY:
                    found.append(" -> ".join(path[path.index(p) :] + [p]))
                elif colour[p] == WHITE:
                    colour[p] = GREY
                    stack.append([p, 0])
                    path.append(p)
            else:
                colour[node] = BLACK
                stack.pop()
                path.pop()
    return found


# --- WI-349: physical-line + control-character integrity of the registry rows --
# WRITTEN FOR THE CSV HOME, and its first premise is retired: `staged_findings`
# used to compare `git show HEAD:<work-items.csv>` against the working copy
# LINE-WISE, and this check enforced the assumption that docstring stated. The
# folder registry is read by NAME LISTING, so nothing reads it line-wise any
# more (main() records the same retirement where the WI rows are loaded). What
# survives, and why this stays: the C0-control half below is about a cell being
# TEXT AT ALL — the `9e2008a` backspace case in `_control_findings` — which no
# carrier change touches, and the spine CSVs' own callers/tests still read it.
LINE_BREAK_CHARS = (("\r", "CR"), ("\n", "LF"))
# TAB is deliberately allowed: it is ordinary whitespace inside a quoted cell and
# breaks nothing downstream. Every other C0 control is not text — see below.
_ALLOWED_CONTROLS = "\t"


def _control_findings(cell):
    """`[(label, detail)]` for the integrity violations in one cell.

    Two classes, reported distinctly because the reader's next action differs:

      - **CR / LF** break the one-physical-line rule a CSV-carried registry
        reads (retired for the WI folder registry — see the block comment above);
      - **any other C0 control** is not text at all. Widened here after
        `9e2008a` wrote a literal `0x08` into this very registry: a shell heredoc
        collapsed the `\\b` of a Windows path, so `Git\\bin` became `Git` +
        BACKSPACE and the Deliverable cell went on to claim the remedy reads
        `put C:\\Program Files\\Gitin on PATH` — corrupting the exact string
        WI-326 existed to make actionable. Every gate step passed over it, and
        the CR/LF-only form of this check passed over it too: an adversarial
        review found it by scanning the bytes. A control character is invisible
        in every editor and diff a reader will use, so nothing but a byte-level
        check can see it, which is precisely the argument for the check.
    """
    out = []
    for char, label in LINE_BREAK_CHARS:
        if char in cell:
            out.append(
                (
                    label,
                    "a WI row must be ONE physical line (the staged-close scan "
                    "compares HEAD line-wise, so an embedded break makes it read "
                    "a different set of rows while every other check passes)",
                )
            )
    if out:
        return out  # a break is the more specific diagnosis; do not double-report
    for char in cell:
        if ord(char) < 0x20 and char not in _ALLOWED_CONTROLS or ord(char) == 0x7F:
            out.append(
                (
                    "control character 0x{:02X}".format(ord(char)),
                    "a registry cell is text; a control character is invisible in "
                    "every editor and diff, so it can only ever be found by a "
                    "byte-level check like this one",
                )
            )
            break  # one finding per cell; the fix is the same
    return out


def cell_integrity_errors(rows):
    """Hard-error strings for any registry cell that is not one line of plain text.

    Demonstrated 2026-07-28: a WI row was written with a literal newline inside a
    quoted `Title` cell. It round-tripped through `csv` perfectly, so the full
    trajectory validator reported CLEAN — and the only thing that surfaced it was
    git warning about mixed line endings in the working tree, i.e. luck. What
    such a row actually costs is silent and downstream: `staged_findings` reads a
    *different set of rows* than the loader does (its line-wise HEAD comparison
    splits the row in two), the dashboard renders a broken cell in its detail
    JSON, and the row is invisible to every line-based tool that touches the
    registry.

    ERROR at every run, alongside the malformed/duplicate-id errors rather than
    in the warn-first coherence tier: those two are the same class — a row the
    loader cannot be trusted to have read correctly — as opposed to a coherence
    question about a row it read fine.

    Deliberately scoped to the WI registry: the line-wise comparison is what
    creates the requirement, and it reads only this file. The spine registries
    are `trace.py`'s to police.

    Names the WI id and the COLUMN, because a bare "row 47 is malformed" against
    a 350-row single-line-per-row CSV is not actionable — the cell is what the
    author has to find. Falls back to the 1-based row number when it is the id
    cell itself that is broken.
    """
    errors = []
    for index, row in enumerate(rows, start=1):
        raw_id = str(row.get("WI-ID") or "")
        broken_id = any(char in raw_id for char, _ in LINE_BREAK_CHARS)
        # A truncated id would be worse than no id — it looks like a real one and
        # matches nothing — so a broken id cell reports by row number instead.
        where = (
            "row {}".format(index)
            if broken_id or not raw_id.strip()
            else raw_id.strip()
        )
        for column, value in row.items():
            # DictReader hands back a list under the restkey when a row has more
            # fields than the header, and None as the key; neither is a str.
            cells = value if isinstance(value, list) else [value]
            name = column if isinstance(column, str) else "<extra fields>"
            for cell in cells:
                if not isinstance(cell, str):
                    continue
                for label, detail in _control_findings(cell):
                    errors.append(
                        "{}: {} cell contains a literal {} — {}".format(
                            where, name, label, detail
                        )
                    )
    return errors


def _title_length_warns(wis):
    """`[]` or one summarised WARN string naming how many OPEN work items carry
    a Title over `_TITLE_CONCISE_MAX` characters (WI-479, M-03).

    Scoped to `OPEN_STATUSES` — a closed row is a historical record this
    advisory never asks anyone to reword. Summarised into ONE line (worst-first,
    first 5 named) rather than one line per row — the same call the IF-coverage
    rule elsewhere in this module already made (its `SUMMARISED` comment: N warn
    lines is a check nobody reads)."""
    over = sorted(
        (
            w
            for w in wis
            if w["status"] in OPEN_STATUSES and len(w["title"]) > _TITLE_CONCISE_MAX
        ),
        key=lambda w: -len(w["title"]),
    )
    if not over:
        return []
    shown = ", ".join(
        "{} ({} chars)".format(w["id"], len(w["title"])) for w in over[:5]
    )
    return [
        "{} open work item(s) carry a Title over {} characters — keep the "
        "Title a concise name and put rationale in the body, not the "
        "registry cell{}: {}".format(
            len(over),
            _TITLE_CONCISE_MAX,
            " (first 5 shown)" if len(over) > 5 else "",
            shown,
        )
    ]


def _predecessor_errors(w, ids, known_ois):
    """The dangling-edge ERRORs for one WI's predecessors: a WI edge (hard or
    soft) that names no work item, or an `OI-###` edge (OI-73) that names no
    minted open item. The two edge kinds resolve against different registries —
    the WI id set and the open-items registry — but are the same dangling-edge
    error class."""
    out = []
    for p in w["preds"] + w["soft"]:
        if p not in ids:
            out.append("{}: predecessor {!r} is not a work item".format(w["id"], p))
    for o in w["oi_preds"]:
        if o not in known_ois:
            out.append(
                "{}: open-item predecessor {!r} is not a minted open item "
                "(OI-73 typed edge; check docs/requirements/open-items.toml and "
                "the id-watermark's OI space)".format(w["id"], o)
            )
    return out


def validate(wis, known_srs, known_ois=None):
    """Return the hard-error strings for the work-item graph ([] = clean).

    Dangling `SR-Refs` are WARNED on stderr (a draft SR referenced ahead of its
    row is legitimate), never failed — and only when the SR registry is
    non-empty, so a repo without SRs yet does not spuriously warn. Soft (`~`)
    predecessors must resolve like hard ones, but only **hard** edges are
    subject to the acyclicity ERROR — a cycle that needs a soft edge to close
    is a WARN (conflicting ordering hints), never a failure. An overlong OPEN
    Title also WARNS (never fails) — see `_title_length_warns`.

    A hard OPEN-ITEM edge (OI-73) resolves against `known_ois` — the open-items
    registry read through the spine carrier — not the WI id set: an `OI-###` in
    `Predecessors` that names no minted open item is a dangling edge, the same
    ERROR class as an unknown WI predecessor. `known_ois=None` (the non-adopter
    with no registry) reads as the empty set, so EVERY OI edge is that ERROR:
    an edge naming a registry the repo does not carry is dangling. The caller
    passes the real set (see `main`).

    Implements: SR-157, LLR-034
    """
    ids = {w["id"] for w in wis}
    known_ois = known_ois if known_ois is not None else frozenset()
    errors = []

    for w in wis:
        errors.extend(_predecessor_errors(w, ids, known_ois))
        for s in w["srs"]:
            if known_srs and s not in known_srs:
                print(
                    "check_trajectory: WARN - {} references {} "
                    "(not in the SR registry; draft?)".format(w["id"], s),
                    file=sys.stderr,
                )

    for msg in _title_length_warns(wis):
        print("check_trajectory: WARN - {}".format(msg), file=sys.stderr)

    # A hard cycle makes the trajectory unstartable -> ERROR.
    hard_map = {w["id"]: [p for p in w["preds"] if p in ids] for w in wis}
    for cyc in _cycles(wis, hard_map):
        errors.append("dependency cycle: {}".format(cyc))

    # A cycle that only closes through soft edges is a hint conflict -> WARN.
    if not any(e.startswith("dependency cycle") for e in errors):
        both_map = {
            w["id"]: [p for p in w["preds"] + w["soft"] if p in ids] for w in wis
        }
        for cyc in _cycles(wis, both_map):
            print(
                "check_trajectory: WARN - soft-edge cycle (advisory ordering "
                "hints conflict; not a blocker): {}".format(cyc),
                file=sys.stderr,
            )
    return errors


def load_known_srs(root):
    """The set of real SR ids from system-requirements.toml (for the SR-ref warn)."""
    return {
        (r.get("SR-ID") or "").strip()
        for r in spine_carrier.load(root / SR_CSV, "SR-ID")
        if (r.get("SR-ID") or "").startswith("SR-")
    }


#: The open-items registry — read directly through `spine_carrier` (already a
#: dependency) rather than through `trace.open_item_states`, because a
#: `check_trajectory -> trace` import edge would form a new module cycle
#: (`trace` reaches back into `check_trajectory`); the import-cycle ratchet
#: forbids it. The read is the same one `trace.open_item_states` performs.
OPEN_ITEMS_REL = "docs/requirements/open-items.toml"


def load_known_ois(root):
    """The set of minted open-item ids (for the typed OI-edge resolution, OI-73).

    Reads the same registry the readiness gate resolves an OI edge against, so
    the validator's ERROR and the scheduler's `waiting` cannot disagree about
    whether an `OI-###` edge is even real. `None` when the repo carries no
    open-items registry at all (the D-5 absent-vs-empty distinction); `validate`
    reads it as the empty set, so every OI edge in such a repo is a dangling-edge
    ERROR."""
    path = Path(root) / OPEN_ITEMS_REL
    if spine_carrier.resolve(path) is None:
        return None
    return frozenset(
        oid
        for r in spine_carrier.load(path, "OI-ID")
        if (oid := (r.get("OI-ID") or "").strip()).startswith("OI-")
        and not oid.endswith("-000")
    )


def uncited_open_item_findings(root, wi_rows):
    """Each pending open item NO queued work item cites in its `needs` (WI-790):
    the queue is the only route a decision reaches the owner by, so such an
    item is invisible, and it is an ERROR whatever the gate. Read off the one
    queue projection (`kitlib.spine.open_item_queue`) the owner surface and the
    status snapshot also read. Vacuous without an open-items registry.

    Implements: SR-148, LLR-299
    """
    path = Path(root) / OPEN_ITEMS_REL
    if spine_carrier.resolve(path) is None:
        return []
    queue = _kitspine.open_item_queue(wi_rows, spine_carrier.load(path, "OI-ID"))
    return [
        "{}: pending, but no queued work item cites it in `needs`, so the "
        "decision never reaches the owner's queue — file a queued placeholder "
        "row citing it (WI-790)".format(oid)
        for oid in queue["uncited"]
    ]


def _registry_ref(specref):
    """`(names the open-items registry, its #anchor)` for a `specref`, under
    either carrier's spelling (`.toml` or `.csv`): the registry is matched by
    its carrier-free stem, the one name it has across a carrier change.

    Implements: SR-148, LLR-299
    """
    pathpart, _hash, anchor = specref.partition("#")
    stem = spine_carrier.stem(OPEN_ITEMS_REL)
    return spine_carrier.stem(pathpart.strip()) == stem, anchor.strip()


def open_item_specref_findings(root, wis):
    """The citation integrity of an open row whose `specref` names the
    open-items registry (WI-790, A6), under either carrier's spelling:

      * its `#OI-NNN` anchor must name an item its `needs` cites — a
        placeholder's spec of record is ITS decision's record, never another's;
      * once every item it cites is ruled it must not keep the registry at
        all: the ruling writes the row's real criteria and points it at a real
        spec. An item absent from the registry is not ruled (the dangling-edge
        ERROR reports it).

    A state check — no diff, no history. Vacuous without a registry.

    Implements: SR-148, LLR-299
    """
    path = Path(root) / OPEN_ITEMS_REL
    if spine_carrier.resolve(path) is None:
        return []
    states = {
        (r.get("OI-ID") or "").strip(): (r.get("Status") or "").strip().lower()
        for r in spine_carrier.load(path, "OI-ID")
    }
    out = []
    for w in wis:
        named, anchor = _registry_ref(w["specref"])
        if w["status"] in OPEN_STATUSES and named:
            out.extend(_registry_ref_findings(w, anchor, states))
    return out


def _registry_ref_findings(w, anchor, states):
    """The two citation-integrity findings for one open row whose `specref`
    names the open-items registry.

    Implements: SR-148, LLR-299
    """
    out = []
    if anchor and anchor not in w["oi_preds"]:
        out.append(
            "{}: its specref names {}, which its needs do not cite — a "
            "placeholder's specref names the item it waits on (WI-790)".format(
                w["id"], anchor
            )
        )
    if all(states.get(o, "pending") != "pending" for o in w["oi_preds"]):
        out.append(
            "{}: every open item it cites ({}) is ruled, but its specref still "
            "names the open-items registry — the ruling owes the row its real "
            "specref and criteria (WI-790)".format(
                w["id"], ", ".join(w["oi_preds"]) or "none"
            )
        )
    return out


# --- the phase-anchor archetype + phase-drop detector (WI-093) -----------------
# The derived model (docs/archive/specs/derived-gate-model.2026-07-20.md §7/§9.3)
# structures a phase's pre-dev work as a first-class WI whose Title carries a
# phase-anchor tag. The derived bar DROPPING below a phase's last-closed level is
# the signal that new/reopened content entered and a new phase-anchor WI is due;
# the committed anchor is where phase identity + membership live (a git-history
# walk is rebase-sensitive and carries no membership, §9.3). Both checks are
# WARN-FIRST — like the connectivity coverage, they never change the exit code.
#
# RE-KEYED TO THE STAGE AXIS (WI-498 slice 4, ruled plan §5 item 4). The detector
# used to compare a phase's derived BAR against an anchor's internal level 1/2.
# Both halves moved: the current reading now comes from `docs/stage`'s
# `per-phase-live` field through the common reader, and an anchor's recorded reach
# is a LADDER RUNG. The bar axis is out of this module entirely.
#
# THE ANCHOR VOCABULARY, AND WHY THE LEGACY SPELLINGS ARE TRANSLATED RATHER THAN
# RE-RECORDED. A phase anchor is a WI TITLE — a committed record of what a closed
# work item did — so D-4's refusal to re-point history applies exactly as it did
# at the `g1`/`g2` changeover: the ~20 anchors already in `docs/work/complete/`
# stay spelled as they were, and the read side declares the translation.
#
# THE TRANSLATION IS BY MEANING, NOT BY SPELLING, and the two differ by two rungs
# in both rows — which is precisely the trap the stage/bar spelling overlap sets:
#
#   `[p]-[reqs]` / `[p]-[g1]`  requirement structuring: the phase's SRs are  check_vocab: allow
#                              authored AND approved. `spine_stage` clears its
#                              `any(is_drafted(sr))` test from there on, so what
#                              the phase then stands at is DevStg-LLReqs — NOT
#                              DevStg-Reqs, which is the rung it has just LEFT.
#   `[p]-[tests]` / `[p]-[g2]` decomposition: LLRs and TCs authored and  check_vocab: allow
#                              non-Drafted. That clears the LLReqs and Tests
#                              predicates both, so the phase stands at
#                              DevStg-Impl — NOT DevStg-Tests.
#
# So an anchor records THE RUNG THE PHASE STANDS AT ONCE IT CLOSES (slice 2's
# inversion finding, on this axis: a bar value corresponds to the rung at which it
# was reached). Going forward the canonical spelling IS that rung, verbatim:
# `[<phase>]-[DevStg-LLReqs]`, `[<phase>]-[DevStg-Impl]` — stage vocabulary, no
# second word to keep in step, and any rung is expressible rather than just two.
PHASE_ANCHOR_RE = re.compile(
    r"^\[([^\]]+)\]-\[(g[12]|reqs|tests|DevStg-[A-Za-z]+)\]", re.IGNORECASE
)
# Legacy anchor token -> the rung it recorded. Read side only; never authored.
_ANCHOR_REACH = {
    "reqs": _kitladder.STAGE_LLREQS,
    "g1": _kitladder.STAGE_LLREQS,
    "tests": _kitladder.STAGE_IMPL,
    "g2": _kitladder.STAGE_IMPL,
}


def _anchor_reach(token):
    """The rung a phase-anchor token records, or None when the token is
    rung-shaped but names no rung on the ladder.

    A `DevStg-*` token is matched CASE-INSENSITIVELY by the regex above (titles
    are prose), so it is folded back onto the canonical spelling here rather than
    handed to `require_rung`, which is deliberately exact."""
    lowered = token.lower()
    if lowered in _ANCHOR_REACH:
        return _ANCHOR_REACH[lowered]
    for rung in _kitladder.STAGE_ORDER:
        if rung.lower() == lowered:
            return rung
    return None


def phase_stages(root):
    """`{phase-label: rung-or-DevStg-Below}` — the LIVE per-phase stage, read
    through the common reader (`derive_stage.read`, ruled plan §3), or `{}` when
    the stage axis cannot be read at all.

    THE LIVE READING, NOT THE SETTLED ONE, AND THAT IS THE WHOLE DESIGN. This is
    an EVENT detector: its question is "did new or reopened content enter a phase
    that had closed an anchor?", and a Drafted or re-Drafted row IS that event.
    The headline `stage`/`per-phase` fields exclude drafts by construction — slice
    1's C-01 fix, which exists so one draft cannot collapse SELECTION — so they
    cannot see the event at all, by design. `per-phase-live` is where the drafts
    are, and reading it here is what lets selection stay uncollapsed while
    detection stays sharp. (It also answers slice 3's banked tension: rung 3's
    self-reporting recursion, a Drafted component dropping the reported stage, is
    visible on the live reading even though it no longer moves the effective one.)

    THE IMPORT IS LAZY AND DEGRADES TO VACUOUS. This module runs in the shipped
    pre-commit hook, and the `approval-fresh` lesson (130-REVIEW-A) is that a hook
    which hard-requires a sibling an adopter's tree may not have blocks every
    commit. A fixture that copies `check_trajectory.py` alone therefore loses the
    drop half only — the same vacuity an absent `docs/gate` produced before."""
    try:
        import derive_stage
    except ImportError:  # pragma: no cover - exercised via the sys.path fallback
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        try:
            import derive_stage
        except ImportError:
            return {}
    try:
        record = derive_stage.read(Path(root))
    except (OSError, ValueError):
        # A hand-edited or ladder-stale docs/stage RAISES in `kitlib.stage.parse`
        # (its ruled direction). That is the `derived-stage` step's finding to
        # report, not this advisory detector's to crash the hook over.
        return {}
    return dict(record.get("per-phase-live") or {})


def phase_anchors(wis):
    """`({(phase, rung): wi}, [shape-warnings])` — the phase-anchor WIs parsed
    from Titles, over the canonical `[phase]-[DevStg-<Rung>]` spelling and the
    retired `[phase]-[reqs|tests]` / `[phase]-[g1|g2]` ones the committed anchors
    carry (all translated by `_anchor_reach`). A duplicate (phase, rung) anchor —
    including one spelled each way, which is exactly the collision worth catching
    during a changeover — and an anchor whose predecessors omit the next-lower
    anchor of its own phase, are warned (advisory only)."""
    anchors, warns = {}, []
    for w in wis:
        m = PHASE_ANCHOR_RE.match(w["title"])
        if not m:
            continue
        reach = _anchor_reach(m.group(2))
        if reach is None:
            warns.append(
                "phase anchor {} names [{}]-[{}], which is not a rung on the "
                "stage ladder — expected one of {}".format(
                    w["id"], m.group(1), m.group(2), ", ".join(_kitladder.STAGE_ORDER)
                )
            )
            continue
        key = (m.group(1), reach)
        if key in anchors:
            warns.append(
                "duplicate phase anchor [{}]-[{}] ({} and {})".format(
                    key[0], reach, anchors[key]["id"], w["id"]
                )
            )
            continue
        anchors[key] = w
    # THE PREDECESSOR SHAPE RULE, GENERALIZED. It used to be "a `tests` anchor
    # lists its `reqs` anchor", which was expressible only because there were
    # exactly two levels. On a ladder it is "each anchor lists the next-LOWER
    # anchor of its own phase" — the same rule, stated over whatever rungs the
    # phase actually recorded.
    by_phase = {}
    for phase, reach in anchors:
        by_phase.setdefault(phase, []).append(reach)
    for phase, reaches in by_phase.items():
        ordered = sorted(reaches, key=_kitstage.order)
        for higher, lower in zip(ordered[1:], ordered):
            w = anchors[(phase, higher)]
            lower_id = anchors[(phase, lower)]["id"]
            if lower_id not in (w["preds"] + w["soft"]):
                warns.append(
                    "phase anchor {} ([{}]-[{}]) does not list its "
                    "[{}]-[{}] ({}) as a predecessor".format(
                        w["id"], phase, higher, phase, lower, lower_id
                    )
                )
    return anchors, warns


def phase_findings(root, wis):
    """The phase-archetype + phase-drop warns (WI-093; warn-first). Returns the
    warn strings ([] when vacuous — no anchors, or no readable stage axis, the
    single-phase meta case).

    THE DROP RULE. For each phase with a **done** anchor, take the highest rung
    its closed anchors recorded and compare the phase's current LIVE stage against
    it; below means new or reopened content entered, and a new phase-anchor WI is
    due. The message names the CANONICAL anchor spelling even when the closed
    anchor it read used a retired one, because the WI it is asking for is a NEW
    row.

    THE ABSTENTION, WHICH IS THE ONLY THING HERE THAT IS NOT A DIRECT RE-KEY.
    `kitlib.stage.REPO_GLOBAL_RUNGS` names the three rungs a per-phase reading
    cannot own — they are decided by repo-wide registries and passed whole to
    every per-phase call. A phase sitting on one of them is BELOW its recorded
    reach as a matter of arithmetic while saying nothing whatever about its own
    content: every phase reads the same rung at once, and blaming any one of them
    for "new or reopened content" would be a fabricated attribution. So the
    detector abstains there — and, because the schedule map's standing criticism
    of this detector was that it went VACUOUS SILENTLY when it could not parse the
    cache, it says so once, naming the rung and the phases it stood down for."""
    anchors, warns = phase_anchors(wis)
    live = phase_stages(root)
    # phase -> the highest rung any of its DONE anchors recorded
    closed = {}
    for (phase, reach), w in anchors.items():
        if w["status"] == "done":
            current = closed.get(phase)
            if current is None or _kitstage.order(reach) > _kitstage.order(current):
                closed[phase] = reach
    stood_down = {}
    for phase, reach in sorted(closed.items()):
        cur = live.get(phase)
        if cur is None:
            continue
        if cur in _kitstage.REPO_GLOBAL_RUNGS:
            stood_down.setdefault(cur, []).append(phase)
            continue
        if _kitstage.order(cur) < _kitstage.order(reach):
            warns.append(
                "phase {!r} dropped to {} but its closed [{}]-[{}] anchor recorded "
                "reach {} — new or reopened content entered; open a new "
                "[{}]-[DevStg-<rung>] work item to structure it (derived model "
                "§9.3)".format(phase, cur, phase, reach, reach, phase)
            )
    for rung, phases in sorted(stood_down.items()):
        warns.append(
            "phase-drop detector stood down for phase(s) {}: each reads {}, a "
            "repo-global rung decided by the need/boundary/component registries "
            "rather than by any one phase's content — the comparison against a "
            "closed anchor's recorded reach would be unattributable. It resumes "
            "when the frame settles".format(", ".join(sorted(phases)), rung)
        )
    return warns


# --- SpecRef anchor resolution (WI-354) ---------------------------------------
# R-E resolved only the PATH half of a `doc#anchor` SpecRef, so a row could cite a
# heading that does not exist and read as traceable for days (WI-326 cited a
# truncated `docs/log.md#...` slug from the day it was filed; it surfaced only when
# the close wrote the same string into a markdown LINK, where check_docs rejected
# it at once). The identical reference was enforced in one home and unread in the
# other — the WI-308 doc-refs class, one registry over.
#
# The anchor set comes from check_docs.parse_doc, NOT from a second slugifier here:
# two slug implementations that drift produce false findings on correct rows, which
# is worse than the gap being closed. That is a SIBLING IMPORT, allowed on the same
# ground as gen_trajectory's `check_trajectory` one — both modules are in
# bootstrap.py MAPPING, so they always ship and re-sync together.
#
# The import is LAZY and degrades to None rather than raising: this module runs in
# the SHIPPED pre-commit hook, and the `approval-fresh` lesson (130-REVIEW-A) is that
# a hook which hard-requires a file an adopter's tree may not have blocks every
# commit. Missing check_docs therefore costs the anchor half only — the path half
# is unchanged. Vacuity here is a real risk, so it is pinned by a test that drives
# the check against a KNOWN-BAD anchor rather than by trusting this comment.
_MD_SUFFIXES = (".md", ".markdown")
_ANCHOR_CACHE = {}  # resolved path -> frozenset of anchors, or None when unreadable


def doc_anchors(path):
    """The lowercase anchor slugs `path` exposes, or None when they cannot be
    determined (not a markdown file, unreadable, or check_docs unavailable).

    None means "unknown, do not judge" and is never treated as an empty set — an
    absent sibling must not turn every anchored SpecRef into a finding."""
    key = str(path)
    if key in _ANCHOR_CACHE:
        return _ANCHOR_CACHE[key]
    anchors = None
    if path.suffix.lower() in _MD_SUFFIXES and path.is_file():
        try:
            import check_docs
        except ImportError:  # pragma: no cover - exercised via the sys.path fallback
            sys.path.insert(0, str(Path(__file__).resolve().parent))
            try:
                import check_docs
            except ImportError:
                check_docs = None
        if check_docs is not None:
            try:
                anchors = frozenset(check_docs.parse_doc(path)["anchors"])
            except OSError:
                anchors = None
    _ANCHOR_CACHE[key] = anchors
    return anchors


def nearest_anchor(frag, anchors):
    """The closest existing slug to `frag`, or None. A wrong anchor is nearly
    always a stale or TRUNCATED one rather than an invented one, so the report
    names the near miss — that is what makes the finding actionable instead of
    merely true.

    The prefix pass runs BEFORE difflib because difflib's ratio degrades with the
    LENGTH of the truncation, not with truncation as such — and 131-REVIEW-A
    refuted the stronger claim this docstring used to make. Measured against the
    live docs/log.md anchor set: WI-326's own 44-of-76-char truncation scores
    0.733 and plain `get_close_matches` finds it unaided, so that case does NOT
    justify the branch. A severer truncation does — `2026-07-26--wi-326` returns
    NOTHING from difflib at the 0.6 cutoff while the prefix pass returns the exact
    heading. That measured pair is pinned by a test, so this rationale cannot rot
    into the over-claim it replaced."""
    if not anchors:
        return None
    prefix = [a for a in anchors if a.startswith(frag) or frag.startswith(a)]
    if prefix:
        return sorted(prefix, key=lambda a: (abs(len(a) - len(frag)), a))[0]
    near = difflib.get_close_matches(frag, sorted(anchors), n=1, cutoff=0.6)
    return near[0] if near else None


def specref_findings(root, w):
    """R-E's SpecRef rule for ONE open WI, as a list of messages (the caller tags
    the rule and owns the warn/strict tier).

    Both halves of a `path#anchor` are resolved. Split out of `ssot_findings`
    when the anchor half landed (WI-354): folding it in line took that function
    past the complexity ratchet, and this module is already named as WI-280's
    next decomposition slice, so the rule gets its own unit rather than the
    monolith getting another sanctioned baseline entry.

    Implements: SR-157, LLR-077
    """
    spec = w["specref"]
    if not spec:
        return [
            "{}: open WI has no SpecRef (name its spec-of-record: "
            "docs/specs/WI-###.md or a doc#anchor)".format(w["id"])
        ]
    pathpart, _, frag = spec.partition("#")
    pathpart, frag = pathpart.strip(), frag.strip()
    if not pathpart:
        # A bare `#anchor` names no document, so there is nothing to resolve it
        # against. This returned CLEAN both before and after WI-354 — a hole
        # 131-REVIEW-A found by driving the rule rather than reading it, and the
        # one shape that made "both halves resolve" untrue as written.
        return [
            "{}: SpecRef {!r} has no path — a SpecRef names a document "
            "(docs/specs/WI-###.md or a doc#anchor), not a bare "
            "fragment".format(w["id"], spec)
        ]
    target = root / pathpart
    if not target.exists():
        return [
            "{}: SpecRef {!r} does not resolve to an in-repo file".format(w["id"], spec)
        ]
    if not target.is_file():
        # A directory exists but is not a spec-of-record; `exists()` alone let one
        # through (same review). Measured before landing: no live row names one.
        return [
            "{}: SpecRef {!r} names a directory, not a document".format(w["id"], spec)
        ]
    if not frag:
        return []
    if spine_carrier.names_carrier(pathpart, SN_CSV, spine_carrier.NEED_CARRIERS):
        ids = spine_carrier.need_ids(spine_carrier.load_needs(target))
        hint = _kitspine.registry_row_hint(ids, frag)
        msg = "{}: SpecRef {!r} names no such row in {} ({})"
        return [] if frag in ids else [msg.format(w["id"], spec, pathpart, hint)]
    # The anchor half (WI-354). Matching check_docs' link rule exactly — compare
    # lowercased, markdown targets only — so the SAME reference cannot pass as a
    # SpecRef and fail as a link, which is how WI-326's truncated anchor survived.
    anchors = doc_anchors(target)
    if anchors is None or frag.lower() in anchors:
        return []
    near = nearest_anchor(frag.lower(), anchors)
    return [
        "{}: SpecRef {!r} names no such heading in {} ({})".format(
            w["id"],
            spec,
            pathpart,
            "did you mean #" + near + "?"
            if near
            else "no similar heading — the target may have been rewritten",
        )
    ]


#: R-A's `restructured` grammar: the WHOLE Deliverable, one line, naming the
#: successor(s) that absorbed this row's scope and nothing else. The form is
#: fixed rather than free prose because it is the only machine-readable half of
#: the lineage that lives on the ABSORBED row — the successor carries
#: `supersedes`, and this is what makes the pair checkable in both directions.
_RESTRUCTURED_DELIVERABLE_RE = re.compile(
    r"Restructured into WI-\d{3,}(?:, WI-\d{3,})*\."
)
#: ...and the two findings it can produce, as templates so the arm below reads
#: as its decision rather than as string assembly.
_RA_RESTRUCTURED_FORM = (
    "{}: status=restructured but the Deliverable is {!r} (it must be exactly one "
    "line, 'Restructured into WI-<successor>.' - several successors "
    "comma-separated - and nothing else)"
)
_RA_RESTRUCTURED_LINEAGE = (
    "{}: status=restructured names successor {} in its Deliverable, {}"
)


def _restructured_lineage_findings(w, lineage, statuses):
    """R-A's `restructured` arm: the Deliverable's grammar AND its MUTUALITY.

    An absorbed row's whole permanent record is the successor it names, so a
    Deliverable that reads as prose, or names a row that never claimed it, is
    a lineage that looks recorded and is not — the exact failure mode `partial`
    avoids by owing a docs/handbacks/ report instead. Two findings, both R-A
    (the same incoherent-handoff class: a reader landing on this row is sent
    somewhere that does not exist or does not agree):

    - the cell is not exactly `Restructured into WI-<id>[, WI-<id>...].`;
    - a named successor is not a DISTINCT FORWARD carrier: not a registry row,
      or the row itself, or named twice, or itself `restructured`, or its
      `Supersedes` cell does not name this row back.

    THE FORWARD-CARRIER ARMS ARE THE POINT, not padding on the mutuality check.
    Existence plus a backlink proves the pair agree; it does not prove the
    reader gets anywhere. A row naming ITSELF satisfies both (its own
    `Supersedes` names it) and is a record that points at the record. A
    successor named TWICE reads as two carriers where there is one. A successor
    that is ITSELF `restructured` sends the reader to a second archived row —
    and mutual pairs (A absorbed by B, B absorbed by A) are exactly that arm
    twice, so both cycle shapes fall out of these two refusals and lineage can
    never be a loop or a chain: the absorbing row is the live thread.

    Liveness is otherwise deliberately "is a registry row", not "is still open":
    a successor that later closes `done` (or `cancelled`, or `partial`) must not
    turn its predecessor's archived record into a red. `restructured` is the one
    terminal that is excluded, because it is the one that redirects again.
    """
    text = w["deliverable"].strip()
    if not _RESTRUCTURED_DELIVERABLE_RE.fullmatch(text):
        return [("R-A", True, _RA_RESTRUCTURED_FORM.format(w["id"], text))]
    out = []
    named = re.findall(r"WI-\d+", text)
    for succ in dict.fromkeys(named):
        why = _restructured_successor_refusal(w, succ, named, lineage, statuses)
        if why:
            out.append(
                ("R-A", True, _RA_RESTRUCTURED_LINEAGE.format(w["id"], succ, why))
            )
    return out


def _restructured_successor_refusal(w, succ, named, lineage, statuses):
    """Why one named successor is not a distinct forward carrier, or None.

    Ordered cheapest-first and self before existence, so the row that names
    ITSELF is told that rather than being told its own `Supersedes` cell
    disagrees with itself."""
    if succ == w["id"]:
        return (
            "but that is this row itself - a restructured row's record must "
            "point FORWARD, at the row that absorbed it"
        )
    seen = named.count(succ)
    if seen > 1:
        return "but it is named {} times - each successor is named once".format(seen)
    if succ not in lineage:
        return "but no such work item exists"
    if statuses.get(succ) == "restructured":
        return (
            "but {} is itself restructured - lineage does not chain, so name "
            "the row that absorbed {} instead".format(succ, succ)
        )
    if w["id"] not in lineage[succ]:
        return (
            "but {}'s Supersedes cell ({}) does not name it back - the "
            "lineage must be mutual".format(succ, ";".join(lineage[succ]) or "empty")
        )
    return None


def ssot_findings(wis, root):
    """The work-item registry's coherence findings (R-A + R-E) + the
    unknown-status lint, each as `(rule, hard, message)`.

    `hard=True` (R-A only) is an ERROR at every run — the incoherent-handoff
    rule. R-E is warn-first; the caller promotes it to an error under `--strict`.
    Kept OUT of `validate()` so the dashboard renderer (`gen_trajectory`, which
    imports `validate`) shares the same registry read. R-B/R-C (open-WI status
    repetition) are retired (WI-180); R-D's done-id rule is RESTORED separately in
    `status_forward_only_findings` (WI-200), kept out of here so it reads the
    status.md text rather than the registry rows.

    Implements: SR-157, LLR-077
    """
    out = []
    lineage = {w["id"]: w.get("supersedes") or [] for w in wis}
    statuses = {w["id"]: w["status"] for w in wis}
    for w in wis:
        st = w["status"]
        # (The `status-vocab` and `blocked-ref` rules retired with the CSV home
        # at Phase 5: status is the spec's DIRECTORY, so an unknown status is a
        # loader refusal before any row exists. `blocked` had been DERIVED as
        # queued+blockref; with the blockref vocabulary retired at WI-553/OI-70
        # nothing produces it, so no row can reach either rule.)
        # R-A: Deliverable non-empty IFF the WI is TERMINAL — with `partial`
        # exempt, and the exemption is the rule working rather than a hole in
        # it. What R-A is FOR is that a terminal row carries a permanent
        # backward record: a `done` WI's Deliverable records what shipped, a
        # `cancelled` WI's records the reason it never will (WI-267).
        #
        # A `partial` close carries that record too, and carries it BETTER: an
        # immutable per-close report under docs/handbacks/ with the commit
        # range, what was and was not delivered, the keep/discard split and who
        # decides it. Demanding a Deliverable cell as WELL would be demanding a
        # second, weaker copy of a record that already exists — and it is
        # unsatisfiable by construction, because SR-144's whole point is that
        # an early close leaves the spec's DEFINITION byte-identical ("scope
        # definitions never change; only whether they were fully delivered").
        # A rule no honest close can satisfy is not a rule; it is a red at
        # every run, and in the loop it is worse than that — the dispatcher's
        # refresh reds, `_refresh_failed` quarantines the lane's work, the
        # retry reds again (the spec move is bookkeeping and exempt from the
        # revert) and the run dies. Driven at review.
        if st in TERMINAL_STATUSES and not w["deliverable"] and st != "partial":
            reason = _TERMINAL_DELIVERABLE_REASON[st]
            out.append(
                (
                    "R-A",
                    True,
                    "{}: status={} but the Deliverable is empty (a {} WI {})".format(
                        w["id"], st, st, reason
                    ),
                )
            )
        elif st == "restructured":
            out.extend(_restructured_lineage_findings(w, lineage, statuses))
        elif st not in TERMINAL_STATUSES and w["deliverable"]:
            out.append(
                (
                    "R-A",
                    True,
                    "{}: status={} (open) but the Deliverable is non-empty (an "
                    "open WI's Deliverable is filled only at close)".format(
                        w["id"], st
                    ),
                )
            )
        # R-E: an open WI names a resolvable SpecRef (path or path#anchor).
        if st in OPEN_STATUSES:
            out.extend(("R-E", False, msg) for msg in specref_findings(root, w))

    return out


# --- LLR-160: queue-conflict vetting (the mechanical pre-filter) --------
# Two rows are OPEN AT ONCE and overlap. Nothing here is an error: overlap is
# frequently correct (two rows may legitimately answer one SR from different
# sides), and a checker that cannot tell those apart must not block. What it CAN
# do is refuse to let the overlap be invisible — which is the whole failure this
# rung addresses, a queue that silently grows two rows for one job because
# nobody compared the mint against what was already queued.
#
# The ADJUDICATOR half of the vetting (does this row's scope contradict the
# spine, or another queued row's intent — and are these rows one work item
# wearing several ids?) is a judgement and lives in the `adjudicate-consolidate`
# prompt, run in a row the idle-station census mints over the cluster THIS
# function's findings help select. This is deliberately the cheap half, and it
# stays warn-only for the same reason: it is a pre-filter feeding a judge.

# Title tokens too common to carry meaning — a shared "the" is not a signal.
_TITLE_STOPWORDS = frozenset(
    {"a", "an", "and", "at", "for", "in", "of", "on", "the", "to", "with"}
)
# Jaccard over title token SETS. 0.8 is deliberately high: this rung's job is to
# catch the same job minted twice (near-identical wording), not to editorialize
# about two rows in the same area. A lower bar turns a useful warn into noise
# that gets ignored, which is worse than not having it.
_TITLE_SIMILARITY = 0.8


def _title_tokens(title):
    """A title's comparable token set: case-folded, punctuation-split,
    stopwords and pure-number tokens dropped (a WI id or a phase number is not
    subject matter).

    Implements: SR-157, LLR-160
    """
    words = re.split(r"[^0-9a-z]+", (title or "").lower())
    return {w for w in words if w and w not in _TITLE_STOPWORDS and not w.isdigit()}


_TITLE_CLIP = 90


def _clip_title(title):
    """A title bounded for a one-line finding (`kitlib.spine.clip_line`)."""
    return _kitspine.clip_line(str(title or ""), _TITLE_CLIP)


def queue_conflict_pairs(wis):
    """LLR-160, mechanical half: pairs of OPEN rows that overlap, as
    `[(first_id, second_id, finding)]` sorted by the id pair then the text.

    THE PAIR IS THE PRODUCT and the sentence is a rendering of it. Both callers
    need the same three signals and they need them at different grains:
    `queue_conflict_findings` below wants the lines (a warn a human reads), and
    `consolidate.clusters` wants the EDGES (which rows a consolidation census
    should hand one judge). Deriving the second by parsing the first would be
    the magic-substring fold — control flow recovered from prose — so the pair
    is returned and the prose is built from it, in that direction.

    Three signals, warn-only, each named with both row ids so the message is
    actionable without opening the registry:

      near-duplicate title  Jaccard >= 0.8 over title token sets — the same job
                            minted twice, which is what a mint that never
                            compared against the queue produces.
      shared SR-Refs        two open rows answering the same requirement. Often
                            correct; worth seeing.
      shared SpecRef        two open rows pointing at ONE spec. This is the
                            sharpest of the three: a spec is a row's
                            definition, so two open rows sharing one is either a
                            duplicate or a split that never got written down.
                            Sections are specs (`kitlib.registry.shared_spec`):
                            two different anchors in one file are two, and a
                            reference with no anchor covers the whole file.

    Deterministic order (sorted by the id pair), and each pair is reported once
    per signal, never once per direction.

    Implements: SR-157, LLR-160
    """
    open_rows = [
        w for w in wis if (w.get("status") or "").strip().lower() in OPEN_STATUSES
    ]
    tokens = {w["id"]: _title_tokens(w.get("title")) for w in open_rows}
    out = []
    for i, a in enumerate(open_rows):
        for b in open_rows[i + 1 :]:
            first, second = sorted((a["id"], b["id"]))
            ta, tb = tokens[a["id"]], tokens[b["id"]]
            union = ta | tb
            texts = []
            if union and len(ta & tb) / len(union) >= _TITLE_SIMILARITY:
                texts.append(
                    "{} and {} are both open with near-identical titles - one "
                    "job minted twice? ({!r} / {!r})".format(
                        first,
                        second,
                        # CLIPPED. A WI title in this repo is routinely a
                        # multi-thousand-character paragraph, so interpolating
                        # two raw ones produced a ~6 KB stderr line per pair —
                        # a warn nobody reads is a warn that does not exist.
                        _clip_title(a.get("title")),
                        _clip_title(b.get("title")),
                    )
                )
            shared_srs = sorted(set(a.get("srs") or ()) & set(b.get("srs") or ()))
            if shared_srs:
                texts.append(
                    "{} and {} are both open and both answer {}".format(
                        first, second, ";".join(shared_srs)
                    )
                )
            spec = _kitregistry.shared_spec(a.get("specref"), b.get("specref"))
            if spec:
                texts.append(
                    "{} and {} are both open and share one spec of record ({})".format(
                        first, second, spec
                    )
                )
            out.extend((first, second, text) for text in texts)
    return sorted(out)


def queue_conflict_findings(wis):
    """`queue_conflict_pairs` rendered as the warn lines — the shape every
    existing caller (the validator's report, the dashboard) reads. One
    derivation, two grains: see the pair producer above."""
    return sorted(text for _first, _second, text in queue_conflict_pairs(wis))


def spec_lifecycle_findings(root, wis):
    """The spec-lifecycle close-side rule **R-F** (WI-251) — the mechanical half
    of the close ritual R-E's open half leaves unstated: *Deliverable filled,
    `SpecRef` cleared, spec archived* (the `docs/specs/` README lifecycle). The
    one-sided enforcement is how this repo accreted 137 done rows with live
    SpecRefs before the rule existed. Two findings, both message-only (the
    caller tags `R-F` and owns the warn-plain / error-under-`--strict`
    promotion, the R-E warn tier — so a rotting spec surface cannot reach a
    green DevStg-Tests/DevStg-Impl gate while a plain commit stays warn-first):

      - a **terminal** WI (`done` or `cancelled`, WI-267) whose `SpecRef` is still
        set — the terminal transition clears it (the Deliverable + log carry the
        backward record; a `cancelled` row's reason lives in its Deliverable).
        The two terminals whose work CONTINUES in a successor — `partial` and
        `restructured` — are carved out and MAY keep the cell (see below);
      - a **live** `docs/specs/` file cited by no *open* WI — archive it to
        `docs/archive/specs/` (close date appended, WI ids noted) or point an
        open WI at it. A shared effort doc therefore archives only when its
        last open citer closes; `deferred`/`blocked` are open, so their specs
        stay, but `cancelled` is terminal, so a cancelled WI keeps no live spec. The
        scaffold boilerplate (README, any `-000` exemplar) is excluded by the
        `spec_interface_findings` idiom.

    Vacuous on a fresh scaffold (no done-with-SpecRef rows; only excluded
    boilerplate in `docs/specs/`). Whether the archived spec's durable content
    actually landed in a spine/architecture home first is the recorded
    Reviewer-tier gap (enforcement-audit.md).

    Implements: SR-157, LLR-097
    """
    out = []
    open_cited = set()
    for w in wis:
        spec = w["specref"]
        if not spec:
            continue
        if w["status"] in OPEN_STATUSES:
            open_cited.add(spec.split("#", 1)[0].strip())
        elif w["status"] in _SPECREF_MAY_STAY:
            # LLR-161: a `partial` row's SpecRef STAYS. R-F exists so a closed
            # row stops pointing at a live spec-of-record that a reader would
            # take as current — but partial work continues by MINTING A
            # SUCCESSOR, and the successor's `supersedes` lineage is worth
            # nothing if the thread it continues has already been cut. The spec
            # is still the record of what was asked for; only the delivery
            # question is closed.
            #
            # `restructured` (2026-09-02 restructure plan §1.6) carries the SAME
            # reason word for word: an absorbed row continues by a successor
            # carrying `supersedes`, and cutting the thread costs the same
            # lineage. So the carve-out is a MAY, not a must — the cell is
            # accepted either way, exactly as for `partial`: a consolidation
            # that clears it loses nothing the successor's own SpecRef does not
            # carry, and one that keeps it keeps the record of what was asked.
            open_cited.add(spec.split("#", 1)[0].strip())
        elif w["status"] in TERMINAL_STATUSES:
            out.append(
                "{}: status={} but SpecRef {!r} is still set (a terminal WI clears "
                "the SpecRef and archives the spec to docs/archive/specs/ — "
                "the {}/README.md lifecycle)".format(
                    w["id"], w["status"], spec, SPECS_DIR
                )
            )
    for path in _armed_specs(root):
        rel = "{}/{}".format(SPECS_DIR, path.name)
        if rel not in open_cited:
            out.append(
                "{}: live spec cited by no open WI (archive it to "
                "docs/archive/specs/ with the close date appended and the "
                "WI ids noted, or point an open WI's SpecRef at it)".format(rel)
            )
    return out


# --- WI-352: the completion reconciler ----------------------------------------
# A WI's `Status` is an ATTESTATION, and the owner ruled 2026-07-28 that it stays
# one rather than becoming derived: the evidence a deriver would read is the `WI:`
# commit trailer, but a trailer means "a commit CLAIMS this WI", not "the work is
# right" (WI-336's code landed while its row correctly stayed `queued`, because a
# review had refuted three of its claims — a deriver would have flipped it), and
# `draft`/`deferred`/`blocked`/`cancelled` are decisions, not outcomes. What was missing is
# not derivation but RECONCILIATION — the shape every other declared-vs-computed
# pair here already has (`spine_rules --check` recomputes and fails on drift;
# every generator carries `--check`). So this compares the declared cell against
# the completion evidence and reports DISAGREEMENT, never auto-flipping: an
# auto-flip would re-create exactly the false completion that WI-336 and
# `40c92f6` were both corrections of.
_DONE_BOX_RE = re.compile(r"^\s*[-*]\s+\[[xX]\]")
_OPEN_BOX_RE = re.compile(r"^\s*[-*]\s+\[ \]")
# THE SHARED HOME (0->A->B): the heading grammar and the Done-when test moved to
# `kitlib.registry` when `consolidate` became their third reader. Re-exported
# under the private names this module's own rules already use, so no call site
# moved and there is exactly one tolerant pattern in the kit.
_HEADING_RE = _kitregistry.HEADING_RE
# Checkboxes live under a "Done-when" heading by overwhelming convention (281 of
# 296 across every live and archived spec; re-derived by
# test_done_when_holds_the_overwhelming_majority_of_checkboxes rather than
# trusted here). The rest are migration checklists,
# which are STEPS rather than completion evidence and must not count — counting
# them would make a kit-version-bump doc read as an unfinished WI.
_DONE_WHEN_RE = _kitregistry.DONE_WHEN_RE


def _done_when_boxes(text):
    """`(ticked, unticked)` counted only within the spec's Done-when SECTION.

    Section, not "everything until the next heading": a Done-when that subdivides
    keeps its boxes, while a SIBLING heading at the same level ends it. That
    distinction is load-bearing — `docs/specs/WI-321.md` carries WI-324's
    remaining boxes under a sibling `## Split off, deliberately` heading, and
    folding those in would attribute one WI's unfinished work to another."""
    ticked = unticked = 0
    depth = None  # the Done-when heading's level, while we are inside its section
    for line in text.splitlines():
        heading = _HEADING_RE.match(line)
        if heading:
            level = len(heading.group(1))
            if _DONE_WHEN_RE.match(heading.group(2)):
                depth = level
            elif depth is not None and level <= depth:
                depth = None  # a sibling or shallower heading closes the section
            continue
        if depth is None:
            continue
        if _DONE_BOX_RE.match(line):
            ticked += 1
        elif _OPEN_BOX_RE.match(line):
            unticked += 1
    return ticked, unticked


def _own_spec(root, wid, archived=True):
    """A WI's OWN spec as `(path, rel)`, or `(None, None)`.

    Name-identified only — `docs/specs/WI-###.md`, then the archived
    `docs/archive/specs/WI-###.<date>.md` — and deliberately NOT whatever the
    `SpecRef` points at. A SpecRef may name a SHARED effort doc (WI-324 cites
    `docs/specs/WI-321.md`) or a non-spec record (`docs/log.md`,
    `docs/reviews/*.md`), and boxes in either are not attributable to the citing
    WI. Reading them anyway is how a reconciler invents a disagreement: measured
    here before this rule existed, following SpecRef reported WI-324's work
    "FINISHED" out of ticks WI-321 had made.

    `archived=False` restricts to the LIVE spec — the standing check's scope, for
    the reason recorded in `completion_reconciliation_findings`."""
    live = root / SPECS_DIR / "{}.md".format(wid)
    if live.is_file():
        return live, "{}/{}".format(SPECS_DIR, live.name)
    if not archived:
        return None, None
    archive = root / ARCHIVE_SPECS_DIR
    if archive.is_dir():
        matches = sorted(archive.glob("{}.*.md".format(wid)))
        if matches:
            return matches[-1], "{}/{}".format(ARCHIVE_SPECS_DIR, matches[-1].name)
    return None, None


def _wi_trailer_claims(root):
    """WI ids named by a `WI:` trailer on a commit reachable from HEAD.

    `None` off-git (no repo, or git unavailable), so the trailer signal is a
    silent no-op there rather than a finding — the stance every other git-reading
    check in this module takes."""
    out = _git(
        root, ["log", "--format=%(trailers:key=WI,valueonly,separator=,)", "HEAD"]
    )
    if out is None:
        return None
    return {
        token.strip()
        for token in out.replace("\n", ",").split(",")
        if re.fullmatch(r"WI-\d+", token.strip())
    }


def _live_spec_boxes(root, wid):
    """`(rel, ticked, unticked)` for a WI's own LIVE spec, or `None` when it has
    none. The one place a Done-when tally is read, so the standing check and the
    close-time check can never answer "is this finished" from different counts."""
    path, rel = _own_spec(root, wid, archived=False)
    if path is None:
        return None
    ticked, unticked = _done_when_boxes(
        path.read_text(encoding="utf-8", errors="replace")
    )
    return rel, ticked, unticked


def completion_reconciliation_findings(root, wis):
    """Disagreements between a WI's declared `Status` and its completion evidence,
    as `(kind, message)` pairs — the kind lets the caller tier them without
    pattern-matching on human-readable prose.

      - **spec-says-finished** — an OPEN row whose own spec has at least one
        ticked Done-when box and none left unticked. The WI-328 shape: six boxes
        ticked across six commits on 2026-07-27, the row still `queued` a day
        later, and because it was `SafetyClass=spine` the scheduler serialized the
        whole project behind finished work while the session told the owner a
        shipped migration was awaiting approval.
      - **spec-says-unfinished** — a `done` row whose own **live** spec still has
        unticked boxes and which no open WI cites (the same "no open citer" test
        R-F uses to decide when a spec may be archived).
      - **trailer-claims-it** — an OPEN row named by a `WI:` trailer on a commit
        reachable from HEAD.

    **Why the done side is scoped to LIVE specs**, measured rather than assumed:
    run over the archive it produced **40** findings (36 with no box ticked at
    all, 4 partly ticked) and neither class was actionable. Some are a self-referential terminal box (`Commit bar green; row
    done, spec archived` — untickable at the moment you would tick it); the rest
    are closes that never ticked. For a WI closed weeks ago, whose Deliverable and
    log entry carry the record, the only available action is cosmetic — and a
    check whose recommended action is "nothing" is a wall of warns, which is
    exactly how WI-308 recorded that a check earns its own ignore. The live window
    is where the disagreement is still resolvable, and the CLOSING COMMIT is where
    it is resolvable and visible at once: `staged_completion_findings` owns that
    moment. The 38 are real record-keeping debt, filed rather than suppressed.

    A fourth signal the row asked for — a `done` row with an empty `Deliverable` —
    is deliberately NOT reimplemented: **R-A already makes it a hard ERROR at every
    run**, strictly stronger than this tier, and a second weaker copy of a live
    rule is the duplication this kit's working agreement forbids.

    Never auto-flips. Vacuous until armed: no specs and no trailers, no findings.
    """
    out = []
    open_cited = {
        w["specref"].split("#", 1)[0].strip()
        for w in wis
        if w["status"] in OPEN_STATUSES and w["specref"]
    }
    for w in wis:
        boxes = _live_spec_boxes(root, w["id"])
        if boxes is None:
            continue
        rel, ticked, unticked = boxes
        if w["status"] in OPEN_STATUSES and ticked and not unticked:
            out.append(
                (
                    "spec-says-finished",
                    "{}: status={} but its spec {} reports the work FINISHED ({} "
                    "Done-when box(es) ticked, none left) — close the row or "
                    "untick what has not shipped; nothing here flips it for "
                    "you".format(w["id"], w["status"], rel, ticked),
                )
            )
        elif w["status"] == "done" and unticked and rel not in open_cited:
            out.append(
                (
                    "spec-says-unfinished",
                    "{}: status=done but its live spec {} still has {} unticked "
                    "Done-when box(es) and no open WI cites it — tick what "
                    "shipped or reopen the row".format(w["id"], rel, unticked),
                )
            )

    claims = _wi_trailer_claims(root)
    if claims:
        for w in wis:
            if w["status"] in OPEN_STATUSES and w["id"] in claims:
                out.append(
                    (
                        "trailer-claims-it",
                        "{}: status={} but a commit reachable from HEAD carries a "
                        "`WI: {}` trailer — a trailer CLAIMS the WI, it does not "
                        "attest the work, so this is a prompt to reconcile, never "
                        "a reason to close".format(w["id"], w["status"], w["id"]),
                    )
                )
    return out


def tier_completion_findings(findings):
    """Split reconciler findings into `(warn_only, gated)`.

    The tier is a property of the SIGNAL, so it is decided here beside the
    signals rather than as another branch in `main()`. Spec evidence is an
    attestation, so a row disagreeing with its own ticked boxes is a
    contradiction between two homes for one fact and belongs at the gate. A `WI:`
    trailer is not: it means "a commit CLAIMS this WI", which is the very
    argument the owner's 2026-07-28 ruling uses to keep Status declared — so it
    warns and never joins the exit code.

    DEVIATION from the WI row, which asked for the whole reconciler at the
    warn-plain / error-under-`--strict` tier. Taken on the row's own reasoning:
    WI-336's code landed while its row CORRECTLY stayed `queued`, a review having
    refuted three of its claims. An error-under-strict trailer rule blocks the DevStg-Impl
    gate for the length of that rework, and the only ways out are a false close
    or an untracked exception."""
    warn_only = [msg for kind, msg in findings if kind == "trailer-claims-it"]
    gated = [msg for kind, msg in findings if kind != "trailer-claims-it"]
    return warn_only, gated


def staged_completion_findings(root):
    """The close-time half of the reconciler (WI-352): a staged commit flipping a
    WI to `done` while its own spec still carries unticked Done-when boxes.

    This is the moment the standing check cannot reach, and the one that matters
    most. `40c92f6` exists because a box was ticked before it was true; WI-334 is
    the mirror, closed 2026-07-27 with five boxes never ticked — and by the time
    either is visible to a gate run the spec has been archived and only a cosmetic
    fix is left. Here the spec is still live, the author is still inside the
    change, and both homes for "is this finished" can be made to agree in one
    commit.

    Warning strings ([] when not applicable), a silent no-op off-git — the same
    shape as `staged_findings` and `critique_ratchet_findings`."""
    staged = _staged_wi_registry(root)
    if staged is None:
        return []
    _, cur_map, head_map = staged
    out = []
    for wid, _cur in _newly_closed(cur_map, head_map):
        boxes = _live_spec_boxes(root, wid)
        if boxes is None:
            continue
        rel, ticked, unticked = boxes
        if unticked:
            out.append(
                "{}: this commit closes it, but its spec {} still has {} unticked "
                "Done-when box(es) ({} ticked) — tick what shipped in THIS commit, "
                "or record in the log why the row closes without them; once the "
                "spec is archived only a cosmetic fix is left".format(
                    wid, rel, unticked, ticked
                )
            )
    return out


# --- status.md forward-only enforcement (WI-200; restores WI-180-retired R-D) --
# A word-bounded `WI-###` id token, so a `done` id embedded in status.md prose
# (a "CLOSED (WI-142)" narrative, a bullet) is found wherever it appears.
_WI_TOKEN_RE = re.compile(r"\bWI-\d+\b")
# The kit's generated-block marker idiom: gen_arch_map / gen_trajectory splice
# content between `<!-- BEGIN GENERATED ... -->` / `<!-- END GENERATED ... -->`
# HTML comments (arch_inventory reads the same `BEGIN GENERATED` sentinel). Its
# presence in status.md means the file is an integrator-generated snapshot.
_STATUS_GENERATED_RE = re.compile(r"<!--\s*BEGIN GENERATED", re.IGNORECASE)


def status_forward_only_findings(root, wis):
    """The status.md forward-only rule (WI-200) — restores the WI-180-retired R-D
    done-id check in a mode-aware form. `docs/status.md` holds only what must
    happen **next**; a closed WI's record lives in `docs/log.md`. So a `done` WI
    id appearing as a token in status.md is a finding — WARN plain, ERROR under
    `--strict` (DevStg-Tests+), the pre-WI-180 severity (the caller owns that promotion, the
    `spec_interface_findings` pattern).

    A repo-state rule evaluated every run (like R-A cross-reads the registry +
    status.md), not a staged-diff rule — under `--jobs N` only the serialized
    integrator publishes to the shared branch, so the invariant holds at every
    published tree.

    **Mode-aware (WI-180's direction preserved, not reversed):** when status.md
    carries the kit's generated-block marker (`<!-- BEGIN GENERATED ... -->`,
    spliced by `gen_trajectory.py --status`, WI-234) the rule stands down ONLY
    inside the marked block — its freshness is the `status-map` byte-compare
    step's job. The hand-authored remainder is exactly where done-ids accrete,
    so the token rule keeps policing it: a whole-file stand-down left the
    forward-only discipline enforced by nothing on a hybrid file (repo-review
    2026-07-21 H-5; the pre-WI-234 "no status.md generator exists yet" wording
    this docstring carried was stale).

    Only ids whose registry Status is `done` flag; open (queued/active/deferred/
    blocked) ids and unknown ids do not (an unknown id is R-E-adjacent). Vacuous
    when status.md is absent or the registry is placeholder-only (no real WIs ->
    no done ids); the `[checks] trajectory_check = false` opt-out is the caller's (it
    returns before any check runs). Returns finding-message strings.

    Implements: SR-157, LLR-075
    """
    path = root / STATUS_MD
    if not path.exists():
        return []
    text = path.read_text(encoding="utf-8", errors="replace")
    if _STATUS_GENERATED_RE.search(text):
        # Hybrid file: exempt the generated block(s) only (see the docstring);
        # the hand-authored remainder stays policed.
        kept, skipping = [], False
        for line in text.splitlines():
            if "<!-- BEGIN GENERATED" in line:
                skipping = True
            if not skipping:
                kept.append(line)
            if "<!-- END GENERATED" in line:
                skipping = False
        text = "\n".join(kept)
    done_ids = {w["id"] for w in wis if w["status"] == "done"}
    if not done_ids:
        return []
    present = sorted(set(_WI_TOKEN_RE.findall(text)) & done_ids)
    return [
        "{}: a `done` work-item id appears in {} — status.md is forward-only; a "
        "closed WI's record belongs in docs/log.md, not here (scrub the token, or "
        "make status.md a generated snapshot)".format(wid, STATUS_MD)
        for wid in present
    ]


# The terminal WON'T-INTEGRATE predecessor states a hard edge can never be
# satisfied by (OI-73 arm 4): `cancelled` (WI-267) AND `partial` — a lane that
# stopped early moves its spec to the terminal `partial/` and NEVER integrates
# `done` (LLR-161), so a live WI hard-depending on one waits forever exactly as
# it would on a cancelled row. `partial` was the WI-541 -> WI-540 strand that
# waited invisibly and was repaired by hand; extending this finding is the
# validator net that makes such a strand reported rather than silent.
# `restructured` joins them (2026-09-02 restructure plan §1.6): an absorbed row
# never integrates `done` either, so a live hard edge onto one waits forever
# exactly as it would on a cancelled or partial predecessor. The close that
# absorbs a row RE-POINTS its inbound edges to the successor, so this finding is
# the validator net behind that step — a re-point that was skipped or missed a
# dependent is reported rather than silently stranding the successor.
_DEAD_PRED_STATES = ("cancelled", "partial", "restructured")


def dead_dependency_findings(wis):
    """Surface a live WI that hard-depends on a terminal predecessor (WI-267,
    extended to `partial` by OI-73 and to `restructured` by the 2026-09-02
    restructure plan §1.6).

    A `cancelled`, `partial` or `restructured` WI is terminal — it will never
    integrate `done`, so an open successor whose hard edge points at it can
    NEVER become ready. The conservative decision (WI-267 design-decision 3) is
    to SURFACE the dead edge rather than let a terminal predecessor silently
    "satisfy" the dependency the way `done` does: the owner must re-home the
    successor's edge (an OI-70/OI-73 close now REPLACES inbound edges at the
    mint, and a consolidation close re-points them the same way, so a strand
    minted through either path never reaches here) or cancel it too. The scheduler already refuses to
    schedule such a WI (schedule.hard_preds_satisfied requires `done`, not merely
    terminal); this makes the same dead edge visible in the validator. WARN
    plain, ERROR under `--strict`. Soft (`~`) edges are advisory and never gate
    readiness, so they are exempt. Vacuous until a registry actually leaves a
    still-depended-on WI terminal.
    """
    by_id = {w["id"]: w for w in wis}
    out = []
    for w in wis:
        if w["status"] not in OPEN_STATUSES:
            continue
        dead = sorted(
            p for p in w["preds"] if by_id.get(p, {}).get("status") in _DEAD_PRED_STATES
        )
        if dead:
            out.append(
                "{}: open WI hard-depends on terminal WI(s) {} — a cancelled, "
                "partial or restructured predecessor never integrates `done` and "
                "so never satisfies a hard dependency; re-home the edge (an "
                "absorbed row's successor carries its scope) or close this WI "
                "too".format(w["id"], ";".join(dead))
            )
    return out


# (run_state_findings — the WI-115 stale-end-state warn over docs/run-state —
# retired at concurrency-restructure Phase 5 with the dispatcher that wrote
# that file; a stale parked state is unrepresentable when no file declares
# one.)


# `git -C <root> <args>` stdout on success, else None (git absent, not a repo,
# no such object). Every staged-mode git call degrades to None so the
# no-validation-delta warn is a silent no-op outside a git checkout.
#
# WI-521 slice 1 folded the BODY into `kitlib.git.git_out`, the declared one home
# for this pattern (`check.py` already aliases it the same way). It had been a
# fourth copy that the D-8/`OI-16` consolidation missed, and the reason it was
# missed is the `stdin` argument — it feeds a batch command (`cat-file
# --batch-check`), which is how the committed-mirror scan asks about many blobs
# in ONE subprocess instead of two per file, and that made it look like a
# different function rather than the same one. `stdin` is now a parameter there,
# defaulting to no input, so the two spellings are one.
_git = _kitgit.git_out


def _blame_row_times(root, rel_path):
    """`{row-id: committer-time-epoch}` for a registry, via a single
    `git blame --line-porcelain`. Returns {} on ANY git failure — no repo, an
    untracked/uncommitted file, an unparseable blame — so the backlog-staleness
    warn degrades silently off-git (never a false warn, never a crash). One
    subprocess per file keeps the cost bounded (WI-205: ≤2 blames).

    THE ROW'S SHAPE IS THE CARRIER'S, and getting that wrong is silent. Under
    CSV a row is ONE line whose leading field (up to the first comma) is its id.
    Under TOML a row is a TABLE spanning many lines, its id in the `[tier.ID]`
    header, and its time is the NEWEST commit over those lines — an amendment
    can touch any one of them. Read with the CSV rule a TOML registry yields a
    map keyed by `[requirement.SR-001]` and `title = "..."`, which no caller
    ever looks up: every lookup misses, the compare never fires, and the
    staleness warn passes because it found nothing to check."""
    live = spine_carrier.resolve(Path(root) / rel_path)
    if live is None:
        return {}
    blamed = spine_carrier.stem(rel_path) + live.suffix
    out = _git(root, ["blame", "--line-porcelain", "--", blamed])
    if out is None:
        return {}
    return (_blame_toml_times if live.suffix == ".toml" else _blame_csv_times)(out)


def _blame_lines(porcelain):
    """`(committer_time, content)` per blamed line, in file order — the shared
    walk both carrier readers need. `--line-porcelain` repeats the full commit
    header for every line, so a `committer-time <epoch>` header always precedes
    its `\\t<content>` line."""
    committer_time = None
    for line in porcelain.split("\n"):
        if line.startswith("committer-time "):
            try:
                committer_time = int(line[len("committer-time ") :].strip())
            except ValueError:
                committer_time = None
        elif line.startswith("\t"):
            yield committer_time, line[1:]
            committer_time = None


def _blame_csv_times(porcelain):
    """One CSV line is one row; its id is the leading field."""
    times = {}
    for committer_time, content in _blame_lines(porcelain):
        token = content.split(",", 1)[0].strip()
        if token and committer_time is not None:
            times[token] = committer_time
    return times


_TOML_ROW_HEADER = re.compile(r"^\s*\[[A-Za-z_][\w-]*\.([A-Za-z]+-\d+)\]\s*$")


def _blame_toml_times(porcelain):
    """One TOML table is one row; its time is the NEWEST commit over its lines,
    the table header included. Newest rather than the header's own time, because
    an amendment edits a VALUE line and leaves the header untouched — taking the
    header's time would date every amended row to its creation and report
    nothing as stale."""
    times, current = {}, None
    for committer_time, content in _blame_lines(porcelain):
        header = _TOML_ROW_HEADER.match(content)
        if header:
            current = header.group(1)
        if current is None or committer_time is None:
            continue
        times[current] = max(times.get(current, committer_time), committer_time)
    return times


def _path_commit_time(root, rel_path, row_history=False):
    """The committer time (epoch int) of the last commit to touch `rel_path`, via
    `git log -1 --format=%ct`, or None (no repo, an untracked path, no history) —
    the SpecRef-target half of the staleness compare, degrading silently like
    `_blame_row_times`.

    `row_history=True` asks the question `git blame` answers for a CSV row, for a
    registry where one row is one FILE: *when was this work item's content last
    edited*, across the renames its status changes are. It adds two flags, and
    the pair was MEASURED rather than reasoned about, because the obvious single
    flag does not work:

      * `--follow` alone still answers 2000 for a spec created at t=1000 and
        `git mv`d at t=2000 — the rename commit touches the new path, so `-1`
        stops there whether renames are followed or not. `--follow` is what lets
        the log reach PAST the move at all, but on its own it changes nothing
        about the answer.
      * `--diff-filter=AM` alone also answers 2000 — without rename detection the
        move looks like an Add of the new path.
      * Together they answer **1000**: the pure rename is filtered out as `R`,
        and `--follow` carries the search back to the file's real last edit.

    A commit that moves AND edits the spec answers 1000 as well — git scores it
    `R<similarity>`, and `--diff-filter=AM` drops it like any other rename. That
    is the accepted blind spot (WI-362, owner ruling 2026-07-29: name it, do not
    build rename detection): re-affirmation must be a content edit at the SAME
    path, because a Title edit renames the spec file. Only a rewrite large enough
    to defeat rename detection reads as `A` and re-dates, so the re-dating of a
    renamed path is a similarity heuristic and never something to rely on.

    Without both, every status move silently resets the row's staleness clock —
    the trap docs/concurrency-restructure.md §7 names, though not by this cause.
    `--follow` accepts exactly one pathspec, which is why the folder mode pays
    one `git log` per OPEN row rather than one per registry."""
    args = ["log", "-1", "--format=%ct"]
    if row_history:
        args += ["--follow", "--diff-filter=AM"]
    out = _git(root, args + ["--", rel_path])
    if out is None:
        return None
    out = out.strip()
    if not out:
        return None
    try:
        return int(out)
    except ValueError:
        return None


def _spec_paths(work_dir):
    """`{wid: repo-relative POSIX path}` for every spec under `work_dir`, keyed
    off the FILENAME's id prefix. Reading the id from the name rather than the
    frontmatter costs no file reads and cannot disagree with the parsed row —
    `parse_spec_row` refuses a spec whose two ids differ."""
    out = {}
    for path in spec_files(work_dir):
        wid = "-".join(path.name.split("-")[:2])
        out[wid] = "{}/{}".format(WI_WORK, path.relative_to(work_dir).as_posix())
    return out


def _spec_row_times(root, work_dir, wids):
    """`{wid: committer-time-epoch}` for the named specs — the folder-registry
    counterpart of `_blame_row_times`, one `git log -1` per id, asking the
    blame-equivalent question (`_path_commit_time(row_history=True)`) so a status
    MOVE does not re-date a row that nobody re-validated.

    Only the ids the caller actually examines are looked up: the whole point of
    the blame form was one subprocess for the whole registry, and per-file logs
    over a 350-item backlog would trade that for 350. Degrades to a missing key
    (never a crash or a false warn) exactly like the blame form."""
    paths = _spec_paths(work_dir)
    times = {}
    for wid in wids:
        rel = paths.get(wid)
        if rel is None:
            continue
        when = _path_commit_time(root, rel, row_history=True)
        if when is not None:
            times[wid] = when
    return times


def _wi_row_times(root, open_wis):
    """`{wid: committer-time}` for the open WIs: one `git log` per open spec —
    a folder registry has no rows to blame. (The CSV-home `git blame` half
    retired with the CSV at Phase 5.)"""
    return _spec_row_times(
        root, spec_work_dir(root / WI_CSV), [w["id"] for w in open_wis]
    )


def _declared_packs(root):
    """`{CMP-ID: [pack token]}` — the Knowledge cells that resolve to a REAL
    pack file (`docs/knowledge/<name>.md`, or a direct path, with or without
    the `.md`). A Knowledge token that resolves to nothing (a skill name, a
    planned pack) is not a citation debt, so it never arms the warn."""
    packs = {}
    for r in spine_carrier.load(root / CMP_CSV, "CMP-ID"):
        cid = (r.get("CMP-ID") or "").strip()
        if not cid:
            continue
        resolved = []
        for token in _split_refs(r.get("Knowledge") or ""):
            candidates = (token, token + ".md", "docs/knowledge/" + token + ".md")
            if any((root / cand).is_file() for cand in candidates):
                resolved.append(token)
        if resolved:
            packs[cid] = resolved
    return packs


def _spec_text_for(work_dir, wid):
    for path in spec_files(work_dir):
        if path.name.startswith(wid + "-"):
            try:
                return path.read_text(encoding="utf-8", errors="replace")
            except OSError:
                return None
    return None


def knowledge_pack_findings(root, wis):
    """The WI-388 pack-citation warn (consumer 3 of the intake context block)
    — WARN-ONLY, never the exit code, not even under --strict (advisory is
    the block's contract): a hand-authored OPEN spec (queued/active) whose
    rows' components declare knowledge packs the spec never cites is building
    blind on rows whose how-knowledge is recorded. The join is the same
    LLR.Component -> CMP.Knowledge join `intake.context_block` makes,
    re-derived here under this module's F5 independence (the shipped hook
    imports no sibling). A minted row's `## Context` block cites the packs at
    mint, so minted rows satisfy the rule by construction — the warn reaches
    exactly the hand-authored residue. A pack is cited by its full token or
    its basename; vacuous with no CMP Knowledge cells or no resolving pack."""
    packs = _declared_packs(root)
    if not packs:
        return []
    sr_comps = {}
    for r in spine_carrier.load(root / LLR_CSV, "LLR-ID"):
        comp = (r.get("Component") or "").strip()
        if comp in packs:
            for sr in _split_refs(r.get("SR-Refs") or ""):
                sr_comps.setdefault(sr, set()).add(comp)
    findings = []
    work_dir = spec_work_dir(root / WI_CSV)
    for w in wis:
        if w["status"] not in ("queued", "active"):
            continue
        comps = sorted({c for sr in w["srs"] for c in sr_comps.get(sr, ())})
        owed = sorted({p for c in comps for p in packs[c]})
        if not owed:
            continue
        text = _spec_text_for(work_dir, w["id"]) or ""
        cited = any(p in text or Path(p).name in text for p in owed)
        if not cited:
            findings.append(
                "{}: component(s) {} declare knowledge pack(s) {} the spec "
                "never cites — read them before building (WI-388 context; "
                "advisory)".format(w["id"], ", ".join(comps), "; ".join(owed))
            )
    return findings


def backlog_staleness_findings(root, wis):
    """WI-205 — the backlog-staleness warn (warn-only, the WI-129 checker stance).

    Approving amended SN/SR/LLR/TC content never touches the open WI rows that
    cite it, so an incomplete backlog can silently drift out of sync with the
    requirement state it was filed against. For each open WI (queued/active/
    blocked — `deferred` and `done` are exempt) this compares when its registry
    row last changed against when each cited source last changed, and warns when a
    source is STRICTLY NEWER: the WI needs a driven re-validation against the
    amended requirement. Re-affirming is deliberately cheap — a content edit to
    the spec at the SAME path (frontmatter or body) re-dates the row and clears
    the warn (a *driven look*, not ceremony). Cited sources: each `SR-Refs` id (a
    row of system-requirements.toml) and the `SpecRef` target file — except a
    `SpecRef` into the open-items registry, which is clocked per cited open item
    (`_specref_staleness`, WI-790), so filing an unrelated item warns nobody.

    SAME PATH is a real limitation, not a turn of phrase, and the warn text says
    so. The row clock reads `--follow --diff-filter=AM` (`_path_commit_time`,
    row-history mode) so that a pure status MOVE cannot re-date a row nobody
    re-validated — the flag pair MEASURED at Phase 2b — and that filter drops a
    rename whatever else the commit did. Since the Title drives the spec
    FILENAME, re-titling a WI renames its file and does NOT clear the warn: a
    genuine re-affirmation carried by a Title edit reads as no re-affirmation at
    all. That is the accepted blind spot of the trade (WI-362, owner ruling
    2026-07-29: state it in the warn, do not build rename detection) — pinned by
    tests/test_wi_folder_loaders.py so changing it has to be deliberate.

    THE SOURCE CLOCK IS LINE-GRANULAR, WHICH THE CELL-CLASS SPLIT IS NOT, and
    that is a second stated limitation rather than a bug to be quietly widened.
    `_blame_row_times` takes the NEWEST commit over a row's lines; a `git blame`
    line time cannot tell an approved cell from a traced one, so writing an
    INFORMATIVE cell re-dates the row and warns every WI that cites it.
    MEASURED (WI-484 phase 2, 2026-08-22): the `hat_refs` backfill wrote 55 SR
    cells and raised seven such warns; at phase 5 one survived — `SR-163`, whose
    newest line is its `hat_refs = [...]`. Two fixes were examined and NEITHER
    is small (recorded so the next reader does not re-derive them):
    line-attribution of the blame to approved-class keys needs a quote-state
    parser for multi-line TOML values AND would silence a re-pointed
    `SN-Refs`/`Boundary-Refs`, which is traced but scope-BEARING — the exact
    change a citing WI most needs to re-validate against; and recomputing the
    clock through `split_changed_cells` over a rev range is exact but replaces
    this check's bounded cost (≤2 blames) with git work per open WI and
    inherits the amendment scan's approved-only population. Which traced cells
    are staleness-bearing is a new classification, i.e. a ruling, not a patch.
    Stated here on the WI-362 precedent (owner ruling 2026-07-29: name the blind
    spot, do not build the detection).

    NEVER joins the exit code — not even under `--strict` (a warn-tier checker
    feature mints no SR and gates nothing, WI-129/132; the caller prints these and
    keeps them out of `errors`). Best-effort and silent off-git: no git, an
    untracked registry, or an uncommitted (not-yet-in-HEAD) WI or SR row simply
    yields no comparison for the affected item — never a false warn. Bounded cost:
    at most two `git blame`s (the WI + SR registries) plus one `git log -1` per
    distinct SpecRef path of an open WI. In the spec-folder registry there are no
    registry ROWS to blame — each work item is its own file — so the WI half
    costs one `git log -1 --follow` per OPEN item (the only rows this check
    examines), never one per work item."""
    open_wis = [w for w in wis if w["status"] in BACKLOG_STALE_STATUSES]
    if not open_wis:
        return []
    wi_times = _wi_row_times(root, open_wis)
    if not wi_times:
        return []  # off-git / the registry is untracked — no basis to compare
    sr_times = _blame_row_times(root, SR_CSV)
    spec_time = {}  # SpecRef path -> commit time, memoized (bounds the git logs)
    out = []
    for w in open_wis:
        wi_time = wi_times.get(w["id"])
        if wi_time is None:
            continue  # the WI row is not yet in HEAD — no basis, skip silently
        for sr in w["srs"]:
            t = sr_times.get(sr)
            if t is not None and t > wi_time:
                out.append(
                    "{}: cites {} amended after the WI row was last touched — "
                    "{}".format(w["id"], sr, BACKLOG_REAFFIRM_HINT)
                )
        out.extend(_specref_staleness(root, w, wi_time, spec_time))
    return out


def _specref_staleness(root, w, wi_time, spec_time):
    """The SpecRef arm of the backlog-staleness warn for one open row. A
    `specref` into the open-items registry is clocked PER CITED ITEM (WI-790):
    the row is stale only when an open item it cites — its `needs` tokens and
    the reference's own `#OI-NNN` anchor — was edited after the row, never
    because some other item was filed in the same file. Any other target is
    clocked by its file. `spec_time` memoizes per path (and, for the registry,
    the row-time map under its own key).

    Implements: SR-148, LLR-299
    """
    pathpart = w["specref"].partition("#")[0].strip()
    if not pathpart:
        return []
    named, anchor = _registry_ref(w["specref"])
    if named:
        if OPEN_ITEMS_REL not in spec_time:
            spec_time[OPEN_ITEMS_REL] = _blame_row_times(root, OPEN_ITEMS_REL)
        times = spec_time[OPEN_ITEMS_REL] or {}
        cited = list(dict.fromkeys(w["oi_preds"] + [anchor.strip()]))
        return [
            "{}: cites {} amended after the WI row was last touched — {}".format(
                w["id"], oid, BACKLOG_REAFFIRM_HINT
            )
            for oid in cited
            if times.get(oid) is not None and times[oid] > wi_time
        ]
    if pathpart not in spec_time:
        spec_time[pathpart] = _path_commit_time(root, pathpart)
    t = spec_time[pathpart]
    if t is not None and t > wi_time:
        return [
            "{}: its SpecRef {} changed after the WI row was last touched — {}".format(
                w["id"], pathpart, BACKLOG_REAFFIRM_HINT
            )
        ]
    return []


# Mirror of wi_convert.SLUG_CHARS, duplicated here DELIBERATELY: this module is
# stdlib-pure with no wi_convert import, and adding one would mint a new
# cross-component seam just to read a number. tests/test_rule_sync.py pins the
# two equal, so drift is detectable rather than representable (the WI-462
# adversarial round's F3: the cap governs only the MINTED filename path, and a
# hand-filed spec could re-open the Windows MAX_PATH cliff unwatched).
_SLUG_CHARS_MIRROR = 30


def branch_length_findings(root):
    """Warn-only (2026-08-16b adversarial round, F3): a PRE-BRANCH spec whose
    filename stem exceeds what the minted path guarantees. dispatch derives the
    git branch from the on-disk stem VERBATIM (never re-slugified), so
    wi_convert.SLUG_CHARS caps only specs that were minted — a hand-filed
    queued/draft/deferred spec with a longer slug walks the same Windows
    MAX_PATH cliff WI-462 closed (measured there at 259/260 characters).
    Terminal and active states are exempt: their branch either exists already
    or never will. Never joins the exit code, even under --strict — the same
    warn-tier contract as every advisory in this module (WI-129/132)."""
    out = []
    for state in ("queued", "draft", "deferred"):
        d = Path(root) / "docs" / "work" / state
        if not d.is_dir():
            continue
        for p in sorted(d.glob("WI-*.md")):
            m = re.match(r"(WI-\d+)-", p.stem)
            if not m:
                continue  # the filename-carries-its-id rule reports that shape
            ceiling = len(m.group(1)) + 1 + _SLUG_CHARS_MIRROR
            if len(p.stem) > ceiling:
                out.append(
                    "{}: filename stem is {} chars (ceiling {}) — dispatch "
                    "derives the git branch from this stem verbatim, and past "
                    "the minted cap (wi_convert.SLUG_CHARS) a hand-filed name "
                    "re-opens the Windows MAX_PATH cliff WI-462 closed; "
                    "shorten the slug, keep the id prefix".format(
                        m.group(1), len(p.stem), ceiling
                    )
                )
    return out


def holdbyrename_findings(root):
    """A `docs/work/active/<branch>/` claim directory with NO matching git
    branch ref — the exact signature of a HOLD-BY-RENAME, which OI-70 BANS: a
    lane that must stop CLOSES PARTIAL (the only sanctioned stop), it is never
    parked by renaming its ref (`git branch -m ... -HELD`) while its claim stays
    on trunk. That mismatch is also the phantom head the scheduler/dispatcher
    disagree over: the row reads `ready` off the claim while the dispatcher
    silently skips it (no ref to resume), so the frontier's head is a lane the
    loop can never take.

    The claim-dir basename IS the branch short name (`integrate.claim` cuts
    `refs/heads/<branch>` for `active/<branch>/`), so the match is exact and the
    finding has no false-positive class: a lane mid-work always has its ref, and
    a closed lane has moved its specs out of `active/` — the only ref-less
    active claim is a rename-hold or a stranded leftover, both of which OI-70
    resolves by closing the lane (never by deleting the claim copy on trunk,
    which the trunk floor holds and no blessing releases).

    WARN at the commit bar, ERROR under `--strict` (the DevStg-Impl gate) — the
    warn-plain / error-under-strict tier the rest of this module's promotable
    findings ride (no new branch in `main`). Degrades silently off-git (a
    checkout with no history has no refs to match), the module's warn-tier
    contract."""
    active = Path(root) / WI_WORK / "active"
    if not active.is_dir():
        return []
    # Off-git: nothing to say. `rev-parse --git-dir` answers None only when git
    # cannot answer at all, so it separates "no repository" (degrade silently)
    # from "ref absent" (the finding) — which a per-ref `--verify` alone cannot,
    # since both return None.
    if _git(root, ["rev-parse", "--git-dir"]) is None:
        return []
    out = []
    for d in sorted(p for p in active.iterdir() if p.is_dir()):
        if not any(d.glob("WI-*.md")):
            continue  # an empty dir is a claim-machinery leftover, not a hold
        branch = d.name
        if (
            _git(root, ["rev-parse", "--verify", "--quiet", "refs/heads/" + branch])
            is None
        ):
            out.append(
                "hold-by-rename: claim directory {w}/active/{b}/ has no matching "
                "branch ref refs/heads/{b} — a lane parked by renaming its ref is "
                "BANNED (OI-70): restore the ref (rename it back, or `git branch "
                "{b} <sha>` at the claim commit, whose subject ends `-> active/{b} "
                "(bookkeeping)`), close the lane PARTIAL through the kit's own "
                "path (the handback report) and land that close through the merge "
                "slot. As it stands the scheduler reads this lane ready off the "
                "claim while the dispatcher can never resume it".format(
                    w=WI_WORK, b=branch
                )
            )
    return out


def _tests_dir(root):
    """The declared tests root (docs/stack.ini [paths] tests), default `tests` —
    the surface a real validation-logic change would touch."""
    return _stack_ini_get(root, "paths", "tests") or "tests"


def _wi_status_map(rows):
    """`{wid: {"status", "srs"}}` for the real (non-`-000`) rows of a WI CSV."""
    out = {}
    for r in rows:
        wid = (r.get("WI-ID") or "").strip()
        if WI_ID_RE.match(wid) and not wid.endswith("-000"):
            out[wid] = {
                "status": (r.get("Status") or "queued").strip().lower(),
                "srs": _split_refs(r.get("SR-Refs", "")),
            }
    return out


def _head_spec_status_map(root):
    """`{wid: {"status", "srs": []}}` at HEAD in the folder registry, or None when
    HEAD carries no `docs/work` (so the caller falls back to the CSV at HEAD).

    Derived from `git ls-tree -r --name-only HEAD` PATHS ALONE — no blob is
    read. In this registry the directory IS the status, so the tree listing
    already answers the whole question the CSV needed a `git show` and a parse
    for; one subprocess, no content, no size dependence on the backlog.

    One honest limit remains, benign for the close ratchets that consume this:
    `srs` is empty, because SR-Refs are content too. `_staged_wi_registry` fills
    that from the WORKING TREE, where the same file is unchanged unless this very
    commit touched it. (The second limit is GONE with WI-384: `archive/` used to
    collapse `done` and `cancelled` behind a frontmatter key no tree listing can
    read, so a HEAD-cancelled item read `done`. Each terminal now has its own
    directory, so paths alone answer shipped-or-cancelled exactly.)"""
    out = _git(
        root, ["ls-tree", "-r", "--name-only", "HEAD", "--", WI_WORK, WI_ARCHIVE_WORK]
    )
    if not out or not out.strip():
        return None
    prefixes = (WI_WORK + "/", WI_ARCHIVE_WORK + "/")
    statuses = {}
    for name in out.splitlines():
        name = name.strip()
        prefix = next((p for p in prefixes if name.startswith(p)), None)
        if prefix is None or not name.endswith(".md"):
            continue
        parts = name[len(prefix) :].split("/")
        status = SPEC_STATUS_DIRS.get(parts[0]) if len(parts) > 1 else None
        wid = "-".join(parts[-1].split("-")[:2])
        if status is None or not WI_ID_RE.match(wid) or wid.endswith("-000"):
            continue
        statuses[wid] = {"status": status, "srs": []}
    return statuses or None


def _chain_untouched(root, staged_names, *extra_dirs):
    """Whether the staged change set leaves the VALIDATION CHAIN alone.

    The shared tail of both no-validation-delta ratchets: a close that touches
    neither the TC registry nor the tests dir landed the fix in the code and not
    in what judges it. `extra_dirs` widens what counts as the chain for a caller
    that accepts another kind of evidence (the critique ratchet also accepts a
    rubric anchor), which is the ONLY way the two sites differed — so the shared
    rule lives here and the difference stays visible at the call."""
    prefixes = (_tests_dir(root).rstrip("/") + "/",) + tuple(extra_dirs)
    return not any(name == TC_CSV or name.startswith(prefixes) for name in staged_names)


def _staged_wi_registry(root):
    """`(staged_names, cur_map, head_map)` for a commit that stages the WI
    registry, or `None` when there is nothing for a `--staged` check to say.

    The preamble every close-time check re-derived: the staged name set, the
    HEAD copy of the registry, and both status maps. `None` covers all three
    no-op cases uniformly — no git context, no registry change staged (so
    nothing was closed here), and no HEAD copy (first commit / file absent) — so
    a caller degrades silently off-git without restating the reason.

    Extracted for WI-344, forced early by WI-352 adding a fourth copy. The
    reason is F5's own boundary and outlives the tool that once flagged it: the
    F5 sanction buys cross-SCRIPT copy-ability, so it never licenses a fourth
    copy of the same preamble INSIDE one module. (The duplication census that
    reported this one was torn down in D-7/WI-426; the extraction stands.)
    (The CSV-home line-diff half retired with the CSV at Phase 5;
    `_staged_spec_registry` is the one implementation.)"""
    staged = _git(root, ["diff", "--cached", "--name-only"])
    if staged is None:
        return None
    staged_names = set(staged.splitlines())
    return _staged_spec_registry(root, staged_names, spec_work_dir(root / WI_CSV))


def _staged_spec_registry(root, staged_names, work_dir):
    """`_staged_wi_registry`'s folder-registry half.

    "The registry changed" becomes "a spec under `docs/work/` is staged", read
    with `--name-status` so a RENAME is visible as one record: a status change in
    this registry IS a rename, and `R<score>  queued/WI-360-x.md
    complete/WI-360-x.md` is exactly what a CLOSURE looks like. The closure SET is
    still derived by `_newly_closed` from the two status maps rather than from
    the `R` records — one home for that fact, and it stays correct even when git
    reports a move as an unpaired delete + add (rename detection is a heuristic;
    the status maps are not).

    HEAD status comes from the tree listing (`_head_spec_status_map`); a HEAD
    with no `docs/work/` at all (a repo's first registry commit) has nothing a
    close-time check can compare, so it degrades to None. (The CSV `git show`
    fallback for the 2c migration commit retired with the CSV home at Phase 5
    — that commit is history now.) HEAD `srs` are filled from the WORKING TREE
    row of the same id: in this registry one work item is one file, so a
    commit that closes A leaves B's SR-Refs untouched, and reading them from
    disk costs nothing. What that cannot see is a commit closing A while also
    editing B's SR-Refs; it would judge A against B's *new* refs. That is a
    narrower blind spot than a silent no-op, which is what "paths alone" would
    otherwise buy here."""
    changed = _git(
        root,
        ["diff", "--cached", "--name-status", "--", WI_WORK, WI_ARCHIVE_WORK],
    )
    if changed is None or not changed.strip():
        return None
    cur_map = _wi_status_map(read_spec_rows(work_dir))
    head_map = _head_spec_status_map(root)
    if head_map is None:
        return None
    for wid, head in head_map.items():
        head["srs"] = cur_map.get(wid, {}).get("srs", [])
    return staged_names, cur_map, head_map


def _newly_closed(cur_map, head_map):
    """The WI ids this staged change flips to `done`, with their current rows —
    the transition all three close-time ratchets key off."""
    return [
        (wid, cur)
        for wid, cur in cur_map.items()
        if cur["status"] == "done" and head_map.get(wid, {}).get("status") != "done"
    ]


def staged_findings(root):
    """The no-validation-delta warn (S0 ruling #2 corollary; warn-first).

    When a commit **closes** a WI (queued/active/deferred → done) that is a
    *follow-up* on an SR a previously-`done` WI already delivered (a shared
    `SR-Ref`), yet the staged change set touches neither the TC registry nor a
    file under the tests dir, the fix landed in the code but not the validation
    chain — so the same failure can recur. Returns warning strings ([] when not
    applicable). Compares the staged WI SPEC REGISTRY — the `docs/work/`
    directory-as-state tree `_staged_wi_registry` reads — against its HEAD
    version via git; any missing git context makes it a silent no-op (the hook
    has git; a gate run does not, and pays nothing). The registry has no CSV
    home to line-split any more: a status change is a RENAME between status
    directories, so both maps come from name listings (`--name-status` staged,
    `ls-tree` at HEAD) and never from parsing a row.

    Known false-positive, accepted at the WI-271 retirement (owner ruling
    2026-07-29): a follow-up WI whose chain change landed in its BUILD commit
    warns on its bookkeeping-only close commit — a moment's investigation, the
    lesser evil against a missed paper-close. Un-defer trigger: reopen (fresh
    WI) only if that noise erodes the signal — operators reflexively
    dismissing the warn. The footprint-aware widening is designed and ready in
    docs/archive/specs/WI-271.2026-07-29.md."""
    staged = _staged_wi_registry(root)
    if staged is None:
        return []
    staged_names, cur_map, head_map = staged

    prev_done_srs = {}  # SR id -> the done WI(s) that already delivered it
    for wid, h in head_map.items():
        if h["status"] == "done":
            for sr in h["srs"]:
                prev_done_srs.setdefault(sr, set()).add(wid)

    followups = []
    for wid, c in cur_map.items():
        was = head_map.get(wid, {}).get("status")
        if c["status"] == "done" and was != "done":
            shared = sorted(sr for sr in c["srs"] if sr in prev_done_srs)
            if shared:
                followups.append((wid, shared))
    if not followups:
        return []

    tests_prefix = _tests_dir(root).rstrip("/") + "/"
    if not _chain_untouched(root, staged_names):
        return []
    return [
        "{}: closes as a follow-up on {} (already delivered by a done WI) but "
        "the change set touches neither {} nor {} — the validation chain did "
        "not change (the fix must land in the chain, not just the code)".format(
            wid, ";".join(shared), TC_CSV, tests_prefix
        )
        for wid, shared in followups
    ]


# --- the acceptance record -------------------------------------------------
# WI-521 slice 1: the two-tree spine comparison and the snapshot mirror moved
# VERBATIM to the `acceptance_record` sibling (677 lines) — see that module's
# docstring for the boundary and why the requirements themselves asked for it.
# What is re-exported here is every name that block defined, under its former
# spelling, so no caller moved: `main` below still aggregates the four warn
# families, `intake.py` still reads `SPINE_CSVS`/`SPINE_TRACED_CELLS` and calls
# `staged_spine_amendments`/`staged_snapshot_findings`, `baseline_snapshot.py`
# still calls `split_changed_cells`/`_spine_rows_at`, and `trace.py` still calls
# `committed_snapshot_findings`. The private names are re-exported too, because
# the tests that pin this tier already reach them by their old spelling and a
# rename is not what this slice is measuring.
SPINE_CSVS = acceptance_record.SPINE_CSVS
SPINE_TABLE = acceptance_record.SPINE_TABLE
SPINE_COLUMN = acceptance_record.SPINE_COLUMN
SPINE_TRACED_CELLS = acceptance_record.SPINE_TRACED_CELLS
SPINE_APPROVED_CELLS = acceptance_record.SPINE_APPROVED_CELLS
HAT_REFS_CELL = acceptance_record.HAT_REFS_CELL
SNAPSHOT_DIR = acceptance_record.SNAPSHOT_DIR
SNAPSHOT_README = acceptance_record.SNAPSHOT_README
_APPROVED_TEXT = acceptance_record._APPROVED_TEXT
_spine_stem = acceptance_record._spine_stem
_spine_carriers = acceptance_record._spine_carriers
_spine_rows_at = acceptance_record._spine_rows_at
_spine_revs = acceptance_record._spine_revs
_snapshot_survives = acceptance_record._snapshot_survives
_snapshot_write_revs = acceptance_record._snapshot_write_revs
spine_cell_class = acceptance_record.spine_cell_class
traced_cells = acceptance_record.traced_cells
split_changed_cells = acceptance_record.split_changed_cells
staged_spine_amendments = acceptance_record.staged_spine_amendments
staged_spine_findings = acceptance_record.staged_spine_findings
staged_hat_refs_findings = acceptance_record.staged_hat_refs_findings
staged_snapshot_findings = acceptance_record.staged_snapshot_findings
committed_snapshot_findings = acceptance_record.committed_snapshot_findings


# The critique-loop ratchet (WI-068). A `Verification=Critique` SR and its latest
# CRITIQUE verdict file (`docs/reviews/*-CRITIQUE.md`, the S8 verdict format), in
# BOTH naming generations — serial `NNN-CRITIQUE.md` and the branch-scoped
# `WI-<n>-CRITIQUE.md` replacing it (concurrency-restructure §5.4, and
# `_latest_critique_file`, which reads both).
RUBRICS_DIR = "docs/rubrics/"
REVIEWS_DIR = "docs/reviews"
CRITIQUE_VERDICT_RE = re.compile(
    r"^\s*VERDICT:\s*(APPROVE|CHANGES-REQUESTED)\s*(?:findings\s*=\s*(\d+))?",
    re.I | re.M,
)

# The registry names its DESTINATION carrier; `spine_carrier.resolve` picks
# whichever of the two is live (repo-lock §8.1).
OPEN_ITEMS_REL = "docs/requirements/open-items.toml"
# A phase anchor appearing anywhere in a brief cell — the canonical
# `[<phase>]-[DevStg-<Rung>]` spelling (WI-498 slice 4) and the retired
# `[<phase>]-[reqs|tests]` / `[<phase>]-[g1|g2]` ones the committed briefs carry.
# Kept a SEPARATE pattern from PHASE_ANCHOR_RE because that one is anchored to the
# start of a Title and this one matches mid-cell; the accepted TOKEN SET is the
# same, and is held equal to it by a test rather than by this comment.
APPROVAL_ANCHOR_RE = re.compile(
    r"\[[^\]\[]+\]-\[(?:g[12]|reqs|tests|DevStg-[A-Za-z]+)\]", re.IGNORECASE
)
# The brief satisfies the rule only by naming an approval/hierarchy VIEW — a
# bare `trace.py --approve` command mention no longer counts (WI-146 REVIEW-A): a
# command can be unexecuted or wrong-scope, so it is not proof the generated view
# exists and is carried in the brief. WI-322 moved briefs from markdown sections
# to registry ROWS, so the proof is a path/link token in the cell rather than a
# markdown link — the rule is the same, its evidence shape follows the source.
# `ratif` stays in the token set deliberately (WI-499): the generated view still
# lives under `docs/ratify/` — the directory kept its name as a record home even
# though the retired-vocabulary rename covers everything else — so a real link
# still reads `docs/ratify/CURRENT.md` / `docs/ratify/<date>-*.md`. `approv` is
# matched too, for a link authored against the word the kit uses everywhere else.
APPROVAL_VIEW_RE = re.compile(
    r"(?:ratif|approv|hierarch)\w*[^\s]*\.(?:md|html|csv)|\]\([^)]*(?:ratif|approv|hierarch)[^)]*\)",
    re.IGNORECASE,
)


def approval_brief_findings(root):
    """Warn-first brief lint (WI-146b): an open-items row whose decision is a
    phase-anchor approval should point at the batch-scoped approval
    hierarchy view (`trace.py --approve <phase>`) instead of hand-copying registry
    rows. WARN only — never a gate fail (the house stance for prose surfaces,
    WI-129/132).

    Reads `docs/requirements/open-items.toml` since WI-322 retired the markdown
    surface; the brief text is the row's prose cells. Vacuous when the registry
    is absent or carries no approval brief, so a repo without the surface
    pays nothing."""
    path = root / OPEN_ITEMS_REL
    if spine_carrier.resolve(path) is None:
        return []
    out = []
    pending = _kitspine.open_items_at(spine_carrier.load(path, "OI-ID"), "pending")
    for oid, row in pending:
        body = " ".join(
            (row.get(k) or "")
            for k in ("OneLine", "Decision", "BlastRadius", "Options", "Recommendation")
        )
        # `approv` (not `ratif`, WI-499): live prose no longer uses the retired
        # spelling, so a freshly-authored row's own text is the "this decision
        # is about a human approval" signal now.
        is_approval = APPROVAL_ANCHOR_RE.search(body) and re.search(
            r"approv", body, re.IGNORECASE
        )
        if not is_approval or APPROVAL_VIEW_RE.search(body):
            continue
        out.append(
            "{}: a phase-anchor approval brief should name the batch-scoped "
            "hierarchy view (generate it with `trace.py --approve <phase>`) instead "
            "of hand-copying registry rows ({})".format(oid, OPEN_ITEMS_REL)
        )
    return out


def _load_critique_srs(root):
    """SR ids whose Verification is `Critique` (system-requirements.toml). Empty
    makes the critique ratchet vacuous — a repo with no perceptual SR pays
    nothing."""
    out = set()
    for r in spine_carrier.load(root / SR_CSV, "SR-ID"):
        sid = (r.get("SR-ID") or "").strip()
        if (
            sid
            and not sid.endswith("-000")
            and (r.get("Verification") or "").strip() == "Critique"
        ):
            out.add(sid)
    return out


def _latest_critique_verdict(root):
    """`(verdict, findings)` of the latest CRITIQUE file (`_latest_critique_file`,
    the shared selection rule), or `(None, 0)`. The verdict file is not WI-tagged,
    so 'latest overall' is the honest proxy for 'the in-scope critique' (a recorded
    gap — the loop critiques one scope at a time, so the newest verdict is live)."""
    f = _latest_critique_file(root)
    if f is None:
        return None, 0
    try:
        text = f.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None, 0
    m = CRITIQUE_VERDICT_RE.search(text)
    if not m:
        return None, 0
    return m.group(1).upper(), int(m.group(2) or 0)


def critique_ratchet_findings(root):
    """The lax-TC ratchet for the critique loop (WI-068; warn-first, the same
    no-validation-delta idea as `staged_findings`). When a staged commit **closes**
    a WI whose `SR-Refs` include a `Verification=Critique` SR, the latest CRITIQUE
    verdict is CHANGES-REQUESTED with findings, yet the staged set touches **neither**
    the TC registry, the tests dir, **nor** a `docs/rubrics/` file, the fix landed in
    the artifact but not the validation chain — so the same 'shipped it because
    nothing judged it' can recur. Returns warning strings ([] when not applicable).
    Any missing git context makes it a silent no-op, like `staged_findings`.

    Implements: SR-157, LLR-084
    """
    critique_srs = _load_critique_srs(root)
    if not critique_srs:
        return []
    verdict, findings = _latest_critique_verdict(root)
    if verdict != "CHANGES-REQUESTED" or findings <= 0:
        return []
    staged = _staged_wi_registry(root)
    if staged is None:
        return []
    staged_names, cur_map, head_map = staged

    closing = []
    for wid, c in _newly_closed(cur_map, head_map):
        shared = sorted(sr for sr in c["srs"] if sr in critique_srs)
        if shared:
            closing.append((wid, shared))
    if not closing:
        return []

    tests_prefix = _tests_dir(root).rstrip("/") + "/"
    if not _chain_untouched(root, staged_names, RUBRICS_DIR):
        return []
    return [
        "{}: closes on Critique-verified {} while the latest CRITIQUE verdict is "
        "CHANGES-REQUESTED ({} finding(s)), but the change set touches neither {}, "
        "{}, nor {} — harden the TC or add a rubric anchor (the fix must land in "
        "the chain, not just the artifact)".format(
            wid, ";".join(shared), findings, TC_CSV, tests_prefix, RUBRICS_DIR
        )
        for wid, shared in closing
    ]


# The render surface a perceptual (Verification=Critique) SR is judged against —
# WI-243. The dashboard facade and its direct render inputs (located beside this
# checker so the paths resolve under `--root` in this repo and a downstream
# scaffold alike) plus the optional meta-only render recipe. A change to any
# after the latest CRITIQUE means the approved perceptual stamp judged an older
# render, so the critique should re-fire.
_RENDER_RECIPE_REL = "scripts/dashboard-shots/shoot.mjs"


# WI-280 split the dashboard generator into a facade, shared display readers and
# renderer modules. P9R places HTML-only emitters under `rendering/`; the three
# shared inputs stay watched because changing their values changes the render an
# earlier perceptual verdict judged.
_RENDER_SHARED_GLOB = "traj_*.py"
_RENDER_PACKAGE_GLOB = "*.py"
_RENDER_PACKAGE = "rendering"


def _render_surface_paths(root):
    """Repo-relative render-surface paths that EXIST under `root`: the co-located
    dashboard facade and shared display inputs, its `rendering/` emitter
    package, and the render recipe if the repo carries one. A
    downstream without the meta-only recipe pays nothing for it; an unlocatable
    generator yields no path (the check then stays silent).

    Accepted warn-first boundary: layout-affecting values the family IMPORTS from
    modules OUTSIDE it (e.g. a display constant defined in this checker) are NOT
    watched — folding them in would fire the warn on every unrelated edit to those
    modules. The surface is the facade, its direct display inputs and emitters,
    plus the recipe; a render change that lands only in a more distant imported
    constant is a known, tolerated miss."""
    out = []
    here = Path(__file__).resolve().parent
    gen = here / "gen_trajectory.py"
    try:
        rel = gen.relative_to(root)
        if gen.is_file():
            out.append(rel.as_posix())
        for sib in sorted(here.glob(_RENDER_SHARED_GLOB)):
            out.append(sib.relative_to(root).as_posix())
        # The HTML-only emitters live under the package; sorted so the warn's
        # path list is deterministic.
        for sib in sorted((here / _RENDER_PACKAGE).glob(_RENDER_PACKAGE_GLOB)):
            out.append(sib.relative_to(root).as_posix())
    except ValueError:
        # the checker is not under root (unusual) — try the kit's two homes.
        for cand in (
            "project-trajectory/scripts",
            "scripts",
        ):
            if (root / cand / "gen_trajectory.py").is_file():
                out.append(cand + "/gen_trajectory.py")
                out.extend(
                    sorted(
                        s.relative_to(root).as_posix()
                        for s in (root / cand).glob(_RENDER_SHARED_GLOB)
                    )
                )
                out.extend(
                    sorted(
                        s.relative_to(root).as_posix()
                        for s in (root / cand / _RENDER_PACKAGE).glob(
                            _RENDER_PACKAGE_GLOB
                        )
                    )
                )
                break
    if (root / _RENDER_RECIPE_REL).is_file():
        out.append(_RENDER_RECIPE_REL)
    return out


def _critique_git_times(root, names):
    """`{filename: committer-time-epoch}` for the `docs/reviews` critique files git
    has history for, from ONE `git log --format=%ct --name-only` over the directory:
    the log walks newest-first, so the FIRST sighting of a path is its last-touched
    time — what `_path_commit_time` answers per path. {} on any git failure, the
    silent degrade every git call here makes. Batched rather than one
    `_path_commit_time` per file because this runs at the commit bar and the
    reviews dir only grows: 20 critiques cost ~1.3s in per-path subprocesses
    here, ~0.1s as one call, whatever the count."""
    out = _git(root, ["log", "--format=%ct", "--name-only", "--", REVIEWS_DIR])
    if out is None:
        return {}
    times = {}
    when = None
    for line in out.splitlines():
        line = line.strip()
        if not line:
            continue
        if line.isdigit():  # a %ct header line; a path line never is
            when = int(line)
            continue
        # `--name-only` prints REPO-root-relative paths, which need not equal
        # `root`-relative ones — match on the directory suffix, which also drops
        # the train-scoped `docs/reviews/<train>/` files (a deeper head).
        head, _, name = line.rpartition("/")
        if when is not None and head.endswith(REVIEWS_DIR) and name in names:
            times.setdefault(name, when)
    return times


def _latest_critique_file(root):
    """The LATEST `docs/reviews/*-CRITIQUE.md` path by last-change TIME, or None —
    the single selection rule shared by `_latest_critique_verdict` and the WI-243
    staleness check.

    Selection is by time, not by name, and the glob accepts BOTH naming
    generations: the historical serial `NNN-CRITIQUE.md` and the branch-scoped
    `WI-<n>-CRITIQUE.md` that replaces it (docs/concurrency-restructure.md §5.4 —
    a next-number counter is a race under concurrency). The two do not sort
    against each other at all, so the old highest-number rule could not survive
    the mix; it was also wrong on its own terms, a fresh critique filed under a
    LOWER number losing to a stale higher-numbered one. The ladder, per file:
    (1) the committer time of the last commit to touch it (`_critique_git_times`,
    one batched `git log`); (2) its filesystem mtime, when git answers nothing —
    uncommitted evidence, or a scaffold that is no git repo at all; (3) its
    filename, greatest wins, as the final tie-break, so equal times still select
    ONE file deterministically (two critiques in one commit, the batch case).
    Both time rungs are wall-clock epochs, so a committed and an uncommitted file
    still compare meaningfully. What time does NOT answer is SCOPE: the verdict
    file is still not matched against the WI under judgement — the recorded proxy
    `_latest_critique_verdict` documents."""
    d = root / REVIEWS_DIR
    if not d.is_dir():
        return None
    files = sorted(d.glob("*-CRITIQUE.md"))
    if not files:
        return None
    git_times = _critique_git_times(root, {p.name for p in files})

    def _when(path):
        t = git_times.get(path.name)
        if t is None:
            try:
                t = path.stat().st_mtime
            except OSError:
                t = 0
        return (t, path.name)

    return max(files, key=_when)


def critique_staleness_findings(root):
    """The perceptual re-fire finding (WI-243; git-time staleness like
    `backlog_staleness_findings`). A `Verification=Critique` SR is judged by a
    human/critic look recorded in `docs/reviews/*-CRITIQUE.md`, and that verdict
    never re-fires on its own — so once the dashboard *render surface* changes,
    the approval stamp is judging an older render. When a declared render-surface
    path last changed STRICTLY AFTER the latest CRITIQUE evidence, flag that the perceptual
    gate is stale and the dashboard critique should be re-run against the current
    render. Returns finding strings ([] when not applicable).

    TIERED severity (set by the caller): WARN at the commit bar, ERROR under
    `--strict` (the DevStg-Impl gate) — fail-closed per the owner's 2026-07-20 ruling, a
    stale render surface cannot reach a green gate; main() routes it through the
    strict-promotable findings loop (the R-E warn tier). Silent off-git
    and vacuous when the repo declares no perceptual SR (so a downstream repo
    without a `Verification=Critique` SR — none ship — pays nothing at either
    tier), carries no CRITIQUE evidence, or exposes no locatable render surface.
    Bounded cost: one `git log -1` for the evidence plus one per declared
    render-surface path. By construction (git-time, not a render diff) it fires
    on ANY commit touching a render-surface path — a data-only or comment-only
    edit to the generator flags even with zero visual change — the
    false-positive-over-false-negative trade the sibling `backlog_staleness`
    also makes."""
    critique_srs = _load_critique_srs(root)
    if not critique_srs:
        return []
    evidence = _latest_critique_file(root)
    if evidence is None:
        return []
    try:
        ev_rel = evidence.relative_to(root).as_posix()
    except ValueError:
        ev_rel = REVIEWS_DIR + "/" + evidence.name
    ev_time = _path_commit_time(root, ev_rel)
    if ev_time is None:
        return []  # uncommitted / off-git evidence — no basis, silent
    newer = [
        rel
        for rel in _render_surface_paths(root)
        if (_path_commit_time(root, rel) or 0) > ev_time
    ]
    if not newer:
        return []
    return [
        "{} (Verification=Critique) last judged by {} but the dashboard render "
        "surface changed after it ({}) — re-run the dashboard critique against the "
        "current render (the shoot.mjs matrix) and record a fresh "
        "docs/reviews/*-CRITIQUE.md".format(
            ";".join(sorted(critique_srs)), ev_rel, ";".join(newer)
        )
    ]


# --- A loop commit that changed a human-held status (SR-210) -----------------
# A changed status on a held rung is supposed to mean a human judged. The one
# observation that would show otherwise is such a change arriving in a commit
# the LOOP made, and the provenance floor makes every loop commit say so (its
# `Loop-Session` trailer). So the committed history can falsify the premise
# rather than the harness trusting it: each loop commit that moved a status
# its own tree's dial held is one advisory line. Advisory, never the exit code:
# the change has already landed, and what it asks for is a human's look.
POLICY_REL = "docs/process.toml"


def _commit_dial(root, rev):
    """The dial `rev`'s OWN policy file declares, read pure: a missing file, a
    missing dial or a legacy value is the most-held rung, and nothing prints -
    one line per visited commit would bury the report it rides."""
    text = _git(root, ["show", "{}:{}".format(rev, POLICY_REL)])
    try:
        policy = tomllib.loads(text) if text else {}
    except tomllib.TOMLDecodeError:
        policy = {}
    return _kitauthority.dial_from_config(policy)


def loop_held_status_findings(root):
    """One advisory per status move a loop commit made on a rung its own dial
    holds, naming the commit, the row and the rung.

    Visits every non-merge commit HEAD reaches - trunk's history, where the
    harness runs, and every lane commit merged into it - once each. A merge is
    skipped because its changes are those of the commits it merges, each
    visited on its own; a root commit is compared with the empty tree
    (`held_status.committed_status_moves`). Only a commit carrying a
    well-formed `Loop-Session` trailer is judged, and it is judged against the
    dial in ITS OWN tree, so raising the dial later re-judges nothing. `[]`
    off git.

    Implements: SR-210, LLR-249
    """
    log = _git(
        root,
        ["log", "--no-merges", "-i", "--grep=Loop-Session:", "--format=%H%x00%B%x1e"],
    )
    out = []
    for record in (log or "").split("\x1e"):
        sha, _nul, message = record.strip().partition("\x00")
        session = sha and _kitprovenance.parse_loop_trailer(message)
        if not session:
            continue
        dial = _commit_dial(root, sha)
        subject = message.strip().splitlines()[0] if message.strip() else ""
        moves = held_status.committed_status_moves(root, sha)
        for line in held_status.held_status_lines(dial, moves):
            out.append(
                "loop commit {} ({!r}, Loop-Session {}) moved {}, a rung its own "
                "approval level ({}) holds for a human".format(
                    sha[:10], subject, session, line, dial
                )
            )
    return out


def main():
    _utf8_console()
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument(
        "--root", default=".", help="repo root (default: current directory)"
    )
    ap.add_argument(
        "--strict",
        action="store_true",
        help="promote the registry coherence rules R-E (open-WI SpecRef resolves) "
        "and R-F (done WI clears SpecRef; a live spec has an open citer) "
        "from WARN to ERROR (wired at gate DevStg-Tests+; R-A always fails regardless)",
    )
    ap.add_argument(
        "--staged",
        action="store_true",
        help="run ONLY the warn-first no-validation-delta check over the staged "
        "commit (needs git; a silent no-op outside a git checkout)",
    )
    args = ap.parse_args()
    root = Path(args.root).resolve()

    if not read_trajectory_enabled(root):
        print(
            "check_trajectory: off (docs/process.toml [checks] trajectory_check) "
            "— nothing to check."
        )
        return 0

    # --staged is the commit-time no-validation-delta warn only: never blocks,
    # never re-runs the full validation (the trajectory step already did). The
    # warns, in the order they print (the count is deliberately not stated — it
    # went stale twice): the follow-up-on-a-done-SR ratchet, the critique-loop
    # ratchet (a WI closing under a CHANGES-REQUESTED critique without hardening
    # the chain), the WI-316 amend-without-flip warn (attested spine prose
    # changed without a fresh blessing) and its WI-484 Hat-Refs arm (the
    # substance moved, the perspective record did not), the mirror invariant
    # below, and the WI-352 close-time
    # completion warn (the row flips to `done` while its spec still has unticked
    # Done-when boxes — the only moment that disagreement is cheaply fixable,
    # since archival leaves nothing but a cosmetic edit).
    if args.staged:
        for w in (
            staged_findings(root)
            + critique_ratchet_findings(root)
            + staged_spine_findings(root)
            # ...and its second arm (WI-484 phase 5, OI-33's residue): the same
            # amendment set read for a row whose PERSPECTIVE cell stayed put
            # while its substance moved. Silent on a traced-only edit, which is
            # the regression the phase-2 backfill measured on a line-blamed
            # neighbour check.
            + staged_hat_refs_findings(root)
            # The MIRROR INVARIANT (snapshot design §F3): a commit that touches
            # the `last_approved` snapshot must leave every touched file
            # byte-identical to its live counterpart. This is the replacement
            # for the co-mutation guard D-1's anchor half would have needed —
            # and it is a stronger rule, because it makes "the only way to write
            # the snapshot is to copy the live file" a decidable property rather
            # than a convention. Vacuous until a snapshot exists.
            + staged_snapshot_findings(root)
            + staged_completion_findings(root)
        ):
            print("check_trajectory: WARN - {}".format(w), file=sys.stderr)
        return 0

    # Architecture-connectivity coverage (S5/WI-056; process.md §8) — warn-first,
    # never an exit-code change (even under --strict). Runs before the WI vacuity
    # return so a repo with modules + seams but no work items is still covered;
    # vacuous under [checks] interfaces_check = false or a ≤1-module arch-map.
    # ...and the multi-membership overlap advisory (WI-440; OI-14's third
    # do-not-wait) shares this WARN-ONLY loop rather than the component block
    # below: it reports the cross-component edges a multi-tagged endpoint
    # SILENCES, which is a question about the PARTITION rather than a defect in
    # the edge, and no partition has been ruled — so it must never join the exit
    # code, not even under --strict, which the component block would do.
    # ...and the seam-TC-coverage allowlist HYGIENE advisory (WI-488) shares it
    # for the same reason: a stale (now-covered, or now-retired) allowlist entry
    # is never itself a defect, so it must never join the exit code either — the
    # PROMOTABLE half of seam-TC coverage is `if_tc_coverage_findings`, below,
    # deliberately kept out of this loop.
    # ...and the loop-commit held-status report (SR-210) rides it too: the
    # change has already landed, so it asks for a human's look, never a red.
    for w in (
        interface_findings(root)
        + cross_component_advisories(root)
        + if_tc_allow_hygiene_findings(root)
        + codesymbol_crosscheck_findings(root)
        + loop_held_status_findings(root)
        + observation_rubric_findings(
            spine_carrier.load(root / "docs/test/test-cases.toml", "TC-ID")
        )
    ):
        print("check_trajectory: WARN - {}".format(w), file=sys.stderr)

    # Approval-brief hierarchy-view lint (WI-146b) — warn-first prose-surface
    # check: a `[phase]-[g1|g2]` approval brief should link the generated
    # batch-scoped hierarchy view. Vacuous without an approval brief.
    for w in approval_brief_findings(root):
        print("check_trajectory: WARN - {}".format(w), file=sys.stderr)

    # How-SW top-view right-sizing (WI-073/FB5) — WARN plain, ERROR under --strict
    # (DevStg-Tests+). Runs before the WI vacuity return too (the bound is a property of the
    # arch-map inventory + the component registry, independent of work items), so
    # a repo with a big arch-map and no CMP rows still trips even with no WIs.
    comp_errors = []
    for msg in component_findings(root):
        if args.strict:
            comp_errors.append(msg)
        else:
            print("check_trajectory: WARN - {}".format(msg), file=sys.stderr)

    # Seam-TC coverage promotion (OI-43 ruled (a), WI-488) — WARN plain, ERROR
    # under --strict (DevStg-Tests+), the component_findings idiom. Runs here
    # (not in the wi-scoped block below) for the same reason component_findings
    # does: the finding is a property of the arch-map + interfaces + TCs, not of
    # the WI registry, so a repo with no work items still gets it.
    if_tc_errors = []
    # ...and the armed definition gate (OI-67 slice 6) rides the same
    # severity: a row with no stated body is an interface with no definition.
    for msg in (
        if_tc_coverage_findings(root)
        + if_tc_allow_parse_findings(root)
        + contract_body_findings(root)
        + tc_tag_findings(root, _tests_dir(root))
    ):
        if args.strict:
            if_tc_errors.append(msg)
        else:
            print("check_trajectory: WARN - {}".format(msg), file=sys.stderr)

    # The one registry home (Phase 5): `docs/work/` specs. Any finding about
    # the REGISTRY ITSELF — a malformed spec, or a stray resurrected CSV — is
    # an integrity error, the same tier as a malformed id. (WI-349's
    # physical-line cell check retired with the CSV home: nothing reads the
    # folder registry line-wise, so a Deliverable body's newline is the format
    # working as designed; `cell_integrity_errors` survives for the spine
    # CSVs' own callers/tests.)
    registry_errors = []
    wi_rows = read_registry_rows(root / WI_CSV, registry_errors)
    wis, integrity = load_wis(wi_rows)
    integrity = registry_errors + integrity
    # The uncited-pending ERROR (WI-790) is evaluated BEFORE the vacuity
    # return: a repo whose only open item has no queued row to cite it is
    # exactly the repo that has no work items, and it must not read clean.
    oi_errors = uncited_open_item_findings(root, wi_rows)
    if not wis and not integrity:
        arch_errors = comp_errors + if_tc_errors + oi_errors
        if arch_errors:
            for e in arch_errors:
                print("check_trajectory: ERROR - {}".format(e), file=sys.stderr)
            print(
                "check_trajectory: {} finding(s) with no work items.".format(
                    len(arch_errors)
                ),
                file=sys.stderr,
            )
            return 1
        print(
            "check_trajectory: clean (no work items — placeholder-only or absent "
            "registry; vacuously clean)."
        )
        return 0

    # Phase archetype + phase-drop detector (WI-093) — WARN-FIRST, never an
    # exit-code change (like the connectivity coverage). Vacuous on a single-phase
    # repo with no `[phase]-[g*]` anchors (the meta case).
    for w in phase_findings(root, wis):
        print("check_trajectory: WARN - {}".format(w), file=sys.stderr)

    errors = (
        comp_errors
        + if_tc_errors
        + oi_errors
        + integrity
        + validate(wis, load_known_srs(root), load_known_ois(root))
        + open_item_specref_findings(root, wis)
    )
    # Specs act on declared interface boundaries (WI-191) — WARN plain, ERROR
    # under --strict (DevStg-Tests+); vacuous until a spec adopts an `## Interfaces` section.
    for msg in spec_interface_findings(root):
        if args.strict:
            errors.append(msg)
        else:
            print("check_trajectory: WARN - {}".format(msg), file=sys.stderr)
    # status.md forward-only (WI-200; the mode-aware R-D restoration) — WARN plain,
    # ERROR under --strict (DevStg-Tests+); yields to a status.md generated-block marker.
    for msg in status_forward_only_findings(root, wis):
        if args.strict:
            errors.append(msg)
        else:
            print("check_trajectory: WARN - {}".format(msg), file=sys.stderr)
    # Backlog-staleness (WI-205) — an open WI whose cited SR row or SpecRef target
    # was amended AFTER the WI row was last touched is re-flagged for a driven
    # re-validation. WARN-ONLY: it never joins the exit code, not even under
    # --strict (the WI-129 warn-tier-checker stance); silent off-git.
    # ...and the pack-citation warn (WI-388, consumer 3 of the intake context
    # block) rides the same WARN-ONLY tier: never the exit code even under
    # --strict — advisory is the block's contract, and minted rows satisfy it
    # by construction (their ## Context cites the packs), so it reaches
    # exactly the hand-authored residue.
    # ...as does LLR-160's queue-conflict pre-filter: overlap between
    # two OPEN rows is frequently correct, so this rung's whole contribution is
    # making it visible. Never the exit code, not even under --strict — a
    # checker that cannot tell a legitimate split from a duplicate must not
    # block on the difference.
    for msg in (
        backlog_staleness_findings(root, wis)
        + knowledge_pack_findings(root, wis)
        + queue_conflict_findings(wis)
        + branch_length_findings(root)
    ):
        print("check_trajectory: WARN - {}".format(msg), file=sys.stderr)
    # The SSOT coherence layer: R-A is always an error; R-E, the
    # unknown-status lint are WARN unless
    # --strict promotes them.
    findings = ssot_findings(wis, root)
    # Dead dependency (WI-267): an open WI hard-depends on a cancelled (terminal
    # WON'T-BUILD) predecessor it can never see satisfied. WARN plain, ERROR under
    # --strict — same warn-tier as R-E (no new branch in main).
    findings.extend(("dead-dep", False, msg) for msg in dead_dependency_findings(wis))
    # Perceptual re-fire (WI-243) — a Verification=Critique SR whose latest CRITIQUE
    # evidence predates a dashboard render-surface change is judging an older render.
    # WARN at the commit bar; **fail-closed under --strict** (the DevStg-Impl gate) per the
    # owner's 2026-07-20 ruling — a stale render surface cannot reach a green gate.
    # hard=False rides the same warn-plain / error-under-strict tier as R-E,
    # so main() gains no branch. Vacuous when no perceptual SR / evidence / render
    # surface (a downstream repo without a Verification=Critique SR — none ship —
    # pays nothing), silent off-git, and opt-out via [checks] trajectory_check.
    findings.extend(
        ("perceptual-stale", False, msg) for msg in critique_staleness_findings(root)
    )
    # Spec-lifecycle close side (WI-251, rule R-F) — done WI with a live SpecRef,
    # or a live docs/specs file no open WI cites. Same warn-plain / error-under-
    # --strict tier (no new branch in main); the R-E open-half's closing
    # counterpart.
    findings.extend(("R-F", False, msg) for msg in spec_lifecycle_findings(root, wis))
    # Hold-by-rename ban (WI-553, OI-70) — a ref-less `active/<branch>/` claim
    # directory. Same warn-plain / error-under-strict tier as R-E/R-F (no new
    # branch in main); silent off-git.
    findings.extend(
        ("hold-by-rename", False, msg) for msg in holdbyrename_findings(root)
    )
    # Completion reconciliation (WI-352) — the declared `Status` cell against the
    # spec's Done-when boxes and the `WI:` trailers. WARN plain, ERROR under
    # --strict, the same warn tier as R-E/R-F, EXCEPT the trailer signal.
    #
    # DEVIATION from the WI row, which asked for the whole reconciler at that
    # tier, taken on the row's OWN argument: it rules that Status stays an
    # attestation precisely because a trailer means "a commit claims this WI",
    # not "the work is right", and cites WI-336 — code landed, row correctly left
    # `queued`, a review having refuted three of its claims. Under an
    # error-under-strict trailer rule that legitimate state blocks the DevStg-Impl gate
    # for as long as the rework takes, and the only ways out are to close the row
    # falsely or to carry an untracked exception. Spec evidence is different in
    # kind: a ticked box IS an attestation, so its disagreement with the row is a
    # contradiction between two homes for one fact and belongs at the gate.
    warn_only, gated = tier_completion_findings(
        completion_reconciliation_findings(root, wis)
    )
    for msg in warn_only:
        print("check_trajectory: WARN - completion {}".format(msg), file=sys.stderr)
    findings.extend(("completion", False, msg) for msg in gated)
    for rule, hard, msg in findings:
        line = "{} {}".format(rule, msg)
        if hard or args.strict:
            errors.append(line)
        else:
            print("check_trajectory: WARN - {}".format(line), file=sys.stderr)
    if errors:
        for e in errors:
            print("check_trajectory: ERROR - {}".format(e), file=sys.stderr)
        print(
            "check_trajectory: {} error(s) in {}.".format(
                len(errors), registry_home(root)
            ),
            file=sys.stderr,
        )
        return 1

    done = sum(1 for w in wis if w["status"] == "done")
    # WI-267: `cancelled` (terminal WON'T-BUILD) rows are counted SEPARATELY,
    # never folded into `done`; surfaced only when present so the line stays
    # unchanged for the common no-cancellation registry.
    cancelled = sum(1 for w in wis if w["status"] == "cancelled")
    cancelled_note = ", {} cancelled".format(cancelled) if cancelled else ""
    print(
        "check_trajectory: clean ({} work item(s), {} done ({}%){}, graph "
        "acyclic).".format(len(wis), done, round(100 * done / len(wis)), cancelled_note)
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
