# Gemini Argon interface review

Requested by the owner; OpenCode Go `opencode-go/gemini-4-argon`, variant `low`,
session `ses_e50896023ffeyacgouP9yHfXmn`. Both responses ended with
`step_finish=stop`. This is static advisory review, not execution evidence,
approval or a claim that all contracts are implemented.

## Author disposition

The complete-input follow-up found **no remaining high-risk issues**. Its use of
"verified" refers to reading the draft text, not testing the tool.

| Candidate | Disposition |
|---|---|
| Readable-secret refusal owned only by notification rather than initial config admission | Accepted as a concrete allocation gap. Added SR-129 to LLR-151/TC-261 and explicit pre-mutation rejection to IF-002, including disabled-notification/non-notifying actions and nonsecret diagnostics. Approved SR text unchanged. |
| Publication and pool consumer links could permit early superseded moves | High-risk conclusion not sustained: the existing ordering already forbids early moves. Clarified the actual dependency instead: native/state consumes IF-007, IF-008 names codecs/platform/pool orchestration, and filesystem effects are tied to B-02 through IF-014. No new transaction or marker mechanism. |

The initial response reported incorrect counts and a truncated long line in the
legacy contract. It was **not accepted as a complete review**. All inputs were
resupplied as short-line rendered text, split at record/paragraph boundaries,
with each ordinary attachment below 12.5 KB and an end marker. The follow-up
confirmed all 40 attachments and corrected the inventory to 25 IFs, 40 new
LLRs, 41 planned TCs, 121 approved SRs, 49 approved SNs plus three stakeholder
records, 46 frame records and 24 assumption/surrogate records.

## Inputs and execution

Fresh temporary working directory, `--pure --agent plan --format json`, all tool
permissions denied. The first 15 attachments supplied the registry, contracts,
trace map, store design, adoption record, legacy agreement and upstream context.
The follow-up supplied all of that scope afresh with the corrections and explicit
mechanically counted ID inventory. The model had no repository tools or runtime
access. Input source hashes and prompts are in the
[review provenance](interfaces-review-inputs.json). The rendered follow-up changes
line wrapping only; the repository TOML/Markdown remain the authoritative text.

No input says tests passed. Planned logical module owners do not create an
engine dependency in the independent carried scripts. B-11 remains conditional;
no download interface was invented. Exact schemas, platform behavior and scale
measurements remain ordinary design/verification work.

## Initial response — incomplete input review

### Input Inventory & Marker Verification

All **13** attached inputs (`adoption.md`, `assumptions.toml`, `cases.toml`, `external.toml`, `interfaces.toml`, `legacy-homehub.md`, `llrs.toml`, `native-contracts.md`, `sr-1.toml`..`sr-4.toml`, `stakeholder-needs.toml`, `store-contracts.md`, `trace-map.md`; note the prompt's "15 attachments" count vs. 13 actual files) were read in full with their `# END OF COMPLETE INPUT: <basename>` markers verified:
- **Interfaces (`interfaces.toml`, `native-contracts.md`, `legacy-homehub.md`):** 25 rows (`IF-001` preserved legacy OCI v1 agreement + 24 new `Drafted` rows `IF-002..IF-025`). Note: `legacy-homehub.md` line 17 has a display truncation (`...(line truncated to 2000 chars)`) before its end marker.
- **Low-Level Requirements (`llrs.toml`):** 40 `Drafted` rows (`LLR-151..LLR-190`).
- **Verification Cases (`cases.toml`):** 41 `Drafted` cases (`TC-261..TC-301`).
- **System Requirements (`sr-1.toml`..`sr-4.toml`):** **78** `Approved` SRs present across the four files (vs. 121 stated in the prompt).
- **Stakeholder Needs (`stakeholder-needs.toml`):** **36** `Approved` SNs + 3 `Drafted` stakeholders `STK-01..03` (vs. 49 stated in the prompt).
- **External Frame & Assumptions (`external.toml`, `assumptions.toml`):** 18 `Approved` entities (`EXT-01..18`), 23 `Approved` boundaries (`B-01..23`, `B-11` conditional/unrealized), 5 `Approved` relationships (`REL-01..05`), 22 `Approved` active assumptions (`DA-01..22`), and 2 `Approved` surrogates (`SUR-01..02`).

---

### High-Risk Findings

#### 1. Plaintext-Credential Configuration Refusal (`SR-129`) Is Unallocated to Configuration Admission (`IF-002` / `LLR-151`)
- **Affected IDs:** `SR-129`, `IF-002`, `IF-018`, `LLR-151`, `LLR-181`, `TC-261`, `TC-291`, `B-05`, `B-07`, `B-08`.
- **Causal Scenario:** `SR-129` requires that if a configuration contains readable notification secrets at `B-05`/`B-07`, the system refuses the configuration *before backup mutation* (`B-08`) without echoing the secret. However, `SR-129` is linked only to `LLR-181` (`native/notify`, `submit_result_notice`) and `IF-017`/`IF-018` (`B-09`/`B-21`). `IF-002` (`native/config`, `LLR-151`)—which owns whole-configuration admission before any set mutates a store (`LLR-153`)—does not trace to `SR-129`, and `Contract IF-002` omits plaintext-credential rejection from its refusal rules. Because `native/notify` (`LLR-181`) executes after a run completes or when notification is enabled for a run, a configuration carrying a plaintext secret when notifications are switched off for the run (`SR-015`), or during a non-notifying action, or prior to `submit_result_notice` after set backups have already mutated the store, will pass `IF-002` admission and mutate the backup before `LLR-181` ever inspects credentials—violating `SR-129`'s pre-mutation refusal guarantee and risking credential exposure in operational state.
- **Smallest Correction:** Add `SR-129` to `LLR-151.sr_refs` (and `TC-261.verifies`), and state in `Contract IF-002` (`native-contracts.md`) and `LLR-151` (`llrs.toml`) that configuration admission rejects readable notification secrets (accepting only opaque credential references) without echoing secret values before any set execution begins.

#### 2. `IF-008` Checkpoint Lifecycle Omits `native/store` (`IF-007`) and `native/platform` (`IF-014`) Consumers/Interfaces for `.prev` and Snapshot Publication
- **Affected IDs:** `IF-008`, `IF-006`, `IF-007`, `IF-014`, `B-02`, `LLR-165`, `LLR-166`.
- **Causal Scenario:** `Contract IF-008` (`native/state`) governs the ordering that protects current definitions and history across interruptions: staging, syncing, and publishing `MANIFEST.csv.prev` and `DIRECTORIES.csv.prev` without replacement before mutating `CurrentBackup`, publishing the prior dated snapshot to `BackupHistory/<date>`, atomically replacing manifest checkpoints, and deleting `.prev` only after finalization (`LLR-165`, `LLR-166`). In `interfaces.toml`, `IF-008` is a pure internal `call` (`consumers = ["native/capture", "native/cli"]`) with no `B-02` crossing, while `IF-006` (`State-record format`) only lists `native/state` as a *consumer* of the CSV codec, not the writer of `.prev` and dated state transitions on `EXT-05` (`B-02`). Furthermore, `LLR-163` (`publish_object` in `native/store`, `IF-007`) owns moving superseded objects only after `native/state` finalizes the latest state, yet `native/state` is not a consumer of `IF-007` and `native/store` is not a consumer of `IF-008`. Implementing `IF-007` and `IF-008` from the registry leaves the handoff between final manifest/sidecar publication and superseded-object relocation (`LLR-163`/`LLR-165`) without an owning interface link, which can allow superseded objects to be moved before final latest dependencies and `.prev` lifecycle steps complete.
- **Smallest Correction:** In `interfaces.toml`, add `native/store` to `IF-008.consumers` (or `native/state` to `IF-007.consumers`) so the post-finalization superseded-object move boundary is bound to `IF-008`'s checkpoint lifecycle, and record `interface_to_external = ["B-02"]` / `interface_from_external = ["B-02"]` (with `bridged_by = ["DA-01", "DA-15", "DA-16"]`) on `IF-008` or explicitly delegate `.prev`/snapshot file publication to `IF-006`/`IF-014`.

---

### Scope & Review Limits

- **No other high-risk contradictions found:** Previous-definition ordering (`.prev` staged/synced before current mutation, preserved across failed runs and kit refresh, deleted only after finalization, lone `.prev` treated as residue, explicit-only `.prev` recovery, file-row authority over conflicting supplemental directory/link sidecars), offline script independence, link capture/restore rules (`SR-137`, `SR-150..152`), and legacy `IF-001` vs. `IF-019` separation are internally consistent across `adoption.md`, `store-contracts.md`, `native-contracts.md`, `llrs.toml`, and `cases.toml`.
- **Advisory limits:** This static review does not verify N1/N2 open items (exact CLI/JSON schemas, format revision numbers, platform qualification, or `LLR-189` scale measurements), does not validate the truncated tail of `legacy-homehub.md` line 17, and is not gate approval or implementation evidence.

## Complete-input follow-up

### Input Confirmation & Inventory Verification

All **40** follow-up attachments (`inventory.json` plus the 39 rendered text files listed in `inventory.json.attachment_files`) were read in full with zero line truncations and every `END OF COMPLETE INPUT: <basename>` marker verified:
- `adoption-01.txt`, `assumptions-01..02.txt`, `cases-01..03.txt`, `definitions-01..02.txt`, `frame-01..02.txt`, `interfaces-01..02.txt`, `legacy-01.txt` (complete, untruncated line 13–83 contract body), `llrs-01..04.txt`, `map-01.txt`, `needs-01..05.txt`, `sr-01..14.txt`, `store-01..02.txt`, and `inventory.json`.
- **Corrected Inventory Counts (confirmed against rendered records and `inventory.json`):**
  - **Interfaces:** **25** (`IF-001` preserved legacy OCI v1 agreement + 24 `Drafted` native/recovery/delivery rows `IF-002..IF-025`).
  - **Low-Level Requirements:** **40** `Drafted` rows (`LLR-151..LLR-190`).
  - **Planned Verification Cases:** **41** `Drafted` cases (`TC-261..TC-301`).
  - **System Requirements:** **121** `Approved` SRs (`SR-001..SR-158` across `sr-01.txt`..`sr-14.txt`; my initial count of 78 was an error).
  - **Stakeholder Needs:** **49** `Approved` SNs (`SN-001..SN-055`) + **3** `Drafted` stakeholder records (`STK-01..STK-03`), totaling **52** records in `needs-01.txt`..`needs-05.txt` (my initial count of 36 was an error).
  - **Frame & Assumptions:** **46** `Approved` frame records (`EXT-01..18`, `B-01..23` with `B-11` conditional/unrealized, `REL-01..05`) and **24** `Approved` assumption/surrogate records (`DA-01..22`, `SUR-01..02`).

---

### Disposition of Prior Findings

1. **Prior Finding 1 (`SR-129` plaintext-credential refusal at configuration admission): Closed / Verified.**
   - `LLR-151` (`llrs-01.txt`) now includes `SR-129` in `sr_refs` and requires rejecting readable notification secrets and accepting only declared protected credential references without echoing values before any set/action mutation, even when notification is disabled or the requested action does not send a notice.
   - `Contract IF-002` (`definitions-01.txt`), `TC-261` (`cases-01.txt`), and `map-01.txt` (`IF-002` and `IF-022` derived SRs) are updated consistently.
2. **Prior Finding 2 (`IF-008` / `IF-007` / `IF-014` orchestration links): Closed / Verified.**
   - `IF-007` (`interfaces-01.txt`) adds `native/state` to `consumers`; `Contract IF-008` (`definitions-01.txt`) explicitly documents orchestration over `IF-006` record codecs, `IF-014` sync/rename primitives, and `IF-007` pool operations while preserving the `LLR-163`/`LLR-165` invariant that final latest dependencies are passed to superseded relocation only after latest publication; and `IF-014` (`interfaces-01.txt`, `definitions-01.txt`, `map-01.txt`) records `B-02` for the actual filesystem primitive surface while keeping `IF-008` an internal call. This accurately reflects the existing bounded-run ordering without redesign.

---

### New High-Risk Findings

**None.** No concrete high-risk contradictions, missing ownership allocations, or broken trace/contract links were found in the revised interface breakdown.

Specifically verified across the full 121-SR / 49-SN / 25-IF / 40-LLR / 41-TC set:
- **Previous-definition (`.prev`) ordering and recovery authority:** `IF-008`, `IF-006`, `IF-010`, `LLR-164..166`, `LLR-172`, `store-01.txt`, and `TC-274..276`/`TC-282` consistently enforce that `MANIFEST.csv.prev` and `DIRECTORIES.csv.prev` are staged, synced, and published without replacement before any current definition changes; never overwritten on unsuccessful runs or kit refresh (`LLR-186`, `IF-025`); deleted only after successful replacement and finalization; treated as benign residue if a lone `.prev` file remains; and used for recovery only when explicitly selected via `IF-010` without mixing current and previous sets.
- **Conflicting supplemental metadata vs. file recovery:** `IF-006`, `IF-011`, `IF-012`, `LLR-164`, `LLR-174`, `LLR-175`, and `TC-284` consistently ensure valid file-manifest rows outrank conflicting directory/link sidecar entries and recover through safe ordinary directories while reporting metadata damage (incomplete outcome), independent of timestamps or `.prev` presence.
- **In-root relative vs. external expanded links:** `IF-006`, `IF-011`, `IF-012`, `IF-013`, `IF-015`, `LLR-164`, `LLR-167`, `LLR-176`, `LLR-177`, and `TC-277`/`TC-286`/`TC-287` align with `SR-137` and `SR-150..152` (in-root links recorded root-relative without re-traversal and restored links-last relative to parent; external folder links expanded under active-ancestor cycle checks with deduplicated storage and expanded capacity accounting; file links captured/restored as bytes; protected system locations excluded).
- **Offline script independence & legacy separation:** `IF-004..007`, `IF-009..012`, `IF-015..016`, `LLR-172..179`, `LLR-184`, and `LLR-187` preserve standalone PowerShell/bash recovery without calling the native executable or network (`SR-007`, `SR-008`, `SR-031`, `SR-153`). `IF-001` (`legacy-01.txt`) preserves the verbatim single-set HomeHub OCI v1 contract separately from `Drafted` multi-set native `IF-019` (`LLR-183`).
- **Pre-mutation admission & maintenance boundaries:** Whole-configuration admission (`IF-002`, `LLR-151..152`), OS-lifetime lock ownership (`IF-014`, `LLR-155`), read-only inspection (`IF-024`, `LLR-168`, `SR-103`), protected post-cutoff prune rehoming (`IF-023`, `LLR-169..170`, `SR-045..046`, `SR-101..102`), verified repair (`IF-024`, `LLR-171`, `SR-109..110`), and kit refresh (`IF-025`, `LLR-186`, `SR-110`, `SR-117`) have complete, non-contradictory interface ownership and test mappings.

---

### Review Limits

- This static review is advisory and does not constitute owner gate approval, implementation verification, or test execution evidence (`IF-001..025`, `LLR-151..190`, and `TC-261..301` remain `Drafted`).
- Open N1/N2/N7 design items—freezing exact CLI flags, JSON event schemas, config/kit/sidecar revision numbers, golden CSV vectors, platform qualification, and `LLR-189` / `TC-299` scale and power-loss measurements—remain to be completed in their designated phases.
