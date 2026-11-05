"""THE FRAME AND NEED-TIER RULES — pure joins over the depth-0 frame's rows.

The sibling of `coherence.py`, and built the same way: every rule here is a
JOIN ACROSS ROWS, it reads no file, and `trace.analyze` composes it and stays
its only caller. `trace.py` is held to an exact size ratchet, so a new rule
family lands here and `trace.py` grows by the composition lines alone (spine
map D21).

What lives here is the frame's own vocabulary about SYSTEMS OF INTEREST. A frame
can hold two: the system in OPERATION, and the system that builds and DELIVERS
it (`kitlib.spine.SYSTEM_VALUES`). Each boundary crossing names which one it
belongs to (SR-187), and a requirement's system is DERIVED from the crossings
its `Boundary-Refs` name (SR-219), recomputed on every run and never written
back to the requirement.

The NEED TIER's joins onto the frame live here too. The needs file carries a
short STAKEHOLDER LIST beside its needs, naming who owns an outcome and which
declared entity of the frame they are (`party`), and each need names its
stakeholders (SR-189). A need may also point at the document it was drawn from
(`source`, SR-190). Whether that document and its anchor exist is a filesystem
question, so `trace.main` reads the anchors and hands them in, and the rule here
only compares.

Rows are the carrier's column-keyed dicts (`B-ID`, `System`, `SR-ID`,
`Boundary-Refs`, `STK-ID`, `Party`, `EXT-ID`), exactly as
`trace.load_registries` hands them over, except the needs, which arrive from
`spine_carrier.load_needs` with lower-case keys and their id under `id`. Every
function returns plain finding strings, per `trace.frame_findings`' note on the
pair shape.

Stdlib only. A plain sibling of `scripts/`, not a `kitlib` module, for the
reason `coherence.py` records: these are the checker's rules, and the
scaffolder has no business importing them.

Contracts: IF-180 — the seam this module declares (process.md §8; row of record
in docs/requirements/interfaces.toml).

Contract IF-180: the frame and need-tier rule surface `trace.py` imports. Rows
    in, findings out, and nothing else: no I/O, no git, no filesystem, no argv.
    `frame_system_findings(bifs)` returns `(failures, advisories)`: the
    failures join the frame class and `trace.py --strict`'s exit code, the
    advisories ride the warn pipe and never join a failure set.
    `sr_system_advisories(srs, bifs)` returns warn-only advisories, and
    `crossing_systems(bifs)` returns a crossing-id to system map.
    `stakeholder_findings(sn_needs, stks, exts)` returns `(failures,
    advisories)` on the same two pipes. `source_documents(sn_needs)` returns
    the sorted documents the needs' `source` cells name, and
    `need_source_findings(sn_needs, anchors)` returns gating failures, where
    `anchors` maps each of those documents to the set of anchors it exposes, or
    to None when it is not a file in the repository. Rows are the carrier's
    column-keyed dicts (the needs: `load_needs`' lower-case keys), and no
    function writes to a row it is handed.
    `mediation_findings(exts)` returns gating failures: an entity's `Mediates`
    naming an undeclared entity or the entity itself.
"""

try:
    from kitlib.spine import SYSTEM_VALUES, is_example, refs, seam_endpoints
except ImportError:  # pragma: no cover - in-process fallback
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from kitlib.spine import SYSTEM_VALUES, is_example, refs, seam_endpoints

# THE STAKEHOLDER ROW'S REQUIRED CELLS (SR-189), in the carrier's column names.
# `Party` is deliberately absent: a stakeholder need not be an entity the frame
# declares (a reviewer owns outcomes without being a party to a crossing).
# Implements: SR-189, LLR-216
STK_REQUIRED = ("Name", "Description", "Status")


def _system(row):
    """A crossing's declared system, stripped; `""` when it declares none."""
    return (row.get("System") or "").strip()


def frame_system_findings(bifs):
    """SR-187's crossing rule, as `(failures, advisories)`.

    A `System` value outside `SYSTEM_VALUES` is a FAILURE naming the crossing:
    the caller adds it to the frame class, which fails `--strict` beside the
    frame's other reference rules. A crossing declaring no value is an ADVISORY
    naming it and rides the warn pipe, because a frame drawn before the two
    systems were told apart is mid-authoring, not wrong. The frame's schema tier
    stays warn-only and judges no vocabulary for this cell, so this is the one
    place the pair is enforced. Vacuous when the frame declares no crossing.

    Implements: SR-187, LLR-212
    """
    failures, advisories = [], []
    allowed = " | ".join(SYSTEM_VALUES)
    for r in bifs:
        bid = r["B-ID"]
        value = _system(r)
        if not value:
            advisories.append(
                f"boundary {bid} declares no System ({allowed}) — the requirements "
                "naming it are placed by their other crossings"
            )
        elif value not in SYSTEM_VALUES:
            failures.append(
                f"boundary {bid} System={value!r} is not one of the two systems "
                f"of interest ({allowed})"
            )
    return failures, advisories


def crossing_systems(bifs):
    """Each crossing id -> its declared system, leaving out a crossing with none
    (and one whose value is outside the pair, which `frame_system_findings`
    already fails): such a crossing places no requirement.

    Implements: SR-219, LLR-213
    """
    return {r["B-ID"]: _system(r) for r in bifs if _system(r) in SYSTEM_VALUES}


def sr_system_advisories(srs, bifs):
    """SR-219's derived placement, as advisories: one per requirement whose
    named crossings belong to BOTH systems, naming the requirement and one
    crossing from each system.

    A requirement is placed by the crossings its `Boundary-Refs` name through
    `crossing_systems`; a crossing with no system contributes nothing, so the
    requirement is placed by its others. Nothing is written back to a row: the
    placement is recomputed on every run. Vacuous with no crossing declared.

    Implements: SR-219, LLR-213
    """
    systems = crossing_systems(bifs)
    if not systems:
        return []
    out = []
    for r in srs:
        first = {}
        for bid in refs(r.get("Boundary-Refs")):
            system = systems.get(bid)
            if system:
                first.setdefault(system, bid)
        if len(first) > 1:
            named = " and ".join(
                f"{first[s]} ({s})" for s in SYSTEM_VALUES if s in first
            )
            out.append(
                f"SR {r['SR-ID']} names crossings of both systems of interest: "
                f"{named} — a requirement belongs to one system; split it or "
                "re-point a crossing"
            )
    return out


# A pointer cell's entries, stripped. The carrier joins a TOML list on `;`, and
# the split is on `;` ALONE: a `source` target may hold a comma or a space in its
# path, and an STK id holds none of the three. That is the carrier's one list-cell
# split, so it is bound from its home (`kitlib.spine.seam_endpoints`, WI-821)
# under this module's local name rather than carried as a second body.
_entries = seam_endpoints


def _real_needs(sn_needs):
    """`(id, need)` for each need that is not the template's `-000` example."""
    for need in sn_needs:
        nid = str(need.get("id") or "").strip()
        if nid and not is_example(nid):
            yield nid, need


def _stakeholder_row_findings(row, entities):
    """One stakeholder's own failures: a missing required cell, a party naming
    no declared entity. A status outside the spine's vocabulary is not one: it
    is schema, and the always-on integrity floor reports it once, as it does
    every tier's status, so a second copy here would count one bad cell twice."""
    sid, out = row["STK-ID"], []
    missing = [c.lower() for c in STK_REQUIRED if not (row.get(c) or "").strip()]
    if missing:
        out.append(
            "stakeholder {} has no {} — a stakeholder states who it is, which "
            "outcomes it owns and its maturity".format(sid, " or ".join(missing))
        )
    party = (row.get("Party") or "").strip()
    if party and party not in entities:
        out.append(
            "stakeholder {} Party names {}, which is not an entity the frame "
            "declares".format(sid, party)
        )
    return out


def stakeholder_findings(sn_needs, stks, exts):
    """SR-189's stakeholder rules, as `(failures, advisories)`.

    FAILURES, which the caller joins to the frame class so they fail wherever
    the frame check runs rather than only under `--strict-schema`: a stakeholder
    missing a `STK_REQUIRED` cell, a stakeholder whose `Party` names no declared
    entity, and a need whose `stakeholder_refs` names an undeclared stakeholder.
    A stakeholder with no party is valid. A status outside the closed vocabulary
    is the integrity floor's, not this rule's (`_stakeholder_row_findings`).

    ADVISORIES: a need naming no stakeholder, one line per need. It rides the
    warn pipe, because a need with no named owner is unconfirmable rather than
    wrong, and every need written before the list existed would otherwise fail
    at once.

    VACUOUS when the needs file declares no stakeholder (the `-000` example is
    none): nothing is advised. A need that CITES a stakeholder is still held to
    the list, so a reference written before its row fails naming both.

    `stks` are the rows loaded by their own `STK-ID` column, so a stakeholder's
    status never mixes with the needs' draft state.

    Implements: SR-189, LLR-216
    """
    entities = {r["EXT-ID"] for r in exts}
    failures = [f for r in stks for f in _stakeholder_row_findings(r, entities)]
    declared = {r["STK-ID"] for r in stks}
    advisories = []
    for nid, need in _real_needs(sn_needs):
        cited = _entries(need.get("stakeholder_refs"))
        failures += [
            "need {} stakeholder_refs names {}, which is not a declared "
            "stakeholder".format(nid, ref)
            for ref in cited
            if ref not in declared
        ]
        if declared and not cited:
            advisories.append(
                "need {} names no stakeholder in stakeholder_refs — nobody is "
                "recorded as the owner who can confirm it is still wanted".format(nid)
            )
    return failures, advisories


def _target(entry):
    """A `source` entry split into its document and its anchor, both stripped."""
    path, _, anchor = entry.partition("#")
    return path.strip(), anchor.strip()


def source_documents(sn_needs):
    """The distinct documents the needs' `source` cells name, sorted: the set
    `trace.main` reads the anchors of, once each, before it calls
    `need_source_findings`."""
    return sorted(
        {
            _target(entry)[0]
            for _nid, need in _real_needs(sn_needs)
            for entry in _entries(need.get("source"))
        }
    )


def need_source_findings(sn_needs, anchors):
    """SR-190's pointer rule: each `source` entry, written `path#anchor`,
    resolves to a file in the repository and to an anchor that file exposes.

    `anchors` maps each document `source_documents` names to the set of
    lower-case anchors it exposes (a heading's slug or an explicit id), or to
    None when it is not a file in the repository. A failure names the need and
    the entry, and the caller joins it to the frame class. An entry with no
    anchor names none the document exposes, so it fails the same way. A need
    with no `source` is valid. The cell is a POINTER, so it stays outside the
    provenance rule that scans the need's prose.

    Implements: SR-190, LLR-217
    """
    out = []
    for nid, need in _real_needs(sn_needs):
        for entry in _entries(need.get("source")):
            path, anchor = _target(entry)
            exposed = anchors.get(path)
            if exposed is None:
                out.append(
                    "need {} source {!r} names no file in the repository".format(
                        nid, entry
                    )
                )
            elif anchor.lower() not in exposed:
                out.append(
                    "need {} source {!r} names no anchor {} exposes — point at a "
                    "heading or an explicit id in it".format(nid, entry, path)
                )
    return out


def mediation_findings(exts):
    """SR-195's frame rule, as failures: an entity's `Mediates` names a
    declared entity other than itself.

    A party with no crossing of its own is reached through one that carries
    its writes and shows it the system's verdicts, and `Mediates` records that
    relation, one entity id. Its one reader is the assumption tier's reach
    check (`assumption_rules.reaching_parties`); it grants no authority and
    moves no sign-off. A mediation naming an undeclared entity, or the row
    itself, would let a crossing reach a party the frame never agreed to, so
    each FAILS naming the entity and the value, and the caller joins it to the
    frame class beside the frame's other reference rules. An empty cell is no
    mediation. The template's `-000` example is never judged.

    Implements: SR-195, LLR-226
    """
    entities = {r["EXT-ID"] for r in exts}
    out = []
    for r in exts:
        eid, target = r["EXT-ID"], (r.get("Mediates") or "").strip()
        if not target or is_example(eid):
            continue
        if target == eid:
            out.append(
                f"entity {eid} Mediates names itself — a party mediates for "
                "another entity, never for itself"
            )
        elif target not in entities:
            out.append(
                f"entity {eid} Mediates names {target}, which is not an entity "
                "the frame declares"
            )
    return out
