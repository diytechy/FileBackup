#!/usr/bin/env bash
#
# verify_restores.sh <fixtures-root> — restore every origin (the store's Latest
# + each Snapshot_<date>) of every storage mode found under
# <fixtures-root>/bash-restore/<mode>/store with reconstruct.sh, and verify each
# restored file byte-for-byte against that origin's expected TSV
# (posixRelPath<TAB>content-hash). Exits non-zero if any origin fails to
# restore cleanly or any file's hash differs. No store flag is passed: kit
# revision 15 finds the store as the origin's parent, which is what a user
# running the kit from inside the store gets.
#
# Used by the CI cross-artifact interop job on a FRESH set of PowerShell-produced
# backups (gen_bash_fixtures.ps1 -Fresh) — the real windows->ubuntu proof — and
# runnable locally against tests/fixtures for a quick end-to-end check.

set -uo pipefail

ROOT="${1:?usage: verify_restores.sh <dir containing bash-restore/>}"
RS="$(cd "$(dirname "$0")/../../bash" && pwd)/reconstruct.sh"
BR="$ROOT/bash-restore"
[[ -d "$BR" ]] || { echo "no bash-restore/ under '$ROOT'" >&2; exit 2; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fails=0; origins=0

hash_upper() { xxh128sum -- "$1" | awk '{print $1}' | tr 'a-f' 'A-F'; }

for modedir in "$BR"/*/; do
    mode="$(basename "$modedir")"
    store="$modedir/store"
    [[ -f "$store/Latest/MANIFEST.csv" ]] || continue
    for tsv in "$modedir"/expected/*.tsv; do
        [[ -f "$tsv" ]] || continue
        name="$(basename "$tsv" .tsv)"
        if [[ "$name" == root ]]; then origin="$store/Latest"; else origin="$store/$name"; fi
        out="$TMP/$mode/$name"; origins=$((origins+1))
        if ! bash "$RS" --target-root "$out" --from "$origin" >/dev/null 2>&1; then
            echo "FAIL  $mode/$name  (reconstruct.sh exit non-zero)"; fails=$((fails+1)); continue
        fi
        vf=0
        while IFS=$'\t' read -r rel want; do
            [[ -n "$rel" ]] || continue
            if [[ ! -f "$out/$rel" ]]; then echo "  MISSING $mode/$name: $rel"; vf=$((vf+1)); continue; fi
            got="$(hash_upper "$out/$rel")"
            [[ "$got" == "$want" ]] || { echo "  HASH-DIFF $mode/$name: $rel got=$got want=$want"; vf=$((vf+1)); }
        done < "$tsv"
        if [[ $vf -eq 0 ]]; then echo "PASS  $mode/$name"; else echo "FAIL  $mode/$name  ($vf mismatch)"; fails=$((fails+1)); fi
    done
done

echo "==== verified $origins origin(s); $fails failing ===="
# Zero origins is a layout mismatch (no <mode>/store/Latest found), never a pass.
[[ $origins -gt 0 ]] || { echo "no store found under '$BR' (expected <mode>/store/Latest)" >&2; exit 1; }
[[ $fails -eq 0 ]]
