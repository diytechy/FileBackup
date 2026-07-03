# Plan: bash/Linux restore variant (phase `bash-v1`)

**For the executing agent (Opus).** This is a complete work order: context,
the pinned contract, the requirement ids already registered, file-by-file work
items, test/CI strategy, and the acceptance checklist. The human has approved
executing **phase `bash-v1` end-to-end** (G2 refinement → G3 implementation →
independent review); they will perform the **final review and cross-check
themselves** — leave the tree clean, green, and fully recorded for that.

---

## 0. Ground rules (non-negotiable)

- Read [CLAUDE.md](../../CLAUDE.md), [AGENTS.md](../../AGENTS.md) §2–§4, and
  [docs/process.md](../process.md) §3–§6 before touching anything. The decision
  dial is **HIGH**: engine/restore-surface decisions get recorded in
  [docs/status.md](../status.md); never advance a gate silently.
- **Never report a green you didn't run.** Local Windows validation uses
  `pwsh scripts/check.ps1`; bash validation must come from a real Linux run —
  the CI ubuntu lane (or WSL if present). Git Bash on the Windows dev box is
  *not* an acceptance environment (no `xxhsum`, BSD-ish quirks).
- **Scope is `bash-v1` (restore) only.** `bash-v2` (the bash backup engine,
  SR-033/SN-023/LLR-033/TC-057) is registered but **out of scope** — do not
  start it; it needs its own human go-ahead and further decomposition.
- Commit early and often (small, green commits); end with a clean tree and a
  status.md audit entry per gate (process.md §5 verdict protocol).

## 1. Why / what already exists

FileBackup (PowerShell 7, Windows) backs up with xxHash128 dedup and dated
`Snapshot_<date>` point-in-time folders, and restores byte-exact from the
backup folder alone via a bundled kit (`RECONSTRUCT.ps1` + Common module +
DLL). The human wants the restore half to also work on a stock **Linux** box
with no PowerShell — a NAS, a rescue live-USB — from the *same* backup
folders. The **contract lives once** (the SR registry + the on-disk format);
only the implementation is duplicated, and cross-implementation conformance
tests keep the two honest.

G1 is **done** (2026-07-03): SN-022 (Linux restore) and SN-023 (Linux backup,
deferred) exist; SR-030/031/032 (`Phase=bash-v1`) and SR-033 (`Phase=bash-v2`)
are registered **Draft** with acceptance criteria; skeleton LLR-030..033 and
TC-053..057 rows exist. The harness exempts not-yet-shipped phases explicitly:
`trace.py --require-verified --phase core` reports them as *phase-deferred*.

## 2. The pinned contract (single source of truth: the SR rows + this table)

Read the authoritative code before implementing — but these facts are pinned
and MUST NOT drift:

| Fact | Value | Authority |
|---|---|---|
| Manifest file | `MANIFEST.csv` in the backup root and in each snapshot | `Get-FileBackupDefaults` |
| Columns (9, exact order) | `DataPath, RelativePath, Length, LastWriteTimeStr, xxH2Hash, Compressed, StoredAsHashSize, Duplicate, MediaMBPerSec` | `Write-Manifest` (Common) |
| CSV dialect | `Export-Csv -NoTypeInformation` output: RFC 4180, fields quoted, CRLF line ends, UTF-8 (no BOM on PS7 — but tolerate a BOM) | `Write-Manifest` |
| `LastWriteTimeStr` | .NET round-trip format `'O'` (ISO 8601, 7 fractional digits, e.g. `2024-01-01T09:00:00.0000000`) — parse culture-invariantly; **do not** reformat | `$script:CSVDateFormat = 'O'` |
| `RelativePath` separator | Windows `\` — map to `/` for filesystem ops on Linux; never alter the manifest itself | `Update-SourceManifest` |
| `Compressed` values | literal `Yes` / `No`; `Yes` ⇒ the stored data file is a single-entry 7-Zip archive and carries a `.7z` extension | `Reconstruct.ps1`, SR-004 |
| Hash | XXH128 (XXH3-128), canonical **big-endian**, **32-char UPPERCASE hex** | `Get-FileXxHash` (SR-002) |
| Linux hash tool | `xxhsum -H128` / `xxh128sum` (xxHash ≥ 0.8) emits the canonical digest — normalize case; **prove equality via TC-053 golden fixtures before anything else** | SR-030 |
| Snapshot folder names | `^Snapshot_\d{4}_\d{2}_\d{2}_\d{2}_\d{2}_\d{2}` + optional `_NNN` disambiguator suffix; label format `yyyy_MM_dd_HH_mm_ss` | `Get-FileBackupDefaults`, SR-005 |
| Restore authority | From the backup root: that manifest = latest state. From a snapshot folder: **that snapshot's own manifest is sole authority** — never overlay a newer one | SR-010 |
| Data pool for hash recovery | backup root + **all** sibling snapshot folders; a blank/missing `DataPath` row is recovered by matching `(xxH2Hash, Length)` — `.7z` candidates are decompressed to hash the payload | SR-010, `Find-DataFileByHash` |
| Infrastructure names to skip when scanning | `MANIFEST.csv`, `RECONSTRUCT*`, `FileBackup.Common*`, `System.IO.Hashing*`, `FileBackupState.json`, `backup.log` — **root-level only** (a nested user file with these names is data, regression B6) | `Test-IsInfrastructureFile`, SR-022 |
| Safety guards | refuse a restore target inside the backup root (SR-009, normalized-path prefix test, not `-like`); pre-check target free space using uncompressed `Length` sums, note when compressed rows were excluded (SR-023) | `Reconstruct.ps1` |
| Fail loudly | restore everything recoverable, then **exit non-zero** naming the unrestored count; log per-row failures; clean restore exits 0 | SR-029/SR-031 |
| Sidecar | `RECONSTRUCT.paths.json` = `{"BackupRoot": "<win path>", "ChangeRoot": "<win path>"}` (UTF-8 JSON). **On Linux those Windows paths will not resolve** — see the layout-detection decision below | `New-ReconstructScript` |
| NOT needed for v1 | the content-addressed short-name codec (`Convert-HexToShortName`, custom alphabet): restore reads `DataPath` from the manifest or recovers by hash — it never *computes* names. (bash-v2 will need it; the alphabet lives in Common.) | — |

**Layout-detection decision (pinned):** `reconstruct.sh` derives its roots from
its own location, exactly like `Reconstruct.ps1`'s folder-name logic: if the
script's directory name matches the snapshot regex it *is* the point-in-time
authority and the backup root is discovered via `--backup-root` or the sidecar;
otherwise the script's directory is the backup root. Provide explicit
`--backup-root` / `--change-root` overrides; treat the sidecar's Windows paths
as usable only if they happen to resolve (they won't on Linux — overrides and
auto-detection are the real path). Mirror `Reconstruct.ps1`'s resolution order
and document any deliberate divergence in the LLR.

**Self-containment decision (pinned):** `reconstruct.sh` is **one
self-contained file** — no `source`d libs at runtime — so it can later be
bundled into the restore kit (that bundling + the SR-007 artifact-list revision
is *deliberately deferred*; see §6 "explicitly out").

## 3. Requirements you own this phase

| Id | What | Verify via |
|---|---|---|
| SR-030 | hash conformance (golden fixtures) | TC-053 |
| SR-031 | standalone bash restore, full semantics incl. fail-loudly | TC-054, TC-055 |
| SR-032 | manifest portability (RFC 4180, `\`→`/`, `'O'` dates, unicode/brackets/commas) | TC-056 |

Refine LLR-030/031/032 (they're skeletons — correct `Module`/`CodeSymbol`
freely, keep ids) and the TC rows (add `Parameters`/`Expected` detail per the
dimensional method, `gen_cases.py` expands the `Permutations` cells). All are
`Draft` — flip to `Verified`/`Pass` **only** with the real green run recorded.

## 4. Deliverables & layout

```
bash/
  reconstruct.sh          # self-contained; bash 4+, gawk, xxhsum, 7z
tests/bash/
  hash_conformance.bats   # TC-053
  manifest_parse.bats     # TC-056
  restore.bats            # TC-054 (fixture restores, root + each snapshot)
  fail_loudly.bats        # TC-055 (tampered fixture → non-zero + salvage)
tests/fixtures/
  hash-conformance/       # tiny golden files + expected-hashes.csv
  bash-restore/           # one tiny committed golden backup (source/ + backup/ + changes/ + expected-hashes.csv)
scripts/
  gen_bash_fixtures.ps1   # regenerates both fixture sets via the real engine (deterministic: -BackupTime, fixed bytes)
```

- Fixtures are **committed** (keep them tiny — a few KB) *and* regenerable, so
  a Linux-only contributor never needs Windows, and fixture drift is reviewable.
  Generate them with the real engine (`FileBackup.ps1 -BackupTime`), covering:
  Mirror + HashAddressed, ±compress, a snapshot with a blank-`DataPath` row
  (delete/re-add cycle produces one via `Optimize-ChangeFolders`), unicode /
  bracketed / comma-containing / empty (0-byte) / duplicate-content files.
- Tooling floor on Linux: `bash` ≥ 4, GNU coreutils, `gawk` (FPAT-based RFC
  4180 parsing — plain `awk`/mawk is not enough), `xxhsum` (xxHash ≥ 0.8),
  `7z`/`7za`/`7zz` (p7zip; probe in that order). Check tools up front and fail
  with remediation guidance (the SN-015 fail-loudly pattern) — degrade only
  where the PS restorer degrades (7z needed only when compressed rows exist).
- `shellcheck` clean (add it to the CI lane; treat warnings as errors, same
  bar as PSScriptAnalyzer).

## 5. Test & CI plan

1. **bats** suites as above; every test name embeds its TC id (house style:
   `@test "restores each snapshot byte-exact (TC-054, SR-031)"`).
2. New CI job in `.github/workflows/tests.yml`: `bash-restore` on
   `ubuntu-latest` — `apt-get install xxhash p7zip-full gawk shellcheck` +
   `bats-core`; run shellcheck, then the bats suites against the committed
   fixtures.
3. **Cross-implementation job** (the real interop proof): `windows-latest`
   step runs `scripts/gen_bash_fixtures.ps1 -Fresh` to produce a *new* backup
   set (all 4 modes) + a source-tree hash listing, uploads as an artifact; the
   ubuntu job downloads it, restores root + every snapshot with
   `reconstruct.sh`, and compares every file's `xxh128sum` against the listing.
   This is TC-054's `origin=set{...}` × mode matrix, end to end.
4. The existing Windows lanes must stay green untouched: `pwsh
   scripts/check.ps1 -Tier Full` before every commit that touches shared files.

## 6. Work order (suggested commits)

1. **G2 refinement** — flesh out LLR-030..032 + TC-053..056 rows (registry
   only); `trace.py --strict --require-verified --phase core` stays 0/0/0.
   Record a G2 driver entry in status.md.
2. **Fixtures** — `scripts/gen_bash_fixtures.ps1` + committed
   `tests/fixtures/**` (+ golden hash values produced by `Get-FileXxHash`).
3. **Hash conformance** — the `xxh128` wrapper inside `reconstruct.sh` +
   `hash_conformance.bats` green on Linux (this de-risks everything else;
   if the digests don't match, STOP and record — the whole phase pivots).
4. **Manifest parsing** — gawk FPAT parser + `manifest_parse.bats`.
5. **`reconstruct.sh`** — full restore semantics per §2, `restore.bats` +
   `fail_loudly.bats`.
6. **CI** — the ubuntu + cross-artifact jobs.
7. **Docs + registry closure** — AGENTS.md: add a `bash/reconstruct.sh` row to
   the §2 module table (the generated map is PowerShell-AST-only; note that)
   and a §4 bullet for the Linux tooling floor; README: "Restore on Linux"
   section; flip SR-030/031/032 → `Verified`, TCs → `Pass`; **append
   `bash-v1` to the `--phase` list in `scripts/check.ps1` AND
   `.github/workflows/tests.yml`** so the ratchet re-arms; status.md G3 entry
   with the real outputs pasted.
8. **Independent review** — restore surface is high-risk (process.md §6):
   spawn a fresh-context reviewer on the bash restore path (adversarial:
   tampered fixtures, weird names, snapshot-deleted-by-user, capacity edge,
   exit codes) before declaring done.

**Explicitly out of this phase** (do not do; note them for the human):
- bundling `reconstruct.sh` into the restore kit (`New-ReconstructScript` +
  SR-007 revision + TC) — natural next step, human decides;
- `bash-v2` backup engine (SR-033);
- any change to engine behavior — if the contract turns out ambiguous or a
  PS-side bug surfaces, **record it in status.md and stop** on that item
  rather than "fixing" the Windows side unilaterally.

## 7. Acceptance checklist (the human cross-checks against this)

- [ ] TC-053: bash digests == committed `Get-FileXxHash` goldens (all fixtures)
- [ ] TC-056: golden manifests parse identically (unicode/comma/quote/bracket/space); `\`→`/` round-trip
- [ ] TC-054: fixture backups restore byte-exact on Linux — backup root **and every snapshot**, all 4 mode combos, incl. blank-DataPath + 0-byte + duplicate rows
- [ ] TC-055: tampered fixture → non-zero exit naming the count, salvageable rows still restored; clean restore exits 0
- [ ] Cross-artifact CI job green (fresh Windows-made backups restored on ubuntu)
- [ ] shellcheck clean; existing Windows suite untouched and green (`check.ps1 -Tier Full`: 52 unit / 236 integration baseline or better)
- [ ] `trace.py --strict --require-verified --phase core,bash-v1` → 0 orphans / 0 status findings; SR-030/031/032 Verified
- [ ] status.md: G2 + G3 driver entries with pasted evidence, independent-review verdict, clean tree
- [ ] Nothing from the "explicitly out" list was started

## 8. Command reference

```powershell
pwsh scripts/check.ps1 -Tier Full            # full Windows gate (must stay green)
python scripts/trace.py --strict --require-verified --phase core           # during the work
python scripts/trace.py --strict --require-verified --phase core,bash-v1  # at closure
pwsh scripts/gen_bash_fixtures.ps1           # regenerate fixtures (to be written)
```
```bash
# Linux (CI or WSL)
shellcheck bash/reconstruct.sh
bats tests/bash/
bash/reconstruct.sh --target-root /tmp/restore [--backup-root PATH] [--change-root PATH]
```
