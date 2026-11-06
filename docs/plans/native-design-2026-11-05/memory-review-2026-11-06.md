# Opus review of remaining native memory costs

Date: 2026-11-06 (America/Chicago). Reviewed source: `1a1f2f2`.

The owner requested another Opus perspective on optimization and explicitly
authorized sharing the seven-file source/measurement bundle. Claude Opus 5.5,
low effort, returned session `0ef5cb1d-a65a-4a52-b4fc-d8d442cfdb0a` through the
Claude CLI. Tools were disabled. This was static review, not execution or proof
of a memory bound. At the time of this review, runtime code and requirement statuses were unchanged.
The subsequent [implementation and measurements](memory-optimization-2026-11-06.md)
record the adopted changes and correct the walk-order assessment below.

The bundle included `rust/src/{engine,format,store,maintenance,tools}.rs`,
`scripts/measure_native.py` and [performance-validation.md](performance-validation.md).
All seven hashes matched the checkout after review. Raw input, hashes and JSON
response are in ignored `.artifacts/native-transition/memory-opus-review-07*`.
The first restricted-environment call failed DNS resolution and is not counted
as a completed review. The approved network-enabled retry delivered the verdict.

## What the existing measurements mean

The unchanged million-file run peaked at **1,680,551,936 bytes** with exactly one
observed process. Deep verification peaked at **1,183,100,928 bytes**. The Windows
100,000-file run used **168,849,408 bytes**. About 1.68 KB per file in the unchanged
runs is consistent with per-file metadata cost; it does not establish a leak or
prove the absence of one. The fixture's eight-byte payloads do not account for
the RSS. Kernel memory backing its RAM filesystem is outside application RSS.

Opus identified several simultaneous representations: prior manifest rows,
object index entries, the source walk, working-row lookup, portable-path lookup,
seen-path set and retry-queue capacity. Strings have allocation and container
overhead beyond their text. Later phases have different costs: unchanged rows
are cloned into final rows while prior rows still exist; verification owns a
separate full-path verdict cache; publication builds a whole CSV buffer.

These costs explain why the current implementation can exceed 1 GB. Opus's
per-structure sizes and phase attribution were estimates, not a heap profile.
Do not add estimates from nonconcurrent phases or claim their sum as a measured
saving. Freed allocations also need not immediately reduce resident memory.

## Recommendations and disposition

| Opportunity | Local assessment and next action |
|---|---|
| Reduce capture bookkeeping | First implementation candidate after phase measurement. Build `seen` only for a complete walk, after capture-only indexes are released. Use sequential first attempts and a heap only for retries; explicitly release its capacity. Reconstruct source paths from relative paths through one helper, preserving external-link aliases and Windows path behavior. These changes need no store-format migration. |
| Compact object/index identity | Real duplication exists in `Object.path`, `state`, `name`, `key` and the map key. Start with shared state paths and borrowed verification-cache paths where lifetimes permit. Opus's binary hash, state-id and per-object verdict representation are larger follow-ups, not one mandatory rewrite. Preserve separate unchecked/damaged verdicts and alternate supply. |
| Avoid finalization row clones | Worth doing if this becomes the peak. Keep prior rows borrowed until comparison/accounting completes, cloning only rows whose output fields change. Generalize shared consumers rather than adding a parallel publication path. Independently, release final rows after building `required`, before the second object index; no later code reads them. |
| Stream canonical CSV publication | Useful for mixed runs whose checkpoints overlap large capture indexes. Reuse one writer and the existing atomic publication primitive; keep sorting, temporary-file sync, rename and directory sync semantics. No durability shortcut. |
| Compact every `FileRow` field | Defer until smaller changes are measured. Typed flags/hashes could save space, but broad representation changes require careful preservation of CSV spelling, ordering and accepted input behavior. |

Opus considers an engine-only unchanged-run peak below **1,000,000,000 bytes**
plausible after multiple improvements. That is an optimization goal for this
corpus, not a new accepted requirement or a measured result. Its lower-memory
projections for verification and engine-plus-compression are also unmeasured.
Longer paths and runs changing many files can have different peaks.

## Concrete measurement gaps to close

1. Attribute memory at the existing phase boundaries in a diagnostic build,
   including before/after capture-index release, final-row construction and the
   second object index. Start with 100,000 files; confirm promising changes at
   one million. Record allocator/environment and distinguish live allocations
   from RSS. Release measurements must still omit `test-hooks`.
2. Check compression late in the actual capture order. **Corrected during
   implementation:** the walker sorts its completed file list before capture.
   The existing `new-gib.txt` therefore already follows the million `d...` paths,
   despite being encountered during the root scan. Opus's early-file concern
   and the initial local assessment overlooked this sort; that concern is
   withdrawn. Do not assert a 2 GB violation by adding independent peaks.
3. Exercise a mixed run with a timed manifest checkpoint on D: HDD storage.
   The 43-second combined run does not exercise the 60-second checkpoint budget.
   Opus suggested forcing a checkpoint during compression, but compression is
   synchronous: the checkpoint branch runs after capture returns, and reusable
   files skip it. Measure late compression and the following checkpoint as
   separate phases, not as concurrent CSV and compressor allocations. A long
   unchanged run alone is insufficient to exercise that branch.
4. Apply the small bookkeeping changes individually, compare counters/output
   and memory, and re-run relevant retry, interruption, collision and alias
   fixtures. Then decide whether broader index/row changes are still warranted.

No new database, spill subsystem, allocator replacement or relaxed durability
contract is justified by this review. Full HDD/resource qualification remains
open under the [owner-corrected reference](owner-hdd-reference.md).
