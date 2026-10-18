# Round 3b: change log of the review dispositions

The builder's application of `r3-dispositions.md` ("Review dispositions, full round 1") to the design tier and the named SR rows, with every pending Owner ruling (P-01 to P-11) at its default and the alignment calls K01 to K38 standing except K27 (overruled by R3S-008). Every row stays Drafted. The edits are scripted: `r3-merged/_r3b_apply.py` (all tier edits, read from HEAD so a re-run reproduces them), `r3-merged/_r3b_docs.py` (design-gaps.md, merge-notes.md and the placement table), `r3-merged/_r3b_lint.py` (extra checks and the changed-row list); `r3-merged/_tomledit.py` is the cell-level editor they share. Nothing was committed.

New LLR ids: LLR-151 to LLR-160, upward from LLR-150, the highest in use (LLR-145 stays retired).

## One entry per finding

| Finding | Rows changed | What changed |
|---|---|---|
| R3S-001 | SR-137, LLR-109 | SR-137's requirement excludes a folder that is one of the link's own ancestors in the walk; its acceptance gains the followed-folder ancestor case and its permutations `ancestor-in-walk`. LLR-109's classes are taken in a fixed order (system location, ancestor by physical location, inside the source, else followed), so exactly one applies. SR-150 already stated the case and is unchanged on this point. |
| R3S-002 | IF-018, LLR-110, LLR-144, SR-152 | IF-018's inside-source class is "a folder the walk captures", an ancestor reached through a followed link included, and its Target is the walk path. LLR-110 records that path (dims gain the ancestor classes); LLR-144 re-points it under the target. SR-152's requirement, acceptance and permutations say "a folder captured in the state", so the SR rule and LLR-144 agree. |
| R3S-003 | LLR-141, SR-121 | LLR-141 checks every link's own place, and the re-pointed target only of a link whose target the walk captured; a link into the system's own locations is not refused for its target. SR-121's requirement splits "placed outside" from "re-pointed outside". |
| R3S-004 | LLR-150, LLR-005, LLR-041, LLR-028, IF-033 | LLR-150 rewritten: prepare the saved state in its own folder inside the staging area, publish it while its content is still in the backup root, publish the new latest record, then move content between published locations (a verified copy across volumes); the next run adopts an identical saved state a kill left behind; dims gain a borrowing older state and volumes. LLR-005 defers the order to LLR-150, LLR-041 restates failure handling for that order, LLR-028 writes the run state after placement, IF-033 lists the prepared folder. IF-013 needed no change for this finding. |
| R3S-005 | LLR-052, LLR-091 | LLR-052's pre-claim plan reads only published records, as a reader does, and "changes nothing" (not "reads and writes nothing"); it may refuse; the plan made under the claim binds. LLR-091 takes the claim before any read a store-changing decision depends on. |
| R3S-006 | LLR-125, SR-144, LLR-117, IF-013 | P-09 (a). LLR-125: one owner-record read before every store mutation, fresh temporaries and new objects included; the residual window is at most one unpublished temporary, which the next run removes. SR-144's title, requirement, acceptance and rationale say "changes no file its successor wrote or published and publishes nothing", with the temporary in the acceptance. LLR-117 removes leftover temporaries; IF-013 gains the stored-object temporary form. |
| R3S-007 | SR-017, LLR-017, LLR-080, IF-044 | Readable evidence not proving death (a torn or unknown-schema record included) is alive or unproven (4 as sole finding); an owner record still unreadable after three reads is evidence that cannot be read (2). SR-017's acceptance, LLR-017's classification, LLR-080's judgement and IF-044's verdict meanings say so. |
| R3S-008 | LLR-042, LLR-095, LLR-018, LLR-097, CMP-006 | Overrules K27. A refused configuration reports on the console only and creates, truncates and appends to no record; SR-018 unchanged. Gap M61. |
| R3S-009 | LLR-026, LLR-149 | LLR-026 rewrites the record of each folder whose entries reference a redundant copy and of each naming a vanished copy, and no other ("not rewritten" replaces "neither read"); records are read only through the index; each rewrite is published and checked before the redundant bytes go; dims gain kill points. LLR-149 now points at LLR-026 instead of restating it. |
| R3S-010 | IF-022, IF-023, LLR-010, LLR-142, LLR-029 | IF-022's report takes RECONSTRUCT-<n>.log where the state records a file at RECONSTRUCT.log; IF-023 says the report takes a name no recorded file takes; LLR-010 says so; LLR-142's collision planning includes the report (dims `report-name`). Gap M67. |
| R3S-011 | SR-106, LLR-123, LLR-040, IF-022 | P-10 (a). SR-106's acceptance holds for every state the running operation does not remove; a restore of the removed state completes or ends with 4 naming the removal, never wrongly; a check or the report leaves it out; rationale and permutations follow. LLR-123 gains the last-copy case, LLR-040 classifies it 4, IF-022 gains the cause StateRemoved. SR-045 unchanged. Gap M71. |
| R3S-012 | LLR-133, IF-042, IF-014 | LLR-133 measures every file of the latest state: read files first, unchanged ones for up to 300 s a run, the rest shown as not yet measured; the previous space view is the cache, so a record never changes for a measure; dims gain file_state, previous_view, budget. IF-042 gains the content key and `not-yet-measured`; IF-014's rate column is described as earlier versions'. Gap M68. |
| R3S-013 | LLR-135, IF-031 | The volume at the longest mount point, Windows folder mounts included, known by a stable identity (volume GUID path, share root, device number) declared in IF-031; dims gain `windows-folder-mount` and alias. Gap M66. |
| R3S-014 | LLR-138, LLR-143, IF-015 | Folder-record age is read from the kit revision (original, else own) below the folder record's first revision; the evidence version decides only the link record and the row counts; dims gain kit age and evidence version. IF-015 says version-2 evidence was written both before and after folder records. **Applied differently on one case** (see below): a version-2-evidence state at or above that revision with no folder record restores complete with the check reported unverified, not 1. Gap M81. |
| R3S-015 | IF-019, LLR-076, LLR-130, LLR-159 (new), LLR-136, LLR-040 | Every text kit artifact carries the kit revision (IF-019 version 14: a remark line in the Windows launcher, a sidecar key, a first line in the notices file; the hashing library by its version). The refresh writes the original revision, then the restorers, then the rest; LLR-159 (child of LLR-130, constrains IF-019) refuses a mixed kit with 3 naming a re-run of the refresh; LLR-136 runs it at admission; LLR-040 classifies it 3. SR-110 already permits 3 and is unchanged. Gap M64. |
| R3S-016 | IF-033 | The owner record's schema version 1, Kind `backup`, the required and the diagnostic fields, and what makes a record of an unknown schema. |
| R3S-017 | IF-044, LLR-017 | IF-044's request gains the staging area's existence, link status, own modification time and age, and read status; LLR-017's dims gain `owner=none`, `staging_age`, `temporary_only`. |
| R3S-018 | IF-019, LLR-022, interfaces.toml header | IF-019 enumerates the closed kit name set (and the retired launcher); LLR-022 uses that one list. The file header no longer says kit files are named by role only. |
| R3S-019 | IF-004, IF-011, LLR-015, LLR-042 | IF-004 states the notification fields (all three needed), SmtpPort 1 to 65535 default 25; IF-011 the port default; LLR-015's eligibility uses the same set (dims gain partial and port); LLR-042's dims gain out-of-range. Gap M75. |
| R3S-020 | LLR-155 (new), LLR-095, LLR-112 | LLR-155 admits the global record's location (request, environment or default) before it is opened: inside a source, the store or at an infrastructure name is a bad request (2), console only. LLR-095 opens the record only after it; LLR-112 points to it. The IF-002 and IF-009 forms needed no change. Gap M72. |
| R3S-021 | LLR-156 (new), IF-027 | LLR-156, a child of LLR-073 constraining IF-027: one provider order for both routes (picker variable first), and any answer but an absolute existing folder gives no target (2). IF-027 gives the Linux dialogs' order of preference. |
| R3S-022 | IF-009, IF-011, IF-015, IF-038, IF-041; also IF-022, IF-030, IF-020; LLR-107, LLR-015, LLR-061, LLR-029, LLR-035 | Behaviour out of the forms: console echo (IF-009 to LLR-107; IF-022's to LLR-029), one message per run and when to log in (IF-011 to LLR-015), unknown evidence keys (IF-015; LLR-039 already states it), pass-through (IF-038; LLR-048 already states it), the root-page replacement (IF-041 keeps the row limit as a constant; LLR-061 the choice). Same case aligned in IF-030 (unknown keys, now LLR-035) and IF-020 (state selection, R3O-032). |
| R3S-023 | LLR-043, LLR-040, LLR-017 | Dims model each coexisting cause as its own boolean, with unclassified-error timing; LLR-017's detail states the 2/3/4 combinations explicitly. |
| R3S-024 | LLR-086, LLR-068 | LLR-086's dims: size below/at/above the floor, saving below/at/above 10 %. LLR-068's dims: signature, length relation, hash match, readability, both recorded-flag values. |
| R3S-025 | LLR-152 (new), LLR-067, SR-137 | LLR-152: each link request waits at most what is left of the location's 60-second budget, shared with retries; once spent, unreachable links are named without waiting; dims gain link_count. LLR-067 shares the budget. SR-137's acceptance gives the unit and per-location scope; permutations gain unreachable_links. |
| R3S-026 | LLR-109, LLR-110, LLR-151 (new), LLR-152 (new), LLR-111, LLR-149, LLR-160 (new) | LLR-109 keeps the routing; LLR-110 recording and its outcome; LLR-151 file links; LLR-152 waiting; an unreachable target is LLR-111's (which now names it). LLR-149 keeps the pass counts and names the rows owning each part; LLR-160 (child) the memory and concurrency bound; progress is LLR-108's. |
| R3S-027 | none | Refuted (the grammar includes `@full`); not applied. |
| R3S-028 | LLR-025, LLR-066, IF-014 | The time text is opaque to the backup side and interpreted by a restore; IF-014 states its grammar (seven fraction digits, Z or a signed hh:mm offset) and that a reader takes LF or CRLF. |
| R3S-029 | LLR-115 | Rationale states the findability and read-only-source consequences, no ruling. |
| R3O-001 | LLR-125, LLR-026, IF-033 | The fence's evidence survives publication: the owner record stays in the staging area until the run-state write, the collapse and the views end, because the saved state is prepared in its own folder inside the staging area and moved out to publish it. Dims gain the collapse steps and the run-state publication. Mechanism differs from the disposition's wording (see below). |
| R3O-002 | see R3S-014 | |
| R3O-003 | LLR-046 | A staging area refuses a removal only when it holds anything other than this request's own removal marker; dims gain `staging-own-marker`. |
| R3O-004 | SR-086 | Requirement states the refusal, treating the backup as held for safety, and leaves the value to the acceptance; retitled. |
| R3O-005 | see R3S-007 | |
| R3O-006 | SR-017, LLR-124, LLR-080 | Each case has its value: move-aside or create failure 4 for an I/O fault, 2 for access denied; identity mismatch after the move 4; an owner record already present 4; a failed final delete keeps the moved folder and the run completes (0). SR-017's acceptance and permutations carry the clean-up cases. Gap M69. |
| R3O-007 | SR-121 | Acceptance gains the link cases (own place out, re-pointed target out: not created, named, 3; own-location target outside: not refused); permutations gain entry=set{file,link}. |
| R3O-008 | see R3S-025 | |
| R3O-009 | see R3S-021 | |
| R3O-010 | LLR-157 (new), LLR-158 (new), LLR-073, LLR-010 | LLR-157 (child of LLR-073): the no-dialog switch and variable, the folder-choice switch, never past an unattended session. LLR-158 (child of LLR-010): the named state and the root overrides, used only where the recorded roots are unusable. The dry run stays unspecified (P-02 (c)). Gaps M73, M74. |
| R3O-011 | IF-007, IF-026 | IF-007 keeps the backup side, its requestors replaced by consumers CMP-006 and CMP-010; FILEBACKUP_NO_GUI and FILEBACKUP_PICKER move to IF-026 (owner unchanged, the restore host), with the rationale. |
| R3O-012 | IF-020, 28 LLRs' constrains, LLR-111, LLR-113, LLR-122, 16 CMP notes, merge-notes, design-gaps | IF-020's owner becomes CMP-017. Rows whose constrained interface belonged to another component's responsibility lost `constrains` (dims kept): LLR-003, 005, 007, 011, 026, 036, 039, 041, 046, 047, 049, 051, 053, 058, 059, 065, 086, 110, 126, 127, 128, 129, 130, 131, 136, 143, 144, 150. LLR-111 now constrains IF-028, LLR-113 IF-029, LLR-122 IF-032. IF-017 and IF-018 keep SR constrainers only (design-gaps section 2). Component notes say which own no interface. merge-notes.md gains the placement table: 64 placed, 11 placed at an ancestor, 63 unplaced, none misplaced. No interface was minted. |
| R3O-013 | LLR-049, IF-010, IF-003, LLR-043 | A record failing its evidence is a RecordEvidenceMismatch finding, reported once per state, outcome 3 (2 over 3 over 1), the check going on; IF-003 and LLR-043 word value 3 for a check. Gap M70. |
| R3O-014 | SR-146, LLR-144, LLR-143, LLR-040 | SR-146 covers the link record and a record short of its stated rows (title, requirement, rationale, acceptance, permutations). LLR-144 (sr_refs gain SR-146) restores every file, names the links not rebuilt and ends 1; LLR-143 gains the short case; LLR-040 classifies both 1. Gap M80. |
| R3O-015 | see R3S-005 | |
| R3O-016 | see R3S-013 | |
| R3O-017 | LLR-103, LLR-153 (new) | The listing-location rule is split out into LLR-153, which carries SR-062 beside SR-063; its rationale gives the relative-link reason. |
| R3O-018 | see R3S-012 | |
| R3O-019 | LLR-027 | The helper clause is Windows-only; the container's route is the example configuration and the published description. |
| R3O-020 | LLR-074, LLR-073 | The macOS launcher passes the folder-choice request and the restore makes the choice; LLR-073 points at LLR-156 and LLR-157. |
| R3O-021 | see R3S-009 | |
| R3O-022 | LLR-117 | Top-level, sr_refs SR-082 and SR-059; constrains kept. |
| R3O-023 | IF-029, LLR-114 | P-08 (a): the record and its evidence are FILEBACKUP-CHANGES.csv(.meta) (IF-029 version 3, rationale); LLR-114 reads the earlier name once where it is identifiably the old change-detection record, then removes it, and treats any other file there as owner content; dims gain earlier_name. Gap M65. |
| R3O-024 | IF-009, LLR-097 | A closed token set with each token's value and cause (the SR-075 tokens kept, [2/staging-busy] and one per refusal cause added) and the message kinds other rows require; LLR-097 uses it (dims). Gap M76. |
| R3O-025 | SR-150, SR-151 | hat_refs removed (the key deleted, as on every SR without a hat); rationales traced to SN-001's acceptance. |
| R3O-026 | SR-151 | `When`; acceptance adds the change-detection state location. |
| R3O-027 | SR-152, SR-121 | SR-152's sn_refs gain SN-001; SR-121's rationale says "a recorded link into the system's own locations". |
| R3O-028 | SR-109 | "or more than one candidate answer remains" dropped from the rationale. |
| R3O-029 | SR-151, LLR-109, IF-018 | P-11 (a): the listing location is one of the system's own locations in all three (requirement, rationale, acceptance and permutations of SR-151). |
| R3O-030 | see R3S-002 | |
| R3O-031 | IF-010 | Each class has a one-line meaning tied to LLR-049 and LLR-054; the fields every finding carries are stated; DanglingDataPath, which duplicated PoolDataPathMissing, is retired (version 2, downstream-visible; in M70). |
| R3O-032 | IF-020 | The state-selection sentence moved out (LLR-010 keeps it); rationale says the state switch is optional. |
| R3O-033 | see R3S-028 | |
| R3O-034 | IF-013 | The full anchored saved-state pattern with the optional `_\d{3}` suffix. Gap M78. |
| R3O-035 | IF-004, LLR-011 | "A or E (every run; A is an accepted synonym of E)"; LLR-011 says either letter; its dims keep A as the synonym. |
| R3O-036 | IF-002 | The general switches apply to every action; -BackupTime is listed as a test seam that sets the run's clock; the code-beyond-the-design entry is updated. |
| R3O-037 | IF-038, LLR-048 | IF-038 states the falsy set; LLR-048: a non-empty value in neither set is a bad request (dims flag_value). Gap M77. |
| R3O-038 | see R3S-018 (IF-019, IF-011 STARTTLS, IF-041 row limit 50000) | |
| R3O-039 | IF-032, IF-044, IF-030, IF-025, IF-014, IF-017, IF-035 | Consumers and requestors recomputed: IF-032 + CMP-011; IF-044 + CMP-013 (the guard's reclaim is IF-044's owner, so not listed); IF-030 loses its own owner; IF-025 + CMP-019, CMP-020; IF-014 + CMP-015; IF-017 + CMP-008; IF-035 + CMP-018. |
| R3O-040 | IF-045 | Kept; rationale says it is the parity form between the two routes. |
| R3O-041 | LLR-037 | "Reading the effort never raises an error and never affects any restore", without the carrier. |
| R3O-042 | LLR-116 | The estimator is a fast general-purpose compressor's fully flushed output size; no codec named. |
| R3O-043 | LLR-022 | "Of the infrastructure names, only the change-detection record and its publication temporaries are left out at a source root." |
| R3O-044 | LLR-042, LLR-099, LLR-027, LLR-103, LLR-153 (new), LLR-154 (new) | Version faults out of LLR-042's dims (LLR-098 and LLR-099 keep them); LLR-099's helper clause moves to LLR-027; LLR-103 split into LLR-103 (backup and saved-state, SR-138), LLR-153 (listing, SR-063 and SR-062) and LLR-154 (state location, SR-149). |
| R3O-045 | LLR-045 | The colliding re-home name is a precondition not met (2), naming the colliding file. |
| R3O-046 | LLR-016, LLR-097, LLR-136 | LLR-016's value is 2; LLR-097 is scoped to the backup side and says a restore's refusal reaches the console, which LLR-136 states. |
| R3O-047 | LLR-080 | Dims gain second_sample, declared_interval=range[1..3600] and the create cases. |
| R3O-048 | LLR-043, LLR-091, LLR-095, IF-039 | Rationales state what breaks, with no past defect; IF-039 says "the least-access requirement" with no id. |
| R3O-049 | CMP-004, CMP-008, CMP-002 | The three claims about today's code are corrected; the "today" sentences stay. |
| R3O-050 | B-01, B-16 | Both crossings carry links. |

## Consistency changes beyond the named rows

Made because a changed value or form also appeared elsewhere: CMP-006's notes (no record on a refused launch); IF-022 and IF-030 (behaviour out of the form, as R3S-022); IF-003's value-3 wording and LLR-043's (a check now returns 3); LLR-028 (run-state write after the new publication order); LLR-041 (failure handling for that order); LLR-018 (console only); LLR-107 (the console echo); LLR-112 (the global record never in a source); LLR-136 (the kit check and console refusals); LLR-143 (the short folder record and the age row); IF-015 (version 2 written before and after folder records). SR-040 is not edited: its value 4 ("a host fault while the restore works, such as ...") admits a state removed by a concurrent removal, which LLR-040 now classifies as 4.

## Not applied, or applied differently

- **R3S-027** is refuted and was not applied.
- **R3S-014 / R3O-002, one dimensions case.** The disposition gives a version-2-evidence state written after folder records existed, with its folder record missing, the value 1. Today's writer removes the folder record when it has no rows (the folder record is present only with rows, K15), and version-2 evidence states no row count, so for such a state a missing folder record cannot be told from a tree with no empty or attributed folder. Applying 1 would make every state written by the current release without such a folder restore with part failed, against SR-115 and SR-084. LLR-138 instead restores it complete with the folder record reported unverified; a folder record present but malformed is still 1. Proposed for the Owner as **P-12**: (a) as written here, unverified and complete; (b) 1, as the disposition says, accepting that today's states without empty or attributed folders restore part failed; (c) make today's writer always write the folder record, so (b) applies only to states written from then on. Rows affected: LLR-138, LLR-143, gap M81.
- **R3O-001, mechanism.** The disposition says the run holds a fresh owner record of the same identity in a fresh staging area before publication. The staging area has one fixed name, so a fresh one cannot exist while the old one is being published, and removing one owner record before creating the other leaves a window with no evidence. The design instead prepares the saved state in its own folder inside the staging area and publishes it by moving that folder out, so the one owner record stays in place, unchanged, until the collapse ends. The obligation the disposition states (the fence's evidence survives publication and lasts until the run-state write and the collapse end) is met.
- **R3O-012, the restored tree.** The disposition's example, "the restored tree to the restore side", is already true: IF-023 is owned by the restore kit (CMP-017), whose children produce it together; it stays there, and rows of entry restoration and tree finishing on it count as placed at an ancestor. IF-020 moved there for the same reason.
- **R3O-039, IF-044's consumers.** The guard's own reclaim uses the verdict, but the guard owns IF-044, and an interface does not list its owner as a consumer.
- **R3O-010, the dry run.** Unspecified until P-02 is ruled, as the disposition says.

## Counts after the fixes

- Components 24; interfaces 45 (41 boundary, 4 internal); LLRs 138 (110 top-level, 28 child), 10 added; legacy LLR ids kept 73.
- Placement: 64 placed, 11 placed at an ancestor, 63 unplaced, none misplaced.
- Design gaps 82 (M01 to M82; M61 to M82 new). SR-constrains pairs 19 (5 new: SR-065, SR-146 to IF-017; SR-150, SR-152, SR-146 to IF-018).
- Rows changed or added: 149 (17 CMP, 31 IF, 78 LLR changed and 10 added, 11 SR, 2 boundary crossings; the list below).

## Every row changed or added

This list scopes the convergence check. Generated by `r3-merged/_r3b_lint.py --changed`, comparing every carrier with git HEAD cell by cell.

### components.toml (17)
- CMP-002: changed: notes
- CMP-003: changed: notes
- CMP-004: changed: notes
- CMP-005: changed: notes
- CMP-006: changed: notes
- CMP-008: changed: notes
- CMP-009: changed: notes
- CMP-010: changed: notes
- CMP-011: changed: notes
- CMP-012: changed: notes
- CMP-013: changed: notes
- CMP-014: changed: notes
- CMP-017: changed: notes
- CMP-018: changed: notes
- CMP-019: changed: notes
- CMP-020: changed: notes
- CMP-022: changed: notes
### interfaces.toml (31)
- IF-002: changed: data
- IF-003: changed: data
- IF-004: changed: data
- IF-007: changed: consumers, data, requestors
- IF-009: changed: data, rationale
- IF-010: changed: data, version
- IF-011: changed: data
- IF-013: changed: data
- IF-014: changed: consumers, data
- IF-015: changed: data
- IF-017: changed: consumers
- IF-018: changed: data
- IF-019: changed: data, rationale, version
- IF-020: changed: data, owner, rationale
- IF-022: changed: data
- IF-023: changed: data
- IF-025: changed: consumers
- IF-026: changed: data, rationale
- IF-027: changed: data
- IF-029: changed: data, rationale, version
- IF-030: changed: consumers, data
- IF-031: changed: data
- IF-032: changed: consumers
- IF-033: changed: data
- IF-035: changed: requestors
- IF-038: changed: data
- IF-039: changed: rationale
- IF-041: changed: data
- IF-042: changed: data
- IF-044: changed: consumers, data
- IF-045: changed: rationale
### low-level-requirements.toml (88)
- LLR-003: changed: constrains
- LLR-005: changed: constrains, detail
- LLR-007: changed: constrains
- LLR-010: changed: detail
- LLR-011: changed: constrains, detail
- LLR-015: changed: detail, dimensions
- LLR-016: changed: detail
- LLR-017: changed: detail, dimensions
- LLR-018: changed: detail
- LLR-022: changed: detail
- LLR-025: changed: detail
- LLR-026: changed: constrains, detail, dimensions, rationale
- LLR-027: changed: detail
- LLR-028: changed: detail
- LLR-029: changed: detail
- LLR-035: changed: detail
- LLR-036: changed: constrains
- LLR-037: changed: detail
- LLR-039: changed: constrains
- LLR-040: changed: detail, dimensions
- LLR-041: changed: constrains, detail, dimensions, rationale
- LLR-042: changed: detail, dimensions
- LLR-043: changed: detail, dimensions, rationale
- LLR-045: changed: detail
- LLR-046: changed: constrains, detail, dimensions
- LLR-047: changed: constrains
- LLR-048: changed: detail, dimensions
- LLR-049: changed: constrains, detail, dimensions
- LLR-051: changed: constrains
- LLR-052: changed: detail
- LLR-053: changed: constrains
- LLR-058: changed: constrains
- LLR-059: changed: constrains
- LLR-061: changed: detail
- LLR-065: changed: constrains
- LLR-066: changed: detail
- LLR-067: changed: detail, dimensions
- LLR-068: changed: dimensions
- LLR-073: changed: detail
- LLR-074: changed: detail
- LLR-076: changed: detail
- LLR-080: changed: detail, dimensions
- LLR-086: changed: constrains, dimensions
- LLR-091: changed: detail, rationale
- LLR-095: changed: detail, dimensions, rationale
- LLR-097: changed: detail, dimensions
- LLR-099: changed: detail
- LLR-103: changed: detail, dimensions, rationale, sr_refs, title
- LLR-107: changed: detail
- LLR-109: changed: detail, dimensions, rationale, title
- LLR-110: changed: constrains, detail, dimensions, rationale
- LLR-111: changed: constrains, detail, dimensions
- LLR-112: changed: detail
- LLR-113: changed: constrains, detail
- LLR-114: changed: detail, dimensions
- LLR-115: changed: rationale
- LLR-116: changed: detail, rationale
- LLR-117: changed: detail, dimensions, parent, sr_refs
- LLR-122: changed: constrains
- LLR-123: changed: detail, dimensions
- LLR-124: changed: detail, dimensions
- LLR-125: changed: detail, dimensions, rationale
- LLR-126: changed: constrains
- LLR-127: changed: constrains
- LLR-128: changed: constrains
- LLR-129: changed: constrains
- LLR-130: changed: constrains, detail, dimensions, rationale
- LLR-131: changed: constrains
- LLR-133: changed: detail, dimensions, rationale
- LLR-135: changed: detail, dimensions, rationale
- LLR-136: changed: constrains, detail, dimensions
- LLR-138: changed: detail, dimensions, rationale
- LLR-141: changed: detail, dimensions
- LLR-142: changed: detail, dimensions
- LLR-143: changed: constrains, detail, dimensions
- LLR-144: changed: constrains, detail, dimensions, sr_refs
- LLR-149: changed: detail, rationale, title
- LLR-150: changed: constrains, detail, dimensions, rationale, title
- LLR-151: added
- LLR-152: added
- LLR-153: added
- LLR-154: added
- LLR-155: added
- LLR-156: added
- LLR-157: added
- LLR-158: added
- LLR-159: added
- LLR-160: added
### system-requirements.toml (11)
- SR-017: changed: acceptance_criteria, permutations
- SR-086: changed: requirement, title
- SR-106: changed: acceptance_criteria, permutations, rationale
- SR-109: changed: rationale
- SR-121: changed: acceptance_criteria, permutations, rationale, requirement
- SR-137: changed: acceptance_criteria, permutations, requirement
- SR-144: changed: acceptance_criteria, rationale, requirement, title
- SR-146: changed: acceptance_criteria, permutations, rationale, requirement, title
- SR-150: changed: hat_refs, rationale
- SR-151: changed: acceptance_criteria, hat_refs, permutations, rationale, requirement
- SR-152: changed: acceptance_criteria, permutations, requirement, sn_refs
### external.toml (2)
- B-01: changed: carries
- B-16: changed: carries
TOTAL 149

## Checks

`python validate_design.py ...\r3-merged`:

```
components=24 interfaces=45 (boundary=41, internal=4) llr=138 (top=110, child=28) legacy_kept=73
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

Every warning is an on-disk name in an interface's `data` (the agreed form); no warning is on an LLR or CMP row.

SR parse and reference resolution (`_r3b_lint.py`: every sn_refs, boundary_refs and da_refs id of every SR resolves; no SR cell names a file; dimension grammar of every LLR; no history token in an LLR rationale; no dangling LLR or IF reference; no curly quote):

```
tomllib: system-requirements, external, stakeholder-needs and assumptions parse
PROBLEMS 0
```
