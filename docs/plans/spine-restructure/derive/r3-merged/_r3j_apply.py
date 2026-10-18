# Round 3j: applies the scoped convergence check of the closing fixes
# (r3-dispositions.md, "Convergence check of the closing fixes", R3I-001..003).
# Reads every carrier from git HEAD, so re-running it reproduces the result.
import re, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from _tomledit import Doc  # noqa: E402

REPO = HERE.parents[4]
REQ = REPO / 'docs' / 'requirements'


def head(name):
    return subprocess.run(['git', 'show', f'HEAD:docs/requirements/{name}'], cwd=REPO,
                          capture_output=True, check=True).stdout.decode('utf-8')


L = Doc(head('low-level-requirements.toml'))
R = Doc(head('system-requirements.toml'))

# ======================================================================
# R3I-001: before replacing any record of a latest state whose evidence is
# of version 3, re-bind the unchanged state by digest with one rename.
# ======================================================================

d = L.row('LLR-162').get('detail')
# Make room for the new step S12: S12..S26 become S13..S27.
d = re.sub(r'\bS(\d\d)\b', lambda m: f'S{int(m.group(1)) + 1:02d}' if int(m.group(1)) >= 12 else m.group(0), d)
old_tail = 'Where the published evidence is of version 3, which binds the folder and link records by row count only, a kill at S14 or S15 in the first run that writes version 4 is seen only where a count differs; from then on the digests show it.'
assert d.count(old_tail) == 1
d = d.replace(old_tail, "Where the latest state's published evidence is of version 3, which binds the folder and link records by row count only, S12 first binds the unchanged state by digest, so no later step can pair one run's folder or link record with another run's files unseen.")
s11 = next(l for l in d.split('\n') if l.startswith('| S11 |'))
d = d.replace(s11, s11 + '\n' + "| S12 | where the latest state's published evidence is of version 3: writing version-4 evidence for the unchanged published record, folder record and link record at a temporary in the backup root's run folder, then renaming it out | the evidence temporary; or, once renamed, the pre-run state bound by version-4 evidence | no content; the latest state is the pre-run tree throughout, bound by digest before any of its records is replaced (LLR-118) |", 1)

# ======================================================================
# R3I-003: the reclaim's identity-mismatch rollback, in reverse order.
# R3..R5 become R4..R6; the new R3 is the rollback.
# ======================================================================

d = re.sub(r'\bR([3-5])\b', lambda m: f'R{int(m.group(1)) + 1}', d)
d = d.replace('changes them only by the steps R1 to R6.', 'changes them only by the steps R1 to R6.')
assert 'steps R1 to R6' in d, 'reclaim range'
r2 = next(l for l in d.split('\n') if l.startswith('| R2 |'))
d = d.replace(r2, r2 + '\n' + "| R3 | finding a moved folder's identity other than the one the sample classified, moving the moved folders back, the saved-state root's first, then the backup root's | as R2 before the first move back, as R1 after it | as R2 or R1; the next run classifies the areas as they then are. A move back that fails leaves one of those shapes, and the run refuses as busy (4) |", 1)
d = d.replace('A run\'s cleanup after an early failure (LLR-124) leaves only the shapes of S24 to S27.',
              "A run's cleanup after an early failure (LLR-124) leaves only the shapes of S24 to S27.")
assert "S24 to S27" in d

steps = re.findall(r'^\| ([SR]\d+) \|', d, re.M)
assert steps[:2] == ['S01', 'S02'] and 'S27' in steps and 'R6' in steps and len(steps) == len(set(steps)) == 33, steps
L.set('LLR-162', 'detail', d)
L.sub('LLR-162', 'dimensions', re.search(r'step=set\{[^}]*\}', L.row('LLR-162').get('dimensions')).group(0),
      'step=set{' + ','.join(steps) + '}')

L.sub('LLR-118', 'detail',
      'so the evidence is the commit point for all three (LLR-162).',
      "so the evidence is the commit point for all three (LLR-162). Where the latest state's published evidence is of an earlier version, which binds the folder and link records by row count only, a backup first publishes version-4 evidence for the unchanged published state, by one rename, before it replaces any of the three.")

L.sub('LLR-124', 'detail',
      'on any mismatch, move the moved folders straight back;',
      "on any mismatch, move the moved folders straight back, the saved-state root's first, the reverse of the order they were moved in, so every kill leaves a shape LLR-162 lists;")

# ======================================================================
# R3I-002: the metadata-only exception (P-16) in the normative text.
# ======================================================================

R.sub('SR-082', 'requirement',
      'and every visible state either restorable as recorded or refused by a restore',
      "and every visible state either restorable as recorded, restorable with its folder or link metadata left unapplied and reported as part failed where only that metadata disagrees with the state's completeness evidence, or refused by a restore")
R.sub('SR-106', 'acceptance_criteria',
      'ends with retry later (value 4), a restore writing nothing.',
      "ends with retry later (value 4), a restore writing nothing; where only a state's folder record or link record still disagrees with its evidence when the wait ends, a restore restores every file, leaves that record unapplied and ends part failed (value 1, SR-040).")
L.sub('LLR-123', 'detail',
      'unless a publication outlasts the wait, which ends with 4.',
      'unless the publication of a record of contents outlasts the wait, which ends with 4; one in which only a folder or link record disagrees ends as stated above.')

for name, doc in (('low-level-requirements.toml', L), ('system-requirements.toml', R)):
    (REQ / name).write_bytes(doc.text().encode('utf-8'))
print('carriers written;', len(steps), 'steps')
