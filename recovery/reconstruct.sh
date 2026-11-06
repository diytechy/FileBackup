#!/usr/bin/env bash
# KitRevision: 17
# Independent native-metadata recovery. Helpers are the exact maintained shell
# primitives carried as reconstruct-core.sh; they do not call a native engine.
# Implements: LLR-172, LLR-173, LLR-174, LLR-175, LLR-176, LLR-179
set -uo pipefail
if (( BASH_VERSINFO[0] < 4 )); then printf '%s\n' 'Bash 4+ is required; install a current bash locally.' >&2; exit 2; fi
kit_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)" || exit 2
# shellcheck source=../bash/reconstruct.sh disable=SC1091
source "$kit_dir/reconstruct-core.sh"
log() { printf '%s\n' "$*" >&2; }
fail() { log "$*"; exit 2; }
host_fail() { log "$*"; exit 4; }
result=0
restored_files=0; failed_files=0; metadata_failures=0
finding() { log "$2"; if (( $1 == 4 || result == 0 )); then result=$1; fi; }
metadata_finding() { ((metadata_failures+=1)); finding 1 "$1"; }
origin="$kit_dir"; store=''; target=''; suffix=''; interactive=0; unattended=0
while (( $# )); do
    case "$1" in
        --from|--record-root) origin="${2:?record root required}"; shift 2 ;;
        --store-root) store="${2:?store root required}"; shift 2 ;;
        --target-root) target="${2:?target root required}"; shift 2 ;;
        --seven-zip) SEVEN_ZIP="${2:?7-Zip path required}"; shift 2 ;;
        --previous) suffix='.prev'; shift ;;
        --non-interactive) unattended=1; shift ;;
        --interactive) interactive=1; shift ;;
        -h|--help) log 'reconstruct.sh --target-root DIR [--from STATE] [--store-root STORE] [--previous] [--seven-zip TOOL]'; exit 0 ;;
        *) fail "Unknown argument: $1" ;;
    esac
done
if [[ -n "$target" ]]; then interactive=0
elif (( interactive && !unattended )) && [[ -t 0 && -t 1 ]]; then
    if [[ "$(uname -s)" == Darwin ]] && have osascript; then
        target="$(osascript -e 'POSIX path of (choose folder with prompt "Choose recovery target outside the backup store")' 2>/dev/null)" || exit 0
    else read -r -p 'Recovery target (absolute path; blank cancels): ' target; fi
    [[ -n "$target" ]] || exit 0
else fail 'An explicit --target-root is required for unattended recovery.'; fi
[[ "$target" == /* && "$origin" == /* && ( -z "$store" || "$store" == /* ) ]] || fail 'Use absolute target, record and store paths.'
have gawk || fail 'Install GNU awk (gawk) locally before recovery.'
if [[ "$(locale charmap 2>/dev/null)" != UTF-8 ]]; then
    if [[ "$(LC_ALL=C.UTF-8 locale charmap 2>/dev/null)" == UTF-8 ]]; then export LC_ALL=C.UTF-8
    elif [[ "$(LC_ALL=en_US.UTF-8 locale charmap 2>/dev/null)" == UTF-8 ]]; then export LC_ALL=en_US.UTF-8
    else fail 'A UTF-8 locale is required for portable path comparisons.'; fi
fi
export FB_PATH_KEYS="$kit_dir/path-keys.tsv"
[[ -r "$FB_PATH_KEYS" && -r "$kit_dir/path-keys.awk" ]] || fail 'Required path comparison helpers are missing.'
[[ -f "$kit_dir/KIT.sha256" && ! -L "$kit_dir/KIT.sha256" ]] || fail 'Required recovery kit inventory is missing.'
gawk '$0 !~ /^[0-9a-f]{64}  [A-Za-z0-9._-]+$/ || seen[$2]++ {exit 1}' "$kit_dir/KIT.sha256" || fail 'Invalid recovery kit inventory.'
if have sha256sum; then
    (cd -- "$kit_dir" && sha256sum --check --strict KIT.sha256 >/dev/null 2>&1) || fail 'Recovery kit is mixed/incomplete; use RECOVERY.previous with explicit record/store roots.'
elif have shasum; then
    (cd -- "$kit_dir" && shasum -a 256 --check KIT.sha256 >/dev/null 2>&1) || fail 'Recovery kit is mixed/incomplete; use RECOVERY.previous with explicit record/store roots.'
else fail 'SHA-256 checking (sha256sum or shasum) is required for kit validation.'; fi
for member in RECONSTRUCT.ps1 reconstruct.sh reconstruct-core.sh path-keys.awk path-keys.tsv FileBackup.Common.psm1 System.IO.Hashing.dll; do
    gawk -v member="$member" '$2==member {found=1} END{exit !found}' "$kit_dir/KIT.sha256" || fail 'Required kit inventory member is missing.'
done
have xxhsum || have xxh128sum || fail 'Install xxHash >=0.8 locally before recovery.'
ordinary_ancestors() {
    local p="$1"
    while [[ -n "$p" && "$p" != / ]]; do
        [[ ! -L "$p" ]] || return 1
        p="${p%/*}"; [[ -n "$p" ]] || p=/
    done
}
valid_relative() {
    [[ -n "$1" && "$1" != /* && "$1" != *\\* && "$1" != *:* && "$1" != *$'\037'* && "$1" != *$'\n'* && "$1" != *$'\r'* ]] || return 1
    case "/$1/" in */../*|*/./*|*//*) return 1;; esac
}
if ! ordinary_ancestors "$origin" || ! ordinary_ancestors "$target"; then fail 'Redirected record/target ancestry is unsafe.'; fi
origin="$(canon "$origin")" || fail 'Cannot resolve record root.'
if [[ -z "$store" ]]; then
    if [[ "${origin##*/}" == CurrentBackup ]]; then store="$(dirname -- "$origin")"
    elif [[ "$(basename -- "$(dirname -- "$origin")")" == BackupHistory && "${origin##*/}" =~ ^[0-9]{4}(_[0-9]{2}){5}(_[0-9]+)?$ ]]; then store="$(dirname -- "$(dirname -- "$origin")")"
    else fail 'Specify --store-root for a kit outside its state folder.'; fi
fi
ordinary_ancestors "$store" || fail 'Redirected store ancestry is unsafe.'
store="$(canon "$store")" || fail 'Cannot resolve store.'
target="$(canon "$target")" || fail 'Cannot resolve target.'
for protected in "$store" "$origin" "$kit_dir"; do
    is_inside "$target" "$protected"; inside_status=$?
    (( inside_status == 1 )) || fail 'Target overlaps protected store/records/kit, or containment is unavailable.'
    is_inside "$protected" "$target"; inside_status=$?
    (( inside_status == 1 )) || fail 'Target contains protected store/records/kit, or containment is unavailable.'
done
manifest="$origin/MANIFEST.csv$suffix"; directories="$origin/DIRECTORIES.csv$suffix"
[[ -f "$manifest" && ! -L "$manifest" ]] || fail 'Selected file definitions are unavailable.'
scratch="$(mktemp -d "${TMPDIR:-/tmp}/filebackup-recovery.XXXXXXXX")" || fail 'Cannot allocate scratch.'
temporary=''
# shellcheck disable=SC2317 # called by EXIT trap
cleanup_native() { [[ -z "$temporary" ]] || rm -f -- "$temporary"; rm -f -- "$scratch/files" "$scratch/dirs" "$scratch/accepted" "$scratch/metadata-errors"; rmdir -- "$scratch"; }
trap cleanup_native EXIT
# Paths/control characters cannot cross the line-oriented script protocol. Reject
# malformed record shapes before writing any target output; never drop a bad row.
parse_native() {
    gawk -f "$kit_dir/path-keys.awk" -v expected="$2" -v count="$3" -e '
      function unq(s) { if(s ~ /^".*"$/) { s=substr(s,2,length(s)-2);gsub(/""/,"\"",s) } return s }
      BEGIN { load_path_keys(ENVIRON["FB_PATH_KEYS"]); FPAT="([^,]*)|(\"([^\"]|\"\")*\")" }
      { sub(/\r$/,""); if(NR==1) { h=$0;gsub(/"/,"",h);if(h!=expected)exit 2;next }
        if(NF!=count)exit 2;
        for(i=1;i<=NF;i++){v[i]=unq($i);if(v[i] ~ /[[:cntrl:]]/)exit 2}
        if(count==9) {
          if(v[2]=="" || v[2] ~ /(^\/|[\\:*?"<>|]|(^|\/)\.\.?($|\/)|\/\/|[ .](\/|$))/ || v[3] !~ /^[0-9]+$/ || length(v[3])>18 || v[5] !~ /^[0-9A-F]{32}$/ || v[7]!="Hash" || (v[6]!="Yes" && v[6]!="No"))exit 2;
          key=path_key(v[2]);if(key in seen)exit 2;seen[key]=1; total+=v[3];if(v[3]>largest)largest=v[3]
        }
        for(i=1;i<=NF;i++)printf "%s%s",v[i],(i==NF?"\n":"\037")
      }
      END {if(NR==0)exit 2;if(count==9)for(key in seen){p=key;while(sub(/\/[^/]+$/, "", p))if(p in seen)exit 2}}
    ' "$1"
}
parse_native "$manifest" 'DataPath,RelativePath,Length,LastWriteTimeStr,xxH2Hash,Compressed,StoredAsHashSize,Duplicate,MediaMBPerSec' 9 >"$scratch/files" || fail 'Malformed/colliding file records.'
if [[ ! -f "$directories" || -L "$directories" ]] || ! parse_native "$directories" 'RelativePath,Attributes,EntryKind,LinkTarget' 4 >"$scratch/dirs"; then
    metadata_finding 'Required directory/link metadata is unavailable; independent file recovery continues.'
    : >"$scratch/dirs"
fi
# Resolve cross-table conflicts once, rather than scanning all file rows for
# every directory. Bad supplemental records never prevent independent files.
gawk -f "$kit_dir/path-keys.awk" -F '\037' -v errors="$scratch/metadata-errors" -e '
    BEGIN { load_path_keys(ENVIRON["FB_PATH_KEYS"]) }
    function invalid(s) { return s=="" || s ~ /(^\/|[\\:*?"<>|]|(^|\/)\.\.?($|\/)|\/\/|[ .](\/|$))/ }
    ARGIND==1 { p=path_key($2); files[p]=1; while(sub(/\/[^/]+$/, "", p)) ancestors[p]=1; next }
    { rows[NR]=$0; p=path_key($1); counts[p]++; if($3=="Directory")ordinary[p]=1; if($3=="FolderLink")links[p]=1 }
    END { for(i in rows) {
        split(rows[i],v,FS); p=path_key(v[1]); bad=invalid(v[1]) || counts[p]!=1 || (p in files) || (v[3]!="Directory" && v[3]!="FolderLink");
        parent=p; while(sub(/\/[^/]+$/, "", parent))if((parent in files)||(parent in links))bad=1;
        if(v[3]=="FolderLink") { t=path_key(v[4]); if((p in ancestors) || (v[4]!="." && (invalid(v[4]) || (!(t in ordinary) && !(t in ancestors)) || (t in links))))bad=1 }
        else if(v[4]!="")bad=1;
        if(bad) print "Rejected supplemental metadata: "v[1] >errors; else print rows[i];
    }}
' "$scratch/files" "$scratch/dirs" >"$scratch/accepted" || fail 'Metadata validation failed.'
if [[ -s "$scratch/metadata-errors" ]]; then
    while IFS= read -r message; do metadata_finding "$message"; done <"$scratch/metadata-errors"
fi
mv -- "$scratch/accepted" "$scratch/dirs" || fail 'Cannot stage validated metadata.'
nearest="$target"; while [[ ! -d "$nearest" ]]; do nearest="$(dirname -- "$nearest")"; done
free_kib="$(df -Pk -- "$nearest" 2>/dev/null | gawk 'END {print $4}')"
required="$(gawk -F '\037' '{total+=$3+4096;if($3>largest)largest=$3} END{printf "%.0f",total+largest}' "$scratch/files")"
if [[ "$free_kib" =~ ^[0-9]+$ ]]; then
    gawk -v n="$required" -v f="$free_kib" 'BEGIN {exit !(f*1024 >= n)}' || host_fail 'Insufficient space for expanded output and temporary replacements.'
else log 'WARNING: target capacity is unavailable; recovery will stop on write failure.'; fi
[[ -n "$SEVEN_ZIP" ]] || find_seven_zip || true
timeout_tool=''; if have timeout; then timeout_tool=timeout; elif have gtimeout; then timeout_tool=gtimeout; fi
states=("$store/CurrentBackup")
for state in "$store/BackupHistory"/*; do
    [[ -d "$state" && ! -L "$state" && "${state##*/}" =~ ^[0-9]{4}(_[0-9]{2}){5}(_[0-9]+)?$ ]] && states+=("$state")
done
list_state_objects() {
    local folder="$1" sharded="$2" shard object name prefix
    if [[ -n "$sharded" ]]; then
        for shard in "$folder"/??; do
            [[ -d "$shard" && ! -L "$shard" ]] || continue
            for object in "$shard"/*; do
                [[ -f "$object" && ! -L "$object" ]] || continue
                name="${object##*/}"; prefix="${name:0:2}"
                [[ "${shard##*/}" == "${prefix,,}" ]] && printf '%s\0' "$object"
            done
        done
    else
        for object in "$folder"/*; do
            [[ -f "$object" && ! -L "$object" && "${object##*/}" =~ ^[2-9A-HJ-NP-Za-km-z]{22}_[2-9A-HJ-NP-Za-km-z]+(\..*)?$ ]] && printf '%s\0' "$object"
        done
    fi
}
declare -A native_index=()
for state in "${states[@]}"; do
    ordinary_ancestors "$state" || { finding 4 'Unsafe pool directory skipped.'; continue; }
    if [[ "$state" == "$store/CurrentBackup" ]]; then sharded=1; else sharded=''; fi
    while IFS=$'\037' read -r -d '' object_hash object_length candidate; do
        key="$object_hash|$object_length"
        native_index[$key]="${native_index[$key]-}$candidate"$'\n'
    done < <(list_state_objects "$state" "$sharded" | decode_hash_size_names "$state/" "$sharded")
done
# Determine prerequisites from actual object forms, before target mutation.
needs_extractor=0
declare -A inspected=()
while IFS=$'\037' read -r _data _rel length _stamp hash _compressed _storage _duplicate _media; do
    key="$hash|$length"
    [[ -z "${inspected[$key]+x}" ]] || continue
    inspected[$key]=1
    has_archive=0; raw_supply=''; raw_candidates=()
    while IFS= read -r candidate; do
        [[ -n "$candidate" ]] || continue
        if [[ "$(od -An -N6 -tx1 -- "$candidate" 2>/dev/null | tr -d ' \n')" == 377abcaf271c ]]; then
            if [[ "$(stat_size "$candidate")" == "$length" && "$(hash_file "$candidate")" == "$hash" ]]; then raw_supply="$candidate"
            else has_archive=1; fi
        elif [[ "$(stat_size "$candidate")" == "$length" ]]; then raw_candidates+=("$candidate"); fi
    done < <(printf '%s' "${native_index[$key]-}")
    if (( has_archive )); then
        if [[ -z "$raw_supply" ]]; then
            for candidate in ${raw_candidates[@]+"${raw_candidates[@]}"}; do
                if [[ "$(hash_file "$candidate")" == "$hash" ]]; then raw_supply="$candidate"; break; fi
            done
        fi
        if [[ -n "$raw_supply" ]]; then native_index[$key]="$raw_supply"$'\n'"${native_index[$key]-}"
        else needs_extractor=1; fi
    fi
done <"$scratch/files"
if (( needs_extractor )); then
    [[ -n "$SEVEN_ZIP" && -n "$timeout_tool" ]] || host_fail 'Compressed content requires local 7-Zip and GNU timeout; install them before recovery.'
    "$timeout_tool" -k 5 10 "$SEVEN_ZIP" i </dev/null >/dev/null 2>&1 || host_fail '7-Zip prerequisite check failed or timed out.'
fi
sync_tool=sync; if have gsync; then sync_tool=gsync; fi
# With file operands, GNU sync uses fsync; -f would flush the entire filesystem.
"$sync_tool" -f -- "$scratch/files" || host_fail 'GNU sync (coreutils) is required for durable target publication.'
output_mode="$(printf '%o' "$((0666 & ~$(umask)))")"
test_content() { [[ "$(stat_size "$1")" == "$2" && "$(hash_file "$1")" == "$3" ]]; }
restore_candidate() {
    local candidate="$1" destination="$2" length="$3" hash="$4" relative="$5" extract_status
    # Verify the staged bytes once; hashing the source before copying did not
    # replace this required verification and added a full read per raw file.
    if [[ "$(stat_size "$candidate")" == "$length" ]]; then
        if cp -- "$candidate" "$destination"; then
            test_content "$destination" "$length" "$hash" && return 0
        elif [[ "$(hash_file "$candidate")" == "$hash" ]]; then
            finding 4 "Copy failed: $relative"; return 1
        fi
    fi
    [[ "$(od -An -N6 -tx1 -- "$candidate" 2>/dev/null | tr -d ' \n')" == 377abcaf271c ]] || return 1
    if [[ -z "$SEVEN_ZIP" || -z "$timeout_tool" ]]; then finding 4 'Compressed content requires local 7-Zip and timeout (GNU coreutils).'; return 1; fi
    # Fixed program and positional paths; bound the complete extractor pipeline.
    # shellcheck disable=SC2016 # Arguments expand in the child Bash only.
    "$timeout_tool" -k 5 "$((300 + length / 1048576))" "$BASH" -c \
        'set -o pipefail; "$1" e -so -mmt=2 -y -- "$2" 2>/dev/null | head -c "$3"' \
        filebackup-extract "$SEVEN_ZIP" "$candidate" "$((length + 1))" </dev/null >"$destination"
    extract_status=$?
    if (( extract_status == 124 || extract_status == 137 )); then finding 4 "Extractor deadline exceeded: $relative"; return 1; fi
    (( extract_status == 0 )) && test_content "$destination" "$length" "$hash"
}
mkdir -p -- "$target" || host_fail 'Cannot create target.'
while IFS=$'\037' read -r _data rel length stamp hash _compressed _storage _duplicate _media; do
    [[ -n "$rel" ]] || continue
    dest="$target/$rel"; parent="${dest%/*}"
    if [[ -d "$dest" ]] || ! ordinary_ancestors "$dest" || ! mkdir -p -- "$parent"; then ((failed_files+=1)); finding 4 "Unsafe/unwritable target: $rel"; continue; fi
    temporary="$(mktemp "$parent/.filebackup.XXXXXXXX")" || { ((failed_files+=1)); finding 4 "Cannot stage target: $rel"; continue; }
    restored=0
    # Identity lookup already includes every decodable candidate across the pool.
    # Never extract unrelated objects once per missing logical file.
    while IFS= read -r candidate; do
        [[ -n "$candidate" ]] || continue
        if restore_candidate "$candidate" "$temporary" "$length" "$hash" "$rel"; then restored=1; break; fi
    done < <(printf '%s' "${native_index["$hash|$length"]-}")
    if (( restored )); then
        if [[ ! -d "$dest" ]] && ordinary_ancestors "$dest" && chmod "$output_mode" -- "$temporary" && "$sync_tool" -- "$temporary" && mv -f -- "$temporary" "$dest" && "$sync_tool" -- "$parent"; then
            ((restored_files+=1)); stamp_mtime "$dest" "$stamp" "$rel"
        else ((failed_files+=1)); finding 4 "Publication failed: $rel"; fi
    else
        ((failed_files+=1))
        if [[ -n "${native_index["$hash|$length"]-}" ]]; then finding 1 "No candidate passed content checks: $rel"
        else finding 1 "Content identity missing from pool: $rel"; fi
    fi
    rm -f -- "$temporary"; temporary=''
done <"$scratch/files"
declare -A metadata_seen=()
for phase in Directory FolderLink; do
    while IFS=$'\037' read -r rel attr kind mapping; do
        [[ -n "$rel" ]] || continue
        [[ "$kind" == "$phase" ]] || { [[ "$kind" == Directory || "$kind" == FolderLink ]] || metadata_finding "Unknown metadata kind: $rel"; continue; }
        if ! valid_relative "$rel" || [[ -n "${metadata_seen[$rel]+x}" ]]; then metadata_finding 'Invalid/duplicate directory metadata.'; continue; fi
        metadata_seen[$rel]=1
        full="$target/$rel"
        if ! ordinary_ancestors "$full"; then metadata_finding "Redirected metadata path: $rel"; continue; fi
        if [[ "$kind" == Directory ]]; then
            if [[ -n "$mapping" ]] || ! mkdir -p -- "$full"; then metadata_finding "Invalid/unwritable directory: $rel"; fi
            [[ -z "$attr" ]] || log "NOTE: Windows directory attributes not applied: $rel"
        else
            if [[ "$mapping" != . ]] && ! valid_relative "$mapping"; then metadata_finding "Invalid link mapping: $rel"; continue; fi
            mapped="$target/$mapping"
            if ! ordinary_ancestors "$mapped" || [[ ! -d "$mapped" || -e "$full" || -L "$full" ]]; then metadata_finding "Unavailable link mapping/path: $rel"; continue; fi
            parent="$(dirname -- "$full")"; mkdir -p -- "$parent" || { finding 4 "Cannot create link parent: $rel"; continue; }
            relative="$(gawk -v a="${rel%/*}" -v whole="$rel" -v b="$mapping" 'BEGIN{if(a==whole)a="";n=split(a,x,"/");m=split(b,y,"/");if(a=="")n=0;if(b==".")m=0;i=1;while(i<=n&&i<=m&&x[i]==y[i])i++;s="";for(j=i;j<=n;j++)s=s"../";for(j=i;j<=m;j++)s=s y[j]"/";sub(/\/$/,"",s);print s==""?".":s}')"
            ln -s -- "$relative" "$full" || metadata_finding "Host cannot recreate relative link: $rel"
        fi
    done <"$scratch/dirs"
done
# Persist newly created ancestor directories, timestamps and metadata entries too.
# One final filesystem flush replaces a whole-filesystem flush for every file.
"$sync_tool" -f -- "$target" || finding 4 'Final target sync failed.'
printf 'Recovery totals: restored=%s, failed=%s, required-metadata-findings=%s, exit=%s\n' "$restored_files" "$failed_files" "$metadata_failures" "$result"
if (( interactive && !unattended )) && [[ -t 0 && -t 1 ]]; then log "Recovery finished with exit $result"; read -r -p 'Press Enter to close' _answer; fi
exit "$result"
