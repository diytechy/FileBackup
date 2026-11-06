# Owner correction: previous definitions and folder/link changes

2026-11-05. Design-only amendment to the [initial breakdown](review.md), following
the owner's review of Claude's feedback. Accepted SN/SR/frame/assumption text and
approval snapshots remain unchanged. Changed LLRs/cases stay Drafted. No runtime
code is changed by this record.

## Decisions applied

- Replace the blanket incomplete-run marker with pre-run `MANIFEST.csv.prev` and
  `DIRECTORIES.csv.prev` copies. Preserve existing copies unchanged across later
  interrupted/incomplete runs; delete only on successful backup completion.
- Treat current records as last-known definitions. Previous-copy presence does
  not suppress valid directories/links or automatically make recovery incomplete.
  Actual missing/malformed/conflicting required metadata retains its diagnostic.
- Report partial previous sets without mixing them with newer metadata. Initial
  copy failure stops before latest mutation; existing partial residue remains
  inspectable and is cleared only after a later successful backup. Dated snapshots
  remain the normal history mechanism; previous copies contain definitions only.
- Include empty-folder, directory-attribute and link-only changes in semantic
  state comparison and preceding-state retention. This is the concrete current
  implementation gap confirmed in `Test-StateChanged`.
- Keep link records in the directory sidecar for now. Supported in-root folder
  links restore relative to their parent; external folder links are captured under
  their alias and restored as ordinary duplicate output trees. Content addressing
  still avoids duplicate stored bytes. Internal links unavailable on the target
  report a capability limitation; they do not silently become copied trees.

## Disposition of supplied Claude feedback

| Topic | Assessment and scoped response |
|---|---|
| Restore time and memory | Measurements quoted by the reviewer were not independently reproduced. Topology, route and verification I/O must be measured. Do an early feasibility probe during N1/N2, before broad porting; N7 remains full acceptance evidence. No time budget was changed or infeasibility declared. |
| Format/completion | Exact format admission is ordinary N1 contract work. New mandatory directory metadata uses a header-only empty record; current optional-sidecar behavior is explicitly distinguished. Rejected the assumption that interrupted enumeration alone invalidates last-known definitions, and removed the marker mechanism. |
| State identity/order | Accepted SR-005 already requires distinct identities through equal dates and rollback. Concrete identity/order belongs in N1 before implementation; no new SR or forced sequence-number design added here. |
| Folder/link-only changes | Confirmed current comparison uses file rows only. Added explicit semantic comparison and planned regression cases in LLR-158/165 and TC-268/275. |
| Link traversal/recovery | Clarified this is new behavior within existing architecture, owned by N3 capture and N5 recovery. Added explicit file-link capture, bounded unreachable-prefix preservation, link-only parents, unavailable target handling and junction-to-relative-symlink disclosure to existing LLRs/cases. No separate link format or broader fidelity promise introduced. |

The prior Gemini response evaluated a different, marker-based proposal. Its
closed-finding language remains historical and cannot serve as evidence for this
replacement. Any new external review is advisory against these decisions, not
permission to strengthen the owner's chosen scope.

The focused [Gemini Argon review](gemini-prev-review.md) is now complete. Its
follow-up found no remaining high-risk issues after a narrow clarification that
conflicting supplemental metadata does not discard independent valid file rows.
Its second candidate assumed unsupported history-loss behavior and was withdrawn.
No marker or automatic `.prev` baseline was reintroduced.

## Verification scope

LLR-158, 164..166, 172, 174..177 and 186 and their existing cases carry the
changes; no IDs are retired or added. The interruption cases cover repeated
failed runs, copy/delete boundaries, no overwriting, explicit previous selection
and usable current records. Folder/link cases cover metadata-only changes,
relative reconstruction and external alias expansion. These are planned cases,
not executed runtime evidence. Integrity, document links and unchanged-parent/
legacy-row checks validate this documentation amendment only.
