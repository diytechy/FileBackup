#!/usr/bin/env bats
#
# SR-071, gen_cases pairwise case 2/4: userland=BSD, mode=HashAddressed_Compress,
# origin=snapshot (TC-179).
#
# WHY THIS FILE EXISTS SEPARATELY FROM portability.bats. Those tests shim a GNU
# tool AWAY, which proves each fallback is reached. That is not the same as
# proving the BSD FORM works: an always-failing stub drives `stat_size` to its
# `wc -c` floor and makes `mktemp` look absent rather than merely stricter. The
# shims here IMITATE BSD instead - `stat` rejects -c and answers -f '%z',
# `mktemp` demands a template, `find` has no -printf, `realpath` has no -m,
# `df` has no -B - so the BSD branch of each shim is what actually runs.
#
# And this combination in particular, because it is the only one that drives the
# mktemp fix (BSD needs a template, or EVERY compressed row fails and is blamed
# on 7-Zip) and the find fix (no -printf, or the pool silently loses every
# sibling snapshot) through a REAL restore rather than as isolated units. The
# permutation set said so; hand-picked cases had missed it.

setup() {
    load helpers
    WORK="$(mktemp -d "${BATS_TMPDIR:-/tmp}/bsd.XXXXXX")"
    BSD="$WORK/bsdbin"
    mkdir -p "$BSD"

    # --- stat: BSD has no -c; it spells the size format -f '%z' -------------
    cat > "$BSD/stat" <<'SH'
#!/bin/bash
[ "$1" = "-c" ] && { echo "stat: illegal option -- c" >&2; exit 1; }
if [ "$1" = "-f" ]; then
    fmt="$2"; shift 2; [ "$1" = "--" ] && shift
    [ "$fmt" = "%z" ] || { echo "stat: unsupported format" >&2; exit 1; }
    wc -c < "$1" 2>/dev/null | tr -d ' ' || exit 1
    exit 0
fi
exit 1
SH

    # --- mktemp: BSD REQUIRES a template ------------------------------------
    cat > "$BSD/mktemp" <<'SH'
#!/bin/bash
args=("$@"); has_template=0
for a in "${args[@]}"; do case "$a" in *XXXXXX*) has_template=1 ;; esac; done
if [ "$has_template" -eq 0 ]; then
    echo "usage: mktemp [-d] [-q] [-t prefix] [-u] template ..." >&2
    exit 1
fi
exec /usr/bin/mktemp "${args[@]}"
SH

    # --- find: BSD has no -printf -------------------------------------------
    cat > "$BSD/find" <<'SH'
#!/bin/bash
for a in "$@"; do [ "$a" = "-printf" ] && { echo "find: -printf: unknown primary or operator" >&2; exit 1; }; done
exec /usr/bin/find "$@"
SH

    # --- realpath: BSD has no -m --------------------------------------------
    cat > "$BSD/realpath" <<'SH'
#!/bin/bash
for a in "$@"; do [ "$a" = "-m" ] && { echo "realpath: illegal option -- m" >&2; exit 1; }; done
exec /usr/bin/realpath "$@"
SH

    # --- touch: BSD/macOS rejects GNU's -d ----------------------------------
    # Without this the "BSD" restores below used GNU `touch -d` and the POSIX
    # -t fallback never ran, so SR-066 was untested on the very userland this
    # suite exists for (2026-08-28 independent review, T5).
    cat > "$BSD/touch" <<'SH'
#!/bin/bash
[ "$1" = "-d" ] && { echo "touch: illegal option -- d" >&2; exit 1; }
exec /usr/bin/touch "$@"
SH

    # --- df: BSD has no -B ---------------------------------------------------
    cat > "$BSD/df" <<'SH'
#!/bin/bash
for a in "$@"; do case "$a" in -B*|--block-size*) echo "df: illegal option -- B" >&2; exit 1 ;; esac; done
exec /usr/bin/df "$@"
SH

    chmod +x "$BSD"/*
    BSD_PATH="$BSD:$PATH"
}

teardown() { rm -rf "$WORK"; }

@test "the BSD shims really do reject the GNU spellings" {
    # A test whose stub silently still works proves nothing, so assert the
    # imitation first (an earlier draft of another test shimmed gawk with a stub
    # that `command -v` happily found, and passed for the wrong reason).
    printf '0123456789' > "$WORK/ten"
    PATH="$BSD_PATH" run stat -c '%s' -- "$WORK/ten";        [ "$status" -ne 0 ]
    PATH="$BSD_PATH" run stat -f '%z' -- "$WORK/ten";        [ "$status" -eq 0 ]; [ "$output" = "10" ]
    PATH="$BSD_PATH" run mktemp -d;                          [ "$status" -ne 0 ]
    PATH="$BSD_PATH" run find "$WORK" -printf '%f\n';        [ "$status" -ne 0 ]
    PATH="$BSD_PATH" run realpath -m -- "$WORK/nope";        [ "$status" -ne 0 ]
    PATH="$BSD_PATH" run df -P -B1 -- "$WORK";               [ "$status" -ne 0 ]
    printf 'x' > "$WORK/t"
    PATH="$BSD_PATH" run touch -d '2024-01-01T08:00:00Z' -- "$WORK/t"; [ "$status" -ne 0 ]
    PATH="$BSD_PATH" run touch -t 202401010800.00 -- "$WORK/t";        [ "$status" -eq 0 ]
}

@test "BSD: a restored file keeps its OWN timestamp through the touch -t fallback (SR-066, TC-182)" {
    # GNU `touch -d` parses the manifest's ISO-8601 stamp directly; BSD does not,
    # and the fallback is what stops every restored file silently taking the
    # RESTORE time instead. Proved by comparing the same restore done both ways:
    # if the fallback were removed the BSD mtime would be "now", not the row's.
    local mode=HashAddressed
    local origin; origin="$(origin_for "$mode" root)"

    # GNU reference restore (no shims on PATH).
    run bash "$RS" --from "$origin" --target-root "$WORK/gnu"
    [ "$status" -eq 0 ]

    # The same restore on a "BSD" userland.
    PATH="$BSD_PATH" run bash "$RS" --from "$origin" --target-root "$WORK/bsd"
    [ "$status" -eq 0 ]

    # Read the times with the REAL stat, outside the shimmed PATH.
    local gnu_t bsd_t now
    gnu_t="$(stat -c '%Y' -- "$WORK/gnu/README")"
    bsd_t="$(stat -c '%Y' -- "$WORK/bsd/README")"
    now="$(date +%s)"

    [ "$bsd_t" = "$gnu_t" ]
    # And it is genuinely the row's stamp, not the moment of restore - the
    # fixtures are dated 2024, so anything within a minute of now is the bug.
    [ "$(( now - bsd_t ))" -gt 60 ]
}

@test "BSD + Compress + snapshot: a dated snapshot restores byte-exact (SR-071, TC-179)" {
    local mode=HashAddressed_Compress
    local snap=Snapshot_2024_01_01_09_00_00
    local origin; origin="$(origin_for "$mode" "$snap")"
    local target="$WORK/restored"

    PATH="$BSD_PATH" run bash "$RS" --from "$origin" --target-root "$target"
    [ "$status" -eq 0 ]

    run verify_tree "$target" "$FIXTURES/bash-restore/$mode/expected/$snap.tsv"
    [ "$status" -eq 0 ]
}

@test "BSD + Compress + root: the live state restores byte-exact too (SR-071)" {
    local mode=HashAddressed_Compress
    local origin; origin="$(origin_for "$mode" root)"
    local target="$WORK/restored-root"

    PATH="$BSD_PATH" run bash "$RS" --from "$origin" --target-root "$target"
    [ "$status" -eq 0 ]

    run verify_tree "$target" "$FIXTURES/bash-restore/$mode/expected/root.tsv"
    [ "$status" -eq 0 ]
}

@test "BSD + the SECOND snapshot restores its own point in time (SR-071)" {
    # Two snapshots exist; restoring the later one must reproduce ITS state, not
    # the earlier one's - the pool walk has to see both siblings, which is the
    # half `find -printf` used to break silently.
    local mode=HashAddressed_Compress
    local snap=Snapshot_2024_01_02_09_00_00
    local origin; origin="$(origin_for "$mode" "$snap")"
    local target="$WORK/restored-2"

    PATH="$BSD_PATH" run bash "$RS" --from "$origin" --target-root "$target"
    [ "$status" -eq 0 ]

    run verify_tree "$target" "$FIXTURES/bash-restore/$mode/expected/$snap.tsv"
    [ "$status" -eq 0 ]
}

@test "BSD + Plain + root still restores, so the shims did not just disable the suite (SR-071)" {
    local origin; origin="$(origin_for HashAddressed root)"
    local target="$WORK/restored-plain"
    PATH="$BSD_PATH" run bash "$RS" --from "$origin" --target-root "$target"
    [ "$status" -eq 0 ]
    run verify_tree "$target" "$FIXTURES/bash-restore/HashAddressed/expected/root.tsv"
    [ "$status" -eq 0 ]
}
