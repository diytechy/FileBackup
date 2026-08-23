# Cross-Project Interfaces (IF-###)

Owned by the **System Engineer** hat. The machine source of truth is
[`requirements/interfaces.csv`](requirements/interfaces.csv) — **this page never
restates its fields; it points at them and renders the current contract in
prose for a human reader.** If this page and the CSV ever disagree, the CSV
wins; fix this page.

FileBackup has exactly one interface today: **IF-001**, the OCI image contract
between FileBackup (`Provides`) and **HomeHub** (`Counterpart`). See the CSV row
for the authoritative `SR-Refs` / `Version` / `Stability` / `Status` columns
(`Direction`, `Contract`, etc. are self-describing from the CSV header) —
process.md §8 covers the registry's rules; not duplicated here.

## IF-001 in plain language

**What it is:** FileBackup ships as a one-shot OCI container. HomeHub supplies a
JSON config plus bind mounts; the container runs one backup/restore/prune/verify
action and exits. HomeHub owns scheduling, mount-identity preflight, retention
*policy*, and NagLight alerting; FileBackup owns the storage engine, retention
*mechanism*, and its own exit-code contract.

**Mounts.** Read-only `source` + `config`; writable `source-state` (the source
hash-cache `MANIFEST.csv`, kept outside the read-only source), `backup`,
`change`, and `log`. `SourceStatePath` in the config points at the writable
source-state mount.

**One BackupSet per container invocation** (ruled 2026-08-21). HomeHub runs one
service/invocation per directory rather than one multi-set config; a JSON config
with more than one `BackupSets` entry is accepted for native-Windows use but is
outside this contract when run in the container.

**Config schema v1** (`SR-042`, published as
[`container/FileBackup.schema.json`](../container/FileBackup.schema.json)):
a required integer `ConfigVersion` (currently **1**); a **closed** schema — any
unrecognized key aborts the run, naming the key; JSON booleans for
`CompressEnabled` / `PreserveFolderTree`; optional `SourceStatePath` (default
`SourcePath`) and `AllowEmptySource` (default `false`); no
`Secrets.Credential` (JSON can't carry a `PSCredential` — containerized runs are
always `-NoMail`). CLIXML remains the unversioned legacy native-Windows form;
JSON is the only form this contract covers.

**Action selection.** A leading positional word — `backup`, `prune`,
`snapshots`, or `verify` — or `FILEBACKUP_ACTION` selects the action; any
argument starting with `-` passes through to `FileBackup.ps1` unchanged. `prune`
also reads `FILEBACKUP_SNAPSHOT` / `-Snapshot` (required) and
`FILEBACKUP_DRY_RUN` / `-WhatIf`; `verify` reads `FILEBACKUP_REPAIR=1` for its
opt-in repair mode.

**Retention: policy vs. mechanism.** HomeHub decides *what* to keep; FileBackup
decides *how* a snapshot is safely removed. **HomeHub must never delete a
`Snapshot_*` folder directly** — dedup means one snapshot's bytes can be the
only physical copy another snapshot recovers by content hash. The container
exposes `snapshots` (read-only inventory: name, date, row count, physical
bytes, bytes-reclaimable-if-pruned — a figure only FileBackup can compute) and
`prune` (`Remove-BackupSnapshot`; `Prune-` is not an approved PowerShell verb),
which re-homes still-referenced bytes into the surviving pool and proves every
surviving manifest still resolves before it deletes anything. Pruning needs the
`backup` mount writable in addition to `change`. `verify` (optionally with
`FILEBACKUP_REPAIR=1`) audits storage form across the live backup and every
snapshot without mutating anything unless repair is requested.

**Exit-code table** — the same table for backup, restore (`RECONSTRUCT.bat` /
`reconstruct.sh`), prune, and verify, precedence `2 > 3 > 4 > 1`:

| Code | Meaning | NagLight translation |
|---|---|---|
| 0 | Complete / nothing to report | ok |
| 1 | Partial: content unrecoverable, or a backup/prune batch incomplete, but nothing lost | warn — retry |
| 2 | Usage or precondition error; nothing mutated | error — do not retry |
| 3 | Manifest-witness verification failed; nothing mutated | error — **escalate** (backup-integrity alarm, not a retention alarm) |
| 4 | Host/dependency I/O failure; retriable | warn — retry |

A backup run whose estimated additions don't fit the backup/change volume
refuses before writing anything (status 1 for that set, naming the volume, the
requirement, and the free space). A restore origin's `MANIFEST.csv` is witnessed
by `MANIFEST.csv.meta`, verified by both restorers before writing anything
(`SR-038`/`SR-039`/`SR-040`). There is no bash `prune` — `reconstruct.sh` stays
restore-only, and pruning is never required to restore.

**Stability: `Experimental`.** IF-001 stays `Experimental` — free to change
without a version bump or counterpart notice — until it clears the joint exit
condition below; then it can move to `Stable` (version bump + notice required
for any breaking change thereafter).

**Exit condition to leave `Experimental`** (both halves, jointly): **WP1**'s
witnessed-manifest + shared exit-code contract (`SR-038`..`SR-040`), and
**WP2**'s versioned, validating config loader (`SR-042`/`SR-043`) — i.e. both
the restore-trust half and the config-contract half of this interface must be
`Verified`, not merely `Implemented`. See [status.md](status.md) for current
verification state.

## Where the rest lives

- Field-by-field contract: [`requirements/interfaces.csv`](requirements/interfaces.csv)
  (`IF-001` row).
- Human-readable background, findings, and the review this contract grew out
  of: [`homehub-integration.md`](homehub-integration.md).
- Current verification status of the SRs cited above: [`status.md`](status.md).
