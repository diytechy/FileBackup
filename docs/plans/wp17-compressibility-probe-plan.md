# WP17 — Decide compression from the bytes, not the filename

Plan owner: driver. Raised by the Owner 2026-08-31 from
[defect-review-2026-08-31-compressibility-by-extension.md](../defect-review-2026-08-31-compressibility-by-extension.md)
(the third of the three production first-pass reviews; C-1..C-3, §5 options A–E, and
the §6 SN-003 constraint). This plan is the expansion of that review's §5 into an
executable, requirement-traced package.

**Scope (Q0, ruled):** the review's **A** (add the
proven-compressed extensions, `.z7` first) as the immediate, list-only fix; **B** (a
sampled compressibility probe) as the durable fix, implemented in **Engine** and
composed *after* the existing extension list; the **§6 ruled-format override** so B can
never reverse SN-003; and a **per-set probe mode** `CompressProbe: Off | ExcludedExtensions |
Always` (the surviving slice of **E**), defaulting to `Always` — the list then serves the
other two modes and the below-floor tail, and measurement decides everything else. Options **C** (measure during hashing) and **D** (size gate) are
deliberately deferred with reasons (§7). The per-set *extension-list* override half of E
is deferred too.

**Status: PROPOSED — awaiting the plan-stage cross-review and then Owner approval; no
code may be written under it.** Nothing here is implemented and no registry row is added
until the Owner approves. The active gate is **G3**. The decision dial is **HIGH**.
**Revision 2 (2026-08-31):** the Owner ruled on Q0–Q6 (§6) and the rulings are folded:
`CompressProbe` is a three-valued mode defaulting to **`Always`** (§2.5), the size floor
is **256 KiB**, Part A bumps `KitRevision`, SN-003's text is not edited, and the hub run
is already stopped (§9). Registry ids in this document are
**provisional** (§3): WP16 is PROPOSED and has reserved `SN-037`, `SR-076..080`,
`LLR-081..085`, `TC-205..221`; WP17 numbers from after those and renumbers if WP16 lands
differently.

**What this package touches, stated honestly.** It changes **which of two correct
storage forms** a newly written object takes. It changes no hashing, no dedup key, no
atomic-write path, no restore decision, nothing in either restorer, and nothing already
stored (SR-061). Both forms already coexist in every compression-enabled store and both
restore byte-exact (SR-050, TC-141 proves restore is insensitive to the `Compressed`
column). The one data-integrity-adjacent edit is inside `Invoke-BackupFileGroup`'s write
branch — the SR-060 owner-election code — which is why §8 sizes the implementation review
as a dual round rather than a single reviewer. Part A edits `Common.psm1`, which is
kit-bundled; Q1 ruled that it bumps `KitRevision` (§6).

---

## 0. The one-paragraph version

`Test-ShouldCompress` decides from the filename alone, and on the production library the
24-entry list missed `.z7` — 649 genuine 7-Zip archives, 880 GB, 43% of the data — so
the first pass is re-compressing 7-Zip archives with 7-Zip at `-mx=9` for a measured 5%
gain at ~20 minutes of two-core CPU per file: **~9 days to save ~47 GB**. LZMA2's own
incompressible-chunk fallback prevents the *space* penalty, never the *time* penalty,
because it decides after the match-finder has run; only the caller can decide before.
The list has already been cross-checked against a second list that shared the blind
spot, so maintaining it harder is not the fix. WP17 does two things. **Part A** adds the
extensions the review confirmed (`.z7` alone recovers the nine days) and is the change
the hub needs today. **Part B** stops trusting the name: by default (`Always`) for every file above a
256 KiB floor — in `ExcludedExtensions` mode only for what the list would compress —
Engine reads three small samples (start, middle, end), Deflate-compresses them at the fastest level, and stores
raw only when **every** sample fails to shrink by the threshold — erring toward today's
behaviour, because a false "already compressed" is the silent, permanent direction
(review §4). A short **ruled list** keeps `.docx`/`.txt`-class formats on their SN-003
path no matter what the bytes say (review §6): the extension list does not disappear, it
changes job. The probe runs **lazily** — only when the group actually has to write, never
for content dedup already owns — and never fails a run: any probe error falls back to the
list's answer. `CompressProbe: Off` restores exactly today's behaviour.

---

## 1. What must remain true

| # | Invariant | How this plan holds it |
|---|---|---|
| **I-1** | **`Compressed` and the stored filename agree for every object** (SR-004 acceptance; AGENTS.md §3 "the filename must not lie"). | The probe changes the *input* to the existing decision, not the write path: `$dataExt`/`Compressed` are still both derived from the one `$ownerCompress` boolean at `Engine.psm1:4990`. TC-093's storage-form audit (SR-049) runs over a probe-mixed store and reports clean. |
| **I-2** | **SN-003's stakeholder ruling is not reversed by measurement.** *"With compression on, a `.docx`/`.txt` is stored as `.7z`; a `.jpg`/`.mp4` is stored as-is."* | The ruled list (§2.3) is consulted **before** the probe in **every** probing mode, `Always` included, and short-circuits it. A `.docx` — a zip container the probe would otherwise call incompressible — is stored `.7z` exactly as today. TC-224 is the regression pin, and it is the negative control that must fail with the override removed. (SN-003's second clause — `.jpg`/`.mp4` stored as-is — holds under `Always` because those bytes probe incompressible; TC-225 covers it with a real JPEG-class corpus, not by name.) |
| **I-3** | **Nothing already stored is ever re-formed** (SR-061). | WP17 has no migration in either direction. An object dedup already locates (`$existingBackupWithHash`) is adopted **before** the probe is ever consulted (§2.4 lazy evaluation), so no existing object's form is re-decided. README's "mixed-form store is normal" paragraph gains one clause, not a new rule. |
| **I-4** | **The extension list stays the ONE definition, in Common** (LLR-004; TC-096 pins one definition site and zero Engine references). | Part A appends to `$script:NonCompressibleExtensions` in place. Part B adds no second copy: Engine calls `Test-ShouldCompress` as it does today and composes the probe *after* it. The ruled list is a **different** set with a different name and job, and TC-096's "Engine has no `NonCompressibleExtensions` reference" arm stays true. |
| **I-5** | **`Common` never depends on `Engine`; KitRevision bumps whenever a kit-bundled file changes behaviour** (AGENTS.md §3). | The probe, the ruled list and the composition live in **Engine**. Only Part A touches Common (a list edit). Whether that is a "behaviour change" for kit purposes was **Q1**; the Owner ruled **bump 10→11** in the Part A commit (two markers + TC-173's pin) rather than argue the reading. |
| **I-6** | **The probe can never fail, slow, or misdirect a run's data path beyond its own read cost.** | Every probe I/O is wrapped; any exception yields the list's answer (compress) and one WARN line. The probe reads at most `3 × 256 KiB` per *written* group, never per file and never for dedup hits. Files below the size floor (§2.2) are not probed at all. The probe never opens the destination. |
| **I-7** | **Determinism within a run and host** (G7: identical re-runs ⇒ identical manifest rows). | Fixed offsets, fixed sample size, fixed codec and level make the probe a pure function of the bytes on a given runtime. The known limit is stated, not hidden: a Deflate ratio that lands within noise of the threshold could flip across .NET runtime versions — it can only affect an object's **first** write (I-3), and both outcomes are correct forms. §6 Q2's threshold margin exists partly for this. |
| **I-8** | **No new exit code; IF-001 unchanged.** | A probe decision is a log line and a summary counter, never a failure. `CompressProbe` rides the JSON config's existing per-set object, which passes through IF-001's config bind mount unchanged. |

---

## 2. Design

### 2.1 Part A — the list, extended with what the review proved

Append to `$script:NonCompressibleExtensions` (`Common.psm1:115`), in the existing
groups, with the evidence class named in the comment:

| ext | group | evidence |
|---|---|---|
| `.z7` | archives | `file(1)`: `7-zip archive data, version 0.4` — the finding (C-1) |
| `.esd` | archives | Windows image, LZMA-compressed by definition |
| `.mpg` `.mpeg` `.m2ts` `.m4v` `.wmv` `.flv` | video | codec containers; same class as `.mp4`/`.mkv` already listed. `.mpg` is the file that prompted the review's original question. (`.mp4` was queried by the Owner and is **already** on the list — `Common.psm1:117`.) |
| `.heic` `.heif` | images | HEVC-coded stills; what current phones produce |
| `.opus` `.m4a` | audio | same class as `.aac`/`.ogg` already listed |

**Explicitly NOT added, with the review's reasons:** `.iso` (a filesystem container —
adding it is the §4 false-"already compressed" error), `.mca` (unconfirmed;
4.5 GB), `.bin`, `.dng`, `.pdf` (plausible but unproven; and these are exactly what
Part B is for). Part A is the accepted-known-formats fast path that §5 says is worth
having *regardless* of B; it is not an attempt to make the list complete.

Part A also updates the README table (TC-096 diffs it against the live list), the
`StorageForm.Tests.ps1` TC-096 parameter block, and the LLR-004 detail text.

### 2.2 Part B — the probe (`Measure-SampleCompressibility`, Engine)

An I/O shell with a pure core, per CLAUDE.md:

- **`Measure-SampleCompressibility -Path -SampleBytes 262144 -Samples 3`** (I/O):
  opens the source read-only with `FileShare.ReadWrite|Delete` (the same tolerance the
  hasher needs on a live tree), reads `Samples` windows at offsets `0`,
  `(len−sample)/2`, `len−sample` (de-duplicated when the file is smaller than three
  windows; a file below one window is read whole), Deflate-compresses each with
  `System.IO.Compression.DeflateStream` at `CompressionLevel.Fastest` into a counting
  null sink, and returns the per-sample ratios `compressed/raw`. Returns `$null` on any
  exception. No native dependency: `DeflateStream` ships with pwsh 7 on Windows and in
  the container image. **Why Deflate-fastest as a proxy for LZMA `-mx=9`:** the probe
  answers "is this near-uniform entropy?", and on that question the codecs agree; where
  Deflate-fastest finds ≥10%, LZMA-9 finds far more, and where LZMA-9 found 5% (the `.z7`
  set) Deflate-fastest finds ~0%. Precedent: ZFS LZ4 early-abort, Btrfs entropy sampling.
  **Is 256 KiB enough per sample?** (Owner's question.) For the entropy question, yes
  with margin: Deflate's window is 32 KiB, so one sample spans eight windows, and ZFS
  decides from 4 KiB. What a sample cannot see is a compressible region *between* the
  offsets of a mixed file — a matter of sample **count**, not size — and the any-sample
  rule already tilts that miss toward compressing. Three samples stay; scaling the count
  with file length is a one-constant change if production counters ever justify it.
- **`Resolve-CompressionDecision`** (pure, unit-testable, no I/O): inputs
  `ListSaysCompress`, `IsRuledFormat`, `Length`, `ProbeEnabled`, `ProbeMinBytes`,
  `Ratios`, `Threshold`; output a small record `{ Compress; Reason }` where `Reason ∈
  {Disabled, ListExempt, Ruled, BelowFloor, ProbeUnavailable, ProbeCompressible,
  ProbeIncompressible}`. Rule, in order:
  1. ruled format → `Ruled`, compress (I-2; before everything, in every mode);
  2. mode `Off`, or `Length < ProbeMinBytes` → the list's answer (`ListExempt` raw or
     compress — today's behaviour);
  3. mode `ExcludedExtensions` and the list says no → `ListExempt`, raw; in mode
     `Always` the list is not consulted above the floor;
  4. probe unavailable (`$null`) → `ProbeUnavailable`, compress, one WARN;
  5. **any** sample ratio `≤ 1 − Threshold` → `ProbeCompressible`, compress;
  6. otherwise → `ProbeIncompressible`, raw.

  Step 5's *any-sample* rule is the conservative choice the review's §4 asks for: a
  mixed file with one compressible region is compressed (7-Zip's per-chunk fallback then
  handles the rest cheaply); only a file that is incompressible **everywhere we looked**
  is stored raw.
- **Defaults (Q2/Q3, ruled):** `Threshold = 0.10` (ZFS uses 12.5% on 4 KiB; we sample
  64× more bytes, so 10% has ample margin both ways — the `.z7` set would read ~0%, text
  ~60–80%), `ProbeMinBytes = 256 KiB` (below it the file is at most one sample window,
  7-Zip's cost is process spawn rather than compression, and the list decides). Both are
  `$script:` constants in Engine, surfaced through `Get-FileBackupDefaults`-style
  read-only access for tests; **neither is a config key** in this package (§7).

### 2.3 The ruled list — what measurement may not overrule

`$script:RuledCompressibleExtensions` in **Engine**, beside the probe, consumed only by
`Resolve-CompressionDecision`:

```
.docx .xlsx .pptx   .odt .ods .odp   .txt
```

The OOXML/ODF entries are the ones that matter: they are zip containers a probe would
classify as incompressible, and SN-003's acceptance names `.docx`. `.txt` is included
for legibility only — text passes any probe — so that the list *reads* as SN-003's
sentence. Formats SN-003 does not name (`.epub`, `.jar` — already exempt — `.pdf`) are
**not** ruled; they get measured, which is the point. Extending the ruled list is an
Owner decision recorded in this file, not a code-review nicety (the review's §6: *"the
list changes job — from 'what to skip' to 'what the measurement may not overrule'"*).

**TC-096's over-claim is corrected in Part B.** Its "SN-003 acceptance-line extensions"
arm currently asserts `.bin`, `.csv` and `.log` compress *because SN-003 says so*;
SN-003 names `.docx`/`.txt` only. The arm is split: `Test-ShouldCompress`'s list answer
for those extensions is unchanged and still asserted (the list has no opinion on them),
and the **composed** decision's SN-003 pin moves to TC-224 with the actual ruled set.

### 2.4 Wiring — lazily, in `Invoke-BackupFileGroup`

Today `$ownerCompress` is computed unconditionally at `Engine.psm1:4945`, before the
group knows whether it will write at all. Part B makes it **lazy**: the list answer stays
where it is (cheap, and the tests that pin owner election read it), and the probe runs
only inside the `else` branch that actually writes (`:4987`), once per group, against the
**owner's** source path — every member has the same bytes, so any member's probe is the
group's. On a first full run this is one probe per written group; on an incremental run
it is one per *new* content group. Dedup hits (`$existingBackupWithHash`) and in-run
adoption (`$writtenThisRun`) never probe (I-3).

The decision's `Reason` is logged once per written group at `DEBUG`
(`compress-decision: <rel> <Reason> ratios=<r1,r2,r3>`), and the set summary gains two
counters: `Probe stored raw: <n> files, <bytes>` and `Probe compressed: <n>`. This is
the visibility the review says the trade never had; under WP16's SR-079 threshold the
per-group line is suppressed by default and the summary is `INFO`. If WP16 has not
landed when WP17 does, the per-group line still goes through the existing `& $log`
sink and is bounded by written-group count, which is already the log's dominant term.

### 2.5 The probe mode — `CompressProbe` (per set; Owner-ruled shape)

A new optional per-set JSON key, validated where SR-042/SR-063 validate every other set
key (an unknown key is already an exit-2 refusal, so the schema, the validator and the
README field table change together). Three values, case-insensitive, any other refused:

| value | above the floor | below the floor |
|---|---|---|
| `Off` | list only — exactly the pre-WP17 path plus Part A's additions | list |
| `ExcludedExtensions` | the list still exempts; everything it would compress is probed | list |
| **`Always`** (default) | **every file is probed, listed extensions included**; the list is not consulted | list |

The ruled list (§2.3) precedes all three (I-2). `Always` is the Owner's ruling (Q4): the
name is not evidence, so the default does not consult it where measurement is
available — which also recovers the review's §4 second direction (a store-mode `.zip`, a
lightly-compressed `.avi`) that `ExcludedExtensions` cannot. Its cost is one
`3 × 256 KiB` read per **written** group for listed extensions too — on the census,
5,088 `.mp4` and 70,314 `.jpg` files, most below or near the floor, at first-run time
only. No other tunable is exposed: threshold and floor are constants (§7).

**Why default-`Always`.** The change direction is safe (both forms correct), the cost is
bounded (I-6), and the failure mode it fixes was silent for the product's whole life —
in both directions. `ExcludedExtensions` exists for a set whose listed content is
enormous and whose operator would rather trust the name; `Off` is the kill switch.

### 2.6 What the operator sees

README "Already-compressed extensions" becomes "How the stored form is chosen": (1) the
exempt list, extended; (2) the probe — what it samples, the threshold, the
any-sample rule, the size floor, and the statement that it errs toward compressing;
(3) the ruled list and its SN-003 origin; (4) the three `CompressProbe` modes; (5) the unchanged
paragraph that nothing already stored is re-formed. AGENTS.md §3's "compression is
per-file (SR-004)" bullet gains: *"decided by the exempt list first, then — for
anything the list would compress and no ruling protects — by a sampled probe of the
bytes (SR-081)"*. The `-mx=9` choice itself is out of scope (§7).

---

## 3. Requirements deltas

Registry rows land **before** the code, in their own commit, with
`python scripts/trace.py --strict` green. Ids are provisional after WP16's reservations.

| id | change |
|---|---|
| **SN-003** | *Unchanged — Owner ruling (Q5).* Its rationale already says *"already-compressed media shouldn't be re-packed"* and its acceptance line is what I-2 protects. No new need is minted and the text is not edited: WP17 realizes the existing need better, and SR-081's rationale carries the content-based sentence. |
| **SR-004** | *Amended.* "...except for already-compressed extensions" becomes "...except for (a) already-compressed extensions and (b) content the SR-081 probe measures as incompressible; formats SN-003 rules on are always compressed." Acceptance keeps the name/column agreement sentence verbatim. Permutations cell gains `mode=set{Off,ExcludedExtensions,Always}; decision=set{list-exempt,ruled,probe-compressible,probe-incompressible,below-floor,probe-unavailable}`. |
| **SR-081** *(new)* | **Measured compressibility gate.** The probe's inputs and outputs (§2.2), the ordered decision rule, the any-sample conservatism, the size floor, the fail-toward-compress contract (I-6), the ruled override (I-2), lazy evaluation only at a group write (I-3), the three-valued per-set `CompressProbe` mode with `Always` default (§2.5), the log line and summary counters, and the explicit non-claims: no re-forming, no restore involvement, no new exit code. Refs `SN-003`, `SN-011`. Verification: `Test`. |
| **SR-042 / SR-063** | *Amended (schema only).* `CompressProbe` added to the per-set key set with its three values and `Always` default; an unknown value is refused like any other schema violation. |
| **LLR-004** | *Amended.* Records the Part A additions and their evidence classes; records that Test-ShouldCompress is now the **first** of two gates, not the whole decision. |
| **LLR-086** *(new)* | Engine: `Measure-SampleCompressibility`, `Resolve-CompressionDecision`, `$script:RuledCompressibleExtensions`, the two constants, the lazy call site in `Invoke-BackupFileGroup`, the log/summary emission. `Module = FileBackup.Engine`. |
| **LLR-003 / LLR-058 / LLR-060** | *Untouched.* The write path, the name grammar and the owner election are not changed — only the boolean fed to them. |
| **TC-173** | *Amended (Q1 ruled: bump):* both KitRevision markers read **11**. |

**LLR → TC map:** LLR-004 → TC-096 (amended), TC-222 · LLR-086 → TC-223, TC-224,
TC-225, TC-226, TC-227, TC-228, TC-229.
**SR → TC map:** SR-004 → TC-002, TC-096, TC-222, TC-224 · SR-081 → TC-223…TC-230 ·
SR-042/063 → TC-227.

---

## 4. Work parts

### Part A — Common: the list (LLR-004 amended)

`Common.psm1` list edit; README table; TC-096 parameter block; LLR-004 detail; both
`KitRevision` markers 10→11 and TC-173's pin, in the same commit (Q1, ruled).
Gate: `pwsh scripts/check.ps1 -Tier Smoke`. This is the commit the hub can ship alone.

### Part B1 — Engine: probe + pure decision (LLR-086)

The two functions, the ruled list, the constants, comment-based help + `Implements:`
lines, and unit tests against **synthetic corpora built in the test**: random bytes
(incompressible everywhere), repeated text (compressible everywhere), a random file with
a 64 KiB text head (mixed: compressible at offset 0 only → must compress under the
any-sample rule), a 4 KiB file (read whole), an empty file, a vanished path, a path held
open with `FileShare.None` (→ `$null`, decision `ProbeUnavailable`). Gate: Smoke.

### Part B2 — Engine: wiring, config key, telemetry (SR-081, SR-042/063)

Lazy call site in `Invoke-BackupFileGroup`; `CompressProbe` in the validator, the
schema doc, the README table; DEBUG line and summary counters; integration cases in the
Compress arm of the suite (§5). Gate: `-Tier Full`.

### Part C — Docs

README §2.6 rewrite; AGENTS.md §3 clause; `scripts/gen_arch_map.ps1` refresh if the
module map changes (it will — two new public Engine symbols); status.md. Gate: Smoke +
`check.ps1`'s generated-docs freshness.

---

## 5. Test cases (TC-222 onward, provisional)

Permutations cell for `python scripts/gen_cases.py`:

```
content=set{random,text,mixed-head,mixed-tail,small,empty}; ext=set{listed,ruled,unlisted,none}; mode=set{Off,ExcludedExtensions,Always}; size=set{below-floor,above-floor}; dedup=set{fresh,existing-hit,in-run-twin}
```

| id | Case | Why it is not optional |
|---|---|---|
| **TC-222** | Part A: every added extension returns `$false` from `Test-ShouldCompress`, case-insensitively; `.iso` still returns `$true`. | Pins the list *and* the deliberate non-addition. |
| **TC-223** | `Measure-SampleCompressibility` on the synthetic corpora: ratios ≈1.0 for random, ≪1 for text, `[≪1, ≈1, ≈1]` for mixed-head, a single ratio for a sub-window file, `$null` for vanished/locked. | The I/O shell's contract, including its refusal to throw. |
| **TC-224** | **SN-003 pin (I-2):** a `.docx` whose bytes are random (so the probe says incompressible) is stored `.7z`, `Compressed=Yes`. **Negative control:** with the ruled list emptied, the same input is stored raw — the test must go red. | The one place WP17 could silently reverse a stakeholder ruling. |
| **TC-225** | Mode `Always`: an unlisted extension (and a no-extension file) above the floor with random bytes is stored **raw**; with text, stored `.7z`; with mixed-head, stored `.7z`; **a listed extension (`.zip`) over text bytes is stored `.7z`** (the list is not consulted) and over random bytes raw. Filename and `Compressed` agree in every arm (I-1). | The finding itself, the any-sample rule, SR-004's agreement sentence, and the default mode's defining property. |
| **TC-226** | **Laziness (I-3):** a group whose `(hash,length)` already exists in the prior backup, and a second member of a group written this run, never call the probe (asserted by a mocked `Measure-SampleCompressibility` with a call counter). | The probe must not add a read per file, only per *written group*. |
| **TC-227** | `CompressProbe: Off` reproduces the pre-WP17 decision for TC-225's inputs; `ExcludedExtensions` stores the `.zip`-over-text arm raw (list exempts) but still probes the unlisted arms; an absent key behaves as `Always`; an invalid value (`"maybe"`) is refused with exit 2 and nothing created (SR-043). | The three modes, the default, and the schema contract. |
| **TC-228** | A probe that throws (mocked) yields compress + one WARN, and the run exits 0 (I-6). | Fail-toward-compress, never fail-the-run. |
| **TC-229** | `-Action Verify` (SR-049, TC-093's harness) over a store mixed by the probe reports **clean**; `Reconstruct.ps1` and `reconstruct.sh` restore it byte-exact. | Proves both forms are still just forms. |
| **TC-230** | Container arm (Release tier): TC-225 inside the image — `DeflateStream` works on the hub's stack and the summary counters appear in `backup.log`. | Linux is where the defect was measured. |

Negative controls that must be shown to fail fix-removed: **TC-224** (ruled list
emptied), **TC-225** (probe bypassed), **TC-226** (laziness removed).

---

## 6. Open questions — RULED by the Owner, 2026-08-31

All seven were answered on the day the plan was drafted; the rulings are folded into
the text above and recorded here so the cross-reviewers know what is decided.

| # | Question | Ruling (folded at) |
|---|---|---|
| **Q0** | Scope | **A + B + ruled list + mode**, as proposed. Part A shippable alone (§8 row 3). |
| **Q1** | KitRevision for the Common list edit | **Bump 10→11** in the Part A commit (§4 Part A, TC-173). |
| **Q2** | Threshold | **0.10** (§2.2). |
| **Q3** | Size floor | **256 KiB**, not the drafted 1 MiB (§2.2). |
| **Q4** | Probe default | **`Always` — probe all files, all extensions** above the floor; `CompressProbe` is `Off` / `ExcludedExtensions` / `Always` (§2.5). The driver's reading that the SN-003 ruled list still precedes the probe under `Always` is recorded at I-2 and is the one interpretation to confirm at cross-review. |
| **Q5** | Edit SN-003's acceptance | **No** — not surfaced; SR-081 carries the sentence (§3). |
| **Q6** | The live hub run | **Already stopped** (§9). |
| — | Owner also asked | `.mp4` is already on the list (§2.1 — `.mpg`/`.mpeg` were the missing MPEG entries); 256 KiB per sample is sufficient for the entropy question (§2.2). |

<details><summary>The questions as originally put, with the driver's recommendations (historical)</summary>

| # | Question | Recommendation | Fallback if the answer is bad |
|---|---|---|---|
| **Q0** | Scope: A + B + ruled list + kill switch, as proposed? Or A alone now and B as a later package? | **A + B together**, one plan, Part A shippable alone (§8 row 3 is a complete deliverable). A-alone repeats the review's §2 argument: the list has been fixed before and missed 43% anyway. | Ship Part A; park B1/B2 with this plan as their spec. |
| **Q1** | Does Part A's `Common.psm1` list edit bump `KitRevision` (AGENTS.md: *"whenever any kit-bundled file changes behavior"*)? Restore never calls `Test-ShouldCompress`, but the file is bundled and the rule is written broadly; WP16 read the same rule strictly (its I-3). | **Bump 10→11** in the Part A commit. It costs two markers and a TC-173 edit and removes an argument about a reading. | No bump; record the narrower reading in AGENTS.md so the next plan does not re-litigate it. |
| **Q2** | Threshold `0.10`? | Yes, with §2.2's reasoning; revisit only with production ratios from the summary counters. | Any value in 0.08–0.15 is defensible; the any-sample rule dominates the outcome more than the exact figure. |
| **Q3** | Size floor `1 MiB`? | Yes. On the census, everything that matters is ≥ 1 GB; the floor only protects the small-file tail from a read that is a large fraction of the copy. | 256 KiB–4 MiB all fine. |
| **Q4** | Probe **default on**? | **On** (§2.5). | Default off with `CompressProbe: on` documented for the hub's config — fixes the hub, not the class. |
| **Q5** | Edit SN-003's acceptance to name content-based exemption explicitly? | Optional; a one-line addition keeps the top of the spine honest about what SR-081 realizes. | Leave SN-003; SR-081's rationale carries the sentence. |
| **Q6** | **The live hub run** (§9): let the ~9-day first pass finish, or stop it and rerun after Part A ships? | See §9 — the plan cannot make this call; it needs one fact verified first. | — |

</details>

---

## 7. Deliberately deferred, with reasons

| item | why not now |
|---|---|
| **C — measure during hashing, store in the manifest** | The cheapest *I/O* home but the most expensive *contract*: a tenth manifest column touches the 9-column invariant, `Read-/Write-Manifest`, the witness, both restorers' parsers, `KitRevision`, and the source hash-cache format — for a saving of `3 × 256 KiB` per written group, which B already makes negligible. If production counters ever show the probe's read cost matters, C is the upgrade path and B's decision core is reused unchanged. Note the cross-document coupling the review names: C would land in the phase WP16 instruments. |
| **D — size gate** | Subsumed by B (the floor is the *inverse* gate, protecting small files) and rejected on the review's own argument: the largest files are exactly where a right answer pays most. |
| **E — per-set extension-list override** | Pushes a data question onto the operator (review §5 E). B answers it from the bytes. Only the kill switch survives. |
| **Threshold / floor as config keys** | Two knobs nobody can measure; the mode is the operator's lever. Revisit with production counters. |
| **Sample count scaling with file length** | Raised by the Owner's sample-size question (§2.2). Three fixed offsets first; scale only if the summary counters show mixed-content misses in practice. |
| **`-mx=9` itself** | A different question (CPU per compressible byte, not *whether* to compress). Worth its own short review with real ratios from the counters; out of scope here. |
| **HomeHub's `common.sh` list also lacks `.z7`** (review C-3) | A HomeHub defect; file it there. This repo's IF-001 does not govern HomeHub's own backup script. |

---

## 8. Sequencing

Each row is one small green commit (CLAUDE.md commit cadence).

| # | Commit | Gate on |
|---|---|---|
| 1 | Defect review + this plan (+ its cross-review round, §10) | *(this file)* |
| 2 | Registry deltas (§3) | `python scripts/trace.py --strict` green, orphans 0 |
| 3 | **Part A** — list, README table, TC-096/TC-222, LLR-004, KitRevision per Q1 | `pwsh scripts/check.ps1 -Tier Smoke` — **the hub can ship from here** |
| 4 | Part B1 — probe + decision core + TC-223 | Smoke |
| 5 | Part B2 — wiring, `CompressProbe`, telemetry, TC-224…TC-228 incl. negative controls | `-Tier Full` |
| 6 | **Independent review round** (dual: Codex CLI + fresh-context Opus; coordinator consolidates, §11) → fold | re-run row 5's gate |
| 7 | Part C — docs, generated map, status.md; TC-229 | Smoke + freshness |
| 8 | TC-230 container evidence | `-Tier Release`, real output pasted |

**Review sizing.** Plan-stage: the same dual cross-review WP14/WP16 had (this document's
§10 once run). Implementation: **dual** after row 5 — not because WP17 can corrupt data
(it cannot re-form, and both outcomes restore) but because it edits the SR-060 owner-
election write branch and the config validator, and the last three independent rounds
on this repo each found P0s in-house testing missed. Part A alone would merit a single
reviewer.

---

## 9. The hub run — separate from all of the above

**The Owner stopped the production first pass on 2026-08-31 (Q6).** It was ~5 h into
step 10 with ~859 GB of `.z7` ahead of it (review §1c). The rerun waits on Part A in a
rebuilt image (§8 row 3), and two facts govern it:

1. **The hub's image does not carry WP14.** An external stop re-creates the stale-`Temp`
   wedge the first review documented; the README stale-lock procedure (WP14 §9's
   `mv Temp Temp.stale-<date>`) must be run by hand before the rerun, after confirming
   as WP14 §9 did that `Temp` holds no snapshot and no data file. This time `Temp` may
   hold the step-7 pre-run snapshot of the prior manifest — inspect before moving.
2. **Unverified by this plan — the coordinator verifies it read-only in Phase 1:** what
   a rerun does with the objects step 10 already wrote to the backup root under
   content-addressed names when step 12's manifest was never written — whether steps
   6/9 adopt them, whether the SR-064 orphan scan reports or moves them, or whether
   step 10 simply overwrites them (`Copy-Item -Force`; `Compress-FileWithSevenZip`
   replaces). Correctness is not in doubt under any of those; **wasted work and a noisy
   first Verify report are**, and the answer tells the Owner what the rerun's first
   hours and first `-Action Verify` will look like. The step-5 hash cache in
   `SourceStatePath` is written at the end of step 5, so the ~8-hour hash is not
   repeated (subject to `HashRecalcFreq`).

Nothing in WP17's code depends on either answer.

---

## 10. Plan-stage review round — composite disposition

*(To be filled by the coordinator after the dual cross-review; WP14 §10 / WP16 §9
style: one row per finding, `Accepted — folded at §x` / `Rejected — <reason>`, findings
raised independently by both reviewers marked.)*

## 11. Implementation review round — composite disposition (after commit 5)

*(Same format; filled after row 6 of §8.)*
