# Round 3h: closes the design tier's last findings (r3-dispositions.md,
# "Closing the design tier"): the Owner's rulings P-14 (a), P-15 (evidence
# version 4) and P-16, R3G-001..R3G-004, SR-144's scope, and the staging
# sequence as one table (LLR-162). Reads every carrier from git HEAD, so
# re-running it reproduces the result. Writes docs/requirements/{interfaces,
# low-level-requirements,system-requirements}.toml.
import subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from _tomledit import Doc  # noqa: E402

REPO = HERE.parents[4]
REQ = REPO / 'docs' / 'requirements'


def head(name):
    return subprocess.run(['git', 'show', f'HEAD:docs/requirements/{name}'], cwd=REPO,
                          capture_output=True, check=True).stdout.decode('utf-8')


I = Doc(head('interfaces.toml'))
L = Doc(head('low-level-requirements.toml'))
R = Doc(head('system-requirements.toml'))

UNSURE = 'stating that the record is damaged where none is running'

# ======================================================================
# P-14 (a): where the claim cannot be tested, 4 with the remedy and the
# damaged-unless-running reading; the SRs admit it.
# ======================================================================

R.sub('SR-039', 'requirement',
      'then the restore kit shall refuse before creating the target or writing anything, with exit code 3.',
      'then the restore kit shall refuse before creating the target or writing anything, with exit code 3, or with exit code 4 where a changing operation holds the backup or the restore cannot test whether one does (SR-106), its message then stating that the record is damaged unless a changing operation is running.')
R.sub('SR-039', 'acceptance_criteria',
      'every restorer exits 3, writes no restore log, and the target does not exist or is unchanged;',
      'every restorer exits 3, writes no restore log, and the target does not exist or is unchanged; a restore route that cannot test whether a changing operation holds the backup (the stock macOS shell route) exits 4 instead, its message naming the fault and stating that the record is damaged unless a changing operation is running, and likewise writes nothing;')
R.sub('SR-039', 'permutations', '; @pairwise', '; claim_test=set{free,untestable}; @pairwise')
R.sub('SR-039', 'rationale',
      'A record replaced together with matching evidence is outside what the backup alone can show (DA-11).',
      'A record replaced together with matching evidence is outside what the backup alone can show (DA-11). A route that cannot test whether a writer holds the backup cannot tell damage from a publication in progress, so it reports retry later and names both readings, rather than call a busy store damaged.')

R.sub('SR-082', 'requirement',
      'refused by a restore with the damaged-record outcome, never restored wrongly.',
      'refused by a restore with the damaged-record outcome (retry later where the restore cannot test whether a changing operation holds the backup), never restored wrongly.')
R.sub('SR-082', 'acceptance_criteria',
      'the latest state restores as the pre-run or the post-run tree or is refused with exit code 3, every visible saved state restores or is refused with exit code 3, and no restore produces a tree other than one the state records;',
      "the latest state restores as the pre-run or the post-run tree or is refused with exit code 3 (exit code 4 on a route that cannot test the claim, SR-039), every visible saved state restores or is refused the same way, and no restore produces a tree other than one the state records, save that a state whose folder record or link record disagrees with the state's completeness evidence restores every file as recorded, applies neither disagreeing record, names it and ends part failed (exit code 1, SR-040);")

R.sub('SR-110', 'requirement',
      'or refused by a restore with the damaged-record outcome, never restored wrongly.',
      'or refused by a restore with the damaged-record outcome (retry later where the restore cannot test whether a changing operation holds the backup), never restored wrongly.')
R.sub('SR-110', 'acceptance_criteria',
      'or is refused with exit code 3,',
      'or is refused with exit code 3 (exit code 4 on a route that cannot test the claim, SR-039),')

L.sub('LLR-039', 'detail',
      'and ends with retry later (4), naming the remedy, where the claim is held or cannot be tested;',
      f'and ends with retry later (4) where the claim is held or cannot be tested, naming the remedy, a re-run once no changing operation runs, and {UNSURE};')
# R3G-003's second half: strict evidence no longer bypasses the wait.
L.sub('LLR-039', 'detail',
      'A request for strict evidence refuses any record without evidence with 3.',
      'A request for strict evidence refuses with 3, at once, a record that has no evidence and is not of the current form, one this kit would otherwise restore as written before evidence existed; a current-form record without evidence is handled as above.')

L.sub('LLR-123', 'detail',
      'and the reader ends with retry later (4), naming a changing operation that may be running and the remedy, a re-run once none runs;',
      f'and the reader ends with retry later (4), naming a changing operation that may be running and the remedy, a re-run once none runs, and {UNSURE};')

# ======================================================================
# P-15: evidence version 4 binds the folder and link records by digest;
# every temporary first, the evidence renamed last. P-16: a folder or link
# record still disagreeing after the wait is left unapplied, part failed.
# ======================================================================

I.sub('IF-015', 'data',
      'the evidence format version, currently 3;',
      'the evidence format version, currently 4;')
I.sub('IF-015', 'data',
      'and was written both before and after folder records existed.',
      'and was written both before and after folder records existed.\n- DirXxH128=<32 hex digits or empty>, LinkXxH128=<32 hex digits or empty>: the content digest of the state\'s folder record and link record exactly as written, empty when the state has none; present from evidence version 4. Evidence of version 3 binds those two records by row count only.')
I.set('IF-015', 'version', '4')

L.sub('LLR-038', 'detail',
      'The evidence also states, for the folder and link records, whether the state has one and how many rows it holds.',
      "The evidence also states, for the folder and link records, whether the state has one, how many rows it holds and, from evidence version 4, the digest of its bytes, so the evidence binds all three files of a state (IF-015); a writer that rewrites only the record of contents computes those digests from the folder's own folder and link records.")

L.set('LLR-118', 'detail', """The writer writes every temporary of a publication before its first rename: the state's new folder record and link record where the state has them, the new record, then the evidence of those temporaries' exact bytes, each forced to stable storage. It then renames the folder record, then the link record (where the new state has none, the published one is deleted at that step instead, through the run folder for a backup), then the record, and the evidence last, so the evidence is the commit point for all three (LLR-162). The next run that holds the backup and has passed its admission checks, finding a state's record, folder record or link record disagreeing with the published evidence, and an evidence temporary that matches each of the three either as published or as a temporary lying beside that evidence temporary, publishes copies of those temporaries, the evidence last, through its own run folder and continues; it looks for that evidence temporary beside the record and in every run folder inside a reclaimed-leftover folder of that root, not only those its own reclaim moved. Leftover temporaries that match nothing are replaced. A folder or link record of the latest state that disagrees and cannot be identified this way is replaced by the run's own publication, which derives both from the source, and the run's record names it. A reader that meets a state's files between the renames waits for them to agree, and reports no damage while a writer holds the backup (LLR-123). A record of contents whose mismatch it cannot positively identify this way is refused as a damaged record, as leftovers require, with nothing changed.""")

L.sub('LLR-039', 'detail',
      "each route reads the evidence and compares the record's length, then its entry count, then its digest.",
      "each route reads the evidence and compares the record's length, then its entry count, then its digest, and, where the evidence binds them (IF-015 version 4), the folder record's and the link record's digests, a stated row count of 0 matching an absent file.")
L.sub('LLR-039', 'detail',
      'A length or digest mismatch, unparseable evidence, or a current-form record with no evidence is first waited out as LLR-123 states, since a writer publishes a record and its evidence by two renames: a pair that comes to agree proceeds. One that persists is refused',
      'A length or digest mismatch, unparseable evidence, a current-form record with no evidence, or a folder or link record disagreeing with its digest is first waited out as LLR-123 states, since a writer publishes those files and their evidence by separate renames: a set that comes to agree proceeds. A folder or link record that still disagrees while the record of contents agrees refuses nothing: every file is restored, and that record is left unapplied and reported, part failed (1), as LLR-143 and LLR-144 state. A record of contents whose mismatch persists is refused')
L.sub('LLR-039', 'dimensions', '; @pairwise',
      '; differing=set{record,folder-record,link-record}; evidence_version=set{3,4}; strict=bool; @pairwise')

L.sub('LLR-123', 'detail',
      'Where a record and its evidence disagree, as a writer shows them between the two renames that publish them (LLR-118), the reader reads both again every 2 seconds until they agree or 60 seconds pass; a pair that comes to agree is read normally. Where they still disagree when the wait ends, the reader tests',
      'Where a record, its folder record or its link record disagrees with its evidence, as a writer shows them between the renames that publish them (LLR-118), the reader reads them again every 2 seconds until they agree or 60 seconds pass; a set that comes to agree is read normally. Where only the folder or link record still disagrees when the wait ends, the record of contents agreeing, the reader reads the state from its record of contents and reports that folder or link record as disagreeing, a restore leaving it unapplied as LLR-143 and LLR-144 state. Where the record of contents still disagrees when the wait ends, the reader tests')
L.sub('LLR-123', 'dimensions', 'pair=set{agrees,agrees-within-wait,still-differs};',
      'pair=set{agrees,agrees-within-wait,still-differs}; differing=set{record,folder-record,link-record};')

L.sub('LLR-143', 'detail',
      'and that record is missing, malformed or holds fewer rows than the evidence states, every file is still restored, the folder metadata not applied (empty folders not recreated, attributes not applied) is named, and the restore ends part failed (1);',
      "and that record is missing, malformed, holds fewer rows than the evidence states or, where the evidence binds it by digest (IF-015 version 4), still disagrees with that digest after the restore's wait (LLR-123), every file is still restored, the folder metadata not applied (empty folders not recreated, attributes not applied) is named with its cause, a damaged folder record or a publication that may be in progress, which a later restore applies once it settles, and the restore ends part failed (1);")
L.sub('LLR-143', 'dimensions', 'malformed,short}', 'malformed,short,digest-differs}')

L.sub('LLR-144', 'detail',
      'and that record is missing, malformed or holds fewer rows than the evidence states, every file is still restored,',
      "and that record is missing, malformed, holds fewer rows than the evidence states or, where the evidence binds it by digest, still disagrees with that digest after the restore's wait (LLR-123), every file is still restored,")

L.sub('LLR-040', 'detail',
      "a current-form state's folder record or link record missing, malformed or short of its stated rows, or a file's time missing or malformed, as some part failed (1);",
      "a current-form state's folder record or link record missing, malformed, short of its stated rows or, past the restore's wait, disagreeing with its digest in the evidence, or a file's time missing or malformed, as some part failed (1);")

R.sub('SR-040', 'acceptance_criteria',
      "a current-form state whose folder record or a file's recorded time is missing or malformed is some part failed (1),",
      "a current-form state whose folder record or a file's recorded time is missing or malformed, or whose folder record disagrees with its completeness evidence, is some part failed (1),")

# The kit before the records (coordinator call).
L.sub('LLR-007', 'detail',
      'Each run places the current restore kit in the latest state, and each saved state is published',
      "Each run places the current restore kit in the latest state before it publishes the latest state's new records (LLR-162), and each saved state is published")
L.sub('LLR-150', 'detail',
      'it publishes the new latest record; and only then places',
      "it places the latest state's kit and publishes the latest state's new records (LLR-118); and only then places")

# ======================================================================
# R3G-001: a prepared folder is recognised complete or not.
# R3G-002: the owner record's deletion entry in an ownerless run folder.
# ======================================================================

L.sub('LLR-088', 'detail',
      'a run folder that is empty or holds only its own location record;',
      "a run folder holding nothing but, at most, its own location record and the owner record's deletion entry (LLR-162);")
L.sub('LLR-088', 'detail',
      "and the folder of a saved state being prepared, recognised positively: it holds no stored object and nothing outside its closed set (the kit's name set, the record of contents, its evidence, the folder record, the link record and their publication temporaries), its record of contents, folder record and link record are each byte-identical to the backup root's file of the same name, and its evidence is valid and matches its own record of contents. The evidence's bytes are not compared, since the writer writes that evidence for the staged record (LLR-038).",
      "and the folder of a saved state being prepared, complete or not, recognised positively: it holds no stored object and nothing outside its closed set (the kit's name set, the record of contents, its evidence, the folder record, the link record and their publication temporaries); each of its record of contents, folder record and link record present under its own name is byte-identical to the backup root's file of that name; and its evidence, where present under its own name, is valid for its own record of contents and binds its own folder and link records as present. Its temporaries are not compared, since each file is written at its temporary and renamed into place, so a kill leaves partial bytes only there; nor are the evidence's bytes, since the writer writes that evidence for the staged record (LLR-038).")
L.sub('LLR-088', 'detail',
      'a run folder holding anything but its own location record beside no usable run identity, a prepared folder whose record copies differ from the published latest state\'s, whose evidence fails, or that holds a stored object,',
      "a run folder holding anything but its own location record and the owner record's deletion entry beside no usable run identity, a prepared folder whose whole record copies differ from the published latest state's, whose whole evidence fails, or that holds a stored object or anything outside its closed set,")
L.sub('LLR-088', 'rationale',
      'counting those folders as content lost because the kill would then wedge the store although it left nothing to keep.',
      'counting those folders as content lost because the kill would then wedge the store although it left nothing to keep. A kill while the prepared folder is being filled, or between the owner record\'s deletion and its purge, likewise leaves nothing to keep, and requiring a complete prepared folder lost for the same reason; LLR-162 enumerates every such shape.')

L.sub('LLR-150', 'detail',
      'A kill while the saved state is still being prepared leaves a folder holding no stored object, whose record copies are byte-identical to the published latest state\'s and whose evidence, written for its own record (LLR-038), matches that record, which the next run recognises as holding no content (LLR-088).',
      "A kill while the saved state is still being prepared, each of its files written at its temporary and renamed into place, leaves a folder holding no stored object and part or all of its closed set, each whole record copy byte-identical to the published latest state's and any partial file only in its temporary, which the next run recognises as holding no content, complete or not (LLR-088).")

L.sub('LLR-017', 'dimensions', 'prepared-matching,', 'prepared-matching,prepared-partial,')
L.sub('LLR-017', 'dimensions', 'deletion-unique,', 'deletion-unique,owner-record-deletion,')

L.sub('LLR-124', 'detail',
      'complete any interrupted publication the classification identified from a temporary in a moved folder, by copying',
      'complete any interrupted publication the classification identified from a temporary in a moved folder, or in any reclaimed-leftover folder of that root (LLR-118), by copying')

I.sub('IF-033', 'data',
      'for a record, its evidence, the run-state record or a kit file',
      'for a record of contents, its evidence, the folder record, the link record, the run-state record or a kit file')
I.sub('IF-033', 'data',
      'the kit (IF-019) and their publication temporaries;',
      'the kit (IF-019) and their publication temporaries, each file written at its temporary and then renamed into place, the evidence after the record copies;')
I.set('IF-033', 'version', '4')

# ======================================================================
# R3G-004: behaviour out of the forms.
# ======================================================================

I.sub('IF-009', 'data',
      'A run writes its own record as backup-<RunId>.log in the saved-state root\'s run folder (IF-033), RunId as in its owner record, and publishes it at its end by renaming it to backup.log, replacing the one before.',
      "A run's record in progress is backup-<RunId>.log in the saved-state root's run folder (IF-033), RunId as in its owner record; once published, it is backup.log.")

I.set('IF-044', 'data', """Request: each staging area as read, the saved-state root's and the backup root's: whether it exists and whether it is a link; its listing (entry names), with the listing of each run folder in it, or unreadable; its own modification time and age, or unreadable; the form of each entry of a run folder (IF-033), with, for an entry being deleted, whether a published folder holds an object of its stored name or no published record names it, and, for a prepared saved-state folder, whether it holds a stored object or any file outside its closed set, whether each of its record of contents, folder record and link record present under its own name is byte-identical to the backup root's file of that name, and whether its evidence, where present under its own name, is valid for its own record of contents and binds its own folder and link records; the owner record (IF-033) as read, one of absent, parsed, unparseable or of an unknown schema (its bytes readable), or unreadable after three reads, with its run identity where it carries a RunId in canonical form, and its modification time and age where readable; and optionally a second sample of the owner record's modification time.
Answer: one verdict, with the evidence it rests on:
- Empty: no owner record, nothing holding content, the areas stale;
- EmptyFresh: no owner record, nothing holding content, an area fresh;
- OwnerStale: an owner record proven dead, nothing else holding content;
- OwnerLive: an owner record not proven dead;
- PruneHeld: a removal's unfinished work;
- HoldsContent: an entry holding content;
- Indeterminate: a staging area that is a link, or evidence that could not be read.
Which entries hold no content, and which observations give which verdict, are decided by the leftover-classification requirements.""")
I.set('IF-044', 'version', '4')

# ======================================================================
# SR-144: "in the store", matching P-09 (a).
# ======================================================================

R.sub('SR-144', 'requirement', 'shall change no file its successor wrote or published',
      'shall change no file in the store that its successor wrote or published')

# ======================================================================
# The staging sequence, enumerated (R3G-001 and R3G-002 as a class).
# ======================================================================

L.add_row('LLR-088', 'design', 'LLR-162', [
    ('title', "Every kill point of a backup's staging sequence leaves a listed shape with one verdict"),
    ('parent', 'LLR-088'),
    ('constrains', 'IF-033'),
    ('detail', """A backup changes its staging areas and the store only by the steps S01 to S26 below, in this order (LLR-161, LLR-150, LLR-118, LLR-125), steps S07 and S08 repeating for each new stored object, S17 to S19 for each earlier content, S21 and S22 for each folder the collapse touches, S09, S10 and S17 to S19 only in a run that keeps a saved state; a reclaim (LLR-124) changes them only by the steps R1 to R5. A kill at any point lies at one of these steps or between two of them, so the table is closed. Each row gives what a kill there leaves beyond the published store, and the verdict the next run (once it holds the claim, LLR-017) and a reader reach. "No content" means every leftover entry holds no content (LLR-088): the next run is refused as busy (4) while the owner record, or with none ("ownerless") the areas' own times, is fresh or not yet confirmed stale, and reclaims the leftovers once the owner is proven dead (LLR-080) or, ownerless, the areas are stale. A leftover shape this table does not list is content and refuses (2).

| Step | A kill after or during | Leftover shape | Verdict |
|---|---|---|---|
| S01 | creating the saved-state root's staging area | that area, empty; no owner record | no content, ownerless |
| S02 | creating the run folder in it | that area holding one empty run folder | no content, ownerless |
| S03 | creating the backup root's staging area, then its run folder | as S02, in one root or both | no content, ownerless |
| S04 | the owner record's exclusive create, before its content is whole | a torn owner record with no usable run identity, beside empty run folders | no content, judged by the record's time with the 1800-second floor |
| S05 | the owner record written, its first touch made or not | the owner record beside empty run folders | no content |
| S06 | opening the location record in the saved-state root's run folder | as S05, with that location record | no content; the reclaim keeps the location record readable (LLR-124) |
| S07 | writing or checking a new stored object's temporary in the backup root's run folder | a stored-object temporary, whole or partial | no content |
| S08 | renaming a new stored object out | a published object that no record names | nothing in staging; no state needs the object, and a later publication at its name replaces it (LLR-117) |
| S09 | creating the prepared saved-state folder in the saved-state root's run folder, or writing any of its files (record copies first, then evidence written for them, the kit in any order, each file at its temporary and then renamed into place) | a prepared folder holding part or all of its closed set: whole record copies byte-identical to the backup root's files, whole evidence valid for the folder's own records, kit files, and at most one partial file, in its temporary | no content, complete or not (LLR-088) |
| S10 | renaming the prepared folder out to its saved-state name | a published saved state equal to the latest state; the run folder holding at most the location record | no content; every state restores; the next run keeps that saved state as its own rather than adding another (LLR-150) |
| S11 | placing the latest state's kit, between two kit files | the previous records beside a kit of two revisions; a kit file's temporary | no content; a restore of the latest state is refused as LLR-159 states until the next run places the whole kit again |
| S12 | writing the latest state's publication temporaries (folder record, link record, record of contents, then the evidence of all three), each forced to stable storage | publication temporaries | no content; the latest state is the pre-run tree |
| S13 | renaming the new folder record out, or deleting the published one through the run folder where the new state has none | the folder record new; the record of contents and the evidence old; the remaining temporaries | no content; a restore of the latest state restores the old files and leaves the folder record unapplied, part failed (1, LLR-143); the next run rolls the publication forward from the evidence temporary (LLR-118) |
| S14 | the same for the link record | as S13, with the link record new | as S13, the links not rebuilt (LLR-144) |
| S15 | renaming the new record of contents out | the record new, the evidence old; the evidence temporary | no content; a reader waits, then refuses (3, or 4 where the claim is held or cannot be tested, LLR-039); the next run rolls forward (LLR-118) |
| S16 | renaming the evidence out | the post-run latest state | nothing in staging from this publication |
| S17 | writing or checking a copy of earlier content, carrying the saved state's name, in the saved-state root's run folder | a stored-object temporary, whole or partial | no content |
| S18 | publishing that copy into the saved state | the content in both the saved state and the backup root | no content; a duplicate the collapse removes (LLR-026) |
| S19 | renaming the backup root's copy into its run folder as an entry being deleted | an entry being deleted whose stored name the saved state holds | no content |
| S20 | writing or publishing the run-state record through the backup root's run folder | its publication temporary, or the record whole, old or new (LLR-028) | no content |
| S21 | the collapse rewriting a folder's record of contents and its evidence through the run folder of that folder's root | as S12, S15 or S16, for that folder | as those steps, for that folder's state |
| S22 | the collapse renaming a redundant copy into a run folder as an entry being deleted | an entry being deleted whose stored name the kept copy's folder holds | no content |
| S23 | publishing the location record out of the saved-state root's run folder | that run folder empty, or still holding the record where its publication failed | no content |
| S24 | emptying and deleting the backup root's run folder, then its staging area | the owner record; the saved-state root's area with its run folder; the backup root's area holding an empty run folder, empty, or gone | no content |
| S25 | renaming the owner record into the saved-state root's run folder as an entry being deleted | no owner record; a run folder holding the owner record's deletion entry, with the location record where its publication failed | no content, ownerless (LLR-088) |
| S26 | purging that entry, then deleting the run folder, then the staging area | an ownerless area holding an empty run folder, or one holding the kept location record, or an empty area, or nothing | no content, ownerless |
| R1 | moving the backup root's staging area aside, before the saved-state root's | a reclaimed-leftover folder at the backup root; the saved-state root's area as the dead run left it | the next run classifies and reclaims the saved-state root's area as before, and looks for an interrupted publication's evidence temporary in every reclaimed-leftover folder of that root (LLR-118) |
| R2 | moving the saved-state root's area aside, before fresh areas exist | no staging area; reclaimed-leftover folders | nothing to classify; the next run starts afresh and rolls forward as R1 states |
| R3 | creating the fresh areas, run folders and owner record | as S01 to S06 | as those steps |
| R4 | completing an interrupted publication from a moved folder through this run's own run folder | as S12 to S16 | as those steps |
| R5 | deleting the recognised entries of a moved folder | a reclaimed-leftover folder, partly emptied | outside every staging area: never classified, never blocking, belonging to no state; a location record in it stays readable |

A run's cleanup after an early failure (LLR-124) leaves only the shapes of S23 to S26. A write landing through a handle already open (the owner record's refresh, the location record) changes no shape. Where the published evidence is of version 3, which binds the folder and link records by row count only, a kill at S13 or S14 in the first run that writes version 4 is seen only where a count differs; from then on the digests show it."""),
    ('dimensions', 'step=set{S01,S02,S03,S04,S05,S06,S07,S08,S09,S10,S11,S12,S13,S14,S15,S16,S17,S18,S19,S20,S21,S22,S23,S24,S25,S26,R1,R2,R3,R4,R5}; interrupt=set{kill,power-loss}; roots=set{same-volume,different-volumes}; next=set{backup-while-fresh,backup-once-stale,restore-latest,restore-saved}; @pairwise'),
    ('rationale', """A rule per leftover shape, stated in prose, cannot show that every kill point is covered, and each point it misses turns a harmless kill into a permanent refusal; one table over the steps can be checked row by row, and each row is a test case. Listing only the shapes that hold no content, and treating every other shape as content, keeps the table fail-closed."""),
    ('status', 'Drafted'),
])

for name, doc in (('interfaces.toml', I), ('low-level-requirements.toml', L),
                  ('system-requirements.toml', R)):
    (REQ / name).write_bytes(doc.text().encode('utf-8'))
print('carriers written')
