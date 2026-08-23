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
> is the thin, human-readable pointer over that CSV (rewritten 2026-08-23, WP6).

> **Naming caution.** The kit's **gates** are `G1, G2, G3, G-Release, G-Final`.
> FileBackup's existing test **groups** are `G1…G9` (storage-mode suites in
> `tests/Run-All.ps1`) — a *different* namespace. Don't conflate them.

---

## Current State

- **BATCH RATIFICATION: human-RATIFIED 2026-08-23** (via the ratification
  worksheet, artifact `d48d6e78`; recorded in the audit entry below): WP1,
  WP2, WP4, WP6; WP5 with both residuals on the recorded re-review APPROVE;
  WP3's implementation pending its own CI evidence; the adversarial-review
  hardening batch (`83cc5f1`) together with its review-fix landing
  (`31a55f2`) on the recorded CHANGES-REQUESTED→landed trail. **The push of
  `resync_v2` is now unblocked.** Not decided in this ratification: the
  dangling/blank-DataPath prioritization and the parked-findings acceptance —
  realism verification for those is in flight; they remain Open below.
- **Active gate:** G3 (retrofit truth-up **human-APPROVED 2026-08-22**; the
  gate stays G3 while the WP1–WP5 scoped changes run their own G1→G3 passes.
  **WP6 (this batch) is now done — the whole WP1→WP6 queue has landed.** The
  next human action is the **batch ratification** covering WP1/WP2/WP4/WP5's
  review-accepted findings, WP3's implementation pending its own CI evidence,
  and WP6's docs, followed by **the push** (WP3's container CI job and the
  bash-interop job have not run on `resync_v2` yet — see WP3's row). Advance
  to G-Release only after that ratification.)
- **Latest verified run (2026-08-23, Full tier, post-WP5 **review fixes**,
  `--phase core,bash-v1` unchanged pending container CI):**
  **316/316 Pester unit, lint clean, trace SN=30 SR=52 LLR=51 TC=101 with
  0 orphans / 0 integrity / 4 phase-deferred, integration 372 PASS / 0 FAIL /
  4 SKIP**, plus **bats 55/55 and `shellcheck -S warning bash/reconstruct.sh`
  clean** on real Linux (WSL). `check.ps1 -Gate G3`
  reports **exactly one status-finding** — SR-052 is honestly `Implemented`
  because TC-101's Linux half (the SR-023 restore capacity check firing
  in-container) cannot run without Docker; see the WP5 audit entry and the
  `TODO(WP5, same CI run)` in `scripts/check.ps1`.
- **WP1 (restore trust & diagnostics) is implemented, independently reviewed
  (APPROVE-WITH-MINORS 2026-08-22) and the accepted findings are landed
  2026-08-23 — awaiting batch ratification.** SR-038..041 Verified,
  TC-066..073 Pass. See the audit entries below.
- **WP2 (config contract) is implemented, independently reviewed
  (CHANGES-REQUESTED 2026-08-22 — a quoted `"false"` for `AllowEmptySource`
  coerced to `$true` and disarmed the delete-all refusal) and every accepted
  finding is landed 2026-08-23 — awaiting batch ratification.** SR-042..043
  Verified, TC-074..078 Pass, all three config test cases now driven from the
  one shared corpus `tests/Common/ConfigFixtures.ps1`. See the audit entries
  below.
- **WP3 (container release-verify + smoke depth) is implemented — awaiting
  CI evidence + independent review + batch ratification.** SN=28 SR=44
  LLR=44 TC=80 minted (SN-028/SR-044/LLR-044/TC-079..080, all Draft);
  SR-034/LLR-034/TC-060 stay `Implemented`/`Draft` and the `--phase` ratchet
  stays at `core,bash-v1` in both `check.ps1` and CI until a real green CI
  run of the extended `container` job lands (Docker was unavailable on the
  driver's host this session — only static verification ran locally). See
  below.
- **WP4 (snapshot retention mechanism, `Remove-BackupSnapshot`) is implemented,
  independently reviewed (CHANGES-REQUESTED 2026-08-23 — the entry sweep deleted
  `*.fbprune.tmp` by bare suffix, so a REFUSED prune destroyed a Mirror-mode
  user file of that name in every folder at once and wedged the store) and every
  accepted finding is landed 2026-08-23 — awaiting batch ratification.**
  SN-029/SR-045..048/LLR-045..048/TC-081..090 minted; SR-045..047 **Verified**
  (TC-081..087, TC-089, TC-090 Pass), SR-048 `Implemented` with TC-088's
  in-container half `Draft` pending the Docker CI job (Docker is still
  unavailable on this host — its locally runnable halves DO run and pass).
  Open-items row **I** flips to Implemented; a new row **C-form** records the
  §5.7 latent defect dispositioned to WP5, for which WP4 ships the detector.
- **WP5 (storage-form trust) is implemented, independently reviewed
  (CHANGES-REQUESTED 2026-08-23 — `Repair-BackupStorageForm` iterated per ROW
  while renaming a PHYSICAL file, so repairing a deduplicated pair healed one
  row and left the other pointing at a path that no longer existed; and both
  locators dropped a `.7z` candidate that expanded successfully to other
  content, which is exactly a genuine `.7z` SOURCE file, leaving that row
  unrecoverable while every checker called the store clean) and every accepted
  finding is landed 2026-08-23; the fix set is **independently re-verified
  APPROVE (2026-08-23, entry below)** — the earlier in-flight re-review
  delivered its HIGH residual (payload-keyed exemption, fixed in `62fc702`)
  but its closing verdict was never recorded, so a fresh read-only
  re-verification against a pristine clone of `83cc5f1` replaced it —
  awaiting batch ratification.** Restore-kit
  revision is now **3**. SN-030/SR-049..052/
  LLR-049..052/TC-091..102 minted; **SR-049/SR-050/SR-051 Verified**
  (TC-091..TC-100 Pass), **SR-052 `Implemented`** with TC-101's Linux half and
  TC-102 `Draft` pending the Docker CI job (Docker unavailable on this host —
  every locally runnable half DOES run and pass). Open-items rows **C**,
  **C-form**, **C-refcount**, **ext-list merge** and **backup-side capacity**
  all flip to Implemented; three new rows record what WP5 surfaced but did not
  fix. Restore-kit revision bumped to **2** by WP5 itself (SR-050) and to **3**
  by the review fixes: snapshots written before a fix keep their old kit
  permanently — README documents the exposure and the two remedies. A **second
  WP5 residual** landed 2026-08-23, found by the first real local container run
  (Podman 5.5 turns out to be available on the driver's host even though Docker
  is not): a zero-object pipeline into `ConvertTo-Json` emitted NOTHING instead
  of `[]`, breaking the SR-049 findings document and the IF-001 snapshots
  inventory on exactly the clean/empty store while every exit code stayed
  correct; fixed with `-InputObject` at both emission sites, pinned by two new
  unit tests, TC-102's harness JSON extraction de-greedied — the full container
  build + smoke + TC-102 storage-form check now passes locally under Podman.
  See the audit entry below.
- **WP6 (docs batch) is done, docs-only, no code touched — the last item in
  the WP1→WP6 queue.** Release checklist regenerated from the registries
  ([release-checklist.md](release-checklist.md), now tracked; the stale
  untracked `checklist-vNEXT-dryrun.md` deleted; one generator bug fixed —
  its hardcoded hygiene line named the nonexistent `scripts/check.py`, now
  `pwsh scripts/check.ps1`). `interfaces.md` rewritten as a thin IF-001
  pointer + prose contract. `homehub-integration.md` §5 item 8 (the false-
  parity comment) verified and closed with a dated note: the comment is
  still there (now `bash/reconstruct.sh:564`) but finding A's fix means its
  claim is no longer false — both restorers now refuse identically when
  7-Zip is missing on a compressed manifest. `docs/plans/wp3-` and
  `wp4-*-plan.md` linked from their WP3/WP4 audit entries (0 orphans besides
  the still-generated `docs/test/report.md`, ignored by `check.ps1`'s own
  `--ignore`). Open items truth-up: WP1/WP2/WP4/WP5 rows now read their
  review verdicts instead of a bare "awaiting independent review"; a new
  Get-StoreFingerprint row records the WP4 reviewer's accepted nit; the
  dangling-DataPath row stays **Open**, explicitly dispositioned "awaiting
  human prioritization in the batch ratification"; the prune form-mismatch
  rail row is relabeled **WP6-or-later** since relaxing a Verified prune rail
  is a code change, out of this docs-only batch's surface. Kit-version stamp
  deliberately left untouched. See the audit entry below.
- **Adversarial review round (2026-08-23, human-directed) is done and its fix
  batch has landed — awaiting the same batch ratification.** Two independent
  fresh-context reviews (whole-repo medium + adversarial data-integrity,
  triage rule: realistic operational scenarios only) produced 19 findings;
  **12 fixed same-day** (backup-side witness gate with exit 3, atomic staging
  lock, non-destructive stale-Temp recovery + early-abort cleanup, state-file
  publish-by-rename, Mirror infra-name collision refusal, Linux case-sensitive
  RelativePath keying, sidecar containment, missing-DataPath hash fallback,
  PS separator mapping, two doc fixes), **restore kit revision 3 → 4**, five
  recorded as new/widened Open items (R5-widening, R6, R7, R10, F8), one
  dismissed malicious-only. Evidence: **Pester unit 330/330** (7 new pins),
  **bats 55/55 + shellcheck clean** on WSL after the reconstruct.sh changes,
  **lint clean**, trace `SN=30 SR=52 LLR=51 TC=101, 0 orphans / 0 integrity`,
  and the rebuilt container's full smoke + TC-102 check passing under Podman.
  See the audit entry below. **Independently reviewed 2026-08-23:
  CHANGES-REQUESTED** (the F3 case-sensitivity conversion missed
  `Save-SupersededData` — on Linux a case-differing pair could skip staging
  superseded bytes — plus a capacity-map nit and stale revision-3 docs);
  **every required change landed same day** (entries below) — awaiting batch
  ratification. `11b2c46` reviewed APPROVE in the same pass.
- **CI-gated (need a real green CI run on `resync_v2` after the push, not
  locally achievable — Docker is unavailable on this host):** SR-034 and
  SR-044 flip `Implemented`→`Verified`, the `--phase` ratchet re-arms to
  `core,bash-v1,container-v1`, and SR-048/SR-052 promote `Implemented`→
  `Verified` once TC-088, TC-101 (Linux half), and TC-102 go from `Draft` to
  `Pass` in the Docker container job. (2026-08-23: the container build, smoke
  test and TC-102 check pass **locally under Podman 5.5** — corroborating
  evidence only; the registry flips and the ratchet still wait on the CI run.)
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
| **E** | Restore can only verify rows its manifest still contains — a truncated manifest shrinks the job and still reports success. HomeHub's archive census does not port because of dedup. Partial mitigation shipped: missing-MANIFEST refusal (TC-063). | **WP1 (restore trust & diagnostics bundle).** Witness = a sidecar (e.g. `MANIFEST.csv.meta`) written atomically alongside the manifest carrying row count + xxHash128 of the manifest bytes, duplicated into each snapshot; both restorers verify it before restoring. Independent of the restore loop; portable to bash with tools already required; **subsumes the corrupt-manifest guard** (garbage manifest fails the digest). Adds an artifact to the SR-022 infrastructure allowlist — mind regression B6/TC-052. Needs its own SN/SR through G1; **blocks any "restore is trustworthy" claim.** | Implemented (WP1), independently reviewed (APPROVE-WITH-MINORS 2026-08-22), accepted findings landed 2026-08-23 — awaiting batch ratification |
| corrupt-manifest guard | Corrupt non-CSV MANIFEST.csv restores nothing yet exits 0 in `Reconstruct.ps1` (2026-07-03 reviewer MINOR; bash validates the header, exit 2). | **WP1**, implemented *inside* the witness change — a lone interim header check would burn a kit revision for something the witness replaces. | Implemented (WP1), independently reviewed (APPROVE-WITH-MINORS 2026-08-22), accepted findings landed 2026-08-23 — awaiting batch ratification |
| **D** + exit-code table | `Find-DataFileByHash` collapses 4 failure causes into one warning; IF-001 promises HomeHub a translatable exit status but `Reconstruct.ps1` throws one generic failure for every cause. | **WP1.** One documented exit-code table shared by both restorers — adopt bash's existing exit 2 as the baseline, don't invent a competing scheme. Prerequisite for IF-001 leaving `Experimental` (NagLight translation needs something to translate). | Implemented (WP1), independently reviewed (APPROVE-WITH-MINORS 2026-08-22), accepted findings landed 2026-08-23 — awaiting batch ratification |
| **J** | Backup-side move loops (`Move-RemovedFilesToStaging`, `Save-SupersededData`) abort on first failure instead of aggregating like restore's `$unrestored`. | **WP1** companion (same fail-loudly theme), or immediately after. Small. | Implemented (WP1), independently reviewed (APPROVE-WITH-MINORS 2026-08-22), accepted findings landed 2026-08-23 — awaiting batch ratification |
| config contract | IF-001's import half is under-specified: `FileBackup.ps1`'s JSON branch is a bare `ConvertFrom-Json` — no schema, no version field, no validation, no test; `container/FileBackup.example.json` is never executed by any test (TC-060 generates its own config). | **WP2.** Versioned JSON schema + validating loader that fails loudly (SR + LLR + TC executing the example file itself). JSON becomes the canonical documented contract; CLIXML stays the legacy native-Windows path. Top HomeHub-facing priority after E. Blocks IF-001 moving past `Experimental`. | Implemented (WP2), independently reviewed (CHANGES-REQUESTED 2026-08-22), accepted findings landed 2026-08-23 — awaiting batch ratification |
| multi-set mounts | How HomeHub maps N host directories onto container paths was unspecified. | **RESOLVED by ruling, WP2 records it:** **one BackupSet per container invocation**; HomeHub runs one service/invocation per directory (matches its per-service scheduling + NagLight model, keeps mounts trivial). Multi-set stays a native-Windows convenience. Recorded in IF-001. | Implemented (WP2), independently reviewed (CHANGES-REQUESTED 2026-08-22), accepted findings landed 2026-08-23 — awaiting batch ratification |
| container release-verify | SR-034/TC-060 are `Implemented`/`Draft`; CI runs **BuildAndTest only** — Export/Publish/Pull and a `docker load` roundtrip are never exercised; no local `check.ps1` tier runs the container step. | **WP3.** Extend the CI job: Export → `docker load` roundtrip; Publish/Pull against a throwaway `registry:2` container in-job. Then TC-060 → Pass, SR-034 → Verified, **re-arm the ratchet to `--phase core,bash-v1,container-v1`.** Blocks calling container-v1 released. | Implemented (WP3) — awaiting CI evidence + independent review + batch ratification |
| container smoke depth | Smoke checks a six-artifact kit that omits `RECONSTRUCT.paths.json` and runs one single-set, no-snapshot, no-rerun backup. | **WP3**, with release-verify: add the sidecar to the kit check and a second incremental, snapshot-producing run restored in-container. | Implemented (WP3) — awaiting CI evidence + independent review + batch ratification |
| **I** | Snapshot retention is unbounded. | **Re-ruled — the pure "delegate to HomeHub" disposition was unsafe:** blank-DataPath rows recover bytes by hash from *other* snapshots' folders, so externally pruning a `Snapshot_*` folder can delete the only physical copy other snapshots still need. **Split: HomeHub owns retention *policy*; FileBackup owns the *mechanism*** — a `Prune-Snapshot` verb (WP4, own SR) that re-homes still-referenced bytes before deleting a folder. IF-001 now states: never delete snapshot folders directly. **Do before HomeHub builds any pruning.** | Implemented (WP4), independently reviewed (CHANGES-REQUESTED 2026-08-23), accepted findings landed 2026-08-23 — awaiting batch ratification |
| **C-form (new, WP4 §5.7)** | A blank-DataPath row whose `Compressed` disagrees with the .7z-ness of the file hash recovery locates restores **archive bytes under the original name**: both restorers branch on the ROW's `Compressed`, not on the form of the file they found. Reachable today after a compression-mode flip, because `Sync-BackupStorageLayout` migrates only the backup root and never the snapshots. | **WP5**, with finding C (same repair story). WP4 ships the **detector**: `Test-PoolResolves` reports `form-mismatch` and `Remove-BackupSnapshot` refuses (code 2) rather than pruning into it, so a store in this state is named instead of silently widened — and WP5 inherits a ready repro (TC-084's `form-mismatch` case). Note the deliberate exemption: a row whose own `RelativePath` ends in `.7z` (a legitimately stored already-compressed source file) is NOT a disagreement. | Implemented (WP5), independently reviewed (CHANGES-REQUESTED 2026-08-23), accepted findings landed 2026-08-23; re-review of the fixes in flight — awaiting batch ratification |
| **C-refcount (new, WP5 planning G10)** | `Sync-BackupStorageLayout` is not refcount-aware: dedup makes rows share one `DataPath` (`Invoke-BackupFileGroup`), the migration decision is per-row (`Engine.psm1` `$needsTransform`), and Phase 2 deletes every superseded path unconditionally — so a config change that flips only ONE of two content-sharing rows deletes the file the other still references (`MissingDataFile` on the next restore, exit 1). **Live data-loss defect on Verified code**, reachable today (compression flip + two same-content rows with different extensions); the ext-list merge would trigger it at scale. Contrast `Move-RemovedFilesToStaging`, which IS refcount-aware (B9). | **WP5 as SR-051** ([plans/wp5-storage-trust-plan.md](plans/wp5-storage-trust-plan.md)), sequenced BEFORE the ext-list merge. Surfaced immediately per the plan's Q7 so it stays visible even if WP5 slips. | Implemented (WP5), independently reviewed (CHANGES-REQUESTED 2026-08-23), accepted findings landed 2026-08-23; re-review of the fixes in flight — awaiting batch ratification |
| **C** | `Sync-BackupStorageLayout` trusts manifest `Compressed`/`StoredAsHashSize` metadata, so a malformed row can validate itself. | **WP5.** With B fixed, new malformed rows can't be created — C matters for pre-fix backups and for migrations the ext-list merge triggers. Repro test first (double-check §5.3); repair via an opt-in `-VerifyStorage` mode, **not** a physical verify inside every migration (would fight SR-024 idempotence/perf). | Implemented (WP5), independently reviewed (CHANGES-REQUESTED 2026-08-23), accepted findings landed 2026-08-23; re-review of the fixes in flight — awaiting batch ratification |
| ext-list merge | Merge bash's broader already-compressed extension list (`jar tgz zst gif webm ogg sav pack`) into `Common.psm1`; keep per-file granularity. | **WP5, sequenced AFTER C's repro test** — not trivial: the merge flips existing `.7z` rows to "wrong" under `Sync-BackupStorageLayout`'s config comparison and exercises the untested migration path at scale. Cover the triggered migration in C's test. | Implemented (WP5), independently reviewed (CHANGES-REQUESTED 2026-08-23), accepted findings landed 2026-08-23; re-review of the fixes in flight — awaiting batch ratification |
| backup-side capacity | Does the backup side have the capacity preflight the restore side gained (SR-023 is restore-only)? | **WP5.** Verify first, then a small SR mirroring SR-023. Importance rises with the container (target is a HomeHub-controlled bind mount). | Implemented (WP5), independently reviewed (CHANGES-REQUESTED 2026-08-23), accepted findings landed 2026-08-23; re-review in flight — SR-052 stays `Implemented` until TC-101's Linux half runs in the Docker CI job; awaiting batch ratification |
| prune form-mismatch rail (new, WP5) | `Test-PoolResolves` refuses a prune with code 2 on a blank-DataPath `form-mismatch`, a rail WP4 justified by "the restorers branch on the ROW". **SR-050 removed that premise**, so prune now refuses a store a revision-2 kit restores correctly — reproducible by any compression flip. | **WP6-or-later.** Left unchanged deliberately by WP5: a pre-revision-2 snapshot restored by its OWN kit IS still exposed, and relaxing a Verified prune rail is not WP5's call. **A code change, so out of this docs-only WP6 batch's scope** — confirmed still open, unchanged since WP5. Likely resolution: downgrade the BLANK-row half to informational once `-RefreshKits` (or a kit-revision check) proves the pool's kits are current. **Realism VERIFIED 2026-08-23 (investigation entry below) and WORSE than this row stated:** the refusal reproduced exactly (exit 2, blocks every prune, the refused snapshot restores byte-exact with its own revision-4 kit); no existing action clears it (`-RepairStorage` reports the rows unrepairable, `-RefreshKits` doesn't help, and the precondition doesn't even exclude the snapshot being pruned); a store holding snapshots from BOTH compression regimes is **permanently wedged under either setting** with no unblock path short of hand-editing manifests; and the WP5 phase-F extension merge is itself a form flip for 8 types — an existing compressed store that merely upgrades to HEAD walks into it with no operator action. README even promised the flip was safe (true for restore, false for prune) — a caveat box is now landed there. Blocks IF-001's prune action too. | **Open → promoted to scheduled** (small fix: the blank-row branch of `Test-PoolResolves` + the `Repairable=$false` classification; data safety never at risk — refusal is conservative) |
| dangling DataPath becomes unrestorable (new, WP5) | A row whose data file is missing is dropped by `Test-BackupManifest`; if the SOURCE file is unchanged the diff never re-copies it, and `Optimize-ChangeFolders` blanks the `DataPath` — leaving a row whose bytes are nowhere in the pool while the run reports success. `Test-PoolResolves` detects it (`broken-pool`); no backup run does, and SR-049's audit deliberately does not (it is not a FORM finding). Pre-existing, observed while writing TC-094. Severity: **pre-existing MEDIUM** (silent-success data-loss risk, not confirmed reachable at scale). **2026-08-23 review round corroborated and WIDENED it (R5):** `Invoke-BackupFileGroup` picks `$existingBackupWithHash[0]` without checking the `DataPath` is non-blank, so a NEWLY ADDED file with matching (hash,length) adopts the blank `DataPath` and its bytes are never copied either; and since `Compare-SourceToBackup` diffs metadata only, an unchanged source file never re-enters the diff to heal its row. Partial mitigation shipped 2026-08-23: kit revision 4's restorers fall back to (hash,length) recovery for MISSING named files, but a truly blank row with no pool copy remains silent-success data loss. **Realism VERIFIED 2026-08-23 (investigation entry below): reproduced end-to-end on HEAD.** The dominant initiating class is external deletion inside the backup root (AV quarantine, cloud-sync dehydration, an operator tidying a folder that looks like a plain copy — README never warns against it); the engine's own deletion paths are closed on current code. After the loss: one WARN on the blanking run, exit 0 forever after, the row is never re-copied though the diff proves the SOURCE still holds the bytes, the R5 adoption spreads it to NEW files with zero warnings — and **`-Action Verify`, even `-Deep`, exits 0 clean on the broken store** (`Test-PoolResolves` is called by nothing but prune). Kit-4 hash fallback saves only rows whose bytes survive elsewhere in the pool; unique content — this product's core case — is unrecoverable at restore time. | Needs its own SR — **verified worth a work package now, not parkable behind "verify detects it" (it doesn't)**: never adopt a blank `DataPath` as "existing" (falls through to the copy branch, killing the spread AND healing rows whenever the content re-enters the diff), force the blanking path to re-copy when the source still matches or fail the set, wire `Test-PoolResolves` into `-Action Verify`, and add the missing README warning against touching backup-root contents. **Awaiting human go-ahead to mint the WP.** | Open — verified HIGH |
| manifest row order (new, WP5) | Consecutive no-op runs can emit manifest ROWS in a different ORDER with identical content (the final manifest is enumerated from a hashtable). SR-024 holds on row content; G7-Determinism does not catch the ordering. TC-094/TC-097 compare rows sorted by `RelativePath`. | **WP6**, low priority. Either sort deterministically before `Write-Manifest`, or state explicitly that row order is not part of the contract. | Open → WP6 |
| snapshot inventory cost (new, WP4 review L3) | `Get-BackupSnapshot` runs one `Get-SnapshotPrunePlan` per snapshot and each rebuilds the whole pool index — O(n^2) in snapshot count — and the plan hashes candidate files (the destination-collision check) during what is advertised as a read-only inventory. Correctness is unaffected; on a large store `-Action Snapshots` is far more expensive than it looks. | **Perf follow-up, unscheduled.** The obvious fix is to build the pool index ONCE and thread it through `Get-SnapshotPrunePlan`; that is not a trivial edit to a data-integrity function, so the WP4 review fixes deliberately did not attempt it. | Recorded 2026-08-23 (WP4 review, accepted as-is) |
| **-RepairFromPruned** (deferred from WP4 §5.4) | Materializing bytes back into a pool that lost them. WP5 landed the DIAGNOSIS half (SR-049's R3/R4/R5 findings say exactly what is missing and where); the byte-materialization half stays deferred. | **WP6 or later.** Build on WP4's plan/copy/prove primitives once they are Verified. SR-050 removed the correctness motive, so this is convenience, not safety. No SN/SR yet. | Deferred → WP6-or-later |
| **H** | No destination mount-identity preflight. | **Stays delegated to HomeHub (IF-001)** — HomeHub genuinely owns mounts and the container can't see the host mount table. Optional later hardening: an `ExpectedSentinel` config key (refuse if a named file is absent at the destination). Low priority; revisit only if FileBackup runs outside the wrapper. | Delegated |
| release checklist | `checklist-vNEXT-dryrun.md` was stale (UN-### vocabulary, no SR-029+, pointed at nonexistent `scripts/check.py`, untracked/gitignored). | **WP6 (docs batch).** Regenerated from the registries via `gen_release_checklist.py` — the generator survived the UN→SN rename intact and already included the container SNs (SN-024/026/028); fixed one generator bug found in passing (its hardcoded hygiene line named the nonexistent `scripts/check.py` — now `pwsh scripts/check.ps1 -Gate G3 -Tier Release`). Deleted the stale untracked dry-run file. [`docs/release-checklist.md`](release-checklist.md) is now tracked (`.gitignore` narrowed to keep only `docs/releases/` — versioned/signed per-release copies — generated). | Done (WP6) |
| interfaces.md boilerplate | `docs/interfaces.md` is unmodified kit boilerplate; the real IF-001 lives in `requirements/interfaces.csv`. | **WP6.** Rewritten as a thin IF-001 pointer + prose contract (config schema v1, one-set-per-invocation, the shared exit-code table, retention policy/mechanism split, no-direct-snapshot-deletion, `Experimental` stability + the joint WP1/WP2 exit condition). See [`interfaces.md`](interfaces.md). | Done (WP6) |
| doc drift | Kit-version stamp still `9b697cc 2026-07-02`; homehub-integration.md §5.8 false-parity comment (bash/reconstruct.sh:380) unverified post-A-fix. (AGENTS.md test count fixed 2026-08-21.) | **WP6.** Kit-version stamp deliberately left untouched (re-stamp only on a real kit resync — not this batch). §5.8 verified and closed with a dated note in [`homehub-integration.md`](homehub-integration.md#5-original-double-check-list): the comment is still present (now at `bash/reconstruct.sh:564`) and its underlying claim is no longer false — finding A's fix made `Reconstruct.ps1` refuse identically to bash when 7-Zip is missing on a compressed manifest; the comment's stale word is "degrade" (neither side degrades anymore), left for a future bash-side editorial pass since this batch touches no `bash/` files. | Done (WP6) |
| Get-StoreFingerprint nit (new, WP4 review) | `Get-StoreFingerprint` excludes `*.fbprune.tmp` wholesale — a future test combining `-SuffixNamedUserFiles` with `Assert-StoreUnchanged` would be blind to the H1 class (missing/renamed-file corruption on that suffix). Not a defect on any test that exists today; a test-authoring blind spot. | **Accepted 2026-08-23 (WP4 review, recorded as-is, no action taken)** — flagged here so a future `-SuffixNamedUserFiles` × `Assert-StoreUnchanged` combination test doesn't silently miss the H1 class. Revisit only if that combination is added. | Accepted, recorded — no action taken |
| Archive-option storage mode (ex-ToDo) | Store backups as `.7z` archive sets with per-folder rebuild scripts. | **REJECTED 2026-08-21** — opaque archive sets contradict the model's core strength (plain files on disk, restorable by a 20 KB bash script with no runtime). Moved to Non-goals. | Rejected |
| CloneSpy CRC export (ex-ToDo) | Emit a CloneSpy-compatible CRC list per backup set. | Harmless C-priority idea; stays parked, unscheduled. | Parked |
| **2026-08-23 review round (fixed batch)** | Two independent fresh-context reviews (whole-repo medium + adversarial data-integrity, human-directed triage: realistic operational scenarios only, malicious-only excluded) surfaced 19 findings, several REPRODUCED by throwaway scripts. Twelve landed same-day: backup-side manifest-witness gate refusing with exit 3 before any mutation (F2, reproduced silent-laundering of a torn index); atomic staging-lock take (R3); non-destructive stale-Temp recovery guidance in guard + README, and early-abort staging cleanup so a locked source file no longer wedges every later run (F1 reproduced/R4); `FileBackupState.json` publish-by-rename (F7); Mirror-mode refusal of a root-level infrastructure-named data path instead of silent corruption (R2); filesystem-faithful RelativePath keying via `New-RelativePathMap` (F3, reproduced on Linux semantics); sidecar containment rule — a copied/moved store restores from ITSELF (F4, reproduced, both reviewers); missing-DataPath (hash,length) fallback in both restorers (F5); `\`-separator mapping in the PS restorer on Linux (F6); README Verify-repairs wording (R9); IF-001 JSON framing note (R8). **Restore kit is now revision 4.** | Fixed, tested (6 new Pester pins + bats 55/55 + shellcheck clean), audit entry below. | Landed — awaiting batch ratification |
| 7-Zip argument quoting (new, R6) | `Compress-`/`Expand-FileWithSevenZip` and `Get-MediaMBPerSec` hand-join quoted arguments into `ProcessStartInfo.Arguments`; a filename containing `"` (legal on Linux) mis-splits the 7-Zip command line. Failure is loud (set fails / exit 4). | Move to `ProcessStartInfo.ArgumentList` (per-argument, no quoting). Touches the kit module, so batch with the NEXT kit-revision bump rather than spending revision 5 on it alone. | Open |
| bash newline-in-filename rows (new, R7) | `reconstruct.sh`'s line-based FPAT parser cannot parse an RFC-4180 quoted field containing a newline — a legal Linux filename the engine can now write from a container backup; `Import-Csv` handles it, so the twin restorers diverge on the same manifest. Loud-ish (exit 1/4), not silent. | bash-v2 scope: refuse such rows with a clear message in bash, or refuse the filename at backup time on Linux. | Open → bash-v2 |
| no-7-Zip raw-candidate skip (new, R10) | Both restorers `continue` past a `.7z`-named hash-recovery candidate when 7-Zip is absent, never testing its raw bytes — which needs no 7-Zip and is exactly the revision-3 exemption shape. A restore needing no actual decompression can exit 4 "install 7-Zip" unnecessarily. | Low impact (a genuinely compressed store dies earlier anyway). Fold into the next kit-revision batch with R6. | Open |
| kit-less snapshot window (new, F8) | A crash inside `Complete-ChangeFolder` between the `Temp`→`Snapshot_*` rename and the kit-artifact copy loop yields a valid snapshot (manifest + witness) carrying NO restore kit (`Get-BackupKitRevision` = 0) — breaks the "every snapshot is self-contained" expectation; no byte loss. | Recoverable today via `-Action Verify -RefreshKits`. Candidate cheap fix: copy the kit into staging BEFORE the rename so the rename publishes a complete snapshot. Unscheduled. | Open |

**Agreed work-package order (after Next-action items (a)–(c) are ratified):**
**WP1** restore trust & diagnostics (E + corrupt-manifest + D/exit codes + J —
one G1→G3 pass, one independent review, one kit revision, PS + bash + kit
copies together) → **WP2** config contract (+ record the one-set-per-invocation
ruling) → **WP3** container release-verify + smoke depth + ratchet re-arm →
**WP4** retention mechanism (`Prune-Snapshot`) → **WP5** storage-form trust (C repro first, then SR-050's restorer fix, SR-051's
refcount-safe migration, SR-049's verify/repair, the ext-list merge and SR-052's
capacity guard) → **WP6** docs batch.

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

### DRIVER (Software + Test Engineer hats) — WP1 restore trust & diagnostics — 2026-08-23

Executed [plans/wp1-restore-trust-plan.md](plans/wp1-restore-trust-plan.md) end
to end under the 2026-08-22 grind authorization (batch ratification). Closes
Open-items rows **E**, **corrupt-manifest guard**, **D + exit-code table**, and
**J**. Ids minted and closed: **SN-025..026, SR-038..041, LLR-038..041,
TC-066..073.**

**What landed, by phase**

- **Registries** (`a6ddc5f`) — SN/SR/LLR/TC rows + the IF-001 contract amendment
  (exit-code table + witness promise; `SR-Refs` now `SR-034;SR-038;SR-039;SR-040`).
  IF-001 stays `v1`/`Experimental` — WP2's config contract is the remaining blocker.
- **Phase A — manifest witness writer** (`ae0bd26`, SR-038 / TC-066, TC-067).
  `Write-Manifest` now stamps `MANIFEST.csv.meta` (`Version`, `Rows`, `Bytes`,
  `XxH128`, `Written`; UTF-8 no BOM, LF) beside every manifest it writes,
  published by `Move-Item -Force` (atomic rename). One writer, so backup root,
  staging, dated snapshots, the source hash cache and every rewrite are covered
  and cannot drift. `Get-ManifestWitnessPath` / `Write-ManifestWitness` /
  `Test-ManifestWitness` live in **Common** (Reconstruct may call only Common).
  The witness joins `Test-IsInfrastructureFile`'s **root-level** allowlist only —
  a nested `sub\MANIFEST.csv.meta` is still user data (B6). It is deliberately
  **not** a kit artifact: copying it into snapshots would overwrite each
  snapshot's own witness with the backup root's. TC-067 pins both halves.
- **Phases B+C — exit-code contract + witness verification** (`3ee8f5b`,
  SR-039/SR-040 / TC-068..072). One documented table in both restorers: **0**
  complete · **1** incomplete/content · **2** usage or precondition · **3**
  witness verification failed · **4** incomplete/host (retriable), precedence
  **2 > 3 > 4 > 1**. `Find-DataFileByHash` / `find_by_hash` now return a distinct
  cause (`ContentMissing`, `DependencyMissing`, `StorageUnreadable`,
  `CandidateError`) instead of collapsing four failures into one warning, and the
  summary names the count per class. Both restorers check the CSV header shape
  and, when a witness is present, `Bytes`/`Rows`/`XxH128` before writing any
  manifest row. A missing sidecar warns `UNVERIFIED` and continues so **legacy
  backups still restore**; `-RequireWitness` / `--require-witness` makes absence
  an abort. Delivery is opt-in: `Reconstruct.ps1` still **throws** for in-process
  callers and only exits with a code under `-ExitCode`, which `RECONSTRUCT.bat`
  now passes — so the six `Should -Throw` assertions and the harness are untouched.
- **Phase D — move-loop failure aggregation** (`60496b3`, SR-041 / TC-073).
  `Move-RemovedFilesToStaging` and `Save-SupersededData` wrap each move in
  try/catch, log an ERROR naming file and cause, count it, continue, and emit a
  per-loop summary; both take `[ref]$OverallSuccess`. `Invoke-BackupSet` passes
  the ref and does **not** early-return, so step 13 still finalizes or discards
  the staging folder. Before this, one failed `Move-Item` escaped the pipeline,
  hid every other failure, skipped snapshot finalization and left `Temp` behind —
  so the *next* run aborted on the SR-017 stale-staging guard (finding J).
- **Phase E — kit, fixtures, docs.** `Invoke-Container.ps1`'s smoke assertion
  six → seven artifacts; `tests/fixtures/bash-restore/**` regenerated so every
  fixture manifest carries a matching witness (the hand-built manifest in
  `fail_loudly.bats` stays witness-less on purpose, pinning the legacy path);
  README gained "Restore exit codes" (normative) plus witness prose in
  "3. Restore", "Restore on Linux", "How it works" and "Manifest columns";
  AGENTS.md §2/§3/§4 gained the witness invariant, the exit-code invariant and
  the deliberate crash-window note; `bash-variant-plan.md`'s contract table
  gained both rows; generated blocks regenerated.

**Evidence (real output, 2026-08-23)**

`pwsh scripts/check.ps1 -Tier Full`:

```
[PASS] PSScriptAnalyzer
==== Traceability (trace.py --strict) ====
Traceability: SN=26 SR=41 LLR=40 TC=72 orphans=0 integrity=0 status-findings=0 phase-deferred=2. Report -> docs\test\report.md
[PASS] Traceability (trace.py --strict)
[PASS] Doc navigability (check_docs.py)
[PASS] Architecture map freshness
Tests Passed: 83, Failed: 0, Skipped: 0, Inconclusive: 0, NotRun: 0
[PASS] Pester unit
[PASS] Performance budgets (check_perf.py)
[PASS] Integration sweep (Full)
All steps passed.
```

Integration sweep detail: **PASS: 236 · FAIL: 0 · SKIP: 4** (G8 SKIPs under Subst).

G3 ratchet, `python scripts/trace.py --strict --require-verified --phase core,bash-v1`:

```
Traceability: SN=26 SR=41 LLR=40 TC=72 orphans=0 integrity=0 status-findings=0 phase-deferred=2. Report -> docs\test\report.md
```

Real Linux (WSL `podman-machine-default`, Fedora 40) — `shellcheck bash/reconstruct.sh`
clean, `bats tests/bash` **45/45 ok** (was 24; +11 `witness.bats`, +10 `exit_codes.bats`):

```
ok 43 --require-witness turns a missing witness into a refusal (SR-039)
ok 44 a witness from the FUTURE verifies the known fields and warns (SR-039)
ok 45 each SNAPSHOT carries its OWN witness, not the backup root's (SR-038)
```

**Decisions taken (per plan §6, flagged for batch ratification)**

1. `-ExitCode` switch for PowerShell exit-code delivery; `throw` stays the default.
2. Engine-side witness verification before mutating a backup deferred to WP5's
   `-VerifyStorage`.
3. `Rows` counted as `Import-Csv` / `parse_manifest` count them; `XxH128` stays
   authoritative, so a counting divergence can never alone condemn a good manifest.
4. SN-025 in the edge-case table, SN-026 in core needs.

**Deviations from the plan, and why**

- **Phases B and C landed in one commit** (`3ee8f5b`). They rewrite the same
  functions in both restorers (`Read-RawManifest` / `main()`'s guard region and
  the shared exit path); splitting them would have required an intermediate
  state that is neither meaningful nor independently reviewable. Both phases'
  tests are present and green.
- **A third manifest-tampering test site** beyond the two the plan's §5 table
  named: `Coverage.Tests.ps1`'s SR-023 capacity test also rewrites `MANIFEST.csv`
  and now re-stamps the witness. `G3-Reconstruction.ps1`'s hash-fallback blanking
  was a fourth; `tests/Run-All.ps1` now imports Common so suites can re-stamp.
- **A "replaced by garbage" manifest exits 2, not 3.** The plan's normative table
  (§2) and its §5 regression row both put an unrecognizable header at code 2 (the
  pre-existing guard `fail_loudly.bats` pins), while TC-068/TC-069's summary prose
  loosely said "witness failure" for all three damage kinds. Implemented per the
  normative table (precedence 2 > 3) and **truthed-up the two TC Expected cells**
  to say so. No design change.
- **A real bug found while implementing bash Phase B:** the first cut set the
  recovery cause in shell globals, but `find_by_hash` is called through command
  substitution — a subshell — so the cause never reached the caller and exit 4
  could never fire. The cause now travels in the function's **output**
  (`<cause>\037<detail>\037<path>`). Caught by TC-071, which is the point of it.

**Known asymmetry for the reviewer.** On a witness failure the bash restorer
writes *nothing at all* (its check sits before `mkdir -p` on the target), while
`Reconstruct.ps1` has already created the target directory and `RECONSTRUCT.log`
by the time `Read-RawManifest` runs — the placement the plan specifies for each.
Neither writes a manifest **row**, which is the contract ("no file is written to
the target" = no restored data), and both TCs assert exactly that. Worth a
reviewer ruling on whether to align them.

**Next action (awaiting human):** independent review of the WP1 data-integrity
surface (witness write/verify path, exit-code classification, move-loop
aggregation), then batch ratification alongside the other WPs.

### DRIVER (Software + Test Engineer hats) — WP2 config contract — 2026-08-23

Executed [plans/wp2-config-contract-plan.md](plans/wp2-config-contract-plan.md)
end to end under the 2026-08-22 grind authorization (batch ratification).
Closes Open-items rows **config contract** and **multi-set mounts**. Ids
minted and closed: **SN-027, SR-042..043, LLR-042..043, TC-074..078**
(sequenced after WP1's SN-025..026/SR-038..041/LLR-038..041/TC-066..073,
reusing WP1's "2 = usage/precondition" exit-code meaning).

**What landed, by phase**

- **Phase A — registries** (`444ee8f`) — SN-027 (edge-case: a wrong config
  refuses to start, names the offending key, never guesses a default), SR-042
  (versioned closed JSON schema) / SR-043 (`-ExitCode` distinguishes a config
  failure from a set failure), LLR-042/043, TC-074..078; IF-001's `Contract`
  cell gained the schema summary and `SR-Refs` gained `SR-042;SR-043` — `Version`
  stays `v1` (never left `Experimental`) and `Stability` stays `Experimental`
  (a separate decision for batch ratification, per the work order).
- **Phase B — the loader** (`10b58fe`, SR-042/LLR-042). New region in
  `Modules/FileBackup.Engine.psm1`: `$script:ConfigSchemaVersion = 1`;
  `Import-BackupConfiguration` (exported) dispatches on extension. JSON:
  parses, checks `ConfigVersion` first — missing / non-integer / `< 1` /
  above `$script:ConfigSchemaVersion` — all hard errors naming `$.ConfigVersion`,
  in document order before anything else runs; then `Assert-NoUnknownConfigKey`
  (private) recursively rejects any key outside the schema at the top level,
  `Tools`, `Secrets`, and every `BackupSets[]` entry, naming the JSON path, and
  explicitly bans `Secrets.Credential`; then `Test-BackupConfigurationShape`
  (private, shared with CLIXML) with `-StrictTypes` — a quoted `"false"` for
  `CompressEnabled`/`PreserveFolderTree` is rejected as the wrong JSON type,
  never coerced by `[bool]`, and a non-integer `Secrets.SmtpPort` is rejected —
  while the three pre-existing message wordings (`*at least one BackupSets
  entry*`, `*must define a non-empty*`, `*invalid HashRecalcFreq*`) are emitted
  **verbatim** by the same shared function. `Resolve-BackupSetDefaults`
  (private) materializes `SourceStatePath=SourcePath`,
  `AllowEmptySource=$false`, and upper-cased `HashRecalcFreq`. CLIXML runs only
  the shared shape check (no version, no closed schema, no credential ban) —
  unversioned legacy. A JSON config with >1 `BackupSets` logs a `WARN` (IF-001)
  instead of failing. 13 new Pester cases (TC-074/075) call the function
  directly, so this phase touched no other file's behavior.
- **Phase C — wire the entry point** (`a6df81e`, SR-043/LLR-043).
  `FileBackup.ps1:100-125`'s bare `ConvertFrom-Json`/`Import-Clixml` dispatch
  and inline per-set validation loop collapsed to one
  `Import-BackupConfiguration` call. The global logger now builds *before* the
  config load (it only needs `$ConfigPath`/`$GlobalLogPath`) so a load failure
  can still be logged. New `[switch]$ExitCode` + `Exit-ConfigFailure`: under
  `-ExitCode` a load failure logs to stderr + the global log and `exit 2`
  (SR-043's usage/precondition class); without it, it rethrows — unchanged
  in-process behavior. The trailing `if (-not $overallSuccess) { exit 1 }` is
  untouched. **Regression fix required to keep this phase green** (flagged in
  the plan's §5 risk table, landed here rather than deferred to Phase D as the
  table's own bullet ordering implied, because the moment the entry point is
  wired the two inline JSON fixtures in `Engine.Tests.ps1`'s SR-018 block break
  the instant `ConfigVersion` is required): added `ConfigVersion` to the valid
  fixture; the pre-existing `'{}'` case now asserts the ConfigVersion-missing
  message (checked first, in document order) rather than the empty-BackupSets
  message, and a new case pins the old `'{}'` → `"at least one BackupSets
  entry"` wording against a `'{"ConfigVersion":1}'` fixture so that check
  stays covered.
- **Phase D — versionize the artifacts, publish the schema** (`136b60a`,
  SR-042/LLR-042). `"ConfigVersion": 1` added to
  `container/FileBackup.example.json`, the README JSON block, and
  `Invoke-Container.ps1`'s `New-SmokeConfiguration`. Published
  `container/FileBackup.schema.json` (JSON Schema draft-07:
  `additionalProperties: false` at every level, `const: 1` for `ConfigVersion`,
  `enum` for `HashRecalcFreq`; `Secrets.Credential` is simply absent from the
  allowed key set, so the schema rejects it the same way the hand-rolled
  validator does) as documentation — the runtime authority stays the
  PowerShell validator, per the plan's decision #5. TC-076
  (`Coverage.Tests.ps1`): loads the checked-in example, retargets *only* its
  path fields and `Tools.SevenZipPath` (to the platform's real 7-Zip), asserts
  a recursive keys-only diff against the checked-in file so the example cannot
  silently drift from what it claims to demonstrate, then drives a real
  compressed `FileBackup.ps1` run and a byte-exact `RECONSTRUCT.ps1` restore.
  TC-077: `Test-Json -SchemaFile` against the same accept/reject fixture corpus
  as TC-074/075, cross-checked against `Import-BackupConfiguration` so the
  published schema and the runtime validator cannot drift apart; also pins
  `ConfigVersion=1` across the example, the extracted README block, and the
  smoke config.
- **Phase E — entrypoint, help, README** (`6097189`, SR-043/LLR-043).
  `container/entrypoint.sh` passes `-ExitCode` (shellcheck-clean, verified in
  WSL `podman-machine-default`). `FileBackup.ps1`'s `.PARAMETER ConfigPath` now
  documents JSON-as-canonical-versioned vs. CLIXML-as-legacy with a worked
  example of each, the IF-001 multi-set warning, and a new `.PARAMETER
  ExitCode`; `.NOTES` gained the SR-043 status-code table. (The `-ExitCode`
  switch itself and `Exit-ConfigFailure` were already added in Phase C, since
  both needed to land in the same commit as the logger-ordering change they
  depend on — Phase E's job here was documentation, not code.) README's
  "Config format" section rewritten to state the same JSON-canonical/
  CLIXML-legacy split, a `ConfigVersion` field row, the multi-set warning, and
  the `-ExitCode` status-code summary (the now-redundant standalone "multiple
  BackupSets" sentence removed). TC-078 (`Coverage.Tests.ps1`, 6 cases):
  child-process `-ExitCode` returns 2 (schema-violating config, no backup
  artifacts created) / 1 (one set fails) / 0 (clean run); the same three
  invocations without `-ExitCode` return the pre-WP2 codes (1/1/0 — a bad
  config is still a non-zero exit, just not specifically 2); an in-process call
  still throws for a bad config; a two-set JSON config logs the IF-001 warning
  naming the count while still processing both sets.
- **Phase F — close (this entry).** Flipped SR-042/043 → `Verified`,
  LLR-042/043 → `Verified` (matching the convention the existing LLR rows use,
  not the work order's literal "Implemented" wording), TC-074..078 → `Pass`,
  via targeted line-level edits (a full CSV-writer rewrite was tried first and
  rejected — it silently reformatted every unrelated row's quoting under
  `QUOTE_MINIMAL`, which would have buried the real diff; reverted and redone
  as anchored regex substitutions touching only the five target rows — verified
  by `git diff` showing exactly those five one-line changes per file).

**Evidence (real output, 2026-08-23)**

`pwsh scripts/check.ps1 -Tier Full`:

```
==== PSScriptAnalyzer ====
[PASS] PSScriptAnalyzer

==== Traceability (trace.py --strict) ====
Traceability: SN=27 SR=43 LLR=42 TC=77 orphans=0 integrity=0 status-findings=0 phase-deferred=2.
[PASS] Traceability (trace.py --strict)

==== Doc navigability (check_docs.py) ====
check_docs: WARN - orphan doc (no path from an entry root): docs/plans/wp2-config-contract-plan.md
check_docs: OK - 15 doc(s), 54 intra-repo link(s), 0 broken (1 orphan warning(s)).
[PASS] Doc navigability (check_docs.py)

==== Architecture map freshness ====
[OK]  Generated regions current in C:\Projects\FileBackup\docs\architecture.md
[OK]  Generated regions current in C:\Projects\FileBackup\AGENTS.md
[PASS] Architecture map freshness

==== Pester unit ====
Tests Passed: 106, Failed: 0, Skipped: 0, Inconclusive: 0, NotRun: 0
[PASS] Pester unit

==== Performance budgets (check_perf.py) ====
check_perf: OK - no performance budgets to compare (process.md §9)
[PASS] Performance budgets (check_perf.py)

==== Integration sweep (Full) ====
  PASS: 236
  FAIL: 0
  SKIP: 4
[PASS] Integration sweep (Full)

================ check.ps1 (tier Full, gate G3) ================
All steps passed.
```

G3 ratchet, `python scripts/trace.py --strict --require-verified --phase core,bash-v1`:

```
Traceability: SN=27 SR=43 LLR=42 TC=77 orphans=0 integrity=0 status-findings=0 phase-deferred=2. Report -> docs\test\report.md
```

The `docs/plans/wp2-config-contract-plan.md` orphan-doc WARN above is
resolved by this entry's own link to it, the same way WP1's plan file avoided
the same WARN — informational, not a `check.ps1` failure either way.

**Decisions taken (per plan §6, flagged for batch ratification)**

1. Missing `ConfigVersion` is fatal (not assumed `1`).
2. Unknown keys are rejected, not warn-and-ignore.
3. A JSON config with >1 `BackupSets` warns (IF-001), does not fail.
4. IF-001 `Version` stays `v1`; `Stability` stays `Experimental` pending WP1
   also being Verified (**not** flipped by this entry — separate decision).
5. Runtime validation is hand-rolled (`Import-BackupConfiguration`); the
   published `container/FileBackup.schema.json` is documentation, with TC-077
   pinning their equivalence.

**Deviations from the plan, and why**

- **The two `Engine.Tests.ps1` JSON-fixture updates moved from Phase D to
  Phase C.** The plan's ordered implementation list (§4) put them in Phase D
  alongside the other artifact versionizing, but its own §5 regression-risk
  table says the fixtures "become invalid the moment `ConfigVersion` is
  required" — which is Phase C, not D. Landing the fix in Phase C (commit
  `a6df81e`) keeps that phase's commit genuinely green rather than leaving a
  known-red window between C and D.
- **`-ExitCode` and `Exit-ConfigFailure` landed in Phase C, not E.** The plan's
  §4 phase list assigns `-ExitCode` to Phase E, but §2's loader design ties the
  switch's failure path directly to the logger-ordering change Phase C already
  had to make (the logger must exist before the config load so a load failure
  can be logged) — splitting them would have meant either a Phase C without a
  working failure path or a Phase E that silently depended on Phase C internals
  it hadn't announced. Phase E's actual work was the `.PARAMETER`/`.NOTES`/
  README documentation, TC-078, and the `entrypoint.sh` flag — all still
  sequenced and committed as planned.
- **TC-076/TC-077 placed in `Coverage.Tests.ps1`, not `Engine.Tests.ps1`.** The
  plan names both TCs but not a file; `Coverage.Tests.ps1` already hosts every
  other integration-style test that drives a real `FileBackup.ps1` run and
  byte-compares a restore (SR-004/012/013/026/028 etc.), so the example-config
  and schema-parity tests joined that file rather than `Engine.Tests.ps1`
  (which stayed pure-function/direct-loader tests per Phase B's own framing).

**Known items for the reviewer.**
- `Assert-NoUnknownConfigKey`'s per-set path uses a literal `[?]` placeholder
  in one `Test-BackupConfigurationShape` message (`$.BackupSets[?].CompressEnabled`)
  rather than the failing set's real index, because that check runs after the
  loop variable no longer carries its array position — the *key-name* messages
  from `Assert-NoUnknownConfigKey` do carry the real `[i]` index; only the
  *type* message for `CompressEnabled`/`PreserveFolderTree` does not. Minor,
  cosmetic, TC-075 asserts on the substring `*CompressEnabled*JSON boolean*`
  rather than the exact set index.
- The example-config integration test (TC-076) skips (via `Set-ItResult
  -Skipped`) rather than fails when no 7-Zip is found at the platform default
  path, since the checked-in example has `CompressEnabled: true` and this
  environment happens to have 7-Zip installed — worth confirming CI's image
  also has 7-Zip on the default path so this doesn't silently skip there too.

**Next action (awaiting human):** independent review of the WP2 config-loading
surface (schema validator correctness, the closed-schema/credential-ban logic,
the exit-code wiring), then batch ratification alongside WP1 and the other WPs.

---

### INDEPENDENT REVIEWER (Opus subagent) — WP1 restore trust & diagnostics — 2026-08-22

**Verdict: APPROVE-WITH-MINORS.** Read-only pass over the committed WP1 surface
(`a6ddc5f..47e2f93`): witness writer, exit-code taxonomy, both restorers'
verification, move-loop aggregation, registries. No data-integrity defect found;
the findings below were dispositioned by the driver and landed the next day.

### DRIVER (Software + Test Engineer hats) — WP1 review fixes — 2026-08-23

Landed the accepted findings from the 2026-08-22 review. Behavior changes are
confined to the restore path and the witness verifier; the backup pipeline is
untouched.

**What landed, by finding**

- **Top-level error routing in `Reconstruct.ps1` (MEDIUM).** An unclassified
  terminating error — e.g. `New-Item` throwing because a FILE occupies the
  target path — escaped and left the process exit status at **1**, the code
  README's table reserves for *content unrecoverable / data loss*, while bash
  returned **2** for the same cause. A script-level `trap` now routes any
  failure the script did not classify to the **precondition** class (exit 2
  under `-ExitCode`; rethrow otherwise, so in-process callers still see the
  original error), and the target-directory / log creation route their own
  failures explicitly through the same class. PS and bash now both return 2 for
  target-is-a-file. Pinned by a new case in TC-070's Describe and its bats twin
  in `exit_codes.bats` (bash already returned 2; it is pinned now).
- **Verification hoisted above mutation (asymmetry ruling — preferred fix).**
  `Read-RawManifest`'s header-shape + witness checks now run **before** the
  target folder and `RECONSTRUCT.log` are created, matching `reconstruct.sh`
  exactly. On any exit-2/exit-3 refusal the PS restorer writes **nothing** into
  the target — not a row, not a log — so README's "no file is written to the
  target" is now literally true. Pre-target log lines are buffered
  (`Add-ReconstructLog`) and flushed once the log exists; refusals go to the
  console/stderr and the thrown error. TC-068/TC-070 now assert *nothing* is
  written (no folder created where it did not exist; no `RECONSTRUCT.log`
  dropped into a folder the operator already had).
- **SR-039 registry truth-up (MEDIUM).** AcceptanceCriteria now states what the
  code does: a replaced/garbage (unrecognizable-header) manifest aborts with the
  **precondition** code 2 (precedence 2 > 3), truncated/byte-edited manifests
  with the witness code 3; the "nothing written into the target" claim is kept
  and is now literally true. The Rationale's false distinction ("a *legacy*
  garbage manifest fails the header check") is dropped — **all**
  unrecognizable-header manifests fail the header check first, whatever their
  provenance; the digest catches damage that preserves the header shape.
- **`MANIFEST.csv.meta.tmp` added to the infrastructure allowlist.** A crash
  between `WriteAllText` and `Move-Item` leaves the witness staging file behind;
  it must not be backed up as user data nor warned about as an orphan. Root-level
  only, as ever (B6). Noted in LLR-038's Detail.
- **Rows-only mismatch demoted** (honors plan §6 decision 3 — *the digest is
  authoritative*). In `Test-ManifestWitness` and `verify_manifest_witness`, when
  `Bytes` and `XxH128` both match but `Rows` disagrees, the verdict is
  **Verified with a warning** (counting-semantics divergence) instead of an
  abort: the manifest is byte-identical to the one that was witnessed, so the
  *count* is what is wrong, not the index. Order stays Bytes → Rows → XxH128;
  a Bytes or digest mismatch still aborts, and a Rows disagreement with **no
  digest to defer to** still aborts. New unit case each side.
- **Perf: `Write-Manifest` no longer re-reads the manifest** with `Import-Csv`
  just to count rows — it passes the record count it already holds through
  `Write-ManifestWitness -RowCount`. A standalone re-stamp (tests tampering on
  purpose) omits it and the file is counted as before. TC-066's `Rows=0`
  empty-set case still passes unchanged.
- **Vacuous assertion fixed** (`Coverage.Tests.ps1`, TC-067). `$rootDigest =
  (Test-ManifestWitness …).Path` grabbed a *path*, so `Should -Not
  -BeNullOrEmpty` could never fail. It now reads the sidecar's real `XxH128`
  value, asserts it equals the backup root manifest's digest, and the
  snapshot-vs-root inequality is compared against that digest — the assertion it
  always meant to make.

**Accepted as-is (deliberately NOT changed):** the `Exit-Reconstruct`
unapproved-verb nit; `MANIFEST.csv` remaining a non-atomic `Export-Csv` (the
stale-witness crash window fails loud in the safe direction — AGENTS.md §4).
The reviewer's clarifying sentence was added wherever "atomic rename" is
claimed (AGENTS.md §3 + §4, `Write-ManifestWitness`'s `.NOTES`, README's
manifest section): **the atomic rename publishes the WITNESS, not
`MANIFEST.csv` itself.**

**Evidence (all genuinely run, 2026-08-23)**

```
Invoke-Pester tests\Unit\Common.Tests.ps1    -> Tests Passed: 21, Failed: 0
Invoke-Pester tests\Unit\Coverage.Tests.ps1  -> Tests Passed: 47, Failed: 0
pwsh scripts/gen_arch_map.ps1                -> [OK] Generated regions already current (x2)
python scripts/trace.py --strict --require-verified --phase core,bash-v1
  -> Traceability: SN=27 SR=43 LLR=42 TC=77 orphans=0 integrity=0
     status-findings=0 phase-deferred=2
pwsh scripts/check.ps1 -Tier Full
  -> [PASS] PSScriptAnalyzer / Traceability / Doc navigability / Architecture map
     freshness; Pester unit Tests Passed: 108, Failed: 0; [PASS] Performance
     budgets; Integration sweep PASS: 236  FAIL: 0  SKIP: 4
  -> "================ check.ps1 (tier Full, gate G3) ================
      All steps passed."
wsl bash -lc "bats tests/bash"  -> 1..48, all ok (45 before; +3 new cases)
wsl bash -lc "shellcheck bash/reconstruct.sh" -> clean
```

**Deviations from the work order (small, deliberate).**
- **SR-039's *Requirement* cell was truthed up too**, not only Acceptance and
  Rationale: the demoted rows-only mismatch and the before-any-mutation ordering
  would otherwise have left the normative sentence false. Same for LLR-039 /
  LLR-040's Detail cells.
- **The top-level catch is a script-scope `trap`, not a `try` wrapping the
  script body** — a `try` would have meant re-indenting ~400 lines of restore
  logic for no behavioral difference. `Exit-Reconstruct` sets a `$classified`
  flag so the trap re-throws our own classified failures verbatim (the six
  `Should -Throw` wordings are untouched).
- **AGENTS.md §6's automated totals were stale** (83 Pester unit / 45 bats,
  written before WP2 landed its tests). Corrected to the measured **108 Pester /
  48 bats** rather than only adding this change's +2/+3.

**Next action (awaiting human):** batch ratification of WP1 (implementation +
review + these fixes) alongside WP2; then the WP3 container/release pass.

### INDEPENDENT REVIEWER (Opus subagent) — WP2 config contract — 2026-08-22

**Verdict: CHANGES-REQUESTED.** Read-only pass over the committed WP2 surface
(`444ee8f..ba1ee48`): the loader, the entry point, the published schema, the
fixtures and the registries. The blocking finding is a **data-loss** one, with a
reproduction:

- **HIGH — only two booleans were type-checked.** `Test-BackupConfigurationShape`
  applied its strict-type rule to `CompressEnabled`/`PreserveFolderTree` only, so
  `"AllowEmptySource": "false"` — a JSON *string* — sailed through the closed-schema
  check and reached `Resolve-BackupSetDefaults`, where `[bool]'false'` is `$true` in
  PowerShell. The reviewer ran it: the delete-all refusal (SR-036) was **disarmed by
  a quoting mistake**, the run wiped the backup root and exited **0**. Same class:
  `"SourcePath": ["x","y"]` became the literal path `x y` via `[string]`.
- **HIGH — one corpus, seven schema↔validator divergences.** TC-077's accepted /
  rejected fixture lists were a hand copy of TC-074/075's, and schema and validator
  disagreed on the six type cases above, on a bare single-set object (the plan says
  accepted-and-wrapped; the schema said array-only) and on `ConfigVersion: 1.0`.
- **MEDIUM — a missing config file exited 1, not 2.** The `Test-Path` existence check
  sat *outside* the try that maps config failures — telling NagLight to retry forever
  on the likeliest container misconfiguration of all.
- **MEDIUM — a refused config truncated the previous run's global log.** Logger
  creation had been moved *before* validation, and `New-Logger` truncates
  (`New-Item -Force`), falsifying TC-075's "no artifact is created by a refused run".
- **MINORS** — TC-074's `Add-Member ConfigVersion` escape hatch defeated the very
  drift the fixture exists to catch; TC-076's 7-Zip skip guard ran *before* the cheap
  keys-only contract check (and CI's `unit` job had no 7-Zip precondition); a literal
  `$.BackupSets[?]` in the message instead of the real index; AGENTS.md's test counts;
  no explicit numeric-range guard on `ConfigVersion`; `container/entrypoint.sh` missing
  from CI's shellcheck list; `Test-Json -Path` needs pwsh 7.4, above the stated floor.

### DRIVER (Software + Test Engineer hats) — WP2 review fixes — 2026-08-23

Landed every accepted finding above. The behavior changes are confined to
configuration loading and the entry point's failure path; the backup pipeline,
the restore path and the CLIXML branch are untouched.

**What landed, by finding**

- **Every schema value is type-checked now (HIGH).** `Test-BackupConfigurationShape
  -StrictTypes` validates each value against its JSON type through a new
  `Test-ConfigValueJsonType` (+ `Test-IsJsonNumber`, `Get-ConfigValueJsonTypeName`):
  JSON strings for `Name`/`SourcePath`/`BackupPath`/`ChangePath`/`HashRecalcFreq`/
  `SourceStatePath`/`Tools.*`/the `Secrets` strings, JSON booleans for
  `CompressEnabled`/`PreserveFolderTree`/**`AllowEmptySource`**, a JSON integer for
  `Secrets.SmtpPort`, and the container types of `BackupSets`/`Tools`/`Secrets`. No
  coercion can run before the type is known, so the reviewer's exploit is dead at the
  door (re-run below). Fixtures added for AllowEmptySource-string, SourcePath-array,
  Name-number, SourceStatePath-number, Tools.SevenZipPath-number and
  HashRecalcFreq-array (`[string]@('A')` is `'A'`, so the array used to pass the enum
  check as well).
- **ONE shared fixture corpus (HIGH).** New `tests/Common/ConfigFixtures.ps1` holds
  7 accepted + 27 rejected fixtures with their expected message; TC-074, TC-075 **and**
  TC-077 all drive it via Pester `-ForEach`, so a divergence can no longer hide in a
  hand copy and a new defect is written down once. Schema alignment: `BackupSets` is
  now `anyOf [array-of-set, set]` (the bare single object the plan promised and the
  loader always wrapped), and `ConfigVersion`'s `const: 1` is documented as accepting
  an integral-valued number — JSON has one number type, so `1.0` **is** `1`, for the
  schema (verified: `Test-Json` returns True) and the validator alike; `1.5`, `0`,
  `"1"` and anything above 1 are refused by both.
- **A missing config file exits 2 (MEDIUM).** The existence check routes through
  `Exit-ConfigFailure` like every other config failure, so it exits 2 under `-ExitCode`
  and still *throws* without it (the harness and `Engine.Tests.ps1` rely on the throw).
  An unsupported extension does the same.
- **A refused run creates nothing (MEDIUM).** Log-*file* creation is deferred until
  after `Import-BackupConfiguration` succeeds; the config-time messages (the multi-set
  `WARN`) are buffered and flushed once the log exists — the same pattern
  `Reconstruct.ps1` uses for its pre-target lines. `Exit-ConfigFailure` writes to
  stderr and *appends* to the global log only when that file already exists, so the
  previous run's log is never truncated and no log directory is created. TC-075's
  registry claim is now true, and TC-078 asserts both halves.
- **Minors.** TC-074's `Add-Member ConfigVersion` escape hatch is gone (the example is
  loaded verbatim from disk); TC-076's cheap keys-only diff now runs **before** the
  7-Zip skip guard and CI's `unit` job asserts 7-Zip is present (mirroring
  `integration-subst`); messages name `$.BackupSets[<real index>]`; `ConfigVersion` is
  range-checked *before* the `[int]` cast (an out-of-Int64 version is refused as an
  unsupported version, not by fractional-representation luck); `container/entrypoint.sh`
  joined CI's shellcheck list (clean); `Test-Json` is called with `-Json`/`-Schema`
  **strings** because `-Path`/`-SchemaFile` need pwsh 7.4 and AGENTS.md's floor is
  PowerShell 7+; AGENTS.md §6's totals corrected to the measured counts.

**Evidence (all genuinely run, 2026-08-23)**

```
# The reviewer's AllowEmptySource repro, re-run against the fixed loader:
run 1 exit=0  backup files=10
  stderr: FileBackup: Config '...\config.json' is invalid:
          $.BackupSets[0].AllowEmptySource - must be a JSON boolean,
          not string ('false') (expected a JSON boolean).
run 2 exit=2 (expect 2)
backup still holds keepme.txt: True
previous log preserved: True

Invoke-Pester tests\Unit           -> Tests Passed: 172, Failed: 0   (was 108)
python scripts/trace.py --strict --require-verified --phase core,bash-v1
  -> Traceability: SN=27 SR=43 LLR=42 TC=77 orphans=0 integrity=0
     status-findings=0 phase-deferred=2
pwsh scripts/gen_arch_map.ps1  -> Updated generated regions in docs\architecture.md
                                  Updated generated regions in AGENTS.md
wsl shellcheck -x bash/reconstruct.sh container/entrypoint.sh
    tests/bash/helpers.bash tests/bash/verify_restores.sh   -> SHELLCHECK-CLEAN
wsl bats tests/bash/  -> ok 48 (1..48, all ok)
pwsh scripts/check.ps1 -Tier Full  (exit 0)
  -> "  PASS: 236   FAIL: 0   SKIP: 4"          (SKIP = G8 RealVolume x4 modes)
     "[PASS] Integration sweep (Full)"
     "================ check.ps1 (tier Full, gate G3) ================
      All steps passed." 
```

**Deviations from the work order (small, deliberate).**
- **The type checker is three module-private helpers, not an inline block.**
  `Test-ConfigValueJsonType` / `Test-IsJsonNumber` / `Get-ConfigValueJsonTypeName` are
  exported to nobody but appear in the generated module map (regenerated). The integral
  test avoids both `[math]::Floor` (ambiguous overload for the `BigInteger` a huge JSON
  number parses to) and culture-dependent string formatting.
- **`Secrets.Credential` in JSON keeps its own named error** rather than folding into
  the generic unknown-key message — it is the one key with a real remediation
  ("use CLIXML, or `-NoMail`").
- **SR-042/SR-043 stay `Verified`** (they were flipped in WP2 phase F): the new
  fixtures land green in the same commit, so there is no window where the claim is
  unbacked. SR-042/043's Requirement and AcceptanceCriteria cells were truthed up to
  state the full type rule, the missing-file case and the no-artifacts guarantee;
  LLR-042/043's Detail and TC-074..078's Parameters/Expected likewise.

**Next action (awaiting human):** batch ratification of WP1 **and WP2**
(implementation + independent review + these fixes); then the WP3
container/release pass.

### INDEPENDENT REVIEWER — WP1 re-verification — 2026-08-22
Verdict: **APPROVE** (upgraded from APPROVE-WITH-MINORS). All seven findings
re-verified as genuinely closed against a pristine export of `84674e3`:
unclassified errors route to exit 2 without swallowing the preserved throw
wordings (probed with a locked-manifest error: child exit 2, in-process still
throws the original message); SR-039/LLR-038..040 cells match the
implementation (trace integrity 0); verification is hoisted with the log
buffer flushing correctly (refusals leave a pre-existing target byte-empty of
new files); `.meta.tmp` allowlisted root-level-only (B6 intact all four
combinations); Rows-only mismatch defers to the digest in BOTH restorers
(doctored `Rows=42` restores with a warning; rows mismatch with no digest
still exits 3); `$Records.Count` edge cases hold (null/empty/single/list);
TC-067 compares real digests. Evidence (pristine export): unit 108/108,
integration 236/0/4, bats 48/48, shellcheck clean, trace 0/0/0. One optional
wording tighten (the late capacity/7-Zip code-2 preflights run after
target+log creation, identically in both restorers) applied by the driver in
`Reconstruct.ps1` `.NOTES` and AGENTS.md §3 in the same commit as this entry.

### DRIVER (Software + Test Engineer hats) — WP3 container release-verify + smoke depth — 2026-08-23
Executed [docs/plans/wp3-container-release-plan.md](plans/wp3-container-release-plan.md) §5 steps 1-4 and 7-8
(steps 5-6, the push and post-CI status flips, are the driver's — real CI
evidence has not landed yet). Grounded at `ba1ee48`; re-read current file
state before editing per the plan's own caution (WP2 review fixes had since
touched `Invoke-Container.ps1`'s smoke config area, `tests.yml`'s unit-job
7-Zip precondition and shellcheck list, and the unit count).

**Landed:**
- `scripts/Invoke-Container.ps1`: new `Load` action (`docker load`, symmetric
  with `Export`); the smoke kit check now lists all 8 real kit artifacts
  (added `RECONSTRUCT.paths.json`, the genuine gap the plan's grounding pass
  found — the "witness sidecar" disposition text was stale, `MANIFEST.csv.meta`
  was already checked since WP1); a second, source-mutating container run
  appended strictly after the existing single-run assertions, asserting
  exactly one `Snapshot_<date>` folder under `/changes`, re-running the
  8-artifact kit check against both `/backup` and the snapshot folder, and
  two more restore containers — one restoring `/backup` (latest) compared
  against the mutated source, one invoking `RECONSTRUCT.ps1` from *inside*
  the snapshot folder itself (per grounding note 4: the authority folder is
  wherever the invoked script physically lives) compared against a
  pre-mutation `source-gen1` copy taken before the mutation.
- `.github/workflows/tests.yml`: `container` job gains a `registry:2`
  service, an Export→`docker rmi`→Load→Test step and a Publish→`docker rmi`
  (both tags)→Pull→Test step, a bounded `curl --retry` registry-readiness
  check before Publish, a one-line localhost-trust comment, and
  `timeout-minutes: 20`→`25`.
- Registries: minted **SN-028, SR-044, LLR-044, TC-079, TC-080** (all
  `Draft`/`Phase=container-v1`) and reworded TC-060's `Expected` to describe
  the 8-artifact kit + load roundtrip + registry roundtrip CI now proves,
  per plan §1. `python scripts/trace.py --strict`: **SN=28 SR=44 LLR=43(of
  44; LLR-019 is a pre-existing gap) TC=79(of 80; TC-029 likewise) orphans=0
  integrity=0.**

**Ratchet NOT re-armed — deviation from plan §2/§4, per the work order's own
contingency clause.** Bumping `--phase` to `core,bash-v1,container-v1` in
both `check.ps1` and `tests.yml`'s traceability job makes
`--require-verified` report a real status-finding (`SR-034 is
Verification=Test but Status=Implemented`), because SR-034/TC-060 are still
pending a green CI run of the new container steps — this is expected
pre-CI, not a defect. Per instruction, **kept both files at `--phase
core,bash-v1`** and left a `TODO(WP3 ratchet)` comment at each site naming
the exact commit-time condition (driver flips `--phase` to
`core,bash-v1,container-v1` in the same commit that flips
SR-034/LLR-034/TC-060/SR-044/LLR-044/TC-079/TC-080 to `Verified`/`Pass`,
after real green CI). SR-034/LLR-034 Status columns and TC-060/079/080
Status columns are untouched (still `Implemented`/`Draft` as the plan
requires until CI proves it).

**Local verification — Docker unavailable on this host.** `docker version`
and `docker` on PATH both fail (`docker: command not found` / not
recognized); the only container tooling present is Podman
(`C:\Program Files\RedHat\Podman\podman.exe`) plus a **stopped** WSL
`podman-machine-default` distro — no running container engine. Per the work
order's contingency, did **not** fake a green `BuildAndTest` run. Static
verification performed instead:
- `Invoke-ScriptAnalyzer -Settings tests/PSScriptAnalyzerSettings.psd1` on
  `scripts/Invoke-Container.ps1` and `scripts/check.ps1`: **0 findings**
  (also swept by `check.ps1 -Tier Full`'s own lint step, see below).
- `[System.Management.Automation.Language.Parser]::ParseFile` on
  `Invoke-Container.ps1`: **no parse errors.**
- Manual code review of the new incremental/snapshot block: mount
  read/write modes match the existing pattern (`/backup`, `/changes`
  writable on the backup run, read-only on every restore run); the
  `source-gen1` copy happens before the host-side mutation and lives outside
  every bind-mounted directory; `$runArgs` is reused verbatim for the second
  `docker run` (same mounts, same image) as the plan specifies; the
  snapshot-restore invocation points at
  `/changes/<Snapshot_name>/RECONSTRUCT.ps1` with explicit
  `-BackupRootOverride /backup -ChangeRootOverride /changes`, matching
  grounding note 4 exactly.
- **In-container proof (BuildAndTest, Load, Publish/Pull, and the new
  incremental/snapshot smoke assertions actually executing) has NOT
  happened locally and awaits the first push's CI run of the `container`
  job**, per the work order.
- WSL shellcheck was not re-run: no `.sh` file was touched by this step (only
  `Invoke-Container.ps1`, `tests.yml`, `check.ps1`, and the registries).

**`pwsh scripts/check.ps1 -Tier Full` (Gate G3) — genuinely green, real
output:**
```
==== PSScriptAnalyzer ====
[PASS] PSScriptAnalyzer

==== Traceability (trace.py --strict) ====
Traceability: SN=28 SR=44 LLR=43 TC=79 orphans=0 integrity=0
status-findings=0 phase-deferred=3.

==== Doc navigability (check_docs.py) ====
[PASS] Doc navigability (check_docs.py)

==== Architecture map freshness ====
[PASS] Architecture map freshness

==== Pester unit ====
Tests Passed: 172, Failed: 0, Skipped: 0, Inconclusive: 0, NotRun: 0
[PASS] Pester unit

==== Integration sweep (Full) ====
TEST SUMMARY
  PASS: 236
  FAIL: 0
  SKIP: 4
[PASS] Integration sweep (Full)

================ check.ps1 (tier Full, gate G3) ================
All steps passed.
```
(`--phase core,bash-v1` still in force, so `status-findings=0` here —
`phase-deferred=3` now covers SR-033 (bash-v2) plus SR-034/SR-044
(container-v1); this is the expected pre-CI shape, not a regression.)

Commits (this session, `resync_v2`, no push — the driver pushes): container
script + smoke depth; CI Export/Load + Publish/Pull roundtrip (phase left at
`core,bash-v1` with TODO comments); registry mints + TC-060 reword.

**Awaiting:** the driver's push, a real green CI run of the `container` job
(BuildAndTest, Export/Load roundtrip, Publish/Pull roundtrip, incremental +
snapshot smoke all passing in-container), the ratchet re-arm to
`core,bash-v1,container-v1` alongside the SR-034/LLR-034/TC-060/SR-044/
LLR-044/TC-079/TC-080 status flips, independent review, and batch
ratification. Current State tallies below updated to SN=28 SR=44 LLR=44
TC=80 per plan §1 (registry *row* counts — trace.py's summary line counts
distinct ids present out of the numeric range, so it reports LLR=43/TC=79
because of the pre-existing LLR-019/TC-029 gaps, not because a row is
missing here).

### INDEPENDENT REVIEWER — WP2 re-verification — 2026-08-22
Verdict: **APPROVE** (upgraded from CHANGES-REQUESTED). All findings
re-probed on a pristine export of `b67cdcf` and confirmed closed: the
AllowEmptySource `"false"` delete-all repro now refuses with
`$.BackupSets[0].AllowEmptySource — must be a JSON boolean` and exit 2,
creating no directories; every other type coercion (SourcePath array, Name
number, HashRecalcFreq array, Tools/Secrets types, SmtpPort string,
BackupSets string) refused with the key named; the shared fixture corpus
(7 accepted / 27 rejected, the shipped example itself a fixture) drives
TC-074/075/077 with schema↔validator parity on all twelve probe rows
including the bare-set `anyOf` and integral-float ConfigVersion; missing
config exits 2 (pinned); a refused config appends to an existing log and
creates nothing in a fresh path (pinned); all minors closed (real
BackupSets index, ConfigVersion range guard, 7-Zip CI precondition,
entrypoint.sh in shellcheck scope, PS 7.0-floor Test-Json form, AGENTS.md
counts 172/48 match measurement). Deviation ruling: keeping SR-042/043 at
`Verified` was ACCEPTED — the fixes and fixtures land green in one commit,
so no commit exists where the row overclaims; the premature `ba1ee48` flip
stays on record in the CHANGES-REQUESTED audit entry. Evidence (pristine
export): unit 172/172, integration Mirror 59/0/1, trace 0/0/0, lint clean.
**WP1 and WP2 are now both implemented + independently review-APPROVED;
awaiting batch ratification.**

### DRIVER (Software + Test Engineer, Data-integrity hat) — WP4 snapshot retention — 2026-08-23
Executed [docs/plans/wp4-retention-plan.md](plans/wp4-retention-plan.md) §3 phases A→F in order, grounded at
`3ee8f5b`/`b4f108c`, one commit per green phase. The plan's §5 driver decisions
were treated as binding: the verb is **`Remove-BackupSnapshot`** (`Prune-` fails
approved-verbs lint), an **absent witness refuses by default**
(`-AllowUnverifiedIndex` overrides — the deliberate inverse of the restore
default), and **unreferenced bytes refuse by default**
(`-DiscardUnreferencedData` overrides).

**Phase A (highest care) — index extraction, zero behavior change.** TC-089
landed FIRST and was run green against the PRE-refactor code, then
`Get-BackupContentIndex` was lifted literally out of `Optimize-ChangeFolders`
(same key construction, same blank/missing guards, same folder ordering) and
Optimize refactored to consume it. Full tier re-run including TC-049.
Commit alone, as the plan requires.

**Phases B–E.** `Get-SnapshotPrunePlan` / `Get-BackupSnapshot` (pure,
read-only); `Assert-PrunePrecondition` / `Test-PoolResolves` (the rails);
then the transaction — `Copy-ReHomedDataFile`, `Publish-PruneManifest`,
`Complete-PruneDeletion`, `Invoke-PruneEntrySweep`, with
`Remove-BackupSnapshot` as a short ordered list of named steps; then the
adversarial and interrupt/resume tests. §4's regression risks were treated as
constraints: prune never copies `MANIFEST.csv.meta` between folders and every
rewrite goes through `Write-Manifest` (TC-085 pins both halves with an AST
guard); TC-084 re-stamps tampered witnesses so the intended failure is what is
observed; the store — `FileBackupState.json` included — is hash-compared
byte-for-byte after every refusal.

**Phase F — boundary.** `FileBackup.ps1 -Action Backup|Prune|Snapshots` +
`-Snapshot` (the Backup path is untouched); `container/entrypoint.sh` dispatches
on `FILEBACKUP_ACTION` or a leading positional word and leaves every
`-`-prefixed argument in `"$@"` exactly as before; README "Snapshot retention
(pruning)" + the container action block; IF-001 rewritten per §1.6 (SR-Refs
+= SR-045..048, the "planned `Prune-Snapshot` verb" wording replaced);
AGENTS.md §2 module map + entry-point row and a new §3 invariant ("a
`Snapshot_*` folder is removed only by `Remove-BackupSnapshot`"); arch map
regenerated; §6 totals refreshed.

**Deliberate deviations (both recorded in the registry cells):**
1. `Assert-PrunePrecondition` **returns** the full refusal set instead of
   throwing on the first one, so `Remove-BackupSnapshot` can apply the
   2 > 3 > 4 > 1 precedence over all of it and `-WhatIf` can report every
   refusal at once (LLR-046 states this).
2. TC-081 and TC-083 are declared `Tier=Smoke`, not `Full`: they live in the
   Pester suite, which every tier runs, and claiming Full would understate
   where they actually execute.

**Defects found while testing (both fixed here):**
- `@($empty.FullName)` yields `@($null)`, which fails a `[string[]]` binding —
  pruning the LAST remaining snapshot aborted with a spurious code 4. All three
  index call sites now project with `ForEach-Object`. (A close cousin of the
  PS 7.5 `@()`-over-a-List gotcha already in AGENTS.md §4.)
- The first draft of TC-082's "stored exactly once" assertion counted copies by
  hashing raw files, which is wrong in the two `+Compress` modes (the stored
  file is a `.7z` whose own bytes hash to something else). It now counts through
  `Get-BackupContentIndex`.

**Also fixed:** `-Action Snapshots` first emitted its JSON down the pipeline,
where the caller captured it as part of the status code — it now writes to
`[Console]::Out` (probed in a child process before and after).

**Evidence — real output, this host.**
```
pwsh scripts/check.ps1 -Tier Full        (gate G3, --phase core,bash-v1)
[PASS] PSScriptAnalyzer
Traceability: SN=29 SR=48 LLR=47 TC=89 orphans=0 integrity=0
              status-findings=0 phase-deferred=4.
[PASS] Doc navigability (check_docs.py)
[PASS] Architecture map freshness
Tests Passed: 223, Failed: 0, Skipped: 0
[PASS] Performance budgets (check_perf.py)
  PASS: 324   FAIL: 0   SKIP: 4
All steps passed.
```
```
WSL (podman-machine-default):
  bats tests/bash            -> 48 ok / 0 not ok
  shellcheck container/entrypoint.sh -> clean
```
Baseline before WP4 was unit 172, integration 236/0/4; the deltas are +51 unit
(TC-081..089 minus TC-088's container half) and +88 integration (G9's retention
half, 22 assertions × 4 modes).

**Status flips:** SR-045/046/047 → `Verified`, LLR-045/046/047 → `Verified`,
TC-081..087/089/090 → `Pass`. **SR-048 stays `Implemented`** (Phase
`container-v1`) with LLR-048 `Implemented` and **TC-088 `Draft`**: Docker is not
available on this host, so the in-container half was NOT run and is not claimed.
TC-088's locally runnable halves — the `-Action`/`-Snapshot` parameter contract,
the real child-process invocations of every action (inventory JSON, prune,
unknown name → 2, dry run, legacy flags-only), the entrypoint dispatch and
`-`-pass-through source assertions, and the guard proving `bash/reconstruct.sh`
carries no removal path — all run and pass in the Pester suite. The
`--phase core,bash-v1` ratchet and its `TODO(WP3 ratchet)` comment are
deliberately untouched.

**Open-items:** row **I** → *Implemented (WP4) — awaiting independent review +
batch ratification*; new row **C-form** records the §5.7 latent defect
(blank-`Compressed` vs the located file's form after a compression-mode flip),
dispositioned to WP5 with WP4's `Test-PoolResolves` as the detector/repro.

**For the independent reviewer, in priority order:** (1) the transaction
ordering in `Remove-BackupSnapshot` — specifically that nothing is deleted
before `Test-PoolResolves -ExcludeFolder` has passed, and that the
`Pruning_<name>` rename is a genuine single commit point for *all three*
consumers (both restorers and Optimize); (2) the TC-049 interaction — a prune
transiently creates a second copy, and the "stored exactly once" property is
asserted on quiescent states only (TC-082); (3) destination election and name
synthesis in `Get-SnapshotPrunePlan` (does the elected destination always
already demand the key? is the collision guard tight enough in Mirror mode?);
(4) the form-agreement rule in `Test-PoolResolves`, including the deliberate
`.7z`-RelativePath exemption; (5) whether refusing to prune *into* an
already-broken pool is the right default given `-RepairFromPruned` is deferred
to WP5.

### DRIVER (Software + Test + Data-integrity hats) — WP5 storage-form trust — 2026-08-23
Verdict: implemented and green on a Full tier — **awaiting independent review +
batch ratification**. Work order:
[plans/wp5-storage-trust-plan.md](plans/wp5-storage-trust-plan.md), phases A→H,
one commit per green phase. Ids minted: **SN-030, SR-049..052, LLR-049..052,
TC-091..102.** Closes HomeHub cross-check finding **C**, the WP4-surfaced
**C-form** latent defect, the planning-pass **C-refcount (G10)** data-loss
defect, the **ext-list merge**, and the **backup-side capacity** row.

**Phase A — one shared predicate (557b2b1).** `Test-StorageFormAgreement`
extracted from `Test-PoolResolves`' inline check so prune (SR-046) and verify
(SR-049) ask the same question and cannot drift, carrying the documented
C-form exemption (a row whose own RelativePath ends `.7z` is not a
disagreement). Behavior identical; WP4's TC-083/084/089 re-run green.

**Phase B — REPRO, RED (ba9b35d).** The evidence commit. Real red output, run
before any fix, from `tests/Unit/StorageForm.Tests.ps1`:

```
[+] leaves every malformed row byte-identical and still reports the set successful (SR-049)
[+] swallows a failed transformation of a Compressed=Yes-over-raw row into a log line (SR-049)
[-] reports one finding per malformed row with its class (SR-049)
    CommandNotFoundException: The term 'Test-BackupStorageForm' is not recognized...
[-] restores a snapshot byte-exact after compression is turned on (mode Mirror) (SR-050)
    Expected: '2A7B9B01C49B84B0D15E4048E13F1BA772FE68630DECFBB711E6BCF807B4EF0D'
    But was:  '540C3E48515CBABA6BBFCAAA3A9AE442A3C74447AF3A80BDC29D1969D588CEE6'
[-] restores a snapshot byte-exact after compression is turned off (mode Mirror) (SR-050)
    RuntimeException: Reconstruction INCOMPLETE: 1 file(s) could not be restored
    (0 content-missing, 1 host): a.txt.
[-] restores a snapshot byte-exact after compression is turned on (mode HashAddressed) (SR-050)
[-] restores a snapshot byte-exact after compression is turned off (mode HashAddressed) (SR-050)
Tests Passed: 2, Failed: 5
```

The two PASSES are the defect: four malformed shapes survive
`Sync-BackupStorageLayout` byte-identical and the set still reports success,
because `$needsTransform` compares manifest metadata with configuration and
never with the bytes. The five failures are the requirement. Note the two
directions of the WP4 §5.7 defect: flipping compression ON gives **exit 0 with
7z container bytes written under the original filename** (silent corruption);
flipping it OFF gives **exit 4 misfiled as a HOST problem**. Both reachable with
NO tampering.

*Masking defect fixed in the same commit (new, not in any disposition):*
`Initialize-Dependencies` set `$deps['7z'] = $null` whenever `CompressEnabled`
was false, so turning compression OFF made the SR-012 migration silently inert
("7-Zip not found. Skipping transformation") and a documented configuration
change was never applied. 7-Zip is now resolved opportunistically and silently
on that branch (no prompt — SR-016).

**Phase C — SR-050, the data-integrity commit (4127edb).** Both restorers now
decide whether to decompress from the form the LOCATOR PROVED, not from the
row's `Compressed` (which describes only a file in the row's own folder).
`Find-DataFileByHash` gains `Form`; `find_by_hash`'s Found tuple becomes
`Found\037<form>\037<path>`; an archive candidate that fails to expand is
re-tested as raw bytes before a CandidateError (Q4). `# KitRevision: 2` markers
in both restorers (no prior convention existed; 2 is the first stamped one).
TC-092 4/4 GREEN, TC-098 6/6, TC-099 6/6 under bats on real Linux.

**Phase D — SR-051, refcount-safe migration (ddf52ab).** Closes G10. Verified
RED against the pre-fix engine before landing:

```
[-] keeps every row of a shared-content pair resolvable ... (mode Mirror)
    Expected $true, because row 'same.jpg' must still resolve after the migration, but got $false.
[-] retains a superseded path that a surviving row still references
    Expected $true, because a still-referenced superseded path must never be deleted, but got $false.
[-] reports a failed transformation ... and FAILS the set   Expected 1, but got 0.
```

Green after, in all four modes. A (hash,length) group is decided together, a
shared file is transformed once, Phase 2 retains any path a surviving row still
references, and a failed transformation fails the set.

**Phase E — SR-049, verify + repair (3e170f0).** `Get-StoredFileForm` (7z magic,
no hashing) → `Get-StorageFormFinding` (exactly one finding per row) →
`Test-BackupStorageForm` (root + every snapshot, mutates nothing) →
`Repair-BackupStorageForm` (bytes are ground truth; rewrites `Compressed` and
renames; never re-packs, never touches the six logical columns, refuses a rename
onto a root-level infrastructure name, persists ONLY through `Write-Manifest`)
→ `-Action Verify` on WP4's one dispatch (+`-VerifyStorage` alias,
`-RepairStorage`, `-Deep`, `-BackupRootOnly`/`-IncludeSnapshots`,
`-RefreshKits`) → the entrypoint word `verify`. Findings as JSON via
`[Console]::Out`. `Get-BackupKitRevision` reports the kit a snapshot is stuck
with on every blank-row finding. Two more defects found while testing and fixed
here: `Get-BackupContentIndex` threw on an empty `-SnapshotFolder` arriving as
`$null` (AGENTS §4 hazard), and the C-form exemption was applied to the flag
check but not the NAME check, so `already.7z` stored raw was reported as
`NameLies` in all four modes.

**Phase F — SR-004 merge (b1aafb5).** `.jar .tgz .zst .gif .webm .ogg .sav
.pack` added to the ONE list (Q6; no Office extensions — SN-003's acceptance is
a stakeholder decision). README gains the table, and TC-096 asserts it equals
the live list and that the list has one definition site. TC-097 (suite case
`G4.2`, four modes) builds a genuine PRE-merge store and re-runs on the merged
list: the triggered migration leaves nothing dangling, verifies clean, and every
state — both snapshots and the latest — restores byte-exact with exit 0; run2 ≡
run3.

**Phase G — SR-052 capacity (d082cda).** `Get-FreeSpaceBytes` /
`Get-VolumeIdentity` in **Common** (the kit stays self-contained), measuring via
`System.IO.DriveInfo` with `Get-PSDrive` as the drive-qualified fallback, never
throwing. `Reconstruct.ps1` rewired: its `Split-Path -Qualifier` lookup **threw
on a rooted POSIX path and was swallowed by the adjacent catch, so SR-023's
restore capacity check has been silently inert on Linux and in the container
since it was written** while bash's `df` half worked (planning finding G9).
Backup side: two pure demand estimators + `Assert-BackupCapacity`, called at
step 5.5 (migration) and 9.4 (content); a refusal removes the staging folder
before throwing so it cannot orphan a `Temp` for the next run's SR-017 guard,
and fails the SET (status 1), not the invocation. No configuration key (Q8).

**Phase H — boundary, docs, registries (this commit).** TC-102 lands as
`Test-ContainerStorageForm` inside the container smoke test (clean verify exits
0 / emits parseable JSON / mutates nothing; a seeded malformed row exits 1;
repair then re-verify exits 0); README gains the `-Action Verify` section, the
finding-class table, the merged-extension table and the **old-kit exposure**
statement with both remedies; AGENTS §2/§3/§4/§6 updated (three new invariants:
the blank-row form rule, the one-predicate rule, and the kit-revision rule; a
new gotcha forbidding `Split-Path -Qualifier` for volumes); IF-001 amended
(SR-Refs += SR-049;SR-052, the `verify` word, the capacity refusal); LLR-004 /
LLR-012 / LLR-023 / TC-002 amended per the plan's §3 table.

**Evidence (real, local, 2026-08-23):**

- `Invoke-Pester -Path tests\Unit` → **294 passed / 0 failed / 0 skipped**.
- `tests\Run-All.ps1 -NonInteractive` → **372 PASS / 0 FAIL / 4 SKIP**
  (G8 RealVolume under Subst).
- `bats tests/bash` on real Linux (WSL Fedora 40) → **54/54**;
  `shellcheck -S warning bash/reconstruct.sh container/entrypoint.sh` clean.
- `python scripts/trace.py --strict` → `SN=30 SR=52 LLR=51 TC=101 orphans=0
  integrity=0`.
- PSScriptAnalyzer over the maintained surface: clean.

**Honest gaps — what is NOT proven here.**

1. **Docker was unavailable on this host.** TC-102 and **TC-101's Linux half**
   have never been executed. TC-101/TC-102 stay `Draft`, and **SR-052 stays
   `Implemented`, not `Verified`** — its acceptance requires the restore
   capacity check to demonstrably fire on Linux, which is exactly the thing the
   `Split-Path -Qualifier` bug prevented, and no local run can show it. This
   means `check.ps1 -Gate G3` reports **exactly one status-finding** until that
   CI run; a `TODO(WP5, same CI run)` in `scripts/check.ps1` names it beside the
   WP3 ratchet TODO, and both flip in the same commit once the container job is
   green. SR-049/SR-050/SR-051 ARE Verified — their acceptance is fully covered
   by locally-passing TCs.
2. **WP5 does not close F3 for pre-existing snapshots restored by their own
   kit**, and never claimed to. A snapshot written before revision 2 keeps the
   defective kit permanently, including copies moved off-volume. The remedies
   are documented in README (restore with the root's current kit, or
   `-RefreshKits`), and the verifier reports each snapshot's kit revision.

**Findings for the independent reviewer.**

- **[MEDIUM] `Test-PoolResolves`' blank-row `form-mismatch` refusal is now
  conservative.** WP4 made it a code-2 prune refusal because "the restorers
  branch on the ROW". SR-050 removed that premise, so prune now refuses to
  prune a store that a revision-2 kit restores correctly — reproducible by any
  compression flip. Left UNCHANGED deliberately (a pre-revision-2 snapshot
  restored by its OWN kit is still exposed, and relaxing a Verified prune rail
  is not WP5's call). New Open-items row; targeted WP6.
- **[MEDIUM] A dangling `DataPath` becomes a permanently unrestorable row.**
  Observed while building TC-094: a row whose data file is missing is dropped by
  `Test-BackupManifest`, re-copied from source only if the diff sees a change —
  and where the source file is unchanged, `Optimize-ChangeFolders` blanks the
  `DataPath` instead, leaving a row whose bytes are nowhere in the pool while
  the run reports success. `Test-PoolResolves` detects it (`broken-pool`); no
  backup run does, and SR-049's form audit deliberately does not (it is not a
  FORM finding). Pre-existing, not a WP5 regression. New Open-items row.
- **[MINOR] Manifest row ORDER is not stable between consecutive no-op runs**
  (the final manifest is enumerated from a hashtable). Row CONTENT is stable, so
  SR-024 holds; TC-094 and TC-097 therefore compare rows sorted by
  `RelativePath` rather than raw file bytes. G7-Determinism does not catch it.
- **Scrutinize most:** the SR-050 change in both restorers (4127edb) — it is the
  one place where a wrong decision silently writes wrong bytes; the Phase 2
  retention filter and the group-consistency gate in
  `Sync-BackupStorageLayout` (ddf52ab); and `Repair-BackupStorageForm`'s rename
  path, which is the only WP5 code that moves a data file.

**Deviations from the work order.**

- TC-092/TC-095/TC-098/TC-100 landed in `tests/Unit/StorageForm.Tests.ps1`
  (which drives real multi-run backups and real restores in-process, as WP4's
  TC-081..090 do) rather than in G9-Rollback; TC-097 landed as the planned
  `G4.2` suite case. The bash half of TC-097's "both restorers" is covered by
  TC-099/TC-054 under bats — the Windows integration suite cannot drive
  `reconstruct.sh`.
- `-IncludeSnapshots` and `-BackupRootOnly` are the same knob, exposed both ways
  (`-IncludeSnapshots:$false` ≡ `-BackupRootOnly`) so the plan's §4 wording and
  the disposition wording both resolve.
- TC-091's "the set still succeeds" assertion had to FLIP at phase D: SR-051
  makes a failed transformation fail the set. The phase-B commit is the record
  of the pre-fix behavior.

---

### DRIVER (Software + Test Engineer, Data-integrity hat) — WP4 review fixes — 2026-08-23

**Verdict received: CHANGES-REQUESTED** on the WP4 snapshot-retention mechanism,
with one confirmed byte-loss path. Every accepted finding is landed here; the
work sits on `resync_v2` at `aa796db` (code + tests) plus this documentation
commit.

**H1 — HIGH, confirmed byte loss (fixed).** `Invoke-PruneEntrySweep`'s
`*.fbprune.tmp` cleanup was a bare-suffix recursive filter over the whole pool.
In Mirror mode a genuine user file `notes.fbprune.tmp` is stored at its verbatim
path and carries a manifest row, so the reviewer's repro — a **REFUSED** prune
(a typo'd snapshot name) — permanently destroyed every copy of it across the
backup root and every snapshot, and then wedged the store: the resulting
`broken-pool` rail blocks all future prunes, and breakage in the backup root
never self-heals. Fix: the sweep deletes a `.fbprune.tmp` only when the folder's
OWN manifest does not reference it (a staged copy is unreferenced by
construction; real content is not), and it scans only pool folders — the only
re-home destinations. Pinned by new TC-083 cases: the user file, root-level AND
nested, survives a refused prune, a `-WhatIf`, and a successful prune of another
snapshot, restores byte-exact from every origin afterwards, and a genuine
unreferenced staged copy beside it is still swept.

**H2/M1 — the entry sweep ran outside the transaction (fixed, behaviorally).**
The sweep now runs INSIDE the per-name transaction, after
`Assert-PrunePrecondition` passes and the Temp lock is held, so (a) its failures
land in the existing code-4 catch instead of escaping unclassified as process
exit 1, (b) refusal paths (2/3) genuinely mutate nothing, and (c) `-WhatIf`
skips it entirely — no log lines, no inflated count. The one thing that still
runs before the rails is deliberately name-scoped: `Remove-CommittedPruneResidue`
completes an outstanding `Pruning_<the same name>` deletion, which is past the
commit point, invisible to every consumer, and occupies the very name the plan
needs; it is wrapped so a host failure is a code-4 record, and it is skipped
under `-WhatIf`. Residue for any other name is left alone. This is what keeps
TC-083's after-commit-rename resume case working (re-invoking sweeps the residue
and then refuses `bad-target` with 2, exactly as before). SR-046 and LLR-046 now
state this ordering, and AGENTS.md section 3 carries the H1 warning.

**M2 — self-fulfilling assertion (fixed).** `tests/Suites/G9-Rollback.ps1`'s
per-state prune check derived `$expectF` from the restore output it was
validating, so a lost `f.txt` passed vacuously. The expectation now comes from
that snapshot's own manifest, and the "must be absent" half is asserted too.

**M3 — three untested rails (fixed).** TC-084 gains `destination-collision`
(hand-verified by the reviewer, now pinned), `infrastructure-name`, and
`capacity`. The capacity rail was rebuilt: WP4 grouped destinations by
`Split-Path -Qualifier` inside a `Group-Object` key, which cannot parse a UNC or
rooted POSIX path — terminating under the entry point's
`$ErrorActionPreference='Stop'`, and otherwise yielding an empty drive name that
the `Get-PSDrive` fallback rejected into a swallowing `catch`. Either way the
rail did not exist on a UNC store. It is now `Get-PruneCapacityRefusal`, built
on Common's `Get-VolumeIdentity`/`Get-FreeSpaceBytes` (SR-052, WP5), summing per
volume, refusing with 2 when free space is short on drive-qualified AND UNC
destinations (probe stubbed in tests), and SKIPPING rather than refusing when a
volume cannot be measured.

**M4 — TOCTOU on the Temp lock (fixed).** `New-Item -Force` succeeds on an
existing directory, so two prunes could both pass the staging-busy rail.
`-Force` is dropped so creation is the atomic test; the already-exists failure is
classified as the staging-busy refusal (2), and the `finally` block no longer
deletes a lock this invocation did not create. Pinned by a test that makes the
folder appear *after* the rails pass (mocked precondition), plus an AST guard.

**L1 — `-Action Backup -WhatIf` (fixed).** It bound because prune needs
`SupportsShouldProcess`, and produced a half-run. It is now refused as a
precondition before anything is read or created: exit 2 under `-ExitCode`, a
terminating error otherwise, with a message saying dry-run is Prune-only.

**Reviewer caveats recorded (not fixed).**

- **README and the broken-pool refusal now say it plainly**: an unresolvable
  pool blocks *every* prune in the store, nothing self-heals, run
  `-Action Verify` to enumerate the damage, and recovering content from a
  partially removed snapshot (`-RepairFromPruned`) is a recorded future item.
  The refusal message itself carries the "run -Action Verify" pointer.
- **L2 accepted as-is**: the AST guard over the prune path is lint, not proof;
  the digest-uniqueness assertion is the real pin.
- **L3 accepted as-is, recorded as a perf follow-up**: `Get-BackupSnapshot` is
  O(n^2) — one `Get-SnapshotPrunePlan` per snapshot, each rebuilding the pool
  index, and the plan hashes candidate files during what is advertised as a
  read-only inventory. Threading a shared index through `Get-SnapshotPrunePlan`
  is not a trivial edit to a data-integrity function, so it was NOT attempted
  here.

**Evidence (real, this host, 2026-08-23).**

- `Invoke-Pester -Path tests\Unit` → **310 Passed / 0 Failed / 0 Skipped** in
  241.94s (was 294; +16 for H1/H2/M3/M4/L1).
- `pwsh scripts/check.ps1 -Tier Full` → integration **372 PASS / 0 FAIL /
  4 SKIP** (Subst, four modes, G1–G9), PSScriptAnalyzer clean, doc navigability
  clean, architecture-map freshness clean, Pester unit green. The run's ONE
  failing step is the pre-existing G3 status finding carried from WP5:
  `SR-052 is Verification=Test but Status=Implemented` (TC-101's Linux half
  needs the Docker CI job). `python scripts/trace.py --strict --phase
  core,bash-v1` → `SN=30 SR=52 LLR=51 TC=101 orphans=0 integrity=0`, exit 0;
  with `--require-verified` the same single SR-052 finding, exit 1 — unchanged
  by this work.
- `pwsh scripts/check.ps1 -Tier Smoke -Gate G1` → **All steps passed.**
- No shell file changed, so bats/shellcheck were not re-run (bats 54/54 stands
  from WP5).

**Registry.** SR-046 (requirement, acceptance, permutations), LLR-046 (code
symbols and detail) and TC-083/TC-084 (parameters and expected) updated to
describe the behavior as it now is. No status flips: SR-045..047 stay Verified,
TC-083/TC-084 stay Pass, and no TC changed so materially as to need re-minting.

**Deviations from the work order.** None on substance. Two notes: (1) the work
order's fallback ("keep a pre-loop sweep gated to provably-residue items") was
not needed — full relocation works, with the name-scoped committed-residue
completion described above as the one documented pre-rail action; (2) the
reviewer's wording said `Split-Path -Qualifier` *throws* on UNC — it emits
"does not have a qualifier specified", which is terminating only under
`$ErrorActionPreference='Stop'` (the entry point's setting). The conclusion is
unchanged, and the test pins the actual behavior on both UNC and POSIX-rooted
paths.
---

### DRIVER (Software + Test Engineer, Data-integrity hat) — WP5 review fixes — 2026-08-23

**Verdict received: CHANGES-REQUESTED** on WP5 (storage-form trust), with one
confirmed data-loss path in the *repair* action and one silent-unrecoverability
path in *both* restorers. Every accepted finding is landed here: code + tests in
`c1cbd4f`, registries and documentation in this commit. The **restore kit is now
revision 3** in both `Reconstruct.ps1` and `bash/reconstruct.sh`.

**H1 — HIGH, `Repair-BackupStorageForm` corrupted deduplicated stores (fixed).**
Findings are emitted per ROW; the repair renames a PHYSICAL file. Dedup points
several rows at one file (SR-003), so the first row's repair renamed the file and
the second row's repair then saw `Missing` at the old path and skipped it — the
store was left with a row pointing at a path that no longer existed. The reviewer
reproduced it: a repairable `FlagOverRaw` pair came out as one healed row and one
unrestorable one. Repairs are now grouped by `(Folder, DataPath)`: the rename
happens ONCE, EVERY row referencing the old path adopts the observed form, and
the folder is persisted once through `Write-Manifest` — the same lesson `ddf52ab`
taught `Sync-BackupStorageLayout`. A row exempted from the flag rewrite by the
`.7z`-`RelativePath` rule still follows the file through the rename but keeps its
own `Compressed` (rewriting it from the bytes would make the restorer expand the
user's own archive). New TC-094 case: two identical-content rows sharing one
DataPath in the `FlagOverRaw` shape — **both** healed, one physical copy still
serves both, re-verify clean, restore byte-exact.

**H2 — MEDIUM-HIGH, a blank row for a genuine `.7z` SOURCE file was
unrecoverable while every checker called the store clean (fixed).** In both
locators, an archive candidate that expanded SUCCESSFULLY but whose payload did
not match was dropped without its own bytes ever being tested — and a real `.7z`
source file, which SR-004 deliberately stores raw, is exactly that shape (it *is*
a valid archive; its payload is simply not that row's content). The row's own
`.7z` `RelativePath` is the deliberate `Test-StorageFormAgreement` exemption, so
`-Action Verify` reported the store clean. Both restorers now test every
non-matching `.7z` candidate as raw bytes before dropping it — symmetric with the
existing failed-expand fallback and free on the happy path. Reachable with **zero
tampering** (the reviewer's recipe, now the test): an ordinary two-run timeline
whose source holds a real `.7z`; run 2 supersedes an unrelated file, so
`Optimize-ChangeFolders` blanks the archive's row in the snapshot.

**M1 — Sync's "7-Zip not found" skip contradicted SR-051 verbatim (fixed).** The
arm in `Sync-BackupStorageLayout` logged WARN and continued *without* setting
`$OverallSuccess`, so a run reported success over a store the configuration no
longer describes. One line: it now logs ERROR and fails the set. Pinned by a new
TC-095 case (`OverallSuccess` false, nothing mutated).

**M2 — `Get-VolumeIdentity` had no Linux semantics, and capacity never summed
(fixed).** `[System.IO.DriveInfo]::new($path).Name` is the IDENTITY function on
Unix — it echoes the path handed to it — so `/backup` and `/backup/sub` read as
*different* volumes and every same-volume decision was wrong off Windows. The
identity now comes from `[System.IO.DriveInfo]::GetDrives()` (which reads the
real mount table on Linux): the longest mount point prefixing the resolved path
on a separator boundary, with the old constructor kept as the fallback and
Windows root normalization unchanged; it still never throws. Separately,
`Assert-BackupCapacity` checked the backup and change demands independently and
never their sum, so two demands competing for ONE volume's free space both
passed; demands are now grouped by volume identity and the group total is checked.
The `.DESCRIPTION`s of both functions say so honestly. **SR-052 stays
`Implemented`** — the true Linux confirmation is still the Docker CI job, and no
Windows run can substitute for it; the Windows-side tests pin the summing and
exercise the same longest-prefix matcher. WP4's prune capacity rail
(`Get-PruneCapacityRefusal`, built on these two Common functions) was re-run and
is green.

**Minors.** (m1) TC-100's "fails the SET (status 1)" case now **observes** the
child process exit code (`Should -Be 1`) against a *genuine* shortfall — an
inflated `Length` in the backup manifest makes step 5.5's migration demand exceed
any volume, so no stub is involved. (m2) `-Action Verify` now resolves its roots
through `Resolve-BackupSetPaths -ReadOnly` **inside the try**: it creates no
directory, does not require `SourcePath` (a verify is about the STORE; the source
may be offline), and a missing backup root is the documented code 2. Its
`.OUTPUTS` drops the code-4 claim, which it never produced. (m3) Recorded, not
rewritten: TC-097's Expected now notes that the case forces
`CompressEnabled=true` (its mode axis is effectively two configurations) and that
**TC-092 is the SR-050 integration proof**; TC-092's row says so too. (m4) Sync's
Phase 2 identifies a superseded path by the `(Full, Rel)` pair recorded in Phase 1
instead of slicing `$rootPrefix` off the full path, and the orphan warning uses
`[IO.Path]::GetRelativePath`. (m5) The step-9.4 comment no longer overclaims
"byte-identical": step 6's migration may already have re-formed existing rows, so
what 9.4 guarantees is that none of THIS RUN's content is written and no staging
folder is orphaned — which is precisely why 5.5 proves the migration's room
first. The same correction is in LLR-052.

**Registry truth-up.** SR-049 (repair acts on the physical file; dedup
acceptance; `sharing` permutation), SR-050 (the raw retest now covers a
successful-but-non-matching expand; `genuine-7z-source` permutation), SR-051
(missing-7-Zip named in the acceptance; `failure` permutation), SR-052
(mount-table identity + per-volume summing in requirement and acceptance),
LLR-049..052 and TC-092/093/094/095/097/098/099/100/101 updated to describe the
behavior as it now is. **No status flips:** SR-049/SR-050/SR-051 stay `Verified`
— their extended TCs genuinely pass — and **SR-052 stays `Implemented`**, so
`check.ps1 -Gate G3` still reports exactly one status-finding, the disclosed one.

**Evidence (real, this session).**

- `Invoke-Pester -Path tests\Unit` → **316 Passed, 0 Failed** (baseline 310; +6).
- `pwsh scripts/check.ps1 -Tier Full` → `[PASS]` PSScriptAnalyzer, doc
  navigability, architecture-map freshness, Pester unit, perf budgets, and
  **Integration sweep: PASS 372 / FAIL 0 / SKIP 4**. The single `[FAIL]` is
  `Traceability (trace.py --strict)` — `SN=30 SR=52 LLR=51 TC=101 orphans=0
  integrity=0 status-findings=1 phase-deferred=4`, i.e. the disclosed SR-052
  status finding and nothing else.
- WSL (real Linux): `bats tests/bash` → **55/55** (baseline 54; +1) and
  `shellcheck -S warning bash/reconstruct.sh` clean.
- **Repro-first evidence.** Each fix was first confirmed RED against `HEAD~`
  (60ebe6d) in a throwaway `git worktree` carrying only the new tests:
  H2 → `Reconstruction INCOMPLETE: 1 file(s) ... (1 content-missing, 0 host):
  real.7z`; H1 → `Expected 2 ... but got 1` (one row healed, one abandoned);
  M2 summing → `no exception was thrown`; M1 → `Expected $false ... but got
  $true`; m2 → the backup root was created by a verify that had nothing to
  verify. The bash half of H2 was confirmed the same way (`git stash` of
  `bash/reconstruct.sh`): `WARN: [ContentMissing] 'real.7z'`, exit 1.

**Deviations from the work order.** None on substance. Two notes: (1) the
repaired-finding COUNT is per repaired *finding*, so a shared-DataPath pair
reports `Repaired = 2` while TC-094's four-shape fixture still reports 3 — the
existing assertion is unchanged; (2) m3 was taken as the recorded-limitation
option (registry truth-up only, no test rewrite), as the work order allowed.

### INDEPENDENT REVIEWER — WP4 re-verification — 2026-08-23
Verdict: **APPROVE** (upgraded from CHANGES-REQUESTED). All six findings
re-verified closed against a pristine export of `60ebe6d` by re-running the
original repros: the H1 byte-loss sweep is dead (Mirror user files named
`*.fbprune.tmp` survive typo'd/dry-run/real prunes and restore byte-exact,
while genuine residue is still swept); the sweep is inside the transaction
with failures classified 4 and refusals mutating nothing; the name-scoped
pre-rail residue completion touches only `Pruning_<same name>`; the G9
assertion now derives expectations from the snapshot's own manifest; all
three missing rails have cases and the capacity rail exists on UNC paths
(unmeasurable volume = reasoned, documented fail-open skip); the Temp lock is
atomic; `-Action Backup -WhatIf` refuses cleanly. Baselines exact on the
export: unit 310/310, integration 372/0/4, trace SN=30 SR=52 LLR=51 TC=101
0/0. Recorded nit (no action): `Get-StoreFingerprint` excludes
`*.fbprune.tmp` wholesale — a future test combining `-SuffixNamedUserFiles`
with `Assert-StoreUnchanged` would be blind to the H1 class. The reviewer's
APPROVE covers WP4 + its fixes only; WP5 has its own review track.

### DRIVER (UX/Docs + System Engineer hats) — WP6 docs batch — 2026-08-23
Verdict: APPROVE (driver hats) — awaiting batch ratification with WP1-WP5.
Executed the three Open-items rows (release checklist, interfaces.md
boilerplate, doc drift) plus the accumulated housekeeping (plan-doc links,
Open-items truth-up, Current State rewrite). **Docs-only — no `Modules/`,
`Reconstruct.ps1`, `bash/`, `tests/`, `FileBackup.ps1`, or `container/` file
was touched.**

What changed:
- **Release checklist.** Regenerated `docs/release-checklist.md` via
  `python scripts/gen_release_checklist.py` — SN=30, human-SR=4, manual-TC=7,
  IF=1, PB=0; confirmed the generator survived the UN→SN rename intact and
  already includes the container SNs (SN-024/026/028) without any patch.
  Found and fixed one real generator bug in passing: its hardcoded release-
  hygiene line named a nonexistent `scripts/check.py` (a Python-stack
  leftover) — now `pwsh scripts/check.ps1 -Gate G3 -Tier Release`, matching
  this repo's actual harness entry point. Deleted the stale, already-
  untracked `docs/releases/checklist-vNEXT-dryrun.md`. Narrowed `.gitignore`
  so `docs/release-checklist.md` is tracked going forward (it is the current,
  regenerate-at-will checklist, kept navigable in the repo); `docs/releases/`
  stays generated/gitignored for future `--version`-stamped, signed copies.
- **`docs/interfaces.md`.** Replaced the unmodified kit boilerplate with a
  thin, project-specific page: what IF-001 is, a pointer to
  `requirements/interfaces.csv` as the machine source of truth, and a prose
  rendering of the current contract (mounts, config schema v1, one-set-per-
  invocation, the shared backup/restore/prune/verify exit-code table,
  retention policy/mechanism split, no-direct-snapshot-deletion,
  `Experimental` stability + the joint WP1/WP2 exit condition to leave it).
- **Doc drift.** Left the kit-version stamp untouched (re-stamp only on a
  real kit resync, not this batch). Read the current `bash/reconstruct.sh`
  and verified homehub-integration.md §5 item 8's claim: the false-parity
  comment is still present, unchanged, now at line 564 (source drifted from
  the finding's original :380/:381 coordinates). Its underlying claim is no
  longer false, though — cross-read against the current `Reconstruct.ps1`
  (~521-527) shows finding A's fix made the PowerShell restorer refuse with
  `EXIT_PRECONDITION` on the identical gate bash already used (`any_comp` and
  no usable 7-Zip), before writing anything. Both restorers now refuse
  identically; neither degrades. Closed the item with a dated verification
  note in place, without rewriting the original finding's history.
- **Plan-doc links.** `docs/plans/wp1-restore-trust-plan.md`,
  `wp2-config-contract-plan.md`, and `wp5-storage-trust-plan.md` were already
  linked (from Open-items or their own WP audit entries); `wp3-container-
  release-plan.md` and `wp4-retention-plan.md` were referenced only inside
  code spans (not real Markdown links, so `check_docs.py` still orphaned
  them) — converted both to real links from their WP3/WP4 audit-entry
  headers.
- **Open-items truth-up.** WP1/WP2/WP4/WP5 rows now read their actual review
  verdicts and landed-fix dates instead of a bare "awaiting independent
  review + batch ratification" (WP3 stays as-is — it genuinely has no CI
  evidence yet). Added a row for the WP4 reviewer's accepted
  `Get-StoreFingerprint`/`*.fbprune.tmp` nit. Confirmed and left `-RepairFrom
  Pruned` (Deferred → WP6-or-later), the dangling-DataPath defect, the
  `Get-BackupSnapshot`/snapshot-inventory-cost perf row, and the manifest-
  row-order row all present with a clear State. Per the work order: the
  dangling-DataPath row's State stays **Open**, its disposition now reads
  "awaiting human prioritization in the batch ratification" verbatim. The
  prune form-mismatch rail row is relabeled **WP6-or-later** and its
  disposition now says explicitly that relaxing a Verified prune rail is a
  code change and out of this docs-only batch's surface.
- **Current State header.** Rewritten: the WP1-WP6 scoreboard (WP1/WP2/WP4
  implemented + independently reviewed with accepted fixes landed; WP5
  implemented + fixes landed with re-review in flight; WP3 implemented,
  awaiting its own CI evidence on the first push of `resync_v2`; WP6 this
  batch, done); the CI-gated flip list (SR-034/SR-044 → Verified, ratchet
  → `core,bash-v1,container-v1`, SR-048/SR-052 → Verified once TC-088/101/102
  leave `Draft`); and the next human action (batch ratification, then the
  push).

**A concurrent, unrelated in-flight change was observed and deliberately left
alone.** `Modules/FileBackup.Engine.psm1` carries an uncommitted modification
to `Get-StorageFormFinding`'s `FlagOverArchive` exemption (payload-hash-keyed
instead of extension-keyed, citing a "WP5 re-review residual") that this
driver did not make and did not touch — consistent with the work order's note
that a read-only reviewer may be re-verifying WP5 concurrently. It is excluded
from every commit in this entry; whoever owns it should commit or discard it
separately.

Evidence (real output, local, this session):
- `python scripts/check_docs.py --root . --ignore 'docs/test/report.md'
  --ignore 'docs/releases/*'` → `check_docs: OK - 19 doc(s), 69 intra-repo
  link(s), 0 broken.` (0 orphans, 0 broken — was 4 orphan warnings before
  this batch: wp3-plan, wp4-plan, the newly-tracked release-checklist, and
  the gitignored report.md, the last of which stays excluded by `--ignore`
  and is expected.)
- `pwsh scripts/check.ps1 -Tier Smoke` (gate G3, from `docs/gate`): lint
  PASS; **Traceability FAILED** — `SN=30 SR=52 LLR=51 TC=101 orphans=0
  integrity=0 status-findings=1 phase-deferred=4`, the one pre-existing,
  disclosed SR-052 CI-gated finding from the WP5 baseline (Docker
  unavailable on this host; not a regression from this batch — no registry
  or code file changed here); doc navigability PASS (0 broken); generated-
  docs freshness PASS; Pester unit **316/316** PASS; performance budgets
  PASS (no budgets registered). `check.ps1`'s own summary: `FAILED:
  Traceability (trace.py --strict)` — the single known finding, unchanged
  by this batch.

Findings: none new. The generator bug (nonexistent `scripts/check.py`
reference) above is the only thing found broken.

### DRIVER (Data-integrity hat) — WP5 re-review residual fix (payload-keyed exemption) — 2026-08-23
Landed as `62fc702` (merged verbatim from the fix agent's audit note; the
note file docs/plans/wp5-residual-fix-note.md is removed in this commit):

# WP5 re-review residual (HIGH): the already-compressed exemption is keyed on the payload

*Audit note for the driver to merge into docs/status.md. Data-integrity hat,
branch `resync_v2`, 2026-08-23.*

## The defect

`Get-StorageFormFinding` granted the "already-compressed source file" exemption
only when the row's `RelativePath` ended in `.7z`, while `Get-StoredFileForm`
judges a stored file by its 7z magic bytes. The two never agreed for a source
file whose *content* is a 7z archive under any other name — `archive.7z.bak`,
a `.pack` file, an installer payload.

Consequences on an **untampered, correct** store:

1. Verify reported `FlagOverArchive` for that row and exited 1 across IF-001 —
   a false alarm on a store with nothing wrong with it.
2. `-RepairStorage` then took the bytes as ground truth and set
   `Compressed=Yes` (and renamed the data file to `*.7z`), after which the next
   restore **expanded the user's own archive** and wrote the inner payload under
   the original filename, exiting 0. Silent corruption of a previously correct
   store — the worst shape available in this product.
3. `-Deep` mislabelled the same case: it expanded the file and compared the
   inner file against the row, producing `PayloadMismatch`.

## The fix

The exemption is now keyed on the **payload**, not on the name. When the
observed form is `Archive` while the row says `Compressed=No`, the file's OWN
bytes are hashed against the row's `(xxH2Hash, Length)`:

- **match** → this is raw storage of archive-shaped content, which is correct
  (SR-004 declines to re-compress an already-compressed source). No finding,
  and no `NameLies` either.
- **mismatch** → a genuine `FlagOverArchive` (the classic legacy shape, where
  the *payload* and not the file reproduces the row). Found and repaired as
  before.

A `.7z` RelativePath is kept purely as a fast path. `-Deep` consults the same
answer, so it never expands a file whose own bytes already reproduce the row.
`Repair-BackupStorageForm` applies the identical payload-keyed rule to the
per-row `Compressed` rewrite inside its grouped path — it reads the bytes'
identity **before** the rename moves them — so a row exempted by payload follows
its file through a rename but keeps its own `Compressed`.

**Cost:** the confirming hash runs only for a file whose bytes are an archive
while its row says `No` — rare — so the default (non-Deep) scan is still a
six-byte read per row. Stated in the function help.

## Evidence

- Repro-first: with the engine change stashed, the new fixtures are RED —
  4 failures, all `FlagOverArchive` on `archive.7z.bak` in an untampered store
  (Mirror and HashAddressed; the two Compress modes are green because the
  engine compresses a `.bak` source anyway). Green with the fix: 82/82 in
  `tests/Unit/StorageForm.Tests.ps1`.
- `Invoke-Pester tests\Unit`: **321 passed, 0 failed** (baseline 316; +5).
- `python scripts/trace.py --strict`: `SN=30 SR=52 LLR=51 TC=101 orphans=0
  integrity=0`.
- `pwsh scripts/check.ps1 -Tier Smoke -Gate G1`: **All steps passed** (lint,
  traceability, doc navigability, architecture-map freshness, Pester unit).
  At the default gate G3 the run fails on exactly one step, Traceability, with
  `status-findings=1` — the pre-existing SR-052 / WP3-ratchet item that
  `scripts/check.ps1` documents at line 119. Verified identical on stashed
  HEAD (`baseline exit=1`, same counts), so it is untouched by this change.

## Test and registry changes

- **TC-093** fixture repaired: `already.7z` held the literal string
  `pretend-archive-source`, which `Get-StoredFileForm` classifies as `Raw` — so
  the clean-store assertion never reached the exemption and passed vacuously.
  Both it and the new `archive.7z.bak` now hold REAL 7z bytes produced by
  `Compress-FileWithSevenZip`.
- New TC-093 cases: (a) an untampered store with a 7z-magic source under a
  non-`.7z` name reports zero findings in all four modes with and without
  `-Deep`, exits 0, is left byte-identical by repair, and restores byte-exact
  before and after; (b) a genuine `FlagOverArchive` is still found and repaired.
- `TC-094`'s Parameters cell contained an unquoted comma
  (`sharing=set{unshared,shared-datapath}`), so the row parsed as 10 fields and
  every column after Parameters was off by one. Re-quoted.
- Registry text updated: `LLR-049` Detail, `TC-093` / `TC-094` Expected.

No restorer or kit file changed → **no KitRevision bump, no bats change**.

## Residual

Full tier not run for this change (narrow, engine-local, Smoke green); the
driver should run it once WP6's docs work merges.

---

### DRIVER (Software + Test Engineer, Data-integrity hat) — WP5 residual #2: empty JSON documents — 2026-08-23

**How it was found.** Podman 5.5 turns out to be installed on the driver's host
(the earlier "Docker unavailable" notes were literally true but incomplete), so
the container suite ran locally for the first time:
`scripts/Invoke-Container.ps1 -Action BuildAndTest -Runtime Podman`. The build
and the core smoke (compressed backup, restore kit, byte-exact restore,
snapshot, both restores) passed; the appended TC-102 storage-form check failed
on the **clean** store — the exact case the Docker CI job would have hit first.

**The defect (engine, two emission sites).** Piping ZERO objects into
`ConvertTo-Json` emits nothing at all — the cmdlet never runs — so
`-AsArray`'s promised `[]` was never printed. Both one-shot JSON documents had
the shape: the SR-049 findings document (`FileBackup.ps1`, `Invoke-VerifyAction`)
and the IF-001/SR-047 snapshots inventory (`Invoke-RetentionAction`). A clean
store's verify and an empty store's inventory printed NO document while every
exit code stayed correct — precisely the states HomeHub will see most. Fixed by
passing `-InputObject` (an empty array serializes to `[]`; note
`-InputObject @() -AsArray` double-wraps to `[[]]`, so `-AsArray` is dropped —
the argument is already the array).

**A second, harness-side defect the fix exposed.** TC-102's extraction in
`scripts/Invoke-Container.ps1` used a greedy `(?s)\[.*\]` over the container's
mixed stdout, which ran from the document into the `[INFO]` tag of a later log
line and handed `ConvertFrom-Json` trailing garbage. Replaced with line-based
extraction (the document opens with a line that IS `[` and closes with a line
that IS `]`, or is the single line `[]`) — the same convention the Pester
snapshots-JSON test already used.

**Tests (new pins, both at the process boundary where IF-001 consumes the
output).** StorageForm.Tests.ps1: 'prints the findings document as parseable
JSON, the literal [] when clean (SR-049)' — malformed store parses to a
non-empty array carrying `Class`; clean store prints the literal `[]`.
Coverage.Tests.ps1: 'prints the literal empty JSON document for a store with no
snapshots (-Action Snapshots)'. Registry: TC-093 and TC-088 Expected updated;
no id re-minted, no status flips (TC-102 stays `Draft` — the CI run remains the
promotion criterion; the local Podman pass is corroborating evidence only).

**Evidence (real, this host, 2026-08-23).**

- `Invoke-Pester tests/Unit/StorageForm.Tests.ps1 tests/Unit/Coverage.Tests.ps1`
  → **234 Passed / 0 Failed / 0 Skipped** in 279.55s (232 before; +2 pins).
- `python scripts/trace.py --strict --phase core,bash-v1` →
  `SN=30 SR=52 LLR=51 TC=101 orphans=0 integrity=0`, exit 0.
- `Invoke-ScriptAnalyzer scripts/Invoke-Container.ps1` (repo settings) → clean.
- `Invoke-Container.ps1 -Action BuildAndTest -Runtime Podman` after the fix →
  **exit 0**: "Container storage-form check passed (TC-102): clean verify exits
  0 and mutates nothing, a malformed row exits 1, repair makes it clean." and
  "Container smoke test passed…". Image 372 MB; export refreshed to
  `.artifacts/filebackup-dev-wp5fix.tar` (354.5 MiB), the pre-fix tar deleted.
- `gen_release_checklist.py` re-run → byte-identical (no drift).

**Scope note.** The restore kit is untouched (revision stays 3 — neither
restorer changed); no SR/LLR text changed; the `--phase` ratchet stays at
`core,bash-v1`. Rolled into WP5's batch-ratification package.

---

### DRIVER (Software + Test Engineer, Data-integrity hat) — Adversarial review round & hardening batch — 2026-08-23

**What ran.** At the human's direction, two independent fresh-context reviews
of the whole repository: a medium-effort general review and an adversarial
data-integrity review (crash windows, dedup refcounting, restore edge stores,
container boundary), both bound by the human's triage rule — *realistic
operational scenarios only; malicious-tampering-only scenarios out of scope by
design*. The adversarial reviewer validated claims with throwaway repro scripts
(scratchpad only); four findings were REPRODUCED, the rest traced to specific
code paths. 19 findings total; 12 fixed same-day, 5 recorded as Open items
(R5-widening, R6, R7, R10, F8), 1 dismissed as malicious-only (R11), 1 already
fixed earlier the same day (R#8's parse bug, WP5 residual #2).

**Fixed — engine (`FileBackup.Engine.psm1`, `FileBackup.ps1`).**

- **F2 (HIGH, reproduced): the backup pipeline never consulted the witness it
  makes everyone else check.** A torn (crash-truncated) root manifest was read
  unchecked, then step 12 re-stamped a FRESH witness over state derived from
  the truncated index — laundering the damage; with a source deletion in the
  window, content vanished with exit 0 and no snapshot. Now a
  Mismatch/Malformed witness refuses the set BEFORE staging or mutation, and
  the entry point maps the distinct ErrorId onto **exit 3** (IF-001's table
  applies to backup). Absent stays legal — a pre-SR-038 store still backs up.
- **R3: staging-lock take was look-then-create.** `Test-Path` + `New-Item
  -Force` let two overlapping scheduled runs both pass; the create (without
  `-Force`) is now itself the lock, the same discipline `Remove-BackupSnapshot`
  already had.
- **F1 (HIGH, reproduced) / R4: the stale-Temp story was destructive.**
  README's remediation ("remove the leftover Temp and re-run") permanently
  destroyed the only physical copy of snapshot-demanded bytes after a
  mid-window crash (reproduced: snapshot restore exit 0 before, exit 1
  `ContentMissing` forever after, with the intervening backup reporting 0).
  Guard message + README now prescribe the non-destructive recovery
  (move-aside → re-run → verify → discard-or-reintroduce, never delete). And a
  step-5/step-6 abort (e.g. a source file locked by AV — routine) now removes
  the still-empty Temp instead of wedging every later run on the SR-017 guard.
- **F7: `FileBackupState.json` torn-write wedge.** Written in place; a torn
  write threw on every later run, and deleting the file walked into the SR-035
  refusal with no documented way out. Now published by write-then-rename like
  the witness.
- **R2: Mirror-mode root infrastructure-name collision.** With an external
  `SourceStatePath` (the container default), a source file legitimately named
  `MANIFEST.csv` at the source root was copied to the backup root and then
  OVERWRITTEN by the real index in step 12 — the manifest row pointed at index
  bytes; default verify called it clean. Prune and repair already refused this
  collision; the copy path now refuses it too (set fails, store intact).
- **F3 (HIGH for container-v1, reproduced at function level): case-insensitive
  hashtables silently drop case-differing files on Linux.** Every
  RelativePath-keyed map was a literal `@{}` (always case-insensitive):
  `Readme.txt`/`readme.txt` — two ordinary distinct Linux files — merged to one
  row through diff, backup map, source cache, and the PS restorer dictionary
  (`Update-SourceManifest` could even reuse the WRONG file's cached hash on a
  length+mtime coincidence). New `New-RelativePathMap` in Common: `@{}` on
  Windows (a case-only rename must NOT be a new file there), Ordinal elsewhere.
  bash was already case-sensitive.

**Fixed — restorers (kit revision 3 → 4;** `Reconstruct.ps1`,
`bash/reconstruct.sh`**).**

- **F4 (both reviewers; reproduced): stale `RECONSTRUCT.paths.json` hijacked
  the PS restorer.** The sidecar's recorded absolute roots were adopted with no
  existence check: a copied/moved store (the flagship self-contained-kit
  scenario) failed against the dead path — or, same-machine, **silently
  restored from the still-live ORIGINAL with exit 0** (and the SR-009
  containment check evaluated against the stale roots). Both restorers now
  honor the sidecar only while the origin still lives INSIDE the recorded
  roots; a copied/moved store auto-detects. (Stronger than bash's previous
  resolvability-only guard, which the same-machine hijack passed.)
- **F5: Optimize's delete-before-blank crash window read as data loss.** A run
  killed between `Optimize-ChangeFolders`' duplicate deletion and its manifest
  rewrite left rows naming deleted files; both restorers treated the non-blank
  `DataPath` as authoritative and reported `MissingDataFile` ("your bytes are
  gone") though the keeper sat in the pool — at exactly the moment an operator
  reaches for the kit. A non-blank `DataPath` is now a locator HINT: on a miss,
  both restorers fall back to the (hash,length) pool recovery blank rows
  already use.
- **F6: `\` separators on a non-Windows restore host.** `Reconstruct.ps1` never
  mapped them, so a Windows-made HashAddressed backup restored with pwsh on
  Linux wrote each nested row as a root-level file literally named
  `sub\file.txt` — **exit 0, structurally wrong tree**. Now mapped exactly as
  bash's `to_posix` does.

**Fixed — docs.** README's prune-unblock recipe claimed `-Action Verify`
"repairs the findings that are unambiguous" — verification mutates nothing
without `-RepairStorage`; sentence fixed (R9). interfaces.md now documents the
JSON framing (line-based extraction from mixed stdout) that HomeHub's wrapper
must implement (R8).

**Evidence (real, this host, 2026-08-23).**

- New pins: Pester Describe *'Backup pipeline crash-window hardening
  (2026-08-23 review round)'* — 6 tests: witness-mismatch backup refuses with
  **exit 3** and mutates nothing; witness-Absent legacy store still backs up;
  locked source file fails the set WITHOUT stranding Temp and the next run
  exits 0; Mirror infra-name collision refused with the store intact; a COPIED
  backup folder restores from the copy (containment warning asserted); a row
  whose named data file is renamed away hash-recovers from the pool. Plus
  *'New-RelativePathMap keys compare like the local filesystem (SR-034)'* in
  Common.Tests. All pass.
- Full unit suite + lint: see the run pasted in the Current State bullet
  (recorded after this entry was drafted; the run includes these 7 new tests).
- bash: `shellcheck -S warning bash/reconstruct.sh` clean; **bats 55/55, 0
  failures** on real Linux (WSL Fedora) after the reconstruct.sh changes.
- Registry: TC-024, TC-033, TC-058, TC-060, TC-066 Expected extended; the
  dangling-DataPath Open row widened with R5's corroboration; 5 new Open-item
  rows + 1 fixed-batch row. No SR/LLR status flips (the new behaviors verify
  under their existing SRs; the Linux halves of F3/F6 ride the container job).
- Known cosmetic drift, accepted: LLR Detail line-number references into
  `Reconstruct.ps1` (e.g. LLR-050's `:225-238`) shifted by this batch; symbol
  references remain correct. Flagged for the ratification rather than
  hand-renumbering mid-batch.

**Kit-revision exposure (same story as revision 2→3).** Snapshots written
before today keep their revision-3 kits, which carry F4/F5/F6 until refreshed —
`-Action Verify -RefreshKits` upgrades every snapshot's kit in place; README's
revision note covers the exposure.

**Deviations / not fixed (with the human's triage rule applied).** R5
blank-DataPath healing needs its own SR (dedup-group selection is not a
rush-fix surface) — widened Open row awaits prioritization; R6 quoting and R10
no-7-Zip-raw-skip batch with the next kit revision; R7 newline rows are
bash-v2; F8 kit-less snapshot window recorded with a candidate cheap fix; R11
(sed JSON nit) dismissed as malicious-only per the rule.

---

### INDEPENDENT REVIEWER — WP5 fix-set re-verification + review of `11b2c46`/`83cc5f1` — 2026-08-23

**Why this entry exists.** The earlier WP5 re-review (in flight last session)
delivered its one HIGH residual — the payload-keyed exemption, fixed in
`62fc702` — but its closing verdict was never merged into this file before its
session ended, violating the durable-memory rule. This fresh read-only
re-verification against a **pristine clone of `83cc5f1`** (repo working tree
untouched) replaces it and also gives the two same-day unreviewed commits
their independent pass.

**Part A — WP5 fix set: APPROVE** (one doc minor, folded into the fixes
below). Independent probes with the reviewer's own fixtures, 25/25 PASS:
H1 dedup-pair repair heals BOTH rows sharing one physical file, re-verifies
clean, restores byte-exact via the standalone kit; the payload-keyed exemption
reports ZERO findings for real 7z bytes under a non-`.7z` name (Mirror and
HashAddressed, ±`-Deep`), repair mutates nothing, restores byte-exact before
and after, while a genuine `FlagOverArchive` is still found and repaired; the
`11b2c46` empty-document fix prints the literal `[]` for both `verify` and
`snapshots` at the process boundary. Pinned TC-094 Describe: 8/8.

**Part B — `11b2c46`: APPROVE.** `-InputObject` at both emission sites is
correct (dropping `-AsArray` avoids the `[[]]` double-wrap; a single finding
still serializes as a one-element array); the harness's line-based extraction
matches the framing now documented in interfaces.md.

**Part B — `83cc5f1`: CHANGES-REQUESTED.** Eleven of the twelve fixes check
out under scrutiny (witness gate truly pre-mutation with real exit 3 observed;
sidecar containment breaks no in-place or snapshot restore and bash's case
pattern is correctly quoted; the hash fallback keys on the row's own
`(xxH2Hash, Length)` — the store's dedup identity, identical to blank-row
recovery; the staging lock matches the prune precedent; the step-5/6 Temp
cleanup only ever removes a Temp that is empty by construction). Required:

1. **R1 (same severity class as F3 itself): `Save-SupersededData`'s
   `$backupByRel` was still a literal case-insensitive map.** On Linux, a
   case-differing pair — kept correctly distinct by the FIXED diff and backup
   maps — collapses here; the lookup returns the twin row, its content
   "survives", staging is skipped, and the copy step overwrites the superseded
   bytes: the snapshot row is permanently ContentMissing. Reproduced at
   function level on the pristine clone.
2. **R2 (minor): `Get-BackupCapacityDemand`'s `$byPath`** — same one-line
   conversion; consequence is capacity under-estimation only.
3. **R3 (docs): the batch's claim "README's revision note covers the
   exposure" was false** — README and AGENTS.md §3 both stopped at revision 3;
   and AGENTS.md still described the exemption as RelativePath-`.7z`-keyed,
   stale since `62fc702` (the Part A minor).

Reviewer's evidence (pristine clone): unit **330/330** (5:04), TC-094 Describe
8/8, hardening Describe 6/6, WSL `shellcheck` clean + **bats 55/55**, trace
0 orphans / 0 integrity, lint 0 findings. Two notes recorded, no action
required: a store that loses both witness integrity AND `FileBackupState.json`
exits 1 (SR-035 fires before the gate), not 3 — still a pre-mutation refusal;
and `New-Item` narrows rather than provably eliminates the lock race — fine
for scheduled-run overlap.

---

### DRIVER (Data-integrity hat) — Landing the `83cc5f1` review's required changes — 2026-08-23

All three required changes landed, exactly as specified:

- **R1:** `Save-SupersededData`'s `$backupByRel` → `New-RelativePathMap`, with
  a why-comment naming the failure. **R2:** `Get-BackupCapacityDemand`'s
  `$byPath` likewise. New CLASS pin in the hardening Describe: a literal
  `@{}` whose fill is keyed by `.RelativePath` anywhere in the four code files
  fails the suite — the exact shape the review caught can't regress silently.
- **R3:** AGENTS.md §3 exemption sentence rewritten payload-keyed (the Part A
  minor); AGENTS.md §3 and README's kit-revision notes extended to
  **revision 4** with the F4/F5/F6 exposure spelled out.
- **Noted for a container-v1 sweep, not converted here (outside the review's
  required scope):** the DataPath-keyed membership maps
  (`$referencedPaths`/`$ownReferenced`/`$existingPaths`) are also literal
  case-insensitive hashtables; their failure modes are orphan-warning
  suppression / missing-file classification, not byte loss. Worth one look
  when container-v1 verifies.

Evidence: see the run pasted in the Current State bullet (full unit suite
including the new class pin, lint, trace, container re-run — all after these
edits).

---

### DRIVER (Software + Test Engineer) — WP8: portable names + raw-candidate recovery — 2026-08-23

Plan: [plans/wp8-portable-names-plan.md](plans/wp8-portable-names-plan.md).
Both scoped items landed.

**Portable-name guard (SR-055, the human's R6/R7 ruling).**
`Test-PortableRelativePath` classifies per component (Windows-forbidden
characters incl. control/newline, trailing dot/space, backslash-in-name on
non-Windows). The skip happens INSIDE `Update-SourceManifest`'s scan, before
any open/hash attempt — a trailing-dot name Windows cannot even open would
otherwise abort the whole set on a read error instead of being named as the
problem. Step 5.1 logs one ERROR per skip and fails the set; step 8 filters
skipped names out of `RemovedFromSource`, so a previously stored row under a
bad name is FROZEN, never evicted. This retires R6 (7-Zip quote mis-split) and
R7 (bash newline rows) at the source for every newly written store.

**Raw-candidate recovery without 7-Zip (R10; kit revision 4 → 5).** Both
locators now test a `.7z`-named candidate's OWN bytes even when 7-Zip is
absent (raw needs none); only a candidate whose raw bytes do not match still
records DependencyMissing. A restore requiring no actual decompression no
longer exits 4 demanding 7-Zip. Two bats fixtures whose no-7z candidate
happened to BE the row's raw bytes renamed `.7z` — exactly the shape that now
recovers — were updated to genuinely non-matching bytes, and a new bats case
pins the recovery; the PS process-level exit-4 pin needed the same fixture
update (its candidate was also the row's bytes renamed), while the PS
function-level DependencyMissing pin already used non-matching bytes and
stands unchanged.

**Registries.** SN-032 minted (deferred from the WP7 commit so it never sat
orphaned); SR-055 `Verified`, LLR-055, TC-106 `Pass`; TC-107 `Pass` under the
SR-050 family for the revision-5 behavior. `trace.py --strict` →
`SN=32 SR=55 LLR=54 TC=106, 0 orphans / 0 integrity`. AGENTS.md §3 and
README's kit-revision notes extended to revision 5.

**Evidence (real, this host, 2026-08-23).** WP8 Describe 3/3 (classification
matrix; trailing-dot end-to-end via `\\?\` — exit 1, one Skipping ERROR, rest
backed up, prior row frozen with its data file intact; raw-`.7z` recovery with
a bogus `-SevenZipPath`). WSL: `shellcheck` clean, **bats 56/56** (55 + the
new revision-5 pin). Full-suite + container runs recorded in the wrap-up
below.

---

### HUMAN — Batch ratification — 2026-08-23

The human reviewed the ratification worksheet (artifact `d48d6e78`, built from
this file's Current State and Open items) and ratified the batch: **WP1, WP2,
WP4, WP6; WP5 including both residuals, on the recorded re-review APPROVE;
WP3's implementation pending its own CI evidence; and the adversarial-review
hardening batch `83cc5f1` together with its review-fix landing `31a55f2`, on
the recorded CHANGES-REQUESTED→landed trail.** ("I've reviewed and ratified",
2026-08-23.)

Consequences: the push of `resync_v2` is unblocked (first run of the container
and bash-interop CI jobs); on green CI the pre-authorized registry flips
execute (SR-034/044/048/052 → Verified, TC-088/101(TC-101 Linux half)/102 →
Pass, ratchet → `core,bash-v1,container-v1`), clearing the one standing G3
status finding.

**Deliberately not decided here:** the dangling/blank-DataPath prioritization
and the parked-findings acceptance (R6/R7/R10/F8 + the form-mismatch rail).
The human asked for a realism verification of those before deciding; two
read-only investigations (blank-DataPath reachability end-to-end, and the
prune form-mismatch rail's real-world trigger) are in flight and their
findings will be recorded here when they land.

---

### INVESTIGATIONS (read-only, scratchpad repros) — realism verification of the two undecided Open items — 2026-08-23

Both run at the human's request before deciding the dispositions; both
escalate their item. Full facts folded into the Open-items rows; summary:

### HUMAN — Open-item rulings + WP7/WP8 minted — 2026-08-23

After the investigations below, the human ruled ("Yes, please build out WP7
and WP8 … I will push when those are completed"):

- **WP7 minted (storage self-healing + retention unblock):** the verified-HIGH
  blank-DataPath item (never adopt a blank DataPath; heal from source on
  blanking; wire `Test-PoolResolves` into `-Action Verify`; README
  backup-root warning) plus the form-mismatch prune-rail relaxation, as one
  WP — shared `Test-PoolResolves`/verify surface.
- **WP8 minted (portable names + raw-candidate recovery):** R6/R7 are
  dispositioned by ruling — **a source filename invalid on either platform is
  skipped LOUDLY at backup time** (reported per file, set fails); no
  special-case handling of quote/newline names. Plus R10's no-7-Zip
  raw-candidate test (a kit-revision bump, batched here).
- **F8** understood and stays parked (sub-second window, `-RefreshKits`
  recovers). **Snapshot inventory cost** accepted: real cadence is one backup
  per day, so O(n²) is a non-issue at practical scale.
- **The push waits for WP7+WP8** — "No reason to push especially with WP7
  still unfixed."

---

### DRIVER (Software + Test Engineer, Data-integrity hat) — WP7: storage self-healing + retention unblock — 2026-08-23

Plan: [plans/wp7-self-healing-plan.md](plans/wp7-self-healing-plan.md). All
four scoped changes landed; every acceptance ran green.

**Healing (SR-053).** `Compare-SourceToBackup` gains a third NewOrChanged arm:
metadata-equal but blank `DataPath` — a blanked row re-enters the diff, so the
run after a data-file loss re-copies from the still-matching source (or
re-points at a surviving dedup copy). `Invoke-BackupFileGroup`'s dedup
candidate filter now requires a non-blank `DataPath`, so a new same-content
file can never adopt a row that points nowhere (the R5 spread). The heal run
mints its snapshot like any other manifest-changing run.

**Verify sees the pool (SR-054).** `Invoke-VerifyAction` appends
`Test-PoolResolves`' `broken-pool` problems to the findings document as
`Class=PoolUnresolvable` (six-field shape preserved; findings drive exit 1) —
closing the investigation's decisive blind spot: a store with permanently
unrestorable rows no longer verifies clean. Pool audit is always pool-wide;
`-RootOnly` scopes only the form audit. Report-only by design — bytes cannot
be conjured; the heal is the next backup run or restoring content into the
pool.

**Rail relaxation (SR-046 as amended).** `Test-PoolResolves`' blank-row form
check is now gated on the ROW'S OWN folder's kit revision (cached
`Get-BackupKitRevision`): revision ≥ 2 kits decide form from the located file
(SR-050), so the disagreement restores correctly and no longer blocks
retention — the compression-flip wedge (including the two-regime permanent
wedge and the phase-F upgrade trigger) is gone. A folder with a pre-revision-2
kit (or none) still refuses, and the refusal now names the kit revision and
the `-RefreshKits` remedy. Non-blank-DataPath form mismatches still refuse —
the restorers still trust `Compressed` for a file present at its named path.
Problem objects gain `Folder`/`RelativePath`/`DataPath` fields (additive).

**Latent defect found and fixed while landing the rail gate:**
`Get-BackupKitRevision` read the kit header with the LAZY
`[IO.File]::ReadLines` and returned from inside the loop — PowerShell does not
dispose the enumerator on an early return, so the open handle on a snapshot's
`RECONSTRUCT.ps1` lingered until garbage collection. Harmless for every
pre-WP7 caller (verify paths never rename afterwards), but the rail gate made
PRUNE a caller, and the leaked handle intermittently blocked the commit rename
with access-denied (4 flaky suite failures, reproduced with the refusal
message in hand). Fixed with the eager `ReadAllLines`; the flakiness is gone.

**Two pre-WP7 pins updated to the new semantics (not weakened):** TC-091's
"leaves every malformed row byte-identical" now exempts exactly the DANGLING
shape — the run heals it from source, which is SR-053's whole point — and
asserts the heal while still proving the three FORM-malformed rows stay
byte-identical; Engine.Tests' pure-diff "ignores unchanged" now models the
backup row with its DataPath column populated (as every real manifest row is)
and pins the blank-DataPath arm explicitly.

**Docs.** README: the backup-root "never tidy this folder" warning with the
AV/cloud-sync culprits and the new healing/verify behavior; the prune
Known-limitation box replaced by the kit-revision-gated behavior.

**Registries.** SN-031 minted; SR-053/SR-054 minted `Verified`; SR-046
Requirement/Acceptance/Permutations amended (kit-revision gate); LLR-053/054;
TC-103..105 `Pass`. `trace.py --strict` → `SN=31 SR=54 LLR=53 TC=104,
0 orphans / 0 integrity`; `--require-verified` still exactly the one
pre-existing SR-052 CI-gated finding.

**Evidence (real, this host, 2026-08-23).** New WP7 Describe — 5/5: pure-diff
blank-row pin; end-to-end heal + adoption ban (external deletion + new
same-content file → exit 0, both rows resolve, restore byte-exact); Verify
exits 1 with `PoolUnresolvable` in the JSON document when every copy of a
content is deleted; compression-flipped store **prunes with exit 0** and the
surviving snapshot restores byte-exact across the flip; the same store with
one kit regressed to revision 1 **refuses with exit 2** naming form-mismatch
and RefreshKits. Full-suite + lint run recorded in the WP7+WP8 wrap-up entry.
Existing TC-084 rail cases (non-blank mismatches) unchanged and green.

**Blank-DataPath (verdict: worth its own WP now; NOT parkable behind "verify
detects it").** Reproduced end-to-end on HEAD: delete one file inside the
backup root (dominant realistic class — AV quarantine, cloud-sync
dehydration, operator tidying; README never warns against it; the engine's
own deletion paths are closed on current code) → next run WARNs once and
exits 0, blanks the row, never re-copies although the diff proves the source
still holds the bytes → all later runs silent → **`-Action Verify`/-`Deep`
exit 0 "no disagreements" on the broken store** → restore exits 1
content-missing. R5 adoption confirmed live: a NEW same-content file adopts
the blank row with zero warnings and no bytes ever written. Kit-4 fallback
rescues only content that survives elsewhere in the pool — unique content is
lost. Cheap fix class verified viable: never adopt a blank DataPath
(simultaneously kills the spread and heals from source), re-copy on blanking
when the source matches, call `Test-PoolResolves` from Verify, README
warning.

**Prune form-mismatch rail (verdict: promote WP6-or-later → scheduled).**
Reproduced: after a `CompressEnabled` flip, prune refuses the whole store
(exit 2 form-mismatch) while the refused snapshot restores byte-exact with
its own revision-4 kit; `-RepairStorage` says unrepairable, `-RefreshKits`
doesn't clear it, the precondition doesn't exclude even the snapshot being
pruned. NEW beyond the row: a store with snapshots from both regimes is
**permanently wedged under either setting** (no unblock short of hand-editing
manifests, which breaks witnesses); and the WP5 phase-F extension merge is
itself a form flip for 8 types, so an existing compressed store that merely
upgrades walks into the wedge with no operator action. README's promise that
the flip is safe was true for restore and false for prune — a Known-
limitation caveat with the single-flip workaround is landed in README in
this commit (docs-only). Data safety never at risk; the refusal is
conservative.

