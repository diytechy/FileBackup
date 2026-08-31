# Defect review — an externally-killed run leaves a permanent stale `Temp` lock

**Found:** 2026-08-31, on the real HomeHub production hub (Ubuntu, `filebackup:local`
container, real 4 TB library / 8 TB backup drives), while investigating why the
whole-library backup had never completed a pass. **Not found by testing this repo** —
found because a HomeHub operator action a day earlier silently wedged every subsequent
run, and the wedge was invisible until something else stopped failing first.

**Status:** one defect, plus one documentation item recorded as done that is not done.
**No outcome is proposed as decided** — the Owner's position is only that *"an
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
| **D-2** | The recovery the guard names does not exist | The error tells the operator to *"follow the safe recovery in README, 'A run refuses because Temp exists'"*. **No such section exists in `README.md` or anywhere else in this repo.** `docs/status.md` (F1/R4) records that the README was updated; the guard message was, the README was not. |

**The two compound.** D-1 wedges the product, and D-2 removes the documented way out —
leaving an operator holding an error that forbids the obvious action (`rm`), names a
procedure they cannot find, and offers nothing else.

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

## 4. D-2 — the missing README section

`docs/status.md` (F1/R4) records the fix as:

> *"Guard message + README now prescribe the non-destructive recovery (move-aside →
> re-run → verify → discard-or-reintroduce, never delete)."*

**Half of that shipped.** Verified 2026-08-31 across the working tree:

| claim | actual |
|---|---|
| guard message prescribes move-aside | **true** — `Engine.psm1:2989` |
| README prescribes the recovery | **false** — `'A run refuses because Temp exists'` appears **nowhere** in `README.md`; the only occurrences of the phrase in the repo are the error string itself and a passing mention in `docs/plans/wp4-retention-plan.md:124`. The words *"move it aside"* appear only in the guard message and in `status.md`'s own account of the fix. |

So the guard directs the operator to a document section that does not exist. The full
four-step procedure (`move-aside → re-run → verify → discard-or-reintroduce`) survives
**only inside a status-log entry describing the fix** — not anywhere an operator hitting
the error would look.

**This is worth fixing regardless of what is decided for D-1**, and it is the cheaper
half. It is also a reminder that F1/R4's own lesson was about a README that gave
destructive advice; the correction to it was recorded as complete while half-applied.

---

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

Write the missing README section; change nothing in code.

- **For:** fixes D-2, costs nothing, no new risk, and is needed under every other option.
- **Against:** leaves the wedge permanent-until-human. Does not satisfy *"an interrupted
  run should not be a permanent interrupt"* — it only makes the interrupt survivable by
  a reader who finds the doc.

### E. Alarm rather than repair

Leave the lock; make a stale one **loud** (feed/health surface reports "wedged since
<time>") rather than a one-second failure.

- **For:** no change to the safety-critical path; addresses the invisibility, which is
  what made this cost 18 hours instead of 18 seconds.
- **Against:** still a permanent interrupt; still needs a human.

**Not mutually exclusive.** D is needed under all of them. E addresses the detection
half regardless of which repair half is chosen. B is the enabler that makes A safe.

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
- `README.md` contains no `'A run refuses because Temp exists'` section and no move-aside procedure.
- HomeHub's `library-backup.sh` contains **zero** occurrences of `Temp` — it neither creates, inspects, nor clears it. This is entirely inside this repo.

**Not verified — deliberately, and each would change the sizing of an option:**

- Whether the container traps `SIGTERM`, and what `docker compose run -T` + `systemctl stop` actually deliver to the PowerShell host (blocks option C).
- Whether any code path leaves `Temp` empty for a prolonged period *during* a healthy run beyond the manifest-cache phase (bounds the stomp risk in option A).
- Whether exFAT semantics on the change-store mount affect atomic directory rename (bounds the A-with-rename variant).

**Nothing on the hub has been changed.** The stale `Temp` is **still in place** at
`/mnt/backup-drive/library-changes/Temp`, deliberately preserved as evidence — so the
whole-library backup remains blocked until a decision is taken here. Recovering it is
one `mv`; it is being held, not overlooked.
