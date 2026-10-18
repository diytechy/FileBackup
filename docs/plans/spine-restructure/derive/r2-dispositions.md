# Round 2: rulings and review dispositions for the SR tier

Input: the merged tier in `r2-merged/` (107 rows), and two independent reviews
of it. `r2-review-astra/` (GPT-6 Astra, medium) has 4 BLOCKER, 25 MAJOR and
1 MINOR findings. `r2-review-opus/` (Claude Opus, medium) has 2 BLOCKER,
13 MAJOR and 23 MINOR. Findings are claims; each is confirmed or refuted here
by the coordinator. Both reviewers found five of them independently:
R2-006/F-01, R2-002/F-09, R2-010/F-11, R2-016/F-13 and R2-021/F-03.

## Owner rulings (2026-10-17)

| # | Question | Ruling | Applies to |
|---|---|---|---|
| a | Compression when the probe can't measure | **Keep the extension fallback.** Where measuring is off or unavailable, the file type decides. The modes, the size floor and the measured decision all stay. SN-003 and the vision gain the qualifier. | SR-081, SN-003, README vision |
| b | Where the change-detection state lives | **At the source root by default**, as a plain record the owner and the tool can both read. It can be configured to live on the backup side. SN-037 gains that one exception. A read-only source with no backup-side location configured is refused before the run starts, naming the setting. | SR-093, SR-094, SN-037 |
| c | Outcome codes | **Always distinct**, with no opt-in. The old opt-in switch is still accepted and changes nothing. "Busy or not ready" is **2**, the precondition value, for every operation. | SR-043 and every refusing row |
| d | Missing or unreadable change-detection state | **Re-derive and report.** The run compares the source with the backup's own record, completes, and reports that the state was rebuilt. | SR-035 |
| e | Retired store forms versus SN-041 | **Supported versions only.** A retired form is refused by name, never misread. SN-041 is clarified to "written by a supported version". | SR-061, SN-041 |
| f | Performance and progress budgets | **Adopted as proposed**: 2 TiB, 1M files, the 4-core / 8 GiB / 200 MiB/s reference host, 8 h for a whole check and a full restore, 30 min for a run with ≤1 GiB changed, ≤4 GiB peak memory, progress at least every 2 min. Drop "proposed" from the cells. | SR-064, SR-112, SR-113, SR-125 |
| g | Configuration forms | **Both forms follow the same rules.** The native-Windows form remains the one that may carry the mail login, but it states its version and is refused on unknown keys, like JSON. Several sets in one configuration are normal, with no warning. | SR-042, SR-095, SR-129, SR-135 |

## Coordinator calls the reviews forced

- **The crash window (R2-001).** One rename is atomic (DA-01), but a state is a
  record plus its completeness evidence, two publications. The honest contract
  is this: after a crash at any point, the latest state is the pre-run or the
  post-run tree, and it either restores correctly or is refused with the
  damaged-record outcome. It is never restored wrongly. The next run
  re-establishes matching evidence before it does anything else. SR-082 states
  exactly that. SN-013's acceptance gets the same clause.
- **SN-024 is widened (R2-010/F-11):** a backup host can run backups,
  removals and the saved-state report inside a container. That is today's
  product behaviour, which the need understated. The Owner can overrule this
  at SN approval.
- **SN-031 is narrowed (R2-020)** to stored content that was *removed or
  quarantined* from outside the tool. Corrupted-but-present content is
  reported by the check (SN-030) and recovered at restore from another intact
  copy where one exists (SN-033). It is not silently re-stored, because a
  check is what tells corruption apart from a legitimate change.
- **A dead removal's leftovers (F-02).** A later backup refuses with
  not-ready (2) and names the remedy: re-run the removal, which completes
  (SR-101). SR-107's "proceeds without manual clean-up" is scoped to a dead
  backup's own leftovers.
- **Links and junctions in a source (R2-021/F-03).** Write the row as the code
  behaves today (check it). Either way the boundary outcome is fixed: content
  behind a link is either captured, or the link is named in the run's record.
  A cycle never makes a run unbounded.

## Dispositions

Every finding below is **CONFIRMED** unless marked otherwise. The fix is the
reviewer's suggested fix, adjusted by the rulings and calls above.

| Finding | Rows | Disposition |
|---|---|---|
| R2-001 | SR-082, SR-110 | Confirmed: the crash-window call above |
| R2-002, F-09 | SR-041 | Confirmed: a superseded file's content stays in the store; the saved state still restores that file; the failure is named and the run fails. Never publish a saved state that is missing a file. |
| R2-003 | SR-038, SR-039 | Confirmed: bound "substituted" to evidence that does not match; cite DA-11 |
| R2-004 | SR-016, SR-073 | Confirmed: the trigger is the declared launch contract and the observable input/session state, not "nobody present" |
| R2-005 | SR-092, SR-031 | Confirmed |
| R2-006, F-01 | SR-019, SR-132 | Confirmed: obtain permitted prerequisites first, then refuse whatever is still missing |
| R2-007 | SR-059 | Confirmed: no operation introduces *new* loss or alteration of resolvable claimed content |
| R2-008 | SR-067, SR-090 | Confirmed |
| R2-009 | SR-075 | Confirmed in part. The observable stale threshold (a dead run's leftovers are reclaimed once it has been dead for longer than the stated time) stays as acceptance. The heartbeat and confirmation algorithm move to design. Exclusion clauses go to their own rows. |
| R2-010, F-11 | SR-048, SN-024 | Confirmed: SN-024 widened (above). Move the no-action default into its own row. |
| R2-011 | (tier) | **REFUTED.** The perspective-record sidecar was retired in the kit (review-churn item 14). The hat questions live in the brief and the outcome in the review record. The shipped spine-questions text still describes it, which is the kit's own pending clean-up. |
| R2-012 | SR-027, 042, 123, 134, 035, 106, … | Confirmed: add the output crossings |
| R2-013 | SR-131 | Confirmed: add a delivery crossing for the container image and its bundled notices (`system = "delivery"`) |
| R2-014 | SR-011 | Confirmed: the vocabulary and calendar meaning move to the configuration interface (IF tier); the SR keeps the deterministic, owner-chosen schedule |
| R2-015 | SR-011 | Confirmed: the schedule governs re-reading for change detection only |
| R2-016, F-13 | SR-064 | Confirmed: the linearity clause leaves the SR (design or performance budget) |
| R2-017 | SR-113 | Confirmed: declare the history envelope (up to 365 saved states) and keep the sub-doubling bound |
| R2-018 | SR-071 | Confirmed: target-path restriction moves to its own SECURITY-derived row under SN-042 |
| R2-019 | SR-118 | Confirmed |
| R2-020 | SN-031 | Confirmed: SN-031 narrowed (above) |
| R2-021, F-03 | SR-001, new row | Confirmed: the links call above |
| R2-022 | SR-109 | Confirmed: declare the certain-repair classes and the report-only ones |
| R2-023 | several | Confirmed: one authoritative row per policy |
| R2-024 | SR-045 | Confirmed |
| R2-025 | SR-052 | Confirmed: demand includes a declared allowance for records, kits, logs and temporary space |
| R2-026 | SR-124 | Confirmed |
| R2-027 | SR-093 | Confirmed: no FileBackup-originated modification; quiescent-source assumption for before/after equality; access time excluded |
| R2-028 | SR-128 | Confirmed: scoped to credentials entered through notification setup, and to system-generated output |
| R2-030 | SR-098, SR-099 | Confirmed |
| F-02 | SR-017, SR-107 | Confirmed: the dead-removal call above |
| F-04 | new row | Confirmed: a backup or saved-state location inside, equal to, or containing a source is refused as configuration-refused |
| F-05 | SR-043 | Confirmed: busy or not-ready applies to the changing operations only |
| F-06 | refusing rows | Confirmed: each names its outcome class |
| F-07 | SR-092, SR-121, SR-116 | Confirmed: collision → content missing (1); escaping entry → damaged record (3); unverified older record → complete (0), with the warning |
| F-08 | SR-122, SR-071 | Confirmed: an attribute the target cannot hold is reported and leaves the outcome complete |
| F-10 | SR-116, SR-039 | Confirmed: "older" requires positive evidence of the older version |
| F-12 | SR-123 | Confirmed: restate as a property of one build |
| F-14 | SR-061 | Confirmed |
| F-15 | SR-075 | Confirmed: bounded by DA-16 |
| All MINOR | | Apply where the rules support it and no ruling above conflicts |
