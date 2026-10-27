#!/usr/bin/env bats
# Kit revision 14 — reconstruct.sh resolves a blank or stale DataPath through a
# NAME INDEX built once per restore, and falls back to find_by_hash (the
# content scan) only when the index has no usable candidate (bounded-run-loop
# section 7). The bats twin of tests/Unit/RestoreIndex.Tests.ps1. The base-57
# decoder itself is held to the PowerShell oracle in name_grammar.bats.

setup() {
    load helpers
}

# copy_store <mode> : a writable copy of a shipped fixture store; sets BK/CH.
copy_store() {
    BK="$BATS_TEST_TMPDIR/store-$1"
    cp -r "$FIXTURES/bash-restore/$1/backup" "$BK"
    CH="$BK/changes"
}

# blank_datapaths <manifest> : blank column 1 of every data row, in place.
blank_datapaths() {
    gawk -v FPAT='("([^"]|"")*")|([^,]*)' -v OFS=',' \
        'NR==1 { print; next } { $1="\"\""; print }' "$1" > "$1.tmp"
    mv "$1.tmp" "$1"
}

# data_rows <manifest> : how many data rows the manifest holds.
data_rows() { gawk 'NR>1 && NF>0' "$1" | wc -l | tr -d ' '; }

@test "a snapshot whose rows are ALL blank restores byte-exact through the name index, never the content scan (both modes)" {
    local mode snap log rows
    for mode in "${MODES[@]}"; do
        copy_store "$mode"
        snap="$CH/Snapshot_2024_01_01_09_00_00"
        # The worst case the field sees (about 96% of real snapshot rows are
        # blank): EVERY DataPath blank, including the two whose objects live
        # in the snapshot itself, so bytes come from the origin AND from latest.
        blank_datapaths "$snap/MANIFEST.csv"
        rows="$(data_rows "$snap/MANIFEST.csv")"

        run bash "$RS" --target-root "$BATS_TEST_TMPDIR/t-$mode" --from "$snap" --backup-root "$BK" --change-root "$CH"
        [ "$status" -eq 0 ] || { echo "$mode: expected 0, got $status"; echo "$output"; false; }
        run verify_tree "$BATS_TEST_TMPDIR/t-$mode" "$FIXTURES/bash-restore/$mode/expected/Snapshot_2024_01_01_09_00_00.tsv"
        [ "$status" -eq 0 ] || { echo "$mode: $output"; false; }

        # The proof the scan did not run: every row was resolved by name, and
        # find_by_hash's own log lines never appear.
        log="$BATS_TEST_TMPDIR/t-$mode/RECONSTRUCT.log"
        [ "$(grep -c 'resolved by name index' "$log")" -eq "$rows" ] || { echo "$mode:"; cat "$log"; false; }
        grep -q 'Name index built' "$log"
        [ "$(grep -c 'attempting hash scan' "$log")" -eq 0 ]
        [ "$(grep -c 'Hash-recovered' "$log")" -eq 0 ]
    done
}

@test "the index prefers the origin's own copy, then latest (kit revision 14)" {
    copy_store HashAddressed
    local snap="$CH/Snapshot_2024_01_01_09_00_00" obj
    # The snapshot's own superseded hello.txt object must be the one used, and
    # an object that exists only in latest must come from latest.
    obj="$(gawk -F'"' '$4 == "hello.txt" { print $2 }' "$snap/MANIFEST.csv")"
    [ -f "$snap/$obj" ]
    blank_datapaths "$snap/MANIFEST.csv"
    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/tpref" --from "$snap" --backup-root "$BK" --change-root "$CH"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    grep -qF "No DataPath for 'hello.txt'; resolved by name index to '$snap/$obj'" "$BATS_TEST_TMPDIR/tpref/RECONSTRUCT.log"
    grep -qF "No DataPath for 'README'; resolved by name index to '$BK/" "$BATS_TEST_TMPDIR/tpref/RECONSTRUCT.log"
}

@test "a DataPath whose object moved to another pool folder resolves through the index (kit revision 14, R6)" {
    copy_store HashAddressed
    local obj
    # Latest's hello.txt object moves into a snapshot: the row still names it
    # in latest, which is the shape a write-once manifest goes stale with.
    obj="$(gawk -F'"' '$4 == "hello.txt" { print $2 }' "$BK/MANIFEST.csv")"
    [ -f "$BK/$obj" ]
    mv "$BK/$obj" "$CH/Snapshot_2024_01_02_09_00_00/$obj"

    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/tmoved" --from "$BK" --backup-root "$BK" --change-root "$CH"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    run verify_tree "$BATS_TEST_TMPDIR/tmoved" "$FIXTURES/bash-restore/HashAddressed/expected/root.tsv"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    grep -qF "missing for 'hello.txt'; resolved by name index to '$CH/Snapshot_2024_01_02_09_00_00/$obj'" "$BATS_TEST_TMPDIR/tmoved/RECONSTRUCT.log"
    [ "$(grep -c 'attempting hash scan' "$BATS_TEST_TMPDIR/tmoved/RECONSTRUCT.log")" -eq 0 ]
}

@test "the content scan runs only when the index has no usable candidate (kit revision 14, call C5)" {
    copy_store HashAddressed
    local obj
    # The bytes survive under a name that is not an object name, so the index
    # cannot see them and the last-resort scan must.
    obj="$(gawk -F'"' '$4 == "hello.txt" { print $2 }' "$BK/MANIFEST.csv")"
    mv "$BK/$obj" "$BK/renamed-by-hand.bin"

    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/tscan" --from "$BK" --backup-root "$BK" --change-root "$CH"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    run verify_tree "$BATS_TEST_TMPDIR/tscan" "$FIXTURES/bash-restore/HashAddressed/expected/root.tsv"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    grep -q "missing for 'hello.txt'; attempting hash scan" "$BATS_TEST_TMPDIR/tscan/RECONSTRUCT.log"
    grep -q "Hash-recovered 'hello.txt' from '.*renamed-by-hand.bin'" "$BATS_TEST_TMPDIR/tscan/RECONSTRUCT.log"
}

@test "an index hit is treated like a DataPath file: wrong bytes under the right name are verified and healed (SR-056)" {
    copy_store HashAddressed
    local obj
    obj="$(gawk -F'"' '$4 == "hello.txt" { print $2 }' "$BK/MANIFEST.csv")"
    # A good copy survives under a non-object name; the object the index picks
    # carries same-length WRONG bytes, and every row is blank.
    cp "$BK/$obj" "$BK/spare.bin"
    printf 'X%.0s' $(seq 1 "$(stat -c '%s' "$BK/$obj")") > "$BK/$obj"
    blank_datapaths "$BK/MANIFEST.csv"

    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/theal" --from "$BK" --backup-root "$BK" --change-root "$CH"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    run verify_tree "$BATS_TEST_TMPDIR/theal" "$FIXTURES/bash-restore/HashAddressed/expected/root.tsv"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    grep -q "No DataPath for 'hello.txt'; resolved by name index" "$BATS_TEST_TMPDIR/theal/RECONSTRUCT.log"
    grep -q 'ContentMismatch' "$BATS_TEST_TMPDIR/theal/RECONSTRUCT.log"
    grep -q 'after a verify mismatch' "$BATS_TEST_TMPDIR/theal/RECONSTRUCT.log"
}

@test "a restore whose every DataPath resolves never builds the index (kit revision 14)" {
    copy_store HashAddressed
    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/tnoindex" --from "$BK" --backup-root "$BK" --change-root "$CH"
    [ "$status" -eq 0 ]
    [ "$(grep -c 'Name index built' "$BATS_TEST_TMPDIR/tnoindex/RECONSTRUCT.log")" -eq 0 ]
}

@test "a snapshot of a one-mount store finds its backup root beside its change root (plan R8)" {
    # <store>/backup beside <store>/changes, restored with no root flags: the
    # change root's parent holds no manifest, so the one sibling that does is
    # the backup root, and every blank row is found by name.
    local mode store snap log rows
    for mode in "${MODES[@]}"; do
        store="$BATS_TEST_TMPDIR/onemount-$mode"
        mkdir -p "$store"
        cp -r "$FIXTURES/bash-restore/$mode/backup" "$store/backup"
        mv "$store/backup/changes" "$store/changes"
        snap="$store/changes/Snapshot_2024_01_01_09_00_00"
        blank_datapaths "$snap/MANIFEST.csv"
        rows="$(data_rows "$snap/MANIFEST.csv")"

        run bash "$RS" --target-root "$BATS_TEST_TMPDIR/t1-$mode" --from "$snap"
        [ "$status" -eq 0 ] || { echo "$mode: expected 0, got $status"; echo "$output"; false; }
        run verify_tree "$BATS_TEST_TMPDIR/t1-$mode" "$FIXTURES/bash-restore/$mode/expected/Snapshot_2024_01_01_09_00_00.tsv"
        [ "$status" -eq 0 ] || { echo "$mode: $output"; false; }
        log="$BATS_TEST_TMPDIR/t1-$mode/RECONSTRUCT.log"
        [ "$(grep -c 'resolved by name index' "$log")" -eq "$rows" ] || { echo "$mode:"; cat "$log"; false; }
        [ "$(grep -c 'attempting hash scan' "$log")" -eq 0 ]
    done
}

@test "a latest-state restore finds the change folder for a row whose object is still in a snapshot (plan C32)" {
    # A move back that failed leaves a latest row naming an object inside a
    # snapshot; with no --change-root, the folder inside or beside the backup
    # root that holds Snapshot_* folders is used.
    local mode obj snap
    for mode in "${MODES[@]}"; do
        copy_store "$mode"
        snap="$CH/Snapshot_2024_01_01_09_00_00"
        obj="$(gawk -F'"' 'NR > 1 && $2 != "" { print $2; exit }' "$BK/MANIFEST.csv")"
        [ -f "$BK/$obj" ] || { echo "$mode: no latest object '$obj'"; false; }
        mv -- "$BK/$obj" "$snap/$obj"

        run bash "$RS" --target-root "$BATS_TEST_TMPDIR/tl-$mode" --from "$BK"
        [ "$status" -eq 0 ] || { echo "$mode: expected 0, got $status"; echo "$output"; false; }
        run verify_tree "$BATS_TEST_TMPDIR/tl-$mode" "$FIXTURES/bash-restore/$mode/expected/root.tsv"
        [ "$status" -eq 0 ] || { echo "$mode: $output"; false; }
    done
}

@test "a change root whose path holds '&' or '#' keeps every sibling snapshot in the pool (review 2026-10-26 A2)" {
    # The snapshot list was prefixed with sed "s#^#$change_root/#": '&' put the
    # match into the path and '#' ended the command, so every sibling snapshot
    # dropped out of the pool. Restoring an older snapshot normally needs an
    # object a newer one holds (C23), and it reported content missing (exit 1)
    # or an unreadable pool (exit 4). The one-mount layout keeps the change
    # folder OUTSIDE the backup root, so no recursive scan of the backup root
    # reaches the snapshots by another route.
    local mode name store older newer obj
    for mode in "${MODES[@]}"; do
        for name in 'Backups & Archive' 'Backup #2'; do
            store="$BATS_TEST_TMPDIR/$name-$mode"
            mkdir -p "$store"
            cp -r "$FIXTURES/bash-restore/$mode/backup" "$store/backup"
            mv "$store/backup/changes" "$store/changes"
            older="$store/changes/Snapshot_2024_01_01_09_00_00"
            newer="$store/changes/Snapshot_2024_01_02_09_00_00"
            obj="$(gawk -F'"' '$4 == "hello.txt" { print $2 }' "$older/MANIFEST.csv")"
            [ -f "$older/$obj" ] || { echo "$mode: no object '$obj' in the older snapshot"; false; }
            mv -- "$older/$obj" "$newer/$obj"
            blank_datapaths "$older/MANIFEST.csv"

            run bash "$RS" --target-root "$BATS_TEST_TMPDIR/t-$name-$mode" --from "$older"
            [ "$status" -eq 0 ] || { echo "$mode '$name': expected 0, got $status"; echo "$output"; false; }
            run verify_tree "$BATS_TEST_TMPDIR/t-$name-$mode" "$FIXTURES/bash-restore/$mode/expected/Snapshot_2024_01_01_09_00_00.tsv"
            [ "$status" -eq 0 ] || { echo "$mode '$name': $output"; false; }
            grep -qF "resolved by name index to '$newer/$obj'" "$BATS_TEST_TMPDIR/t-$name-$mode/RECONSTRUCT.log" \
                || { echo "$mode '$name':"; cat "$BATS_TEST_TMPDIR/t-$name-$mode/RECONSTRUCT.log"; false; }
        done
    done
}

@test "the change-folder search sees a dot-named change folder (plan C32)" {
    local mode obj snap
    for mode in "${MODES[@]}"; do
        copy_store "$mode"
        mv -- "$CH" "$BK/.changes"
        snap="$BK/.changes/Snapshot_2024_01_01_09_00_00"
        obj="$(gawk -F'"' 'NR > 1 && $2 != "" { print $2; exit }' "$BK/MANIFEST.csv")"
        mv -- "$BK/$obj" "$snap/$obj"

        run bash "$RS" --target-root "$BATS_TEST_TMPDIR/td-$mode" --from "$BK"
        [ "$status" -eq 0 ] || { echo "$mode: expected 0, got $status"; echo "$output"; false; }
        run verify_tree "$BATS_TEST_TMPDIR/td-$mode" "$FIXTURES/bash-restore/$mode/expected/root.tsv"
        [ "$status" -eq 0 ] || { echo "$mode: $output"; false; }
    done
}
