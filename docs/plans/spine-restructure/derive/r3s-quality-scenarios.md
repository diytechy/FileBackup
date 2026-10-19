# Quality-attribute scenarios: the data-integrity set (round 3s, item 6)

**Draft for the Owner's review.** An ATAM-style analysis of FileBackup's
design tier against its integrity qualities. Each scenario states a stimulus,
the environment, the response the design commits to, a measure a test can
check, and the rows that carry it. After the scenarios come the risks,
sensitivity points and trade-offs, many of them already decided by the
Owner's rulings. ATAM is Kazman, Klein and Clements, CMU/SEI-2000-TR-004.

The flows named are in [../../../runtime-flows.md](../../../runtime-flows.md).

## Scenarios

| # | Quality | Stimulus and environment | Response the design commits to | Measure | Carried by |
|---|---|---|---|---|---|
| Q1 | Crash consistency | Power is lost, or the process is killed, at any step of a backup (S01..S27) or of a reclaim (R1..R6). | Every published state restores exactly or is refused; the next run recognises every leftover and either completes, reclaims or refuses with the reason. Nothing is ever restored wrongly. | For each step in LLR-162's table, a kill leaves the listed shape, and the next run and a reader reach the listed verdict. | SR-082, SR-075, SR-017, LLR-162, LLR-118, LLR-150, LLR-088 (flow 1) |
| Q2 | No silent loss | Any operation (backup, removal, repair, kit refresh, collapse) runs to completion against a store with shared content. | No content any state depends on is lost or altered; earlier content that cannot be placed stays restorable and the run fails. | Before and after each operation, every state restores byte-exact. | SR-059, SR-041, LLR-051, LLR-045, LLR-026, LLR-129 (flows 2, 7, 8) |
| Q3 | Exclusive use | A second changing operation starts while one holds the backup, on the same host or a container sharing the kernel. | The second is refused as busy (4) and touches nothing. | The store is byte-identical after the refused run. | SR-085, SR-086, LLR-090, LLR-122 (flow 3) |
| Q4 | Availability for readers | A restore, check or report starts while a backup, removal, repair or kit refresh is running. | It completes normally against every state the writer does not remove. Otherwise it waits up to 60 s, then ends retry later (4), never wrong. | Restored bytes equal the chosen state's record; an unsettled case ends 4 and writes nothing. | SR-106, LLR-123, LLR-159, LLR-039 (flow 3) |
| Q5 | Self-recovery | A backup was killed, or froze, and its owner record went stale. The next scheduled run starts with nobody present. | It proves the earlier run dead (stale time plus a second sample), moves its leftovers aside, completes any interrupted publication and runs. A woken former owner changes nothing in the store except at most one misplaced object. | No person is needed. Restores after the takeover are exact. A woken former owner ends 1. | SR-075, SR-107, SR-144, LLR-080, LLR-124, LLR-125 (flow 4) |
| Q6 | Restore correctness | A restore runs from any state's own folder, possibly years later, on Windows, Linux or macOS, with the record possibly damaged or substituted. | Every whole-restore check runs before anything is written. Every written file is verified, with one recovery from another copy. A damaged record is refused. The value is the same on every route. | Every file written matches its recorded length and digest. A substituted record is refused 3. | SR-010, SR-039, SR-056, SR-008, SR-084, LLR-136, LLR-056, LLR-040 (flows 5, 6) |
| Q7 | Detecting silent corruption | Stored bytes rot, or an object is replaced with different bytes of the same length. | A deep check finds it. A plain check finds missing and wrong-form content only. A scheduled re-hash catches source changes size and time don't show. | A deep check reports PayloadMismatch for every altered object, the same-length case included. | SR-049, SR-011, LLR-049, LLR-011 (flow 8) |
| Q8 | Unattended operation | A scheduled or container run meets any refusal: no space, unmeasurable volume, busy, damaged record, missing tool. | It never prompts. It ends with one value of the shared vocabulary, so a host can alert on 2 and retry on 4. | No run blocks on input; every refusal has a value and a reason in the record. | SR-016, SR-052, LLR-016, LLR-043, LLR-097 (flow 9) |
| Q9 | Scale | A 2 TiB library of one million files with 365 saved states, on the declared reference host. | A full restore and a whole-backup check (the deep one included) each finish within 8 hours; a nightly run's time follows what changed; memory stays within its bound. | Measured at the declared scale. | SR-064, SR-113, SR-112, LLR-149, LLR-062, LLR-160 |

## Risks

- **R1. The kill-point table is only as good as its enumeration.** Every review
  round found another kill point until the table existed, and each check of
  the table found one more. Mitigation: the table is closed by construction
  (every change is one of its steps), and round 4 turns each row into a test.
  The residual risk is a step added in the build that the table does not
  list.
- **R2. Cross-host locking is outside the guarantee.** On SMB and NFS, a
  claim may not be seen by a second machine. Two hosts writing one backup is
  unsupported (DA-03), but nothing stops a user configuring it. The design
  bounds the damage (Q5), but it doesn't prevent it.
- **R3. A plain check calls an altered store clean** (P-03). An owner who
  never runs `-Deep` can miss bit rot until a restore's per-file verification
  catches it.
- **R4. A frozen run on a network share whose session is dropped** is the
  one single-host path to a takeover (Q5). It's rare, but needs a sleep, a
  share and an overlapping run.
- **R5. The macOS shell route cannot test the claim.** An unsettled record or
  kit there always ends 4, never 3 (P-14). A truly damaged record on that
  route reads as "retry later" with a message naming the damage.

## Sensitivity points (one decision moves a quality)

- **The stale time and second sample** (LLR-080: at least 1800 s, a second
  sample). Shorter makes self-recovery faster (Q5) and a false takeover more
  likely (Q3). Longer does the reverse.
- **The reader's settle wait** (60 s, every 2 s; LLR-123, LLR-159). Longer
  turns more retry-laters into completions (Q4) and makes a host wait longer
  before learning of real damage.
- **The re-read schedule** (SR-011, P-01). It moves Q7 (catching unflagged
  source changes) against Q9 (nightly run time).
- **Kit revision discipline** (LLR-076, LLR-120). Every kit-file change must
  move the revision, or Q6's "restores years later with its own kit" breaks.

## Trade-offs (one decision moves two qualities in opposite directions)

| Decision | Gains | Costs | Ruled |
|---|---|---|---|
| Superseded content renamed into the saved state on one volume, not copied (P-13) | Q9: no full copy of large edited or deleted files | Q5: a woken former owner can misplace at most one object | Owner, P-13 (b), with two writers unsupported |
| Plain check reads opening bytes; altered content needs `-Deep` (P-03) | Q9: a routine check is fast | Q7: a plain check misses bit rot | Owner, P-03 (b) |
| An unmeasurable backup volume is refused (P-04) | Q2/Q8: a backup never starts without known room | Q8: a mount that hides free space can't be a destination | Owner, P-04 |
| Readers take no claim (SR-106) | Q4: restores never blocked by a long backup | Q4: a restore of a state being removed can only end 4 | Owner, P-10 (a) |
| Evidence version 4 binds folder and link records by digest (P-15) | Q1/Q6: a torn publication can't pair one run's files with another's metadata | Q9: one more digest per publication; an older kit reads version 4 only after kit revision 14 | Owner, P-15 |
| Every change through a run-unique staging folder (the fence, LLR-161) | Q5: a woken former owner's renames fail by themselves | Complexity: the staging table has 27 steps and 6 reclaim steps | Design, R3C-002 |

## Questions for the Owner

1. Is the scenario list complete? Missing qualities would be added as Q10
   onwards (for example: privacy of credentials, or the views' freshness).
2. Should R2 (cross-host locking) get a guard? For example, the launch could
   warn when the backup root is a network share and the claim is not
   guaranteed across hosts. That would be a new requirement, not a change to
   this page.
3. Are the sensitivity points' current values (1800 s stale time, 60 s
   settle wait) right for the HomeHub host?
