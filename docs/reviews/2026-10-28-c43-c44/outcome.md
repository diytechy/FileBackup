# Independent reviews of C43 and C44 (2026-10-27/28)

Two independent Claude Opus 5.5 reviews, each in a fresh context, in a detached
worktree, briefed with the commit and the plan rather than the implementer's
conclusions. Each ran the tests it cites itself. Their repro scripts lived in the
session's scratch folder and are not kept; every finding below has a regression
test instead.

## C43 — prune and the pool check read one manifest at a time (`15ed359`)

Verdict: **ship with fixes**. No data-safety defect. The reviewer reproduced the
data-loss path the commit closes on the parent commit (a damaged copy counted as
supply let prune delete the only good copy: old `Pruned code=0`, new `Refused
code=2 destination-collision`, good copy kept), confirmed old and new
`Get-SnapshotPrunePlan` / `Test-PoolResolves` give identical results on four
real stores and that three real prunes leave byte-identical stores, and ran
Coverage + ContentIndex + StorageForm: 313 passed, 0 failed.

| # | Severity | Finding | Outcome |
|---|---|---|---|
| 1 | Medium | The plan kept the target's row for every endangered key while it read every other manifest; most of a snapshot's own objects are endangered but demanded by no row, so it held close to a second manifest (measured: +48.6 MB on a 20,000-row target, all unused). | Fixed `8512ed2`: the target is read after the demand, keeping source rows only for demanded keys. Test: the plan reads the target's manifest last. |
| 2 | Low | `Publish-PruneManifest` checked and wrote folder by folder, so a changed second destination left the first rewritten while the message said nothing was published (unreachable under the store lock). | Fixed `8512ed2`: every destination is checked before any is written. Test: a changed second destination leaves the first manifest byte-identical. |

## C44 — one store folder per backup set (`14564ba`)

Verdict: **ship with fixes**. Sharding, the layout, `/` as separator, config v3
and both restorers behaved correctly in everything it ran, including a prune
re-homing into an `l` shard, a Windows store restored by `reconstruct.sh` in WSL,
a store written by pwsh on Linux restored on Windows, and drive-not-attached = 4
for every action. It ran the unit suite (970 passed, 0 failed, 1 skipped) and
`bats tests/bash` (152 ok).

| # | Severity | Finding | Outcome |
|---|---|---|---|
| 1 | High | `-RepairStorage` set a misplaced object aside with no check that its content existed anywhere else; when it was the only copy a snapshot needed, the restore went from 0 to 1 (content-missing). | Fixed: a misplaced object whose bytes prove its name is moved back into its own shard folder when that place is free; it is set aside only when that place holds a proven-good copy or its own bytes are proven damaged; anything unproven stays where it is. Tests (BoundedRun): the only copy goes back and the snapshot restores; a misplaced object of other bytes is set aside. Mutation check: with the new branch disabled the only-copy test fails. |
| 2 | Medium | `Assert-StoreLayout` accepted an old store whose backup folder was named `Latest` (or whose snapshots sat in a `changes/` folder beside it) and wrote into it. | Fixed: refused when `Latest` holds `RECONSTRUCT.paths.json` or a kit older than revision 15, or a folder beside `Latest` holds `Snapshot_*` folders. Tests (Engine): each marker refused, run and read-only. |
| 3 | Low | `Reconstruct.ps1` compared the folder name `Latest` case-sensitively on Windows, so `...\latest\RECONSTRUCT.ps1` refused a real store. | Fixed: case-insensitive on Windows. Test (Coverage). |
| 4 | Low | With a store override, the two restorers restored different manifests for a non-store origin (bash: `--from`'s; PowerShell: the store's `Latest`). | Fixed by aligning PowerShell with bash: with `-StoreRootOverride`, a kit run from a folder of its own that holds a manifest restores that manifest; the store supplies the pool. README says so. |
| 5 | Low | A configuration refused at the view check still leaves an empty `<store>/Latest` behind. | Not new (the old engine created both roots before the view check); left as is, recorded here. |

Not a finding but worth knowing: since C44 no pool folder can be a volume root,
so the restorer's volume-root filter in its content scan no longer fires; TC-180
was rewritten with the store at a drive root and still passes.
