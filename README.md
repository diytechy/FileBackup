# FileBackup

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

**The index is checked before anything is restored.** Every `MANIFEST.csv` is
written together with a small witness file, `MANIFEST.csv.meta`, recording that
manifest's row count, byte length, and xxHash128. Both restorers verify the
manifest against its witness *before* writing a single file, so a truncated,
half-written, or replaced index refuses the restore instead of quietly
"succeeding" against a shrunken job. Each dated snapshot carries its own witness
for its own manifest.

A backup written by an older version has no witness; it still restores, and the
log says `UNVERIFIED`. Pass `-RequireWitness` (Windows) or `--require-witness`
(Linux) to refuse an unverifiable index instead.

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
| **3** | Witness verification failed | The index itself is untrustworthy; **no file is written to the target.** | The manifest is damaged — restore from a snapshot or another copy. |
| **4** | Incomplete — host | Rows failed because of *this machine*, not the backup: an unreadable search folder, 7-Zip unavailable for an archive candidate, or an extraction/copy I/O error on an **archive-shaped** object. | **Retriable** — fix the host and run again. |

Since kit revision 8 the split between **1** and **4** is decided by the stored
bytes rather than by the manifest's `Compressed` column. An object carrying no
7-Zip signature that reproduces neither form is damage (**1**), not a failed
extraction (**4**): no retry on a healthy machine fixes it, and classifying it as
retriable sent wrappers into loops over corruption. An object that *does* look
like an archive and will not open is still **4**, because this host's 7-Zip
genuinely may be at fault.

When several apply the precedence is **2 > 3 > 4 > 1**: codes 2 and 3 abort
before anything is written — the manifest's header and witness are checked before
the target folder and the restore log are even created, so a refused restore
leaves the target exactly as it was — and 4 outranks 1 because it is the
actionable one.
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
auto-detected from that location; pass `--backup-root` / `--change-root` to
override (needed when the backup and change folders are not nested — the sidecar's
Windows paths are ignored on Linux). Like the Windows restorer it **fails loudly**:
it verifies the manifest against its `MANIFEST.csv.meta` witness before writing
anything, then restores everything recoverable and exits with the code from
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

`-WhatIf` is for `-Action Prune` only. It binds on every action (pruning needs
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
needs it), rewrites that destination's manifest — re-stamping its witness —
proves that **every** surviving manifest row still resolves, and only then
deletes the folder. The last step out of the `Snapshot_` namespace is a single
rename, so no restore ever sees a half-removed snapshot. Nothing is deleted
until the pool is provably redundant.

It refuses rather than guesses. Removal reports the same status codes as a
restore (see "Restore exit codes"): **0** removed, **1** a batch finished
incomplete but **no data was lost**, **2** usage or precondition (nothing was
mutated), **3** a manifest witness did not verify (nothing was mutated),
**4** a host I/O problem — retriable, and always before the point of no return.
Common refusals: a manifest with no witness at all (pass
`-AllowUnverifiedIndex` for a backup written before witnesses existed), data
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
| `DanglingDataPath` | The row names a data file that is not there. | no |
| `PayloadMismatch` | `-Deep` only: the stored bytes do not reproduce the row's hash/length. | no |
| `BlankRowFormDisagreement` | A row that resolves by content hash, whose `Compressed` disagrees with the copy the restore would find. Harmless with a current restore kit — see below. | no |
| `Unreferenced` | A data file in the folder that no manifest row names. | no |

Repair takes the **bytes as ground truth**: it rewrites `Compressed` and renames
the data file so its name stops lying. It never re-packs or re-compresses
content, never touches the logical columns (path, length, timestamp, hash), and
never migrates layout. Findings it will not touch are reported, not silently
"fixed".

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
            AllowEmptySource   = $false   # true only for an intentional delete-all
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
    "SourceStatePath": "/state",
    "BackupPath": "/backup",
    "ChangePath": "/changes",
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

| Field | Meaning |
|---|---|
| `ConfigVersion` | JSON only, required. Currently `2` (version 1 is refused as too old — it carried the removed `PreserveFolderTree` selector). A config declaring a higher version is refused by name rather than half-understood; a missing/non-integer/out-of-range value is a hard error. |
| `HashRecalcFreq` | When to re-hash an *unchanged* file. `A`/`E`=always, `D`=daily, `W`=weekly, `M`=monthly, `Y`=yearly, `N`=never. |
| `SourceStatePath` | Optional writable folder for the source hash-cache `MANIFEST.csv`. Omit for legacy in-source storage; containers should set a unique path outside the read-only source, backup, and change trees. |
| `CompressEnabled` | `$true`/`true` stores data files as `.7z` (already-compressed extensions are exempt). JSON must use a real boolean, not a quoted string. |
| `CompressProbe` | Optional; `off` \| `excluded-extensions` \| `always` (default `always`), exact lowercase. How the stored form is decided when `CompressEnabled` is on: `off` trusts the already-compressed extension list alone; `excluded-extensions` keeps the list's exemptions and measures everything it would otherwise compress; `always` measures a sample of the bytes of every file at or above 256 KiB, the list serving only the smaller files. |
| `AllowEmptySource` | Defaults to `$false`/`false`, refusing to empty a previously populated backup when its source is unexpectedly empty. Set `true` only for an intentional delete-all. |
| `BrowseView` | `off` (default) or `index`: generate a browsable, manifest-derived `INDEX.tsv` + per-folder HTML view of the backup, outside the backup root. `link` is reserved and refused by name. |
| `ViewPath` | Where the view is written. Defaults to `<BackupPath>_View`; must lie outside the backup and change roots and on the backup volume. |

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

### Already-compressed extensions

With `CompressEnabled` on, files with these extensions are stored verbatim
rather than re-packed (`Compressed=No`), because re-compressing them costs CPU
and gains nothing:

```
.zip .7z .z7 .rar .gz .bz2 .xz .tgz .zst .esd
.mp4 .mkv .mov .avi .webm .mpg .mpeg .m2ts .m4v .wmv .flv
.mp3 .aac .flac .ogg .opus .m4a
.jpg .jpeg .png .webp .gif .heic .heif
.jar .pack .sav
```

Matching is on the **extension only**, case-insensitively, never on the path.
Office and text formats (`.docx`, `.txt`, …) are deliberately **not** on the
list — they compress well and are stored as `.7z`. The list lives in exactly one
place, `$script:NonCompressibleExtensions` in `Modules/FileBackup.Common.psm1`;
this table is checked against it by TC-096.

Changing the list changes what a *future* run stores. **Nothing already stored is
ever re-formed** — there is no migration, in either direction. Existing data
files keep the form they were written with, in the backup root and in every
snapshot alike, and are restored correctly regardless (see "Restoring an older
snapshot" below). The same is true of flipping `CompressEnabled`: it governs
content written after the flip and nothing else. A mixed-form store is normal,
because compression is decided per file.

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
outcome as a process exit code instead of only a terminating error: `0`
complete, `1` a backup set failed, `2` the configuration could not be loaded —
the file is **missing** or unreadable, or it violates the contract above — the
same usage/precondition class as the restore table in "Restore exit codes". A
supervisor can therefore tell "your config is wrong, retrying will not help"
from "the backup failed". A refused run creates **nothing**: no log directory
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
mkdir -p /srv/backups/source-state /srv/backups/current /srv/backups/changes /srv/backups/logs
docker build -t filebackup:local .
docker run --rm --network none --read-only \
  --security-opt no-new-privileges --cap-drop ALL \
  --tmpfs /tmp:rw,noexec,nosuid,nodev \
  -v /srv/homehub/filebackup.json:/config/FileBackup.json:ro \
  -v /srv/library:/source:ro \
  -v /srv/backups/source-state:/state \
  -v /srv/backups/current:/backup \
  -v /srv/backups/changes:/changes \
  -v /srv/backups/logs:/logs \
  filebackup:local
```

`compose.example.yaml` expresses the same boundary using
`FILEBACKUP_SOURCE`, `FILEBACKUP_STATE`, `FILEBACKUP_DESTINATION`,
`FILEBACKUP_CHANGES`, and `FILEBACKUP_LOGS`. The source and config are read-only;
source-state, backup, change, and log mounts must be writable by the selected
`FILEBACKUP_UID`/`FILEBACKUP_GID`. Give each backup set its own state folder.
The entrypoint preserves FileBackup's exit code, so HomeHub can wrap the job and
post its own NagLight result without coupling this project to that service.

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

Pruning writes to `/changes` **and** `/backup`, so both must be mounted
writable for that action. See "Snapshot retention (pruning)" above for the
status codes and the refusal set.

### Build, verify, and move the image

The checked-in helper uses the same commands locally and in CI. Its test creates
a real compressed backup in the container, checks the six-file recovery kit,
restores it in a second container, and compares every file byte-for-byte:

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
D:\Data\report.docx  -hash→ E:\…\DataStore\Ab92Cd 5K.7z          E:\…\DataChanges\
D:\Data\photo.jpg    -hash→ E:\…\DataStore\Xy7Ko 3M.jpg            Snapshot_2026_03_19_22_50_06\
                            MANIFEST.csv                            ← full point-in-time MANIFEST.csv
                            MANIFEST.csv.meta                          + its own MANIFEST.csv.meta
                            RECONSTRUCT.ps1/.bat/.sh                   + only the superseded bytes
                            FileBackup.Common.psm1                     + a restore kit
                            System.IO.Hashing.dll                  Snapshot_2026_02_10_08_00_00\  …
                            FileBackupState.json
```

Identical content is stored once (keyed on `(xxHash128, length)`); extra logical names just
point at the same data file. The backup root is always the **latest** state. Each older
state is a `Snapshot_<date>` folder named for the backup whose state it preserves — it holds
that point's full manifest plus only the bytes superseded afterward, and resolves everything
else by hash from the backup root. The **most recent run has no snapshot** (it *is* the live
backup), and a run that changes nothing creates none.

**A note on your source folder:** each run keeps its hash cache as a
`MANIFEST.csv` (and now a `MANIFEST.csv.meta` beside it) in the source-state
location, which by default is the source root itself. Set `SourceStatePath` to
keep both out of the tree being backed up.

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
| `MANIFEST.csv.meta` | beside every `MANIFEST.csv` | **The witness** — `Version`, `Rows`, `Bytes`, `XxH128`, `Written`. Lets a restore prove the index it is about to trust is the index that was written. |
| `MANIFEST.csv` + `MANIFEST.csv.meta` | the **source-state** location (`SourceStatePath`; the source root by default) | **The hash cache.** The same format, used to decide what changed without re-reading every byte. Point `SourceStatePath` somewhere else to keep it out of the tree being backed up. |
| `DIRECTORIES.csv` | backup root, and each `Snapshot_<date>` folder, when there is anything to say | **The directory sidecar.** One row per folder that holds no file anywhere beneath it, or that carries a `Hidden`, `System`, `ReadOnly` or `NotContentIndexed` attribute - the two things a one-row-per-file index cannot express. Advisory: it is not witnessed, and a restore never fails over it. A tree with no empty or attributed folder gets no such file at all. |
| `FileBackupState.json` | backup root | Two dates: `LastHashRun` (when the last full re-hash swept) and `LastBackupRun` (which dates the next snapshot). Written by rename, so a crash cannot leave it torn. |
| `RECONSTRUCT.paths.json` | backup root | The source/backup/change paths this store was written with, so a restore in place needs no arguments. Ignored once the folder is moved elsewhere. |
| `backup.log` | change root | The run log: what was hashed, copied, staged, refused. |
| `RECONSTRUCT.log` | the **restore target** | Written by a restore, not a backup — the per-file record of what was recovered and how. |
| `.viewstamp` | the view root (`ViewPath`), only with `BrowseView: index` | A digest of the manifest rows the browse view mirrors, so a stale view is rebuilt rather than trusted. |
| `RECONSTRUCT.ps1` · `RECONSTRUCT.cmd` · `RECONSTRUCT.command` · `reconstruct.sh` · `FileBackup.Common.psm1` · `System.IO.Hashing.dll` | backup root and every snapshot | The restore kit — the reason a backup folder needs nothing else to give your files back. (Stores older than kit revision 10 carry `RECONSTRUCT.bat` in place of the `.cmd`.) |

Those names are **infrastructure at the root only**. A file of your own called
`MANIFEST.csv` in a subfolder is ordinary data and is backed up as such.

One detail about the witness is deliberate and worth knowing: `MANIFEST.csv` is
written in place, and only the witness beside it is published by atomic rename.
A crash between the two therefore leaves a witness that *disagrees* with the
index — which refuses the restore (exit 3) rather than quietly passing, and the
next successful run rewrites both. It fails in the safe direction on purpose.

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
- **A run refuses because `Temp` exists (stale `Temp` folder error).** A prior run aborted
  mid-flight — and the leftover `Temp` under your `ChangePath` may hold the **only physical
  copy** of bytes that older snapshots recover by hash (the run moves superseded and removed
  content there before finalizing the snapshot). **Do not delete it.** Safe recovery:
  (1) move the whole `Temp` folder *aside*, outside `ChangePath` (a rename is instant and
  loses nothing); (2) re-run the backup, which is now unblocked; (3) run `-Action Verify`
  and test-restore your oldest snapshot — if verification is clean and restores complete,
  discard the moved folder; (4) if any snapshot restore reports missing content, copy the
  moved folder's *data files* into the backup root under any non-colliding names (skip its
  `MANIFEST.csv` — that is the interrupted run's staging copy of the index) — both restorers
  find content by hash regardless of filename — and verify again.

  **Most of these now recover themselves.** A `Temp` that is *empty*, or that holds
  *only* a stale `RUN.inprogress` owner record and nothing else, is **reclaimed
  automatically**: the run confirms with a second sample — taken a while later — that the
  previous owner really is gone and is not merely quiet, moves the old folder aside,
  recreates `Temp` and carries on, logging `[SR-075/reclaimed]`. Nothing is deleted to get
  there. A run that is genuinely still alive is refused, not stomped
  (`[SR-075/owner-live]`), as is a `Temp` held by a prune (`[SR-075/prune-held]`).
  The four steps above remain the operator's path for the one case that is never
  reclaimed: a `Temp` that holds **content** (`[SR-075/content-refused]`).

  **`Temp.stale-<utc>-<hex>` folders** are that moved-aside prior staging folder — created
  by the automatic reclaim, and the same thing you produce by hand at step (1). They sit
  beside `Temp` under `ChangePath`, are safe to inspect and safe to copy files out of, and
  are **never deleted automatically while they hold anything**: an aside folder that proves
  to contain nothing but the old owner record (or nothing at all) is cleaned up for you,
  and any other one is kept until you work through steps (3) and (4).
- **Where a run's log lives.** Per-set detail — the staging-lock messages above included —
  is written to **`backup.log` inside that set's `ChangePath`**. `Backup_Global.log` (beside
  the config unless `-GlobalLogPath` / `FILEBACKUP_LOG_PATH` says otherwise) is the
  orchestrator's sink: configuration, dependency checks, cross-set failure summaries and
  mail. It is legitimately near-empty while a set is running, so read `ChangePath\backup.log`
  when you want to know what a run is doing or why it refused.
- **Unexpected empty source.** A previously populated set fails before mutating the backup
  when its source becomes empty (often an unavailable share). Set `AllowEmptySource = $true`
  on that set only when deleting every backed-up file is intentional.
- **Never delete or "clean up" files inside the backup root or snapshot folders.** The
  backup root is a managed pool of content-addressed objects: deduplication means one file
  there can be the only physical copy that other rows and older snapshots recover by
  content hash. If a data file does go missing
  (antivirus quarantine and cloud-sync "free up space" features are the usual culprits —
  exclude backup and change paths from both), the next backup run re-copies it from the
  source as long as the source still holds that content, and `-Action Verify` reports any
  row whose bytes are gone from the pool entirely (`PoolUnresolvable`) so you can restore
  the content before the source is also lost.
