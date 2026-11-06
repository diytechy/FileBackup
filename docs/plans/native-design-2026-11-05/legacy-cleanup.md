# Legacy baseline cleanup

The owner authorized removal of obsolete interfaces and requirements on the
Rust rewrite branch. This cleanup retires the imported PowerShell-era design and
test definitions as an active baseline; it does not declare all their behavior
obsolete or claim the native replacement is implemented or equivalent.

## Active scope

| Registry | Before | After |
|---|---:|---:|
| LLR design definitions | 127 | 40 Drafted: LLR-151..190 |
| Test definitions | 281 | 41 Drafted: TC-261..301 |
| Interfaces | 25 | 24 Drafted: IF-002..025 |

The 49 accepted needs, 121 accepted SRs, approved boundaries and assumptions,
all approval snapshots, and the ID watermarks are unchanged. The new rows are
unchanged: this removes a superseded baseline, not a verification obligation.
No hooks are enabled and no product source or executable tests are removed.

## Disposition and retained obligations

The legacy LLRs were read before retirement. Their text mixes useful behavior
with removed functions, old layouts and contracts already contradicted by later
rows. Maintaining two active decompositions would misstate the native design.
The accepted parent outcomes remain authoritative. The following dispositions
identify where to carry the useful details into implementation work:

| Legacy subject | Disposition / native work |
|---|---|
| Walk, hash, deduplication, compression, retry, protected prior rows | Keep outcomes in LLR-156..163; reconcile concrete source fixtures in N1/N3. Old group-election and retry timing prescriptions do not override approved policy. |
| Name/hash encoding, CSV, path separators, shards and pool lookup | Retain current contracts and golden vectors through LLR-163/164/172/187 and IF-006/007; pin them in N1 before binding native code. |
| Prior-state publication and atomic writes | LLR-165/166 retain ordering, flush and recovery obligations, with owner-approved `.prev` preservation. Old witness writing and manifest-blanking optimization are removed. |
| Heartbeat takeover, stale markers, source cache and old configuration keys | Superseded mechanisms. LLR-151/152/155/166 cover admission, supported OS-lifetime ownership and known scratch cleanup. |
| Recovery, physical containment, hidden files, timestamps and portable adapters | Preserve outcomes in LLR-172..179/187. Retained script tests are migration inputs; compare actual assertions before claiming native verification. |
| Directory metadata | LLR-164/175..177 replace silent omission with required metadata diagnostics and add portable links and folder-only change history. |
| Prune, rehoming, inventory, repair, browse and bounded memory | LLR-168..171/182/188 retain valid outcomes under the accepted retention window. Old witness/whole-pool rails do not reintroduce retired policy. |
| Shell backup engine, seven-file kits, legacy path sidecar and version-specific configuration | Rust backup plus independent PowerShell/bash recovery is the selected scope. LLR-183..187/190 govern delivery, refresh and declared support; no legacy versions are designated supported. |
| GUI/picker launch details, notifications and exit propagation | LLR-178..181/184/190 carry the required user outcomes. Existing executable regressions remain available during platform adaptation. |
| Legacy test definitions and pass labels | Retire from the active native test plan. Keep executable tests, original results and assertions as porting references; neither old passes nor new links demonstrate native conformance. |

The [retired design crosswalk](allocation.md#retired-legacy-design-crosswalk)
links all 87 LLR lookup records and candidate native areas. Those candidates are
not proven successors. The 240 TC records below preserve ID lookup without a
false one-to-one successor. Broad native cases still need concrete assertions,
fixtures and executed evidence in each work package.

## IF-001 and redundant files

IF-001's HomeHub OCI v1 agreement is removed from the active registry. Its
one-set PowerShell invocation is not the future native multi-set contract;
Drafted IF-019, LLR-183 and TC-293 govern that proposal. This branch cleanup
does not change the shipped container, a counterparty deployment or its behavior.
Integration acceptance is still required when native delivery replaces it.
IF-001 remains spent. The pinned retirement writer handles SN/SR/LLR/TC only,
so this section is IF-001's disposition rather than an unsupported retirement row.

The following redundant copies are deleted; exact contents remain in commit
`a184d9a`:

- `docs/interfaces/legacy-homehub.md`
- `docs/plans/native-design-2026-11-05/legacy/interfaces.csv`
- `docs/plans/native-design-2026-11-05/legacy/interfaces-overview.md.txt`

For example, `git show a184d9a:docs/interfaces/legacy-homehub.md` retrieves the
former contract. The same syntax retrieves either retired registry definition
from `docs/requirements/low-level-requirements.toml` or `docs/test/test-cases.toml`.

Example-only `assets.csv`, `procurement.csv` and `performance-budgets.csv` are
also removed from `docs/requirements`; each held only an ID-000 template row.
No actual asset, purchased part or accepted performance target is removed.
Their optional tooling remains available. The empty component carrier remains
because the approval-baseline reader expects it.

## History deliberately retained

Keep the [original evidence harvest](../spine-rebaseline-2026-11-05/legacy/evidence-harvest.json),
original LLR/TC CSVs, approval snapshots, dated audits, owner decisions, review
reports and implementation plans still referenced by the existing engine guide.
They explain current code and previous decisions; they are not competing live
requirements. Old `Implements:` and test IDs in executable source identify this
historical baseline and can be looked up in the retirement records. No source
annotation is rebound to a native draft without inspecting its actual behavior.

## Retired test lookup

- [TC-001](../../log.d/retired/TC-001.md), [TC-002](../../log.d/retired/TC-002.md), [TC-003](../../log.d/retired/TC-003.md), [TC-004](../../log.d/retired/TC-004.md), [TC-005](../../log.d/retired/TC-005.md), [TC-006](../../log.d/retired/TC-006.md), [TC-007](../../log.d/retired/TC-007.md), [TC-008](../../log.d/retired/TC-008.md)
- [TC-009](../../log.d/retired/TC-009.md), [TC-010](../../log.d/retired/TC-010.md), [TC-011](../../log.d/retired/TC-011.md), [TC-012](../../log.d/retired/TC-012.md), [TC-013](../../log.d/retired/TC-013.md), [TC-014](../../log.d/retired/TC-014.md), [TC-015](../../log.d/retired/TC-015.md), [TC-016](../../log.d/retired/TC-016.md)
- [TC-017](../../log.d/retired/TC-017.md), [TC-018](../../log.d/retired/TC-018.md), [TC-019](../../log.d/retired/TC-019.md), [TC-020](../../log.d/retired/TC-020.md), [TC-021](../../log.d/retired/TC-021.md), [TC-022](../../log.d/retired/TC-022.md), [TC-024](../../log.d/retired/TC-024.md), [TC-025](../../log.d/retired/TC-025.md)
- [TC-026](../../log.d/retired/TC-026.md), [TC-027](../../log.d/retired/TC-027.md), [TC-028](../../log.d/retired/TC-028.md), [TC-030](../../log.d/retired/TC-030.md), [TC-031](../../log.d/retired/TC-031.md), [TC-032](../../log.d/retired/TC-032.md), [TC-033](../../log.d/retired/TC-033.md), [TC-034](../../log.d/retired/TC-034.md)
- [TC-035](../../log.d/retired/TC-035.md), [TC-036](../../log.d/retired/TC-036.md), [TC-037](../../log.d/retired/TC-037.md), [TC-038](../../log.d/retired/TC-038.md), [TC-039](../../log.d/retired/TC-039.md), [TC-040](../../log.d/retired/TC-040.md), [TC-041](../../log.d/retired/TC-041.md), [TC-042](../../log.d/retired/TC-042.md)
- [TC-043](../../log.d/retired/TC-043.md), [TC-044](../../log.d/retired/TC-044.md), [TC-045](../../log.d/retired/TC-045.md), [TC-046](../../log.d/retired/TC-046.md), [TC-047](../../log.d/retired/TC-047.md), [TC-048](../../log.d/retired/TC-048.md), [TC-049](../../log.d/retired/TC-049.md), [TC-050](../../log.d/retired/TC-050.md)
- [TC-051](../../log.d/retired/TC-051.md), [TC-052](../../log.d/retired/TC-052.md), [TC-053](../../log.d/retired/TC-053.md), [TC-054](../../log.d/retired/TC-054.md), [TC-055](../../log.d/retired/TC-055.md), [TC-056](../../log.d/retired/TC-056.md), [TC-057](../../log.d/retired/TC-057.md), [TC-058](../../log.d/retired/TC-058.md)
- [TC-059](../../log.d/retired/TC-059.md), [TC-060](../../log.d/retired/TC-060.md), [TC-061](../../log.d/retired/TC-061.md), [TC-062](../../log.d/retired/TC-062.md), [TC-063](../../log.d/retired/TC-063.md), [TC-064](../../log.d/retired/TC-064.md), [TC-065](../../log.d/retired/TC-065.md), [TC-066](../../log.d/retired/TC-066.md)
- [TC-067](../../log.d/retired/TC-067.md), [TC-068](../../log.d/retired/TC-068.md), [TC-069](../../log.d/retired/TC-069.md), [TC-070](../../log.d/retired/TC-070.md), [TC-071](../../log.d/retired/TC-071.md), [TC-072](../../log.d/retired/TC-072.md), [TC-073](../../log.d/retired/TC-073.md), [TC-074](../../log.d/retired/TC-074.md)
- [TC-075](../../log.d/retired/TC-075.md), [TC-076](../../log.d/retired/TC-076.md), [TC-077](../../log.d/retired/TC-077.md), [TC-078](../../log.d/retired/TC-078.md), [TC-079](../../log.d/retired/TC-079.md), [TC-080](../../log.d/retired/TC-080.md), [TC-081](../../log.d/retired/TC-081.md), [TC-082](../../log.d/retired/TC-082.md)
- [TC-083](../../log.d/retired/TC-083.md), [TC-084](../../log.d/retired/TC-084.md), [TC-085](../../log.d/retired/TC-085.md), [TC-086](../../log.d/retired/TC-086.md), [TC-087](../../log.d/retired/TC-087.md), [TC-088](../../log.d/retired/TC-088.md), [TC-089](../../log.d/retired/TC-089.md), [TC-090](../../log.d/retired/TC-090.md)
- [TC-091](../../log.d/retired/TC-091.md), [TC-092](../../log.d/retired/TC-092.md), [TC-093](../../log.d/retired/TC-093.md), [TC-094](../../log.d/retired/TC-094.md), [TC-096](../../log.d/retired/TC-096.md), [TC-097](../../log.d/retired/TC-097.md), [TC-098](../../log.d/retired/TC-098.md), [TC-099](../../log.d/retired/TC-099.md)
- [TC-100](../../log.d/retired/TC-100.md), [TC-101](../../log.d/retired/TC-101.md), [TC-102](../../log.d/retired/TC-102.md), [TC-103](../../log.d/retired/TC-103.md), [TC-104](../../log.d/retired/TC-104.md), [TC-105](../../log.d/retired/TC-105.md), [TC-106](../../log.d/retired/TC-106.md), [TC-107](../../log.d/retired/TC-107.md)
- [TC-108](../../log.d/retired/TC-108.md), [TC-109](../../log.d/retired/TC-109.md), [TC-110](../../log.d/retired/TC-110.md), [TC-111](../../log.d/retired/TC-111.md), [TC-112](../../log.d/retired/TC-112.md), [TC-113](../../log.d/retired/TC-113.md), [TC-114](../../log.d/retired/TC-114.md), [TC-115](../../log.d/retired/TC-115.md)
- [TC-116](../../log.d/retired/TC-116.md), [TC-117](../../log.d/retired/TC-117.md), [TC-118](../../log.d/retired/TC-118.md), [TC-119](../../log.d/retired/TC-119.md), [TC-120](../../log.d/retired/TC-120.md), [TC-121](../../log.d/retired/TC-121.md), [TC-122](../../log.d/retired/TC-122.md), [TC-123](../../log.d/retired/TC-123.md)
- [TC-124](../../log.d/retired/TC-124.md), [TC-125](../../log.d/retired/TC-125.md), [TC-126](../../log.d/retired/TC-126.md), [TC-127](../../log.d/retired/TC-127.md), [TC-128](../../log.d/retired/TC-128.md), [TC-129](../../log.d/retired/TC-129.md), [TC-130](../../log.d/retired/TC-130.md), [TC-131](../../log.d/retired/TC-131.md)
- [TC-132](../../log.d/retired/TC-132.md), [TC-133](../../log.d/retired/TC-133.md), [TC-134](../../log.d/retired/TC-134.md), [TC-135](../../log.d/retired/TC-135.md), [TC-136](../../log.d/retired/TC-136.md), [TC-137](../../log.d/retired/TC-137.md), [TC-138](../../log.d/retired/TC-138.md), [TC-139](../../log.d/retired/TC-139.md)
- [TC-140](../../log.d/retired/TC-140.md), [TC-141](../../log.d/retired/TC-141.md), [TC-142](../../log.d/retired/TC-142.md), [TC-143](../../log.d/retired/TC-143.md), [TC-144](../../log.d/retired/TC-144.md), [TC-145](../../log.d/retired/TC-145.md), [TC-146](../../log.d/retired/TC-146.md), [TC-147](../../log.d/retired/TC-147.md)
- [TC-148](../../log.d/retired/TC-148.md), [TC-149](../../log.d/retired/TC-149.md), [TC-150](../../log.d/retired/TC-150.md), [TC-151](../../log.d/retired/TC-151.md), [TC-152](../../log.d/retired/TC-152.md), [TC-153](../../log.d/retired/TC-153.md), [TC-154](../../log.d/retired/TC-154.md), [TC-155](../../log.d/retired/TC-155.md)
- [TC-156](../../log.d/retired/TC-156.md), [TC-157](../../log.d/retired/TC-157.md), [TC-158](../../log.d/retired/TC-158.md), [TC-159](../../log.d/retired/TC-159.md), [TC-160](../../log.d/retired/TC-160.md), [TC-161](../../log.d/retired/TC-161.md), [TC-162](../../log.d/retired/TC-162.md), [TC-163](../../log.d/retired/TC-163.md)
- [TC-164](../../log.d/retired/TC-164.md), [TC-165](../../log.d/retired/TC-165.md), [TC-166](../../log.d/retired/TC-166.md), [TC-167](../../log.d/retired/TC-167.md), [TC-168](../../log.d/retired/TC-168.md), [TC-169](../../log.d/retired/TC-169.md), [TC-170](../../log.d/retired/TC-170.md), [TC-171](../../log.d/retired/TC-171.md)
- [TC-172](../../log.d/retired/TC-172.md), [TC-173](../../log.d/retired/TC-173.md), [TC-174](../../log.d/retired/TC-174.md), [TC-175](../../log.d/retired/TC-175.md), [TC-176](../../log.d/retired/TC-176.md), [TC-177](../../log.d/retired/TC-177.md), [TC-178](../../log.d/retired/TC-178.md), [TC-179](../../log.d/retired/TC-179.md)
- [TC-180](../../log.d/retired/TC-180.md), [TC-181](../../log.d/retired/TC-181.md), [TC-182](../../log.d/retired/TC-182.md), [TC-183](../../log.d/retired/TC-183.md), [TC-184](../../log.d/retired/TC-184.md), [TC-185](../../log.d/retired/TC-185.md), [TC-186](../../log.d/retired/TC-186.md), [TC-187](../../log.d/retired/TC-187.md)
- [TC-188](../../log.d/retired/TC-188.md), [TC-189](../../log.d/retired/TC-189.md), [TC-190](../../log.d/retired/TC-190.md), [TC-191](../../log.d/retired/TC-191.md), [TC-192](../../log.d/retired/TC-192.md), [TC-193](../../log.d/retired/TC-193.md), [TC-194](../../log.d/retired/TC-194.md), [TC-195](../../log.d/retired/TC-195.md)
- [TC-196](../../log.d/retired/TC-196.md), [TC-197](../../log.d/retired/TC-197.md), [TC-198](../../log.d/retired/TC-198.md), [TC-199](../../log.d/retired/TC-199.md), [TC-200](../../log.d/retired/TC-200.md), [TC-201](../../log.d/retired/TC-201.md), [TC-202](../../log.d/retired/TC-202.md), [TC-203](../../log.d/retired/TC-203.md)
- [TC-204](../../log.d/retired/TC-204.md), [TC-222](../../log.d/retired/TC-222.md), [TC-223](../../log.d/retired/TC-223.md), [TC-224](../../log.d/retired/TC-224.md), [TC-225](../../log.d/retired/TC-225.md), [TC-226](../../log.d/retired/TC-226.md), [TC-227](../../log.d/retired/TC-227.md), [TC-228](../../log.d/retired/TC-228.md)
- [TC-229](../../log.d/retired/TC-229.md), [TC-230](../../log.d/retired/TC-230.md), [TC-231](../../log.d/retired/TC-231.md), [TC-232](../../log.d/retired/TC-232.md), [TC-233](../../log.d/retired/TC-233.md), [TC-234](../../log.d/retired/TC-234.md), [TC-235](../../log.d/retired/TC-235.md), [TC-236](../../log.d/retired/TC-236.md)
- [TC-237](../../log.d/retired/TC-237.md), [TC-238](../../log.d/retired/TC-238.md), [TC-239](../../log.d/retired/TC-239.md), [TC-240](../../log.d/retired/TC-240.md), [TC-241](../../log.d/retired/TC-241.md), [TC-242](../../log.d/retired/TC-242.md), [TC-243](../../log.d/retired/TC-243.md), [TC-244](../../log.d/retired/TC-244.md)
- [TC-245](../../log.d/retired/TC-245.md), [TC-246](../../log.d/retired/TC-246.md), [TC-247](../../log.d/retired/TC-247.md), [TC-248](../../log.d/retired/TC-248.md), [TC-249](../../log.d/retired/TC-249.md), [TC-250](../../log.d/retired/TC-250.md), [TC-251](../../log.d/retired/TC-251.md), [TC-252](../../log.d/retired/TC-252.md)
- [TC-253](../../log.d/retired/TC-253.md), [TC-254](../../log.d/retired/TC-254.md), [TC-255](../../log.d/retired/TC-255.md), [TC-256](../../log.d/retired/TC-256.md), [TC-257](../../log.d/retired/TC-257.md), [TC-258](../../log.d/retired/TC-258.md), [TC-259](../../log.d/retired/TC-259.md), [TC-260](../../log.d/retired/TC-260.md)

## Validation and independent review

The [Gemini Argon review](gemini-cleanup-review.md), through OpenCode Go on low,
found no high-risk issue. Its disclosed limits include the absence of full retired
TC assertion text and executable code; work-package reconciliation remains required.

Scope checks confirm all accepted upstream registries, approval snapshots, ID
watermarks and surviving native rows are unchanged; runtime and executable tests
are untouched. All 121 accepted SRs retain planned design and case allocation.
All 327 retired LLR/TC IDs have lookup records, with no fabricated successors.

- `trace.py --strict-integrity`: exit 0; orphans 0, integrity 0, interface findings 0.
- `trace.py --strict --strict-schema`: exit 1; 39 native automated cases still lack
  concrete test-evidence bindings, with 18 existing requirement-form findings and
  four acceptance-criteria advisories. These are visible outstanding work.
- `gen_interface_map.py --check`: generated map current.
- `check_docs.py`: no broken links; existing historical orphan-document warnings remain.
- `git diff --check`: clean. No product runtime suite or benchmark was run for this
  documentation and trace-navigation cleanup.

The next implementation preparation is N1: pin shared serialization/format and
script-reader fixtures, reconcile useful legacy assertions, and split the broad
native cases into executable checks. Draft approval and measured platform/scale
evidence are still open; removing old registry rows does not close a gate.
