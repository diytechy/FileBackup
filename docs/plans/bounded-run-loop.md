# Bounded run loop: the Owner's architecture for the backup run

*Branch `BoundedRebuild`, 2026-10-24. Status: rulings recorded; the calls in
§11 await the Owner's confirmation. Nothing here is implemented.*

This branch rebuilds the spine against an architecture the Owner fixes up
front. The aim is to **bound the run loop**: a corner case gives a warning and
the run carries on, instead of each corner case getting its own recovery path.
The design below came from three rounds of questions with the Owner on
2026-10-24. Answers the Owner gave directly are **rulings**. Recommendations
the Owner accepted as a group ("I'm good with your other recommendations")
count as rulings too. Calls made inside a ruling's limits are listed in §11.

`DirectRebuild` is cited for its **rulings only** (P-01, P-03, P-13). None of
its rows are adopted; this branch stays the independent comparison. The
complexity this design removes is mostly DirectRebuild's recovery machinery:
the 27-step staging sequence (LLR-162), the owner record and its refresh timer
(LLR-080), leftover classification and reclaim (LLR-017, LLR-088, LLR-124,
LLR-125), and restores that wait for a writer to settle (LLR-123, LLR-159).

Terms: an **object** is a stored data file named `<hash22>_<len><ext>`
(SR-069 grammar). **Latest** is the backup root (`BackupPath`). A
**snapshot** is a `Snapshot_<date>` folder under `ChangePath`.

## 1. Rulings

| # | Ruling |
|---|---|
| R1 | **Corner cases warn; they never get a recovery path.** A file the run cannot capture keeps its previous row and is named in the log; the run completes everything else. Backups run when files are not in use, so these cases are rare. The run stops only where going on could store wrong content or lose a state (§6). |
| R2 | **Concurrent runs are unsupported.** One OS lock, `<ChangePath>/Temp.lock`, opened with no sharing and never deleted (same path as today). If it is held, the run stops and touches nothing. There is no owner record, heartbeat, stale time or reclaim. Compare DirectRebuild P-13. |
| R3 | **One record.** The latest `MANIFEST.csv` is also the change-detection record. There is no source-side record, and nothing is written into the source. See §2 for why this costs no detection. |
| R4 | **The manifest is preserved:** the 9-column schema, the object-name grammar, a flat pool at `BackupPath`, and `Snapshot_<date>` under `ChangePath`. The new engine continues the existing HomeHub store in place, unless that turns out costly (§8). |
| R5 | **No `.meta`.** Manifests are still published by temp file plus rename (as today, SR-082). The run deletes the latest state's old `MANIFEST.csv.meta` the first time it writes the latest manifest. Otherwise every kit, old and new, refuses the latest state with exit 3. Snapshot `.meta` files stay, and stay valid, because of R6. |
| R6 | **Snapshots are write-once.** Once `Snapshot_<D>` is published, nothing rewrites its manifest. A `DataPath` that goes stale (re-added content moved back to latest, a duplicate moved out) is resolved by the kit through the object's name (§7). |
| R7 | **A snapshot follows any row change.** When the final manifest differs from the prior one in any row (a path added, removed or renamed, or a change to content, size or modification time), the prior state becomes `Snapshot_<prior run's completion date>`. A run with no row differences makes none. Bytes move only for objects that no row of the new latest manifest uses. The trigger cannot be "an object moved": a rename, a deleted duplicate, an added duplicate or a time-only change moves no object, and the prior state would be lost from history. |
| R8 | **One volume and one mount.** `BackupPath` and `ChangePath` sit on one volume and one mount, so every move is a rename (DirectRebuild P-13). The run checks this at the start with a test directory rename and refuses the set if it fails. On Linux, a rename across two bind mounts fails even on one filesystem. .NET's `File.Move` hides this by falling back to copy plus delete, so the check uses a directory rename, which does not fall back. |
| R9 | **A backup run never deletes a stored object.** Duplicates are not deleted at all: `-Action Verify` moves them into `<ChangePath>/Verify/`, and the Owner empties that folder by hand. |
| R10 | **Backup hash validation and duplicate cleanup are not part of the run.** They belong to `-Action Verify -Deep` (DirectRebuild P-03). This means fewer disk writes per run. |
| R11 | **The re-read schedule is unchanged:** `HashRecalcFreq`, using calendar periods (DirectRebuild P-01). |
| R12 | **Retrying a locked or unreadable file.** The run keeps each failed file's last attempt time in memory. After the main loop, it retries each one no sooner than 60 s after that file's last attempt, at most 3 attempts in all. After that the file gets a warning and its old row stays (SR-091). |
| R13 | **Progress checkpoints.** The latest `MANIFEST.csv` is saved about every minute while rows are changing, within the limits in §5. After an interruption the next run is a separate backup, but it keeps the progress. Any imperfection in a checkpoint is caught by the next run's compare. |
| R14 | **Feedback reaches where it needs to go** (the Owner had no preference on exit codes). The table in §6 was chosen so the scheduler, HomeHub and mail each see a missed file. |

## 2. Why one record costs no detection (R3)

The source-side record is a cache of three fields per path: `Length`,
`LastWriteTime` and `xxH2Hash`. Today `Compare-SourceToBackup` compares
exactly those three fields with the backup manifest's row
([FileBackup.Engine.psm1:5778](../../Modules/FileBackup.Engine.psm1#L5778)).
Every corruption detector the product has is a hash compared against the
backup row or an object name, and none of them needs a second record:

| Corruption | What detects it |
|---|---|
| Source file rots; size and time unchanged | The scheduled re-read: the hash differs from the row, the new content is stored, and a warning is logged (SR-105). |
| A stored object rots | `-Action Verify -Deep` (the object's hash against its name), and every restore (SR-056). |
| The latest manifest loses rows | The next run sees those files as new, hashes them, and finds their objects by name. The latest manifest therefore repairs itself. |
| A snapshot manifest loses rows | Nothing. With `.meta` gone (R5), this is the accepted gap, and it needs damage to a file written once. |

A second record also brings a failure mode of its own. Today's copy does not
hash the bytes it writes (`Copy-SourceFileToBackup`,
[FileBackup.Engine.psm1:6000](../../Modules/FileBackup.Engine.psm1#L6000)).
So if the source record holds a wrong cached hash for an unchanged-looking
file, the run stores that file's bytes under a name for a different hash, and
only the restore's check catches it. Two records can disagree; one record
cannot. Losing the latest manifest costs one full re-hash, which is slow but
correct.

## 3. The run, in order

1. **Lock and clean up.**
   - Take the lock (R2); if it is held, stop with 4.
   - Run the one-mount check (R8).
   - Delete what a killed run left behind: `<ChangePath>/Incoming/` (temp copies) and any `Building_*` folder. Neither ever holds the only copy of anything.
2. **Read and index.**
   - Read the latest manifest and the prior run's completion date D (`FileBackupState.json`, `LastBackupRun`).
   - List latest and every `Snapshot_*` folder once. Index every object by its name, keyed on hash and length.
   - Never read snapshot manifests: holding them all caused the 6.6 GB OOM ([defect review 2026-10-05](../defect-review-2026-10-05-content-index-memory.md)).
   - Any name found in more than one folder is a duplicate; it is noted and left for Verify (R10).
3. **Publish the prior state first** (skipped on a first backup). If `Snapshot_D` does not exist, copy the latest manifest and the restore kit into `Building_D`, then rename it to `Snapshot_D`.
   - The snapshot restores at once, because every object it needs is still in latest or an older snapshot.
   - This must come before the first checkpoint (step 4), or the checkpoint would overwrite the prior state's only record.
   - If `Snapshot_D` already exists, an interrupted run published it; keep it as it is. It holds the true prior state, and the checkpointed manifest is only a mix.
4. **Library loop.** For each file in the source:
   - Size and time match its row, and no re-read is due: keep the row.
   - Otherwise, hash it using the tiers in §4. If the object exists in latest, reuse it. If it exists only in a snapshot, move it back into latest by rename. If it doesn't exist, store it.
   - A file that is locked or unreadable is set aside for step 5, keeping its old row.
   - Save `MANIFEST.csv` as progress (R13, limits in §5).
5. **Retry pass** (R12).
6. **Finish latest.** Write the final `MANIFEST.csv` and the latest kit, then record this run's date as `LastBackupRun`.
7. **Discard an unneeded snapshot.** If no row differs from the prior manifest and this run built `Snapshot_D` in step 3, delete it. It holds no objects yet, so R9 is untouched.
8. **Move superseded content.** Move every object in latest that no row of the final manifest uses into `Snapshot_D`.
9. **Release the lock.**

The browse view (SR-062), when turned on, is rebuilt after step 8 as today. A
failure there is a warning.

## 4. Hashing and temp copies

Every stored object is written by **hashing the bytes during the copy** to a
temp file, then renaming it to the name of its own hash. So an object's name
always matches its bytes, even if the source file changed in between. The
Owner had accepted that risk as unremediable; this design removes it.

Size and time are compared before and after the read. A difference means the
file was being written: it is treated as a locked file (R12), and its old row
stays.

Where the temp copy goes depends on how likely the content is to be new. The
length test costs nothing, because object names carry the length:

| The file is | Likely new? | Read |
|---|---|---|
| A path in the manifest whose size or time changed | Yes | Hash while copying to `<ChangePath>/Incoming/`, then rename into latest. One read. |
| A new path, and no stored object has its exact length | Certainly | As above. |
| A new path, and a stored object has its length (a rename, move or copy), and the file is small | Probably not | Hash while copying to the container or host temp. If it is new, move the copy to the backup; if not, delete it. One read. |
| As above, but too big for the temp | Probably not | Hash in place. Read it again (step 1 of this table) only if it turns out to be new. |
| A scheduled re-read of an unchanged-looking file | Almost never | Hash in place. Read again only if the content changed (SR-105, with a warning). |

Nothing is written into the library. The container mounts the source
read-only (`/source:ro`), and the walk would pick up any temp file there.
"Too big for the temp" means more than 256 MiB, or more than half the temp's
free space (call C7). The container's `/tmp` is a tmpfs in RAM, half the host
by default, and that is what failed in C-12.

**A second read is rare in normal operation.** It happens only for a new path
whose exact length matches a different stored object, or for a re-read that
finds changed content. Today every new or changed file is read twice: once to
hash it at step 5 and again to copy it at step 10. DirectRebuild's LLR-149
keeps that.

**Compression** (SR-081, unchanged) works from the stable temp copy: the run
compresses the temp file to a temp `.7z` file and renames that into place.

## 5. Checkpoint limits (R13)

`Write-Manifest` takes about 20 s for a 180,000-row manifest (26.4 MB) on the
development machine, measured 2026-10-24 over three runs. HomeHub's latest
manifest is about that size, and the mini PC is likely slower. A flat
one-minute checkpoint would therefore spend about a third of the run writing
manifests. So:

- a checkpoint is written only when rows have changed since the last one; a
  run over an unchanged library writes none;
- the next checkpoint is due after 60 s or after ten times the last write's
  duration, whichever is longer, so checkpoints never take more than about
  10% of the run;
- the implementation should use a streamed CSV writer rather than
  `Export-Csv`. The writer is an implementation choice; the manifest format
  does not change.

## 6. Outcomes

| Exit | Meaning | Who sees it |
|---|---|---|
| 0 | Every file was captured. | |
| 1 | The run completed, but one or more files were not captured. Each one is named in the log and the mail. | HomeHub NagLight: warn (IF-001: "partial, no data lost"). |
| 2 | Refused before changing anything; a person must fix it. Causes: the configuration, a missing tool, the source root missing, the one-mount check failing, or a latest manifest that cannot be read (move it aside to force a rebuild; the snapshots are untouched). | NagLight: error. |
| 4 | Stopped by a host problem; retry later. Causes: the lock is held, the backup volume is full, or the backup volume disappeared. | NagLight: warn and retry. |

A backup never returns 3 any more, because there is no witness to fail.

An interruption at any point leaves every visible state restorable (§3, §7).
A stop with 4 is no worse than a kill.

**A source that exists but is empty** gets a warning, not a refusal (call C2).
Nothing is deleted: everything moves into a snapshot by rename, and comes back
by rename on the next run.

## 7. Restore kit (kit revision 14)

- **Look up objects by name.** At the start of a restore, list latest and
  every snapshot once and build a name index. Resolve a row by its `DataPath`
  if that file exists, otherwise by its key in the index. Today's kit instead
  scans and hashes the whole pool recursively for each blank row
  (`Find-DataFileByHash`,
  [Reconstruct.ps1:304](../../Reconstruct.ps1#L304), called per row at
  [Reconstruct.ps1:1414](../../Reconstruct.ps1#L1414)). About 96% of rows in
  HomeHub's manifests are blank, so a full snapshot restore today costs rows ×
  pool. This was read from the code, not measured.
- Today's content scan stays as the last resort, for a row the index cannot
  resolve (call C5).
- There is no `.meta` check and no "unverified index" warning.
- Both restorers change together (`Reconstruct.ps1` and `bash/reconstruct.sh`).
- Old kits stay in old snapshots and still restore, more slowly. They still
  check their own snapshot's `.meta`, which stays valid (R6). Nothing outside
  the tests passes `-RequireWitness`.

## 8. Continuing an existing store (HomeHub)

- `LastBackupRun` in `FileBackupState.json` supplies D.
- **The old engine's `Temp` staging folder** gets a warning and is left alone.
  It may hold the only copy of superseded bytes (README). The new engine uses
  `Incoming/` and `Building_*`, never `Temp`.
- The latest state's old `.meta` is deleted on the first write (R5).
- Duplicates already spread across folders are left for Verify (R10).
- `Optimize-ChangeFolders` no longer runs.
- **The old source-side record** (`MANIFEST.csv` at `SourceStatePath` or the
  source root) is no longer read or written. It stays excluded from the backup,
  so it is not captured as user data, and a warning says it can be deleted
  (call C6).

## 9. Cross-project impact: IF-001 (HomeHub)

This needs the counterparty's agreement before it ships:

- the `/state` mount and `SourceStatePath` go away (R3);
- `/backup` and `/changes` must be one mount, for example one host folder
  mounted at `/store` holding `backup/` and `changes/` (R8). The separate bind
  mounts in `compose.example.yaml` fail the check;
- a backup no longer returns 3, and IF-001's witness text becomes obsolete
  (R5).

## 10. Impact on the drafted SR tier (input to the SR rewrite)

| Change | SRs |
|---|---|
| Retire | SR-038, SR-039 (the witness); SR-075, SR-144 (recovering and reclaiming a dead run); SR-139, SR-140, SR-148, SR-149 (the source-side record and where it lives) |
| Rewrite | SR-017 (leftovers are deleted, not refused); SR-082 (after a kill, latest restores as its last checkpoint, not as "before or after"); SR-036 (an empty source warns); SR-067, SR-089, SR-090 (R12 and exit 1); SR-035 (the change-detection record is the latest manifest); SR-094 (the source is always read-only); SR-116 (no evidence record at all); SR-049 (Verify moves duplicates and damaged objects into `Verify/`); SR-040, SR-043 (no 3 from a backup); SR-052 (call C3); SR-106 (no settle wait needed) |
| Keep as drafted | SR-001, SR-003, SR-005, SR-011, SR-053, SR-059, SR-084, SR-085, SR-086, SR-091, SR-093, SR-100, SR-105, SR-107, SR-108, SR-112, SR-113, SR-114, SR-115 |

The need tier still has to be checked against R1 to R14 before the SR rewrite.

## 11. Calls awaiting the Owner's confirmation

| # | Call | Why |
|---|---|---|
| C1 | The exit-code table in §6. | R14 left it open; this mapping makes NagLight and the scheduler see a missed file. |
| C2 | An empty source warns rather than being refused. | Nothing is lost: it is all renames, both ways. |
| C3 | No space estimate before the run. A write that fails for space stops the set with 4. | The ordering already makes a stop as safe as a kill, and the demand estimators are the kind of complexity R1 removes. |
| C4 | `-Action Verify -Deep` also moves an object that fails its hash into `Verify/`. | The same as for duplicates (R9); the run then stores the content again if the source still has it (SR-053). |
| C5 | The new kit keeps today's content scan as a last resort. | A restore should recover as much as possible; the scan is existing code that runs only on damage. |
| C6 | The old source-side record stays excluded, with a warning. | Otherwise every run backs up a dead 26 MB file. |
| C7 | The temp threshold is 256 MiB, or half the temp's free space. | It keeps the tmpfs well under the C-12 failure. |
| C8 | The checkpoint limits in §5. | They follow from the 20 s measurement. |

## 12. Not designed yet

- **Prune under write-once snapshots:** move last-copy objects into a surviving
  snapshot without rewriting its manifest.
- **Verify's moves into `Verify/`,** and how `Verify/` is named and reported.
- **The component and LLR breakdown** of this run (the
  `architecture-decomposition` skill applies).
- **Unchanged and out of this scope:** links (SR-150..152), the folder sidecar
  (SR-065), the views, and the container action words.
