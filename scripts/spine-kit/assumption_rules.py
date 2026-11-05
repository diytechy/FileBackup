"""THE ASSUMPTION TIER'S RULES — pure joins over the assumptions registry.

The sibling of `frame_rules.py`, and built the same way: every rule here is a
JOIN ACROSS ROWS, it reads no file, and `trace.analyze` composes it and stays
the only caller of its rules. `trace.py` is held to an exact size ratchet, so
the tier's rules land here and `trace.py` grows by the composition lines alone
(spine map D21). Two other readers take one derivation from here and no rule:
the stage derivation and the red-TC census read `da_citing_srs`, because an
assumption's citing requirements are what place and count its evidence. And
the observation writer reads one rule, `record_policy_problem`, so the record
it refuses is exactly the record the checker would fail.

What the tier records. A requirement states what the system does at its own
boundary and a stakeholder need what a person experiences; between them sits a
claim about the world, and a false one makes a fully verified system deliver
nothing. `docs/requirements/assumptions.toml` holds each such claim as a row of
its own (`[assumption.DA-###]`, SR-191): where its outcome lands, what it
assumes, when it holds, the obstacle under which it fails, its maturity and its
validity. Beside it sit the stand-ins that answer for an outside party in tests
(`[surrogate.SUR-###]`, SR-192); a stand-in is evidence only as far as it
matches the party it replaces, so an assumption naming it in `RealizedBy`
states that match, and lands on a crossing of a party it emulates.

Each requirement then cites the assumptions its argument relies on
(`DA-Refs`), or records in `Coincident` why its own specification alone
delivers its needs (SR-193), and declares its `Form` (SR-194). An assumption no
requirement cites, or with no falsifying signal, is reported (SR-196). The need
link stays on the requirement: an assumption's needs are derived from the
requirements citing it (`da_citing_srs`), and nothing records them on the
assumption.

A TEST CASE NAMES THE ASSUMPTIONS IT CAN FALSIFY (SR-197): its
`Assumption-Refs`, in place of or beside what its `Verifies` names. And many
such tests are OBSERVATIONS (a person reading a render, a measurement across an
adopter's first week) that the harness cannot rerun. A test case recorded as
not automated declares the inputs its judgment reads, how many days its result
holds, and, citing an assumption, how it samples (SR-198), so a changed input
or an expired lifetime can make the result stale without anyone re-judging it.
Those declarations are judged here too; they apply to every observation case,
with or without a frame.

AND THE RESULTS THEMSELVES. Each observation result is a record of its own
(`kitlib.observation`, SR-199), judged here against the case it names. An
assumption carries NO EVIDENCE LEVEL (owner ruling 2026-10-02): a passed
observation proves nothing beyond its sample, so no result raises an
assumption and no rule asks one for current evidence. The one evidence-shaped
signal is falsification: one shown false, by its standing or by a failing
sample, is listed with every requirement, need and case relying on it
(SR-201), and recording it false stays a person's act on its `Standing`. A
recorded accepted risk covers an assumption only while the texts the act
accepting it saw still stand and no sample has failed since (SR-202).
`trace.main` has the files and the history these rules need read once
(`record_observation.evidence_inputs`) and composes them through
`observation_evidence_findings`.

WHERE THE TIER APPLIES. An assumption's outcome lands on a boundary crossing,
so with no declared crossing there is nothing to land on and the whole tier is
silent (SR-191's applies-when). And the requirement-side reports ask nothing of
a project that has not adopted the tier: until the registry holds a real
assumption row, no requirement is asked for a citation or a form. Every
adopter is scaffolded the blank form, so the file existing is not adoption.
The two rules at the end of this module stand apart (IF-208) and wait for no
declared crossing: each boundary interface is asked whether assumptions bridge
it or its reading is the outcome (SR-211), and each assumption's obstacle
perspectives are resolved against the hats roster (SR-214). The bridging rule
takes the requirement side's adoption rule whole, so a project that never
adopts the tier is not handed one line per boundary seam: before the first real
assumption row, every assumption a seam names is necessarily undeclared, so a
failure that survived would be that worklist under another name.

Rows are the carrier's column-keyed dicts (`DA-ID`, `EffectAt`, `SUR-ID`,
`Emulates`, `SR-ID`, `DA-Refs`, `EXT-ID`, `B-ID`, `Entity`), exactly as
`trace.load_registries` hands them over; a list cell arrives `;`-joined. Every
function returns plain finding strings, and no function writes to a row it is
handed.

Stdlib only. A plain sibling of `scripts/`, not a `kitlib` module, for the
reason `coherence.py` records: these are the checker's rules, and the
scaffolder has no business importing them.

Contracts: IF-190, IF-200, IF-201, IF-208, IF-216, IF-226, IF-231 — the seams
this module declares (process.md §8; rows of record in docs/requirements/interfaces.toml).

Contract IF-190: the assumption tier's rule surface `trace.py` imports. Rows in,
    findings out, and nothing else: no I/O, no git, no filesystem, no argv.
    `assumption_tier_findings(srs, das, surs, exts, bifs)` is the tier as the
    checker composes it and returns `(frame, integrity, advisories)`: the
    frame list joins the frame class and `trace.py --strict`'s exit code, the
    integrity list joins the always-on `--strict-integrity` floor, and the
    advisories ride the warn pipe and never join a failure set. It returns
    three empty lists when `bifs` declares no crossing, and asks no requirement
    for a form until `das` holds a real assumption row. The rules it composes
    are public and callable alone: `assumption_row_findings(das, bifs)` returns
    failures, `surrogate_findings(surs, das, exts, bifs)`,
    `sr_classification_advisories(srs, das)` and `sr_form_findings(srs)`
    return `(failures, advisories)`, and `uncited_assumption_advisories(das,
    srs)` and `no_falsifier_advisories(das)` return advisories. Two data reads
    ride the same seam: `da_citing_srs(srs)` maps each cited assumption id to
    the requirement ids citing it, and `classify_srs(srs, das)` maps each
    requirement id to one of `SR_CLASSES`. A row whose id ends `-000` is the
    template's example and is never judged.
    Two reach reports ride the same seam as advisories, composed by the checker
    beside the tier: `assumption_reach_advisories(das, srs, needs, stks, exts,
    bifs, surs)`, silent when `bifs` declares no crossing, and
    `need_frame_gap_advisories(needs, stks, srs, bifs, das)`, silent with no
    operation crossing or no agreed stakeholder. `needs` are
    `spine_carrier.load_needs`' rows. `reaching_parties(needs, stks, exts)` is
    their data read: each need id mapped to the set of entities a crossing
    must belong to in order to reach it.

Contract IF-200: the observation test declaration's rules `trace.py` imports.
    Rows in, findings out, with no I/O. `observation_tc_findings(tcs)` returns
    `(failures, advisories)`: the failures join the always-on
    `--strict-integrity` floor and the advisories ride the warn pipe, each
    naming its row. It applies whatever the frame declares. Two reads ride the
    same seam: `is_observation_tc(tc)`, true when the `Automated` cell reads
    No, and `sampling_model_declared(tc)`, true only for a sampled case whose
    sample size and acceptance rule are both valid. A `-000` row is never
    judged. `input_escape(name)` says why a declared input names a path
    outside the repository (absolute, drive-qualified or still climbing with
    `..` once normalized, in either separator style), or None; such an input
    is a failure here, the observation writer refuses its case and digests it
    without reading it, and the checkpoint re-judge reads it the same way.
    `input_path(name)` is the repository-relative path an inside input names,
    normalized, or None for an escaping one.
Contract IF-201: the one derivation of an assumption's citing requirements,
    `da_citing_srs(srs) -> {assumption id: [requirement ids]}` in row order,
    read by the stage derivation and the red-TC census. Pure over requirement
    rows in the carrier's column names; a `-000` row contributes nothing, and a
    requirement citing no assumption appears nowhere in the map.

Contract IF-208: the tier's two pointer rules that land in OTHER classes, which
    `trace.py` imports beside the tier entry point and composes itself. Rows in,
    findings out, on the same terms as IF-190. `interface_bridge_findings(ifs,
    das)` returns `(failures, advisories)` over boundary interfaces alone
    (a from- or to-external tie-back): the failures, a `BridgedBy` entry naming
    an undeclared assumption, join the interface class and `--strict`'s exit
    code; the advisories, a boundary interface with neither `BridgedBy` nor
    `Coincident`, ride the warn pipe. Both are empty until `das` holds a real
    assumption row. `obstacle_hat_findings(das, hat_names)` returns failures,
    each an `ObstacleHats` entry the roster names in `hat_names` do not hold,
    joining the dangling-hat class; an empty `hat_names` means no roster, so
    every named perspective fails. Neither waits for a declared crossing.
Contract IF-216: the observation results and what they can falsify, the rules
    `trace.py` composes and the writer's one policy read. Rows and already-read
    inputs in, findings and readings out, with no I/O, no git and no clock.
    `observation_evidence_findings(srs, das, tcs, needs, bifs, *, records,
    raw_files, views, gate=False)` returns `(integrity, advisories)`: every
    record file that is not a whole record or that its case does not allow
    joins the integrity floor, naming the file, with or without a frame; where
    the frame declares a crossing, the falsification worklist and each
    reopened accepted risk ride the warn pipe. Its rules are public:
    `record_policy_problem(tid, tc, observed_at, expires)` (the writer's
    refusal and the checker's finding, one statement),
    `observation_record_findings`, `falsification_worklist` and
    `accepted_risk_state` (one of `RISK_COVERED`, `RISK_UNPROVEN`, with its
    reasons). A view is `baseline_snapshot.risk_acceptance_view`'s dict.
Contract IF-226: the chain the approval brief renders for one assumption or
    surrogate, read by `trace.py`'s brief. `assumption_chain(da_id, reg)`
    returns a dict, or None for an id the registry does not declare, and reads
    no file: `reg` maps `srs`, `needs`, `das`, `surs`, `exts`, `bifs` and
    `tcs` to what the caller already read, a missing key reading as empty. An
    assumption's chain carries `citing` as `(id, title, requirement)`, `needs`
    as `(id, need)`, `landing` as `(crossing, entity, name)`, `cases` (the
    test cases that can falsify it), `falsifier` and, for a fidelity
    assumption, `surrogate`, that surrogate's chain; a surrogate's carries
    `emulates` as `(id, name)` and `named_by` as `(id, assumption)`. Both
    carry `row`, the row itself.
Contract IF-231: the assumption gate's rules, read by the gate's check step
    (`check_assumption_gate.py`). Rows and already-derived readings in,
    finding strings out, with no I/O; whether a finding fails or advises is
    the step's. `boundary_gate_findings(srs, das, surs, reach, have_frame)`
    (SR-205), with `reach` from `reach_gaps(das, srs, needs, stks, exts, bifs,
    surs) -> {assumption id: [reasons]}`, the reach check's own derivation;
    `crossing_gate_findings(srs, das, bifs)` and
    `interface_form_gate_findings(srs, ifs, llrs)` (SR-212's Boundary and Arch
    arms), over `if_reached_srs(ifs, llrs) -> {interface id: [requirement
    ids]}` and `module_srs(llrs) -> {module: [requirement ids]}`; and
    `release_gate_findings(das, srs, risks)` (SR-206), with `risks` mapping
    each assumption id to its `accepted_risk_state` pair. A `-000` row is never
    judged.
"""

import datetime
import posixpath
import re

try:
    from kitlib.spine import (
        FORM_VALUES,
        MAX_AGE_FLOOR_DAYS,
        SAMPLING_VALUES,
        STATUS_VALUES,
        is_example,
        refs,
    )
    from kitlib.spine import is_approved, is_founded, norm_module
except ImportError:  # pragma: no cover - in-process fallback
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from kitlib.spine import (
        FORM_VALUES,
        MAX_AGE_FLOOR_DAYS,
        SAMPLING_VALUES,
        STATUS_VALUES,
        is_example,
        refs,
    )
    from kitlib.spine import is_approved, is_founded, norm_module

# The observation record's reader (SR-199): the shipped package again,
# importable once the block above has put this directory on the path.
from kitlib.observation import format_utc, latest, parse_utc
from kitlib.observation import problem as record_problem
from kitlib.spine import is_approved, is_founded

# THE ASSUMPTION ROW'S REQUIRED CELLS (SR-191), in the carrier's column names.
# `Falsifier` is deliberately absent: an assumption is often written before the
# signal that could show it false exists, so a missing one is reported by
# `no_falsifier_advisories` rather than failed here. `AcceptedRisk`,
# `RealizedBy` and `ObstacleHats` are optional by their own requirements.
# Implements: SR-191, LLR-219
DA_REQUIRED = ("EffectAt", "Assumption", "HoldsWhen", "Obstacle", "Status", "Standing")

# An assumption's VALIDITY, separate from its maturity: an approved assumption
# can later be shown false, and `Status` cannot say so without un-approving it.
# Implements: SR-191, LLR-219
STANDING_VALUES = ("active", "falsified")

# THE SURROGATE ROW'S REQUIRED CELLS (SR-192), in the carrier's column names.
# `Emulates` is a list, and an empty one counts as missing: a stand-in that
# answers for nobody is not a stand-in.
# Implements: SR-192, LLR-221
SUR_REQUIRED = ("Name", "Emulates", "Description", "Status")

# How a requirement's argument delivers its needs (SR-193). `bridged`: it cites
# declared assumptions; `joint`: it names the sibling requirements that deliver
# the need with it; `coincident`: its own specification delivers its needs;
# `unclassified`: none of those; `both`: an assumption citation and a
# coincident waiver at once, which contradict each other. A joint row may also
# cite assumptions of its own without inheriting any from its siblings.
# Implements: SR-193, LLR-223
SR_CLASSES = ("bridged", "joint", "coincident", "unclassified", "both")

# AN OBSERVATION CASE'S DECLARATION CELLS (SR-198), in the carrier's column
# names: the cells an automated case has no use for, since the harness reruns
# it and nothing it produces goes stale by age.
OBSERVATION_CELLS = ("Inputs", "MaxAge", "Sampling", "SampleSize", "AcceptanceRule")

# A whole number of days or samples, written in digits: `7.5`, `seven` and `-3`
# are not. The carrier hands an integer cell over as its text.
_WHOLE = re.compile(r"[0-9]+")
# A drive-qualified path (`C:`, `c:\`), which is absolute on Windows.
_DRIVE = re.compile(r"\A[A-Za-z]:")


def _cell(row, column):
    """One cell, stripped; `""` when the row does not carry it."""
    return (row.get(column) or "").strip()


def _real(rows, id_col):
    """`(id, row)` for each row that is not the template's `-000` example."""
    for row in rows:
        rid = _cell(row, id_col)
        if rid and not is_example(rid):
            yield rid, row


def _adopted(das):
    """Whether the registry holds a real assumption row: the one sign a project
    has adopted the tier, since every scaffold receives the blank form."""
    return next(_real(das, "DA-ID"), None) is not None


def _missing(row, required):
    """The required columns this row leaves empty, in the stated order. A list
    cell counts as empty when it names nothing, whitespace included."""
    return [c for c in required if not refs(row.get(c))]


def _assumption_row(did, row, crossings):
    """One assumption's own failures: each empty required cell, a status or a
    standing outside its vocabulary, a landing crossing the frame does not
    declare."""
    out = [
        "assumption {} has no {} — an assumption states where its outcome lands, "
        "what it assumes, when it holds, the obstacle under which it fails, its "
        "maturity and its validity".format(did, column)
        for column in _missing(row, DA_REQUIRED)
    ]
    status, standing = _cell(row, "Status"), _cell(row, "Standing")
    if status and status not in STATUS_VALUES:
        out.append(
            "assumption {} Status={!r} is outside the spine's closed vocabulary "
            "({})".format(did, status, " | ".join(sorted(STATUS_VALUES)))
        )
    if standing and standing not in STANDING_VALUES:
        out.append(
            "assumption {} Standing={!r} is outside its closed vocabulary ({})".format(
                did, standing, " | ".join(STANDING_VALUES)
            )
        )
    out += [
        "assumption {} EffectAt names {}, which is not a crossing the frame "
        "declares".format(did, bid)
        for bid in refs(row.get("EffectAt"))
        if bid not in crossings
    ]
    return out


def assumption_row_findings(das, bifs):
    """SR-191's row rule, as failures naming the row and the cell.

    An assumption missing a `DA_REQUIRED` cell, carrying a `Status` outside the
    spine's closed vocabulary or a `Standing` outside `STANDING_VALUES`, or
    landing (`EffectAt`) on a crossing the frame does not declare, fails. The
    caller joins these to the frame class, which fails wherever the frame check
    runs rather than only under `--strict-schema` (the Impl rung alone).

    VACUOUS when the frame declares no crossing, since an assumption's outcome
    has nowhere to land, and for the template's `-000` example rows.

    Implements: SR-191, LLR-219
    """
    if not bifs:
        return []
    crossings = {r["B-ID"] for r in bifs}
    return [
        f
        for did, row in _real(das, "DA-ID")
        for f in _assumption_row(did, row, crossings)
    ]


def _surrogate_row(sid, row, entities):
    """One surrogate's own failures: each empty required cell, a status outside
    the vocabulary, an emulated party that is not a declared entity."""
    out = [
        "surrogate {} has no {} — a surrogate names itself, the outside parties "
        "it answers for, what it is and its maturity".format(sid, column)
        for column in _missing(row, SUR_REQUIRED)
    ]
    status = _cell(row, "Status")
    if status and status not in STATUS_VALUES:
        out.append(
            "surrogate {} Status={!r} is outside the spine's closed vocabulary "
            "({})".format(sid, status, " | ".join(sorted(STATUS_VALUES)))
        )
    out += [
        "surrogate {} Emulates names {}, which is not an entity the frame "
        "declares — only an outside party (EXT-###) is emulated, never a "
        "component or an interface".format(sid, party)
        for party in refs(row.get("Emulates"))
        if party not in entities
    ]
    return out


def _fidelity(did, row, surrogates, landing):
    """One fidelity assumption's failures: it names exactly one declared
    surrogate, and lands on a crossing of a party that surrogate emulates."""
    named = refs(row.get("RealizedBy"))
    if len(named) > 1:
        return [
            "assumption {} RealizedBy names {} surrogates ({}) — a fidelity "
            "assumption states the match of exactly one".format(
                did, len(named), ", ".join(named)
            )
        ]
    (sid,) = named
    if sid not in surrogates:
        return [
            "assumption {} RealizedBy names {}, which is not a declared "
            "surrogate".format(did, sid)
        ]
    emulated = set(refs(surrogates[sid].get("Emulates")))
    parties = {landing.get(bid) for bid in refs(row.get("EffectAt"))}
    if parties & emulated:
        return []
    return [
        "assumption {} lands on no crossing of a party its surrogate {} emulates "
        "({}) — a stand-in's fidelity is a claim about the party it answers "
        "for".format(did, sid, ", ".join(sorted(emulated)) or "none")
    ]


def surrogate_findings(surs, das, exts, bifs):
    """SR-192's surrogate rules, as `(failures, advisories)`.

    FAILURES: a surrogate missing a `SUR_REQUIRED` cell (an empty `Emulates`
    list included), carrying a status outside the spine's closed vocabulary, or
    emulating anything but a declared entity (`exts`) — a component or an
    interface id does not resolve there, since only an outside party is
    emulated. And each FIDELITY assumption — one naming a surrogate in
    `RealizedBy` — must name exactly one declared surrogate and land (`EffectAt`)
    on a crossing (`bifs`) whose entity that surrogate emulates.

    ADVISORIES: a surrogate no assumption names, one line each. A stand-in
    whose fidelity nothing states is unexamined evidence, not a wrong row.

    Implements: SR-192, LLR-221
    """
    entities = {r["EXT-ID"] for r in exts}
    landing = {r["B-ID"]: _cell(r, "Entity") for r in bifs}
    surrogates = dict(_real(surs, "SUR-ID"))
    failures = [
        f for sid, row in surrogates.items() for f in _surrogate_row(sid, row, entities)
    ]
    named = set()
    for did, row in _real(das, "DA-ID"):
        if refs(row.get("RealizedBy")):
            named.update(refs(row.get("RealizedBy")))
            failures += _fidelity(did, row, surrogates, landing)
    advisories = [
        "surrogate {} is named by no assumption's RealizedBy — nothing states how "
        "faithfully it stands in for {}".format(
            sid, _cell(row, "Emulates") or "its parties"
        )
        for sid, row in surrogates.items()
        if sid not in named
    ]
    return failures, advisories


def da_citing_srs(srs):
    """`{assumption id: [requirement ids]}`: each assumption a requirement's
    `DA-Refs` cites, and the requirements citing it, in row order.

    THE ONE DERIVATION of an assumption's citing requirements. Its served needs
    are read from here, through those requirements' `SN-Refs`, and nothing
    records needs on the assumption: each requirement keeps its own need link,
    because one seam serves several arguments, and needs inherited through a
    shared assumption would hand a requirement the needs of every other
    requirement that merely relies on the same claim.

    Implements: SR-193, LLR-223
    """
    out = {}
    for sid, row in _real(srs, "SR-ID"):
        for did in refs(row.get("DA-Refs")):
            citing = out.setdefault(did, [])
            if sid not in citing:
                citing.append(sid)
    return out


def _classify(row, declared, requirements):
    """Return one requirement's class and every reference advisory fact.

    This is the one parse of the classification cells. Callers either expose
    the class or format these facts; they do not re-derive reference state.
    """
    cited = refs(row.get("DA-Refs"))
    siblings = refs(row.get("Delivered-With"))
    waiver = _cell(row, "Coincident")
    undeclared = [did for did in cited if did not in declared]
    unknown_siblings = [sid for sid in siblings if sid not in requirements]
    row_needs = set(refs(row.get("SN-Refs")))
    disjoint_siblings = [
        sid
        for sid in siblings
        if sid in requirements
        and row_needs.isdisjoint(refs(requirements[sid].get("SN-Refs")))
    ]
    if undeclared or unknown_siblings:
        cls = None
    elif any(sid not in disjoint_siblings for sid in siblings):
        cls = "joint"
    elif cited and waiver:
        cls = "both"
    elif cited:
        cls = "bridged"
    else:
        cls = "coincident" if waiver else "unclassified"
    return cls, undeclared, unknown_siblings, disjoint_siblings


def classify_srs(srs, das):
    """`{requirement id: class}` over `SR_CLASSES`: how each requirement relates
    to the assumptions under it. A requirement citing an undeclared assumption
    is left out, because `sr_classification_advisories` fails it instead. An
    empty or whitespace-only `DA-Refs` counts as no citation.

    `{}` when the registry holds no real assumption: the tier is not adopted.
    The data read beside `sr_classification_advisories`, which reports from the
    same per-row classification (`_classify`).
    """
    if not _adopted(das):
        return {}
    declared = dict(_real(das, "DA-ID"))
    requirements = dict(_real(srs, "SR-ID"))
    return {
        sid: cls
        for sid, row in requirements.items()
        if (cls := _classify(row, declared, requirements)[0])
    }


def sr_classification_advisories(srs, das):
    """SR-193's classification, as `(failures, advisories)`.

    A requirement naming declared siblings with a shared need is joint; it may
    also cite assumptions of its own. A joint row carrying a `Coincident`
    waiver, a declared sibling sharing no need, an unclassified row and the
    existing assumption-plus-waiver `both` class are advisories. An undeclared
    assumption or sibling is a FAILURE naming the requirement. The requirement's
    `SN-Refs` are read only to compare sibling scope and are never changed.

    VACUOUS until the registry holds a real assumption row.

    Implements: SR-193, LLR-223
    """
    if not _adopted(das):
        return [], []
    declared = dict(_real(das, "DA-ID"))
    requirements = dict(_real(srs, "SR-ID"))
    failures, advisories = [], []
    for sid, row in requirements.items():
        cls, undeclared, unknown_siblings, disjoint_siblings = _classify(
            row, declared, requirements
        )
        failures += [
            f"SR {sid} DA-Refs names {did}, which is not a declared assumption"
            for did in undeclared
        ]
        failures += [
            f"SR {sid} Delivered-With names {sibling}, which is not a declared SR"
            for sibling in unknown_siblings
        ]
        advisories += [
            f"SR {sid} names sibling {sibling} in Delivered-With, but the two "
            f"requirements share no need; keep only siblings that jointly deliver "
            f"one of {sid}'s needs"
            for sibling in disjoint_siblings
        ]
        if cls == "unclassified":
            advisories.append(
                f"SR {sid} is unclassified: it cites no assumption in DA-Refs, "
                "names no sibling requirement in Delivered-With, and records no "
                "Coincident waiver saying why its own specification alone delivers "
                "its needs"
            )
        elif cls == "both":
            advisories.append(
                f"SR {sid} cites assumptions in DA-Refs AND records a Coincident "
                "waiver — the two contradict each other; keep the one that is true"
            )
        elif cls == "joint" and _cell(row, "Coincident"):
            advisories.append(
                f"SR {sid} names siblings in Delivered-With AND records a Coincident "
                "waiver — joint delivery contradicts the claim that its own "
                "specification alone delivers its needs; keep the one that is true"
            )
    return failures, advisories


def sr_form_findings(srs):
    """SR-194's form rule, as `(failures, advisories)`, over every requirement
    it is handed.

    A `Form` outside `FORM_VALUES` is a FAILURE naming the row; the caller
    joins it to the always-on integrity class. A requirement declaring no form
    is an ADVISORY naming it: the omission stays visible without failing, where
    a default would hide a missing interface behind a legitimate exception.

    Whether the question is asked at all is the composer's: the tier asks no
    requirement for a form until the registry holds a real assumption row, so
    a project that never adopts the tier is never asked
    (`assumption_tier_findings`).

    Implements: SR-194, LLR-224
    """
    failures, advisories = [], []
    allowed = " | ".join(FORM_VALUES)
    for sid, row in _real(srs, "SR-ID"):
        form = _cell(row, "Form")
        if not form:
            advisories.append(
                "SR {} declares no Form ({}) — say whether it is met at an "
                "interface, rests on an assumption or is a property of the whole "
                "system".format(sid, allowed)
            )
        elif form not in FORM_VALUES:
            failures.append(
                "SR {} Form={!r} is not one of the three forms ({})".format(
                    sid, form, allowed
                )
            )
    return failures, advisories


def uncited_assumption_advisories(das, srs):
    """SR-196, the first half: one advisory per assumption no requirement's
    `DA-Refs` cites. Drafted and approved rows are read alike, since an
    assumption is often written before the requirement that will cite it.

    Implements: SR-196, LLR-228
    """
    cited = da_citing_srs(srs)
    return [
        "assumption {} is cited by no requirement's DA-Refs — no argument relies "
        "on it yet".format(did)
        for did, _row in _real(das, "DA-ID")
        if did not in cited
    ]


def no_falsifier_advisories(das):
    """SR-196, the second half: one advisory per assumption declaring no
    `Falsifier`, the observable signal that would show it false. Drafted and
    approved rows are read alike.

    Implements: SR-196, LLR-228
    """
    return [
        "assumption {} declares no Falsifier — no falsifying signal says which "
        "observation would show it false, so it cannot be tested".format(did)
        for did, row in _real(das, "DA-ID")
        if not _cell(row, "Falsifier")
    ]


def assumption_tier_findings(srs, das, surs, exts, bifs):
    """The whole tier as `trace.analyze` composes it: `(frame, integrity,
    advisories)`, each list bound for its own class.

    FRAME: the assumption rows' own failures and a requirement's citation of an
    undeclared assumption, the tier's reference rules beside the frame's own.
    INTEGRITY, the always-on floor: every surrogate failure and a form outside
    the three. ADVISORIES, the warn pipe: an unnamed surrogate, an unclassified
    or doubly classified requirement, a requirement with no form, an uncited
    assumption and one with no falsifier.

    Three empty lists when the frame declares no crossing: an assumption's
    outcome has nowhere to land, so the tier does not apply (SR-191). And no
    requirement is asked for a form until the registry holds a real assumption
    row (SR-194): every project is scaffolded the blank form, so the file
    existing is not adoption.
    """
    if not bifs:
        return [], [], []
    sur_failures, sur_advisories = surrogate_findings(surs, das, exts, bifs)
    cls_failures, cls_advisories = sr_classification_advisories(srs, das)
    form_failures, form_advisories = (
        sr_form_findings(srs) if _adopted(das) else ([], [])
    )
    frame = assumption_row_findings(das, bifs) + cls_failures
    advisories = (
        sur_advisories
        + cls_advisories
        + form_advisories
        + uncited_assumption_advisories(das, srs)
        + no_falsifier_advisories(das)
    )
    return frame, sur_failures + form_failures, advisories


# --- reach: where an assumption lands, and where a need met in operation does --
# A crossing REACHES a need when it belongs to the party of one of the need's
# agreed stakeholders, or to a party the frame records as mediating for that
# party (`Mediates` on an entity, judged by `frame_rules.mediation_findings`).
# Two reports read that relation. The reach check (SR-195) holds each cited
# assumption to the needs it serves, need by need, so an assumption shared by
# two needs cannot reach one and silently miss the other. The need-frame gap
# (SR-188) asks the frame itself whether a need whose stakeholder is a party in
# operation has anything answering it at an operation crossing. Both ride the
# warn pipe: each names a gap in an argument, not a malformed row.

# The system in use, the member of `kitlib.spine.SYSTEM_VALUES` a need met in
# operation lands in (the other is the system that builds and delivers it).
_OPERATION = "operation"


def _agreed_parties(stks):
    """`{stakeholder id: party}` for each agreed stakeholder declaring a party:
    `Approved`, or `Founded`, which reads above it on the one ladder. A
    stakeholder still in draft has not been agreed as anyone's, so its party is
    never read."""
    return {
        sid: _cell(row, "Party")
        for sid, row in _real(stks, "STK-ID")
        if _cell(row, "Party") and (is_approved(row) or is_founded(row))
    }


def reaching_parties(needs, stks, exts):
    """`{need id: set of entity ids}`: the parties a crossing must belong to in
    order to reach each need.

    A need's parties are those of its agreed stakeholders (`stakeholder_refs`),
    plus every entity whose `Mediates` names one of them: a development session
    reaches its operator because it carries the operator's writes in and shows
    them the system's verdicts. Mediation is one step, never a chain. A need
    whose agreed stakeholders declare no party maps to an empty set, which is
    how the reach check tells an unreachable need from an undeclared one.
    `needs` are `spine_carrier.load_needs`' rows, lower-case keys and the id
    under `id`.

    Implements: SR-195, LLR-227
    """
    agreed = _agreed_parties(stks)
    mediators = {}
    for eid, row in _real(exts, "EXT-ID"):
        target = _cell(row, "Mediates")
        if target and target != eid:
            mediators.setdefault(target, set()).add(eid)
    out = {}
    for nid, need in _real(needs, "id"):
        direct = {agreed[s] for s in refs(need.get("stakeholder_refs")) if s in agreed}
        out[nid] = direct.union(*(mediators.get(p, set()) for p in direct))
    return out


def _served_needs(srs, declared):
    """`{assumption id: [need ids]}`: each cited assumption's served needs, read
    through `da_citing_srs` and the citing requirements' `SN-Refs`, in order and
    once each. A need `declared` does not hold is left out: a dangling `SN-Refs`
    is the orphan rules' finding, and it has no stakeholders to reach."""
    sn_of = {sid: refs(row.get("SN-Refs")) for sid, row in _real(srs, "SR-ID")}
    out = {}
    for did, citing in da_citing_srs(srs).items():
        served = out.setdefault(did, [])
        for nid in (n for sid in citing for n in sn_of[sid]):
            if nid in declared and nid not in served:
                served.append(nid)
    return out


def _emulated(row, surrogates):
    """`(judged, parties)`: whether the reach check judges this assumption, and
    the parties a fidelity assumption is judged against.

    An assumption naming no surrogate is judged against its needs' parties
    (`(True, None)`). A fidelity assumption whose `RealizedBy` resolves to
    exactly one declared surrogate is judged against the parties that surrogate
    emulates. One naming an undeclared surrogate, or several, is NOT judged
    (`(False, None)`): that reference is `surrogate_findings`' failure, and
    with no resolved stand-in there is no emulated party to judge against, so
    a reach report on top would only restate the broken reference."""
    named = refs(row.get("RealizedBy"))
    if not named:
        return True, None
    if len(named) != 1 or named[0] not in surrogates:
        return False, None
    return True, set(refs(surrogates[named[0]].get("Emulates")))


def _unreached_needs(did, landing, entity_of, reach, fidelity):
    """One line per served need no landing crossing reaches; a need with no
    party at all is named unreachable, since no landing could reach it."""
    whose = (
        "a party its surrogate emulates"
        if fidelity
        else "a party of the need's approved stakeholders or one mediating for it"
    )
    out = []
    for nid, parties in reach.items():
        if not parties and not fidelity:
            out.append(
                "assumption {} serves need {}, which is unreachable: no approved "
                "stakeholder of it declares a party a crossing could belong "
                "to".format(did, nid)
            )
        elif not any(entity_of[bid] in parties for bid in landing):
            out.append(
                "assumption {} serves need {}, but none of its landing crossings "
                "belongs to {}".format(did, nid, whose)
            )
    return out


def _idle_landings(did, landing, entity_of, reach, fidelity):
    """One line per landing crossing that reaches none of the served needs."""
    what = (
        "belongs to no party its surrogate emulates"
        if fidelity
        else "reaches none of the needs it serves ({})".format(", ".join(reach))
    )
    return [
        "assumption {} lands on {} ({}), which {}".format(
            did, bid, entity_of[bid] or "no entity", what
        )
        for bid in landing
        if not any(entity_of[bid] in parties for parties in reach.values())
    ]


def assumption_reach_advisories(das, srs, needs, stks, exts, bifs, surs):
    """SR-195's reach check, need by need, as advisories: every line
    `reach_gaps` holds, in assumption order.

    Implements: SR-195, LLR-227
    """
    gaps = reach_gaps(das, srs, needs, stks, exts, bifs, surs)
    return [line for lines in gaps.values() for line in lines]


def reach_gaps(das, srs, needs, stks, exts, bifs, surs):
    """SR-195's reach check, need by need, as `{assumption id: [lines]}` for
    each assumption the check reports; the advisories and the boundary gate's
    "does not reach" condition read this one derivation.

    For each assumption at least one requirement cites, its SERVED NEEDS are
    derived through `da_citing_srs` and the citing requirements' `SN-Refs`, and
    never read from the assumption. Every (served need, landing crossing) pair
    is evaluated against `reaching_parties`: a served need no landing crossing
    reaches is one advisory naming the assumption and the need, and a landing
    crossing reaching none of the served needs is one naming the assumption and
    the crossing. A served need none of whose approved stakeholders declares a
    party is named unreachable.

    A FIDELITY assumption, one naming a surrogate in `RealizedBy`, is judged
    against the parties its surrogate emulates instead of the needs' parties:
    its claim is that a stand-in matches an outside party, not that a
    stakeholder's outcome lands. An uncited assumption is not judged here
    (`uncited_assumption_advisories` reports it), nor is a fidelity assumption
    whose `RealizedBy` does not resolve to exactly one declared surrogate
    (`surrogate_findings` fails it), and a landing on an undeclared crossing is
    left to `assumption_row_findings`, which fails it.
    Silent when the frame declares no crossing (SR-191's applies-when).

    Implements: SR-195, LLR-227
    """
    if not bifs:
        return {}
    entity_of = {r["B-ID"]: _cell(r, "Entity") for r in bifs}
    parties = reaching_parties(needs, stks, exts)
    served_by = _served_needs(srs, parties)
    surrogates = dict(_real(surs, "SUR-ID"))
    out = {}
    for did, row in _real(das, "DA-ID"):
        served = served_by.get(did)
        judged, emulated = _emulated(row, surrogates)
        if not served or not judged:
            continue
        landing = [bid for bid in refs(row.get("EffectAt")) if bid in entity_of]
        fidelity = emulated is not None
        reach = {nid: emulated if fidelity else parties[nid] for nid in served}
        lines = _unreached_needs(did, landing, entity_of, reach, fidelity)
        lines += _idle_landings(did, landing, entity_of, reach, fidelity)
        if lines:
            out[did] = lines
    return out


def _answering_srs(srs):
    """`{need id: [requirement rows]}`: the requirements naming each need in
    their `SN-Refs`, in row order."""
    out = {}
    for _sid, row in _real(srs, "SR-ID"):
        for nid in refs(row.get("SN-Refs")):
            out.setdefault(nid, []).append(row)
    return out


def _reaches_operation(rows, operation, lands):
    """Whether any of these requirements names an operation crossing in its
    `Boundary-Refs`, or cites in `DA-Refs` an assumption landing on one."""
    for row in rows:
        if operation & set(refs(row.get("Boundary-Refs"))):
            return True
        if any(operation & lands.get(did, set()) for did in refs(row.get("DA-Refs"))):
            return True
    return False


def need_frame_gap_advisories(needs, stks, srs, bifs, das):
    """SR-188's need-frame gap, as advisories: one per need met in operation
    that nothing answering it reaches an operation crossing for.

    A need is IN SCOPE when the party of one of its approved stakeholders is
    itself the entity of an operation crossing. A party that only mediates for
    such an entity does not bring the need into scope: the rule reads the
    stakeholder's own party, as SR-188 states it. An in-scope need is reported,
    once, naming it and those stakeholders, when none of the requirements
    naming it in `SN-Refs` names an operation crossing in `Boundary-Refs` and
    none of the assumptions they cite in `DA-Refs` lands on one. That is the
    one place the gap shows: a need about what a person experiences while the
    system runs, answered only at the crossings of the system that builds and
    delivers it, still passes every reference check. A need no requirement
    names meets the condition as written and is reported too: nothing answers
    it at an operation crossing either.

    Only approved stakeholders are read (`Approved`, or `Founded` above it).
    VACUOUS with no frame, no stakeholder list or no crossing declaring the
    operation system.

    Implements: SR-188, LLR-214
    """
    operation = {
        r["B-ID"]: _cell(r, "Entity") for r in bifs if _cell(r, "System") == _OPERATION
    }
    agreed = _agreed_parties(stks)
    if not operation or not agreed:
        return []
    crossings, in_operation = set(operation), set(operation.values())
    lands = {did: set(refs(row.get("EffectAt"))) for did, row in _real(das, "DA-ID")}
    answering = _answering_srs(srs)
    out = []
    for nid, need in _real(needs, "id"):
        owners = [
            s
            for s in refs(need.get("stakeholder_refs"))
            if agreed.get(s) in in_operation
        ]
        if owners and not _reaches_operation(answering.get(nid, []), crossings, lands):
            out.append(
                "need {} is met in operation by {}, but none of its requirements "
                "names an operation crossing and none of the assumptions they cite "
                "lands on one — the frame has no crossing where this outcome "
                "lands".format(
                    nid, ", ".join("{} ({})".format(s, agreed[s]) for s in owners)
                )
            )
    return out


def is_observation_tc(tc):
    """Whether a test case is an OBSERVATION: a judgment the harness cannot
    rerun, recorded as such by its `Automated` cell reading No.

    THE ONE MARKER, and deliberately not the `Level` or the requirement's
    `Verification`: those cells disagree across rows (a manual inspection is
    filed at more than one level), while every case the harness cannot rerun
    says so in `Automated`. So manual and demonstration cases are observations
    too, and declare how long their results hold.

    Implements: SR-198, LLR-233
    """
    return _cell(tc, "Automated").lower() == "no"


def _whole_at_least(value, floor):
    """Whether a cell reads as a whole number of at least `floor`."""
    return bool(_WHOLE.fullmatch(value)) and int(value) >= floor


def _present(row, column):
    """Whether a cell holds anything, whitespace included.

    THE CARRIER RULE: an absent key IS an empty cell (`kitlib.spine`). The TOML
    carrier refuses an explicit `""` at load and the migration drops empty
    cells, so an empty cell here is an absent one, on every carrier alike;
    reading key presence instead would make a legacy carrier's empty column
    declare the optional sampling model on every row. A whitespace-only cell
    was written and says nothing, so it is present, and the rule reading it
    judges it blank."""
    return (row.get(column) or "") != ""


def _model_failures(tid, row):
    """The sampling model's failures for one case: each malformed cell, and
    one of the two cells without the other."""
    out = []
    size, rule = _cell(row, "SampleSize"), _cell(row, "AcceptanceRule")
    if _present(row, "SampleSize") and not _whole_at_least(size, 1):
        out.append(
            "TC {} SampleSize={!r} is not a whole number of at least 1 — a "
            "sampling model's size counts the samples judged".format(tid, size)
        )
    if _present(row, "AcceptanceRule") and not rule:
        out.append(
            "TC {} AcceptanceRule is empty — a sampling model states what a "
            "passing sample is".format(tid)
        )
    if _present(row, "SampleSize") != _present(row, "AcceptanceRule"):
        has, lacks = ("SampleSize", "AcceptanceRule")
        if not _present(row, "SampleSize"):
            has, lacks = lacks, has
        out.append(
            "TC {} declares {} without {} — a sampling model is both cells or "
            "neither".format(tid, has, lacks)
        )
    return out


def _declaration_failures(tid, row):
    """One case's malformed declaration cells: a lifetime that is not a whole
    number of days at the floor, a policy outside the pair, and the model."""
    out = []
    max_age, sampling = _cell(row, "MaxAge"), _cell(row, "Sampling")
    if max_age and not _whole_at_least(max_age, MAX_AGE_FLOOR_DAYS):
        out.append(
            "TC {} MaxAge={!r} is not a whole number of days of at least {} — "
            "a judgment is not demanded more often than it can honestly be "
            "taken".format(tid, max_age, MAX_AGE_FLOOR_DAYS)
        )
    if sampling and sampling not in SAMPLING_VALUES:
        out.append(
            "TC {} Sampling={!r} is outside its closed vocabulary ({})".format(
                tid, sampling, " | ".join(SAMPLING_VALUES)
            )
        )
    return out + _escape_failures(tid, row) + _model_failures(tid, row)


def input_path(name):
    """The declared input `name` as the repository-relative path it names, in
    forward slashes with `.` and inner `..` resolved lexically
    (`docs/../src/a.txt` is `src/a.txt`), or None when that path is absolute,
    drive-qualified or climbs out of the repository.

    The one spelling every reader of a declared input resolves it by, so the
    writer's checkout and a checkpoint's commit read the same file for the
    same name. Symbolic links are not resolved here, since this reads no file:
    each reader resolves them against the tree it digests.
    """
    text = str(name).strip().replace("\\", "/")
    if text.startswith("/") or _DRIVE.match(text):
        return None
    normal = posixpath.normpath(text) if text else ""
    if normal == ".." or normal.startswith("../"):
        return None
    return "" if normal == "." else normal


def input_escape(name):
    """Why the declared input `name` names a path outside the repository, or
    None when it names a path inside it (or a registry row id).

    A result is trusted only for what it judged, and what it judged has to be
    what the repository holds: the writer digests the checkout and a
    checkpoint digests a commit, and a path reaching outside either would
    make the digest read a file no commit carries, which moves without any
    merge and cannot be checked out at the revision judged. So an absolute
    path, a drive-qualified one and one that still climbs out with `..` once
    normalized (`input_path`) are refused here, in either separator style,
    and this one rule is what the declaration check, the writer and the
    checkpoint all apply. A `..` that stays inside is no escape.

    Implements: SR-198, LLR-233
    """
    text = str(name).strip().replace("\\", "/")
    if text.startswith("/") or _DRIVE.match(text):
        return "an absolute path"
    if input_path(name) is None:
        return "a path climbing out of the repository with `..`"
    return None


def _escape_failures(tid, row):
    """One failure per declared input naming a path outside the repository."""
    out = []
    for name in refs(row.get("Inputs")):
        why = input_escape(name)
        if why:
            out.append(
                "TC {} Inputs names `{}`, {} — a declared input is read inside "
                "the repository only, so a result's digest is of committed "
                "bytes".format(tid, name, why)
            )
    return out


def _omissions(tid, row):
    """One observation case's omitted declarations, one advisory each."""
    wanted = [("Inputs", "the inputs its judgment reads"), ("MaxAge", "its lifetime")]
    if refs(row.get("Assumption-Refs")):
        wanted.append(("Sampling", "its sampling policy, sampled | monitored"))
    return [
        "TC {} is an observation test case declaring no {} ({}) — declare it "
        "so its result can go stale".format(tid, column, what)
        for column, what in wanted
        if not refs(row.get(column))
    ]


def observation_tc_findings(tcs):
    """SR-198's declaration rules, as `(failures, advisories)`, each naming the
    row.

    ADVISORIES: an observation case (`is_observation_tc`) omitting `Inputs`,
    `MaxAge`, or, when it cites assumptions, `Sampling`, one line per omission.
    Reported rather than refused, so observation cases written before these
    cells existed keep passing. And an AUTOMATED case carrying any
    `OBSERVATION_CELLS` cell, one line per cell: the harness reruns it, so the
    declaration says nothing about it.

    FAILURES, bound for the always-on integrity floor: a `MaxAge` that is not a
    whole number of days of at least `MAX_AGE_FLOOR_DAYS`, an `Inputs` entry
    naming a path outside the repository (`input_escape`), a `Sampling` outside
    `SAMPLING_VALUES`, a `SampleSize` that is not a whole number of at least
    one, an `AcceptanceRule` of whitespace alone, and one of those two model
    cells without the other, on an observation case. An empty cell is an
    absent one (the carrier rule, `_present`). An automated case's
    stray cell is the advisory above and nothing more: its values declare
    nothing, so judging them would fail a row for a cell it should not carry.

    Whether a sampling model is adequate for its claim is judged when the case
    is approved, never here. The template's `-000` row is never judged.

    Implements: SR-198, LLR-233
    """
    failures, advisories = [], []
    for tid, row in _real(tcs, "TC-ID"):
        if is_observation_tc(row):
            failures += _declaration_failures(tid, row)
            advisories += _omissions(tid, row)
            continue
        advisories += [
            "TC {} is automated but declares {} — only an observation test case "
            "declares what it reads, how long its result holds and how it "
            "samples".format(tid, column)
            for column in OBSERVATION_CELLS
            if _present(row, column)
        ]
    return failures, advisories


def sampling_model_declared(tc):
    """Whether a case declares a usable SAMPLING MODEL: it is `sampled`, and its
    sample size (a whole number of at least one) and its acceptance rule (not
    empty) are both valid. A sampled result supports a positive claim only under
    a stated model; a monitored case, or a sampled one with neither cell, has
    declared none.

    Implements: SR-198, LLR-233
    """
    return (
        _cell(tc, "Sampling") == "sampled"
        and _whole_at_least(_cell(tc, "SampleSize"), 1)
        and bool(_cell(tc, "AcceptanceRule"))
    )


def _crossings(row):
    """The boundary crossings an interface row realizes: its from- and
    to-external tie-backs. Empty for an internal seam."""
    return refs(row.get("InterfaceFromExternal")) + refs(row.get("InterfaceToExternal"))


def interface_bridge_findings(ifs, das):
    """SR-211's interface rule, as `(failures, advisories)`.

    Reads only BOUNDARY interfaces, those with a from- or to-external tie-back:
    an internal seam realizes no crossing, so no outcome hangs on its reading.
    A boundary interface naming declared assumptions in `BridgedBy` is bridged,
    and one recording in `Coincident` why its reading is the outcome is
    coincident; neither is reported.

    FAILURES: a `BridgedBy` entry naming an assumption the registry does not
    declare, naming the interface and the id; the caller joins it to the
    interface class, which fails `--strict`. ADVISORIES: a boundary interface
    with neither cell, one line naming it, on the warn pipe.

    VACUOUS until the registry holds a real assumption row, the requirement
    side's adoption rule (`_adopted`): until then no seam can be bridged, so
    every boundary seam would be a line in a worklist the project never took
    on, and every assumption a seam names is necessarily undeclared.

    No requirement reference is read or asked for: the requirement a seam
    answers stays derived through its owner, and stating it on the row would
    give that relation a second home.

    Implements: SR-211, LLR-250
    """
    if not _adopted(das):
        return [], []
    declared = dict(_real(das, "DA-ID"))
    failures, advisories = [], []
    for iid, row in _real(ifs, "IF-ID"):
        crossings = _crossings(row)
        if not crossings:
            continue
        bridging = refs(row.get("BridgedBy"))
        failures += [
            "IF {} BridgedBy names {}, which is not a declared assumption".format(
                iid, did
            )
            for did in bridging
            if did not in declared
        ]
        if not bridging and not _cell(row, "Coincident"):
            advisories.append(
                "IF {} realizes boundary crossing {} but names no assumption in "
                "BridgedBy carrying its reading to an outcome, and records no "
                "Coincident waiver saying why its reading is the outcome".format(
                    iid, ", ".join(crossings)
                )
            )
    return failures, advisories


def obstacle_hat_findings(das, hat_names):
    """SR-214's provenance rule: each perspective an assumption's
    `ObstacleHats` names is a declared hat, as failures naming the assumption
    and the name. The caller joins them to the dangling-hat class, which fails
    `--strict`.

    `hat_names` is the roster's names as the checker read them, or an empty
    set when the project has no roster; every named perspective is then
    undeclared, since a cell pointing into a roster that does not exist points
    at nothing. An empty cell is valid and produces nothing: it reads as NOT
    RECORDED, never as "no perspective applied". The cell is kept apart from
    `Hat-Refs`, which records attribution, because this one records which
    perspective's question raised the obstacle.

    Implements: SR-214, LLR-252
    """
    return [
        "assumption {} ObstacleHats names {}, which is not a perspective the "
        "hats roster declares".format(did, name)
        for did, row in _real(das, "DA-ID")
        for name in refs(row.get("ObstacleHats"))
        if name not in hat_names
    ]


# --- OBSERVATION RESULTS, AND WHAT THEY CAN FALSIFY (SR-199, SR-201, SR-202) --
# A test case says what a test IS; its results say what it last FOUND. The
# observation half of those results is one file per result
# (`kitlib.observation`). The rules below judge those files against the cases
# they name, list what relies on an assumption shown false, and read whether an
# accepted risk still covers one. No rule here derives how well an assumption
# holds: an assumption carries no evidence level (owner ruling 2026-10-02),
# since a passed observation proves nothing beyond its sample. Every input that
# lives on disk or in git arrives already read: `record_observation.evidence_inputs`
# reads the records and each accepted risk's act, once, and `trace.main` hands
# them here.

# AN ACCEPTED RISK'S READING (SR-202). `covered`: the risk accepted for the
# assumption still stands. `unproven`: the risk has reopened. No result makes
# a risk moot.
RISK_COVERED = "covered"
RISK_UNPROVEN = "unproven"

# An assumption's cells the risk's acceptance is NOT bound to: its id, its
# maturity (an act moves it) and the accepted risk itself.
_UNBOUND_CELLS = frozenset({"DA-ID", "Status", "AcceptedRisk"})
# A served need's cells the acceptance IS bound to, in the needs' own keys.
_BOUND_NEED_CELLS = ("need", "acceptance")


def _unique(ids):
    """`ids` in first-seen order, each once."""
    return list(dict.fromkeys(ids))


def _citing_cases(did, tcs):
    """The ids of the cases naming `did` in `Assumption-Refs`, in row order."""
    return [
        tid for tid, tc in _real(tcs, "TC-ID") if did in refs(tc.get("Assumption-Refs"))
    ]


def record_policy_problem(tid, tc, observed_at, expires):
    """Why a whole record's CASE does not allow it, or None: the case is not
    declared, is automated, declares no usable lifetime, or the record expires
    later than that lifetime after its observation.

    The one statement of a record's policy, so the writer's refusal and the
    checker's finding cannot disagree. A case declaring no lifetime allows no
    expiry at all: its omission is only reported on the case, but a record for
    it could then claim any lifetime it liked. `tc` is the case's row or None;
    both instants are canonical UTC, as a parsed record carries them.
    """
    if tc is None:
        return "{} is not a declared test case".format(tid)
    if not is_observation_tc(tc):
        return (
            "{} is automated: its results are the harness's evidence record, "
            "not an observation".format(tid)
        )
    max_age = _cell(tc, "MaxAge")
    if not _whole_at_least(max_age, MAX_AGE_FLOOR_DAYS):
        return "{} declares no usable MaxAge, so no expiry is allowed".format(tid)
    limit = parse_utc(observed_at) + datetime.timedelta(days=int(max_age))
    if parse_utc(expires) > limit:
        return "expires {}, later than {}'s {}-day lifetime allows ({})".format(
            expires, tid, max_age, format_utc(limit)
        )
    return None


def observation_record_findings(records, raw_files, tcs):
    """SR-199's check of the records found on disk, as failures naming the file.

    A file that is not a whole record (`kitlib.observation.problem`: not TOML,
    a missing field, a non-canonical instant, an expiry before the observation,
    an empty provenance, a name other than its case's and instant's) fails
    with its reason; so does a whole record whose
    case does not allow it (`record_policy_problem`). The caller joins these to
    the always-on integrity floor, where the writer's own refusal already
    stands: a record that reached the repository some other way is caught
    where the commit lands. `raw_files` is `{name: text}` of every file the
    reader read, and never holds a leading-dot name.

    Implements: SR-199, LLR-236
    """
    cases = dict(_real(tcs, "TC-ID"))
    out = []
    for name, text in sorted(raw_files.items()):
        why = record_problem(text, name)
        if why:
            out.append(
                "observation record {} does not parse as a record: {}".format(name, why)
            )
    for rec in sorted(records, key=lambda r: r.get("file", "")):
        why = record_policy_problem(
            rec["tc"], cases.get(rec["tc"]), rec["observed_at"], rec["expires"]
        )
        if why:
            out.append("observation record {}: {}".format(rec.get("file"), why))
    return out


def falsification_worklist(das, srs, tcs, records, gate=False):
    """SR-201's worklist: one advisory per assumption shown false, listing the
    requirements citing it (`da_citing_srs`), the needs those requirements
    name and the cases naming it in `Assumption-Refs`, each row once.

    An assumption is listed when its `Standing` reads falsified, or when the
    latest record of any case naming it failed: that record is
    falsification evidence and is reported as such, but recording the
    assumption false stays a judgment, so no cell is written. An active
    assumption with no failing latest record is not listed. With the gate that
    relies on assumptions enabled (`gate`), a falsified assumption fails
    through the boundary gate's not-active condition instead, so it is left
    out here rather than counted twice.

    Implements: SR-201, LLR-238
    """
    citing = da_citing_srs(srs)
    requirements = dict(_real(srs, "SR-ID"))
    out = []
    for did, da in _real(das, "DA-ID"):
        falsified = _cell(da, "Standing") == "falsified"
        if falsified and gate:
            continue
        cases = _citing_cases(did, tcs)
        failing = [latest(records, tid) for tid in cases]
        failing = [r for r in failing if r and r.get("outcome") == "fail"]
        if not falsified and not failing:
            continue
        relying = citing.get(did, [])
        needs = _unique(
            n for sid in relying for n in refs(requirements[sid].get("SN-Refs"))
        )
        out.append(
            "assumption {} {} — relied on by {}; serving {}; can be falsified "
            "by {}".format(
                did,
                _falsified_why(da, failing),
                ", ".join(relying) or "no requirement",
                ", ".join(needs) or "no need",
                ", ".join(cases) or "no test case",
            )
        )
    return out


def _falsified_why(da, failing):
    """Why the worklist lists an assumption: its Standing reads falsified, or
    the failing latest records of the cases naming it, its Standing unchanged."""
    if _cell(da, "Standing") == "falsified":
        return "is falsified (its Standing reads falsified)"
    return (
        "has falsification evidence: the latest record {} failed, and "
        "recording it false stays a judgment, so its Standing still "
        "reads {}".format(
            ", ".join(r.get("file") or r["tc"] for r in failing),
            _cell(da, "Standing") or "(unset)",
        )
    )


def _assumption_drift(did, then, now, act):
    """The reopening reasons the assumption's own text gives: each bound cell
    that differs between the acceptance act and now."""
    if then is None:
        return ["assumption {} did not exist at the act {}".format(did, act)]
    cells = sorted((set(then) | set(now)) - _UNBOUND_CELLS)
    return [
        "assumption {}'s {} changed since the act {} accepting its risk".format(
            did, cell, act
        )
        for cell in cells
        if (then.get(cell) or "").strip() != (now.get(cell) or "").strip()
    ]


def _need_drift(did, view, needs, act):
    """The reopening reasons the served needs give: each need the assumption
    served AT THE ACT, derived through that act's requirements, whose need or
    acceptance text differs now, or which is gone."""
    then_srs = {_cell(r, "SR-ID"): r for r in view.get("srs") or ()}
    served = _unique(
        n
        for sid in da_citing_srs(list(then_srs.values())).get(did, [])
        for n in refs(then_srs[sid].get("SN-Refs"))
    )
    then_needs = view.get("needs") or {}
    now_needs = {str(n.get("id") or "").strip(): n for n in needs}
    out = []
    for nid in served:
        then, current = then_needs.get(nid) or {}, now_needs.get(nid)
        if current is None:
            out.append(
                "need {}, served at the act {} accepting {}'s risk, is gone".format(
                    nid, act, did
                )
            )
            continue
        out += [
            "need {}'s {} changed since the act {} accepting {}'s risk".format(
                nid, cell, act, did
            )
            for cell in _BOUND_NEED_CELLS
            if str(then.get(cell) or "").strip() != str(current.get(cell) or "").strip()
        ]
    return out


def _late_failures(did, view, tcs, records, act):
    """The reopening reasons failed samples give: each failing record of a case
    naming the assumption that the act's tree did not hold, which orders it
    after the act by commit ancestry, whatever instant it names."""
    known = set(view.get("known") or ())
    cases = set(_citing_cases(did, tcs))
    return [
        "observation record {} failed after the act {} accepting {}'s risk "
        "(ordered by commit ancestry, not by its timestamp)".format(
            r.get("file"), act, did
        )
        for r in sorted(records, key=lambda r: r.get("file", ""))
        if r.get("tc") in cases
        and r.get("outcome") == "fail"
        and r.get("file") not in known
    ]


def accepted_risk_state(da, view, needs, tcs=(), records=()):
    """SR-202: `(state, reasons)` for an assumption's accepted risk, or
    `(None, [])` when it records none.

    No result makes the risk moot: a passed observation proves nothing beyond
    its sample. The risk is bound to the approval act that accepted it (`view`, read by `baseline_snapshot.risk_acceptance_view`:
    the act, and the rows and record files as they stood there), and it reads
    `RISK_UNPROVEN`, naming each trigger, when the assumption's bound cells or
    the need or acceptance text of a need it served then differ now, or when a
    failing record of a case naming it is not in the act's tree. A later
    re-approval of a changed need clears nothing, since the comparison is with
    the act, not with the latest recorded copy; accepting the risk again in an
    act moves the anchor. With no act found (history too shallow, no act
    accepting the risk) it reads unproven with the view's reason. Otherwise
    `RISK_COVERED`. No clock is read, so time alone never reopens it.

    Implements: SR-202, LLR-239
    """
    did = _cell(da, "DA-ID")
    if not _cell(da, "AcceptedRisk"):
        return None, []
    if not view or not view.get("act"):
        reason = (view or {}).get("reason") or "no record of its acceptance was read"
        return RISK_UNPROVEN, [
            "no act accepting assumption {}'s risk was found: {}".format(did, reason)
        ]
    act = view["act"][:12]
    reasons = (
        _assumption_drift(did, view.get("assumption"), da, act)
        + _need_drift(did, view, needs, act)
        + _late_failures(did, view, tcs, records, act)
    )
    return (RISK_UNPROVEN, reasons) if reasons else (RISK_COVERED, [])


def accepted_risk_advisories(das, tcs, needs, records, views):
    """SR-202's report: one advisory per assumption whose accepted risk has
    reopened, naming each trigger. `views` maps an assumption id to its
    `baseline_snapshot.risk_acceptance_view`.
    """
    out = []
    for did, da in _real(das, "DA-ID"):
        if not _cell(da, "AcceptedRisk"):
            continue
        state, reasons = accepted_risk_state(da, views.get(did), needs, tcs, records)
        if state == RISK_UNPROVEN:
            out.append(
                "assumption {}'s accepted risk has reopened, and it reads "
                "unproven until the risk is accepted again in a reviewed "
                "approval: {}".format(did, "; ".join(reasons))
            )
    return out


def observation_evidence_findings(
    srs,
    das,
    tcs,
    needs,
    bifs,
    *,
    records,
    raw_files,
    views,
    gate=False,
):
    """The observation results and what they can falsify, as `trace.main`
    composes them: `(integrity, advisories)`.

    INTEGRITY: every record file that is not a whole record or that its case
    does not allow (`observation_record_findings`), with or without a frame,
    since an observation case need not name an assumption. ADVISORIES, where
    the frame declares a crossing: the falsification worklist and each
    reopened accepted risk. No assumption is reported for lacking a result.
    `gate` is the assumption gate's setting, read by the caller.
    """
    integrity = observation_record_findings(records, raw_files, tcs)
    if not bifs:
        return integrity, []
    advisories = falsification_worklist(
        das, srs, tcs, records, gate=gate
    ) + accepted_risk_advisories(das, tcs, needs, records, views)
    return integrity, advisories


# --- the approval brief's chain: what an approver judges an assumption by -----
# An assumption is approved for what it lets the requirements claim, so the
# approver's question is whether those requirements may rely on it (SR-203).
# The brief therefore needs, for one row, everything that question reads: the
# requirements citing it with their text, the needs derived through them,
# where its outcome lands and whose crossing that is, the cases that can
# falsify it, and what would show it false. A fidelity assumption is
# meaningless without its surrogate, and a surrogate without the assumptions
# stating its fidelity, so each carries the other.


def _named(rows, id_col, name_col):
    """`{id: name}` over the real rows."""
    return {rid: _cell(row, name_col) for rid, row in _real(rows, id_col)}


def _surrogate_chain(sid, reg):
    """The chain of one surrogate: its cells, the parties it emulates with
    their names, and the assumptions naming it in `RealizedBy` with their
    text."""
    surrogates = dict(_real(reg.get("surs") or (), "SUR-ID"))
    if sid not in surrogates:
        return None
    row = surrogates[sid]
    entities = _named(reg.get("exts") or (), "EXT-ID", "Name")
    return {
        "id": sid,
        "kind": "surrogate",
        "row": row,
        "emulates": [(e, entities.get(e, "")) for e in refs(row.get("Emulates"))],
        "named_by": [
            (did, _cell(da, "Assumption"))
            for did, da in _real(reg.get("das") or (), "DA-ID")
            if sid in refs(da.get("RealizedBy"))
        ],
    }


def assumption_chain(da_id, reg):
    """What the approval brief shows for one assumption or surrogate, or None
    when the registry does not declare `da_id`.

    For an ASSUMPTION: its row, the requirements citing it (`da_citing_srs`) as
    `(id, title, requirement text)`, the needs derived through them as
    `(id, need text)` in first-seen order, each landing crossing as
    `(crossing, entity, entity name)`, the cases naming it in
    `Assumption-Refs` (the ones that can falsify it), its falsifier, and,
    for a fidelity assumption, its surrogate's chain. For a SURROGATE: its row,
    the parties it emulates as `(id, name)` and the assumptions naming it as
    `(id, assumption text)`.

    `reg` is a mapping of rows already read: `srs`, `needs` (the carrier's need
    rows), `das`, `surs`, `exts`, `bifs` and `tcs`. A missing key reads as
    empty. Nothing is read from disk here, and no result is read at all.

    Implements: SR-203, LLR-240
    """
    if str(da_id).startswith("SUR-"):
        return _surrogate_chain(da_id, reg)
    das = dict(_real(reg.get("das") or (), "DA-ID"))
    if da_id not in das:
        return None
    row = das[da_id]
    srs = reg.get("srs") or ()
    requirements = dict(_real(srs, "SR-ID"))
    citing = da_citing_srs(srs).get(da_id, [])
    need_text = {
        nid: _cell(n, "need") for nid, n in _real(reg.get("needs") or (), "id")
    }
    served = _unique(
        n for sid in citing for n in refs(requirements[sid].get("SN-Refs"))
    )
    crossings = {_cell(b, "B-ID"): _cell(b, "Entity") for b in reg.get("bifs") or ()}
    entities = _named(reg.get("exts") or (), "EXT-ID", "Name")
    named = refs(row.get("RealizedBy"))
    return {
        "id": da_id,
        "kind": "assumption",
        "row": row,
        "citing": [
            (
                sid,
                _cell(requirements[sid], "Title"),
                _cell(requirements[sid], "Requirement"),
            )
            for sid in citing
        ],
        "needs": [(nid, need_text.get(nid, "")) for nid in served],
        "landing": [
            (bid, crossings.get(bid, ""), entities.get(crossings.get(bid, ""), ""))
            for bid in refs(row.get("EffectAt"))
        ],
        "cases": _citing_cases(da_id, reg.get("tcs") or ()),
        "falsifier": _cell(row, "Falsifier"),
        "surrogate": _surrogate_chain(named[0], reg) if len(named) == 1 else None,
    }


# --- the assumption gate: the argument behind each requirement, gated ---------
# Everything above REPORTS. With the project's `[checks] assumption_gate` on,
# the same questions FAIL a check step instead, each at the rung where it can
# first be answered honestly (spine map D16: gates are check steps, never
# conjuncts of the derived stage, which stays the harness evidence's alone):
#
#   DevStg-Boundary  maturity: each requirement not recorded coincident cites
#                    approved, active assumptions that reach its stakeholders
#                    (SR-205), and each interface-form requirement's crossings
#                    are coincident or bridged by a cited assumption landing on
#                    them (SR-212's Boundary arm), since the crossings are the
#                    level-0 interfaces approved with the frame;
#   DevStg-Arch      the same form judged against the boundary interfaces that
#                    realize the crossings, once they exist (SR-212's Arch arm);
#   DevStg-Release   standing: no relied-on assumption is falsified unless
#                    an accepted risk that has not reopened covers it
#                    (SR-206). No result is asked for: an assumption carries
#                    no evidence level (owner ruling 2026-10-02).
#
# With the gate off the step prints the same findings as advisories and
# passes. The rules below return the findings alone; which of the two they
# become is the step's (`check_assumption_gate.py`).


def _unmet(did, da, surrogates, reach):
    """The conditions assumption `did` fails for a requirement relying on it
    at the boundary gate, one reason each, in the order SR-205 names them."""
    if da is None:
        return ["is not a declared assumption"]
    out = []
    if not is_approved(da):
        out.append("is not approved (Status {})".format(_cell(da, "Status") or "unset"))
    if _cell(da, "Standing") != "active":
        out.append(
            "is not active (Standing {})".format(_cell(da, "Standing") or "unset")
        )
    if reach.get(did):
        out.append(
            "does not reach the stakeholders of its needs: " + "; ".join(reach[did])
        )
    return out + [
        "is a fidelity assumption whose surrogate {} is not approved".format(sur)
        for sur in refs(da.get("RealizedBy"))
        if not is_approved(surrogates.get(sur) or {})
    ]


def boundary_gate_findings(srs, das, surs, reach, have_frame):
    """SR-205's boundary gate, as findings naming the requirement, the
    assumption and the unmet condition.

    A requirement recorded coincident (`Coincident`) passes. Any other
    requirement fails when it cites no assumption, and once for each unmet
    condition of each assumption it cites: not `Approved`, `Standing` not
    active, reported by the reach check (`reach`, `reach_gaps`' map), or a
    fidelity assumption whose `RealizedBy` surrogate is not `Approved`. With
    no assumptions registry every requirement not recorded coincident
    therefore fails: enabling the gate asks for the argument.

    Nothing when `have_frame` is false: with no declared crossing an
    assumption has nowhere to land, and the tier does not apply.

    Implements: SR-205, LLR-242
    """
    if not have_frame:
        return []
    declared = dict(_real(das, "DA-ID"))
    surrogates = dict(_real(surs, "SUR-ID"))
    out = []
    for sid, row in _real(srs, "SR-ID"):
        if _cell(row, "Coincident"):
            continue
        cited = refs(row.get("DA-Refs"))
        if not cited:
            out.append(
                "SR {} cites no assumption in DA-Refs and records no Coincident "
                "waiver: the gate asks every requirement for the argument that "
                "carries it to its needs".format(sid)
            )
        for did in cited:
            out += [
                "SR {} relies on assumption {}, which {}".format(sid, did, why)
                for why in _unmet(did, declared.get(did), surrogates, reach)
            ]
    return out


def release_gate_findings(das, srs, risks):
    """SR-206's release gate, as findings naming the assumption, the
    requirements relying on it and why it blocks, over each assumption at
    least one requirement cites.

    It reads STANDING, never a result: an active assumption passes whatever
    results it has or lacks, since a passed observation proves nothing beyond
    its sample and a failing one sets nothing until a person records the
    assumption false. A falsified assumption passes only while its accepted
    risk reads covered (`risks`, `accepted_risk_state` per assumption id); with
    no accepted risk, or one reopened, it fails, naming the reopening
    triggers.

    Implements: SR-206, LLR-243
    """
    cited = da_citing_srs(srs)
    out = []
    for did, da in _real(das, "DA-ID"):
        if did not in cited or _cell(da, "Standing") != "falsified":
            continue
        reading, reasons = risks.get(did) or (None, [])
        if reading == RISK_COVERED:
            continue
        risk = "its accepted risk has reopened: " + "; ".join(reasons or ["?"])
        out.append(
            "assumption {}, relied on by {}: it is falsified (its Standing reads "
            "falsified), and {}".format(
                did,
                ", ".join(cited[did]),
                risk if reading else "it records no accepted risk",
            )
        )
    return out


def module_srs(llrs):
    """`{module: [requirement ids]}`: each design row's `Module` entries,
    normalized by `norm_module`, mapped to the requirements its `SR-Refs`
    names, in row order and once each.

    Implements: SR-212, LLR-244
    """
    out = {}
    for _lid, row in _real(llrs, "LLR-ID"):
        for module in refs(row.get("Module")):
            listed = out.setdefault(norm_module(module), [])
            listed += [s for s in refs(row.get("SR-Refs")) if s not in listed]
    return out


def if_reached_srs(ifs, llrs):
    """`{interface id: [requirement ids]}` for each BOUNDARY interface (a
    from- or to-external tie-back): the requirements its owner's module
    realizes, through the design rows naming that module. Derived here and
    never recorded on the interface, so the relation has one home.

    Implements: SR-212, LLR-244
    """
    by_module = module_srs(llrs)
    return {
        iid: by_module.get(norm_module(_cell(row, "Owner")), [])
        for iid, row in _real(ifs, "IF-ID")
        if _crossings(row)
    }


def _interface_form(srs):
    """`(id, row)` for each requirement whose `Form` is interface."""
    return [(s, r) for s, r in _real(srs, "SR-ID") if _cell(r, "Form") == "interface"]


def interface_form_gate_findings(srs, ifs, llrs):
    """SR-212's Arch arm, as findings: each interface-form requirement judged
    against EVERY boundary interface reaching it (`if_reached_srs`).

    One reached by none fails, naming it and stating that no boundary
    interface reaches it; nothing is invented to reach it. Each reaching
    interface that records no `Coincident` and whose `BridgedBy` shares no
    assumption with the requirement's `DA-Refs` fails, naming the requirement
    and that interface, so one valid interface never excuses another. The
    other two forms are not judged.

    Implements: SR-212, LLR-244
    """
    rows = dict(_real(ifs, "IF-ID"))
    reaching = {}
    for iid, sids in if_reached_srs(ifs, llrs).items():
        for sid in sids:
            reaching.setdefault(sid, []).append(iid)
    out = []
    for sid, row in _interface_form(srs):
        if sid not in reaching:
            out.append(
                "SR {} is of interface form, but no boundary interface reaches it "
                "through the modules its design rows name".format(sid)
            )
            continue
        cited = set(refs(row.get("DA-Refs")))
        for iid in reaching[sid]:
            bridging = refs(rows[iid].get("BridgedBy"))
            if _cell(rows[iid], "Coincident") or cited & set(bridging):
                continue
            out.append(
                "SR {} is reached by boundary interface {}, which records no "
                "Coincident waiver and is bridged by no assumption the "
                "requirement cites (BridgedBy: {})".format(
                    sid, iid, ", ".join(bridging) or "none"
                )
            )
    return out


def crossing_gate_findings(srs, das, bifs):
    """SR-212's Boundary arm, as findings: each interface-form requirement
    judged against every declared crossing its `Boundary-Refs` names.

    The frame's crossings are the level-0 interfaces, approved with the frame
    before any interface row exists, and an assumption already lands on them
    (`EffectAt`). So a requirement recorded coincident passes, its own
    specification being the outcome at the crossing; otherwise each crossing
    it names must be the landing of an assumption it cites, and each one that
    is not fails, naming the requirement and the crossing. The other two
    forms are not judged, and neither is a crossing the frame does not
    declare, which the frame's own reference rule fails. Nothing with no
    declared crossing.

    Implements: SR-212, LLR-244
    """
    declared = {_cell(r, "B-ID") for r in bifs}
    lands = {did: set(refs(r.get("EffectAt"))) for did, r in _real(das, "DA-ID")}
    out = []
    for sid, row in _interface_form(srs):
        if _cell(row, "Coincident"):
            continue
        cited = refs(row.get("DA-Refs"))
        for bid in refs(row.get("Boundary-Refs")):
            if bid not in declared or any(bid in lands.get(d, ()) for d in cited):
                continue
            out.append(
                "SR {} names crossing {} in Boundary-Refs, but records no "
                "Coincident waiver and cites no assumption landing on it "
                "(EffectAt)".format(sid, bid)
            )
    return out
