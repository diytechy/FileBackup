# CLAUDE.md — Agent guide for FileBackup

Two standing references govern work here. Read both:

1. **[AGENTS.md](AGENTS.md)** — the authoritative source for *what FileBackup is*:
   architecture, the Common/Engine split, invariants you must not break, the test
   matrix, conventions, and history. **Always defer to it for code facts; never
   duplicate them elsewhere.**
2. **[docs/process.md](docs/process.md)** — *how we evolve it*: the gated,
   requirement-traced process (the load-bearing core, §1–§7; opt-in layers are
   summarized there and expanded in
   [docs/process-options.md](docs/process-options.md) — this standalone repo
   runs the minimum profile and skips them). Live state is in
   [docs/status.md](docs/status.md).

This file is the thin bridge between them.

---

## Stack & how to run

- **PowerShell 7+ (`pwsh`) on Windows only.** Windows PowerShell 5.1 is not
  supported. Entry point `FileBackup.ps1`; standalone restore `Reconstruct.ps1`.
- **Tests are Pester**, driven by [tests/Run-All.ps1](tests/Run-All.ps1) (suite
  groups G1–G9 × Plain/Compress — storage is always content-addressed since
  WP9 deleted Mirror; `-EmitJUnit` for CI, `-NonInteractive` for unattended).
  Lint config: `tests/PSScriptAnalyzerSettings.psd1`.
- **Traceability tooling is Python** (stdlib, no pip): `python scripts/trace.py
  --strict` joins the registries and reports orphans (`--require-verified` adds
  the G3 status criterion); `python scripts/gen_release_checklist.py` builds the
  release checklist; `python scripts/gen_cases.py --spec "<Permutations cell>"`
  expands a requirement's input dimensions into test combinations. These read
  `docs/` CSVs only — they don't touch the PowerShell code.
- **The harness is `pwsh scripts/check.ps1`** (`-Tier Smoke|Full|Release`;
  `-Gate G1|G2|G3|all`, defaulting to the active gate in `docs/gate`) — lint,
  traceability, doc navigability, generated-docs freshness, Pester, perf
  budgets (inert until real `PB-###` rows exist). CI runs the same steps.
  Optional local floor: `git config core.hooksPath .githooks` (map freshness +
  id integrity on every commit).

> **Gates vs. test groups — don't conflate.** Process **gates** are
> `G1, G2, G3, G-Release, G-Final` (docs/process.md §4). The test harness's
> **groups** `G1…G9` are storage-mode suites — a different namespace.

## The process, in brief (see docs/process.md for the full method)

- This is a **retrofit**: back-fill `SN → SR → LLR → TC` from existing behavior
  (README + AGENTS.md + the test matrix), drive traceability orphans to **0**,
  then keep new work gated. Registries under `docs/requirements/` + `docs/test/`
  are the machine source of truth. (The top layer was `UN-###`/`user-needs.md`
  before the 2026-07 kit re-sync; ids kept their numbers.)
- **One driver wears the role hats** in sequence. Spawn subagents deliberately
  (process.md §6): an independent reviewer for pre-gate audits of high-risk
  changes (hashing, dedup, atomic writes, restore correctness — the
  data-integrity surface); a cheaper-tier agent for mechanical, well-specced
  subtasks; a fresh-context peer for bulk content.
- **Gates pause for human approval.** Record decisions in docs/status.md.
- **Decision dial (process.md §6, set for this repo): HIGH.** This product's
  whole value is data safety — surface decisions to the human often, including
  medium ones; decide autonomously only for trivially-reversible, non-engine
  work (docs wording, test scaffolding), and record even those in status.md.
- **Commit early and often** — a small, green commit per logical step; readable
  change only exists once committed. End sessions with a clean tree
  (process.md §3 "Commit cadence").
- **Never report a green you didn't run.** Paste the real Pester / trace output.
- **Repo text is the project's memory; yours is scratch.** Durable facts — a
  decision, constraint, or gotcha — belong in `docs/` (status.md, registries,
  AGENTS.md), not in agent-private memory. Promote them before closing a
  session (process.md §7 "durable agent memory layer").

## Code conventions (reinforcing AGENTS.md)

- **Honor the invariants in AGENTS.md §3** — manifest 9-column schema, Common
  never depends on Engine, restore kit stays self-contained.
- **Pure cores vs. I/O shells:** keep diff/decision logic pure and unit-tested;
  isolate filesystem/7-Zip/network side effects.
- **Back-link code to requirements:** annotate functions `Implements: SR-007,
  LLR-014` and name Pester tests so the verified id is visible (e.g.
  `It 'dedups identical content (SR-003)'`). Registry columns are authoritative.
- **Automation-safe:** anything interactive needs a `-NonInteractive` path that
  fails loudly with a non-zero exit (CI/scheduled runs must never block).
- **Entry points orchestrate, they don't compute.** A top-level routine reads as
  a short, ordered list of well-named step calls; push logic into the steps.
  `scripts/gen_arch_map.ps1 -Flow <fn>` renders the call sequence into
  docs/architecture.md — a short or vague flow means the routine inlines too much.
- **Define the interface (contract) at the code.** Each public function carries
  comment-based help (`<# .SYNOPSIS / .PARAMETER / .OUTPUTS #>`) as the **first**
  thing in its body — a plain comment before it breaks `Get-Help` and the
  generated map — followed by the `# Implements: SR-###, LLR-###` back-link line.
  Reference SR ids for input ranges/sets instead of restating them
  (process.md §3 "Interface contracts live at the code").
- **Diagrams are Mermaid fenced blocks** in the Markdown docs; the dependency
  diagram, module map, and `Invoke-BackupSet` flow are **generated** — never edit
  between `GENERATED` markers; `check.ps1` fails when they're stale.
- Match the surrounding PowerShell style; small functions; comments explain *why*.

## First task for a new session

Open **[START_HERE.md](START_HERE.md)** — it has the filled project brief — then
read the *Current State* header of [docs/status.md](docs/status.md) for the
active gate and the exact next action awaiting approval.
