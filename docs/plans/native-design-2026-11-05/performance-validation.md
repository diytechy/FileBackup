# Native performance work — 2026-11-06

The owner deferred macOS validation and authorized continued Windows/Linux
performance work. These are development measurements, not acceptance of the full
1M-file / 2 TiB / 365-state reference envelope. LLR/TC/IF statuses remain Drafted.
See the [implementation bindings](implementation-map.md) and
[earlier validation](implementation-validation.md) for the remaining obligations.

The owner subsequently clarified that deployed drives are platter drives. The
[reference storage correction](owner-hdd-reference.md) makes D: the candidate
for further HDD testing. Historical SSD and RAM measurements below retain their
actual labels; they do not establish elapsed-time compliance on HDDs. Time and
memory budgets remain unchanged and full qualification remains open.

## Method and scope

The reusable `scripts/measure_native.py` sampler uses development-only psutil
7.2.2. Every 50 ms it sums the resident memory of the operation and its observed
live descendants at that instant. It retains observed process identities across
reparenting. It does not add independent process peaks. Shared pages are counted
per process, and a child born and exited between samples can be missed. The sampler
records query errors, stops at a 1,900,000,000-byte guard or 30-minute deadline,
and terminates its observed processes when a probe stops. A fixture exercises
two simultaneous 24 MiB children; another checks deadline cleanup and refusal to
overwrite existing results. Both pass.

Each measured operation inherits affinity to four logical CPUs. The workstation
has 24 logical CPUs and substantially more available RAM than the 2 GB reference
host. Affinity does not reproduce four dedicated physical cores. C: is the local
SSD; D: is an HGST SATA rotational disk. WSL accesses Windows-mounted paths through
its filesystem bridge. Caches are uncontrolled. None of these results establish
compliance with the full 100 MiB/s sequential HDD reference, cold-cache behavior,
or operation on a 2 GB host. Further HDD trials must record physical-device
placement for source, store, restore target and scratch, including whether they
share a spindle. Existing D: trials remain partial evidence, not full qualification.

Fixtures are private. Cargo caches, packages and large disk corpora stay on D:.
The small C: corpus contains 3,000 distinct 4 KiB files plus eight 8 MiB files:
3,008 files and 79,396,864 logical bytes. Independent recovery comparisons check
every restored path and SHA-256 digest. No production store or live credentials
are involved.

## Changes driven by measurements

- Capture-only indexes now end before finalization rebuilds its indexes. Prior
  records end after change comparison/accounting. One reusable index insertion
  helper initially reserves one object slot per identity instead of four.
- Working rows borrow immutable prior records; only captured replacements own
  boxed rows. This avoids reserving an entire file record in each unchanged map
  entry. Final rows become owned before duplicate flags are updated.
- Canonical comparison sorts references and compares all fields instead of
  building two complete CSV buffers. Checkpoints serialize references through
  the same canonical writer. Portable collision grouping also borrows names.
- PowerShell's ASCII path-key fast path retains the shared Unicode path for
  non-ASCII names. Ordinary-ancestor checks use filesystem attributes directly.
  Access/I/O errors still refuse publication when ancestry cannot be confirmed.
- Bash streams each state's object names into the existing decoder, avoids
  repeated whole-pool filtering, and removes avoidable external commands. Raw
  recovery copies once and verifies the staged output; it does not first hash
  the same source again. On a failed copy only, a source check distinguishes
  unreadable content from a target-write failure. Candidate fallback remains.
- GNU `sync` with file operands performs per-file/parent fsync around publication;
  one final `sync -f` covers new ancestor directories and metadata. The earlier
  per-file `-f` flushed the entire filesystem repeatedly. This retains the
  existing flush ordering without adding a new recovery protocol.
- Native compression/extraction and both native kit extractors explicitly select
  two 7-Zip workers. A real combined million-file index plus 1 GiB capture crossed
  the 1.9 GB guard with automatic workers. The cap retains level 5 and its dictionary
  defaults; existing objects remain untouched and readable. More LZMA2 workers
  can require additional block buffers, as explained by
  [7-Zip's author](https://sourceforge.net/p/sevenzip/support-requests/581/).

## Real-file memory and history

The cardinality generator creates independent source and stored files with real
hashes, timestamps and canonical names. Each contains eight bytes, so a million
files exercise a million distinct identities and objects, not a million rows
referring to one object. It initializes a valid benchmark corpus directly; this
does not measure initial capture or establish power-loss durability.

An initial million-file run crossed the 1.9 GB guard. After the allocation fixes,
the diagnostic build completed backup at 1,680,760,832 bytes peak RSS and deep
check at 1,181,839,360 bytes. Final release measurements are recorded below.

The million-file corpus uses a temporary Linux RAM filesystem. Its kernel memory
is excluded from application RSS. This isolates application allocations; its
elapsed time is not disk-performance evidence and its host RAM use is much larger
than 2 GB. The mount and corpus are removed after each experiment.

Final release builds omit `test-hooks`. The million-file backup reports exactly
1,000,000 reused files, zero captured/changed/removed files, and exit 0.

| Corpus / operation | Elapsed | Peak sampled RSS | Result |
|---|---:|---:|---|
| Linux RAM filesystem, 1M source/object pairs, unchanged backup | 34.921 s | 1,680,551,936 bytes | Exit 0 |
| Same corpus, deep verification | 32.013 s | 1,183,100,928 bytes | Exit 0 |
| Windows D: NTFS, 100,000 source/object pairs, unchanged backup | 23.860 s | 168,849,408 bytes | Exit 0 |

The original Windows release's 100,000-pair run used 378,601,472 bytes. The final
run uses about 55% less peak RSS on that corpus. Its baseline elapsed time was
27.860 seconds; cache effects prevent attributing that small time difference
solely to the code change.

The Windows history corpus holds 100,000 distinct eight-byte objects and 100,000
rows per saved state. Historical definitions/kits are hard-linked to conserve
disk; all states reference the same current pool. A warmup precedes each set of
three unchanged-run trials. Actual reports confirm all 100,000 files reused and
zero captured/added/changed/removed/failed/frozen files in every trial. The final
history contains exactly 365 dated states.

| Saved states | Three unchanged trials | Median |
|---|---|---:|
| 182 | 23.094, 23.188, 24.015 s | 23.188 s |
| 364 | 23.640, 23.594, 23.453 s | 23.594 s |

The median ratio is **1.018**. A subsequent deep check of all 365 histories plus
latest, **36.6 million rows**, completed with exit 0 in **581.343 seconds** at
**147,001,344 bytes** peak RSS. These results characterize history traversal with
a real 100,000-object pool; they do not qualify a 2 TiB pool or 366 million rows.

## Restore characterization

The original Windows package restored the small C: corpus with PowerShell in
76.594 seconds at 167,194,624 bytes peak RSS. The optimized script restored the
same bytes in 30.297 seconds at 169,730,048 bytes: approximately 60% less elapsed
time in this comparison. This is a small warm-cache characterization, not a
linear forecast for a million files or 2 TiB.

On the same C: corpus, sequential Bash runs through WSL's Windows-filesystem
bridge took **439.502 seconds** with the original carried kit and **280.280
seconds** with the updated kit, about 36% less elapsed time. Peak sampled RSS was
17,129,472 and 17,059,840 bytes respectively. Both exited 0; all 3,008 restored
paths and SHA-256 digests match. Scratch was on the Linux filesystem and no
competing benchmark/build ran during either restore. This is bridge-backed
characterization, not native Linux disk throughput.

On Ubuntu WSL's Linux temporary filesystem, the same 3,008-file corpus restored
in **215.377 seconds** with the original package's kit and **148.830 seconds**
after refreshing to the updated kit: about **31% less elapsed time**. Peak RSS
was 17,027,072 and 17,100,800 bytes. Both restored path sets and SHA-256 inventories
match. These restores ran sequentially after corpus preparation. This separate
comparison avoids the Windows-filesystem bridge, while still being WSL evidence,
not bare-metal Linux or the full reference hardware profile.

The same original corpus on D: took 130.953 seconds to capture, 1.532 seconds on
the second unchanged run, 0.671 seconds to deep-check and 161.219 seconds to
restore with PowerShell. SSD/HDD differences and cache effects are substantial;
do not compare these timings as if they came from identical storage conditions.

## Compression and simultaneous tool memory

The Windows D: corpus contains one distinct 4 KiB file and one real, compressible
1 GiB file. Every output path and SHA-256 digest matches the source. Both captures
use the same deterministic bytes; these are isolated four-logical-CPU trials.

| Operation | Automatic workers: time / peak RSS | Two workers: time / peak RSS |
|---|---|---|
| Capture, engine plus compressor | 28.906 s / 966,242,304 bytes | 34.531 s / 409,047,040 bytes |
| Deep verify, engine plus extractor | 0.750 s / 551,882,752 bytes | 0.891 s / 48,218,112 bytes |
| PowerShell recovery including descendants | 16.312 s / 692,662,272 bytes | 15.266 s / 189,071,360 bytes |

The sampler observed two simultaneous processes for native operations and up to
three for PowerShell recovery. These are simultaneous RSS sums, not sums of the
engine and tool's separate peaks. Short-operation timing has sampling overhead;
the subsecond verification difference is not a throughput claim. The larger
capture tradeoff is roughly six additional seconds with substantially lower RSS.

A separate Linux RAM-filesystem run starts with **1,000,000 real source/object
pairs and adds one new 1 GiB file** with compression enabled. Automatic workers
crossed the guard at 1,973,497,856 bytes and were stopped; that run did not complete.
With two workers the complete backup passed in **43.043 seconds**, peaking at
**1,814,810,624 bytes across engine and compressor**. This exercises concurrent
index/tool memory at cardinality, but is not a 2 TiB, physical-disk or 2 GB-host
qualification. Recovery scripts still need their full million-path memory/time
qualification; a two-file 1 GiB restore does not establish that result.
The follow-up deep check, including latest and the preserved prior state,
completed with exit 0 in 45.712 seconds at 1,326,653,440 bytes peak process-tree
RSS. The backup report confirms one captured file and one million reused files.

## Excluded experiments

A private ext4 image backed by a file on Windows-mounted D: stalled in journal
flushes through the WSL bridge. Its initial guarded memory failure informed the
allocation work, but its subsequent elapsed times are discarded. No product
workaround was added for that test arrangement. After checking that Ubuntu had
no active containers or unrelated application jobs, the test environment was
restarted and the exact owned 32 GiB image was removed.

An early optimized Bash timing overlapped that image's formatting/I/O and is
excluded from speed comparisons. The final Bash comparison runs sequentially
with ordinary Linux scratch and no competing benchmark/build jobs. An interrupted
partial NTFS million-file fixture is also not counted as a completed benchmark.

## Reviews and checks

Opus 5.5 low and DeepSeek 4.1 Flash low reviewed the allocation changes in focused
rounds. Opus performance reviews 01–05 included these delivered sessions:

- `8533ab94-4fde-4a29-b600-472dccb145c3`: retain a final filesystem flush for
  ancestor-directory and metadata durability; adopted.
- `7908536a-6709-4547-b49e-bd856855a61b`: no Rust/Bash regression; suggestion to
  swallow ancestry access/I/O errors rejected because safe ancestry is unconfirmed.
- `74d1db17-398f-432c-a988-b79bd6a0024c`: no high/medium issue in borrowed rows,
  canonical comparison and shared serialization.
- `ec87cf81-8db7-4ad5-b3a8-c381fbccf6ad`: no high/medium issue in collision grouping
  or single-slot object indexing. Both index producers use the shared helper.
- `2e6a951e-966e-4a87-a4e0-23f67f475303`: accepted the compact row representation;
  identified copy-error classification. Fixed and exercised with source-read and
  target-write failures. Also adopted an empty-array expansion compatible with
  older Bash 4 and rebuilt the ordinary-directory set after excluding stale
  descendants. The existing folder-to-link fixture now covers a stale link target.

Focused Opus follow-up `0666fdfe-a04f-4dd9-890c-217880ee3d2a` found no confirmed
high issue. Its conditional concerns are resolved by existing code: `finding`
preserves exit 4 over content findings; the final target `sync -f` is present;
native findings set the report code. Change counters already preceded publication
before this work. No new flags or alternate failure protocol were added.

DeepSeek session `ses_e4eeefdafffe67s4V4HuwDs9NJ` delivered no high/medium Rust
regression in the focused comparison/borrowing changes. Its initial tool-call text
was not counted as a review; the explicit follow-up verdict was. Review scope and
execution evidence remain separate.

The final DeepSeek round, `ses_e4eb9ee06ffeE4Y12euJdqphwX`, exhausted its 32,000
reasoning-token response budget without a verdict. It is not counted as a review;
the completed Opus reviews were used as the owner-authorized fallback.

Opus harness review `b9bafdaa-308b-4f0d-89f1-2b4c6a98a0f3` led to explicit refusal
when Windows recovery cannot run, rejection of zero-sample measurements, checks
of actual unchanged-run counters and history counts, distinct compressible file
payloads, and per-process cleanup error reporting. Sampling now waits on process
completion between polls and excludes cleanup from elapsed time. Earlier tables
used the 50 ms sleep-based sampler; allow that quantization/cleanup overhead when
comparing short operations. These changes do not revise their recorded values.
The suggestion to regenerate history members after each block was not adopted:
the fixture already publishes complete definitions and kits, and its unchanged
operations preserve them. The optional run timestamp is not a recovery definition.
Sampler regression tests pass and are included in the native CI workflow; that
workflow has not been executed remotely.

Final Windows native tests: 43 passed. Final Linux native tests: 46 passed.
These suites were rerun after the two-worker tool cap. Opus review
`480200e4-3335-469d-a7c9-b362ef9f8b6a` found no high/medium regression in the
argument changes. The native Bash wrapper owns its extraction path; its carried
legacy helper does not perform that extraction. Low-power host deadline margins
remain part of hardware qualification. Actual installed versions are 7-Zip
24.09 on Windows and 23.01 on Linux; the review prompt's Linux version was
incorrectly described as 24.09, so executed interoperability is the evidence.
Clippy with warnings denied, formatting, PowerShell lint and ShellCheck pass.
All 154 existing Bash tests also passed after the shared uppercase helper change.
The existing PowerShell runtime is unchanged; its prior full-suite result remains
recorded in the earlier validation.

## Packaged preview and repository checks

Fresh release packages, built without `test-hooks`, are on D::

- `D:/FileBackupBuild/packages/filebackup-native-windows-x64-performance-20261106.zip`
- `D:/FileBackupBuild/packages/filebackup-native-linux-x64-performance-20261106.zip`

All 204 Windows and 336 Linux packaged-file checksums passed, as did ZIP integrity
and archive/file byte comparison. Both packaged executables report 0.1.0. No
package or image was published. The local image
`filebackup-native:performance-20261106` passed compressed backup and independent
Bash recovery offline as UID 65532, with a read-only image/source, dropped
capabilities and no-new-privileges. C: had 33.4 GiB free after the builds; large
build caches, archives and retained disk corpora remain on D:. Temporary RAM
mounts are gone. No unrelated user files or caches were removed.

Generated architecture/interface maps are current. Document checking covers 460
documents and 765 intra-repository links with zero broken links (29 historical
orphan warnings). Strict trace still exits 1 for the same 18 approved-SR form
findings; orphan, integrity and interface findings are zero. These findings were
not hidden by changing approved normative text. General hooks remain disabled.

## Reproduction and outstanding qualification

The subsequent [Opus memory review](memory-review-2026-11-06.md) identifies
remaining allocation costs and a staged optimization sequence. Its projections
are unmeasured. It also identifies early compression placement and missing
timed-checkpoint coverage in the short combined run; the existing measurements
remain valid for their executed order, not worst-case concurrent memory bounds.

Install `scripts/requirements-performance.txt` into a development environment.
Set Cargo caches/targets and scratch to a drive with sufficient capacity, then:

```text
cargo build --locked --release --manifest-path rust/Cargo.toml --examples --bin filebackup
python scripts/performance_native.py --root ABSOLUTE_FRESH_ROOT --binary RELEASE_BINARY
cardinality_fixture ABSOLUTE_FRESH_ROOT 100000
python scripts/measure_native.py --output FRESH_RESULT.json --label unchanged --cores 4 -- RELEASE_BINARY backup --config FIXTURE/config.json --no-mail
python scripts/performance_history.py --root FIXTURE --binary RELEASE_BINARY --with-check
python scripts/performance_native.py --root ANOTHER_FRESH_ROOT --binary RELEASE_BINARY --files 1 --large-mib 1024 --large-file-mib 1024 --compressible --compress
```

The history runner requires its designated private cardinality fixture and empty
history. It creates hard-linked historical definitions over the same valid pool,
warms each 182/364-state case, measures three trials, and optionally checks all
365 histories plus latest. It does not create 365 different content generations.

Still open: the combined full 1M-file/2 TiB/365-state reference topology, repeated
cold/warm measurements, required restore/check budgets on designated hardware,
blocked source-filesystem I/O deadlines, and the remaining host/hardware matrix.
No 2 TiB corpus fits this machine's scratch capacity. macOS/APFS is explicitly
deferred by the owner, not passed. Physical power loss, network disconnects,
live credentials/TLS relays and desktop UI also remain unqualified. Partial
measurements do not close these requirements or justify a new spill subsystem.

Raw local JSON, stdout, stderr and review records remain in the ignored
`.artifacts/native-transition/` directory and named private D: fixture folders.
