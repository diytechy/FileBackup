#!/usr/bin/env bats
# Kit revision 14 (bounded-run-loop R5) — reconstruct.sh no longer reads the
# MANIFEST.csv.meta witness. A witness that is present, stale, garbage, from the
# future, from a pre-WP12 store, or absent changes nothing: there is no exit 3,
# no 'unverified index' warning and no --require-witness. Until revision 13
# this file (TC-069) pinned the opposite; the witness WRITER's own contract
# (SR-038) still holds for the shipped fixtures and is kept at the end.
#
# What still refuses: a file that is not a manifest at all (the header guard,
# exit 2), and the SR-061 name-grammar markers (name_grammar.bats,
# restore_fidelity.bats).

setup() {
    load helpers
    # Work on a WRITABLE copy so we can damage the witness and the manifest.
    WORK="$BATS_TEST_TMPDIR/work"
    cp -r "$FIXTURES/bash-restore/HashAddressed/backup" "$WORK"
    BK="$WORK"; CH="$WORK/changes"
    MANIFEST="$BK/MANIFEST.csv"
    WITNESS="$BK/MANIFEST.csv.meta"
    EXPECTED="$FIXTURES/bash-restore/HashAddressed/expected/root.tsv"
}

# Count files the restore actually wrote into the target. The restorer's own
# RECONSTRUCT.log does not count as a restored row.
restored_count() {
    local target="$1"
    [[ -d "$target" ]] || { echo 0; return; }
    find "$target" -type f ! -name 'RECONSTRUCT.log' | wc -l | tr -d ' '
}

# restore_ok <target> : restore the root and require exit 0, byte-exact, and no
# word about a witness anywhere in the output.
restore_ok() {
    run bash "$RS" --target-root "$1" --from "$BK" --backup-root "$BK" --change-root "$CH"
    [ "$status" -eq 0 ] || { echo "expected 0, got $status"; echo "$output"; return 1; }
    [[ "$output" != *[Ww]itness* ]] || { echo "the witness was consulted:"; echo "$output"; return 1; }
    run verify_tree "$1" "$EXPECTED"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "a witness that DISAGREES with its manifest no longer refuses: exit 0, not 3 (kit revision 14, R5)" {
    # Edit the manifest WITHOUT re-stamping: blank every DataPath, so the
    # bytes, the digest and the row text all disagree with the witness. Until
    # revision 13 this was exit 3 and nothing was written.
    gawk -v FPAT='("([^"]|"")*")|([^,]*)' -v OFS=',' \
        'NR==1 { print; next } { $1="\"\""; print }' "$MANIFEST" > "$MANIFEST.tmp"
    mv "$MANIFEST.tmp" "$MANIFEST"
    restore_ok "$BATS_TEST_TMPDIR/stale"
}

@test "a GARBAGE witness is ignored rather than refused (kit revision 14, R5)" {
    printf 'garbage sidecar, no keys here\n' > "$WITNESS"
    restore_ok "$BATS_TEST_TMPDIR/garbage-meta"
}

@test "a witness declaring the pre-WP12 format version no longer refuses the store (kit revision 14)" {
    # Version=1 was the witness marker for a base-85 store (exit 2). The kit
    # does not read it any more; the name-grammar markers still guard SR-061.
    sed -i -E 's/^Version=[0-9]+$/Version=1/' "$WITNESS"
    restore_ok "$BATS_TEST_TMPDIR/v1-meta"
}

@test "an ABSENT witness restores with no 'unverified index' warning (kit revision 14)" {
    rm -f "$WITNESS"
    restore_ok "$BATS_TEST_TMPDIR/no-meta"
    [[ "$output" != *UNVERIFIED* ]]
}

@test "--require-witness is gone: it is an unknown argument, usage and exit 2 (kit revision 14)" {
    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/strict" --from "$BK" --backup-root "$BK" \
        --change-root "$CH" --require-witness
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown argument: --require-witness"* ]]
    [ "$(restored_count "$BATS_TEST_TMPDIR/strict")" -eq 0 ]
}

@test "the kit carries no witness reader at all (kit revision 14)" {
    # A structural pin, so a half-removal cannot pass the behavioural cases by
    # luck: no reader of the sidecar is left in the shipped restorer.
    [ "$(grep -cE 'verify_manifest_witness|witness_value|WITNESS_NAME|WITNESS_FORMAT_VERSION' "$RS")" -eq 0 ]
}

@test "a manifest REPLACED BY GARBAGE still exits 2 via the header guard, writing nothing (SR-040)" {
    # The header-shape check stays: an unrecognizable header means this is not
    # a manifest at all (fail_loudly.bats pins the same code).
    printf 'this is not a backup manifest at all\n' > "$MANIFEST"
    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/garbage" --from "$BK" --backup-root "$BK" --change-root "$CH"
    [ "$status" -eq 2 ]
    [[ "$output" == *"not a FileBackup manifest"* ]]
    [ "$(restored_count "$BATS_TEST_TMPDIR/garbage")" -eq 0 ]
}

@test "each SNAPSHOT carries its OWN witness, not the backup root's (SR-038, writer side)" {
    # The writer's contract, checked on fixtures the real engine produced. The
    # kit no longer reads these, but an OLDER kit bundled in an old snapshot
    # still does (bounded-run-loop section 7), so they must stay correct.
    local snap
    for snap in "$CH"/Snapshot_*; do
        [ -f "$snap/MANIFEST.csv.meta" ]
        local want got
        want="$(grep -m1 '^XxH128=' "$snap/MANIFEST.csv.meta" | cut -d= -f2 | tr -d '\r')"
        got="$(xxh128sum -- "$snap/MANIFEST.csv" | awk '{print $1}' | tr 'a-f' 'A-F')"
        [ "$want" = "$got" ]
        # ...and it is NOT the backup root's digest.
        local root_digest
        root_digest="$(xxh128sum -- "$MANIFEST" | awk '{print $1}' | tr 'a-f' 'A-F')"
        [ "$want" != "$root_digest" ]
    done
}
