# Legacy LLR mapping (round 3, merged tier)

One line per legacy id from LLR-001 to LLR-094, saying what became of it in the merged tier. "Kept" means the id survives with its meaning, reworded to contract voice; "child of" means it is kept as a child row under the named parent; "merged into" means its obligation now lives in the named row and the id is retired; "split" names the rows its parts went to; "moved to IF" means its content is now an interface's form; "moved to TC" means a test or delivery statement; "not in the registry" means the id had no row when the legacy registry was stripped. No retired id is reused. Where the merge chose between the two derivations, the K-call is named (r3-dispositions.md).

| Legacy id | Fate | New home | Reason |
|---|---|---|---|
| LLR-001 | Kept, split | LLR-001 (the walk); LLR-113 (the change comparison); LLR-111 (what cannot be captured) | The walk and the diff are two decisions with two parents (SR-001/SR-074 against SR-088/SR-105/SR-024); naming what cannot be captured serves SR-089/SR-091. |
| LLR-002 | Kept, merged LLR-030 | LLR-002; digest algorithm and text form to IF-034 | One digest rule for every route; the algorithm and its text form are interface form, owned by the store format. |
| LLR-003 | Kept | LLR-003; naming grammar to IF-016 | Store-once by content key survives, now saying an entry with a blank or absent copy is demand, not supply. |
| LLR-004 | Kept as child, split | LLR-004 (child of LLR-086, the explicit list, K30); object-write rule to LLR-117; effort level to LLR-037 | The list is the file-type rule of the compression decision and needs one spine home; the write path is its own rule. |
| LLR-005 | Kept | LLR-005; dating to LLR-028 (child); folder grammar to IF-013 | Saved state on change and none on no change survive; a folder-only or link-only change now counts (K37). |
| LLR-006 | Merged into | LLR-051 | Reference-counted eviction is one of the two removal sites LLR-051 binds; a separate row duplicated it. |
| LLR-007 | Kept, merged LLR-075 | LLR-007; artifact list to IF-019; notices to LLR-119 | Kit placement survives, now complete before the state is visible; the artifact list is form. |
| LLR-008 | Kept, merged LLR-031 | LLR-008 (flat, K29) | Standalone restore on the kit and the floor; the shell restorer's copy of it is the same obligation on another route. Astra's eight-SR parent shape was not adopted. |
| LLR-009 | Kept, split | LLR-009 (target guard); LLR-137 (unresolvable or parent component); LLR-141 (per-entry containment) | The guards have different outcomes (2 against 3) and different parents (SR-009, SR-141, SR-121). |
| LLR-010 | Kept, merged part of LLR-057 | LLR-010 | Point-in-time authority (its legacy meaning, not Astra's reuse for the pool lookup, which went to LLR-050); the pool includes hidden folders, and nothing but the state's entries and the report is written under the target. |
| LLR-011 | Kept | LLR-011; schedule letters to IF-004 | The decision survives with calendar periods judged against the last completed re-read (K01 as narrowed by P-01 (c), 2026-10-18); the letters are configuration form. |
| LLR-012 | Not in the registry | none | No row when the registry was stripped; not reused. |
| LLR-013 | Not in the registry | none | No row when the registry was stripped; not reused. |
| LLR-014 | Kept | LLR-014 | Per-location isolation with the fold rule, every set resolved and validated for every action. |
| LLR-015 | Kept | LLR-015; message form to IF-011 | Conditional, non-fatal notification survives. |
| LLR-016 | Kept, split | LLR-016 (every operation); the restore's no-target part to LLR-073 | The unattended rule spans every operation; the restorer's no-target behaviour is LLR-073's decision. |
| LLR-017 | Kept, split | LLR-017 (classification and refusal); LLR-080 (liveness evidence); LLR-124 (reclaim); LLR-125 (fencing) | Classification, liveness, reclaim and fencing serve SR-017, SR-075 and SR-144; each is one decision. |
| LLR-018 | Kept as child | LLR-018 (child of LLR-042) | A missing configuration is one fault of the validated launch; creating nothing, the global record included, is the child's addition. |
| LLR-019 | Not in the registry | none | No row when the registry was stripped; not reused. |
| LLR-020 | Kept | LLR-020 (constrains IF-046) | Runtime and tool presence before any location is touched; the hashing component's fetch moved to LLR-105. |
| LLR-021 | Kept | LLR-021 | Literal paths survive as a rule independent of any interface; the cross-host clause went to LLR-121. |
| LLR-022 | Kept | LLR-022; infrastructure names to IF-013 | Root-only infrastructure recognition survives, now with the source-root rule (backup-only names there are owner content). |
| LLR-023 | Kept | LLR-023 | Restore space check before the target exists, with Astra's declared allowance values (K09) and no refusal of an unmeasurable volume (K08, P-04). |
| LLR-024 | Kept | LLR-024 | Deterministic record output survives. |
| LLR-025 | Kept, merged LLR-032; split | LLR-025 (one reader, one writer, every route); columns to IF-014; publication to LLR-087 | The column schema is form; readers accept either separator in older records (K13). |
| LLR-026 | Kept as child | LLR-026 (child of LLR-003) | Cross-state collapse serves store-once; it now deletes a copy only once the kept copy and every rewritten dependent state resolve. |
| LLR-027 | Kept | LLR-027; helper and guidance form to IF-008 | Quick start plus helper to a first backup survives; the example and description parity went to LLR-102 and LLR-101. |
| LLR-028 | Kept as child | LLR-028 (child of LLR-005); run-state form to IF-030 | Dating and the run-state write order survive; the date is the completion time of the state held. |
| LLR-029 | Kept | LLR-029 | Unrestored-entry accounting survives, with per-entry causes. |
| LLR-030 | Merged into | LLR-002 | The shell route's digest wrapper is the same digest rule on another route; loading it for unit tests went to the test tier. |
| LLR-031 | Merged into | LLR-008 (and LLR-009, LLR-010, LLR-023, LLR-029 per obligation) | The shell restorer restated the other restorer's obligations; one set of restore rows binds both routes. |
| LLR-032 | Merged into | LLR-025; CSV and separator rules to IF-014 | Record parsing is one rule on every route; its form is the record interface. |
| LLR-033 | Merged into | LLR-121 | A separate shell backup engine was never built; SR-033 is met by one engine writing one form from either host. |
| LLR-034 | Not in the registry (retired at the strip) | none | Container build and smoke test went to delivery and the test tier at the strip. |
| LLR-035 | Kept, meaning narrowed | LLR-035 | Still "a missing run-state record never makes a populated backup a first backup"; the refusal becomes a rebuild from the evidence's written time, reported (K11, P-05). |
| LLR-036 | Kept | LLR-036 | Empty-source refusal with the value 2; an unreadable source root is not an empty one. |
| LLR-037 | Kept | LLR-037; variable names to IF-007 | Environment tool resolution and the effort setting survive; it now also carries SR-081. |
| LLR-038 | Kept | LLR-038; evidence fields to IF-015 | Evidence written with every record survives, now stating folder- and link-record rows (K14). |
| LLR-039 | Kept | LLR-039; age evidence to LLR-138 | Restore-side verification survives; absent evidence is excused only on positive age evidence. |
| LLR-040 | Kept | LLR-040; search causes to LLR-050 | One restore classification for both routes; a tool failing its admission self-test is 2 (K32). |
| LLR-041 | Kept | LLR-041 | Move-failure aggregation survives. |
| LLR-042 | Kept, split | LLR-042; key catalogue to IF-004; JSON rules to IF-005; version rules to LLR-098, LLR-099; credentials to LLR-100; description parity to LLR-101 | Validation binds both forms equally; Astra's five-SR row was split so each SR's obligation has its own row. |
| LLR-043 | Kept | LLR-043; record-creation timing to LLR-095; container part to LLR-048; the multi-location fold to LLR-014 | The shared vocabulary across every operation, the report and the view rebuild included. |
| LLR-044 | Not in the registry (retired at the strip) | none | Container export, load and registry round trips are delivery verification, moved to the test tier at the strip. |
| LLR-045 | Kept | LLR-045 | Removal plan and re-homing survive. |
| LLR-046 | Kept, split | LLR-046 (refusals); LLR-126 (confinement, SR-102); LLR-127 (commit and re-run recovery, SR-101) | Three decisions serving three SRs; no override and no dry run is stated (K04, K06). |
| LLR-047 | Kept, split | LLR-047 (report figures); index form to IF-043; index memory to LLR-062 | The report survives; the index is an internal interface shared with the check and the collapse. |
| LLR-048 | Kept | LLR-048; action words and variables to IF-038 and IF-002 | Container action mapping survives; mounts and identity went to LLR-147. |
| LLR-049 | Kept, split | LLR-049 (check: plain form test, full payload with -Deep, P-03 (b)); repair to LLR-129; finding classes to IF-010 | The check and the repair serve SR-049 and SR-109; repair now copies back, so it is its own row. |
| LLR-050 | Kept as child | LLR-050 (child of LLR-056, constrains IF-045) | Search-by-key causes and the proven form serve the verify-and-recover rule; its answer set is now the typed IF-045. |
| LLR-051 | Kept, merged LLR-006 | LLR-051 | The final-record claim test at both removal sites. |
| LLR-052 | Kept, split | LLR-052 (backup space plan); LLR-135 (volume identity, free space and allocation unit) | The measurement serves backup and restore; the plan runs read-only before anything is created and is re-checked under the claim (K10), with declared allowance values (K09). |
| LLR-053 | Kept | LLR-053 | Heal and present-only adoption survive. |
| LLR-054 | Kept as child | LLR-054 (child of LLR-049) | Missing-here against missing-everywhere refines the check. |
| LLR-055 | Kept | LLR-055 | Portable-name refusal survives, with non-portable folder names left out of the folder record. |
| LLR-056 | Kept | LLR-056 | Verify after write with one recovery survives. |
| LLR-057 | Merged into | LLR-001 (source side); LLR-010 (pool side); LLR-047 (removal accounting) | Hidden capture is part of each enumeration's own obligation; a list of call sites was implementation; its static guard went to the test tier. |
| LLR-058 | Kept as child | LLR-058 (child of LLR-003) | Owner election and the once-per-group decision refine store-once. |
| LLR-059 | Kept | LLR-059 | Superseded preservation survives (Astra merged it into LLR-051; the claim test does not state the preservation itself). |
| LLR-060 | Kept | LLR-060 | Retired-form refusal, naming unrecognised forms, value 2 everywhere. |
| LLR-061 | Kept, merged LLR-064 | LLR-061; view files to IF-041; location checks to LLR-103 | The generator survives; its location refusals moved to launch. |
| LLR-062 | Kept | LLR-062 | The linear audit survives, joined by the lean index default. |
| LLR-063 | Kept as child | LLR-063 (child of LLR-042) | Retired-key refusal by name is a distinct decision SR-018 names; its versioning sentence went to LLR-098. |
| LLR-064 | Merged into | LLR-061; the action word to IF-002 | The view-rebuild action is a request form; its behaviour is the generator's. |
| LLR-065 | Kept, split | LLR-065 (capture side); LLR-143 (restore side); folder-record columns to IF-017 | Recording and applying folder metadata are two decisions with different outcomes. |
| LLR-066 | Kept | LLR-066 | Each file's own modification time, part failed on a bad time, the recorded offset honoured. |
| LLR-067 | Kept | LLR-067 | Bounded retry per location, covering the read for the digest. |
| LLR-068 | Kept | LLR-068 (top-level, K29) | Byte-derived stored form survives. |
| LLR-069 | Kept | LLR-069; grammar to IF-016 | Codec and one parser survive; the grammar is form. |
| LLR-070 | Moved to IF | IF-016 (the extension is opaque and may be empty), and LLR-069 | "The extension is opaque and may be empty" is a grammar fact. |
| LLR-071 | Kept | LLR-071 | Tool-flavour independence of the shell route, with the portable byte-count fallback. |
| LLR-072 | Merged into | LLR-079 | Physical canonicalisation with a three-way answer is one containment rule for both routes. |
| LLR-073 | Kept, merged the restore part of LLR-016 | LLR-073 | The target-prompt decision survives; Opus's LLR-145 (the folder choice never fails) folds in for its observable part, and its threading and quoting rules go to the test tier. |
| LLR-074 | Kept | LLR-074; launcher artifacts to IF-019 | Launchers and the window hold survive, with the macOS executable permission and the support boundary of P-07. |
| LLR-075 | Merged into | LLR-007 (placement); IF-019 (artifact list); LLR-022 (retired launcher recognised); LLR-131 (refresh never deletes) | Each clause already had a home; the row only listed them. |
| LLR-076 | Kept as child | LLR-076 (child of LLR-120) | The kit revision is what makes "never write what an existing kit cannot read" checkable; Astra's coherent-refresh clauses went to LLR-130 and LLR-131. |
| LLR-077 | Kept as child | LLR-077 (child of LLR-056, K28) | Reworded: a stored item's protection never blocks verification or the time stamp and is not handed to the restored file. Astra retired it; without it verification fails on read-only stores. |
| LLR-078 | Kept as child | LLR-078 (child of LLR-001) | The volume-root exclusion is one declared exclusion of the walk; an unknown volume-root status defaults to capture. |
| LLR-079 | Kept as child, merged LLR-072 | LLR-079 (child of LLR-009) | Physical containment is how the target guard decides. |
| LLR-080 | Kept | LLR-080 (top-level, serves SR-075); record fields to IF-033; reclaim to LLR-124; fences to LLR-125 | The owner record and liveness evidence survive, with Astra's second-sample formula (K24). |
| LLR-081 | Not in the registry | none | No row when the registry was stripped; not reused. |
| LLR-082 | Not in the registry | none | No row when the registry was stripped; not reused. |
| LLR-083 | Not in the registry | none | No row when the registry was stripped; not reused. |
| LLR-084 | Not in the registry | none | No row when the registry was stripped; not reused. |
| LLR-085 | Not in the registry | none | No row when the registry was stripped; not reused. |
| LLR-086 | Kept, split | LLR-086 (decision); LLR-116 (measurement, child); LLR-004 (type list, child) | The decision, the sampling geometry and the type list are three rows. |
| LLR-087 | Kept, split | LLR-087 (atomic publication, flushed before the rename, K19); LLR-118 (evidence before publication, child, K20) | The write order lets the next run complete an interrupted publication; the flush keeps a power loss from tearing the newest record. |
| LLR-088 | Kept as child | LLR-088 (child of LLR-017) | Its legacy meaning, publication temporaries are not content, root-scoped and case-exact. Astra reused the id for the reclaim, which went to LLR-124. |
| LLR-089 | Not in the registry (retired at the strip) | none | It recorded one revision bump; its durable remnants live in LLR-076 and LLR-094. |
| LLR-090 | Kept | LLR-090; claim file form to IF-032; failure classes to LLR-122 | The claim primitive survives. |
| LLR-091 | Kept as child | LLR-091 (child of LLR-090) | Backup claim window. |
| LLR-092 | Kept as child | LLR-092 (child of LLR-090) | Removal claim window. |
| LLR-093 | Kept as child | LLR-093 (child of LLR-090) | Claim file lifecycle and invisibility. |
| LLR-094 | Kept as child | LLR-094 (child of LLR-090) | Repair and kit-refresh claim window. |

Counts: 73 kept (of the 83 rows in the stripped registry); 10 merged, moved or retired (LLR-006, 030, 031, 032, 033, 057, 064, 070, 072, 075); 11 ids not in the registry (LLR-012, 013, 019, 034, 044, 081 to 085, 089).

## IF-001 (legacy HomeHub contract): retired, split

| Part of IF-001 | Where it went |
|---|---|
| Container action words, environment variables, argument pass-through, default action | IF-038; behaviour in LLR-048 |
| Read-only source and config, writable state, backup, change and log mounts | IF-039; behaviour in LLR-147 |
| The change-detection record kept outside a read-only source | IF-029; behaviour in LLR-115 and LLR-104 |
| Exit-code tables for backup, removal, verify and restore | IF-003 and IF-021 (one vocabulary 0 to 4); behaviour in LLR-043 and LLR-040 |
| The restore-kit artifacts deposited in every state | IF-019; behaviour in LLR-007 |
| The configuration contract (version, closed keys, types, defaults, optional additive keys) | IF-004, IF-005, IF-006; behaviour in LLR-042, LLR-063, LLR-098, LLR-099, LLR-101 |
| Saved-state inventory fields and the bytes-reclaimed figure | IF-010; behaviour in LLR-047 |
| Removal mechanism (re-home, prove, then delete) | LLR-045, LLR-046, LLR-127 |
| Verify as a container action, report-only | IF-038; LLR-049, LLR-128 |
| Capacity refusal of a backup | LLR-052 (now value 2, not 1) |
| Compression-effort variable outside the configuration | IF-007; LLR-037 |
| Witness verified before writing | IF-015; LLR-039 |
| "One location set per container invocation" | Dropped: SR-095 makes several locations normal; nothing in the design depends on one set |
| HomeHub owns scheduling, retention policy and its own alert translation | Not an interface of FileBackup: REL-03 and REL-05 in external.toml describe it; DA-09 bridges the outcome |
| "HomeHub must never delete a saved-state folder directly" | A host obligation outside FileBackup's design; SR-045 and SR-046 give the safe removal it should use instead |
| The browse view kept outside the container contract | IF-041 is a native-host view; the container has no view mount |
| The legacy opt-in exit-code switch | Accepted and meaningless (IF-002, LLR-043) |
