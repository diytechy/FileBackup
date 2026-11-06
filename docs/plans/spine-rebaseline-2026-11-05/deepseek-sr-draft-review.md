# DeepSeek SR draft cross-review

Advisory review, not approval. Date: 2026-11-05. Provider/model:
`opencode-go/deepseek-v4.1-flash`, OpenCode 1.19.4, `--variant low`.
The first full 121-row SR draft was attached in four complete parts under
50 KB each, alongside four complete upstream documents. No code, LLRs or
tests were supplied. The pure plan agent had tools denied and a fresh temporary
working directory; global OpenCode instructions may still affect context.
The completed event stream reports `reason: stop`. The exact SR input SHA-256
was `c9827bfa824cce6e2525ad461706433cc898164329ea9d0380546fd9a4fb2d85`.
Raw inputs, prompt and event stream remain under ignored
`.artifacts/sr-generation/`. This review predates the author corrections below.

## Author dispositions

| Finding | Disposition and final change |
|---|---|
| 1 — link scope | **Clarified; rejected its approval claim.** SR-137 is a Drafted policy, not approved. SR-074 already excluded only traversal behind recorded links, but now explicitly names SR-150/151 and the distinct SR-137 proposal. Approved SN-001 does not itself mandate following every external folder link. |
| 2 — removal capacity | **Accepted narrowing, not a blanket ban on capacity checks.** SR-046 blocks only a documented allocation actually needed for that removal. Full capacity alone does not bar a deletion requiring no extra allocation. Later-window preservation still governs. |
| 3 — collision result | **Accepted.** SR-092/120/040/126 use incomplete recovery with a specific target-name-collision cause, without falsely asserting missing stored bytes. No new top-level result class is required by SN-026. |
| 4 — link metadata outcome | **Accepted.** SR-152 explicitly proposes complete byte recovery with per-link unsupported-target/privilege warnings, aligned with SR-122. Lost/malformed required recorded metadata remains incomplete. This policy remains for owner review. |
| 5 — compatibility title | **Accepted.** SR-084's title now states designated-path scope, matching its body. |
| 6 — premise attribution | **Accepted.** Removed DA-08 from SR-063/138 and DA-03/08 from SR-154. Path-overlap and root-uniqueness validation are unconditional product duties, not conditional on a restore-name premise or prior validation. |
| 7 — state identity | **Accepted.** SR-005 distinguishes completion-date display from a distinct selectable identity; equal dates and clock rollback are explicitly covered. |
| 8 — retirement path | **Clarified, with a narrower interpretation than the review suggests.** SR-036 now specifies removing the source's set entry from configuration: future runs stop capturing it and leave its store intact. SN-038 does not require publishing an empty replacement for a previously populated source; the review's proposed “legitimately emptied source” bypass is not added. |

The author also corrected captured-state versus whole-tree language in SR-010,
whole-configuration admission versus per-set failures in SR-014, timestamp
precision in SR-066, nonmutation of store-side logs/views in SR-103, delivery
crossing attribution and contradictory Coincident/DA declarations. These are
post-review edits, not assertions that DeepSeek approved or rechecked them.

## Validation

Final validation: strict trace integrity passed with **zero integrity findings**;
49 SN, 121 SR, 87 LLR and 240 TC rows parse. Documentation checks passed for
109 documents and 301 internal links, with zero broken links. Whitespace checks
passed. All SRs remain Drafted; approved upstream rows, the approval baseline,
legacy LLR/TC registries and runtime code are unchanged by SR authoring.

The report still has **131 orphan findings** (119 before this SR pass), one
inherited interface finding and four acceptance-wording advisories. Five legacy
LLRs directly reference newly retired SRs: LLR-035/038/046/049/087. Those links
are intentionally exposed for the next reconciliation, not reassigned merely
to make the report green. The six added SRs have no implementation evidence yet.
This is not a passing full-spine or implementation-conformance claim. Product
tests were not rerun for documentation-only work.

## Reviewer response (verbatim wording)

Trailing whitespace and line endings are normalized. The response's references
to an “approved” SR policy are the reviewer's wording, not an approval act.

## Input confirmation

Read all eight attachments in full. End markers present:

- `assumptions.toml` end marker at 240 → **DA‑01…DA‑22 (22) + SUR‑01/SUR‑02 (2)**
- `external.toml` end marker at 330 → **B‑01…B‑23 (23 active); B‑24 inactive/none**
- `hats.toml` end marker at 70 → **9 hats**
- `stakeholder-needs.toml` end marker at 495 → **SN‑001…SN‑055 with gaps, 49 Approved**
- `sr-part-1/2/3/4.toml` end markers at 517/510/535/255 → **121 Drafted SRs**

Counts reconcile. No edits, approval, or tool/repository access. The retired obligations are absent as promises; residual mentions in SR‑039/082/094 correctly reject completeness witnesses, source-side caches, and cross-configuration fencing. The retained numeric parameters and link/metadata policies are proposal material, not defects by themselves.

## Material issues, ranked

**1. SR‑074 contradicts the approved link-capture policy of SR‑137.**
SR‑074 acceptance says the scope excludes “traversal behind links recorded rather than followed.” SR‑137 requires following external folder links and junctions, SR‑150 records only in-tree/ancestor links, and SR‑151 records only system-location links. As written, SR‑074 can be read as excluding the external-folder data SN‑001 requires. Smallest correction: delete that phrase or limit it to links governed by SR‑150/SR‑151; SR‑137 remains the external-follow rule.

**2. SR‑046 makes a capacity shortfall a blocker to history removal.**
SR‑046 rationale/acceptance require “a known capacity shortfall” to prevent destructive removal. Removal is the operation SN‑029 provides specifically to limit storage use; a full store is when the owner most needs it. This is a lost/contradicted obligation, not just a policy. Smallest correction: remove capacity shortfall from SR‑046’s blockers unless a specific temporary-space need is documented, in which case scope it to that need.

**3. SR‑092 mislabels a name collision as “content-missing.”**
SN‑026/SR‑040 define content-incomplete versus invalid request/record versus host/tool failure. A collision means content exists but cannot be represented on the target. SR‑120’s causes (`missing, recovery-failed, expand-failed, content-mismatch, mixed`) have no collision cause, so automation may report missing content when none is missing. Smallest correction: add one documented name-collision/target-representation outcome and use it in SR‑040, SR‑092, SR‑120 and SR‑126.

**4. SR‑152 invokes an undefined “documented metadata-limitation outcome,” while SR‑122 sets a different rule.**
SR‑122 says unsupported folder attributes are reported but an otherwise intact restore remains complete. SR‑152 says unsupported link type/target/privilege uses “the documented metadata-limitation outcome,” which no SR defines. This is an SR defect in outcome definition, not merely the open metadata policy. Smallest correction: make SR‑152 apply SR‑122’s rule (report per link, keep complete) or explicitly designate a distinct link-metadata outcome in SR‑040.

**5. SR‑084’s title asserts the unlimited compatibility its own body disclaims.**
Title: “The system never writes what a kit already in the backup cannot read.” Requirement/rationale correctly limit this to a “designated compatibility path” and say universal old-kit readability is not promised; SR‑114/115/116 confirm no older version is designated. The title is an unsafe overclaim. Smallest correction: retitle to the designated-path scope already stated in the requirement.

**6. Trace metadata conflicts with revised prose.**
(a) SR‑063 and SR‑138 cite `DA-08`, whose `effect_at` is B‑16 (restore-target naming), while both rows govern B‑05/B‑07/B‑08 configuration/source/store path overlap. (b) SR‑154 cites `DA-03`, but DA‑03 `holds_when` says “Unique-root validation and refusal of duplicate roots are independent product admission requirements, not environmental premises.” Smallest correction: remove DA‑08 from SR‑063/SR‑138 and DA‑03 from SR‑154; those rows stand on SN‑027/SN‑039 and B‑04/B‑05.

**7. SR‑005 treats the completion date as the state identifier, conflicting with DA‑16.**
DA‑16 says displayed date order alone does not establish state identity, capture order, or ownership. SR‑005 says the previous state is “identified by the date that state was completed,” while only its acceptance adds distinct same-second identifiers. Since SN‑006 lets the restorer choose by date, this is material to selection. Smallest correction: state that the date is the display/selection label and the state’s identity is a distinct identifier exposed to the restorer.

**8. SR‑036 promises explicit source retirement without defining it.**
SR‑036 acceptance says “intentional retirement is explicit configuration action,” but no SR or interface row defines that action or its settings. SN‑038 requires retirement to be an explicit owner action rather than inferred emptiness. This is a lost operational path: a legitimately emptied source can never be recorded. Smallest correction: add a requirement/interface row for the explicit retirement action (configuration key and effect) or mark it explicitly as downstream design and remove the unsupported promise from SR‑036.

## Areas checked and not flagged

Bounded per-file publication is coherent: SR‑001 governs completed runs; SR‑082 permits checkpointed latest progress referring only to completed stored content; SR‑075/SR‑017 distinguish continuation from blockers. Later-window retention is coherent in SR‑045/046/101/102. Whole-store verification covers invalidated older history in SR‑049 and remains nonmutating under SR‑103. Source nonmutation is protected by SR‑093/094 and DA‑21. One-configuration uniqueness/coordination is substantively sound in SR‑154/085/086/107 (only the DA‑03 trace is wrong). DA‑10 diagnostics are handled by SR‑008/118/019/132. No unlimited compatibility promise survives except the SR‑084 title. Native engine plus independent offline recovery is covered by SR‑153/156/031/008.

The 3-attempt/60-second retry, 256 KiB/10% compression, 120-second progress, 2 TiB/1M/365/4 GiB/8h/30min performance, and external-link-following choices are open proposed policies; they need owner review, not automatic deletion, and are not counted as SR defects above.
