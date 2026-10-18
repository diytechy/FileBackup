# Strip adjudication

Two independent proposals per tier (GPT-6 Astra, medium, via Codex; Claude Opus, medium), each from `strip-brief.md` without sight of the other. The coordinator's ruling follows. The per-row comparison is in `compare-{sn,sr,llr}.md`, and the adjudicated rows, with the removal ledger saying where each removed piece belongs, are in `final/`.

## SN

**Base: opus-sn-sr.** Keeps each need's outcome and its reason with fewer losses; Astra's need text is thinner and occasionally drops a stakeholder-visible clause.

Result: {'strip': 28, 'keep': 7, 'retire': 1}. 11 removed pieces carry a destination tier (LLR/IF/TC) for the restructure to place.

Overrides:

- **SN-005** → strip. Astra flagged 'no installs' against the restore-tool floor (SN-022/035). The ruled vision settles it: FileBackup is never needed to recover, and the restore kit runs with commonly available tools.
- **SN-007** → strip. Opus kept the configuration key and its codes as declared vocabulary. A need is the owner's outcome; the key belongs to the configuration interface. Both proposers' acceptance still named the key.
- **SN-024** → strip. Opus retired the row as delivery. Only the build and export tooling is delivery (D3); running backups in a container on a backup host is a product need, and the gap map lists container operation as a need. Astra's strip keeps that runtime need.

Retired: SN-028.

## SR

**Base: astra-sn-sr.** Follows the brief's tier rule: an SR keeps what is observable at the system boundary and moves internal mechanism down, logging each move with destination LLR. Opus kept the mechanism inline (89% of source length), which the restructure would have to strip again.

Result: {'strip': 78, 'keep': 2, 'retire': 1}. 107 removed pieces carry a destination tier (LLR/IF/TC) for the restructure to place.

Overrides:

- **SR-033** → strip. Astra flagged it: no Linux backup engine exists. It is a phase-deferred Drafted row under SN-023, so it stays, stripped, and the flag goes to the findings.
- **SR-034** → strip. Opus retired it as delivery. As with SN-024, the container runtime contract is product; only build and export are delivery.
- **SR-052** → strip. Astra flagged a visible code-versus-row gap (source scanning and index sanitation precede the capacity refusal the row says comes before any mutation). Kept as written; recorded as a finding.

Retired: SR-044.

## LLR

**Base: opus-llr.** The LLR is where mechanism and its reasons live. Opus keeps both in contract voice; Astra's condensation (52% of source length) drops arguments the restructure's rationale cells will need.

Result: {'strip': 80, 'keep': 3, 'retire': 3}. 41 removed pieces carry a destination tier (LLR/IF/TC) for the restructure to place.

Overrides:

- **LLR-026** → strip. Opus added 'This bounds the cost to one existence check per stored object per run', which no source cell states. Removed.
- **LLR-089** → retire. Opus retires it as one revision bump's history, with its durable remnants on LLR-076 and LLR-094; Astra kept the compatibility clause. The clause is LLR-094's, so the row is history.

Retired: LLR-034, LLR-044, LLR-089.

## Behaviour findings for the Owner

Each is a place where a proposer, checking the code, found the row and the code disagreeing, or two rows disagreeing. Stripping kept the side the code implements, or kept the row and flagged it. None changes behaviour; each needs a ruling during the restructure.

| row | raised by | verdict | conflicts with | note |
|---|---|---|---|---|
| SN-003 | astra-sn-sr | strip | SR-004, SR-081 | The compression decision code supports measured gain above the 256 KiB floor in always mode, not the former extension examples. Below-floor, off, excluded-extensions and unavailable-probe exceptions remain in SR-081; the broader owner vision is not fully implemented by those exceptions. |
| SN-005 | astra-sn-sr | flag |  | Kept “no installs” as an obligation, but the declared restore tool floors require tools that a clean host may lack; this is an obligation/code gap, not noise to strip. |
| SN-029 | astra-sn-sr | strip | SR-058, SR-061 | Current code has one content-addressed layout with raw or compressed objects; the four-storage-mode claim is stale. |
| SN-032 | astra-sn-sr | strip | SR-055 | Source scanning preserves a previously stored row under a non-portable name; SR-055 is supported by the code, so the unconditional no-row claim is narrowed to new content. |
| SN-036 | astra-sn-sr | strip | SR-058, SR-061 | The code supports one storage layout with optional compression, not four storage modes. |
| SN-013 | opus-sn-sr | strip | SR-017, SR-075 | The always-abort side contradicts SR-017/SR-075, which reclaim a staging area proved abandoned; the code implements the reclaim (move-aside to an aside folder, refuse on any doubt), so the stale always-abort wording is stripped. |
| SN-013 | astra-sn-sr | strip | SR-017, SR-075 | Current staging classification reclaims stale marker-only or empty staging, subject to ownership and exclusivity checks; unconditional refusal is stale. The atomic rename mechanism belongs at LLR. |
| SR-004 | astra-sn-sr | strip | SN-003, SR-037 | The code follows measured gain in always mode and rejects an invalid compression level at backup preflight; import-time fallback to 9 is not permission for such a backup to proceed. |
| SR-007 | astra-sn-sr | strip | SR-044 | The kit copy implementation supplies seven artifacts; the eight-artifact claim in SR-044 is stale. Exact artifact enumeration and dependency structure move to LLR; compatibility remains subject to SR-061’s format refusal. |
| SR-016 | astra-sn-sr | strip | SR-020 | Current dependency initialization refuses unavailable compression tools when compression is selected; only optional media metrics degrade. The broad optional-tool acceptance was narrowed accordingly. |
| SR-017 | astra-sn-sr | strip | SN-013 | The code supports selective stale staging recovery, not unconditional refusal. Prune-owned abandoned staging remains a refusal. |
| SR-031 | opus-sn-sr | strip | SR-071 | 'GNU coreutils/awk' contradicts SR-071, which forbids GNU-specific dependence; the restorer's preflight requires bash 4+, gawk and xxhsum, with no GNU coreutils check, so SR-071's side is kept and the floor is cited there. The storage modes no longer exist. |
| SR-033 | astra-sn-sr | flag | SR-058, SR-069, SR-081 | The current engine uses unconditional content addressing and probe-based compression; the named bash backup engine does not exist in bash/. The interoperability obligation is retained, but its separate-producer implementation claim needs resolution. |
| SR-044 | astra-sn-sr | retire | SR-007 | Move the proof obligation to TC. Current kit copying supports SR-007’s seven-artifact count, not this row’s eight; exact artifacts belong below SR. |
| SR-045 | astra-sn-sr | strip | SR-061, SR-069 | Current prune preserves the source object name and refuses retired formats; legacy Original naming, synthesis and four-mode claims are stale. Destination election and publication details move to LLR. |
| SR-045 | opus-sn-sr | strip | SR-061 | The 'prune still serves legacy Original rows' clause contradicts SR-061 (a legacy-form store is refused, no read path exists); the code has no legacy name synthesis in prune and refuses/reports 'Original' rows, so SR-061's side is kept. |
| SR-050 | astra-sn-sr | strip | SR-068 | Current direct-object form detection and both restore loops support SR-068: Compressed is not correctness authority even for nonblank locations. The contradictory direct-location clause is removed. |
| SR-050 | opus-sn-sr | strip | SR-068 | SR-050 said an own-DataPath entry is still resolved by its Compressed column; SR-068 says the column is consulted for no correctness decision. Both restorers now derive an own-DataPath object's form from its bytes (the stored-object form sniff), so SR-068's side is kept. 'which SR-004 stores raw' is no longer categorical (the probe decides), so it was softened. |
| SR-052 | astra-sn-sr | flag |  | The no-mutation obligation is retained and flagged: source scanning, backup-index sanitation and staging the prior index visibly precede the capacity check in the current pipeline. This is an implementation gap, not stale text to discard. |
| SR-055 | astra-sn-sr | strip | SN-032 | The source walker freezes existing entries under invalid names. Only newly skipped content receives no entry, resolving SN-032’s unconditional no-row claim. |
| SR-058 | astra-sn-sr | strip | SR-069, SR-033, SN-029, SN-036 | The code implements SR-069’s 22-character base-57 hash and underscore grammar, not the old space-separated grammar or four layout modes. The persisted storage format is an observable boundary contract; encoding mechanics remain below SR. |
| SR-058 | opus-sn-sr | strip | SR-069 | '<hashShort> <sizeShort><ext>' is the retired space-separated base-85 grammar; SR-069's base-57 '<hash>_<len><ext>' is what the code generates, so SR-069's side is kept and this row now points at it. |
| SR-068 | astra-sn-sr | strip | SR-050 | The current byte-based form detector and both restore loops support this row over SR-050’s stale direct-location metadata clause. Signature, length and digest decision mechanics are transferred to LLR. |
| SR-069 | astra-sn-sr | strip | SR-058 | The current encoder and parser implement this grammar; SR-058’s old space-separated name is stale. Persisted name vocabulary and refusal limits remain as boundary behavior; the single-parser implementation constraint moves to LLR. |
| SR-075 | astra-sn-sr | strip | SN-013, SR-017 | Current code uses exclusive creation, not the stale temp-write-and-rename rationale, and fences five boundaries, not the acceptance’s three. Selective recovery agrees with SR-017 and supersedes SN-013’s unconditional refusal; exact record schema, publication and nonrecursive cleanup algorithms move to LLR. |
| SR-081 | astra-sn-sr | strip | SN-003, SR-033 | The current decision code supports measured aggregate gain rather than extension-based examples in always mode. The exact sampling offsets, codec lifecycle, pure decision function and group memo mechanism move to LLR; observable thresholds, cost bounds and fallback remain. |
| SR-084 | astra-sn-sr | strip | SR-061 | Existing supported kits need no refresh for atomic index publication. SR-061 and current format gates do not support the unrestricted “any earlier revision” claim; the specific revision-13 bump is provenance, not a standing obligation. |
| LLR-004 | astra-llr | strip | LLR-086, SR-081 | The opening extension-only decision conflicts with LLR-086/SR-081; the current composed decision implements measured compression, retaining the list for the specified modes, floor and fallback. |
| LLR-008 | opus-llr | strip | LLR-068 | 'Decompresses .7z rows' reads as a decision from the row's name/flag; the restorers now decide the form from the located file's bytes (LLR-068 side, which the code implements). |
| LLR-008 | astra-llr | strip | LLR-068, SR-068 | The .7z-row shorthand is stale if read as filename-driven expansion; current restorers implement LLR-068/SR-068 byte-derived form and (hash,length) recovery. |
| LLR-017 | astra-llr | flag |  | The 600 s wait bound is retained, not stripped: current code caps the declared cadence at 600 s and then adds a 30 s margin, allowing a 630 s confirmation wait. This visibly differs from the row's bound and needs adjudication. |
| LLR-018 | opus-llr | strip | LLR-043 | LLR-018 said 'throws "Config file not found"'; LLR-043 says the missing-file refusal routes through the config-failure exit (status 2 under the exit-code switch). The code supports LLR-043 and its message names the path; 'refuses' is worded to be true of both, and the stale throw/message wording is stripped. |
| LLR-023 | opus-llr | strip | LLR-068 | The code skips Compressed=Yes rows from the sum and logs a note that the true need is higher; LLR-068 describes that estimate as explicitly approximate. The 'decompressed sizes' clause was stale; the code supports LLR-068. Whether excluding compressed rows meets SR-023's intent is a restructure question. |
| LLR-040 | astra-llr | strip | LLR-050 | Current pool recovery returns no CandidateError: unusable dependencies and unreadable storage are host failures, while failed candidate expansion with a usable tool is content damage. LLR-050's older candidate-error claim is stale. |
| LLR-043 | opus-llr | strip | LLR-018 | Kept the side the code implements: the missing-file check exits through the configuration-failure path (see LLR-018). The container entry point is kept as a shipped launcher. |
| LLR-047 | astra-llr | flag |  | Retained the O(stored objects) claim, but the code keeps a DataPath entry per non-blank manifest row, including duplicate references, so that bound is not established by dropping full rows. Prune still explicitly retains full manifests; neither issue is repaired by stripping. |
| LLR-049 | astra-llr | strip | LLR-059 | The code permits policy changes to leave both stored forms of a content key; LLR-059's older-stores-only qualification is stale. |
| LLR-050 | opus-llr | strip | LLR-040, LLR-068 | Code supports LLR-040: the locator never returns CandidateError (a failed expand folds into the ContentMissing detail). Code supports LLR-068 for the non-blank-DataPath branch: the form is read from the bytes, not the Compressed column. |
| LLR-050 | astra-llr | strip | LLR-068, SR-068, LLR-040 | The named-DataPath branch's Compressed-driven rule is stale; current restorers implement LLR-068/SR-068 for that branch too. The locator also no longer reports CandidateError, as LLR-040's retained contract specifies. |
| LLR-052 | astra-llr | strip | LLR-060, SR-061 | Current capacity estimation contains no pending storage transformation demand; code supports LLR-060/SR-061's removal of layout migration. |
| LLR-059 | astra-llr | strip | LLR-049 | The claim that two hash names for one content key occur only in older stores is stale; current policy changes can produce both forms as LLR-049 describes, while the final-manifest claim rule still holds. |
| LLR-060 | astra-llr | strip | LLR-052 | Current code implements no migration and no migration-capacity demand; LLR-052's transformation term is stale. |
| LLR-068 | astra-llr | strip | LLR-050, SR-050 | Current restorers support this byte-derived contract; LLR-050 and SR-050's named-path reliance on Compressed is stale. |
| LLR-086 | astra-llr | strip | LLR-004 | Current composed compression code supports this measured decision; LLR-004's opening extension-only claim is stale. |
