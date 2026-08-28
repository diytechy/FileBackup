#!/usr/bin/env bash
#
# RECONSTRUCT.command — double-clickable macOS restore launcher (SR-072).
#
# Deposited into the backup root and every dated snapshot beside reconstruct.sh,
# RECONSTRUCT.ps1 and RECONSTRUCT.cmd. Finder opens a .command in Terminal, so a
# Mac operator can start a restore without recalling a single argument — the
# same reach RECONSTRUCT.cmd gives Windows. It holds no restore logic of its own
# and never will: one implementation of the POSIX restore, in reconstruct.sh.
#
# Two Finder facts shape this file:
#
#   1. Finder launches a .command with the working directory set to $HOME, not
#      to the folder the file lives in. Without the cd below, reconstruct.sh
#      would take $HOME as the restore origin and find no MANIFEST.csv.
#   2. A double-click passes NO arguments, and reconstruct.sh REQUIRES
#      --target-root (deliberately — see SR-016). So a bare launch asks for
#      --pick-target, which opens the macOS folder chooser. If the operator
#      cancels, reconstruct.sh prints usage and exits 2; it never guesses.
#
# THE EXECUTABLE BIT IS THE LIMIT OF THIS CONVENIENCE. The kit is written by
# Windows PowerShell, which cannot set a POSIX mode. macOS synthesises execute
# permission on FAT/exFAT/NTFS volumes — the USB-stick case, which works — but a
# copy that has been through a zip onto APFS arrives without it, and Finder then
# refuses to launch this file until:
#
#     chmod +x RECONSTRUCT.command
#
# The path that needs no executable bit at all, and is the documented macOS
# route in the README, is:
#
#     bash reconstruct.sh --pick-target
#
# reconstruct.sh is invoked through `bash` here for the same reason: it lets the
# restorer run without ITS executable bit surviving the trip from Windows.
#
# Implements: SR-072, SR-073 (LLR-072, LLR-073)

set -u

here="$(dirname "${BASH_SOURCE[0]}")"
cd "$here" || {
    printf 'RECONSTRUCT.command: cannot enter its own folder (%s).\n' "$here" >&2
    exit 2
}

if [ ! -f ./reconstruct.sh ]; then
    printf 'RECONSTRUCT.command: reconstruct.sh is missing from %s.\n' "$(pwd)" >&2
    printf 'The restore kit is incomplete; restore from another copy of this backup.\n' >&2
    exit 2
fi

# A double-click has no arguments; anything scripted passes its own.
[ $# -eq 0 ] && set -- --pick-target

exec bash -- ./reconstruct.sh "$@"
