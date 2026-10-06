# Defect review — the content index holds every snapshot manifest whole; at 16 manifests the run is OOM-killed at step 14, and because step 15 never runs, each failure makes the next one worse

**Found:** 2026-10-05, on the real HomeHub production hub (Ubuntu, `filebackup:local`
container, 7.6 GB RAM, 4 GB swap, real 4 TB library / 8 TB backup drives). **Not
found by testing this repo** — found because the whole hub stopped answering on
2026-10-04 and the post-mortem traced it to this product. Host-side write-up:
HomeHub `docs/FOLLOWUP_HUB_UNRESPONSIVE_RCA_2026-10-04.md`.

**Severity — three different kinds, keep them apart:**

- **Host availability (the one that was noticed).** The container has no memory
  limit, so a `pwsh` growing past RAM takes the whole box into swap thrash for
  hours before the kernel OOM killer fires. On 2026-10-04 the hub was unreachable
  for ~3 h 25 m. The missing limit is the deployment's defect (HomeHub /
  MiniPC-Deployer); the growth is this product's.
- **Every library run since 2026-09-22 has been reported FAILED** (exit 137,
  13 runs). **This is NOT data loss** — see M-4: steps 1–13 complete before the
  kill, so the nightly copy, the final manifest and the snapshot are all written.
- **Correctness, secondary:** snapshot names are wrong (M-4b) and the weekly
  rehash runs every night (M-4c), both because step 15 is never reached.

**Not covered by** `defect-review-2026-09-06-optimize-changefolders-stat-storm.md`.
That review measured this same function on the first incremental run, when **no
snapshots existed yet** (one manifest, 181,721 rows, 26.4 s of allocation). It is a
time review; memory and snapshot count are never measured, and none of its fixes
are implemented.

---

## Summary

| | Finding | One line |
|---|---|---|
| **M-1** | `Get-BackupContentIndex` retains every manifest whole, in `Folders[].Manifest` | Measured **~2.3 KB per row** after `Read-Manifest` → **~420 MB per 182k-row manifest**. 26 manifests ≈ 11 GB on a 7.6 GB host. |
| **M-2** | Almost none of those rows are needed | Of **4,728,887** rows across 26 manifests, **183,236 (3.87%)** carry a `DataPath`, and 181,925 of those are the backup root's. All 25 snapshots together hold **1,311**. Distinct `hash\|length` keys: **159,681**. |
| **M-3** | Whole manifests are retained for the blanking pass, which touches only `DataPath` rows | `Optimize-ChangeFolders` keeps them to blank missing `DataPath`s and rewrite. `Get-SnapshotPrunePlan` keeps them too — so **`prune`, the documented relief valve, would OOM on the same host**. |
| **M-4** | Step 14 dies; step 15 (persist `LastBackupRun`/`LastHashRun`) never runs | **(a)** each failing run still publishes a snapshot, so the count grew **15 → 25** during the failures; **(b)** every one is named for the stale prior date — `Snapshot_2026_09_21_08_04_20_001 … _010`; **(c)** `LastHashRun` stays at 2026-09-21, so the **weekly** rehash (6.5 h over 1.2 TB) has run **every night since the 2026-09-28 week rollover**, stretching runs from 6–7 h to 15–25 h. |
| **M-5** | A snapshot is published almost every night | `Configs/*` service-state archives change nightly, so 25 snapshots in 20 days, most holding 0–9 data files. Q-FB2's premise that growth is "bounded by CHANGE RATE" holds for **disk**; for **memory** each snapshot costs a full library of rows regardless of its change size. |

---

## 1. The measurements

### 1.1 What is on the pool (hub, 2026-10-05, streamed with Python `csv` — read-only)

| Manifest | Folder mtime | Rows | Rows with `DataPath` | Files in folder |
|---|---|---|---|---|
| backup root | 10-04 09:56 | 181,925 | 181,925 | — |
| `Snapshot_2026_09_02_00_00_49` | 09-06 12:34 | 181,721 | 17 | 27 |
| `Snapshot_2026_09_06…` → `_09_08…` (3) | 09-07 → 09-09 | 181,721 | 13–19 | 23–29 |
| `Snapshot_2026_09_11_08_01_07` | 09-12 13:10 | 181,688 | 1,215 | 1,169 |
| `Snapshot_2026_09_12…` → `_09_20…` (9) | 09-13 → 09-21 | 181,911–181,919 | 0–6 | 10–16 |
| `Snapshot_2026_09_21_08_04_20` | 09-22 03:51 | 181,920 | 0 | 10 |
| `Snapshot_2026_09_21_08_04_20_001` → `_010` | 09-23 → 10-03 | 181,921–181,925 | 0–9 | 10–19 |
| **Total (26 manifests)** | | **4,728,887** | **183,236 (3.87%)** | |

Distinct `hash|length` keys across everything: **159,681** — and every one of them
appears on at least one `DataPath` row, so a map built from `DataPath` rows alone
loses no key. The "10 files" floor of a near-empty snapshot is its manifest plus
the restore kit.

### 1.2 What a retained manifest costs

`Read-Manifest` = `Import-Csv` + two `Add-Member` per row (`Length` as `[long]`,
parsed `LastWriteTime`). Measured on the dev PC (pwsh 7, Windows) by importing
`FileBackup.Common.psm1` and calling `Read-Manifest` on a **synthetic** manifest of
the production shape — 181,925 rows, 9 columns, mean `RelativePath` ~100 chars
(production: 98.5), 41.4 MB (production: 37.0 MB). No production paths left the
hub. Holding N manifests, `[GC]::GetTotalMemory($true)` after a full collection:

| Held | Managed | Per row | Working set |
|---|---|---|---|
| 1 | 418 MB | 2,408 B | 753 MB |
| 2 | 835 MB | 2,407 B | 1,231 MB |
| 3 | 1,124 MB | 2,160 B | 1,695 MB |

### 1.3 The arithmetic closes the case

At ~420 MB per manifest, **15 manifests ≈ 6.3 GB** and **16 ≈ 6.7 GB** — and every
kernel OOM record shows `pwsh` killed at **6.63–6.93 GB anon-rss**, the host's
ceiling. The 2026-09-21 run indexed the backup root + 14 snapshots = 15 manifests
and **succeeded** (11.6 h). The 2026-09-22 run had 16 and was killed. Every run
since has been killed at the same point, while (M-4a) adding one more manifest.

The kill size is the host's ceiling, not the function's demand: the demand today
is ~11 GB, and it grows ~420 MB per snapshot.

---

## 2. M-1 / M-3 — where the memory goes, line by line

`Get-BackupContentIndex` (`Modules/FileBackup.Engine.psm1`):

- `$map` is built only from rows with a non-blank `DataPath` whose file exists —
  **small** (≤ 183k location records).
- `$folders.Add([pscustomobject]@{ … Manifest = $manifest … })` — **every row of
  every manifest stays referenced** for the life of the returned index. This is
  the 11 GB.

The consumers that read `Folders[].Manifest`:

| Consumer | Why it holds manifests | What it actually needs |
|---|---|---|
| `Optimize-ChangeFolders` (step 14) | blank `DataPath`s whose file is gone, then `Write-Manifest` the folder | per folder, only the `DataPath` rows to test — and the full row set **only for a folder that changed**, which it can re-read |
| `Get-SnapshotPrunePlan` | `$plan.Manifests[$f.Folder] = $f.Manifest`; the demand set is every row outside the target whose `DataPath` is blank or missing | a **set of demanded keys** (≤ 159,681 strings), not the rows themselves; full rows only for the manifests prune rewrites |

## 3. M-4 — why the failure feeds itself

Pipeline order (AGENTS.md):

```
12. Write the final backup manifest           <- completes on every failing run
13. Complete-ChangeFolder → Snapshot_<prior>  <- completes; staging lock released here
14. Optimize-ChangeFolders                    <- OOM-killed
15. Set-LastHashRun / Set-LastBackupRun       <- never runs
16. Browse view
```

- **(a) The count grows.** Step 13 publishes before step 14 dies, so each failed
  night adds a manifest to the next night's index. 15 → 25 between 09-22 and 10-03.
- **(b) The snapshot names are wrong.** `Complete-ChangeFolder` names a snapshot for
  `$priorBackupDate`, read from `LastBackupRun`, which step 15 never advances. Ten
  snapshots therefore claim to be the state as of 2026-09-21 08:04:20 and are told
  apart only by `_NNN`. `Get-SnapshotDate` tolerates the suffix, so nothing errors;
  a date-driven restore would pick the wrong state.
- **(c) The weekly rehash runs nightly.** `HashRecalcFreq=W` compares ISO weeks with
  `LastHashRun`; stuck at 2026-09-21, every run from the 2026-09-28 week on reports
  `Recalculate=True` and rehashes the whole 1.2 TB source (6.5 h on 10-04). This is
  also continuous read load on a library drive that has been re-enumerating.
- **What it does NOT do:** leave a stale `Temp` lock. Step 13 fences, stops the
  heartbeat and deletes the marker before finalizing, so an OOM at step 14 runs
  after the lock is gone. Confirmed: no `Temp` under the change root on 2026-10-05.

## 4. Fix shape — not built

1. **Index from `DataPath` rows only, streamed.** Read each manifest, add its
   `DataPath` rows to the map, and drop the rows. Do not retain `Folders[].Manifest`.
   The map's size is then O(stored objects), independent of snapshot count.
2. **Consumers re-read what they rewrite.** `Optimize-ChangeFolders` decides per
   folder from the `DataPath` rows, and re-reads + rewrites only a folder whose
   rows actually change. `Get-SnapshotPrunePlan` builds its demand set as a
   `HashSet[string]` of keys; full rows are read only for manifests it publishes.
3. **Persist step 15 before step 14.** The backup's content is final at step 12
   and the snapshot is published at step 13, so `LastBackupRun` is true from that
   point, and `LastHashRun` is true once the rehash in step 5 has finished.
   *(Corrected 2026-10-05 after external review, finding F7.)* An earlier draft
   offered "make step 14 non-fatal like step 16" as an equivalent. **It is not.**
   Step 16's non-fatal handling is a PowerShell `try/catch`, and the observed
   failure is a kernel **SIGKILL**, which no `catch` sees, so step 15 would still
   never run. Only moving the persistence earlier survives the observed
   failure.
   **What fix 3 does and does not stop:** it stops M-4b (stale snapshot names) and
   M-4c (the nightly rehash). It does **not** stop M-4a: under retention NONE
   (Q-FB2), a snapshot is still published on most nights, because `Configs/*`
   changes nightly. The count keeps growing, and only fix 1 makes that growth
   harmless to memory.
4. **A memory test that would have caught it.** A synthetic pool of ~30 manifests
   × ~180k rows (mostly blank `DataPath`) must index under a stated ceiling
   (≤ 1 GB is generous for ~180k map entries). Without it, the next regression is
   found by a host wedging again.
5. **Repairing the mislabelled snapshots** (M-4b) is a separate decision — renaming
   a published snapshot touches every restorer's date logic. Leaving them is safe;
   their contents are correct, only their names are not.

Fix 1 alone makes the current pool index in roughly the size of one manifest
plus 183k map entries. Fix 3 is the smallest change that stops the stale names
and the nightly rehash before fix 1 lands; it does not stop the snapshot count
growing.

6. **Follow-up — interaction with host recovery** *(added 2026-10-05, external
   review finding F3)*. A run killed or rebooted during **steps 7–13** leaves `Temp`
   holding the prior manifest and possibly the only preserved copy of superseded
   bytes. `Get-StagingLockState` classes that as `HoldsContent`: any entry other
   than the run marker (`FileBackup.Engine.psm1:3296`), and only `Empty`/`OwnerStale`
   are reclaimable (`:3259`). Every later run then refuses until a person
   recovers it.
   - The HomeHub hang watchdog will kill or reboot in that window when the host
     is thrashing (HomeHub
     `docs/design/HUB_HANG_WATCHDOG_DESIGN_2026-10-05.md` §4).
   - Making a killed run's `Temp` safely resumable, or re-classifiable without a
     person, is FileBackup work. It is not designed here.
   - A run killed at step 14 (the 2026-10-04 case) is unaffected, because the
     lock is released at step 13.

## 5. What was NOT proven

- **Per-row cost inside the container.** 2.3 KB/row was measured on Windows pwsh 7
  with synthetic rows of the production shape, not in `filebackup:local` on Linux.
  §1.3's agreement with the production kill threshold (15 manifests fit, 16 do not)
  is the cross-check.
- **Peak memory of steps 1–13.** They complete under the current ceiling every
  night, but how much they need is unmeasured. That number decides any interim
  container memory limit: a limit below it would stop the nightly copy at step 10
  instead of the cosmetic step 14.
- **Behaviour under a container memory limit.** .NET sizes its GC heap hard limit
  from the cgroup limit, so a capped run may die with `OutOfMemoryException`
  inside pwsh rather than a kernel SIGKILL. Whether `Invoke-BackupSet` then fails
  the set cleanly, and with which exit code, is untested.
- **C-13 from the 09-06 review** ("probably the snapshot/`Optimize-ChangeFolders`
  interaction") is not advanced by this review.
