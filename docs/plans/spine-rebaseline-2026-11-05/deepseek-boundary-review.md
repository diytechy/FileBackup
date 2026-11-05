# DeepSeek boundary cross-review

Date: 2026-11-05 (America/Chicago). Advisory review, not approval.

Provider/model: `opencode-go/deepseek-v4.1-flash`, through OpenCode CLI 1.19.4.
Input revision: `3f8c2db`, before the response corrections recorded in the
[boundary review guide](boundary-review.md). The five inputs were the live
stakeholder needs, external frame, assumptions, hats and owner-review-01.
Each was attached separately, under 50 KB, with a completeness marker.
The reviewer confirmed all markers and registry counts below. It received
no source code and ran in a fresh temporary directory, with the plan agent,
external plugins disabled and all tool permissions denied. This is an
independent model perspective, not an approval or evidence of implementation
compliance; global OpenCode instructions may still influence its context.

The prompt requested at most ten concrete findings about frame completeness,
unsupported guarantees, implementation constraints and assumptions that weaken
approved needs, distinguishing frame fixes from later requirements work and
owner questions. Approved needs could not be silently amended. B-24 was
explicitly identified as inactive legacy debt. The complete prompt, marked
input copies and JSON event stream are retained locally under the ignored
`.artifacts/boundary-review/` directory (`prompt-go-complete.txt`,
`complete-inputs/`, `deepseek-go-complete.jsonl`).

An earlier combined attachment was truncated by OpenCode at 50 KB; its report
was discarded as an incomplete-input review. It is not counted as corroborating
findings. This rerun used a new session and the complete documents.

## Reviewer response (verbatim wording)

Trailing whitespace and line endings are normalized.

## Input confirmation

All five documents are present and complete:

- `# END OF COMPLETE INPUT: stakeholder-needs.toml` — 49 needs; 3 stakeholders (STK-01–03).
- `# END OF COMPLETE INPUT: external.toml` — 18 entities (EXT-01–18); 24 boundaries (B-01–24, B-24 inactive); 5 relationships (REL-01–05).
- `# END OF COMPLETE INPUT: assumptions.toml` — 22 assumptions (DA-01–22); 2 surrogates (SUR-01–02).
- `# END OF COMPLETE INPUT: hats.toml` — 9 hats.
- `# END OF COMPLETE INPUT: owner-review-01.md` — terminates at “Implementation boundary.”

No truncation noted. No implementation compliance is inferred.

## Findings

1. **High — Nonmutating check/report conflicts with store-side operational logging.** `SN-030`, `SN-046`, `EXT-15`, `B-20`.
   **Frame correction plus later SR definition.** B-20 permits operational run state and logs “kept on the store side.” SN-030 requires a check to leave the store byte-identical; SN-046 requires a retention report not to mutate the store. If check/report logging is written inside the store, both acceptance criteria fail.
   **Smallest correction:** make B-20 distinguish protected backup content from an operational-record/view area, and state that check/report writes cannot alter protected store content. Define “store” for nonmutation in the SR tier. Do not weaken SN-030/046.

2. **Medium — Duplicate-root refusal lacks a clear unattended machine-readable crossing.** `SN-039`, `SN-045`, `B-04`, `B-06`, `B-07`, `B-08`.
   **Frame correction.** SN-039 requires refusal with conflicting entries identified; SN-045 requires configuration-refused as a distinct host-visible outcome. B-04 carries coordination/busy results, not admission findings. B-06 is the owner route. B-08’s machine-readable findings are expressly “for listings and checks,” so duplicate-root identification is not clearly carried to an unattended host.
   **Smallest correction:** make B-08 carry machine-readable configuration-refusal findings, including duplicate resolved roots and conflicting entries, or add a dedicated refusal output.

3. **Medium — Retention cutoff versus “every saved state” check.** `SN-029`, `SN-030`, `SN-034`, `B-02`, `B-13`.
   **Genuine owner/SR clarification; not a frame omission.** SN-029 and B-13 allow older folders to survive outside the supported recovery window. SN-030 requires checking the latest and every saved state and reporting missing content. If surviving out-of-window folders remain “saved states,” an intact retained window may fail a check because retention intentionally invalidated those older folders. If they are ignored, SN-030’s “every” is narrowed.
   **Smallest correction:** define whether out-of-window surviving folders are excluded from “saved state,” reported separately as out-of-window, or checked with expected failures. Do not reopen the approved retention reporting/removal authorization.

4. **Medium — DA-14 turns SN-007’s explicit case into an out-of-scope assumption.** `DA-14`, `SN-007`, `SN-001`.
   **Assumptions review.** DA-14 assumes content changes alter size or modification time. SN-007 exists precisely because some changes do not; it requires a configurable re-read from every run to never. Treating DA-14 as an active premise would weaken SN-007.
   **Smallest correction:** recast DA-14 as a default detection heuristic, not a guarantee; keep SN-007 re-read verification independent of it.

5. **Medium — DA-08 assumes away name collisions that SN-032 requires reporting.** `DA-08`, `SN-032`, `B-15`, `B-16`.
   **Assumptions review.** DA-08 holds when the target is case-sensitive, or no source names differ only by case, and normalization is not rewritten. SN-032 explicitly requires case and normalization collisions to be reported without overwrite or merge. A premise that excludes those cases narrows the obligation.
   **Smallest correction:** limit DA-08 to representability of non-colliding names; preserve SN-032 collision detection/reporting as required behavior, not an environmental failure.

6. **Medium — B-22’s “or” can be read as container-only delivery.** `B-22`, `EXT-17`, `SN-024`, `SN-055`.
   **Frame correction.** EXT-17 describes native executables for supported Windows/Linux/macOS hosts and an optional container image. B-22 says “Native release bundles or a container image.” That permits a reading where declared native OS/CPU support is satisfied by a container alone, contrary to SN-055 and SN-024’s optional-container status.
   **Smallest correction:** require native bundles for each declared OS/CPU and, where offered, the optional container image.

7. **Medium — DA-17/SUR-01 evidence is narrower than the declared platform/store promises.** `DA-17`, `SUR-01`, `SN-023`, `SN-039`, `SN-055`, `EXT-05`.
   **Assumptions review.** The surrogate is mapped temporary drives on a local NTFS assumption. It cannot evidence native Linux/macOS operation, cross-host store interchange, or removable/network/synchronized/non-NTFS stores. EXT-05 correctly warns that naming a storage type does not designate every instance as supported, but DA-17 may be read as covering the store promise.
   **Smallest correction:** state that SUR-01/DA-17 is Windows local-NTFS test evidence only; require separate evidence or an explicit declared matrix for every claimed host and store filesystem.

8. **Low — B-04 release wording does not clearly cover holder death.** `B-04`, `SN-039`, `DA-02`.
   **Frame wording.** SN-039 requires release when the holder ends or dies; B-04 says ownership ends when the operation “completes or is interrupted.” A kill or crash may not read as “interrupted.”
   **Smallest correction:** align B-04 to “completes, ends, is interrupted, or dies under the declared host contract,” without prescribing a mechanism.

9. **Low — B-24 remains machine-readable as Drafted/operation.** `B-24`, `B-01`, `SN-037`.
   **Frame traceability housekeeping.** The comment calls B-24 inactive, but its row still has `status = "Drafted"` and `system = "operation"`. Coverage tooling or a reader can count it as an authorized source write, contradicting B-01/SN-037.
   **Smallest correction:** mark B-24 retired/inactive in the row, or move it out of the active B namespace once downstream references are reconciled; exclude it from coverage. This is not a request for source writes.

## Coverage checks

I found no missing external exchange for external deletion/repair (`REL-01`, `B-02`, `B-06`/`B-08`), link fidelity (`B-16`, `B-15`), target confinement (`B-14`, `B-17`; SN-042 is internal behavior, not a new crossing), conditional provisioning (`B-11`, `B-23`), or handoff (`B-13`, `REL-02`). The native-engine versus carried-recovery distinction is represented (`B-10`, `B-18`, `B-19`, `B-22`, `B-23`), subject to findings 6 and 7.

## Readiness

**Conditionally ready for owner boundary review; not ready for approval as-is.** Findings 1, 2 and 6 are frame corrections; 8 and 9 are housekeeping; 4, 5 and 7 are assumptions-review work; 3 requires one owner/SR clarification. No new scope is required and no approved need is silently amended.

The only genuine owner-level ambiguity is SN-030’s treatment of surviving out-of-window folders. The support matrix and the already-recorded no-older-version designation are release/SR decisions unless the owner chooses to elevate them to boundary commitments. This is advisory review, not approval.
