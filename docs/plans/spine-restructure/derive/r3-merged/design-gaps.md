# Design gaps (round 3, merged tier)

Where an SR obligation is not met by today's code: the SR, the merged LLR that now states the design, and what the code does instead. This list becomes the build work. It is the alignment's merged list (section 6, M01 to M57) with the coordinator's calls (r3-dispositions.md, K01 to K38, P-01 to P-07) applied, plus three gaps those calls add (M58 to M60). 'Found by' says which derivation listed it; the last column records the call or the code check that settles it. Nothing here was run; a 'does instead' resting on inference says so.

## 1. Obligations today's code does not meet

| Gap | SRs | Merged LLR | Found by | What the code does instead | Settled, or the call that governs it |
|---|---|---|---|---|---|
| M01 | SR-137, SR-150, SR-151, SR-152 | LLR-109, LLR-110, LLR-144 | both | The walk neither follows a folder link nor records one; no link record exists; neither restore route recreates a link. File links are followed. | The 60-second bound per resolution or enumeration request is new design (K18). The alignment's reading: a folder link is probably written to the folder record as an empty folder today. |
| M02 | SR-138, SR-063, SR-149 | LLR-103 | both | A backup or saved-state location overlapping a source is not refused. The listing location is checked only when the view is on, per location during the run, failing it (1). State-location overlap is checked only against its own set, failing it (1). Roots are created before these checks. |  |
| M03 | SR-140 | LLR-104 | both | No up-front writability check; the run works, then fails when the change-detection record is written (1). |  |
| M04 | SR-035 | LLR-114 | both | A missing record is silently treated as empty; a malformed one throws and fails the location; its evidence is never checked on read; a stale or foreign record is trusted wherever size and time match. | K12: reconciled per path against the backup's latest record; no new record fields. Missing means empty today (no refusal). |
| M05 | SR-035, SR-005 | LLR-035 | both | A populated backup whose run-state record is missing or unparseable is refused (location fails, 1). | P-05 default (a): rebuild from the evidence's written time and report it (K11). |
| M06 | SR-005 | LLR-028 | Opus | A saved state is named by the previous run's start time; LastBackupRun stores a time taken near the run's start. | Confirmed in code; A missed it. |
| M07 | SR-011, SR-105 | LLR-011 | Astra | Calendar-boundary decision; N with no recorded re-read does re-read; the re-read time is stamped whenever a re-read was due, including runs with unreadable folders. | K01 and P-01 default (a): elapsed periods; the configuration stays at version 2 (K02). |
| M08 | SR-043, SR-040 | LLR-043, LLR-040 | both | A backup returns 1 for busy, capacity, retired form and empty source, and 3 only for witness mismatch; the saved-state report always returns 0; unhandled errors in removal or the report get no mapped value; non-backup actions and both restorers' classified exits are gated by -ExitCode. | Settled: the backup's own exit is not gated by -ExitCode (A over-generalised); configuration failures, non-backup actions and the restorers are. |
| M09 | SR-085, SR-086 | LLR-122 | both | Every claim failure is one refusal (backup 1, removal 2); contention and I/O are not told from denial or an unusable location; the holder is not reliably named. |  |
| M10 | SR-017, SR-107 | LLR-017 | Opus | Every leftover refusal fails the location with 1; an unfinished removal's refusal does not name re-running it as the remedy. | A's G-14 touches only the lock side. |
| M11 | SR-036 | LLR-036 | Opus | The empty-source refusal fails the location with 1, not 2. |  |
| M12 | SR-052 | LLR-052 | both | The demand is per location set, content only (no records, kits, logs, temporary space or allocation), checked after roots, claim, log and staging exist; a shortfall fails the location with 1. | K10: the plan runs read-only before any root, claim, record, staging area or log exists and is checked again under the claim (today it is never re-checked). K09: the declared allowance values in LLR-052 are new. |
| M13 | SR-061 | LLR-060 | both | A backup over a retired form fails with 1; the shell route checks the retired form after creating the target and its log; an unrecognised marker or header is not refused as a form. |  |
| M14 | SR-019 | LLR-020 | Opus | No backup-side runtime-version check. |  |
| M15 | SR-132, SR-016 | LLR-105, LLR-016 | Opus | Obtaining the hashing component prompts when attended and needs -AutoInstallDeps when unattended; the fetched package is not checked against a digest; a missing optional tool may prompt; redirected or closed input is not detected. | K07: fetched without a question, attended or not; the permission switch stays accepted with no meaning. No digest check was found in the code. |
| M16 | SR-008, SR-016 | LLR-008 | Opus | If the kit's hashing library is missing, the language-runtime restore falls back to a package-source install with a prompt, even with -NonInteractive. | Confirmed. |
| M17 | SR-118 | LLR-139 | Opus | The language-runtime route checks neither its runtime version nor the kit's hashing library before writing; the shell route checks the archive extractor only after creating the target. | Second clause from the code check. |
| M18 | SR-009, SR-141 | LLR-009, LLR-079, LLR-137 | both | The language-runtime route normalises the path lexically first (a parent component is cancelled, not refused), resolves only the deepest existing component, and falls back to the text when resolution fails; on GNU systems the shell route accepts a parent component through its resolver. | Both sides right; each saw part. |
| M19 | SR-023, SR-145 | LLR-023, LLR-136 | both | Both routes leave compressed entries out of the demand and add no allowance; the language-runtime route creates the target and its log before the space and archive-tool checks; an unmeasurable volume is skipped (silently on that route). | K09: declared allowance values (allocation rounding, per-folder and per-entry bytes, a fixed 16 MiB, twice the largest expanded item). K08 and P-04 default (a): an unmeasurable volume is not refused, but the report must say the check was not made. |
| M20 | SR-039, SR-116 | LLR-039, LLR-138 | both | Absent evidence is excused for every state; no positive age evidence is consulted; the shell route silently skips non-numeric Rows or Bytes. |  |
| M21 | SR-121 | LLR-141 | both | An escaping entry is counted as missing content (1), not a damaged record (3); an escaping folder-record row only warns. |  |
| M22 | SR-092 | LLR-142 | both | Collisions are not detected: on Windows the language-runtime route keeps the last of two case-differing rows; elsewhere both are written to one file; the shell route lets the second overwrite the first. |  |
| M23 | SR-146, SR-122, SR-065 | LLR-143 | both | A missing or malformed folder record never changes the outcome; nothing tells a state that should have one from one that has none; the language-runtime route assigns attributes (replacing existing bits); the shell route never applies attributes, only logs them. | Shell-route clause from the code check; neither side listed it. |
| M24 | SR-066 | LLR-066 | both | A blank time is skipped silently and an unparseable one only warns; the restore still ends complete. |  |
| M25 | SR-040, SR-068, SR-119 | LLR-040, LLR-050 | both | An unclassified error mid-restore reports 2 although files were written; a shell switch without its value exits 127; a direct object's expansion failure is a host failure (4) with no tool self-test (the self-test runs only in the pool search); a missing item whose search ends in a host cause is recorded as missing content. | A found the direct-expansion case, O the rest. |
| M26 | SR-120 | LLR-029 | Opus | The summaries give counts and names but no per-entry causes (causes only in separate log lines); the report entries are not in the IF-022 form. |  |
| M27 | SR-124 | LLR-107 | Opus | The record gives one new-or-changed count and a removed count; added files are not told from changed ones and most are not named. |  |
| M28 | SR-125 | LLR-108 | both | No progress entries at all; the only periodic activity is the owner-record refresh. |  |
| M29 | SR-089, SR-091, SR-067 | LLR-111, LLR-067 | both | A file that cannot be read for its digest aborts the whole location; retries cover only the copy. |  |
| M30 | SR-049 | LLR-049 | both | The default check reads only an object's opening bytes; altered content is found only with -Deep. | K05 and P-03 default (a): the full payload check is the default (about 3 h of reading at the reference host, inside SR-064's 8 h); the deep switch stays accepted with no meaning. |
| M31 | SR-109 | LLR-129 | both | Repair renames and rewrites forms but never copies content back from a verified copy elsewhere. |  |
| M32 | SR-117, SR-110 | LLR-131, LLR-130 | Astra | The refresh copies the backup root's existing kit into each saved state (it does not regenerate it from the installed program), file by file with no temporary name, so a kill can leave a mixed kit. | Confirmed in code. K23: the source becomes the installed program's kit, each file through a temporary and a rename, never deleting, the files carrying the kit revision last. K14: the first refresh of a state records its original kit revision (new form, IF-019). Whether each repair rename publishes by temporary and rename is still unconfirmed. |
| M33 | SR-097 | LLR-132 | both | No space view and no setting for it. |  |
| M34 | SR-098, SR-099, SR-147 | LLR-133, LLR-134 | Opus | The media rate is never computed: the switch that would enable the tool is hard-wired off, and no record entry says the measure was not taken. | Settled for O: the measurement function is called per hashed file but returns nothing because the tool is never resolved. A's 'invokes measurement when the tool is available' is wrong. |
| M35 | SR-131 | LLR-119 | both | No licence or notice file in any backup; the hashing library is redistributed without its notice. |  |
| M36 | SR-143 | LLR-148 | Opus | The container image carries no notices file. | Confirmed from the image build definition (A had not read it). |
| M37 | SR-135, SR-027 | LLR-099 | both | The native-Windows form carries no version and the helper writes none. |  |
| M38 | SR-018, SR-042 | LLR-042, LLR-101 | both | The native-Windows form gets a shape check only: no closed key set, no strict value kinds; the published description covers JSON only. |  |
| M39 | SR-129 | LLR-100 | both | A native-Windows credential in plain text is not refused. |  |
| M40 | SR-095 | LLR-014 | both | A multi-set JSON configuration draws a warning; removal, report, check and view act on the first set only. | First-set clause from O, confirmed. |
| M41 | SR-048, SR-103 | LLR-048, LLR-128 | Opus | Removal and the report resolve locations in the backup's mode: they need the source to exist and create missing backup or saved-state folders. |  |
| M42 | SR-033, SR-136 | LLR-121 | Opus | A Linux run writes '/' where a Windows run writes '\'; a run from the other host type then sees every file removed and added. | Confirmed. K13 and P-06 default (a): the writer uses the backslash on every host; readers of a record written by a supported version take '/' and '\' alike and change detection compares the normalised paths, so a Linux-written store takes no full rewrite and no extra saved state; its latest record turns to the backslash with the first run that has a real change. The format change is a downstream-visible migration to flag. |
| M43 | SR-082 | LLR-087, LLR-118 | both | The evidence is written only after the record is renamed, and nothing is flushed; a kill between the two leaves a mismatch the next run refuses. | K19: each temporary is flushed to stable storage before its rename (today nothing is flushed). K20: the evidence of the temporary is written before the record's rename, so the next run completes the publication. |
| M44 | SR-027 | LLR-027 | Opus | The quick start's first run asks before installing the hashing component; the helper writes an unversioned document; the user manual states two different current configuration versions. |  |
| M45 | SR-064, SR-112, SR-113 | LLR-149, LLR-062 | both | The time and memory budgets have never been measured at the declared scale; removal and the audit keep whole records; restore recovery scans candidates per unresolved row. | Not a measured failure: a missing measurement. |
| M46 | SR-104 | LLR-096 | Opus | The repair's findings document has no per-finding Repaired field (a fresh re-check is printed instead). |  |
| M47 | SR-001, SR-074 | LLR-001, LLR-022 | Astra | With the change-detection record at the source root, the whole backup infrastructure list is excluded at the source root (owner files sharing a backup-only name are skipped); with the record elsewhere, that branch also skips the volume-root filter. | A's claim, not re-checked by the alignment; confirm when the code is headed. |
| M48 | SR-005, SR-065 | LLR-005 | Astra | The saved-state decision comes from the file-row diff only; a run whose only change is a new empty folder adds no saved state and overwrites the folder record. | Confirmed in code. |
| M49 | SR-101, SR-017 | LLR-127 | Astra | A removal killed before its commit point leaves its staging marker; the next removal refuses any existing staging area and backups refuse the marker, so the store wedges until a person clears it. | Confirmed in code. |
| M50 | SR-046, SR-102 | LLR-046, LLR-126 | both | Target checks are lexical (a link to outside is not resolved); module-level options can waive the unreferenced-content and evidence refusals. |  |
| M51 | SR-082, SR-059, SR-041 | LLR-150 | Astra | Removed and superseded objects move into staging before the new latest record is published; a kill there leaves a witnessed latest record whose bytes only staging holds, and no restore searches staging. | Confirmed in code. The design (LLR-150) moves content out of the backup root only after the new latest record is published. |
| M52 | SR-081 | LLR-086 | Astra | A file of exactly 262144 bytes is measured; the SR gives files at or below 256 KiB the file-type rule. | Confirmed (both code conditions treat 262144 as above the floor). |
| M53 | SR-072 | LLR-074 | Astra | A Windows-written kit carried to a Mac by zip needs a manual chmod before Finder opens the launcher; the restorer holds the window on success and on classified exits but not on its error trap. | K34 and P-07 default (a): a kit carried to a Mac inside a zip is outside the support boundary; the build work is the manual's one-line remedy, writing the launcher with its executable permission where the volume holds one, and holding the window on the restorer's error trap. |
| M54 | SR-073 | LLR-073 | alignment code check | The language-runtime route never checks for a desktop session (only the console and input), and a cancelled folder choice falls back to a typed prompt. | Found by the alignment's code check. |
| M55 | SR-144 | LLR-125 | Astra | The owner identity is re-checked at five boundaries only; a resumed former owner can still move or delete between them. | K21: re-check before every destructive step (move, delete, replace, publish); writing a new object at a fresh temporary name needs none. |
| M56 | SR-106, SR-103 | LLR-123 | Astra | A reader meeting a location that a concurrent repair, collapse or removal has just moved has no re-resolution or re-read rule. | K22: no claim and no reader artifact; a reader re-resolves a vanished location by content key and re-reads a record whose evidence changed mid-read, up to three times. |
| M57 | SR-130 | LLR-147 | Astra | Scratch uses the host temporary folder; the shipped compose file mounts /tmp as tmpfs. | K26: /tmp is declared in the mount form (IF-039) as a non-persistent scratch mount. A gap only if the reviewers find SR-130's 'working-state locations' does not admit it. |
| M58 | SR-118, SR-040 | LLR-139, LLR-040 | coordinator (K32) | Neither route self-tests a present tool at admission; the archive tool's self-test runs only inside the content search, so a broken tool is met mid-restore and reported as a host fault (4). | K32: a tool present but failing its self-test at admission returns 2. |
| M59 | SR-003, SR-082 | LLR-117 | O (its reading of the code) | A new stored object is written directly at its content-derived name after clearing an unreferenced file there (the archive tool adds to an existing archive); it is not written at a temporary name, checked and published by rename. | K33: write at a private temporary, verify the content key, publish without replacing a claimed object. Not re-checked by the alignment; confirm when the code is headed. |
| M60 | SR-116, SR-146, SR-084 | LLR-138, LLR-038, LLR-131 | coordinator (K14) | The completeness evidence is version 2 and states no folder- or link-record rows; no state records an original kit revision, and a kit refresh overwrites the only kit revision a state carries, so age cannot be told positively once a state is refreshed. | K14: evidence version 3 with DirRows and LinkRows (IF-015); the kit refresh records a state's original kit revision once, never changed (IF-019); no per-state format descriptor. The kit revisions that introduced completeness evidence, the folder record and the link record must be read from the release history at build time. |

60 gaps. Claimed gaps the alignment dropped or folded: Astra G-10 (a refused configuration appends to an existing global log) is dropped, since SR-018 forbids truncation, not an appended refusal line (K27); Astra G-13 is folded into M08; Astra G-30 into M34; Opus G-36's kit-refresh half is settled in M32 and its repair-rename half stays open there.

## 2. SR constrains

Boundary interfaces whose behaviour an SR states at the system boundary. The SR tier is not this tier's to edit, so these pairs are listed for it to carry as `constrains` cells. Every interface except IF-027 also has a constraining LLR; IF-027 relies on its pair here.

- SR-043 -> IF-003 (Operation outcome value)
- SR-040 -> IF-021 (Restore outcome value)
- SR-010 -> IF-023 (Restored tree)
- SR-104 -> IF-010 (Machine-readable findings)
- SR-120 -> IF-022 (Restore report)
- SR-142 -> IF-038 (Container actions and environment)
- SR-130 -> IF-039 (Container mounts and user)
- SR-131 -> IF-019 (Restore kit artifact set)
- SR-143 -> IF-040 (Container image contents)
- SR-139 -> IF-029 (Change-detection record)
- SR-148 -> IF-029 (Change-detection record)
- SR-132 -> IF-037 (Package source)
- SR-073 -> IF-026 (Restore host session)
- SR-073 -> IF-027 (Folder choice dialog) (added by the merge: the folded Opus LLR-145 was IF-027's only constraining row; its observable part, an absent, failed or cancelled choice giving no target, now sits in LLR-073, which constrains IF-026, so SR-073's own 'asks for the target folder' is what constrains the dialog)

## 3. SRs that reach no LLR

None. Every one of the 123 SRs is in the `sr_refs` of at least one top-level LLR (the validator's count: 0 unreached).

## 4. Code beyond the design

No SR asks for these. None is stated by an LLR; where the request form still accepts a switch so that existing callers are not refused, the interface form says so.

- **Removal dry run** (the removal's what-if switch, and the container's dry-run variable). P-02 default (c), K04: it stays accepted in the removal request form (IF-002) and the container form (IF-038) and keeps working, unspecified; no LLR states it, and it is never made a bad request until the Owner rules (add a need, or retire it with a release note).
- **Removal overrides at the module level** (discard unreferenced content, accept unverified records, skip verification). K06: not in the request form; SR-046 refuses those cases without exception. Retire them or keep them test-only.
- **The deep-check switch.** K05: its meaning becomes the default check (LLR-049); it stays accepted with no meaning, like the former outcome switch.
- **The permission switch for obtaining the hashing component.** K07: accepted with no meaning; the component is fetched without a question (LLR-105).
- **The strict-evidence restore switch** (both routes). Kept in the restore request form (IF-020) and honoured in LLR-039, though no SR asks for it; treat like the dry run: the Owner adds a need or it stays outside the design.
- **The multi-set warning.** Goes (SR-095, LLR-014).
- **The run-date test seam** (the switch that pins a run's date). Not part of the launch form; a test-tier seam.
- **The include-saved-states boolean and the verify alias.** Accepted by today's entry point; the merged IF-002 lists both as accepted spellings of existing requests (latest-only check, the check action), so they stay working with no new meaning.
- **The listing location must be on the backup's volume.** K35: kept, with its reason now in LLR-103's rationale (each view entry is a relative link to its stored object, and a relative link cannot cross volumes on Windows), so it is no longer beyond the design.
