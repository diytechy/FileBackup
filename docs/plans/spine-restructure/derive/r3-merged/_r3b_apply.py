# Round 3b: applies the full-round-1 review dispositions (r3-dispositions.md)
# to the design tier and the named SR rows. Reads every carrier from git HEAD,
# so re-running it reproduces the same result. Writes docs/requirements/*.toml.
import subprocess, sys, tomllib
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
E = Doc(head('external.toml'))

# ======================================================================
# SR tier (only the rows the dispositions name)
# ======================================================================

# R3S-007 + R3O-005 + R3O-006: SR-017's acceptance gives every case its value.
R.set('SR-017', 'acceptance_criteria', """With an earlier run's unfinished work that may hold content (hidden, system and dot-named content included), with the unfinished work of a removal that did not complete, with an earlier run alive or not proven dead, with a state's record whose completeness evidence does not match and that cannot be identified as an interrupted publication, with unfinished work reached through a link or other redirection, or with evidence that cannot be read, the next run moves and deletes nothing, publishes no saved state, is refused, and its message names what was found. Liveness evidence that can be read, a torn copy of it included, but does not prove the earlier run dead counts as an earlier run alive or not proven dead; liveness evidence, or a listing of the unfinished work, that still cannot be read after the run's bounded re-reads is evidence that cannot be read, which waiting will not change. The refusal reports, by the precedence of SR-043: a precondition not met (value 2) where any finding other than a damaged record or a live or unproven earlier run is present, since only someone acting on what was found resolves it; a damaged record (value 3) where the findings are a damaged record, with or without a live or unproven earlier run; and busy (value 4) where the only finding is an earlier run alive or not proven dead. Where the unfinished work is a removal's, the message names the remedy, re-running that removal, which completes it (SR-101), after which backups proceed. Unfinished work that holds no content does not by itself cause the refusal. When a safe clean-up of reclaimable unfinished work cannot begin, because moving it aside or creating fresh working state fails, the run is refused with nothing lost: busy (value 4) where the cause is an I/O fault, a precondition not met (value 2) where access is denied. When only the clean-up's final delete fails, the leftovers, which hold no content, are kept and named with recovery guidance, and the run completes (value 0).""")
R.set('SR-017', 'permutations', 'leftover=set{may-hold-content,removal-unfinished,owner-alive,owner-unproven,damaged-record,linked,unreadable-evidence,holds-no-content}; cleanup=set{none,start-fails-io,start-fails-access,final-delete-fails}; @pairwise')

# R3O-004: SR-086 states the refusal and leaves the value to the acceptance.
R.set('SR-086', 'title', 'A backup whose exclusive use cannot be established is treated as held, and the change is refused')
R.set('SR-086', 'requirement', 'If the system cannot establish exclusive use of a backup for any reason, then the system shall treat the backup as held, for safety, and refuse the changing operation without creating, moving or deleting anything in it.')

# R3S-011 (P-10): SR-106 holds for every state the concurrent operation does not remove.
R.set('SR-106', 'acceptance_criteria', 'A check, the saved-state report and a restore started while a backup, a removal, a repair or a kit refresh is running each complete with their normal outcome against every complete state the running operation does not remove. A restore of the saved state that a running removal deletes either completes byte-exact or ends with retry later (value 4, SR-043) naming the removal; every file it has written is byte-exact, and no file is restored wrongly. A check or the report that meets a saved state removed while it reads leaves that state out as no longer present and reports no finding for it.')
R.set('SR-106', 'rationale', 'Locking readers out turns every long backup into an outage for restores and checks. A removal deletes the state it removes, so completion cannot be promised to a reader of that one state; promising it would need readers to hold removals back, which a restore cannot do, since it leaves nothing in the backup that a removal could see.')
R.set('SR-106', 'permutations', 'reader=set{check,report,restore}; writer=set{backup,removal,repair,kit-refresh}; state=set{kept,being-removed}; @pairwise')

# R3O-028: SR-109 drops the unexplained second condition.
R.sub('SR-109', 'rationale', 'Where no such copy exists, or more than one candidate answer remains, the finding is reported', 'Where no such copy exists, the finding is reported')

# R3S-003 + R3O-007 + R3O-027: SR-121's link clauses.
R.set('SR-121', 'requirement', 'If a file entry in the record of a state being restored would land outside the restore target, by its path or through a link, or a recorded link would be placed outside the target or, where it led to a folder captured in the state, would be re-pointed to outside the target, in a restore that has passed admission (SR-145), then the restore kit shall leave it unwritten, name it, and report the damaged-record outcome.')
R.set('SR-121', 'rationale', "A damaged or crafted record can name a path that climbs out of the target, or redirect through a link, and overwrite files the restorer never meant to touch. Joining path text blindly lost to checking where the write really lands. A recorded link into the system's own locations is the owner's and is recreated as a link pointing there (SR-152); its own place is checked like a file's, its target is not, and it is made after every file, so nothing is written through it.")
R.set('SR-121', 'acceptance_criteria', "A record holding entries with parent-climbing, absolute and drive-qualified paths, and entries redirected outside the target through a link, restores every other entry, writes nothing outside the target, names and counts each such entry as not restored, and returns exit code 3. A state recording a link whose own place climbs out of the target, and an inside link whose re-pointed target climbs out of the target, restores every other entry, creates neither link, names each, and returns exit code 3; a link into the system's own locations, rebuilt pointing to its original path outside the target (SR-152), is not refused. A record holding such an entry whose completeness evidence does not match is refused before anything is written, with exit code 3 (SR-039, SR-145).")
R.set('SR-121', 'permutations', 'path_form=set{parent-climb,absolute,drive-qualified,via-link}; entry=set{file,link}; restorer=set{windows,linux,macos}; target_exists=bool; @pairwise')

# R3S-001 + R3S-025 + R3O-008: SR-137's follow predicate and its wait bound.
R.set('SR-137', 'requirement', "When a source holds a link or junction to a folder outside that source and outside the system's own locations, and that folder is not one of the link's own ancestors in the walk, the system shall capture what it leads to as part of the source, under the link's path.")
R.set('SR-137', 'acceptance_criteria', "With a folder link and a junction inside a source, each leading to a folder on another volume outside every system location, the run captures every file behind them under the link's path, and a restore produces them as ordinary folders and files at that path under the target; two links to the same outside folder both appear in the record and the content behind them is stored once; a link to a single file is captured and restored as the file it leads to; a link inside a followed outside folder that leads back to one of its own ancestors is recorded and not followed (SR-150), and the walk ends. A link whose target cannot be reached is named in the run's record as not captured, its earlier captured content is not recorded as removed, and the run reports part failed (value 1, SR-043). The waiting on unreachable link targets in one location, together with that location's waiting to retry unreadable files (SR-090), totals no more than 60 seconds in a run; once that is spent, further unreachable link targets are named without waiting.")
R.set('SR-137', 'permutations', 'link=set{folder-link,junction,file-link}; target=set{other-volume,network-share,unreachable,ancestor-in-walk}; repeated=bool; unreachable_links=range[0..1000]; @pairwise')

# R3S-006 (P-09): SR-144's requirement aligned with its acceptance.
R.set('SR-144', 'title', 'A run whose work was reclaimed after its claim was lost changes nothing its successor made and publishes nothing more')
R.set('SR-144', 'requirement', 'If a run resumes after a successor has reclaimed its work because its claim of exclusive use was no longer held and its liveness evidence was stale beyond the stale time, then the system shall change no file its successor wrote or published, publish nothing further in that backup, and end the resumed run without reporting it complete.')
R.set('SR-144', 'acceptance_criteria', 'A run suspended while it holds its claim, for longer than the stale time, keeps the backup held: a successor is refused as busy (value 4, SR-085) until the claim is released, and the store is unchanged by it. A run on another host or container whose claim the successor does not see, suspended for longer than the stale time while the successor reclaims its unfinished work and completes, then resumed, changes no file the successor wrote or published, publishes nothing, leaves at most one unpublished temporary file that the next run removes, every state restores as the successor left it, and the resumed run ends with the part-failed outcome (value 1) and a record saying its work was reclaimed.')
R.sub('SR-144', 'rationale', 'so the protection sits on the resuming side: it must notice it no longer holds the backup and touch nothing its successor wrote.', 'so the protection sits on the resuming side: it must notice it no longer holds the backup and touch nothing its successor wrote. No check can close the window between reading the evidence and the write it guards, so the promise is the one a check before every write can keep: at most one unpublished temporary, which changes nothing the successor made and is removed by the next run.')

# R3O-014: SR-146 extends to the link record.
R.set('SR-146', 'title', 'A current-form state with missing or malformed folder metadata or links restores its files and reports part failed')
R.set('SR-146', 'requirement', "If the folder record or the link record of a current-form state is missing or malformed, or holds fewer rows than the state's completeness evidence states, then the restore kit shall still restore every file of that state, name the folder metadata and the links it could not apply, and report the part-failed outcome.")
R.sub('SR-146', 'rationale', 'so a complete outcome would tell the restorer the tree is whole when it is not (SN-053).', 'so a complete outcome would tell the restorer the tree is whole when it is not (SN-053); a lost link record loses the links SN-036 asks for in the same way.')
R.set('SR-146', 'acceptance_criteria', "With a current-form state's folder record removed, malformed and short of its stated rows, and with its link record removed, malformed and short of its stated rows, every file restores byte-exact, the report names the folder metadata not applied (empty folders not recreated, attributes not applied) or the links not rebuilt, and the restore ends with exit code 1, through every restorer; a state positively identified as written before folder metadata existed ends with exit code 0 (SR-116).")
R.set('SR-146', 'permutations', 'record=set{folder,link}; fault=set{missing,malformed,short}; restorer=set{windows,linux,macos}; @pairwise')

# R3O-025: SR-150 and SR-151 carry no PERFORMANCE hat; SN-001's acceptance states both.
R.delete('SR-150', 'hat_refs')
R.set('SR-150', 'rationale', "SN-001's acceptance states it: links that lead inside the same source or back to one of their own ancestors are recorded and rebuilt at restore rather than followed. A link back to one of its own ancestors makes a walk that follows it never end, and a link to a folder already inside the source would capture that content a second time under another path for no gain, since the content itself is captured at its real place. Recording the link instead keeps the restored tree the way it was (SN-036): the link comes back as a link. Following inside links and relying on de-duplication lost: it cannot end on a cycle.")

# R3O-025 + R3O-026 + R3O-029 (P-11): SR-151.
R.delete('SR-151', 'hat_refs')
R.set('SR-151', 'requirement', 'When a source holds a link or junction to a folder inside the backup, its saved states, the change-detection state, the logs or the listing location, the system shall record the link and where it leads without following it.')
R.set('SR-151', 'rationale', "SN-001's acceptance states it: links that lead into the backup's own locations are recorded and rebuilt at restore rather than followed. Following a link into the backup backs the backup up into itself, and the store grows by its own size every run until the volume fills; following one into the listing location captures the generated views as source content. The link is the owner's, so it is recorded and comes back at restore like any other (SR-152), pointing where it pointed; only what lies behind it is the system's own, which SN-001 already leaves out.")
R.set('SR-151', 'acceptance_criteria', "With a link inside a source leading to the backup root, one to a saved state's folder, one to the change-detection state location, one to the log location and one to the listing location, the run captures nothing from behind them, the store does not grow by their content, each link is recorded with where it leads, and their presence does not change the outcome from complete.")
R.set('SR-151', 'permutations', 'leads_to=set{backup-root,saved-state,state-location,log-location,listing-location}; @full')

# R3O-027 + R3S-002: SR-152 traces to SN-001 too; a captured ancestor is re-pointed.
R.set('SR-152', 'sn_refs', ['SN-036', 'SN-001'])
R.set('SR-152', 'requirement', 'When a restored state records a link, the restore kit shall recreate it at its place under the target after every file is written, pointing at the matching path under the target where it led to a folder captured in the state, and at the path it led to otherwise.')
R.set('SR-152', 'acceptance_criteria', 'A state recording a link inside its source, a junction inside its source, a link inside a followed outside folder back to one of its ancestors, and a link into the backup restores each as a link at its place: the first three lead to the matching folders under the target and open their restored content, the last leads to its original path; no file is written through any of them. On a target that cannot create a link of that kind, or without the right to, the restore names each link it could not recreate and the outcome stays complete (value 0).')
R.set('SR-152', 'permutations', 'link=set{inside-source,junction-inside-source,ancestor-in-followed-folder,own-location}; target_os=set{windows,linux,macos}; can_create_links=bool; @pairwise')

# ======================================================================
# external.toml (R3O-050)
# ======================================================================
E.set('B-01', 'carries', "Each source file's bytes, name, size, modification time and attributes, the directory structure including empty and hidden folders, and each folder link and junction with the target it leads to, read without writing anything back to the source.")
E.set('B-16', 'carries', "The restored tree written to the target: each file's bytes, name and modification time, empty folders, the folder attributes the target supports, and the recorded links.")

# ======================================================================
# Components (R3O-049, R3O-012)
# ======================================================================
NOIF = ' It owns no interface, so its rows show as unplaced: placement is derived only through an interface\'s owner, and no interface was minted just to place them.'
C.sub('CMP-002', 'notes', 'Today this is the thin entry-point script plus the outcome mapping scattered through the backup-only engine module: the per-location fold lives in the entry point, but the classification of each refusal into a value lives inside each operation.',
      "Today this is the thin entry-point script plus the outcome mapping scattered through the backup-only engine module: the per-location fold lives in the entry point, and so do the values of a check and of a view rebuild, while every other operation classifies its own refusals into a value. Its interfaces carry the rows that state the request, the outcome value and the findings document; the report's and the check's own findings rows sit with their components, unplaced.")
C.sub('CMP-003', 'notes', 'so a listing-location refusal happens late rather than at launch.', "so a listing-location refusal happens late rather than at launch. The global record's own location check has no interface of this component to sit on and shows as unplaced.")
C.sub('CMP-004', 'notes', 'Today the hashing-component loader sits in the restore-safe shared library (so the restorer can load the bundled copy) and tool discovery sits in the backup-only engine module; the split is sound, but the restore-side loader can still fall back to a package-source install with a prompt, which the restore kit must never do.',
      'Today the hashing-component loader and the archive-tool and media-tool lookups all run when the restore-safe shared library loads (so the restorer can load the bundled copy), and the backup-only engine module uses what they found; the restore-side loader can still fall back to a package-source install with a prompt, which the restore kit must never do. Its rows on the runtime floor and the package source constrain external interfaces and show as unplaced.')
C.sub('CMP-005', 'notes', 'Today it is a short block at the end of the entry-point script.', 'Today it is a short block at the end of the entry-point script. Its credential row constrains the external credential facility and shows as unplaced.')
C.sub('CMP-008', 'notes', 'Today the walk does not distinguish links at all (directory links are never descended and are not recorded), and a file that cannot be hashed aborts the whole location instead of being named.',
      'Today the walk does not distinguish links: it lists a folder link like a folder and writes it to the folder record as an empty folder, so a link comes back from a restore as an empty folder; and a file that cannot be hashed aborts the whole location instead of being named.' + NOIF + ' Most of them state behaviour across the external source tree view.')
C.sub('CMP-009', 'notes', 'a missing record is silently treated as empty and an unreadable one fails the location rather than being rebuilt.', 'a missing record is silently treated as empty and an unreadable one fails the location rather than being rebuilt. It owns the change-detection record; the re-read schedule row states no behaviour across it and shows as unplaced.')
C.sub('CMP-010', 'notes', 'so a list edit moves the kit revision although no restore reads the list.', 'so a list edit moves the kit revision although no restore reads the list.' + NOIF + ' The stored-object name and form it writes is the store format\'s interface.')
C.sub('CMP-011', 'notes', 'with the record writer in the restore-safe shared library.', "with the record writer in the restore-safe shared library. It owns only the run-state record; its publication rows state behaviour across the store layout and the record of contents, which the store format owns, so they show as unplaced rather than placed in the format.")
C.sub('CMP-012', 'notes', 'which is right: it has no restore-side meaning.', 'which is right: it has no restore-side meaning. The readers\' rule of taking no claim is stated here, across the claim.')
C.sub('CMP-013', 'notes', 'Today it is the retention part of the backup-only engine module.', "Today it is the retention part of the backup-only engine module. It owns the content-location index; its refusal, confinement, interruption and report rows state behaviour across the outcome value, the request, the store layout and the findings document, owned elsewhere, so they show as unplaced.")
C.sub('CMP-014', 'notes', 'and repair renames objects but never copies content back.', 'and repair renames objects but never copies content back.' + NOIF)
C.sub('CMP-017', 'notes', 'One set of requirements binds both routes; parity between them is verified per route at the test tier.', 'One set of requirements binds both routes; parity between them is verified per route at the test tier. It owns the kit artifact set, the restore request and the restored tree, which its children produce together, so rows of its children that state behaviour across those are placed here.')
C.sub('CMP-018', 'notes', 'and neither consults positive age evidence.', "and neither consults positive age evidence. It owns no interface: its rows on the target probe and the tool floor constrain external interfaces and show as unplaced, and its age and kit-revision rows are placed at the restore kit through the kit artifact set.")
C.sub('CMP-019', 'notes', 'Owns the content search by key, whose answer set both routes must give alike.', 'Owns the content search by key, whose answer set both routes must give alike; its rows on the restored tree are placed at the restore kit, which owns that tree.')
C.sub('CMP-020', 'notes', 'and folder metadata that is missing or malformed never changes the outcome.', 'and folder metadata that is missing or malformed never changes the outcome. It owns no interface: its time rows are placed at the restore kit through the restored tree, and its folder-record and link-record rows show as unplaced, the two records being the store format\'s.')
C.sub('CMP-022', 'notes', 'so it can never reach an automated caller.', "so it can never reach an automated caller. It owns no interface: the restore request is the restore kit's, so its launcher rows are placed there, and its folder-choice rows constrain the external session and dialog and show as unplaced.")

# ======================================================================
# Interfaces
# ======================================================================
I.set('IF-002', 'data', """One process start of the backup program with named switches (case-insensitive, each at most once):
- -Action <word>: one of Backup (the default when absent), Prune (remove named saved states), Snapshots (the saved-state report), Verify (the check), View (rebuild the browse view).
- -Snapshot <name>[,<name>...]: the saved states a Prune acts on, each a saved-state folder name of the store layout (IF-013).
- -RepairStorage, -RefreshKits: with -Action Verify, run the repair or the kit refresh.
- -BackupRootOnly: with -Action Verify, check the latest state only; -IncludeSnapshots given the value false is accepted as the same request.
- -Deep: with -Action Verify, the former request for a payload check; accepted, carries no meaning.
- -VerifyStorage: accepted as the same request as -Action Verify.
- -WhatIf: with -Action Prune only, the removal dry run; with any other action a bad request.
General switches, accepted with every action:
- -ConfigPath <path>: the configuration document (IF-005 or IF-006); default a documented location in the invoking account's home folder.
- -GlobalLogPath <path>: the global run record (IF-009); default beside the configuration.
- -NoMail: switch notification off for this run.
- -NonInteractive: declare that no person is present.
- -AutoInstallDeps: the former permission to obtain the required component; accepted, carries no meaning.
- -ExitCode: the former request for distinct outcome values; accepted, carries no meaning.
- -BackupTime <ISO-8601 time>: a test seam that sets the run's clock in place of the host's.
Any other switch, an unknown action word, or a switch that does not apply to the chosen action is a bad request.""")

I.sub('IF-003', 'data', '- 3 refused over a damaged record of a state;', '- 3 a damaged record of a state: the operation refused over it, or a check found it;')

I.set('IF-004', 'data', """The one catalogue of settings, whatever the document form. Top level:
- ConfigVersion: integer, required; the description version the document follows. Supported: 2.
- BackupSets: one or more location sets, required.
- Tools: optional; SevenZipPath (string, a path), FfprobePath (string, a path).
- Secrets: optional; ToEmail, FromEmail, SmtpServer (strings, non-empty where present), SmtpPort (integer, 1 to 65535, default 25), and in the native-Windows form only, Credential (a host-protected credential, IF-012). The notification fields are ToEmail, FromEmail and SmtpServer: notification is set up only when all three are present.
Each location set:
- Name: string, non-empty, required.
- SourcePath, BackupPath, ChangePath: strings, non-empty paths, required; the source, the backup (latest state) and the saved-state locations.
- HashRecalcFreq: required, one of A or E (every run; A is an accepted synonym of E), D (daily), W (weekly), M (monthly), Y (yearly), N (never); case-insensitive.
- CompressEnabled: boolean, required.
- CompressProbe: optional, one of off, excluded-extensions, always (exact lower case); default always.
- BrowseView: optional, one of off, index (exact lower case); default off. The word link is reserved and refused.
- ViewPath: optional path, the listing location; default the BackupPath followed by _View.
- SpaceView: optional boolean; default false.
- SourceStatePath: optional path, the change-detection record's location; default the source root.
- AllowEmptySource: optional boolean; default false.
Retired keys, refused by name: PreserveFolderTree.""")

# R3O-011: the restore-side variables leave IF-007 for IF-026; IF-007 lists its consumers.
I.delete('IF-007', 'requestors')
I.set('IF-007', 'consumers', ['CMP-006', 'CMP-010'], after='owner')
I.set('IF-007', 'data', """Process environment variables of the backup side, each optional, set by the host or the container:
- FILEBACKUP_7ZIP_PATH: path of the archive tool.
- FILEBACKUP_FFPROBE_PATH: path of the media-measurement tool.
- FILEBACKUP_7Z_LEVEL: the archive tool's effort level, exactly one of the ten strings 0 to 9 with no padding; absent or empty means 9.
- FILEBACKUP_LOG_PATH: location of the global run record.
The restore side's variables are part of the restore host session (IF-026).""")

I.set('IF-009', 'data', """Two kinds of record, each UTF-8 text, one entry per line:
- the global record, one per launch, at the location the launch request or FILEBACKUP_LOG_PATH gives, by default Backup_Global.log beside the configuration document;
- one location record per configured location, named backup.log in that location's saved-state root (IF-013).
Entry grammar: <yyyy-MM-dd HH:mm:ss.fff host-local> [<LEVEL>] <message>, LEVEL one of DEBUG, INFO, WARN, ERROR. The console carries the same entries in the same grammar.
Message kinds:
- Added: <path> | Changed: <path> | Removed: <path>
- Failed: <path> - <cause> | Not captured: <path> - <cause>
- Retried: <path> - attempt <n> of 3 | Retry limit reached: <seconds> s spent in this location
- Progress: <phase> <entries done>/<entries known> entries, <bytes> bytes, phase one of reading, storing, finalising
- Summary: added=<n> changed=<n> removed=<n> failed=<n>
- Refused <token>: <what was found>. Remedy: <what to do>
- Rebuilt change-detection state: <reason> | Rebuilt run state: <reason>
- Space check not made: <volume> - <reason>
- Work reclaimed: run <run identity> lost its claim and changed nothing more
- Leftovers kept: <folder> - <recovery guidance>
- Notification skipped: <reason> | Notification failed: <cause>
- Media measure not taken: <reason> | Extra skipped: <name>
Refusal tokens, a closed set, each with the outcome value it reports:
- [SR-075/owner-live]: an earlier run alive or not proven dead (4);
- [SR-075/content-refused]: unfinished work holding content, reached through a link, or whose evidence cannot be read (2);
- [SR-075/prune-held]: a removal's unfinished work (2);
- [SR-075/lock-held]: the claim is held by another operation (4);
- [SR-075/lock-lost]: this run's claim was lost (1);
- [SR-075/reclaimed]: a dead run's leftovers were reclaimed (an entry, not a refusal);
- [SR-075/heartbeat]: a liveness refresh failed (an entry, not a refusal);
- [2/staging-busy]: a removal refused by a staging area holding more than its own marker;
- [2/configuration]: a refused configuration;
- [2/record-location]: a refused global record location;
- [2/bad-request]: a bad request;
- [2/claim-location]: access to the claim denied, or its location unusable;
- [4/claim-io]: an I/O error while taking the claim;
- [2/capacity]: a volume lacking the space a run or a removal needs;
- [2/tool]: a runtime, component or tool missing or below its version;
- [2/unsupported-form]: a store or state in a retired or unrecognised form;
- [2/empty-source]: a source that suddenly looks empty;
- [2/location-overlap]: configured locations that overlap;
- [2/read-only-source]: a source the run cannot write, with no state location;
- [2/removal-refused]: a removal that could lose content;
- [3/record-damage]: a state's record failing its completeness evidence;
- [4/host-fault]: a host fault while the operation worked.""")
I.set('IF-009', 'rationale', """An owner reading why a run failed, and a host searching for a refusal class, need stable entry kinds; free prose cannot be searched and a count without the names cannot be acted on. A structured log in a machine format lost for the owner-facing record: the machine-readable form is IF-010, and a person reads this one. The SR-075 tokens are kept exactly as hosts already search for them; every other token names the value and the cause and no requirement, because requirement numbering is not a host-visible form, and the set is closed so a host can match every refusal.""")

I.set('IF-010', 'data', """One UTF-8 JSON document on standard output.
Saved-state report: an array, one object per saved state, oldest first: Name (string, the saved-state folder name), Date (string, ISO-8601), Rows (integer), PhysicalBytes, BytesReclaimed, BytesReHomed (integers, bytes).
Check, and check with repair: an array, one object per finding, empty when clean. Every finding carries Folder (string), FolderName (string), RelativePath (string, empty for a finding about a folder or a stored object rather than an entry), DataPath (string, possibly empty), Class, Observed (string), Expected (string), Repairable (boolean) and KitRevision (integer or null); with repair, also Repaired (boolean).
Class, one of:
- PoolDataPathMissing: an entry's stored-copy reference names a copy absent from its folder while the same content survives elsewhere in the backup (missing from its place);
- PoolUnresolvable: an entry whose content is found nowhere in the backup (missing from the whole backup);
- FlagOverRaw: the entry records the archive form over raw bytes at its place;
- FlagOverArchive: the entry records the raw form over bytes that are an archive and not the entry's own content;
- NameLies: the stored name claims a form its bytes do not have, the recorded form agreeing with the bytes;
- PayloadMismatch: the stored bytes, expanded where they are an archive, do not have the entry's digest and length (content altered);
- BlankRowFormDisagreement: a blank entry whose recorded form disagrees with the form of the copy the search by content key locates, in a state whose own kit cannot decide form from the bytes;
- Unreferenced: a stored object that no entry of any record references;
- LegacyStoredForm: a state in a retired form;
- RecordEvidenceMismatch: a state's record that fails its completeness evidence.
DanglingDataPath, the earlier name of a missing-from-its-place finding, is retired.""")
I.set('IF-010', 'version', '2')

I.set('IF-011', 'data', """One mail message: submitted by SMTP to Secrets.SmtpServer on Secrets.SmtpPort (default 25), the session upgraded to TLS by STARTTLS before the message is sent; From Secrets.FromEmail, To Secrets.ToEmail; subject Automatic Backup Successful or Automatic Backup Failed; a plain-text body holding the run's summary entries. Authentication: SMTP AUTH with the stored login (IF-012), or none.""")

I.set('IF-013', 'data', """Two roots per configured location.
Backup root (BackupPath), the latest state:
- MANIFEST.csv: the record of contents (IF-014); MANIFEST.csv.meta: its completeness evidence (IF-015);
- MANIFEST.csv.tmp, MANIFEST.csv.meta.tmp: publication temporaries;
- DIRECTORIES.csv: the folder record (IF-017), present only when it has rows; LINKS.csv: the link record (IF-018), present only when it has rows;
- FileBackupState.json and FileBackupState.json.tmp: the run-state record (IF-030);
- the restore kit (IF-019);
- the stored objects, flat at the root, named by IF-016;
- a stored object's publication temporary: its stored name followed by .fbprune.tmp (a removal's or a repair's copy) or by .fb-<8 lowercase hex digits>.tmp (any other writer); a name of this form is a temporary only where no entry of the folder's record names it.
Saved-state root (ChangePath):
- one folder per saved state, named Snapshot_<yyyy>_<MM>_<dd>_<HH>_<mm>_<ss>[_<NNN>] and matching exactly ^Snapshot_\\d{4}_\\d{2}_\\d{2}_\\d{2}_\\d{2}_\\d{2}(_\\d{3})?$; the date and time are host-local, and the optional three-digit suffix separates two folders of the same second. Each holds its own MANIFEST.csv, MANIFEST.csv.meta, DIRECTORIES.csv and LINKS.csv where present, its own restore kit, the stored objects only it preserves and their publication temporaries;
- Temp: the staging area (IF-033); Temp.lock: the claim file (IF-032); Temp.stale-<yyyyMMddTHHmmssZ>-<8 hex digits>: reclaimed leftovers; Pruning_<saved-state folder name>: a removal past its commit point;
- backup.log: the location record (IF-009).
Infrastructure names are names at a folder's own root; the same names deeper in a folder are data. RECONSTRUCT.bat, the retired launcher name, is an infrastructure name.""")

I.set('IF-014', 'data', """CSV per RFC 4180, UTF-8, every field quoted, a header row then one row per file of the state, rows in ordinal order of RelativePath; written without a byte-order mark and with LF line endings, read with or without a byte-order mark and with LF or CRLF line endings. A record of a state with no file is the header alone. Columns, in order:
- DataPath: the stored object's name in the state's own folder (IF-016), or blank meaning locate the content by its content key anywhere in the backup;
- RelativePath: the file's path under the source root, components separated by a backslash whatever the host; records written from Linux by earlier versions use the forward slash;
- Length: non-negative 64-bit integer bytes;
- LastWriteTimeStr: the file's modification time as <yyyy>-<MM>-<dd>T<HH>:<mm>:<ss>.<seven fraction digits><offset>, the offset either Z or a sign, two hour digits, a colon and two minute digits; opaque to the backup side, interpreted by a restore;
- xxH2Hash: the content digest (IF-034 text form);
- Compressed: Yes or No, the form the writer recorded;
- StoredAsHashSize: the storage-layout marker, Hash for the current form; Original marks a retired form;
- Duplicate: 0, 1 or empty;
- MediaMBPerSec: blank, or a decimal with three places in a record written by an earlier version; the measures live in the space view (IF-042).
The content key of a row is the pair (xxH2Hash, Length).""")
I.set('IF-014', 'consumers', ['CMP-009', 'CMP-011', 'CMP-013', 'CMP-014', 'CMP-015', 'CMP-017'])

I.set('IF-015', 'data', """A sidecar beside each record of contents, UTF-8 without byte-order mark, LF line endings, one key=value per line:
- Version=<integer>: the evidence format version, currently 3; a version below 2 marks a retired form;
- Rows=<integer>: data rows in the record;
- Bytes=<integer>: the record's length in bytes;
- XxH128=<32 hex digits>: the content digest of the record's bytes exactly as written;
- Written=<ISO-8601 time>: when the record was written;
- DirRows=<integer>, LinkRows=<integer>: the rows of the state's folder record and link record, 0 when the state has none; present from evidence version 3. Evidence of version 2 states neither, and was written both before and after folder records existed.""")

I.set('IF-017', 'consumers', ['CMP-008', 'CMP-011', 'CMP-020'])

I.set('IF-018', 'data', """CSV per RFC 4180, UTF-8 without byte-order mark, every field quoted, rows in ordinal order of RelativePath. Columns:
- RelativePath: the link's path under the source root, in the walk, backslash-separated;
- LinkKind: one of symlink, junction;
- TargetClass: one of inside-source (the target is a folder the walk captures: a folder of the same source, or an ancestor of the link, one reached through a followed outside folder included), own-location (the target lies in the backup, its saved states, the change-detection state location, the record location or the listing location);
- Target: for inside-source, the path at which the walk captured the target, under the source root and through followed links, backslash-separated; for own-location, the target's absolute path as it was resolved at backup time.
Present only when the state records at least one link.""")

I.set('IF-019', 'data', """The kit's closed name set; every state's folder carries these artifacts, each at the folder's root:
- RECONSTRUCT.cmd: the Windows launcher, ASCII with CRLF line endings: a remark line REM KitRevision: <integer>, then one command line;
- RECONSTRUCT.command: the macOS launcher;
- RECONSTRUCT.ps1: the language-runtime restorer;
- reconstruct.sh: the shell restorer;
- FileBackup.Common.psm1: the restore-safe shared library;
- System.IO.Hashing.dll: the hashing library the language-runtime route loads, at the version of IF-037;
- RECONSTRUCT.paths.json: a JSON object {BackupRoot: string, ChangeRoot: string, KitRevision: integer}, BackupRoot and ChangeRoot absolute paths at backup time;
- THIRD-PARTY-NOTICES.txt: a first line KitRevision: <integer>, then, for each third-party component in the folder, its name, version, licence and required notice text;
- KIT-ORIGIN.txt: present only in a state whose kit a kit refresh has replaced; UTF-8, one line OriginalKitRevision=<integer>, the kit revision the state carried before its first refresh.
Recognised, never written: RECONSTRUCT.bat, the retired Windows launcher.
Kit revision: every text artifact above but KIT-ORIGIN.txt carries one, equal in all of them; the restorers, the library and the macOS launcher as a line # KitRevision: <integer>. The hashing library is identified by its version, which the kit revision fixes. A text artifact without a revision belongs to a kit older than revision 14, in which only the two restorers carried one. The revision records which record kinds that kit writes and reads.""")
I.set('IF-019', 'version', '14')
I.set('IF-019', 'rationale', """A state whose kit is incomplete restores only where FileBackup is installed, which is the case the kit exists for, and a kit mixing two revisions can run code against a library it was not written for. Putting one kit at the backup root only lost: a saved state copied out on its own, or a store whose root kit was refreshed, must still restore with the kit it was written with. Leaving the file names to the kit's own documentation lost because the writer, the launchers, the loader, the kit refresh and the infrastructure-name test all need the one closed set.""")

I.set('IF-020', 'owner', 'CMP-017')
I.set('IF-020', 'data', """Language-runtime route switches: -TargetRoot <path>, -BackupRootOverride <path>, -ChangeRootOverride <path>, -SevenZipPath <path>, -RequireWitness, -NonInteractive, -NoGui, -ExitCode (accepted, no meaning).
Shell route switches: --target-root <path>, --from <state folder>, --backup-root <path>, --change-root <path>, --seven-zip <path>, --require-witness, --pick-target, -h or --help.
Double-click: RECONSTRUCT.cmd on Windows, RECONSTRUCT.command on macOS, each with no arguments.
An unknown switch, a switch without its value, or a missing target where none can be asked for is a bad request.""")
I.set('IF-020', 'rationale', """A restorer under stress must be able to start a restore by double-click, and a script must be able to start one with no prompt; one form serving both lost nothing. A form with a required state argument lost: the folder a person opens already says which point in time it is, so the state switch is optional.""")

I.set('IF-022', 'data', """The report, in the restore target's root: RECONSTRUCT.log or, where the state records a file at that path (compared as the target compares names), the first of RECONSTRUCT-1.log, RECONSTRUCT-2.log and so on at which the state records no file. UTF-8 text, one entry per line in the run-record entry grammar (IF-009); the console carries the same entries. Entries:
- Not restored: <path> - <cause> per entry, cause one of ContentMissing, ContentMismatch, PathTraversal, NameCollision, MissingDataFile, NoDataPathOrHash, DependencyMissing, StorageUnreadable, CandidateError, WriteMismatch, StateRemoved;
- Not applied: <path> - <what> for folder metadata, a modification time or a link;
- Recovered: <path> - from <folder>;
- Unverified: <check> - <reason> for a check an older state cannot support;
- the final summary: restored=<n> not-restored=<n> content=<n> host=<n> outcome=<value>, followed by the names of every entry not restored.""")

I.set('IF-023', 'data', """Under the chosen target folder: each file of the state at its RelativePath (separators mapped to the target host's), with the recorded bytes and the recorded modification time; each recorded folder, empty ones included, with the recorded attributes the target can hold; each recorded link as a link at its RelativePath; and the restore report (IF-022), at a name no recorded file takes.""")

I.set('IF-025', 'consumers', ['CMP-018', 'CMP-019', 'CMP-020'])

I.set('IF-026', 'data', """Signals read at restore start: the operating system (Windows, Linux, macOS); whether standard input is redirected or closed; whether an interactive console is attached; whether a desktop session is present (on Linux, DISPLAY or WAYLAND_DISPLAY set); the flavour of the system tools (GNU or BSD); and the restore side's environment variables, each optional:
- FILEBACKUP_NO_GUI: the value 1 asks for no folder choice;
- FILEBACKUP_PICKER: the path of one program that offers the folder choice (IF-027).""")
I.set('IF-026', 'rationale', """Without these signals a restore either asks a question nobody can answer, hanging a script, or never asks a person who double-clicked it. Keeping the restore side's variables with the backup side's environment lost because the restore kit must depend on nothing backup-only.""")

I.set('IF-027', 'data', """Request: a title text. Answer: one folder path, or cancelled. Providers: the program FILEBACKUP_PICKER names (IF-026), called with the title as its one argument, printing the chosen path on standard output and exiting non-zero on cancel; the Windows folder browser; the macOS folder chooser; and zenity, kdialog or yad on a Linux desktop, each printing the chosen path on standard output and exiting non-zero on cancel.""")

I.set('IF-029', 'data', """A record of contents (IF-014) with DataPath, Compressed and StoredAsHashSize blank, and its completeness evidence (IF-015), named FILEBACKUP-CHANGES.csv and FILEBACKUP-CHANGES.csv.meta, with publication temporaries FILEBACKUP-CHANGES.csv.tmp and FILEBACKUP-CHANGES.csv.meta.tmp, at the SourceStatePath location, by default the source root. Its earlier name, used by versions before this one, was MANIFEST.csv and MANIFEST.csv.meta, the names of a backup's own record.""")
I.set('IF-029', 'version', '3')
I.set('IF-029', 'rationale', """Re-reading every file on every run overruns the backup window; the record of each file's last size, time and digest is what lets a run read only what changed. A private binary cache lost: the owner must be able to open and read what the tool keeps in his source. Keeping the backup record's own name lost: a source whose root holds a copy of a backup's record would have it taken for the run's own state and overwritten.""")

I.set('IF-030', 'data', """FileBackupState.json at the backup root: a UTF-8 JSON object with LastBackupRun (string, ISO-8601 round-trip, the completion time of the latest state) and LastHashRun (string, ISO-8601 round-trip, the time the last completed full re-read began); a later version may add keys. FileBackupState.json.tmp is its publication temporary.""")
I.set('IF-030', 'consumers', ['CMP-009'])

I.set('IF-031', 'data', """For a path: its physical location, and the mount points of the host (on Windows the drive roots, share roots and folder mount points; on Linux and macOS the mount table), each with the identity of the volume mounted there. A volume identity is stable while the volume is mounted: on Windows the volume's GUID path, or the share root for a share; on Linux and macOS the device number. For a volume: its free bytes and its allocation unit in bytes, each or unknown.""")

I.set('IF-032', 'consumers', ['CMP-011', 'CMP-013', 'CMP-014'])

I.set('IF-033', 'data', """Temp at the saved-state root: the staging area of the one changing operation holding the backup.
While a backup holds it, Temp contains RUN.inprogress, the owner record: a UTF-8 JSON object of schema version 1:
- SchemaVersion: integer, 1;
- Kind: string, backup;
- RunId: string, a fresh GUID per acquisition;
- StartedUtc: ISO-8601 time;
- HeartbeatIntervalSeconds: integer, 60;
- StaleAfterSeconds: integer, at least 1800;
- SetName, Host, ContainerId, BootId (strings) and Pid (integer): diagnostic, optional.
SchemaVersion, Kind, RunId, StartedUtc, HeartbeatIntervalSeconds and StaleAfterSeconds are required; a record with another SchemaVersion or Kind, or without a required field, is of an unknown schema. The record's modification time is part of it.
While a removal holds it, Temp contains PRUNE.inprogress, UTF-8 text holding the name of the saved-state folder being removed.
Other entries a backup may place in Temp: the folder of the saved state being prepared, named as it will be published (IF-013), holding the copied prior record of contents, its completeness evidence, the folder record, the link record, the kit and their publication temporaries.""")

I.set('IF-035', 'requestors', ['CMP-010', 'CMP-013', 'CMP-014', 'CMP-018', 'CMP-019'])

I.set('IF-038', 'data', """Action: a leading positional word, or FILEBACKUP_ACTION, one of backup (the default when both are absent), prune, snapshots, verify. Arguments after the action that start with '-' are switches of the backup launch request (IF-002).
Variables: FILEBACKUP_CONFIG_PATH (default /config/FileBackup.json); FILEBACKUP_LOG_PATH (default /logs/Backup_Global.log); FILEBACKUP_SNAPSHOT (saved-state names for prune, comma-separated); FILEBACKUP_REPAIR (with verify, run the repair); FILEBACKUP_DRY_RUN (with prune, the removal dry run); and the environment settings of IF-007.
A flag variable is set when it holds exactly one of 1, true, TRUE, True, yes, YES, Yes, and unset when it is absent, empty or exactly one of 0, false, FALSE, False, no, NO, No.
Exit status: the operation outcome value (IF-003).""")

I.sub('IF-039', 'rationale', "Running as root with one writable mount lost on SR-130's least-access requirement.", 'Running as root with one writable mount lost on the least-access requirement.')

I.set('IF-041', 'data', """At the ViewPath location: INDEX.tsv (UTF-8, tab-separated, a header then one row per path of the latest state, duplicates included: RelativePath, DataPath, Length, xxH2Hash, Compressed); one INDEX.html per folder of the latest state, each entry a relative link to its stored object; a root INDEX.html in one of two forms, a search page embedding every row with a name filter, or a pointer page giving search commands over INDEX.tsv; and .viewstamp holding the SHA-256 of the canonical rows the view mirrors. The search-page row limit is 50000 rows.""")

I.set('IF-042', 'data', """SPACE.tsv at the ViewPath location: UTF-8, tab-separated, a header then one row per file of the latest state, ordered by StoredBytes descending then RelativePath ordinal. Columns: RelativePath; xxH2Hash and Length (the content key); StoredBytes (integer, the size of the stored copy); Shared (yes when the stored copy serves more than one path, else no); MediaMBPerSec (decimal with three places, or blank); MediaMeasure (taken, not-yet-measured, or not-taken: <reason>), taken with a blank rate meaning the tool gave no playing time.""")

I.set('IF-044', 'consumers', ['CMP-011', 'CMP-013'])
I.set('IF-044', 'data', """Request: the staging area as read: whether it exists and whether it is a link; its listing (entry names), or unreadable; its own modification time and age, or unreadable; the owner record (IF-033) as read, one of absent, parsed, unparseable or of an unknown schema (its bytes readable), or unreadable after three reads, with its modification time and age where readable; and optionally a second sample of the owner record's modification time.
Answer: one verdict, with the evidence it rests on:
- Empty: no entry but record publication temporaries, the area's own time stale;
- EmptyFresh: the same, the area's own time fresh;
- OwnerStale: the owner record readable, older than its stale time and unchanged at the second sample;
- OwnerLive: the owner record readable and fresh, future-dated, or not yet confirmed stale;
- PruneHeld: a removal's marker;
- HoldsContent: any other entry;
- Indeterminate: the area is a link, or its listing, its own time or the owner record could not be read.""")

I.set('IF-045', 'rationale', """Both restore routes realise this search, and a restore's outcome depends on which answer it gives; the interface sits inside one component on purpose, as the parity form the two routes must agree on. Leaving the answer set in prose lost because a route that folds a host cause into content-missing reports loss where there is none.""")

# ======================================================================
# LLRs
# ======================================================================

def drop_constrains(rid):
    L.delete(rid, 'constrains')

# --- Operation launch and outcome ---
L.sub('LLR-043', 'detail', '3 when it refused over a damaged record of a state;', '3 when it refused over a damaged record of a state, or a check found one;')
L.set('LLR-043', 'dimensions', 'operation=set{backup,removal,report,check,repair,kit-refresh,view}; part_failed=bool; bad_request=bool; configuration_refused=bool; precondition_not_met=bool; damaged_record=bool; busy=bool; host_fault=bool; unclassified=set{none,before-change,after-change}; legacy_switch=bool; host=set{direct,container}; @pairwise')
L.set('LLR-043', 'rationale', """Without one mapping each operation classifies its own refusals, and a host cannot read the value without knowing which operation it ran; a busy backup and a refused configuration then share a value, and a host either retries a refusal forever or raises an alarm over a store that is only busy. Leaving the mapping to each operation lost; the operations still decide which causes they found, and this row decides the value.""")

L.sub('LLR-016', 'detail', 'and a step that would have needed an answer fails the operation with an outcome naming what was needed.', 'and a step that would have needed an answer ends the operation with the precondition-not-met value (2), naming what was needed.')

L.sub('LLR-048', 'detail', 'An unknown action word or variable value is a bad request (2).', 'An unknown action word, or a flag variable holding a non-empty value in neither its truthy nor its falsy set, is a bad request (2).')
L.set('LLR-048', 'dimensions', 'action=set{none,backup,prune,snapshots,verify,verify-repair,unknown}; source=set{word,variable,both}; flag_value=set{truthy,falsy,empty,other}; passthrough=bool; request=set{valid,unknown-state}; @pairwise')

# --- Configuration ---
L.sub('LLR-042', 'detail', 'and the launch ends with the configuration-refused value (2), creating nothing and changing no location; an existing global record only gains the refusal entry.', 'and the launch ends with the configuration-refused value (2), creating nothing and changing no location and no record: the refusal reaches the console only (LLR-095). The description version is checked as LLR-098 and LLR-099 state.')
L.set('LLR-042', 'dimensions', 'fault=set{none,unknown-key,retired-key,wrong-type,quoted-boolean,list-for-string,missing-required,empty-string,bad-enum,out-of-range}; form=set{json,native-windows}; level=set{top,tools,secrets,location-set}; @pairwise')
L.sub('LLR-018', 'detail', 'nothing is created, the global record included.', 'nothing is created or changed, the global record included, and the message reaches the console only.')
L.sub('LLR-099', 'detail', ' The configuration helper writes the current version into every document it produces.', '')

L.set('LLR-103', 'title', 'A backup or saved-state location may not overlap a source')
L.set('LLR-103', 'sr_refs', ['SR-138'])
L.set('LLR-103', 'detail', """Before the run starts and before anything is written, every configured backup and saved-state location is resolved to its physical place, links included, and compared with every source of every location set. A backup or saved-state location inside, equal to or containing a source, a drive-root source included, is refused with the configuration-refused value (2) and a message naming both locations, and nothing is created or changed in any location. Locations that do not overlap run normally.""")
L.set('LLR-103', 'dimensions', 'location=set{backup,saved-states}; relation=set{inside,equal,containing,separate}; resolution=set{as-written,through-link}; source_root=set{ordinary-folder,drive-root}; @pairwise')
L.set('LLR-103', 'rationale', """A backup inside its own source backs itself up on every run and grows by its own size each night. Comparing the paths as written lost because a link makes a separate-looking location land inside the source; checking once a backup has started lost because the refused location would already have been written.""")
L.add_row('LLR-103', 'design', 'LLR-153', [
    ('title', "A listing location may not overlap a source or the store, shares the backup's volume, and holds only generated views"),
    ('sr_refs', ['SR-063', 'SR-062']),
    ('constrains', 'IF-004'),
    ('detail', """Before the run starts and before anything is written, the listing location is resolved to its physical place, links included, and compared with every source, backup, saved-state and state location of every location set. Refused, with the configuration-refused value (2), a message naming both locations or the setting, and nothing created or changed: a listing location inside, equal to or containing any of them; one not on the backup's volume; one already holding entries the system did not generate, which are left in place."""),
    ('dimensions', 'relation=set{inside,equal,containing,separate}; other=set{source,backup,saved-states,state}; resolution=set{as-written,through-link}; same_volume=bool; foreign_content=bool; @pairwise'),
    ('rationale', """A listing written over a source deletes the owner's files when it is regenerated, and one inside the store is taken for data. It must share the backup's volume because each browse-view entry is a relative link to its stored object, and a relative link cannot cross volumes on Windows; absolute links lost because the view then breaks whenever the backup's drive is mounted under another letter. Checking only when the listing is written lost: by then a backup has already been taken with a refused location."""),
    ('status', 'Drafted')])
L.add_row('LLR-153', 'design', 'LLR-154', [
    ('title', 'A change-detection state location may not lie in a source or the store'),
    ('sr_refs', ['SR-149']),
    ('constrains', 'IF-004'),
    ('detail', """Before the run starts and before anything is written, a configured state location is resolved to its physical place, links included, and refused, with the configuration-refused value (2), a message naming the state-location setting, and nothing created or changed, where it lies inside any source, or equals or lies inside a backup or saved-state location. A location outside every source, backup and saved-state location is accepted."""),
    ('dimensions', 'relation=set{inside-source,equal-backup,inside-backup,equal-saved-states,inside-saved-states,separate}; resolution=set{as-written,through-link}; @pairwise'),
    ('rationale', """A state location inside a source makes the record part of what it records, and one inside the store is taken for stored content and can be deleted by a removal. Accepting either and leaving the record out by name lost because that exclusion would have to follow the location wherever it is configured."""),
    ('status', 'Drafted')])
L.add_row('LLR-154', 'design', 'LLR-155', [
    ('title', "The global record's location is admitted like every other writable location"),
    ('sr_refs', ['SR-093', 'SR-059']),
    ('detail', """Before the global record is opened, its location, whether named in the launch request, given by the environment or taken by default, is resolved to its physical place, links included, and refused where the file would lie inside a source, inside a backup or saved-state location, or at an infrastructure name of the store layout. The refusal is a bad request (2), reaches the console only, and creates, truncates and changes nothing. A location outside every source and store location is opened as the global record."""),
    ('dimensions', 'origin=set{request,environment,default}; place=set{inside-source,inside-backup,inside-saved-states,infrastructure-name,separate}; resolution=set{as-written,through-link}; @pairwise'),
    ('rationale', """A record path pointed at a source file overwrites the owner's file, and one pointed into the store truncates content a state needs. Checking only the configured locations lost because the record's path comes from the request or the environment, where no configuration check reaches."""),
    ('status', 'Drafted')])

# --- Provisioning ---
L.sub('LLR-037', 'detail', 'Reading the effort never raises an error, because the restore-safe library that reads it is loaded by the restore kit; an invalid value is recorded as rejected and the effort stays 9.', 'Reading the effort never raises an error and never affects any restore: an invalid value is recorded as rejected and the effort stays 9.')

# --- Notification ---
L.set('LLR-015', 'detail', """After each backup run, where notification is set up (the catalogue's notification fields, relay, sender and recipient, all present and non-empty) and not switched off for the run, exactly one message stating success or failure is sent, on the configured port or its default; it logs in with the stored login only where the configuration carries one, and otherwise sends without logging in. Where any of the three is missing, or notification is switched off, none is sent, the run's record says notification was skipped and why, and the run proceeds. A send that fails, whether the relay is unreachable or refuses, is recorded as a warning, and the run's value is the one it had without notification.""")
L.set('LLR-015', 'dimensions', 'configured=set{all-three,partial,none}; switched_off=bool; outcome=set{success,failure}; relay=set{ok,unreachable,auth-refused}; login=bool; port=set{default,configured}; @pairwise')

# --- Run record ---
L.set('LLR-095', 'detail', """The global record is created or truncated only once the configuration has been admitted and the record's own location has passed its check (LLR-155); entries produced before that are held and written once it exists. A refused configuration, and a refused record location, create, truncate and append to no record: the refusal reaches the console only, and the host sees 2. A location's record is truncated only once that location holds the backup and has passed its admission checks; a refusal before that point appends one entry to the existing location record, which belongs to the live holder.""")
L.set('LLR-095', 'dimensions', 'configuration=set{valid,refused,missing}; record_location=set{admitted,refused}; prior_record=set{absent,present}; claim=set{held,refused}; @pairwise')
L.set('LLR-095', 'rationale', """Opening a record truncates it, so a record opened before the configuration is admitted destroys the previous run's record, the one the owner needs after a typo, and even an appended refusal changes a log the refused launch had no business touching. Creating the record first and deleting it on refusal lost: the previous content is already gone.""")
L.set('LLR-107', 'detail', """Every entry written to a run record is also written to the console as it is written. When a run ends, each location's record names each file added, changed and removed in its own category, each file or folder that failed or was not captured with its cause, and a summary with the counts of each category. Over an unchanged source the added, changed and removed counts are zero, and the failure count is zero only when nothing failed.""")
L.set('LLR-097', 'detail', """Each refusal of a backup-side operation (a launch, a location, a removal, a check, a repair or a kit refresh) is one entry carrying its token from the closed refusal-token set and naming the condition found (the setting, location, volume, tool, form, holder or leftover concerned, with the figures that decided it) and an action that resolves it. A refused configuration or record location shows that entry on the console only (LLR-095). A restore's refusals, made before its report exists, are shown on the console in the same form (LLR-136).""")
L.set('LLR-097', 'dimensions', 'cause=set{configuration,record-location,bad-request,busy,claim-location,claim-io,record-damage,capacity,tool,unsupported-form,leftovers-content,unfinished-removal,empty-source,location-overlap,read-only-source,removal-refused,staging-busy,host-fault}; @full')

# --- Source capture ---
L.set('LLR-109', 'title', "A folder link is followed when it leads outside, and recorded when it leads back in or into the system's own locations")
L.set('LLR-109', 'detail', """Each folder link or junction met in the walk is resolved to its physical target and given exactly one class, the first of these that applies: into a system location (the backup root, the saved-state root and its saved states, the change-detection state location, the record location or the listing location), recorded and not followed; to a folder that is one of the link's own ancestors in the walk, compared by physical location, whether that ancestor lies in the source or inside a followed outside folder, recorded and not followed; to a folder inside the source, recorded and not followed, its target captured at its real place; otherwise, to a folder outside the source and every system location, followed: what it leads to is captured as part of the source under the link's path, and two links to the same outside folder are each followed, the content behind them stored once. A recorded link is written as LLR-110 states, a file link is captured as LLR-151 states, the waiting is bounded as LLR-152 states, and a link whose target cannot be reached is a folder the run could not capture (LLR-111).""")
L.set('LLR-109', 'dimensions', 'link=set{folder-link,junction}; leads_to=set{outside-source,inside-source,ancestor-in-source,ancestor-in-followed-folder,backup,saved-states,state-location,log-location,listing-location,unreachable}; reached_through=set{source,followed-folder}; repeated=bool; @pairwise')
L.set('LLR-109', 'rationale', """Following every link can loop forever and can back up the backup into itself; following none silently omits whatever the owner keeps behind a link to another drive. Classes that overlap let one link be both followed and recorded, so the first class that applies, in a fixed order, decides. Deciding ancestry by path text lost because a link inside a followed outside folder reaches its ancestor by a path that never repeats.""")

L.set('LLR-110', 'detail', """Each link recorded rather than followed is written to the state's link record with its path under the source root, its kind, its target class, and its target: for a target the walk captures (a folder of the source, or an ancestor of the link, one reached through a followed outside folder included), the path at which the walk captured that folder, under the source root and through followed links; for a target in a system location, the absolute path it resolved to at backup time. A state with no recorded link has no link record. Recording a link does not change the outcome from complete.""")
L.set('LLR-110', 'dimensions', 'target_class=set{inside-source,ancestor-in-source,ancestor-in-followed-folder,own-location}; link=set{folder-link,junction}; @full')
L.set('LLR-110', 'rationale', """A restore can rebuild only what was written down. Storing the raw target text lost because a target written relative to the link cannot be re-pointed under a new restore target, and storing an ancestor's physical path lost because an ancestor reached through a followed link has no path under the source root except the one the walk gave it.""")
drop_constrains('LLR-110')

L.add_row('LLR-110', 'design', 'LLR-151', [
    ('title', 'A file link is captured as the file it leads to'),
    ('parent', 'LLR-109'),
    ('constrains', 'IF-028'),
    ('detail', """A link to a single file, wherever it leads, is captured as an ordinary file at the link's path, with the bytes, size and modification time of the file it leads to; the link itself is not recorded. A file link whose target cannot be read is a file the run could not capture (LLR-111)."""),
    ('dimensions', 'target=set{inside-source,outside-source,system-location,unreadable}; @full'),
    ('rationale', """Recording file links as links would need a second kind of link at restore for nothing the owner asked for, and a file link to another drive would lose its content. Capturing the file costs only a record row, the content being stored once."""),
    ('status', 'Drafted')])
L.add_row('LLR-151', 'design', 'LLR-152', [
    ('title', "Waiting on unreachable link targets shares the location's wait budget"),
    ('parent', 'LLR-109'),
    ('constrains', 'IF-028'),
    ('detail', """Each request that resolves a link, or enumerates what a followed link leads to, waits at most 60 seconds and never longer than what is left of its location's wait budget, the 60 seconds per location it shares with the retries of unreadable files (LLR-067). Once that budget is spent, every further link whose target does not answer at once is named as not captured without waiting, and the record says the limit was reached."""),
    ('dimensions', 'link_count=range[1..1000]; target=set{answers,slow,unreachable}; budget=set{unspent,partly-spent,spent}; retries_in_location=bool; @pairwise'),
    ('rationale', """A bound per request is not a bound per run: many junctions to a share that sleeps at night would each wait a minute and overrun the run's window. A budget for links apart from the retry budget lost because a location with both locked files and dead links would then wait twice the declared limit."""),
    ('status', 'Drafted')])

L.sub('LLR-067', 'detail', 'The total waiting for retries is bounded to 60 seconds for each configured location, shared by every file of that location; once it is spent, further unreadable files are reported failed without waiting and the record says the limit was reached.', 'Each retry is named in the run\'s record. The total waiting for retries, together with the waiting on link targets (LLR-152), is bounded to 60 seconds for each configured location, shared by every file and link of that location; once it is spent, further unreadable files are reported failed without waiting and the record says the limit was reached.')
L.set('LLR-067', 'dimensions', 'failure=set{transient-lock,folder-at-destination,budget-spent}; released=set{before-second-attempt,before-third-attempt,never}; group=set{unique,shared-content}; unreadable_count=range[1..10000]; link_waits=bool; @pairwise')

L.set('LLR-111', 'constrains', 'IF-028')
L.set('LLR-111', 'detail', """A file or folder the run cannot read, or a folder it cannot enumerate, a followed link whose target cannot be reached included, is named in the run's record with its cause, is counted neither as captured nor as removed, and the location reports part failed while every readable file is still captured. Where an earlier run captured it, the latest state keeps the earlier entry and its content, including when another file shared those bytes and has since changed or been removed.""")
L.set('LLR-111', 'dimensions', 'unreadable=set{file,folder,unreachable-link-target,both}; prior_capture=bool; shared=bool; @pairwise')

drop_constrains('LLR-065')
L.sub('LLR-112', 'detail', 'The same holds for every action and every outcome, refusals included.', 'The global record is never written inside a source (LLR-155). The same holds for every action and every outcome, refusals included.')
drop_constrains('LLR-036')

# --- Change detection ---
L.set('LLR-113', 'constrains', 'IF-029')
L.sub('LLR-113', 'detail', "Each walked file is compared with the latest state's entry of the same path:", "Each walked file is compared with its entry in the change-detection record, as reconciled with the latest state's record (LLR-114):")
drop_constrains('LLR-011')
L.sub('LLR-011', 'detail', 'An every-run schedule always re-reads.', 'An every-run schedule, under either of its two letters, always re-reads.')
L.set('LLR-114', 'detail', """The change-detection record is checked against its completeness evidence when read. Where it is missing, unreadable, fails its evidence, or disagrees with the backup's latest record for a path (a different size, time or digest for the same path, as a stale copy or another source's record would), the latest record supplies that path's size, time and digest instead, so a file is unchanged only where it matches what the backup holds and every file edited since is captured. No unchanged file is recorded as removed, a superseded state is kept as for any changing run, the run completes, and its record says the change-detection state was rebuilt and why. Where no record exists under its own name but one exists under its earlier name (IF-029), that file is read once as the change-detection record only where its evidence matches and every one of its rows has a blank stored-copy reference; the new record is then written under its own name, and the earlier file and its evidence are removed. A file at the earlier name that fails either test is owner content, captured like any other file and never overwritten.""")
L.set('LLR-114', 'dimensions', 'state_fault=set{none,missing,truncated,unparseable,evidence-mismatch,stale,foreign}; earlier_name=set{none,own-record,store-record-copy,other-file}; @pairwise')
L.set('LLR-115', 'rationale', """The source root is the one place every owner can find the record, beside the files it describes, and it moves with the source; keeping it only beside the backup lost because an owner looking in his source for what the tool keeps there would find nothing, and two sources backed up to one store would need their records told apart by name. A source the run may only read, such as a container's read-only mount, cannot hold the record, so it needs the configured location.""")
L.sub('LLR-035', 'detail', 'With an empty latest record the run is a first backup.', 'With an empty latest record the run is a first backup. A key of the run-state record that the reader does not know is ignored, so a later version may add keys.')
L.sub('LLR-028', 'detail', 'is written to the run-state record after the state is published and before the cross-state collapse runs,', 'is written to the run-state record after the new latest record and the saved state it keeps are published and their content placed (LLR-150), and before the cross-state collapse runs,')

# --- Content writer ---
drop_constrains('LLR-003')
drop_constrains('LLR-058')
L.delete('LLR-117', 'parent')
L.set('LLR-117', 'sr_refs', ['SR-082', 'SR-059'], after='title')
L.set('LLR-117', 'detail', """A new stored object is written at a fresh temporary name in its folder, of the stored-object temporary form of the store layout (an archive is built there from nothing), its content key is checked from the written bytes (an archive by expanding it), and only then is it published at its content-derived name by rename. A file already at that name that no entry of any state references (left by a killed run, an interrupted archive tool, or an entry evicted while its object awaits removal) is replaced by the publication; an object at that name that some entry still claims is never replaced. A failed check removes the temporary and the file is reported as not stored. A compressed object is written at the effort level resolved from the environment. A temporary left by a killed or fenced run is removed by the next run that holds the backup and has passed admission, recognised by its form and confirmed unreferenced by the folder's record, never by its name alone.""")
L.set('LLR-117', 'dimensions', 'destination=set{absent,unreferenced-valid,truncated-debris,claimed}; form=set{raw,archive}; check=set{passes,fails}; effort=range[0..9]; leftover_temporary=set{none,unreferenced,named-by-an-entry}; @pairwise')
drop_constrains('LLR-053')
drop_constrains('LLR-086')
L.set('LLR-086', 'dimensions', 'compress=bool; measuring=set{off,excluded-extensions,always}; name_class=set{listed-already-compressed,unlisted,none}; size=set{empty,below-floor,at-floor,above-floor}; saving=set{below-threshold,at-threshold,above-threshold}; measurement=set{taken,unavailable}; @pairwise')
L.sub('LLR-116', 'detail', 'Each window is compressed by Brotli at its fastest quality level into a counting sink whose count is read only after the encoder is closed.', "Each window is compressed by a fast general-purpose compressor, and the window's compressed size is the compressor's fully flushed output size, taken only once it has finished.")
L.sub('LLR-116', 'rationale', 'A count read before the encoder closes reads short and calls random bytes compressible.', 'A size read before the compressor has flushed reads short and calls random bytes compressible.')
L.set('LLR-052', 'detail', """Before any location's root, claim, record, staging area or log is created, a plan that changes nothing sums the demand on each volume over every configured location on it, reading only published records, as a reader does, and taking no claim (LLR-123): new content not already held, at its uncompressed length rounded up to the volume's allocation unit (64 KiB where the unit cannot be observed); content stored again to heal a loss, the same way; earlier content that must be copied rather than moved because the saved-state location is on another volume, at its stored size; and a declared allowance: the records and their evidence written (old and new), the restore kits at their actual size, 4096 bytes per folder and per record entry, and 16 MiB per location plus the largest temporary objects the run holds at once. Where a volume's demand exceeds its free space, every location with demand on it is refused as a precondition not met (2), naming the volume, the space needed and the space free, with nothing created or changed on that volume; a refusal changes nothing, so this plan may make it. Other locations proceed, and demand equal to free space passes. A volume whose free space cannot be measured is not refused; the location's record says the space check was not made. Once the claim is held, the plan is made again against the store as it then is, before any content is written; that plan binds, and a shortfall refuses the same way.""")
L.set('LLR-135', 'detail', """A path's volume is the one mounted at the longest mount point that prefixes the path's physical location on a separator boundary: on Windows the drive roots, share roots and folder mount points; on Linux and macOS the mount table. The volume is known by its stable identity (IF-031), so two paths that reach one volume, through a drive letter and a folder mount for example, count as one volume, and a folder-mounted volume is never counted as the drive it sits on. Its free space and its allocation unit are measured for drive-qualified, share and rooted POSIX paths alike, and each is reported as unknown, never as an error, when it cannot be measured. The same measurement serves the backup's and the restore's space checks.""")
L.set('LLR-135', 'dimensions', 'path=set{drive-qualified,share,rooted-posix,nested-mount,windows-folder-mount,unmeasurable}; alias=bool; host=set{windows,linux,macos}; @pairwise')
L.set('LLR-135', 'rationale', """A measurement that only understands drive letters makes the check silently inert on Linux and in a container, and measures a folder-mounted disk as the drive it sits on. Using the path itself as the volume lost because two folders on one volume then compete unseen, and using the mount path text as the identity lost because one volume reached by two paths would be counted twice.""")

# --- State publication ---
drop_constrains('LLR-005')
L.set('LLR-005', 'detail', """When the change set is not empty (an addition served by deduplication, a removal of shared content, a time-only change, a heal, and a difference in the folder record or the link record all count), the previous latest state's record, its evidence, folder and link records and kit are prepared and published as a saved state, dated as its child row requires, and its superseded and removed content then moves into it in the order LLR-150 gives. A saved state becomes visible only after its own record, its evidence and its kit are complete. When the change set is empty and no stored content needs storing again, no saved state is created; the latest state is never itself a saved state.""")
drop_constrains('LLR-051')
drop_constrains('LLR-059')
drop_constrains('LLR-150')
L.set('LLR-150', 'title', 'Content a visible state needs is never only in staging')
L.set('LLR-150', 'detail', """A backup that keeps a saved state publishes in this order: it prepares the saved state (its record, evidence, folder and link records and kit) in its own folder inside the staging area, while every stored object that state needs is still in the backup root; it publishes the saved state by moving that folder to its saved-state name; it publishes the new latest record; and only then moves each stored object that no entry of the new latest record claims from the backup root into the saved state, by rename on one volume, or across volumes by a verified copy published at the destination before the root's copy is deleted. A restore searches the backup root and every published saved state, so at every point each published state, an older one whose blank entries borrow that content by content key included, finds every object it needs, and the staging area is never the only place holding content a visible state needs. A kill after the saved state is published and before the new latest record is published leaves a saved state equal to the latest state, under the name the next run would give it; the next changing run finds that folder, whose record matches the latest record's evidence, and keeps it as its saved state rather than adding another.""")
L.set('LLR-150', 'dimensions', 'kill_point=set{before-saved-state-publication,after-saved-state-publication,after-latest-publication,during-content-move,after-content-move}; content=set{removed,superseded,unchanged}; borrower=bool; volumes=set{same,different}; @pairwise')
L.set('LLR-150', 'rationale', """A restore searches the backup root and the published saved states, never the staging area, so content moved into staging, or into a saved state not yet published, is unreachable from every visible state that needs it if the run dies there, an older state that borrows it by content key included. Copying the content instead of moving it lost on space at the declared scale; letting restores search the staging area lost because the staging area of a live run is not a published state and may be reclaimed.""")
drop_constrains('LLR-041')
L.set('LLR-041', 'detail', """Each failure to move a removed or superseded file's earlier content from the backup root into the published saved state is caught per file, recorded naming the file and the cause, counted, and the loop continues; the content is left in the backup root, where every state still finds it by content key, and the run reports part failed. Where the saved state cannot be published at all, the new latest record is not published, the latest state is left as before the run, and the location fails, reporting part failed."""
)
L.set('LLR-041', 'dimensions', 'kind=set{superseded,removed}; failures=range[1..2]; failing_step=set{content-move,saved-state-publication}; @pairwise')
L.set('LLR-041', 'rationale', """Aborting on the first failed move leaves content half placed for no gain, since the content is safe where it is; silently continuing lost because the owner must know which files' history is at risk. Publishing the new latest record without the saved state that keeps the old one lost: the previous state would vanish.""")
drop_constrains('LLR-007')
L.sub('LLR-076', 'detail', 'Both restore routes carry the same kit revision.', "Every kit file carries the same kit revision: both restorers, the shared library, both launchers, the location sidecar and the notices file, and the hashing library's version is the one that revision fixes.")
drop_constrains('LLR-026')
L.set('LLR-026', 'detail', """After the run state is written, content stored in more than one folder of the backup is kept once: in the backup root where the latest state references it, otherwise in the newest saved state that references it. The collapse rewrites the record of each folder whose entries reference a redundant copy, blanking those references so the content is found by content key, and of each folder whose references name a vanished copy, each distinct reference being probed once; it rewrites no other folder, and reads records only through the content-location index (LLR-062). The kept copy is confirmed present, each rewritten record is published, and every state whose entries were blanked is confirmed to resolve each of them, before the redundant copy is deleted. Every rewrite and delete is fenced (LLR-125).""")
L.set('LLR-026', 'dimensions', 'sharing=set{root-and-saved,between-saved,none}; vanished=bool; kill_point=set{before-rewrite,after-rewrite,after-delete}; @pairwise')
L.set('LLR-026', 'rationale', """Without the collapse the same bytes superseded in several runs are stored once per run. Deleting a redundant copy before every record referencing it is rewritten leaves an entry naming a vanished file; rewriting every folder each run lost on the run-time budget, which the history must not dominate.""")

# --- Exclusive-use guard ---
L.set('LLR-122', 'constrains', 'IF-032')
L.set('LLR-091', 'detail', """A backup takes the claim after resolving its locations and before it reads any store state on which a decision that changes the store depends (the run-state record, the latest record and its evidence), and so before it classifies or creates the staging area; the space plan made before the claim reads only published records and changes nothing (LLR-052), and its one possible decision, a refusal, changes nothing either. The backup holds the claim until the saved state is published, the run state written, the cross-state collapse and the views done, and releases it in a final step that runs on every path, after any liveness refresh has stopped. A refusal on the claim appends one entry to the location's record.""")
L.set('LLR-091', 'rationale', """Store state read before the claim may be state another run has not finished writing; a run that acts on it can take a half-written run-state record for none and itself for a first backup. Taking the claim only around the publication lost for that reason.""")
L.set('LLR-123', 'detail', """A check without repair or refresh, the saved-state report and a restore take no claim, leave no artifact in the store and read only published records and folders, never the staging area. Where a stored object or a saved-state folder a reader has located vanishes before the reader has read it (a concurrent repair renamed it, the cross-state collapse removed a redundant copy, a removal deleted the folder), the reader locates the content again by content key over the pool as it then is. Where a record's evidence changes while the reader reads that record, the reader reads the record and its evidence again, up to three times, before it reports the record as damaged. Each therefore completes with the outcome it would have against a quiet store, for every state the concurrent operation does not remove, while a backup, a removal, a repair or a kit refresh holds the backup. A check or the report that meets a saved state a concurrent removal deletes while it reads leaves that state out, as no longer present, and reports on the rest. A restore of the very state a concurrent removal deletes completes where it read that state's record and every content it needs before they went; otherwise it ends with retry later (4), naming the concurrent removal, every file it has already written being byte-exact, and it never writes a file whose content it could not verify.""")
L.set('LLR-123', 'dimensions', 'reader=set{check,report,restore}; writer=set{backup,removal,repair,kit-refresh}; event=set{none,object-renamed,copy-collapsed,folder-removed,record-rewritten,state-being-read-removed}; last_copy_in_removed_state=bool; rereads=range[0..3]; @pairwise')
L.set('LLR-017', 'detail', """A run that finds the staging area present never overwrites it. It lists the staging area forced, literally and fail-closed (hidden, system and dot-named entries are content; an enumeration, read or access failure is never evidence of emptiness), reads the staging area's own modification time, reads the owner record up to three times about 300 ms apart, and records each finding independently: content (any entry other than the owner record and the record publication temporaries, LLR-088); an unfinished removal (a removal's marker); a staging area that is a link; evidence that cannot be read (the listing, the area's own time, or an owner record still unreadable after the three reads); a live or unproven earlier run (an owner record that can be read, a torn one or one of an unknown schema included, whose run is not proven dead, or an ownerless empty area that is still fresh); and reclaimable leftovers (an empty area, or one holding only an owner record, proven dead as LLR-080 judges). Refused, with nothing moved or deleted and no saved state published, by the precedence of the shared vocabulary: precondition not met (2) where content, an unfinished removal, a link or evidence that cannot be read is found, whatever else is; damaged record (3) where a state's record fails its evidence and is not an interrupted publication, and nothing of class 2 is found, a live or unproven earlier run included; busy (4) where the only finding is a live or unproven earlier run. An unfinished removal's message names the remedy, re-running that removal. Reclaimable leftovers holding no content do not by themselves refuse.""")
L.set('LLR-017', 'dimensions', 'owner=set{none,fresh,stale-confirmed,stale-unconfirmed,torn,unknown-schema,future-dated,unreadable}; staging_age=set{fresh,stale}; content=bool; temporary_only=bool; removal_marker=bool; linked=bool; listing_readable=bool; record_damage=bool; @pairwise')
L.set('LLR-080', 'detail', """Right after creating the staging area a backup writes its owner record once, by an exclusive create that both creates the file and proves it was not already there; finding one already there means another holder, and the run refuses as busy (4), touching nothing. A refresh on its own timer, independent of the work, touches the record's modification time every 60 seconds for the claim's whole life, re-reading the record first and touching it through the same open handle only when the run identity is its own; the first touch happens before the timer starts and its landing is verified. Where the record cannot be created, or the first touch does not land, the run refuses touching nothing more, busy (4) for an I/O fault and a precondition not met (2) for access denied, and clears its own staging area as LLR-124 states. Stopping the refresh is idempotent, never raises, waits out a touch in flight, and reports any failed touches. An earlier run is judged dead only when its record's modification time is older than the stale time the record states, never less than 1800 seconds, and a second sample, taken after the record's refresh interval capped at 600 seconds plus 30 seconds, and never less than 90 seconds, shows it unchanged; a future-dated time is fresh; a torn record, or one of an unknown schema, falls back to its modification time with the 1800-second floor. An owner record still unreadable after three reads about 300 ms apart is evidence that cannot be read: it is judged neither dead nor live, and the leftovers are refused as LLR-017 states.""")
L.set('LLR-080', 'dimensions', 'record=set{parsed,torn,unknown-schema,unreadable,short-stale-time}; age=set{fresh,stale,future}; second_sample=set{unchanged,changed}; declared_interval=range[1..3600]; refresh=set{running,stalled,first-touch-fails}; create=set{created,already-present,io-fault,access-denied}; host=set{same,other-container}; @pairwise')
L.set('LLR-124', 'detail', """Only leftovers classified reclaimable, and confirmed by the second sample, are reclaimed, in this order: move the staging area aside to a reclaimed-leftover name; check the moved folder against the identity the sample classified and, on any mismatch, move it straight back; create a fresh staging area and immediately write this run's owner record; then list the moved folder again, forced and fail-closed, and delete the exact owner record by name and the folder non-recursively. A failed move aside, or a failed create of the fresh staging area or owner record, refuses without retrying in a loop and leaves any moved folder in place: busy (4) where the cause is an I/O fault, a precondition not met (2) where access is denied. A mismatch after the move means another run reached the leftovers first: the folder is moved back and the run refuses as busy (4). Where the final listing finds another entry or cannot be made, or either delete fails, the moved folder, which belongs to no state, is kept and named in the run's record with the recovery guidance, and the run completes (0). Nothing in this path deletes recursively. A run's own cleanup on an early failure first proves the staging area is still its own (its owner record carries its identity, and nothing is inside beyond its own disposable entries), deletes those by exact name with the owner record last, and otherwise keeps the folder.""")
L.set('LLR-124', 'dimensions', 'verdict=set{empty-stale,owner-stale}; race=set{none,owner-resumes-before-move,owner-writes-after-move,two-reclaimers}; failure=set{none,move-aside,identity-mismatch,create-staging,create-owner-record,final-listing,final-delete}; cause=set{io-fault,access-denied}; @pairwise')
L.set('LLR-125', 'detail', """From the moment the claim is taken until the staging area is removed, every change the run makes to the store is preceded by one read of its owner record comparing the run identity: writing a new stored object or any temporary; publishing, moving, deleting or replacing a stored object, a folder or a record; publishing a saved state or the run state; and every record rewrite and delete of the cross-state collapse. The owner record stays in the staging area until the run-state write, the collapse and the views have ended: the saved state is prepared in its own folder inside the staging area and published by moving that folder out (LLR-150), so the owner record never enters a saved state. A mismatch, or a record that stays unreadable after three reads about 300 ms apart, means the claim was lost: the run stops at once, cleans up nothing, ends the location with part failed (1), and its record says its work was reclaimed. A run can lose its claim between one check and the write it guards, so a resumed former owner writes at most one unpublished temporary after its successor took over; that temporary changes no file the successor wrote or published, and the next run removes it (LLR-117). The run's last steps stop its refresh, delete its owner record and then the empty staging area.""")
L.set('LLR-125', 'dimensions', 'step=set{temporary-write,object-publication,object-move,object-delete,object-replace,record-publication,saved-state-publication,run-state-publication,collapse-record-rewrite,collapse-delete}; record=set{same,different,unreadable-transient,unreadable-persistent}; lost_between_check_and_write=bool; @pairwise')
L.set('LLR-125', 'rationale', """A plain filesystem gives no true lease; a run frozen past the stale time and resumed would otherwise overwrite or delete what its successor published, or publish objects no record references. Checking only before destructive steps lost because a resumed run could still write new objects and temporaries; one read of a small record per object written costs little next to writing the object. Deleting the owner record when the saved state is published lost because the steps after it, the run-state write and the collapse, would then have no evidence to check against.""")

# --- Removal and saved-state report ---
L.sub('LLR-045', 'detail', 'A name that would be an infrastructure name at the destination, or would overwrite a different file there, is a bad request;', 'A name that would be an infrastructure name at the destination, or would overwrite a different file there, is a precondition not met (2), naming the colliding file;')
drop_constrains('LLR-046')
L.sub('LLR-046', 'detail', 'the run-state record is damaged; a staging area is present;', "the run-state record is damaged; a staging area holds anything other than this request's own removal marker (LLR-127);")
L.set('LLR-046', 'dimensions', 'cause=set{none,not-a-saved-state,run-state-damaged,staging-present,staging-own-marker,content-already-missing,unreferenced-content,no-space,compression-tool-missing,record-evidence-fails,record-evidence-absent}; compress=bool; @pairwise')
drop_constrains('LLR-126')
drop_constrains('LLR-127')
drop_constrains('LLR-047')
drop_constrains('LLR-128')
L.set('LLR-149', 'title', 'A run reads what changed, not the history')
L.set('LLR-149', 'detail', """Unchanged-looking files are decided from size and time without reading their content unless a re-read is due; changed content is read once to take its digest and once to store it; each saved state's record is read at most once per run, through the content-location index; a check reads each distinct stored object once and a full restore streams each file once. The rows that own each part are LLR-113 and LLR-011 (which files are read), LLR-062 (the index and how records are kept), LLR-026 (which records the collapse rewrites), LLR-049 (the check's reads) and LLR-002 (streaming); memory and concurrency are LLR-160's, and progress is LLR-108's.""")
L.set('LLR-149', 'rationale', """A run that rereads every file or every saved state's content each night grows with the history and overruns its window; stating the pass counts once, with the rows that own each, lets a measurement at the declared scale be checked against one statement. Letting each row state its own share of the budget lost because no row would then say what the whole run reads.""")
L.add_row('LLR-149', 'design', 'LLR-160', [
    ('title', "A run's memory and tool concurrency stay within the declared bound"),
    ('parent', 'LLR-149'),
    ('detail', """The content-location index and the run's counters stay within 1 GiB of resident memory, and at most one archive job runs at a time, so a run, a check or a full restore and the tools it runs together stay within 4 GiB."""),
    ('rationale', """Caching more in memory lost on the total memory bound, which the reference host must meet with the tools it runs. Running archive jobs in parallel lost for the same reason, each job holding its own buffers. Spilling the index to temporary files above its bound lost until a measurement at the declared scale shows the bound is reached."""),
    ('status', 'Drafted')])

# --- Check, repair and kit refresh ---
drop_constrains('LLR-049')
L.set('LLR-049', 'detail', """A check walks the latest state and then every saved state in name order through the content-location index, and reports one finding per disagreement, naming the folder, the entry's path and stored-copy reference, the kind of problem (its class, IF-010), the form observed and expected, and whether it is repairable: a recorded form the stored bytes do not have; a stored name claiming a form its bytes do not have; a reference to a copy that is absent; content no record refers to; a blank entry whose located copy disagrees in form where that state's own kit cannot decide form from the bytes; content altered from its record; and a state's record that fails its completeness evidence after the re-reads a reader makes (LLR-123), reported once for that state, with no finding from its entries, the check continuing with the other states. Every distinct stored object is read and its digest compared once, so an altered copy, a same-length one included, is always found; the form test reads the opening bytes first and an archive is expanded only where its own bytes are not the entry's content. Infrastructure names count only at each folder's root. The check reports damaged record (3) where any state's record fails its evidence, part failed (1) where there is any other finding, and complete (0) on a clean store; a missing backup root or a needed tool absent is a precondition not met (2), which takes precedence over 3, as 3 does over 1.""")
L.set('LLR-049', 'dimensions', 'damage=set{none,deleted-everywhere,deleted-here-present-elsewhere,altered,same-length-altered,wrong-form,name-lies,unreferenced,record-evidence-fails}; location=set{latest,saved-state}; scope=set{whole,latest-only}; precondition_not_met=bool; @pairwise')
drop_constrains('LLR-129')
drop_constrains('LLR-130')
L.set('LLR-130', 'detail', """A repair renames or copies back one stored item at a time, each by publish-on-rename, and rewrites each touched record through the one writer, so at every point each entry's reference names an item that exists in its recorded form or one the restore finds by content key, and each record is whole. A kit refresh records a state's original kit revision first (LLR-131), then replaces the two restorers, then every other kit file, each whole, through a temporary name and a rename. A kill between two kit files leaves that state's kit with files of two revisions and a restorer of the new one, which refuses it as damaged record (3) naming a re-run of the kit refresh (LLR-159); re-running the refresh completes the kit. Re-running the interrupted operation, or the next run once it holds the backup and has passed admission, leaves every state restorable where it positively identifies the interruption from what is on disk, and otherwise refuses as leftovers require with nothing changed.""")
L.set('LLR-130', 'dimensions', 'operation=set{repair,kit-refresh}; point=set{before-item,after-item,after-record,after-evidence,between-restorers,between-kit-files}; @pairwise')
L.set('LLR-130', 'rationale', """A repair killed between renaming an item and rewriting its record leaves an entry naming a vanished file; ordering the steps so the old name stays resolvable until the record changes lost nothing, and a backup-and-restore of the whole folder lost on space. Replacing the restorers last lost: an old restorer cannot know that the files beside it are newer, while a new one can see that they are older.""")
drop_constrains('LLR-131')

# --- Views ---
L.sub('LLR-061', 'detail', 'and a root page searchable by name.', "and a root page that, for a latest state of at most the search-page row limit (IF-041), searches every row by name, and above it gives the search commands over the index.")
L.set('LLR-133', 'detail', """With the space view on and the media-measurement tool available, every file of the latest state is to carry a measure. A file whose content key the previous space view lists as measured keeps that measure, a rate or none, without being measured again. Every other file is given to the tool: files whose content is read in the run first, then unchanged files in path order, the measuring of unchanged files stopping once it has taken 300 seconds in the run; the files left over are listed as not yet measured and are measured on later runs. Where the tool reports a positive playing time, the file's encoding rate, its size in mebibytes divided by the playing time in seconds, to three decimal places, is shown in the space view; a file with no playing time, still images and malformed media included, carries none. The space view is where the measures are kept, so measuring never changes a record of contents.""")
L.set('LLR-133', 'dimensions', 'file=set{video,audio,still-image,malformed-media,non-media}; file_state=set{read-this-run,unchanged-unmeasured,unchanged-measured}; previous_view=set{absent,present,other-content-key}; budget=set{unspent,spent}; @pairwise')
L.set('LLR-133', 'rationale', """Media that could be re-encoded at a lower rate is where large savings hide, and only a playing time reveals the rate; estimating from file type lost because one type spans every rate. Measuring only what a run reads lost: an owner who turns the view on for an existing library would see no rates. Measuring every unchanged file in one run lost on the run's time budget, and keeping the rates in the record of contents lost because a rate written for an unchanged file would change the record and add a saved state for nothing.""")

# --- Store format ---
L.sub('LLR-022', 'detail', 'The infrastructure names cover every artifact the kit places, the records, their evidence and their publication temporaries, the run-state record and the retired launcher name. At a source root only the change-detection record and its publication temporaries are left out; a file there sharing a name with a backup-only artifact is owner content.',
      "The infrastructure names cover the kit's closed name set (IF-019), the retired launcher name included, the records, their evidence and their publication temporaries, stored-object temporaries that no entry names, and the run-state record. Of the infrastructure names, only the change-detection record and its publication temporaries are left out at a source root; a file there sharing a name with a backup-only artifact is owner content.")
L.sub('LLR-025', 'detail', 'the modification-time text carried opaquely and never reparsed or reformatted,', 'the modification-time text carried as written on the backup side, never reparsed or reformatted there, and interpreted by a restore to apply the time (LLR-066),')
L.set('LLR-068', 'dimensions', 'signature=bool; length_vs_entry=set{equal,different}; hash_matches=bool; readable=bool; recorded_form=set{Yes,No}; @pairwise')

# --- Restore admission ---
drop_constrains('LLR-136')
L.set('LLR-136', 'detail', """A restore makes, in this order and before creating the target, its report or any file: the request (switches and their values); the target (inside the backup, unresolvable, a parent-folder component); the kit, every file of one revision (LLR-159); the record's integrity and form (evidence, header, retired forms); the tools its route needs, the need for the archive tool decided from the stored items' own opening bytes, not from the recorded form alone; and the target's space. Only when every one has passed does it continue entry by entry. Where several whole-restore faults are present the value is the one the shared precedence gives; with only per-entry faults every other file restores and the per-entry outcome is reported. A refusal at this stage is shown on the console, naming what was found and what to do, since no report exists yet.""")
L.set('LLR-136', 'dimensions', 'whole_fault=set{none,target-in-backup,unresolvable-target,mixed-kit,record-evidence-mismatch,retired-form,missing-tool,no-space}; entry_fault=set{none,escaping-entry,missing-content,name-collision}; route=set{language-runtime,shell}; @pairwise')
drop_constrains('LLR-039')
L.set('LLR-138', 'detail', """A state counts as recorded before a kind of record existed only on positive evidence, read from its kit revision (the original revision a kit refresh recorded for it or, where none is recorded, the revision its own kit carries) and from its completeness evidence. Completeness evidence: a kit revision below the revision that first wrote evidence. The folder record: a kit revision below the revision that first wrote folder records. The link record: evidence of a version that states no row counts, since no release before the one that introduced the counts wrote link records. Where the evidence states a count of zero the state has no such record by design; where it states more, the record must be present with that many rows. A state whose evidence states no row counts but whose kit revision is at or above the folder record's first revision wrote its folder record only when it had rows, so its absence cannot be told from a tree with no such folder: such a state restores its files, its report names the folder record as unverified, and the restore ends complete where nothing else failed, while a folder record present in it that is malformed is damage (LLR-143). An older state restores as before and its report says each check it could not make, ending complete where nothing else failed. Absence alone is never evidence of age: a state missing what its kit revision or its evidence says it carries is damage.""")
L.set('LLR-138', 'dimensions', 'missing_kind=set{completeness-evidence,folder-record,link-record}; kit_age=set{below-introduction,at-or-above}; evidence_version=set{2,3}; stated_rows=set{none,zero,more}; refreshed=bool; route=set{language-runtime,shell}; @pairwise')
L.set('LLR-138', 'rationale', """Taking every missing record as a sign of age lets damage pass as history, and deleting the evidence then switches the check off; refusing every older state lost because states written by supported versions must still restore. Reading folder-record age from the evidence version lost: the version that added row counts came after folder records, so evidence without counts does not show that a state predates them. Reading age from the kit a state carries now lost once a refresh replaces that kit; a separate format descriptor per state lost because no state written so far carries one.""")
L.add_row('LLR-138', 'design', 'LLR-159', [
    ('title', 'A restore refuses a kit whose files are of two revisions'),
    ('parent', 'LLR-130'),
    ('constrains', 'IF-019'),
    ('detail', """As one of its whole-restore checks (LLR-136), a restore reads the kit revision of every artifact of the kit's name set in the state's folder, a file of a kit older than the one whose files all carry it counting as older, and on the language-runtime route the version of the hashing library it loads. Where any differs from the restorer's own revision, the restore is refused before anything is written with the damaged-record value (3), naming the files that differ and the remedy, re-running the kit refresh, which completes the kit. A kit whose files all agree proceeds. The retired launcher name, kept by a refresh, is not part of the check."""),
    ('dimensions', 'kit=set{one-revision,new-restorers-old-files,one-restorer-new,old-library,refreshed-with-retired-launcher}; route=set{language-runtime,shell}; @pairwise'),
    ('rationale', """A kit refresh killed between two files leaves a restorer beside files of another revision, which can run against a library it was not written for and restore wrongly or fail with an arbitrary error. Making the whole kit one atomic replacement lost: a state's folder holds the kit beside its content, and there is no single rename that swaps a set of files."""),
    ('status', 'Drafted')])

# --- Entry restoration ---
L.set('LLR-010', 'detail', """The state restored is the one whose folder the restore is started from, or the one the request names (LLR-158): a saved-state folder restores that state, the backup root the latest state. That state's record is the only list of what to restore, with nothing from a newer record mixed in. Content is found by content key over the whole pool: the backup root and every saved-state folder, hidden ones included. Under the target the restore writes only the chosen state's recorded entries and its report, the report at a name no recorded entry takes (IF-022).""")
L.add_row('LLR-010', 'design', 'LLR-158', [
    ('title', 'A named state and named roots are used only as far as the request needs them'),
    ('parent', 'LLR-010'),
    ('constrains', 'IF-020'),
    ('detail', """A state named in the request (the shell route's origin switch) is restored in place of the folder the restore was started from; it must be a backup root or a saved-state folder of the layout, or the request is a bad request (2). The pool's roots are the recorded roots of the location sidecar while the restore's own folder physically lies inside one of them. A root named in the request (the backup-root and saved-state-root overrides of either route) is used only where the recorded roots are unusable: the sidecar is absent or unreadable, or the restore's own folder lies inside neither recorded root; otherwise it is ignored with a warning. A named root used and found not to exist is a precondition not met (2)."""),
    ('dimensions', 'origin=set{own-folder,named-backup-root,named-saved-state,named-other}; recorded_roots=set{usable,sidecar-absent,sidecar-unreadable,own-folder-outside}; override=set{none,backup-root,saved-state-root,both}; override_exists=bool; route=set{language-runtime,shell}; @pairwise'),
    ('rationale', """A backup moved to another drive must still find its pool, and a stale sidecar must not send a restore to another backup's pool. Letting a named root always win lost because a mistyped root would then mix another backup's content into the restore, while the recorded roots are the ones the state was written with."""),
    ('status', 'Drafted')])
L.set('LLR-141', 'detail', """Before writing an entry, its destination under the target is resolved physically. A file entry whose path climbs out, is absolute or drive-qualified, or reaches outside the target through a link; a recorded link whose own place would land outside the target; and a link whose target the walk captured, whose re-pointed target would land outside the target: each is left unwritten, named with the cause, counted as not restored, and the restore reports the damaged-record value (3) after restoring every other entry. A link into the system's own locations, recreated pointing to its original path (LLR-144), is checked at its own place only; that its target lies outside the target is not a refusal. A folder-record row that would land outside is not applied and is reported the same way. Containment is checked again immediately before each write, and no file is written through a link met under the target since admission.""")
L.set('LLR-141', 'dimensions', 'path_form=set{parent-climb,absolute,drive-qualified,via-link}; entry=set{file,link-place,captured-link-target,own-location-link,folder-row}; target_exists=bool; route=set{language-runtime,shell}; @pairwise')
L.sub('LLR-142', 'detail', 'On a target that keeps both distinct, both restore.', "On a target that keeps both distinct, both restore. The restore's report takes part in the comparison: it takes a name that no recorded path takes under the target's comparison (IF-022).")
L.set('LLR-142', 'dimensions', 'collision=set{none,case,unicode-normalisation,report-name}; target_case_sensitive=bool; target_normalises=bool; @pairwise')
L.sub('LLR-029', 'detail', 'The restore never skips an entry silently:', 'The report is written fresh by each restore, at its name (IF-022), every entry also shown on the console. The restore never skips an entry silently:')

# --- Tree finishing ---
L.sub('LLR-066', 'detail', "The recorded offset is honoured whatever the restoring host's time zone.", "The recorded time text is interpreted by its grammar (IF-014), its offset honoured whatever the restoring host's time zone.")
drop_constrains('LLR-143')
L.sub('LLR-143', 'detail', 'Where the state\'s evidence says it has a folder record and that record is missing or malformed,', "Where the state's evidence or its kit revision says it has a folder record (LLR-138) and that record is missing, malformed or holds fewer rows than the evidence states,")
L.set('LLR-143', 'dimensions', 'folder=set{empty,nested-empty,hidden,system,read-only}; record=set{present,absent-current,absent-older,absent-unverifiable,malformed,short}; restore_system=set{windows,linux,macos}; @pairwise')
drop_constrains('LLR-144')
L.set('LLR-144', 'sr_refs', ['SR-152', 'SR-146'])
L.set('LLR-144', 'detail', """After every file is written, each recorded link is recreated at its path under the target: one whose target the walk captured (inside the source, or an ancestor reached through a followed outside folder) leads to the matching path under the target, its recorded target path re-pointed there, and opens the restored content there; one that led into a system location leads to its original path. No file is written through any link. Where the target cannot hold a link of that kind, or the restore lacks the right to create one, the link is named as not recreated and the outcome stays complete. Where the state's evidence says it has a link record and that record is missing, malformed or holds fewer rows than the evidence states, every file is still restored, the links not rebuilt are named (all of them, by count, where the record cannot be read), and the restore ends part failed (1).""")
L.set('LLR-144', 'dimensions', 'link=set{inside-source,junction-inside-source,ancestor-in-followed-folder,own-location}; target_os=set{windows,linux,macos}; can_create_links=bool; link_record=set{present,missing,malformed,short}; @pairwise')

# --- Restore outcome ---
L.set('LLR-040', 'detail', """Each route classifies: content that cannot be produced although the host's tools work, and two names colliding, as content missing (1); an entry escaping the target as damaged record (3); a current-form state's folder record or link record missing, malformed or short of its stated rows, or a file's time missing or malformed, as some part failed (1); a bad request or a precondition not met (a tool absent, below version or failing its self-test at admission, a target lacking space) as 2; a damaged record, a kit whose files are of two revisions included, as 3; an I/O failure or a tool failing mid-restore, and the state being restored removed by a concurrent removal before its content was read, as retry later (4); and a state recorded before a check existed, restored with the check reported not made, as complete (0). When several apply, 2 over 3, 3 over 4, 4 over 1. An error the route did not classify ends with 2 when it arose before anything was written and with 4 after. A switch given without its value is a bad request (2). The same induced failure gives the same value through every route on Windows, Linux and macOS.""")
L.set('LLR-040', 'dimensions', 'content_missing=bool; part_failed=bool; bad_request=bool; precondition_not_met=bool; damaged_record=bool; host_fault=bool; unclassified=set{none,before-write,after-write}; route=set{language-runtime,shell}; restore_system=set{windows,linux,macos}; @pairwise')

# --- Restore launch and target choice ---
L.sub('LLR-073', 'detail', 'a folder choice on a desktop.', 'a folder choice on a desktop, as the switches and the variable of LLR-157 allow and from the provider LLR-156 picks.')
L.add_row('LLR-073', 'design', 'LLR-156', [
    ('title', 'The folder choice is asked of one provider, and only an absolute folder is an answer'),
    ('parent', 'LLR-073'),
    ('constrains', 'IF-027'),
    ('detail', """Where the restore offers a folder choice, the provider is, in this order: the program the picker variable names, on every system; otherwise the Windows folder browser on Windows, the macOS folder chooser on macOS, and on a Linux desktop the first present of zenity, kdialog and yad; with none of these there is no folder choice. The answer is taken only when it is one absolute path of an existing folder, a trailing separator dropped; a cancel, a non-zero exit, a failure to start, an empty answer, a relative path or a path that is not a folder gives no target, with the usage and 2 as LLR-073 states. Both routes use the same order."""),
    ('dimensions', 'provider=set{picker-variable,windows-browser,macos-chooser,linux-first-dialog,linux-second-dialog,linux-third-dialog,none}; answer=set{chosen,cancelled,failed,empty,relative,not-a-folder}; restore_system=set{windows,linux,macos}; route=set{language-runtime,shell}; @pairwise'),
    ('rationale', """Two routes that try providers in different orders open different dialogs on one machine, and an answer taken unchecked can restore into a relative path under whatever folder the launcher ran in. Trying only the system's native dialog lost on Linux, where no one dialog is always present; the picker variable is the one provider a headless test or an integrator can supply."""),
    ('status', 'Drafted')])
L.add_row('LLR-156', 'design', 'LLR-157', [
    ('title', 'The no-dialog switch and the folder-choice switch steer the choice, never past an unattended session'),
    ('parent', 'LLR-073'),
    ('constrains', 'IF-020'),
    ('detail', """On the language-runtime route, the no-dialog switch, or the no-dialog variable set to 1, suppresses the folder choice: with an interactive console and no target the restore asks by typed prompt, and without one it prints its usage and returns 2. On the shell route a folder choice is offered only when the request carries the folder-choice switch; without it a missing target is a bad request (2) whatever the session, and the shell route never asks by typed prompt. Neither switch overrides a session in which nobody can answer: declared unattended, redirected or closed input, or neither a console nor a desktop, still gives the usage and 2."""),
    ('dimensions', 'route=set{language-runtime,shell}; no_gui=set{none,switch,variable}; pick_target=bool; session=set{unattended,console-only,desktop}; @pairwise'),
    ('rationale', """A desktop user who wants the typed prompt, or a test with no display, needs a way to turn the dialog off, and a shell restore started by a script with no target must fail at once rather than open a dialog. Offering the dialog on the shell route whenever a desktop is present lost because a scheduled job on a desktop machine would then wait on a dialog nobody sees."""),
    ('status', 'Drafted')])
L.sub('LLR-074', 'detail', 'The Windows launcher is one line, with no pause; the macOS launcher asks for the target by folder choice when given no arguments and runs the shell route without needing an executable bit on the restorer. Neither carries restore logic.',
      'The Windows launcher runs one command, with no pause; the macOS launcher, given no arguments, passes the request for a folder choice to the shell route (LLR-157), which makes the choice, and runs it without needing an executable bit on the restorer. Neither carries restore logic.')

# --- Release guidance ---
L.set('LLR-027', 'detail', """Following only the quick-start guidance, a new user on a supported host produces a configuration the launch checks accept and completes a first backup with the complete outcome; the hashing component is obtained on first use without a separate install step. On Windows the user runs the configuration helper, which writes the native-Windows form in the current description version, with the notification login protected by the host. In the container the user starts from the example configuration and the published description of the JSON form, since the helper writes only the native-Windows form and a host-protected login cannot exist there.""")

# --- consistency fixes found by the sweep ---
C.sub('CMP-006', 'notes', 'Opens a record only once the configuration has been admitted, so a refused launch truncates nothing.', 'Opens a record only once the configuration and the record\'s own location have been admitted, so a refused launch creates, truncates and appends to no record and reports on the console only.')
I.sub('IF-009', 'rationale', 'The SR-075 tokens are kept exactly as hosts already search for them;', 'The tokens already in use are kept exactly as hosts already search for them;')
I.sub('IF-027', 'data', 'and zenity, kdialog or yad on a Linux desktop,', 'and on a Linux desktop zenity, kdialog and yad, in that order of preference,')
L.sub('LLR-156', 'detail', 'and on a Linux desktop the first present of zenity, kdialog and yad;', 'and on a Linux desktop the first present of the Linux desktop dialogs, in the order of preference the dialog form gives;')
L.sub('LLR-125', 'detail', 'From the moment the claim is taken until the staging area is removed,', 'From the moment its owner record is written until the staging area is removed,')
old_hdr = "# spell them identically. The kit's own code files are named by role only.\n"
assert I.segs[0].count(old_hdr) == 1
I.segs[0] = I.segs[0].replace(old_hdr, "# spell them identically. The kit's artifact names are form too: IF-019 holds\n# the one closed set, which the writers, the launchers and the kit refresh share.\n")

# ======================================================================
# Write, and check
# ======================================================================
out = {
    'components.toml': C.text(),
    'interfaces.toml': I.text(),
    'low-level-requirements.toml': L.text(),
    'external.toml': E.text(),
}
for name, text in out.items():
    tomllib.loads(text)
    (REQ / name).write_bytes(text.encode('utf-8'))
srt = R.text()
tomllib.loads(srt)
(REQ / 'system-requirements.toml').write_bytes(srt.replace('\n', '\r\n').encode('utf-8'))
for name in ('components.toml', 'interfaces.toml', 'low-level-requirements.toml'):
    (HERE / name).write_bytes(out[name].encode('utf-8'))
print('written')
