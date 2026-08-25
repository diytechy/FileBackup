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
# The infrastructure-name skip used during hash recovery is applied ROOT-LEVEL
# ONLY (per the contract / AGENTS.md sec.3 "Infrastructure files are root-level
# only" — a nested user file named MANIFEST.csv is data, regression B6). The skip
# is a scan optimization, never a correctness gate: matching is by (hash,length).
# Reconstruct.ps1 originally over-skipped recursively; that was fixed 2026-07-03
# (TC-058), so both implementations now match the contract identically.
#
# reconstruct.sh is copied into the live backup and each snapshot. The restore
# ORIGIN is still named by --from (default: the current directory), rather than
# the script's location, so callers may also keep one external rescue copy and
# point it at any compatible backup.
#
# Exit codes (SR-040 — the normative table lives in README "Restore exit codes";
# Reconstruct.ps1 -ExitCode returns the same numbers):
#
#   0  complete — every manifest row restored.
#   1  INCOMPLETE, CONTENT — the remaining rows' bytes are not in the data
#      pool, or nothing in the pool reproduces them (ContentMismatch: the
#      written file disagreed with the row's Length/xxH2Hash — SR-056).
#   2  usage or precondition failure (bad args, missing or unrecognizable
#      manifest, target inside backup, missing tool, insufficient capacity).
#   3  manifest-witness verification failed — the index itself is untrustworthy;
#      NO file is written to the target (SR-039).
#   4  INCOMPLETE, HOST — rows failed for reasons on this machine, not in the
#      backup (unreadable search folder, 7z unavailable/unusable for an
#      archive candidate, extraction/copy I/O error on the row's OWN file, or
#      a WriteMismatch — a hash-PROVEN pool source whose written destination
#      disagrees: the backup holds the bytes, the write is broken). Retry
#      after fixing the host. Since kit revision 6 a POOL candidate that
#      fails to expand while 7z passes its self-test is data damage
#      (ContentMissing, exit 1).
#
# Precedence when several apply: 2 > 3 > 4 > 1.
#
# Implements: SR-030, SR-031, SR-032, SR-039, SR-040, SR-050 (LLR-030, LLR-031,
#             LLR-032, LLR-039, LLR-040, LLR-050)
#
# KitRevision: 6
# The revision of the restore kit bundled into a backup folder — the same marker
# Reconstruct.ps1 carries, bumped together whenever any kit-bundled file changes
# behaviour. Revision 2 was the first to decide a hash-recovered row's form from
# the FILE it located rather than the row's Compressed column (SR-050); revision
# 3 additionally tests every non-matching '.7z' candidate as RAW bytes, so a
# blank row for a genuine '.7z' SOURCE file is recoverable. Revision 4 honors
# the path sidecar only while the origin still lives inside the roots it
# records (a copied/moved store auto-detects instead of reading the original)
# and falls back to (hash,length) pool recovery when a row's named data file is
# missing. Revision 5 tests a '.7z'-named recovery candidate's raw bytes even
# when 7z is absent (raw needs no 7z), so a restore that requires no actual
# decompression no longer exits 4 demanding it. Revision 6 verifies EVERY
# written file against the row's (Length, xxH2Hash) — healing a mismatch from
# the pool once, else failing loudly as ContentMismatch (SR-056); and
# reclassifies an unexpandable POOL candidate as content damage (exit 1)
# rather than a host problem, while a row's own file failing to extract stays
# exit 4. (The -Force pool-scan and non-interactive-guard halves of revision 6
# are PowerShell-side: find(1) never skipped dot files and --target-root was
# always required here.) Restoring a snapshot with its OWN older kit still
# carries the defects fixed after it.

set -uo pipefail

readonly MANIFEST_NAME='MANIFEST.csv'
# Witness sidecar written by Write-Manifest (SR-038): five Key=Value lines,
# UTF-8 without BOM, LF-terminated — deliberately not JSON so this reader stays
# a grep/cut with no new tool on the Linux floor.
readonly WITNESS_NAME='MANIFEST.csv.meta'
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
    die_code 2 "$1"
}

die_code() {
    # Abort with an explicit SR-040 code: message to stderr and (if open) the log.
    # Used for 3 (witness verification failed) as well as die()'s 2.
    local code="$1" msg="$2"
    printf 'reconstruct.sh: %s\n' "$msg" >&2
    [[ -n "$LOG_PATH" ]] && printf 'ERROR: %s\n' "$msg" >>"$LOG_PATH" 2>/dev/null
    exit "$code"
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

# sevenzip_usable : proves this HOST can run 7z end-to-end (compress a tiny
# probe, expand it back). Separates "7z ran and rejected that archive" (data
# damage, ContentMissing/exit 1) from "7z cannot run or write here" (a HOST
# problem, exit 4) — without the split, a broken 7z made the locator report
# intact pool bytes as gone (2026-08-24 independent review, blocker 2).
# Cached per shell; find_by_hash runs in a subshell, so the cache lives for
# one locator call — one probe per locator call that meets an expand failure.
# Implements: SR-040 (LLR-040)
SEVENZIP_USABLE=''
sevenzip_usable() {
    if [[ -z "$SEVENZIP_USABLE" ]]; then
        local w
        w="$(mktemp -d)"
        printf 'selftest' > "$w/p.txt"
        if (cd "$w" && "$SEVEN_ZIP" a -bd -y p.7z p.txt >/dev/null 2>&1) \
           && sevenzip_to_file "$w/p.7z" "$w/o.txt" \
           && [[ "$(cat "$w/o.txt" 2>/dev/null)" == 'selftest' ]]; then
            SEVENZIP_USABLE=0
        else
            SEVENZIP_USABLE=1
        fi
        rm -rf "$w"
    fi
    return "$SEVENZIP_USABLE"
}

# restore_one <src> <dest> <needs_expand> <want_hash> <want_len> : the single
# write+verify implementation (SR-056, kit revision 6) — mirrors Reconstruct
# .ps1's Restore-OneRow. The restore loop calls it once per row, and at most
# once more after a pool recovery. Verification hashes the DESTINATION file:
# the locator (when one was involved) proved the POOL file, not this write.
# Length is compared first (cheap); the hash only when the length agrees.
# 0-byte rows hash like any other; a row with no hash restores unverified.
# On a mismatch the bad destination file is DELETED before returning.
#
# Returns 0 ok; 10 mismatch (RESTORE_GOT carries "<hash>/<len>" written, the
# bad destination is DELETED); 20 extraction failed; 21 copy failed; 22 the
# written file could not be read back for verification (stat/hash failure —
# a HOST condition; the file is KEPT, matching Restore-OneRow). Called
# DIRECTLY (never via command substitution) so the RESTORE_GOT global
# survives.
# Implements: SR-056 (LLR-056)
RESTORE_GOT=''
restore_one() {
    local src="$1" dest="$2" needs_expand="$3" want_hash="$4" want_len="$5" sz h
    RESTORE_GOT=''
    if (( needs_expand )); then
        if ! sevenzip_to_file "$src" "$dest"; then rm -f -- "$dest" 2>/dev/null; return 20; fi
    else
        cp -f -- "$src" "$dest" 2>/dev/null || return 21
    fi
    if [[ -z "$want_hash" || ! "$want_len" =~ ^[0-9]+$ ]]; then return 0; fi
    sz="$(stat -c '%s' -- "$dest" 2>/dev/null || echo -1)"
    if [[ "$sz" == "-1" ]]; then return 22; fi
    if [[ "$sz" == "$want_len" ]]; then
        h="$(hash_file "$dest" 2>/dev/null)" || return 22
    else
        h='(not hashed)'
    fi
    if [[ "$sz" == "$want_len" && "$h" == "$want_hash" ]]; then return 0; fi
    RESTORE_GOT="$h/$sz"
    rm -f -- "$dest" 2>/dev/null
    return 10
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

# find_by_hash <hash> <length> : locate a pool file whose content matches
# (hash,length). Plain candidates are filtered by size then hashed; .7z
# candidates are decompressed to a temp file and their PAYLOAD checked (their
# on-disk size/hash differ), and the ARCHIVE path is reported so the caller
# extracts it. Mirrors Find-DataFileByHash.
#
# Echoes ONE line:  <cause>\037<detail>\037<path>   where cause is
#   Found | ContentMissing | DependencyMissing | StorageUnreadable
# so the caller can tell "your bytes are gone" (exit 1) from "fix this host and
# retry" (exit 4) — SR-040. The cause travels in the OUTPUT rather than a global
# because callers use command substitution, which runs this in a subshell where
# any global assignment would be discarded. The two host causes are only
# reported when nothing matched: a successful recovery must never be downgraded
# by an unrelated bad folder.
#
# This locator never returns CandidateError (kit revision 6; SR-040 amendment
# 2026-08-24): it is only ever called when the row's own file is blank or
# missing, so no candidate it inspects is the row's own file — an archive
# candidate that fails to EXPAND is data damage, and a retry on this host cannot
# change the outcome. Such candidates are named inside ContentMissing's detail
# instead. A candidate whose bytes cannot be READ (hash_file fails) is
# StorageUnreadable — matching Reconstruct.ps1; before the 2026-08-25 Terra
# review fix it silently fell through to non-match, letting an unreadable pool
# file misreport surviving content as gone (exit 1 instead of 4).
# Only the restore loop raises CandidateError, for a row's OWN file.
#
# On Found the DETAIL field carries the located file's proven FORM — 'Archive'
# (the payload matched after expanding it) or 'Raw' (the file itself hashed) —
# which is what the caller must use to decide whether to decompress (SR-050).
# The row's Compressed column describes a file in the ROW's own folder, so for a
# blank-DataPath row it describes the wrong file: trusting it plain-copies 7z
# container bytes under the original name, or expands raw bytes. The search has
# already proven the form, so reporting it costs nothing.
#
# EVERY '.7z' candidate that does not yield the payload is re-tested as raw
# bytes before it is dropped: it may be raw content under a lying name (which
# fails to expand), or a genuine '.7z' SOURCE file stored raw (which expands
# fine, to something that is not this row's content). Free on the happy path.
# Mirrors Reconstruct.ps1 exactly.
find_by_hash() {
    local want_hash="$1" want_len="$2" folder f sz tmp h expand_failed
    local host_dep='' host_storage='' expand_fail_first='' expand_fail_n=0
    for folder in "${SEARCH_FOLDERS[@]}"; do
        if [[ ! -d "$folder" || ! -r "$folder" ]]; then
            host_storage="search folder '$folder' is absent or unreadable"
            continue
        fi
        while IFS= read -r -d '' f; do
            infra_skip "$f" "$folder" && continue
            if [[ "${f,,}" == *.7z ]]; then
                if [[ -z "$SEVEN_ZIP" ]]; then
                    # Its OWN bytes may still be the answer — a raw file under a
                    # '.7z' name, or a genuine '.7z' source stored verbatim —
                    # and testing that needs no 7z at all (kit revision 5).
                    sz="$(stat -c '%s' -- "$f" 2>/dev/null || echo -1)"
                    if [[ "$sz" == "$want_len" ]]; then
                        # A candidate that cannot be read records exactly ONE
                        # cause — 7z could not have helped read it (kit rev 6).
                        if ! h="$(hash_file "$f")"; then
                            host_storage="candidate '$f' could not be read"
                            continue
                        fi
                        if [[ "$h" == "$want_hash" ]]; then printf 'Found\037Raw\037%s' "$f"; return 0; fi
                    fi
                    host_dep="archive candidate '$f' needs 7z, which is not installed"
                    continue
                fi
                tmp="$(mktemp)"
                expand_failed=0
                if sevenzip_to_file "$f" "$tmp"; then
                    sz="$(stat -c '%s' -- "$tmp" 2>/dev/null || echo -1)"
                    if [[ "$sz" == "$want_len" ]]; then
                        h="$(hash_file "$tmp")"
                        if [[ "$h" == "$want_hash" ]]; then rm -f "$tmp"; printf 'Found\037Archive\037%s' "$f"; return 0; fi
                    fi
                    rm -f "$tmp"
                else
                    rm -f "$tmp"
                    expand_failed=1
                fi
                # The candidate's OWN bytes may be the answer, whether or not it
                # expanded: a '.7z' name over raw content would not expand, and a
                # genuine '.7z' SOURCE file stored raw expands fine but to
                # something that is not this row's content. Test raw before
                # dropping it (SR-050; WP5 review finding H2).
                sz="$(stat -c '%s' -- "$f" 2>/dev/null || echo -1)"
                if [[ "$sz" == "$want_len" ]]; then
                    if ! h="$(hash_file "$f")"; then
                        # Unreadable raw bytes: host class (Reconstruct.ps1
                        # parity); the expand verdict below still stands.
                        host_storage="candidate '$f' could not be read"
                        h=''
                    fi
                    if [[ -n "$h" && "$h" == "$want_hash" ]]; then printf 'Found\037Raw\037%s' "$f"; return 0; fi
                fi
                if (( expand_failed )); then
                    if sevenzip_usable; then
                        # 7z provably works here — the archive itself is
                        # damaged. See the header comment.
                        (( expand_fail_n++ ))
                        [[ -n "$expand_fail_first" ]] || expand_fail_first="$f"
                    else
                        # 7z cannot run/write on THIS host: the candidate is
                        # untested, not disproven (exit 4, precise remediation).
                        host_dep="7z at '${SEVEN_ZIP}' is present but not usable on this host (self-test failed); archive candidate '$f' could not be tested"
                    fi
                fi
            else
                sz="$(stat -c '%s' -- "$f" 2>/dev/null || echo -1)"
                [[ "$sz" == "$want_len" ]] || continue
                if ! h="$(hash_file "$f")"; then
                    # Unreadable candidate = host class, not "bytes are gone"
                    # (Reconstruct.ps1 parity; 2026-08-25 Terra review T1).
                    host_storage="candidate '$f' could not be read"
                    continue
                fi
                if [[ "$h" == "$want_hash" ]]; then printf 'Found\037Raw\037%s' "$f"; return 0; fi
            fi
        done < <(find "$folder" -type f -print0 2>/dev/null)
        # PINNED AS INTENT (SR-057): `find` never skips dot/hidden entries, so
        # the bash walk needs no -Force twin — and it deliberately runs WITHOUT
        # -L, so symlinks are never followed (link-immunity, option-3 design
        # record §3). Do not "improve" either property.
    done
    # A missing dependency outranks the other: it is the one with a precise
    # remediation. Mirrors Find-DataFileByHash's ordering.
    if   [[ -n "$host_dep"       ]]; then printf 'DependencyMissing\037%s\037' "$host_dep"
    elif [[ -n "$host_storage"   ]]; then printf 'StorageUnreadable\037%s\037' "$host_storage"
    elif (( expand_fail_n > 0 )); then
        printf 'ContentMissing\037no file with (hash=%s, len=%s) survives in the data pool. %d archive candidate(s) could not be expanded (7z passed its self-test on this host, so the archive itself is damaged): '\''%s'\''\037' \
            "$want_hash" "$want_len" "$expand_fail_n" "$expand_fail_first"
    else printf 'ContentMissing\037no file with (hash=%s, len=%s) survives in the data pool\037' "$want_hash" "$want_len"
    fi
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

# ---------------------------------------------------------------------------
# Manifest witness verification — SR-039 / LLR-039
# ---------------------------------------------------------------------------

# witness_value <file> <key> : echo the value of a Key=Value line, or empty.
# Tolerates a stray CR so a witness that survived a CRLF-mangling transfer still
# reads, and takes the first occurrence.
witness_value() {
    local f="$1" key="$2" line
    line="$(grep -m1 -E "^${key}=" -- "$f" 2>/dev/null)" || return 1
    printf '%s' "${line#*=}" | tr -d '\r'
}

# verify_manifest_witness <manifest> <require>
#   Compares the manifest on disk against its MANIFEST.csv.meta sidecar (Bytes,
#   Rows, XxH128). A mismatch or an unparseable sidecar aborts with exit 3
#   BEFORE anything is written to the target. An ABSENT sidecar is a backup
#   written before the witness contract: warn 'unverified index' and continue,
#   unless <require> is 1 (--require-witness), which makes absence an abort.
#   A sidecar whose Version is newer than this build verifies only the keys it
#   understands and warns — a witness from the future must never condemn a good
#   manifest.
# Implements: SR-039, LLR-039
verify_manifest_witness() {
    local manifest="$1" require="$2"
    local witness="${manifest%/*}/$WITNESS_NAME"
    local version want_bytes want_rows want_hash have_bytes have_rows have_hash

    if [[ ! -f "$witness" ]]; then
        if (( require )); then
            die_code 3 "no $WITNESS_NAME beside '$manifest' and --require-witness was given: the index cannot be verified."
        fi
        log "WARN: no $WITNESS_NAME beside the manifest — restoring against an UNVERIFIED index (backup predates the witness contract)."
        return 0
    fi

    version="$(witness_value "$witness" 'Version')"
    [[ "$version" =~ ^[0-9]+$ ]] || die_code 3 "'$witness' has no readable Version line; it is not a manifest witness."
    (( version > 1 )) && log "WARN: $WITNESS_NAME declares format version $version (newer than this build understands); verifying the known fields only."

    want_bytes="$(witness_value "$witness" 'Bytes')"
    want_rows="$(witness_value "$witness" 'Rows')"
    want_hash="$(witness_value "$witness" 'XxH128')"
    if [[ -z "$want_bytes" && -z "$want_rows" && -z "$want_hash" ]]; then
        die_code 3 "'$witness' carries none of Bytes, Rows or XxH128 — nothing to verify the manifest against."
    fi

    # Bytes is the cheap pre-check that names truncation precisely.
    if [[ "$want_bytes" =~ ^[0-9]+$ ]]; then
        have_bytes="$(stat -c '%s' -- "$manifest" 2>/dev/null || echo -1)"
        if [[ "$have_bytes" != "$want_bytes" ]]; then
            die_code 3 "manifest byte length disagrees with its witness: expected $want_bytes, found $have_bytes. The index is damaged; nothing was restored."
        fi
    fi

    # Rows is the operator-legible number ("expected 412 rows, found 118"). A
    # row-count disagreement is DEFERRED: the digest gets the final say, so a
    # counting-semantics difference between the writer and this reader can never
    # alone condemn a manifest the digest proves intact (WP1 plan sec.6 dec. 3).
    local rows_disagreement=''
    if [[ "$want_rows" =~ ^[0-9]+$ ]]; then
        have_rows="$(parse_manifest "$manifest" | wc -l | tr -d ' ')"
        if [[ "$have_rows" != "$want_rows" ]]; then
            rows_disagreement="manifest row count disagrees with its witness: expected $want_rows row(s), found $have_rows."
        fi
    fi

    # XxH128 is the authoritative check.
    if [[ -n "$want_hash" ]]; then
        have_hash="$(hash_file "$manifest")" || die_code 3 "could not hash '$manifest' to verify it against its witness."
        want_hash="$(printf '%s' "$want_hash" | tr '[:lower:]' '[:upper:]')"
        if [[ "$have_hash" != "$want_hash" ]]; then
            die_code 3 "manifest digest disagrees with its witness: expected $want_hash, found $have_hash. The index is damaged; nothing was restored."
        fi
    fi

    if [[ -n "$rows_disagreement" ]]; then
        if [[ -n "$want_hash" ]]; then
            log "WARN: $rows_disagreement The byte length and digest both match, so the index is intact — this is a row-counting difference, not damage."
        else
            die_code 3 "$rows_disagreement The witness carries no digest to defer to. The index is damaged; nothing was restored."
        fi
    fi

    log "Manifest verified against its witness (version $version, rows=${want_rows:-?}, bytes=${want_bytes:-?})."
}

usage() {
    cat >&2 <<'EOF'
Usage: reconstruct.sh --target-root DIR [--from DIR] [--backup-root DIR]
                      [--change-root DIR] [--seven-zip PATH] [--require-witness]

  --target-root DIR   Where to rebuild the tree (must be OUTSIDE the backup).
  --from DIR          Restore origin: a backup root or a Snapshot_<date> folder.
                      Default: the current directory.
  --backup-root DIR   Override the auto-detected backup root (the live data pool).
  --change-root DIR   Override the folder that holds the Snapshot_<date> siblings.
  --seven-zip PATH    Explicit 7z/7za binary (else auto-probed; needed only when
                      the backup has compressed rows).
  --require-witness   Refuse an origin with no MANIFEST.csv.meta witness instead
                      of restoring it with an 'unverified index' warning.
  -h, --help          This help.

Exit: 0 complete; 1 incomplete, content unrecoverable; 2 usage/precondition;
      3 manifest-witness verification failed (nothing written); 4 incomplete,
      host problem (retry after fixing this machine). Precedence: 2 > 3 > 4 > 1.
EOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    local from='' backup_root='' change_root='' seven_zip_opt='' require_witness=0
    TARGET_ROOT=''
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --require-witness) require_witness=1; shift ;;
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

    # Precedence: explicit flag > sidecar > auto-detection — and the sidecar
    # only applies while this ORIGIN still lives inside the roots it records.
    # For a store copied or moved, the recorded roots may still exist (the
    # original store on the same machine) and would silently point the restore
    # at the ORIGINAL instead of this copy. Reconstruct.ps1 applies the same
    # containment rule.
    local side_ok=0 origin_canon
    origin_canon="$(canon "$origin")"
    if [[ -n "$side_backup" && -d "$side_backup" ]]; then
        case "$origin_canon/" in "$(canon "$side_backup")"/*) side_ok=1 ;; esac
    fi
    if (( ! side_ok )) && [[ -n "$side_change" && -d "$side_change" ]]; then
        case "$origin_canon/" in "$(canon "$side_change")"/*) side_ok=1 ;; esac
    fi

    if   [[ -n "$backup_root" ]]; then backup_root="$(canon "$backup_root")"
    elif (( side_ok )) && [[ -n "$side_backup" && -d "$side_backup" ]]; then backup_root="$(canon "$side_backup")"
    else backup_root="$auto_backup"; fi

    if   [[ -n "$change_root" ]]; then change_root="$(canon "$change_root")"
    elif (( side_ok )) && [[ -n "$side_change" && -d "$side_change" ]]; then change_root="$(canon "$side_change")"
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

    # --- Verify the index itself before touching the target (SR-039) ---
    # Placed AFTER the exit-2 precondition checks (precedence 2 > 3) and BEFORE
    # the target is created, so a damaged index writes nothing at all — not even
    # the log — into the target.
    verify_manifest_witness "$authority" "$require_witness"

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

    # A non-empty, non-numeric Length is an unusable index value — refuse as a
    # PRECONDITION (exit 2) before writing anything, matching RECONSTRUCT.ps1
    # (whose capacity/verify casts throw the same class). Restoring such a row
    # unverified would silently disable SR-056 for it (2026-08-24 review, minor 7).
    local pre_i
    for (( pre_i=0; pre_i<nrows; pre_i++ )); do
        if [[ -n "${d_len[pre_i]}" && ! "${d_len[pre_i]}" =~ ^[0-9]+$ ]]; then
            die "manifest row '${d_rel[pre_i]}' carries a non-numeric Length '${d_len[pre_i]}' — the index is unusable; nothing was restored."
        fi
    done

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
        if [[ -r "$change_root" && -x "$change_root" ]]; then
            while IFS= read -r sn; do
                [[ -n "$sn" ]] && SEARCH_FOLDERS+=("$sn")
            done < <(find "$change_root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null \
                        | grep -E "$SNAPSHOT_RE" | sort -r | sed "s#^#$change_root/#")
        else
            # The snapshot tree exists but cannot be LISTED: silently shrinking
            # the pool would let a blank row whose only copy lives in a snapshot
            # report "your bytes are gone" (exit 1) for a host problem. The
            # unlistable root goes in as-is so find_by_hash's readability check
            # surfaces StorageUnreadable / exit 4 (2026-08-25 Terra review, T2;
            # Reconstruct.ps1 does the same).
            SEARCH_FOLDERS+=("$change_root")
        fi
    fi
    SEARCH_FOLDERS+=("$backup_root")

    # Any compressed row means 7z is mandatory (degrade only where PS degrades).
    if (( any_comp )) && [[ -z "$SEVEN_ZIP" ]]; then
        die "backup has compressed (.7z) rows but no 7z/7za found. Install: apt-get install p7zip-full / dnf install p7zip p7zip-plugins."
    fi

    # --- Restore loop: salvage everything, record every failure (SR-029/SR-031) ---
    # Failures are split by class so the exit code separates "your bytes are
    # gone" (1) from "fix this host and retry" (4) — SR-040.
    local -a unrestored=() unrestored_host=()
    local rel dest destdir src found fcause frest fdetail fpath located_form needs_expand recovered rc
    for (( i=0; i<nrows; i++ )); do
        # The PROVEN form of a hash-recovered file, which outranks the row's
        # Compressed column for that row (SR-050). Empty for a non-blank
        # DataPath, whose Compressed does describe its own folder's file.
        located_form=''
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
                # <cause>\037<detail>\037<path> — see find_by_hash.
                found="$(find_by_hash "${d_hash[i]}" "${d_len[i]}")"
                fcause="${found%%$'\037'*}"
                frest="${found#*$'\037'}"
                fdetail="${frest%%$'\037'*}"
                fpath="${frest#*$'\037'}"
                if [[ "$fcause" == 'Found' ]]; then
                    log "Hash-recovered '$rel' from '$fpath' (form: $fdetail)"
                    src="$fpath"
                    located_form="$fdetail"
                else
                    # One message per CAUSE, not one warning for all four (SR-040).
                    log "WARN: [$fcause] '$rel' — $fdetail"
                    case "$fcause" in
                        DependencyMissing|StorageUnreadable|CandidateError) unrestored_host+=("$rel") ;;
                        *) unrestored+=("$rel") ;;
                    esac
                    continue
                fi
            else
                log "WARN: no DataPath or hash for '$rel'."
                unrestored+=("$rel"); continue
            fi
        else
            src="$origin/$(to_posix "${d_data[i]}")"
        fi

        if [[ ! -f "$src" ]]; then
            # A non-blank DataPath is a locator HINT, not the content authority:
            # a run killed between Optimize-ChangeFolders' duplicate deletion
            # and its manifest rewrite leaves rows naming deleted files while
            # the keeper copy still sits in the pool. Try (hash,length)
            # recovery — the same machinery blank rows use — before declaring
            # the content missing (Reconstruct.ps1 does the same).
            recovered=0
            if [[ -n "${d_hash[i]}" && "${d_len[i]}" =~ ^[0-9]+$ ]]; then
                log "Data file '${src}' missing for '$rel'; attempting hash scan..."
                found="$(find_by_hash "${d_hash[i]}" "${d_len[i]}")"
                fcause="${found%%$'\037'*}"
                frest="${found#*$'\037'}"
                fdetail="${frest%%$'\037'*}"
                fpath="${frest#*$'\037'}"
                if [[ "$fcause" == 'Found' ]]; then
                    log "Hash-recovered '$rel' from '$fpath' (form: $fdetail)"
                    src="$fpath"
                    located_form="$fdetail"
                    recovered=1
                fi
            fi
            if (( ! recovered )); then
                log "WARN: missing data file '${src}' for '$rel' and no pool file matches its (hash,length)."
                unrestored+=("$rel"); continue
            fi
        fi

        # SR-050: a hash-recovered file is decided by the form the locator PROVED;
        # only a row resolved through its own DataPath is decided by its Compressed.
        if [[ -n "$located_form" ]]; then
            [[ "$located_form" == 'Archive' ]] && needs_expand=1 || needs_expand=0
        else
            [[ "${d_comp[i]}" == "Yes" ]] && needs_expand=1 || needs_expand=0
        fi

        # SR-056 (kit revision 6): EVERY restored row — expanded or copied, own
        # DataPath or hash-recovered — is verified against (Length, xxH2Hash)
        # after the write; on a mismatch the bad file is deleted, the
        # (hash,length) pool recovery attempted at most ONCE, and the result
        # verified again. A row that still cannot be verified counts into the
        # fail-loudly accounting as ContentMismatch (content class, exit 1) —
        # never reported as success. An extraction/copy failure on the row's
        # own file stays a HOST problem (SR-040), unchanged.
        rc=0; restore_one "$src" "$dest" "$needs_expand" "${d_hash[i]}" "${d_len[i]}" || rc=$?
        case "$rc" in
            0) ;;
            20) log "WARN: [CandidateError] '$rel' — 7z extraction failed (from '$src')."
                unrestored_host+=("$rel") ;;
            21) log "WARN: [CandidateError] '$rel' — copy failed (from '$src')."
                unrestored_host+=("$rel") ;;
            22) log "WARN: [CandidateError] '$rel' — restored file could not be read back for verification (host problem; file kept)."
                unrestored_host+=("$rel") ;;
            10)
                log "WARN: [ContentMismatch] '$rel' — restored bytes do not match the manifest (expected ${d_hash[i]}/${d_len[i]}, got $RESTORE_GOT); attempting pool recovery."
                if [[ -n "$located_form" ]]; then
                    # Already resolved through the locator, which hashes every
                    # candidate before returning it: the pool PROVABLY holds
                    # the bytes and the WRITE is what failed — host class
                    # (exit 4), not data loss (2026-08-24 review, major 3).
                    log "WARN: [WriteMismatch] '$rel' — the pool source '$src' was proven by hash, but the written destination disagrees (got $RESTORE_GOT) — a destination/write problem on this host."
                    unrestored_host+=("$rel"); continue
                fi
                found="$(find_by_hash "${d_hash[i]}" "${d_len[i]}")"
                fcause="${found%%$'\037'*}"
                frest="${found#*$'\037'}"
                fdetail="${frest%%$'\037'*}"
                fpath="${frest#*$'\037'}"
                if [[ "$fcause" == 'Found' ]]; then
                    log "Hash-recovered '$rel' from '$fpath' after a verify mismatch (form: $fdetail)"
                    [[ "$fdetail" == 'Archive' ]] && needs_expand=1 || needs_expand=0
                    rc=0; restore_one "$fpath" "$dest" "$needs_expand" "${d_hash[i]}" "${d_len[i]}" || rc=$?
                    case "$rc" in
                        0) ;;
                        10) # The recovery source was hash-proven by the
                            # locator: this second mismatch is a write problem
                            # on this host (exit 4) — the backup demonstrably
                            # still holds the bytes.
                            log "WARN: [WriteMismatch] '$rel' — the pool copy '$fpath' was proven by hash, but the written destination disagrees (got $RESTORE_GOT) — a destination/write problem on this host."
                            unrestored_host+=("$rel") ;;
                        20) log "WARN: [CandidateError] '$rel' — 7z extraction failed (from '$fpath')."
                            unrestored_host+=("$rel") ;;
                        22) log "WARN: [CandidateError] '$rel' — restored file could not be read back for verification (host problem; file kept)."
                            unrestored_host+=("$rel") ;;
                        *)  log "WARN: [CandidateError] '$rel' — copy failed (from '$fpath')."
                            unrestored_host+=("$rel") ;;
                    esac
                elif [[ "$fcause" == 'ContentMissing' ]]; then
                    log "WARN: [ContentMismatch] '$rel' — the bytes at '$src' do not reproduce the row, and no pool copy does. $fdetail"
                    unrestored+=("$rel")
                else
                    # DependencyMissing / StorageUnreadable: the pool may still
                    # hold a good copy this host could not check — host class.
                    log "WARN: [$fcause] '$rel' — $fdetail"
                    unrestored_host+=("$rel")
                fi ;;
        esac
    done

    # --- Fail loudly on any unrestored row (SR-029 / SR-031 / SR-040) ---
    # 4 outranks 1: the host class is the actionable one, so a wrapper retries
    # rather than alarming the user about lost data.
    local n_content=${#unrestored[@]} n_host=${#unrestored_host[@]} n_all
    n_all=$(( n_content + n_host ))
    if (( n_all > 0 )); then
        # ${a[@]+...} guards the empty-array expansion under `set -u` on bash 4.3.
        local all=(${unrestored[@]+"${unrestored[@]}"} ${unrestored_host[@]+"${unrestored_host[@]}"})
        log "ERROR: Reconstruction INCOMPLETE: $n_all file(s) could not be restored ($n_content content-missing, $n_host host): ${all[*]}"
        printf 'Reconstruction INCOMPLETE: %d file(s) could not be restored (%d content-missing, %d host).\n' \
            "$n_all" "$n_content" "$n_host" >&2
        if (( n_host > 0 )); then exit 4; fi
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
