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
| K01 | Astra: elapsed periods since the last completed full re-read (SR-011). |
| K02 | **Owner-level, default taken:** the configuration stays at version 2 (P-01). |
| K03 | SpaceView is a boolean, default false. |
| K04 | **Owner-level, default taken:** the removal dry run stays accepted in the removal request form and keeps working; no LLR states it, since no SR asks for it; it is listed under "code beyond the design" (P-02). It is never made a bad request until the Owner rules. |
| K05 | Full payload check by default (SR-049); the deep switch stays accepted with no meaning, like the old outcome switch. The check's cost rises (about 3 h at the reference host, inside SR-064's 8 h); recorded as P-03. |
| K06 | Opus: no removal override switches in the request form; the module-level overrides are code beyond the design. |
| K07 | Opus: the hashing component is fetched without a question, attended or not (SR-132); the auto-install switch is accepted with no meaning. |
| K08 | **Owner-level, default taken:** Opus: a volume whose free space cannot be measured is not refused; the run's record says the space check was not made (P-04). |
| K09 | Astra's declared allowance numbers; round 4 checks them against the harvested test edges. |
| K10 | Astra: the space plan is read-only and runs before any root, claim, log, record or staging is created, then is revalidated under the claim. |
| K11 | **Owner-level, default taken:** Opus: a missing or unreadable run-state record with a populated backup is rebuilt (completion time from the latest evidence's written time, a full re-read due) and the rebuild is reported (P-05). |
| K12 | Opus: reconcile per path against the backup's latest record; the backup wins. |
| K13 | **Owner-level, default taken, with a coordinator design call.** The record's path separator is the backslash on every host. Design call: the reader of a record written by a supported version treats '/' and '\' alike, and change detection compares normalised paths, so a Linux-written store does **not** take a spurious full rewrite and extra saved state; its records turn to the backslash with the first run that has a real change. A source name holding a literal '\' on Linux is handled by the non-portable-name rule (SR-114/SR-136). The format change itself is a downstream-visible migration (P-06). |
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
| K34 | **Owner-level, default taken:** SR-072's double-click holds for a kit opened from the backup's own volume. A kit carried to a Mac inside a zip is outside the support boundary; the manual gives the one-line remedy (P-07). |
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
| P-01 | Does a version-2 configuration's D/W/M/Y re-read schedule mean calendar buckets (today's code) or elapsed periods (SR-011)? | (a) elapsed periods, still version 2; (b) calendar buckets are v2's meaning, so SR-011 forces version 3 and both meanings are kept | (a) | the configuration interface, the re-read LLRs (filled in by the builder) |
| P-02 | The removal dry run (`-WhatIf`, and the container's dry-run flag) has no need behind it. Keep it or retire it? | (a) add a need, then a dry-run LLR; (b) retire it with a release note; (c) keep it working, unspecified, until ruled | (c) | the removal request interface; code beyond the design |
| P-03 | The check reads every stored object by default (SR-049), about 3 h at the reference host. Accept the heavier routine check? | (a) accept; (b) narrow SR-049 to report altered content only on a deep check | (a) | the check LLRs |
| P-04 | A volume whose free space cannot be measured: refuse (2) or proceed and record that the check was not made? | (a) proceed and record; (b) refuse with 2 | (a) | SR-052 / SR-023 LLRs |
| P-05 | Does the "re-derive and report" ruling for missing change-detection state also cover the run-state record (last completion, last full re-read)? Today the run is refused with 1. | (a) yes, rebuild and report; (b) no, refuse | (a) | LLR-035 and its children |
| P-06 | The record's path separator becomes the backslash on every host. Linux-written stores change form at their next real change (no spurious saved state). Accept the format migration? | (a) accept; (b) keep the host's separator and have every reader accept both | (a) | the record-format interface, LLR-121, gap list |
| P-07 | Does SR-072's macOS double-click cover a kit carried to the Mac inside a zip (which strips the executable bit)? | (a) no: supported from the backup's own volume, the manual gives the remedy; (b) yes: the kit's form must survive zip transfer | (a) | the launcher interface, the macOS launch LLR |

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
| P-08 | The change-detection record at a source root shares its name with a backup's own record, so a source whose root holds such a file (a copied store) has it overwritten. | (a) give the record a name no other artifact uses, reading the old name once; (b) keep the name and refuse a source root holding a backup's record; (c) keep today's behaviour | (a) | IF-029, LLR-114, LLR-001, gap list |
| P-09 | SR-144 says a resumed former owner "changes nothing further", but no fence can close the window between its check and its next write. Align the requirement with its acceptance (it changes no file the successor wrote or published, publishes nothing, and at most leaves one reclaimable temporary)? | (a) align; (b) keep the absolute and require a mechanism with no window | (a) | SR-144, LLR-125 |
| P-10 | A restore of the very state a concurrent removal deletes cannot complete. | (a) SR-106 holds for every state the concurrent operation does not remove; that one restore ends 4, naming the removal, never wrong; (b) a removal waits for readers (needs reader-visible state, which the shell route cannot keep) | (a) | SR-106, LLR-123 |
| P-11 | The Owner's link ruling lists the backup, saved states, change-detection state and logs as the system's own locations. Add the listing location (the views)? | (a) add it; (b) leave it out, so a link into the views is followed | (a) | SR-151, LLR-109, IF-018 |

| P-12 | A state with version-2 evidence (no row counts), written after folder records existed, has no folder record. Today's writer omits the folder record when it has no rows, so its absence cannot be told from a tree with no empty or attributed folder. | (a) restore complete (0), the folder record reported unverified; a present but malformed folder record is still 1; (b) 1, accepting that today's states without empty or attributed folders restore part failed; (c) as (a), and the writer always writes the folder record from now on, so evidence v3's DirRows settles it for new states | (a) | LLR-138, LLR-143, gap M81 |

**Builder deviations accepted** (detail in `r3b-change-log.md`). R3S-014's
one dimensions case is written to P-12 (a), not to 1, for the reason above.
R3O-001's mechanism: the saved state is prepared in its own folder inside the
staging area and published by moving it out, so the one owner record stays in
place until the collapse ends. That meets the disposition's obligation without
a moment with no owner record. Under R3O-012, 28 LLRs lost a `constrains`
cell that placed them wrongly, so they show as unplaced (allowed). New names
the builder chose, for the reviewers to check: the change-detection record
`FILEBACKUP-CHANGES.csv` (P-08), kit revision 14 with a revision line in every
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
| P-13 | Moving superseded or removed content into a saved state by a direct rename would be a mutation outside the run folder, so a resumed former owner could still make it. Copying it and then deleting the original through the run folder keeps it fenced, at the cost of reading and writing that content once more. A large edited file then pays a full copy where it used to be a rename. | (a) copy, then delete through the run folder: fenced; (b) direct rename: today's cost, with one unfenced mutation kind | (a) | LLR-150, LLR-005, LLR-161, gap list |

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
| R3E-001 | LLR-125, LLR-161, SR-144, IF-009, IF-013 | Confirmed. The store's own location record is inside the store, so it comes inside the fence: each run writes its entries to a per-run record inside its run folder, published by rename at the end of the run (IF-009 and IF-013 state the per-run name pattern; a killed run's record stays readable among its moved-aside leftovers). The change-detection state and the views are outside the store. They are derived, and the next run reconciles them from the backup's own record, so SR-144's acceptance names them as outside its guarantee. This is P-09 (a) as widened; the other option, per-run names for them too, stays open to the Owner. |
| R3E-002 | LLR-080, LLR-088, LLR-161, IF-044 | Confirmed. An owner record that is present but carries no usable run identity (torn at creation), beside empty run folders, is the harmless case once its death is proven by stale age and the confirming sample. A non-empty or unrecognised folder still refuses. |
| R3E-003 | IF-033, LLR-088, LLR-150, LLR-038 | Confirmed. LLR-038 stands: the writer generates the prepared saved state's evidence for its own staged record. A prepared folder is recognised by record bytes identical to the published latest record, plus evidence that is valid and matches that record. Evidence bytes are not compared. |
| R3E-004 | LLR-159, LLR-130, LLR-040 | Confirmed; **reverses the round-2 deviation.** A claim that cannot be tested is indeterminate, so a still-mixed kit then ends with 4, naming the refresh and the remedy (re-run it if none is running). Only positive evidence that no refresh holds the claim gives 3. No tool is added to the shell floor. |
| R3E-005 | LLR-123, LLR-118, LLR-039, SR-106 | Confirmed. A reader that finds a record and its evidence disagreeing re-reads until the pair is stable or a declared bound passes (60 s). A pair settling to a match is read normally. A mismatch that outlasts the bound while a writer holds the backup, or while the claim cannot be tested, ends with 4. A mismatch with positive evidence that no writer holds it is damage (3). P-10 is widened to cover this case. |
| R3E-006 | LLR-157, LLR-073, SR-073 | Confirmed: LLR-157 meets SR-073. On a desktop, the shell route offers the folder choice through the dialog providers (IF-027). With no provider available, it asks by typed prompt in an interactive console, otherwise usage and 2, naming the missing provider. On a console with no desktop it uses the typed prompt. An unattended session is refused (2). |
