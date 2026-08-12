# HomeHub integration — findings against FileBackup, and whether it can ship as a container

> **Implementation update (2026-08-12).** This document began as a read-only
> review, so the detailed findings below preserve that review's evidence and
> wording. The repository now includes a runnable container boundary:
> [`Dockerfile`](../Dockerfile), [`compose.example.yaml`](../compose.example.yaml),
> a non-root [`container/entrypoint.sh`](../container/entrypoint.sh), and a
> portable JSON configuration example. Finding 0 is fixed by cross-platform tool
> discovery plus `FILEBACKUP_7ZIP_PATH` / `Tools.SevenZipPath`; finding B is
> closed fail-safe by refusing a compression-enabled run when 7-Zip is absent.
> `System.IO.Hashing.dll` and 7-Zip are baked into the image, and the entrypoint
> keeps email/runtime installation disabled and propagates the process exit
> status. Docker was not installed in the review workstation, so the image still
> needs a real Linux build/run in CI before container support should be called
> release-verified. NagLight posting remains intentionally outside this repo: a
> HomeHub wrapper should translate the preserved exit status into its feed event.

**Written 2026-08-09 from the HomeHub side.** Nothing in this repo was changed to
produce it. It exists because the Owner has directed that FileBackup be brought
back and folded into the HomeHub backup flow, and a cross-check was run first.

> **PROVENANCE, AND THE LIMIT ON IT.** Everything below was found by **reading
> this repo**, cross-checking it against defects found and fixed the same day in
> HomeHub's bash reimplementation (`MiniPC-Deployer/stack/backup/*`). Each
> finding was then attacked by an independent adversarial pass whose instruction
> was to refute it at a specific line. **FileBackup itself was never executed for
> the original review.** So: the cited code paths were real at the time, but each
> finding remains "verified by reading, needs a reproducing test" until a later
> disposition explicitly names its test evidence. Line numbers are historical
> review coordinates and may move as fixes land; function names and requirement
> IDs are the stable references.

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

### A — Missing 7-Zip silently corrupts PowerShell restores

**Where:** `Reconstruct.ps1:254,262-264,267,272` (historical coordinates).

`Reconstruct.ps1` gates decompression on `Compressed -eq 'Yes'` **and** a
present 7-Zip executable. With 7-Zip absent, it falls through to the plain-copy
branch and writes `.7z` container bytes under the original filename. The row is
not marked unrestored, so the script reports success.

**Consequence:** silent data corruption on restore.

### B — Missing 7-Zip can make the backup manifest lie

**Where:** `Copy-SourceFileToBackup` and `Invoke-BackupFileGroup` in
`FileBackup.Engine.psm1` (historically lines 402, 866, 883, 889, and 909).

The compression flag controls the `.7z` filename and `Compressed='Yes'`
manifest value, while the actual compression call is separately gated on a
non-empty 7-Zip path. Raw bytes can therefore be stored under a `.7z` name while
the manifest says they are compressed.

**Consequence:** the manifest states something false about the stored bytes.

### C — Layout migration trusts the same potentially false metadata

**Where:** `Sync-BackupStorageLayout` in `FileBackup.Engine.psm1` (historically
line 486).

The migration decision compares the manifest's `Compressed` and
`StoredAsHashSize` values with current configuration, not the physical file
form. A later run with 7-Zip available can therefore consider a malformed row
already correct and leave it unrepaired.

**Consequence:** the reconciliation guard can validate its own bad output.

### D — Hash recovery collapses distinct failures into one message

**Where:** `Find-DataFileByHash` in `Reconstruct.ps1` (historically lines 63,
70, 77-78, and 87).

The function returns `$null` when nothing matches, a search folder is
unreadable or absent, 7-Zip is unavailable for archive candidates, or lookup
throws. The caller emits the same "cannot recover by hash" warning for all four.

**Consequence:** operators cannot distinguish missing content from a missing
dependency or inaccessible storage.

### E — Restore can only verify the rows its manifest still contains

**Where:** `Read-RawManifest` and the reconstruction loop in `Reconstruct.ps1`
(historically lines 142-147, 158-162, 216, and 267-272).

The restore dictionary comes only from `MANIFEST.csv`, and success counts only
rows that failed during that loop. Truncating the manifest makes the job
smaller, so an incomplete restore can still report success. Counting physical
data files cannot close this by itself because dedup means logical rows and
stored files are not one-to-one.

**Consequence:** a partial restore can report success.

### F — Missing backup state can discard superseded history

**Where:** `Read-BackupState`, `Save-SupersededData`,
`Move-RemovedFilesToStaging`, and `Complete-ChangeFolder` in
`FileBackup.Engine.psm1` (historically lines 85, 91-94, 963, 1009, 1054, and
1126).

A missing or unparseable `FileBackupState.json` becomes an empty state, so the
prior backup date is `$null`. Changed and removed bytes are moved into staging,
but `Complete-ChangeFolder` treats a null snapshot date as "first backup" and
deletes that staging folder.

**Consequence:** the only superseded copies can be deleted during an otherwise
normal-looking run. This finding especially needs a reproducing test.

### G — An empty source is interpreted as deleting everything

**Where:** the backup diff and removal path.

When an existing source enumerates zero files, every prior row is
`RemovedFromSource`; no plausibility gate distinguishes an intentionally empty
source from an unavailable or mis-mounted one.

**Consequence:** the live backup can be emptied. HomeHub has an explicit
`INGEST_ALLOW_EMPTY` override for this case.

### H — The backup destination has no mount-identity preflight

**Where:** backup-set path resolution and orchestration.

Nothing establishes that the destination is the intended mounted volume rather
than an ordinary directory created at the expected mount point.

**Consequence:** a failed `nofail` mount can produce a green backup on the wrong
disk.

### I — Snapshot retention is unbounded

**Where:** the whole product; no removal path prunes a `Snapshot_*` folder.

Nothing rotates or ages out snapshots. Deduplication slows growth but does not
bound it.

**Consequence:** this is a design gap, not a defect; the backup volume will
eventually fill without an external retention policy.

### J — Backup-side move loops stop at the first failure

**Where:** `Move-RemovedFilesToStaging` and `Save-SupersededData`.

The move loops abort on the first error and do not aggregate failures as the
restore side does with `$unrestored`.

**Consequence:** one visible error can hide the remaining failures.

### Disposition from the 2026-08-12 review

- **A — fixed and regression-tested.** The PowerShell restorer now preflights
  7-Zip whenever the authoritative manifest contains compressed rows and fails
  before writing archive bytes as restored content.
- **B — fixed and regression-tested.** A backup configured for compression now
  fails dependency initialization when 7-Zip is unavailable, before processing
  any set; it can no longer write raw bytes under a `.7z` name.
- **F — fixed and regression-tested.** A non-initial backup no longer treats
  missing/corrupt run state as a first run and discards staged history.
- **G — fixed and regression-tested.** An empty-source transition is refused by
  default and requires an explicit opt-in.
- **Recovery-kit gap — fixed and regression-tested.** New live backups and dated
  snapshots carry `RECONSTRUCT.bat`, `RECONSTRUCT.ps1`, and `reconstruct.sh`;
  the POSIX script remains self-contained and does not require PowerShell.
- **C, D, E, H, I, and J — open** unless a later status entry records a
  reproducing test and disposition. Containerization is tracked separately.

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
- **Complete traceability.** `scripts/trace.py --strict` is part of the Smoke
  gate and currently reports zero traceability orphans.

---

## 3. What HomeHub already solved that should be ported back

HomeHub's bash service hit several of the same defects and fixed them on
2026-08-09. The fixes are cheap to mirror and two of them are directly
transferable:

| HomeHub fix | relevance here |
|---|---|
| **Restore reconciles three witnesses** — manifest count, table count, and an independent census of the archive — because the manifest count is *not* independent (it is written by the same loop). | Directly addresses finding **E**. **The fix does not port as-is**: it uses `tar -t` on a container archive, while FileBackup writes a deduplicated file pool. Counting pool files cannot prove how many logical paths belonged in a manifest. FileBackup needs a separately persisted witness, such as atomically written manifest metadata carrying a row count and digest. The exact witness and trust model remain an open design question. |
| **Distinct exit codes per cause** (skipped set / unknown set / damaged run / not trustworthy) instead of one status. | Addresses finding **D**. |
| **Capacity preflight before writing anything**, refusing loudly. | Addresses finding **H**. Note this repo already found and fixed its own version — `docs/status.md` records `[BLOCKER→FIXED] SR-023 capacity check was a no-op` (the `throw` sat inside a `try/catch` that swallowed it). Worth checking the backup side has the same guard the restore side now does. |
| **Empty-source refusal with an explicit override.** | Addresses finding **G**. |

---

## 4. Can it ship as a container HomeHub imports and hands a config to?

**Yes, and it is a good fit.** The shape works
because the backup and the restore can be decoupled:

> **2026-08-12 implementation update:** this repository now includes a non-root
> one-shot `Dockerfile`, `compose.example.yaml`, a POSIX entrypoint, portable JSON
> configuration, Linux-safe tool discovery, and the hashing DLL baked into the
> image. The remaining HomeHub boundary work is mount/sentinel validation,
> NagLight status translation, retention policy, container CI, and supply-chain
> pinning. The original four-item analysis below is retained as review history.

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
- **The policy question is settled — the container is allowed.** When this
  document was first written, `HOMELAB_TOPOLOGY.md` item 3 read "No `.bat`/`.ps1`
  anywhere in the pipeline", which a PowerShell container contradicts on the
  letter while meeting the intent. **The Owner softened it on 2026-08-09**: they
  are now "avoided in the pipeline where possible". The rule existed to stop the
  hub depending on Windows-shaped tooling — and a runner that is PowerShell only
  *inside the image*, with nothing on the host being PowerShell, satisfies that.
  **The constraints that did not move**, and which this integration must still
  meet: the hub grows no PowerShell dependency on the host; bash stays the
  default; every failure posts `ok=false` and exits non-zero; and the backup must
  remain restorable **without its own runtime** — which is exactly what
  `bash/reconstruct.sh` provides, and why it should not be allowed to rot.

---

## 5. Original double-check list

This was the reproduction agenda from the 2026-08-09 reading pass. The current
dispositions above supersede completed items; the list remains useful context for
the still-open findings.

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
