#!/usr/bin/env python3
"""Architecture seams, components, contracts, and spec-boundary decisions.

This module owns the architecture inventory joins: interface connectivity and
contract declarations, seam-to-test coverage, component containment and
cross-component edges, code-symbol crosschecks, and spec interface citations.
Trajectory lifecycle, phase, staleness, and CLI composition stay in
``check_trajectory``.

Contracts: IF-263 — the interface seam this file declares (process.md §8; row
of record in docs/requirements/interfaces.toml).

Contract IF-263: ``check_trajectory`` imports and re-exports this module's
architecture rule surface. Inputs are a repository root, the spine/config
files beneath it and, for `tc_tag_findings`, the test files under the declared
tests root; outputs are normalized inventories or finding strings. The module
performs no writes and exposes no command-line entry point.
"""

import ast
import re
import sys
from pathlib import Path

try:
    from kitlib import config as _kitconfig
    from kitlib import spine as _kitspine
except ImportError:  # pragma: no cover - in-process fallback
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from kitlib import config as _kitconfig
    from kitlib import spine as _kitspine

try:
    import spine_carrier
except ImportError:  # pragma: no cover - in-process fallback
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import spine_carrier

try:
    import gen_arch_map
except ImportError:
    try:  # pragma: no cover - in-process fallback
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        import gen_arch_map
    except ImportError:
        gen_arch_map = None

_first_declared_line = _kitconfig.first_declared_line
_process_check = _kitconfig.process_check
_split_refs = _kitspine.refs

TC_CSV = "docs/test/test-cases.toml"
IF_CSV = "docs/requirements/interfaces.toml"
LLR_CSV = "docs/requirements/low-level-requirements.toml"
CMP_CSV = "docs/requirements/components.toml"
SPECS_DIR = "docs/specs"
# The How-SW top view is bounded at this many items (top-level components +
# uncontained modules); exceeding it drives right-sizing of the component
# designations (WI-073, FB5 — warn plain, error --strict).
TOP_VIEW_MAX = 10

# An IF-### interface-seam id token (process.md §8). Matched word-bounded so a
# `Contracts: IF-003, IF-004` docstring line (harvested into the arch-map) or an
# id cell yields each id cleanly.
IF_ID_RE = re.compile(r"IF-\d+")

# The declared shared-kernel surface (OI-48 ruled (d), WI-494) — see
# `read_kernel_modules`. The reuse provision's home: a small declared file,
# consistent with the `docs/*-allow` idiom `provenance-allow` and
# `if-tc-coverage-allow` already established, over a `[checks]`-side list —
# a per-entry recorded REASON is the point, and `docs/process.toml` carries
# dials, not reasoned prose.
KERNEL_ALLOW = "docs/kernel-modules-allow"
KERNEL_ALLOW_SEP = " — "

# The seam-TC coverage migration allowlist (OI-43 ruled (a), WI-488) — see
# `read_if_tc_allow`.
IF_TC_ALLOW = "docs/if-tc-coverage-allow"
# The allowlist's machine-readable baseline: how many of its entries are the
# SEEDED population (which shares one reason, stated once in the header). Past
# that count an entry is an addition and must carry its own ` — <reason>`.
IF_TC_SEED_RE = re.compile(r"^#\s*seed-count:\s*(\d+)\s*$")
# A CMP-### component id token (process-options.md "Component layer"). trace.py
# owns CMP integrity; this loader is lenient (skips a malformed id) — it only
# feeds the warn-first top-view coverage.
CMP_ID_RE = re.compile(r"^CMP-\d+$")


def read_interfaces_check_enabled(root):
    """Whether the architecture-connectivity coverage warns are on (S5/WI-056).
    `docs/process.toml` `[checks] interfaces_check = false` opts out; else
    (migration window) `docs/interfaces-check` with the one word `off`; absent
    or any other value reads on — the ruled opt-out, default-on posture (same
    shape as `trajectory_check`). Default-on means the coverage warn fires even
    with an empty/absent `interfaces.csv`; the off-switch or a ≤1-module
    inventory is the only silence."""
    declared = _process_check(root, "interfaces_check")
    if declared is not None:
        return declared
    return (
        _first_declared_line(root / "docs" / "interfaces-check") or ""
    ).lower() != "off"


def read_components_check_enabled(root):
    """Whether the How-SW top-view right-sizing rule is on (WI-073/FB5).
    `docs/process.toml` `[checks] components_check = false` opts out; else
    (migration window) `docs/components-check` with the one word `off`; absent
    or any other value reads on — the ruled opt-out, default-on posture (same
    shape as `interfaces_check`)."""
    declared = _process_check(root, "components_check")
    if declared is not None:
        return declared
    return (
        _first_declared_line(root / "docs" / "components-check") or ""
    ).lower() != "off"


# Source-file extensions stripped when normalizing a module path, so the arch-map
# name (`scripts/check`), an LLR `Module` cell and an IF endpoint written with
# the full repo path (`project-trajectory/scripts/check.py`) collapse to one key.
# ONE HOME since WI-448 slice 4 (`kitlib.spine`), which also retired the false
# claim this comment carried: it promised the tuple was "kept in sync with
# trace.py._MODULE_EXTS", and `trace.py` has no such name — the sync partner
# named here did not exist. The real second copy was `gen_arch_map.py`'s.
_MODULE_EXTS = _kitspine.MODULE_EXTS
_norm_module = _kitspine.norm_module


def load_ifs(rows):
    """Real (non-`-000`) IF-### interface rows as dicts, each already RESOLVED
    into its two sides — `owner` (one endpoint, possibly `''`) and the far side
    as `requestors` / `consumers` (lists; exactly one is meant to be set — the
    key name is the direction) plus `far`, whichever of the two it is. Lenient — `trace.py` owns IF integrity (malformed ids, owner
    shape); this loader only feeds the warn-first coverage views, so a
    malformed id is simply skipped here.

    `approval` is the tier's ONE maturity field. It replaced `stability` at
    WI-442, which had itself replaced `status` at WI-443 — the same defect twice
    (two columns on one row meaning different kinds of "settled"), fixed the same
    way. `direction`/`this_project`/`counterpart` went at WI-455 (OI-60 ruled
    (a)): flow is no longer a column but the shape of the row, so RESOLUTION
    happens here, once, and every view downstream (this module's connectivity
    credit and declared pairs, `traj_views`' seam graphs) reads the same two
    keys instead of re-deriving the orientation from a flag. Since OI-67 the
    owner side is the row's own `owner` cell, one spelling, nothing derived."""
    out = []
    for r in rows:
        iid = (r.get("IF-ID") or "").strip()
        if not IF_ID_RE.fullmatch(iid) or iid.endswith("-000"):
            continue
        out.append(
            {
                "id": iid,
                "owner": _kitspine.seam_owner(r),
                "requestors": _kitspine.seam_requestors(r),
                "consumers": _kitspine.seam_consumers(r),
                "far": _kitspine.seam_far_side(r)[1],
                "approval": (r.get("Status") or "").strip().lower(),
                "notes": (r.get("Notes") or "").strip().lower(),
            }
        )
    return out


def load_seams(root):
    """`load_ifs` over the live registry — the one call every seam view makes."""
    return load_ifs(spine_carrier.load(root / IF_CSV, "IF-ID"))


def _contracts_grammar_findings(root):
    """Marker-grammar findings over the declared scan root, or `[]` where the
    tree cannot be read.

    Degrades to silence on a missing `gen_arch_map`, files-mode or an absent
    scan root, exactly as `arch_inventory` does — a detector that crashed in a
    scaffold would be removed from the floor, which is the same outcome as not
    having it."""
    if gen_arch_map is None or not hasattr(gen_arch_map, "contracts_grammar_findings"):
        return []
    src, mode = _arch_scan_profile(root)
    if mode == "files":
        return []
    src_dir = root / src.strip().replace("\\", "/").rstrip("/")
    if not src_dir.is_dir():
        return []
    found = []
    for path in sorted(src_dir.rglob("*.py")):
        if "__pycache__" in path.parts:
            continue
        try:
            text = path.read_text(encoding="utf-8")
            tree = ast.parse(text)
        except (OSError, UnicodeDecodeError, SyntaxError):
            continue
        found.extend(
            gen_arch_map.contracts_grammar_findings(path.name, tree, text.splitlines())
        )
    # The file owners — registries, config, hooks — read through the same
    # grammar (OI-67 slice 2), so a lossy marker in a header is named too.
    if hasattr(gen_arch_map, "file_grammar_findings"):
        for owner, path in _owner_files(root):
            found.extend(gen_arch_map.file_grammar_findings(owner, path))
    return found


def _owner_files(root):
    """`gen_arch_map.owner_files` over the live registry; `[]` when the
    generator is absent or predates the file-owner scan."""
    if gen_arch_map is None or not hasattr(gen_arch_map, "owner_files"):
        return []
    return gen_arch_map.owner_files(root, spine_carrier.load(root / IF_CSV, "IF-ID"))


def _file_owner_declarations(root, out):
    """`{owner: {IF ids}}` declared by the file owners' headers; a header the
    grammar refuses is reported into `out` and read as declaring nothing."""
    declared = {}
    for owner, path in _owner_files(root):
        try:
            ids, _bodies = gen_arch_map.file_contracts(path)
        except gen_arch_map.ContractsGrammarError as exc:
            out.append("{}: {}".format(owner, exc))
            continue
        if ids:
            declared[owner] = set(ids)
    return declared


def arch_inventory(root):
    """`(module_names, {module: {IF ids}}, {module: {imported stems}})` derived
    STRAIGHT from the source tree under the declared arch-map scan root
    (`[paths] src` + `[arch-map] mode`, the same profile check.py reads),
    through `gen_arch_map.scan_inventory` — the one AST walk the map's
    consumers share. Until WI-455 (sitting-2 decision 8) this parsed the
    committed MODULE MAP block back out of `docs/architecture.md`; the
    registries→dashboard re-pointing retired that way-station, so the
    inventory is now the LIVE tree — on a work branch too, which is what
    dissolved the WI-399 committed-vs-disk delta rule (`shipped_modules` and
    the station-first firing gap died with it). `module_names` keep the map's
    grammar (`scripts/check`-style keys relative to the scan root's parent);
    the IF map carries each module's `Contracts: IF-###` docstring
    declarations; the import map carries the internal-import names — the
    cross-CMP rule's edge source (WI-064). Empty when the root is absent,
    files-mode (no parser), or `gen_arch_map` is not beside this script, so
    the coverage layers stay vacuous exactly where the committed map was.

    Implements: SR-159, LLR-067
    """
    if gen_arch_map is None:
        return set(), {}, {}
    src, mode = _arch_scan_profile(root)
    if mode == "files":
        return set(), {}, {}
    src_dir = root / src.strip().replace("\\", "/").rstrip("/")
    names, contracts, imports = [], {}, {}
    for rel, _summary, imps, cons, _rows in gen_arch_map.scan_inventory(
        [src_dir], strict=False
    ):
        names.append(rel)
        if cons:
            contracts.setdefault(rel, set()).update(cons)
        if imps:
            imports.setdefault(rel, set()).update(imps)
    return set(names), contracts, imports


def interface_findings(root):
    """Architecture-connectivity coverage warns (S5/WI-056; process.md §8), all
    warn-first — the caller prints them and they never change the exit code, at
    any gate. Returns the warn strings ([] when opted out or vacuous).

    Ruled opt-out, default-on: fires even with an empty/absent `interfaces.csv`
    (a multi-module arch-map with no declared seams reads "connectivity
    undeclared"); silenced only by `[checks] interfaces_check = false` or a ≤1-module
    inventory (nothing to connect).

    Implements: SR-159, LLR-042
    """
    if not read_interfaces_check_enabled(root):
        return []
    inventory, declared_contracts, _imports = arch_inventory(root)
    if len(inventory) <= 1:
        return []  # nothing to connect (or no arch-map yet) — vacuous
    ifs = load_seams(root)
    out = []
    if not ifs:
        return [
            "connectivity undeclared: the {}-module architecture declares no "
            "interfaces — add IF-### rows to {}, or set docs/process.toml "
            "[checks] interfaces_check = false".format(len(inventory), IF_CSV)
        ]

    inv_norm = {_norm_module(m): m for m in inventory}
    inv_norm.pop("", None)
    endpoints, provides, consumes = set(), set(), set()
    sources, sinks = set(), set()
    for r in ifs:
        producer = _norm_module(r["owner"])
        consumer_ns = {_norm_module(c) for c in r["far"]} & set(inv_norm)
        endpoints.update(consumer_ns)
        if producer in inv_norm:
            endpoints.add(producer)
        # The honesty valve: a `source`/`sink` FIRST word in Notes marks the
        # row's own side a deliberate source (consumes nothing) / sink (provides
        # nothing), so it doesn't breed a boilerplate opposite-facing row. Since
        # WI-455 the marked side is named by the ROLE rather than by a column:
        # `source` marks the OWNER, `sink` marks the CONSUMERS — which is what
        # the two words meant when both were read off `ThisProject`.
        marker = r["notes"].split()
        first = marker[0].rstrip(":;,.") if marker else ""
        if first == "source":
            sources.add(producer)
        elif first == "sink":
            sinks.update(_norm_module(c) for c in r["far"])
        # Producer -> consumer credit, read off the resolved sides.
        if producer in inv_norm:
            provides.add(producer)
        consumes.update(consumer_ns)

    for n in sorted(inv_norm):
        module = inv_norm[n]
        if n not in endpoints:
            out.append(
                "connectivity undeclared: module {!r} is in the arch-map but no "
                "IF-### row names it".format(module)
            )
            continue
        if n not in consumes and n not in sources:
            out.append(
                "module {!r} declares no Consumes seam (mark it `source` in its "
                "IF row Notes if it deliberately consumes nothing)".format(module)
            )
        if n not in provides and n not in sinks:
            out.append(
                "module {!r} declares no Provides seam (mark it `sink` in its IF "
                "row Notes if it deliberately provides nothing)".format(module)
            )

    # Seam-TC citation: each declared IF id should be cited by >=1 TC (the rung-2
    # seam-TC rule, and process.md §8's "every interface is backed by an SR and a
    # contract/fixture test").
    #
    # THE ARMING KEY HAS NOW MOVED TWICE, AND THE THIRD SPELLING IS "ALL ROWS".
    # It first read `Status == Active`, which armed EXACTLY the 5 rows already
    # TC-cited — zero findings by construction. WI-443 re-keyed it to
    # `Stability == Stable` (103 of 108 uncited). WI-442 retired `Stability` for
    # `Approval`, and copying the shape forward as `Approval == "approved"` would
    # have reproduced the ORIGINAL tautology in a new column: every row reads
    # `draft` today, so the rule would arm on nothing and report a clean zero.
    #
    # So it arms on EVERY real IF row, and the maturity column drops out of the
    # rule entirely. That is the honest reading of the obligation anyway — an
    # interface is backed by a contract test or it is not; how settled its
    # contract is was never the question — and it is the one spelling that cannot
    # be silently disarmed by a vocabulary change.
    #
    # SUMMARISED, not one line per row, and that is a deliberate ergonomic choice
    # rather than a softening: this function runs in the shipped pre-commit hook,
    # where 103 warn lines is a check nobody reads and therefore a check that does
    # not work. One line carries the count, which is the number that has to fall.
    #
    # STAYS PURE WARN-FIRST, FOREVER, EVEN UNDER --strict — the promotable half
    # split off at WI-488 (OI-43 ruled (a)) into `if_tc_coverage_findings` below,
    # which reports only the seams NOT on the migration allowlist. This line keeps
    # reporting the TOTAL uncited count (allowlisted seams included) so the whole
    # debt stays visible even once the actionable subset goes quiet.
    tc_cited = set()
    for r in spine_carrier.load(root / TC_CSV, "TC-ID"):
        tc_cited.update(IF_ID_RE.findall(r.get("Verifies", "") or ""))
    uncited = [r["id"] for r in ifs if r["id"] not in tc_cited]
    if uncited:
        shown = ", ".join(uncited[:5])
        out.append(
            "{} IF seam(s) are cited by no TC (a seam should carry a "
            "contract/fixture test, process.md §8){}: {}".format(
                len(uncited), " — first 5" if len(uncited) > 5 else "", shown
            )
        )

    # Marker-grammar honesty (OI-66): the `Contracts:` marker must OPEN its line
    # and parse as an id list, which is what stops prose that DENIES a
    # declaration from making one. Tightening a shipped grammar may not lose an
    # adopter's seams in silence, so both lossy forms — a marker-shaped line
    # whose id list will not parse, and a `Contracts:` carrying ids mid-line —
    # are reported by name. Warn-first: on this repo the count is zero, and on
    # an upgrading repo it is the migration list.
    out.extend(_contracts_grammar_findings(root))

    # Docstring citation: a `Contracts: IF-###` a script declares (harvested into
    # the arch-map) must exist in the registry; and, once the convention is in
    # use, a registry IF whose OWNER declares no matching citation warns too.
    registry_ids = {r["id"] for r in ifs}
    file_declared = _file_owner_declarations(root, out)
    for module, ids in sorted(declared_contracts.items()):
        for iid in sorted(ids - registry_ids):
            out.append(
                "module {!r} docstring declares Contracts: {} but no such IF-### "
                "row exists".format(module, iid)
            )
    for owner, ids in sorted(file_declared.items()):
        for iid in sorted(ids - registry_ids):
            out.append(
                "{!r} header declares Contracts: {} but no such IF-### row "
                "exists".format(owner, iid)
            )
    if declared_contracts or file_declared:  # reverse direction, once opted in
        out.extend(
            _owner_exact_findings(
                ifs,
                inv_norm,
                declared_contracts,
                file_declared,
                dict(_owner_files(root)),
            )
        )
    return out


def _owner_exact_findings(
    ifs, inv_norm, declared_contracts, file_declared, file_owners
):
    """OWNER-EXACT (OI-67 slice 2): the row's owner is the source that must
    declare it — a module's `Contracts:` line, or a file's header. An id
    declared on some OTHER module used to pass; that is the id-global hole the
    build round named, closed here. Every module in the INVENTORY is judged,
    not only the declaring ones — an owner that declares nothing at all is the
    plainest miss. An `external:` owner has nothing to scan; a directory with
    no README or an owner the tree cannot resolve falls back to the id-global
    read rather than warning about a header nobody could write."""
    out = []
    by_module = {_norm_module(m): ids for m, ids in declared_contracts.items()}
    all_declared = set().union(*declared_contracts.values(), *file_declared.values())
    for r in ifs:
        owner, iid = r["owner"], r["id"]
        if not owner or owner.startswith("external:"):
            continue
        norm = _norm_module(owner)
        if norm in inv_norm:
            if iid not in by_module.get(norm, set()):
                out.append(
                    "IF {} is owned by {!r}, but that module's Contracts: line "
                    "does not declare it — the owner is the one declaration "
                    "site".format(iid, owner)
                )
        elif owner in file_owners:
            if iid not in file_declared.get(owner, set()):
                out.append(
                    "IF {} is owned by {!r}, but that file's header declares "
                    "no Contracts: line naming it — the owner is the one "
                    "declaration site".format(iid, owner)
                )
        elif iid not in all_declared:
            out.append(
                "IF {} is in the registry but no source declares it via a "
                "Contracts: line".format(iid)
            )
    return out


# --- the armed definition gate (OI-67 slice 6) --------------------------------


def _declaration_sites(root):
    """`({key: (source_as_written, ids, bodies)}, problems)` — every source in
    the tree that declares a seam, read through the one harvester the
    interface reference uses (`gen_arch_map.scan_contracts`): the modules under
    the declared scan root, keyed by normalized module path (`scripts/check`),
    and the file owners the registry names, keyed by the owner as the registry
    spells it (`docs/stack.ini`, `hooks/pre-commit`). `problems` is
    `[(source, message)]` for every header the contract GRAMMAR refused, so a
    refusal is reported rather than read as "declares nothing" — and, above
    all, rather than DISARMING the gate: the refusal used to be caught for the
    whole scan and answered with `(None, [])`, so one malformed body anywhere
    in the tree silenced every other row's verdict too (adversarial review
    2026-08-29, F1). A refused source is absent from `sites` rather than
    entered as declaring nothing, which would hand its rows to the reverse
    check's warn instead of this gate's finding. A source the scan could not
    READ is deliberately NOT in `problems`: that is the reference's own "could
    not read" list and `arch_inventory`'s skip. `(None, problems)` when there
    is no surface to read — files-mode, an absent scan root, no generator
    beside this script — the `arch_inventory` posture."""
    if gen_arch_map is None or not hasattr(gen_arch_map, "scan_contracts"):
        return None, []
    src, mode = _arch_scan_profile(root)
    if mode == "files":
        return None, []
    src_dir = root / src.strip().replace("\\", "/").rstrip("/")
    if not src_dir.is_dir():
        return None, []
    owner_files = _owner_files(root)
    refused = []
    records, _unreadable = gen_arch_map.scan_contracts(
        [src_dir], owner_files, grammar_errors=refused
    )
    file_names = {owner for owner, _path in owner_files}
    sites = {}
    for rel, _summary, ids, bodies in records:
        key = rel if rel in file_names else _norm_module(rel)
        sites[key] = (rel, set(ids), set(bodies))
    return sites, refused


def contract_body_findings(root):
    """THE ARMED DEFINITION GATE (OI-67 slice 6). Every interface row must be
    STATED — declared on its owner's `Contracts:` marker and given a
    `Contract IF-###:` body there — because under the one-owner shape the body
    is the definition's only home: a row with no body is an interface with no
    definition. Returns finding strings; the caller prints them WARN plain and
    promotes them to ERROR under `--strict`, the `if_tc_coverage_findings`
    idiom, sharing its `[checks] interfaces_check` opt-out.

    ONE RULE, FOUR SHAPES. (1) The owner declares the id and states no body —
    "declared, not stated", the reference's own debt line, now a finding.
    (2) An `external:`-owned row is declared and stated by the kit module on
    its FAR SIDE — the consumer that reads the external surface, or the
    requestor that drives it — because the external party's header is not
    ours to write and that module is the one in-tree home of OUR READING of
    the surface; where the far side names several kit modules any one of them
    may state it. (3) A stray declaration — a source declaring an id the
    registry owns to a different in-tree source — because the owner is the
    ONE declaration site and a second copy is a second definition waiting to
    disagree; a far-side module stating an external-owned row is not stray.
    (4) A source whose header the contract GRAMMAR refuses — an empty
    `Contract IF-###:` opener, a body before its marker, a duplicate body, a
    body carrying an HTML comment — because nobody can read what it states:
    its declared rows count as unstated, and the refusal is named once per
    source rather than once per row it takes down with it.

    WHAT STAYS A WARN, on record: an owner that declares NOTHING is the
    owner-exact reverse check's finding (`_owner_exact_findings`, warn-only),
    not this gate's — the ruled rule is "a DECLARED seam with no body", and
    promoting the undeclared case would red every fixture and adopter row
    whose owner has not yet been headed at all, which is the migration list
    rather than a defect in a stated definition. The dodge that leaves —
    never declare, never owe a body — is visible in that warn and in the
    reference's summary line, and is the owner's to promote. Vacuous where
    there is no surface (files-mode, an absent scan root), the
    `arch_inventory` posture; an unreadable source is the reference's own
    list, not a finding here."""
    if not read_interfaces_check_enabled(root):
        return []
    sites, refused = _declaration_sites(root)
    if sites is None:
        return []
    out = [
        "{!r} declares seams but its header is refused by the contract "
        "grammar: {} — its declared rows count as unstated".format(rel, msg)
        for rel, msg in refused
    ]
    ifs = load_seams(root)
    file_names = {owner for owner, _path in _owner_files(root)}

    def site_key(owner):
        return owner if owner in file_names else _norm_module(owner)

    owner_key = {}
    for r in ifs:
        if r["owner"] and not r["owner"].startswith("external:"):
            owner_key.setdefault(r["id"], site_key(r["owner"]))
    external_far = {}
    for r in ifs:
        iid, owner = r["id"], r["owner"]
        if not owner:
            continue  # trace.py's required-cell finding
        if owner.startswith("external:"):
            far = [site_key(e) for e in r["far"] if not e.startswith("external:")]
            external_far[iid] = set(far)
            out.extend(_external_body_findings(sites, iid, owner, far))
            continue
        site = sites.get(site_key(owner))
        if site is None:
            continue  # declares nothing, or unresolvable: the reverse check's warn
        rel, ids, bodies = site
        if iid in ids and iid not in bodies:
            out.append(
                "IF {} is declared by its owner {!r} but states no `Contract {}:` "
                "body there — an interface with no definition".format(iid, rel, iid)
            )
    out.extend(_stray_declaration_findings(sites, owner_key, external_far))
    return out


def _external_body_findings(sites, iid, owner, far):
    """The external arm of `contract_body_findings`: `far` is the row's far
    side as site keys (kit modules only); silent when none faces it or one
    states the body, a finding otherwise."""
    if not far or any(k in sites and iid in sites[k][2] for k in far):
        return []
    declared = [sites[k][0] for k in far if k in sites and iid in sites[k][1]]
    if declared:
        return [
            "IF {} is owned by {!r}; its far side {!r} declares it but states no "
            "`Contract {}:` body — our reading of an external surface is stated "
            "by the kit module that faces it".format(iid, owner, declared[0], iid)
        ]
    return [
        "IF {} is owned by {!r} and no far-side kit module states it — our "
        "reading of an external surface lives in the header of the module that "
        "faces it ({})".format(iid, owner, ", ".join(sorted(far)) or "none named")
    ]


def _stray_declaration_findings(sites, owner_key, external_far):
    """The stray arm of `contract_body_findings`: a source declaring an id the
    registry owns to a different in-tree source, or an external-owned id whose
    far side it is not."""
    out = []
    for key, (rel, ids, _bodies) in sorted(sites.items()):
        for iid in sorted(ids):
            if iid in external_far:
                if key not in external_far[iid]:
                    out.append(
                        "{!r} declares IF {}, an external-owned seam whose far side "
                        "it is not — our reading of an external surface is stated "
                        "by the module that faces it".format(rel, iid)
                    )
                continue
            home = owner_key.get(iid)
            if home is None or home == key or home not in sites:
                continue  # unowned (trace's finding), the owner, or unresolvable
            out.append(
                "{!r} declares IF {}, which the registry owns to {!r} — the owner is "
                "the one declaration site; a second copy is a second "
                "definition".format(rel, iid, sites[home][0])
            )
    return out


# --- seam-TC coverage promotion + its migration allowlist (OI-43 ruled (a),
# WI-488) -------------------------------------------------------------------


def _parse_if_tc_allow_full(text):
    """`(entries, seed, unparsed)` — the whole parse, both halves, the
    `docs/provenance-allow` split (`trace.read_provenance_allow`): `entries`
    and `seed` are exactly `parse_if_tc_allow`'s return (kept as a separate,
    pinned-arity wrapper below since `tests/test_trajectory_arch.py` unpacks
    it as a 2-tuple); `unparsed` is `[(lineno, line)]` for every DECLARING
    line the grammar dropped — not blank, not a `#`-comment, and whose first
    token does not parse as an `IF-###` id — so a malformed entry is reported
    rather than silently read as an empty file
    (`if_tc_allow_parse_findings`)."""
    entries = []
    seed = None
    unparsed = []
    for lineno, raw in enumerate(text.splitlines(), start=1):
        line = raw.strip()
        if not line:
            continue
        if line.startswith("#"):
            m = IF_TC_SEED_RE.match(line)
            if m and seed is None:
                seed = int(m.group(1))
            continue
        head, _, reason = line.partition(" — ")
        token = head.split()[0] if head.split() else ""
        if IF_ID_RE.fullmatch(token):
            entries.append((token, reason.strip() or None))
        else:
            unparsed.append((lineno, line))
    return entries, seed, unparsed


def parse_if_tc_allow(text):
    """`([(id, reason-or-None), ...] in file order, declared seed count or
    None)` for one allowlist file's TEXT.

    The SEED COUNT is a machine-readable header key, `# seed-count: <int>`,
    naming how many of the entries below are the migration BASELINE — the
    population measured when the promotion was seeded, which shares one reason
    stated once in the header rather than repeated per line. Entries past that
    count are ADDITIONS, and an addition is a judgment someone made, so it
    carries its own ` — <reason>`. A file that declares no seed count has no
    baseline to grow past; every entry is then read as seeded, which is what an
    adopter's freshly-seeded file looks like before it has ever grown.

    `_parse_if_tc_allow_full` is the same parse plus the malformed-line half;
    this wrapper's 2-tuple return is pinned by
    `test_this_repos_seam_tc_allowlist_is_exactly_its_seeded_set`, so it stays
    exactly as it was rather than growing a third element."""
    entries, seed, _unparsed = _parse_if_tc_allow_full(text)
    return entries, seed


def read_if_tc_allow(root):
    """`{IF-### id: reason-or-None}` from `docs/if-tc-coverage-allow` — the
    seam-TC coverage migration allowlist. Absent file: empty dict.

    Grammar, deliberately the cheap kind: one non-blank, non-`#`-comment line
    per entry, the first whitespace-run-delimited token an `IF-###` id,
    optionally followed by ` — <reason>`. FAIL-SOFT IN THE LOUD DIRECTION, the
    `docs/provenance-allow` rule: a line whose first token does not parse as an
    IF-### id declares nothing and is dropped, so the worst a malformed entry
    can do is leave the finding it was meant to silence still reported — never
    the reverse.

    AN ADDITION BEYOND THE DECLARED SEED NEEDS A REASON, and a bare one
    SUPPRESSES NOTHING — the same fail-soft-loud direction. The 2026-08-21
    review measured why: a new seam reds `--strict`, and the one-line edit that
    greened it was appending its bare id, which was lexically indistinguishable
    from the 120 seeded lines and produced no hygiene signal, no test failure
    and no reason anyone could review. The list is a burn-down; growth has to
    cost a sentence."""
    path = Path(root) / IF_TC_ALLOW
    if not path.is_file():
        return {}
    entries, seed = parse_if_tc_allow(
        path.read_text(encoding="utf-8-sig", errors="replace")
    )
    out = {}
    for i, (token, reason) in enumerate(entries):
        if seed is not None and i >= seed and not reason:
            continue
        out[token] = reason
    return out


def if_tc_allow_growth(root):
    """`([(id, reason-or-None), ...], seed)` — the entries past the declared
    seed count, and that count (None when the file declares none)."""
    path = Path(root) / IF_TC_ALLOW
    if not path.is_file():
        return [], None
    entries, seed = parse_if_tc_allow(
        path.read_text(encoding="utf-8-sig", errors="replace")
    )
    return ([] if seed is None else entries[seed:]), seed


def if_tc_coverage_findings(root):
    """The PROMOTABLE half of seam-TC coverage (OI-43 ruled (a), WI-488): an IF
    seam cited by no TC — the rung-2 seam-TC rule `interface_findings` already
    reports informationally, in full — becomes an ERROR when it is NOT on the
    migration allowlist `docs/if-tc-coverage-allow`. Returns the finding
    string(s) ([] when clean or opted out); the caller prints them WARN plain
    and promotes them to ERROR under `--strict` (DevStg-Tests+), the
    `component_findings` idiom.

    THE ALLOWLIST IS A MIGRATION DEVICE, NOT A PERMANENT EXEMPTION SURFACE. It
    was seeded at the population measured when the ruling executed (the file's
    own header carries the exact count, command and revision) — the standing
    never-green-by-list-edit rule (session-protocol skill §2) governs every
    entry: adding one to silence a genuinely NEW uncited seam is ACCEPTING what
    it measures, not laundering it, and should carry its own reason. An
    allowlisted seam still counts in `interface_findings`' total; it simply does
    not error here. `if_tc_allow_hygiene_findings` reports — never blocks — a
    listed seam that has since gained a TC, so a shrinking list (the declared
    burn-down) stays visible rather than silently absorbed.

    Opt-out shares `interface_findings`' `[checks] interfaces_check` dial —
    same data, same switch — AND its ≤1-module arch-map vacuity: the promoted
    rule must arm on no MORE than the warn it promotes, so a `files`-mode or
    single-module adopter that never saw this warn does not suddenly see this
    error. Widening scope is a second, unruled change riding a severity one.

    DELIBERATELY UNCLAIMED — this function declares no back-link at all.
    `LLR-042` (`SR-159`) is
    `Approved`, and its own `detail` says the connectivity layer emits its
    findings "without changing exit status" — true of `interface_findings`,
    which this function does not touch, and now FALSE of the seam-TC rule this
    function promotes. Amending an Approved cell overrides attestation (the
    sitting's act, the SR-006/LLR-060 precedent, WI-473); minting a fresh
    Drafted LLR under `SR-159` was considered and declined for the same reason
    that session gave first — `SR-159` is phase 1, and a Drafted child would
    drag that phase's derived bar down as a side effect of unrelated work. So
    the built behaviour is ahead of its requirement on purpose, recorded as
    owed on WI-488's own spec rather than claimed here.
    """
    if not read_interfaces_check_enabled(root):
        return []
    inventory, _declared_contracts, _imports = arch_inventory(root)
    if len(inventory) <= 1:
        return []  # nothing to connect — vacuous, the interface_findings gate
    ifs = load_ifs(spine_carrier.load(root / IF_CSV, "IF-ID"))
    if not ifs:
        return []
    tc_cited = set()
    for r in spine_carrier.load(root / TC_CSV, "TC-ID"):
        tc_cited.update(IF_ID_RE.findall(r.get("Verifies", "") or ""))
    allow = read_if_tc_allow(root)
    new_uncited = [
        r["id"] for r in ifs if r["id"] not in tc_cited and r["id"] not in allow
    ]
    if not new_uncited:
        return []
    shown = ", ".join(new_uncited[:5])
    return [
        "{} IF seam(s) have no citing TC and are not on the migration allowlist "
        "({}) — cite the seam from a TC, or add a reasoned entry to the "
        "allowlist (process.md §8; OI-43/WI-488){}: {}".format(
            len(new_uncited),
            IF_TC_ALLOW,
            " — first 5" if len(new_uncited) > 5 else "",
            shown,
        )
    ]


def if_tc_allow_hygiene_findings(root):
    """`docs/if-tc-coverage-allow` hygiene (WI-488) — WARN-ONLY, never the exit
    code, not even under `--strict`: unlike a NEW uncited seam, a STALE entry is
    never a defect to fix under pressure. Two shapes:

    - a listed seam has since gained a TC citation — burn-down PROGRESS, so
      pruning the entry is housekeeping, not a fix owed to a red build;
    - a listed id resolves to no live IF-### row (retired/renumbered).

    Kept structurally apart from `if_tc_coverage_findings` so a shrinking
    allowlist can never itself be mistaken for a new finding, and so this
    class can never gate even by an unintended promotion of that function.
    Shares that function's ≤1-module arch-map vacuity: reporting a listed
    seam as stale is meaningless while the coverage rule it tracks never arms.

    DELIBERATELY UNCLAIMED — see `if_tc_coverage_findings`' own note on why no
    back-link declaration names `LLR-042` here.
    """
    if not read_interfaces_check_enabled(root):
        return []
    allow = read_if_tc_allow(root)
    grown, seed = if_tc_allow_growth(root)
    # `grown` is consulted for the early return too: an addition the reader
    # DROPPED (no reason) leaves `allow` empty while the file still grew, and
    # that is exactly the state most worth reporting.
    if not allow and not grown:
        return []
    inventory, _declared_contracts, _imports = arch_inventory(root)
    if len(inventory) <= 1:
        return []
    ifs = load_ifs(spine_carrier.load(root / IF_CSV, "IF-ID"))
    all_ids = {r["id"] for r in ifs}
    tc_cited = set()
    for r in spine_carrier.load(root / TC_CSV, "TC-ID"):
        tc_cited.update(IF_ID_RE.findall(r.get("Verifies", "") or ""))
    out = []
    unknown = sorted(i for i in allow if i not in all_ids)
    if unknown:
        shown = ", ".join(unknown[:5])
        out.append(
            "{} {} entries name no live IF-### row (retired/renumbered){}: {}".format(
                len(unknown),
                IF_TC_ALLOW,
                " — first 5" if len(unknown) > 5 else "",
                shown,
            )
        )
    if grown:
        # GROWTH IS REPORTED EVEN WHEN EVERY ADDITION IS REASONED, because the
        # list's declared direction is DOWN. A reasoned addition is legitimate
        # and still worth a sitting's attention; an unreasoned one suppresses
        # nothing (see `read_if_tc_allow`) and is named here rather than
        # vanishing silently.
        unreasoned = [i for i, reason in grown if not reason]
        out.append(
            "{} {} entr{} stand past the declared seed of {} — the list is a "
            "burn-down, so growth is a sitting's business{}: {}".format(
                len(grown),
                IF_TC_ALLOW,
                "y" if len(grown) == 1 else "ies",
                seed,
                " ({} carr{} no reason and therefore suppress nothing)".format(
                    len(unreasoned), "ies" if len(unreasoned) == 1 else "y"
                )
                if unreasoned
                else "",
                ", ".join(i for i, _ in grown[:5]),
            )
        )
    stale = sorted(i for i in allow if i in tc_cited)
    if stale:
        shown = ", ".join(stale[:5])
        out.append(
            "{} {} entries are now cited by a TC — prune them (burn-down "
            "progress, never a defect){}: {}".format(
                len(stale), IF_TC_ALLOW, " — first 5" if len(stale) > 5 else "", shown
            )
        )
    return out


def if_tc_allow_parse_findings(root):
    """PARSE HONESTY for `docs/if-tc-coverage-allow`, the
    `kernel_allow_parse_findings` idiom (WI-519): a declaring line the grammar
    cannot read is an explicit finding naming it, not a silent drop — the
    other half of "declares nothing" is that it also grants no exemption, and
    a malformed line that still reads like a live entry to a human is the
    state most worth reporting. Reported at the FIRST unparsed line with a
    count, not all of them, for the same reason `provenance_allow_parse_findings`
    does: the fix is the same edit for every one.

    Shares `if_tc_coverage_findings`' `[checks] interfaces_check` opt-out —
    deliberately NOT its ≤1-module arch-map vacuity, unlike that function and
    `if_tc_allow_hygiene_findings`: a malformed line is a fact about the FILE,
    not about whether the tree is currently large enough for the coverage
    rule to have anything to say, the same reasoning
    `kernel_allow_parse_findings` gives for riding only `components_check`
    and not the top-view bound."""
    if not read_interfaces_check_enabled(root):
        return []
    path = Path(root) / IF_TC_ALLOW
    if not path.is_file():
        return []
    _entries, _seed, unparsed = _parse_if_tc_allow_full(
        path.read_text(encoding="utf-8-sig", errors="replace")
    )
    if not unparsed:
        return []
    lineno, line = unparsed[0]
    return [
        "{}:{}: this line DECLARES a seam-TC exception and the grammar cannot "
        "read it ({} such line(s)) — `{}`. An entry's first token is an "
        "IF-### id, optionally followed by ` — <reason>`; a token that does "
        "not parse as IF-### suppresses nothing".format(
            IF_TC_ALLOW, lineno, len(unparsed), line[:80]
        )
    ]


# --- Implements-tag vs CodeSymbol crosscheck (WI-502; OI-53 ruled (d)) --------
# The 2026-08-21 closing review found the CodeSymbol dozen (WI-501) by hand:
# resolve every `Implements:` tag's ENCLOSING def/class and compare it against
# its row's `CodeSymbol`/`Module` claim. This promotes that manual method into
# a continuous warn-first finding, so the next stale batch is measured rather
# than rediscovered by campaign. WARN-FIRST FOREVER by the ruling — no
# allowlist, no `--strict` arm — because it checks a TRACED, not APPROVED,
# cell (process.md §8's `Module`/`CodeSymbol`/`TestRefs` "traced, not
# approved" posture, cited at check_trajectory.py:77) and a mismatch is
# routine drift, not a defect to gate a commit over.
#
# ONE HOME for the AST walk (WI-486): `gen_arch_map.implements_report` builds
# the (tag site -> enclosing symbol) map and the known-symbol-name set; this
# function only compares them against the registry, the way `arch_inventory`
# already consumes `gen_arch_map.scan_inventory` rather than re-walking trees.
_CODESYMBOL_SPLIT_RE = re.compile(r"[/;]|\s\+\s")


def _codesymbol_candidates(cell):
    """A `CodeSymbol` cell's symbol names, trimmed. `CodeSymbol` is authored
    prose-adjacent, not a strict machine grammar — measured across the live
    registry it mixes `/` (`run/classify`), `;` (`tier_legend...; STATUS_GLYPH`)
    and a spaced ` + ` (`PHASE_ACCENTS + _ring_ink`) as the same "and also"
    join, sometimes in one cell. Splitting on all three costs nothing when a
    candidate is real prose rather than a name — an unmatched fragment simply
    never satisfies containment — and undercounts nothing a single-character
    splitter would have caught, so the wider split is the conservative one."""
    return [c.strip() for c in _CODESYMBOL_SPLIT_RE.split(cell or "") if c.strip()]


def _codesymbol_site_finding(
    rid, site, qualname, module_cell, code_symbol_cell, module_ok, known_names
):
    """One `codesymbol_crosscheck_findings` tag site, resolved to a finding
    string or `None` — split out so the caller's loop stays a plain walk
    (C901) and this comparison, the actual rule, reads as one thing. See
    `codesymbol_crosscheck_findings` for the containment/mismatch/unresolvable
    vocabulary this implements."""
    candidates = _codesymbol_candidates(code_symbol_cell)
    if not candidates:
        contained = module_ok and qualname == ""
    else:
        # Containment reads BOTH directions of the dotted path: a cell naming
        # the CLASS (`RoutingState`) is a prefix of a method's qualname, but
        # the registry just as often names the bare METHOD (`stall_verdict`,
        # no `RoutingState.` qualifier) — the rendered map's own `methods` row
        # lists them unqualified, and most live CodeSymbol cells follow that
        # convention. A suffix match covers that shape without opening the
        # door to a coincidental same-named method on an unrelated class:
        # `Foo.stall_verdict` and `Bar.stall_verdict` both satisfy a bare
        # `stall_verdict` cell, which is the map's own granularity limit, not
        # one this rule invents.
        contained = module_ok and any(
            qualname == c or qualname.startswith(c + ".") or qualname.endswith("." + c)
            for c in candidates
        )
    if contained:
        return None
    enclosing = qualname or "(module scope)"
    resolvable = any(
        c == n or n.endswith("." + c) for c in candidates for n in known_names
    )
    if candidates and not resolvable:
        return (
            "{} tag at {} encloses `{}`, but the row's CodeSymbol `{}` does "
            "not resolve to any def/class under the scanned source — "
            "unresolvable, not matched (Module `{}`)".format(
                rid, site, enclosing, code_symbol_cell, module_cell
            )
        )
    return "{} tag at {} encloses `{}`, but the row's CodeSymbol claims `{}` (Module `{}`)".format(
        rid, site, enclosing, code_symbol_cell or "(module-only)", module_cell
    )


def codesymbol_crosscheck_findings(root):
    """Every live LLR's `Implements:` tag site under the declared arch-map
    source surface (`docs/stack.ini` `[paths] src`), checked by CONTAINMENT
    against its row's `CodeSymbol` + `Module` cells: a tag inside
    `RoutingState.note_session` satisfies a cell naming `RoutingState`; a tag
    at module scope satisfies a module-only (empty `CodeSymbol`) cell. Two
    finding shapes, distinguished so a reader (and the regression tests) can
    tell "the cell names a different REAL symbol" from "the cell names
    nothing resolvable at all" (a function-local variable, or a symbol that
    is simply gone) — the WI-429 census defect this crosscheck is built to
    keep from recurring silently:

    - **mismatch**: at least one of the cell's candidate names IS a real
      def/class somewhere in the scanned surface, just not one that contains
      this tag's site.
    - **unresolvable**: none of the cell's candidate names resolve to any
      real def/class anywhere in the surface — the cell cannot be verified,
      and reporting it as a silent match would be the false-quiet defect
      `docs/enforcement-audit.md` item 5 already names for a neighboring
      grammar (`Contracts:`); this rule does not inherit that shape.

    `[]` (vacuous) when `[arch-map] mode = files` (no parser) or the LLR
    registry has no `Module`/`CodeSymbol` cells to compare against. A tag
    naming an id with no live LLR row, or an LLR id with an empty `Module`
    AND `CodeSymbol` (nothing claimed), is silently skipped — orphan/schema
    integrity is `trace.py`'s finding, not this one's."""
    if gen_arch_map is None:
        return []
    src, mode = _arch_scan_profile(root)
    if mode == "files":
        return []
    src_dir = root / src.strip().replace("\\", "/").rstrip("/")
    if not src_dir.exists():
        return []
    rows = {}
    for r in spine_carrier.load(root / LLR_CSV, "LLR-ID"):
        lid = (r.get("LLR-ID") or "").strip()
        if not lid.startswith("LLR-") or lid.endswith("-000"):
            continue
        module_cell = (r.get("Module") or "").strip()
        code_symbol_cell = (r.get("CodeSymbol") or "").strip()
        if module_cell or code_symbol_cell:
            rows[lid] = (module_cell, code_symbol_cell)
    if not rows:
        return []
    sites, known_names = gen_arch_map.implements_report([src_dir])
    findings = []
    for rel, tags in sorted(sites.items()):
        file_module = _norm_module(rel)
        for lineno, ids, qualname in tags:
            for rid in ids:
                if rid not in rows:
                    continue
                module_cell, code_symbol_cell = rows[rid]
                declared_modules = {_norm_module(m) for m in _split_refs(module_cell)}
                module_ok = not declared_modules or file_module in declared_modules
                finding = _codesymbol_site_finding(
                    rid,
                    "{}:{}".format(rel, lineno),
                    qualname,
                    module_cell,
                    code_symbol_cell,
                    module_ok,
                    known_names,
                )
                if finding:
                    findings.append(finding)
    return findings


def tc_tag_findings(root, tests_dir):
    """Each refused test-file tag under `tests_dir`, the declared tests root, as
    a `<file>:<line>: <shape>: <detail>` string. `check_trajectory` owns the
    declared-root read, so the value is handed in.

    `[]` (vacuous) with no TC registry, and with no tests root, which
    `read_test_tags` walks as no files. `[arch-map] mode = files` is no reason to
    be vacuous: this reads test files, not the source surface. A registry holding
    only `-000` rows is not vacuous either, so every tag there is unknown. No
    `hasattr` guard, unlike this module's other `gen_arch_map` reads: a stale
    sibling must fail loudly, since "no tags" is the reading this rule refuses.

    Implements: SR-157, LLR-365"""
    if gen_arch_map is None or spine_carrier.resolve(root / TC_CSV) is None:
        return []
    rows = spine_carrier.load(root / TC_CSV, "TC-ID", False)
    live_tcs = {(r.get("TC-ID") or "").strip() for r in rows}
    _tags, findings = gen_arch_map.read_test_tags(root, tests_dir, live_tcs)
    return [
        "{}:{}: {}: {}".format(f["file"], f["line"], f["shape"], f["detail"])
        for f in findings
    ]


# --- the How-SW top-view right-sizing rule (WI-073/FB5) ------------------------
# The software-architecture diagram's first view is bounded at TOP_VIEW_MAX
# items = top-level components (a CMP with no PartOf that contains ≥1 arch-map
# module) + uncontained modules. Membership derives from the AXES join: a
# `Component` tag on an LLR joins LLR.Module → CMP-###; CMP nesting via PartOf.
# The derivation below is the ONE home for that join — gen_trajectory imports it
# (`ct.component_top_view`) so the render and this rule can never disagree on the
# count. Small stable loaders duplicated per the F5 convention (no sibling import
# into check_trajectory).


def load_cmps(rows):
    """Real (non-`-000`) CMP-### component rows as dicts (id, name, category,
    partof). Lenient — `trace.py` owns CMP integrity; a malformed id is skipped
    here, since this only feeds the warn-first top-view coverage."""
    out = []
    for r in rows:
        cid = (r.get("CMP-ID") or "").strip()
        if not CMP_ID_RE.match(cid) or cid.endswith("-000"):
            continue
        out.append(
            {
                "id": cid,
                "name": (r.get("Name") or "").strip(),
                "category": (r.get("Category") or "").strip(),
                "partof": [p for p in _split_refs(r.get("PartOf", "")) if p],
            }
        )
    return out


def _cmp_roots(cmps):
    """`{cmp id: set(top-level root ids)}` — walk `PartOf` upward to the root(s)
    (a CMP with no real PartOf is its own root). A PartOf parent that names no
    real CMP is ignored (trace.py flags it separately). Cycle-guarded (a `seen`
    frontier), so a pathological PartOf cycle degrades to the CMP itself rather
    than looping."""
    by_id = {c["id"]: c for c in cmps}
    roots = {}
    for c in cmps:
        seen, frontier, out = set(), [c["id"]], set()
        while frontier:
            n = frontier.pop()
            if n in seen:
                continue
            seen.add(n)
            parents = [p for p in by_id.get(n, {}).get("partof", []) if p in by_id]
            if parents:
                frontier.extend(parents)
            else:
                out.add(n)
        roots[c["id"]] = out or {c["id"]}
    return roots


def module_components(root):
    """`{normalized module key: set(real-looking CMP ids)}` from the LLR
    `Component` tags joined on `LLR.Module` — the AXES membership rule (a module
    belongs to the CMP(s) its LLRs are tagged with). Empty when the LLR registry
    has no `Component` column (legacy) or no tags, so it costs a non-adopter
    nothing. The tag set is left unfiltered against the CMP registry here; the
    caller intersects with the real ids (a phantom tag is trace.py's finding)."""
    out = {}
    for r in spine_carrier.load(root / LLR_CSV, "LLR-ID"):
        lid = (r.get("LLR-ID") or "").strip()
        if not lid.startswith("LLR-") or lid.endswith("-000"):
            continue
        tags = {t for t in _split_refs(r.get("Component", "")) if t.startswith("CMP-")}
        if not tags:
            continue
        # `Module` is a `;`-JOINED LIST, and this reader has to split it (WI-429).
        # It did not, and the bug is the D-6 failure mode exactly: an unsplit
        # `a.py;b.py` normalized to one nonsense key, so a row spanning two
        # modules tagged NEITHER of them — silently, because a membership map
        # that is missing an entry reads identically to a module nobody tagged.
        # The kit's other readers of this cell (`check_doc_refs.SPINE_CELLS`,
        # trace's back-link resolution) already split it; this one had not
        # learned the shape, and 2 live rows were losing their tags before the
        # WI-429 repair widened the same cells to 13.
        for part in _split_refs(r.get("Module", "")):
            key = _norm_module(part)
            if key:
                out.setdefault(key, set()).update(tags)
    return out


def component_top_view(root):
    """The How-SW containment derivation (WI-073), shared by the right-sizing
    rule and the dashboard render so the item count and the picture never
    disagree. Returns a dict:
      inventory    `{norm: display}` arch-map modules (empty pre-arch-map)
      cmps         `[cmp dict]` real CMP rows
      by_id        `{cmp id: cmp dict}`
      children_of  `{cmp id: sorted[child cmp ids]}` (PartOf inverted)
      roots_of     `{cmp id: set(top-level root ids)}` (PartOf resolved up)
      module_cmps  `{norm: set(finest real CMP ids tagged on its LLRs)}`
      module_roots `{norm: set(top-level root ids)}` (derived, real modules only)
      top_roots    sorted `[cmp id]` top-level roots containing ≥1 module
      uncontained  sorted `[norm]` inventory modules with no membership
      count        `len(top_roots) + len(uncontained)`

    Implements: SR-159, LLR-049
    """
    names = arch_inventory(root)[0]
    inventory = {}
    for m in names:
        n = _norm_module(m)
        if n:
            inventory.setdefault(n, m)
    cmps = load_cmps(spine_carrier.load(root / CMP_CSV, "CMP-ID"))
    by_id = {c["id"]: c for c in cmps}
    cmp_ids = set(by_id)
    roots_of = _cmp_roots(cmps)
    children_of = {c["id"]: [] for c in cmps}
    for c in cmps:
        for p in c["partof"]:
            if p in by_id:
                children_of[p].append(c["id"])
    for cid in children_of:
        children_of[cid] = sorted(children_of[cid])

    raw = module_components(root)
    module_cmps, module_roots = {}, {}
    top_roots, uncontained = set(), []
    for n in sorted(inventory):
        tags = raw.get(n, set()) & cmp_ids
        module_cmps[n] = tags
        if not tags:
            uncontained.append(n)
            module_roots[n] = set()
            continue
        r = set()
        for c in tags:
            r |= roots_of[c]
        module_roots[n] = r
        top_roots |= r
    return {
        "inventory": inventory,
        "cmps": cmps,
        "by_id": by_id,
        "children_of": children_of,
        "roots_of": roots_of,
        "module_cmps": module_cmps,
        "module_roots": module_roots,
        "top_roots": sorted(top_roots),
        "uncontained": uncontained,
        "count": len(top_roots) + len(uncontained),
    }


def knowledge_packs(root):
    """Real knowledge-pack labels under `docs/knowledge/` (research-knowledge.md
    §3a) — every `*.md` except the scaffolded `README.md` index. Empty (a
    non-adopter, an absent dir, or the index alone) means the knowledge layer is
    not in use, so the knowledge⇒component coupling stays dormant. Sorted for a
    deterministic count/message."""
    d = root / "docs" / "knowledge"
    if not d.is_dir():
        return []
    return sorted(p.stem for p in d.glob("*.md") if p.name.lower() != "readme.md")


# --- the declared arch-map scan profile -------------------------------------
# (The WI-399 committed-vs-disk delta machinery that lived here —
# _has_internal_import / _would_be_inventoried / shipped_modules /
# added_module_findings — RETIRED at WI-455: arch_inventory reads the live
# source tree, so the delta it bridged no longer exists.)


def _stack_ini_get(root, section, option):
    """ONE lenient docs/stack.ini read (absent file / unreadable or broken
    profile / missing option all → None), shared by `_arch_scan_profile` and
    `_tests_dir` so the idiom has a single home here — check.py owns the loud
    reading of the same profile, and `kitlib.config.read_stack_ini` the parse."""
    try:
        cp = _kitconfig.read_stack_ini(Path(root) / _kitconfig.STACK_INI)
    except _kitconfig.StackIniError:
        return None
    if cp is None or not cp.has_option(section, option):
        return None
    return cp.get(section, option).strip()


def _arch_scan_profile(root):
    """`(src, mode)` from docs/stack.ini — the same `[paths] src` and
    `[arch-map] mode` check.py hands gen_arch_map — read leniently
    (`_stack_ini_get`): an absent or broken profile degrades to the defaults
    (`src`, `symbols`) rather than crashing a warn-tier rule."""
    return (
        _stack_ini_get(root, "paths", "src") or "src",
        _stack_ini_get(root, "arch-map", "mode") or "symbols",
    )


def _declared_seam_pairs(root):
    """The IF registry's endpoint pairs, normalized and stored BOTH ways — a
    seam is one declared relationship, whichever side authored the row.

    A MULTI-ENDPOINT SIDE IS SEVERAL ENDPOINTS, and every combination is a
    declared pair. `trace.py` has split on `;` since IF-097 (the comment there
    names it); this reader did not, so the two readers of the same cells
    disagreed — 14 of 249 pairs carried an unsplit, non-existent module name as
    an endpoint after WI-469 took the population from one row to seven
    (2026-08-21 review, M-14). Latent, but the failure it sets up is expensive
    in the wrong direction: a real cross-component import whose seam row plainly
    names both modules is reported as having no declared seam, and the cheapest
    fix available to that author is to duplicate or delete a correct row.

    PAIRS ARE TAKEN ACROSS THE ROW'S WHOLE ENDPOINT SET since WI-455, not across
    two named cells. On a row whose consumers are a measured READER SET over one
    medium (`IF-029`, `IF-035`, `IF-037`, `IF-047`, `IF-072`) that is what keeps
    the reader-to-reader pairs the two-cell shape used to produce, now stated as
    what they always were: one declared relationship among all of the seam's
    endpoints."""
    covered = set()
    for r in load_seams(root):
        ends = _norm_endpoints([r["owner"]] + r["far"])
        for a in ends:
            for b in ends:
                if a != b:
                    covered.add((a, b))
                    covered.add((b, a))
    return covered


def _norm_endpoints(endpoints):
    """The normalized module keys of an endpoint list, empties dropped — so a
    blank side contributes no pair, exactly as before. Each entry may itself be
    a `;`-joined cell (`kitlib.spine.seam_endpoints` splits those): an endpoint
    may legitimately contain a space (`external:downstream adopter`) or a
    comma, so `;` stays the only separator."""
    out = []
    for endpoint in endpoints:
        for part in _kitspine.seam_endpoints(endpoint):
            normalized = _norm_module(part)
            if normalized:
                out.append(normalized)
    return out


def _parse_kernel_allow(root):
    """`(entries, unparsed)` for `docs/kernel-modules-allow` — the whole parse,
    both halves, the `docs/provenance-allow` split (`trace.read_provenance_allow`):
    `entries` is `[(normalized module key, reason, lineno)]`; `unparsed` is
    `[(lineno, line)]` for every DECLARING line the grammar dropped, so a
    malformed entry is reported rather than silently read as an empty file
    (`kernel_allow_parse_findings`).

    Grammar: one non-blank, non-`#`-comment line per entry, `<module path> —
    <reason>` (an em dash, space each side — the same separator
    `docs/provenance-allow` uses). A REASON IS REQUIRED, unlike
    `docs/if-tc-coverage-allow`'s migration seed: OI-48's reuse provision is
    a deliberate recorded act every time, never a bare-baseline default, so
    there is no seeded-population exception here. A line with no separator,
    or an empty module or reason on either side of it, DECLARES NOTHING — it
    is dropped (fail-safe: absence of a valid declaration grants no
    exemption) and counted as unparsed."""
    path = Path(root) / KERNEL_ALLOW
    if not path.is_file():
        return [], []
    out, unparsed = [], []
    text = path.read_text(encoding="utf-8-sig", errors="replace")
    for lineno, raw in enumerate(text.split("\n"), start=1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if KERNEL_ALLOW_SEP not in line:
            unparsed.append((lineno, line))
            continue
        head, reason = line.split(KERNEL_ALLOW_SEP, 1)
        module = _norm_module(head.strip())
        reason = reason.strip()
        if not module or not reason:
            unparsed.append((lineno, line))
            continue
        out.append((module, reason, lineno))
    return out, unparsed


def read_kernel_modules(root):
    """`{normalized module key: reason}` — the declared shared-kernel surface
    (OI-48 ruled (d), 2026-08-21; executed WI-494). Absent file, or a file
    with no parseable entries: empty dict — the FAIL-SAFE DEFAULT the ruling
    requires, since an empty mapping exempts nothing and every edge stays
    policed by the ordinary cross-component rule.

    `_cross_component_scan` treats an import edge whose DESTINATION resolves
    into this set as not a seam at all — neither a finding nor the
    multi-membership advisory — because the module is a declared shared
    kernel: consumed across components BY DESIGN, and re-declaring that fact
    edge-by-edge (the WI-064 seam registry) would restate "everyone imports
    the shared helper" once per caller (OI-48's option (b), priced and
    declined). The exemption is ONE-DIRECTIONAL: an edge OUT of a kernel
    module — a kernel module importing a non-kernel sibling — is not
    exempted here and stays fully policed, because a shared kernel importing
    outward is the one shape a layered system forbids regardless of who
    calls it (WI-448's dedicated bootstrap-manifest test polices the literal
    kitlib case already; this rule polices any OTHER declared kernel the
    same way going forward).

    NEVER A KITLIB HARDCODE — the reuse provision's whole point: any future
    shared module whose real consumers span components takes this same
    declared path, one entry, one recorded reason, a deliberate act rather
    than a default."""
    return {module: reason for module, reason, _ in _parse_kernel_allow(root)[0]}


def kernel_allow_parse_findings(root):
    """PARSE HONESTY for `docs/kernel-modules-allow`, the
    `provenance_allow_parse_findings` idiom: a declaring line the grammar
    cannot read is an explicit finding naming it, not a silent drop — the
    other half of "declares nothing" is that it also grants no exemption,
    and a malformed line that still reads like a live entry to a human is
    the state most worth reporting. Reported at the FIRST unparsed line with
    a count, not all of them, for the same reason `provenance_allow_parse_findings`
    does: the fix is the same edit for every one.

    Shares `component_findings`' WARN-plain / ERROR-under-`--strict`
    promotion and its `[checks] components_check` opt-out — this file is
    part of the components layer, not a spine-integrity surface, so it rides
    that gate rather than the always-on floor `docs/provenance-allow` uses."""
    _entries, unparsed = _parse_kernel_allow(root)
    if not unparsed:
        return []
    lineno, line = unparsed[0]
    return [
        "{}:{}: this line DECLARES a kernel module and the grammar cannot "
        "read it ({} such line(s)) — `{}`. An entry is `<module path>{}"
        "<reason>` and BOTH fields are required — a bare module path or a "
        "missing separator suppresses nothing".format(
            KERNEL_ALLOW, lineno, len(unparsed), line[:80], KERNEL_ALLOW_SEP
        )
    ]


def _classifiable_edges(root):
    """Yield `(src, dst, src_cmps, dst_cmps)` for every internal import edge
    the cross-CMP rules can classify — both endpoints normalized, both carrying
    at least one REAL CMP membership.

    The vacuity guards live here, so every caller inherits them: no arch-map
    `Imports (internal):` lines, no real CMP rows, an endpoint with no
    `Component`-tag membership (coverage is the containment rule's job, not
    this one's), or an import stem that resolves to no/multiple inventory
    modules."""
    names, _contracts, imports = arch_inventory(root)
    if not imports:
        return
    cmp_ids = {c["id"] for c in load_cmps(spine_carrier.load(root / CMP_CSV, "CMP-ID"))}
    if not cmp_ids:
        return
    raw = module_components(root)
    membership = {n: tags & cmp_ids for n, tags in raw.items()}
    # A bare imported stem (`agent_route`) resolves against the inventory's
    # normalized module names (`scripts/agent_route`) by unique-stem match —
    # the same resolution gen_arch_map applied when it emitted the line.
    by_stem = {}
    for m in names:
        n = _norm_module(m)
        if n:
            by_stem.setdefault(n.rsplit("/", 1)[-1], set()).add(n)
    for src in sorted(imports):
        src_n = _norm_module(src)
        src_cmps = membership.get(src_n, set())
        if not src_cmps:
            continue
        for stem in sorted(imports[src]):
            targets = by_stem.get(stem, set())
            if len(targets) != 1:
                continue  # unknown/ambiguous stem — not this rule's finding
            dst_n = next(iter(targets))
            dst_cmps = membership.get(dst_n, set())
            if dst_cmps:
                yield src_n, dst_n, src_cmps, dst_cmps


_SCAN_CACHE = {}


def _cross_component_scan(root):
    """`(findings, advisories)` over the classifiable import edges — the two
    tiers of the cross-CMP rule, computed in ONE pass so they can never disagree
    about which edge is which.

    A **finding** (unchanged since WI-064) is an edge whose endpoint component
    sets are DISJOINT and which no declared IF-### row covers.

    An **advisory** (WI-440, OI-14) is an edge the overlap guard SUPPRESSES only
    because an endpoint is tagged into more than one component: the sets
    intersect, no IF row covers the pair, and `len(cmps) > 1` somewhere. That
    edge would be a finding under a partition where each module belongs to one
    component, so the multi-membership is EVIDENCE ABOUT THE PARTITION (the file
    splits, the shared part is its own component, or the boundary is drawn
    wrong) rather than a licence to stay quiet. Reporting it reverses the
    direction of the old rule, where authoring one more `Component` tag
    monotonically silenced the check — a fail-open the author controls.

    An edge whose endpoints are single-tagged into the SAME component is
    ordinary intra-component wiring and is neither.

    A THIRD, EARLIER exit (OI-48 ruled (d), WI-494): an edge whose
    DESTINATION is a declared shared-kernel module (`read_kernel_modules`) is
    not a seam at all — neither a finding nor the multi-membership advisory.
    Checked before the overlap split, so a kernel module that still carries a
    residual multi-tag is not ALSO advised about (the advisory exists to
    surface undeclared candidates; a module already declared kernel is a
    settled candidate, not an open one). One-directional by construction —
    the exemption keys on `dst_n`, never `src_n`, so an edge OUT of a kernel
    module stays exactly as policed as any other edge.

    ONE scan per run, cached per root: the two public wrappers used to each
    trigger their own scan from `main`, so the two tiers were computed from two
    separate reads of the same registries — the exact could-disagree state this
    function's contract forbids (and a review round demonstrated with a
    mid-run registry change). The cache makes the docstring's "computed in ONE
    pass" literally true for the process's lifetime.
    """
    cached = _SCAN_CACHE.get(str(root))
    if cached is not None:
        return cached
    # `covered` and `kernel` are resolved LAZILY: with zero classifiable edges
    # the old rule never read interfaces.csv (or now kernel-modules-allow) at
    # all, and an unreadable file must not turn a vacuous scan into a crash
    # (review finding, extended to the new surface for the same reason).
    covered = None
    kernel = None
    findings, advisories = [], []
    for src_n, dst_n, src_cmps, dst_cmps in _classifiable_edges(root):
        if covered is None:
            covered = _declared_seam_pairs(root)
        if (src_n, dst_n) in covered:
            continue
        if kernel is None:
            kernel = read_kernel_modules(root)
        if dst_n in kernel:
            continue
        edge = "{} ({}) -> {} ({})".format(
            src_n,
            "/".join(sorted(src_cmps)),
            dst_n,
            "/".join(sorted(dst_cmps)),
        )
        if src_cmps & dst_cmps:
            multi = [m for m, c in ((src_n, src_cmps), (dst_n, dst_cmps)) if len(c) > 1]
            if multi:
                advisories.append(
                    "multi-component module(s) {} suppress the cross-component "
                    "seam rule on import {} — the shared tag, not a declared "
                    "IF-### row, is what silences this edge; split the module, "
                    "give the shared part its own component, or declare the "
                    "seam in {} (advisory only — never the exit "
                    "code)".format(", ".join(multi), edge, IF_CSV)
                )
            continue
        findings.append(
            "cross-component import {} has no declared IF-### seam — declare "
            "the interface row in {} or retag the membership, or set "
            "docs/process.toml [checks] components_check = false".format(edge, IF_CSV)
        )
    _SCAN_CACHE[str(root)] = (findings, advisories)
    return findings, advisories


def cross_component_findings(root):
    """The cross-CMP-edge-without-IF rule (WI-064; the AXES approved model's
    "Enforceability" ruling, process-options.md "Component layer"): an internal
    import edge whose endpoints belong to *different* CMP-### components must be
    covered by a declared IF-### row — an undeclared cross-component coupling is
    a finding, mechanized from the same committed artifacts the other component
    rules read. The CALLER gates the opt-out (`component_findings` shares
    `[checks] components_check`) and the WARN-plain / ERROR-under-`--strict`
    promotion. See `_cross_component_scan` for the tier split (this is tier one)
    and `_classifiable_edges` for the vacuity guards this rule inherits —
    including the DELIBERATE vacuousness for an endpoint carrying no
    `Component` tag, which stays the containment rule's job, not this one's.
    Since OI-48 (WI-494) an edge into a declared shared-kernel module
    (`read_kernel_modules`, `docs/kernel-modules-allow`) is exempted here
    before either tier — see `_cross_component_scan`'s "THIRD, EARLIER exit".

    Implements: SR-159, LLR-067
    """
    return _cross_component_scan(root)[0]


def cross_component_advisories(root):
    """The multi-membership overlap advisory (WI-440, OI-14's third
    do-not-wait): the edges the overlap guard silences because an endpoint
    carries more than one `Component` tag — see `_cross_component_scan`.

    WARN-ONLY, never the exit code, not even under `--strict`: this reports a
    question about the PARTITION, and no partition has been ruled yet, so it
    must not block. Shares `component_findings`' `[checks] components_check`
    opt-out, which the caller does NOT gate for it — this function does."""
    if not read_components_check_enabled(root):
        return []
    return _cross_component_scan(root)[1]


def component_findings(root):
    """The How-SW component-coverage finding(s) (process-options.md "Component
    layer"). Returns the finding strings ([] when opted out or clean). The caller
    prints them WARN plain and promotes them to ERROR under `--strict` (DevStg-Tests+).
    Opt-out via `[checks] components_check = false`. Five rules, all off the arch-map ⇒
    CMP join:

    - **Top-view right-sizing** (WI-073/FB5): vacuous when the arch-map inventory
      has ≤ TOP_VIEW_MAX modules (a small or pre-arch-map repo can never exceed the
      bound — the bound, not the registry, is the rule). Only when the inventory
      itself is larger than the bound do the declared components decide: a
      right-sized handful of top-level CMPs brings the top view back under it.
    - **Knowledge⇒component coupling** (WI-153; research-knowledge.md §3a,
      owner-ruled 2026-07-14): when ≥1 knowledge pack exists the component web is
      *expected* — any arch-map module the CMP join leaves uncontained is a finding
      regardless of the bound, because packs tie the *what* to the knowledge behind
      the *how* and that web must be robust wherever packs are enabled. Arms the
      existing join from pack presence; invents no new join, and is dormant (no
      cost to a non-adopter) until `docs/knowledge/` holds a real pack.
    - (The WI-399 "containment owed where a module is ADDED" delta rule is
      RETIRED — WI-455 made the inventory the LIVE source tree, so a lane's
      added module is simply IN the inventory and the coupling rule above
      fires on it directly; there is no committed-vs-disk gap left to bridge.)
    - **Cross-CMP edges need a declared seam** (WI-064): see
      `cross_component_findings` — an import edge between two components with
      no covering IF-### row. Its warn-only sibling
      `cross_component_advisories` (WI-440) reports the edges a multi-tagged
      endpoint silences; main() prints those, not this function, because they
      must never reach the exit code. An edge into a declared shared-kernel
      module (OI-48 (d), WI-494) is exempted from BOTH before either can fire
      — see `_cross_component_scan`.
    - **Declared-kernel allowlist hygiene** (OI-48 (d), WI-494): see
      `kernel_allow_parse_findings` — a `docs/kernel-modules-allow` line the
      grammar cannot read (missing module, missing reason, or no separator)
      is reported, the same parse-honesty shape
      `if_tc_allow_hygiene_findings` and `provenance_allow_parse_findings`
      use for their own allow-files. A malformed line grants no exemption
      either way (fail-safe), so this rule is reporting, never gating, the
      fail-safe default — it just says so out loud instead of leaving the
      author to notice a seam finding that did not go away.

    Implements: SR-159, LLR-049
    """
    if not read_components_check_enabled(root):
        return []
    view = component_top_view(root)
    out = []
    packs = knowledge_packs(root)
    if packs and view["inventory"] and view["uncontained"]:
        # The module NAMES ride in the finding (capped): the retired WI-399
        # delta message carried them so a lane knew WHICH file to tag, and
        # under the live inventory (WI-455) this rule is that lane's first
        # and only firing point.
        shown = ", ".join(view["uncontained"][:8]) + (
            ", …" if len(view["uncontained"]) > 8 else ""
        )
        out.append(
            "docs/knowledge/ holds {} pack(s) but {} arch-map module(s) are in no "
            "CMP-### component ({}); tag them via LLR `Component` cells in {} so "
            "the knowledge⇒component web is complete, or set docs/process.toml "
            "[checks] components_check = false".format(
                len(packs), len(view["uncontained"]), shown, CMP_CSV
            )
        )
    if len(view["inventory"]) > TOP_VIEW_MAX and view["count"] > TOP_VIEW_MAX:
        out.append(
            "How-SW top view has {} items ({} top-level component(s) + {} "
            "uncontained module(s)) — exceeds the bound of {}; declare CMP-### "
            "components in {} to contain modules (nest with PartOf), or set "
            "docs/process.toml [checks] components_check = false".format(
                view["count"],
                len(view["top_roots"]),
                len(view["uncontained"]),
                TOP_VIEW_MAX,
                CMP_CSV,
            )
        )
    out.extend(cross_component_findings(root))
    out.extend(kernel_allow_parse_findings(root))
    return out


# --- specs act on declared interface boundaries (WI-191) -----------------------
_IF_TOKEN_RE = re.compile(r"\bIF-\d+\b")
_INTERFACES_HEADING_RE = re.compile(r"(?im)^[ \t]*##[ \t]+Interfaces\b.*$")
# The intra-module escape hatch (PROCESS.md §8 scoping): a spec whose WIs act only
# within one module states that instead of inventing a seam.
_INTRA_MODULE_RE = re.compile(
    r"intra-module|single-module|no (?:cross-module )?seam|no interface|no cross-module",
    re.I,
)


def _spec_interfaces_section(text):
    """The body of a spec's `## Interfaces` section (between that heading and the
    next `## ` heading / EOF), or None when the spec has no such heading — the
    unarmed case that keeps the check vacuous-until-armed."""
    m = _INTERFACES_HEADING_RE.search(text)
    if not m:
        return None
    rest = text[m.end() :]
    nxt = re.search(r"(?m)^[ \t]*##[ \t]+", rest)
    return rest[: nxt.start()] if nxt else rest


def _armed_specs(root):
    """The live `docs/specs/` files that are real specs-of-record, sorted.

    The skip rule is a POLICY — the specs README documents the convention in
    prose and `WI-000` is the inert example, so neither is an armed spec — and it
    was stated at both walk sites. WI-344's `spec-scan` block; stating it once
    means a change to what counts as armed cannot land in one checker and not the
    other. Empty (never an error) when there is no specs dir."""
    specs = root / SPECS_DIR
    if not specs.is_dir():
        return []
    return [
        path
        for path in sorted(specs.glob("*.md"))
        if path.name.lower() != "readme.md" and not path.stem.endswith("-000")
    ]


def spec_interface_findings(root):
    """WI-191 — a spec-of-record acts on DECLARED interface boundaries. A spec's
    `## Interfaces` section must cite only IF-### seams that resolve in
    `interfaces.toml` (the one seam home, PROCESS.md §8). WARN plain / ERROR
    under `--strict` (DevStg-Tests+), like `component_findings`; the caller owns
    that promotion.

    THE ANTI-DUPLICATION ARM RETIRED AT WI-442, AND IT IS NOT A SILENT DROP.
    Until decision 4 this function also demanded a rationale on the citation line
    of any `Stability = Experimental` seam — the forced nearest-existing-IF
    search. Its arming input was DELETED: the slimmed tier has one maturity
    field with two values, and neither means what `Experimental` meant ("proposed
    and not yet pinned by a second consumer"). Re-keying onto `approval ==
    "draft"` was the obvious move and is the WRONG one: it silently changes the
    predicate to "not yet approved", which on this repo's registry arms 113 of
    113 rows instead of 5, and it does so at a severity that ERRORS under
    --strict. A rule whose blast radius multiplies twentyfold while its sentence
    stays the same is not the same rule.

    So the arm is GONE rather than approximated, and its loss is a recorded
    finding of the re-tier (log entry, WI-442) with a home at sitting 3: if the
    forced search is worth keeping, it needs a value that means "proposed",
    which is a vocabulary decision (D-9/decision 12), not a checker's to invent.

    **Vacuous-until-armed:** a spec with no `## Interfaces` heading is skipped, so
    existing specs and downstream repos stay green until they adopt the section.
    An armed section that cites no resolvable IF-### AND states no intra-module
    escape (PROCESS.md §8) is itself a finding — an empty-ceremony section."""
    specs = root / SPECS_DIR
    if not specs.is_dir():
        return []
    if_rows = {r["id"]: r for r in load_ifs(spine_carrier.load(root / IF_CSV, "IF-ID"))}
    out = []
    for path in _armed_specs(root):
        section = _spec_interfaces_section(
            path.read_text(encoding="utf-8", errors="replace")
        )
        if section is None:
            continue  # unarmed — no `## Interfaces` section
        rel = "{}/{}".format(SPECS_DIR, path.name)
        ids = list(dict.fromkeys(_IF_TOKEN_RE.findall(section)))
        if not ids:
            if not _INTRA_MODULE_RE.search(section):
                out.append(
                    "{}: `## Interfaces` cites no IF-### and states no "
                    "intra-module escape — cite the seam(s) the WI acts on, or "
                    "state the intra-module case (PROCESS.md §8)".format(rel)
                )
            continue
        for iid in ids:
            if iid not in if_rows:
                out.append(
                    "{}: `## Interfaces` cites {} which resolves to no row in "
                    "{}".format(rel, iid, IF_CSV)
                )
    return out


__all__ = (
    "_first_declared_line",
    "_process_check",
    "_split_refs",
    "TC_CSV",
    "IF_CSV",
    "LLR_CSV",
    "CMP_CSV",
    "SPECS_DIR",
    "TOP_VIEW_MAX",
    "IF_ID_RE",
    "KERNEL_ALLOW",
    "KERNEL_ALLOW_SEP",
    "IF_TC_ALLOW",
    "IF_TC_SEED_RE",
    "CMP_ID_RE",
    "read_interfaces_check_enabled",
    "read_components_check_enabled",
    "_MODULE_EXTS",
    "_norm_module",
    "load_ifs",
    "load_seams",
    "_contracts_grammar_findings",
    "_owner_files",
    "_file_owner_declarations",
    "arch_inventory",
    "interface_findings",
    "_owner_exact_findings",
    "_declaration_sites",
    "contract_body_findings",
    "_external_body_findings",
    "_stray_declaration_findings",
    "_parse_if_tc_allow_full",
    "parse_if_tc_allow",
    "read_if_tc_allow",
    "if_tc_allow_growth",
    "if_tc_coverage_findings",
    "if_tc_allow_hygiene_findings",
    "if_tc_allow_parse_findings",
    "_CODESYMBOL_SPLIT_RE",
    "_codesymbol_candidates",
    "_codesymbol_site_finding",
    "codesymbol_crosscheck_findings",
    "tc_tag_findings",
    "load_cmps",
    "_cmp_roots",
    "module_components",
    "component_top_view",
    "knowledge_packs",
    "_stack_ini_get",
    "_arch_scan_profile",
    "_declared_seam_pairs",
    "_norm_endpoints",
    "_parse_kernel_allow",
    "read_kernel_modules",
    "kernel_allow_parse_findings",
    "_classifiable_edges",
    "_SCAN_CACHE",
    "_cross_component_scan",
    "cross_component_findings",
    "cross_component_advisories",
    "component_findings",
    "_IF_TOKEN_RE",
    "_INTERFACES_HEADING_RE",
    "_INTRA_MODULE_RE",
    "_spec_interfaces_section",
    "_armed_specs",
    "spec_interface_findings",
)
