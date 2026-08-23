# Project Status — Blackboard

Live coordination for the gated process (see [process.md](process.md)). Keep the
**Current State** header short and current; append the audit log below (newest
last) — it is the record, not required reading for every pass.

> **Retrofit, not greenfield.** FileBackup already works and ships a green Pester
> suite. We are layering the requirement-traced process *onto existing code*:
> back-fill SN/SR/LLR/TC from what the tool already does and from
> [AGENTS.md](../AGENTS.md), close traceability gaps, then keep new work gated.
> The spine's top layer is
> [requirements/stakeholder-needs.md](requirements/stakeholder-needs.md)
> (formerly `user-needs.md`/UN-###; ids kept their numbers, so audit entries
> below still resolve). Cross-project contracts live in
> [requirements/interfaces.csv](requirements/interfaces.csv) — IF-001 (the
> HomeHub OCI image contract) since 2026-08-12. [interfaces.md](interfaces.md)
> is still unadapted kit boilerplate — tracked in *Open items*.

> **Naming caution.** The kit's **gates** are `G1, G2, G3, G-Release, G-Final`.
> FileBackup's existing test **groups** are `G1…G9` (storage-mode suites in
> `tests/Run-All.ps1`) — a *different* namespace. Don't conflate them.

---

## Current State

- **Active gate:** G3 (retrofit truth-up **human-APPROVED 2026-08-22**; the
  gate stays G3 while the WP1–WP5 scoped changes run their own G1→G3 passes —
  advance to G-Release only after WP6)
- **Latest verified run (2026-08-22, Full tier):** **65/65 Pester unit, lint
  clean, trace SN=24 SR=37 LLR=36 TC=64 with 0 orphans / 0 integrity /
  0 status-findings / 2 phase-deferred (bash-v2, container-v1), integration
  236 PASS / 0 FAIL / 4 SKIP** (`check.ps1 -Tier Full` → "All steps passed").
  This closes the post-2026-08-12 Full-tier gap that was blocking G3 sign-off.
  (First attempt crashed on an environment defect — the Subst backend's
  free-letter probe couldn't see disconnected-but-remembered network mappings;
  harness fixed, audit entry 2026-08-22.)
- **`COVERAGE_THRESHOLD` = 80%**; **78.1% accepted** with documented exclusions
  (human 2026-06-05) — G3 coverage criterion met.
- **SR tally (2026-08-21):** every in-phase `Verification=Test` SR is Verified
  (machine-checked: `trace.py --require-verified --phase core,bash-v1` →
  0 status-findings); the two phase-deferred SRs are SR-033 (bash-v2, Draft)
  and SR-034 (container-v1, Implemented — see *Open items*).
- **2026-07-01 — kit re-sync (ai-template @ e4bcfb1):** process docs split into
  the §1–§7 core ([process.md](process.md)) + opt-in expansions
  ([process-options.md](process-options.md)); this standalone repo runs the
  kit's **minimum profile** (spine hats, ids, §3 discipline, G1→G3+G-Final,
  §5/§6, harness) and skips §8/§9/§10 until scope forces them. Top spine layer
  renamed `UN-###`→`SN-###` (ids keep numbers). Harness gained doc-navigability
  (check_docs.py), the §9 perf comparator (check_perf.py, inert placeholder),
  a machine-readable [gate file](gate) that check.ps1/CI read, and the
  `.githooks/pre-commit` process floor. **Not adopted (deliberate):**
  check_flows.py (this repo's reviewable flow surface is the generated
  `Invoke-BackupSet` flow + AGENTS.md §2 pipeline, which predate that
  convention) and check_stubs.py (Python-only product tooling; no PowerShell
  port shipped — adopting it would pass vacuously). Full audit entry below.
- **2026-06-09 — template re-sync (ai-template HEAD):** process.md updated
  (thin orchestrators, interface contracts at the code, Mermaid convention,
  tier semantics, method rules); trace.py/--require-verified wired into
  check.ps1 + CI; gen_cases.py added; gen_arch_map.ps1 now also generates the
  Mermaid dependency diagram (architecture.md + AGENTS.md) and the
  `Invoke-BackupSet` flow (architecture.md). Gap remediation: comment-based
  help ordering fixed module-wide (a leading `# Implements:` comment was
  silently breaking `Get-Help`); new Reconstruct⊥Engine AST guard (TC-048);
  stale doc totals/sections refreshed (AGENTS §1/§5/§6, START_HERE).
- **2026-07-02 — adversarial dedup/snapshot review (subagent + driver-verified):**
  primary property **CONFIRMED** in all 4 modes — delete → reintroduce-identical →
  delete stores the content's bytes exactly once across backup root + snapshots,
  every dated state restorable; pinned as TC-049 (commit c930f4f). Three
  verified findings recorded; **human approved the scoped-change framing
  ("please proceed") and all three are now FIXED through the gate** — SR-005
  supersession criterion rewritten (manifest diff, not byte I/O), new SR-029
  (restore fails loudly, non-zero exit on unrestorable rows), sidecar added to
  the infrastructure allowlist — validated by TC-050/051/052, the full tier,
  and an **independent reviewer APPROVE** (audit entries below). Awaiting human
  ratification.
- **Resolved decisions (detail in the audit log):** coverage accepted at 78.1%
  with documented structural exclusions (human 2026-06-05; cleanup candidate:
  retire or wire up the dormant MediaMBPerSec metric); snapshot-model redesign
  taken through its own G1→G2→G3 and **independently review-APPROVED 2026-06-06**
  (SR-005/010/028 Verified).
- **2026-07-03 — bash/Linux variant: G1 DONE, handed to the executing agent.**
  Human reversed the non-Windows non-goal (restore-first). Registered: SN-022/
  SN-023; SR-030 (hash conformance), SR-031 (standalone bash restore), SR-032
  (manifest portability) tagged `Phase=bash-v1`; SR-033 (bash backup engine)
  tagged `bash-v2` — **deferred, needs its own go**. Skeleton LLR-030..033 +
  TC-053..057 keep trace at 0 orphans; the harness + CI now run
  `--require-verified --phase core`, which exempts the deferred phases
  *explicitly* (reported as phase-deferred, currently 4). Work order for the
  executing agent: **[plans/bash-variant-plan.md](plans/bash-variant-plan.md)**
  (pinned contract, deliverables, CI plan, acceptance checklist). Human
  performs the final review + cross-check when it returns.
- **2026-07-03 — bash/Linux variant `bash-v1` DELIVERED (driver + independent
  review); awaiting human final review + cross-check.** `bash/reconstruct.sh`
  (one self-contained file) restores byte-exact on Linux from the same backup
  folders, mirroring `Reconstruct.ps1`. **Real-Linux evidence (WSL Fedora 40):**
  22/22 bats green (hash conformance TC-053, manifest parse TC-056, restore
  TC-054 all 4 modes × root+2 snapshots, fail-loudly TC-055), shellcheck clean.
  SR-030/031/032 → **Verified**; the harness ratchet re-armed to
  `--phase core,bash-v1` (only bash-v2/SR-033 stays deferred). Existing Windows
  suite untouched: `check.ps1 -Tier Full` → 52/52 unit, 236/0/4 integration,
  0/0/0 trace. CI gained a ubuntu `bash-restore` (bats) job and a
  windows→ubuntu `bash-interop` job (fresh backups restored + byte-compared) —
  those run on push; the human's final review is the acceptance gate.
- **2026-08-09/12 — HomeHub cross-check + cross-platform hardening + container
  runtime (commits ec43711/6b1484c/bf2ccd0/d5f8894).** A read-only review from
  the HomeHub side ([homehub-integration.md](homehub-integration.md)) produced
  findings 0/A–J. Implemented since: cross-platform tool discovery (finding 0),
  restore dependency preflight (A), fail-before-mutation on missing 7-Zip (B —
  SR-020/LLR-020/TC-039 rewritten), run-state integrity gate (F), empty-source
  refusal with `AllowEmptySource` opt-in (G), the PS-side traversal guard (one
  of the two 2026-07-03 reviewer MINORs), `reconstruct.sh` kit bundling
  (SR-007/TC-059), and a non-root Linux container boundary (SN-024/SR-034/
  LLR-034/TC-060/IF-001, phase `container-v1`, Docker CI job added). **These
  commits did not update this blackboard or the registries for F/G/0/A/
  traversal; that back-fill landed 2026-08-21 (audit entry below) and awaits
  ratification.** Findings C/D/E/H/I/J remain open — see *Open items* below.
- **2026-08-21 — registry back-fill of the 2026-08-12 hardening (driver;
  awaiting human ratification):** new SR-035 (run-state integrity gate, F),
  SR-036 (empty-source refusal, G), SR-037 (cross-platform tool discovery, 0,
  Inspection) + LLR-035..037; SR-009/LLR-009 extended to the traversal guard;
  new TC-061..065 pinning the already-shipped `Safety.Tests.ps1` /
  `Coverage.Tests.ps1` tests; SR back-links and test names annotated.
- **2026-08-22 — Next-action items (a)–(c) RATIFIED (human, audit entry
  below):** (a) G3 sign-off, (b) bash-v1 final review acceptance, (c) the
  2026-08-12 hardening + container work and its 2026-08-21 registry back-fill
  (including the `reconstruct.sh` bundling decision). Item (d) was resolved
  2026-08-21 by the approved frontier dispositions. **The WP1→WP6 queue is now
  unblocked and being executed** under the human's standing "grind to
  completion" authorization: driver + independent-reviewer approvals recorded
  per gate as work lands, with all human gate sign-offs collected in one batch
  at the end of the queue.

## Open items (frontier)

Tracked open work, minted 2026-08-21 from the HomeHub cross-check
([homehub-integration.md](homehub-integration.md) §1/§3/§5) and prior review
carry-overs. Ids are the cross-check's finding letters until each is promoted
to an SR through the gate. **Dispositions human-approved 2026-08-21** ("Yes
that sounds good — proceed"); each row carries its agreed answer, and the
work-package order follows the table.

| Item | What | Disposition (human-approved 2026-08-21) | State |
|---|---|---|---|
| **E** | Restore can only verify rows its manifest still contains — a truncated manifest shrinks the job and still reports success. HomeHub's archive census does not port because of dedup. Partial mitigation shipped: missing-MANIFEST refusal (TC-063). | **WP1 (restore trust & diagnostics bundle).** Witness = a sidecar (e.g. `MANIFEST.csv.meta`) written atomically alongside the manifest carrying row count + xxHash128 of the manifest bytes, duplicated into each snapshot; both restorers verify it before restoring. Independent of the restore loop; portable to bash with tools already required; **subsumes the corrupt-manifest guard** (garbage manifest fails the digest). Adds an artifact to the SR-022 infrastructure allowlist — mind regression B6/TC-052. Needs its own SN/SR through G1; **blocks any "restore is trustworthy" claim.** | Open → WP1 |
| corrupt-manifest guard | Corrupt non-CSV MANIFEST.csv restores nothing yet exits 0 in `Reconstruct.ps1` (2026-07-03 reviewer MINOR; bash validates the header, exit 2). | **WP1**, implemented *inside* the witness change — a lone interim header check would burn a kit revision for something the witness replaces. | Open → WP1 |
| **D** + exit-code table | `Find-DataFileByHash` collapses 4 failure causes into one warning; IF-001 promises HomeHub a translatable exit status but `Reconstruct.ps1` throws one generic failure for every cause. | **WP1.** One documented exit-code table shared by both restorers — adopt bash's existing exit 2 as the baseline, don't invent a competing scheme. Prerequisite for IF-001 leaving `Experimental` (NagLight translation needs something to translate). | Open → WP1 |
| **J** | Backup-side move loops (`Move-RemovedFilesToStaging`, `Save-SupersededData`) abort on first failure instead of aggregating like restore's `$unrestored`. | **WP1** companion (same fail-loudly theme), or immediately after. Small. | Open → WP1 |
| config contract | IF-001's import half is under-specified: `FileBackup.ps1`'s JSON branch is a bare `ConvertFrom-Json` — no schema, no version field, no validation, no test; `container/FileBackup.example.json` is never executed by any test (TC-060 generates its own config). | **WP2.** Versioned JSON schema + validating loader that fails loudly (SR + LLR + TC executing the example file itself). JSON becomes the canonical documented contract; CLIXML stays the legacy native-Windows path. Top HomeHub-facing priority after E. Blocks IF-001 moving past `Experimental`. | Open → WP2 |
| multi-set mounts | How HomeHub maps N host directories onto container paths was unspecified. | **RESOLVED by ruling, WP2 records it:** **one BackupSet per container invocation**; HomeHub runs one service/invocation per directory (matches its per-service scheduling + NagLight model, keeps mounts trivial). Multi-set stays a native-Windows convenience. Recorded in IF-001. | Ruled — document in WP2 |
| container release-verify | SR-034/TC-060 are `Implemented`/`Draft`; CI runs **BuildAndTest only** — Export/Publish/Pull and a `docker load` roundtrip are never exercised; no local `check.ps1` tier runs the container step. | **WP3.** Extend the CI job: Export → `docker load` roundtrip; Publish/Pull against a throwaway `registry:2` container in-job. Then TC-060 → Pass, SR-034 → Verified, **re-arm the ratchet to `--phase core,bash-v1,container-v1`.** Blocks calling container-v1 released. | In CI (partial) → WP3 |
| container smoke depth | Smoke checks a six-artifact kit that omits `RECONSTRUCT.paths.json` and runs one single-set, no-snapshot, no-rerun backup. | **WP3**, with release-verify: add the sidecar to the kit check and a second incremental, snapshot-producing run restored in-container. | Open → WP3 |
| **I** | Snapshot retention is unbounded. | **Re-ruled — the pure "delegate to HomeHub" disposition was unsafe:** blank-DataPath rows recover bytes by hash from *other* snapshots' folders, so externally pruning a `Snapshot_*` folder can delete the only physical copy other snapshots still need. **Split: HomeHub owns retention *policy*; FileBackup owns the *mechanism*** — a `Prune-Snapshot` verb (WP4, own SR) that re-homes still-referenced bytes before deleting a folder. IF-001 now states: never delete snapshot folders directly. **Do before HomeHub builds any pruning.** | Open → WP4 |
| **C** | `Sync-BackupStorageLayout` trusts manifest `Compressed`/`StoredAsHashSize` metadata, so a malformed row can validate itself. | **WP5.** With B fixed, new malformed rows can't be created — C matters for pre-fix backups and for migrations the ext-list merge triggers. Repro test first (double-check §5.3); repair via an opt-in `-VerifyStorage` mode, **not** a physical verify inside every migration (would fight SR-024 idempotence/perf). | Open → WP5 |
| ext-list merge | Merge bash's broader already-compressed extension list (`jar tgz zst gif webm ogg sav pack`) into `Common.psm1`; keep per-file granularity. | **WP5, sequenced AFTER C's repro test** — not trivial: the merge flips existing `.7z` rows to "wrong" under `Sync-BackupStorageLayout`'s config comparison and exercises the untested migration path at scale. Cover the triggered migration in C's test. | Open → WP5 |
| backup-side capacity | Does the backup side have the capacity preflight the restore side gained (SR-023 is restore-only)? | **WP5.** Verify first, then a small SR mirroring SR-023. Importance rises with the container (target is a HomeHub-controlled bind mount). | Open → WP5 |
| **H** | No destination mount-identity preflight. | **Stays delegated to HomeHub (IF-001)** — HomeHub genuinely owns mounts and the container can't see the host mount table. Optional later hardening: an `ExpectedSentinel` config key (refuse if a named file is absent at the destination). Low priority; revisit only if FileBackup runs outside the wrapper. | Delegated |
| release checklist | `checklist-vNEXT-dryrun.md` is stale (UN-### vocabulary, no SR-029+, points at nonexistent `scripts/check.py`, gitignored). | **WP6 (docs batch).** Regenerate from the registries via `gen_release_checklist.py` (also verifies the generator survived the UN→SN rename); include container rows. Blocks G-Release. | Open → WP6 |
| interfaces.md boilerplate | `docs/interfaces.md` is unmodified kit boilerplate; the real IF-001 lives in `requirements/interfaces.csv`. | **WP6.** Rewrite as a thin IF-001 pointer + prose contract. | Open → WP6 |
| doc drift | Kit-version stamp still `9b697cc 2026-07-02`; homehub-integration.md §5.8 false-parity comment (bash/reconstruct.sh:380) unverified post-A-fix. (AGENTS.md test count fixed 2026-08-21.) | **WP6.** Re-stamp only on a real kit resync; verify + close §5.8. | Open → WP6 |
| Archive-option storage mode (ex-ToDo) | Store backups as `.7z` archive sets with per-folder rebuild scripts. | **REJECTED 2026-08-21** — opaque archive sets contradict the model's core strength (plain files on disk, restorable by a 20 KB bash script with no runtime). Moved to Non-goals. | Rejected |
| CloneSpy CRC export (ex-ToDo) | Emit a CloneSpy-compatible CRC list per backup set. | Harmless C-priority idea; stays parked, unscheduled. | Parked |

**Agreed work-package order (after Next-action items (a)–(c) are ratified):**
**WP1** restore trust & diagnostics (E + corrupt-manifest + D/exit codes + J —
one G1→G3 pass, one independent review, one kit revision, PS + bash + kit
copies together) → **WP2** config contract (+ record the one-set-per-invocation
ruling) → **WP3** container release-verify + smoke depth + ratchet re-arm →
**WP4** retention mechanism (`Prune-Snapshot`) → **WP5** C repro test, then
ext-list merge; backup-capacity check → **WP6** docs batch.

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
- Requirements: SN-004 (recover older copy), SN-006 (historical restore),
  SR-005 (change-folder contract), SR-010 (historical restore) — all revised.
- Tests: every G2/G3 suite + Coverage.Tests assertion that references `Pre_*`.
- Docs: README "how it works" diagram + AGENTS pipeline steps 7/13/14.

**Proposed handling:** treat as a scoped change through the gate — (G1) revise
SN-004/006 + SR-005/010 to the new model and a migration/compat stance for
existing `Pre_*` backups; (G2) decompose to LLRs + tests; (G3) implement with an
independent review of the restore-path change. **Do not implement until the human
approves this framing.**

### Non-goals (assumed — confirm at G1)
Out of scope unless the human says otherwise: PowerShell 5.1 support, any GUI,
cloud/remote backup targets, and encryption-at-rest. **Added 2026-08-21
(human-approved):** opaque `.7z` archive-set storage (the old ToDo
"archive option") — rejected because it contradicts the model's core strength:
bytes stay ordinary files on disk, restorable by the self-contained bash kit
with no runtime. **Revised 2026-07-03
(human):** *non-Windows* is no longer a blanket non-goal — a **bash/Linux
restore** variant is in scope as phase `bash-v1` (SN-022), and a bash backup
engine is registered-but-deferred as `bash-v2` (SN-023). **Revised 2026-08-12:**
the engine stays *PowerShell*-only, but no longer Windows-only — it now also
runs on Linux inside the `container-v1` image (SN-024/SR-034); a *bash* backup
engine still awaits its own bash-v2 go-ahead.

## Scope (restated from the brief)

- **Goal:** Periodic, content-aware file backup with change tracking and
  self-contained reconstruction (xxHash128 dedup, optional 7-Zip, `MANIFEST.csv`,
  per-run change snapshots, standalone restore kit).
- **End user(s):** Technical Windows users / the author running scheduled or
  ad-hoc backups via `pwsh`; agents modifying the tool.
- **Active hats:** Stakeholder (the kit's current name for End User), UX/Docs,
  System Engineer, Software Engineer, Test Engineer. _Domain hat to consider: **Data-integrity/Storage** (hashing,
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
  invariant is traced SN→SR→LLR→TC with **0 orphans**; the check harness is
  wired to Pester + PSScriptAnalyzer and runs green locally and in CI; the
  architecture map reflects the real module/function layout.

## Gate Sign-offs

Drop `G-Release` only if this becomes a one-off; FileBackup ships versioned, so
keep it.

| Gate | End User | UX/Docs | System Eng | Test Eng | Human |
|---|---|---|---|---|---|
| G1 — Requirements/UX/Constraints | APPROVE (driver) | APPROVE (driver) | APPROVE (driver) | n/a | **APPROVE 2026-06-05** |
| G2 — Decomposition & Test Coverage | n/a | n/a | APPROVE (driver) | APPROVE (driver) | **APPROVE 2026-06-05** |
| G3 — Implementation | n/a | n/a | APPROVE (driver 2026-08-22) | APPROVE (driver 2026-08-22) | **APPROVE 2026-08-22** |
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
- `requirements/stakeholder-needs.md`: 12 core needs (SN-001..012) + 9 edge-case
  expectations (SN-013..021), each with priority + acceptance intent.
- `requirements/system-requirements.csv`: 27 measurable SRs (SR-001..027), each
  linked to ≥1 UN, with AcceptanceCriteria, Permutations (storage modes /
  compression / hash-freq), Priority, and Verification method. Test-verifiable
  SRs marked `Test`; mail SR-015 + onboarding SR-027 + degradation SR-020
  `Demonstration`; SR-016 (automation) + SR-019 (required deps) `Inspection`.
- `trace.py`: UN=21 SR=27, **0 UN-without-SR**. Remaining 52 orphans are all
  the expected SR→LLR/TC gaps that G2 will close (not G1 blockers).

Findings:
- [MINOR] SN-012 (first-run setup/docs) had no SR on first pass → added SR-027
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
  SN-004). Left SR-010 **Open** pending the human's intended semantics; did not
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
- `stakeholder-needs.md`: SN-004 (point-in-time snapshots, each fully restorable) +
  SN-006 (restore a dated snapshot byte-exact) revised to the new model.
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
  manual. Inherent to staging; current behavior matches SN-013 (fail loudly).
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

### DRIVER (System + Test Engineer hats) — kit re-sync 2026-07 — 2026-07-01
Verdict: APPROVE (driver) — process-tooling + docs change; no engine/restore
behavior touched (the only .ps1 edited is scripts/check.ps1). Pilot adoption
for the kit's Thread-27 core/optional split; friction fed back to ai-template.

Applied ai-template @ e4bcfb1 (Threads 24–28 + WI-1.3 since the 2026-06-09
sync), on branch `kit-resync-2026-07`:
- **Process split:** docs/process.md replaced with the current core (§1–§7 +
  applies-when summaries); new docs/process-options.md carries the expansions.
  This repo runs the stated **minimum profile** (rung 1, standalone).
- **Spine rename:** `user-needs.md`/UN-### → `stakeholder-needs.md`/SN-###
  (kit Thread 7); ids keep their numbers so older entries in this log still
  resolve. `SN-Refs` column renamed; CI job title updated. Historical evidence
  quotes ("UN=21…") left verbatim — they record what the tool printed then.
- **Harness:** trace.py/gen_release_checklist.py/gen_cases.py re-synced
  (verbatim kit copies); check_docs.py + check_perf.py adopted and wired into
  check.ps1 (steps 3 and 6) and CI; docs/gate (G3) is now the default -Gate
  source; .githooks/pre-commit added (map freshness + id integrity; opt-in via
  core.hooksPath); .gitattributes pins the hook to LF. Inert optional
  registries scaffolded: performance-budgets.csv (PB-000), procurement.csv
  (PART-000).
- **Not adopted, deliberately:** check_flows.py (would demand a hand-authored
  "Runtime flows" section; the generated Invoke-BackupSet flow + AGENTS.md §2
  pipeline already serve reviewable-flow duty — revisit if a concurrency-heavy
  change lands) and check_stubs.py (Python-only; would pass vacuously on a
  PowerShell tree). check.ps1 (not the kit's check.py) stays the single gate
  command: it is the one definition of passing this Windows/Pester repo runs
  locally and in CI.

Evidence (real output, local, post-upgrade):
- `pwsh scripts/check.ps1 -Tier Full` → lint PASS · trace PASS (SN=21 SR=28
  LLR=27 TC=47, orphans=0, integrity=0, status-findings=0) · doc navigability
  PASS (0 broken links) · generated docs fresh · Pester unit **48/48** ·
  perf-budgets PASS (inert) · integration **236 PASS / 0 FAIL / 4 SKIP** →
  "All steps passed." (identical totals to the pre-upgrade baseline).
- `sh .githooks/pre-commit` → exit 0.

**Open:** the pre-existing item stands — human G3 sign-off on the
implementation truth-up + snapshot redesign (this re-sync does not change that
scope). New minor: consider a PowerShell check_stubs equivalent and a
"Runtime flows" section as future hardening, not gate blockers.

<!-- agent-setup --> Agent setup (2026-07-02): agents=`claude`; skills materialized: downstream-resync, gate-advance, registry-hygiene. AGENTS.md remains the canonical, agent-neutral guide (skills are opt-in accelerators, not a process gate).

### Kit re-sync — 2026-07-02 — (prev: kit e4bcfb1, unstamped) → 9b697cc (WI-1.6..WI-1.12)

Kit-owned overwrites: docs/process.md (+ meta strip), docs/process-options.md,
scripts/trace.py (Attest vocabulary + assets.csv integrity). docs/kit-version
now exists (the pilot predated the stamp feature — first stamped state).
New: docs/requirements/assets.csv (inert), .claude/skills (3) + inert
settings.json.example, GEMINI.md stub, run.cmd.
Decisions (dial: recorded, reversible):
- run.cmd wired to `pwsh -NoProfile -File FileBackup.ps1` (README Quick-start
  flow; args pass through). POSIX run.sh/run.command not shipped (PS7/Windows
  product). RECONSTRUCT.bat remains the restore entry, unchanged.
- Bootstrap over-scaffold pruned to honor this repo's recorded "not adopted
  (deliberate)" stance: removed check.py/check.sh (check.ps1 stays the single
  gate), check_flows.py/check_stubs.py (recorded not-adopted), gen_arch_map.py
  (the .ps1 port is this repo's generator — bootstrap's initializer had
  clobbered the generated diagram with Python-AST output; reverted),
  pytest.ini, kit check.yml (tests.yml is this repo's CI), setup/dev-setup/
  onboard scripts (minimal-adoption stance), src/tests .gitkeep noise.
- .githooks/pre-commit kept as this repo's local adaptation (drives
  gen_arch_map.ps1); the kit's Scripts/-case fix is moot here (lowercase).
- CLAUDE.md gains decision dial (= HIGH: data-safety product — surface often;
  autonomous only for trivially-reversible non-engine work, recorded),
  commit-cadence rule, and the deliberate-subagent bullet.

### INDEPENDENT REVIEWER (sonnet subagent) + DRIVER verification — adversarial dedup/snapshot review — 2026-07-02
Verdict: CHANGES-REQUESTED (3 findings, all driver-reverified) — while the
primary adversarial question is APPROVED/confirmed.

Primary question (user-posed): file deleted → reintroduced identical → deleted
again ⇒ bytes stored exactly ONCE across backup root + Snapshot_* folders, all
dated states restorable. **CONFIRMED** twice independently: driver probe
(4 modes × 4-run timeline; copies=1 at every stage; 16/16 restore checks) and
reviewer probe (4 modes × 5-run timeline incl. second reintroduce; copies=1 at
every stage; 16/16 restores). Mechanism: reintroduce briefly makes a transient
second copy (Invoke-BackupFileGroup checks only the live manifest for reuse) but
Optimize-ChangeFolders collapses to one copy in the same pipeline pass, blanking
the losing DataPath rows, which recover by (hash,length) — verified two levels
deep. Pinned as TC-049 / Coverage.Tests "Re-deleted content stored once across
snapshots" (commit c930f4f). Adjacent probes also clean: shared-content paths
deleted at different times (refcount correct), same path returning with a
different size (distinct group, no cross-contamination).

Findings (per §5; owners to act only after human direction — engine surface):
- [MAJOR] SR-005 area → a run whose ONLY manifest change is a duplicate-content
  add or a shared-content removal produces NO snapshot: `Complete-ChangeFolder`
  gates on `$ChangedCount`, which increments only on physical copy/evict I/O
  (Invoke-BackupFileGroup new-copy branch; Move-RemovedFilesToStaging eviction),
  not on manifest-only changes (dedup reuse branch; still-referenced skip). The
  preceding state is then permanently unrestorable, logged misleadingly as "No
  prior state superseded". Repro: probe6 (add B.txt duplicating A.txt ⇒ no
  Snapshot_D0). G9 misses it because its dup-delete co-occurs with a content
  modify. → Suggested: gate snapshot creation on a real manifest diff, not byte
  I/O; extend G9/TC with a manifest-only-change run. → @SoftwareEngineer
- [MAJOR] SN-013/SR-009 area → `Reconstruct.ps1` completes with exit 0 when a
  row''s bytes cannot be recovered (logs "WARN: cannot recover … skipping").
  A scripted/CI restore checking the exit code sees success on an incomplete
  tree — violates the fail-loudly principle. Repro: probe4 (delete the snapshot
  holding the sole physical copy; restore of the older snapshot exits 0 with the
  file silently missing). → Suggested: aggregate unrecovered-row count ⇒ nonzero
  exit (+ summary line), document snapshot folders as load-bearing. → @SoftwareEngineer
- [MINOR] SR-022 area → `Test-IsInfrastructureFile` allowlist omits the
  `RECONSTRUCT.paths.json` sidecar that New-ReconstructScript writes ⇒ two false
  [WARN]s per run in backup.log (orphan/unreferenced). Confirmed in probe logs.
  → Suggested: add the sidecar name to the `$infra` list + TC for no-WARN run.
  → @SoftwareEngineer

Evidence: reviewer probes probe1/2/4/5/6 (scratchpad, repo untouched) re-run by
driver for findings 1–2; finding 3 confirmed in code (`$infra` list) and driver
probe backup.log. New TC-049 test PASS; `check.ps1 -Tier Smoke` green after
pinning (49 unit); trace: SN=21 SR=28 LLR=27 TC=48, 0 orphans, 0 findings.
**Next action (human):** approve the three fixes as a scoped change through the
gate (SR/LLR/TC revisions for findings 1–2 are requirement-level, not patches).

### HUMAN — review-findings scoped change — 2026-07-02
Verdict: APPROVE ("That all sounds appropriate, please proceed") — fix the three
2026-07-02 review findings as a scoped change through the gate.

### DRIVER (System + Software + Test + Data-integrity hats) — REVIEW-FINDINGS G1→G3 — 2026-07-02
Verdict: implemented + validated; independent review APPROVE (below). Awaiting
human ratification.

G1 (requirements): SR-005 rewritten — the supersession criterion is a **manifest
diff** (any added/removed/changed row, incl. dedup-served adds and shared-content
removals), not physical byte I/O; permutations extended with
change=set{content,dup-add,shared-removal,noop}. New **SR-029** (SN-013):
Reconstruct restores everything recoverable, then fails loudly (non-zero exit)
naming the unrestored count; clean restores exit 0. Finding 3 needed no SR change
(SR-022 already covers it — implementation gap only).

G2 (decomposition): LLR-005 revised (gate = Compare-SourceToBackup diff
non-empty); new LLR-029 (unrestored-row accounting + terminal throw); LLR-022
extended (allowlist covers every deployed kit artifact). New TC-050 (manifest-only
change ⇒ snapshot; no-op ⇒ none), TC-051 (fail-loudly restore), TC-052 (no false
sidecar WARNs). Trace: SN=21 SR=29 LLR=28 TC=51, 0 orphans / 0 integrity.

G3 (implementation):
- Engine: Invoke-BackupSet computes $manifestChanged from the diff and passes
  -ManifestChanged to Complete-ChangeFolder (replaces the -ChangedCount gate;
  the byte counter remains for logging). Skip log now states why (first backup
  vs manifest-identical no-op). Gotcha hit + documented in code: `@()` around a
  List reached via a PSObject property throws "Argument types do not match" on
  PS 7.5 — use .Count directly.
- Reconstruct.ps1: $unrestored list collects every skip (hash-recovery failure,
  missing DataPath, extraction failure); after restoring all recoverable rows a
  non-empty list logs ERROR and throws "Reconstruction INCOMPLETE: N file(s)…"
  (⇒ exit 1 via pwsh -File and RECONSTRUCT.bat).
- Engine: RECONSTRUCT.paths.json added to the Test-IsInfrastructureFile allowlist.

Evidence (real output, local): both original repros re-run — dup-add now creates
Snapshot_<D0> with both states individually restorable; tampered restore exits 1
with the INCOMPLETE error. Driver edge probe: 0-byte files through
shared-removal/delete/re-add cycles — all snapshots + latest restore correctly,
no spurious throw. `check.ps1 -Tier Full` → lint PASS · trace 0/0/0 ·
docs fresh · Pester **52/52** · integration **236 PASS / 0 FAIL / 4 SKIP**.

### INDEPENDENT REVIEWER (sonnet subagent) — REVIEW-FINDINGS G3 — 2026-07-02
Verdict: **APPROVE** (0 defects; 1 cosmetic nit, fixed). Fresh-context probing of
the three fixes: no false-positive snapshot from layout migration (3-run
Mirror→HashAddressed+Compress→Mirror cycle ⇒ 0 snapshots; Sync-BackupStorageLayout
mutates only DataPath/Compressed/StoredAsHashSize, never the diffed fields) or
forced rehash (freq=A rehash leaves hash/mtime identical); no false-negative
escape constructed; hypothesized [long]0 empty-file throw does not occur
(Import-Csv yields string "0" — truthy; end-to-end blank-DataPath 0-byte rows
hash-recover cleanly); throw semantics verified via pwsh -File AND the generated
RECONSTRUCT.bat (clean=0, tampered=1, multi-failure message accurate, partial
tree preserved); PS 7.5 @()-on-List workaround independently reproduced. Ran
52/52 unit, Mirror full-group sweep 59/0/1, lint 0, trace 0/0/0, Smoke tier all
green. Nit: test-cases.csv trailing newline — restored by driver.

### DRIVER (UX/Docs hat) — demonstration tooling — 2026-07-03
Autonomous (trivially-reversible, non-engine; recorded per the HIGH dial):
added `scripts/demo_timeline.ps1` — a narrative Demonstration artifact that
drives a create/modify/remove/re-add/no-op timeline and emits a legible,
timestamped Markdown report (source events → backup outcome → restore +
xxHash128 byte-compare verification → point-in-time reconstruction of every
snapshot). Human-requested ("see that timestep in motion"). Not a gate test;
the gated suites remain authoritative. First run: Overall PASS (5 runs,
3 snapshots). Lint clean.

**Open scope question (human):** a bash/Linux variant (restore-first) was
discussed 2026-07-03 — would reverse the recorded "non-Windows" non-goal, so
it needs a G1 scope revision before any code. Awaiting explicit go-ahead.

### HUMAN — bash/Linux variant — 2026-07-03
Verdict: APPROVE — "Yes run the G1 pass, and then create a detailed plan file
for restructuring that I can hook Opus into to perform the convert, then I''ll
come back here to perform the final review and cross-check." Reverses the
non-Windows non-goal for the restore path.

### DRIVER (Stakeholder + System Engineer hats) — BASH-VARIANT G1 (+G2 skeleton) — 2026-07-03
Verdict: APPROVE (driver) — G1 artifacts registered; executing-agent handoff
plan written; awaiting the converted implementation, then human cross-check.

What changed (docs/registries only — no engine code):
- stakeholder-needs.md: SN-022 (restore on Linux from the backup folder alone,
  bash-v1) + SN-023 (Linux-produced interoperable backups, bash-v2, deferred).
- system-requirements.csv: new optional **Phase** column (blank = always in
  scope, per trace.py "Phased delivery"); SR-030 hash conformance, SR-031
  standalone bash restore (full SR-008/010/009/023/029 semantics), SR-032
  manifest portability — Draft, Phase=bash-v1; SR-033 bash backup-engine
  parity — Draft, Phase=bash-v2.
- Skeleton decomposition so the tree stays green between now and the convert:
  LLR-030..033, TC-053..057 (Draft; the executing agent refines at its G2).
- check.ps1 + CI trace step: `--require-verified --phase core` — deferred-phase
  SRs are exempted EXPLICITLY and counted (phase-deferred=4), so the G3 ratchet
  stays armed for everything already shipped. When bash-v1 lands, the phase
  list becomes `core,bash-v1`.
- **docs/plans/bash-variant-plan.md** — the executing-agent work order: pinned
  on-disk contract (manifest dialect, ''O'' dates, hash canonical form, snapshot
  regex, authority/pool rules, sidecar caveat, layout-detection + single-file
  decisions), deliverables/layout, fixtures strategy, bats + ubuntu +
  cross-artifact CI plan, commit-ordered work items, out-of-scope fence, and
  the §7 acceptance checklist the human will cross-check against.

Evidence (real output, local): `trace.py --strict --require-verified --phase
core` → SN=23 SR=33 LLR=32 TC=56, **0 orphans / 0 integrity / 0 status
findings / 4 phase-deferred**, exit 0.

### DRIVER (System + Test Engineer hats) — BASH-VARIANT bash-v1 G2 refinement — 2026-07-03
Verdict: APPROVE (driver) — registry-only refinement; no engine code touched.
Executing [plans/bash-variant-plan.md](plans/bash-variant-plan.md) end-to-end.

**De-risking (plan §6 step 3) done FIRST — hash conformance CONFIRMED.** Acceptance
environment is **WSL Fedora 40** (`podman-machine-default`; `dnf`-installed xxhash
0.8.3 / p7zip / bats / shellcheck; gawk present) — a real Linux run, not Git Bash.
Probed empty / one-byte / 20-byte-text / 100 KB-random inputs: `xxh128sum <f> |
cut -d' ' -f1` uppercased **equals `Get-FileXxHash` byte-for-byte** in every case.
The whole phase's pivot risk is retired before any implementation.

What changed (registries only):
- LLR-030/031/032 refined off their skeletons to honor the plan's **pinned
  self-containment decision**: the hasher (`hash_file`), CSV parser
  (`parse_manifest`), and path mapper (`to_posix_path`) are functions **inside the
  single `bash/reconstruct.sh`** (no `source`d runtime libs); a bottom-of-file
  `main` guard lets bats source the script to unit-test those functions. The prior
  skeleton wrongly located them in a `bash/lib/common.sh` — corrected (ids kept).
- TC-053..056 already carried dimensional Parameters/Expected from G1 skeleton;
  left as-is (they match the deliverables).

Evidence (real output, local): `python scripts/trace.py --strict --require-verified
--phase core` → SN=23 SR=33 LLR=32 TC=56, **0 orphans / 0 integrity / 0 status
findings / 4 phase-deferred**, exit 0. SR-030/031/032 remain Draft (flip at G3
with the real green Linux run). Next: fixtures + `reconstruct.sh` (plan §6 2–5).

### FINDING (surfaced by bash-v1, PS-side — recorded, NOT fixed per plan §6) — SR-010/SR-022 — 2026-07-03
[MAJOR — for the human] **`Reconstruct.ps1`'s `Find-DataFileByHash` over-skips
infra-named files recursively, so a nested user file named like an infrastructure
file (regression B6) becomes UNRECOVERABLE from a Mirror-mode snapshot.** The
pinned contract (plan §2; AGENTS.md §3 "Infrastructure files are root-level only")
says the infra-name skip is **root-level only** — a nested `sub\MANIFEST.csv` is
data. But `Find-DataFileByHash` applies its `^(MANIFEST|RECONSTRUCT|FileBackup\.Common|System\.IO\.Hashing|FileBackupState)`
skip to **every** file in a `-Recurse` scan. When such a file is unchanged across
runs, `Optimize-ChangeFolders` blanks its DataPath in each snapshot (bytes recover
by hash) — but the only surviving copy is the Mirror-layout data file named
`sub\MANIFEST.csv`, which the recursive skip excludes ⇒ the row is reported
unrestorable and the snapshot restore FAILS LOUDLY (SR-029 exit 1). Reproduced on
the bash-v1 fixture timeline (Mirror + Mirror+Compress; HashAddressed is immune —
its data files carry short-names, not `MANIFEST.csv`). Driver-verified: with a
**root-level-only** skip (the contract) the same row recovers cleanly.
- **Scope call:** engine/restore surface → per plan §6 "record it in status.md and
  **stop** on that item rather than fixing the Windows side unilaterally." Not
  fixed here. Suggested PS fix (for the human): make the recovery skip root-level
  only (parent == search-folder root), matching the contract; add a G9 assertion
  that restores a Mirror snapshot holding a blanked nested-infra-named row.
- **bash-v1 stance:** `reconstruct.sh` implements the **contract** (root-level-only
  skip), so it restores these fixtures correctly. This is a deliberate,
  documented divergence from the current PS code (which has the bug), not from the
  contract — recorded in LLR-031 and the README.

### DRIVER (Test Engineer hat) — BASH-VARIANT bash-v1 fixtures — 2026-07-03
Autonomous (test-scaffolding, non-engine; recorded per the HIGH dial). Added
`scripts/gen_bash_fixtures.ps1` — drives the **real engine** over a fixed,
deterministic 3-run timeline (pinned `-BackupTime`, fixed bytes + mtimes) to emit
the committed golden fixtures under `tests/fixtures/`:
- `hash-conformance/` — empty / one-byte / text / unicode-named / >1 MiB binary +
  `expected-hashes.csv` (golden `Get-FileXxHash`). The 1 MiB binary is SR-030's
  explicit "binary >1 MiB" multi-buffer case (regenerable, so drift is reviewable).
- `bash-restore/<mode>/` (all 4 modes) — `backup/` + nested `changes/Snapshot_*` +
  `expected/<origin>.tsv` (posix-relpath⇢content-hash from each origin's own
  manifest = the independent restore oracle). Timeline covers dedup, a modified
  file (v1↔v2 point-in-time), delete→identical-re-add (⇒ 16 blank-DataPath rows
  recovered by hash), a 0-byte file, unicode / bracketed / comma-bearing names,
  and a nested `sub/MANIFEST.csv` (B6). Committed copies are stripped of the
  large/churny Windows kit (DLL/psm1/RECONSTRUCT.*) + logs and carry a stabilized
  Windows-path sidecar (proves reconstruct.sh ignores it on Linux). Total ~1.2 MB
  (≈1 MB is the conformance binary); `-Fresh` keeps everything for the CI interop
  job. Fixtures regenerate deterministically (EXIT=0, all 4 modes, 2 snapshots each).

### DRIVER (Software + Test + Data-integrity hats) — BASH-VARIANT bash-v1 G3 — 2026-07-03
Verdict: implemented + validated on real Linux; independent review below.
Delivered `bash/reconstruct.sh` — one self-contained POSIX-shell restorer
mirroring `Reconstruct.ps1` against the same MANIFEST.csv contract:
- `hash_file` (xxhsum/xxh128sum → 32-char UPPER hex), `parse_manifest` (gawk
  FPAT RFC-4180; \x1f-delimited output so an empty leading DataPath is NOT
  trimmed — the key parse bug found + fixed), `to_posix` (`\`→`/`).
- folder-name authority/layout detection (origin = `--from`, default PWD; a
  Windows-path sidecar is ignored when it doesn't resolve; explicit
  `--backup-root`/`--change-root` > sidecar > auto-detect); data-pool hash
  recovery over snapshots+backup-root; 7z **dir-extract + first-file** (a shared
  dedup archive can hold >1 identical-content entry — `-so` streaming would
  concatenate them, the second bug found + fixed); capacity + target-inside
  guards; **fail-loudly** non-zero exit naming the unrestored count.
- **Contract-faithful divergence:** root-level-only infra skip (recovers the
  nested B6 `sub/MANIFEST.csv` that the PS recursive skip drops — see the FINDING
  above).

Evidence (REAL runs):
- **WSL Fedora 40 (real Linux, plan's accepted env):** `bats tests/bash/` →
  **22/22 ok**; `shellcheck` clean on reconstruct.sh + helpers + verify_restores.
- Adversarial probes (driver): root restore with `changes/` deleted → 0;
  snapshot restore with a sibling snapshot deleted → 0; bad origin → 2; bogus
  `--seven-zip` on a compressed backup → dies with remediation (2); leading-dash
  filename → restored; `--help` → 0; unknown arg → 2.
- **Windows suite untouched:** `pwsh scripts/check.ps1 -Tier Full` → lint PASS ·
  trace **SN=23 SR=33 LLR=32 TC=56, 0 orphans / 0 integrity / 0 status-findings /
  1 phase-deferred** (`--phase core,bash-v1`) · docs PASS · arch-map PASS ·
  Pester **52/52** · perf PASS · integration **236 PASS / 0 FAIL / 4 SKIP** →
  "All steps passed."
- SR-030/031/032 → **Verified**; TC-053..056 → **Pass**; LLR-030..032 →
  **Verified**. Ratchet re-armed in `check.ps1` + CI (`--phase core,bash-v1`).
- CI: new `bash-restore` (ubuntu bats + shellcheck) and `bash-interop-make/
  -restore` (windows makes fresh 4-mode backups → ubuntu restores every origin
  and byte-compares) jobs added; they run on push (the human's final review is
  the acceptance gate).

Nothing from the plan's "explicitly out" list was started (no kit bundling of
reconstruct.sh, no bash-v2 engine, no engine-behavior change — the one PS defect
found is recorded above, not fixed). **Open:** independent review (below), then
human final review + cross-check against the plan §7 checklist.

### INDEPENDENT REVIEWER (fresh-context subagent) — BASH-VARIANT bash-v1 — 2026-07-03
Verdict: **APPROVE** (2 MINOR + 2 NIT; both MINORs are shared with Reconstruct.ps1).
Ran on WSL Fedora 40 (real Linux): reproduced 22/22 bats + shellcheck clean, then
~20 adversarial scenarios. **Could not reach any silent wrong-bytes restore, nor
any exit-0-incomplete case for an uncorrupted manifest** — the load-bearing safety
property holds. Confirmed sound: the empty-leading-DataPath `\x1f` parser fix (16
blank-DataPath rows recover end-to-end), the 7z multi-entry dir-extract fix (the
shared dedup archive genuinely holds 2 entries / 26 bytes → 13-byte payload
written, both dups byte-exact), and the root-level-only infra skip in BOTH
directions (root-level `FileBackupState.json` skipped; nested `sub/MANIFEST.csv`
used as data). A same-length/wrong-hash pool file is correctly rejected, not
grabbed. All exit codes correct; special-glyph HashAddressed short-names and
leading-dash names restore byte-exact across 4 modes × root+2 snapshots.

Findings + driver disposition:
- [MINOR] a `..`-escaping RelativePath wrote above the target and exited 0;
  [MINOR] a corrupt (non-CSV) but non-empty manifest restored nothing yet exited
  0. Both are fail-loudly/defense-in-depth gaps that **Reconstruct.ps1 shares**
  (not bash regressions). **Driver FIXED both on the bash side** (non-engine,
  trivially-reversible; the traversal guard matters for the "restore a foreign
  backup on a rescue USB" threat model): reconstruct.sh now (a) refuses any row
  whose destination canonicalizes outside `--target-root` (counted unrestored ⇒
  exit 1) and (b) validates the manifest header carries `RelativePath`+`xxH2Hash`
  (a legitimately empty backup still has the header) ⇒ exit 2 on a corrupt file.
  New bats: "refuses a path-traversal RelativePath", "corrupt MANIFEST.csv fails
  loudly" (now **24/24** green, shellcheck clean). **For the human:** the SAME two
  gaps exist in `Reconstruct.ps1` — left unfixed per plan §6 (no unilateral engine
  change); recommend tracking them against the Windows restorer too.
- [NIT] non-blank-DataPath rows are copied without re-hashing (authoritative per
  the contract; matches PS) and [NIT] blank-vs-whitespace DataPath handling
  (engine never emits whitespace-only) — noted, no change.

**bash-v1 is complete and green; awaiting the human's final review + cross-check.**

### HUMAN — Find-DataFileByHash root-level-only fix — 2026-07-03
Verdict: APPROVE — "You can proceed with option a right now." Confirmed the
`MANIFEST.csv` naming convention itself is fine and needs no change: the
requirement (SR-022, root-level-only) was already correct; the defect was the
restore-path scanner re-implementing the skip recursively. Also clarified the
manifest-as-source-of-truth stance: on a standard restore no re-hashing/
extraction-to-verify is wanted — restore-time hashing is legitimate only as
*lookup* on the blank-DataPath recovery path (the hash is the address, not a
check). Consequence recorded for the option-(c) design sketch (manifest-built
recovery index): its "verify-on-hit" re-hash should be a **configurable**
integrity option (like the legacy stability cross-check provision), off by
default — not mandatory as the driver first proposed. Option (c) itself remains
a future, gated candidate — not scheduled.

### DRIVER (Software + Test + Data-integrity hats) — Find-DataFileByHash fix (SR-022/SR-010) — 2026-07-03
Verdict: implemented + validated (human-approved scope, above). One-line-class
fix on the restore surface, test-first:
- **Red first:** new Pester test (TC-058) written before the fix and run against
  the unfixed code — failed with exactly the predicted defect: "Reconstruction
  INCOMPLETE: 1 file(s) could not be restored: sub\MANIFEST.csv".
- **Fix:** `Find-DataFileByHash` (Reconstruct.ps1) now applies the infra-name
  skip only to files directly in each search folder's root (normalized-path
  parent comparison), matching SR-022/AGENTS.md §3 and `reconstruct.sh`. The
  skip is documented in-code as a scan optimization, never a correctness gate
  (matching is by (hash,length)).
- **Registry:** TC-058 added (Verifies SR-022;SR-010;LLR-010, Pass); LLR-010
  detail + TestRefs extended. Stale "deliberate divergence" notes retired in
  AGENTS.md §4, bash/reconstruct.sh header, and restore.bats (both restorers now
  match the contract identically).
Evidence (real output, local): red-first fail pasted above; post-fix
`check.ps1 -Tier Full` → lint PASS · trace **SN=23 SR=33 LLR=32 TC=57,
0 orphans / 0 integrity / 0 status-findings / 1 phase-deferred** · docs PASS ·
arch-map PASS · Pester **53/53** · perf PASS · integration **236 PASS / 0 FAIL /
4 SKIP** → "All steps passed." Linux side re-validated: shellcheck clean,
bats **24/24** (WSL Fedora 40). Note: Reconstruct.ps1 is engine-deployed — the
fix ships in every new backup's kit; existing backups restore correctly by
re-running restore from an updated kit copy if they ever hit the nested-infra
case.

### HUMAN — repo cleanup: legacy artifacts — 2026-07-03
Verdict: APPROVE (all three scopes, via AskUserQuestion): (1) delete the
superseded engine artifacts + pre-history notes; (2) delete BOTH standalone
personal-utility folders (`Auxilary/`, `DatabaseDuplicateDeletion/` — no longer
in use); (3) delete tracked `.idea/` and gitignore it. Context: the human's own
memory of which old scripts were still live was unclear and the leftovers were
creating confusion.

### DRIVER (UX/Docs hat) — repo cleanup executed — 2026-07-03
Deleted (all recoverable from git history — `git log --diff-filter=D --summary`):
- Superseded pre-modularization: `Test-Backup.ps1`, `RunTests.bat`,
  `TestRelated/` (FileBackupTestReset.ps1, Tests.xlsx), `PrepPropertiesFile.ps1`.
- Pre-history notes for the OLD SHA-256/HashTable.csv system: `FullPrompt.txt`
  (the original generation prompt), root + Auxilary `ScratchPad.txt`/`ToDo.txt`,
  `Auxilary/BackupMethodBreakdown.txt`, `Auxilary/BackupTestCases`.
- Personal utilities (human confirmed no longer used): `Auxilary/*.ps1` ×4,
  `DatabaseDuplicateDeletion/*.ps1` ×3.
- `.idea/` (IDE-private; now gitignored).

**Backlog preserved from the deleted root ToDo.txt (Nov 2025)** — the only two
ideas not already realized by the current implementation:
1. *Archive option:* optionally store a backup as `.7z` archive sets (full
   snapshot at a configured interval, diffs between), with a rebuild script per
   folder. (The dated-snapshot model realized the diff/point-in-time half.)
2. *CloneSpy CRC export:* an option to emit a CloneSpy-compatible CRC list per
   backup set.

Docs refreshed: AGENTS.md §7 rewritten as a removal record (§ numbering kept);
README repo-layout block updated to the current tree (adds `bash/`, `scripts/`,
`docs/`; drops deleted entries) and the stale personal-tools note removed;
check.ps1 lint comment updated; `.gitignore` gains `.idea/` and simplifies the
`BuildAlbum/` rule. **NOT deleted (flagged to human):** untracked `BuildAlbum/`
(23 MB personal photos/videos in the working folder — unrecoverable if deleted,
so left in place and kept gitignored; human to move/delete it manually if
stale).

### HUMAN — evaluator launchers (run.cmd / run.sh) — 2026-07-03
Verdict: APPROVE (direction) — make the repo ai-template compatible: ship BOTH
`run.cmd` and `run.sh`, and have them "trigger the standard test run on a
virtual / created run, instead of attempting to run a formal defined backup."
**Reverses two 2026-07-02 kit re-sync decisions** (run.cmd → FileBackup.ps1;
POSIX run.sh not shipped).

### DRIVER (UX/Docs hat) — evaluator launchers rewired — 2026-07-03
Per the kit's evaluator-rung convention (process.md §7: one readable command per
launcher, zero recall required):
- **run.cmd** → `pwsh -NoProfile -File scripts\demo_timeline.ps1`: the
  self-contained demonstration — scratch source tree under `%TEMP%\FileBackupDemo`,
  a create/modify/remove/re-add/no-op timeline through the REAL engine, restore
  of the latest state + every dated snapshot, xxHash128 byte-verification, and a
  narrative TimelineReport.md. No config file; nothing outside temp touched.
  Args pass through (`-Mode HashAddressed -Compress`).
- **run.sh** (new) → `bash tests/bash/verify_restores.sh tests/fixtures`: the
  Linux product surface (the engine is Windows-only) — restores every origin of
  the four committed real-engine fixture backups into a mktemp dir and
  byte-compares each file; friendly tool preflight with install remediation.
  Executable bit set (100755); shellcheck clean.
- README gains a "Run it (no setup)" section documenting both underlying
  commands; repo-layout block lists the launchers; `.gitattributes` pins
  `*.cmd`/`*.bat` to CRLF (LF-only batch can break cmd.exe).
Evidence (real runs): demo_timeline → "**Overall: PASS** — 5 runs, 3 snapshots,
every state restored and byte-compared", exit 0 (Windows). run.sh → "verified
12 origin(s); 0 failing", exit 0 (WSL Fedora 40). check_docs → 44 links,
0 broken.

### DRIVER (System + Test hats, subagent-assisted audits) — frontier truth-up & registry back-fill — 2026-08-21
**Trigger:** human asked whether the frontier of work is properly documented
after the 2026-08-12 commits (ec43711/6b1484c/bf2ccd0/d5f8894). Two independent
audits (an Opus documentation audit + an adversarial frontier review) confirmed
those four commits changed the engine/restore surface and shipped a container
runtime **without touching this blackboard, without gate records, and with new
engine behavior carrying no requirement rows** — under the HIGH decision dial.

**Back-fill performed (registry + code annotations, awaiting human
ratification):**
- New **SR-035** (run-state integrity gate — HomeHub finding F), **SR-036**
  (empty-source delete-all refusal + `AllowEmptySource` — finding G),
  **SR-037** (cross-platform tool discovery — finding 0, Verification=
  Inspection), with **LLR-035..037**.
- **SR-009/LLR-009 extended** to the path-traversal refusal (the first of the
  two 2026-07-03 reviewer MINORs, silently fixed in `Reconstruct.ps1`
  2026-08-12); its sibling — **corrupt non-CSV MANIFEST.csv still restores
  nothing and exits 0 on the PS side** — remains OPEN and is now tracked in
  *Open items* (bash validates the header and exits 2; live divergence).
- New **TC-061..065** pinning the already-shipped `Safety.Tests.ps1` and
  `Coverage.Tests.ps1` tests (state gate ×2, empty source, dependency
  preflight, traversal) + the SR-037 inspection.
- `Safety.Tests.ps1` Describe/It names annotated with SR ids;
  `# Implements:` back-links added in Engine (`Invoke-BackupSet`),
  `Reconstruct.ps1` (restore loop), and `Common.psm1` (tool discovery).
- Current State header updated (2026-08-12 block, revised Non-goals wording,
  corrected interfaces claim); new **"Open items (frontier)"** section minting
  C/D/E/H/I/J, the corrupt-manifest guard, ext-list merge, backup-side
  capacity check, container release-verification (CI runs BuildAndTest only —
  Export/Publish/Pull unexercised), the IF-001 config-contract gap (no JSON
  schema/validation/test; single-set-only mounts), release-checklist staleness,
  interfaces.md boilerplate, and doc drift — each with dependency/blocking
  notes.

**On the remembered "codex" adversarial review:** no artifact, commit, or log
entry named codex exists (`grep -ri codex`, `git log -S/--grep` all empty). The
memory maps to the recorded adversarial passes (2026-07-02 dedup/snapshot —
closed; 2026-07-03 bash-v1 reviewer — one finding still open, the
corrupt-manifest gap above; 2026-08-09 HomeHub cross-check — findings tracked
here).

**For the human:** ratify (or amend) this back-fill plus the unratified
2026-08-12 work — including the `reconstruct.sh` bundling decision that was
implemented without an approval record — and prioritize the Open-items table;
**E** (independent restore witness) is the standing design question.
Evidence of the post-back-fill green is recorded in the Current State header.

### HUMAN — frontier dispositions approved — 2026-08-21
Verdict: APPROVE ("Yes that sounds good, feel free to proceed to fill the
frontier with these decisions") for the driver's per-item review of the Open
items against the queued work and the project vision (data safety is the
product; HomeHub consumes the engine via container/IF-001; restore must never
need a runtime). Approved substance, now recorded in the Open-items table:
- **Two conflicts found and resolved.** (1) Item **I**: pure delegation of
  retention to HomeHub was unsafe — external pruning of a `Snapshot_*` folder
  can delete the only physical copy of bytes other snapshots recover by hash
  from the shared pool. Split: HomeHub owns retention *policy*, FileBackup owns
  the *mechanism* (planned `Prune-Snapshot` verb, WP4, own SR); IF-001 now
  forbids direct snapshot-folder deletion. (2) **Ext-list merge** is not a
  drive-by: it flips existing `.7z` rows "wrong" under
  `Sync-BackupStorageLayout`'s config comparison, exercising the untested
  migration path finding **C** covers — sequenced after C's repro test (WP5).
- **WP1 bundling:** E (manifest witness sidecar: row count + xxHash128 of
  manifest bytes, atomic, per-snapshot, verified by BOTH restorers) +
  corrupt-manifest guard (subsumed by the witness) + D/exit-code table
  (baseline = bash's existing exit 2) + J — one gated pass, one independent
  review, one kit revision instead of four.
- **Rulings:** one BackupSet per container invocation (recorded in IF-001;
  multi-set stays a native-Windows convenience); archive-option storage
  REJECTED into Non-goals; H stays delegated (optional `ExpectedSentinel`
  hardening later); CloneSpy export stays parked.
- **Order:** WP1 restore trust → WP2 config contract → WP3 container
  release-verify + ratchet re-arm → WP4 retention mechanism → WP5 C/ext-list/
  capacity → WP6 docs batch — all after Next-action (a)–(c) ratification.

### DRIVER (UX/Docs hat) — frontier dispositions recorded — 2026-08-21
Open-items table rewritten with per-item dispositions + WP1–WP6 order; IF-001
contract text extended (one-set-per-invocation; no direct snapshot deletion;
retention policy/mechanism split); Non-goals gains the archive-option
rejection. Registry/doc-only change — no engine code touched; WP1's SN/SR
minting still goes through its own G1 when scheduled.

### DRIVER (Test hat) — test-harness fix: Subst free-letter probe — 2026-08-22
The first post-hardening Full-tier attempt failed 32 integration assertions,
all environmental: this machine holds disconnected-but-remembered network
mappings (`X:`/`S:` → MINI-SERV shares). `New-SubstEnv`'s free-letter probe
(`Test-Path "X:\"`) returns **False** for such a letter, so the harness
claimed `X:`, its `subst` lost silently to the remembered mapping, and every
volume-backed write hit the dead share ("user name or password is incorrect").
Fix (tests/Common/VolumeBackend.ps1): the probe now also excludes every
`Get-PSDrive -PSProvider FileSystem` name (which lists disconnected mappings)
before the `Test-Path` check. Test-scaffolding-only change, decided
autonomously per the decision dial; the user's remembered mappings were left
untouched. Evidence: rerun below.

### HUMAN — (a)–(c) ratified; WP1–WP6 grind authorized — 2026-08-22
Verdict: APPROVE. The human directed "spin up opus and sonnet agents as
appropriate to grind through the queue to completion" and confirmed via
explicit prompts: (1) that instruction **counts as ratification of
Next-action (a)–(c)** — G3 sign-off, bash-v1 final-review acceptance, and the
2026-08-12 hardening + container work with its 2026-08-21 registry back-fill
(incl. the `reconstruct.sh` bundling decision) — contingent on the pending
Full tier coming back green; and (2) WP-level gate pauses are handled by
**batch ratification** — agents drive each WP through its gates with driver +
independent-reviewer approvals and pasted evidence, and all human gate
sign-offs are collected in one batch at the end of the queue.
Evidence (real output, 2026-08-22, post-harness-fix): `check.ps1 -Tier Full`
→ PSScriptAnalyzer PASS · trace **SN=24 SR=37 LLR=36 TC=64, 0 orphans /
0 integrity / 0 status-findings / 2 phase-deferred** · Pester unit **65/65** ·
integration **236 PASS / 0 FAIL / 4 SKIP** → "All steps passed." The G3 row in
Gate Sign-offs is marked APPROVE 2026-08-22 accordingly.
