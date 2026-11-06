# Native memory reduction through shared records

Date: 2026-11-06 (America/Chicago). Baseline: `5033473` plus test-only RSS logging.

The owner authorized iterative implementation, preferring fewer redundant
records and simpler ownership. This implements the practical parts of the
[Opus memory review](memory-review-2026-11-06.md). It does not change the store
format, recovery scripts, accepted budgets or qualification status.

## What changed

- A single portable-path map replaces the working-row map plus its separate
  portable-to-original-path map. Original spelling is still checked before
  reuse; final rows sort by recorded path before duplicate-owner assignment.
- The walk retains relative paths, deriving a native source path only when
  needed. First attempts iterate directly; only failures enter the retry heap.
  The seen-path set is built after capture supply is released and only for a
  complete walk. Unreadable-source protection and retry order remain intact.
- Unchanged rows stay borrowed through finalization and publication. A row is
  copied only when a derived duplicate flag actually changes. Validation,
  comparison and publication accept the same row references. Prior rows remain
  immutable until accounting is complete; final rows are released before the
  second object index is built.
- Hashes occupy 16 bytes in memory. Strict serde conversion preserves the
  existing uppercase, fixed-width hexadecimal CSV representation. Big-endian
  bytes preserve the existing identity ordering. There is no hash-algorithm,
  object-name or schema change.
- Objects share state-directory paths, including newly captured/moved objects.
  Verification-cache keys borrow object paths from the immutable index.
- Canonical CSV streams into the existing atomic temporary-file publication
  protocol. Byte-slice callers and streamed callers use one publication core;
  CSV errors return before sync/rename. File sync, permissions and host rename
  behavior remain unchanged. Small byte-buffer helpers remain for existing
  callers and tests.

The result removes whole-file work queues, a redundant map and full manifest
copies. It is not a net line-count reduction: compact-hash conversion, shared
writer adapters, tests and diagnostic logging add some code. No new database,
spill layer, allocator dependency or alternate backup protocol was introduced.

## Matched diagnostic trials

One retained private Linux RAM-filesystem corpus held one million independent
eight-byte source files and one million valid stored objects. Its manifest was
**147,000,125 bytes**, about 147 bytes per row. The former `FileRow` alone held
eight string handles plus a length; decoded records, allocations and lookup
structures cost more than the CSV text. This is not evidence that a manifest
must always use the same memory regardless of path lengths.

Trials used the same source/store path, four-logical-CPU affinity and the existing
50 ms simultaneous process-tree RSS sampler. Diagnostic builds enabled only the
existing `test-hooks` feature; phase tracing now also reads Linux VmRSS/VmHWM.
Phase readings include retained allocator pages, not just live allocations.
Available RAM greatly exceeded 2 GB, and kernel memory backing the corpus is
outside application RSS. Caches were uncontrolled; other builds/tests sometimes
ran concurrently. Elapsed times are observations, not isolated speedup claims.

| Stage | Backup peak bytes | Deep-check peak bytes | Backup / check seconds |
|---|---:|---:|---:|
| Baseline | 1,759,891,456 | 1,242,386,432 | 40.377 / 38.212 |
| One path map, relative walk paths, retry-only heap, borrowed verify keys | 1,408,462,848 | 1,178,935,296 | 37.716 / 32.580 |
| Borrow rows through finalization | 1,233,551,360 | 1,179,103,232 | 38.240 / 30.853 |
| Binary hashes and shared indexed state paths | 1,003,864,064 | 920,707,072 | 34.085 / 31.450 |
| Stream canonical manifest publication | 976,928,768 | 921,284,608 | 31.757 / 28.305 |

The matched diagnostic backup peak fell about **44.5%**. Baseline peak occurred
at final-row construction; the streamed candidate's peak was during source-walk
and capture bookkeeping. The changed absolute fixture path is longer than the
earlier 1.681 GB trial's path, so use this matched baseline for comparisons.

## Final release and mixed-workload measurements

The final Windows and Linux release executables were built without `test-hooks`.
All completed measurements below returned 0, stayed below the sampler guard and
reported no measurement errors. MB/GB descriptions use decimal bytes.

| Executable / workload | Peak simultaneous RSS bytes | Seconds |
|---|---:|---:|
| Linux release, unchanged 1M-file corpus | 973,242,368 | 44.363 |
| Linux release, deep check of that state | 920,342,528 | 40.544 |
| Linux release, 1M reused files plus a new compressed 1 GiB file | 1,143,861,248 | 42.919 |
| Linux release, deep check of latest plus its prior state | 952,504,320 | 42.556 |
| Linux diagnostic, change that 1 GiB file and force a checkpoint after capture | 1,143,361,536 | 43.120 |
| Linux diagnostic, deep check after the second change | 975,323,136 | 55.705 |
| Windows release, D: HDD unchanged 100k-file corpus with 365 saved states | 103,985,152 | 34.844 |
| Windows release, same HDD corpus plus a compressed 1 GiB file | 505,729,024 | 54.203 |
| Windows release, deep check of latest plus 366 history states (36,700,001 rows) | 139,718,656 | 595.110 |

Release counters confirmed exactly 1,000,000 reused files and zero captures on
the unchanged Linux run. The compressed run captured one new file; the forced
checkpoint run captured one changed file; both reused the other million with
zero failures or removals. Diagnostic stderr confirms `manifest-checkpoint` was
reached. Mixed-run peaks include the simultaneously observed 7-Zip process.
Two history states now exist, so the final diagnostic verification inspects
3,000,002 logical rows; do not compare that time as a single-state check.

The Windows fixture is the existing private D: NTFS corpus. Source and store
share the same HGST rotational drive; staging is in the store. Its 365 historical
manifests share the same 100k objects; adding a file creates the 366th history
state. This is history-scan characterization beyond the 365-history envelope,
not a second full logical data copy for each state. The reference HDD topology,
2 TiB volume and four physical cores are not established by this fixture.
The HDD deep check verified all 36,700,001 logical references with zero failures.

## Review and correctness checks

Opus 5.5 low session `343a4765-6e2a-4b09-860a-749223a690bc` reviewed the approved
seven-file source/measurement bundle and found no high/medium defect. Its one
allocation suggestion was adopted: `Store.current` is shared too, so capture
does not allocate another state path for every new object. Focused follow-up
`81628a5a-a11d-4dc7-9f3f-d1fdd2a17be7` reviewed engine/store/maintenance and found
no high/medium defect. Neither review executed tests. The publication helper
and tests were not supplied; its raw-file callback/sync ordering was checked
locally and exercised by regressions. The reviewer explicitly noted that scope.

Windows passed **44 tests** and Linux **47 tests**, with strict Clippy on both.
The additional regression checks recorded-path duplicate ownership, byte-identical
unchanged publication, and preservation of old history flags when the owner file
is removed. Existing independent hash/name vectors and script recovery pass.
Streaming tests compare bytes against the canonical buffer writer and inject a
partial-output failure, proving the old target remains unchanged. Process-kill
coverage now includes an intermediate manifest checkpoint alongside the seven
existing backup interruption points.

A test-only `FILEBACKUP_TEST_CHECKPOINT=1` makes the initial checkpoint immediately
due, allowing its memory/publication path to be exercised without a sleep.
This and phase-memory logging are compiled out of default/release builds unless
`test-hooks` is explicitly requested. Ordinary backup still uses 60 seconds.
Compression is synchronous; checkpoint serialization follows capture and is not
counted as concurrent with the compressor.

The earlier review's early-compression concern was based on overlooking the
walk's final sort. Existing `new-gib.txt` already follows the million `d...` paths.
That concern is withdrawn; it is not a newly discovered resource violation.

Full 1M-file/2 TiB/365-state HDD qualification, mixed/high-churn workloads across
the supported envelope, cold-cache repetition and actual 2 GB-host testing remain
open. macOS remains deferred. Diagnostic and small-corpus results do not close
those requirements.

## Delivery and repository checks

Optimized release packages are local, not published:

- `D:/FileBackupBuild/packages/filebackup-native-windows-x64-memory-20261106.zip`
- `D:/FileBackupBuild/packages/filebackup-native-linux-x64-memory-20261106.zip`

All 204 Windows and 336 Linux packaged-file checksums passed. ZIP integrity and
archive/file byte comparisons passed too. Package support notes reference the
new evidence; the packaging helper converts those source-repository links to
plain references as it does for the earlier evidence links. The previously built
container image is not rebuilt by this memory-only iteration.

Document checks cover 463 documents and 788 links with zero broken links (29
existing orphan warnings); the interface map and formatting/whitespace checks
pass. Strict trace retains the same 18 approved-SR form findings, with zero
orphan, integrity or interface findings. TC-298/299 and implementation-map notes
link this evidence without changing approval statuses. No gates were enabled.

The temporary Linux RAM mount and corpus were removed after measurement. Private
HDD fixtures, build caches and packages remain on D:. C: retains about 33 GiB
free. Reproduce final-release cardinality runs with `cardinality_fixture` and
`scripts/measure_native.py` as documented in the earlier
[performance record](performance-validation.md); initial fixture assembly is
excluded from the measured backup operation.

Raw input, source hashes, Opus JSON, build/test logs and measurement JSON/stdout/
stderr are retained under ignored `.artifacts/native-transition/memory-08-*`.
