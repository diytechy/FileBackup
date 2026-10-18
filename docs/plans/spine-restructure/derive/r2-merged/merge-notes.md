# Merged system-requirement tier: merge notes

This file goes with `system-requirements.toml` in the same folder. That file holds 107 rows: 58 keep their legacy ids and 49 are new, numbered SR-088 to SR-136. They were composed from the round-2 alignment map with the coordinator's rulings applied, and every row is Drafted.

Validation run on the finished file:
- It parses with tomllib, and the rows are in id order.
- No id appears twice. The kept legacy ids are exactly the map's 58 `keep_legacy_id` values, and the new ids run without gaps.
- Every `sn_refs`, `boundary_refs`, `da_refs` and `hat_refs` value resolves against the needs, external, assumptions and hats registries.
- Every `delivered_with` value resolves to a row in this file and shares at least one need with the row that cites it.
- Every requirement cell holds exactly one " shall ", and opens on an EARS keyword. No other cell uses "shall".
- Each row has either `da_refs` or `coincident`, never both, and its `form` is one of the three allowed values.
- A scan finds none of the source rows' file, configuration-key, switch or tool-product tokens in any cell.

## Cluster map

| Cluster | Final SR id(s) | Source rows used | Note |
|---|---|---|---|
| C-001 | SR-001 | O:SR-101 + L:SR-057 | merge: O requirement; L adds "no visibility-exclusion setting". Link and junction traversal stays unruled (see open items). |
| C-002 | SR-074 | O:SR-102 + L:SR-074 | merge: case-insensitive match, drive or share root, an unreadable system folder never fails the run nor changes a restore class. |
| C-003 | SR-088 | O:SR-103 | as recommended. |
| C-004 | SR-089 | O:SR-104 (+ A:SR-102 clause) | O row; sn_refs widened to the cluster's needs (adds SN-052); A's not-counted-as-captured-or-removed clause in acceptance. |
| C-005 | SR-067 | O:SR-105 + L:SR-067 | merge: legacy 3 attempts per file, retry only for faults that could change, immediate fail for a permanent fault, visible retry. |
| C-006 | SR-090 | O:SR-106 + A:SR-103 (+ legacy budget) | merge: legacy numbers carried: 3 attempts per file and one 60 s retry budget per configured location (the legacy SR names a shared per-set budget; its value, 60 s, is the legacy implementation's). A's 5 s per source not taken. |
| C-007 | SR-091 | O:SR-107 + A:SR-104 | merge: O's scope (files and folders) plus A's shared-bytes case. |
| C-008 | SR-021 | O:SR-108 + A:SR-105 | merge: A's distinct-paths-stay-distinct; the extension cases of dropped C-107 (L:SR-070) added as a permutation. |
| C-009 | SR-055 | O:SR-109 + L:SR-055 | merge: L's enumerated invalid-name classes and the earlier-entry-kept case; rewritten to one shall. |
| C-010 | SR-092 | O:SR-177 | derived (CROSS-PLATFORM), as recommended. |
| C-011 | SR-093, SR-094 | O:SR-110, O:SR-111 | pending (b): the change-detection state never lives inside a source; a configuration placing it there is refused. |
| C-012 | SR-036 | O:SR-112 (+ L:SR-036) | O row; legacy "an opted-in delete-all keeps the prior state" added to acceptance. |
| C-013 | SR-095 | O:SR-113 | pending (g): several locations in one configuration are normal, with no warning. |
| C-014 | SR-014 | O:SR-114 | as recommended. |
| C-015 | SR-003 | O:SR-115 + L:SR-060 | merge: within-one-run case; independence from extension and compression. |
| C-016 | SR-081 | O:SR-116 + L:SR-081 | pending (a): compression only on a measured saving; legacy 10% saving and 256 KiB floor carried; name-only skips and a missing measurement store as is, never compress by name. |
| C-017 | SR-096 | O:SR-117 (+ L:SR-081 clause) | O row; legacy "no measuring, tool not required, when off" added. |
| C-018 | SR-097, SR-098 | O:SR-118, O:SR-119 | as recommended. |
| C-019 | SR-099 | O:SR-120 | as recommended; kept beside SR-133 (the generic optional-extra row), which is the only other home. |
| C-020 | SR-005 | O:SR-121 + L:SR-005 | merge: legacy change definition (duplicate-only add, shared-content removal, time-only change), dated by the prior state's completion, same-second disambiguation. L:SR-028's storage-layout part not carried (design tier). |
| C-021 | SR-024, SR-100 | O:SR-130, O:SR-122 | as recommended; SR-024 takes the legacy id (the first recommended row). |
| C-022 | SR-059 | O:SR-123 + L:SR-051 | merge: kept-earlier-entry and failed-replacement cases; the shared copy survives removal of either twin. |
| C-023 | SR-035 | O:SR-133 | pending (d): re-derive changes from the backup's own record and report that it did. |
| C-024 | SR-045 | O:SR-124 + L:SR-045 | merge: oldest, middle, newest and only cases; kept content not re-formed; record entries unchanged; zero copy when safe. |
| C-025 | SR-046 | O:SR-125 + L:SR-046 | merge: legacy refusal classes become acceptance cases, all reported with the not-ready value. NOT carried: legacy owner overrides, the dry run, and the 2>3>4>1 removal precedence (no need asks for them; LLR or a needs question). |
| C-026 | SR-101 | O:SR-126 | as recommended; rewritten to one shall. |
| C-027 | SR-102 | A:SR-172 | derived (SECURITY); wildcard and not-a-saved-state cases from L:SR-046 added. |
| C-028 | SR-047 | O:SR-127 | as recommended. |
| C-029 | SR-103 | O:SR-128 | as recommended. |
| C-030 | SR-104 | O:SR-129 | as recommended. |
| C-031 | SR-011 | O:SR-131 + A:SR-121 | merge: A's calendar-period rule (host local time, month-end clamp) carried as acceptance. It is A's proposal; the Owner should confirm it. |
| C-032 | SR-105 | O:SR-132 | as recommended. |
| C-033 | SR-082 | O:SR-134 (+ L:SR-082 clauses) | O row; legacy torn-record and cut-off-evidence cases added; INTEGRITY-RECOVERABILITY attributed. |
| C-034 | SR-075 | O:SR-135 + L:SR-075 | merge: legacy 1800 s stale floor, max(90 s, interval + 30 s) confirmation, 60 s liveness, process identity insufficient across hosts, racing reclaimers. |
| C-035 | SR-017 | O:SR-136 + L:SR-017 | merge: legacy refusal triggers become acceptance cases. |
| C-036 | SR-085 | O:SR-137 | O row; the legacy platform-scope limit (one kernel, not across SMB/NFS hosts) is carried by DA-03's holds_when, not by row text. |
| C-037 | SR-106 | O:SR-138 | as recommended. |
| C-038 | SR-107 | O:SR-139 | as recommended. |
| C-039 | SR-086 | L:SR-086 re-authored | derived (FILESYSTEM-SEMANTICS); retry counts and log tokens left to LLR. |
| C-040 | SR-053 | O:SR-140 + L:SR-053 | merge: healing with unchanged metadata, reuse of a surviving copy, superseded state kept. |
| C-041 | SR-108 | O:SR-141 | as recommended. |
| C-042 | SR-049 | O:SR-142 | O row; legacy missing-everywhere versus missing-here distinction added. Open: whether a check that does not re-read content satisfies "altered". |
| C-043 | SR-109 | O:SR-143 | O row; legacy "content missing everywhere stays report-only" added. |
| C-044 | SR-110 | O:SR-144 | derived (INTEGRITY-RECOVERABILITY), as recommended. |
| C-045 | SR-111 | O:SR-145 | as recommended. |
| C-046 | SR-068 | O:SR-146 + L:SR-068 | merge: flipped-form, source-archive-stored-raw and matches-neither cases. |
| C-047 | SR-052 | O:SR-147 + L:SR-052 | merge: demand includes healed content and cross-volume history; a mount is one volume on Windows and Linux. |
| C-048 | SR-023 | O:SR-148 | as recommended (exit 2). |
| C-049 | SR-064 | O:SR-149 + A:SR-133 (+ L:SR-064) | pending (f): A's envelope as proposed values; legacy linear audit at 10,000 entries carried. The small-change run moved to SR-113 to avoid two homes. |
| C-050 | SR-112 | O:SR-150 | pending (f): 4 GiB peak, proposed. |
| C-051 | SR-113 | O:SR-151 + A:SR-134 | pending (f): 30 min for at most 1 GiB changed; doubling history adds less than 2x. |
| C-052 | SR-114 | O:SR-152 | as recommended. |
| C-053 | SR-061 | O:SR-153 + L:SR-061 | pending (e): a retired form is refused by name everywhere, restorers included (exit 2); damaged-versus-retired distinction kept. L's compression clause lives in SR-111. |
| C-054 | SR-084 | O:SR-154 | as recommended. |
| C-055 | SR-115 | O:SR-155 | as recommended; "supported" read per pending (e). |
| C-056 | SR-116 | O:SR-156 | sn_refs widened to SN-025 (the cluster's needs); legacy opt-in strict mode not carried; folder-metadata case from L:SR-065. |
| C-057 | SR-117 | O:SR-157 | as recommended. |
| C-058 | SR-007 | O:SR-160 | as recommended. |
| C-059 | SR-008 | O:SR-161 | as recommended. |
| C-060 | SR-010 | O:SR-162 | as recommended. |
| C-061 | SR-031 | O:SR-163 | as recommended. |
| C-062 | SR-118 | O:SR-164 + A:SR-143 | merge: a missing tool is a precondition, exit 2 (the legacy value); see the needs-defect note on SN-026. |
| C-063 | SR-071 | O:SR-165 + L:SR-071 | merge: an unmet floor or an unresolvable target is exit 2, never damage; a parent-folder component is refused. |
| C-064 | SR-072 | O:SR-166 | as recommended; legacy macOS executable-bit volume limit left to LLR. |
| C-065 | SR-073 | O:SR-167 + L:SR-073 | merge: no console and no desktop gives usage and exit 2; console only gives a typed prompt; a cancelled choice never defaults. |
| C-066 | SR-016 | O:SR-181 | as recommended; rewritten to one shall; component resolution never prompts. |
| C-067 | SR-056 | O:SR-168 | as recommended. |
| C-068 | SR-119 | O:SR-169 | as recommended. |
| C-069 | SR-029, SR-120 | A:SR-146, A:SR-147 | as recommended; SR-029 takes the legacy id. |
| C-070 | SR-039 | O:SR-171 | O row (exit 3); legacy "not a record at all is 2, which takes precedence" added. Legacy count-only-disagreement warning not carried. |
| C-071 | SR-038 | L:SR-038 re-authored | derived (INTEGRITY-RECOVERABILITY); no format named. |
| C-072 | SR-009 | O:SR-172 | O row; legacy prefix-sharing sibling case added. |
| C-073 | SR-121 | O:SR-173 + A:SR-150 | merge: link redirection case. |
| C-074 | SR-066 | O:SR-174 + L:SR-066 | merge: a time never fails a restore. |
| C-075 | SR-065 | O:SR-175 | as recommended. |
| C-076 | SR-122 | O:SR-176 | as recommended. |
| C-077 | SR-040 | A:SR-154 | A row re-voiced: values 0 to 4, precedence 2>3>4>1, per-class counts. |
| C-078 | SR-062 | O:SR-179 | as recommended; legacy "nothing depends on the view" not carried (no need asks). |
| C-079 | SR-063, SR-123 | O:SR-180 + L:SR-063 | merge split into two decisions: the listing-location refusal (adds the foreign-content case) and the description-versioning rule from L:SR-063 (filed under SN-050 and SN-027). |
| C-080 | SR-043 | O:SR-182 | pending (c): distinct values always; legacy 0/1/2 carried; no source pins the busy/not-ready value. |
| C-081 | SR-124 | O:SR-183 | as recommended. |
| C-082 | SR-125 | O:SR-184 + A:SR-160 | pending (f): 2 minutes, proposed. |
| C-083 | SR-126 | O:SR-185 | as recommended. |
| C-084 | SR-015 | O:SR-186 | as recommended. |
| C-085 | SR-127 | O:SR-187 | as recommended. |
| C-086 | SR-128 | O:SR-188 | as recommended. |
| C-087 | SR-129 | O:SR-189 | O row; pending (g) applied (both configuration forms). |
| C-088 | SR-034 | O:SR-190 | O row; legacy separate writable state location added. |
| C-089 | SR-130 | O:SR-191 | as recommended. |
| C-090 | SR-048 | L:SR-048 re-authored | filed under SN-024 per ruling 3; SN-024 understates it (needs defect). |
| C-091 | SR-131 | O:SR-192 | as recommended. |
| C-092 | SR-027 | O:SR-193 | as recommended. |
| C-093 | SR-132 | O:SR-194 | as recommended; the first-use fetch never prompts (SN-011). |
| C-094 | SR-019 | O:SR-199 | as recommended; legacy runtime-version floor left to LLR. |
| C-095 | SR-133 | O:SR-200 | as recommended. |
| C-096 | SR-042 | O:SR-195 | pending (g): the native-Windows form is versioned and held to the closed-key and credential rules. |
| C-097 | SR-134 | O:SR-196 | as recommended. |
| C-098 | SR-135 | O:SR-197 | pending (g): every form states its version. |
| C-099 | SR-018 | O:SR-198 | as recommended; legacy "no log truncation" added. |
| C-100 | SR-033 | O:SR-158 | as recommended. |
| C-101 | SR-136 | O:SR-159 | as recommended. |
| C-102 | none (dropped) | L:SR-002, L:SR-030 | moved to the design tier (IF) |
| C-103 | none (dropped) | L:SR-013 | moved to the design tier (IF) |
| C-104 | none (dropped) | L:SR-025 | moved to the design tier (IF) |
| C-105 | none (dropped) | L:SR-037 | moved to the design tier (LLR) |
| C-106 | SR-041 | L:SR-041 re-authored | derived (UNATTENDED-OPS); the move mechanism dropped. |
| C-107 | none (dropped) | L:SR-058, L:SR-069, L:SR-070 | moved to the design tier (IF) |
| C-108 | none (dropped) | L:SR-083 | moved to the design tier (LLR) |
| C-109 | none (dropped) | L:SR-087 | moved to the design tier (LLR) |

Source prefixes: A = r2-astra, O = r2-opus, L = the stripped legacy tier.

## Moved to the design tier

No SR is written for these clusters. Each goes down a tier: IF for formats, layouts, digests and artifacts, LLR for mechanisms.

- **C-102** (L:SR-002, L:SR-030) goes to **IF**: the content-digest algorithm and its text representation are an interface fact (the record format). The observable outcomes are in SR-003, SR-056 and SR-033.
- **C-103** (L:SR-013) goes to **IF**: the constant storage-layout marker is a record-format field. Retired-form recognition is in SR-061.
- **C-104** (L:SR-025) goes to **IF**: the record-of-contents layout, its round-trip and its empty-set rules are the record format. Atomic publication is an LLR mechanism under SR-082.
- **C-105** (L:SR-037) goes to **LLR**: tool discovery and path overrides (and the compression-effort setting) are mechanisms under SR-019. "A backup-only fault never blocks a restore" is not written as an SR; the Owner may want it as a derived row.
- **C-107** (L:SR-058, L:SR-069, L:SR-070) goes to **IF**: the stored-object naming grammar and layout are an artifact format. L:SR-070's observable extension cases moved into SR-021's permutations.
- **C-108** (L:SR-083) goes to **LLR**: the handling of incomplete record-publication leftovers is a mechanism under SR-074 (the system's own working files) and SR-017 / SR-075.
- **C-109** (L:SR-087) goes to **LLR**: the persistent exclusion artifact is a mechanism of SR-085 and SR-086. Its invisibility to content consumers is SR-074.

## Pending Owner rulings

Each row below is written on the coordinator's default. The Owner either confirms the default or picks the alternative. That makes 7 rulings over 13 rows.

- **(a) Compression decision.** Row: **SR-081**. Cluster: C-016 (C-017 / SR-096 is consistent with either answer).
  - Default (written): SN-003's rule. Content is compressed only where a measurement shows a saving of at least 10%, and never on file name alone. The owner still chooses between measuring off, skipping known-incompressible types without measuring, and measuring every file, and nothing at or below the 256 KiB floor is compressed. A missing measurement means "store as it is", not "compress by extension". As a consequence, under this default the "measuring off" choice compresses nothing even with compression on, whereas in legacy it applies the extension policy.
  - Alternative: keep the legacy extension fallback. Mode off and the below-floor tail then apply the extension policy, and a missing probe falls back to it with a warning. This would mean amending SN-003, whose "whatever the file's name" this alternative breaks.
- **(b) Change-detection state location.** Rows: **SR-093, SR-094**. Cluster: C-011.
  - Default (written): the change-detection state never lives inside a source tree. When no location is configured it goes outside the source, and a configuration placing it inside a source is refused.
  - Alternative: allow the legacy default (the source root). SN-037 would then need amending, because writing that state into the source alters it.
- **(c) Distinct outcome codes.** Row: **SR-043**. Cluster: C-080 (and C-090 / SR-048, which reuses the same vocabulary).
  - Default (written): distinct values are always returned, with no opt-in: 0 complete, 1 part failed, 2 configuration refused, and a fourth value for busy or not ready. No source pins that fourth value. Legacy folds busy into 1 for a backup and into 2 for a removal, so it is a new number the Owner must choose.
  - Alternative: the legacy opt-in. Without it, configuration errors are terminating and a failed set exits 1.
- **(d) Missing or unreadable change-detection state.** Row: **SR-035**. Cluster: C-023.
  - Default (written): the run re-derives the changes from the backup's own record and reports that it did.
  - Alternative: refuse. This is the legacy behaviour: exit non-zero, change nothing, create no saved state.
- **(e) Retired forms versus SN-041.** Rows: **SR-061** (and SR-115, whose "supported version" this reading defines). Clusters: C-053, C-055.
  - Default (written): a store or a state in a retired form is refused by name and never misread. That covers backup, removal, repair and every restorer (exit 2), and a check reports it as a finding. SN-041 is read as covering states written by a supported version.
  - Proposed SN-041 clarification: change "whatever version of FileBackup wrote it" to "whatever supported version wrote it", and state that a retired form is refused by name, never misread.
  - Alternative: restorers restore retired forms, which SN-041's current wording asks for.
- **(f) Progress interval and performance budgets.** Rows: **SR-125** (C-082), **SR-064** (C-049), **SR-112** (C-050), **SR-113** (C-051).
  - Default (written, each marked "Proposed"): Astra's numbers. Progress at least every 2 minutes. A library of 2 TiB in one million files, on a four-core host with 8 GiB of available memory and 200 MiB/s local storage. A check and a full restore each within 8 h. A small-change run (at most 1 GiB changed) within 30 min, with doubling the history adding less than 2x. Peak memory 4 GiB. SR-064 also carries the legacy linear-audit check at 10,000 entries.
  - Alternative: the Owner supplies other figures. The legacy tier has none at this scale.
- **(g) Native-Windows configuration form, and several sets.** Rows: **SR-042** (C-096), **SR-135** (C-098), and **SR-095** (C-013) and **SR-129** (C-087), which follow from the same ruling.
  - Default (written): the native-Windows configuration form stays supported. It states its version as the JSON form does and obeys the same closed-key and credential rules. Several sets in one configuration are normal (SN-009), with no warning.
  - Alternative: the legacy exemptions. The native-Windows form would be unversioned and exempt from the closed-key and credential rules, and several sets would draw a warning pointing at a one-set convention.

## Needs-defect notes (to raise with the Owner)

- **SN-024 understates SR-048 (C-090).** SN-024 reads as backups only ("can run backups inside a container"). A host that backs up in a container also needs retention there: the saved-state report and removal, with the same outcome vocabulary. Ruling 3 files SR-048 under SN-024 alone. The fix belongs in the need: widen SN-024 to "backups, removals and the saved-state report", or add a need for container-run retention. Until then, SR-048 traces to a need whose text does not demand it.
- **SN-041 wording versus retired forms (C-053).** See pending ruling (e). The need promises restorability "whatever version wrote it", but the system refuses retired forms by name. The proposed clarification is "whatever supported version", with retired forms refused by name.
- **SN-026 class of a missing restore tool (C-062).** SN-026 lists "host or tool problem" as one class, which reads as though a missing tool belongs there (value 4). SR-118 and SR-040 follow the legacy value instead: a missing tool is a precondition, exit 2. That is the right outcome for a script, because the restore can be retried once the tool is installed and nothing was written. SN-026 should say that a missing required tool is a precondition, and that "tool problem" means a present tool that fails.
- **SN-003 versus the name-based modes (C-016).** See pending ruling (a). If the Owner keeps the legacy extension fallback, SN-003's "whatever the file's name" has to change.
- **SN-037 versus the legacy state location (C-011).** See pending ruling (b). If the legacy default survives, SN-037 has to say what the system may write into a source.
- **Possible missing needs that the derivations surfaced and this tier does not write:**
  - a removal dry run (C-025);
  - an opt-in strict restore that refuses a state lacking completeness evidence (C-056, C-070);
  - legacy owner overrides on removal refusals (C-025);
  - "nothing depends on the browse view" (C-078);
  - "a backup-only setting never blocks a restore" (C-105);
  - file-level hidden, system and read-only attributes on restore (SN-036 asks only about folders).

## Other open items (no ruling requested by the coordinator)

- **Links and junctions in a source (C-001).** SR-001 leaves traversal unruled, as the legacy tier did. SN-001's "the whole of each source tree" makes content behind an unfollowed junction a silent omission unless the run's record names it.
- **The "altered" clause of SR-049 (C-042).** SR-049 reports "altered" content. The legacy check detects altered bytes only with a deep option. Is a check without that option compliant?
- **The busy or not-ready value in SR-043 (C-080).** No source pins it (see (c)). SR-046 and SR-086 report "the busy outcome" or "the not-ready value" by class only, never by number.
- **The re-read schedule in SR-011 (C-031).** SR-011 carries A's calendar rule: host local time and the month-end clamp. It is A's proposal and is not on the coordinator's pending list, but the Owner should confirm it.
- **The retry budget in SR-090 (C-006).** SR-090 carries 60 s per configured location. That figure is the legacy implementation's budget, because the legacy SR text names a shared per-set budget without a value. A proposed 5 s per source.

## Coverage check

Each of the 48 needs, with the rows that cite it. None is at zero.

| Need | SR count | Rows |
|---|---|---|
| SN-001 | 5 | SR-001, SR-035, SR-074, SR-088, SR-089 |
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
| SN-013 | 4 | SR-017, SR-075, SR-082, SR-086 |
| SN-015 | 5 | SR-019, SR-099, SR-126, SR-132, SR-133 |
| SN-019 | 2 | SR-023, SR-052 |
| SN-021 | 2 | SR-024, SR-100 |
| SN-022 | 4 | SR-008, SR-031, SR-071, SR-118 |
| SN-023 | 2 | SR-033, SR-136 |
| SN-024 | 4 | SR-034, SR-048, SR-094, SR-130 |
| SN-025 | 3 | SR-038, SR-039, SR-116 |
| SN-026 | 1 | SR-040 |
| SN-027 | 4 | SR-018, SR-063, SR-123, SR-126 |
| SN-029 | 4 | SR-045, SR-046, SR-101, SR-102 |
| SN-030 | 3 | SR-049, SR-103, SR-104 |
| SN-031 | 2 | SR-053, SR-108 |
| SN-032 | 3 | SR-021, SR-055, SR-092 |
| SN-033 | 2 | SR-056, SR-119 |
| SN-034 | 4 | SR-035, SR-041, SR-059, SR-063 |
| SN-035 | 2 | SR-072, SR-073 |
| SN-036 | 3 | SR-065, SR-066, SR-122 |
| SN-037 | 3 | SR-063, SR-093, SR-094 |
| SN-038 | 1 | SR-036 |
| SN-039 | 4 | SR-085, SR-086, SR-106, SR-107 |
| SN-040 | 3 | SR-061, SR-114, SR-126 |
| SN-041 | 5 | SR-084, SR-110, SR-115, SR-116, SR-117 |
| SN-042 | 2 | SR-009, SR-121 |
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
| SN-054 | 1 | SR-131 |
