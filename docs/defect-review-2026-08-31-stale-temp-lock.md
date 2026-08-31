# Defect review — an externally-killed run leaves a permanent stale `Temp` lock

**Found:** 2026-08-31, on the real HomeHub production hub (Ubuntu, `filebackup:local`
container, real 4 TB library / 8 TB backup drives), while investigating why the
whole-library backup had never completed a pass. **Not found by testing this repo** —
found because a HomeHub operator action a day earlier silently wedged every subsequent
run, and the wedge was invisible until something else stopped failing first.

**Status (corrected 2026-08-31):** **one** defect, D-1. The original version of this
review also raised **D-2** — "the README recovery section the guard names does not
exist". **D-2 is WITHDRAWN as a false finding**: the section has existed since
`8897ca7` (2026-08-23) and prescribes exactly the procedure `status.md` records.
§4 now documents the withdrawal and the search error that produced it, because a
false "recorded as done but not done" claim against `status.md` is more corrosive
here than the defect it accompanied. Everything else in this review stands as
written and was re-verified. **No outcome is proposed as decided** — the Owner's position is only that *"an
interrupted run generally should not be a permanent interrupt."* Options are laid out
in §5 with their trade-offs; §6 states the constraint any option must not break.

**Severity:** availability, not data loss. Nothing is corrupted or lost by this defect.
Its cost is that backups **silently stop happening** — which, for a backup product, is
the failure mode that looks most like success from the outside.

---

## Summary

| | | |
|---|---|---|
| **D-1** | Staging lock is never released on external termination | A `SIGKILL`/`docker kill`/`systemctl stop` of a running set leaves `Temp` behind. Every later run then refuses at `Initialize-StagingFolder`. There is no automatic recovery and no time limit — the wedge is permanent until a human intervenes. |
| ~~**D-2**~~ | ~~The recovery the guard names does not exist~~ | **WITHDRAWN — false.** `README.md:947` carries the section and the full four-step procedure. See §4. |

**D-1 therefore stands alone.** The original review argued the two compounded — that
D-1 wedges the product while D-2 removes the documented way out. Half of that was
never true: the operator who reaches the error *can* find the procedure, and following
it recovers them. What is true is narrower, and still bad: nothing brings the product
back **without** a human reading a document.

---

## 1. What happened, in order

| when | event |
|---|---|
| 2026-08-30 14:33 | First real whole-library run started **by hand** on the hub. |
| 2026-08-30 ~14:34 | Owner stopped it **deliberately** — it should only run at 03:00. `Temp` created at 14:34 and **left behind**. |
| 2026-08-30 15:31 | Timer installed. |
| 2026-08-31 03:00 | First scheduled run. Failed — but on an unrelated HomeHub-side disk-full condition that fired *first*. **The stale `Temp` was not yet visible.** |
| 2026-08-31 08:15 | HomeHub-side cause fixed; run retried. Reached the container, started the set, and refused: |

```
[INFO]  ----- Backup set 'library' starting -----
[ERROR] Staging folder '/changes/Temp' already exists. Previous run may have failed or still be running.
[ERROR] If no other run is active, do NOT delete Temp: it may hold the only copy of
        snapshot-demanded bytes. Move it aside and follow the safe recovery in README,
        'A run refuses because Temp exists'.
[ERROR] Failed to initialize staging folder; Temp already exists at '/changes/Temp'
```

**Elapsed wedge: ~18 hours, spanning the product's first two scheduled opportunities,
with no signal that the cause was a leftover directory.**

### State on the drive at the time of the refusal

| | |
|---|---|
| files in `/changes/Temp` | **0** |
| `Snapshot_*` trees in `/changes` | **0** |
| `/backup` (the store) | **empty — no run has ever completed** |
| `Temp` mtime | `Aug 30 14:34` |

**All three independently confirm `Temp` held nothing recoverable.** No pass has ever
completed, so nothing exists to supersede; per `Invoke-BackupSet`'s own comment, *"Temp
holds nothing of value until the preserve/evict steps"*, and this run was killed long
before them (it was ~3.5 minutes into *Updating source manifest cache*).

---

## 2. Where it is in the code

**The lock take** — `Modules/FileBackup.Engine.psm1:2980-2992`:

```powershell
$stagingFolder = Join-Path $ChgPath 'Temp'
# The create IS the lock take: CreateDirectory-without-Force fails when the
# folder already exists, so two overlapping runs cannot both pass a
# Test-Path look-then-create window (the same TOCTOU Remove-BackupSnapshot
# already closes for the prune path).
try {
    New-Item -ItemType Directory -Path $stagingFolder -ErrorAction Stop | Out-Null
} catch {
    ...
    throw "Cannot initialize staging folder; Temp already exists at '$stagingFolder'"
}
```

**This is correct and should be kept.** Creation-as-lock is the right primitive, it
closes the R3 TOCTOU deliberately, and testing *contents* instead of *existence* would
reintroduce exactly that race. **D-1 is not an argument against the lock.** It is an
argument about what releases it.

**The release** — four `catch`-block cleanups, at `:3988`, `:4037`, `:4051`, `:4066`.
The design intent is explicit at `:3986-3991`:

> *"A source file that cannot be read (open for write, AV hold) fails the set loudly —
> but must not strand the still-empty staging folder, or every LATER run refuses on the
> SR-017 stale-Temp guard instead of the real cause. Temp holds nothing of value until
> the preserve/evict steps."*

`AGENTS.md` step 9.4 states the same rule for the capacity refusal — *"never orphaning a
`Temp` for the next run's SR-017 guard."*

**So the hazard is already understood, and already handled — for in-process failures
only.** Every release path is a `catch`. There is no `finally`, and no startup-side
reclaim. **A process that is terminated externally runs none of them.**

### The gap, stated precisely

| how a run ends | `Temp` released? |
|---|---|
| completes normally | yes |
| throws (unreadable source, capacity refusal, AV hold, torn state) | yes — `catch` cleanup, by design |
| **killed externally (`SIGKILL`, `docker kill`, `systemctl stop`, OOM, host reset, power loss)** | **no — permanently** |

The uncovered row is not exotic. In the HomeHub deployment it is **routine and
expected**: the unit runs `TimeoutStartSec=infinity` against a multi-hour 2.1 TB pass,
so "stop the run" is a normal operator action with no in-process equivalent. It is what
happened here, and it was the *correct* action at the time.

---

## 3. Why it stayed invisible for 18 hours

Three properties combine, and each is individually defensible:

1. **The lock carries no identity or liveness.** It is a bare directory — no PID, no
   boot id, no heartbeat, no timestamp of intent. So the guard genuinely cannot tell
   *"a run is active"* from *"a run died 18 hours ago"*, which is why its message has to
   say *"may have failed or still be running"*. It is hedging because it has no way to
   know.
2. **The failure is at the very start of the set**, before any progress, so a wedged run
   costs one second and looks like a fast clean failure rather than a stuck job.
3. **It was masked.** At 03:00 a HomeHub-side disk-full condition failed the sibling
   unit one second earlier, so the stale-`Temp` refusal was not the reported cause.
   Fixing the visible cause revealed a second one underneath.

---

## 4. D-2 — withdrawn, and how the search went wrong

**The original finding was:** `docs/status.md` (F1/R4) records the fix as

> *"Guard message + README now prescribe the non-destructive recovery (move-aside →
> re-run → verify → discard-or-reintroduce, never delete)."*

…and claimed only the guard half shipped. **That claim is false.** Re-verified
2026-08-31 against the working tree:

| claim | actual |
|---|---|
| guard message prescribes move-aside | **true** — `Engine.psm1:2989` |
| README prescribes the recovery | **also true** — `README.md:947-957`, under *Notes & troubleshooting*, heading **"A run refuses because `Temp` exists (stale `Temp` folder error)."** |

The README section is not a stub. It carries the whole four-step procedure the status
entry claims, in order, with the destructive action explicitly forbidden:

1. move the whole `Temp` folder *aside*, outside `ChangePath` — never delete;
2. re-run the backup, now unblocked;
3. `-Action Verify` **and** test-restore the oldest snapshot;
4. if any restore reports missing content, copy the moved folder's *data files* into
   the backup root under any non-colliding names — skipping its `MANIFEST.csv`, which
   is the interrupted run's staging copy of the index — because both restorers find
   content by hash regardless of filename; then verify again.

`git log -S` dates it to `8897ca7` (2026-08-23), the F1/R4 merge itself. **Both halves
shipped together. `status.md` was accurate.**

### The search error

The review searched for the guard message's own literal, `A run refuses because Temp
exists`. The README writes the identifier in backticks — ``A run refuses because `Temp`
exists`` — so that literal does not occur, in the README or anywhere a plain-text
search would find it. The review read a zero-hit result as *absence of the procedure*
rather than *absence of that exact byte sequence*, and never searched for the
procedure's own distinctive words (`move the whole`, `non-colliding`, `discard the
moved folder`), any of which would have landed on it immediately.

**The lesson worth keeping** is not "grep harder". It is that a claim of the form
*"`status.md` records something that did not happen"* is an accusation against the
repo's own memory, and this review published one on the strength of a single
unbackticked substring search. That class of claim needs a positive check — read the
document, not merely the absence of a string — before it is written down.

### What genuinely remains (small, and unrelated to the defect)

| # | item |
|---|---|
| **N-1** | The guard message cites the section as *"README, 'A run refuses because Temp exists'"*, which is not the heading's exact text. Harmless to a human — and it is what misled this review. Quote the heading verbatim. |
| **N-2** | If D-1 is repaired, the README section then describes only part of the behaviour and must be extended (§5, and Part D of the plan). |

## 5. Options — trade-offs only, nothing recommended as decided

**The distinguishing fact the engine already relies on internally:** an **empty** `Temp`
provably holds nothing recoverable, and a **non-empty** one may hold the only physical
copy of snapshot-demanded bytes. Every existing `catch` cleanup is justified on exactly
that basis. The options differ mainly in whether that same reasoning is extended to
startup, and in how much liveness information the lock carries.

### A. Reclaim a provably-empty `Temp` at startup

If `Temp` exists and is **empty**, log loudly, remove it, take the lock, proceed.
Non-empty `Temp` keeps today's refusal unchanged.

- **For:** smallest change; applies the rule the code already applies four times; fixes
  the observed case completely and every crash-before-preserve/evict case, which is most
  of the window in a long run.
- **Against:** an empty `Temp` no longer proves "no concurrent run" — two runs starting
  in the same instant could both see empty. The R3 TOCTOU would be partially reopened
  **unless** the reclaim is itself atomic (e.g. directory rename, then create).
- **Open:** does anything legitimately leave `Temp` empty *while* a run is live? Between
  the lock take and the first preserve/evict write, yes — so a reclaim could stomp a
  genuinely running set. That window is minutes on a 2.1 TB source. **This option is not
  safe without liveness (B).**

### B. Give the lock liveness

Write an owner record inside `Temp` at lock take (host, PID, container id, boot id,
start time), refreshed periodically. A later run reads it and distinguishes *"the owner
is alive"* (refuse, as today) from *"the owner is provably gone"* (reclaim if empty, or
prescribe recovery if not).

- **For:** attacks the root cause — the guard's inability to tell dead from live. Makes
  the message truthful instead of hedged. Enables A safely.
- **Against:** most work. Cross-boundary liveness is genuinely hard here: the writer is
  a container that may not share a PID namespace or host with the reader, and the store
  is on exFAT, so PID alone is not sufficient. A heartbeat plus a staleness threshold is
  more robust but introduces a tunable, and a threshold that is too short reintroduces
  the stomp risk that A has.

### C. Release the lock on signal

Add a `finally`, plus a `SIGTERM`/`Ctrl-C` handler that removes a still-empty `Temp`.

- **For:** covers the *graceful* stop path — `docker stop` and `systemctl stop` both send
  `SIGTERM` first, which is how the observed kill most likely began.
- **Against:** cannot cover `SIGKILL`, OOM, power loss, or host reset; those are exactly
  the cases with no recovery today. Narrows the gap without closing it, so it is a
  complement to A/B rather than an alternative.
- **Unverified:** whether the container's PowerShell host traps `SIGTERM` at all under
  `docker compose run -T`, and whether the 10-second default stop grace is enough to
  unwind. **Both need testing before this option can be sized** — I did not test them.

### D. Documentation only

~~Write the missing README section~~ — **there is no missing section (§4).** What
survives of this option is small: fix the guard's citation (N-1), and describe whatever
D-1's repair changes (N-2).

- **For:** costs nothing, no new risk.
- **Against:** on its own it now changes nothing. The documented way out already exists
  and already works; it did not prevent an 18-hour wedge, because the wedge's cost was
  never that the operator could not find the procedure — it was that nobody knew to go
  looking for one. Documentation cannot satisfy *"an interrupted run should not be a
  permanent interrupt"*.

### E. Alarm rather than repair

Leave the lock; make a stale one **loud** (feed/health surface reports "wedged since
<time>") rather than a one-second failure.

- **For:** no change to the safety-critical path; addresses the invisibility, which is
  what made this cost 18 hours instead of 18 seconds.
- **Against:** still a permanent interrupt; still needs a human.

**Not mutually exclusive.** E addresses the detection half regardless of which repair
half is chosen, and D's remnant (N-1/N-2) follows whichever repair lands. B is the
enabler that makes A safe.

### The option §5 missed: B-lite, which makes A safe cheaply

§5 treats A and B as a spectrum from "smallest change, unsafe" to "most work, safe",
with the stomp window — a live run holding an **empty** `Temp` for minutes during the
manifest-cache phase — as the thing forcing the expensive end. **That window is an
accident of how the backup takes the lock, not a property of the lock, and the
codebase already contains its own fix.**

`Remove-BackupSnapshot` takes the *identical* create-as-lock at
`Engine.psm1:2618-2620` and then, at `:2630`, immediately writes a `PRUNE.inprogress`
marker **inside** `Temp` — an owner record — with a `finally` that removes only a lock
that invocation created. The backup path takes the same lock and writes nothing.

Write an owner record at the backup's lock take too, and the stomp window shrinks from
*minutes* to the microseconds between `New-Item` and the marker write. A live run's
`Temp` is then **never** marker-less, and the guard's decision becomes three-way, each
branch provable from the disk alone:

| `Temp` contains | means | action |
|---|---|---|
| the marker only | a run took the lock and has written nothing of value | decide on liveness → reclaim if provably dead |
| nothing at all | died inside the create→marker window, or predates the marker | reclaim |
| **any data file** | may hold the only physical copy of snapshot-demanded bytes | **refuse — exactly as today** |

This is **B's mechanism at close to A's cost**, and it keeps §6 intact by construction:
the non-empty branch is untouched. It is what the plan implements.

---

## 6. The constraint any option must not break

**F1/R4 is the reason the guard is worded as it is, and it was reproduced, not
theorised:** the README once said *"remove the leftover Temp and re-run"*, and that
advice **permanently destroyed the only physical copy of snapshot-demanded bytes** after
a mid-window crash — snapshot restore `exit 0` before, `exit 1 ContentMissing` forever
after, with the intervening backup reporting `0`.

**So: no option may auto-delete a non-empty `Temp`, and no documentation may tell an
operator to.** Every option above is confined to the provably-empty case for that
reason. If a future option needs to touch a non-empty `Temp`, it must move it aside and
keep it until a human rules — never delete.

---

## 7. What was and was not verified

**Verified directly** — on the production hub and in this working tree:

- `Temp` empty (0 files), `Snapshot_*` count 0, `/backup` empty, `Temp` mtime `Aug 30 14:34`.
- The refusal reproduced live at 2026-08-31 08:15:58 with the log lines quoted in §1.
- Lock code at `Engine.psm1:2980-2992`; four `catch` cleanups at `:3988`, `:4037`, `:4051`, `:4066`; no `finally` on that path.
- ~~`README.md` contains no `'A run refuses because Temp exists'` section and no move-aside procedure.~~ **Withdrawn — the search was wrong; see §4.** `README.md:947-957` carries the section and the full four-step procedure, dated to `8897ca7` (2026-08-23).
- The prune path's owner-record precedent: lock take at `Engine.psm1:2618-2620`, `PRUNE.inprogress` written at `:2630`, `finally` cleanup at `:2657-2659`.
- HomeHub's `library-backup.sh` contains **zero** occurrences of `Temp` — it neither creates, inspects, nor clears it. This is entirely inside this repo.

**Not verified — deliberately, and each would change the sizing of an option:**

- Whether the container traps `SIGTERM`, and what `docker compose run -T` + `systemctl stop` actually deliver to the PowerShell host (blocks option C).
- Whether any code path leaves `Temp` empty for a prolonged period *during* a healthy run beyond the manifest-cache phase (bounds the stomp risk in option A).
- Whether exFAT semantics on the change-store mount affect atomic directory rename (bounds the A-with-rename variant).

**Nothing on the hub has been changed.** The stale `Temp` is **still in place** at
`/mnt/backup-drive/library-changes/Temp`, deliberately preserved as evidence — so the
whole-library backup remains blocked until a decision is taken here. Recovering it is
one `mv`; it is being held, not overlooked.
