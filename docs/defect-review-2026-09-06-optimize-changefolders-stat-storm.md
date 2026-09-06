# Review — an incremental run that changed 17 files took 1 h 28 m, and 0.583 s of it was the change: the whole run decomposed, phase by phase, against its own log

**Found:** 2026-09-06, on the real HomeHub production hub, watching the **first
incremental pass** — the first run after the whole-library backup completed on
2026-09-04. Not found by code reading: found because a run in which **17 files
changed, totalling 38 MB, took 1 h 28 m**, and the question *"where did the time
go, when preserving the changed data took 0.583 seconds?"* had a much more
specific answer than "it is a big library".

**Severity: cost, not correctness.** Nothing is lost, nothing is mis-stored, no
restore is affected. Every byte the run was supposed to preserve was preserved.
The finding is that **the price of a run is set by the size of the library and
not by the size of the change**, and that the dominant term is avoidable by a
change of shape rather than a change of algorithm.

**This matters more now than it did last week.** Until 2026-09-04 no
whole-library pass had ever completed, so no incremental pass had ever run and
this cost had never been paid. It is now paid **every night**, and §4 shows it
grows with the library.

---

## Summary

| | Finding | One line |
|---|---|---|
| **O-1** | `Get-BackupContentIndex` issues one `Test-Path` per manifest row | 181,721 individual existence checks against a FUSE-mounted NTFS volume. Measured **~10 ms each in situ**; that is **~30.5 of the 31 minutes**. |
| **O-2** | A single `readdir` answers the same question in **2.288 s** | The check is only ever "does this name exist in this one directory". One enumeration into a `HashSet` replaces 181,721 syscalls with 159,771 in-memory lookups — the same answer, **~800× cheaper**. |
| **O-3** | The parse is NOT the cost, and a fix should not target it | Measured: `Import-Csv` on the 42,376,713-byte manifest is **2.0 s**; building the map costs **26.4 s** in object allocation. Together **~28 s — 1.5% of the phase.** Anyone optimising the CSV reader is optimising the wrong 1.5%. |
| **O-4** | The phase runs unconditionally, including when nothing changed | `Optimize-ChangeFolders` is step 14 with no guard. `$manifestChanged` gates only whether `Complete-ChangeFolder` publishes a snapshot. A zero-change night pays the full 31 minutes. |
| **O-5** | ~23,531 of the stats are provably redundant before they are issued | 181,721 rows resolve to **158,190 distinct `hash\|length` keys** and 159,771 objects on disk. Duplicate rows share a `DataPath`, so the same path is stat'ed repeatedly within one run. |
| **O-6** | *(related, different phase)* Sanitize reports 1,570 orphaned objects and nothing reclaims them | **44,457,076,469 bytes — 41.4 GiB** of stored objects that no manifest row references, verified unreferenced. Re-reported every run, reclaimed by nothing. |
| **O-7** | **The enumeration O-1 needs has already been built, 30 minutes earlier, and thrown away** | `Test-BackupManifest` builds `$existingPaths` — every file in the pool, in a `New-RelativePathMap` — at step 6. `Optimize-ChangeFolders` at step 14 re-derives exactly that, one `Test-Path` at a time. Passing the map forward makes the O-2 fix nearly free. |
| **O-8** | The source tree is walked **twice**, in full | `Update-SourceManifest` walks it for files (11 m 18.8 s); `Get-SourceDirectoryRecord` then walks it again with `-Recurse -Directory` for the sidecar (8 m 49.4 s) — despite the function's own docstring saying emptiness is "decided from the file rows the walk already produced". |
| **O-9** | **Storing an object is ~15× slower in an incremental run than in a full one, at the same pool size** | 17 objects took 4 m 45 s — 11 to 25 s each, size-independent (a **123-byte** file took 11.1 s), with nothing logged between. The first full pass stored **0.87 objects/s** in its final hour with the pool already ~156k. **Not diagnosed** — but measured well enough to rule out directory scale. |
| **O-10** | Snapshot finalize costs 16 m 39.7 s and is not decomposed here | Observed, cause not isolated. §7 lists what runs in that window. |

**O-1 through O-3 are one finding about one function. O-7 through O-10 are the
rest of the run**, and together they account for the other ~57 minutes.

---

## 1. The measurement

### 1a. Provenance

| | |
|---|---|
| Run | `RunId=1cca4a5d-aeca-42d9-8596-c31275c37b01`, started `2026-09-06T16:36:47Z` |
| Kind | first INCREMENTAL pass; predecessor is the first completed full pass, `2026-09-04T02:02:46Z` |
| Source | `/srv/library`, 181,721 files, 1.10 TiB |
| Backup | `/mnt/backup-drive/library` — 159,771 directory entries, 1.1 TiB, drive 46% full |
| Backup FS | **`fuseblk`** (NTFS-3G) on `/dev/sda1`, 8 TB 5400 rpm USB 3.5" |
| Manifest | `MANIFEST.csv`, **42,376,713 bytes, 181,721 data rows**, every row carrying a non-blank `DataPath` |
| Changed | **17 files**, all under `Configs/`, snapshot `Snapshot_2026_09_02_00_00_49` = 38 MB |

### 1b. Where the 1 h 28 m 25 s went

From the run's own `backup.log` timestamps:

| Phase | Duration | Scales with |
|---|---|---|
| Update source manifest cache | 11 m 18.8 s | source file count |
| Sanitize backup manifest (incl. 1,570 orphan WARNs) | 20 m 31.5 s | backup object count |
| **Preserve the 17 superseded files into the snapshot** | **0.583 s** | **the actual change** |
| Directory sidecar (4,570 rows) | 8 m 49.4 s | source directory count |
| Finalize snapshot | 16 m 39.7 s | manifest size |
| **`Optimize-ChangeFolders`** | **31 m 02.9 s** | **backup manifest rows** |
| — total | **1 h 28 m 25.0 s** | |

**The work the run existed to do took 0.583 seconds — 0.011% of the elapsed
time.** Everything else is fixed overhead that would have been paid identically
had nothing changed at all.

### 1c. The stat cost, measured on the box

3,000 `DataPath` values taken from the head of the real manifest, stat'ed in
place, against 1,126 files on the system disk for comparison:

| Target | Filesystem | Calls | Wall | Per call |
|---|---|---|---|---|
| `/mnt/backup-drive/library` | fuseblk (NTFS-3G) | 3,000 | 57.865 s | **19.3 ms** |
| `/usr/bin` | ext4 on LVM | 1,126 | 2.716 s | 2.41 ms |

**Both figures are inflated and the ext4 one especially so** — the loop forks
`stat(1)` per file, so ~2.4 ms of each is process creation, and a **deep verify
was concurrently reading the same spindle** while this was measured. Neither
number is a clean microbenchmark and neither needs to be: the ratio is ~8× and
the absolute cost is milliseconds where a hash lookup is nanoseconds.

The run's own arithmetic is the better estimate, because it was measured with
the drive to itself: 31 m 02.9 s minus ~28 s of parse and allocation (§1d)
leaves **~1,835 s for 181,721 stats ≈ 10.1 ms each**.

### 1d. What the phase is NOT spending time on

Measured on a copy of the real manifest, PowerShell 7.6.5:

| Step | Cost |
|---|---|
| `Import-Csv` of 42,376,713 bytes → 181,721 rows | **2.0 s** |
| Build the `hash\|length` → list map, with the `PSCustomObject` per entry, **no stat** | **26.4 s** |
| — subtotal | **~28 s, 1.5% of the phase** |

This is the finding that redirects the fix. The CSV reader and the object model
are not the problem; **the syscalls are the entire problem.**

### 1e. The alternative, measured on the same directory

```
$ time ls -U /mnt/backup-drive/library > /tmp/dirlist.txt
real  0m2.288s          entries: 159771
```

**2.288 seconds** to learn the existence of every object in the directory, versus
**~1,835 seconds** to learn the same thing one name at a time.

---

## 2. The mechanism

`Get-BackupContentIndex` (`Modules/FileBackup.Engine.psm1`) builds the index from
manifest rows. Per row:

```powershell
$key  = "$($Row.xxH2Hash)|$($Row.Length)"
$full = Join-Path $Folder $Row.DataPath
if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return }
```

Three properties of this loop together produce the cost:

1. **The hash is never recomputed and no data file is ever opened.** `xxH2Hash`
   and `Length` come straight out of the CSV. This is a metadata-only pass, and
   the review is not asking it to read less data — it already reads none.
2. **`Test-Path` is called once per ROW, not once per distinct `DataPath`.**
   181,721 rows over 158,190 distinct keys and 159,771 objects: the same path is
   checked more than once whenever rows dedup onto it (**O-5**).
3. **Every check crosses a FUSE boundary.** `DataPath` values are flat names in
   one directory — there is no tree to walk and no per-directory locality to
   exploit. The question is always "is this name in this one directory", which
   is the question `readdir` answers in bulk.

`Optimize-ChangeFolders` then adds a `Test-Path` before each `Remove-Item`, and
one per change-folder row in the blanking loop. The latter is cheap in practice
because it skips blank `DataPath` rows immediately and a sanitized snapshot's
rows are nearly all blank — which is itself evidence the design already knows
the difference between a row that needs checking and one that does not.

---

## 3. The fix

> **READ §6 BEFORE IMPLEMENTING THIS.** The enumeration described below already
> exists at step 6, 30 minutes earlier in the same run, and is thrown away
> (**O-7**). On the backup path the fix is to *pass that map forward*, not to
> build a second one. What follows is still the right shape for callers that
> arrive without one — `-Action Verify`, a standalone `Optimize` — and it is the
> fallback the parameter needs.

**Replace per-row `Test-Path` with one enumeration per folder.** For each folder
about to be indexed:

```powershell
$present = [System.Collections.Generic.HashSet[string]]::new(
    [string[]](Get-ChildItem -LiteralPath $Folder -File -Force -Name),
    [StringComparer]::OrdinalIgnoreCase)   # match the volume's semantics
```

then in `addToMap`, `if (-not $present.Contains($Row.DataPath)) { return }`.

Same answer, same skip semantics, same order of results. **~1,835 s → ~2.3 s per
folder**, and O-5 disappears for free because a `HashSet` hit costs nothing to
repeat.

Four things a patch has to get right, none of them optional:

- **Case sensitivity must match the volume, not the platform.** The reference
  deployment is NTFS-via-FUSE (case-insensitive) reached from Linux
  (case-sensitive APIs). `Test-Path` inherits the volume's behaviour today; a
  `HashSet` with the wrong comparer would silently change which rows survive.
  This is the one way the change could become a correctness bug, so it wants a
  test on both.
- **Files must be filtered from directories.** `-PathType Leaf` currently
  excludes a directory that happens to share a `DataPath` name; `-File` above
  preserves that.
- **The enumeration is a point-in-time snapshot.** Today each row is checked
  when it is reached; afterwards, all rows are judged against one listing taken
  at the start. Only a concurrent writer could tell the difference, and the
  staging lock exists to exclude exactly that — but it is a real semantic change
  and should be stated in the commit rather than discovered later.
- **Do not also rewrite the CSV reader.** §1d measured it at 1.5%.

**The same treatment applies to the sanitize phase (20 m 31.5 s)**, which
enumerates the same directory to answer a closely related question. The two
phases together are ~51 of the 88 minutes.

### 3a. And consider gating the phase (O-4)

`Optimize-ChangeFolders` is called at step 14 with no condition, and `Changed
files count` is not even computed until after it returns. With the fix above the
phase becomes cheap enough that gating it is optional; without the fix, skipping
it when `$manifestChanged` is false and no change folder was touched would
return 31 minutes a night on its own. Gating alone is the smaller and more
surgical change; the enumeration is the one that scales.

---

## 4. Why this gets worse

The cost is `O(rows in the backup manifest)`, and that number only grows —
nothing prunes a manifest row. Two independent contributors on this deployment:

- **The library grows.** Every added file is another row, another stat, forever.
- **Config archives churn nightly and cannot dedup.** The 17 changed files are
  `*.tar.zst` service-state archives rebuilt every night. tar embeds mtimes, so
  the bytes differ every run even when the contents do not — the measured
  evidence is `caddy.files.tsv`, where 7 of 26 tracked entries changed and every
  one was a certificate-metadata `.json` or a `last_clean.json` timestamp, with
  the certificates and keys themselves untouched. **Dedup cannot collapse them,
  and nothing prunes a snapshot**, so this is ~38 MB of new snapshot every night
  — on the order of **14 GB/year** — each byte of which is more rows to stat.

---


---

## 5. The whole run, decomposed from its own log

§1b listed the phases. This section says what each one *is*, derived by gap
analysis: every consecutive pair of log lines in `backup.log`, sorted by the
interval between them. Every number below is a measured gap, not an estimate.

| Gap | Ends at | Phase | Diagnosed? |
|---|---|---|---|
| 678.8 s | `Sanitizing backup manifest` | `Update-SourceManifest` — full source walk | necessary, but see **O-8** |
| 778.6 s | first orphan `WARN` | `Test-BackupManifest` — pool enumeration | **yes — O-7** |
| ~70 s | `Saving pre-backup manifest` | emitting 1,570 orphan WARNs | cheap; the WARNs are ~2 ms apart |
| 77.2 s | `New or changed files: 24` | `Write-Manifest` of 181,721 rows to staging | inherent to a full-manifest write |
| 285 s | last `Stored object` | storing **17 objects** | **no — O-9, anomalous** |
| 529.4 s | `Directory sidecar: 4570 row(s)` | `Get-SourceDirectoryRecord` — **second** source walk | **yes — O-8** |
| 999.7 s | `Snapshot finalized` | `New-ReconstructScript` + `Complete-ChangeFolder` | **no — O-10** |
| 1862.9 s | `Optimize-ChangeFolders completed` | 181,721 `Test-Path` | **yes — O-1** |

The two facts worth carrying out of this table: **the phase that did the work
took 0.583 s**, and **the three largest phases are all whole-library scans that
would have cost the same had nothing changed.**

---

## 6. O-7 — the pool listing is built at step 6 and re-derived at step 14

This is the most actionable finding in the document, and it makes §3's fix
smaller rather than larger.

`Test-BackupManifest` (step 6) already does the right thing. Its comment says so
— *"SR-064 (LLR-062): ONE pass over the disk and ONE over the rows"* — and the
code matches:

```powershell
$existingPaths = New-RelativePathMap
$rootFull = (Resolve-Path -LiteralPath $FolderRoot).Path
Get-DataFile -Root $FolderRoot |
    ForEach-Object { $existingPaths[$_.FullName.Substring($rootFull.Length).TrimStart('\','/')] = $true }
```

**That map is the exact thing `Get-BackupContentIndex` spends 31 minutes
rebuilding at step 14**, one `Test-Path` per row, with worse locality. It is
already keyed by `New-RelativePathMap`, which the comment notes exists precisely
so "path keys compare the way the local filesystem does" — which is also the
answer to the case-sensitivity hazard §3 flags. The comparer question is already
solved in this codebase; it just is not reused.

`$existingPaths` is local to `Test-BackupManifest` and discarded when it
returns. Returning it alongside `$backupDb`, and threading it into
`Get-BackupContentIndex` as an optional "already know what is on disk"
parameter, converts O-1 from a rewrite into a parameter pass. The fallback
enumeration in §3 is still worth having for callers that arrive without one
(`-Action Verify`, a standalone `Optimize`), but the backup path would not use
it.

**This also halves the remaining cost**, because `Get-DataFile`'s own walk is
where the 778.6 s goes: `Get-ChildItem -Recurse -File -Force` piped through a
`Where-Object` calling `Test-IsInfrastructureFile` per entry. `-File` forces the
enumerator to classify every entry, and on a FUSE mount whose `readdir` cannot
be trusted to carry `d_type` that is a `stat` per entry — 159,771 of them at
**~4.9 ms**. That is cheaper per call than O-1's ~10.1 ms because it walks in
directory order rather than manifest order, which is the same locality effect
from the other side.

Whether that walk can be made cheaper is a separate question from O-7, and a
smaller prize: **one** stat-per-entry pass over the pool per run is defensible.
**Two, the second in random order, is not.**

---

## 7. O-10 — the 16 m 39.7 s before `Snapshot finalized`

Not decomposed, and this document does not guess at it. What runs in that window,
from the step-13 call site:

- `New-ReconstructScript -BackupRoot ... -ChangeRoot ...`
- `Complete-ChangeFolder`, which iterates all 181,721 staging rows, calls
  `Write-Manifest` on them, copies seven reconstruct artifacts
  (`RECONSTRUCT.*`, `FileBackup.Common.psm1`, `System.IO.Hashing.dll`,
  `RECONSTRUCT.paths.json`), and finishes with one `Rename-Item`.

A calibration point from the same run: the step-7 `Write-Manifest` of the same
181,721 rows to staging took **77.2 s**. So one full manifest write is ~1.3
minutes, and the phase costs thirteen of those. **The gap between 77 s and 999 s
is the thing to measure**, and this review did not.

---

## 8. O-9 — storing an object costs 11–25 s in an incremental run, and 1.1 s in a full one

The 17 objects were stored between 17:03:33 and 17:08:40. Consecutive
`Stored object` lines are 11 to 25 seconds apart with **nothing logged between
them**, and the interval does not track file size:

| Object | Source | Bytes | Gap before |
|---|---|---|---|
| `ExF7zEE9…_4B.7z` | `Configs/finance.files.tsv` | **123** | 11.1 s |
| `KmgrAAaDo…_B3.7z` | `Configs/actual.files.tsv` | 514 | 11.3 s |
| `LtCzBHGBw…_6K.zst` | `Configs/finance.tar.zst` | 245 | 11.3 s |
| `TK9Md3Rzy…_4B.7z` | `Configs/uptimekuma.files.tsv` | **123** | 25.8 s |
| `iNMMswXeP…_BXBz.zst` | `Configs/technitium.tar.zst` | 1,761,527 | 22.8 s |

A 123-byte file taking 11.1 s, and another taking 25.8 s, rules out compression
and I/O volume. Every one of these rows logged `BelowFloor`, so the
compressibility probe did not run and is not the cost either.

**The obvious explanation — inserting into a directory of 159,771 entries on
NTFS-3G — is ruled out by the first run's own history.** Counted from the
journal, the first full pass stored **3,132 objects in its final hour**
(2026-09-03 20:00–21:00), with the pool already at ~156k entries: **0.87
objects/s**. The incremental run managed **17 in 285 s — 0.06/s**. Same pool,
same volume, same build, **~15× apart**.

So the cost is not pool scale and not object size. It is something about the
shape of a run that stores a handful of objects rather than a stream of them —
per-object work that the full pass amortised or pipelined and the incremental
pass pays in full, unlogged. **Candidates not distinguished by this data:** a
flush or `fsync` per object, an external compressor process spawned per object,
or a re-read/verify step. Isolating it wants one instrumented incremental run
with timing around the store call, which is a smaller experiment than it looks
because 17 objects is the whole sample.

**Why it matters more than 4 m 45 s suggests:** every nightly run stores this
same handful of config archives (§4), so this is a nightly cost, and it is the
one term here that scales with *changes* rather than with library size. A night
with 500 changed files would pay it 500 times.

---

## 9. What the fixes are worth, together

Ordered by measured saving against the 1 h 28 m 25 s run:

| | Fix | Saves | Confidence |
|---|---|---|---|
| **O-7 + O-1** | thread `$existingPaths` from step 6 into step 14 | **~31 min** | high — the map already exists and is already correctly compared |
| **O-8** | capture directories during the source file walk instead of walking again | **~8.8 min** | high — the docstring already describes the intended shape |
| **O-4** | skip `Optimize-ChangeFolders` when nothing changed | up to 31 min, overlaps O-7 | high, and much smaller than O-7 |
| **O-10** | unknown, 16.7 min available | ? | needs measurement first |
| **O-9** | unknown, 4.8 min on this run, scales with change count | ? | needs an instrumented run |
| **O-6** | reclaim 41.4 GiB and stop re-reporting it | not time, space | high |

**O-7 and O-8 alone are ~40 of the 88 minutes**, both are shape changes rather
than algorithm changes, and both are changes the surrounding code already
believes it has made — SR-064 says one pass over the disk, and
`Get-SourceDirectoryRecord`'s docstring says the walk is not repeated. In each
case the intent is documented and the implementation does it twice.

## 10. O-6 — 41.4 GiB of orphaned objects, re-reported nightly, reclaimed by nothing

The sanitize phase emitted **1,570** `File exists in backup folder but not in DB`
warnings. Verified rather than assumed: sampled orphans return **0** matches in
`MANIFEST.csv` while a control row returns 1. Total **44,457,076,469 bytes
(41.4 GiB)**.

Provenance is almost certainly the two runs killed by signal during bring-up
(2026-08-30 14:34–14:37 and 2026-08-31 09:25–22:53): objects written before the
manifest that would have recorded them was ever finalized. That is the expected
debris of a mid-copy kill and is not itself a defect.

The defect is what happens next: **the condition is detected on every run,
reported 1,570 times into the run log, and acted on by nothing.** The bytes are
unreferenced, so they will never be restored and never pruned — `prune` operates
on snapshots, not on loose objects. They also inflate every phase that
enumerates the directory, so they are paying rent in the very pass that finds
them.

Worth having, in rough order of value:

1. A **count and total size** in the run summary instead of 1,570 individual
   WARN lines — one line that says how much space is unreachable.
2. An **explicit reaper with a dry run**, so reclaiming is a decision an operator
   makes with a number in front of them, rather than a hand-deletion in a
   directory where hand-deletion is otherwise the cardinal sin.

---

## 11. What this review does NOT claim

- **Not a data-loss finding.** The delete in `Optimize-ChangeFolders` is guarded
  by `-not $_.IsBackup`; it can only remove a duplicate from a change/snapshot
  folder, never from the backup tree. That guard was read and is correct.
- **Not an argument against deduplication.** Collapsing bytes shared between the
  backup and its snapshots is what bounds growth in a design where nothing is
  ever pruned. The mechanism is right; the lookup strategy is what costs.
- **Not a claim that 88 minutes is wrong for this hardware.** A 5400 rpm USB
  spindle carrying 1.1 TiB across ~160k objects is entitled to be slow. The
  claim is narrower and measured: **~51 of those 88 minutes are spent asking
  questions that one `readdir` per directory already answers.**
- **Not measured on other filesystems.** The 8× FUSE penalty in §1c is specific
  to NTFS-3G. On ext4 or NTFS-native the absolute win would be smaller — but
  159,771 syscalls versus one enumeration is a favourable trade on any of them.
