# Gemini high-risk requirements review

Date: 2026-11-05. Advisory feedback only; no requirement or approval changed.

The owner requested an independent high-risk-only SR review with permission to
critique the approved stakeholder needs and boundaries. After clarifying the
model name, the owner selected **Gemini 4 Argon via OpenCode Go**. Both passes
used `opencode-go/gemini-4-argon --variant low`; the configured variant maps to
`thinkingLevel: low`. The first review received no earlier reviewer reports.

## Outstanding high-risk decision

**External-link expansion and the scale envelope — SR-137, SR-064/112/113,
SR-023/155; related SN-001/043 and B-01/16.**

The proposed capture policy follows external folder links and restores their
contents as ordinary folders/files. Several links to the same data therefore
produce several logical copies during recovery, even though stored content is
deduplicated. For example, ten external links exposing the same 100 GiB folder
can require roughly 1,000 GiB of restored file data, plus allocation overhead.
Nested acyclic link structures can multiply paths further. SR-150's ancestor
rule prevents ordinary cycles; it does not eliminate this acyclic expansion.

The current million-file/2 TiB envelope does not explicitly say whether it
counts distinct physical source files or recorded logical paths and expanded
restore bytes. Under a physical-data interpretation, a small physical tree can
require work far beyond the proposed time and memory budgets. Under a logical
interpretation, the expanded tree may simply be outside the declared envelope.
The distinction is material to the user's expectation of what is protected and
how much capacity recovery needs.

**Author assessment:** retain this as a high-risk owner decision because it
changes capture scope, restore-space expectations and acceptance-test meaning.
It is not a demonstrated runtime defect or proof that the current budgets are
infeasible. SR-023 already requires an expanded-output capacity estimate, so
the reviewer’s smaller-replacement-drive example should cause a disclosed
capacity refusal, not be described as permission for unsafe writes. Nor does
any approved need promise recovery onto a drive matching physical source size.

Recommended resolution for review:

1. Define the per-state scale envelope in terms of **recorded logical paths and
   expanded logical bytes**, while specifying shared-pool and historical-record
   sizes separately in the benchmark fixture.
2. Decide whether external-link following is intentionally transitive and
   captures repeated targets at every path, or whether nested/repeated external
   targets should instead be recorded as links under a revised capture policy.
   Suppressing repeated targets is a behavior change, not a free cycle fix.
3. Make the selected expansion behavior and its restore-space consequences
   visible in the capture/recovery guidance and capacity estimate.

This may be resolved within the Drafted SR policy. If the owner wants a
different capture-scope promise, amend the relevant SN/boundary explicitly;
approved records are not silently reopened by an external review.

## Review accounting and dispositions

The first response proposed three high-risk candidates and incorrectly counted
93 SRs. A local table count established **32 + 31 + 36 + 22 = 121**; every
live SR was in the supplied files. The clarification pass supplied that ID
inventory and asked the reviewer to distinguish actual contract defects from
implementations that would already violate explicit preservation/path rules.
It was explicitly told not to retract a valid issue merely because challenged.

The reviewer corrected the count and confirmed that no table was inaccessible.
It withdrew the checkpoint-history-loss and restore-link-write candidates as
high-risk SR defects: safe designs can satisfy the existing requirements, and
the proposed harmful behavior would violate them. Only external-link expansion
remains an active high-risk finding. The original report below is preserved as
superseded evidence, not a list of three outstanding defects.

The clarification's inference that the restore target is free of hostile
concurrent mutation is not an explicit new accepted assumption. It is not
adopted here as a waiver of SN-042. The review did not establish a second
high-risk requirement contradiction on that basis or inspect implementation.

## Inputs, invocation and limits

Reviewed commit: `4582f71`. Inputs: 49 approved needs, 18 entities / 23 active
crossings / five relationships, 22 approved assumptions / two surrogates,
nine hats, and all 121 Drafted SRs. The three stakeholder identity records
remain Drafted. The current 2 GB available-memory / 100 MiB/s SSD correction
was included. Four upstream documents and four SR chunks were attached
separately, each below 50 KB with an end marker. No code, LLRs or tests were
provided; no implementation conformance or performance validation is claimed.

Invocation shape:

```text
opencode run <review-prompt> --model opencode-go/gemini-4-argon --variant low
  --pure --agent plan --dir <fresh-temporary-directory> --format json
  --file <eight-separate-input-files>
```

Tool permissions were denied through `OPENCODE_CONFIG_CONTENT`. The second
pass continued the same session with `--session`, the same model/variant and
the same isolated directory. Global OpenCode instructions may still influence
context. Both event streams finished with `reason: stop`. The clarification is
a challenged reassessment by the same reviewer, not a second independent vote.
Exact prompts, attachments, provider catalog metadata and raw JSONL streams
remain in ignored `.artifacts/gemini-spine-review/`.

Input SHA-256 fingerprints:

| Registry | SHA-256 |
|---|---|
| stakeholder-needs.toml | `b30222bc7f7d8a454df68a5f979afce3f8b77d7ebd97dbf4f5d8d6df5ff0deff` |
| external.toml | `7379dedd13b5a24dc93a54d8c9aa1c5fbbf045951205aedd1c7ffbd2b267f157` |
| assumptions.toml | `8cec1b0f3aff8e9f3f60ef7500444e9dcce44bc1e3d4976b9f60963ed32505f7` |
| hats.toml | `bcd28d68d302bb16c75de38b103471306ad6d052d75f632741351485b0ab8cc5` |
| system-requirements.toml | `2e1f2543f122af5d07a3dda9349ed42c25cfe40d0f313683caa7cc0f81bf9b6e` |

## Original response — superseded by clarification

Verbatim wording; line endings and trailing whitespace normalized. The incorrect
93-row count and the subsequently withdrawn candidates are preserved for audit.

### Input Verification

All eight attachments have been read in full with their terminal markers confirmed:
- `assumptions.toml` (`# END OF COMPLETE INPUT: assumptions`): **22** assumptions (`DA-01`–`DA-22`) and **2** surrogates (`SUR-01`–`SUR-02`).
- `external.toml` (`# END OF COMPLETE INPUT: external`): **18** entities (`EXT-01`–`EXT-18`), **23** boundary crossings (`B-01`–`B-23`), and **5** relationships (`REL-01`–`REL-05`).
- `hats.toml` (`# END OF COMPLETE INPUT: hats`): **9** expert hats.
- `stakeholder-needs.toml` (`# END OF COMPLETE INPUT: stakeholder-needs`): **49** Approved needs (`SN-001`–`SN-055`, excluding merged/retired IDs) and **3** Drafted stakeholder records (`STK-01`–`STK-03`).
- `sr-part-1.toml` through `sr-part-4.toml` (`# END OF COMPLETE INPUT: SR part 1..4 of 4`): **93** Drafted system requirements present across the four files (`25 + 22 + 28 + 18 = 93` `[requirement.SR-*]` blocks; **Count Discrepancy:** the prompt cites 121 Drafted SRs, so 28 SR IDs are either retired gaps in the numbering sequence or omitted from the four input files).

---

### High-Risk Findings

#### 1. Incremental checkpoints overwrite `latest` before run completion, destroying the prior state on mid-run failure or disappearance
- **Severity:** High (Loss of protected backup history / contradiction in core recovery contract)
- **IDs:** `SN-004`, `SN-013`, `SN-038`, `SR-005`, `SR-036`, `SR-082`, `B-02`
- **Classification:** SR defect (and potential upstream `SN-013` / `SN-004` policy conflict)
- **Document Facts & Conflicting Clauses:**
  - `SN-004` / `SR-005` require that when a run changes the backed-up state of a source, the system preserves the preceding recorded state as a dated saved state, labeled with its *completion-date*, alongside `latest`.
  - `SN-013` / `SR-082` state that a run may checkpoint individual files so that after interruption, *"The latest state may contain progress from the interrupted run and is not promised to be an atomic image of the entire source"* (`SN-013`) and *"published latest progress reconstructs the recorded captured files, possibly a mixture of earlier and newly captured versions"* (`SR-082`).
  - `SR-036` (`SN-038`) notes that when a populated source disappears mid-capture, *"A bounded run may already have published valid per-file progress when disappearance is detected; preserving earlier recoverable content is required, not rollback of every checkpoint."*
- **Causal Failure Scenario:**
  - *Scenario assumptions:* A user has a clean backup from Day 1 (`latest`, with no prior dated states). On Day 2, a corrupted script or ransomware begins overwriting files in the source, or a drive mount begins failing after a few files are modified, and the run is interrupted mid-way (or aborted by `SR-036`).
  - *Mechanism:* Because `SR-082` publishes incremental per-file progress directly into `latest` during the run, `latest` becomes a hybrid of Day 1 and Day 2 files before the run finishes. If the Day 1 state was not preserved as a dated saved state *before* `latest` was mutated, the clean Day 1 point-in-time state is permanently destroyed—violating `SN-004` and `SN-013` ("previously saved content" is preserved). Conversely, if the system snapshots Day 1 into a dated saved state at the *first* checkpointed file change, then every interrupted, crashed, or aborted run fabricates a permanent dated saved state, and a subsequent resumption (`SR-075`) that changes another file will snapshot the half-baked hybrid `latest` as yet another dated state.
- **Smallest Correction / Owner Decision:**
  - Separate *resumable checkpoint state* from the published `latest` state: keep `latest` pointing to the last completed run's state until the new run completes (or explicitly require preserving the pristine pre-run `latest` as a saved state before the first in-place mutation of `latest`, and never snapshotting an incomplete hybrid `latest` into a second dated state on resume).

---

#### 2. Following external links/junctions without cycle or alias bounds inside the external target causes infinite traversal or path explosion
- **Severity:** High (Unbounded hang / storage exhaustion in unattended backup)
- **IDs:** `SN-001`, `SN-036`, `SN-043`, `SR-074`, `SR-137`, `SR-150`, `B-01`
- **Classification:** SR defect
- **Document Facts & Conflicting Clauses:**
  - `SR-137` requires that when a source holds a link or junction to a folder outside that source and outside the system's own locations, *"the system shall capture what it leads to as part of the source, under the link's path. ... Two links to one folder are each followed: the content is stored once ... and only the record grows."*
  - `SR-150` prevents infinite loops only for links *"to a folder inside that same source, or to a folder that is one of the link's own ancestors in the walk"*.
- **Causal Failure Scenario:**
  - *Scenario assumptions:* A source tree contains a junction or symlink `S/ext` pointing to an external volume or share `E/root`. Inside `E/root`, there are two subdirectories `E/root/a` and `E/root/b` that contain symlinks pointing to each other's siblings or to a shared external subtree `E/shared` (non-ancestor cross-links or a two-node external cycle where neither target is inside the configured source `S`, nor is it a strict walk ancestor at first entry, or where `N` chained sibling links create $2^N$ distinct walk paths).
  - *Mechanism:* Because `SR-150` only records-without-following links pointing *inside that same source* or to *one of the link's own ancestors in the walk*, links inside the followed external tree pointing to *other* external folders (or DAG diamonds of symlinks on another volume/share) are treated as external links under `SR-137` and followed every time. A DAG of 30 nested sibling links doubles the manifest records at each level ($2^{30}$ record entries), exhausting the 2 GB memory bound (`SR-112`) and 30-minute window (`SR-113`), while restore (`SR-137` acceptance criteria) expands every followed external link into *"ordinary folders and files at that path under the target"*, multiplying physical disk usage on the restore target until capacity is exhausted.
- **Smallest Correction / Owner Decision:**
  - Amend `SR-137` / `SR-150` so that cycle and alias detection applies to the *entire resolved walk graph* (including already-visited external targets within the same source walk), or bound external link following to one hop / record nested links inside followed external trees as links.

---

#### 3. Restoring recorded in-tree symlinks/junctions while continuing per-file recovery creates a symlink-traversal write vulnerability
- **Severity:** High (Security / arbitrary overwrite outside target or into backup)
- **IDs:** `SN-036`, `SN-042`, `SR-029`, `SR-121`, `SR-152`, `B-16`
- **Classification:** SR defect
- **Document Facts & Conflicting Clauses:**
  - `SR-152` requires that when a state records a supported link (including in-source links and declared external-target links), *"the recovery route shall recreate it within the target ... and preventing restore writes through the link."*
  - `SR-121` requires that if a recorded restore entry would write outside the selected target or into the backup *"through its path or a link, then the recovery route shall leave that entry unwritten"*.
  - `SR-007` and `SR-031` mandate that recovery is executed by standalone PowerShell and bash scripts using stock local archive/file utilities (`EXT-11`, `DA-10`).
- **Causal Failure Scenario:**
  - *Scenario assumptions:* A backup state (either crafted, corrupted under `DA-11`, or legitimately captured when a folder was replaced by a symlink across checkpointed runs under `SR-082`) contains both a recorded directory symlink `dir_a -> /outside/path` (or `../..`) and a file entry `dir_a/payload.txt`, or an existing target directory contains pre-existing links.
  - *Mechanism:* In bash and PowerShell (`EXT-11`), standard file creation and extraction utilities (`7z`, `tar`, `cp`, redirection) resolve intermediate directory symlinks in the kernel path lookup. If `SR-152` recreates links before or during file restoration, or if a pre-existing target directory is used, standard script-level string/path resolution at admission (`SR-145`) or per-file copy cannot atomically prevent `O_NOFOLLOW` on every intermediate path component across Windows, Linux, and macOS shell tools. Recreating links before all regular files are written—or failing to enforce strict two-phase restoration (all directories and verified files first, links last, with no parent component of any file allowed to be a link)—allows `dir_a/payload.txt` to write through `dir_a` outside the target.
- **Smallest Correction / Owner Decision:**
  - Explicitly require in `SR-121` and `SR-152` that recovery scripts never recreate any link until all directories and regular files have been written and verified, and refuse (or skip) any entry whose resolved parent chain in the target contains a reparse point or symlink.

---

### Review Limitations
- **Scope & Count Discrepancy:** Review was strictly confined to the eight provided TOML inputs without repository or codebase inspection. Although the prompt refers to 121 Drafted SRs, the four complete `sr-part-*.toml` files contain 93 `[requirement.SR-*]` definitions; any requirements in the 28 unpopulated ID slots could not be evaluated.
- **Excluded Observations:** Lower-severity traceability gaps, minor wording ambiguities, and downstream design trade-offs with viable safe implementations have been omitted per instructions.

## Clarification response — final reviewer disposition

### Input Accounting Reconciliation

Verified against the supplied attachments: all **121** `[requirement.SR-*]` tables (`32 + 31 + 36 + 22 = 121`) are present in full across `sr-part-1.toml` through `sr-part-4.toml`, alongside all **49** Approved needs (`stakeholder-needs.toml`), **18** entities / **23** boundary crossings / **5** relationships (`external.toml`), **22** assumptions / **2** surrogates (`assumptions.toml`), and **9** hats (`hats.toml`). The earlier `93` figure was an arithmetic error on my part; no tables were missing or inaccessible.

---

### Re-Evaluation of High-Risk Candidates

#### Candidate 1: Incremental checkpoints vs. preserving the prior state
- **Disposition:** **RETRACTED as a High-Risk Finding.**
- **Re-evaluation:**
  - `SR-005` requires preserving the preceding recorded state when a run changes the backed-up state, and `SR-082` explicitly requires preserving previously recoverable in-window states upon interruption while permitting `latest` to hold checkpointed per-file progress.
  - A design that preserves the prior `latest` record as a saved state before publishing the first checkpointed change satisfies both `SR-005` and `SR-082` without losing any prior state.
  - Because `SR-005` requires distinct selectable identities (even within the same second or across clock rollback) and `SR-010` defines recovery over the selected recorded state (explicitly noting that an interrupted run may have checkpointed a mixture of versions under `SR-082`), retaining an interrupted run's partial state as an additional selectable saved state when a subsequent run resumes does not cause data loss, silent corruption, or an unselectable good state. How checkpoints are staged before publication is a downstream design choice with a valid safe implementation, not a requirement defect.

---

#### Candidate 2: External-folder link traversal, DAG path multiplication, and restore expansion
- **Disposition:** **RETAINED & RECLASSIFIED as a High-Risk Upstream Policy / Requirement Ambiguity (`SN-001`, `SN-043`, `SR-023`, `SR-064`, `SR-112`, `SR-113`, `SR-137`).**
- **Document Facts & Conflicting Clauses:**
  - `SR-137` requires that every link or junction to a folder outside the source (and outside system locations) be followed and captured under the link's path: *"Two links to one folder are each followed: the content is stored once, because identical content is (SN-002), and only the record grows... and a restore produces them as ordinary folders and files at that path under the target."*
  - `SR-150` suppresses following only for links *"to a folder inside that same source, or to a folder that is one of the link's own ancestors in the walk"*. (As noted, a cycle `A -> B -> A` is caught because `A` is a walk ancestor on re-entry; a non-cyclic DAG of external links is not.)
  - `SR-064`, `SR-112`, and `SR-113` bound check time (8h), restore time (8h), backup time (30m), and peak resident memory (2 GB) for *"a library of up to 2 TiB in up to one million files"*, without specifying whether "up to one million files" and "up to 2 TiB" count **distinct physical source files/bytes** or **logical traversed paths/expanded restore bytes**.
- **Causal Failure Scenario:**
  - *Scenario assumptions:* A user's source + external target hold well under 1,000,000 physical files and 2 TiB of physical data, but the external tree uses directory junctions/symlinks as organizational views (e.g., media or photo trees indexed by date, album, and tag via external folder links, or chained external folder links forming a DAG).
  - *Mechanism:*
    1. **Scale-envelope ambiguity (`SR-064`, `SR-112`, `SR-113`):** If the 1,000,000-file / 2 TiB scale envelope is measured over *physical* files/bytes on disk, `SR-137` forces the engine to traverse every alias path and the restore kit to materialize every alias path as a separate physical copy on the target (`B-16`). A physical library well inside the 2 TiB / 1M-file envelope can expand into tens of millions of manifest entries and many terabytes of duplicated restore writes, violating the 30-minute backup, 8-hour restore, and 2 GB RAM bounds.
    2. **Unbounded restore expansion vs. source size:** Because `SR-137` converts $K$ external links to the same 100 GiB external folder into $K \times 100\text{ GiB}$ of ordinary files on restore, a backup of a 100 GiB source that fits easily on both source and store volumes becomes unrestorable onto an identically sized replacement drive (`SR-023` / `SR-158`).
- **Smallest Correction / Owner Decision:**
  - **Owner Policy Decision:**
    1. Clarify in `SR-064`, `SR-112`, and `SR-113` that the 1,000,000-file and 2 TiB scale envelope is defined over **recorded logical paths and expanded logical bytes in the state record** (not deduplicated physical source inodes/bytes); **and**
    2. Decide in `SR-137` whether following external links is intentionally transitive across nested external links (with the resulting restore-space multiplication accepted and disclosed in `SR-023`/`SR-155`), or whether a second link to an already-captured external target (or nested links inside a followed external folder) should be recorded as a link rather than duplicated into independent file trees on restore.

---

#### Candidate 3: Symlink traversal during restore
- **Disposition:** **RETRACTED as a High-Risk SR Defect (residual concurrent-actor TOCTOU is an environmental boundary condition, not an SR contradiction).**
- **Re-evaluation:**
  - `SR-121` explicitly requires that if a recorded entry would write outside the target or into the backup through its path or a link, the recovery route shall leave it unwritten, and `SR-152` explicitly requires *"preventing restore writes through the link"* and verifies that *"No restore writes follow a recreated link."*
  - Any implementation that recreates links before regular files and writes through them would directly violate `SR-121` and `SR-152`; Conversely, a two-phase restore (validating existing target components, writing regular files first, and creating links last) satisfies both requirements using standard PowerShell and bash primitives.
  - The only scenario where script-level checks cannot prevent a link redirect is if an external concurrent process actively replaces a validated target directory with a symlink between the script's check and write (TOCTOU). Because `EXT-12` (`B-16`/`B-17`) and `DA-08` treat the restore target as an enabling filesystem rather than a concurrently hostile multi-user adversary, and `SN-042` ("whatever the backup's contents say") targets untrusted backup records and operator target-selection mistakes, no SR change is required unless the owner wishes to explicitly state in `DA-08` / `B-17` that the restore target directory is assumed free of concurrent external mutation during recovery.

---

### Summary of High-Risk Findings

Only **1** candidate (Candidate 2, reclassified as an upstream traversal-scope / scale-envelope definition decision on `SR-137` and `SR-064`/`SR-112`/`SR-113`) remains at the high-risk bar. Candidates 1 and 3 are retracted.
