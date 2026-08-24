#!/usr/bin/env bats
# TC-054 / SR-031 — a PowerShell-produced fixture backup restores byte-for-byte
# on Linux via reconstruct.sh, from the backup ROOT and from EVERY Snapshot_<date>
# folder, across all four storage modes (Mirror/HashAddressed x +-Compress). The
# per-origin expected TSVs (posixRelPath -> content hash, read from each origin's
# own manifest) are the oracle: a restored file's xxh128sum must equal it.

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

@test "Mirror: root + every snapshot restore byte-exact (TC-054, SR-031)" {
    restore_mode_autodetect Mirror
}

@test "Mirror+Compress: root + every snapshot restore byte-exact (TC-054, SR-031)" {
    restore_mode_autodetect Mirror_Compress
}

@test "HashAddressed: root + every snapshot restore byte-exact (TC-054, SR-031)" {
    restore_mode_autodetect HashAddressed
}

@test "HashAddressed+Compress: root + every snapshot restore byte-exact (TC-054, SR-031)" {
    restore_mode_autodetect HashAddressed_Compress
}

@test "explicit --backup-root/--change-root overrides restore a snapshot byte-exact (TC-054, SR-031)" {
    local bk="$FIXTURES/bash-restore/Mirror/backup"
    local snap="$bk/changes/Snapshot_2024_01_01_09_00_00"
    local out="$BATS_TEST_TMPDIR/explicit"
    run bash "$RS" --target-root "$out" --from "$snap" --backup-root "$bk" --change-root "$bk/changes"
    [ "$status" -eq 0 ]
    verify_tree "$out" "$FIXTURES/bash-restore/Mirror/expected/Snapshot_2024_01_01_09_00_00.tsv"
}

@test "a nested infra-named file (sub/MANIFEST.csv) is recovered by hash from a Mirror snapshot (B6, SR-022/SR-031)" {
    # Regression B6 + the contract's root-level-only infra skip: the blanked
    # nested sub/MANIFEST.csv row recovers from the backup-root copy. The PS
    # restorer's twin is TC-058 (its recursive over-skip was fixed 2026-07-03).
    local out="$BATS_TEST_TMPDIR/b6"
    run bash "$RS" --target-root "$out" --from "$FIXTURES/bash-restore/Mirror/backup/changes/Snapshot_2024_01_01_09_00_00"
    [ "$status" -eq 0 ]
    [ -f "$out/sub/MANIFEST.csv" ]
    [ "$(cat "$out/sub/MANIFEST.csv")" = "nested not-infra" ]
}

@test "refuses a target inside the backup root (SR-009)" {
    run bash "$RS" --target-root "$FIXTURES/bash-restore/Mirror/backup/restore-here" \
        --from "$FIXTURES/bash-restore/Mirror/backup"
    [ "$status" -eq 2 ]
    [[ "$output" == *"inside the backup"* ]]
}
