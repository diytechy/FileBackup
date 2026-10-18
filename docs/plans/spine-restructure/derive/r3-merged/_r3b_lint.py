# Extra checks for round 3b: dimension grammar, history tokens in rationale,
# references to LLR/IF ids that do not exist, file names in SR cells, curly
# quotes, and the set of rows changed against git HEAD.
import re, subprocess, sys, tomllib
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[4]
REQ = REPO / 'docs' / 'requirements'
TABLES = {'components.toml': 'component', 'interfaces.toml': 'interface',
          'low-level-requirements.toml': 'design', 'system-requirements.toml': 'requirement',
          'external.toml': 'boundary'}


def load_head(name):
    t = subprocess.run(['git', 'show', f'HEAD:docs/requirements/{name}'], cwd=REPO,
                       capture_output=True, check=True).stdout.decode('utf-8')
    return tomllib.loads(t)


new = {n: tomllib.load(open(REQ / n, 'rb')) for n in TABLES}
old = {n: load_head(n) for n in TABLES}
llr = new['low-level-requirements.toml']['design']
ifs = new['interfaces.toml']['interface']
srs = new['system-requirements.toml']['requirement']
problems = []

DIM = re.compile(r'^[a-z_][a-z0-9_]*=(set\{[^{}]+\}|range\[[^\[\]]+\.\.[^\[\]]+\]|bool)$')
for lid, l in llr.items():
    d = l.get('dimensions')
    if d:
        parts = [p.strip() for p in d.split(';')]
        if parts[-1] not in ('@pairwise', '@full', '@boundaries'):
            problems.append(f'{lid}: dimensions end {parts[-1]!r}')
        for p in parts[:-1]:
            if not DIM.match(p):
                problems.append(f'{lid}: dimension {p!r}')
    rat = l.get('rationale', '')
    if re.search(r'\b(20\d\d|OI-\d+|WP\d+|R3[SO]-\d+|K\d\d|P-\d\d|review|ruled|ruling|used to|once made)\b', rat):
        problems.append(f'{lid}: history-like token in rationale')
    for k in ('title', 'detail', 'rationale'):
        txt = l.get(k, '')
        if re.search(r'\bshall\b', txt):
            problems.append(f'{lid}.{k}: shall')
        for ref in re.findall(r'LLR-\d{3}', txt):
            if ref not in llr:
                problems.append(f'{lid}.{k}: dangling {ref}')
        for ref in re.findall(r'IF-\d{3}', txt):
            if ref not in ifs:
                problems.append(f'{lid}.{k}: dangling {ref}')
    if 'parent' in l and 'sr_refs' in l:
        problems.append(f'{lid}: parent and sr_refs')
for iid, i in ifs.items():
    for k in ('data', 'rationale'):
        if re.search(r'\bSR-\d{3}\b|\bLLR-\d{3}\b', re.sub(r'\[SR-075/[a-z-]+\]', '', i.get(k, ''))):
            problems.append(f'{iid}.{k}: names a requirement id')
        for ref in re.findall(r'IF-\d{3}', i.get(k, '')):
            if ref not in ifs:
                problems.append(f'{iid}.{k}: dangling {ref}')

# SR cells: no file names, ids resolve
sn = set(tomllib.load(open(REQ / 'stakeholder-needs.toml', 'rb'))['need'])
ext = tomllib.load(open(REQ / 'external.toml', 'rb'))
bnd = set(ext.get('boundary', {}))
asm = set()
for v in tomllib.load(open(REQ / 'assumptions.toml', 'rb')).values():
    asm |= set(v)
FILEPAT = re.compile(r'\b[\w-]+\.(csv|json|meta|ps1|psm1|sh|cmd|command|bat|txt|log|tsv|html|dll|clixml)\b', re.I)
for sid, s in srs.items():
    for r in s.get('sn_refs', []):
        if r not in sn:
            problems.append(f'{sid}: sn_ref {r}')
    for r in s.get('boundary_refs', []):
        if r not in bnd:
            problems.append(f'{sid}: boundary_ref {r}')
    for r in s.get('da_refs', []):
        if r not in asm:
            problems.append(f'{sid}: da_ref {r}')
    for k, v in s.items():
        if isinstance(v, str) and FILEPAT.search(v):
            problems.append(f'{sid}.{k}: file-like name {FILEPAT.search(v).group(0)!r}')

for n in TABLES:
    raw = (REQ / n).read_text(encoding='utf-8')
    if re.search('[‘’“”]', raw):
        problems.append(f'{n}: curly quote')

print('PROBLEMS', len(problems))
for p in problems:
    print('  P', p)

changed = {}
for n, t in TABLES.items():
    o, w = old[n].get(t, {}), new[n].get(t, {})
    for rid in sorted(set(o) | set(w)):
        if rid not in o:
            changed.setdefault(n, []).append((rid, 'added'))
        elif rid not in w:
            changed.setdefault(n, []).append((rid, 'removed'))
        elif o[rid] != w[rid]:
            keys = sorted(k for k in set(o[rid]) | set(w[rid]) if o[rid].get(k) != w[rid].get(k))
            changed.setdefault(n, []).append((rid, 'changed: ' + ', '.join(keys)))
if '--changed' in sys.argv:
    total = 0
    for n, rows in changed.items():
        print(f'## {n} ({len(rows)})')
        for rid, what in rows:
            print(f'- {rid}: {what}')
        total += len(rows)
    print('TOTAL', total)
