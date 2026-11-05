# `last_approved` — the approval stamp

**This file is prose. Nothing parses it.** Every machine fact about the snapshot comes from the copied registry files beside it, from the act ledger `acts.toml`, or from `git log` over this directory.

## Refreshes recorded under an explicit approval

Each line below records a refresh that copied a registry under authority — a `--approves` ref, rows named by `--reattests`, or a `Status` move in the copied registry (`intake.py snapshot [--approves <REGISTRY=REF>] [--reattests <ROW-ID,...>]`) — and names, for each registry copied, the ref and the re-attested rows, or the Status move when neither named it. The seed and a refresh that copied nothing (a traced-only re-point) write no line.

- 2026-11-05 — refresh under approval. Copied: external.toml (ref: docs/plans/spine-rebaseline-2026-11-05/boundary-approval.md). Registries not named by this act keep their prior snapshot bytes.
