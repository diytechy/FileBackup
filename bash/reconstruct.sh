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
#   - a LEGACY path-addressed store (a DataPath carrying a path separator) is
#     REFUSED as a precondition (exit 2), not restored: support for
#     pre-content-addressed stores was withdrawn at kit revision 7, and kit
#     revision 9 refuses pre-WP12 base-85-named stores too (SR-061/SR-069);
#   - every restored file is stamped with its OWN row's LastWriteTimeStr, so a
#     deduplicated row keeps its own mtime rather than the pool object's
#     (SR-066);
#   - the DIRECTORIES.csv sidecar recreates empty directories (SR-065); its
#     Windows folder attributes have no POSIX equivalent and are logged, not
#     applied;
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
#      an extraction failure on an ARCHIVE-SHAPED object (kit revision 8: an
#      object with no 7-Zip signature that reproduces neither form is content
#      damage, exit 1, not a retriable host problem - SR-068/SR-040), or
#      a WriteMismatch - a hash-PROVEN pool source whose written destination
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
# KitRevision: 11
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
# always required here.) Revisions 7, 8 and 9 changed behaviour here without
# this marker being bumped with them, and revision 9 - the base-57 name grammar
# (WP12) - was never emitted by EITHER restorer: the PowerShell marker stopped
# at 8 and this one at 6, so a store written by WP12 reports the kit it carries
# as 8. That drift is corrected at revision 10 rather than back-dated, because
# the marker records what a bundled kit DOES, and a store's bundled copy cannot
# be rewritten after the fact (WP13, F-1). Revision 10 makes this restorer
# correct on a NON-GNU userland (SR-071): sizes, temp directories, timestamps,
# free space, snapshot enumeration and path canonicalisation no longer assume
# GNU coreutils, where they previously produced WRONG ANSWERS rather than loud
# failures - an intact manifest failing its witness with "found -1", a data pool
# silently missing every snapshot, or every compressed row blamed on 7-Zip. It
# also refuses a target path it cannot canonicalise instead of silently handing
# back the raw input, and clears the read-only bit on every restored file so a
# write-protected store cannot hand its protection to the restored tree.
# Restoring a snapshot with its OWN older kit still carries the defects fixed
# after it.

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
readonly INFRA_RE='^(MANIFEST|RECONSTRUCT|DIRECTORIES|FileBackup\.Common|System\.IO\.Hashing|FileBackupState)'
readonly DIR_SIDECAR_NAME='DIRECTORIES.csv'

# ---------------------------------------------------------------------------
# Small utilities
# ---------------------------------------------------------------------------

TARGET_ROOT=''
LOG_PATH=''

# Appended to each tool-floor refusal (SR-071): the same store restores through
# the PowerShell kit on any platform pwsh runs on, including macOS.
readonly ALT_PWSH_HINT="Alternatively restore with PowerShell 7: pwsh RECONSTRUCT.ps1 -TargetRoot DIR (install: https://aka.ms/powershell; macOS: brew install --cask powershell)."

# ---------------------------------------------------------------------------
# Portability shims (SR-071) — GNU vs BSD userlands
#
# The three gates in main() (bash 4+, gawk, xxhsum) make the FLOOR loud, but
# they let through a userland that HAS those three and still differs elsewhere:
# macOS with Homebrew, FreeBSD/TrueNAS. Every shim below existed as a bare GNU
# invocation whose `2>/dev/null` fallback was written for "the tool is absent",
# not "the tool behaves differently here" — so a BSD host did not fail loudly,
# it produced a WRONG ANSWER: an intact manifest failing its witness, a pool
# missing every snapshot, or every compressed row blamed on 7-Zip.
# ---------------------------------------------------------------------------

# stat_size <file> : file size in bytes, or -1. Replaces GNU-only `stat -c %s`.
#
# The style is probed ONCE against a known regular file (this script) and the
# probe REQUIRES NUMERIC OUTPUT rather than trusting an exit status: on GNU,
# `stat -f` means "filesystem status" and takes no argument, so a bare
# `stat -f '%z' -- /` probe SUCCEEDS whenever a file named '%z' happens to sit
# in the working directory — silently selecting the BSD branch on a GNU host
# (2026-08-28 independent review, T4). Validating the output removes any
# dependence on cwd contents. `wc -c` is the last-resort POSIX floor.
_STAT_STYLE=''
_stat_probe() {
    local out
    case "$1" in
        gnu) out="$(stat -c '%s' -- "$2" 2>/dev/null)" ;;
        bsd) out="$(stat -f '%z' -- "$2" 2>/dev/null)" ;;
    esac
    [[ "$out" =~ ^[0-9]+$ ]]
}
_detect_stat_style() {
    local probe="${BASH_SOURCE[0]}"
    if   [[ -f "$probe" ]] && _stat_probe gnu "$probe"; then _STAT_STYLE='gnu'
    elif [[ -f "$probe" ]] && _stat_probe bsd "$probe"; then _STAT_STYLE='bsd'
    else _STAT_STYLE='wc'
    fi
}
_detect_stat_style
stat_size() {
    local n
    case "$_STAT_STYLE" in
        gnu) n="$(stat -c '%s' -- "$1" 2>/dev/null)" ;;
        bsd) n="$(stat -f '%z' -- "$1" 2>/dev/null)" ;;
        *)   n="$(wc -c < "$1" 2>/dev/null | tr -d ' ')" ;;
    esac
    if [[ "$n" =~ ^[0-9]+$ ]]; then printf '%s' "$n"; else printf '%s' -1; fi
}

# iso_now : an ISO-8601 local timestamp. GNU's `--iso-8601=seconds` does not
# exist on BSD, where the old `|| date` fallback silently changed the
# RECONSTRUCT.log timestamp format. The explicit format string is POSIX.
iso_now() { date +%Y-%m-%dT%H:%M:%S%z 2>/dev/null || date; }

# make_tempdir : a private temp directory, or non-zero. GNU mktemp defaults the
# template; BSD mktemp requires one, so a bare `mktemp -d` is not portable. An
# explicit template is correct on both.
make_tempdir() { mktemp -d "${TMPDIR:-/tmp}/reconstruct.XXXXXX" 2>/dev/null; }

# make_tempfile : a private temp FILE, or non-zero. Same portability rule as
# make_tempdir - a bare `mktemp` has no template either, so BSD refuses it.
make_tempfile() { mktemp "${TMPDIR:-/tmp}/reconstruct.XXXXXX" 2>/dev/null; }

log() {
    # Append "<iso-ts> - <msg>" to the target-root log and echo to stderr.
    local msg="$1"
    local ts; ts="$(iso_now)"
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
    tmpd="$(make_tempdir)" || return 1
    [[ -n "$tmpd" && -d "$tmpd" ]] || return 1
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
        # An UNCHECKED mktemp here used to leave $w empty, so the probe was
        # written to "/p.txt" — the filesystem ROOT — and `rm -rf "$w"` cleaned
        # up nothing, while 7-Zip was misreported as unusable. That was a latent
        # defect on every platform, not only where mktemp needs a template.
        w="$(make_tempdir)"
        if [[ -z "$w" || ! -d "$w" ]]; then
            log "WARN: cannot create a temporary directory for the 7-Zip self-test (TMPDIR='${TMPDIR:-/tmp}')."
            SEVENZIP_USABLE=1
            return 1
        fi
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
    # A RESTORED TREE IS ORDINARY WRITABLE FILES (human ruling 2026-08-28).
    # `cp` gives a newly created destination the SOURCE's mode bits, so a
    # write-protected pool object would hand its read-only-ness straight to the
    # restored file — and a snapshot keeps the kit it was written with forever,
    # so a kit that lacks this clear can never be fixed once the store is
    # protected. Clearing here, at the single write choke point, covers the
    # expand path too and runs BEFORE verification and mtime stamping so both
    # operate on a writable file. A no-op until WP14 marks the store.
    chmod u+w -- "$dest" 2>/dev/null || true
    if [[ -z "$want_hash" || ! "$want_len" =~ ^[0-9]+$ ]]; then return 0; fi
    sz="$(stat_size "$dest")"
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
# Emits one line per DATA row (header skipped): the seven columns the restore
# needs, in manifest order:  DataPath | RelativePath | Length |
#   LastWriteTimeStr | xxH2Hash | Compressed | StoredAsHashSize,
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
            printf "%s\037%s\037%s\037%s\037%s\037%s\037%s\n", unq($1), unq($2), unq($3), unq($4), unq($5), unq($6), unq($7)
        }
    ' "$manifest"
}

# ---------------------------------------------------------------------------
# Directory sidecar parsing (SR-065 / LLR-065)
# ---------------------------------------------------------------------------
# Emits  RelativePath \037 Attributes  per data row of DIRECTORIES.csv. Same
# RFC 4180 handling as parse_manifest; the sidecar is advisory and unwitnessed,
# so a file that yields nothing simply produces no rows.
parse_dir_sidecar() {
    local sidecar="$1"
    gawk '
        function unq(s) {
            sub(/^\xef\xbb\xbf/, "", s)
            if (s ~ /^".*"$/) { s = substr(s, 2, length(s) - 2); gsub(/""/, "\"", s) }
            return s
        }
        BEGIN { FPAT = "([^,]*)|(\"([^\"]|\"\")*\")" }
        {
            sub(/\r$/, "")
            if (NR == 1) next
            if (NF == 0) next
            printf "%s\037%s\n", unq($1), unq($2)
        }
    ' "$sidecar"
}

# apply_dir_sidecar <origin> <target> : recreate the empty directories the
# manifest cannot describe (SR-065). Windows folder ATTRIBUTES travel in the
# sidecar too, but Hidden/System/ReadOnly/NotContentIndexed have no POSIX
# equivalent, so that half is reported rather than applied - a deliberate,
# stated platform divergence, not a silent one. Never fails the restore: the
# sidecar is advisory and the contract is still bytes at paths.
apply_dir_sidecar() {
    local origin="$1" target="$2"
    local sidecar="$origin/$DIR_SIDECAR_NAME"
    [[ -f "$sidecar" && -r "$sidecar" ]] || return 0
    local rel attr full made=0 skipped_attr=0 rows=0
    while IFS=$'\037' read -r rel attr; do
        [[ -n "$rel" ]] || continue
        rows=$(( rows + 1 ))
        rel="$(to_posix "$rel")"
        full="$target/$rel"
        # Opposite polarity to the SR-009 target guard: reject unless PROVABLY
        # inside, so an indeterminate answer refuses the row too.
        if ! is_inside "$full" "$target"; then
            log "WARN: directory row '$rel' escapes the target root or cannot be canonicalised (path traversal); refusing."
            continue
        fi
        if [[ ! -d "$full" ]]; then
            if mkdir -p -- "$full" 2>/dev/null; then made=$(( made + 1 ))
            else log "WARN: could not create directory '$rel'."; fi
        fi
        [[ -n "$attr" ]] && skipped_attr=$(( skipped_attr + 1 ))
    done < <(parse_dir_sidecar "$sidecar")
    (( rows == 0 )) && return 0
    log "Directory sidecar: $rows row(s), $made directory(ies) created."
    if (( skipped_attr > 0 )); then
        log "NOTE: $skipped_attr directory row(s) carry Windows folder attributes (Hidden/System/ReadOnly/NotContentIndexed). They have no POSIX equivalent and were NOT applied."
    fi
    return 0
}

# stored_object_form <path> <want_hash> <want_len> : 'Archive' or 'Raw', decided
# from the BYTES rather than the row's Compressed column (SR-068). Twin of
# Common's Get-StoredObjectForm; see that function for the reasoning.
#
#   1. No 7-Zip signature in the first six bytes -> Raw, conclusively (the
#      engine never writes a compressed object without one).
#   2. Signature present: either an archive WE created, or the user's OWN
#      already-compressed file stored raw (SR-004 never re-compresses those, and
#      such a source can be named anything, so the extension proves nothing).
#      Length differing from the row's settles it as Archive; lengths equal ask
#      the hash, and a match means the bytes ARE the content, i.e. Raw.
stored_object_form() {
    local f="$1" want_hash="$2" want_len="$3" sig sz
    [[ -f "$f" ]] || { printf 'Missing'; return 0; }
    # od rather than head|xxd: no pipeline, and it is in coreutils everywhere.
    sig="$(od -An -N6 -tx1 -- "$f" 2>/dev/null | tr -d ' \n')"
    if [[ "$sig" != '377abcaf271c' ]]; then printf 'Raw'; return 0; fi
    [[ "$want_len" =~ ^[0-9]+$ ]] || { printf 'Archive'; return 0; }
    sz="$(stat_size "$f")"
    [[ "$sz" == "$want_len" ]] || { printf 'Archive'; return 0; }
    [[ -n "$want_hash" ]] || { printf 'Archive'; return 0; }
    if [[ "$(hash_file "$f" 2>/dev/null)" == "$want_hash" ]]; then printf 'Raw'; else printf 'Archive'; fi
}

# stamp_mtime <dest> <lastwritetimestr> <rel> : apply the row's OWN modification
# time (SR-066). Called only after the SR-056 verification passes, so a file
# that was deleted and re-recovered never keeps a stamp from the failed attempt.
# Never fatal - the bytes are already correct and verified by the time this
# runs. GNU date parses the manifest's ISO-8601 round-trip form ('O', 7-digit
# fractional seconds plus offset) directly; leaner userlands do not, so a
# fraction-stripped retry precedes the warning.
stamp_mtime() {
    local dest="$1" stamp="$2" rel="$3" trimmed
    [[ -n "$stamp" ]] || return 0
    touch -d "$stamp" -- "$dest" 2>/dev/null && return 0
    trimmed="$(printf '%s' "$stamp" | sed -E 's/\.[0-9]+//')"
    if [[ "$trimmed" != "$stamp" ]]; then
        touch -d "$trimmed" -- "$dest" 2>/dev/null && return 0
    fi
    # POSIX `touch -t` fallback (SR-071): where neither -d form parses, the
    # stamp is otherwise LOST SILENTLY and every restored file carries the
    # RESTORE time — a quiet SR-066 violation on any host without GNU touch.
    #
    # -t takes LOCAL wall-clock digits, so this converts only where it can do so
    # WITHOUT date arithmetic: a UTC stamp is applied under TZ=UTC, and an
    # offset that equals this host's current offset is applied as-is. Any other
    # offset would need real calendar arithmetic to normalise, so it keeps the
    # warning rather than writing a time that is wrong by the difference.
    if stamp_mtime_posix "$dest" "$trimmed"; then return 0; fi
    log "WARN: could not stamp LastWriteTime on '$rel' from '$stamp' (content is correct and verified)."
    return 0
}

# stamp_mtime_posix <dest> <iso-stamp-without-fraction> : apply via `touch -t`,
# or return non-zero when the stamp cannot be parsed.
#
# `touch -t` takes LOCAL wall-clock digits with no way to state an offset, so the
# offset is carried by TZ instead. POSIX TZ states how much to ADD to local time
# to reach UTC, which is the OPPOSITE sign to ISO-8601: '-06:00' becomes
# 'UTC+6:00'. That converts every offset exactly, with no calendar arithmetic
# and no rollover to get wrong.
#
# An earlier version refused any offset that was neither UTC nor the host's own,
# reasoning that losing the stamp beat writing a wrong one. Both are bad: a
# backup written in a different timezone from the restore host is entirely
# ordinary, so on BSD that silently dropped SR-066 for most real stores
# (2026-08-28 independent review, T5 - the defect was invisible until a BSD
# `touch` shim was added and the restored mtime actually compared).
stamp_mtime_posix() {
    local dest="$1" s="$2" y mo d h mi sec off digits sign hhmm tzs
    [[ "$s" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(Z|[+-][0-9]{2}:[0-9]{2})?$ ]] || return 1
    y="${BASH_REMATCH[1]}"; mo="${BASH_REMATCH[2]}"; d="${BASH_REMATCH[3]}"
    h="${BASH_REMATCH[4]}"; mi="${BASH_REMATCH[5]}"; sec="${BASH_REMATCH[6]}"
    off="${BASH_REMATCH[7]:-}"
    digits="${y}${mo}${d}${h}${mi}.${sec}"
    case "$off" in
        '')  touch -t "$digits" -- "$dest" 2>/dev/null && return 0 ;;
        Z)   TZ='UTC0' touch -t "$digits" -- "$dest" 2>/dev/null && return 0 ;;
        *)   sign="${off:0:1}"; hhmm="${off:1}"
             if [[ "$sign" == '-' ]]; then tzs='+'; else tzs='-'; fi
             TZ="UTC${tzs}${hhmm}" touch -t "$digits" -- "$dest" 2>/dev/null && return 0 ;;
    esac
    return 1
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

# is_volume_root <dir> : true when <dir> is the root of its own filesystem — '/'
# or a mount point. df's mount-point column is POSIX (-P) and needs no GNU-only
# flag. When detection FAILS this returns false, which is the safe direction:
# the folder is scanned as it was before SR-074 rather than skipped.
#
# This gate is what stops the exclusion reaching a user's own folder. Its
# PowerShell twin compares the root against GetPathRoot; without the equivalent
# check the predicate treats the first component below ANY root as a
# pseudo-folder, which silently dropped user files from a backup of an ordinary
# directory (2026-08-28 independent review, T2).
is_volume_root() {
    local d="$1" mp
    [[ "$d" == "/" ]] && return 0
    mp="$(df -P -- "$d" 2>/dev/null | awk 'NR==2{ for (i=1;i<=5;i++) $i=""; sub(/^ +/,""); print }')"
    [[ -n "$mp" && "$mp" == "$d" ]]
}

# volume_root_skip <file> <folder> : true if <file> lies inside one of the
# pseudo-folders Windows puts at the ROOT of every NTFS volume (SR-074). The
# twin of Test-IsVolumeRootPseudoPath, kept so both restorers scan the same pool
# over the same store. These names do not arise on a native POSIX filesystem,
# but they do on an NTFS volume mounted here — the borrowed-laptop case SN-022
# exists for. Root-level ONLY, matching the B6 rule: a nested folder carrying
# one of these names is ordinary data. The CALLER must have established that
# <folder> is a volume root (see is_volume_root).
volume_root_skip() {
    local f="$1" folder="$2" rel first
    rel="${f#"$folder"/}"
    [[ "$rel" != "$f" ]] || return 1             # not under this folder at all
    first="${rel%%/*}"
    shopt -s nocasematch
    local m=1
    # shellcheck disable=SC2016  # the '$' in $RECYCLE.BIN is literal, not an expansion
    [[ "$first" == 'System Volume Information' || "$first" == '$RECYCLE.BIN' ]] && m=0
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
        # Once per folder, not once per candidate: df is a process each time.
        local folder_is_root=0
        is_volume_root "$folder" && folder_is_root=1
        while IFS= read -r -d '' f; do
            infra_skip "$f" "$folder" && continue
            (( folder_is_root )) && volume_root_skip "$f" "$folder" && continue
            if [[ "${f,,}" == *.7z ]]; then
                if [[ -z "$SEVEN_ZIP" ]]; then
                    # Its OWN bytes may still be the answer — a raw file under a
                    # '.7z' name, or a genuine '.7z' source stored verbatim —
                    # and testing that needs no 7z at all (kit revision 5).
                    sz="$(stat_size "$f")"
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
                # A BARE `mktemp` here is not portable, and this is the HASH
                # RECOVERY path - the one a snapshot restore leans on, because
                # its rows resolve by content rather than through their own
                # DataPath. When it failed, every compressed candidate looked
                # unexpandable and the run reported ContentMissing / exit 1:
                # "your bytes are gone", about an intact backup. A root restore
                # never showed it, because those rows go through
                # sevenzip_to_file instead - which is why only the
                # BSD+Compress+snapshot permutation caught this.
                if ! tmp="$(make_tempfile)" || [[ -z "$tmp" ]]; then
                    host_storage="cannot create a temporary file to expand candidate '$f' (TMPDIR='${TMPDIR:-/tmp}')"
                    continue
                fi
                expand_failed=0
                if sevenzip_to_file "$f" "$tmp"; then
                    sz="$(stat_size "$tmp")"
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
                sz="$(stat_size "$f")"
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
                sz="$(stat_size "$f")"
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

# canon <path> : absolute, symlink-resolved path that need NOT exist yet, on
# stdout. Returns NON-ZERO, printing nothing, when the path cannot be
# canonicalised safely on this host (SR-071).
#
# It used to end `|| printf '%s' "$1"` — silently handing back the RAW input
# when `realpath -m` was unavailable, which is how a BSD host (no `-m`) lost the
# SR-009 guard without saying so.
canon() {
    local p="$1" out head tail
    out="$(realpath -m -- "$p" 2>/dev/null)" && [[ -n "$out" ]] && { printf '%s' "$out"; return 0; }

    # --- Fallback for a userland without `realpath -m` (BSD/macOS) ---
    #
    # A '..' component is REFUSED rather than cancelled. Textual '..' reduction
    # is not path resolution: with /outside/link -> /backup, the kernel resolves
    #     /outside/link/../backup/victim  ->  /backup/victim   (INSIDE the backup)
    # while a lexical reduction yields /outside/backup/victim and is judged
    # OUTSIDE — walking a restore into the very root SR-009 exists to protect
    # (2026-08-28 independent review, T2; an earlier draft of this function had
    # exactly that hole). Doing it correctly means reimplementing realpath's
    # component-by-component walk; refusing costs an operator nothing, because a
    # restore target never needs '..'.
    case "/$p/" in */../*) return 1 ;; esac

    [[ "$p" == /* ]] || p="$PWD/$p"
    while [[ "$p" == *//*  ]]; do p="${p/\/\//\/}"; done      # '//' -> '/'
    while [[ "$p" == */./* ]]; do p="${p/\/.\//\/}"; done     # '/./' -> '/'
    while [[ "$p" == */.   ]]; do p="${p%/.}"; [[ -n "$p" ]] || p=/; done
    p="${p%/}"; [[ -n "$p" ]] || p=/

    # Resolve the deepest EXISTING ancestor with the shell's physical walk, then
    # re-append the tail. Sound because a path that does not exist cannot
    # contain a symlink, and the '..' check above guarantees the tail is inert.
    head="$p"; tail=''
    while [[ "$head" != / && ! -d "$head" ]]; do
        tail="${head##*/}${tail:+/$tail}"
        head="${head%/*}"
        [[ -n "$head" ]] || head=/
    done
    out="$(cd -P -- "$head" 2>/dev/null && pwd -P)" || return 1
    [[ -n "$out" ]] || return 1
    printf '%s' "${out%/}${tail:+/$tail}"
}

# is_inside <child> <parent> : TRI-STATE, because the safe answer differs by
# caller —
#     0  provably inside (child == parent or nested under it)
#     1  provably outside
#     2  INDETERMINATE: a path could not be canonicalised
# Compared as canonical paths with a trailing separator, so 'bk' vs 'bk-restore'
# do not falsely match. Every caller must handle 2 explicitly and take its own
# refusing branch; a boolean here would silently pick the wrong side at one of
# the two polarities (a target guard wants "refuse unless provably outside", a
# traversal guard wants "reject unless provably inside").
is_inside() {
    local c p
    c="$(canon "$1")" || return 2
    p="$(canon "$2")" || return 2
    [[ "$c/" == "$p/"* ]]
}

# ---------------------------------------------------------------------------
# The witness format version this kit writes and reads. 2 = the SR-069 base-57
# name grammar (WP12); 1 = the pre-WP12 base-85, space-separated grammar. A
# store declaring less than this is refused outright — see the SR-061 gate in
# restore_from(). Kept beside the witness code because that is what stamps it.
WITNESS_FORMAT_VERSION=2

# is_legacy_stored_name <datapath> : true when <datapath> is a PRE-WP12 stored
# object name. A POSITIVE test for the retired grammars, deliberately NOT the
# negation of "parses under SR-069" - see the SR-061 gate in restore_from()
# for why those two are not complements. Blank is never legacy: it means
# "recover by hash". Mirrors Test-LegacyStoredObjectName in
# FileBackup.Common.psm1, and tests/bash/name_grammar.bats holds them to a
# shared corpus case for case (TC-151).
#
# This kit deliberately carries NO "is it the current grammar?" predicate.
# It would be dead weight in a file bundled into every backup: the locator
# matches CONTENT, never names, so the only naming question this kit ever
# asks is whether a store is one it must refuse.
is_legacy_stored_name() {
    [[ -n "$1" ]] || return 1
    # A path separator: the pre-WP9 path-addressed form. The backslash is held
    # in a variable so a mangled pattern cannot silently match only '/', the
    # same care Reconstruct.ps1 takes - this guard must not fail open.
    local bs; bs=$'\134'
    [[ "$1" == */* || "$1" == *"$bs"* ]] && return 0
    # The base-85 form's space at index 16. Decisive: a WP12 name's first 22
    # characters are its hash field and are always alphanumeric.
    [[ ${#1} -ge 27 && "${1:16:1}" == ' ' ]]
}

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
    (( version > WITNESS_FORMAT_VERSION )) && log "WARN: $WITNESS_NAME declares format version $version (newer than this build understands); verifying the known fields only."

    want_bytes="$(witness_value "$witness" 'Bytes')"
    want_rows="$(witness_value "$witness" 'Rows')"
    want_hash="$(witness_value "$witness" 'XxH128')"
    if [[ -z "$want_bytes" && -z "$want_rows" && -z "$want_hash" ]]; then
        die_code 3 "'$witness' carries none of Bytes, Rows or XxH128 — nothing to verify the manifest against."
    fi

    # Bytes is the cheap pre-check that names truncation precisely.
    if [[ "$want_bytes" =~ ^[0-9]+$ ]]; then
        have_bytes="$(stat_size "$manifest")"
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

# ---------------------------------------------------------------------------
# Graphical target selection (SR-073) — reached ONLY via --pick-target
# ---------------------------------------------------------------------------

# Set when the target came from the picker rather than the command line: the
# one case where a human is provably watching, and therefore the only case in
# which this script holds the window open before exiting.
INTERACTIVE_TARGET=0

# pick_target_dir : echo a directory chosen in a graphical dialog, or return
# non-zero when no dialog is available or the operator cancelled. NEVER blocks
# without a dialog, and never invents a default — an empty result reaches the
# required-argument check and becomes usage + exit 2.
#
# $FILEBACKUP_PICKER overrides the probe with a command that prints a path; it
# exists so the bats suite can exercise this path headlessly, because a real
# dialog can never appear in CI.
pick_target_dir() {
    local out=''
    local prompt='Choose the folder to restore into (must be OUTSIDE the backup)'

    if [[ -n "${FILEBACKUP_PICKER:-}" ]]; then
        # Quoted: a picker path containing spaces would otherwise be word-split
        # and the first fragment executed (2026-08-28 independent review, T6).
        # The variable is ONE executable path, not a command line.
        out="$("$FILEBACKUP_PICKER" "$prompt" 2>/dev/null)" || return 1
    elif [[ "$(uname -s 2>/dev/null)" == 'Darwin' ]] && have osascript; then
        # macOS needs no extra package for this — osascript is part of the OS.
        out="$(osascript -e "POSIX path of (choose folder with prompt \"$prompt\")" 2>/dev/null)" || return 1
    elif [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
        if   have zenity;  then out="$(zenity --file-selection --directory --title="$prompt" 2>/dev/null)" || return 1
        elif have kdialog; then out="$(kdialog --getexistingdirectory "${HOME:-/}" --title "$prompt" 2>/dev/null)" || return 1
        elif have yad;     then out="$(yad --file --directory --title="$prompt" 2>/dev/null)" || return 1
        else return 1
        fi
    else
        return 1
    fi

    out="${out%$'
'}"
    out="${out%/}"                      # osascript returns a trailing slash
    [[ -n "$out" ]] || return 1
    printf '%s' "$out"
}

# hold_if_interactive : an EXIT trap, armed only when the picker supplied the
# target. A double-clicked launcher closes its window the instant the process
# ends, so the operator would never see the outcome. Deliberately NOT done in
# the launcher shell: a pause there would also fire for an automated no-argument
# caller and hang it (2026-08-28 independent review, T6). Here it can only fire
# on the branch that already proved a human is present.
hold_if_interactive() {
    local rc=$?
    (( INTERACTIVE_TARGET )) || return 0
    [[ -t 0 ]] || return 0
    printf '
Exited with code %s. Press Return to close.' "$rc" >&2
    read -r _ || true
    return 0
}

usage() {
    cat >&2 <<'EOF'
Usage: reconstruct.sh --target-root DIR [--from DIR] [--backup-root DIR]
                      [--change-root DIR] [--seven-zip PATH] [--require-witness]
                      [--pick-target]

  --target-root DIR   Where to rebuild the tree (must be OUTSIDE the backup).
  --from DIR          Restore origin: a backup root or a Snapshot_<date> folder.
                      Default: the current directory.
  --backup-root DIR   Override the auto-detected backup root (the live data pool).
  --change-root DIR   Override the folder that holds the Snapshot_<date> siblings.
  --seven-zip PATH    Explicit 7z/7za binary (else auto-probed; needed only when
                      the backup has compressed rows).
  --require-witness   Refuse an origin with no MANIFEST.csv.meta witness instead
                      of restoring it with an 'unverified index' warning.
  --pick-target       Choose the target folder in a graphical file dialog when
                      one is available (macOS 'choose folder', or zenity/kdialog
                      on Linux). Explicit by design: WITHOUT this flag a missing
                      --target-root is still a usage failure, never a prompt, so
                      an automated run can never start waiting on a human.
                      Cancelling, or having no dialog available, is usage + 2.
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
    local pick_target=0
    TARGET_ROOT=''
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --require-witness) require_witness=1; shift ;;
            --pick-target)     pick_target=1; shift ;;
            --target-root) TARGET_ROOT="${2:?--target-root needs a value}"; shift 2 ;;
            --from)        from="${2:?--from needs a value}"; shift 2 ;;
            --backup-root) backup_root="${2:?--backup-root needs a value}"; shift 2 ;;
            --change-root) change_root="${2:?--change-root needs a value}"; shift 2 ;;
            --seven-zip)   seven_zip_opt="${2:?--seven-zip needs a value}"; shift 2 ;;
            -h|--help)     usage; exit 0 ;;
            *) usage; die "unknown argument: $1" ;;
        esac
    done

    # A picker runs ONLY when explicitly asked for. A missing --target-root
    # without --pick-target stays what it has always been - usage, exit 2, never
    # a prompt - which is the twin of Reconstruct.ps1's -NonInteractive guard
    # (SR-016) and is asserted by exit_codes.bats. If the picker is unavailable
    # or the operator cancels, TARGET_ROOT stays empty and the required-argument
    # check below fires: loud, never a hang, never a silent default.
    if (( pick_target )) && [[ -z "$TARGET_ROOT" ]]; then
        TARGET_ROOT="$(pick_target_dir)" || TARGET_ROOT=''
        if [[ -n "$TARGET_ROOT" ]]; then
            INTERACTIVE_TARGET=1
            trap hold_if_interactive EXIT
        fi
    fi

    [[ -n "$TARGET_ROOT" ]] || { usage; die "--target-root is required"; }

    # Tool preflight (SN-015 fail-loudly). 7z is checked later, only if needed.
    # Each message names the macOS remediation too, because macOS ships bash 3.2
    # and none of these tools — and names the PowerShell alternative, because
    # RECONSTRUCT.ps1 restores the SAME store on any platform pwsh runs on. An
    # operator who cannot meet this floor is not out of options, and the moment
    # a restore fails is the wrong moment to have to work that out.
    (( BASH_VERSINFO[0] >= 4 )) || die "bash 4+ required (found ${BASH_VERSION}); install a newer bash. macOS: brew install bash (/bin/bash is 3.2). $ALT_PWSH_HINT"
    have gawk || die "gawk is required (RFC-4180 manifest parsing). Install: apt-get install gawk / dnf install gawk / brew install gawk. $ALT_PWSH_HINT"
    { have xxh128sum || have xxhsum; } || die "xxhsum (xxHash >= 0.8) is required. Install: apt-get install xxhash / dnf install xxhash / brew install xxhash. $ALT_PWSH_HINT"
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
    origin="$(canon "$origin")" || die "cannot canonicalise restore origin '$origin' on this host. Pass an absolute path containing no '..'."

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
    # An UNCANONICALISABLE sidecar root must not be treated as containing the
    # origin: with canon() now able to fail, an empty expansion would leave the
    # pattern "/*", which matches every absolute path and would honour a stale
    # sidecar for a store that has been copied away from it.
    local side_ok=0 origin_canon side_canon
    origin_canon="$(canon "$origin")" || die "cannot canonicalise restore origin '$origin' on this host."
    if [[ -n "$side_backup" && -d "$side_backup" ]] && side_canon="$(canon "$side_backup")"; then
        case "$origin_canon/" in "$side_canon"/*) side_ok=1 ;; esac
    fi
    if (( ! side_ok )) && [[ -n "$side_change" && -d "$side_change" ]] && side_canon="$(canon "$side_change")"; then
        case "$origin_canon/" in "$side_canon"/*) side_ok=1 ;; esac
    fi

    if   [[ -n "$backup_root" ]]; then backup_root="$(canon "$backup_root")" || die "cannot canonicalise backup root '$backup_root' on this host."
    elif (( side_ok )) && [[ -n "$side_backup" && -d "$side_backup" ]]; then backup_root="$(canon "$side_backup")" || die "cannot canonicalise backup root '$side_backup' on this host."
    else backup_root="$auto_backup"; fi

    if   [[ -n "$change_root" ]]; then change_root="$(canon "$change_root")" || die "cannot canonicalise change root '$change_root' on this host."
    elif (( side_ok )) && [[ -n "$side_change" && -d "$side_change" ]]; then change_root="$(canon "$side_change")" || die "cannot canonicalise change root '$side_change' on this host."
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
    # Tri-state: refuse unless the target is PROVABLY outside. An
    # indeterminate answer (a path this host cannot canonicalise) is a
    # precondition failure, never a pass — that is the polarity SR-009 needs.
    local inside_rc
    is_inside "$TARGET_ROOT" "$backup_root"; inside_rc=$?
    if (( inside_rc == 0 )); then die "target '$TARGET_ROOT' is inside the backup root '$backup_root'."; fi
    if (( inside_rc == 2 )); then
        die "cannot safely canonicalise '$TARGET_ROOT' or '$backup_root' on this host, so the target cannot be proven outside the backup. Pass an absolute target path containing no '..'."
    fi
    if [[ -n "$change_root" && -d "$change_root" ]]; then
        is_inside "$TARGET_ROOT" "$change_root"; inside_rc=$?
        if (( inside_rc == 0 )); then die "target '$TARGET_ROOT' is inside the change root '$change_root'."; fi
        if (( inside_rc == 2 )); then
            die "cannot safely canonicalise '$TARGET_ROOT' or '$change_root' on this host, so the target cannot be proven outside the change root. Pass an absolute target path containing no '..'."
        fi
    fi

    # --- Verify the index itself before touching the target (SR-039) ---
    # Placed AFTER the exit-2 precondition checks (precedence 2 > 3) and BEFORE
    # the target is created, so a damaged index writes nothing at all — not even
    # the log — into the target.
    verify_manifest_witness "$authority" "$require_witness"

    mkdir -p -- "$TARGET_ROOT" || die "cannot create target '$TARGET_ROOT'."
    TARGET_ROOT="$(canon "$TARGET_ROOT")" || die "cannot canonicalise target '$TARGET_ROOT' on this host. Pass an absolute path containing no '..'."
    LOG_PATH="$TARGET_ROOT/$LOG_NAME"
    : >"$LOG_PATH" 2>/dev/null || true
    log "Reconstruction starting (origin=$origin, snapshot=$is_snapshot, backupRoot=$backup_root, changeRoot=${change_root:-<none>})"

    # --- Read the authoritative manifest into parallel arrays ---
    local -a d_data=() d_rel=() d_len=() d_lwt=() d_hash=() d_comp=() d_form=()
    local dp rp ln lw hh cp sf
    while IFS=$'\037' read -r dp rp ln lw hh cp sf; do
        [[ -n "$rp" ]] || continue
        d_data+=("$dp"); d_rel+=("$rp"); d_len+=("$ln"); d_lwt+=("$lw")
        d_hash+=("$hh"); d_comp+=("$cp"); d_form+=("$sf")
    done < <(parse_manifest "$authority")

    local nrows=${#d_rel[@]}
    log "Manifest rows: $nrows"

    # A store this kit cannot read is refused, not restored (SR-061 / SR-069).
    # Writing to a path-addressed store went at WP9; kit revision 7 withdrew
    # READING it, and kit revision 9 (WP12) extends the same refusal to a
    # pre-WP12 CONTENT-ADDRESSED store, whose objects carry the old base-85,
    # space-separated names. Refused as a PRECONDITION, before any file is
    # restored. Mirrors Reconstruct.ps1 exactly.
    #
    # THREE markers, because no one of them is complete:
    #   1. StoredAsHashSize='Original' — a pre-content-addressed store (WP9).
    #      It does NOT identify a base-85 store: those say 'Hash', like ours.
    #   2. A witness declaring a format version below ours — the positive
    #      marker, and the only one that works on a manifest whose DataPath
    #      values are all blank. Only meaningful when a witness EXISTS: SR-039
    #      deliberately lets a witness-less store restore with a warning.
    #   3. A DataPath in a RETIRED grammar - a path separator (pre-WP9
    #      path-addressed), or a space at index 16 (the pre-WP12 base-85
    #      "<hash16> <len10><ext>" form). Catches a witness-less old store.
    #
    # Marker 3 is a POSITIVE test, NOT "does not parse under SR-069". Those are
    # not complements: a merely DAMAGED DataPath parses under neither grammar,
    # and SR-056's verify-and-heal machinery must get to answer for it - a
    # whole-store refusal would turn one repairable row into an unrestorable
    # backup. Refuse the old FORMAT; let damaged ROWS take the content path.
    #
    # A blank DataPath means "recover by hash" and is not tested by 3 — a blank
    # string carries no grammar. Benign: the locator matches CONTENT, so a store
    # reached through blank rows alone restores correctly whatever its objects
    # are named.
    local w_version
    if [[ -f "${authority%/*}/$WITNESS_NAME" ]]; then
        w_version="$(witness_value "${authority%/*}/$WITNESS_NAME" 'Version')"
        if [[ "$w_version" =~ ^[0-9]+$ ]] && (( w_version < WITNESS_FORMAT_VERSION )); then
            die "'$authority' is a pre-WP12 store: its manifest witness declares format version $w_version, and this kit (revision 9) writes and reads $WITNESS_FORMAT_VERSION — the SR-069 base-57 name grammar. This kit does not restore stores written under the older base-85 grammar (SR-061). Restore it with the kit bundled inside that backup folder, which was written by the build that produced it."
        fi
    fi

    local lg_i lg_form
    for (( lg_i=0; lg_i<nrows; lg_i++ )); do
        lg_form="$(printf '%s' "${d_form[lg_i]}" | tr '[:upper:]' '[:lower:]')"
        if [[ "$lg_form" == 'original' ]]; then
            die "'$authority' is not a store this kit can restore: row '${d_rel[lg_i]}' carries StoredAsHashSize='${d_form[lg_i]}'. This kit (revision 9) does not restore pre-content-addressed stores (SR-061). Restore it with the kit bundled inside that backup folder, which was written by the build that produced it."
        fi
        if is_legacy_stored_name "${d_data[lg_i]}"; then
            die "'$authority' is not a store this kit can restore: row '${d_rel[lg_i]}' names its data '${d_data[lg_i]}', a retired stored-object name. This kit (revision 9) restores only content-addressed stores using the SR-069 base-57 grammar (SR-061). Restore it with the kit bundled inside that backup folder, which was written by the build that produced it."
        fi
    done

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
    # GNU `-B1` gives bytes directly; BSD/macOS df has no -B, where this used to
    # yield nothing and the capacity precheck then skipped in SILENCE, so
    # SR-040's "insufficient capacity -> exit 2" never fired. POSIX `-Pk` is the
    # portable fallback, and the KiB->bytes multiply happens in bash 64-bit
    # integers rather than awk doubles.
    local avail_kb
    avail="$(df -P -B1 -- "$TARGET_ROOT" 2>/dev/null | awk 'NR==2{print $4}')"
    if ! [[ "$avail" =~ ^[0-9]+$ ]]; then
        avail_kb="$(df -Pk -- "$TARGET_ROOT" 2>/dev/null | awk 'NR==2{print $4}')"
        if [[ "$avail_kb" =~ ^[0-9]+$ ]]; then avail=$(( avail_kb * 1024 )); else avail=''; fi
    fi
    if ! [[ "$avail" =~ ^[0-9]+$ ]]; then
        log "WARN: capacity precheck skipped for '$TARGET_ROOT' - df reported no usable free-space figure on this host."
    fi
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
            done < <(find "$change_root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
                        | sed 's#.*/##' \
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
    local rel dest destdir src found fcause frest fdetail fpath located_form own_form needs_expand recovered rc
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
        # Reject unless PROVABLY inside (rc 0); both "outside" and
        # "indeterminate" take this branch.
        if ! is_inside "$dest" "$TARGET_ROOT"; then
            log "WARN: '$rel' escapes the target root or cannot be canonicalised (path traversal); refusing."
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

        # SR-050 proved the form for a hash-recovered row; SR-068 (kit revision
        # 8) extends that to a row resolved through its OWN DataPath, which was
        # the last decision either restorer took on the Compressed column's
        # word. The column is now an input to the capacity ESTIMATE only.
        if [[ -n "$located_form" ]]; then
            [[ "$located_form" == 'Archive' ]] && needs_expand=1 || needs_expand=0
        else
            own_form="$(stored_object_form "$src" "${d_hash[i]}" "${d_len[i]}")"
            [[ "$own_form" == 'Archive' ]] && needs_expand=1 || needs_expand=0
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
            0) stamp_mtime "$dest" "${d_lwt[i]}" "$rel" ;;
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
                        0) stamp_mtime "$dest" "${d_lwt[i]}" "$rel" ;;
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

    # --- Directory sidecar (SR-065): empty directories, after every file ---
    # Last, so a directory is never created or touched while its contents are
    # still appearing, and so a failure here cannot affect the file accounting.
    apply_dir_sidecar "$origin" "$TARGET_ROOT"

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
