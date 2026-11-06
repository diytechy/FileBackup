#!/usr/bin/env bash
# Private fixture only: no production stores, network or credentials.
set -euo pipefail
image="${1:-filebackup-native:rust-preview}"
scratch="${2:-${TMPDIR:-/tmp}}"
root="$(mktemp -d "$scratch/native-container.XXXXXXXX")"
mkdir "$root/source" "$root/store" "$root/scratch" "$root/restored"
runtime_uid="$(id -u)"; runtime_gid="$(id -g)"
if [[ "$runtime_uid" == 0 ]]; then
    runtime_uid=65532; runtime_gid=65532
    chown "$runtime_uid:$runtime_gid" "$root/store" "$root/scratch" "$root/restored"
fi
printf 'container native recovery\n%.0s' {1..20000} > "$root/source/payload.txt"
printf '%s\n' '{"ConfigVersion":3,"BackupSets":[{"Name":"smoke","SourcePath":"/source","StorePath":"/store","CompressEnabled":true}]}' > "$root/config.json"
docker run --rm --read-only --network none --cap-drop ALL --security-opt no-new-privileges \
    --user "$runtime_uid:$runtime_gid" -v "$root/source:/source:ro" -v "$root/store:/store" \
    -v "$root/config.json:/config/FileBackup.json:ro" -v "$root/scratch:/tmp" "$image"
docker run --rm --read-only --network none --cap-drop ALL --security-opt no-new-privileges \
    --user "$runtime_uid:$runtime_gid" -v "$root/store:/store:ro" -v "$root/restored:/restored" \
    -v "$root/scratch:/tmp" --entrypoint bash "$image" /store/CurrentBackup/reconstruct.sh --target-root /restored
cmp "$root/source/payload.txt" "$root/restored/payload.txt"
printf 'Offline container round trip passed as UID %s: %s\n' "$runtime_uid" "$root"
