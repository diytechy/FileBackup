# Option 3 — content-addressed storage + index view (design record)

**Status:** design RULED by the human 2026-08-24 (see status.md audit entries of
that date); this file is the consolidated pre-WP design record. The fix WP(s)
still run the full gated process (G1 requirements pass → G2 decomposition → G3
implementation + independent review — engine and restore surface, so the
independent pre-gate review is mandatory per process.md §6). Nothing here is
implemented yet; AGENTS.md continues to describe the current code until G3.

**Ruling (human, 2026-08-24, verbatim intent):** content-address all storage;
Mirror browsability becomes a best-effort, non-authoritative view; where the
filesystem cannot support richer views, "the user must refer to the manifest."
View mechanism ruled: **generated HTML index, not links** ("agreed with the
html index, that also gives searchability"). Backward compatibility is NOT
required (human ruling 2026-08-24) — store-format and config changes are free.

**Deployment facts recorded with the ruling:** production disks are **NTFS**
(4 TB library source; 6 or 8 TB backup — human unsure which). The bench drill
ran on exFAT stand-ins. NTFS keeps a future `link` view *feasible*, but the
index is the ruled v1 mechanism; `link` stays out of the enum until a
deployment asks for it.

---

## 1. Why (one paragraph)

D-1: Mirror addresses data files by PATH ("whatever this source file holds
now") while dedup hands that address to rows that mean "these exact bytes";
an ordinary edit of one of two duplicate files destroys the last copy
(`Save-SupersededData`'s source-based survival test authorizes the in-place
overwrite — mechanism (a), settled by code reading 2026-08-24). Hash naming
(`Get-HashSizeFileName`) makes a stored object immutable-by-construction:
different content ⇒ different filename ⇒ no overwrite, ever. Option 3 makes
that the ONLY addressing semantic, deleting the hazard class rather than
guarding it. D-5 (same-run duplicates stored twice) resolves in the same WP:
with one addressing semantic, intra-run dedup is the natural implementation.

## 2. Storage design

- **All data files are hash-named** via `Get-HashSizeFileName` — the existing
  HashAddressed behavior becomes the only behavior. `±Compress` remains, and
  remains per-file (`Test-ShouldCompress`): compressed rows store as `.7z`,
  incompressible rows keep their real extension.
- **Pool subfolder (recommended, decide at G1):** data files move under a
  dedicated `<BackupRoot>/pool/` (or similar) so the separation
  root-infra / pool-data / view is structural. With it,
  `Test-IsInfrastructureFile`'s allowlist shrinks toward a prefix check, and
  "the backup root holds no loose data files" becomes an invariant. Even
  without it, a flat hash-named root already guarantees no data file can
  spell an infrastructure name.
- **Manifest schema:** the 9-column contract survives as-is for the WP's
  entry point; `StoredAsHashSize` becomes constant `'Hash'` and
  `Duplicate` becomes derivable — whether to retire either column is a G1
  decision (the "smallest honest normalization" from the 2026-08-24
  two-registry analysis is explicitly OPTIONAL and separate; if ever adopted,
  `{hash,length}` stays on every logical row — never an opaque id).
- **Collision machinery deleted** (the payoff): the SR-022 Mirror-name
  refusal (`Engine.psm1:2861-2865`) and its rename/re-home twins
  (`:1143-1145`, `:1791-1792`); `Sync-BackupStorageLayout`'s Mirror target
  branch and form-conflict gate; the B6 nested-infra-name recovery hazard on
  the pool (pool files can never carry user names). MAX_PATH exposure leaves
  the authoritative store (~27-char flat names; 7-Zip never sees a deep path).
- **Emergency predicates land regardless** (also valid under any design, and
  they harden the transition): `Save-SupersededData`'s survival test asks
  "does a live BACKUP row still demand this `(hash,length)`" (not "is it
  still in the source", `Engine.psm1:2996,3003`), and no write may change the
  bytes at a `DataPath` any row still claims under a different key — the
  minimal violated invariant from the defect review, kept as a stated
  invariant + test even after hash naming makes it structural.

## 3. The view (BrowseView)

- **Mechanism:** a single generated root-level **`INDEX.html`** (collapsible,
  searchable tree; one relative `<a href>` per logical path — double-click
  opens the pool file) plus a sibling **`INDEX.tsv`**
  (`RelativePath ⇥ pool name ⇥ Length ⇥ xxH2Hash`) for grep/scripting.
  Works on every filesystem (incl. exFAT) and both OSes, no privileges.
- **Location: OUTSIDE both roots**, a same-volume sibling — default
  `<BackupPath>_View`, `ViewPath` configurable, refused when
  `Get-VolumeIdentity` disagrees with `BackupPath`. Consequence: zero edits
  to the six filesystem scans (`Get-DataFile`, `Test-BackupManifest`,
  `Sync-BackupStorageLayout`, `Get-SnapshotPrunePlan`,
  `Get-StorageFormFinding`, the restorers' pool scans) and a **zero-line diff
  in both restorers**.
- **Naming rule:** view entry name = `RelativePath` + (`Compressed == 'Yes'`
  ? `'.7z'` : `''`) — driven by the ROW's `Compressed` column, never the
  set's config (per-file compression ⇒ mixed trees; pin in a test).
- **Dedup faithfulness:** every one of the N paths sharing content gets an
  entry. Today's Mirror OMITS the borrower's path entirely — the view is
  strictly more faithful to the source tree than Mirror ever was.
- **Lifecycle:** purely manifest-derived (no new column); fully regenerated
  as a **new pipeline step 16** (after step 15, so Optimize has finished
  electing keepers); staleness detected by stamping the live manifest's
  witness hash into the view root (`.viewstamp`); explicit rebuild via
  `-Action View`. A torn/stale view is cosmetic by construction — nothing
  reads it.
- **Snapshots get NO view** (invariant): prune `PhysicalBytes` accounting,
  the staging rename, and snapshot self-containment all argue against it.
- **`link` deferred:** rejected for v1 on measurement — NTFS symlinks need
  Developer Mode/elevation for normal users and are unreadable from Linux;
  full link regeneration ≈5 min/500k files on SSD (worse on USB), forcing
  incremental maintenance = another diff-driven bookkeeping site of the
  shape that produced D-1; hardlinks rejected outright (indistinguishable
  from real files to every scanner, false restore candidates, prune
  accounting lies). The enum grows later without breakage if wanted.
- **Bash restorer:** `find … -type f` without `-L` is already link-immune —
  record as intent (comment/test), not accident.

## 4. Config surface

```jsonc
{
  "ConfigVersion": 2,            // PreserveFolderTree is GONE — stale configs fail loudly by name
  "BackupSets": [{
    "CompressEnabled": true,
    "BrowseView": "index",       // "off" | "index"   ("link" reserved, not implemented)
    "ViewPath": null             // optional; default <BackupPath>_View; same-volume enforced
  }]
}
```

`PreserveFolderTree` is deleted (not repurposed); `container/FileBackup.schema.json`
and the example config update with it; `Assert-NoUnknownConfigKey` rejects the
old key by name.

## 5. Test reshape

- Storage-mode axis collapses: `tests/Run-All.ps1` sweeps **2 modes**
  (`±Compress`) instead of 4 — the integration budget halves.
- New focused **G10-View** suite (once per compress setting): index matches
  the manifest exactly; every dedup sibling path present; view excluded from
  Verify/prune accounting; witness staleness ⇒ rebuild; `-Action View`
  idempotent; per-file-compression mixed-tree naming.
- The freed budget funds the **test-battery import** (status.md Open item):
  owner-edit across modes, blank-row-hash vs verified-pool second pass as
  tooling, wrong-bytes-at-DataPath in both restorers (D-2), unrelated-bad-`.7z`
  (D-3), dot/Hidden sources (D-4), fix the vacuous `G2.8 Dedup_singleDataPath`.

## 6. Folded / adjacent items (dispositions from status.md)

| Item | Disposition |
|---|---|
| **D-5** | Resolves inside this WP (single addressing semantic + intra-run dedup). |
| **O(N²) unreferenced scan** (`Test-BackupManifest`, `Engine.psm1:566`) | Fix in this WP (hashtable; pattern at `:761/:772/:1571`). At 500k files the current code plausibly never finishes — critical for the real library. |
| **Source-side manifest cache default** | Stop defaulting the hash cache INTO the source root (silently shadows a real root-level `MANIFEST.csv`); default it outside (change root or app-data), keep `ManifestFolderPath` as override. Decide exact default at G1. |
| **DataPath-keyed CI maps** | Sweep here — same functions touched. |
| **manifest row order** | Sort before `Write-Manifest` here if convenient. |
| **D-2 verify-after-restore, D-3 precedence, D-4 `-Force`, restorer TargetRoot parity, no-7z double record, `RECONSTRUCT.log` target-name nit** | Separate fix WP(s) sharing ONE kit-revision bump (rev 6); approved/pending per status.md Open items. D-2/D-4 are needed regardless of this design. |

## 7. Out of scope

- The two-registry normalization (persisted content registry) — analyzed
  2026-08-24, ruled orthogonal; revisit only after this WP ships, if ever.
- `link`/FUSE/projected-filesystem views.
- bash-v2 (Linux backup engine) — unchanged phase deferral.
- `-RepairFromPruned`.
