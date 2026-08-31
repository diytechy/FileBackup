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

**Revised 2026-08-31 after a two-reviewer plan-stage review** (driver self-review +
an independent OpenAI Codex CLI pass over the repo). The composite found five P0-class
design gaps in the first draft; every accepted finding is folded into the sections
below and the round is recorded with dispositions in §10. This plan-stage review does
**not** replace the pre-gate independent review required at §8 commit 5.

---

## 0. The one-paragraph version

The staging lock is a bare directory whose only release paths are `catch` blocks, so a
run killed from outside leaves it forever. We give the lock an **owner record** written
microseconds after the create — the same thing `Remove-BackupSnapshot` already does with
`PRUNE.inprogress` — heartbeat it from a compiled .NET timer callback, and let a later
run **reclaim** a lock whose owner is provably dead — stale by age **and confirmed by a
second sample** — *and* which provably holds nothing. A `Temp` holding any data file is
refused exactly as it is today, nothing is ever deleted that has not first been moved
aside, and no delete in the reclaim path is ever recursive. The refusal messages stop
hedging, because for the first time the guard can tell dead from live.

---

## 1. What must remain true

Restated from review §6, because it is the constraint the whole design is shaped around.
F1/R4 was **reproduced, not theorised**: a README that once said *"remove the leftover
Temp and re-run"* permanently destroyed the only physical copy of snapshot-demanded
bytes, and snapshot restore went `exit 0` → `exit 1 ContentMissing` forever after.

| # | Invariant | How this plan holds it |
|---|---|---|
| **I-1** | **No `Temp` holding anything but its own recognized `RUN.inprogress` marker leaf is ever deleted**, by code or by documentation — and the deletes that do happen are the exact marker leaf by name plus a **non-recursive** directory delete that *fails* if anything else has appeared (§2.4). `Remove-Item -Recurse` never appears in the reclaim path. | The reclaim branch is unreachable when a data file is present, the move-aside is re-checked *after* the move, and the final delete is structurally incapable of taking a data file with it. |
| **I-2** | Creation-as-lock stays the atomic primitive; the R3 TOCTOU stays closed. | `New-Item` without `-Force` remains the only way the lock is taken. Reclaim is `Directory.Move` + a fresh `New-Item` — two atomic steps, never a delete-then-create. The create→marker window is closed from both sides: the marker write is **exclusive-create and aborts the run if it loses** (§2.1), and a markerless `Temp` is reclaimable only when the directory itself is stale by age (§2.3). |
| **I-3** | Prune and backup stay mutually exclusive (SR-046). | A `PRUNE.inprogress` in `Temp` is never reclaimable by the backup path. |
| **I-4** | `Common` never depends on `Engine` (AGENTS.md §3) — **and stays untouched.** | The marker/heartbeat/classifier helpers live in **Engine**, not Common: Common is bundled into every restore kit, and any behavioral change there forces both `KitRevision` markers to bump (AGENTS.md). Staging-lock ownership is an engine concept with no restore-side meaning, so nothing kit-bundled changes. *(The first draft put these in Common citing I-4; that misread the invariant — it forbids a dependency direction, it does not demand engine concepts migrate down.)* |
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
  "RunId": "b3f1…-guid",
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

**`RunId` is a fresh GUID per acquisition** — it is the fencing token every later
identity check compares against (§2.2, §2.5). The rest of the identity fields are
diagnostic only: they tell a human who wedged it.

**The content is written once and never rewritten**, and the write is published
atomically: the payload is written to a temp name inside `Temp` and `File.Move`d to
`RUN.inprogress`, so a reader can never observe a torn or partial record — "written
once" alone does not guarantee that; a process can die mid-write. The final `Move` is
**exclusive**: if `RUN.inprogress` already exists at publish time, this run has provably
lost the lock (a reclaimer stole the directory in the create→marker window) and **aborts
immediately, touching nothing**. That failure is loud, safe, and closes the theft
window from the victim's side.

Write-once has two load-bearing consequences:

1. A reader can never observe a torn write (now guaranteed by the atomic publish).
2. It forces liveness to be carried by something else — the file's **mtime** — which is
   the only signal that survives a garbage, truncated, or future-schema payload.

`StaleAfterSeconds` is in the *record*, not in the reader, so the reader honours the
threshold **the writer committed to** — with one floor: a reader never treats a marker
as stale before its own built-in 1800 s. A future schema may lengthen the threshold; it
can never shorten it below the floor an old reader would apply anyway.

### 2.2 Liveness is mtime plus a confirmation sample, not PID

Review §5 is right that PID is useless here: the writer is a container that may share
neither PID namespace nor host with the reader, and the store is exFAT. So identity in
the record is diagnostic (except `RunId`, the fence). The *decision* is:

> the owner is dead **iff** `RUN.inprogress`'s mtime is older than `StaleAfterSeconds`
> **and** a second sample, taken at least one heartbeat interval plus margin later
> (~90 s), shows the mtime **unchanged**.

- **Heartbeat** = `File.SetLastWriteTimeUtc` on the marker, every 60 s, **guarded by
  identity**: the callback re-reads the marker first and touches it only when the
  `RunId` matches its own. A late callback firing after stop, or after a reclaim has
  replaced the marker, therefore cannot freshen a successor's record.
- **The confirmation sample is what makes the age test safe.** A computed age compares
  the writer's clock (the value `SetLastWriteTimeUtc` stamps) against the reader's — and
  the dangerous skew is the writer being *behind*: a live, continuously beating owner
  would look instantly stale to a fast reader. The second sample is clock-free: a live
  owner beats during the window and the mtime moves, whatever either clock says. It also
  absorbs any metadata caching a remote volume does. The cost — ~90 s added to the
  reclaim path only — buys the property that no clock configuration can cause a live
  owner to be stomped. The first draft's future-mtime-is-fresh rule is kept, but it was
  covering only the harmless direction.
- **Threshold** = 1800 s (30 min) — a 30× margin. The asymmetry is total: too long costs
  a slower auto-recovery, too short costs stomping a live run. So it is set long, and it
  is not exposed as a knob.

**The heartbeat callback must be compiled .NET code, not a PowerShell scriptblock.**
This is a certainty, not a risk: a scriptblock attached to `Timer.Elapsed` needs a
runspace the threadpool thread does not have, and `Register-ObjectEvent` queues the
handler to the pipeline — which is exactly what is blocked while a 100 GB file hashes.
Both reviewers converged on this independently, and one reproduced the non-firing
callback under PowerShell 7.6/.NET 10. The repo has prior art for the failure mode:
LLR-073 records a bare background `Thread` terminating the whole process with
`PSInvalidOperationException`, so the first draft's Q4 fallback was worse than its
primary. The implementation is a small `Add-Type` class (`StagingHeartbeat`: timer,
identity-guarded touch, cancellation flag, drain) whose reference the engine keeps
rooted for the lock's whole lifetime — an unrooted timer is collectable and stops
silently, and `System.Timers.Timer` swallows handler exceptions, so nothing else would
tell us.

### 2.3 The guard becomes three-way

Each branch is decidable from the disk alone. First, though, the evidence has to be
**complete and fail-closed**:

- Enumeration is `Get-ChildItem -Force -LiteralPath -ErrorAction Stop` (or
  `Directory.EnumerateFileSystemEntries`) — hidden and system entries are content like
  any other, and an enumeration, stat, or access **failure is never evidence of
  emptiness**: any I/O error classifies as `Indeterminate` and refuses.
- A `Temp` that is a **reparse point / symlink** is refused outright — moving or
  deleting through one acts on a tree this guard never classified.

| `Temp` contains | verdict | action |
|---|---|---|
| nothing at all, **and the directory's own mtime is stale** | died inside the create→marker window long ago, or predates WP14 | **reclaim** |
| nothing at all, directory mtime fresh | may be a live run inside the create→marker window | **refuse** — the owner's exclusive publish (§2.1) resolves it within microseconds either way |
| `RUN.inprogress` only, stale by age **and confirmation sample** | owner provably dead, nothing of value written | **reclaim** |
| `RUN.inprogress` only, fresh (or moving during confirmation) | **a run is genuinely active** | **refuse** — and say so truthfully |
| `PRUNE.inprogress` (any age) | prune holds it; out of scope (§7) | **refuse** |
| **any other file or subdirectory** (hidden included) | may hold the only physical copy | **refuse** — unchanged from today |

An unparseable or truncated `RUN.inprogress` (`ParseInvalid`) falls back to mtime alone
with the 1800 s floor: stale-and-confirmed → reclaim, fresh → refuse. It is never an
error — a torn record means the writer died mid-publish, which is exactly the pre-WP14
state. A marker that cannot be **read at all** (`Unreadable` — locked, ACL, I/O error)
refuses: absence of evidence, not evidence of death. The pre-WP14 empty-`Temp` on the
hub (mtime 2026-08-30) passes the stale-directory branch — the upgrade path costs
nothing.

### 2.4 Reclaim is a move, never a delete — and never recursive

```
1. New-Item Temp                      -> success? write own marker (2.1). done.
2. classify Temp (2.3)                -> not reclaimable? refuse, with the branch's message.
   (includes the ~90 s confirmation sample on the stale branches)
3. Directory.Move Temp -> Temp.stale-<utc>-<8 hex>
                                      -> failed? refuse. Do NOT retry in a loop.
4. New-Item Temp, then IMMEDIATELY publish own RUN.inprogress (2.1)
                                      -> either failed? refuse; leave the aside folder in place.
5. RE-ENUMERATE the aside folder (-Force, fail-closed):
      marker-only                     -> delete the exact marker leaf BY NAME, then
                                         Directory.Delete(path, recursive:false).
                                         Either step failing -> KEEP the folder, log, continue.
      empty                           -> Directory.Delete(path, recursive:false), same rule.
      anything else, or any I/O error -> KEEP IT. Log loudly, print the README recovery.
```

**Step 5 is not belt-and-braces, it is the design's safety proof.** Between the
classification at step 2 and the move at step 3, a frozen-then-resumed owner could
write data files. So we never rely on the classification surviving: the move-aside is
itself the README's prescribed safe action, and the only deletes are (a) one leaf whose
exact name we recognize and (b) a **non-recursive** directory delete that the
filesystem itself fails if *anything* has appeared since the re-enumeration. The first
draft re-enumerated and then deleted recursively — which left a final enumerate→delete
window where a resurrected owner's data file could be swept up. The non-recursive
delete converts that last race into a safe failure: the folder is kept and a human is
told.

The `Directory.Move` at step 3 also gives us the race guarantee for free: two
simultaneous reclaimers cannot both move the same source directory, and the loser then
fails step 3 and refuses. `New-Item` at step 4 is a second, independent atomic gate,
and the immediate marker publish closes the reclaimer's own create→marker window
against a third contender.

### 2.5 The residual two-writer window, and the fence

The honest limit of this design: a plain filesystem offers no true lease, so a process
frozen for 30+ minutes (SIGSTOP, VM pause) whose lock is then reclaimed can resume and
write **by path** — and the path `Temp` now names the *successor's* staging folder,
not the aside folder. The first draft claimed the resurrected owner's bytes land in
the aside folder; that is only true for handles it already held open. Both reviewers
flagged it; the Codex pass rated it the plan's worst gap.

The mitigation is the **`RunId` fence**: the engine re-reads the marker and compares
`RunId` at every phase boundary that is about to mutate the pool or publish state —
before eviction (`Move-RemovedFilesToStaging`), before preservation
(`Save-SupersededData`), and before `Complete-ChangeFolder`. A mismatch means the lock
was lost; the run **aborts immediately and cleans up nothing** — the folder is no
longer ours to delete. The check is one small-file read per phase, and it shrinks the
exposure from "the rest of the run" to "inside a single phase whose first act follows
a passed fence".

What remains after the fence is a genuinely residual risk — resurrection *mid-phase*
after a 30-minute freeze — and it is accepted **because the baseline is worse**: today
the same frozen run races the human performing the README's manual move-aside, with no
marker, no fence, and no detection at all. The fence also protects the manual
procedure, since a moved-then-recreated `Temp` fails the resurrected owner's next
check. If a stronger guarantee is ever wanted, it is an O_EXCL lease file re-acquired
per phase — noted in §7, not needed to beat the status quo.

---

## 3. Requirements deltas

Registry rows land **before** the code, in their own commit, with
`python scripts/trace.py --strict` green.

| id | change |
|---|---|
| **SR-017** | *Amended.* Keeps the refusal as the default. Adds: the refusal is conditioned on the staging folder holding content or a live owner; a folder proved to hold neither is reclaimed non-destructively. **Acceptance is scoped to the externally interrupted *backup* run** — a killed prune still wedges (deferred, §7) and the SR must not claim the general case closed. Rationale line records WP14 and the HomeHub 2026-08-31 wedge. |
| **SR-075** *(new)* | **Staging lock ownership and stale reclaim.** The owner record with `RunId`, atomic exclusive publish, mtime-as-heartbeat, the threshold-plus-confirmation-sample semantics, the fail-closed classification, the move-then-verify-then-non-recursive-delete reclaim protocol, and the phase-boundary fence. Verification: `Test`. Permutations cell (§5). |
| **LLR-017** | *Amended.* `Initialize-StagingFolder` gains the classification and reclaim; `CodeSymbol` extended. |
| **LLR-080** *(new)* | Marker read/write/heartbeat helpers in **Engine** (I-4 as corrected) + the reclaim protocol's exact step order from §2.4, including the non-recursive step 5, + the §2.5 fence points. |
| **SR-046 / LLR-046** | *Untouched.* Prune's `PRUNE.inprogress` and its staging-busy refusal are unchanged; the backup path simply learns to recognise the marker and refuse on it (I-3). |

No Common change ⇒ **no KitRevision bump** (I-4). If review of Part A ever forces a
helper into Common after all, both kit markers bump in that same commit — AGENTS.md
makes that non-optional.

---

## 4. Work parts

### Part A — Engine: the marker (LLR-080)

New helpers **in `FileBackup.Engine.psm1`**, each with comment-based help as the first
thing in the body and an `# Implements:` back-link:

- `Write-StagingOwnerRecord` — temp-write + exclusive `File.Move` publish (§2.1); must
  be called only after a successful `New-Item`; **losing the exclusive publish throws**,
  and the caller treats it as lock-lost (abort, touch nothing).
- `Read-StagingOwnerRecord` — returns `{ State: Parsed|ParseInvalid|Unreadable, Record,
  LastWriteUtc, AgeSeconds }`. `ParseInvalid` with the mtime fields populated is a
  normal, expected return; `Unreadable` is distinct and refuses upstream (§2.3).
- `Get-StagingLockState` — the §2.3 classifier. **Pure of I/O decisions**: it takes the
  (`-Force`, fail-closed) enumeration result and the record and returns one of
  `Empty | EmptyFresh | OwnerStale | OwnerLive | PruneHeld | HoldsContent |
  Indeterminate`. Unit-testable with no filesystem (pure core / I/O shell, per
  CLAUDE.md). The confirmation sample is the caller's, not the classifier's — the
  classifier stays pure.
- `StagingHeartbeat` (compiled via `Add-Type`, §2.2) wrapped by
  `Start-StagingHeartbeat` / `Stop-StagingHeartbeat`. Start returns the rooted handle.
  Stop is idempotent, must not throw from a finalizer path, and **drains**: it sets the
  cancellation flag, disposes the timer, and waits out any in-flight callback, so no
  touch can land after Stop returns. The callback's identity guard (`RunId` match
  before touch) is the second, independent layer against the late-callback race.

### Part B — Engine: heartbeat the lock (SR-075)

`Initialize-StagingFolder` writes the record on the success path and returns the
heartbeat handle alongside the folder path. From the moment the handle exists, **all
post-acquisition work in `Invoke-BackupSet` runs inside a `try/finally` whose `finally`
stops and drains the heartbeat** — the four existing `catch` cleanups cover only the
early exits, and an exception escaping after staging gains content would otherwise
leave a live timer advertising an abandoned lock as owned. (This heartbeat-only
`finally` is deliberately *not* the deferred guarded-`finally` refactor of the deletion
cleanups in §7 — it stops a timer, it deletes nothing.)

*Ordering matters twice:* the record is written **after** `New-Item` returns, never
before, or the write itself becomes the race. And the marker must be **removed — stop,
drain, delete the leaf — immediately before `Complete-ChangeFolder`**: that function
either deletes `Temp` (no-op/first run) or renames it wholesale into `Snapshot_*`
(changed run), and as first-drafted the marker would have been published into every
snapshot — where prune's unreferenced-data rail (SR-046) would then refuse the
snapshot as holding a file its manifest does not name. No `RUN.inprogress` may ever
reach a `Snapshot_*` folder; TC-202 asserts it.

### Part C — Engine: reclaim (SR-017 amended, §2.4)

The classification and the five-step protocol, in `Initialize-StagingFolder`; the §2.5
fence checks at their three phase boundaries in `Invoke-BackupSet`. The existing
`New-Item` fast path is untouched — the new code is reachable **only** from the current
`catch`, so a healthy run's instruction path does not change at all.

### Part D — The reduced E: make the facts legible

The review's E imagined a "feed/health surface". **FileBackup has none, and should not
grow one:** IF-001 gives HomeHub the exit status and the log, and says HomeHub owns
NagLight translation. So E reduces to emitting facts HomeHub can act on:

- **Distinct, greppable branch tokens** in the log — `[SR-075/reclaimed]`,
  `[SR-075/owner-live]`, `[SR-075/content-refused]`, `[SR-075/prune-held]`,
  `[SR-075/lock-lost]` (the §2.1 exclusive-publish loss and the §2.5 fence trip share
  the last one). This is the bit that turns *"a one-second clean-looking failure"* into
  something a wrapper can alarm on, and it is the half of E that would actually have
  cut 18 hours to minutes.
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
state=set{empty-stale,empty-fresh,marker-only-stale,marker-only-fresh,marker-unparseable-stale,marker-unparseable-fresh,marker-unreadable,marker-plus-data,data-no-marker,prune-marker,temp-is-symlink}; platform=set{windows,container}
```

Beyond the generated matrix, these are named, **with their ids assigned now** so §6/§8
cannot drift from a counting convention (the first draft said "TC-190" for a case that
sequential numbering made TC-194):

| id | Case | Why it is not optional |
|---|---|---|
| TC-185 | Marker written and heartbeat advances mtime **while a long blocking operation runs**, observed from a separate process; a callback made to throw is also shown not to kill or silently stop the beat unnoticed | Proves the compiled callback, not the pipeline, drives the beat (§2.2). Inline beats and scriptblock handlers pass a naive test and fail in production; `Timers.Timer` swallows handler exceptions. |
| TC-186 | Stale marker-only → confirmation sample → reclaimed, run completes, aside folder gone, `[SR-075/reclaimed]` logged | The observed defect, end to end. |
| TC-187 | Fresh marker-only → refused, no move, tree byte-identical | The stomp case A alone could not survive. |
| TC-188 | `marker + data file`, marker stale → **refused, nothing moved, nothing deleted, every byte hash-identical before and after** | I-1. Assert hashes, not just presence. |
| TC-189 | **Resurrection before the move:** data files appear between classify and move (test hook) → aside folder is **kept**, deletion skipped, recovery printed | §2.4 step 5, first window. |
| TC-190 | `PRUNE.inprogress` present → refused | I-3 / SR-046 regression. |
| TC-191 | Two reclaimers racing the same stale lock → exactly one proceeds, one refuses, one `Temp` exists, its marker is the winner's | I-2. |
| TC-192 | Empty `Temp`, no marker, directory mtime **stale** (a pre-WP14 store) → reclaimed; same but mtime **fresh** → refused | Upgrade path (the hub's literal state) *and* the create→marker theft gate (§2.3). |
| TC-193 | Future-dated marker mtime → treated as fresh, refused | Clock-skew conservatism, harmless direction (§2.2). |
| TC-194 | G8 real-volume + **exFAT** (Windows): reclaim end to end | Half of the §6 Q1 evidence. |
| TC-195 | Container acceptance: reclaim inside `filebackup:local`, boot id read from `/proc`, on the hub's Linux-over-exFAT stack | The deployment the defect was found in; the other half of Q1. |
| TC-196 | Existing TC-073 and the four `catch` cleanups still green; an exception injected at each major phase **after** staging gains content still stops the heartbeat (the Part B `finally`) | The heartbeat-stop coverage is the regression risk in Part B. |
| TC-197 | **Theft window, victim side:** run A paused (hook) after `New-Item`, before marker publish; A's directory reclaimed-or-refused per TC-192; on resume A's exclusive publish **fails and A aborts touching nothing**, `[SR-075/lock-lost]` | §2.1. The window is microseconds; correctness cannot depend on that. |
| TC-198 | **Resurrection after the re-check:** file lands in the aside folder between step-5 re-enumeration and delete (hook) → non-recursive delete **fails**, folder kept, bytes intact | §2.4's last window; the reason `-Recurse` is banned. |
| TC-199 | Torn/truncated marker and unknown-`SchemaVersion` marker → `ParseInvalid`, mtime fallback with the 1800 s floor; marker held **locked/unreadable** → `Unreadable`, refused | §2.3 fail-closed split. |
| TC-200 | Hidden + system + dot-named entries classified `HoldsContent`; enumeration error → `Indeterminate`, refused; `Temp` as symlink/junction → refused | §2.3's evidence-completeness rules. |
| TC-201 | Callback deliberately held in flight across `Stop-StagingHeartbeat` while a successor acquires `Temp` → successor's marker mtime **not** freshened (drain + `RunId` guard) | §2.2 late-callback race. |
| TC-202 | Changed-run finalize: no `RUN.inprogress` inside the produced `Snapshot_*`; that snapshot **prunes without an unreferenced-data refusal**; no-op and first-run paths also leave no marker behind | Part B marker lifecycle vs `Complete-ChangeFolder`. |
| TC-203 | Writer clock **behind** reader beyond the threshold, owner alive and beating → confirmation sample sees the mtime move → refused | §2.2. The dangerous skew direction the first draft had backwards. |
| TC-204 | Fence: marker swapped for a different `RunId` (hook) at each of the three §2.5 boundaries → run aborts before the phase mutates, cleans up nothing, `[SR-075/lock-lost]` | §2.5. |

**Negative controls required** for TC-185, TC-189, TC-191, TC-197, TC-198, TC-201,
TC-203 and TC-204 — each must be shown to fail with its fix removed. WP13's T4 is the
precedent: two tests that could not fail shipped as green.

---

## 6. Open questions to close during implementation

Q3 and Q4 from the first draft are **closed by design** (§2.2: the confirmation sample;
the mandated compiled callback — TC-185/TC-203 remain the proof). What stays open:

| # | Question | Fallback if the answer is bad |
|---|---|---|
| Q1 | Is `Directory.Move` of a directory within the same parent reliable on the **actual deployment stacks** — not just Windows-exFAT (TC-194) but the hub's Linux-container-over-exFAT bind mount (TC-195 runs there), and UNC/SMB stores? The public .NET contract does not promise rename atomicity and permits in-use failures. | Define the supported-provider list from the evidence; on any provider not proven, or on any ambiguous move failure: **refuse**, leave both paths untouched, start no writer. Never fall back to delete. Auto-recovery is lost on that provider only; today's behaviour is what remains. |
| Q2 | Does any healthy path leave `Temp` marker-less for a prolonged period? | Should be impossible after Part B; TC-185/TC-202 prove it. If one exists, it is a bug in Part B, not a reason to widen the reclaim. |

---

## 7. Deliberately deferred, with reasons

| item | why not now |
|---|---|
| **Prune gets a heartbeat too** | `Remove-BackupSnapshot` has the identical defect — a killed prune wedges `Temp` permanently, blocking backups. It is deferred because prune is human-invoked and minutes-long, not scheduled and hours-long, so its exposure is a fraction of the backup path's. **It should be WP15, and this row exists so it is not forgotten.** Until it lands, WP14's title claim is scoped: SR-017/SR-075 acceptance names the *backup* run only (§3). |
| **A guarded `finally` replacing the four `catch` cleanups** | Half of the review's option C, which the Owner scoped out. A genuine simplification and strictly safer than four unguarded `Remove-Item -Recurse -Force` calls, but it edits the data-safety path for tidiness rather than for the defect. Raise separately. (Part B's heartbeat-only `finally` is not this — it deletes nothing.) |
| **`SIGTERM` trapping** (`PosixSignalRegistration`) | The rest of option C. Once reclaim lands it buys only the graceful path, which reclaim already covers, and it cannot touch `SIGKILL`/OOM/power loss. Poor trade. |
| **A per-phase O_EXCL lease** | The §2.5 fence's stronger sibling. Only worth its complexity if the residual mid-phase resurrection window ever bites in practice; the fence already beats the status quo by a wide margin. |
| **A new exit code for "wedged"** | IF-001 is a cross-project contract and HomeHub owns alarm policy (I-5). The branch tokens in Part D give HomeHub what it needs without a contract change. |

---

## 8. Sequencing

Each row is one small green commit (CLAUDE.md commit cadence).

| # | Commit | Gate on |
|---|---|---|
| 1 | Defect review committed as found, then corrected; this plan; the §10 review round | *(done — the commits carrying this file)* |
| 2 | Registry deltas (§3) | `python scripts/trace.py --strict` green, orphans 0 |
| 3 | Part A — Engine helpers + their unit tests (incl. the TC-199/TC-200 classifier halves) | `pwsh scripts/check.ps1 -Tier Smoke` |
| 4 | Part B — marker + heartbeat + `finally` + marker lifecycle; TC-185, TC-196, TC-201, TC-202 | Smoke; TC-073 still green |
| 5 | Part C — reclaim + fence; TC-186…TC-193, TC-197, TC-198, TC-203, TC-204, incl. negative controls | `-Tier Full` |
| 6 | Part D — messages, tokens, N-1, N-2 | Smoke |
| 7 | G8 exFAT + container acceptance evidence (TC-194, TC-195); status.md entry | `-Tier Release`, real output pasted |

**Independent review** (process.md §6) after commit 5, before the gate: this is hashing-
adjacent, data-integrity surface, and the last two independent reviews on this repo each
found P0s that in-house testing had missed. The §10 plan-stage round does not discharge
this — it reviewed the design, not the code.

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

---

## 10. Plan-stage review round, 2026-08-31 — composite disposition

Two independent passes over the first draft: the driver's self-review against the code,
and an OpenAI Codex CLI agent (read-only, full repo access, ~280 k tokens). Four
findings were found by both. Every accepted finding is folded above; this table is the
audit record, not a to-do list.

| finding (both = found independently twice) | sev | disposition |
|---|---|---|
| Resurrected owner writes **by path** into the successor's `Temp` and the pool; "bytes land in the aside folder" was false (both) | P0 | **Folded** — §2.5 `RunId` fence at the three pool-mutating boundaries; residual mid-phase window documented and accepted vs. the strictly-worse baseline; O_EXCL lease deferred (§7). TC-204. |
| Create→marker window lets a reclaimer steal a live lock; recurs for the reclaimer at step 4 (both) | P0 | **Folded** — exclusive atomic marker publish aborts the victim (§2.1); empty-no-marker reclaim gated on directory mtime (§2.3); reclaimer publishes immediately at step 4 (§2.4). TC-192, TC-197. Codex's prepare-dir-then-rename acquisition was **rejected**: `Directory.Move` onto an existing name is check-then-move in .NET, a worse TOCTOU than the proven `New-Item` primitive. |
| Scriptblock timer callback cannot fire without a runspace; `Register-ObjectEvent` queues to the blocked pipeline; the bare-`Thread` fallback repeats the LLR-073 process-kill (both) | P0 | **Folded** — compiled `Add-Type` callback mandated, rooted handle, drain-on-stop (§2.2, Part A). Q4 closed. TC-185, TC-201. |
| Step 5 "re-enumerate then `-Recurse` delete" left a final race that could delete a just-arrived data file; also contradicted I-1's letter (both) | P0 | **Folded** — exact-leaf delete + non-recursive `Directory.Delete`; `-Recurse` banned from the reclaim path; I-1 reworded to match (§1, §2.4). TC-198. |
| Enumeration not specified `-Force`/fail-closed; hidden entries, I/O errors, `Temp`-as-reparse-point unhandled (Codex) | P0 | **Folded** — §2.3 evidence rules, `Indeterminate` refuses. TC-200. |
| Torn single write observable; unparseable record cannot supply its own threshold (Codex) | P1 | **Folded** — atomic temp+move publish; `ParseInvalid` vs `Unreadable` split; 1800 s reader floor (§2.1, §2.3). TC-199. Refusing *all* unparseable markers was **rejected**: a torn marker is precisely a dead writer, and refusing it re-creates the permanent wedge for the commonest crash. |
| UNC clock-skew analysis backwards — writer-*behind* makes a live owner look stale (Codex) | P1 | **Folded** — clock-free confirmation sample (§2.2); future-mtime rule kept for the harmless direction. Q3 closed. TC-203. Disabling reclaim on all remote stores was **rejected** as broader than the fixed defect needs. |
| Late/queued callback after Stop can freshen a successor's marker; no `RunId`; timer collectable if unrooted (Codex) | P1 | **Folded** — `RunId` in the record, identity-guarded touch, drain barrier, rooted reference (§2.1, §2.2, Part A). TC-201. |
| No heartbeat stop on exits after staging gains content — four `catch`es don't cover them (Codex) | P1 | **Folded** — heartbeat-only `try/finally` in Part B, distinguished from the deferred cleanup refactor. TC-196. |
| Marker lifecycle vs `Complete-ChangeFolder`: marker would be snapshotted, then refuse its own snapshot's prune as unreferenced data (Codex; verified against `Engine.psm1:3405` and SR-046) | P1 | **Folded** — stop/drain/remove-leaf before finalize (Part B). TC-202. |
| `Directory.Move` atomicity unproven on the hub's actual Linux-over-exFAT stack; one Windows run is not evidence (Codex) | P1 | **Folded** — Q1 rewritten: supported-provider list from evidence, ambiguous failure refuses, TC-195 runs the real stack. |
| Common placement misreads I-4 and silently incurs a KitRevision bump — Common is kit-bundled (Codex; verified against AGENTS.md) | P2 | **Folded** — helpers moved to Engine; I-4 row corrected; no-bump consequence recorded (§1, §3, Part A). |
| TC numbering internally inconsistent (Q1 said TC-190 for the exFAT case; §8 referenced ids no table assigned); several safety rails had no named test (both, partially) | P2 | **Folded** — ids assigned in the table (§5); TC-197…TC-204 added; negative-control list extended; §6/§8 references updated. |
| Title/acceptance overclaims: a killed prune still wedges forever (Codex) | P2 | **Folded** — SR-017 acceptance scoped to the backup run (§3); WP15 row strengthened (§7). |
