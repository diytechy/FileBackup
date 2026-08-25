# WP9 — Content-addressed storage + browse view (D-1 / D-5 fix): work order

**Drafted 2026-08-25** by the driver, pinned at `553638c` — every line reference
below is that commit's coordinates. This is the **implementation work order**
for the design the human ruled on 2026-08-24; the design record it implements is
[option3-content-addressed-storage-plan.md](option3-content-addressed-storage-plan.md)
and the evidence is
[../defect-review-2026-08-24-mirror-dedup.md](../defect-review-2026-08-24-mirror-dedup.md).

> **Naming.** The request named these defects **D-FB1** and **D-FB5** (the
> HomeHub-side prefix for FileBackup defects). They are this repo's **D-1**
> (stale cross-path dedup reference — *data loss*) and **D-5** (same-run
> duplicates each stored in full — *space*), the two the 2026-08-24 review
> called "the same mechanism seen from two sides". D-2/D-3/D-4 are already
> implemented (kit rev 6) and are **not** in this WP.

**Gate posture, under the human's 2026-08-25 standing directive.** That entry
ratified the kit-bump G3 and ruled: *"everything that is queued to be addressed
and fixed should be fixed, without any arbitrary ratification bars, so that a
full solution can be implemented, tested, and handed off to HomeHub"*, with
**HomeHub holding** until the full solution is ready. So this WP runs
**G1 → G2 → G3 + the mandatory independent pre-gate review** (retained: a
quality bar, not a ratification bar — it caught real blockers twice), and
**does not pause for ratification**. Gate *evidence* is still recorded in
status.md as always. §9 therefore lists **decisions the driver takes and
records**, not questions that block — each is flagged for veto, and Q1 is
flagged loudly because it refines a ruling the human made personally.

**Ids allocated (provisional until G2 closes):** SN-034, SR-058..SR-064,
LLR-058..LLR-064, TC-118..TC-135, plus **TC-117 + the SR-055/LLR-055 amendment**
already drafted for the reserved-device-names item the ratification entry moved
**IN** to this WP (§3.10), plus amendments to SN-008, SR-003, SR-010, SR-012,
SR-013, SR-022, SR-028, SR-042, SR-051, SR-052.

---

## 1. Grounding table (verified @ `553638c`)

| # | Fact | Location |
|---|---|---|
| G1 | Dedup adoption consults the **prior backup only**: rows with matching `(xxH2Hash,Length)` and a non-blank DataPath; the list is computed **once, before the member loop** | `Engine.psm1:2868-2870` |
| G2 | **D-5 mechanism.** Because G1's list is computed before the loop, every member of a *new* group takes the copy branch. In hash mode all members compute the *same* name (one file, re-copied N times — wasted work); in Mirror mode each computes its **own** rel path — N physical copies | `Engine.psm1:2877-2937` |
| G3 | **D-1 mechanism.** The Mirror copy destination is `"$rel.7z"` / `$rel` — the row's own path — so a content change **overwrites in place** while borrower rows keep pointing at it | `Engine.psm1:2891-2899` |
| G4 | `Save-SupersededData`'s survival test asks "is this content anywhere in the **new source**", not "does a live **backup row** still demand it" — the source-based answer is what authorizes the in-place overwrite | `Engine.psm1:3047, 3054` |
| G5 | `Compare-SourceToBackup` only re-examines a path whose own metadata changed (or whose DataPath is blank) — the borrower is never revisited | `Engine.psm1:2809-2826` |
| G6 | Storage form is decided in exactly **four** places, all from `PreserveFolderTree` / `StoredAsHashSize` | `Engine.psm1:665` (Sync), `:1053` (re-home), `:2870/2932` (copy), `:3195` (capacity) |
| G7 | The restorers **never** branch on `StoredAsHashSize` or on tree mode; both scan candidates **recursively** and match by `(hash,length)` after proving the form | `Reconstruct.ps1:244-330`; `reconstruct.sh:412`; only mention: `Common.psm1:688` (column pass-through) |
| G8 | `PreserveFolderTree` reaches the engine through the closed config key set, the shape check's boolean list, and the defaults materializer | `Engine.psm1:3672-3673, 3858, 3937` |
| G9 | `$script:ConfigSchemaVersion = 1`; the published schema mirrors it with `const: 1` | `Engine.psm1:3654`; `container/FileBackup.schema.json:34,46` |
| G10 | `Sync-BackupStorageLayout` **skips** a `(hash,length)` group whose members disagree about compression ("Form conflict"), leaving it permanently un-migrated | `Engine.psm1:684-696` |
| G11 | Migration is **copy → persist manifest → delete** (B7), so it transiently needs a second copy of everything it moves; `Get-MigrationCapacityDemand` sizes that and `Assert-BackupCapacity` refuses without room | `Engine.psm1:620-828, 3160-3208, 3535-3538` |
| G12 | O(N²) unreferenced-file audit: `$db` is re-piped through `Where-Object` **per on-disk file** | `Engine.psm1:610-614` |
| G13 | `Test-IsInfrastructureFile` is root-level-only and serves **both** the source walk and the pool walks — it stays needed after Mirror dies | `Engine.psm1:30-68, 113-153` |
| G14 | SR-022's Mirror-name refusal (copy path) and its prune/repair twins exist only because a Mirror DataPath can spell an infrastructure name | `Engine.psm1:2906-2916` + `Get-ReHomedDataPathName` / `Repair-BackupStorageForm` |
| G15 | Hash names are `"<hash16> <len10><ext>"` (~27 chars, one space) — a grammar no user file can accidentally satisfy at the pool root, and MAX_PATH-flat | `Common.psm1:371-387` |
| G16 | Test matrix: `Run-All.ps1 -Modes` sweeps 4 combos; `Write-TestConfig` takes `-ContentAddressed` and sets `PreserveFolderTree = -not $ContentAddressed` | `tests/Run-All.ps1:29`; `tests/Common/Harness.ps1:135-155` |
| G17 | Mirror-dependent test sites: `Coverage.Tests.ps1` (23), `StorageForm.Tests.ps1` (11 + 34 `-ContentAddressed`), `G4-Sanitization.ps1` (6), `G2-Incremental.ps1` (2), `RestoreVerify.Tests.ps1` (1) | grep @ `553638c` |
| G18 | Active gate `G3`; registries end at SN-033 / SR-057 / LLR-057 / TC-116 | `docs/gate`, registries |

---

## 2. What the fix actually is (three changes, one invariant)

1. **One addressing semantic.** Every stored object is named by its content
   (`Get-HashSizeFileName`). Different content ⇒ different name ⇒ **an existing
   stored object is never overwritten**. D-1's hazard class is deleted, not
   guarded.
2. **Intra-run dedup.** The `(hash,length)` group elects one physical form and
   writes it **once**; the remaining members adopt it in memory. D-5 dies with
   the same edit, and the redundant re-compression of identical bytes in hash
   mode goes with it.
3. **The view replaces Mirror's only real value.** A generated, manifest-derived
   index outside both roots gives browse + search, and is *more* faithful than
   Mirror ever was (Mirror omits borrower paths entirely).

The invariant to state, test, and never lose again:

> **SR-059 (new).** A run may create a stored object and it may delete one, but
> it may never **change the bytes at a DataPath that any live manifest row still
> claims**; and an object may only be created at a content-addressed name that
> its own bytes actually hash to.

Both halves get direct tests (§6, TC-122 / TC-121). Hash naming makes the first
half structural — the test is what keeps it structural.

---

## 3. Design decisions carried into implementation

The driver's position on each. Under the 2026-08-25 standing directive these are
**taken, recorded, and open to veto** rather than held — §9 collects them with
the reasoning, and marks the one that refines a personal ruling of the human's.

### 3.1 Flat pool at the backup root — **no `pool/` subfolder** (driver call, reversible)

The design record left this open ("recommended, decide at G1"). Recommendation:
**keep the flat root.** The safety the subfolder was meant to buy is already
bought by G15 — a hash name (`"<16> <10><ext>"`) cannot collide with any
infrastructure name, so the whole B6/SR-022 collision family dies from hash
naming alone. A subfolder would instead re-touch every relative-path computation
in prune, re-home, snapshot staging, the storage-form audit, and both restorers'
interop fixtures: cost with no safety delta. Recorded as a follow-on if a future
deployment wants the structural separation; no-backward-compat makes moving it
later exactly as free as moving it now.

**Compensating control:** TC-123 asserts that every non-infrastructure file at
the backup root matches the hash-name grammar.

### 3.2 The 9-column manifest schema is untouched (driver call)

`StoredAsHashSize` freezes at the constant `'Hash'`; `Duplicate` keeps its
existing meaning (a source-side annotation from `Update-SourceManifest`, which
already does not decide byte placement). **Zero restorer diff, zero bash-parser
diff, zero interop-fixture churn.** Column retirement stays out of scope
(option-3 plan §7).

### 3.3 There is no migration — a legacy store is refused, not converted (**HUMAN RULED 2026-08-25**)

**Ruling: "No storage exists currently here that must be maintained. Migration is
a moot point."** So the `Original → Hash` conversion is **deleted, not kept**,
and with it the two hard requirements an earlier draft of this plan carried
(verify-before-name; rename-instead-of-copy). Both existed only to make an
in-place conversion of an existing Mirror store safe, and there is no such store
to protect.

What ships instead:

- **`Sync-BackupStorageLayout` loses the tree-mode axis entirely** and keeps only
  the compression-flip axis, which is still real (`CompressEnabled` can be
  toggled on an existing store). B7's copy-then-delete order and SR-051's
  never-delete-a-still-referenced-file rule are unchanged for that axis.
- **A row stored in the legacy `Original` form is refused, loudly.** If a
  manifest carries `StoredAsHashSize = 'Original'`, `-Action Backup` fails the
  set before mutating anything, naming the condition and the remedy: *this store
  was written by a pre-content-addressed build; back up to a fresh `BackupPath`.*
  `-Action Verify` **reports** it as a finding rather than refusing — an audit
  action that cannot audit is useless.
- **Test fixtures follow.** `tests/fixtures/bash-restore/Mirror*` (two fixture
  trees, Mirror and Mirror_Compress) are content-addressed stores' twins from a
  layout that no longer exists; they are regenerated as content-addressed or
  deleted at step 5 (`scripts/gen_bash_fixtures.ps1` owns them).

Net effect on this WP: step 3 shrinks to a deletion plus one refusal,
`Get-MigrationCapacityDemand` keeps only its compression term, and the two
migration risks (pool poisoning, capacity refusal on a 4 TB store) **disappear
from §7** — they were consequences of converting in place.

### 3.4 Group form election (replaces the "form conflict" skip)

A `(hash,length)` group can contain members whose extensions differ (`a.txt`,
`a.dat`) and therefore whose `Test-ShouldCompress` answers differ — today that
yields either two physical copies (copy path, G2) or a permanent skip (Sync,
G10). Election rule, applied identically in `Invoke-BackupFileGroup` and
`Sync-BackupStorageLayout`:

> The group's **owner** is the member with the shortest `RelativePath` (ties
> broken by ordinal comparison) — the same election `Update-SourceManifest`
> already uses to assign `Duplicate`. The owner's extension and compression
> decision define the single stored object; every member's row records that
> object's `DataPath` / `Compressed`.

This is the precedent already set at `Engine.psm1:2884` (adopting rows take the
*existing* row's `Compressed`), and it retires G10's WARN-and-skip class.

### 3.5 `Save-SupersededData` moves **after** the copy/evict steps (driver call)

Under content addressing nothing is overwritten, so preservation no longer has to
run before step 10. Moving the call to just after step 11 lets the survival test
be **exact** — "does any row in the final manifest still demand this
`(hash,length)`" — instead of the source-based approximation at G4 that
authorized D-1's overwrite. Frozen rows (SR-055 / SR-057) and evicted rows are
then accounted for correctly, which the source-based test never could.

### 3.6 The view: TSV always, HTML **per folder** (**HUMAN APPROVED 2026-08-25**)

The human ruled "HTML index, not links" on 2026-08-24 and **approved this
refinement on 2026-08-25** ("Agreed, I did not think of file expansion").
The scale fact behind it:
a single `INDEX.html` over the production library (~500k files) is roughly
**100 MB of markup** — no browser opens that comfortably, and it would be
regenerated every run. Proposal that keeps the ruling's intent (browsable +
searchable) and scales linearly:

- **`INDEX.tsv`** — always generated, one line per logical path:
  `RelativePath ⇥ DataPath ⇥ Length ⇥ xxH2Hash ⇥ Compressed`. Authoritative,
  greppable, tiny per row, the scripting surface.
- **`INDEX.html` per folder** — one small page per source directory, mirroring
  the tree as *pages*: subfolder links, plus one relative `<a href>` per file
  pointing at the pool object (double-click opens/extracts it, as Mirror browsing
  did). Each page is bounded by that folder's fan-out, so it opens instantly at
  any library size.
- **Root search** — the root `INDEX.html` embeds a search box over a compact data
  file when the row count is under a threshold (default 50 000), and above that
  prints the exact `grep` / `Select-String` one-liner against `INDEX.tsv`. Honest
  degradation, never a page that hangs the browser.

Naming rule (from the design record, unchanged): entry name = `RelativePath` +
(`Compressed -eq 'Yes'` ? `'.7z'` : `''`), driven by the **row**, never the set's
config — per-file compression means mixed trees.

### 3.7 View location, staleness, lifecycle (driver call)

- Default `<BackupPath>_View`, overridable by `ViewPath`; **refused** when
  `Get-VolumeIdentity` disagrees with `BackupPath`, and refused when the resolved
  path lies inside `BackupPath` or `ChangePath` (it would be walked as data).
- Regenerated as **pipeline step 16**, after `Optimize-ChangeFolders` has elected
  keepers; skipped when the manifest witness matches the `.viewstamp` recorded at
  the view root; forced by `-Action View`.
- **Snapshots get no view** (invariant): prune's `PhysicalBytes` accounting, the
  staging rename, and snapshot self-containment all argue against it.
- A torn or stale view is **cosmetic by construction** — nothing in the engine or
  either restorer reads it.

### 3.8 Config v2 and how a stale config fails (driver call on the CLIXML half — §9 Q3)

`ConfigVersion` becomes **2**; `PreserveFolderTree` is **deleted** from the
closed key set and gets a **named** diagnostic rather than the generic
unknown-key message ("PreserveFolderTree was removed in ConfigVersion 2: storage
is always content-addressed. Remove the key."). `BrowseView` (`"off"|"index"`,
with `"link"` reserved and refused by name) and `ViewPath` are added. The
published schema, the container example, `FileBackup.ps1`'s help block and README
follow.

**The CLIXML gap:** legacy CLIXML configs are exempt from `ConfigVersion` *and*
from the closed schema, so a CLIXML set carrying `PreserveFolderTree = $true`
would be **silently ignored** — a user believing they still have Mirror. Driver
recommendation: **refuse it by name** (config failure, status 2) in
`Resolve-BackupSetDefaults`, for both formats. See §9 Q3.

### 3.9 Folded items (from status.md Open items / option-3 §6)

| Item | Disposition in this WP |
|---|---|
| O(N²) unreferenced scan (G12) | **Fixed** — one referenced-DataPath hashtable; the pattern already exists at `:761/:772` |
| DataPath-keyed case-insensitive maps | Swept to `New-RelativePathMap` in the functions this WP already opens |
| manifest row order | `Sort-Object` before `Write-Manifest` (partly done at `:3630`), pinned by a determinism test |
| Source-side manifest cache default | **Out of this WP** — an independent config change with no D-1/D-5 coupling; stays an Open item (§9 Q5) |
| Windows reserved device names | **IN** — the 2026-08-25 ratification moved the deferred kit-bump plan §11 Q2 into this WP; see §3.10 |
| **S3 (trivial half) — re-homing is a same-name copy** | **FOLDED IN** (2026-08-25 architecture read): a content-addressed name is derived from content, so a re-homed file's source and destination names are always identical — `Get-ReHomedDataPathName` (30 lines) collapses and the "already re-homed?" question becomes a filename test. The `Get-BackupContentIndex`/`Optimize-ChangeFolders` half is to be MEASURED here, not promised. See status.md "Simplification candidates" |
| **F8 kit-less snapshot window** | **FOLDED IN** (driver call 2026-08-25): a crash between the `Temp`→`Snapshot_*` rename and the kit copy leaves a valid snapshot with no restore kit. Fix: copy the kit into staging **before** the rename. This WP already opens `Complete-ChangeFolder`'s neighbourhood, and the standing directive says the queue ships whole |

### 3.10 Windows reserved device names — the deferred SR-055 extension, now IN

The kit-bump WP withheld this pending a ruling (`CON`, `NUL.txt`, `COM1` etc.
pass today's portable-name guard, and the worst case is a loud copy failure on a
Windows restore). The 2026-08-25 ratification entry lists it as **now IN** for
this WP, and it belongs here: `Test-PortableRelativePath`
(`Engine.psm1:72-111`) is a **per-component** rule and the reserved-name check is
one more component predicate.

- Rule: a name component whose stem (the text before the first `.`) is, case
  insensitively, `CON`, `PRN`, `AUX`, `NUL`, `COM1`..`COM9` or `LPT1`..`LPT9` is
  **not portable**, with or without an extension.
- Consequence, disclosed: a Linux source holding `NUL.txt` starts **failing
  loudly** (SR-055's existing behavior — the file is skipped, the row is frozen,
  the set is marked failed and the operator is told to rename at the source).
  That is a new refusal class, which is exactly why it was held for a ruling.
- Registry: amend **SR-055** and **LLR-055** (both already drafted at
  kitbump-rev6-plan.md §310/§313), add **TC-117** (unit/smoke) exactly as that
  plan's §329 row specifies.
- Storage-side impact: none. A content-addressed name (`"<16> <10><ext>"`) can
  never spell a device name, so this is purely the source-walk guard.

---

## 4. Registry rows — **already committed** (2026-08-25, `Phase=ca-v1`)

> **These rows are in the registries now, not waiting for G1.** That is the
> anti-loss mechanism: `trace.py`'s orphan rules are phase-blind, so every one of
> these SRs already carries its LLR and TC rows, while `--require-verified
> --phase core,bash-v1,container-v1,kitbump-v6` reports them as **phase-deferred**
> (8 rows: SR-033 bash-v2 + the seven `ca-v1` rows) instead of demanding they be
> Verified. Nothing can be quietly dropped: the moment `ca-v1` joins the ratchet
> in `scripts/check.ps1`, every row below must be Verified/Pass or the G3 check
> fails. SR rows are `Status=Draft`, LLRs `Planned`, TCs `Draft` — the same
> pattern SR-033/TC-057 (bash-v2) has used since 2026-07.

### 4.1 `stakeholder-needs.md`

- **SN-008 — REWRITE.** Was "Choose the on-disk layout…". Becomes: *"See what is
  in the backup and find a file by name, without running a restore."* Why:
  browsing was the only reason to mirror the tree. Priority **S**. Acceptance:
  the generated index lists every logical path — including every duplicate
  sibling — and opening an entry opens that file's stored object.
- **SN-034 — NEW.** *"Nothing already stored in the backup may be silently
  rewritten by a later run."* Why: an ordinary edit of one of two duplicate files
  destroyed the last copy of the shared content, invisibly (D-1). Priority **M**.
  Acceptance: after editing one of two identical files, restoring the previous
  snapshot still reproduces the old bytes for **both** paths, and the pool audit
  reports no blank row whose content is unaccounted for.

### 4.2 `system-requirements.csv` (header: `SR-ID,Title,SN-Refs,Requirement,Rationale,AcceptanceCriteria,Permutations,Priority,Verification,Status,Phase`)

| SR | Title | SN | Requirement (abbrev — full prose at G1) | Verification |
|---|---|---|---|---|
| SR-058 | Content addressing is the only storage layout | SN-002;SN-008 | Every data file the system stores shall be named `Get-HashSizeFileName(hash,length,ext)`; no configuration selects a mirrored layout | Test |
| SR-059 | Stored objects are immutable and name-proven | SN-034;SN-005 | No run shall change the bytes at a DataPath any live manifest row still claims; an object shall only be created at a content-addressed name its own bytes hash to | Test |
| SR-060 | Dedup covers content first seen within one run | SN-002 | Identical `(hash,length)` content appearing several times in one run shall be stored once, with every logical name referencing that one object | Test |
| SR-061 | A legacy-form store is refused, not converted | SN-008;SN-030 | A manifest row stored in the legacy `Original` form shall fail the backup set before any mutation, naming the condition and the remedy (a fresh `BackupPath`); `-Action Verify` shall report it as a finding rather than refuse. There is no in-place conversion (human ruling 2026-08-25: no store exists that must be maintained) | Test |
| SR-062 | Generated browse view | SN-008 | When `BrowseView` is `index`, the system shall generate a manifest-derived index outside both roots (TSV always; per-folder HTML), covering every logical path including duplicates, refreshed when the manifest witness changes and on `-Action View`; nothing in the engine or the restorers shall read it | Test |
| SR-063 | Configuration contract v2 | SN-027;SN-008 | `ConfigVersion` shall be 2; `PreserveFolderTree` shall be refused **by name** in every config format; `BrowseView` (`off`\|`index`) and `ViewPath` shall be accepted, `ViewPath` refused when it is not on the backup volume or lies inside either root | Test |
| SR-064 | Store audits scale linearly | SN-001;SN-030 | The unreferenced-data-file audit shall be O(N) in manifest rows plus on-disk files | Test |

**Amendments:** SR-003 (dedup key now covers within-run occurrences; states the
owner-election rule); SR-012 / SR-013 (no layout migration exists; `StoredAsHashSize` is
the constant `'Hash'`; the compression-flip migration is unchanged); SR-022 (drop the Mirror-name
refusal clause — the root-only infrastructure classification itself stays, for
the source walk and the pool walks); SR-042 (version 2, key-set change); SR-051
(form election replaces the conflict skip; the never-delete-a-referenced-file
half is unchanged); SR-052 (the migration demand keeps only its compression term); SR-010 / SR-028 (superseded preservation happens after the copy/evict steps
and tests survival against the **final** manifest).

### 4.3 `low-level-requirements.csv` (`LLR-ID,SR-Refs,Title,Module,CodeSymbol,Detail,TestRefs,Status`)

| LLR | SR-Refs | Module | CodeSymbol |
|---|---|---|---|
| LLR-058 | SR-058;SR-060;SR-003 | Engine | `Invoke-BackupFileGroup` (owner election + intra-run memo; `PreserveFolderTree` param deleted) |
| LLR-059 | SR-010;SR-028;SR-059 | Engine | `Save-SupersededData` (moved after evict; survival tested against the final manifest) |
| LLR-060 | SR-061;SR-051;SR-012 | Engine | `Sync-BackupStorageLayout` (tree-mode axis deleted; compression-flip axis kept; legacy `Original` row refused) |
| LLR-061 | SR-062 | Engine | `New-BrowseViewIndex` (**new**; Engine-side only — Common must never grow view code, AGENTS.md §3) |
| LLR-062 | SR-064 | Engine | `Test-BackupManifest` (linear referenced-path map) |
| LLR-063 | SR-063;SR-042 | Engine | `Assert-NoUnknownConfigKey` / `Test-BackupConfigurationShape` / `Resolve-BackupSetDefaults` |
| LLR-064 | SR-062 | FileBackup.ps1 | `Invoke-ViewAction` + `-Action View` dispatch |

### 4.4 `test-cases.csv` — TC-118..TC-135, detailed in §6

---

## 5. Ordered implementation plan (G3, test-first; one green commit per step)

Each step is a commit that leaves lint, unit and the affected suites green.
Step 1 is written **red first** — it reproduces D-1 and D-5 on today's code.

| # | Step | Touches | Exit evidence |
|---|---|---|---|
| **1** | **Red repros.** Owner-edit-of-a-duplicate across all four *current* modes (D-1) and a same-run duplicate copy counter (D-5). Both must FAIL on Mirror and PASS on HashAddressed today — that asymmetry is the proof the tests are real | `tests/Unit/Coverage.Tests.ps1`, `tests/Common/PoolAudit.ps1` | Pester output showing the Mirror failures and the hash-mode passes |
| **2** | **Intra-run dedup + owner election** in `Invoke-BackupFileGroup` (still mode-aware at this step): elect the owner's form, write once, memo the group's DataPath in-process, adopt for the rest | `Engine.psm1:2834-2939` | D-5 repro green in both modes; copy counter = 1 |
| **3** | **Delete the tree-mode migration axis** from `Sync-BackupStorageLayout` (compression-flip axis kept); apply the owner election there too and delete the form-conflict skip; refuse a legacy `Original` row loudly, report it under `-Action Verify` | `Engine.psm1:620-828`, `:3160-3208` | TC-124 green; existing G4 suite green |
| **4** | **Preservation reorder + exact survival test** (`Save-SupersededData` after step 11; survival from the final manifest) | `Engine.psm1:3010-3074, 3596-3625` | D-1 repro green **in Mirror too**; G9 rollback suite green |
| **5** | **Delete Mirror.** `PreserveFolderTree` out of the engine signatures, the config key set, the shape check and the defaults materializer; hash naming unconditional; the SR-022 Mirror refusal and its dead twins removed; `StoredAsHashSize` pinned to `'Hash'` | `Engine.psm1` (G6 + G8 sites), `FileBackup.ps1` help, `container/*.json`, harness + every Mirror test site (G17), `tests/fixtures/bash-restore/Mirror*` regenerated or deleted via `scripts/gen_bash_fixtures.ps1` | Full unit + integration green on the **2-mode** matrix |
| **6** | **Config v2:** `$script:ConfigSchemaVersion = 2`, named refusal for `PreserveFolderTree` (both formats), `BrowseView` / `ViewPath` accepted and validated | `Engine.psm1:3654-3705, 3790-3941`, `tests/Common/ConfigFixtures.ps1` | TC-125..TC-128 green; TC-077 updated |
| **7** | **The view:** `New-BrowseViewIndex` + `.viewstamp` + pipeline step 16 + `-Action View` dispatch + the volume/containment refusals | `Engine.psm1` (new function), `FileBackup.ps1` | New **G10-View** suite green (§6) |
| **8** | **Folded fixes:** linear unreferenced audit, `New-RelativePathMap` sweep, deterministic row order, and **F8** (copy the restore kit into staging *before* the `Temp`→`Snapshot_*` rename, closing the kit-less-snapshot window) | `Engine.psm1:584-618`, `Complete-ChangeFolder`/`Update-BackupSnapshotKit` + sweep sites | TC-132 green; G7 determinism suite green; a kill between rename and kit copy leaves no kit-less snapshot |
| **8b** | **Reserved device names (§3.10):** one component predicate in `Test-PortableRelativePath`; SR-055/LLR-055 amended, TC-117 added. Independent of everything above — can land any time after step 1 | `Engine.psm1:72-111`, registries | TC-117 green; SR-055's existing skip/freeze/fail behavior unchanged |
| **9** | **Docs + generated artifacts + registries:** AGENTS.md §2/§3/§6, README, regenerated `docs/architecture.md` maps, `docs/interfaces.md` / IF-001 if the container contract names modes, registry rows flipped to Verified, status.md audit entry | docs, registries | `check.ps1 -Gate G3` all steps pass; `trace.py --strict --require-verified` 0/0/0 |

**Kit revision.** The restore kit's *code* does not change (G7), but
`Reconstruct.ps1`'s and `reconstruct.sh`'s comments describing Mirror do. If any
byte of the kit changes, **both markers bump together** (kit rev **7**) per the
rev-6 precedent; if nothing in the kit changes the revision stays at 6 and the G3
entry says so explicitly. Decide at step 9, not before.

---

## 6. Test plan (G2 artifacts; TC-118..TC-135)

**Matrix collapse.** `Run-All.ps1 -Modes` drops to `Plain,Compress`; the
integration budget roughly halves and funds the battery below.

| TC | Level | What it pins |
|---|---|---|
| TC-118 | Integration | **D-1 repro (the headline).** A and B identical; run; edit A; run; the *previous* snapshot restores the old bytes for **both** paths, and no live row's `(hash,length)` is unaccounted for. Runs on ±Compress |
| TC-119 | Integration | **D-5 repro.** Two identical files first seen in one run ⇒ exactly **one** physical object; the copy/compress counter proves one write, not two |
| TC-120 | Unit | Owner election is deterministic: mixed extensions (`a.txt`/`a.dat`) and mixed compressibility (`x.txt`/`x.jpg`) in one group elect exactly one object, and every row's `Compressed` describes *that* object |
| TC-121 | Unit | Every new DataPath matches the hash-name grammar; `StoredAsHashSize` is `'Hash'` on every written row |
| TC-122 | Integration | **SR-059 invariant.** Across a multi-run timeline, no byte at a DataPath any live row claims ever changes (per-run stat+hash census of the pool) |
| TC-123 | Integration | No non-infrastructure file at the backup root fails the hash-name grammar (the §3.1 compensating control) |
| TC-124 | Integration | **Legacy-store refusal.** A manifest carrying `StoredAsHashSize = 'Original'` fails `-Action Backup` before anything is staged or mutated, with the fresh-`BackupPath` remedy in the message; the same store under `-Action Verify` yields a finding and a non-zero audit status, never a refusal; a compression flip on a content-addressed store still migrates correctly (the surviving axis) |
| TC-125 | Unit | `PreserveFolderTree` in a **JSON** config fails with the named diagnostic and status 2 |
| TC-126 | Unit | `PreserveFolderTree` in a **CLIXML** config fails the same way (per §9 Q3), and `ConfigVersion: 1` is refused as too old |
| TC-127 | Unit | `BrowseView` vocabulary: `off` / `index` accepted, `link` refused by name, anything else refused |
| TC-128 | Unit | `ViewPath` refusals: different volume; inside `BackupPath`; inside `ChangePath` |
| TC-129 | Integration | **G10-View:** the index matches the manifest exactly — every logical path present, **including every dedup sibling**; per-file compression yields a mixed tree named from the row |
| TC-130 | Integration | The view is invisible to the engine: Verify, prune accounting, `Get-DataFile` and both restorers ignore it entirely |
| TC-131 | Integration | Witness staleness ⇒ rebuild; `-Action View` is idempotent; a torn view is rebuilt, never trusted |
| TC-132 | Unit | The unreferenced-data audit is linear (behavioral/timing proof at 10k rows) |
| TC-133 | Integration | Snapshots get **no** view (invariant) |
| TC-134 | Integration | bats twin: `reconstruct.sh` restores a content-addressed store built by this WP, and its `find … -type f` (no `-L`) link-immunity is pinned **as intent** |
| TC-135 | Integration | **Owner deleted while a borrower lives** (B9's refcount, untested today): removing the shorter-path member of a dedup group evicts nothing the surviving member still needs — the borrower restores byte-exact from the live backup, and the snapshot restores the removed path's bytes |

### 6.1 Drill permutation coverage — what is already ported, what WP9 owes

The HomeHub drill (`scripts/verify/library-permutation-drill.sh`) was never
copied into this repo; its **assertions** were ported in the kit-bump WP. Status
of the eight permutations recorded in the 2026-08-24 verification entry:

| Permutation | State @ `553638c` | Owner |
|---|---|---|
| Blank-row hashes vs the verified pool (*the assertion that caught D-1*) | **Ported and strengthened** — `tests/Common/PoolAudit.ps1` proves by reading and hashing bytes (and expanding `.7z` payloads), not by `Test-Path`; run at the end of the G2/G3/G9/G9Prune timelines | TC-116 (shipped) |
| Nested dot-directories | **Ported** (`.config/nested/deep.txt`, all modes) | TC-113 (shipped) |
| Windows Hidden (files + directories, System attribute) | **Ported** | TC-113 / TC-114 (shipped) |
| Same-length corruption | **Ported** (`same-length-bitflip`, both restorers + cross-artifact interop) | TC-108 / TC-109 / TC-110 (shipped) |
| All-four-modes owner-edit (**the D-1 shape**) | **NOT ported** — deliberately: it cannot pass while Mirror exists. TC-116's row records the deferral | **WP9 TC-118** |
| Same-run vs prior-run duplicates | **Half ported** — `G2.8 Dedup_singleDataPath` is de-vacuumed (one DataPath + one physical copy in hash mode; the Mirror arm is a *labelled change-detector* that documents D-5). Prior-run dedup was already covered | **WP9 TC-119** (same-run half, properly) |
| Edit-the-borrower | **NOT ported** — no equivalent anywhere | **WP9 TC-118**, added arm |
| Multiple borrowers | **NOT ported** — no equivalent anywhere | **WP9 TC-118**, added arm |
| Owner deleted while borrower lives (B9 eviction refcount) | **NOT ported** — only the *migration*-side refcount is tested (`StorageForm.Tests.ps1:436,539`, SR-051); `Move-RemovedFilesToStaging`'s own refcount has no named test | **WP9 TC-135** (new) |

TC-118 therefore runs as a **timeline**, not a single case: two identical files →
edit the owner → edit the borrower → add a third copy → remove the owner while a
borrower still lives, asserting after every step that each path restores its
own-era bytes from the right snapshot and that `Get-BlankRowPoolViolations`
reports nothing.

**Battery import** (status.md, approved + expanded 2026-08-24) — now unblocked by
the freed budget: owner-edit across the surviving modes (TC-118), the
byte-verified orphan second pass extended to the D-1 shape (`PoolAudit.ps1`,
TC-116's deferred arm), and de-vacuuming `G2.8 Dedup_singleDataPath` (assert
`-eq 1`, not `-le 2`).

---

## 7. Regression risks, with the call sites

| # | Risk | Guard |
|---|---|---|
| R1 | A user who *does* hold a pre-v2 store meets a hard refusal | The message names the condition and the remedy (fresh `BackupPath`); `-Action Verify` still audits the old store, and both restorers still restore it unchanged (G7) — nothing about reading a legacy store breaks, only writing to it |
| R2 | Deleting the tree-mode axis could take the compression-flip axis with it | Step 3 is its own commit; `StorageForm.Tests.ps1`'s SR-051 refcount suite (`:436`, `:539`) and the G4 sanitization suite both exercise the surviving axis |
| R3 | Election changes which physical form is stored for a mixed group ⇒ a stale `Compressed` on a sibling row restores 7z container bytes under the real name (the finding-B family) | TC-120; `Get-StoredFileForm` audit unchanged; `-Action Verify` covers the store |
| R4 | Moving `Save-SupersededData` after step 11 could miss bytes `Move-RemovedFilesToStaging` already relocated | The survival test reads the **final** map; the G9 rollback suite is the existing net; add an eviction-and-supersession-in-one-run case to TC-118's timeline |
| R5 | Deleting `PreserveFolderTree` touches ~45 test sites (G17) — a mechanical sweep that can silently *weaken* an assertion | Step 5 is its own commit; diff-review every deleted assertion; the coverage floor (78.1%) must not drop |
| R6 | The view writes outside both roots — new filesystem surface (a wrong `ViewPath` could write into user data) | TC-128 refusals; the writer only ever creates files under the resolved view root, from manifest `RelativePath`s that already passed the SR-055 portable-name guard |
| R7 | View generation becomes a per-run tax on a 500k-row library | `.viewstamp` skip; per-folder pages; measure, and if it earns a `PB-###` row, record it (perf budgets stay inert until a real row exists) |
| R8 | IF-001 (the HomeHub OCI contract, Experimental) names the config keys | Step 9 checks `docs/interfaces.md` + `interfaces.csv`; promoting IF-001 to Stable is the *next* action after this WP — D-1 was its stated blocker |

---

## 8. Verification (paste real output; never report a green you didn't run)

```powershell
pwsh scripts/check.ps1 -Tier Full -Gate G3
pwsh tests/Run-All.ps1 -Backend Subst -NonInteractive -EmitJUnit   # 2-mode matrix now
python scripts/trace.py --strict --require-verified --phase core,bash-v1,container-v1,kitbump-v6,ca-v1
pwsh scripts/gen_arch_map.ps1 -Flow Invoke-BackupSet               # regenerate; check.ps1 fails when stale
```

Plus bats + shellcheck for the restore twin and the container job for the
real-Docker end-to-end, exactly as the kit-bump G3 entry did. **A Windows host is
required for every one of these** (status.md session constraint).

---

## 9. Decisions taken (recorded under the 2026-08-25 standing directive; each open to veto)

The directive removed the ratification bar, so these are **driver calls that
ship** unless the human countermands. **Q1 and Q4 were answered by the human on
2026-08-25** and are recorded here as settled; the rest stand as driver calls.

1. **View shape (§3.6) — HUMAN APPROVED 2026-08-25.** A single `INDEX.html`
   over ~500k files is ~100 MB of markup and will not open in a browser.
   **`INDEX.tsv` always + per-folder HTML pages + root search under a
   50 000-row threshold** is approved ("Agreed, I did not think of file
   expansion") — the 2026-08-24 ruling's intent at library scale.
2. **`BrowseView` default when the key is absent: `off`.** No per-run cost is
   incurred by a config that never asked for a view; the shipped example config
   and the container example both set `"index"`, so a user following the docs
   gets browsability. (Reversible in one line if the production set should have
   it implicitly.)
3. **Stale CLIXML configs (§3.8): refuse by name.** CLIXML is exempt from the
   closed schema, so `PreserveFolderTree = $true` there would otherwise be
   **silently ignored** — a user believing they still have Mirror while the
   engine content-addresses everything. Silent divergence between what the
   config says and what the store does is the exact failure class this WP
   exists to kill, so it fails loudly (status 2) in both formats.
4. **Migration (§3.3) — HUMAN RULED 2026-08-25: moot.** "No storage exists
   currently here that must be maintained." The `Original → Hash` conversion is
   deleted rather than kept; a legacy-form store is refused with the
   fresh-`BackupPath` remedy, and `-Action Verify` still audits it. This removes
   the whole verify-before-name / rename-not-copy workstream and its two risks.
5. **Source-side manifest cache default stays OUT** (option-3 §6): an
   independent config change with no D-1/D-5 coupling. It remains an Open item
   in status.md so it is not lost.
6. **Kit revision decided at step 9, not now.** If any kit byte changes
   (comments describing Mirror, expected) both markers bump together to rev
   **7**; if nothing in the kit changes, it stays at 6 and the G3 entry says so.
7. **Reserved device names are IN** (§3.10) — per the ratification entry. Noted
   here only because it introduces a **new loud-failure class**: a Linux source
   holding `NUL.txt` starts failing the set until the name is fixed at source.

---

## 10. Out of scope (restated)

Two-registry normalization; `link` / FUSE / projected views; bash-v2; manifest
column retirement; `-RepairFromPruned`; the source-side cache default (Q5).
D-2 / D-3 / D-4 are already implemented at kit rev 6 and are not reopened here.
