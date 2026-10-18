# Round 3f: applies full round 3, the last (r3-dispositions.md, "Convergence
# check 2 and full round 3 (the last)", R3E-001..R3E-006) to the design tier
# and the named SR rows. Reads every carrier from git HEAD, so re-running it
# reproduces the result. Writes docs/requirements/{components,interfaces,
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


C = Doc(head('components.toml'))
I = Doc(head('interfaces.toml'))
L = Doc(head('low-level-requirements.toml'))
R = Doc(head('system-requirements.toml'))

# ======================================================================
# R3E-001: the location record comes inside the fence. Each run writes its
# own record in its run folder and publishes it by rename at its end; the
# change-detection state and the views are outside the store and outside
# SR-144's guarantee.
# ======================================================================

I.sub('IF-009', 'data',
      "- one location record per configured location, named backup.log in that location's saved-state root (IF-013).",
      "- one location record per configured location: backup.log in that location's saved-state root (IF-013), the record of the last run that published one there. A run writes its own record as backup-<RunId>.log in the saved-state root's run folder (IF-033), RunId as in its owner record, and publishes it at its end by renaming it to backup.log, replacing the one before. The record of a run killed or reclaimed keeps its run name: in its run folder, and after a reclaim among that root's reclaimed leftovers, at Temp.stale-<yyyyMMddTHHmmssZ>-<8 hex digits>/Run-<RunId>/backup-<RunId>.log.")
I.sub('IF-009', 'rationale',
      'and the set is closed so a host can match every refusal.',
      'and the set is closed so a host can match every refusal. One location record written in place lost because a run that lost its claim could still append to the record its successor writes; a record per run, reachable only through that run\'s own folder until it is published, cannot be.')
I.set('IF-009', 'version', '2')

I.sub('IF-013', 'data', '- backup.log: the location record (IF-009).',
      "- backup.log: the location record of the last run that published one (IF-009); a run's record in progress is backup-<RunId>.log in its run folder (IF-033).")

I.sub('IF-033', 'data',
      "holding copies of the backup root's record of contents, its completeness evidence, the folder record and the link record where present, the kit (IF-019) and their publication temporaries;",
      "holding a copy of the backup root's record of contents, completeness evidence written for that copy (IF-015), copies of the folder record and the link record where present, the kit (IF-019) and their publication temporaries;\n- in the saved-state root's run folder only: backup-<RunId>.log, the run's location record (IF-009), RunId as in the run folder's name;")
I.set('IF-033', 'version', '3')

# IF-044: R3E-001 (the location record), R3E-002 (an owner record with no
# usable run identity) and R3E-003 (the prepared folder's evidence).
I.set('IF-044', 'data', """Request: each staging area as read, the saved-state root's and the backup root's: whether it exists and whether it is a link; its listing (entry names), with the listing of each run folder in it, or unreadable; its own modification time and age, or unreadable; the form of each entry of a run folder (IF-033), with, for an entry being deleted, whether a published folder holds an object of its stored name or no published record names it, and, for a prepared saved-state folder, whether it holds a stored object or any file outside its closed set, whether its record of contents, folder record and link record are each byte-identical to the backup root's file of the same name, and whether its evidence parses and matches its own record of contents; the owner record (IF-033) as read, one of absent, parsed, unparseable or of an unknown schema (its bytes readable), or unreadable after three reads, with its run identity where it carries a RunId in canonical form, and its modification time and age where readable; and optionally a second sample of the owner record's modification time.
Answer: one verdict, with the evidence it rests on:
- Empty: no entry but entries holding no content, no owner record, the areas' own times stale;
- EmptyFresh: the same, an area's own time fresh;
- OwnerStale: the owner record readable, a torn one included, older than its stale time and unchanged at the second sample, every other entry holding no content;
- OwnerLive: the owner record readable and fresh, future-dated, or not yet confirmed stale;
- PruneHeld: a removal's marker;
- HoldsContent: any other entry;
- Indeterminate: an area is a link, or a listing, an area's own time or the owner record could not be read.
Entries holding no content: the owner record; a run folder named for the owner record's run identity; where there is no owner record, or it carries no RunId in canonical form, a run folder that is empty or holds only its own location record; and in a run folder, the run's location record, a publication temporary, a stored-object temporary, an entry being deleted whose stored name a published folder holds or no published record names, and a prepared saved-state folder holding no stored object and nothing outside its closed set, whose record of contents, folder record and link record are byte-identical to the backup root's and whose evidence is valid and matches its own record of contents.""")
I.set('IF-044', 'version', '3')

L.sub('LLR-161', 'detail',
      'creates each run folder only inside a staging area it has just created, and never re-creates either.',
      'creates each run folder only inside a staging area it has just created, and never re-creates either; a kill between these and the owner record\'s write leaves empty run folders beside no owner record or a torn one, which hold no content (LLR-088).')
L.sub('LLR-161', 'detail',
      'and the owner record is deleted the same way at the end.',
      "and the owner record is deleted the same way at the end. The run's location record is written in the saved-state root's run folder from the moment the location has passed its admission checks, and is published, on every ending but a lost claim, by renaming it out to the location record's name, replacing the record of the run before; a failed publication leaves it in that run folder, which the run then keeps with its staging area, naming it on the console and in the global record, its outcome unchanged.")
L.sub('LLR-161', 'dimensions',
      'change=set{stored-object,record,evidence,run-state,kit-file,saved-state,earlier-content,delete,owner-record}',
      'change=set{stored-object,record,evidence,run-state,kit-file,saved-state,earlier-content,delete,owner-record,location-record}')

L.set('LLR-125', 'detail', """From the moment its owner record is written until its staging areas are removed, a backup changes the store only by renames into or out of its own run folders (LLR-161), its location record included: the run writes that record in its run folder and publishes it by rename at its end. A successor's reclaim moves those folders aside (LLR-124), so every rename the former owner then issues names a path that no longer exists and fails by itself: it publishes nothing, deletes nothing and replaces nothing, with no check between a test and a write to race. Before each step and each stored object the run also re-reads its owner record, comparing the run identity, as an early exit. A mismatch, a rename that fails because its run folder is gone, or an owner record that stays unreadable after three reads about 300 ms apart means the claim was lost: the run stops at once, cleans up nothing, publishes no location record, ends the location with part failed (1), and reports that its work was reclaimed on the console and in the global record; its own location record stays among the leftovers its successor moved aside. A write through a handle the run already holds open (its owner record's refresh, its location record, a temporary being written) is the one write that can land after a reclaim, and it lands in those leftovers, never in a file the successor wrote or published. The owner record stays in place until the run-state write, the collapse and the views have ended: the saved state is prepared in the run folder and published by moving its folder out (LLR-150), so the owner record never enters a saved state. The change-detection state and the views lie outside the store and pass through no run folder; the early exit is all that guards them, and both are derived: the next run reconciles the change-detection state with the backup's latest record (LLR-114) and rebuilds a view whose stamp differs from it (LLR-061). The run's last steps stop its refresh, publish its location record out of the saved-state root's run folder, empty and delete the backup root's run folder and then that staging area, delete its owner record through the saved-state root's run folder, and then delete that run folder and staging area, each folder non-recursively; where the location record's publication fails, that run folder and its staging area are kept with the record in them (LLR-161).""")
L.sub('LLR-125', 'dimensions',
      'collapse-record-rewrite,collapse-delete,owner-record-delete}',
      'collapse-record-rewrite,collapse-delete,location-record-publication,owner-record-delete}')
L.sub('LLR-125', 'rationale',
      'Deleting the owner record when the saved state is published lost',
      "Writing the location record in place lost because a run resumed after a reclaim could still append to the record its successor writes. Deleting the owner record when the saved state is published lost")

R.set('SR-144', 'acceptance_criteria', """A run suspended while it holds its claim, for longer than the stale time, keeps the backup held: a successor is refused as busy (value 4, SR-085) until the claim is released, and the store is unchanged by it. A run on another host or container whose claim the successor does not see, suspended for longer than the stale time while the successor reclaims its unfinished work and completes, then resumed, changes no file of the store the successor wrote or published, the location's record included, publishes nothing, writes nothing in the store outside the leftovers the successor set aside, every state restores as the successor left it, and the resumed run ends with the part-failed outcome (value 1) and a record saying its work was reclaimed. The change-detection state and the views lie outside the store and outside this guarantee: they are derived, and the next run reconciles them from the backup's own record.""")

L.sub('LLR-095', 'detail',
      "A location's record is truncated only once that location holds the backup and has passed its admission checks; a refusal before that point, on the claim or at admission, reaches the console and the global record only, and the location's record, which lies in the store and belongs to the live holder or to the last run, is left unchanged.",
      "A location's record is never truncated or appended in place: a run creates its own record in its run folder only once that location holds the backup and has passed its admission checks, and replaces the location's record only by publishing its own at its end (LLR-161); a refusal before that point, on the claim or at admission, reaches the console and the global record only, and the location's record, which lies in the store and is the last published run's, is left unchanged.")

L.sub('LLR-091', 'detail',
      "nothing is appended to the location's record, which lies in the store (LLR-095).",
      "the location's record, which lies in the store, is left unchanged (LLR-095).")

L.sub('LLR-124', 'detail',
      'and delete by exact name each entry LLR-088 recognises (the files of a prepared saved-state folder before that folder, the owner record last) and each folder non-recursively.',
      "and delete by exact name each entry LLR-088 recognises but a former run's location record (the files of a prepared saved-state folder before that folder, the owner record last) and each folder non-recursively. A former run's location record is kept where it lies, with the folders that hold it, so it stays readable: that moved folder is named in the run's record and the run completes (0).")
L.sub('LLR-124', 'dimensions',
      'contents=set{none,temporaries,entry-being-deleted,prepared-folder,interrupted-publication}',
      'contents=set{none,temporaries,entry-being-deleted,prepared-folder,interrupted-publication,location-record}')

C.sub('CMP-006', 'notes',
      "the per-location record lives in the location's saved-state root;",
      "the per-location record is truncated and appended in place in the location's saved-state root, outside any run folder;")

L.sub('LLR-061', 'detail',
      'so a run that changed the latest state rebuilds it and one that did not may skip it;',
      "so a run that changed the latest state rebuilds it and one that did not skips it only where the view's stamp matches the latest record's rows;")

# ======================================================================
# R3E-002: an owner record torn at creation, beside empty run folders.
# R3E-003: a prepared saved state's evidence is its own; recognised by
# record bytes plus valid matching evidence.
# ======================================================================

L.sub('LLR-080', 'detail',
      'a torn record, or one of an unknown schema, falls back to its modification time with the 1800-second floor.',
      'a torn record, or one of an unknown schema, falls back to its modification time with the 1800-second floor. A record torn at its creation carries no usable run identity; the empty run folders its run created first hold no content (LLR-088), so once its death is proven the creation it interrupted is reclaimed like any other dead run\'s leftovers.')

L.set('LLR-088', 'detail', """In a backup's staging areas, these entries hold no content, each matched by its exact form with letter case (IF-033): the owner record; a run folder named for the owner record's run identity; where there is no owner record, or the owner record carries no usable run identity (torn at its creation, or of an unknown schema without a RunId in canonical form), a run folder that is empty or holds only its own location record; and, in a run folder, the run's location record, a publication temporary, a stored-object temporary, an entry being deleted whose stored name a published folder still holds or no published record names, and the folder of a saved state being prepared, recognised positively: it holds no stored object and nothing outside its closed set (the kit's name set, the record of contents, its evidence, the folder record, the link record and their publication temporaries), its record of contents, folder record and link record are each byte-identical to the backup root's file of the same name, and its evidence is valid and matches its own record of contents. The evidence's bytes are not compared, since the writer writes that evidence for the staged record (LLR-038). Any other entry is content: an unrecognised file or folder, a run folder of another run identity beside an owner record that carries one, a run folder holding anything but its own location record beside no usable run identity, a prepared folder whose record copies differ from the published latest state's, whose evidence fails, or that holds a stored object, and an entry being deleted whose content no published folder holds although a record names it. Areas holding only entries that hold no content classify by the owner record alone, and with no owner record by their own modification times. Once the owner is proven dead (LLR-080), they are reclaimable (LLR-124), the prepared folder included. In the backup root and every saved state, a publication temporary beside a record, left by a removal, a repair or an earlier release, is an infrastructure name only at the root of the folder that owns the record, never backed up, reported or found by the check; a same-named file deeper in a tree is ordinary content.""")
L.set('LLR-088', 'rationale', """A killed backup leaves temporaries, at most one entry it was deleting, the saved state it was preparing and its own location record; counting them as content turns every such kill into a permanent refusal, while recognising them by name alone would let an unrelated folder or a unique stored object pass as debris. A prepared saved state holds only copies of the published latest state's records, evidence written for its own record, and the kit, so comparing the record copies with the published files and checking the evidence against its own record recognises it; comparing the evidence's bytes lost because evidence written for the copy carries its own written time. A creation killed between the owner record's create and its write leaves a torn record beside empty run folders; counting those folders as content lost because the kill would then wedge the store although it left nothing to keep.""")

L.sub('LLR-017', 'dimensions',
      'run_folder_entry=set{none,publication-temporary,object-temporary,deletion-with-published-twin,deletion-unreferenced,deletion-unique,prepared-matching,prepared-differing,prepared-holding-object,unknown}',
      'run_folder_entry=set{none,location-record,publication-temporary,object-temporary,deletion-with-published-twin,deletion-unreferenced,deletion-unique,prepared-matching,prepared-differing,prepared-evidence-fails,prepared-holding-object,unknown}; run_folder=set{owner-identity,other-identity,beside-no-identity,beside-no-owner}')

L.sub('LLR-150', 'detail',
      'it prepares the saved state (its record, evidence, folder and link records and kit)',
      'it prepares the saved state (a copy of the latest record, evidence written for that copy, copies of the folder and link records, and the kit)')
L.sub('LLR-150', 'detail',
      "A kill while the saved state is still being prepared leaves a folder holding no stored object, whose record files match the published latest state's, which the next run recognises as holding no content (LLR-088).",
      "A kill while the saved state is still being prepared leaves a folder holding no stored object, whose record copies are byte-identical to the published latest state's and whose evidence, written for its own record (LLR-038), matches that record, which the next run recognises as holding no content (LLR-088).")

L.sub('LLR-038', 'detail',
      'A saved state\'s evidence is its own, written when its record is written, and evidence is never copied from another folder.',
      'A saved state\'s evidence is its own, written when its record is written, the record a backup stages for the saved state it prepares included, and evidence is never copied from another folder.')

# ======================================================================
# R3E-004: a claim that cannot be tested is indeterminate: a still-mixed
# kit then ends with 4; only positive evidence that no refresh holds the
# claim gives 3.
# ======================================================================

L.sub('LLR-159', 'detail',
      "not held, the kit is what an interrupted refresh left, and the restore is refused with the damaged-record value (3), naming the files that differ and the remedy, re-running the kit refresh, which completes the kit. Where the claim cannot be tested (the route has no lock tool, or the claim file cannot be reached), the restore is refused the same way with 3, its message adding that a refresh may still be running.",
      "not held, which is positive evidence that no refresh is running, the kit is what an interrupted refresh left, and the restore is refused with the damaged-record value (3), naming the files that differ and the remedy, re-running the kit refresh, which completes the kit. Where the claim cannot be tested (the route has no lock tool, or the claim file cannot be reached), whether a refresh is running is unknown, and the restore ends with retry later (4), naming the kit refresh, the files that differ and the remedy: where no refresh is running, re-run it.")
L.sub('LLR-159', 'rationale',
      'Testing the claim decides between the two,',
      'Testing the claim decides between the two; treating a claim that cannot be tested as free lost because a live refresh would then be reported as damage on every route that cannot test it, while retry later naming the remedy lets a person finish an interrupted refresh with no tool added to the shell route\'s floor;')

L.sub('LLR-130', 'detail',
      'which, with no holder of the claim, refuses it as damaged record (3) naming a re-run of the kit refresh (LLR-159); re-running the refresh completes the kit.',
      'which, with positive evidence that no operation holds the claim, refuses it as damaged record (3) naming a re-run of the kit refresh, and where the claim cannot be tested ends with retry later (4) naming the refresh and that remedy (LLR-159); re-running the refresh completes the kit.')

L.sub('LLR-040', 'detail',
      'a damaged record, a kit whose files are of two revisions with no refresh running included, as 3;',
      "a damaged record, as 3, a kit whose files are of two revisions, or a record that still disagrees with its evidence after the restore's wait, included where the claim's test shows no changing operation holds it;")
L.sub('LLR-040', 'detail',
      "and a kit refresh still running past the restore's wait, as retry later (4);",
      "and a kit still of two revisions, or a record still disagreeing with its evidence, past the restore's wait while the claim is held or cannot be tested, as retry later (4);")
L.sub('LLR-040', 'dimensions', 'host_fault=bool;', 'host_fault=bool; claim_test=set{not-needed,held,free,untestable};')

# ======================================================================
# R3E-005: a reader that finds a record and its evidence disagreeing waits
# for the pair to settle, up to 60 s; past the bound, the claim test
# decides 4 (held or untestable) or 3 (free).
# ======================================================================

L.sub('LLR-123', 'detail',
      "Where a record's evidence changes while the reader reads that record, the reader reads the record and its evidence again, up to three times, before it reports the record as damaged. Each therefore completes with the outcome it would have against a quiet store, for every state the concurrent operation does not remove, while a backup, a removal, a repair or a kit refresh holds the backup.",
      "Where a record and its evidence disagree, as a writer shows them between the two renames that publish them (LLR-118), the reader reads both again every 2 seconds until they agree or 60 seconds pass; a pair that comes to agree is read normally. Where they still disagree when the wait ends, the reader tests whether the backup's claim is held, as LLR-159 does: held, or not testable, a writer may still be publishing, and the reader ends with retry later (4), naming a changing operation that may be running and the remedy, a re-run once none runs; not held, which is positive evidence that no writer holds the backup, the record is damaged (3). Each therefore completes with the outcome it would have against a quiet store, for every state the concurrent operation does not remove, while a backup, a removal, a repair or a kit refresh holds the backup, unless a publication outlasts the wait, which ends with 4.")
L.sub('LLR-123', 'dimensions', 'rereads=range[0..3];',
      'pair=set{agrees,agrees-within-wait,still-differs}; claim=set{held,free,untestable}; wait_seconds=range[0..60];')
L.sub('LLR-123', 'rationale',
      'Pinning a read generation',
      'Reporting damage after a fixed number of re-reads lost because a writer descheduled between its two renames outlasts any count, and waiting with no bound lost because real damage never settles. Pinning a read generation')

L.sub('LLR-118', 'detail',
      'leftover temporaries that match nothing are replaced.',
      'leftover temporaries that match nothing are replaced. A reader that meets the new record beside the old evidence between the two renames waits for the pair to agree, and reports no damage while a writer holds the backup (LLR-123).')
L.sub('LLR-118', 'dimensions', 'leftover=set{complete,torn,zero-length,none};',
      'leftover=set{complete,torn,zero-length,none}; observer=set{next-run,concurrent-reader};')

L.sub('LLR-039', 'detail',
      'A length or digest mismatch, unparseable evidence, or a current-form record with no evidence, is refused with the damaged-record value (3), the target absent or unchanged and no report written.',
      "A length or digest mismatch, unparseable evidence, or a current-form record with no evidence is first waited out as LLR-123 states, since a writer publishes a record and its evidence by two renames: a pair that comes to agree proceeds. One that persists is refused with the damaged-record value (3) where the claim's test shows no changing operation holds the backup, and ends with retry later (4), naming the remedy, where the claim is held or cannot be tested; either way the target is absent or unchanged and no report is written.")
L.sub('LLR-039', 'dimensions', 'state=set{latest,saved};',
      'state=set{latest,saved}; pair=set{agrees-within-wait,persists}; claim=set{held,free,untestable};')

L.sub('LLR-049', 'detail',
      "and a state's record that fails its completeness evidence after the re-reads a reader makes (LLR-123), reported once for that state, with no finding from its entries, the check continuing with the other states.",
      "and a state's record that still fails its completeness evidence when the wait a reader makes (LLR-123) ends with positive evidence that no other changing operation holds the backup, reported once for that state, with no finding from its entries, the check continuing with the other states. A state whose record still disagrees with its evidence while another operation holds the claim, or while the claim cannot be tested, is not checked: the check names it on the console and in its record as not settled and reports no finding for it.")
L.sub('LLR-049', 'detail',
      'The check reports damaged record (3) where any state\'s record fails its evidence, part failed (1) where there is any other finding, and complete (0) on a clean store; a missing backup root or a needed tool absent is a precondition not met (2), which takes precedence over 3, as 3 does over 1.',
      'The check reports damaged record (3) where any state\'s record fails its evidence, retry later (4) where a state was not checked because its record had not settled, part failed (1) where there is any other finding, and complete (0) on a clean store; a missing backup root or a needed tool absent is a precondition not met (2); 2 takes precedence over 3, 3 over 4, and 4 over 1.')
L.sub('LLR-049', 'dimensions', 'record-evidence-fails}',
      'record-evidence-fails,record-evidence-unsettled}; claim=set{held-by-other,free,untestable}')

R.sub('SR-106', 'acceptance_criteria',
      'each complete with their normal outcome against every complete state the running operation does not remove.',
      'each complete with their normal outcome against every complete state the running operation does not remove, save the bounded waits below.')
R.sub('SR-106', 'acceptance_criteria',
      'A check or the report that meets a saved state removed while it reads',
      "A reader that meets a state's record beside completeness evidence that does not match it waits a bounded time for the two to agree and then completes with its normal outcome, or, where they still disagree while a changing operation holds the backup or the claim cannot be tested, ends with retry later (value 4), a restore writing nothing. A check or the report that meets a saved state removed while it reads")
R.sub('SR-106', 'rationale',
      'and a refresh outlasting the wait is reported as retry later.',
      'and a refresh outlasting the wait is reported as retry later. A record and its completeness evidence are published by two steps, so a reader meeting the pair between them waits a bounded time rather than report damage, and a publication outlasting the wait is reported as retry later.')
R.sub('SR-106', 'permutations', 'kit=set{settled,mid-refresh};',
      'kit=set{settled,mid-refresh}; record=set{settled,mid-publication};')

# ======================================================================
# R3E-006: on a desktop the shell route offers the folder choice through
# the dialog providers; no provider -> typed prompt at a console, else 2
# naming the missing provider; console with no desktop -> typed prompt.
# ======================================================================

L.set('LLR-157', 'detail', """On a desktop, either route offers the folder choice (LLR-156) unless it is suppressed, by the no-dialog switch on the language-runtime route or by the no-dialog variable set to 1 on either route. The language-runtime route sees a desktop from the host session (IF-026); the shell route sees it from the host session or from the folder-choice switch, which declares one, as the macOS launcher passes it where the shell cannot see the desktop itself. With the folder choice suppressed, or no provider present, a restore with no target asks by typed prompt where an interactive console is present, and otherwise prints its usage and returns 2, naming the missing provider where none was present. With an interactive console and no desktop, either route asks by typed prompt. A typed answer is taken as LLR-156 takes a chosen folder: only one absolute path of an existing folder is a target, and an empty or other answer gives the usage and 2. A failed or cancelled folder choice gives no target and the usage and 2, never a typed prompt. Neither switch overrides a session in which nobody can answer: declared unattended, redirected or closed input, or neither a console nor a desktop, still gives the usage and 2, with no prompt and no dialog.""")
L.set('LLR-157', 'dimensions', 'route=set{language-runtime,shell}; no_gui=set{none,switch,variable}; pick_target=bool; session=set{unattended,redirected-input,console-only,console-and-desktop,desktop-only}; provider=set{present,none}; choice=set{chosen,cancelled,failed}; typed_answer=set{absolute-folder,empty,relative,not-a-folder}; @pairwise')
L.set('LLR-157', 'rationale', """A desktop user who wants the typed prompt, or a test with a display, needs a way to turn the dialog off, and a restore started by a script with no target must fail at once rather than open a dialog; a script's input is redirected or closed, so it is never prompted or shown a dialog, a scheduled job on a desktop machine included. Offering the shell route's folder choice only under its switch lost because a restorer at a desktop who starts the shell restorer would then be prompted where a folder choice is owed. Refusing a restore with no provider lost where a console can still take a typed answer; falling back to a prompt after a cancelled choice lost because the restorer has already declined.""")
L.set('LLR-157', 'title', 'The no-dialog switches and the folder-choice switch steer how the target is asked for, never past an unattended session')

L.set('LLR-073', 'detail', """When no target is given, the restore decides from the session alone, with every signal an input: no question when declared unattended, when input is redirected or closed, or with neither a console nor a desktop, in which case it prints its usage and returns 2 without asking anything; a typed prompt with an interactive console and no desktop, on either route; on a desktop, on either route, a folder choice from the provider LLR-156 picks, and where the folder choice is suppressed or no provider is present (LLR-157), a typed prompt with an interactive console, otherwise the usage and 2 naming the missing provider. A failed or cancelled folder choice gives no target: the restore prints its usage and returns 2, never falling back to a typed prompt or restoring into a default target.""")
L.sub('LLR-073', 'dimensions', 'choice=set{chosen,cancelled,failed,unavailable};',
      'choice=set{chosen,cancelled,failed,unavailable}; console_with_desktop=bool;')

# ======================================================================
# Consistency beyond the named rows (see r3f-change-log.md).
# ======================================================================

# The check's "not settled" entry needs a message kind (IF-009's list is closed).
I.sub('IF-009', 'data',
      '- Media measure not taken: <reason> | Extra skipped: <name>',
      '- Media measure not taken: <reason> | Extra skipped: <name>\n- Not checked: <saved-state folder name or latest> - record and evidence not settled while a changing operation may hold the backup')

# The macOS launcher's switch now declares a desktop to the shell route.
L.sub('LLR-074', 'detail',
      'passes the request for a folder choice to the shell route (LLR-157), which makes the choice,',
      'passes the folder-choice switch to the shell route, declaring the desktop the shell cannot see itself (LLR-157), and the shell route makes the choice,')

# A run's own cleanup publishes its location record before deleting its folders.
L.sub('LLR-124', 'detail',
      'deletes those through its run folders (LLR-161) with the owner record last, and otherwise keeps the folders.',
      'publishes its location record where it has one, deletes the rest through its run folders (LLR-161) with the owner record last, and otherwise keeps the folders.')

for name, doc in (('components.toml', C), ('interfaces.toml', I),
                  ('low-level-requirements.toml', L), ('system-requirements.toml', R)):
    (REQ / name).write_bytes(doc.text().encode('utf-8'))
print('carriers written')
