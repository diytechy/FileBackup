# Builds the merged LLR tier: Opus rows as the base (most clusters are "take O" or
# an Opus-based union), the alignment's ids, parents and SR sets, and the
# builder's per-cluster edits below (union clauses from Astra, the coordinator's
# K-calls). Every textual replacement asserts its anchor, so a drifted base fails.
import json, tomllib, sys
from pathlib import Path

D = Path(__file__).resolve().parent.parent
m = json.load(open(D / 'r3-alignment-map.json', encoding='utf-8'))
o = tomllib.load(open(D / 'r3-opus/low-level-requirements.toml', 'rb'))['design']
BS = chr(92)

# ---- per-row edits ---------------------------------------------------------
# keys: field -> new value; 'rep' -> list of (field, old, new); 'add' -> (field, text appended)
E = {}

E['LLR-014'] = {'rep': [('detail', 'A run processes every configured location in turn in the one launch.',
    'Every location set of the configuration, not only the first, is resolved and validated before the first location runs, for every action; the run then processes every configured location in turn in the one launch.')]}

E['LLR-048'] = {'rep': [('detail', "The container's exit status is the operation's outcome value, equal to that of the same request started directly.",
    "The container's exit status is the operation's outcome value, and its findings document the operation's, each equal to that of the same request started directly.")]}

E['LLR-042'] = {'rep': [('detail', 'and the launch ends with the configuration-refused value (2), creating and changing nothing.',
    'and the launch ends with the configuration-refused value (2), creating nothing and changing no location; an existing global record only gains the refusal entry.')]}

E['LLR-063'] = {'rep': [('detail', ' An optional setting added with a default leaves the description version unchanged, and an older build refusing such a setting by name is the closed catalogue working as designed.', '')]}

E['LLR-103'] = {'rep': [('rationale', 'Checking only at the moment the listing is written lost: by then a backup has already been taken into a refused location.',
    "Checking only at the moment the listing is written lost: by then a backup has already been taken into a refused location. The listing location must share the backup's volume because each view entry is a relative link to its stored object, and a relative link cannot cross volumes on Windows.")]}

E['LLR-037'] = {'sr_refs': ['SR-019', 'SR-081']}

E['LLR-020'] = {'constrains': 'IF-046'}

E['LLR-105'] = {'sr_refs': ['SR-132']}

E['LLR-109'] = {'rep': [('detail', "A link whose target cannot be reached within the run's bounded wait is named",
    "Each request that resolves a link or enumerates what it leads to is bounded to 60 seconds; a link whose target cannot be reached within that wait is named")],
    'dimensions': 'link=set{folder-link,junction,file-link}; leads_to=set{outside-source,inside-source,ancestor,backup,saved-states,state-location,log-location,unreachable,timeout}; repeated=bool; @pairwise'}

E['LLR-078'] = {'add': ('detail', ' Where whether the source is a volume root cannot be told, its system folders are captured.'),
    'dimensions': 'source_root=set{drive-root,share-root,ordinary-folder,unknown}; folder_position=set{top-level,nested}; folder_name=set{volume-metadata,recycle,ordinary}; name_case=set{as-created,different-case}; readable=bool; @pairwise'}

E['LLR-067'] = {'rep': [('detail', "Reading or copying a file's content is tried up to three times in all,",
    "Reading a file's content, the first read that takes its digest included, and copying it are each tried up to three times in all,")]}

E['LLR-036'] = {'add': ('detail', ' A source root that cannot be read is not an empty source: the location fails naming it, and nothing in its backup changes.'),
    'dimensions': 'previous=set{populated,empty-from-first-run}; allow_empty=bool; only_left_out_files=bool; source_root=set{readable,unreadable}; @pairwise'}

E['LLR-113'] = {'rep': [('detail', 'The comparison changes nothing;',
    "Paths are compared with the forward slash and the backslash taken as the same separator, so a record written with the other separator makes no file new or removed. The comparison changes nothing;")],
    'dimensions': 'case=set{new,removed,unchanged,size-changed,time-changed,content-changed-on-reread,blank-stored-copy,kept-unreadable,other-separator}; reread_due=bool; @pairwise'}

E['LLR-011'] = {
    'detail': """Whether a run re-reads unchanged-looking files is a function of the schedule setting, the time the last completed full re-read began and the current time only. An every-run schedule always re-reads. A never schedule never re-reads, whether or not a completed re-read is on record. A daily, weekly, monthly or yearly schedule re-reads on the first run at or after 24 hours, 7 days, one calendar month or one calendar year has elapsed since the time the last completed full re-read began; with no completed full re-read on record it re-reads. The time is recorded only when a full re-read completes: a re-read interrupted before completion, or one that met a file or folder it could not read, does not count. Reads made to capture new content or to store lost content again happen whatever the schedule.""",
    'dimensions': 'schedule=set{A,E,D,W,M,Y,N}; elapsed=range[0..400d]; elapsed_vs_period=set{before,at,after}; last_reread=set{none,completed,interrupted,part-unreadable}; @pairwise',
    'rationale': """A schedule that decides differently for the same inputs gives the owner no real choice on the speed-against-certainty trade-off. Calendar boundaries lost: a daily schedule would re-read twice within minutes across midnight and a weekly one twice in two days across a week boundary, which is not a period elapsed since the last completed re-read. Counting from the last run instead of the last completed re-read lost because an interrupted re-read would reset the clock and the re-read might never finish."""}

E['LLR-028'] = {
    'detail': """The completion time of each latest state is written to the run-state record after the state is published and before the cross-state collapse runs, together with the time the last completed full re-read began, so a kill during the collapse cannot leave them stale; the run-state record is replaced whole through its publication temporary, as records are. The next changing run names the saved state it keeps by that completion time, in host-local time to the second, with the numeric suffix of the layout keeping apart states completed in the same second.""",
    'dimensions': 'kill_point=set{before-publication,after-publication,during-collapse}; same_second=bool; @full'}

E['LLR-005'] = {
    'detail': """When the change set is not empty (an addition served by deduplication, a removal of shared content, a time-only change, a heal, and a difference in the folder record or the link record all count), the previous latest state's record, its evidence, folder and link records and kit are staged, its superseded and removed content is placed with it, and it is published as a saved state, dated as its child row requires. A saved state becomes visible only after its own record, its evidence and its kit are complete. When the change set is empty and no stored content needs storing again, no saved state is created; the latest state is never itself a saved state.""",
    'dimensions': 'runs=range[2..20]; change_kind=set{add,edit,remove,rename,duplicate-only-add,shared-content-remove,time-only,heal,folder-only,link-only,none}; same_second=bool; compress=bool; @pairwise'}

E['LLR-003'] = {'rep': [('detail', 'A key already held by the backup is adopted:',
    'A key the backup holds at a stored copy that is actually present is adopted (an entry whose stored-copy reference is blank or names an absent copy is a demand for the content, not a supply of it):')]}

E['LLR-117'] = {
    'title': 'A stored object is published from a verified temporary, never merged into leftovers at its name',
    'detail': """A new stored object is written at a fresh temporary name in its folder (an archive is built there from nothing), its content key is checked from the written bytes (an archive by expanding it), and only then is it published at its content-derived name by rename. A file already at that name that no entry of any state references (left by a killed run, an interrupted archive tool, or an entry evicted while its object awaits removal) is replaced by the publication; an object at that name that some entry still claims is never replaced. A failed check removes the temporary and the file is reported as not stored. A compressed object is written at the effort level resolved from the environment.""",
    'dimensions': 'destination=set{absent,unreferenced-valid,truncated-debris,claimed}; form=set{raw,archive}; check=set{passes,fails}; effort=range[0..9]; @pairwise',
    'rationale': """An archive tool adding to debris at the name produces an archive of two members that restores the wrong bytes or none, and writing in place leaves a torn object under a valid-looking name after a kill. Clearing the debris at the name before writing lost: it puts a delete on the hot path of every new object, and a mistaken classification of the debris deletes content another state needs."""}

E['LLR-004'] = {
    'detail': """The file-type rule's list of already-compressed types is, matched without regard to letter case: zip, 7z, rar, z7, esd, gz, bz2, xz, tgz, zst, mp4, mkv, mov, avi, webm, mpg, mpeg, m2ts, m4v, wmv, flv, mp3, aac, flac, ogg, opus, m4a, jpg, jpeg, png, webp, gif, heic, heif, jar, pack, sav. A file of a listed type is stored as it is; the rule says compress for any other type, a file with no extension included. Office and text formats are not listed, and neither are filesystem containers such as plain disk images, whose contents are not known to be compressed. The list is a fast path for known formats, not a claim of completeness, and never overrides a measurement that can be taken. The user manual's table of already-compressed types equals this list."""}

E['LLR-116'] = {'rep': [('detail', 'Each window is compressed by a fast general-purpose codec with a long history window into a counting sink',
    'Each window is compressed by Brotli at its fastest quality level into a counting sink')]}

E['LLR-052'] = {
    'detail': """Before any location's root, claim, record, staging area or log is created, a plan that reads and writes nothing sums the demand on each volume over every configured location on it: new content not already held, at its uncompressed length rounded up to the volume's allocation unit (64 KiB where the unit cannot be observed); content stored again to heal a loss, the same way; earlier content that must be copied rather than moved because the saved-state location is on another volume, at its stored size; and a declared allowance: the records and their evidence written (old and new), the restore kits at their actual size, 4096 bytes per folder and per record entry, and 16 MiB per location plus the largest temporary objects the run holds at once. Where a volume's demand exceeds its free space, every location with demand on it is refused as a precondition not met (2), naming the volume, the space needed and the space free, with nothing created or changed on that volume; other locations proceed, and demand equal to free space passes. A volume whose free space cannot be measured is not refused; the location's record says the space check was not made. Once the claim is held, the plan is checked again against the store as it then is, before any content is written, and a shortfall refuses the same way.""",
    'dimensions': 'locations_on_volume=range[1..3]; need_vs_free=set{below,equal,above}; demand=set{new-content,healed-content,cross-volume-history,many-small-files}; platform=set{windows,linux}; measurable=bool; allocation_unit=set{observed,unknown}; changed_after_claim=bool; @pairwise',
    'rationale': """A backup that runs out of space halfway leaves a half-staged state and an owner who learns only from a cryptic write error. Checking each location against the volume separately lost because two locations that each fit can together not fit; planning only after the claim, staging and record exist lost because a refused run would already have created them on the full volume. Refusing a volume whose free space cannot be measured lost: a share or mount that hides its free space would stop every run, a precondition the owner cannot always fix, while the record line keeps the unchecked state visible."""}

E['LLR-135'] = {'rep': [('detail', 'Its free space is measured for drive-qualified',
    "Its free space and its allocation unit are measured for drive-qualified"),
    ('detail', 'and is reported as unknown, never as an error, when neither works.',
    'and each is reported as unknown, never as an error, when it cannot be measured.')]}

E['LLR-150'] = {
    'constrains': 'IF-013',
    'detail': """Until a run's new latest record is published, every stored object the previous latest record references stays in the backup root or in a published saved-state folder, where a restore searches for it; the staging area is never the only place holding content a published record references. Content leaves the backup root for the saved state being kept only after the new latest record that no longer references it is published, and that saved state is published once its content is in place. A kill at any point therefore leaves the published latest record restorable and the content of the state being kept in the backup root or in the published saved state.""",
    'dimensions': 'kill_point=set{before-latest-publication,after-latest-publication,during-content-placement,after-saved-state-publication}; content=set{removed,superseded,unchanged}; @pairwise',
    'rationale': """A restore searches the backup root and the published saved states, never the staging area, so content moved into staging before the new record is published is unreachable from a witnessed latest record if the run dies there. Copying the content instead of moving it lost on space at the declared scale; letting restores search the staging area lost because the staging area of a live run is not a published state and may be reclaimed."""}

E['LLR-087'] = {'rep': [('detail', "The writer does not force the temporary to stable storage before the rename; on a filesystem that reorders the rename ahead of the data a power loss may lose the newest record, which the evidence then reports as damage.",
    'The temporary is forced to stable storage before the rename, so after a power loss a reader finds the complete previous record or the complete new one.'),
    ('rationale', 'a journal lost because the rename already gives the needed atomicity on the supported journaled filesystems.',
    'a journal lost because the rename already gives the needed atomicity on the supported journaled filesystems. Renaming without forcing the data first lost: a filesystem may order the rename ahead of the data, and a power loss then leaves a torn newest record.')],
    'dimensions': 'kill_point=set{before-temporary,after-temporary-complete,after-temporary-torn,after-rename}; failure=set{kill,power-loss,rename-error}; folder=set{latest,saved-state,change-detection}; @pairwise'}

E['LLR-118'] = {'rep': [('detail', 'then renames the record, then renames the evidence.',
    'then renames the record, then renames the evidence, each temporary forced to stable storage before its rename.')]}

E['LLR-007'] = {'rep': [('detail', 'The kit depends on nothing backup-only.',
    'The kit is complete in a state before that state becomes visible, and depends on nothing backup-only.')]}

E['LLR-026'] = {'rep': [('detail', 'every other entry referencing it has its stored-copy reference blanked, to be found by content key.',
    'every other entry referencing it has its stored-copy reference blanked, to be found by content key. A redundant copy is deleted only after the kept copy is confirmed present and every state whose entries were blanked has its record rewritten and still resolves each of them.')]}

E['LLR-121'] = {
    'detail': """A backup written from Windows or from Linux has the same form: relative paths are recorded with the backslash as separator whatever the host, rows in ordinal order, digests and names as their interfaces define, times as opaque round-trip text. The compression decision depends only on content, type and settings. A reader treats a forward slash in a record written by an earlier supported version as the same separator, and change detection compares paths in that form, so a store written from Linux with forward slashes continues with no file seen as removed and added and no extra saved state; its latest record takes the backslash with the first run that has a real change. A run on either host type continues a backup written from the other, or by the previous released version, without a fresh start: it adds no duplicate of content already stored, makes the same decisions and saved states a same-host run would, and leaves every earlier state restorable.""",
    'dimensions': 'direction=set{windows-to-linux,linux-to-windows,same-host}; writer=set{previous-release,current}; record_separator=set{backslash,forward-slash}; change=set{none,real}; compress=bool; history=set{none,multiple}; @pairwise',
    'rationale': """With the host's own separator in the record, a run from the other host type sees every file as removed and added again and writes a full saved state for a tree that did not change. Keeping each host's separator and having every reader accept both lost: two stores of one source would still differ in their bytes, and an unchanged re-run could not be compared byte for byte across hosts. Rewriting a forward-slash record on the first run whatever changed lost because it adds a saved state for a tree that did not change."""}

E['LLR-088'] = {'rep': [('detail', 'In the backup root and every saved state it is an infrastructure name, never backed up, reported or found by the check.',
    'In the backup root and every saved state it is an infrastructure name only at the root of the folder that owns the record, never backed up, reported or found by the check; a same-named file deeper in a tree is ordinary content.')]}

E['LLR-080'] = {'rep': [('detail', 'and a second sample taken at least the record\'s refresh interval plus 30 seconds later (at least 90, at most 600 seconds) shows it unchanged;',
    'and a second sample, taken after the record\'s refresh interval capped at 600 seconds plus 30 seconds, and never less than 90 seconds, shows it unchanged;')]}

E['LLR-123'] = {
    'sr_refs': ['SR-106', 'SR-103'],
    'title': 'Checks, the report and restores take no claim, leave no artifact and still complete beside a writer',
    'detail': """A check without repair or refresh, the saved-state report and a restore take no claim, leave no artifact in the store and read only published records and folders, never the staging area. Where a stored object or a saved-state folder a reader has located vanishes before the reader has read it (a concurrent repair renamed it, the cross-state collapse removed a redundant copy, a removal deleted the folder), the reader locates the content again by content key over the pool as it then is. Where a record's evidence changes while the reader reads that record, the reader reads the record and its evidence again, up to three times, before it reports the record as damaged. Each therefore completes with the outcome it would have against a quiet store while a backup, a removal, a repair or a kit refresh holds the backup.""",
    'dimensions': 'reader=set{check,report,restore}; writer=set{backup,removal,repair,kit-refresh}; event=set{none,object-renamed,copy-collapsed,folder-removed,record-rewritten}; rereads=range[0..3]; @pairwise',
    'rationale': """A restore that waits for a nightly backup to finish is no use in a disaster, so readers take no claim. Assuming published states never change in place lost: a repair renames objects, the collapse blanks references and deletes duplicates, and a removal deletes a folder. Pinning a read generation that writers must respect lost because the shell route cannot keep reader-visible state, and a reader artifact would make a read change the store."""}

E['LLR-125'] = {
    'detail': """Before every destructive step on the store (moving, deleting or replacing a stored object, a folder or a record, and publishing a record, the run state or a saved state), the run re-reads its owner record and compares the run identity; writing a new object at a fresh temporary name, and publishing it at a name nothing occupies, is not destructive and is not preceded by the check. A mismatch, or a record that stays unreadable after three reads about 300 ms apart, means the claim was lost: the run stops at once, cleans up nothing, ends the location with part failed (1), and its record says its work was reclaimed. Immediately before the saved state is published the run stops its refresh and deletes its own owner record, so none reaches a saved state.""",
    'dimensions': 'step=set{object-move,object-delete,object-replace,record-publication,run-state-publication,saved-state-publication,new-object-publication}; record=set{same,different,unreadable-transient,unreadable-persistent}; @pairwise',
    'rationale': """A plain filesystem gives no true lease; a run frozen past the stale time and resumed would otherwise overwrite or delete what its successor published. Checking at a few fixed boundaries lost because a resumed run can still move or delete between them; checking before every write lost on the cost of a re-read per new object at a million files, where a new object at a fresh name cannot harm a successor."""}

E['LLR-046'] = {'rep': [('detail', '(measured per volume, skipped where unmeasurable)',
    "(measured per volume; where unmeasurable the check is not made and the removal's record says so)")]}

E['LLR-127'] = {'rep': [('detail', 'No journal is kept.',
    "A removal killed before its commit point leaves its marker in the staging area naming the saved state it removes; re-running the same removal recognises its own marker and resumes from the plan, rather than being refused by it, while a marker naming another saved state refuses with a message naming that removal as the remedy. No journal is kept.")],
    'dimensions': 'interrupt=set{kill,power-loss}; point=set{before-commit,after-copy,after-record,after-commit-rename,during-delete}; residue=set{staged-copy,committed-folder,own-marker,other-removal-marker,user-file-named-like-residue}; @pairwise'}

E['LLR-149'] = {
    'detail': """Unchanged-looking files are decided from size and time without reading their content unless a re-read is due; changed content is read once to take its digest and once to store it; each saved state's record is read at most once per run, through the content-location index, and only folders whose references vanished are rewritten; no whole record of every saved state is held in memory. The content-location index and the run's counters stay within 1 GiB of resident memory and at most one archive job runs at a time, so the operation and its tools together stay within 4 GiB. A check reads each distinct stored object once and a full restore streams each file once. Progress is recorded throughout.""",
    'rationale': """A run that rereads every file or every saved state's content each night grows with the history and overruns its window; caching more in memory lost on the total memory bound, which the reference host must meet with the tools it runs. Spilling the index to temporary files above its bound lost until a measurement at the declared scale shows the bound is reached."""}

E['LLR-130'] = {'rep': [('detail', 'A kit refresh copies each kit file to a temporary name and publishes it by rename, never deleting.',
    'A kit refresh replaces each kit file whole, through a temporary name and a rename, with the files that carry the kit revision last, so a state shows the new revision only once its whole new kit is in place.')]}

E['LLR-131'] = {
    'detail': """A kit refresh, holding the claim, takes the kit from the installed program, not from the backup root's existing kit, and places it in the latest state and every saved state. Nothing is deleted, so a refreshed older state may hold both launcher names. Before a state's kit is first replaced, the refresh records the kit revision that state carried as its original kit revision; a later refresh leaves a recorded original revision as it is. Every state's record, evidence, folder record and link record stay byte-identical, and no state's evidence is copied. A normal backup run leaves saved states' kits as they were.""",
    'dimensions': 'states=set{latest,saved,both}; previous_kit=set{current,older}; original_recorded=bool; @pairwise',
    'rationale': """A saved state's kit fixes what it can restore; without an owner-requested refresh a fix in the restore kit never reaches existing history. Refreshing on every run lost because a saved state must keep the kit it was written with unless the owner asks. Copying the root's existing kit lost because a root kit that is itself old or damaged would be spread to every state; overwriting the revision a state was written with lost because that revision is the only age evidence a state with no completeness evidence carries."""}

E['LLR-002'] = {'add': ('detail', ' An empty stream has a digest like any other; a read that fails gives no digest, never the digest of the part read.'),
    'dimensions': 'content=set{empty,one-byte,text,binary-1MiB,large}; read=set{ok,fails-midway}; route=set{library,host-command}; @pairwise'}

E['LLR-022'] = {'add': ('detail', ' At a source root only the change-detection record and its publication temporaries are left out; a file there sharing a name with a backup-only artifact is owner content.'),
    'dimensions': 'path=set{root-infrastructure,nested-same-name,ordinary,retired-launcher,publication-temporary}; folder=set{backup-root,saved-state,source-root}; @pairwise'}

E['LLR-025'] = {'rep': [('detail', 'an optional byte-order mark tolerated, lengths read as integers,',
    'an optional byte-order mark and either common line ending tolerated, lengths read as non-negative 64-bit integers,'),
    ('detail', 'backslash separators mapped to the host\'s.',
    'backslash separators, and forward slashes in a record written by an earlier supported version, mapped to the host\'s.'),
    ('detail', 'A missing record reads as an empty state only where the run-state record shows no earlier backup.',
    'A record holding only its header is an empty state. A missing record reads as an empty state only where the run-state record shows no earlier backup; anywhere else a missing record is damage, never an empty state.')],
    'dimensions': 'records=set{rows,header-only,missing}; field=set{plain,comma,quote,unicode,bracket,space}; byte_order_mark=bool; line_ending=set{lf,crlf}; separator=set{backslash,forward-slash}; route=set{backup,language-runtime-restore,shell-restore}; @pairwise'}

E['LLR-136'] = {'sr_refs': ['SR-145'],
    'rep': [('detail', 'the tools its route needs;',
    'the tools its route needs, the need for the archive tool decided from the stored items\' own opening bytes, not from the recorded form alone;')]}

E['LLR-138'] = {
    'sr_refs': ['SR-116', 'SR-146'],
    'detail': """A state counts as recorded before a kind of record existed (completeness evidence, a folder record, a link record) only on positive evidence. For completeness evidence: the state's original kit revision, recorded by a kit refresh, or where none is recorded the revision its own kit carries, is below the revision that introduced evidence. For the folder and link records: the state's evidence is of a version that does not state their row counts; where it states a count of zero the state has no such record by design, and where it states more the record must be present with that many rows. Such an older state restores as before and its report says each check it could not make, ending complete where nothing else failed. Absence alone is never such evidence: a current-form state missing what it should carry is damage.""",
    'dimensions': 'missing_kind=set{completeness-evidence,folder-record,link-record}; age=set{older-unrefreshed,older-refreshed,current}; stated_rows=set{none,zero,more}; route=set{language-runtime,shell}; @pairwise',
    'rationale': """Taking every missing record as a sign of age lets damage pass as history, and deleting the evidence then switches the check off; refusing every older state lost because states written by supported versions must still restore. Reading age from the kit a state carries now lost once a refresh replaces that kit; a separate format descriptor per state lost because no state written so far carries one, while the evidence version and the original revision a refresh records serve the same purpose with no new record."""}

E['LLR-139'] = {'rep': [('detail', 'A present tool that fails its self-test is a host fault, not a missing tool.',
    'Each tool found is given a self-test before writing (the digest command over a known input, the archive extractor over a known archive); a tool present but failing it refuses the same way, with 2, naming the tool, since nothing has been written and a retry cannot fix it.')],
    'dimensions': 'missing=set{none,digest-command,archive-extractor,text-processor,shell-below-version,runtime-below-version,hashing-library}; self_test=set{passes,fails}; compressed_content=bool; route=set{shell,language-runtime}; @pairwise'}

E['LLR-023'] = {
    'detail': """Before writing, the restore's demand is the recorded length of every entry, compressed ones included, each rounded up to the target's allocation unit (64 KiB where the unit cannot be observed), plus a declared allowance: 4096 bytes per folder and per record entry for folder metadata and the report, 16 MiB fixed, and twice the largest compressed item's expanded size for extraction and verification scratch, charged to the volume that holds the scratch. Where the demand on a volume exceeds its free space, the restore is refused before writing with the precondition-not-met value (2), naming the volume, the space needed and the space free; demand equal to free space passes. A volume that cannot be measured is not refused; the report says the check was not made. The volume is measured the same way on drive-qualified, share and rooted POSIX paths.""",
    'dimensions': 'need_vs_free=set{below,equal,above}; demand=set{few-large-files,many-small-files,compressed-content}; measurable=bool; allocation_unit=set{observed,unknown}; scratch_volume=set{same,other}; restore_system=set{windows,linux,macos}; @pairwise',
    'rationale': """A restore that fills the disk halfway leaves a partial tree and a host fault where a precondition was knowable; leaving compressed entries out of the sum lost because the recorded length is already the expanded size, and an allowance stated only as declared lost because nothing could then check it. Refusing an unmeasurable volume lost: a restorer with a target that hides its free space would have no way to restore at all."""}

E['LLR-071'] = {'rep': [('detail', 'and accepted only when its output is numeric;',
    'and accepted only when its output is numeric, counting the bytes portably where neither style gives a number;'),
    ('detail', 'creates every temporary folder from an explicit template and checks the result;',
    'creates every temporary folder from an explicit template and checks the result, never taking an empty result as a root path;')]}

E['LLR-010'] = {'add': ('detail', ' Under the target the restore writes only the chosen state\'s recorded entries and its report.')}

E['LLR-141'] = {'rep': [('detail', 'A folder-record row that would land outside is not applied and is reported the same way.',
    'A folder-record row that would land outside is not applied and is reported the same way. Containment is checked again immediately before each write, and no file is written through a link met under the target since admission.')]}

E['LLR-050'] = {'constrains': 'IF-045'}

E['LLR-066'] = {'rep': [('detail', 'A read-only file does not block it.',
    "The recorded offset is honoured whatever the restoring host's time zone.")]}

E['LLR-077'] = {
    'title': "A stored item's protection never blocks verification and is not handed to the restored file",
    'detail': """A stored item's read-only protection never blocks the written file's verification or its time stamp, and is not handed to the restored file: every file a restore writes is left writable before it is verified and before its time is set. A source file's read-only state is not part of what a restore reproduces."""}

E['LLR-040'] = {'rep': [('detail', '(a tool absent or below version, a target lacking space)',
    '(a tool absent, below version or failing its self-test at admission, a target lacking space)')]}

E['LLR-073'] = {'rep': [('detail', 'A cancelled or unavailable folder choice never restores into a default target.',
    'An absent, failed or cancelled folder choice gives no target: the restore prints its usage and returns 2, never falling back to a typed prompt or restoring into a default target.')],
    'dimensions': 'start=set{declared-unattended,redirected-input,closed-input,no-console-no-desktop,console-only,desktop}; choice=set{chosen,cancelled,failed,unavailable}; restore_system=set{windows,linux,macos}; @pairwise'}

E['LLR-074'] = {
    'detail': """Each launcher starts the restore from its own state's folder, whatever the caller's working folder, passing every argument through and returning the restore's value. The Windows launcher is one line, with no pause; the macOS launcher asks for the target by folder choice when given no arguments and runs the shell route without needing an executable bit on the restorer. Neither carries restore logic. The macOS launcher is written with its executable permission where the backup volume's filesystem holds one, so a kit opened from the backup's own volume starts by double-click; a kit carried to a Mac inside a zip archive is outside the support boundary, and the user manual gives the one-line remedy. The restore, not the launcher, keeps the outcome and its value on screen until dismissed, whatever the outcome, an unclassified error included, and only when the target came from a folder choice or a prompt, so a scripted caller with arguments is never held and gets the value.""",
    'dimensions': 'restore_system=set{windows,macos}; start=set{double-click,console-no-arguments,scripted-with-arguments}; caller_folder=set{state-folder,elsewhere}; outcome=set{complete,failed,unclassified-error}; @pairwise'}

E['LLR-147'] = {'rep': [('detail', 'and its scratch folder; it writes nowhere else.',
    'and its non-persistent scratch mount; it writes nowhere else.')]}

# ---- build -----------------------------------------------------------------
def q(s):
    s = s.replace(BS, BS + BS).replace('"""', BS + '"' + BS + '"' + BS + '"')
    return '"""' + s + '"""'

def arr(v):
    return '[' + ', '.join('"%s"' % x for x in v) + ']'

def asc(s):
    return (s.replace('‘', "'").replace('’', "'").replace('“', '"')
             .replace('”', '"').replace('–', '-').replace('—', '-'))

KEYS = ['title', 'sr_refs', 'parent', 'constrains', 'detail', 'dimensions', 'rationale', 'hat_refs', 'status']
SECTIONS = {
    'LLR-043': 'Operation launch and outcome', 'LLR-042': 'Configuration',
    'LLR-037': 'Provisioning', 'LLR-015': 'Notification', 'LLR-095': 'Run record and progress',
    'LLR-001': 'Source capture', 'LLR-113': 'Change detection', 'LLR-003': 'Content writer',
    'LLR-005': 'State publication', 'LLR-090': 'Exclusive-use guard',
    'LLR-045': 'Removal and saved-state report', 'LLR-049': 'Check, repair and kit refresh',
    'LLR-061': 'Views', 'LLR-002': 'Store format', 'LLR-136': 'Restore admission',
    'LLR-010': 'Entry restoration', 'LLR-066': 'Tree finishing', 'LLR-040': 'Restore outcome',
    'LLR-073': 'Restore launch and target choice', 'LLR-146': 'Container',
    'LLR-027': 'Release guidance'}
out = ['# low-level-requirements.toml: FileBackup design requirements, round 3, merged tier.',
       '#',
       '# Contract voice: each row states the observable obligation (inputs, outcome,',
       '# refusals) in words that survive a behaviour-preserving refactor. No row names',
       '# a code file, function or symbol; on-disk names, settings and switches are',
       '# interface form, and rows refer to them by role. A top-level row points up with',
       '# sr_refs; a child row names its one parent. Placement is derived from the owner',
       '# of the interface a row constrains. All rows are Drafted.', '']
used = set()
for c in m['llrs']:
    k = c['keep_id']
    if k.startswith('fold:'):
        continue
    base = o.get(k, {'title': c['cluster'], 'sr_refs': c['srs']})
    r = dict(base)
    if c['parent']:
        r.pop('sr_refs', None)
        r['parent'] = c['parent']
    ed = E.get(k, {})
    used.add(k) if ed else None
    for f, old, new in ed.get('rep', []):
        if old not in r[f]:
            sys.exit(f'ANCHOR MISSING {k}.{f}: {old[:60]}')
        r[f] = r[f].replace(old, new)
    if 'add' in ed:
        f, t = ed['add']
        r[f] = r[f] + t
    for f, v in ed.items():
        if f not in ('rep', 'add'):
            r[f] = v
    r['status'] = 'Drafted'
    for f in ('detail', 'rationale'):
        if not r.get(f):
            sys.exit(f'EMPTY {k}.{f}')
    if k in SECTIONS:
        out.append(f'# === {SECTIONS[k]} ' + '=' * max(4, 70 - len(SECTIONS[k])))
        out.append('')
    out.append(f'[design.{k}]')
    for kk in KEYS:
        if kk not in r:
            continue
        v = r[kk]
        if isinstance(v, list):
            out.append(f'{kk} = {arr(v)}')
        elif kk in ('detail', 'rationale'):
            out.append(f'{kk} = {q(asc(v))}')
        elif '"' in v or BS in v:
            out.append(f'{kk} = {q(asc(v))}')
        else:
            out.append(f'{kk} = "{asc(v)}"')
    extra = set(r) - set(KEYS)
    if extra:
        sys.exit(f'EXTRA KEYS {k} {extra}')
    out.append('')
missing = set(E) - used
if missing:
    sys.exit(f'EDITS FOR UNKNOWN ROWS {missing}')
(D / 'r3-merged/low-level-requirements.toml').write_text('\n'.join(out), encoding='utf-8', newline='\n')
print('rows', sum(1 for l in out if l.startswith('[design.')), 'edited', len(used))
