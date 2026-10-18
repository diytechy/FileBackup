# Legacy LLR mapping (round 3, Opus derivation)

One line per legacy LLR id from LLR-001 to LLR-094. "Kept" means the id survives with its meaning, reworded to contract voice; "child of" means it is kept as a child row under the named parent; "merged into" means its obligation now lives in the named row and the id is retired; "split" names the rows its parts went to; "moved to IF" means its content is now an interface's form; "moved to TC" means it was a test or delivery statement; "retired" means no requirement asks for it.

| Legacy id | Fate | New home | Reason |
|---|---|---|---|
| LLR-001 | Kept, split | LLR-001 (walk); LLR-113 (the change comparison) | The walk and the diff are two decisions with two parents (SR-001/SR-074 against SR-088/SR-105); the diff moved to change detection. |
| LLR-002 | Kept, merged LLR-030 | LLR-002; digest text form to IF-034 | One digest rule for every route; the algorithm and its text form are interface form. |
| LLR-003 | Kept | LLR-003; naming grammar to IF-016 | Store-once by content key survives; the object-name grammar is form. |
| LLR-004 | Kept as child, split | LLR-004 (child of LLR-086); object-write clearing to LLR-117; effort level to LLR-037 | The list is the file-type rule of the compression decision; clearing debris before an archive write is a separate write-path rule; its test-instrument clauses moved to the test tier. |
| LLR-005 | Kept | LLR-005; date naming to LLR-028 and IF-013 | Saved state on change and none on no change survive; the folder naming is layout form. |
| LLR-006 | Merged into | LLR-051 | Reference-counted eviction is one of the two removal sites LLR-051 already binds; a separate row duplicated it. |
| LLR-007 | Kept, merged LLR-075 | LLR-007; artifact list to IF-019; notices to LLR-119 | Kit placement survives; the artifact list is form. |
| LLR-008 | Kept, merged LLR-031 | LLR-008 | Standalone restore on the kit and the floor; the shell restorer's mirror of it is the same obligation on another route (parity is a test question). |
| LLR-009 | Kept, split | LLR-009 (target guard); LLR-141 (per-entry containment) | The target guard and the per-entry guard now have different outcomes (2 against 3) and different parents (SR-009, SR-121). |
| LLR-010 | Kept, merged part of LLR-057 | LLR-010 | Point-in-time authority survives; the pool now explicitly includes hidden folders (from LLR-057). |
| LLR-011 | Kept | LLR-011; schedule codes to IF-004 | The decision survives; the code letters and their calendar meaning are configuration form. |
| LLR-014 | Kept | LLR-014 | Per-location isolation, now with the SR-043 folding rule. |
| LLR-015 | Kept | LLR-015; message form to IF-011 | Conditional, non-fatal notification survives. |
| LLR-016 | Kept, split | LLR-016 (backup side); restore usage part merged into LLR-073 | The unattended rule spans every operation; the restorer's no-target behaviour is LLR-073's decision. |
| LLR-017 | Kept, split | LLR-017 (classification and refusal); LLR-124 (reclaim protocol); LLR-125 (fences) | Classification, reclaim and fencing serve three different SRs (SR-017, SR-075, SR-144); each is one decision. |
| LLR-018 | Kept as child | LLR-018 (child of LLR-042) | A missing configuration is one fault of the validated launch; its message detail is the child's addition. |
| LLR-020 | Kept | LLR-020 | Tool presence at launch, now with the runtime floor. |
| LLR-021 | Kept | LLR-021 | Literal paths survive as a rule independent of any interface. |
| LLR-022 | Kept | LLR-022; infrastructure names to IF-013 | Root-only infrastructure recognition survives; the names themselves are layout form. |
| LLR-023 | Kept | LLR-023 | Restore space check, now with the SR-023 allowance and before the target exists. |
| LLR-024 | Kept | LLR-024 | Deterministic record output survives. |
| LLR-025 | Kept, merged LLR-032; split | LLR-025 (one reader, one writer, on every route); schema to IF-014; atomic publication to LLR-087 | The column schema is form; publication is LLR-087's decision. |
| LLR-026 | Kept as child | LLR-026 (child of LLR-003) | Cross-state collapse serves store-once; it reads the content-location index (IF-043). |
| LLR-027 | Kept | LLR-027; helper and guidance form to IF-008 | Quick start plus helper to a first backup survives. |
| LLR-028 | Kept as child | LLR-028 (child of LLR-005); run-state form to IF-030 | Dating and the run-state write order survive; the date is now the completion time. |
| LLR-029 | Kept | LLR-029 | Unrestored-entry accounting survives, with per-entry causes. |
| LLR-030 | Merged into | LLR-002 | The shell route's digest wrapper is the same digest rule on another route; loading the script for unit tests moved to the test tier. |
| LLR-031 | Merged into | LLR-008 (and LLR-010, LLR-009, LLR-023, LLR-029 per obligation) | The shell restorer restates the PowerShell restorer's obligations; one set of restore rows binds both routes. |
| LLR-032 | Merged into | LLR-025; CSV and separator rules to IF-014 | Record parsing is one rule on every route; its form is the record interface. |
| LLR-033 | Merged into | LLR-121 | A separate shell backup engine was never built; SR-033 is met by one engine writing one form from either host. |
| LLR-034 | Retired | none (container build and smoke test moved to delivery and the test tier at the strip) | Already retired at the strip; image build tooling is delivery, outside the product spine. |
| LLR-035 | Kept, meaning narrowed | LLR-035 | Still "a missing run-state record never makes a populated backup a first backup"; the refusal becomes a rebuild from the evidence's written time (see design-gaps). |
| LLR-036 | Kept | LLR-036 | Empty-source refusal, now with the precondition value 2. |
| LLR-037 | Kept | LLR-037; variable names to IF-007 | Environment tool resolution and the effort setting survive. |
| LLR-038 | Kept | LLR-038; evidence fields to IF-015 | Evidence written with every record survives; its key=value form is interface form. |
| LLR-039 | Kept | LLR-039; age evidence to LLR-138 | Restore-side verification survives; an absent evidence file is excused only on positive age evidence. |
| LLR-040 | Kept | LLR-040; locator causes to LLR-050 | One restore classification for both routes. |
| LLR-041 | Kept | LLR-041 | Move-failure aggregation survives. |
| LLR-042 | Kept | LLR-042; key catalogue to IF-004; JSON rules to IF-005; description parity to LLR-101 | Validation survives and now binds both forms equally; the published-schema parity is its own row. |
| LLR-043 | Kept | LLR-043; log-creation timing to LLR-095; container part to LLR-048 | The outcome mapping is now the shared vocabulary across every operation; the record-truncation rule is a run-record decision. |
| LLR-044 | Retired | none (moved to the test tier at the strip) | Container export, load and registry round trips are delivery verification, not a design obligation. |
| LLR-045 | Kept | LLR-045 | Removal plan and re-homing survive. |
| LLR-046 | Kept, split | LLR-046 (refusals); LLR-126 (confinement, its own row for SR-102); LLR-127 (commit and re-run recovery) | Three decisions serving SR-046, SR-102 and SR-101. |
| LLR-047 | Kept, split | LLR-047 (report figures); index form to IF-043; index memory to LLR-062 | The inventory survives; the index is an internal interface shared with the check and the collapse. |
| LLR-048 | Kept | LLR-048; action words to IF-038 and IF-002 | Container and entry-point action mapping survives. |
| LLR-049 | Kept, split | LLR-049 (check); repair to LLR-129; finding classes to IF-010 | The check and the repair serve SR-049 and SR-109; repair now copies back, so it is its own row. |
| LLR-050 | Kept as child | LLR-050 (child of LLR-056) | Search-by-key causes and proven form serve the verify-and-recover rule. |
| LLR-051 | Kept, merged LLR-006 | LLR-051 | The final-record claim test at both removal sites. |
| LLR-052 | Kept, split | LLR-052 (backup space preflight); LLR-135 (volume identity and free space) | The measurement serves both the backup and the restore check; the preflight now adds the allowance and value 2. |
| LLR-053 | Kept | LLR-053 | Heal and present-only adoption survive (SR-053, SR-108). |
| LLR-054 | Kept as child | LLR-054 (child of LLR-049) | Missing-here against missing-everywhere is a refinement of the check; its kit-revision form rail moved into LLR-049. |
| LLR-055 | Kept | LLR-055 | Portable-name refusal survives. |
| LLR-056 | Kept | LLR-056 | Verify after write with one recovery survives. |
| LLR-057 | Merged into | LLR-001 (source side); LLR-010 (pool side); LLR-047 (removal accounting) | Hidden capture is part of each enumeration's obligation; a cross-cutting list of call sites was implementation; its static guard moved to the test tier. |
| LLR-058 | Kept as child | LLR-058 (child of LLR-003) | Owner election and the once-per-group decision refine store-once. |
| LLR-059 | Kept | LLR-059 | Superseded preservation survives. |
| LLR-060 | Kept | LLR-060 | Retired-form refusal, now naming unrecognised forms and the value 2 everywhere. |
| LLR-061 | Kept, merged LLR-064 | LLR-061; view files to IF-041; location checks to LLR-103 | The generator survives; its location refusals moved to launch. |
| LLR-062 | Kept | LLR-062 | The linear audit survives, joined by the index memory rule. |
| LLR-063 | Kept as child | LLR-063 (child of LLR-042); view keys to IF-004 | Retired-key refusal by name refines validation. |
| LLR-064 | Merged into | LLR-061; the action word to IF-002 | The view-rebuild action is a request form; its behaviour is the generator's. |
| LLR-065 | Kept, split | LLR-065 (capture side); LLR-143 (restore side); sidecar columns to IF-017 | Recording and applying folder metadata are two decisions with different outcomes. |
| LLR-066 | Kept | LLR-066 | Own modification time, now with part failed on a bad time. |
| LLR-067 | Kept | LLR-067 | Bounded retry, now per location and covering reads for the digest. |
| LLR-068 | Kept | LLR-068 | Byte-derived stored form survives. |
| LLR-069 | Kept | LLR-069; grammar to IF-016 | Codec and one parser survive; the grammar is form. |
| LLR-070 | Moved to IF | IF-016 (extension opaque, may be empty) and LLR-069 | "The extension is opaque and may be empty" is a grammar fact. |
| LLR-071 | Kept | LLR-071 | Tool-flavour independence of the shell route survives. |
| LLR-072 | Merged into | LLR-079 | Physical canonicalisation with a tri-state answer is one containment rule for both routes. |
| LLR-073 | Kept, merged restore part of LLR-016 | LLR-073; dialog rules to LLR-145 | The pure target-prompt decision survives. |
| LLR-074 | Kept | LLR-074 | Launchers and the window hold survive; launcher bytes are in IF-019. |
| LLR-075 | Merged into | LLR-007 (placement); IF-019 (artifact list); LLR-022 (retired launcher recognised); LLR-131 (refresh copies, never deletes) | Each clause had a home already; the row only listed them. |
| LLR-076 | Kept as child | LLR-076 (child of LLR-120) | The kit revision is what makes "never write what an existing kit cannot read" checkable. |
| LLR-077 | Kept | LLR-077 | Restored files never inherit read-only. |
| LLR-078 | Kept as child | LLR-078 (child of LLR-001) | The volume-root exclusion is one declared exclusion of the walk. |
| LLR-079 | Kept as child, merged LLR-072 | LLR-079 (child of LLR-009) | Physical containment is how the target guard decides. |
| LLR-080 | Kept | LLR-080; record fields to IF-033; reclaim order to LLR-124; fences to LLR-125 | The owner record and liveness evidence survive; its dependency-direction preamble is component information (CMP-012 notes). |
| LLR-086 | Kept, split | LLR-086 (decision); LLR-116 (measurement, child); LLR-004 (type list, child) | The pure decision, the sampling geometry and the type list are three rows; the per-set counters moved to the run record form. |
| LLR-087 | Kept, split | LLR-087 (atomic publication); LLR-118 (evidence before publication, child) | The new write order lets the next run complete an interrupted publication (SR-082). |
| LLR-088 | Kept as child | LLR-088 (child of LLR-017) | Publication temporaries are a classification rule. |
| LLR-089 | Retired | none (retired at the strip) | It recorded one revision bump; its durable remnants live in LLR-076 and LLR-094. |
| LLR-090 | Kept | LLR-090; claim file form to IF-032; failure classes to LLR-122 | The claim primitive survives. |
| LLR-091 | Kept as child | LLR-091 (child of LLR-090) | Backup claim window. |
| LLR-092 | Kept as child | LLR-092 (child of LLR-090) | Removal claim window. |
| LLR-093 | Kept as child | LLR-093 (child of LLR-090) | Claim file lifecycle and invisibility. |
| LLR-094 | Kept as child | LLR-094 (child of LLR-090) | Repair and kit-refresh claim window. |

Ids absent from the legacy registry when it was stripped (no row to map): LLR-012, LLR-013, LLR-019, LLR-081, LLR-082, LLR-083, LLR-084, LLR-085. They are not reused.

## IF-001 (legacy HomeHub contract): retired, split

| Part of IF-001 | Where it went |
|---|---|
| Container action words, environment variables, argument pass-through, default action | IF-038, behaviour in LLR-048 |
| Read-only source and config, writable state, backup, change and log mounts | IF-039, behaviour in LLR-147 |
| The change-detection record kept outside a read-only source | IF-029, behaviour in LLR-115 and LLR-104 |
| Exit-code tables for backup, removal, verify and restore | IF-003 and IF-021 (one vocabulary 0 to 4), behaviour in LLR-043 and LLR-040 |
| The restore-kit artifacts deposited in every state | IF-019 |
| The configuration contract (version, closed keys, types, defaults, optional additive keys) | IF-004, IF-005, IF-006; behaviour in LLR-042, LLR-063, LLR-098, LLR-099, LLR-101 |
| Saved-state inventory fields and bytes-reclaimed figure | IF-010, behaviour in LLR-047 |
| Removal mechanism (re-home, prove, then delete) | LLR-045, LLR-046, LLR-127 |
| Verify as a container action, report-only | IF-038, LLR-049 |
| Capacity refusal of a backup | LLR-052 (now value 2, not 1) |
| Compression-effort variable outside the configuration | IF-007, LLR-037 |
| Witness verified before writing | IF-015, LLR-039 |
| "One location set per container invocation" | Dropped: SR-095 makes several locations normal; nothing in the design depends on one set |
| HomeHub owns scheduling, retention policy and its own alert translation | Not an interface of FileBackup: REL-03 and REL-05 in external.toml describe it; DA-09 bridges the outcome |
| "HomeHub must never delete a saved-state folder directly" | A host obligation, outside FileBackup's design; SR-045/SR-046 give the safe removal it should use instead |
| The browse view kept outside the container contract | IF-041 is a native-host view; the container has no view mount (no change) |
| The legacy opt-in exit-code switch | Accepted and meaningless (IF-002, LLR-043) |
