#!/usr/bin/env bats
# TC-109 / SR-056 — reconstruct.sh verifies every byte it writes against the
# row's (Length, xxH2Hash), heals a mismatch from the pool once, and fails
# loudly as content damage when nothing reproduces the row (TC-108 is the
# PowerShell twin). Before kit revision 6 a resolvable DataPath was trusted:
# wrong payload, a same-length bit-flip, even truncation restored with exit 0.

setup() {
    load helpers
}

restamp_witness() {
    local manifest="$1" witness="${1}.meta" rows bytes hash
    rows="$(gawk 'NR>1 && NF>0' "$manifest" | wc -l | tr -d ' ')"
    bytes="$(stat -c '%s' -- "$manifest")"
    hash="$(xxh128sum -- "$manifest" | awk '{print $1}' | tr 'a-f' 'A-F')"
    printf 'Version=1\nRows=%s\nBytes=%s\nXxH128=%s\nWritten=%s\n' \
        "$rows" "$bytes" "$hash" "$(date --iso-8601=seconds)" > "$witness"
}

# one_row_store <dir> <payload> : a store whose single row names its own data
# file "data.bin"; echoes nothing, sets STORE_HASH/STORE_LEN.
one_row_store() {
    local dir="$1" payload="$2"
    mkdir -p "$dir"
    printf '%s' "$payload" > "$dir/data.bin"
    STORE_HASH="$(hash_upper "$dir/data.bin")"
    STORE_LEN="$(stat -c '%s' "$dir/data.bin")"
    {
      printf '"DataPath","RelativePath","Length","LastWriteTimeStr","xxH2Hash","Compressed","StoredAsHashSize","Duplicate","MediaMBPerSec"\r\n'
      printf '"data.bin","restored.txt","%s","d","%s","No","Original","0",""\r\n' "$STORE_LEN" "$STORE_HASH"
    } > "$dir/MANIFEST.csv"
    restamp_witness "$dir/MANIFEST.csv"
}

@test "0: a wrong-payload data file is healed from a surviving pool copy, warning logged (SR-056 / TC-109)" {
    local s="$BATS_TEST_TMPDIR/heal"
    one_row_store "$s" 'GOOD-PAYLOAD-BYTES'
    cp "$s/data.bin" "$s/spare.bin"                       # good copy survives in the pool
    printf 'WRNG-PAYLOAD-BYTES' > "$s/data.bin"           # same length, wrong bytes

    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/theal" --from "$s"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ContentMismatch"* ]]
    [[ "$output" == *"after a verify mismatch"* ]]
    printf 'GOOD-PAYLOAD-BYTES' | diff - "$BATS_TEST_TMPDIR/theal/restored.txt"
}

@test "1: a same-length bit-flip with no surviving copy fails loudly, bad bytes deleted (SR-056 / TC-109)" {
    local s="$BATS_TEST_TMPDIR/flip"
    one_row_store "$s" 'GOOD-PAYLOAD-BYTES'
    printf 'GOOD-PAYLOAD-BYTEX' > "$s/data.bin"

    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/tflip" --from "$s"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ContentMismatch"* ]]
    [[ "$output" == *"content-missing"* ]]
    [ ! -e "$BATS_TEST_TMPDIR/tflip/restored.txt" ]
}

@test "1: truncation is caught by the length check before any hashing (SR-056 / TC-109)" {
    local s="$BATS_TEST_TMPDIR/trunc"
    one_row_store "$s" 'GOOD-PAYLOAD-BYTES'
    printf 'GOOD' > "$s/data.bin"

    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/ttrunc" --from "$s"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ContentMismatch"* ]]
    [[ "$output" == *"(not hashed)/4"* ]]
}

@test "4: a 7z that cannot run is a HOST problem, never lost content (SR-040, kit rev 6 review fix)" {
    # A working 7z on the same store proves the bytes are fine, so a failing
    # one must exit 4 (self-test separates broken-host from damaged-archive).
    local s="$BATS_TEST_TMPDIR/broken7z"
    one_row_store "$s" 'PAYLOAD-FOR-BROKEN7Z'
    rm -f "$s/data.bin"
    sed -i 's/^"data.bin"/""/' "$s/MANIFEST.csv"
    restamp_witness "$s/MANIFEST.csv"
    printf 'garbage-not-archive' > "$s/noise.7z"
    printf '#!/bin/sh\nexit 2\n' > "$BATS_TEST_TMPDIR/fake7z"
    chmod +x "$BATS_TEST_TMPDIR/fake7z"

    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/tb7z" --from "$s" --seven-zip "$BATS_TEST_TMPDIR/fake7z"
    [ "$status" -eq 4 ]
    [[ "$output" == *"not usable on this host"* ]]
    [[ "$output" != *"ContentMissing"* ]]
}

@test "restore_one: a read-back failure is HOST class (rc=22) and KEEPS the file (SR-056, review major 4)" {
    # White-box: source the script (main guard keeps it inert), then break
    # hash_file — the verify read-back must not report data loss or delete
    # the restored file (that is Reconstruct.ps1's behavior too).
    source "$RS"
    hash_file() { return 1; }
    local d="$BATS_TEST_TMPDIR/rb"
    mkdir -p "$d"
    printf 'x' > "$d/src.bin"
    local rc=0
    restore_one "$d/src.bin" "$d/dest.bin" 0 'AAAABBBBCCCCDDDDAAAABBBBCCCCDDDD' 1 || rc=$?
    [ "$rc" -eq 22 ]
    [ -f "$d/dest.bin" ]
}

@test "2: a non-numeric Length is refused as a PRECONDITION before anything is written (review minor 7)" {
    # Parity: RECONSTRUCT.ps1's casts refuse the same index shape as class 2;
    # restoring such a row unverified would silently disable SR-056 for it.
    local s="$BATS_TEST_TMPDIR/badlen"
    one_row_store "$s" 'GOOD-PAYLOAD-BYTES'
    sed -i "s/\"$STORE_LEN\"/\"abc\"/" "$s/MANIFEST.csv"
    restamp_witness "$s/MANIFEST.csv"

    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/tbadlen" --from "$s"
    [ "$status" -eq 2 ]
    [[ "$output" == *"non-numeric Length"* ]]
    [ ! -e "$BATS_TEST_TMPDIR/tbadlen/restored.txt" ]
}

@test "0: a DOT-NAMED pool file is found by hash recovery (SR-057 regression pin / TC-114 twin)" {
    # find(1) never skipped dot files, so this has always worked on Linux —
    # pinned so it stays true (the PowerShell scan needed -Force, kit rev 6).
    local s="$BATS_TEST_TMPDIR/dotpool"
    one_row_store "$s" 'DOT-POOL-PAYLOAD'
    mv "$s/data.bin" "$s/.pool-copy.bin"
    sed -i 's/^"data.bin"/""/' "$s/MANIFEST.csv"
    restamp_witness "$s/MANIFEST.csv"

    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/tdot" --from "$s"
    [ "$status" -eq 0 ]
    printf 'DOT-POOL-PAYLOAD' | diff - "$BATS_TEST_TMPDIR/tdot/restored.txt"
}

@test "0: a valid archive with the WRONG payload at the row's own DataPath is healed from a pool copy (SR-056 / TC-109)" {
    command -v 7z >/dev/null || command -v 7za >/dev/null || command -v 7zz >/dev/null || skip "7z not installed"
    local zbin; zbin="$(command -v 7z || command -v 7za || command -v 7zz)"
    local s="$BATS_TEST_TMPDIR/arch" w="$BATS_TEST_TMPDIR/work"
    mkdir -p "$s" "$w"
    printf 'ARCHIVE-GOOD-PAYLOAD' > "$w/restored.txt"
    local h len
    h="$(hash_upper "$w/restored.txt")"; len="$(stat -c '%s' "$w/restored.txt")"
    (cd "$w" && "$zbin" a -bd -y good.7z restored.txt >/dev/null)
    printf 'ARCHIVE-BAD--PAYLOAD' > "$w/restored.txt"
    (cd "$w" && "$zbin" a -bd -y bad.7z restored.txt >/dev/null)
    cp "$w/bad.7z"  "$s/data.7z"      # the row's own archive: valid, wrong payload
    cp "$w/good.7z" "$s/spare.7z"     # a good pool copy under an unrelated name
    {
      printf '"DataPath","RelativePath","Length","LastWriteTimeStr","xxH2Hash","Compressed","StoredAsHashSize","Duplicate","MediaMBPerSec"\r\n'
      printf '"data.7z","restored.txt","%s","d","%s","Yes","HashSize","0",""\r\n' "$len" "$h"
    } > "$s/MANIFEST.csv"
    restamp_witness "$s/MANIFEST.csv"

    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/tarch" --from "$s"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ContentMismatch"* ]]
    printf 'ARCHIVE-GOOD-PAYLOAD' | diff - "$BATS_TEST_TMPDIR/tarch/restored.txt"
}
