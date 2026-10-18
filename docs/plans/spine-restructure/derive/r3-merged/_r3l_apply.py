# Round 3l: applies the second scoped convergence check (r3-dispositions.md,
# "Second scoped check", R3K-001..003). Reads every carrier from git HEAD, so
# re-running it reproduces the result.
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

# R3K-001: the digest upgrade covers every evidence version without the
# digests (2 and 3), not only 3.
L.sub('LLR-162', 'detail',
      "| S12 | where the latest state's published evidence is of version 3:",
      "| S12 | where the latest state's published evidence is of version 2 or 3:")
L.sub('LLR-162', 'detail',
      "Where the latest state's published evidence is of version 3, which binds the folder and link records by row count only,",
      "Where the latest state's published evidence is of version 2 or 3, neither of which binds the folder and link records by digest,")
L.sub('LLR-118', 'detail',
      "of an earlier version, which binds the folder and link records by row count only,",
      "of an earlier version (2 or 3), neither of which binds the folder and link records by digest,")

# R3K-003: an unidentified latest folder or link record mismatch is a damaged
# record, refused with nothing changed (SR-017, SR-082). Replacing it lost:
# the saved state the run keeps copies it and would bind the damage with
# fresh evidence.
L.sub('LLR-118', 'detail',
      "A folder or link record of the latest state that disagrees and cannot be identified this way is replaced by the run's own publication, which derives both from the source, and the run's record names it.",
      "A folder or link record of the latest state that disagrees and cannot be identified this way is a damaged record, as one of contents is: the run is refused as leftovers require, with nothing changed (LLR-017). Replacing it from the source lost, because the saved state the run keeps copies the latest state's records and would bind the damage with fresh evidence.")
L.sub('LLR-017', 'detail',
      "damaged record (3) where a state's record fails its evidence and is not an interrupted publication (LLR-118),",
      "damaged record (3) where a state's record, or the latest state's folder or link record, fails its evidence and is not an interrupted publication (LLR-118),")

# R3K-002: early-failure cleanup empties a prepared folder in a safe order,
# and the table lists that dismantling as C1.
L.sub('LLR-124', 'detail',
      'deletes the rest through its run folders (LLR-161) with the owner record last,',
      'deletes the rest through its run folders (LLR-161) with the owner record last, emptying a prepared saved-state folder, which lies inside its run folder, in place: its evidence first, then its record copies, then its kit files and temporaries, then the folder itself,')
d = L.row('LLR-162').get('detail')
s27 = next(l for l in d.split('\n') if l.startswith('| S27 |'))
d = d.replace(s27, s27 + '\n' + "| C1 | an early failure's cleanup emptying the prepared saved-state folder in place: its evidence first, then its record copies, then its kit files and temporaries, then the folder (LLR-124) | a prepared folder holding part of its closed set, with no evidence, or with whole evidence beside every record it binds | no content, as S09 |", 1)
old = "A run's cleanup after an early failure (LLR-124) leaves only the shapes of S24 to S27."
assert d.count(old) == 1
d = d.replace(old, "A run's cleanup after an early failure (LLR-124) leaves only the shapes of C1 and S24 to S27, with any subset of the disposable entries S07 to S23 list.")
L.set('LLR-162', 'detail', d)
steps = re.findall(r'^\| ([SCR]\d+) \|', d, re.M)
assert len(steps) == len(set(steps)) == 34 and 'C1' in steps, steps
dims = L.row('LLR-162').get('dimensions')
dims = re.sub(r'step=set\{[^}]*\}', 'step=set{' + ','.join(steps) + '}', dims)
dims = dims.replace('; @pairwise', '; evidence_before=set{2,3,4}; @pairwise')
L.set('LLR-162', 'dimensions', dims)

(REQ / 'low-level-requirements.toml').write_bytes(L.text().encode('utf-8'))
print('carriers written;', len(steps), 'steps')
