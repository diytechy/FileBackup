You are reviewing the repository in your current working directory (a detached checkout of FileBackup, branch BoundedRebuild, at commit df830ee). Do the work yourself; do not delegate. Do not edit, create or delete anything in the checkout. You cannot write files in this mode, so print the complete report as your final message.

# Independent review brief: what is still wrong (FileBackup @ df830ee)

FileBackup is a PowerShell 7 backup tool whose whole value is data safety. A
four-reviewer data-loss review of commit 7532b86 (2026-10-26) was adjudicated and
its fixes merged; 41 commits since then. This is a second, whole-repository pass
to find what that review and its fixes missed, or what the fixes broke.

## Goal

Find defects that produce UNEXPECTED behaviour in a RELATIVELY NORMAL scenario,
in this priority order:
1. permanent data loss, a backup state that silently no longer restores (or
   restores wrong bytes), or a run that reports success while content was not kept;
2. a wrong exit code or a misleading report in normal operation (the exit-code
   tables are in README "Exit codes" and "Restore exit codes", and in
   docs/interfaces.md);
3. a regression introduced by the fixes since 7532b86 (`git log 7532b86..HEAD`,
   `git diff 7532b86..HEAD -- Modules FileBackup.ps1 Reconstruct.ps1 bash container`).

The Owner does NOT want guards against contrived scenarios or against
limitations already accepted (listed below). Precision matters far more than
volume: one real finding beats ten speculative ones. "No findings" is an
acceptable and useful answer if that is what the code supports.

## What to read first

1. `AGENTS.md` sections 1-4 (architecture, the backup pipeline, the invariants, the gotchas).
2. `docs/plans/bounded-run-loop.md`, especially section 13: rulings R1-R14 and
   calls C1-C44 are DECIDED. Do not report a ruling as a defect. If you believe
   a ruling loses data in normal operation, report it once as a "ruling question".
3. `docs/reviews/2026-10-26-data-loss/consolidated.md`: every finding of the
   previous review and its outcome (fixed, ruled, declined). Do not re-report
   any of them unless you show the fix is incomplete or wrong, citing the code.
4. `docs/plans/bounded-run-loop-reviews.md`: five earlier reviews, all adjudicated.
5. `README.md` sections "What is **not** recorded" and "Notes & troubleshooting".
6. `docs/status.md`, the "Current State" header only: the items it lists as open
   are KNOWN; do not report them.

## Code to read, line by line

- `Modules/FileBackup.Engine.psm1` (the backup run `Invoke-BackupSet` and every
  step it calls; retention `Remove-BackupSnapshot` and helpers; Verify and its
  repair; `Resolve-BackupSetPaths`) and `Modules/FileBackup.Common.psm1`
  (`Write-Manifest`/`Read-Manifest`, hashing, shared predicates);
- the restorers `Reconstruct.ps1` and `bash/reconstruct.sh`;
- `FileBackup.ps1` (entry point, actions, exit codes) and `container/entrypoint.sh`.

## Plausible failures (in scope)

- normal operation: daily scheduled runs, files added/edited/renamed/deleted,
  duplicates, compression on, retention (`-Action Prune`), `-Action Verify` (with
  and without `-RepairStorage`/`-Deep`/`-RefreshKits`), `-Action Snapshots`,
  restore of the latest state and of any snapshot, on Windows and with
  `bash/reconstruct.sh`;
- a process kill, a power loss or an OS crash at any instant (C36 now flushes
  before every rename or deletion relied on; check that it really does, on
  every path);
- the backup volume filling up or disappearing (USB drive unplugged, share dropped);
- a source file locked, or changing while it is read; an antivirus scanner holding a file;
- a source drive offline during a backup, a prune or a verify;
- a store copied or moved to another machine and restored there.

## Out of scope - do not report

- Contrived cases (ruling R1): a hand-edited store, a name that lies about its
  bytes, two runs at once (unsupported; there is an OS lock), two hosts writing
  one store, clock skew, a chain of several independent failures.
- Accepted limitations: file attributes, ACLs, alternate data streams, reparse
  points/junctions, creation/access times (README "What is not recorded");
  PowerShell 5.1; a snapshot manifest losing rows (plan section 2); the C17
  window; a plain-Linux store whose one mount is missing; a mapped drive letter
  invisible to a scheduled task (C35); the user deleting files inside the store;
  older stores in the pre-content-addressed layout (support withdrawn).
- Known and planned: prune and the pool-resolve check holding every manifest in
  memory (C43, second half, open); the single-store layout and `/` as the only
  path separator (C44 and its L7, planned in docs/plans/single-store-layout.md);
  the registry/traceability debts; the small follow-ups in the status header.
- Silent media bit-rot after a clean write (detected by `Verify -Deep` and every restore).
- Style, naming, comments, missing tests, performance (unless a normal run at
  HomeHub scale - 180,000 files, 1 TB - fails).

## Method

Before you report a finding, write down the concrete steps that produce it from
a store the tool itself made, and check the code path line by line (cite
`file:line` at df830ee). If you cannot write those steps, drop it. For a
power-loss claim, state the exact filesystem behaviour you rely on and how
confident you are in it, and say whether the loss is PERMANENT or self-healing
on the next run. Say why it is not an R1 corner case, an accepted limitation, or
already adjudicated in consolidated.md.

## Limits

- Do not edit, create or delete anything in the repository.
- Do not run Pester or `tests/Run-All.ps1`. Small read-only commands are fine,
  and, if you need one, a small pwsh repro whose stores live under
  C:\Users\Peter\AppData\Local\Temp\opencode\fb-review2\ (never inside the checkout).
- Stop at 10 findings; rank them.
- Keep your thinking efficient: your output budget is limited, and the report is
  what counts. Leave enough budget to write the report.

## Return - markdown, exactly these six sections, compact, facts before judgement

1. What was done (what you read; what you ran, if anything).
2. Where the artifact is (this final message).
3. What was checked and found clean (so an absence of findings is evidence).
4. Findings, most severe first. For each: severity (High = content permanently
   lost or a state unrestorable / wrong bytes in a normal scenario or plausible
   failure; Medium = a wrong outcome code, a needed state not kept, or a store
   that wedges later runs; Low = other), `file:line`, concrete steps, permanent
   or self-healing, why it is not contrived, accepted or already adjudicated, and
   the smallest fix that closes it.
5. What was not done, and why.
6. Open questions for the caller (including any "ruling questions").
