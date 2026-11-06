# Native FileBackup preview

This branch adds the Rust executable alongside the existing PowerShell engine.
Use a **new, empty StorePath** for the native preview. No older executable/store
version is designated supported for native continuation. Existing backups keep
restoring with their own carried kits. Do not point a native writer at production
history as a conversion experiment.

The executable needs no compiler or PowerShell runtime for backup. Install 7-Zip
locally when new compression is enabled or existing compressed content must be
verified. Recovery has its own independent prerequisites below. See the shipped
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
optional `ViewPath` when enabled. Tools can name `SevenZipPath` and `FfprobePath`
using absolute executable paths or bare PATH commands. Unknown/retired keys,
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

For other hosts, set `CARGO_HOME`, `CARGO_TARGET_DIR` and `TMPDIR` to suitable
locations. Provision the carried DLL at build time using
`python3 scripts/prepare_native_hash.py --cache /large-disk/filebackup-deps`, then
set `FILEBACKUP_HASH_DLL` to the printed path. The script also accepts a pinned
offline NuGet package through `--package`. Runtime backup/recovery never downloads
dependencies.

```sh
cargo test --locked --manifest-path rust/Cargo.toml --features test-hooks
cargo clippy --locked --manifest-path rust/Cargo.toml --all-targets --features test-hooks -- -D warnings
cargo build --locked --release --manifest-path rust/Cargo.toml
```

`test-hooks` enables process-termination fixtures and must not be enabled in a
release artifact. Use `scripts/package_native.py` to collect exact dependency
notices and checksums into a fresh output directory. The repository has not
designated a project redistribution license; this does not prevent authorized
local development, but third-party licenses do not grant rights to FileBackup.
