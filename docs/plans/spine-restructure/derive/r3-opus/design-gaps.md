# Design gaps (round 3, Opus derivation)

Where an SR obligation is not met by today's code, the SR, the LLR that now states the design, and what the code does instead. This list is the build work. Evidence comes from reading the code (the backup-only engine module, the restore-safe shared library, the entry point, both restore routes, the container files and the user manual); none of it was run, so a "does instead" that rests on inference says so.

## 1. Obligations today's code does not meet

| # | SR | LLR | What the code does instead |
|---|---|---|---|
| G-01 | SR-137 | LLR-109 | The walk never descends a folder link or junction and does not tell outside targets from inside ones, so content behind a link to another drive is silently omitted; a link with an unreachable target is not named. File links are followed. |
| G-02 | SR-150, SR-151 | LLR-109, LLR-110 | No link is recorded; a directory link is probably written to the folder record as an empty folder (inferred). There is no link record (IF-018 is new form). |
| G-03 | SR-152 | LLR-144 | Neither restore route recreates any link. |
| G-04 | SR-138 | LLR-103 | A backup or saved-state location equal to, inside or containing a source is not refused at all. |
| G-05 | SR-063 | LLR-103 | The listing location is checked only when the browse view is on, per location during the run, and its refusal fails that location (value 1) instead of refusing the run with value 2 before it starts. |
| G-06 | SR-149 | LLR-103 | State-location overlap is checked only against its own location set's paths and fails that location (value 1), not the configuration (value 2); a state location inside another set's source is not caught. |
| G-07 | SR-140 | LLR-104 | A read-only source with the record at its root is not refused up front: the run does its work and then fails when the change-detection record is written (value 1). |
| G-08 | SR-035 | LLR-114 | A missing change-detection record is silently treated as empty (every file re-read, no report); an unreadable one fails the location; its evidence is never checked on read; a stale or foreign record is trusted wherever size and time match, rather than reconciled with the backup's own record. |
| G-09 | SR-035, SR-005 | LLR-035 | A populated backup with a missing or unreadable run-state record is refused (location fails, value 1) instead of re-deriving the completion time from the evidence's written time and reporting the rebuild. |
| G-10 | SR-005 | LLR-028 | A saved state is named by the previous run's start time, not by the completion time of the state it holds; the run-state record stores the start time. |
| G-11 | SR-043 | LLR-043 | A backup exits 1 for a busy store, a capacity shortfall, a retired store form and an empty source (the design gives 4, 2, 2 and 2), and 3 only for a witness mismatch. The saved-state report always exits 0. A dependency-initialisation failure and a path failure in removal or the report are unhandled errors with no mapped value. A non-backup action without the legacy switch raises an error instead of returning its value. |
| G-12 | SR-085, SR-086 | LLR-122 | Every claim failure is one refusal: a backup marks the location failed (1), a removal reports 2. Contention and an I/O error (busy, 4) are not told from access denied or an unusable claim location (2). |
| G-13 | SR-017, SR-107 | LLR-017 | Every leftover refusal fails the location with value 1; the design gives 2 for content, an unfinished removal, a link or unreadable evidence, 3 for a damaged record and 4 for a live or unproven run. An unfinished removal's refusal does not name re-running the removal as the remedy. |
| G-14 | SR-036 | LLR-036 | The empty-source refusal fails the location with value 1, not 2. |
| G-15 | SR-052 | LLR-052 | A shortfall fails the location with value 1, not 2; the demand has no allowance for records, kits, logs and temporary space. |
| G-16 | SR-061 | LLR-060 | A backup over a retired form fails the location with value 1, not 2. The shell restore route runs its retired-form check after creating the target and its report, so a refusal leaves both behind. An unrecognised layout-marker value or record header is not refused as a form. |
| G-17 | SR-019 | LLR-020 | No runtime-version check on the backup side (the floor is only documented). |
| G-18 | SR-132, SR-016 | LLR-105, LLR-016 | Obtaining the hashing component asks a yes/no question when attended, and when unattended refuses unless a separate permission switch is given. Whether the fetched package is checked against its published digest was not confirmed. A missing optional tool asks a question unless the run is declared unattended; redirected or closed input is not detected. |
| G-19 | SR-008, SR-016 | LLR-008 | If a kit's hashing library is missing, the language-runtime restore route falls back to a package-source install with a question, even when started unattended. |
| G-20 | SR-118 | LLR-139 | The language-runtime route checks neither the runtime version nor the presence of the kit's hashing library; a missing runtime surfaces as the launcher shell's own not-found error with no guidance. The shell route's missing-extractor message gives no macOS install hint. |
| G-21 | SR-009 | LLR-009, LLR-079 | The language-runtime route resolves only the deepest existing path component, so a junction in the middle of the target path is missed; it reduces parent components lexically before resolving; and an unresolvable location falls back silently to the text. |
| G-22 | SR-141 | LLR-137 | The language-runtime route refuses neither an unresolvable target nor one holding a parent-folder component; on GNU systems the shell route accepts a parent component through its resolver. |
| G-23 | SR-023 | LLR-023 | Both routes leave compressed entries out of the demand and add no allowance; the language-runtime route measures after creating the target and its report and skips an unmeasurable volume without a word. |
| G-24 | SR-039, SR-116 | LLR-039, LLR-138 | An absent evidence file is excused for every state ("predates the evidence"); no positive age evidence is consulted, so deleting the evidence switches the check off. The shell route silently skips non-numeric length or count fields. |
| G-25 | SR-121 | LLR-141 | An entry escaping the target is counted as missing content (1, or 4 with a host failure), not as a damaged record (3). |
| G-26 | SR-092 | LLR-142 | Colliding names are not detected: on Windows the language-runtime route merges case-differing entries and the last wins; the shell route lets the second overwrite the first and counts both restored. |
| G-27 | SR-146, SR-122 | LLR-143 | A missing or malformed folder record never changes the outcome, and nothing tells a state that should have one from a state that has none (the evidence does not state folder-record rows; IF-015 version 3 is new form). The language-runtime route assigns attributes, replacing a folder's existing bits, instead of adding them. |
| G-28 | SR-066 | LLR-066 | A blank or unreadable recorded time is a warning only; the restore still ends complete instead of part failed. |
| G-29 | SR-040 | LLR-040, LLR-050 | An unclassified error in the middle of the language-runtime restore loop reports 2 although files were written (the design gives 4). A shell switch given without its value exits 127, not 2. A missing referenced item whose search ends in a host cause is recorded as missing content. |
| G-30 | SR-120 | LLR-029 | The language-runtime route names unrestored paths in its summary but gives causes only in separate log lines; the shell route's console summary gives counts only. The report entries are not yet in the IF-022 form. |
| G-31 | SR-124 | LLR-107 | The run record gives counts of new-or-changed and removed files and names failures, but does not name each added, changed and removed file, and does not separate added from changed. |
| G-32 | SR-125 | LLR-108 | No progress reporting exists; the only periodic activity is the liveness refresh of the owner record. |
| G-33 | SR-089, SR-091, SR-067 | LLR-111, LLR-067 | A file that cannot be read when its digest is taken aborts the whole location instead of being named while every other file is captured; retries apply only to copying, not to reading for the digest. |
| G-34 | SR-049 | LLR-049 | The default check reads only each object's opening bytes, so altered content is found only by an opt-in deep pass. |
| G-35 | SR-109 | LLR-129 | Repair renames items and rewrites forms, but never copies content back from a verified copy elsewhere. |
| G-36 | SR-110 | LLR-130 | Not confirmed from the code whether the kit refresh and each repair rename publish by temporary and rename; to be checked when the code is headed. |
| G-37 | SR-097 | LLR-132 | There is no space view and no setting for it (SpaceView in IF-004 and IF-042 are new form). |
| G-38 | SR-098, SR-099, SR-147 | LLR-133, LLR-134 | The media rate is computed nowhere: the switch that would enable it is hard-wired off, and no record entry says the measure was not taken. |
| G-39 | SR-131 | LLR-119 | No licence or notice file is placed in any backup; the hashing library is redistributed without its notice (the notices file in IF-019 is new form). |
| G-40 | SR-143 | LLR-148 | The container image carries no notices for the runtime, the hashing library or the archive tool. |
| G-41 | SR-135 | LLR-099 | The native-Windows form carries no version, and the configuration helper writes none. |
| G-42 | SR-018, SR-042 | LLR-042, LLR-101 | The native-Windows form gets a shape check only: no closed key set and no strict value kinds, so a coerced value or an unknown key passes there. |
| G-43 | SR-129 | LLR-100 | A native-Windows document whose credential is a plain-text value is not refused (no check of the credential's kind was found). |
| G-44 | SR-095 | LLR-014 | A JSON configuration with several location sets draws a warning; the removal, report, check and view actions act on the first set only, with a warning. |
| G-45 | SR-048, SR-103 | LLR-048, LLR-128 | Removal and the report resolve the set's locations in the backup's mode: they need the source to exist and create missing backup or saved-state folders, and a resolution failure is an unhandled error. |
| G-46 | SR-033, SR-136 | LLR-121 | Relative paths are recorded with the host's own separator, so a Linux run writes '/' where a Windows run writes '\'; a run from the other host type then sees every file as removed and added again and keeps a full saved state for an unchanged tree. |
| G-47 | SR-082 | LLR-118 | The evidence is written only after the record is renamed; a kill between the two leaves a mismatch that the next run refuses as damage instead of completing. |
| G-48 | SR-027 | LLR-027 | The quick start's first run asks before installing the hashing component; the helper writes an unversioned native-Windows document; the user manual states two different current configuration versions. |
| G-49 | SR-064, SR-112, SR-113 | LLR-149, LLR-062 | The time and memory budgets have never been measured at the declared scale; nothing shows they are met or missed. |
| G-50 | SR-104 | LLR-096 | The repair's findings document carries no per-finding repaired flag. |

## 2. Code that goes beyond the design

No SR asks for these; each is either kept as a convenience the Owner may confirm, or retired with its rationale. None is in an LLR.

- **Removal dry run** (the removal's what-if switch and the container's dry-run variable). Not in IF-002 or IF-038. A "removal dry run" was listed as a possible missing need at the SR merge.
- **Removal overrides** (discarding unreferenced content, removing over unverified records, skipping content verification), reachable only by a direct module caller. SR-046 refuses those cases without exception.
- **The deep-check switch.** The design makes reading every distinct stored object the default check (LLR-049), so the switch has no remaining meaning.
- **The strict-evidence restore switch** is kept in IF-020 and LLR-039 though no SR asks for it ("an opt-in strict restore" was a possible missing need at the SR merge).
- **The multi-set warning** goes (SR-095 makes several sets normal).
- **A backup's what-if switch** is refused today with 2; it is not part of IF-002, so it falls under "any other switch is a bad request", which keeps the value.

## 3. SRs that reach no LLR and no interface

None. Every one of the 123 SRs is in the `sr_refs` of at least one top-level LLR.

## 4. SR constrains

Boundary interfaces whose behaviour the SR itself states at the system boundary. Each also has at least one constraining LLR, so none of them depends on this list for coverage; the pairs are listed because the SR tier, not mine to edit, would carry them as `constrains` cells.

- SR-043 -> IF-003
- SR-040 -> IF-021
- SR-010 -> IF-023
- SR-104 -> IF-010
- SR-120 -> IF-022
- SR-142 -> IF-038
- SR-130 -> IF-039
- SR-131 -> IF-019
- SR-143 -> IF-040
- SR-139 -> IF-029
