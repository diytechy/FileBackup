# Review — compressibility is decided by file extension, and the list misses 43% of this library

**Found:** 2026-08-31, on the real HomeHub production hub, by watching the **first
whole-library pass this product has ever run against production disks** reach its copy
phase. Not found by code reading — found because `7z` was observed burning two cores on
a file that could not benefit from it, and the question *"what else is it doing that
to?"* had a much larger answer than expected.

**Third of three companion documents from the same run**, all filed separately so each
can be ruled on alone:

| document | subject |
|---|---|
| `defect-review-2026-08-31-stale-temp-lock.md` | an externally-killed run wedges every later run |
| `defect-review-2026-08-31-run-observability.md` | the hashing phase emits nothing |
| **this one** | compression is chosen by extension, and the list is wrong for this data |

**Nothing here modifies the other two.** The only dependency runs one way and is noted
in §7: the fix considered most promising here would be computed during the phase the
observability document is about.

**Severity:** cost, not correctness. **Every byte is backed up correctly and restorably.**
The output is right; the price is wrong. On this dataset the price is **~9 days of CPU to
save ~47 GB**.

---

## Summary

| | Finding | One line |
|---|---|---|
| **C-1** | The exempt list misses `.z7` — **43% of the library** | `NonCompressibleExtensions` has 24 entries. `.z7` is not one, so 880.6 GB of already-compressed archives are re-compressed at `-mx=9` for a measured **~5%** gain, at ~20 minutes of two-core CPU per file. |
| **C-2** | 7-Zip's own guard does not help | LZMA2 emits uncompressed chunks when compression fails, so the *output* never bloats. But it decides that **after** running the match-finder. 7-Zip prevents the space penalty, **not the time penalty** — and time is the entire cost. |
| **C-3** | The same blind spot exists in both codebases | HomeHub's `backup.sh` uses the same extension-list approach (aggregated by bytes, 60% threshold) and **its list also lacks `.z7`**. This is not a divergence between the two — it is one idea, adopted twice, wrong in the same place. |

---

## 1. The measurement

### 1a. What is actually in the library

Full census of `/srv/library`, by extension, 2026-08-31 (2,063 GB total):

| ext | size | files | exempt today? |
|---|---|---|---|
| **`.z7`** | **880.6 GB** | 649 | **NO** |
| `.mp4` | 533.4 GB | 5,088 | yes |
| *(none)* | 252.9 GB | 42,940 | n/a — no extension to match |
| `.jpg` | 117.5 GB | 70,314 | yes |
| `.mkv` | 68.3 GB | 7 | yes |
| `.iso` | 47.9 GB | 25 | NO — **but see the note below; do NOT add it** |
| `.mov` | 33.3 GB | 178 | yes |
| `.zip` | 27.9 GB | 129 | yes |
| `.7z` | 19.6 GB | 56 | yes |
| `.png` | 12.2 GB | 14,722 | yes |
| `.bin` | 7.9 GB | 698 | NO |
| **`.m2ts`** | **7.9 GB** | 1 | **NO** |
| `.avi` | 5.0 GB | 180 | yes *(FileBackup only — not on HomeHub's list)* |
| **`.mca`** | **4.5 GB** | 1,799 | **NO** — Minecraft region files, zlib-compressed internally |
| `.gz` | 3.6 GB | 32,602 | yes |
| `.dng` | 3.0 GB | 139 | NO — raw camera, usually losslessly compressed |
| `.pdf` | 2.4 GB | 2,714 | NO — usually Flate-compressed internally |
| **`.esd`** | **2.3 GB** | 19 | **NO** — Windows image, already LZMA-compressed |

**`.z7` is the single largest extension in the library — larger than every video format
combined**, and it is 43% of the whole. `file(1)` confirms these are **7-Zip archives**
(`7-zip archive data, version 0.4`): the product is re-compressing 7-Zip archives with
7-Zip, at maximum settings, because the extension is `.z7` rather than the `.7z` already
on the list. `.mpg`, which prompted the original question, does not reach this table at
all; it is a rounding error. **The `.z7` miss is the finding; everything else on the "NO"
rows is secondary.**

**⚠ `.iso` IS NOT A SECOND `.z7`, AND THIS MATTERS FOR OPTION A.** `file(1)` reports
`ISO 9660 CD-ROM filesystem data` — a **filesystem container**, not a compressed format.
Its compressibility depends entirely on what is inside it, which may be anything from
already-compressed installers to highly compressible raw files. **Adding `.iso` to the
exempt list would be exactly the false-"already compressed" error described in §4** —
silent, permanent, and costing space forever. It is listed above as "not exempt today"
because that is a fact about the list, **not** a recommendation to change it.

This is the sharpest available illustration of §5's argument: **two unlisted extensions,
opposite correct answers, and the filename distinguishes them for neither.** `.z7`
should be skipped and is not; `.iso` should be measured and cannot be. A sampled probe
gets both right without anyone deciding in advance.

### 1b. What the re-compression actually buys

Six `.z7` files, source length from the run log, stored size from the pool:

| source | stored | ratio |
|---|---|---|
| 1864 MB | 1771 MB | 0.950 |
| 2498 MB | 2365 MB | 0.947 |
| 2232 MB | 2131 MB | 0.955 |
| 1839 MB | 1696 MB | 0.922 |
| 2430 MB | 2307 MB | 0.950 |
| 2496 MB | 2363 MB | 0.947 |

**Mean ≈ 0.947 — about 5.3% saved.** Extrapolated across 880.6 GB: **~47 GB**.

This is the number that makes the finding precise. It is **not** wasted work in the sense
of producing nothing — 5% is real. It is a **terrible exchange rate**, and nobody chose
it, because nothing in the system measures the trade.

It also shows the current design cannot express the right answer: compressibility is a
**continuum** (0.922–0.955 here), and a set-membership test can only return yes/no.

### 1c. What it costs

Step 10 began **17:15:58**. Measured at **22:36** — 5 h 20 m later:

| | |
|---|---|
| stored | 57 GB |
| `.z7` files completed | **16 of 649** |
| per file | ~20 min at ~160% CPU (`7z a -mx=9`) |
| `.z7` throughput | **≈ 4.1 GB/hour** |
| remaining `.z7` | 859 GB → **≈ 210 hours ≈ 8.7 days** |

**Two independent derivations agree** — by file count (16/649 in 5.33 h) and by bytes
(21.7 GB of 880.6 GB) — so the order of magnitude is solid even though the sample is
early.

**The projection: this run takes ~9–10 days, and essentially all of it is `MC Server
Backups`.** With `.z7` exempt, those 880 GB become a straight copy — hours, not days.
**Roughly a 60–80× difference in wall-clock, to forgo a 47 GB saving.**

---

## 2. The mechanism

`Modules/FileBackup.Common.psm1:115-125` — 24 extensions:

```
archives   .zip .7z .rar .gz .bz2 .xz .tgz .zst
video      .mp4 .mkv .mov .avi .webm
audio      .mp3 .aac .flac .ogg
images     .jpg .jpeg .png .webp .gif
containers .jar .pack
saves      .sav
```

`Test-ShouldCompress` (`:680-694`) is the entire decision:

```powershell
if (-not $CompressEnabled) { return $false }
$ext = [IO.Path]::GetExtension($FileName).ToLowerInvariant()
return -not ($script:NonCompressibleExtensions -contains $ext)
```

**The filename is the only input.** No sampling, no entropy estimate, no size gate, no
content sniffing. Case is handled correctly (`.MOV` was observed matching), and the
group-election comment at `Engine.psm1:4879` shows the per-group consequence was thought
through — *"'x.txt' and 'x.jpg' get different `Test-ShouldCompress` answers"*. **The
implementation is careful. The signal it is careful about is the wrong one.**

### How the list got here — and why `.z7` was always going to be missed

The comment at `:110-114` records that the list was extended on 2026-08-23 (WP5) *"with
the eight entries the HomeHub deployer's list carried and this one did not."*

**So the list was last improved by syncing it against HomeHub's list — and HomeHub's list
does not contain `.z7` either.** Reconciling two lists that share a blind spot cannot
reveal that blind spot. `common.sh:167` in HomeHub:

```sh
INCOMPRESSIBLE_EXT="jar zip 7z gz tgz bz2 xz zst rar png jpg jpeg gif webp
                    mp4 mkv webm mov mp3 ogg flac sav pack"
```

Its own comment says it *"Mirrors FileBackup's 'already-compressed extensions are exempt',
lifted to archive granularity."* Same idea, same gap. (The two lists have also drifted:
FileBackup has `.avi` and `.aac`, HomeHub does not.)

**This is the argument against fixing C-1 by adding `.z7` to the list.** The list has been
maintained, reviewed, and cross-checked against a second list — and still missed the
largest single category of data on the target system. The maintenance process is not the
weak part; **the signal is.**

---

## 3. Why 7-Zip does not rescue this

A fair objection: *7-Zip knows about incompressible data — why doesn't it just skip?*

**It does, and it is the wrong half.** The invocation is plain `-mx=9`, so LZMA2, whose
container format supports **uncompressed chunks**: the encoder compresses each chunk
(~2 MB), compares against the raw bytes, and emits raw when compression did not help.

So 7-Zip **already guarantees you will not bloat** — consistent with the observed 0.92–0.955
ratios, which are ≤1 with no expansion anywhere.

But that comparison happens **after** the LZMA match-finder has run at maximum settings.
The decision is *post-hoc, per chunk* — *"should I keep this result?"* — never *a-priori,
per file* — *"is this worth attempting?"* **7-Zip prevents the space penalty; only the
caller can prevent the time penalty**, and `Test-ShouldCompress` is exactly the place
where the caller decides. It is asking the right question of the wrong evidence.

---

## 4. What extension matching gets wrong, in both directions

| case | today | consequence |
|---|---|---|
| `.z7`, `.iso`, `.m2ts`, `.esd`, `.mca`, `.dng`, `.pdf` | compressed | **wasted CPU** — the dominant cost here |
| `.heic`/`.heif`, `.m4v`, `.wmv`, `.flv`, `.opus`, `.m4a` | compressed | same, and `.heic` is what current phones produce |
| `.zip` written in **store** mode | skipped | **lost savings** — 100% compressible, never tried |
| `.avi`/`.mov` holding lightly-compressed video | skipped | lost savings |
| 42,940 files with **no extension** (252.9 GB) | compressed | unknowable from a filename either way |

The second direction is worth naming because nobody looks for it: **a false "already
compressed" is silent and permanent.** It costs space forever and never appears in a log.

That 252.9 GB no-extension bucket is the cleanest statement of the limit: **for 12% of
this library the filename carries no information at all**, so no list — however well
maintained — can classify it.

---

## 5. Options

### A. Add the missing extensions

`.z7` (confirmed 7-Zip archives), `.m2ts`, `.esd`, plus `.heic/.heif`, `.m4v`, `.wmv`,
`.opus`, `.m4a`. **`.z7` alone recovers essentially the entire 9 days.**

**Do NOT add `.iso`** — `file(1)` shows it is an ISO 9660 *filesystem*, whose contents
may compress well (see §1a). **`.mca` is uncertain**: Minecraft region files are
zlib-compressed internally, but `file(1)` reports only `data`, so it is unconfirmed and
at 4.5 GB is not worth guessing about. Both are cases where the honest answer is "measure
it", which is the point of B and C.

- **For:** one-line change, no new machinery, immediately recovers the 9 days on this box.
- **Against:** does not address §2's point — this list was *already* cross-checked against
  another list and still missed 43% of the data. Fixes this instance, not the class.
  Leaves the no-extension 252.9 GB and the store-mode-`.zip` direction untouched.

### B. Sample and measure

Probe a slice (64 KB–1 MB, ideally from several offsets) with a fast codec; compress only
if the probe beats a threshold.

- **For:** measures the bytes instead of guessing from the name. Correct on `.z7`, on
  no-extension files, and on store-mode `.zip` — all three cases a list cannot reach.
  Well-precedented: **ZFS LZ4 early-abort** (give up if the first ~4 KB does not shrink
  ≥12.5%), **Btrfs** entropy sampling, and zstd level-1 as a probe for a level-19 decision.
- **Against:** a threshold is a new tunable. Mixed-content files (compressible header,
  high-entropy payload) can mislead a single-offset probe — multi-offset sampling is the
  standard mitigation. Adds a read per file, though small relative to the copy.
- **Accuracy:** high, and for a principled reason — compressed data is statistically
  near-uniform, so a small sample predicts the whole file tightly. Far more reliable than
  a filename, which carries *no* causal relationship to the bytes.

### C. Measure during hashing — the cheapest place to put B

**Step 5 already reads every byte of every file.** On this run that was an 8-hour full-source
read. A compressibility estimate could be computed *there*, at near-zero marginal I/O, and
stored in the source manifest beside the hash. Step 10 then reads a recorded number instead
of guessing.

- **For:** the data is already streaming through — this is the one point in the run where
  measurement is nearly free. Puts the answer in the manifest, so it is inspectable,
  testable, and explains itself. Composes with the manifest work already happening.
- **Against:** changes the manifest schema (versioning, back-compat with existing stores).
  Couples two phases that are currently independent. A file changed between hash and copy
  would carry a stale estimate — though the hash has the same property and is already
  handled.
- **Note:** this is the one cross-document dependency in the trio — the phase it lands in
  is the phase `defect-review-2026-08-31-run-observability.md` is about.

### D. Size gate

Skip compression above N GB regardless of type, or probe only above a size.

- **For:** trivial; cost is concentrated in large files, so this captures most of the win.
- **Against:** crude — a 3 GB uncompressed `.bmp` or database dump is exactly what you
  *do* want compressed. Solves the symptom by discarding the case with the biggest payoff.

### E. Per-set override

A `NonCompressibleExtensions` / `CompressEnabled` override in set config, so a deployment
can declare its own data's shape.

- **For:** no engine change; lets HomeHub fix this today without a release.
- **Against:** pushes a data question onto the operator, who must know their extension mix
  and remember to revisit it. The census above took a `find` and a decision — most
  operators will never run it.

**Not mutually exclusive.** A is the immediate unblock; B/C are the durable answer; A is
worth doing regardless as an accepted-known-formats fast path even if B or C lands.

---

## 6. The constraint any option must preserve

`Common.psm1:112-114` records a **stakeholder ruling**, not an oversight:

> *"Office/text formats are deliberately NOT here: SN-003's acceptance line says a
> `.docx` / `.txt` IS stored as `.7z`, which is a stakeholder decision, not an oversight."*

A `.docx` is a zip container and would very likely be classified "already compressed" by
any sampled probe — **so option B or C would silently reverse SN-003.** Any measured
approach needs an explicit override list that keeps ruled-on formats on their ruled-on
path, regardless of what the bytes say. **The list does not disappear under B or C; it
changes job — from "what to skip" to "what the measurement may not overrule."**

---

## 7. Verified / not verified

**Verified directly:**

- The census in §1a — full `find` over `/srv/library`, sizes and counts as shown.
- The ratios in §1b — source length from the run log, stored size from the pool on disk.
- The throughput and file counts in §1c, from the live run.
- `NonCompressibleExtensions` contents and `Test-ShouldCompress` logic, as quoted.
- The `-mx=9` invocation, observed live in `ps`: `7z a -mx=9 -bso0 -bsp0 /backup/<obj>.7z <source>`.
- HomeHub's `INCOMPRESSIBLE_EXT` list and 60% threshold at `common.sh:167-183`.
- That `.z7` files are stored as `.7z` (i.e. compressed), from the run log.

**Not verified:**

- ~~The container format of the `.z7` files.~~ **CONFIRMED** — `file(1)` reports
  `7-zip archive data, version 0.4`. They are genuine 7-Zip archives, named `.z7`
  instead of `.7z`. **7-Zip is re-compressing 7-Zip archives at maximum settings because
  of two transposed characters in the filename**, and `.7z` is already on the exempt list.
- Whether LZMA2's uncompressed-chunk fallback is what produced these particular ratios, as
  opposed to genuine small gains. Both are consistent with ≤1 ratios; distinguishing them
  needs a controlled test, and nothing in this document turns on which it is.
- The composition of the 252.9 GB no-extension bucket.
- Whether throughput improves once past `MC Server Backups` — it should, since `.mp4`/`.jpg`
  are exempt, but the 9-day projection assumes current rates for the `.z7` portion only and
  does **not** model the remainder.

**Nothing was changed on the hub for this document.** The run described here is the live
production first pass and was left running.

---

## 8. Disposition → WP17

The §5 options are expanded into an executable, requirement-traced package in
[plans/wp17-compressibility-probe-plan.md](plans/wp17-compressibility-probe-plan.md)
(**PROPOSED**, 2026-08-31 — Owner approval required before any code). Its proposed
scope is **A** (the confirmed extensions, `.z7` first — the hub-shippable commit) plus
**B** as an Engine-side sampled probe composed *after* the extension list, the §6 ruled
list so measurement can never reverse SN-003, and a per-set `CompressProbe` kill switch
(the surviving slice of **E**). **C** and **D** are deferred with reasons in the plan's
§7. The live-run decision (finish the ~9-day pass, or stop and rerun on Part A) is the
plan's §9 / Q6 and needs one code fact verified first.
