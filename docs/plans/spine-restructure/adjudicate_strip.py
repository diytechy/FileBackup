"""The coordinator's strip adjudication: two proposals in, one stripped spine out.

The two independent strip proposals live under strip/. This script holds the
coordinator's ruling as data: which proposal is the base for each tier, why,
and every row-level override with its reason. It writes:

  strip/final/{sn,sr,llr}.json   the adjudicated rows, with their removal ledgers
  strip/adjudication.md          rulings, overrides, retirements, and the
                                 behaviour findings both proposers raised

With --apply it also writes the stripped text back into the registries
(stakeholder-needs.md, system-requirements.csv, low-level-requirements.csv) and
removes retired rows. Only text cells change; ids, refs, status, priority,
verification and phase are untouched. Stdlib only:

    python docs/plans/spine-restructure/adjudicate_strip.py [--apply]
"""

from __future__ import annotations

import csv
import io
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
REQ = ROOT / "docs" / "requirements"
STRIP = HERE / "strip"
FINAL = STRIP / "final"

# Base proposal per tier, and why.
BASE = {
    "sn": ("opus-sn-sr", "Keeps each need's outcome and its reason with fewer losses; Astra's need text "
                         "is thinner and occasionally drops a stakeholder-visible clause."),
    "sr": ("astra-sn-sr", "Follows the brief's tier rule: an SR keeps what is observable at the system "
                          "boundary and moves internal mechanism down, logging each move with destination "
                          "LLR. Opus kept the mechanism inline (89% of source length), which the "
                          "restructure would have to strip again."),
    "llr": ("opus-llr", "The LLR is where mechanism and its reasons live. Opus keeps both in contract voice; "
                        "Astra's condensation (52% of source length) drops arguments the restructure's "
                        "rationale cells will need."),
}
OTHER = {"opus-sn-sr": "astra-sn-sr", "astra-sn-sr": "opus-sn-sr", "opus-llr": "astra-llr"}

# Row-level overrides: (tier, id) -> (verdict, cells-or-source, reason).
# cells "astra"/"opus" takes that proposer's row whole; a dict replaces cells
# on top of the base row.
OVERRIDES = {
    ("sn", "SN-005"): ("strip", {
        "Need (plain language)": "Restore the original tree **bit-for-bit from the backup folder alone**, "
                                 "without installing FileBackup and using only commonly available tools.",
        "Acceptance intent (how we'd know it's met)": "Copy a backup folder to a machine without FileBackup, "
            "run its restore kit using only commonly available tools, and byte-compare the result to the "
            "original: identical.",
    }, "Astra flagged 'no installs' against the restore-tool floor (SN-022/035). The ruled vision settles it: "
       "FileBackup is never needed to recover, and the restore kit runs with commonly available tools."),
    ("sn", "SN-007"): ("strip", {
        "Need (plain language)": "Control how often unchanged files have their content rechecked, to trade "
                                 "speed against integrity.",
        "Why it matters": "Rechecking a huge tree every run is slow; I want options from every run to never.",
        "Acceptance intent (how we'd know it's met)": "Each recheck setting, from every run to never, decides "
            "deterministically whether an unchanged file's content is rechecked on a given run.",
    }, "Opus kept the configuration key and its codes as declared vocabulary. A need is the owner's outcome; "
       "the key belongs to the configuration interface. Both proposers' acceptance still named the key."),
    ("sn", "SN-024"): ("strip", "astra",
       "Opus retired the row as delivery. Only the build and export tooling is delivery (D3); running "
       "backups in a container on a backup host is a product need, and the gap map lists container operation "
       "as a need. Astra's strip keeps that runtime need."),
    ("sr", "SR-033"): ("strip", None,
       "Astra flagged it: no Linux backup engine exists. It is a phase-deferred Drafted row under SN-023, so it "
       "stays, stripped, and the flag goes to the findings."),
    ("sr", "SR-034"): ("strip", None,
       "Opus retired it as delivery. As with SN-024, the container runtime contract is product; only build "
       "and export are delivery."),
    ("sr", "SR-052"): ("strip", None,
       "Astra flagged a visible code-versus-row gap (source scanning and index sanitation precede the "
       "capacity refusal the row says comes before any mutation). Kept as written; recorded as a finding."),
    ("llr", "LLR-026"): ("strip", {"Detail": None},
       "Opus added 'This bounds the cost to one existence check per stored object per run', which no source "
       "cell states. Removed."),
    ("llr", "LLR-089"): ("retire", None,
       "Opus retires it as one revision bump's history, with its durable remnants on LLR-076 and LLR-094; "
       "Astra kept the compatibility clause. The clause is LLR-094's, so the row is history."),
}
INVENTED = {("llr", "LLR-026", "Detail"): " This bounds the cost to one existence check per stored object per run."}

SN_TEXT = ["Need (plain language)", "Why it matters", "Acceptance intent (how we'd know it's met)",
           "Scenario", "Expected behavior"]
QUOTES = str.maketrans({"‘": "'", "’": "'", "“": '"', "”": '"'})


def load(who: str, tier: str) -> dict[str, dict]:
    rows = json.loads((STRIP / who / f"{tier}.json").read_text(encoding="utf-8"))
    return {r["id"]: r for r in rows}


def adjudicate(tier: str) -> tuple[list[dict], list[str], list[dict]]:
    harvest = json.loads((HERE / "harvest" / f"{tier}.json").read_text(encoding="utf-8"))
    base_name = BASE[tier][0]
    base, other = load(base_name, tier), load(OTHER[base_name], tier)
    final, notes, findings = [], [], []
    for h in harvest:
        rid = h["id"]
        row = json.loads(json.dumps(base[rid]))
        row["source"] = base_name
        row.setdefault("cells", {})
        if (tier, rid) in OVERRIDES:
            verdict, cells, reason = OVERRIDES[(tier, rid)]
            if cells == "astra" or cells == "opus":
                pick = base if base_name.startswith(cells) else other
                row = json.loads(json.dumps(pick[rid]))
                row["source"] = base_name if pick is base else OTHER[base_name]
                row.setdefault("cells", {})
            elif isinstance(cells, dict):
                for c, v in cells.items():
                    if v is None:
                        text = row["cells"].get(c, h["cells"].get(c, ""))
                        row["cells"][c] = text.replace(INVENTED[(tier, rid, c)], "")
                    else:
                        row["cells"][c] = v
                row["source"] += " + coordinator"
            row["verdict"] = verdict
            notes.append(f"- **{rid}** → {verdict}. {reason}")
        for who, prop in ((base_name, base), (OTHER[base_name], other)):
            r = prop[rid]
            if r.get("verdict") == "flag" or r.get("contradicts"):
                findings.append({"id": rid, "by": who, "verdict": r.get("verdict"),
                                 "contradicts": r.get("contradicts", []), "notes": r.get("notes", "")})
        row["cells"] = {c: re.sub(r"\s*\n\s*", " ", v.translate(QUOTES)).strip()
                       for c, v in row.get("cells", {}).items()}
        final.append(row)
    return final, notes, findings


def csv_rewrite(path: Path, key: str, final: list[dict]) -> None:
    by_id = {r["id"]: r for r in final}
    with path.open(encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        fields, rows = reader.fieldnames, list(reader)
    out = io.StringIO()
    w = csv.DictWriter(out, fieldnames=fields, quoting=csv.QUOTE_ALL, lineterminator="\r\n")
    w.writeheader()
    for row in rows:
        r = by_id[row[key]]
        if r["verdict"] == "retire":
            continue
        row.update(r.get("cells", {}))
        w.writerow(row)
    path.write_bytes(out.getvalue().encode("utf-8"))


def sn_rewrite(path: Path, final: list[dict]) -> None:
    by_id = {r["id"]: r for r in final}
    lines, header = [], None
    for line in path.read_text(encoding="utf-8").splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")] if line.startswith("|") else []
        if cells and cells[0] == "SN-ID":
            header = cells
        if cells and header and re.fullmatch(r"SN-\d{3}", cells[0]):
            r = by_id[cells[0]]
            if r["verdict"] == "retire":
                continue
            row = dict(zip(header, cells))
            row.update({c: v.replace("|", "\\|") for c, v in r.get("cells", {}).items()})
            line = "| " + " | ".join(row[h] for h in header) + " |"
        lines.append(line)
    path.write_bytes(("\r\n".join(lines) + "\r\n").encode("utf-8"))


def report(results: dict) -> str:
    out = ["# Strip adjudication", "",
           "Two independent proposals per tier (GPT-6 Astra, medium, via Codex; Claude Opus, medium), "
           "each from `strip-brief.md` without sight of the other. The coordinator's ruling follows. "
           "The per-row comparison is in `compare-{sn,sr,llr}.md`, and the adjudicated rows, with the "
           "removal ledger saying where each removed piece belongs, are in `final/`.", ""]
    for tier, (final, notes, findings) in results.items():
        base_name, why = BASE[tier]
        verdicts = {}
        for r in final:
            verdicts[r["verdict"]] = verdicts.get(r["verdict"], 0) + 1
        moved = sum(1 for r in final for x in r.get("removed", []) if x.get("destination") in {"LLR", "IF", "TC"})
        out += [f"## {tier.upper()}", "", f"**Base: {base_name}.** {why}", "",
                f"Result: {verdicts}. {moved} removed pieces carry a destination tier (LLR/IF/TC) for the "
                "restructure to place.", ""]
        if notes:
            out += ["Overrides:", "", *notes, ""]
        retired = [r["id"] for r in final if r["verdict"] == "retire"]
        out += [f"Retired: {', '.join(retired) or 'none'}.", ""]
    out += ["## Behaviour findings for the Owner", "",
            "Each is a place where a proposer, checking the code, found the row and the code disagreeing, or "
            "two rows disagreeing. Stripping kept the side the code implements, or kept the row and flagged "
            "it. None changes behaviour; each needs a ruling during the restructure.", "",
            "| row | raised by | verdict | conflicts with | note |", "|---|---|---|---|---|"]
    for tier, (_, _, findings) in results.items():
        for f in findings:
            note = f["notes"].replace("|", "/").replace("\n", " ")
            out.append(f"| {f['id']} | {f['by']} | {f['verdict']} | {', '.join(f['contradicts'])} | {note} |")
    return "\n".join(out) + "\n"


def main() -> None:
    FINAL.mkdir(exist_ok=True)
    results = {t: adjudicate(t) for t in ("sn", "sr", "llr")}
    for tier, (final, _, _) in results.items():
        (FINAL / f"{tier}.json").write_text(json.dumps(final, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    (STRIP / "adjudication.md").write_text(report(results), encoding="utf-8")
    retired = {r["id"] for final, _, _ in results.values() for r in final if r["verdict"] == "retire"}
    for tier, (final, _, _) in results.items():
        for r in final:
            if r["verdict"] == "retire":
                continue
            for c, t in r.get("cells", {}).items():
                for rid in sorted(retired & set(re.findall(r"\b(?:SN|SR|LLR)-\d{3}\b", t))):
                    print(f"note: {r['id']} {c} still names retired {rid}")
    if "--apply" in sys.argv:
        sn_rewrite(REQ / "stakeholder-needs.md", results["sn"][0])
        csv_rewrite(REQ / "system-requirements.csv", "SR-ID", results["sr"][0])
        csv_rewrite(REQ / "low-level-requirements.csv", "LLR-ID", results["llr"][0])
        print("applied to the registries")
    for tier, (final, notes, findings) in results.items():
        print(f"{tier}: {len(final)} rows, {len(notes)} overrides, {len(findings)} findings")


if __name__ == "__main__":
    main()
