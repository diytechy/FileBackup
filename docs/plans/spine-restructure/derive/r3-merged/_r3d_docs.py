# Round 3d: updates design-gaps.md and merge-notes.md for full round 2
# (R3C-001..R3C-008). Reads both from git HEAD so a re-run reproduces them.
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[4]
REL = 'docs/plans/spine-restructure/derive/r3-merged/'


def head(path):
    return subprocess.run(['git', 'show', f'HEAD:{path}'], cwd=REPO, capture_output=True,
                          check=True).stdout.decode('utf-8')


def once(text, old, new):
    assert text.count(old) == 1, (old[:60], text.count(old))
    return text.replace(old, new)


def amend(text, gap, note):
    lines = text.split('\n')
    hits = [i for i, l in enumerate(lines) if l.startswith(f'| {gap} |')]
    assert len(hits) == 1, gap
    line = lines[hits[0]]
    assert line.endswith(' |'), gap
    lines[hits[0]] = line[:-2] + ' ' + note + ' |'
    return '\n'.join(lines)


# ---------------------------------------------------------------- design-gaps
g = head(REL + 'design-gaps.md')
g = once(g, "and added M61 to M82.",
         "and added M61 to M82. Round 3d (`../r3d-change-log.md`) applied full round 2: it amended M55, M62, M63, M64, M67, M73 and M79 in place and added M83 to M88.")

g = amend(g, 'M55', 'Round 3d: M62 is in turn superseded by M83.')
g = amend(g, 'M62', 'Round 3d (R3C-002): superseded by M83; the owner-record read before each change stays only as an early exit.')
g = amend(g, 'M63', 'Round 3d (R3C-002): earlier content is now placed by a verified copy published through the run folder, the backup root\'s copy deleted after, on one volume as on two (M83); a prepared folder a kill leaves is recognised (M84).')
g = amend(g, 'M64', 'Round 3d: the kit-origin artifact takes no part in the revision check (R3C-007), and a restore meeting a live refresh waits rather than refusing (M85).')
g = amend(g, 'M67', 'Round 3d (R3C-006): the free name is taken across recorded files, folders, links and the parent folders entries need (M86).')
g = amend(g, 'M73', 'Round 3d (R3C-008): the shell route also asks by typed prompt (M87).')
g = amend(g, 'M79', 'Round 3d (R3C-001): with the change-detection record at the source root, only the record and its temporaries are the system\'s own; a link to the source root or any folder of the source is inside-source and re-pointed at restore. The subtree rule applies only to a state location configured apart from the source.')

NEW = [
    ('M83', 'SR-144, SR-075, SR-082, SR-041', 'LLR-125, LLR-161, LLR-124, LLR-150, LLR-117, LLR-087, LLR-118, LLR-080, LLR-026', 'review (R3C-002)',
     "One fixed staging area at the saved-state root; the owner identity is re-checked at a few boundaries only (M55); stored objects, records, their evidence and the run-state record are written at temporaries beside their destinations and renamed into place; superseded and removed content is moved by rename (into staging, M51); nothing exists at the backup root to stage through, and a reclaim moves only the saved-state root's staging area.",
     "Coordinator design call: a run folder unique to the run identity in a staging area at each root (Temp/Run-<RunId> at the backup root and at the saved-state root, IF-033 version 2, IF-013 version 3); every store change a backup makes is a rename into or out of it, a delete being a rename in then a purge; a reclaim moves the backup root's staging area aside first, then the saved-state root's, so a resumed former owner's renames fail by themselves; the owner-record read stays as the early exit. Applied with two choices (r3d-change-log.md): one run folder per root rather than per volume, and earlier content placed by a verified copy then a delete on one volume as on two, since a rename straight between published places passes through no run folder and two renames through it leave the content in no published place between them; the copy costs reading and writing the superseded content once more (within SR-113 at the declared 1 GiB of change) and one object's extra space at a time (LLR-052). Downstream-visible: a store layout change (an older release meeting a backup root's staging area, and the publication temporaries moving into the run folders)."),
    ('M84', 'SR-075, SR-082, SR-017', 'LLR-088, LLR-017, LLR-124, IF-044', 'review (R3C-005)',
     "A staging area holding anything but the owner record and record temporaries is content and refuses; nothing recognises a saved state that was being prepared, a temporary or an entry being deleted, so a kill during preparation would refuse until a person cleans up.",
     "The run folder's entries are a closed set (IF-033); a prepared saved-state folder holding no stored object and nothing outside its closed set, whose record files are byte-identical to the backup root's, holds no content and is reclaimable once its owner is proven dead; an entry being deleted holds no content only where a published folder holds its stored name or no record names it; any other folder or entry still refuses (2). IF-044 version 2 carries these facts to the classifier."),
    ('M85', 'SR-106, SR-110, SR-040', 'LLR-159, LLR-123, LLR-130, LLR-040', 'review (R3C-004, R3C-007)',
     "No restore checks the kit's revisions (M64), so nothing tells a kit mid-refresh from one an interrupted refresh left; no restore reads the claim.",
     "P-10 widened, default (a): a restore meeting a kit of two revisions re-reads the revisions every 2 seconds for up to 60 seconds; agreeing with its own it proceeds, agreeing with another (its own restorer replaced) it ends with 4; still mixed, it tests the claim by an open the holder's excludes, closed at once and never creating the file: held gives 4 naming the refresh, free or untestable gives 3 naming a re-run of the refresh. The kit-origin artifact is outside the revision equality. The shell route's claim test needs a lock tool: present on Linux with util-linux, absent on stock macOS, where the route reports the case as untestable (3); confirm when the code is headed."),
    ('M86', 'SR-001, SR-010, SR-092', 'LLR-010, LLR-142, LLR-143, LLR-144', 'review (R3C-006)',
     "Extends M67: the report is always RECONSTRUCT.log, whatever the state records there.",
     "The report takes RECONSTRUCT.log, or the first RECONSTRUCT-<n>.log, that no recorded file, folder or link at the target's root, and no parent folder a recorded entry needs, takes under the target's comparison rules (IF-022, IF-023); the collision planning, the folder pass and the link pass use that one rule."),
    ('M87', 'SR-073, SR-016', 'LLR-157, LLR-073', 'review (R3C-008), code check',
     "The shell route never asks by typed prompt: without its folder-choice switch a missing target is usage and exit 2 whatever the session (checked in the shell restorer's argument handling: the picker runs only with the switch, and an empty target then reaches the required-argument check).",
     "SR-073 stands: the shell route asks by typed prompt where an interactive console is present and no folder-choice switch is given, desktop or not, taking only one absolute path of an existing folder; declared unattended, redirected or closed input, or neither a console nor a desktop, still gives usage and 2."),
    ('M88', 'SR-086, SR-082', 'LLR-091, LLR-095, LLR-122', 'review (R3C-003), code check',
     "A backup refused before its location's record is opened, on the claim included, appends its refusal line to the existing location record in the saved-state root (the engine's pre-logger refusal path adds to that file when it exists).",
     "A refusal on the claim or at admission reaches the console and the global record only; the location's record, inside the store, is left byte-identical."),
]
rows = '\n'.join(f'| {m} | {srs} | {llrs} | {by} | {does} | {sett} |' for m, srs, llrs, by, does, sett in NEW)
g = once(g, '\n\n82 gaps.', '\n' + rows + '\n\n88 gaps.')
(HERE / 'design-gaps.md').write_bytes(g.encode('utf-8'))

# ---------------------------------------------------------------- merge-notes
n = head(REL + 'merge-notes.md')
n = once(n, 'Counts: 64 placed, 11 placed at an ancestor, 63 unplaced; none misplaced.',
         'Counts: 65 placed, 11 placed at an ancestor, 63 unplaced; none misplaced (round 3d added LLR-161, placed at the guard).')
n = once(n, '| CMP-012 Exclusive-use guard | IF-032, IF-033, IF-044 | 11 |', '| CMP-012 Exclusive-use guard | IF-032, IF-033, IF-044 | 12 |')
n = once(n, '| LLR-160 | CMP-001 FileBackup | - | - | unplaced | unplaced |',
         '| LLR-160 | CMP-001 FileBackup | - | - | unplaced | unplaced |\n| LLR-161 | CMP-012 Exclusive-use guard | IF-033 | CMP-012 | CMP-012 | placed |')
n = n.rstrip('\n') + """

## Round 3d: full round 2

The full-round-2 dispositions (`../r3-dispositions.md`, "Convergence check 1 and full round 2", R3C-001 to R3C-008) are applied by `_r3d_apply.py` (anchored replacements over the HEAD carriers) and `_r3d_docs.py` (design-gaps M83 to M88 and this section); the entry per finding is in `../r3d-change-log.md`. One LLR was added, LLR-161 (child of LLR-125, constrains IF-033, so placed at the exclusive-use guard). No other `constrains` cell changed, so no other placement moved. IF-032 gains the restore admission (CMP-018) as a consumer, since a restore meeting a kit mid-refresh tests whether the claim is held; ownership is unchanged.
"""
(HERE / 'merge-notes.md').write_bytes(n.encode('utf-8'))
print('docs written')
