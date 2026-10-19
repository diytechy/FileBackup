# Round 3: calls and review dispositions for the design tier

Input: two blind derivations (`r3-astra/`, GPT-6 Astra medium; `r3-opus/`,
Claude Opus medium) and their alignment (`r3-alignment.md`, `r3-alignment-map.json`,
Claude Opus medium). This run is unattended: Owner-level calls take the
recommended default and are listed under **Pending Owner rulings** below.
Flipping one is a row edit. Every row stays Drafted.

## Alignment calls (coordinator)

The aligner's 38 conflicts (K01–K38). Each takes the aligner's recommendation
unless the call says otherwise.

| K | Call |
|---|---|
| K01 | Astra: elapsed periods since the last completed full re-read (SR-011). **Superseded by the Owner's P-01 ruling (2026-10-18): calendar periods, as today's code.** The rest of K01 stands: judged against the last *completed* full re-read. |
| K02 | **Owner-level, default taken:** the configuration stays at version 2 (P-01). |
| K03 | SpaceView is a boolean, default false. |
| K04 | **Owner-level, default taken:** the removal dry run stays accepted in the removal request form and keeps working; no LLR states it, since no SR asks for it; it is listed under "code beyond the design" (P-02). It is never made a bad request until the Owner rules. **Superseded by the Owner's P-02 ruling (2026-10-18): specified as SR-153 / LLR-163.** |
| K05 | Full payload check by default (SR-049); the deep switch stays accepted with no meaning, like the old outcome switch. The check's cost rises (about 3 h at the reference host, inside SR-064's 8 h); recorded as P-03. **Superseded by the Owner's P-03 ruling (2026-10-18): today's two levels stay; SR-049 narrowed so altered content is a deep-check finding.** |
| K06 | Opus: no removal override switches in the request form; the module-level overrides are code beyond the design. |
| K07 | Opus: the hashing component is fetched without a question, attended or not (SR-132); the auto-install switch is accepted with no meaning. |
| K08 | **Owner-level, default taken:** Opus: a volume whose free space cannot be measured is not refused; the run's record says the space check was not made (P-04). **Superseded for the backup by the Owner's P-04 ruling (2026-10-18): shares are measured, and a backup volume still unmeasurable is refused with 2. The restore keeps K08 (LLR-023).** |
| K09 | Astra's declared allowance numbers; round 4 checks them against the harvested test edges. |
| K10 | Astra: the space plan is read-only and runs before any root, claim, log, record or staging is created, then is revalidated under the claim. |
| K11 | **Owner-level, default taken:** Opus: a missing or unreadable run-state record with a populated backup is rebuilt (completion time from the latest evidence's written time, a full re-read due) and the rebuild is reported (P-05). **Confirmed by the Owner's P-05 ruling (a), 2026-10-18.** |
| K12 | Opus: reconcile per path against the backup's latest record; the backup wins. |
| K13 | **Owner-level, default taken, with a coordinator design call.** The record's path separator is the backslash on every host. Design call: the reader of a record written by a supported version treats '/' and '\' alike, and change detection compares normalised paths, so a Linux-written store does **not** take a spurious full rewrite and extra saved state; its records turn to the backslash with the first run that has a real change. A source name holding a literal '\' on Linux is handled by the non-portable-name rule (SR-114/SR-136). The format change itself is a downstream-visible migration (P-06). **Accepted by the Owner's P-06 ruling (2026-10-18).** |
| K14 | Coordinator design call: the state's own completeness-evidence version 3 (Opus, with DirRows/LinkRows) settles folder and link records with no new file. For a state with no evidence at all, age is told by the state's kit revision, and the kit refresh preserves it: the first refresh of a state records the revision it replaced as the state's original revision, written once and never changed. Astra's per-state format descriptor is not adopted. The release that introduced evidence is read from history at build time (design gap). |
| K15 | Opus plus evidence DirRows=0: the folder record is present only with rows. |
| K16 | Opus: comma attribute separator (today's form; a semicolon breaks shipped kits). |
| K17 | Opus: the link record form, a separate file present only with rows; classes inside-source and own-location. |
| K18 | Astra: 60 s per remote resolution or enumeration request. |
| K19 | Astra: flush the temporary to stable storage before the rename (SR-082). |
| K20 | Opus's write order; Astra's concern kept as its own LLR: earlier content stays reachable until the replacing state is published. |
| K21 | Fence before every destructive step (move, delete, replace, publish); creation at a fresh temporary name needs no fence. |
| K22 | Middle course: readers take no claim and leave no artifact; a reader that finds a location vanished re-resolves by content key, and one whose record's evidence changed mid-read re-reads it, a bounded number of times. |
| K23 | Union: the source is the installed program's kit; per-file temporary plus rename, never deleting; the revision marker files are written last. |
| K24 | Astra's formula (today's code). |
| K25 | Astra's exact truthy set (the shipped entry script's). |
| K26 | Opus: /tmp declared as a non-persistent scratch mount in the container's mount form; reviewers check SR-130's wording admits it. |
| K27 | Opus: a refused configuration never creates or truncates a log; the refusal line is appended to an existing global record. |
| K28 | Keep LLR-077 as a child of LLR-056: a stored item's protection never blocks verification or the time stamp, and is not handed to the restored file. |
| K29 | Opus: flat restore rows, each carrying its own SR. |
| K30 | Astra: the already-compressed type list is enumerated once, in LLR-004; the manual's table is checked against it. |
| K31 | Opus: the media rate is measured for each file whose content the run reads. |
| K32 | A restore tool present but failing its self-test at admission returns 2. |
| K33 | Astra: write a stored object at a private temporary, verify its content key, publish without replacing a claimed object. |
| K34 | **Owner-level, default taken:** SR-072's double-click holds for a kit opened from the backup's own volume. A kit carried to a Mac inside a zip is outside the support boundary; the manual gives the one-line remedy (P-07). **Confirmed by the Owner's P-07 ruling (2026-10-18), with a kit readme added.** |
| K35 | Keep the same-volume rule for the listing location only if the browse view's relative links need it, with that reason in the LLR; otherwise drop it. |
| K36 | Opus: on-disk names live in the interface form; LLRs refer to them by role. |
| K37 | Astra: a difference in the folder or link record is a change and keeps a saved state (SR-005). |
| K38 | Opus's component tree, as the aligner proposed it. |

The two Astra-only forms the aligner held back (the per-state format
descriptor and the reader pin) are not adopted, by K14 and K22.

## Pending Owner rulings

Each is written to the default. Flipping one is a row edit.

| # | Question | Options | Default taken | Rows affected |
|---|---|---|---|---|
| P-01 | Does a version-2 configuration's D/W/M/Y re-read schedule mean calendar buckets (today's code) or elapsed periods (SR-011)? | (a) elapsed periods, still version 2; (b) calendar buckets are v2's meaning, so SR-011 forces version 3 and both meanings are kept; (c), added 2026-10-18: calendar buckets, SR-011 rewritten to match, no code or config change | **Ruled (c)** by the Owner, 2026-10-18: calendar periods as today's code; SR-011 and LLR-011 rewritten; the configuration stays at version 2 | SR-011, LLR-011, gap M07 |
| P-02 | The removal dry run (`-WhatIf`, and the container's dry-run flag) has no need behind it. Keep it or retire it? | (a) add a need, then a dry-run LLR; (b) retire it with a release note; (c) keep it working, unspecified, until ruled | **Ruled (a)** by the Owner, 2026-10-18: SN-046 widened (preview whether a removal would be refused), SR-153 and LLR-163 pin today's behaviour | SN-046, SR-153, LLR-163, IF-002 |
| P-03 | The check reads every stored object by default (SR-049), about 3 h at the reference host. Accept the heavier routine check? | (a) accept; (b) narrow SR-049 to report altered content only on a deep check | **Ruled (b)** by the Owner, 2026-10-18: the plain check tests presence and form, -Deep proves content, as today's code | SR-049, LLR-049, LLR-149, IF-002, IF-010, CMP-014 note, gap M30 |
| P-04 | A volume whose free space cannot be measured: refuse (2) or proceed and record that the check was not made? | (a) proceed and record; (b) refuse with 2; (c), added 2026-10-18: measure shares by their network name first (today every UNC path is unmeasurable) | **Ruled (c) then (b)** by the Owner, 2026-10-18: shares are measured; a backup volume still unmeasurable is refused with 2. Restore unchanged (not refused) | SR-052, LLR-052, gap M96 |
| P-05 | Does the "re-derive and report" ruling for missing change-detection state also cover the run-state record (last completion, last full re-read)? Today the run is refused with 1. | (a) yes, rebuild and report; (b) no, refuse | **Ruled (a)** by the Owner, 2026-10-18: rebuild and report; refused (3) where the evidence itself is missing or mismatched | LLR-035 |
| P-06 | The record's path separator becomes the backslash on every host. Linux-written stores change form at their next real change (no spurious saved state). Accept the format migration? | (a) accept; (b) keep the host's separator and have every reader accept both | **Ruled (a)** by the Owner, 2026-10-18 | the record-format interface, LLR-121, gap list |
| P-07 | Does SR-072's macOS double-click cover a kit carried to the Mac inside a zip (which strips the executable bit)? | (a) no: supported from the backup's own volume, the manual gives the remedy; (b) yes: the kit's form must survive zip transfer | **Ruled (a)** by the Owner, 2026-10-18, plus a kit readme (RECONSTRUCT-README.txt) naming the remedy, since Finder's refusal dialog points nowhere | SR-072, LLR-074, IF-019, gap M53 |

## Review dispositions, full round 1

Inputs: `r3-review-sol/` (Codex gpt-6.1-sol, high: 9 BLOCKER, 17 MAJOR,
3 MINOR) and `r3-review-opus/` (Claude Opus, medium: 3 BLOCKER, 21 MAJOR,
26 MINOR), both of the merged tier at `f4fc923` and of open item 1's SR
edits. Neither saw `docs/plans/` or the other's review. The Sol prompt's
output-path placeholder rendered empty; Sol wrote into its working folder,
which is the right one, so nothing was lost. Findings are claims: each is
**confirmed** unless marked otherwise, and the fix is the reviewer's
suggested fix as adjusted here. Pairs found by both reviewers are listed
together.

| Finding | Rows | Disposition and fix |
|---|---|---|
| R3S-001 | SR-137, SR-150, LLR-109 | Confirmed. SR-137's follow predicate excludes a folder that is an ancestor of the link in the walk; LLR-109's classes become mutually exclusive, and the ancestor-in-a-followed-folder case stays explicit in acceptance. |
| R3S-002 + R3O-030 | IF-018, LLR-110, LLR-144 | Confirmed. IF-018's inside-source `Target` is the target's path in the walk (under the source root, through followed links), so an ancestor reached through a followed outside link has a captured path; LLR-110 and LLR-144 gain that class, and LLR-144 re-points it under the restore target. |
| R3S-003 | LLR-141, LLR-144, SR-121 | Confirmed. The containment check applies to a link's own place (always under the target) and to an inside-source target re-pointed under the target; an own-location link pointing to its original path is not refused. |
| R3S-004 | LLR-150, LLR-005, IF-013 | Confirmed. The sequence must never leave unpublished staging as the only copy a visible state needs: the saved state is published, indexed and kit-complete while the content it receives is still resolvable from the root, and content then moves between published locations. Crash cases include an older state that borrows the content. |
| R3S-005 + R3O-015 | LLR-052, LLR-091 | Confirmed. The pre-claim plan reads only published records, as a reader does (no claim), and changes nothing; it may refuse, since a refusal changes nothing. The binding plan is re-checked under the claim. LLR-091 is scoped to decisions that change the store. "Reads and writes nothing" becomes "changes nothing". |
| R3S-006 | LLR-125, SR-144 | Confirmed. Every store mutation after the claim could have been lost is fenced, fresh temporaries included, at one owner-record check per object (a stat, small next to writing the object). The residual window between a check and its write is at most one unpublished temporary, which changes no file the successor wrote or published and is reclaimable. SR-144's requirement is aligned with its acceptance (P-09). |
| R3S-007 + R3O-005 | SR-017, LLR-017, IF-044, LLR-080 | Confirmed. An owner record readable and fresh, or readable but not proven dead, is live or unproven (4 as sole finding). An owner record still unreadable after the bounded re-reads is evidence that cannot be read (2): a retry will not fix it, and a host retrying forever is the failure. SR-017's acceptance, LLR-017 and IF-044 say so, mapping each listing and record state to its verdict. |
| R3S-008 | LLR-042, LLR-095, SR-018 | **Confirmed; overrules K27.** SR-018 says no log is created or changed. A refused configuration reports on the console only and changes no log; the host sees 2 and alerts. |
| R3S-009 + R3O-021 | LLR-026, LLR-003 | Confirmed. The collapse rewrites the record of a folder whose entry it blanks because that copy is redundant, and of a folder whose references vanished; it rewrites no other folder. "Neither read" becomes "not rewritten". Reference changes are published before the redundant bytes go. |
| R3S-010 | IF-022, IF-023, LLR-010, LLR-142 | Confirmed. The restore report never takes the path of a captured file: where the state records a file at the report's name, the report takes the next free suffixed name (stated in IF-022's form), and destination planning includes generated restore artifacts. |
| R3S-011 | LLR-123, SR-106, SR-045 | Confirmed as an SR gap (P-10). A restore of the state a concurrent removal deletes cannot complete. Default: SR-106 holds for every state the concurrent operation does not remove. A restore of the state being removed completes, or ends with 4 (retry later) naming the concurrent removal; files already written are byte-exact, and it never restores wrongly. LLR-123 gains the last-copy case. |
| R3S-012 + R3O-018 | LLR-133, SR-098 | Confirmed. A file of the latest state with no rate on record is measured, unchanged files included. To keep SR-113's run budget, the measuring of unchanged files is bounded per run and catches up over runs; the view shows a not-yet-measured file as such. Dimensions gain file_state. |
| R3S-013 + R3O-016 | LLR-135, IF-031 | Confirmed. A path's volume is the one at the longest mount point that prefixes the resolved path (drive roots and folder mount points on Windows, the mount table on Linux), identified by a stable volume identity declared in IF-031's form. Dimensions gain the folder-mount and alias cases. |
| R3S-014 + R3O-002 | LLR-138, IF-015, SR-116, SR-146 | Confirmed. Folder-record age is decided by kit revision (the state's original revision, K14) below the revision that first wrote folder records. Evidence version is the age test for link records only, and for row counts. A dimensions case covers a version-2-evidence state written with folder records whose folder record is missing (1). The introducing revision is read from history at build time (gap). |
| R3S-015 | LLR-130, IF-019, SR-110 | Confirmed. Every kit file carries the kit revision. The restore checks the kit is one revision before admission, and a mixture is refused with 3, naming a re-run of the refresh, which completes it. Dimensions gain an interruption between artifacts. |
| R3S-016 | IF-033, LLR-080 | Confirmed: state the schema number, the Kind vocabulary and the required fields per version. |
| R3S-017 | IF-044, LLR-088 | Confirmed: the staging area's own modification time, age and read status join the request form; ownerless-empty and temporary-only cases go into dimensions. |
| R3S-018 + R3O-038 | IF-019, LLR-007, LLR-022, IF-011, IF-041 | Confirmed: IF-019 enumerates the kit's closed artifact name set; LLR-022 uses that one list. IF-011 states the TLS mode (today STARTTLS). IF-041 states the row threshold. |
| R3S-019 | IF-004, IF-011, LLR-015, LLR-042 | Confirmed: the catalogue states which notification fields are required together, the port's default (today's code value) and its admitted range; LLR-015's eligibility uses the same set. |
| R3S-020 | IF-002, IF-009, LLR-103, LLR-112 | Confirmed: the global record path (from the request or the environment) is admitted like every other writable location before it is opened: no source overlap, no collision with store data. |
| R3S-021 + R3O-009 | IF-027, LLR-073 | Confirmed: a child of LLR-073 constrains IF-027: provider order per system, the picker variable's precedence, and cancel, failure, empty or relative answer each give no target (2). |
| R3S-022 | IF-009, IF-011, IF-015, IF-038, IF-041 | Confirmed: behaviour moves out of these forms into the LLRs that constrain them. |
| R3S-023 | LLR-043, LLR-040, LLR-017 | Confirmed: coexisting causes become separate booleans, with the 2/3/4 precedence combinations explicit. |
| R3S-024 | LLR-086, LLR-068 | Confirmed: below/at/above for 256 KiB and for 10 %; form detection models signature, length relation and hash match. |
| R3S-025 + R3O-008 | LLR-109, LLR-149, SR-137, SR-090 | Confirmed. Link resolution waits share the location's declared wait budget (SR-090's, 60 s per location); once it is spent, further unreachable links are named without waiting. SR-137's acceptance gives the bound's unit and per-location scope. Dimensions gain link_count. |
| R3S-026 | LLR-109, LLR-149 | Confirmed: split into children, one decision each (routing, file links, waiting, preservation of earlier content, outcome; passes, index, memory and concurrency, progress), or link to the rows that already own a decision. |
| R3S-027 | 23 LLRs | **Refuted.** `@full` is in the kit's grammar (gen_cases accepts `@full`, `@pairwise`, `@boundaries`), and the SR tier uses it. |
| R3S-028 + R3O-033 | LLR-025, IF-014, LLR-066 | Confirmed: the text is opaque to the backup side only, and the restore interprets it. IF-014 states the exact time grammar, and that a reader accepts LF or CRLF. |
| R3S-029 | LLR-115 | Confirmed: state the findability and read-only-source consequences, not the ruling. |
| R3O-001 | LLR-125, LLR-028, LLR-026 | Confirmed. The fence's evidence survives publication: before the saved state is published, the run holds an owner record of the same run identity in a fresh staging area, and keeps it until the run-state write and the collapse end. LLR-125's dimensions gain the post-publication steps. |
| R3O-003 | LLR-046, LLR-127 | Confirmed: a removal is refused by a staging area holding anything other than this request's own removal marker. |
| R3O-004 | SR-086 | Confirmed: the requirement states the refusal and that the backup is treated as held for safety, and leaves the value to the acceptance (4 where the cause clears by itself, 2 where a person must act). Retitled to match. |
| R3O-006 | SR-017, LLR-124, LLR-080 | Confirmed. Each case gets its value: a move-aside or create failure from an I/O fault is 4, and from access denial 2. An owner record found already present at the run's first touch is another holder (4). A failed delete of reclaimable leftovers that hold no content keeps them and the run completes (0), naming them with guidance. |
| R3O-007 | SR-121 | Confirmed: the acceptance gains an inside-source link re-pointed out of the target (not created, named, 3), and the permutations gain entry=set{file,link}. |
| R3O-010 | IF-002, IF-038, IF-020, IF-007 | Confirmed except the dry run, which stays unspecified until P-02. Children of LLR-073 and LLR-010 state the no-GUI switch and variable, --pick-target, the root overrides (used only where the recorded root is unusable) and --from. |
| R3O-011 | IF-007, CMP-004, CMP-022 | Confirmed: the restore-side variables move into the restore session interface (IF-026), owned on the restore side. IF-007 keeps the backup side and lists its consumers. |
| R3O-012 | components, interfaces | Confirmed in part. Unplaced rows are allowed (pointer rules: counted, not refused), but rows placed in the wrong component are not. Re-point interface owners to their producers (e.g. the restored tree to the restore side). A component that produces no interface keeps its rows unplaced, and its notes say so. Do not mint interfaces only to place rows. merge-notes gains a placement table. |
| R3O-013 | LLR-049, IF-010 | Confirmed. A record failing its completeness evidence is a check finding of its own class (RecordEvidenceMismatch) with outcome 3, as for a restore and a removal, and the check continues with the other states. Precedence: 2 over 3 over 1. |
| R3O-014 | SR-146, LLR-143, LLR-040 | Confirmed: SR-146 extends to the link record. A current-form state whose link record is missing, malformed or short of its stated rows restores every file, names the links not rebuilt and ends with 1. |
| R3O-017 | LLR-103 | Confirmed: the same-volume rule for the listing traces to SR-062 (the browse view's relative links cannot cross volumes on Windows); its rationale says so. |
| R3O-019 | LLR-027, IF-008 | Confirmed: the helper clause is Windows-only. The container's route to a valid document is the example configuration and the published description. |
| R3O-020 | LLR-074, LLR-073 | Confirmed: the macOS launcher passes --pick-target and the restore makes the choice. |
| R3O-022 | LLR-117 | Confirmed: top-level, sr_refs SR-082 and SR-059. |
| R3O-023 | IF-029, LLR-114 | Confirmed; Owner-level (P-08). Default: the change-detection record and its evidence take a name no other artifact uses, and the old name is read once for migration. |
| R3O-024 | IF-009, LLR-097 | Confirmed: a closed token set, one per refusal cause plus [2/staging-busy], and message kinds for every entry the LLRs require. |
| R3O-025 | SR-150, SR-151 | Confirmed: no PERFORMANCE hat; SN-001's acceptance already states both obligations. |
| R3O-026 | SR-151 | Confirmed. |
| R3O-027 | SR-152, SR-121 | Confirmed. |
| R3O-028 | SR-109 | Confirmed: drop "more than one candidate answer". |
| R3O-029 | SR-151, LLR-109, IF-018 | Confirmed: the listing location is one of the system's own locations (it holds the views); recorded under P-11 because it widens the Owner's link ruling's list. |
| R3O-031..R3O-048 | as listed | Confirmed, as suggested. Notes: R3O-036, `-BackupTime` is listed in IF-002 as a test seam that sets the run's clock. R3O-037, a non-empty value outside the truthy and falsy sets is a bad request, and the falsy set is stated. R3O-040, keep IF-045 as the routes' parity form and say so. |
| R3O-049 | CMP-004, CMP-008, CMP-002 | Confirmed in part: the three claims are corrected. The "today" notes stay, since the brief asks for them. |
| R3O-050 | external.toml B-16, B-01 | Confirmed: a frame clarity edit; both crossings carry links. |

### Pending Owner rulings added by the review

| # | Question | Options | Default taken | Rows affected |
|---|---|---|---|---|
| P-08 | The change-detection record at a source root shares its name with a backup's own record, so a source whose root holds such a file (a copied store) has it overwritten. | (a) give the record a name no other artifact uses, reading the old name once; (b) keep the name and refuse a source root holding a backup's record; (c) keep today's behaviour | **Ruled (a)** by the Owner, 2026-10-18, named `MANIFEST.fb.src.csv`. Renaming the backup's own record as well (`MANIFEST.fb.bkp.csv`) was considered and declined: nothing of the owner's shares that folder (stored objects are named by hash), and every existing kit reads `MANIFEST.csv` | IF-029, LLR-114, LLR-001, gap M65 |
| P-09 | SR-144 says a resumed former owner "changes nothing further", but no fence can close the window between its check and its next write. Align the requirement with its acceptance (it changes no file the successor wrote or published, publishes nothing, and at most leaves one reclaimable temporary)? | (a) align; (b) keep the absolute and require a mechanism with no window | **Ruled (a)** by the Owner, 2026-10-18: store-scoped, the change-detection state and the views outside the guarantee (per-run names for them declined) | SR-144, LLR-125 |
| P-10 | A restore of the very state a concurrent removal deletes cannot complete. | (a) SR-106 holds for every state the concurrent operation does not remove; that one restore ends 4, naming the removal, never wrong; (b) a removal waits for readers (needs reader-visible state, which the shell route cannot keep) | **Ruled (a)** by the Owner, 2026-10-18, as widened (a kit refresh or a record publication outlasting the wait also ends 4) | SR-106, LLR-123 |
| P-11 | The Owner's link ruling lists the backup, saved states, change-detection state and logs as the system's own locations. Add the listing location (the views)? | (a) add it; (b) leave it out, so a link into the views is followed | **Ruled (a)** by the Owner, 2026-10-18: the listing location is one of the system's own locations | SR-151, LLR-109, IF-018 |

| P-12 | A state with version-2 evidence (no row counts), written after folder records existed, has no folder record. Today's writer omits the folder record when it has no rows, so its absence cannot be told from a tree with no empty or attributed folder. | (a) restore complete (0), the folder record reported unverified; a present but malformed folder record is still 1; (b) 1, accepting that today's states without empty or attributed folders restore part failed; (c) as (a), and the writer always writes the folder record from now on, so evidence v3's DirRows settles it for new states | **Ruled (a)** by the Owner, 2026-10-18: complete, the folder record reported unverified ((c) adds nothing: evidence from version 3 states the row count) | LLR-138, LLR-143, gap M81 |

**Builder deviations accepted** (detail in `r3b-change-log.md`). R3S-014's
one dimensions case is written to P-12 (a), not to 1, for the reason above.
R3O-001's mechanism: the saved state is prepared in its own folder inside the
staging area and published by moving it out, so the one owner record stays in
place until the collapse ends. That meets the disposition's obligation without
a moment with no owner record. Under R3O-012, 28 LLRs lost a `constrains`
cell that placed them wrongly, so they show as unplaced (allowed). New names
the builder chose, for the reviewers to check: the change-detection record
`FILEBACKUP-CHANGES.csv` (P-08; the Owner later chose `MANIFEST.fb.src.csv`), kit revision 14 with a revision line in every
kit file (R3S-015), and IF-010 version 2.

The fixes are applied by an Opus builder (`r3b-change-log.md`). Then a fresh
convergence check (Codex Sol, high, a new session) reviews only the changed
rows. This is full round 1 of at most 3.

## Convergence check 1 and full round 2

Input: `r3c-convergence-sol/` (Codex gpt-6.1-sol, high, a fresh session that
saw no earlier verdicts), scoped to the 149 rows changed at `45aca03`:
2 BLOCKER, 6 MAJOR, 0 MINOR. The tier has not converged, so this is full
round 2 of at most 3. All eight findings are **confirmed**.

| Finding | Rows | Disposition and fix |
|---|---|---|
| R3C-001 | LLR-109, LLR-115, IF-004, IF-018, LLR-144 | Confirmed. Where the change-detection state sits at the source root (the default), only the change-detection record and its temporaries are system-owned; the source-root folder is not an own location. A link to another folder of the source stays inside-source and is re-pointed under the target. The subtree rule applies only to a separately configured state location. |
| R3C-002 | SR-144, LLR-125 | Confirmed. **Coordinator design call:** a separate owner-record check before each mutation always leaves a window, so the fence becomes the filesystem's own. Each run works in a staging folder unique to its run identity, one on each volume it changes, under the claim. Every store mutation is a rename whose source or destination lies in that folder: a publication renames out of it, and a delete renames the object into it before the folder is purged. A successor's reclaim moves the former owner's run folder aside, so any rename the resumed run then issues fails by itself, with no check to race. The owner-record re-read stays as the early exit. The one residual is a write through a handle the run already held open, which lands in the moved-aside leftovers, never in a file the successor wrote or published. That is why P-09 (a) still stands. A build gap records the staging layout change. |
| R3C-003 | SR-086, LLR-122, LLR-091, LLR-095, IF-013 | Confirmed: a refused claim leaves the store byte-identical. The refusal goes to the console and to the admitted global record, never to a log inside the store. |
| R3C-004 | SR-106, LLR-123, LLR-130, LLR-159 | Confirmed. A restore that finds a mixed kit while a kit refresh holds the backup waits, bounded (as LLR-123 re-reads a changed record), and re-checks; past the bound it ends with 4, naming the refresh. A mixed kit with no live holder is an interrupted refresh, refused with 3 (LLR-159). P-10 is widened to cover this case. |
| R3C-005 | LLR-150, IF-033, LLR-017, LLR-124 | Confirmed. A prepared, unpublished saved-state folder is positively recognised: it holds no stored object, and its record and evidence match the published latest state. Once its owner is proven dead it is reclaimable as holding no content. Any other folder in staging still refuses. |
| R3C-006 | IF-022, IF-023, LLR-010, LLR-142, LLR-143, LLR-144 | Confirmed: the report takes the first name free, under the target's comparison rules, across recorded files, folders and links, and the parent folders they need. IF-022 and the restore rows use that one rule. |
| R3C-007 | IF-019, LLR-131, LLR-138, LLR-159 | Confirmed: the kit-origin artifact carries no current revision and is excluded from LLR-159's revision equality. |
| R3C-008 | LLR-073, LLR-157, SR-073 | Confirmed: SR-073 stands. The shell route asks for the target by typed prompt in an interactive console with no desktop, and refuses (2) only in an unattended session. If today's shell route does not, that is a gap. |

P-10 is widened: (a) also covers a restore that meets a live kit refresh
outlasting its bounded wait (4, naming the refresh).

Applied by an Opus builder (`r3d-change-log.md`), then checked by a fresh
convergence reviewer (Codex Sol, high, a new session), scoped to the rows
round 2 changes.

**Builder deviations accepted** (detail in `r3d-change-log.md`):
- There is one run folder per root, not one per volume. It covers every
  volume and keeps each rename inside one root.
- A restore that cannot test the claim (stock macOS has no lock tool for the
  shell route) treats a still-mixed kit as an interrupted refresh (3), not 4,
  so a host never retries forever. The convergence check is asked to look at
  this.
- A restorer replaced during the bounded wait ends with 4, under P-10 as
  widened.
- Superseded content is copied into the saved state, then the original is
  deleted through the run folder, even on one volume. This becomes P-13.

| # | Question | Options | Default taken | Rows affected |
|---|---|---|---|---|
| P-13 | Moving superseded or removed content into a saved state by a direct rename would be a mutation outside the run folder, so a resumed former owner could still make it. Copying it and then deleting the original through the run folder keeps it fenced, at the cost of reading and writing that content once more. A large edited file then pays a full copy where it used to be a rename. | (a) copy, then delete through the run folder: fenced; (b) direct rename: today's cost, with one unfenced mutation kind | **Ruled (b)** by the Owner, 2026-10-18: direct rename on one volume (a copy between volumes, as today); two hosts or containers writing one backup is unsupported (DA-03), so the copy's recurring cost buys nothing a supported setup needs | LLR-150, LLR-161, LLR-162 (S18 to S20), LLR-125, LLR-052, SR-144, DA-03 |

P-09 is widened (and amended again in full round 3): the fence covers the store (records, saved states, stored
content). The store's own log, the change-detection state and the views are
guarded only by the early exit. They are re-derivable, and no saved content
depends on them. Default: SR-144's acceptance is scoped to the store. The
other option is to give those artifacts per-run names.

## Convergence check 2 and full round 3 (the last)

Input: `r3e-convergence-sol/` (Codex gpt-6.1-sol, high, a fresh session),
scoped to the 44 rows changed at `be982ca`: 1 BLOCKER, 5 MAJOR, 0 MINOR. All
six are **confirmed**. This is full round 3 of 3. After its fixes, one final
convergence check runs, and whatever it finds is adjudicated and recorded for
the next session, not fixed in this run.

| Finding | Rows | Disposition and fix |
|---|---|---|
| R3E-001 | LLR-125, LLR-161, SR-144, IF-009, IF-013 | Confirmed. The store's own location record is inside the store, so it comes inside the fence: each run writes its entries to a per-run record inside its run folder, published by rename at the end of the run (IF-009 and IF-013 state the per-run name pattern; a killed run's record stays readable among its moved-aside leftovers). The change-detection state and the views are outside the store. They are derived, and the next run reconciles them from the backup's own record, so SR-144's acceptance names them as outside its guarantee. This is P-09 (a) as widened; the other option, per-run names for them too, was declined by the Owner's P-09 ruling (2026-10-18). |
| R3E-002 | LLR-080, LLR-088, LLR-161, IF-044 | Confirmed. An owner record that is present but carries no usable run identity (torn at creation), beside empty run folders, is the harmless case once its death is proven by stale age and the confirming sample. A non-empty or unrecognised folder still refuses. |
| R3E-003 | IF-033, LLR-088, LLR-150, LLR-038 | Confirmed. LLR-038 stands: the writer generates the prepared saved state's evidence for its own staged record. A prepared folder is recognised by record bytes identical to the published latest record, plus evidence that is valid and matches that record. Evidence bytes are not compared. |
| R3E-004 | LLR-159, LLR-130, LLR-040 | Confirmed; **reverses the round-2 deviation.** A claim that cannot be tested is indeterminate, so a still-mixed kit then ends with 4, naming the refresh and the remedy (re-run it if none is running). Only positive evidence that no refresh holds the claim gives 3. No tool is added to the shell floor. |
| R3E-005 | LLR-123, LLR-118, LLR-039, SR-106 | Confirmed. A reader that finds a record and its evidence disagreeing re-reads until the pair is stable or a declared bound passes (60 s). A pair settling to a match is read normally. A mismatch that outlasts the bound while a writer holds the backup, or while the claim cannot be tested, ends with 4. A mismatch with positive evidence that no writer holds it is damage (3). P-10 is widened to cover this case. |
| R3E-006 | LLR-157, LLR-073, SR-073 | Confirmed: LLR-157 meets SR-073. On a desktop, the shell route offers the folder choice through the dialog providers (IF-027). With no provider available, it asks by typed prompt in an interactive console, otherwise usage and 2, naming the missing provider. On a console with no desktop it uses the typed prompt. An unattended session is refused (2). |

**Builder deviations accepted, full round 3** (detail in `r3f-change-log.md`):
- Only the in-progress location record has a per-run name. The published
  record keeps the fixed name, replaced at the end of each run, so there is
  still one record per location. During a run, the fixed name shows the
  previous run's record (gap M89).
- A reclaim keeps the killed run's record, so it leaves one small
  moved-aside folder.
- The 60 s settle covers every evidence fault.
- The check's 4 is a "not checked" entry.
- The no-provider fallback to a typed prompt applies on both restore routes,
  for parity.

## Final convergence check (three full rounds spent)

Input: `r3g-convergence-sol/` (Codex gpt-6.1-sol, high, a fresh session),
scoped to the 28 rows changed at `aa42eb8`: 1 BLOCKER, 2 MAJOR, 1 MINOR. Three
full rounds are spent, so by the run's rules these are **adjudicated and
recorded here, not fixed**. They are the first work of the next session,
before round 4.

| Finding | Rows | Disposition (open) |
|---|---|---|
| R3G-003 (BLOCKER) | LLR-039, LLR-040, LLR-123, LLR-130, LLR-159, SR-039, SR-082, SR-106, SR-110 | Confirmed, as P-14. It is the same conflict the round-3 builder surfaced. Where the claim cannot be tested (the stock macOS shell route), an unsettled record pair or a mixed kit gets 4 under the LLRs, but 3 under SR-039, SR-082 and SR-110. LLR-039's strict-evidence clause also conflicts with its wait. The recommended fix is P-14 (c). |
| R3G-001 (MAJOR) | LLR-150, LLR-088, IF-044, SR-075 | Confirmed. A kill while the prepared saved-state folder is still being filled leaves partial copies that the classifier counts as content, so recovery is refused for good. Fix: a prepared folder holding only entries of its closed set (record copy or its temporary, evidence or its temporary, kit files) and no stored object is reclaimable once its owner is proven dead, whatever its completeness. Unknown entries still refuse. |
| R3G-002 (MAJOR) | LLR-125, LLR-161, LLR-088, IF-044, SR-075 | Confirmed. A kill between renaming the owner record into the run folder and purging it leaves an ownerless run folder that the classifier counts as content. Fix: the owner-record deletion entry is recognised as disposable in the ownerless case, or the owner record is deleted last, after the run folder is purged. |
| R3G-004 (MINOR) | IF-009, IF-044 | Confirmed. Publication timing (IF-009) and verdict mapping (IF-044) move out of the forms into LLR-161, LLR-017, LLR-080 and LLR-088. |

**Coordinator recommendation for the next session.** R3G-001 and R3G-002
are the same kind of finding as R3C-005 and R3E-002: a kill point in the
staging sequence whose leftovers have no recognised shape. Rather than fix
them one at a time, write one child LLR under LLR-088 that enumerates every
step of the backup's staging sequence (create the run folders, the owner
record, preparation, each publication, each deletion, the purge, the final
owner delete). For each step it gives the leftover shape a kill there leaves
and the verdict, closed over the steps. Then run one bounded convergence
check on it. Round 4 turns that table into test cases directly.

| # | Question | Options | Written as | Recommended | Rows affected |
|---|---|---|---|---|---|
| P-14 | Where a restore cannot test the claim (stock macOS shell route, no lock tool), what does an unsettled record pair or a mixed kit report after the 60 s settle? | (a) 4, and SR-039, SR-082 and SR-110 admit 4 where the claim cannot be tested; (b) the macOS shell floor gains a lock-testing tool; (c) the owner record is the no-writer signal any reader can check without a lock: no owner record, or a stale one confirmed by the second sample, means no writer, so 3; a fresh one gives 4 | (a), in effect: the LLRs give 4, and the SRs are not yet qualified | (c): a design call that needs no Owner ruling unless (a) is wanted | LLR-039, LLR-040, LLR-123, LLR-130, LLR-159; SR-039, SR-082, SR-110 |

Also open from the round-3 builder: SR-144's requirement text still says
"change no file its successor wrote or published", which is wider than its
store-only acceptance. Adding "in the store" matches P-09 (a). And at build
time, confirm per filesystem that a reclaim can move aside a folder holding a
file open on another host (it fails toward refusal).

## Closing the design tier (session 2026-10-18 c, the Owner present)

The Owner was present for this session, so the open behaviour calls went to
the Owner one at a time, as multiple choice with a recommendation.

**Why P-14 (c) was not taken.** The handoff recommended (c), the owner record
as the no-writer signal. Reading LLR-080 and LLR-094 showed that only a backup
writes an owner record; a repair and a kit refresh hold only the operating-system
claim. Under (c), a shell restore on a stock Mac that meets a live kit
refresh's mixed kit, or a live repair's half-published record, would find no
owner record and report damage (3) for a store that is only busy. Widening (c)
to every changing operation would add owner records, and their kill points, to
two more operations.

| # | Question | Ruling (Owner, 2026-10-18) | Rows |
|---|---|---|---|
| P-14 | Where a restore cannot test the claim (the stock macOS shell route), what does a record still disagreeing with its evidence, or a kit still of two revisions, report after the 60 s wait? | **(a)** retry later (4), the message naming the remedy and stating that, where no changing operation is running, the record is damaged (or the kit is an interrupted refresh's). SR-039, SR-082 and SR-110 admit 4 on such a route. | SR-039, SR-082, SR-110, LLR-039, LLR-123 |
| P-15 | **New, found while enumerating the staging sequence.** The latest state's folder record and link record are published as separate files beside the record and its evidence; no row orders those publications, and the evidence binds those two files by row count only. A kill between them, or a reader during a backup, can pair one run's files with another run's folder set, undetectably when the counts match (SR-082). | **Evidence version 4**: the evidence also carries the digest of the folder record and of the link record. A writer writes every temporary first, then renames the folder record, the link record, the record and the evidence last, so the evidence is the commit point for all three. The next run rolls forward from the evidence temporary. | IF-015, LLR-038, LLR-118, LLR-039, LLR-123, LLR-143, LLR-162 |
| P-16 | Under P-15, the record of contents matches its evidence but the folder or link record still disagrees after the wait (a kill mid-publication, or a damaged folder record). | **Restore every file, apply neither mismatched record, report part failed (1)**, naming it as damaged or a publication in progress. This keeps SR-040's existing value for a damaged folder record, and folder metadata never blocks a file restore. SR-082 admits it. | SR-082, LLR-039, LLR-143 |

**Coordinator calls (design only, recorded for the Owner):**
- **R3G-001, tightened.** A prepared saved-state folder is recognised as holding
  no content whatever its completeness: it holds no stored object and nothing
  outside its closed set, and partial bytes may lie only in a temporary. Each
  whole record copy in it must still be byte-identical to the backup root's
  file of the same name, and whole evidence, where present, must be valid for
  the folder's whole record copy. This is stricter than the disposition's
  "whatever its completeness" and covers every kill while it is being filled,
  because each file in it is written at its temporary and then renamed.
- **R3G-002.** In a run folder beside no owner record, the owner record's own
  deletion entry holds no content, as the run's location record already does.
  The order (owner record deleted through the run folder) stays, because a
  plain delete of the owner record by path would delete a successor's.
- **The kit before the record.** A backup places the latest state's kit before
  it publishes the latest state's records, so a kill between two kit files
  leaves the pre-run records beside a mixed kit, refused as LLR-159 states
  until the next run places the whole kit again. A new kit reads an older
  record; an older kit beside a newer record would not know its evidence.
- **The roll-forward search covers every reclaimed-leftover folder of that
  root.** A reclaim killed between moving the backup root's staging area aside
  and moving the saved-state root's would otherwise leave the evidence
  temporary in a folder the second reclaim did not move, turning an
  identifiable interrupted publication into a refusal. An evidence temporary
  is positively identified by its digests wherever it lies.
- **R3G-004.** IF-009 keeps the paths, names and entry grammar; IF-044 keeps the
  typed request, the verdict variants and the evidence payload. Publication
  timing stays in LLR-161, and the classification mapping in LLR-017 and
  LLR-088.
- **SR-144** gains "in the store", matching P-09 (a).
- **The staging sequence as one table: LLR-162**, a child of LLR-088. Every kill
  point of a backup and of a reclaim, with the leftover shape and its verdict,
  closed over the steps. Round 4 takes its rows as test cases directly.

The changed rows then go to one bounded convergence check (a fresh session, no
earlier verdicts), scoped to them.

## Convergence check of the closing fixes

Input: `r3i-convergence-sol/` (Codex gpt-6.1-sol, high, a fresh session),
scoped to the 22 rows changed at `c44a4e2`: 1 BLOCKER, 2 MAJOR, 0 MINOR. All
three are **confirmed** and fixed by `r3-merged/_r3j_apply.py`
(`r3h-change-log.md`, round 3j).

| Finding | Rows | Disposition and fix |
|---|---|---|
| R3I-001 (BLOCKER) | LLR-162, LLR-118, IF-015, SR-082 | Confirmed. The first run that writes version 4 over a latest state bound by version-3 evidence could, killed after replacing the folder record with an equal-count one, leave a state that restores the old files with the new folders and reports 0. A new step S12: where the published evidence is of version 3, the run first publishes version-4 evidence for the unchanged state, by one rename, before it replaces any record. The table's closing caveat is replaced by that guard. Steps S12 to S26 become S13 to S27. |
| R3I-002 (MAJOR) | SR-082, SR-106, LLR-123 | Confirmed. P-16 had reached SR-082's acceptance but not its requirement, and LLR-123 still gave 4 to any publication outlasting the wait. SR-082's requirement admits a state restored with its folder or link metadata left unapplied and reported as part failed; SR-106's acceptance says the same for a reader during a writer; LLR-123's 4 is limited to the record of contents. SN-013 is not edited: the files restore as recorded and the unapplied metadata is reported, which is not a wrong restore. The Owner may still want the need's wording to say so. |
| R3I-003 (MAJOR) | LLR-162, LLR-124 | Confirmed. The reclaim's identity-mismatch rollback was missing from the table, and its order was open. The rollback moves the folders back in reverse order (the saved-state root's first), so a kill or a failed move back leaves R2's or R1's shape. It is the table's new R3; R3 to R5 become R4 to R6. |

These fixes have not had a convergence check of their own. The method allows
one scoped check per pass, so whether to run another is the Owner's call.

## Second scoped check (the Owner asked for it)

Input: `r3k-convergence-sol/` (Codex gpt-6.1-sol, high, a fresh session),
scoped to the 6 rows changed at `5bade31`: 2 BLOCKER, 1 MAJOR. All three are
**confirmed** and fixed by `r3-merged/_r3l_apply.py` (round 3l).

| Finding | Rows | Disposition and fix |
|---|---|---|
| R3K-001 (BLOCKER) | LLR-162, LLR-118 | Confirmed. Version-2 evidence is still a supported form and binds the folder record not at all, yet S12 upgraded only version 3. S12 and LLR-118 now cover versions 2 and 3: any evidence without the digests. LLR-162's dimensions gain `evidence_before`. |
| R3K-002 (MAJOR) | LLR-124, LLR-162 | Confirmed. An early failure's cleanup could delete a prepared folder's record copy before its evidence, leaving a shape LLR-088 refuses. The cleanup empties a prepared folder in place, evidence first, then the record copies, then the kit and temporaries, then the folder. This is the table's new row C1. |
| R3K-003 (BLOCKER) | LLR-118, LLR-017, SR-082 | Confirmed. **Coordinator call: refuse.** Round 3h's replace-from-source clause is reversed. A latest folder or link record that disagrees with its evidence, and cannot be identified as an interrupted publication, is a damaged record (3), refused with nothing changed, as SR-017 and SR-082 already require. Replacing it was also unsafe: the saved state the run keeps copies the latest state's records and would bind the damage with fresh evidence. |

**Closing note.** The staging class gave three findings at each of the last
two checks, each narrower than the one before (a version transition, a
cleanup order, a policy contradiction). These round-3l fixes are not
re-checked. The coordinator stops here, as the method's cap and the Owner's
request to close the branch both say. A future check of LLR-162, LLR-118,
LLR-124 and LLR-017 is the first thing to run if this branch is taken
forward.

## Owner rulings made (session 2026-10-18 d, the Owner present)

P-01..P-13 were ruled one at a time with the Owner; each row in the tables
above now records the ruling, and each ruling's commit names the rows it
changed. In short: P-01 calendar periods as today's code; P-02 the removal
dry run specified (SR-153, LLR-163); P-03 the plain check stays quick, -Deep
proves content; P-04 shares measured by their network name, an unmeasurable
backup volume refused (new gap M96); P-05 rebuild; P-06 accept; P-07 drive
only, plus a kit readme; P-08 the source record renamed MANIFEST.fb.src.csv;
P-09 store-scoped; P-10 retry later; P-11 add the views; P-12 complete,
unverified; P-13 a direct rename on one volume, two writers unsupported
(DA-03).

## Scoped check of the round-3l fixes and the session-d rulings

Input: `r3m-convergence-sol/` (Codex gpt-6.1-sol, high, a fresh session),
scoped to the four round-3l rows (LLR-162, LLR-118, LLR-124, LLR-017) and the
22 rows the Owner's rulings rewrote. Group A (round 3l, the staging table, the
P-13 rename and its bound) gave **no finding**. Group B gave 3 BLOCKER, all in
rows written this session, all **confirmed** and fixed by
`r3-merged/_r3n_apply.py` (round 3n).

| Finding | Rows | Disposition and fix |
|---|---|---|
| R3M-001 (BLOCKER) | SR-011, LLR-011 | Confirmed. SR-011 said "a later calendar period"; LLR-011 states today's comparisons, which fire on any different week or month (a clock set back included) and treat the year's end as dividing a week. P-01 ruled today's code, so SR-011 now states LLR-011's predicate, and its permutations gain the earlier period and the year-split week. |
| R3M-002 (BLOCKER) | LLR-035, LLR-011, SR-011 | Confirmed. A rebuilt run-state record made "a re-read due" even under a never schedule. LLR-035 now leaves that to LLR-011: a periodic or every-run schedule re-reads, a never schedule does not. |
| R3M-003 (BLOCKER) | SR-153, LLR-163, LLR-092, LLR-159 | Confirmed. LLR-163 claimed the dry run could not see an existing holder, but LLR-159 already gives readers a non-creating claim test. The dry run now makes that test first and reports a held claim, or a failed test, for every named state as the removal would (LLR-092); its remaining caveat is an operation starting after the preview. This is a small change from today's dry run, which makes no such test; the Owner is told. |

These round-3n fixes are three wording-level corrections within rows the
check already covered; they are not re-checked.

## Double-check of rounds 3n, 3o and 3p (the Owner asked for it)

Input: `r3q-convergence-sol/` (Codex gpt-6.1-sol, high, a fresh session),
scoped to the round-3n rows, the whole component tree after the Owner's
decomposition calls, the IF-010 / IF-047 split, the re-pointed LLRs and
consumer lists, and the new `docs/runtime-flows.md`. No BLOCKER; 3 MAJOR and
1 MINOR, all **confirmed** and fixed by `r3-merged/_r3r_apply.py` (round 3r).

| Finding | Rows | Disposition and fix |
|---|---|---|
| R3Q-001 (MAJOR) | runtime-flows flow 2, LLR-124, LLR-118 | Confirmed. Flow 2 completed an interrupted publication before the successor's staging and owner record existed; LLR-124 orders move aside (R1, R2), fresh areas and owner record (R4), then the completion through this run's folder (R5), then the deletions (R6). Flow 2 now shows that order, with ordinary staging (S01..S05) only in the no-leftovers branch. |
| R3Q-002 (MAJOR) | runtime-flows flow 9, LLR-095 | Confirmed. Flow 9 opened the location record before the action held the backup; it now notes that the record opens inside the action (S06). |
| R3Q-003 (MAJOR) | LLR-163, IF-032 | Confirmed, a defect in round 3n's fix: the claim file is created when absent, so an absent file means no holder, and the non-creating probe would have refused a removal that proceeds. LLR-163 now treats absence as no holder; its dimensions gain the claim file's states. |
| R3Q-004 (MINOR) | CMP-002, CMP-013 | Confirmed. Both notes still described one findings document; they now follow the split. |

These are flow-order and wording corrections within what the check covered;
they are not re-checked.

## The decomposition finished unattended (session 2026-10-18 e)

The Owner asked for the decomposition to be finished unattended by best
judgement, with every call needing a closer look recorded for review in
`DECOMPOSITION-REVIEW.md` (repo root). Working record:
`r3t-root-decomposition.md`.

- **Round 3t:** the top-level pass. Flow 0, N2 charts at every decomposed
  scope, the sibling argument and the descend test. IF-048 to IF-052 and child
  LLR-164 were added; consumer lists completed; flows put each step on the
  component doing the work. A new advisory checker,
  `check_design_layer.py`, was committed.
- **Round 3u** (`r3u-convergence-sol/`, Codex gpt-6.1-sol, high): 0 BLOCKER,
  11 MAJOR, 3 MINOR. Thirteen were confirmed and fixed in round 3v:
  - IF-049 and IF-050 forms closed;
  - IF-053 and IF-054 added;
  - IF-048 gained the plan request (LLR-052);
  - flows 0, 2 and 9 reordered (admission before provisioning, a launch-wide
    plan, the claim before the binding comparison);
  - endpoints completed;
  - gap M97 added.

  R3U-010 was not taken: it contradicts the Owner's Call 4, and is recorded for
  the Owner.
- **Round 3w** (`r3w-convergence-sol/`): the first attempt failed before
  reading anything (a Codex sandbox error). The retry, on the same model,
  completed: 0 BLOCKER, 1 MAJOR, 0 MINOR. R3W-001 was confirmed: IF-054 had no
  form for a check permitted not to be made (LLR-023, LLR-138). It was fixed in
  round 3x. That fix is a one-clause form extension and is not re-checked.

End state: 19 components, 53 interfaces (11 internal), 142 LLRs.
`validate_design.py` reports 0 errors. `check_design_layer.py` reports 0
design-owned findings and 55 placement disagreements, which are ai-template's
placement rule.
