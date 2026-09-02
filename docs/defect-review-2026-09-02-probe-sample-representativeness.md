# Review — the compressibility probe's three windows land on container metadata, and 57% of the copy phase is spent compressing files it already knew were incompressible

**Found:** 2026-09-02, on the real HomeHub production hub, by watching the **first
whole-library pass that has ever reached the copy phase** — the run is still going as this
is written. Not found by code reading: found because the copy phase was running at 5 MiB/s
when the hashing phase had just sustained 75 MiB/s on the same drive, and the question
*"where is the other 93% of the throughput going?"* had a much more specific answer than
"compression is slow".

**Companion to the 2026-08-31 set**, and a direct descendant of one of them:

| document | subject |
|---|---|
| `defect-review-2026-08-31-compressibility-by-extension.md` | compression chosen by extension — the defect SR-081's probe was built to fix |
| `defect-review-2026-08-31-run-observability.md` | the hashing phase emits nothing |
| **this one** | the probe SR-081 replaced it with samples the three least representative parts of a media file |

**The probe is a large improvement and this review does not argue otherwise.** It
correctly diverted 10,429 files — 43% of everything stored so far — away from 7-Zip at a
cost of 0.55 s each. The finding is narrower: **its 3-window geometry is biased for exactly
the file shapes that cost the most to get wrong.**

**Severity:** cost, not correctness. Every byte is stored and restorable, at `-mx=5`, with
`Compressed` and the stored form in agreement. The output is right; the price is wrong.
**On this dataset the price is 4.56 hours of the first 8 to save 1.88 GiB, on a volume with
5.5 TB free.**

---

## Summary

| | Finding | One line |
|---|---|---|
| **P-1** | The three windows are at offsets 0, middle, and EOF−256 KiB — two of the three places a media container keeps its metadata | Matroska puts SeekHead/Tracks/Tags at the head and Cues at the tail; a non-faststart MP4 puts `moov` at the tail. Head and tail are structurally the *least* representative bytes of a video file, and the probe weights them 2:1 against the one window that samples payload. |
| **P-2** | When the middle window says incompressible, the file is incompressible — and the aggregate overrides it | **407 files whose middle window read ≥ 0.95 consumed 4.56 h — 76% of all compression time and 57% of the entire copy phase — to save 1.88 GiB (3.05%).** The other 912 compressed files saved 7.30 GiB in 1.47 h. That is 0.41 GiB/h versus 5.0 GiB/h: a **12× difference in return**, on the one signal the probe already has in hand. |
| **P-3** | The cost is concentrated in a handful of files, and it is enormous per file | 65 files — 0.3% of the run — consumed 67.4% of the elapsed time. The worst: a 19.98 GiB MKV, `windows=0.62,0.992,0.707`, **87.1 minutes to save 1.5%** (3.6 MiB saved per minute of CPU). |
| **P-4** | `windows=1,1,0.x` is a reliable signature of zero benefit | Seven observed instances of head and middle both reading ≥ 0.98 with only the tail low. **Realised saving: 0.0% in every one.** Between 4.2 and 16.3 minutes each, ~64 minutes total, for nothing. |
| **P-5** | The probe itself is NOT the cost, and no fix should slow it down | `ProbeIncompressible` averages 0.548 s/file over 10,429 files — 19.8% of the clock for 43% of the files, at 18.4 MiB/s. The probe pays for itself many times over. The cost is 7-Zip running on what the probe waves through. |

---

## 1. The measurement

### 1a. Provenance

| | |
|---|---|
| Run | `RunId=333c06fb-afde-45db-9495-16759abfd090`, started `2026-09-02T00:00:49Z` |
| Build | kit revision 12, FileBackup `4b809d1`, container `filebackup:local` |
| Level | `FILEBACKUP_7Z_LEVEL=5` (HomeHub ruling, 2026-09-01) |
| Probe mode | `always` (the shipped default; the set config carries no `CompressProbe` key) |
| Source | `/srv/library`, 1.10 TiB, 181,721 files to store, 225,808 in the source manifest |
| Window analysed | the first **8.01 h** of the copy phase — 24,413 files, 13.4% of the run |

Every number below comes from the run's own `compress-decision` DEBUG lines joined against
`stat` of the objects those decisions produced. Per-file wall clock is the interval between
consecutive `compress-decision` lines, which accounts for 8.01 h of the 8.35 h elapsed —
the residual is process start and the pre-backup manifest save.

### 1b. Where the copy phase's time goes

| verdict | files | share of files | avg s/file | avg size | throughput | **share of clock** |
|---|---|---|---|---|---|---|
| `ProbeIncompressible` | 10,429 | 42.7% | 0.548 | 10.06 MiB | 18.36 MiB/s | 19.8% |
| **`ProbeCompressible`** | **1,319** | **5.4%** | **16.455** | **63.35 MiB** | **3.85 MiB/s** | **75.2%** |
| `BelowFloor` | 12,665 | 51.9% | 0.113 | 0.04 MiB | — | 4.9% |

Two facts sit in that table. A raw copy runs at **18.36 MiB/s** and compression runs at
**3.85 MiB/s** — a 4.8× penalty — and the 5.4% of files paying it own three quarters of the
clock. At the raw-copy rate the whole 1.10 TiB would be a **~17 hour** job; the projected
finish with compression is **~58 hours**.

### 1c. What the compression actually bought

Joining every `ProbeCompressible` decision to the size of the object it produced:

| cohort | files | time | source | saved | rate of return |
|---|---|---|---|---|---|
| all `ProbeCompressible` | 1,319 | 6.03 h | 81.6 GiB | 9.18 GiB (11.2%) | 26.0 MiB/min |
| **of which middle window ≥ 0.95** | **407** | **4.56 h** | **61.6 GiB** | **1.88 GiB (3.05%)** | **7.0 MiB/min** |
| the remaining 912 | 912 | 1.47 h | 20.0 GiB | 7.30 GiB | 84.7 MiB/min |
| of which ≥ 1 GiB | 14 | 3.67 h | — | 4.13 GiB | — |

**4.56 of the first 8.01 hours went to files whose middle window had already reported the
body incompressible.** That is 57% of the copy phase for a 3% saving.

### 1d. The individual files, with their window vectors

Every `ProbeCompressible` file that took over two minutes, with the realised outcome:

| time | in → out | saved | MiB saved/min | `windows=` |
|---|---|---|---|---|
| 87.1 min | 19.98 → 19.67 GiB | **1.5%** | 3.6 | `0.62,0.992,0.707` |
| 31.8 min | 7.86 → 6.87 GiB | 12.6% | 31.8 | `0.002,0.676,0` |
| 20.4 min | 4.11 → 2.60 GiB | 36.7% | 75.5 | `0.021,0.452,0` |
| 18.4 min | 4.20 → 3.39 GiB | 19.3% | 45.3 | `0.021,0.976,0.892` |
| 16.3 min | 3.80 → 3.80 GiB | **0.0%** | 0.0 | `0,1,0.336` |
| 9.7 min | 2.25 → 2.25 GiB | **0.0%** | 0.0 | `1,1,0.444` |
| 5.4 min | 1.26 → 1.26 GiB | **0.0%** | 0.0 | `0.985,1,0.611` |
| 5.4 min | 1.24 → 1.24 GiB | **0.0%** | 0.0 | `1,1,0.362` |
| 4.9 min | 1.08 → 1.08 GiB | 0.2% | 0.4 | `1,1,0.315` |
| 4.9 min | 1.08 → 1.08 GiB | 0.0% | 0.1 | `0.276,1,1` |
| 4.5 min | 1.03 → 1.03 GiB | 0.2% | 0.4 | `1,1,0.3` |
| 4.4 min | 1.02 → 1.02 GiB | **0.0%** | 0.0 | `1,1,0.514` |
| 4.4 min | 1.02 → 1.02 GiB | **0.0%** | 0.0 | `1,1,0.462` |
| 4.2 min | 0.95 → 0.95 GiB | **0.0%** | 0.0 | `1,1,0.436` |

The pattern is not subtle. **Read the middle column of `windows=` and you have predicted
the outcome**: `0.976`, `0.992` and `1` produce 0–1.5% savings; `0.452` and `0.676` produce
12.6–36.7%.

---

## 2. The mechanism

`Measure-SampleCompressibility` (`Modules/FileBackup.Engine.psm1:4575`) samples with this
geometry, stated in its own doc comment:

> Otherwise `Samples` windows of `SampleBytes` are read at Int64 offsets evenly spaced
> across the file — for the shipped `Samples = 3` those are exactly `0`,
> `floor((len - SampleBytes) / 2)` and `len - SampleBytes`.

With the shipped constants (`Engine.psm1:4570-4573`):

```
$script:CompressProbeThreshold   = 0.10      # compress when ratio <= 0.90
$script:CompressProbeMinBytes    = 262144    # 256 KiB floor
$script:CompressProbeSampleBytes = 262144    # 256 KiB per window
$script:CompressProbeSampleCount = 3         # start, middle, end
```

For the 19.98 GiB MKV that is **768 KiB sampled out of 21,454,398,564 — one part in
27,000** — and two of those three parts are chosen at precisely the offsets where a media
container is guaranteed *not* to hold payload:

- **Matroska/MKV**: `EBML` header, `SeekHead`, `Info`, `Tracks`, `Tags` at the head; the
  `Cues` index almost always at the tail. Both are structured, repetitive, highly
  compressible, and both are a rounding error of the file's bytes.
- **MP4/MOV not written `faststart`**: the `moov` atom — sample tables, chunk offsets,
  thousands of near-identical 32-bit integers — sits at the **end**. That is the
  `windows=1,1,0.3` family in §1d exactly: head is payload (1.0), middle is payload (1.0),
  tail is the index (0.3), and the index wins the vote.

Rule 6 in `Resolve-CompressionDecision` is an unweighted aggregate over the sampled bytes:

```powershell
if ($CompressedBytes -le ((1.0 - $Threshold) * $SampledBytes)) {
    return (& $verdict $true 'ProbeCompressible')
}
```

Because every window is the same size, that aggregate is the **arithmetic mean of the three
window ratios**. So `(1 + 1 + 0.444) / 3 = 0.815 ≤ 0.90` → compress 2.25 GiB → save nothing.
One 256 KiB window of index outvotes two windows of payload, and 512 KiB of evidence
commits the run to nine minutes of work.

The doc comment anticipates the single-window version of this failure and dismisses it
correctly:

> a multi-gigabyte random file with a 64 KiB text head reads ~0.93 and stays raw
> (the defect review's own failure mode)

That reasoning holds for **one** unrepresentative window out of three. It does not hold for
**two**, and head-plus-tail is the common case, not the exotic one — the review that
motivated SR-081 was itself about video containers.

---

## 3. Why this is a sampling problem and not a threshold problem

It is tempting to read §1d and conclude the threshold is simply too loose. It is not that
simple, and the data says so in both directions:

- **`0,1,0.336` — 3.80 GiB, 16.3 minutes, 0.0% saved.** One window of pure zeros at the
  head. Aggregate 0.445, less than half the threshold, and the file did not compress at
  all. No threshold that keeps the genuine wins would have caught this.
- **`0.021,0.976,0.892` — 4.20 GiB, 19.3% saved.** The *middle* window said incompressible
  and the file compressed well anyway, because an ISO's padding is distributed rather than
  central. A middle-window-only rule would have wrongly skipped a genuine 0.81 GiB win.

Both are the same underlying fault: **768 KiB cannot characterise a multi-gigabyte
heterogeneous file**, and which way it errs depends on where the structure happens to sit.
More evidence fixes both; a different threshold on the same three numbers trades one error
class for the other.

---

## 4. Options

Arithmetic below applies each option to the observed `windows=` vectors, assuming interior
windows read as the observed middle window does (the honest assumption for payload).

### Option A — scale the window count with file size *(recommended)*

Keep the offsets evenly spaced; raise `Samples` for large files, e.g.
`Samples = clamp(3, 24, 3 + floor(log2(Length / 16 MiB)))` — 3 windows below 16 MiB,
9 at 1 GiB, 13 at 20 GiB.

| file | 3 windows | ~8–13 windows | realised | verdict |
|---|---|---|---|---|
| 19.98 GiB MKV | 0.773 → compress | `(0.62 + 11×0.99 + 0.707)/13 = 0.940` → **raw** | 1.5% | fixed |
| 2.25 GiB MP4 | 0.815 → compress | `(1 + 8×1 + 0.444)/10 = 0.944` → **raw** | 0.0% | fixed |
| 1.02 GiB MP4 | 0.838 → compress | `(1 + 7×1 + 0.514)/9 = 0.946` → **raw** | 0.0% | fixed |
| 3.80 GiB `0,1,0.336` | 0.445 → compress | `(0 + 9×1 + 0.336)/11 = 0.849` → **raw** | 0.0% | fixed |
| 4.20 GiB ISO | 0.63 → compress | more windows find more distributed padding | 19.3% | preserved |
| 4.11 GiB | 0.158 → compress | middle already 0.452 | 36.7% | preserved |

**Cost.** Brotli-Fastest is quoted at ~28 ms per 256 KiB window in the codec calibration, so
13 windows is ~364 ms against ~84 ms. That cost lands only on files above the floor, and it
scales *with* the thing being protected: an extra 280 ms to avoid an 87-minute mistake is
four orders of magnitude of headroom. Keeping small files at 3 windows means the 12,665
`BelowFloor` and the bulk of the 10,429 `ProbeIncompressible` files see no change at all
(P-5).

This is the option that improves accuracy in **both** directions, which is why it is the
recommendation.

### Option B — exclude the extreme head and tail for large files

Sample the interior only — offsets spread across `[SampleBytes, Length − 2×SampleBytes]` —
once `Length` is above some multiple of the window size.

Sharper than Option A on the media cases (the MKV becomes ~0.99, an unambiguous raw), and
cheap. But it deliberately blinds the probe to a real pattern: archives and disk images
often carry their most compressible content exactly at the head. `0.021,0.976,0.892` saved
19.3% and its head window was the strongest evidence. **Better combined with A than used
alone** — more interior windows, with head and tail retained but no longer 67% of the vote.

### Option C — trimmed statistic instead of the mean

Median, or drop the single most compressible window. On `0.62,0.992,0.707` the median is
0.707 → still compresses. **Does not fix the headline case**, because with three samples the
median is just the middle-ranked value, not the middle-*positioned* one. Becomes viable
only once A supplies enough windows for a trimmed mean to mean anything.

### Option D — cost-aware threshold that tightens with size

Require a stronger ratio as the file grows, since 7-Zip's cost scales with bytes while the
benefit is a percentage: e.g. `0.90` under 256 MiB, `0.75` above 1 GiB.

Applied to §1d it fixes 8 of the 10 false positives and keeps all three true positives — but
it does **not** fix `0,1,0.336` (0.445 passes any threshold that keeps the 0.63 ISO), and
alone it can only ever suppress work, never find work the sample missed. Worth considering
**after** A as a second-order guard; the projected-saving-versus-CPU-seconds framing is the
honest one, and it is a policy question rather than a sampling one.

### Option E — do nothing

Defensible for a steady state. This cost is dominated by the **first** pass: 24,414 objects
in, the store is content-addressed, and an unchanged 20 GiB MKV is never re-compressed. On
this library the recurring cost is small.

It is rejected for two reasons. Every *new* large video pays the full price on the night it
arrives — a single 20 GiB import is 87 minutes of a nightly window. And the first pass is
precisely the one users judge the product by; 58 hours instead of ~25 is the difference
between "slow" and "did it hang?".

---

## 5. Recommendation

**Option A, with the head/tail de-weighting of Option B folded in as the window count
rises.** It is the only change supported in both error directions by the measurements, it
needs no configuration key, no `ConfigVersion` change and no restore-side change, and its
cost falls only on the files whose decisions are expensive.

Explicitly **not** recommended as the primary fix:

- **Lowering `FILEBACKUP_7Z_LEVEL` further.** `mx1` would make the *wrong work* faster. The
  87 minutes on the MKV is not a level problem; that file should never have reached 7-Zip.
- **Adding `.mkv`/`.mp4` to `NonCompressibleExtensions`.** They are already there. The probe
  runs in mode `always`, which is the shipped default, and `always` deliberately overrides
  the list — that is SR-081's whole point. Extending the list does nothing while the mode is
  `always`, and reverting to `excluded-extensions` re-opens the 2026-08-31 defect.

---

## 6. What it would have saved on this run

Extrapolating the measured cohort to the full 181,721 files at the same mix:

Those 407 files would still have to be **copied**, at the measured raw rate of 18.36 MiB/s
— 61.6 GiB is 0.95 h — so the recoverable time is the difference, not the whole 4.56 h:

| | first 8.01 h measured | projected full run |
|---|---|---|
| time spent on middle-window-≥0.95 files | 4.56 h | ~34 h |
| time the same files would take copied raw | 0.95 h | ~7 h |
| **net time recoverable** | **3.61 h** | **~27 h** |
| saving bought by that time | 1.88 GiB | ~14 GiB |
| projected total run | — | ~58 h |
| projected with Option A | — | **~31 h** |

Roughly **a day of the projected two and a half days**, to keep about 14 GiB on a volume
with 5,515 GB free.

---

## 7. Verified / not verified

**Verified by measurement on production hardware:**

- The per-verdict time split, from 24,413 timed decisions (§1b).
- The realised in/out sizes, by `stat` on the objects the decisions produced (§1c, §1d).
- That the middle window predicts the outcome, across 1,319 compressed files (§1c).
- That `windows=1,1,0.x` yielded 0.0% in all seven observed instances (§1d).
- That the probe itself is cheap: 0.548 s/file over 10,429 files (§1b).

**Not verified — would need a deliberate experiment:**

- The projected window ratios in §4 Option A. Interior windows are *assumed* to read like
  the observed middle window. Plausible for video payload; unproven for the ISOs, which is
  precisely where a false negative would cost a real saving. **Re-probing a handful of the
  §1d files at 8/13/24 windows and comparing against their now-known realised ratios is a
  cheap, decisive experiment** — the realised sizes in §1d are the ground truth to score
  against, and this review's data set already supplies them.
- Whether the `-mx=5` throughput of 3.85 MiB/s holds at other levels. Not needed for this
  finding, which is about what reaches 7-Zip, not how fast it runs.
- Any claim about non-media large files. This library is video-heavy; a code or VM-image
  corpus may sit differently against the same geometry.

---

## 8. Non-findings, recorded so they are not re-investigated

- **The probe is not slow.** P-5. Any fix that makes probing meaningfully more expensive per
  small file is a worse trade than the defect.
- **7-Zip is not misbehaving.** It compressed what it was given, at the level it was given,
  and produced correct output every time. LZMA2 emitting store-mode chunks caps the *space*
  penalty at ~0%, which is why the 0.0%-saved rows are 0.0% and not negative — the same
  finding as `defect-review-2026-08-31…-by-extension.md` §3. It does not cap the time.
- **The threshold is not obviously wrong.** §3. `0.90` is defensible on three good samples;
  the samples are the problem.
- **`BelowFloor` is not implicated.** 12,665 files, 4.9% of the clock, 0.113 s each. The
  256 KiB floor is doing its job.
- **This is not the stale-`Temp` defect.** That lock was cleared by hand before this run
  started; staging was taken cleanly at `00:00:51` with a live heartbeat throughout.
- **HomeHub needs no change.** `FILEBACKUP_7Z_LEVEL=5` is orthogonal and stays. The fix is
  entirely inside `Measure-SampleCompressibility`'s geometry.
