# Round 2, final: the finished system-requirement tier

This file goes with `docs/requirements/system-requirements.toml`, the finished
tier. That tier was built from `r2-merged/system-requirements.toml` (107 rows),
with every ruling, call and disposition in `r2-dispositions.md` applied.

- **115 rows**: the merged file's 107 ids, all kept, plus 8 new rows, SR-137 to
  SR-144. No row was removed or merged away. 70 of the 107 kept rows changed.
- Every row is Drafted. The legacy `system-requirements.csv` is deleted; git
  and the harvest keep its rows.
- No "Proposed" or "pending" wording remains.

## Validation (run on the finished files)

- `system-requirements.toml`, `stakeholder-needs.toml`, `external.toml` and
  `assumptions.toml` all parse with tomllib.
- No id is duplicated in any of the four. The new SR ids continue from SR-136
  with no gap. B-22 and B-23, EXT-17 and EXT-18, and DA-21 are each the next
  id in their registry.
- Every `sn_refs`, `boundary_refs`, `da_refs`, `hat_refs` and `delivered_with`
  id resolves. Every SR, SN or DA id cited inside a prose cell also resolves.
- Every `delivered_with` sibling shares at least one need with the row that
  cites it.
- Every hat named resolves. Its `applies_when` matches a tag of one of the row's
  needs.
- Each requirement holds exactly one " shall " and opens on The, When, While,
  If or Where. No other cell uses "shall".
- Each row has exactly one of `da_refs` and `coincident`. Each `form` is one of
  the three allowed values.
- A scan of every SR text cell finds no file name, extension, script, switch,
  setting key or tool-product token.
- Advisory only: SR-027, SR-042 and SR-134 cite both an operation crossing and
  the new delivery crossing B-23. Each row's rationale says this is on
  purpose, because the artifact crosses at delivery and is judged in operation.
  The checker's "spans both systems" advisory will name them.

## Findings: one line each

"Rows" lists the rows changed, and "+" marks a new row.

| Finding | Rows | What changed |
|---|---|---|
| R2-001 | SR-082, SR-110, SN-013 | Crash contract applied. The latest state is the pre-run or post-run tree. Every visible state restores as recorded or is refused with exit 3, and none is restored wrongly. The next run re-establishes matching evidence first. SR-110 uses the same contract. |
| R2-002 | SR-041 | Rewritten. Earlier content stays in the store and the saved state still restores the file. The failure is named and the run reports part-failed. A saved state missing a file is never published. |
| R2-003 | SR-038, SR-039 | "Substituted" is bounded to a record that its evidence does not match. DA-11 is cited and `coincident` is dropped. |
| R2-004 | SR-016, SR-073 | The trigger is now how the operation was started: non-interactive, input redirected or closed, no console or desktop. "Nobody present" is gone. |
| R2-005 | SR-092, SR-031 | DA-08 is dropped from SR-092, which is now coincident, form interface, and gains the Unicode-normalisation case. SR-031 is scoped to names that stay distinct and cites DA-08. |
| R2-006 | SR-019, SR-132 | SR-019 refuses only what is still missing once a permitted fetch has been tried. Its hashing case runs with the package source unreachable. SR-132 keeps obtain-first. |
| R2-007 | SR-059 | Now a preservation property: no operation makes content that restored before missing or different. Damage already present is SR-053's and SR-109's. |
| R2-008 | SR-067, SR-090 | Capture is promised at the first allowed attempt that succeeds, within three attempts and while the location's limit lasts. The attempt count lives in SR-067 only. |
| R2-009 | SR-075, SR-085, +SR-144 | SR-075 keeps the observable 30-minute stale time. The confirmation wait and heartbeat move to design. Racing recoverers move to SR-085. A run reclaimed while suspended gets its own row, SR-144. |
| R2-010 | SR-048, +SR-142, SN-024 | SN-024 is widened. The no-action default moves to SR-142. The kit-has-no-removal sentence is dropped from SR-048. |
| R2-011 | none | REFUTED, so not applied: the perspective-record sidecar is retired in the kit. |
| R2-012 | SR-027, SR-035, SR-042, SR-106, SR-134, SR-017, SR-019, SR-045, SR-101, SR-109; B-23 | Output crossings added: B-13 and B-06 (SR-035); B-08, B-15 and B-16 (SR-106); B-08 or B-02 on the others. The new delivery crossing B-23 carries the guidance and the configuration contract. |
| R2-013 | SR-131, +SR-143; B-22, EXT-17 | SR-131 now covers the backup folder only (B-13). The container image's components move to SR-143 at the new delivery crossing B-22. |
| R2-014 | SR-011 | The setting vocabulary and calendar semantics move to the configuration interface (IF). The SR keeps every-run, periodic and never, decided the same way every time. |
| R2-015 | SR-011 | The schedule governs re-reads for change detection only. Reads that capture new content or store lost content again happen whatever the schedule. |
| R2-016 | SR-064 | Linearity clause removed. How the audit scales is design under this budget. |
| R2-017 | SR-113 | History envelope declared: up to 365 saved states. The requirement now says time grows less than in proportion, and the sub-doubling test is kept (182 to 364 states). |
| R2-018 | SR-071, +SR-141 | Refusals for an unresolvable target or a parent-folder component move to SR-141 (SECURITY, SN-042). SR-071 keeps tool-flavour parity only. |
| R2-019 | SR-118 | Scoped to a route that has started. A shell below its version is a case. An absent interpreter is left to the documented floor (SR-008). |
| R2-020 | SN-031, SR-053 | SN-031 narrowed to removed or quarantined content. SR-053's requirement says so. Its rationale points corrupt-but-present content to SR-049 and SR-119. |
| R2-021 | +SR-137, SR-001 | New links row (see code facts). SR-001's "not decided" sentence is replaced by a pointer. |
| R2-022 | SR-109 | Certain classes declared: a recorded form that disagrees with the bytes at the entry's own place, and a name that claims the wrong form. The report-only classes are listed. |
| R2-023 | SR-005, SR-042, SR-038, SR-067, SR-090, SR-099, SR-085, SR-034, SR-130, SR-016, SR-073, SR-132 | Second homes removed. No-change goes to SR-100 only, version to SR-135, credential to SR-129, and attempts to SR-067. Optional extra goes to SR-133, exclusion to SR-106, and asks-nothing to SR-016. |
| R2-024 | SR-045 | The copy-count clause is removed. The stored-form clause and its rationale go to design (see "Not applied"). |
| R2-025 | SR-052 | Demand includes a declared allowance for records, kits, logs and temporary space. A many-small-files case is added. |
| R2-026 | SR-124 | Change counts are zero for an unchanged source, and the failure count is zero only when nothing failed. An unchanged-but-unreadable case is added. |
| R2-027 | SR-093, DA-21 | FileBackup originates no change. Modification time only, with access time excluded. The before/after equality rests on the new quiescent-source assumption DA-21. |
| R2-028 | SR-128 | Scoped to credentials entered through notification setup and to what the system writes. A source file holding the same bytes is backed up as data. |
| R2-029 | SR-064, SR-112, SR-122, SR-010 | `Where` openings for SR-064 and SR-112. SR-122 is a `When` with the condition fronted. SR-010 states its default inside the response. |
| R2-030 | SR-098, SR-099 | Domain: files the tool gives a playing time. The rate is size over playing time, in MiB/s to three decimals. A failing or absent tool is SR-099's. |
| F-01 | SR-019 | As R2-006. |
| F-02 | SR-017, SR-107 | A dead removal's leftovers mean the next backup is refused as not ready (2), naming the remedy: re-run the removal (SR-101). SR-107's "without manual clean-up" now applies to a dead backup only. |
| F-03 | +SR-137 | As R2-021. |
| F-04 | +SR-138 | A backup or saved-state location inside, equal to or containing a source is refused as configuration-refused (2) before anything is written. |
| F-05 | SR-043 | Busy and not-ready apply to backup and removal only. A check's classes are 0, 1 and 2 (configuration). |
| F-06 | SR-017, SR-019, SR-036, SR-046, SR-048, SR-052, SR-061, SR-085, SR-086, SR-102, SR-132 | Each names its class: not ready, busy or configuration-refused (value 2). SR-043 defines the run value across several locations. |
| F-07 | SR-092, SR-121, SR-116, SR-040 | Collision → 1, escaping entry → 3, unverified older record → 0 with the warning. The cases are added to SR-040. |
| F-08 | SR-122, SR-071 | An attribute the target cannot hold is reported and the outcome stays complete. SR-071 includes that case. |
| F-09 | SR-041 | As R2-002. |
| F-10 | SR-116, SR-039 | "Older" needs positive evidence in the record. A current-form record without evidence is refused with 3. |
| F-11 | SR-048, SN-024 | As R2-010. |
| F-12 | SR-123, SR-018 | SR-123 restated as a property of one build: an older supported version is read with that version's meaning. The retired-setting refusal is folded into SR-018. |
| F-13 | SR-064 | As R2-016. |
| F-14 | SR-061 | Recognition cues removed. A retired form is refused by name, also with no evidence present. Recognition is the record-format interface's. |
| F-15 | SR-075 | "Never judged dead" is bounded: not suspended beyond the stale time, with clocks within DA-16's bound. |
| F-16 | SR-075 | Heartbeat interval moved to design. |
| F-17 | SR-017 | The leftover cases are restated at the boundary (may hold content, holds no content). Remnant handling stays at LLR. |
| F-18 | SR-093, SR-103 | "Modification time", with access times not compared. |
| F-19 | SR-064, SR-112 | `Where` openings. |
| F-20 | SR-091 | SHARED-CONTENT dropped (SN-052 has no store-mutation tag). |
| F-21 | SR-131, +SR-143 | As R2-013. |
| F-22 | SR-090 | Attempt count removed; it lives in SR-067. |
| F-23 | SR-067 | The destination-side "folder in the way" case removed (see "Not applied"). |
| F-24 | SR-099 | Narrowed to what the space view shows. SR-133 stays the generic home. |
| F-25 | SR-019 | Compression-off case removed. SR-096 is the home. |
| F-26 | SR-085 | Read-only clause removed. SR-106 is the home. |
| F-27 | SR-016, SR-073, SR-132 | SR-016 is the one home for asking nothing. SR-073 keeps the restore-without-target behaviour. SR-132 points at SR-016. |
| F-28 | SR-034, SR-130 | SR-034: no runtime on the host, compression on and off. SR-130: least privilege, writes nowhere else. |
| F-29 | SR-038 | Nested-same-name clause removed. SR-074 is the home. |
| F-30 | SR-071, +SR-141 | As R2-018. |
| F-31 | SR-001, SR-074 | Visibility-setting clause dropped from SR-001's acceptance. The "only" in SR-074 carries it, and the reason moved to SR-074's rationale. |
| F-32 | SR-074 | "Own" now means what the system writes into a source: its change-detection state at the root. Owner files sharing a name are backed up. |
| F-33 | SR-049, SR-106 | SR-049 reports part-failed (1). SR-106 says "the saved-state report". |
| F-34 | SR-094, +SR-139, +SR-140 | The state location is its own row (SR-139). The read-only refusal is SR-140. SR-094 keeps the read-only success. |
| F-35 | SR-039, SR-056, SR-116, SR-121 | macOS added to the restorer domain. |
| F-36 | SR-097 | A shared stored copy is listed at its full size and marked as shared. |
| F-37 | SR-059 | As R2-007. A repair that restores the same bytes alters nothing. |
| F-38 | SR-092 | Neither colliding entry is written, and both are named as not restored. |

## Owner rulings: one line each

- **(a) Extension fallback kept:** SR-081 (rewritten), SN-003 (need and
  acceptance), and the README vision bullet. SR-096 is unchanged.
- **(b) State at the source root by default:** SR-093, SR-094 and SR-074, plus
  new rows SR-139 (location) and SR-140 (read-only refusal); SN-037 (need and
  acceptance).
- **(c) Three distinct outcomes, busy and not-ready = 2:** SR-043, and value 2
  named in SR-017, SR-019, SR-036, SR-046, SR-048, SR-052, SR-061, SR-085,
  SR-086, SR-102, SR-132, SR-138, SR-139 and SR-140.
- **(d) Re-derive and report:** SR-035.
- **(e) Supported versions only:** SR-061, plus SN-041 (need and acceptance).
  SR-115 already read this way.
- **(f) Budgets adopted:** "Proposed" dropped from SR-064, SR-112, SR-113 and
  SR-125. SR-113 gains the 365-state envelope (R2-017).
- **(g) Both forms, same rules:** SR-042 and SR-129. SR-129 states that the
  native-Windows form is the one that may carry the protected mail login.
  SR-095 and SR-135 already matched and are unchanged.

Coordinator calls: the crash window (SR-082, SR-110, SN-013); SN-024 widened
(SN-024, SR-048, SR-142); SN-031 narrowed (SN-031, SR-053); a dead removal's
leftovers (SR-017, SR-107); links and junctions (SR-137, SR-001).

## Need-tier amendments (old → new)

All six rows stay Drafted. No other cell changed.

**SN-003, `need`:**
- Old: "Where the owner turns compression on, a file is stored compressed only
  when compressing it measurably saves space; when compression is off, nothing
  is compressed."
- New: "Where the owner turns compression on, a file is stored compressed only
  when compressing it measurably saves space, or, where measuring is turned off
  or cannot be done, when its file type is not one known to be already
  compressed; when compression is off, nothing is compressed."

**SN-003, `acceptance`:**
- Old: "With compression on, content that measurably shrinks is stored
  compressed and content that does not is stored as it is, whatever the file's
  name; with compression off, nothing is compressed; every file restores
  byte-exact either way."
- New: "With compression on and measuring done, content that measurably shrinks
  is stored compressed and content that does not is stored as it is, whatever
  the file's name; where measuring is turned off or cannot be done, the file
  type decides, and a file of a type known to be already compressed is stored as
  it is; with compression off, nothing is compressed; every file restores
  byte-exact either way."

**SN-037, `need`:**
- Old: "Backing up never alters, moves or deletes anything in the source: the
  files, their times, their attributes and the folders that hold them stay
  exactly as they were."
- New: "Backing up never alters, moves or deletes anything in the source: the
  files, their times, their attributes and the folders that hold them stay
  exactly as they were. The one exception is the record of what the tool last
  saw, which it keeps as a plain file at the source root unless the owner sets
  it to live on the backup side."

**SN-037, `acceptance`:**
- Old: "After any run, every file and folder in the source is byte-identical
  with unchanged modification times and attributes; a run succeeds against a
  source the run is only allowed to read."
- New: "After any run, every file and folder in the source is byte-identical
  with unchanged modification times and attributes, apart from that record
  where it is kept at the source root; with the record set to live on the backup
  side, a run succeeds against a source the run is only allowed to read, and a
  source the run cannot write, with no such setting, is refused before the run
  starts, naming the setting."

**SN-041, `need`:**
- Old: "Every saved state stays restorable whatever version of FileBackup wrote
  it and whatever version writes to the backup later, and the owner can bring
  the restore kit inside an existing backup up to date when they choose."
- New: "Every saved state written by a supported version of FileBackup stays
  restorable whatever version writes to the backup later, a state in a retired
  form is refused by name rather than misread, and the owner can bring the
  restore kit inside an existing backup up to date when they choose."

**SN-041, `acceptance`:**
- Old: "A saved state written by an older version restores byte-exact both with
  the restore kit it carries and with the current one, after the current version
  has run against the store; content recorded before a newer kind of record
  existed restores as it did before, with any check it could not make reported;
  refreshing the restore kits leaves every state restorable."
- New: "A saved state written by an older supported version restores byte-exact
  both with the restore kit it carries and with the current one, after the
  current version has run against the store; content recorded before a newer
  kind of record existed restores as it did before, with any check it could not
  make reported; a state in a retired form is refused by name, never misread;
  refreshing the restore kits leaves every state restorable."

**SN-024, `need`:**
- Old: "A backup host can run backups inside a container, without installing
  the backup tool's runtime on the host, with no more access than reading the
  source and writing the backup."
- New: "A backup host can run backups, removals and the saved-state report
  inside a container, without installing the backup tool's runtime on the host,
  with no more access than reading the source and writing the backup."

**SN-024, `acceptance`:**
- Old: "In a container on a host that has no backup runtime installed, a run
  backs up a source the container can only read, as an unprivileged user, into
  a backup that restores byte-exact, with compression on."
- New: "In a container on a host that has no backup runtime installed, a run
  backs up a source the container can only read, as an unprivileged user, into
  a backup that restores byte-exact, with compression on; a removal and the
  saved-state report run the same way and return the same outcomes as when
  started directly."

**SN-031, `need`:**
- Old: "If something outside the tool damages the backup, such as antivirus
  quarantine, a cloud-sync space sweep or someone tidying a folder that looks
  like an ordinary copy, the next run puts it right while the source still holds
  the bytes."
- New: "If something outside the tool removes or quarantines content stored in
  the backup, such as antivirus quarantine, a cloud-sync space sweep or someone
  tidying a folder that looks like an ordinary copy, the next run puts it right
  while the source still holds the bytes."

**SN-013, `acceptance`:**
- Old: "After an interruption at any point of a run, every saved state that is
  visible is complete and restorable, and the latest state is either the state
  before the run or the state after it; the next run either completes by itself,
  when it can tell from the backup alone that the interrupted run is dead and
  that nothing would be lost, or refuses before changing anything and names what
  it found."
- New: "After an interruption at any point of a run, the latest state is either
  the state before the run or the state after it, and every visible state either
  restores correctly or is refused by a restore as damaged, never restored
  wrongly; the next run puts back what a restore needs to check each state before
  it does anything else, and either completes by itself, when it can tell from
  the backup alone that the interrupted run is dead and that nothing would be
  lost, or refuses before changing anything and names what it found."

### Other registry changes

- **`external.toml`:**
  - Added EXT-17 "Container image" and B-22, its delivery crossing (out,
    `system = "delivery"`).
  - Added EXT-18 "Release guidance and configuration contract" and B-23, a
    delivery crossing for R2-012's shipped guidance and configuration contract.
  - B-02/B-13, B-06/B-08 and B-16 already existed.
  - The file's header comment said no delivery crossing is drawn. It now names
    the two.
- **`assumptions.toml`:** added DA-21. Nothing else changes the source while a
  run reads it, which is the quiescent-source premise for SR-093's before/after
  test.
- **README vision:** the compression bullet now reads "...a file is compressed
  only when measuring it shows compression actually saves space; where
  measuring is off or unavailable, its file type decides."

## Code facts checked

- **Links and junctions (SR-137).** The engine's source walk lists files and
  folders recursively, with hidden items included and no link-following option.
  Verified on PowerShell 7.6.6 on Windows:
  - A junction or folder link is listed as a folder but not descended into. The
    content behind it is not captured, and a junction that points back at an
    ancestor causes no loop.
  - Nothing names the link in the run's record, so today the omission is
    silent. Naming it is the new obligation.
  - The folder walk records the link as an empty folder, so it restores as an
    ordinary empty folder.
  - A link to a single file is listed as a file. Its target's content is read
    and copied under the link's name.
  - Not checked: the same behaviour on Linux and macOS, and dangling links.
- **F-04 (SR-138): not implemented today.** The set check refuses a
  change-detection state location inside the source, and one equal to or inside
  the backup or saved-state location. The view root is checked both ways against
  every owned path and the source. No check compares the backup location or the
  saved-state location with the source. The check also creates a missing backup
  or saved-state folder before the state-location checks run.
- **Ruling (b).** With no setting, the change-detection state goes to the source
  root, as SR-139 says. A configured location inside a source, or inside a
  backup or saved-state location, is refused, as SR-139 says.
  - SR-140 is not implemented: no check refuses a read-only source without a
    configured state location before the run starts.
  - SR-074 gap: with the state at the source root, the walk drops every
    root-level file whose name matches one of the store's own artifact names,
    not only the state record.
- **SR-067.** Today every source-side copy failure counts as possibly
  transient. The only failure treated as permanent is a folder standing at the
  destination, which is the case moved out of SR-067 (F-23). Attempts are 3,
  waiting 250 ms and then 1000 ms. The retry budget is 60 s per set, which
  matches SR-090's "per configured location".
- **SR-098.** The media measure is size in MiB divided by the playing time the
  tool reports, rounded to three decimals. Any file with a positive playing
  time gets one.
- **SR-109.** The repair corrects exactly two classes: the recorded form, and a
  stored name that claims the wrong form. It reports the others: missing,
  altered and unreferenced content, and the blank-row form class.
- **SR-043, ruling (c).** Today a backup returns 0, 1 or 2, and 2 means a
  refused configuration. A removal returns the restore table, 0 to 4.
  Implementing the ruling means:
  - busy and not-ready must return 2 for a backup;
  - a removal's outcomes 3 and 4 must fold into 2 (not ready, nothing changed);
  - the former opt-in becomes a no-op.

## Coverage

Each of the 48 needs, with the rows that cite it. None is at zero.

| Need | SR count | Rows |
|---|---|---|
| SN-001 | 6 | SR-001, SR-035, SR-074, SR-088, SR-089, SR-137 |
| SN-002 | 1 | SR-003 |
| SN-003 | 2 | SR-081, SR-096 |
| SN-004 | 3 | SR-005, SR-041, SR-100 |
| SN-005 | 3 | SR-007, SR-008, SR-118 |
| SN-006 | 1 | SR-010 |
| SN-007 | 2 | SR-011, SR-105 |
| SN-008 | 1 | SR-062 |
| SN-009 | 2 | SR-014, SR-095 |
| SN-010 | 2 | SR-015, SR-127 |
| SN-011 | 2 | SR-016, SR-073 |
| SN-012 | 2 | SR-027, SR-132 |
| SN-013 | 5 | SR-017, SR-075, SR-082, SR-086, SR-144 |
| SN-015 | 5 | SR-019, SR-099, SR-126, SR-132, SR-133 |
| SN-019 | 2 | SR-023, SR-052 |
| SN-021 | 2 | SR-024, SR-100 |
| SN-022 | 4 | SR-008, SR-031, SR-071, SR-118 |
| SN-023 | 2 | SR-033, SR-136 |
| SN-024 | 5 | SR-034, SR-048, SR-094, SR-130, SR-142 |
| SN-025 | 3 | SR-038, SR-039, SR-116 |
| SN-026 | 1 | SR-040 |
| SN-027 | 6 | SR-018, SR-063, SR-123, SR-126, SR-138, SR-140 |
| SN-029 | 4 | SR-045, SR-046, SR-101, SR-102 |
| SN-030 | 3 | SR-049, SR-103, SR-104 |
| SN-031 | 2 | SR-053, SR-108 |
| SN-032 | 3 | SR-021, SR-055, SR-092 |
| SN-033 | 2 | SR-056, SR-119 |
| SN-034 | 4 | SR-035, SR-041, SR-059, SR-063 |
| SN-035 | 2 | SR-072, SR-073 |
| SN-036 | 3 | SR-065, SR-066, SR-122 |
| SN-037 | 6 | SR-063, SR-093, SR-094, SR-138, SR-139, SR-140 |
| SN-038 | 1 | SR-036 |
| SN-039 | 5 | SR-085, SR-086, SR-106, SR-107, SR-144 |
| SN-040 | 3 | SR-061, SR-114, SR-126 |
| SN-041 | 5 | SR-084, SR-110, SR-115, SR-116, SR-117 |
| SN-042 | 3 | SR-009, SR-121, SR-141 |
| SN-043 | 3 | SR-064, SR-112, SR-113 |
| SN-044 | 5 | SR-041, SR-089, SR-124, SR-125, SR-126 |
| SN-045 | 2 | SR-043, SR-104 |
| SN-046 | 3 | SR-047, SR-103, SR-104 |
| SN-047 | 2 | SR-109, SR-110 |
| SN-048 | 2 | SR-068, SR-111 |
| SN-049 | 2 | SR-128, SR-129 |
| SN-050 | 4 | SR-042, SR-123, SR-134, SR-135 |
| SN-051 | 3 | SR-097, SR-098, SR-099 |
| SN-052 | 4 | SR-067, SR-089, SR-090, SR-091 |
| SN-053 | 4 | SR-029, SR-092, SR-119, SR-120 |
| SN-054 | 2 | SR-131, SR-143 |

## Not applied, and calls a reviewer should check

- **R2-011:** refuted by the coordinator. No perspective record was written.
- **Moved down a tier, so no SR carries them:**
  - F-23: the destination-side "folder in the way fails at once" case goes to
    LLR under SR-041 or SR-067.
  - R2-024: "content kept for the remaining states keeps its stored form" on
    removal goes to LLR under SR-045.
  - R2-009 and F-16: the 60 s heartbeat and the confirmation wait of the larger
    of 90 s and the interval plus 30 s go to LLR under SR-075.
  - R2-014: the schedule letters and calendar rules go to the configuration
    interface (IF). The calendar rule is host local time and the month-end
    clamp.
- **My calls, not set by any ruling:**
  - **SR-043, runs covering several locations.** The value is 2 only when every
    location was refused before anything changed, 1 when any location failed or
    was refused, and 0 otherwise. A refusal per location (empty source, no
    space, retired form, a dead removal) is classed "not ready" and folds into
    that rule.
  - **SR-081, the size floor.** For files at or below 256 KiB, the file type
    decides, as in the legacy behaviour. Ruling (a) keeps "the size floor and
    the extension fallback". The merged tier had read this as "stored as it is".
  - **SR-137.** A link that is not followed is named, and the outcome stays
    complete. It does not fail the run.
  - **SR-144.** The resumed run reports part-failed (1).
  - **SR-140.** Value 2, with configuration-refused wording.
- **Unresolved, carried from the merge notes (no finding asked for it):**
  - Whether a check without the deep option satisfies "altered" in SR-049.
  - The possible missing needs (removal dry run, strict restore, owner
    overrides).
