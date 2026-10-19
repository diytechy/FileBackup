"""Advisory checks over the design layer and the runtime flows (stdlib only).

usage: python check_design_layer.py [<repo-root>] [--n2]

A prototype of the checks the architecture research recommends for ai-template
(docs/plans/spine-restructure/architecture-breakdown-research.md, recommendations
2, 3 and 6, and section 6's entry criteria 1 to 4):

  1. leaf components with no row placed on them;
  2. interfaces with no consumer, an external interface with no local endpoint,
     or an interface no LLR or SR constrains;
  3. flows against the registries: a message between two components (not parent
     and child) with no interface between them, and each LLR cited on a lifeline
     compared with where the registry places it (A: placed at the root through an
     external interface, B: unplaced, C: placed on another component);
  4. every SR rendered by a flow (directly or through its LLRs) or declared
     flow-free in the flows document;
  5. every id the flows cite exists.

Placement follows the ruled model: an LLR is placed on the owner of the interface
it constrains; an external owner resolves to the root. A message is credited to
the component doing the work: the receiver of a request, the sender of a reply,
a self-message's component, and the sender of a write to the store format.
Everything here is advisory: it reports, it never fails a build.
"""
import collections
import re
import sys
import tomllib
from pathlib import Path

root = Path(sys.argv[1]) if len(sys.argv) > 1 and not sys.argv[1].startswith('--') else Path('.')
R = root / 'docs' / 'requirements'


def load(name, key):
    return tomllib.load(open(R / f'{name}.toml', 'rb'))[key]


sr = load('system-requirements', 'requirement')
llr = load('low-level-requirements', 'design')
cmp_ = load('components', 'component')
ifs = load('interfaces', 'interface')
das = load('assumptions', 'assumption')
flows = (root / 'docs' / 'runtime-flows.md').read_text(encoding='utf-8')

kids = collections.defaultdict(list)
for k, v in cmp_.items():
    if v.get('part_of'):
        kids[v['part_of']].append(k)
leaves = [k for k in cmp_ if not kids[k]]


def chain(c):
    out = [c]
    while cmp_.get(c, {}).get('part_of'):
        c = cmp_[c]['part_of']
        out.append(c)
    return out


def place(k):
    c = llr[k].get('constrains')
    if not c:
        return None
    o = ifs[c].get('owner', '')
    return o if o.startswith('CMP') else 'ROOT'


def subtree(k):
    out = {k}
    for c, v in llr.items():
        if v.get('parent') == k:
            out |= subtree(c)
    return out


sr_rows = collections.defaultdict(set)
for k, v in llr.items():
    if not v.get('parent'):
        for s in v.get('sr_refs', []):
            sr_rows[s] |= subtree(k)

findings = 0


def report(title, lines):
    global findings
    print(f'== {title}: {len(lines)}')
    for line in lines:
        print('   ' + line)
    findings += len(lines)


# 1. leaves with nothing placed
placed = collections.Counter(p for k in llr if (p := place(k)) and p != 'ROOT')
report('leaf components with no row placed on them',
       [f"{k} {cmp_[k]['name']}" for k in leaves if not placed[k]])

# 2. interface consistency
lines = []
for k, v in ifs.items():
    owner = v.get('owner', '')
    users = v.get('consumers', []) + v.get('requestors', [])
    if not users:
        lines.append(f'{k} {v["title"]}: no consumer or requestor')
    if owner.startswith('external') and not any(u.startswith('CMP') for u in users):
        lines.append(f'{k} {v["title"]}: external interface with no local endpoint')
    if not any(lv.get('constrains') == k for lv in llr.values()) and \
            not any(k in str(sv.get('constrains', '')) for sv in sr.values()):
        lines.append(f'{k} {v["title"]}: constrained by no LLR or SR')
report('interface consistency', lines)

# 3. flows against the registries
pairs = collections.defaultdict(set)
for k, v in ifs.items():
    for u in v.get('consumers', []) + v.get('requestors', []):
        pairs[frozenset((v.get('owner', ''), u))].add(k)
no_if = collections.defaultdict(set)
groups = collections.defaultdict(set)
for block in re.findall(r'```mermaid\n(.*?)```', flows, re.S):
    if not block.startswith('sequenceDiagram'):
        continue
    parts = dict(re.findall(r'participant (\w+) as [^(\n]*\(([^)]*)\)', block))
    for line in block.splitlines():
        m = re.match(r'\s*(\w+)(-+>>)(\w+):(.*)', line)
        if not m:
            continue
        a, arrow, b, text = m.groups()
        ca = re.findall(r'CMP-\d{3}', parts.get(a, ''))
        cb = re.findall(r'CMP-\d{3}', parts.get(b, ''))
        if a != b and len(ca) == 1 and len(cb) == 1:
            x, y = ca[0], cb[0]
            if x not in chain(y) and y not in chain(x) and \
                    not any(pairs.get(frozenset((p, q))) for p in chain(x) for q in chain(y)):
                no_if[(x, y)].add(text.strip()[:70])
        if arrow == '-->>' or a == b or b not in parts or 'CMP-016' in parts.get(b, ''):
            perf = a
        else:
            perf = b
        pc = re.findall(r'CMP-\d{3}', parts.get(perf, ''))
        if len(pc) != 1:
            continue
        c = pc[0]
        for l in re.findall(r'LLR-\d{3}', text):
            p = place(l)
            if p == c or (p and p != 'ROOT' and (p in chain(c) or c in chain(p))):
                continue
            g = 'A at the root via an external interface' if p == 'ROOT' else \
                'B unplaced' if p is None else 'C placed on another component'
            groups[g].add(f'{l} on {c}, placed {p}')
report('messages between components with no interface between them',
       [f"{x} -> {y}: {'; '.join(sorted(t))}" for (x, y), t in sorted(no_if.items())])
for g in sorted(groups):
    report(f'flow lifeline vs placement, {g}', sorted(groups[g]))

# 4. scenario coverage
cited = set(re.findall(r'\b(?:SR|LLR|CMP|IF|DA)-\d{3}\b', flows))
flow_part, _, free_part = flows.partition('## Requirements no flow renders')
in_flows = set(re.findall(r'SR-\d{3}', flow_part))
flow_llrs = set(re.findall(r'LLR-\d{3}', flow_part))
declared_free = set(re.findall(r'SR-\d{3}', free_part))
uncovered = [s for s in sr if s not in in_flows and not (sr_rows[s] & flow_llrs) and s not in declared_free]
report('SRs neither in a flow nor declared flow-free', [f"{s} {sr[s]['title']}" for s in uncovered])

# 5. citations
known = set(sr) | set(llr) | set(cmp_) | set(ifs) | set(das)
report('ids the flows cite that do not exist', sorted(cited - known))

if '--n2' in sys.argv:
    def scoped(c, scope):
        ch = chain(c)
        return ch[ch.index(scope) - 1] if scope in ch and ch.index(scope) > 0 else None
    for scope in [k for k in cmp_ if kids[k]]:
        children = kids[scope]
        cell = collections.defaultdict(set)
        for k, v in ifs.items():
            o = v.get('owner', '')
            for u in v.get('consumers', []) + v.get('requestors', []):
                oc, uc = scoped(o, scope), scoped(u, scope)
                if oc and uc and oc != uc:
                    cell[(oc, uc)].add(k[3:])
        print(f'\n#### N2 at {scope} {cmp_[scope]["name"]} (row owns, column consumes)\n')
        print('| owns \\ consumes | ' + ' | '.join(c[-3:] for c in children) + ' |')
        print('|---|' + '---|' * len(children))
        for r in children:
            print(f'| **{r[-3:]}** {cmp_[r]["name"]} | ' +
                  ' | '.join('—' if r == c else ', '.join(sorted(cell[(r, c)])) for c in children) + ' |')

print(f'\n{findings} advisory finding(s)')
