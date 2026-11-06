# Interface breakdown and scoped carrier adoption

Historical adoption record for `a184d9a`. The subsequent
[legacy cleanup](legacy-cleanup.md) removes IF-001, its redundant copies and the
imported LLR/TC rows from the active baseline. Preservation statements and check
counts below describe the adoption commit, not the current registry inventory.

Draft for owner review. This completes the initial formal interface allocation
requested after the native design breakdown. It does not approve interfaces,
implement Rust code, change accepted requirements, enable hooks or close a gate.

Start at the [interface index](../../interfaces.md), then read the
[contract definitions](../../interfaces/native-contracts.md) and
[IF → LLR → SR → TC map](../../interfaces/trace-map.md). The machine registry is
[interfaces.toml](../../requirements/interfaces.toml).

## What changed

- **Previous definitions:** the draft now states the ordering directly: complete
  initial preservation before changing current definitions, and delete `.prev`
  only after successful replacement/finalization. Interruption during copying
  leaves old current definitions available; interruption during deletion leaves
  new current definitions available. Lone-copy residue does not fail current
  recovery or trigger an automatic fallback. Explicit previous selection still
  diagnoses any unavailable required record.
- **Formal contracts:** IF-002..025 allocate configuration/actions, outcome and
  reporting, state/content formats, checkpoint publication, recovery, source and
  host adapters, tools/credentials/notifications, container/view/delivery, and
  explicit maintenance operations. These are observable surfaces; they are not
  one interface per requirement or per internal function.
- **Trace:** `verified_by` names the responsible LLRs. Their `sr_refs` provide
  the SR tie-back; their existing Drafted cases also name each IF in `verifies`.
  The rendered map derives its SR list from that chain. No accepted SR was edited
  to duplicate an interface list. A referenced case is still only a planned case.
- **Admission ownership:** SR-129 now also reaches configuration admission through
  LLR-151/TC-261 and IF-002. Readable notification secrets refuse before any action
  can mutate the store, including when notifications are disabled. Existing
  notification-side credential isolation remains in place.
- **Legacy preservation:** IF-001's contract text and original CSV are preserved
  exactly. Its historical Implemented/Experimental labels remain in the archive;
  the new row is Drafted pending rebaseline reconciliation. This changes the
  carrier, not HomeHub's deployed agreement. Its old LLR pointers are explicitly
  historical, not proof against rebaselined requirements. Native IF-019 is
  separate, so multi-set native behavior does not rewrite OCI v1 by implication.

## Contract ownership and boundaries

Each new owner is a planned logical module already named by an LLR. The contract
body has one design home until implementation exists. When the module is written,
move the body/binding with it and leave a navigation pointer; do not maintain two
normative copies. The PowerShell/bash scripts independently implement shared
format and result protocols: a `native/...` owner names design responsibility,
not a runtime call into the native executable during recovery.

Every approved operation/delivery boundary has at least one drafted realizing
interface except conditional B-11. Automatic tool acquisition is not offered in
the initial design; IF-016 and IF-022 provide tool admission and local guidance.
No fake download interface was added to make coverage appear complete. Actual
boundary direction and applicable assumptions are recorded in the registry.
Internal publication/maintenance calls have no invented external tie-back.
IF-008 orchestrates IF-006 codecs, IF-014 filesystem primitives and IF-007 pool
operations; `native/state` is an explicit consumer of the pool contract. B-02 is
attached to the filesystem primitive surface, not to every internal caller.

The registry follows the pinned template's owner/requestor-or-consumer/channel
shape. The retired `Contract` CSV cell moves into its single definition body;
the legacy CSV lives under this plan's `legacy` directory, not beside the live
carrier. This scoped adoption updates process §8 and the current index only;
it does not adopt the rest of the changing template or activate hooks.

## Remaining design work

The contracts state observable inputs, outcomes, ordering and refusals. N1 still
pins exact CLI/event schemas, metadata/kit revision admission, state identity and
ordering, and shared serialization fixtures. Platform qualification and measured
time/memory evidence remain N2/N7 work, with an early recovery feasibility probe.
These ordinary design tasks are not represented as completed interface evidence.

Legacy code/test reconciliation and eventual owner approval of this Drafted
breakdown remain open. Full trace/schema readiness must not be inferred from
zero ID/reference-integrity findings.

## Review and checks

The [Gemini Argon review](gemini-interfaces-review.md) used OpenCode Go on low.
Its complete-input follow-up found no remaining high-risk issues after the
configuration-admission allocation fix and explicit publication dependency links.
The initial response had count/truncation problems; all inputs were resupplied in
smaller short-line files before accepting the review as complete.

Scope checks preserve all four approved parent registries, every legacy LLR/TC
row and existing ID, and the exact original IF-001 contract. Each new interface
has a matching LLR owner, a definition body, derived SR parents, direct planned
TC links and directionally valid boundary references. No execution evidence or
approval is fabricated. The trace map is reproducible:

```powershell
py -3.11 scripts/gen_interface_map.py
py -3.11 scripts/gen_interface_map.py --check
```

Strict integrity reports zero findings and the interface finding count falls
from one to zero. Full strict/schema remains red with 131 orphan findings,
274 schema findings, 18 requirement-form findings and four acceptance-criteria
advisories. Pending code/test evidence is still visible. Conditional B-11 and
external endpoints also produce expected advisory coverage notes. Document links
and whitespace are checked separately; no product runtime suite is claimed for
this documentation and trace-rendering change.
