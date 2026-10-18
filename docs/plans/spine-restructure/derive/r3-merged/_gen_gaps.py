# Writes design-gaps.md from the alignment's merged gap list (section 6) with the
# coordinator's calls applied, the gaps those calls add, the SR-constrains pairs,
# the coverage statement and the code beyond the design.
import json, tomllib, sys
from pathlib import Path

D = Path(__file__).resolve().parent.parent
m = json.load(open(D / 'r3-alignment-map.json', encoding='utf-8'))
llr = tomllib.load(open(D / 'r3-merged/low-level-requirements.toml', 'rb'))['design']
ifs = tomllib.load(open(D / 'r3-merged/interfaces.toml', 'rb'))['interface']

SET = {  # replaces the "settled" cell: the call that now governs the gap
 'M01': "The 60-second bound per resolution or enumeration request is new design (K18). The alignment's reading: a folder link is probably written to the folder record as an empty folder today.",
 'M04': "K12: reconciled per path against the backup's latest record; no new record fields. Missing means empty today (no refusal).",
 'M05': "P-05 default (a): rebuild from the evidence's written time and report it (K11).",
 'M07': "K01 and P-01 default (a): elapsed periods; the configuration stays at version 2 (K02).",
 'M12': "K10: the plan runs read-only before any root, claim, record, staging area or log exists and is checked again under the claim (today it is never re-checked). K09: the declared allowance values in LLR-052 are new.",
 'M15': "K07: fetched without a question, attended or not; the permission switch stays accepted with no meaning. No digest check was found in the code.",
 'M19': "K09: declared allowance values (allocation rounding, per-folder and per-entry bytes, a fixed 16 MiB, twice the largest expanded item). K08 and P-04 default (a): an unmeasurable volume is not refused, but the report must say the check was not made.",
 'M30': "K05 and P-03 default (a): the full payload check is the default (about 3 h of reading at the reference host, inside SR-064's 8 h); the deep switch stays accepted with no meaning.",
 'M32': "Confirmed in code. K23: the source becomes the installed program's kit, each file through a temporary and a rename, never deleting, the files carrying the kit revision last. K14: the first refresh of a state records its original kit revision (new form, IF-019). Whether each repair rename publishes by temporary and rename is still unconfirmed.",
 'M42': "Confirmed. K13 and P-06 default (a): the writer uses the backslash on every host; readers of a record written by a supported version take '/' and '\\' alike and change detection compares the normalised paths, so a Linux-written store takes no full rewrite and no extra saved state; its latest record turns to the backslash with the first run that has a real change. The format change is a downstream-visible migration to flag.",
 'M43': "K19: each temporary is flushed to stable storage before its rename (today nothing is flushed). K20: the evidence of the temporary is written before the record's rename, so the next run completes the publication.",
 'M51': "Confirmed in code. The design (LLR-150) moves content out of the backup root only after the new latest record is published.",
 'M53': "K34 and P-07 default (a): a kit carried to a Mac inside a zip is outside the support boundary; the build work is the manual's one-line remedy, writing the launcher with its executable permission where the volume holds one, and holding the window on the restorer's error trap.",
 'M55': "K21: re-check before every destructive step (move, delete, replace, publish); writing a new object at a fresh temporary name needs none.",
 'M56': "K22: no claim and no reader artifact; a reader re-resolves a vanished location by content key and re-reads a record whose evidence changed mid-read, up to three times.",
 'M57': "K26: /tmp is declared in the mount form (IF-039) as a non-persistent scratch mount. A gap only if the reviewers find SR-130's 'working-state locations' does not admit it.",
}
NEW = [
 ('M58', ['SR-118', 'SR-040'], ['LLR-139', 'LLR-040'], 'coordinator (K32)',
  "Neither route self-tests a present tool at admission; the archive tool's self-test runs only inside the content search, so a broken tool is met mid-restore and reported as a host fault (4).",
  "K32: a tool present but failing its self-test at admission returns 2."),
 ('M59', ['SR-003', 'SR-082'], ['LLR-117'], 'O (its reading of the code)',
  "A new stored object is written directly at its content-derived name after clearing an unreferenced file there (the archive tool adds to an existing archive); it is not written at a temporary name, checked and published by rename.",
  "K33: write at a private temporary, verify the content key, publish without replacing a claimed object. Not re-checked by the alignment; confirm when the code is headed."),
 ('M60', ['SR-116', 'SR-146', 'SR-084'], ['LLR-138', 'LLR-038', 'LLR-131'], 'coordinator (K14)',
  "The completeness evidence is version 2 and states no folder- or link-record rows; no state records an original kit revision, and a kit refresh overwrites the only kit revision a state carries, so age cannot be told positively once a state is refreshed.",
  "K14: evidence version 3 with DirRows and LinkRows (IF-015); the kit refresh records a state's original kit revision once, never changed (IF-019); no per-state format descriptor. The kit revisions that introduced completeness evidence, the folder record and the link record must be read from the release history at build time."),
]

def ids(v):
    return ', '.join(v)

for g in m['design_gaps']:
    for l in g['llrs']:
        if l not in llr:
            sys.exit(f"gap {g['id']} names unknown {l}")
L = []
L.append('# Design gaps (round 3, merged tier)')
L.append('')
L.append("Where an SR obligation is not met by today's code: the SR, the merged LLR that now states the design, and what the code does instead. This list becomes the build work. It is the alignment's merged list (section 6, M01 to M57) with the coordinator's calls (r3-dispositions.md, K01 to K38, P-01 to P-07) applied, plus three gaps those calls add (M58 to M60). 'Found by' says which derivation listed it; the last column records the call or the code check that settles it. Nothing here was run; a 'does instead' resting on inference says so.")
L.append('')
L.append('## 1. Obligations today\'s code does not meet')
L.append('')
L.append('| Gap | SRs | Merged LLR | Found by | What the code does instead | Settled, or the call that governs it |')
L.append('|---|---|---|---|---|---|')
fb = {'both': 'both', 'A': 'Astra', 'O': 'Opus', 'neither': 'alignment code check'}
for g in m['design_gaps']:
    s = SET.get(g['id'], g['settled'])
    L.append(f"| {g['id']} | {ids(g['srs'])} | {ids(g['llrs'])} | {fb.get(g['found_by'], g['found_by'])} | {g['code']} | {s} |")
for gid, srs, ll, by, code, s in NEW:
    for l in ll:
        assert l in llr, l
    L.append(f"| {gid} | {ids(srs)} | {ids(ll)} | {by} | {code} | {s} |")
L.append('')
L.append(f"{len(m['design_gaps']) + len(NEW)} gaps. Claimed gaps the alignment dropped or folded: Astra G-10 (a refused configuration appends to an existing global log) is dropped, since SR-018 forbids truncation, not an appended refusal line (K27); Astra G-13 is folded into M08; Astra G-30 into M34; Opus G-36's kit-refresh half is settled in M32 and its repair-rename half stays open there.")
L.append('')
L.append('## 2. SR constrains')
L.append('')
L.append("Boundary interfaces whose behaviour an SR states at the system boundary. The SR tier is not this tier's to edit, so these pairs are listed for it to carry as `constrains` cells. Every interface except IF-027 also has a constraining LLR; IF-027 relies on its pair here.")
L.append('')
pairs = [tuple(p) for p in m['sr_constrains']] + [('SR-073', 'IF-027')]
for s, i in pairs:
    assert i in ifs, i
    note = ''
    if i == 'IF-027':
        note = " (added by the merge: the folded Opus LLR-145 was IF-027's only constraining row; its observable part, an absent, failed or cancelled choice giving no target, now sits in LLR-073, which constrains IF-026, so SR-073's own 'asks for the target folder' is what constrains the dialog)"
    L.append(f"- {s} -> {i} ({ifs[i]['title']}){note}")
L.append('')
L.append('## 3. SRs that reach no LLR')
L.append('')
L.append("None. Every one of the 123 SRs is in the `sr_refs` of at least one top-level LLR (the validator's count: 0 unreached).")
L.append('')
L.append('## 4. Code beyond the design')
L.append('')
L.append("No SR asks for these. None is stated by an LLR; where the request form still accepts a switch so that existing callers are not refused, the interface form says so.")
L.append('')
L.append("- **Removal dry run** (the removal's what-if switch, and the container's dry-run variable). P-02 default (c), K04: it stays accepted in the removal request form (IF-002) and the container form (IF-038) and keeps working, unspecified; no LLR states it, and it is never made a bad request until the Owner rules (add a need, or retire it with a release note).")
L.append("- **Removal overrides at the module level** (discard unreferenced content, accept unverified records, skip verification). K06: not in the request form; SR-046 refuses those cases without exception. Retire them or keep them test-only.")
L.append("- **The deep-check switch.** K05: its meaning becomes the default check (LLR-049); it stays accepted with no meaning, like the former outcome switch.")
L.append("- **The permission switch for obtaining the hashing component.** K07: accepted with no meaning; the component is fetched without a question (LLR-105).")
L.append("- **The strict-evidence restore switch** (both routes). Kept in the restore request form (IF-020) and honoured in LLR-039, though no SR asks for it; treat like the dry run: the Owner adds a need or it stays outside the design.")
L.append("- **The multi-set warning.** Goes (SR-095, LLR-014).")
L.append("- **The run-date test seam** (the switch that pins a run's date). Not part of the launch form; a test-tier seam.")
L.append("- **The include-saved-states boolean and the verify alias.** Accepted by today's entry point; the merged IF-002 lists both as accepted spellings of existing requests (latest-only check, the check action), so they stay working with no new meaning.")
L.append("- **The listing location must be on the backup's volume.** K35: kept, with its reason now in LLR-103's rationale (each view entry is a relative link to its stored object, and a relative link cannot cross volumes on Windows), so it is no longer beyond the design.")
(D / 'r3-merged/design-gaps.md').write_text('\n'.join(L) + '\n', encoding='utf-8', newline='\n')
print('gaps', len(m['design_gaps']) + len(NEW))
