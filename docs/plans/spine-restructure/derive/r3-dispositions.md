# Round 3: calls and review dispositions for the design tier

Input: two blind derivations (`r3-astra/`, GPT-6 Astra medium; `r3-opus/`,
Claude Opus medium) and their alignment (`r3-alignment.md`, `r3-alignment-map.json`,
Claude Opus medium). This run is unattended: Owner-level calls take the
recommended default and are listed under **Pending Owner rulings** below.
Flipping one is a row edit. Every row stays Drafted.

## Alignment calls (coordinator)

The aligner's 38 conflicts (K01–K38). Each takes the aligner's recommendation
unless the call says otherwise.

| K | Call |
|---|---|
| K01 | Astra: elapsed periods since the last completed full re-read (SR-011). |
| K02 | **Owner-level, default taken:** the configuration stays at version 2 (P-01). |
| K03 | SpaceView is a boolean, default false. |
| K04 | **Owner-level, default taken:** the removal dry run stays accepted in the removal request form and keeps working; no LLR states it, since no SR asks for it; it is listed under "code beyond the design" (P-02). It is never made a bad request until the Owner rules. |
| K05 | Full payload check by default (SR-049); the deep switch stays accepted with no meaning, like the old outcome switch. The check's cost rises (about 3 h at the reference host, inside SR-064's 8 h); recorded as P-03. |
| K06 | Opus: no removal override switches in the request form; the module-level overrides are code beyond the design. |
| K07 | Opus: the hashing component is fetched without a question, attended or not (SR-132); the auto-install switch is accepted with no meaning. |
| K08 | **Owner-level, default taken:** Opus: a volume whose free space cannot be measured is not refused; the run's record says the space check was not made (P-04). |
| K09 | Astra's declared allowance numbers; round 4 checks them against the harvested test edges. |
| K10 | Astra: the space plan is read-only and runs before any root, claim, log, record or staging is created, then is revalidated under the claim. |
| K11 | **Owner-level, default taken:** Opus: a missing or unreadable run-state record with a populated backup is rebuilt (completion time from the latest evidence's written time, a full re-read due) and the rebuild is reported (P-05). |
| K12 | Opus: reconcile per path against the backup's latest record; the backup wins. |
| K13 | **Owner-level, default taken, with a coordinator design call.** The record's path separator is the backslash on every host. Design call: the reader of a record written by a supported version treats '/' and '\' alike, and change detection compares normalised paths, so a Linux-written store does **not** take a spurious full rewrite and extra saved state; its records turn to the backslash with the first run that has a real change. A source name holding a literal '\' on Linux is handled by the non-portable-name rule (SR-114/SR-136). The format change itself is a downstream-visible migration (P-06). |
| K14 | Coordinator design call: the state's own completeness-evidence version 3 (Opus, with DirRows/LinkRows) settles folder and link records with no new file. For a state with no evidence at all, age is told by the state's kit revision, and the kit refresh preserves it: the first refresh of a state records the revision it replaced as the state's original revision, written once and never changed. Astra's per-state format descriptor is not adopted. The release that introduced evidence is read from history at build time (design gap). |
| K15 | Opus plus evidence DirRows=0: the folder record is present only with rows. |
| K16 | Opus: comma attribute separator (today's form; a semicolon breaks shipped kits). |
| K17 | Opus: the link record form, a separate file present only with rows; classes inside-source and own-location. |
| K18 | Astra: 60 s per remote resolution or enumeration request. |
| K19 | Astra: flush the temporary to stable storage before the rename (SR-082). |
| K20 | Opus's write order; Astra's concern kept as its own LLR: earlier content stays reachable until the replacing state is published. |
| K21 | Fence before every destructive step (move, delete, replace, publish); creation at a fresh temporary name needs no fence. |
| K22 | Middle course: readers take no claim and leave no artifact; a reader that finds a location vanished re-resolves by content key, and one whose record's evidence changed mid-read re-reads it, a bounded number of times. |
| K23 | Union: the source is the installed program's kit; per-file temporary plus rename, never deleting; the revision marker files are written last. |
| K24 | Astra's formula (today's code). |
| K25 | Astra's exact truthy set (the shipped entry script's). |
| K26 | Opus: /tmp declared as a non-persistent scratch mount in the container's mount form; reviewers check SR-130's wording admits it. |
| K27 | Opus: a refused configuration never creates or truncates a log; the refusal line is appended to an existing global record. |
| K28 | Keep LLR-077 as a child of LLR-056: a stored item's protection never blocks verification or the time stamp, and is not handed to the restored file. |
| K29 | Opus: flat restore rows, each carrying its own SR. |
| K30 | Astra: the already-compressed type list is enumerated once, in LLR-004; the manual's table is checked against it. |
| K31 | Opus: the media rate is measured for each file whose content the run reads. |
| K32 | A restore tool present but failing its self-test at admission returns 2. |
| K33 | Astra: write a stored object at a private temporary, verify its content key, publish without replacing a claimed object. |
| K34 | **Owner-level, default taken:** SR-072's double-click holds for a kit opened from the backup's own volume. A kit carried to a Mac inside a zip is outside the support boundary; the manual gives the one-line remedy (P-07). |
| K35 | Keep the same-volume rule for the listing location only if the browse view's relative links need it, with that reason in the LLR; otherwise drop it. |
| K36 | Opus: on-disk names live in the interface form; LLRs refer to them by role. |
| K37 | Astra: a difference in the folder or link record is a change and keeps a saved state (SR-005). |
| K38 | Opus's component tree, as the aligner proposed it. |

The two Astra-only forms the aligner held back (the per-state format
descriptor and the reader pin) are not adopted, by K14 and K22.

## Pending Owner rulings

Each is written to the default. Flipping one is a row edit.

| # | Question | Options | Default taken | Rows affected |
|---|---|---|---|---|
| P-01 | Does a version-2 configuration's D/W/M/Y re-read schedule mean calendar buckets (today's code) or elapsed periods (SR-011)? | (a) elapsed periods, still version 2; (b) calendar buckets are v2's meaning, so SR-011 forces version 3 and both meanings are kept | (a) | the configuration interface, the re-read LLRs (filled in by the builder) |
| P-02 | The removal dry run (`-WhatIf`, and the container's dry-run flag) has no need behind it. Keep it or retire it? | (a) add a need, then a dry-run LLR; (b) retire it with a release note; (c) keep it working, unspecified, until ruled | (c) | the removal request interface; code beyond the design |
| P-03 | The check reads every stored object by default (SR-049), about 3 h at the reference host. Accept the heavier routine check? | (a) accept; (b) narrow SR-049 to report altered content only on a deep check | (a) | the check LLRs |
| P-04 | A volume whose free space cannot be measured: refuse (2) or proceed and record that the check was not made? | (a) proceed and record; (b) refuse with 2 | (a) | SR-052 / SR-023 LLRs |
| P-05 | Does the "re-derive and report" ruling for missing change-detection state also cover the run-state record (last completion, last full re-read)? Today the run is refused with 1. | (a) yes, rebuild and report; (b) no, refuse | (a) | LLR-035 and its children |
| P-06 | The record's path separator becomes the backslash on every host. Linux-written stores change form at their next real change (no spurious saved state). Accept the format migration? | (a) accept; (b) keep the host's separator and have every reader accept both | (a) | the record-format interface, LLR-121, gap list |
| P-07 | Does SR-072's macOS double-click cover a kit carried to the Mac inside a zip (which strips the executable bit)? | (a) no: supported from the backup's own volume, the manual gives the remedy; (b) yes: the kit's form must survive zip transfer | (a) | the launcher interface, the macOS launch LLR |
