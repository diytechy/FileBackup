# Gemini Argon high-risk design review

2026-11-05. Requested by the owner; OpenCode Go model
`opencode-go/gemini-4-argon`, variant `low`, CLI 1.19.4. Session
`ses_e50f8a664ffe1gFvSAthNlADSF`. Both responses completed with `step_finish=stop`.
This is advisory static review, not approval, source inspection or executed tests.

## Author disposition

The follow-up reported **no remaining high-risk findings**. That is the reviewer's
judgment within the supplied scope, not proof of implementation safety.

| Initial candidate | Disposition |
|---|---|
| Stale directory/link record beside a checkpointed manifest can look complete | Accepted. Draft now specifies `INCOMPLETE_RUN` before latest mutation, clearing after synced final metadata, propagation into snapshots of interrupted states, preservation across cleanup/refresh, and incomplete recovery status with unfinalized links omitted. Implement/test in N1/N3/N5. |
| Prune cutoff could sweep unexamined older folders or resume without survivor supply | Not sustained as high risk: required an unproposed sweep or external postcommit deletion. Clarified explicit deletion set, whole-batch survivor exclusion, synced rehoming before commit and non-expanding resumption. |
| Missing-object recapture could treat changed bytes as an unchanged repair | Clarification of existing semantic-identity constraints. Fresh identity equality is repair; inequality is a source change plus a missing-historical-content diagnostic. |

The initial response said 12 attachments while naming all 13. The reviewer
confirmed that was a counting typo in the follow-up. Input record counts were
49 approved SNs, 121 approved SRs, 40 Drafted LLRs and 41 planned cases. No approved
upstream requirement changed. The proposed scale pool cap remains for owner
review; the reviewer's rough I/O calculation is not performance evidence.

## Reproduction and input scope

Run from a fresh temporary working directory with tool permission denied:

```powershell
$env:OPENCODE_CONFIG_CONTENT = '{"permission":{"*":"deny"}}'
opencode run $reviewPrompt --model opencode-go/gemini-4-argon --variant low --pure --agent plan --dir $reviewDir --format json --file @reviewFiles
```

Follow-up added `--session ses_e50f8a664ffe1gFvSAthNlADSF` and four revised
attachments. The reviewer had no repository tools. Initial inputs: approved
needs/frame/assumptions/hats, four complete SR slices, review/contracts/flows,
and the new LLR/TC slices. Every attachment was below 50 KB with an end marker.
The follow-up supplied revised contracts/flows/new LLRs/new cases and challenged
the assumptions behind findings 2/3. No earlier reviewers' reports were supplied
in the independent first pass.

Inputs were an uncommitted draft over `9e03be4`; the
[input provenance](review-inputs.json) records source hashes for each round.
The exact response text follows; severity labels belong to the reviewer, and
the author dispositions above control how this package uses them.

## First response

**Input Confirmation**
All 12 attachments read and `END OF COMPLETE INPUT` markers confirmed (`assumptions.toml`, `contracts.md`, `external.toml`, `flows.md`, `hats.toml`, `new-cases.toml`, `new-llrs.toml`, `review.md`, `sr-part-1.toml`..`sr-part-4.toml`, `stakeholder-needs.toml`). Verified counts: 49 Approved SNs, 121 Approved SRs, 40 Drafted LLRs (`LLR-151`..`LLR-190`), and 41 Drafted test cases (`TC-261`..`TC-301`).

---

### High-Risk Findings

#### 1. Unmarked Checkpoint Manifest Paired with Pre-Run `DIRECTORIES.csv` Causes Silent Missing-Directory/Link Recovery (`Complete` Status After Interrupted Run)
* **IDs and Clauses:** `LLR-165` (`publish_latest_state`), `LLR-164` (`decode_state_records`), `LLR-175` (`apply_recorded_metadata`), `contracts.md` ("Publication and maintenance"), `flows.md` ("Backup and interruption"); `SR-082`, `SR-146`, `SR-152`, `SN-013`, `SN-036`.
* **Causal Scenario & Assumptions:** During a changing run (`LLR-165`), the prior state is staged to `BackupHistory/<date>`, and the loop checkpoints valid file progress into `CurrentBackup/MANIFEST.csv` via atomic replacement (`DA-01`), while `CurrentBackup/DIRECTORIES.csv` and completion markers are updated only at finalization. If the process is killed (`DA-02`) after one or more manifest checkpoints:
  1. New empty folders, hidden/system folders, or in-root `FolderLink` entries created on the source in this run are absent from the pre-run `CurrentBackup/DIRECTORIES.csv`.
  2. Or, a path that was an empty `Directory` in the prior run (still listed in the old `DIRECTORIES.csv`) was replaced on the source by a parent directory with children or changed in link/attribute status without creating a path-kind conflict that the parser can detect.
  When a standalone restore kit (`EXT-02`, `LLR-172`, `LLR-175`) runs against `CurrentBackup`, both `MANIFEST.csv` and the stale `DIRECTORIES.csv` are present and syntactically well-formed CSVs of the current format revision. Because `contracts.md` specifies a 9-column `MANIFEST.csv` and 4-column `DIRECTORIES.csv` with no run-generation token or checkpoint-in-progress flag inside either file, and `LLR-172` only reads those two files, the restore kit cannot detect that `DIRECTORIES.csv` is unfinalized for the checkpointed `MANIFEST.csv`. It restores the checkpointed files and stale directories and exits `0` (`Complete`), violating `SR-146`, `SR-152`, and `LLR-165` ("A failed required directory/link write prevents a complete result and identifies the metadata gap").
* **Classification:** Design defect in `LLR-164` / `LLR-165` / `LLR-172` (acknowledged as an open risk in `contracts.md` lines 79–81, but left without a concrete detection mechanism in the record contracts).
* **Smallest Architecture-Compatible Correction:** Keep the two-file layout and checkpoint loop. Before the first `CurrentBackup/MANIFEST.csv` checkpoint of a run, either:
  * Write `CurrentBackup/DIRECTORIES.csv` early (before file checkpoints begin, since `walk_source` / `LLR-156` already enumerates the directory/link tree) so `DIRECTORIES.csv` always covers any subsequently checkpointed `MANIFEST.csv` rows; or
  * Record a lightweight state-completion marker / generation ID shared between `MANIFEST.csv` and `DIRECTORIES.csv` (or a kit-visible `INCOMPLETE_RUN` sidecar in `CurrentBackup` removed at finalization) that carried recovery scripts check so an interrupted checkpointed state always reports `1` (`Incomplete`) with a named unfinalized-metadata diagnostic rather than `0` (`Complete`).

---

#### 2. Resumable Prune Deletion List vs. Cutoff Rehoming Scope Can Delete Un-Rehomed Objects Needed by Retained Later States After a Crash
* **IDs and Clauses:** `LLR-169` (`plan_and_commit_removal`), `LLR-170` (`sweep_unprotected_objects`), `LLR-166` (`resume_interrupted_work`), `flows.md` ("Managed removal"); `SR-045`, `SR-046`, `SR-059`, `SR-101`, `DA-01`.
* **Causal Scenario & Assumptions:** In the single-store layout (`LLR-163`), `BackupHistory/<date>` folders hold flat content objects that younger states may reference from the shared pool. Under `SR-045`, removing cutoff date $D_k$ invalidates both $D_k$ and all older dates $D_{<k}$, while protecting `CurrentBackup` and retained later states $D_{>k}$. Two failure edges arise in `LLR-169`/`LLR-170`:
  1. **Older-folder deletion scope:** If removing cutoff $D_k$ also deletes or sweeps invalidated older folders $D_{<k}$ (or if multiple dates $\le D_k$ are removed in one request), scanning only the single selected folder $D_k$ for last-copy objects misses shared objects physically residing in $D_{<k}$ that are still referenced by protected states $D_{>k}$ or `CurrentBackup`.
  2. **Crash resumption after `Pruning` commit:** `LLR-169` states: *"Only after survivor supply is available commit the selected removal through the established Pruning phase and finish deletion. Repeating the request resumes safely"*, and `LLR-166` states: *"resume or report Pruning work under the retention protocol."* If a prune commits the `Pruning` phase and is interrupted mid-deletion, and a subsequent backup run (`LLR-166`) or repeated prune (`LLR-169`) finishes deleting the `Pruning` folder without re-verifying that every protected state ($D_{>k}$ and `CurrentBackup`) currently has verified outside supply, any interruption or external change between rehoming and deletion completion permanently destroys the last copy needed by a protected state.
* **Classification:** Design defect / ambiguity in `LLR-169`, `LLR-170`, and `LLR-166`.
* **Smallest Architecture-Compatible Correction:** Clarify in `LLR-169` and `LLR-170` that:
  1. Destructive deletion in a prune operation touches *only* the specific folder(s) whose contents were explicitly checked against the protected manifest set ($D_{>k}$ and `CurrentBackup`) and rehomed; older invalidated folders $D_{<k}$ not rehomed-from are left on disk unless included in the rehoming scan.
  2. Resuming an interrupted `Pruning` folder (`LLR-166`, `LLR-169`) must either re-verify that outside supply exists for all protected states before unlinking remaining objects in `Pruning`, or only rename the target state folder into `Pruning` *after* all required objects have been moved/copied out and fsynced into survivor folders.

---

#### 3. Re-Capturing Externally Lost Content (`SR-053`) When Source Bytes Changed Silently Mutates `CurrentBackup` While Reporting an Unchanged/Repair Run (`SR-024` / `SR-100`)
* **IDs and Clauses:** `LLR-158` (`select_capture_work`), `LLR-159` (`capture_verified_object`), `LLR-165` (`publish_latest_state`); `SR-011`, `SR-024`, `SR-053`, `SR-100`, `DA-14`.
* **Causal Scenario & Assumptions:** Suppose an external actor (`EXT-13`, `REL-01`) deletes a stored content object $H_1$ referenced by file $F$ in `CurrentBackup/MANIFEST.csv`. Simultaneously, on the source (`EXT-04`), $F$ was modified in place without changing its byte length or timestamp (`DA-14`, e.g., coarse filesystem timestamp resolution, restored timestamp, or fixed-size container/database edit), so its current bytes now hash to $H_2 \neq H_1$, while a periodic reread (`SR-011`) is not due.
  * Under `SR-053` and `LLR-158`, because object $H_1$ is missing from the store, the run must re-read $F$ regardless of the reread schedule.
  * Re-reading $F$ produces `(H_2, Length)`, which differs from the prior manifest's `(H_1, Length)`.
  * `SR-024` and `SR-100` state that a run repairing externally lost bytes from an unchanged source adds no saved state and reports zero source changes. However, if `LLR-158` / `LLR-159` treats a missing-supply re-capture as a repair whenever `size` and `mtime` matched, it will either overwrite `CurrentBackup`'s row with $H_2$ while discarding the staged `BackupHistory/<date>` snapshot (treating it as an unchanged repair run under `SR-100`) or face a contradiction with `LLR-159` ("without claiming changed current bytes reconstruct a missing historical version"). Conversely, when $H_2 \neq H_1$, the source *did* change ($H_1$ is permanently lost, and $H_2$ is a new source version).
* **Classification:** Design defect in `LLR-158` / `LLR-159` interaction.
* **Smallest Architecture-Compatible Correction:** Specify in `LLR-158` and `LLR-159` that when a missing/unusable object triggers a forced source read (`SR-053`):
  * If the freshly captured hash/length equals the recorded latest identity $H_1$, classify the action as a **content repair** (no source change, no new history state needed if no other changes occurred, satisfying `SR-024` and `SR-100`).
  * If the freshly captured hash/length $H_2$ differs from $H_1$, classify $F$ as a **changed source file** (preserving the prior state record in `BackupHistory/<date>` under `SR-005`) *and* emit a distinct diagnostic warning that the prior version $H_1$ was already missing from the pool and could not be repaired from the changed source.

---

### Review Limits
* This review is strictly static and advisory against the supplied design breakdown and requirements; no implementation code, existing PowerShell/bash scripts, or runtime test artifacts were inspected or executed, and planned test cases (`TC-261`..`TC-301`) are not treated as execution evidence.
* The proposed scale reference interpretation in `contracts.md` and `LLR-189` (capping the whole-store unique-content pool at 2 TiB for the 8-hour `SR-064` check benchmark while keeping 365 states and 1M paths/state) is mathematically consistent with the 100 MiB/s SSD floor (~5.8 hours raw sequential read of 2 TiB) and 2 GB RAM budget (via `LLR-188` streaming/spilling), provided the owner accepts that 2 TiB unique-pool bound as the benchmark interpretation of `SR-064`.

## Follow-up response

**Input & Count Confirmation**
* **Attachment count clarification:** Yes, "12 attachments" in the initial report was a count typo for the 13 actual files inspected (4 context TOMLs, 4 SR chunks, 3 design MDs, 2 new LLR/TC TOMLs).
* **Revised inputs:** All four revised attachments read and their `END OF COMPLETE INPUT` markers confirmed (`# END OF COMPLETE INPUT: revised contracts.md`, `# END OF COMPLETE INPUT: revised flows.md`, `# END OF COMPLETE INPUT: revised new-cases.toml`, `# END OF COMPLETE INPUT: revised new-llrs.toml`).
* **Row counts:** Confirmed 40 Drafted LLRs (`LLR-151`..`LLR-190`) and 41 Drafted test cases (`TC-261`..`TC-301`), with 49 Approved SNs and 121 Approved SRs unchanged. No test execution or implementation evidence is assumed.

---

### Dispositions of Initial Findings

1. **Finding 1 (Unfinalized `DIRECTORIES.csv` vs. Checkpointed `MANIFEST.csv`): Closed / Resolved.**
   * **Evaluation:** The `INCOMPLETE_RUN` protocol marker in `contracts.md` (lines 79–93), `flows.md` (lines 24, 33, 79, 86), `LLR-164`, `LLR-165`, `LLR-166`, `LLR-172`, `LLR-186`, `TC-275`, and `TC-282` closes the causal gap while preserving the existing two-file record layout and bounded checkpoint loop. Installing and syncing `INCOMPLETE_RUN` before the first `CurrentBackup` record mutation, propagating it if a prior interrupted `CurrentBackup` is snapshotted into `BackupHistory/<date>`, preserving it across cleanup (`LLR-166`) and kit refresh (`LLR-186`), and clearing it only after final `MANIFEST.csv`, `DIRECTORIES.csv`, and completion markers are synced ensures that under `DA-01`/`DA-15` neither script route can mistake a checkpointed state with stale directory/link metadata for a finalized tree. Omitting unfinalized links and reporting incomplete metadata while still recovering verified ordinary files satisfies `SR-082`, `SR-146`, and `SR-152`.

2. **Finding 2 (Prune Deletion Scope and Resumption Boundary): Reclassified (Not Sustained as High-Risk Defect) & Closed by Clarification.**
   * **Evaluation:** Upon re-evaluating the baseline draft without assuming an unstated cutoff-wide sweep or post-commit external deletion (`EXT-13`), the original text of `LLR-169`/`LLR-170` already restricted removal to named folders and required survivor supply before committing `Pruning`. The revised text in `contracts.md` (lines 100–103), `LLR-169`, `LLR-170`, and `TC-279` makes the batch supply exclusion, non-deletion of unselected older invalidated folders, sync-before-`Pruning` commit, and non-expanding resumption explicit. No high-risk gap remains.

3. **Finding 3 (Forced Recapture of Missing Object When Source Bytes Changed): Reclassified (Clarification of Existing Constraints) & Closed.**
   * **Evaluation:** The original `LLR-158` ("Compare semantic state, not serialization order") and `LLR-159` ("without claiming changed current bytes reconstruct a missing historical version") already implied comparing captured content identity rather than relying on `size`/`mtime` after a forced read. The explicit wording added to `contracts.md` (lines 105–107), `LLR-158`, `LLR-159`, and `TC-268`—distinguishing matching-hash repair from different-hash source change plus an unrecoverable-prior-content diagnostic—eliminates any ambiguity.

---

### Remaining or New High-Risk Findings

None. No remaining or newly introduced high-risk scenarios qualify under the review criteria.

---

### Review Limits
* This review is static and advisory against the draft specifications; no implementation code or test execution exists or is inferred from `TC-261`..`TC-301`.
* The proposed 2 TiB unique-content pool cap in `contracts.md` and `LLR-189` remains an explicit owner-review decision for bounding the reference `SR-064` check corpus, and back-of-the-envelope I/O bounds are not a substitute for measured cross-host performance evidence (`TC-298`, `TC-299`).
