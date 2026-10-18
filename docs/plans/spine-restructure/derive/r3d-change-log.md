# Round 3d: change log of full round 2

The builder's application of `r3-dispositions.md` ("Convergence check 1 and full round 2", R3C-001 to R3C-008) to the design tier and the named SR rows. The earlier calls K01 to K38, the round-1 dispositions and the pending Owner rulings P-01 to P-12 stand at their defaults; P-10 is widened as the disposition states. Every row stays Drafted. The edits are scripted: `r3-merged/_r3d_apply.py` (every tier edit, as anchored replacements over the carriers read from git HEAD, so a re-run reproduces them) and `r3-merged/_r3d_docs.py` (design-gaps.md and merge-notes.md); `r3-merged/_r3b_lint.py` and `_tomledit.py` are reused unchanged. Nothing was committed. stakeholder-needs.toml is untouched.

New LLR id: LLR-161, upward from LLR-160, the highest in use (LLR-145 stays retired).

## The one staging layout and the one fence (R3C-002, R3C-005)

The tier now states one layout. A staging area `Temp` sits at the saved-state root (the one a removal uses and the one holding the owner record) and, while a backup holds the backup, at the backup root. Each staging area of a backup holds that run's folder `Run-<RunId>`. Every change a backup makes to the store is a rename into or out of the run folder of the root it changes: a publication renames out of it, a delete renames the entry in under the `.fb-deleted` form and purges it at once, the saved state is prepared in the saved-state root's run folder and published by renaming its folder out, and the owner record is deleted the same way at the end. A reclaim moves the backup root's staging area aside first, then the saved-state root's, so any rename a resumed former owner then issues names a path that no longer exists and fails by itself. The owner-record re-read stays as the early exit. The one write that can land after a reclaim is through a handle the run already held open, and it lands in the moved-aside leftovers. The run folder's entries are a closed set (IF-033), so a dead run's leftovers are recognised positively (LLR-088), the prepared saved-state folder included.

Rows that state the layout, publication, deletion, reclaim, leftovers classification or the fence, and what each now says:

| Row | What it now states |
|---|---|
| IF-033 (v2) | Both staging areas, the owner record (schema unchanged, RunId in lowercase canonical form), the run folder, the closed set of run-folder entries (prepared saved-state folder, publication temporaries, stored-object temporaries, entries being deleted, each prefixed with the saved-state folder name where its destination is a saved state), reclaimed leftovers beside either Temp. |
| IF-013 (v3) | The backup root gains its staging area and reclaimed leftovers; the temporaries beside a record or a stored object are now those of a removal, a repair or an earlier release (a backup's lie in its run folder). |
| IF-030 | The run-state record's temporary sits beside it or in a backup's run folder. |
| IF-044 (v2) | The request carries both staging areas, the run folders' listings, each entry's form and the facts needed to recognise an entry being deleted and a prepared folder; the verdicts are defined over "entries holding no content", which the form lists. |
| LLR-125 | The fence: changes only by renames through the run folders (LLR-161); a reclaim makes every later rename fail; the owner-record re-read as the early exit; the open-handle residual; the reclaimed run reports on the console and the global record only; the end-of-run order. Writes outside the store are named as guarded by the early exit only. |
| LLR-161 (new, child of LLR-125, constrains IF-033) | The routing: one run folder per root, created once before the owner record, never re-created; each kind of change as a rename into or out of it; no rename straight between published places. |
| LLR-150 | Preparation in the saved-state root's run folder; earlier content placed by a verified copy published through the run folder, the backup root's copy deleted only after; the prepared-folder and copy-before-delete kill cases. |
| LLR-005, LLR-059, LLR-041 | Content is "placed", not "moved"; LLR-041's failing steps are the copy, its check, its publication and the saved-state publication; a failed delete of the root copy leaves a duplicate the collapse removes. |
| LLR-026 | Each rewritten record published, and each redundant copy deleted, through the run folder of its root. |
| LLR-117 | A new stored object's temporary is in the run folder of its root; a dead run's temporaries go with its reclaim; only an earlier release's temporary beside an object is swept by form. |
| LLR-087, LLR-118 | The record writer's temporary is in a backup's run folder, or beside the destination for a removal, a repair or the change-detection state; an interrupted record publication is completed from an evidence temporary beside the record or in the moved-aside run folder, by a copy published through the new run's own folder. |
| LLR-080 | Staging areas and run folders are created before the owner record, which sits in the saved-state root's staging area; a refresh touch after a reclaim lands in the moved-aside leftovers. |
| LLR-017 | Classifies both staging areas and their run folders; content is any entry LLR-088 does not recognise; ownerless areas holding no content are judged by their own times. |
| LLR-088 | The closed list of entries holding no content, the prepared folder recognised positively (no stored object, nothing outside its closed set, record files byte-identical to the backup root's); every other entry is content. |
| LLR-124 | The reclaim moves both staging areas aside (backup root first), checks identity, creates fresh areas with this run's folders and the owner record, completes an identified interrupted publication through its own folder, then deletes the recognised entries by exact name and the folders non-recursively. |
| LLR-022 | The staging area and its reclaimed leftovers are infrastructure names at the backup root. |
| LLR-052 | Earlier content counts at its stored size where the saved-state root is on another volume; on the same volume only the largest copy counts, within the temporary allowance. |
| LLR-091, LLR-122, LLR-123 | "a staging area" where they said "the staging area". |
| CMP-012 | The guard keeps the run folders and its reclaim is the fence; today's single staging area noted. |
| SR-144 | Rationale and acceptance follow the filesystem fence: the resumed run writes nothing outside the leftovers its successor set aside. P-09 (a) still stands. |

Checked and left unchanged: LLR-028 (writes the run state "through its publication temporary, as records are", which LLR-087 now places), IF-032's form, LLR-046 and LLR-127 (a removal is refused by any staging area holding more than its own marker, which already covers a backup's leftover at either root), LLR-093, SR-017, SR-075, SR-082.

## One entry per finding

| Finding | Rows changed | What changed |
|---|---|---|
| R3C-001 | LLR-109, IF-018, LLR-144, LLR-115, IF-004 | With the change-detection record at the source root (the default), only the record and its publication temporaries there are system-owned. LLR-109's system-location class names "a change-detection state location configured apart from the source", its inside-source class includes the source root, and a new sentence says a link to the source root or any folder of the source is inside-source, recorded with its walk path and re-pointed at restore; dims gain `source-root`, `separate-state-location` and `state_location`. IF-018's classes say the same. LLR-144 re-points a link to the source root; dims gain `source-root`. LLR-115 says the source root stays part of the source. IF-004's SourceStatePath reads "a folder apart from the source ... default the source root, where only the record's own files are the system's". SR-150 and SR-152 already require this and are unchanged. Gap M79 amended. |
| R3C-002 | SR-144, LLR-125, LLR-161 (new), IF-033, IF-013, IF-030, LLR-150, LLR-117, LLR-087, LLR-118, LLR-080, LLR-026, LLR-005, LLR-041, LLR-052, LLR-059, LLR-022, CMP-012 | The coordinator's design call, as the section above. Gap M83 (supersedes M62). |
| R3C-003 | SR-086, LLR-091, LLR-095, LLR-122 | SR-086's requirement says "without changing anything in it" (it said create, move or delete, which an append slipped past); its acceptance adds that the refusal is reported on the console and in the launch's own record outside the backup. LLR-091 and LLR-122: a refusal on the claim reaches the console and the global record only. LLR-095: a refusal before the location's record is opened, on the claim or at admission, leaves the location's record unchanged; dims gain `location_admission`. IF-013 needed no change (it places the location record; the rows decide who writes it). Gap M88 (today's engine appends the refusal to the existing location record). |
| R3C-004 | SR-106, LLR-159, LLR-123, LLR-130, LLR-040, IF-032 | P-10 widened. LLR-159: a mixed kit is re-read every 2 seconds for up to 60 seconds; agreeing with the restorer's own revision proceeds; still mixed, the restore tests the claim by an open the holder's excludes, closed at once and never creating the file: held gives 4 naming the refresh, not held gives 3 naming a re-run of the refresh (the interrupted case). LLR-123 and LLR-130 state the wait and the 4; LLR-040 classifies a live refresh past the wait as 4 and a mixed kit with no refresh running as 3. SR-106's acceptance, rationale and permutations (`kit=set{settled,mid-refresh}`) carry the case. IF-032 gains the restore admission (CMP-018) as a consumer. Gap M85. |
| R3C-005 | LLR-088, LLR-017, LLR-124, IF-033, IF-044, LLR-150 | A prepared, unpublished saved-state folder is recognised positively (no stored object, nothing outside its closed set, record files byte-identical to the published latest state's) and is reclaimable as holding no content once its owner is proven dead; any other folder in staging still refuses. Gap M84. |
| R3C-006 | IF-022, IF-023, LLR-010, LLR-142, LLR-143, LLR-144 | The report takes RECONSTRUCT.log, or the first RECONSTRUCT-<n>.log, that no recorded file, folder or link at the target's root, and no parent folder a recorded entry needs, takes under the target's comparison rules. IF-022 states it; IF-023, LLR-010 and LLR-142 use the same wording; LLR-143 and LLR-144 say the report never takes a folder's or a link's place. Dims: LLR-142 `report-vs-file`, `report-vs-folder`, `report-vs-link`, `report-vs-parent-folder`; LLR-143 `folder_named_like_report`; LLR-144 `link_named_like_report`. Gap M86 (extends M67). |
| R3C-007 | LLR-159 | The kit-origin artifact carries no current revision and takes no part in the revision check; its original revision is kept for LLR-138's age decisions; dims gain `refreshed-with-kit-origin`. IF-019 already says the artifact carries no current revision, and LLR-131 and LLR-138 already keep and read it; all three unchanged. Gap M64 amended. |
| R3C-008 | LLR-157, LLR-073 | SR-073 stands. LLR-157: on the shell route, with no folder-choice switch and no target, the restore asks by typed prompt where an interactive console is present, desktop or not, taking only one absolute path of an existing folder; an unattended session (declared, redirected or closed input, or neither console nor desktop) still gives usage and 2. LLR-073 says "on either route"; dims gain `route`. Code check: `bash/reconstruct.sh` has no typed prompt (the picker runs only with `--pick-target`, and an empty target reaches the required-argument check, usage and exit 2). Gap M87. |

## Consistency changes beyond the named rows

Made because a changed value or form also appears elsewhere: LLR-040 (the restore's classification of a mixed kit, live 4 and interrupted 3, aligned with LLR-159); LLR-123 and LLR-130 (the same case); LLR-005, LLR-041, LLR-059 (content is placed by copy then delete, not moved); LLR-022 (the backup root's staging area is an infrastructure name); LLR-052 (the space plan's count of earlier content on one volume and on two); LLR-087 and LLR-118 (where a backup's temporaries now lie); LLR-091, LLR-122 and LLR-123 ("a staging area", since there are now two); IF-030 (the run-state temporary's place); IF-032 (the restore's claim test makes the restore admission a consumer). Every outcome value used is from the vocabulary: 4 for a refresh still running or a restorer replaced while it ran (SN-026's host or tool class, as SR-040's 4 admits), 3 for a kit an interrupted refresh left (damaged record), 2 for no target in an unattended session, 0 for a reclaim whose final delete fails, 1 for a run whose claim was lost (SN-045).

## Applied differently, and why

- **R3C-002, one run folder per root, not per volume.** The call says one staging folder on each volume the run changes. A run folder in each root it changes (backup root and saved-state root) covers every volume, keeps every rename inside one root, and needs no volume-identity test to decide whether the two roots share a volume. On one volume this costs one extra empty folder.
- **R3C-002, earlier content is copied, then the original deleted, on one volume as on two.** The call lists publication and deletion, not a move between published places. A rename straight from the backup root into a published saved state goes through no run folder, so a resumed former owner could still make it after a reclaim. Two renames through the run folder would leave the content in no published place between them, which breaks LLR-150 and SR-082 (a visible state restorable or refused with 3, never short). So each object is a verified copy published into the saved state through the saved-state root's run folder, and only then is the backup root's copy deleted through its run folder. The cost: the superseded and removed content is read and written once more each run, about 1 GiB at most within SR-113's declared change (a few seconds at the reference host's 200 MiB/s), plus one object's extra space at a time on the same volume (counted in LLR-052's temporary allowance). Before this, a same-volume move was a rename. **For the coordinator:** a run that supersedes or removes very large files outside the declared envelope (a large edited disk image, a big folder deleted from the source) now pays a full copy where it used to rename.
- **R3C-004, a claim that cannot be tested.** The disposition sets two values: 4 with a live holder and 3 with none. A route that cannot test the claim (stock macOS has no lock tool for the shell route, or the claim file cannot be reached) is given 3, with a message saying a refresh may still be running. The other choice, 4, would make a host retry forever over an interrupted refresh, which is the failure R3S-007's reasoning rejects. Also within P-10 (a) as widened: a restore whose own restorer was replaced during the wait (the kit comes to agree on another revision) ends with 4 naming the refresh, since a re-run starts the new restorer.
- **R3C-008, a desktop with no console on the shell route.** Without the folder-choice switch, the shell route still gives usage and 2 there. The desktop launchers pass the switch (LLR-074), so the restore kit asks by folder choice on a desktop as SR-073 requires; a bare shell restorer double-clicked with no switch is not one of the kit's desktop entry points.

## Findings outside this pass's scope (surfaced, not fixed)

- **SR-144 and writes outside the store.** The fence covers the store's two roots. A resumed former owner can still write to three things before its next early-exit read: the location's record (an append-only log in the saved-state root, which its successor truncated and writes), the change-detection state (at the source root or a configured location) and the views. None of these renames through a run folder. Data is not at risk: the change-detection state is reconciled against the latest record (LLR-114) and the views are regenerated. But SR-144's "change no file its successor wrote" is not met for these in the letter. LLR-125 now says the early exit is what guards them. Closing it needs either a narrower SR-144 (the store only) or per-run names for those artifacts. That is a design choice for the coordinator.

## Counts after the fixes

- Components 24; interfaces 45 (41 boundary, 4 internal); LLRs 139 (110 top-level, 29 child), 1 added; legacy LLR ids kept 73.
- Placement: 65 placed, 11 placed at an ancestor, 63 unplaced, none misplaced (LLR-161 placed at CMP-012; no other `constrains` cell changed).
- Design gaps 88 (M01 to M88; M83 to M88 new; M55, M62, M63, M64, M67, M73, M79 amended). SR-constrains pairs 19 (unchanged).
- Rows changed or added: 44 (1 CMP, 9 IF, 30 LLR changed and 1 added, 3 SR; the list below).

## Every row changed or added

This list scopes the next convergence check. Generated by `r3-merged/_r3b_lint.py --changed`, comparing every carrier with git HEAD (`4c802dd`) cell by cell.

### components.toml (1)
- CMP-012: changed: notes
### interfaces.toml (9)
- IF-004: changed: data
- IF-013: changed: data, version
- IF-018: changed: data
- IF-022: changed: data
- IF-023: changed: data
- IF-030: changed: data
- IF-032: changed: consumers
- IF-033: changed: data, rationale, title, version
- IF-044: changed: data, version
### low-level-requirements.toml (31)
- LLR-005: changed: detail
- LLR-010: changed: detail
- LLR-017: changed: detail, dimensions
- LLR-022: changed: detail, dimensions
- LLR-026: changed: detail
- LLR-040: changed: detail
- LLR-041: changed: detail, dimensions, rationale
- LLR-052: changed: detail
- LLR-059: changed: detail, rationale
- LLR-073: changed: detail, dimensions
- LLR-080: changed: detail
- LLR-087: changed: detail, dimensions
- LLR-088: changed: detail, rationale, title
- LLR-091: changed: detail
- LLR-095: changed: detail, dimensions
- LLR-109: changed: detail, dimensions
- LLR-115: changed: detail
- LLR-117: changed: detail, dimensions
- LLR-118: changed: detail
- LLR-122: changed: detail
- LLR-123: changed: detail, dimensions
- LLR-124: changed: detail, dimensions, rationale, title
- LLR-125: changed: detail, dimensions, rationale, title
- LLR-130: changed: detail
- LLR-142: changed: detail, dimensions
- LLR-143: changed: detail, dimensions
- LLR-144: changed: detail, dimensions
- LLR-150: changed: detail, dimensions, rationale
- LLR-157: changed: detail, dimensions, rationale, title
- LLR-159: changed: detail, dimensions, rationale, title
- LLR-161: added
### system-requirements.toml (3)
- SR-086: changed: acceptance_criteria, requirement
- SR-106: changed: acceptance_criteria, permutations, rationale
- SR-144: changed: acceptance_criteria, rationale
TOTAL 44

## Checks

The three design-tier files in `r3-merged/` are byte-identical to `docs/requirements/`.

`python validate_design.py C:\Projects\FileBackup\docs\plans\spine-restructure\derive\r3-merged`:

```
components=24 interfaces=45 (boundary=41, internal=4) llr=139 (top=110, child=29) legacy_kept=73
SRs reaching no LLR: 0 []
ERRORS 0
WARNINGS 14
  W IF IF-013.data: code-like token 'FileBackupState.json'
  W IF IF-013.data: code-like token 'FileBackupState.json'
  W IF IF-013.data: code-like token 'RECONSTRUCT.bat'
  W IF IF-019.data: code-like token 'RECONSTRUCT.cmd'
  W IF IF-019.data: code-like token 'RECONSTRUCT.ps1'
  W IF IF-019.data: code-like token 'reconstruct.sh'
  W IF IF-019.data: code-like token 'Common.psm1'
  W IF IF-019.data: code-like token 'paths.json'
  W IF IF-019.data: code-like token 'RECONSTRUCT.bat'
  W IF IF-020.data: code-like token 'RECONSTRUCT.cmd'
  W IF IF-028.data: code-like token '$RECYCLE'
  W IF IF-030.data: code-like token 'FileBackupState.json'
  W IF IF-030.data: code-like token 'FileBackupState.json'
  W IF IF-038.data: code-like token 'FileBackup.json'
```

Every warning is an on-disk name in an interface's `data` (the agreed form), the same 14 as round 3b; no warning is on an LLR or CMP row.

SR parse and reference resolution (`_r3b_lint.py`: every sn_refs, boundary_refs and da_refs id of every SR resolves; no SR cell names a file; dimension grammar of every LLR; no history token in an LLR rationale; no `shall` in an LLR; no dangling LLR or IF reference; no curly quote):

```
tomllib: system-requirements, external, stakeholder-needs and assumptions parse
PROBLEMS 0
```
