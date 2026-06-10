# Project Status — Blackboard

Live coordination for the gated process (see [process.md](process.md)). Keep the
**Current State** header short and current; append the audit log below (newest
last) — it is the record, not required reading for every pass.

> **Retrofit, not greenfield.** FileBackup already works and ships a green Pester
> suite. We are layering the requirement-traced process *onto existing code*:
> back-fill UN/SR/LLR/TC from what the tool already does and from
> [AGENTS.md](../AGENTS.md), close traceability gaps, then keep new work gated.

> **Naming caution.** The kit's **gates** are `G1, G2, G3, G-Release, G-Final`.
> FileBackup's existing test **groups** are `G1…G9` (storage-mode suites in
> `tests/Run-All.ps1`) — a *different* namespace. Don't conflate them.

---

## Current State

- **Active gate:** G3 — Implementation truth-up (G2 human-APPROVED 2026-06-05)
- **Latest full run (2026-06-09):** **48/48 unit, 236/0/4 integration, lint
  clean, 0 orphans, 0 status findings** (`check.ps1 -Tier Full` — gate `all`
  now also machine-checks `--require-verified`).
- **`COVERAGE_THRESHOLD` = 80%**; **78.1% accepted** with documented exclusions
  (human 2026-06-05) — G3 coverage criterion met.
- **SR tally:** 24 Test/Verified · 3 Demonstration · 1 Inspection · 0 Open —
  every `Verification=Test` SR is Verified (machine-checked by
  `trace.py --require-verified`).
- **2026-06-09 — template re-sync (ai-template HEAD):** process.md updated
  (thin orchestrators, interface contracts at the code, Mermaid convention,
  tier semantics, method rules); trace.py/--require-verified wired into
  check.ps1 + CI; gen_cases.py added; gen_arch_map.ps1 now also generates the
  Mermaid dependency diagram (architecture.md + AGENTS.md) and the
  `Invoke-BackupSet` flow (architecture.md). Gap remediation: comment-based
  help ordering fixed module-wide (a leading `# Implements:` comment was
  silently breaking `Get-Help`); new Reconstruct⊥Engine AST guard (TC-048);
  stale doc totals/sections refreshed (AGENTS §1/§5/§6, START_HERE).
- **Resolved decisions (detail in the audit log):** coverage accepted at 78.1%
  with documented structural exclusions (human 2026-06-05; cleanup candidate:
  retire or wire up the dormant MediaMBPerSec metric); snapshot-model redesign
  taken through its own G1→G2→G3 and **independently review-APPROVED 2026-06-06**
  (SR-005/010/028 Verified).
- **Next action (human):** **G3 sign-off** — both the main implementation
  truth-up and the snapshot redesign stand complete, validated, and
  reviewer-approved; the Gate Sign-offs table awaits the human row.

### Design note: dated snapshots — implemented 2026-06-06, kept for the record
**Human direction (2026-06-05):** snapshot folders should be **labelled by the
date OF the backup that produced them (drop the `Pre_` marker)**; each snapshot
**fully reconstructs the state as of that backup**; the **latest run has no
snapshot folder** because the live backup root *is* the latest snapshot.

**Why this is a redesign, not a patch:** today a `Pre_<ts>_Changes` folder holds
the *prior* versions captured *before* a run, and Reconstruct overlays the backup
root as newest authority — so restoring from a change folder yields current
content (the SR-010 defect). The new model inverts the meaning: a dated snapshot
is an authoritative point-in-time, self-sufficient for full restore.

**Blast radius (the "multiple segments"):**
- AGENTS.md §3 invariant — the `^Pre_\d{4}…_Changes$` change-folder regex.
- `Complete-ChangeFolder` / `New-ReconstructScript` — naming + when a snapshot is
  (not) created for the latest run; `$Def.ChangeFolderRegex`.
- `Reconstruct.ps1` — overlay order (snapshot must win for its point-in-time),
  search-folder aggregation, the `Pre_`-based `$ChangeFolderPattern`.
- `Optimize-ChangeFolders`, `Move-RemovedFilesToStaging` — what data a snapshot
  must retain to stand alone vs. share with the backup root.
- Requirements: UN-004 (recover older copy), UN-006 (historical restore),
  SR-005 (change-folder contract), SR-010 (historical restore) — all revised.
- Tests: every G2/G3 suite + Coverage.Tests assertion that references `Pre_*`.
- Docs: README "how it works" diagram + AGENTS pipeline steps 7/13/14.

**Proposed handling:** treat as a scoped change through the gate — (G1) revise
UN-004/006 + SR-005/010 to the new model and a migration/compat stance for
existing `Pre_*` backups; (G2) decompose to LLRs + tests; (G3) implement with an
independent review of the restore-path change. **Do not implement until the human
approves this framing.**

### Non-goals (assumed — confirm at G1)
Out of scope unless the human says otherwise: non-Windows / PowerShell 5.1
support, any GUI, cloud/remote backup targets, and encryption-at-rest.

## Scope (restated from the brief)

- **Goal:** Periodic, content-aware file backup with change tracking and
  self-contained reconstruction (xxHash128 dedup, optional 7-Zip, `MANIFEST.csv`,
  per-run change snapshots, standalone restore kit).
- **End user(s):** Technical Windows users / the author running scheduled or
  ad-hoc backups via `pwsh`; agents modifying the tool.
- **Active hats:** End User, UX/Docs, System Engineer, Software Engineer, Test
  Engineer. _Domain hat to consider: **Data-integrity/Storage** (hashing,
  dedup, atomicity, restore correctness) — the load-bearing risk area._
- **Supported platforms:** Windows + **PowerShell 7+** (`pwsh`) only (Windows
  PowerShell 5.1 is explicitly unsupported). Launchers/harness are PowerShell.
- **Constraints:** Restore kit must be self-contained (Common module + DLL +
  `Reconstruct.ps1` bundled); **Common must never depend on Engine**; manifest
  schema is a fixed 9-column contract; `System.IO.Hashing` 8.0.0 required;
  7-Zip/ffprobe optional. Tests sweep 4 storage modes (Mirror / HashAddressed ×
  ±Compress).
- **Non-goals:** _(confirm with human — e.g. non-Windows support, GUI, cloud
  targets, encryption-at-rest)._
- **Definition of done (for the retrofit):** Every existing capability and
  invariant is traced UN→SR→LLR→TC with **0 orphans**; the check harness is
  wired to Pester + PSScriptAnalyzer and runs green locally and in CI; the
  architecture map reflects the real module/function layout.

## Gate Sign-offs

Drop `G-Release` only if this becomes a one-off; FileBackup ships versioned, so
keep it.

| Gate | End User | UX/Docs | System Eng | Test Eng | Human |
|---|---|---|---|---|---|
| G1 — Requirements/UX/Constraints | APPROVE (driver) | APPROVE (driver) | APPROVE (driver) | n/a | **APPROVE 2026-06-05** |
| G2 — Decomposition & Test Coverage | n/a | n/a | APPROVE (driver) | APPROVE (driver) | **APPROVE 2026-06-05** |
| G3 — Implementation | n/a | n/a | CHANGES-REQUESTED (driver) | CHANGES-REQUESTED (driver) | PENDING |
| G-Release — Release readiness | n/a | n/a | PENDING | PENDING | PENDING |
| G-Final — Acceptance | PENDING | n/a | n/a | (evidence) | PENDING |

---

## Audit log

<!-- Append verdict blocks here per process.md §5. Newest at the bottom. -->

### DRIVER — G1 — Round 1 — 2026-06-05
Process scaffolded onto the existing repo (docs/, registries, trace.py,
gen_release_checklist.py). Registries are empty placeholders. Next: back-fill
UN/SR from README + AGENTS.md and reconcile against the existing test matrix.

### DRIVER (End User + UX + System Engineer hats) — G1 — Round 1 — 2026-06-05
Verdict: APPROVE (driver hats) — awaiting human ratification.
Back-filled the registries from README.md, AGENTS.md (invariants sec.3, test
matrix sec.6), the config schema, and observed `FileBackup.ps1` behavior.
Baseline before writing: tool green (Pester Unit 27/27), deps present
(System.IO.Hashing 8.0.0, 7-Zip, Pester 5.7.1, PSScriptAnalyzer 1.25.0);
`trace.py` clean.

What changed:
- `requirements/user-needs.md`: 12 core needs (UN-001..012) + 9 edge-case
  expectations (UN-013..021), each with priority + acceptance intent.
- `requirements/system-requirements.csv`: 27 measurable SRs (SR-001..027), each
  linked to ≥1 UN, with AcceptanceCriteria, Permutations (storage modes /
  compression / hash-freq), Priority, and Verification method. Test-verifiable
  SRs marked `Test`; mail SR-015 + onboarding SR-027 + degradation SR-020
  `Demonstration`; SR-016 (automation) + SR-019 (required deps) `Inspection`.
- `trace.py`: UN=21 SR=27, **0 UN-without-SR**. Remaining 52 orphans are all
  the expected SR→LLR/TC gaps that G2 will close (not G1 blockers).

Findings:
- [MINOR] UN-012 (first-run setup/docs) had no SR on first pass → added SR-027
  (Demonstration). Resolved.
- [MINOR] Non-goals + `COVERAGE_THRESHOLD` assumed from the brief, not yet
  human-ratified → see Open items.

G1 exit criteria status: UN complete w/ priority + acceptance intent + edge
cases ✅; every SR links ≥1 UN w/ measurable AcceptanceCriteria ✅;
constraints + non-goals captured ✅ (non-goals pending human confirm).
**Awaiting human sign-off to close G1 and open G2.**

### HUMAN — G1 — 2026-06-05
Verdict: APPROVE. G1 closed; proceed to G2.

### DRIVER (System Engineer + Test Engineer hats) — G2 — Round 1 — 2026-06-05
Verdict: APPROVE (driver hats) — awaiting human ratification.
Decomposed the 27 SRs into 25 LLRs (real Module + CodeSymbol) and 41 TCs mapped
to the existing tests; SR-016/SR-019 are Inspection-only (no LLR, per trace
rules) and still carry a TC. Wired the check harness and CI.

What changed:
- `requirements/low-level-requirements.csv`: LLR-001..027 (gaps at 016/019),
  each naming the real function(s) (e.g. SR-003→Invoke-BackupFileGroup/
  Get-HashSizeFileName, SR-005→Complete-ChangeFolder, SR-008→Reconstruct.ps1/
  Expand-FileWithSevenZip) with TestRefs.
- `test/test-cases.csv`: TC-001..042 (gap at 029). TC-001..028 map to real
  automated tests — the 7 Pester unit Describes + integration suite case ids
  (G1.1..G8.2). TC-030..042 cover the rest by Inspection/Analysis/Demonstration
  or are flagged as cheap auto-tests to add at G3.
- `scripts/gen_arch_map.ps1`: AST-based PowerShell module-map generator; fills
  the BEGIN/END block in `architecture.md`, `-Check` fails when stale.
- `scripts/check.ps1`: tiered gate (Smoke = lint + trace --strict + map-fresh +
  Pester unit; Full/Release add the Subst integration sweep); nonzero on any
  failure.
- `.github/workflows/tests.yml`: new `traceability` job (trace --strict +
  map-fresh, uploads report.md); `scripts/` added to the lint path.

Evidence (real output, local):
- `python scripts/trace.py --strict` → `UN=21 SR=27 LLR=25 TC=41 orphans=0`, exit 0.
- `pwsh scripts/check.ps1 -Tier Smoke` → PSScriptAnalyzer PASS, Traceability
  PASS (0 orphans), Architecture map PASS, Pester unit **27/27** PASS →
  "All steps passed." (Full-tier Subst sweep is a G3 step; not run this turn.)

Findings:
- [MINOR] Lint initially failed on legacy `Test-Backup.ps1` (unapproved verb);
  scoped the harness lint to the AGENTS.md sec.5 maintained surface
  (FileBackup.ps1, Reconstruct.ps1, Modules, tests, scripts). Resolved.
- [MINOR] Functions lack `Implements:` tags so the generated map shows "—" in
  the back-link column → tracked as G2/G3 hardening (Open items).

G2 exit criteria status: every SR → ≥1 LLR (or Inspection) ✅; every SR & LLR →
≥1 TC ✅; traceability **0 orphans** ✅; harness runs locally ✅ + CI wired ✅.
**Awaiting human sign-off to close G2 and open G3.**

### FINDING (carried to G3) — SR-016 / SR-019 — 2026-06-05
[MAJOR] `Initialize-XxHashLibrary` (Common) installs System.IO.Hashing on first
use via an interactive `Read-Host "(Y/N)"` with **no non-interactive fallback**.
An unattended `FileBackup.ps1` run on a host where the package is neither
installed nor bundled as a DLL would **block on the prompt** — the exact failure
SR-016 ("automation must never block") forbids; also touches SR-019.
→ G3 work item: add a `-NonInteractive` / `-AutoInstall` switch to
`Initialize-XxHashLibrary` (and thread it from `Initialize-Dependencies` /
`FileBackup.ps1`) so an unattended first run either auto-installs or fails loudly
with a non-zero exit instead of hanging. Add an LLR + an automated TC; this would
promote SR-016/SR-019 from Inspection to **Verified**. @SoftwareEngineer
(Until fixed, the documented mitigation stands: pre-run
`tests/Setup.ps1 -InstallDeps -NonInteractive`, or bundle the DLL.)

### HUMAN — G2 — 2026-06-05
Verdict: APPROVE. G2 closed; proceed to G3.

### DRIVER (Software Engineer + Test Engineer hats) — G3 — Round 1 — 2026-06-05
Verdict: CHANGES-REQUESTED (driver) — two decisions for the human (Current State).
Implemented the SR-016/SR-019 fix, added automated tests, tagged the code, and
ran the full tier green.

What changed (code):
- `Initialize-XxHashLibrary` (Common): added `-NonInteractive` / `-AutoInstall`;
  a missing package under -NonInteractive now throws with remediation instead of
  prompting. `Resolve-OptionalTool` + `Initialize-Dependencies` (Engine) and
  `FileBackup.ps1` thread `-NonInteractive` / `-AutoInstallDeps` end-to-end.
  Closes the SR-016 hang risk. Added LLR-016; SR-016 Inspection→Test→Verified.
- `Implements:` back-link tags on 25 functions across both modules; the generated
  `architecture.md` map now shows SR/LLR back-links and a fixed Exported column.

What changed (tests): +4 unit tests (now 31, all green):
- `Resolve-OptionalTool non-interactive` ×2 (SR-016) — would hang if it blocked.
- `FileBackup.ps1 entry point` throws on missing config (SR-018, TC-037).
- `Common does not depend on Engine` AST guard (SR-007, TC-031).
TC-031/036/037 promoted to automated/Pass.

Evidence (real output, local):
- `pwsh scripts/check.ps1 -Tier Full` → lint PASS · trace PASS (0 orphans) ·
  arch-map PASS · Pester unit **31/31** · integration **160 PASS / 0 FAIL /
  4 SKIP** (G8 RealVolume under Subst) → "All steps passed."
- `python scripts/trace.py --strict` → UN=21 SR=27 LLR=26 TC=41 orphans=0.
- Unit-test module line coverage: **22.0%** (187/849).
- SR truth-up: 18 Verified · 5 Open · 3 Demonstration · 1 Inspection.

G3 exit criteria status: lint clean ✅; full tier green ✅; coverage ≥ threshold
**❓ (22% unit — decision #1)**; every test-verifiable SR Verified **❌ (5 Open —
decision #2)**; non-test SRs explicitly Demonstration/Inspection ✅.
**Blocked on the two human decisions before G3 can close.**

### DRIVER (Software Engineer + Test Engineer + Data-integrity hats) — G3 — Round 2 — 2026-06-05
Verdict: CHANGES-REQUESTED (driver) — fixed two real defects; one design
question remains for the human.

Writing tests for the 5 Open SRs surfaced two genuine bugs in the data-integrity
surface (fixed) and one restore-semantics question (escalated):

- [BLOCKER→FIXED] **SR-023 capacity check was a no-op.** Reconstruct.ps1's
  "not enough free space" `throw` sat inside the same try/catch that tolerates a
  failure to resolve the target drive, so it was always swallowed — a restore
  onto a too-small target would silently produce a partial tree. Restructured so
  drive-resolution stays non-fatal but an actual shortfall aborts. Test: TC-040.
- [MAJOR→FIXED] **SR-014 under-reported failure.** A set whose path wouldn't
  resolve returned without setting OverallSuccess, so the run exited 0 despite a
  failed set; a mid-pipeline throw also aborted the remaining sets. Path-failure
  now marks the run failed; FileBackup.ps1 wraps each set so one set's throw
  can't abort the others. Test: TC-034 (good set still backs up; exit code 1).
- [QUESTION] **SR-010 historical restore** overlays the backup-root manifest as
  newest authority, so restoring from a change folder yields the *current*
  version of a modified file, not the captured prior version (contradicts
  UN-004). Left SR-010 **Open** pending the human's intended semantics; did not
  guess at a fix on the restore-correctness path.

New tests (tests/Unit/Coverage.Tests.ps1, +4 → 35 unit total, all green):
SR-005 (change-folder naming + manifest), SR-014 (multi-set + exit code),
SR-023 (capacity abort), SR-026 (cross-change collapse).

Evidence (real output, local):
- `pwsh scripts/check.ps1 -Tier Full` → lint PASS · trace PASS (0 orphans) ·
  arch-map PASS · Pester unit **35/35** · integration **160 PASS / 0 FAIL /
  4 SKIP** → "All steps passed."
- Module line coverage **69.6%** (592/850), up from 22.0% (the in-process backup/
  reconstruct tests exercise the engine I/O shells under Pester).
- SR truth-up: **22 Verified · 1 Open (SR-010) · 3 Demonstration · 1 Inspection**.

NOTE (high-risk surface): SR-014/SR-023 touch restore + orchestration; per
process.md §6 an independent pre-gate review is advisable before G3 sign-off.

### DRIVER (End User + System Engineer hats) — SNAPSHOT REDESIGN G1 — Round 1 — 2026-06-05
Verdict: APPROVE (driver) — awaiting human ratification.
Approved plan: `~/.claude/plans/refactored-jingling-panda.md` (dated-snapshot
model; delta + hash-pull storage; clean cutover). Stepped back to requirements.

What changed (docs only — no code touched; suite still green):
- `user-needs.md`: UN-004 (point-in-time snapshots, each fully restorable) +
  UN-006 (restore a dated snapshot byte-exact) revised to the new model.
- `system-requirements.csv`: SR-005 rewritten (dated `Snapshot_<date>` naming,
  no snapshot for the latest/no-op run, atomic completion) → Draft; SR-010
  rewritten (snapshot's own manifest authoritative, bytes resolved by hash from
  the live backup + sibling snapshots, no newer-manifest overlay) → Draft; new
  SR-028 (delta + hash-pull storage, clean cutover) → Draft.
- `AGENTS.md` §3: forward-pointer note (did NOT rewrite the live `Pre_` invariant
  — AGENTS documents current code facts; the regex/pipeline rewrite lands at G3
  with the code, to avoid a doc/code mismatch). Deviation from the plan's literal
  "G1 updates AGENTS §3" for that reason.
- `trace.py`: UN=21 SR=28 LLR=26 TC=41, **orphans=2** — both SR-028 (no LLR/TC),
  expected at G1 and closed at G2. SR-005/SR-010 stay non-orphan via existing
  LLR/TC (revised at G2/G3).

G1 exit criteria: UN updated w/ acceptance intent ✅; SRs measurable + linked ✅;
constraints (clean cutover) captured ✅. **Awaiting human G1 sign-off to open G2.**

### HUMAN — SNAPSHOT REDESIGN G1 — 2026-06-05
Verdict: APPROVE. Folder name `Snapshot_<date>` confirmed; snapshot date = prior
backup completion time persisted in FileBackupState.json confirmed. Proceed to G2.

### DRIVER (System Engineer + Test Engineer hats) — SNAPSHOT REDESIGN G2 — Round 1 — 2026-06-05
Verdict: APPROVE (driver) — awaiting human ratification.
Decomposed the revised SRs; trace back to 0 orphans (docs only, suite green).

What changed:
- `low-level-requirements.csv`: LLR-005 → dated `Snapshot_<date>` completion
  (skip empty/latest); LLR-010 → reconstruct authority rule (snapshot manifest is
  sole authority; bytes by hash over backup root + all snapshots); new LLR-028 →
  persisted last-backup date (`Get/Set-LastBackupRun`), delta storage, `^Snapshot_`
  regex in `Get-FileBackupDefaults`, clean cutover.
- `test-cases.csv`: TC-030 → dated-naming + no-op-no-snapshot (Draft); TC-033 →
  the **point-in-time restore** test (v1→v2 ⇒ snapshot=v1, root=v2) (Draft); new
  TC-043 (delta storage / hash-pull) + TC-044 (AST check: no `Pre_*` left) (Draft).
- `trace.py --strict`: UN=21 SR=28 LLR=27 TC=43, **orphans=0**, exit 0. Unit
  suite still green (no code touched; the current `Pre_` test stays green until
  G3 replaces it).

G2 exit criteria: every revised/new SR → ≥1 LLR ✅; every SR & LLR → ≥1 TC ✅;
**0 orphans** ✅; harness green ✅.

**G2 expansion (human-requested permutation matrix + date seam, 2026-06-06):**
- Injectable backup-date seam folded into LLR-005 (`Complete-ChangeFolder
  -BackupTime`) and LLR-028 (`Set-LastBackupRun -When`) — deterministic snapshot
  dating for tests, mirroring the existing `Test-HashRecalcDue -Now`.
- New rollback matrix TCs → a planned **`G9-Rollback` suite**: TC-045 (restore
  as-of EACH historical snapshot + latest, byte-exact, × 4 storage modes),
  TC-046 (snapshot lifecycle/naming over a dated timeline; no snapshot for
  no-op/latest), TC-047 (mixed content — compressible / already-compressed media
  / binary / empty / duplicate / nested-infra-named / unicode-bracket — handled
  + hash-restorable at every rollback point). SR-010 permutations extended with
  `snapshot=set{each-historical,latest}`.
- Rationale: rollback verification had **zero** coverage and there was no seam to
  date snapshots deterministically — gaps the user flagged before G3.
- trace `--strict`: UN=21 SR=28 LLR=27 TC=46, **orphans=0**. Suite still green.

**Awaiting human G2 sign-off to open G3.** (G3 is the high-risk restore-path
change → independent review per process.md §6.)

### HUMAN — SNAPSHOT REDESIGN G2 — 2026-06-06
Verdict: APPROVE. Proceed to G3 implementation. (Checkpoint committed.)

### DRIVER (Software + Test + Data-integrity hats) — SNAPSHOT REDESIGN G3 — Round 1 — 2026-06-06
Verdict: implemented + validated; **recommend an independent restore-path review
before final human sign-off** (high-risk surface, process.md §6).

Implemented the dated-snapshot model (clean cutover):
- Common: `^Snapshot_` regex + `SnapshotPrefix`; merged state file.
- Engine: `Read-BackupState`/`Set-BackupStateField` (merge), `Get/Set-LastBackupRun`;
  **`Save-SupersededData`** (the crux — preserves prior bytes BEFORE Mirror
  overwrite / HashAddressed orphaning, refcount-safe via new-source survival
  check); `Complete-ChangeFolder` → dated naming, skip-empty, copies the path
  sidecar; `Invoke-BackupSet` → `-BackupTime` seam, prior-date snapshot, persists
  `LastBackupRun`.
- `Reconstruct.ps1`: snapshot's own manifest is sole authority (no overlay); data
  pool = backup root + all snapshots (null-safe); `^Snapshot_` pattern.
- FileBackup.ps1 + harness `Invoke-Backup`: `-BackupTime` passthrough.

Scope note: the plan assumed storage "barely changes," but writing the tests
revealed modified-file/Mirror-overwrite byte loss — `Save-SupersededData` (new
pipeline step 9.5) was required for correct point-in-time restore. Flagged + done.

Tests (all green): clean-cutover AST (TC-044), point-in-time restore × 4 modes
(TC-033), new **G9-Rollback** suite (TC-045/046/047) — dated timeline with
modify/delete/add/no-op, restore-as-of-each + latest byte-exact, mixed content.

Evidence (real, local): `pwsh scripts/check.ps1 -Tier Full` → lint PASS · trace
PASS (**0 orphans**, UN=21 SR=28 LLR=27 TC=46) · arch-map PASS · Pester **42/42** ·
integration **212 PASS / 0 FAIL / 4 SKIP** → "All steps passed."
SR truth-up: **SR-005/SR-010/SR-028 → Verified.**

Self-review (data-integrity): superseded bytes preserved before overwrite in all
4 modes ✓; shared/surviving data never evicted (survival check) ✓; no-op &
first-run create no snapshot ✓; snapshot self-contained via copied sidecar ✓;
state-file merge keeps LastHashRun+LastBackupRun ✓; reconstruct null-safe ✓.
Residual gaps for the reviewer: explicit **rename** rollback assertion (covered
indirectly by add/delete) and many-snapshot Optimize interaction (2 in G9).

**Open:** independent reviewer pass, then human G3 sign-off.

### INDEPENDENT REVIEWER — SNAPSHOT REDESIGN G3 — 2026-06-06
Verdict: **APPROVE** (2 MINOR). Fresh-context defect hunt on the restore/data-
integrity surface; ran `check.ps1 -Tier Full` (236/0/4) and 4 adversarial probe
timelines across all 4 modes (delete→re-add-different, 4-version history,
duplicate-modify, dedup-both-modified) — **no data loss**. Confirmed: superseded
bytes preserved before overwrite; survival check correct; refcount-aware eviction;
Optimize never removes a byte a snapshot still needs; reconstruct authority +
data-pool correct; clean cutover.
Findings:
- [MINOR→FIXED] `Reconstruct.ps1` target guard used `-like "$root*"` →
  false-rejected prefix-sharing siblings (`bk` vs `bk-restore`) and mishandled
  bracket/wildcard chars. Replaced with normalized full-path `StartsWith` +
  trailing separator (`Test-PathIsInside`); added Pester test 'Restore target
  guard (SR-009)'. Strengthens SR-009. Full tier re-run green (236/0/4, 43 unit).
- [MINOR→BACKLOG] Crash mid-run can leave an orphaned `Temp` with a transient
  manifest/data mismatch; next run aborts loudly (SR-017 guard) — recovery is
  manual. Inherent to staging; current behavior matches UN-013 (fail loudly).
  Future hardening: auto-roll-back a stale `Temp` instead of only refusing.

### DRIVER — SNAPSHOT REDESIGN G3 — 2026-06-06
Independent review APPROVED; sole actionable finding fixed + tested. **Awaiting
human G3 sign-off** to close the dated-snapshot redesign.

### DRIVER (Software + Test Engineer hats) — template re-sync + gap sweep — 2026-06-09
Verdict: APPROVE (driver) — process-tooling + docs change; no engine/restore
behavior touched (module edits are comment-only).

Applied the four ai-template commits newer than the last sync (2e32d0b flow +
interface contracts; e7fa050 harness/tier/trace fixes + --require-verified;
0418812 kit restyle; 05c50ab Mermaid convention + dependency diagram):
- docs/process.md, scripts/trace.py, scripts/gen_release_checklist.py replaced
  with template HEAD (all three were verbatim kit copies); scripts/gen_cases.py
  added (the SR Permutations cells already use its grammar).
- scripts/gen_arch_map.ps1 ported the two new generators: a Mermaid dependency
  diagram (modules + entry scripts, so Common⊥Engine AND Reconstruct→Common-only
  are visible) and the ordered `Invoke-BackupSet` flow; duplicated-marker guard;
  `Implements:` harvesting now anchored to the comment line (a help-block prose
  mention had produced a wrong back-link). Markers added to architecture.md
  (flow + diagram) and AGENTS.md (diagram).
- check.ps1 gained -Gate (G2|G3|all); G3/all add `trace.py --require-verified`
  (the machine half of the G3 "every Test SR Verified" criterion). CI now runs
  --require-verified and triggers on every branch push.

Gap sweep findings (fixed):
- [MAJOR] Comment-based help placed *after* the `# Implements:` line in 19
  module functions silently broke `Get-Help` and summary harvesting → order
  swapped module-wide; 7 orchestration functions lacking any .SYNOPSIS got one.
  Convention recorded in AGENTS.md §4 + CLAUDE.md.
- [MINOR] No AST guard for "Reconstruct.ps1 calls only Common" (the sibling of
  the Common⊥Engine guard) → added (TC-048, SR-007).
- [MINOR] Stale docs: AGENTS §1 still described the Pre_*_Changes model; §5/§6
  carried outdated test totals; suite-group axes said G1–G8; START_HERE listed
  the already-done wiring as deferred → all refreshed.

Evidence (real output, local): `check.ps1 -Tier Full` → lint PASS · trace PASS
(UN=21 SR=28 LLR=27 TC=47, 0 orphans, 0 status findings) · generated docs fresh ·
Pester unit **48/48** · integration **236 PASS / 0 FAIL / 4 SKIP** →
"All steps passed."
