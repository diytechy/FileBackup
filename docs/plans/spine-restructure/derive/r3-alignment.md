# Round 3 alignment: the design tier (components, interfaces, LLRs)

The aligner's comparison of the two independent design derivations, `r3-astra` (GPT-6 Astra) and `r3-opus` (Claude Opus), against the derivation brief `derive-brief-r3-design.md`, the pointer rules, spine-questions sections 0 and 3, and the Owner rulings in force (handoff of 2026-10-18). Every row stays Drafted; nothing here is approved. Open item 1 (the review of the last unreviewed SR edits) is the reviewers', not this file's.

Machine-readable twin: `r3-alignment-map.json` (same clusters, plus an id crosswalk from each side's ids to the merged ids).

**Independence.** Both derivers saw `AGENTS.md`: Astra discloses it was in its opening context, and Opus read its sections 1 and 2 (its notes). So agreement on code-derived detail (switch names, layout names, values) is weaker evidence of independence than agreement on design choices. Where the two disagreed about what today's code does, the alignment checked the code itself (two read-only surveys of the engine, the shared library, the entry point, both restore routes, the container files and the image build, with line evidence). The settled facts appear under each conflict and gap.

## Counts

| Item | Astra | Opus | Aligned |
|---|---|---|---|
| Components | 16 | 24 | 24 |
| Interfaces | 40 (28 boundary, 12 internal) | 43 (40 boundary, 3 internal) | 45 adopted (41 boundary, 4 internal), plus 2 conditional on a conflict; 47 clusters |
| LLRs | 85 (75 top, 10 child) | 128 (106 top, 22 child) | 129 obligation clusters giving 128 rows (106 top-level, 22 child); 1 cluster folds into another row |
| Legacy LLR ids kept | 63 | 73 | 73 kept; 10 retired; 11 never in the stripped registry |
| New LLR ids | 22 (LLR-095 to LLR-116) | 55 (LLR-095 to LLR-149) | 55: Opus's own new id wherever the row comes from Opus, LLR-150 for the one Astra-only row; LLR-145 is left unused (folded) |
| Design gaps | 36 | 50 (+6 code beyond the design) | 57 merged gaps, 4 claimed gaps dropped or folded, 8 items of code beyond the design |
| SRs reaching an LLR | 123/123 | 123/123 | 123/123 |
| Cluster verdicts | | | take A 3, take O 48, union 69, conflict 8, fold 1; 33 clusters touch a listed conflict |
| Conflicts | | | 38, of which 6 are Owner-level |

The aligned LLR count equals Opus's (128) by coincidence of two moves: one Opus row folds into LLR-073, and one obligation only Astra stated is added. Both sides minted from LLR-095 with different meanings. The merge keeps Opus's new ids (so a merged new id means what Opus's row with that id means) and renumbers every Astra new id; use the crosswalk for Astra's ids, never Astra's own new numbers.

## 1. Proposed component tree

Drawn from the responsibilities the SRs demand. It is Opus's tree, which already separates the responsibilities the SRs assign to different parents; each row says what Astra contributes. The one structural rule kept from Opus: the restore kit depends on nothing backup-only, because it travels inside every backup.

- CMP-001 FileBackup
  - CMP-002 Operation launch and outcome
  - CMP-003 Configuration
  - CMP-004 Provisioning
  - CMP-005 Notification
  - CMP-006 Run record and progress
  - CMP-007 Backup engine
    - CMP-008 Source capture
    - CMP-009 Change detection
    - CMP-010 Content writer
    - CMP-011 State publication
    - CMP-012 Exclusive-use guard
    - CMP-013 Removal and saved-state report
    - CMP-014 Check, repair and kit refresh
    - CMP-015 Views
  - CMP-016 Store format
  - CMP-017 Restore kit
    - CMP-018 Restore admission
    - CMP-019 Entry restoration
    - CMP-020 Tree finishing
    - CMP-021 Restore outcome and report
    - CMP-022 Restore launch and target choice
  - CMP-023 Container
  - CMP-024 Release guidance

| Id | Name | part_of | From | Note |
|---|---|---|---|---|
| CMP-001 | FileBackup | (root) | A CMP-001 + O CMP-001 | Root. Keep O's structural rule: the restore kit depends on nothing backup-only. |
| CMP-002 | Operation launch and outcome | CMP-001 | O CMP-002; A CMP-012 (dispatch, cross-location outcome) | Owns the one outcome vocabulary and the per-location fold. |
| CMP-003 | Configuration | CMP-001 | O CMP-003; A CMP-012 (validation, defaults) | Owns both document forms and the cross-location overlap checks at launch. |
| CMP-004 | Provisioning | CMP-001 | O CMP-004; A CMP-013 (dependency discovery) | Runtime floor, required component, tool location; never prompts unattended. |
| CMP-005 | Notification | CMP-001 | O CMP-005; A CMP-014 (notification) |  |
| CMP-006 | Run record and progress | CMP-001 | O CMP-006; A CMP-014 (progress, run records) |  |
| CMP-007 | Backup engine | CMP-001 | O CMP-007; A CMP-002 (backup production, narrower) | O's engine also holds the guard, removal, check and views; A spread those over top-level components. |
| CMP-008 | Source capture | CMP-007 | O CMP-008; A CMP-003 (traversal, portability, links) |  |
| CMP-009 | Change detection | CMP-007 | O CMP-009; A CMP-003 (cached identities) | A merged capture and change detection; the SRs give them different parents (SR-001/074 against SR-088/105/035/011). |
| CMP-010 | Content writer | CMP-007 | O CMP-010; A CMP-004 |  |
| CMP-011 | State publication | CMP-007 | O CMP-011; A CMP-005 |  |
| CMP-012 | Exclusive-use guard | CMP-007 | O CMP-012; A CMP-006 (store coordination, top-level in A) | A puts coordination at the top because its read-generation session (A IF-040) makes readers participants; that design is not recommended (conflict K22), so the guard stays backup-only under the engine. |
| CMP-013 | Removal and saved-state report | CMP-007 | O CMP-013; A CMP-009 (retention) | Owns the content-location index (O IF-043). |
| CMP-014 | Check, repair and kit refresh | CMP-007 | O CMP-014; A CMP-010 |  |
| CMP-015 | Views | CMP-007 | O CMP-015; A CMP-014 (generated views) |  |
| CMP-016 | Store format | CMP-001 | O CMP-016; A CMP-007 (store representation); A CMP-013 (digest text, volume measurement) | Shared by every writer and both restore routes; owns the digest text form (see interface cluster I13). |
| CMP-017 | Restore kit | CMP-001 | O CMP-017; A CMP-011 | One set of requirements binds both routes (both sides agree). |
| CMP-018 | Restore admission | CMP-017 | O CMP-018; A CMP-011 (admission) |  |
| CMP-019 | Entry restoration | CMP-017 | O CMP-019; A CMP-011 (file recovery) + A CMP-008 (content resolution, restore side) | A's CMP-008 'Content resolution' shared between maintenance and restore is not adopted as its own component: the backup-side index (CMP-013) and the restore-side search (CMP-019) have different forms (O IF-043 against A IF-018) and the kit may not depend on backup-only code. Recorded as conflict K38. |
| CMP-020 | Tree finishing | CMP-017 | O CMP-020; A CMP-011 (metadata application) |  |
| CMP-021 | Restore outcome and report | CMP-017 | O CMP-021 |  |
| CMP-022 | Restore launch and target choice | CMP-017 | O CMP-022; A CMP-015 (launchers) |  |
| CMP-023 | Container | CMP-001 | O CMP-023; A CMP-016 (container adapter, part_of A CMP-012) + A CMP-015 (licensed image) | A nests the adapter under launch; O keeps adapter and image together. O preferred: SR-034/130/143 are one delivery responsibility. |
| CMP-024 | Release guidance | CMP-001 | O CMP-024; A CMP-015 (setup delivery) |  |

Astra's components and where they went: CMP-002 backup production -> CMP-007 (narrower in Astra); CMP-003 capture and change detection -> CMP-008 + CMP-009; CMP-004 -> CMP-010; CMP-005 -> CMP-011; CMP-006 store coordination -> CMP-012; CMP-007 store representation -> CMP-016; CMP-008 content resolution -> CMP-013 (index) + CMP-019 (search), see K38; CMP-009 retention -> CMP-013; CMP-010 -> CMP-014; CMP-011 restore -> CMP-017 and its children; CMP-012 configuration and launch -> CMP-002 + CMP-003; CMP-013 host capabilities -> CMP-004 (discovery) + CMP-016 (digest text, volume measurement); CMP-014 operator reporting -> CMP-005 + CMP-006 + CMP-015; CMP-015 delivery and setup -> CMP-022 (launchers) + CMP-023 (image) + CMP-024 (guidance); CMP-016 container adapter -> CMP-023.

Both sides' component notes name no file or code; both describe today's carriers in role words (the backup-only engine module, the restore-safe shared library), which the brief asks for as design information.

## 2. Interface clusters

Clustered by the form they state. The merged numbering follows Opus's ids (IF-002 to IF-044) because its set is the more complete; Astra-only forms that are adopted take IF-045 and IF-046. IF-001 is retired by both, and both map its parts to the same clusters (Astra's mapping section, Opus's IF-001 table).

| Merged | Form | Astra | Opus | Verdict | Where they differ |
|---|---|---|---|---|---|
| IF-002 | Backup launch request | IF-003 | IF-002 | take O | Both have it. O is more correct: it names the real switches (-AutoInstallDeps, not A's -AutoInstallHashing), states applicability and the bad-request rule. A lists -DiscardUnreferencedData and -AllowUnverifiedIndex, which are module-level options, not entry switches. Disagree on -WhatIf (removal dry run, K04) and -Deep (K05). Neither lists -IncludeSnapshots or the -VerifyStorage alias that the entry point also accepts; -BackupTime is a test seam and stays out of the form. |
| IF-003 | Operation outcome value | IF-004 | IF-003 | take O | Both: {0,1,2,3,4} with the ruled meanings. O adds the closed list of operations, matching the ruling 'every operation' (A omits the report and the view rebuild). |
| IF-004 | Configuration settings catalogue | IF-002 | IF-004 | take O, conflicts K02, K03 | Both. A states one row for both forms; O splits catalogue / JSON form / native form (IF-004/005/006, carried_by) and adds the reserved word link and the retired key PreserveFolderTree. Disagree on ConfigVersion (A 3, O 2; K02) and SpaceView type (A off/on, O boolean; K03). BEHAVIOUR FLAG: both state the schedule letters' timing in the form (A elapsed periods, O calendar buckets); the letters' value set is form, their timing belongs to LLR-011 only. |
| IF-005 | JSON configuration document | IF-002 | IF-005 | take O |  |
| IF-006 | Native-Windows configuration document | IF-002 | IF-006 | take O | Both admit a host-protected credential only in this form (owner ruling). |
| IF-007 | Environment settings | IF-024 | IF-007 | take O | O adds FILEBACKUP_LOG_PATH and FILEBACKUP_NO_GUI (both read by today's code). A's discovery-source order is behaviour and belongs to LLR-037. |
| IF-008 | Release guidance set | IF-035 | IF-008 | take O |  |
| IF-009 | Run record | IF-027 | IF-009 | take O, flag | Both. O concrete (names, entry grammar, prefixes). FLAG: O's refusal tokens embed requirement ids ([SR-075/...]); they exist in today's code, so keep them frozen as form but do not mint new id-bearing tokens (requirement renumbering would change a host-visible string). |
| IF-010 | Machine-readable findings | IF-028, IF-029 | IF-010 | take O + A note | Both. O matches the code's field names (Class, FolderName, KitRevision; A says Kind and invents WitnessMismatch/UnsupportedForm where the code has LegacyStoredForm). O adds Repaired for SR-104 (gap). A adds that BytesReclaimed may be negative; keep that as a stated value range if the plan can yield it. |
| IF-011 | Notification message | IF-031 | IF-011 | take O |  |
| IF-012 | Protected notification credential | IF-032 | IF-012 | take O |  |
| IF-013 | Backup store layout | IF-011, IF-041 | IF-013 | take O, flag | Both. A states roles without names and puts the leaf names into LLRs (K36); O names them in the form, which the brief allows and which gives each name one home. A's IF-041 (B-02 live storage exchange) folds in as O's second crossing. BEHAVIOUR FLAG in O: 'the date is the completion time of the state it holds' and 'the retired launcher name is never written' move to LLR-028 and LLR-007. |
| IF-014 | Record of contents | IF-007 | IF-014 | union | Same nine columns, both backslash separators (today's Linux writer uses '/', gap M42). A adds canonical bytes (LF, BOM tolerated on input, Length range, Duplicate may be empty); O adds Original as the retired layout-marker value and the boundary crossing. Union. |
| IF-015 | Completeness evidence | IF-008 | IF-015 | conflict K14 | Same keys today (Version=2, Rows, Bytes, XxH128, Written; A matches the code). O proposes Version=3 with DirRows/LinkRows as positive age evidence. |
| IF-016 | Stored object name and form | IF-010 | IF-016 | take O | Same grammar and alphabet. O is correct that a compressed object's extension becomes .7z (A's 'outer .7z suffix' reads as appended); O adds the retired grammars the code recognises (separator in name; space at index 16 in 27+ characters). BEHAVIOUR FLAG: 'the electing file's extension' is LLR-058's decision. |
| IF-017 | Folder record | IF-012 | IF-017 | take O, conflicts K15, K16 | A's semicolon separator contradicts today's comma (both routes split on ','); changing it breaks kits already in backups (SR-084). A's always-present header-only record against O's present-only-with-rows (today's behaviour). |
| IF-018 | Link record | IF-013 | IF-018 | conflict K17 | Both new form, separate file LINKS.csv. Column names and value sets differ. |
| IF-019 | Restore kit artifact set | IF-033 | IF-019 | take O, flag | O names the on-disk artifacts that are data or launchers and names the kit's code files by role (correct per brief). BEHAVIOUR FLAG: the launcher's 'one line passing every argument' is LLR-074's. |
| IF-020 | Restore request | IF-005 | IF-020 | take O | O gives the real switches of both routes; A abstract. |
| IF-021 | Restore outcome value | IF-006 | IF-021 | take O | Same value set. |
| IF-022 | Restore report | IF-006 | IF-022 | take O, flag | O's cause tokens match the code. BEHAVIOUR FLAG: 'nothing is written to the target before admission passes' is LLR (admission) text. |
| IF-023 | Restored tree | IF-022 | IF-023 | take O |  |
| IF-024 | Restore tool floor | IF-026 | IF-024 | take O | A's 'POSIX byte-count fallback' is behaviour (LLR-071). |
| IF-025 | Restore target probe | IF-020 | IF-025 | union | A adds allocation-unit bytes and target name/attribute/link semantics, needed by the declared allowance (K09) and collision detection. |
| IF-026 | Restore host session | IF-039 | IF-026 | take O |  |
| IF-027 | Folder choice dialog | IF-039 | IF-027 | take O |  |
| IF-028 | Source tree view | IF-021 | IF-028 | union | Same. BEHAVIOUR FLAG in O: 'read-only opens that share reading only' belongs to the source-never-changed LLR. |
| IF-029 | Change-detection record | IF-036, IF-037 | IF-029 | take O, conflict K12 | A splits the external location (B-20) and the source-root cache (B-24) and adds a source/store identity binding and generation id (new form); O one row on both crossings, no new fields. |
| IF-030 | Run-state record | IF-017 | IF-030 | take O, flag | A adds a state-generation identity and source/store binding (new form, tied to K12/K20). BEHAVIOUR FLAG in O: 'written to .tmp and published by rename' is LLR-028/087 text; the .tmp name itself is form. |
| IF-031 | Volume space and identity | IF-019 | IF-031 | union | A adds allocation-unit bytes. BEHAVIOUR FLAG in O: the mount-table rule is FileBackup's measurement (LLR for volume identity), not the external party's form. |
| IF-032 | Exclusive-use claim | IF-015 | IF-032 | take O, flag | Same artifact (Temp.lock at the saved-state root). BEHAVIOUR FLAG in O: 'never written and never deleted' is LLR-093's. |
| IF-033 | Staging area and owner record | IF-016 | IF-033 | take O, flag | Same fields as the code. A puts the classification verdict in this row; O moves it to the internal IF-044 (better: verdict is a result, not the record). Add: PRUNE.inprogress holds the saved-state name as text. BEHAVIOUR FLAG in O: 'written once by exclusive create', 'modification time is the liveness evidence' belong to LLR-080. |
| IF-034 | Content digest | IF-009, IF-025 | IF-034 | take O, owner change | Both: XXH128, 32 uppercase hex, most significant byte first. Owner differs: A CMP-007 (internal store representation), O external:EXT-06. Recommend owner CMP-016 for the text form, which is FileBackup's choice, with the hashing service itself in IF-046. FLAG: O names the third-party package; move the package identity to IF-037. |
| IF-035 | Archive tool | IF-025 | IF-035 | take O |  |
| IF-036 | Media probe | IF-025 | IF-036 | take O |  |
| IF-037 | Package source | IF-038 | IF-037 | take O | O pins 8.0.0 identified by the published SHA-256 (as the image build does today); A allows 'a declared compatible release'. |
| IF-038 | Container actions and environment | IF-023 | IF-038 | take O + A values, conflicts K04, K25 | A's truthy set (1,true,TRUE,True,yes,YES,Yes) matches the entry script exactly; O's 'any case' is wrong. A keeps FILEBACKUP_DRY_RUN; O drops it. |
| IF-039 | Container mounts and user | IF-023 | IF-039 | take O, conflict K26 | O names the mounts and uid 65532 and adds /tmp scratch (the shipped compose file mounts /tmp as tmpfs). |
| IF-040 | Container image contents | IF-034 | IF-040 | take O |  |
| IF-041 | Browse view | IF-030 | IF-041 | take O |  |
| IF-042 | Space view | IF-030 | IF-042 | take O | New form both sides; O concrete (SPACE.tsv). |
| IF-043 | Content-location index (internal) | - | IF-043 | take O | O only. A's nearest is IF-018 (per-key query), a different form. |
| IF-044 | Leftover classification verdict (internal) | IF-016 | IF-044 | take O | A carries the verdict set inside its owner-record row. |
| IF-045 | Content search by key (internal, restore side) | IF-018 | - | take A | A only. O states the same answer set in LLR-050 text; a typed, symbol-free form is the target shape for a call that crosses components. Owner CMP-019. |
| IF-046 | Backup runtime and tool floor | IF-025 | - | take A (part) | A states the backup-side runtime floor at B-10; O states it only in LLR-020. Owner external:EXT-06. |
| (not adopted) | State format descriptor and publication intent | IF-014 | - | conflicts K14, K20 | A only (STATE-FORMAT.json plus a durable intent). Adopted only if K14 or K20 goes A's way. |
| (not adopted) | Read-generation session | IF-040 | - | conflict K22 | A only. Adopted only if K22 goes A's way. |

**Interfaces that state behaviour (flags).** Each flagged clause moves to the LLR named in the table; the form row keeps only names, grammar, value sets and columns.

- Astra IF-002 and Opus IF-004: the timing of the schedule letters (elapsed in Astra, calendar in Opus). The letters are form; when each is due is LLR-011's.
- Opus IF-013 (completion-time dating; retired launcher never written), IF-016 (the electing file's extension), IF-019 (the launcher's single line), IF-022 (nothing written before admission), IF-023 (no other file written), IF-028 (read-only shared opens), IF-030 (written through .tmp then renamed), IF-031 (the mount-table rule), IF-032 (never written or deleted), IF-033 (exclusive create; modification time as liveness), IF-044 (forced, literal, fail-closed listing).
- Astra IF-016 (modification time as heartbeat), IF-024 (discovery order), IF-026 (the POSIX fallback).

**Interfaces that name a code file or symbol.** None names a kit code file or function on either side (both validators checked this; spot reading agrees). Borderline items:

- Opus IF-034 names the third-party hashing package. That is an external party's identity, not kit code; move it to IF-037 (package source), where the identity is the form.
- Opus IF-009's refusal tokens embed requirement ids ([SR-075/...]). They are not code, but a requirement renumbering would change a host-visible string. They exist in today's code, so freeze them as form and mint no new id-bearing tokens.
- Astra IF-003 names -AutoInstallHashing, which does not exist (the entry point's switch is -AutoInstallDeps), and two module-level options that are not entry switches (K06). These are errors of fact, not symbol leaks.
- Astra puts the on-disk leaf names in LLR text (MANIFEST.csv, DIRECTORIES.csv, LINKS.csv, Temp.lock, RUN.inprogress, FileBackupState.json, STATE-FORMAT.json); Opus keeps them in interface data. The brief allows them in interface data as agreed form; recommend Opus's convention (K36).

**Tooling notes.** Opus adds a `title` key to interface rows and writes `interface_*_external` and `carried_by` as lists where a form sits on two crossings or rides in two carriers. The brief says 'a B-NN crossing', so the build must either accept lists or move a second crossing into the rationale. Astra's rows have scalars.

**SR constrains pairs** (for the SR tier, not edited here), merged from both sides and mapped to merged interface ids: SR-043 -> IF-003; SR-040 -> IF-021; SR-010 -> IF-023; SR-104 -> IF-010; SR-120 -> IF-022; SR-142 -> IF-038; SR-130 -> IF-039; SR-131 -> IF-019; SR-143 -> IF-040; SR-139 -> IF-029; SR-148 -> IF-029; SR-132 -> IF-037; SR-073 -> IF-026. Every adopted interface also has at least one constraining LLR in the merged set.

## 3. Conflicts

38 places where the two sides disagree on substance. 'Design' means the coordinator's call; 'OWNER' means a behaviour call that changes what an owner or host sees. Opus's five least-sure calls are K11 (call 1, the run-state record), K13 (call 2, the separator), K14 (call 3, positive age evidence), K05 (call 4, the full check by default) and K17 (call 5, links).

**Owner-level:** K02 (Configuration description version), K04 (Removal dry run), K08 (A volume whose free space cannot be measured (backup and restore)), K11 (Missing or unreadable run-state record with a populated backup (Opus call 1)), K13 (One path separator and the migration (Opus call 2)), K34 (macOS double-click).

### K01. Re-read schedule timing

- **Astra:** Elapsed periods since the last completed full re-read; N never re-reads, history or not; the time is stamped only when a full re-read completes.
- **Opus:** Calendar buckets in host-local time (day, ISO week, month, year differ), as today's code; a run with no completed re-read re-reads.
- **Bears on it:** SR-011 (AC: 'at or after its period has elapsed since the last completed full re-read'; 'a never schedule never does').
- **Recommendation:** Take A. SR-011 decides it; O followed the code. Today N with no history re-reads and the time is stamped whenever a re-read was due, even partly (gap M07).
- **Level:** design (coordinator); settled by SR-011

### K02. Configuration description version

- **Astra:** Bump to ConfigVersion 3 (adds SpaceView, uniform versioning); keep a v2 meaning table; asks whether calendar scheduling is v2's meaning.
- **Opus:** Stay at 2: an optional key with a meaning-preserving default does not bump (the published description already says so of CompressProbe).
- **Bears on it:** SR-123, SR-135, SR-011, SR-097; ruling 'Configuration: version stated, unknown keys refused'.
- **Recommendation:** Stay at 2. The documented v2 meaning of D/W/M/Y is 'daily, weekly, monthly, yearly', which elapsed periods satisfy, so SR-011's rule does not change v2's meaning; SpaceView defaults off. If the Owner reads calendar buckets as v2's meaning, SR-123 forces version 3 with two schedule semantics kept forever.
- **Level:** OWNER (what a v2 document means; integrators see the version)

### K03. SpaceView value kind

- **Astra:** Enum off|on.
- **Opus:** Boolean, default false.
- **Bears on it:** SR-097.
- **Recommendation:** Boolean, matching AllowEmptySource and CompressEnabled; BrowseView is an enum only because it has a second non-off value.
- **Level:** design (coordinator)

### K04. Removal dry run

- **Astra:** Kept: -WhatIf with Prune and FILEBACKUP_DRY_RUN in the container.
- **Opus:** Dropped: code beyond the design; -WhatIf becomes a bad request.
- **Bears on it:** No SR asks for it; listed as a possible missing need at the SR merge. Implementation-born.
- **Recommendation:** Do not drop silently: it is a working, documented feature a host may call. Either the Owner adds a need (then a dry-run LLR and the form stay) or it is retired with a release note. Until ruled, keep it out of the LLRs and list it under code beyond the design.
- **Level:** OWNER (removes a feature hosts can see)

### K05. Full-payload check by default; the -Deep switch (Opus call 4)

- **Astra:** Full payload check is the default; -Deep still listed in the request form.
- **Opus:** Full payload check is the default; -Deep dropped from the form.
- **Bears on it:** SR-049 (altered content must be reported), SR-064 (8 h budget; about 3 h of reading at the reference host).
- **Recommendation:** Both agree on the default, so SR-049 settles it. Keep -Deep accepted with no meaning, like -ExitCode, so existing callers are not refused.
- **Level:** design (coordinator); the cost change is worth telling the Owner

### K06. Removal overrides in the request

- **Astra:** -DiscardUnreferencedData and -AllowUnverifiedIndex listed as launch switches.
- **Opus:** Not in the form; module-level overrides are code beyond the design.
- **Bears on it:** SR-046 refuses those cases without exception. The entry point has no such switches today.
- **Recommendation:** Take O. A's switches do not exist at the entry point; retire the module overrides or keep them test-only.
- **Level:** design (coordinator)

### K07. Permission to fetch the hashing component

- **Astra:** 'The permitted package fetch'; an auto-install switch kept with meaning.
- **Opus:** Fetched without a question, attended or not; -AutoInstallDeps accepted with no meaning.
- **Bears on it:** SR-132 ('attended or not, either obtains it ... or is refused'); SR-016.
- **Recommendation:** Take O. Today attended runs prompt and unattended runs need the switch (gap M15).
- **Level:** design (coordinator); settled by SR-132

### K08. A volume whose free space cannot be measured (backup and restore)

- **Astra:** Refused with 2 (needed, free and volume named).
- **Opus:** Not refused; the record says the check was not made (today's behaviour on both routes).
- **Bears on it:** SR-052 and SR-023 refuse only when demand exceeds free space; silent on unknown. Ruling: 2 = precondition not met.
- **Recommendation:** Take O. Refusing on unknown would stop every run on a share or mount that hides its free space, a precondition the owner cannot always fix; the record line keeps it visible.
- **Level:** OWNER (changes the outcome an owner sees on such hosts)

### K09. Declared allowance values

- **Astra:** Declared numbers: allocation rounding (observed unit, else 64 KiB), 4096 bytes per folder and per record entry, 16 MiB fixed, twice the largest expanded object (restore) or the largest temporary objects (backup).
- **Opus:** 'A declared allowance' without numbers; restore scratch is the largest compressed item's expanded size.
- **Bears on it:** SR-052, SR-023 ('a declared allowance').
- **Recommendation:** Take A's numbers: an allowance the SR calls declared must be stated somewhere; review the values in round 4 against the harvested test edges.
- **Level:** design (coordinator)

### K10. When the backup's space plan runs

- **Astra:** A read-only plan over every location before any root, claim, log, record or staging is created; revalidated after the claim is taken.
- **Opus:** After the change set is known and before anything is written.
- **Bears on it:** SR-052 ('nothing is created or changed on the volume'); SR-085.
- **Recommendation:** Take A. O's order lets the claim file, staging and the log exist before a refusal; the revalidation under the claim closes the race.
- **Level:** design (coordinator)

### K11. Missing or unreadable run-state record with a populated backup (Opus call 1)

- **Astra:** Recover the prior completion date from durable evidence, or refuse.
- **Opus:** Always rebuild: completion time from the evidence's Written time, a full re-read due, the rebuild reported.
- **Bears on it:** SR-035 (names the change-detection state only), SR-005, SR-082; ruling 'missing change-detection state: re-derive from the backup's record, then report it'.
- **Recommendation:** Take O: the evidence time is the completion time and the ruling's spirit is 'rebuild and report'. Ask the Owner to confirm that the ruling extends to the run-state record (today the run is refused, value 1).
- **Level:** OWNER (confirm the ruling's reach)

### K12. How a stale or foreign change-detection record is caught

- **Astra:** Bind the record to a source/store identity and a completed generation (new fields).
- **Opus:** Reconcile per path against the backup's latest record; the backup's values win where they differ.
- **Bears on it:** SR-035; SR-084 (form changes).
- **Recommendation:** Take O: no new form, and any disagreement with the backup's own record is caught whatever its cause.
- **Level:** design (coordinator)

### K13. One path separator and the migration (Opus call 2)

- **Astra:** Backslash in the record (form); no gap listed.
- **Opus:** Backslash; lists the gap and the migration: a Linux-written store sees one full rewrite of its latest record and one extra saved state on the first run after the change.
- **Bears on it:** SR-033, SR-136, SR-114; code: a Linux run writes '/' today (confirmed).
- **Recommendation:** Take the backslash (both agree). The migration is real for container deployments and must be flagged downstream.
- **Level:** OWNER (a one-time extra saved state in every Linux-written store)

### K14. Positive age evidence (Opus call 3)

- **Astra:** An immutable state-format descriptor per state (STATE-FORMAT.json) bound into publication evidence; current states always carry a header-only folder record; kit revision is never age evidence.
- **Opus:** The state's own kit revision (for missing completeness evidence) and evidence version 3 with DirRows/LinkRows (for folder and link records).
- **Bears on it:** SR-116, SR-146, SR-117, SR-084, SR-039.
- **Recommendation:** Hybrid. O's evidence version 3 is immutable (a refresh never copies evidence) and settles folder and link records with no new file. For a state with no evidence at all, O's kit revision fails once a refresh replaces the kit (A's point, and O's own LLR-131), and A's descriptor exists in no state written so far. So the refresh must keep the state's original kit revision readable, or must refuse to refresh a state that predates evidence. Coordinator to choose; the release that introduced evidence must be read from history.
- **Level:** design (coordinator); owner-visible if a refreshed old state starts refusing

### K15. Folder record when a state has none

- **Astra:** Always present, header-only when empty.
- **Opus:** Present only with rows (today).
- **Bears on it:** SR-116, SR-146, SR-084.
- **Recommendation:** Take O together with evidence DirRows=0 (K14). It keeps today's form, and old kits need no change.
- **Level:** design (coordinator)

### K16. Folder attribute separator

- **Astra:** Semicolon.
- **Opus:** Comma (today; both routes split on ',').
- **Bears on it:** SR-084.
- **Recommendation:** Take O. A semicolon breaks every kit already in a backup for multi-attribute rows.
- **Level:** design (coordinator); A's value is an error against the code

### K17. Link record form (Opus call 5)

- **Astra:** Columns RelativePath, Kind {directory-symlink, junction}, TargetScope {source-relative, external-absolute}, Target (original absolute target).
- **Opus:** Columns RelativePath, LinkKind {symlink, junction}, TargetClass {inside-source, own-location}, Target (absolute path as resolved at backup time); file LINKS.csv present only with rows.
- **Bears on it:** SR-150, SR-151, SR-152; ruling: an inside link is re-pointed under the target, an own-location link is rebuilt to its original path.
- **Recommendation:** Take O: its class names are the ruling's two classes. 'Original path' means where the link led, as resolved. A separate file keeps old kits safe (SR-084), as both say.
- **Level:** design (coordinator)

### K18. Bounded wait for an unreachable link target

- **Astra:** 60 seconds per remote resolution or enumeration request.
- **Opus:** 'The run's bounded wait', no value.
- **Bears on it:** SR-137 ('within the run's bounded wait').
- **Recommendation:** Take A's value. The SR requires a bound, and only A declares one.
- **Level:** design (coordinator)

### K19. Durability of record publication

- **Astra:** Flush the temporary to stable storage before the rename.
- **Opus:** No flush; a power loss may lose the newest record, reported later as damage.
- **Bears on it:** SR-082 (AC: power removed during writing; 'never a torn one').
- **Recommendation:** Take A. O's choice contradicts SR-082's AC.
- **Level:** design (coordinator); settled by SR-082

### K20. Completing an interrupted publication

- **Astra:** A durable publication intent (old and new record identities, required content keys) written before any change.
- **Opus:** Write order: record temporary, evidence of the temporary, rename record, rename evidence; the next run publishes a matching evidence temporary.
- **Bears on it:** SR-082, SR-110.
- **Recommendation:** Take O's write order as the mechanism (minimal, positively identified, no new artifact). Carry A's other concern as its own LLR: earlier content stays reachable until the replacing state is published (orphan ii, gap M53).
- **Level:** design (coordinator)

### K21. Fencing a resumed former owner

- **Astra:** Revalidate ownership before every publication, move, delete and record replacement.
- **Opus:** Five fixed boundaries.
- **Bears on it:** SR-144 ('changes no file the successor wrote or published').
- **Recommendation:** Between O's fences a resumed run can still move or delete. Fence before every destructive step (move, delete, replace, publish). Object creation through a temporary name that never replaces an existing name needs no fence, which keeps the cost off the million-file path.
- **Level:** design (coordinator)

### K22. Readers while a writer holds the backup

- **Astra:** Readers pin a complete generation; writers defer disposal of pinned supply (new read-session form).
- **Opus:** Readers take no claim and read only published states, which 'never change in place'.
- **Bears on it:** SR-106, SR-103, SR-059.
- **Recommendation:** O's premise is false (repair renames objects, the collapse blanks references and deletes duplicates, a removal deletes a folder). A's pinning needs reader-visible state that the shell route cannot keep. Middle course: no claim and no reader artifact; a reader that finds a location vanished re-resolves by content key, and one that reads a record whose evidence changed mid-read re-reads it (bounded).
- **Level:** design (coordinator)

### K23. Kit refresh mechanism

- **Astra:** Refresh the root's kit from the installed program first, then stage a complete kit per state and activate it as a whole.
- **Opus:** Copy each kit file through a temporary name and rename, never deleting (an older state may then hold both launcher names).
- **Bears on it:** SR-117, SR-110; code: copies the root's existing kit directly, no temporary (confirmed).
- **Recommendation:** Union: source is the installed program's kit; per-file temporary plus rename, never deleting (O); the revision marker files are written last, so a mixed kit is detectable rather than silent (A's concern, at lower cost).
- **Level:** design (coordinator)

### K24. Liveness second-sample wait

- **Astra:** max(90, min(declared cadence, 600) + 30) seconds (up to 630).
- **Opus:** Declared cadence + 30, between 90 and 600 seconds.
- **Bears on it:** SR-075; code uses A's formula.
- **Recommendation:** Take A (matches the code; no requirement asks for a change).
- **Level:** design (coordinator)

### K25. Container truthy values

- **Astra:** Exactly 1, true, TRUE, True, yes, YES, Yes.
- **Opus:** 1, true or yes in any case.
- **Bears on it:** SR-048; the shipped entry script uses A's exact set.
- **Recommendation:** Take A.
- **Level:** design (coordinator)

### K26. Container scratch space

- **Astra:** All scratch inside the writable working-state mounts; today's host temporary use is a gap.
- **Opus:** /tmp is a writable scratch mount, possibly in memory (the shipped compose file mounts it as tmpfs).
- **Bears on it:** SR-130 ('writes nowhere else').
- **Recommendation:** Take O with /tmp declared in the mount form, and have the reviewers check that SR-130's wording admits a non-persistent scratch mount. If it does not, A's routing is the fix.
- **Level:** design (coordinator); SR-130 wording to reviewers

### K27. A refused configuration and the existing global record

- **Astra:** No change at all to an existing log (lists today's append as a gap).
- **Opus:** Never created or truncated; the refusal is appended to an existing global record.
- **Bears on it:** SR-018 (AC: 'an existing log is not truncated').
- **Recommendation:** Take O. SR-018 forbids truncation, not an appended refusal line, and the appended line is how the owner learns of the refusal.
- **Level:** design (coordinator)

### K28. Restored files made writable (legacy LLR-077)

- **Astra:** Retired: read-only state is outside the fidelity contract; needed writability is covered by verification and time stamping.
- **Opus:** Kept under SR-010.
- **Bears on it:** SR-010, SR-056, SR-066. Implementation-born (orphan i), done today on both routes.
- **Recommendation:** Keep LLR-077 as a child of LLR-056, reworded as: a stored item's protection never blocks verification or the time stamp, and is not handed to the restored file. Its meaning survives, and without it the verification fails on read-only stores.
- **Level:** design (coordinator)

### K29. Shape of the restore tree

- **Astra:** LLR-008 is a parent carrying eight SRs, with children 010, 029, 050, 056 and 068.
- **Opus:** Flat: each row carries its own SR.
- **Bears on it:** Pointer rules: a child's SR is derived up its chain; one obligation per row.
- **Recommendation:** Take O. Under A's shape every child inherits eight SRs, which blurs coverage and the blast radius.
- **Level:** design (coordinator)

### K30. Where the already-compressed type list lives

- **Astra:** Enumerated in LLR-004.
- **Opus:** 'One list, defined once'; the user manual's table equals the live list; no list in the spine.
- **Bears on it:** SR-081 ('a type declared as already compressed').
- **Recommendation:** Take A's enumeration in LLR-004: the declaration needs one spine home, and the manual is generated from or checked against it.
- **Level:** design (coordinator)

### K31. Which files the media rate is measured for

- **Astra:** Every file for which the tool gives a duration.
- **Opus:** Each file whose content is read in the run; the rate travels with the entry.
- **Bears on it:** SR-098, SR-113 (run time follows what changed).
- **Recommendation:** Take O. Running the probe over every file each run breaks SR-113.
- **Level:** design (coordinator)

### K32. A restore tool present but failing its self-test at admission

- **Astra:** (A states tool availability and version as 2, and a known-good probe to tell archive damage from tool failure.)
- **Opus:** Host fault, 4.
- **Bears on it:** SR-040; ruling: 4 = busy or a host fault mid-work; 2 = needs a person, precondition not met.
- **Recommendation:** Return 2 at admission. Nothing is mid-work yet, and a retry will not fix a broken tool. O's 4 contradicts the outcome-vocabulary ruling.
- **Level:** design (coordinator); ruling decides

### K33. Writing a stored object where leftovers may sit

- **Astra:** Write to a private temporary object, verify the content key, publish without replacing any object still claimed.
- **Opus:** Clear unreferenced debris at the name first, then write (the archive tool appends to an existing archive).
- **Bears on it:** SR-003, SR-082, SR-059.
- **Recommendation:** Take A's temporary-then-publish (no delete on the hot path); O's hazard (appending to debris) cannot occur when the archive is built at a fresh temporary name.
- **Level:** design (coordinator)

### K34. macOS double-click

- **Astra:** The launcher must arrive launchable; a Windows-written kit carried by zip needs a manual chmod today, which falls short of SR-072.
- **Opus:** 'Runs the shell route without needing an executable bit on the restorer' (true), silent on the launcher's own bit.
- **Bears on it:** SR-072 (double-click on macOS presents a folder choice).
- **Recommendation:** A is right about the gap (the launcher file says so itself). The fix may lie outside the code (how a kit reaches a Mac), so the Owner decides whether SR-072's double-click holds for zip-transferred kits.
- **Level:** OWNER (support boundary)

### K35. Listing location on the backup's volume

- **Astra:** Not required.
- **Opus:** Refused when not on the backup's volume (today's code).
- **Bears on it:** SR-063 does not ask. Implementation-born (orphan i).
- **Recommendation:** Keep only if the browse view's relative links need it (they cannot cross drives on Windows). State that reason in the LLR, or drop the rule.
- **Level:** design (coordinator)

### K36. Where on-disk names live

- **Astra:** Leaf names (MANIFEST.csv, DIRECTORIES.csv, LINKS.csv, Temp.lock, RUN.inprogress, FileBackupState.json, STATE-FORMAT.json) in LLRs; interfaces state roles.
- **Opus:** Names in the interface form; LLRs refer to them by role.
- **Bears on it:** Brief: on-disk data names that are the agreed form are allowed in interface data; single home.
- **Recommendation:** Take O. The name is form, both sides spell it, and a rename then touches one row.
- **Level:** design (coordinator)

### K37. Folder-only or link-only change and the saved state

- **Astra:** A difference in the folder or link record is a change and keeps a saved state.
- **Opus:** Change set is files plus heals; silent on folder-only changes.
- **Bears on it:** SR-005 ('when a run changes the backed-up state'), SR-065.
- **Recommendation:** Take A. The folder record is part of the backed-up state; today a new empty folder alone discards the prior folder record (gap M48).
- **Level:** design (coordinator)

### K38. Component cuts

- **Astra:** Store coordination and content resolution as top-level components; capture and change detection one component; container adapter under launch.
- **Opus:** Guard under the backup engine; index under removal; restore search under entry restoration; capture and change detection separate; container on its own.
- **Bears on it:** Responsibilities the SRs demand; the kit-independence rule.
- **Recommendation:** Take O's tree (proposed tree above). A's shared 'content resolution' would make the restore kit depend on the backup-side index unless it moves into the store format; revisit only if K22 goes A's way.
- **Level:** design (coordinator)

### Outcome values against SN-045, SN-026 and the outcome-vocabulary ruling

Every outcome value either side assigns was checked against the ruling (0 complete; 1 part failed or content missing; 2 needs a person; 3 damaged record; 4 retry later: busy, or a host fault mid-work), against SN-045 (distinct outcomes for every backup, removal and check; machine-readable findings) and against SN-026 (one restore class per failure on every system).

- Agreeing and conforming on both sides: busy 4; claim contention or I/O 4 and denial or unusable location 2; configuration refused 2; missing runtime, component or tool 2; capacity 2; empty source 2; retired or unrecognised form 2; read-only source 2; leftovers 2 over 3 over 4; removal 3 only when failing evidence is the sole cause, else 2; check findings 1; lost claim on resume 1; restore: collision 1, escaping entry 3, damaged current folder metadata or time 1, older state with the check not made 0, not-a-record 2 over 3; distinct values always, the old switch accepted and meaning nothing.
- Opus is more complete on the ruling's 'every operation': its value set covers the saved-state report and the view rebuild, which Astra omits (today the report always returns 0).
- Opus LLR-139 gives 4 to a restore tool that is present but fails its self-test at admission. Under the ruling that is 2: nothing is mid-work, and a retry will not fix the tool (K32).
- Opus's unclassified-error rule (2 before any change, 4 after) conforms to the ruling's letter. A host that retries on 4 will then retry a program fault; acceptable, because the host alerts once retries are exhausted. Astra states no rule.
- The unmeasurable volume (K08) is the only point where the two sides give different values for the same case; both conform to the vocabulary, and the choice is the Owner's.

## 4. LLR clusters

One obligation per cluster. 'Merged' is the id the aligned tier uses: a kept legacy id where its meaning survives, otherwise a new id from LLR-095 up (no retired id reused). 'Parent' is set for a child row, whose SRs column shows the SRs derived up its chain (a child carries no sr_refs, so an SR a side attached to a would-be child is reached through another row instead; the coverage count includes this). Ids in brackets under Astra state part of the obligation inside a row clustered elsewhere.

| # | Merged | Parent | Obligation | SRs | Astra | Opus | Verdict | Note |
|---|---|---|---|---|---|---|---|---|
| 1 | LLR-043 |  | Every operation ends with one value of the shared vocabulary | SR-043 | LLR-043 | LLR-043 | union | O adds the full operation list (report and view rebuild included, per the ruling 'every operation'), the precondition list and the unclassified-error rule (2 before any change, 4 after). A adds nothing O lacks. Move the multi-location fold out (to LLR-014) so it has one home. |
| 2 | LLR-014 |  | Configured locations run independently and fold into one value | SR-014, SR-095 | LLR-014 | LLR-014 | union | O carries the fold rule; A adds that the full location set is resolved and validated before admission and that a multi-location configuration draws no warning. |
| 3 | LLR-016 |  | An unattended operation never asks | SR-016 | LLR-016 | LLR-016 | take O | Same obligation; O enumerates the session signals and the per-operation scope. Today redirected or closed input is not detected (gap M15). |
| 4 | LLR-096 |  | The report and the check write one findings document on standard output | SR-104 | - [LLR-047, LLR-049] | LLR-096 | take O | A states SR-104 only through interface forms and the sr_refs of its check and report rows. O adds 'nothing else on standard output' and the repaired flag. |
| 5 | LLR-048 |  | Container actions map onto the same request and outcome | SR-048, SR-142 | LLR-048 | LLR-048 | union; conflicts K04, K25 | A also bundles mounts and identity (moved to the container-access cluster) and keeps the dry-run variable; O forces notification off and the unattended declaration (both true of today's entry script). |
| 6 | LLR-042 |  | Configuration validated against the one catalogue before anything is touched | SR-018 | LLR-042 | LLR-042 | take O | A's row carries five SRs (018, 042, 123, 135, 129); split per O so each SR's obligation has its own row. Both: closed keys, kind-checked values, first fault in document order, defaults materialised. |
| 7 | LLR-018 | LLR-042 | A configuration location naming no document is refused | SR-018 | - [LLR-042] | LLR-018 | take O (child) | A merged this into LLR-042; the legacy meaning survives and O's child adds 'creates nothing, the global record included'. |
| 8 | LLR-063 | LLR-042 | A retired setting is refused by name, as retired | SR-018 | - [LLR-042] | LLR-063 | take O (child) | A retired LLR-063 into LLR-042 text; SR-018's AC names the retired-by-name message, a distinct decision. |
| 9 | LLR-098 |  | An older supported description version keeps its meaning | SR-123 | - [LLR-042] | LLR-098 | take O; conflict K02 | A states a version-specific meaning table inside LLR-042. |
| 10 | LLR-099 |  | Every configuration document states its description version | SR-135 | - [LLR-042] | LLR-099 | take O | A inside LLR-042. O adds that the helper writes the current version. |
| 11 | LLR-100 |  | A configuration carrying a readable credential is refused | SR-129 | - [LLR-042, LLR-104] | LLR-100 | take O | A inside LLR-042 and LLR-104. |
| 12 | LLR-101 |  | The published description and the launch checks give the same verdict | SR-042 | - [LLR-042, LLR-027] | LLR-101 | take O | A inside LLR-042 and LLR-027. |
| 13 | LLR-102 |  | The shipped example configuration is accepted | SR-134 | - [LLR-027] | LLR-102 | take O | A inside LLR-027. |
| 14 | LLR-103 |  | Configured locations may not overlap a source or the store | SR-138, SR-063, SR-149 | LLR-095 | LLR-103 | union; conflict K35 | Both physical, across every set, before anything is created. O adds drive-root sources, foreign content left in place, and 'listing location not on the backup's volume' (today's code; no SR asks, K35). |
| 15 | LLR-104 |  | A read-only source with no state location elsewhere is refused up front | SR-140 | - [LLR-095] | LLR-104 | union | A inside LLR-095 (names the SourceStatePath setting). O: an access query that writes nothing, no probe file. |
| 16 | LLR-037 |  | Tool locations and compression effort | SR-019, SR-081 | LLR-037 | LLR-037 | union | Same precedence and the exact single-digit rule; O adds that reading the effort never raises (the restore-safe library reads it), A that restores and non-compressing actions ignore an invalid value (both say so). |
| 17 | LLR-020 |  | The runtime and every needed tool are checked before any location is touched | SR-019, SR-133 | LLR-020 | LLR-020 | union | A also covers SR-132 (moved to the next cluster). O adds the runtime floor; neither side's code has a runtime check (gap M14). |
| 18 | LLR-105 |  | The hashing component is obtained on first use, or the launch is refused | SR-132 | - [LLR-020] | LLR-105 | take O; conflict K07 | A inside LLR-020 ('the permitted package fetch'). |
| 19 | LLR-015 |  | A run's outcome is sent where set up; a send failure changes nothing | SR-015, SR-127 | LLR-015 | LLR-015 | take O | Same; O adds login only where the configuration carries one (owner ruling: SMTP login only where the server needs one). |
| 20 | LLR-106 |  | Notification credentials are never written in readable form | SR-128 | LLR-104 | LLR-106 | union | A adds sanitising provider failures; A's SR-129 part goes to the readable-credential cluster. |
| 21 | LLR-095 |  | No record is created or truncated before the configuration is admitted | SR-018 | - [LLR-042] | LLR-095 | take O; conflict K27 | A states 'before creating or changing any location or log' inside LLR-042 and lists appending as a gap. |
| 22 | LLR-107 |  | Each run's record names every change and failure, with counts | SR-124 | LLR-103 | LLR-107 | union | A's LLR-103 carries four SRs (124, 125, 126, 089); split per O. |
| 23 | LLR-108 |  | Progress at least every two minutes of active time | SR-125 | - [LLR-103] | LLR-108 | take O | Same in A LLR-103. |
| 24 | LLR-097 |  | Every refusal states what was found and what to do | SR-126 | - [LLR-103] | LLR-097 | take O | Same in A LLR-103; A's secret-sanitising clause goes to the credentials cluster. |
| 25 | LLR-001 |  | Every entry is walked; only the declared exclusions are left out | SR-001, SR-074 | LLR-001 | LLR-001 | union | A's LLR-001 also states change detection (moved to the change-set cluster) and SR-089 naming (moved to the uncapturable cluster). |
| 26 | LLR-078 | LLR-001 | Volume system folders are left out only at a volume-root source | SR-074 | LLR-078 | LLR-078 | take O (child of LLR-001) + A clause | A adds that an unknown volume-root status defaults to capture; O that every store enumeration applies the same test. |
| 27 | LLR-055 |  | A name invalid on Windows or Linux is refused and named | SR-055 | LLR-055 | LLR-055 | union | O adds that a non-portable folder name is left out of the folder record with a warning. |
| 28 | LLR-109 |  | Folder links: followed outside, recorded inside or into own locations | SR-137, SR-150, SR-151 | LLR-105, LLR-106 | LLR-109 | union; conflicts K17, K18 | One classification decision (O); A splits following (105) from recording (106). A adds the 60-second bounded wait per remote request (K18); O adds the ancestor test 'inside a followed outside folder too'. |
| 29 | LLR-110 | LLR-109 | A recorded link carries its kind and where it led | SR-150, SR-151 | - [LLR-106] | LLR-110 | take O; conflict K17 | A states it inside LLR-106. |
| 30 | LLR-067 |  | A briefly unreadable file is retried within a bounded per-location limit | SR-067, SR-090 | LLR-067 | LLR-067 | union | Same values (3 attempts, 250 ms then 1000 ms, 60 s per location, a folder at the destination is permanent); both cover the digest read, which today's code does not (gap M29). |
| 31 | LLR-111 |  | A file or folder that cannot be captured is named and keeps its earlier content | SR-089, SR-091 | - [LLR-001, LLR-055, LLR-067] | LLR-111 | take O | A states it across LLR-001, LLR-055 and LLR-067. |
| 32 | LLR-065 |  | Empty and attributed folders are recorded | SR-065, SR-122 | LLR-065 | LLR-065 | union; conflicts K15, K16 | A's LLR-065 also applies the record at restore (split to the folder-application cluster). |
| 33 | LLR-112 |  | A run never changes the source | SR-093 | LLR-096 | LLR-112 | union | A's row also carries SR-094/139/148 (to the record-location cluster). |
| 34 | LLR-036 |  | A source that suddenly looks empty is refused unless declared | SR-036 | LLR-036 | LLR-036 | union | Both value 2. O adds that a source whose only files were left out still counts as showing files; A that an unreadable source is distinguished from an empty one. |
| 35 | LLR-021 |  | Source-derived paths are taken literally | SR-021 | LLR-021 | LLR-021 | union | A's cross-host clause moves to the one-store-form cluster; A constrains IF-014, O nothing (an LLR need not name an interface). |
| 36 | LLR-113 |  | The change set comes from size, time and, when re-read, content | SR-088, SR-105, SR-024 | - [LLR-001, LLR-011] | LLR-113 | take O | A states it inside LLR-001 and LLR-011 (O split legacy LLR-001's diff out because it serves different SRs). |
| 37 | LLR-011 |  | The re-read schedule decides the same way every time | SR-011 | LLR-011 | LLR-011 | take A; conflict K01 | SR-011 says 'at or after its period has elapsed since the last completed full re-read': A's elapsed periods meet it, O's calendar buckets follow today's code. A also keeps N as never with no history (the code re-reads). |
| 38 | LLR-114 |  | An unusable change-detection record is rebuilt from the backup's own record | SR-035 | LLR-113 | LLR-114 | take O; conflict K12 | A binds the record to a source/store identity and generation (new form); O reconciles per path against the backup's latest record. Both log the rebuild. |
| 39 | LLR-115 |  | The change-detection record lives at the source root unless configured elsewhere | SR-139, SR-148, SR-094 | - [LLR-096] | LLR-115 | take O | A inside LLR-096. |
| 40 | LLR-035 |  | A missing run-state record never makes a populated backup a first backup | SR-035, SR-005 | - [LLR-028] | LLR-035 | take O; conflict K11 | A states it inside LLR-028 ('recover the prior state date from durable evidence or refuse'). |
| 41 | LLR-028 | LLR-005 | A saved state is named by the completion time of the state it holds | SR-005 | LLR-028 | LLR-028 | union (child of LLR-005) | Both: written after publication, before the collapse; today the name comes from the previous run's start time (gap M06, found by O only). |
| 42 | LLR-003 |  | Identical content is stored once | SR-003 | LLR-003 | LLR-003 | union | A adds that a blank or missing location is demand, not supply (shared with LLR-053). |
| 43 | LLR-058 | LLR-003 | Each content group has one owner and one stored form, decided once | SR-003 | LLR-058 | LLR-058 | union (child of LLR-003) | Same election (shortest path, ordinal tie). A adds create-through-temporary-then-publish without replacing a claimed object (see K33). |
| 44 | LLR-117 | LLR-003 | A stored object is never merged into leftovers at its name | SR-003 | - [LLR-058] | LLR-117 | union; conflict K33 | A's private-temporary publication in LLR-058 serves the same hazard. |
| 45 | LLR-053 |  | Lost content is stored again; adoption needs content actually present | SR-053, SR-108 | LLR-053 | LLR-053 | union | Same. |
| 46 | LLR-086 |  | Compression decided by measured saving, by file type where nothing is measured | SR-081, SR-096, SR-111 | LLR-086 | LLR-086 | take O | Same order and values (floor 256 KiB inclusive, 0.90 aggregate); O adds the decision's reason names. Today a file of exactly 262144 bytes is probed (gap M57, found by A only). |
| 47 | LLR-004 | LLR-086 | One list of already-compressed types is the file-type rule | SR-081 | LLR-004 | LLR-004 | union (child of LLR-086); conflict K30 | O's child structure, A's explicit list (the values need one spine home). |
| 48 | LLR-116 | LLR-086 | The measurement samples three windows and never fails a run | SR-081 | LLR-109 | LLR-116 | union | Same geometry and bounds; A names the codec (fastest Brotli level), O describes it. Keep the named algorithm: it fixes the measured ratio, and it is not a code symbol. |
| 49 | LLR-052 |  | A backup refuses before writing when a volume lacks the space it needs | SR-052 | LLR-052 | LLR-052 | conflicts K08, K09, K10 | Same demand terms and value 2. Disagree on an unmeasurable volume, on declared allowance values and on when the plan runs. |
| 50 | LLR-135 |  | Volume identity and free space are measured the same way on every host | SR-052, SR-023 | - [LLR-052, LLR-023] | LLR-135 | take O + A's allocation unit | A states it in IF-019/020 data and its capacity rows. |
| 51 | LLR-005 |  | A changing run keeps the previous state; an unchanged run adds none | SR-005, SR-100 | LLR-005 | LLR-005 | union; conflict K37 | A adds folder-only and link-only changes to the change set (today a new empty folder alone adds no saved state, gap M48). |
| 52 | LLR-051 |  | Content leaves the latest state only when no final-record entry claims it | SR-059 | LLR-051 | LLR-051 | take O | Same rule at both removal sites; A merged legacy LLR-006 and LLR-059 into it. |
| 53 | LLR-059 |  | Superseded content is kept with the saved state | SR-059, SR-005 | - [LLR-051, LLR-005] | LLR-059 | take O | A merged it into LLR-051; O's row states the preservation itself, which the claim test does not. |
| 54 | LLR-150 |  | Earlier content stays reachable until the replacing state is published | SR-082, SR-059, SR-041 | - [LLR-115, LLR-041] | - | take A (orphan ii) | A states it inside LLR-115 and LLR-041; O misses it. Today removed and superseded objects move into the staging area before the new latest record is published, so a kill there leaves a witnessed record whose bytes only staging holds (gap M53, confirmed in code). |
| 55 | LLR-041 |  | Earlier content that cannot be placed stays restorable, and the run fails | SR-041 | LLR-041 | LLR-041 | union | Both: continue per file, report part failed, publish no saved state missing content. |
| 56 | LLR-087 |  | A record is published whole or not at all | SR-082, SR-038 | LLR-087 | LLR-087 | take A on durability; conflict K19 | A flushes before the rename; O says it does not, accepting a torn newest record after power loss, which SR-082's AC forbids. |
| 57 | LLR-118 | LLR-087 | An interrupted publication is completed when positively identified | SR-082 | LLR-115 | LLR-118 | conflict K20 | O: evidence temporary written before the record rename; A: a durable publication intent with old/new identities. |
| 58 | LLR-038 |  | Every record carries its own completeness evidence | SR-038 | LLR-038 | LLR-038 | union; conflict K14 | O adds the folder- and link-record row counts to the evidence. |
| 59 | LLR-007 |  | Every state carries a restore kit | SR-007 | LLR-007 | LLR-007 | union | A adds 'before the state is visible' and the kit's closed dependency set; A's SR-131 part goes to the notices cluster. |
| 60 | LLR-119 |  | Third-party components travel with their licences and notices | SR-131 | - [LLR-007] | LLR-119 | take O | A inside LLR-007. |
| 61 | LLR-120 |  | No write leaves an existing kit unable to read its state | SR-084 | - [LLR-060, LLR-076, LLR-111] | LLR-120 | take O | A spreads SR-084 over LLR-060, LLR-076 and LLR-111. |
| 62 | LLR-076 | LLR-120 | One kit revision, moved whenever a kit file changes behaviour | SR-084 | LLR-076 | LLR-076 | union (child of the SR-084 row) | A's coherent-refresh clauses move to the kit-refresh cluster. |
| 63 | LLR-026 | LLR-003 | Content duplicated across saved states is collapsed to one copy | SR-003 | LLR-026 | LLR-026 | union (child of LLR-003) | A adds: remove a redundant copy only after the keeper is verified and every dependent state still resolves (a SR-059 safeguard O lacks). |
| 64 | LLR-121 |  | Every host writes and continues one store form | SR-033, SR-136, SR-114 | - [LLR-021, LLR-024] | LLR-121 | take O; conflict K13 | Both choose the backslash separator (A in its record form); only O lists the gap (today's Linux writer uses '/') and the migration it causes. |
| 65 | LLR-090 |  | One changing operation at a time holds the backup through the OS claim | SR-085, SR-086, SR-107 | LLR-090 | LLR-090 | union | Same primitive (3 attempts 250 ms apart, never unlinked). A also states the failure classes (split to the next cluster). |
| 66 | LLR-122 | LLR-090 | A claim that cannot be taken is classified and touches nothing | SR-086 | - [LLR-090] | LLR-122 | take O | Same values in A LLR-090 (contention or I/O 4; denial or unusable location 2). |
| 67 | LLR-091 | LLR-090 | A backup holds the claim from its first store read to its last write | SR-085 | LLR-091 | LLR-091 | take O (child of LLR-090) | A's LLR-091 also absorbs removal, repair, refresh and the reader rule; split per legacy ids. |
| 68 | LLR-092 | LLR-090 | A removal holds the claim for its whole batch | SR-085 | - [LLR-091] | LLR-092 | take O (child of LLR-090) | A merged it into LLR-091; each window has its own start and end point. |
| 69 | LLR-094 | LLR-090 | A repair and a kit refresh hold the claim | SR-085 | - [LLR-091] | LLR-094 | take O (child of LLR-090) | A merged it into LLR-091. |
| 70 | LLR-093 | LLR-090 | The claim file is never deleted and is invisible to every reader | SR-085 | - [LLR-090, LLR-022] | LLR-093 | take O (child of LLR-090) | A states it in LLR-090 and LLR-022. |
| 71 | LLR-123 |  | Checks, the report and restores take no claim and still complete | SR-106, SR-103 | LLR-116 [LLR-091] | LLR-123 | conflict K22 | A adds a pinned read generation and writer-side deferral (new IF-040); O relies on published states not changing in place, which repair, collapse and removal contradict. |
| 72 | LLR-017 |  | An earlier run's leftovers are classified from the disk alone | SR-017, SR-107 | LLR-017 | LLR-017 | union | Same classes and precedence (2 over 3 over 4). A adds the unchanged second sample here; O in LLR-080. |
| 73 | LLR-088 | LLR-017 | Record publication temporaries are not content | SR-017 | LLR-110 | LLR-088 | union (child of LLR-017) | Legacy LLR-088 means the staging allowlist; O kept that meaning. A reused the id LLR-088 for the move-aside reclaim (next-but-one cluster) and minted LLR-110 (child of LLR-022) for this; keep LLR-088 with O's meaning and A's root-scoped, case-exact detail. |
| 74 | LLR-080 |  | A backup's owner record and its age are the liveness evidence | SR-075 | LLR-080 | LLR-080 | union; take A's sample formula (K24) | Same 60 s refresh and 1800 s floor. A is a child of LLR-017; O is top-level because it serves SR-075, not SR-017 (O's rule, adopted). |
| 75 | LLR-124 |  | A provably dead run's leftovers are reclaimed by moving them aside | SR-075, SR-082 | LLR-088 | LLR-124 | union | Same protocol (move aside, re-check identity, fresh staging and record, non-recursive delete, keep on any surprise). |
| 76 | LLR-125 |  | A run whose claim was lost changes nothing more | SR-144 | LLR-108 | LLR-125 | conflict K21 | A fences before every mutation; O at five fixed boundaries. |
| 77 | LLR-045 |  | Content only the removed state holds is re-homed first | SR-045 | LLR-045 | LLR-045 | union | Same election and verification; both refuse a conflicting destination and reuse an identical one. |
| 78 | LLR-046 |  | A removal that could lose content is refused before anything changes | SR-046 | LLR-046 | LLR-046 | union; conflicts K04, K06 | Both collect every cause; values per SR-046 (3 only for failing evidence alone, else 2). A's confinement clauses move to the next cluster. |
| 79 | LLR-126 |  | A removal is confined to the chosen backup | SR-102 | - [LLR-046] | LLR-126 | take O | A inside LLR-046. |
| 80 | LLR-127 |  | An interrupted removal loses nothing and completes when re-run | SR-101 | LLR-098 | LLR-127 | union | A adds resuming the removal's own pre-commit work (today a killed pre-commit removal wedges on its own staging marker, gap M51, found by A only). |
| 81 | LLR-047 |  | The saved-state report gives what each removal would free and move | SR-047 | LLR-047 | LLR-047 | union | Same: figures from the removal's own plan. |
| 82 | LLR-128 |  | The report and a check without repair change nothing | SR-103 | - [LLR-047, LLR-049] | LLR-128 | take O | A inside LLR-047 and LLR-049. |
| 83 | LLR-062 |  | Whole-backup passes grow with the entries; the index with the stored objects | SR-064, SR-112 | LLR-062 | LLR-062 | union | Same linear reference-set audit with filesystem case semantics; O adds the lean index default. |
| 84 | LLR-149 |  | A run's work follows what changed, within the memory bound | SR-113, SR-064, SR-112 | LLR-114 | LLR-149 | union | A adds numbers (index bound 1 GiB, one archive job at a time) and a spill mechanism; keep the numbers, drop the spill until a measurement shows the need (orphan iii part). |
| 85 | LLR-049 |  | A check reports every disagreement between records and what is stored | SR-049 | LLR-049 | LLR-049 | union (Opus call 4: both agree) | Both make reading every distinct stored object once the default check. |
| 86 | LLR-054 | LLR-049 | Missing content is told apart from content missing only from its place | SR-049 | - [LLR-049] | LLR-054 | take O (child of LLR-049) | A states it in LLR-049's dimensions only. |
| 87 | LLR-129 |  | A repair corrects only what is certain | SR-109 | LLR-099 | LLR-129 | union | Same three certain classes and copy-back with a hash before use (owner ruling). |
| 88 | LLR-130 |  | An interrupted repair or kit refresh leaves every state restorable | SR-110 | - [LLR-115, LLR-076] | LLR-130 | union; conflicts K20, K23 | A covers it in LLR-115 and LLR-076. |
| 89 | LLR-131 |  | A kit refresh places the current kit in every state and changes nothing else | SR-117 | - [LLR-076] | LLR-131 | conflict K23 | A inside LLR-076. |
| 90 | LLR-060 |  | A store or state in a retired or unrecognised form is refused by name | SR-061 | LLR-060 | LLR-060 | union | Both value 2 with a fresh-location remedy, a check reports only, a damaged entry is not a retired store, the retired test is positive. |
| 91 | LLR-069 |  | Stored names are encoded, decoded and parsed one way | SR-003, SR-061 | LLR-069 | LLR-069 | union | Same. |
| 92 | LLR-061 |  | Where turned on, the browse view lists every path | SR-062 | LLR-061 | LLR-061 | union | O adds that a rebuild wipes only a folder already holding a generated view (SR-063). |
| 93 | LLR-132 |  | Where turned on, the space view lists files by stored size | SR-097 | LLR-097 | LLR-132 | take O | A's LLR-097 carries four SRs; split per O. |
| 94 | LLR-133 |  | The space view gives a media encoding rate where a playing time is measured | SR-098 | - [LLR-097] | LLR-133 | take O; conflict K31 | A inside LLR-097. |
| 95 | LLR-134 |  | A media measure not taken changes nothing else, and says so | SR-099, SR-133, SR-147 | - [LLR-097] | LLR-134 | take O | A inside LLR-097. |
| 96 | LLR-002 |  | The content digest is computed and written one way everywhere | SR-003, SR-056, SR-033 | LLR-002 | LLR-002 | union | Same. |
| 97 | LLR-022 |  | Infrastructure names count only at a folder's own root | SR-001, SR-074 | LLR-022 | LLR-022 | union | A adds the source-root rule (backup-only names there are owner content), which SR-074's AC states. |
| 98 | LLR-025 |  | Records are read and written one way, on every route | SR-024, SR-033 | LLR-025 | LLR-025 | union | A: an absent record is not an empty state and refuses; O: it reads empty only where the run-state record shows no earlier backup. Compatible; keep both. |
| 99 | LLR-024 |  | An unchanged re-run writes an identical record | SR-024 | LLR-024 | LLR-024 | union | Same. |
| 100 | LLR-068 |  | A stored item's form is decided from its bytes | SR-068 | LLR-068 | LLR-068 | take O (top-level) | A makes it a child of a multi-SR LLR-008 (K29). |
| 101 | LLR-136 |  | Every whole-restore check is made before anything is written | SR-145 | LLR-102 | LLR-136 | union | Same order; A adds deciding the archive-tool need from actual content forms. |
| 102 | LLR-009 |  | A restore target inside the backup is refused | SR-009 | LLR-009 | LLR-009 | union | Both value 2, physical, separator boundary. A's SR-141 part goes to its own cluster. |
| 103 | LLR-079 | LLR-009 | Containment compares physical locations and refuses rather than guesses | SR-009 | - [LLR-009] | LLR-079 | take O (child of LLR-009) | A merged LLR-079 and LLR-072 into LLR-009. |
| 104 | LLR-137 |  | An unresolvable target or one with a parent-folder component is refused | SR-141 | - [LLR-009] | LLR-137 | take O | A inside LLR-009. |
| 105 | LLR-039 |  | The record is verified against its evidence before the target exists | SR-039 | LLR-039 | LLR-039 | union | Same values (3; not-a-record 2; count-only warns; strict refuses). O adds checking a newer evidence version on its known fields. |
| 106 | LLR-138 |  | Only positive evidence excuses a check an older state cannot support | SR-116, SR-146 | LLR-111 | LLR-138 | conflict K14 |  |
| 107 | LLR-139 |  | The tools a route needs are checked before writing | SR-118 | - [LLR-102] | LLR-139 | take O, with value fix K32 | A inside LLR-102. |
| 108 | LLR-023 |  | The target's space is checked, with allowances, before writing | SR-023 | LLR-023 | LLR-023 | conflicts K08, K09 |  |
| 109 | LLR-008 |  | A restore needs only the kit and the documented floor | SR-008, SR-031 | LLR-008 | LLR-008 | take O (flat); conflict K29 | A makes LLR-008 an eight-SR parent of five children. |
| 110 | LLR-071 |  | The shell route behaves the same whatever the host's tool flavour | SR-071 | LLR-071 | LLR-071 | union | Same. |
| 111 | LLR-010 |  | The chosen state's own record is the sole authority | SR-010 | - [LLR-008] | LLR-010 | take O | Legacy LLR-010 means point-in-time authority (O); A reused LLR-010 for the verified pool lookup (merged into LLR-050) and states authority in LLR-008. |
| 112 | LLR-140 |  | States written by earlier supported versions restore with the current kit | SR-115 | - [LLR-060, LLR-076] | LLR-140 | take O | A inside LLR-060 and LLR-076. |
| 113 | LLR-141 |  | An entry that would land outside the target is not written | SR-121 | LLR-101 | LLR-141 | union | Both value 3. A adds re-checking containment immediately before each write and never writing through a link met since admission (orphan ii clause). |
| 114 | LLR-056 |  | Every written file is verified, with one recovery from another copy | SR-056, SR-119 | LLR-056 | LLR-056 | union | Same. |
| 115 | LLR-050 | LLR-056 | Searching by content key gives one cause per lookup and proves the form | SR-056, SR-119 | LLR-010, LLR-050 | LLR-050 | union (child of LLR-056) | A splits verified lookup (its LLR-010) from the proven form (its LLR-050). |
| 116 | LLR-142 |  | Two names that would collide on the target are both reported | SR-092 | LLR-100 | LLR-142 | union | Both value 1, neither written. |
| 117 | LLR-029 |  | Every entry not restored is recorded with its cause, and counted | SR-029, SR-120 | LLR-029 | LLR-029 | union | Same. |
| 118 | LLR-066 |  | Each restored file gets its own recorded modification time | SR-066 | LLR-066 | LLR-066 | union | Both value 1 for a bad time on a current-form record. |
| 119 | LLR-077 | LLR-056 | Restored files never inherit the store's read-only protection | SR-056, SR-119 | - | LLR-077 | conflict K28 (orphan i) | A retired it; O keeps it under SR-010. Today's code does it on both routes. |
| 120 | LLR-143 |  | Folders and their attributes are applied last; gaps are reported | SR-065, SR-122, SR-146 | - [LLR-065] | LLR-143 | union | A inside LLR-065. O adds OR-ing attributes into existing bits. |
| 121 | LLR-144 |  | Recorded links are rebuilt at their places | SR-152 | LLR-107 | LLR-144 | union | Same. |
| 122 | LLR-040 |  | A restore returns one value, the same on every route and system | SR-040 | LLR-040 | LLR-040 | union | Same classes and precedence; O adds the unclassified-error rule and the bare switch as 2. |
| 123 | LLR-073 |  | A restore asks for a target only where someone can answer | SR-073, SR-016 | LLR-073 | LLR-073 | union | Same decision. |
| 124 | fold:LLR-073 |  | The folder choice never fails the restore | SR-073 | - | LLR-145 | fold into LLR-073 (orphan i) | Its observable part (absent, failed or cancelled choice gives no target) joins LLR-073; the thread-context and quoting rules mirror code and go to the test tier. |
| 125 | LLR-074 |  | The launchers start a restore and hold the outcome only when started by hand | SR-072 | LLR-074 | LLR-074 | union; conflict K34 |  |
| 126 | LLR-146 |  | The container carries everything a backup needs | SR-034 | LLR-112 | LLR-146 | union | A's row carries SR-034, SR-130 and SR-143; split per O. |
| 127 | LLR-147 |  | A containerised run needs no more access than its own locations | SR-130 | - [LLR-112, LLR-048] | LLR-147 | union; conflict K26 | A inside LLR-112 and LLR-048. |
| 128 | LLR-148 |  | Third-party components in the image carry their licences and notices | SR-143 | - [LLR-112] | LLR-148 | take O | A inside LLR-112 (adds: a dependency without permission is excluded; O says the same). |
| 129 | LLR-027 |  | The quick start and the helper take a new user to a first backup | SR-027 | LLR-027 | LLR-027 | union | A's SR-134 and SR-042 parts go to their own clusters. |

**Legacy ids retired by the merge** (meaning absorbed elsewhere): LLR-006, LLR-030, LLR-031, LLR-032, LLR-033, LLR-057, LLR-064, LLR-070, LLR-072, LLR-075. Both sides agree on all ten: LLR-006 and LLR-059's duplicate into LLR-051 (LLR-059 itself is kept, as Opus does), LLR-030/031/032 into the route-neutral digest, restore and record rows, LLR-033 (no second backup engine) into the one-store-form row, LLR-057 into each enumeration's own row, LLR-064 into LLR-061, LLR-070 into the object-name form, LLR-072 into LLR-079, LLR-075 into LLR-007 and the kit form. Astra also retired LLR-018, LLR-054, LLR-059, LLR-063, LLR-077, LLR-079, LLR-092, LLR-093 and LLR-094; the merge keeps them all because their meaning survives in Opus's rows. Never in the stripped registry, so not reused: LLR-012, 013, 019, 034, 044, 081 to 085, 089.

**Id collisions to watch.** Astra reused LLR-010 for the verified pool lookup (legacy meaning: point-in-time authority) and LLR-088 for the move-aside reclaim (legacy meaning: the staging allowlist). The merge keeps both ids with their legacy meanings (Opus's) and moves Astra's content to the clusters the crosswalk names.

## 5. Orphans

A whole row only one side has, then the clauses inside a shared cluster that only one side states. (i) implementation-born: mirrors code, no SR demands it, so drop it or record it as a design gap. (ii) a need understated: an SR obligation the other side missed, so keep it. (iii) accretion: drop it.

Rows:

- (ii) 'Earlier content stays reachable until the replacing state is published' (Astra, inside its LLR-115 and LLR-041). SR-082 and SR-059 need it, and the code has the hole (M51). Keep as a new row.
- (i) Opus LLR-077, restored files never inherit read-only. Implementation-born but load-bearing for verification; keep as a child of LLR-056 (K28).
- (i) Opus LLR-145, the folder choice never fails. The observable part joins LLR-073; the thread-context and quoting rules mirror code and go to the test tier.
- Opus's other single-side rows (LLR-018, 063, 054, 059, 079, 092, 093, 094 and the per-SR splits of Astra's multi-SR rows) are not orphans: Astra states the same obligation inside a broader row, listed in brackets in section 4.

Clauses only Astra states:

- (ii) A folder-only or link-only change keeps a saved state (K37; gap M48).
- (ii) The cross-state collapse deletes a redundant copy only after the keeper is verified and every dependent state still resolves (LLR-026).
- (ii) A re-run removal resumes its own pre-commit work (gap M49).
- (ii) The space plan runs read-only before any artifact and is revalidated under the claim (K10).
- (ii) Containment is re-checked immediately before each write, never through a link met since admission (SR-121).
- (ii) A declared bounded wait of 60 s for a link target (K18) and declared allowance values (K09).
- (ii) Flush before rename (K19).
- (ii) Fence before each destructive step (K21).
- (ii) At the source root, a backup-only artifact name is owner content (SR-074's AC).
- (ii) An unknown volume-root status defaults to capture.
- (ii) The macOS launcher must arrive launchable (K34).
- (iii) The index spill to partitioned temporary files above 1 GiB (Astra LLR-114): keep the numbers, drop the mechanism until a measurement shows the need (M45).
- (iii) The source/store identity binding and generation fields in the change-detection and run-state records (K12), the publication-intent artifact (K20) and writer-side reader pinning (K22), if those conflicts go as recommended.
- (iii) Media measured for every file each run (K31).

Clauses only Opus states:

- (ii) The unclassified-error rule on both sides of the tier (2 before any change, 4 after).
- (ii) The saved-state report and the view rebuild in the outcome set (the ruling: every operation).
- (ii) Reading the compression effort never raises (the restore-safe library reads it).
- (ii) A view rebuild wipes only a folder already holding a generated view.
- (ii) The helper writes the current version.
- (ii) The findings document is alone on standard output and carries the repaired flag.
- (ii) A claim refusal appends one entry to the live holder's record.
- (ii) A non-portable folder name is left out of the folder record with a warning.
- (ii) Attributes are OR-ed into a folder's existing bits.
- (ii) A newer evidence version is checked on its known fields.
- (ii) The ancestor test applies inside a followed outside folder too.
- (ii) The run-state rebuild (K11).
- (i) The listing location on the backup's volume (K35).
- (i) The saved-state date is read from the folder name, with the same-second suffix tolerated: it mirrors code but is harmless reading of the layout form; keep it.

## 6. Design gaps (merged)

Where an SR obligation is not met by today's code, with the merged LLR that states the design. 'Found by' says which side listed it; 'Settled' records where the sides disagreed on what the code does and what the code check found. This list becomes the build work (handoff open item 5).

| Gap | SRs | Merged LLR | Found by | What the code does instead | Settled |
|---|---|---|---|---|---|
| M01 | SR-137, SR-150, SR-151, SR-152 | LLR-109, LLR-110, LLR-144 | both | The walk neither follows a folder link nor records one; no link record exists; neither restore route recreates a link. File links are followed. | O's inference is consistent with the code: the walk lists a folder link with no files beneath it, so it is probably written to the folder record as an empty folder. |
| M02 | SR-138, SR-063, SR-149 | LLR-103 | both | A backup or saved-state location overlapping a source is not refused. The listing location is checked only when the view is on, per location during the run, failing it (1). State-location overlap is checked only against its own set, failing it (1). Roots are created before these checks. |  |
| M03 | SR-140 | LLR-104 | both | No up-front writability check; the run works, then fails when the change-detection record is written (1). |  |
| M04 | SR-035 | LLR-114 | both | A missing record is silently treated as empty; a malformed one throws and fails the location; its evidence is never checked on read; a stale or foreign record is trusted wherever size and time match. | Settled for O: missing means empty (no refusal). A's 'refuses malformed state' concerns the run-state record (M05). |
| M05 | SR-035, SR-005 | LLR-035 | both | A populated backup whose run-state record is missing or unparseable is refused (location fails, 1). |  |
| M06 | SR-005 | LLR-028 | O | A saved state is named by the previous run's start time; LastBackupRun stores a time taken near the run's start. | Confirmed in code; A missed it. |
| M07 | SR-011, SR-105 | LLR-011 | A | Calendar-boundary decision; N with no recorded re-read does re-read; the re-read time is stamped whenever a re-read was due, including runs with unreadable folders. | Confirmed in code; O's design followed the code (conflict K01). |
| M08 | SR-043, SR-040 | LLR-043, LLR-040 | both | A backup returns 1 for busy, capacity, retired form and empty source, and 3 only for witness mismatch; the saved-state report always returns 0; unhandled errors in removal or the report get no mapped value; non-backup actions and both restorers' classified exits are gated by -ExitCode. | Settled: the backup's own exit is not gated by -ExitCode (A over-generalised); configuration failures, non-backup actions and the restorers are. |
| M09 | SR-085, SR-086 | LLR-122 | both | Every claim failure is one refusal (backup 1, removal 2); contention and I/O are not told from denial or an unusable location; the holder is not reliably named. |  |
| M10 | SR-017, SR-107 | LLR-017 | O | Every leftover refusal fails the location with 1; an unfinished removal's refusal does not name re-running it as the remedy. | A's G-14 touches only the lock side. |
| M11 | SR-036 | LLR-036 | O | The empty-source refusal fails the location with 1, not 2. |  |
| M12 | SR-052 | LLR-052 | both | The demand is per location set, content only (no records, kits, logs, temporary space or allocation), checked after roots, claim, log and staging exist; a shortfall fails the location with 1. |  |
| M13 | SR-061 | LLR-060 | both | A backup over a retired form fails with 1; the shell route checks the retired form after creating the target and its log; an unrecognised marker or header is not refused as a form. |  |
| M14 | SR-019 | LLR-020 | O | No backup-side runtime-version check. |  |
| M15 | SR-132, SR-016 | LLR-105, LLR-016 | O | Obtaining the hashing component prompts when attended and needs -AutoInstallDeps when unattended; the fetched package is not checked against a digest; a missing optional tool may prompt; redirected or closed input is not detected. | Confirmed in code (no digest check found). |
| M16 | SR-008, SR-016 | LLR-008 | O | If the kit's hashing library is missing, the language-runtime restore falls back to a package-source install with a prompt, even with -NonInteractive. | Confirmed. |
| M17 | SR-118 | LLR-139 | O | The language-runtime route checks neither its runtime version nor the kit's hashing library before writing; the shell route checks the archive extractor only after creating the target. | Second clause from the code check. |
| M18 | SR-009, SR-141 | LLR-009, LLR-079, LLR-137 | both | The language-runtime route normalises the path lexically first (a parent component is cancelled, not refused), resolves only the deepest existing component, and falls back to the text when resolution fails; on GNU systems the shell route accepts a parent component through its resolver. | Both sides right; each saw part. |
| M19 | SR-023, SR-145 | LLR-023, LLR-136 | both | Both routes leave compressed entries out of the demand and add no allowance; the language-runtime route creates the target and its log before the space and archive-tool checks; an unmeasurable volume is skipped (silently on that route). |  |
| M20 | SR-039, SR-116 | LLR-039, LLR-138 | both | Absent evidence is excused for every state; no positive age evidence is consulted; the shell route silently skips non-numeric Rows or Bytes. |  |
| M21 | SR-121 | LLR-141 | both | An escaping entry is counted as missing content (1), not a damaged record (3); an escaping folder-record row only warns. |  |
| M22 | SR-092 | LLR-142 | both | Collisions are not detected: on Windows the language-runtime route keeps the last of two case-differing rows; elsewhere both are written to one file; the shell route lets the second overwrite the first. |  |
| M23 | SR-146, SR-122, SR-065 | LLR-143 | both | A missing or malformed folder record never changes the outcome; nothing tells a state that should have one from one that has none; the language-runtime route assigns attributes (replacing existing bits); the shell route never applies attributes, only logs them. | Shell-route clause from the code check; neither side listed it. |
| M24 | SR-066 | LLR-066 | both | A blank time is skipped silently and an unparseable one only warns; the restore still ends complete. |  |
| M25 | SR-040, SR-068, SR-119 | LLR-040, LLR-050 | both | An unclassified error mid-restore reports 2 although files were written; a shell switch without its value exits 127; a direct object's expansion failure is a host failure (4) with no tool self-test (the self-test runs only in the pool search); a missing item whose search ends in a host cause is recorded as missing content. | A found the direct-expansion case, O the rest. |
| M26 | SR-120 | LLR-029 | O | The summaries give counts and names but no per-entry causes (causes only in separate log lines); the report entries are not in the IF-022 form. |  |
| M27 | SR-124 | LLR-107 | O | The record gives one new-or-changed count and a removed count; added files are not told from changed ones and most are not named. |  |
| M28 | SR-125 | LLR-108 | both | No progress entries at all; the only periodic activity is the owner-record refresh. |  |
| M29 | SR-089, SR-091, SR-067 | LLR-111, LLR-067 | both | A file that cannot be read for its digest aborts the whole location; retries cover only the copy. |  |
| M30 | SR-049 | LLR-049 | both | The default check reads only an object's opening bytes; altered content is found only with -Deep. |  |
| M31 | SR-109 | LLR-129 | both | Repair renames and rewrites forms but never copies content back from a verified copy elsewhere. |  |
| M32 | SR-117, SR-110 | LLR-131, LLR-130 | A | The refresh copies the backup root's existing kit into each saved state (it does not regenerate it from the installed program), file by file with no temporary name, so a kill can leave a mixed kit. | Confirmed in code; O had left it unconfirmed. Whether each repair rename publishes by temporary and rename is still unconfirmed. |
| M33 | SR-097 | LLR-132 | both | No space view and no setting for it. |  |
| M34 | SR-098, SR-099, SR-147 | LLR-133, LLR-134 | O | The media rate is never computed: the switch that would enable the tool is hard-wired off, and no record entry says the measure was not taken. | Settled for O: the measurement function is called per hashed file but returns nothing because the tool is never resolved. A's 'invokes measurement when the tool is available' is wrong. |
| M35 | SR-131 | LLR-119 | both | No licence or notice file in any backup; the hashing library is redistributed without its notice. |  |
| M36 | SR-143 | LLR-148 | O | The container image carries no notices file. | Confirmed from the image build definition (A had not read it). |
| M37 | SR-135, SR-027 | LLR-099 | both | The native-Windows form carries no version and the helper writes none. |  |
| M38 | SR-018, SR-042 | LLR-042, LLR-101 | both | The native-Windows form gets a shape check only: no closed key set, no strict value kinds; the published description covers JSON only. |  |
| M39 | SR-129 | LLR-100 | both | A native-Windows credential in plain text is not refused. |  |
| M40 | SR-095 | LLR-014 | both | A multi-set JSON configuration draws a warning; removal, report, check and view act on the first set only. | First-set clause from O, confirmed. |
| M41 | SR-048, SR-103 | LLR-048, LLR-128 | O | Removal and the report resolve locations in the backup's mode: they need the source to exist and create missing backup or saved-state folders. |  |
| M42 | SR-033, SR-136 | LLR-121 | O | A Linux run writes '/' where a Windows run writes '\'; a run from the other host type then sees every file removed and added. | Confirmed; A's record form says backslash but A listed no gap. Migration: K13. |
| M43 | SR-082 | LLR-087, LLR-118 | both | The evidence is written only after the record is renamed, and nothing is flushed; a kill between the two leaves a mismatch the next run refuses. | Flush clause from A. |
| M44 | SR-027 | LLR-027 | O | The quick start's first run asks before installing the hashing component; the helper writes an unversioned document; the user manual states two different current configuration versions. |  |
| M45 | SR-064, SR-112, SR-113 | LLR-149, LLR-062 | both | The time and memory budgets have never been measured at the declared scale; removal and the audit keep whole records; restore recovery scans candidates per unresolved row. | Not a measured failure: a missing measurement. |
| M46 | SR-104 | LLR-096 | O | The repair's findings document has no per-finding Repaired field (a fresh re-check is printed instead). |  |
| M47 | SR-001, SR-074 | LLR-001, LLR-022 | A | With the change-detection record at the source root, the whole backup infrastructure list is excluded at the source root (owner files sharing a backup-only name are skipped); with the record elsewhere, that branch also skips the volume-root filter. | A's claim, not re-checked by the alignment; confirm when the code is headed. |
| M48 | SR-005, SR-065 | LLR-005 | A | The saved-state decision comes from the file-row diff only; a run whose only change is a new empty folder adds no saved state and overwrites the folder record. | Confirmed in code. |
| M49 | SR-101, SR-017 | LLR-127 | A | A removal killed before its commit point leaves its staging marker; the next removal refuses any existing staging area and backups refuse the marker, so the store wedges until a person clears it. | Confirmed in code. |
| M50 | SR-046, SR-102 | LLR-046, LLR-126 | both | Target checks are lexical (a link to outside is not resolved); module-level options can waive the unreferenced-content and evidence refusals. |  |
| M51 | SR-082, SR-059, SR-041 | LLR-150 | A | Removed and superseded objects move into staging before the new latest record is published; a kill there leaves a witnessed latest record whose bytes only staging holds, and no restore searches staging. | Confirmed in code; O missed it. |
| M52 | SR-081 | LLR-086 | A | A file of exactly 262144 bytes is measured; the SR gives files at or below 256 KiB the file-type rule. | Confirmed (both code conditions treat 262144 as above the floor). |
| M53 | SR-072 | LLR-074 | A | A Windows-written kit carried to a Mac by zip needs a manual chmod before Finder opens the launcher; the restorer holds the window on success and on classified exits but not on its error trap. | Hold-on-trap clause from the code check. See K34. |
| M54 | SR-073 | LLR-073 | neither | The language-runtime route never checks for a desktop session (only the console and input), and a cancelled folder choice falls back to a typed prompt. | Found by the alignment's code check. |
| M55 | SR-144 | LLR-125 | A | The owner identity is re-checked at five boundaries only; a resumed former owner can still move or delete between them. | A gap under the recommended K21 design. |
| M56 | SR-106, SR-103 | LLR-123 | A | A reader meeting a location that a concurrent repair, collapse or removal has just moved has no re-resolution or re-read rule. | Reworded to the recommended K22 design. |
| M57 | SR-130 | LLR-147 | A | Scratch uses the host temporary folder; the shipped compose file mounts /tmp as tmpfs. | Remains a gap only if SR-130's wording excludes a non-persistent scratch mount (K26). |

Found by both: 30; Astra only: 11; Opus only: 15; neither (the alignment's code check): 1.

Claimed gaps dropped or folded:

- A G-10 (a refused configuration appends to an existing global log): SR-018 forbids truncating an existing log, not an appended refusal line (K27). Dropped.
- A G-13 (the backup's classified exit is selected by -ExitCode): Wrong for the backup itself (its 1/3 exit is unconditional); right for configuration failures, non-backup actions and both restorers. Folded into M08.
- A G-30 (media measured while hashing when the tool is available): Wrong: the tool is never resolved, so no measurement is made. Folded into M34 on O's reading.
- O G-36 (kit refresh and repair publication unconfirmed): The kit-refresh half is settled in M32; the repair-rename half stays open.

Code beyond the design (no SR asks for it):

- Removal dry run (-WhatIf with Prune; FILEBACKUP_DRY_RUN): Owner call K04.
- Removal overrides at the module level (discard unreferenced content, accept unverified records, skip verification): SR-046 refuses those cases without exception; retire them or keep them test-only (K06).
- -Deep: Its meaning becomes the default check; keep it accepted with no meaning (K05).
- The strict-evidence restore switch (-RequireWitness / --require-witness): Both sides keep it in the request form, and no SR asks for it. Treat it like K04: the Owner adds a need or it stays out of the LLRs (O already lists it as beyond the design).
- The multi-set warning: Goes (SR-095).
- -BackupTime (test seam that pins the run's date): Not part of the launch form; a test-tier seam.
- -IncludeSnapshots and the -VerifyStorage alias: Accepted by today's entry point; neither side's form lists them. Keep them as accepted aliases of the form or retire them, and say which in IF-002.
- Listing location must be on the backup's volume: K35.

SRs that reach no LLR and no interface: none, on either side or in the merge.

The handoff's known build work is all present: links (M01), the inside-source location refusal (M02), the read-only-source refusal (M03), the outcome codes (M08 to M13, M25), repair copy-back (M31), the budgets and progress (M45, M28), licence notices (M35, M36). The 'empty-source remedy for an unfinished removal' is covered by M10 and M49 (name the remedy; let the re-run resume).

