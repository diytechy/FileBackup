#!/usr/bin/env bats
# TC-150 / TC-151 / TC-152 — SR-069, SR-061, SR-049.
#
# SR-061's refusal has TWO implementations — Test-LegacyStoredObjectName here in
# PowerShell, is_legacy_stored_name in bash/reconstruct.sh — and it decides
# whether a store is restorable AT ALL. Drift is silent until someone needs a
# restore, and it fails in both directions: a bash side that ACCEPTS a retired
# name MISreads a pre-WP12 store (the exact thing SR-061 exists to prevent),
# and one that REFUSES a current name makes the POSIX restorer reject good
# backups.
#
# tests/fixtures/name-grammar/cases.tsv is the shared corpus, written by
# scripts/gen_bash_fixtures.ps1 with the PowerShell functions as the ORACLE.
# The Pester twin (Common.Tests.ps1) re-derives the same file, so it cannot rot
# unnoticed either. Same pattern as the hash-conformance goldens (TC-053).
#
# Only IsLegacy is checked here, and deliberately so: this kit carries no
# "is it the current grammar?" predicate, because it would be dead weight in a
# file bundled into every backup. The locator matches CONTENT, never names, so
# the only naming question a restore ever asks is whether the store is one it
# must refuse. IsCurrent is the ENGINE's concern and the Pester twin owns it.

setup() {
    load helpers
    source "$RS"                                   # source-guard => main() does not run
    CASES="$FIXTURES/name-grammar/cases.tsv"
}

@test "is_legacy_stored_name matches the PowerShell oracle for every case (TC-151, SR-061)" {
    [ -f "$CASES" ]
    local fail=0 n=0 name want_cur want_leg got_leg
    # TSV, not CSV: a stored-object name may hold a space, a comma or a quote
    # (the extension is opaque, SR-070) but never a tab — SR-055 refuses control
    # characters at source, so the separator cannot appear in the data.
    while IFS=$'\t' read -r name want_cur want_leg; do
        [[ "$name" == "Name" ]] && continue         # header
        [[ -n "$name" ]] || continue
        n=$((n+1))
        if is_legacy_stored_name "$name"; then got_leg=1; else got_leg=0; fi
        if [[ "$got_leg" != "$want_leg" ]]; then
            echo "IsLegacy MISMATCH '$name': bash=$got_leg powershell=$want_leg"
            fail=$((fail+1))
        fi
    done < "$CASES"

    echo "checked $n name-grammar cases"
    [ "$n" -ge 20 ]
    [ "$fail" -eq 0 ]
}

@test "current and legacy are DIFFERENT questions, not complements (TC-150, SR-061/SR-049)" {
    # The T7 pin, and the most valuable test in this file. WP12's gate was first
    # written as "anything that does not parse under SR-069 is legacy". That
    # refused a WHOLE STORE over a single DAMAGED DataPath — turning one
    # repairable row into an unrestorable backup and locking out the
    # SR-049/SR-053/SR-056 heal-and-verify machinery entirely.
    #
    # The corpus deliberately carries names that are NEITHER grammar. If someone
    # ever re-derives one predicate from the other, that class collapses to
    # empty and this is what fails.
    [ -f "$CASES" ]
    local neither=0 name cur leg
    while IFS=$'\t' read -r name cur leg; do
        [[ "$name" == "Name" ]] && continue
        [[ -n "$name" ]] || continue
        [[ "$cur" == 0 && "$leg" == 0 ]] && neither=$((neither+1))
        [[ "$cur" == 1 && "$leg" == 1 ]] && { echo "'$name' is BOTH current and legacy"; return 1; }
    done < "$CASES"

    echo "names that are neither current nor legacy: $neither"
    [ "$neither" -ge 5 ]
}

@test "a damaged DataPath is not treated as a retired grammar (TC-150, SR-061/SR-049)" {
    # Directly, not via the corpus: these are the shapes a damaged or
    # third-party-rewritten row actually takes. Every one must fall through to
    # the per-row content machinery rather than condemning the store.
    local n
    for n in 'data.bin' 'obj00000.bin' 'd.txt' 'c.txt.7z' 'restored.txt' 'x'; do
        if is_legacy_stored_name "$n"; then
            echo "'$n' was wrongly classified as a retired grammar"
            return 1
        fi
    done
}

@test "a blank DataPath is never legacy - it means 'recover by hash' (TC-150, SR-061)" {
    run is_legacy_stored_name ''
    [ "$status" -ne 0 ]
}

@test "both retired grammars are caught: base-85 and path-addressed (TC-151, SR-061)" {
    # Real names: two from the WP11-era fixtures, one from a live pool.
    local n
    for n in 'lii`7EXH@[hgD!I= !!!!!!=X&K.7z' \
             '.nArDBFwE!yq[FFf !!!!!!!!#..bin' \
             'f7(#5C=v.uYfdGbp !!!!!!!!!%.foo bar' \
             'sub/old.txt' 'sub\old.txt'; do
        if ! is_legacy_stored_name "$n"; then
            echo "'$n' slipped past the SR-061 gate"
            return 1
        fi
    done
}

@test "no shipped fixture object reads as a retired grammar (TC-151, SR-069/SR-061)" {
    # The engine must never emit a name its own restore gate would refuse —
    # checked here by the OTHER implementation, against fixtures the real
    # PowerShell engine produced.
    local mode f base n=0 bad=0
    for mode in "${MODES[@]}"; do
        for f in "$FIXTURES/bash-restore/$mode/backup"/*; do
            [[ -f "$f" ]] || continue
            base="${f##*/}"
            # Root-level infrastructure is not a data object (SR-022).
            [[ "$base" =~ ^(MANIFEST|RECONSTRUCT|DIRECTORIES|FileBackup\.Common|System\.IO\.Hashing|FileBackupState|reconstruct\.sh) ]] && continue
            n=$((n+1))
            if is_legacy_stored_name "$base"; then
                echo "shipped object reads as RETIRED grammar: $base"
                bad=$((bad+1))
            fi
        done
    done
    echo "checked $n shipped pool objects"
    [ "$n" -ge 4 ]
    [ "$bad" -eq 0 ]
}

@test "the witness format version agrees across every file that declares it (TC-152, SR-061)" {
    # Three files declare it and they must move together: FileBackup.Common.psm1
    # STAMPS it, bash/reconstruct.sh REFUSES anything below it, and
    # tests/bash/helpers.bash RE-STAMPS fixtures with it. When the WP12 bump left
    # the third behind, 30 bats tests failed at once — and a mismatch between the
    # first two would be far worse: the POSIX restorer would refuse every store
    # the Windows engine writes, and no test here would have said why.
    local ps_v sh_v helper_v
    ps_v="$(grep -oE '^\$script:WitnessFormatVersion[[:space:]]*=[[:space:]]*[0-9]+' "$REPO/Modules/FileBackup.Common.psm1" | grep -oE '[0-9]+$')"
    sh_v="$(grep -oE '^WITNESS_FORMAT_VERSION=[0-9]+' "$RS" | grep -oE '[0-9]+$')"
    helper_v="$(grep -oE '^WITNESS_FORMAT_VERSION=[0-9]+' "$REPO/tests/bash/helpers.bash" | grep -oE '[0-9]+$')"

    echo "Common.psm1=$ps_v reconstruct.sh=$sh_v helpers.bash=$helper_v"
    [ -n "$ps_v" ] && [ -n "$sh_v" ] && [ -n "$helper_v" ]
    [ "$ps_v" == "$sh_v" ]
    [ "$ps_v" == "$helper_v" ]
}

@test "the ONE gap the gate leaves open is benign: blank rows restore by content (TC-154, SR-061)" {
    # SR-061's markers cannot classify a store whose DataPath values are ALL
    # blank and whose witness is absent — a blank string carries no grammar, and
    # SR-039 deliberately lets a witness-less store restore with a warning. WP12
    # accepted that gap on the grounds that it is HARMLESS: the locator matches
    # CONTENT, never names, so such a store restores correctly whatever its
    # objects are called.
    #
    # That is an argument, and arguments rot. This is the experiment. The store
    # below is the worst case the gap admits — every object renamed into the
    # RETIRED base-85 grammar, every DataPath blanked, no witness — and it must
    # still come back byte-exact rather than half-restored or misread.
    local work="$BATS_TEST_TMPDIR/blank" i=0
    cp -r "$FIXTURES/bash-restore/HashAddressed/backup" "$work"
    rm -rf "$work/changes"
    rm -f "$work/MANIFEST.csv.meta"

    # Rename every pool object into the old grammar. Names become meaningless;
    # only the bytes can answer now.
    local f base
    for f in "$work"/*; do
        [[ -f "$f" ]] || continue
        base="${f##*/}"
        [[ "$base" =~ ^(MANIFEST|RECONSTRUCT|DIRECTORIES|FileBackup\.Common|System\.IO\.Hashing|FileBackupState|reconstruct\.sh) ]] && continue
        i=$((i+1))
        mv "$f" "$work/$(printf 'lii%013d !!!!!!=X&%d.bin' "$i" "$i")"
    done
    [ "$i" -ge 4 ]

    # Blank every DataPath: column 1 of every data row.
    gawk -v FPAT='("([^"]|"")*")|([^,]*)' -v OFS=',' \
        'NR==1 { print; next } { $1="\"\""; print }' "$work/MANIFEST.csv" > "$work/m.tmp"
    mv "$work/m.tmp" "$work/MANIFEST.csv"

    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/tblank" --from "$work"
    [ "$status" -eq 0 ] || { echo "expected 0, got $status"; echo "$output"; false; }

    # Byte-exact against the same oracle every other restore test uses.
    run verify_tree "$BATS_TEST_TMPDIR/tblank" "$FIXTURES/bash-restore/HashAddressed/expected/root.tsv"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
}
