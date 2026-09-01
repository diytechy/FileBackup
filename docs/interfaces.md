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

**Config schema v2** (`SR-042`/`SR-063`, published as
[`container/FileBackup.schema.json`](../container/FileBackup.schema.json)):
a required integer `ConfigVersion` (currently **2**; version 1 is refused as
too old); a **closed** schema — any unrecognized key aborts the run, naming
the key; a JSON boolean `CompressEnabled` (`PreserveFolderTree` was removed at
WP9 — storage is always content-addressed, and a config still carrying the key
is refused with a named removal diagnostic); optional `BrowseView`
(`off`|`index`, default `off` — note a containerized run cannot satisfy the
view's same-volume rule, so `index` is native-host functionality until IF-001
rules otherwise) and `ViewPath`; optional `SourceStatePath` (default
`SourcePath`) and `AllowEmptySource` (default `false`); no
`Secrets.Credential` (JSON can't carry a `PSCredential` — containerized runs are
always `-NoMail`). CLIXML remains the unversioned legacy native-Windows form;
JSON is the only form this contract covers.

**Action selection.** A leading positional word — `backup`, `prune`,
`snapshots`, or `verify` — or `FILEBACKUP_ACTION` selects the action; any
argument starting with `-` passes through to `FileBackup.ps1` unchanged. `prune`
also reads `FILEBACKUP_SNAPSHOT` / `-Snapshot` (required) and
`FILEBACKUP_DRY_RUN` / `-WhatIf`; `verify` reads `FILEBACKUP_REPAIR=1` for its
opt-in repair mode. `view` (SR-062) is deliberately **not** one of them: the
browse view must be written outside both roots and on the backup volume, which
a container's separate `/backup` bind mount cannot satisfy, so it stays
native-host functionality until a later IF-001 revision rules on a container
view mount.

**Environment overrides.** Beside the tool paths (`FILEBACKUP_7ZIP_PATH`,
`FILEBACKUP_FFPROBE_PATH`), `FILEBACKUP_7Z_LEVEL` (added 2026-09-01) selects
7-Zip's `-mx` effort level as a single digit `0`–`9`, default `9`; it is
deliberately **not** a configuration key, so `ConfigVersion` stays `2`. It
changes only how hard 7-Zip tries — never *whether* content is compressed, and
never the restore contract: the restorers read no *policy* from the variable and
restore correctness is level-independent, every level's archive being read back
by the same kit. (`Reconstruct.ps1`'s host self-test compresses a throwaway
probe file of its own, so that probe archive inherits the resolved level —
harmless, because every `0`–`9` archive round-trips.) An invalid value fails a
compression-enabled backup on the existing exit `2` (a terminating error without
`-ExitCode`) before anything is written.

**Retention: policy vs. mechanism.** HomeHub decides *what* to keep; FileBackup
decides *how* a snapshot is safely removed. **HomeHub must never delete a
`Snapshot_*` folder directly** — dedup means one snapshot's bytes can be the
only physical copy another snapshot recovers by content hash. The container
exposes `snapshots` (read-only inventory: name, date, row count, physical
bytes, bytes-reclaimable-if-pruned — a figure only FileBackup can compute) and
`prune` (`Remove-BackupSnapshot`; `Prune-` is not an approved PowerShell verb),
which re-homes still-referenced bytes into the surviving pool and proves every
surviving manifest still resolves before it deletes anything. Pruning needs the
`backup` mount writable in addition to `change`.

**JSON framing.** The `snapshots` inventory and `verify` findings documents are
printed to stdout, which also carries timestamped log lines. A consumer must
extract the document by LINE: it is either the single line `[]`, or the block
from the line that is exactly `[` through the line that is exactly `]`. (The
repo's own harness does exactly this — `scripts/Invoke-Container.ps1`.) `verify` (optionally with
`FILEBACKUP_REPAIR=1`) audits storage form across the live backup and every
snapshot without mutating anything unless repair is requested.

**Exit-code table** — the same table for backup, restore (`RECONSTRUCT.cmd` /
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
