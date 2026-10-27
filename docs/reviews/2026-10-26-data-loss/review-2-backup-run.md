# Review slice: the backup run (Claude, main session) — BoundedRebuild @ 7532b86

## 1. What was done
Read `Invoke-BackupSet` and every step on the run's path: `Resolve-BackupSetPaths`, `Assert-StoreVolumePresent`,
`Read-PriorStateForRun`, `Clear-InterruptedRunResidue`, `Get-PriorBackupDate`, `Read-BackupState`/`Set-BackupStateField`,
`Get-StoreObjectIndex`, `ConvertFrom-StoredObjectName`, `New-ReconstructScript`, `Publish-PriorStateSnapshot`,
`New-BackupRunContext`, `Invoke-LibraryCapture`, `Invoke-SourceFileCapture`, `Copy-FileWithHash`, `Publish-StagedObject`,
`Get-LatestObject`, `New-CapturedRow`, `ConvertTo-FrozenRow`, `Get-SortedManifestRow`, `Publish-LatestState`,
`Test-StateChanged`, `Remove-UnchangedSnapshot`, `Move-SupersededObject`, `Test-HashRecalcDue`; in Common `Write-Manifest`,
`Read-Manifest`, `ConvertFrom-ManifestDateString`, `Compress-/Expand-FileWithSevenZip`; the restorers' header guards only.
Ran two repros in the scratchpad (nothing in the repo): (a) overwriting a `System.IO.Hashing.dll` that another pwsh
process has loaded; (b) per-file cost of `FileStream.Flush($true)` before a rename, on NVMe and on a SATA HDD.

## 2. Where the artifact is
This file.

## 3. Checked and found clean
- Kill-safety ordering of steps 1-9 (agrees with reviews 1-5): snapshot before first checkpoint; final manifest before
  `LastBackupRun`; superseded moves after both; Incoming/Building_* hold no only-copy.
- State file is temp + rename; an unreadable one is set aside and the manifest's time used.
- Time comparison is robust: `LastWriteTimeStr` is ISO 'O' with offset, parsed back to local; DST/TZ changes compare equal.
- Source-gone / source-emptied mid-run (C24/C27), retry pass (R12), disk-full rethrow (C3), frozen rows keep objects.
- Dedup keyed by name prefix; a case-insensitive filesystem merges two names only if ~110 bits of hash collide: negligible.
- A blank `LastWriteTimeStr` cannot reach the compiled writer's throw: `ParseExact` refuses it first (loud exit 2).

## 4. Findings

### F1 — High: nothing is flushed to disk before it is named; after a power loss or OS crash the store can name objects (and a snapshot's manifest) whose bytes never reached the disk, and the run trusts names forever
- **Where:** `Modules/FileBackup.Engine.psm1:4371-4387` (`Copy-FileWithHash`: `Dispose()` only, no `Flush($true)`),
  `:4520-4524` (`Publish-StagedObject` renames it to its content name), `:4499` (7-Zip writes the archive; nothing flushes it),
  `Modules/FileBackup.Common.psm1:1365-1406` (`Write-Manifest`: no flush of `MANIFEST.csv.tmp` before the rename),
  `:4976-4985` (`Publish-PriorStateSnapshot`: manifest + kit written, then `Building_D` renamed to `Snapshot_D`).
  No `Flush(true)`/fsync exists anywhere in Modules, Reconstruct.ps1 or reconstruct.sh.
- **Filesystem behaviour relied on:** journaling filesystems make the *rename* durable on their own schedule, independent of
  the *data*. ext4 (default `data=ordered`, delayed allocation): a file written and then renamed to a NEW name can come back
  0 bytes long after a crash within the writeback window (~5-35 s); `auto_da_alloc` covers only rename-*over*-an-existing
  file and truncate — high confidence (documented ext4 behaviour; the 2009 zero-length-file issue). NTFS journals metadata,
  not data: a renamed file whose data pages were still dirty comes back at full length reading as NULs (valid-data-length)
  — medium-high confidence (the widely reported "file full of NUL bytes after a crash" pattern; git hit the same with loose
  objects and added `core.fsync`).
- **Steps (ext4, the container):** a long run (initial backup, a big import) stores objects continuously and checkpoints the
  latest manifest every >=60 s (R13). Power is cut 10 s after checkpoint C. The checkpoint replaced `MANIFEST.csv` by
  rename-over (auto_da_alloc: durable) and names objects stored in the ~30 s before C, which were renamed to new names
  (not protected): they come back 0 bytes. Next run: `Get-StoreObjectIndex` (`:4080-4094`) indexes them by name and never
  compares `FileLength` with the name's length; each source file looks unchanged against its row → `Kept`
  (`:4606-4612`) → the row keeps naming a 0-byte object, run after run. Plain Verify does not judge object bytes; only
  `-Deep` (`Get-StoredObjectVerdict`) does. A restore then fails that file (`ContentMismatch`, exit 1; for a `.7z` object
  the own-file extract failure is classed 4).
- **Steps (NTFS):** the same, with the object at full length reading as NULs — invisible to any listing.
- **Even the documented repair keeps the damage:** if the checkpoint itself came back unreadable (NUL header → exit 2) and
  the person moves it aside as the message says, the rebuild hashes each source file and finds the damaged object *by name*
  (`Get-LatestObject`), so it is reused. And `Publish-StagedObject:4520-4521` drops a freshly staged good copy whenever an
  object already sits at that name — the "same name = same bytes" assumption.
- **Snapshot variant:** `Snapshot_D/MANIFEST.csv` is written to a new name and then the folder is renamed; on a short run the
  final latest manifest (rename-over, protected on ext4) can be durable while the snapshot's manifest comes back 0 bytes /
  NULs. State D — including files the user deleted since D — is then gone: the latest has moved on, and the objects moved
  into `Snapshot_D` in step 8 are named by no manifest. The restorer refuses that snapshot loudly (header check, exit 2),
  but the state is not recoverable. Window: seconds on a short run, so lower likelihood than the object case.
- **Permanent or self-healing:** permanent for any version whose source changes or is deleted before someone runs
  `-Action Verify -Deep` (C4 then moves the bad object aside and the next run re-stores it — only if the source still has
  it). Nothing prompts that Verify after an unclean shutdown.
- **Why not contrived/accepted:** a power cut or OS crash during a multi-hour backup is ordinary; it is not "a name that lies"
  by hand-editing — the tool itself publishes the name before the bytes are durable. The plan's accepted bit-rot case is
  damage after a clean write; AGENTS.md §4 accepts only that the *newest manifest write* may be lost, which self-heals.
- **Suggested fix (the Owner's cost call; measured here):**
  1. *Near-free:* `Flush($true)` on `MANIFEST.csv.tmp` before its rename (Write-Manifest), on the state-file temp, and on the
     snapshot's files before `Building_D` → `Snapshot_D`. One flush per checkpoint / per run.
  2. *Objects:* `$out.Flush($true)` in `Copy-FileWithHash` before `Dispose`, and the same on the `.7z` (open it and
     `Flush($true)`) before the rename. Measured `Flush($true)` + rename, 64 KiB files: NVMe 1.75 → 3.18 ms/file (+1.4 ms);
     SATA laptop HDD 1.39 → 50.7 ms/file (+49 ms). So ~25 s on a 500-new-file nightly run to an HDD, ~2.5 h extra on a
     180,000-file initial backup to an HDD. On Linux a single `sync -f <store>` (syncfs) before each manifest publish
     would make every earlier object durable for one call per checkpoint instead.
  3. *Zero-cost detection (partial):* in `Get-StoreObjectIndex`, do not index a raw object whose file length differs from
     its name's length, or a 0-byte `.7z`; treat it as damaged (move to `Verify/`, as C4 does), and let
     `Publish-StagedObject` replace rather than drop when the object at that name is such a file. Catches ext4's
     zero-length mode; does not catch NTFS NUL-fill.

### F2 — Medium: every run overwrites the kit in the backup root in place; a restore session that loaded the bundled DLL makes every backup stop with 4
- **Where:** `Modules/FileBackup.Engine.psm1:2915-2966` (`New-ReconstructScript`, called unguarded at `:6154`).
- **Repro (run):** another pwsh process loads `<kit>\System.IO.Hashing.dll` (what `RECONSTRUCT.ps1` run from the backup root
  does — Common's `Get-XxHashDllPath` prefers the DLL beside the module); `Copy-Item -Force` over it fails: "The process
  cannot access the file ... because it is being used by another process."
- **Steps:** the user test-restores (README recommends it) by running `E:\Backup\RECONSTRUCT.ps1` inside an interactive pwsh /
  VS Code terminal and leaves it open; or a long restore is still running at the scheduled time. Each nightly run then
  throws at step 3, the outer catch reports "did not finish ... it stopped" and returns 4, before any file is captured —
  every night until that session exits.
- **Also:** `Copy-Item -Force` truncates and rewrites in place, so a kill (or power loss) mid-copy leaves a truncated
  `RECONSTRUCT.ps1` / `FileBackup.Common.psm1` / DLL in the latest root until the next run, and the same run copies the
  kit into `Snapshot_D` right after. Recoverable (any snapshot's kit restores), so this half is Low.
- **Permanent or self-healing:** self-healing once the session closes; no data lost, but backups silently stop happening
  (exit 4 reads as "retry later").
- **Suggested fix:** copy a kit file only when its bytes differ from the template (length + hash, or the KitRevision marker),
  and then via temp file + rename. An unchanged kit (the normal case) is then never touched.

## 5. What was not done
- No Pester / Run-All. Power-loss behaviour was reasoned from documented filesystem semantics, not reproduced on a cut-power
  rig. Retention, Verify and the restorers were left to the other two reviewers.

## 6. Open questions / ruling questions
- **Ruling question (C2):** a source that is empty when the walk starts warns and exits **0**. On Linux/the container a
  source drive that failed or is not mounted shows as exactly that (an empty mount point / bind mount). The run moves the
  whole library into a snapshot, the latest restores empty, NagLight shows green, and a caller's age-based retention can
  later prune the only snapshot holding the library. C2 ruled "warn, don't refuse"; the exit code was not ruled. Should it
  be 1 (or 4, like C27's mid-run case) so it is seen?
