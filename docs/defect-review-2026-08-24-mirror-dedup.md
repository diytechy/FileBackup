# Defect review — Mirror-mode dedup, restore trust, and source enumeration

**Found:** 2026-08-24, on real hardware (HomeHub bench box, Ubuntu, `filebackup:local`
container, exFAT USB stand-in drives), while proving the library backup before
committing 12 TB of real disks to it. Five defects, two of which lose or corrupt data.

**Configuration under test.** One backup set, `PreserveFolderTree: true` (Mirror),
`CompressEnabled: true`, `HashRecalcFreq: W`, retention NONE (the consumer never
prunes). **Mirror mode matters:** D-1 and D-2 below are specific to it, and the
hash-addressed storage mode appears immune for a structural reason given in D-1.

**Status of the evidence.** Everything in the "What happened" and "Where it is in the
code" sections was either observed directly on the box or read out of the source in
this repo. The bench machine has since been powered down and its drives are being
swapped for the production ones, so **no further experiment could be run** to settle
the one open mechanism question — it is marked as open in D-1 rather than guessed at.

---

## Summary

| | Defect | Severity | One line |
|---|---|---|---|
| **D-1** | Stale cross-path dedup reference | **Data loss** | A row that borrows another path's data file is never revisited when that file's owner changes, so the borrowed bytes are overwritten and every row still claiming them is orphaned. Mirror mode only. |
| **D-2** | Restore trusts `DataPath` without checking the hash | **Silent corruption** | A row resolved through its own `DataPath` is decompressed and written with no comparison against the row's `xxH2Hash`. Wrong bytes restore as `Reconstruction complete`, exit 0. |
| **D-3** | `CandidateError` outranks `ContentMissing` | Misdirection | One unrelated unexpandable `.7z` anywhere in the pool turns "your bytes are gone" (exit 1) into "fix this host and retry" (exit 4). |
| **D-4** | Hidden/dot-prefixed source files are never backed up | **Silent omission** | `Get-ChildItem` without `-Force` skips them. They appear in no manifest and the run reports success. |
| **D-5** | Same-run duplicates are each stored in full | Space | The dedup lookup consults only the *prior* backup, so identical files first seen in one run are stored twice. |

D-1 and D-5 are the same mechanism seen from two sides, and they are **backwards with
respect to safety**: the engine deduplicates against earlier runs, where the reference
can go stale, and does not deduplicate within a run, where it would be safe.

---

## The question this review kept provoking: how can a row be tagged `Duplicate` when the contents have changed?

Short answer: **it cannot, and it never was.** Nothing mis-detects a duplicate, and
modification time is not being abused. The tag was correct on the day it was written.
What goes wrong is that it is never re-examined.

Three separate things have to be held apart:

1. **`Duplicate` is a source-side annotation, and it is not what causes byte sharing.**
   `Update-SourceManifest` groups the freshly walked source by `(xxH2Hash, Length)` and,
   inside a group of more than one, marks every row except the shortest `RelativePath`
   as `Duplicate = 1` (`Modules/FileBackup.Engine.psm1:492-498`). It is a label
   describing this run's source. It does not decide where bytes are stored.

2. **The byte sharing is decided separately, against the *previous backup*.**
   `Invoke-BackupFileGroup` looks for a row already in the backup with the same
   `(hash, length)` and a non-blank `DataPath`; if one exists, every entry in the group
   **adopts that `DataPath` verbatim and writes no bytes of its own**
   (`Engine.psm1:2817-2838`). In Mirror mode, that adopted `DataPath` is the *other
   file's* relative path with `.7z` appended. So one row's bytes now live at a location
   named after a different file.

3. **When the owner's content later changes, only the owner is reconsidered.**
   `Compare-SourceToBackup` calls a file new-or-changed when its own length, mtime or
   hash differs from the backup's row for that same `RelativePath` — or when its backup
   row has a blank `DataPath` (`Engine.psm1:2758-2775`). The borrower's file did not
   change, so it is not in the diff, and its row is not rewritten. Meanwhile the owner
   goes down the copy branch, which in Mirror mode computes the destination as
   `"$rel.7z"` — **the same path it already occupies** — and overwrites it.

So the sequence is entirely reasonable at every individual step:

```
run N     A and B hold identical bytes.
          A (shorter path) stores them.  B's row: DataPath -> A's file, hash H.   ← correct
run N+1   A's content is replaced.
          A is rehashed (H -> H'), A's data file is REWRITTEN IN PLACE with H'.
          B did not change, so B's row is never looked at.
          B's row still says: DataPath -> A's file, hash H.                        ← now a lie
```

Nothing tagged B as a duplicate of something it no longer matches. B was tagged
correctly, and then the ground moved underneath it. The missing concept is a
**back-reference from a data file to the rows that borrowed it** — the refcount the
codebase already implements in three other places:

- `Sync-BackupStorageLayout` transforms a whole `(hash,length)` group together or not at
  all, explicitly "refcount-safe (SR-051)" (`Engine.psm1:585, 631, 661`);
- removed-file eviction "refcounts shared data files first" (**B9**, `Engine.psm1:18`);
- the prune path re-homes a shared data file before deleting the snapshot that held it
  (`Copy-ReHomedDataFile`, `Test-PoolResolves`).

The ordinary "an existing file's content changed" path is the one route that mutates a
shared data file without consulting who else points at it.

---

## D-1 — A stale cross-path dedup reference destroys content that other rows still claim

**Severity: data loss.** Under retention NONE, where nothing is ever supposed to become
unrestorable.

### How this arises in real life

It needs nothing exotic — only two copies of one file, and a later edit to one of them:

- the same photo in `Media/2024/` and in `Media/ToSort/`, and later you re-export or
  rotate the one in `ToSort/`;
- a document and the copy you made before editing it, where you then edit the *original*;
- an installer or ISO kept in two places, one of which is replaced by a newer build with
  the same filename;
- any tree that has been merged from two sources, which is most large personal libraries.

A 4 TB media and document library is close to guaranteed to contain duplicate files.

### What happened

Cycle 10 of the bench drill created `awkward/twin-of-small.bin` as a byte-identical copy
of `d1/small-64k-zero.bin` (64 KiB). The engine stored no bytes for the twin:

```
"permtest/d1/small-64k-zero.bin.7z","permtest/awkward/twin-of-small.bin","65536",
    …,"FD5EE061C8433A0F33B202D302B65CAA","Yes","Original","1",""
```

Correct at that moment: the named file did hold `FD5EE061`.

Cycle 13 replaced `d1/small-64k-zero.bin` with different bytes. Its own row was updated
to the new hash `ADF2C034`, and its data file was rewritten in place. Afterwards:

```
row 'permtest/awkward/twin-of-small.bin' claims FD5EE061C8433A0F33B202D302B65CAA
'permtest/d1/small-64k-zero.bin.7z'      actually holds 058A9BCB955093E1DCE4784D6D1639AA
```

`twin-of-small.bin` is a live file that **never changed**, and the backup can no longer
produce it.

The damage is not limited to the live mirror. Every snapshot row for the old content had
been reduced to a blank `DataPath` — "recover me by hash from the pool" — because that
content was, at the time, still present. Extracting every archive on the drive
afterwards found `FD5EE061` **nowhere**. Measured across the run:

```
cycle 12   170 hash-recovered rows, ALL resolvable                    PASS
cycle 13   the overwrite: 14 of 190 orphaned, 1 pointed-to row wrong  FAIL
cycle 15   15 of 210 hash-recovered rows orphaned, over 19 manifests  FAIL
```

One ordinary edit orphaned fifteen manifest rows across nineteen snapshots.

### Where it is in the code

| Step | Location |
|---|---|
| Group the source by `(hash,length)`, label all but the shortest path `Duplicate=1` | `Engine.psm1:492-498` |
| Adopt an existing backup row's `DataPath`, storing no bytes | `Engine.psm1:2817-2838` |
| Mirror-mode `DataPath` is the row's own `RelativePath` + `.7z` | `Engine.psm1:~2848` |
| A file is new-or-changed only by its OWN metadata or a blank `DataPath` | `Engine.psm1:2758-2775` |

### Why hash-addressed mode looks immune

In the non-Mirror mode the destination is `Get-HashSizeFileName -HashHex $hash -Length
$len` — content-addressed. Changed content therefore produces a *different* filename, so
the old data file is never overwritten and every row still pointing at it stays valid.
The collision in Mirror mode comes from the data file being addressed by **path**, which
means "the current content of this source file" rather than "these particular bytes",
while dedup hands that address to rows that mean the latter.

This has not been re-tested under hash-addressed mode on hardware; it is a reading of
the code, and it should be confirmed before being relied on.

### Open question, not settled

Two mechanisms could explain the old bytes being gone rather than preserved in the
snapshot that supersedes them:

- **(a)** the change path overwrote the data file in place and no snapshot copy was ever
  taken for it; or
- **(b)** a snapshot copy *was* taken, and `Optimize-ChangeFolders` then deleted it as a
  duplicate — because a live row (the borrower's, still claiming `FD5EE061`) appeared to
  prove that the content was still present in the mirror.

(b) is the more likely of the two, because `Optimize-ChangeFolders` was observed doing
exactly that kind of deletion earlier in the session, logging
`Removed duplicate datapath … (hash/len: …)` and blanking the corresponding row. If (b)
is what happens, the borrower's stale row is not merely a casualty of the overwrite —
it is the thing that authorises deletion of the last surviving copy, which makes the
stale reference considerably more dangerous than it first appears.

**Discriminating experiment** (one run, needs the bench box back):
create `A` and `B` with identical content in one run; back up; replace `A`'s content;
back up; then inspect the snapshot created by that second run. If it contains a data
file for the old content, (a) is wrong and (b) is the mechanism. `run.log.13` from the
2026-08-24 drill would answer it directly — it is at `/var/tmp/permdrill/run.log.13` on
the bench box, if that box is brought up before `/var/tmp` is cleared.

### Direction

The shape of a fix already exists in the codebase. `Compare-SourceToBackup` re-enters a
row into the diff when its `DataPath` is blank (SR-053/WP7 — "damage being healed"), and
blanking a row is how `Test-BackupManifest` already marks bytes as lost. So a change
path that, before overwriting a data file, blanked or re-materialised every *other* row
pointing at it would land on machinery that already exists rather than needing new
concepts. Copy-on-write for the borrower, or simply refusing to reuse a Mirror-mode
`DataPath` across relative paths, are the other two obvious shapes.

---

## D-2 — The restore writes wrong bytes and reports success

**Severity: silent corruption.** Independent of D-1 and worth fixing on its own.

### How this arises in real life

Any restore performed after D-1 has occurred. Also any store where a data file has been
altered underneath the manifest — a partial write, a filesystem repair that salvaged the
wrong block, a user "tidying" the backup drive, or bit rot on media that has been sitting
for a year, which is exactly the interval a snapshot history is kept for.

### What happened

Restoring the newest state of the bench store:

```
Reconstruction complete: 20 file(s).                            ← exit 0
restored awkward/twin-of-small.bin   sha256 45c1b811…          ← the other file's new content
oracle   awkward/twin-of-small.bin   sha256 de2f2560…          ← 64 KiB of zeros, correct
```

The operator is told the restore is complete, and one file's contents are silently
someone else's.

### Where it is in the code

`bash/reconstruct.sh:645-698`. When a row's `DataPath` names a file that **exists**, the
file is expanded (`sevenzip_to_file`) or copied (`cp -f`) straight to the destination.
`d_hash[i]` is consulted only in the branch where the named file is *missing*, to drive
pool recovery. There is no post-write verification against the row's `xxH2Hash`.

Hash-*recovered* rows are safe by construction: they were located by matching that hash.
So the exposure is exactly the pointer path.

The file states the correct principle itself, four lines above the code that departs from
it:

> `# A non-blank DataPath is a locator HINT, not the content authority`

It is treated as the content authority whenever the hint resolves. `Reconstruct.ps1`
should be checked for the same gap — the two implementations are kept deliberately
equivalent, so if one verifies and the other does not, that is itself a finding.

### Direction

Hash what was written and compare against the row before counting it restored; on
mismatch, fall through to the same `find_by_hash` pool recovery that a missing file
already triggers, and if that fails, count the row unrestored as **ContentMissing**. The
cost is one hash per restored file, which is the same order as the decompression already
being done, and the restore already hashes candidates during pool recovery.

---

## D-3 — One bad `.7z` in the pool misreports where the fault is

**Severity: misdirection**, no data effect.

### How this arises in real life

A library containing any `.7z` that this host cannot expand:

- a truncated or interrupted download;
- a file renamed to `.7z` that never was an archive;
- an archive using a codec the *restore* host's 7-Zip build does not support — very
  plausible on the rescue machine a restore actually happens on, which is by definition
  not the machine that made the backup.

Only one such file has to exist anywhere in the pool.

### What happened

```
WARN: [CandidateError] 'permtest/d1/small-64k-zero.bin' — archive candidate
      '…/permtest/awkward/notreally.7z' could not be expanded
ERROR: Reconstruction INCOMPLETE: 1 file(s) … (0 content-missing, 1 host)   ← exit 4
```

`notreally.7z` is a text file with a `.7z` name and has nothing to do with the row being
restored. The bytes for that row were genuinely gone (D-1), which is exit 1, CONTENT.
Exit 4 means "rows failed for reasons on this machine — retry after fixing the host", so
the operator is sent to inspect their rescue machine while the actual fault is in the
backup. During the bench drill this affected **twelve** historical restores.

### Where it is in the code

`bash/reconstruct.sh:288-306`. While scanning the pool for `(hash,length)`, any candidate
that fails to expand records `host_candidate`. If the scan then finds nothing, the
precedence block reports `CandidateError` **above** `ContentMissing`.

The ordering is right for `DependencyMissing` (7-Zip absent is a genuine host fault with
a precise remedy, as the comment says) and wrong for `CandidateError`: a *different*
file failing to open is not evidence about whether the wanted bytes exist. Note the
same label is also used correctly at line 689, where extraction of *this row's own*
archive fails — that one really is a host problem.

### Direction

Rank `CandidateError` below `ContentMissing` when it was raised by a candidate that was
not this row's own `DataPath`, and keep both in the log. The distinction is already
carried in the code — the failing candidate's path is captured in `host_candidate`.

---

## D-4 — Hidden and dot-prefixed source files are never backed up

**Severity: silent omission.** Arguably the worst of the five for a Linux source, because
it needs no unusual sequence at all: it is the steady-state behaviour.

### How this arises in real life

It is not a corner case on Linux. Dot-prefixed names are ordinary content:
`.config/`, `.ssh/`, `.gitignore`, `.env`, Syncthing's `.stfolder` and `.stignore`,
`.thunderbird/`, and anything under a dot-directory — which is skipped wholesale, not
just the dot-file itself. On Windows the same call skips Hidden and System attribute
files, which is narrower but still includes files a user deliberately hid.

The engine was written for Windows, where "hidden" is an attribute and this exclusion is
defensible. On Linux, `-Force` is the difference between "user data" and "invisible".

### What happened

`permtest/awkward/.leading-dot` (128 bytes, an ordinary readable file) appeared in **no
manifest, ever**, across fifteen backup runs. The wrapper reported success every time.
Asked of the shipped image directly:

```
$ docker run --rm --entrypoint pwsh filebackup:local -c '(Get-ChildItem /probe -File -Recurse).Count'
default: 1
-Force : 2
```

### Where it is in the code

`Modules/FileBackup.Engine.psm1:121` (`Get-DataFile`) and the fallback walk at
`Engine.psm1:438`, both `Get-ChildItem -LiteralPath … -Recurse -File` with no `-Force`.

### Direction

Add `-Force` to both walks, or make it configurable per set with the Linux default being
on. Whichever is chosen, the more important half is that **the count of files skipped by
policy should be reported by the run**, so an exclusion is a number an operator can see
rather than an absence they cannot. A backup that omits files silently is
indistinguishable from one that did not.

---

## D-5 — Identical files first seen in one run are each stored in full

**Severity: space only.** No correctness impact, and included because it is the same
mechanism as D-1 viewed from the other side.

### What happened

Two 512-byte files with identical content, created in the same run
(`awkward/café-ünïcode.txt` and `awkward/日本語.txt`), were each stored as their own
archive. One was labelled `Duplicate=1`, but it still had a data file of its own — the
label and the storage decision disagree.

### Where it is in the code

`Engine.psm1:2817` — `$existingBackupWithHash` is computed **once, from `$BackupDb`**,
before the loop over the group's entries. `$BackupDb` is the *prior* backup, so files
stored earlier in this same run are not in it, and every entry of a brand-new group takes
the copy branch.

### Why it matters beyond space

Put beside D-1, the two behaviours are exactly inverted with respect to risk:

| | Deduplicated? | Safe? |
|---|---|---|
| Identical files in the **same** run | No | would be safe — both are new, neither is a stale pointer |
| Identical file matching an **earlier** run | Yes | unsafe in Mirror mode — this is D-1 |

Any fix for D-1 should probably resolve both, since a design that makes cross-run reuse
safe (ownership, refcounts, or content-addressed data files) also makes intra-run reuse
straightforward.

---

## What was not proven

- The **(a) vs (b)** mechanism question in D-1. See the discriminating experiment there.
- Whether **`Reconstruct.ps1`** shares D-2's missing verification. Only `reconstruct.sh`
  was read and only it was exercised on the box. The two are kept deliberately
  equivalent, so this needs checking either way.
- Whether **hash-addressed (non-Mirror) storage** is genuinely immune to D-1. That is a
  reading of the code, not a test result.
- D-1's blast radius was measured on a store of ~20 files over 15 runs. How it scales to
  a real library — where a single popular duplicate could be referenced by far more rows
  — is unknown, and the direction of the error is not reassuring.

## Reproducing this

The harness is `scripts/verify/library-permutation-drill.sh` in the **HomeHub** repo. It
drives the production wrapper over a deliberately hostile source tree (0 B to 8 MiB,
seven directory levels, unicode / 200-character / dot-prefixed names, files named after
the restore kit's own infrastructure, a genuine `.7z` and a fake one) through fifteen
mutation cycles, asserting after every cycle that the manifest names exactly the source's
files and that every row naming a `DataPath` resolves to a file whose content hashes to
what the row claims. It fails at **cycle 13** — the mutation that causes D-1 — rather
than fifteen cycles later in a restore.

Its findings were independently re-run and confirmed by a second agent on the same
hardware, which additionally verified the safe case by physical scan rather than by
manifest: two full delete/re-add generations leave exactly one copy of the content on
the drive (`PHYSICAL_MATCH_COUNT=1`).

**Ordinary delete-then-re-add is not affected by any of this.** Deleting a file and later
restoring the identical file deduplicates correctly, keeps one copy, and leaves the
pre-delete snapshot reconstructable byte-for-byte. The defect is specifically two paths
holding the same content *at the same time*, followed by a change to one of them.
