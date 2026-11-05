#!/usr/bin/env python3
"""The requirement spine's registry CARRIER (OI-12 / docs/repo-lock.md D-5).

ONE FILE PER TIER, id-keyed TOML:

    [requirement.SR-137]        # the id PREFIX is retained, and BARE
    title = "One policy home, with a checked shape"
    sn_refs = ["SN-028"]        # refs are typed arrays
    phase = 5                   # ints are ints
    requirement = \"\"\"...\"\"\"       # multi-line strings hold the prose cells

replacing the two carriers the spine shipped with — stakeholder needs as
markdown prose tables, SR/LLR/TC as CSV. `tomllib` is stdlib at the kit's 3.11
floor, and the kit already sanctions TOML in two homes (`docs/process.toml`,
the `+++` frontmatter of every `docs/work/` spec).

WHAT THE CARRIER BUYS THAT A CHECK USED TO. Three integrity rules stop being
code and become properties of the parse: a DUPLICATE ID is a decode error (the
id is the table key, and TOML forbids declaring one twice); a REF LIST is an
array, retiring the split-on-whitespace rule and with it the
`SN-001 and SN-002` -> "`and` is an orphan" defect; an EMPTY CELL is an ABSENT
KEY, so "unset" and "set to empty" stop being the same value.

ROWS COME BACK UNDER TODAY'S COLUMN NAMES (`SR-ID`, `Title`, `SN-Refs`, ...),
which is the whole point of this module existing: the carrier change is data
plus a loader, not a sixteen-module rename braided into a migration. D-3 is the
pass that renames things, and it renames them on this carrier afterwards.

WHY THIS IS A SIBLING MODULE AND NOT ELEVEN COPIES — OWNER RULING 2026-08-10,
AMENDING the F5 ruling that rejected a shared `_kitcommon.py` at WI-078. The F5 rule buys cross-script copy-ability, and it
is a good rule; it was written for small stable PLUMBING (a five-line CSV
loader, the argparse preamble), where a divergence between copies is visible
and cheap. This is not that. Measured before the ruling: two readers need all
28 columns, three need none, and the rest need between 1 and 20 — so the
duplicated form is ~300 lines of VOCABULARY across eleven modules, and its
failure mode is the one this repo keeps finding. A copy that has not learned a
column does not fail loudly; it returns a row with that cell missing, which
every consumer downstream reads as "the cell is empty". That is silent content
loss on the registries the kit exists to make trustworthy.

So the vocabulary gets ONE home and the readers import it. The cost is real and
is paid where it belongs: a kit re-sync copies this file alongside its
importers (ADOPTING.md §6 lists it), exactly as `trace.py` already ships with
`trace_text.py`. "Independently copyable" becomes "copyable with its declared
siblings", which is what the kit already practised and had not yet said.

PURE BY DESIGN, like `trace_text.py`: text in, rows out. No git, no argv, and
the only filesystem it touches is `resolve()`'s existence check — because the
one thing that MUST NOT be duplicated eleven ways is the dual-home refusal.
Every caller does its own reading, so a script keeps deciding its own I/O.

Contracts: IF-102, IF-104, IF-105, IF-106, IF-107, IF-108, IF-109, IF-110, IF-111, IF-112, IF-114, IF-118, IF-265, IF-119, IF-120, IF-122, IF-128, IF-133, IF-142, IF-178 — the seams this module declares (process.md §8; rows of record
in docs/requirements/interfaces.toml).

Contracts: IF-270 — the registry column vocabulary used by the case generator.

Contract IF-270: SPINE_COLUMN maps TOML registry keys to legacy column names. Together
    with kitlib.spine.REGISTRY_KEYS it supplies the complete ordered header of a
    registry tier, including cells a generated automated case leaves blank.

Contract IF-265: `load(path, "OI-ID")` supplies the scheduler's IF-073
    owner-registry rows under carrier-neutral column names. An absent file
    returns no rows; malformed content raises rather than publishing an empty
    queue. Both TOML and legacy CSV use the same load boundary.
Contract IF-102: the carrier's whole read surface, as trace.py imports it — and
    as the spine readers that JOINED it read it rather than each restating the
    vocabulary: acceptance_record, check_trajectory, gen_arch_map,
    plan_coverage, spine_rules, traj_status through check_trajectory's module
    attribute, check_test_first, rejudge, and retire. SPINE_TABLE maps an id
    column to its TOML tier table
    (SR-ID -> requirement, LLR-ID -> design, TC-ID -> test) and SPINE_COLUMN
    maps a carrier key to today's column name. rows_from_text(text, id_col,
    carrier) returns {id: row} under those names, or None — never {} — when a
    TOML text does not parse (the file-order, duplicates-kept read is the
    model registry's own row). stem(rel) strips the suffix and carriers(rel)
    names both suffixed paths, for an applicability test that has to span the
    cutover commit. resolve(path) returns the live carrier file and
    RAISES when a stem exists under both, rather than resolving by precedence;
    load(path, id_col) returns rows in file order, the shape csv.DictReader
    returns, [] when the registry is absent and SystemExit when it exists and
    will not parse. status_cells(text, tables=None) returns {row id: status}
    for every row of every table of a TOML text (or of the named tables only)
    that carries a `status` cell, or None when it does not parse. The `-000`
    example filter is NOT applied here.

Contract IF-104: check_doc_refs reads the spine through resolve() and load()
    for its Evidence-class pointer scan. resolve() is asked first, so an absent
    tier SKIPs cleanly instead of reporting every pointer in it as dangling;
    load() then hands back the TC and LLR rows under today's column names
    (Evidence, Module, CodeSymbol, TestRefs) whichever carrier is live, and
    raises rather than returning [] on a registry that exists and will not
    parse.

Contract IF-105: check_flows needs id UNIVERSES, not cells. load(path, id_col)
    supplies the SR/LLR/SN/TC keys a runtime-flow diagram's citations are
    validated against — under TOML an id is the table key, so this is the one
    consumer that needs no column vocabulary at all — and
    resolve(path, NEED_CARRIERS) says which need carrier is live, so a
    markdown-era needs registry is still found.

Contract IF-106: gen_okf exports the SR, LLR, TC and IF tiers through load()
    and the need tier through needs_for_root(root), which folds each need onto
    the core four with the `-000` examples dropped and the rows id-sorted.
    resolve(), stem(), CARRIERS and NEED_CARRIERS give each emitted source
    pointer the live carrier's own suffix, so a bundle file names the registry
    that exists rather than the one the migration is heading for.

Contract IF-107: gen_release_checklist groups the SR, TC, LLR and IF rows it
    lists by phase through load(), and reads the need tier through
    folded_needs(). Phase arrives as an int from the TOML carrier and as a
    string from CSV; value_to_cell renders both to the same cell text, so the
    grouping is identical either side of the carrier cutover.

Contract IF-108: plan_briefs reads the system-requirements and interfaces
    registries through load(root / rel, id_col) — the rows a dual-plan planning
    brief embeds VERBATIM. They arrive in file order under today's column names
    under either carrier; an absent registry is [], and one that exists and
    will not parse raises instead of quietly narrowing what the planner is told.

Contract IF-109: agent_brief reads SR and TC rows through load() for two
    purposes at once — the SR Verification cell decides whether a critique
    round is owed, and SR/TC prose is lifted verbatim into the session brief.
    Both take the same rows under the same column names, so a gate decision and
    the brief beside it can never be drawn from different vocabularies;
    agent_loop re-exports the behavior surface.

Contract IF-110: the unified mint reads the LLR, TC, IF, CMP and open-item
    registries through load() to decide what already exists before it places a
    new row; resolve(), stem(), CARRIERS and NEED_CARRIERS name the live
    carrier of each registry it reports on, and SPINE_TABLE names a tier's TOML
    table. This is the READ half of a read-modify-write — the mint also writes
    Status back — so the carrier must answer the read and the write about the
    same file.

Contract IF-111: traj_parse renders the dashboard's need tier from
    needs_for_root(root) — folded onto the core four, `-000` rows dropped,
    id-sorted, markdown emphasis stripped — and its row and off-spine tiers
    from load(root / rel, col). The fold has one home here, so two renderers
    cannot disagree about which needs exist.

Contract IF-112: check_docs holds the root README to the need tier through
    needs_or_refuse(path, text) and is_draft_need(need): the Must/Should
    coverage floor reads each need's own priority and status fields rather than
    a table's header text, under the carrier the file's suffix names, and a
    `.toml` file that does not parse refuses the run naming the file rather
    than reading as markdown. resolve(path, NEED_CARRIERS) decides whether there
    is a registry to hold the README to at all. The same module reads the
    open-items registry through resolve() and load() for its deferred-decision
    detector. Existence checking of cited ids stays check_docs' own whole-file
    scrape; only the floor and the open-items read cross this seam.

Contract IF-114: adjudicate_brief lists a red-TC brief's cases from
    load(root / rel, id_col): the TC rows (Verifies, Status, Method, Expected,
    Evidence) and the SR Requirement / LLR Detail text naming the obligation
    each case covers. Every cell it lists is REQUIRED — a row missing one
    refuses rather than rendering a dash. Read-only: nothing on this seam
    writes a registry.

Contract IF-118: the owner decision view reads docs/requirements/open-items
    through resolve() and load(), so it answers whichever carrier is live and
    the rows arrive under today's column names. load() returns [] only when the
    registry is genuinely absent and raises on one that exists and will not
    parse, so an unreadable decision queue can never be published as "0 pending
    decisions".

Contract IF-119: agent_route reads the model registry docs/agents through
    resolve() and rows_seq_from_text(text, id_col, carrier), so a pair row
    arrives under today's column names whichever carrier is live; the CSV
    branch keeps its own declared-header check, which TOML answers as a decode
    failure instead. An unparseable registry is an ERROR here, never an empty
    routing pool. The `# tag-rank:` line the router parses survives as an
    ordinary TOML comment.

Contract IF-120: trunk_step asks the carrier one question — resolve(path):
    which carrier of a registry is live — as the applicability predicate for
    its components and open-items freshness steps. None means the registry is
    absent and the step is inapplicable; a stem present under both carriers
    raises rather than being resolved by precedence.

Contract IF-122: check_need_form scans the need tier through load_needs(path),
    with resolve(path, NEED_CARRIERS) as its presence test, so it reads
    whichever of TOML or legacy markdown is live. Three outcomes stay distinct:
    an unreadable carrier REFUSES loudly (SystemExit), a registry present but
    yielding zero scannable need cells is VACUOUS, and an absent registry is
    the pre-scaffold clean skip.

Contract IF-128: baseline_snapshot resolves and reads every snapshotted
    registry through resolve(), carriers(), stem(), load(), load_needs(),
    CARRIERS and NEED_CARRIERS, so a snapshot root reuses each live resolver
    verbatim, carrier fallback included, and a snapshot taken under one carrier
    and read under another joins on the carrier-STRIPPED stem. Two refusals
    ride this seam: resolve() raises on a stem present under both carriers,
    load() on a file that exists and will not parse.

Contract IF-133: the hats audit worksheet reads the stakeholder-need tier
    through load_needs(), resolve(), NEED_CARRIERS, stem() and folded(), so
    each need arrives under today's column names whichever of TOML or legacy
    markdown is live. An ABSENT registry is [] and the audit prints VACUOUS; a
    carrier that exists and will not parse raises SystemExit, never zero rows.
    The roster read beside it goes to tomllib directly and is no tier of this
    carrier's.

Contract IF-142: gen_components reads all four of its source registries —
    components, system-requirements, low-level-requirements and interfaces —
    through load(), so each answers whichever carrier is live and the rows
    arrive under today's column names. The placement view passes
    keep_examples=False so a scaffold's inert `-000` rows never enter it; the
    "does this repo name any component at all" probe keeps them and filters by
    id itself.
Contract IF-178: `resolve(path, suffixes=CARRIERS) -> Path | None`, the live
    carrier file for a registry named under either suffix, read by the
    consolidation's spine digest so it hashes the same bytes every other spine
    reader loads. None when neither carrier exists, which the digest hashes as
    an empty registry; both carriers present is REFUSED by raising, never
    resolved by precedence, so a half-finished migration cannot be read.

Requirements: SR-147 (one machine-parseable carrier for the spine).
"""

import csv
import re
import io
import os
import tomllib
from pathlib import Path, PurePosixPath

# The one sibling this module imports, and it is the SHIPPED package rather than
# a peer: `kitlib` is import-clean of the rest of `scripts/` by assertion
# (tests/test_bootstrap.py), so binding it here keeps this module as cheap to
# copy as it was. It holds the schema of record the block below used to state.
from kitlib import spine as _kitspine

# The tier each registry's rows live under, keyed by the registry's ID COLUMN
# rather than by its path. A path carries a carrier suffix and therefore moves;
# the tier is the thing that does not.
# `SN-ID` JOINED 2026-08-17 (owner ruling 2026-08-17k, "Yes add in"). The need
# tier had no declared schema at all, which is the guard gap that let the
# shipped template ship without `tags` and let three fields accumulate for one
# axis — the census is what makes a fourth impossible to add quietly.
SPINE_TABLE = {
    "SN-ID": "need",
    "SR-ID": "requirement",
    "LLR-ID": "design",
    "TC-ID": "test",
}

# BATCH-2 (repo-lock.md §8.1): the OFF-SPINE registries the same OI-12 ruling
# covers, keyed the same way. `interfaces` and `components` JOINED at WI-443 —
# §8.1 held the first behind OI-14 and the second behind the components ruling,
# both of which rewrite what those rows ARE, and converting a registry twice is
# the one cost the sequencing avoided. Both are ruled (OI-14 part B, 2026-08-13),
# so each converted ONCE, with its new and retired columns in the same pass.
#
# THEY LIVE IN THIS MODULE RATHER THAN A SECOND ONE for D-6's reason exactly.
# A second carrier module would not duplicate the *vocabulary* — the columns
# differ — it would duplicate `resolve`, `rows_from_toml`, `load`, `columns`
# and the absent-vs-empty and None-vs-`{}` rules, which is ~150 lines of the
# behaviour this repo has already watched drift once per copy. The union maps
# below are what the readers consult; the SPINE_* names stay exactly what they
# were, so a spine consumer and its pins are untouched.
#
# THE FRAME REGISTRY IS THREE ENTRIES ON ONE PATH (WI-442). `external.toml`
# carries entities, boundary crossings and relationships in one file because
# they are one statement — but each is its own TIER with its own id column, so
# it joins the map three times and `load(external.toml, "B-ID")` returns exactly
# the crossings. Nothing in the loader changed to allow that: keying by id
# column rather than by path is what already made it work.
#
# THE NEEDS FILE HOLDS TWO TIERS THE SAME WAY (SR-189): its needs, and the
# stakeholder list whose rows those needs cite. `load(stakeholder-needs.toml,
# "STK-ID")` returns exactly the stakeholders, and the need readers below read
# `NEED_TABLE` alone, so a stakeholder's status never joins the needs' draft set.
#
# THE ASSUMPTIONS REGISTRY IS TWO ENTRIES ON ONE PATH (SR-191, SR-192):
# `assumptions.toml` carries the domain assumptions and the surrogates their
# fidelity assumptions name, each tier under its own id column.
# Implements: SR-189, SR-191, SR-192, LLR-215, LLR-218
OFFSPINE_TABLE = {
    "OI-ID": "open_item",
    "Id": "agent",
    "IF-ID": "interface",
    "CMP-ID": "component",
    "EXT-ID": "entity",
    "B-ID": "boundary",
    "REL-ID": "relationship",
    "STK-ID": "stakeholder",
    "DA-ID": "assumption",
    "SUR-ID": "surrogate",
}
REGISTRY_TABLE = dict(SPINE_TABLE, **OFFSPINE_TABLE)

# The carrier's keys -> today's COLUMN NAMES. STATED, never derived. Two
# reasons, and the second is the load-bearing one:
#
#   * no rule turns `sr_id` back into `SR-ID` and `sn_refs` into `SN-Refs`
#     without a list of which letter-runs are acronyms — a regex here would be
#     a rule nobody can predict from either side;
#   * a DERIVED mapping means renaming a column in code silently renames the
#     key on disk, orphaning that cell in every committed row. A stated map
#     makes the rename a visible edit to a reviewed table.
#
# This is the exact inverse of `migrate_carrier.KEY` (the writer), and
# tests/test_rule_sync.py pins the two as inverses so a column can never be
# renamed on one side of the conversion only.
# Implements: SR-193, SR-197, SR-198, LLR-222, LLR-232
SPINE_COLUMN = {
    "title": "Title",
    "sn_refs": "SN-Refs",
    # WI-442 — the SR-side BOUNDARY reference: which declared crossing(s) in
    # `external.toml` this requirement states an observable AT. Minted here
    # rather than in the re-tier because a checker cannot be written against a
    # column that does not exist; WI-451 slice 2 populates it. Named for the
    # tier it resolves into (`[boundary.B-##]`) and NOT `bif_refs`, which would
    # have kept the retired `BIF-###` id shape alive in a column name sitting
    # beside the `B-##` ids that replaced it.
    "boundary_refs": "Boundary-Refs",
    # WI-484 / OI-32 phase 0 — the HAT reference, on the SR and LLR tiers: which
    # declared perspective(s) in `docs/requirements/hats.toml` this row's content
    # is ATTRIBUTABLE to. Named `hat_refs` and not `hats_ref`/`concern_refs`, and
    # the choice is decided by precedent rather than taste. Against `hats_ref`:
    # every sibling in this map is `<singular tier noun>_refs` (`sn_refs`,
    # `boundary_refs`, `sr_refs`, `req_refs`), so `hats_ref` is the one form no
    # other column takes. Against `concern_refs`: `boundary_refs` was minted three
    # lines up under the rule "named for the tier it resolves into", and a cell
    # named for `concern` resolving against `[hat.NAME]` rows is exactly the
    # vocabulary hop that rule refuses. The value space is the ROSTER NAMES
    # (`SECURITY`, `UNATTENDED-OPS`) — `hats.py` already validates them and they
    # are what a composer holds; the prose `C-SEC-2` numbering that appears in
    # eight live rationale cells is NOT a second id space, and resolves nowhere.
    "hat_refs": "Hat-Refs",
    "sr_refs": "SR-Refs",
    "verifies": "Verifies",
    "requirement": "Requirement",
    "rationale": "Rationale",
    "acceptance_criteria": "AcceptanceCriteria",
    "permutations": "Permutations",
    "priority": "Priority",
    "verification": "Verification",
    "status": "Status",
    # the SN tier's own four, plus the `tags` cell the hats roster reads
    "need": "Need",
    "why": "Why",
    "acceptance": "Acceptance",
    "tags": "Tags",
    # The need's two POINTERS (SR-189, SR-190): the stakeholders whose outcome
    # it is, and the `path#anchor` document it was drawn from.
    "stakeholder_refs": "Stakeholder-Refs",
    "source": "Source",
    "phase": "Phase",
    "aspect": "Aspect",
    # The requirement's assumption citations, joint-delivery siblings and
    # waiver (SR-193), and its form (SR-194). `coincident` is declared ONCE,
    # here, and an interface row's waiver reads the same column: one key, one
    # column name, repo-wide (D-3).
    "da_refs": "DA-Refs",
    "delivered_with": "Delivered-With",
    "coincident": "Coincident",
    "form": "Form",
    "superseded_by": "SupersededBy",
    "lifecycle": "Lifecycle",
    "detail": "Detail",
    "module": "Module",
    "code_symbol": "CodeSymbol",
    "test_refs": "TestRefs",
    "level": "Level",
    "method": "Method",
    "expected": "Expected",
    "parameters": "Parameters",
    "automated": "Automated",
    "evidence": "Evidence",
    "tier": "Tier",
    "component": "Component",
    "notes": "Notes",
    # The test case's assumption evidence (SR-197) and an observation case's
    # declaration (SR-198): what it reads, how many days its result holds, how
    # it samples, and its sampling model as two flat cells.
    "assumption_refs": "Assumption-Refs",
    "inputs": "Inputs",
    "max_age": "MaxAge",
    "rubric": "Rubric",
    "trigger": "Trigger",
    "min_work_items": "MinWorkItems",
    "sampling": "Sampling",
    "sample_size": "SampleSize",
    "acceptance_rule": "AcceptanceRule",
}

# The batch-2 half of the same vocabulary. `title`/`status`/`tier`/`notes` are
# NOT repeated here: D-3 rules that a column name means one thing repo-wide, so
# the two halves union cleanly and a second entry for a shared column would be
# precisely the drift a single stated map exists to prevent.
OFFSPINE_COLUMN = {
    # open-items (the owner decision queue)
    "raised": "Raised",
    "one_line": "OneLine",
    "decision": "Decision",
    "blast_radius": "BlastRadius",
    "options": "Options",
    "recommendation": "Recommendation",
    "wi_refs": "WI-Refs",
    "ruled_date": "RuledDate",
    "ruling_ref": "RulingRef",
    # agents (the model routing registry)
    "family": "Family",
    "model": "Model",
    "version": "Version",
    "cmd_template": "CmdTemplate",
    "env": "Env",
    # interfaces (IF-###, process.md §8; WI-443 / OI-14 part B). `sr_refs`,
    # `rationale`, `component`, `notes` and `version` are already declared above
    # and are NOT repeated — one column name, one meaning, repo-wide (D-3).
    # There is deliberately no `status` entry for this tier: the IF `Status`
    # column RETIRED at the conversion, and `approval` is the one maturity field.
    #
    # `stability` RETIRED IN TURN at WI-442 (decision 4, owner 13u) and is gone
    # rather than deprecated-in-place: it was the whole input to rung 1's
    # `boundary_incomplete` predicate, and leaving a dead maturity column beside
    # the live one is precisely the two-words-one-meaning defect that retired
    # `Status`.
    #
    # `direction` + `this_project` + `counterpart` went the same way at WI-455
    # (OI-60 ruled (a), 2026-08-23), and the two cells below replace all three:
    # `provider` (optional — absent wherever `owner`→LLR→`module` derives it)
    # and `consumers` (the list the far side always was). Flow is no longer a
    # column: it is provider→consumers, read off the row.
    # `provider`, `req_refs`, `signal` and `signal_note` LEFT THE ROW at OI-67
    # (ruled (a), 2026-08-29): the row is one owner, its consumers and a typed
    # statement. A legacy carrier still carrying them keys them as themselves
    # (`KEY.get(col, col)`) and the schema tier names them — the same degrade
    # `Status`, `Stability` and `ThisProject` took before them.
    #
    # `owner` is the providing THING — a module path, a file or directory path,
    # or an `external:` party, the spelling `consumers` already uses — and no
    # longer a requirement id. The id-typed owner and the path-typed provider
    # were one fact in two spellings; the path is the one that survived, and
    # the spine link is DERIVED from it (the design rows whose `Module` names
    # it) rather than stated on the row.
    "owner": "Owner",
    # The closed vocabulary of what crosses (`kitlib.spine.IF_CHANNELS`), and
    # the optional short alphabet or schema pointer beside it. `channel`, not
    # `kind`: `kind` is the relationship tier's column, and one name carries
    # one meaning repo-wide (D-3).
    "channel": "Channel",
    "data": "Data",
    # OI-61's sub-question, sanctioned 2026-08-23: the OPTIONAL seam-tier
    # verification pointer. A `TC-###` or an `LLR-###`; empty means "verified in
    # its own right". It is not a second `Verification` column — the IF tier has
    # none — it is the pointer that makes "the parent functionality's tests
    # cover this" sayable at all.
    "verified_by": "VerifiedBy",
    # Q3: a constituent names the bundle that carries it. Optional by design —
    # most seams ride nothing, and an empty cell IS "this is not a constituent".
    "carried_by": "CarriedBy",
    # The far side names the DIRECTION: `requestors` put information into the
    # surface the owner defines, `consumers` take what it emits — exactly one
    # per row (OI-67, the owner's own addition).
    "requestors": "Requestors",
    "consumers": "Consumers",
    # `contract` LEFT the row with them once every definition had moved into
    # its owner's `Contract IF-###:` body: a legacy carrier still carrying it
    # keys it as itself, and `trace.interface_findings` names the row.
    "interface_from_external": "InterfaceFromExternal",
    "interface_to_external": "InterfaceToExternal",
    # A boundary interface's bridging assumptions (SR-211), DA ids. Its waiver
    # is the requirement tier's `coincident`, declared ONCE in SPINE_COLUMN.
    "bridged_by": "BridgedBy",
    # external (EXT-###/B-##/REL-###, the depth-0 frame; WI-442, sitting-2
    # §1R). Shared columns already declared above (`name`, `notes`) are NOT
    # repeated — one column name, one meaning, repo-wide (D-3).
    #
    # `direction` WAS THE WATCHED COLLISION IN THIS MAP, and WI-455 CLOSED IT
    # exactly as the note promised it would: the IF tier's Provides|Consumes
    # reading is gone (OI-60 ruled (a), 2026-08-23), so `Direction` now carries
    # ONE vocabulary on the carrier — the boundary tier's in|out|inout. The
    # honest residue, stated because it is still true: `Direction` carries a
    # THIRD vocabulary repo-wide that this file cannot see, `check_perf.py`'s
    # `lower-better`/`higher-better` off the perf-budget registry, which is not
    # on the carrier.
    "direction": "Direction",
    "class": "Class",
    "description": "Description",
    "entity": "Entity",
    "carries": "Carries",
    # `system` (WI-627, SR-187): the crossing's system of interest, one of
    # `kitlib.spine.SYSTEM_VALUES`. The inverse lives in migrate_carrier.KEY.
    "system": "System",
    # `mediates` (SR-195): the one entity a party acts for. A scalar entity id,
    # not a list. The inverse lives in migrate_carrier.KEY.
    "mediates": "Mediates",
    "from": "From",
    "to": "To",
    "kind": "Kind",
    "flow": "Flow",
    "absorbs": "Absorbs",
    # stakeholders (STK-##, SR-189): the declared frame entity a stakeholder is.
    # `name`, `description` and `status` are shared columns, declared above.
    "party": "Party",
    # the assumptions registry (DA-###, SUR-###; SR-191, SR-192). `status`,
    # `standing`, `name` and `description` are shared columns, declared
    # elsewhere in this map.
    "effect_at": "EffectAt",
    "assumption": "Assumption",
    "holds_when": "HoldsWhen",
    "obstacle": "Obstacle",
    "falsifier": "Falsifier",
    "accepted_risk": "AcceptedRisk",
    "realized_by": "RealizedBy",
    "obstacle_hats": "ObstacleHats",
    "emulates": "Emulates",
    # components (CMP-###, process-options.md "Component layer"; WI-443).
    "name": "Name",
    "category": "Category",
    "knowledge": "Knowledge",
    "standing": "Standing",
    "part_of": "PartOf",
}
REGISTRY_COLUMN = dict(SPINE_COLUMN, **OFFSPINE_COLUMN)

# THE PER-TIER SCHEMA — the schema of record — MOVED TO `kitlib/spine.py` at
# WI-448 slice 5 and bound here, so the three names below still resolve exactly
# as they always did and no consumer moved. WHY IT MOVED: the scaffolder writes
# one open-items row (`bootstrap.append_stack_checklist`) and had been carrying
# its own copy of that tier's key names, DECLARED as a duplicate on the premise
# that `bootstrap.py` can import no sibling — the premise D-8's inversion
# retired. `bootstrap.py` may import the shipped package and nothing else, so a
# vocabulary the scaffolder must agree with has to live there; and `kitlib.spine`
# is where it belongs on its own terms, being the module whose one sentence is
# "what one registry row's cells MEAN". The carrier READS registries; the schema
# is the vocabulary it reads them in, and every other reader is checked against
# it (tests/test_dogfood_sync.py). Adding a column to a tier is still a reviewed
# edit in ONE file — that file is now `kitlib/spine.py`.
SPINE_TIER_KEYS = _kitspine.SPINE_TIER_KEYS
OFFSPINE_KEYS = _kitspine.OFFSPINE_KEYS
REGISTRY_KEYS = _kitspine.REGISTRY_KEYS


# The row tiers moved CSV -> TOML; the need tier moved markdown -> TOML. Both
# lists are ordered NEW FIRST, because resolution prefers the destination
# carrier and falls back to the legacy one — never the other way round, or a
# half-finished migration keeps reading the file it was supposed to leave.
CARRIERS = (".toml", ".csv")
NEED_CARRIERS = (".toml", ".md")


def stem(rel_path):
    """A registry path with its carrier suffix removed, so one constant can
    name a registry across a carrier change."""
    return str(rel_path).rsplit(".", 1)[0]


def carriers(rel_path, suffixes=CARRIERS):
    """Both carrier paths a registry can appear under.

    An applicability test (`git diff --name-only` against a watched set) has to
    name BOTH or the cutover commit — which deletes the `.csv` and adds the
    `.toml` — matches neither name, and the check silently skips the one commit
    that rewrites every row it watches."""
    return [stem(rel_path) + s for s in suffixes]


def names_carrier(rel_path, registry, suffixes=CARRIERS):
    """Whether a root-relative spelling names one of `registry`'s carriers.

    Strip cell whitespace and normalize native path components, as R-E does
    when locating the referenced file. No filesystem dereference: backslashes
    remain filename bytes on POSIX and separators on Windows.
    """
    normalized = Path(os.path.normpath(str(rel_path).strip())).as_posix()
    canonical = Path(os.path.normpath(str(registry).strip())).as_posix()
    return normalized in carriers(canonical, suffixes)


def value_to_cell(value):
    """One TOML value as the cell text the CSV carrier held.

    The inverse of `migrate_carrier.cell_to_value`, and deliberately the same
    rules its `value_to_cell` writes by: a ref array re-joins on `;` — the
    separator the registries actually use, measured 271 of 271 at the cutover —
    and an int stringifies. A row read here is therefore cell-for-cell what the
    CSV row was, which is what lets every consumer stay unchanged and what lets
    the amendment guard's silence across the cutover mean something."""
    if isinstance(value, list):
        return ";".join(str(v) for v in value)
    return str(value)


def rows_from_toml(text, id_col):
    """`{id: row}` under today's column names, or None when `text` does not
    parse.

    An ABSENT key stays absent rather than being filled with `""`. That is the
    carrier's whole point — "unset" and "set to empty" stop being the same
    value — and it costs nothing downstream, because every consumer reads a
    cell as `.get(col) or ""`, so absent and empty compare equal where it
    matters and stay distinguishable where it does not.

    None (not `{}`) on a decode error, because the two are OPPOSITE claims.
    `{}` says "this registry had no rows", which for a baseline read means
    "re-bless everything with no diff" and for a gate means "nothing to check".
    A carrier that cannot be read is ABSENT, and the caller has to be able to
    tell the two apart rather than inheriting the reading that fails open."""
    try:
        tables = tomllib.loads(text)
    except tomllib.TOMLDecodeError:
        return None
    out = {}
    for rid, cells in (tables.get(REGISTRY_TABLE[id_col]) or {}).items():
        row = {id_col: rid}
        for key, value in cells.items():
            row[REGISTRY_COLUMN.get(key, key)] = value_to_cell(value)
        out[rid] = row
    return out


def nested_table_findings(text, id_col, rel=""):
    """One finding per row cell that is itself a TABLE — the shape an UNQUOTED
    DOTTED ID silently produces.

    TOML's table path is dot-separated and a bare key may not contain a dot, so
    `[agent.ANTHROPIC-OPUS-4.8]` written bare declares
    `agent."ANTHROPIC-OPUS-4"."8"`. The file parses, the registry loads, and the
    model row is simply GONE — replaced by a row called `ANTHROPIC-OPUS-4` whose
    only cell is a sub-table. Every value here passes through `value_to_cell`,
    which would stringify that sub-table into a cell nobody can read.

    The spine never met this (`SR-137` has no dot); the `agents` registry's ids are model
    versions and routinely do, which is why the carrier gained a rule
    (`migrate_carrier.toml_key` quotes what TOML will not take bare) and why
    the rule needs a reader-side check that a HAND edit cannot slip past.
    Refused rather than repaired, for `empty_value_findings`' reason: the fix is
    a two-character edit the author must make, and silently re-nesting the row
    would make the file and the loaded registry disagree about what it says."""
    try:
        tables = tomllib.loads(text)
    except tomllib.TOMLDecodeError:
        return []  # the caller's own parse reports this; one finding is enough
    out = []
    for rid, cells in sorted((tables.get(REGISTRY_TABLE[id_col]) or {}).items()):
        for key, value in sorted(cells.items()):
            if isinstance(value, dict):
                out.append(
                    "{}{}.{} is a TABLE, not a cell — an id containing a `.` "
                    "must be QUOTED in its table header "
                    '(`[{}."{}.{}"]`), or TOML reads the dot as a table '
                    "path and the row's real id disappears.".format(
                        rel and rel + ": ",
                        rid,
                        key,
                        REGISTRY_TABLE[id_col],
                        rid,
                        key,
                    )
                )
    return out


def rows_from_csv(text, id_col):
    """`{id: row}` from the CSV carrier.

    Parsed over the FULL text, never line-split: spine cells are long and
    RFC-4180 quoting spans lines. Callers strip a BOM first (adversarial-review
    F4 — `git show` preserves a committed BOM, and a BOM'd header glues to the
    first column name so every row hides). A leading `#` declaration header
    — the OI-67 marker and bodies a CSV owner carries — is skipped by the one
    shared reader, never read as the header row."""
    return {r[id_col]: r for r in _kitspine.csv_reader(text) if r.get(id_col)}


def rows_from_text(text, id_col, carrier):
    """`{id: row}` for the named carrier (`".toml"` / `".csv"`), or None when a
    TOML text does not parse. The `-000` template example rows are kept — the
    caller filters them, because `is_example` is trace_text's rule and this
    module does not own the spine's semantics, only its carrier.

    BY-ID, so a duplicated id under the CSV carrier collapses. That is correct
    for the one question this shape answers — "what did row X say at revision
    R" — and wrong for every question about the FILE, which is why the live
    loader goes through `rows_seq_from_text` instead."""
    text = text.lstrip("﻿")  # F4, as above
    if carrier == ".toml":
        return rows_from_toml(text, id_col)
    return rows_from_csv(text, id_col)


def rows_seq_from_text(text, id_col, carrier):
    """Rows as a SEQUENCE in file order, duplicates included — or None when a
    TOML text does not parse.

    THIS EXISTS BECAUSE THE BY-ID SHAPE DESTROYS AN INTEGRITY CHECK, and it did
    so silently. `{r[id_col]: r for r in DictReader(...)}` drops the first of
    two rows that share an id, so a duplicated id — the very first thing
    `--strict-integrity` is required to fail on — arrives at the checker as ONE
    row and the check passes. Under TOML a duplicate id cannot be written at
    all (it is a decode error, which is the carrier turning a check into a
    property); under the CSV fallback the check has to keep working, or a repo
    that has not migrated silently loses it.

    So the LIVE read preserves the file, and only the baseline read — which
    asks "what did row X say at revision R", a question that is by-id by
    construction — takes the mapping."""
    text = text.lstrip("﻿")  # F4, as above
    if carrier == ".toml":
        rows = rows_from_toml(text, id_col)
        return None if rows is None else list(rows.values())
    return [r for r in _kitspine.csv_reader(text) if r.get(id_col)]


def resolve(path, suffixes=CARRIERS):
    """The live carrier file for a registry, given a path under EITHER suffix.

    REFUSES both homes at once by raising, rather than resolving by precedence.
    That is the rule `bootstrap.py --migrate-config` already applies to the
    policy dials — "running with both homes live is REFUSED, not resolved by
    precedence" — and it exists for the same reason: a precedence rule means a
    half-finished migration keeps working while quietly reading the stale half,
    so the conversion is never actually finished and nobody finds out. Returns
    None when neither exists, which is the pre-scaffold case and is not an
    error here."""
    import pathlib

    # Built by STRING concatenation on `stem`, never `Path.with_suffix`: that
    # method treats everything after the LAST dot as the suffix, so
    # `system-requirements.template.toml` resolves to `system-requirements.toml`
    # — a different file, silently. `carriers()` already builds paths this way
    # and the two must agree.
    base = stem(path)
    live = [pathlib.Path(base + s) for s in suffixes]
    live = [p for p in live if p.is_file()]
    if len(live) > 1:
        raise SystemExit(
            "spine_carrier: REFUSED — {} exists under BOTH carriers ({}). Two "
            "homes for one fact is the state the migration exists to leave; "
            "delete the stale one in the same commit that wrote the other "
            "rather than letting a precedence rule pick.".format(
                pathlib.Path(base).name, ", ".join(p.name for p in live)
            )
        )
    return live[0] if live else None


def empty_value_findings(rows, id_col, rel=""):
    """One finding per cell written as an EXPLICIT EMPTY STRING.

    THE CARRIER'S CLAIM IS THAT ABSENT MEANS UNSET, and until this check that
    claim was only true of machine-written files: the converter omits an empty
    cell, but nothing stopped a HAND-authored `title = ""` — and TOML parses it
    happily, so the row came back with the key PRESENT and empty. That is the
    third state the migration exists to abolish, re-entering through the one
    door nobody was watching: `.get(col) or ""` reads it as empty, a key-set
    check reads it as declared, and the two disagree about the same cell.

    REJECTED rather than normalised, which is the fail-closed half of the fork.
    Normalising (dropping the key on read) would make the file and the loaded
    row disagree — the file says the author wrote something, the reader says
    they did not — and every writer downstream would then re-emit a row it never
    read. Refusing names the row and the key and asks for a one-character edit:
    delete the line. (Owner ruling owed — this fork was never ruled; the
    fail-closed option is taken and flagged.)"""
    out = []
    for row in rows:
        rid = str(row.get(id_col) or "").strip() or "(unnamed row)"
        for col, value in sorted(row.items()):
            if col != id_col and isinstance(value, str) and value == "":
                out.append(
                    "{}{} sets `{}` to an EMPTY STRING — under this carrier an "
                    "unset cell is an ABSENT KEY, and an explicit empty is a "
                    "third state the readers disagree about. Delete the "
                    "line.".format(rel and rel + ": ", rid, col)
                )
    return out


def load(path, id_col, keep_examples=True):
    """The live registry as a LIST of rows in file order — the shape
    `csv.DictReader` returns, so a caller swaps its loader and changes nothing
    else. `[]` when the registry does not exist.

    Raises SystemExit on a carrier that exists and does not parse, and on a cell
    written as an explicit empty string: at a LIVE read there is a file to fix
    and a person to tell, so degrading to "no rows" — or to "that cell is just
    empty" — would turn a broken registry into a clean gate. The BASELINE reads
    stay permissive on purpose (`rows_from_text` never raises): history is not
    editable, and a strict reader pointed at an old revision would fail a check
    over a file nobody can fix."""
    live = resolve(path)
    if live is None:
        return []
    rows = rows_seq_from_text(
        live.read_text(encoding="utf-8-sig", errors="replace"), id_col, live.suffix
    )
    if rows is None:
        raise SystemExit(
            "spine_carrier: {} does not parse as TOML — refusing to report an "
            "unreadable registry as an empty one".format(live)
        )
    if live.suffix == ".toml":
        findings = nested_table_findings(
            live.read_text(encoding="utf-8-sig", errors="replace"), id_col, str(live)
        ) + empty_value_findings(rows, id_col, str(live))
        if findings:
            raise SystemExit("spine_carrier: " + "\n".join(findings))
    return [
        r
        for r in rows
        if keep_examples or not str(r.get(id_col) or "").endswith("-000")
    ]


def columns(path, id_col):
    """The COLUMN NAMES a live registry actually uses, id column first, in
    first-seen order — whichever carrier holds it. `[]` when it is absent.

    THE TWO CARRIERS ANSWER THIS DIFFERENTLY AND BOTH ANSWERS ARE HONEST. A CSV
    header is a declaration: every row has every column, empty or not. TOML has
    no header at all — an absent key IS the empty cell, which is the carrier's
    whole point — so the analogue is the UNION over rows: a column exists in
    this registry iff some row sets it. Union, never intersection: a column one
    row uses is a column the registry has, and intersecting would erase every
    optional field the moment one row omitted it.

    Callers that check a registry against a shipped template want exactly this,
    and want it stated in ONE place — the three that asked it independently were
    each reading the CSV header with `csv.reader`, which over a TOML file
    returns the first line, `[requirement.SR-001]`, as a column name.

    The CSV arm reads through `kitlib.spine.csv_body`, like every other reader
    in the kit, so a `#` declaration header is a header here too — read raw, the
    comment's cells would come back AS the column names."""
    live = resolve(path)
    if live is None:
        return []
    text = live.read_text(encoding="utf-8-sig", errors="replace").lstrip("﻿")
    if live.suffix != ".toml":
        header = next(csv.reader(io.StringIO(_kitspine.csv_body(text))), [])
        return [c for c in header if c]
    rows = rows_from_toml(text, id_col)
    if rows is None:
        raise SystemExit(
            "spine_carrier: {} does not parse as TOML — refusing to report an "
            "unreadable registry as a column-less one".format(live)
        )
    out = [id_col]
    for row in rows.values():
        for col in row:
            if col not in out:
                out.append(col)
    return out


# --- the stakeholder-need tier ------------------------------------------------
# The SN tier is the reason the spine had TWO carriers: needs shipped as
# markdown prose tables in three different SHAPES, and reading 32 of them cost
# ~166 code lines across 14 functions in 8 modules while reading all 436
# SR+LLR+TC rows cost `csv.DictReader`. Under one carrier a need is a table like
# any other row, and two long-standing sharp edges go with the markdown:
#
#   * SECTION-AS-STATE is retired. Draft-ness was "appears under a heading whose
#     text contains the word draft", scraped by one function while the id
#     universe was scraped by another — and during the 2026-08-10 sitting a
#     prose MENTION of an id under the draft heading silently re-drafted an
#     already-attested need. `kind` is now a field on the need itself.
#   * THE EDGE-CASE TIER keeps its own fields (`lifecycle` / `scenario` /
#     `expected`) instead of being folded onto the core four at read time.
NEED_TABLE = "need"
SN_CORE = ("need", "why", "priority", "acceptance")
SN_EDGE = ("lifecycle", "scenario", "expected")
_SN_HEADING = re.compile(r"^#{2,}\s+(.*)$")
_SN_ROW = re.compile(r"^\|\s*(SN-\d+)\s*\|")


def _kind_from_heading(title):
    """Which of the three tables a markdown heading opens. Legacy carrier only:
    under TOML the need CARRIES its kind, which is the whole point."""
    t = title.lower()
    if "draft" in t:
        return "draft"
    if "edge" in t:
        return "edge"
    return "core" if ("core" in t or "need" in t) else None


# Header text -> canonical field, first match wins. The order is deliberate:
# every live and shipped header cell is prose ("Need (plain language)",
# "Acceptance intent (how we'd know it's met)"), so the fields whose words could
# appear inside another cell's gloss are matched LAST.
_SN_HEADER_FIELD = (
    ("lifecycle", "lifecycle"),
    ("scenario", "scenario"),
    ("expected", "expected"),
    ("why", "why"),
    ("priority", "priority"),
    ("acceptance", "acceptance"),
    ("need", "need"),
)


def _names_from_header(cells):
    """Canonical field name per non-id column of a markdown header row, or None
    when this row is not a need-table header."""
    if not cells or "sn-id" not in cells[0].lower():
        return None
    names = []
    for cell in cells[1:]:
        low = cell.lower()
        names.append(next((f for w, f in _SN_HEADER_FIELD if w in low), None))
    return names if any(names) else None


def _edge_folded(need):
    """A legacy edge-table row read as an ORDINARY need.

    The `edge` row TYPE is retired (owner ruling 2026-08-17j) — no live carrier
    emits it and no reader downstream defines it — but legacy markdown files
    still HAVE edge tables, and their cells are content. So the shape is
    resolved here, at the one boundary that still meets it, rather than left for
    a renderer to special-case: the SCENARIO is the need, the LIFECYCLE phase is
    the why, and the EXPECTED behavior is the acceptance.

    NEVER the lifecycle word as the title — that was the live F-6 regression,
    which published SN-013 as "Provision" across the dashboard and the OKF
    bundle for the whole life of both. Dropping the fold instead of moving it
    would trade that wrong title for four blank cells, which is the same content
    loss with less evidence that it happened.

    The CONVERTER does not use this: `migrate_carrier` must preserve the raw
    cells it was handed, because its job is to carry a registry across carriers
    without deciding anything about it."""
    return {
        "id": need["id"],
        "status": need.get("status", "Approved"),
        "need": need.get("scenario", ""),
        "why": need.get("lifecycle", ""),
        "priority": need.get("priority", "n/a"),
        "acceptance": need.get("expected", ""),
    }


def needs_from_markdown(text):
    """`[{id, kind, **fields}]` from the legacy prose tables, document order.

    Cells are resolved by the table's OWN HEADER where it has one, and by the
    table's SHAPE where it does not — never by fixed offset. The shape arm is
    what stopped an edge row being read at the core offsets, which published
    SN-013 as "Provision" — its LIFECYCLE word — for the whole life of the
    dashboard and the OKF bundle.

    THE HEADER ARM IS NOT A REFINEMENT, it is fidelity to the readers this
    replaced. They found `Priority` BY HEADER TEXT, so an abbreviated core table
    — `| SN-ID | Need | Priority | Acceptance |`, which the kit's own fixtures
    and briefs use — read correctly. Shape alone maps that row's Priority onto
    `why`, every need reads as priority-less, and the README Must/Should
    coverage floor silently drops to nothing: a check that passes because it
    found no rows to check. Legacy text must keep the semantics it was written
    under (the same rule `draft_ids_from_text` states for section-as-state)."""
    kind, names, out = None, None, []
    for line in text.split("\n"):
        heading = _SN_HEADING.match(line)
        if heading:
            kind = _kind_from_heading(heading.group(1))
            names = None  # a heading ends the table above it
            continue
        cells = [c.strip() for c in line.split("|")[1:-1]] if "|" in line else []
        header = _names_from_header(cells)
        if header is not None:
            names = header
            continue
        row = _SN_ROW.match(line)
        if not row:
            continue
        # A row with NO heading above it is resolved by the table's SHAPE, which
        # is what the readers this replaces always did: the edge table is three
        # cells wide and carries no priority, the core table four. Requiring a
        # heading would refuse a headerless fragment — and the fragment is the
        # normal case for a test fixture and for a table pasted into a brief.
        row_kind = kind or ("edge" if len(cells) - 1 == len(SN_EDGE) else "core")
        if names is None:
            names = list(SN_EDGE if row_kind == "edge" else SN_CORE)
        if kind is None and any(n in SN_EDGE for n in names if n):
            row_kind = "edge"
        # Section-as-state, translated into the ONE field at the read boundary:
        # legacy markdown had exactly two maturities — under the draft heading
        # or not — so the mapping is total and loses nothing. Emitting it here
        # is what keeps `is_draft_need` honest over legacy text; without it a
        # draft-heading row reads as approved and the derived gate RISES, the
        # one failure shape this carrier exists to prevent.
        need = {
            "id": cells[0],
            "status": "Drafted" if row_kind == "draft" else "Approved",
        }
        for name, value in zip(names, cells[1:]):
            if name:
                need[name] = value
        out.append(_edge_folded(need) if row_kind == "edge" else need)
    return out


def needs_from_toml(text):
    """`[{id, kind, **fields}]` from the TOML carrier, or None when it does not
    parse. Same absent-vs-empty and None-vs-`{}` rules as the row tiers."""
    try:
        tables = tomllib.loads(text)
    except tomllib.TOMLDecodeError:
        return None
    out = []
    for rid, cells in (tables.get(NEED_TABLE) or {}).items():
        need = {"id": rid}
        need.update({k: value_to_cell(v) for k, v in cells.items()})
        out.append(need)
    return out


def needs_from_text(text, carrier):
    """`[{id, kind, **fields}]` for a needs registry's TEXT, under the carrier
    it was read from (`.toml` or `.md`, the resolved file's suffix).

    Exists because some readers hold the registry's TEXT rather than its path:
    the approval view's need prose, the README's Must/Should floor, and the
    snapshot's reads of a needs file at a past commit. Each read that text from
    a file it resolved, so each knows the carrier.

    THE CARRIER COMES FROM THE FILE, NOT FROM THE TEXT, for the reason
    `draft_ids_from_text` gives. Sniffing read a TOML text that declares no need
    table as markdown, so a table row inside a TOML string became a need the
    file never declared, and read a TOML text that does not parse as markdown
    instead of refusing it. A `.toml` text that does not parse RAISES, and so
    does a carrier the need tier does not have: ValueError, because the refusal
    is the caller's (`needs_or_refuse` names the file).

    Implements: SR-147, LLR-277"""
    if carrier == ".toml":
        parsed = needs_from_toml(text)
        if parsed is None:
            raise ValueError(
                "the .toml needs carrier does not parse as TOML; refusing to "
                "read its needs from a guess"
            )
        return parsed
    if carrier != ".md":
        raise ValueError(
            "no needs carrier {!r}: the need tier is .toml or .md".format(carrier)
        )
    return needs_from_markdown(text)


def needs_or_refuse(path, text):
    """`needs_from_text` for a needs file its caller resolved, taking the
    carrier from `path`'s suffix and refusing the run, naming the file, when it
    cannot be read — the refusal `draft_ids_or_refuse` makes for the draft set.
    `path` may name a file at a past commit (`<rev>:<path>`); only its suffix
    and its spelling are read.

    Implements: SR-147, LLR-277"""
    try:
        return needs_from_text(text, PurePosixPath(str(path).replace("\\", "/")).suffix)
    except ValueError as exc:
        raise SystemExit("{}: {}".format(path, exc)) from exc


def load_needs(path):
    """Every stakeholder need, through whichever carrier is live.

    `path` may name either suffix; `resolve` refuses both at once. `[]` when the
    registry is absent, and SystemExit when a carrier exists and cannot be read
    — an unreadable needs registry must not read as "this project has no needs",
    which is a DevStg-Below gate and a vacuous orphan check at the same time."""
    live = resolve(path, NEED_CARRIERS)
    if live is None:
        return []
    text = live.read_text(encoding="utf-8-sig", errors="replace")
    if live.suffix == ".md":
        return needs_from_markdown(text)
    needs = needs_from_toml(text)
    if needs is None:
        raise SystemExit(
            "spine_carrier: {} does not parse as TOML — refusing to report an "
            "unreadable needs registry as an empty one".format(live)
        )
    return needs


def load_need_tier(path, id_col, keep_examples=True):
    """The needs file's `id_col` tier (`SN-ID` or `STK-ID`) as rows under
    today's column names, whichever of the two need carriers is live — the
    shape `load` returns for every other tier, so one comparison reads them.

    `load` knows the row tiers' carriers alone (`.toml`/`.csv`), so a needs
    file still on the legacy markdown carrier read through it yielded no rows
    on either side of a comparison, and a drifted need read as no drift. Under
    markdown the needs are `needs_from_markdown`'s rows keyed by their column
    names (`status` read off the section as it always was), and the stakeholder
    tier, which that carrier never had, is `[]`. `[]` when neither carrier
    exists; a `.toml` that does not parse raises through `load`.

    Implements: SR-147, LLR-277"""
    live = resolve(path, NEED_CARRIERS)
    if live is None:
        return []
    if live.suffix != ".md":
        return load(live, id_col, keep_examples)
    text = live.read_text(encoding="utf-8-sig", errors="replace")
    return [
        row
        for row in _markdown_need_rows(text, id_col)
        if keep_examples or not row["SN-ID"].endswith("-000")
    ]


def _markdown_need_rows(text, id_col):
    """The legacy markdown needs file's `id_col` tier as rows under today's
    column names: its needs for `SN-ID`, `[]` for the stakeholder tier that
    carrier never had."""
    if id_col != "SN-ID":
        return []
    rows = []
    for need in needs_from_markdown(text):
        row = {"SN-ID": need["id"]}
        row.update({REGISTRY_COLUMN.get(k, k): v for k, v in need.items() if k != "id"})
        rows.append(row)
    return rows


# The id columns the needs file holds (SR-189): its registry's carriers are the
# need carriers, every other tier's the row carriers.
NEED_TIER_COLS = ("SN-ID", "STK-ID")


def tier_carriers(rel_path, id_col):
    """Every carrier path the registry holding `id_col`'s tier can appear
    under, in preference order: the need carriers for the needs file's tiers,
    the row carriers for every other tier. The ONE place a tier's carrier set
    is chosen, so a reader of a registry at a revision never lists formats of
    its own (WI-841 round 6).

    Implements: SR-147, LLR-277"""
    return carriers(rel_path, NEED_CARRIERS if id_col in NEED_TIER_COLS else CARRIERS)


def tier_rows_from_text(text, id_col, carrier):
    """`{id: row}` for one tier's registry TEXT under the carrier its file was
    read from, for every carrier the kit supports (`.toml`, `.csv`, and the
    needs file's legacy `.md`), or None when a TOML text does not parse. The
    `-000` example rows are kept, as `rows_from_text` keeps them.

    Implements: SR-147, LLR-277"""
    if carrier != ".md":
        return rows_from_text(text, id_col, carrier)
    rows = _markdown_need_rows(text.lstrip("﻿"), id_col)
    return {row[id_col]: row for row in rows}


def folded(need):
    """A need projected onto the CORE four, for a reader that renders one shape.

    This is the PRESENTATION rule the markdown tables forced, kept out of the
    carrier deliberately — but kept in ONE place, which the
    carrier did not previously manage. `traj_parse._sn_rows` and
    `gen_okf.sn_rows` each carried a copy pinned by nothing but a docstring
    saying "change both together"; they drifted, and the dashboard rendered a
    phantom `SN-000` root (§6 F-6).

    THE EDGE ARM IS GONE (owner ruling 2026-08-17j, "edge is dropped"). It
    re-titled an edge row — scenario as the need, lifecycle phase as the why —
    and there is nothing left to re-title: the row TYPE is retired along with
    the `kind` field that declared it, and edge coverage is the hats
    mechanism's job now. The fold is one shape because the tier is one shape."""
    return {k: need.get(k, "") for k in ("id",) + SN_CORE}


def draft_ids_from_text(text, carrier):
    """Draft need ids for a needs registry's TEXT, under the carrier it was read
    from.

    THE TWO CARRIERS ARE DELIBERATELY NOT UNIFIED HERE, and that is the whole
    care in this function. Under TOML draft-ness is a FIELD (`status`, read by
    `is_draft_need`), which is what
    retires section-as-state and kills the sharp edge the 2026-08-10 sitting
    hit — a prose MENTION of an id under the draft heading silently re-drafted
    an already-attested need, because the id universe is a whole-text scrape
    while draft-ness was a heading scan. Under MARKDOWN the heading scan is
    reproduced EXACTLY as it always behaved, prose mentions and all.

    Reading legacy text by the new rule would be a silent behaviour change for
    every repo that has not migrated yet: needs that were draft would stop
    being draft, and the derived gate would rise. The ruling retires the sharp
    edge WITH the carrier, not ahead of it, so a file gets the semantics it was
    written under.

    THE CARRIER COMES FROM THE FILE, NOT FROM THE TEXT. `carrier` is the
    resolved registry's suffix (`.toml` or `.md`), which every caller holds
    because it read the file; `load_needs` and `sn_all_ids` take it the same
    way. Sniffing cannot decide it: an empty or comment-only TOML file parses
    to nothing, exactly like a markdown file of headings, and read as markdown
    a `## Draft` comment followed by a commented need id drafted a need the
    file never declared.

    A `.toml` TEXT THAT DOES NOT PARSE RAISES, and so does a carrier the need
    tier does not have. There is no safe guess: a heading-scan fallback over
    malformed TOML with no markdown draft heading answers "no drafts", every
    need then reads as approved, and the derived stage rises on a file nobody
    could read. ValueError, not SystemExit, because the policy is the
    caller's: the two readers of the gate turn it into a refusal naming the
    file, the way `load_needs` refuses."""
    if carrier == ".toml":
        parsed = needs_from_toml(text)
        if parsed is None:
            raise ValueError(
                "the .toml needs carrier does not parse as TOML; refusing to "
                "report its drafts from a guess"
            )
        return draft_need_ids(parsed)
    if carrier != ".md":
        raise ValueError(
            "no needs carrier {!r}: the need tier is .toml or .md".format(carrier)
        )
    draft, in_draft = set(), False
    for line in text.splitlines():
        heading = _SN_HEADING.match(line)
        if heading:
            in_draft = "draft" in heading.group(1).lower()
            continue
        if in_draft:
            draft.update(
                u for u in re.findall(r"\bSN-\d+\b", line) if not u.endswith("-000")
            )
    return draft


def draft_ids_or_refuse(path, text):
    """`draft_ids_from_text` for a needs file a gate reader RESOLVED, refusing
    the run when the file cannot be read.

    The refusal is a SystemExit naming the file, the way `load_needs` refuses:
    answering "no drafts" for an unreadable file would read every need as
    approved and let the derived stage rise. It has one home because its two
    callers are the two readers of the gate, `trace.load_registries` and
    `spine_rules.load_spine`, and a refusal policy stated twice is one that
    drifts. The stage derivation reads the needs file nowhere else, so this is
    where its refusal has to happen."""
    try:
        return draft_ids_from_text(text, path.suffix)
    except ValueError as exc:
        raise SystemExit("{}: {}".format(path, exc)) from exc


_SN_EMPHASIS = re.compile(r"\*\*|`")


def folded_needs(path):
    """Every need as the CORE four, `-000` skipped and id-sorted — the shape
    every renderer of the need tier wants.

    THIS COLLAPSES A KNOWN-DRIFTING TRIPLET. `traj_parse._sn_rows`,
    `gen_okf.sn_rows` and `trace._sn_prose` each carried this rule with a
    docstring saying "change all three together"; that is a promise, not a
    mechanism, and they broke it — one kept the `-000` example row and one did
    not, which rendered a phantom `SN-000` root in the dashboard's icicle. It is
    the same argument that put the column vocabulary in one home (D-6): a
    duplicated RULE whose copies disagree does not fail loudly, it renders
    something subtly wrong on a surface a human is expected to trust.

    Markdown emphasis is stripped because these cells are prose written for a
    table and re-rendered somewhere that is not one."""
    out = []
    for need in load_needs(path):
        if str(need.get("id", "")).endswith("-000"):
            continue
        row = folded(need)
        out.append({k: _SN_EMPHASIS.sub("", v).strip() for k, v in row.items()})
    return sorted(out, key=lambda r: r["id"])


def needs_for_root(root):
    """`folded_needs` addressed from a REPO ROOT rather than a registry path.

    THE ELEVENTH DUPLICATE, retired the way `draft_ids_from_text` was (WI-448
    slice 4). `traj_parse._sn_rows` and `gen_okf.sn_rows` were each a one-line
    wrapper composing the same relpath onto the same call — a duplicate the
    census scored, and one that could not move to `kitlib` because that package
    may import no sibling of `scripts/`. So the home is here, beside the reader
    it delegates to, and both former holders BIND this function directly under
    their existing local names; the wrappers disappear.

    `.toml` is named because `load_needs` resolves through `NEED_CARRIERS`, so
    a repo still on the markdown carrier is found anyway."""
    return folded_needs(root / "docs/requirements/stakeholder-needs.toml")


def need_ids(needs):
    """Every declared need id — the UNIVERSE the draft set is carved out of."""
    return {n["id"] for n in needs}


def is_draft_need(need):
    """Is this need still at draft — the ONE predicate that answers it.

    Drafted-ness lives in `status`, the same field and the same Title-case word
    the other three spine tiers use (`Drafted | Approved | Founded`); the SN
    tier used to spell it `kind = "draft"`, a field that also carried row TYPE.

    A NEED WITH NO `status` IS NOT DRAFT, and that default is deliberate rather
    than incidental: the failure mode this tier can least afford is the one the
    markdown carrier had — a row silently reading as un-drafted floats the
    derived gate UPWARD. Here the absent-key case reads as approved only because
    an absent `status` is caught upstream, as a SCHEMA finding on a required
    key, rather than being invented into a maturity by a reader.

    MATCHED CASE-INSENSITIVELY, the one Status-casing rule the other three tiers
    already follow (`trace.is_drafted`/`is_approved`/`is_founded` all lower the
    cell before comparing; process.md §4). It was an EXACT compare here, and the
    asymmetry failed in the unsafe direction: a need written `status = "drafted"`
    read as approved, floating the derived gate upward — the same silent
    float this docstring's absent-key paragraph exists to prevent, arriving by
    casing instead of by an absent key. Casing is not a maturity, so a
    mis-cased word must not decide one; a word that is not in the vocabulary at
    all is still a finding, and that is `trace.enum_integrity_findings`' job.

    (The transitional `kind = "draft"` fallback that stood here during the
    registry migration is gone with the field itself.)"""
    return str(need.get("status", "")).strip().lower() == "drafted"


def draft_need_ids(needs):
    """The needs still at draft. A FIELD now, not a heading a prose mention can
    fall under."""
    return {n["id"] for n in needs if is_draft_need(n)}


def status_cells(text, tables=None):
    """`{row id: status}` for every row of EVERY table of a TOML registry text
    that carries a `status` cell, or None when the text does not parse.
    `tables`, when given, narrows the read to the tables it names: the needs
    file carries a spine tier and an off-spine one, and a reader that walks the
    spine tier elsewhere must read only the other one here, or it reads every
    need twice.

    Keyed by row id across tables rather than read one tier by its id column,
    because a question about a whole FILE's status cells - which ones a delta
    moved - must see every tier the file carries, including one this module's
    `OFFSPINE_TABLE` has not been told about yet: the frame holds three tiers in
    one file, and a new registry can arrive before its tier is mapped here.
    Ids are unique across a file's tiers (each tier has its own prefix). The
    `-000` example rows are kept, as `rows_from_text` keeps them - the caller
    owns that filter. None and `{}` stay opposite claims, as everywhere here."""
    try:
        parsed = tomllib.loads(text.lstrip("﻿"))
    except tomllib.TOMLDecodeError:
        return None
    return {
        str(rid): str(cells["status"]).strip()
        for name, rows in parsed.items()
        if isinstance(rows, dict) and (tables is None or name in tables)
        for rid, cells in rows.items()
        if isinstance(cells, dict) and "status" in cells
    }
