# Review — `Optimize-ChangeFolders` spends 98% of its 31 minutes asking a FUSE mount, one file at a time, whether files it could have listed in 2.3 seconds exist

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

## 5. O-6 — 41.4 GiB of orphaned objects, re-reported nightly, reclaimed by nothing

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

## 6. What this review does NOT claim

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
