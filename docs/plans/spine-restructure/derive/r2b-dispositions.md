# Round 2b: dispositions for the fresh review of the SR tier

Input: `r2-review2-astra/` (GPT-6 Astra, medium), a fresh review of the
committed tier (13ac3cd) that saw no earlier verdicts. It raised 4 BLOCKER,
15 MAJOR and 2 MINOR findings. This is full round 2 of at most 3. Its fixes are
followed by one bounded convergence check, limited to the changed rows, after
which the tier goes to the Owner for approval.

Every finding is **CONFIRMED** unless marked otherwise; the fix is as stated.

| Finding | Disposition and fix |
|---|---|
| R2A-001 | **Confirmed; the coordinator's earlier call is overruled by SN-045.** Busy and configuration-refused must differ. One outcome vocabulary across every operation, aligned with the restore's: **0** complete; **1** some part failed or content missing; **2** bad request or configuration refused; **3** damaged record (store or restore); **4** busy, not ready, or a host or tool problem (fix or wait, then retry). Busy is a "retry later" condition, the same class as the restore's host problem. Apply this to SR-043, SR-040 and every row that names a value. |
| R2A-002 | Define the capture domain in SR-001: every file in the source, except the declared exclusions (the source-root change-detection record, volume system folders, folder links that are not followed, names refused as non-portable), is either captured or named as not captured. The run's outcome follows SR-089/SR-055. SR-074 lists every exclusion, so "nothing else is omitted" stays true. |
| R2A-003 | Admission and exclusive ownership come before any recovery. SR-082's "before it does anything else" becomes: after it holds the backup exclusively and has passed admission. Only positively identified interrupted publications are completed; anything ambiguous is refused under SR-017. |
| R2A-004 | A no-op means no source change *and* no repair needed. Healing is exempt from SR-024/SR-100, and a heal that changes the record saves the preceding state as SR-053 says. SN-021's acceptance is read with that exemption; note it in the rationale. |
| R2A-005 | Frame: B-01 stays read-only. Add a crossing for the one authorised write, the change-detection record at a source's root by default, and cite it from SR-139. |
| R2A-006 | Part of the Owner's ruling (b): the exception covers the record *and* the incidental change to the source-root folder's own modification time that creating or updating it causes. SN-037 and SR-093 say so. Nothing else in the source changes. |
| R2A-007 | Restore demand includes a declared allowance for allocation, folder metadata and temporary working space, like the backup's (SR-052). |
| R2A-008 | A common restore admission boundary: whole-record integrity and precondition refusals stop before any write. Per-entry continuation (SR-029, SR-120, SR-121) applies only after admission. |
| R2A-009 | Confirmed: SR-109 adds a certain-repair class. When content is missing from its place but an identity-verified copy exists elsewhere in the backup (same digest and length), repair re-points or restores it. Ambiguous cases stay report-only. This will be build work. |
| R2A-010 | Separate old-version compatibility (positively identified older records) from damaged current metadata. A current-format folder record that is missing or malformed is reported, and the restore's outcome is "some part failed" (1), not complete. |
| R2A-011 | The default action moves upstream: SN-024's acceptance gains "a container started without naming an action runs a backup". SR-142 then traces to it. |
| R2A-012 | Refuse a *readable* credential. The rationale argues that the JSON form has no protected representation of a credential, so any credential in it is readable. The native-Windows form carries it protected by the host (DA-20). |
| R2A-013 | The memory bound is the operation's total resident memory, including the tools it runs concurrently. |
| R2A-014 | The reference host adds local solid-state storage, which bounds small-file and metadata cost, and the envelope adds up to 365 saved states. State the history-doubling comparison conditions. |
| R2A-015 | The run's record says the media measure was not taken when the feature is off, as SN-051 says. |
| R2A-016 | Under DA-03, a suspended holder still holds its claim, so a successor is refused while it does (SR-085). SR-144 is scoped to a claim that is no longer held: the holder was on another host or container where DA-03's claim is not shared, and was stale beyond the threshold. Its acceptance tests refusal while the claim is held. |
| R2A-017 | SR-139 keeps only the default location. Explicit relocation and the location-admission rules get their own row, or go to SR-094/SR-140 where they already belong. |
| R2A-018 | The progress interval is measured in the run's active execution time. Measure from the run's start to the first entry, between entries, and from the last entry to completion. A suspended process is out of scope, under a scheduling assumption row. |
| R2A-019 | Preservation is stated for retained point-in-time states and the content recorded for them. The latest state advances, and a state removed through an authorised removal leaves. |
| MINORs | Apply where the rules support them. |

After the fixes, the coordinator runs one convergence check (Claude Opus,
medium). It covers only the rows these dispositions change, and only two
questions: is each finding's fix present in the shape required, and has a
contradiction appeared with any unchanged row?
