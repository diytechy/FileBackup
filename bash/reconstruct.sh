#!/usr/bin/env bash
#
# reconstruct.sh — standalone Linux/bash restore for FileBackup backups (bash-v1)
#
# Rebuilds a source tree byte-for-byte from a FileBackup backup folder on a stock
# Linux box (a NAS, a rescue live-USB) with no PowerShell — using only commodity
# tools: bash 4+, GNU coreutils/gawk, xxhsum (xxHash >= 0.8), and 7z (p7zip) when
# the backup contains compressed rows. It is the Linux counterpart of the Windows
# Reconstruct.ps1 and honors the SAME on-disk contract (the SR registry + the
# MANIFEST.csv format are the single source of truth; only the implementation is
# duplicated). See docs/plans/bash-variant-plan.md and AGENTS.md sec.2/3.
#
#   * From a backup ROOT: that folder's MANIFEST.csv is the latest state.
#   * From a dated SNAPSHOT folder (name matches ^Snapshot_<date>): that
#     snapshot's own manifest is the authoritative point-in-time state, with each
#     file's bytes resolved by (xxH2Hash,Length) from the data pool = backup root
#     + all sibling snapshots (no newer manifest is ever overlaid).
#
# Restore semantics (mirror Reconstruct.ps1):
#   - a row's DataPath (Windows '\' mapped to '/') resolves against the origin
#     folder; a blank/missing DataPath recovers by content hash from the pool;
#   - .7z-stored rows (Compressed=Yes) are decompressed;
#   - the restore refuses a target inside the backup, pre-checks free capacity,
#     and FAILS LOUDLY: it restores everything recoverable, then exits non-zero
#     naming the count of rows it could not restore (a clean restore exits 0).
#
# DELIBERATE, DOCUMENTED DIVERGENCE from the current Reconstruct.ps1: the
# infrastructure-name skip used during hash recovery is applied ROOT-LEVEL ONLY
# (per the pinned contract / AGENTS.md sec.3 "Infrastructure files are root-level
# only" — a nested user file named MANIFEST.csv is data, regression B6). The
# PowerShell Find-DataFileByHash currently applies that skip recursively, which
# makes a nested infra-named file unrecoverable from a Mirror-mode snapshot; this
# script follows the contract, not that bug (recorded in docs/status.md).
#
# Because reconstruct.sh is one self-contained external file (it is NOT copied
# into each snapshot the way Reconstruct.ps1 is), the restore ORIGIN is named by
# --from (default: the current directory) rather than the script's own location.
#
# Exit codes: 0 = complete; 1 = restore INCOMPLETE (unrestored rows); 2 = usage
# or precondition failure (bad args, missing manifest, target inside backup,
# missing tool, insufficient capacity).
#
# Implements: SR-030, SR-031, SR-032 (LLR-030, LLR-031, LLR-032)

set -uo pipefail

readonly MANIFEST_NAME='MANIFEST.csv'
readonly SIDECAR_NAME='RECONSTRUCT.paths.json'
readonly LOG_NAME='RECONSTRUCT.log'
readonly SNAPSHOT_RE='^Snapshot_[0-9]{4}_[0-9]{2}_[0-9]{2}_[0-9]{2}_[0-9]{2}_[0-9]{2}'
# Infrastructure filenames excluded at the ROOT of each search folder during hash
# recovery (nested files with these names are user data — B6). Matches Reconstruct
# .ps1's $skip set (case-insensitive).
readonly INFRA_RE='^(MANIFEST|RECONSTRUCT|FileBackup\.Common|System\.IO\.Hashing|FileBackupState)'

# ---------------------------------------------------------------------------
# Small utilities
# ---------------------------------------------------------------------------

TARGET_ROOT=''
LOG_PATH=''

log() {
    # Append "<iso-ts> - <msg>" to the target-root log and echo to stderr.
    local msg="$1"
    local ts; ts="$(date --iso-8601=seconds 2>/dev/null || date)"
    if [[ -n "$LOG_PATH" ]]; then printf '%s - %s\n' "$ts" "$msg" >>"$LOG_PATH" 2>/dev/null; fi
    printf '%s\n' "$msg" >&2
}

die() {
    # Precondition/usage failure: message to stderr, exit 2.
    printf 'reconstruct.sh: %s\n' "$1" >&2
    [[ -n "$LOG_PATH" ]] && printf 'ERROR: %s\n' "$1" >>"$LOG_PATH" 2>/dev/null
    exit 2
}

have() { command -v "$1" >/dev/null 2>&1; }

# to_posix <path> : map Windows backslash separators to '/'. The manifest itself
# is never rewritten (SR-032) — only the value used for filesystem ops.
to_posix() { printf '%s' "${1//\\//}"; }

# hash_file <path> : xxHash128 of a file as 32-char UPPERCASE big-endian hex,
# byte-identical to Get-FileXxHash / System.IO.Hashing (proven by TC-053).
# Implements: SR-030, LLR-030
hash_file() {
    local f="$1" line
    if have xxh128sum; then
        line="$(xxh128sum -- "$f" 2>/dev/null)" || return 1
    elif have xxhsum; then
        line="$(xxhsum -H128 -- "$f" 2>/dev/null)" || return 1
    else
        return 3
    fi
    # Output is "<hex>  <name>"; take the first whitespace-delimited token.
    printf '%s' "${line%% *}" | tr '[:lower:]' '[:upper:]'
}

# find_seven_zip : echo the first available p7zip binary, or empty.
SEVEN_ZIP=''
find_seven_zip() {
    local c
    for c in 7z 7za 7zz; do
        if have "$c"; then SEVEN_ZIP="$c"; return 0; fi
    done
    return 1
}

# sevenzip_to_file <archive> <dest> : extract the payload of a .7z archive to
# <dest>. Extracts to a temp dir and takes the FIRST file — mirroring
# Expand-FileWithSevenZip — because a shared dedup archive can hold more than one
# identically-named-content entry (streaming with -so would concatenate them).
# Returns non-zero on failure.
sevenzip_to_file() {
    local archive="$1" dest="$2" tmpd first
    [[ -n "$SEVEN_ZIP" ]] || return 1
    tmpd="$(mktemp -d)" || return 1
    if ! "$SEVEN_ZIP" e -bd -y -o"$tmpd" -- "$archive" >/dev/null 2>&1; then rm -rf "$tmpd"; return 1; fi
    first="$(find "$tmpd" -type f 2>/dev/null | head -n1)"
    if [[ -z "$first" ]]; then rm -rf "$tmpd"; return 1; fi
    mv -f -- "$first" "$dest" 2>/dev/null || { rm -rf "$tmpd"; return 1; }
    rm -rf "$tmpd"
}

# ---------------------------------------------------------------------------
# Manifest parsing (RFC 4180 via gawk FPAT) — SR-032 / LLR-032
# ---------------------------------------------------------------------------
# Emits one line per DATA row (header skipped): the five columns the restore
# needs, in order:  DataPath | RelativePath | Length | xxH2Hash | Compressed,
# separated by the US control char (\x1f). A non-whitespace separator is required
# so `read` preserves an EMPTY leading DataPath field (a tab would be trimmed as
# IFS-whitespace, shifting every column). Quoted fields (which may contain commas
# or ""-escaped quotes) are unquoted; a trailing CR (CRLF manifests) and a leading
# UTF-8 BOM are tolerated. Filenames never contain \x1f or a newline.
# Implements: SR-032, LLR-032
parse_manifest() {
    local manifest="$1"
    gawk '
        function unq(s,   n) {
            # Strip a UTF-8 BOM if present on the very first byte.
            sub(/^\xef\xbb\xbf/, "", s)
            if (s ~ /^".*"$/) {
                s = substr(s, 2, length(s) - 2)
                gsub(/""/, "\"", s)
            }
            return s
        }
        BEGIN { FPAT = "([^,]*)|(\"([^\"]|\"\")*\")" }
        {
            sub(/\r$/, "")            # tolerate CRLF (re-splits under FPAT)
            if (NR == 1) next          # header row
            if (NF == 0) next
            printf "%s\037%s\037%s\037%s\037%s\n", unq($1), unq($2), unq($3), unq($5), unq($6)
        }
    ' "$manifest"
}

# ---------------------------------------------------------------------------
# Hash recovery over the data pool — SR-031 / LLR-031
# ---------------------------------------------------------------------------
SEARCH_FOLDERS=()   # populated in main(): sibling snapshots (desc) then backup root

# infra_skip <file> <folder> : true if <file> sits directly in <folder> (root
# level) AND its name matches an infrastructure name — the root-level-only rule.
infra_skip() {
    local f="$1" folder="$2" name dir
    name="$(basename -- "$f")"
    dir="$(dirname -- "$f")"
    [[ "$dir" == "$folder" ]] || return 1        # nested => always data (B6)
    shopt -s nocasematch
    local m=1; [[ "$name" =~ $INFRA_RE ]] && m=0
    shopt -u nocasematch
    return $m
}

# find_by_hash <hash> <length> : echo the path of a pool file whose content
# matches (hash,length). Plain candidates are filtered by size then hashed; .7z
# candidates are decompressed to a temp file and their PAYLOAD checked (their
# on-disk size/hash differ), and the ARCHIVE path is echoed so the caller extracts
# it. Empty output = not found. Mirrors Find-DataFileByHash.
find_by_hash() {
    local want_hash="$1" want_len="$2" folder f sz tmp h
    for folder in "${SEARCH_FOLDERS[@]}"; do
        [[ -d "$folder" ]] || continue
        while IFS= read -r -d '' f; do
            infra_skip "$f" "$folder" && continue
            if [[ "${f,,}" == *.7z ]]; then
                [[ -n "$SEVEN_ZIP" ]] || continue
                tmp="$(mktemp)"
                if sevenzip_to_file "$f" "$tmp"; then
                    sz="$(stat -c '%s' -- "$tmp" 2>/dev/null || echo -1)"
                    if [[ "$sz" == "$want_len" ]]; then
                        h="$(hash_file "$tmp")"
                        if [[ "$h" == "$want_hash" ]]; then rm -f "$tmp"; printf '%s' "$f"; return 0; fi
                    fi
                fi
                rm -f "$tmp"
            else
                sz="$(stat -c '%s' -- "$f" 2>/dev/null || echo -1)"
                [[ "$sz" == "$want_len" ]] || continue
                h="$(hash_file "$f")"
                if [[ "$h" == "$want_hash" ]]; then printf '%s' "$f"; return 0; fi
            fi
        done < <(find "$folder" -type f -print0 2>/dev/null)
    done
    return 1
}

# ---------------------------------------------------------------------------
# Path helpers
# ---------------------------------------------------------------------------

# canon <path> : absolute, symlink-free-ish path that need NOT exist yet.
canon() { realpath -m -- "$1" 2>/dev/null || printf '%s' "$1"; }

# is_inside <child> <parent> : true if child == parent or is nested under it,
# compared as canonical paths with a trailing separator (so 'bk' vs 'bk-restore'
# do not falsely match). Mirrors Reconstruct.ps1's Test-PathIsInside.
is_inside() {
    local c p
    c="$(canon "$1")/"
    p="$(canon "$2")/"
    [[ "$c" == "$p"* ]]
}

usage() {
    cat >&2 <<'EOF'
Usage: reconstruct.sh --target-root DIR [--from DIR] [--backup-root DIR]
                      [--change-root DIR] [--seven-zip PATH]

  --target-root DIR   Where to rebuild the tree (must be OUTSIDE the backup).
  --from DIR          Restore origin: a backup root or a Snapshot_<date> folder.
                      Default: the current directory.
  --backup-root DIR   Override the auto-detected backup root (the live data pool).
  --change-root DIR   Override the folder that holds the Snapshot_<date> siblings.
  --seven-zip PATH    Explicit 7z/7za binary (else auto-probed; needed only when
                      the backup has compressed rows).
  -h, --help          This help.

Exit: 0 complete; 1 restore incomplete (unrestored rows named); 2 usage/precondition.
EOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    local from='' backup_root='' change_root='' seven_zip_opt=''
    TARGET_ROOT=''
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --target-root) TARGET_ROOT="${2:?--target-root needs a value}"; shift 2 ;;
            --from)        from="${2:?--from needs a value}"; shift 2 ;;
            --backup-root) backup_root="${2:?--backup-root needs a value}"; shift 2 ;;
            --change-root) change_root="${2:?--change-root needs a value}"; shift 2 ;;
            --seven-zip)   seven_zip_opt="${2:?--seven-zip needs a value}"; shift 2 ;;
            -h|--help)     usage; exit 0 ;;
            *) usage; die "unknown argument: $1" ;;
        esac
    done

    [[ -n "$TARGET_ROOT" ]] || { usage; die "--target-root is required"; }

    # Tool preflight (SN-015 fail-loudly). 7z is checked later, only if needed.
    (( BASH_VERSINFO[0] >= 4 )) || die "bash 4+ required (found ${BASH_VERSION}); install a newer bash."
    have gawk || die "gawk is required (RFC-4180 manifest parsing). Install: apt-get install gawk / dnf install gawk."
    { have xxh128sum || have xxhsum; } || die "xxhsum (xxHash >= 0.8) is required. Install: apt-get install xxhash / dnf install xxhash."
    if [[ -n "$seven_zip_opt" ]]; then
        # An explicit --seven-zip that is not a runnable command is treated as
        # absent, so a compressed backup dies up front with remediation (below)
        # rather than failing every .7z row one by one.
        if have "$seven_zip_opt" || [[ -x "$seven_zip_opt" ]]; then SEVEN_ZIP="$seven_zip_opt"; else SEVEN_ZIP=''; fi
    else
        find_seven_zip || true
    fi

    # --- Resolve the restore origin and the backup/change roots ---
    local origin
    if [[ -n "$from" ]]; then origin="$from"
    elif [[ -n "$backup_root" ]]; then origin="$backup_root"
    else origin="$PWD"; fi
    [[ -d "$origin" ]] || die "restore origin '$origin' is not a directory (pass --from)."
    origin="$(canon "$origin")"

    local origin_name is_snapshot=0
    origin_name="$(basename -- "$origin")"
    [[ "$origin_name" =~ $SNAPSHOT_RE ]] && is_snapshot=1

    # Auto-detected roots (mirror Reconstruct.ps1's folder-name logic).
    local auto_backup auto_change=''
    if (( is_snapshot )); then
        auto_change="$(dirname -- "$origin")"
        auto_backup="$(dirname -- "$auto_change")"
    else
        auto_backup="$origin"
    fi

    # A path sidecar (written for the Windows kit) only applies on Linux if its
    # paths actually resolve here — Windows paths won't, so they are ignored. The
    # plan pins overrides + auto-detection as the real Linux path.
    local side_backup='' side_change=''
    if [[ -f "$origin/$SIDECAR_NAME" ]]; then
        side_backup="$(sed -n 's/.*"BackupRoot"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' "$origin/$SIDECAR_NAME" | head -n1)"
        side_change="$(sed -n 's/.*"ChangeRoot"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' "$origin/$SIDECAR_NAME" | head -n1)"
        side_backup="${side_backup//\\\\//}"; side_change="${side_change//\\\\//}"
    fi

    # Precedence: explicit flag > resolvable sidecar > auto-detection.
    if   [[ -n "$backup_root" ]]; then backup_root="$(canon "$backup_root")"
    elif [[ -n "$side_backup" && -d "$side_backup" ]]; then backup_root="$(canon "$side_backup")"
    else backup_root="$auto_backup"; fi

    if   [[ -n "$change_root" ]]; then change_root="$(canon "$change_root")"
    elif [[ -n "$side_change" && -d "$side_change" ]]; then change_root="$(canon "$side_change")"
    else change_root="$auto_change"; fi

    local authority="$origin/$MANIFEST_NAME"
    [[ -f "$authority" ]] || die "no $MANIFEST_NAME in origin '$origin'. Point --from at a backup root or a Snapshot_<date> folder."

    # A non-empty but unparseable manifest must fail loudly, not silently restore
    # an empty tree (a scripted caller checks only the exit code). Validate the
    # header carries the schema's key columns — a legitimately empty backup still
    # has the full header row, so this only rejects a corrupt/wrong file.
    local hdr
    hdr="$(head -n1 -- "$authority" | tr -d '\r')"
    hdr="${hdr#$'\xef\xbb\xbf'}"
    if [[ "$hdr" != *RelativePath* || "$hdr" != *xxH2Hash* ]]; then
        die "'$authority' is not a FileBackup manifest (unexpected header). Corrupt or wrong file."
    fi

    # --- Safety: refuse a target inside the backup or change root (SR-009) ---
    if is_inside "$TARGET_ROOT" "$backup_root"; then die "target '$TARGET_ROOT' is inside the backup root '$backup_root'."; fi
    if [[ -n "$change_root" && -d "$change_root" ]] && is_inside "$TARGET_ROOT" "$change_root"; then
        die "target '$TARGET_ROOT' is inside the change root '$change_root'."
    fi

    mkdir -p -- "$TARGET_ROOT" || die "cannot create target '$TARGET_ROOT'."
    TARGET_ROOT="$(canon "$TARGET_ROOT")"
    LOG_PATH="$TARGET_ROOT/$LOG_NAME"
    : >"$LOG_PATH" 2>/dev/null || true
    log "Reconstruction starting (origin=$origin, snapshot=$is_snapshot, backupRoot=$backup_root, changeRoot=${change_root:-<none>})"

    # --- Read the authoritative manifest into parallel arrays ---
    local -a d_data=() d_rel=() d_len=() d_hash=() d_comp=()
    local dp rp ln hh cp
    while IFS=$'\037' read -r dp rp ln hh cp; do
        [[ -n "$rp" ]] || continue
        d_data+=("$dp"); d_rel+=("$rp"); d_len+=("$ln"); d_hash+=("$hh"); d_comp+=("$cp")
    done < <(parse_manifest "$authority")

    local nrows=${#d_rel[@]}
    log "Manifest rows: $nrows"

    # --- Capacity pre-check (B11: exclude compressed rows; lengths are uncompressed) ---
    local need=0 any_comp=0 i
    for (( i=0; i<nrows; i++ )); do
        if [[ "${d_comp[i]}" == "Yes" ]]; then any_comp=1; continue; fi
        [[ "${d_len[i]}" =~ ^[0-9]+$ ]] && need=$(( need + d_len[i] ))
    done
    local avail
    avail="$(df -P -B1 -- "$TARGET_ROOT" 2>/dev/null | awk 'NR==2{print $4}')"
    if [[ "$avail" =~ ^[0-9]+$ ]]; then
        if (( avail < need )); then
            die "not enough free space on target. Required (uncompressed rows only): $need, Free: $avail."
        fi
        (( any_comp )) && log "NOTE: backup has compressed rows; capacity check excluded them (true need is higher)."
    fi

    # --- Build the data pool for hash recovery: snapshots (desc) then backup root ---
    SEARCH_FOLDERS=()
    if [[ -n "$change_root" && -d "$change_root" ]]; then
        while IFS= read -r sn; do
            [[ -n "$sn" ]] && SEARCH_FOLDERS+=("$sn")
        done < <(find "$change_root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null \
                    | grep -E "$SNAPSHOT_RE" | sort -r | sed "s#^#$change_root/#")
    fi
    SEARCH_FOLDERS+=("$backup_root")

    # Any compressed row means 7z is mandatory (degrade only where PS degrades).
    if (( any_comp )) && [[ -z "$SEVEN_ZIP" ]]; then
        die "backup has compressed (.7z) rows but no 7z/7za found. Install: apt-get install p7zip-full / dnf install p7zip p7zip-plugins."
    fi

    # --- Restore loop: salvage everything, record every failure (SR-029/SR-031) ---
    local -a unrestored=()
    local rel dest destdir src found
    for (( i=0; i<nrows; i++ )); do
        rel="$(to_posix "${d_rel[i]}")"
        [[ -n "$rel" ]] || continue
        dest="$TARGET_ROOT/$rel"
        # Refuse a RelativePath that escapes the target root (e.g. '..\..\x') — a
        # foreign/tampered manifest must not write outside where the user aimed.
        # Count it as unrestored so the run still fails loudly (defense in depth).
        if ! is_inside "$dest" "$TARGET_ROOT"; then
            log "WARN: '$rel' escapes the target root (path traversal); refusing."
            unrestored+=("$rel"); continue
        fi
        destdir="$(dirname -- "$dest")"
        mkdir -p -- "$destdir" 2>/dev/null

        if [[ -z "${d_data[i]}" ]]; then
            if [[ -n "${d_hash[i]}" && "${d_len[i]}" =~ ^[0-9]+$ ]]; then
                found="$(find_by_hash "${d_hash[i]}" "${d_len[i]}")"
                if [[ -n "$found" ]]; then
                    log "Hash-recovered '$rel' from '$found'"
                    src="$found"
                else
                    log "WARN: cannot recover '$rel' by hash (hash=${d_hash[i]}, len=${d_len[i]})."
                    unrestored+=("$rel"); continue
                fi
            else
                log "WARN: no DataPath or hash for '$rel'."
                unrestored+=("$rel"); continue
            fi
        else
            src="$origin/$(to_posix "${d_data[i]}")"
        fi

        if [[ ! -f "$src" ]]; then
            log "WARN: missing data file '${src}' for '$rel'."
            unrestored+=("$rel"); continue
        fi

        if [[ "${d_comp[i]}" == "Yes" ]]; then
            if ! sevenzip_to_file "$src" "$dest"; then
                log "WARN: 7z extraction failed for '$rel' (from '$src')."
                rm -f -- "$dest" 2>/dev/null
                unrestored+=("$rel"); continue
            fi
        else
            if ! cp -f -- "$src" "$dest" 2>/dev/null; then
                log "WARN: copy failed for '$rel' (from '$src')."
                unrestored+=("$rel"); continue
            fi
        fi
    done

    # --- Fail loudly on any unrestored row (SR-029 / SR-031) ---
    if (( ${#unrestored[@]} > 0 )); then
        log "ERROR: Reconstruction INCOMPLETE: ${#unrestored[@]} file(s) could not be restored: ${unrestored[*]}"
        printf 'Reconstruction INCOMPLETE: %d file(s) could not be restored.\n' "${#unrestored[@]}" >&2
        exit 1
    fi
    log "Reconstruction complete: $nrows file(s)."
    printf 'Reconstruction finished. See log: %s\n' "$LOG_PATH" >&2
    exit 0
}

# Run main only when executed directly, so bats can `source` this file to unit-
# test hash_file / parse_manifest / to_posix without triggering a restore.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
