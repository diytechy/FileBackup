#!/usr/bin/env bats
# TC-071 / SR-040 (with SR-031) — reconstruct.sh reports outcome through the one
# documented exit-code table, returning the SAME five codes as Reconstruct.ps1
# -ExitCode for the same five induced conditions (TC-070 is the PowerShell
# twin). The pre-existing TC-055 expectations in fail_loudly.bats are unchanged
# by design: only NEW conditions get 3 and 4.
#
#   0 complete | 1 incomplete, content | 2 usage/precondition
#   3 witness verification failed | 4 incomplete, host
#   Precedence: 2 > 3 > 4 > 1.

setup() {
    load helpers
    WORK="$BATS_TEST_TMPDIR/work"
    cp -r "$FIXTURES/bash-restore/HashAddressed/backup" "$WORK"
    BK="$WORK"; CH="$WORK/changes"
    MANIFEST="$BK/MANIFEST.csv"
}

restamp_witness() {
    local manifest="$1" witness="${1}.meta" rows bytes hash
    rows="$(gawk 'NR>1 && NF>0' "$manifest" | wc -l | tr -d ' ')"
    bytes="$(stat -c '%s' -- "$manifest")"
    hash="$(xxh128sum -- "$manifest" | awk '{print $1}' | tr 'a-f' 'A-F')"
    printf 'Version=1\nRows=%s\nBytes=%s\nXxH128=%s\nWritten=%s\n' \
        "$rows" "$bytes" "$hash" "$(date --iso-8601=seconds)" > "$witness"
}

@test "0: a clean restore (SR-040)" {
    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/t0" --from "$BK" --backup-root "$BK" --change-root "$CH"
    [ "$status" -eq 0 ]
}

@test "1: content class — a row's only data source is gone (SR-040)" {
    rm -f -- "$(pool_file_by_hash "$BK" "$(expected_hash HashAddressed 'hello.txt')")"
    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/t1" --from "$BK" --backup-root "$BK" --change-root "$CH"
    [ "$status" -eq 1 ]
    [[ "$output" == *"INCOMPLETE"* ]]
    [[ "$output" == *"content-missing"* ]]
}

@test "2: precondition — bad arguments (SR-040)" {
    run bash "$RS" --no-such-flag
    [ "$status" -eq 2 ]
}

@test "2: no --target-root dies loudly with usage — the RECONSTRUCT.ps1 -NonInteractive twin (SR-016 / TC-115)" {
    # Pinned as the parity contract: reconstruct.sh has always required
    # --target-root; kit revision 6 gives RECONSTRUCT.ps1 the same
    # non-interactive behavior (usage + exit 2, never a prompt).
    run bash "$RS"
    [ "$status" -eq 2 ]
    [[ "$output" == *"--target-root is required"* ]]
    [[ "$output" == *"Usage:"* ]]
}

@test "2: precondition — no manifest in the origin (SR-040)" {
    local empty="$BATS_TEST_TMPDIR/empty"
    mkdir -p "$empty"
    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/t2b" --from "$empty"
    [ "$status" -eq 2 ]
}

@test "2: precondition — target inside the backup root (SR-040)" {
    run bash "$RS" --target-root "$BK/inside" --from "$BK" --backup-root "$BK" --change-root "$CH"
    [ "$status" -eq 2 ]
}

@test "2: precondition — a FILE occupies the target path (SR-040)" {
    # The PowerShell twin (TC-070) had to be fixed to agree here: an unclassified
    # terminating error left its status at 1, the code reserved for data loss.
    # Nothing is attempted in this case, so both restorers report 2.
    local blocked="$BATS_TEST_TMPDIR/t2-file"
    printf 'I am a file, not a folder\n' > "$blocked"
    run bash "$RS" --target-root "$blocked" --from "$BK" --backup-root "$BK" --change-root "$CH"
    [ "$status" -eq 2 ]
    [[ "$output" == *"cannot create target"* ]]
    [ "$(cat "$blocked")" = "I am a file, not a folder" ]
}

@test "2 outranks 3: a bad target with a damaged index still reports the usage failure (SR-040)" {
    # Precedence 2 > 3 — the invocation is wrong, so the index never gets a say.
    truncate -s -40 "$MANIFEST"
    run bash "$RS" --target-root "$BK/inside" --from "$BK" --backup-root "$BK" --change-root "$CH"
    [ "$status" -eq 2 ]
}

@test "3: the manifest disagrees with its witness (SR-040)" {
    truncate -s -40 "$MANIFEST"
    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/t3" --from "$BK" --backup-root "$BK" --change-root "$CH"
    [ "$status" -eq 3 ]
}

@test "4: host class — hash recovery meets an archive candidate with no 7z (SR-040)" {
    # The row itself stays Compressed=No, so the up-front 7z precondition (exit
    # 2) does not fire: the missing dependency is discovered DURING recovery,
    # which is a host problem (retriable), not lost data.
    local bad="$BATS_TEST_TMPDIR/hostcase"
    mkdir -p "$bad"
    printf 'payload-bytes\n' > "$bad/orig.txt"
    local h len
    h="$(hash_upper "$bad/orig.txt")"; len="$(stat -c '%s' "$bad/orig.txt")"
    # Blank DataPath => must be hash-recovered; the only pool candidate is a .7z.
    {
      printf '"DataPath","RelativePath","Length","LastWriteTimeStr","xxH2Hash","Compressed","StoredAsHashSize","Duplicate","MediaMBPerSec"\r\n'
      printf '"","payload.txt","%s","d","%s","No","Hash","0",""\r\n' "$len" "$h"
    } > "$bad/MANIFEST.csv"
    # The candidate must NOT carry the row's own bytes: since kit revision 5 a
    # raw match under a '.7z' name recovers WITHOUT 7z (pinned below), so the
    # dependency failure needs a candidate whose raw bytes do not match.
    rm -f "$bad/orig.txt"
    printf 'other-bytes-entirely\n' > "$bad/candidate.7z"
    restamp_witness "$bad/MANIFEST.csv"

    # --seven-zip pointing at a non-command is treated as absent (see main()).
    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/t4" --from "$bad" --seven-zip "$BATS_TEST_TMPDIR/no-such-7z"
    [ "$status" -eq 4 ]
    [[ "$output" == *"DependencyMissing"* ]]
    [[ "$output" == *"host"* ]]
}

@test "hash recovery tests a raw .7z-named candidate WITHOUT 7z (kit revision 5)" {
    # A raw file parked under a '.7z' name — a genuine .7z source stored
    # verbatim is the common shape — needs no 7z to test: its own bytes are
    # hashed directly, so the restore succeeds instead of exiting 4.
    local pool="$BATS_TEST_TMPDIR/rawcase"
    mkdir -p "$pool"
    printf 'raw-payload\n' > "$pool/orig.txt"
    local h len
    h="$(hash_upper "$pool/orig.txt")"; len="$(stat -c '%s' "$pool/orig.txt")"
    {
      printf '"DataPath","RelativePath","Length","LastWriteTimeStr","xxH2Hash","Compressed","StoredAsHashSize","Duplicate","MediaMBPerSec"\r\n'
      printf '"","payload.txt","%s","d","%s","No","Hash","0",""\r\n' "$len" "$h"
    } > "$pool/MANIFEST.csv"
    mv -f "$pool/orig.txt" "$pool/candidate.7z"
    restamp_witness "$pool/MANIFEST.csv"

    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/traw" --from "$pool" --seven-zip "$BATS_TEST_TMPDIR/no-such-7z"
    [ "$status" -eq 0 ]
    printf 'raw-payload\n' | diff - "$BATS_TEST_TMPDIR/traw/payload.txt"
}

@test "4 outranks 1: a host failure alongside a content failure reports the actionable one (SR-040)" {
    # A wrapper should retry rather than alarm the user about lost data.
    local bad="$BATS_TEST_TMPDIR/mixed"
    mkdir -p "$bad"
    printf 'payload-bytes\n' > "$bad/orig.txt"
    local h len
    h="$(hash_upper "$bad/orig.txt")"; len="$(stat -c '%s' "$bad/orig.txt")"
    {
      printf '"DataPath","RelativePath","Length","LastWriteTimeStr","xxH2Hash","Compressed","StoredAsHashSize","Duplicate","MediaMBPerSec"\r\n'
      # row 1: host class (archive candidate, no 7z)
      printf '"","payload.txt","%s","d","%s","No","Hash","0",""\r\n' "$len" "$h"
      # row 2: content class (a DataPath that simply is not there)
      printf '"missing.bin","gone.txt","4","d","DEADBEEFDEADBEEFDEADBEEFDEADBEEF","No","Hash","0",""\r\n'
    } > "$bad/MANIFEST.csv"
    # Non-matching bytes, for the same kit-revision-5 reason as the test above.
    rm -f "$bad/orig.txt"
    printf 'other-bytes-entirely\n' > "$bad/candidate.7z"
    restamp_witness "$bad/MANIFEST.csv"

    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/tmix" --from "$bad" --seven-zip "$BATS_TEST_TMPDIR/no-such-7z"
    [ "$status" -eq 4 ]
    [[ "$output" == *"1 content-missing, 1 host"* ]]
}

@test "1: an unrelated unexpandable .7z in the pool is data damage, not a host problem (kit rev 6, SR-040 / TC-112)" {
    # D-3: with 7z PRESENT, a garbage archive candidate met during hash recovery
    # used to flip "your bytes are gone" (1) into "fix this host" (4). No
    # candidate the locator inspects is the row's own file, so an unexpandable
    # archive there is damaged data: ContentMissing, exit 1, candidate named.
    command -v 7z >/dev/null || command -v 7za >/dev/null || command -v 7zz >/dev/null || skip "7z not installed"
    local bad="$BATS_TEST_TMPDIR/d3content"
    mkdir -p "$bad"
    printf 'payload-bytes\n' > "$bad/orig.txt"
    local h len
    h="$(hash_upper "$bad/orig.txt")"; len="$(stat -c '%s' "$bad/orig.txt")"
    {
      printf '"DataPath","RelativePath","Length","LastWriteTimeStr","xxH2Hash","Compressed","StoredAsHashSize","Duplicate","MediaMBPerSec"\r\n'
      printf '"","payload.txt","%s","d","%s","No","Hash","0",""\r\n' "$len" "$h"
    } > "$bad/MANIFEST.csv"
    rm -f "$bad/orig.txt"
    printf 'not-an-archive-at-all\n' > "$bad/noise.7z"
    restamp_witness "$bad/MANIFEST.csv"

    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/td3" --from "$bad"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ContentMissing"* ]]
    [[ "$output" == *"could not be expanded"* ]]
    [[ "$output" == *"noise.7z"* ]]
    [[ "$output" != *"CandidateError"* ]]
}

@test "4: a row's OWN archive failing to expand is still host class (kit rev 6 non-regression, SR-040 / TC-112)" {
    # The restore loop's CandidateError is untouched by D-3: the row resolves
    # through its own DataPath, so extraction failure is about THIS host.
    command -v 7z >/dev/null || command -v 7za >/dev/null || command -v 7zz >/dev/null || skip "7z not installed"
    local bad="$BATS_TEST_TMPDIR/d3own"
    mkdir -p "$bad"
    printf 'garbage-not-7z\n' > "$bad/own.7z"
    {
      printf '"DataPath","RelativePath","Length","LastWriteTimeStr","xxH2Hash","Compressed","StoredAsHashSize","Duplicate","MediaMBPerSec"\r\n'
      printf '"own.7z","payload.txt","999","d","DEADBEEFDEADBEEFDEADBEEFDEADBEEF","Yes","HashSize","0",""\r\n'
    } > "$bad/MANIFEST.csv"
    restamp_witness "$bad/MANIFEST.csv"

    run bash "$RS" --target-root "$BATS_TEST_TMPDIR/td3own" --from "$bad"
    [ "$status" -eq 4 ]
    [[ "$output" == *"CandidateError"* ]]
}

@test "the usage text documents the whole table (SR-040)" {
    run bash "$RS" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"3 manifest-witness verification failed"* ]]
    [[ "$output" == *"4 incomplete"* ]]
    [[ "$output" == *"2 > 3 > 4 > 1"* ]]
}
