# Gemini review of the previous-definition correction

2026-11-05. OpenCode Go `opencode-go/gemini-4-argon`, variant `low`, session
`ses_e509b639fffe5XvEWuSS0o5Cs6`. Both responses completed with `step_finish=stop`.
Advisory text review only: no runtime/code access or test execution.

## Author disposition

The follow-up reports no remaining high-risk issues within the owner's scope.
Two first-pass candidates were assessed rather than applied automatically:

- **Supplemental metadata conflict:** retained one clarification. A stale
  directory/link record cannot prevent independent valid manifest file recovery.
  Reject/report that metadata; restore through safe ordinary directories. File-row
  collisions and unsafe pre-existing target redirects remain refused. LLR-174 and
  TC-284 now state this explicitly. No marker or transaction scheme was added.
- **History loss after restart:** rejected and withdrawn. The scenario assumed
  relocation looked only at this run's changes and ignored intact pool content.
  The retained design uses final latest dependencies and prior-state manifests;
  backup does not delete objects. Prior snapshot publication precedes checkpoint
  mutation. There is no justification for making `.prev` an automatic baseline.

The reviewer initially listed seven attachments while saying six; the follow-up
confirmed a counting typo and named all seven. Minor later edits add explicit
SR-005/100 parent references to LLR-158/TC-268 and make the existing successful-
backup-only deletion condition an explicit flow branch. No new mechanism is
claimed reviewed on that basis.

## Inputs and method

A fresh temporary directory, `--pure --agent plan --format json`, all tool
permissions denied; seven attachments under 50 KB each with end markers:
contracts, flows, owner disposition, 40 drafted LLRs, 41 planned cases, assumptions
and 12 accepted SRs. The review asked for concrete high-risk causal failures only,
explicitly preserving owner checkpoint, retention and `.prev` semantics.

The follow-up supplied the exact conflict-handling clarification in its prompt
and challenged the unsupported relocation/deletion assumptions. Initial source
hashes and the exact follow-up prompt are in the [review record](prev-review-inputs.json).
The owner's [scoped decision record](owner-prev-review.md) controls the draft;
reviewer conclusions are not implementation proof or owner approval of all LLRs.

## Initial response

**Attachment & Inventory Confirmation**
- Six attachment `END OF COMPLETE INPUT` markers are present in the supplied prompt (`accepted-sr-context.json`, `assumptions.toml`, `contracts.md`, `draft-cases.toml`, `draft-llrs.toml`, `flows.md`, and `owner-prev-review.md`—note: 6 files were attached in the prompt context, while `review.md` referenced in the text was not attached, making 6 observed END markers rather than 7).
- Confirmed: 40 Drafted LLRs (`LLR-151`..`LLR-190`), 41 planned test cases (`TC-261`..`TC-301`), 12 accepted SRs in context, and `assumptions.toml` (`DA-01`..`DA-22`, `SUR-01`..`SUR-02`).

---

### High-Risk Findings

#### 1. Un-checkpointed `DIRECTORIES.csv` causes directory/file path conflicts or lost folder metadata when restoring an interrupted run's default records
* **Clauses:** `flows.md` ("Backup and interruption": per-entry loop checkpoints `MANIFEST.csv` file rows, while `DIRECTORIES.csv` is written only after the loop: *"Final manifest then directory/link record then completion markers"*); `contracts.md` ("Directory/link sidecar: extend" & "Publication and maintenance"); `LLR-164`; `LLR-165`; `LLR-172`; `SR-082`.
* **Causal sequence:**
  1. Run 1 completes with directory `A/B` (or in-root `FolderLink` `A/B`) recorded in `CurrentBackup/DIRECTORIES.csv`.
  2. In the source, the user replaces directory/link `A/B` with an ordinary file `A/B` (or adds files under a newly created folder/renamed tree).
  3. Run 2 starts, copies Run 1's records to `.prev`, captures file `A/B`, checkpoints `CurrentBackup/MANIFEST.csv` with file `A/B`, and is killed before finalization writes the new `DIRECTORIES.csv`.
  4. `CurrentBackup` now contains Run 2's checkpointed `MANIFEST.csv` (where `A/B` is a file) paired with Run 1's `DIRECTORIES.csv` (where `A/B` is a `Directory` or `FolderLink`).
  5. Under `LLR-164` and `LLR-174`, default recovery of `CurrentBackup` validates `MANIFEST.csv` against `DIRECTORIES.csv`, detects a file/directory/link path conflict on `A/B`, and **rejects recovery of the newly captured file `A/B`** (violating `SR-082` *"published latest progress reconstructs the recorded captured files"*), or fails to recreate newly added empty folders/links alongside checkpointed files.
* **Smallest correction:** In `LLR-165` and `flows.md`, either checkpoint `DIRECTORIES.csv` alongside `MANIFEST.csv` during bounded progress checkpoints, or specify in `LLR-164`/`LLR-174` that when `MANIFEST.csv` is newer than `DIRECTORIES.csv` (e.g., `.prev` is present from an interrupted run), a checkpointed file row in `MANIFEST.csv` supersedes a stale `Directory`/`FolderLink` entry at the same path in `DIRECTORIES.csv` (with a metadata warning rather than rejecting the file write).

#### 2. Unchanged run after an interrupted run can delete the pre-interruption dated snapshot while its content was never moved or finalized
* **Clauses:** `flows.md` ("Backup and interruption": *"Stage prior records and kit; rename Building to dated state"* before loop; *"Remove unneeded new snapshot; move superseded objects last; Delete .prev only on successful backup completion"*); `LLR-165`; `LLR-158`; `SR-005`; `SR-082`.
* **Causal sequence:**
  1. State $S_0$ is in `CurrentBackup`.
  2. Run 1 starts, stages $S_0$ into `BackupHistory/<date1>`, copies $S_0$ to `.prev`, captures changed file $F_1$, checkpoints `CurrentBackup/MANIFEST.csv` (now $S_1$), and is killed before finalization. (Superseded object for $F_0$ was not yet moved to `<date1>`, and `DIRECTORIES.csv` is still $S_0$'s).
  3. Run 2 starts after the interruption. Following `flows.md` and `LLR-165` unconditionally: Run 2 reads prior state from `CurrentBackup` ($S_1$ manifest), stages `CurrentBackup` into `BackupHistory/<date2>`, leaves existing `.prev` ($S_0$) alone, and scans the source.
  4. Because the source did not change between Run 1's checkpoint and Run 2, Run 2 sees no change relative to its baseline (`CurrentBackup` $S_1$, `LLR-158`).
  5. Run 2 finalizes as an unchanged run: it removes its "unneeded new snapshot" (`<date2>`), does **not** move $S_0$'s superseded $F_0$ object into `<date1>` (since $F_1$ was reused, not newly superseded in Run 2), and deletes `.prev` on successful completion.
  6. Result: `.prev` ($S_0$) is deleted, and `<date1>` in `BackupHistory` never received its superseded content $F_0$ (which remains unreferenced in `CurrentBackup` shards until a later prune or check flags it misplaced, or if Run 1 was killed *before* `<date1>` rename completed, $S_0$ history is lost entirely when `.prev` is deleted).
* **Smallest correction:** In `LLR-158` and `LLR-165`, specify that when `.prev` exists on entry (indicating the prior run did not finalize), change detection for history retention, prior-snapshot creation, and superseded-object relocation must compare the final captured state against `.prev` (the last completed state $S_0$), rather than against the unfinalized checkpoint in `CurrentBackup`.

---

### Scope & Review Limits
- Evaluated strictly against the provided text attachments without repo/code access, runtime execution, or external assumptions.
- Lower-risk observations, N1 schema/format pinning, and unmeasured performance envelopes are excluded per instructions.

## Follow-up response

**Attachment & Inventory Confirmation**
- **Count Clarification:** Yes, that was a count typo on my part. All **seven** actual attachments and their `END OF COMPLETE INPUT` markers were present and observed by basename:
  1. `accepted-sr-context.json`
  2. `assumptions.toml`
  3. `contracts.md`
  4. `draft-cases.toml`
  5. `draft-llrs.toml`
  6. `flows.md`
  7. `owner-prev-review.md`
- Also confirmed: 40 Drafted LLRs (`LLR-151`..`LLR-190`), 41 planned test cases (`TC-261`..`TC-301`), 12 accepted SRs in context, and `assumptions.toml`. No unobserved inputs were accessed or used.

---

### Re-evaluation & Final Disposition

#### Finding 1: Closed
- **Assessment:** The normative clarification to `LLR-174` and `TC-284`—rejecting only the conflicting supplemental `DIRECTORIES.csv` directory/link record while restoring independently valid `MANIFEST.csv` file rows through safe ordinary parent directories and reporting metadata damage—completely closes the concrete recovery conflict scenario.
- Because it relies strictly on record roles (authoritative file manifest vs. supplemental directory/link sidecar) rather than timestamps, `.prev` presence, or pairing transactions, it preserves `SR-082` checkpointed file recovery without strengthening bounded checkpoint scope.

#### Finding 2: Withdrawn
- **Assessment:** Withdrawn as unsupported. Under the existing sequence (`flows.md` / `LLR-165`), the prior snapshot (`<date1>`) is staged and renamed *before* `.prev` copies and *before* any `CurrentBackup/MANIFEST.csv` checkpoint can occur, so a checkpoint cannot coexist with an uncreated `<date1>` snapshot. Furthermore, `LLR-163` determines superseded objects against final latest dependencies across the store rather than single-run deltas, and any unreferenced object remaining in a `CurrentBackup` shard stays intact and discoverable in the shared pool without being deleted by backup or unprotected prune. Keeping `.prev` strictly auxiliary and using `CurrentBackup` as the baseline causes no loss of protected data or history.

---

### Remaining High-Risk Issues
- **None.** There are no remaining qualifying high-risk causal issues within the owner's scope.

---

### Scope & Review Limits
- Evaluated strictly against the seven supplied text attachments and the stated `LLR-174`/`TC-284` clarification, with no repository access, tool execution, or runtime verification.
- Lower-risk suggestions, N1 contract details, and performance characterization are excluded.
