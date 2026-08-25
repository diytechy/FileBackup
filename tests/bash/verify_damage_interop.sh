#!/usr/bin/env bash
# TC-110 (SR-056, SR-031): restore the Windows-damaged stores with
# reconstruct.sh and demand VERDICT PARITY with the PowerShell restorer —
# identical exit codes and identical restored bytes, as recorded in
# <root>/damage/expected.tsv by scripts/make_damaged_interop.ps1.
set -uo pipefail

root="${1:?usage: verify_damage_interop.sh <fixture-root>}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rs="$here/../../bash/reconstruct.sh"
damage="$root/damage"
expected_raw="$damage/expected.tsv"
[[ -f "$expected_raw" ]] || { echo "FAIL: $expected_raw missing"; exit 1; }
# The verdict file is written on Windows — tolerate CRLF like the manifest
# parser does, or every comparison fails on an invisible trailing \r.
expected="$(mktemp)"
tr -d '\r' < "$expected_raw" > "$expected"

hash_upper() { xxh128sum -- "$1" | awk '{print $1}' | tr 'a-f' 'A-F'; }

fails=0
for shape in heal gone; do
    store="$damage/$shape"
    [[ -d "$store" ]] || { echo "FAIL: store '$store' missing"; fails=$((fails+1)); continue; }
    want_exit="$(awk -F'\t' -v s="$shape" '$1=="exit" && $2==s {print $3}' "$expected")"
    target="$(mktemp -d)/t"
    bash "$rs" --target-root "$target" --from "$store" --backup-root "$store" >/dev/null 2>&1
    got_exit=$?
    if [[ "$got_exit" != "$want_exit" ]]; then
        echo "FAIL[$shape]: exit parity broken — PowerShell $want_exit, bash $got_exit"
        fails=$((fails+1))
    else
        echo "OK[$shape]: both restorers exit $got_exit"
    fi
    # No extras: bash must produce exactly the files PowerShell produced.
    want_n="$(awk -F'\t' -v s="$shape" '$1=="file" && $2==s' "$expected" | wc -l | tr -d ' ')"
    got_n="$(find "$target" -type f ! -name 'RECONSTRUCT.log' 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "$got_n" != "$want_n" ]]; then
        echo "FAIL[$shape]: restored file-count mismatch (PowerShell $want_n, bash $got_n)"
        fails=$((fails+1))
    fi
    # Byte parity for every file the PowerShell restorer produced.
    while IFS=$'\t' read -r kind s rel want_hash; do
        [[ "$kind" == "file" && "$s" == "$shape" ]] || continue
        if [[ ! -f "$target/$rel" ]]; then
            echo "FAIL[$shape]: '$rel' restored on Windows but missing here"
            fails=$((fails+1)); continue
        fi
        got_hash="$(hash_upper "$target/$rel")"
        if [[ "$got_hash" != "$want_hash" ]]; then
            echo "FAIL[$shape]: '$rel' byte mismatch (PowerShell $want_hash, bash $got_hash)"
            fails=$((fails+1))
        fi
    done < "$expected"
done

if (( fails > 0 )); then echo "verify_damage_interop: $fails failure(s)"; exit 1; fi
echo "verify_damage_interop: verdict parity holds for both damaged stores."
