# Native implementation: initial design breakdown

Draft for owner review, 2026-11-05, against the 121 accepted SRs at `9e03be4`.
This package changes documentation and proposed allocation only. No Rust engine,
restore behavior, approved upstream record, approval snapshot or hook is changed.

**The current design already accommodates most of the required behavior.** Keep
the single-store layout, bounded capture loop, shared content pool, prior-state
publication, rehoming prune and independent recovery kits. Port their contracts;
change a mechanism only where an accepted obligation or measured limitation
requires it. Rust itself is not a reason to change the store format.

## What actually needs work

| Area | Existing foundation | Native work or remaining evidence |
|---|---|---|
| Capture and deduplication | Hash copied bytes, reuse by hash/length, preserve failed rows | Port implementation and prove parity on the declared host matrix |
| Store and publication | Sharded latest, flat history, prior snapshot before checkpoints, superseded moves last | Port rename/flush/lock primitives; exercise directory/link metadata failures and timestamp collisions |
| Retention and repair | Dependency rehoming, resumable removal, verified repair and quarantine | Reconcile accepted cutoff semantics and read-only inspection; retain stronger preservation where useful |
| Recovery | Carried PowerShell/bash scripts, per-file verification and pool fallback | Extend their common metadata contract and test each supported platform/tool combination |
| Folder links | Directory sidecar and directory restore phase | Add entry kind and root-relative destination; restore relative links after ordinary content |
| Configuration and operation | Versioned JSON, actions, per-set results, logs | Portable root identity, credentials, dependencies, progress reporting and native/container packaging |
| Scale | One manifest at a time and name-based object index | Measure within 2 GB; add bounded spilling only if required; pin logical versus physical corpus accounting |

An ordinary directory is created at its recorded path. A folder link additionally
needs a destination, conversion to a path relative to its restored parent, and a
host capability check. The existing directory machinery is the right extension
point. Those additions do not require another object pool or a new database-backed
recovery format.

## Review order

1. Read the [contracts and targeted decisions](contracts.md), especially link
   records, interrupted metadata publication, kit refresh and scale accounting.
2. Read the [critical flows](flows.md), which retain the existing run ordering.
3. Use the [allocation map](allocation.md) to review LLR-151..190 and TC-261..301
   in the [LLR registry](../../requirements/low-level-requirements.toml) and
   [test registry](../../test/test-cases.toml).
4. Read the [owner's scoped correction and review disposition](owner-prev-review.md).
   The earlier [Gemini review](gemini-review.md) is historical: its marker-based
   resolution is superseded by preserved previous definitions and explicit
   last-known-checkpoint semantics. It does not validate the revised design.

All 121 accepted SRs have a proposed design allocation and verification case.
These 40 LLRs and 41 cases are an **initial breakdown**, not evidence that the
requirements have been implemented or fully decomposed into coding tasks. Broad
cases will be split into concrete fixtures/assertions as their work package is
prepared. Planned symbols identify responsibilities, not existing functions.

## Decisions that need evidence before implementation is frozen

- **Link metadata revision:** retain the nine-column manifest and extend the
  directory sidecar. Pin header/version admission and mandatory metadata failure
  behavior with both script readers before enabling the writer.
- **Publication:** retain the bounded loop and preserve previous definitions as
  `.prev` until success, without overwriting them on later runs. TC-275/282 cover
  partial copies, repeated interruptions and explicit record selection. Current
  valid checkpoints remain usable; missing/conflicting required metadata still
  produces a diagnostic. Folder/link-only changes count when retaining history.
- **Kit refresh:** current staged per-file writes are reusable; prove a usable
  prior or new kit survives every interruption. If mixed files are unsafe, add
  the smallest kit-local validation/commit mechanism needed.
- **Filesystem boundaries:** prototype path identity, no-follow target writes,
  link capabilities, OS-lifetime locks and durability on Windows/Linux/macOS.
  Portable scripts must not quietly claim native-handle race guarantees they
  cannot provide. Any necessary scope change goes back to the accepted SRs.
- **Scale:** count expanded logical output, shared unique content and historical
  rows separately. The proposed reference corpus below needs review; it is not
  permission to weaken an accepted time/resource target.

## Implementation order after design review

| Package | Outcome and exit evidence |
|---|---|
| N1: contract fixtures | Name/hash/CSV/path golden vectors; both script readers agree on existing and proposed link records; explicit supported-version matrix |
| N2: platform primitives | Locks, volume/capacity, staged publication, path identity and containment exercised on each supported host/filesystem |
| N3: bounded backup port | Existing ordered loop reproduced; previous definitions survive interruptions; main walk captures/classifies links; folder/link changes retain history; retries/results match approved policy |
| N4: maintenance port | Inventory/check, retention, repair, kit refresh and view behavior reconciled against legacy tests and protected dependencies |
| N5: portable recovery | Link recreation and metadata outcomes in both carried scripts; clean-host offline restore independent of native engine |
| N6: delivery and operations | Native artifacts, container actions, credentials, progress and shipped guidance tested on declared support matrix |
| N7: scale and release evidence | Full reference corpus, simultaneous memory, time budgets, failure tests and license/support records; no unsupported platform claims |

N1/N2 prototypes settle uncertainty; they do not authorize broad runtime changes
before this design review. Existing code/test reconciliation occurs within each
package before implementation attachment. Preserve old rationale and results;
retire a trace only with an explicit disposition. A shared SR ID is not proof
that an old assertion verifies its revised meaning.

Include a small recovery throughput/memory feasibility probe in N1/N2 for each
script route and the proposed storage topology. N7 is full acceptance evidence;
it is not the first opportunity to discover an unsuitable recovery strategy.

The modern interface-carrier migration remains separate: IF-001's existing
HomeHub agreement stays in place. The contracts here are draft internal/product
contracts, not invented approved IF records. Hooks remain disabled and this
package does not close a gate.

## Validation and outstanding trace work

The scope check confirms all four accepted upstream registries are unchanged,
all 87 legacy LLRs and 240 legacy cases are retained, and new rows are Drafted
with no invented evidence. Planned references reach all 121 accepted SRs.

The integrity check reports zero findings. Full strict/schema checking remains
red: 131 orphan findings, 274 schema findings, one inherited interface finding,
18 requirement-form findings and four acceptance-criteria advisories. In
particular, `Automated=Yes` on a new case states intended automation but there
is no implemented test binding yet; these evidence findings are deliberately
visible. Checker verification-method counts are not passed-test counts.

Document navigation and whitespace are checked separately. No product suite or
platform benchmark was run for this documentation-only change. Legacy semantic
reconciliation, concrete interface carrier adoption, implementation bindings,
executed verification and owner approval remain subsequent work.
