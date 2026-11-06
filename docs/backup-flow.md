# How a normal backup runs

Reviewed against `Rust-Rewrite` at `45c9a4d`, 2026-11-05. These diagrams describe
the current PowerShell engine. They are a user-oriented view; the generated
function map remains in [architecture.md](architecture.md), and the detailed
rules remain in [AGENTS.md](../AGENTS.md).

The Rust preview retains this main loop, with explicit previous-definition
preservation before mutation and directory/link changes included in history.
Its [native flow/design](plans/native-design-2026-11-05/flows.md),
[implementation bindings](plans/native-design-2026-11-05/implementation-map.md)
and [usage/support limits](native-usage.md) describe the implemented transition.

## 1. One run, from the user's perspective

A configuration can contain several backup sets. Each set pairs one source
folder with one store folder; the sets run sequentially. A failure in one set
does not prevent the others from being attempted.

```mermaid
flowchart TD
    A[Start a backup manually or from a scheduler] --> B[Read and validate configuration and tools]
    B --> C{Configuration accepted?}
    C -- No --> X[Report refusal and exit]
    C -- Yes --> D[Take the next configured backup set]
    D --> E[Check source and store layout; acquire the store lock]
    E --> F{Safe to proceed?}
    F -- No --> R[Record this set's outcome]
    F -- Yes --> G[Read the latest file list; check for an unexpectedly empty source]
    G --> H[Clear interrupted work; list objects and set aside visible damage]
    H --> I[Publish the recovery kit; preserve the previous state as a dated snapshot, if there is one]
    I --> J[Walk the source and process each file - diagram 2]
    J --> K[Retry files that could not be captured]
    K --> L{Source still present and safe to publish?}
    L -- No --> S[Stop this set; keep recoverable progress]
    L -- Yes --> M[Publish the latest file list, directory details and run dates]
    M --> N[Discard a snapshot made by this run if no file row changed]
    N --> O[Move unused objects into the snapshots that need them]
    O --> P[Update the optional browse view; write totals and timings]
    P --> Q[Release the store lock]
    S --> Q
    Q --> R
    R --> T{More backup sets?}
    T -- Yes --> D
    T -- No --> U[Send optional notification and return the overall outcome]
```

The previous state's snapshot is published **before files are processed**. It
is named for that previous state's recorded completion date, not today's run.
On the first backup there is no previous state to preserve. A rename, a changed
timestamp or an added duplicate changes a file row and can keep a snapshot even
when no new content has to be stored.

The diagram groups preparation for readability. In the code, prior-state and
empty-source checks precede residue cleanup; residue cleanup precedes the
object listing. Errors after taking the lock release it through the same final
cleanup.

## 2. What happens to each file

The engine first gathers a list of files, then processes that list sequentially.
It includes hidden and dot-named files. It reports invalid names and unreadable
folders, preserving their earlier rows where available. Directory links are
not traversed; link metadata is not preserved. See the
[documented exclusions](../README.md#what-is-not-recorded--read-this-before-relying-on-a-restore).

```mermaid
flowchart TD
    A[Take the next source file] --> B{Same size and modification time as before,
        and no scheduled content re-read?}
    B -- Yes --> C{Usable object still present in the store?}
    C -- Yes --> D[Reuse it; move it back from history if possible]
    D --> E[Keep a row for this file without reading source content]
    C -- No --> F[Read the source and calculate its content hash]
    B -- No --> F
    F --> G{File vanished or changed during the read?}
    G -- Vanished --> H[Treat it as removed, subject to the source safety check]
    G -- Changed or unreadable --> I[Queue a retry; after three attempts warn and keep its earlier row]
    G -- Stable --> J{Same hash and size already stored?}
    J -- Yes --> K[Reuse the stored object; discard any temporary copy]
    J -- No --> L[Stage the captured bytes on the store volume - diagram 3]
    L --> M[Choose raw storage or 7-Zip from the staged bytes]
    M --> N[Flush the new object and publish it under its content name]
    N --> O[Add it to this run's object index]
    K --> P[Record this file's path, time and object in the working file list]
    O --> P
    E --> Z[Continue to the next file]
    H --> Z
    I --> Z
    P --> Z
```

Deduplication uses **hash plus original length**, across paths, earlier runs,
history and files first seen in this same run. Two identical files get two
logical rows and one stored object. Changing compression settings affects new
objects; it does not recompress existing ones. A snapshot object normally moves
back by rename; if that fails it can still be referenced where it is. Objects
held by very old kits are used without moving them.

## 3. When bytes actually get copied

An unchanged file normally costs a metadata check and object lookup. A file
that needs hashing does not always need another object written to the backup
drive.

```mermaid
flowchart TD
    A[File needs a content read] --> B{Likely to contain new content?}
    B -- Yes --> C[Copy to store Incoming while hashing the same bytes]
    B -- No --> D{Fits the available local temporary tier?}
    D -- Yes --> E[Copy to local temporary storage while hashing]
    D -- No --> F[Hash the source in place]
    C --> G{Content key already in the store?}
    E --> G
    F --> G
    G -- Yes --> H[Reuse that object; discard temporary bytes if any]
    G -- No --> I{Where are the captured bytes?}
    I -- Incoming --> J[Use that staged copy]
    I -- Local temporary storage --> K[Transfer the staged copy onto the store volume]
    I -- Source only --> L[Read again while copying to Incoming; recheck hash, size and time]
    K --> J
    L --> J
    J --> M[Optionally compress the staged copy]
    M --> N[Flush and rename into CurrentBackup's correct shard]
```

“Likely already stored” includes a scheduled re-read of an unchanged-looking
file, or a new path whose length already occurs in the store. It is only a
staging hint; the hash decides whether content is reused. The local tier is
capped per file at 256 MiB or half its measured free space, whichever is less.
If it cannot be used, hashing in place avoids that temporary write.

Compression reads the staged copy, so its content is the content that was
hashed. An archive exactly as long as its original is stored raw. Publication
does not overwrite a live object's bytes. A normal backup does not delete
stored content; removal of history is a separate explicit prune operation.

## 4. What remains on the drive

```text
MyStore/
  CurrentBackup/
    MANIFEST.csv                 latest logical file list
    DIRECTORIES.csv              optional empty-folder / folder-attribute details
    FileBackupState.json         run and full-rehash dates
    RECONSTRUCT.* + dependencies recovery kit
    ab/<content-name>            objects in two-character shard folders
  BackupHistory/
    2026_11_04_03_00_00/
      MANIFEST.csv               that previous state's complete logical file list
      RECONSTRUCT.* + dependencies
      <content-name>             objects stored flat in history
  View/                          optional generated browse pages
  Incoming/                      temporary work
  Verify/                        damaged / duplicate / misplaced objects set aside
  Temp.lock
  backup.log
```

A snapshot is a full **description** of a state, with some of its objects
possibly held elsewhere in the store. Preserve or copy the **whole store** for
reliable recovery. Copying one snapshot folder is not a self-contained data
export. Its kit is self-contained software, but still resolves shared data
from `CurrentBackup` and the other snapshots.

During a long run the engine periodically replaces the latest manifest with a
complete, recoverable checkpoint. That checkpoint can combine files captured
so far with earlier rows for files not reached yet. It is not a promise of an
all-before-or-all-after source tree. The prior snapshot remains the previous
state. Checkpoints are considered between files, normally no more frequently
than once a minute, with longer spacing when writing a manifest is expensive.

Retries are at least 60 seconds after a file's last failed attempt, with three
attempts total. A persistently unreadable file keeps its earlier copy, if any,
and makes the set incomplete. A previously populated source that now looks
empty stops the set with 4; `AllowEmptySource` is accepted but ignored.

## 5. Recovery stays independent of the backup engine

```mermaid
flowchart LR
    A[Choose CurrentBackup or a dated history state] --> B[Run its PowerShell or bash restore kit]
    B --> C[Use only the chosen state's manifest as authority]
    C --> D[Find each object locally, by its content name in the pool,
        or by a fallback content scan]
    D --> E[Detect raw or archive from bytes; copy or extract on target volume]
    E --> F[Check every restored file's hash and length]
    F --> G[Apply each file's timestamp and advisory directory details]
    G --> H[Report complete or list files that could not be recovered]
```

Recovery requires the documented shell/runtime and tools, but no repository,
Rust binary, Cargo or package download during the restore. PowerShell recovery
uses PowerShell 7 plus its bundled Common module and hashing DLL. Bash recovery
uses bash 4+, gawk and xxHash utilities, plus 7-Zip when extraction is needed;
the script has GNU/BSD userland shims. See
[restore instructions](../README.md#3-restore).

## Outcomes and implementation pointers

| Code | What the user should understand |
|---|---|
| 0 | This set completed with every file captured. |
| 1 | The set completed with files not captured, or detected damaged objects. Read the warnings. |
| 2 | The request or store needs correction before proceeding. |
| 4 | The store is busy, or a source, volume or host problem stopped this set. Retry after fixing the cause. |

Across sets, precedence is `2 > 4 > 1`. Optional notification and browse-view
failures do not change an otherwise successful backup into a failed one.

The diagrams follow `Invoke-BackupSet`, `Invoke-LibraryCapture`,
`Invoke-SourceFileCapture`, `Copy-FileWithHash`, `Publish-StagedObject` and
`Get-LatestObject` in [the engine](../Modules/FileBackup.Engine.psm1), with
publication and object-path primitives in [Common](../Modules/FileBackup.Common.psm1).
The interruption, checkpoint and retry examples live in
[BoundedRun.Tests.ps1](../tests/Unit/BoundedRun.Tests.ps1).

Related review: [requirements audit](requirements-audit-2026-11-05.md) and
[Rust migration plan](plans/rust-migration.md).
