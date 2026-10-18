# Round 2b: change log for the fresh review's dispositions

Applies `r2b-dispositions.md` to the findings in `r2-review2-astra/findings.json`.
Every row stays Drafted. The SR tier goes from 115 rows to 120. New rows are
SR-145 to SR-149, the new crossing is B-24 and the new assumption is DA-22.

## Per finding

| Finding | Rows changed | Cells changed |
|---|---|---|
| R2A-001 | SR-043, SR-040, SR-017, SR-019, SR-023, SR-036, SR-046, SR-048, SR-052, SR-061, SR-085, SR-086, SR-102, SR-107, SR-118, SR-129, SR-132, SR-140, SR-144 | SR-043: title, requirement, rationale, acceptance, permutations (five-value vocabulary; configuration refused and busy now have different values; how several locations combine, with 2 taking precedence over 3 and 3 over 4). SR-040: requirement (cites the shared vocabulary), acceptance (new labels; a missing or too-old restore tool and a target lacking space are 4; damaged current metadata is 1), permutations. Busy or not ready changed from 2 to 4 in the acceptance of SR-017, SR-019, SR-036, SR-052, SR-061 (backup side), SR-085, SR-086, SR-107 and SR-132. SR-046: requirement no longer says "as not ready"; acceptance gives 3 for a remaining record that fails its completeness check and 4 for every other cause. SR-023 and SR-118: restore space and tool refusals changed from 2 to 4. Wording only, value 2 kept: SR-048 and SR-102 ("bad request"), SR-140 and SR-129 ("configuration-refused"). |
| R2A-002 | SR-001, SR-074 | SR-001: requirement (every file outside the declared exclusions is either recorded or named as not captured), rationale (the capture domain; each exclusion listed; outcome per SR-089/SR-055), acceptance (a file neither restored nor named is a failure; a named file makes the run part failed), delivered_with (+SR-055). SR-074: title, requirement (the full exclusion list, adding what lies behind an unfollowed link (SR-137) and refused names (SR-055)), rationale, acceptance ("Nothing else is omitted" kept), delivered_with (+SR-137, SR-055). |
| R2A-003 | SR-082, SR-110 | SR-082: rationale and acceptance (recovery only after exclusive hold and admission; only a positively identified interrupted publication is completed; anything ambiguous is refused under SR-017; a run refused at admission recovers nothing), delivered_with (+SR-017, SR-085). SR-110: acceptance (same admission and positive-identification condition). |
| R2A-004 | SR-024, SR-100 | requirement (a no-op means no source change *and* no stored content needing to be stored again), rationale (healing is exempt; a heal that changes the record saves the previous state as SR-053 says; SN-021 is read with that exemption), acceptance ("with no stored content lost between them"). |
| R2A-005 | B-24 (new), EXT-04, SR-139, SR-093 | B-24: new `out` crossing to EXT-04 for the default source-root record and the root folder's own modification time; B-01 is unchanged and still read-only. EXT-04: description notes the one exception (B-24). SR-139: boundary_refs B-01 replaced by B-24. SR-093: boundary_refs +B-24. |
| R2A-006 | SN-037, SR-093 | SN-037: need and acceptance (quoted below). SR-093: requirement, rationale and acceptance now also allow the source-root folder's own modification time, and say nothing else changes. |
| R2A-007 | SR-023 | title, requirement and rationale (demand is the expanded content plus a declared allowance for allocation, folder metadata and temporary working space, as SR-052 does for a backup), acceptance (refused above the demand; no failure for want of space at or below it, many small files included; exit code 4), permutations. |
| R2A-008 | SR-145 (new), SR-029, SR-120, SR-121 | SR-145: the common restore admission boundary (every whole-restore check before any write; combined-fault acceptance). SR-029, SR-120, SR-121: the requirement now applies only "in a restore that has passed admission (SR-145)"; delivered_with +SR-145. SR-029 and SR-121: acceptance adds a combined-fault case. SR-029 and SR-120: rationale. |
| R2A-009 | SR-109 | rationale (certainty also comes from an identity-verified copy elsewhere, same digest and length; cites DA-05 and DA-11), acceptance (new certain class: missing from its place with a verified copy elsewhere, which is re-pointed or stored again; an unverified copy is report-only), permutations, da_refs (+DA-05, DA-11; coincident removed so that each row has da_refs or coincident, not both). |
| R2A-010 | SR-116, SR-146 (new), SR-066, SR-040 | SR-116: title, rationale and acceptance cover old-version compatibility only (a positively identified older state is 0); the sentence "absent or malformed folder metadata never fails a restore" is removed; delivered_with +SR-146. SR-146: a current-form state with a missing or malformed folder record restores its files, reports the gap and returns 1. SR-066 (the finding's second half): rationale and acceptance; a blank or unreadable time in a current-form record is reported and the restore returns 1 (the file is still restored); "a time never fails a restore" is removed. SR-040: these cases are listed under 1. |
| R2A-011 | SN-024, SR-142 | SN-024: acceptance gains the default action (quoted below). SR-142: rationale now traces to SN-024's acceptance; the argument about compatibility with existing hosts is removed. |
| R2A-012 | SR-129 | rationale (the row refuses a readable credential, not a format; the JSON form has no protected representation, so any credential in it is readable; the native-Windows form carries it protected, DA-20), acceptance (states the JSON reasoning; value 2), da_refs (+DA-20; coincident removed). |
| R2A-013 | SR-112 | title, requirement (total resident memory of the operation, including the tools it runs at the same time; run within the declared change envelope), rationale, acceptance (summed peak; a run with at most 1 GiB changed). |
| R2A-014 | SR-064, SR-113 | SR-064: rationale, acceptance (local solid-state storage; up to 365 saved states; a check of every state and a full restore of one state), permutations (+saved_states). SR-113: acceptance (conditions for comparing the doubled history: same source, same change, no re-read, same host with no competing load, same compression). |
| R2A-015 | SR-147 (new), SR-099 | SR-147: where the space view is off, the run's record says the media measure was not taken. SR-099: delivered_with +SR-147. |
| R2A-016 | SR-144 | title, requirement (scoped to a claim no longer held, with liveness evidence stale beyond the threshold), rationale (under DA-03 a suspended holder still holds its claim; a reclaim happens only across hosts or containers where the claim is not shared, or after the claim is lost), acceptance (a successor is refused as busy, 4, while the claim is held; the reclaim case is tested on another host or container), permutations, da_refs (+DA-03, DA-16; coincident removed). |
| R2A-017 | SR-139, SR-148 (new), SR-149 (new), SR-094, SR-138 | SR-139: rationale, acceptance, permutations, coincident and delivered_with now cover the default location only. SR-148: explicit relocation. SR-149: the location admission rules, with the allowed relation stated once. SR-094: rationale points to SR-148; delivered_with +SR-148. SR-138: rationale points to SR-149; delivered_with +SR-149. |
| R2A-018 | SR-125, DA-22 (new) | SR-125: requirement (two minutes of active execution time), rationale, acceptance (start to first entry, between entries, last entry to completion), permutations, da_refs (+DA-22; coincident removed). DA-22: the scheduling assumption (the run is not suspended). |
| R2A-019 | SR-059 | requirement (in terms of a retained state's record), rationale (the unit preserved; the latest state advances; an authorised removal takes a state away), acceptance (the universal clause restated for retained saved states). |
| R2A-020 (MINOR) | SR-015 | requirement: opens "Where notification is set up and is not switched off for the run". |
| R2A-021 (MINOR) | SR-031 | requirement: opens with the distinct-names and tool-floor conditions as a `Where` clause; da_refs unchanged. |

## Need edits (both rows still Drafted; no other text changed)

**SN-037 `need`**
- old: "... The one exception is the record of what the tool last saw, which it keeps as a plain file at the source root unless the owner sets it to live on the backup side."
- new: "... The one exception is the record of what the tool last saw, which it keeps as a plain file at the source root unless the owner sets it to live on the backup side, together with the change to the source-root folder's own modification time that creating or updating that record causes; nothing else in the source changes."

**SN-037 `acceptance`**
- old: "After any run, every file and folder in the source is byte-identical with unchanged modification times and attributes, apart from that record where it is kept at the source root; ..."
- new: "After any run, every file and folder in the source is byte-identical with unchanged modification times and attributes, apart from that record and the source-root folder's own modification time, where the record is kept at the source root; ..."

**SN-024 `acceptance`**
- old: "... a removal and the saved-state report run the same way and return the same outcomes as when started directly."
- new: "... a removal and the saved-state report run the same way and return the same outcomes as when started directly; a container started without naming an action runs a backup."

## Frame and assumption edits

- external.toml: B-24 added. EXT-04 description, old: "... FileBackup only reads it." New: "... FileBackup only reads it, apart from the change-detection record it keeps at a source's root by default (B-24)."
- assumptions.toml: DA-22 added (effect_at B-06, B-20; obstacle_hats UNATTENDED-OPS).

## Judgement calls for the convergence check

1. **Restore space and tool refusals moved from 2 to 4** (SR-023, SR-118, SR-040). The new vocabulary has no "precondition" under 2, and it names "tool problem" and "not ready" under 4. The backup's matching refusals (SR-052 space, SR-019 tool) are 4 as well.
2. **SR-061 keeps 2 on the restore side** for a retired form (bad request). The backup side is labelled "not ready" and moves to 4. Keeping 2 on the restore side preserves SR-040's rule that 2 takes precedence over 3 for a retired form that has no completeness evidence.
3. **3 is now a backup or removal outcome** ("damaged record (store or restore)"). It applies to SR-046's "remaining record fails its completeness check" cause.
4. **SR-066** gets the R2A-010 treatment although the disposition text names only the folder record. The finding names SR-066 explicitly.

## Not applied

- R2A-003 suggests aligning SN-013's "before it does anything else" clause. This brief permits need edits only to SN-037 and SN-024, so SN-013 is unchanged. SR-082 now reads that clause as "after exclusive hold and admission".
- SN-001's acceptance still names only the backup's own files and the volume system folders as left out. SR-001 and SR-074 now also list unfollowed links and refused names. SN-001 is outside this brief.

## Changed or added row ids

SR-001, SR-015, SR-017, SR-019, SR-023, SR-024, SR-029, SR-031, SR-036, SR-040, SR-043, SR-046, SR-048, SR-052, SR-059, SR-061, SR-064, SR-066, SR-074, SR-082, SR-085, SR-086, SR-093, SR-094, SR-099, SR-100, SR-102, SR-107, SR-109, SR-110, SR-112, SR-113, SR-116, SR-118, SR-120, SR-121, SR-125, SR-129, SR-132, SR-138, SR-139, SR-140, SR-142, SR-144, SR-145, SR-146, SR-147, SR-148, SR-149, SN-024, SN-037, EXT-04, B-24, DA-22

## Round 2c

Applies the coordinator's ruling on the outcome vocabulary, which overrides the
round-2b vocabulary above (judgement call 1 and the "not ready" class are
withdrawn). For a backup host, 2 means "alert a person" and 4 means "retry
later". The rule covers every operation: 0 complete; 1 some part failed or
content missing; 2 cannot proceed until someone changes something (a bad
request, a refused configuration, or a precondition not met); 3 damaged record;
4 retry later without changing anything (busy, or a host fault while working).
"Not ready", "host or tool problem" and "tool problem" no longer appear in the
SR tier. Every row stays Drafted.

| Row | Cell | Old → new |
|---|---|---|
| SR-017 | acceptance | every listed finding 4 ("not ready") → busy 4 only where the sole finding is an earlier run alive or not proven dead; 2 (precondition not met) where any other finding is present, so 2 still outranks 4 |
| SR-019 | acceptance | unsupported runtime, unobtainable hashing component, missing archive tool: 4 → 2 |
| SR-023 | requirement, rationale, acceptance | "not-ready outcome" → "precondition-not-met outcome"; rationale: fixed by someone freeing space or choosing another target; restore exit code 4 → 2 |
| SR-029 | acceptance | content missing with the target lacking space: exit code 4 → 2 |
| SR-036 | requirement, acceptance, coincident | "as not ready" → "as a precondition not met"; value 4 → 2 |
| SR-040 | rationale, acceptance, permutations | the vocabulary is stated once in the acceptance: 2 = bad request or precondition not met (a host tool absent or below its version, a target lacking space), 4 = host fault while the restore works (I/O failure, tool failing mid-restore); the separate sentence classing absent tools and lacking space as 4 is removed; precedence unchanged (2 > 3 > 4 > 1); permutation classes host-or-tool-problem and target-not-ready → precondition-not-met and host-fault |
| SR-043 | title, requirement, rationale, acceptance, permutations | scope: backup, removal, check → backup, removal, check, repair, kit refresh; requirement classes: "busy or not ready or a host or tool problem" → "stopped for a later retry because busy or a host fault while working", and "request or configuration refused" → "cannot proceed until someone changes something"; rationale no longer lists the values (it explains alert versus retry); acceptance states the values once, with the precondition examples under 2; precedence unchanged (2 > 3 > 4); permutations: operation +repair, kit-refresh; class not-ready, tool-problem → precondition-not-met, host-fault |
| SR-046 | acceptance | every cause other than a failed completeness check: 4 → 2; 3 now applies where it is the only cause, so 2 outranks 3 when causes combine |
| SR-052 | requirement, acceptance | "as not ready" → "as a precondition not met"; value 4 → 2 |
| SR-061 | acceptance | backup, removal and repair of a retired or unrecognised form: 4 → 2 (the restore side was already 2) |
| SR-107 | acceptance | the next backup after a dead removal: 4 → 2 |
| SR-118 | acceptance | missing or too-old restore tool: "tool-problem outcome, exit code 4" → "precondition-not-met outcome, exit code 2" |
| SR-132 | acceptance | unobtainable component: 4 → 2 |
| SR-140 | acceptance | value 2 kept; label "configuration-refused" → "precondition-not-met" |
| SN-001 | acceptance | "only the backup's own files and the volume's own system folders are left out" → "the only things left out are the declared exclusions: the backup's own files, the volume's own system folders, the change-detection record at the source root, what lies behind folder links that are not followed, which are named in the run's record, and files whose names are refused as non-portable, which are named and make the run report failure" |
| SN-013 | acceptance | "the next run puts back what a restore needs to check each state before it does anything else" → "once the next run holds the backup exclusively and has passed its checks, it first puts back what a restore needs to check each state" |

Checked and kept: SR-085 and SR-144 (busy, 4); SR-009, SR-018, SR-039, SR-048,
SR-073, SR-102, SR-129, SR-138, SR-141 and SR-149 (2, a bad request or refused
configuration); SR-039, SR-082, SR-110 and SR-121 (3); SR-145 (cites SR-040's
precedence).

Judgement calls for the coordinator:

1. **SR-086 keeps 4 (busy)** for every failure to claim exclusive use,
   including access denial and an unusable claim location. The row's own rule
   treats any claim failure as a live holder, so it reports busy. A person
   would have to fix those two causes, so they could be 2 instead. That would
   change SR-086's requirement, so it is left for a ruling.
2. **SR-043's scope now covers repairs and kit refreshes**, because the ruling
   applies to every operation and SR-061 and SR-086 already cite SR-043 for
   them.
3. **SR-046's "shared content already missing"** is 2 (someone must repair it
   before the removal can go ahead), not 1. 1 is reserved for an operation that
   ran.
