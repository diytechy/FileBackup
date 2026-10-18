"""Compare two independent strip proposals, tier by tier.

For each tier it validates both proposals against the harvest (one object per
row, in order, no unknown cells), then reports:
  - verdict agreement, and every row where the verdicts differ;
  - per changed cell, how far apart the two stripped texts are, and which
    rows differ most;
  - per row, the removal kinds only one proposer made.

The report goes to strip/compare-<tier>.md. Stdlib only:

    python docs/plans/spine-restructure/compare_strip.py sn sr llr
"""

from __future__ import annotations

import difflib
import json
import sys
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
STRIP = HERE / "strip"
SOURCES = {"sn": ("astra-sn-sr", "opus-sn-sr"), "sr": ("astra-sn-sr", "opus-sn-sr"),
           "llr": ("astra-llr", "opus-llr")}
TEXT_CELLS = {
    "sn": {"Need (plain language)", "Why it matters", "Acceptance intent (how we'd know it's met)",
           "Scenario", "Expected behavior"},
    "sr": {"Title", "Requirement", "Rationale", "AcceptanceCriteria"},
    "llr": {"Title", "Detail"},
}


def load(tier: str, who: str) -> list[dict]:
    return json.loads((STRIP / who / f"{tier}.json").read_text(encoding="utf-8"))


def validate(tier: str, rows: list[dict], harvest: list[dict], who: str) -> list[str]:
    problems = []
    if [r.get("id") for r in rows] != [h["id"] for h in harvest]:
        problems.append(f"{who}: ids are not one-per-row in harvest order")
    for r in rows:
        bad = set(r.get("cells", {})) - TEXT_CELLS[tier]
        if bad:
            problems.append(f"{who} {r.get('id')}: changed non-text cells {sorted(bad)}")
    return problems


def final_text(row: dict, harvest_row: dict, cell: str) -> str:
    return row.get("cells", {}).get(cell, harvest_row["cells"].get(cell, ""))


def compare(tier: str) -> str:
    harvest = json.loads((HERE / "harvest" / f"{tier}.json").read_text(encoding="utf-8"))
    a_name, b_name = SOURCES[tier]
    a, b = load(tier, a_name), load(tier, b_name)
    out = [f"# Strip comparison: {tier.upper()} ({a_name} vs {b_name})", ""]
    problems = validate(tier, a, harvest, a_name) + validate(tier, b, harvest, b_name)
    if problems:
        out += ["## Validation problems", ""] + [f"- {p}" for p in problems] + [""]
    by_id_a = {r["id"]: r for r in a}
    by_id_b = {r["id"]: r for r in b}
    agree = Counter()
    verdict_rows, text_rows, kind_rows = [], [], []
    for h in harvest:
        rid = h["id"]
        ra, rb = by_id_a.get(rid, {}), by_id_b.get(rid, {})
        va, vb = ra.get("verdict", "?"), rb.get("verdict", "?")
        agree[va == vb] += 1
        if va != vb:
            verdict_rows.append(f"| {rid} | {va} | {vb} | {ra.get('notes', '')[:140]} | {rb.get('notes', '')[:140]} |")
        cells = set(ra.get("cells", {})) | set(rb.get("cells", {}))
        worst = 1.0
        for cell in sorted(cells):
            ratio = difflib.SequenceMatcher(None, final_text(ra, h, cell), final_text(rb, h, cell)).ratio()
            worst = min(worst, ratio)
        if cells:
            src_len = sum(len(h["cells"].get(c, "")) for c in cells)
            len_a = sum(len(final_text(ra, h, c)) for c in cells)
            len_b = sum(len(final_text(rb, h, c)) for c in cells)
            text_rows.append((worst, rid, src_len, len_a, len_b))
        ka = Counter(x.get("kind") for x in ra.get("removed", []))
        kb = Counter(x.get("kind") for x in rb.get("removed", []))
        only_a = sorted(k for k in ka if k not in kb)
        only_b = sorted(k for k in kb if k not in ka)
        if only_a or only_b:
            kind_rows.append(f"| {rid} | {', '.join(only_a)} | {', '.join(only_b)} |")
    total = sum(agree.values())
    va_count = Counter(r.get("verdict") for r in a)
    vb_count = Counter(r.get("verdict") for r in b)
    out += ["## Summary", "",
            f"- Rows: {total}. Verdicts agree on {agree[True]}, differ on {agree[False]}.",
            f"- {a_name} verdicts: {dict(va_count)}",
            f"- {b_name} verdicts: {dict(vb_count)}",
            f"- Total stripped text: source {sum(t[2] for t in text_rows)} chars, "
            f"{a_name} {sum(t[3] for t in text_rows)}, {b_name} {sum(t[4] for t in text_rows)}.", ""]
    if verdict_rows:
        out += ["## Verdict disagreements", "", f"| id | {a_name} | {b_name} | {a_name} notes | {b_name} notes |",
                "|---|---|---|---|---|", *verdict_rows, ""]
    text_rows.sort()
    out += ["## Text distance (lowest similarity first; 1.0 = identical)", "",
            f"| id | similarity | source chars | {a_name} chars | {b_name} chars |", "|---|---|---|---|---|"]
    out += [f"| {rid} | {w:.2f} | {s} | {la} | {lb} |" for w, rid, s, la, lb in text_rows]
    out += [""]
    if kind_rows:
        out += ["## Removal kinds only one proposer made", "", f"| id | only {a_name} | only {b_name} |",
                "|---|---|---|", *kind_rows, ""]
    return "\n".join(out)


def main(tiers: list[str]) -> None:
    for tier in tiers:
        report = compare(tier)
        path = STRIP / f"compare-{tier}.md"
        path.write_text(report + "\n", encoding="utf-8")
        print(f"{tier}: {path.relative_to(HERE)}")
        print("\n".join(report.splitlines()[2:9]))


if __name__ == "__main__":
    main(sys.argv[1:] or ["sn", "sr", "llr"])
