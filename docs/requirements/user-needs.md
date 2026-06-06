# User Needs (UN-###)

Owned by the **End User** hat. Plain-language needs + edge-case expectations.
Engineering translations live in `system-requirements.csv` (referenced by
`UN-Refs`); do not restate them here. Priority: **M**=Must · **S**=Should ·
**C**=Could.

> Back-filled (retrofit) from README.md, AGENTS.md, the config schema, and the
> existing test matrix. Each row is what a *user* wants; the measurable
> engineering contract is the linked SR.

## Core needs

| UN-ID | Need (plain language) | Why it matters | Priority | Acceptance intent (how we'd know it's met) |
|---|---|---|---|---|
| UN-001 | Back up an entire source tree, periodically, capturing every file. | The whole point — nothing in the source may be silently skipped. | M | Run against a known tree; every source file appears in the backup's `MANIFEST.csv`; re-running picks up new/changed files. |
| UN-002 | Don't waste space storing identical content twice. | Large media trees have many duplicate files; storing each once saves real disk. | M | Two files with identical bytes produce one physical data file; the second is recorded as a duplicate pointing at the same data. |
| UN-003 | Optionally compress stored data to save more space. | Compressible documents/text shrink a lot; already-compressed media shouldn't be re-packed. | S | With compression on, a `.docx`/`.txt` is stored as `.7z`; a `.jpg`/`.mp4` is stored as-is. |
| UN-004 | Keep point-in-time snapshots of earlier states, each fully restorable. | Lets me recover an older copy after an accidental edit/delete — and trust that restoring "as of date X" reproduces exactly what existed then. | M | After several runs, each earlier backup has a snapshot named by that backup's date; restoring one reproduces that exact state (changed files at their old content), and the latest run needs no snapshot because the live backup already is the latest state. |
| UN-005 | Restore the original tree **bit-for-bit from the backup folder alone** — no repo, no installs. | A backup I can't restore on a clean machine is worthless. | M | Copy a backup folder to a machine without this repo, run its restore kit, and byte-compare the result to the original — identical. |
| UN-006 | Restore a *historical* snapshot, not just the latest. | I may want the state as of a specific earlier run, picked by date. | S | Running the restore kit inside a specific dated snapshot folder rebuilds exactly that earlier state, byte-for-byte; running it from the backup root rebuilds the latest state. |
| UN-007 | Control how often unchanged files get re-hashed, to trade speed vs. integrity. | Re-hashing a huge tree every run is slow; I want daily/weekly/never options. | S | Setting `HashRecalcFreq` to `D`/`W`/`N` etc. changes whether an unchanged file is re-hashed on a given run, deterministically. |
| UN-008 | Choose the on-disk layout: mirror the source tree, or content-addressed names. | Mirror is browsable; content-addressed dedups visibly. I want to switch without losing data. | S | Toggling `PreserveFolderTree` changes the stored layout; switching an existing backup migrates its data without loss. |
| UN-009 | Back up several independent source/target sets from one config and one run. | I have multiple data roots; one scheduled job should cover them. | S | A config with multiple `BackupSets` processes each independently in one invocation. |
| UN-010 | Optionally email me whether the backup succeeded or failed. | For unattended/scheduled runs I want to know without checking logs. | C | With SMTP configured, a success/failure email arrives; with it omitted or `-NoMail`, none is sent. |
| UN-011 | Run unattended/scheduled without ever blocking, with a clear pass/fail signal. | A scheduled task that hangs on a prompt or hides failures is dangerous. | M | A scheduled `pwsh` run completes without prompting and returns exit 0 on success, non-zero if any set failed. |
| UN-012 | Get set up on the first run with discoverable docs and a config builder. | New users (and future me) shouldn't have to reverse-engineer the config. | S | README + `CredSetEx.ps1` let a new user build a config and run a first backup; required deps install on first use. |

## Edge-case expectations

How the system should behave when things go wrong (the highest-value part — be
specific; the System Engineer turns each into measurable SRs).

| UN-ID | Scenario | Expected behavior |
|---|---|---|
| UN-013 | Interruption / power loss / killed mid-operation | The next run detects the leftover `Temp` staging folder and aborts with a clear message rather than proceeding on a half-written state; a completed change folder is only ever produced atomically (rename after its manifest is written). |
| UN-014 | Invalid input — config file missing | Fail immediately with a clear "config not found" message and a non-zero exit; do nothing destructive. |
| UN-015 | Missing **required** dependency / wrong runtime (PowerShell 5.1, no `System.IO.Hashing`) | Fail loudly with remediation guidance; never run hashing against a bogus/absent library. |
| UN-016 | Missing **optional** dependency (7-Zip when compressing, ffprobe for media metrics) | Degrade gracefully: skip compression/media metrics, log it, keep going — not fatal. |
| UN-017 | Awkward file names (Unicode, `[brackets]`, `(parens)`, spaces) | Backed up and restored correctly; path handling never mis-parses bracketed/Unicode names. |
| UN-018 | A *nested* user file happens to be named like infrastructure (e.g. `MANIFEST.csv`) | Treated as real user data and preserved — only true root-level infrastructure files are filtered (regression B6). |
| UN-019 | Restore target too small / unwritable | The restore surfaces an insufficient-capacity/space problem (accounting for compressed data) rather than silently producing a partial tree. |
| UN-020 | Email/SMTP failure during notification | Logged as a warning; the backup itself still reports its real success/failure — mail is never load-bearing. |
| UN-021 | A run with nothing changed (idempotent re-run) | Produces identical manifest rows and no spurious "changes"; output is deterministic across identical re-runs. |
