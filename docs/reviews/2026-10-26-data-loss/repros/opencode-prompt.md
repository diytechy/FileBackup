You are reviewing the repository in your current working directory (a detached checkout of FileBackup at commit 7532b86). Your full brief follows. Your scope is the WHOLE repository's data-integrity surface, in this priority order: (1) the backup run in Modules/FileBackup.Engine.psm1 (Invoke-BackupSet and every step it calls, Copy-FileWithHash, Publish-StagedObject, Move-SupersededObject, the state file writes) and Write-Manifest/Read-Manifest in Modules/FileBackup.Common.psm1; (2) the restorers Reconstruct.ps1 and bash/reconstruct.sh; (3) retention (Remove-BackupSnapshot and helpers) and -Action Verify with -RepairStorage / -RefreshKits; (4) FileBackup.ps1 and container/entrypoint.sh.

Your context window is large: read the code itself, line by line, not summaries of it. Any repro store must live under C:\Users\Peter\AppData\Local\Temp\opencode\fb-review\ (create it there), never inside the checkout.

DELIVERABLE: write your complete report (the six sections the brief specifies) to the file .opencode/plans/fb-review.md in the current directory, and ALSO print the complete report as your final message.

=== BRIEF ===
# Independent review brief: hidden data-loss defects (FileBackup, branch BoundedRebuild @ 7532b86)

You are an independent reviewer of a PowerShell 7 backup tool whose whole value is
data safety. Do the work yourself; do not delegate.

## Goal

Find hidden defects that produce UNEXPECTED behaviour in a RELATIVELY NORMAL
scenario: above all **permanent data loss**, a backup state that silently no
longer restores (or restores wrong bytes), or a run that reports success while
content was not kept. The Owner does NOT want guards against contrived scenarios
or against limitations already accepted (listed below). Precision matters more
than volume: one real finding beats ten speculative ones.

Five earlier reviews of this branch considered a **process kill** at any
instant. They did not consider **power loss or an OS crash** (data still in the
OS write cache, metadata and data reaching the disk in a different order than
they were written, a USB backup drive unplugged), so give that lens real
attention: on Windows (NTFS, and exFAT/FAT32 for a USB drive) and in the Linux
container (ext4, overlay/bind mounts).

## What to read first

1. `AGENTS.md` sections 1-4 (architecture, the backup pipeline steps, the
   invariants, the gotchas).
2. `docs/plans/bounded-run-loop.md` - the Owner's rulings R1-R14 and calls
   C1-C35. These are DECIDED. Do not report a ruling as a defect. If you believe
   a ruling loses data in normal operation, report it once as a "ruling question".
3. `README.md` sections "What is **not** recorded" and "Notes & troubleshooting".
4. `docs/plans/bounded-run-loop-reviews.md` - what the five earlier reviews found
   (all adjudicated; do not re-report them).

## Plausible failures (in scope)

- normal operation: daily scheduled runs, files added/edited/renamed/deleted,
  duplicates, compression on, retention (`-Action Prune`), `-Action Verify` (with
  and without `-RepairStorage`/`-Deep`/`-RefreshKits`), restore of the latest
  state and of any snapshot, on Windows and with `bash/reconstruct.sh`;
- a process kill at any instant;
- **a power loss or OS crash at any instant, including in the seconds after a
  run has returned** (writes not yet flushed from the cache);
- the backup volume filling up, or disappearing (USB drive unplugged, share dropped);
- a source file locked, or changing while it is read; an antivirus scanner
  holding a file;
- a store continued from an older engine (older snapshots with older restore kits);
- a store copied or moved to another machine and restored there.

## Out of scope - do not report

- Contrived cases (ruling R1): a hand-edited store, a name that lies about its
  bytes, two runs at once (unsupported; there is an OS lock), two hosts writing
  one store, clock skew, a chain of several independent failures.
- Accepted limitations: file attributes, ACLs, alternate data streams, reparse
  points/junctions, creation/access times (README "What is not recorded");
  PowerShell 5.1; a snapshot manifest losing rows (plan section 2, accepted gap);
  the C17 window; a plain-Linux store whose one mount is missing (plan section 13
  note); a mapped drive letter invisible to a scheduled task (C35);
  the user deleting files inside the store.
- Silent media bit-rot of an object the hardware damaged after a clean write
  (plan section 2: detected by `Verify -Deep` and every restore).
- Style, naming, comments, missing tests, performance (unless a normal run at
  HomeHub scale - 180,000 files, 1 TB - fails).

## Method

Before you report a finding, write down the concrete steps that produce it from
a store the tool itself made, and check the code path line by line (cite
`file:line`). If you cannot write those steps, drop it. For a power-loss claim,
state the exact filesystem behaviour you rely on (for example, which writes the
filesystem may reorder or drop) and how confident you are in it; say whether the
loss is PERMANENT (no later run or restore recovers it while the source still
exists) or self-healing on the next run. Say why it is not an R1 corner case or
an accepted limitation.

## Limits

- Do not edit, create or delete anything in the repository.
- Do not run Pester or `tests/Run-All.ps1`. Small read-only commands are fine,
  and, if you need one, a small pwsh repro whose stores live under a temp folder
  outside the repository.
- Stop at 10 findings; rank them.

## Return - markdown, exactly these six sections, compact, facts before judgement

1. What was done (what you read; what you ran, if anything).
2. Where the artifact is (the report path, if you were given one).
3. What was checked and found clean (so an absence of findings is evidence).
4. Findings, most severe first. For each: severity (High = content permanently
   lost or a state unrestorable / wrong bytes in a normal scenario or plausible
   failure; Medium = a wrong outcome code, a needed state not kept, or a store
   that wedges later runs; Low = other), `file:line`, concrete steps, permanent
   or self-healing, why it is not contrived or accepted, a suggested fix
   (the smallest that closes it).
5. What was not done, and why.
6. Open questions for the caller (including any "ruling questions").
