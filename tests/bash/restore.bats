#!/usr/bin/env bats
# TC-054 / SR-031 — a PowerShell-produced fixture store restores byte-for-byte
# on Linux via reconstruct.sh, from the store's CurrentBackup folder and from EVERY
# BackupHistory/<date> folder, in both compression combos (storage is always
# content-addressed since WP9 step 5 deleted Mirror; TC-134 regenerated these
# fixtures). The per-origin expected TSVs (posixRelPath -> content hash, read
# from each origin's own manifest) are the oracle: a restored file's xxh128sum
# must equal it.
#
# Kit revision 15 (plan C44, S3): one store folder per backup set. The store is
# the origin's parent, so the origin must be a folder named exactly 'CurrentBackup' or
# matching ^BackupHistory/<date>; anything else is refused with 2 unless
# --store-root names the store. No path sidecar is read and nothing is guessed.

setup() { load helpers; }

# Restore every origin of a mode with NO store flag: the store is found as the
# origin's parent folder, nothing else.
restore_mode_from_origin() {
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

# copy_store <mode> <dest> : a writable copy of a shipped fixture store.
copy_store() {
    mkdir -p -- "$(dirname -- "$2")"
    cp -r "$(store_for "$1")" "$2"
}

@test "HashAddressed: CurrentBackup + every snapshot restore byte-exact (TC-054, SR-031)" {
    restore_mode_from_origin HashAddressed
}

@test "HashAddressed+Compress: CurrentBackup + every snapshot restore byte-exact (TC-054, SR-031)" {
    restore_mode_from_origin HashAddressed_Compress
}

@test "the fixture store has the kit revision 15 layout: CurrentBackup sharded, snapshots flat, no path sidecar (TC-054, L8)" {
    # Pins what the restores above run against, so a fixture regenerated from
    # an engine that writes another layout fails here by name.
    local mode store f base shard n=0
    for mode in "${MODES[@]}"; do
        store="$(store_for "$mode")"
        [ -f "$store/CurrentBackup/MANIFEST.csv" ]
        [ -z "$(find "$store" -name 'RECONSTRUCT.paths.json')" ]
        [ ! -e "$store/MANIFEST.csv" ]
        # Every object of CurrentBackup sits in its own shard folder...
        while IFS= read -r -d '' f; do
            base="${f##*/}"; shard="$(basename -- "$(dirname -- "$f")")"
            [ "$shard" = "$(shard_of "$base")" ] || { echo "$mode: '$f' is not in its shard folder"; false; }
            n=$((n+1))
        done < <(find "$store/CurrentBackup" -mindepth 2 -maxdepth 2 -type f -print0)
        # ...and no object sits at CurrentBackup's top level.
        [ -z "$(find "$store/CurrentBackup" -mindepth 1 -maxdepth 1 -type f ! -name 'MANIFEST.csv*' ! -name 'DIRECTORIES.csv' ! -name 'FileBackupState.json')" ]
        # Snapshots stay flat.
        [ -z "$(find "$store"/BackupHistory/2* -mindepth 1 -type d)" ]
    done
    [ "$n" -ge 20 ]
}

@test "--store-root restores CurrentBackup from OUTSIDE the store, with no --from (TC-054, SR-031, kit revision 15)" {
    local out="$BATS_TEST_TMPDIR/sr-latest" elsewhere="$BATS_TEST_TMPDIR/elsewhere"
    mkdir -p "$elsewhere"
    # The working directory is NOT inside the store: without --store-root this
    # origin ($PWD) would be refused.
    run bash -c 'cd "$1" && bash "$2" --target-root "$3" --store-root "$4"' _ \
        "$elsewhere" "$RS" "$out" "$(store_for HashAddressed)"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    verify_tree "$out" "$FIXTURES/bash-restore/HashAddressed/expected/root.tsv"
}

@test "--store-root with --from a snapshot restores that snapshot byte-exact (TC-054, SR-031, kit revision 15)" {
    local store snap out="$BATS_TEST_TMPDIR/sr-snap"
    store="$(store_for HashAddressed)"
    snap="$store/BackupHistory/2024_01_01_09_00_00"
    run bash "$RS" --target-root "$out" --from "$snap" --store-root "$store"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    verify_tree "$out" "$FIXTURES/bash-restore/HashAddressed/expected/2024_01_01_09_00_00.tsv"
}

@test "--store-root names a store whose CurrentBackup a renamed origin cannot (TC-054, kit revision 15)" {
    # A copy of CurrentBackup under another name is refused on its own (below); the
    # one store override is what makes it restorable, with the pool taken from
    # the store named.
    local w="$BATS_TEST_TMPDIR/renamed"
    copy_store HashAddressed "$w/store"
    cp -r "$w/store/CurrentBackup" "$w/latest-copy"
    run bash "$RS" --target-root "$w/out" --from "$w/latest-copy" --store-root "$w/store"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    verify_tree "$w/out" "$FIXTURES/bash-restore/HashAddressed/expected/root.tsv"
}

@test "2: an origin that is neither CurrentBackup nor a BackupHistory/<date> folder is refused, writing nothing (SR-040, kit revision 15)" {
    local w="$BATS_TEST_TMPDIR/badorigin" o
    copy_store HashAddressed "$w/store"
    # The old backup-root shape (a manifest in a folder of another name), the
    # store folder itself, a case variant of CurrentBackup, and a near-miss snapshot
    # name. Each holds a real manifest except the store, so the refusal is the
    # NAME rule and not a missing manifest.
    cp -r "$w/store/CurrentBackup" "$w/backup"
    cp -r "$w/store/CurrentBackup" "$w/currentbackup"
    cp -r "$w/store/CurrentBackup" "$w/CURRENTBACKUP"
    cp -r "$w/store/CurrentBackup" "$w/Latest"
    cp -r "$w/store/BackupHistory/2024_01_01_09_00_00" "$w/Snapshot-2024_01_01_09_00_00"
    # With no prefix a date proves nothing: a dated folder is a snapshot only
    # inside BackupHistory, and an old Snapshot_<date> name is none at all (S12, S13).
    cp -r "$w/store/BackupHistory/2024_01_01_09_00_00" "$w/2024_01_01_09_00_00"
    cp -r "$w/store/BackupHistory/2024_01_01_09_00_00" "$w/Snapshot_2024_01_01_09_00_00"
    for o in "$w/backup" "$w/store" "$w/currentbackup" "$w/CURRENTBACKUP" "$w/Latest" "$w/Snapshot-2024_01_01_09_00_00" \
             "$w/2024_01_01_09_00_00" "$w/Snapshot_2024_01_01_09_00_00"; do
        run bash "$RS" --target-root "$w/t-${o##*/}" --from "$o"
        [ "$status" -eq 2 ] || { echo "'$o': expected 2, got $status"; echo "$output"; false; }
        [[ "$output" == *"neither a store's CurrentBackup folder nor a dated folder in its BackupHistory folder"* ]] \
            || { echo "'$o':"; echo "$output"; false; }
        [ ! -e "$w/t-${o##*/}" ]
    done
}

@test "CurrentBackup still restores when BackupHistory is missing (plan S15)" {
    local w="$BATS_TEST_TMPDIR/no-history"
    copy_store HashAddressed "$w/store"
    rm -rf "$w/store/BackupHistory"
    run bash "$RS" --target-root "$w/out" --from "$w/store/CurrentBackup"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    verify_tree "$w/out" "$FIXTURES/bash-restore/HashAddressed/expected/root.tsv"
}

@test "2: the default origin is the working directory, refused when it is not CurrentBackup or a snapshot (SR-040, kit revision 15)" {
    local w="$BATS_TEST_TMPDIR/pwd-origin"
    copy_store HashAddressed "$w/store"
    run bash -c 'cd "$1" && bash "$2" --target-root "$3"' _ "$w/store" "$RS" "$w/t-store"
    [ "$status" -eq 2 ]
    [[ "$output" == *"--store-root"* ]]
    # From inside CurrentBackup the same command line restores.
    run bash -c 'cd "$1" && bash "$2" --target-root "$3"' _ "$w/store/CurrentBackup" "$RS" "$w/t-latest"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    verify_tree "$w/t-latest" "$FIXTURES/bash-restore/HashAddressed/expected/root.tsv"
}

@test "the retired --backup-root / --change-root are unknown arguments: usage and exit 2 (SR-040, kit revision 15)" {
    local origin; origin="$(origin_for HashAddressed root)"
    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/t-br" --from "$origin" --backup-root "$origin"
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown argument: --backup-root"* ]]
    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/t-cr" --from "$origin" --change-root "$(store_for HashAddressed)"
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown argument: --change-root"* ]]
    [ ! -e "$BATS_TEST_TMPDIR/t-br" ] && [ ! -e "$BATS_TEST_TMPDIR/t-cr" ]
}

@test "a MOVED store restores from where it is now, every origin byte-exact (SR-031, kit revision 15)" {
    # Nothing records where a store was: a copy restores from its own folders
    # even while the original still exists, and a stale path sidecar of the
    # old kits is not read. Its paths point at the ORIGINAL store, which would
    # restore just as well - so the log line naming the store is the proof.
    local mode w store tsv name out origin
    for mode in "${MODES[@]}"; do
        w="$BATS_TEST_TMPDIR/moved-$mode"
        store="$w/new home/Backups & Archive #2"
        copy_store "$mode" "$store"
        printf '{\n  "BackupRoot": "%s",\n  "ChangeRoot": "%s"\n}\n' \
            "$(store_for "$mode")/CurrentBackup" "$(store_for "$mode")" > "$store/CurrentBackup/RECONSTRUCT.paths.json"
        store="$(cd "$store" && pwd -P)"
        for tsv in "$FIXTURES/bash-restore/$mode"/expected/*.tsv; do
            name="$(basename "$tsv" .tsv)"
            if [[ "$name" == root ]]; then name=CurrentBackup; origin="$store/$name"
            else origin="$store/BackupHistory/$name"; fi
            out="$w/t-$name"
            run bash "$RS" --target-root "$out" --from "$origin"
            [ "$status" -eq 0 ] || { echo "$mode/$name: expected 0, got $status"; echo "$output"; false; }
            verify_tree "$out" "$tsv" || { echo "$mode/$name: verify failed"; false; }
            grep -qF "store=$store)" "$out/RECONSTRUCT.log" || { echo "$mode/$name:"; cat "$out/RECONSTRUCT.log"; false; }
        done
    done
}

@test "the kit reads no path sidecar at all (kit revision 15)" {
    # A structural pin: the sidecar and the root guessing are gone together.
    # (DIR_SIDECAR_NAME is DIRECTORIES.csv, SR-065, and stays.)
    [ "$(grep -cE '(^|[^_[:alnum:]])SIDECAR_NAME|paths\.json' "$RS")" -eq 0 ]
    [ "$(grep -cE 'side_backup|side_change|auto_backup|auto_change' "$RS")" -eq 0 ]
}

@test "a NESTED infra-named pool file is scanned by hash recovery (root-level-only skip) (B6, SR-022/SR-031)" {
    # Regression B6 + the contract's root-level-only infra skip: the original
    # 2026-07 defect was reconstruct.sh applying the skip RECURSIVELY. The
    # engine no longer produces nested pool files (objects sit in their shard
    # folders), so the legacy shape is CONSTRUCTED — the restorer deliberately
    # still serves legacy stores: sub/MANIFEST.csv's OBJECT is moved to the
    # nested infra name; its row's named file is then missing, forcing hash
    # recovery, which must scan past CurrentBackup/sub/MANIFEST.csv rather than skip
    # it. The PS twin is TC-058 (same constructed shape since WP9 step 5).
    local store="$BATS_TEST_TMPDIR/b6-legacy/store"
    copy_store HashAddressed "$store"
    local bk="$store/CurrentBackup"
    local want obj
    want="$(expected_hash HashAddressed 'sub/MANIFEST.csv')"
    [ -n "$want" ]
    obj="$(pool_file_by_hash "$bk" "$want")"
    [ -n "$obj" ]
    mkdir -p "$bk/sub"
    mv -- "$obj" "$bk/sub/MANIFEST.csv"

    local out="$BATS_TEST_TMPDIR/b6"
    run bash "$RS" --target-root "$out" --from "$bk"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    [ -f "$out/sub/MANIFEST.csv" ]
    [ "$(cat "$out/sub/MANIFEST.csv")" = "nested not-infra" ]
}

@test "refuses a target inside the store, its CurrentBackup or a snapshot (SR-009)" {
    local store; store="$(store_for HashAddressed)"
    local t
    for t in "$store/restore-here" "$store/CurrentBackup/restore-here" "$store/BackupHistory/2024_01_01_09_00_00/restore-here"; do
        run bash "$RS" --target-root "$t" --from "$store/CurrentBackup"
        [ "$status" -eq 2 ] || { echo "'$t': expected 2, got $status"; false; }
        [[ "$output" == *"inside the store"* ]]
        [ ! -e "$t" ]
    done
}

@test "reconstruct.sh scans the pool with plain 'find ... -type f', never -L: symlink immunity is INTENT (TC-134)" {
    # Source-text pin (the bash sibling of the repo's AST guards): every find
    # in the restorer must walk real files only — following symlinks would let
    # a link inside a store smuggle bytes from outside the pool into recovery.
    run grep -nE '(^|[^[:alnum:]])find[[:space:]]+(-L|-H)' "$RS"
    [ "$status" -ne 0 ]
    run grep -cE 'find "[^"]+" .*-type f' "$RS"
    [ "$output" -ge 2 ]
}

@test "a target inside the origin is refused even when --store-root names another store (SR-009, kit revision 15)" {
    local a="$BATS_TEST_TMPDIR/A" b="$BATS_TEST_TMPDIR/B"
    cp -R "$(store_for HashAddressed)" "$a"
    cp -R "$(store_for HashAddressed)" "$b"
    run bash "$RS" --target-root "$a/CurrentBackup/inside" --from "$a/CurrentBackup" --store-root "$b"
    [ "$status" -eq 2 ]
    [[ "$output" == *"inside the restore origin"* ]]
    [ ! -e "$a/CurrentBackup/inside" ]
}
