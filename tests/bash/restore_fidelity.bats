#!/usr/bin/env bats
# TC-136 / TC-137 / TC-138 — the POSIX half of kit revision 7's fidelity work:
# each restored file carries its OWN LastWriteTimeStr (SR-066), the
# DIRECTORIES.csv sidecar recreates empty directories while reporting the
# Windows folder attributes as inapplicable here (SR-065), and a legacy
# path-addressed store is REFUSED rather than restored (SR-061). The PowerShell
# twins live in tests/Unit/RestoreFidelity.Tests.ps1.

setup() {
    load helpers
}

# twin_store <dir> : two rows sharing ONE stored object (the dedup shape) with
# DIFFERENT LastWriteTimeStr values, plus a third row whose timestamp cell is
# garbage. Mirrors what the engine writes for content-addressed twins.
twin_store() {
    local dir="$1" h len uh ulen
    mkdir -p "$dir"
    local sd ud
    printf 'SHARED-PAYLOAD-BYTES' > "$dir/shared.stage"
    printf 'UNIQUE-PAYLOAD-BYTES' > "$dir/unique.stage"
    h="$(hash_upper "$dir/shared.stage")";  len="$(stat -c '%s' "$dir/shared.stage")"
    uh="$(hash_upper "$dir/unique.stage")"; ulen="$(stat -c '%s' "$dir/unique.stage")"
    sd="$(hash_size_name "$h" "$len" '.bin')";  mv "$dir/shared.stage" "$dir/$sd"
    ud="$(hash_size_name "$uh" "$ulen" '.bin')"; mv "$dir/unique.stage" "$dir/$ud"
    {
      printf '"DataPath","RelativePath","Length","LastWriteTimeStr","xxH2Hash","Compressed","StoredAsHashSize","Duplicate","MediaMBPerSec"\r\n'
      printf '"%s","twin-a.txt","%s","2001-01-01T01:02:03.0000000+00:00","%s","No","Hash","0",""\r\n' "$sd" "$len" "$h"
      printf '"%s","twin-b.txt","%s","2002-02-02T04:05:06.0000000+00:00","%s","No","Hash","1",""\r\n' "$sd" "$len" "$h"
      printf '"%s","garbage-time.txt","%s","not-a-timestamp","%s","No","Hash","0",""\r\n' "$ud" "$ulen" "$uh"
    } > "$dir/MANIFEST.csv"
    restamp_witness "$dir/MANIFEST.csv"
}

@test "a deduplicated twin keeps its OWN modification time (SR-066 / TC-136)" {
    local s="$BATS_TEST_TMPDIR/mtime" t="$BATS_TEST_TMPDIR/tmtime"
    twin_store "$s"

    run bash "$RS" --target-root "$t" --from "$s"
    [ "$status" -eq 0 ]
    # Compared as epoch seconds so the host's timezone cannot decide the result:
    # the manifest carries an offset, and the instant is what must round-trip.
    [ "$(date -u -d '2001-01-01T01:02:03+00:00' +%s)" = "$(stat -c '%Y' "$t/twin-a.txt")" ]
    [ "$(date -u -d '2002-02-02T04:05:06+00:00' +%s)" = "$(stat -c '%Y' "$t/twin-b.txt")" ]
}

@test "a garbage LastWriteTimeStr warns but still restores the bytes (SR-066 / TC-136)" {
    local s="$BATS_TEST_TMPDIR/badtime" t="$BATS_TEST_TMPDIR/tbadtime"
    twin_store "$s"

    run bash "$RS" --target-root "$t" --from "$s"
    [ "$status" -eq 0 ]
    [[ "$output" == *"could not stamp LastWriteTime on 'garbage-time.txt'"* ]]
    [ "$(cat "$t/garbage-time.txt")" = 'UNIQUE-PAYLOAD-BYTES' ]
}

# sidecar_store <dir> : one ordinary row plus a DIRECTORIES.csv describing an
# empty directory, a nested empty one, and a Hidden+System folder.
sidecar_store() {
    local dir="$1" h len
    mkdir -p "$dir"
    local dn
    printf 'PAYLOAD' > "$dir/data.stage"
    h="$(hash_upper "$dir/data.stage")"; len="$(stat -c '%s' "$dir/data.stage")"
    dn="$(hash_size_name "$h" "$len" '.bin')"; mv "$dir/data.stage" "$dir/$dn"
    {
      printf '"DataPath","RelativePath","Length","LastWriteTimeStr","xxH2Hash","Compressed","StoredAsHashSize","Duplicate","MediaMBPerSec"\r\n'
      printf '"%s","hidden-dir/secret.txt","%s","2003-03-03T07:08:09.0000000+00:00","%s","No","Hash","0",""\r\n' "$dn" "$len" "$h"
    } > "$dir/MANIFEST.csv"
    restamp_witness "$dir/MANIFEST.csv"
    {
      printf '"RelativePath","Attributes"\r\n'
      printf '"empty-dir",""\r\n'
      printf '"empty-dir\\nested-empty",""\r\n'
      printf '"hidden-dir","Hidden,System"\r\n'
    } > "$dir/DIRECTORIES.csv"
}

@test "the sidecar recreates empty directories and reports the attributes as inapplicable (SR-065 / TC-137)" {
    local s="$BATS_TEST_TMPDIR/dirs" t="$BATS_TEST_TMPDIR/tdirs"
    sidecar_store "$s"

    run bash "$RS" --target-root "$t" --from "$s"
    [ "$status" -eq 0 ]
    [ -d "$t/empty-dir" ]
    [ -d "$t/empty-dir/nested-empty" ]
    [ -f "$t/hidden-dir/secret.txt" ]
    # The attribute half is REPORTED, never silently dropped.
    [[ "$output" == *"have no POSIX equivalent and were NOT applied"* ]]
}

@test "an absent sidecar restores exactly as before, with no empty directories (SR-065 / TC-137)" {
    local s="$BATS_TEST_TMPDIR/nodirs" t="$BATS_TEST_TMPDIR/tnodirs"
    sidecar_store "$s"
    rm -f "$s/DIRECTORIES.csv"

    run bash "$RS" --target-root "$t" --from "$s"
    [ "$status" -eq 0 ]
    [ -f "$t/hidden-dir/secret.txt" ]
    [ ! -d "$t/empty-dir" ]
}

@test "a garbage sidecar never fails the restore (SR-065 / TC-137)" {
    local s="$BATS_TEST_TMPDIR/junkdirs" t="$BATS_TEST_TMPDIR/tjunkdirs"
    sidecar_store "$s"
    printf 'this is not a directory sidecar\n,,,\n' > "$s/DIRECTORIES.csv"

    run bash "$RS" --target-root "$t" --from "$s"
    [ "$status" -eq 0 ]
    [ -f "$t/hidden-dir/secret.txt" ]
}

@test "the sidecar cannot write outside the target root (SR-065 / TC-137)" {
    local s="$BATS_TEST_TMPDIR/escdirs" t="$BATS_TEST_TMPDIR/tescdirs"
    sidecar_store "$s"
    {
      printf '"RelativePath","Attributes"\r\n'
      printf '"..\\..\\ESCAPED-DIR",""\r\n'
    } > "$s/DIRECTORIES.csv"

    run bash "$RS" --target-root "$t" --from "$s"
    [ "$status" -eq 0 ]
    [[ "$output" == *"escapes the target root"* ]]
    [ ! -d "$BATS_TEST_TMPDIR/ESCAPED-DIR" ]
}

# legacy_store <dir> <marker> : a CONSTRUCTED pre-content-addressed store. No
# post-WP9 engine can produce one, so the shape is built by hand - the same
# honesty pattern the PowerShell G4.1 case uses.
legacy_store() {
    local dir="$1" marker="$2" h len data form
    mkdir -p "$dir/sub"
    printf 'LEGACY-PAYLOAD' > "$dir/sub/old.txt"
    h="$(hash_upper "$dir/sub/old.txt")"; len="$(stat -c '%s' "$dir/sub/old.txt")"
    if [[ "$marker" == 'stored-as-original' ]]; then
        # The authoritative marker, with a content-addressed-looking DataPath.
        cp "$dir/sub/old.txt" "$dir/flat.bin"
        data='flat.bin'; form='Original'
    else
        # The structural marker alone: a path-addressed DataPath, column 'Hash'.
        data='sub\old.txt'; form='Hash'
    fi
    {
      printf '"DataPath","RelativePath","Length","LastWriteTimeStr","xxH2Hash","Compressed","StoredAsHashSize","Duplicate","MediaMBPerSec"\r\n'
      printf '"%s","sub/old.txt","%s","d","%s","No","%s","0",""\r\n' "$data" "$len" "$h" "$form"
    } > "$dir/MANIFEST.csv"
    restamp_witness "$dir/MANIFEST.csv"
}

@test "a legacy store marked StoredAsHashSize=Original is refused, writing nothing (SR-061 / TC-138)" {
    local s="$BATS_TEST_TMPDIR/legacy-col" t="$BATS_TEST_TMPDIR/tlegacy-col"
    legacy_store "$s" 'stored-as-original'

    run bash "$RS" --target-root "$t" --from "$s"
    [ "$status" -eq 2 ]
    [[ "$output" == *"not a store this kit can restore"* ]]
    [[ "$output" == *"StoredAsHashSize"* ]]
    [ ! -f "$t/sub/old.txt" ]
}

@test "a legacy store marked by a path-addressed DataPath is refused too (SR-061 / TC-138)" {
    local s="$BATS_TEST_TMPDIR/legacy-path" t="$BATS_TEST_TMPDIR/tlegacy-path"
    legacy_store "$s" 'path-addressed-datapath'

    run bash "$RS" --target-root "$t" --from "$s"
    [ "$status" -eq 2 ]
    [[ "$output" == *"not a store this kit can restore"* ]]
    [ ! -f "$t/sub/old.txt" ]
}

# form_store <dir> <compressed-cell> : one row whose stored object is RAW content
# while the manifest's Compressed cell says whatever the caller asks. SR-068 says
# the bytes decide, so a lying cell must change nothing.
form_store() {
    local dir="$1" cell="$2" h len
    mkdir -p "$dir"
    local dn
    printf 'RAW-CONTENT-NOT-AN-ARCHIVE' > "$dir/data.stage"
    h="$(hash_upper "$dir/data.stage")"; len="$(stat -c '%s' "$dir/data.stage")"
    dn="$(hash_size_name "$h" "$len" '.bin')"; mv "$dir/data.stage" "$dir/$dn"
    {
      printf '"DataPath","RelativePath","Length","LastWriteTimeStr","xxH2Hash","Compressed","StoredAsHashSize","Duplicate","MediaMBPerSec"
'
      printf '"%s","restored.txt","%s","d","%s","%s","Hash","0",""
' "$dn" "$len" "$h" "$cell"
    } > "$dir/MANIFEST.csv"
    restamp_witness "$dir/MANIFEST.csv"
}

@test "a LYING Compressed=Yes over raw bytes still restores byte-exact (SR-068 / TC-141)" {
    local s="$BATS_TEST_TMPDIR/formlie" t="$BATS_TEST_TMPDIR/tformlie"
    form_store "$s" 'Yes'

    run bash "$RS" --target-root "$t" --from "$s"
    [ "$status" -eq 0 ]
    [ "$(cat "$t/restored.txt")" = 'RAW-CONTENT-NOT-AN-ARCHIVE' ]
}

@test "an already-compressed SOURCE file stored raw is never expanded (SR-068 / TC-141)" {
    command -v 7z >/dev/null 2>&1 || skip "7z not available"
    local s="$BATS_TEST_TMPDIR/form7z" t="$BATS_TEST_TMPDIR/tform7z" h len
    mkdir -p "$s" "$BATS_TEST_TMPDIR/mk"
    printf 'INSIDE-THE-USERS-ARCHIVE' > "$BATS_TEST_TMPDIR/mk/payload.txt"
    ( cd "$BATS_TEST_TMPDIR/mk" && 7z a -bso0 -bsp0 mine.7z payload.txt >/dev/null 2>&1 )
    # Stored RAW: the object's bytes ARE a 7z archive, and the row says so
    # correctly with Compressed=No. Sniffing alone would expand the user's file.
    cp "$BATS_TEST_TMPDIR/mk/mine.7z" "$s/data.stage"
    h="$(hash_upper "$s/data.stage")"; len="$(stat -c '%s' "$s/data.stage")"
    local dn; dn="$(hash_size_name "$h" "$len" '.bin')"; mv "$s/data.stage" "$s/$dn"
    {
      printf '"DataPath","RelativePath","Length","LastWriteTimeStr","xxH2Hash","Compressed","StoredAsHashSize","Duplicate","MediaMBPerSec"
'
      printf '"%s","mine.7z","%s","d","%s","No","Hash","0",""
' "$dn" "$len" "$h"
    } > "$s/MANIFEST.csv"
    restamp_witness "$s/MANIFEST.csv"

    run bash "$RS" --target-root "$t" --from "$s"
    [ "$status" -eq 0 ]
    [ "$(hash_upper "$t/mine.7z")" = "$h" ]
}
