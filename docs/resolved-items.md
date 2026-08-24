# Resolved & historical items — archive

Moved out of [status.md](status.md) 2026-08-24 at the human's direction so the
live Open-items list holds only items still needing input. Every row below is
DONE, ratified, rejected, or otherwise closed; the full narrative for each
lives in status.md's audit log (entries are dated). Nothing here is live state.

## The WP1→WP8 era Current State bullets (as they stood 2026-08-24)

## Current State

- **BATCH RATIFICATION: human-RATIFIED 2026-08-23** (via the ratification
  worksheet, artifact `d48d6e78`; recorded in the audit entry below): WP1,
  WP2, WP4, WP6; WP5 with both residuals on the recorded re-review APPROVE;
  WP3's implementation pending its own CI evidence; the adversarial-review
  hardening batch (`83cc5f1`) together with its review-fix landing
  (`31a55f2`) on the recorded CHANGES-REQUESTED→landed trail. **The push of
  `resync_v2` is now unblocked.** The two items deferred from this
  ratification were realism-verified same day (investigation entry below) and
  the human then ruled: both became **WP7/WP8, now implemented** — the
  remaining Open rows (dangling-DataPath is largely closed by WP7's heal;
  reserved-names note, F8, R6/R7-retired-for-new-stores) are recorded below.
- **WP7 (storage self-healing + retention unblock) and WP8 (portable names +
  raw-candidate recovery, kit revision 5) are implemented, independently
  reviewed (WP7 CHANGES-REQUESTED → required changes landed; WP8
  APPROVE-WITH-MINORS → minors landed), and green across the full battery:
  unit 341/341, integration 372/0/4 (Subst, the CI command verbatim), bats
  56/56 + shellcheck clean, bash-interop 12/12 origins on Linux, and the
  container job replicated END-TO-END ON REAL DOCKER (Ubuntu WSL) including
  the Export/Load sequence.** The first real CI run (push of `83cc5f1`)
  failed 5 jobs; the post-mortem entry below diagnoses all five — one
  genuine container-harness bug (host-side witness stamp needing a DLL
  ubuntu-latest lacks) is fixed; after two more diagnosed-and-fixed CI rounds
  (post-mortem addenda below), **the fourth CI run (`08a1743`, run
  32673687758) came back GREEN on every job except the by-design Traceability
  failure — including the container job's FIRST green run, the promotion
  evidence.** The pre-authorized registry flips are now LANDED:
  SR-034/044/048/052 → Verified, TC-060/079/080/088/101/102 → Pass,
  LLR-044 → Implemented, ratchet re-armed to `core,bash-v1,container-v1` in
  `check.ps1` and CI. `trace.py --strict --require-verified` now reports
  **0 status-findings** (1 phase-deferred: SR-033, bash-v2 — by design).
  **Next human action: push the flip commit; expected result: a fully green
  wall. Then the gate is clear to advance G3 → G-Release,** and IF-001's
  exit condition (WP1+WP2 Verified) is long since met — the contract can move
  Experimental → Stable when HomeHub is ready.
- **Active gate:** G3 (retrofit truth-up **human-APPROVED 2026-08-22**; the
  whole WP1→WP8 queue has landed and is human-ratified through WP6 + the
  hardening batch, with WP7/WP8 review-closed. **Next human action: push
  `resync_v2`** (head `9d6a786`); on a green container CI job the
  pre-authorized registry flips land, Traceability clears on the following
  push, and the gate can advance to G-Release.)
- **Latest verified run (2026-08-23, post-WP7/WP8 review fixes — the "full
  battery" wrap-up entry below):** **Pester unit 341/341, integration
  372 PASS / 0 FAIL / 4 SKIP (Subst, the CI command verbatim), bats 56/56 +
  shellcheck clean (WSL), bash-interop 12/12 origins on Linux, container job
  end-to-end on REAL Docker (Ubuntu WSL) incl. Export/Load, lint clean,
  trace `SN=32 SR=55 LLR=54 TC=106, 0 orphans / 0 integrity`.**
  `check.ps1 -Gate G3` now reports **0 status-findings** — the container CI
  job's first green run (32673687758) supplied the promotion evidence and the
  registry flips landed; the long-standing SR-052 finding is CLEARED.
- **WP1 (restore trust & diagnostics) is implemented, independently reviewed
  (APPROVE-WITH-MINORS 2026-08-22) and the accepted findings are landed
  2026-08-23 — ratified 2026-08-23.** SR-038..041 Verified,
  TC-066..073 Pass. See the audit entries below.
- **WP2 (config contract) is implemented, independently reviewed
  (CHANGES-REQUESTED 2026-08-22 — a quoted `"false"` for `AllowEmptySource`
  coerced to `$true` and disarmed the delete-all refusal) and every accepted
  finding is landed 2026-08-23 — ratified 2026-08-23.** SR-042..043
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
  accepted finding is landed 2026-08-23 — ratified 2026-08-23.**
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
  ratified 2026-08-23.** Restore-kit
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


## The original Open-items table (all rows now closed or migrated)

## Open items (frontier)

Tracked open work, minted 2026-08-21 from the HomeHub cross-check
([homehub-integration.md](homehub-integration.md) §1/§3/§5) and prior review
carry-overs. Ids are the cross-check's finding letters until each is promoted
to an SR through the gate. **Dispositions human-approved 2026-08-21** ("Yes
that sounds good — proceed"); each row carries its agreed answer, and the
work-package order follows the table.

| Item | What | Disposition (human-approved 2026-08-21) | State |
|---|---|---|---|
| **E** | Restore can only verify rows its manifest still contains — a truncated manifest shrinks the job and still reports success. HomeHub's archive census does not port because of dedup. Partial mitigation shipped: missing-MANIFEST refusal (TC-063). | **WP1 (restore trust & diagnostics bundle).** Witness = a sidecar (e.g. `MANIFEST.csv.meta`) written atomically alongside the manifest carrying row count + xxHash128 of the manifest bytes, duplicated into each snapshot; both restorers verify it before restoring. Independent of the restore loop; portable to bash with tools already required; **subsumes the corrupt-manifest guard** (garbage manifest fails the digest). Adds an artifact to the SR-022 infrastructure allowlist — mind regression B6/TC-052. Needs its own SN/SR through G1; **blocks any "restore is trustworthy" claim.** | Implemented (WP1), independently reviewed (APPROVE-WITH-MINORS 2026-08-22), accepted findings landed 2026-08-23 — ratified 2026-08-23 |
| corrupt-manifest guard | Corrupt non-CSV MANIFEST.csv restores nothing yet exits 0 in `Reconstruct.ps1` (2026-07-03 reviewer MINOR; bash validates the header, exit 2). | **WP1**, implemented *inside* the witness change — a lone interim header check would burn a kit revision for something the witness replaces. | Implemented (WP1), independently reviewed (APPROVE-WITH-MINORS 2026-08-22), accepted findings landed 2026-08-23 — ratified 2026-08-23 |
| **D** + exit-code table | `Find-DataFileByHash` collapses 4 failure causes into one warning; IF-001 promises HomeHub a translatable exit status but `Reconstruct.ps1` throws one generic failure for every cause. | **WP1.** One documented exit-code table shared by both restorers — adopt bash's existing exit 2 as the baseline, don't invent a competing scheme. Prerequisite for IF-001 leaving `Experimental` (NagLight translation needs something to translate). | Implemented (WP1), independently reviewed (APPROVE-WITH-MINORS 2026-08-22), accepted findings landed 2026-08-23 — ratified 2026-08-23 |
| **J** | Backup-side move loops (`Move-RemovedFilesToStaging`, `Save-SupersededData`) abort on first failure instead of aggregating like restore's `$unrestored`. | **WP1** companion (same fail-loudly theme), or immediately after. Small. | Implemented (WP1), independently reviewed (APPROVE-WITH-MINORS 2026-08-22), accepted findings landed 2026-08-23 — ratified 2026-08-23 |
| config contract | IF-001's import half is under-specified: `FileBackup.ps1`'s JSON branch is a bare `ConvertFrom-Json` — no schema, no version field, no validation, no test; `container/FileBackup.example.json` is never executed by any test (TC-060 generates its own config). | **WP2.** Versioned JSON schema + validating loader that fails loudly (SR + LLR + TC executing the example file itself). JSON becomes the canonical documented contract; CLIXML stays the legacy native-Windows path. Top HomeHub-facing priority after E. Blocks IF-001 moving past `Experimental`. | Implemented (WP2), independently reviewed (CHANGES-REQUESTED 2026-08-22), accepted findings landed 2026-08-23 — ratified 2026-08-23 |
| multi-set mounts | How HomeHub maps N host directories onto container paths was unspecified. | **RESOLVED by ruling, WP2 records it:** **one BackupSet per container invocation**; HomeHub runs one service/invocation per directory (matches its per-service scheduling + NagLight model, keeps mounts trivial). Multi-set stays a native-Windows convenience. Recorded in IF-001. | Implemented (WP2), independently reviewed (CHANGES-REQUESTED 2026-08-22), accepted findings landed 2026-08-23 — ratified 2026-08-23 |
| container release-verify | SR-034/TC-060 are `Implemented`/`Draft`; CI runs **BuildAndTest only** — Export/Publish/Pull and a `docker load` roundtrip are never exercised; no local `check.ps1` tier runs the container step. | **WP3.** Extend the CI job: Export → `docker load` roundtrip; Publish/Pull against a throwaway `registry:2` container in-job. Then TC-060 → Pass, SR-034 → Verified, **re-arm the ratchet to `--phase core,bash-v1,container-v1`.** Blocks calling container-v1 released. | **Done — CI evidence run 32673687758 (2026-08-23); flips + ratchet landed** |
| container smoke depth | Smoke checks a six-artifact kit that omits `RECONSTRUCT.paths.json` and runs one single-set, no-snapshot, no-rerun backup. | **WP3**, with release-verify: add the sidecar to the kit check and a second incremental, snapshot-producing run restored in-container. | **Done — CI evidence run 32673687758 (2026-08-23)** |
| **I** | Snapshot retention is unbounded. | **Re-ruled — the pure "delegate to HomeHub" disposition was unsafe:** blank-DataPath rows recover bytes by hash from *other* snapshots' folders, so externally pruning a `Snapshot_*` folder can delete the only physical copy other snapshots still need. **Split: HomeHub owns retention *policy*; FileBackup owns the *mechanism*** — a `Prune-Snapshot` verb (WP4, own SR) that re-homes still-referenced bytes before deleting a folder. IF-001 now states: never delete snapshot folders directly. **Do before HomeHub builds any pruning.** | Implemented (WP4), independently reviewed (CHANGES-REQUESTED 2026-08-23), accepted findings landed 2026-08-23 — ratified 2026-08-23 |
| **C-form (new, WP4 §5.7)** | A blank-DataPath row whose `Compressed` disagrees with the .7z-ness of the file hash recovery locates restores **archive bytes under the original name**: both restorers branch on the ROW's `Compressed`, not on the form of the file they found. Reachable today after a compression-mode flip, because `Sync-BackupStorageLayout` migrates only the backup root and never the snapshots. | **WP5**, with finding C (same repair story). WP4 ships the **detector**: `Test-PoolResolves` reports `form-mismatch` and `Remove-BackupSnapshot` refuses (code 2) rather than pruning into it, so a store in this state is named instead of silently widened — and WP5 inherits a ready repro (TC-084's `form-mismatch` case). Note the deliberate exemption: a row whose own `RelativePath` ends in `.7z` (a legitimately stored already-compressed source file) is NOT a disagreement. | Implemented (WP5), independently reviewed (CHANGES-REQUESTED 2026-08-23), accepted findings landed 2026-08-23; re-review of the fixes in flight — ratified 2026-08-23 |
| **C-refcount (new, WP5 planning G10)** | `Sync-BackupStorageLayout` is not refcount-aware: dedup makes rows share one `DataPath` (`Invoke-BackupFileGroup`), the migration decision is per-row (`Engine.psm1` `$needsTransform`), and Phase 2 deletes every superseded path unconditionally — so a config change that flips only ONE of two content-sharing rows deletes the file the other still references (`MissingDataFile` on the next restore, exit 1). **Live data-loss defect on Verified code**, reachable today (compression flip + two same-content rows with different extensions); the ext-list merge would trigger it at scale. Contrast `Move-RemovedFilesToStaging`, which IS refcount-aware (B9). | **WP5 as SR-051** ([plans/wp5-storage-trust-plan.md](plans/wp5-storage-trust-plan.md)), sequenced BEFORE the ext-list merge. Surfaced immediately per the plan's Q7 so it stays visible even if WP5 slips. | Implemented (WP5), independently reviewed (CHANGES-REQUESTED 2026-08-23), accepted findings landed 2026-08-23; re-review of the fixes in flight — ratified 2026-08-23 |
| **C** | `Sync-BackupStorageLayout` trusts manifest `Compressed`/`StoredAsHashSize` metadata, so a malformed row can validate itself. | **WP5.** With B fixed, new malformed rows can't be created — C matters for pre-fix backups and for migrations the ext-list merge triggers. Repro test first (double-check §5.3); repair via an opt-in `-VerifyStorage` mode, **not** a physical verify inside every migration (would fight SR-024 idempotence/perf). | Implemented (WP5), independently reviewed (CHANGES-REQUESTED 2026-08-23), accepted findings landed 2026-08-23; re-review of the fixes in flight — ratified 2026-08-23 |
| ext-list merge | Merge bash's broader already-compressed extension list (`jar tgz zst gif webm ogg sav pack`) into `Common.psm1`; keep per-file granularity. | **WP5, sequenced AFTER C's repro test** — not trivial: the merge flips existing `.7z` rows to "wrong" under `Sync-BackupStorageLayout`'s config comparison and exercises the untested migration path at scale. Cover the triggered migration in C's test. | Implemented (WP5), independently reviewed (CHANGES-REQUESTED 2026-08-23), accepted findings landed 2026-08-23; re-review of the fixes in flight — ratified 2026-08-23 |
| backup-side capacity | Does the backup side have the capacity preflight the restore side gained (SR-023 is restore-only)? | **WP5.** Verify first, then a small SR mirroring SR-023. Importance rises with the container (target is a HomeHub-controlled bind mount). | Implemented (WP5), independently reviewed (CHANGES-REQUESTED 2026-08-23), accepted findings landed 2026-08-23; re-review APPROVE recorded — SR-052 stays `Implemented` until TC-101's Linux half runs in the Docker CI job; ratified 2026-08-23 |
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
| **2026-08-23 review round (fixed batch)** | Two independent fresh-context reviews (whole-repo medium + adversarial data-integrity, human-directed triage: realistic operational scenarios only, malicious-only excluded) surfaced 19 findings, several REPRODUCED by throwaway scripts. Twelve landed same-day: backup-side manifest-witness gate refusing with exit 3 before any mutation (F2, reproduced silent-laundering of a torn index); atomic staging-lock take (R3); non-destructive stale-Temp recovery guidance in guard + README, and early-abort staging cleanup so a locked source file no longer wedges every later run (F1 reproduced/R4); `FileBackupState.json` publish-by-rename (F7); Mirror-mode refusal of a root-level infrastructure-named data path instead of silent corruption (R2); filesystem-faithful RelativePath keying via `New-RelativePathMap` (F3, reproduced on Linux semantics); sidecar containment rule — a copied/moved store restores from ITSELF (F4, reproduced, both reviewers); missing-DataPath (hash,length) fallback in both restorers (F5); `\`-separator mapping in the PS restorer on Linux (F6); README Verify-repairs wording (R9); IF-001 JSON framing note (R8). **Restore kit is now revision 4.** | Fixed, tested (6 new Pester pins + bats 55/55 + shellcheck clean), audit entry below. | Landed — ratified 2026-08-23 |
| 7-Zip argument quoting (new, R6) | `Compress-`/`Expand-FileWithSevenZip` and `Get-MediaMBPerSec` hand-join quoted arguments into `ProcessStartInfo.Arguments`; a filename containing `"` (legal on Linux) mis-splits the 7-Zip command line. Failure is loud (set fails / exit 4). | Move to `ProcessStartInfo.ArgumentList` (per-argument, no quoting). Touches the kit module, so batch with the NEXT kit-revision bump rather than spending revision 5 on it alone. | Open |
| bash newline-in-filename rows (new, R7) | `reconstruct.sh`'s line-based FPAT parser cannot parse an RFC-4180 quoted field containing a newline — a legal Linux filename the engine can now write from a container backup; `Import-Csv` handles it, so the twin restorers diverge on the same manifest. Loud-ish (exit 1/4), not silent. | bash-v2 scope: refuse such rows with a clear message in bash, or refuse the filename at backup time on Linux. | Open → bash-v2 |
| no-7-Zip raw-candidate skip (new, R10) | Both restorers `continue` past a `.7z`-named hash-recovery candidate when 7-Zip is absent, never testing its raw bytes — which needs no 7-Zip and is exactly the revision-3 exemption shape. A restore needing no actual decompression can exit 4 "install 7-Zip" unnecessarily. | Low impact (a genuinely compressed store dies earlier anyway). Fold into the next kit-revision batch with R6. | Open |
| kit-less snapshot window (new, F8) | A crash inside `Complete-ChangeFolder` between the `Temp`→`Snapshot_*` rename and the kit-artifact copy loop yields a valid snapshot (manifest + witness) carrying NO restore kit (`Get-BackupKitRevision` = 0) — breaks the "every snapshot is self-contained" expectation; no byte loss. | Recoverable today via `-Action Verify -RefreshKits`. Candidate cheap fix: copy the kit into staging BEFORE the rename so the rename publishes a complete snapshot. Unscheduled. | Open |
| **D-1 stale cross-path dedup reference (2026-08-24 bench, VERIFIED)** | Mirror mode: a row adopting another path's DataPath is never revisited when the owner changes; `Save-SupersededData`'s source-based survival test then skips preserving the old bytes and the copy branch overwrites them in place — last copy destroyed, borrower + every blank snapshot row orphaned, invisible to every default check (only `-Deep` sees it, post-mortem). Hash-addressed mode proven immune by repro. | **Design decision required (human):** (1) end cross-path sharing in Mirror mode — each row owns its DataPath; per-mode SR-003 amendment; deletes the hazard and simplifies; costs Mirror dedup space; (2) copy-on-write/heal borrowers on owner change — keeps Mirror dedup, adds a fourth refcount site; (3) content-address all storage, Mirror as a restore view — strongest invariant, store migration + loses browsability. Driver recommends (1) + a one-time migration healing existing shared Mirror rows. Interim mitigations regardless: fix `$survivingContent` to consult the BACKUP's surviving rows, and D-2's restore verification as backstop. | **Open — awaiting design ruling** |
| **D-2 restore trusts DataPath (2026-08-24 bench, VERIFIED both restorers)** | Wrong payload, same-length bit-flip, and truncation all restore exit 0; `xxH2Hash` is the original-content hash so verify-after-write + fall-through to pool recovery is sound and symmetric with existing candidate testing. | Small fix, both restorers, kit revision bump; pairs with the "three witnesses" prior art in MiniPC-Deployer's restore. | Open — fix scheduled |
| **D-3 CandidateError outranks ContentMissing (2026-08-24 bench, VERIFIED)** | One unrelated bad `.7z` anywhere in the pool flips "your bytes are gone" (1) into "fix this host" (4). Every CandidateError the locators raise is by construction from a non-own candidate, so the reorder needs no new state. | Trivial precedence reorder in both locators (DependencyMissing/StorageUnreadable stay above ContentMissing; CandidateError drops below), same kit bump as D-2. | Open — fix scheduled |
| **D-4 hidden/dot-prefixed files never backed up (2026-08-24 bench, VERIFIED; systemic)** | No PowerShell-side `Get-ChildItem` in the repo uses `-Force` — source walks, restore pool scan, prune residue scan; bash `find` does not skip dot-files, so the twin restorers disagree. Silent omission with zero disclosure. | Small fix: `-Force` on all enumeration sites + a disclosed skipped-by-policy count per run; one design question (Windows Hidden-attribute semantics / per-set opt-out) for the human. | Open — fix scheduled, one design question |
| **D-5 same-run duplicates stored in full (2026-08-24 bench, VERIFIED, Mirror-only)** | The dedup lookup consults only the prior backup; the `Duplicate` label and storage disagree. Same mechanism as D-1 from the safe side; resolves with whichever D-1 design is chosen. G2.8's existing assertion is VACUOUS (`-le 2`) and must be fixed regardless. | Fold into the D-1 design decision; fix the vacuous assertion immediately. | Open — folded into D-1 ruling |
| Windows reserved device names (new, WP8 review minor 2) | `CON`, `NUL.txt`, `COM1.dat` etc. pass `Test-PortableRelativePath` as portable — SR-055 as ruled never claimed them, and the worst case is a loud copy failure on a Windows restore, but they are one more not-on-both-platforms name class. | Follow-up note only; extend SR-055's character rules if it ever bites. | Recorded |
| no-7z double host record (WP8 review minor 3, accepted) | An UNREADABLE `.7z` candidate met with no 7-Zip records both CandidateError and DependencyMissing for one candidate in `Reconstruct.ps1`'s locator. Cosmetic: hostIssues aggregate, DependencyMissing outranks by design, and the reported cause is correct. | Accepted as-is — not worth a kit-revision-relevant edit on its own; fold into the next kit touch. | Accepted |

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

