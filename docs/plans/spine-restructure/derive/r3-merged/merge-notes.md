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
