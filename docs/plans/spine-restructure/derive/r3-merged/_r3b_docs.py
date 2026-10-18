# Round 3b: updates design-gaps.md and merge-notes.md (read from git HEAD so a
# re-run reproduces them) and generates the placement table R3O-012 asks for.
import re, subprocess, tomllib
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[4]
REQ = REPO / 'docs' / 'requirements'
REL = 'docs/plans/spine-restructure/derive/r3-merged/'


def head(rel):
    return subprocess.run(['git', 'show', f'HEAD:{rel}'], cwd=REPO, capture_output=True,
                          check=True).stdout.decode('utf-8')


def once(text, old, new):
    assert text.count(old) == 1, old[:60]
    return text.replace(old, new)


def append_cell(text, gap, extra):
    lines = text.split('\n')
    hits = [i for i, l in enumerate(lines) if l.startswith(f'| {gap} |')]
    assert len(hits) == 1, gap
    l = lines[hits[0]].rstrip()
    assert l.endswith('|')
    body = l[:-1].rstrip()
    sep = ' ' if not body.endswith('|') else ' '
    lines[hits[0]] = body + sep + extra + ' |'
    return '\n'.join(lines)


# ---------------------------------------------------------------- design-gaps
g = head(REL + 'design-gaps.md')
g = once(g, "plus three gaps those calls add (M58 to M60).",
         "plus three gaps those calls add (M58 to M60). Round 3b (`../r3b-change-log.md`) applied the review dispositions: it amended M01, M10, M12, M32, M34, M51, M54, M55 and M60 in place where a disposition changed what governs them, and added M61 to M82.")
for gap, extra in [
    ('M01', 'Round 3b: see M79 (fixed class order, ancestry by physical location, the shared wait budget, the listing location) and M80 (a damaged link record).'),
    ('M10', 'Round 3b: the values per case are M69\'s.'),
    ('M12', 'Round 3b: see M82 (the pre-claim plan reads published records only).'),
    ('M32', 'Round 3b: see M64 (every kit file carries the revision; the restorers are replaced first; a mixed kit is refused with 3).'),
    ('M34', 'Round 3b: see M68 (unchanged files measured over runs, the space view as the cache).'),
    ('M51', 'Round 3b: the order is now M63\'s (the saved state published before content moves).'),
    ('M54', 'Round 3b: see M73 (one provider order for both routes).'),
    ('M55', 'Round 3b: superseded by M62 (every store mutation fenced, the owner record kept until the collapse ends).'),
    ('M60', 'Round 3b: folder-record age reads the kit revision, not the evidence version (M81).'),
]:
    g = append_cell(g, gap, extra)

NEW = [
 ('M61', 'SR-018', 'LLR-042, LLR-095, LLR-018', 'review (R3S-008)',
  'A refused configuration appends its refusal line to an existing global record (the entry script\'s early-failure path adds to the record when the file exists).',
  'R3S-008 overrules K27: a refused configuration reports on the console only and creates, truncates and appends to no record.'),
 ('M62', 'SR-144', 'LLR-125, LLR-117', 'review (R3S-006, R3O-001)',
  'The owner identity is re-checked at five boundaries only (M55); new objects and temporaries are never fenced; the design of round 3a deleted the owner record before the saved state was published, leaving the run-state write and the collapse with nothing to check; a temporary left by a fenced run is never removed.',
  'P-09 default (a): one owner-record read before every store mutation, fresh temporaries included; the owner record stays in the staging area until the collapse ends, the saved state being prepared in its own folder inside the staging area; the next run removes unreferenced object temporaries, by the temporary form now in IF-013.'),
 ('M63', 'SR-082, SR-059, SR-041', 'LLR-150, LLR-005, LLR-041, LLR-028', 'review (R3S-004)',
  'Superseded and removed content moves into the staging area before the saved state is published (M51), and the saved state is the staging area renamed, so a kill leaves content a visible state needs only in staging.',
  'Prepare the saved state in a folder inside the staging area, publish it while its content is still in the backup root, publish the new latest record, then move content between published locations; the next run adopts an identical saved state a kill left behind.'),
 ('M64', 'SR-110, SR-007', 'LLR-076, LLR-130, LLR-159, LLR-136, LLR-022', 'review (R3S-015, R3S-018, R3O-038)',
  'Only the two restorers carry the kit revision; the refresh copies file by file with no temporary and in no stated order (M32); no restore checks that the kit is of one revision; the kit\'s file names are fixed only in code.',
  'Kit revision 14: every text artifact carries the revision (a remark line in the Windows launcher, a key in the location sidecar, a first line in the notices file); the refresh writes the original revision, then the restorers, then the rest; a restorer refuses a kit of two revisions with 3 naming the refresh. IF-019 now holds the closed name set that LLR-022 uses.'),
 ('M65', 'SR-035, SR-093, SR-074', 'LLR-114, LLR-001, LLR-022', 'review (R3O-023)',
  'The change-detection record takes the backup record\'s own names at the source root, so a copy of a store kept at a source root has its record taken for the run\'s own and overwritten.',
  'P-08 default (a): the record is FILEBACKUP-CHANGES.csv and its evidence (IF-029 version 3); a file at the earlier name is read once where its evidence matches and every stored-copy reference is blank, then removed, and is otherwise owner content. The names are the builder\'s design; the call ruled the mechanism. Downstream-visible: every existing source root carries the old name until its first run under this version.'),
 ('M66', 'SR-052, SR-023', 'LLR-135, LLR-052, LLR-023', 'review (R3S-013, R3O-016)',
  'On Windows a path\'s volume is its drive or share root, so a folder-mounted volume is measured as the drive it sits on, and one volume reached by two paths is counted twice.',
  'The volume at the longest mount point, folder mounts included, known by a stable identity: the volume GUID path on Windows (the share root for a share), the device number on Linux and macOS (IF-031).'),
 ('M67', 'SR-001, SR-010, SR-056', 'LLR-010, LLR-142, LLR-029', 'review (R3S-010)',
  'The restore report is always RECONSTRUCT.log at the target root, so a state holding a root file of that name has it overwritten or appended to.',
  'Where the state records a file at that name (compared as the target compares names), the report takes the first free RECONSTRUCT-<n>.log (IF-022); collision planning includes the report.'),
 ('M68', 'SR-098', 'LLR-133', 'review (R3S-012, R3O-018)',
  'The round-3a design measured only files read in the run (and today none is measured, M34).',
  'Every file of the latest state is measured over runs: files read first, unchanged files for up to 300 seconds a run, the rest listed as not yet measured; the space view, which gains the content key (IF-042), is the cache; the record\'s rate column is written blank.'),
 ('M69', 'SR-017, SR-075', 'LLR-017, LLR-080, LLR-124', 'review (R3S-007, R3O-005, R3O-006, R3S-016, R3S-017)',
  'An unreadable owner record classifies as Indeterminate and every leftover refusal reports 1 (M10); a failed move aside or create refuses with 1; an owner record already present at the exclusive create aborts the run with no stated value; the owner record\'s schema and the classifier\'s inputs are not stated as form.',
  'An owner record still unreadable after three reads is evidence that cannot be read (2); a readable torn or unknown-schema record is live or unproven (4 as sole finding); a failed move aside or create is 4 for an I/O fault and 2 for access denied; an owner record already present is another holder (4); a failed final delete keeps the folder and the run completes (0). IF-033 states schema 1, Kind backup and the required fields; IF-044 takes the staging area\'s own time and read status.'),
 ('M70', 'SR-049, SR-043, SR-104', 'LLR-049', 'review (R3O-013, R3O-031)',
  'The check never tests a record against its completeness evidence, so a damaged record passes as clean; DanglingDataPath and PoolDataPathMissing report one condition twice, and the two Pool classes carry fewer fields than the rest.',
  'A failing record is a RecordEvidenceMismatch finding with outcome 3 (2 over 3 over 1), the check going on with the other states. IF-010 version 2 gives every class a meaning, states the fields every finding carries and retires DanglingDataPath: downstream-visible for a host that matches on it.'),
 ('M71', 'SR-106, SR-040', 'LLR-123, LLR-040', 'review (R3S-011)',
  'A restore of a state a concurrent removal deletes fails with whatever error the vanished folder raises, and a check meeting it reports it.',
  'P-10 default (a): the restore completes where it already read what it needs, else ends with 4 naming the removal (cause StateRemoved, IF-022); a check or the report leaves the removed state out.'),
 ('M72', 'SR-093, SR-059', 'LLR-155, LLR-095', 'review (R3S-020)',
  'The global record path from the request or the environment is created or truncated wherever it points, inside a source or the store included.',
  'Admitted before it is opened: refused as a bad request (2), on the console only, inside a source, a backup or saved-state location, or at an infrastructure name.'),
 ('M73', 'SR-073, SR-016', 'LLR-156, LLR-157, LLR-074', 'review (R3S-021, R3O-009, R3O-010, R3O-011, R3O-020)',
  'The two routes try different providers (the language-runtime route on Linux tries zenity then kdialog, with no yad and no picker variable); neither checks that the answer is an absolute existing folder; whether the shell route\'s folder-choice switch is refused in an unattended session is unconfirmed.',
  'One provider order for both routes, the picker variable first; any answer but an absolute existing folder gives no target (2). The no-dialog and picker variables now sit in the restore host session form (IF-026). Confirm the unattended case when the code is headed.'),
 ('M74', 'SR-010', 'LLR-158', 'review (R3O-010)',
  'A root override always replaces the location sidecar\'s recorded root.',
  'An override is used only where the recorded roots are unusable (the sidecar absent or unreadable, or the restore\'s own folder inside neither), and is otherwise ignored with a warning.'),
 ('M75', 'SR-015, SR-127', 'LLR-015', 'review (R3S-019, R3O-038)',
  'SmtpPort has no default in the catalogue (an absent port reaches the mail call empty, which then uses 25) and no range check; the TLS mode is implicit in the mail call\'s switch; a skipped notification is logged without being a stated entry kind.',
  'Default 25, range 1 to 65535 and STARTTLS stated in the forms (IF-004, IF-011); a skipped notification is recorded with its reason.'),
 ('M76', 'SR-126', 'LLR-097', 'review (R3O-024)',
  'The documented refusal tokens are the seven SR-075 ones; [2/staging-busy] is used but undocumented; most refusals carry no token; several entries other rows require (run state rebuilt, retry limit reached, space check not made, work reclaimed, each retry) have no message kind.',
  'A closed token set, each naming its value and cause and no requirement, plus the message kinds (IF-009).'),
 ('M77', 'SR-048', 'LLR-048', 'review (R3O-037)',
  'A flag variable holding any value outside the truthy set counts as unset.',
  'A non-empty value in neither the truthy nor the falsy set is a bad request (2); the falsy set is stated in IF-038.'),
 ('M78', 'SR-061, SR-005', 'LLR-005', 'review (R3O-034)',
  'The saved-state folder pattern has no end anchor, so a folder named like a saved state with any tail is taken for one.',
  'The anchored pattern with the optional three-digit suffix (IF-013).'),
 ('M79', 'SR-137, SR-090, SR-150, SR-151', 'LLR-109, LLR-110, LLR-151, LLR-152, LLR-067, LLR-111', 'review (R3S-001, R3S-002, R3S-025, R3S-026, R3O-008, R3O-029, R3O-030)',
  'Extends M01, which is build work in full.',
  'Classes taken in a fixed order, ancestry by physical location; an ancestor reached through a followed link is recorded with its walk path and re-pointed at restore; link waits share the location\'s 60-second budget with retries; the listing location is a system location (P-11 default (a)).'),
 ('M80', 'SR-146', 'LLR-144, LLR-143, LLR-040', 'review (R3O-014)',
  'No link record exists (M01), and a folder record short of its stated rows is not detected.',
  'A missing, malformed or short folder or link record of a current-form state restores every file, names what was not applied and ends with 1.'),
 ('M81', 'SR-116, SR-146', 'LLR-138, LLR-143', 'review (R3S-014, R3O-002)',
  'Extends M60.',
  'Folder-record age is read from the kit revision, the evidence version deciding only the link record and the row counts. Not applied as written: the disposition gives a version-2-evidence state written after folder records existed, with its folder record missing, the value 1, but that release wrote the folder record only when it had rows, so 1 would fail every such state that has no empty or attributed folder. The design restores it complete with the folder record reported unverified; a malformed one present is still 1. Proposed as P-12 (r3b-change-log.md).'),
 ('M82', 'SR-052, SR-085', 'LLR-052, LLR-091', 'review (R3S-005, R3O-015)',
  'Extends M12.',
  'The pre-claim plan reads only published records, as a reader does, and changes nothing, so it may refuse; the plan made under the claim binds.'),
]
rows = '\n'.join(f'| {a} | {b} | {c} | {d} | {e} | {f} |' for a, b, c, d, e, f in NEW)
m60 = [l for l in g.split('\n') if l.startswith('| M60 |')][0]
g = once(g, m60 + '\n', m60 + '\n' + rows + '\n')
g = once(g, '\n60 gaps. ', '\n82 gaps. ')
g = once(g, "Astra G-10 (a refused configuration appends to an existing global log) is dropped, since SR-018 forbids truncation, not an appended refusal line (K27);",
         "Astra G-10 (a refused configuration appends to an existing global log) was dropped under K27, and returns as M61 since R3S-008 overruled K27;")

g = once(g, "Every interface except IF-027 also has a constraining LLR; IF-027 relies on its pair here.",
         "Every interface except IF-017 and IF-018 also has a constraining LLR; those two rely on their pairs here. Round 3b (R3O-012): the rows stating their behaviour belong to source capture and tree finishing, which own no interface, so they no longer constrain the store format's records and show as unplaced; the SRs are the records' constrainers.")
g = once(g, "- SR-073 -> IF-027 (Folder choice dialog) (added by the merge:",
         "- SR-065 -> IF-017 (Folder record)\n- SR-146 -> IF-017 (Folder record)\n- SR-150 -> IF-018 (Link record)\n- SR-152 -> IF-018 (Link record)\n- SR-146 -> IF-018 (Link record)\n- SR-073 -> IF-027 (Folder choice dialog) (round 3b: LLR-156 now constrains IF-027 as well; added by the merge:")
g = once(g, "- **The run-date test seam** (the switch that pins a run's date). Not part of the launch form; a test-tier seam.",
         "- **The run-date test seam** (the switch that pins a run's date). Round 3b (R3O-036): listed in the launch form (IF-002) as a test seam that sets the run's clock, so no caller is refused; still no SR asks for it and no LLR states it.")
g = once(g, "- **The listing location must be on the backup's volume.** K35: kept, with its reason now in LLR-103's rationale (each view entry is a relative link to its stored object, and a relative link cannot cross volumes on Windows), so it is no longer beyond the design.",
         "- **The listing location must be on the backup's volume.** K35, R3O-017: kept, and now traced to SR-062 in LLR-153 (each view entry is a relative link to its stored object, and a relative link cannot cross volumes on Windows), so it is no longer beyond the design.")
(HERE / 'design-gaps.md').write_bytes(g.encode('utf-8'))

# ---------------------------------------------------------------- placement
llr = tomllib.load(open(REQ / 'low-level-requirements.toml', 'rb'))['design']
ifs = tomllib.load(open(REQ / 'interfaces.toml', 'rb'))['interface']
cmp_ = tomllib.load(open(REQ / 'components.toml', 'rb'))['component']
SEC = {'Operation launch and outcome': 'CMP-002', 'Configuration': 'CMP-003', 'Provisioning': 'CMP-004',
       'Notification': 'CMP-005', 'Run record and progress': 'CMP-006', 'Source capture': 'CMP-008',
       'Change detection': 'CMP-009', 'Content writer': 'CMP-010', 'State publication': 'CMP-011',
       'Exclusive-use guard': 'CMP-012', 'Removal and saved-state report': 'CMP-013',
       'Check, repair and kit refresh': 'CMP-014', 'Views': 'CMP-015', 'Store format': 'CMP-016',
       'Restore admission': 'CMP-018', 'Entry restoration': 'CMP-019', 'Tree finishing': 'CMP-020',
       'Restore outcome': 'CMP-021', 'Restore launch and target choice': 'CMP-022', 'Container': 'CMP-023',
       'Release guidance': 'CMP-024'}
# Rows whose responsibility is not their file section's.
OVR = {'LLR-048': 'CMP-023', 'LLR-102': 'CMP-024', 'LLR-087': 'CMP-016', 'LLR-118': 'CMP-016',
       'LLR-038': 'CMP-016', 'LLR-120': 'CMP-016', 'LLR-121': 'CMP-016', 'LLR-060': 'CMP-016',
       'LLR-069': 'CMP-016', 'LLR-140': 'CMP-016', 'LLR-035': 'CMP-011', 'LLR-028': 'CMP-011',
       'LLR-123': 'CMP-012', 'LLR-076': 'CMP-017', 'LLR-119': 'CMP-017', 'LLR-029': 'CMP-021',
       'LLR-149': 'CMP-001', 'LLR-160': 'CMP-001'}
txt = (REQ / 'low-level-requirements.toml').read_text(encoding='utf-8')
sec, resp = None, {}
for line in txt.splitlines():
    m = re.match(r'# === (.*?) =+', line)
    if m:
        sec = m.group(1)
    m = re.match(r'\[design\.(LLR-\d+)\]', line)
    if m:
        resp[m.group(1)] = OVR.get(m.group(1), SEC[sec])


def ancestors(c):
    out = []
    while c in cmp_ and cmp_[c].get('part_of'):
        c = cmp_[c]['part_of']; out.append(c)
    return out


tab = ['| LLR | Responsibility | Constrains | Interface owner | Derived placement | Verdict |', '|---|---|---|---|---|---|']
counts = {}
for lid in sorted(llr):
    l, r = llr[lid], resp[lid]
    cs = l.get('constrains')
    own = ifs[cs]['owner'] if cs else ''
    if not cs or own.startswith('external:'):
        place, verdict = 'unplaced', 'unplaced'
    elif own == r:
        place, verdict = own, 'placed'
    elif own in ancestors(r):
        place, verdict = own, 'placed at an ancestor'
    else:
        place, verdict = own, 'MISPLACED'
    counts[verdict] = counts.get(verdict, 0) + 1
    name = cmp_[r]['name'] if r in cmp_ else r
    tab.append(f'| {lid} | {r} {name} | {cs or "-"} | {own or "-"} | {place} | {verdict} |')
assert 'MISPLACED' not in counts, counts

own_by = {}
for iid, i in ifs.items():
    own_by.setdefault(i['owner'], []).append(iid)
ctab = ['| Component | Owns | Rows placed here |', '|---|---|---|']
for cid in sorted(cmp_):
    placed = [lid for lid in sorted(llr) if llr[lid].get('constrains') and ifs[llr[lid]['constrains']]['owner'] == cid]
    ctab.append(f'| {cid} {cmp_[cid]["name"]} | {", ".join(sorted(own_by.get(cid, []))) or "none"} | {len(placed)} |')

mn = head(REL + 'merge-notes.md')
mn += f"""
## Round 3b: the review dispositions

The full-round-1 dispositions (`../r3-dispositions.md`, review dispositions table) are applied by `_r3b_apply.py` (every edit as an anchored replacement over the HEAD carriers, so a re-run reproduces the tier) and `_r3b_docs.py` (this section and the design-gaps changes); `_r3b_lint.py` adds the dimension-grammar, history-token, dangling-reference and SR-naming checks and lists every row changed. The entry per finding is in `../r3b-change-log.md`. Ten LLRs were added (LLR-151 to LLR-160, after the highest id in use, LLR-150; LLR-145 stays retired).

### Placement (R3O-012)

Placement is derived from the owner of the interface a row constrains. The dispositions allow unplaced rows but not rows placed in the wrong component, and forbid minting interfaces only to place rows. So: IF-020 (the restore request) moved to the restore kit (CMP-017), which with IF-019 and IF-023 owns what its children produce together; every row whose constrained interface belonged to another component's responsibility lost its `constrains` cell (its dimensions stay) and shows as unplaced; LLR-111, LLR-113 and LLR-122 were re-pointed to an interface their own component owns or reads at (IF-028, IF-029, IF-032). The store-format records IF-017 and IF-018 are left with SR constrainers only (design-gaps section 2). A row placed at an enclosing component counts as placed. Responsibility is the row's section in `low-level-requirements.toml`, except where the table's first column says otherwise (writer rows filed under State publication, the container's mapping row, the whole-run rows).

Counts: {', '.join(f'{v} {k}' for k, v in sorted(counts.items()))}; none misplaced.

{chr(10).join(ctab)}

{chr(10).join(tab)}
"""
(HERE / 'merge-notes.md').write_bytes(mn.encode('utf-8'))
print('docs written', counts)
