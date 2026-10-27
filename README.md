# FileBackup

<a id="vision"></a>
**PROJECT-VISION:** FileBackup keeps a trustworthy, space-efficient history of
one owner's files. It runs unattended, and any saved point in time can be
restored bit-for-bit on a clean machine from the backup folder alone.

What sets it apart:

- FileBackup is needed only to *make* backups, never to recover them. Every
  backup carries its own restore kit, which runs with commonly available tools.
- It spends storage only where it pays: identical content is stored once, and a
  file is compressed only when measuring it shows compression actually saves
  space; where measuring is off or unavailable, its file type decides.

It never loses content a saved state still depends on, never alters the files it
backs up, and says plainly when it could not do its job.

Periodic, content-aware backup with change tracking and self-contained
reconstruction scripts. PowerShell **7+** on Windows, or the provided Linux
container for unattended backup runs.

FileBackup walks a source tree, hashes every file with **xxHash128**, deduplicates
identical content by `(hash, size)`, optionally compresses with 7-Zip, and records
everything in a `MANIFEST.csv`. When a run supersedes earlier content it preserves a
**dated point-in-time snapshot** (`Snapshot_<date>`) of the prior state, and drops a
**self-contained restore kit** into the backup so you can rebuild *any* point in time —
the latest from the backup folder, or an earlier state from its dated snapshot — with
nothing but that folder and the documented restore tools. No repository or NuGet
download is needed at restore time.

> **Status:** functional and covered across all four storage modes, including the
> G9 rollback matrix. Current suite totals and the full test matrix live in
> **[AGENTS.md](AGENTS.md)**.
> Contributors and agents modifying the tool should read **[AGENTS.md](AGENTS.md)**
> (architecture, invariants, test matrix, history).

---

## Requirements

| What | How | Needed for |
|---|---|---|
| **PowerShell 7+** (`pwsh`) | `winget install Microsoft.PowerShell` | everything (Windows PowerShell 5.1 is **not** supported) |
| **System.IO.Hashing** (NuGet) | auto-installed on first run, or `Install-Package System.IO.Hashing -RequiredVersion 8.0.0 -Scope CurrentUser` | xxHash128 hashing (required) |
| **7-Zip** | `winget install 7zip.7zip` | only when `CompressEnabled = $true` |
| **ffmpeg/ffprobe** | put `ffprobe.exe` at `C:\ffmpeg\bin\` | optional media bitrate column |

---

## Run it (no setup, nothing touched outside temp)

Double-click **`run.cmd`** (Windows) or run **`./run.sh`** (Linux) to see the
product work without configuring anything:

- `run.cmd` runs the self-contained demonstration: it builds a scratch source
  tree under `%TEMP%\FileBackupDemo`, drives a create/modify/remove/re-add/no-op
  backup timeline with the real engine, restores the latest state **and every
  dated snapshot**, byte-verifies everything (xxHash128), and writes a narrative
  `TimelineReport.md`. (Underlying command:
  `pwsh -NoProfile -File scripts\demo_timeline.ps1`; try
  `-Mode HashAddressed -Compress` for the other layout.)
- `run.sh` exercises the Linux restore surface: it restores every origin of the
  four committed real-engine fixture backups into a temp dir and byte-compares
  each file. (Underlying command:
  `bash tests/bash/verify_restores.sh tests/fixtures`; the fuller Linux suite is
  `bats tests/bash/`.)

A **formal backup** of your own data is the Quick start below.

---

## Quick start

### 1. Create a config

Edit and run the example builder (writes `$HOME\BackupConfig.xml`):

```powershell
pwsh -File .\CredSetEx.ps1     # prompts for the SMTP account (mail is optional)
```

### 2. Run a backup

```powershell
pwsh -File .\FileBackup.ps1                       # uses $HOME\BackupConfig.xml
pwsh -File .\FileBackup.ps1 -ConfigPath C:\my.xml
pwsh -File .\FileBackup.ps1 -NoMail               # skip the success/failure email
```

First run installs `System.IO.Hashing` per-user (prompts unless already present).

A run never stops for a file it cannot read: it carries on with everything else, keeps
that file's earlier copy, and names it in the set's log. Its exit code says what happened
(the worst set wins, precedence 2 > 4 > 1):

| Code | Meaning | What to do |
|---|---|---|
| **0** | Every file was captured. | Nothing. |
| **1** | The run completed, but one or more files were not captured (locked after three tries 60 s apart, unreadable, or named in a way Windows or Linux cannot restore). Each is named in `backup.log`; their earlier copies are kept. | Read the log; usually nothing — the next run tries again. |
| **2** | Refused before changing anything: a bad configuration, a missing tool, a missing source folder, a `BackupPath`/`ChangePath` pair on different volumes, a damaged latest manifest, or a `BackupPath` that is gone while its `ChangePath` still holds snapshots (moved, renamed, or a mount that is not there — a fresh full backup is never started beside old snapshots). | Fix what the message names. |
| **4** | Stopped by a host problem, or not started: the backup drive is not attached (a Windows drive letter or a network share), the backup volume filled up or went away, the source disappeared or emptied during the run (a dropped mount looks like that), or another run of this store holds its lock. Every state stays restorable. | Retry later — the next scheduled run is the retry. |

### Where a run's time goes

Every run ends its `backup.log` with what it spent its time on, so a check that
slows the backup can be found and changed:

- `Timings:` — each step of the run in seconds (reading the latest manifest,
  indexing the store, publishing the snapshot, walking the source, capturing
  files, the retry pass, finishing the latest state, moving superseded objects).
- `Work:` — how many files were skipped unread, and for each kind of read
  (`copy while hashing (new or changed)`, `hash in place (scheduled re-read)`,
  `copy to local temp (likely already stored)`, ...) and for compression, the
  compressibility probe, the media probe, moves back from snapshots, progress
  checkpoints and retry waits: count, bytes, seconds and MB/s.
- `Slowest files:` — the five slowest captures that took half a second or more.
- `metrics {...}` — the same as one JSON line, to compare night with night.
- During a long run, a `Progress:` line every minute.

A run that stops (exit 4) still writes what it had measured.

### 3. Restore

Open the backup folder and double-click **`RECONSTRUCT.cmd`** (Windows) or
**`RECONSTRUCT.command`** (macOS). With no arguments it opens a folder picker, restores,
and holds the window so you can read the result; it writes a `RECONSTRUCT.log` next to
the restored tree. To restore a *historical* state, run the launcher inside a specific
dated `Snapshot_<date>` folder instead — it reproduces exactly the state as of that
backup. The backup folder is self-contained — it carries `RECONSTRUCT.cmd`,
`RECONSTRUCT.command`, `RECONSTRUCT.ps1`, `reconstruct.sh`, the hashing module,
`System.IO.Hashing.dll`, and a path sidecar — so restore works on a machine without
this repo.

Backups written before kit revision 10 carry `RECONSTRUCT.bat` instead of
`RECONSTRUCT.cmd`; it still works, and it is still recognised as part of the kit rather
than mistaken for one of your files. `-Action Verify -RefreshKits` puts the current kit
into an existing store.

**On macOS**, `RECONSTRUCT.command` is a convenience with one limit worth knowing before
you need it: Finder will only launch a file that carries the executable bit, and the kit
is written by Windows, which cannot set one. On a FAT/exFAT/NTFS volume — a USB stick,
the usual case — macOS supplies it and the double-click works. After a zip round-trip
onto an APFS disk it does not, and Finder refuses until you run
`chmod +x RECONSTRUCT.command`. The route that never needs it is:

```bash
bash reconstruct.sh --pick-target
```

`reconstruct.sh` needs `bash` 4+, `gawk` and `xxhsum` (`brew install bash gawk xxhash`),
plus `7z` if the backup has compressed rows. If you would rather not install those, every
store also restores with PowerShell 7 — `pwsh RECONSTRUCT.ps1 -TargetRoot DIR` — and each
refusal tells you both routes.

**Headless and scheduled runs never prompt.** `-NonInteractive`, redirected input, or a
session with no console and no desktop all produce the usage text and exit 2 rather than
waiting for an answer nobody is there to give. `-NoGui` (or `FILEBACKUP_NO_GUI=1`) keeps
the typed prompt instead of the picker, and on Linux/macOS the picker is only ever
reached by asking for it with `--pick-target`.

**The index is checked before anything is restored, and every file after.** Both
restorers refuse a `MANIFEST.csv` that is not a FileBackup manifest *before* they
create the target, and they check every file they write against its row's length
and xxHash128, healing it once from another copy in the pool if it does not match.
From restore-kit revision 14 they read no `MANIFEST.csv.meta` witness: this version
writes none, and deletes the one an older version left whenever it rewrites that
manifest. A snapshot written by an older version keeps its own older kit, which still
checks that snapshot's own witness.

### Restore exit codes

Both restorers report outcome through one table, so a scheduled task or wrapper
can tell the failure classes apart without reading the log. `RECONSTRUCT.cmd` and
`reconstruct.sh` return these directly; `Reconstruct.ps1` throws a terminating
error unless you pass `-ExitCode` (which `RECONSTRUCT.cmd` does for you).

| Code | Class | Meaning | What to do |
|---|---|---|---|
| **0** | Complete | Every manifest row restored. | Nothing. |
| **1** | Incomplete — content | Everything salvageable was restored; the remaining rows' bytes do not exist anywhere in the data pool. | Real data loss: check an older backup. |
| **2** | Precondition / usage | Nothing was attempted — bad or missing arguments, no `MANIFEST.csv`, an unrecognizable manifest, a legacy path-addressed store (see `StoredAsHashSize` below), target inside the backup, an unusable target path, a missing required tool, or not enough free space. Any unexpected failure lands here too, since nothing was attempted. | Fix the invocation or environment. |
| **3** | *Retired* | Never returned from kit revision 14. A kit an older version bundled into an older snapshot can still return it when that snapshot's witness disagrees with its manifest. | Restore that snapshot with a current kit (`-Action Verify -RefreshKits`), or from another copy. |
| **4** | Incomplete — host | Rows failed because of *this machine*, not the backup: an unreadable search folder, 7-Zip unavailable for an archive candidate, or an extraction/copy I/O error on an **archive-shaped** object. | **Retriable** — fix the host and run again. |

Since kit revision 8 the split between **1** and **4** is decided by the stored
bytes rather than by the manifest's `Compressed` column. An object carrying no
7-Zip signature that reproduces neither form is damage (**1**), not a failed
extraction (**4**): no retry on a healthy machine fixes it, and classifying it as
retriable sent wrappers into loops over corruption. An object that *does* look
like an archive and will not open is still **4**, because this host's 7-Zip
genuinely may be at fault.

When several apply the precedence is **2 > 4 > 1**: code 2 aborts before anything
is written — the manifest's header is checked before the target folder and the
restore log are even created, so a refused restore leaves the target exactly as it
was — and 4 outranks 1 because it is the actionable one.

A row whose data file is not in its own folder — blank, or moved to another folder
of the pool — is found through a **name index**: each stored object's name carries
its content key, so the restorer lists the pool once and looks the row up. Only a
row the index cannot place falls back to scanning and hashing the pool.
The summary line names both counts regardless, e.g.
`Reconstruction INCOMPLETE: 3 file(s) could not be restored (2 content-missing, 1 host).`

### Restore on Linux (no PowerShell)

The same backup folders also restore on a stock Linux box — a NAS, a rescue
live-USB — with **`bash/reconstruct.sh`**, a single self-contained script that
reads the *same* `MANIFEST.csv` and data files. It needs only commodity tools:
`bash` 4+, GNU coreutils, **gawk**, **xxhsum** (xxHash ≥ 0.8), and **7z** (p7zip,
only if the backup used compression). Install them with e.g.
`apt-get install xxhash p7zip-full gawk` or `dnf install xxhash p7zip gawk`.

```bash
# Restore the latest state from a backup root:
bash reconstruct.sh --target-root /tmp/restore --from /path/to/backup

# Restore a historical point in time from a dated snapshot:
bash reconstruct.sh --target-root /tmp/asof --from /path/to/backup/changes/Snapshot_2024_01_01_09_00_00
```

`--from` names the restore origin (a backup root or a `Snapshot_<date>` folder;
default: the current directory). The backup root and the snapshot folder are
auto-detected from that location: for a snapshot, the backup root is the change
folder's parent when that holds a `MANIFEST.csv`, else the one folder beside the
change folder that does (the one-mount layout, `<store>/backup` beside
`<store>/changes`); for the latest state, the change folder is the one folder inside
or beside the backup root that holds `Snapshot_*` folders (needed only for a row
whose object is still in a snapshot). Pass `--backup-root` / `--change-root` to override when neither
fits — the sidecar's Windows paths are ignored on Linux, and a container's `/store`
paths do not exist on the host. Like the Windows restorer it **fails loudly**:
it checks the manifest's header before writing anything, then restores everything
recoverable and exits with the code from
"Restore exit codes" above — the same numbers the Windows restorer returns.
New backups carry the tested script as
`reconstruct.sh` in the live root and each snapshot; an external rescue copy of
the same script also works. See `bash reconstruct.sh --help`.

---

## Snapshot retention (pruning)

Snapshots pile up, so eventually you want to drop old ones. **Do not delete a
`Snapshot_*` folder yourself.** Because content is deduplicated, a folder that
looks like old history can hold the *only* physical copy of content other
snapshots recover by hash — deleting it from outside the tool is silent data
loss. Ask FileBackup to do it instead:

```powershell
# What is there, and what would each removal actually free?
pwsh -File FileBackup.ps1 -ConfigPath config.json -Action Snapshots

# Dry run first: reports exactly what the real run would do, changes nothing.
pwsh -File FileBackup.ps1 -ConfigPath config.json -Action Prune `
     -Snapshot Snapshot_2024_01_01_09_00_00 -WhatIf

# Remove it (several names are allowed; each is its own transaction).
pwsh -File FileBackup.ps1 -ConfigPath config.json -Action Prune `
     -Snapshot Snapshot_2024_01_01_09_00_00
```

`-WhatIf` is for `-Action Prune`, and for `-Action Verify -RepairStorage`, which
then moves and repairs nothing. It binds on every action (pruning needs
it), but a backup run does not honor it, so `-Action Backup -WhatIf` is refused
up front with status **2** rather than performing part of a run.

`-Action Snapshots` prints JSON, one object per snapshot:

| Field | Meaning |
|---|---|
| `Name`, `Date` | The folder and the point in time it preserves. |
| `Rows` | Rows in that snapshot's own manifest. |
| `PhysicalBytes` | What the folder occupies on disk. |
| `BytesReHomed` | Bytes that must be copied elsewhere before it can go. |
| `BytesReclaimed` | What removing it would **actually** free — `PhysicalBytes` less the re-homed bytes. Not the same as the folder size, because of dedup. |

Removing a snapshot first copies any content whose only physical copy it holds
into the surviving pool (the backup root, or the newest surviving snapshot that
needs it), rewrites that destination's manifest, proves that **every** surviving manifest row still resolves, and only then
deletes the folder. The last step out of the `Snapshot_` namespace is a single
rename, so no restore ever sees a half-removed snapshot. Nothing is deleted
until the pool is provably redundant.

It refuses rather than guesses. Removal reports the same status codes as a
restore (see "Restore exit codes"): **0** removed, **1** a batch finished
incomplete but **no data was lost**, **2** usage or precondition (nothing was
mutated), **3** a witness an older version left does not match its manifest
(nothing was mutated), **4** a host I/O problem — retriable, and always before the
point of no return. Common refusals: data
files in the snapshot its own manifest does not reference (`-DiscardUnreferencedData`
to discard them deliberately), a backup that is running (prune and backup are
mutually exclusive), or a pool that does not resolve as it stands.

**A pool that does not resolve blocks *every* prune in that store**, not just
the snapshot you named — pruning into a store that is already damaged could
turn a recoverable problem into a permanent one, so the mechanism refuses with
status **2** and names the offending rows. Nothing self-heals: the refusal
persists until the pool is made whole again. To proceed, run
`-Action Verify` first (see the next section) to enumerate the damage — it
reports every disagreement between the manifests and the bytes, and with
`-RepairStorage` added it also repairs the findings that are unambiguous
(verification alone mutates nothing) — and re-run the prune once verification
is clean. If the missing bytes exist only in a folder outside the pool, they must
be restored there by hand; recovering content from a partially removed snapshot
is a recorded future item (`-RepairFromPruned`), not something this version can
do.

Interrupted? Just run the same command again. There is no journal to repair:
the plan is recomputed from what is on disk, and the next invocation sweeps up
anything the interrupted one left behind. Retention *policy* — how many to
keep, how old is too old — is deliberately not FileBackup's business; it takes
explicit names only.

There is no prune on the Linux side: `reconstruct.sh` stays restore-only, and
pruning is never needed in order to restore.

---

## Checking that the index tells the truth (`-Action Verify`)

The manifest records **how** each file was stored — compressed or not. Nothing
in a normal backup run ever checks that claim against the bytes on disk, so a
wrong entry would validate itself forever. `-Action Verify` is the check. It is
opt-in, a normal backup never invokes it, and by default it reads and reports
without changing anything:

```powershell
# Audit the live backup AND every snapshot. Prints findings as JSON.
pwsh -File FileBackup.ps1 -ConfigPath config.json -Action Verify

# Fast pass: the live backup only.
pwsh -File FileBackup.ps1 -ConfigPath config.json -Action Verify -BackupRootOnly

# Also prove every row's payload really reproduces its recorded hash (needs 7-Zip).
pwsh -File FileBackup.ps1 -ConfigPath config.json -Action Verify -Deep

# Fix what is unambiguous from the bytes in each row's own folder.
pwsh -File FileBackup.ps1 -ConfigPath config.json -Action Verify -RepairStorage
```

Each finding names the folder, the row, and a class:

| Class | Meaning | Repairable |
|---|---|:---:|
| `FlagOverRaw` | The row says compressed; the bytes are raw. | yes |
| `FlagOverArchive` | The row says not compressed; the bytes are a `.7z` archive. | yes |
| `NameLies` | Flag and bytes agree, but the data file's name claims the other form. | yes |
| `DanglingDataPath` | The row names a data file that is not there, and its content is nowhere else in the pool. | no |
| `PayloadMismatch` | `-Deep` only: the stored bytes do not reproduce the row's hash/length. | no |
| `BlankRowFormDisagreement` | A row that resolves by content hash, whose `Compressed` disagrees with the copy the restore would find. Harmless with a current restore kit — see below. | no |
| `Unreferenced` | A data file in the folder that no manifest row names. | no |
| `DuplicateObject` | The same content is stored in a second folder (stores written by older versions). The copy kept is the latest state's, else the newest snapshot's. | yes — moved |
| `DamagedObject` | `-Deep` only: a stored object whose bytes were read (or expanded) completely and do not hash to the content its name records. A `.7z` exactly as long as its content is expanded before it is judged. | yes — moved |
| `UnverifiedObject` | `-Deep` only: a stored object that could not be checked — a read or a 7-Zip expand failed, which can be a corrupt archive or a host problem such as a full volume. Nothing is moved on a guess. `-Deep` without 7-Zip is refused before any object is checked. | no |

A row whose named data file has moved to another folder of the pool is **not** a
finding: snapshots are written once, so this happens whenever content that was
deleted comes back and is moved back into the latest state, and every restore finds
it by name.

Repair takes the **bytes as ground truth**: it rewrites `Compressed` and renames
the data file so its name stops lying. It never re-packs or re-compresses
content, never touches the logical columns (path, length, timestamp, hash), and
never migrates layout. Findings it will not touch are reported, not silently
"fixed". **It never deletes:** duplicate and damaged objects are moved into
`<ChangePath>/Verify/<folder>/`, which no backup and no restore reads — delete that
folder yourself once you no longer want them.

A duplicate is moved aside only after the copy that is kept has been read and
checked against its name: until then the second copy is real redundancy (a restore
that finds a damaged copy heals from another one in the pool), and `Verify/` is not
in the pool. A plain `-Action Verify` says what that costs before you repair —
`Found N duplicate cop(ies) ... first reads M kept cop(ies), X, to confirm them` —
and a repair logs its progress every minute and its total time. Under `-Deep` every
copy is checked anyway, so nothing is read twice. Each Verify ends its log with
`Verify timings:` and a `metrics {...}` line, like a backup run.

Status follows the same table as a restore: **0** nothing to report, **1**
findings (a statement about your data, not a usage error), **2** a precondition
failed — no manifest to verify, or `-Deep` without 7-Zip.

In the container: `verify` as the action word, and `FILEBACKUP_REPAIR=1` to
repair.

### Older snapshots carry the restore kit they were written with

Each snapshot bundles its own copy of the restore scripts, frozen at the moment
it was created. A defect fixed in the kit is therefore fixed for the live backup
and for every **new** snapshot, but a snapshot written before the fix keeps the
old kit permanently — including copies you moved off the volume.

One such fix matters: kits **before revision 2** decided whether to decompress a
hash-recovered file from the *manifest row* rather than from the file they
actually found. After turning compression on or off, restoring an old snapshot
*with its own old kit* could therefore write archive bytes under the original
filename and still report success. Kits from revision 2 on decide from the file
itself and are correct. Kits **before revision 3** additionally gave up on a
`.7z` file in the pool once it expanded to something other than the content they
were looking for — so a backed-up file that is *itself* a `.7z` archive could
become unrestorable from an older snapshot, with every check still reporting the
backup clean. Revision 3 tries the file's own bytes as well. Kits **before
revision 4** trusted the `RECONSTRUCT.paths.json` sidecar unconditionally — a
*copied* backup folder restored on the same machine could silently read the
still-live **original** store instead of the copy — treated a missing data file
as unrecoverable even when the bytes survived elsewhere in the pool, and (in
`RECONSTRUCT.ps1` on Linux) wrote `sub\file.txt` as one root-level file instead
of a folder tree. Revision 4 fixes all three. Kits **before revision 5** gave up
on a `.7z`-named recovery candidate whenever 7-Zip was absent — even when the
candidate was a raw file whose own bytes were the answer, needing no 7-Zip at
all. Kits **before revision 6** restored whatever bytes a resolvable
`DataPath` held **without checking them** — a wrong payload, a same-length
bit-flip, even a truncated file restored with exit 0 — could not see hidden
or dot-named files in the data pool (making exactly the hash-addressed names
that begin with a dot unrecoverable), and reported one unrelated unexpandable
`.7z` in the pool as a host problem (exit 4) instead of data damage (exit 1).
Revision 6 verifies every written file against the manifest's hash and
length, heals a mismatch from the pool when a good copy survives, scans the
pool with hidden files included, and fails with honest exit codes. Kits
**before revision 7** restored every deduplicated copy of a file with the
modification time of whichever twin happened to be stored first, never
recreated an empty directory, and brought a Hidden or System folder back as an
ordinary one; revision 7 stamps each file's own recorded time, applies the
`DIRECTORIES.csv` sidecar, and refuses a pre-2026-08 path-addressed store
outright rather than half-supporting it. Kits **before revision 8** decided
whether to decompress a file resolved through its *own* `DataPath` from the
manifest's `Compressed` column rather than from the bytes â€” the same class of
mistake revision 2 fixed for hash-recovered files, left in place for the common
path; revision 8 decides from the bytes in both cases, so a manifest whose
column disagrees with what is stored can no longer produce a wrong restore.
Kits **before revision 10** assumed **GNU** coreutils in seven places that no
tool check covered, so a restore host with BSD tools — a Mac that had installed
exactly what the script asked for, a FreeBSD/TrueNAS NAS — did not fail loudly,
it answered **wrongly**: an intact `MANIFEST.csv` failed its witness as
`expected 41231, found -1` and exited 3 (“the index is damaged”); the data pool
silently lost every dated snapshot, so a deduplicated file whose only copy lived
in one reported “your bytes are gone”; every compressed row failed and blamed
7-Zip; each restored file quietly took the restore time instead of its own; and
the guard that refuses a target *inside* the backup silently stopped
canonicalising paths. Revision 10 removes all seven assumptions, refuses a target
path it cannot resolve safely instead of guessing at it, and clears the read-only
attribute on every file it writes so a restored tree is always ordinary writable
files. **There is no revision 9 in the wild**: the marker was left at 8 when that
work shipped, so stores written by it report 8 — corrected forward rather than
back-dated, because the number records what a bundled kit *does*.
(The
revision is the `# KitRevision:` line near the top
of a folder's `RECONSTRUCT.ps1` / `reconstruct.sh`; `-Action Verify` reports it
alongside every `BlankRowFormDisagreement` finding.)

Two ways to be safe:

* restore an old snapshot with the **live backup root's** current
  `RECONSTRUCT.ps1`, pointing it at the snapshot
  (`-BackupRootOverride` / `-ChangeRootOverride`); or
* refresh the kits in place, once:

```powershell
pwsh -File FileBackup.ps1 -ConfigPath config.json -Action Verify -RefreshKits
```

`-RefreshKits` re-copies the current restore scripts into every snapshot folder.
It is opt-in and never automatic — it writes inside folders that are otherwise
immutable. It copies only the kit files; each snapshot keeps its **own** manifest
and its own witness.

---

## Browsing the backup without restoring (`BrowseView` / `-Action View`)

Data files in the backup root are named by their **content**, not by their
original path — that is what makes the store safe (an edit can never overwrite
the bytes another file still shares), but it means the backup folder is not
browsable by eye. The browse view is the answer: a generated, read-only index of
what is in the backup, written **outside** the backup root.

Turn it on per set with `BrowseView = 'index'`. It is written to `ViewPath`,
which defaults to `<BackupPath>_View`.

> **`ViewPath` must be a folder of its own.** The view is **wiped and
> regenerated from scratch** on every refresh, so that folder must contain
> nothing you care about. FileBackup enforces this rather than trusting it:
> a `ViewPath` that overlaps your source, backup or change roots — inside
> one, equal to one, or *containing* one — is refused before the run
> starts, as is one on a different volume; and the generator itself
> refuses to wipe any folder that does not already look like a view it
> made.

```powershell
# rebuild the view on demand (a normal backup run refreshes it automatically)
pwsh -File FileBackup.ps1 -ConfigPath config.json -Action View
```

You get `INDEX.tsv` — one row per logical path with its `DataPath`, `Length`,
`xxH2Hash` and `Compressed` — plus one `INDEX.html` page per folder, so a 500,000-file library
opens instantly instead of as one enormous page. The root page carries a search
box; above a size threshold the searchable data stays in `INDEX.tsv` and the page
tells you to grep it instead.

Three things worth knowing:

- **The view is cosmetic.** Nothing in FileBackup reads it — not the backup,
  not `-Action Verify`, not pruning, not either restore script. If generating it
  fails, the run logs a warning and still reports the backup's real outcome.
- **It lists duplicates honestly.** Every path appears, including files that
  share one stored object. (The old mirrored layout omitted them entirely.)
- **Snapshots do not get one.** Only the live backup root is indexed.

---

## Config format

`FileBackup.ps1 -ConfigPath` accepts CLIXML (`.xml`) and JSON (`.json`),
loaded and validated by `Import-BackupConfiguration` (SR-042).

**JSON is the canonical, versioned contract** — the portable, secret-free
format for containers and HomeHub, and the one this README's examples and
`container/FileBackup.example.json` are tested against. Every document
declares a `ConfigVersion` (currently `1`); the schema is **closed** — any key
it doesn't recognize (a typo like `AllowEmptySources`) aborts the run before
anything is touched, naming the offending key and its JSON path — and
**every** value must have the JSON type the schema gives it. Booleans are real
JSON booleans (a quoted `"false"` is rejected, never silently coerced to
`true` — PowerShell's `[bool]'false'` *is* `$true`, so for `AllowEmptySource`
that coercion would disarm the delete-all refusal), paths are real JSON
strings (`["x","y"]` is rejected rather than flattened to the literal path
`x y`), and `Secrets.SmtpPort` is a number. JSON has a single number type, so
an integral-valued number *is* that integer: `"ConfigVersion": 1.0` is the
same document as `1`, while `1.5` is refused.
`container/FileBackup.schema.json` publishes the
same contract as a JSON Schema (draft-07) for editor support; the hand-rolled
PowerShell validator in `FileBackup.Engine.psm1` is the runtime authority, and
a test (TC-077) pins the two together so the published schema cannot drift.

**CLIXML is the unversioned legacy native-Windows form** — still useful for a
Windows-only SMTP `PSCredential` (JSON cannot carry one at all: containerized
runs are `-NoMail` by design). It keeps today's per-set shape checks but is
exempt from `ConfigVersion`, the closed schema, and the credential rule.

```powershell
@{
    Secrets = @{                          # entire block optional → no email is sent
        ToEmail    = 'you@example.com'
        FromEmail  = 'backup@example.com'
        SmtpServer = 'smtp.example.com'
        SmtpPort   = 587
        Credential = $cred                # PSCredential (e.g. Get-Credential)
    }
    BackupSets = @(
        [pscustomobject]@{
            Name               = 'MainData'
            SourcePath         = 'D:\Data'
            BackupPath         = 'E:\Backups\DataStore'
            ChangePath         = 'E:\Backups\DataChanges'
            HashRecalcFreq     = 'W'      # A/E/D/W/M/Y/N
            CompressEnabled    = $true
            CompressProbe      = 'always' # 'always' (default) | 'excluded-extensions' | 'off'
            BrowseView         = 'index'  # 'off' (default) | 'index' browsable view
        }
    )
} | Export-Clixml -Path $HOME\BackupConfig.xml
```

The equivalent container-oriented JSON is:

```json
{
  "ConfigVersion": 2,
  "Tools": { "SevenZipPath": "/usr/bin/7z" },
  "BackupSets": [{
    "Name": "MainData",
    "SourcePath": "/source",
    "BackupPath": "/store/backup",
    "ChangePath": "/store/changes",
    "HashRecalcFreq": "W",
    "CompressEnabled": true
  }]
}
```

`Tools.SevenZipPath` and `Tools.FfprobePath` are optional overrides. The same
values can be supplied as `FILEBACKUP_7ZIP_PATH` and
`FILEBACKUP_FFPROBE_PATH`; otherwise FileBackup checks platform defaults and
`PATH`. If a set requests compression and 7-Zip is unavailable, the run fails
before backup processing instead of writing raw bytes described as compressed.

`FILEBACKUP_7Z_LEVEL` tunes how hard 7-Zip tries when a file *is* compressed: a
single digit `0`–`9` (7-Zip's own `-mx` range), **default `9`** when the
variable is unset. It is an environment variable rather than a configuration
key, so it needs no `ConfigVersion` bump and can be set per deployment. A lower
level trades compression ratio for CPU time and wall clock; it never changes
*whether* a file is compressed (see "How the stored form is chosen"). Note that
`0` is 7-Zip's *store* mode: the object is still a `.7z` container, holding the
bytes uncompressed, so it comes out slightly **larger** than the source — use
`1` rather than `0` when the goal is speed. Restore correctness is
level-independent: the restorers read no *policy* from the variable, and every
level's archive is read back by the same kit. (`Reconstruct.ps1`'s host
self-test compresses a tiny throwaway probe file of its own, which does inherit
the resolved level — harmless, precisely because every `0`–`9` archive
round-trips.) To pick a level for your data, run at two levels and compare each
set's `Probe compressed: <n>` count and the pool's disk usage — the honest
measure of the ratio you actually bought — against the wall clock. An invalid
value is refused by name before a compression-enabled backup creates anything
(status 2 under `-ExitCode`, a terminating error otherwise); a
`CompressEnabled: false` run and a restore are unaffected by it.

| Field | Meaning |
|---|---|
| `ConfigVersion` | JSON only, required. Currently `2` (version 1 is refused as too old — it carried the removed `PreserveFolderTree` selector). A config declaring a higher version is refused by name rather than half-understood; a missing/non-integer/out-of-range value is a hard error. |
| `HashRecalcFreq` | When to re-hash an *unchanged* file. `A`/`E`=always, `D`=daily, `W`=weekly, `M`=monthly, `Y`=yearly, `N`=never. |
| `SourceStatePath` | Ignored; accepted so older configurations still load. Nothing is written into the source any more: the latest backup manifest is the change-detection record. A `MANIFEST.csv` an older version left at the source root stays out of the backup and can be deleted. |
| `CompressEnabled` | `$true`/`true` allows data files to be re-packed as `.7z`; `false` stores everything verbatim and probes nothing. Which allowed files are actually compressed is decided per object — see "How the stored form is chosen". JSON must use a real boolean, not a quoted string. |
| `CompressProbe` | Optional; `off` \| `excluded-extensions` \| `always` (default `always`), exact lowercase. How the stored form is decided when `CompressEnabled` is on: `off` trusts the already-compressed extension list alone; `excluded-extensions` keeps the list's exemptions and measures everything it would otherwise compress; `always` measures a sample of the bytes of every file at or above 256 KiB, the list serving only the smaller files. |
| `AllowEmptySource` | Ignored; accepted so older configurations still load. A source that is suddenly empty is a warning, not a refusal: nothing is deleted, every file moves into that run's snapshot, and it all moves back when the source returns. |
| `BrowseView` | `off` (default) or `index`: generate a browsable, manifest-derived `INDEX.tsv` + per-folder HTML view of the backup, outside the backup root. `link` is reserved and refused by name. |
| `ViewPath` | Where the view is written. Defaults to `<BackupPath>_View`; must lie outside the backup and change roots and on the backup volume. |

`BackupPath` and `ChangePath` must be two folders on **one volume** (in a
container: under one mount). Content moves between the latest state and the
snapshots by rename, and a run refuses (status 2) a pair that a rename cannot
cross — on Linux that includes two separate bind mounts of the same disk.

Storage is always content-addressed: every data file is stored once per unique
content under a `<hash>_<len><ext>` name and referenced via the manifest. The
two fields are base-57 — the alphanumerics less the ambiguous `0 O I l 1` — so
a stored object is named with letters and digits only:

```
bqCY8RX7mwkoaQybcV4qdG_oJua.7z
└──── 22 chars ─────┘ └──┘
   full 128-bit hash   length, unpadded
```

The hash field is the row's complete `xxH2Hash`, so a pool object can be checked
against the manifest by decoding its own name; the length field carries no
padding. Nothing outside `[2-9A-HJ-NP-Za-km-z_]` appears before the extension,
which means a data file can never be hidden (a leading dot), never look like a
command-line switch (a leading dash), and never need quoting in a shell. (The former `PreserveFolderTree` mirror layout was removed — an
in-place edit of one of two identical files could destroy the last copy of
their shared content. A store written by a pre-content-addressed build still
restores and verifies, but backing up onto it is refused; use a fresh
`BackupPath`.)

### How the stored form is chosen

With `CompressEnabled` on, every newly written object is stored in one of two
correct forms — re-packed as `.7z`, or verbatim (`Compressed=No`). Two things
decide which: the already-compressed extension list, and a measurement of the
file's own bytes.

#### Already-compressed extensions

These extensions name content that is already compressed, so re-packing them
costs CPU and gains nothing:

```
.zip .7z .z7 .rar .gz .bz2 .xz .tgz .zst .esd
.mp4 .mkv .mov .avi .webm .mpg .mpeg .m2ts .m4v .wmv .flv
.mp3 .aac .flac .ogg .opus .m4a
.jpg .jpeg .png .webp .gif .heic .heif
.jar .pack .sav
```

Matching is on the **extension only**, case-insensitively, never on the path.
The list lives in exactly one place, `$script:NonCompressibleExtensions` in
`Modules/FileBackup.Common.psm1`; this table is checked against it by TC-096.

The list is no longer the whole answer. It decides on its own under
`CompressProbe: off`, it exempts files under `CompressProbe:
excluded-extensions`, and under the default `always` it decides only the tail of
files **below the 256 KiB probe floor** — everything at or above the floor is
measured instead.

#### The probe: the bytes decide

For a file at or above **256 KiB**, FileBackup reads three **256 KiB** samples —
at the start, the middle and the end (a file smaller than 768 KiB is read once,
whole, as a single sample) — and compresses them with Brotli at its fastest
level. The rule is an **aggregate** one: the object is stored as `.7z` only when
the sampled bytes shrink by **at least 10%** in total; otherwise it is stored
raw. Aggregating over all three windows is what stops a multi-gigabyte random
file with a compressible first page from being sent to `-mx=9` whole, and what
keeps a file only a third of which compresses from being skipped.

The probe runs **only when a group actually has to write**: content the backup
already holds is a dedup hit and is never probed, so a probe is paid once per
new object, not once per file per run. It can never fail a run either — if the
file cannot be sampled (a lock, an I/O error), the decision falls back to the
extension list's answer with a single `WARN`, which is exactly the pre-probe
behaviour.

**No name overrides the measurement.** A `.docx` whose bytes will not shrink is
stored raw; a `.jpg` whose bytes will shrink is stored as `.7z`. That is a
deliberate ruling (WP17, Q7): the need is to *save space*, the extensions named
in the acceptance criteria are examples of the old mechanism rather than rules
about those formats, and measured bytes serve the need better than any filename
can.

#### `CompressProbe` — the three modes

| `CompressProbe` | at or above the 256 KiB floor | below the floor |
|---|---|---|
| `off` | the extension list alone decides — exactly the pre-probe behaviour | the list |
| `excluded-extensions` | the list still exempts what it names; everything else is probed | the list |
| **`always`** (default; the key may be omitted) | **every file is probed**, listed extensions included — the list is not consulted | the list |

`CompressEnabled: false` comes before all three: nothing is compressed and
nothing is probed.

**What `always` costs on the first run, honestly.** Every object the first pass
writes above the floor is probed once. On a large media library that is on the
order of *tens of thousands* of probes and *tens of GiB* of sampled reads —
once, in exchange for the `-mx=9` CPU those files would otherwise have burned
(on the library that prompted the change, ~880 GB of pointless re-packing).
Later runs probe only genuinely new content. The figure is measured, not
estimated: each set's summary reports `Probe stored raw: <n> objects, <bytes>`,
`Probe compressed: <n>` (a count — the compressed objects' bytes are not
totalled) and `Probe reads: <bytes>`, and every written group logs its own
decision at `DEBUG` as
`compress-decision: <path> <Reason> ratio=<aggregate> windows=<per-sample>` —
run with `-LogLevel DEBUG` to see why any single object took the form it did.

#### Nothing already stored is ever re-formed

Changing the list, or the mode, changes what a *future* run stores. **Nothing
already stored is ever re-formed** — there is no migration, in either direction.
Existing data files keep the form they were written with, in the backup root and
in every snapshot alike, and are restored correctly regardless (see "Restoring
an older snapshot" below). An object that dedup already locates is adopted
*before* the probe is ever consulted, so no stored object's form is re-decided.
The same is true of flipping `CompressEnabled`: it governs content written after
the flip and nothing else. A mixed-form store is normal, because the form is
decided per object.

> **A blank-row form disagreement after a list or mode change is expected.**
> Once the list or the mode changes, the pool can legitimately hold **both**
> forms of one content — say a `.z7` archived as `.7z` before the change and
> re-added raw afterwards. Pruning keeps one copy and blanks the other
> snapshot's row, whose recorded form may then disagree with the copy that
> survives, and `-Action Verify` reports that row as a (report-only)
> `BlankRowFormDisagreement`. On a store whose list or mode changed, that
> finding is **benign**: both restorers decide the form from the file they
> actually locate, so every row still restores byte-exact.

> **After a form change, prune checks each snapshot's kit revision.** Flipping
> `CompressEnabled` (or changing the extension list) means newly stored copies
> of shared content take the new form, so an older snapshot can hold a
> blank-DataPath row whose recorded form no longer matches the copy that
> survives elsewhere in the pool. Restores are byte-exact either way
> (revision-2+ kits decide from the file they find), and prune accepts the
> disagreement for any folder whose own kit is revision 2 or newer. Only a folder still carrying a
> pre-revision-2 kit (or none) refuses, naming the kit revision — run
> `-Action Verify -RefreshKits` to upgrade every snapshot's kit, then retry.

You can list multiple `BackupSets` in either format; each is processed
independently. IF-001 rules **one `BackupSet` per container invocation** —
HomeHub runs one service/invocation per directory — so a JSON config with
more than one set is accepted (a legitimate native-Windows use) but logs a
`WARN` naming the count instead of failing.

`FileBackup.ps1 -ExitCode` (passed by `container/entrypoint.sh`) reports
outcome as a process exit code instead of only a terminating error, from the
table under "2. Run a backup": `0` every file captured, `1` completed with
files not captured, `2` refused before anything changed — a configuration file
that is **missing**, unreadable or violates the contract above among the causes,
the same usage/precondition class as the restore table in "Restore exit codes" —
and `4` stopped by a host problem or a held lock. A supervisor can therefore
tell "your config is wrong, retrying will not help" from "try again later".
Without `-ExitCode` a run still ends with the same non-zero code. A refused run creates **nothing**: no log directory
is made and the previous run's global log is left byte-for-byte intact (the
message goes to stderr, and is appended to that log only if it already
exists). Without `-ExitCode`, a configuration
problem is a terminating error and a failed set still yields a non-zero exit,
unchanged from before this contract existed.

---

## Run as a Linux container

The image bakes PowerShell, `System.IO.Hashing`, and 7-Zip at build time, runs as
a non-root user, and performs no runtime package installation. Copy
`container/FileBackup.example.json` before editing it, then pre-create every
host bind-mount directory (especially on NTFS/exFAT mounts):

```bash
cp container/FileBackup.example.json /srv/homehub/filebackup.json
mkdir -p /srv/backups/store /srv/backups/logs
docker build -t filebackup:local .
docker run --rm --network none --read-only \
  --security-opt no-new-privileges --cap-drop ALL \
  --tmpfs /tmp:rw,noexec,nosuid,nodev \
  -v /srv/homehub/filebackup.json:/config/FileBackup.json:ro \
  -v /srv/library:/source:ro \
  -v /srv/backups/store:/store \
  -v /srv/backups/logs:/logs \
  filebackup:local
```

`compose.example.yaml` expresses the same boundary using `FILEBACKUP_SOURCE`,
`FILEBACKUP_STORE` and `FILEBACKUP_LOGS`. The source and config are read-only;
the store and log mounts must be writable by the selected
`FILEBACKUP_UID`/`FILEBACKUP_GID`. **The store is ONE mount** holding `backup/`
and `changes/`: content moves between them by rename, Linux cannot rename across
two bind mounts even of the same disk, and a set whose `BackupPath` and
`ChangePath` sit on separate mounts is refused with exit 2. Give each backup set
its own store folder. Nothing is written into `/source`, so there is no
source-state mount any more.
The entrypoint preserves FileBackup's exit code, so HomeHub can wrap the job and
post its own NagLight result without coupling this project to that service.
The image sets `FILEBACKUP_7ZIP_PATH`; add `-e FILEBACKUP_7Z_LEVEL=<0-9>` to
tune the 7-Zip effort level for that deployment (default `9`, see
"Configuration" above — the image deliberately ships no default of its own).

The same container also performs retention. A leading word — `backup` (the
default), `snapshots` or `prune` — selects the action, or set
`FILEBACKUP_ACTION`; anything starting with `-` is passed to `FileBackup.ps1`
untouched, so existing invocations are unaffected:

```bash
# Inventory with dedup-aware reclaim figures (JSON on stdout, changes nothing):
docker run --rm ... filebackup:local snapshots

# Remove one snapshot (FILEBACKUP_SNAPSHOT / FILEBACKUP_DRY_RUN work too):
docker run --rm ... filebackup:local prune -Snapshot Snapshot_2024_01_01_09_00_00
```

Pruning writes inside `/store`, so it must be mounted writable for that action. See "Snapshot retention (pruning)" above for the
status codes and the refusal set.

### Build, verify, and move the image

The checked-in helper uses the same commands locally and in CI. Its test creates
a real compressed backup in the container, checks the restore kit, restores
the latest state and a snapshot in further containers and compares every file
byte-for-byte, checks that a clean store verifies clean, and checks that the old
two-mount layout is refused:

```powershell
pwsh -File scripts/Invoke-Container.ps1 -Action BuildAndTest
```

The helper auto-detects Docker or Podman; use `-Runtime Docker` or
`-Runtime Podman` to pin one. A locally installed Podman CLI also needs its
machine/socket running (`podman machine start` on Windows).

For an offline HomeHub, export and later load the OCI image tar:

```powershell
pwsh -File scripts/Invoke-Container.ps1 -Action Export `
  -OutputPath .artifacts/filebackup-image.tar
docker load --input .artifacts/filebackup-image.tar
```

NuGet is only a **build dependency source** here: the Dockerfile downloads the
pinned `System.IO.Hashing` package, verifies its SHA-256, and extracts the DLL
into the image. NuGet does not publish, activate, or fetch the container.

To use Repsy later, create a Docker repository there, authenticate without
putting the token on a command line, then publish a fully-qualified image tag:

```powershell
docker login docker.repsy.io                         # username + API token
$remote = 'docker.repsy.io/YOUR_USER/YOUR_REPOSITORY/filebackup:1.0.0'
pwsh -File scripts/Invoke-Container.ps1 -Action Publish -RegistryImage $remote
```

The same flow works with Podman by adding `-Runtime Podman` and using
`podman login docker.repsy.io`.

Another machine fetches and gives the image its local name with:

```powershell
pwsh -File scripts/Invoke-Container.ps1 -Action Pull `
  -RegistryImage docker.repsy.io/YOUR_USER/YOUR_REPOSITORY/filebackup:1.0.0
```

Alternatively set `FILEBACKUP_IMAGE` to the remote tag when using
`compose.example.yaml`; Compose will pull it when it is not already local.
Registry publication is optional—the local build and exported tar are complete
consumption paths on their own.

---

## How it works

```
SOURCE                      BACKUP (latest state)                 SNAPSHOTS (older states)
------                      ---------------------                 ------------------------
D:\Data\report.docx  -hash→ E:\Store\Backup\Ab92Cd…_5K.7z         E:\Store\Changes\
D:\Data\photo.jpg    -hash→ E:\Store\Backup\Xy7Ko…_3M.jpg           Snapshot_2026_03_19_22_50_06\
                            MANIFEST.csv                            ← full point-in-time MANIFEST.csv
                            RECONSTRUCT.ps1/.cmd/.sh                   + the bytes superseded after it
                            FileBackup.Common.psm1                     + a restore kit
                            System.IO.Hashing.dll                  Snapshot_2026_02_10_08_00_00\  …
                            FileBackupState.json
```

Identical content is stored once (keyed on `(xxHash128, length)`) under a name that
carries that key; extra logical names just point at the same object. The backup root
is always the **latest** state. Each older state is a `Snapshot_<date>` folder named
for the backup whose state it preserves — its full manifest plus the objects that
stopped being used after it; everything else it resolves by name from the rest of the
pool. The **most recent run has no snapshot** (it *is* the live backup), and a run
that changes nothing creates none. A rename, a time-only change or an added copy does
make one: a state is its list of paths, not just its bytes.

A run, in order: take the store's lock; read the latest manifest and list every
folder of the pool once; **publish the previous state as its snapshot first**; walk
the source, hashing each new or changed file *while* copying it, so a stored object
is always named after the bytes actually written; bring content that comes back
from a snapshot back by rename instead of copying it again; save progress about
once a minute; write the new manifest; then move what is no longer used into the
snapshot. Nothing is ever deleted. A kill at any point leaves every state
restorable, and the next run simply carries on from the files.

**A note on your source folder:** nothing is written into it. Older versions kept a
hash cache as a `MANIFEST.csv` at the source root (or at `SourceStatePath`); it is no
longer read or written, stays out of the backup, and can be deleted.

**Hidden and dot-prefixed files are backed up** (since kit revision 6 —
before it, no PowerShell-side walk saw them at all). That deliberately
includes Windows noise files (`desktop.ini`, `Thumbs.db`), macOS `.DS_Store`,
dot-directories like `.git`, and files carrying the System attribute: for a
data-safety tool, capturing too much beats silently capturing too little. There
is currently no per-set exclusion setting — to keep such trees out of a backup,
point `SourcePath` at a folder that does not contain them.

**Two exceptions, and only at the root of `SourcePath`:** `System Volume
Information` and `$RECYCLE.BIN`. Windows puts both on every NTFS volume, so they
appear whenever you point a set at a *volume root* like `D:\`, and neither is
your data — one is the volume's own shadow-copy and indexing store, the other
holds files you have already deleted. Before they were excluded, a `SourcePath`
of `D:\` **failed every single run**: `System Volume Information` denies read
access even to an administrator, and an unreadable directory marks the set
failed. `$RECYCLE.BIN` had the opposite problem — it is readable by its owner, so
deleted files were quietly being backed up. The same folder also confused a
*restore*: when a file genuinely could not be found in the pool, the unreadable
folder made the run blame **this machine** (exit 4, "fix the host and retry")
instead of reporting the content as gone (exit 1) — so a wrapper would retry
forever rather than tell you a file was lost. An intact backup still restored
correctly; it was the failure *diagnosis* that was wrong.

The exclusion is deliberately narrow, and needs **both** of these to be true: the
folder is at the top level, **and** `SourcePath` is a whole volume. A folder of
either name *nested* in your tree is your data. So is one at the top of an
ordinary folder — back up `C:\Users\Pat\Project` and a `$RECYCLE.BIN` inside it
is kept, because nothing about an ordinary directory makes that folder the
system's rather than yours. What comes *back* is a subtler question —
FILE attributes are not in the index at all, so see "What is **not** recorded"
below before assuming a Hidden file returns Hidden. A hidden *folder* does come
back hidden (kit revision 7); a hidden file does not.

### What FileBackup records, and where

Everything FileBackup knows lives in plain text beside your data — there is no
database and nothing in the registry or your user profile. Ten artifacts, all
named below so you can recognise every file the tool creates:

| File | Where | What it holds |
|---|---|---|
| `MANIFEST.csv` | backup root, and each `Snapshot_<date>` folder | **The index.** One row per logical file, nine columns (below). A snapshot's copy is that point in time's complete index. |
| `MANIFEST.csv.meta` | beside a `MANIFEST.csv` an **older version** wrote | The witness older versions wrote. Not written any more; a run deletes it when it rewrites that manifest, and only the older kit bundled beside it reads it. |
| `Incoming\`, `Building_<date>\` | change root, while a run is working | A run's temporary copies and the snapshot it is preparing. A run that is killed leaves them; the next run deletes them — neither ever holds the only copy of anything. |
| `Verify\` | change root, only after `-Action Verify -RepairStorage` | Duplicate and damaged objects that repair set aside instead of deleting. Delete it yourself. |
| `DIRECTORIES.csv` | backup root, and each `Snapshot_<date>` folder, when there is anything to say | **The directory sidecar.** One row per folder that holds no file anywhere beneath it, or that carries a `Hidden`, `System`, `ReadOnly` or `NotContentIndexed` attribute - the two things a one-row-per-file index cannot express. Advisory: it is not witnessed, and a restore never fails over it. A tree with no empty or attributed folder gets no such file at all. |
| `FileBackupState.json` | backup root | Two dates: `LastHashRun` (when the last full re-hash swept) and `LastBackupRun` (which dates the next snapshot). Written by rename, so a crash cannot leave it torn. If it is missing or unreadable, a run warns, sets it aside, and dates the previous state by the manifest file's own time. |
| `RECONSTRUCT.paths.json` | backup root | The source/backup/change paths this store was written with, so a restore in place needs no arguments. Ignored once the folder is moved elsewhere. |
| `backup.log` | change root | The run log: what was hashed, stored, moved, not captured, refused. |
| `RECONSTRUCT.log` | the **restore target** | Written by a restore, not a backup — the per-file record of what was recovered and how. |
| `.viewstamp` | the view root (`ViewPath`), only with `BrowseView: index` | A digest of the manifest rows the browse view mirrors, so a stale view is rebuilt rather than trusted. |
| `RECONSTRUCT.ps1` · `RECONSTRUCT.cmd` · `RECONSTRUCT.command` · `reconstruct.sh` · `FileBackup.Common.psm1` · `System.IO.Hashing.dll` | backup root and every snapshot | The restore kit — the reason a backup folder needs nothing else to give your files back. (Stores older than kit revision 10 carry `RECONSTRUCT.bat` in place of the `.cmd`.) |

Those names are **infrastructure at the root only**. A file of your own called
`MANIFEST.csv` in a subfolder is ordinary data and is backed up as such.

`MANIFEST.csv` is published by atomic rename — written as `MANIFEST.csv.tmp` and
renamed over the old one — so it can never be half-written. A `.tmp` file left by a
crash is harmless: the next write replaces it, and it is never backed up or
reported.

### Manifest columns

| Column | Meaning |
|---|---|
| `RelativePath` | The file's path under `SourcePath` — its identity. |
| `DataPath` | The stored object holding its bytes, named by content: `"<hash22>_<len><ext>"` in base-57 (see above). **Blank** means "recover by content hash" — the bytes live in another folder of the pool and the restorer finds them by `(hash, length)`. |
| `Length` · `xxH2Hash` | The original content's size and xxHash128. Together they are the dedup key, the restore lookup key, and the post-write verification the restorer performs on every file. |
| `LastWriteTimeStr` | The source file's modification time, used with `Length` to skip re-hashing an unchanged file. |
| `Compressed` | Whether *this row's own* stored object is a `.7z`. Compression is decided per file, so a tree is normally mixed. **Advisory since kit revision 8**: a restore decides the real form from the object's bytes (SR-068), so a wrong value here cannot produce a wrong restore. It still feeds the restore's free-space estimate, which is approximate by design. |
| `StoredAsHashSize` | Always `Hash`. Kept in the schema because every restorer and every existing store reads it; `Original` identifies a pre-2026-08 path-addressed store. Such a store is refused outright as of kit revision 7 â€” by a backup, by a restore (exit 2), and reported as a finding by `-Action Verify`. There is no conversion: back up to a fresh `BackupPath`, and restore the old store with the kit bundled inside it. |
| `Duplicate` | This row shares its object with another row. |
| `MediaMBPerSec` | Optional media bitrate, when `ffprobe` is available. Informational. |

### What is **not** recorded — read this before relying on a restore

The contract is **bytes at paths**: every file comes back with exactly its
original content at exactly its original relative path, or the restore fails
loudly. Everything else about a file is outside that contract.

- **File ATTRIBUTES are not in the index, and are not restored from it.** They
  ride along only as a side effect of how the bytes were copied. For a file
  whose content is unique that usually means Hidden, System and ReadOnly
  survive intact. **For a deduplicated file it means something sharper: every
  row sharing one stored object comes back with the attributes of whichever
  file created that object.** Two identical files â€” one ordinary, one
  Hidden+ReadOnly â€” restore as two copies of whichever one was stored first. If
  your workflow depends on file attributes, verify them after a restore.
- **Modification times ARE restored, per row** (kit revision 7). Each file is
  stamped with its own `LastWriteTimeStr` from the manifest once its bytes are
  verified, so a deduplicated twin no longer inherits the stored object's
  timestamp. A blank or unreadable value is logged and the file still restores.
  Creation time and last-access time are not recorded and are not restored.
- **Directories: empty ones, and their attributes, ARE recorded** (kit revision
  7) in the `DIRECTORIES.csv` sidecar â€” an empty directory is recreated, and a
  `Hidden`, `System`, `ReadOnly` or `NotContentIndexed` folder comes back with
  those bits on Windows. Four bits, no more: they are the only ones
  `SetFileAttributes` can apply to a directory. **Directory timestamps, owners
  and permissions are still not recorded**; NTFS compression and EFS encryption
  on a folder cannot be re-applied through that API and are not restored; and on
  Linux `reconstruct.sh` creates the directories but logs the Windows attributes
  as inapplicable rather than pretending. A backup written before this carries
  no sidecar and restores exactly as it always did.
- **Security descriptors are not captured** — no ACLs, owners, auditing or
  integrity labels. A restored tree inherits permissions from wherever you
  restore it. FileBackup is a content backup, not a system-state backup.
- **Junctions, symbolic links and other reparse points are not followed and not
  recorded.** The walk does not descend through them, so content that exists
  only behind a junction inside your source is **not backed up**, and the link
  itself does not reappear in a restored tree. If a linked folder matters,
  give it its own `BackupSet`.
- **Alternate data streams are outside the contract.** `Length` and `xxH2Hash`
  cover a file's primary stream only, so editing a stream is not even seen as a
  change. A stream may incidentally ride along on an uncompressed copy; nothing
  guarantees it and you should not rely on it.
- **Nothing about the volume itself** — no partition layout, boot data, drive
  letters or volume GUIDs.

### Volume roots and `System Volume Information`

Pointing `SourcePath` at a **volume root** (`D:\`) rather than a data folder
(`D:\Data`) puts three Windows-owned directories inside your backup scope:
`System Volume Information`, `$RECYCLE.BIN`, and — on a system volume —
`Recovery`. The first is the one that bites.

`System Volume Information` exists at the root of essentially every NTFS, ReFS
and exFAT volume, and its ACL grants access to `SYSTEM` alone: not
Administrators, not you. It holds volume-scoped machine bookkeeping — Volume
Shadow Copy / System Restore data, the NTFS distributed-link-tracking database
(`tracking.log`), disk-quota indices, Windows Search catalogue data, and on
removable drives `WPSettings.dat` and `IndexerVolumeGuid`.

**What happens today:** hidden and system directories became visible to the
walk in 2026-08 (kit revision 6), so FileBackup *sees* the folder, cannot list
it, and treats that as a real failure. Every run logs

> `Cannot enumerate 'D:\System Volume Information': Access to the path is denied. Files beneath it are NOT backed up this run and existing rows there are frozen; this set is marked failed (SR-057). Point SourcePath below it, or grant read access.`

and the **set exits 1**. Everything readable is still backed up and manifested;
rows under the unreadable path are *frozen*, not evicted, so a permissions
problem is never mistaken for "the user deleted these files".

**The blast radius if it were simply ignored** — that is, skipped silently
instead of failing:

- **Nothing recoverable is lost.** Its contents are volume-scoped state that
  only means anything on the volume that produced it: shadow-copy differentials
  reference that volume's live block layout, the tracking database keys on that
  volume's object IDs, the indexer catalogue describes files by that volume's
  GUID. Restoring any of it onto another volume is meaningless, and Windows
  recreates and re-owns the folder itself in any case. You cannot recover
  Previous Versions or System Restore points by copying this folder around;
  that is what a system-image tool is for.
- **The real cost is the false negative.** The code path that would hide
  `System Volume Information` cannot tell it apart from any *other* directory a
  permission denies — a colleague's profile folder, an EFS-encrypted tree, a
  share subtree whose ACLs changed last night. Silently skipping this one means
  silently skipping those too, and "the backup said 0 errors" while quietly
  capturing less than you asked for is precisely the class of defect the
  `-Force` work fixed. The loud failure is the deliberate trade.

**What to do instead:** point `SourcePath` at the data you actually want
(`D:\Data`, not `D:\`). That is the same answer as for every other exclusion —
there is no per-set exclude list, and scoping `SourcePath` is the supported
mechanism. If a volume root is genuinely what you mean to back up, grant your
account read access to the folder and the run goes green.

---

## Repository layout

```
FileBackup.ps1            Entry point (reads config, runs each backup set)
Reconstruct.ps1          Restore script (deployed standalone into each backup folder)
Modules/
  FileBackup.Common.psm1   Restore-safe primitives (hashing, manifest I/O, 7-Zip, …)
  FileBackup.Engine.psm1   Backup engine (walk, diff, dedup, snapshots, retention, view)
bash/reconstruct.sh      Linux restore — same backups, no PowerShell (see "Restore on Linux")
run.cmd · run.sh         Zero-setup launchers: demo timeline (Win) / fixture restores (Linux)
CredSetEx.ps1            Example config builder
RunAllTests.bat          Test runner  ·  Setup-USB.bat  (RealUSB provisioning)
tests/                   Test harness — Run-All.ps1, Suites/G1..G9, Unit/, bash/ (bats), fixtures/
scripts/                 Check harness (check.ps1), traceability + doc generators
docs/                    Gated-process docs: status.md, requirements/, test/, plans/
.github/workflows/tests.yml CI: lint + unit + Subst integration + Linux restore/interop
AGENTS.md                Contributor/agent guide (architecture, invariants, tests, history)
```

For the current HomeHub/container gap analysis and its explicitly unverified
findings, see [docs/homehub-integration.md](docs/homehub-integration.md).

---

## Testing

```powershell
.\RunAllTests.bat            # Subst backend — no admin, no USB (the default)
.\RunAllTests.bat VHDX       # virtual disks (admin + Hyper-V)
.\RunAllTests.bat RealUSB    # physical USB partitioned by Setup-USB.bat
```

Unit tests: `Invoke-Pester tests\Unit`. The full backend/mode/hardware matrix and the
suite breakdown live in **[AGENTS.md](AGENTS.md)**.

---

## Notes & troubleshooting

- **PowerShell 5.1 is unsupported.** The hashing library's Desktop build needs transitive
  `System.Memory` assemblies absent from a stock 5.1 session. Use `pwsh`.
- **Email is optional.** Omit the `Secrets` SMTP fields (or pass `-NoMail`); mail failures
  are logged, never fatal.
- **A run refuses because `Temp` exists (stale `Temp` folder error).** Older versions
  staged a run in a `Temp` folder under `ChangePath`, and one left by an aborted run may
  hold the **only physical copy** of bytes that older snapshots recover by hash. This
  version never uses `Temp`: a run that finds one warns that it is left alone and carries
  on. **Do not delete it.** Safe recovery: (1) move the whole `Temp` folder *aside*,
  outside `ChangePath` (a rename is instant and loses nothing); (2) run `-Action Verify`
  and test-restore your oldest snapshot — if verification is clean and restores complete,
  discard the moved folder; (3) if any snapshot restore reports missing content, copy the
  moved folder's *data files* into the backup root (skip its `MANIFEST.csv`) — both
  restorers find content by name and hash regardless of folder — and verify again. A
  `Temp` left by an interrupted **prune** blocks further prunes the same way; the same
  steps apply.
- **`Temp.lock` and the `[SR-075/lock-held]` refusal.** Every backup and every prune —
  and `-Action Verify` when given `-RepairStorage` or `-RefreshKits` (exit 2 if refused),
  while it sets objects aside, repairs or refreshes kits —
  holds an exclusive lock on the empty file `Temp.lock` in `ChangePath` for as long as it runs;
  the operating system drops it the instant that process ends, however it ends. A run that
  finds it held refuses straight away with `[SR-075/lock-held]` and touches nothing
  (a backup exits 4): another backup or prune of this store is still alive. If none is,
  something else has the file open (an antivirus scanner, a backup agent) — find it rather
  than deleting the file. **Leave `Temp.lock` where it is.** It is never written, it is not
  part of the backup, and deleting it while a run holds it can let a second run lock a fresh
  copy alongside the first on Linux. On Linux the lock is advisory (`flock`): it excludes
  every FileBackup process on the same host, containers included, but not a run on another
  machine reaching the same store over SMB or NFS — **two machines writing one store are not
  supported**.
- **Where a run's log lives.** Per-set detail — the lock messages above included —
  is written to **`backup.log` inside that set's `ChangePath`**. `Backup_Global.log` (beside
  the config unless `-GlobalLogPath` / `FILEBACKUP_LOG_PATH` says otherwise) is the
  orchestrator's sink: configuration, dependency checks, cross-set failure summaries and
  mail. It is legitimately near-empty while a set is running, so read `ChangePath\backup.log`
  when you want to know what a run is doing or why it refused.
- **Unexpected empty source.** A previously populated set whose source becomes empty (often
  an unavailable share) warns and carries on: nothing is deleted — every file moves into that
  run's snapshot by rename, and moves back when the source returns. A source folder that
  does not exist at all is refused (exit 2).
- **Never delete or "clean up" files inside the backup root or snapshot folders.** The
  backup root is a managed pool of content-addressed objects: deduplication means one file
  there can be the only physical copy that other rows and older snapshots recover by
  content hash. If a data file does go missing
  (antivirus quarantine and cloud-sync "free up space" features are the usual culprits —
  exclude backup and change paths from both), the next backup run re-copies it from the
  source as long as the source still holds that content, and `-Action Verify` reports any
  row whose bytes are gone from the pool entirely (`PoolUnresolvable`) so you can restore
  the content before the source is also lost.
