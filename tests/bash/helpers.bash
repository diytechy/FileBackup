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
