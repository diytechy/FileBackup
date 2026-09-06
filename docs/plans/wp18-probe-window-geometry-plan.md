# WP18 — The compressibility probe's window geometry scales with file size

Plan owner: driver. Raised by the Owner 2026-09-02 from
[defect-review-2026-09-02-probe-sample-representativeness.md](../defect-review-2026-09-02-probe-sample-representativeness.md)
(§4 Option A, §5 recommendation, §7 open question). This plan expands that
review's recommendation into an executable, requirement-traced package.

**Status: DRAFT, pre-gate. Not approved, not started.** §7 carries the questions
that need an Owner ruling before any code moves.

---

## 1. The defect in one paragraph

`Measure-SampleCompressibility` samples every file above the 256 KiB floor at
exactly three offsets — `0`, the middle, and `len − 256 KiB`. For a media
container two of those three land on metadata: Matroska keeps SeekHead/Tracks/Tags
at the head and Cues at the tail, and a non-faststart MP4 keeps `moov` at the
tail. Metadata is structured and highly compressible, so head and tail vote
"compress" while the one window that samples payload votes "raw", and the
unweighted aggregate in rule 6 of `Resolve-CompressionDecision` lets the two
unrepresentative windows win. On the production first pass this sent 407 files
whose middle window had already read ≥ 0.95 to 7-Zip, costing 4.56 h of the first
8.01 h to save 1.88 GiB. Every byte was stored correctly. The output is right and
the price is wrong.

## 2. The change

**Option A with Option B folded in**, per the review's §5. One function changes:
`Measure-SampleCompressibility` (`Modules/FileBackup.Engine.psm1:4575`).

Raise the window count with file size instead of holding it at three:

```
Samples = clamp(3, 24, 3 + floor(log2(Length / 16 MiB)))
```

| file size | windows | sampled bytes | fraction of file |
|---|---:|---:|---:|
| **< 32 MiB** | 3 | 768 KiB | — |
| 32 MiB | 4 | 1 MiB | 1 / 32 |
| 64 MiB | 5 | 1.25 MiB | 1 / 51 |
| 1 GiB | 9 | 2.25 MiB | 1 / 455 |
| 20 GiB | 13 | 3.25 MiB | 1 / 6,300 |
| 512 GiB | 18 | 4.5 MiB | 1 / 116,000 |

**The first bump is at 32 MiB, not 16 MiB.** At exactly 16 MiB the quotient is 1,
`log2(1) = 0`, and the formula returns 3 — the base is where the *count* starts
rising, not where it first exceeds three. Verified across the ladder: `[16, 32)`
MiB takes 3 windows, `[32, 64)` takes 4, `[64, 128)` takes 5. Any statement of
the qualifying cohort must use ≥ 32 MiB.

Head and tail stay in the set, so an archive or disk image carrying its
compressible content at the head still gets credit — that is Option B folded in
rather than applied, and it is why the head/tail windows are not simply dropped.
What changes is their weight: at three windows they are 67% of the vote, at
thirteen they are 15%.

**13 is not a new constant.** It is what the formula yields at 20 GiB. The
constants that actually enter the code are the base (16 MiB), the floor (3) and
the ceiling (24).

Explicitly unchanged: the 0.10 threshold, the 256 KiB floor, the 256 KiB window
size, the Brotli-Fastest codec, the aggregate-over-sampled-bytes rule, the
`Reason` vocabulary, and every caller. `-Samples` already generalizes in the
shipped function — the offsets are computed from it — so this is a change to how
the parameter is *chosen*, not to the sampling machinery.

## 3. What it costs, measured rather than assumed

### 3a. A correction the review needs

The review's §1e states that its production figure of 29.9 ms per window is "an
independent confirmation of the Part B1 codec calibration, which measured
Brotli-Fastest at ~28 ms per 256 KiB sample on a dev machine."

**That reading of the calibration is wrong.** `wp17-codec-calibration.md` reports
27.6 ms as the *total probe time over the whole 11-file corpus* — 11 files × 3
windows = 33 windows, i.e. **~0.84 ms per window**, not 28 ms per window. The
Engine doc comment states it correctly ("137 ms vs 28 ms **over the corpus**");
only the review misreads it. The agreement between 29.9 and 28 is a coincidence
between two numbers that measure different things.

Measured on this dev box (Windows 11, PowerShell 7), Brotli at
`CompressionLevel.Fastest` over one 256 KiB window, CPU only, no file I/O, 20
reps after warm-up:

| window content | ms per window | ratio |
|---|---:|---:|
| random (video payload) | 1.13 | 1.000 |
| text (metadata / index) | 0.49 | 0.000 |
| zeros (padding) | 0.36 | 0.000 |
| half text, half random | 0.69 | 0.500 |

That reproduces the calibration's ~0.84 ms/window and refutes 28 ms/window.

### 3b. What that means for the cost model

If Brotli costs ~1 ms per window and production measures 29.9 ms per window, then
**roughly 97% of a window's cost is disk I/O — the seek and the 256 KiB read —
not compression.** The consequence for this plan is direct and it cuts against
the change: extra windows are extra *seeks*, and on the hub's array a seek is the
entire bill. The cost is therefore set by the hub's disk, not by its CPU, and it
will not improve on faster silicon.

This does not reverse the recommendation, but it does mean the honest per-window
price is the production 29.9 ms and **not** anything measurable on a dev NVMe.
For the record, the same probe on a page-cache-warm 1 GiB local file:

| windows | total ms | ms per window |
|---:|---:|---:|
| 3 | 5.7 | 1.9 |
| 8 | 9.3 | 1.2 |
| 13 | 11.4 | 0.9 |
| 24 | 19.9 | 0.8 |

Those numbers are a floor on the cost, not an estimate of it. They exclude every
seek the hub will actually pay.

### 3c. The per-file and whole-run bill

Per qualifying file, at the production rate of 29.9 ms per window:

| windows | extra vs. 3 | extra ms per file |
|---:|---:|---:|
| 4 | 1 | 30 |
| 9 | 6 | 179 |
| 13 | 10 | 299 |
| 24 | 21 | 628 |

**The multiplier is not the file count.** Only files ≥ 32 MiB get more than three
windows. Every `BelowFloor` file, every probed file under 32 MiB, and the whole
`[16, 32)` MiB band see **no change at all**.

The review counted 987 files ≥ 16 MiB out of the 24,413 measured, or 4.0%. That
is the cohort at the *wrong* boundary — the real qualifying set is ≥ 32 MiB and is
strictly smaller. The run's size histogram is on the hub, so the exact count is
not available here. Using 987 therefore gives a **conservative upper bound**:

| | files | worst-case extra time |
|---|---:|---:|
| measured window (24,413 files), ≥ 16 MiB | 987 | ~5 min |
| extrapolated full run (181,721 files) | ~7,350 | **~37 min** |

**The review's §4 understates this.** It calls `987 × 299 ms ≈ 5 minutes` "the
whole-run bill", but 987 is the count from the 13.4% sample, not the run. The
full-run figure is ~37 minutes, 7.4× the review's own number.

Both figures are a worst case twice over. They bill every qualifying file at the
20 GiB window count when a file in `[32, 64)` MiB takes four windows — one extra,
30 ms — not thirteen. And they count from ≥ 16 MiB when the true threshold is
≥ 32 MiB.

Against the ~27 hours §6 shows are recoverable, ~37 minutes is a 44:1 return. The
change remains strongly worth making; the margin is one and a half orders of
magnitude, not the four §4 claims. **Confirming the ≥ 32 MiB count from the run's
own histogram is a task for the hub session**, and it can only move the bill down.

## 4. Implementation

One function, one new private helper, no new configuration key, no
`ConfigVersion` change, no restore-side change.

1. **`Get-ProbeWindowCount`** — a pure function of `Length` returning the window
   count. Pure so it is unit-testable without touching a disk, and separate so
   the geometry can be tested independently of the I/O shell.
2. **`Measure-SampleCompressibility`** — when the caller does not pass `-Samples`
   explicitly, derive it from the stream's length via the helper. An explicit
   `-Samples` still wins, because the tests and the §6 experiment depend on it.
3. **The module-scope constants** gain the base, floor and ceiling beside the
   existing four, with the same "no configuration key" rationale SR-081 records.
4. **The `compress-decision` DEBUG line** already prints `windows=` as a
   comma-joined vector. At 24 windows that is a long line. It stays — the vector
   is what made this defect findable at all — but the plan should confirm no log
   consumer parses it positionally.
5. **Regenerate the derived documentation in the same commit.**
   `Get-ProbeWindowCount` is a new top-level function, so it enters the
   AST-generated module map and `docs/architecture.md`. Run
   `scripts/gen_arch_map.ps1` and let `check.ps1` prove freshness — it fails the
   build when those blocks are stale, so skipping this breaks the gate rather
   than merely leaving a doc behind.

### The one coupling hazard

The short-file branch reads a file **whole, as a single sample** when
`Length < Samples × SampleBytes`. Raising `Samples` raises that trip point, so in
principle a larger `Samples` could flip a mid-sized file from three windows into
a full read of itself.

With the proposed constants this cannot happen **for any file that gets more than
three windows**. A file only reaches `Samples = S` at `Length ≥ 16 MiB ×
2^(S−3)`, and that exceeds `S × 256 KiB` by at least **32×**, the minimum falling
at S = 4 (32 MiB earned against a 1 MiB trip point) and growing from there.
Checked over the whole ladder:

| S | earned at | trip point (S × 256 KiB) | margin |
|---:|---:|---:|---:|
| 4 | 32 MiB | 1 MiB | 32× |
| 9 | 1 GiB | 2.25 MiB | 455× |
| 13 | 16 GiB | 3.25 MiB | 5,041× |
| 24 | 32 TiB | 6 MiB | 5.6 million× |

**At S = 3 the whole-file branch still fires, and that is unchanged, intended
behaviour**: a file between the 256 KiB floor and 768 KiB is read once, whole,
exactly as it is today. The formula returns 3 for everything under 16 MiB, so
nothing about that band moves.

**The margin is large but it is implicit**, and it rests on a constant (16 MiB) a
future tuning pass would plausibly lower. The implementation must make it
explicit with an assertion or a comment carrying the arithmetic, so the branch
cannot silently flip.

### The degenerate-input hazard

`floor(log2(Length / 16 MiB))` is `-Infinity` at `Length = 0`, and casting that to
`[int]` does not yield the clamp's floor — it faults or wraps. In the shipped
call path this is unreachable, because `Measure-SampleCompressibility` returns
`$null` for `$length -le 0` (`Engine.psm1:4694`) before any geometry is computed,
and the probe only runs at all above the 256 KiB floor. But `Get-ProbeWindowCount`
is specified above as a **pure, independently testable** function, so it must
handle zero and negative lengths by returning the floor of 3 rather than by
relying on a guard in its only current caller. Verified on this box: the raw
expression yields `-Infinity` at `Length = 0` and `-3` at exactly 256 KiB, both of
which the clamp must absorb.

## 5. Traceability

| id | action |
|---|---|
| SR-081 | AMEND: the probe's window count is a function of length, not a constant. The pure decision function's signature is unchanged. |
| LLR-086 | AMEND: it currently pins the shell at "3 windows"; it must state the formula, the three new constants, and the short-file coupling margin. |
| TC-223 | AMEND, two arms, both **without** an explicit `-Samples`: (a) the defect's shape — a file long enough to earn more than three windows, carrying compressible head and tail over an incompressible body, must resolve **raw**, asserting `Windows.Count` as well as the verdict; (b) an explicit `-Samples` still overrides the derived count. |
| TC-NEW-1 | ADD, Unit: `Get-ProbeWindowCount` over a size ladder pinning just-below / at / just-above **every** power-of-two transition — 16 MiB and 32 MiB especially — plus both clamp ends and the degenerate inputs 0 and negative. |
| TC-NEW-2 | ADD, Unit: the short-file coupling — assert that for every window count the formula can return, the size that earns it exceeds the whole-file-read trip point. |

**Why TC-223 must drop `-Samples`.** Every existing arm passes the count
explicitly, and the §6 experiment does too. A fixture that supplies its own count
proves the *geometry* works and proves nothing about the *default*: it would pass
unchanged if the implementation forgot to call `Get-ProbeWindowCount` at all, or
put the breakpoint one power of two off, and production would still sample three
windows. The regression arm has to exercise the path production takes.

No kit revision. The probe lives in the Engine, which is not bundled into the
restore kit, and no encoding format or filename grammar changes: the `.7z`
container, the hash-size naming rule and the manifest's 9-column schema are all
untouched, so every existing store stays readable by the same kit.

**But new objects can come out differently, and that is the point of the change.**
For a first write the verdict picks `.7z` or the owner's extension
(`Engine.psm1:5563`), which sets the stored object's **name**, and it sets the
manifest's `Compressed` value (`Engine.psm1:5646`). A file that would have been
stored `.7z` before this change may be stored raw after it. What is guaranteed is
narrower and worth stating exactly:

- **Existing objects are never re-formed.** A `(hash,length)` already in the store
  is adopted without probing at all (`Engine.psm1:5515`), so no run rewrites what
  it already holds.
- **Restore is unaffected** in both directions, because the stored form is read
  from the row and the name, never inferred.
- **The stored form is no longer stable across builds for the same bytes.** Two
  stores built from one source by the old and new builds can legitimately differ
  in form, name and `Compressed` for the same file. Any test that pins an
  expected `DataPath` for a large fixture must be re-checked.

## 6. Verification

The review's §7 flags the one thing nobody has measured: the projected window
ratios in Option A **assume interior windows read like the observed middle
window**. That is plausible for video payload and unproven for the ISOs, which is
exactly where a false negative would cost a real saving.

`scripts/probe-window-experiment.ps1` (written 2026-09-05, uncommitted) runs that
experiment. It re-probes real files at 3, 8, 13 and 24 windows through the
**shipped** function and scores each geometry against the realised 7-Zip ratio,
which §1d already supplies as ground truth. It is measurement only: it imports
the Engine, writes no object and touches no store.

**It has not been run on the hub.** This dev box cannot reach it — the `homehub`
alias does not resolve here and both addresses in `known_hosts` refuse the
operator key. The script has been exercised only on synthetic files:

| windows | incompressible body, compressible tail | compressible throughout |
|---:|---|---|
| 3 | wrong, compresses | correct |
| 8 | wrong, compresses | correct |
| 13 | correct, stays raw | correct |
| 24 | correct, stays raw | correct |

That reproduces the review's predicted behaviour but proves nothing about the
library. **Synthetic bytes are precisely the assumption §7 says is unproven.**

**What this experiment cannot do.** It passes `-Samples` explicitly, by design —
that is how it compares geometries. So it validates the *geometry* and is blind to
the *wiring*: it would report success unchanged if the implementation never called
`Get-ProbeWindowCount`, put a breakpoint one power of two off, or silently kept
the default at three. That gap is why TC-223's new arms in §5 must run without an
explicit `-Samples`. The experiment chooses the number; the test cases prove
production chooses it too.

## 7. Open questions for the Owner

1. **Does the hub experiment gate the code change, or run beside it?** The
   experiment needs hub access this session does not have. Landing the change
   without it means shipping on the review's arithmetic rather than on measured
   interior windows.
2. **The formula's three constants.** Base 16 MiB, floor 3, ceiling 24 come from
   the review and are not themselves measured. The experiment would inform them.
3. **Is ~37 minutes on the full run acceptable** for the ~27 hours it recovers?
   The plan assumes yes; the number is 7× the review's own figure, so it is worth
   an explicit ruling rather than an inherited one.
4. **Work package number.** WP18 is assumed here.

---

## 8. Pre-implementation review — 2026-09-05

Independent adversarial review by **Codex CLI at medium reasoning effort**,
read-only, before any code was written.

**Model deviation, recorded as WP17's was.** The Owner asked for `astra` at
medium. This ChatGPT account cannot run it:

```
ERROR: {"type":"error","status":400,"error":{"type":"invalid_request_error",
"message":"The 'astra' model is not supported when using Codex with a ChatGPT account."}}
```

`terra` was refused the same way on 2026-09-01. The account default
`gpt-5.6-sol` reviewed instead, at the requested medium effort.

**Verdict: no P0. Two P1 and two P2, all accepted and folded in above.**

| id | finding | disposition |
|---|---|---|
| P1-1 | The 16 MiB base is not where the count first exceeds three. At exactly 16 MiB the quotient is 1 and `log2(1) = 0`, so the formula returns 3; the first bump to 4 is at **32 MiB**. Every "≥ 16 MiB qualifies" statement in §2 and §3c was wrong, and the review's 987-file cohort is counted at the wrong boundary. | **Accepted.** §2 gains the regime ladder and the corrected table; §3c restates 987 as a conservative upper bound and hands the exact ≥ 32 MiB count to the hub session. |
| P1-2 | The §6 experiment passes `-Samples` explicitly, so nothing in the stated verification would catch the implementation failing to call `Get-ProbeWindowCount`, an off-by-one breakpoint, or the default silently staying at three. | **Accepted.** TC-223's arms now run **without** `-Samples` and assert `Windows.Count`; TC-NEW-1 pins every power-of-two transition plus zero and negative; §6 states the experiment's blind spot outright. |
| P2-1 | "Nothing about a stored object's format changes" overstated the invariant. A first write can now choose a different form, so `DataPath` (`Engine.psm1:5563`) and `Compressed` (`Engine.psm1:5646`) can differ from what the old build would have written. | **Accepted.** §5 now separates what is guaranteed (existing objects never re-formed, restore unaffected, no kit revision) from what genuinely changes, and flags that stored form is no longer stable across builds for the same bytes. |
| P2-2 | Adding `Get-ProbeWindowCount` moves the AST-generated module map and `docs/architecture.md`, which `check.ps1` fails on when stale. The implementation steps omitted the regeneration. | **Accepted.** §4 gains step 5. |

**Confirmed with no finding**, which is worth recording so it is not
re-investigated: the short-file coupling and its 32× margin; the §3a calibration
correction (27.6 ms over 11 files × 3 windows ≈ 0.84 ms/window, so the review's
"28 ms per sample" is a misreading); the §3c arithmetic (987/24,413 = 4.043%,
extrapolating to 7,347 files and 36.6 minutes, 7.44× the review's figure); and
the probe's stability witnesses, single buffer allocation, `ReadBytes`
accounting, group memoization and DEBUG line, none of which the longer probe
disturbs.
