# Derivation brief, round 1: the frame and the stakeholder needs

You are one of two independent derivers. The other gets this same brief and
never sees your output; you never see theirs. A coordinator compares the two
results and builds the tier from them. Work alone. Do not read anything under
`docs/plans/spine-restructure/derive/` except your own output directory.

## The job

Write FileBackup's new **need tier** and the **frame** around it, in the kit's
TOML carriers:

1. `stakeholder-needs.toml`: the three stakeholder rows (given below) and every
   stakeholder need.
2. `external.toml`: the external parties (`entity.EXT-NN`), the boundary
   crossings (`boundary.B-NN`), and any relationships between two external
   parties (`relationship.REL-NN`).
3. `assumptions.toml`: the domain assumptions (`assumption.DA-NN`). Add a
   `surrogate.SUR-NN` only where a test stand-in plainly exists.
4. `mapping.md`: one line per legacy need SN-001…SN-036, saying what became of
   it: kept as SN-xxx, merged into SN-xxx, split into SN-xxx and SN-yyy,
   moved down to SR or design, or retired, each with a reason. Then one line
   per new need, naming the evidence for it.

Every row is `status = "Drafted"`. You author; you never approve.

## Fixed inputs (Owner rulings; do not change them)

- **Vision:** the `PROJECT-VISION` block at the top of `README.md`. Every need
  must serve part of it. A need serving none of it is scope creep; say so
  rather than writing it.
- **Stakeholders.** Write exactly these three rows:
  - `STK-01` **Owner**: configures, schedules, sets retention, checks store
    health, and owns the space and time the backups cost.
  - `STK-02` **Restorer**: the owner, or whoever holds the backup folder, on a
    clean or foreign machine with no FileBackup installed, possibly another OS,
    possibly under stress.
  - `STK-03` **Backup host**: any system that runs FileBackup unattended on the
    owner's behalf and acts on its results (a home server, a NAS, a container
    platform, a scheduled task). Generic on purpose: no need names HomeHub or
    any one product. HomeHub may appear in `external.toml` only as one example.
- **Scope:**
  - The media metric is an optional, configurable feature serving
    space-efficiency. Its need is roughly "show me where backup space goes,
    such as large files or media that could be re-encoded at a lower bitrate".
  - CI proof of the container is a test-tier matter, not a need.
  - Container build and export tooling is delivery, outside the spine.
    Running backups inside a container on a backup host is a product need.
- **Hats:** `docs/requirements/hats.toml`. Tag each need with the tags whose
  hat's charter subject *is* that need's subject (the tag list is in the file's
  header). Untagged is normal; never tag just to reach a hat.
- **Ids.** Keep a legacy SN id where the need's meaning survives. Mint new
  needs from SN-037 upward. Never reuse a retired id. External ids: `EXT-01…`,
  `B-01…`, `REL-01…`, `DA-01…`.

## Rules for a need (the kit's §0 and §1)

The full text is `C:\Projects\ai-template\project-trajectory\prompts\spine-questions.md`
§0–§1, and the schema is
`C:\Projects\ai-template\project-trajectory\registries\stakeholder-needs.template.toml`.
Read both. In short:

- A need is a **stakeholder outcome in plain language**. It names no file, no
  code, no tool, no config key and no mechanism ("rename after write", "a
  witness", "content-addressed" are designs). `acceptance` states an
  observable condition, never an instrument.
- **Every load-bearing clause goes in `need` or `acceptance`**, never only in
  `why`. The test: if a stranger derived requirements from `need` plus
  `acceptance` alone, would this obligation appear?
- `why` argues the consequence of not meeting the need. It carries no
  history: no dates, no review or defect ids, no "after the incident".
- **One outcome per need.** Split a need that bundles two outcomes, and merge
  two needs that are one outcome.
- **Cover the lifecycle.** Add `lifecycle = "Provision"` (before the first run:
  install, prerequisites) or `"Startup"` (once per launch: configuration,
  format and version checks) where a need is not steady-state; omit it for
  Runtime.
- **Edge cases are ordinary needs.** "Never hand me a half-written backup" is
  a need like any other.
- **Consider the cost:** time, memory, disk, licensing and observability needs
  are needs, routed like any other.
- `priority`: M (Must), S (Should) or C (Could). Every need has
  `stakeholder_refs`.

## Evidence you may read

- `docs/requirements/stakeholder-needs.md`: the 36 legacy needs, already
  stripped of provenance and carriers. This is the Owner's stated intent. Read
  each one's `why` before declaring it unsupported.
- `docs/requirements/system-requirements.csv`: the stripped legacy SRs, read
  **only** to find outcomes the system already serves that no legacy need
  demands (for example concurrency, a vanished source, upgrade of an existing
  store, scale, observability). Do not copy an SR into a need; state the
  stakeholder outcome behind it.
- `docs/plans/spine-restructure-gap-map.md` Appendix A: an earlier first-pass
  list of missing needs, candidate parties, crossings and assumptions. It is a
  claim to check, not an answer.
- `README.md` and `AGENTS.md`, for what the product does.

## The frame

- **Entities.** Each is one party outside FileBackup, with
  `class` ∈ {operational, enabling, interoperating, deliverable}. Include the
  backup volume, the source filesystem, the restore host and target, the tools
  the restore relies on, the backup host, the owner as operator, notification,
  and the self-contained backup folder handed to a future restorer
  (deliverable).
- **Boundary crossings.** What crosses, in one testable line, with
  `direction` ∈ {in, out, inout} from FileBackup's point of view and
  `system = "operation"` (or `"delivery"` for the build-only crossings, if you
  include any). Requirements will later be stated *at* these crossings, so
  draw them where an observable happens.
- **Assumptions.** Things taken to be true about the world between what
  FileBackup does and what a stakeholder experiences, such as atomic same-volume
  rename, lock release on process death, stable bytes during a read, a
  negligible content-key collision rate, accurate free-space reports, and
  time and attribute fidelity on the target. Each assumption carries
  `effect_at` (crossing ids), `holds_when`, `obstacle`, a `falsifier` where
  one exists, and `obstacle_hats` where a hat produced the obstacle.

## Output

Write the four files to the output directory you were given, and nothing
anywhere else. Validate that each TOML file parses with Python's `tomllib`,
that every `stakeholder_refs`, `effect_at`, `entity` and `party` id resolves,
and that every tag is in the hats file's list. Finish by printing the counts:
needs (kept, new, merged-away, retired), entities, crossings, assumptions.
