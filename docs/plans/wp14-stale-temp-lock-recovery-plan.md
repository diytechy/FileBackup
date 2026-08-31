# WP14 — An interrupted run must not be a permanent interrupt

Plan owner: driver. Raised by the Owner 2026-08-31 from
[defect-review-2026-08-31-stale-temp-lock.md](../defect-review-2026-08-31-stale-temp-lock.md)
(D-1). The Owner's position, quoted: *"an interrupted run generally should not be a
permanent interrupt."*

**Scope, as ruled:** the review's **B-lite + A**, plus a **reduced E**. Options C
(signal handling) and D (documentation-only) are out of scope; D-2 is withdrawn as a
false finding (review §4) and what remains of D is two one-line doc fixes carried here
as N-1/N-2.

**Status: PROPOSED — awaiting human approval.** Nothing in this plan is implemented.
The active gate is **G3** and this touches the data-integrity surface, so per
[process.md](../process.md) §6 it needs an independent reviewer before the gate and the
Owner's approval before the first code commit. The decision dial is **HIGH**.

---

## 0. The one-paragraph version

The staging lock is a bare directory whose only release paths are `catch` blocks, so a
run killed from outside leaves it forever. We give the lock an **owner record** written
microseconds after the create — the same thing `Remove-BackupSnapshot` already does with
`PRUNE.inprogress` — heartbeat it from a .NET timer, and let a later run **reclaim** a
lock whose owner is provably dead *and* which provably holds nothing. A `Temp` holding
any data file is refused exactly as it is today, and nothing is ever deleted that has
not first been moved aside. The refusal messages stop hedging, because for the first
time the guard can tell dead from live.

---

## 1. What must remain true

Restated from review §6, because it is the constraint the whole design is shaped around.
F1/R4 was **reproduced, not theorised**: a README that once said *"remove the leftover
Temp and re-run"* permanently destroyed the only physical copy of snapshot-demanded
bytes, and snapshot restore went `exit 0` → `exit 1 ContentMissing` forever after.

| # | Invariant | How this plan holds it |
|---|---|---|
| **I-1** | **No non-empty `Temp` is ever deleted**, by code or by documentation. | The reclaim branch is unreachable when a data file is present, and the move-aside is re-checked *after* the move before anything is removed (§4.4). |
| **I-2** | Creation-as-lock stays the atomic primitive; the R3 TOCTOU stays closed. | `New-Item` without `-Force` remains the only way the lock is taken. Reclaim is `Directory.Move` + a fresh `New-Item` — two atomic steps, never a delete-then-create. |
| **I-3** | Prune and backup stay mutually exclusive (SR-046). | A `PRUNE.inprogress` in `Temp` is never reclaimable by the backup path. |
| **I-4** | `Common` never depends on `Engine` (AGENTS.md §3). | The new marker read/write helpers live in **Common** and are pure of engine concepts; `Engine` calls them. |
| **I-5** | Nothing acquires a new exit code. | IF-001 is a cross-project contract; HomeHub owns alarm policy. We emit facts into the log, we do not renumber exits (§6). |

---

## 2. Design

### 2.1 The owner record

At lock take, immediately after the `New-Item` succeeds, write **`RUN.inprogress`**
inside `Temp`. Name and placement mirror `PRUNE.inprogress` deliberately, so the two
lock-holders are legible to the same reader.

```json
{
  "SchemaVersion": 1,
  "Kind": "backup",
  "SetName": "library",
  "Host": "homehub",
  "ContainerId": "…",
  "BootId": "…",
  "Pid": 1,
  "StartedUtc": "2026-08-30T14:34:02Z",
  "HeartbeatIntervalSeconds": 60,
  "StaleAfterSeconds": 1800
}
```

**The content is written once and never rewritten.** Two reasons, both load-bearing:

1. A reader can never observe a torn write.
2. It forces liveness to be carried by something else — the file's **mtime** — which is
   the only signal that survives a garbage, truncated, or future-schema payload.

`StaleAfterSeconds` is in the *record*, not in the reader, so the reader honours the
threshold **the writer committed to**. A future version that beats faster or slower
cannot be misjudged by an older reader.

### 2.2 Liveness is mtime, not PID

Review §5 is right that PID is useless here: the writer is a container that may share
neither PID namespace nor host with the reader, and the store is exFAT. So identity in
the record is **diagnostic only** — it tells a human who wedged it. The *decision* is:

> the owner is alive **iff** `RUN.inprogress`'s mtime is within `StaleAfterSeconds`.

- **Heartbeat** = `File.SetLastWriteTimeUtc` on the marker, every 60 s.
- **Threshold** = 1800 s (30 min) — a 30× margin. Review §5 worries that a threshold is
  a tunable that can be set too short and reintroduce the stomp risk; the answer is that
  the asymmetry is total. Too long costs **a slower auto-recovery**. Too short costs
  **stomping a live run**. So it is set long, and it is not exposed as a knob.
- **Clock skew:** a marker whose mtime is in the **future** is treated as *fresh*, never
  as stale. exFAT's 2 s mtime granularity is irrelevant at a 1800 s threshold.

**The heartbeat must be a `System.Timers.Timer`, not an inline call.** An inline beat
would fail during exactly the operations that need it most — hashing one 100 GB file
blocks the pipeline for minutes. The timer callback runs on a .NET threadpool thread and
touches a timestamp; it needs no runspace, so it is safe to fire from outside the
PowerShell pipeline. This is the single most important implementation detail in the
plan.

### 2.3 The guard becomes three-way

Each branch is decidable from the disk alone:

| `Temp` contains | verdict | action |
|---|---|---|
| nothing at all | died inside the create→marker window, or predates WP14 | **reclaim** |
| `RUN.inprogress` only, mtime stale | owner provably dead, nothing of value written | **reclaim** |
| `RUN.inprogress` only, mtime fresh | **a run is genuinely active** | **refuse** — and say so truthfully |
| `PRUNE.inprogress` (any age) | prune holds it; out of scope (§7) | **refuse** |
| **any other file or subdirectory** | may hold the only physical copy | **refuse** — unchanged from today |

An unparseable or empty `RUN.inprogress` falls back to mtime alone: stale → reclaim,
fresh → refuse. It is never an error.

### 2.4 Reclaim is a move, never a delete

```
1. New-Item Temp                      → success? done. (unchanged fast path)
2. classify Temp (§2.3)               → not reclaimable? refuse, with the branch's message.
3. Directory.Move Temp → Temp.stale-<utc>-<8 hex>
                                      → failed? refuse. Do NOT retry in a loop.
4. New-Item Temp                      → failed? refuse; leave the aside folder in place.
5. RE-ENUMERATE the aside folder:
      empty, or marker-only          → delete it, log what was removed.
      anything else                  → KEEP IT. Log loudly, print the README recovery.
```

**Step 5 is not belt-and-braces, it is the design's safety proof.** Between the
classification at step 2 and the move at step 3, a frozen-then-resumed owner could
write data files. It is a narrow window and a stale owner is unlikely to wake, but the
cost of being wrong is F1/R4 again. So we never rely on the classification surviving:
the move-aside is itself the README's prescribed safe action, and we only ever delete
something we have re-proved empty *after* it can no longer be written to under that
name. A resurrected owner keeps writing into the aside folder, its bytes preserved, and
fails later at `Complete-ChangeFolder` — noisy, and non-destructive.

The `Directory.Move` at step 3 also gives us the race guarantee for free: two
simultaneous reclaimers cannot both move the same source directory, and the loser then
fails step 3 and refuses. `New-Item` at step 4 is a second, independent atomic gate.

---

## 3. Requirements deltas

Registry rows land **before** the code, in their own commit, with
`python scripts/trace.py --strict` green.

| id | change |
|---|---|
| **SR-017** | *Amended.* Keeps the refusal as the default. Adds: the refusal is conditioned on the staging folder holding content or a live owner; a folder proved to hold neither is reclaimed non-destructively. Rationale line records WP14 and the HomeHub 2026-08-31 wedge. |
| **SR-075** *(new)* | **Staging lock ownership and stale reclaim.** The owner record, its write-once content, mtime-as-heartbeat, the threshold semantics, the three-way classification, and the move-then-verify-then-delete reclaim protocol. Verification: `Test`. Permutations cell (§5). |
| **LLR-017** | *Amended.* `Initialize-StagingFolder` gains the classification and reclaim; `CodeSymbol` extended. |
| **LLR-080** *(new)* | Marker read/write/heartbeat helpers in **Common** (I-4) + the reclaim protocol's exact step order from §2.4, including step 5. |
| **SR-046 / LLR-046** | *Untouched.* Prune's `PRUNE.inprogress` and its staging-busy refusal are unchanged; the backup path simply learns to recognise the marker and refuse on it (I-3). |

---

## 4. Work parts

### Part A — Common: the marker (LLR-080)

New helpers, each with comment-based help as the first thing in the body and an
`# Implements:` back-link:

- `Write-StagingOwnerRecord` — write-once payload; must be called only after a
  successful `New-Item`.
- `Read-StagingOwnerRecord` — returns `{ Parsed, Record, LastWriteUtc, AgeSeconds,
  IsStale }`. **Never throws** on bad content; `Parsed=$false` and the mtime fields
  still populated is a normal, expected return.
- `Get-StagingLockState` — the §2.3 classifier. **Pure of I/O decisions**: it takes the
  enumeration result and the record and returns one of
  `Empty | OwnerStale | OwnerLive | PruneHeld | HoldsContent`. Unit-testable with no
  filesystem (pure core / I/O shell, per CLAUDE.md).
- `Start-StagingHeartbeat` / `Stop-StagingHeartbeat` — the `System.Timers.Timer` pair.
  Stop must be idempotent and must not throw from a finalizer path.

### Part B — Engine: heartbeat the lock (SR-075)

`Initialize-StagingFolder` writes the record on the success path and returns the
heartbeat handle alongside the folder path. `Invoke-BackupSet` stops the heartbeat when
the set ends — including on every existing `catch` cleanup, which must stop the beat
before removing the folder.

*Ordering matters:* the record is written **after** `New-Item` returns, never before,
or the write itself becomes the race.

### Part C — Engine: reclaim (SR-017 amended, §2.4)

The classification and the five-step protocol, in `Initialize-StagingFolder`. The
existing `New-Item` fast path is untouched — the new code is reachable **only** from the
current `catch`, so a healthy run's instruction path does not change at all.

### Part D — The reduced E: make the facts legible

The review's E imagined a "feed/health surface". **FileBackup has none, and should not
grow one:** IF-001 gives HomeHub the exit status and the log, and says HomeHub owns
NagLight translation. So E reduces to emitting facts HomeHub can act on:

- **Distinct, greppable branch tokens** in the log — `[SR-075/reclaimed]`,
  `[SR-075/owner-live]`, `[SR-075/content-refused]`, `[SR-075/prune-held]`. This is the
  bit that turns *"a one-second clean-looking failure"* into something a wrapper can
  alarm on, and it is the half of E that would actually have cut 18 hours to minutes.
- **The refusal stops hedging.** *"may have failed or still be running"* becomes, per
  branch, either "a run started by <host>/<pid> at <time> is alive (last heartbeat Ns
  ago)" or "held since <time> (<duration> ago) by a run that is gone; it holds N
  file(s), so it is being kept".
- **N-1:** quote the README heading verbatim in the guard message.
- **N-2:** extend `README.md:947-957` — auto-reclaim, what
  `Temp.stale-*` folders are, and that they are safe to inspect and never auto-deleted
  when non-empty. The existing four-step procedure stays exactly as it is; it is still
  the operator's path for the content branch.

---

## 5. Test cases (TC-185 onward)

Permutations cell for `python scripts/gen_cases.py`:

```
state=set{empty,marker-only-stale,marker-only-fresh,marker-unparseable-stale,marker-unparseable-fresh,marker-plus-data,data-no-marker,prune-marker}; platform=set{windows,container}
```

Beyond the generated matrix, these are named and must exist:

| # | Case | Why it is not optional |
|---|---|---|
| 1 | Marker written and heartbeat advances mtime **while a long blocking operation runs** | Proves the timer, not the pipeline, drives the beat (§2.2). Inline beats pass a naive test and fail in production. |
| 2 | Stale marker-only → reclaimed, run completes, aside folder gone, `[SR-075/reclaimed]` logged | The observed defect, end to end. |
| 3 | Fresh marker-only → refused, no move, tree byte-identical | The stomp case A alone could not survive. |
| 4 | `marker + data file`, marker stale → **refused, nothing moved, nothing deleted, every byte hash-identical before and after** | I-1. Assert hashes, not just presence. |
| 5 | **Resurrection:** data files appear in the folder between classify and move (test hook) → aside folder is **kept**, deletion skipped, recovery printed | §2.4 step 5. Without this the design is only probably safe. |
| 6 | `PRUNE.inprogress` present → refused | I-3 / SR-046 regression. |
| 7 | Two reclaimers racing the same stale lock → exactly one proceeds, one refuses, one `Temp` exists | I-2. |
| 8 | Empty `Temp` with no marker (a pre-WP14 store) → reclaimed | Upgrade path; this is literally the state on the hub right now. |
| 9 | Future-dated marker mtime → treated as fresh, refused | Clock-skew conservatism (§2.2). |
| 10 | G8 real-volume + **exFAT**: reclaim end to end | Resolves the review's §7 open item on `Directory.Move` semantics. |
| 11 | Container acceptance: reclaim inside `filebackup:local`, boot id read from `/proc` | The deployment the defect was found in. |
| 12 | Existing TC-073 and the four `catch` cleanups still green | The heartbeat-stop added to each cleanup is the regression risk in Part B. |

**Negative controls required** for 1, 5 and 7 — each must be shown to fail with the fix
removed. WP13's T4 is the precedent: two tests that could not fail shipped as green.

---

## 6. Open questions to close during implementation

Three carried from review §7, plus one this plan adds. None blocks approval; each has a
predetermined safe fallback, so no answer can make the design unsafe — only smaller.

| # | Question | Fallback if the answer is bad |
|---|---|---|
| Q1 | Is `Directory.Move` of a directory within the same parent reliable on **exFAT**? (TC-190) | If not: skip the move entirely and **refuse**. Never fall back to delete. Auto-recovery is lost on exFAT only; today's behaviour is what remains. |
| Q2 | Does any healthy path leave `Temp` marker-less for a prolonged period? | Should be impossible after Part B; TC-185 proves it. If one exists, it is a bug in Part B, not a reason to widen the reclaim. |
| Q3 | Clock source when the store is on a **UNC/remote** volume — the writer touches the file, but the reader compares against its own clock. | Future-mtime-is-fresh (§2.2) already covers skew in the dangerous direction. Skew the other way only slows recovery. |
| Q4 | *(new)* Does `System.Timers.Timer` keep firing while the pipeline blocks in native 7-Zip or the hashing library? | Verified by TC-185. If it does not, the fallback is a dedicated `Thread` with `IsBackground=$true` doing the same one-line touch — **not** an inline beat. |

---

## 7. Deliberately deferred, with reasons

| item | why not now |
|---|---|
| **Prune gets a heartbeat too** | `Remove-BackupSnapshot` has the identical defect — a killed prune wedges `Temp` permanently, blocking backups. It is deferred because prune is human-invoked and minutes-long, not scheduled and hours-long, so its exposure is a fraction of the backup path's. **It should be WP15, and this row exists so it is not forgotten.** |
| **A guarded `finally` replacing the four `catch` cleanups** | This is half of the review's option C, which the Owner scoped out. It is a genuine simplification and strictly safer than four unguarded `Remove-Item -Recurse -Force` calls, but it edits the data-safety path for tidiness rather than for the defect. Raise separately. |
| **`SIGTERM` trapping** (`PosixSignalRegistration`) | The rest of option C. Once reclaim lands it buys only the graceful path, which reclaim already covers, and it cannot touch `SIGKILL`/OOM/power loss. Review §7 flags two untested behaviours needed even to size it. Poor trade. |
| **A new exit code for "wedged"** | IF-001 is a cross-project contract and HomeHub owns alarm policy (I-5). The branch tokens in Part D give HomeHub what it needs without a contract change. |

---

## 8. Sequencing

Each row is one small green commit (CLAUDE.md commit cadence).

| # | Commit | Gate on |
|---|---|---|
| 1 | Defect review committed as found, then corrected; this plan | *(done — the commit carrying this file)* |
| 2 | Registry deltas (§3) | `python scripts/trace.py --strict` green, orphans 0 |
| 3 | Part A — Common helpers + their unit tests | `pwsh scripts/check.ps1 -Tier Smoke` |
| 4 | Part B — marker + heartbeat, TC-185, TC-196 | Smoke; TC-073 still green |
| 5 | Part C — reclaim, TC-186…TC-192 incl. negative controls | `-Tier Full` |
| 6 | Part D — messages, tokens, N-1, N-2 | Smoke |
| 7 | G8 exFAT + container acceptance evidence (TC-194, TC-195); status.md entry | `-Tier Release`, real output pasted |

**Independent review** (process.md §6) after commit 5, before the gate: this is hashing-
adjacent, data-integrity surface, and the last two independent reviews on this repo each
found P0s that in-house testing had missed.

---

## 9. Unblocking the hub — separate from all of the above

The stale `Temp` is still in place at `/mnt/backup-drive/library-changes/Temp`,
deliberately preserved as evidence, and the whole-library backup is blocked until it
moves. It does **not** need to wait for WP14:

```
mv /mnt/backup-drive/library-changes/Temp \
   /mnt/backup-drive/library-changes/Temp.stale-20260830
```

Review §1 establishes three independent proofs that it holds nothing — 0 files, 0
`Snapshot_*` trees, and a `/backup` that no run has ever populated. Steps 3 and 4 of the
README procedure (verify, then reintroduce data files) have nothing to act on for the
same reason: there is no snapshot to test-restore and no data file in the folder. The
move alone is sufficient, and it is reversible.

Keeping the aside folder until WP14 lands costs nothing and preserves the evidence.
