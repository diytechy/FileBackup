# Builds the merged interfaces: the Opus rows as the base (IF-002..IF-044 keep
# Opus's ids), anchored edits for the union clauses, behaviour moved out to LLRs,
# and the coordinator's calls; then the two Astra-sourced rows IF-045 and IF-046.
import sys
from pathlib import Path

D = Path(__file__).resolve().parent.parent
t = (D / 'r3-opus/interfaces.toml').read_text(encoding='utf-8')

R = [
# header
("""# interfaces.toml: FileBackup's interfaces, round-3 derivation (Opus).""",
 """# interfaces.toml: FileBackup's interfaces, round 3, merged tier."""),
# IF-002: accepted switches (K04 dry run kept working, K05 -Deep, the alias and -IncludeSnapshots)
("""- -BackupRootOnly: with -Action Verify, check the latest state only.""",
 """- -BackupRootOnly: with -Action Verify, check the latest state only; -IncludeSnapshots given the value false is accepted as the same request.
- -Deep: with -Action Verify, the former request for a payload check; accepted, carries no meaning.
- -VerifyStorage: accepted as the same request as -Action Verify.
- -WhatIf: with -Action Prune only, the removal dry run; with any other action a bad request."""),
# IF-004: the schedule letters are form; when each is due is the re-read rule's (LLR-011)
("""- HashRecalcFreq: required, one of A, E (every run), D (when the host-local calendar date differs from that of the last completed full re-read), W (when the ISO-8601 week, Monday first, or the year differs), M (when the month or year differs), Y (when the year is later), N (never); case-insensitive.""",
 """- HashRecalcFreq: required, one of A, E (every run), D (daily), W (weekly), M (monthly), Y (yearly), N (never); case-insensitive."""),
# IF-009: refusal tokens frozen
("""A structured log in a machine format lost for the owner-facing record: the machine-readable form is IF-010, and a person reads this one.\"\"\"""",
 """A structured log in a machine format lost for the owner-facing record: the machine-readable form is IF-010, and a person reads this one. The refusal tokens are kept exactly as hosts already search for them; a new refusal class takes a token that names no requirement, because requirement numbering is not a host-visible form.\"\"\""""),
# IF-013: behaviour moved to LLR-028 and LLR-007
("""the date is the host-local completion time of the state it holds, the three-digit suffix separating states completed in the same second.""",
 """the date and time are host-local, and the optional three-digit suffix separates two folders of the same second."""),
("""Infrastructure names are names at a folder's own root; the same names deeper in a folder are data. The retired launcher name RECONSTRUCT.bat is an infrastructure name and is never written.""",
 """Infrastructure names are names at a folder's own root; the same names deeper in a folder are data. RECONSTRUCT.bat, the retired launcher name, is an infrastructure name."""),
# IF-014: union with Astra's canonical bytes; the separator (K13)
("""data = \"\"\"CSV per RFC 4180, UTF-8 without byte-order mark, every field quoted, a header row then one row per file of the state, rows in ordinal order of RelativePath. Columns, in order:""",
 """data = \"\"\"CSV per RFC 4180, UTF-8, LF line endings, every field quoted, a header row then one row per file of the state, rows in ordinal order of RelativePath; written without a byte-order mark, read with or without one. A record of a state with no file is the header alone. Columns, in order:"""),
("""- RelativePath: the file's path under the source root, components separated by a backslash whatever the host;
- Length: integer bytes;""",
 """- RelativePath: the file's path under the source root, components separated by a backslash whatever the host; records written from Linux by earlier versions use the forward slash;
- Length: non-negative 64-bit integer bytes;"""),
("""- Duplicate: 0 or 1;""",
 """- Duplicate: 0, 1 or empty;"""),
# IF-016: the extension's election is LLR-058's
("""- <ext>: the electing file's own extension carried verbatim (may be empty, may contain spaces or non-ASCII characters), or .7z when stored compressed;""",
 """- <ext>: a file extension carried verbatim (may be empty, may contain spaces or non-ASCII characters) for a raw-form object, or .7z for an archive-form object;"""),
# IF-019: the launcher line is LLR-074's; the original-revision marker (K14)
("""- RECONSTRUCT.cmd: the Windows launcher, ASCII with CRLF line endings, one line passing every argument to the language-runtime restorer;""",
 """- RECONSTRUCT.cmd: the Windows launcher, ASCII with CRLF line endings;"""),
("""- THIRD-PARTY-NOTICES.txt: for each third-party component in the folder, its name, version, licence and required notice text.
Each restorer carries a line # KitRevision: <integer>, equal in both; the revision records which record kinds that kit writes and reads.\"\"\"""",
 """- THIRD-PARTY-NOTICES.txt: for each third-party component in the folder, its name, version, licence and required notice text;
- KIT-ORIGIN.txt: present only in a state whose kit a kit refresh has replaced; UTF-8, one line OriginalKitRevision=<integer>, the kit revision the state carried before its first refresh.
Each restorer carries a line # KitRevision: <integer>, equal in both; the revision records which record kinds that kit writes and reads.\"\"\""""),
# IF-022: admission order is LLR-136's
("""every entry also echoed to the console; nothing is written to the target before admission passes. Entries:""",
 """every entry also echoed to the console. Entries:"""),
# IF-023: what else may be written is LLR-010's
("""each recorded link as a link at its RelativePath. No other file is written under the target except the restore report (IF-022).\"\"\"""",
 """each recorded link as a link at its RelativePath; and the restore report (IF-022).\"\"\""""),
# IF-025: union with Astra (allocation unit, name and link semantics)
("""data = \"\"\"For a target path: its physical location with every link and junction along the path resolved, or an indication that it cannot be resolved; the free bytes of the volume holding it, or unknown; and whether the target already exists.\"\"\"""",
 """data = \"\"\"For a target path: its physical location with every link and junction along the path resolved, or an indication that it cannot be resolved; the identity of the volume holding it, its free bytes and its allocation unit in bytes, each or unknown; whether the target already exists; whether it compares names with or without letter case and whether it normalises Unicode names; and whether it can hold folder links, junctions and each folder attribute.\"\"\""""),
# IF-028: union with Astra (errors), the volume system folder names; read-only opens are LLR-112's
("""for a link its target as the filesystem reports it, and whether that target is reachable. Read through read-only opens that share reading only.\"\"\"""",
 """for a link its target as the filesystem reports it, and whether that target is reachable. An enumeration or read that fails gives the path and the cause. A volume root's system folders are named System Volume Information and $RECYCLE.BIN.\"\"\""""),
# IF-030: publication by rename is LLR-028's
("""Written to FileBackupState.json.tmp and published by rename. A writer of a later version may add keys; a reader ignores keys it does not know.\"\"\"""",
 """FileBackupState.json.tmp is its publication temporary. A writer of a later version may add keys; a reader ignores keys it does not know.\"\"\""""),
# IF-031: union with Astra (allocation unit); the mount-table rule is LLR-135's
("""data = \"\"\"For a path: the identity of the volume holding it (on Linux and macOS the longest mount point of the mount table that prefixes the resolved path on a separator boundary; on Windows the volume of the drive or share root), and that volume's free bytes, or unknown.\"\"\"""",
 """data = \"\"\"For a path: the host's mount table on Linux and macOS, or the drive or share root on Windows; and for a volume, its free bytes and its allocation unit in bytes, each or unknown.\"\"\""""),
# IF-032: never written or deleted is LLR-093's
("""holding that open handle is the claim. The file is empty, is never written, and is never deleted.\"\"\"""",
 """holding that open handle is the claim. The file is empty.\"\"\""""),
# IF-033: exclusive create and liveness are LLR-080's; the removal marker's content
("""a UTF-8 JSON object written once by exclusive create: SchemaVersion""",
 """a UTF-8 JSON object: SchemaVersion"""),
("""StaleAfterSeconds (integer, at least 1800). The file's modification time is the liveness evidence. While a removal holds it, Temp contains PRUNE.inprogress.""",
 """StaleAfterSeconds (integer, at least 1800); its modification time is part of the record. While a removal holds it, Temp contains PRUNE.inprogress, UTF-8 text holding the name of the saved-state folder being removed."""),
# IF-034: owner is the store format (the text form is FileBackup's); the package identity moves to IF-037
("""title = "Content digest"
owner = "external:EXT-06"
consumers = ["CMP-009", "CMP-010", "CMP-014", "CMP-016", "CMP-019"]""",
 """title = "Content digest"
owner = "CMP-016"
consumers = ["CMP-009", "CMP-010", "CMP-013", "CMP-014", "CMP-019"]"""),
("""data = \"\"\"XXH128 (xxHash, 128-bit, seed 0) over a byte stream. Text form: 32 uppercase hexadecimal digits, most significant byte first. Provided to the backup side and the language-runtime restore route by the System.IO.Hashing library at version 8.0.0, and to the shell restore route by the xxhsum or xxh128sum command.\"\"\"""",
 """data = \"\"\"XXH128 (xxHash, 128-bit, seed 0) over a byte stream. Text form: 32 uppercase hexadecimal digits, most significant byte first. Computed by the hashing library (IF-037) on the backup side and the language-runtime restore route, and by the host's digest command (IF-024) on the shell restore route.\"\"\""""),
# IF-038: Astra's exact truthy set (K25); the dry-run variable kept working (K04, P-02)
("""FILEBACKUP_REPAIR (with verify, run the repair, truthy one of 1, true, yes in any case); and the environment settings of IF-007.""",
 """FILEBACKUP_REPAIR (with verify, run the repair); FILEBACKUP_DRY_RUN (with prune, the removal dry run); and the environment settings of IF-007. A flag variable is set when it holds exactly one of 1, true, TRUE, True, yes, YES, Yes."""),
# IF-040: the hashing library's identity lives in IF-037
("""the hashing library at the version of IF-034; 7-Zip;""",
 """the hashing library at the version of IF-037; 7-Zip;"""),
# IF-044: the listing's manner is LLR-017's
("""data = \"\"\"Request: a forced, literal, fail-closed listing of the staging area and the owner record as read""",
 """data = \"\"\"Request: the listing of the staging area and the owner record as read"""),
]
for old, new in R:
    if t.count(old) != 1:
        sys.exit(f'ANCHOR {t.count(old)}x: {old[:70]}')
    t = t.replace(old, new)

t = t.rstrip('\n') + '\n\n' + '''[interface.IF-045]
title = "Content search by key"
owner = "CMP-019"
requestors = ["CMP-019"]
channel = "in-process call"
data = """Request: a content key (the digest and the length); the pool folders, the backup root and every saved-state folder; optionally one folder to leave out. Answer: exactly one of
- found: the folder, the stored name, the stored bytes and the proven form (raw or archive);
- content-missing: with the candidates that failed and why;
- dependency-missing: the tool that was needed;
- storage-unreadable: the folder or item that could not be read."""
rationale = """Both restore routes realise this search, and a restore's outcome depends on which answer it gives; a typed answer set is what the two routes must agree on. Leaving the answer set in prose lost because a route that folds a host cause into content-missing reports loss where there is none."""
version = "1"
status = "Drafted"

[interface.IF-046]
title = "Backup runtime and tool floor"
owner = "external:EXT-06"
consumers = ["CMP-004"]
channel = "host commands and runtime"
interface_from_external = ["B-10"]
bridged_by = ["DA-18"]
data = """What a backup host provides for the backup side:
- the runtime: PowerShell 7 or later, reporting its version;
- the hashing library (IF-037), loadable by the runtime;
- the archive tool (IF-035), where any location set compresses;
- the media probe (IF-036), optional.
Each tool, when looked for, is either found (with its location and version) or absent."""
rationale = """A run that finds a missing runtime or tool halfway has already changed the backup, so the floor must be stated where the launch can check it first. Leaving the floor in the user manual only lost because nothing then ties the launch check to it."""
version = "1"
status = "Drafted"
'''
(D / 'r3-merged/interfaces.toml').write_text(t, encoding='utf-8', newline='\n')
print('ok')
