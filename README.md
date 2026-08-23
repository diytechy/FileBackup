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

Open the backup folder and run **`RECONSTRUCT.bat`**. It asks for a target directory and
writes a `RECONSTRUCT.log` next to the restored tree. To restore a *historical* state,
run the `RECONSTRUCT.bat` inside a specific dated `Snapshot_<date>` folder instead — it
reproduces exactly the state as of that backup. The backup folder is self-contained —
it carries `RECONSTRUCT.bat`, `RECONSTRUCT.ps1`, `reconstruct.sh`, the hashing module,
`System.IO.Hashing.dll`, and a path sidecar — so restore works on a machine without
this repo.

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
can tell the failure classes apart without reading the log. `RECONSTRUCT.bat` and
`reconstruct.sh` return these directly; `Reconstruct.ps1` throws a terminating
error unless you pass `-ExitCode` (which `RECONSTRUCT.bat` does for you).

| Code | Class | Meaning | What to do |
|---|---|---|---|
| **0** | Complete | Every manifest row restored. | Nothing. |
| **1** | Incomplete — content | Everything salvageable was restored; the remaining rows' bytes do not exist anywhere in the data pool. | Real data loss: check an older backup. |
| **2** | Precondition / usage | Nothing was attempted — bad or missing arguments, no `MANIFEST.csv`, an unrecognizable manifest, target inside the backup, a missing required tool, or not enough free space. | Fix the invocation or environment. |
| **3** | Witness verification failed | The index itself is untrustworthy; **no file is written to the target.** | The manifest is damaged — restore from a snapshot or another copy. |
| **4** | Incomplete — host | Rows failed because of *this machine*, not the backup: an unreadable search folder, 7-Zip unavailable for an archive candidate, or an extraction/copy I/O error. | **Retriable** — fix the host and run again. |

When several apply the precedence is **2 > 3 > 4 > 1**: codes 2 and 3 abort
before anything is written, and 4 outranks 1 because it is the actionable one.
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

## Config format

`FileBackup.ps1 -ConfigPath` accepts CLIXML (`.xml`) and JSON (`.json`). CLIXML
remains useful for a Windows-only SMTP `PSCredential`; JSON is the portable,
secret-free format intended for containers and HomeHub.

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
            PreserveFolderTree = $false   # $true = mirror tree; $false = "<hash> <size>" names
            AllowEmptySource   = $false   # true only for an intentional delete-all
        }
    )
} | Export-Clixml -Path $HOME\BackupConfig.xml
```

The equivalent container-oriented JSON is:

```json
{
  "ConfigVersion": 1,
  "Tools": { "SevenZipPath": "/usr/bin/7z" },
  "BackupSets": [{
    "Name": "MainData",
    "SourcePath": "/source",
    "SourceStatePath": "/state",
    "BackupPath": "/backup",
    "ChangePath": "/changes",
    "HashRecalcFreq": "W",
    "CompressEnabled": true,
    "PreserveFolderTree": false
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
| `HashRecalcFreq` | When to re-hash an *unchanged* file. `A`/`E`=always, `D`=daily, `W`=weekly, `M`=monthly, `Y`=yearly, `N`=never. |
| `SourceStatePath` | Optional writable folder for the source hash-cache `MANIFEST.csv`. Omit for legacy in-source storage; containers should set a unique path outside the read-only source, backup, and change trees. |
| `CompressEnabled` | `$true` stores data files as `.7z` (already-compressed extensions are exempt). |
| `PreserveFolderTree` | `$true` mirrors the source tree under the backup root; `$false` stores content-addressed `<hashShort> <sizeShort>.<ext>` files referenced via the manifest. |
| `AllowEmptySource` | Defaults to `$false`, refusing to empty a previously populated backup when its source is unexpectedly empty. Set `$true` only for an intentional delete-all. |

You can list multiple `BackupSets`; each is processed independently.

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

### Manifest columns

`DataPath` · `RelativePath` · `Length` · `LastWriteTimeStr` · `xxH2Hash` · `Compressed` ·
`StoredAsHashSize` · `Duplicate` · `MediaMBPerSec`. A blank `DataPath` means "recover by
content hash" — the restore script scans for a matching file (decompressing `.7z`
candidates as needed).

Every `MANIFEST.csv` is accompanied by **`MANIFEST.csv.meta`**, a five-line
`Key=Value` witness (`Version`, `Rows`, `Bytes`, `XxH128`, `Written`) written by
the same code path that writes the manifest and published by atomic rename. It
is what lets a restore prove the index it is about to trust is the index that was
written. See "Restore exit codes" above.

---

## Repository layout

```
FileBackup.ps1            Entry point (reads config, runs each backup set)
Reconstruct.ps1          Restore script (deployed standalone into each backup folder)
Modules/
  FileBackup.Common.psm1   Restore-safe primitives (hashing, manifest I/O, 7-Zip, …)
  FileBackup.Engine.psm1   Backup engine (walk, diff, dedup, migrate, snapshots)
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
- **Stale `Temp` folder error.** A prior run aborted mid-flight; remove the leftover `Temp`
  folder under your `ChangePath` and re-run.
- **Unexpected empty source.** A previously populated set fails before mutating the backup
  when its source becomes empty (often an unavailable share). Set `AllowEmptySource = $true`
  on that set only when deleting every backed-up file is intentional.
