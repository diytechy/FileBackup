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
is what a corpus needs; §7 regenerates the selection on any library.

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

**132 GiB of MP4 was compressed for a 5.7% mean saving** — the single largest
pool of wasted effort, and the one a per-extension prior would fix outright.
`hdr`, `sup`, `pdf` and `ppt` are why a blanket "skip media-ish things" rule is
too blunt.

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

## 6. What this corpus cannot answer

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

## 7. Regenerating the join

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
