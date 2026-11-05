#!/usr/bin/env bats
# Kit revision 14 — reconstruct.sh resolves a blank or stale DataPath through a
# NAME INDEX built once per restore, and falls back to find_by_hash (the
# content scan) only when the index has no usable candidate (bounded-run-loop
# section 7). The bats twin of tests/Unit/RestoreIndex.Tests.ps1. The base-57
# decoder itself is held to the PowerShell oracle in name_grammar.bats.
#
# Kit revision 15 (plan C44): one store folder per backup set. The index lists
# CurrentBackup through its shard folders (<CurrentBackup>/<xx>/<name>, L8) and each
# BackupHistory/<date> flat; the store is the origin's parent, never guessed.

setup() {
    load helpers
}

# copy_store <mode> : a writable copy of a shipped fixture store; sets
# STORE (the store), BK (its CurrentBackup folder) and CH (the folder holding the
# snapshots, which is the store itself).
copy_store() {
    STORE="$BATS_TEST_TMPDIR/store-$1"
    cp -r "$(store_for "$1")" "$STORE"
    BK="$STORE/CurrentBackup"
    CH="$STORE"
}

# lobj <name> : where object <name> sits in the copied store's CurrentBackup (L8).
lobj() { printf '%s' "$BK/$(shard_of "$1")/$1"; }

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
        snap="$CH/BackupHistory/2024_01_01_09_00_00"
        # The worst case the field sees (about 96% of real snapshot rows are
        # blank): EVERY DataPath blank, including the two whose objects live
        # in the snapshot itself, so bytes come from the origin AND from latest.
        blank_datapaths "$snap/MANIFEST.csv"
        rows="$(data_rows "$snap/MANIFEST.csv")"

        run bash "$RS" --target-root "$BATS_TEST_TMPDIR/t-$mode" --from "$snap"
        [ "$status" -eq 0 ] || { echo "$mode: expected 0, got $status"; echo "$output"; false; }
        run verify_tree "$BATS_TEST_TMPDIR/t-$mode" "$FIXTURES/bash-restore/$mode/expected/2024_01_01_09_00_00.tsv"
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

@test "the index prefers the origin's own copy, then latest's shard folders (kit revision 14, 15)" {
    copy_store HashAddressed
    local snap="$CH/BackupHistory/2024_01_01_09_00_00" obj readme
    # The snapshot's own superseded hello.txt object must be the one used, and
    # an object that exists only in latest must come from latest.
    obj="$(gawk -F'"' '$4 == "hello.txt" { print $2 }' "$snap/MANIFEST.csv")"
    readme="$(gawk -F'"' '$4 == "README" { print $2 }' "$BK/MANIFEST.csv")"
    [ -f "$snap/$obj" ]
    blank_datapaths "$snap/MANIFEST.csv"
    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/tpref" --from "$snap"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    grep -qF "No DataPath for 'hello.txt'; resolved by name index to '$snap/$obj'" "$BATS_TEST_TMPDIR/tpref/RECONSTRUCT.log"
    grep -qF "No DataPath for 'README'; resolved by name index to '$(lobj "$readme")'" "$BATS_TEST_TMPDIR/tpref/RECONSTRUCT.log"
}

@test "a DataPath whose object moved to another pool folder resolves through the index (kit revision 14, R6)" {
    copy_store HashAddressed
    local obj
    # CurrentBackup's hello.txt object moves into a snapshot: the row still names it
    # in latest, which is the shape a write-once manifest goes stale with.
    obj="$(gawk -F'"' '$4 == "hello.txt" { print $2 }' "$BK/MANIFEST.csv")"
    [ -f "$(lobj "$obj")" ]
    mv "$(lobj "$obj")" "$CH/BackupHistory/2024_01_02_09_00_00/$obj"

    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/tmoved" --from "$BK"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    run verify_tree "$BATS_TEST_TMPDIR/tmoved" "$FIXTURES/bash-restore/HashAddressed/expected/root.tsv"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    grep -qF "missing for 'hello.txt'; resolved by name index to '$CH/BackupHistory/2024_01_02_09_00_00/$obj'" "$BATS_TEST_TMPDIR/tmoved/RECONSTRUCT.log"
    [ "$(grep -c 'attempting hash scan' "$BATS_TEST_TMPDIR/tmoved/RECONSTRUCT.log")" -eq 0 ]
}

@test "the content scan runs only when the index has no usable candidate (kit revision 14, call C5)" {
    copy_store HashAddressed
    local obj
    # The bytes survive under a name that is not an object name, so the index
    # cannot see them and the last-resort scan must.
    obj="$(gawk -F'"' '$4 == "hello.txt" { print $2 }' "$BK/MANIFEST.csv")"
    mv "$(lobj "$obj")" "$BK/renamed-by-hand.bin"

    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/tscan" --from "$BK"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    run verify_tree "$BATS_TEST_TMPDIR/tscan" "$FIXTURES/bash-restore/HashAddressed/expected/root.tsv"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    grep -q "missing for 'hello.txt'; attempting hash scan" "$BATS_TEST_TMPDIR/tscan/RECONSTRUCT.log"
    grep -q "Hash-recovered 'hello.txt' from '.*renamed-by-hand.bin'" "$BATS_TEST_TMPDIR/tscan/RECONSTRUCT.log"
}

@test "an object in the WRONG place in CurrentBackup is not found by the name index, only by the content scan (kit revision 15, L8)" {
    # A file in CurrentBackup is an object only in its own shard folder: at CurrentBackup's
    # top level, in another name's shard folder, or in an uppercase spelling
    # of its own (a distinct folder here, one folder on Windows) no path leads
    # to it. The index must not offer it; the content scan, which reads bytes,
    # still recovers it, so nothing is lost while the store is misfiled.
    local obj shard where i=0 t log
    copy_store HashAddressed
    obj="$(gawk -F'"' '$4 == "hello.txt" { print $2 }' "$BK/MANIFEST.csv")"
    shard="$(shard_of "$obj")"
    [ "$shard" != zz ]
    for where in "$BK" "$BK/zz" "$BK/${shard^^}"; do
        i=$((i+1)); t="$BATS_TEST_TMPDIR/twrong-$i"
        rm -rf "$STORE"; copy_store HashAddressed
        mkdir -p "$where"
        mv "$(lobj "$obj")" "$where/$obj"

        run bash "$RS" --target-root "$t" --from "$BK"
        [ "$status" -eq 0 ] || { echo "'$where': expected 0, got $status"; echo "$output"; false; }
        run verify_tree "$t" "$FIXTURES/bash-restore/HashAddressed/expected/root.tsv"
        [ "$status" -eq 0 ] || { echo "'$where': $output"; false; }
        log="$t/RECONSTRUCT.log"
        grep -q 'Name index built' "$log" || { echo "'$where':"; cat "$log"; false; }
        [ "$(grep -c "resolved by name index" "$log")" -eq 0 ] || { echo "'$where': the index offered a misplaced object"; cat "$log"; false; }
        grep -qF "missing for 'hello.txt'; attempting hash scan" "$log"
        grep -qF "Hash-recovered 'hello.txt' from '$where/$obj'" "$log" || { echo "'$where':"; cat "$log"; false; }
    done
}

@test "an index hit is treated like a DataPath file: wrong bytes under the right name are verified and healed (SR-056)" {
    copy_store HashAddressed
    local obj
    obj="$(gawk -F'"' '$4 == "hello.txt" { print $2 }' "$BK/MANIFEST.csv")"
    # A good copy survives under a non-object name; the object the index picks
    # carries same-length WRONG bytes, and every row is blank.
    cp "$(lobj "$obj")" "$BK/spare.bin"
    printf 'X%.0s' $(seq 1 "$(stat -c '%s' "$(lobj "$obj")")") > "$(lobj "$obj")"
    blank_datapaths "$BK/MANIFEST.csv"

    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/theal" --from "$BK"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    run verify_tree "$BATS_TEST_TMPDIR/theal" "$FIXTURES/bash-restore/HashAddressed/expected/root.tsv"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    grep -q "No DataPath for 'hello.txt'; resolved by name index" "$BATS_TEST_TMPDIR/theal/RECONSTRUCT.log"
    grep -q 'ContentMismatch' "$BATS_TEST_TMPDIR/theal/RECONSTRUCT.log"
    grep -q 'after a verify mismatch' "$BATS_TEST_TMPDIR/theal/RECONSTRUCT.log"
}

@test "a restore whose every DataPath resolves in its shard folder never builds the index (kit revision 14, 15)" {
    copy_store HashAddressed
    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/tnoindex" --from "$BK"
    [ "$status" -eq 0 ]
    [ "$(grep -c 'Name index built' "$BATS_TEST_TMPDIR/tnoindex/RECONSTRUCT.log")" -eq 0 ]
}

@test "a snapshot of a COPIED store resolves every blank row inside the copy, with no flags (kit revision 15, S3)" {
    # Replaces the one-mount sibling guess (plan R8): the store is the
    # snapshot's parent wherever it now lives, so a copy restores from its own
    # CurrentBackup and snapshots, never the original's.
    local mode store snap log rows
    for mode in "${MODES[@]}"; do
        store="$BATS_TEST_TMPDIR/copied-$mode/some where/My Store"
        mkdir -p "$(dirname -- "$store")"
        cp -r "$(store_for "$mode")" "$store"
        store="$(cd "$store" && pwd -P)"
        snap="$store/BackupHistory/2024_01_01_09_00_00"
        blank_datapaths "$snap/MANIFEST.csv"
        rows="$(data_rows "$snap/MANIFEST.csv")"

        run bash "$RS" --target-root "$BATS_TEST_TMPDIR/t1-$mode" --from "$snap"
        [ "$status" -eq 0 ] || { echo "$mode: expected 0, got $status"; echo "$output"; false; }
        run verify_tree "$BATS_TEST_TMPDIR/t1-$mode" "$FIXTURES/bash-restore/$mode/expected/2024_01_01_09_00_00.tsv"
        [ "$status" -eq 0 ] || { echo "$mode: $output"; false; }
        log="$BATS_TEST_TMPDIR/t1-$mode/RECONSTRUCT.log"
        [ "$(grep -c "resolved by name index to '$store/" "$log")" -eq "$rows" ] || { echo "$mode:"; cat "$log"; false; }
        [ "$(grep -c 'attempting hash scan' "$log")" -eq 0 ]
    done
}

@test "a latest-state restore finds a row whose object is still in a snapshot of its store (plan C19, kit revision 15)" {
    # A move back that failed leaves a latest row naming an object inside a
    # snapshot. Until kit revision 15 the change folder was guessed (plan
    # C32); now it is the store, CurrentBackup's parent, and nothing is guessed.
    local mode obj snap
    for mode in "${MODES[@]}"; do
        copy_store "$mode"
        snap="$CH/BackupHistory/2024_01_01_09_00_00"
        obj="$(gawk -F'"' 'NR > 1 && $2 != "" { print $2; exit }' "$BK/MANIFEST.csv")"
        [ -f "$(lobj "$obj")" ] || { echo "$mode: no latest object '$obj'"; false; }
        mv -- "$(lobj "$obj")" "$snap/$obj"

        run bash "$RS" --target-root "$BATS_TEST_TMPDIR/tl-$mode" --from "$BK"
        [ "$status" -eq 0 ] || { echo "$mode: expected 0, got $status"; echo "$output"; false; }
        run verify_tree "$BATS_TEST_TMPDIR/tl-$mode" "$FIXTURES/bash-restore/$mode/expected/root.tsv"
        [ "$status" -eq 0 ] || { echo "$mode: $output"; false; }
        grep -qF "resolved by name index to '$snap/$obj'" "$BATS_TEST_TMPDIR/tl-$mode/RECONSTRUCT.log"
    done
}

@test "skips a prune staged copy in the name index, whatever its case (review 2026-10-26 A3)" {
    # Copy-ReHomedDataFile stages '<object>.fbprune.tmp' beside the
    # destination; a prune killed mid-copy leaves a truncated one there. Its
    # name still decodes (the extension is opaque), so the origin's residue was
    # the key's first candidate, the partial archive failed to expand, and the
    # restore exited 4 with the intact original in latest.
    copy_store HashAddressed_Compress
    local snap="$CH/BackupHistory/2024_01_01_09_00_00" o1 o2 log
    o1="$(gawk -F'"' '$4 == "README" { print $2 }' "$BK/MANIFEST.csv")"
    o2="$(gawk -F'"' '$4 == "[b] (p).txt" { print $2 }' "$BK/MANIFEST.csv")"
    [[ "$o1" == *.7z && "$o2" == *.7z ]] || { echo "objects must be archives: '$o1' '$o2'"; false; }
    head -c "$(( $(stat -c '%s' "$(lobj "$o1")") / 2 ))" "$(lobj "$o1")" > "$snap/$o1.fbprune.tmp"
    head -c "$(( $(stat -c '%s' "$(lobj "$o2")") / 2 ))" "$(lobj "$o2")" > "$snap/$o2.FBPrune.TMP"

    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/tstaged" --from "$snap"
    [ "$status" -eq 0 ] || { echo "expected 0, got $status"; echo "$output"; false; }
    run verify_tree "$BATS_TEST_TMPDIR/tstaged" "$FIXTURES/bash-restore/HashAddressed_Compress/expected/2024_01_01_09_00_00.tsv"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    log="$BATS_TEST_TMPDIR/tstaged/RECONSTRUCT.log"
    grep -qF "for 'README'; resolved by name index to '$(lobj "$o1")'" "$log"
    grep -qF "for '[b] (p).txt'; resolved by name index to '$(lobj "$o2")'" "$log"
    [ "$(grep -ci 'fbprune' "$log")" -eq 0 ]
    # Skipped, never deleted: the suffix alone proves nothing (AGENTS.md section 3).
    [ -f "$snap/$o1.fbprune.tmp" ] && [ -f "$snap/$o2.FBPrune.TMP" ]
}

@test "a store whose path holds '&' or '#' keeps every sibling snapshot in the pool (review 2026-10-26 A2)" {
    # The snapshot list was prefixed with sed "s#^#$change_root/#": '&' put the
    # match into the path and '#' ended the command, so every sibling snapshot
    # dropped out of the pool. Restoring an older snapshot normally needs an
    # object a newer one holds (C23), and it reported content missing (exit 1)
    # or an unreadable pool (exit 4). The store folder is now the change root
    # (kit revision 15), so its own name is what the path is joined to.
    local mode name store older newer obj
    for mode in "${MODES[@]}"; do
        for name in 'Backups & Archive' 'Backup #2'; do
            store="$BATS_TEST_TMPDIR/$name-$mode"
            cp -r "$(store_for "$mode")" "$store"
            older="$store/BackupHistory/2024_01_01_09_00_00"
            newer="$store/BackupHistory/2024_01_02_09_00_00"
            obj="$(gawk -F'"' '$4 == "hello.txt" { print $2 }' "$older/MANIFEST.csv")"
            [ -f "$older/$obj" ] || { echo "$mode: no object '$obj' in the older snapshot"; false; }
            mv -- "$older/$obj" "$newer/$obj"
            blank_datapaths "$older/MANIFEST.csv"

            run bash "$RS" --target-root "$BATS_TEST_TMPDIR/t-$name-$mode" --from "$older"
            [ "$status" -eq 0 ] || { echo "$mode '$name': expected 0, got $status"; echo "$output"; false; }
            run verify_tree "$BATS_TEST_TMPDIR/t-$name-$mode" "$FIXTURES/bash-restore/$mode/expected/2024_01_01_09_00_00.tsv"
            [ "$status" -eq 0 ] || { echo "$mode '$name': $output"; false; }
            grep -qF "resolved by name index to '$newer/$obj'" "$BATS_TEST_TMPDIR/t-$name-$mode/RECONSTRUCT.log" \
                || { echo "$mode '$name':"; cat "$BATS_TEST_TMPDIR/t-$name-$mode/RECONSTRUCT.log"; false; }
        done
    done
}

@test "a dot-named store keeps its snapshots in the pool (SR-057, plan C32 successor)" {
    # The change-folder guess had to see a dot-named folder ('.changes'). The
    # store is now named by the origin, so a dot-named STORE is the remaining
    # shape: its snapshots must still be listed and its CurrentBackup still sharded.
    local mode store obj snap
    for mode in "${MODES[@]}"; do
        store="$BATS_TEST_TMPDIR/dot-$mode/.store"
        mkdir -p "$(dirname -- "$store")"
        cp -r "$(store_for "$mode")" "$store"
        BK="$store/CurrentBackup"
        snap="$store/BackupHistory/2024_01_01_09_00_00"
        obj="$(gawk -F'"' 'NR > 1 && $2 != "" { print $2; exit }' "$BK/MANIFEST.csv")"
        mv -- "$(lobj "$obj")" "$snap/$obj"

        run bash "$RS" --target-root "$BATS_TEST_TMPDIR/td-$mode" --from "$BK"
        [ "$status" -eq 0 ] || { echo "$mode: expected 0, got $status"; echo "$output"; false; }
        run verify_tree "$BATS_TEST_TMPDIR/td-$mode" "$FIXTURES/bash-restore/$mode/expected/root.tsv"
        [ "$status" -eq 0 ] || { echo "$mode: $output"; false; }
    done
}
