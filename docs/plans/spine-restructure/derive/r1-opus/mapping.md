# Round-1 need mapping (r1-opus)

## Legacy needs SN-001 to SN-036

- **SN-001** kept as SN-001: reworded to the outcome (every file captured, none skipped silently); "never silently skipped" moved from `why` into `need`; acceptance no longer names the index file; absorbs SN-018 and the hidden/system/volume-folder scope.
- **SN-002** kept as SN-002: acceptance now states the outcome (space of one copy, both restore) rather than the one-stored-object mechanism; scope widened to across runs and states.
- **SN-003** kept as SN-003: compression by measured gain only; file-type and archive-format wording removed; made optional ("where the owner turns compression on").
- **SN-004** split into SN-004 and SN-006: SN-004 keeps the *keeping* of dated saved states; the *restoring* half is SN-006; snapshot folder naming moved down to design.
- **SN-005** kept as SN-005: "no installs" replaced by "only the documented, commonly available restore tools", which agrees with SN-022's tool floor; carrier wording removed.
- **SN-006** kept as SN-006: now the one home of "restore a chosen saved state exactly", absorbing SN-004's restore half; layout words removed.
- **SN-007** kept as SN-007: the setting name and its value codes moved down to SR; the need is the speed-versus-integrity trade-off, with an acceptance that a hidden change is eventually captured.
- **SN-008** kept as SN-008: "generated index" mechanism and layout history removed from `why`; the outcome is see-and-find without restoring.
- **SN-009** kept as SN-009: the config key removed; the need is one job, several roots, each failing independently.
- **SN-010** kept as SN-010: absorbs SN-020 (notification failure never changes the outcome); the flag name removed.
- **SN-011** split into SN-011 and SN-045: SN-011 keeps "never waits for a person"; the pass/fail signal became SN-045, widened to the outcome classes of every operation; the runtime name removed.
- **SN-012** kept as SN-012 (Provision): file and helper-script names removed; the dependency-install clause restated as "obtained on first use or named with how to obtain it", which does not conflict with the container; the config contract half split out to SN-050.
- **SN-013** kept as SN-013: the staging-folder and rename-after-write mechanism moved down to SR/design; the outcome (no half-written state built on or read as complete; no indefinite block) kept, with the "recovers by itself only when nothing would be lost" clause in acceptance.
- **SN-014** merged into SN-027: a missing configuration is one case of a refused configuration.
- **SN-015** kept as SN-015 (Startup): absorbs SN-016; product names removed; required versus optional prerequisites stated as the outcome.
- **SN-016** merged into SN-015: a missing tool for a selected feature is a missing prerequisite; the media-metric degradation is now SN-015's "optional extra skipped visibly", and the media feature itself is SN-051.
- **SN-017** merged into SN-032: awkward names restoring exactly and unportable names refused loudly are one outcome, "a file's name never comes back wrong".
- **SN-018** merged into SN-001: a nested file named like the backup's own files is part of "every file is captured".
- **SN-019** kept as SN-019: absorbs SN-030's capacity half; now covers both backup and restore running out of space, refusing before writing.
- **SN-020** merged into SN-010.
- **SN-021** kept as SN-021: "identical index rows" instrument replaced by the observable outcome (no reported changes, no new saved state).
- **SN-022** kept as SN-022: absorbs SN-035's macOS half (restore on any of Windows, Linux, macOS; never false damage on a different tool flavour); script name removed.
- **SN-023** kept as SN-023 (priority C): "bash engine" mechanism removed; restated as interchangeability of Linux-made and Windows-made backups.
- **SN-024** kept as SN-024: the constraints that sat only in `why` (no host runtime install, read-only source, no elevated rights) moved into `need` and `acceptance`; the instrument removed; build and export tooling left outside the spine as delivery; "source untouched" generalised to SN-037.
- **SN-025** kept as SN-025: the witness mechanism moved down; the outcome is "refuse a damaged or substituted record before writing"; its "older backup without proof still restores" clause moved to SN-041.
- **SN-026** kept as SN-026: light reword; the restore's outcome classes stay here, the backup-side classes are SN-045.
- **SN-027** split into SN-027 and SN-050 (absorbs SN-014): SN-027 keeps validation and refusal (Startup); the documented, versioned contract for hosts is SN-050; the two file formats moved down to design.
- **SN-028** retired: proof of the container in automated test runs is a test-tier matter (Owner ruling), not a stakeholder outcome; the id is not reused.
- **SN-029** split into SN-029 and SN-046: SN-029 keeps safe removal of saved states with refusal and interruption safety, the authority clause (the tool does the removing) argued in `why` and carried by acceptance; the reclaim forecast is SN-046; stale storage-mode wording removed.
- **SN-030** split into SN-030, SN-047, SN-048 and SN-019: SN-030 keeps the read-only whole-store check (and absorbs SN-031's reporting half); repair is SN-047; compression-policy-change safety is SN-048; the capacity clause merged into SN-019.
- **SN-031** kept as SN-031: the internal function name removed from `why`; now the heal-on-next-run outcome; its "verification reports what it cannot heal" half moved into SN-030.
- **SN-032** kept as SN-032: absorbs SN-017; the archive tool's quoting and the restorer's parsing (mechanism) removed from `why`.
- **SN-033** kept as SN-033: "surviving pool copy" mechanism restated as "another intact copy in the backup".
- **SN-034** kept as SN-034: widened from "a later run" to "any later operation of the tool", making it the one home of the vision's "never loses content a saved state still depends on"; flag name removed. Kept rather than merged into SN-004 because keeping states (SN-004) and never damaging what they share are different outcomes.
- **SN-035** split into SN-035 and SN-022: SN-035 keeps the guided restore (no command to recall, outcome stays on screen, scripted calls unaffected); the macOS and other-tool-flavour half merged into SN-022; launcher names and flags removed.
- **SN-036** kept as SN-036: mechanism removed from `why`; stale storage-mode wording removed; its "a backup written without this record restores as before" clause moved to SN-041.

## New needs

- **SN-037** source left untouched: the vision ("never alters the files it backs up"); legacy SR-034's read-only source rationale; gap map Appendix A "the source left untouched".
- **SN-038** a vanished source never discards the backup: legacy SR-036 (refusal when a populated source enumerates empty, opt-in to allow it); gap map Appendix A.
- **SN-039** concurrent operations on one backup: legacy SR-085, SR-086, SR-087 (mutation exclusion, refusal, read-only operations unaffected, release on process death); gap map Appendix A.
- **SN-040** a newer version continues an existing backup or refuses its form by name (Startup): legacy SR-061 (retired formats refused before mutation with a remedy), SR-084; gap map "store upgrade and migration".
- **SN-041** every saved state stays restorable across versions, kits refreshable: legacy SR-007 (snapshots keep their kit, explicit refresh, older launchers recognised), SR-084 and SR-087 (no kit refresh required), and the compatibility clauses of legacy SN-025 and SN-036.
- **SN-042** a restore never writes into the backup or outside its target: legacy SR-009 (target inside the backup refused, escaping entries refused); gap map "restore never harms the store".
- **SN-043** scale, time and memory: legacy SR-064 (audit linear in rows and files, hundreds of thousands of files), the production-shape memory test in the AGENTS.md suite description; the PERFORMANCE hat's charter (terabytes, millions of files); the brief's cost prompt.
- **SN-044** a readable record of what a run did, with progress: legacy SR-029 and SR-041 (each failure logged with cause and summary count), SR-075 (liveness kept observable during long blocking work); gap map "observability" and crossing B-04 "log, progress".
- **SN-045** backup-side outcome classes for a host: split from legacy SN-011; legacy SR-043 (distinct codes for complete, failed sets, configuration), SR-047/SR-048 (machine-readable inventory, prune outcomes), SR-054 (machine-readable findings with non-zero status), SR-086 (busy refusal); gap map "backup failure classes".
- **SN-046** reclaim forecast before removal: split from legacy SN-029, whose `why` and acceptance state it; legacy SR-047 (reclaim and re-home figures equal to the measured drop, read-only, one machine-readable document).
- **SN-047** repair of unambiguous store problems: split from legacy SN-030's "a repair mode fixes the ones that are unambiguously wrong"; legacy SR-049 and SR-054 (repair of storage form).
- **SN-048** compression-policy changes never harm saved states: split from legacy SN-030 (policy safety); legacy SR-061 (existing physical form unchanged when compression setting changes), SR-050 and SR-068 (restore by the stored bytes' real form).
- **SN-049** notification credentials never readable in plain form (Provision): legacy SR-042 (credentials refused in the portable configuration), the configuration helper that prompts for the mail account in README.md; the SECURITY hat's `listens_for` ("a stored credential readable in plain form"); gap map "credentials".
- **SN-050** a documented, versioned configuration contract for hosts (Provision): split from legacy SN-027 ("the JSON form is the documented, versioned contract and the shipped example configuration is itself valid"); legacy SR-042 (published schema and runtime validation agree, shipped example valid).
- **SN-051** see where backup space goes, media included (optional, C): the Owner's scope ruling on the media metric (an optional, configurable space-efficiency feature); legacy SN-016's optional media metric; README's optional media bitrate column.
- **SN-052** a file briefly in use is still backed up, and a stuck one never loses its earlier copy: legacy SR-067 (bounded retries, shared budget, no row for unstored content, prior row kept); the source-capture obligation of legacy SN-001.
- **SN-053** a partial restore salvages everything else and names what is missing: legacy SR-029 (restore every recoverable entry, log each unrestored entry and cause, report count and non-zero status); README's restore exit-code table (code 1, "everything salvageable was restored").
- **SN-054** third-party components shipped under terms that allow it: README's statement that every backup carries the hashing library and the container ships its tools; the LEGAL hat's charter and `listens_for`; the brief's licensing cost prompt; gap map hats table (LEGAL on SN-024 and SN-005).

## Considered and not written

- **CI proof of the container**: test tier (Owner ruling); see SN-028.
- **Container build and export tooling**: delivery, outside the spine (Owner ruling); no delivery crossing drawn.
- **A separate "index matches store" need apart from the check**: it is what SN-030's check observes and what SN-033 and SN-048 guarantee at restore; a fourth need would restate them.
