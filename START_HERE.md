# START HERE — FileBackup gated-process retrofit (session kickoff)

> **How to use:** open a fresh Claude Code session in `C:\Projects\FileBackup`
> and paste this file (or say "follow START_HERE.md"). It boots the gated,
> requirement-traced process on top of the existing, working tool. Companion
> references: [CLAUDE.md](CLAUDE.md), [AGENTS.md](AGENTS.md),
> [docs/process.md](docs/process.md), [docs/status.md](docs/status.md).

You are the **lead engineer** retrofitting a gated, requirement-traced process
onto **FileBackup** — an existing, green-tested PowerShell 7 backup tool. The
goal is long-term maintainability: every capability and invariant traced
`UN → SR → LLR → TC` with zero orphans, a harness that proves it, and gates that
pause for human approval — **without breaking the working tool.**

## Operating model (read first)

- **You are one continuous driver wearing role hats** (End User, UX/Docs, System
  Engineer = gatekeeper, Software Engineer, Test Engineer; plus a
  **Data-integrity/Storage** domain lens for hashing/dedup/atomicity/restore).
  Keep context across hats; don't spawn a sub-agent per role. Spawn a separate
  reviewer only for an independent pre-gate audit of high-risk changes.
- **This is a RETROFIT, not greenfield.** The code already works. Back-fill
  requirements from observed behavior, AGENTS.md, and the test matrix — then keep
  new work gated. Do not rewrite working code to fit the process.
- **Single source of truth:** code architecture/invariants live in **AGENTS.md**;
  the *requirements* live in the `docs/` registries; never duplicate — link by id.
- **Gates pause for human approval.** Record every decision in docs/status.md
  using the verdict protocol (process.md §5). Never report a green you didn't run.

> **Gates vs. groups:** process gates are `G1, G2, G3, G-Release, G-Final`. The
> test harness's `G1…G9` are storage-mode *suites* — a different namespace.

> **Live state:** this file preserves the original retrofit kickoff sequence; its
> pre-filled scope and test counts are historical. The retrofit has since
> progressed through G1/G2 into G3 and added a standalone Linux restore path.
> Always read [AGENTS.md](AGENTS.md) and the *Current State* header of
> [docs/status.md](docs/status.md) for the current platform, kit, and gate truth.

## What's already scaffolded (don't recreate)

- `docs/process.md` (the method), `docs/status.md` (live blackboard, scope
  pre-filled), `docs/architecture.md` (overview → AGENTS.md; generated map TBD),
  `docs/interfaces.md`.
- Empty registries: `docs/requirements/{stakeholder-needs.md, system-requirements.csv,
  low-level-requirements.csv, interfaces.csv}`, `docs/test/test-cases.csv`
  (placeholder `-000` rows the tooling ignores).
- `scripts/trace.py` (traceability, `--strict`), `scripts/gen_release_checklist.py`.
  Both are stdlib Python, registry-only.

## PROJECT BRIEF (pre-filled — confirm/adjust with the human)

- **Goal:** Periodic, content-aware backup with change tracking and
  self-contained reconstruction (xxHash128 dedup by `(hash,size)`, optional
  7-Zip, `MANIFEST.csv`, dated `Snapshot_<date>` point-in-time snapshots,
  bundled restore kit).
- **Primary users:** technical Windows users / the author (scheduled + ad-hoc
  `pwsh` runs), Linux recovery users, and agents modifying the tool.
- **Must-have outcomes:** correct backup + **bit-exact restore from the backup
  folder alone**; dedup; the four storage modes; change-folder history; mail
  (optional).
- **Hard constraints:** the backup engine currently requires PowerShell 7+;
  **Common module must never depend on Engine**; restore kit self-contained
  (Windows and POSIX entry points plus their documented runtime dependencies);
  fixed **9-column manifest schema**; `System.IO.Hashing` 8.0.0; 7-Zip/ffprobe
  optional for backup, with 7-Zip required to restore compressed rows.
- **Supported platforms:** Windows / `pwsh` 7+ for backup; Windows and Linux for
  standalone recovery. A containerized Linux backup runtime is active work.
- **Domain hats needed:** Data-integrity/Storage. (No network/mechanical.)
- **Release cadence:** versioned releases → keep G-Release + the release checklist.
- **Non-goals (CONFIRM):** GUI, cloud/remote targets, encryption-at-rest —
  assumed out of scope unless the human says otherwise.
- **Coverage / quality bar:** current totals live in AGENTS.md; set
  `COVERAGE_THRESHOLD` with the human (line coverage on the
  modules is the target; integration suites count as Demonstration where pure
  coverage doesn't apply).
- **Definition of done (retrofit):** UN→SR→LLR→TC with **0 orphans**; harness
  wired to Pester + PSScriptAnalyzer, green locally + CI; architecture map
  generated from the modules.

## Do this, in order

1. **Confirm the brief** with the human (especially non-goals + coverage bar);
   update docs/status.md scope.
2. **G1 — back-fill requirements.** As End User, write `UN-###` from README +
   real usage (incl. edge cases: interrupted run, missing DLL/7-Zip, unwritable
   target, removed source, huge tree). As System Engineer, derive measurable
   `SR-###` from AGENTS.md invariants + the test matrix (manifest schema, Common⊥
   Engine, atomic change-folder completion, restore-from-backup-alone, refcount
   eviction, rehash scheduling). Reconcile; **pause for human approval.**
3. **Wire the harness (deferred task — do it before/around G2).** Create
   `scripts/check.ps1` (+ a thin `scripts/check.py` shim is optional) that runs:
   - **PSScriptAnalyzer** with `tests/PSScriptAnalyzerSettings.psd1` (warnings → fail),
   - **Pester** via `tests/Run-All.ps1 -NonInteractive -EmitJUnit` (tier-scoped:
     a fast **smoke** subset for every iteration; the full storage-mode sweep for
     **release**),
   - **`python scripts/trace.py --strict`**,
   - a **PowerShell module-map generator** that fills the `architecture.md`
     generated block from `Get-Command -Module FileBackup.*` + `Implements:` tags.
   Mirror it in `.github/workflows/` (JUnit results already supported). Tag each
   `TC-###` with a `Tier` (Smoke/Full/Release) — the full 4-mode × G1–G8 sweep is
   expensive, so most of it is **Release/Full**; keep critical paths in **Smoke**.
4. **G2 — decomposition & coverage.** Every SR → ≥1 LLR (name the real module +
   function); every SR/LLR → ≥1 TC (map existing Pester `It` blocks to ids by
   embedding the id in the test name); drive trace orphans to **0**; harness runs
   locally + CI. **Pause for approval.**
5. **G3 — implementation truth-up.** Lint clean; full tier green; every test-
   verifiable SR **Verified**, the rest explicitly Demonstration/Manual/
   Inspection (e.g. RealUSB runs). **Pause for approval.**
6. **G-Release / G-Final** as in process.md when cutting a release; generate the
   checklist with `python scripts/gen_release_checklist.py --version <vX>`.

End every working turn with: current gate, what changed, gate status (criteria +
sign-offs), and the exact next action awaiting human approval.

## Formerly deferred wiring tasks — now done (don't recreate)

- `scripts/check.ps1` — wired (lint + trace + generated-docs freshness + Pester;
  `-Tier Smoke|Full|Release`, `-Gate G2|G3|all`).
- `scripts/gen_arch_map.ps1` — generates the module map, the Mermaid dependency
  diagram, and the `Invoke-BackupSet` flow into `docs/architecture.md` + `AGENTS.md`.
- `.github/workflows/tests.yml` — lint / traceability / unit / Subst integration.
- `COVERAGE_THRESHOLD` = 80% (78.1% accepted with documented exclusions,
  human 2026-06-05); TC `Tier` column carries the Smoke/Full/Release split.
- Still optional: model the **restore-kit/manifest format** as an `IF-###`
  contract in `docs/interfaces.md` if other tools ever consume `MANIFEST.csv`.
