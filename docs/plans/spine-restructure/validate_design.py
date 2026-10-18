"""Structural check of a design tier (components / interfaces / LLRs) per the r3 brief.

usage: python validate_design.py <dir-with-the-three-toml> [<repo-root>]
"""
import re
import sys
import tomllib
from pathlib import Path

d = Path(sys.argv[1])
root = Path(sys.argv[2] if len(sys.argv) > 2 else r"C:\Projects\FileBackup")
req = root / "docs" / "requirements"

cmp_ = tomllib.load(open(d / "components.toml", "rb"))["component"]
ifs = tomllib.load(open(d / "interfaces.toml", "rb"))["interface"]
llr = tomllib.load(open(d / "low-level-requirements.toml", "rb"))["design"]
srs = tomllib.load(open(req / "system-requirements.toml", "rb"))["requirement"]
ext = tomllib.load(open(req / "external.toml", "rb"))
asm = tomllib.load(open(req / "assumptions.toml", "rb"))
hats = tomllib.load(open(req / "hats.toml", "rb"))


def ids_of(doc):
    out = set()
    for v in doc.values():
        if isinstance(v, dict):
            out |= set(v.keys())
    return out


ext_ids = ids_of(ext)
asm_ids = ids_of(asm)
hat_ids = ids_of(hats)
errs, warns = [], []


def as_list(v):
    if v is None:
        return []
    return v if isinstance(v, list) else [v]


def party_ok(p):
    if p.startswith("external:"):
        return p[len("external:"):] in ext_ids
    return p in cmp_


for cid, c in cmp_.items():
    if c.get("part_of") and c["part_of"] not in cmp_:
        errs.append(f"{cid}: part_of {c['part_of']} unresolved")
    if c.get("status") != "Drafted":
        errs.append(f"{cid}: status {c.get('status')}")

for iid, i in ifs.items():
    if not party_ok(i.get("owner", "")):
        errs.append(f"{iid}: owner {i.get('owner')} unresolved")
    if "consumers" in i and "requestors" in i:
        errs.append(f"{iid}: both consumers and requestors")
    for p in as_list(i.get("consumers")) + as_list(i.get("requestors")):
        if not party_ok(p):
            errs.append(f"{iid}: party {p} unresolved")
    for k in ("interface_from_external", "interface_to_external"):
        for b in as_list(i.get(k)):
            if b not in ext_ids:
                errs.append(f"{iid}: {k} {b} unresolved")
    for b in as_list(i.get("bridged_by")):
        if b not in asm_ids:
            errs.append(f"{iid}: bridged_by {b} unresolved")
    for cb in as_list(i.get("carried_by")):
        if cb not in ifs:
            errs.append(f"{iid}: carried_by {cb} unresolved")
    if i.get("status") != "Drafted":
        errs.append(f"{iid}: status {i.get('status')}")

for lid, l in llr.items():
    has_sr, has_par = "sr_refs" in l, "parent" in l
    if has_sr == has_par:
        errs.append(f"{lid}: needs exactly one of sr_refs / parent")
    for s in as_list(l.get("sr_refs")):
        if s not in srs:
            errs.append(f"{lid}: sr_ref {s} unresolved")
    if has_par and l["parent"] not in llr:
        errs.append(f"{lid}: parent {l['parent']} unresolved")
    for c in as_list(l.get("constrains")):
        if c not in ifs:
            errs.append(f"{lid}: constrains {c} unresolved")
    if l.get("constrains") and not l.get("dimensions"):
        errs.append(f"{lid}: constrains an IF but has no dimensions")
    for h in as_list(l.get("hat_refs")):
        if h not in hat_ids:
            errs.append(f"{lid}: hat {h} unresolved")
    if l.get("status") != "Drafted":
        errs.append(f"{lid}: status {l.get('status')}")
    for k in ("module", "code_symbol", "component"):
        if k in l:
            errs.append(f"{lid}: forbidden cell {k}")
    txt = " ".join(str(l.get(k, "")) for k in ("title", "detail"))
    if re.search(r"\bshall\b", txt):
        warns.append(f"{lid}: 'shall' in text")

# acyclic parents
for lid in llr:
    seen, cur = set(), lid
    while "parent" in llr.get(cur, {}):
        if cur in seen:
            errs.append(f"{lid}: parent cycle")
            break
        seen.add(cur)
        cur = llr[cur]["parent"]


def top_srs(lid):
    cur = lid
    while "parent" in llr[cur]:
        cur = llr[cur]["parent"]
    return as_list(llr[cur].get("sr_refs"))


reached = set()
for lid in llr:
    reached |= set(top_srs(lid))
constrained = {c for l in llr.values() for c in as_list(l.get("constrains"))}
gaps = (d / "design-gaps.md").read_text(encoding="utf-8") if (d / "design-gaps.md").exists() else ""
for iid in ifs:
    if iid not in constrained and iid not in gaps:
        errs.append(f"{iid}: constrained by no LLR and not in design-gaps.md")
for s in srs:
    if s not in reached and s not in gaps:
        errs.append(f"{s}: reaches no LLR and not in design-gaps.md")
unreached = sorted(s for s in srs if s not in reached)

# code-token sweep: file names, cmdlet Verb-Noun, function-call shapes, $vars
code_pat = re.compile(
    r"(\b[\w-]+\.(?:ps1|psm1|psd1|sh|py|cmd|bat|json|clixml|xml)\b"
    r"|\b(?:Get|Set|New|Remove|Invoke|Test|Start|Stop|Enter|Exit|Complete|Initialize|Optimize|Write|Read|Resolve|Update|Copy|Move|Add|Find|Format|Import|Export|ConvertTo|ConvertFrom|Assert|Register|Use|Save|Restore|Compare|Measure|Select|Wait)-[A-Z]\w+"
    r"|\$[A-Za-z_]\w*|\b\w+\(\))"
)
for kind, rows, keys in (
    ("CMP", cmp_, ("name", "notes")),
    ("IF", ifs, ("data", "rationale", "channel")),
    ("LLR", llr, ("title", "detail", "rationale", "dimensions")),
):
    for rid, r in rows.items():
        for k in keys:
            for m in code_pat.findall(str(r.get(k, ""))):
                warns.append(f"{kind} {rid}.{k}: code-like token {m!r}")

tops = sum(1 for l in llr.values() if "sr_refs" in l)
bnd = sum(1 for i in ifs.values() if i.get("interface_from_external") or i.get("interface_to_external"))
print(f"components={len(cmp_)} interfaces={len(ifs)} (boundary={bnd}, internal={len(ifs)-bnd}) "
      f"llr={len(llr)} (top={tops}, child={len(llr)-tops}) legacy_kept={sum(1 for x in llr if int(x[4:]) <= 94)}")
print(f"SRs reaching no LLR: {len(unreached)} {unreached}")
print(f"ERRORS {len(errs)}")
for e in errs:
    print("  E", e)
print(f"WARNINGS {len(warns)}")
for w in warns:
    print("  W", w)
