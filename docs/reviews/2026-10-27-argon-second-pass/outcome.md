# Second whole-repository pass, opencode argon — outcome (2026-10-27)

Reviewer: opencode `opencode-go/gemini-4-argon`, plan agent, detached worktree at
`df830ee` ([brief](prompt.md), [report](review-opencode-argon.md)). The first run
read every file and then spent its whole output budget thinking (`finish:
length`, no text, exit 0); the same session resumed with `--variant low` wrote
the report, as on 2026-10-26.

Each finding was checked against the code by the main session (Claude Opus 5.5).
Nothing below has been changed yet; each needs the Owner.

| # | Reviewer's claim | Verdict | Severity (ours) |
|---|---|---|---|
| 1 | `DIRECTORIES.csv` is written in place, with no temp file, flush or rename | **Confirmed** | Low |
| 2 | A held lock makes Prune and `Verify -RepairStorage`/`-RefreshKits` exit 2 where IF-001 says 4 | **Not a defect** (a policy question) | — |
| 3 | `-Action Verify` reports a killed prune's `*.fbprune.tmp` as `Unreferenced` | **Confirmed** | Low |

## 1. `DIRECTORIES.csv` written in place — confirmed, Low

`Write-DirectorySidecar` (`Modules/FileBackup.Engine.psm1:709`) ends with
`Export-Csv -LiteralPath $path`: the latest state's sidecar is truncated and
rewritten in place, never flushed. `Publish-PriorStateSnapshot` (`:5589-5597`)
flushes its COPY before the snapshot's rename, so C36 covered the snapshot side
but not the source of that copy. A power loss after a run returns (or a kill
during the write) can leave the latest state's sidecar short or NUL-filled; the
next run copies it into `Snapshot_<D>`, which is write-once, so that state's
empty directories and folder attributes are lost for good. The latest state
heals on the next run. No file content is involved: the sidecar is advisory and
no restorer fails over it (its own help). Not checked: what either restorer does
with a NUL-filled sidecar line.

Smallest fix: write `DIRECTORIES.csv.tmp`, `Sync-FileToDisk`, rename over (the
`Write-KitFile` pattern), and add `DIRECTORIES.csv.tmp` to
`Test-IsInfrastructureFile`.

## 2. Lock-held exit code — not a defect

Prune returns 2 `staging-busy` on a held lock by design (`Engine.psm1:3105-3119`,
recorded in status.md), and README notes "exit 2 if refused" for Verify's
mutating modes. IF-001 lists "another run holds the lock" under 4 only in its
**Backup** column; its prune/verify column says "Host/dependency I/O failure".
So code and contract agree. Whether a held lock should be 4 ("retry") for every
action, as the Owner just ruled for an unplugged drive, is a policy question.
On HomeHub a backup and a prune of one store run in sequence, so it rarely arises.

## 3. Verify flags a prune leftover — confirmed, Low

`Get-StorageFormFinding` (`Engine.psm1:1606-1615`) lists every data file no row
names as `Unreferenced` and does not skip `*.fbprune.tmp`, while
`Get-SnapshotPrunePlan` (`:1031`), `Get-StoreObjectIndex` (`:4631`) and both
restorers do. Only the next prune's `Invoke-PruneEntrySweep` (`:3179`) removes
the leftover, so after a prune killed while copying, every Verify until the next
prune reports a finding and exits 1. Nothing is lost; the report misleads.

Smallest fix: skip an unreferenced `*.fbprune.tmp` in `Get-StorageFormFinding`
(or report it as prune residue that the next prune removes).
