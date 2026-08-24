#!/usr/bin/env bash
#
# verify_restores.sh <fixtures-root> — restore every origin (backup root + each
# Snapshot_<date>) of every storage mode found under <fixtures-root>/bash-restore/
# with reconstruct.sh, and verify each restored file byte-for-byte against that
# origin's expected TSV (posixRelPath<TAB>content-hash). Exits non-zero if any
# origin fails to restore cleanly or any file's hash differs.
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
    bk="$modedir/backup"; ch="$bk/changes"
    [[ -f "$bk/MANIFEST.csv" ]] || continue
    for tsv in "$modedir"/expected/*.tsv; do
        [[ -f "$tsv" ]] || continue
        name="$(basename "$tsv" .tsv)"
        if [[ "$name" == root ]]; then origin="$bk"; else origin="$ch/$name"; fi
        out="$TMP/$mode/$name"; origins=$((origins+1))
        if ! bash "$RS" --target-root "$out" --from "$origin" --backup-root "$bk" --change-root "$ch" >/dev/null 2>&1; then
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
[[ $fails -eq 0 ]]
