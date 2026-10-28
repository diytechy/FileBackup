# Work package: one store folder per backup set (plan call C44)

*Ruled by the Owner 2026-10-27. Not yet built: it starts after the fix batches of
the [2026-10-26 data-loss review](../reviews/2026-10-26-data-loss/consolidated.md)
merge, because it touches the same code.*

## Why

A snapshot holds only what was superseded, so most of its rows name objects
that still live in the latest state. Today the latest state (`BackupPath`) and
the snapshots' folder (`ChangePath`) are two folders the user names and places
freely. A restore of a moved store (a USB drive under another letter, a Linux
restore) cannot use the absolute paths it recorded, so it guesses the latest
state's folder among the change folder's siblings; with two backup sets under
one parent it cannot pick, and every such row falls to a content scan that never
finishes at scale (review item A6). One folder per set removes the guess.

## The layout

```
<StorePath>/                     one folder per backup set (container: /store)
├── Latest/                      the latest state: MANIFEST.csv, the kit, and
│   ├── 2a/ … zz/                every object in use, one folder down (L8)
│   └── …
├── Snapshot_<date>/             one per superseded state, as today (objects flat)
├── Snapshot_<date>/
├── View/                        the browse view (SR-062), when turned on
└── Temp.lock, backup.log, Incoming/, Building_*/, Verify/   run files
```

From any state folder (`Latest` or a `Snapshot_*`) the store is its parent, and
the pool is `Latest` plus every `Snapshot_*` beside it. Nothing else in the store
is part of the pool.

## The Owner's rulings

| # | Ruling |
|---|---|
| L1 | Configuration: one key, `StorePath`, replaces `BackupPath` and `ChangePath` (ConfigVersion 3). The latest state's folder is named exactly `Latest`. A configuration that still names them is refused before anything is touched, with a message saying how to convert it. |
| L2 | No migration. A store in the old layout is set aside and keeps restoring with the kits already inside it. The new kit knows only the new layout; `-Action Verify -RefreshKits` refuses an old-layout store rather than give it a kit that cannot read it. |
| L3 | The browse view's default location is `<StorePath>/View`, so everything of one set lives in one folder. Neither the engine nor a restorer reads it. |
| L4 | The one-mount check stays (a cheap directory rename): `Latest` and the snapshots must still be on one mount, and a Linux bind mount could split them. |
| L5 | HomeHub: the container uses `StorePath=/store`. IF-001 and HomeHub's branch change to match. The Owner sets the existing HomeHub backup aside and starts a clean one. |
| L6 | Built as one work package after the review's fix batches merge, with an independent review before it lands. |
| L7 | (2026-10-27) Paths recorded in the store use `/` as the separator, whatever host writes them: `RelativePath` in `MANIFEST.csv` and in `DIRECTORIES.csv`. Today each records the writer's own separator (`\` on Windows, `/` in the container), on `main` as on this branch. The change is lossless: no Windows name holds `/`, and SR-055 already refuses a Linux name holding `\` as unportable. It rides on this package because L2 means no store has to be migrated, so nothing reads both forms. |
| L8 | (2026-10-27) An object in `Latest` lives one folder down, in a folder named by the first two characters of its name, lowercased: `Latest/ab/aB…_<len><ext>`. Fixed: no configuration key, no other length. The snapshots stay flat. Why: a Linux file manager over FUSE (ntfs-3g) takes more than two minutes to open a flat `Latest`, while a snapshot holds only superseded objects, usually few. `DataPath` stays the bare name (both restorers refuse a separator in it); the folder is a pure function of the name and of which state folder holds the object, so nothing searches for it. Lowercase because Windows treats `Ab` and `aB` as one folder and Linux as two. A shard folder's name matches `^[2-9a-z]{2}$`, **`l` included**: `L` is in the alphabet, so lowercasing produces it (a first proposal left `l` out and would have hidden about 4% of objects from every listing). Folders fill unevenly, by up to about 2x: the first character only reaches the first 46 digits (`2`..`o`, since 2^128 / 57^21 is about 45.6) and lowercasing pairs some of them. Accepted, because a person looking for an object by name looks in the folder its name starts with. It rides on this package for L7's reason: no store has to read both layouts. Independent review of an opencode argon proposal: a per-set `ShardPrefixLength` (0..4) was rejected, because a kit that must work without the configuration would have to try every length. |

## Scope (what changes)

- **Configuration:** schema and loader (`Import-BackupConfiguration`,
  `Test-BackupConfigurationShape`, the published JSON schema), the PowerShell
  and JSON examples in README, `Resolve-BackupSetPaths` (C25/C26 re-read for one
  root: a store drive not attached is still 4; a store that holds snapshots but
  no `Latest` is refused, never answered with a fresh full backup).
- **Engine:** every place that derives a path from `BkpPath`/`ChgPath` (the run,
  the lock, residue clean-up, the object index, retention, Verify, the browse
  view, `New-ReconstructScript`).
- **Restorers, both:** root detection becomes "the parent of the state folder";
  the path sidecar (`RECONSTRUCT.paths.json`) and the sibling and child guesses
  (C21, C32) are removed; the override parameters are reduced to one store
  override. `-RefreshKits` refuses an old-layout store (L2).
- **Separator (L7):** the source walk, `Get-SourceDirectoryRecord`, every
  comparison of a walked path against a manifest row (change detection, the
  frozen-prefix and unreadable-prefix checks, infrastructure names, C42's
  case-only check), retention, Verify and the browse view; both restorers turn
  `/` into the host's separator only for filesystem calls (`to_posix` and
  `ConvertTo-LocalRelativePath` become the reverse or go away).
- **Shard folders (L8):** one function in Common, so the kit carries it, gives
  an object's path from its state folder and name; every place that builds an
  object's path in `Latest` or lists `Latest`'s objects uses it:
  `Publish-StagedObject` (creates the shard folder before the rename),
  `Move-SupersededObject` and the rename of re-added content back out of a
  snapshot, prune's re-homing into `Latest`, the object index and its listing
  damage check (`Get-StoreObjectIndex`, `Get-ListedObjectDamage`,
  `Move-DamagedStoreObject`), `Get-BackupContentIndex` / `Get-FolderFileSet` /
  `Test-FolderHoldsFile`, the storage-form audit and its repair (a misnamed
  object is renamed inside its own shard folder), Verify's object audit and its
  set-aside (`Verify/<folder>/<name>` stays flat), the browse view's links, and
  both restorers' row lookup and name index (`New-StoredObjectNameIndex`,
  `build_name_index`). Both content scans already recurse. Nothing may take a
  state folder from an object's directory any more (that is now a shard
  folder), e.g. where `Get-BackupKitRevision` finds the kit. An emptied shard
  folder is left in place.
- **Container:** `container/entrypoint.sh`, `compose.example.yaml`, the image
  smoke test, `scripts/Invoke-Container.ps1`.
- **Docs:** README, AGENTS.md sections 1-4, the generated maps,
  [interfaces.md](../interfaces.md) / IF-001.
- **Tests:** unit, the integration sweep (`tests/Run-All.ps1`, groups G1-G9), bats.

## Left to the implementer, to settle and report

- How the kit recognizes an old-layout store in order to refuse it cleanly.
- Whether any restorer override besides the store override is still needed.
- Whether the new kit refuses a `RelativePath` holding `\` or still maps it
  (only an old-layout manifest can carry one, and L2 refuses those).
- Where the engine converts to `/`: once at the walk, so every later comparison
  sees one form, is the expected shape.
- What happens to a misplaced object in `Latest` (at its top level, or in
  another name's shard folder). Expected: it is not part of the pool, so a run
  stores that content again in its right place; Verify reports it, and
  `-RepairStorage` moves it into `Verify/` like any other duplicate.

## Settled by the implementer (2026-10-27)

Recorded as they were made; each is reported to the Owner with the package.

- **S1 - one key outside, the same two roots inside.** The configuration names
  only `StorePath`. The loader derives `BackupPath = <StorePath>/Latest` and
  `ChangePath = <StorePath>` on the normalized set, so every engine step keeps
  its two-root parameters and their meaning (the latest state; the folder that
  holds the snapshots and the run files) and only path derivation changes.
  `BackupPath` or `ChangePath` in a configuration is refused by name (JSON and
  CLIXML alike), with the conversion in the message.
- **S2 - an old-layout store is refused, not adopted.** A `StorePath` that holds
  `MANIFEST.csv` itself (an old backup root named directly), or a folder beside
  `Latest` that holds one (the R8 layout's `backup/` beside `changes/`), or that
  holds snapshots but no `Latest` (C26 re-read for one root), is refused with 2
  before anything is written (`Assert-StoreLayout`). An empty or new
  `StorePath` starts a store.
- **S3 - the kit recognizes its layout by its own folder's name.** A restorer
  runs only from a folder named exactly `Latest` or matching `^Snapshot_`; the
  store is that folder's parent and the pool is `<store>/Latest` plus every
  `<store>/Snapshot_*`. Run from anywhere else it refuses with 2 (that is how an
  old-layout store, or a kit copied out of a store, is told apart), unless the
  one store override is given. The path sidecar and the sibling and child
  guesses (C21, C32) are gone. Kit revision 15.
- **S4 - shard folders are decided by which folder holds the object.** One
  Common function gives an object's path from its state folder, its name and
  whether that folder is the latest state; the engine passes "is the backup
  root", the restorers "is `<store>/Latest`". Nothing infers it from a folder's
  name, so a test or a tool that names its roots differently still agrees.

- **S5 - a misplaced object is set aside, not adopted.** (The "left to the
  implementer" item above.) The listing of the latest state reads a file only
  from its own shard folder (`Get-StoredObjectFile`), so retention, the run's
  index and both restorers' name indexes agree that a file elsewhere in
  `Latest` - at its top, or in another name's shard folder - is not an object.
  The run stores its content again in its right place while the source holds
  it. `-Action Verify` reports it as `MisplacedObject` (`Get-MisplacedStoreObject`,
  read only by Verify, so a run pays nothing), and `-RepairStorage` moves it
  into `Verify/` like a duplicate.
- **S6 - the kit still maps a `\` in a recorded path on a POSIX host.** (The
  L7 item above.) This engine never writes one, so mapping costs nothing and
  keeps a hand-edited or older manifest restoring as it did; refusing it would
  add a failure mode for no gain.
- **S7 - the view may sit inside the store only as `<StorePath>/View`.** (L3.)
  Anywhere else inside the store it could be `Latest`, a snapshot or a run
  folder, and the view root is wiped on every refresh; outside the store the
  rails are as before (no overlap with the store or the source, same volume).
- **S8 - no path sidecar, and its parameter went with it.** `New-ReconstructScript`
  takes only `-BackupRoot`; the kit has six files. `RECONSTRUCT.paths.json`
  stays on the infrastructure list because older stores hold one.
- **S9 - the remedy wording names `StorePath`.** Messages that told the user to
  "back up to a fresh BackupPath" now say "fresh StorePath"; the one-mount
  refusal names Latest and its store and keeps the phrase "one volume and one
  mount", which the container check matches.

## Done when

Lint clean; the full unit suite, the integration sweep, bats and shellcheck,
and the container smoke test pass on the merged tree; a store written on
Windows and one written in the container hold byte-identical `RelativePath`
values for the same tree, and each restores on the other platform; tests index,
restore, prune and Verify sharded objects, one of them in an `l` folder (a name
starting or continuing with `L`); an independent review of
the package has reported and its findings are adjudicated; AGENTS.md, README and
IF-001 describe the new layout; HomeHub's side is ready for a clean backup.
