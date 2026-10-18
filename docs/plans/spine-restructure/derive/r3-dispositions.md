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

The fixes are applied by an Opus builder (`r3b-change-log.md`). Then a fresh
convergence check (Codex Sol, high, a new session) reviews only the changed
rows. This is full round 1 of at most 3.
