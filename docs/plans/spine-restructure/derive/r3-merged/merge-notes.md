# Round 3 merge notes: the design tier

The merged tier built from the two blind derivations (`r3-astra/`, `r3-opus/`), their alignment (`r3-alignment.md`, `r3-alignment-map.json`) and the coordinator's calls (`r3-dispositions.md`: K01 to K38, P-01 to P-07 at their defaults). Where a call and the alignment differ, the call governs. Every row is Drafted.

## How the files were built

- **The base.** Most clusters are "take O" or a union whose richer side is Opus, so each merged row starts from Opus's row under the alignment's id, parent and SR set, and the builder's edits are applied on top. `_merge_llr.py` and `_merge_if.py` hold every edit as an anchored replacement (each asserts its anchor exists exactly once) and regenerate the two TOML files; `_gen_gaps.py` writes `design-gaps.md` from the alignment's gap list plus the calls. Re-running them reproduces the tier. Curly quotes are normalised to ASCII; long cells are TOML multi-line strings.
- **Ids.** The alignment's crosswalk throughout: 73 legacy ids kept, Opus's new ids LLR-095 to LLR-149, LLR-150 for the Astra-only row, LLR-145 left unused (folded). Interfaces IF-002 to IF-044 keep Opus's ids; IF-045 and IF-046 are the two Astra-sourced forms. No new id beyond the alignment's was minted.
- **Components.** Opus's tree as the alignment proposed it (K38), with four note edits: provisioning fetches without a question (K07); the check, repair and kit-refresh component refreshes from the installed program and records the original revision (K23, K14); entry restoration owns the content search (IF-045).

## Choices made per cluster

LLR clusters (alignment section 4 numbering in brackets):

- **LLR-014 [2]** union: Astra's "every set resolved and validated before admission, for every action" added (it is also the M40 build work).
- **LLR-042 [6]**: K27 made the row's "creating and changing nothing" read "creating nothing and changing no location; an existing global record only gains the refusal entry", so it agrees with LLR-095.
- **LLR-063 [8]**: dropped Opus's sentence on optional settings not raising the version; that is LLR-098's decision and was a sibling overlap.
- **LLR-103 [14]** K35: the listing location's same-volume rule is kept, with its reason in the rationale (each view entry is a relative link to its stored object; a relative link cannot cross volumes on Windows).
- **LLR-037 [16]** carries SR-019 and SR-081, per the alignment. **LLR-105 [18]** carries SR-132 only (Opus also had SR-019, which LLR-020 carries). **LLR-020 [17]** now constrains the new IF-046 (the backup runtime and tool floor) instead of the archive tool.
- **LLR-109 [28]** K18: "the run's bounded wait" became 60 seconds per resolution or enumeration request.
- **LLR-078 [26]**: Astra's clause, an unknown volume-root status defaults to capture. The system folder names went to IF-028's form, so the LLR names them by role.
- **LLR-067 [30], LLR-036 [34], LLR-002 [96], LLR-022 [97], LLR-071 [110], LLR-141 [113], LLR-066 [118]**: Astra's distinct clauses added (the digest read retried; an unreadable source root is not an empty source; a failed read gives no digest; the source-root rule; the portable byte-count fallback and the empty-scratch guard; re-checking containment before each write and never writing through a link met since admission; the recorded offset honoured). Astra's "report precision loss" in LLR-066 was not added: no SR asks for it.
- **LLR-113 [36]** K13: paths are compared with both separators taken as one.
- **LLR-011 [37]** K01, P-01: rewritten to elapsed periods (24 hours, 7 days, one calendar month, one calendar year) since the start of the last completed full re-read; a never schedule never re-reads, history or not; a re-read that met an unreadable entry does not count. The schedule letters stay in IF-004 as names only.
- **LLR-005 [51] and LLR-028 [41]**: the saved-state naming moved from the parent to its child LLR-028, so the parent no longer paraphrases the child; LLR-005 gained K37 (a folder-only or link-only change counts) and "visible only once record, evidence and kit are complete". LLR-028 gained the run-state record's whole replacement (moved out of IF-030's form).
- **LLR-003 [42]**: Astra's "a blank or absent copy is demand, not supply".
- **LLR-117 [44]** K33: rewritten from Opus's clear-then-write to Astra's private temporary, content-key check and publish without replacing a claimed object; new gap M59.
- **LLR-004 [47]** K30: the explicit list, checked against the shipped list in the restore-safe library (the same 37 extensions, in its order). Opus's "filesystem containers excluded" kept.
- **LLR-116 [48]**: the codec named (Brotli at its fastest quality level), as the alignment asked.
- **LLR-052 [49]** K08, K09, K10: rewritten. The plan reads and writes nothing and runs before any root, claim, record, staging area or log exists; it is re-checked under the claim; Astra's declared allowance values; an unmeasurable volume is not refused and the record says the check was not made (P-04). Astra's "refuse unknown capacity" was overruled by K08.
- **LLR-135 [50]**: the allocation unit added (needed by K09's rounding).
- **LLR-150 [54]** (Astra-only, orphan ii): written fresh from Astra's clause in its LLR-115/LLR-041 and gap M51; it constrains IF-013.
- **LLR-087 [56]** K19: Opus's "no flush" sentence replaced by a flush before the rename; **LLR-118 [57]** K20 keeps Opus's write order and adds the flush per temporary.
- **LLR-007 [59]**: "complete before the state is visible".
- **LLR-026 [63]**: Astra's safeguard, a copy deleted only once the kept copy is present and every rewritten dependent state resolves.
- **LLR-121 [64]** K13, P-06: the coordinator's design call written in (readers take both separators; change detection normalises; no spurious saved state; the record turns to the backslash at the first real change). Opus's rationale clause "translating at read time lost" was replaced, since readers now do accept both.
- **LLR-080 [74]** K24: Astra's sample formula, in words.
- **LLR-123 [71]** K22: rewritten to the middle course (no claim, no reader artifact, re-resolve by content key, re-read a record whose evidence changed, up to three times). Opus's premise ("published states never change in place") left the rationale as the losing alternative. Carries SR-106 and SR-103.
- **LLR-125 [76]** K21: rewritten from five fixed boundaries to a check before every destructive step, with new objects at fresh names exempt.
- **LLR-046 [78]**: an unmeasurable destination volume is now "not checked and the record says so", consistent with K08.
- **LLR-127 [80]**: Astra's resume-own-marker clause (gap M49), using the removal marker's content from IF-033.
- **LLR-149 [84]**: Astra's numbers (1 GiB for the index and counters, one archive job at a time, 4 GiB in all); the spill mechanism dropped, with that as the losing alternative.
- **LLR-130 [88] and LLR-131 [89]** K23, K14: LLR-131 states what a refresh does (source is the installed program, never deletes, records each state's original kit revision once, changes nothing else); LLR-130 states the interruption safety (each file replaced whole, the revision-carrying files last). The write order lives in LLR-130 only.
- **LLR-025 [98]**: both sides' clauses kept (a header-only record is empty; a missing record is empty only with no earlier backup, otherwise damage), plus either line ending and either separator in older records (K13).
- **LLR-136 [101]**: Astra's clause, the archive-tool need decided from the items' opening bytes, not the recorded form alone. Carries SR-145 only (SR-029 is LLR-029's).
- **LLR-138 [106]** K14: rewritten. Age for completeness evidence is the original kit revision a refresh recorded, else the kit's own; for folder and link records, the evidence version and its row counts. Carries SR-116 and SR-146.
- **LLR-139 [107]** K32: a present tool failing its admission self-test refuses with 2; **LLR-040 [122]** lists it among the 2 causes. New gap M58.
- **LLR-023 [108]** K08, K09: Astra's allowance values (twice the largest expanded item for scratch), no refusal of an unmeasurable volume.
- **LLR-010 [111]**: took IF-023's "nothing else is written under the target" (moved out of the form).
- **LLR-050 [115]**: now constrains IF-045, the typed answer set.
- **LLR-077 [119]** K28: child of LLR-056, reworded as the call states.
- **LLR-073 [123], fold [124]**: Opus's LLR-145 folded in for its observable part (an absent, failed or cancelled choice gives no target and never falls back to a typed prompt); its threading and quoting rules go to the test tier.
- **LLR-074 [125]** K34, P-07: the support boundary written in (double-click holds for a kit opened from the backup's own volume; the zip case gets the manual's remedy), plus Astra's "starts from its own folder" and the hold on the error trap (M53).
- **LLR-147 [127]** K26: "its non-persistent scratch mount".
- **LLR-048 [5]** K04, K25: no dry run in the LLR; the exact truthy set lives in IF-038's form.

Interfaces:

- **IF-002** K04, K05: lists -WhatIf (with Prune only), -Deep (no meaning), and the two accepted spellings today's entry point takes (-IncludeSnapshots set false for the latest-only check; -VerifyStorage for the check action), so no existing caller is refused. -BackupTime stays out (a test seam).
- **IF-004** K02, K03: ConfigVersion stays 2; SpaceView boolean; the schedule letters' timing removed (behaviour, now LLR-011 only).
- **IF-009**: the refusal tokens are frozen as form; the rationale says a new refusal class takes a token naming no requirement.
- **IF-013, IF-016, IF-019, IF-022, IF-023, IF-028, IF-030, IF-031, IF-032, IF-033, IF-044**: every behaviour clause the alignment flagged moved out to the LLR it names (dating, "never written", the electing extension, the launcher's one line, nothing before admission, no other file, read-only opens, publication by rename, the mount-table rule, never written or deleted, exclusive create and liveness, the forced fail-closed listing).
- **IF-014** union: Astra's canonical bytes (LF, a byte-order mark read but never written, the header-only empty record, the Length range, Duplicate may be empty), plus the note that Linux-written records of earlier versions use '/'.
- **IF-019** K14: a new artifact, KIT-ORIGIN.txt (`OriginalKitRevision=<integer>`), present only in a refreshed state. The name and grammar are the builder's design; the coordinator ruled the mechanism, not the name.
- **IF-025, IF-031** union: allocation unit, name comparison and normalisation, link and attribute support.
- **IF-033**: PRUNE.inprogress holds the saved-state name as text (confirmed in code).
- **IF-034**: owner moved to CMP-016 (the text form is FileBackup's); the package identity is now only in IF-037. It keeps its B-10 crossing.
- **IF-038** K25, K04: Astra's exact truthy set (matches the shipped entry script); FILEBACKUP_DRY_RUN kept (P-02 default (c)).
- **IF-045** (from Astra IF-018): requestor and owner are both CMP-019, since today's search lives in the restorer and only entry restoration calls it. The pointer rules make a call inside one component optional; it is kept because the alignment adopted it and both routes must give the same answer set. Reviewers may retire it on that rule.
- **IF-046** (from Astra IF-025, the backup-side part): the backup runtime and tool floor at B-10, constrained by LLR-020.

## What could not be applied as written, and why

- **IF-027 lost its only constraining row through the fold.** Opus's LLR-145 was the one row constraining the folder choice dialog; folding it into LLR-073 (which constrains IF-026) left IF-027 unconstrained. Rather than un-fold or mint a row, the merge lists SR-073 -> IF-027 under "SR constrains" in design-gaps.md (the dialog sits on the B-19 boundary, and SR-073's "asks for the target folder" is the behaviour across it). If the reviewers prefer an LLR, LLR-073's `constrains` could move to IF-027, leaving IF-026 to SR-073.
- **BytesReclaimed may be negative (Astra IF-028).** Not added: the code computes it as the folder's physical bytes less the bytes re-homed, and re-homed content is a part of what the folder holds, so the plan does not yield a negative value.
- **K09's allowance values** are applied as the alignment and call say, but not yet checked against the harvested test edges; that is round 4's.
- **K26** depends on the reviewers reading SR-130's "working-state locations" as admitting a non-persistent scratch mount; M57 stays a conditional gap.
- **The release that introduced completeness evidence** (and the folder and link records) is not in the design; K14 assigns reading it from history to the build (M60).
- **The repair-rename half of Opus's G-36** (whether each repair rename publishes by temporary and rename) is still unconfirmed in code; it stays in M32.
- **Validator warnings.** All ten remaining warnings are on-disk names in interface `data` (FileBackupState.json, RECONSTRUCT.cmd and .bat, RECONSTRUCT.paths.json, FileBackup.json, $RECYCLE.BIN), the agreed form. No LLR or component text raises a warning. The one other warning seen while building (`$false` in IF-002) was reworded away.

## Validation

Run from the FileBackup repo root with Python 3.11.9. Every legacy id LLR-001 to LLR-094 has a row in mapping.md (94 of 94, checked by script), and IF-001's parts are mapped.

```
> python validate_design.py C:\Projects\FileBackup\docs\plans\spine-restructure\derive\r3-merged .
components=24 interfaces=45 (boundary=41, internal=4) llr=128 (top=106, child=22) legacy_kept=73
SRs reaching no LLR: 0 []
ERRORS 0
WARNINGS 10
  W IF IF-013.data: code-like token 'FileBackupState.json'
  W IF IF-013.data: code-like token 'FileBackupState.json'
  W IF IF-013.data: code-like token 'RECONSTRUCT.bat'
  W IF IF-019.data: code-like token 'RECONSTRUCT.cmd'
  W IF IF-019.data: code-like token 'paths.json'
  W IF IF-020.data: code-like token 'RECONSTRUCT.cmd'
  W IF IF-028.data: code-like token '$RECYCLE'
  W IF IF-030.data: code-like token 'FileBackupState.json'
  W IF IF-030.data: code-like token 'FileBackupState.json'
  W IF IF-038.data: code-like token 'FileBackup.json'
```

Opus's own stricter validator (dimension grammar, hats already carried by the parent SRs, history tokens, legacy symbol tokens) was also run against this folder from a temporary copy. Beyond the IF-027 pair (it reads only its own gap-file layout) and $RECYCLE.BIN in IF-028's form, its one finding was that mapping.md names LLR-145, which is deliberate: the line records that Opus's row was folded.

Counts: 24 components; 45 interfaces (41 boundary, 4 internal); 128 LLRs (106 top-level, 22 child); 73 legacy ids kept; 60 design gaps (M01 to M60); 14 SR-constrains pairs; 9 items of code beyond the design.

## Round 3b: the review dispositions

The full-round-1 dispositions (`../r3-dispositions.md`, review dispositions table) are applied by `_r3b_apply.py` (every edit as an anchored replacement over the HEAD carriers, so a re-run reproduces the tier) and `_r3b_docs.py` (this section and the design-gaps changes); `_r3b_lint.py` adds the dimension-grammar, history-token, dangling-reference and SR-naming checks and lists every row changed. The entry per finding is in `../r3b-change-log.md`. Ten LLRs were added (LLR-151 to LLR-160, after the highest id in use, LLR-150; LLR-145 stays retired).

### Placement (R3O-012)

Placement is derived from the owner of the interface a row constrains. The dispositions allow unplaced rows but not rows placed in the wrong component, and forbid minting interfaces only to place rows. So: IF-020 (the restore request) moved to the restore kit (CMP-017), which with IF-019 and IF-023 owns what its children produce together; every row whose constrained interface belonged to another component's responsibility lost its `constrains` cell (its dimensions stay) and shows as unplaced; LLR-111, LLR-113 and LLR-122 were re-pointed to an interface their own component owns or reads at (IF-028, IF-029, IF-032). The store-format records IF-017 and IF-018 are left with SR constrainers only (design-gaps section 2). A row placed at an enclosing component counts as placed. Responsibility is the row's section in `low-level-requirements.toml`, except where the table's first column says otherwise (writer rows filed under State publication, the container's mapping row, the whole-run rows).

Counts: 65 placed, 11 placed at an ancestor, 63 unplaced; none misplaced (round 3d added LLR-161, placed at the guard).

| Component | Owns | Rows placed here |
|---|---|---|
| CMP-001 FileBackup | none | 0 |
| CMP-002 Operation launch and outcome | IF-002, IF-003, IF-010 | 4 |
| CMP-003 Configuration | IF-004, IF-005, IF-006 | 9 |
| CMP-004 Provisioning | IF-007 | 1 |
| CMP-005 Notification | IF-011 | 1 |
| CMP-006 Run record and progress | IF-009 | 4 |
| CMP-007 Backup engine | none | 0 |
| CMP-008 Source capture | none | 0 |
| CMP-009 Change detection | IF-029 | 3 |
| CMP-010 Content writer | none | 0 |
| CMP-011 State publication | IF-030 | 2 |
| CMP-012 Exclusive-use guard | IF-032, IF-033, IF-044 | 12 |
| CMP-013 Removal and saved-state report | IF-043 | 2 |
| CMP-014 Check, repair and kit refresh | none | 0 |
| CMP-015 Views | IF-041, IF-042 | 3 |
| CMP-016 Store format | IF-013, IF-014, IF-015, IF-016, IF-017, IF-018, IF-034 | 13 |
| CMP-017 Restore kit | IF-019, IF-020, IF-023 | 13 |
| CMP-018 Restore admission | none | 0 |
| CMP-019 Entry restoration | IF-045 | 1 |
| CMP-020 Tree finishing | none | 0 |
| CMP-021 Restore outcome and report | IF-021, IF-022 | 2 |
| CMP-022 Restore launch and target choice | none | 0 |
| CMP-023 Container | IF-038, IF-039, IF-040 | 4 |
| CMP-024 Release guidance | IF-008 | 2 |

| LLR | Responsibility | Constrains | Interface owner | Derived placement | Verdict |
|---|---|---|---|---|---|
| LLR-001 | CMP-008 Source capture | IF-028 | external:EXT-04 | unplaced | unplaced |
| LLR-002 | CMP-016 Store format | IF-034 | CMP-016 | CMP-016 | placed |
| LLR-003 | CMP-010 Content writer | - | - | unplaced | unplaced |
| LLR-004 | CMP-010 Content writer | - | - | unplaced | unplaced |
| LLR-005 | CMP-011 State publication | - | - | unplaced | unplaced |
| LLR-007 | CMP-011 State publication | - | - | unplaced | unplaced |
| LLR-008 | CMP-018 Restore admission | IF-024 | external:EXT-11 | unplaced | unplaced |
| LLR-009 | CMP-018 Restore admission | IF-025 | external:EXT-12 | unplaced | unplaced |
| LLR-010 | CMP-019 Entry restoration | IF-020 | CMP-017 | CMP-017 | placed at an ancestor |
| LLR-011 | CMP-009 Change detection | - | - | unplaced | unplaced |
| LLR-014 | CMP-002 Operation launch and outcome | IF-003 | CMP-002 | CMP-002 | placed |
| LLR-015 | CMP-005 Notification | IF-011 | CMP-005 | CMP-005 | placed |
| LLR-016 | CMP-002 Operation launch and outcome | IF-002 | CMP-002 | CMP-002 | placed |
| LLR-017 | CMP-012 Exclusive-use guard | IF-044 | CMP-012 | CMP-012 | placed |
| LLR-018 | CMP-003 Configuration | - | - | unplaced | unplaced |
| LLR-020 | CMP-004 Provisioning | IF-046 | external:EXT-06 | unplaced | unplaced |
| LLR-021 | CMP-008 Source capture | - | - | unplaced | unplaced |
| LLR-022 | CMP-016 Store format | IF-013 | CMP-016 | CMP-016 | placed |
| LLR-023 | CMP-018 Restore admission | IF-025 | external:EXT-12 | unplaced | unplaced |
| LLR-024 | CMP-016 Store format | IF-014 | CMP-016 | CMP-016 | placed |
| LLR-025 | CMP-016 Store format | IF-014 | CMP-016 | CMP-016 | placed |
| LLR-026 | CMP-011 State publication | - | - | unplaced | unplaced |
| LLR-027 | CMP-024 Release guidance | IF-008 | CMP-024 | CMP-024 | placed |
| LLR-028 | CMP-011 State publication | IF-030 | CMP-011 | CMP-011 | placed |
| LLR-029 | CMP-021 Restore outcome and report | IF-022 | CMP-021 | CMP-021 | placed |
| LLR-035 | CMP-011 State publication | IF-030 | CMP-011 | CMP-011 | placed |
| LLR-036 | CMP-008 Source capture | - | - | unplaced | unplaced |
| LLR-037 | CMP-004 Provisioning | IF-007 | CMP-004 | CMP-004 | placed |
| LLR-038 | CMP-016 Store format | IF-015 | CMP-016 | CMP-016 | placed |
| LLR-039 | CMP-018 Restore admission | - | - | unplaced | unplaced |
| LLR-040 | CMP-021 Restore outcome and report | IF-021 | CMP-021 | CMP-021 | placed |
| LLR-041 | CMP-011 State publication | - | - | unplaced | unplaced |
| LLR-042 | CMP-003 Configuration | IF-004 | CMP-003 | CMP-003 | placed |
| LLR-043 | CMP-002 Operation launch and outcome | IF-003 | CMP-002 | CMP-002 | placed |
| LLR-045 | CMP-013 Removal and saved-state report | IF-043 | CMP-013 | CMP-013 | placed |
| LLR-046 | CMP-013 Removal and saved-state report | - | - | unplaced | unplaced |
| LLR-047 | CMP-013 Removal and saved-state report | - | - | unplaced | unplaced |
| LLR-048 | CMP-023 Container | IF-038 | CMP-023 | CMP-023 | placed |
| LLR-049 | CMP-014 Check, repair and kit refresh | - | - | unplaced | unplaced |
| LLR-050 | CMP-019 Entry restoration | IF-045 | CMP-019 | CMP-019 | placed |
| LLR-051 | CMP-011 State publication | - | - | unplaced | unplaced |
| LLR-052 | CMP-010 Content writer | IF-031 | external:EXT-05 | unplaced | unplaced |
| LLR-053 | CMP-010 Content writer | - | - | unplaced | unplaced |
| LLR-054 | CMP-014 Check, repair and kit refresh | - | - | unplaced | unplaced |
| LLR-055 | CMP-008 Source capture | IF-028 | external:EXT-04 | unplaced | unplaced |
| LLR-056 | CMP-019 Entry restoration | IF-023 | CMP-017 | CMP-017 | placed at an ancestor |
| LLR-058 | CMP-010 Content writer | - | - | unplaced | unplaced |
| LLR-059 | CMP-011 State publication | - | - | unplaced | unplaced |
| LLR-060 | CMP-016 Store format | IF-014 | CMP-016 | CMP-016 | placed |
| LLR-061 | CMP-015 Views | IF-041 | CMP-015 | CMP-015 | placed |
| LLR-062 | CMP-013 Removal and saved-state report | IF-043 | CMP-013 | CMP-013 | placed |
| LLR-063 | CMP-003 Configuration | - | - | unplaced | unplaced |
| LLR-065 | CMP-008 Source capture | - | - | unplaced | unplaced |
| LLR-066 | CMP-020 Tree finishing | IF-023 | CMP-017 | CMP-017 | placed at an ancestor |
| LLR-067 | CMP-008 Source capture | IF-028 | external:EXT-04 | unplaced | unplaced |
| LLR-068 | CMP-016 Store format | IF-016 | CMP-016 | CMP-016 | placed |
| LLR-069 | CMP-016 Store format | IF-016 | CMP-016 | CMP-016 | placed |
| LLR-071 | CMP-018 Restore admission | IF-024 | external:EXT-11 | unplaced | unplaced |
| LLR-073 | CMP-022 Restore launch and target choice | IF-026 | external:EXT-10 | unplaced | unplaced |
| LLR-074 | CMP-022 Restore launch and target choice | IF-020 | CMP-017 | CMP-017 | placed at an ancestor |
| LLR-076 | CMP-017 Restore kit | IF-019 | CMP-017 | CMP-017 | placed |
| LLR-077 | CMP-020 Tree finishing | IF-023 | CMP-017 | CMP-017 | placed at an ancestor |
| LLR-078 | CMP-008 Source capture | IF-028 | external:EXT-04 | unplaced | unplaced |
| LLR-079 | CMP-018 Restore admission | IF-025 | external:EXT-12 | unplaced | unplaced |
| LLR-080 | CMP-012 Exclusive-use guard | IF-033 | CMP-012 | CMP-012 | placed |
| LLR-086 | CMP-010 Content writer | - | - | unplaced | unplaced |
| LLR-087 | CMP-016 Store format | IF-014 | CMP-016 | CMP-016 | placed |
| LLR-088 | CMP-012 Exclusive-use guard | - | - | unplaced | unplaced |
| LLR-090 | CMP-012 Exclusive-use guard | IF-032 | CMP-012 | CMP-012 | placed |
| LLR-091 | CMP-012 Exclusive-use guard | IF-032 | CMP-012 | CMP-012 | placed |
| LLR-092 | CMP-012 Exclusive-use guard | IF-032 | CMP-012 | CMP-012 | placed |
| LLR-093 | CMP-012 Exclusive-use guard | IF-032 | CMP-012 | CMP-012 | placed |
| LLR-094 | CMP-012 Exclusive-use guard | IF-032 | CMP-012 | CMP-012 | placed |
| LLR-095 | CMP-006 Run record and progress | IF-009 | CMP-006 | CMP-006 | placed |
| LLR-096 | CMP-002 Operation launch and outcome | IF-010 | CMP-002 | CMP-002 | placed |
| LLR-097 | CMP-006 Run record and progress | IF-009 | CMP-006 | CMP-006 | placed |
| LLR-098 | CMP-003 Configuration | IF-004 | CMP-003 | CMP-003 | placed |
| LLR-099 | CMP-003 Configuration | IF-006 | CMP-003 | CMP-003 | placed |
| LLR-100 | CMP-003 Configuration | IF-006 | CMP-003 | CMP-003 | placed |
| LLR-101 | CMP-003 Configuration | IF-005 | CMP-003 | CMP-003 | placed |
| LLR-102 | CMP-024 Release guidance | IF-008 | CMP-024 | CMP-024 | placed |
| LLR-103 | CMP-003 Configuration | IF-004 | CMP-003 | CMP-003 | placed |
| LLR-104 | CMP-003 Configuration | IF-004 | CMP-003 | CMP-003 | placed |
| LLR-105 | CMP-004 Provisioning | IF-037 | external:EXT-07 | unplaced | unplaced |
| LLR-106 | CMP-005 Notification | IF-012 | external:EXT-16 | unplaced | unplaced |
| LLR-107 | CMP-006 Run record and progress | IF-009 | CMP-006 | CMP-006 | placed |
| LLR-108 | CMP-006 Run record and progress | IF-009 | CMP-006 | CMP-006 | placed |
| LLR-109 | CMP-008 Source capture | IF-028 | external:EXT-04 | unplaced | unplaced |
| LLR-110 | CMP-008 Source capture | - | - | unplaced | unplaced |
| LLR-111 | CMP-008 Source capture | IF-028 | external:EXT-04 | unplaced | unplaced |
| LLR-112 | CMP-008 Source capture | IF-028 | external:EXT-04 | unplaced | unplaced |
| LLR-113 | CMP-009 Change detection | IF-029 | CMP-009 | CMP-009 | placed |
| LLR-114 | CMP-009 Change detection | IF-029 | CMP-009 | CMP-009 | placed |
| LLR-115 | CMP-009 Change detection | IF-029 | CMP-009 | CMP-009 | placed |
| LLR-116 | CMP-010 Content writer | - | - | unplaced | unplaced |
| LLR-117 | CMP-010 Content writer | IF-035 | external:EXT-06 | unplaced | unplaced |
| LLR-118 | CMP-016 Store format | IF-015 | CMP-016 | CMP-016 | placed |
| LLR-119 | CMP-017 Restore kit | IF-019 | CMP-017 | CMP-017 | placed |
| LLR-120 | CMP-016 Store format | IF-014 | CMP-016 | CMP-016 | placed |
| LLR-121 | CMP-016 Store format | IF-014 | CMP-016 | CMP-016 | placed |
| LLR-122 | CMP-012 Exclusive-use guard | IF-032 | CMP-012 | CMP-012 | placed |
| LLR-123 | CMP-012 Exclusive-use guard | IF-032 | CMP-012 | CMP-012 | placed |
| LLR-124 | CMP-012 Exclusive-use guard | IF-033 | CMP-012 | CMP-012 | placed |
| LLR-125 | CMP-012 Exclusive-use guard | IF-033 | CMP-012 | CMP-012 | placed |
| LLR-126 | CMP-013 Removal and saved-state report | - | - | unplaced | unplaced |
| LLR-127 | CMP-013 Removal and saved-state report | - | - | unplaced | unplaced |
| LLR-128 | CMP-013 Removal and saved-state report | - | - | unplaced | unplaced |
| LLR-129 | CMP-014 Check, repair and kit refresh | - | - | unplaced | unplaced |
| LLR-130 | CMP-014 Check, repair and kit refresh | - | - | unplaced | unplaced |
| LLR-131 | CMP-014 Check, repair and kit refresh | - | - | unplaced | unplaced |
| LLR-132 | CMP-015 Views | IF-042 | CMP-015 | CMP-015 | placed |
| LLR-133 | CMP-015 Views | IF-036 | external:EXT-06 | unplaced | unplaced |
| LLR-134 | CMP-015 Views | IF-042 | CMP-015 | CMP-015 | placed |
| LLR-135 | CMP-010 Content writer | IF-031 | external:EXT-05 | unplaced | unplaced |
| LLR-136 | CMP-018 Restore admission | - | - | unplaced | unplaced |
| LLR-137 | CMP-018 Restore admission | IF-025 | external:EXT-12 | unplaced | unplaced |
| LLR-138 | CMP-018 Restore admission | IF-019 | CMP-017 | CMP-017 | placed at an ancestor |
| LLR-139 | CMP-018 Restore admission | IF-024 | external:EXT-11 | unplaced | unplaced |
| LLR-140 | CMP-016 Store format | IF-014 | CMP-016 | CMP-016 | placed |
| LLR-141 | CMP-019 Entry restoration | IF-023 | CMP-017 | CMP-017 | placed at an ancestor |
| LLR-142 | CMP-019 Entry restoration | IF-023 | CMP-017 | CMP-017 | placed at an ancestor |
| LLR-143 | CMP-020 Tree finishing | - | - | unplaced | unplaced |
| LLR-144 | CMP-020 Tree finishing | - | - | unplaced | unplaced |
| LLR-146 | CMP-023 Container | IF-040 | CMP-023 | CMP-023 | placed |
| LLR-147 | CMP-023 Container | IF-039 | CMP-023 | CMP-023 | placed |
| LLR-148 | CMP-023 Container | IF-040 | CMP-023 | CMP-023 | placed |
| LLR-149 | CMP-001 FileBackup | - | - | unplaced | unplaced |
| LLR-150 | CMP-011 State publication | - | - | unplaced | unplaced |
| LLR-151 | CMP-008 Source capture | IF-028 | external:EXT-04 | unplaced | unplaced |
| LLR-152 | CMP-008 Source capture | IF-028 | external:EXT-04 | unplaced | unplaced |
| LLR-153 | CMP-003 Configuration | IF-004 | CMP-003 | CMP-003 | placed |
| LLR-154 | CMP-003 Configuration | IF-004 | CMP-003 | CMP-003 | placed |
| LLR-155 | CMP-003 Configuration | - | - | unplaced | unplaced |
| LLR-156 | CMP-022 Restore launch and target choice | IF-027 | external:EXT-10 | unplaced | unplaced |
| LLR-157 | CMP-022 Restore launch and target choice | IF-020 | CMP-017 | CMP-017 | placed at an ancestor |
| LLR-158 | CMP-019 Entry restoration | IF-020 | CMP-017 | CMP-017 | placed at an ancestor |
| LLR-159 | CMP-018 Restore admission | IF-019 | CMP-017 | CMP-017 | placed at an ancestor |
| LLR-160 | CMP-001 FileBackup | - | - | unplaced | unplaced |
| LLR-161 | CMP-012 Exclusive-use guard | IF-033 | CMP-012 | CMP-012 | placed |

## Round 3d: full round 2

The full-round-2 dispositions (`../r3-dispositions.md`, "Convergence check 1 and full round 2", R3C-001 to R3C-008) are applied by `_r3d_apply.py` (anchored replacements over the HEAD carriers) and `_r3d_docs.py` (design-gaps M83 to M88 and this section); the entry per finding is in `../r3d-change-log.md`. One LLR was added, LLR-161 (child of LLR-125, constrains IF-033, so placed at the exclusive-use guard). No other `constrains` cell changed, so no other placement moved. IF-032 gains the restore admission (CMP-018) as a consumer, since a restore meeting a kit mid-refresh tests whether the claim is held; ownership is unchanged.

## Round 3f: full round 3 (the last)

The full-round-3 dispositions (`../r3-dispositions.md`, "Convergence check 2 and full round 3 (the last)", R3E-001 to R3E-006) are applied by `_r3f_apply.py` (anchored replacements over the HEAD carriers) and `_r3f_docs.py` (design-gaps M89 and M90, the amended gaps, and this section); the entry per finding is in `../r3f-change-log.md`. No LLR was added and no `constrains`, `owner`, `consumers` or `parent` cell changed, so the placement table above stands unchanged (65 placed, 11 placed at an ancestor, 63 unplaced, none misplaced). Interface versions moved: IF-009 to 2 (the per-run location record name), IF-033 to 3 (the run's location record joins the run folder's closed set; the prepared folder's evidence is its own), IF-044 to 3 (the run identity's presence, the prepared folder's evidence test).
