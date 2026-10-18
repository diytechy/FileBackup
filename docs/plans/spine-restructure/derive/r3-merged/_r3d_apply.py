# Round 3d: applies full round 2 (r3-dispositions.md, "Convergence check 1 and
# full round 2", R3C-001..R3C-008) to the design tier and the named SR rows.
# Reads every carrier from git HEAD, so re-running it reproduces the result.
# Writes docs/requirements/{components,interfaces,low-level-requirements,
# system-requirements}.toml.
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
# R3C-002 (+ R3C-005): one staging layout and one fence. Every change a
# backup makes to the store is a rename into or out of a run folder of its
# own, one in each root it changes; a reclaim moves those folders aside.
# ======================================================================

I.set('IF-033', 'title', 'Staging areas, run folders and owner record')
I.set('IF-033', 'data', """Temp at the saved-state root, and Temp at the backup root: the staging areas of the one changing operation holding the backup. The saved-state root's is the one a removal uses and the one holding the owner record; the backup root's is present only while a backup holds the backup.
While a backup holds it, the saved-state root's Temp contains RUN.inprogress, the owner record: a UTF-8 JSON object of schema version 1:
- SchemaVersion: integer, 1;
- Kind: string, backup;
- RunId: string, a fresh GUID per acquisition, in lowercase canonical form;
- StartedUtc: ISO-8601 time;
- HeartbeatIntervalSeconds: integer, 60;
- StaleAfterSeconds: integer, at least 1800;
- SetName, Host, ContainerId, BootId (strings) and Pid (integer): diagnostic, optional.
SchemaVersion, Kind, RunId, StartedUtc, HeartbeatIntervalSeconds and StaleAfterSeconds are required; a record with another SchemaVersion or Kind, or without a required field, is of an unknown schema. The record's modification time is part of it.
Each staging area of a backup contains that run's folder, Run-<RunId>, RunId as in the owner record.
While a removal holds it, the saved-state root's Temp contains PRUNE.inprogress, UTF-8 text holding the name of the saved-state folder being removed.
Entries of a run folder, a closed set:
- in the saved-state root's run folder only: the folder of the saved state being prepared, named as it will be published (IF-013), holding copies of the backup root's record of contents, its completeness evidence, the folder record and the link record where present, the kit (IF-019) and their publication temporaries;
- a publication temporary: <name>.tmp, for a record, its evidence, the run-state record or a kit file whose destination is <name> at the root of the folder holding the run folder's staging area; <saved-state folder name>.<name>.tmp for a destination in that saved state;
- a stored-object temporary: <stored name>.fb-<8 lowercase hex digits>.tmp, prefixed <saved-state folder name>. where its destination lies in a saved state;
- an entry being deleted: the name it had followed by .fb-deleted, prefixed <saved-state folder name>. where it came from a saved state.
Temp.stale-<yyyyMMddTHHmmssZ>-<8 hex digits>, beside either Temp: that root's reclaimed leftovers.""")
I.set('IF-033', 'rationale', "A dead run's leftovers must be told from a live run's by any later FileBackup, on any host or container sharing the store, from the disk alone, and a run that lost its claim must be unable to change anything its successor made; a process-identity check lost because a container shares neither process namespace nor host with the reader, and one fixed staging folder shared by every run lost because a reclaim could then not take a former owner's working folder away from it.")
I.set('IF-033', 'version', '2')

I.sub('IF-013', 'data', '- MANIFEST.csv.tmp, MANIFEST.csv.meta.tmp: publication temporaries;',
      "- MANIFEST.csv.tmp, MANIFEST.csv.meta.tmp: publication temporaries of a removal, a repair or an earlier release (a backup's lie in its run folder, IF-033);")
I.sub('IF-013', 'data', 'or by .fb-<8 lowercase hex digits>.tmp (any other writer);',
      "or by .fb-<8 lowercase hex digits>.tmp (an earlier release's; a backup's lie in its run folder, IF-033);")
I.sub('IF-013', 'data', '- the stored objects, flat at the root, named by IF-016;',
      '- the stored objects, flat at the root, named by IF-016;\n- Temp: the backup root\'s staging area (IF-033), present only while a backup holds the backup; Temp.stale-<yyyyMMddTHHmmssZ>-<8 hex digits>: its reclaimed leftovers;')
I.sub('IF-013', 'data', '- Temp: the staging area (IF-033);', "- Temp: the saved-state root's staging area (IF-033);")
I.set('IF-013', 'version', '3')

I.sub('IF-030', 'data', 'FileBackupState.json.tmp is its publication temporary.',
      "FileBackupState.json.tmp is its publication temporary, beside it, or in a backup's run folder (IF-033).")

I.set('IF-044', 'data', """Request: each staging area as read, the saved-state root's and the backup root's: whether it exists and whether it is a link; its listing (entry names), with the listing of each run folder in it, or unreadable; its own modification time and age, or unreadable; the form of each entry of a run folder (IF-033), with, for an entry being deleted, whether a published folder holds an object of its stored name or no published record names it, and, for a prepared saved-state folder, whether it holds a stored object or any file outside its closed set and whether each record file in it is byte-identical to the backup root's file of the same name; the owner record (IF-033) as read, one of absent, parsed, unparseable or of an unknown schema (its bytes readable), or unreadable after three reads, with its modification time and age where readable; and optionally a second sample of the owner record's modification time.
Answer: one verdict, with the evidence it rests on:
- Empty: no entry but entries holding no content, no owner record, the areas' own times stale;
- EmptyFresh: the same, an area's own time fresh;
- OwnerStale: the owner record readable, older than its stale time and unchanged at the second sample, every other entry holding no content;
- OwnerLive: the owner record readable and fresh, future-dated, or not yet confirmed stale;
- PruneHeld: a removal's marker;
- HoldsContent: any other entry;
- Indeterminate: an area is a link, or a listing, an area's own time or the owner record could not be read.
Entries holding no content: the owner record; a run folder named for the owner record's run identity, or, with no owner record, an empty one; and in a run folder, a publication temporary, a stored-object temporary, an entry being deleted whose stored name a published folder holds or no published record names, and a prepared saved-state folder holding no stored object, nothing outside its closed set, and record files byte-identical to the backup root's.""")
I.set('IF-044', 'version', '2')

I.set('IF-032', 'consumers', ['CMP-011', 'CMP-013', 'CMP-014', 'CMP-018'])

# --- LLR-125: the fence is the filesystem's
L.set('LLR-125', 'title', "A run whose claim was lost can change nothing more, because a reclaim takes its run folders away")
L.set('LLR-125', 'detail', """From the moment its owner record is written until its staging areas are removed, a backup changes the store only by renames into or out of its own run folders (LLR-161). A successor's reclaim moves those folders aside (LLR-124), so every rename the former owner then issues names a path that no longer exists and fails by itself: it publishes nothing, deletes nothing and replaces nothing, with no check between a test and a write to race. Before each step and each stored object the run also re-reads its owner record, comparing the run identity, as an early exit. A mismatch, a rename that fails because its run folder is gone, or an owner record that stays unreadable after three reads about 300 ms apart means the claim was lost: the run stops at once, cleans up nothing, ends the location with part failed (1), and reports that its work was reclaimed on the console and in the global record, appending nothing to the location's record. A write through a handle the run already holds open (its owner record's refresh, a temporary being written) is the one write that can land after a reclaim, and it lands in the leftovers its successor moved aside, never in a file the successor wrote or published. The owner record stays in place until the run-state write, the collapse and the views have ended: the saved state is prepared in the run folder and published by moving its folder out (LLR-150), so the owner record never enters a saved state. The run's writes outside the store (the location's record, the change-detection state and the views) pass through no run folder; the early exit is what guards them. The run's last steps stop its refresh, empty and delete the backup root's run folder and then that staging area, delete its owner record through the saved-state root's run folder, and then delete that run folder and staging area, each folder non-recursively.""")
L.set('LLR-125', 'dimensions', 'step=set{object-publication,object-delete,record-publication,saved-state-publication,earlier-content-copy,run-state-publication,collapse-record-rewrite,collapse-delete,owner-record-delete}; reclaimed_at=set{before-check,between-check-and-rename,while-a-handle-is-open}; record=set{same,different,unreadable-transient,unreadable-persistent}; roots=set{same-volume,different-volumes}; @pairwise')
L.set('LLR-125', 'rationale', "A plain filesystem gives no true lease; a run frozen past the stale time and resumed would otherwise overwrite or delete what its successor published, or publish objects no record references. A read of the owner record before each write lost: the run can be suspended between the read and the write it guards, and the write then lands on the successor's files; routing every change through a folder the reclaim moves away makes each rename its own test. Deleting the owner record when the saved state is published lost because the steps after it, the run-state write and the collapse, would then run with no evidence of the claim.")

# --- LLR-161 (new): the routing of each change through the run folders
L.add_row('LLR-125', 'design', 'LLR-161', [
    ('title', "Every change a backup makes to the store is a rename through its own run folder"),
    ('parent', 'LLR-125'),
    ('constrains', 'IF-033'),
    ('detail', "A backup holds one run folder in each root it changes, the backup root and the saved-state root, so every rename it makes stays inside one root and on one volume. It creates each staging area, and its run folder inside, before it writes its owner record, creates each run folder only inside a staging area it has just created, and never re-creates either. Each kind of change is a rename into or out of the run folder of the root it changes: a new stored object, a record, its evidence, the run-state record and a kit file are written at a temporary in that folder and published by renaming them out, replacing a destination only where the publishing row allows; the saved state is prepared in the saved-state root's run folder and published by renaming its folder out; earlier content placed in a saved state is a verified copy published that way, the backup root's copy deleted only after (LLR-150); a delete renames the entry into the run folder of its root under the deletion form and purges it at once, so a kill leaves at most one entry being deleted in each run folder; and the owner record is deleted the same way at the end. No change renames an entry straight from one published place to another. An entry of the saved-state root's run folder whose destination lies in a saved state carries that saved state's folder name (IF-033), so a later run can tell where it was going."),
    ('dimensions', 'change=set{stored-object,record,evidence,run-state,kit-file,saved-state,earlier-content,delete,owner-record}; roots=set{same-volume,different-volumes}; kill_point=set{after-temporary-written,after-rename-in,after-rename-out}; destination=set{backup-root,saved-state}; @pairwise'),
    ('rationale', "A rename whose source or destination is the run's own folder fails by itself once a reclaim has moved that folder away, which no separate test can match. A rename straight between published places lost for that reason; moving earlier content through the run folder in two renames lost because between them no published place would hold it; a verified copy costs that content's reading and writing once more, inside the run's time budget at the declared change, and one object's extra space at a time. One run folder per root, rather than one per volume, lost nothing and needs no volume test."),
    ('status', 'Drafted'),
])

# --- LLR-150: content is placed by verified copy then delete
L.set('LLR-150', 'detail', """A backup that keeps a saved state publishes in this order: it prepares the saved state (its record, evidence, folder and link records and kit) in a folder in the saved-state root's run folder, while every stored object that state needs is still in the backup root; it publishes the saved state by renaming that folder to its saved-state name; it publishes the new latest record; and only then places in the saved state each stored object that no entry of the new latest record claims: a copy written in the saved-state root's run folder, its content key checked from the written bytes, is published into the saved state by rename, and only then is the backup root's copy deleted through the backup root's run folder (LLR-161). A restore searches the backup root and every published saved state, so at every point each published state, an older one whose blank entries borrow that content by content key included, finds every object it needs, and a run folder is never the only place holding content a visible state needs. A kill after the saved state is published and before the new latest record is published leaves a saved state equal to the latest state, under the name the next run would give it; the next changing run finds that folder, whose record matches the latest record's evidence, and keeps it as its saved state rather than adding another. A kill while the saved state is still being prepared leaves a folder holding no stored object, whose record files match the published latest state's, which the next run recognises as holding no content (LLR-088). A kill between a copy's publication and the deletion of the backup root's copy leaves a duplicate, which the cross-state collapse removes.""")
L.set('LLR-150', 'dimensions', 'kill_point=set{while-preparing,before-saved-state-publication,after-saved-state-publication,after-latest-publication,during-copy,after-copy-before-delete,after-delete}; content=set{removed,superseded,unchanged}; borrower=bool; volumes=set{same,different}; @pairwise')
L.set('LLR-150', 'rationale', "A restore searches the backup root and the published saved states, never a staging area, so content moved into staging, or into a saved state not yet published, is unreachable from every visible state that needs it if the run dies there, an older state that borrows it by content key included. A rename straight from the backup root into the saved state lost because it passes through no run folder, so a former owner resumed after a reclaim could still make it; moving the content through a run folder in two renames lost because between them no published place holds it. Keeping a second full copy of the history lost on space, while a copy then a delete needs one object's extra space at a time. Letting restores search the staging area lost because the staging area of a live run is not a published state and may be reclaimed.")

L.sub('LLR-005', 'detail', 'and its superseded and removed content then moves into it in the order LLR-150 gives.',
      'and its superseded and removed content is then placed in it in the order LLR-150 gives.')

L.sub('LLR-041', 'detail', "Each failure to move a removed or superseded file's earlier content from the backup root into the published saved state is caught per file,",
      "Each failure to place a removed or superseded file's earlier content in the published saved state (its copy, the copy's check or its publication) is caught per file,")
L.sub('LLR-041', 'detail', 'and the run reports part failed. Where the saved state',
      'and the run reports part failed. A failure to delete the backup root\'s copy after its copy is published leaves a duplicate the collapse removes, and is not a failure. Where the saved state')
L.set('LLR-041', 'dimensions', 'kind=set{superseded,removed}; failures=range[1..2]; failing_step=set{copy,copy-check,copy-publication,root-copy-delete,saved-state-publication}; @pairwise')
L.sub('LLR-041', 'rationale', 'Aborting on the first failed move leaves content half placed', 'Aborting on the first failed placement leaves content half placed')

L.sub('LLR-026', 'detail', 'Every rewrite and delete is fenced (LLR-125).',
      'Each rewritten record is published, and each redundant copy deleted, through the run folder of its root (LLR-161).')

L.sub('LLR-117', 'detail', 'A new stored object is written at a fresh temporary name in its folder, of the stored-object temporary form of the store layout (an archive is built there from nothing),',
      'A new stored object is written at a fresh temporary in the run folder of its root (LLR-161), of the stored-object temporary form (IF-033) (an archive is built there from nothing),')
L.sub('LLR-117', 'detail', 'only then is it published at its content-derived name by rename.',
      'only then is it published at its content-derived name by renaming it out of the run folder.')
L.sub('LLR-117', 'detail', 'A temporary left by a killed or fenced run is removed by the next run that holds the backup and has passed admission, recognised by its form and confirmed unreferenced by the folder\'s record, never by its name alone.',
      "A temporary a killed or reclaimed run left in its run folder goes with that folder's reclaim (LLR-124). A stored-object temporary beside a stored object, left by an earlier release, is removed by the next run that holds the backup and has passed admission, recognised by its form and confirmed unreferenced by the folder's record, never by its name alone.")
L.set('LLR-117', 'dimensions', 'destination=set{absent,unreferenced-valid,truncated-debris,claimed}; form=set{raw,archive}; check=set{passes,fails}; effort=range[0..9]; leftover_temporary=set{none,in-reclaimed-run-folder,beside-unreferenced,beside-named-by-an-entry}; @pairwise')

L.sub('LLR-087', 'detail', 'Every record of contents is written through one writer: any publication temporary left beside the destination by a killed run is removed and never read, the new content is written to the temporary, and it replaces the destination by one overwriting rename on the same volume;',
      "Every record of contents is written through one writer: the new content is written to a temporary on the destination's volume (a backup's in its run folder, LLR-161; a removal's, a repair's or the change-detection state's beside the destination, where a temporary a killed run left is removed and never read), and it replaces the destination by one overwriting rename on the same volume;")
L.set('LLR-087', 'dimensions', 'kill_point=set{before-temporary,after-temporary-complete,after-temporary-torn,after-rename}; failure=set{kill,power-loss,rename-error}; folder=set{latest,saved-state,change-detection}; temporary_place=set{run-folder,beside-destination}; @pairwise')

L.sub('LLR-118', 'detail', 'finding a record whose evidence does not match but whose evidence temporary does, publishes that temporary and continues;',
      "finding a record whose evidence does not match but whose evidence temporary does, that temporary lying beside the record or in the run folder a reclaim moved aside, publishes a copy of it through its own run folder and continues;")

L.sub('LLR-022', 'detail', 'stored-object temporaries that no entry names, and the run-state record.',
      'stored-object temporaries that no entry names, the run-state record, and the staging area and its reclaimed leftovers (IF-013).')
L.set('LLR-022', 'dimensions', 'path=set{root-infrastructure,nested-same-name,ordinary,retired-launcher,publication-temporary,staging-area}; folder=set{backup-root,saved-state,source-root}; @pairwise')

L.sub('LLR-052', 'detail', 'earlier content that must be copied rather than moved because the saved-state location is on another volume, at its stored size;',
      'earlier content copied into the saved state, at its stored size where the saved-state location is on another volume (on the same volume each copy is freed again when the backup root\'s copy is deleted, so only the largest counts, within the temporary allowance);')

# --- LLR-080: staging areas and run folders before the owner record
L.sub('LLR-080', 'detail', 'Right after creating the staging area a backup writes its owner record once,',
      "Right after creating its staging areas and its run folders in them (LLR-161), a backup writes its owner record once, in the saved-state root's staging area,")
L.sub('LLR-080', 'detail', 'touching it through the same open handle only when the run identity is its own;',
      'touching it through the same open handle only when the run identity is its own, so a touch made after a reclaim lands in the leftovers moved aside;')
L.sub('LLR-080', 'detail', 'and clears its own staging area as LLR-124 states.', 'and clears its own staging areas as LLR-124 states.')

# --- LLR-017 / LLR-088 / LLR-124: classification and reclaim over both areas
L.set('LLR-017', 'detail', """A run that finds a staging area present, at the saved-state root or at the backup root, never overwrites it. It lists each staging area, and each run folder in it, forced, literally and fail-closed (hidden, system and dot-named entries are content; an enumeration, read or access failure is never evidence of emptiness), reads each area's own modification time, reads the owner record up to three times about 300 ms apart, and records each finding independently: content (any entry LLR-088 does not recognise as holding no content); an unfinished removal (a removal's marker); a staging area that is a link; evidence that cannot be read (a listing, an area's own time, or an owner record still unreadable after the three reads); a live or unproven earlier run (an owner record that can be read, a torn one or one of an unknown schema included, whose run is not proven dead, or ownerless areas holding no content whose own time is still fresh); and reclaimable leftovers (areas holding no content, with no owner record and their own times stale, or with an owner record proven dead as LLR-080 judges). Refused, with nothing moved or deleted and no saved state published, by the precedence of the shared vocabulary: precondition not met (2) where content, an unfinished removal, a link or evidence that cannot be read is found, whatever else is; damaged record (3) where a state's record fails its evidence and is not an interrupted publication (LLR-118), and nothing of class 2 is found, a live or unproven earlier run included; busy (4) where the only finding is a live or unproven earlier run. An unfinished removal's message names the remedy, re-running that removal. Reclaimable leftovers, a prepared saved-state folder LLR-088 recognises included, do not by themselves refuse.""")
L.set('LLR-017', 'dimensions', 'owner=set{none,fresh,stale-confirmed,stale-unconfirmed,torn,unknown-schema,future-dated,unreadable}; staging=set{saved-state-root,backup-root,both}; staging_age=set{fresh,stale}; run_folder_entry=set{none,publication-temporary,object-temporary,deletion-with-published-twin,deletion-unreferenced,deletion-unique,prepared-matching,prepared-differing,prepared-holding-object,unknown}; content=bool; removal_marker=bool; linked=bool; listing_readable=bool; record_damage=bool; @pairwise')

L.set('LLR-088', 'title', "A dead backup's staging entries that hold no content are recognised by their form, the prepared saved state included")
L.set('LLR-088', 'detail', """In a backup's staging areas, these entries hold no content, each matched by its exact form with letter case (IF-033): the owner record; a run folder named for the owner record's run identity, or, with no owner record, an empty run folder; and, in a run folder, a publication temporary, a stored-object temporary, an entry being deleted whose stored name a published folder still holds or no published record names, and the folder of a saved state being prepared, recognised positively: it holds no stored object and nothing outside its closed set (the kit's name set, the record of contents, its evidence, the folder record, the link record and their publication temporaries), and each record file in it is byte-identical to the backup root's file of the same name. Any other entry is content: an unrecognised file or folder, a run folder of another run identity, a prepared folder that differs from the published latest state or holds a stored object, and an entry being deleted whose content no published folder holds although a record names it. Areas holding only entries that hold no content classify by the owner record alone, and with no owner record by their own modification times. Once the owner is proven dead (LLR-080), they are reclaimable (LLR-124), the prepared folder included. In the backup root and every saved state, a publication temporary beside a record, left by a removal, a repair or an earlier release, is an infrastructure name only at the root of the folder that owns the record, never backed up, reported or found by the check; a same-named file deeper in a tree is ordinary content.""")
L.set('LLR-088', 'rationale', "A killed backup leaves temporaries, at most one entry it was deleting and the saved state it was preparing; counting them as content turns every such kill into a permanent refusal, while recognising them by name alone would let an unrelated folder or a unique stored object pass as debris. A prepared saved state holds only copies of the published latest state's records and the kit, so comparing those copies with the published files recognises it, and it holds no stored object.")

L.set('LLR-124', 'title', "A provably dead run's leftovers are reclaimed by moving its staging areas aside")
L.set('LLR-124', 'detail', """Only leftovers classified reclaimable, and confirmed by the second sample, are reclaimed, in this order: move the backup root's staging area aside to a reclaimed-leftover name, where present, then the saved-state root's, so the root holding the latest record is taken from the former owner first; check each moved folder against the identity the sample classified and, on any mismatch, move the moved folders straight back; create fresh staging areas with this run's folders and immediately write this run's owner record (LLR-080); complete any interrupted publication the classification identified from a temporary in a moved folder, by copying that temporary into this run's own folder and publishing it from there (LLR-118); then list each moved folder again, forced and fail-closed, and delete by exact name each entry LLR-088 recognises (the files of a prepared saved-state folder before that folder, the owner record last) and each folder non-recursively. A failed move aside, or a failed create of a fresh staging area, a run folder or the owner record, refuses without retrying in a loop and leaves any moved folder in place: busy (4) where the cause is an I/O fault, a precondition not met (2) where access is denied. A mismatch after a move means another run reached the leftovers first: the folders are moved back and the run refuses as busy (4). Where a final listing finds an entry LLR-088 does not recognise or cannot be made, or a delete fails, that moved folder, which belongs to no state, is kept and named in the run's record with the recovery guidance, and the run completes (0). Nothing in this path deletes recursively. A run's own cleanup on an early failure first proves its staging areas are still its own (its owner record carries its identity, and nothing is inside beyond its own disposable entries), deletes those through its run folders (LLR-161) with the owner record last, and otherwise keeps the folders.""")
L.set('LLR-124', 'dimensions', 'verdict=set{empty-stale,owner-stale}; staging=set{saved-state-root-only,both}; contents=set{none,temporaries,entry-being-deleted,prepared-folder,interrupted-publication}; race=set{none,owner-resumes-before-move,owner-writes-after-move,two-reclaimers}; failure=set{none,move-aside-backup-root,move-aside-saved-state-root,identity-mismatch,create-staging,create-owner-record,final-listing,final-delete}; cause=set{io-fault,access-denied}; @pairwise')
L.set('LLR-124', 'rationale', "A reclaim that deletes in place can delete content a frozen owner wrote after the classification; a second exclusive claim artifact lost because it brings its own staleness and wedge modes, while move-aside then verify fails only toward refusal. Moving the backup root's area first lost nothing and takes the latest record out of the former owner's reach before anything else; publishing a recovered temporary straight from the moved folder lost because that rename would pass through no run folder of this run.")

C.set('CMP-012', 'notes', "Gives one changing operation at a time the use of a backup: takes and holds the operating-system claim, writes and refreshes the owner record whose age is the liveness evidence, keeps a backup's run folders, one in each root, through which every change the backup makes to the store passes, classifies an earlier run's leftovers from the disk alone, and reclaims a provably dead run's leftovers that hold no content by moving its staging areas aside, which also fences a run whose claim was lost: its next change then fails by itself. Backup, removal, repair and kit refresh all go through it; reads and restores never take the claim, though a restore that meets a kit mid-refresh tests whether it is held. Today all of it is in the backup-only engine module, with one staging area at the saved-state root and no run folder; the restore's test of the claim is new. The readers' rule of taking no claim is stated here, across the claim.")

# SR-144: the rationale and acceptance follow the filesystem fence (P-09 (a) stands).
R.sub('SR-144', 'rationale', 'No check can close the window between reading the evidence and the write it guards, so the promise is the one a check before every write can keep: at most one unpublished temporary, which changes nothing the successor made and is removed by the next run.',
      "No separate check can close the window between reading the evidence and the write it guards, so the reclaim itself must disable the resumed run's changes; what such a run can still write through work it already had open lands among the leftovers the successor set aside, never in a file the successor wrote or published.")
R.sub('SR-144', 'acceptance_criteria', 'publishes nothing, leaves at most one unpublished temporary file that the next run removes, every state restores',
      'publishes nothing, writes nothing outside the leftovers the successor set aside, every state restores')

# ======================================================================
# R3C-001: at the default state location only the record is system-owned
# ======================================================================
L.sub('LLR-109', 'detail', 'into a system location (the backup root, the saved-state root and its saved states, the change-detection state location, the record location or the listing location), recorded and not followed;',
      'into a system location (the backup root, the saved-state root and its saved states, a change-detection state location configured apart from the source, the record location or the listing location), recorded and not followed;')
L.sub('LLR-109', 'detail', 'to a folder inside the source, recorded and not followed, its target captured at its real place;',
      'to a folder inside the source, the source root included, recorded and not followed, its target captured at its real place;')
L.sub('LLR-109', 'detail', 'A recorded link is written as LLR-110 states,',
      'Where the change-detection record is kept at the source root, the default, only that record and its publication temporaries there are the system\'s own, never the folder: a link to the source root or to any other folder of the source is a link inside the source, recorded with its walk path and re-pointed under the target at restore. A recorded link is written as LLR-110 states,')
L.set('LLR-109', 'dimensions', 'link=set{folder-link,junction}; leads_to=set{outside-source,inside-source,source-root,ancestor-in-source,ancestor-in-followed-folder,backup,saved-states,separate-state-location,log-location,listing-location,unreachable}; state_location=set{source-root,separate}; reached_through=set{source,followed-folder}; repeated=bool; @pairwise')

I.sub('IF-018', 'data', '- TargetClass: one of inside-source (the target is a folder the walk captures: a folder of the same source, or an ancestor of the link, one reached through a followed outside folder included), own-location (the target lies in the backup, its saved states, the change-detection state location, the record location or the listing location);',
      '- TargetClass: one of inside-source (the target is a folder the walk captures: a folder of the same source, the source root included, or an ancestor of the link, one reached through a followed outside folder included), own-location (the target lies in the backup, its saved states, a change-detection state location configured apart from the source, the record location or the listing location);')

L.sub('LLR-144', 'detail', 'one whose target the walk captured (inside the source, or an ancestor reached through a followed outside folder)',
      'one whose target the walk captured (inside the source, the source root included where it holds the change-detection record, or an ancestor reached through a followed outside folder)')

L.sub('LLR-115', 'detail', 'and nothing else is added to the source.',
      'and nothing else is added to the source; the source root stays part of the source, only the record and its temporaries there being the system\'s own, so a link to that folder is a link inside the source (LLR-109).')

I.sub('IF-004', 'data', "- SourceStatePath: optional path, the change-detection record's location; default the source root.",
      "- SourceStatePath: optional path, a folder apart from the source for the change-detection record; default the source root, where only the record's own files are the system's.")

# ======================================================================
# R3C-003: a refused claim leaves the store byte-identical
# ======================================================================
R.sub('SR-086', 'requirement', 'and refuse the changing operation without creating, moving or deleting anything in it.',
      'and refuse the changing operation without changing anything in it.')
R.sub('SR-086', 'acceptance_criteria', 'are each refused and the store is byte-identical:',
      'are each refused and the store is byte-identical, the refusal reported on the console and in the launch\'s own record outside the backup:')
L.sub('LLR-091', 'detail', "A refusal on the claim appends one entry to the location's record.",
      "A refusal on the claim reaches the console and the global record only; nothing is appended to the location's record, which lies in the store (LLR-095).")
L.sub('LLR-095', 'detail', 'a refusal before that point appends one entry to the existing location record, which belongs to the live holder.',
      "a refusal before that point, on the claim or at admission, reaches the console and the global record only, and the location's record, which lies in the store and belongs to the live holder or to the last run, is left unchanged.")
L.set('LLR-095', 'dimensions', 'configuration=set{valid,refused,missing}; record_location=set{admitted,refused}; prior_record=set{absent,present}; claim=set{held,refused}; location_admission=set{passed,refused}; @pairwise')
L.sub('LLR-122', 'detail', 'After the cause clears the same operation proceeds.',
      "The refusal reaches the console and the global record only, never the location's record (LLR-095). After the cause clears the same operation proceeds.")

# ======================================================================
# R3C-004 + R3C-007: a restore meeting a kit mid-refresh; the kit-origin
# artifact takes no part in the revision equality
# ======================================================================
L.set('LLR-159', 'title', 'A restore waits out a kit refresh, and refuses a kit an interrupted refresh left in two revisions')
L.set('LLR-159', 'detail', """As one of its whole-restore checks (LLR-136), a restore reads the kit revision of every artifact of the kit's name set in the state's folder that carries the current revision (IF-019), a file without one counting as of a kit older than the one whose files all carry it, and on the language-runtime route the version of the hashing library it loads. The kit-origin artifact carries no current revision and takes no part in this check; its original revision is kept for age decisions (LLR-138). The retired launcher name, kept by a refresh, is not part of the check either. A kit whose files all carry the restorer's own revision proceeds. Otherwise, since a kit refresh replaces a kit's files one at a time, the restore reads the revisions again every 2 seconds for up to 60 seconds: where they come to agree with its own revision it proceeds; where they come to agree with another revision, the restorer itself was replaced while it ran, and the restore ends with retry later (4), naming the kit refresh, since a re-run starts the new restorer. Where they still differ when the wait ends, the restore tests whether the backup's claim is held, by opening the claim file (IF-032) in a way its holder's open excludes and closing it at once, never creating it: held, a refresh is still running, and the restore ends with retry later (4), naming the kit refresh; not held, the kit is what an interrupted refresh left, and the restore is refused with the damaged-record value (3), naming the files that differ and the remedy, re-running the kit refresh, which completes the kit. Where the claim cannot be tested (the route has no lock tool, or the claim file cannot be reached), the restore is refused the same way with 3, its message adding that a refresh may still be running. Every outcome is reached before anything is written.""")
L.set('LLR-159', 'dimensions', 'kit=set{one-revision,new-restorers-old-files,one-restorer-new,old-library,refreshed-with-retired-launcher,refreshed-with-kit-origin}; during_wait=set{agrees-with-own,agrees-with-other,still-differs}; claim=set{held,free,untestable}; route=set{language-runtime,shell}; @pairwise')
L.set('LLR-159', 'rationale', "A kit refresh killed between two files leaves a restorer beside files of another revision, which can run against a library it was not written for and restore wrongly or fail with an arbitrary error. Making the whole kit one atomic replacement lost: a state's folder holds the kit beside its content, and there is no single rename that swaps a set of files. Refusing a mixed kit at once lost because a live refresh shows one to every restore that starts within its few seconds per state; waiting with no bound lost because an interrupted refresh never finishes. Testing the claim decides between the two, and a changing operation that meets the test's brief open retries as it does for contention. Comparing the kit-origin artifact's revision lost because it holds, by design, the revision the state had before its first refresh.")

L.sub('LLR-123', 'detail', 'while a backup, a removal, a repair or a kit refresh holds the backup.',
      'while a backup, a removal, a repair or a kit refresh holds the backup. A restore that meets the state\'s kit mid-refresh waits for it and, past its wait, ends with retry later (4), naming the refresh, as LLR-159 states; it never restores beside a kit of two revisions.')
L.set('LLR-123', 'dimensions', 'reader=set{check,report,restore}; writer=set{backup,removal,repair,kit-refresh}; event=set{none,object-renamed,copy-collapsed,folder-removed,record-rewritten,state-being-read-removed,kit-mid-refresh}; last_copy_in_removed_state=bool; rereads=range[0..3]; @pairwise')

L.sub('LLR-130', 'detail', 'A kill between two kit files leaves that state\'s kit with files of two revisions and a restorer of the new one, which refuses it as damaged record (3) naming a re-run of the kit refresh (LLR-159); re-running the refresh completes the kit.',
      "While the refresh runs, a restore that meets a state's kit with files of two revisions waits and, past its wait, ends with retry later (4), naming the refresh. A kill between two kit files leaves that state's kit with files of two revisions and a restorer of the new one, which, with no holder of the claim, refuses it as damaged record (3) naming a re-run of the kit refresh (LLR-159); re-running the refresh completes the kit.")

L.sub('LLR-040', 'detail', 'a damaged record, a kit whose files are of two revisions included, as 3;',
      'a damaged record, a kit whose files are of two revisions with no refresh running included, as 3;')
L.sub('LLR-040', 'detail', 'and the state being restored removed by a concurrent removal before its content was read, as retry later (4);',
      "the state being restored removed by a concurrent removal before its content was read, and a kit refresh still running past the restore's wait, as retry later (4);")

R.set('SR-106', 'acceptance_criteria', 'A check, the saved-state report and a restore started while a backup, a removal, a repair or a kit refresh is running each complete with their normal outcome against every complete state the running operation does not remove. A restore of the saved state that a running removal deletes either completes byte-exact or ends with retry later (value 4, SR-043) naming the removal; every file it has written is byte-exact, and no file is restored wrongly. A restore that meets a state\'s restore kit part-way through a running kit refresh waits a bounded time and then completes with its normal outcome, or ends with retry later (value 4) naming the refresh, writing nothing. A check or the report that meets a saved state removed while it reads leaves that state out as no longer present and reports no finding for it.')
R.sub('SR-106', 'rationale', 'since it leaves nothing in the backup that a removal could see.',
      'since it leaves nothing in the backup that a removal could see. A kit refresh replaces a state\'s kit a file at a time, which no single step makes whole, so a restore meeting it part-way waits a bounded time rather than run beside files of another revision, and a refresh outlasting the wait is reported as retry later.')
R.set('SR-106', 'permutations', 'reader=set{check,report,restore}; writer=set{backup,removal,repair,kit-refresh}; state=set{kept,being-removed}; kit=set{settled,mid-refresh}; @pairwise')

# ======================================================================
# R3C-006: the report takes the first name free across every recorded entry
# ======================================================================
I.sub('IF-022', 'data', 'The report, in the restore target\'s root: RECONSTRUCT.log or, where the state records a file at that path (compared as the target compares names), the first of RECONSTRUCT-1.log, RECONSTRUCT-2.log and so on at which the state records no file.',
      "The report, in the restore target's root: RECONSTRUCT.log or, where that name is taken (compared as the target compares names) by a file, a folder or a link the state records at the target's root, or by a folder a recorded entry needs as its parent, the first of RECONSTRUCT-1.log, RECONSTRUCT-2.log and so on that none of these takes.")
I.sub('IF-023', 'data', 'and the restore report (IF-022), at a name no recorded file takes.',
      'and the restore report (IF-022), at a name no recorded file, folder or link takes, nor any folder a recorded entry needs.')
L.sub('LLR-010', 'detail', 'the report at a name no recorded entry takes (IF-022).',
      'the report at the first report name that no recorded file, folder or link, and no parent folder a recorded entry needs, takes under the target\'s comparison (IF-022).')
L.sub('LLR-142', 'detail', 'The restore\'s report takes part in the comparison: it takes a name that no recorded path takes under the target\'s comparison (IF-022).',
      "The restore's report takes part in the comparison: its name is the first of IF-022's that no recorded file, folder or link, and no parent folder a recorded entry needs, takes under the target's comparison.")
L.set('LLR-142', 'dimensions', 'collision=set{none,case,unicode-normalisation,report-vs-file,report-vs-folder,report-vs-link,report-vs-parent-folder}; target_case_sensitive=bool; target_normalises=bool; @pairwise')
L.sub('LLR-143', 'detail', 'After every file is written and verified, the folder record is applied:',
      "After every file is written and verified, the folder record is applied, no folder's place being taken by the restore's report, whose name avoids every recorded folder and every parent folder an entry needs (IF-022):")
L.set('LLR-143', 'dimensions', 'folder=set{empty,nested-empty,hidden,system,read-only}; record=set{present,absent-current,absent-older,absent-unverifiable,malformed,short}; folder_named_like_report=bool; restore_system=set{windows,linux,macos}; @pairwise')
L.sub('LLR-144', 'detail', 'No file is written through any link.',
      "No file is written through any link, and no link's place is taken by the restore's report, whose name avoids every recorded link (IF-022).")
L.set('LLR-144', 'dimensions', 'link=set{inside-source,source-root,junction-inside-source,ancestor-in-followed-folder,own-location}; target_os=set{windows,linux,macos}; can_create_links=bool; link_record=set{present,missing,malformed,short}; link_named_like_report=bool; @pairwise')

# ======================================================================
# R3C-008: SR-073 stands; the shell route asks by typed prompt
# ======================================================================
L.set('LLR-157', 'title', 'The no-dialog switch and the folder-choice switch steer how the target is asked for, never past an unattended session')
L.set('LLR-157', 'detail', """On the language-runtime route, the no-dialog switch, or the no-dialog variable set to 1, suppresses the folder choice: with an interactive console and no target the restore asks by typed prompt, and without one it prints its usage and returns 2. On the shell route a folder choice is offered only when the request carries the folder-choice switch; without it, a restore with no target asks by typed prompt where an interactive console is present, desktop or not, and otherwise prints its usage and returns 2. A typed answer is taken as LLR-156 takes a chosen folder: only one absolute path of an existing folder is a target, and an empty or other answer gives the usage and 2. Neither switch overrides a session in which nobody can answer: declared unattended, redirected or closed input, or neither a console nor a desktop, still gives the usage and 2, with no prompt and no dialog.""")
L.set('LLR-157', 'dimensions', 'route=set{language-runtime,shell}; no_gui=set{none,switch,variable}; pick_target=bool; session=set{unattended,redirected-input,console-only,console-and-desktop,desktop-only}; typed_answer=set{absolute-folder,empty,relative,not-a-folder}; @pairwise')
L.set('LLR-157', 'rationale', "A desktop user who wants the typed prompt, or a test with no display, needs a way to turn the dialog off, and a shell restore started by a script with no target must fail at once rather than open a dialog; a script's input is not an interactive console, so it is never prompted either. Refusing every shell restore without a target lost because a restorer at a console with no desktop would then have no way to be asked, which the restore kit owes him. Offering the dialog on the shell route whenever a desktop is present lost because a scheduled job on a desktop machine would then wait on a dialog nobody sees.")
L.sub('LLR-073', 'detail', 'a typed prompt with an interactive console and no desktop;',
      'a typed prompt with an interactive console and no desktop, on either route;')
L.set('LLR-073', 'dimensions', 'start=set{declared-unattended,redirected-input,closed-input,no-console-no-desktop,console-only,desktop}; choice=set{chosen,cancelled,failed,unavailable}; route=set{language-runtime,shell}; restore_system=set{windows,linux,macos}; @pairwise')

# ----------------------------------------------------------------------
# Consistency: rows stating the same layout in the singular or as a move
L.sub('LLR-059', 'detail', 'After the new content is stored and removed content is moved,',
      'After the new content is stored and removed content is placed (LLR-150),')
L.sub('LLR-059', 'rationale', 'copying every superseded file lost because shared content would be stored twice.',
      'keeping a copy of every superseded file per state lost because shared content would be stored twice.')
L.sub('LLR-122', 'detail', 'creates, moves and deletes nothing in the staging area, the stored content or any record.',
      'creates, moves and deletes nothing in a staging area, the stored content or any record.')
L.sub('LLR-091', 'detail', 'and so before it classifies or creates the staging area;',
      'and so before it classifies or creates a staging area;')
L.sub('LLR-123', 'detail', 'read only published records and folders, never the staging area.',
      'read only published records and folders, never a staging area.')

for name, doc in (('components.toml', C), ('interfaces.toml', I),
                  ('low-level-requirements.toml', L), ('system-requirements.toml', R)):
    (REQ / name).write_bytes(doc.text().encode('utf-8'))
print('written')
