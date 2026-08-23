#!/usr/bin/env bats
# TC-099 / SR-050 (with SR-031, SR-040) — the bash twin of TC-098. A
# blank-DataPath row is decided by the FORM of the file find_by_hash located,
# not by the row's Compressed column, so a snapshot written before a
# compression-policy flip still restores byte-exact instead of receiving 7z
# container bytes under the original filename (exit 0) or a misfiled host
# failure (exit 4). The exit-code classes for genuinely missing content and
# genuine host problems are unchanged.

setup() {
    load helpers
    WORK="$BATS_TEST_TMPDIR/work"
}

# Copy a fixture backup into a writable work tree and return its root.
use_fixture() {  # <mode>
    rm -rf "$WORK"
    cp -r "$FIXTURES/bash-restore/$1/backup" "$WORK"
}

# Rewrite one manifest row's DataPath and Compressed, then re-stamp the SR-038
# witness so the restore observes the case under test and not exit 3.
bend_row() {  # <relpath> <new-datapath> <new-compressed>
    local m="$WORK/MANIFEST.csv"
    gawk -v FPAT='("([^"]|"")*")|([^,]*)' -v OFS=',' \
         -v rel="\"$1\"" -v dp="\"$2\"" -v comp="\"$3\"" '
        NR==1 { print; next }
        $2==rel { $1=dp; $6=comp }
        { print }
    ' "$m" > "$m.tmp"
    mv "$m.tmp" "$m"
    restamp_witness "$m"
}

restamp_witness() {
    local manifest="$1" witness="${1}.meta" rows bytes hash
    rows="$(gawk 'NR>1 && NF>0' "$manifest" | wc -l | tr -d ' ')"
    bytes="$(stat -c '%s' -- "$manifest")"
    hash="$(xxh128sum -- "$manifest" | awk '{print $1}' | tr 'a-f' 'A-F')"
    printf 'Version=1\nRows=%s\nBytes=%s\nXxH128=%s\nWritten=%s\n' \
        "$rows" "$bytes" "$hash" "$(date --iso-8601=seconds)" > "$witness"
}

# hello.txt's true content hash, shared by every mode's fixture.
HELLO_HASH='3F6A2320F4D75810986789940FF30339'

restore_work() {  # <outdir>
    run bash "$RS" --target-root "$1" --from "$WORK" --backup-root "$WORK" --change-root "$WORK/changes"
}

@test "row says Compressed=No but the located file is a .7z: restores the payload (TC-099, SR-050)" {
    use_fixture Mirror_Compress
    bend_row 'hello.txt' '' 'No'
    restore_work "$BATS_TEST_TMPDIR/a"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    [ "$(hash_upper "$BATS_TEST_TMPDIR/a/hello.txt")" = "$HELLO_HASH" ]
}

@test "row says Compressed=Yes but the located file is raw: copies it (TC-099, SR-050)" {
    use_fixture Mirror
    bend_row 'hello.txt' '' 'Yes'
    restore_work "$BATS_TEST_TMPDIR/b"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    [ "$(hash_upper "$BATS_TEST_TMPDIR/b/hello.txt")" = "$HELLO_HASH" ]
}

@test "a .7z-named file holding RAW bytes is recovered, not called a candidate error (TC-099, SR-050)" {
    use_fixture Mirror
    mv "$WORK/hello.txt" "$WORK/hello.txt.7z"
    bend_row 'hello.txt' '' 'Yes'
    restore_work "$BATS_TEST_TMPDIR/c"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    [ "$(hash_upper "$BATS_TEST_TMPDIR/c/hello.txt")" = "$HELLO_HASH" ]
}

@test "a NON-blank DataPath row is still decided by its own Compressed (TC-099, SR-050)" {
    use_fixture Mirror_Compress
    restore_work "$BATS_TEST_TMPDIR/d"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    verify_tree "$BATS_TEST_TMPDIR/d" "$FIXTURES/bash-restore/Mirror_Compress/expected/root.tsv"
}

@test "a blank row for a GENUINE .7z source file is recovered, not called missing (TC-099, SR-050)" {
    # WP5 review finding H2, the bash twin. A real archive stored raw (SR-004
    # declines to re-compress a '.7z' source) EXPANDS successfully, but to
    # something that is not the row's content; before the fix the candidate was
    # dropped without its own bytes ever being tested, so the row was
    # unrecoverable while every checker called the store clean.
    use_fixture Mirror
    [ -n "${SEVEN_ZIP:-}" ] || SEVEN_ZIP="$(command -v 7z || command -v 7za || command -v 7zz)"
    [ -n "$SEVEN_ZIP" ] || skip "no 7z on this host"

    printf 'ARCHIVE-PAYLOAD-%.0s' {1..200} > "$BATS_TEST_TMPDIR/inner.txt"
    ( cd "$BATS_TEST_TMPDIR" && "$SEVEN_ZIP" a -bso0 -bsp0 -y real.7z inner.txt >/dev/null )
    cp "$BATS_TEST_TMPDIR/real.7z" "$WORK/real.7z"

    # A row for it with a BLANK DataPath: hash recovery must locate the file in
    # the pool and copy its own bytes.
    local h len
    h="$(hash_upper "$WORK/real.7z")"
    len="$(stat -c '%s' -- "$WORK/real.7z")"
    printf '"","real.7z","%s","2024-01-01T08:00:00.0000000-06:00","%s","No","Original","0",""\r\n' \
        "$len" "$h" >> "$WORK/MANIFEST.csv"
    restamp_witness "$WORK/MANIFEST.csv"

    restore_work "$BATS_TEST_TMPDIR/g"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    [ "$(hash_upper "$BATS_TEST_TMPDIR/g/real.7z")" = "$h" ]
}

@test "an unexpandable, unmatching .7z candidate is still a HOST failure, exit 4 (TC-099, SR-040)" {
    use_fixture Mirror
    rm -f "$WORK/hello.txt"
    printf 'neither an archive nor the payload' > "$WORK/hello.txt.7z"
    bend_row 'hello.txt' '' 'Yes'
    restore_work "$BATS_TEST_TMPDIR/e"
    [ "$status" -eq 4 ] || { echo "expected 4, got $status"; echo "$output"; false; }
}

@test "genuinely absent content is still the CONTENT class, exit 1 (TC-099, SR-040)" {
    use_fixture Mirror
    rm -f "$WORK/hello.txt"
    bend_row 'hello.txt' '' 'No'
    restore_work "$BATS_TEST_TMPDIR/f"
    [ "$status" -eq 1 ] || { echo "expected 1, got $status"; echo "$output"; false; }
}
