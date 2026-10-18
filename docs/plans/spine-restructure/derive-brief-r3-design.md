# Derivation brief, round 3: the design tier (components, interfaces, LLRs)

You are one of two independent derivers. The other gets this same brief and
never sees your output; you never see theirs. A coordinator aligns the two
results and builds the tier, which reviewers then check. Work alone. Do not read
anything under `docs/plans/spine-restructure/derive/` except your own output
directory.

## The job

FileBackup's need tier and system-requirement tier are rebuilt and Drafted.
Write the **design tier** that realizes them, in three TOML carriers:

1. `components.toml`: the component tree, one `[component.CMP-NNN]` per
   component, nested by `part_of`.
2. `interfaces.toml`: one `[interface.IF-NNN]` per interface. Each states its
   **form** only.
3. `low-level-requirements.toml`: one `[design.LLR-NNN]` per design
   requirement, in contract voice. LLRs may nest.

Also write two companion files:

4. `mapping.md`: one line per legacy LLR (LLR-001…LLR-094 in
   `docs/requirements/low-level-requirements.csv`), saying what became of it.
   It was kept as LLR-xxx, merged into, split into, made a child of, moved to
   an interface's form, moved to the test tier, or retired, each with a
   reason.
5. `design-gaps.md`:
   - every place where an SR obligation is not met by today's code, each
     naming the SR, the LLR that now states the design, and what the code does
     instead (this list becomes the build work);
   - every SR that reaches no LLR and no interface, with the reason.

Every row is `status = "Drafted"`. You author; you never approve.

## The target shape (ruled in ai-template, not yet built in its tooling)

Read `C:\Projects\ai-template\docs\plans\2026-10-11-review-churn\pointer-rules.md`
in full; it is the target. Read
`C:\Projects\ai-template\project-trajectory\prompts\spine-questions.md` §0 and §3.
In short:

- **Everything points up.** A top-level LLR carries `sr_refs`. A child LLR
  carries `parent = "LLR-NNN"` instead, and no `sr_refs`; its SR is derived up
  the chain. The links are acyclic. An LLR may carry `constrains = "IF-NNN"`:
  the interface whose behaviour it states. A component's place in the tree is
  its `part_of`.
- **A component** (`name`, `category = "software"`, `part_of`, `status`,
  `notes`) names no file and no code. Draw components from **responsibilities
  the SRs demand**, not one per file. Today's engine module holds several. Where
  today's files do not match the tree you draw, say so in `notes`: that is
  design information.
- **An interface states its form only**: what both sides must agree on to
  connect at all. Examples:
  - an exit code's value set;
  - an on-disk layout's names and grammar;
  - a record's columns and encoding;
  - a configuration document's keys and types;
  - a container's actions and mounts.

  Its keys:
  - `owner`: a CMP id, or `external:<EXT-id>` from `external.toml`;
  - `consumers` **or** `requestors`, never both, each a list of CMP ids or
    `external:<EXT-id>`;
  - `channel`;
  - `data`, the whole form in as many lines as it needs (the old 160-character
    limit does not apply to form);
  - `rationale`, `version`, `status`;
  - `interface_from_external` or `interface_to_external` (a `B-NN` crossing),
    where the interface sits on the system boundary;
  - `bridged_by` (DA ids) or `coincident`, at the boundary;
  - `carried_by`, where one interface rides inside another.

  No interface names a file or code, and none states behaviour. **The
  behaviour across an interface lives in the LLR (or SR) that constrains it.**
  Every interface is constrained by at least one LLR. An interface at the
  system boundary may instead be constrained by an SR: list such pairs in
  `design-gaps.md` under "SR constrains", because the SR tier is not yours to
  edit.
- **An LLR** has these keys:
  - `title`;
  - `sr_refs` or `parent`;
  - `constrains` (optional);
  - `detail`;
  - `dimensions`, the input space of its behaviour in the grammar
    `name=set{a,b}; name=range[min..max]; name=bool; @pairwise`, required when
    it constrains an interface;
  - `rationale`;
  - `hat_refs`, only for a hat the parent SR does not already carry;
  - `status`.

  It states the observable obligation (inputs, outcome, refusals) in words
  that survive a behaviour-preserving refactor. **It names no code file,
  function, cmdlet or symbol.** It may name a shipped boundary artifact (the
  configuration document, the launchers). It has no `shall`, because the SR
  states the obligation and the LLR decomposes it. It has no `module`,
  `code_symbol` or `component` cell: its placement is derived from the owner of
  the interface it constrains. A child adds detail, never a paraphrase.
- **Stop decomposing** where a further split would only paraphrase or
  duplicate. Most SRs need one to three LLRs; some need none, being met
  directly at a boundary interface.
- **Rationale** states what breaks without the row and which alternative lost.
  It carries no history: no dates, no review, defect, WP or OI ids.

## Inputs

You may read all of these. The code is in scope for this tier, because a design
must be one the code can meet or be changed to meet.

- `README.md` (the vision and the user manual), and `AGENTS.md`.
- `docs/requirements/`: `stakeholder-needs.toml`, `system-requirements.toml`
  (123 rows, the parents), `external.toml`, `assumptions.toml`, `hats.toml`,
  `interfaces.csv` (IF-001, the old HomeHub contract, to split into the
  interfaces it bundles), and `low-level-requirements.csv` (the 83 stripped
  legacy LLRs; their `Module` and `CodeSymbol` cells say where things live
  today).
- `docs/plans/spine-restructure/strip/final/llr.json`, `sr.json` and `sn.json`:
  every piece stripped out of the legacy rows, each with a destination tier.
  Pieces marked LLR or IF are your material.
- `docs/plans/spine-restructure/derive/r2-merged/merge-notes.md`, section
  "Moved to the design tier": the digest, store layout, record format and
  lock artifact the SR tier deliberately left to you.
- `docs/plans/spine-restructure-gap-map.md` Appendix C: an earlier first-pass
  component tree, interface list and per-LLR verdict. It is a claim to check,
  not an answer.
- `docs/plans/spine-restructure/harvest/tc.json`: the legacy test cases'
  input sets, thresholds and edge cases. They are the best source for
  `dimensions`.
- The code: `Modules/`, `FileBackup.ps1`, `Reconstruct.ps1`, `bash/`,
  `container/`, `CredSetEx.ps1`.

## Ids

- Keep a legacy LLR id where its meaning survives. Mint new LLRs from
  **LLR-095** upward, and never reuse a retired id.
- Number components from CMP-001.
- Number interfaces from IF-002. IF-001 is the legacy HomeHub contract: retire
  it, and map its parts in `mapping.md`.

## Output

Write the five files to the output directory you were given, and nowhere else.
Validate:

- each TOML file parses with Python's `tomllib`;
- every `sr_refs`, `parent`, `constrains`, `part_of`, `owner`, `consumers`,
  `requestors`, `interface_*_external`, `bridged_by` and `hat_refs` id
  resolves;
- `parent` links are acyclic, and no LLR has both `sr_refs` and `parent`;
- every interface is constrained by at least one LLR, or is listed under "SR
  constrains";
- every SR reaches at least one LLR, or is listed in `design-gaps.md` with the
  reason;
- no LLR, interface or component text names a code file, function, cmdlet or
  symbol.

Finish by printing the counts: components, interfaces (boundary and internal),
LLRs (top-level and child), legacy LLR ids kept, design gaps.
