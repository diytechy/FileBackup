#!/usr/bin/env python3
"""Generate the human release checklist from the registries.

Stack-agnostic kit, stdlib-only (Python 3.11+). Most of the harness is machine-
checkable, but a release still needs a human to *exercise the real product* —
the Demonstration / Manual / Inspection items that no automated test can honestly
cover (the owner's final read in process.md). This script collects exactly those, back-linked to
their requirement ids, into a tick-box checklist so the release sign-off is
concrete and traceable instead of a vibe.

It pulls, from `docs/`:
    - Stakeholder needs (SN) + their acceptance intent -> "Does the product meet the need?"
    - System specifications whose Verification is Demonstration / Manual / Inspection
    - Release-tier test cases, and any non-automated (manual) test cases
    - Provided cross-project interfaces (IF, if present) -> contract still honored?
    - Performance budgets (PB, if present) -> still within allocation? (§9; the
      warn-tier runtime budgets never fail the gate, so a human confirms them here)
    - Active Approved assumptions and any missing falsifier -> recall whether
      the assumption has been falsified; a person sets standing
    - A REQUIRED re-judge item (SR-215): the command that files one re-judge
      work item per observation test case due at the release commit, with
      how many are due now

Ordinary rows use `- [ ] <ID> — <what to confirm> (refs)`; assumption rows use
the differentiable `ASSUMPTION <DA-ID>` marker. The output is a *generated
record*: regenerate it per release and keep the ticked copy as the sign-off
artifact (use --version to file it under docs/releases/).

Usage:
    python scripts/gen_release_checklist.py [--docs docs] [--version X]
                                            [--phase LIST] [--out PATH]

    --version  Stamp the checklist and write to docs/releases/checklist-<X>.md.
    --phase    Phased delivery (process.md §4): include only SRs whose Phase is
               blank or listed (e.g. v1 or v1,v2), and only the release-tier /
               manual TCs that verify an in-scope SR (or an LLR under one).
    --out      Explicit output path (overrides the default/--version location).
    default    Writes docs/release-checklist.md.

Contracts: IF-018 — the interface seam this module declares (process.md §8; row
of record in docs/requirements/interfaces.toml).

Contract IF-018: the human release checklist, written as a Markdown document
    whose ordinary items are `- [ ] <ID> — <what to confirm> (refs)`. It collects
    exactly the rows a machine cannot honestly close: stakeholder needs and
    their acceptance intent, system specifications whose Verification is
    Demonstration, Manual or Inspection, release-tier and manual test cases,
    the declared interface seams, and the performance budgets whose runtime
    tier never fails a gate. Its assumptions section lists each active Approved
    assumption and any assumption with no falsifier, once each, marked
    `- [ ] ASSUMPTION <DA-ID> — <falsifier question> (method: <TC IDs>)`.
    Checking an assumption asserts only that it has not been falsified; this
    generator sets nothing, and a person sets standing. Its release-hygiene
    section always carries one required item naming
    `intake.py rejudge --checkpoint release` and the
    number of observation test cases due at HEAD, or why that number could not
    be read. `--phase` narrows to the listed phases while the
    foundation phase is never deferred; `--version` files the output under
    `docs/releases/checklist-<X>.md`, `--out` overrides the path, and the
    default is `docs/release-checklist.md`. Every optional registry is
    absent-tolerant, so a repo without one simply has no section for it. The
    output is a generated RECORD: regenerate it per release and keep the ticked
    copy as the sign-off artifact.
"""

import argparse
import datetime
import re
import sys
from pathlib import Path

# The console guard's one home is the shipped package (WI-448 / D-8);
# aliased to the module-local name so no call site changes.
from kitlib.config import utf8_console as _utf8_console

# The spine ROW vocabulary — the `-000` placeholder test.
from kitlib import spine as _kitspine

# Sibling: the spine's registry CARRIER — the one home for
# the TOML tier tables, the key->column vocabulary and both readers. Run as a
# subprocess this script's own dir is sys.path[0] so a plain import resolves;
# the guard covers an in-process import (a test) whose sys.path does not yet
# carry scripts/ — the sanctioned-sibling idiom trace.py uses for trace_text.
try:
    import spine_carrier
except ImportError:  # pragma: no cover - in-process fallback
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import spine_carrier

# The checkpoint re-judge decision (SR-215). A pure read of git: this view may
# not import the intake mint, so it counts through the decision the mint files.
try:
    import rejudge
except ImportError:  # pragma: no cover - in-process fallback
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import rejudge

import assumption_rules

HUMAN_METHODS = {"Demonstration", "Manual", "Inspection"}

# The release checkpoint's command, as a person preparing a release runs it.
REJUDGE_COMMAND = "python scripts/intake.py rejudge --checkpoint release"


def _rejudge_checklist_line(root):
    """The release checklist's REQUIRED re-judge item: the command that files
    one re-judge work item per observation test case due at HEAD, and how many
    are due now, counted by the decision the command files through.

    Release preparation is a person's act, so the checkpoint is an item on the
    person's list rather than something this generator does unasked. A count
    git cannot give is stated as unavailable with its reason, never as zero,
    because zero would read as nothing to re-judge.

    Implements: SR-215, LLR-255
    """
    try:
        count = "{} observation test case(s) due now".format(
            len(rejudge.due_cases(root, "HEAD", checkpoint="release"))
        )
    except rejudge.RejudgeError as exc:
        count = "the due count could not be read ({})".format(exc)
    return (
        "- [ ] **Required** — re-judge observation tests: run `{}` and close "
        "each re-judge item it files before sign-off ({}).".format(
            REJUDGE_COMMAND, count
        )
    )


def load_csv(path):
    """The off-spine rows of a registry CSV, `[]` when absent; a leading `#`
    declaration header is skipped by the one shared reader."""
    if not path.exists():
        return []
    return _kitspine.csv_rows(path.read_text(encoding="utf-8-sig"))


# The `-000` placeholder-row convention. THE THIRD HOME, retired at WI-448
# slice 4: `kitlib.spine.is_example` is the one the pair already shares, and
# `tests/test_rule_sync.py` had to pin this copy against it by value — including
# a `None` case, because one of the three copies used to crash on it.
is_example = _kitspine.is_example


def read_stakeholder_needs(md_path):
    """`(SN-ID, need, acceptance)` per need, through the CARRIER.

    Was a bespoke markdown table parse that discovered its own `Need` and
    `Acceptance` columns by header text. Under one carrier those are fields, and
    the edge-case fold — which this reader never had, so an edge row's need read
    as its Lifecycle word here too — comes from the single home the fold now
    has."""
    return [
        (n["id"], n["need"], n["acceptance"])
        for n in spine_carrier.folded_needs(md_path)
    ]


def assumption_checklist_lines(docs, tcs):
    """Recall falsifiers at sign-off; a checked box cannot establish a premise.

    Implements: SR-033, LLR-296
    """
    rows = spine_carrier.load(
        Path(docs) / "requirements/assumptions.toml", "DA-ID", False
    )
    items = []
    for row in rows:
        falsifier = (row.get("Falsifier") or "").strip()
        if falsifier and not (
            row.get("Status") == "Approved" and row.get("Standing") == "active"
        ):
            continue
        rid = row["DA-ID"]
        methods = [
            tc["TC-ID"]
            for tc in tcs
            if assumption_rules.is_observation_tc(tc)
            and rid in re.split(r"[;,\s]+", tc.get("Assumption-Refs", ""))
        ]
        items.append(
            "- [ ] ASSUMPTION {} — has its falsifier been observed? {} (method: {})".format(
                rid,
                falsifier or "no falsifier declared",
                ", ".join(methods) or "none declared",
            )
        )
    if not items:
        return []
    return (
        [
            "",
            "## 7. Assumptions — not falsified",
            "",
            "Checking a box asserts only ‘not falsified’; a person sets `standing`.",
            "",
        ]
        + items
        + [""]
    )


def _read_checklist_rows(docs):
    """Read optional registries once; example rows are never release items."""
    needs = read_stakeholder_needs(docs / "requirements" / "stakeholder-needs.toml")
    srs = [
        r
        for r in spine_carrier.load(
            docs / "requirements" / "system-requirements.toml", "SR-ID"
        )
        if r.get("SR-ID") and not is_example(r["SR-ID"])
    ]
    tcs = [
        r
        for r in spine_carrier.load(docs / "test" / "test-cases.toml", "TC-ID")
        if r.get("TC-ID") and not is_example(r["TC-ID"])
    ]
    ifs = [
        r
        for r in spine_carrier.load(docs / "requirements" / "interfaces.toml", "IF-ID")
        if r.get("IF-ID") and not is_example(r["IF-ID"])
    ]
    # Performance budgets (process.md §9): the warn-tier runtime budgets never
    # fail the gate, so the release checklist is where a human confirms them.
    pbs = [
        r
        for r in load_csv(docs / "requirements" / "performance-budgets.csv")
        if r.get("PB-ID") and not is_example(r["PB-ID"])
    ]

    llrs = [
        r
        for r in spine_carrier.load(
            docs / "requirements" / "low-level-requirements.toml", "LLR-ID"
        )
        if r.get("LLR-ID") and not is_example(r["LLR-ID"])
    ]
    return needs, srs, llrs, tcs, ifs, pbs


def _phase_num(tag):
    m = re.search(r"\d+", tag or "")
    return int(m.group()) if m else None


def _in_phase(sr_row, phases, foundation_phase):
    """The foundation and blank phases remain in scope under any phase filter."""
    tag = (sr_row.get("Phase") or "").strip()
    if phases is None or not tag or tag in phases:
        return True
    n = _phase_num(tag)
    return n is not None and n == foundation_phase


def _tc_in_scope(tc_row, phases, in_scope_ids):
    cited = [x for x in re.split(r"[;,\s]+", tc_row.get("Verifies", "")) if x]
    return phases is None or any(x in in_scope_ids for x in cited)


def _scope_ids(srs, llrs, phases, foundation_phase):
    """Resolve LLR-only test targets through any in-scope parent requirement."""
    ids = {r["SR-ID"] for r in srs if _in_phase(r, phases, foundation_phase)}
    for r in llrs:
        parents = [p for p in re.split(r"[;,\s]+", r.get("SR-Refs", "")) if p]
        if any(p in ids for p in parents):
            ids.add(r["LLR-ID"])
    return ids


def _provided_interface(row):
    """A release confirms owned contracts read by an outside party."""
    return not (row.get("Owner") or "").strip().startswith("external:") and any(
        c.strip().startswith("external:")
        for c in (row.get("Requestors") or row.get("Consumers") or "").split(";")
    )


def _manual_release_case(row):
    """Unclassified cases remain human work, as do all release-tier cases."""
    return row.get("Tier", "") == "Release" or row.get(
        "Automated", ""
    ).strip().lower() in ("no", "false", "")


def _checklist_inputs(docs, phase):
    """Select human sign-off rows using the foundation and TC parentage rules."""
    needs, srs, llrs, tcs, ifs, pbs = _read_checklist_rows(docs)
    phases = {p for p in re.split(r"[;,\s]+", phase.strip()) if p} if phase else None
    foundation_phase = min(
        (n for n in (_phase_num(r.get("Phase")) for r in srs) if n is not None),
        default=None,
    )
    ids = _scope_ids(srs, llrs, phases, foundation_phase)
    human_srs = [
        r
        for r in srs
        if r.get("Verification", "") in HUMAN_METHODS
        and _in_phase(r, phases, foundation_phase)
    ]
    # Blank Automated means unclassified: keep it visible for a person.
    manual_tcs = [
        r for r in tcs if _manual_release_case(r) and _tc_in_scope(r, phases, ids)
    ]
    provided_ifs = [r for r in ifs if _provided_interface(r)]
    return needs, human_srs, manual_tcs, provided_ifs, pbs, tcs


def _need_lines(needs):
    L = []
    L += ["## 1. Stakeholder needs met (acceptance)", ""]
    if needs:
        for uid, need, acc in needs:
            detail = acc or need or "confirm the need is met"
            L.append("- [ ] **{}** — {} ({})".format(uid, detail, uid))
    else:
        L.append("- [ ] _(no stakeholder needs registered)_")

    return L


def _human_requirement_lines(human_srs):
    L = []
    L += [
        "",
        "## 2. Human-verified requirements (Demonstration / Manual / Inspection)",
        "",
    ]
    if human_srs:
        for r in human_srs:
            L.append(
                "- [ ] **{}** [{}] — {} (AcceptanceCriteria of {})".format(
                    r["SR-ID"],
                    r.get("Verification", ""),
                    r.get("Title", "").strip(),
                    r["SR-ID"],
                )
            )
    else:
        L.append("- [ ] _(every requirement is automated — nothing manual to verify)_")

    return L


def _manual_case_lines(manual_tcs):
    L = []
    L += ["", "## 3. Release-tier & manual test cases", ""]
    if manual_tcs:
        for r in manual_tcs:
            L.append(
                "- [ ] **{}** [{}] — {} (verifies {})".format(
                    r["TC-ID"],
                    r.get("Tier", "") or "Manual",
                    r.get("Method", "").strip(),
                    r.get("Verifies", ""),
                )
            )
    else:
        L.append("- [ ] _(no release-tier or manual test cases)_")

    return L


def _interface_lines(provided_ifs):
    L = []
    if provided_ifs:
        L += ["", "## 4. Cross-project contracts still honored", ""]
        for r in provided_ifs:
            L.append(
                "- [ ] **{}** ({} {}) — {} still satisfies the published "
                "contract ({} to {})".format(
                    r["IF-ID"],
                    r.get("Version", ""),
                    r.get("Status", ""),
                    r.get("Owner", ""),
                    r.get("Channel", ""),
                    r.get("Requestors") or r.get("Consumers", ""),
                )
            )

    return L


def _budget_lines(pbs):
    L = []
    if pbs:
        L += ["", "## 5. Performance budgets within allocation (§9)", ""]
        for r in pbs:
            arrow = "≤" if (r.get("Direction") or "").strip() == "lower-better" else "≥"
            L.append(
                "- [ ] **{}** — {} {} {}{} ({}; refs {})".format(
                    r["PB-ID"],
                    r.get("Metric", "").strip(),
                    arrow,
                    r.get("Budget", "").strip(),
                    r.get("Unit", "").strip(),
                    r.get("Gate", "").strip() or "warn",
                    r.get("Refs", "").strip(),
                )
            )

    return L


def main():
    """Write the release sign-off record.

    Implements: SR-033, LLR-033
    """
    _utf8_console()
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("--docs", default="docs")
    ap.add_argument("--version", default=None)
    ap.add_argument(
        "--phase",
        default=None,
        help="comma-separated phases in scope (blank Phase = every phase)",
    )
    ap.add_argument("--out", default=None)
    args = ap.parse_args()
    docs = Path(args.docs)

    needs, human_srs, manual_tcs, provided_ifs, pbs, tcs = _checklist_inputs(
        docs, args.phase
    )
    stamp = args.version or "(unreleased)"
    if args.phase and re.search(r"[^;,\s]", args.phase):
        stamp += " — phase {}".format(args.phase)
    today = datetime.date.today().isoformat()
    L = [
        "# Release Checklist — {}".format(stamp),
        "",
        "_Generated by `scripts/gen_release_checklist.py` on {}. Tick each box "
        "after exercising the real product; keep the completed copy as the "
        "DevStg-Impl sign-off record._".format(today),
        "",
        "- Version / build under test: __________   Date: __________   "
        "Signed-off by: __________",
        "",
    ]

    L += _need_lines(needs)
    L += _human_requirement_lines(human_srs)
    L += _manual_case_lines(manual_tcs)
    L += _interface_lines(provided_ifs)
    L += _budget_lines(pbs)
    L += [
        "",
        "## 6. Release hygiene",
        "",
        "- [ ] `python scripts/check.py --stage DevStg-Impl --tier release` is green "
        "(paste the output in the audit log).",
        _rejudge_checklist_line(docs.resolve().parent),
        "- [ ] CHANGELOG / release notes updated.",
        "- [ ] Version bumped; any changed `Approved` interface versions "
        "communicated to counterparts.",
        "- [ ] Docs (README / quick-reference) match the shipped behavior.",
        "- [ ] README `sn-inventory` bullets still reflect the current "
        "stakeholder needs (wording, not just ids — the gate checks ids).",
        "",
    ]

    L += assumption_checklist_lines(docs, tcs)

    if args.out:
        out = Path(args.out)
    elif args.version:
        out = docs / "releases" / "checklist-{}.md".format(args.version)
    else:
        out = docs / "release-checklist.md"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(L) + "\n", encoding="utf-8", newline="\n")

    print(
        "Release checklist -> {}  (SN={} human-SR={} manual-TC={} IF={} PB={})".format(
            out,
            len(needs),
            len(human_srs),
            len(manual_tcs),
            len(provided_ifs),
            len(pbs),
        )
    )


if __name__ == "__main__":
    main()
