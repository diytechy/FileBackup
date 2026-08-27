#!/usr/bin/env bats
# TC-056 / SR-032 — the bash manifest layer must interpret MANIFEST.csv exactly
# as the Windows engine writes it: RFC-4180 quoting (commas / ""-escaped quotes),
# CRLF line ends, UTF-8 (with BOM tolerance), an empty leading DataPath, and the
# '\'->'/' RelativePath mapping. Fields are validated via parse_manifest's
# \x1f-separated output (DataPath|RelativePath|Length|LastWriteTimeStr|xxH2Hash|Compressed|StoredAsHashSize).

setup() {
    load helpers
    source "$RS"
    US=$'\x1f'
    HDR='"DataPath","RelativePath","Length","LastWriteTimeStr","xxH2Hash","Compressed","StoredAsHashSize","Duplicate","MediaMBPerSec"'
    CSV="$BATS_TEST_TMPDIR/m.csv"
}

# Write the header + given rows as a CRLF, UTF-8 (no BOM) manifest.
write_csv() { { printf '%s\r\n' "$HDR"; for r in "$@"; do printf '%s\r\n' "$r"; done; } > "$CSV"; }

@test "to_posix maps Windows backslashes to forward slashes (SR-032)" {
    [ "$(to_posix 'sub\dir\file.txt')" = "sub/dir/file.txt" ]
    [ "$(to_posix 'flat.txt')" = "flat.txt" ]
    [ "$(to_posix '')" = "" ]
}

@test "parses a plain row (TC-056, SR-032)" {
    write_csv '"a.txt","a.txt","5","2024-01-01T09:00:00.0000000","HASHA","No","Original","0",""'
    run parse_manifest "$CSV"
    [ "$status" -eq 0 ]
    [ "$output" = "a.txt${US}a.txt${US}5${US}2024-01-01T09:00:00.0000000${US}HASHA${US}No${US}Original" ]
}

@test "parses a quoted field containing a comma (TC-056, SR-032)" {
    write_csv '"with,comma.txt","with,comma.txt","3","d","HASHB","No","Original","0",""'
    run parse_manifest "$CSV"
    [ "$output" = "with,comma.txt${US}with,comma.txt${US}3${US}d${US}HASHB${US}No${US}Original" ]
}

@test "unescapes a doubled quote inside a quoted field (TC-056, SR-032)" {
    write_csv '"qu""ote.txt","qu""ote.txt","4","d","HASHC","No","Original","0",""'
    run parse_manifest "$CSV"
    [ "$output" = 'qu"ote.txt'"${US}"'qu"ote.txt'"${US}4${US}d${US}HASHC${US}No${US}Original" ]
}

@test "preserves an EMPTY leading DataPath field (TC-056, SR-032)" {
    # The hash-recovery case: a blank DataPath must not shift the other columns.
    write_csv '"","blank.txt","7","d","HASHD","Yes","Hash","0",""'
    run parse_manifest "$CSV"
    [ "$output" = "${US}blank.txt${US}7${US}d${US}HASHD${US}Yes${US}Hash" ]
}

@test "keeps unicode / bracket / space / backslash names intact (TC-056, SR-032)" {
    write_csv '"sub\[b] (p) café.txt","sub\[b] (p) café.txt","9","d","HASHE","No","Original","0",""'
    run parse_manifest "$CSV"
    [ "$output" = 'sub\[b] (p) café.txt'"${US}"'sub\[b] (p) café.txt'"${US}9${US}d${US}HASHE${US}No${US}Original" ]
    # And the RelativePath maps to POSIX for filesystem use.
    local rp; rp="$(printf '%s' "$output" | cut -d"$US" -f2)"
    [ "$(to_posix "$rp")" = "sub/[b] (p) café.txt" ]
}

@test "tolerates a bare (unquoted) empty trailing field (TC-056, SR-032)" {
    # PS Export-Csv writes a \$null MediaMBPerSec as a bare empty field (no quotes).
    write_csv '"f.txt","f.txt","2","d","HASHF","No","Original","0",'
    run parse_manifest "$CSV"
    [ "$output" = "f.txt${US}f.txt${US}2${US}d${US}HASHF${US}No${US}Original" ]
}

@test "tolerates a UTF-8 BOM on the header (TC-056, SR-032)" {
    { printf '\xef\xbb\xbf%s\r\n' "$HDR"; printf '%s\r\n' '"a.txt","a.txt","5","d","HASHA","No","Original","0",""'; } > "$CSV"
    run parse_manifest "$CSV"
    [ "$status" -eq 0 ]
    [ "$output" = "a.txt${US}a.txt${US}5${US}d${US}HASHA${US}No${US}Original" ]
}

@test "parses the real committed fixture manifests without error (TC-056, SR-032)" {
    # Checked against the WITNESS's own Rows= line, not a hard-coded number.
    # The witness is stamped by the PowerShell engine, so this asserts the bash
    # parser and the engine agree on how many rows the manifest holds - a real
    # cross-implementation check, and one that does not go stale every time the
    # fixture timeline gains a file. It went stale exactly that way when WP12
    # added the SR-070 extension shapes.
    local m rows want
    for m in "${MODES[@]}"; do
        rows="$(parse_manifest "$FIXTURES/bash-restore/$m/backup/MANIFEST.csv" | wc -l)"
        want="$(witness_value "$FIXTURES/bash-restore/$m/backup/MANIFEST.csv.meta" 'Rows')"
        [[ "$want" =~ ^[0-9]+$ ]] || { echo "no Rows= in the $m witness"; false; }
        [ "$rows" -ge 10 ] || { echo "$m: only $rows rows parsed"; false; }
        [ "$rows" -eq "$want" ] || { echo "$m: bash parsed $rows rows, engine recorded $want"; false; }
    done
}
