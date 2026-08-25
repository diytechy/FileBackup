# Plan: kit-bump WP — restore verification, exit-code honesty, hidden/dot capture (kit revision 5 → 6)

**For the executing agent (Windows host, Opus).** This is a complete work
order: the pinned decisions, the code sites (enumerated, not "find them"), the
commit-ordered work items, the expanded test matrix, the registry deltas a
follow-up registry agent can execute mechanically, and the acceptance checklist
the human cross-checks. Every decision below was **ruled by the human on
2026-08-24** (docs/status.md audit entries of that date) — do **not** re-litigate
them; if the code contradicts a pinned fact, **stop and record it in
docs/status.md** rather than reinterpreting.

Authored 2026-08-24 on macOS (no `pwsh`/`bats`/`shellcheck` available), per the
bash-variant-plan precedent: the plan and the registry passes are drafted here;
**every green in this WP must come from a real Windows-host run.**

---

## 0. Ground rules (non-negotiable)

- Read [CLAUDE.md](../../CLAUDE.md), [AGENTS.md](../../AGENTS.md) §2–§4 and
  [docs/process.md](../process.md) §3–§6 before touching anything. Decision dial
  is **HIGH**: this WP is entirely on the data-integrity surface (restore
  correctness + source enumeration), so an **independent pre-gate reviewer is
  mandatory** (process.md §6) before declaring done.
- **Never report a green you didn't run.** Paste real Pester / Run-All / bats /
  `trace.py` output into the status.md entries. macOS or "should pass" is not
  evidence.
- **Constraints restated from AGENTS.md §3 — this WP breaks none of them:**
  - `MANIFEST.csv` stays a **9-column** contract in the documented order. No new
    column, no reordering, no sidecar schema change.
  - **`FileBackup.Common` never depends on `FileBackup.Engine`.** The verify
    helper D-2 needs is `Get-FileXxHash`, which already lives in Common.
  - The **restore kit stays self-contained**: `RECONSTRUCT.ps1` +
    `FileBackup.Common.psm1` + `System.IO.Hashing.dll` + `RECONSTRUCT.bat` +
    `reconstruct.sh` + `RECONSTRUCT.paths.json`, nothing new added to the bundle.
  - **`bash/reconstruct.sh` remains ONE self-contained file** — no `source`d
    libraries, no new runtime dependency (the verify step reuses the existing
    `hash_file` wrapper).
  - **Automation-safe:** anything interactive gets a `-NonInteractive` path that
    fails loudly with a non-zero exit (this WP *adds* one — see W5).
  - **No engine storage-format change.** Mirror stays Mirror, hash-addressing
    stays hash-addressing, `Save-SupersededData` and `Invoke-BackupFileGroup`
    are **not touched**. That is the option-3 WP
    ([option3-content-addressed-storage-plan.md](option3-content-addressed-storage-plan.md)).
- Commit early and often — one small green commit per work item; end with a
  clean tree and status.md entries per gate.

## 1. Why / what this WP is

The 2026-08-24 HomeHub bench defect review
([defect-review-2026-08-24-mirror-dedup.md](../defect-review-2026-08-24-mirror-dedup.md))
found five defects, all confirmed by a three-agent verification with
reproductions. **D-1 and D-5 are storage-design defects and belong to the
option-3 WP.** This WP takes the other three plus the two approved kit nits —
everything that lives in the **restore kit and the enumeration surface** and is
needed *regardless of the storage design*:

| Defect | One line | Human ruling 2026-08-24 |
|---|---|---|
| **D-2** | Both restorers expand/copy a resolvable `DataPath` with **no hash check** — wrong payload, same-length bit-flip, even a truncation restore with exit 0. | **GO** ("Sounds good") |
| **D-3** | One unrelated unexpandable `.7z` anywhere in the pool flips "your bytes are gone" (exit 1) into "fix this host" (exit 4). | **GO** ("Agreed") |
| **D-4** | **No `Get-ChildItem` anywhere** in Engine/Common/Reconstruct uses `-Force`: hidden and dot-prefixed files are never backed up, hidden/dot pool files are invisible to the restore scan, and the twin restorers disagree (bash `find` never skipped them). | **RULED: hidden AND dot files are backed up by default** ("Yes ideally hidden and dot files are backed up") |
| **restorer TargetRoot parity** | `Reconstruct.ps1` falls back to `Read-Host` when `-TargetRoot` is omitted — a scripted restore hangs; `reconstruct.sh` requires `--target-root` and dies loudly. | **APPROVED: align** ("yes it would be good to align the behavior") |
| **no-7z double record** (parked nit) | One unreadable `.7z` candidate under no-7-Zip records `CandidateError` **and** `DependencyMissing`. | Fold in here |
| **kit revision** | Both restorers change behavior ⇒ the marker must be bumped **together**, README + AGENTS.md §3 updated, `-RefreshKits` named as the upgrade path. | 5 → **6** |

Both restorers ship in the kit (`New-ReconstructScript` copies `Reconstruct.ps1`
*and* `bash/reconstruct.sh` verbatim), so every fix here reaches an existing
store only through `-Action Verify -RefreshKits`.

## 2. Pinned contract & decisions

Read the authoritative code before implementing, but these are pinned:

| Fact | Value | Authority |
|---|---|---|
| `xxH2Hash` semantics | the **ORIGINAL CONTENT** hash (uncompressed payload), 32-char uppercase hex, XXH128 big-endian — so a post-write hash of the restored file is directly comparable | verification 2026-08-24; SR-002 |
| Verify comparison | `Length` **and** `xxH2Hash` both must match; length first (cheap) | this plan |
| Fall-through on mismatch | delete the bad destination file, then run the **existing** `(hash,length)` pool recovery (`Find-DataFileByHash` / `find_by_hash`) exactly as a blank row does; re-verify the result; **at most one recovery attempt per row** | D-2 ruling |
| No exclusion state needed | the pool locator hashes every candidate, so a wrong-bytes file cannot be returned as a match — no `-ExcludePath` parameter, no new state | code reading, `Reconstruct.ps1:251-322` |
| Unrecoverable after fall-through | counts into the **SR-029 unrestored accounting**, non-zero exit, one log line per row | D-2 ruling |
| Exit-code table | unchanged: 0 complete · 1 content · 2 usage/precondition · 3 witness · 4 host; precedence **2 > 3 > 4 > 1**. Normative copy: README "Restore exit codes" | SR-040 |
| D-3 precedence | in the **locators only**: `ContentMissing` outranks a candidate-expansion failure. Restore-loop `CandidateError` (the row's OWN file failed to expand/copy — `Reconstruct.ps1:679,687`, `reconstruct.sh:689,695`) stays a **host** cause, unchanged | D-3 ruling + code reading |
| D-4 shape | `-Force` on **every** `Get-ChildItem` in Engine/Common/Reconstruct. **No new config knob in v1.** `ExcludeFolder` remains the deliberate-exclusion path | D-4 design-impact entry, status.md |
| D-4 non-goals | reparse-point / symlink traversal semantics are **NOT changed** by `-Force` — existing behavior stands; **pin it as intent** with a comment + test, do not "improve" it | D-4 design-impact entry §5 |
| Kit revision | `# KitRevision: 5` → `6` in **BOTH** `Reconstruct.ps1:52` and `bash/reconstruct.sh:57`; bump together, always | AGENTS.md §3 |
| Storage format | untouched. `Save-SupersededData`, `Invoke-BackupFileGroup`, `Sync-BackupStorageLayout`, `Get-HashSizeFileName` are **out of bounds** | option-3 WP fence |
| Test matrix | this WP runs on the **current 4-mode matrix** (`Mirror`, `Mirror+Compress`, `HashAddressed`, `HashAddressed+Compress`) | sequencing §8 |

### 2.1 Two design refinements the executing agent must implement as written

Both fall inside the rulings; both are recorded here because a literal reading of
the ruling would produce worse code.

**(a) D-3 is a *reclassification*, not just a list reorder.** The locator's
precedence loop is `DependencyMissing → StorageUnreadable → CandidateError`
(`Reconstruct.ps1:327`; `reconstruct.sh:302-305`) with `ContentMissing` as the
fallback. Simply inserting `ContentMissing` above `CandidateError` makes
`CandidateError` **dead code** in the locator — because `ContentMissing` is
always available. So implement it honestly:

- The locator **never returns `CandidateError`**. Its return set becomes
  `Found | DependencyMissing | StorageUnreadable | ContentMissing`.
- A candidate that **failed to expand** is data damage, not a host condition — a
  retry on this host cannot change the outcome. Its detail is **appended to the
  `ContentMissing` detail** (`"… ; N candidate(s) could not be expanded: <first>"`),
  so the operator still sees it and exit 1 is correct.
- A candidate that **could not be read at all** (`Get-FileXxHash` threw — I/O
  error, lock, permission) *is* a host condition: record it as
  **`StorageUnreadable`**, preserving today's exit-4 signal. (`Reconstruct.ps1`
  has three such sites at `:273,:305,:318`; `reconstruct.sh` currently has no
  read-error arm — leave that asymmetry alone, note it in the LLR.)
- Rationale to put in the code comment: *the locator is only ever called when
  the row's own file is blank or missing, so no candidate it inspects is the
  row's own file; an unexpandable archive there proves nothing about this host.*

**(b) The no-7-Zip double record is fixed at the same site.** In
`Reconstruct.ps1:296-311`, when the raw-bytes test **throws**, record the read
failure once (as `StorageUnreadable` per (a)) and `continue` — 7-Zip could not
have helped read a file that cannot be read. Only a candidate whose raw bytes
were read successfully and did **not** match still records `DependencyMissing`.
Mirror the resulting behavior in `reconstruct.sh:255-266`.

## 3. Code sites you are changing (enumerated)

### 3.1 D-2 — verify-after-write (both restorers)

| File | Site | Change |
|---|---|---|
| `Reconstruct.ps1` | restore loop `:673-691` (the `if ($needsExpand) { Expand… } else { Copy-Item… }` block) | after a successful expand/copy, hash the **destination** and compare `(Length, xxH2Hash)`; on mismatch delete the destination, log, and re-enter the `(hash,length)` recovery path once; verify again; on final failure `Add-Unrestored` with the new `ContentMismatch` cause |
| `bash/reconstruct.sh` | restore loop `:645-698` (`sevenzip_to_file` / `cp -f` arms) | the identical sequence with `hash_file "$dest"` + `stat -c '%s'`; unrestored classification via the existing `unrestored` / `unrestored_host` arrays |

Implementation notes (both):

- Verify **every** restored row, including hash-recovered ones. The locator
  proved the *pool file*; it did not prove the *destination write* (a truncated
  write to a full target, a 7-Zip extraction that produced a different file).
  Cost is one extra read of the restored bytes — see §6 open question 3.
- Structure the loop so there is exactly one verify implementation and one
  "restore this row from `$srcFull`" implementation, called at most twice.
  Recommended shape: extract a small `Restore-OneRow`/`restore_one` helper
  returning `ok | mismatch | <host cause>`; the loop calls it, and on `mismatch`
  runs the recovery and calls it once more. Entry points orchestrate
  (CLAUDE.md), so keep the loop readable.
- New unrestored cause **`ContentMismatch`**, classified **content-class**
  (exit 1) — the bytes in the store do not reproduce the index and no pool copy
  does either. Do **not** add it to `$hostCauses` (`Reconstruct.ps1:698`) or to
  the bash `DependencyMissing|StorageUnreadable|CandidateError` case arm
  (`:636`). A *target-side* write failure surfaces as an exception from
  `Copy-Item`/`cp` and stays `CandidateError`/host, unchanged.
- Log one line per event, both restorers, same wording:
  `WARN: [ContentMismatch] '<rel>' — restored bytes do not match the manifest
  (expected <hash>/<len>, got <hash>/<len>); attempting pool recovery.`
- **0-byte rows:** `Length = 0` still hashes; do not special-case.

### 3.2 D-3 + no-7z nit — the locators

| File | Site |
|---|---|
| `Reconstruct.ps1` | `Find-DataFileByHash`: the `CandidateError` records at `:273`, `:305`, `:309`, `:318`; the no-7z branch `:296-311`; the precedence loop `:326-337`; the comment-based help's cause list at `:222-232` |
| `bash/reconstruct.sh` | `find_by_hash`: `host_candidate` assignment `:290-292`, the no-7z arm `:255-266`, the precedence block `:300-306`, the header comment `:215-243` |
| `Reconstruct.ps1` | the `.NOTES` exit-code block `:24-46` — the code-4 sentence lists "extraction/copy I/O error"; keep it (the loop still raises it) but note the locator no longer does |

### 3.3 D-4 — `-Force` on every enumeration

**All nine `Get-ChildItem` calls** in Engine/Common/Reconstruct, verified by grep
at HEAD. Each gets `-Force`; each needs the one-line *why* comment:

| # | Site | What it scans | Why `-Force` matters |
|---|---|---|---|
| 1 | `Modules/FileBackup.Engine.psm1:121` (`Get-DataFile`) | recursive data-file walk under a root (source walk and pool walks) | **the D-4 headline**: hidden/dot source files were never backed up; also skips hidden *directories* entirely under `-Recurse` |
| 2 | `Modules/FileBackup.Engine.psm1:438` (`Update-SourceManifest`, external-cache branch) | source tree when `ManifestFolderPath` is external | same, on the branch that bypasses `Get-DataFile` |
| 3 | `Modules/FileBackup.Engine.psm1:892` (`Optimize-ChangeFolders`) | `-Directory` under the change root | a hidden `Snapshot_*` folder is invisible to sanitization |
| 4 | `Modules/FileBackup.Engine.psm1:963` (`Get-PoolSnapshotFolder`) | `-Directory` under the change root | the **pool** would silently omit a hidden snapshot — recovery/prune both consume this |
| 5 | `Modules/FileBackup.Engine.psm1:1090` (`Get-SnapshotPrunePlan`) | `PhysicalBytes` accounting over the target folder | hidden files are deleted with the folder but not counted — the reclaim figure lies |
| 6 | `Modules/FileBackup.Engine.psm1:2202` (`Invoke-PruneEntrySweep`) | `*.fbprune.tmp` residue | hidden residue is never swept |
| 7 | `Modules/FileBackup.Common.psm1:470` (`Expand-FileWithSevenZip`) | picks the single extracted file out of the temp dir | 7-Zip can restore attributes: a hidden payload makes this return `$null` and throw "No file extracted" |
| 8 | `Reconstruct.ps1:251` (`Find-DataFileByHash`) | the **restore pool scan** | hash-addressed short names **can begin with a dot** (`.nArDBFwE!yq[…#..bin` exists in the committed fixtures — the exact shape that broke the CI artifact upload on 2026-08-23); a hidden pool file is unrecoverable-by-hash today |
| 9 | `Reconstruct.ps1:554` | snapshot-folder enumeration for the search pool | a hidden snapshot folder drops out of the pool |

Also:

- **Anti-regression guard (required):** add a Pester test that greps
  `Modules/*.psm1`, `Reconstruct.ps1`, `FileBackup.ps1` for `Get-ChildItem`
  occurrences lacking `-Force` and fails naming the file/line. This is the only
  cheap defense against site #10 arriving later. (Model it on the existing
  static checks in `tests/Unit/Coverage.Tests.ps1`.)
- **bash side: zero-line change** for D-4 — `find "$folder" -type f` never
  skipped dot-files. Add a comment at `reconstruct.sh:298` pinning that as
  *intent*, and pin `find` **without `-L`** (link-immunity) as intent too, per
  the option-3 design record §3.
- **Do not** add an `IncludeHidden` knob, a per-set policy, or hidden-file
  skip accounting. The only remaining skip class is SR-055 portable-name
  refusals, which already fail loudly.
- **README note (required):** `desktop.ini`, `Thumbs.db`, `.DS_Store`,
  `.git/`, `$RECYCLE.BIN` and System-attribute files now enter backups by
  default; point at `ExcludeFolder` for deliberate exclusion.

### 3.4 Restorer TargetRoot parity

`Reconstruct.ps1:384-386` — the `Read-Host` fallback. Add a `[switch]$NonInteractive`
parameter (documented in the `param()` block comments like `-ExitCode` and
`-RequireWitness` are) and:

```
if (-not $TargetRoot) {
    if ($NonInteractive -or [System.Console]::IsInputRedirected) {
        Exit-Reconstruct -Code $EXIT_PRECONDITION -Message <usage block>
    }
    $TargetRoot = Read-Host 'Enter target folder to reconstruct into'
}
```

- Exit code **2** (usage/precondition), matching `reconstruct.sh:455`
  (`--target-root is required` after `usage`).
- Write a `Show-ReconstructUsage` helper whose text mirrors
  `reconstruct.sh:414-425` parameter-for-parameter, so the twins document the
  same surface.
- The interactive prompt is **kept** for hand use (the ruling says align the
  *non-interactive* behavior, not delete the prompt).
- `RECONSTRUCT.bat` passes `%*`, so `-NonInteractive` reaches the script with no
  bat change; confirm and note it.
- The `IsInputRedirected` arm is defense-in-depth for a scheduled run that
  forgot the switch. Verify it is **false** for the in-process Pester callers
  (they always pass `-TargetRoot`, so the branch is unreachable there) — if any
  harness call hits it, drop the heuristic and keep the explicit switch only.

### 3.5 Kit revision 6

- `Reconstruct.ps1:52` and `bash/reconstruct.sh:57`: `# KitRevision: 6` plus one
  paragraph in each header describing revision 6 (verify-after-write; locator
  no longer misreports a bad pool candidate as a host problem; `-Force` pool
  scan; `-NonInteractive` guard), in the style of the revision 2–5 paragraphs.
- `AGENTS.md` §3, the "A snapshot keeps the restore kit it was written with"
  bullet (`AGENTS.md:306-326`): add revision 6. Also update the §3 "Known open
  defects" preamble box (`AGENTS.md:202-211`) — D-2/D-3/D-4 move from *open* to
  *fixed in revision 6*; **leave the D-1/D-5 forward-pointer intact** (that box
  is the option-3 WP's).
- `README.md:280-307` ("kits before revision N…"): add the revision-6 paragraph
  — kits before 6 restore whatever the `DataPath` holds without checking it,
  and cannot see hidden/dot pool files — and name
  `-Action Verify -RefreshKits` as the upgrade path for existing snapshots.
- `Get-BackupKitRevision` (`Engine.psm1:1583`) needs **no** change (it parses the
  marker). Confirm nothing hardcodes `5`; the only hardcoded revisions found are
  `tests/Unit/StorageForm.Tests.ps1:894` (`-BeGreaterOrEqual 2`, fine) and
  `tests/Unit/Coverage.Tests.ps1:2654` (rewrites the marker to `1`, fine).
- The committed bats fixtures (`tests/fixtures/bash-restore/**`) do **not**
  contain kit scripts — no fixture churn from the bump. New fixtures for the new
  cases are a separate work item (W7).

## 4. Work order (suggested commits — one green commit each)

1. **G1/G2 registry pass** (registry CSVs only, no code): mint/amend per §5;
   `python scripts/trace.py --strict` clean, `--require-verified` still clean
   for shipped phases (new rows are `Draft`/`Planned`). status.md G1+G2 entries.
   *May be executed by a separate registry agent before implementation starts.*
2. **D-3 + no-7z nit** — both locators, per §2.1 and §3.2. Smallest, highest
   confidence, no behavior change on the happy path. Tests: TC-111/TC-112.
3. **D-2 PowerShell** — `Reconstruct.ps1` verify-after-write (§3.1). Tests:
   TC-108.
4. **D-2 bash** — `reconstruct.sh` verify-after-write, byte-for-byte equivalent
   semantics. Tests: TC-109. Keep the two loops readable side by side.
5. **TargetRoot parity** (§3.4). Tests: TC-115.
6. **D-4 `-Force` sweep** — all nine sites + the anti-regression guard + bash
   intent comments + README note (§3.3). Tests: TC-113/TC-114. This is the
   commit most likely to move existing suite results (new files now enter
   backups): re-run the **full** Run-All before committing.
7. **Fixtures + test battery** — new bats fixtures via
   `scripts/gen_bash_fixtures.ps1` (regenerated on Windows, committed), the
   expanded matrix of §6, the orphan second-pass tooling, the de-vacuumed G2.8.
8. **Kit revision 6 + docs** (§3.5) — bump both markers, README, AGENTS.md §3.
9. **Registry closure** — flip the new SR/LLR/TC rows to
   `Verified`/`Implemented`/`Pass` **only** with real output pasted; status.md
   G3 entry.
10. **Independent review** — fresh-context reviewer on the restore surface
    (adversarial: mismatch during expand vs copy, mismatch on a hash-recovered
    row, a pool whose only copy is also corrupt, exit-code precedence when a
    mismatch and a genuine host failure coexist in one run, hidden files at
    every one of the nine sites, `-NonInteractive` interactions). Record the
    verdict before declaring done.

## 5. Registry deltas (for the registry agent — execute mechanically)

Conventions from `docs/requirements/*.csv` and `docs/test/test-cases.csv`:
SR columns `SR-ID,Title,SN-Refs,Requirement,Rationale,AcceptanceCriteria,Permutations,Priority,Verification,Status,Phase`;
LLR `LLR-ID,SR-Refs,Title,Module,CodeSymbol,Detail,TestRefs,Status`;
TC `TC-ID,Verifies,Level,Method,Tier,Parameters,Expected,Automated,Status`.
Next free ids at HEAD: **SN-033, SR-056, LLR-056, TC-108**. New rows start
`Draft` / `Planned` / (TC) `Planned`; `Phase` stays **empty** (core).

### 5.1 Mints

| Id | Shape |
|---|---|
| **SN-033** *(optional — see open question 1)* | "A restore that reports success has **proved** the bytes it wrote against the index." Evidence: D-2, reproduced in both restorers 2026-08-24 (wrong payload, same-length bit-flip and truncation all exit 0). Priority M. Acceptance: a store whose data file has been altered restores byte-exact from a surviving pool copy, or fails non-zero naming the row — never exit 0 with wrong bytes. *If the human prefers no new SN, point SR-056 at `SN-005;SN-006;SN-026` instead.* |
| **SR-056** — *Restore verifies the bytes it wrote* | SN-Refs `SN-033;SN-005;SN-026`. Requirement: after restoring any manifest row — expanded or copied, resolved through its own `DataPath` or hash-recovered — **both** restorers shall hash the written file and compare `(Length, xxH2Hash)` against the row; on disagreement the written file shall be deleted, the `(hash,length)` pool recovery attempted once, and the result verified again; a row that cannot be verified shall be counted into the SR-029 unrestored accounting as the content-class cause `ContentMismatch` (exit 1), never reported as success. Verification `Test`, Priority `M`. Permutations: `damage=set{none,wrong-payload,same-length-bitflip,truncated}; recoverable=set{pool-has-good-copy,pool-has-none}; resolution=set{own-datapath,hash-recovered}; form=set{raw,archive}; restorer=set{powershell,bash}; origin=set{backup-root,snapshot}@pairwise` |
| **SR-057** — *Hidden and dot-prefixed files are captured and located* | SN-Refs `SN-001;SN-005;SN-031`. Requirement: every filesystem enumeration in the engine, the shared module and the Windows restorer shall include hidden, system and dot-prefixed entries (files **and** directories) — source walks, the restore pool scan, the snapshot enumerations, the prune residue sweep and the prune byte accounting alike — so that no source file is silently omitted and no pool file is invisible to `(hash,length)` recovery. Deliberate exclusion remains `ExcludeFolder`; **no hidden-file configuration knob exists**. Reparse-point/symlink traversal semantics are unchanged by this requirement. Priority `M`. Permutations: `class=set{dot-file,nested-dot-directory,windows-hidden-file,windows-hidden-directory,system-attribute,dot-named-pool-file,hidden-pool-file}; site=set{source-walk,external-cache-walk,restore-pool-scan,snapshot-enumeration,prune-residue,physical-bytes,7z-extract-pick}; mode=set{Mirror,Mirror+Compress,HashAddressed,HashAddressed+Compress}@pairwise` |
| **LLR-056** | SR-Refs `SR-056`. Module `Reconstruct.ps1;bash/reconstruct.sh`. CodeSymbol `Restore-OneRow;restore_one` (or the loop names you settle on). Detail: the single verify implementation, the one-retry rule, the `ContentMismatch` content-class classification, and the explicit note that no exclusion state is needed because the locator hashes every candidate. TestRefs `TC-108;TC-109;TC-110`. |
| **LLR-057** | SR-Refs `SR-057`. Module `Modules/FileBackup.Engine.psm1;Modules/FileBackup.Common.psm1;Reconstruct.ps1`. CodeSymbol `Get-DataFile;Update-SourceManifest;Optimize-ChangeFolders;Get-PoolSnapshotFolder;Get-SnapshotPrunePlan;Invoke-PruneEntrySweep;Expand-FileWithSevenZip;Find-DataFileByHash`. Detail: the nine `-Force` sites **listed with the reason each one matters** (copy §3.3's table), the bash `find` zero-diff note, and the static anti-regression guard. TestRefs `TC-113;TC-114`. |

### 5.2 Amendments (edit in place, keep the id, note the amendment date in the text — the SR-046/SR-054 rows show the house style)

| Id | Amendment |
|---|---|
| **SR-040** (shared restore exit-code contract) | The **locators** shall never report a candidate-expansion failure as a host cause: an archive candidate in the pool that does not yield the row's payload is data damage, so the outcome is `ContentMissing` (1) with the failed candidates named in the detail. A candidate that cannot be **read** is a host condition and shall be reported as `StorageUnreadable` (4). A candidate that could not be read shall record **one** cause, not `CandidateError` + `DependencyMissing`. Restore-loop failures on a row's **own** file (extraction/copy I/O) remain host-class (4), unchanged. Add `ContentMismatch` to the content-class cause list (SR-056). Acceptance: one unrelated garbage `.7z` in the pool yields **exit 1**, not 4. |
| **SR-016** (non-interactive automation safety) | Extend to the restore entry point: `Reconstruct.ps1` invoked without `-TargetRoot` under `-NonInteractive` (or with input redirected) shall print usage and exit **2** rather than prompting, matching `reconstruct.sh`'s required `--target-root`. |
| **SR-029** | Cross-reference `ContentMismatch` as an unrestored cause. |
| **SR-001** | Rationale/acceptance note: the recursive walk includes hidden, system and dot-prefixed entries (SR-057) — the 2026-08-24 D-4 finding. |
| **SR-007** / **AGENTS.md §3** | Kit revision **6**; both restorers bumped together. |
| **SR-055** *(only if open question 2 is answered "yes")* | Extend the portable-name refusal to Windows **reserved device names** (`CON PRN AUX NUL COM1-9 LPT1-9`, case-insensitive, with or without an extension) as a per-component rule. |
| **LLR-040 / LLR-050** | Reflect the locator's reduced return set and the single-record no-7z path. |
| **LLR-016** | Add the `Reconstruct.ps1` `-NonInteractive` guard + `Show-ReconstructUsage`. |
| **LLR-055** | Reserved-name component rule, if adopted. |
| **TC-019** | **De-vacuum the G2.8 assertion** — see §6.4 and open question 4. |

### 5.3 New TC rows

| TC | Verifies | Level / Tier | Substance |
|---|---|---|---|
| **TC-108** | SR-056;LLR-056 | Integration / Smoke (Pester) | PowerShell restorer × damage matrix (§6.1). |
| **TC-109** | SR-056;LLR-056 | Integration / Smoke (bats) | bash twin of TC-108 against the same fixture shapes. |
| **TC-110** | SR-056;SR-031 | Integration / Full (interop) | Windows-made damaged store restored by **both** restorers in the cross-artifact CI job; identical exit codes and identical restored bytes. |
| **TC-111** | SR-040;LLR-040 | Integration / Smoke (Pester) | unrelated unexpandable `.7z` ⇒ `ContentMissing`/exit **1**; unreadable candidate ⇒ `StorageUnreadable`/exit 4; no-7-Zip unreadable candidate ⇒ exactly **one** recorded cause; the row's own archive failing to expand still ⇒ exit 4. |
| **TC-112** | SR-040;SR-031 | Integration / Smoke (bats) | bash twin of TC-111 (extend `tests/bash/exit_codes.bats`). |
| **TC-113** | SR-057;LLR-057 | Integration / Full | end-to-end hidden/dot capture across all 4 modes: dot file at root, **nested dot-directory** with content, Windows Hidden file, Windows Hidden directory, System-attribute file — all appear in `MANIFEST.csv` and restore byte-exact; a hidden file's `Hidden` attribute is *not* required to survive the restore (state the expectation either way — see open question 5). |
| **TC-114** | SR-057;LLR-057 | Unit / Smoke (Pester) | the static "no `Get-ChildItem` without `-Force`" guard; a **dot-named / hidden pool data file** recovered by `(hash,length)` in `Find-DataFileByHash`; a hidden extracted payload picked up by `Expand-FileWithSevenZip`; a hidden `Snapshot_*` folder present in `Get-PoolSnapshotFolder` and counted by `Get-SnapshotPrunePlan`'s `PhysicalBytes`. |
| **TC-115** | SR-016;LLR-016 | Integration / Smoke | `Reconstruct.ps1 -NonInteractive` with no `-TargetRoot` ⇒ exit 2 + usage, **does not block**; with `-TargetRoot` ⇒ unchanged; `reconstruct.sh` with no `--target-root` ⇒ exit 2 + usage (existing behavior, pinned as the parity twin). |
| **TC-116** | SR-053;SR-054 | Integration / Full | **orphan second pass as tooling** (§6.3): after each timeline, every blank-`DataPath` row's `(hash,length)` is present among the hashes *actually verified by reading bytes* this cycle. |
| **TC-117** | SR-055;LLR-055 | Unit / Smoke | reserved device names refused (only if adopted). |

## 6. Test scope — the approved battery, expanded

**Floor** (human-approved import list, all six items) → items 6.1–6.6 below.
**Expansion** (human: "expand it applicable to cover a larger test area") →
the permutation matrices, driven with the repo's grammar
(`python scripts/gen_cases.py --spec "<the Permutations cell>"`, pairwise
default at ≥3 dimensions). Levels: **Pester** = `tests/Unit/*.Tests.ps1`
(unit + integration-level Describes, the WP7/WP8 precedent), **suite** =
`tests/Suites/G*.ps1` (auto-swept across all 4 modes by `Run-All.ps1`),
**bats** = `tests/bash/*.bats` (WSL/CI Linux), **interop** = the cross-artifact
CI job (Windows makes the store, Linux restores it).

### 6.1 Wrong bytes at `DataPath`, both restorers (floor item 3 — the D-2 core)

Spec: `damage=set{wrong-payload,same-length-bitflip,truncated}; recoverable=set{pool-has-good-copy,pool-has-none}; resolution=set{own-datapath,hash-recovered}; form=set{raw,archive}; restorer=set{powershell,bash}; origin=set{backup-root,snapshot}@pairwise`

- **Recoverable** ⇒ the restore is **silently healed** from the pool, tree
  byte-exact, **exit 0**, and the log carries the `ContentMismatch` warning
  (assert the log line — a silent heal that leaves no trace is not acceptable).
- **Unrecoverable** ⇒ **exit 1**, the row named, every other row still restored
  (SR-029 salvage semantics).
- `truncated` must be caught even though `Length` alone would catch it — assert
  both the length check and the hash check fire (use a same-length bit-flip for
  the hash-only arm).
- The `archive` arm needs a `.7z` whose **payload** is wrong (repack different
  bytes), not a corrupt container — a corrupt container already exits 4.
- Placement: Pester TC-108 (PS), bats TC-109, interop TC-110.

### 6.2 Unrelated bad `.7z` ⇒ ContentMissing (floor item 4 — D-3)

Spec: `pool-noise=set{unexpandable-7z,unreadable-candidate,none}; row=set{blank-datapath,named-file-missing}; sevenzip=set{present,absent}; restorer=set{powershell,bash}@pairwise`
Placement: TC-111 (Pester), TC-112 (bats, extend `exit_codes.bats`).
Pin the **precedence interaction**: a run containing *both* a genuinely
unrecoverable row and a real host failure still exits **4** (4 > 1 survives).

### 6.3 Orphan-detection second pass, as tooling (floor item 2 — the assertion that caught D-1)

Port the HomeHub drill assertion
(`scripts/verify/library-permutation-drill.sh`, offered by the human for pull if
the original is needed):

> after a timeline, for **every** blank-`DataPath` row in every manifest (backup
> root **and** every snapshot), its `(xxH2Hash, Length)` must appear among the
> hashes **actually verified this cycle by reading bytes** — not merely
> `Test-Path`-resolved.

- Implement as reusable harness tooling: `tests/Common/PoolAudit.ps1` exporting
  `Assert-BlankRowsBackedByVerifiedHashes -BackupRoot -ChangeRoot`, dot-sourced
  by `Run-All.ps1` and called at the end of G2, G3 and G9 (and G9Prune).
- It must build its verified-hash set by **hashing pool files** (expanding `.7z`
  candidates), the same way `Find-DataFileByHash` proves a match — that is
  precisely what makes it stronger than `-Action Verify` and than SR-054's
  `Test-PoolResolves`, which resolves blank rows through the in-memory content
  index.
- Under the current 4-mode matrix this assertion is expected to **FAIL on Mirror
  in the D-1 shape** (owner-edit) — that is the point. Wire it so the D-1 shapes
  are exercised by the **option-3 WP**; here it runs over the existing
  timelines, where it must pass. See §8.
- TC-116.

### 6.4 The vacuous G2.8 assertion (floor item 6)

`tests/Suites/G2-Incremental.ps1:56-59` asserts
`(… DataPath -Unique).Count -le 2` for two identical files — which passes under
D-5 (Mirror stores both copies) and would pass even if dedup were removed
entirely. Replace with a **mode-aware, exact** assertion:

- `HashAddressed` (± Compress): exactly **one** distinct non-blank `DataPath`
  across the two rows, **and** exactly **one** physical pool file whose bytes
  hash to the shared content.
- `Mirror` (± Compress): assert the **current, documented truth** — two
  DataPaths, two physical copies — with an inline comment naming **D-5** and the
  option-3 WP as the fix. This turns a vacuous assertion into a change-detector:
  when option-3 lands, Mirror is gone and this arm is deleted rather than
  silently passing.
- Amend **TC-019** to state both arms.
- ⚠️ Do **not** write `-eq 1` unconditionally: it fails on Mirror **today** by
  design (D-5), and this WP is explicitly forbidden from touching the storage
  path. See open question 4.

### 6.5 Hidden / dot everywhere (floor item 5, expanded)

Spec: `class=set{dot-file,nested-dot-directory,windows-hidden-file,windows-hidden-directory,system-attribute,dot-named-pool-file,hidden-pool-file}; site=set{source-walk,external-cache-walk,restore-pool-scan,snapshot-enumeration,prune-residue,physical-bytes,7z-extract-pick}; mode=4-modes@pairwise`

- **Nested dot-directories** matter beyond the file case: `-Recurse` without
  `-Force` does not descend into a hidden directory at all, so a whole subtree
  was missing. Use `.config/nested/deep.txt`.
- **Hidden pool data files** are the CI-breaking shape: a HashAddressed short
  name beginning with a dot (present in the committed fixtures), plus a pool
  file with the Windows Hidden attribute set — both must be found by
  `(hash,length)` recovery (TC-114) and both must survive a prune's accounting.
- Suite-level end-to-end (TC-113) runs across **all four modes** via `Run-All`;
  the site-specific probes are Pester (TC-114).
- **bats**: add one case proving the Linux restorer already finds a dot-named
  pool file (regression pin — it does today; the value is that it stays true).

### 6.6 Owner-edit across all 4 storage modes (floor item 1)

This is the **D-1 shape**. Under the current code it **fails on Mirror by
design** (that is the confirmed data-loss defect), and the fix is the option-3
WP, not this one. Therefore:

- **Write the test here** as harness tooling + a suite case, but land it in the
  option-3 WP's scope as the assertion that must flip green — or land it here
  **restricted to HashAddressed** (proven immune by repro) so it protects the
  surviving mode immediately.
- **Recommendation:** land the HashAddressed arms here (they pass today, so they
  are a regression guard), and record the Mirror arms as `Planned` TC parameters
  owned by the option-3 WP. Do **not** commit a knowingly-red Mirror test to
  this WP's green bar.
- Same treatment for the recorded permutations that are D-1/D-5 shapes:
  *edit-the-borrower*, *multiple borrowers*, *same-run vs prior-run duplicates*,
  *owner-deleted-while-borrower-lives* → **option-3 WP**.
  *Nested dot-directories*, *Windows Hidden*, *same-length corruption*,
  *all-four-modes owner-edit (HashAddressed arms)* → **this WP**.

### 6.7 Non-interactive parity

Spec: `invocation=set{interactive-no-arg,noninteractive-no-arg,arg-given}; restorer=set{powershell,bash}`
(TC-115). The `interactive-no-arg` arm is **manual/self-hosted** — do not try to
automate a `Read-Host`; assert instead that the prompt branch is unreachable
under `-NonInteractive`.

## 7. Windows-host execution preamble (run these FIRST, paste the output)

```powershell
# 0. clean tree on the WP branch
git status --porcelain          # must be empty before you start

# 1. baseline the harness BEFORE any edit — this is the number every later
#    claim is measured against
pwsh scripts/check.ps1 -Tier Smoke
pwsh scripts/check.ps1 -Tier Full          # lint + trace + docs + map + Pester + Subst integration
pwsh tests/Run-All.ps1 -Backend Subst -NonInteractive -EmitJUnit

# 2. traceability baseline (must be 0/0/0 with one phase-deferred row: SR-033)
python scripts/trace.py --strict --require-verified --phase core,bash-v1,container-v1
```

```bash
# 3. Linux half, under WSL (Git Bash is NOT an acceptance environment)
shellcheck bash/reconstruct.sh
bats tests/bash/
```

**Expected baseline at HEAD** (2026-08-23 evidence, status.md): Pester unit
**341/341**, integration **372 pass / 0 fail / 4 skip**, bats **56/56**,
bash-interop **12/12**, `check.ps1 -Gate G3` all steps pass, `trace.py` →
`SN=32 SR=55 LLR=54 TC=106, 0 orphans / 0 integrity / 0 status-findings /
1 phase-deferred`. **If the baseline does not reproduce, stop and record it** —
do not build on an unknown floor.

Per-commit floor: `pwsh scripts/check.ps1 -Tier Smoke` on every commit,
`-Tier Full` on every commit touching `Modules/`, `Reconstruct.ps1` or
`bash/reconstruct.sh`, and the bats suite on every commit touching
`bash/reconstruct.sh`.

## 8. Sequencing vs. the option-3 WP

- **This WP runs first, on the current 4-mode matrix**, and is independent: it
  touches the restore kit and the enumeration surface only. The option-3 WP
  rewrites the storage path (`Save-SupersededData`, `Invoke-BackupFileGroup`,
  `Sync-BackupStorageLayout`, config v2) and the test matrix.
- **Which of these tests survive the option-3 matrix halving** (4 modes →
  ±Compress):
  - **Survive unchanged** (storage-agnostic, restore-side): TC-108, TC-109,
    TC-110, TC-111, TC-112, TC-115 — they parameterize on damage class, pool
    noise and restorer, not on layout.
  - **Survive with the mode axis collapsed** (4 arms → 2): TC-113 (hidden/dot
    end-to-end), TC-116 (orphan second pass). No content change, half the runs.
  - **Partly deleted**: TC-019's **Mirror arm** (§6.4) dies with Mirror; its
    HashAddressed arm becomes *the* assertion. Any "hidden file in a Mirror
    tree" arm of TC-113 collapses into the pool-file arms.
  - **Strengthened by option-3**: TC-114's dot-named pool file becomes the
    *only* pool shape (every data file is hash-named), so `-Force` on
    `Find-DataFileByHash` moves from "important" to "load-bearing".
- **No shared files are edited by both WPs** except `README.md`, `AGENTS.md` §3
  and `docs/status.md`. Land this WP first to keep those merges trivial.
- The option-3 plan's §6 table already claims the **manifest row-order** nit and
  the **O(N²) unreferenced-file scan** — both stay out of this WP (§9).

## 9. Out of scope (do not start; note anything you find for the human)

- **D-1 and D-5** and every storage-format change — the option-3 WP.
- The **manifest row-order** nit — already claimed by the option-3 WP §6
  (`Write-Manifest` is on its critical path; two WPs touching it is needless
  risk). *This is the plan author's call on the "your call" item.*
- The **O(N²) `Test-BackupManifest` scan**, the **DataPath-keyed
  case-insensitive maps**, the **source-side manifest-cache default location**,
  the **F8 kit-less snapshot window**, **`-RepairFromPruned`**, the
  **`RECONSTRUCT.log` target-name nit** — all parked or option-3-owned.
- Any **new configuration key** (no `IncludeHidden`, no verify toggle — verify
  is unconditional; a "trust me" switch on a data-integrity check is exactly
  the kind of option this product should not have).
- Changing **reparse-point / symlink traversal** semantics.
- **bash-v2** (Linux backup engine, SR-033) — unchanged phase deferral.
- Retiring the `Read-Host` prompt (the ruling was *align*, not *delete*).

## 10. Acceptance checklist (the human cross-checks against this)

- [ ] **D-2 PS**: wrong-payload / same-length bit-flip / truncated data file at a
      resolvable `DataPath` → healed from the pool (exit 0, byte-exact, warning
      logged) when a good copy exists; **exit 1** naming the row when not.
      Real Pester output pasted.
- [ ] **D-2 bash**: same three damages, same two outcomes, same exit codes.
      Real bats output pasted.
- [ ] **D-2 interop**: a Windows-made damaged store restores identically under
      both restorers in the cross-artifact CI job.
- [ ] **D-3**: one unrelated unexpandable `.7z` in the pool ⇒ **exit 1 /
      ContentMissing** (was 4/CandidateError) in **both** restorers, with the
      candidate still named in the detail; an unreadable candidate ⇒ exit 4 /
      `StorageUnreadable`; a no-7-Zip unreadable candidate records **one** cause.
- [ ] **D-3 non-regression**: a row's **own** archive failing to expand still
      exits 4 in both restorers.
- [ ] **D-4**: all **nine** `Get-ChildItem` sites carry `-Force`; the static
      guard test fails on a deliberately reverted site; dot file, **nested
      dot-directory**, Windows Hidden file/directory and System-attribute file
      are backed up and restore byte-exact **in all four modes**; a dot-named
      and a Hidden **pool** data file are found by `(hash,length)` recovery.
- [ ] **D-4 disclosure**: README documents `desktop.ini`/`Thumbs.db`/`.DS_Store`
      entering backups and points at `ExcludeFolder`; no new config key exists.
- [ ] **Parity**: `Reconstruct.ps1 -NonInteractive` with no `-TargetRoot` exits
      **2** with usage and never blocks; the prompt still works interactively;
      `reconstruct.sh` unchanged.
- [ ] **Kit revision 6** stamped in **both** restorers; README + AGENTS.md §3
      revision paragraphs updated; `-RefreshKits` named as the upgrade path;
      AGENTS.md §3 open-defect box updated for D-2/D-3/D-4 with the D-1/D-5
      forward-pointer left intact.
- [ ] **G2.8 de-vacuumed** (TC-019 amended, mode-aware, exact) and the
      **orphan second pass** runs as harness tooling over G2/G3/G9 timelines.
- [ ] `pwsh scripts/check.ps1 -Tier Full` green with the real numbers pasted;
      integration total ≥ baseline 372 and **explained** if it moved (D-4 adds
      files to test sources).
- [ ] `shellcheck bash/reconstruct.sh` clean; `bats tests/bash/` green.
- [ ] `python scripts/trace.py --strict --require-verified --phase
      core,bash-v1,container-v1` → 0 orphans / 0 integrity / 0 status-findings
      (SR-033 phase-deferred), with SR-056/SR-057 `Verified`, LLR-056/057
      `Implemented`, TC-108..TC-116 `Pass`.
- [ ] **Independent review** verdict recorded in status.md (restore surface,
      adversarial).
- [ ] Nothing from §9 was started; storage path untouched (`git diff` shows no
      change to `Save-SupersededData` / `Invoke-BackupFileGroup` /
      `Sync-BackupStorageLayout`).
- [ ] status.md G1/G2/G3 entries with pasted evidence; clean tree.

## 11. Open questions for the human (answer before or during G1)

1. **Mint SN-033?** D-2 is a failure of existing SN-005 ("restore bit-for-bit")
   rather than a new need. Precedent cuts both ways: SN-030/031/032 were minted
   from investigations. Default if unanswered: **mint SN-033** and point SR-056
   at it plus SN-005/SN-026.
2. **Windows reserved device names (parked SR-055 extension) — in or out?**
   Author's call: **IN**, it is the same walk surface, a per-component string
   rule in the existing `Test-PortableRelativePath`, and unit-testable. The one
   cost: a Linux source legitimately holding `NUL.txt` would start **failing the
   set loudly**, which is a new refusal class arriving in the same release that
   *widens* what gets captured. If the human prefers minimal blast radius,
   defer it — it is genuinely cheap either way.
3. **Verify cost.** Verify-after-write adds one full read+hash of every restored
   file: a restore's read volume roughly doubles (≈ +40–60% wall clock on
   spinning/USB media). Unconditional is the right default for a data-safety
   tool; confirm there should be **no opt-out switch**. A `PB-###` perf-budget
   row could be minted for restore throughput (the perf step is inert until real
   rows exist).
4. **G2.8 Mirror arm.** The honest fix asserts *two* DataPaths in Mirror (today's
   D-5 truth) with a comment naming the defect; a naive `-eq 1` would be a
   knowingly-red test in a WP forbidden from touching storage. Confirm the
   change-detector approach (§6.4) rather than "fix G2.8 to assert dedup".
5. **Hidden attributes on restore.** `-Force` makes hidden files *backed up*;
   the 9-column manifest has nowhere to record the Hidden/System attribute, so a
   restored file comes back **without** it. Confirm that is acceptable (author's
   read: yes — attributes have never been preserved and adding a column would
   break the AGENTS.md §3 schema invariant). It should be stated in the README
   note.
