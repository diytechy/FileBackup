# Development Process (template)

Canonical method for a gated, requirement-traced project. Copy this into a new
repo as `docs/process.md`. It is **stack-agnostic** — wire the harness commands
to your project's language/tooling. Other docs reference this file by section
rather than restating it.

---

## 1. Roles (hats), not necessarily separate agents

One driver wears these hats in sequence, keeping context. Spawn a *separate*
agent only for an independent pre-gate review (see §6).

| Hat | Owns (single source of truth) |
|---|---|
| End User | `requirements/user-needs.md` (UN-###) + edge-case expectations |
| UX / Docs | documentation quality, quick-reference, usability findings |
| System Engineer | `requirements/system-requirements.csv` (SR-###); **gatekeeper** |
| Software Engineer | `requirements/low-level-requirements.csv` (LLR-###) + code + `architecture.md` |
| Test Engineer | `test/test-cases.csv` (TC-###) + the check harness + coverage/trace reports |

A hat only edits artifacts it owns; to change another, file a finding addressed
to its owner (§5).

**Domain hats (scope-dependent).** The five above are the spine; choose
additional discipline hats at project setup to match the scope — e.g. **Network
Engineer**, **Security Engineer**, **Data/ML Engineer**, **Hardware/Mechanical
Engineer**, **Mechatronics Engineer**, **DBA**, **SRE/Ops**. A domain hat owns
the slice of `SR-###`/`LLR-###` rows in its area (tag them, e.g. an `Area`
column or an `SR-NET-###`-style prefix) and brings its own edge-case and
release-checklist items. Record the **active hats** for this project in
`status.md`; don't wear a hat the scope doesn't need. Like the others, a domain
hat is usually the same driver switching context — spawn a separate specialist
agent only for an independent high-risk review (§6).

## 2. Identifier scheme

| Prefix | Level | Parent link |
|---|---|---|
| `UN-###` | User Need | — |
| `SR-###` | System Requirement | `UN-Refs` |
| `LLR-###` | Low-Level Requirement | `SR-Refs` (+ Module/CodeSymbol) |
| `TC-###` | Test Case | `Verifies` (SR/LLR) |

Stable, zero-padded, never reused.

## 3. Traceability & anti-duplication

- **One fact, one home.** Reference by ID and link; never restate.
- **Decompose, don't paraphrase.** A child adds detail; if it would merely
  repeat its parent, link instead.
- **Registries are the machine source of truth; prose is thin** and links by ID.
- **The traceability matrix is generated** by a small join over the registries'
  ID/parent columns; it reports **orphans** (req with no child/test; test/LLR
  with no parent). Hand-maintaining the matrix is forbidden.
- **Code carries back-links** (`Implements: SR-007, LLR-014`); test names embed
  the verified ID. CSV columns are authoritative.
- **Architecture is generated** (module/function map) so it cannot drift; keep a
  hand-written one-page overview above it.
- **Modularity/dedup**: shared logic in exactly one place; pure cores separated
  from I/O/GUI shells; small functions; one-page-readable architecture.

## 4. Objectives, gates, and exit criteria

Advance only when criteria pass; **pause for human approval at each gate**.
Define machine-checkable criteria wherever possible; classify the rest honestly.

- **G1 — Requirements, UX & constraints.** UN complete (priority + measurable
  acceptance intent + edge cases); every SR links ≥1 UN with measurable
  acceptance criteria; usability/doc needs + constraints + non-goals captured.
  Sign-offs: End User, UX, System Engineer.
- **G2 — Decomposition & test coverage.** Every SR → ≥1 LLR (or
  Analysis/Inspection); every SR and LLR → ≥1 TC; traceability **0 orphans**;
  harness runs locally + CI. Sign-offs: System Engineer, Test Engineer.
- **G3 — Implementation.** Format/lint clean; the **full** test tier passes;
  coverage ≥ `COVERAGE_THRESHOLD`; every test-verifiable SR **Verified**; every
  other SR explicitly **Demonstration / Manual / Inspection**. Sign-offs: System
  Engineer, Test Engineer.
- **G-Release — Release readiness** *(per release; skip for a one-off
  deliverable)*. The **release** test tier passes (incl. slow/hardware tests);
  the generated **release checklist** (`scripts/gen_release_checklist.py`) is
  completed and signed; version bumped; changed `Stable` interface versions
  communicated to counterparts; docs/changelog updated. Sign-offs: Test Engineer,
  any active domain hats, Human.
- **G-Final — Acceptance.** Human/end-user exercises the real product (incl.
  Demonstration/Manual items) and approves. For shipped software this is the
  human half of G-Release; for a bespoke deliverable it stands alone.

**Constants:** `MAX_ROUNDS = 4` per gate (then escalate to the human);
`COVERAGE_THRESHOLD = 80%` line coverage (adjust by agreement; record here).

**Verification methods:** `Test` (automated) · `Demonstration` (run + observe,
e.g. a GUI or a real device) · `Manual` (human procedure) · `Analysis` ·
`Inspection`. Pick the cheapest method that actually establishes the criterion;
don't claim `Test` for something only a human can confirm.

**Test tiers (run cost vs. confidence).** Running the whole suite every iteration
gets untenable as a project grows (and CI has time/quota limits), so each
`TC-###` carries a **`Tier`**: `Smoke` (fast, run every iteration / on every
push), `Full` (the pre-merge suite, run on PRs), `Release` (slow, hardware,
manual-adjacent, or long-running — run at `G-Release`). Tiers are cumulative:
`full` includes smoke, `release` includes both. The harness selects a tier
(`check.py --tier`) via pytest markers; the `Tier` column is the source of
truth. Keep at least the critical paths in `Smoke` so the cheap gate still
catches regressions.

## 5. Verdict & status protocol

Reviews append to `status.md`:

```
### <HAT or REVIEWER> — <Gate> — Round <r> — <YYYY-MM-DD>
Verdict: APPROVE | CHANGES-REQUESTED
Findings:
- [BLOCKER|MAJOR|MINOR] <ID or area> → <issue> → <suggested change> → @<owner>
```

Gate sign-offs live in the **Gate Sign-offs** table; the driver records the gate
decision and pauses for the human.

## 6. Review-depth triage (efficiency)

- **High-risk** (security, data loss, crash-safety, money, irreversible, gate
  closure): spawn an **independent** reviewer with a fresh-context, defect-
  hunting prompt. Verify its file edits; never trust an unverified "green."
- **Medium**: self-review against the gate checklist + run the harness.
- **Low/mechanical** (rename, doc tweak, config): just run the harness.

Keep the status file's *Current State / Open Items* header short so a reviewer
can orient cheaply; the full log lives below and need not be re-read each pass.

## 7. Harness contract (wire to your stack)

`scripts/check` (and the CI workflow) must run, and fail nonzero on any failure:
format check · linter (warnings as errors) · unit + integration tests · coverage
(≥ threshold) · the traceability check (0 orphans for the active gate). Emit the
coverage + traceability reports as artifacts. Prefer a generated architecture
map step so `architecture.md` stays current.

Ready reference scripts ship with this template (Python 3.8+, stdlib only — no
pip needed to run them):

- `scripts/check.py` — the harness itself. Gate-scoped (`--gate G2|G3|all`), runs
  format · lint · tests · coverage · traceability · arch-map freshness, and exits
  nonzero on any failure. Wire it to your stack by editing its `STEPS` table; the
  contract is the gates + exit code, not the specific tools. CI runs the same
  command (`ci/check.yml`).
- `scripts/trace.py` — joins the registries, writes `docs/test/report.md`, exits
  nonzero on orphans with `--strict`. Called by `check.py` at G2/G3.
- `scripts/gen_arch_map.py` — regenerates the module/function map in
  `architecture.md` from the source tree (and surfaces `Implements:` back-links);
  `--check` fails when the doc is stale, so the map can't drift.
- `scripts/gen_release_checklist.py` — generates the human **release checklist**
  for `G-Release` from the registries: every Demonstration/Manual/Inspection SR,
  every Release-tier/manual TC, the UN acceptance intents, and provided
  interfaces — each a tick-box back-linked to its id. Keep the completed copy as
  the sign-off record.

**Cross-platform launchers** (so a fresh clone is trivial to run on any OS):
`scripts/setup.{sh,ps1}` create a venv and install the toolchain;
`scripts/check.{sh,ps1}` are thin wrappers that forward to `check.py`. Provide
the pair for every platform the project supports.

`scripts/bootstrap.py` scaffolds all of the above (plus `docs/` and CI) into a new
repo in one command. See `EXAMPLE.md` for a complete worked UN→SR→LLR→TC chain.

## 8. Cross-project interfaces (only when projects interlink)

When this project provides or consumes a contract shared with another repo,
record each shared surface once in `requirements/interfaces.csv` as an `IF-###`
(see `INTERFACES.template.md`): direction, counterpart, contract, the `SR-Refs`
that realize/rely on it, version, and stability. The owning (`Provides`) side
holds the authoritative spec; the consuming side links the same `IF-###` and
pins the version. Every interface is backed by an SR and a contract/fixture test.
This keeps interlinked projects from silently drifting apart without imposing a
multi-repo build system. Standalone projects skip this section.
