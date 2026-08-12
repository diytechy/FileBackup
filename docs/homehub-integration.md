# HomeHub integration — findings against FileBackup, and whether it can ship as a container

**Written 2026-08-09 from the HomeHub side.** Nothing in this repo was changed to
produce it. It exists because the Owner has directed that FileBackup be brought
back and folded into the HomeHub backup flow, and a cross-check was run first.

> **PROVENANCE, AND THE LIMIT ON IT.** Everything below was found by **reading
> this repo**, cross-checking it against defects found and fixed the same day in
> HomeHub's bash reimplementation (`MiniPC-Deployer/stack/backup/*`). Each
> finding was then attacked by an independent adversarial pass whose instruction
> was to refute it at a specific line. **FileBackup itself was never executed.**
> So: the code paths are real and cited, but no failure here has been
> *reproduced*. Treat every row as "verified by reading, needs a reproducing
> test" — which is also the fastest way to close them, since `tests/` covers
> none of them today.

---

## 0. The one that stops everything: FileBackup cannot start on Linux

`Modules/FileBackup.Common.psm1:59`

```powershell
$script:SevenZipDefaultPath = Join-Path $env:ProgramFiles '7-Zip\7z.exe'
```

This is at **module scope**, so it runs at `Import-Module` time. On any
non-Windows host `$env:ProgramFiles` is `$null`, and PowerShell 7.6 does not
tolerate that — measured:

```
Join-Path [null]  -> THROWS: ParameterBindingValidationException
Join-Path [empty] -> THROWS: ParameterBindingValidationException
```

**So today the module fails to import on Linux and the tool never runs at all.**
Not a degraded run — no run. This is the first thing to fix for any Linux or
container target, and it is two lines.

There is a second half worth fixing in the same change: the 7-Zip location is a
module-scoped constant with **no configuration key**. It appears only at
`Common.psm1:59` (definition), `:83` (export), `Engine.psm1:210` and
`Reconstruct.ps1:207` (use). A container will have `7z` at `/usr/bin/7z`, so the
path needs to be a config field or an environment override, not a constant.

`Common.psm1:60` (`FfprobePathDefault = 'C:\ffmpeg\bin\ffprobe.exe'`) has the
same Windows assumption but is a plain string, so it degrades rather than
throwing — it only means media metrics are always off on Linux.

**Double-check:** confirm the throw on a real Linux `pwsh` rather than inferring
it from `Join-Path` semantics on Windows. That is one `docker run` once a base
image exists.

---

## 1. Findings, by what they cost

Severity is about consequence, not effort.

| # | finding | where | consequence |
|---|---|---|---|
| **A** | **Missing 7-Zip is treated as "do not compress", not as an error.** `Reconstruct.ps1:254` gates the decompress branch on `Compressed -eq 'Yes'` **AND** `Test-Path $sevenZipPath`. With 7-Zip absent that falls through to the plain-copy `else` at `:262-264`, which writes the **`.7z` container bytes to the destination under the original filename** (`holiday.jpg` containing 7z bytes). The row never enters `$unrestored`, `:267` passes, `:272-273` print "Reconstruction finished", exit 0. Nothing re-hashes what was written. | `Reconstruct.ps1:254,262-264,267,272` | **Silent data corruption on restore.** Combined with finding 0, this is the *default* behaviour on Linux. |
| **B** | **The same absence corrupts the backup side, permanently.** `$compressFlag` is computed from config + extension only (`Engine.psm1:866`) and never consults tool availability; it drives both the stored filename (`.7z` at `:883`/`:889`) and the manifest's `Compressed` column (`:909`). The actual compression is gated separately at `Engine.psm1:402` on `$ShouldCompress -and $SevenZipPath`. So raw bytes get stored under a `.7z` name while the manifest records `Compressed='Yes'`. | `Engine.psm1:402,866,883,889,909` | The manifest states something false about the bytes. |
| **C** | **…and the migration engine cannot see the lie, because it asks the manifest.** `Sync-BackupStorageLayout` decides "needs transform" at `Engine.psm1:486` by comparing the manifest's own `Compressed`/`StoredAsHashSize` bookkeeping against the current configuration — never the actual stored form. Once a row is written wrong, a later run on a machine that *does* have 7-Zip evaluates `needsTransform = false` and skips it forever. | `Engine.psm1:486` | **A guard that tests its own output.** The component whose entire job is reconciling stored form against configuration is structurally unable to notice its own error. |
| **D** | **`Find-DataFileByHash` returns one `$null` for four different causes**: nothing matched; the search folder was unreadable/offline/deleted (`:63` enumerates with `-ErrorAction SilentlyContinue`); 7-Zip absent so every `.7z` candidate was skipped (`:70`); or the lookup threw (`:77-78` catches every exception type into a `Write-Verbose`). The caller logs one WARN, "cannot recover `<rel>` by hash". | `Reconstruct.ps1:63,70,77-78,87` | One message for four causes — the shape that cost HomeHub three hours on `cifs-utils`. |
| **E** | **Reconstruct verifies only what its manifest lists.** `$main` is built purely from `MANIFEST.csv` rows (`:158-162` via `Read-RawManifest` at `:142-147`, a bare `Import-Csv`), iterates exactly those keys (`:216`), and reaches its verdict by counting only `$unrestored` (`:267-272`). Nothing counts what *should* have been there, so a truncated manifest makes the job **smaller** and it still prints "Reconstruction finished". | `Reconstruct.ps1:142-147,158-162,216,267-272` | A partial restore reports success. HomeHub hit the identical defect in `restore.sh` and fixed it — see §3. |
| **F** | **A missing or unparseable `FileBackupState.json` destroys superseded history.** `Read-BackupState` returns an empty hashtable both when the file is absent (`Engine.psm1:85`) and when parsing fails (`:91-94`, `catch → return @{}`), so `$priorBackupDate` is `$null` (`:1126`). The run then proceeds: `Save-SupersededData` **moves** the old bytes of every changed file into staging (`:1009`) and `Move-RemovedFilesToStaging` moves the last reference of every removed file (`:963`) — physically out of the live backup root. `Complete-ChangeFolder` is reached with `$ManifestChanged=$true` and `$SnapshotDate=$null`, and its first branch (`:1054`) **deletes staging**, while logging "first backup". | `Engine.psm1:85,91-94,963,1009,1054,1126` | **Irreversible loss of the only surviving copies**, reported as a normal first run. |
| **G** | **An existing-but-empty source is read as "everything was deleted."** `RemovedFromSource` covers every row, staging takes all the bytes, and the live backup is emptied in one run. There is no plausibility gate. | backup-side diff path | HomeHub's reimplementation **has** this guard (`INGEST_ALLOW_EMPTY` refuses to mirror-delete from a share that came up empty) and the spec it was written from does not. |
| **H** | **No destination preflight.** Nothing checks that the backup destination is a real mounted volume rather than an empty directory of the same name on the system disk. | — | HomeHub's step 0 exists precisely for this; a `nofail` mount that did not mount otherwise produces a green backup onto the wrong disk. |
| **I** | **No retention of any kind.** Nothing prunes, rotates or ages out a snapshot — verified by enumerating every `Remove-Item` in the product: `Engine.psm1:527/551` (temp files during layout migration), `:561` (an old data file, only after the manifest points at its new location), `:666` (a duplicate data file during cross-snapshot dedup, with `:681` blanking `DataPath` so restore still recovers by hash), `:1054` (the current run's staging), `Common.psm1:439` (a 7-Zip temp dir). None touches a `Snapshot_*` folder. | whole product | **Not a bug — a design gap for this use.** Growth is bounded by deduplication alone. Adopting this model does not remove "the drive fills"; it changes it from *loudly, in a few nights* to *silently, eventually, with no knob*. |
| **J** | **Backup-side failures stop at the first one.** Two `Move-Item` loops abort on their first failure and there is no failure count. (The restore side is fine — `$unrestored` is the right shape.) | backup-side move loops | One error line can hide many. |

### A false parity claim, worth deleting on sight

`bash/reconstruct.sh:381` **dies up front** when 7-Zip is missing — the correct
behaviour, and the opposite of finding **A**. Its comment says it degrades only
where the PowerShell version degrades. That is not true, and a comment asserting
false parity is worse than no comment: it tells a reader the two are equivalent
when the bash one is safer.

---

## 2. What FileBackup does BETTER, and should be carried over rather than lost

This is not a one-way list, and the integration should keep these.

- **Per-file compression decisions.** `Engine.psm1:517/883` chooses `.7z`-or-raw
  **per row**, from `Common.psm1:52-57`. HomeHub's reimplementation coarsened
  this into a **per-set 60% byte threshold**, so a Documents tree that is 61%
  photos currently has its *text* stored uncompressed too. FileBackup's
  granularity is the better design.
  *(Though the bash side's extension **list** is broader — it adds `jar tgz zst
  gif webm ogg sav pack`. Merge the list, keep the granularity.)*
- **The storage model itself** — one live tree plus delta snapshots, everything
  resolved by `(xxHash128, Length)` from a shared pool. This is the reason for
  the whole integration.
- **Time injection done properly.** `HashRecalcFreq` D/W/M/Y takes an injectable
  `$Now` and a backdatable `Set-LastHashRun -When`, unit-tested that way, and
  `FileBackup.ps1 -BackupTime` pins a run's completion date. HomeHub has no
  equivalent seam and should copy this rather than reach for a system clock.
- **The bytes stay ordinary files on disk.** A `DataPath` points at a real file;
  a blank one is recovered by content hash. This is why a 20 KB
  `bash/reconstruct.sh` can exist at all, and it is the strongest argument for
  this model over an opaque-repo tool.
- **Complete traceability.** `scripts/trace.py --strict` reports
  `UN=21 SR=27 LLR=26 TC=41 orphans=0`.

---

## 3. What HomeHub already solved that should be ported back

HomeHub's bash service hit several of the same defects and fixed them on
2026-08-09. The fixes are cheap to mirror and two of them are directly
transferable:

| HomeHub fix | relevance here |
|---|---|
| **Restore reconciles three witnesses** — manifest count, table count, and an independent census of the archive — because the manifest count is *not* independent (it is written by the same loop). | Directly addresses finding **E**. **The fix does not port as-is**: it uses `tar -t` on a container archive, and FileBackup writes a file-per-file tree with no container to census. FileBackup needs a *different* independent witness — the obvious candidate is a count of data files actually present in the pool. **This is the main open design question.** |
| **Distinct exit codes per cause** (skipped set / unknown set / damaged run / not trustworthy) instead of one status. | Addresses finding **D**. |
| **Capacity preflight before writing anything**, refusing loudly. | Addresses finding **H**. Note this repo already found and fixed its own version — `docs/status.md` records `[BLOCKER→FIXED] SR-023 capacity check was a no-op` (the `throw` sat inside a `try/catch` that swallowed it). Worth checking the backup side has the same guard the restore side now does. |
| **Empty-source refusal with an explicit override.** | Addresses finding **G**. |

---

## 4. Can it ship as a container HomeHub imports and hands a config to?

**Yes, and it is a good fit — with four things to settle first.** The shape works
because the backup and the restore can be decoupled:

> **Back up inside the container; restore without it.** `bash/reconstruct.sh` is
> a standalone 20 KB bash restore needing only coreutils, `xxhsum` and `7z`. So
> an emergency recovery never depends on the container, the image, or PowerShell
> being present. That is a genuinely strong property and it is the main reason to
> prefer this over an opaque-repo tool.

**What works out of the box:**

- **Dependencies are packageable.** `xxhash` (0.8.2) and `p7zip-full` are both in
  Ubuntu 24.04 apt, so HomeHub's offline apt bake can carry them and the image
  can be built without network at install time.
- **Config is already a file with a path parameter.** `FileBackup.ps1
  -ConfigPath` (default `$HOME/BackupConfig.xml`) reads CLIXML. Mount a config
  and point at it — no interactive step.
- **`-NonInteractive` exists** and is the documented mode for scheduled runs.
- **`-BackupTime`** gives the scheduler a deterministic seam.
- **Exit codes are already meaningful**, which HomeHub's never-silent-green
  contract needs.

**Four things to settle:**

1. **Finding 0 must be fixed** or the module will not import. Non-negotiable.
2. **The SMTP credential does not survive the platform change.** `CredSetEx.ps1`
   builds the config with `Get-Credential` and relies on CLIXML encrypting it
   "under the current Windows user" — that is DPAPI, and it does not exist on
   Linux. **This is not a blocker, because mail is optional:** run with
   `-NoMail`, or omit the `Secrets`/`SmtpServer` fields entirely. HomeHub does
   not want email anyway — it wants a NagLight feed post. **Do not port the
   credential path; delete it from the container's config.**
3. **`System.IO.Hashing` is fetched from NuGet on first use** (or by
   `tests/Setup.ps1`, or `-AutoInstallDeps`). **An offline HomeHub box cannot
   fetch it at runtime** — it must be baked into the image at build time, and
   `-AutoInstallDeps` must never be the mechanism in production.
4. **The reporting contract has to be added.** HomeHub requires that every
   failure posts `ok=false` to NagLight and exits non-zero. FileBackup exits
   non-zero but has no feed concept. A thin wrapper around the entrypoint is
   probably right — the container's `CMD` runs FileBackup, captures its status,
   and posts. That keeps this repo unaware of NagLight.

**Two mount-level cautions specific to HomeHub's hardware:**

- The library and backup drives are **NTFS** in production (Owner ruling A15,
  2026-07-30) and **exFAT** on the flash stand-ins used during bring-up. Neither
  carries POSIX ownership. FileBackup stores its own metadata, so this is
  survivable — but the container must not rely on uid/gid or symlinks, and
  Docker will `chown` a bind-mount source **that it had to create**, which on a
  FAT-family filesystem returns EPERM and aborts the whole compose. HomeHub hit
  exactly this. **Pre-create every bind-mount path before starting the
  container.**
- **The policy question is the Owner's, not this document's.**
  `HOMELAB_TOPOLOGY.md` item 3 states "No `.bat`/`.ps1` anywhere in the
  pipeline". A container arguably honours the intent — nothing on the host is
  PowerShell — while contradicting the letter. That ruling needs revisiting
  explicitly rather than being quietly worked around.

---

## 5. The double-check list

In priority order. None of these needs HomeHub — they are all local to this repo.

1. **Reproduce finding 0** on a real Linux `pwsh`. Everything else about the
   container plan depends on it.
2. **Reproduce A and B with 7-Zip absent** — a `CompressEnabled` set, no `7z` on
   PATH, then a round-trip. Confirm the restored file contains 7z container
   bytes under its original name and that the run exits 0. This is the most
   damaging finding and the one most worth having a test for.
3. **Reproduce C**: write a row wrong, then re-run *with* 7-Zip present, and
   confirm `Sync-BackupStorageLayout` never repairs it.
4. **Reproduce E**: truncate a `MANIFEST.csv`, restore, confirm "Reconstruction
   finished" and exit 0. Then decide what FileBackup's *independent* witness
   should be, since HomeHub's archive census has no analogue here.
5. **Reproduce F**: delete or corrupt `FileBackupState.json` between two runs
   that supersede data, and confirm whether the superseded bytes survive. This
   one I am least certain of — the control flow was traced by reading and it
   depends on `Complete-ChangeFolder`'s first branch being reached with
   `$SnapshotDate = $null`. **Verify before trusting the severity.**
6. **Confirm G** — that an empty source really does empty the live backup, with
   no plausibility gate anywhere in the diff path. I read the mechanism but did
   not find an explicit gate; absence of evidence, so check.
7. **Decide on retention (I).** This is a design decision, not a defect. Whatever
   HomeHub adopts needs a bound on growth, and FileBackup has none.
8. **Delete the false parity comment** at `bash/reconstruct.sh:381`.

> Findings **0**, **A**, **B**, **C**, **D**, **E** and **I** were each confirmed
> by an independent adversarial pass at the cited lines. **F** and **G** were
> traced but are the two most worth reproducing before acting on.
