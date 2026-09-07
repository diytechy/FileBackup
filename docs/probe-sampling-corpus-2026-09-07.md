# A corpus for designing the compressibility probe's sampling and windowing

**Purpose.** `defect-review-2026-09-02-probe-sample-representativeness.md` argued
from 24,413 decisions in the first 8 hours of one run that the 3-window geometry
is biased. This document supplies the **evidence base and the test corpus** for
fixing it: 154,647 probe decisions from the whole of that run, joined against
what the store *actually achieved*, and a set of file profiles chosen so any
proposed sampling rule can be scored before it ships.

**The join is what makes this different from the probe review.** That review had
the probe's own windows and its verdict. This has, for every row, the **realised
ratio** — stored bytes over original bytes — so a rule can be graded against
outcomes rather than against the prediction it is trying to replace.

**Files are identified by profile, not by path.** The library is a household's,
and the exact paths carry family names and personal content. Every exemplar below
is pinned by exact byte length, format, probe windows and realised ratio, which
is what a corpus needs; §9 regenerates the selection on any library.

---

## 1. Provenance

| | |
|---|---|
| Run | first whole-library pass, `2026-09-02T00:00:49Z` → `2026-09-04T02:02:46Z` |
| Level | `FILEBACKUP_7Z_LEVEL=5`, probe mode `always` |
| Decisions joined | **154,647** of 181,721 rows |
| Realised ratio | stored object size ÷ manifest `Length`, from one pool listing |

Verdict split across the whole run:

| Verdict | Count |
|---|---|
| `BelowFloor` (never probed) | 80,282 |
| `ProbeIncompressible` (probed, stored raw) | 65,832 |
| `ProbeCompressible` (probed, 7-Zip ran) | **8,534** |

**What the 7-Zip work bought:** 437.51 GiB in, **72.17 GiB saved — 16.5%**.

---

## 2. The one-line finding the corpus exists to fix

**The middle window is a good predictor and the aggregate dilutes it.** Realised
ratio bucketed by each:

| Middle window | n | mean realised | | Aggregate probe ratio | n | mean realised |
|---|---|---|---|---|---|---|
| 0.0–0.1 | 287 | **0.083** | | 0.0–0.1 | 456 | 0.023 |
| 0.4–0.5 | 269 | 0.336 | | 0.4–0.5 | 630 | 0.352 |
| 0.8–0.9 | 552 | 0.666 | | 0.8–0.9 | **4,018** | 0.884 |
| 0.9–1.0 | 822 | 0.837 | | 0.9–1.0 | 42 | 0.896 |
| **≥ 1.0** | **2,018** | **0.948** | | — | | |

Both are monotonic, so both carry signal. The difference is **where the mass
sits**: the aggregate piles 4,018 files into one bucket averaging 0.884, while
the middle window isolates **2,018 files that average 0.948** — a 5% saving for
full 7-Zip cost. A rule of *"middle ≥ 1.0 ⇒ store raw"* diverts those 2,018
without touching anything below.

And the P-4 signature from the probe review holds on the full run:

| Window shape | n | mean realised |
|---|---|---|
| `1,1,*` | 185 | **0.944** |
| everything else | 8,349 | 0.632 |

---

## 3. Design questions a sampling rule must answer

1. Where should windows land, given that head and tail are container metadata?
2. How many windows, and should the count scale with size?
3. How are windows combined — mean, min, median, or *middle-dominant*?
4. What threshold diverts to raw storage, and does it vary by size?
5. Does the rule keep the wins in §4d while dropping the waste in §4a–4c?

---

## 4. The corpus

Eight profiles. **The first four are the traps; the fifth is the one a naive fix
breaks.** All lengths are exact bytes; `win=` is the probe's three windows in
order (head, middle, tail); `real=` is the realised ratio.

### 4a. Nintendo WUA — the `1,1,*` signature, zero benefit, enormous cost

| Length | probe | win | real |
|---|---|---|---|
| 13,820,260,960 | 0.756 | `1,1,0.269` | **1.000** |
| 13,660,330,872 | 0.863 | `1,1,0.589` | 0.999 |
| 4,559,783,561 | 0.777 | `1,1,0.33` | 0.988 |

Head and middle both read incompressible; only the tail is low, and the tail is
the container's trailing structure. The aggregate believes the tail. **~32 GiB
compressed to save nothing.** Any candidate rule that still compresses these is
not a fix.

### 4b. Matroska film remuxes — the tail drags a correct middle down

| Length | probe | win | real |
|---|---|---|---|
| 21,454,398,564 | 0.773 | `0.62,0.992,0.707` | **0.985** |
| 20,628,305,972 | 0.752 | `0.64,1,0.617` | 0.985 |

Middle reads 0.99–1.00 and is right. Head and tail read 0.6–0.7 because MKV keeps
SeekHead/Tracks/Tags at the head and Cues at the tail — **structured, repetitive,
and not representative of a single frame of video.** Two of three windows are
measuring the index.

### 4c. ISO 9660 — the head window is nearly always a lie

| Length | probe | win | real |
|---|---|---|---|
| 7,271,940,096 | 0.254 | `0.003,0,0.76` | 0.675 |
| 8,533,671,936 | 0.365 | `0.021,0.782,0.294` | 0.794 |
| 4,410,671,104 | 0.158 | `0.021,0.452,0` | 0.633 |
| 2,693,955,584 | 0.132 | `0.021,0.375,0` | 0.280 |

**Every ISO head window reads 0.003–0.021.** The ISO 9660 system area and volume
descriptors are mostly zero padding, so the head compresses ~50:1 and tells you
nothing about the payload. These are also the cases where the probe most
*under*-predicts the realised ratio — it expects 0.13–0.37 and gets 0.28–0.79.

### 4d. Consumer phone video — where the head lies in the other direction

| Length | probe | win | real | note |
|---|---|---|---|---|
| 4,080,926,352 | 0.445 | `0,1,0.336` | **1.000** | head reads **0** |
| 3,274,483,230 | 0.774 | `1,1,0.322` | 1.000 | |
| 3,286,919,234 | 0.839 | `1,1,0.518` | 0.998 | |

The first is the probe's worst single call in the run: a head window of **0** —
zero-padded container preamble — pulls the aggregate to 0.445 and buys a full
7-Zip pass on a file that compresses by **nothing at all**. The middle window
said 1.

### 4e. The counter-case a middle-only rule must not break

| Length | probe | win | real | saved |
|---|---|---|---|---|
| 1,657,667,590 | 0.494 | `1,0.08,0.401` | **0.137** | 1,364 MiB |
| 21,165,363,450 | 0.195 | `0.586,0,0` | 0.430 | 11,501 MiB |

**The first row is the whole argument against trusting the head.** Its head reads
1 — perfectly incompressible — and the file compresses to 13.7%. A head-weighted
or min-of-windows rule loses 1.36 GiB on this one file. It is a screen-recorded
presentation: a real and common shape whose opening frames are dense and whose
body is near-static.

### 4f. Already-compressed containers — must stay waved through

65,832 rows took `ProbeIncompressible` and were stored raw. Any candidate rule is
scored on **not regressing these into 7-Zip**. Include several `.zip`, `.7z`,
`.gz`, `.zst`, `.jpg`, `.mp3` spanning 1 MiB → 5 GiB.

### 4g. The size bands, including two thresholds that matter

- around the **probe floor** (768 KiB — three windows vs one whole-file sample);
- around **4,069,416,960 bytes**, the tmpfs cap in
  `defect-review-2026-09-06-…-stat-storm.md` C-12 — not a probe concern, but any
  corpus run through a real `verify -Deep` will trip it, and a bench that does
  not know why will misread the result as corruption.

### 4h. Formats where compression genuinely pays

Mean realised ratio by extension, `ProbeCompressible` rows, n ≥ 30:

| ext | n | mean realised | total |
|---|---|---|---|
| wma | 297 | 0.949 | 1.1 GiB |
| **mp4** | **381** | **0.943** | **132.0 GiB** |
| avi | 64 | 0.934 | 17.7 GiB |
| mp3 | 233 | 0.910 | 3.6 GiB |
| jpg | 2,761 | 0.864 | 17.6 GiB |
| iso | 37 | 0.813 | 106.1 GiB |
| pdf | 480 | 0.692 | 1.9 GiB |
| ppt | 105 | 0.697 | 0.3 GiB |
| hdr | 141 | 0.573 | 0.6 GiB |
| sup | 95 | 0.527 | 1.3 GiB |

**132 GiB of MP4 was compressed for a 5.7% mean saving** — ~7.5 GiB, which is a
real return and not waste, bought with a full LZMA2 pass per file. It is the
largest pool of *slow* saving rather than of wasted saving, and the distinction
matters: §4a-4d are effort for NO return and are defects; this is effort for a
small return and is a scheduling trade. `hdr`, `sup`, `pdf` and `ppt` are why a
blanket "skip media-ish things" rule is too blunt.

---

## 5. How to score a candidate rule

For each row in the join, the candidate emits compress or raw. Then:

| Metric | Meaning |
|---|---|
| **Bytes wasted** | Σ length × (1 − realised) ≈ 0 where it compressed. Baseline: 415 files at realised ≥ 0.98. |
| **Bytes lost** | Σ length × (1 − realised) for rows it now stores raw that previously won. **Must stay ~0.** |
| **7-Zip calls avoided** | Baseline 8,534. |
| **Net saving** | Baseline 72.17 GiB. |

A rule is better only if it cuts calls and wasted bytes while **bytes lost stays
near zero** — §4e is the row that will expose a rule that does not.

---


---

## 6. The recommendation — scored, not argued

The corpus was built to grade rules, so it was used. Every candidate below was
run over the **5,369** `ProbeCompressible` rows that carry three windows (the
other 3,165 fell below the 768 KiB three-window floor and got one whole-file
sample, which no windowing rule can improve). Baseline: 5,369 7-Zip invocations
on 437.51 GiB of input, realising **71.55 GiB** of saving.

`GiB out` is 7-Zip **input avoided**; `LOST` is realised saving forgone;
`ratio` is work avoided per unit of saving given up.

| Rule ⇒ store raw | skips | GiB out | LOST | kept | ratio |
|---|---|---|---|---|---|
| `median > 0.95` | 2,026 | 168.1 | **1.49** | 97.9% | **113:1** |
| **`median > 0.95` OR `middle ≥ 0.98`** | **2,407** | **263.8** | **6.53** | **90.9%** | **40:1** |
| `median > 0.90` OR `middle ≥ 0.98` | 2,597 | 266.2 | 6.83 | 90.5% | 39:1 |
| `median > 0.90` | 2,405 | 185.0 | 2.21 | 96.9% | 84:1 |
| `middle ≥ 1.00` | 2,018 | 226.0 | 5.17 | 92.8% | 44:1 |
| `middle ≥ 0.95` | 2,566 | 305.1 | 10.91 | 84.8% | 28:1 |
| `middle > 0.90` | 2,830 | 324.9 | 15.38 | 78.5% | 21:1 |

### 6a. Recommended: `median(head, middle, tail) > 0.95` **OR** `middle ≥ 0.98`

**It avoids 263.8 GiB of 7-Zip input — 60% of everything currently compressed —
for 6.53 GiB of forgone saving, keeping 90.9%.**

**The median is where most of the win comes from, and the reason is structural.**
In every trap in §4 exactly one or two of the three windows are container
metadata, and the median is robust to a minority of outliers where the mean is
not. `1,1,0.269` has median 1 and mean 0.756: the median sees two honest windows
and one index, the mean is dragged by the index. `0.021,0.452,0` — the ISO
shape — has median 0.452 against a mean of 0.158, and realised 0.633: the median
is closer. **Swapping the mean for the median changes no sampling, no I/O and no
geometry; it changes one line of arithmetic.**

**The `middle ≥ 0.98` clause exists for the one case the median cannot see:**
head *and* tail both misleading-low. The Matroska remuxes are exactly that —
`0.62,0.992,0.707`, median 0.707, so a median-only rule still compresses them,
and they realise 0.985. Two files in that shape are 42 GiB of input for ~600 MiB
of saving. The clause is deliberately at 0.98 rather than 0.95: dropping it to
0.95 buys 41 GiB more avoided work but costs 4.4 GiB more saving — a 9:1 marginal
trade against 19:1 for the step before it, which is where the frontier bends.

**Loss profile, because a total can hide a disaster.** Of the 6.53 GiB forgone,
only **3.86 GiB** comes from rows that had a real win (realised < 0.90), spread
over 391 files, and the **largest single forgone saving is 0.96 GiB** — an ISO
reading `0.021,1,0` that realises 0.745. Nothing large is thrown away; the loss
is a long tail of marginal wins.

**The §4e counter-case survives**, which was the test the rule had to pass:
`1,0.08,0.401` has median 0.401 and middle 0.08 — neither clause fires, the file
is still compressed, and its 1.36 GiB saving is kept.

### 6b. If a smaller change is wanted: `median > 0.95` alone

168.1 GiB avoided for **1.49 GiB** forgone — **113:1**, the best ratio on the
board, and 97.9% of the saving retained. It is one arithmetic change with no new
clause and no new constant, and it leaves the Matroska class uncaught. A
reasonable first step that 6a can be layered onto later.

### 6c. What this does NOT settle

The recommendation covers **how the windows are combined and at what threshold**.
It does not settle:

- **Where windows land, and how many.** Every rule above is scored on the
  *existing* head / middle / tail geometry. **§7 now measures both**, and the
  answer is larger than anything in this section: the head window's correlation
  with the outcome is **+0.059**, and moving three windows to 25/50/75% lifts
  correlation from +0.647 to +0.892 at identical cost. **Read §7 before
  implementing §6a** — placement is the bigger and cheaper win, the two are
  independent, and the numbers in this section were all computed on the old
  geometry.
- **Whether a per-extension prior would be simpler for media.** §4h: 381 MP4s,
  132 GiB, mean realised 0.943. **That is ~7.5 GiB genuinely saved, and it is not
  waste** — an earlier draft of this document called it wasted effort and that
  was wrong. The cost is *time*, not invalidity: those files each paid a full
  LZMA2 pass to give up 5.7%. A `.mp4` prior would trade that saving away for
  speed, which is a scheduling decision and not a correctness one, and it is
  offered here as a lever rather than a recommendation. **Edge conditions are
  expected**; a probe that occasionally spends effort for a small real return is
  behaving correctly, and only the cases in §4a–4d — effort for *no* return —
  are defects.


---

## 7. Window placement and count — measured, on the real library

§6c listed these as open. They are no longer open. **The head window carries
essentially no signal, and the shipped geometry spends two of its three windows
on the two worst positions on the file.**

### 7a. Method

166 files, stratified across all ten realised-ratio bands, every one ≥ 32 MiB and
already stored `Compressed=Yes` so its **realised 7-Zip ratio is known**. Each was
sampled at **21 offsets** — 0%, 5%, … 100% of `length − 256 KiB` — with the
probe's own 256 KiB window size. Ground truth is the realised ratio; the score is
how well a sampling scheme predicts it.

**The sampling compressor is zlib level 1, not the probe's Brotli(Fastest)**,
because the hub has no brotli and a production appliance was not going to be
modified for an experiment. **That substitution was then validated rather than
assumed**, against the probe's own recorded windows for the same 162 files at the
same three offsets:

| offset | corr(zlib, Brotli) | mean zlib | mean Brotli |
|---|---|---|---|
| head 0% | **+0.996** | 0.537 | 0.544 |
| middle 50% | **+0.993** | 0.623 | 0.625 |
| tail 100% | **+0.997** | 0.279 | 0.275 |

Agreement to three decimals in both correlation and level. **The two coders are
interchangeable for this purpose**, so everything below transfers to the shipped
probe without rescaling.

### 7b. Placement — the head window is noise

Correlation of a **single** window at each position against the realised ratio:

| position | corr | MAE | mean ratio |
|---|---|---|---|
| **0% (head)** | **+0.059** | 0.328 | 0.535 |
| 5% | +0.769 | 0.172 | 0.652 |
| 20% | +0.818 | 0.165 | 0.634 |
| 30% | +0.838 | 0.166 | 0.655 |
| **35%** | **+0.854** | — | — |
| 40% | +0.841 | 0.156 | 0.645 |
| 50% | +0.797 | 0.174 | 0.621 |
| 60% | +0.838 | 0.163 | 0.623 |
| 70% | +0.832 | 0.161 | 0.601 |
| 90% | +0.714 | 0.189 | 0.569 |
| **100% (tail)** | **+0.417** | 0.326 | 0.277 |

**A window at offset 0 predicts the outcome with correlation +0.059.** That is
not a weak signal, it is no signal — the head is a container header, and its
compressibility is a fact about the format, not about the file. The tail at
+0.417 is little better, and note its **mean of 0.277**: tails read as highly
compressible almost everywhere, which is exactly the bias that drags an average
downward and buys 7-Zip passes on incompressible media (§4a, §4d).

**Everything from 5% to 90% works**, peaking around 30–60%. The plateau is broad,
so precision is not required — only *staying off the ends*.

### 7c. Count — three interior windows beat twenty-one badly placed ones

Median of N evenly spaced windows, graded against realised:

| N | offsets | MAE | corr |
|---|---|---|---|
| 1 | 50% | 0.174 | +0.797 |
| **3** | **0 / 50 / 100 (shipped)** | **0.191** | **+0.647** |
| 3 | 25 / 50 / 75 | 0.144 | +0.892 |
| 5 | 0 / 25 / 50 / 75 / 100 | 0.125 | +0.850 |
| **7** | 0 / 15 / 35 / 50 / 65 / 85 / 100 | **0.114** | +0.907 |
| 9 | … | 0.116 | +0.923 |
| 11 | … | 0.122 | +0.924 |
| 21 | every 5% | 0.127 | +0.924 |

**The shipped 3-window geometry scores worse than a single window at 50%** —
0.647 against 0.797. Adding the head and tail to a good middle sample makes the
estimate *worse*, because two of the three inputs are noise and the third is
outvoted.

Correlation plateaus at **~0.92 by N=9** and does not improve at 21. MAE is best
at **N=7**. There is no case for sampling more than about nine windows.

### 7d. What to change, in order of value per unit of effort

1. **Move the windows off the ends.** Keeping three windows and placing them at
   **25 / 50 / 75%** takes correlation from **+0.647 to +0.892** — a larger gain
   than any change to the combining rule in §6, at *identical* I/O and CPU cost.
   Three seeks, three 256 KiB reads, three compressions: the same work, in
   better places.
2. **Then, if more accuracy is wanted, raise N to 5–7** interior windows for
   +0.892 → ~+0.907. This costs proportional I/O and is the only item here that
   does.
3. **Combine with the median** (§6). Placement and combination are independent
   wins: the median protects against a minority of misleading windows, and
   interior placement means fewer of them are misleading in the first place.

**Do not sample offset 0 or EOF at all.** No weighting scheme rescues a +0.059
input; the correct weight for the head window is zero, and the cheapest way to
apply that weight is not to read it.

### 7e. Limits

- **166 files, one library, one 7-Zip level.** The correlations are strong enough
  that the head/interior split is not in doubt, but exact optima (35% vs 50%) are
  not resolved at this n.
- **Files ≥ 32 MiB only.** Below that, 21 non-overlapping 256 KiB windows do not
  fit, and the probe's own floor already routes small files to a single
  whole-file sample where placement is moot.
- **`Compressed=Yes` rows only**, because those are the ones with a realised
  ratio. Files the probe waved through have no measured outcome to grade against,
  so this cannot say whether better placement would have *caught* any of them —
  only that it predicts the graded set far better.
- Still unmeasured: whether the optimum shifts with 7-Zip level, and the
  faststart/non-faststart MP4 control of §8.

## 8. What this corpus cannot answer

- **No faststart/non-faststart MP4 pair.** The probe review's P-1 turns on `moov`
  position, and nothing here confirms which layout each file has. Two synthetic
  remuxes of one source are needed; the library cannot supply the control.
- **No deliberately mixed file** — a large incompressible body with a genuinely
  compressible middle. Every §4e win is incidental.
- **One 7-Zip level only.** Everything is `-mx=5`; whether the geometry interacts
  with level is unmeasured.
- **Realised ratio is 7-Zip's outcome, not compressibility itself.** A rule
  scored here is scored against *this compressor at this level*.

---

## 9. Regenerating the join

Requires a completed run whose `compress-decision` DEBUG lines are still in the
journal, and the pool it wrote. Emits
`relpath, length, Compressed, verdict, probeRatio, windows, realisedRatio`:

```bash
B=/mnt/backup-drive/library
ls -lU "$B" | awk 'NF>=9 {n=$9; for(i=10;i<=NF;i++) n=n" "$i; print n "\t" $5}' > /tmp/objsize.tsv
awk -F'","' 'NR>1 {dp=$1; sub(/^"/,"",dp); print $2 "\t" $3 "\t" $6 "\t" dp}' "$B/MANIFEST.csv" > /tmp/mani.tsv
journalctl -u homehub-library-backup.service --no-pager \
  | grep -oP 'compress-decision: \K.*' \
  | sed -E 's/^(.*) (BelowFloor|ProbeIncompressible|ProbeCompressible) ratio=(\S+) windows=(\S+).*$/\1\t\2\t\3\t\4/' \
  | awk -F'\t' 'NF==4' | sort -u -t$'\t' -k1,1 > /tmp/probe.tsv
```

then join on `relpath`, taking `realisedRatio = objsize[dp] / length`. One pool
listing rather than a stat per row — the same lesson as C-1/C-2 in the stat-storm
review, and on this library the difference is 2.3 s against ~30 minutes.
