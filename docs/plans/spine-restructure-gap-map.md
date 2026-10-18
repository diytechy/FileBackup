# Spine restructure — gap map

*Branch `SpineRestructure` (cut from `New_Fix_Batch` at `d61e57a`) · 2026-10-17 ·
for the owner to align on before any spine row is rewritten.*

This compares FileBackup's current spine (back-filled from code in 2026-07 under
kit `9b697cc`) with the spine model ai-template has since ruled. It is a map of
what has to change, not a rewrite. The per-row verdicts in the appendices are a
first pass by independent read-only analyses, one per tier; treat each as a
claim to confirm or overrule, not a decision.

## 1. The target, in one screen

The ruled model (ai-template's `spine-questions.md` and the review-churn plan's
`pointer-rules.md`):

- **Everything points up.** SR → SN, top-level LLR → SR, child LLR → one parent
  LLR, TC → LLR (an SR directly only where justified). Code points up to the
  spine (`Implements: LLR-NNN`, `Contract IF-NNN:`, `Component: CMP-NNN`); the
  spine never points down at code.
- **What a row may name.** SN and SR name no file and no code in any cell,
  acceptance and rationale included. LLR and TC may name shipped boundary
  artifacts (the config document, the launchers) but never code files,
  functions, cmdlets or test files. A declared vocabulary token (a status word,
  a config key value set) is not a file name, but still has to belong at that tier.
- **Contract voice.** An LLR states inputs, outcome and refusals in words that
  survive a behaviour-preserving refactor. No `shall` in an LLR.
- **One `shall`, one decision, EARS with the condition in front** (The / When /
  While / If / Where) at SR.
- **No provenance in any cell.** No dates, WP/D-/M-/OI ids, "AMENDED",
  "ruled", "finding". Keep the durable reason; send the history to the log.
- **The design layer is its own registries.** Components (CMP, nested by
  `part_of`) and interfaces (IF). An IF states its *form* only and names an owner
  (a CMP or an `external:` party); the *behaviour* across it lives in the LLR (or
  the SR, at the system boundary) that `constrains` it. An LLR's placement on a
  component is derived through that interface, not authored.
- **The frame.** Stakeholders (STK), external parties and boundary crossings
  (`external.toml`, B-###) that SRs are stated at, domain assumptions (DA) that
  bridge system output to stakeholder outcome, and a hats roster whose
  `applies_when` reads tags the needs carry.
- **Carrier and vocabulary.** TOML, one table per row; `status` is
  `Drafted`/`Approved` at every tier; authoring never approves.

**Kit caveat.** Several of these are ruled but **not built** in the kit yet:
no `module`/`code_symbol` removal, no parent-LLR link, no `constrains` cell, no
generated evidence column. Those land last in ai-template's queue (review-churn
item 5). FileBackup can author to the ruled shape now, but no checker will
enforce the new cells until that lands. That fits "spine first, tooling later",
but it means the first pass is judged by review alone.

## 2. Where FileBackup stands

| Tier | Rows | Headline gaps |
|---|---|---|
| SN | 36 (markdown table) | 23 name a file, flag, key or tool. ~15 put a mechanism in the need or acceptance. 13 carry provenance. 9 are written as reactions to a defect rather than an outcome. 11 have no why, priority or acceptance. No stakeholders, tags, lifecycle or vision anchor. |
| SR | 81 | 57 make more than one decision (59 have more than one `shall`). ~59 name code, ~49 name a file, ~55 carry provenance, 47 mirror the implementation. Mean requirement cell is 933 characters. 42 open on something other than an EARS keyword. 7 internal contradictions. |
| LLR | 86 | All 86 use an off-spine status word. All carry Module/CodeSymbol; Detail names a cmdlet in 68 and a code file in 45. ~40 carry provenance. 37 run past 1,000 characters (LLR-086 is 8,085). ~25 paraphrase their SR. |
| TC | 234 | No row can stay as written. Expected names a test or suite in 149, a symbol in 114, provenance in 75. Tests name TCs only in prose titles and comments; 75 TCs appear nowhere in `tests/`. |
| CMP | 0 | — |
| IF | 1 | IF-001 (the HomeHub contract) bundles about eight interfaces and carries HomeHub policy. |
| STK / external / DA / hats | none | — |

**Format defects that mislead today's tooling** (worth knowing before trusting
any `trace.py` output on this branch):
- SR-071..074 (SN-Refs), LLR-072/073/075/076/078 (SR-Refs) and TC-155..204
  (Verifies) separate ids with `, ` where every other row uses `;`. That is why
  `trace.py` reports SR-073 and SR-074 as LLR-less (they are not; only **SR-019**
  truly is), and why TCs that also verify an LLR read as "SR-only".
- SR-015/019/027/037 hold their verification method in `Status`. That is an
  old-kit convention, not a column shift; map them to `Drafted`.
- 27 SR rows have non-integer Phase labels (`bash-v1`, `ca-v1`).
- TC-173 names TC-216, which does not exist.

**Contradictions inside the spine** (these are behaviour calls, not wording):
1. SR-050 resolves a non-blank row by its own `Compressed` column, but SR-068
   says that column is never consulted for correctness.
2. SR-075's rationale describes a temp-write plus rename; its requirement says
   no temp file and no rename.
3. SR-058 uses the object-name grammar SR-069 replaced.
4. The kit artifact count: SR-007 says seven, SR-044 says eight, and the TCs
   say four, seven and eight.
5. SR-033 still describes `HashAddressed` and the extension-gated `.7z`.
6. SR-042 warns on a multi-set JSON config, while SN-009 asks for several sets
   in one config.
7. SN-003's acceptance (compress by extension) contradicts SR-081 (compress by
   measured gain). SN-013 contradicts SR-075 (stale-lock reclaim). SN-029 and
   SN-036 assume the four storage modes that SR-058 retired.

## 3. Decisions to make before rewriting

In the order they block work. Each one has a recommendation.

| # | Decision | Recommendation |
|---|---|---|
| D1 | **Vision anchor.** The needs need a `PROJECT-VISION` to serve, and the README has none. | Write a short vision clause first. It is the reference every need is checked against. |
| D2 | **Stakeholders.** | Three: **STK-01 owner/operator**; **STK-02 restorer on a clean or foreign machine** (possibly not the person who configured it); **STK-03 HomeHub integrator** (another system that consumes exit codes and contracts). Fold Linux-host operators and household data owners into STK-01. |
| D3 | **Scope of the spine.** CI proof (SN-028, SR-044), container *build* tooling and the media-metrics (ffprobe) column. | Move CI proof to the TC tier. Treat container build and export as delivery, outside the product spine. Media metrics: decide whether it is a need or retire the feature. |
| D4 | **Hats roster.** The kit's `applies_when` clauses read kit tags and reach none of FileBackup's needs. | Rewrite the roster for FileBackup. Add three: **SHARED-CONTENT** (an operation on one path or snapshot destroys bytes another depends on), **STORE-FORMAT-COMPATIBILITY** (a change strands an existing store or an older restorer), **FILESYSTEM-SEMANTICS**. Drop SAFETY. Tag the needs so the hats reach them (Appendix A). |
| D5 | **How to derive the SRs.** | Do a **blind re-derivation** from the new needs, frame and hats, without reading the old SRs. Then run an alignment pass against the 81 old rows; the SR clusters in Appendix B are that check. Read each old row's rationale before declaring it unsupported. The kit calls this its strongest instrument, and it is the main protection against rewriting the code back into the requirements. |
| D6 | **Interface granularity.** One analysis produced ~5 system-boundary IFs; the design analysis produced 26 boundary IFs plus 9 internal ones. | Start with the boundary set: the store layout, index, witness, object naming, restore kit, both CLIs and exit alphabets, the config document, the container contract and mail. Add internal IFs only where two components or two processes must agree on a form: the lock and owner record, run state, the pool index. Internal calls within a component are not IFs. |
| D7 | **Components versus today's files.** Engine.psm1 holds nine of the twenty proposed components, and Common.psm1 holds engine policy (the compressible-extension list, defaults), which is why every list edit bumps KitRevision. | Author the component tree from responsibilities now (Appendix C). Map code to it later, under the code-header pass. Moving the policy out of Common changes a kit-bundled file, which is a downstream migration, so flag it rather than doing it inside the spine work. |
| D8 | **Twin restorers.** About 20 rows say "both restorers" or "mirrors". | One set of restore LLRs on the restore-kit component. Parity between the PowerShell and bash restorers becomes a TC question, with one TC per implementation. |
| D9 | **Ids.** | Keep an id where its meaning survives, mint new ids for splits, retire merged ids explicitly, and never reuse a retired id. |
| D10 | **Test tagging form.** Under the kit rule, a test file carries a tag naming its TC (singular). FileBackup's test files verify up to 32 TCs each. | This needs an ai-template ruling (a tag per test block) before the tagging pass. It does not block the spine rewrite. |
| D11 | **The 7 contradictions in §2.** | Each needs an owner call on actual behaviour. Settle them while rewriting the affected cluster, not up front. |

### Owner rulings on D1–D4 (2026-10-17)

**D1 — vision: ruled.** This goes at the top of README.md as the
`PROJECT-VISION` anchor:

> FileBackup keeps a trustworthy, space-efficient history of one owner's
> files. It runs unattended, and any saved point in time can be restored
> bit-for-bit on a clean machine from the backup folder alone.
>
> What sets it apart:
> - FileBackup is needed only to *make* backups, never to recover them. Every
>   backup carries its own restore kit, which runs with commonly available
>   tools.
> - It spends storage only where it pays: identical content is stored once,
>   and a file is compressed only when measuring it shows compression actually
>   saves space.
>
> It never loses content a saved state still depends on, never alters the
> files it backs up, and says plainly when it could not do its job.

**D2 — stakeholders: ruled.**
- **STK-01 Owner.** Configures, schedules, sets retention, checks store health.
- **STK-02 Restorer.** The owner, or whoever holds the backup folder, on a
  clean or foreign machine with no FileBackup installed, possibly on another
  OS.
- **STK-03 Backup host.** Any system that runs FileBackup unattended on the
  owner's behalf and acts on its results: a home server, a NAS, a container
  platform, a scheduled task. Deliberately generic. HomeHub is one instance,
  kept only as an example external party, and named in no need.

**D3 — scope: ruled.**
- The media metric stays, as an optional, configurable feature. Its new need
  is roughly "show me where backup space goes, such as large files or media
  that could be re-encoded at a lower bitrate". It serves the space-efficiency
  outcome: as little space as feasible, bit-for-bit identical, and not
  egregiously slow.
- CI proof of the container moves to the TC tier.
- Container build and export tooling is delivery, outside the product spine.
- Other retirements come out of the SR re-derivation's "true accretion"
  bucket, as proposals for the owner.

**D4 — hats: ruled; the domain-focused roster.**
- **Always:** INTEGRITY-RECOVERABILITY, SECURITY.
- **Tagged:**
  - SHARED-CONTENT (`store-mutation`)
  - STORE-FORMAT-COMPATIBILITY (`store-format`)
  - FILESYSTEM-SEMANTICS (`filesystem`)
  - UNATTENDED-OPS (`unattended`)
  - CROSS-PLATFORM (`restore-host`)
  - PERFORMANCE (`scale`)
- **Also kept:** LEGAL (`redistribution`). Every backup and the container image
  ship third-party code (the hashing library and 7-Zip), and the media metric
  depends on ffmpeg/ffprobe. The hat asks whether each redistribution or
  dependency is licensed for the way it ships.
- **Dropped:** the kit's process hats, the UX trio (they can return keyed on
  `ui`), FIRST-RUN-ADOPTER and SAFETY.

### How the work runs (Owner direction, 2026-10-17)

- **Strip first.** Strip the legacy spine of provenance, code and file names,
  instruments in acceptance, and stale or contradictory text. Every strip
  decision is cross-reviewed by GPT-6 Astra (medium) and an independent Claude
  Opus (medium). The coordinator makes the final call on what is removed and
  records where the reviewers disagreed.
- **Then reorganize.** Restructure into the new model and decompose where
  needed. A sparser spine is expected and acceptable.
- **Build back out with two independent derivations.** GPT-6 Astra and an
  independent Claude Opus (medium) each derive their own breakdown, which the
  coordinator cross-compares to find the differences. Alternatively, one
  builds and the other reviews.

## 4. Proposed order of work

Each phase ends with a tier you can approve before the next one starts. Under
the kit, a child is approved only after its parent.

**Phase 0 — frame and harvest** (no spine rows rewritten yet)
1. Put the hold banner on this branch's `status.md`.
2. Write the vision clause, then STK, `external.toml` (parties and crossings,
   Appendix A), the DA candidates and the FileBackup hats roster.
3. **Build a harvest sheet** from the old spine with a script, before anything
   is rewritten. The old TC `Expected` cells are the only acceptance text this
   spine has (the LLR CSV has no acceptance column). They hold about 40 rows'
   worth of input-space sets, thresholds, negative controls, mutation checks
   and the "this test could pass vacuously unless…" notes. Columns: old id,
   verifies, the test-title or Describe link, input sets, thresholds,
   negative-control and mutation notes, scope limits, provenance. This sheet is
   the one artifact that must not be skipped.

**Phase 1 — needs.** Rewrite the 36 SNs per Appendix A: merges, splits,
mechanisms moved down, the why-cell clauses lifted into the need. Add the
roughly 12 missing needs: concurrency, a vanished source, a source left
untouched, store upgrade and migration, restore never harming the store,
scale, observability, backup failure classes, on-demand store health, host
provisioning, container operation and credentials. Expect about 35–40 needs.
**Approve the tier.**

**Phase 2 — system requirements.** Blind-derive from Phase 1 and the frame
(D5), then align against the old 81 rows using the clusters in Appendix B.
Expect about 80–90 SRs, each 150–250 characters, filling `boundary_refs`,
`form`, `da_refs`/`coincident` and `hat_refs` for derived rows. **Approve the
tier.**

**Phase 3 — design, built around the requirements.** Author the component tree
and the interfaces (form only), then the LLRs in contract voice, as a tree,
each pointing at the IF it constrains, with a dimensions cell taking the input
spaces from the harvest sheet. Appendix C has the per-LLR first pass. Then
re-anchor the prose: `architecture.md` keeps the runtime flow and the reason
for the restore-safe split, and the rest is generated from CMP and IF.
`interfaces.md` becomes generated. About 90% of AGENTS.md §3 restates SRs and
goes; its genuine design invariants become LLRs on their interfaces. **Approve
the tier.**

**Phase 4 — test cases.** Regenerate from the new LLRs rather than editing in
place: every row's `verifies` and `expected` change and its status needs
re-judging, so nothing stable is left to edit around. Keep old TC ids where a
case maps one to one. Retire the 9 overlap clusters explicitly. Settle D10,
then run one mechanical tagging pass over `tests/` from an old-to-new map.

**Phase 5 — code and tooling.** Add the `Component:`, `Implements:` and
`Contract IF-NNN:` headers. Do the kit resync or adapt `trace.py`. The template
comparisons you planned branch from the approved spine (tag it) and start here.

## Appendix A — needs and frame

**Per-need verdicts**

| SN | Verdict | Defect |
|---|---|---|
| 001 | reword | acceptance names `MANIFEST.csv`; "never silently skipped" sits only in why |
| 002 | reword | acceptance is a mechanism (one physical data file), not the outcome |
| 003 | reword | names `.7z` and extensions; contradicts compression by measured gain; why-cell clause |
| 004 | reword, absorb 034 | bundles keeping and restoring; snapshot naming is design |
| 005 | reword | "no installs" contradicts the restore-tool floor (022/035); "this repo" is a carrier |
| 006 | keep, reword or merge with 004 | layout words |
| 007 | reword | names `HashRecalcFreq` and its D/W/N values; the need is the speed-versus-integrity trade-off |
| 008 | reword | provenance throughout; why is Mirror history; "generated index" is a mechanism |
| 009 | reword | names `BackupSets`; the need is "one job, several roots, each failing independently" |
| 010 | reword, absorb 020 | names `-NoMail` |
| 011 | reword | names `pwsh` |
| 012 | split (provision) | names README and `CredSetEx.ps1`; dependency install conflicts with the container |
| 013 | reword, move the mechanism down | names `Temp` and rename-after-manifest; contradicts SR-075 |
| 014 | merge with 027 | no why or acceptance |
| 015 | merge with 016 | names PS 5.1 and `System.IO.Hashing` |
| 016 | merge with 015 | names 7-Zip and ffprobe; media metrics has no need |
| 017 | merge with 032 | no why or acceptance |
| 018 | reword or fold into 001 | names `MANIFEST.csv`; provenance |
| 019 | merge with 030's capacity half | no why or acceptance |
| 020 | merge with 010 | no why or acceptance |
| 021 | reword | "identical manifest rows" is an instrument |
| 022 | reword, absorb 035's macOS half | provenance; names `reconstruct.sh` |
| 023 | keep as Drafted | provenance; "bash engine" is a mechanism |
| 024 | split | the constraints sit only in why; acceptance names an instrument |
| 025 | reword, move the mechanism down | the need text is the design; its compatibility clause is really a migration need |
| 026 | keep (light reword) | sound |
| 027 | split | JSON/CLIXML is design; validation is the need; absorbs 014 |
| 028 | retire to TC / delivery | a verification gap, not an outcome |
| 029 | split | stale "four storage modes"; authority clause only in why; provenance |
| 030 | split ×3 | provenance; bundles index-matches-store, policy safety and capacity |
| 031 | reword | why names `Test-PoolResolves`; provenance |
| 032 | reword, absorb 017 | names 7-Zip quoting; provenance; mechanism |
| 033 | reword | provenance; "surviving pool copy" is a mechanism |
| 034 | merge into 004 | provenance; names `-Deep` |
| 035 | split | names launchers and flags; bundles guided restore with macOS |
| 036 | reword | provenance; mechanism in why; stale "every storage mode" |

**Missing needs:** concurrency (SR-085/086/087), a vanished source never
discards the backup (SR-036), the source left untouched, store upgrade and
migration (SR-061/084, kit revisions), restore never harms the store (SR-009),
scale (SR-064), observability (the 2026-08-31 defect review), backup failure
classes (SR-041/043), on-demand store health (SR-049/054), host provisioning
(SR-019/027), container operation (from 024), credentials (`CredSetEx`).

**External parties (candidates):** operator · host scheduler · HomeHub ·
source filesystem · backup volume · out-of-band store actors (antivirus,
cloud sync, a person tidying folders) · restore host and its target
filesystem · runtime and tools (PS7, hashing library, 7-Zip, ffprobe;
bash/gawk/xxhsum) · SMTP relay · package feed · container runtime and registry
· the backup folder handed to a future restorer · CI (delivery).

**Boundary crossings (candidates)**

| B | Party | Direction | Carries |
|---|---|---|---|
| 01 | source filesystem | in | bytes, names, times, attributes, directory shape (read-only) |
| 02 | backup volume | in and out | stored objects, index and witness, snapshots |
| 03 | operator, scheduler, HomeHub | in | config document, action |
| 04 | operator, scheduler, HomeHub | out | exit status per outcome class, log, progress |
| 05 | SMTP | out | outcome notification |
| 06 | runtime and tools | in and out | availability; hashing and compression calls |
| 07 | future restorer | out | restore kit plus store |
| 08 | restore host | out | the restored tree |
| 09 | package feed | in | first-run dependency install |
| 10 | container runtime and registry | out | image (delivery) |
| 11 | CI | in and out | build and roundtrip proof (delivery) |

**Domain assumptions (candidates):**
- **DA-01** A same-volume rename is atomic (not on SMB, exFAT or cloud-sync drives).
- **DA-02** A dead process's file lock is released (network locks, NFS).
- **DA-03** A file's bytes are stable during its read, or change detectably (live databases, no VSS).
- **DA-04** A (xxHash128, size) collision is negligible.
- **DA-05** Reported free space is accurate.
- **DA-06** The target filesystem keeps mtimes and attributes (FAT's 2 s granularity, Linux).
- **DA-07** Names survive the restore filesystem (APFS normalisation, case folding).
- **DA-08** Someone reads the exit status or the mail.
- **DA-09** The documented restore-tool floor exists or can be installed.
- **DA-10** Out-of-band damage is deletion or quarantine, not forgery.
- **DA-11** Volume-root pseudo-folders are not user data.
- **DA-12** The container runtime honours read-only mounts and non-root.

**Hats and the tags that reach them**

| Hat | applies_when | Needs tagged |
|---|---|---|
| INTEGRITY-RECOVERABILITY, SECURITY, MAINTAINER, TEST-ENGINEER, CONSISTENCY, PRODUCT-FITNESS | always | — |
| SHARED-CONTENT (new) | `store-mutation` | 029, 031, 004, 030, retention |
| STORE-FORMAT-COMPATIBILITY (new) | `store-format` | 025, 027, 036, migration, 003 |
| FILESYSTEM-SEMANTICS (new) | `filesystem` | 013, 017/032, 036, capacity, concurrency |
| UNATTENDED-OPS | `unattended` | 009, 010, 011, 013, 024, 026, 029, observability |
| CROSS-PLATFORM | `restore-host` | 005, 006, 022, 023, 032, 035 |
| PERFORMANCE | `scale` | 007, scale, 001 |
| FIRST-RUN-ADOPTER | `provision` | 012, 015/016, provisioning |
| UX trio | `ui` | 035, 008, 012, observability |
| LEGAL | `redistribution` | 024, 005 (the hashing library and 7-Zip ship inside every backup and the image) |

## Appendix B — system-requirement clusters and per-row verdicts

**Clusters: the proposed new shape**

| Cluster | Old rows | New shape |
|---|---|---|
| A. Killed-run recovery and concurrency | 017, 075, 083, 085, 086, 087, plus the lock clauses of 046 and 035 | 3 SRs: (1) recover an interrupted run only when its owner is provably gone; otherwise refuse, name the owner and change nothing; (2) while one mutating operation holds the store, every other refuses; (3) cross-cutting: a kill at any point loses no stored content. About 20 LLRs; DA rows for lock semantics, SMB/NFS and clock skew. |
| B. Index integrity | 025, 038, 039, 082, 084, 013 | 4 SRs: a self-witness; refuse a damaged index before writing; a missing witness warns (refuses where strict); the index is crash-atomic. Plus one IF for the index schema. |
| C. Claimed content is never lost | 006, 051, 059, 058 | 1 cross-cutting SR (SN-034); content addressing goes to LLR. |
| D. Dedup and snapshot cost | 003, 060, 026, 028 | 2 SRs: one stored object per content; a snapshot holds only superseded content. |
| E. Stored form and compression | 004, 081, 068, 050, 061a, 020a, 037-level | 7 SRs: compress only on measured gain; the probe never fails a file; a policy change never re-forms stored content; restore reproduces the bytes whatever the index says about form; a missing compressor refuses before mutation; the level knob (derived). |
| F. One store format, two implementations | 002, 030, 032, 033, 069, 070, 025 | 1 store-format IF plus 2 SRs: either restorer restores any store; parity where the Linux engine ships. |
| G. Restore outcome | 029, 040, 056, 074-restore, 052-restore | 3 SRs: restore everything recoverable and name each failure; one shared outcome vocabulary; verify after write. Plus an exit-table IF and about 6 LLRs. |
| H. Configuration | 018, 042, 063, 037-path, 043-config | 5 SRs: refuse invalid config before mutation, naming the key; version policy; the legacy form; a refused run leaves nothing behind; the view path never overlaps a store or source root (derived). Plus a key-catalogue IF. |
| I. Unattended operation | 016, 073, 072, 014, 043, 015 | 6 SRs: never prompt while unattended; offer a picker when interactive; launchers; the backup outcome vocabulary; mail ×2. |
| J. Retention | 045, 046, 047, 048 | About 8 SRs: survivors stay restorable; the logical index is unchanged; refuse on risk; interruption-safe; overrides; dry run whose reported reclaim equals the achieved reclaim; container invocation. |
| K. Verify and heal | 049, 054, 053 | 3 SRs. |
| L. Source capture | 001, 057, 021, 022, 055, 067, 041, 074, 036 | About 10 SRs. |
| M. Container | 034, 044, 048 | 3 SRs; 044 moves to TC. |

**Per-row verdicts**

Tags: cn = code name · fn = file name · ia = instrument as acceptance · pv = provenance · ms = more than one decision · bc = buried condition · im = mirrors the implementation · du = derived but unlabelled · sm = schema misalignment.

```
001 reword; absorb 057 source half        | fn cn pv
002 move-down (store-format IF/LLR)       | cn ia im fn
003 split 2; absorbs 060, 026             | ms pv fn im
004 split 3                               | cn fn ia pv ms du
005 split 2; name regex -> IF             | ms fn pv
006 merge 059                             | ms im pv
007 split 2                               | fn cn pv ms im
008 reword                                | cn fn
009 split 2; junction resolution -> LLR   | ms cn pv bc du
010 reword                                | cn bc im
011 reword                                | cn fn ia pv
013 move-down (index IF); wrong parent    | im cn
014 split 2                               | ms
015 split 2                               | ms cn pv sm
016 split 2                               | ms cn fn pv bc
017 -> cluster A                          | ms cn fn pv im
018 merge 042                             | bc
019 reword                                | ms cn ia fn sm
020 split 2                               | ms cn
021 reword                                | cn im fn
022 reword; absorbs 083/087 invisibility  | cn fn ia ms pv
023 reword; absorbs 052 restore half      | cn bc pv
024 reword                                | ia pv
025 move-down (index IF + LLR)            | cn ia im ms
026 merge 003                             | cn im bc
027 split 2                               | fn sm ms
028 split 2                               | ms cn fn im
029 reword; re-parent SN-005/026          | fn pv ms
030 move-down (hash-encoding IF)          | cn im pv
031 reword                                | fn ms pv
032 move-down (index parsing IF)          | cn im pv
033 reword (stale)                        | fn cn im
034 split 3                               | ms cn ia du
035 reword                                | fn pv
036 reword; needs its own SN              | pv
037 split 2                               | ms cn fn pv im sm
038 split                                 | ms cn fn pv im
039 split 3                               | ms cn fn bc pv
040 split 2 + exit IF                     | ms cn fn pv im sm
041 reword                                | cn ms im pv
042 split 4 + key-catalogue IF            | ms cn fn pv im ia
043 split 2                               | ms cn fn im
044 need-defect -> TC                     | ia cn im
045 split 2 + LLR                         | ms cn fn pv im
046 split 4 + LLR                         | ms cn fn pv im bc
047 reword (field list -> IF)             | ms im
048 split 2                               | ms cn fn im ia
049 split 2; absorbs 054                  | ms cn pv im ia
050 merge 068 (contradicts it)            | ms cn fn pv im ia
051 merge 059                             | pv cn
052 split 2                               | bc ms cn fn pv im
053 split 2                               | ms im pv
054 merge 049                             | ms cn pv
055 split 2                               | bc ms pv im
056 split 2                               | bc ms pv
057 merge 001                             | cn pv im
058 move-down (stale grammar)             | cn im pv
059 reword as THE immutability SR         | ms cn pv
060 merge 003                             | pv
061 split 2                               | ms cn pv im
062 reword                                | fn cn ms pv
063 -> cluster H                          | ms pv du im
064 move-down (perf budget / LLR)         | cn im du ia
065 split 3                               | ms fn pv im
066 split 2                               | ms cn pv
067 split 2                               | ms bc pv cn
068 reword                                | ms im cn
069 move-down (store-format IF)           | ms im pv
070 move-down (merge 069)                 | ms cn pv
071 split 2; tool floor -> DA             | fn ms
072 split 2                               | fn ms im
073 split 2                               | ms im cn
074 split 2                               | ms pv
075 -> cluster A; mostly LLR              | ms cn fn pv im
081 split 3 + LLR                         | ms cn pv im ia du
082 reword; mechanism -> LLR              | ms cn fn im pv
083 merge 022                             | ms cn fn
084 retire (compatibility note -> log)    | cn fn im pv ia
085 -> cluster A                          | ms cn fn pv im ia
086 -> cluster A                          | ms cn im ia
087 move-down                             | fn cn im ia
```

Totals: reword 20 · split 35 · merge 14 · move down 10 · need defect 1 · retire 1.

## Appendix C — design layer

**Proposed component tree** (placeholder numbers)

| CMP | part_of | Responsibility |
|---|---|---|
| 001 FileBackup | — | the whole system |
| 002 Backup engine | 001 | produces and maintains a store |
| 003 Source capture | 002 | walk, name and pseudo-folder filtering, hash cache and rehash schedule, directory records, the changed set |
| 004 Object writer | 002 | dedup grouping, owner election, the compression decision, copy retry, capacity check |
| 005 Snapshot lifecycle | 002 | staging, eviction, superseded bytes, publish, run state, kit deposit, duplicate collapse |
| 006 Pool index | 002 | the (hash, length) → locations map |
| 007 Store concurrency guard | 002 | OS lock, owner record, heartbeat, stale reclaim, fences |
| 008 Retention | 002 | plan, rails, re-homing, commit, inventory |
| 009 Store audit and repair | 002 | form audit, pool resolution, repair, kit refresh, orphan scan |
| 010 Browse view | 002 | the generated view |
| 011 Configuration | 001 | validation, defaults, environment overrides, tool resolution |
| 012 Run entry point | 001 | CLI, dispatch, per-set isolation, status code, mail |
| 013 Store format core (restore-safe) | 001 | manifest, witness and sidecar formats, hashing, name codec, form sniff, compressor adapter, volume probes, logger |
| 014 Restore kit | 001 | the restore behaviour both restorers share: CLI, status, output tree, kit layout |
| 015 PowerShell restorer | 014 | |
| 016 POSIX restorer | 014 | includes the shims |
| 017 Restore launchers | 014 | |
| 018 Container runtime | 001 | entrypoint, environment and mount contract |
| 019 Container lifecycle tooling | 001 | build, smoke test, export, publish (delivery; see D3) |
| 020 Config builder | 001 | |

**Proposed interfaces: form only, owner in brackets**

- **System boundary:**
  - 1 container action word and env [018; requestor HomeHub]
  - 2 mounts [018]
  - 3 OCI image [019]
  - 4 config document schema [011]
  - 5 environment overrides [011]
  - 6 backup CLI [012]
  - 7 backup status codes {0–4} with precedence [012]
  - 8 restore CLI [014]
  - 9 restore status codes [014]
  - 10 stdout record formats [012]
  - 11 store layout [002]
  - 12 manifest format [013]
  - 13 witness format [013]
  - 14 stored-object naming and content form [013]
  - 15 directory records [013]
  - 16 restore kit artifact set and marker [014]
  - 17 launchers [014]
  - 18 restored tree [014]
  - 19 source filesystem view [external]
  - 20 log line and refusal-token alphabet [013] (the tokens embed SR ids today; flag)
  - 21 mail [012]
  - 22–25 7-Zip, ffprobe, the XXH128 encoding and the folder picker [external]
  - 26 browse view files [010]
- **Internal, cross-process** (each needs a version, because an older FileBackup is the other side): 27 store lock, 28 owner record and heartbeat, 29 run state.
- **Internal, within the engine:** 30 pool index, 31 witness verdict, 32 volume probes, 33 form sniff, 34 locator result (optional), 35 mutation lock.

Today's IF-001 splits into 1–4, 7, 9, 10 and 11. Its HomeHub policy text goes to `external.toml` and assumption rows.

**Per-LLR first pass**

Key: RW = reword to contract voice · SP = split · MG = merge with · CH = becomes child of · RT = retire · SR = is really an SR · TC = is really a TC.

```
001 SP walk / diff(child)      002 SP hex->IF24; library->new LLR for SR-019
003 MG 058                     004 SP list RW; 7z->CH 058; level->MG 037
005 RW                         006 MG 051
007 RW; artifact list->IF16    008 RW (top restore LLR)
009 RW; parent of 072,079      010 RW
011 RW                         014 SR
015 RW                         016 SP backup RW; restore MG 073
017 SP children of 080         018 MG 043
020 RW                         021 RT (coding rule)
022 RW; parent of infra names  023 RW
024 RW; ordering->IF12         025 SP schema->IF12
026 RW; probe-once child       027 SR
028 SP / RT                    029 CH 008
030 MG 002                     031 RT
032 RT into IF12               033 SR
034 SP image->IF3; smoke->TC   035 RW
036 RW                         037 RW
038 SP form->IF13; MG 022      039 RW
040 SP alphabet->IF9           041 RW
042 SP keys->IF4; behaviour RW 043 RW
044 TC                         045 RW
046 SP rails/commit/residue    047 SP index/inventory; memory->PB
048 RW                         049 SP classes->IF10; children
050 CH 008                     051 RW
052 SP probe CH 023; preflight 053 RW
054 RW                         055 RW
056 CH 008                     057 RT
058 RW                         059 RW
060 SP backup / restore        061 RW
062 RW                         063 MG 042
064 MG 048                     065 SP form->IF15; restore CH 008
066 CH 008                     067 RW
068 CH 008                     069 SP grammar->IF14
070 RT into IF14               071 RW
072 CH 009                     073 RW
074 RW                         075 SP list->IF16; legacy CH 022
076 RW                         077 CH 008 (wrong parent today)
078 RW                         080 SP record->IF28; classifier; heartbeat; reclaim
086 SP rule / sampling / codec 087 RW; publish->IF12
088 SP CH 022 + CH 080         089 MG 076
090 RW                         091 RW; 092, 094 fold in
092 MG 091                     093 TC
094 MG 091
```

Totals: RW 37 · SP 22 · MG 9 · CH 8 · RT 5 · SR 3 · TC 2.

**What the prose docs become:**
- `architecture.md`: generated from CMP and IF, except the runtime flow and the reason for the restore-safe split.
- `interfaces.md`: a generated contract reference.
- AGENTS.md §2 (the file and role table): derivable from the code headers.
- AGENTS.md §3: about 90% restates SRs and goes. The genuine design invariants become LLRs on their interfaces:
  - Common never depends on Engine.
  - Exactly one name parser and one form-agreement predicate.
  - The witness is never copied or stamped from a caller.
  - Every store writer takes the lock; the lock file is never deleted.

## Appendix D — test cases

- **Tagging today:**
  - 43 of 53 test files mention a TC, but only in prose.
  - 355 of about 825 test blocks name a TC in their own title.
  - 75 TCs appear nowhere in `tests/`; 49 of them can be found backwards, from a Describe title or G-case named in the TC cell.
  - About 160 of the 234 can be resolved by script.
- **Buckets:**
  - 8 drafts with no test behind them: TC-032/035/038/042 are observation cases; also TC-057, 169, 170, 195.
  - 45 more drafts already have tests, so their status is stale.
  - 77 need re-pointing (and every row will need it once the LLRs change).
  - 16 rows in 9 overlap clusters.
  - 110 have mechanical text problems.
  - 23 are clean apart from format.
- **Overlap clusters:** 002/096 · 030/046 · 033/045 · 026/027/028 · 020/059/171/080 · 031/048 · 019/119 · 115/167 · 041/089/235. The PowerShell/bash twins are legitimate pairs.
- **Approach:** harvest (Phase 0), regenerate from the LLRs (Phase 4), keep ids where a case maps one to one, then do the tagging pass.
