# Handoff 2026-10-18: FileBackup spine restructure, into the design tier

*Branch `DirectRebuild` (split by the Owner from `SpineRestructure` at
`9fa7394`; same history). Nothing is pushed. ai-template is untouched by this
work.*

## Where it stands

| Tier | File | Rows | State |
|---|---|---|---|
| Vision | `README.md` (`PROJECT-VISION`) | — | Owner's wording, including the compression-fallback qualifier |
| Stakeholders + needs | `docs/requirements/stakeholder-needs.toml` | 3 STK, 48 SN | Drafted; Owner reviewing; core judged good enough to split the branch |
| Frame | `external.toml`, `assumptions.toml` | 18 EXT, 24 B, 5 REL; 22 DA, 2 SUR | Drafted |
| Hats | `hats.toml` | 9 hats | Owner's roster (D4 plus LEGAL) |
| System requirements | `system-requirements.toml` | 123 SR | Drafted; reviewed and converged except the last edits (see open item 1) |
| **Design (CMP / IF / LLR)** | not written yet | — | **next: round 3** |
| Test cases | `docs/test/test-cases.csv` (legacy) | 234 | rebuilt after the design tier |

The legacy `low-level-requirements.csv`, `interfaces.csv` and
`test-cases.csv` still point at old ids. The old `trace.py` and `check.ps1`
fail on the new shape. That is expected until the tooling phase, and the
status banner says so.

## The method (it worked; keep it)

1. **Two independent derivations** from one brief, each written to its own
   folder under `docs/plans/spine-restructure/derive/rN-<who>/`. Neither sees
   the other.
2. **An alignment pass**, by a separate Opus agent: the only role that reads
   both sides, plus the legacy rows. It clusters every row by obligation and
   classifies orphans: (i) implementation-born, (ii) a need understated,
   (iii) accretion.
3. **A builder** (Opus, medium) composes the merged tier from the alignment
   and the coordinator's rulings.
4. **Two independent reviews** of the merged tier, written as
   `findings.json` plus `summary.md`. Neither reviewer reads the other's
   output or anything under `docs/plans/`.
5. **The coordinator confirms or refutes every finding** in a
   `rN-dispositions.md`. Owner-level calls go to the Owner one at a time, as
   multiple choice with a recommendation. A builder applies the dispositions.
6. **A bounded convergence check** by a fresh reviewer that sees no earlier
   verdicts, scoped to the changed rows, in convergence stance. Three full
   rounds at most. Fix what it finds, then commit and stop.

**Roles for round 3** (Owner, 2026-10-18):
- **Derivers:** Claude Opus (medium) and GPT-6 Astra (medium).
- **Reviewers:** Codex Sol at **high**, plus an independent Claude Opus
  (medium).
- **Builder and aligner:** Opus (medium).
- **Final call on everything:** the coordinator. The Owner rules on behaviour.

## Records (all under `docs/plans/spine-restructure/`)

| What | Where |
|---|---|
| The gap map, the Owner's D1–D4 rulings and how the work runs | `../spine-restructure-gap-map.md` |
| Legacy spine, verbatim, plus the TC-to-test links | `harvest/` (`harvest.py` regenerates it) |
| The strip: proposals, comparison, adjudication, removal ledger | `strip/` (`adjudication.md`, `final/`) |
| Round 1: needs and frame | `derive/r1-*`, `derive/r1-alignment.md` |
| Round 2: SRs | `derive/r2-*`. The Owner's seven SR rulings are in `derive/r2-dispositions.md`; the round 2b/2c calls (one outcome vocabulary) are in `derive/r2b-dispositions.md` and `derive/r2b-change-log.md` |
| Round 3 brief | `derive-brief-r3-design.md` |

## Owner rulings in force (beyond the vision and D1–D4)

- **Compression:** the extension fallback stays. Where measuring is off or
  unavailable, the file type decides.
- **The change-detection record** sits at the source root by default and can
  be configured to the backup side. It is the one permitted write into a
  source, together with the root folder's own modification time. A read-only
  source with no other location configured is refused up front.
- **Outcome vocabulary, every operation:** 0 complete; 1 part failed or
  content missing; 2 needs a person (bad request, configuration refused, or a
  precondition not met); 3 damaged record; 4 retry later (busy, or a host
  fault mid-work). A host alerts on 2 and retries on 4. Distinct values are
  always returned; the old opt-in switch is accepted and does nothing.
- **Missing change-detection state:** re-derive from the backup's record, then
  report it.
- **Retired store forms:** refused by name. SN-041 covers states written by
  supported versions.
- **Budgets:** a 2 TiB, 1M-file library; a 4-core, 8 GiB, 200 MiB/s
  solid-state reference host; up to 365 saved states. A check and a full
  restore take ≤8 h each. A run with ≤1 GiB changed takes ≤30 min. Total
  memory ≤4 GiB. Progress at least every 2 minutes of active execution time.
- **Configuration:** the native-Windows (CLIXML) form stays as the one form
  that may carry the mail login, protected by the host. Otherwise it obeys the
  JSON rules (version stated, unknown keys refused). Several sets in one
  configuration are normal.
- **Repair (SR-109):** copy-back only, never re-pointing an entry, and the
  copy's bytes must be hashed and verified before use.
- **Links in a source:**
  - A link to a folder outside the source and outside FileBackup's own
    locations is followed, and restored as ordinary folders.
  - A link inside the same source, or back to one of its own ancestors, is
    recorded and rebuilt at restore, re-pointed under the target.
  - A link into the backup, its saved states, the change-detection state or
    the logs is recorded and rebuilt to its original path.
  - A repeat link is just followed again.
  - An unreachable target is named, and the outcome is 1.
- **Removal (SN-029, SR-045):** older and newer states both survive. Only what
  no remaining state records is given up.
- **Mail stays.** SMTP login only where the server needs one.
- **The media metric stays**, as an optional feature. Third-party licence
  notices (the hashing library, 7-Zip, ffmpeg) are a need: SN-054.

## Open items, in order

1. **Review the last unreviewed SR edits**, as the first item of round 3's
   reviews: SR-121, SR-137, SR-150, SR-151 and SR-152 (links), SR-109
   (copy-back), SN-029 and SR-045 (removal scope), and SR-017 and SR-086
   (outcome splits).
2. **Owner approval of the need tier, then the SR tier.** This is a reviewed
   Status-change commit; only the Owner signs it. The design round may proceed
   on Drafted parents and re-align if the Owner changes any.
3. **Round 3, the design tier**, from `derive-brief-r3-design.md`.
4. **Round 4, the test cases.** Regenerate them from the new LLRs; do not edit
   the legacy rows. Use `harvest/` for the old cases' knowledge, keep old TC
   ids where a case maps one to one, and retire the 9 overlap clusters
   (gap map Appendix D). **Needs an ai-template ruling first:** the
   test-tagging form, since FileBackup files verify up to 32 TCs each and the
   kit rule says one tag per file.
5. **Then the code:** the design-gap list from round 3, plus the headers
   (`Component:`, `Implements:`, `Contract IF-NNN:`), then tooling or a kit
   resync. The Owner's template comparisons branch from an approved spine tag.

**Known build work so far:**
- links followed, recorded and rebuilt;
- the inside-source backup-location refusal;
- the read-only-source refusal;
- the outcome codes (distinct by default, busy as 4, preconditions as 2,
  across every operation);
- repair copy-back;
- the performance and progress budgets;
- licence notices;
- the empty-source remedy for an unfinished removal.

## Traps learned this session

- **Codex loads the repo's `AGENTS.md` automatically** when its working folder
  is inside FileBackup, so an Astra derivation is never fully blind to it.
  Say so in its notes, and weigh its rows accordingly. Run Codex as
  `codex exec -m gpt-6-astra -c 'model_reasoning_effort="medium"' -s workspace-write -C <out-dir> -o <out-dir>\last-message.md "<prompt>"`
  (`gpt-6.1-sol` for Sol), in the background. It writes only inside
  `-C`.
- **Subagents cannot use Write to create `summary.md`-style report files**;
  they fall back to the shell, which is fine. Long Python edits with quotes
  break bash heredocs: write the script to the scratchpad and run it.
- **Embedded newlines in CSV cells** broke one row per line; normalise them
  to spaces. Normalise curly quotes to ASCII when applying text.
- **A character-similarity diff between two rewrites is meaningless.** Compare
  verdicts, residual rule hits and retained numbers instead, then read the
  rows where they differ.
- **Fresh reviews always find new corners.** Cap the rounds, and end with a
  convergence check scoped to changed rows that sees no earlier verdicts.
- **One coordinator call was overruled by a reviewer** (busy as 2): SN-045
  needs busy distinct. Check every outcome-value call against SN-045 and
  SN-026.
