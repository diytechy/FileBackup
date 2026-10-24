"""Structural check of a design tier: components, interfaces and low-level requirements.

usage: py -3.12 -X utf8 validate_design.py [<repo-root>] [--design <dir>] [--pairs <file>]

Part of the architecture-decomposition skill (FileBackup project skill). Reads
<repo-root>/docs/requirements/{system-requirements,external,assumptions,hats}.toml
and the three design files (components.toml, interfaces.toml,
low-level-requirements.toml) from --design (default: the same folder).

Errors (the tier is structurally wrong):
  - an unresolved id: part_of, an interface owner or party, a boundary crossing,
    a bridging assumption, carried_by, an LLR's sr_refs, parent, constrains or hat;
  - an interface row carrying both consumers and requestors;
  - an LLR with neither or both of sr_refs and parent, or a parent cycle;
  - an LLR that constrains an interface but has no dimensions cell;
  - an LLR carrying a module, code_symbol or component cell: rows never bind the
    implementation's structure; placement is derived through the interface an
    LLR constrains, and code points up to the spine later;
  - a status other than Drafted or Approved;
  - an interface nothing constrains, or an SR no LLR reaches, unless the pair or
    the id is listed in --pairs (a free-text file; any line naming the id counts),
    or the SR row itself carries a constrains cell naming the interface.
Warnings: 'shall' in an LLR (the SR states the obligation), and code-like tokens
(file names, PowerShell Verb-Noun names, $variables, calls) in component,
interface or LLR text.
"""
import argparse
import re
import tomllib
from pathlib import Path

ap = argparse.ArgumentParser(description='Structural check of a design tier.')
ap.add_argument('root', nargs='?', default='.', help='repo root (default: current folder)')
ap.add_argument('--design', help='folder holding the three design files (default: <root>/docs/requirements)')
ap.add_argument('--pairs', help='free-text file listing SR-to-interface pairs or known gaps')
args = ap.parse_args()

root = Path(args.root)
req = root / 'docs' / 'requirements'
d = Path(args.design) if args.design else req


def load(path, key=None):
    doc = tomllib.load(open(path, 'rb'))
    return doc[key] if key else doc


cmp_ = load(d / 'components.toml', 'component')
ifs = load(d / 'interfaces.toml', 'interface')
llr = load(d / 'low-level-requirements.toml', 'design')
srs = load(req / 'system-requirements.toml', 'requirement')
ext = load(req / 'external.toml')
asm = load(req / 'assumptions.toml')
hats = load(req / 'hats.toml')
pairs_text = Path(args.pairs).read_text(encoding='utf-8') if args.pairs else ''


def ids_of(doc):
    out = set()
    for v in doc.values():
        if isinstance(v, dict):
            out |= set(v.keys())
    return out


def as_list(v):
    if v is None:
        return []
    return v if isinstance(v, list) else [v]


ext_ids, asm_ids, hat_ids = ids_of(ext), ids_of(asm), ids_of(hats)
STATUSES = {'Drafted', 'Approved'}
errs, warns = [], []


def party_ok(p):
    if p.startswith('external:'):
        return p[len('external:'):] in ext_ids
    return p in cmp_


for cid, c in cmp_.items():
    if c.get('part_of') and c['part_of'] not in cmp_:
        errs.append(f"{cid}: part_of {c['part_of']} unresolved")
    if c.get('status') not in STATUSES:
        errs.append(f"{cid}: status {c.get('status')}")

for iid, i in ifs.items():
    if not party_ok(i.get('owner', '')):
        errs.append(f"{iid}: owner {i.get('owner')} unresolved")
    if 'consumers' in i and 'requestors' in i:
        errs.append(f'{iid}: both consumers and requestors')
    for p in as_list(i.get('consumers')) + as_list(i.get('requestors')):
        if not party_ok(p):
            errs.append(f'{iid}: party {p} unresolved')
    for k in ('interface_from_external', 'interface_to_external'):
        for b in as_list(i.get(k)):
            if b not in ext_ids:
                errs.append(f'{iid}: {k} {b} unresolved')
    for b in as_list(i.get('bridged_by')):
        if b not in asm_ids:
            errs.append(f'{iid}: bridged_by {b} unresolved')
    for cb in as_list(i.get('carried_by')):
        if cb not in ifs:
            errs.append(f'{iid}: carried_by {cb} unresolved')
    if i.get('status') not in STATUSES:
        errs.append(f"{iid}: status {i.get('status')}")

for lid, l in llr.items():
    has_sr, has_par = 'sr_refs' in l, 'parent' in l
    if has_sr == has_par:
        errs.append(f'{lid}: needs exactly one of sr_refs / parent')
    for s in as_list(l.get('sr_refs')):
        if s not in srs:
            errs.append(f'{lid}: sr_ref {s} unresolved')
    if has_par and l['parent'] not in llr:
        errs.append(f"{lid}: parent {l['parent']} unresolved")
    for c in as_list(l.get('constrains')):
        if c not in ifs:
            errs.append(f'{lid}: constrains {c} unresolved')
    if l.get('constrains') and not l.get('dimensions'):
        errs.append(f'{lid}: constrains an IF but has no dimensions')
    for h in as_list(l.get('hat_refs')):
        if h not in hat_ids:
            errs.append(f'{lid}: hat {h} unresolved')
    if l.get('status') not in STATUSES:
        errs.append(f"{lid}: status {l.get('status')}")
    for k in ('module', 'code_symbol', 'component'):
        if k in l:
            errs.append(f'{lid}: forbidden cell {k} (rows never bind the implementation)')
    txt = ' '.join(str(l.get(k, '')) for k in ('title', 'detail'))
    if re.search(r'\bshall\b', txt):
        warns.append(f"{lid}: 'shall' in text")

for lid in llr:
    seen, cur = set(), lid
    while 'parent' in llr.get(cur, {}):
        if cur in seen:
            errs.append(f'{lid}: parent cycle')
            break
        seen.add(cur)
        cur = llr[cur]['parent']


def top_srs(lid):
    cur = lid
    while 'parent' in llr[cur]:
        cur = llr[cur]['parent']
    return as_list(llr[cur].get('sr_refs'))


reached = set()
for lid in llr:
    reached |= set(top_srs(lid))
constrained = {c for l in llr.values() for c in as_list(l.get('constrains'))}
constrained |= {c for s in srs.values() for c in as_list(s.get('constrains'))}
for iid in ifs:
    if iid not in constrained and iid not in pairs_text:
        errs.append(f'{iid}: constrained by no LLR or SR, and not listed in --pairs')
for s in srs:
    if s not in reached and s not in pairs_text:
        errs.append(f'{s}: reaches no LLR, and not listed in --pairs')
unreached = sorted(s for s in srs if s not in reached)

code_pat = re.compile(
    r"(\b[\w-]+\.(?:ps1|psm1|psd1|sh|py|cmd|bat|json|clixml|xml)\b"
    r"|\b(?:Get|Set|New|Remove|Invoke|Test|Start|Stop|Enter|Exit|Complete|Initialize|Optimize|Write|Read|Resolve|Update|Copy|Move|Add|Find|Format|Import|Export|ConvertTo|ConvertFrom|Assert|Register|Use|Save|Restore|Compare|Measure|Select|Wait)-[A-Z]\w+"
    r"|\$[A-Za-z_]\w*|\b\w+\(\))"
)
for kind, rows, keys in (
    ('CMP', cmp_, ('name', 'notes')),
    ('IF', ifs, ('data', 'rationale', 'channel')),
    ('LLR', llr, ('title', 'detail', 'rationale', 'dimensions')),
):
    for rid, r in rows.items():
        for k in keys:
            for m in code_pat.findall(str(r.get(k, ''))):
                warns.append(f'{kind} {rid}.{k}: code-like token {m!r}')

tops = sum(1 for l in llr.values() if 'sr_refs' in l)
bnd = sum(1 for i in ifs.values() if i.get('interface_from_external') or i.get('interface_to_external'))
print(f'components={len(cmp_)} interfaces={len(ifs)} (boundary={bnd}, internal={len(ifs) - bnd}) '
      f'llr={len(llr)} (top={tops}, child={len(llr) - tops})')
print(f'SRs reaching no LLR: {len(unreached)} {unreached}')
print(f'ERRORS {len(errs)}')
for e in errs:
    print('  E', e)
print(f'WARNINGS {len(warns)}')
for w in warns:
    print('  W', w)
