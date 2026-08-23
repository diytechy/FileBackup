# WP3 — Container release-verify + smoke depth + ratchet re-arm: work order

Drafted 2026-08-22 by an independent Sonnet planning agent (read-only pass at
`ba1ee48`), adopted by the driver under the human's 2026-08-22 grind
authorization (batch ratification). Covers Open-items rows **"container
release-verify"** and **"container smoke depth"**. Ids allocated: **SN-028,
SR-044, LLR-044, TC-079..080** (WP1/WP2 hold through SN-027/SR-043/LLR-043/
TC-078). Prefer amending SR-034/LLR-034/TC-060 over minting where the work
verifies existing requirements.

## Grounding notes (deviations from the disposition text found by inspection)

1. **The disposition's "witness sidecar" claim is stale.**
   `scripts/Invoke-Container.ps1` (`Invoke-ContainerSmokeTest`, ~line 149)
   already checks `MANIFEST.csv.meta` — WP1 added it. The **real** gap: the
   loop omits `RECONSTRUCT.paths.json`, which *is* a genuine kit artifact
   (copied by `Complete-ChangeFolder`'s artifact loop and in
   `Test-IsInfrastructureFile`'s allowlist). Today's loop checks 7 names but
   the *wrong* 7. The full real kit is 8 files: `MANIFEST.csv`,
   `MANIFEST.csv.meta`, `RECONSTRUCT.bat`, `RECONSTRUCT.ps1`,
   `reconstruct.sh`, `FileBackup.Common.psm1`, `System.IO.Hashing.dll`,
   `RECONSTRUCT.paths.json`. Fix: add `'RECONSTRUCT.paths.json'`.
2. **`--phase` is set in exactly two places**, both get the same edit:
   `scripts/check.ps1:105` (`@('--require-verified','--phase','core,bash-v1')`)
   and `.github/workflows/tests.yml:44`. Both become
   `core,bash-v1,container-v1`.
3. **`check.ps1` has no container step** — deliberate; stays CI-only
   (decision 1 below).
4. **Snapshot-restore mechanics** (verified by reading Reconstruct.ps1): the
   authority folder is wherever the invoked `RECONSTRUCT.ps1` physically
   lives (`$authorityFolder = if ($isChangeFolder) { $here } else
   { $backupRoot }`) — to prove a snapshot restore, invoke `RECONSTRUCT.ps1`
   *from inside the snapshot folder*. `-BackupRootOverride`/
   `-ChangeRootOverride` only affect containment checks and the hash-recovery
   search-folder list — they do **not** relocate the manifest read.
5. `container/entrypoint.sh` already passes `-ExitCode` (WP2); no new
   entrypoint-exit assertions needed here (TC-078's territory).

## 1. Registry changes

**Amend existing rows** (no new ids for verifying already-specified behavior):

- `system-requirements.csv` `SR-034` — `Status`: `Implemented` → `Verified`
  (flip only after the new CI steps are green and TC-060/079/080 all Pass).
- `low-level-requirements.csv` `LLR-034` — `Status` → `Verified`; `TestRefs`
  becomes `TC-060;TC-079;TC-080`.
- `test-cases.csv` `TC-060` — `Status`: `Draft` → `Pass`; reword `Expected`
  (currently "six recovery-kit artifacts" + forward-looking
  Export/Publish/Pull wording) to state what CI now actually proves: the
  8-artifact kit, a `docker load` roundtrip, and a registry publish/pull
  roundtrip, each smoke-reverified.

**New rows:**

`stakeholder-needs.md` (Core needs table):

```
| SN-028 | Prove the container's exported/published image is the same runnable artifact as the locally built one, and that a second incremental run through the container produces a restorable dated snapshot in place, not just a first-run backup. | The container-v1 claim ("distribution=set{local,tar,registry}") and the dated-snapshot model (SR-005/SR-010) are both currently asserted only by unit/Pester coverage outside the container — CI's Docker job never exercises either path end-to-end. | M | CI builds, exports, `docker load`s, and re-smoke-tests the image; CI publishes/pulls through a throwaway registry and re-smoke-tests the pulled image; the container smoke test runs a second, source-mutating pass and restores both the latest state and the superseded snapshot in-container, byte-comparing each against the correct source generation. |
```

`system-requirements.csv`:

```
SR-044,Container distribution and snapshot-restore roundtrip proof,SN-028,"CI shall prove, inside the container job, that an exported image reloads via `docker load` into a working image, that publish/pull through a registry produces a working image, and that a second incremental container run produces a dated snapshot that restores byte-exact in-container alongside the latest state.","Closes the gap between SR-034's acceptance criteria (which already promises tar/registry distribution and container use) and what CI actually exercises today (BuildAndTest only, single no-snapshot run) -- container-v1 cannot be called released without this.","In the `container` CI job: Export -> docker rmi -> Invoke-Container.ps1 -Action Load -> -Action Test all succeed against the reloaded image; Publish to a throwaway registry:2 service -> docker rmi both tags -> -Action Pull -> -Action Test all succeed against the pulled image; the smoke test's kit check lists all 8 real kit artifacts (adds RECONSTRUCT.paths.json); a second, source-mutating container run creates exactly one Snapshot_<date> folder under /changes, and both the post-run latest state and the pre-mutation snapshot restore byte-exact in separate restore containers.","distribution=set{tar-roundtrip,registry-roundtrip}; restore=set{latest,snapshot}",M,Test,Draft,container-v1
```

`low-level-requirements.csv`:

```
LLR-044,SR-044,Container distribution roundtrip + incremental snapshot smoke,scripts/Invoke-Container.ps1;.github/workflows/tests.yml,Invoke-ContainerSmokeTest;Invoke-Container.ps1 -Action Load,"Adds an Action=Load verb (docker load wrapper, mirrors Export) to Invoke-Container.ps1; CI's container job chains BuildAndTest -> Export/Load roundtrip -> Publish/Pull roundtrip against a throwaway registry:2 service, re-running -Action Test after each reload. Invoke-ContainerSmokeTest gains the RECONSTRUCT.paths.json artifact check and a second incremental run (source mutated between two docker run invocations) that asserts a Snapshot_<date> folder appears, then restores both the latest state and the snapshot alone in separate restore containers, byte-comparing each against the correct source generation.",TC-079;TC-080,Draft
```

`test-cases.csv`:

```
TC-079,SR-044;SR-034;LLR-044,System,Test,Full,"distribution=set{tar-load,registry-publish-pull}","On the ubuntu-latest container CI job, scripts/Invoke-Container.ps1 -Action Export followed by docker rmi and -Action Load reproduces a working image verified by -Action Test; separately, -Action Publish to a throwaway registry:2 service followed by docker rmi (both tags) and -Action Pull reproduces a working image verified by -Action Test. Both roundtrips run in the same job, teardown via the registry service's automatic container lifecycle.",Yes,Draft
TC-080,SR-044;SR-005;SR-010;LLR-044,System,Test,Full,"kit=8-artifact; run=set{initial,incremental}","The container smoke test's kit check lists all 8 real kit artifacts (adds RECONSTRUCT.paths.json to the existing 7). After the first no-snapshot backup and its restore, the source is mutated (one file changed, one removed, one added) and the container is run a second time; exactly one Snapshot_<date> folder appears under /changes with its own complete kit; a restore container reconstructs the latest state from /backup and byte-compares it against the mutated source; a second restore container invokes RECONSTRUCT.ps1 from inside the snapshot folder itself and byte-compares its output against the pre-mutation source (SR-010 point-in-time authority).",Yes,Draft
```

TC-079/080 land `Draft` at mint; flip to `Pass` (and SR-044/LLR-044/SR-034/
LLR-034 → `Verified`) only after a real green CI run, per WP2's precedent
(regex-anchored line edits — avoid full CSV rewrites).

`docs/status.md`: flip the two WP3 Open-items rows to "Implemented (WP3) —
awaiting independent review + batch ratification"; append an audit entry with
real evidence (check.ps1 Full output + CI run link); Current State tallies →
SN=28 SR=44 LLR=44 TC=80, phase-deferred drops 2 → 1 (only bash-v2 remains).

## 2. `scripts/Invoke-Container.ps1` changes

**a. New `Load` action** (symmetric with `Export`):

```powershell
[ValidateSet('Build','Test','BuildAndTest','Export','Publish','Pull','Load')]
...
'Load' {
    if (-not $OutputPath) { $OutputPath = Join-Path $repo '.artifacts\filebackup-image.tar' }
    $OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
    Invoke-ContainerCommand -Arguments @('load','--input',$OutputPath)
    Write-Host "Loaded image from $OutputPath"
}
```

(`docker load` restores the tag baked in at Export time — no retag needed.)

**b. Kit-artifact fix**: add `'RECONSTRUCT.paths.json'` to the smoke's
artifact `foreach` list (8 names total).

**c. Incremental/snapshot smoke depth** — appended AFTER today's single-run
restore verification (strictly additive so a regression can't mask under an
existing passing assertion):
1. Before mutating, `Copy-Item -Recurse $source $sourceGen1` (new
   `source-gen1` folder under `$smokeRoot`, NOT nested inside any bind-mounted
   dir) as the snapshot-comparison reference.
2. Mutate `$source` on the host: rewrite `alpha.txt`, delete `binary.dat`,
   add `gamma.txt` — guarantees both NewOrChanged and RemovedFromSource so
   SR-005 supersession fires.
3. Re-run the same `run` container invocation (reuse `$runArgs` construction)
   against the same mounts — the incremental run.
4. Assert exactly one `Snapshot_<date>` directory under `$changes`
   (`Get-ChildItem -Directory | Where-Object Name -match '^Snapshot_\d'`);
   throw on zero or >1. Capture the name dynamically.
5. Re-run the 8-artifact kit check against both the new `/backup` root and
   the snapshot folder (proves the per-snapshot kit copy, including its own
   witness, works in-container).
6. Restore #1 (extends existing logic): restore `/backup` (latest) into a
   fresh target; byte-compare against the **mutated** source (alpha v2,
   gamma present, binary.dat absent).
7. Restore #2 (new): a third container run with `--entrypoint pwsh`,
   mounting `/backup` and `/changes` read-only and a fresh
   `/restore-snapshot` target, invoking
   `-File /changes/Snapshot_<name>/RECONSTRUCT.ps1 -TargetRoot
   /restore-snapshot -BackupRootOverride /backup -ChangeRootOverride /changes
   -SevenZipPath /usr/bin/7z` (name from step 4, arg list built dynamically).
   Byte-compare against `$sourceGen1` (alpha v1, binary.dat present, gamma
   absent) — the concrete SR-010 point-in-time proof in-container.
8. `finally` cleanup unchanged — `$smokeRoot` removal already covers the new
   subfolders.

## 3. `.github/workflows/tests.yml` changes

Traceability job (~line 44): `--phase core,bash-v1` →
`--phase core,bash-v1,container-v1`.

Container job: add a `registry:2` service + steps (bump `timeout-minutes` to
25; the job is runner-hosted, not `container:`-wrapped, so `services:` ports
map to localhost; Docker trusts localhost for plain HTTP by default — leave a
one-line comment saying so):

```yaml
    services:
      registry:
        image: registry:2
        ports:
          - 5000:5000
    steps:
      - uses: actions/checkout@v4
      - name: Build image and verify a byte-exact restore
        shell: pwsh
        run: ./scripts/Invoke-Container.ps1 -Action BuildAndTest -Image filebackup:ci

      - name: Export -> docker load roundtrip
        shell: pwsh
        run: |
          ./scripts/Invoke-Container.ps1 -Action Export -Image filebackup:ci -OutputPath .artifacts/filebackup-image.tar
          docker rmi filebackup:ci
          ./scripts/Invoke-Container.ps1 -Action Load -Image filebackup:ci -OutputPath .artifacts/filebackup-image.tar
          ./scripts/Invoke-Container.ps1 -Action Test -Image filebackup:ci

      - name: Publish/Pull roundtrip against a throwaway registry
        shell: pwsh
        run: |
          ./scripts/Invoke-Container.ps1 -Action Publish -Image filebackup:ci -RegistryImage localhost:5000/filebackup:ci
          docker rmi localhost:5000/filebackup:ci filebackup:ci
          ./scripts/Invoke-Container.ps1 -Action Pull -RegistryImage localhost:5000/filebackup:ci -Image filebackup:ci
          ./scripts/Invoke-Container.ps1 -Action Test -Image filebackup:ci

      - name: Clean up exported tar
        if: always()
        shell: pwsh
        run: Remove-Item -Recurse -Force .artifacts -ErrorAction SilentlyContinue
```

Add a bounded readiness retry (`curl --retry` against
`http://localhost:5000/v2/`) before the Publish step — registry:2 has no
built-in healthcheck and a slow runner could hit connection-refused.

The explicit `docker rmi` calls force each Load/Pull to prove a genuine
roundtrip rather than reusing a cached tag; they are CI plumbing, so they
call `docker` directly. A raw `docker rmi` failure in a `run: |` block should
hard-fail the step (desired) — don't swallow it.

## 4. `check.ps1` and `docs/gate`

- `scripts/check.ps1:105`: phase list → `core,bash-v1,container-v1`; update
  the comment above it (container-v1 shipped).
- `docs/gate` stays `G3` — this closes an Open-items row within the same G3
  pass.
- No container step joins check.ps1's tiers (decision 1).

## 5. Ordered implementation steps

1. `Invoke-Container.ps1`: Load action + kit-check fix + incremental/snapshot
   smoke. Prove locally with Docker Desktop
   (`pwsh -File scripts/Invoke-Container.ps1 -Action BuildAndTest`) before
   touching CI — highest-risk change.
2. `tests.yml`: registry service + new steps; traceability `--phase` bump.
3. `check.ps1` `--phase` bump.
4. Registries: append SN-028, SR-044/LLR-044/TC-079/TC-080 as Draft; run
   `python scripts/trace.py --strict --phase core,bash-v1,container-v1` —
   0 orphans before touching Status columns.
5. Push the branch; let the real CI container job run; capture the real log.
6. Only after real green CI: flip TC-060/079/080 → Pass, SR-034/SR-044 +
   LLR-034/LLR-044 → Verified.
7. `pwsh scripts/check.ps1 -Tier Full` locally (now enforcing container-v1
   in-phase); paste real output into the status.md audit entry.
8. status.md rows + Current State tallies as in §1.

## 6. Regression risks

- `docker rmi` "image referenced/in use" failures — all `docker run`s use
  `--rm`; keep bare `docker rmi` failures hard-failing.
- `registry:2` readiness race — bounded curl retry before Publish.
- `localhost:5000` insecure-registry trust is a Docker *default*, not a
  guarantee — one-line workflow comment so a future failure diagnoses fast.
- Timeout budget roughly triples the job — bumped to 25 min; verify against
  the first real run.
- The smoke's control flow changes affect the already-green BuildAndTest
  step (same function) — keep new assertions strictly appended; prove locally
  first.
- `source-gen1` copy must precede mutation and live outside every bind mount.
- `services:` teardown assumes a runner-hosted job (true today — no
  `container:` key); note it.

## 7. Decisions on the planner's open questions (driver, 2026-08-22 — flagged for batch ratification)

1. **Container step stays CI-only**, not in check.ps1's tiers (dev machines
   have no Docker guarantee; only the Docker-free `--phase` ratchet reaches
   check.ps1).
2. **`Load` becomes a script action** — Export without a reciprocal Load
   leaves the roundtrip half ad-hoc; Publish/Pull are already paired.
3. **`registry:2` via GitHub `services:`** — standard idiom, free teardown.
4. **Snapshot restore uses explicit `-BackupRootOverride`/
   `-ChangeRootOverride`** — deterministic; auto-detection internals already
   covered by TC-059 on Windows.
5. **One combined change+add+delete mutation permutation** — the full
   rollback matrix is G9's job on Windows; the container proves the same
   mechanism end-to-end, not the mechanism itself.
