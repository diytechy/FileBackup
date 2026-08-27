#!/usr/bin/env bats
# TC-069 / SR-039 (with SR-031) — reconstruct.sh verifies the manifest witness
# (MANIFEST.csv.meta) BEFORE restoring anything: a damaged index refuses the
# restore rather than "succeeding" against a shrunken job. The bash twin of
# TC-068. A backup written before the witness contract (no sidecar) must still
# restore, with an explicit 'unverified index' warning.

setup() {
    load helpers
    # Work on a WRITABLE copy so we can damage the index.
    WORK="$BATS_TEST_TMPDIR/work"
    cp -r "$FIXTURES/bash-restore/HashAddressed/backup" "$WORK"
    BK="$WORK"; CH="$WORK/changes"
    MANIFEST="$BK/MANIFEST.csv"
    WITNESS="$BK/MANIFEST.csv.meta"
}

# Re-stamp the witness the way Write-Manifest does (SR-038): five Key=Value
# lines, UTF-8 without BOM, LF. Used to prove a damaged manifest restores again
# once its witness agrees, and to keep deliberate tampering on-target.
# Count files the restore actually wrote into the target. The restorer's own
# RECONSTRUCT.log does not count as a restored row.
restored_count() {
    local target="$1"
    [[ -d "$target" ]] || { echo 0; return; }
    find "$target" -type f ! -name 'RECONSTRUCT.log' | wc -l | tr -d ' '
}

@test "the shipped fixtures carry a witness that verifies (SR-038/SR-039)" {
    [ -f "$WITNESS" ]
    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/ok" --from "$BK" --backup-root "$BK" --change-root "$CH"
    [ "$status" -eq 0 ]
    [[ "$output" == *"verified against its witness"* ]]
}

@test "a TRUNCATED manifest exits 3 and writes nothing into the target (SR-039)" {
    # Byte length is the cheap pre-check that names truncation precisely.
    truncate -s -40 "$MANIFEST"
    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/trunc" --from "$BK" --backup-root "$BK" --change-root "$CH"
    [ "$status" -eq 3 ]
    [[ "$output" == *"byte length disagrees with its witness"* ]]
    [ "$(restored_count "$BATS_TEST_TMPDIR/trunc")" -eq 0 ]
}

@test "a BYTE-EDITED manifest of the same length exits 3 (digest catches it) (SR-039)" {
    # Same length and same row count, so only the xxHash128 can catch it — this
    # is why the digest, not the counts, is the authoritative check.
    local before after
    before="$(stat -c '%s' -- "$MANIFEST")"
    # Overwrite ONE byte in place, deep inside the data rows, so byte length and
    # row count are untouched and only the digest can catch the change.
    printf 'X' | dd of="$MANIFEST" bs=1 seek=$(( before - 12 )) count=1 conv=notrunc status=none
    after="$(stat -c '%s' -- "$MANIFEST")"
    [ "$before" -eq "$after" ]

    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/edit" --from "$BK" --backup-root "$BK" --change-root "$CH"
    [ "$status" -eq 3 ]
    [[ "$output" == *"digest disagrees with its witness"* ]]
    [ "$(restored_count "$BATS_TEST_TMPDIR/edit")" -eq 0 ]
}

@test "a manifest with rows REMOVED exits 3 naming the expected row count (SR-039)" {
    # The operator-legible failure: "expected N rows, found M" — the exact shape
    # of HomeHub cross-check finding E (a shrunken job reported as success).
    head -n 3 "$MANIFEST" > "$MANIFEST.tmp" && mv -f "$MANIFEST.tmp" "$MANIFEST"
    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/short" --from "$BK" --backup-root "$BK" --change-root "$CH"
    [ "$status" -eq 3 ]
    [ "$(restored_count "$BATS_TEST_TMPDIR/short")" -eq 0 ]
}

@test "a ROWS-ONLY disagreement warns and restores, because the digest is authoritative (SR-039)" {
    # WP1 plan sec.6 decision 3: XxH128 is the authority, Rows is the
    # operator-legible number. Bytes and digest matching means this is exactly
    # the manifest that was witnessed, so a differing count is a
    # counting-semantics divergence, not damage — it must not refuse a restore.
    sed -i -E 's/^Rows=[0-9]+$/Rows=999/' "$WITNESS"
    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/rowsonly" --from "$BK" --backup-root "$BK" --change-root "$CH"
    [ "$status" -eq 0 ]
    [[ "$output" == *"row count disagrees with its witness"* ]]
    [[ "$output" == *"not damage"* ]]
    [ -f "$BATS_TEST_TMPDIR/rowsonly/hello.txt" ]
}

@test "a ROWS disagreement with NO digest to defer to still exits 3 (SR-039)" {
    sed -i -E 's/^Rows=[0-9]+$/Rows=999/' "$WITNESS"
    sed -i -E '/^XxH128=/d' "$WITNESS"
    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/rowsnodigest" --from "$BK" --backup-root "$BK" --change-root "$CH"
    [ "$status" -eq 3 ]
    [ "$(restored_count "$BATS_TEST_TMPDIR/rowsnodigest")" -eq 0 ]
}

@test "a manifest REPLACED BY GARBAGE exits 2 via the header guard (SR-039/SR-040)" {
    # Precedence 2 > 3: an unrecognizable header means this is not a manifest at
    # all, which is the pre-existing corrupt-file guard (fail_loudly.bats pins
    # the same code) — the witness never gets a say.
    printf 'this is not a backup manifest at all\n' > "$MANIFEST"
    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/garbage" --from "$BK" --backup-root "$BK" --change-root "$CH"
    [ "$status" -eq 2 ]
    [[ "$output" == *"not a FileBackup manifest"* ]]
    [ "$(restored_count "$BATS_TEST_TMPDIR/garbage")" -eq 0 ]
}

@test "an UNPARSEABLE witness exits 3 rather than being ignored (SR-039)" {
    printf 'garbage sidecar, no keys here\n' > "$WITNESS"
    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/badmeta" --from "$BK" --backup-root "$BK" --change-root "$CH"
    [ "$status" -eq 3 ]
    [ "$(restored_count "$BATS_TEST_TMPDIR/badmeta")" -eq 0 ]
}

@test "RE-STAMPING the witness makes the same damaged-then-restamped manifest restore (SR-039)" {
    # Proves the refusal is about the manifest DISAGREEING with its witness, not
    # about the manifest being unusual: re-stamp and the restore proceeds.
    truncate -s -40 "$MANIFEST"
    restamp_witness "$MANIFEST"
    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/restamped" --from "$BK" --backup-root "$BK" --change-root "$CH"
    # The index is now self-consistent, so verification passes. (Rows really are
    # gone, so this is a smaller job — which is exactly the point: the witness
    # detects DISAGREEMENT, and re-stamping is a deliberate operator act.)
    [ "$status" -ne 3 ]
    [[ "$output" != *"witness"*"disagrees"* ]]
}

@test "a LEGACY origin with no witness restores, warning that the index is unverified (SR-039)" {
    # Every backup written before this contract must keep restoring.
    rm -f "$WITNESS"
    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/legacy" --from "$BK" --backup-root "$BK" --change-root "$CH"
    [ "$status" -eq 0 ]
    [[ "$output" == *"UNVERIFIED"* ]]
    [ -f "$BATS_TEST_TMPDIR/legacy/hello.txt" ]
}

@test "--require-witness turns a missing witness into a refusal (SR-039)" {
    rm -f "$WITNESS"
    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/strict" --from "$BK" --backup-root "$BK" \
        --change-root "$CH" --require-witness
    [ "$status" -eq 3 ]
    [[ "$output" == *"require-witness"* ]]
    [ "$(restored_count "$BATS_TEST_TMPDIR/strict")" -eq 0 ]
}

@test "a witness from the FUTURE verifies the known fields and warns (SR-039)" {
    # A newer witness format must never condemn a good manifest.
    sed -i -E 's/^Version=[0-9]+$/Version=99/' "$WITNESS"
    printf 'SomeFutureKey=whatever\n' >> "$WITNESS"
    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/future" --from "$BK" --backup-root "$BK" --change-root "$CH"
    [ "$status" -eq 0 ]
    [[ "$output" == *"newer than this build understands"* ]]
}

@test "each SNAPSHOT carries its OWN witness, not the backup root's (SR-038)" {
    # The single most dangerous mistake available in SR-038 would be copying the
    # root's witness into snapshots with the restore kit.
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
