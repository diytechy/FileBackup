# Candidate-to-legacy system requirement alignment

Reconciliation proposal, 2026-11-05. This is not owner adjudication, a replacement specification, approval of amended needs, or runtime evidence. No normative requirement, approval status, code or test was changed by this review.

The separate alignment reviewer read all 123 current SR statements, rationales and acceptance criteria in [the system registry](../../requirements/system-requirements.toml), the revised 49 needs and boundary/assumption/hat registries, and all 82 [fresh candidates](fresh-derivation.md). Earlier architecture and audit exposure is explicit. Reading both sides is permitted for this alignment role; it does not make the preceding derivation fully blind. Its inherited architecture context remains a limitation. Matching below compares actual obligations and acceptance intent, not shared parent IDs. No LLR/TC-chain completeness or implementation verification is claimed.

The amended needs are Drafted proposals. An apparent conflict with them is a reconciliation item, not permission to delete an existing obligation. Audit references refer to [A01–A24](../../requirements-audit-2026-11-05.md).

Review accounting: **123 legacy rows = 42 matched outcomes + 63 partial/conflicting matches + 18 legacy-only** (7 derived/design candidates, 4 missing/understated-outcome decisions, 7 retirement proposals). **82 candidates = 76 with a semantic match to at least one legacy row + 6 fresh-only**. These are review buckets, not approval or implementation coverage scores. The two indexes contain 130 manually chosen semantic links.

## Reading the map

- **M — matched outcome:** a fresh candidate carries the legacy row's central observable obligation. This does not approve every threshold, interface detail or implementation, or imply identical wording.
- **P — partial match/conflict:** only the stated kernel matches; the note identifies changed scope, a stronger legacy promise or an uncarried clause. No replacement by the weaker text is implied.
- **L — legacy-only:** no fresh candidate explicitly carries the row's distinctive obligation. Related generic safety requirements are not counted as matches.
- Legacy-only classifications: **D** = implementation-derived/design or perspective-derived constraint candidate; **N** = missing/understated stakeholder outcome or scope decision; **R** = accretion/retirement proposal after changed premises. Classification follows reading the row's own rationale. A sound D/N obligation is retained for explicit placement or owner decision; R is a proposal, not a deletion.

Candidate policy placeholders do not erase existing numbers. In particular, the legacy three-attempt, 60-second aggregate retry proposal; 256 KiB/10% compression proposal; 120-second progress interval; and million-file/2 TiB/365-state, 4 GiB/eight-hour/30-minute budgets remain named policy inputs for review. Existing code disagreement is evidence of work or conflict, never sufficient grounds to weaken a sound need.

## 1. Deliver, configure and admit work

| Legacy SR | Candidate match | Class | Semantic alignment and proposed disposition |
|---|---|---|---|
| SR-018 | F-006 | M | Missing, retired/unknown, wrongly typed and unsupported configurations refuse before backup mutation. Preserve the stronger no-log-truncation/no-created-output acceptance as an admission detail. |
| SR-019 | F-004 | P | Required-component refusal matches; runtime/hash-fetch examples need native/bundled-component treatment. Optional dependencies must not become required incidentally. |
| SR-027 | F-007 | M | Shipped guidance/helper leads a new owner to a successful first backup. Extend demonstrated hosts, not the meaning of success. |
| SR-033 | F-010 | P | Writer/reader interchangeability matches; legacy Windows/Linux pair omits macOS and declared filesystem/name limitations. A15. |
| SR-034 | F-002 | M | Container backup avoids host runtime installation and carries required execution components; native delivery is an additional route, not replacement of this outcome. |
| SR-042 | F-005 | P | Configuration-description/validator agreement matches. Native-Windows and JSON form support needs an explicit compatibility matrix; no automatic deletion of either form. A10/A19. |
| SR-048 | F-002, F-074 | M | Container removal/reporting and direct-execution outcome/findings parity match. Preserve unknown-state refusal and read-only report acceptance. |
| SR-061 | F-048 | P | Unsupported-form refusal matches. Legacy also requires positive form recognition, restore pre-target refusal and per-entry damage distinction; carry these forward, and decide mixed supported/unsupported store scope. A10. |
| SR-063 | — | L/D | Rationale protects source, stored data and unrelated owner files from regenerated listings. Keep a derived overlap/ownership guard; revise blanket backup overlap to distinguish an authorized derived-view area from recovery content. A16. |
| SR-094 | F-013 | P | Read-only source capability matches; remove the obsolete condition that an external cache location must first be configured. A03. |
| SR-123 | F-005 | P | Versioned meaning is related, but the candidate does not explicitly promise preservation of every supported older version's defaults. Retain that compatibility clause and declare the supported versions/forms. A10. |
| SR-130 | F-002, F-013 | M | Unprivileged container with read-only source and bounded writable locations matches; preserve no-added-capabilities/offline acceptance for the declared configuration. |
| SR-131 | F-008 | M | Kit redistribution permission and accompanying notices match. Native distribution extends, rather than discharges, these obligations. A19. |
| SR-132 | F-004, F-007 | P | Obtain-or-explain prerequisite handling matches; a runtime hashing-package fetch is not required when native packaging supplies the component. Keep noninteractive and pre-mutation behavior. |
| SR-134 | F-005 | M | Shipped example accepted by documentation and launch validation matches; keep actual first-backup acceptance. |
| SR-135 | F-005 | P | Explicit configuration version matches. Every-form versioning and integral-decimal acceptance are additional compatibility clauses, not inferred from a Rust integer type. A10. |
| SR-136 | F-010 | P | Continuing another host's store without duplicate content/history drift matches; extend to macOS and define allowed host-specific metadata differences. A15. |
| SR-138 | — | L/D | Rationale prevents backup recursion and source modification through overlapping locations. Retain an explicit derived configuration guard; generic read-only source text does not fully specify ancestor/equality/alias admission. |
| SR-140 | — | L/R | Refusal of read-only source without external cache exists solely because the former source-write default required it. Proposed retirement follows read-only SN-037/B-24 change, not failure to implement. A03. |
| SR-142 | F-003 | M | Omitted container action selects backup, not maintenance. |
| SR-143 | F-008 | M | Container redistribution permissions/notices match; package audit remains required. A19. |

## 2. Capture source content and choose storage

| Legacy SR | Candidate match | Class | Semantic alignment and proposed disposition |
|---|---|---|---|
| SR-001 | F-011, F-082 | P | Complete capture-or-named-failure matches. Legacy exclusions depend on active source cache and specific link policies; reconcile those separately rather than silently widening exclusions. A03/A09. |
| SR-003 | F-022 | M | One stored payload for identical content across names/runs/states matches. Legacy already says one backup; do not infer cross-store global deduplication. |
| SR-011 | F-019 | P | Deterministic reread policy matches; elapsed-period acceptance conflicts with calendar scheduling. Preserve interrupted-reread and healing-read exceptions while deciding schedule semantics. A23. |
| SR-035 | — | L/R | Rationale protects capture against a torn external change-detection cache. That artifact is absent from the revised frame; retire this specific rebuild/report promise. Do not relabel damaged authoritative latest-state data as a disposable cache. A03. |
| SR-036 | F-014, F-015 | P | Empty/missing-source protection and first-empty acceptance match. Remove ordinary allow-empty override; reconcile exit class and startup no-write versus recoverable mid-run progress. Explicit retirement is a separate decision. A06. |
| SR-053 | F-037 | P | Recapture externally lost content even with unchanged metadata matches. Legacy rationale excludes all corruption repair during backup and requires a history snapshot when healing changes records; reconcile with proven-damage handling and state-change semantics. A08/A22. |
| SR-055 | F-021 | P | Loud invalid-name handling/no silent loss matches. Windows/Linux invalid-character list, capture-stage refusal and retention of prior rows are more specific; include macOS/collision scope without silently permitting mangling. A15. |
| SR-067 | F-017 | P | Within-run retries match. Three attempts and operation-wide versus per-location timing policy remain explicit decisions; current per-file delays do not prove the drafted aggregate bound. A12. |
| SR-074 | F-012 | P | Declared exclusions and honest capture scope match. Source-root cache identity and follow/record link rules are legacy-specific; retain nested-name/root-only distinctions and resolve the link scope. A03/A09. |
| SR-081 | F-023 | P | Measured-savings/fallback policy matches. Existing 10% and 256 KiB thresholds, exempt modes and visible fallback require explicit retention or amendment; exact inclusive boundary differs from code. A14. |
| SR-088 | F-011 | M | New/size-or-time-changed files become recoverable at current content. |
| SR-089 | F-011, F-075, F-082 | M | Unreadable file/folder is named with cause, not counted captured or removed, and makes the run incomplete while readable files continue. |
| SR-090 | F-017 | P | Bounded aggregate retry waiting matches in intent. Fresh Q-04 does not supersede the existing 60-second per-location proposal; choose an achievable approved bound rather than substituting per-file counts. A12. |
| SR-091 | F-018 | M | Persistently unreadable files/folders retain previous recoverable content in latest state, including shared bytes. |
| SR-093 | F-013 | P | Source noninterference matches; remove source-cache/root-time exception. Keep host-managed access-time exclusion and tool-caused-change observation. A03. |
| SR-095 | F-072 | P | Multiple independent locations in one configured run are supported; candidate emphasizes failure independence. Explicit no-warning-for-count acceptance remains unresolved against container-only limits. A24. |
| SR-096 | F-023 | M | Compression off governs newly stored bytes; no compression probe/tool dependency in that case remains a useful acceptance detail. |
| SR-105 | F-019 | M | A due reread that finds concealed content change captures new bytes while earlier states retain old bytes. |
| SR-108 | F-037 | M | A new identical source file cannot share nonexistent stored content; actual recapture must make it recoverable. |
| SR-137 | — | L/N | Rationale says outside-link content may be the owner's only protected copy. Revised SN-001 no longer mandates following it and fresh Q-02 leaves scope open. Explicitly retain/defer/withdraw outside-folder and file-link capture; do not silently classify it as implemented or accidental. A09. |
| SR-139 | — | L/R | Plain source-root cache default was justified by travel/readability and a former owner exception. The amended source-read-only need/frame removes that premise; propose retirement with history preserved. A03. |
| SR-148 | — | L/R | Configured external-cache location is a removed artifact-specific capability. Retire its read/write contract; preserve read-only source outcome through SR-094's amendment. A03. |
| SR-149 | — | L/R | Cache-location overlap prohibition was justified by the now-retired configured cache. Retire this setting-specific guard, while keeping source/store/view overlap guards elsewhere. A03. |
| SR-150 | — | L/D | Cycle avoidance and recording in-tree links have explicit performance/fidelity rationale. Fresh recovery-of-links does not specify traversal termination or capture recording. Retain a derived finite-walk rule and an explicit link-recording scope decision. A09. |
| SR-151 | — | L/D | Avoiding traversal into product locations prevents recursive backup growth; retain that derived boundary. Recreating the original external link and cache-location references require separate scope reconciliation. A09. |

## 3. Publish history, exclude writers and recover interruption

| Legacy SR | Candidate match | Class | Semantic alignment and proposed disposition |
|---|---|---|---|
| SR-005 | F-025, F-027 | M | Previous changed state, duplicate/time-only changes and distinct same-second identity match. Fresh clock-rollback/timezone cases expand the identity challenge; existing same-second promise stays live. A21. |
| SR-017 | F-030 | P | Safe continuation or explained refusal matches. Witness failures, proof-of-death admission and unfinished-removal refusal are legacy mechanisms/policies requiring replacement under OS ownership and commit-aware cleanup. A04/A05. |
| SR-024 | F-026 | P | No-op latest-record stability matches. Legacy exempts missing-content healing; fresh broad no-source-change wording must preserve necessary healing instead of forbidding correction of damaged state. |
| SR-038 | — | L/R | Producer completeness evidence follows the former detect-substitution SN-025; the rationale correctly explains that content matching cannot detect a shortened record. Retire this protocol only with the proposed assurance change; stronger completeness protection remains a separate owner decision. A04. |
| SR-041 | F-028, F-075 | P | Recoverable superseded bytes and named move problems match. Mandatory part-failed outcome and whole-run rollback on unplaceable content are stronger legacy clauses; explicit warning/outcome policy needed. A13. |
| SR-059 | F-028 | M | Every mutation preserves previously recoverable content of retained states, including frozen rows and shared data. This safety rule remains across all new native operations. |
| SR-075 | F-030, F-032 | P | Automatic safe restart matches. Thirty-minute stale-liveness proof, cross-host time assumptions and delayed restart are retired-design candidates; use supported interoperable exclusion, not age takeover. A05. |
| SR-082 | F-029, F-030 | P | Interruption recoverability/restart matches. Atomic whole-run before/after tree, witness reconstitution and exit-3 alternative conflict with recoverable checkpoints; distinguish process kill from physical persistence. A04/A08. |
| SR-084 | F-050 | M | New writes must not strand a carried kit for a supported combination. Declare the compatibility window; do not assume current-kit replacement is necessary. A10. |
| SR-085 | F-031 | P | Competing mutations refused across their full extent matches. Naming the exact holder is omitted by amended SN-039; retain as an explicit diagnostic scope decision rather than accidental loss. |
| SR-086 | — | L/D | Fail-closed admission when exclusivity cannot be established is a valid filesystem-derived obligation, absent from the fresh competitor-only rule. Retain it; reconcile access-denied versus busy outcomes and remove separate stale-owner proof. A05. |
| SR-100 | F-026 | P | No saved state on an unchanged run matches. Preserve the explicit healing exception consistently with SR-024/053 rather than deriving a blanket no-mutation rule. |
| SR-101 | F-047 | P | Interrupted removal preserves survivors and can be retried. Legacy guarantees same-request complete even after commit; fresh allows safe actionable refusal. Decide post-commit/idempotent outcomes, and bound power-loss claims. |
| SR-106 | F-033 | P | Concurrent reads need not acquire writer ownership. Guaranteed normal result against a complete immutable view is stronger than amended valid-result-or-interference behavior. |
| SR-107 | F-032 | P | OS release after holder death matches. Legacy stale-death prerequisites and blanket unfinished-removal rejection are not part of lock release; reconcile residue separately. A05. |
| SR-110 | — | L/D | Rationale correctly identifies repair/refresh writes inside saved states as an interruption hazard. Fresh backup/prune interruption candidates omit this operation-specific obligation. Retain explicit crash-safe repair/refresh and retry requirements, removing witness/exit-3 assumptions. A04/A08. |
| SR-111 | F-024 | M | Existing stored form stays unchanged; changed compression policy governs only new content. |
| SR-114 | F-048, F-050 | P | Safe supported continuation matches; unconditional previous-release support conflicts with the proposed declared-format window. Record the actual supported formats and old-kit recovery route. A10. |
| SR-115 | F-050 | P | Current kit recovery of supported earlier states matches only if the declared matrix includes that combination. Fresh wording must not silently remove the legacy current-kit promise. A10. |
| SR-116 | — | L/N | Rationale protects old states while distinguishing absent-by-age metadata from damage. Fresh compatibility declaration alone does not carry skipped-check disclosure/positive-age evidence. Decide required version evidence and metadata assurance; witness-specific clauses are retirement candidates. A04/A11. |
| SR-117 | F-049 | P | Explicit refresh preserving recoverability matches. Legacy all-state refresh, unchanged state records and no automatic historical refresh are additional scope/authority clauses to retain or decide. |
| SR-144 | — | L/R | Stale-claim reclamation/fencing exists for a former takeover protocol outside shared-lock assumptions. Propose retirement of that protocol, not weakening exclusive ownership. Lost-lock-on-supported-host behavior remains a derived safety question for SR-086/085. A05. |

## 4. Check, repair and retain

| Legacy SR | Candidate match | Class | Semantic alignment and proposed disposition |
|---|---|---|---|
| SR-045 | F-045 | M | Remove a named state, preserve every remaining state and reclaim only content exclusive to removed history. Caller supplies retention policy. |
| SR-046 | F-046 | P | Unsafe or unprovably safe removal refuses before mutation. Specific witness, unreferenced-content, capacity and tool rails/outcomes need operation-specific reconciliation; retain last-copy safety. A04/A07. |
| SR-047 | F-043 | P | Reclaimed versus relocated accounting matches. Amended SN-046 measures content bytes, not observed filesystem allocation/free-space drop; retain stable-store precondition. |
| SR-049 | F-038 | P | Whole-store missing/altered/form findings match. Preserve missing-own-place versus missing-pool distinction; explicitly label check depth so shallow checks do not claim deep corruption assurance. A22. |
| SR-102 | F-042 | M | Prune containment/refusal for absolute/traversal/wildcard/link escapes matches its security-derived purpose. Fresh candidate extends the same authority boundary to repair. |
| SR-103 | F-039, F-044 | M | Integrity checks and reports leave store bytes and modification times unchanged; access-time effects excluded. |
| SR-104 | F-074 | M | Structured findings match human facts; empty clean-check findings remain explicit. |
| SR-109 | F-040, F-041 | P | Certain repair versus reported uncertainty matches. Legacy own-place rehoming, verified alternate-copy supply and untouched other folders are stronger specified repair classes, not proved by generic repair wording. Rehoming rationale needs reassessment against shared-pool design, while the desired repair remains visible. A22. |

## 5. Recover the selected state

| Legacy SR | Candidate match | Class | Semantic alignment and proposed disposition |
|---|---|---|---|
| SR-007 | F-055 | P | Carried clean-host recovery matches. Legacy requires a kit at every state; candidate promises carried complete-store capability without per-state placement. Preserve autonomous per-state launchability or place that layout decision at its justified tier. |
| SR-008 | F-055, F-056 | M | Offline recovery with documented local tools matches. Native engine/toolchain is not a recovery prerequisite; tool installation before recovery is distinct from downloading during recovery. |
| SR-009 | F-058 | M | Direct/aliased target inside store refuses before writes; sibling-prefix paths are valid. |
| SR-010 | F-057 | M | Selected historical state alone is authoritative; default selection yields latest. |
| SR-021 | F-020 | P | Exact supported names match; byte-identical spelling on every target is conditioned by normalization/representation support. No silent transliteration or merging. A15. |
| SR-023 | F-034, F-036 | P | Known capacity refusal/reporting matches. Exact expanded-demand/headroom calculation, zero target writes and guarantee of no later exhaustion are stronger or impossible without reservations. Preserve preflight enhancement as a decision and safe exhaustion handling separately. A07. |
| SR-029 | F-064 | P | Unaffected files still recover matches. Whole-restore admission priority, especially space-plus-missing-content, is stronger and awaits SR-145 reconciliation. |
| SR-031 | F-056 | M | Three-platform recovery independent of engine runtime matches; named script routes and closed tool matrix make independence more explicit. |
| SR-039 | F-060 | P | Detected unsafe state-record interpretation cannot yield false success. Witness presence/mismatch refusal, zero target/log writes and exit 3 conflict with revised salvage/assurance scope. Preserve the limits explicitly. A04. |
| SR-040 | F-070, F-082 | P | Consistent truthful result classes match; fixed shared 0/1/2/3/4 taxonomy, precedence and metadata/path assignments need per-operation/version reconciliation. Prune's legacy 3 cannot be erased with current restore 3. A04/A11. |
| SR-056 | F-062, F-082 | M | Every reported restored file is content-verified; failed verification must not leave a file presented as successfully restored. |
| SR-065 | F-066 | M | Empty and nested empty directories return. |
| SR-066 | F-065 | P | Per-file own timestamps match. Explicit part-failed result for malformed current timestamps is stronger than candidate's declared-capability policy; retain as metadata decision. A11. |
| SR-068 | F-024, F-062 | P | Mixed forms remain recoverable and bytes validated. Legacy requires successful recovery despite every form flag being wrong, including raw source archives; candidates alone permit failure and do not capture that stronger recovery capability. Retain its acceptance vectors. |
| SR-071 | F-056, F-070 | M | Intact store succeeds across supported GNU/BSD/Windows tool environments without false damage. Unsupported folder attributes must follow the declared warning policy. |
| SR-072 | F-069 | M | Double-click target guidance and persistent visible outcome on Windows/macOS match. |
| SR-073 | F-069, F-071 | P | Interactive versus noninteractive prompt behavior matches. Console-only fallback and cancellation never choosing a default target are important uncarried details to retain. |
| SR-092 | F-021 | P | No silent case/normalization collision loss matches. Legacy writes neither entry and classifies both as incomplete; candidate leaves exact disposition open. Retain that proposal for owner decision. A15. |
| SR-118 | F-004 | P | Missing/unsupported tool is named rather than misdiagnosed as content damage. Absolute zero target/log writes is stronger than candidate's backup-protection wording and amended before-affected-work need. A07. |
| SR-119 | F-063 | P | Damage cannot yield false success. Legacy requires using an intact alternate wherever present; fresh candidate permits reporting failure despite an intact alternate. Rationale says otherwise-recoverable data would be lost: retain stronger healing request for explicit decision, not automatic weakening. |
| SR-120 | F-064, F-082 | M | Every unrecovered path/cause and exact total accompany incomplete outcome; admission exceptions remain linked to SR-145. |
| SR-121 | F-059 | P | Entry/path/link confinement and safe-entry continuation match. Witness admission, exit 3 and recreation of external recorded links require separate reconciliation. A04/A09. |
| SR-122 | F-067 | P | Apply supported folder attributes and report unsupported ones matches; legacy explicitly preserves complete outcome for unsupported attributes. Do not replace this with unexplained failure. A11. |
| SR-141 | — | L/D | Rationale treats unresolved targets and parent components as unprovable confinement. Fresh escape checks do not specify admission when resolution fails. Retain fail-closed uncertainty; decide whether lexical parent-component prohibition is necessary design restriction. |
| SR-145 | — | L/N | Rationale resolves combined whole-restore versus per-file faults through zero-write admission. Fresh per-case candidates do not cover their ordering/combinations. Decide strict admission scope explicitly, including tools/capacity; containment safety remains non-negotiable. A07. |
| SR-146 | — | L/N | Rationale separates old-format absence from lost current metadata and refuses false whole-tree completeness. Fresh empty-folder/attribute capabilities omit this detection/outcome. Retain requested assurance as a metadata policy decision; absence alone may not prove loss in the present format. A11. |
| SR-152 | F-068 | P | Internal links retargeted into recovered tree match. External links, late-creation ordering and success despite unsupported/unauthorized link creation remain uncarried clauses; decide separately and retain containment. A09. |

## 6. Supervise operations, account for resources and notify

| Legacy SR | Candidate match | Class | Semantic alignment and proposed disposition |
|---|---|---|---|
| SR-014 | F-072 | P | Other sets continue and aggregate non-success matches. Fixed part-failed aggregation conflicts with existing worst-class precedence; preserve interface compatibility pending decision. A24. |
| SR-015 | F-078 | M | Configured/enabled notification reaches relay; disabled notification sends none. End-user receipt is an external relay assumption. |
| SR-016 | F-071 | M | No prompt for any noninteractive operation, including prerequisite handling. |
| SR-043 | F-073, F-082 | P | Distinct operational results match. Universal exit-3, old cache/empty-source/preflight classifications, multi-set aggregation and legacy opt-in need versioned interface reconciliation. A04/A06/A07/A24. |
| SR-052 | F-034, F-036 | P | Known insufficiency and measured-volume reporting match. Aggregate exact upfront demand, separate-volume history copies and no-space-failure guarantee conflict with bounded writes; safe exhaustion must be explicit. A07. |
| SR-062 | F-051 | M | Optional fresh latest-state listing covers duplicates, name search and stored-content access. Define compressed-entry opening semantics without assuming transparent extraction. |
| SR-064 | F-080 | P | Whole-check/full-restore time bound matches. Existing 2 TiB/million-file/365-state/reference-SSD/eight-hour envelope remains a concrete unverified proposal, not erased by Q-21. A18. |
| SR-097 | F-053 | P | Space-ranked files match. Full stored-copy size charged to each duplicate plus shared marker is an existing explicit attribution policy to retain or decide. A20. |
| SR-098 | F-054 | P | Media encoding-density view matches. Positive playing-time scope, MiB/s and three-decimal precision are existing policy detail, not supplied by the fresh placeholder. A20. |
| SR-099 | F-054 | M | Missing/failed optional measurement leaves backup unchanged and visibly unavailable; preserve distinction from zero. A20. |
| SR-112 | F-080 | P | Peak memory budget matches. Retain whole-process-tree accounting and existing 4 GiB target/envelope until explicitly amended; measuring only the Rust process would weaken it. A18. |
| SR-113 | F-080, F-081 | P | Few-change deadline and sublinear history scaling match. Keep 1 GiB-change/no-reread/30-minute and 182-to-364-state proposals, with measurable workload/cache conditions. A18. |
| SR-124 | F-075 | M | Semantic file change/failure ledger and correct summary counts match; current work metrics alone are not this capability. A13. |
| SR-125 | F-076 | P | Bounded progress matches. Existing 120-second active-time threshold across reading/storing/finalizing stays visible; callbacks between files alone do not satisfy it. A13. |
| SR-126 | F-077 | M | Every refusal names condition and actionable remedy. |
| SR-127 | F-078 | M | Notification failure warns without changing the backup result. |
| SR-128 | F-079 | M | Tool-handled credentials never appear plaintext in configuration/generated backup records/logs/errors; source files containing those bytes remain ordinary backed-up data. |
| SR-129 | F-079 | P | Plaintext credential configuration refusal matches. Blanket JSON credential ban and native-Windows protected representation are carrier-specific policies requiring portable credential design/support decisions. A19. |
| SR-133 | F-054 | P | Optional media absence visibly degrades without failing good capture. Legacy rule covers any optional extra; fresh candidate is media-specific, so retain a package-wide optional-dependency home. |
| SR-147 | F-054 | M | Disabled measurement is visibly not taken, invokes no measurement and changes no backup content/outcome. A20. |

## Legacy-only decisions and partial-match safeguards

The L rows above are not free deletions. D classifications preserve explicit guard or interruption obligations; N classifications preserve a stakeholder scope/assurance question; R classifications propose removal of superseded premises. The source-cache group (SR-035/139/140/148/149), producer witness SR-038 and stale-reclaim SR-144 have rationale that was coherent under the previous frame. Their proposed retirement is traceable to changed scope, not to lack of code.

Specific partial or fresh gaps require attention before using candidates as replacement SRs:

1. **Publication and availability:** preserve recoverable checkpoints without promising a transactional whole-run tree. Add repair/refresh interruption and fail-closed unknown-lock admission. Simultaneous readers must not silently misreport an interference as corruption or complete recovery.
2. **Capacity:** explicit exhaustion safety is newly stated, while exact capacity guarantees are withdrawn in the proposed needs. An improved restore preflight and strict whole-restore admission remain owner decisions; preflight cannot guarantee future capacity without stronger external control.
3. **Recovery assurance:** distinguish structural interpretation, verified file bytes, completeness and authenticity. Retiring witnesses does not make valid truncation detectable. Keep alternate-copy healing, mixed-form recovery and metadata completeness requests visible rather than accepting the fresh set's weaker alternatives by default.
4. **Scope and containment:** source/store/view overlap, unknown target resolution, finite traversal and link recording have rationale beyond generic happy-path capture. Current exclusions and portability refusals are policy input, not automatically abolished by fresh open questions.
5. **Compatibility:** independently declare writable store, readable kit and configuration matrices. Current support need not include every previous release, but unsupported stores must keep their original recovery route. Numeric outcome compatibility, including legacy prune behavior, is operation-specific.
6. **Unmet capabilities:** link fidelity, complete semantic reporting/progress, aggregate retry bounds, space/media view, repair classes, strict metadata/admission and quantitative budgets remain requested work or explicit scope decisions. No implementation absence adjudicates them away.

## Genuinely new or expanded native/platform obligations

Native engine/maintenance distribution across the declared OS/CPU matrix is new under SN-055; no existing container or restore row supplies it. Native third-party notices extend existing kit/container obligations. macOS writer continuation extends SR-033/136, while independent script recovery is an existing purpose now made explicit against Rust-engine/toolchain dependence. A closed support declaration, source-name normalization behavior, secure credential facilities, filesystem durability/exclusion evidence and packaging/tool floors must be carried through their affected chains. Their mechanisms belong below the capability tier; a Rust implementation alone proves none of them.

No general hooks, lifecycle callbacks or plugin-execution capability is introduced. Disabled hooks are the task's scope constraint, not an invented stakeholder requirement.

## Inverse candidate index

The index below is generated from the manually reviewed match column above. A listed SR may be a **partial** match: consult its row rather than treating the inverse as full equivalence. Fresh-only does not automatically mean a new stakeholder need; the explanation distinguishes new scope, an explicit cross-cutting home and stronger safety feedback.

| Candidate | Bucket | Legacy rows or proposed disposition |
|---|---|---|
| F-001 | Fresh-only | New native backup/maintenance outcome under SN-055; retain as new scope, not container equivalence. |
| F-002 | Matched/partial | SR-034, SR-048, SR-130 |
| F-003 | Matched/partial | SR-142 |
| F-004 | Matched/partial | SR-019, SR-132, SR-118 |
| F-005 | Matched/partial | SR-042, SR-123, SR-134, SR-135 |
| F-006 | Matched/partial | SR-018 |
| F-007 | Matched/partial | SR-027, SR-132 |
| F-008 | Matched/partial | SR-131, SR-143 |
| F-009 | Fresh-only | Explicit operation/store/kit support declaration; existing supported-version promises lack a complete published matrix. |
| F-010 | Matched/partial | SR-033, SR-136 |
| F-011 | Matched/partial | SR-001, SR-088, SR-089 |
| F-012 | Matched/partial | SR-074 |
| F-013 | Matched/partial | SR-094, SR-130, SR-093 |
| F-014 | Matched/partial | SR-036 |
| F-015 | Matched/partial | SR-036 |
| F-016 | Fresh-only | Explicit source-retirement intent from amended SN-038; decide whether configuration removal suffices, without inventing a destructive command. |
| F-017 | Matched/partial | SR-067, SR-090 |
| F-018 | Matched/partial | SR-091 |
| F-019 | Matched/partial | SR-011, SR-105 |
| F-020 | Matched/partial | SR-021 |
| F-021 | Matched/partial | SR-055, SR-092 |
| F-022 | Matched/partial | SR-003 |
| F-023 | Matched/partial | SR-081, SR-096 |
| F-024 | Matched/partial | SR-111, SR-068 |
| F-025 | Matched/partial | SR-005 |
| F-026 | Matched/partial | SR-024, SR-100 |
| F-027 | Matched/partial | SR-005 |
| F-028 | Matched/partial | SR-041, SR-059 |
| F-029 | Matched/partial | SR-082 |
| F-030 | Matched/partial | SR-017, SR-075, SR-082 |
| F-031 | Matched/partial | SR-085 |
| F-032 | Matched/partial | SR-075, SR-107 |
| F-033 | Matched/partial | SR-106 |
| F-034 | Matched/partial | SR-023, SR-052 |
| F-035 | Fresh-only | Explicit mid-write exhaustion safety under amended SN-019; legacy preflight guarantees omit this failure response. |
| F-036 | Matched/partial | SR-023, SR-052 |
| F-037 | Matched/partial | SR-053, SR-108 |
| F-038 | Matched/partial | SR-049 |
| F-039 | Matched/partial | SR-103 |
| F-040 | Matched/partial | SR-109 |
| F-041 | Matched/partial | SR-109 |
| F-042 | Matched/partial | SR-102 |
| F-043 | Matched/partial | SR-047 |
| F-044 | Matched/partial | SR-103 |
| F-045 | Matched/partial | SR-045 |
| F-046 | Matched/partial | SR-046 |
| F-047 | Matched/partial | SR-101 |
| F-048 | Matched/partial | SR-061, SR-114 |
| F-049 | Matched/partial | SR-117 |
| F-050 | Matched/partial | SR-084, SR-114, SR-115 |
| F-051 | Matched/partial | SR-062 |
| F-052 | Fresh-only | Boundary-derived independence of recoverability from the optional view; existing browse behavior does not explicitly state it. |
| F-053 | Matched/partial | SR-097 |
| F-054 | Matched/partial | SR-098, SR-099, SR-133, SR-147 |
| F-055 | Matched/partial | SR-007, SR-008 |
| F-056 | Matched/partial | SR-008, SR-031, SR-071 |
| F-057 | Matched/partial | SR-010 |
| F-058 | Matched/partial | SR-009 |
| F-059 | Matched/partial | SR-121 |
| F-060 | Matched/partial | SR-039 |
| F-061 | Fresh-only | Honest record-assurance limits under amended SN-025; old witness assurances are not an equivalent promise. |
| F-062 | Matched/partial | SR-056, SR-068 |
| F-063 | Matched/partial | SR-119 |
| F-064 | Matched/partial | SR-029, SR-120 |
| F-065 | Matched/partial | SR-066 |
| F-066 | Matched/partial | SR-065 |
| F-067 | Matched/partial | SR-122 |
| F-068 | Matched/partial | SR-152 |
| F-069 | Matched/partial | SR-072, SR-073 |
| F-070 | Matched/partial | SR-040, SR-071 |
| F-071 | Matched/partial | SR-073, SR-016 |
| F-072 | Matched/partial | SR-095, SR-014 |
| F-073 | Matched/partial | SR-043 |
| F-074 | Matched/partial | SR-048, SR-104 |
| F-075 | Matched/partial | SR-089, SR-041, SR-124 |
| F-076 | Matched/partial | SR-125 |
| F-077 | Matched/partial | SR-126 |
| F-078 | Matched/partial | SR-015, SR-127 |
| F-079 | Matched/partial | SR-128, SR-129 |
| F-080 | Matched/partial | SR-064, SR-112, SR-113 |
| F-081 | Matched/partial | SR-113 |
| F-082 | Matched/partial | SR-001, SR-089, SR-040, SR-056, SR-120, SR-043 |

The inverse is an inventory check, not an automated semantic verdict. All 123 SR IDs and all 82 candidate IDs occur once in their respective primary indexes; references in notes do not count as extra rows. Structural enumeration was checked against the actual registries and candidate table; no execution acceptance was run.
