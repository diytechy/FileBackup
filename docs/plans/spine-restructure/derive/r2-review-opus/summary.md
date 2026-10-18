# Review of the merged SR tier (r2-merged, 107 rows): independent reviewer (Opus)

I judged the merged tier against the needs, the frame (external.toml and assumptions.toml), the hats roster and spine-questions sections 0 and 2. For the rows waiting on a pending Owner ruling, I judged only defects unrelated to that ruling. The full list is in `findings.json`.

## Counts

| Severity | Count |
|---|---|
| BLOCKER | 2 |
| MAJOR | 13 |
| MINOR | 23 |
| **Total** | **38** |

## The five most important findings

1. **F-02 (BLOCKER): SR-107 and SR-017 conflict over a killed removal.** SR-017 refuses every later run while a removal holds the leftovers, at any age. SR-107 promises that the next backup proceeds without manual clean-up once the holder's process dies. As written, a reboot during a removal stops all backups until a person re-runs it, which breaks SN-039 and SN-013. One row has to decide the recovery.
2. **F-01 (BLOCKER): SR-019 and SR-132 give opposite outcomes for an absent required component.** SR-019's acceptance refuses the run, while SR-132 obtains the component and completes. SR-019's trigger has to become "missing and cannot be obtained".
3. **F-04 (MAJOR): no row refuses a backup location inside a source.** The listing location (SR-063) and the change-detection state (SR-094) are guarded, but the backup and saved-state locations are not. A drive-root source with its backup on the same drive, a case SR-074 tests explicitly, writes into the source, which SR-093 forbids. The legacy configuration checks have the same gap.
4. **F-06 and F-07 (MAJOR): many refusals and partial failures name no outcome class.** On the backup side these are SR-019, SR-036, SR-052, SR-061 and the repair and kit-refresh refusals. On the restore side they are SR-092, SR-121 and SR-116. SR-043 and SR-040 promise one documented value per class, but these rows leave the value open, so two builds that choose different values would both pass. Related: F-05 (SR-043 requires a check to return "busy", which SR-106 makes impossible) and F-08 (SR-122's unapplied attributes on Linux and macOS would fail SR-071's exit-0 requirement unless SR-122 states that the outcome stays complete).
5. **F-10 (MAJOR): SR-116 has no way to tell an older state from missing evidence.** It restores any state "recorded before the completeness evidence existed", but nothing distinguishes such a state from a current state whose evidence file was deleted from outside the tool. Read loosely, that lets a substituted or truncated record through, against SN-025 and SR-039. SR-116 should depend on positive version evidence, and SR-039 should refuse missing evidence on a current-format record.

Other MAJOR themes:
- The SN-001 link and junction gap is still unruled (F-03).
- SR-041's trigger is unobservable and reads as permitted loss against SR-059 (F-09).
- SR-048 traces to a need whose text does not demand it (F-11).
- SR-123 states a maintainer's versioning discipline rather than behaviour in operation (F-12).
- Mechanism sits at SR in SR-064 (a linearity claim with no pass/fail line) and SR-061 (the recognition cues the merge notes moved to IF) (F-13, F-14).
- SR-075's "never judged dead ... clock runs slow" is not bounded to DA-16 (F-15).
