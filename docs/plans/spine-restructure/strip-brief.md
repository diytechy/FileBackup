# Strip brief: one proposer's job

You are one of two independent proposers. The other proposer gets the same
brief and never sees your output, and you never see theirs. A coordinator
compares the two proposals and makes the final call. Work alone. Do not look
for, or read, any other proposal under `docs/plans/spine-restructure/strip/`.

## What "strip" means here

FileBackup's spine (SN → SR → LLR → TC) was back-filled from the code. Its
rows carry material a requirement row must not hold. **Stripping removes that
material from each row while keeping the row's durable obligation in that same
row.** It is not the restructure. Do not split rows, create rows, renumber,
re-parent, or reorganise. Those come in the next phase. A sparser spine is the
expected and welcome result.

Remove from every text cell:

1. **Provenance.** Dates, `AMENDED`/`REWORDED`/`Added`/`Renamed`, "ruled",
   "finding", "regression", review or defect ids (D-#, M-#, T#, F-#), WP/OI/WI
   numbers, kit revisions given as history, links to plans or defect reviews,
   and "[Field restored …]" notes. **Keep the reason**: if a provenance clause
   carries an argument ("so a killed run can't publish a half-written
   index"), restate the argument as standing prose and drop only the frame.
2. **Implementation carriers, at SN and SR**: file names (`MANIFEST.csv`,
   `Temp.lock`, `Reconstruct.ps1`), cmdlet and function names, parameters
   that are really code (`-LiteralPath`), library and type names
   (`System.IO.Hashing`), and code line numbers. Replace each with the
   capability or artifact-class wording: "the backup's index", "the restore
   kit", "the staging area". **At LLR**, remove code names from `Title` and
   `Detail` and restate them in contract voice: inputs, outcome, refusals. A
   behaviour-preserving refactor must leave the row true. Leave the `Module`
   and `CodeSymbol` cells untouched; the harvest keeps them, and they retire
   at the restructure. An LLR may still name a shipped boundary artifact (the
   config document, the launchers).
3. **Instruments in acceptance.** "Pester Describe X", "Unit: Get-FileXxHash",
   "TC-123 asserts", "Mutation-checked", "Statically:". Acceptance keeps the
   observable condition and its threshold; *how* it is observed belongs to the
   TC.
4. **Mechanisms in a need (SN), or in an SR beyond what crosses the
   boundary.** A need states a stakeholder outcome. "Rename after manifest",
   "a witness with row count and digest" and "content-addressed" are designs.
   Remove the mechanism and record it with destination `LLR`. An SR keeps what
   is observable at the system boundary and moves the internal design
   (`destination: LLR`).
5. **Stale text.** Anything describing behaviour the current code no longer
   has: the four storage modes, Mirror, `HashAddressed`, extension-gated
   compression, the old object-name grammar. Check the code
   (`Modules/*.psm1`, `FileBackup.ps1`, `Reconstruct.ps1`, `bash/`) when
   unsure. The code's current behaviour is the reference for this retrofit,
   unless a row states an obligation the code visibly violates; flag that,
   don't strip it.
6. **Contradictions.** Where two rows contradict, read the code, keep the
   side the code implements, strip the stale side, and record both ids. If the
   code is ambiguous, strip nothing and flag it.

**Do not remove:** an obligation, a bound, a threshold, a refusal condition,
an edge case, a declared vocabulary (config setting names and their value
sets, exit-code values, action words — these are interface vocabulary, not
code), or a rationale's argument. When unsure whether something is an
obligation or noise, keep it and say why in `notes`.

## Context the owner has ruled (read-only for you)

- **Vision:** in `docs/plans/spine-restructure-gap-map.md` §3, "Owner rulings
  on D1–D4": one owner's files; the tool is needed only to make backups, never
  to recover them; compression only where measurement shows a saving.
- **Stakeholders:** Owner, Restorer, a generic Backup host. HomeHub is only an
  example of a backup host, so a need naming HomeHub should say "the backup
  host" instead.
- **Scope:** the CI proof of the container is a TC-tier matter (SN-028,
  SR-044 → `retire`, destination `TC`). Container build and export tooling
  is delivery, outside the product spine. The media metric stays as an
  optional feature.
- The full target rules are `C:\Projects\ai-template\project-trajectory\prompts\spine-questions.md`
  §0–§3. The gap map's appendices hold an earlier first-pass verdict per row.
  Treat it as a claim to check, not an answer.

## Inputs

- `docs/plans/spine-restructure/harvest/{sn,sr,llr}.json`: every row, with its
  cells verbatim (`cells`) and extracted hints. **The source of truth for the
  text is `cells`.**
- The code, for stale and contradiction checks.

## Output

Write exactly one JSON file per tier you were assigned, to the output
directory you were given: `sn.json`, `sr.json`, `llr.json`. Each is an array
with one object per input row, in input order. **No row may be omitted.**

```json
{
  "id": "SR-001",
  "verdict": "strip",
  "cells": {"Requirement": "…full stripped text…", "Rationale": "…", "AcceptanceCriteria": "…"},
  "removed": [
    {"text": "AMENDED 2026-08-24 (kit-bump rev6): …", "kind": "provenance", "destination": "log"},
    {"text": "MANIFEST.csv", "kind": "file", "destination": "drop", "replaced_by": "the backup's index"}
  ],
  "contradicts": [],
  "notes": "one or two sentences, only when a call was close"
}
```

- `verdict` is one of:
  - `keep`: nothing to remove.
  - `strip`: some text removed, the obligation kept.
  - `retire`: nothing durable is left, or it belongs wholly to another tier or
    to delivery. Say where in `notes`.
  - `flag`: you could not decide; say why.
- `cells` holds only the text cells you changed, each with its **complete new
  text** (not a diff). For SN those are `Need (plain language)`,
  `Why it matters` and `Acceptance intent (how we'd know it's met)`, or for
  the edge-case table `Scenario` and `Expected behavior`. For SR they are
  `Title`, `Requirement`, `Rationale` and `AcceptanceCriteria`. For LLR they
  are `Title` and `Detail`. Never change id, ref, status, priority,
  verification or phase cells.
- `kind` is one of: `provenance`, `code`, `file`, `instrument`, `mechanism`,
  `stale`, `contradiction`.
- `destination` is one of:
  - `log`: history.
  - `LLR`, `IF`, `TC`: content that belongs at that tier.
  - `drop`: replaced by a capability word, or genuinely nothing.
- `contradicts` lists ids this row conflicts with. For each, say in `notes`
  which side the code supports.

When you finish, print one summary line per tier: rows per verdict, and the
count of removals per kind.
