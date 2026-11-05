# Input-restricted candidate derivation

> **Review snapshot:** [Owner review 01](owner-review-01.md) supersedes the retention, reporting, coordination, compatibility and absolute-verification proposals affected by SN-029/046/039/041/033 and the consistency edit to SN-034. The analysis below records the earlier draft, not the current ruling.

This is a validation instrument, not an approved specification or a replacement for the live system requirements. All 82 `F-###` obligations below are **Drafted candidates**. Their 49 stakeholder parents are also Drafted and contain proposed amendments awaiting owner review. Coverage here means an obligation has a candidate home; it does not mean its policy choices, acceptance thresholds, implementation or evidence have been approved.

## Inputs and independence

The derivation used only the project vision in the first 20 lines of the README, the stakeholder-needs, external, assumptions and hats registries, the spine questions, the explicitly authorized spine-authoring skill's validation guidance, and the task instruction. It used an operational-lifecycle decomposition axis, independent of any component map.

**Independence limitation:** the agent's inherited context contained architecture-bearing AGENTS instructions. Those instructions were not used to derive these candidates, but their visibility prevents an honest claim of a fully blind session. No current SR, LLR or TC registry, source implementation, audit, migration plan or implementation evidence was opened. A separate alignment reviewer must assess this limitation rather than treating this document as a pristine blind experiment.

The input instruction requires native backup and maintenance on Windows, Linux and macOS, with carried PowerShell and bash recovery independent of a Rust engine. This derives delivered capabilities, not a language choice for implementation. General hooks remaining disabled is a process constraint outside this product derivation. The candidate identifiers are local to this exercise and are not live SR identifiers.

## Reading the candidates

Each row makes one externally observable decision. `Parents` lists the normative need sources, `Boundary` the external crossing, and `Hat-Refs` attributes only a failure class that the row prevents. `—` means no attribution recorded. `Q-##` marks an unresolved stakeholder policy or threshold; a row depending on it is not acceptance-ready until that choice is resolved. The obligation and fit columns deliberately name capability classes, not implementation files or symbols.

The two levels are lifecycle groups and candidate obligations. Lower decomposition should add an independent decision or verification purpose; reproducing these sentences as children would add no assurance. Cross-cutting obligations have one home and apply to the declared operation set. They are not repeated as a condition in every capability.

## 1. Deliver, configure and start

| ID | Candidate obligation | Parents | Boundary | Observable fit condition | Hat-Refs |
|---|---|---|---|---|---|
| F-001 | The product shall deliver native backup and maintenance execution for its declared Windows, Linux and macOS host combinations without an installed engine language runtime or development toolchain. | SN-055 | B-10, B-22 | Backup, state listing/removal, verification/repair, kit refresh and browse generation run on every declared OS/CPU combination using only declared optional tools; unsupported combinations are identified. Matrix pending Q-01. | CROSS-PLATFORM |
| F-002 | Where container operation is selected, the product shall perform backup, state removal and state reporting with read-only source access and an unprivileged execution identity. | SN-024, SN-037 | B-01, B-12, B-22 | Each action completes with the host lacking the engine runtime, compressed backup remains recoverable, and its outcome matches direct execution. DA-13 bounds platform enforcement. | SECURITY |
| F-003 | When a container launch omits its action, the product shall select backup. | SN-024 | B-12 | An otherwise valid actionless launch produces the backup outcome and does not select a destructive maintenance action. | — |
| F-004 | If a required execution component is absent or unsupported, then the product shall refuse affected work before changing the backup. | SN-015, SN-022 | B-10, B-18, B-06, B-15 | Each missing required component produces non-success naming the component and acquisition route; protected backup bytes remain unchanged. Required versus optional classification is published for each setting and route. | UNATTENDED-OPS |
| F-005 | The product shall deliver a versioned configuration contract consistent with its launch validation. | SN-050 | B-05, B-07, B-23 | Every declared valid/invalid configuration class has the same result in the contract and validation; the shipped example is accepted after location substitution; each configuration declares its version. | — |
| F-006 | If configuration is missing or invalid, then the product shall reject the request without creating or changing backup data. | SN-027 | B-05, B-07, B-08 | Missing configuration, unknown settings, wrong types, absent required settings and unsupported versions each produce configuration refusal identifying the offending setting and expectation, with zero backup changes. | UNATTENDED-OPS |
| F-007 | The product shall provide a guided path from a supported clean host to a first successful backup. | SN-012 | B-11, B-23 | A new owner completes configuration and backup using only shipped guidance and its helper; each prerequisite is obtained or identified with acquisition instructions. Host/tool matrix pending Q-01. | — |
| F-008 | The product shall distribute third-party components only with permitted distribution terms and the notices those terms require. | SN-054 | B-13, B-22 | Each bundled component in native releases, recovery kits and containers has applicable distribution permission and accompanying required notices; separately installed dependencies are identified separately. | LEGAL |
| F-009 | The product shall declare its supported store-continuation and recovery combinations. | SN-040, SN-041 | B-13, B-22, B-23 | An owner can determine whether a given store/writer/kit combination supports continuation, recovery and kit refresh without trial mutation. The declared matrix includes retired-format guidance. | STORE-FORMAT-COMPATIBILITY |
| F-010 | Where a writer/reader host combination is declared supported, the product shall exchange its stores without content conversion. | SN-023 | B-02, B-13, B-16 | Each declared Windows/Linux/macOS combination continues and recovers shared, raw and compressed content with unchanged file bytes and distinct supported paths. Metadata exceptions are explicit. | CROSS-PLATFORM |

## 2. Capture the declared source

| ID | Candidate obligation | Parents | Boundary | Observable fit condition | Hat-Refs |
|---|---|---|---|---|---|
| F-011 | When a backup runs, the product shall account for each file in the declared capture scope as captured or not captured. | SN-001 | B-01, B-02, B-06, B-08 | Hidden, system, dot-named and nested infrastructure-named files are included; new/changed content becomes recoverable; every capture failure names its path and makes the outcome non-success. | UNATTENDED-OPS |
| F-012 | The product shall make capture exclusions and unsupported source-object classes distinguishable from captured content. | SN-001 | B-01, B-06, B-23 | No excluded object or unsupported link is represented as captured; the scope declaration identifies exclusions and their reporting behavior. Exact link/special-object policy pending Q-02; DA-12 is not a silent exclusion license. | FILESYSTEM-SEMANTICS |
| F-013 | While reading a source for backup, the product shall leave source content, modification times, attributes and structure unmodified by its own actions. | SN-037 | B-01 | A readable source with no write permission suffices; no product state is placed there; observed product-originated writes, moves, deletes or metadata changes total zero. Host-managed read effects are excluded. | — |
| F-014 | If a previously populated source becomes missing or appears empty, then the product shall stop without publishing an empty replacement for its saved files. | SN-038 | B-01, B-02, B-08 | The condition at startup or during capture produces non-success and preserves previously captured content; an empty observation is not interpreted as wholesale deletion. | UNATTENDED-OPS |
| F-015 | When the first backup observes an empty source, the product shall accept that source state. | SN-038 | B-01, B-02, B-08 | A valid first backup containing no source files is accepted without the previously-populated-source refusal. | — |
| F-016 | The product shall require an explicit owner action to retire a previously populated source. | SN-038 | B-05, B-07 | Empty or missing listings alone never count as retirement; the declared retirement action is distinguishable from ordinary capture. Its form and consequences remain Q-03. | UNATTENDED-OPS |
| F-017 | If a capture attempt is temporarily unreadable, then the product shall retry within a bounded run-level waiting policy. | SN-052 | B-01, B-06, B-08 | A file becoming readable within the supported retry interval is captured; persistent failures are named; total extra waiting is bounded even with many failing files. Numeric interval, attempts and aggregate bound remain Q-04. | UNATTENDED-OPS |
| F-018 | If a source file remains uncaptured, then the product shall preserve its previously captured recoverable content. | SN-052 | B-02, B-13 | The earlier file bytes remain recoverable after a persistent failure; the latest outcome does not claim that new bytes were captured. | SHARED-CONTENT |
| F-019 | The product shall let the owner choose a deterministic schedule for rereading unchanged-looking file content. | SN-007 | B-05, B-07, B-01 | Offered settings span every run through never; the same policy inputs produce the same due decision; a concealed same-size/same-time edit is captured at its first due reread. Schedule/time rules remain Q-05. | FILESYSTEM-SEMANTICS |
| F-020 | The product shall preserve each supported source path without ambiguous renaming through capture and recovery. | SN-032 | B-01, B-02, B-16 | Unicode, spaces, brackets and parentheses return unchanged where representable, across the declared writer/target matrix. Supported-name and normalization equivalence policy remains Q-06. | CROSS-PLATFORM |
| F-021 | If source names cannot remain distinct on a supported target, then the product shall report the conflicting names without silently merging or overwriting their content. | SN-032 | B-01, B-06, B-15, B-16 | Invalid names, case collisions and normalization collisions yield named findings; unaffected supported paths remain recoverable. Capture-stage disposition remains Q-06. | FILESYSTEM-SEMANTICS |

## 3. Store content, publish history and survive interruption

| ID | Candidate obligation | Parents | Boundary | Observable fit condition | Hat-Refs |
|---|---|---|---|---|---|
| F-022 | The product shall share one stored content copy among identical captured contents in the declared deduplication domain. | SN-002 | B-02, B-13 | Identical files across names, folders, runs and states consume one stored payload copy and each recovers correctly; the domain across independent backup locations remains Q-07. | — |
| F-023 | When new content is stored, the product shall apply the owner's documented compression savings policy. | SN-003 | B-05, B-07, B-10, B-02 | Disabled compression stores new content uncompressed; enabled measurement compresses only when its declared saving criterion is met; the documented file-type fallback applies when measurement is off/unavailable. Threshold and fallback rules remain Q-08. | — |
| F-024 | When existing content is reused or compression settings change, the product shall preserve that content's stored form. | SN-003, SN-048 | B-02, B-13 | Setting changes affect only new content; existing payloads keep their form and recorded states still yield their original bytes. | SHARED-CONTENT |
| F-025 | When a backup changes the captured state, the product shall retain the previous backed-up state as a date-identified recovery choice alongside the latest state. | SN-004 | B-02, B-06, B-13 | After successive changes, every superseded captured state is selectable by its date and the latest state remains available. | SHARED-CONTENT |
| F-026 | When captured source state is unchanged, the product shall report no content changes and create no additional saved state. | SN-021, SN-004 | B-02, B-06, B-08 | Consecutive unchanged runs preserve identical captured-content records, report zero additions/changes/removals and add zero saved states; logs and run times may advance. | — |
| F-027 | The product shall keep distinct saved states distinguishable when their display dates collide or clocks move backwards. | SN-004, SN-006 | B-02, B-06, B-14 | Equal timestamps, clock rollback and timezone changes neither overwrite a state nor prevent unambiguous selection. Display/selection rule remains Q-09; derived from DA-16 and the need for selectable history. | INTEGRITY-RECOVERABILITY |
| F-028 | While performing a declared store mutation, the product shall preserve content required by every remaining recorded state. | SN-034 | B-02, B-13 | After backup, deletion/rename/re-addition, removal, repair or kit refresh, every still-recorded path yields its recorded bytes, including shared content. Externally caused damage remains explicitly distinguishable from product mutation. | SHARED-CONTENT |
| F-029 | If a backup is interrupted, then the product shall leave every published file record backed by complete recoverable content. | SN-013 | B-02, B-13 | Previously completed states remain recoverable and no published progress record points at partially stored bytes. A partially advanced latest state is permitted; storage durability is bounded by DA-01 and DA-15. | INTEGRITY-RECOVERABILITY |
| F-030 | When backup resumes after interruption, the product shall recover disposable working state without requiring manual reconstruction. | SN-013 | B-02, B-06, B-08 | A subsequent run proceeds safely or names the condition preventing safe continuation; interruption alone does not leave an unexplained permanent refusal. | INTEGRITY-RECOVERABILITY |
| F-031 | While one operation mutates a store, the product shall refuse a competing mutation of that store as busy. | SN-039 | B-04, B-08 | Competing backup, removal, repair and kit-refresh operations never both enter protected mutation; the loser changes zero protected data. DA-03 limits supported multi-host/store arrangements. | FILESYSTEM-SEMANTICS |
| F-032 | When a mutating operation ends or its process dies, the product shall relinquish its exclusive claim under the declared host assumptions. | SN-039 | B-04 | The next otherwise valid mutation can proceed after normal exit or process death on supported hosts; no owner cleanup of a dead claim is required. DA-02 bounds the guarantee. | INTEGRITY-RECOVERABILITY |
| F-033 | While a store is being mutated, the product shall allow read-only operations to recover valid results or report interference without taking writer ownership. | SN-039 | B-02, B-04, B-15, B-08 | Reads never own the mutation claim; a concurrent read returns valid recovered content/findings or explicit interference, without claiming an immutable whole-store view. | FILESYSTEM-SEMANTICS |

## 4. Capacity, damage detection and repair

| ID | Candidate obligation | Parents | Boundary | Observable fit condition | Hat-Refs |
|---|---|---|---|---|---|
| F-034 | If available capacity is known to be insufficient, then the product shall report the limitation before undertaking unsafe work. | SN-019 | B-03, B-17, B-06, B-15 | A known-insufficient case refuses the unsafe part without damaging prior recoverable content; required reserves and estimation scope remain Q-10. | FILESYSTEM-SEMANTICS |
| F-035 | If capacity is exhausted while writing, then the product shall terminate affected work without losing previously recoverable content or claiming completion. | SN-019 | B-02, B-16, B-08, B-15 | Mid-write exhaustion returns non-success, preserves completed stored content/prior states and permits retry after capacity returns. Preflight success does not suppress this outcome. | INTEGRITY-RECOVERABILITY |
| F-036 | When reporting capacity limits, the product shall identify the affected volume and available measurements with their uncertainty. | SN-019 | B-03, B-17, B-06, B-15 | Host-supplied values and volume identity are reported where measurable; unavailable measurements are explicit; estimates are not described as guarantees. DA-06 is not assumed for quota/thin-provisioned/concurrently used storage. | FILESYSTEM-SEMANTICS |
| F-037 | If external deletion removes stored content still available at the source, then the next backup shall recapture that content. | SN-031 | B-01, B-02, B-13 | A deleted stored copy is restored from a readable source; an additional identical source file does not reuse nonexistent content; the latest state recovers correctly after the run. | UNATTENDED-OPS |
| F-038 | When a whole-store check is requested, the product shall report each recorded file affected by missing, altered or incorrectly described stored content. | SN-030 | B-02, B-06, B-08 | Latest and all saved states are covered; findings name affected paths and damage class; an intact store is clean and induced discrepancies produce non-success. DA-05/DA-11 delimit identity assurance. | INTEGRITY-RECOVERABILITY |
| F-039 | While checking store integrity, the product shall leave the checked store unchanged. | SN-030 | B-02 | Before/after store contents are byte-identical, including damaged content and records. Reporting destinations must respect this boundary. | — |
| F-040 | When repair is requested for a problem with a certain correct resolution, the product shall apply that resolution without reducing existing recoverability. | SN-047, SN-034 | B-02, B-13 | Each supported certain repair class clears its finding and every previously recoverable state still recovers; the class list and sufficient evidence remain Q-11. | SHARED-CONTENT |
| F-041 | If a repair lacks a certain correct resolution, then the product shall retain and report the unresolved problem. | SN-047 | B-02, B-06, B-08 | Ambiguous or unsupported damage is not guessed away, remains identifiable after repair, and does not receive a clean outcome. Certainty rules remain Q-11. | INTEGRITY-RECOVERABILITY |
| F-042 | When removal or repair encounters a crafted path or link, the product shall confine its mutations to the selected store's authorized scope. | SN-029, SN-047 | B-02, B-05, B-07 | An escape attempt changes no outside content and returns a named refusal/finding. This is a SECURITY-derived candidate requiring upward review: selective retention/repair authority does not authorize arbitrary filesystem modification. Exact scope/alias rules remain Q-12. | SECURITY |

## 5. Retain, continue and inspect

| ID | Candidate obligation | Parents | Boundary | Observable fit condition | Hat-Refs |
|---|---|---|---|---|---|
| F-043 | When state removal is being considered, the product shall report its stored-content reclamation accounting. | SN-046 | B-02, B-06, B-08 | Each state distinguishes bytes reclaimed from bytes retained or relocated; with no intervening change, removal matches the content-byte accounting. Filesystem allocation and unrelated free-space changes are not counted as a promise. | — |
| F-044 | While preparing a saved-state or reclamation report, the product shall leave the store unchanged. | SN-046 | B-02, B-08 | Report production changes no stored content or state and does not begin removal. | — |
| F-045 | When the owner requests removal of a saved state, the product shall remove only recovery content unneeded by the remaining states. | SN-029, SN-034 | B-02, B-05, B-07, B-13 | Removing an older, intermediate or newer state preserves the latest and every other state, including a shared copy initially located with the removed state, in raw and compressed forms. | SHARED-CONTENT |
| F-046 | If requested removal cannot preserve remaining-state recovery, then the product shall refuse it before changing the store. | SN-029 | B-02, B-08 | An unsafe removal produces its documented refusal outcome and zero store changes. | SHARED-CONTENT |
| F-047 | If state removal is interrupted, then the product shall preserve recoverability and permit the removal to be safely retried. | SN-029 | B-02, B-13 | At interruption points, retained states recover; rerunning the requested removal completes or gives an actionable safe refusal without losing their content. DA-01/DA-15 bound physical durability. | INTEGRITY-RECOVERABILITY |
| F-048 | If a store format is outside the requested operation's support, then the product shall refuse that operation before store mutation. | SN-040, SN-041 | B-02, B-06, B-08 | Unsupported continuation/refresh names the format and supported options; original content and recovery kit remain untouched; guidance permits retaining the old store and using a new one. No migration capability is inferred. | STORE-FORMAT-COMPATIBILITY |
| F-049 | When the owner requests kit refresh on a supported store, the product shall update carried recovery capability without reducing recoverability. | SN-041, SN-055 | B-02, B-13 | Previously recoverable states still recover after refresh, with the documented independent tools. Unsupported combinations take F-048. | STORE-FORMAT-COMPATIBILITY |
| F-050 | When a supported newer writer continues a store, the product shall preserve recovery of its earlier states through the declared kit combinations. | SN-041 | B-02, B-13, B-18 | Older states recover correctly after newer writes for every declared supported store/kit combination; an older carried kit is not silently stranded. | STORE-FORMAT-COMPATIBILITY |
| F-051 | Where browsing is enabled, the product shall expose the latest backed-up paths for name search and access to their stored content. | SN-008 | B-06, B-20 | Each path, including duplicates, appears after the latest run; search locates it and opening its entry accesses the associated stored content without full-tree restoration. Compressed-entry behavior remains Q-13. | — |
| F-052 | The product shall keep recoverability independent of the optional derived browse view. | SN-008, SN-034 | B-20, B-13 | Removing or rebuilding the view loses no recorded content and changes no recovery result. Boundary-derived candidate: EXT-15 explicitly makes the view rebuildable; upward review confirms this property. | SHARED-CONTENT |
| F-053 | Where space analysis is enabled, the product shall expose backed-up files ranked by their recorded space use. | SN-051 | B-06 | The owner can identify largest contributors with declared units and shared-content attribution; attribution among duplicate paths remains Q-14. | — |
| F-054 | Where optional media measurement is enabled and available, the product shall expose its encoding-density measure without making backup correctness depend on that measure. | SN-051, SN-015 | B-10, B-06, B-20 | Enabled supported media has a declared measure; disabled/unavailable measurement is visibly not taken and has the same capture/recovery outcome as a run without the extra. Metric definition remains Q-14. | UNATTENDED-OPS |

## 6. Recover on a clean host

| ID | Candidate obligation | Parents | Boundary | Observable fit condition | Hat-Refs |
|---|---|---|---|---|---|
| F-055 | The product shall deliver a complete-store recovery capability independent of the backup engine and its repository. | SN-005 | B-13, B-18 | The complete store copied to a clean machine with documented local tools restores latest and earlier states without network access; shared content may reside anywhere in the store. DA-19 excludes copying a state directory alone. | CROSS-PLATFORM |
| F-056 | The product shall carry PowerShell recovery for Windows and bash recovery for Linux and macOS independent of the engine executable. | SN-022, SN-055 | B-13, B-18, B-19 | Each supported route recovers offline with the engine, its build toolchain and repository absent; a Rust executable is unnecessary. Local shell/tool prerequisites are declared and checked by F-004. | CROSS-PLATFORM |
| F-057 | When recovery selects a state, the product shall restore exactly that state, defaulting to the latest when none is selected. | SN-006 | B-14, B-16 | A dated historical selection yields only its recorded paths/content, with no newer-state mixing; omitted selection yields latest. Collision disambiguation follows F-027. | — |
| F-058 | If a recovery target resolves inside the backup being recovered, then the product shall refuse before writing. | SN-042 | B-14, B-17, B-15 | Direct and link-aliased targets inside the store yield non-success and zero writes; valid outside targets are accepted. | SECURITY |
| F-059 | If a recovery entry would write outside the chosen target, then the product shall reject that entry. | SN-042 | B-13, B-16, B-17, B-15 | Traversal and link-mediated escape cases create no outside writes, identify the entry and produce non-success; unaffected safe entries remain recoverable. Existing-target/link-race scope remains Q-12. | SECURITY |
| F-060 | If a state record cannot be interpreted safely, then the product shall refuse it or report invalid entries without unsafe writes. | SN-025 | B-13, B-15, B-16 | Unreadable/structurally invalid records never produce an unqualified successful recovery; each accepted recovered file is validated against the selected record. Whole-record versus entry-level salvage remains Q-15. | INTEGRITY-RECOVERABILITY |
| F-061 | The product shall communicate the assurance limits of state-record interpretation and per-file content validation. | SN-025 | B-15, B-23 | Recovery guidance and outcomes do not claim authentication of a well-formed externally substituted or shortened record from parsing/content checks alone. Stronger completeness/authenticity assurance remains Q-15. | — |
| F-062 | When recovery reports a file restored, the product shall have verified its written content against the selected state's recorded content identity. | SN-033 | B-13, B-16, B-18, B-15 | Altered, flipped or truncated content is never reported as correctly restored; valid writes match recorded length/content identity under DA-05/DA-18. | INTEGRITY-RECOVERABILITY |
| F-063 | If the initially located stored copy is damaged and an intact equivalent is available in the complete store, then recovery shall use the intact copy or report the file unrecovered. | SN-033 | B-13, B-16, B-15 | The damaged candidate never yields false success; recovery produces verified original bytes or a named non-success. Search/repair promises beyond the parent's explicit alternative remain Q-16. | INTEGRITY-RECOVERABILITY |
| F-064 | If some content cannot be recovered, then recovery shall continue with the other recoverable files. | SN-053 | B-13, B-16, B-15 | Every unaffected supported file is written correctly; every unrecovered path has its cause, failure count and non-success outcome. A host-wide inability to write remains a host failure rather than a promise of impossible progress. | — |
| F-065 | The product shall restore each file's own recorded modification time within the target's declared representational capability. | SN-036 | B-16 | Identical files with different times retain their own times through each recovery route and storage form; precision/rounding and unsupported cases are declared under Q-17 and DA-07. | FILESYSTEM-SEMANTICS |
| F-066 | The product shall recreate recorded empty directory structure during recovery. | SN-036 | B-16 | Empty and nested empty directories exist at their recorded relative paths in the recovered tree. | — |
| F-067 | The product shall apply recorded directory attributes supported by the recovery target and report those it cannot apply. | SN-036 | B-16, B-15 | Windows Hidden/System attributes return where supported; elsewhere directories are created and unsupported attributes are named rather than silently discarded. | CROSS-PLATFORM |
| F-068 | The product shall recover supported in-tree links as links to the corresponding recovered locations. | SN-036 | B-01, B-13, B-16, B-15 | A link between two captured folders points to the recovered folder, not the original source; unsupported target links are reported. Link kinds, cycles, dangling and external targets remain Q-02. | CROSS-PLATFORM |
| F-069 | When recovery is started interactively from the backup on Windows or macOS, the product shall guide target selection and retain the result until dismissed. | SN-035 | B-14, B-15, B-19 | A double-click start needs no remembered command, obtains a target and keeps its outcome visible; argument-driven scripted execution follows F-071 without a prompt. | — |
| F-070 | The product shall report recovery outcomes using consistent documented result classes across its supported routes. | SN-026 | B-15 | Complete, incomplete-content, invalid-request/record and host/tool cases produce the same semantic class through every route; a person or script obtains it without parsing the log. Exit-code mapping/mixed-failure precedence remain Q-18. | CROSS-PLATFORM |

## 7. Supervise the whole product

| ID | Candidate obligation | Parents | Boundary | Observable fit condition | Hat-Refs |
|---|---|---|---|---|---|
| F-071 | While operating unattended, the product shall complete or fail without requesting a human answer. | SN-011 | B-07, B-08, B-14, B-15 | Backup, maintenance and scripted recovery never block on a prompt; missing answers produce a reasoned non-success. | UNATTENDED-OPS |
| F-072 | When one configured source/backup location fails, the product shall continue processing the other independent locations and return an aggregate non-success. | SN-009 | B-07, B-01, B-02, B-08 | Healthy locations complete despite another location's failure; the overall result cannot be success when any required location failed. | UNATTENDED-OPS |
| F-073 | The product shall return documented operational outcome classes for backup, removal and check. | SN-045 | B-08 | Complete, partial failure, configuration refusal and busy/not-ready refusal are distinguishable from the result alone; class encoding and multiple-failure precedence remain Q-18. | UNATTENDED-OPS |
| F-074 | When listing or checking is requested, the product shall return findings in a documented program-readable form. | SN-045, SN-046 | B-08 | A host reads state identities, applicable reclamation accounting and check findings without parsing prose; schema/version and error-envelope choices remain Q-18. | — |
| F-075 | When a run completes or fails, the product shall expose its file-level change/failure account and summary counts. | SN-044 | B-06, B-20 | Added, changed, removed and failed paths are named; each failure has a cause; counts agree with the recorded events. Reporting-failure policy remains Q-19. | UNATTENDED-OPS |
| F-076 | While a long run is executing, the product shall expose progress within the declared maximum reporting interval. | SN-044 | B-06, B-20 | No active-execution reporting gap exceeds the owner-approved interval; it must satisfy the parent's 'every few minutes' intent. Numeric limit remains Q-19; DA-22 addresses host suspension. | UNATTENDED-OPS |
| F-077 | When an operation refuses work, the product shall explain the observed condition and an actionable next step. | SN-044, SN-015, SN-027 | B-06, B-15 | Each declared refusal class names what was found and what the user can do; detail never requires interpreting an unexplained internal error identifier. | UNATTENDED-OPS |
| F-078 | Where run notification is configured and enabled, the product shall send its success/failure result without allowing notification delivery to change that result. | SN-010 | B-09, B-06, B-08 | Enabled runs issue the appropriate message; disabled/unconfigured runs issue none; sending failure records a warning and preserves the underlying run outcome. Arrival depends on the relay; DA-09 does not promise owner attention. | UNATTENDED-OPS |
| F-079 | The product shall keep notification credentials unreadable in plain form from configuration, backups and operational records. | SN-049 | B-05, B-07, B-09, B-20, B-21 | Plaintext-bearing configuration is refused or never produced; supported provisioning and failure paths expose zero plaintext credentials in those locations. DA-20 and per-host facility support require Q-20. | SECURITY |
| F-080 | The product shall meet declared time and peak-memory budgets for few-change backup, whole-store check and full recovery at its supported library scale. | SN-043 | B-01, B-02, B-16, B-22, B-23 | Each operation stays within numeric budgets on the declared host/workload, including terabytes and millions of files. No numeric values are invented here; Q-21 blocks acceptance readiness. | PERFORMANCE |
| F-081 | The product shall keep few-change backup time from scaling linearly with stored history alone. | SN-043 | B-01, B-02 | With source/workload/host fixed, doubling stored history does not double few-change-run time. Measurement conditions, tolerances and relationship to absolute budgets remain Q-21. | PERFORMANCE |
| F-082 | The product shall use one truthful definition of complete success across its declared operating and recovery routes. | SN-001, SN-025, SN-033, SN-045, SN-053 | B-08, B-15 | A required omitted/uncaptured/unvalidated file cannot be hidden by another route's success label; partial outcomes retain their causes. Optional features explicitly permitted to degrade, such as notification, are not reclassified as failed capture. This is a package-wide consolidation, not an extra exit-code taxonomy. | UNATTENDED-OPS |

## Open policy decisions and intake findings

These are questions for stakeholder/requirements review, not authorization to choose implementation defaults. Parent text already establishes the safety floor named below. An unresolved decision must not weaken that floor.

| ID | Unresolved decision and affected candidates |
|---|---|
| Q-01 | Declare OS releases, CPU architectures, filesystem/mount classes and local tool floors for native operation, containers and each recovery route. SN-055 does not mean every CPU or every filesystem. F-001/004/007/010/056 need a closed matrix. Include actual native macOS and Windows evidence later; a Linux-only or simulated-volume result cannot establish it. |
| Q-02 | Define capture/recovery scope for symbolic links, junctions, hard links, link cycles, dangling links, external links and special files. SN-036 demands supported in-tree links, while SN-001 requires honest accounting of unsupported objects. Decide whether source link traversal is permitted and what an excluded link report means. B-01/B-16 currently omit explicit link transport; propose frame clarification. F-012/068 remain partially open. |
| Q-03 | Define explicit source-retirement action and its effect on latest state/history. F-014's empty-source protection is fixed; F-016 must not invent deletion authorization or a retention policy. |
| Q-04 | Set retry count, minimum/maximum delay and aggregate extra-wait bound, including the meaning of 'briefly' unreadable and fairness across many failures. A per-file bound alone does not establish SN-052's bounded total delay. F-017. |
| Q-05 | Specify reread schedules, units, clock behavior and treatment of absent/corrupt scheduling state. DA-14 is intentionally defeasible; its obstacle motivates the offered reread setting. DA-04/DA-21 do not establish database-consistent live capture; state that limit or raise a separate need if demanded. F-019. |
| Q-06 | Choose the supported portable-name domain and whether unportable paths are refused at capture, retained with target-specific recovery restrictions, or otherwise handled. Define normalization equivalence, case-collision detection and target-side disposition without silently renaming or merging. F-020/021. DA-08 is conditional, not evidence that all Unicode names port unchanged. |
| Q-07 | Decide deduplication scope across independent configured backup locations. SN-002's universal language and SN-009's independence permit a domain ambiguity. One copy within a complete store is clear; global cross-store sharing could destroy handoff independence. F-022 must not silently introduce a global shared service. |
| Q-08 | Set the compression savings criterion, measurement scope, fallback file-type policy and required tool behavior. Vision calls for measured savings and fallback; no algorithm, extension list or numeric cutoff is inferable. F-023. |
| Q-09 | Set date display, timezone and selection rules for colliding timestamps. F-027 derives the no-loss/no-ambiguity outcome; it does not choose a folder layout or timestamp encoding. B-14 describes selection by starting folder whereas SN-006 describes selection by date; the frame must support the outcome without forcing one interface. |
| Q-10 | Set capacity preflight scope, unknown-capacity behavior, reserve/headroom policy and treatment of temporary/relocation space. Known insufficiency and actual exhaustion must be safe regardless of estimates. DA-06's strong premise is limited to its holding conditions; F-034/036 must remain honest under quotas and concurrent writers. |
| Q-11 | Enumerate repair classes and what evidence makes each resolution certain, including missing content, wrong storage-form records, duplicate or unreferenced content and damaged state records. Define destructive versus reversible repair authority. SN-047 does not authorize guessing missing historical bytes or unconditional cleanup. F-040/041. |
| Q-12 | Define authorized mutation scope, filesystem alias handling, preexisting recovery-target conflicts, overwrite permission and supported protection against concurrent link replacement. SN-042 fixes the no-outside-write guarantee; it does not settle all target overwrite semantics. F-042 is an explicitly derived upward-review candidate, not an assumed parent mandate. F-058/059 share the scope question. |
| Q-13 | Define what opening a compressed browse entry exposes: archive, contained file or a prepared readable view. SN-008 says stored content and does not select a materialization mechanism. F-051 must also define freshness/reporting when view generation fails. |
| Q-14 | Define space attribution for shared content and the media encoding metric/units, handling unknown values distinctly from zero. SN-051 supports advice, not automatic media re-encoding or source modification. F-053/054. |
| Q-15 | Decide whether malformed records are refused wholesale or salvaged entry by entry; specify duplicate-row and unsupported-record handling. Current SN-025 explicitly limits assurance for well-formed shortened/substituted records. If authenticity/completeness against that threat is wanted, amend the need; do not silently add a witness, signature, checksum sidecar or authentication service. F-060/061. |
| Q-16 | Decide whether recovery must exhaustively seek alternative intact copies or may report the affected file unrecovered after detecting damage. SN-033 explicitly allows either verified recovery or named failure; F-063 preserves that alternative. An automatic healing promise would need stronger parent text and a bounded search policy. |
| Q-17 | Declare timestamp precision and unsupported metadata outcomes across target filesystems, including coarse timestamp rounding. SN-036 expressly demands file times, empty folders, directory Hidden/System and supported in-tree links; permissions, ownership, ACLs, resource forks and alternate streams are not silently added. F-065/067. |
| Q-18 | Define operational/recovery result encodings, machine-readable schema compatibility, aggregation and simultaneous-failure precedence. Preserve SN-045's operational distinctions and SN-026's recovery distinctions without assuming identical numeric exits for both domains. F-070/072/073/074/082. |
| Q-19 | Choose a numeric progress interval satisfying 'every few minutes' and state reporting behavior when the log/view destination is inaccessible or full. Define which report remains available on early refusal. F-075/076/077; B-20 promises visible reporting failure but does not select the final outcome. |
| Q-20 | Declare supported native credential facilities and account/host-transfer behavior. SN-049 forbids exposed plaintext in the stated locations; DA-20's account binding may need platform-specific qualification. Missing notification credentials must follow the notification/dependency policy without leaking secrets. F-079. |
| Q-21 | Set file count/size/distribution/history depth, changed fraction, storage/CPU/RAM class, cache conditions, operation time budgets, memory limits and timing tolerance. SN-043 currently lacks those values. F-080/081 are measurable templates, not a fabricated benchmark contract. |

Additional frame/assumption review: B-24 is explicitly retired and produces no candidate source-write obligation. The external registry's introductory prose still describes only two delivery crossings in container-oriented terms, while B-22 now includes native delivery; the rows, not that stale summary, were used. DA-17 explicitly limits what mapped temporary drives establish. DA-10 permits prerequisite installation, but SN-005/022 require recovery itself to work offline once the declared tools are available. DA-05/11 describe accidental-damage/content-identity assumptions and do not authenticate a record's provenance. DA-01/15 require an explicit distinction between process interruption and physical power-loss assurance. These are review findings, not automatic amendments in this document.

## Hat outcomes for this derivation

Every roster hat was considered against its question and failure class. Attribution is not a quota. Cross-platform and filesystem properties often apply to needs without the corresponding tag; those reachability gaps are listed below for the authoring reviewer rather than hidden by the table.

| Hat | Outcome |
|---|---|
| INTEGRITY-RECOVERABILITY | Interruption/restart, exclusive-claim release, physical-capacity failure, validation and uncertain repair have explicit homes at F-027/029/030/032/035/038/041/047/060/062/063. DA-01/15 prevent claiming that a process-kill result proves power-loss persistence. |
| SECURITY | Credential exposure, privilege and filesystem escape appear at F-002/042/058/059/079. F-042 is derived and requires upward feedback; no general encryption-at-rest, adversarial collision resistance or arbitrary hook system is inferred. DA-05/11 delimit accidental content-damage assumptions, but do not waive path confinement. |
| SHARED-CONTENT | F-028 is the package-wide protection rule; F-018/024/025/040/045/046/052 address independent boundary outcomes that depend on it. F-052 is explicitly boundary-derived. Q-07 prevents global deduplication being assumed across independent stores. |
| STORE-FORMAT-COMPATIBILITY | F-009/048/049/050 expose compatibility decisions and refusals. No automatic migration or perpetual support for every historical format is invented. |
| FILESYSTEM-SEMANTICS | Scope, names, metadata, lock interoperability, concurrent readers and capacity assumptions produce F-012/019/021/031/033/034/036/065 and Q-01/02/06/10/12/17. Matrix evidence must later cover actual supported filesystem semantics. |
| UNATTENDED-OPS | Bounded retry, honest degraded outcomes, progress and refusal explainability have explicit homes, including F-071/075/076/077/082. Notification delivery cannot redefine capture success. No automatic scheduler or host-alert acknowledgement is inferred from DA-09. |
| CROSS-PLATFORM | Native operation, store exchange, names, independent script recovery, metadata/link limits and result parity are addressed at F-001/010/020/055/056/067/068/070. Host versions and tool floors remain Q-01 rather than unstated universal support. |
| PERFORMANCE | F-080/081 carry the package-wide scale promises; Q-04 also prevents retry multiplication. No bounded memory implementation strategy or invented throughput target is imposed. Missing numeric budgets are a stakeholder-policy gap. |
| LEGAL | F-008 covers native bundles, kits and containers. Optional separately installed tools are distinguished from redistribution; no new license approval service or dependency architecture is inferred. |

Tag reachability observations: F-001 and F-010 portability follows SN-055 and SN-023's explicit host promises and their backup-host tags; SN-005's restore-host tag reaches clean-host recovery. SN-039 has filesystem/backup-host tags but its read-only recovery consequences also touch recovery behavior. SN-042 has no filesystem or restore-host tag despite link-resolution dependence. SN-033 and SN-053 have no unattended tag although scripted outcomes reach hosts. These are proposed intake checks, not silent tag edits. A hat attribution in this candidate table records the actual failure question considered; it does not assert the current tag-driven brief already reaches it.

## Coverage of all 49 needs

Each current need appears exactly once in this index. Candidate references may serve more than one parent where they state one common external decision. Open questions qualify readiness, not whether the need was considered.

| Need | Candidate homes | Open policy |
|---|---|---|
| SN-001 | F-011, F-012, F-082 | Q-02 |
| SN-002 | F-022 | Q-07 |
| SN-003 | F-023, F-024 | Q-08 |
| SN-004 | F-025, F-026, F-027 | Q-09 |
| SN-005 | F-055 | Q-01 |
| SN-006 | F-027, F-057 | Q-09 |
| SN-007 | F-019 | Q-05 |
| SN-008 | F-051, F-052 | Q-13 |
| SN-009 | F-072 | Q-18 |
| SN-010 | F-078 | — |
| SN-011 | F-071 | — |
| SN-012 | F-007 | Q-01 |
| SN-013 | F-029, F-030 | Q-01 |
| SN-015 | F-004, F-054, F-077 | Q-01 |
| SN-019 | F-034, F-035, F-036 | Q-10 |
| SN-021 | F-026 | — |
| SN-022 | F-004, F-056 | Q-01 |
| SN-023 | F-010 | Q-01, Q-06, Q-17 |
| SN-024 | F-002, F-003 | Q-01 |
| SN-025 | F-060, F-061, F-082 | Q-15 |
| SN-026 | F-070 | Q-18 |
| SN-027 | F-006, F-077 | — |
| SN-029 | F-042, F-045, F-046, F-047 | Q-12 |
| SN-030 | F-038, F-039 | Q-15 |
| SN-031 | F-037 | — |
| SN-032 | F-020, F-021 | Q-06 |
| SN-033 | F-062, F-063, F-082 | Q-16 |
| SN-034 | F-028, F-040, F-045, F-052 | Q-11, Q-12 |
| SN-035 | F-069 | Q-01 |
| SN-036 | F-065, F-066, F-067, F-068 | Q-02, Q-17 |
| SN-037 | F-002, F-013 | — |
| SN-038 | F-014, F-015, F-016 | Q-03 |
| SN-039 | F-031, F-032, F-033 | Q-01 |
| SN-040 | F-009, F-048 | Q-01 |
| SN-041 | F-009, F-048, F-049, F-050 | Q-01 |
| SN-042 | F-058, F-059 | Q-12 |
| SN-043 | F-080, F-081 | Q-21 |
| SN-044 | F-075, F-076, F-077 | Q-19 |
| SN-045 | F-073, F-074, F-082 | Q-18 |
| SN-046 | F-043, F-044, F-074 | Q-18 |
| SN-047 | F-040, F-041, F-042 | Q-11, Q-12 |
| SN-048 | F-024 | Q-08 |
| SN-049 | F-079 | Q-20 |
| SN-050 | F-005 | — |
| SN-051 | F-053, F-054 | Q-14 |
| SN-052 | F-017, F-018 | Q-04 |
| SN-053 | F-064, F-082 | — |
| SN-054 | F-008 | — |
| SN-055 | F-001, F-049, F-056 | Q-01 |

## Handoff to alignment

The separate alignment pass may read both this candidate set and the legacy chain, classify matched / orphaned-in-legacy / orphaned-in-fresh obligations, and read each legacy orphan's rationale before deciding whether it is implementation-derived, evidence of an understated need, or accretion. No candidate is automatically inserted and no legacy obligation is automatically deleted. The two explicit derived candidates and date-identity constraint require upward review. All unresolved policy rows remain visible to that review, especially where a candidate fit condition cannot yet be evaluated numerically.

This exercise made no implementation claim and ran no implementation tests. It stops at candidate obligation and observable fit; mechanism, numeric policy approval, detailed verification design and authoritative trace reconciliation belong to later authorized work.

## Authoring follow-through

After this candidate pass, the coordinator added the missing filesystem/restore-host tags for containment and browse behavior, unattended tags for recovery verification/salvage, scale tags for retention accounting, and backup-host tags for native provisioning and credentials. The delivery-frame introduction now includes native releases. The observations above describe the input snapshot; these reachability corrections do not approve the candidates.
