# System requirements review

Status: **[accepted by the owner](sr-approval.md); design decomposition next**.

The review discussions below preserve the authoring/review context. The live
registry now has 121 Approved SRs. The approval record defines its scope and
the next breakdown; earlier Drafted/proposal language is historical, not a
claim that implementation or verification has been approved.

The owner accepted the [22 assumptions and two surrogates](assumptions-approval.md).
The [live system registry](../../requirements/system-requirements.toml) now holds
121 Approved SRs: 115 retained/reconciled legacy IDs and six additions. All 49
approved needs have candidate SR coverage. Coverage means an obligation has a
draft home, not that its policy, implementation or verification has passed.

The approved needs, active external frame and assumptions are unchanged.
Only the inactive Drafted B-24 source-write placeholder was removed from the
live frame after its obsolete SR references were resolved. The standing
approval snapshot and ledger were not changed by SR authoring. Hooks remain
disabled. LLRs, tests, interface contracts and code annotations still need
reattachment after this tier is accepted; no runtime behavior changed here.

## Start the review here

| Topic | Draft outcome | Main SRs |
|---|---|---|
| Recovery prerequisites | Guidance names the shell and local tools; a route that can start refuses detectable missing prerequisites before output. Recovery works offline once provisioned. | 007, 008, 019, 031, 118, 132 |
| Source protection | Read-only sources suffice; no source-side state or source-write exception. | 093, 094, 138 |
| Interruption | Preserve earlier recoverable states and completed per-file publication. Latest can contain recorded progress from an interrupted run; no whole-tree transaction or completeness witness. | 017, 041, 075, 082, 101, 110, 158 |
| Retention | Removing a date may invalidate that date and every older date. Protect latest and retained later states; no duty to rehome content for older history. | 045–047, 059, 101, 155 |
| Verification | Inspect every remaining record, including out-of-window older folders; distinguish their damage from later states. Check every reported restored file; disclose collision and record-substitution limits. | 039, 049, 056, 119, 155 |
| Coordination | Validate unique resolved roots within one configuration; refuse competing mutations in that scope. Death releases ownership; suspension is not age-based permission to take over. | 085, 086, 107, 138, 154 |
| Compatibility | Explicitly designate continuation/migration/current-kit support; a new-store transition is valid. No older versions currently designated. | 061, 084, 114–117, 123, 156 |
| Native delivery | Native engine and maintenance on Windows/Linux/macOS; independent carried PowerShell/bash recovery. All distribution routes carry required notices. | 033, 131, 136, 143, 153, 156, 157 |

DA-10 now has an explicit diagnostic obligation in **SR-118**, with engine-side
prerequisite handling in SR-019/132. It does not presume that an absent shell
can execute a warning about itself.

## Additional high-risk cross-review

The owner-requested [Gemini 4 Argon review](gemini-high-risk-review.md), run
through OpenCode Go on low, included permission to critique approved needs and
boundaries. After a clarification pass, **one high-risk policy decision remains**:
external links can multiply logical capture paths and restored bytes, while the
scale envelope does not yet explicitly distinguish logical from physical size.
Decide the SR-137 nested/repeated-link policy and define the SR-064/112/113
benchmark counting basis. No approved record or Drafted SR was changed by this
review. The report records the candidate dispositions and input provenance.

The subsequent [folder-link preference](folder-link-policy.md) narrows SR-150/151/152
to portable relative links whose destinations remain within the captured root.
This is feasible but requires new link records and support in both recovery
scripts; genuinely external-link fallback and scale counting remain open.

## Proposed policies needing particular attention

These are proposals in Drafted SRs, not conclusions extracted from current code
and not previous owner approval. The numerical proposals remain visible from
the legacy draft so they are not silently lost during rebaseline.

| Choice | Current proposal | Why review it |
|---|---|---|
| Retry budget — SR-067/090 | At most three attempts per file, within **60 seconds aggregate extra waiting per configured location**. | This differs from the current engine's per-file delayed retry schedule. The attempt spacing/fairness belongs in design, but the aggregate budget needs agreement. |
| Compression — SR-081 | Measure above **256 KiB** and compress at **at least 10% measured saving**; retain explicit type-based fallback/exemption modes. | Inclusive threshold, sampling basis and fallback must be deliberate; matching current code is not sufficient reason to choose them. |
| Progress — SR-125 | No gap longer than **120 seconds of active execution time**, including long reads and finalization. | Suspension is excluded by DA-22, but blocking calls must not silently evade the active-time budget. |
| Scale — SR-064/112/113 | **2 TiB, one million files, 365 dated saved states plus latest**; four-core host, **2 GB available RAM and 100 MiB/s local SSD**, as corrected by the owner; combined concurrent resident memory must fit that available-memory budget. Proposed time targets remain **8 hours** check/full restore and **30 minutes** routine backup with at most 1 GiB changed. | The saved-state count is a benchmark envelope, not a retention limit or 365 separate full copies. Time targets remain unvalidated on the revised host. Corpus composition, shared-content history size, warm/cold runs and repeatability must be fixed in the benchmark design before claiming evidence. |
| External links — SR-137/150–152 | Preserve supported in-root folder links as relative links. Outside-folder expansion in SR-137 remains a proposal; system-location links are not traversed and links that cannot be preserved are reported. | Outside-tree traversal expands the selected capture domain. The approved needs require visible, safe behavior but do not choose this particular external-link policy. Retained for an explicit owner choice. |
| Names and exclusions — SR-055/074 | Declare a supported name domain; report invalid/colliding names. Limit system exclusions to actual volume-owned metadata/recycle entries at volume roots, never familiar nested names. | Exact name/tool/filesystem support belongs in the matrix. Case and normalization collisions must not be hidden by an assumption. |
| Metadata outcomes — SR-066/122/146/152 | Malformed required current metadata is incomplete; unsupported target attributes/links are reported under a documented limitation policy. | The proposal treats unsupported attributes as complete-with-warning. The revised proposal explicitly applies complete-with-warning to unsupported links too; this needs owner agreement. Unsupported is different from lost current metadata. |
| Capacity — SR-023/052/158 | Refuse known shortfalls against a disclosed bounded-work estimate; report unmeasurable capacity and handle later failures safely. | Estimates do not reserve space. The missing-measurement admission policy and allocation/temporary allowances must be explicit in design; no promise that passing an estimate prevents disk-full. |
| Configuration representation — SR-042/123/135 | Publish declared forms/versions and their exact meanings; no automatic old-version support. | The older draft specifically named JSON and native Windows forms and accepted integral decimal version values. Those are now explicit interface/design decisions, not silently guaranteed legacy compatibility. |
| Concurrent readers — SR-156 | Publish supported read-during-mutation limits; no general reader-isolation guarantee. | Legacy SR-106 promised coherent checks/restores during every mutation without an approved supporting need or evidence. Its retirement does not authorize a silently incorrect recovery result. |

“365 saved states” means 365 dated records of earlier captured trees, in addition
to latest. For example, one changing backup per day could produce roughly a
year of history; unchanged runs add no saved state. These records share stored
file content, so this does not require 365 copies of the whole library or impose
a maximum retention period.

RSS means **resident set size**: process memory currently resident in physical
RAM. The earlier “4 GiB total concurrent RSS” proposal limited the combined
memory of FileBackup and all helper processes running at the same instant, not
4 GiB per process. The owner reduced the reference host to 2 GB available RAM
and 100 MiB/s SSD throughput; SR-112 now requires the combined memory to fit
that available budget. GB here means 1,000,000,000 bytes; GiB means
1,073,741,824 bytes. Measurement must state how shared pages are counted.
This correction does not approve the remaining scale targets or the SR tier.
The DeepSeek reports preserve their original reviewed values as historical
evidence; this owner correction came afterward.

The default re-read schedule, exact platform/CPU/tool floors, content-identity
algorithm and protection checks, machine-readable result mapping/precedence,
credential mechanisms and repair classes need concrete interface/design
choices next. They must satisfy the SRs; “documented” is not permission to omit
required checks or designate away Windows, Linux or macOS. The SR draft is a
behavioral target, not a declaration that those builds already exist.

## Reconciliation and independent review

The author read all 123 legacy statements, rationales and acceptance criteria
before retirement, and used the earlier [82-candidate alignment](sr-alignment.md)
as a historical checklist. Accepted parent decisions take precedence over its
earlier proposals. Existing IDs remain where the obligation has continuity;
new IDs are SR-153 through SR-158 and retired IDs are never reused.

DeepSeek first received only approved upstream records and the nine hats, with
no legacy SRs or implementation. Its [fresh coverage report](deepseek-sr-fresh-review.md)
provided 35 lifecycle groups. A separate full-draft review is complete in
[the cross-review record](deepseek-sr-draft-review.md). Neither review approves
requirements. Provider/model was `opencode-go/deepseek-v4.1-flash` through the
working OpenCode subscription, with low reasoning effort, disabled tools,
fresh temporary directories and separate complete attachments below 50 KB.

The fresh review's main mapping is:

| Fresh checklist items | Draft homes |
|---|---|
| 1–8: delivery, tools, configuration, unattended work, credentials, notifications, container, compatibility | 015/016/018/019/027/034/042/048/061/084/114–118/123/127–135/142/143/153/156/157 |
| 9–15: scope, unreadable files, source protection, empty source, multi-set, rereads, names | 001/011/014/021/024/036/055/067/074/088–095/105/137/138/150/151 |
| 16–21: dedup, compression, capacity, interruption, repair from source, space/media reporting | 003/017/023/041/052/053/075/081/082/096–099/108/147/158 |
| 22–28: saved states, dependencies, retention advice, verification, repair, record assurance | 005/039/045–049/056/059/100–104/109–111/155 |
| 29: scoped coordination | 085/086/107/138/154 |
| 30–35: independent recovery, containment, metadata, partial results, interaction, scale | 007–010/029/031/033/040/062–066/068/071–073/092/112/113/119–122/124–126/141/145/146/152/156 |

One fresh-review error was rejected: item 7 says “no action defaults to
backup,” while approved SN-024 explicitly requires backup as the container's
default action. SR-142 retains that required default. The suggested choice of
sampled versus full verification cannot waive the requirement to check every
reported restored file or the whole-store discrepancy coverage. Algorithm and
verification implementation remain design work, with residual limits disclosed.

All nine hats were considered. The live `hat_refs` record concrete failure
obligations, not every applicable hat: publication/verification, path safety,
shared-content retention, version support, filesystem semantics, unattended
failures, host portability, scale budgets and redistribution each have named
homes. No hat's broad wording expands the owner's narrowed retention,
coordination or compatibility promise.

## Retired obligations

Each deletion has an immutable lookup record under `docs/log.d/retired/`.
They preserve the reason and successor rather than fabricating a Retired
registry status. The old text remains in git at `7b4dcc8`.

| ID | Reason and surviving obligation |
|---|---|
| [SR-035](../../log.d/retired/SR-035.md) | Separate change-detection cache recovery is a superseded design obligation. Approved B-20 uses the selected latest state; SR-024/011 cover unchanged-state and re-read behavior without a source cache. |
| [SR-038](../../log.d/retired/SR-038.md) | A completeness witness is not an approved outcome and cannot authenticate a well-formed substituted record. Structural validation remains SR-039 and disclosed assurance limits are SR-155. |
| [SR-106](../../log.d/retired/SR-106.md) | Guaranteed coherent reads during every concurrent mutation is an unsupported legacy-only policy. Approved SN-039 scopes writer coordination, not concurrent reader isolation. SR-156 requires declared read-during-mutation limits; a future isolation guarantee needs explicit design and evidence. |
| [SR-139](../../log.d/retired/SR-139.md) | Source-side state directly conflicts with approved SN-037 and B-01/B-20. Backup writes no FileBackup state into the source. |
| [SR-140](../../log.d/retired/SR-140.md) | Refusing a read-only source without an alternate cache is the consequence of a superseded source-cache design. Read-only access is sufficient under approved SN-037. |
| [SR-144](../../log.d/retired/SR-144.md) | Cross-host/configuration lease expiry and fencing exceed approved SN-039/DA-03. No age-based takeover is required; supported ownership persists through suspension and releases on holder death. |
| [SR-148](../../log.d/retired/SR-148.md) | Configurable separate source-cache placement is a superseded design prescription, not a stakeholder outcome. Source non-mutation and store-side operational state remain required. |
| [SR-149](../../log.d/retired/SR-149.md) | Separate cache placement exclusions belong to the retired cache design. Protected-source/store/view overlap checks remain SR-138 and SR-063. |

## Legacy row accounting

Every legacy row is accounted for below. “Reconciled” includes corrections to
scope, outcomes, premise attribution and acceptance, not a claim of code changes.
The detailed reason is in the thematic sections above or the retirement record.

| Legacy ID | Disposition | Current subject |
|---|---|---|
| SR-001 | Reconciled | Every file in a source tree is captured |
| SR-003 | Retained outcome; delivery links reviewed | Identical content is stored once |
| SR-005 | Reconciled | A changing run keeps the previous state as a dated saved state |
| SR-007 | Reconciled | Every state in a backup carries a restore kit |
| SR-008 | Reconciled | A restore needs only the documented tool floor and downloads nothing |
| SR-009 | Reconciled | A restore target inside the backup is refused |
| SR-010 | Reconciled | A restore reproduces exactly the chosen state |
| SR-011 | Reconciled | The re-read schedule decides deterministically when unchanged-looking files are re-read |
| SR-014 | Reconciled | One location's failure does not stop the others |
| SR-015 | Retained outcome; delivery links reviewed | Where notification is set up, each run's outcome is sent |
| SR-016 | Retained outcome; delivery links reviewed | An operation started without an interactive session never prompts |
| SR-017 | Reconciled | Unsafe interrupted work is preserved and its blocker reported |
| SR-018 | Reconciled | A wrong or missing configuration is refused before any backup is touched |
| SR-019 | Reconciled | A missing required component or unsupported runtime stops the run first |
| SR-021 | Reconciled | File names restore exactly |
| SR-023 | Reconciled | Restore reports a known capacity shortfall before target writes |
| SR-024 | Reconciled | An unchanged source reports no changes and leaves the latest state as it was |
| SR-027 | Reconciled | Shipped guidance takes a new user to a first backup |
| SR-029 | Reconciled | A partial restore still restores every other file |
| SR-031 | Reconciled | A restore behaves the same on Windows, Linux and macOS |
| SR-033 | Reconciled | Backups from Linux and Windows hosts restore through every restorer |
| SR-034 | Retained outcome; delivery links reviewed | Backups run inside a container with nothing installed on the host |
| SR-035 | Retired with record | A damaged change-detection state never costs a change or stored content |
| SR-036 | Reconciled | A source that suddenly looks empty is refused |
| SR-038 | Retired with record | Every record of a state carries evidence of its own completeness |
| SR-039 | Reconciled | Detectably invalid records or entries are rejected safely |
| SR-040 | Reconciled | Recovery routes agree on documented result classes |
| SR-041 | Reconciled | Earlier content a run cannot place in the saved state stays restorable, and the run fails |
| SR-042 | Reconciled | The configuration has a documented, versioned description matching the launch checks |
| SR-043 | Reconciled | Management actions report consistent documented outcomes |
| SR-045 | Reconciled | History removal preserves the later recovery window |
| SR-046 | Reconciled | Removal checks protect the later recovery window |
| SR-047 | Reconciled | Retention advice states estimates and cutoff limits |
| SR-048 | Reconciled | Removal and the saved-state report can be run through the container |
| SR-049 | Reconciled | A check reports every disagreement between the record and what is stored |
| SR-052 | Reconciled | Backup capacity admission uses a disclosed estimate |
| SR-053 | Reconciled | Content lost from the backup is stored again |
| SR-055 | Reconciled | Unsupported capture names and collisions are visible |
| SR-056 | Reconciled | Every reported restored file passes the required content checks |
| SR-059 | Reconciled | No operation loses or alters content a state depends on |
| SR-061 | Reconciled | A backup or state in a retired or unrecognised form is refused by name |
| SR-062 | Retained outcome; delivery links reviewed | Where turned on, a browsable listing of the latest state is produced |
| SR-063 | Reconciled | A listing location that overlaps a source or a backup, or holds other content, is refused |
| SR-064 | Retained outcome; delivery links reviewed | A check and a full restore fit their time budgets at scale |
| SR-065 | Retained outcome; delivery links reviewed | Empty folders are recreated |
| SR-066 | Reconciled | Each restored file gets its own modification time |
| SR-067 | Retained outcome; delivery links reviewed | A briefly locked file is retried within the run |
| SR-068 | Reconciled | A store holding both forms restores byte-exact |
| SR-071 | Reconciled | A restore reports no damage that is not there, whatever the host's tool flavour |
| SR-072 | Retained outcome; delivery links reviewed | A double-clicked restore asks for the target and keeps its outcome on screen |
| SR-073 | Reconciled | A restore with no target asks only where it can, or prints its usage |
| SR-074 | Reconciled | Capture exclusions are explicit and location-specific |
| SR-075 | Reconciled | A run after a dead interrupted run proceeds by itself when nothing would be lost |
| SR-081 | Retained outcome; delivery links reviewed | With compression on, a measured saving decides, and the file type decides where no measurement is taken |
| SR-082 | Reconciled | Interrupted capture preserves recoverable published progress |
| SR-084 | Reconciled | Designated compatibility paths preserve their promised recovery routes |
| SR-085 | Reconciled | Only one changing operation proceeds on a backup at a time |
| SR-086 | Reconciled | Ownership acquisition failure never permits mutation |
| SR-088 | Retained outcome; delivery links reviewed | New and changed files are picked up on later runs |
| SR-089 | Retained outcome; delivery links reviewed | A file or folder not captured is named and fails the run |
| SR-090 | Retained outcome; delivery links reviewed | Retrying unreadable files is bounded for each location |
| SR-091 | Retained outcome; delivery links reviewed | A persistently unreadable file keeps its earlier copy |
| SR-092 | Reconciled | Names that would collide on the restore target are reported, never merged |
| SR-093 | Reconciled | Backup does not mutate the source |
| SR-094 | Reconciled | Read-only source access is sufficient |
| SR-095 | Retained outcome; delivery links reviewed | One configuration covers several locations in one run |
| SR-096 | Retained outcome; delivery links reviewed | With compression off, nothing is compressed |
| SR-097 | Retained outcome; delivery links reviewed | The space view lists files by space taken |
| SR-098 | Retained outcome; delivery links reviewed | The space view gives a media encoding measure |
| SR-099 | Retained outcome; delivery links reviewed | A missing media measure changes nothing else and the space view says so |
| SR-100 | Reconciled | A run that changes nothing adds no saved state |
| SR-101 | Reconciled | An interrupted removal loses nothing and can be re-run |
| SR-102 | Reconciled | A removal is confined to the chosen backup |
| SR-103 | Reconciled | Read-only actions change nothing in the store |
| SR-104 | Retained outcome; delivery links reviewed | Reports and checks return machine-readable findings |
| SR-105 | Retained outcome; delivery links reviewed | A re-read that finds new content captures it |
| SR-106 | Retired with record | Reading and restoring still work while a backup is held |
| SR-107 | Reconciled | A dead holder's claim on a backup is released |
| SR-108 | Reconciled | New content is deduplicated only against content actually present |
| SR-109 | Reconciled | Repair acts only on supported, checked corrections |
| SR-110 | Reconciled | Interrupted maintenance preserves recovery or a detectable resumable route |
| SR-111 | Reconciled | A change of compression setting leaves stored content as it is |
| SR-112 | Retained outcome; delivery links reviewed | Runs, checks and restores stay within their total memory bound at scale |
| SR-113 | Retained outcome; delivery links reviewed | A run's time follows what changed, and grows less than in proportion to stored history |
| SR-114 | Reconciled | Older-version transition support is explicitly designated |
| SR-115 | Reconciled | The current restore kit restores states written by older supported versions |
| SR-116 | Reconciled | Designated older-format limitations are explicit |
| SR-117 | Reconciled | The owner can refresh the restore kits in an existing backup |
| SR-118 | Reconciled | A missing restore tool is refused by name |
| SR-119 | Retained outcome; delivery links reviewed | A damaged file is restored from another intact copy or named |
| SR-120 | Reconciled | An incomplete restore names every file not restored, its cause and the count |
| SR-121 | Reconciled | A restore never writes outside its target |
| SR-122 | Reconciled | Hidden and system folders come back hidden, or the gap is reported |
| SR-123 | Reconciled | A configuration written for an older supported description version keeps its meaning |
| SR-124 | Retained outcome; delivery links reviewed | Each run's record says what was added, changed, removed and failed |
| SR-125 | Retained outcome; delivery links reviewed | A long run shows progress at least every two minutes |
| SR-126 | Retained outcome; delivery links reviewed | Every refusal states what was found and what to do |
| SR-127 | Retained outcome; delivery links reviewed | A failed notification never changes the run's outcome |
| SR-128 | Retained outcome; delivery links reviewed | Notification credentials the system handles are never written in plain form |
| SR-129 | Reconciled | A configuration carrying readable credentials is refused |
| SR-130 | Retained outcome; delivery links reviewed | The container needs no more access than reading the source and writing its own locations |
| SR-131 | Retained outcome; delivery links reviewed | Third-party components shipped in a backup are licensed for it and carry their notices |
| SR-132 | Reconciled | A required component absent on first use is obtained or named |
| SR-133 | Retained outcome; delivery links reviewed | A missing optional extra is skipped visibly |
| SR-134 | Reconciled | The shipped example configuration is accepted |
| SR-135 | Reconciled | Each configuration states the version of the description it follows |
| SR-136 | Reconciled | Each host continues the other's backup identically |
| SR-137 | Reconciled | A link or junction to a folder outside its source is followed |
| SR-138 | Reconciled | A backup or saved-state location that overlaps a source is refused |
| SR-139 | Retired with record | The change-detection state lives at the source root unless configured elsewhere |
| SR-140 | Retired with record | A read-only source with no state location set elsewhere is refused before the run starts |
| SR-141 | Reconciled | A restore target whose real location cannot be established is refused |
| SR-142 | Retained outcome; delivery links reviewed | A container started without naming an action runs a backup |
| SR-143 | Retained outcome; delivery links reviewed | Third-party components in the container image are licensed for it and carry their notices |
| SR-144 | Retired with record | A run whose work was reclaimed after its claim was lost changes nothing more |
| SR-145 | Reconciled | A restore makes every whole-restore refusal before it writes anything |
| SR-146 | Reconciled | A current-form state with missing or malformed folder metadata restores its files and reports part failed |
| SR-147 | Retained outcome; delivery links reviewed | With the space view off, the run's record says the media measure was not taken |
| SR-148 | Retired with record | A change-detection state given a location is kept there |
| SR-149 | Retired with record | A change-detection state location inside a source or inside the store is refused |
| SR-150 | Reconciled | In-root folder links record a portable destination without repeated traversal |
| SR-151 | Reconciled | Links into protected system locations are not traversed |
| SR-152 | Reconciled | Supported in-root folder links restore as relative links |

## Need-to-SR review index

This index is a navigation aid over the current parent links, not independent
proof that the need is fully specified or implemented.

| Approved need | Draft SRs |
|---|---|
| SN-001 | SR-001, SR-074, SR-088, SR-089, SR-137, SR-150, SR-151 |
| SN-002 | SR-003 |
| SN-003 | SR-081, SR-096 |
| SN-004 | SR-005, SR-041, SR-100 |
| SN-005 | SR-007, SR-008, SR-118 |
| SN-006 | SR-010 |
| SN-007 | SR-011, SR-105 |
| SN-008 | SR-062 |
| SN-009 | SR-014, SR-095 |
| SN-010 | SR-015, SR-127 |
| SN-011 | SR-016, SR-073 |
| SN-012 | SR-027, SR-132 |
| SN-013 | SR-017, SR-075, SR-082, SR-086, SR-158 |
| SN-015 | SR-019, SR-099, SR-126, SR-132, SR-133 |
| SN-019 | SR-023, SR-052, SR-145, SR-158 |
| SN-021 | SR-024, SR-100 |
| SN-022 | SR-008, SR-031, SR-071, SR-118, SR-156 |
| SN-023 | SR-033, SR-136, SR-156 |
| SN-024 | SR-034, SR-048, SR-094, SR-130, SR-142 |
| SN-025 | SR-039, SR-116, SR-145, SR-155 |
| SN-026 | SR-040 |
| SN-027 | SR-018, SR-063, SR-123, SR-126, SR-138, SR-154 |
| SN-029 | SR-045, SR-046, SR-101, SR-102, SR-155 |
| SN-030 | SR-049, SR-103, SR-104 |
| SN-031 | SR-053, SR-108 |
| SN-032 | SR-021, SR-055, SR-092 |
| SN-033 | SR-056, SR-119, SR-155 |
| SN-034 | SR-041, SR-059, SR-063 |
| SN-035 | SR-072, SR-073 |
| SN-036 | SR-065, SR-066, SR-122, SR-146, SR-150, SR-152 |
| SN-037 | SR-063, SR-093, SR-094, SR-138 |
| SN-038 | SR-036 |
| SN-039 | SR-085, SR-086, SR-107, SR-154 |
| SN-040 | SR-061, SR-114, SR-126, SR-156 |
| SN-041 | SR-084, SR-110, SR-115, SR-116, SR-117, SR-156 |
| SN-042 | SR-009, SR-121, SR-141, SR-145 |
| SN-043 | SR-064, SR-112, SR-113 |
| SN-044 | SR-041, SR-089, SR-124, SR-125, SR-126 |
| SN-045 | SR-043, SR-104 |
| SN-046 | SR-047, SR-103, SR-104, SR-155 |
| SN-047 | SR-109, SR-110 |
| SN-048 | SR-068, SR-111 |
| SN-049 | SR-128, SR-129 |
| SN-050 | SR-042, SR-123, SR-134, SR-135 |
| SN-051 | SR-097, SR-098, SR-099, SR-147 |
| SN-052 | SR-067, SR-089, SR-090, SR-091 |
| SN-053 | SR-029, SR-092, SR-119, SR-120, SR-145, SR-146, SR-158 |
| SN-054 | SR-131, SR-143, SR-157 |
| SN-055 | SR-153, SR-156 |

## Validation and next gate

Strict trace integrity passed with zero findings. Documentation checks passed
with zero broken links; whitespace and approval-scope checks passed. The
cross-review record gives the counts and dispositions. The expected inherited
debt remains visible: LLR/TC orphan links,
legacy schema/interface vocabulary and stakeholder-party reachability are not
fixed by approving assumptions or drafting SRs. New orphan references caused
by explicit retirement are kept for accountable downstream reconciliation;
they are not mechanically reassigned to a vaguely related requirement. The
report has 131 orphans (previously 119) and one inherited interface finding;
LLR-035/038/046/049/087 directly reference newly retired SRs. This does not
pass the full spine gate and does not establish implementation conformance.

Next is owner review of the SR outcomes and proposed policy choices above.
After acceptance, decompose to design/LLRs and interface contracts, then map
existing code/tests to each obligation as satisfied, partial, conflicting,
missing or obsolete. Only then can the Rust work packages distinguish reusable
contracts, current defects and new implementation work. No implementation
conformance or full spine gate is claimed by this draft.
