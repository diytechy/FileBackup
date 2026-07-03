#!/usr/bin/env bats
# TC-053 / SR-030 — the bash hasher (hash_file) must produce the exact
# 32-char uppercase big-endian hex that Get-FileXxHash committed as goldens.
# This de-risks the whole variant: if a digest differs, cross-implementation
# restore is silently broken.

setup() {
    load helpers
    source "$RS"                                   # source-guard => main() does not run
    HC="$FIXTURES/hash-conformance"
}

@test "hash_file equals the committed Get-FileXxHash goldens for every fixture (TC-053, SR-030)" {
    [ -f "$HC/expected-hashes.csv" ]
    local fail=0 n=0 name want got
    # expected-hashes.csv: "FileName,xxH2Hash" header + one row per file. Fixture
    # names contain no commas, so a plain split is safe here.
    while IFS=, read -r name want; do
        [[ "$name" == "FileName" ]] && continue    # header
        [[ -n "$name" ]] || continue
        n=$((n+1))
        [ -f "$HC/$name" ] || { echo "fixture missing: $name"; fail=$((fail+1)); continue; }
        got="$(hash_file "$HC/$name")"
        if [[ "$got" != "$want" ]]; then echo "MISMATCH $name: got=$got want=$want"; fail=$((fail+1)); fi
    done < "$HC/expected-hashes.csv"
    echo "checked $n fixtures"
    [ "$n" -ge 5 ]
    [ "$fail" -eq 0 ]
}

@test "hash_file handles the empty file (TC-053, SR-030)" {
    run hash_file "$HC/empty.dat"
    [ "$status" -eq 0 ]
    [ "$output" = "99AA06D3014798D86001C324468D497F" ]
}

@test "hash_file streams a >1 MiB binary correctly (multi-buffer) (TC-053, SR-030)" {
    local f="$HC/binary-1MiB.bin"
    [ -f "$f" ]
    [ "$(stat -c '%s' "$f")" -gt 1048576 ]
    # Compare hash_file against a second independent xxh128sum invocation.
    run hash_file "$f"
    [ "$status" -eq 0 ]
    [ "$output" = "$(xxh128sum -- "$f" | awk '{print $1}' | tr 'a-f' 'A-F')" ]
}
