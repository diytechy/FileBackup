"""Harvest the legacy spine before the restructure rewrites it.

Reads the SN table, the SR/LLR/TC registries and the test tree, and writes
one JSON file per tier under harvest/ beside this script, plus the
TC-to-test link table. Every row keeps its cells verbatim. The script adds
mechanical extractions alongside them (normalised id lists, provenance
fragments, input-space sets, thresholds, negative-control and mutation notes,
and test links) so a later reader can find what a row knew without the
original cell.

Stdlib only. Run from anywhere:

    python docs/plans/spine-restructure/harvest.py
"""

from __future__ import annotations

import csv
import json
import re
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
REQ = ROOT / "docs" / "requirements"
OUT = HERE / "harvest"

ID_RE = re.compile(r"\b(SN|SR|LLR|TC|IF)-\d{3}\b")
PROVENANCE_RE = re.compile(
    r"[^.;]*\b(?:AMENDED|REWORDED|MINTED|RETIRED|Added|Renamed|ruled|ruling|"
    r"finding|regression|WP\d+|OI-\d+|WI-\d+|D-\d+|M-\d+|rev\d+|kit-bump|"
    r"20\d\d-\d\d-\d\d)\b[^.;]*[.;]?",
    re.IGNORECASE,
)
SPACE_RE = re.compile(r"\b\w+=(?:set\{[^}]*\}|range\[[^\]]*\]|bool)|@(?:full|pairwise|boundaries)")
THRESHOLD_RE = re.compile(
    r"[^.;]*(?:<=|>=|≤|≥|<|>|\bat (?:most|least)\b|\bwithin\b|\bunder\b)\s*~?\d[\d.,]*\s*"
    r"(?:%|ms|s\b|sec|min|GB|GiB|MB|MiB|KB|x\b|files|rows|bytes)?[^.;]*[.;]?",
    re.IGNORECASE,
)
CONTROL_RE = re.compile(
    r"[^.]*\b(?:NEGATIVE CONTROL|MUTATION[- ]CHECKED|mutation check|vacuous|"
    r"could not fail|cannot fail|would pass)\b[^.]*\.?",
    re.IGNORECASE,
)


def split_ids(cell: str) -> list[str]:
    """Ids from a refs cell, whichever separator the row used (';' or ', ')."""
    return [m.group(0) for m in ID_RE.finditer(cell)]


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def read_needs(path: Path) -> list[dict[str, str]]:
    """The SN markdown file holds two tables with different columns."""
    rows: list[dict[str, str]] = []
    header: list[str] | None = None
    section = ""
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("## "):
            section = line[3:].strip()
            header = None
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if cells[0] == "SN-ID":
            header = cells
        elif header and re.fullmatch(r"SN-\d{3}", cells[0]):
            row = dict(zip(header, cells))
            row["_section"] = section
            rows.append(row)
    return rows


def extract(text: str) -> dict[str, list[str]]:
    found = {
        "provenance": [m.group(0).strip() for m in PROVENANCE_RE.finditer(text)],
        "input_spaces": [m.group(0) for m in SPACE_RE.finditer(text)],
        "thresholds": [m.group(0).strip() for m in THRESHOLD_RE.finditer(text)],
        "controls": [m.group(0).strip() for m in CONTROL_RE.finditer(text)],
    }
    return {k: v for k, v in found.items() if v}


def test_links() -> dict[str, list[dict[str, str]]]:
    """Every line under tests/ naming a TC id, with the nearest block title."""
    title_re = re.compile(r"^\s*(?:It|Describe|Context)\s+['\"](.*?)['\"]|^\s*@test\s+['\"](.*?)['\"]")
    links: dict[str, list[dict[str, str]]] = defaultdict(list)
    for path in sorted((ROOT / "tests").rglob("*")):
        if path.suffix not in {".ps1", ".bats", ".sh"} or not path.is_file():
            continue
        title = ""
        for n, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            m = title_re.match(line)
            if m:
                title = m.group(1) or m.group(2) or ""
            for tc in re.findall(r"\bTC-\d{3}\b", line):
                kind = "title" if m else ("comment" if line.lstrip().startswith("#") else "code")
                links[tc].append({
                    "file": path.relative_to(ROOT).as_posix(),
                    "line": str(n),
                    "kind": kind,
                    "block": title,
                })
    return links


def main() -> None:
    OUT.mkdir(exist_ok=True)
    tiers = {
        "sn": (read_needs(REQ / "stakeholder-needs.md"), "SN-ID", []),
        "sr": (read_csv(REQ / "system-requirements.csv"), "SR-ID", ["SN-Refs"]),
        "llr": (read_csv(REQ / "low-level-requirements.csv"), "LLR-ID", ["SR-Refs", "TestRefs"]),
        "tc": (read_csv(ROOT / "docs" / "test" / "test-cases.csv"), "TC-ID", ["Verifies"]),
    }
    links = test_links()
    for name, (rows, key, ref_cols) in tiers.items():
        out = []
        for row in rows:
            rid = row[key]
            text = " ".join(v for k, v in row.items() if not k.startswith("_") and v)
            entry = {"id": rid, "cells": row}
            entry["refs"] = {c: split_ids(row.get(c, "")) for c in ref_cols}
            entry.update(extract(text))
            if name == "tc":
                entry["test_links"] = links.get(rid, [])
            out.append(entry)
        (OUT / f"{name}.json").write_text(json.dumps(out, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"{name}: {len(out)} rows")
    with (OUT / "tc-test-links.csv").open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["TC-ID", "file", "line", "kind", "block"])
        for tc in sorted(links):
            for link in links[tc]:
                w.writerow([tc, link["file"], link["line"], link["kind"], link["block"]])
    print(f"tc links: {sum(len(v) for v in links.values())} lines over {len(links)} TC ids")


if __name__ == "__main__":
    main()
