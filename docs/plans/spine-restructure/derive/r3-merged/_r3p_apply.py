"""Round 3p: apply the Owner's Calls 1-4 from r3o-decomposition.md.

Call 1: fold CMP-008 (source capture) into CMP-009.
Call 2: fold CMP-010 (content writer) into CMP-011.
Call 3: split IF-010 into the check findings (CMP-014) and the saved-state report (new IF-047, CMP-013).
Call 4: fold CMP-018, CMP-020 and CMP-022 into CMP-017 as states of the restore.
"""
import os
import re

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', '..', '..'))
C = 'docs/requirements/components.toml'
I = 'docs/requirements/interfaces.toml'
L = 'docs/requirements/low-level-requirements.toml'


def read(p):
    return open(p, encoding='utf-8').read()


def write(p, s):
    open(p, 'w', encoding='utf-8', newline='').write(s)


def sub(p, old, new):
    s = read(p)
    assert s.count(old) == 1, (p, old[:70], s.count(old))
    write(p, s.replace(old, new))


def drop_table(p, header):
    s = read(p)
    m = re.search(r'^' + re.escape(header) + r'\n[\s\S]*?(?=^\[|\Z)', s, re.M)
    assert m, header
    write(p, s[:m.start()] + s[m.end():])


def set_cell(p, header, key, value):
    s = read(p)
    m = re.search(r'^' + re.escape(header) + r'\n[\s\S]*?(?=^\[|\Z)', s, re.M)
    assert m, header
    block = m.group(0)
    pat = re.compile(r'^' + key + r' = (""".*?"""|"[^"\n]*"|\[[^\]]*\])$', re.M | re.S)
    assert pat.search(block), (header, key)
    block2 = pat.sub(lambda _: key + ' = ' + value, block, count=1)
    write(p, s[:m.start()] + block2 + s[m.end():])


# ---- components -------------------------------------------------------------
for h in ('[component.CMP-008]', '[component.CMP-010]', '[component.CMP-018]',
          '[component.CMP-020]', '[component.CMP-022]'):
    drop_table(C, h)

set_cell(C, '[component.CMP-007]', 'notes', '"""Everything that produces and maintains a backup and that a restore never needs. Its children are drawn by the decision each one hides: source scan and change detection, content storage and state publication, the exclusive-use guard, removal and the saved-state report, check, repair and kit refresh, and the views. Today one backup-only module holds all of them, which is why one change to any of them touches the same file; the tree records the seams that file does not."""')

set_cell(C, '[component.CMP-009]', 'name', '"Source scan and change detection"')
set_cell(C, '[component.CMP-009]', 'notes', '"""Walks each source tree read-only, every entry at every depth hidden, system and dot-named ones included, leaving out only the declared exclusions; classifies each folder link or junction as followed or recorded; refuses names that cannot exist on Windows or Linux; retries a briefly unreadable file within a per-location limit; names everything it could not capture; records the empty and attributed folders; and decides which files are new, changed or removed, comparing each file\'s size and modification time with the change-detection record and re-reading unchanged-looking content on the runs the re-read schedule makes due. It rebuilds the change-detection record from the backup\'s own record of contents when that record is missing, damaged or foreign, and keeps it at the source root or at the configured state location. The source tree it reads belongs to the source system, outside FileBackup, so it is an external interface and never a component: the walk\'s rows constrain that interface and show at the system root. Today the walk lists a folder link like a folder, so a link comes back from a restore as an empty folder; a file that cannot be hashed aborts the whole location instead of being named; and a missing change-detection record is silently treated as empty while an unreadable one fails the location. It owns the change-detection record; the re-read schedule row states no behaviour across it and shows as unplaced."""')

set_cell(C, '[component.CMP-011]', 'name', '"Content storage and state publication"')
set_cell(C, '[component.CMP-011]', 'notes', '"""Stores each distinct content once and turns a run\'s changes into published states. Storage: groups new and changed files by content key, elects the one stored form of each group, decides compression from a measured saving or from the file type, writes each stored object under its content-derived name, stores lost content again, adopts existing content only where it is actually present, and checks free space per volume before anything is written. Publication: stages the previous state, keeps its superseded and removed content, removes from the latest state only content no remaining entry claims, publishes each record of contents with matching completeness evidence so a reader never sees a torn one, dates and names the saved state, adds none for an unchanged run, places the restore kit in every state, collapses content duplicated across saved states, and keeps the run-state record. Today the compression measurement and decision live in the backup-only engine module while the already-compressed type list and the archive calls live in the restore-safe shared library, so a list edit moves the kit revision although no restore reads the list; and publication is spread over the backup driver and its staging, eviction, preservation and finalisation steps, with the record writer in the shared library. It owns only the run-state record; stored objects, the store layout and the record of contents are the store format\'s, so its storage and publication rows show as unplaced rather than placed in the format."""')

sub(C, "today repair renames objects but never copies content back. It owns no interface, so its rows show as unplaced: placement is derived only through an interface's owner, and no interface was minted just to place them.",
       "today repair renames objects but never copies content back. It owns the check findings (IF-010).")

set_cell(C, '[component.CMP-017]', 'notes', '"""What every state of a backup carries so it can be restored with no FileBackup installed. A restore runs through the states its runtime flow shows: launched, admitting, restoring, finishing and reported. The launchers start it and carry no restore logic, and the target is asked for only where someone can answer, an interactively started restore keeping its outcome on screen until dismissed. Admission makes every whole-restore decision before anything is written: the request and its target, the kit\'s revision, the record\'s completeness evidence and form, the age evidence that excuses a check an older state cannot support, the tools the route needs, and the target\'s space. Finishing applies, after every file is written and verified, each file\'s own time, the empty folders and folder attributes the target can hold, and the recorded links. Entry restoration and the outcome classification are its child components, since each hides a decision of its own; the phases are states, not components. Everything is realised twice today, once on the language-runtime route and once on the shell route; one set of requirements binds both, and parity is verified per route at the test tier. Today the language-runtime route runs the space check after it has created the target and its log, the shell route runs its retired-form check after the same point, neither consults positive age evidence, links are neither recorded nor rebuilt, and folder metadata that is missing or malformed never changes the outcome. It owns the kit artifact set, the restore request and the restored tree; rows that state behaviour across those are placed here, and rows across the target probe, the tool floor, the host session and the folder dialog, which belong to systems outside FileBackup, show at the system root."""')

# ---- interfaces: consumers and requestors of the retired components ----------
s = read(I)
pairs = [
    ('consumers = ["CMP-006", "CMP-010"]', 'consumers = ["CMP-006", "CMP-011"]'),
    ('consumers = ["CMP-010", "CMP-013", "CMP-014", "CMP-019"]', 'consumers = ["CMP-011", "CMP-013", "CMP-014", "CMP-019"]'),
    ('consumers = ["CMP-008", "CMP-011", "CMP-020"]', 'consumers = ["CMP-009", "CMP-011", "CMP-017"]'),
    ('consumers = ["CMP-008", "CMP-020"]', 'consumers = ["CMP-009", "CMP-017"]'),
    ('consumers = ["CMP-018", "CMP-019", "CMP-020"]', 'consumers = ["CMP-017", "CMP-019"]'),
    ('consumers = ["CMP-022"]', 'consumers = ["CMP-017"]'),
    ('requestors = ["CMP-022"]', 'requestors = ["CMP-017"]'),
    ('consumers = ["CMP-008", "CMP-009"]', 'consumers = ["CMP-009"]'),
    ('consumers = ["CMP-010", "CMP-013"]', 'consumers = ["CMP-011", "CMP-013"]'),
    ('consumers = ["CMP-011", "CMP-013", "CMP-014", "CMP-018"]', 'consumers = ["CMP-011", "CMP-013", "CMP-014", "CMP-017"]'),
    ('consumers = ["CMP-009", "CMP-010", "CMP-013", "CMP-014", "CMP-019"]', 'consumers = ["CMP-009", "CMP-011", "CMP-013", "CMP-014", "CMP-019"]'),
    ('requestors = ["CMP-010", "CMP-013", "CMP-014", "CMP-018", "CMP-019"]', 'requestors = ["CMP-011", "CMP-013", "CMP-014", "CMP-017", "CMP-019"]'),
]
for old, new in pairs:
    assert s.count(old) == 1, (old, s.count(old))
    s = s.replace(old, new)
write(I, s)

# ---- interfaces: split IF-010 -----------------------------------------------
set_cell(I, '[interface.IF-010]', 'title', '"Check findings"')
set_cell(I, '[interface.IF-010]', 'owner', '"CMP-014"')
sub(I, '''data = """One UTF-8 JSON document on standard output.
Saved-state report: an array, one object per saved state, oldest first: Name (string, the saved-state folder name), Date (string, ISO-8601), Rows (integer), PhysicalBytes, BytesReclaimed, BytesReHomed (integers, bytes).
Check, and check with repair: an array, one object per finding, empty when clean.''',
       '''data = """One UTF-8 JSON document on standard output, for a check and a check with repair: an array, one object per finding, empty when clean.''')
sub(I, 'rationale = """A host deciding whether to remove a saved state, or whether a store is healthy, must parse the answer; scraping the human-readable record lost because its wording is free to change."""',
       'rationale = """A host deciding whether a store is healthy must parse the answer; scraping the human-readable record lost because its wording is free to change. One document for the check and the saved-state report lost because they are two information kinds with two producers (IF-047)."""')
s = read(I)
s = s.rstrip('\n') + '''

[interface.IF-047]
title = "Saved-state report"
owner = "CMP-013"
consumers = ["external:EXT-03"]
channel = "standard output"
interface_to_external = ["B-08"]
coincident = """The document written is the report."""
data = """One UTF-8 JSON document on standard output: an array, one object per saved state, oldest first: Name (string, the saved-state folder name), Date (string, ISO-8601), Rows (integer), PhysicalBytes, BytesReclaimed, BytesReHomed (integers, bytes)."""
rationale = """A host deciding which saved state to remove must parse what each removal would free; scraping the human-readable record lost because its wording is free to change. Sharing one row with the check findings lost because they are two information kinds with two producers."""
status = "Drafted"
'''
write(I, s)

# ---- LLRs: place the report and the check on their interfaces ---------------
sub(L, '[design.LLR-047]\ntitle = "The saved-state report gives what each removal would free and move, from the removal\'s own plan"\nsr_refs = ["SR-047"]\n',
       '[design.LLR-047]\ntitle = "The saved-state report gives what each removal would free and move, from the removal\'s own plan"\nsr_refs = ["SR-047"]\nconstrains = "IF-047"\n')
sub(L, '[design.LLR-049]\ntitle = "A check reports every disagreement between the records and what is stored"\nsr_refs = ["SR-049"]\n',
       '[design.LLR-049]\ntitle = "A check reports every disagreement between the records and what is stored"\nsr_refs = ["SR-049"]\nconstrains = "IF-010"\n')
sub(L, 'one item per saved state for the report, one item per finding for the check (a repair adds whether each finding was repaired).',
       'one item per saved state for the report (IF-047), one item per finding for the check (IF-010; a repair adds whether each finding was repaired).')
print('round 3p applied')
