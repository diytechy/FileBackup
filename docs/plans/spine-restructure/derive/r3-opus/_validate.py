"""Validate the round-3 Opus derivation (run from anywhere with python)."""
import csv
import os
import re
import sys
import tomllib

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..', '..', '..', '..'))
REQ = os.path.join(REPO, 'docs', 'requirements')

problems = []
warnings = []


def load(path):
    with open(path, 'rb') as fh:
        return tomllib.load(fh)


# 1. parse
files = {}
for name in ('components.toml', 'interfaces.toml', 'low-level-requirements.toml'):
    try:
        files[name] = load(os.path.join(HERE, name))
        print(f'PARSE OK  {name}')
    except Exception as exc:  # noqa: BLE001
        print(f'PARSE FAIL {name}: {exc}')
        sys.exit(1)

cmps = files['components.toml']['component']
ifs = files['interfaces.toml']['interface']
llrs = files['low-level-requirements.toml']['design']

srs = load(os.path.join(REQ, 'system-requirements.toml'))['requirement']
ext = load(os.path.join(REQ, 'external.toml'))
ents = set(ext.get('entity', {}))
bnds = set(ext.get('boundary', {}))
das = set(load(os.path.join(REQ, 'assumptions.toml')).get('assumption', {}))
hats = set(load(os.path.join(REQ, 'hats.toml')).get('hat', {}))


def ref_ok(v, kinds):
    if v.startswith('external:'):
        return 'ext' in kinds and v[len('external:'):] in ents
    return 'cmp' in kinds and v in cmps


def as_list(v):
    return v if isinstance(v, list) else [v]


# 2. resolution
for cid, c in cmps.items():
    if 'part_of' in c and c['part_of'] not in cmps:
        problems.append(f'{cid}: part_of {c["part_of"]} unresolved')
    if c.get('status') != 'Drafted':
        problems.append(f'{cid}: status not Drafted')
    if c.get('category') != 'software':
        problems.append(f'{cid}: category not software')
roots = [c for c, v in cmps.items() if 'part_of' not in v]
if len(roots) != 1:
    problems.append(f'component roots: {roots}')
# part_of acyclic
for cid in cmps:
    seen, cur = set(), cid
    while cur in cmps and 'part_of' in cmps[cur]:
        if cur in seen:
            problems.append(f'{cid}: part_of cycle')
            break
        seen.add(cur)
        cur = cmps[cur]['part_of']

for iid, i in ifs.items():
    if not ref_ok(i['owner'], {'cmp', 'ext'}):
        problems.append(f'{iid}: owner {i["owner"]} unresolved')
    has_c, has_r = 'consumers' in i, 'requestors' in i
    if has_c == has_r:
        problems.append(f'{iid}: needs exactly one of consumers/requestors')
    for v in i.get('consumers', []) + i.get('requestors', []):
        if not ref_ok(v, {'cmp', 'ext'}):
            problems.append(f'{iid}: side {v} unresolved')
    boundary = False
    for key in ('interface_from_external', 'interface_to_external'):
        for b in as_list(i.get(key, [])):
            boundary = True
            if b not in bnds:
                problems.append(f'{iid}: {key} {b} unresolved')
    for d in i.get('bridged_by', []):
        if d not in das:
            problems.append(f'{iid}: bridged_by {d} unresolved')
    if boundary and not (i.get('bridged_by') or i.get('coincident')):
        problems.append(f'{iid}: boundary interface without bridged_by or coincident')
    if (i.get('bridged_by') or i.get('coincident')) and not boundary:
        problems.append(f'{iid}: bridged_by/coincident on an internal interface')
    for cb in as_list(i.get('carried_by', [])):
        if cb not in ifs:
            problems.append(f'{iid}: carried_by {cb} unresolved')
    for k in ('channel', 'data', 'rationale', 'version'):
        if not i.get(k):
            problems.append(f'{iid}: missing {k}')
    if i.get('status') != 'Drafted':
        problems.append(f'{iid}: status not Drafted')

DIM_TERM = re.compile(r'^(@pairwise|@full|[a-z_]+=(set\{[^{}]+\}|range\[[^\[\]]+\.\.[^\[\]]+\]|bool))$')
for lid, l in llrs.items():
    has_s, has_p = 'sr_refs' in l, 'parent' in l
    if has_s and has_p:
        problems.append(f'{lid}: both sr_refs and parent')
    if not has_s and not has_p:
        problems.append(f'{lid}: neither sr_refs nor parent')
    for s in l.get('sr_refs', []):
        if s not in srs:
            problems.append(f'{lid}: sr_ref {s} unresolved')
    if has_p and l['parent'] not in llrs:
        problems.append(f'{lid}: parent {l["parent"]} unresolved')
    if 'constrains' in l:
        if l['constrains'] not in ifs:
            problems.append(f'{lid}: constrains {l["constrains"]} unresolved')
        if not l.get('dimensions'):
            problems.append(f'{lid}: constrains an interface but has no dimensions')
    if l.get('dimensions'):
        for term in [t.strip() for t in l['dimensions'].split(';')]:
            if not DIM_TERM.match(term):
                problems.append(f'{lid}: bad dimensions term {term!r}')
    for h in l.get('hat_refs', []):
        if h not in hats:
            problems.append(f'{lid}: hat {h} unresolved')
    for k in ('title', 'detail', 'rationale'):
        if not l.get(k):
            problems.append(f'{lid}: missing {k}')
    for k in ('module', 'code_symbol', 'component', 'shall'):
        if k in l:
            problems.append(f'{lid}: forbidden key {k}')
    if re.search(r'\bshall\b', l.get('detail', '') + l.get('title', ''), re.I):
        problems.append(f'{lid}: uses "shall"')
    if l.get('status') != 'Drafted':
        problems.append(f'{lid}: status not Drafted')

# 3. parent acyclic, and derived SR of children
def top_of(lid):
    seen = set()
    cur = lid
    while 'parent' in llrs[cur]:
        if cur in seen:
            return None
        seen.add(cur)
        cur = llrs[cur]['parent']
        if cur not in llrs:
            return None
    return cur

for lid in llrs:
    if top_of(lid) is None:
        problems.append(f'{lid}: parent chain cyclic or broken')

# hat_refs only where the effective parent SRs do not already carry the hat
for lid, l in llrs.items():
    top = top_of(lid)
    if top is None:
        continue
    parent_hats = set()
    for s in llrs[top].get('sr_refs', []):
        parent_hats |= set(srs[s].get('hat_refs', []))
    for h in l.get('hat_refs', []):
        if h in parent_hats:
            problems.append(f'{lid}: hat {h} already carried by a parent SR')

# 4/5. coverage, against design-gaps.md
gaps = open(os.path.join(HERE, 'design-gaps.md'), encoding='utf-8').read()
sec4 = gaps.split('## 4. SR constrains', 1)[1] if '## 4. SR constrains' in gaps else ''
sr_constrains = re.findall(r'^- (SR-\d{3}) -> (IF-\d{3})', sec4, re.M)
for s, i in sr_constrains:
    if s not in srs or i not in ifs:
        problems.append(f'SR constrains pair {s} -> {i} unresolved')
sec3 = gaps.split('## 3. SRs that reach no LLR', 1)[1].split('## 4.', 1)[0]
sr_listed_uncovered = set(re.findall(r'^- (SR-\d{3})', sec3, re.M))

constrained = {l['constrains'] for l in llrs.values() if 'constrains' in l}
for iid in ifs:
    if iid not in constrained and iid not in {i for _, i in sr_constrains}:
        problems.append(f'{iid}: constrained by no LLR and not under "SR constrains"')

reached = set()
for l in llrs.values():
    reached |= set(l.get('sr_refs', []))
for s in srs:
    if s not in reached and s not in sr_listed_uncovered:
        problems.append(f'{s}: reaches no LLR and is not listed in design-gaps')

# 6. code-token scan
legacy = list(csv.DictReader(open(os.path.join(REQ, 'low-level-requirements.csv'), encoding='utf-8', errors='replace')))
tokens = set()
for row in legacy:
    for cell in (row['CodeSymbol'], row['Module']):
        for t in re.split(r'[;,/ ]+', cell):
            t = t.strip()
            if len(t) > 3 and t not in ('bash', 'container', 'marker'):
                tokens.add(t)
FILE_RX = re.compile(r'\b[\w.-]+\.(?:ps1|psm1|psd1|sh|py|cs|dll|bat)\b', re.I)
VERB_RX = re.compile(r'\b(?:Get|Set|New|Test|Invoke|Remove|Write|Read|Resolve|Assert|Update|Compare|Initialize|Move|Save|Complete|Copy|Publish|Measure|Enter|Exit|Start|Stop|Format|Convert|ConvertTo|ConvertFrom|Expand|Compress|Import|Export|Optimize|Clear|Select|Wait|Restore|Find|Send|Add)-[A-Z]\w+')
VAR_RX = re.compile(r'\$[A-Za-z_]\w*')
SNAKE_FN = re.compile(r'\b[a-z]+(?:_[a-z]+)+\b')
ALLOWED_SNAKE = set()  # dimension names live only in the dimensions cell, which is not scanned for prose
FORM_WORDS = ['MANIFEST.csv', 'DIRECTORIES.csv', 'LINKS.csv', 'Snapshot_', 'Temp.lock', 'RUN.inprogress',
              'PRUNE.inprogress', 'FileBackupState', 'RECONSTRUCT.paths', 'FILEBACKUP_', 'ConfigVersion',
              'BackupSets', 'CompressEnabled', 'CompressProbe', 'HashRecalcFreq', 'SourceStatePath',
              'AllowEmptySource', 'BrowseView', 'ViewPath', 'SpaceView', 'SevenZipPath', 'FfprobePath',
              'xxH2Hash', 'DataPath', 'RelativePath', 'StoredAsHashSize', 'backup.log', 'RECONSTRUCT.log',
              '-ExitCode', '-WhatIf', '-NoMail', '-NonInteractive', '-Action', '-RepairStorage', '-RefreshKits',
              '-RequireWitness', '-Deep', 'Pester', 'PowerShell 7', 'bats']


IF_FORM_ALLOW = {'RECONSTRUCT.bat', 'KitRevision'}  # launcher and kit-marker names that ARE layout form


def scan(kind, rid, text, prose_only_llr=False):
    for m in FILE_RX.findall(text):
        if kind == 'IF' and m in IF_FORM_ALLOW:
            continue
        problems.append(f'{kind} {rid}: names a code file {m!r}')
    for m in VERB_RX.findall(text):
        problems.append(f'{kind} {rid}: names a function/cmdlet {m!r}')
    for m in VAR_RX.findall(text):
        problems.append(f'{kind} {rid}: names a variable {m!r}')
    for t in tokens:
        if kind == 'IF' and t in IF_FORM_ALLOW:
            continue
        if re.search(r'(?<![\w-])' + re.escape(t) + r'(?![\w-])', text):
            problems.append(f'{kind} {rid}: names legacy code token {t!r}')
    for m in SNAKE_FN.findall(text):
        if m not in ALLOWED_SNAKE:
            problems.append(f'{kind} {rid}: snake_case identifier {m!r}')
    if prose_only_llr:
        for w in FORM_WORDS:
            if w in text:
                warnings.append(f'LLR {rid}: carries interface-form word {w!r} (form belongs on the IF)')


for cid, c in cmps.items():
    scan('CMP', cid, c['name'] + '\n' + c['notes'])
for iid, i in ifs.items():
    scan('IF', iid, '\n'.join(str(i.get(k, '')) for k in ('title', 'channel', 'data', 'rationale', 'coincident')))
for lid, l in llrs.items():
    scan('LLR', lid, '\n'.join(l.get(k, '') for k in ('title', 'detail', 'rationale')), prose_only_llr=True)

# rationale carries no history
HIST = re.compile(r'\b(?:19|20)\d{2}-\d{2}-\d{2}\b|\bWP\d+\b|\bOI-\d+\b|\bD-\d{3}\b|\breview(?:ed|er)?\b|\bdefect\b', re.I)
for kind, rows, keys in (('CMP', cmps, ('notes',)), ('IF', ifs, ('rationale', 'data')), ('LLR', llrs, ('rationale', 'detail'))):
    for rid, r in rows.items():
        for k in keys:
            for m in HIST.findall(r.get(k, '')):
                problems.append(f'{kind} {rid}: {k} carries history token {m!r}')

# 7. mapping covers every legacy row
mapping = open(os.path.join(HERE, 'mapping.md'), encoding='utf-8').read()
import json
strip = json.load(open(os.path.join(REPO, 'docs', 'plans', 'spine-restructure', 'strip', 'final', 'llr.json'), encoding='utf-8'))
for x in strip:
    if not re.search(r'^\| ' + re.escape(x['id']) + r' \|', mapping, re.M):
        problems.append(f'mapping.md: no line for {x["id"]}')
for m in re.findall(r'\b(LLR-\d{3})\b', mapping):
    n = int(m[4:])
    if n >= 95 and m not in llrs:
        problems.append(f'mapping.md: names {m}, which does not exist')

# 8. kept legacy ids are not retired ids
retired = {x['id'] for x in strip if x['verdict'] == 'retire'}
for lid in llrs:
    if lid in retired:
        problems.append(f'{lid}: reuses a retired id')
legacy_ids = {row['LLR-ID'] for row in legacy} | {x['id'] for x in strip}
for lid in llrs:
    n = int(lid[4:])
    if n < 95 and lid not in legacy_ids:
        problems.append(f'{lid}: below LLR-095 but not a legacy id')

# counts
boundary_ifs = [i for i, v in ifs.items() if v.get('interface_from_external') or v.get('interface_to_external')]
top = [l for l, v in llrs.items() if 'sr_refs' in v]
child = [l for l, v in llrs.items() if 'parent' in v]
kept = sorted(l for l in llrs if int(l[4:]) < 95)
gap_rows = re.findall(r'^\| G-\d+ \|', gaps, re.M)

print()
print(f'components: {len(cmps)}')
print(f'interfaces: {len(ifs)} (boundary {len(boundary_ifs)}, internal {len(ifs) - len(boundary_ifs)})')
print(f'LLRs: {len(llrs)} (top-level {len(top)}, child {len(child)})')
print(f'legacy LLR ids kept: {len(kept)}')
print(f'new LLR ids minted: {len(llrs) - len(kept)}')
print(f'design gaps: {len(gap_rows)}')
print(f'SRs reached by an LLR: {len(reached & set(srs))}/{len(srs)}')
print(f'interfaces constrained by an LLR: {len(constrained & set(ifs))}/{len(ifs)}')
print(f'SR constrains pairs listed: {len(sr_constrains)}')
print()
for w in warnings:
    print('WARN ', w)
print()
if problems:
    for p in problems:
        print('FAIL ', p)
    print(f'\n{len(problems)} problem(s)')
    sys.exit(1)
print('VALIDATION PASSED: 0 problems')
