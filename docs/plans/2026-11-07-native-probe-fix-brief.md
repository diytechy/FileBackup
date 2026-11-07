# Brief, 2026-11-07: the native engine's compressibility probe, and what else never got built

For: a new agent session in this repo. Written from a HomeHub session that watched the
first real library backup and stopped it. Commit this file with your first commit.

## Why this session exists

The first real library run of the native engine (`filebackup:ef3ab06`, branch
`Rust-Rewrite`) started on the hub at 03:01 on 2026-11-07. By 10:39 it had read 92.3 GiB
of a 1.1 TiB library and stored 87 GB. It was spending hours on single video files. The
Owner had it stopped and asked for two things, in this order:

1. **An audit of which defects were found but never fixed**, in either engine. The Owner
   believed the defect reviews were inside the native rewrite's scope. At least one
   was not, so check all of them.
2. **The probe fix, built in the Rust engine** (`rust/`).

The Owner's words: *"start a separate session to build that fix in filebackup in the rust
implementation. That can start with an audit of what other defects might have never
been addressed, I thought it was included in the scope but obviously not."*

## What was measured on the hub (facts, not inferences)

- Compression is CPU-bound. `7zz -mx=5 -mmt=2` (`rust/src/tools.rs:323`) wrote 2.4 MiB/s
  on two of the hub's four cores, with the disks about 5% busy. Media saves about 6%:
  92.3 GiB read became 87 GB stored.
- Each written object takes three passes: a staged copy into `Incoming/.tmp*`, the
  compression, then a `7zz e -so` read-back. The progress counter therefore sits still for
  hours on one large file.
- The probe (`should_compress`, `rust/src/engine.rs:385`) is a faithful port of the
  PowerShell probe as it shipped: 3 windows of 256 KiB at 0, the middle and len-256 KiB,
  and compress when the aggregate is 0.90 or less. `CompressProbe` is unset on the hub,
  so it runs at its default, `always`.
- Per-window `7zz -mx=5` ratios on real files, run by the bundled 7zz:

  | file | head / middle / tail | aggregate | realised |
  |---|---|---|---|
  | ESB AVCHD `.iso`, 8.43 GB | 0.003 / 0.963 / 0.017 | 0.33 | 0.934 |
  | ROTJ `.mkv`, 20.6 GB | 0.59 / 0.985 / 0.55 | 0.71 | (not run) |
  | ESB `.mkv`, 21.2 GB | 0.56 / 0.001 / 0.001 | 0.19 | (stopped) |

  The ESB MKV is a **sparse file**: 9.2 GB allocated, data ends at about 8.8 GiB, and the
  rest reads as zeros. Compressing it is genuinely right. The Owner is checking whether
  the source was always incomplete. It does raise an audit question: staging writes all
  21 GB of zeros to `Incoming` before the probe runs.

## What already exists. Read these before designing anything.

- `docs/defect-review-2026-09-02-probe-sample-representativeness.md`: the defect, found on
  the PowerShell engine's first production pass (4.56 h of the first 8 h spent compressing
  to save 1.88 GiB). Its Option A scales the window count with file size: 9 at 1 GiB,
  13 at 20 GiB.
- `docs/plans/wp18-probe-window-geometry-plan.md`: WP18. Status DRAFT, "NOT approved and
  NOT started" (`docs/status.md:6158`). §7 holds open questions for the Owner.
- `docs/probe-sampling-corpus-2026-09-07.md`, commits `e7afc1b`, `9b5eaff`, `e3042bc`, and
  `docs/experiments/probe-window-*.py`. Measured on 166 real files: the head window
  correlates +0.06 with the outcome (noise); the shipped 0/50/100 geometry (+0.65) is
  worse than one middle window (+0.80); 25/50/75 reaches +0.89; accuracy plateaus at
  about 9 windows. The recommended rule: **raw when median(windows) > 0.95 OR
  middle >= 0.98**, which avoids 60% of the 7-Zip input. That work came after WP18 was
  drafted and changes its premise.
- `docs/requirements-audit-2026-11-05.md` and
  `docs/plans/native-design-2026-11-05/implementation-workorder.md`: the native rewrite's
  scope. Find out why the defect reviews did not reach it.

## Known gaps between the ports, found in passing

- Rust has no `compress-decision: <rel> <Reason> ratio=… windows=…` DEBUG line and no
  `Probe stored raw / compressed / reads` counters (PowerShell
  `Modules/FileBackup.Engine.psm1:4342` and `:5572`). Nobody can see from the hub why a
  file was compressed.
- Rust measures windows with a full `7zz -mx=5` run per probe. The LLR specifies Brotli at
  its fastest setting (the PowerShell engine and the `astra-llr` LLR text). The bias comes
  from where the windows sit, not from the codec, but it is still a deviation from the
  LLR.
- The 2026-11-06 progress lines were also restored after the port had dropped them
  (`e3f7fe7`), so expect more of this kind.

## Order of work

1. **Audit first, read-only.** For every `docs/defect-review-*.md` (there are 7), every
   plan marked DRAFT / NOT approved / NOT started, and the Owner's queue (split staging
   recovery, prune fix 2, step-10 `.fbwrite.tmp` hardening, the Reconstruct torn-7z
   fallback), record:
   - fixed in PowerShell?
   - carried into Rust?
   - never built?
   - whether it costs time, space or correctness on the hub's real library.

   Also cover the port gaps above, and any behaviour the PowerShell engine has that Rust
   lacks. Write it as a doc in this repo, self-contained for the Owner: no bare codes, and
   each item gives its context and evidence.
2. **Bring the probe design to the Owner before coding.** The choices are WP18's
   size-scaled count, 25/50/75 placement, about 7-9 interior windows, and the
   median/middle rule. Recommend one from the 09-07 measurements. Check the ISO case: its
   padding still reads as compressible under the median/middle rule. WP18 §7's questions
   need answers. Get the design cross-checked by a reviewer before you show it.
3. **Build on a feature branch cut from `Rust-Rewrite`**, merge back `--no-ff`, and build
   releases only from `Rust-Rewrite`. Put back the decision log line and counters. Test
   against the real-file shapes above. Synthetic random/text files miss the
   header/tail bias.

## Constraints

- **Do not touch the hub.** The backup is stopped and `FILEBACKUP_TIMER_ENABLED=false` in
  `/opt/homehub/stack/.env`, so the 03:00 timer skips. The store at
  `/mnt/backup-drive/library-store` holds 87 GB in `CurrentBackup` from the stopped run,
  plus a 21 GB leftover `Incoming/.tmpVJASFU` and `Incoming/archive-AJ18zx/`. Deploying a
  new image, re-enabling the timer and deciding what happens to that partial store are
  the Owner's calls. Answer the question they need for that: does a restarted run reuse
  the 87 GB already stored, and does it reclaim `Incoming` cleanly?
- Agents commit locally; the Owner pushes. The HomeHub bake refuses an image stamp that
  differs from this repo's HEAD, so a new commit here means a rebuilt image and a new
  `FILEBACKUP_IMAGE_TAG` on the hub.
- Builds and caches go on `D:/FileBackupBuild` (see AGENTS.md).
- The Owner's working pattern: written briefs to Sonnet builders, an independent Sonnet
  review at medium effort for every item, and designs also cross-checked by Codex
  (`codex exec`). Fix rounds go back to the same builder and reviewer.
