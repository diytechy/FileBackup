# Native FileBackup preview

This branch adds the Rust executable alongside the existing PowerShell engine.
Use a **new, empty StorePath** for the native preview. No older executable/store
version is designated supported for native continuation. Existing backups keep
restoring with their own carried kits. Do not point a native writer at production
history as a conversion experiment.

Extract the **whole package**, keeping `tools/7zip` beside `filebackup` or
`filebackup.exe`. Native backup, verification and retention use the included
official 7-Zip 26.05 helper (`7za.exe` on Windows, `7zz` on Linux/macOS).
No separate 7-Zip installation, compiler or PowerShell runtime is required.
Compression uses `-mx=5 -mmt=2` with the official default dictionary. Helper calls
have finite deadlines and bounded output; verification streams decoded bytes
through the content hash without extracting archive-supplied paths.
The package includes 7-Zip license notices and its corresponding source archive.
Optional media-duration reporting still uses locally configured `ffprobe`.
PowerShell/bash recovery remains independent and has its own prerequisites below,
including external 7-Zip for compressed objects. See the shipped
[support matrix](native-support.md) for exercised coverage
and remaining qualification work.

## Configure and run

Use absolute source and store paths. These examples use POSIX paths; on Windows
substitute paths such as `D:\Source` and `E:\BackupStore` and `filebackup.exe`.
The helper refuses to overwrite an existing configuration.

```sh
filebackup configure --config backup.json --source /data/source --store /data/backup --name documents
filebackup validate --config backup.json
filebackup backup --config backup.json
filebackup snapshots --config backup.json
filebackup verify --config backup.json --deep
filebackup verify --config backup.json --deep --repair-storage
filebackup prune --config backup.json --snapshot 2026_11_06_12_00_00 --dry-run
filebackup prune --config backup.json --snapshot 2026_11_06_12_00_00
filebackup refresh-kits --config backup.json
```

An omitted action means backup. JSON stdout carries per-set results; progress goes
to stderr. Exit codes are 0 complete, 1 incomplete/content findings, 2 refused input
or configuration, and 4 busy/host/tool stop. Aggregate precedence is 2, then 4,
then 1. Explicit repair preserves uncertain bytes in `Verify`; inspect those
bytes before manually clearing them. A content hash verifies byte agreement with
the selected definitions, not provenance or source completeness.

ConfigVersion 3 retains `BackupSets`, `Tools` and `Secrets`. Set keys are `Name`,
`SourcePath`, `StorePath`, `HashRecalcFreq` (A/E/D/W/M/Y/N), `CompressEnabled`,
`CompressProbe` (always/off/excluded-extensions), `BrowseView` (off/index), and an
optional `ViewPath` when enabled. Tools can name `FfprobePath` using an absolute
executable path or bare PATH command. The legacy `SevenZipPath` key is accepted
and type-checked but unused by the native executable, which always uses its
packaged helper. Recovery scripts retain their own extractor selection. Unknown/retired keys,
overlapping roots and readable credential values are refused before any set runs.
Optional `Secrets` holds `ToEmail`, `FromEmail`, `SmtpServer`, `SmtpPort` (default
587), and `Credential` such as `credential:backup-mail`. Omit `Credential` for a
relay that permits unauthenticated submission. Port 465 uses TLS directly; other
ports require STARTTLS. Plaintext SMTP is not offered. `--no-mail` disables
submission without bypassing configuration validation. A bounded summary sends
set names, outcomes and counts; detailed paths and errors remain local. Relay
acceptance is reported separately from backup success and does not prove delivery.

Provision the named credential for the actual account running the task. Windows
uses a Generic Credential named `FileBackup:backup-mail`, with username/password;
Linux Secret Service uses attributes `service=FileBackup`, `account=backup-mail`;
macOS Keychain uses service `FileBackup`, account `backup-mail`. The latter two
store UTF-8 JSON with `username` and `password` in the protected item's secret
value. Windows also accepts that JSON blob. The engine does not create, unlock
or prompt for credentials. An inaccessible/locked item makes notification
unavailable while preserving the backup result. Live relay and credential-store
qualification is still pending; do not put these secret values in configuration,
shell arguments or logs. Configuration and credential-store access belong to the
execution account's trust boundary; the executable does not elevate privileges.

## Why a file was or was not compressed

For each new file above 256 KiB that is not already stored, the engine measures
how well it compresses while it copies the file. A file of 2.25 MiB or more is
sampled at seven interior 256 KiB windows (one eighth, two eighths, up to seven
eighths of the way through); a smaller one is sampled whole. It compresses the
file when the combined saving is at least 10%. Nothing is read twice and no
helper process runs for the measurement. A file whose content is already stored
is not measured.

Each measured decision is one line in a new file per run,
`<StorePath>/compress-decisions/YYYY_MM_DD_HH_MM_SS.log` (the run's start time,
UTC; a `_1`, `_2` suffix if two runs start in the same second). The file appears
when the first decision is made. Fields are tab separated:

1. the time (RFC 3339, UTC);
2. the path relative to the source;
3. the length in bytes;
4. `compress` or `raw`;
5. the reason: `mean` (the combination in use), `whole-file`, or `fallback`
   (the measurement failed and the file type decided);
6. the combined ratio to four decimals (compressed over raw; 0.90 or less
   compresses), or `-`;
7. the ratio of each window, comma separated, or `-`.

The newest 30 logs are kept; older ones are deleted when a new run creates its
file, and nothing else in the folder is touched. A log that cannot be created or
written produces one warning in the run report and never fails the backup.

A line is written when the decision is made, before the file is compressed, so a
run stopped mid-compression still shows what it was doing. A file whose capture
is retried after a failure can therefore appear more than once in the log; the
`probe` counters (below) are updated only when the object is published, so each
file counts once.

The backup report gains a `probe` object (all zero when compression is off):
`measured`, `compressed`, `raw`, `whole_file` (measured as one sample),
`unmeasured` (new files that reached the decision with compression on but were
not measured: 256 KiB or smaller, or excluded by `CompressProbe`), `fallback`,
and `bytes_compressed_in` / `bytes_compressed_out` (source length and archive
size of each object stored compressed).

`bytes_compressed_out` counts 0 for an object whose archive size could not be read
after verification; it is a statistic only and the backup is unaffected.

## Recover without Rust

Carry the **whole store**: CurrentBackup and all retained BackupHistory content.
A selected dated folder's manifest may depend on objects stored elsewhere in that
pool. A single state folder is not a complete export.

From the chosen CurrentBackup or dated BackupHistory folder:

```powershell
pwsh -NoProfile -File ./RECONSTRUCT.ps1 -TargetRoot D:\Recovered -ExitCode
```

```sh
bash ./reconstruct.sh --target-root /absolute/recovered
```

PowerShell requires version 7+, its carried Common module and System.IO.Hashing
DLL. Bash requires version 4+, GNU awk, xxHash tools >=0.8, a UTF-8 locale and
coreutils; compressed objects additionally require 7-Zip and `timeout` (or
`gtimeout`). Install/provision these before disaster recovery, including offline
copies of their installers if needed. macOS's system bash is too old; provision a
current bash and GNU tools separately. Missing interpreters cannot diagnose
themselves; launch from a terminal to see the operating-system error.

Use an exclusively controlled target outside the store. Existing redirects and
portable-name collisions are rejected. Files are verified before replacement;
ordinary directories follow, then relative folder links. Link privileges and
attributes depend on the target host. External folder aliases restore as ordinary
duplicate trees; capacity is estimated for their expanded logical bytes.

`-Previous` / `--previous` explicitly selects `.prev` definitions. Default recovery
uses current definitions even if previous copies remain. Missing supplemental
metadata reports incomplete recovery while independent valid files can recover.
Never combine a leftover previous member with newer current records. Current
definitions remain usable through interrupted previous-copy creation/cleanup.

`KIT.sha256` checks that carried scripts/helpers form a complete kit. It is not a
state-completion marker or an authenticity signature. A mixed kit refuses before
target writes. Kit refresh preserves a prior route in `RECOVERY.previous`. Run its script with
explicit `-RecordRoot` and `-StoreRootOverride`, or `--record-root` and
`--store-root`, pointing to the selected state and complete store.

Removing history at a selected cutoff may invalidate older saved states that
borrow its bytes. Native prune protects latest and retained later states and does
not delete unselected older folders. Manually deleting folders bypasses those
protections. Complete a pending explicit prune batch before another backup.

## Build without filling the system drive

Rust 1.96 is the exercised toolchain. `scripts/Invoke-Native.ps1` uses an explicit
build root, defaulting to `D:\FileBackupBuild` when available on Windows. It keeps
Cargo downloads, output and scratch there without moving existing user caches.
It also provisions the helper beside each build profile. Windows provisioning
uses a build-time `7z`/`7zz` to unpack the pinned official standalone executable;
the resulting deployable package needs no installed extractor.

For other hosts, set `CARGO_HOME`, `CARGO_TARGET_DIR` and `TMPDIR` to suitable
locations. Provision the carried DLL at build time using
`python3 scripts/prepare_native_hash.py --cache /large-disk/filebackup-deps`, then
set `FILEBACKUP_HASH_DLL` to the printed path. The script also accepts a pinned
offline NuGet package through `--package`. Runtime backup/recovery never downloads
dependencies.

```sh
python3 scripts/prepare_native_sevenzip.py --cache /large-disk/sevenzip --output "$CARGO_TARGET_DIR/debug/tools/7zip"
python3 scripts/prepare_native_sevenzip.py --cache /large-disk/sevenzip --output "$CARGO_TARGET_DIR/release/tools/7zip"
cargo test --locked --manifest-path rust/Cargo.toml --features test-hooks
cargo clippy --locked --manifest-path rust/Cargo.toml --all-targets --features test-hooks -- -D warnings
cargo build --locked --release --manifest-path rust/Cargo.toml
```

`test-hooks` enables process-termination fixtures and must not be enabled in a
release artifact. Use `scripts/package_native.py --sevenzip-cache /large-disk/sevenzip`
with `--binary` and a fresh `--output` directory to collect the helper, exact
dependency notices, corresponding 7-Zip source and checksums. Both provisioning
and packaging accept `--offline` with a prepopulated cache; supported archive
names and SHA-256 pins are in `scripts/prepare_native_sevenzip.py`. The repository has not
designated a project redistribution license; this does not prevent authorized
local development, but third-party licenses do not grant rights to FileBackup.
