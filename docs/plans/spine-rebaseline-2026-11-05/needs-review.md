# Stakeholder-needs review

> **Review snapshot:** [Owner review 01](owner-review-01.md) supersedes the retention, reporting, coordination, compatibility and absolute-verification proposals affected by SN-029/046/039/041/033 and the consistency edit to SN-034. The analysis below records the earlier draft, not the current ruling.

Review basis: the 48 needs at `92268f9`, the project's vision and operating
frame, the implementation audit, and the native-engine direction. A separate
read-only reviewer considered every need. This is independent needs analysis,
not a blind derivation, approval act or new runtime evidence.

The coordinator's amendments are in the live registry, still Drafted.
“Keep” means the outcome remains wanted; it does not mean the code satisfies it.
“Decision” preserves a question for adjudication instead of removing an unmet
promise because the current implementation lacks it.

| Need | Disposition | Reason / follow-through |
|---|---|---|
| SN-001 | Amend; decision | Whole-tree coverage and explicit omissions remain; remove source-cache assumptions and move link-policy details into the explicit N4 decision. |
| SN-002 | Keep | Shared content once per independent store. |
| SN-003 | Amend | Compression setting governs new content; reuse preserves the existing form. Threshold and fallback mechanisms belong below SN. |
| SN-004 | Keep | Every changed completed state remains selectable; same-second identity loss is a defect candidate, not permission to drop history. |
| SN-005 | Amend | The complete store carries shared data; an isolated snapshot is not the portable recovery unit. |
| SN-006 | Keep | Historical selection and exact chosen-state authority. |
| SN-007 | Keep | Re-read policy; calendar/elapsed semantics belong in decomposition. |
| SN-008 | Keep | Browse/search without recovery remains distinct from space analysis. |
| SN-009 | Keep | Failure of one configured set does not suppress others. |
| SN-010 | Keep | Optional notification cannot change the backup result. |
| SN-011 | Keep | No unattended prompts. |
| SN-012 | Keep | Guidance and configuration setup cover declared supported hosts. |
| SN-013 | Amend; N1 | Recoverable checkpoints and prior-state preservation; separate process interruption from storage power-loss premises. |
| SN-015 | Keep | Required dependencies admitted before relevant work; optional degradation visible. |
| SN-019 | Amend; N2 | Safe space exhaustion instead of an unachievable promise that capacity cannot change; stronger restore admission remains a choice. |
| SN-021 | Clarify | No new content state/history on an unchanged run; logs and run dates can advance. |
| SN-022 | Amend | Independent PowerShell/bash recovery on all three OS families, without a backup executable or toolchain. |
| SN-023 | Amend | Include macOS writers and continuation, bounded by a declared support matrix. |
| SN-024 | Keep | Unprivileged container operation with a read-only source remains useful. |
| SN-025 | Amend; N3 | Detectable structural damage and verified file recovery; no false authentication claim for a valid substituted/truncated record. |
| SN-026 | Amend | Shared documented recovery outcome classes, not a code for every diagnostic detail. |
| SN-027 | Keep | Invalid configuration refused before protected backup mutation. |
| SN-029 | Keep | Prune preserves all remaining states, including after interruption. |
| SN-030 | Keep | Requested full integrity check remains wanted; shallow checks must disclose scope. |
| SN-031 | Keep | Restore missing supply from readable source; decomposition must exercise unchanged source size/time. |
| SN-032 | Amend; N4 | Windows/Linux/macOS naming, case and normalization collisions; no silent merge or overwrite. |
| SN-033 | Keep | Verify every successfully recovered file's content. |
| SN-034 | Keep | Protect every live dependency on shared content. |
| SN-035 | Keep | Interactive recovery remains usable, scripted recovery remains noninteractive. |
| SN-036 | Decision N4/N8 | Link fidelity and metadata expectations remain requested, despite implementation gaps. |
| SN-037 | Amend | Read-only source sufficient; no source-cache exception; host access-time effects distinguished. |
| SN-038 | Amend | Empty/missing previously populated source cannot publish mass deletion; no retired override switch. |
| SN-039 | Amend; N6 | Exclusive mutations under declared coordination assumptions; distinguish reader access from isolation and holder diagnostics. |
| SN-040 | Amend; N5 | Explicitly supported continuation window and nonmutating refusal of retired layouts. |
| SN-041 | Clarify; N5 | Supported kit/store combinations, preserving excluded stores' original recovery route. |
| SN-042 | Keep | Recovery containment includes links and protected store locations. |
| SN-043 | Decision N7 | Retain scale outcome; corpus, host and operation-specific budgets still needed. |
| SN-044 | Keep | Semantic changes and bounded visible progress remain unmet where the implementation is narrower. |
| SN-045 | Keep | Machine-readable operation outcomes and findings. |
| SN-046 | Clarify | Account for stored-content bytes, not an exact change in unrelated filesystem free space. |
| SN-047 | Decision N8 | Closed supported repair classes needed; preserve every previously recoverable state. |
| SN-048 | Keep | Setting changes do not rewrite or strand existing content. |
| SN-049 | Keep | Credentials protected across native host implementations. |
| SN-050 | Keep | Versioned configuration contract and valid shipped examples. |
| SN-051 | Keep | Optional space/media insight is not satisfied merely by a directory browse view. |
| SN-052 | Keep | Bounded retry and prior-copy preservation; avoid an invented global 60-second budget. |
| SN-053 | Keep | Salvage unaffected files and report incomplete recovery precisely. |
| SN-054 | Amend | Include native bundles, kits and containers in redistribution obligations. |
| SN-055 | New proposal | Native backup and maintenance without an installed engine language runtime/toolchain. Separate from interchangeability and recovery. |

## Scope findings retained for subsequent decomposition

- Whole-store portability is a user-visible delivery contract, not an internal
  object lookup detail.
- Native distribution changes the provisioning and licensing surface; it does
  not erase the container, notification or independent recovery needs.
- Filesystem support must be stated for actual combinations. An OS name alone
  establishes neither rename durability nor cross-process lock behavior.
- Link following/recreation, metadata completeness, stronger manifest assurance,
  stronger restore capacity admission and holder identification are explicit
  decisions. Their legacy promises remain in git at `92268f9` and the review
  records; proposed clarification must not be mistaken for owner approval.
- A supported corruption check and a supported repair action have different
  scopes. Reporting a defect does not prove the tool can repair it safely.
- General hooks staying disabled is a working constraint, not a new end-user
  need. No process-only requirement was added to the product spine.

## Perspective reach

The always-applicable integrity and security lenses remain. Shared-content,
format-compatibility, filesystem, unattended-operation, performance and legal
questions remain material. CROSS-PLATFORM now also matches `backup-host`;
SN-023 and SN-055 cannot be derived under a restore-only lens.

The hats audit is a reach matrix, not an adequacy verdict. Subsequent requirement
reviews must record each relevant question's finding or justified no-finding,
especially where a need's tags currently understate a filesystem or scale issue.
