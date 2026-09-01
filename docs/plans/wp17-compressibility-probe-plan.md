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
is already stopped (§9). **Revision 3 (2026-09-01):** the plan-stage cross-review
(OpenAI Codex CLI + a fresh-context Opus reviewer, coordinator-consolidated) raised
2 P0 / 27 P1 / 12 P2 across 41 findings; every disposition is in **§10**, every accepted
finding is folded, and the one open item it produced is **Q7** (§6). Registry ids in this document are
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
raw when the sampled bytes **in aggregate** fail to shrink by the threshold — a rule
that neither sends a multi-gigabyte random file to `-mx=9` because its first 64 KiB
was text (the review's failure mode, re-created) nor skips a file a third of which
compresses. A short **ruled list** keeps `.docx`/`.txt`-class formats on their SN-003
path no matter what the bytes say (review §6): the extension list does not disappear, it
changes job. The probe runs **lazily** — only when the group actually has to write, never
for content dedup already owns — and never fails a run: any probe error falls back to the
list's answer — and `CompressEnabled=false` dominates everything: no probe, no
compression, exactly as today. `CompressProbe: off` restores exactly today's behaviour.

---

## 1. What must remain true

| # | Invariant | How this plan holds it |
|---|---|---|
| **I-1** | **`Compressed` and the stored filename agree for every object** (SR-004 acceptance; AGENTS.md §3 "the filename must not lie"). | The probe changes the *input* to the existing decision, not the write path: `$dataExt`/`Compressed` are still both derived from the one `$ownerCompress` boolean at `Engine.psm1:4990`. TC-093's storage-form audit (SR-049) runs over a probe-mixed store and reports clean. |
| **I-2** | **SN-003's stakeholder ruling is not reversed by measurement — in either direction.** *"With compression on, a `.docx`/`.txt` is stored as `.7z`; a `.jpg`/`.mp4` is stored as-is."* Both clauses are rulings. | The ruled list (§2.3) is **directional** — `Compress` for the `.docx`/`.txt` family, `Raw` for `.jpg`/`.mp4` — and is consulted **before** the probe in **every** probing mode, `always` included. A `.docx` (a zip container the probe would call incompressible) is stored `.7z`; a `.jpg` whose bytes happen to compress (a BMP under a `.jpg` name) is stored raw. Both are what SN-003 says, and neither is what the bytes say. TC-224 pins both directions and is the negative control that must fail with the ruled list emptied. **Q7** asks the Owner to confirm the `Raw` half, because it withholds exactly two extensions from `always`'s "probe everything". |
| **I-3** | **Nothing already stored is ever re-formed** (SR-061). | WP17 has no migration in either direction. An object dedup already locates (`$existingBackupWithHash`) is adopted **before** the probe is ever consulted (§2.4 lazy evaluation), so no existing object's form is re-decided. README's "mixed-form store is normal" paragraph gains one clause, not a new rule. |
| **I-4** | **The extension list stays the ONE definition, in Common** (LLR-004; TC-096 pins one definition site and zero Engine references). | Part A appends to `$script:NonCompressibleExtensions` in place. Part B adds no second copy: Engine calls `Test-ShouldCompress` as it does today and composes the probe *after* it. The ruled list is a **different** set with a different name and job, and TC-096's "Engine has no `NonCompressibleExtensions` reference" arm stays true. |
| **I-5** | **`Common` never depends on `Engine`; KitRevision bumps whenever a kit-bundled file changes behaviour** (AGENTS.md §3). | The probe, the ruled list and the composition live in **Engine**. Only Part A touches Common (a list edit). Whether that is a "behaviour change" for kit purposes was **Q1**; the Owner ruled **bump 10→11** in the Part A commit (two markers + TC-173's pin) rather than argue the reading. |
| **I-6** | **The probe can never fail, slow, or misdirect a run's data path beyond its own read cost.** | Every probe I/O is wrapped; if no member of the group can be sampled, the decision is **the list's answer** — today's behaviour, not "compress" — with one WARN. The probe reads at most `3 × 256 KiB` per *written* group (once, memoized at group scope — a failed member write does not re-probe), never per file and never for dedup hits. Files below the floor are not probed. The probe never opens the destination. |
| **I-7** | **Determinism within a run and host** (G7: identical re-runs ⇒ identical manifest rows). | Fixed offsets, fixed sample size, fixed codec and level make the probe a pure function of the bytes on a given runtime. The known limit is stated, not hidden: a Deflate ratio that lands within noise of the threshold could flip across .NET runtime versions — it can only affect an object's **first** write (I-3), and both outcomes are correct forms. §6 Q2's threshold margin exists partly for this. Part B1's calibration item (§2.2) records the codec's behaviour on the real corpus classes so the margin is measured, not assumed. |
| **I-8** | **No new exit code; `ConfigVersion` stays 2; IF-001 revised by a note only.** | A probe decision is a log line and a summary counter, never a failure. `CompressProbe` is an **optional, additive** per-set key: an unchanged v2 document still loads (and resolves to `always`), and IF-001's *"closed schema"* sentence gains the key name. An older build rejects the new key by name, which is the closed schema working as designed. SR-063's amendment ratifies the additive-optional policy explicitly (§3) so the next optional key does not re-open the question. |

---

## 2. Design

### 2.1 Part A — the list, extended with what the review proved

Append to `$script:NonCompressibleExtensions` (`Common.psm1:115`), in the existing
groups, with the evidence class named in the comment:

| ext | group | evidence |
|---|---|---|
| `.z7` | archives | `file(1)`: `7-zip archive data, version 0.4` — the finding (C-1) |
| `.esd` | archives | Windows image, LZMA-compressed by definition |
| `.mpg` `.mpeg` `.m2ts` `.m4v` `.wmv` `.flv` | video | codec containers; same class as `.mp4`/`.mkv` already listed. `.mpg` is the file that prompted the review's original question. (`.mp4` was queried by the Owner and is **already** on the list — `Common.psm1:118`.) |
| `.heic` `.heif` | images | HEVC-coded stills; what current phones produce |
| `.opus` `.m4a` | audio | same class as `.aac`/`.ogg` already listed |

**Explicitly NOT added, with the review's reasons:** `.iso` (a filesystem container —
adding it is the §4 false-"already compressed" error), `.mca` (unconfirmed;
4.5 GB), `.bin`, `.dng`, `.pdf` (plausible but unproven; and these are exactly what
Part B is for). Part A is the accepted-known-formats fast path that §5 says is worth
having *regardless* of B; it is not an attempt to make the list complete.

Part A also updates the README table (TC-096 diffs it against the live list), the
`StorageForm.Tests.ps1` TC-096 parameter block, and the LLR-004 detail text.

**Two facts about Part A the reviewers made explicit.** First, under the shipped default
(`always`) every `.z7` in the census is far above the floor, so the **probe**, not the
list, is what saves the nine days once Part B lands; Part A's durable value is the
below-floor tail, the two non-default modes, and the interim window before B2 ships.
Second, Part A alone creates a **`-Action Verify` cost regression**: the SR-049 audit's
payload exemption (`Engine.psm1:1633`) takes a cheap path only for a `.7z`-named
RelativePath and otherwise **re-hashes** every raw-stored object whose bytes carry 7-Zip
magic while its row says `Compressed=No` — which, after Part A, is all 649 `.z7` files
(880 GB per Verify). The code's own comment calls that case "rare"; Part A makes it
43% of the library. **Part A therefore carries an LLR-049 amendment (§3):** the
non-`Deep` scan exempts a `Compressed=No` archive-magic object when its DataPath
extension equals the row's RelativePath extension *and* its on-disk length equals the
row's `Length` — an object stored raw under its own name, at its own size — and reserves
the confirming hash for `-Deep`. This is the one WP17 edit inside a data-integrity
audit; TC-229 gains an arm asserting the exemption is taken without a hash, and the
§8 dual review covers it.

### 2.2 Part B — the probe (`Measure-SampleCompressibility`, Engine)

An I/O shell with a pure core, per CLAUDE.md:

- **`Measure-SampleCompressibility -Path -SampleBytes 262144 -Samples 3`** (I/O).
  Opens the source read-only with **`FileShare.Read`** — the same share the hasher
  (`Common.psm1:352`) and the form sniffer (`Common.psm1:847`) use, so probe success
  predicts copy success and no window can sample a file being rewritten underneath it.
  A file that cannot be opened returns `$null`; the caller's fallback (§2.4) is the
  list's answer, so a lock costs a decision, never a file. Geometry, stated exactly:
  `len < Samples × SampleBytes` → **one** read of the whole file as a single sample
  (this removes the 1.9× over-read the drafted "three overlapping windows" produced
  for the 256 KiB–768 KiB band); otherwise three windows at `Int64` offsets `0`,
  `(len − SampleBytes) / 2` (floor), `len − SampleBytes`, each filled by an exact-read
  loop (a short `Read` is retried until the window is full or EOF). Each window is
  compressed into a counting null sink and the compressed length is read **after
  `Dispose()`** — a count taken before the encoder is closed reads short and would
  call random bytes compressible. Returns `[SampledBytes; CompressedBytes]` totals plus
  the per-window ratios for the log line. Empty files are unreachable above the floor
  and return `$null` from a direct call.
- **Codec.** `System.IO.Compression.DeflateStream` at `CompressionLevel.Fastest` is
  the drafted choice; its **32 KiB history** is the reviewers' one substantive objection
  (Codex #7): repeated blocks farther apart than that — VM images, database pages —
  compress well under LZMA's 64 MB dictionary and not at all under Deflate, and the
  synthetic fixtures cannot see it. **`BrotliStream` at `Fastest`** (also in-box .NET,
  window 4 MB by default, covers a whole 256 KiB sample) is the alternative. **Part B1
  carries a calibration item**: a throw-away script (scratch, not shipped) runs both
  codecs and real `7z -mx=9` over the corpus classes the review names — genuine `.z7`,
  a store-mode `.zip`, media, text, a long-range-repetition file, mixed content — and
  the codec is chosen from that table, recorded in LLR-086 with the numbers. The
  decision rule and every test are codec-agnostic. Whichever codec wins, on the
  question the probe asks — "is this near-uniform entropy?" — the `.z7` set reads ~0%
  and text ~60–80%; precedent: ZFS LZ4 early-abort, Btrfs entropy sampling.
  **Is 256 KiB enough per sample?** (Owner's question.) For that question, yes with
  margin: a window spans eight Deflate histories or a fraction of one Brotli window, and
  ZFS decides from 4 KiB. What a sample cannot see is a compressible region *between*
  the offsets — a matter of sample **count**, not size. Three samples stay; scaling the
  count with file length is a one-constant change if production counters justify it.
- **`Resolve-CompressionDecision`** (pure, no I/O). One signature, no ambiguity:
  `CompressEnabled`, `Mode` (`off` | `excluded-extensions` | `always`),
  `ListSaysCompress` (the `Test-ShouldCompress` answer, computed with `-CompressEnabled
  $true` so it carries only the list's opinion), `RuledDecision` (`Compress` | `Raw` |
  `None`, §2.3), `Length`, `ProbeMinBytes`, `SampledBytes`, `CompressedBytes`,
  `Threshold`. Output `{ Compress; Reason }` with `Reason ∈ {CompressDisabled, Ruled,
  ModeOff, BelowFloor, ListExempt, ProbeUnavailable, ProbeCompressible,
  ProbeIncompressible}`. Rule, in order:
  0. `CompressEnabled = false` → raw, `CompressDisabled`. **Nothing below runs.** (Both
     reviewers' P0: today this guard lives inside `Test-ShouldCompress`, and a rule
     that consulted the ruled list or the probe first would name a `.7z` object and
     record `Compressed=Yes` on a Plain set — and, with 7-Zip not even resolved for a
     Plain set, `Copy-SourceFileToBackup` would raw-copy under that name.)
  1. `RuledDecision ≠ None` → that decision, `Ruled` (I-2; every mode).
  2. `Mode = off` → the list's answer (`ListExempt` raw, else compress — today).
  3. `Length < ProbeMinBytes` → the list's answer, `BelowFloor`.
  4. `Mode = excluded-extensions` and the list says no → raw, `ListExempt`.
  5. probe unavailable (`$null`) → **the list's answer**, `ProbeUnavailable`, one WARN.
  6. `CompressedBytes ≤ (1 − Threshold) × SampledBytes` → compress, `ProbeCompressible`.
  7. otherwise → raw, `ProbeIncompressible`.

  Rule 6 is the **aggregate** rule, replacing the drafted any-sample rule on Codex #6's
  argument: a multi-gigabyte random file with a 64 KiB text head would have passed
  any-sample and gone to `-mx=9` whole — the review's own failure mode. Aggregate over
  768 KiB: a file one-third compressible reads ≈0.7 and compresses; a 64 KiB head reads
  ≈0.93 and stays raw. TC-223's fixtures pin both.
- **Defaults (Q2/Q3, ruled):** `Threshold = 0.10`, `ProbeMinBytes = 256 KiB`. Both are
  `$script:` constants **in Engine**, read by tests through `InModuleScope` — there is no
  Common accessor (adding one would edit Common again) and no config key (§7).

### 2.3 The ruled list — what measurement may not overrule

`$script:RuledCompressionDecisions` in **Engine**, beside the probe, consumed only by
`Resolve-CompressionDecision`, **directional**:

```
Compress:  .docx .xlsx .pptx   .odt .ods .odp   .txt
Raw:       .jpg .mp4                                   (Q7)
```

The `Compress` entries are SN-003's first clause: OOXML/ODF are zip containers a probe
would classify as incompressible, and SN-003's acceptance names `.docx`. `.txt` is
included for legibility only. The `Raw` entries are SN-003's **second** clause, which
the drafted plan wrongly claimed would "hold under `always` because those bytes probe
incompressible" — an empirical property of typical files, not an invariant (both
reviewers). A boolean override could only force compression; a directional one keeps
both halves of the ruling literally true without editing SN-003 (Q5). The price is that
`always` withholds two extensions from the probe — **Q7**. Formats SN-003 does not name
(`.epub`, `.pdf`, `.iso`, everything else) are **not** ruled; they get measured, which
is the point. Extending either direction is an Owner decision recorded in this file.

**TC-096's over-claim is corrected in Part B.** Its "SN-003 acceptance-line extensions"
arm asserts `.xlsx`, `.csv`, `.log` and `.bin` compress *because SN-003 says so*;
SN-003 names `.docx`/`.txt` only. The arm is split: `Test-ShouldCompress`'s list answer
for those extensions is unchanged and still asserted, and the **composed** decision's
SN-003 pin moves to TC-224 with the actual ruled set.

### 2.4 Wiring — lazily, memoized, in `Invoke-BackupFileGroup`

Today `$ownerCompress` is computed unconditionally at `Engine.psm1:4945`, before the
group knows whether it will write. Both reviewers verified that nothing reads it before
the write branch (`:4990, 5025, 5071, 5079` are all inside the `else`), so it becomes
**lazy and memoized at group scope**: a `$decision` record initialized `$null` before
the member loop and resolved on first entry to the write branch (`:4987`). The memo
matters because the write branch is *inside* `foreach ($entry in $Group)` and a failed
member write `continue`s with `$writtenThisRun` still null — a naive lazy expression
would re-probe and re-WARN per failing member (both reviewers). Dedup hits
(`$existingBackupWithHash`) and in-run twins (`$writtenThisRun`) return before the
branch and never probe (I-3).

**The probe walks the group's candidates.** The copy path already tries the owner and
then every member because a locked owner must not fail a group a readable twin can
serve (`:5017-5022`, WP9 MIN-1). The probe builds the same list and samples the first
member it can open; only if none opens is the decision `ProbeUnavailable`.

**Plumbing named:** `Invoke-BackupFileGroup` gains `-CompressProbe` (defaulted for the
direct-unit-test path, as `-RetryBudgetMs` is at `:4915`), and the step-10 call site
(`:5979`) passes `$Set.CompressProbe`.

The decision's `Reason` is logged once per written group at `DEBUG`
(`compress-decision: <rel> <Reason> ratio=<agg> windows=<r1,r2,r3>`), and the set
summary gains per-set physical-object counters incremented **after a successful write**:
`Probe stored raw: <n> objects, <bytes>` / `Probe compressed: <n>` / `Probe reads:
<bytes>`, the last being the first-run cost figure §2.5 owes the operator. **WP16
interplay:** this is a new proportional `DEBUG` site. If WP16 lands first, its SR-079 /
LLR-082 / TC-212 enumeration of `DEBUG` sites is amended to include it in WP17's row 5;
if WP17 lands first, WP16's plan absorbs it — recorded in both plans' §7.

### 2.5 The probe mode — `CompressProbe` (per set; Owner-ruled shape)

A new optional per-set JSON key with an **exact-lowercase vocabulary**, matching the
`BrowseView` precedent (`Engine.psm1:6392`: `-cnotin`, and the published schema's
`enum` must equal it for TC-077's schema↔validator parity to hold):

| value | above the floor | below the floor |
|---|---|---|
| `off` | list only — exactly the pre-WP17 path plus Part A's additions | list |
| `excluded-extensions` | the list still exempts; everything it would compress is probed | list |
| **`always`** (default; absent key ⇒ `always`) | **every file is probed, listed extensions included**; the list is not consulted | list |

`CompressEnabled=false` precedes all three (rule 0); the ruled list precedes all three
(I-2). Any other value — mixed case included — is refused with the SR-042 exit 2
naming the key, in **both** config formats. **The change surface, enumerated** (the
draft named three places; the reviewers found nine): the closed key set in
`Assert-NoUnknownConfigKey` (`:6163`, JSON only); the value check in
`Test-BackupConfigurationShape` beside the `BrowseView` block (`:6388`), which runs for
JSON **and CLIXML** — the only place a CLIXML `"maybe"` is caught; the fixed field list
in `Resolve-BackupSetDefaults` (`:6468`), without which a validated key is silently
dropped; `container/FileBackup.schema.json` (`enum`); `container/FileBackup.example.json`;
`tests/Common/ConfigFixtures.ps1` (the one corpus TC-074/075/077 drive — TC-227's
accept/reject fixtures live there); `FileBackup.ps1`'s help and example config; the
README field table; IF-001's closed-schema sentence. `ConfigVersion` **stays 2** (I-8).

`always` is the Owner's ruling (Q4): the name is not evidence, so the default does not
consult it where measurement is available — which also recovers the review's §4 second
direction (a store-mode `.zip`, a lightly-compressed `.avi`) that `excluded-extensions`
cannot. **Its first-run cost, stated honestly** (the draft's "most below or near the
floor" was wrong — the census means are ≈105 MB per `.mp4` and ≈1.7 MB per `.jpg`):
on the order of **75,000 probes and ≈55 GiB of sampled reads** over the listed
extensions alone, plus the codec's CPU on those bytes, **once** — against ≈880 GB of
`-mx=9` avoided. Later runs probe only new content. TC-230 reports the `Probe reads`
counter and wall time from the container run so the figure is measured; no pass budget
is set until there is production data to set it from (§7).

### 2.6 What the operator sees

README "Already-compressed extensions" becomes "How the stored form is chosen" — keeping
`### Already-compressed extensions` as a sub-heading, because TC-096's parity regex
(`StorageForm.Tests.ps1:876`) anchors on that literal and Part A (row 3) must stay green
before Part C renames anything: (1) the
exempt list, extended; (2) the probe — what it samples, the threshold, the
any-sample rule, the size floor, and the statement that it errs toward compressing;
(3) the ruled list and its SN-003 origin; (4) the three `CompressProbe` modes and the first-run probe-read cost; (5) the unchanged
paragraph that nothing already stored is re-formed. AGENTS.md §3's "compression is
per-file (SR-004)" bullet gains: *"decided by the exempt list first, then — for
anything the list would compress and no ruling protects — by a sampled probe of the
bytes (SR-081)"*. The `-mx=9` choice itself is out of scope (§7).

---

## 3. Requirements deltas

Registry rows land **before** the code, in their own commit, with
`python scripts/trace.py --strict` green. Ids are provisional after WP16's reservations.
**Phase tag `probe-v1`** on every new row: `check.ps1`'s G3 criterion is
`--require-verified` filtered by a phase list (`check.ps1:122`), so Draft rows in a phase
not yet on that list do not fail the gate; the final commit (§8 row 9) flips them to
Verified and adds the phase to the list. Amended rows keep their current status and are
re-verified in the same commit as their amendment.

| id | change |
|---|---|
| **SN-003** | *Unchanged — Owner ruling (Q5).* Both acceptance clauses stay literally true (I-2). |
| **SR-004** | *Amended.* "...except for already-compressed extensions" becomes "...except for (a) already-compressed extensions, in mode `off`/`excluded-extensions` and below the floor in `always`, and (b) content the SR-081 probe measures as incompressible; formats SN-003 rules on take their ruled form in every mode." The acceptance clause *"an already-compressed extension is stored verbatim and Compressed=false"* is **re-scoped the same way** — under `always` above the floor TC-225 deliberately asserts the opposite. The name/column agreement sentence stays verbatim. Permutations: keep `compress=set{on,off}`; add `mode=set{off,excluded-extensions,always}; decision=set{compress-disabled,ruled-compress,ruled-raw,list-exempt,below-floor,probe-compressible,probe-incompressible,probe-unavailable}`. |
| **SR-081** *(new, `probe-v1`)* | **Measured compressibility gate.** Rule 0 (`CompressEnabled` dominates), the ordered rule, the aggregate threshold, the floor, the list-answer fallback (I-6), the directional ruled override (I-2), lazy memoized evaluation only at a group write walking the group's candidates (§2.4), the three-valued `CompressProbe` with `always` default, the log line and counters, and the explicit non-claims: no re-forming, no restore involvement, no new exit code. Refs `SN-003`, `SN-011`. Verification: `Test`. |
| **SR-042 / SR-063** | *Amended (schema).* `CompressProbe` joins the per-set key set with its exact-lowercase vocabulary and `always` default, validated in both formats; SR-063 additionally **ratifies the additive-optional-key policy**: an optional key with a default may join v2 without a version bump, and an older build's by-name rejection of it is the closed schema working as designed. |
| **LLR-004** | *Amended.* Part A's additions and evidence classes; `Test-ShouldCompress` is now the **first** of two gates, not the whole decision. |
| **LLR-042 / LLR-063** | *Amended.* `CodeSymbol` unchanged; detail gains `CompressProbe`'s validator placement (§2.5's nine surfaces). |
| **LLR-049** | *Amended.* The non-`Deep` payload exemption's cheap path (§2.1): raw-stored under its own extension at the row's length ⇒ exempt without hashing; `-Deep` keeps the confirming hash. |
| **LLR-058** | *Amended.* Its detail says the owner's *"`Test-ShouldCompress` answer"* defines the form; it becomes *"the owner's SR-081 decision"*, resolved lazily in the write branch. `CodeSymbol` unchanged. |
| **LLR-076** | *Amended.* Hard-codes *"Both restorers carry `# KitRevision: 10`"*; becomes the new value. |
| **LLR-086** *(new, `probe-v1`)* | Engine: `Measure-SampleCompressibility`, `Resolve-CompressionDecision`, `$script:RuledCompressionDecisions`, the two constants, the memoized call site and candidate walk in `Invoke-BackupFileGroup`, the `-CompressProbe` parameter and step-10 plumbing, the log/summary emission, the calibration table and the codec it chose. Helpers are module-internal, tested via `InModuleScope`; if exported, the `Export-ModuleMember` list (`:6590`) and the generated module map move in the same commit. |
| **IF-001** | *Notes amended.* The closed-schema sentence names `CompressProbe` as optional/additive; `Version` unchanged. |
| **TC-173** | *Amended.* Both KitRevision markers read the new value — and **`RestoreLaunchers.Tests.ps1:84`** is where the pin actually lives; WP16's TC-216 pins the same fact and the two are merged when the second of WP16/WP17 lands. |

**KitRevision is "current + 1 after rebase", not "11".** WP16's Q6 option (a) also takes
11. Whichever package lands second takes 12, and amends TC-173/TC-216 and LLR-076 again
in its own commit. AGENTS.md's kit-history paragraph gains the revision's one-line reason.

**LLR → TC map:** LLR-004 → TC-096 (amended), TC-222 · LLR-049 → TC-229 · LLR-058 →
TC-226 · LLR-042/063 → TC-227 · LLR-086 → TC-223…TC-228, TC-230, TC-231.
**SR → TC map:** SR-004 → TC-002, TC-096, TC-222, TC-224, TC-231 · SR-081 → TC-223…TC-231
· SR-042/063 → TC-227 · SR-049 → TC-229.

---

## 4. Work parts

### Part A — Common: the list (LLR-004 amended)

`Common.psm1` list edit; README table; TC-096 parameter block (incl. moving `.xlsx`
out of its SN-003 claim); LLR-004 detail; both `KitRevision` markers `current+1`,
TC-173's pin in `RestoreLaunchers.Tests.ps1:84`, LLR-076, AGENTS.md kit history (Q1,
ruled); **the LLR-049 Verify exemption (§2.1) and TC-229's no-hash arm**; TC-231's
Part-A end-to-end arm (a `.z7` source is stored raw and 7-Zip is not invoked). Gate:
`pwsh scripts/check.ps1 -Gate G2 -Tier Smoke` plus the generated-map freshness step.
This is the commit the hub can ship alone.

### Part B1 — Engine: probe + pure decision (LLR-086)

The two functions, the directional ruled list, the constants, comment-based help +
`Implements:` lines, **the codec calibration** (§2.2 — scratch script, results into
LLR-086), and unit tests against **synthetic corpora built in the test**: random bytes
(incompressible everywhere), repeated text, a random file with a 64 KiB text head
(aggregate ≈0.93 → **raw**), a file one-third text (aggregate ≈0.7 → compress), a
500 KiB file (read whole, once), a 4 KiB file, an empty file, a vanished path, a path
held open with `FileShare.None` (→ `$null`). `Resolve-CompressionDecision` is tested
over the full `CompressEnabled × mode × ruled × list × floor × ratio` grid, rule 0
first. Gate: `-Gate G2 -Tier Smoke`; map regenerated if any symbol is exported.

### Part B2 — Engine: wiring, config key, telemetry (SR-081, SR-042/063)

Memoized lazy call site with the candidate walk; `-CompressProbe` parameter and
step-10 plumbing; `CompressProbe` across all nine surfaces of §2.5; DEBUG line and
counters; TC-224…TC-228, TC-231's remaining arms. Gate: `-Gate G2 -Tier Full`.

### Part C — Docs

README §2.6 rewrite (sub-heading preserved for TC-096); AGENTS.md §3 clause and kit
history; status.md; WP16 §7 cross-note. Gate: `-Gate G2 -Tier Smoke` + freshness.
**Any code change after row 6 reopens the dual review** (§8).

---

## 5. Test cases (TC-222 onward, provisional)

Permutations cell for `python scripts/gen_cases.py`:

```
compress=set{on,off}; mode=set{off,excluded-extensions,always}; content=set{random,text,mixed-head,mixed-third,small,empty}; ext=set{listed,ruled-compress,ruled-raw,unlisted,none}; size=set{below-floor,above-floor}; dedup=set{fresh,existing-hit,in-run-twin,failed-then-twin}; format=set{json,clixml}
```

**How the integration cases reach the engine.** The suites drive backups through
`FileBackup.ps1`, which re-imports both modules with `-Force` (`FileBackup.ps1:236`)
and thereby discards any `Mock -ModuleName` injected earlier. Cases that need a seam
therefore call `Invoke-BackupFileGroup` **directly** in-process, where
`Mock -ModuleName FileBackup.Engine` has precedent (`Coverage.Tests.ps1:1862`); cases
that need the whole run assert on the **`compress-decision:` line count** and the
counters instead of a mock.

| id | Case | Why it is not optional |
|---|---|---|
| **TC-222** | Part A: every added extension returns `$false` from `Test-ShouldCompress`, case-insensitively; `.iso` still returns `$true`. | Pins the list *and* the deliberate non-addition. |
| **TC-223** | `Measure-SampleCompressibility` on the synthetic corpora: aggregate ≈1.0 random, ≪1 text, ≈0.93 mixed-head, ≈0.7 mixed-third; a 500 KiB file is read exactly once as one sample; `$null` for vanished/locked; the compressed count is taken after dispose (random bytes must not read < 0.98). | The I/O shell's contract, the geometry, and its refusal to throw. |
| **TC-224** | **SN-003 pin, both directions (I-2):** a `.docx` over random bytes is stored `.7z`; a `.jpg` over text bytes is stored raw. **Negative control:** with the ruled list emptied, both flip — the test must go red. | The one place WP17 could reverse a stakeholder ruling. |
| **TC-225** | Mode `always`: an unlisted extension and a no-extension file above the floor — random → raw, text → `.7z`, mixed-head → raw, mixed-third → `.7z`; a listed `.zip` over text → `.7z`, over random → raw. Filename and `Compressed` agree in every arm (I-1). **Negative control:** probe bypassed → the random arms compress. | The finding itself, the aggregate rule, SR-004's agreement sentence, the default mode's defining property. |
| **TC-226** | **Laziness and memo (I-3), via direct `Invoke-BackupFileGroup` with a mocked probe and call counter:** a prior-backup dedup hit → 0 calls; an in-run twin → 0 extra calls; a group whose first member's copy fails and whose second succeeds → **exactly 1** call and 1 WARN at most; a locked owner with a readable twin → the twin is sampled, decision not `ProbeUnavailable`. **Negative control:** memo removed → the failed-then-twin arm counts 2. | The probe must add a read per *written group*, never per file or per failed attempt. |
| **TC-227** | Config: `off` reproduces the pre-WP17 decision for TC-225's inputs; `excluded-extensions` stores `.zip`-over-text raw but probes the unlisted arms; absent key ⇒ `always`; the resolved set object carries the value (`Resolve-BackupSetDefaults`); `"Always"`, `"maybe"`, `null`, a number → exit 2, nothing created, in **JSON and CLIXML**; the shared fixture corpus keeps TC-074/075/077 green; an unchanged v2 config loads. | The three modes, the default, both validators, the schema parity. |
| **TC-228** | A probe that cannot open any member (real `FileShare.None` holds on every member, direct call) yields the **list's answer** + one WARN, and the run exits 0 (I-6). | Fail-toward-today, never fail-the-run. |
| **TC-229** | `-Action Verify` (SR-049, TC-093's harness) over a probe-mixed store reports **clean**; a raw-stored `.z7` is exempted **without a hash** (mocked `Get-FileXxHash` counter = 0 non-`Deep`, > 0 under `-Deep`); `Reconstruct.ps1` and `reconstruct.sh` restore the store byte-exact. | Both forms are still just forms, and Verify does not re-hash the library. |
| **TC-230** | Container arm (Release tier): TC-225 inside the image; the summary reports `Probe reads` bytes and wall time — the measured first-run cost figure. | Linux is where the defect was measured; the cost claim is measured, not asserted. |
| **TC-231** | **Compression disabled dominates (rule 0):** with `CompressEnabled=false`, every mode × every extension class (ruled-compress, ruled-raw, listed, unlisted) stores raw with `Compressed=No`, and the probe is never called; and a Part-A end-to-end arm: a `.z7` source under `CompressEnabled=true`, mode `off`, is stored raw and `7z` is not invoked (mocked `Compress-FileWithSevenZip` counter = 0). | The reviewers' P0, and the hub's actual fix path. |

Negative controls that must be shown to fail fix-removed: **TC-224** (ruled list
emptied), **TC-225** (probe bypassed), **TC-226** (memo removed), **TC-231** (rule 0
removed).

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
| **Q7** *(open, from the cross-review)* | Does `always` withhold **`.jpg` and `.mp4`** from the probe so SN-003's second clause (*"a `.jpg`/`.mp4` is stored as-is"*) stays literally true? Both reviewers found the drafted claim that it "holds because those bytes probe incompressible" to be empirical, not an invariant (a BMP under a `.jpg` name compresses). | **Recommended: yes** — the directional ruled list (§2.3) with exactly those two `Raw` entries. Costs two extensions out of "probe everything"; keeps SN-003 unedited (Q5). The alternative is to treat the clause as an Owner-ruled departure and edit SN-003 after all. |
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
| **A probe-read performance budget (PB row)** | Codex #8 asked for a first-run benchmark with a pass budget. TC-230 *measures* (probe count, bytes, wall time); a budget is set from production counters, not invented. |
| **`ConfigVersion` 3** | Codex #10. Rejected in favour of ratifying the additive-optional policy in SR-063 (I-8): a version bump would force every deployment, HomeHub included, to edit a config for a key it does not need to set. |
| **Measure-then-override for telemetry honesty** | Codex #3: under `always`, probe ruled files anyway and log the ratio. Rejected — a read spent on a decision already made; the `Reason=Ruled` line is the honest telemetry. |

---

## 8. Sequencing

Each row is one small green commit (CLAUDE.md commit cadence). Rows 2–8 gate at
**`-Gate G2`**, as WP16's plan does for the same reason: G3's `--require-verified` is
phase-filtered (`check.ps1:122`) and the new `probe-v1` rows are Draft until row 9. Every
commit that changes the PowerShell AST regenerates the maps (`check.ps1:132` runs
freshness on every check, not only at the end).

| # | Commit | Gate on |
|---|---|---|
| 1 | Defect review + this plan + its §10 cross-review round | *(this file)* |
| 2 | Registry deltas (§3), phase `probe-v1` | `python scripts/trace.py --strict` green, orphans 0 |
| 3 | **Part A** — list, README table, TC-096/TC-222, LLR-004/049/076, KitRevision `current+1`, TC-173 pin, Verify exemption + TC-229's no-hash arm, TC-231's Part-A arm | `check.ps1 -Gate G2 -Tier Smoke` — **the hub can ship from here** |
| 4 | Part B1 — probe + decision core + calibration table + TC-223 | `-Gate G2 -Tier Smoke` |
| 5 | Part B2 — wiring, `CompressProbe`, telemetry, TC-224…TC-228, TC-231 incl. negative controls | `-Gate G2 -Tier Full` |
| 6 | **Independent review round** (dual: Codex CLI + fresh-context Opus; coordinator consolidates, §11) → fold | re-run row 5's gate |
| 7 | Part C — docs, status.md, WP16 cross-note; TC-229's full arm | `-Gate G2 -Tier Smoke` + freshness |
| 8 | TC-230 container evidence | `-Tier Release`, real output pasted |
| 9 | Flip `probe-v1` rows to Verified; add the phase to `check.ps1:122`; status.md | `check.ps1 -Gate G3` clean apart from WP14's pending commit-7 rows |

**Review sizing.** Plan-stage: the dual round in §10 (done). Implementation: **dual**
after row 5 — not because WP17 can corrupt data (it cannot re-form, and both outcomes
restore) but because it edits the SR-060 owner-election write branch, the config
validator, and now the SR-049 Verify exemption, and the last four independent rounds on
this repo each found P0s in-house testing missed. **Any code change after row 6 —
including one prompted by TC-229 or TC-230 — reopens the dual review** (Codex #20).
Part A alone would merit a single reviewer.

---

## 9. The hub run — separate from all of the above

**The Owner stopped the production first pass on 2026-08-31 (Q6).** It was ~5 h into
step 10 with ~859 GB of `.z7` ahead of it (review §1c). The rerun waits on Part A in a
rebuilt image (§8 row 3). **What the code does on that rerun — verified read-only,
2026-09-01, by the coordinator and independently by Codex #19:**

1. **The hub's image does not carry WP14.** The external stop left the stale-`Temp`
   wedge the first review documented; the README stale-lock procedure (WP14 §9's
   `mv Temp Temp.stale-<date>`) must be run by hand before the rerun, after confirming
   what `Temp` holds. This time it holds the **step-7 pre-run snapshot of the prior
   manifest** (`Engine.psm1:5913`, written before step 10 began) — inspect, then move.
2. **The hash cache survives.** `Update-SourceManifest` writes the source manifest at
   its end (`Engine.psm1:576`) into `SourceStatePath`, so step 5's ~8-hour hash is not
   repeated on the rerun (subject to `HashRecalcFreq`).
3. **Every object step 10 wrote is an orphan, and nothing adopts or removes it.**
   Step 12's manifest was never written, so the backup root's `MANIFEST.csv` still
   describes the pre-run state (empty — this was the first pass). Step 6's sanitizer
   (`Test-BackupManifest`, `Engine.psm1:916`) **only warns** — one
   `File exists in backup folder but not in DB` line per object, several thousand of
   them. Step 10's dedup lookup consults **manifest rows only** (`:4931`), so the
   orphans are not adopted. The rerun re-writes every object: raw copies land on the
   same content-addressed name via `Copy-Item -Force`; compressed ones via
   `Compress-FileWithSevenZip`, which removes the destination first (TC-139).
4. **The 16+ completed `.z7` objects are the one permanent residue.** They were
   stored **compressed**, named `<hash>_<len>.7z`. After Part A the rerun stores the
   same content **raw**, named `<hash>_<len>.z7` — a *different* name — so the old
   `.7z` objects (~21.7 GB) are never overwritten, stay `Unreferenced` forever, and
   **repair explicitly does not remove unreferenced objects** (`Engine.psm1:1700`).
   They cost space and one Verify warning each, permanently, unless removed by hand.

**Recommended procedure, for the Owner to approve (it deletes data, so it is not the
coordinator's call):** since no run has ever completed against this store, the backup
root holds nothing a manifest claims. Empty the backup root entirely (every data
object; the empty `MANIFEST.csv` and its witness may stay or go), move `Temp` aside as
in item 1, keep `SourceStatePath` untouched (item 2), then rerun on the Part A image.
That yields a clean first pass with no orphans, no warning storm, and no 21.7 GB
residue, at the cost of re-copying ~57 GB the stopped run had already stored. The
alternative — leave the objects and accept the residue — is safe but permanently
untidy, and the first `-Action Verify` will report every one of them.

Nothing in WP17's code depends on either answer.

---

## 10. Plan-stage review round, 2026-09-01 — composite disposition

Two independent reviewers of revision 2, same brief, run in parallel: **OpenAI Codex
CLI** (`codex exec --sandbox read-only`; 2 P0, 15 P1, 3 P2) and a **fresh-context Opus
subagent** with no drafting context (1 P0, 13 P1, 7 P2). The coordinator verified every
finding against the tree before disposing of it. Findings raised **independently by
both** are marked ★ and were folded first. `A` = accepted and folded (section named);
`A′` = accepted in modified form; `R` = rejected, reason given.

| # | Raised by | Sev | Finding | Disposition |
|---|---|---|---|---|
| R-1 | ★ Opus 1, Codex 1 | **P0** | `Resolve-CompressionDecision` never consults `CompressEnabled`; the ruled short-circuit and `always` would compress on a Plain set, naming `.7z` / `Compressed=Yes` with 7-Zip unresolved. | **A** — rule 0 (§2.2), TC-231, `CompressEnabled` in SR-081 and the permutations. Verified: the guard lives only in `Test-ShouldCompress` (`Common.psm1:691`); `FileBackup.ps1:325` resolves 7-Zip from `CompressEnabled` alone. |
| R-2 | ★ Codex 2 (P0), Opus 11 (P1) | **P0** | The ruled model protects only SN-003's `.docx` half; a boolean override cannot force `.jpg`/`.mp4` raw, and the plan's claim that the clause "holds because those bytes probe incompressible" is empirical, not invariant. | **A** — directional ruled list (§2.3), I-2 rewritten, TC-224 pins both directions. The two `Raw` entries are the cross-review's one open item, **Q7**, because they withhold two extensions from the Owner's "probe everything". |
| R-3 | Codex 3 | P1 | Under `always`, measure ruled files anyway and apply the ruled outcome afterwards, so "probes all files" and the telemetry stay literally true. | **R** — a read spent on a decision already taken; the `Reason=Ruled` line is the honest telemetry, and §2.5 now defines `always` as "the list is not consulted", not "everything is measured". Recorded in §7. |
| R-4 | ★ Opus 16, Codex 4 | P1/P2 | The write branch is inside the member loop and a failed write `continue`s with `$writtenThisRun` null; a naive lazy expression re-probes and re-WARNs per failing member. | **A** — group-scope memo (§2.4), TC-226's failed-then-twin arm, memo-removed negative control. Verified at `Engine.psm1:4950`, `:5060`. |
| R-5 | ★ Opus 2, Codex 5 | P1 | Probing only the owner defeats the readable-twin fallback the copy path has (`:5017-5022`); a locked owner would be classified unavailable and compressed. | **A** — the probe walks the same candidate list (§2.4); TC-226's locked-owner arm. |
| R-6 | Opus 2 | P1 | `ProbeUnavailable → compress` contradicts §0/I-6 ("the list's answer") and, under `always`, re-creates the 9-day defect for any transiently locked `.z7`. | **A** — rule 5 is the list's answer; I-6 and §0 reconciled; TC-228 asserts it. |
| R-7 | Codex 6 | P1 | The any-sample rule sends a multi-GB random file with a 64 KiB text head to `-mx=9` whole — the review's own failure mode re-created. | **A** — aggregate rule (§2.2 rule 6); TC-223/TC-225 mixed-head expectation flipped to raw; mixed-third fixture added for the other direction. |
| R-8 | Codex 7 | P1 | Deflate-fastest's 32 KiB history is uncalibrated against LZMA2's 64 MB dictionary; long-range repetition compresses under 7-Zip and not under the probe; synthetic fixtures cannot see it. | **A′** — Part B1 carries a calibration item over the real corpus classes, with `BrotliStream` as the candidate whose window covers a whole sample; codec chosen from the table and recorded in LLR-086 (§2.2). The request to "define acceptable false-raw/false-compress rates before implementation" is **R** — rates come from the table, not before it. |
| R-9 | ★ Opus 14, Codex 8 | P1 | The "most below or near the floor" cost claim contradicts the census (means ≈105 MB `.mp4`, ≈1.7 MB `.jpg`); real first-run cost ≈55 GiB of reads and ≈75k probes. | **A** — §2.5 restated with the numbers; TC-230 measures `Probe reads` and wall time. Codex's pass-budget/HDD-seek benchmark is **A′** — measured now, budgeted later from production counters (§7). |
| R-10 | ★ Opus 13/15/21, Codex 9 | P1/P2 | The I/O contract: `FileShare.ReadWrite\|Delete` misattributed to the hasher (it uses `FileShare.Read`, `Common.psm1:352`); overlapping triple reads for 256–768 KiB files; short reads, `Int64` offsets, empty files unspecified; compressed count must be read after `Dispose()`. | **A** — §2.2 specifies `FileShare.Read`, whole-file single read below `3 × SampleBytes`, exact-read loop, `Int64` floor offsets, empty-file behaviour, dispose-before-count; TC-223 pins the geometry and the dispose hazard. |
| R-11 | ★ Opus 3, Codex 11 | P1 | `Resolve-BackupSetDefaults` builds a fixed-field object (`:6468`); a validated key not added there is silently dropped. | **A** — §2.5 surface list; TC-227 asserts the resolved object carries the value. |
| R-12 | ★ Opus 5, Codex 11 | P1 | Value validation belongs in `Test-BackupConfigurationShape` (both formats), not only in the JSON-only `Assert-NoUnknownConfigKey`; a CLIXML `"maybe"` would pass. | **A** — §2.5; TC-227 has a CLIXML arm. |
| R-13 | ★ Opus 4, Codex 11 | P1 | "Case-insensitive" breaks the `BrowseView` precedent (`-cnotin`, exact lowercase) and TC-077's schema `enum` parity; `ExcludedExtensions` cannot be enumerated in all casings. | **A** — exact-lowercase vocabulary `off \| excluded-extensions \| always` (§2.5); the Owner's `Off \| ExcludedExtensions \| Always` names are preserved in meaning, not casing. Codex's `(?i)` pattern alternative **R** — parity by `enum` is the precedent. |
| R-14 | ★ Opus 6, Codex 11 | P1 | The `-CompressProbe` parameter and the step-10 call site (`:5979`) are unnamed. | **A** — §2.4, LLR-086. |
| R-15 | Codex 11 | P1 | The full config change surface: schema, example JSON, fixture corpus, smoke config, `FileBackup.ps1` help, README table, IF-001. | **A** — nine surfaces enumerated in §2.5; IF-001 row in §3. |
| R-16 | ★ Opus 18 (stays 2), Codex 10 (bump to 3) | P1/P2 | `ConfigVersion`: an unchanged v2 document changes meaning (defaults to `always`); an older v2 build rejects the key. | **A′** — stays 2; SR-063 ratifies the additive-optional policy; I-8 rewritten; TC-227's unchanged-v2 arm. Bumping to 3 **R** — forces every deployment (HomeHub) to edit config for a key it need not set; the by-name rejection on an older build is the closed schema working (§7). |
| R-17 | ★ Opus 10, Codex 12 | P1 | SR-004's acceptance clause "an already-compressed extension is stored verbatim" becomes false under `always`. | **A** — re-scoped in §3. |
| R-18 | Codex 12 | P1 | LLR-058 says the owner's `Test-ShouldCompress` answer defines the form; LLR-042/063 describe the validator; IF-001 states the closed schema — all must be amended. | **A** — §3 rows for LLR-058, LLR-042/063, IF-001. Verified at `low-level-requirements.csv:56` and `interfaces.csv`. |
| R-19 | ★ Opus 9, Codex 13 | P1 | KitRevision 11 collides with WP16 Q6(a); LLR-076 hard-codes 10; the pin lives in `RestoreLaunchers.Tests.ps1:84`; WP16's TC-216 pins the same fact. | **A** — "current + 1 after rebase" rule, LLR-076 and TC-173 rows, TC-216 merge note (§3). |
| R-20 | Opus 8 | P1 | Part A alone makes `-Action Verify` re-hash every raw-stored archive-magic object (`Engine.psm1:1633` exempts only a `.7z`-named RelativePath) — 880 GB per Verify. | **A** — LLR-049 amendment in Part A (§2.1, §3): own-extension + row-length exemption for the non-`Deep` scan, hash reserved for `-Deep`; TC-229's no-hash arm; flagged for the dual review as the one edit inside a data-integrity audit. |
| R-21 | Opus 7 | P1 | README heading rename breaks TC-096's parity regex (`StorageForm.Tests.ps1:876`), and the break lands in a different commit from the fix. | **A** — sub-heading preserved (§2.6, Part C). |
| R-22 | ★ Opus 12, Codex 14 | P1 | TC-226/TC-228 as drafted cannot be built through the entry point: `FileBackup.ps1:236` re-imports with `-Force` and discards module mocks. | **A′** — §5 preamble: seam-needing cases call `Invoke-BackupFileGroup` directly, where `Mock -ModuleName FileBackup.Engine` **does** have precedent (`Coverage.Tests.ps1:1862`; Opus's "no precedent anywhere" claim is wrong); whole-run cases assert on the `compress-decision:` line count. TC-228 uses a real `FileShare.None` hold. |
| R-23 | Codex 14 | P1 | Missing arms: `CompressEnabled=false` × modes; ruled-raw; failed-first-member re-entry; locked owner with twin; JSON/CLIXML parity; a Part-A end-to-end `.z7` case proving 7-Zip is not invoked; TC-225's promised JPEG corpus absent. | **A** — TC-231 (new), TC-226/227 arms; the "JPEG corpus" claim is withdrawn with R-2 (the `Raw` ruling replaces it). |
| R-24 | Codex 15 | P1 | WP16's SR-079/LLR-082/TC-212 enumerate `DEBUG` sites; WP17 adds one; counters must be per-set physical-object counters after successful writes. | **A** — §2.4 ordering clause and counter semantics; cross-note in both plans' §7 (Part C). |
| R-25 | Codex 16 | P1 | The helper API is not executable as drafted (`ProbeEnabled` vs three modes; `Disabled` ambiguous; `ListExempt` mis-assigned; the promised Engine accessor absent, and `Get-FileBackupDefaults` would edit Common). | **A** — one signature, unambiguous reasons, `InModuleScope` for constants, no Common accessor (§2.2). |
| R-26 | Codex 17 | P1 | Rows 2–8 cannot pass a G3 gate with Draft SR-081; maps must regenerate per AST-changing commit. | **A′** — `-Gate G2` for rows 2–8, `probe-v1` phase tag, row 9 flips and adds the phase (§3, §8); maps per commit. Codex's premise that Part A cannot be G3-green is **R** as stated — the phase filter (`check.ps1:122`) is the mechanism, and SR-004 stays Verified through Part A because TC-096/TC-222 pass in the same commit. |
| R-27 | Codex 18 | P2 | TC-096's over-claim also includes `.xlsx`; the heading regex. | **A** — §2.3, Part A; heading per R-21. |
| R-28 | Codex 19 | P2 | §9's stopped-run behaviour is answerable now: sanitizer warns only (`:916`), dedup adopts rows only (`:4931`), Part A renames the `.z7` objects so the interrupted-run `.7z` objects stay `Unreferenced` and repair never removes them (`:1700`). | **A** — §9 rewritten with the coordinator's independent verification (which reached the same four facts) and a recommended cleanup procedure for the Owner. |
| R-29 | Codex 20 | P2 | TC-229/TC-230 land after the dual review; fixes they prompt would be unreviewed. | **A** — §8: any post-row-6 code change reopens the review. |
| R-30 | Opus 17 | P2 | Exports: Engine has an explicit `Export-ModuleMember` list (`:6590`); tests cannot reach unexported helpers. | **A′** — helpers stay internal and are tested via `InModuleScope` (LLR-086); if exported, list + map move together. |
| R-31 | Opus 19 | P2 | Part A is largely inert under `always` for the census's `.z7` files (all far above the floor). | **A** — §2.1 sentence. |
| R-32 | Opus 20 | P2 | "The tests that pin owner election read `$ownerCompress`" — nothing does. | **A** — sentence removed (§2.4). |
| R-33 | Opus, Codex (verified-correct blocks) | — | Laziness structurally safe (`:4990/5025/5071/5079` all inside the write branch); dedup/twin branches return first; `Test-StorageFormAgreement` independent of the list; SR-052 sizes by uncompressed length; restorers untouched; ids after WP16's blocks; Part A's twelve additions defensible, `.iso` correctly excluded; `.mp4` at `Common.psm1:118` (plan said `:117` — cosmetic, fixed). | Recorded as the checked surface. |

**Net effect on the plan:** two P0s closed by rule 0 and the directional ruled list;
the decision rule, I/O contract, config surface, registry deltas, test set and
sequencing all rewritten; one question (Q7) returned to the Owner. The plan remains
**PROPOSED**.

## 11. Implementation review round — composite disposition (after commit 5)

*(Same format; filled after row 6 of §8.)*
