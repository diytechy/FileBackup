# Shared helpers for the bash-v1 restore bats suites (SR-030/031/032).
# Sourced by every *.bats file's setup().
# shellcheck disable=SC2034  # RS/FIXTURES/MODES are consumed by the sourcing suites

# Repo root = two levels up from tests/bash.
REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
RS="$REPO/bash/reconstruct.sh"
FIXTURES="$REPO/tests/fixtures"
MODES=(HashAddressed HashAddressed_Compress)

# xxHash128 of a file as UPPERCASE hex (the on-disk manifest form).
hash_upper() { xxh128sum -- "$1" | awk '{print $1}' | tr 'a-f' 'A-F'; }

# Verify every row of an expected TSV (posixRelPath<TAB>hash) restored byte-exact
# under <target>. Echoes a line per mismatch; returns the mismatch count.
verify_tree() {  # <target> <expected.tsv>
    local target="$1" tsv="$2" rel want got fail=0
    while IFS=$'\t' read -r rel want; do
        [[ -n "$rel" ]] || continue
        if [[ ! -f "$target/$rel" ]]; then echo "MISSING: $rel"; fail=$((fail+1)); continue; fi
        got="$(hash_upper "$target/$rel")"
        [[ "$got" == "$want" ]] || { echo "HASH-DIFF: $rel got=$got want=$want"; fail=$((fail+1)); }
    done < "$tsv"
    return $fail
}

# Origin folder for a mode + expected-file basename ("root" or "Snapshot_...").
origin_for() {  # <mode> <origin_name>
    local mode="$1" name="$2"
    if [[ "$name" == root ]]; then printf '%s' "$FIXTURES/bash-restore/$mode/backup"
    else printf '%s' "$FIXTURES/bash-restore/$mode/backup/changes/$name"; fi
}

# Expected content hash of one logical path, from a mode's expected/root.tsv.
expected_hash() {  # <mode> <posix_relpath>
    awk -F'\t' -v rel="$2" '$1==rel{print $2}' "$FIXTURES/bash-restore/$1/expected/root.tsv"
}

# First ROOT-LEVEL pool file whose raw bytes hash to the given content hash.
# Content addressing derives names from bytes, so tests locate objects by
# CONTENT rather than assuming a path (WP9 step 5: Mirror deleted).
pool_file_by_hash() {  # <backup_root> <upper_hash>
    local bk="$1" want="$2" f
    for f in "$bk"/*; do
        [[ -f "$f" ]] || continue
        [[ "$(hash_upper "$f")" == "$want" ]] && { printf '%s' "$f"; return 0; }
    done
    return 1
}

# The witness format version the CURRENT kit writes. Must track
# $script:WitnessFormatVersion in FileBackup.Common.psm1 and
# WITNESS_FORMAT_VERSION in bash/reconstruct.sh: since WP12 a store declaring
# LESS than this is refused outright as a pre-WP12 base-85 store (SR-061), so a
# fixture that re-stamps with a stale number no longer merely mislabels itself,
# it becomes unrestorable.
WITNESS_FORMAT_VERSION=2

# Re-stamp a manifest's witness after a test has deliberately modified the
# manifest. Lived in FIVE byte-identical copies across the suites until
# 2026-08-27, each with the version hard-coded - so the WP12 bump broke 30 tests
# at once. One definition now: the next bump touches this line only.
restamp_witness() {  # <manifest-path>
    local manifest="$1" witness="${1}.meta" rows bytes hash
    rows="$(gawk 'NR>1 && NF>0' "$manifest" | wc -l | tr -d ' ')"
    bytes="$(stat -c '%s' -- "$manifest")"
    hash="$(xxh128sum -- "$manifest" | awk '{print $1}' | tr 'a-f' 'A-F')"
    printf 'Version=%s\nRows=%s\nBytes=%s\nXxH128=%s\nWritten=%s\n' \
        "$WITNESS_FORMAT_VERSION" "$rows" "$bytes" "$hash" "$(date --iso-8601=seconds)" > "$witness"
}

# Build a conforming SR-069 stored-object name: 22 base-57 characters of hash,
# '_', the length base-57 unpadded, then the extension verbatim.
#
# Synthetic stores in these suites used to invent DataPath values ('data.bin',
# 'shared.bin'). Since WP12 both restorers REFUSE a non-blank DataPath that does
# not parse under the grammar (SR-061's structural half), so a fixture that
# invents a name is now testing a store the engine could never have written -
# and gets refused before reaching the behaviour under test.
#
# python3 rather than pwsh: this runs per fixture row and a pwsh start-up per
# call is seconds. reconstruct.sh itself has NO python dependency - this is
# test-scaffolding only, and the shipped fixtures still come from the real
# PowerShell encoder via scripts/gen_bash_fixtures.ps1.
hash_size_name() {  # <hash-hex-32> <length> [<ext>]
    python3 - "$1" "$2" "${3-}" <<'PYEOF'
import sys
ALPHA = "23456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
def enc(v, width=0):
    out = ""
    while v > 0:
        out = ALPHA[v % 57] + out
        v //= 57
    out = out or ALPHA[0]
    return out.rjust(width, ALPHA[0])
h, ln, ext = sys.argv[1], int(sys.argv[2]), sys.argv[3]
sys.stdout.write(enc(int(h, 16), 22) + "_" + enc(ln) + ext)
PYEOF
}
