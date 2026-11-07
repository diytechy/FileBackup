# Design, 2026-11-07: the native engine's compressibility probe

**Status:** PROPOSED, revision 3. This is step 2 of
[the 2026-11-07 brief](2026-11-07-native-probe-fix-brief.md). No code may be written under this
design until the Owner rules on the decisions in §9.

- **Revision 1** was reviewed by an independent Sonnet reviewer at medium effort.
- **Revision 2** was cross-checked by Codex at medium effort.

Both returned "approve with changes". Their findings and what changed are in §11.

**Built from:**

- [the defect audit](../defect-audit-2026-11-07.md), §4.5 and §7.1;
- the [2026-09-02 defect review](../defect-review-2026-09-02-probe-sample-representativeness.md);
- the [2026-09-07 corpus study](../probe-sampling-corpus-2026-09-07.md);
- [WP17's codec calibration](wp17-codec-calibration.md);
- [WP18](wp18-probe-window-geometry-plan.md), the unbuilt PowerShell plan this design supersedes.

**Terms.**

- **Probe:** the measurement that decides, for each new file, whether to compress it with 7-Zip.
- **Window:** one 256 KiB sample of the file.
- **Ratio:** a window's compressed size divided by its raw size. 1.0 means no saving; 0.90 means a
  10% saving.
- **Realised ratio:** what 7-Zip actually achieved on the whole file. It is the ground truth the
  corpus measured.
- **Correlation:** how well a measurement predicts the realised ratio, from 0 (no signal) to 1.
- **SR-081:** the approved requirement that a file whose measured saving is at least 10% is stored
  compressed and any other file is stored as it is.
- **LLR-162:** the draft design row that says how the Rust engine measures that saving.

---

## 1. The problem in one paragraph

The Rust probe copies the PowerShell probe as it shipped. It takes three windows, at the start,
the middle and the end of the file, joins them and compresses them with one 7-Zip run. It
compresses the whole file when the joined sample shrinks to 90% or less.

Video and disc images keep compressible headers, indexes and padding at both ends, so two of the
three windows measure the container, not the content. Measured on 166 real library files, the
predictive power of single windows was:

- the start window: correlation +0.06, no signal;
- the end window: +0.42;
- the shipped three-window set: +0.65;
- one window in the middle alone: +0.80.

The result was the stopped 2026-11-07 run: hours of 7-Zip per video for about a 6% saving. On top
of that, each Rust probe starts 7-Zip and writes temporary files to the backup disk, and nothing in
the log says why a file was compressed.

## 2. Recommendation

All changes sit inside the compression decision. **No stored byte, manifest field or restore kit
changes:** a compressed object is still checked against its content by a full read-back before it
is published (`rust/src/engine.rs:563-568`). A wrong decision costs space or time, never data.

1. **Place the windows inside the file, never at the ends.** Seven windows at 1/8, 2/8, … 7/8 of the
   way through. Each window starts at `floor(k × (length − 256 KiB) / 8)`, for k = 1 … 7.
2. **Combine the windows by a rule the scoring run chooses** (§4, §8.1). Compress when the
   combined ratio is **0.90 or less**, SR-081's threshold.
   - The candidates are the **mean** (each window compressed on its own, the compressed bytes
     summed over the raw bytes: what the PowerShell probe computes), the **trimmed mean** (drop
     the highest and lowest window) and the **median**.
   - The mean is the provisional default. It is a candidate, not a proven winner.
   - Today's Rust probe compresses the joined windows as one stream. That is a different
     estimator from all three, because a compressor can find repeats across window boundaries.
3. **Measure in memory with Brotli at the PowerShell probe's settings** (`CompressionLevel.Fastest`),
   not with 7-Zip. Brotli is the coder the 0.90 threshold was calibrated on (§5).
4. **Take the windows from the staging copy as it streams past.** The engine already reads every
   byte of a new file once, to hash it and copy it into `Incoming`. The windows are kept from that
   stream, so the probe adds no disk reads, no temporary files and no 7-Zip process (§6).
5. **Measure files too short for seven separate windows as one whole-file sample.** That is files
   above SR-081's 256 KiB floor and under 2.25 MiB. Seven 256 KiB windows at eighths stop
   overlapping only at 9 × 256 KiB.
6. **Put the evidence back:** a decision line per measured file, and probe counters in the run
   report (§7).

## 3. Placement and count

### 3.1 Off the ends

The corpus measured one window at each of 21 positions, 0% to 100% in steps of 5%. It used 166
files of 32 MiB or more, each already stored compressed so its realised ratio was known
(corpus §7b):

| Window position | Correlation |
|---|---|
| start (0%) | +0.06 |
| end (100%) | +0.42, and it reads compressible almost everywhere (mean ratio 0.28) |
| everywhere from 5% to 90% | +0.71 to +0.85, a broad plateau |

Staying off the two ends is what matters; the exact interior positions are not. Three windows at
25/50/75% scored +0.89, against +0.65 for today's three, at the same cost.

### 3.2 Seven windows, fixed, not scaled with size

The corpus graded the median of N evenly spaced windows (corpus §7c):

| Windows | Correlation | Average error |
|---|---|---|
| 3: start / middle / end (shipped) | +0.65 | 0.191 |
| 3: 25 / 50 / 75% | +0.89 | 0.144 |
| 5: 0 / 25 / 50 / 75 / 100% | +0.85 | 0.125 |
| 7: 0 / 15 / 35 / 50 / 65 / 85 / 100% | +0.91 | **0.114** (best) |
| 9, evenly spaced | +0.92 | 0.116 |
| 21, every 5% | +0.92 | 0.127 |

- **Accuracy stops improving at about nine windows.** Seven is chosen for margin over three: more
  interior samples average out local variation, such as padding between files inside a disc image
  or an index in mid-file.
- **The set graded closest to the proposal had both end windows in it.** The 7-window set above
  includes both ends and so has only five interior windows, yet it outscored the 5-window set
  that also includes both ends (+0.91 against +0.85). Ends hurt and interior windows help, so
  seven interior windows plausibly score at least as well. **That is an inference.** No graded
  set was seven interior windows. The scoring run in §8 measures it.
- **Because the windows come from a stream the engine already reads, seven cost no more disk
  work than three.** The extra cost is CPU only (§6).
- **Not scaled with file size (WP18).** WP18 grew the count with size, from 3 windows at 16 MiB up
  to 24, and kept the start and end windows. The corpus, measured two days after WP18 was drafted,
  shows the end windows were the bias and that accuracy stops improving at about nine.

## 4. How the windows are combined

### 4.1 The mean, by default

The realised ratio of a whole file is, to a first approximation, the average of how compressible
each part of it is. **The mean of evenly spaced interior windows estimates that average.**

- The mean here means each window compressed separately, with the compressed bytes summed over
  the raw bytes. With equal windows that is the mean of the window ratios, and it is what the
  PowerShell probe computes (`Engine.psm1:4042-4063`).
- Today's Rust probe compresses the joined windows in one stream, which can find repeats across
  window boundaries. It is a different estimator, and the corpus never measured it.
- The corpus's placement figures (§3) were all computed with the **median**, so they are evidence
  about where to sample, not about which combination wins. **Nothing on record grades the mean of
  interior windows.**

**Why the corpus preferred the median, and why that may not carry over.** Every rule the corpus
scored (§6) sat on the old start/middle/end geometry, and its traps were all end-window artifacts:

- Matroska indexes at both ends, read `0.62, 0.99, 0.71`;
- a Wii U archive's trailing structure, `1, 1, 0.27`;
- a zeroed phone-video preamble, `0, 1, 0.34`.

The median outvoted one bad end window, and a `middle ≥ 0.98` clause covered both ends being bad.
**With no end windows, neither problem exists to correct.**

**What the median gets wrong.** It rejects any file that is compressible in fewer than four of its
seven windows. WP17's calibration fixture `mixed-third` is 2 MiB random, 2 MiB text, 2 MiB random:
7-Zip realises 0.71, a 29% saving. Only three of the seven interior windows land in the text, so
the median reads random (about 1.0) and stores it raw. SR-081 speaks of *measured* saving, so a
median is not itself a breach of the requirement. But it is a measurement that cannot see a
saving confined to less than half the file, and the Owner should choose that knowingly. The
corpus has no deliberately mixed file (corpus §8), so it never tested this.

**What the mean risks.** A single interior window that lands on a small, very compressible region,
such as a padding run between files inside a disc image, counts for one seventh of the estimate
whatever that region's real share of the file. On an otherwise incompressible 8 GB image, one zero
window gives a mean of 0.857, so the file is compressed. That is not wasted work if the padding
is real, but the saving may be smaller than estimated.

- **The trimmed mean** (drop the highest and lowest window, average the other five) caps that risk.
  It still tracks mixtures: `mixed-third` reads about 0.64.
- **The median** removes the risk but loses mixtures.

### 4.2 The three combinations on the known shapes

The window positions below are the proposed eighths. **These verdicts are inferences from each
file's described structure.** The corpus did not measure these offsets on these files.

| Case | Shape | Shipped | Mean | Trimmed | Median |
|---|---|---|---|---|---|
| Matroska remux (corpus 4b; hub ROTJ), realised 0.985 | index at both ends, video between | compress | raw | raw | raw |
| Wii U archive `1, 1, 0.27` (4a), realised 1.00 | incompressible but the trailing structure | compress | raw | raw | raw |
| Phone video, zeroed preamble (4d), realised 1.00 | one padding window at the start | compress | raw | raw | raw |
| Screen recording `1, 0.08, 0.40` (4e), realised 0.137 | dense opening, near-static body | compress | compress | compress | compress |
| Sparse ESB `.mkv` (hub; corpus 4e), realised 0.43 | data to about 42%, zeros after | compress | compress (about 0.43) | compress | compress |
| `mixed-third` (WP17), realised 0.71 | one third compressible, in the middle | compress | compress | compress | **raw (wrong)** |
| Video with one interior padding window | 1 window in 7 at 0, the rest 1.0 | depends | compress (0.857) | raw | raw |
| Already-compressed archives (4f) | uniform | raw | raw | raw | raw |

A local run of `docs/experiments/probe-window-interior.py` on synthetic files built to these shapes
agreed with this table. Those files are this design's own constructions, so the run checks the
arithmetic, not the real library.

### 4.3 The hub's AVCHD disc image

The brief asked for this case to be checked. The ESB AVCHD `.iso` (8.43 GB) reads
`0.003 / 0.963 / 0.017` today and realised **0.934**, a 6.6% saving.

- **By its realised outcome it should have been stored raw.** SR-081 decides on the *measured*
  saving, so compressing it was compliant. It was still wasted work, caused by two padding windows
  pulling the joined sample to 0.33.
- **The corpus's own recommended rule** ("raw when the median is above 0.95, or the middle is 0.98
  or more") **also compresses it.** The median of those three windows is a padding window, and the
  middle falls just short of 0.98. The brief's concern is confirmed.
- **Under the proposal, the outcome depends on the interior, which nobody has measured.** An AVCHD
  image is an ISO 9660 wrapper around MPEG transport streams. If its padding sits at the start and
  the end, as the three windows suggest, all seven interior windows read about 0.96 and every
  combination stores it raw. If padding also sits between the streams, the mean may compress it,
  and the trimmed mean and the median probably will not.
- **One window in the middle is not evidence about the other six.** §8's script prints all of them
  in a minute.

Even if it compressed, the cost is about 56 minutes of 7-Zip (8.43 GB at 2.4 MiB/s) for a real
6.6% saving: a slow decision, not a wasted one.

### 4.4 What the scoring run decides

§8's read-only script grades the mean, the trimmed mean and the median, on three and seven
interior windows and on today's geometry, against the hub's realised ratios. For each it reports
the 7-Zip input spent on files that realised above 0.90 (**wasted**) and the saving given up on
files that realised 0.90 or below (**forgone**), both in GiB.

**The selection rule is fixed before the run, so the result cannot steer it.** Among the
seven-interior-window combinations, adopt the one with the least wasted 7-Zip input whose forgone
saving stays within a budget the Owner sets (§9 decision 4). Proposed budget: forgone saving no
more than **10% of the saving the candidates realise in total**. That is the trade the corpus's
own recommendation made (it kept 90.9%). If none fits the budget, the result comes back to the
Owner.

**The run is a release gate.** If it cannot be run, the Owner chooses between shipping the mean,
the PowerShell probe's own estimator applied to interior windows, and holding the release
(decision 4).

## 5. The measuring codec: Brotli, at the PowerShell probe's settings

**Why not 7-Zip, as today.** The Rust probe joins the windows into a temporary file in `Incoming`,
starts `7zz`, flushes the archive and reads its size (`engine.rs:406-436`). Measuring windows
separately would take seven runs per file of 2.25 MiB or more, and one for a whole-file sample.
Over a first pass of up to about 74,000 measured files (65,832 + 8,534 in the September run),
that is up to about half a million process starts, plus temporary writes on the backup disk.

**Why Brotli rather than zlib** (revision 1 proposed zlib):

- **It is what the threshold was calibrated on.** WP17 measured both against real 7-Zip on eleven
  fixtures (`wp17-codec-calibration.md`, lines 17-68), and Deflate, the zlib coder, made more wrong
  decisions:
  - Deflate reads incompressible data at about 1.05, not 1.00.
  - Its 32 KiB history cannot see a 64 KiB repeat that 7-Zip compresses to nothing
    (`longrange-64KiB-x256.bin`: Deflate 1.05, Brotli 0.25, 7-Zip 0.00).
- **It is faster.** Brotli took about a fifth of Deflate's time: 27.6 ms against 136.8 ms over
  WP17's whole set of eleven files. That is about 0.84 ms per 256 KiB window, a figure WP18
  re-measured (`wp18-probe-window-geometry-plan.md`, §3).
- **Corpus caveat.** The corpus's placement study used zlib level 1 only because the hub had no
  Brotli. On real files it tracked Brotli closely (correlation +0.99 at each position), so its
  placement conclusions stand. The threshold should still be applied to Brotli, as it was
  calibrated.
- **It is the same measurement PowerShell made.** The PowerShell probe uses .NET's
  `BrotliStream` at `CompressionLevel.Fastest` (`Engine.psm1:3921-3926`).
- **The settings are quality 1, window 22.** On 2026-11-07, .NET's `BrotliStream` at `Fastest` and
  `BrotliEncoder` at quality 1, window 22 produced byte-identical sizes on random, text and mixed
  256 KiB buffers (pwsh 7, this machine); qualities 0, 2 and 3 differed.
- **The encoder is pinned by tests, not by memory.**
  - Matching settings do not prove that two implementations produce the same sizes. A table of
    exact compressed sizes from .NET's `BrotliEncoder` at quality 1, window 22 is checked in, over
    generated buffers that include ratios near 0.90 and WP17's fixtures (for example
    `longrange-64KiB-x256.bin` at 0.2502).
  - The Rust probe must agree with that table within 0.005 in ratio. Each window is a finished,
    independent stream.
  - If the scoring run uses zlib (the hub has no Brotli module), its results are placement and
    combination evidence. They do not validate the 0.90 threshold.
- **The crate:** `brotli`, the pure-Rust encoder (BSD-3-Clause or MIT; no C code or system library),
  at a pinned exact version, used for the compressed byte count only. Its licence goes into the
  package notices alongside the other crates. The restore kits do not touch it.

**The earlier codec ruling.** The Owner removed an embedded 7-Zip codec on 2026-11-06 in favour of
the bundled official 7-Zip
([embedded-codec record](native-design-2026-11-05/embedded-codec-2026-11-06.md)). That ruling
concerned the codec that **writes stored objects**, whose output a restore must read for decades.
A probe codec writes nothing that is kept. It is still a new dependency, so it is put to the Owner
(§9 decision 1).

## 6. Taking the windows from the staging stream

Today `format::copy_hash` (`rust/src/format.rs:99-118`) reads the source in chunks of up to
256 KiB, writes each chunk to the staged copy and feeds it to the hash. The proposal adds an
optional window sampler to that loop.

**The sampler:**

- **Positions:** the seven offsets are computed from the length measured before the copy
  (`engine.rs:458`). The sampler copies bytes into a 1.75 MiB buffer only where a chunk overlaps a
  window, so a window that straddles two reads, or arrives in short reads, is assembled correctly.
  For a whole-file sample under 2.25 MiB, the buffer holds the file.
- **When it exists:** only when compression is on, the probe mode measures this file, and the
  length is above 256 KiB. `hash_file` and every other caller pass none, so behaviour elsewhere is
  unchanged.
- **Exactly the bytes that were hashed.** The sampler sees exactly the chunks `copy_hash` has
  written and hashed (`format.rs:104-112`), never a separate read.
- **Bounded.** Its buffer is fixed at the planned windows, so a file that grows during the copy
  cannot enlarge it. Offset arithmetic is checked, so it cannot overflow.
- **Running out:** if the stream ends before a window is full, the sampler marks itself incomplete
  and never panics. Capture already rejects a file whose length changed during the copy
  (`engine.rs:492-495`), so the windows are discarded with the failed attempt, and a retry samples
  afresh.
- **Failures stay separate.** A failure inside the sampler or the measuring coder only makes the
  type list decide, with SR-081's warning. A copy, write or hash failure keeps exactly today's
  meaning (retry, then "capture failed").
- **Lazy compression:** Brotli runs only after the dedup check misses. A file whose content is
  already stored returns early (`engine.rs:508-558`) with no measurement, no decision line and no
  counter.
- **Memory:** captures run one at a time (the capture loop starts no threads), so one buffer of at
  most 2.25 MiB is live.

**Cost.**

| | Today's Rust probe | Proposed |
|---|---|---|
| Disk reads for the probe | 3 seeks + 768 KiB from the staged copy | **none** |
| Disk writes for the probe | a sample file and a 7-Zip archive in `Incoming`, flushed | **none** |
| Processes started | one `7zz` per measured file | **none** |
| CPU per measured file | one 7-Zip run over 768 KiB | Brotli over 7 windows: about 6 ms on the dev PC (0.84 ms per window, measured), perhaps 10-25 ms on the hub [estimate; hub CPU unmeasured] |
| First pass, up to about 74,000 measured files | about 5-7 h [estimate, audit §7.1] | about 7-30 min of CPU [estimate] |

**7-Zip time saved.** It is not yet measured for this rule. The corpus scored only the old
geometry, where the median-based rules avoided 168-264 GiB of 7-Zip input, about 20-31 h at
2.4 MiB/s. Interior placement predicts much better (§3.1), but how many hours it saves on the
hub's library is exactly what the §8 run reports.

This also answers WP18's third question. Its "about 37 minutes per run" was the price of reading
more windows, and taking them from the staging stream removes that price.

## 7. The evidence (telemetry)

PowerShell wrote one `compress-decision:` line per stored object and three probe counters. Rust
dropped both when the full probe requirement (LLR-086) was retired with no successor.

1. **Counters in the JSON run report**, which goes to stdout and the store's `backup.log`. A new
   `probe` object holds:
   - `measured`: files measured;
   - `compressed` and `raw`: their outcomes;
   - `whole_file`: files measured as one sample;
   - `unmeasured`: files at or under 256 KiB, or excluded by the probe mode;
   - `fallback`: the measurement failed, so the type list decided;
   - `bytes_compressed_in` and `bytes_compressed_out`.

   Existing fields are unchanged; this only adds one.
2. **One decision line per measured file** in `<StorePath>/compress-decisions/<run start>.log`.
   - Each line holds: the time, the relative path, the length, the decision, the reason
     (`mean` or the chosen combination, `whole-file`, `fallback`, `type-list`), the combined
     ratio and the window ratios.
   - **One file per run, the newest N kept**, so a stopped run's decisions survive the restart.
     Revision 1 truncated a single file at each run start, which would have destroyed exactly the
     evidence it was meant to keep. N is the Owner's choice (decision 5): ten nightly runs evict an
     incident's log within ten days.
   - **Rotation deletes only what it made.**
     - The folder must be an ordinary directory, not a link or junction; if it is not, logging is
       skipped with a warning, as other store mutations refuse redirected entries
       (`platform.rs:71-92`).
     - A run's file is created exclusively, under a portable, sortable name from the run's start
       time (`YYYY_MM_DD_HH_MM_SS.log`, with a numeric suffix on a collision).
     - Rotation deletes only ordinary files matching that exact pattern, oldest first. Anything
       else in the folder is left alone.
     - A rotation failure is a warning, never a failed run.
   - **Lines are flushed in small batches**, at least every few seconds and at the end of each
     capture. A stopped run keeps all but its last moments.
   - **A write failure never fails a capture.** It becomes one warning per run, as the existing
     `backup.log` append does (`engine.rs:647-655`).
   - **Created only after the store is initialized, under the store lock.** Store admission refuses
     any unknown entry in a store root that has no `CurrentBackup` yet (`store.rs:56-80`). No
     restorer, verify or prune reads the store root's loose entries: prune scans snapshot folders
     only (`maintenance.rs:373`), and the restore kits look only in `CurrentBackup` and
     `BackupHistory`.
   - **Why not the journal:** SR-159 keeps paths and file names off standard error, which reaches
     the system journal.
   - **Why not `backup.log`:** it holds one JSON report per run.
   - **Size:** about 74,000 lines of about 200 bytes, roughly 15 MB on a first pass; nightly runs
     are small. The store already holds every path in its manifest, so this exposes nothing new.

## 8. Validation

### 8.1 Before building: the scoring run on the hub (read-only, the Owner runs it)

`docs/experiments/probe-window-interior.py` follows the September sampler, made finer.

**What it does:**

- reads a store's manifest and picks files stored compressed, so their realised ratio is known;
- samples each source file at 41 offsets, every 2.5%;
- prints the window ratios as CSV on stdout;
- grades every geometry and combination at 0.90 on stderr: correlation, average error, wasted GiB,
  forgone GiB and 7-Zip input GiB, weighted back to the whole population.

**`--file PATH`** prints the windows and each rule's verdict for a named file. That settles §4.3
for the AVCHD image, and checks ROTJ and the ESB `.mkv`.

**How it runs:**

- It opens files for reading only: one manifest read, one stat per sampled file, and 41 reads of
  256 KiB per file.
- It uses Brotli if the `brotli` Python module is present, and otherwise zlib level 1 with the
  caveat in §5.
- Inputs: the September PowerShell store (`/mnt/backup-drive/library`, flat) if it still exists;
  otherwise the native store's `CurrentBackup` with `--sharded`. The stopped run's compressed
  objects are a biased but real set.

**Ground-truth guard.** A source file is graded only if its size equals the manifest length and
its modification time matches the manifest within 2 s, both before and after sampling. Anything
else is excluded and counted, so a file edited since it was stored never borrows another version's
outcome. This is a size-and-time check, not a hash.

**Weighting.** It grades distinct stored objects, since a duplicate is compressed only once. It
stratifies by realised ratio and by size (2.25-32 MiB, and 32 MiB or more), weights every
statistic back to the population, and prints coverage, exclusions and any stratum left empty.

**Limits.**

- Like the corpus, it can grade only files already stored compressed (corpus §7e), so it shows
  wasted work and lost saving among those. It cannot show compressible files the old probe waved
  through.
- Its "shipped" rows grade today's start/middle/end geometry under each combination. They are not
  a replay of the Rust engine's single 7-Zip run over the joined windows.
- A local run on synthetic files exercised the exclusion, duplicate, cohort and weighting paths. It
  has not been run on real data.

### 8.2 In the repo: tests built to the real shapes

Synthetic random or text files miss the start/end bias, so each fixture copies a real file's
structure at 16-64 MiB. Every rule is in fractions of the length, so the geometry is the same.

**Shapes:**

| Fixture | Expected |
|---|---|
| padding at both ends, random body (disc image) | raw |
| compressible index at both ends, random body (remux) | raw |
| random body with a compressible tail (`1, 1, 0.27`) | raw |
| zeroed preamble, then random (phone video) | raw |
| random opening tenth, then a compressible body (screen recording) | compress |
| random to 42%, then zeros (sparse file) | compress |
| `mixed-third`, scaled up | compress under the mean and the trimmed mean |
| a 64 KiB block repeated (WP17 `longrange`) | compress |
| uniform text | compress |
| uniform random | raw |

**The codec:** the checked-in .NET size table (§5) is reproduced within 0.005, including the
buffers near 0.90.

**Sizes:**

- exactly 256 KiB: not measured;
- just above 256 KiB: measured as a whole file;
- just under 2.25 MiB: whole file;
- exactly 2.25 MiB: seven windows.

**The stream:**

- windows that straddle reads;
- short reads;
- a file that shrinks or grows during the copy: the windows are discarded, the file is retried,
  nothing panics, and the buffer never exceeds its planned size;
- a sampler failure, forced through `test-hooks`: type fallback only, with the capture itself
  unaffected;
- a dedup hit: no measurement, no line, no counter.

**Modes:**

- all three probe modes;
- compression off: no measurement at all (SR-096);
- a forced measurement failure through the existing `test-hooks` feature: type fallback plus a
  warning (SR-081).

**Evidence:** each case also checks the decision line and the counters.

## 9. Decisions for the Owner

1. **Add the `brotli` crate for the probe measurement?**
   - Recommended: **yes**. It is the coder the threshold was calibrated on.
   - The alternative is seven 7-Zip runs per file: slower than today, and it still writes to the
     backup disk.
2. **Window placement and count: seven interior windows at eighths, fixed?**
   - Recommended: **yes**.
   - Alternatives: three at 25/50/75% (measured +0.89), or WP18's size-scaled count (not
     recommended, §3.2).
3. **How the windows are combined.**
   - Recommended: let the §8.1 run choose by the selection rule fixed in §4.4, among the mean, the
     trimmed mean and the median.
   - The **median** cannot see a saving confined to less than half the file (`mixed-third`).
     SR-081 decides on measured saving, so it stays within the requirement, but choose it knowingly.
   - A threshold of 0.95 instead of 0.90 would need SR-081 amended.
4. **The scoring run as a release gate, its budget, and the fallback.**
   - Recommended: **run it before the build.** It is read-only, takes well under an hour, and is
     the only evidence for seven interior windows, the combination and the AVCHD image.
   - **Budget:** forgone saving no more than 10% of the total saving the candidates realise,
     unless you set another.
   - **If it cannot be run:** ship the mean (recommended: the PowerShell probe's own estimator,
     moved off the ends), or hold the release.
5. **The decision record:** a per-run `compress-decisions/<run start>.log` plus the report counters?
   - Recommended: **yes**.
   - **How many runs to keep:** recommended **30**, about a month of nights and well under 100 MB
     after a first pass.
   - Alternative: decision lines in the JSON report only for files that were compressed (about
     8,500 on a first pass), with no new store folder.
6. **The whole-file cutoff: 2.25 MiB, where seven windows stop overlapping?**
   - Recommended: **yes**.
   - The alternative is 1.75 MiB with overlapping windows.
7. **The two items that bear on a clean restart, in the same release as their own reviewed
   changes?**
   - **The 7-Zip deadline**, 300 s plus 1 s per MiB. Running past it ends the whole run as a host
     failure, so any file that compresses slower than about 1 MiB/s stops the night.
   - **The progress count freezing** during compression and read-back.
   - Recommended: **yes, both**, as separate small changes after this one.
8. **A name for the work.** Suggested: **"native probe fix"**, with WP18 recorded as superseded.

### WP18's open questions, answered

1. **Should a hub experiment gate the code change?** The 2026-09-07 corpus was that experiment and
   overturned WP18's premise. A smaller, sharper one now gates the choice of combination
   (decision 4).
2. **Its three constants (16 MiB, 3, 24):** moot. There is no size formula. The constants are
   seven windows, 2.25 MiB and SR-081's 0.90.
3. **About 37 minutes per run:** moot. The probe's disk cost becomes zero (§6).
4. **The work-package number:** decision 8.

## 10. Requirement and test changes

- **SR-081 (approved):** unchanged. It decides on measured saving at 10%, and every candidate
  measures and applies that threshold.
- **LLR-162 (draft):**
  - State the interior offsets at eighths, the 2.25 MiB whole-file cutoff, Brotli at the
    calibrated settings, and the combination.
  - Under the mean, the existing "(sample raw − sample archive) / sample raw" definition stands,
    with the archive bytes defined as the sum of independently compressed windows. Today's Rust
    joined stream does not meet that reading. Under the trimmed mean or the median, the definition
    is reworded to that combination.
  - Restore what the retired LLR-086 required: the decision line and the counters.
  - The Owner approves this design-tier change with the design.
- **A new test case** covering §8.2, traced to LLR-162 and SR-081.
- **Documentation:** the README and `docs/native-usage.md` describe the decision log and the
  counters.

### Not in this change (audit items, for the Owner to schedule)

- the deadline and the progress freeze (decision 7);
- the full copy into `Incoming` before the dedup check, and expanding sparse files (audit §7.3);
- the full already-compressed extension list (audit §4.2);
- every other audit item.

## 11. Review record

**Revision 1 → 2.** Independent Sonnet review at medium effort: *approve with changes*. Its twelve
findings and how each was taken:

1. **The median loses mixed files** (WP17 `mixed-third`): accepted. The default became the mean
   (§4); the median is offered with its cost stated; mixed fixtures were added.
2. **zlib is not calibrated like Brotli** (WP17's Deflate failures): accepted. The codec became
   Brotli (§5).
3. **The saved-work estimate quoted the wrong rule:** accepted. The figure is now stated as
   unmeasured for this rule (§6).
4. **The basis of the seven-window inference was misstated:** accepted (§3.2).
5. **The windows overlap below 2.25 MiB:** accepted. The cutoff is now 2.25 MiB (decision 6).
6. **The hub measurement belongs before the build:** accepted (decision 4).
7. **A truncated log defeats its purpose:** accepted. There is now one file per run, with a write-failure
   policy. How many to keep is now decision 5.
8. **The stream sampler was underspecified:** accepted (§6, §8.2).
9. **The dependency's notices:** accepted (§5).
10. **Correlation is not decision accuracy:** accepted. The script reports wasted and forgone GiB.
11. **Unexplained codes:** glossed.
12. **The deadline:** raised to the Owner (decision 7).

**Revision 2 → 3.** Codex cross-check at medium effort (read-only): *approve with changes*. Its
nine findings and how each was taken:

1. **Nothing on record shows seven interior windows with the mean are best:** accepted. The mean
   is now a candidate. The scoring run is a release gate with a selection rule fixed in advance and
   a budget the Owner sets (§4.4, decision 4).
2. **The joined-stream ratio is not the mean of the window ratios, and SR-081 speaks of measured
   saving:** accepted. The estimators are now distinguished (§2, §4.1). The AVCHD and median
   wording no longer claims a requirement breach (§4.1, §4.3), and the LLR-162 reconciliation is
   per combination (§10).
3. **The script's ground truth could describe a different version of the file:** accepted. A
   size-and-time check runs before and after sampling, and exclusions are counted (§8.1).
4. **The script's population estimates were wrong:** accepted. It now counts distinct objects,
   weights every statistic (correlation included), reports coverage and empty strata, and fixes
   the selection rule in advance.
5. **Log rotation needs safe deletion rules:** accepted. Ordinary-directory check, exclusive
   creation, deleting only recognised files, failures as warnings, batched flushing and a
   retention choice (§7, decision 5).
6. **The sampler's safety boundary should be explicit:** accepted (§6).
7. **The CPU estimate reused WP17's whole-set 27.6 ms as a per-probe figure,** an error WP18 had
   already corrected: accepted. Recalculated from 0.84 ms per window, with process starts
   qualified (§5, §6).
8. **Matching settings do not prove matching encoders:** accepted. Quality 1, window 22 was
   confirmed against .NET locally, and a checked-in .NET size table is pinned by test, including
   ratios near 0.90 (§5, §8.2).
9. **The script's coverage was overstated:** accepted. A 2.25-32 MiB cohort was added, an empty
   result is handled, the "shipped" rows are labelled geometry-only, and the limits are stated
   (§8.1).
