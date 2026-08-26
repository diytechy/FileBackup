#!/usr/bin/env bats
# TC-054 / SR-031 — a PowerShell-produced fixture backup restores byte-for-byte
# on Linux via reconstruct.sh, from the backup ROOT and from EVERY Snapshot_<date>
# folder, in both compression combos (storage is always content-addressed since
# WP9 step 5 deleted Mirror; TC-134 regenerated these fixtures). The per-origin
# expected TSVs (posixRelPath -> content hash, read from each origin's own
# manifest) are the oracle: a restored file's xxh128sum must equal it.

setup() { load helpers; }

# Restore every origin of a mode using AUTO-DETECTION only (no --backup-root /
# --change-root): this simultaneously proves the folder-name layout detection AND
# that the committed Windows-path RECONSTRUCT.paths.json sidecar is ignored on
# Linux (its C:\... paths do not resolve, so auto-detection must take over).
restore_mode_autodetect() {
    local mode="$1" tsv name origin out
    for tsv in "$FIXTURES/bash-restore/$mode"/expected/*.tsv; do
        name="$(basename "$tsv" .tsv)"
        origin="$(origin_for "$mode" "$name")"
        out="$BATS_TEST_TMPDIR/$mode/$name"
        run bash "$RS" --target-root "$out" --from "$origin"
        [ "$status" -eq 0 ] || { echo "restore exit=$status for $mode/$name"; echo "$output"; return 1; }
        verify_tree "$out" "$tsv" || { echo "verify failed for $mode/$name"; return 1; }
    done
}

@test "HashAddressed: root + every snapshot restore byte-exact (TC-054, SR-031)" {
    restore_mode_autodetect HashAddressed
}

@test "HashAddressed+Compress: root + every snapshot restore byte-exact (TC-054, SR-031)" {
    restore_mode_autodetect HashAddressed_Compress
}

@test "explicit --backup-root/--change-root overrides restore a snapshot byte-exact (TC-054, SR-031)" {
    local bk="$FIXTURES/bash-restore/HashAddressed/backup"
    local snap="$bk/changes/Snapshot_2024_01_01_09_00_00"
    local out="$BATS_TEST_TMPDIR/explicit"
    run bash "$RS" --target-root "$out" --from "$snap" --backup-root "$bk" --change-root "$bk/changes"
    [ "$status" -eq 0 ]
    verify_tree "$out" "$FIXTURES/bash-restore/HashAddressed/expected/Snapshot_2024_01_01_09_00_00.tsv"
}

@test "a NESTED infra-named pool file is scanned by hash recovery (root-level-only skip) (B6, SR-022/SR-031)" {
    # Regression B6 + the contract's root-level-only infra skip: the original
    # 2026-07 defect was reconstruct.sh applying the skip RECURSIVELY. The
    # engine no longer produces nested pool files (hash names are flat at the
    # root), so the legacy shape is CONSTRUCTED — the restorer deliberately
    # still serves legacy stores: sub/MANIFEST.csv's OBJECT is moved to the
    # nested infra name; its row's named file is then missing, forcing hash
    # recovery, which must scan past backup/sub/MANIFEST.csv rather than skip
    # it. The PS twin is TC-058 (same constructed shape since WP9 step 5).
    local store="$BATS_TEST_TMPDIR/b6-legacy"
    mkdir -p "$store"
    cp -r "$FIXTURES/bash-restore/HashAddressed/backup" "$store/backup"
    local bk="$store/backup"
    local want obj
    want="$(expected_hash HashAddressed 'sub/MANIFEST.csv')"
    [ -n "$want" ]
    obj="$(pool_file_by_hash "$bk" "$want")"
    [ -n "$obj" ]
    mkdir -p "$bk/sub"
    mv -- "$obj" "$bk/sub/MANIFEST.csv"

    local out="$BATS_TEST_TMPDIR/b6"
    run bash "$RS" --target-root "$out" --from "$bk" --backup-root "$bk" --change-root "$bk/changes"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    [ -f "$out/sub/MANIFEST.csv" ]
    [ "$(cat "$out/sub/MANIFEST.csv")" = "nested not-infra" ]
}

@test "refuses a target inside the backup root (SR-009)" {
    run bash "$RS" --target-root "$FIXTURES/bash-restore/HashAddressed/backup/restore-here" \
        --from "$FIXTURES/bash-restore/HashAddressed/backup"
    [ "$status" -eq 2 ]
    [[ "$output" == *"inside the backup"* ]]
}
