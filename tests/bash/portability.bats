#!/usr/bin/env bats
#
# WP13 / SR-071 / SR-073 — the POSIX restorer on a NON-GNU userland, and the
# explicit graphical target picker.
#
# Why these tests exist: reconstruct.sh gates loudly on bash 4+, gawk and
# xxhsum, so a stock Mac stops at the floor. But a host that CLEARS those gates
# and still has BSD coreutils used to produce WRONG ANSWERS rather than loud
# failures — an intact manifest failing its witness with "found -1", a data pool
# silently missing every snapshot. CI is GNU, so the BSD branches are reached
# here by shimming the GNU tool away on PATH. That proves OUR branch selection,
# not Apple's stat(1); the macOS acceptance run is what proves the rest.

setup() {
    load helpers
    WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/wp13.XXXXXX")"
    SHIM="$WORK/shim"
    mkdir -p "$SHIM" "$WORK/backup" "$WORK/outside"
}

teardown() { rm -rf "$WORK"; }

# Put a always-failing stand-in for <tool> ahead of the real one on PATH, so the
# script takes the branch a userland without that GNU behaviour would take.
shim_away() {
    printf '#!/bin/sh\nexit 1\n' > "$SHIM/$1"
    chmod +x "$SHIM/$1"
    PATH="$SHIM:$PATH"
}

# ---------------------------------------------------------------------------
# canon() / is_inside() — the SR-009 guard (2026-08-28 review, T2)
# ---------------------------------------------------------------------------

@test "canon: without realpath -m, a '..' component is REFUSED, not cancelled (SR-009/SR-071, review T2)" {
    shim_away realpath
    # shellcheck disable=SC1090
    source "$RS"
    # THE ATTACK: /outside/link -> /backup. The kernel resolves
    # link/../backup/victim INSIDE the backup; cancelling '..' textually first
    # judges it OUTSIDE and would let a restore write into the backup root.
    ln -s "$WORK/backup" "$WORK/outside/link"
    mkdir -p "$WORK/outside/backup"
    run canon "$WORK/outside/link/../backup/victim"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "canon: without realpath -m, an upward escape is refused (SR-009/SR-071)" {
    shim_away realpath
    # shellcheck disable=SC1090
    source "$RS"
    run canon "$WORK/backup/nope/../../evil"
    [ "$status" -ne 0 ]
    run canon "$WORK/backup/.."
    [ "$status" -ne 0 ]
}

@test "canon: without realpath -m, ordinary paths still resolve (SR-071)" {
    shim_away realpath
    # shellcheck disable=SC1090
    source "$RS"
    local want; want="$(cd "$WORK/backup" && pwd -P)"
    run canon "$WORK/backup";          [ "$status" -eq 0 ]; [ "$output" = "$want" ]
    run canon "$WORK/./backup";        [ "$status" -eq 0 ]; [ "$output" = "$want" ]
    run canon "$WORK//backup";         [ "$status" -eq 0 ]; [ "$output" = "$want" ]
    # A tail that does not exist yet is the case the guard runs in: is_inside is
    # checked BEFORE mkdir, which is exactly why GNU's realpath -m was used.
    run canon "$WORK/backup/new/deep"; [ "$status" -eq 0 ]; [ "$output" = "$want/new/deep" ]
    # '..' inside a NAME is not a '..' component.
    run canon "$WORK/backup/foo..bar"; [ "$status" -eq 0 ]; [ "$output" = "$want/foo..bar" ]
}

@test "canon: a failure is never silently the raw input (SR-071)" {
    shim_away realpath
    # shellcheck disable=SC1090
    source "$RS"
    run canon "$WORK/backup/../x"
    # It used to end '|| printf %s "$1"', handing back an uncanonicalised path
    # and losing the guard without saying so.
    [ "$output" != "$WORK/backup/../x" ]
}

@test "is_inside is TRI-STATE: 0 inside, 1 outside, 2 indeterminate (SR-009)" {
    shim_away realpath
    # shellcheck disable=SC1090
    source "$RS"
    run is_inside "$WORK/backup/sub" "$WORK/backup";     [ "$status" -eq 0 ]
    run is_inside "$WORK/outside"    "$WORK/backup";     [ "$status" -eq 1 ]
    run is_inside "$WORK/backup"     "$WORK/backup";     [ "$status" -eq 0 ]
    # A prefix-sharing sibling must not match (the 'bkp' vs 'bkp-restore' case).
    mkdir -p "$WORK/backup-restore"
    run is_inside "$WORK/backup-restore" "$WORK/backup"; [ "$status" -eq 1 ]
    # Indeterminate is its OWN answer, because the safe branch differs by caller.
    run is_inside "$WORK/backup/a/../../x" "$WORK/backup"; [ "$status" -eq 2 ]
}

@test "2: a target that cannot be canonicalised is a PRECONDITION failure, not a pass (SR-009/SR-040)" {
    shim_away realpath
    local origin; origin="$(origin_for HashAddressed root)"
    run bash "$RS" --from "$origin" --target-root "$WORK/out/../out2"
    [ "$status" -eq 2 ]
    [[ "$output" == *"cannot safely canonicalise"* ]]
    # Nothing may be created when a precondition refuses.
    [ ! -d "$WORK/out2" ]
}

# ---------------------------------------------------------------------------
# stat_size / temp dirs / timestamps — the silent-wrong-answer shims
# ---------------------------------------------------------------------------

@test "stat_size: falls back to a POSIX byte count when GNU stat is unavailable (SR-071)" {
    shim_away stat
    # shellcheck disable=SC1090
    source "$RS"
    printf '0123456789' > "$WORK/ten.txt"
    # The probe must NOT choose a style whose output is not a number.
    [ "$(stat_size "$WORK/ten.txt")" = "10" ]
    [ "$(stat_size "$WORK/absent")" = "-1" ]
}

@test "a store restores byte-exact with GNU stat shimmed away (SR-071)" {
    # The regression this whole work package exists for: without stat_size the
    # witness check reported "expected <N>, found -1" and exited 3 — "the index
    # is damaged" — against a wholly intact backup.
    shim_away stat
    local origin; origin="$(origin_for HashAddressed root)"
    run bash "$RS" --from "$origin" --target-root "$WORK/restored"
    [ "$status" -eq 0 ]
    run verify_tree "$WORK/restored" "$FIXTURES/bash-restore/HashAddressed/expected/root.tsv"
    [ "$status" -eq 0 ]
}

@test "the snapshot pool is complete without find -printf (SR-071)" {
    # BSD find has no -printf; the old pipeline silently produced NOTHING, so
    # the pool collapsed to the backup root and a blank row whose only copy
    # lives in a snapshot reported "your bytes are gone" (exit 1).
    # shellcheck disable=SC1090
    source "$RS"
    local chg="$FIXTURES/bash-restore/HashAddressed/backup/changes"
    run bash -c "find '$chg' -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed 's#.*/##' | grep -E '^Snapshot_' | sort -r"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    # Descending, so the newest snapshot is consulted first.
    [ "$(printf '%s\n' "$output" | head -n1)" = "$(printf '%s\n' "$output" | sort -r | head -n1)" ]
}

@test "make_tempdir works with an explicit template, and a failure never writes to / (SR-071)" {
    # shellcheck disable=SC1090
    source "$RS"
    local d; d="$(make_tempdir)"
    [ -d "$d" ]
    rmdir "$d"
    # With mktemp shimmed away, sevenzip_usable must refuse rather than leaving
    # $w empty and writing its probe to the filesystem ROOT.
    shim_away mktemp
    # shellcheck disable=SC2034  # both are read by sevenzip_usable, sourced above
    SEVEN_ZIP=7z
    # shellcheck disable=SC2034
    SEVENZIP_USABLE=''
    run sevenzip_usable
    [ "$status" -ne 0 ]
    [ ! -e /p.txt ]
    [ ! -e /p.7z ]
}

@test "stamp_mtime_posix applies a UTC stamp and refuses what it cannot honour exactly (SR-066/SR-071)" {
    # shellcheck disable=SC1090
    source "$RS"
    printf 'x' > "$WORK/f"
    run stamp_mtime_posix "$WORK/f" "2024-01-01T08:00:00Z"
    [ "$status" -eq 0 ]
    run stamp_mtime_posix "$WORK/f" "not-a-timestamp"
    [ "$status" -ne 0 ]
    # A foreign offset is converted EXACTLY, through POSIX TZ - neither refused
    # (which silently dropped SR-066 on BSD for any store written in another
    # timezone) nor applied as local digits (wrong by the offset).
    printf 'x' > "$WORK/utc"; printf 'x' > "$WORK/plus"
    run stamp_mtime_posix "$WORK/utc"  "2024-01-01T13:30:00Z"
    [ "$status" -eq 0 ]
    run stamp_mtime_posix "$WORK/plus" "2024-01-01T19:00:00+05:30"
    [ "$status" -eq 0 ]
    # 19:00+05:30 IS 13:30Z, so both files must carry the same instant.
    [ "$(stat -c '%Y' -- "$WORK/utc")" = "$(stat -c '%Y' -- "$WORK/plus")" ]
}

# ---------------------------------------------------------------------------
# --pick-target (SR-073) — explicit, testable, and never a new way to hang
# ---------------------------------------------------------------------------

@test "--pick-target restores into the folder the picker returned (SR-073)" {
    printf '#!/bin/sh\nprintf %%s "%s"\n' "$WORK/picked" > "$WORK/p"; chmod +x "$WORK/p"
    local origin; origin="$(origin_for HashAddressed root)"
    FILEBACKUP_PICKER="$WORK/p" run bash "$RS" --pick-target --from "$origin"
    [ "$status" -eq 0 ]
    run verify_tree "$WORK/picked" "$FIXTURES/bash-restore/HashAddressed/expected/root.tsv"
    [ "$status" -eq 0 ]
}

@test "2: a CANCELLED picker is usage + exit 2, never a default target (SR-073/SR-040)" {
    printf '#!/bin/sh\nexit 1\n' > "$WORK/p"; chmod +x "$WORK/p"
    local origin; origin="$(origin_for HashAddressed root)"
    FILEBACKUP_PICKER="$WORK/p" run bash "$RS" --pick-target --from "$origin"
    [ "$status" -eq 2 ]
    [[ "$output" == *"--target-root is required"* ]]
}

@test "2: --pick-target with NO dialog available fails loudly instead of hanging (SR-016/SR-073)" {
    local origin; origin="$(origin_for HashAddressed root)"
    run env -u DISPLAY -u WAYLAND_DISPLAY -u FILEBACKUP_PICKER bash "$RS" --pick-target --from "$origin"
    [ "$status" -eq 2 ]
    [[ "$output" == *"--target-root is required"* ]]
}

@test "2: WITHOUT --pick-target a missing --target-root is unchanged - usage, never a prompt (SR-016)" {
    # The twin of Reconstruct.ps1's -NonInteractive guard. Adding a picker must
    # not turn the bare failure into an interactive path: an automated caller
    # that forgot the flag has to keep failing, not start waiting.
    local origin; origin="$(origin_for HashAddressed root)"
    FILEBACKUP_PICKER=/bin/true run bash "$RS" --from "$origin"
    [ "$status" -eq 2 ]
    [[ "$output" == *"--target-root is required"* ]]
}

@test "--pick-target is documented in the usage text (SR-073)" {
    run bash "$RS" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--pick-target"* ]]
}

@test "every tool-floor refusal names macOS remediation AND the PowerShell alternative (SR-071)" {
    # Asserted against the message text rather than by removing gawk: `have`
    # uses `command -v`, so a failing stub on PATH still SATISFIES the check —
    # the gate can only be reached by a userland that genuinely lacks the tool,
    # which CI is not. An operator who cannot meet the POSIX floor is not out of
    # options, and a failing restore is the wrong moment to work that out.
    local gates
    gates="$(grep -E 'die "(bash 4\+|gawk is|xxhsum \()' "$RS")"
    [ "$(printf '%s
' "$gates" | wc -l)" -eq 3 ]
    # Each of the three names a macOS route and the PowerShell one.
    [ "$(printf '%s
' "$gates" | grep -c 'brew install')" -eq 3 ]
    [ "$(printf '%s
' "$gates" | grep -c 'ALT_PWSH_HINT')" -eq 3 ]
    grep -q 'RECONSTRUCT.ps1 -TargetRoot' "$RS"
    grep -q 'aka.ms/powershell' "$RS"
}

# ---------------------------------------------------------------------------
# Volume-root pseudo-folders — the bash twin (SR-074)
# ---------------------------------------------------------------------------

@test "volume_root_skip matches only the ROOT level, never a nested folder (SR-074, TC-175)" {
    # shellcheck disable=SC1090
    source "$RS"
    run volume_root_skip "$WORK/backup/System Volume Information/x" "$WORK/backup"; [ "$status" -eq 0 ]
    run volume_root_skip "$WORK/backup/\$RECYCLE.BIN/x"             "$WORK/backup"; [ "$status" -eq 0 ]
    run volume_root_skip "$WORK/backup/system volume information/x" "$WORK/backup"; [ "$status" -eq 0 ]
    # Nested is the user's data (B6), and so is anything else.
    run volume_root_skip "$WORK/backup/sub/System Volume Information/x" "$WORK/backup"; [ "$status" -ne 0 ]
    run volume_root_skip "$WORK/backup/ordinary.txt" "$WORK/backup";     [ "$status" -ne 0 ]
    # A prefix-sharing name is not a match.
    run volume_root_skip "$WORK/backup/System Volume Information Backup/x" "$WORK/backup"; [ "$status" -ne 0 ]
}

@test "is_volume_root tells a mount point from an ordinary directory (SR-074)" {
    # The gate that stops the exclusion reaching a user's own folder. Its
    # PowerShell twin compares the root against GetPathRoot; without an
    # equivalent here the twins would disagree about the same store.
    # shellcheck disable=SC1090
    source "$RS"
    run is_volume_root "/";            [ "$status" -eq 0 ]
    run is_volume_root "$WORK/backup"; [ "$status" -ne 0 ]
    run is_volume_root "$WORK";        [ "$status" -ne 0 ]
}

@test "a store whose root is NOT a volume root keeps its pool intact (SR-074)" {
    # End-to-end: the fixture store lives in an ordinary directory, so nothing
    # may be excluded from its pool and the restore must still be byte-exact.
    local origin; origin="$(origin_for HashAddressed root)"
    run bash "$RS" --from "$origin" --target-root "$WORK/restored"
    [ "$status" -eq 0 ]
    run verify_tree "$WORK/restored" "$FIXTURES/bash-restore/HashAddressed/expected/root.tsv"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# The picker seam itself (SR-073)
# ---------------------------------------------------------------------------

@test "--pick-target works when the picker path CONTAINS SPACES (SR-073, TC-184)" {
    # The override was expanded unquoted, so '/opt/FileBackup Tools/picker' ran
    # '/opt/FileBackup' instead (2026-08-28 independent review, T6). It names ONE
    # executable, not a command line.
    local dir="$WORK/FileBackup Tools"
    mkdir -p "$dir"
    printf '#!/bin/sh\nprintf %%s "%s"\n' "$WORK/picked-spaces" > "$dir/pick er"
    chmod +x "$dir/pick er"

    local origin; origin="$(origin_for HashAddressed root)"
    FILEBACKUP_PICKER="$dir/pick er" run bash "$RS" --pick-target --from "$origin"
    [ "$status" -eq 0 ]
    run verify_tree "$WORK/picked-spaces" "$FIXTURES/bash-restore/HashAddressed/expected/root.tsv"
    [ "$status" -eq 0 ]
}

@test "iso_now produces an ISO-8601 timestamp without GNU date (SR-071)" {
    # `date --iso-8601` is GNU-only; the old fallback silently changed the
    # RECONSTRUCT.log timestamp format on any other userland.
    # shellcheck disable=SC1090
    source "$RS"
    run iso_now
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{4}$ ]]
}
