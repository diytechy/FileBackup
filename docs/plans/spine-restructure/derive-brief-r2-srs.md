# Derivation brief, round 2: the system requirements (blind)

You are one of two independent derivers. The other gets this same brief and
never sees your output; you never see theirs. A coordinator compares the two
results with each other and with the legacy rows. Work alone.

## Blindness

This is a **blind re-derivation**: the requirements must follow from the needs
and the frame, not from the code. **Do not read:**

- `docs/requirements/system-requirements.csv`, `low-level-requirements.csv`
  or `docs/test/`;
- anything under `docs/plans/` except this brief;
- `AGENTS.md`;
- any code: `Modules/`, `*.ps1`, `bash/`, `container/`, `scripts/`, `tests/`.

Reading any of them defeats the exercise. If you need a fact only they would
hold, write the requirement as the needs and frame demand it, and note the
question in `notes.md`.

## Inputs you may read

- `README.md`: the vision at the top, and the user-facing manual. Use the
  manual for **declared vocabulary** a stakeholder sees: action names,
  configuration setting names and value sets, exit-code values, flags. Do not
  use it as a design description.
- `docs/requirements/stakeholder-needs.toml`: 48 needs, three stakeholders.
- `docs/requirements/external.toml`: parties, boundary crossings (B-##),
  relationships.
- `docs/requirements/assumptions.toml`: domain assumptions (DA-##).
- `docs/requirements/hats.toml`: the perspectives, and the tags that reach
  them.
- The kit's rules: `C:\Projects\ai-template\project-trajectory\prompts\spine-questions.md`
  §0 and §2. The schema:
  `C:\Projects\ai-template\project-trajectory\registries\system-requirements.template.toml`.
  Read both.

## What an SR is here

- **One testable `shall`, one decision**, on an EARS pattern with the
  condition in front: `The system shall …` / `When <trigger>, the system shall
  …` / `While <state>, …` / `If <fault>, then the system shall …` /
  `Where <feature is enabled>, …`. "The system" is FileBackup: the backup
  engine together with the restore kit it places in every backup. Where only
  one side applies, say "the restore kit".
- **Stated at a boundary.** Each SR states something observable at one or more
  crossings in `external.toml` (`boundary_refs`). A behaviour that crosses no
  boundary and is consumed only by another part of the system is a design
  decision; it belongs at the LLR tier, so do not write it here. A row that is
  off-boundary on purpose says why in `rationale`.
- **Names no file and no code** in any cell, acceptance and rationale included.
  Use capability or artifact-class wording: "the backup's record of a state",
  "the restore kit", "the change-detection state". Declared vocabulary is
  allowed where a stakeholder sees it (an action name, a setting name and its
  values, an exit-code value).
- **Acceptance** holds the observable condition and its pass/fail line. It
  never names an instrument or a test.
- **Rationale** says what breaks without the row and which alternative lost.
  No history.
- **Every SR traces to at least one need** (`sn_refs`) whose text actually
  demands it. If an obligation arrives through a hat rather than through a
  need's text (a **derived requirement**), name the hat in `hat_refs` and
  argue it in `rationale`. Never trace a row to a need that does not call for
  it. If you find an obligation no need demands and no hat justifies, do not
  write it; list it in `notes.md` as a possible missing need.
- **Every need gets at least one SR**, unless it is satisfied wholly by a
  sibling's rows; say so in `notes.md`.
- **Delivery argument.** Set `form` ∈ {interface, assumption, cross-cutting}.
  Cite the assumptions the row relies on in `da_refs`, or, when the system's
  output *is* the outcome, write `coincident` instead. Use `delivered_with`
  for siblings that deliver a need together with this row.
- **Permutations:** the input dimensions a test designer must cover, in the
  grammar `name=set{a,b}; name=range[min..max]; name=bool; @pairwise`.
- `verification` ∈ {Test, Demonstration, Inspection, Analysis, Attest}.
  `priority` M/S/C, inherited from the strongest need it serves unless argued
  otherwise. `status = "Drafted"`. Omit `phase`, `aspect` and any key you have
  nothing for (an empty cell is an absent key).

## Stopping

Stop decomposing at the point where a row states a boundary-observable
obligation in one decision. Do not descend into how the system achieves it.
The design tier comes later. A sparser tier is better than a tier that
restates the design.

## Output

Write to the output directory you were given, and nowhere else:

1. `system-requirements.toml`: one `[requirement.SR-NNN]` table per row,
   numbered from **SR-101** upward. The coordinator renumbers matched rows
   later.
2. `notes.md`: one line per need, listing its SRs, or saying why it has none.
   Then the derived rows and their hats; possible missing needs; and questions
   you could not settle without the forbidden inputs.

Validate that the TOML parses with Python's `tomllib`, and that every
`sn_refs`, `boundary_refs`, `da_refs`, `hat_refs` and `delivered_with` id
resolves. Finish by printing: SR count, the count per need, derived rows, and
rows per `form`.
