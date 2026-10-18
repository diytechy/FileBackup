# Round 3f: change log of full round 3 (the last)

This is the builder's pass over `r3-dispositions.md`, section "Convergence check 2 and full round 3 (the last)" (R3E-001 to R3E-006), applied to the design tier and to the two SR rows it names. The earlier calls (K01 to K38), the round-1 and round-2 dispositions and the pending Owner rulings P-01 to P-13 still stand at their defaults, with P-09 and P-10 as widened. The one exception is R3E-004, which reverses the round-2 choice of 3 for a claim that cannot be tested. Every row stays Drafted.

The edits are scripted:
- `r3-merged/_r3f_apply.py` makes every tier edit as an anchored replacement over the carriers read from git HEAD (`6366498`), so a re-run reproduces them.
- `r3-merged/_r3f_docs.py` updates design-gaps.md and merge-notes.md.
- `_tomledit.py` and `_r3b_lint.py` are reused unchanged.

Nothing was committed. stakeholder-needs.toml is untouched. No LLR was added, so the highest id in use is still LLR-161.

## One entry per finding

| Finding | Rows changed | What changed |
|---|---|---|
| R3E-001 | LLR-125, LLR-161, SR-144, IF-009, IF-013, IF-033 | **The location record is now inside the fence.** A run writes its own record as `backup-<RunId>.log` in the saved-state root's run folder. As its last step before cleanup, on every ending except a lost claim, it publishes that record by renaming it to `backup.log`, replacing the previous one. IF-009 (v2) states both names and the place a killed or reclaimed run's record keeps (`Temp.stale-.../Run-<RunId>/backup-<RunId>.log`). Its rationale says why a record written in place lost. IF-013 says `backup.log` is the record of the last run that published one, and names the in-progress record. IF-033 (v3) adds the record to the run folder's closed set. LLR-161 states the routing, plus a failed publication: the record stays in the run folder, which is kept, and the outcome is unchanged. LLR-125 covers four things: the record is fenced like every other store change; a run that lost its claim publishes no record and its record stays among the leftovers; the open-handle residual now includes the record; the end order now publishes the record before the deletes. It also states that the change-detection state and the views lie outside the store, are guarded only by the early exit, and are derived (reconciled by LLR-114 and LLR-061). Dimensions: LLR-125 `step` gains `location-record-publication`, LLR-161 `change` gains `location-record`. SR-144's acceptance now reads "changes no file of the store ..., the location's record included" and "writes nothing in the store outside the leftovers", and names the change-detection state and the views as outside its guarantee because they are derived and the next run reconciles them. New gap M89; M83 and M88 amended. |
| R3E-002 | LLR-080, LLR-088, LLR-161, IF-044 | **A torn owner record beside empty run folders is now reclaimable.** An owner record that carries no usable run identity (torn at creation, or of an unknown schema with no RunId in canonical form) sits beside run folders that are empty or hold only their own location record. Those folders hold no content, so the leftovers are the harmless case once death is proven by stale age and the confirming second sample (LLR-080's fall-back to modification time). A non-empty or unrecognised folder is still content and refuses. IF-044 (v3) now carries the owner record's run identity where present, lists the case among "entries holding no content", and says OwnerStale includes a torn record. LLR-161 says a kill between the run folders' creation and the owner record's write leaves exactly this case. LLR-017's dimensions gain `run_folder=set{owner-identity,other-identity,beside-no-identity,beside-no-owner}`. M84 amended. |
| R3E-003 | IF-033, LLR-088, LLR-150, LLR-038, IF-044 | **The prepared saved state's evidence is generated, not copied.** LLR-038 stands: the writer writes evidence for the record it stages for a prepared saved state, and evidence is never copied. IF-033's prepared folder now holds "completeness evidence written for that copy". A prepared folder is recognised when three things hold: its record of contents, folder record and link record are byte-identical to the backup root's; its evidence is valid; and that evidence matches its own record. Evidence bytes are not compared. LLR-088 states this and its rationale says why comparing evidence bytes lost (written time). IF-044 carries the evidence test and LLR-150 describes the kill-while-preparing case the same way. LLR-017's dimensions gain `prepared-evidence-fails`. M84 amended. |
| R3E-004 | LLR-159, LLR-130, LLR-040 | **Reverses the round-2 deviation.** After the wait, a still-mixed kit gives: claim held, 4 naming the refresh; claim free, which is positive evidence, 3 naming a re-run of the refresh; claim untestable, 4 naming the refresh, the files that differ and the remedy (re-run it where none is running). No tool is added to the shell floor (IF-024 unchanged). LLR-159's rationale says why treating an untestable claim as free lost. LLR-130 and LLR-040 use the same three cases, and LLR-040's dimensions gain `claim_test`. M85 and M64 amended. |
| R3E-005 | LLR-123, LLR-118, LLR-039, SR-106 | **A reader now waits for a record and its evidence to settle.** Where the two disagree, a reader re-reads the pair every 2 seconds for up to 60 seconds, and a pair that comes to agree is read normally. If they still disagree, the reader tests the claim as LLR-159 does: held or untestable gives 4, naming a changing operation that may be running and the remedy; free gives 3. LLR-123 replaces its three re-reads with this rule; its dimensions swap `rereads=range[0..3]` for `pair`, `claim` and `wait_seconds=range[0..60]`, and its rationale says why a fixed count and an unbounded wait lost. LLR-118 says a reader meeting the new record beside the old evidence waits, and reports no damage while a writer holds the backup; its dimensions gain `observer`. LLR-039 waits out each evidence fault first, then gives 3 with a free claim and 4 with a held or untestable one; its dimensions gain `pair` and `claim`. SR-106 is required by this finding, because its acceptance promised the normal outcome without exception. It now says "save the bounded waits below", adds the record/evidence wait and its 4, adds a rationale sentence, and its permutations gain `record=set{settled,mid-publication}`. This is P-10 as widened. New gap M90. |
| R3E-006 | LLR-157, LLR-073 | **LLR-157 now meets SR-073 on the shell route.** On a desktop, either route offers the folder choice through the providers (LLR-156, IF-027) unless it is suppressed: by the no-dialog switch on the language-runtime route, or by the no-dialog variable on either route. The shell route sees a desktop from the host session, or from the folder-choice switch, which declares one; the macOS launcher passes it. With the choice suppressed or no provider present: a typed prompt where an interactive console is present, otherwise usage and 2 naming the missing provider. A console with no desktop gets the typed prompt. An unattended session gets 2. A failed or cancelled choice gives 2 and never a prompt. LLR-073 states the same session decision, and its dimensions gain `console_with_desktop`. LLR-157's dimensions gain `provider` and `choice`. Its rationale drops the lost alternative it had adopted ("dialog on the shell route whenever a desktop is present") and says why a scheduled job is not asked (its input is redirected or closed). Its title becomes "no-dialog switches". SR-073 is unchanged. M87 and M73 amended. |

## Consistency changes beyond the named rows

I searched the whole tier (every CMP, IF, LLR and SR row) for the location record and `backup.log`, for mixed-kit outcomes, for record/evidence mismatch outcomes, for the prepared folder's record files, and for the shell route's target choice. The rows below changed because they state the same case:

- **The location record.**
  - LLR-095: a location's record is never truncated or appended in place. A run creates its own in its run folder after admission and replaces the published one only by publishing its own. A refusal before that point leaves the published record unchanged.
  - LLR-091: "nothing is appended to" becomes "is left unchanged".
  - LLR-124: a reclaim deletes every entry LLR-088 recognises except a former run's location record. The record is kept where it lies, with the folders that hold it, so it stays readable; the moved folder is named and the run completes (0). A run's own cleanup on an early failure publishes its location record first. `contents` gains `location-record`.
  - LLR-088 and IF-044: a run's location record in its run folder holds no content.
  - CMP-006 notes: today the record is truncated and appended in place outside any run folder.
  - LLR-107, LLR-052 and LLR-122: checked, unchanged. They state what a record says, not where it is written.
- **The views.** LLR-061: a run that did not change the latest state skips the view only where its stamp matches the latest record's rows. This makes LLR-125's "the next run rebuilds a view whose stamp differs" true. Before, the row said "may skip".
- **Record/evidence mismatch outcomes.**
  - LLR-049: the check reports RecordEvidenceMismatch (3) only once the wait ends with the claim free. A state whose pair still disagrees while another operation holds the claim, or the claim cannot be tested, is not checked. The check names it, reports no finding for it, and ends with 4. The precedence becomes 2 over 3 over 4 over 1, the shared vocabulary's (it was 2 over 3 over 1, with no 4). `damage` gains `record-evidence-unsettled`, plus a `claim` dimension.
  - IF-009: a message kind `Not checked: <saved-state folder name or latest> - record and evidence not settled ...`, since the message-kind list is closed.
  - LLR-040: a record still disagreeing with its evidence after the wait is 3 with the claim free, and 4 when the claim is held or untestable.
  - Checked, unchanged: LLR-017 and LLR-046 (they run under their own claim, so the evidence is positive), LLR-114 (the change-detection record is rebuilt, with no outcome), LLR-136 (order only).
- **Mixed-kit outcomes.** LLR-040 and LLR-130, as above. LLR-123 (the kit sentence) and SR-106 (the kit sentence) already say 4 past the wait, so both are unchanged.
- **The shell route's target choice.** LLR-074: the macOS launcher passes the folder-choice switch, which declares the desktop the shell cannot see, and the shell route makes the choice. Checked, unchanged: LLR-156 (provider order; "with none of these there is no folder choice", which LLR-157 now picks up), IF-020 (the switch list), IF-026 (the no-dialog variable already reads "asks for no folder choice", route-neutral), CMP-022.

Outcome values used, checked against SN-045 and SN-026:
- 4 where a refresh or writer may still be running, or the claim cannot be tested (retry later, nothing changed);
- 3 only with positive evidence that no writer holds the backup (damaged record);
- 2 for no target in an unattended session or with neither console nor provider (needs a person);
- 0 for a reclaim that keeps a former run's record;
- 1 for a run whose claim was lost.

## Applied differently, and why

- **R3E-001: the published name is fixed, and only the in-progress name is per-run.** The run's record is `backup-<RunId>.log` inside its run folder, and is published as `backup.log`, replacing the previous run's. That keeps today's one-record-per-location form (today's record is truncated at each run's start, so only the last run's survives either way) and adds no unbounded set of files at the saved-state root. **Downstream-visible:** during a run, `backup.log` shows the previous run's record, and the run in progress can be read from its run folder, the console and the global record. Recorded in M89.
- **R3E-001: the reclaim keeps the killed run's record.** For that record to "stay readable among its moved-aside leftovers", the reclaim must not delete it. So the moved-aside folder that holds it is kept and named, and the run completes (0). Each reclaim that finds such a record therefore leaves one small `Temp.stale-*` folder.
- **R3E-001: SR-144's requirement text is unchanged.** The instruction scoped the SR edit to the acceptance. The requirement still says "change no file its successor wrote or published", which read literally includes the change-detection state and the views that the acceptance now excludes. See "Surfaced" below.
- **R3E-005: the wait covers every evidence fault.** It covers unparseable evidence and a current-form record with no evidence, as well as a length or digest mismatch. An evidence file is replaced whole by rename, so in practice only a mismatch or a first publication shows mid-publication. Waiting on all of them keeps one rule and costs at most 60 s before a real 3.
- **R3E-005: the check's 4 is a "not checked" entry, not a new finding class.** IF-010's class set is unchanged, and a host sees no finding for that state plus exit 4.
- **R3E-006: both routes take the no-provider fallback.** The disposition states it for the shell route. LLR-073 had said an absent folder choice never falls back to a typed prompt. Keeping that on the language-runtime route only would give the two routes different answers for one session, which LLR-156 and SR-040's parity reasoning reject. So with no provider present, both routes now prompt at an interactive console. A failed or cancelled choice still gives 2 on both. The no-dialog variable now applies on the shell route too, since that route can now open a dialog.

## Findings outside this pass's scope (surfaced, not fixed)

- **SR-039 against the macOS shell route.** The shell floor has no lock tool on stock macOS (IF-024, unchanged by R3E-004), so the claim cannot be tested there. Under R3E-004 and R3E-005, a damaged record or an interrupted kit refresh met on that route is reported as 4, naming the remedy, never 3. SR-039's acceptance says "every restorer exits 3" for a damaged record, with `restorer=set{windows,linux,macos}`, and SR-110 says 3 for a kit an interrupted refresh left. Options: (a) SR-039 and SR-110 admit 4 where the claim cannot be tested; (b) the shell floor gains a way to test the claim on macOS; (c) a positive no-writer signal the shell can read without a lock. This needs an Owner or coordinator ruling.
- **SR-144's requirement wording.** "Change no file its successor wrote or published" against the acceptance's "of the store". Adding "in the store" to the requirement would match P-09 (a) as widened.
- **The open-handle residual and the move-aside.** The location record is now held open for the run's whole life, beside the owner record's refresh handle. On some filesystems a folder holding a file open on another host cannot be renamed, so the reclaim's move-aside fails and refuses (4 for an I/O fault), which fails toward refusal. This is unchanged in kind from round 3d, but the window is wider. Confirm per filesystem at build time.

## Counts after the fixes

- Components: 24.
- Interfaces: 45 (41 boundary, 4 internal).
- LLRs: 139 (110 top-level, 29 child), none added. Legacy LLR ids kept: 73.
- Placement: 65 placed, 11 placed at an ancestor, 63 unplaced, none misplaced. Unchanged, because no `constrains`, `parent`, `owner` or `consumers` cell changed.
- Design gaps: 90 (M01 to M90). M89 and M90 are new; M64, M73, M83, M84, M85, M87 and M88 are amended.
- SR-constrains pairs: 19 (unchanged).
- Interface versions: IF-009 2, IF-033 3, IF-044 3.
- Rows changed: 28 (1 CMP, 4 IF, 21 LLR, 2 SR; none added).

## Every row changed or added

This list scopes the final convergence check. It was generated by `r3-merged/_r3b_lint.py --changed`, comparing every carrier with git HEAD (`6366498`) cell by cell.

### components.toml (1)
- CMP-006: changed: notes
### interfaces.toml (4)
- IF-009: changed: data, rationale, version
- IF-013: changed: data
- IF-033: changed: data, version
- IF-044: changed: data, version
### low-level-requirements.toml (21)
- LLR-017: changed: dimensions
- LLR-038: changed: detail
- LLR-039: changed: detail, dimensions
- LLR-040: changed: detail, dimensions
- LLR-049: changed: detail, dimensions
- LLR-061: changed: detail
- LLR-073: changed: detail, dimensions
- LLR-074: changed: detail
- LLR-080: changed: detail
- LLR-088: changed: detail, rationale
- LLR-091: changed: detail
- LLR-095: changed: detail
- LLR-118: changed: detail, dimensions
- LLR-123: changed: detail, dimensions, rationale
- LLR-124: changed: detail, dimensions
- LLR-125: changed: detail, dimensions, rationale
- LLR-130: changed: detail
- LLR-150: changed: detail
- LLR-157: changed: detail, dimensions, rationale, title
- LLR-159: changed: detail, rationale
- LLR-161: changed: detail, dimensions
### system-requirements.toml (2)
- SR-106: changed: acceptance_criteria, permutations, rationale
- SR-144: changed: acceptance_criteria
TOTAL 28

## Checks

The three design-tier files in `r3-merged/` are byte-identical to `docs/requirements/` (checked with `cmp`).

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

Every warning is an on-disk name in an interface's `data` (the agreed form), the same 14 as rounds 3b and 3d. No warning is on an LLR or CMP row.

SR parsing and reference resolution use `_r3b_lint.py`. It checks that every sn_refs, boundary_refs and da_refs id of every SR resolves, that no SR cell names a file, the dimension grammar of every LLR, that no LLR rationale carries a history token, that no LLR uses `shall`, that no LLR or IF reference dangles, and that there are no curly quotes. A tomllib parse of all seven carriers was also run, plus a `shall` count over components.toml:

```
tomllib: all seven carriers parse
SRs 123
PROBLEMS 0
components.toml shall: 0
```
