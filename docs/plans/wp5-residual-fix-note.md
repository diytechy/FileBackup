# WP5 re-review residual (HIGH): the already-compressed exemption is keyed on the payload

*Audit note for the driver to merge into docs/status.md. Data-integrity hat,
branch `resync_v2`, 2026-08-23.*

## The defect

`Get-StorageFormFinding` granted the "already-compressed source file" exemption
only when the row's `RelativePath` ended in `.7z`, while `Get-StoredFileForm`
judges a stored file by its 7z magic bytes. The two never agreed for a source
file whose *content* is a 7z archive under any other name — `archive.7z.bak`,
a `.pack` file, an installer payload.

Consequences on an **untampered, correct** store:

1. Verify reported `FlagOverArchive` for that row and exited 1 across IF-001 —
   a false alarm on a store with nothing wrong with it.
2. `-RepairStorage` then took the bytes as ground truth and set
   `Compressed=Yes` (and renamed the data file to `*.7z`), after which the next
   restore **expanded the user's own archive** and wrote the inner payload under
   the original filename, exiting 0. Silent corruption of a previously correct
   store — the worst shape available in this product.
3. `-Deep` mislabelled the same case: it expanded the file and compared the
   inner file against the row, producing `PayloadMismatch`.

## The fix

The exemption is now keyed on the **payload**, not on the name. When the
observed form is `Archive` while the row says `Compressed=No`, the file's OWN
bytes are hashed against the row's `(xxH2Hash, Length)`:

- **match** → this is raw storage of archive-shaped content, which is correct
  (SR-004 declines to re-compress an already-compressed source). No finding,
  and no `NameLies` either.
- **mismatch** → a genuine `FlagOverArchive` (the classic legacy shape, where
  the *payload* and not the file reproduces the row). Found and repaired as
  before.

A `.7z` RelativePath is kept purely as a fast path. `-Deep` consults the same
answer, so it never expands a file whose own bytes already reproduce the row.
`Repair-BackupStorageForm` applies the identical payload-keyed rule to the
per-row `Compressed` rewrite inside its grouped path — it reads the bytes'
identity **before** the rename moves them — so a row exempted by payload follows
its file through a rename but keeps its own `Compressed`.

**Cost:** the confirming hash runs only for a file whose bytes are an archive
while its row says `No` — rare — so the default (non-Deep) scan is still a
six-byte read per row. Stated in the function help.

## Evidence

- Repro-first: with the engine change stashed, the new fixtures are RED —
  4 failures, all `FlagOverArchive` on `archive.7z.bak` in an untampered store
  (Mirror and HashAddressed; the two Compress modes are green because the
  engine compresses a `.bak` source anyway). Green with the fix: 82/82 in
  `tests/Unit/StorageForm.Tests.ps1`.
- `Invoke-Pester tests\Unit`: **321 passed, 0 failed** (baseline 316; +5).
- `python scripts/trace.py --strict`: `SN=30 SR=52 LLR=51 TC=101 orphans=0
  integrity=0`.
- `pwsh scripts/check.ps1 -Tier Smoke -Gate G1`: **All steps passed** (lint,
  traceability, doc navigability, architecture-map freshness, Pester unit).
  At the default gate G3 the run fails on exactly one step, Traceability, with
  `status-findings=1` — the pre-existing SR-052 / WP3-ratchet item that
  `scripts/check.ps1` documents at line 119. Verified identical on stashed
  HEAD (`baseline exit=1`, same counts), so it is untouched by this change.

## Test and registry changes

- **TC-093** fixture repaired: `already.7z` held the literal string
  `pretend-archive-source`, which `Get-StoredFileForm` classifies as `Raw` — so
  the clean-store assertion never reached the exemption and passed vacuously.
  Both it and the new `archive.7z.bak` now hold REAL 7z bytes produced by
  `Compress-FileWithSevenZip`.
- New TC-093 cases: (a) an untampered store with a 7z-magic source under a
  non-`.7z` name reports zero findings in all four modes with and without
  `-Deep`, exits 0, is left byte-identical by repair, and restores byte-exact
  before and after; (b) a genuine `FlagOverArchive` is still found and repaired.
- `TC-094`'s Parameters cell contained an unquoted comma
  (`sharing=set{unshared,shared-datapath}`), so the row parsed as 10 fields and
  every column after Parameters was off by one. Re-quoted.
- Registry text updated: `LLR-049` Detail, `TC-093` / `TC-094` Expected.

No restorer or kit file changed → **no KitRevision bump, no bats change**.

## Residual

Full tier not run for this change (narrow, engine-local, Smoke green); the
driver should run it once WP6's docs work merges.
