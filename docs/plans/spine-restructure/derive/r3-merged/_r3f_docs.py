# Round 3f: updates design-gaps.md and merge-notes.md for full round 3, the
# last (R3E-001..R3E-006). Reads both from git HEAD so a re-run reproduces them.
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
g = once(g, "and added M83 to M88.",
         "and added M83 to M88. Round 3f (`../r3f-change-log.md`) applied full round 3, the last: it amended M64, M73, M83, M84, M85, M87 and M88 in place and added M89 and M90.")

g = amend(g, 'M64', 'Round 3f (R3E-004): a kit still of two revisions after the wait gives 3 only where the claim test shows no refresh holds it; held or untestable gives 4 (M85).')
g = amend(g, 'M73', 'Round 3f (R3E-006): see M87; with no provider present, both routes now ask by typed prompt at an interactive console.')
g = amend(g, 'M83', "Round 3f (R3E-001): the location record joins the fence: each run writes it in its run folder and publishes it by rename (M89). The change-detection state and the views stay outside the store and outside SR-144's guarantee (P-09 (a) as widened).")
g = amend(g, 'M84', "Round 3f: the prepared folder is recognised by its record copies being byte-identical to the backup root's plus evidence that is valid and matches its own record, never by evidence bytes, since the writer writes its own evidence (R3E-003, LLR-038 stands); an owner record torn at creation (no usable run identity) beside empty run folders is the harmless case once its death is proven (R3E-002); a run's own location record in its run folder holds no content and is kept, readable, by a reclaim (M89). IF-044 is now version 3.")
g = amend(g, 'M85', "Round 3f (R3E-004), reversing the round-3d choice: an untestable claim is indeterminate, so a still-mixed kit then ends with 4, naming the refresh, the files that differ and the remedy (re-run the refresh where none is running); only a claim test showing the claim free gives 3. No tool is added to the shell floor, so on stock macOS the shell route reports every still-mixed kit as 4.")
g = amend(g, 'M87', "Round 3f (R3E-006): on a desktop the shell route offers the folder choice from the providers (IF-027), the folder-choice switch declaring a desktop the shell cannot see (the macOS launcher passes it); with the choice suppressed (the no-dialog variable now applies on both routes) or no provider present, a typed prompt at an interactive console, otherwise usage and 2 naming the missing provider; at a console with no desktop, a typed prompt; unattended, 2. The language-runtime route takes the same no-provider fallback, where an absent provider gave no target. Build work: the shell route's desktop test on Linux and macOS, and its reading of the no-dialog variable.")
g = amend(g, 'M88', "Round 3f: the location record is now a run's own, published at its end (M89), so a refused run never touches the published one.")

NEW = [
    ('M89', 'SR-144, SR-082, SR-124', 'LLR-125, LLR-161, LLR-095, LLR-124, LLR-088, IF-009, IF-013, IF-033', 'review (R3E-001), code check',
     "The location record backup.log sits at the saved-state root, outside any run folder; the engine truncates it when the run opens its logger and appends to it in place for the whole run (checked in the engine's per-location logger setup), so a run resumed after a reclaim can still write into the record its successor writes.",
     "Each run writes its own record as backup-<RunId>.log in the saved-state root's run folder (IF-033 version 3, IF-009 version 2) and publishes it by renaming it to backup.log as its last step before cleanup, on every ending but a lost claim; a run killed or reclaimed leaves its record readable under its run name, and the reclaim keeps the moved folder holding it (LLR-124); a failed publication keeps the run folder with the record. The change-detection state and the views are outside the store and named in SR-144's acceptance as outside its guarantee; the next run reconciles them (LLR-114, LLR-061). Downstream-visible: backup.log is replaced whole at each run's end rather than truncated at its start, so during a run backup.log shows the previous run's record and the run in progress is read from its run folder (or from the console and the global record)."),
    ('M90', 'SR-106, SR-039, SR-049, SR-040', 'LLR-123, LLR-039, LLR-049, LLR-118, LLR-040', 'review (R3E-005), code check',
     "A restore reads a record's completeness evidence once and refuses any disagreement with 3 (checked in the language-runtime restorer's evidence check; the shell route's is assumed to match); nothing waits for a writer between its record and evidence renames, and no reader tests the claim.",
     "P-10 widened, default (a): a reader meeting a record and its evidence disagreeing re-reads the pair every 2 seconds for up to 60 seconds; a pair that comes to agree is read normally; still disagreeing, it tests the claim as for a mixed kit: held or untestable gives 4 (a restore writes nothing; a check leaves the state unchecked, reports no finding for it and ends with 4 unless 2 or 3 applies), free gives 3. On stock macOS the shell route cannot test the claim, so there a persisting mismatch is reported as 4, where SR-039 asks 3 (surfaced in r3f-change-log.md)."),
]
rows = '\n'.join(f'| {m} | {srs} | {llrs} | {by} | {does} | {sett} |' for m, srs, llrs, by, does, sett in NEW)
g = once(g, '\n\n88 gaps.', '\n' + rows + '\n\n90 gaps.')
(HERE / 'design-gaps.md').write_bytes(g.encode('utf-8'))

# ---------------------------------------------------------------- merge-notes
n = head(REL + 'merge-notes.md')
n = n.rstrip('\n') + """

## Round 3f: full round 3 (the last)

The full-round-3 dispositions (`../r3-dispositions.md`, "Convergence check 2 and full round 3 (the last)", R3E-001 to R3E-006) are applied by `_r3f_apply.py` (anchored replacements over the HEAD carriers) and `_r3f_docs.py` (design-gaps M89 and M90, the amended gaps, and this section); the entry per finding is in `../r3f-change-log.md`. No LLR was added and no `constrains`, `owner`, `consumers` or `parent` cell changed, so the placement table above stands unchanged (65 placed, 11 placed at an ancestor, 63 unplaced, none misplaced). Interface versions moved: IF-009 to 2 (the per-run location record name), IF-033 to 3 (the run's location record joins the run folder's closed set; the prepared folder's evidence is its own), IF-044 to 3 (the run identity's presence, the prepared folder's evidence test).
"""
(HERE / 'merge-notes.md').write_bytes(n.encode('utf-8'))
print('docs written')
