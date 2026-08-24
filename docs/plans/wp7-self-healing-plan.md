# WP7 — Storage self-healing + retention unblock

Minted by human ruling 2026-08-23 (status.md, "HUMAN — Open-item rulings +
WP7/WP8 minted") from the two verified investigations of the same date:
blank-DataPath rows are silently permanent and spreading (Verify is blind),
and the prune form-mismatch rail refuses stores that restore perfectly,
wedging two-regime stores permanently.

## Scope (one G1→G3 pass, independent review required — data-integrity surface)

1. **Never adopt a blank DataPath** (`Invoke-BackupFileGroup`): the dedup
   "existing content" candidate set excludes rows whose `DataPath` is blank,
   so a new same-content file falls through to the copy branch instead of
   inheriting a row that points nowhere (kills the R5 spread).
2. **Heal from source** (`Compare-SourceToBackup`): a backup-root row whose
   `DataPath` is blank is treated as changed, so the next run re-copies it
   whenever the source still holds the content (or re-points it at a
   surviving dedup copy via 1). Pure-diff change, unit-testable.
3. **Verify sees the pool** (`Invoke-VerifyAction` + `Test-PoolResolves`):
   `-Action Verify` additionally runs the pool-resolution audit across the
   backup root and every snapshot and reports `broken-pool` findings in the
   JSON document — the blind spot both investigations hit. Report-only; the
   heal is the next backup run (or restore-from-elsewhere), not `-RepairStorage`.
4. **Rail relaxation** (`Test-PoolResolves` blank-row branch): a blank-row
   form disagreement is only a refusal for a folder whose OWN kit revision
   is < 2 (those kits genuinely restore the wrong form); revision ≥ 2 kits
   decide form from the located file (SR-050), so for them the disagreement
   is not reported as a prune-blocking problem. Non-blank-DataPath form
   mismatches remain refusals — the restorers still trust `Compressed` there.
5. **Docs:** README warning against touching backup-root contents; the
   Known-limitation prune box updated to the new conditional behavior.

## Registries

SN-031 (self-healing store), SR-053 (heal + no-adoption), SR-054 (verify pool
audit), SR-046 requirement text amended for the conditional rail, LLR-053/054,
TC-103.. covering: adoption ban, end-to-end heal (external deletion → next run
exits 0 having re-copied → restore byte-exact), dedup re-point, verify reports
broken-pool when the source is also gone, two-regime store prunes with
revision-4 kits, a pre-revision-2 kit still refuses.

## Out of scope

Portable filenames and the raw-candidate recovery (WP8); `-RepairFromPruned`;
the DataPath-keyed case-insensitive membership maps (container-v1 sweep note).
