#!/usr/bin/env bash
# Product launcher (Linux/POSIX) — run this to see FileBackup's Linux surface work.
# Every launchable project ships run.cmd / run.sh (process.md section 7, "the
# evaluator's rungs") so starting it never requires recalling a command. Read it
# first; it only runs the one command below.
#
# --- EDIT FOR YOUR PROJECT ----------------------------------------------------
# The backup ENGINE is Windows/PowerShell-only; the Linux product surface is the
# standalone restore (bash/reconstruct.sh). This launcher runs the standard test
# pass on a CREATED environment: it restores every origin (backup root + every
# dated snapshot) of the four committed, real-engine-produced fixture backups
# under tests/fixtures/ into a temp dir and byte-compares each file (xxh128).
# Nothing outside the temp dir is written; no configuration is needed.
#
# Tooling floor (see README "Restore on Linux"): bash 4+, GNU coreutils, gawk,
# xxhsum (xxHash >= 0.8), 7z/7za (p7zip). Install e.g.:
#   apt-get install xxhash p7zip-full gawk    |    dnf install xxhash p7zip gawk
#
# The fuller Linux suite is `bats tests/bash/`; the Windows demo/full matrix are
# run.cmd / RunAllTests.bat.
RUN_CMD=(bash tests/bash/verify_restores.sh tests/fixtures)
# ------------------------------------------------------------------------------

set -u
cd "$(dirname "$0")" || exit 1

if [ "${#RUN_CMD[@]}" -eq 0 ]; then
    echo "run.sh: no launch command wired yet."
    echo "Edit RUN_CMD in this file — see the EDIT FOR YOUR PROJECT block — and"
    echo "in run.cmd. The README \"Run it\" section documents the underlying command."
    exit 1
fi

# Friendly preflight so a missing tool reads as remediation, not a stack of errors.
missing=""
command -v gawk >/dev/null 2>&1 || missing="$missing gawk"
{ command -v xxh128sum >/dev/null 2>&1 || command -v xxhsum >/dev/null 2>&1; } || missing="$missing xxhash"
{ command -v 7z >/dev/null 2>&1 || command -v 7za >/dev/null 2>&1 || command -v 7zz >/dev/null 2>&1; } || missing="$missing p7zip"
if [ -n "$missing" ]; then
    echo "run.sh: missing required tool(s):$missing"
    echo "Install them first, e.g.:  sudo apt-get install xxhash p7zip-full gawk"
    echo "                     or :  sudo dnf install xxhash p7zip p7zip-plugins gawk"
    exit 1
fi

echo "Running: ${RUN_CMD[*]}"
"${RUN_CMD[@]}"
code=$?
echo
echo "Exited with code $code."
exit $code
