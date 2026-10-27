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
├── Latest/                      the latest state: MANIFEST.csv, every object in use, the kit
├── Snapshot_<date>/             one per superseded state, as today
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
| L1 | Configuration: one key, `StorePath`, replaces `BackupPath` and `ChangePath` (ConfigVersion 3). A configuration that still names them is refused before anything is touched, with a message saying how to convert it. |
| L2 | No migration. A store in the old layout is set aside and keeps restoring with the kits already inside it. The new kit knows only the new layout; `-Action Verify -RefreshKits` refuses an old-layout store rather than give it a kit that cannot read it. |
| L3 | The browse view's default location is `<StorePath>/View`, so everything of one set lives in one folder. Neither the engine nor a restorer reads it. |
| L4 | The one-mount check stays (a cheap directory rename): `Latest` and the snapshots must still be on one mount, and a Linux bind mount could split them. |
| L5 | HomeHub: the container uses `StorePath=/store`. IF-001 and HomeHub's branch change to match. The Owner sets the existing HomeHub backup aside and starts a clean one. |
| L6 | Built as one work package after the review's fix batches merge, with an independent review before it lands. |

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
- **Container:** `container/entrypoint.sh`, `compose.example.yaml`, the image
  smoke test, `scripts/Invoke-Container.ps1`.
- **Docs:** README, AGENTS.md sections 1-4, the generated maps,
  [interfaces.md](../interfaces.md) / IF-001.
- **Tests:** unit, the integration sweep (`tests/Run-All.ps1`, groups G1-G9), bats.

## Left to the implementer, to settle and report

- The exact name and case of `Latest`, and how the kit recognizes an old-layout
  store in order to refuse it cleanly.
- Whether any restorer override besides the store override is still needed.

## Done when

Lint clean; the full unit suite, the integration sweep, bats and shellcheck,
and the container smoke test pass on the merged tree; an independent review of
the package has reported and its findings are adjudicated; AGENTS.md, README and
IF-001 describe the new layout; HomeHub's side is ready for a clean backup.
