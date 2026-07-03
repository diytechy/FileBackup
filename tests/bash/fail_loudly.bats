#!/usr/bin/env bats
# TC-055 / SR-031 (mirrors SR-029) — reconstruct.sh restores everything it can,
# then FAILS LOUDLY: a tampered backup exits non-zero naming the unrestored
# count while still salvaging every recoverable row; a clean restore exits 0.

setup() {
    load helpers
    # Work on a WRITABLE copy so we can destroy data sources.
    WORK="$BATS_TEST_TMPDIR/work"
    cp -r "$FIXTURES/bash-restore/Mirror/backup" "$WORK"
    BK="$WORK"; CH="$WORK/changes"
}

@test "a clean (untampered) restore exits 0 (TC-055, SR-031)" {
    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/clean" --from "$BK" --backup-root "$BK" --change-root "$CH"
    [ "$status" -eq 0 ]
}

@test "missing data source: salvages the rest and exits non-zero naming the count (TC-055, SR-031)" {
    rm -f "$BK/hello.txt"                          # destroy one non-blank-DataPath row's source
    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/tampered" --from "$BK" --backup-root "$BK" --change-root "$CH"
    [ "$status" -eq 1 ]
    [[ "$output" == *"INCOMPLETE"* ]]
    [[ "$output" == *"1 file"* ]]
    # The unrecoverable row is absent...
    [ ! -f "$BATS_TEST_TMPDIR/tampered/hello.txt" ]
    # ...but everything else was still salvaged.
    [ -f "$BATS_TEST_TMPDIR/tampered/empty.dat" ]
    [ -f "$BATS_TEST_TMPDIR/tampered/with,comma.txt" ]
    [ -f "$BATS_TEST_TMPDIR/tampered/dir/dup_a.txt" ]
}

@test "hash-unrecoverable: a blank-DataPath row whose only pool copy is gone exits non-zero (TC-055, SR-031)" {
    # In Snapshot_T1, recur.txt is a blank-DataPath row recovered by hash from the
    # backup-root copy. Destroy that sole copy -> unrecoverable -> loud failure,
    # while the snapshot's own superseded rows (hello.txt, data.bin) still restore.
    rm -f "$BK/recur.txt"
    local snap="$CH/Snapshot_2024_01_01_09_00_00"
    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/hu" --from "$snap" --backup-root "$BK" --change-root "$CH"
    [ "$status" -eq 1 ]
    [[ "$output" == *"INCOMPLETE"* ]]
    [ ! -f "$BATS_TEST_TMPDIR/hu/recur.txt" ]
    [ -f "$BATS_TEST_TMPDIR/hu/hello.txt" ]        # superseded bytes preserved in the snapshot
    [ -f "$BATS_TEST_TMPDIR/hu/data.bin" ]
}
