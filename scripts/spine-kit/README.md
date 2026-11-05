# Pinned spine tooling

This directory contains unchanged files from ai-template commit
`e3e399b8d1a0ba0d6e5b27e280eb9e18e7766b54` (2026-11-05).
`UPSTREAM.json` records their SHA-256 hashes. `LICENSE` covers the copied kit
files, not FileBackup's product code.

The copy is the Python import closure of `trace`, `hats`, `migrate_carrier`
and `gen_release_checklist`. The trace engine imports shared approval and
work-item helpers, so those files travel with it; copying the four entry points
alone would not produce a working checker. No agent route, approval act,
general hook or full-kit process policy is activated by this copy.

Run from the repository root with Python 3.11 or newer:

```powershell
py -3.11 scripts/trace.py --strict-integrity
py -3.11 scripts/trace.py --strict --strict-schema
py -3.11 scripts/hats.py audit
py -3.11 scripts/gen_release_checklist.py --out .artifacts/release-checklist.md
```

The root wrappers delegate to this isolated copy. In particular the upstream
Python architecture scanner does not replace FileBackup's PowerShell AST
generator. The existing PowerShell product checks remain in `scripts/check.ps1`.
Pass `-Python <path-to-python-3.11-or-newer>` to that harness when `python` on
PATH is older. The CI trace job explicitly selects Python 3.11.

The conversion was checked cell-for-cell against corrected CSV before the
active CSV carriers were removed. Historic status words and test detail remain
in the rebaseline's `legacy` directory. The live design/test rows are Drafted:
historic test results do not approve their new parent chain.

This is a **partial spine resync**. The whole-kit `docs/kit-version` stamp is
unchanged. Broader process docs, policy, stage derivation and hooks have not
been resynced. Follow the adoption record for the next steps:
[spine rebaseline](../../docs/plans/spine-rebaseline-2026-11-05.md).

Do not hand-edit vendored Python files. Take a new coherent import closure
from a committed upstream revision and update the hash manifest together.
