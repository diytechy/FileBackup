# Project Status — Blackboard

Live coordination for the gated process (see [process.md](process.md)). Keep the
**Current State** header short and current; append the audit log below (newest
last) — it is the record, not required reading for every pass.

> **Retrofit, not greenfield.** FileBackup already works and ships a green Pester
> suite. We are layering the requirement-traced process *onto existing code*:
> back-fill SN/SR/LLR/TC from what the tool already does and from
> [AGENTS.md](../AGENTS.md), close traceability gaps, then keep new work gated.
> The spine's top layer is
> [requirements/stakeholder-needs.md](requirements/stakeholder-needs.md)
> (formerly `user-needs.md`/UN-###; ids kept their numbers, so audit entries
> below still resolve). Cross-project contracts live in
> [requirements/interfaces.csv](requirements/interfaces.csv) — IF-001 (the
> HomeHub OCI image contract) since 2026-08-12. [interfaces.md](interfaces.md)
> is the thin, human-readable pointer over that CSV (rewritten 2026-08-23, WP6).

> **Naming caution.** The kit's **gates** are `G1, G2, G3, G-Release, G-Final`.
> FileBackup's existing test **groups** are `G1…G9` (storage-mode suites in
> `tests/Run-All.ps1`) — a *different* namespace. Don't conflate them.

---

## Current State

- **THE CONTAINER IS BUILT AND ACCEPTANCE-TESTED (2026-08-28), so the HomeHub
  surface is no longer unverified.** Earlier in this session I recorded that it
  could not be built here and deferred it to CI. That was a WRONG DIAGNOSIS,
  twice over. First: "the podman VM has no outbound HTTPS". Then a correction to
  "not a blanket outage - docker.io pulls worked, so nuget is being filtered".
  The correction was the worse claim and its reasoning was faulty: an image pull
  runs in the podman SERVICE on the host side and never touches a container's
  network namespace, so a successful pull says nothing about whether a build
  step can reach the internet. Measured from inside a container: DNS resolves,
  but raw TCP 443 is blocked to EVERY host including 1.1.1.1 - podman containers
  here have no outbound network at all, and nuget was incidental.
- **WSL Ubuntu's docker has working container networking**, and pwsh 7.6.5.
  `Invoke-Container.ps1 -Action BuildAndTest -Runtime Docker` there: **EXIT 0**.
  Smoke test (compressed backup, restore kit, byte-exact restore), storage-form
  check (TC-102: clean verify exits 0 and mutates nothing, malformed row exits
  1, repair makes it clean), and the incremental pass (a restorable dated
  snapshot alongside a byte-exact latest-state restore) all passed. The image
  carries `bash/reconstruct.command`, and the in-container assertion over the
  full artifact list passed - which is the check that would have caught the
  missing Dockerfile COPY, and now proves the fix in a real image rather than
  by a source-text test.
- **Why the build needs HTTPS at all, since it was asked:** BUILD time only, and
  for two steps - `apt-get install` of p7zip/curl/unzip, and the pinned fetch of
  System.IO.Hashing 8.0.0. The RUNTIME needs no network. The fetch is version-
  pinned and SHA-256 verified before unpacking, deliberately: that assembly
  computes every hash the dedup and verification story rests on, so a verified
  artifact beats copying whatever the build host happens to hold. Recorded here
  because "just COPY a local DLL" will look obvious to someone later.
- **SECOND INDEPENDENT REVIEW (OpenAI gpt-5.6-terra, medium, via `codex exec`,
  adversarial, read-only) - this time against the IMPLEMENTATION, not the plan
  (2026-08-28).** 6 findings: 2 P0, 3 P1, 1 P2. Verdict: **"not safe to ship to
  HomeHub yet." ALL SIX WERE VALID** and all six are fixed.
- **T1 (P0) - a junction walked a restore INTO the backup.** `Test-PathIsInside`
  was purely lexical, so with `outside\link` a junction to the backup root,
  `-TargetRoot outside\link\restore` compared as OUTSIDE and the restore wrote
  into the backup. This was D-7/F-3, recorded as pre-existing and DEFERRED - the
  review was right that a deferral does not close a live SR-009 hole. Now
  resolves reparse points on the deepest existing ancestor (`Resolve-PathPhysically`,
  LLR-079), verified against a real junction. Closes D-7: the twins agree.
- **T2 (P0) - SR-074 as first written SILENTLY DELETED USER DATA.** The predicate
  keyed on the ENUMERATION root, not the volume root, so backing up an ordinary
  folder containing `$RECYCLE.BIN` dropped every file under it from the manifest
  with no error. My own tests encoded the defect by using `C:\src` as the
  supposed volume root. Now requires the root to BE a volume root; the tests use
  a real one made with `subst`, and assert the negative case as hard as the
  positive one. Negative control: both the predicate guard and the end-to-end
  enumeration test fail without the gate.
- **T3 (P1) - and it was worse than filed.** The MTA picker invoked a PowerShell
  scriptblock on a raw `System.Threading.Thread`, which has no Runspace. Not
  merely a failure to return: reproduced here, it throws an UNHANDLED
  `PSInvalidOperationException` that TERMINATES THE PROCESS. Replaced with a
  runspace created ApartmentState=STA; verified it returns `STA/marshalled`.
- **T4 (P1) - two tests that could not fail.** The "all seven artifacts" loop
  named six, omitting `System.IO.Hashing.dll`; the read-only test performed the
  attribute clear ITSELF instead of calling the restorer. Rewritten - and the
  negative control STILL passed, because with compression on both files took the
  7-Zip expand path, which never propagates the attribute. A `.jpg` (on
  NonCompressibleExtensions, so stored raw) was needed to reach `Copy-Item`.
- **T5 (P1) - and it exposed a further defect.** The BSD shim layer never shimmed
  `touch`, so "BSD" restores used GNU `touch -d` and the fallback never ran.
  Adding the shim made the test FAIL: the conservative "refuse a foreign offset"
  design meant a BSD host lost the timestamp for any store written in a different
  timezone - ordinary, not exotic. Now converts every offset exactly through
  POSIX `TZ`, whose sign is the inverse of ISO-8601 ('-06:00' -> 'UTC+6:00').
- **T6 (P2)** - `FILEBACKUP_PICKER` was expanded unquoted; a picker path with
  spaces executed its first fragment. Quoted.
- **NOTHING WAS DECLINED THIS TIME.** The first review's one wrong finding (that
  BSD rejects `--`) has no counterpart here.
- **THE PATTERN WORTH KEEPING:** five of the six findings, plus both defects the
  permutation work found, were about tests that passed for the wrong reason or
  paths never exercised. Every fix in this batch now carries a NEGATIVE CONTROL -
  revert the production change, confirm the test fails - and three tests needed
  two or three attempts before they could fail at all.
- **SR-074 (2026-08-28, human-requested during WP13): the volume-root
  pseudo-folders are no longer treated as data.** Raised by the human asking a
  plain question - "is `System Volume Information` ignored?" - and the answer was
  no, with three consequences, all of them false verdicts about a folder that is
  never the user's data. **(1)** `System Volume Information` denies read access
  even to an administrator, and SR-057 reports an unreadable directory by marking
  the set FAILED - so a `SourcePath` of a volume root (`D:\`) **could never
  report success, on any run**, and a scheduled job alerted every time. **(2)**
  `$RECYCLE.BIN` is the opposite: READABLE by its owner, so deleted files were
  quietly being backed up. **(3)** On the restore side the same folder counted
  as a pool read failure and MISCLASSIFIED a genuine content loss as
  StorageUnreadable / exit 4 - "fix this host and retry" - instead of
  ContentMissing / exit 1, so an SR-040 wrapper would retry forever instead of
  reporting data loss. All three existed only because SR-057 added `-Force`;
  before that the folders were invisible.
- **CORRECTION to the claim first written here and in commit e8e38de's
  successor:** I stated the restore returned exit 4 "against a wholly intact
  store". That is WRONG and the test proved it. `Find-DataFileByHash` returns as
  soon as it FINDS the bytes and consults its collected host issues only when it
  does not - so on an intact store the enumeration error is discarded and the
  restore exits 0 either way. The defect is narrower and is about
  CLASSIFICATION, not success. Two versions of TC-180 passed against a
  deliberately broken restorer before a negative control caught the test itself
  being wrong; the third version asserts exit 1 vs exit 4 and fails correctly
  without the fix.
- Fixed with ONE predicate used by both sides (`Test-IsVolumeRootPseudoPath` in
  Common, so the standalone restorer can reach it too) plus a bash twin. Both the
  enumerated FILES and the enumeration ERRORS are filtered in each place -
  filtering only one half leaves half the defect. **Root-level only**, the same
  B6 rule the infrastructure names follow: a folder of either name nested inside
  the tree is the user's data and is backed up and restored normally.
- Registry: SR-057 amended, **SR-074** + **LLR-078** + **TC-175..178** added
  (phase `portable-v1`, Draft). README's "Hidden and dot-prefixed files" section
  said `$RECYCLE.BIN` WAS backed up; corrected, with the root-level-only rule
  spelled out.
- **HEADLINE - WP13 IS IMPLEMENTED, NOT YET RATIFIED (2026-08-28). Restore kit
  revision 10.** Four human questions about the restore entry points (`.cmd` vs
  `.bat`, a folder picker, the same from bash, a macOS `.command`) turned up a
  defect underneath the fourth: **`reconstruct.sh` returned FALSE VERDICTS on any
  BSD userland.** The three tool gates (bash 4+, gawk, xxhsum) make the floor
  loud, so a stock Mac stops correctly - but a user who FOLLOWS that advice
  (`brew install bash gawk xxhash`) clears them and meets seven GNU-specific
  assumptions behind them, each wrapped in a `2>/dev/null` fallback written for
  "the tool is absent" rather than "the tool differs here". So the failure was
  not loud, it was WRONG: `stat -c` made an intact manifest fail its witness as
  `expected 41231, found -1` -> **exit 3, "the index is damaged"** (or exit 4 on
  an unwitnessed store); `find -printf` silently emptied the snapshot pool so a
  deduplicated row reported "your bytes are gone"; `mktemp -d` failed every
  compressed row and blamed 7-Zip; `touch -d` silently cost SR-066; and `canon()`
  returned its raw input, losing the SR-009 guard without saying so. Affects
  macOS-with-Homebrew and FreeBSD/TrueNAS - a NAS platform `reconstruct.sh`'s own
  header claims as an audience.
- **The independent review found a P0 IN THE PLAN, and it was right.** (OpenAI
  gpt-5.6-terra, medium, via `codex exec`, adversarial, read-only: 9 findings,
  2 P0, verdict "not safe to implement as written".) **T2:** the first `canon()`
  fix reduced `..` textually before resolving symlinks, so with
  `/outside/link -> /backup` the target `/outside/link/../backup/victim` was
  judged OUTSIDE while the kernel resolves it INSIDE - **the guard would have
  walked a restore into the backup root it exists to protect.** Redesigned to
  REFUSE a `..` component rather than reduce it. **T4:** the `stat` probe could
  misidentify GNU as BSD if a file named `%z` sat in the cwd; it now probes a
  known regular file and requires numeric output. **T6/T7** replaced a batch
  `pause` (which hangs a console-attached no-arg caller) with a hold inside the
  restorer, and closed a PRE-EXISTING hang. **T8** caught five registry rows the
  plan had missed - and itself missed `LLR-040`.
- **Not everything was accepted.** T1/T5 claimed BSD rejects `--`; it does not
  (POSIX Utility Syntax Guideline 10, honoured via `getopt(3)`), and acting on it
  would have REGRESSED a deliberate safety property this file's own live-items
  list praises. Declined with reasons. T3/T7 describe real problems that PRE-DATE
  the WP; attribution corrected, recommendations still taken (D-6, D-7).
- **The driver's own sweep found three the review missed:** `mktemp -d` (incl. an
  UNCHECKED result at `:204` that writes the 7-Zip self-test probe to the
  filesystem **root** - latent on every platform), `touch -d`, `date --iso-8601`.
- **D-6, a deliberate behaviour change, flagged not buried:** a restore started
  with no `-TargetRoot`, no `-NonInteractive` and no redirected stdin - a
  scheduled task set to run whether or not a user is logged on - reached
  `Read-Host` and **waited forever**, violating SR-016/SN-011 in shipped code. It
  now exits 2 with usage. A job that hangs today will fail fast tomorrow.
- **F-1 (pre-existing): the kit revision marker never reached 9.**
  `Get-BackupKitRevision` reads one source of truth and it said **8**, while
  `reconstruct.sh` said **6** and this file claimed 9 - so every WP12 store
  reports the wrong kit, and nothing pinned it (`-BeGreaterOrEqual 2`).
  Corrected FORWARD to 10, not back-dated: the marker records what a BUNDLED kit
  does, and a deployed copy cannot be rewritten. Now pinned by TC-173.
- **F-2 (pre-existing, NOT fixed here - D-5): `SN-031` is assigned to two
  different needs** (restore fidelity, and self-healing). Any `SN-031` reference
  is therefore ambiguous, and `trace.py` does not check SN id uniqueness.
  Renumbering a top-layer id deserves its own reviewable commit.
- **AWAITING HUMAN RULING before release: D-2.** `RECONSTRUCT.bat` is named in
  **IF-001**, a ratified cross-project contract. The rename is implemented (the
  human asked for it), but amending a counterparty's contract needs HomeHub's
  acknowledgement. This blocks release, not implementation. D-7 (the twins
  already disagree about symlinks: bash resolves them via `realpath`, PowerShell
  never has via `GetFullPath`) is recorded as F-3 and deferred.
- **macOS acceptance is NOT claimed.** No Mac on this host. The BSD branches are
  exercised by shimming the GNU tool off `PATH`, which proves OUR branch
  selection, not Apple's `stat`. TC-169/TC-170 are Manual/Release for that
  reason, and the open BSD `mktemp` default-template question is settled there
  (the explicit template is correct either way).
- **Plan:** [../plans/wp13-portable-launchers-plan.md](../plans/wp13-portable-launchers-plan.md)
  (revision 2 carries the full review dispositions in section 9).
- **HEADLINE - WP12 IS COMPLETE (2026-08-27). Restore kit revision 9.** Stored
  objects are named `<hash22>_<len><ext>` in base-57 (the alphanumerics less
  `0 O I l 1`), carrying the COMPLETE 128-bit hash with an UNPADDED length -
  the same 30 characters as before, 26 more bits of hash, and none of the
  hostile name shapes the old 85-glyph alphabet could produce. Raised by the
  human from a live pool; ratified, independently reviewed, repaired TWICE, and
  green. Witness format version 1 -> 2; SR-061 refuses a pre-WP12 store.
- **Evidence (real output, 2026-08-27):** `check.ps1 -Tier Full -Gate G3` **all
  steps passed** - lint clean; trace **0 orphans / 0 integrity / 0
  status-findings**, 1 phase-deferred (SR-033, by design); unit **444/444**;
  integration **274 PASS / 0 FAIL / 2 SKIP**. Ubuntu WSL: **bats 79/79**,
  `shellcheck` clean. Ratchet:
  `core,bash-v1,container-v1,kitbump-v6,ca-v1,fidelity-v1,robust-v1,form-v1,name-v1`.
- **A LIVE PRODUCTION BUG was found and fixed along the way (T6):** an
  extensionless source file (`README`, `LICENSE`, `Makefile`) in a Plain-mode
  set **failed the entire backup set** - `-Extension` was
  `[Parameter(Mandatory)]`, which rejects `''`. Invisible in Compress mode,
  which is why no suite caught it. Now pinned by TC-148 in both modes.
- **The name grammar had NO owning requirement** before this - it was stated
  only in TC-004's `Expected`. SR-069 and SR-070 now own it.
- **THE PRUNE EXIT-4 SIGHTINGS ARE OPEN, AND THE CAUSE IS UNKNOWN.** Two on
  2026-08-27 (`G9.6 Prune_oldest_succeeds`; `Coverage.Tests.ps1:2922`), at a
  rate of **2 failures in 3 full batteries** - frequent, not a rare flake.
  ESTABLISHED: prune's exit 4 has exactly two sources in the engine, both
  `host-io` catch blocks, while every policy refusal is code 2 - so this is
  always a caught filesystem exception, never the product refusing, and
  correctness is not implicated. NOT established: the cause. Four hypotheses
  tested and all negative (standalone 0/12; under concurrent WSL load 0/14;
  whole-file 0/3; "rare flake" contradicted). It appears only inside a full
  battery. An earlier entry called it a harness issue with a lingering-handle
  signature - that was inferred from a bare exit code and is **corrected**; see
  the 2026-08-27 correction entry. Mitigation shipped: all 11 prune assertions
  that tested only an exit code now carry the refusal payload, so the next
  sighting names its own filesystem error.
- **THREE LIVE ITEMS, all pre-existing or environmental, none introduced by WP12:** (1) no
  collision rail on the content-addressed write path - `Invoke-BackupFileGroup`
  writes to the derived name without proving an object already there is the same
  content (an SR-029 verify-or-fail conversation, not a naming one); (2) no `--`
  end-of-options guard on the PowerShell 7-Zip calls (`Common.psm1:444`,
  `:478`), where the bash twin guards every external call - base-57 removes the
  reachability of a leading `-` or `@`, not the hole; (3) the prune transient
  above.
- **HEADLINE - WP11 IS COMPLETE (2026-08-26), and its live-items list was EMPTY.**
  Two parts. **Part A closed the Full-tier intermittent by finding it**, and it
  was the TEST HARNESS, not the product: `Reset-TestEnvironment` wiped the
  volumes with `-ErrorAction SilentlyContinue` and never verified the result, so
  a transiently failed delete left a `Temp` folder behind and SR-017's
  stale-staging guard then refused every backup in the NEXT scenario -
  surfacing, because `Invoke-Backup` also ignored `$LASTEXITCODE`, as an opaque
  `Condition returned false` in G9 prune several steps downstream. Both halves
  are fixed and the instrumentation caught it on its first run. **Part B is
  S1's load-bearing half** (SR-068, kit revision **8**): both restorers derive a
  stored object's form from the BYTES for a row resolved through its own
  `DataPath`, so `Compressed` is consulted for no correctness decision. That
  narrowed SR-040's host class - a row's own object is exit 4 only when it is
  archive-shaped and will not open - which was put to the human and **ratified**.
  Two deviations from S1 as filed are recorded rather than assumed: the column
  and the audit classes are both RETAINED, so S1's predicted ~200-line saving is
  **not** realised and the payoff is the correctness one.
- **Evidence (real output, 2026-08-26):** `check.ps1 -Tier Full -Gate G3` **all
  steps passed** - lint clean; trace **0 orphans / 0 integrity / 0
  status-findings**, 1 phase-deferred (SR-033, by design); unit **437/437**;
  integration **240 PASS / 0 FAIL / 2 SKIP**. Ubuntu WSL: **bats 79/79**,
  `shellcheck` clean. Ratchet:
  `core,bash-v1,container-v1,kitbump-v6,ca-v1,fidelity-v1,robust-v1,form-v1`.
- **Nothing is awaiting a decision.** SR-033 (`bash-v2`) is phase-deferred by
  design; **G-Release** and **G-Final** are the remaining gates. The optional
  S1 follow-up (reclassify the form findings as informational, stop repairing a
  cosmetic field) is recorded and unstarted.
- **HEADLINE - WP10 IS COMPLETE (2026-08-26, Windows host + Ubuntu WSL for the
  POSIX half). Restore kit revision 7.** One session's human rulings on the four
  open items, shipped together because they shared one kit revision:
  **(1) legacy path-addressed READ support WITHDRAWN** (SR-061 amended): both
  restorers refuse a store marked `StoredAsHashSize='Original'` or carrying a
  path-separator `DataPath`, exit 2, nothing written. This closes review MIN-2
  by dropping the promise rather than building a fixture for it, on the human's
  instruction that no support, verification or testing remain around older
  stores. **(2) The S3 collapse taken**: `Get-ReHomedDataPathName` deleted, the
  re-homed destination name is now just the source `DataPath`. **(3) nit-4
  taken**: `Compress-FileWithSevenZip` clears its destination before `7z a`.
  **(4) SR-066**: each restored file carries its OWN `LastWriteTimeStr`, closing
  the dedup timestamp leak; the FILE-attribute half stays out of contract and
  documented. **(5) SR-065**: `DIRECTORIES.csv`, an advisory unwitnessed
  sidecar, records and restores empty directories plus the four folder attribute
  bits `SetFileAttributes` can apply (`Hidden`/`System`/`ReadOnly`/
  `NotContentIndexed`); `reconstruct.sh` creates the directories and reports the
  attributes as inapplicable on POSIX rather than dropping them silently.
- **Evidence (real output, this session).** `check.ps1 -Tier Full -Gate G3`
  **all steps passed**: PSScriptAnalyzer clean, trace **0 orphans / 0 integrity /
  0 status-findings**, doc navigability and generated-doc freshness clean, Pester
  unit **424/424**, integration **240 PASS / 0 FAIL / 2 SKIP**. Ubuntu WSL:
  **bats 76/76** (up from 68 - `tests/bash/restore_fidelity.bats` adds the eight
  POSIX twins) and `shellcheck bash/reconstruct.sh` clean. The ratchet is armed
  to `core,bash-v1,container-v1,kitbump-v6,ca-v1,fidelity-v1` in both
  `check.ps1` and CI, with SR-065/066 Verified and TC-136..139 Pass in the same
  commit. SR-033 (`bash-v2`) remains the one phase-deferred row. **One honest
  caveat:** across three Full runs the Deny-ACE SR-057 case failed once (see the
  intermittent item below); it is pre-existing, not WP10's, and re-ran clean
  (unit **425/425** isolated, integration **240 PASS / 0 FAIL / 2 SKIP**
  isolated). An earlier Full run also showed four G9 prune failures that were
  purely my own machine contention - two Pester suites running against the same
  host - and did not reproduce on a clean sweep.
- **Registries.** New: SN-031, SR-065, SR-066 (phase `fidelity-v1`), LLR-065,
  LLR-066, TC-136..TC-139. Amended: SR-061, LLR-060, LLR-045, LLR-004, TC-124.
  Docs: README's records table (now ten artifacts) and its "What is **not**
  recorded" section rewritten - the mtime and directory bullets moved from
  *never* to *recorded*, with the remaining gaps stated exactly; AGENTS.md sec.3
  carries the new invariant and the withdrawn legacy claim.
- **Where things stand (2026-08-25).** The retrofit and the WP1→WP9 queue are
  COMPLETE. WP1→WP8 were implemented, independently reviewed, human-ratified and
  proven on CI; the kit-bump WP (D-2/D-3/D-4, restore-kit revision **6**) was
  RATIFIED 2026-08-25 together with a standing directive: **no further
  ratification pauses** — queued work ships as a full solution before HomeHub
  builds, with independent review retained as a quality bar. Coverage 78.1%
  accepted (human 2026-06-05). One phase-deferred row remains: SR-033
  (`bash-v2`), by design. The narrative history is the **audit log below**; closed
  work-item rows live in **[resolved-items.md](resolved-items.md)**.
- **HEADLINE — WP9 IS COMPLETE (2026-08-25, Windows host). D-1 and D-5 are fixed
  by deleting their hazard class, not by guarding it: ALL storage is
  content-addressed.** The 2026-08-24 HomeHub bench review
  ([defect-review-2026-08-24-mirror-dedup.md](defect-review-2026-08-24-mirror-dedup.md))
  found five real defects, all five confirmed with reproductions; all five are
  now closed. What WP9 shipped, over nine committed steps on `New_Fix_Batch`:
  Mirror/`PreserveFolderTree` **deleted** (SR-058) so hash naming is
  unconditional and a stored object can never be overwritten in place; owner
  election + an intra-run memo (SR-060) closing D-5; `Save-SupersededData`
  retargeted to ask the **final manifest** whether anything still claims an
  object (SR-059/SR-051), which also fixed two red-first-proven D-1-family holes
  the source-based test could not see (a FROZEN row's claim, and a row whose
  replacement copy failed); the storage-layout migration **deleted whole** with a
  loud legacy-store refusal (SR-061); the generated browse view (SR-062);
  configuration contract **v2** (SR-063); a linear unreferenced-data audit
  (SR-064); and the folded fixes — canonical manifest bytes, F8, the
  directory-destination guard, reserved device names.
- **Kit revision stays at 6 (driver decision, WP9 step 9, open to veto).** WP9
  changed **no kit byte**: content addressing is entirely engine-side, and both
  restorers already resolve a row by its `DataPath` or by `(hash, length)`
  without caring how the name was chosen. A kit comment still describes the
  legacy path-addressed shape, and that is correct — the kit must go on restoring
  such stores (SR-061 refuses only *writing* to one), and bumping to revision 7
  for a comment would invalidate every existing snapshot's kit against TC-105 and
  `-RefreshKits` for zero behavioural gain.
- **Evidence (real output, this session — the full paste is in the WP9 G3 audit
  entry below):** `check.ps1 -Tier Full -Gate G3` **all steps passed** on the
  2-mode matrix (Plain/Compress) — unit **405/405**, integration **236 PASS / 0
  FAIL / 2 SKIP**, bats (WSL Fedora) **68/68**, `shellcheck` clean, lint clean;
  trace **0 orphans / 0 integrity / 0 status-findings** with the ratchet advanced
  to `core,bash-v1,container-v1,kitbump-v6,ca-v1` (phase-deferred = 1: SR-033).
  Every `ca-v1` registry row is now Verified/Pass — nothing can be quietly
  dropped, because the ratchet fails the gate the moment one is not.
- **Registry reconciliation landed with step 9.** The mode axis is gone from
  every Permutations/Parameters cell (60 rows: `mode=4-modes` and
  `mode=set{Mirror,…}` collapse to `compress=set{on,off}`, the tree axis having
  ceased to exist). SR-012 RETIRED (its whole subject — layout selection and
  migration — is now stated by SR-058 + SR-061); SR-013 amended to
  "`StoredAsHashSize` is the constant `'Hash'`"; **SR-051 retargeted rather than
  retired** — its never-delete-a-still-referenced-file half is real, implemented
  and tested, it simply moved from the migration site to the two that still
  delete (eviction and preservation). LLR-012/LLR-013 deleted (their CodeSymbol
  is gone), LLR-051 retargeted, TC-023/TC-095 retired with the tests they named,
  TC-097/TC-100 re-pointed, and the vacuous `StorageForm` capacity-estimate `It`
  deleted rather than left inert.
- **WP9 INDEPENDENT REVIEW DONE (Claude subagent, 2026-08-25): REQUEST-CHANGES,
  and it was right.** It reproduced a **data-loss** defect the driver's own
  review missed — a `ViewPath` that CONTAINS a storage root, or IS `SourcePath`,
  passed the one-directional containment rail and was then wiped, destroying the
  store or the user's source on a run that reported success — plus a vacuous
  TC-119 (the intra-run memo could be deleted outright with all 405 tests still
  green). Both are FIXED and re-verified by re-breaking them; two MIN findings
  and five nits are fixed or recorded. Full entry at the end of the log.
- **Next actions, in order:** (1) the OpenAI adversarial pass via `codex exec`
  (it found real defects on the kit-bump WP, and the Claude pass has now proven
  its worth here too); (2) G3 → G-Release (human attestation); (3) IF-001
  Experimental → Stable jointly with HomeHub — D-2 is fixed and D-1 is now
  cleared, and IF-001's contract text was updated at step 9 for config v2,
  unconditional content addressing, and the ruling that the browse view is
  **not** a container action word (a container's separate `/backup` bind can
  never satisfy the same-volume rule).
- **Active gate:** G3.

## Open items

Only items still needing input or work. Everything resolved/ratified moved to
[resolved-items.md](resolved-items.md) (2026-08-24, at the human's direction).
**Interactions to keep in view:** the D-1 design ruling determines D-5 for
free and shapes the test-battery import; D-2 + D-3 (+ the two parked kit
nits) share one kit-revision bump; the no-backward-compat ruling frees every
option from migration cost.

### Live items — EMPTY

Every row opened by the WP9 independent review (2026-08-25), the README
metadata sweep (2026-08-25) and WP10/WP11's own verification runs (2026-08-26)
is closed and has been moved to [resolved-items.md](resolved-items.md) with its
disposition. D-2/D-3/D-4 moved there 2026-08-25; D-1/D-5, the test-battery
import and the step-4 review's n6 nit moved there when WP9 landed.

What is genuinely outstanding is **not** an open item in this sense: SR-033
(`bash-v2`) is phase-deferred by design, and G-Release / G-Final are gates
awaiting their own evidence. The simplification candidates below are a record
of measured options, not a queue.

> **WP11** (2026-08-26) planned and delivered the last two live items:
> [plans/wp11-diagnosability-and-form-derivation-plan.md](plans/wp11-diagnosability-and-form-derivation-plan.md)
> â€” Part A diagnosed the Full-tier intermittent (it was the harness), Part B is
> S1's load-bearing half (SR-068, kit revision 8).

### Simplification candidates (2026-08-25 architecture read, human-prompted)

The human asked whether the codebase carries band-aid patchwork that WP9 does
not already scope. It does, and it is **one family, not scattered**: *derived
facts about content, persisted where they can drift from the content*. D-1 is
that shape (`DataPath` as a claim about bytes); so is the form-claim apparatus
(`Compressed` as a claim about bytes); so is the overloaded blank-`DataPath`
sentinel. WP9 kills the first structurally.

| Candidate | What it removes | State |
|---|---|---|
| **S1 — retire the `Compressed` claim; derive form from bytes** | 4 of `Get-StorageFormFinding`'s 7 classes (`FlagOverRaw`, `FlagOverArchive`, `NameLies`, `BlankRowFormDisagreement`) exist only to police a claim the bytes already answer. SR-050 already made BOTH restorers prefer the located file's PROVEN form — but only for hash-recovered rows; a row resolved through its own `DataPath` is still decided by the column (`Reconstruct.ps1:893`, `reconstruct.sh:823`). Extend proven-form there and the claim has no consumer left. The complete byte-derived rule is the one `Find-DataFileByHash` already implements, and D-2's verify-after-write makes it self-checking. Cost: a ~10-line 7z-magic sniffer in **Common** (the kit does not bundle Engine, so `Get-StoredFileForm` is unreachable there) plus a bash twin. Payoff ≈ 200 lines of audit/repair logic and one whole class of "the index lies about the bytes". The column stays in the 9-column contract as advisory — no parser or kit break. | **LOAD-BEARING HALF DONE 2026-08-26 (WP11 Part B, SR-068, kit revision 8).** Both restorers now derive a DataPath-resolved row's form from the bytes, so the column is consulted for NO correctness decision - the last path by which a wrong column could produce a wrong restore is closed. **Two deviations from S1 as filed, stated and deliberate.** (1) The column is RETAINED: removing it is an 8-column schema break for every existing store, both parsers and eight bats fixtures, for a field that is now harmless; it still feeds the restore capacity ESTIMATE, which is approximate by design. (2) The four audit classes are **NOT deleted** - S1 assumed they die once nothing reads the column, but they become non-fatal, which is not the same as worthless: a manifest disagreeing with its bytes is still evidence that something wrote a wrong index, and deleting a detector to save lines is the wrong trade in a data-safety tool. So the ~200-line saving S1 predicted is NOT realised and the real payoff is the correctness one. **Remaining, if wanted:** reclassify those findings as informational and make form-only repair explain rather than write - a separate, reversible decision, not started. |
| **S2 — retire storage-layout migration entirely** | `Sync-BackupStorageLayout` (210 lines) + `Get-MigrationCapacityDemand` (50) + the step-5.5 migration preflight + the SR-051 refcount apparatus, which existed only to make a migration safe. Also collapses two overlapping orphan scans into one. | **HUMAN RULED 2026-08-25: GO — and FOLDED INTO WP9** ("Retroactive space reclamation is not necessary... Similarly, retroactive decompression is also not necessary"). It does NOT depend on S1: a mixed-form store is already normal today because compression is per-file (SR-004) and every row's `Compressed` describes its own object. `CompressEnabled` now governs only content written after the flip. |
| **S3 — re-homing becomes a same-name copy** | Under content addressing a data file's name is derived from its content, so a re-homed file's source and destination names are ALWAYS identical: `Get-ReHomedDataPathName` (30 lines) collapses to nothing and "does the destination already hold this content" becomes a filename test instead of an index lookup. The same lever may thin `Get-BackupContentIndex` + `Optimize-ChangeFolders` (168 lines between them), since identical content now shares a filename in every folder. | **COLLAPSED 2026-08-26**, once the legacy-store decision made it free. `Get-ReHomedDataPathName` is deleted whole and the caller now uses `$sourceRow.DataPath` - the destination name is always the source name under content addressing. The `Get-BackupContentIndex`/`Optimize-ChangeFolders` half (168 lines) is still UNMEASURED and remains a candidate, not a promise. |

**Deferred by the same ruling:** retroactive re-packing, if ever wanted, becomes
a **standalone offline script** (human's suggestion, 2026-08-25) — re-forms a
store's objects to a new compression policy outside the engine, never on the
backup path. Not scheduled, not built by WP9; recorded so the capability is not
silently lost.

**Deliberately NOT reopened:** the overloaded blank-`DataPath` sentinel (means
"bytes lost", "deduped into another folder", and "heal pending" at once). It is
the sharpest remaining smell, and the 2026-08-24 two-registry analysis already
ruled it: fixing it properly means a PERSISTED content registry, which converts
a currently-cannot-be-stale derived view into stored state that can lie — D-1's
exact bug class. Deferred for a reason, not from inertia.

**Judged EARNED, not patchwork** (same read): the twin restorers (SN-022/SN-026
make interchangeability a product requirement), the SR-038 witness sidecar, the
capacity preflights, and the frozen-row handling for unportable/unreadable
paths. Each is one mechanism answering one real, traced failure.

### Parked / minor (no input needed now)

| Item | What | Disposition |
|---|---|---|
| manifest row order | No-op runs can reorder manifest ROWS with identical content; G7 doesn't catch ordering. | **DONE — WP9 step 8.** Canonical manifest writes (ordinal `RelativePath` order, every text column string-ified), pinned by a byte-identical-no-op-run test. Engine-side, so no kit bytes changed. |
| F8 kit-less snapshot window | Sub-second crash window between the `Temp`→`Snapshot_*` rename and the kit copy leaves a valid snapshot without a kit. Recoverable via `-RefreshKits`. | **DONE — WP9 step 8.** The kit is copied into staging BEFORE the publish rename, so a `Snapshot_*` folder structurally cannot exist kit-less; pinned by a mocked-rename crash test. |
| DataPath-keyed CI maps | The DataPath-keyed membership hashtables are literal case-insensitive maps; failure modes are warning-suppression, not byte loss (noted at the `31a55f2` review). | **DONE — WP9 step 8** (`New-RelativePathMap` sweep across the functions the WP opened). |
| Windows reserved device names | `CON`, `NUL.txt` etc. pass the SR-055 portable-name guard; worst case a loud copy failure on Windows restore. | **DONE — WP9 step 8b.** SR-055/LLR-055 amended, per-component reserved-name predicate, TC-117 Pass (windows + posix arms). The work also EXPOSED a latent classifier bug: `Test-PortableRelativePath` never actually split components — invisible while every predicate was character- or suffix-scoped. |
| `-RepairFromPruned` | Materializing bytes back into a pool that lost them (diagnosis half shipped in WP5). | **RETIRED 2026-08-26** (human) - content addressing dissolved the premise. See [resolved-items.md](resolved-items.md). |
| O(N²) unreferenced-file scan | `Test-BackupManifest` re-pipes `$db` per on-disk file (Engine.psm1:610-614); runs on every backup via Sync step 6. Plausibly hangs a 500k-file library. | **FOLDED into WP9** step 8 as **SR-064 / LLR-062 / TC-132** (one hashtable; pattern at :761/:772). |

## Scope (restated from the brief)

- **Goal:** Periodic, content-aware file backup with change tracking and
  self-contained reconstruction (xxHash128 dedup, optional 7-Zip, `MANIFEST.csv`,
  per-run change snapshots, standalone restore kit).
- **End user(s):** Technical Windows users / the author running scheduled or
  ad-hoc backups via `pwsh`; agents modifying the tool.
- **Active hats:** Stakeholder (the kit's current name for End User), UX/Docs,
  System Engineer, Software Engineer, Test Engineer. _Domain hat to consider: **Data-integrity/Storage** (hashing,
  dedup, atomicity, restore correctness) — the load-bearing risk area._
- **Supported platforms:** Windows + **PowerShell 7+** (`pwsh`) only (Windows
  PowerShell 5.1 is explicitly unsupported). Launchers/harness are PowerShell.
- **Constraints:** Restore kit must be self-contained (Common module + DLL +
  `Reconstruct.ps1` bundled); **Common must never depend on Engine**; manifest
  schema is a fixed 9-column contract; `System.IO.Hashing` 8.0.0 required;
  7-Zip/ffprobe optional. Tests sweep 4 storage modes (Mirror / HashAddressed ×
  ±Compress).
- **Non-goals:** _(confirm with human — e.g. non-Windows support, GUI, cloud
  targets, encryption-at-rest)._
- **Definition of done (for the retrofit):** Every existing capability and
  invariant is traced SN→SR→LLR→TC with **0 orphans**; the check harness is
  wired to Pester + PSScriptAnalyzer and runs green locally and in CI; the
  architecture map reflects the real module/function layout.

## Gate Sign-offs

Drop `G-Release` only if this becomes a one-off; FileBackup ships versioned, so
keep it.

| Gate | End User | UX/Docs | System Eng | Test Eng | Human |
|---|---|---|---|---|---|
| G1 — Requirements/UX/Constraints | APPROVE (driver) | APPROVE (driver) | APPROVE (driver) | n/a | **APPROVE 2026-06-05** |
| G2 — Decomposition & Test Coverage | n/a | n/a | APPROVE (driver) | APPROVE (driver) | **APPROVE 2026-06-05** |
| G3 — Implementation | n/a | n/a | APPROVE (driver 2026-08-22) | APPROVE (driver 2026-08-22) | **APPROVE 2026-08-22** |
| G-Release — Release readiness | n/a | n/a | PENDING | PENDING | PENDING |
| G-Final — Acceptance | PENDING | n/a | n/a | (evidence) | PENDING |

---

## Audit log

<!-- Append verdict blocks here per process.md §5. Newest at the bottom. -->

### DRIVER — G1 — Round 1 — 2026-06-05
Process scaffolded onto the existing repo (docs/, registries, trace.py,
gen_release_checklist.py). Registries are empty placeholders. Next: back-fill
UN/SR from README + AGENTS.md and reconcile against the existing test matrix.

### DRIVER (End User + UX + System Engineer hats) — G1 — Round 1 — 2026-06-05
Verdict: APPROVE (driver hats) — awaiting human ratification.
Back-filled the registries from README.md, AGENTS.md (invariants sec.3, test
matrix sec.6), the config schema, and observed `FileBackup.ps1` behavior.
Baseline before writing: tool green (Pester Unit 27/27), deps present
(System.IO.Hashing 8.0.0, 7-Zip, Pester 5.7.1, PSScriptAnalyzer 1.25.0);
`trace.py` clean.

What changed:
- `requirements/stakeholder-needs.md`: 12 core needs (SN-001..012) + 9 edge-case
  expectations (SN-013..021), each with priority + acceptance intent.
- `requirements/system-requirements.csv`: 27 measurable SRs (SR-001..027), each
  linked to ≥1 UN, with AcceptanceCriteria, Permutations (storage modes /
  compression / hash-freq), Priority, and Verification method. Test-verifiable
  SRs marked `Test`; mail SR-015 + onboarding SR-027 + degradation SR-020
  `Demonstration`; SR-016 (automation) + SR-019 (required deps) `Inspection`.
- `trace.py`: UN=21 SR=27, **0 UN-without-SR**. Remaining 52 orphans are all
  the expected SR→LLR/TC gaps that G2 will close (not G1 blockers).

Findings:
- [MINOR] SN-012 (first-run setup/docs) had no SR on first pass → added SR-027
  (Demonstration). Resolved.
- [MINOR] Non-goals + `COVERAGE_THRESHOLD` assumed from the brief, not yet
  human-ratified → see Open items.

G1 exit criteria status: UN complete w/ priority + acceptance intent + edge
cases ✅; every SR links ≥1 UN w/ measurable AcceptanceCriteria ✅;
constraints + non-goals captured ✅ (non-goals pending human confirm).
**Awaiting human sign-off to close G1 and open G2.**

### HUMAN — G1 — 2026-06-05
Verdict: APPROVE. G1 closed; proceed to G2.

### DRIVER (System Engineer + Test Engineer hats) — G2 — Round 1 — 2026-06-05
Verdict: APPROVE (driver hats) — awaiting human ratification.
Decomposed the 27 SRs into 25 LLRs (real Module + CodeSymbol) and 41 TCs mapped
to the existing tests; SR-016/SR-019 are Inspection-only (no LLR, per trace
rules) and still carry a TC. Wired the check harness and CI.

What changed:
- `requirements/low-level-requirements.csv`: LLR-001..027 (gaps at 016/019),
  each naming the real function(s) (e.g. SR-003→Invoke-BackupFileGroup/
  Get-HashSizeFileName, SR-005→Complete-ChangeFolder, SR-008→Reconstruct.ps1/
  Expand-FileWithSevenZip) with TestRefs.
- `test/test-cases.csv`: TC-001..042 (gap at 029). TC-001..028 map to real
  automated tests — the 7 Pester unit Describes + integration suite case ids
  (G1.1..G8.2). TC-030..042 cover the rest by Inspection/Analysis/Demonstration
  or are flagged as cheap auto-tests to add at G3.
- `scripts/gen_arch_map.ps1`: AST-based PowerShell module-map generator; fills
  the BEGIN/END block in `architecture.md`, `-Check` fails when stale.
- `scripts/check.ps1`: tiered gate (Smoke = lint + trace --strict + map-fresh +
  Pester unit; Full/Release add the Subst integration sweep); nonzero on any
  failure.
- `.github/workflows/tests.yml`: new `traceability` job (trace --strict +
  map-fresh, uploads report.md); `scripts/` added to the lint path.

Evidence (real output, local):
- `python scripts/trace.py --strict` → `UN=21 SR=27 LLR=25 TC=41 orphans=0`, exit 0.
- `pwsh scripts/check.ps1 -Tier Smoke` → PSScriptAnalyzer PASS, Traceability
  PASS (0 orphans), Architecture map PASS, Pester unit **27/27** PASS →
  "All steps passed." (Full-tier Subst sweep is a G3 step; not run this turn.)

Findings:
- [MINOR] Lint initially failed on legacy `Test-Backup.ps1` (unapproved verb);
  scoped the harness lint to the AGENTS.md sec.5 maintained surface
  (FileBackup.ps1, Reconstruct.ps1, Modules, tests, scripts). Resolved.
- [MINOR] Functions lack `Implements:` tags so the generated map shows "—" in
  the back-link column → tracked as G2/G3 hardening (Open items).

G2 exit criteria status: every SR → ≥1 LLR (or Inspection) ✅; every SR & LLR →
≥1 TC ✅; traceability **0 orphans** ✅; harness runs locally ✅ + CI wired ✅.
**Awaiting human sign-off to close G2 and open G3.**

### FINDING (carried to G3) — SR-016 / SR-019 — 2026-06-05
[MAJOR] `Initialize-XxHashLibrary` (Common) installs System.IO.Hashing on first
use via an interactive `Read-Host "(Y/N)"` with **no non-interactive fallback**.
An unattended `FileBackup.ps1` run on a host where the package is neither
installed nor bundled as a DLL would **block on the prompt** — the exact failure
SR-016 ("automation must never block") forbids; also touches SR-019.
→ G3 work item: add a `-NonInteractive` / `-AutoInstall` switch to
`Initialize-XxHashLibrary` (and thread it from `Initialize-Dependencies` /
`FileBackup.ps1`) so an unattended first run either auto-installs or fails loudly
with a non-zero exit instead of hanging. Add an LLR + an automated TC; this would
promote SR-016/SR-019 from Inspection to **Verified**. @SoftwareEngineer
(Until fixed, the documented mitigation stands: pre-run
`tests/Setup.ps1 -InstallDeps -NonInteractive`, or bundle the DLL.)

### HUMAN — G2 — 2026-06-05
Verdict: APPROVE. G2 closed; proceed to G3.

### DRIVER (Software Engineer + Test Engineer hats) — G3 — Round 1 — 2026-06-05
Verdict: CHANGES-REQUESTED (driver) — two decisions for the human (Current State).
Implemented the SR-016/SR-019 fix, added automated tests, tagged the code, and
ran the full tier green.

What changed (code):
- `Initialize-XxHashLibrary` (Common): added `-NonInteractive` / `-AutoInstall`;
  a missing package under -NonInteractive now throws with remediation instead of
  prompting. `Resolve-OptionalTool` + `Initialize-Dependencies` (Engine) and
  `FileBackup.ps1` thread `-NonInteractive` / `-AutoInstallDeps` end-to-end.
  Closes the SR-016 hang risk. Added LLR-016; SR-016 Inspection→Test→Verified.
- `Implements:` back-link tags on 25 functions across both modules; the generated
  `architecture.md` map now shows SR/LLR back-links and a fixed Exported column.

What changed (tests): +4 unit tests (now 31, all green):
- `Resolve-OptionalTool non-interactive` ×2 (SR-016) — would hang if it blocked.
- `FileBackup.ps1 entry point` throws on missing config (SR-018, TC-037).
- `Common does not depend on Engine` AST guard (SR-007, TC-031).
TC-031/036/037 promoted to automated/Pass.

Evidence (real output, local):
- `pwsh scripts/check.ps1 -Tier Full` → lint PASS · trace PASS (0 orphans) ·
  arch-map PASS · Pester unit **31/31** · integration **160 PASS / 0 FAIL /
  4 SKIP** (G8 RealVolume under Subst) → "All steps passed."
- `python scripts/trace.py --strict` → UN=21 SR=27 LLR=26 TC=41 orphans=0.
- Unit-test module line coverage: **22.0%** (187/849).
- SR truth-up: 18 Verified · 5 Open · 3 Demonstration · 1 Inspection.

G3 exit criteria status: lint clean ✅; full tier green ✅; coverage ≥ threshold
**❓ (22% unit — decision #1)**; every test-verifiable SR Verified **❌ (5 Open —
decision #2)**; non-test SRs explicitly Demonstration/Inspection ✅.
**Blocked on the two human decisions before G3 can close.**

### DRIVER (Software Engineer + Test Engineer + Data-integrity hats) — G3 — Round 2 — 2026-06-05
Verdict: CHANGES-REQUESTED (driver) — fixed two real defects; one design
question remains for the human.

Writing tests for the 5 Open SRs surfaced two genuine bugs in the data-integrity
surface (fixed) and one restore-semantics question (escalated):

- [BLOCKER→FIXED] **SR-023 capacity check was a no-op.** Reconstruct.ps1's
  "not enough free space" `throw` sat inside the same try/catch that tolerates a
  failure to resolve the target drive, so it was always swallowed — a restore
  onto a too-small target would silently produce a partial tree. Restructured so
  drive-resolution stays non-fatal but an actual shortfall aborts. Test: TC-040.
- [MAJOR→FIXED] **SR-014 under-reported failure.** A set whose path wouldn't
  resolve returned without setting OverallSuccess, so the run exited 0 despite a
  failed set; a mid-pipeline throw also aborted the remaining sets. Path-failure
  now marks the run failed; FileBackup.ps1 wraps each set so one set's throw
  can't abort the others. Test: TC-034 (good set still backs up; exit code 1).
- [QUESTION] **SR-010 historical restore** overlays the backup-root manifest as
  newest authority, so restoring from a change folder yields the *current*
  version of a modified file, not the captured prior version (contradicts
  SN-004). Left SR-010 **Open** pending the human's intended semantics; did not
  guess at a fix on the restore-correctness path.

New tests (tests/Unit/Coverage.Tests.ps1, +4 → 35 unit total, all green):
SR-005 (change-folder naming + manifest), SR-014 (multi-set + exit code),
SR-023 (capacity abort), SR-026 (cross-change collapse).

Evidence (real output, local):
- `pwsh scripts/check.ps1 -Tier Full` → lint PASS · trace PASS (0 orphans) ·
  arch-map PASS · Pester unit **35/35** · integration **160 PASS / 0 FAIL /
  4 SKIP** → "All steps passed."
- Module line coverage **69.6%** (592/850), up from 22.0% (the in-process backup/
  reconstruct tests exercise the engine I/O shells under Pester).
- SR truth-up: **22 Verified · 1 Open (SR-010) · 3 Demonstration · 1 Inspection**.

NOTE (high-risk surface): SR-014/SR-023 touch restore + orchestration; per
process.md §6 an independent pre-gate review is advisable before G3 sign-off.

### DRIVER (End User + System Engineer hats) — SNAPSHOT REDESIGN G1 — Round 1 — 2026-06-05
Verdict: APPROVE (driver) — awaiting human ratification.
Approved plan: `~/.claude/plans/refactored-jingling-panda.md` (dated-snapshot
model; delta + hash-pull storage; clean cutover). Stepped back to requirements.

What changed (docs only — no code touched; suite still green):
- `stakeholder-needs.md`: SN-004 (point-in-time snapshots, each fully restorable) +
  SN-006 (restore a dated snapshot byte-exact) revised to the new model.
- `system-requirements.csv`: SR-005 rewritten (dated `Snapshot_<date>` naming,
  no snapshot for the latest/no-op run, atomic completion) → Draft; SR-010
  rewritten (snapshot's own manifest authoritative, bytes resolved by hash from
  the live backup + sibling snapshots, no newer-manifest overlay) → Draft; new
  SR-028 (delta + hash-pull storage, clean cutover) → Draft.
- `AGENTS.md` §3: forward-pointer note (did NOT rewrite the live `Pre_` invariant
  — AGENTS documents current code facts; the regex/pipeline rewrite lands at G3
  with the code, to avoid a doc/code mismatch). Deviation from the plan's literal
  "G1 updates AGENTS §3" for that reason.
- `trace.py`: UN=21 SR=28 LLR=26 TC=41, **orphans=2** — both SR-028 (no LLR/TC),
  expected at G1 and closed at G2. SR-005/SR-010 stay non-orphan via existing
  LLR/TC (revised at G2/G3).

G1 exit criteria: UN updated w/ acceptance intent ✅; SRs measurable + linked ✅;
constraints (clean cutover) captured ✅. **Awaiting human G1 sign-off to open G2.**

### HUMAN — SNAPSHOT REDESIGN G1 — 2026-06-05
Verdict: APPROVE. Folder name `Snapshot_<date>` confirmed; snapshot date = prior
backup completion time persisted in FileBackupState.json confirmed. Proceed to G2.

### DRIVER (System Engineer + Test Engineer hats) — SNAPSHOT REDESIGN G2 — Round 1 — 2026-06-05
Verdict: APPROVE (driver) — awaiting human ratification.
Decomposed the revised SRs; trace back to 0 orphans (docs only, suite green).

What changed:
- `low-level-requirements.csv`: LLR-005 → dated `Snapshot_<date>` completion
  (skip empty/latest); LLR-010 → reconstruct authority rule (snapshot manifest is
  sole authority; bytes by hash over backup root + all snapshots); new LLR-028 →
  persisted last-backup date (`Get/Set-LastBackupRun`), delta storage, `^Snapshot_`
  regex in `Get-FileBackupDefaults`, clean cutover.
- `test-cases.csv`: TC-030 → dated-naming + no-op-no-snapshot (Draft); TC-033 →
  the **point-in-time restore** test (v1→v2 ⇒ snapshot=v1, root=v2) (Draft); new
  TC-043 (delta storage / hash-pull) + TC-044 (AST check: no `Pre_*` left) (Draft).
- `trace.py --strict`: UN=21 SR=28 LLR=27 TC=43, **orphans=0**, exit 0. Unit
  suite still green (no code touched; the current `Pre_` test stays green until
  G3 replaces it).

G2 exit criteria: every revised/new SR → ≥1 LLR ✅; every SR & LLR → ≥1 TC ✅;
**0 orphans** ✅; harness green ✅.

**G2 expansion (human-requested permutation matrix + date seam, 2026-06-06):**
- Injectable backup-date seam folded into LLR-005 (`Complete-ChangeFolder
  -BackupTime`) and LLR-028 (`Set-LastBackupRun -When`) — deterministic snapshot
  dating for tests, mirroring the existing `Test-HashRecalcDue -Now`.
- New rollback matrix TCs → a planned **`G9-Rollback` suite**: TC-045 (restore
  as-of EACH historical snapshot + latest, byte-exact, × 4 storage modes),
  TC-046 (snapshot lifecycle/naming over a dated timeline; no snapshot for
  no-op/latest), TC-047 (mixed content — compressible / already-compressed media
  / binary / empty / duplicate / nested-infra-named / unicode-bracket — handled
  + hash-restorable at every rollback point). SR-010 permutations extended with
  `snapshot=set{each-historical,latest}`.
- Rationale: rollback verification had **zero** coverage and there was no seam to
  date snapshots deterministically — gaps the user flagged before G3.
- trace `--strict`: UN=21 SR=28 LLR=27 TC=46, **orphans=0**. Suite still green.

**Awaiting human G2 sign-off to open G3.** (G3 is the high-risk restore-path
change → independent review per process.md §6.)

### HUMAN — SNAPSHOT REDESIGN G2 — 2026-06-06
Verdict: APPROVE. Proceed to G3 implementation. (Checkpoint committed.)

### DRIVER (Software + Test + Data-integrity hats) — SNAPSHOT REDESIGN G3 — Round 1 — 2026-06-06
Verdict: implemented + validated; **recommend an independent restore-path review
before final human sign-off** (high-risk surface, process.md §6).

Implemented the dated-snapshot model (clean cutover):
- Common: `^Snapshot_` regex + `SnapshotPrefix`; merged state file.
- Engine: `Read-BackupState`/`Set-BackupStateField` (merge), `Get/Set-LastBackupRun`;
  **`Save-SupersededData`** (the crux — preserves prior bytes BEFORE Mirror
  overwrite / HashAddressed orphaning, refcount-safe via new-source survival
  check); `Complete-ChangeFolder` → dated naming, skip-empty, copies the path
  sidecar; `Invoke-BackupSet` → `-BackupTime` seam, prior-date snapshot, persists
  `LastBackupRun`.
- `Reconstruct.ps1`: snapshot's own manifest is sole authority (no overlay); data
  pool = backup root + all snapshots (null-safe); `^Snapshot_` pattern.
- FileBackup.ps1 + harness `Invoke-Backup`: `-BackupTime` passthrough.

Scope note: the plan assumed storage "barely changes," but writing the tests
revealed modified-file/Mirror-overwrite byte loss — `Save-SupersededData` (new
pipeline step 9.5) was required for correct point-in-time restore. Flagged + done.

Tests (all green): clean-cutover AST (TC-044), point-in-time restore × 4 modes
(TC-033), new **G9-Rollback** suite (TC-045/046/047) — dated timeline with
modify/delete/add/no-op, restore-as-of-each + latest byte-exact, mixed content.

Evidence (real, local): `pwsh scripts/check.ps1 -Tier Full` → lint PASS · trace
PASS (**0 orphans**, UN=21 SR=28 LLR=27 TC=46) · arch-map PASS · Pester **42/42** ·
integration **212 PASS / 0 FAIL / 4 SKIP** → "All steps passed."
SR truth-up: **SR-005/SR-010/SR-028 → Verified.**

Self-review (data-integrity): superseded bytes preserved before overwrite in all
4 modes ✓; shared/surviving data never evicted (survival check) ✓; no-op &
first-run create no snapshot ✓; snapshot self-contained via copied sidecar ✓;
state-file merge keeps LastHashRun+LastBackupRun ✓; reconstruct null-safe ✓.
Residual gaps for the reviewer: explicit **rename** rollback assertion (covered
indirectly by add/delete) and many-snapshot Optimize interaction (2 in G9).

**Open:** independent reviewer pass, then human G3 sign-off.

### INDEPENDENT REVIEWER — SNAPSHOT REDESIGN G3 — 2026-06-06
Verdict: **APPROVE** (2 MINOR). Fresh-context defect hunt on the restore/data-
integrity surface; ran `check.ps1 -Tier Full` (236/0/4) and 4 adversarial probe
timelines across all 4 modes (delete→re-add-different, 4-version history,
duplicate-modify, dedup-both-modified) — **no data loss**. Confirmed: superseded
bytes preserved before overwrite; survival check correct; refcount-aware eviction;
Optimize never removes a byte a snapshot still needs; reconstruct authority +
data-pool correct; clean cutover.
Findings:
- [MINOR→FIXED] `Reconstruct.ps1` target guard used `-like "$root*"` →
  false-rejected prefix-sharing siblings (`bk` vs `bk-restore`) and mishandled
  bracket/wildcard chars. Replaced with normalized full-path `StartsWith` +
  trailing separator (`Test-PathIsInside`); added Pester test 'Restore target
  guard (SR-009)'. Strengthens SR-009. Full tier re-run green (236/0/4, 43 unit).
- [MINOR→BACKLOG] Crash mid-run can leave an orphaned `Temp` with a transient
  manifest/data mismatch; next run aborts loudly (SR-017 guard) — recovery is
  manual. Inherent to staging; current behavior matches SN-013 (fail loudly).
  Future hardening: auto-roll-back a stale `Temp` instead of only refusing.

### DRIVER — SNAPSHOT REDESIGN G3 — 2026-06-06
Independent review APPROVED; sole actionable finding fixed + tested. **Awaiting
human G3 sign-off** to close the dated-snapshot redesign.

### DRIVER (Software + Test Engineer hats) — template re-sync + gap sweep — 2026-06-09
Verdict: APPROVE (driver) — process-tooling + docs change; no engine/restore
behavior touched (module edits are comment-only).

Applied the four ai-template commits newer than the last sync (2e32d0b flow +
interface contracts; e7fa050 harness/tier/trace fixes + --require-verified;
0418812 kit restyle; 05c50ab Mermaid convention + dependency diagram):
- docs/process.md, scripts/trace.py, scripts/gen_release_checklist.py replaced
  with template HEAD (all three were verbatim kit copies); scripts/gen_cases.py
  added (the SR Permutations cells already use its grammar).
- scripts/gen_arch_map.ps1 ported the two new generators: a Mermaid dependency
  diagram (modules + entry scripts, so Common⊥Engine AND Reconstruct→Common-only
  are visible) and the ordered `Invoke-BackupSet` flow; duplicated-marker guard;
  `Implements:` harvesting now anchored to the comment line (a help-block prose
  mention had produced a wrong back-link). Markers added to architecture.md
  (flow + diagram) and AGENTS.md (diagram).
- check.ps1 gained -Gate (G2|G3|all); G3/all add `trace.py --require-verified`
  (the machine half of the G3 "every Test SR Verified" criterion). CI now runs
  --require-verified and triggers on every branch push.

Gap sweep findings (fixed):
- [MAJOR] Comment-based help placed *after* the `# Implements:` line in 19
  module functions silently broke `Get-Help` and summary harvesting → order
  swapped module-wide; 7 orchestration functions lacking any .SYNOPSIS got one.
  Convention recorded in AGENTS.md §4 + CLAUDE.md.
- [MINOR] No AST guard for "Reconstruct.ps1 calls only Common" (the sibling of
  the Common⊥Engine guard) → added (TC-048, SR-007).
- [MINOR] Stale docs: AGENTS §1 still described the Pre_*_Changes model; §5/§6
  carried outdated test totals; suite-group axes said G1–G8; START_HERE listed
  the already-done wiring as deferred → all refreshed.

Evidence (real output, local): `check.ps1 -Tier Full` → lint PASS · trace PASS
(UN=21 SR=28 LLR=27 TC=47, 0 orphans, 0 status findings) · generated docs fresh ·
Pester unit **48/48** · integration **236 PASS / 0 FAIL / 4 SKIP** →
"All steps passed."

### DRIVER (System + Test Engineer hats) — kit re-sync 2026-07 — 2026-07-01
Verdict: APPROVE (driver) — process-tooling + docs change; no engine/restore
behavior touched (the only .ps1 edited is scripts/check.ps1). Pilot adoption
for the kit's Thread-27 core/optional split; friction fed back to ai-template.

Applied ai-template @ e4bcfb1 (Threads 24–28 + WI-1.3 since the 2026-06-09
sync), on branch `kit-resync-2026-07`:
- **Process split:** docs/process.md replaced with the current core (§1–§7 +
  applies-when summaries); new docs/process-options.md carries the expansions.
  This repo runs the stated **minimum profile** (rung 1, standalone).
- **Spine rename:** `user-needs.md`/UN-### → `stakeholder-needs.md`/SN-###
  (kit Thread 7); ids keep their numbers so older entries in this log still
  resolve. `SN-Refs` column renamed; CI job title updated. Historical evidence
  quotes ("UN=21…") left verbatim — they record what the tool printed then.
- **Harness:** trace.py/gen_release_checklist.py/gen_cases.py re-synced
  (verbatim kit copies); check_docs.py + check_perf.py adopted and wired into
  check.ps1 (steps 3 and 6) and CI; docs/gate (G3) is now the default -Gate
  source; .githooks/pre-commit added (map freshness + id integrity; opt-in via
  core.hooksPath); .gitattributes pins the hook to LF. Inert optional
  registries scaffolded: performance-budgets.csv (PB-000), procurement.csv
  (PART-000).
- **Not adopted, deliberately:** check_flows.py (would demand a hand-authored
  "Runtime flows" section; the generated Invoke-BackupSet flow + AGENTS.md §2
  pipeline already serve reviewable-flow duty — revisit if a concurrency-heavy
  change lands) and check_stubs.py (Python-only; would pass vacuously on a
  PowerShell tree). check.ps1 (not the kit's check.py) stays the single gate
  command: it is the one definition of passing this Windows/Pester repo runs
  locally and in CI.

Evidence (real output, local, post-upgrade):
- `pwsh scripts/check.ps1 -Tier Full` → lint PASS · trace PASS (SN=21 SR=28
  LLR=27 TC=47, orphans=0, integrity=0, status-findings=0) · doc navigability
  PASS (0 broken links) · generated docs fresh · Pester unit **48/48** ·
  perf-budgets PASS (inert) · integration **236 PASS / 0 FAIL / 4 SKIP** →
  "All steps passed." (identical totals to the pre-upgrade baseline).
- `sh .githooks/pre-commit` → exit 0.

**Open:** the pre-existing item stands — human G3 sign-off on the
implementation truth-up + snapshot redesign (this re-sync does not change that
scope). New minor: consider a PowerShell check_stubs equivalent and a
"Runtime flows" section as future hardening, not gate blockers.

<!-- agent-setup --> Agent setup (2026-07-02): agents=`claude`; skills materialized: downstream-resync, gate-advance, registry-hygiene. AGENTS.md remains the canonical, agent-neutral guide (skills are opt-in accelerators, not a process gate).

### Kit re-sync — 2026-07-02 — (prev: kit e4bcfb1, unstamped) → 9b697cc (WI-1.6..WI-1.12)

Kit-owned overwrites: docs/process.md (+ meta strip), docs/process-options.md,
scripts/trace.py (Attest vocabulary + assets.csv integrity). docs/kit-version
now exists (the pilot predated the stamp feature — first stamped state).
New: docs/requirements/assets.csv (inert), .claude/skills (3) + inert
settings.json.example, GEMINI.md stub, run.cmd.
Decisions (dial: recorded, reversible):
- run.cmd wired to `pwsh -NoProfile -File FileBackup.ps1` (README Quick-start
  flow; args pass through). POSIX run.sh/run.command not shipped (PS7/Windows
  product). RECONSTRUCT.bat remains the restore entry, unchanged.
- Bootstrap over-scaffold pruned to honor this repo's recorded "not adopted
  (deliberate)" stance: removed check.py/check.sh (check.ps1 stays the single
  gate), check_flows.py/check_stubs.py (recorded not-adopted), gen_arch_map.py
  (the .ps1 port is this repo's generator — bootstrap's initializer had
  clobbered the generated diagram with Python-AST output; reverted),
  pytest.ini, kit check.yml (tests.yml is this repo's CI), setup/dev-setup/
  onboard scripts (minimal-adoption stance), src/tests .gitkeep noise.
- .githooks/pre-commit kept as this repo's local adaptation (drives
  gen_arch_map.ps1); the kit's Scripts/-case fix is moot here (lowercase).
- CLAUDE.md gains decision dial (= HIGH: data-safety product — surface often;
  autonomous only for trivially-reversible non-engine work, recorded),
  commit-cadence rule, and the deliberate-subagent bullet.

### INDEPENDENT REVIEWER (sonnet subagent) + DRIVER verification — adversarial dedup/snapshot review — 2026-07-02
Verdict: CHANGES-REQUESTED (3 findings, all driver-reverified) — while the
primary adversarial question is APPROVED/confirmed.

Primary question (user-posed): file deleted → reintroduced identical → deleted
again ⇒ bytes stored exactly ONCE across backup root + Snapshot_* folders, all
dated states restorable. **CONFIRMED** twice independently: driver probe
(4 modes × 4-run timeline; copies=1 at every stage; 16/16 restore checks) and
reviewer probe (4 modes × 5-run timeline incl. second reintroduce; copies=1 at
every stage; 16/16 restores). Mechanism: reintroduce briefly makes a transient
second copy (Invoke-BackupFileGroup checks only the live manifest for reuse) but
Optimize-ChangeFolders collapses to one copy in the same pipeline pass, blanking
the losing DataPath rows, which recover by (hash,length) — verified two levels
deep. Pinned as TC-049 / Coverage.Tests "Re-deleted content stored once across
snapshots" (commit c930f4f). Adjacent probes also clean: shared-content paths
deleted at different times (refcount correct), same path returning with a
different size (distinct group, no cross-contamination).

Findings (per §5; owners to act only after human direction — engine surface):
- [MAJOR] SR-005 area → a run whose ONLY manifest change is a duplicate-content
  add or a shared-content removal produces NO snapshot: `Complete-ChangeFolder`
  gates on `$ChangedCount`, which increments only on physical copy/evict I/O
  (Invoke-BackupFileGroup new-copy branch; Move-RemovedFilesToStaging eviction),
  not on manifest-only changes (dedup reuse branch; still-referenced skip). The
  preceding state is then permanently unrestorable, logged misleadingly as "No
  prior state superseded". Repro: probe6 (add B.txt duplicating A.txt ⇒ no
  Snapshot_D0). G9 misses it because its dup-delete co-occurs with a content
  modify. → Suggested: gate snapshot creation on a real manifest diff, not byte
  I/O; extend G9/TC with a manifest-only-change run. → @SoftwareEngineer
- [MAJOR] SN-013/SR-009 area → `Reconstruct.ps1` completes with exit 0 when a
  row''s bytes cannot be recovered (logs "WARN: cannot recover … skipping").
  A scripted/CI restore checking the exit code sees success on an incomplete
  tree — violates the fail-loudly principle. Repro: probe4 (delete the snapshot
  holding the sole physical copy; restore of the older snapshot exits 0 with the
  file silently missing). → Suggested: aggregate unrecovered-row count ⇒ nonzero
  exit (+ summary line), document snapshot folders as load-bearing. → @SoftwareEngineer
- [MINOR] SR-022 area → `Test-IsInfrastructureFile` allowlist omits the
  `RECONSTRUCT.paths.json` sidecar that New-ReconstructScript writes ⇒ two false
  [WARN]s per run in backup.log (orphan/unreferenced). Confirmed in probe logs.
  → Suggested: add the sidecar name to the `$infra` list + TC for no-WARN run.
  → @SoftwareEngineer

Evidence: reviewer probes probe1/2/4/5/6 (scratchpad, repo untouched) re-run by
driver for findings 1–2; finding 3 confirmed in code (`$infra` list) and driver
probe backup.log. New TC-049 test PASS; `check.ps1 -Tier Smoke` green after
pinning (49 unit); trace: SN=21 SR=28 LLR=27 TC=48, 0 orphans, 0 findings.
**Next action (human):** approve the three fixes as a scoped change through the
gate (SR/LLR/TC revisions for findings 1–2 are requirement-level, not patches).

### HUMAN — review-findings scoped change — 2026-07-02
Verdict: APPROVE ("That all sounds appropriate, please proceed") — fix the three
2026-07-02 review findings as a scoped change through the gate.

### DRIVER (System + Software + Test + Data-integrity hats) — REVIEW-FINDINGS G1→G3 — 2026-07-02
Verdict: implemented + validated; independent review APPROVE (below). Awaiting
human ratification.

G1 (requirements): SR-005 rewritten — the supersession criterion is a **manifest
diff** (any added/removed/changed row, incl. dedup-served adds and shared-content
removals), not physical byte I/O; permutations extended with
change=set{content,dup-add,shared-removal,noop}. New **SR-029** (SN-013):
Reconstruct restores everything recoverable, then fails loudly (non-zero exit)
naming the unrestored count; clean restores exit 0. Finding 3 needed no SR change
(SR-022 already covers it — implementation gap only).

G2 (decomposition): LLR-005 revised (gate = Compare-SourceToBackup diff
non-empty); new LLR-029 (unrestored-row accounting + terminal throw); LLR-022
extended (allowlist covers every deployed kit artifact). New TC-050 (manifest-only
change ⇒ snapshot; no-op ⇒ none), TC-051 (fail-loudly restore), TC-052 (no false
sidecar WARNs). Trace: SN=21 SR=29 LLR=28 TC=51, 0 orphans / 0 integrity.

G3 (implementation):
- Engine: Invoke-BackupSet computes $manifestChanged from the diff and passes
  -ManifestChanged to Complete-ChangeFolder (replaces the -ChangedCount gate;
  the byte counter remains for logging). Skip log now states why (first backup
  vs manifest-identical no-op). Gotcha hit + documented in code: `@()` around a
  List reached via a PSObject property throws "Argument types do not match" on
  PS 7.5 — use .Count directly.
- Reconstruct.ps1: $unrestored list collects every skip (hash-recovery failure,
  missing DataPath, extraction failure); after restoring all recoverable rows a
  non-empty list logs ERROR and throws "Reconstruction INCOMPLETE: N file(s)…"
  (⇒ exit 1 via pwsh -File and RECONSTRUCT.bat).
- Engine: RECONSTRUCT.paths.json added to the Test-IsInfrastructureFile allowlist.

Evidence (real output, local): both original repros re-run — dup-add now creates
Snapshot_<D0> with both states individually restorable; tampered restore exits 1
with the INCOMPLETE error. Driver edge probe: 0-byte files through
shared-removal/delete/re-add cycles — all snapshots + latest restore correctly,
no spurious throw. `check.ps1 -Tier Full` → lint PASS · trace 0/0/0 ·
docs fresh · Pester **52/52** · integration **236 PASS / 0 FAIL / 4 SKIP**.

### INDEPENDENT REVIEWER (sonnet subagent) — REVIEW-FINDINGS G3 — 2026-07-02
Verdict: **APPROVE** (0 defects; 1 cosmetic nit, fixed). Fresh-context probing of
the three fixes: no false-positive snapshot from layout migration (3-run
Mirror→HashAddressed+Compress→Mirror cycle ⇒ 0 snapshots; Sync-BackupStorageLayout
mutates only DataPath/Compressed/StoredAsHashSize, never the diffed fields) or
forced rehash (freq=A rehash leaves hash/mtime identical); no false-negative
escape constructed; hypothesized [long]0 empty-file throw does not occur
(Import-Csv yields string "0" — truthy; end-to-end blank-DataPath 0-byte rows
hash-recover cleanly); throw semantics verified via pwsh -File AND the generated
RECONSTRUCT.bat (clean=0, tampered=1, multi-failure message accurate, partial
tree preserved); PS 7.5 @()-on-List workaround independently reproduced. Ran
52/52 unit, Mirror full-group sweep 59/0/1, lint 0, trace 0/0/0, Smoke tier all
green. Nit: test-cases.csv trailing newline — restored by driver.

### DRIVER (UX/Docs hat) — demonstration tooling — 2026-07-03
Autonomous (trivially-reversible, non-engine; recorded per the HIGH dial):
added `scripts/demo_timeline.ps1` — a narrative Demonstration artifact that
drives a create/modify/remove/re-add/no-op timeline and emits a legible,
timestamped Markdown report (source events → backup outcome → restore +
xxHash128 byte-compare verification → point-in-time reconstruction of every
snapshot). Human-requested ("see that timestep in motion"). Not a gate test;
the gated suites remain authoritative. First run: Overall PASS (5 runs,
3 snapshots). Lint clean.

**Open scope question (human):** a bash/Linux variant (restore-first) was
discussed 2026-07-03 — would reverse the recorded "non-Windows" non-goal, so
it needs a G1 scope revision before any code. Awaiting explicit go-ahead.

### HUMAN — bash/Linux variant — 2026-07-03
Verdict: APPROVE — "Yes run the G1 pass, and then create a detailed plan file
for restructuring that I can hook Opus into to perform the convert, then I''ll
come back here to perform the final review and cross-check." Reverses the
non-Windows non-goal for the restore path.

### DRIVER (Stakeholder + System Engineer hats) — BASH-VARIANT G1 (+G2 skeleton) — 2026-07-03
Verdict: APPROVE (driver) — G1 artifacts registered; executing-agent handoff
plan written; awaiting the converted implementation, then human cross-check.

What changed (docs/registries only — no engine code):
- stakeholder-needs.md: SN-022 (restore on Linux from the backup folder alone,
  bash-v1) + SN-023 (Linux-produced interoperable backups, bash-v2, deferred).
- system-requirements.csv: new optional **Phase** column (blank = always in
  scope, per trace.py "Phased delivery"); SR-030 hash conformance, SR-031
  standalone bash restore (full SR-008/010/009/023/029 semantics), SR-032
  manifest portability — Draft, Phase=bash-v1; SR-033 bash backup-engine
  parity — Draft, Phase=bash-v2.
- Skeleton decomposition so the tree stays green between now and the convert:
  LLR-030..033, TC-053..057 (Draft; the executing agent refines at its G2).
- check.ps1 + CI trace step: `--require-verified --phase core` — deferred-phase
  SRs are exempted EXPLICITLY and counted (phase-deferred=4), so the G3 ratchet
  stays armed for everything already shipped. When bash-v1 lands, the phase
  list becomes `core,bash-v1`.
- **docs/plans/bash-variant-plan.md** — the executing-agent work order: pinned
  on-disk contract (manifest dialect, ''O'' dates, hash canonical form, snapshot
  regex, authority/pool rules, sidecar caveat, layout-detection + single-file
  decisions), deliverables/layout, fixtures strategy, bats + ubuntu +
  cross-artifact CI plan, commit-ordered work items, out-of-scope fence, and
  the §7 acceptance checklist the human will cross-check against.

Evidence (real output, local): `trace.py --strict --require-verified --phase
core` → SN=23 SR=33 LLR=32 TC=56, **0 orphans / 0 integrity / 0 status
findings / 4 phase-deferred**, exit 0.

### DRIVER (System + Test Engineer hats) — BASH-VARIANT bash-v1 G2 refinement — 2026-07-03
Verdict: APPROVE (driver) — registry-only refinement; no engine code touched.
Executing [plans/bash-variant-plan.md](plans/bash-variant-plan.md) end-to-end.

**De-risking (plan §6 step 3) done FIRST — hash conformance CONFIRMED.** Acceptance
environment is **WSL Fedora 40** (`podman-machine-default`; `dnf`-installed xxhash
0.8.3 / p7zip / bats / shellcheck; gawk present) — a real Linux run, not Git Bash.
Probed empty / one-byte / 20-byte-text / 100 KB-random inputs: `xxh128sum <f> |
cut -d' ' -f1` uppercased **equals `Get-FileXxHash` byte-for-byte** in every case.
The whole phase's pivot risk is retired before any implementation.

What changed (registries only):
- LLR-030/031/032 refined off their skeletons to honor the plan's **pinned
  self-containment decision**: the hasher (`hash_file`), CSV parser
  (`parse_manifest`), and path mapper (`to_posix_path`) are functions **inside the
  single `bash/reconstruct.sh`** (no `source`d runtime libs); a bottom-of-file
  `main` guard lets bats source the script to unit-test those functions. The prior
  skeleton wrongly located them in a `bash/lib/common.sh` — corrected (ids kept).
- TC-053..056 already carried dimensional Parameters/Expected from G1 skeleton;
  left as-is (they match the deliverables).

Evidence (real output, local): `python scripts/trace.py --strict --require-verified
--phase core` → SN=23 SR=33 LLR=32 TC=56, **0 orphans / 0 integrity / 0 status
findings / 4 phase-deferred**, exit 0. SR-030/031/032 remain Draft (flip at G3
with the real green Linux run). Next: fixtures + `reconstruct.sh` (plan §6 2–5).

### FINDING (surfaced by bash-v1, PS-side — recorded, NOT fixed per plan §6) — SR-010/SR-022 — 2026-07-03
[MAJOR — for the human] **`Reconstruct.ps1`'s `Find-DataFileByHash` over-skips
infra-named files recursively, so a nested user file named like an infrastructure
file (regression B6) becomes UNRECOVERABLE from a Mirror-mode snapshot.** The
pinned contract (plan §2; AGENTS.md §3 "Infrastructure files are root-level only")
says the infra-name skip is **root-level only** — a nested `sub\MANIFEST.csv` is
data. But `Find-DataFileByHash` applies its `^(MANIFEST|RECONSTRUCT|FileBackup\.Common|System\.IO\.Hashing|FileBackupState)`
skip to **every** file in a `-Recurse` scan. When such a file is unchanged across
runs, `Optimize-ChangeFolders` blanks its DataPath in each snapshot (bytes recover
by hash) — but the only surviving copy is the Mirror-layout data file named
`sub\MANIFEST.csv`, which the recursive skip excludes ⇒ the row is reported
unrestorable and the snapshot restore FAILS LOUDLY (SR-029 exit 1). Reproduced on
the bash-v1 fixture timeline (Mirror + Mirror+Compress; HashAddressed is immune —
its data files carry short-names, not `MANIFEST.csv`). Driver-verified: with a
**root-level-only** skip (the contract) the same row recovers cleanly.
- **Scope call:** engine/restore surface → per plan §6 "record it in status.md and
  **stop** on that item rather than fixing the Windows side unilaterally." Not
  fixed here. Suggested PS fix (for the human): make the recovery skip root-level
  only (parent == search-folder root), matching the contract; add a G9 assertion
  that restores a Mirror snapshot holding a blanked nested-infra-named row.
- **bash-v1 stance:** `reconstruct.sh` implements the **contract** (root-level-only
  skip), so it restores these fixtures correctly. This is a deliberate,
  documented divergence from the current PS code (which has the bug), not from the
  contract — recorded in LLR-031 and the README.

### DRIVER (Test Engineer hat) — BASH-VARIANT bash-v1 fixtures — 2026-07-03
Autonomous (test-scaffolding, non-engine; recorded per the HIGH dial). Added
`scripts/gen_bash_fixtures.ps1` — drives the **real engine** over a fixed,
deterministic 3-run timeline (pinned `-BackupTime`, fixed bytes + mtimes) to emit
the committed golden fixtures under `tests/fixtures/`:
- `hash-conformance/` — empty / one-byte / text / unicode-named / >1 MiB binary +
  `expected-hashes.csv` (golden `Get-FileXxHash`). The 1 MiB binary is SR-030's
  explicit "binary >1 MiB" multi-buffer case (regenerable, so drift is reviewable).
- `bash-restore/<mode>/` (all 4 modes) — `backup/` + nested `changes/Snapshot_*` +
  `expected/<origin>.tsv` (posix-relpath⇢content-hash from each origin's own
  manifest = the independent restore oracle). Timeline covers dedup, a modified
  file (v1↔v2 point-in-time), delete→identical-re-add (⇒ 16 blank-DataPath rows
  recovered by hash), a 0-byte file, unicode / bracketed / comma-bearing names,
  and a nested `sub/MANIFEST.csv` (B6). Committed copies are stripped of the
  large/churny Windows kit (DLL/psm1/RECONSTRUCT.*) + logs and carry a stabilized
  Windows-path sidecar (proves reconstruct.sh ignores it on Linux). Total ~1.2 MB
  (≈1 MB is the conformance binary); `-Fresh` keeps everything for the CI interop
  job. Fixtures regenerate deterministically (EXIT=0, all 4 modes, 2 snapshots each).

### DRIVER (Software + Test + Data-integrity hats) — BASH-VARIANT bash-v1 G3 — 2026-07-03
Verdict: implemented + validated on real Linux; independent review below.
Delivered `bash/reconstruct.sh` — one self-contained POSIX-shell restorer
mirroring `Reconstruct.ps1` against the same MANIFEST.csv contract:
- `hash_file` (xxhsum/xxh128sum → 32-char UPPER hex), `parse_manifest` (gawk
  FPAT RFC-4180; \x1f-delimited output so an empty leading DataPath is NOT
  trimmed — the key parse bug found + fixed), `to_posix` (`\`→`/`).
- folder-name authority/layout detection (origin = `--from`, default PWD; a
  Windows-path sidecar is ignored when it doesn't resolve; explicit
  `--backup-root`/`--change-root` > sidecar > auto-detect); data-pool hash
  recovery over snapshots+backup-root; 7z **dir-extract + first-file** (a shared
  dedup archive can hold >1 identical-content entry — `-so` streaming would
  concatenate them, the second bug found + fixed); capacity + target-inside
  guards; **fail-loudly** non-zero exit naming the unrestored count.
- **Contract-faithful divergence:** root-level-only infra skip (recovers the
  nested B6 `sub/MANIFEST.csv` that the PS recursive skip drops — see the FINDING
  above).

Evidence (REAL runs):
- **WSL Fedora 40 (real Linux, plan's accepted env):** `bats tests/bash/` →
  **22/22 ok**; `shellcheck` clean on reconstruct.sh + helpers + verify_restores.
- Adversarial probes (driver): root restore with `changes/` deleted → 0;
  snapshot restore with a sibling snapshot deleted → 0; bad origin → 2; bogus
  `--seven-zip` on a compressed backup → dies with remediation (2); leading-dash
  filename → restored; `--help` → 0; unknown arg → 2.
- **Windows suite untouched:** `pwsh scripts/check.ps1 -Tier Full` → lint PASS ·
  trace **SN=23 SR=33 LLR=32 TC=56, 0 orphans / 0 integrity / 0 status-findings /
  1 phase-deferred** (`--phase core,bash-v1`) · docs PASS · arch-map PASS ·
  Pester **52/52** · perf PASS · integration **236 PASS / 0 FAIL / 4 SKIP** →
  "All steps passed."
- SR-030/031/032 → **Verified**; TC-053..056 → **Pass**; LLR-030..032 →
  **Verified**. Ratchet re-armed in `check.ps1` + CI (`--phase core,bash-v1`).
- CI: new `bash-restore` (ubuntu bats + shellcheck) and `bash-interop-make/
  -restore` (windows makes fresh 4-mode backups → ubuntu restores every origin
  and byte-compares) jobs added; they run on push (the human's final review is
  the acceptance gate).

Nothing from the plan's "explicitly out" list was started (no kit bundling of
reconstruct.sh, no bash-v2 engine, no engine-behavior change — the one PS defect
found is recorded above, not fixed). **Open:** independent review (below), then
human final review + cross-check against the plan §7 checklist.

### INDEPENDENT REVIEWER (fresh-context subagent) — BASH-VARIANT bash-v1 — 2026-07-03
Verdict: **APPROVE** (2 MINOR + 2 NIT; both MINORs are shared with Reconstruct.ps1).
Ran on WSL Fedora 40 (real Linux): reproduced 22/22 bats + shellcheck clean, then
~20 adversarial scenarios. **Could not reach any silent wrong-bytes restore, nor
any exit-0-incomplete case for an uncorrupted manifest** — the load-bearing safety
property holds. Confirmed sound: the empty-leading-DataPath `\x1f` parser fix (16
blank-DataPath rows recover end-to-end), the 7z multi-entry dir-extract fix (the
shared dedup archive genuinely holds 2 entries / 26 bytes → 13-byte payload
written, both dups byte-exact), and the root-level-only infra skip in BOTH
directions (root-level `FileBackupState.json` skipped; nested `sub/MANIFEST.csv`
used as data). A same-length/wrong-hash pool file is correctly rejected, not
grabbed. All exit codes correct; special-glyph HashAddressed short-names and
leading-dash names restore byte-exact across 4 modes × root+2 snapshots.

Findings + driver disposition:
- [MINOR] a `..`-escaping RelativePath wrote above the target and exited 0;
  [MINOR] a corrupt (non-CSV) but non-empty manifest restored nothing yet exited
  0. Both are fail-loudly/defense-in-depth gaps that **Reconstruct.ps1 shares**
  (not bash regressions). **Driver FIXED both on the bash side** (non-engine,
  trivially-reversible; the traversal guard matters for the "restore a foreign
  backup on a rescue USB" threat model): reconstruct.sh now (a) refuses any row
  whose destination canonicalizes outside `--target-root` (counted unrestored ⇒
  exit 1) and (b) validates the manifest header carries `RelativePath`+`xxH2Hash`
  (a legitimately empty backup still has the header) ⇒ exit 2 on a corrupt file.
  New bats: "refuses a path-traversal RelativePath", "corrupt MANIFEST.csv fails
  loudly" (now **24/24** green, shellcheck clean). **For the human:** the SAME two
  gaps exist in `Reconstruct.ps1` — left unfixed per plan §6 (no unilateral engine
  change); recommend tracking them against the Windows restorer too.
- [NIT] non-blank-DataPath rows are copied without re-hashing (authoritative per
  the contract; matches PS) and [NIT] blank-vs-whitespace DataPath handling
  (engine never emits whitespace-only) — noted, no change.

**bash-v1 is complete and green; awaiting the human's final review + cross-check.**

### HUMAN — Find-DataFileByHash root-level-only fix — 2026-07-03
Verdict: APPROVE — "You can proceed with option a right now." Confirmed the
`MANIFEST.csv` naming convention itself is fine and needs no change: the
requirement (SR-022, root-level-only) was already correct; the defect was the
restore-path scanner re-implementing the skip recursively. Also clarified the
manifest-as-source-of-truth stance: on a standard restore no re-hashing/
extraction-to-verify is wanted — restore-time hashing is legitimate only as
*lookup* on the blank-DataPath recovery path (the hash is the address, not a
check). Consequence recorded for the option-(c) design sketch (manifest-built
recovery index): its "verify-on-hit" re-hash should be a **configurable**
integrity option (like the legacy stability cross-check provision), off by
default — not mandatory as the driver first proposed. Option (c) itself remains
a future, gated candidate — not scheduled.

### DRIVER (Software + Test + Data-integrity hats) — Find-DataFileByHash fix (SR-022/SR-010) — 2026-07-03
Verdict: implemented + validated (human-approved scope, above). One-line-class
fix on the restore surface, test-first:
- **Red first:** new Pester test (TC-058) written before the fix and run against
  the unfixed code — failed with exactly the predicted defect: "Reconstruction
  INCOMPLETE: 1 file(s) could not be restored: sub\MANIFEST.csv".
- **Fix:** `Find-DataFileByHash` (Reconstruct.ps1) now applies the infra-name
  skip only to files directly in each search folder's root (normalized-path
  parent comparison), matching SR-022/AGENTS.md §3 and `reconstruct.sh`. The
  skip is documented in-code as a scan optimization, never a correctness gate
  (matching is by (hash,length)).
- **Registry:** TC-058 added (Verifies SR-022;SR-010;LLR-010, Pass); LLR-010
  detail + TestRefs extended. Stale "deliberate divergence" notes retired in
  AGENTS.md §4, bash/reconstruct.sh header, and restore.bats (both restorers now
  match the contract identically).
Evidence (real output, local): red-first fail pasted above; post-fix
`check.ps1 -Tier Full` → lint PASS · trace **SN=23 SR=33 LLR=32 TC=57,
0 orphans / 0 integrity / 0 status-findings / 1 phase-deferred** · docs PASS ·
arch-map PASS · Pester **53/53** · perf PASS · integration **236 PASS / 0 FAIL /
4 SKIP** → "All steps passed." Linux side re-validated: shellcheck clean,
bats **24/24** (WSL Fedora 40). Note: Reconstruct.ps1 is engine-deployed — the
fix ships in every new backup's kit; existing backups restore correctly by
re-running restore from an updated kit copy if they ever hit the nested-infra
case.

### HUMAN — repo cleanup: legacy artifacts — 2026-07-03
Verdict: APPROVE (all three scopes, via AskUserQuestion): (1) delete the
superseded engine artifacts + pre-history notes; (2) delete BOTH standalone
personal-utility folders (`Auxilary/`, `DatabaseDuplicateDeletion/` — no longer
in use); (3) delete tracked `.idea/` and gitignore it. Context: the human's own
memory of which old scripts were still live was unclear and the leftovers were
creating confusion.

### DRIVER (UX/Docs hat) — repo cleanup executed — 2026-07-03
Deleted (all recoverable from git history — `git log --diff-filter=D --summary`):
- Superseded pre-modularization: `Test-Backup.ps1`, `RunTests.bat`,
  `TestRelated/` (FileBackupTestReset.ps1, Tests.xlsx), `PrepPropertiesFile.ps1`.
- Pre-history notes for the OLD SHA-256/HashTable.csv system: `FullPrompt.txt`
  (the original generation prompt), root + Auxilary `ScratchPad.txt`/`ToDo.txt`,
  `Auxilary/BackupMethodBreakdown.txt`, `Auxilary/BackupTestCases`.
- Personal utilities (human confirmed no longer used): `Auxilary/*.ps1` ×4,
  `DatabaseDuplicateDeletion/*.ps1` ×3.
- `.idea/` (IDE-private; now gitignored).

**Backlog preserved from the deleted root ToDo.txt (Nov 2025)** — the only two
ideas not already realized by the current implementation:
1. *Archive option:* optionally store a backup as `.7z` archive sets (full
   snapshot at a configured interval, diffs between), with a rebuild script per
   folder. (The dated-snapshot model realized the diff/point-in-time half.)
2. *CloneSpy CRC export:* an option to emit a CloneSpy-compatible CRC list per
   backup set.

Docs refreshed: AGENTS.md §7 rewritten as a removal record (§ numbering kept);
README repo-layout block updated to the current tree (adds `bash/`, `scripts/`,
`docs/`; drops deleted entries) and the stale personal-tools note removed;
check.ps1 lint comment updated; `.gitignore` gains `.idea/` and simplifies the
`BuildAlbum/` rule. **NOT deleted (flagged to human):** untracked `BuildAlbum/`
(23 MB personal photos/videos in the working folder — unrecoverable if deleted,
so left in place and kept gitignored; human to move/delete it manually if
stale).

### HUMAN — evaluator launchers (run.cmd / run.sh) — 2026-07-03
Verdict: APPROVE (direction) — make the repo ai-template compatible: ship BOTH
`run.cmd` and `run.sh`, and have them "trigger the standard test run on a
virtual / created run, instead of attempting to run a formal defined backup."
**Reverses two 2026-07-02 kit re-sync decisions** (run.cmd → FileBackup.ps1;
POSIX run.sh not shipped).

### DRIVER (UX/Docs hat) — evaluator launchers rewired — 2026-07-03
Per the kit's evaluator-rung convention (process.md §7: one readable command per
launcher, zero recall required):
- **run.cmd** → `pwsh -NoProfile -File scripts\demo_timeline.ps1`: the
  self-contained demonstration — scratch source tree under `%TEMP%\FileBackupDemo`,
  a create/modify/remove/re-add/no-op timeline through the REAL engine, restore
  of the latest state + every dated snapshot, xxHash128 byte-verification, and a
  narrative TimelineReport.md. No config file; nothing outside temp touched.
  Args pass through (`-Mode HashAddressed -Compress`).
- **run.sh** (new) → `bash tests/bash/verify_restores.sh tests/fixtures`: the
  Linux product surface (the engine is Windows-only) — restores every origin of
  the four committed real-engine fixture backups into a mktemp dir and
  byte-compares each file; friendly tool preflight with install remediation.
  Executable bit set (100755); shellcheck clean.
- README gains a "Run it (no setup)" section documenting both underlying
  commands; repo-layout block lists the launchers; `.gitattributes` pins
  `*.cmd`/`*.bat` to CRLF (LF-only batch can break cmd.exe).
Evidence (real runs): demo_timeline → "**Overall: PASS** — 5 runs, 3 snapshots,
every state restored and byte-compared", exit 0 (Windows). run.sh → "verified
12 origin(s); 0 failing", exit 0 (WSL Fedora 40). check_docs → 44 links,
0 broken.

### DRIVER (System + Test hats, subagent-assisted audits) — frontier truth-up & registry back-fill — 2026-08-21
**Trigger:** human asked whether the frontier of work is properly documented
after the 2026-08-12 commits (ec43711/6b1484c/bf2ccd0/d5f8894). Two independent
audits (an Opus documentation audit + an adversarial frontier review) confirmed
those four commits changed the engine/restore surface and shipped a container
runtime **without touching this blackboard, without gate records, and with new
engine behavior carrying no requirement rows** — under the HIGH decision dial.

**Back-fill performed (registry + code annotations, awaiting human
ratification):**
- New **SR-035** (run-state integrity gate — HomeHub finding F), **SR-036**
  (empty-source delete-all refusal + `AllowEmptySource` — finding G),
  **SR-037** (cross-platform tool discovery — finding 0, Verification=
  Inspection), with **LLR-035..037**.
- **SR-009/LLR-009 extended** to the path-traversal refusal (the first of the
  two 2026-07-03 reviewer MINORs, silently fixed in `Reconstruct.ps1`
  2026-08-12); its sibling — **corrupt non-CSV MANIFEST.csv still restores
  nothing and exits 0 on the PS side** — remains OPEN and is now tracked in
  *Open items* (bash validates the header and exits 2; live divergence).
- New **TC-061..065** pinning the already-shipped `Safety.Tests.ps1` and
  `Coverage.Tests.ps1` tests (state gate ×2, empty source, dependency
  preflight, traversal) + the SR-037 inspection.
- `Safety.Tests.ps1` Describe/It names annotated with SR ids;
  `# Implements:` back-links added in Engine (`Invoke-BackupSet`),
  `Reconstruct.ps1` (restore loop), and `Common.psm1` (tool discovery).
- Current State header updated (2026-08-12 block, revised Non-goals wording,
  corrected interfaces claim); new **"Open items (frontier)"** section minting
  C/D/E/H/I/J, the corrupt-manifest guard, ext-list merge, backup-side
  capacity check, container release-verification (CI runs BuildAndTest only —
  Export/Publish/Pull unexercised), the IF-001 config-contract gap (no JSON
  schema/validation/test; single-set-only mounts), release-checklist staleness,
  interfaces.md boilerplate, and doc drift — each with dependency/blocking
  notes.

**On the remembered "codex" adversarial review:** no artifact, commit, or log
entry named codex exists (`grep -ri codex`, `git log -S/--grep` all empty). The
memory maps to the recorded adversarial passes (2026-07-02 dedup/snapshot —
closed; 2026-07-03 bash-v1 reviewer — one finding still open, the
corrupt-manifest gap above; 2026-08-09 HomeHub cross-check — findings tracked
here).

**For the human:** ratify (or amend) this back-fill plus the unratified
2026-08-12 work — including the `reconstruct.sh` bundling decision that was
implemented without an approval record — and prioritize the Open-items table;
**E** (independent restore witness) is the standing design question.
Evidence of the post-back-fill green is recorded in the Current State header.

### HUMAN — frontier dispositions approved — 2026-08-21
Verdict: APPROVE ("Yes that sounds good, feel free to proceed to fill the
frontier with these decisions") for the driver's per-item review of the Open
items against the queued work and the project vision (data safety is the
product; HomeHub consumes the engine via container/IF-001; restore must never
need a runtime). Approved substance, now recorded in the Open-items table:
- **Two conflicts found and resolved.** (1) Item **I**: pure delegation of
  retention to HomeHub was unsafe — external pruning of a `Snapshot_*` folder
  can delete the only physical copy of bytes other snapshots recover by hash
  from the shared pool. Split: HomeHub owns retention *policy*, FileBackup owns
  the *mechanism* (planned `Prune-Snapshot` verb, WP4, own SR); IF-001 now
  forbids direct snapshot-folder deletion. (2) **Ext-list merge** is not a
  drive-by: it flips existing `.7z` rows "wrong" under
  `Sync-BackupStorageLayout`'s config comparison, exercising the untested
  migration path finding **C** covers — sequenced after C's repro test (WP5).
- **WP1 bundling:** E (manifest witness sidecar: row count + xxHash128 of
  manifest bytes, atomic, per-snapshot, verified by BOTH restorers) +
  corrupt-manifest guard (subsumed by the witness) + D/exit-code table
  (baseline = bash's existing exit 2) + J — one gated pass, one independent
  review, one kit revision instead of four.
- **Rulings:** one BackupSet per container invocation (recorded in IF-001;
  multi-set stays a native-Windows convenience); archive-option storage
  REJECTED into Non-goals; H stays delegated (optional `ExpectedSentinel`
  hardening later); CloneSpy export stays parked.
- **Order:** WP1 restore trust → WP2 config contract → WP3 container
  release-verify + ratchet re-arm → WP4 retention mechanism → WP5 C/ext-list/
  capacity → WP6 docs batch — all after Next-action (a)–(c) ratification.

### DRIVER (UX/Docs hat) — frontier dispositions recorded — 2026-08-21
Open-items table rewritten with per-item dispositions + WP1–WP6 order; IF-001
contract text extended (one-set-per-invocation; no direct snapshot deletion;
retention policy/mechanism split); Non-goals gains the archive-option
rejection. Registry/doc-only change — no engine code touched; WP1's SN/SR
minting still goes through its own G1 when scheduled.

### DRIVER (Test hat) — test-harness fix: Subst free-letter probe — 2026-08-22
The first post-hardening Full-tier attempt failed 32 integration assertions,
all environmental: this machine holds disconnected-but-remembered network
mappings (`X:`/`S:` → MINI-SERV shares). `New-SubstEnv`'s free-letter probe
(`Test-Path "X:\"`) returns **False** for such a letter, so the harness
claimed `X:`, its `subst` lost silently to the remembered mapping, and every
volume-backed write hit the dead share ("user name or password is incorrect").
Fix (tests/Common/VolumeBackend.ps1): the probe now also excludes every
`Get-PSDrive -PSProvider FileSystem` name (which lists disconnected mappings)
before the `Test-Path` check. Test-scaffolding-only change, decided
autonomously per the decision dial; the user's remembered mappings were left
untouched. Evidence: rerun below.

### HUMAN — (a)–(c) ratified; WP1–WP6 grind authorized — 2026-08-22
Verdict: APPROVE. The human directed "spin up opus and sonnet agents as
appropriate to grind through the queue to completion" and confirmed via
explicit prompts: (1) that instruction **counts as ratification of
Next-action (a)–(c)** — G3 sign-off, bash-v1 final-review acceptance, and the
2026-08-12 hardening + container work with its 2026-08-21 registry back-fill
(incl. the `reconstruct.sh` bundling decision) — contingent on the pending
Full tier coming back green; and (2) WP-level gate pauses are handled by
**batch ratification** — agents drive each WP through its gates with driver +
independent-reviewer approvals and pasted evidence, and all human gate
sign-offs are collected in one batch at the end of the queue.
Evidence (real output, 2026-08-22, post-harness-fix): `check.ps1 -Tier Full`
→ PSScriptAnalyzer PASS · trace **SN=24 SR=37 LLR=36 TC=64, 0 orphans /
0 integrity / 0 status-findings / 2 phase-deferred** · Pester unit **65/65** ·
integration **236 PASS / 0 FAIL / 4 SKIP** → "All steps passed." The G3 row in
Gate Sign-offs is marked APPROVE 2026-08-22 accordingly.

### DRIVER (Software + Test Engineer hats) — WP1 restore trust & diagnostics — 2026-08-23

Executed [plans/wp1-restore-trust-plan.md](plans/wp1-restore-trust-plan.md) end
to end under the 2026-08-22 grind authorization (batch ratification). Closes
Open-items rows **E**, **corrupt-manifest guard**, **D + exit-code table**, and
**J**. Ids minted and closed: **SN-025..026, SR-038..041, LLR-038..041,
TC-066..073.**

**What landed, by phase**

- **Registries** (`a6ddc5f`) — SN/SR/LLR/TC rows + the IF-001 contract amendment
  (exit-code table + witness promise; `SR-Refs` now `SR-034;SR-038;SR-039;SR-040`).
  IF-001 stays `v1`/`Experimental` — WP2's config contract is the remaining blocker.
- **Phase A — manifest witness writer** (`ae0bd26`, SR-038 / TC-066, TC-067).
  `Write-Manifest` now stamps `MANIFEST.csv.meta` (`Version`, `Rows`, `Bytes`,
  `XxH128`, `Written`; UTF-8 no BOM, LF) beside every manifest it writes,
  published by `Move-Item -Force` (atomic rename). One writer, so backup root,
  staging, dated snapshots, the source hash cache and every rewrite are covered
  and cannot drift. `Get-ManifestWitnessPath` / `Write-ManifestWitness` /
  `Test-ManifestWitness` live in **Common** (Reconstruct may call only Common).
  The witness joins `Test-IsInfrastructureFile`'s **root-level** allowlist only —
  a nested `sub\MANIFEST.csv.meta` is still user data (B6). It is deliberately
  **not** a kit artifact: copying it into snapshots would overwrite each
  snapshot's own witness with the backup root's. TC-067 pins both halves.
- **Phases B+C — exit-code contract + witness verification** (`3ee8f5b`,
  SR-039/SR-040 / TC-068..072). One documented table in both restorers: **0**
  complete · **1** incomplete/content · **2** usage or precondition · **3**
  witness verification failed · **4** incomplete/host (retriable), precedence
  **2 > 3 > 4 > 1**. `Find-DataFileByHash` / `find_by_hash` now return a distinct
  cause (`ContentMissing`, `DependencyMissing`, `StorageUnreadable`,
  `CandidateError`) instead of collapsing four failures into one warning, and the
  summary names the count per class. Both restorers check the CSV header shape
  and, when a witness is present, `Bytes`/`Rows`/`XxH128` before writing any
  manifest row. A missing sidecar warns `UNVERIFIED` and continues so **legacy
  backups still restore**; `-RequireWitness` / `--require-witness` makes absence
  an abort. Delivery is opt-in: `Reconstruct.ps1` still **throws** for in-process
  callers and only exits with a code under `-ExitCode`, which `RECONSTRUCT.bat`
  now passes — so the six `Should -Throw` assertions and the harness are untouched.
- **Phase D — move-loop failure aggregation** (`60496b3`, SR-041 / TC-073).
  `Move-RemovedFilesToStaging` and `Save-SupersededData` wrap each move in
  try/catch, log an ERROR naming file and cause, count it, continue, and emit a
  per-loop summary; both take `[ref]$OverallSuccess`. `Invoke-BackupSet` passes
  the ref and does **not** early-return, so step 13 still finalizes or discards
  the staging folder. Before this, one failed `Move-Item` escaped the pipeline,
  hid every other failure, skipped snapshot finalization and left `Temp` behind —
  so the *next* run aborted on the SR-017 stale-staging guard (finding J).
- **Phase E — kit, fixtures, docs.** `Invoke-Container.ps1`'s smoke assertion
  six → seven artifacts; `tests/fixtures/bash-restore/**` regenerated so every
  fixture manifest carries a matching witness (the hand-built manifest in
  `fail_loudly.bats` stays witness-less on purpose, pinning the legacy path);
  README gained "Restore exit codes" (normative) plus witness prose in
  "3. Restore", "Restore on Linux", "How it works" and "Manifest columns";
  AGENTS.md §2/§3/§4 gained the witness invariant, the exit-code invariant and
  the deliberate crash-window note; `bash-variant-plan.md`'s contract table
  gained both rows; generated blocks regenerated.

**Evidence (real output, 2026-08-23)**

`pwsh scripts/check.ps1 -Tier Full`:

```
[PASS] PSScriptAnalyzer
==== Traceability (trace.py --strict) ====
Traceability: SN=26 SR=41 LLR=40 TC=72 orphans=0 integrity=0 status-findings=0 phase-deferred=2. Report -> docs\test\report.md
[PASS] Traceability (trace.py --strict)
[PASS] Doc navigability (check_docs.py)
[PASS] Architecture map freshness
Tests Passed: 83, Failed: 0, Skipped: 0, Inconclusive: 0, NotRun: 0
[PASS] Pester unit
[PASS] Performance budgets (check_perf.py)
[PASS] Integration sweep (Full)
All steps passed.
```

Integration sweep detail: **PASS: 236 · FAIL: 0 · SKIP: 4** (G8 SKIPs under Subst).

G3 ratchet, `python scripts/trace.py --strict --require-verified --phase core,bash-v1`:

```
Traceability: SN=26 SR=41 LLR=40 TC=72 orphans=0 integrity=0 status-findings=0 phase-deferred=2. Report -> docs\test\report.md
```

Real Linux (WSL `podman-machine-default`, Fedora 40) — `shellcheck bash/reconstruct.sh`
clean, `bats tests/bash` **45/45 ok** (was 24; +11 `witness.bats`, +10 `exit_codes.bats`):

```
ok 43 --require-witness turns a missing witness into a refusal (SR-039)
ok 44 a witness from the FUTURE verifies the known fields and warns (SR-039)
ok 45 each SNAPSHOT carries its OWN witness, not the backup root's (SR-038)
```

**Decisions taken (per plan §6, flagged for batch ratification)**

1. `-ExitCode` switch for PowerShell exit-code delivery; `throw` stays the default.
2. Engine-side witness verification before mutating a backup deferred to WP5's
   `-VerifyStorage`.
3. `Rows` counted as `Import-Csv` / `parse_manifest` count them; `XxH128` stays
   authoritative, so a counting divergence can never alone condemn a good manifest.
4. SN-025 in the edge-case table, SN-026 in core needs.

**Deviations from the plan, and why**

- **Phases B and C landed in one commit** (`3ee8f5b`). They rewrite the same
  functions in both restorers (`Read-RawManifest` / `main()`'s guard region and
  the shared exit path); splitting them would have required an intermediate
  state that is neither meaningful nor independently reviewable. Both phases'
  tests are present and green.
- **A third manifest-tampering test site** beyond the two the plan's §5 table
  named: `Coverage.Tests.ps1`'s SR-023 capacity test also rewrites `MANIFEST.csv`
  and now re-stamps the witness. `G3-Reconstruction.ps1`'s hash-fallback blanking
  was a fourth; `tests/Run-All.ps1` now imports Common so suites can re-stamp.
- **A "replaced by garbage" manifest exits 2, not 3.** The plan's normative table
  (§2) and its §5 regression row both put an unrecognizable header at code 2 (the
  pre-existing guard `fail_loudly.bats` pins), while TC-068/TC-069's summary prose
  loosely said "witness failure" for all three damage kinds. Implemented per the
  normative table (precedence 2 > 3) and **truthed-up the two TC Expected cells**
  to say so. No design change.
- **A real bug found while implementing bash Phase B:** the first cut set the
  recovery cause in shell globals, but `find_by_hash` is called through command
  substitution — a subshell — so the cause never reached the caller and exit 4
  could never fire. The cause now travels in the function's **output**
  (`<cause>\037<detail>\037<path>`). Caught by TC-071, which is the point of it.

**Known asymmetry for the reviewer.** On a witness failure the bash restorer
writes *nothing at all* (its check sits before `mkdir -p` on the target), while
`Reconstruct.ps1` has already created the target directory and `RECONSTRUCT.log`
by the time `Read-RawManifest` runs — the placement the plan specifies for each.
Neither writes a manifest **row**, which is the contract ("no file is written to
the target" = no restored data), and both TCs assert exactly that. Worth a
reviewer ruling on whether to align them.

**Next action (awaiting human):** independent review of the WP1 data-integrity
surface (witness write/verify path, exit-code classification, move-loop
aggregation), then batch ratification alongside the other WPs.

### DRIVER (Software + Test Engineer hats) — WP2 config contract — 2026-08-23

Executed [plans/wp2-config-contract-plan.md](plans/wp2-config-contract-plan.md)
end to end under the 2026-08-22 grind authorization (batch ratification).
Closes Open-items rows **config contract** and **multi-set mounts**. Ids
minted and closed: **SN-027, SR-042..043, LLR-042..043, TC-074..078**
(sequenced after WP1's SN-025..026/SR-038..041/LLR-038..041/TC-066..073,
reusing WP1's "2 = usage/precondition" exit-code meaning).

**What landed, by phase**

- **Phase A — registries** (`444ee8f`) — SN-027 (edge-case: a wrong config
  refuses to start, names the offending key, never guesses a default), SR-042
  (versioned closed JSON schema) / SR-043 (`-ExitCode` distinguishes a config
  failure from a set failure), LLR-042/043, TC-074..078; IF-001's `Contract`
  cell gained the schema summary and `SR-Refs` gained `SR-042;SR-043` — `Version`
  stays `v1` (never left `Experimental`) and `Stability` stays `Experimental`
  (a separate decision for batch ratification, per the work order).
- **Phase B — the loader** (`10b58fe`, SR-042/LLR-042). New region in
  `Modules/FileBackup.Engine.psm1`: `$script:ConfigSchemaVersion = 1`;
  `Import-BackupConfiguration` (exported) dispatches on extension. JSON:
  parses, checks `ConfigVersion` first — missing / non-integer / `< 1` /
  above `$script:ConfigSchemaVersion` — all hard errors naming `$.ConfigVersion`,
  in document order before anything else runs; then `Assert-NoUnknownConfigKey`
  (private) recursively rejects any key outside the schema at the top level,
  `Tools`, `Secrets`, and every `BackupSets[]` entry, naming the JSON path, and
  explicitly bans `Secrets.Credential`; then `Test-BackupConfigurationShape`
  (private, shared with CLIXML) with `-StrictTypes` — a quoted `"false"` for
  `CompressEnabled`/`PreserveFolderTree` is rejected as the wrong JSON type,
  never coerced by `[bool]`, and a non-integer `Secrets.SmtpPort` is rejected —
  while the three pre-existing message wordings (`*at least one BackupSets
  entry*`, `*must define a non-empty*`, `*invalid HashRecalcFreq*`) are emitted
  **verbatim** by the same shared function. `Resolve-BackupSetDefaults`
  (private) materializes `SourceStatePath=SourcePath`,
  `AllowEmptySource=$false`, and upper-cased `HashRecalcFreq`. CLIXML runs only
  the shared shape check (no version, no closed schema, no credential ban) —
  unversioned legacy. A JSON config with >1 `BackupSets` logs a `WARN` (IF-001)
  instead of failing. 13 new Pester cases (TC-074/075) call the function
  directly, so this phase touched no other file's behavior.
- **Phase C — wire the entry point** (`a6df81e`, SR-043/LLR-043).
  `FileBackup.ps1:100-125`'s bare `ConvertFrom-Json`/`Import-Clixml` dispatch
  and inline per-set validation loop collapsed to one
  `Import-BackupConfiguration` call. The global logger now builds *before* the
  config load (it only needs `$ConfigPath`/`$GlobalLogPath`) so a load failure
  can still be logged. New `[switch]$ExitCode` + `Exit-ConfigFailure`: under
  `-ExitCode` a load failure logs to stderr + the global log and `exit 2`
  (SR-043's usage/precondition class); without it, it rethrows — unchanged
  in-process behavior. The trailing `if (-not $overallSuccess) { exit 1 }` is
  untouched. **Regression fix required to keep this phase green** (flagged in
  the plan's §5 risk table, landed here rather than deferred to Phase D as the
  table's own bullet ordering implied, because the moment the entry point is
  wired the two inline JSON fixtures in `Engine.Tests.ps1`'s SR-018 block break
  the instant `ConfigVersion` is required): added `ConfigVersion` to the valid
  fixture; the pre-existing `'{}'` case now asserts the ConfigVersion-missing
  message (checked first, in document order) rather than the empty-BackupSets
  message, and a new case pins the old `'{}'` → `"at least one BackupSets
  entry"` wording against a `'{"ConfigVersion":1}'` fixture so that check
  stays covered.
- **Phase D — versionize the artifacts, publish the schema** (`136b60a`,
  SR-042/LLR-042). `"ConfigVersion": 1` added to
  `container/FileBackup.example.json`, the README JSON block, and
  `Invoke-Container.ps1`'s `New-SmokeConfiguration`. Published
  `container/FileBackup.schema.json` (JSON Schema draft-07:
  `additionalProperties: false` at every level, `const: 1` for `ConfigVersion`,
  `enum` for `HashRecalcFreq`; `Secrets.Credential` is simply absent from the
  allowed key set, so the schema rejects it the same way the hand-rolled
  validator does) as documentation — the runtime authority stays the
  PowerShell validator, per the plan's decision #5. TC-076
  (`Coverage.Tests.ps1`): loads the checked-in example, retargets *only* its
  path fields and `Tools.SevenZipPath` (to the platform's real 7-Zip), asserts
  a recursive keys-only diff against the checked-in file so the example cannot
  silently drift from what it claims to demonstrate, then drives a real
  compressed `FileBackup.ps1` run and a byte-exact `RECONSTRUCT.ps1` restore.
  TC-077: `Test-Json -SchemaFile` against the same accept/reject fixture corpus
  as TC-074/075, cross-checked against `Import-BackupConfiguration` so the
  published schema and the runtime validator cannot drift apart; also pins
  `ConfigVersion=1` across the example, the extracted README block, and the
  smoke config.
- **Phase E — entrypoint, help, README** (`6097189`, SR-043/LLR-043).
  `container/entrypoint.sh` passes `-ExitCode` (shellcheck-clean, verified in
  WSL `podman-machine-default`). `FileBackup.ps1`'s `.PARAMETER ConfigPath` now
  documents JSON-as-canonical-versioned vs. CLIXML-as-legacy with a worked
  example of each, the IF-001 multi-set warning, and a new `.PARAMETER
  ExitCode`; `.NOTES` gained the SR-043 status-code table. (The `-ExitCode`
  switch itself and `Exit-ConfigFailure` were already added in Phase C, since
  both needed to land in the same commit as the logger-ordering change they
  depend on — Phase E's job here was documentation, not code.) README's
  "Config format" section rewritten to state the same JSON-canonical/
  CLIXML-legacy split, a `ConfigVersion` field row, the multi-set warning, and
  the `-ExitCode` status-code summary (the now-redundant standalone "multiple
  BackupSets" sentence removed). TC-078 (`Coverage.Tests.ps1`, 6 cases):
  child-process `-ExitCode` returns 2 (schema-violating config, no backup
  artifacts created) / 1 (one set fails) / 0 (clean run); the same three
  invocations without `-ExitCode` return the pre-WP2 codes (1/1/0 — a bad
  config is still a non-zero exit, just not specifically 2); an in-process call
  still throws for a bad config; a two-set JSON config logs the IF-001 warning
  naming the count while still processing both sets.
- **Phase F — close (this entry).** Flipped SR-042/043 → `Verified`,
  LLR-042/043 → `Verified` (matching the convention the existing LLR rows use,
  not the work order's literal "Implemented" wording), TC-074..078 → `Pass`,
  via targeted line-level edits (a full CSV-writer rewrite was tried first and
  rejected — it silently reformatted every unrelated row's quoting under
  `QUOTE_MINIMAL`, which would have buried the real diff; reverted and redone
  as anchored regex substitutions touching only the five target rows — verified
  by `git diff` showing exactly those five one-line changes per file).

**Evidence (real output, 2026-08-23)**

`pwsh scripts/check.ps1 -Tier Full`:

```
==== PSScriptAnalyzer ====
[PASS] PSScriptAnalyzer

==== Traceability (trace.py --strict) ====
Traceability: SN=27 SR=43 LLR=42 TC=77 orphans=0 integrity=0 status-findings=0 phase-deferred=2.
[PASS] Traceability (trace.py --strict)

==== Doc navigability (check_docs.py) ====
check_docs: WARN - orphan doc (no path from an entry root): docs/plans/wp2-config-contract-plan.md
check_docs: OK - 15 doc(s), 54 intra-repo link(s), 0 broken (1 orphan warning(s)).
[PASS] Doc navigability (check_docs.py)

==== Architecture map freshness ====
[OK]  Generated regions current in C:\Projects\FileBackup\docs\architecture.md
[OK]  Generated regions current in C:\Projects\FileBackup\AGENTS.md
[PASS] Architecture map freshness

==== Pester unit ====
Tests Passed: 106, Failed: 0, Skipped: 0, Inconclusive: 0, NotRun: 0
[PASS] Pester unit

==== Performance budgets (check_perf.py) ====
check_perf: OK - no performance budgets to compare (process.md §9)
[PASS] Performance budgets (check_perf.py)

==== Integration sweep (Full) ====
  PASS: 236
  FAIL: 0
  SKIP: 4
[PASS] Integration sweep (Full)

================ check.ps1 (tier Full, gate G3) ================
All steps passed.
```

G3 ratchet, `python scripts/trace.py --strict --require-verified --phase core,bash-v1`:

```
Traceability: SN=27 SR=43 LLR=42 TC=77 orphans=0 integrity=0 status-findings=0 phase-deferred=2. Report -> docs\test\report.md
```

The `docs/plans/wp2-config-contract-plan.md` orphan-doc WARN above is
resolved by this entry's own link to it, the same way WP1's plan file avoided
the same WARN — informational, not a `check.ps1` failure either way.

**Decisions taken (per plan §6, flagged for batch ratification)**

1. Missing `ConfigVersion` is fatal (not assumed `1`).
2. Unknown keys are rejected, not warn-and-ignore.
3. A JSON config with >1 `BackupSets` warns (IF-001), does not fail.
4. IF-001 `Version` stays `v1`; `Stability` stays `Experimental` pending WP1
   also being Verified (**not** flipped by this entry — separate decision).
5. Runtime validation is hand-rolled (`Import-BackupConfiguration`); the
   published `container/FileBackup.schema.json` is documentation, with TC-077
   pinning their equivalence.

**Deviations from the plan, and why**

- **The two `Engine.Tests.ps1` JSON-fixture updates moved from Phase D to
  Phase C.** The plan's ordered implementation list (§4) put them in Phase D
  alongside the other artifact versionizing, but its own §5 regression-risk
  table says the fixtures "become invalid the moment `ConfigVersion` is
  required" — which is Phase C, not D. Landing the fix in Phase C (commit
  `a6df81e`) keeps that phase's commit genuinely green rather than leaving a
  known-red window between C and D.
- **`-ExitCode` and `Exit-ConfigFailure` landed in Phase C, not E.** The plan's
  §4 phase list assigns `-ExitCode` to Phase E, but §2's loader design ties the
  switch's failure path directly to the logger-ordering change Phase C already
  had to make (the logger must exist before the config load so a load failure
  can be logged) — splitting them would have meant either a Phase C without a
  working failure path or a Phase E that silently depended on Phase C internals
  it hadn't announced. Phase E's actual work was the `.PARAMETER`/`.NOTES`/
  README documentation, TC-078, and the `entrypoint.sh` flag — all still
  sequenced and committed as planned.
- **TC-076/TC-077 placed in `Coverage.Tests.ps1`, not `Engine.Tests.ps1`.** The
  plan names both TCs but not a file; `Coverage.Tests.ps1` already hosts every
  other integration-style test that drives a real `FileBackup.ps1` run and
  byte-compares a restore (SR-004/012/013/026/028 etc.), so the example-config
  and schema-parity tests joined that file rather than `Engine.Tests.ps1`
  (which stayed pure-function/direct-loader tests per Phase B's own framing).

**Known items for the reviewer.**
- `Assert-NoUnknownConfigKey`'s per-set path uses a literal `[?]` placeholder
  in one `Test-BackupConfigurationShape` message (`$.BackupSets[?].CompressEnabled`)
  rather than the failing set's real index, because that check runs after the
  loop variable no longer carries its array position — the *key-name* messages
  from `Assert-NoUnknownConfigKey` do carry the real `[i]` index; only the
  *type* message for `CompressEnabled`/`PreserveFolderTree` does not. Minor,
  cosmetic, TC-075 asserts on the substring `*CompressEnabled*JSON boolean*`
  rather than the exact set index.
- The example-config integration test (TC-076) skips (via `Set-ItResult
  -Skipped`) rather than fails when no 7-Zip is found at the platform default
  path, since the checked-in example has `CompressEnabled: true` and this
  environment happens to have 7-Zip installed — worth confirming CI's image
  also has 7-Zip on the default path so this doesn't silently skip there too.

**Next action (awaiting human):** independent review of the WP2 config-loading
surface (schema validator correctness, the closed-schema/credential-ban logic,
the exit-code wiring), then batch ratification alongside WP1 and the other WPs.

---

### INDEPENDENT REVIEWER (Opus subagent) — WP1 restore trust & diagnostics — 2026-08-22

**Verdict: APPROVE-WITH-MINORS.** Read-only pass over the committed WP1 surface
(`a6ddc5f..47e2f93`): witness writer, exit-code taxonomy, both restorers'
verification, move-loop aggregation, registries. No data-integrity defect found;
the findings below were dispositioned by the driver and landed the next day.

### DRIVER (Software + Test Engineer hats) — WP1 review fixes — 2026-08-23

Landed the accepted findings from the 2026-08-22 review. Behavior changes are
confined to the restore path and the witness verifier; the backup pipeline is
untouched.

**What landed, by finding**

- **Top-level error routing in `Reconstruct.ps1` (MEDIUM).** An unclassified
  terminating error — e.g. `New-Item` throwing because a FILE occupies the
  target path — escaped and left the process exit status at **1**, the code
  README's table reserves for *content unrecoverable / data loss*, while bash
  returned **2** for the same cause. A script-level `trap` now routes any
  failure the script did not classify to the **precondition** class (exit 2
  under `-ExitCode`; rethrow otherwise, so in-process callers still see the
  original error), and the target-directory / log creation route their own
  failures explicitly through the same class. PS and bash now both return 2 for
  target-is-a-file. Pinned by a new case in TC-070's Describe and its bats twin
  in `exit_codes.bats` (bash already returned 2; it is pinned now).
- **Verification hoisted above mutation (asymmetry ruling — preferred fix).**
  `Read-RawManifest`'s header-shape + witness checks now run **before** the
  target folder and `RECONSTRUCT.log` are created, matching `reconstruct.sh`
  exactly. On any exit-2/exit-3 refusal the PS restorer writes **nothing** into
  the target — not a row, not a log — so README's "no file is written to the
  target" is now literally true. Pre-target log lines are buffered
  (`Add-ReconstructLog`) and flushed once the log exists; refusals go to the
  console/stderr and the thrown error. TC-068/TC-070 now assert *nothing* is
  written (no folder created where it did not exist; no `RECONSTRUCT.log`
  dropped into a folder the operator already had).
- **SR-039 registry truth-up (MEDIUM).** AcceptanceCriteria now states what the
  code does: a replaced/garbage (unrecognizable-header) manifest aborts with the
  **precondition** code 2 (precedence 2 > 3), truncated/byte-edited manifests
  with the witness code 3; the "nothing written into the target" claim is kept
  and is now literally true. The Rationale's false distinction ("a *legacy*
  garbage manifest fails the header check") is dropped — **all**
  unrecognizable-header manifests fail the header check first, whatever their
  provenance; the digest catches damage that preserves the header shape.
- **`MANIFEST.csv.meta.tmp` added to the infrastructure allowlist.** A crash
  between `WriteAllText` and `Move-Item` leaves the witness staging file behind;
  it must not be backed up as user data nor warned about as an orphan. Root-level
  only, as ever (B6). Noted in LLR-038's Detail.
- **Rows-only mismatch demoted** (honors plan §6 decision 3 — *the digest is
  authoritative*). In `Test-ManifestWitness` and `verify_manifest_witness`, when
  `Bytes` and `XxH128` both match but `Rows` disagrees, the verdict is
  **Verified with a warning** (counting-semantics divergence) instead of an
  abort: the manifest is byte-identical to the one that was witnessed, so the
  *count* is what is wrong, not the index. Order stays Bytes → Rows → XxH128;
  a Bytes or digest mismatch still aborts, and a Rows disagreement with **no
  digest to defer to** still aborts. New unit case each side.
- **Perf: `Write-Manifest` no longer re-reads the manifest** with `Import-Csv`
  just to count rows — it passes the record count it already holds through
  `Write-ManifestWitness -RowCount`. A standalone re-stamp (tests tampering on
  purpose) omits it and the file is counted as before. TC-066's `Rows=0`
  empty-set case still passes unchanged.
- **Vacuous assertion fixed** (`Coverage.Tests.ps1`, TC-067). `$rootDigest =
  (Test-ManifestWitness …).Path` grabbed a *path*, so `Should -Not
  -BeNullOrEmpty` could never fail. It now reads the sidecar's real `XxH128`
  value, asserts it equals the backup root manifest's digest, and the
  snapshot-vs-root inequality is compared against that digest — the assertion it
  always meant to make.

**Accepted as-is (deliberately NOT changed):** the `Exit-Reconstruct`
unapproved-verb nit; `MANIFEST.csv` remaining a non-atomic `Export-Csv` (the
stale-witness crash window fails loud in the safe direction — AGENTS.md §4).
The reviewer's clarifying sentence was added wherever "atomic rename" is
claimed (AGENTS.md §3 + §4, `Write-ManifestWitness`'s `.NOTES`, README's
manifest section): **the atomic rename publishes the WITNESS, not
`MANIFEST.csv` itself.**

**Evidence (all genuinely run, 2026-08-23)**

```
Invoke-Pester tests\Unit\Common.Tests.ps1    -> Tests Passed: 21, Failed: 0
Invoke-Pester tests\Unit\Coverage.Tests.ps1  -> Tests Passed: 47, Failed: 0
pwsh scripts/gen_arch_map.ps1                -> [OK] Generated regions already current (x2)
python scripts/trace.py --strict --require-verified --phase core,bash-v1
  -> Traceability: SN=27 SR=43 LLR=42 TC=77 orphans=0 integrity=0
     status-findings=0 phase-deferred=2
pwsh scripts/check.ps1 -Tier Full
  -> [PASS] PSScriptAnalyzer / Traceability / Doc navigability / Architecture map
     freshness; Pester unit Tests Passed: 108, Failed: 0; [PASS] Performance
     budgets; Integration sweep PASS: 236  FAIL: 0  SKIP: 4
  -> "================ check.ps1 (tier Full, gate G3) ================
      All steps passed."
wsl bash -lc "bats tests/bash"  -> 1..48, all ok (45 before; +3 new cases)
wsl bash -lc "shellcheck bash/reconstruct.sh" -> clean
```

**Deviations from the work order (small, deliberate).**
- **SR-039's *Requirement* cell was truthed up too**, not only Acceptance and
  Rationale: the demoted rows-only mismatch and the before-any-mutation ordering
  would otherwise have left the normative sentence false. Same for LLR-039 /
  LLR-040's Detail cells.
- **The top-level catch is a script-scope `trap`, not a `try` wrapping the
  script body** — a `try` would have meant re-indenting ~400 lines of restore
  logic for no behavioral difference. `Exit-Reconstruct` sets a `$classified`
  flag so the trap re-throws our own classified failures verbatim (the six
  `Should -Throw` wordings are untouched).
- **AGENTS.md §6's automated totals were stale** (83 Pester unit / 45 bats,
  written before WP2 landed its tests). Corrected to the measured **108 Pester /
  48 bats** rather than only adding this change's +2/+3.

**Next action (awaiting human):** batch ratification of WP1 (implementation +
review + these fixes) alongside WP2; then the WP3 container/release pass.

### INDEPENDENT REVIEWER (Opus subagent) — WP2 config contract — 2026-08-22

**Verdict: CHANGES-REQUESTED.** Read-only pass over the committed WP2 surface
(`444ee8f..ba1ee48`): the loader, the entry point, the published schema, the
fixtures and the registries. The blocking finding is a **data-loss** one, with a
reproduction:

- **HIGH — only two booleans were type-checked.** `Test-BackupConfigurationShape`
  applied its strict-type rule to `CompressEnabled`/`PreserveFolderTree` only, so
  `"AllowEmptySource": "false"` — a JSON *string* — sailed through the closed-schema
  check and reached `Resolve-BackupSetDefaults`, where `[bool]'false'` is `$true` in
  PowerShell. The reviewer ran it: the delete-all refusal (SR-036) was **disarmed by
  a quoting mistake**, the run wiped the backup root and exited **0**. Same class:
  `"SourcePath": ["x","y"]` became the literal path `x y` via `[string]`.
- **HIGH — one corpus, seven schema↔validator divergences.** TC-077's accepted /
  rejected fixture lists were a hand copy of TC-074/075's, and schema and validator
  disagreed on the six type cases above, on a bare single-set object (the plan says
  accepted-and-wrapped; the schema said array-only) and on `ConfigVersion: 1.0`.
- **MEDIUM — a missing config file exited 1, not 2.** The `Test-Path` existence check
  sat *outside* the try that maps config failures — telling NagLight to retry forever
  on the likeliest container misconfiguration of all.
- **MEDIUM — a refused config truncated the previous run's global log.** Logger
  creation had been moved *before* validation, and `New-Logger` truncates
  (`New-Item -Force`), falsifying TC-075's "no artifact is created by a refused run".
- **MINORS** — TC-074's `Add-Member ConfigVersion` escape hatch defeated the very
  drift the fixture exists to catch; TC-076's 7-Zip skip guard ran *before* the cheap
  keys-only contract check (and CI's `unit` job had no 7-Zip precondition); a literal
  `$.BackupSets[?]` in the message instead of the real index; AGENTS.md's test counts;
  no explicit numeric-range guard on `ConfigVersion`; `container/entrypoint.sh` missing
  from CI's shellcheck list; `Test-Json -Path` needs pwsh 7.4, above the stated floor.

### DRIVER (Software + Test Engineer hats) — WP2 review fixes — 2026-08-23

Landed every accepted finding above. The behavior changes are confined to
configuration loading and the entry point's failure path; the backup pipeline,
the restore path and the CLIXML branch are untouched.

**What landed, by finding**

- **Every schema value is type-checked now (HIGH).** `Test-BackupConfigurationShape
  -StrictTypes` validates each value against its JSON type through a new
  `Test-ConfigValueJsonType` (+ `Test-IsJsonNumber`, `Get-ConfigValueJsonTypeName`):
  JSON strings for `Name`/`SourcePath`/`BackupPath`/`ChangePath`/`HashRecalcFreq`/
  `SourceStatePath`/`Tools.*`/the `Secrets` strings, JSON booleans for
  `CompressEnabled`/`PreserveFolderTree`/**`AllowEmptySource`**, a JSON integer for
  `Secrets.SmtpPort`, and the container types of `BackupSets`/`Tools`/`Secrets`. No
  coercion can run before the type is known, so the reviewer's exploit is dead at the
  door (re-run below). Fixtures added for AllowEmptySource-string, SourcePath-array,
  Name-number, SourceStatePath-number, Tools.SevenZipPath-number and
  HashRecalcFreq-array (`[string]@('A')` is `'A'`, so the array used to pass the enum
  check as well).
- **ONE shared fixture corpus (HIGH).** New `tests/Common/ConfigFixtures.ps1` holds
  7 accepted + 27 rejected fixtures with their expected message; TC-074, TC-075 **and**
  TC-077 all drive it via Pester `-ForEach`, so a divergence can no longer hide in a
  hand copy and a new defect is written down once. Schema alignment: `BackupSets` is
  now `anyOf [array-of-set, set]` (the bare single object the plan promised and the
  loader always wrapped), and `ConfigVersion`'s `const: 1` is documented as accepting
  an integral-valued number — JSON has one number type, so `1.0` **is** `1`, for the
  schema (verified: `Test-Json` returns True) and the validator alike; `1.5`, `0`,
  `"1"` and anything above 1 are refused by both.
- **A missing config file exits 2 (MEDIUM).** The existence check routes through
  `Exit-ConfigFailure` like every other config failure, so it exits 2 under `-ExitCode`
  and still *throws* without it (the harness and `Engine.Tests.ps1` rely on the throw).
  An unsupported extension does the same.
- **A refused run creates nothing (MEDIUM).** Log-*file* creation is deferred until
  after `Import-BackupConfiguration` succeeds; the config-time messages (the multi-set
  `WARN`) are buffered and flushed once the log exists — the same pattern
  `Reconstruct.ps1` uses for its pre-target lines. `Exit-ConfigFailure` writes to
  stderr and *appends* to the global log only when that file already exists, so the
  previous run's log is never truncated and no log directory is created. TC-075's
  registry claim is now true, and TC-078 asserts both halves.
- **Minors.** TC-074's `Add-Member ConfigVersion` escape hatch is gone (the example is
  loaded verbatim from disk); TC-076's cheap keys-only diff now runs **before** the
  7-Zip skip guard and CI's `unit` job asserts 7-Zip is present (mirroring
  `integration-subst`); messages name `$.BackupSets[<real index>]`; `ConfigVersion` is
  range-checked *before* the `[int]` cast (an out-of-Int64 version is refused as an
  unsupported version, not by fractional-representation luck); `container/entrypoint.sh`
  joined CI's shellcheck list (clean); `Test-Json` is called with `-Json`/`-Schema`
  **strings** because `-Path`/`-SchemaFile` need pwsh 7.4 and AGENTS.md's floor is
  PowerShell 7+; AGENTS.md §6's totals corrected to the measured counts.

**Evidence (all genuinely run, 2026-08-23)**

```
# The reviewer's AllowEmptySource repro, re-run against the fixed loader:
run 1 exit=0  backup files=10
  stderr: FileBackup: Config '...\config.json' is invalid:
          $.BackupSets[0].AllowEmptySource - must be a JSON boolean,
          not string ('false') (expected a JSON boolean).
run 2 exit=2 (expect 2)
backup still holds keepme.txt: True
previous log preserved: True

Invoke-Pester tests\Unit           -> Tests Passed: 172, Failed: 0   (was 108)
python scripts/trace.py --strict --require-verified --phase core,bash-v1
  -> Traceability: SN=27 SR=43 LLR=42 TC=77 orphans=0 integrity=0
     status-findings=0 phase-deferred=2
pwsh scripts/gen_arch_map.ps1  -> Updated generated regions in docs\architecture.md
                                  Updated generated regions in AGENTS.md
wsl shellcheck -x bash/reconstruct.sh container/entrypoint.sh
    tests/bash/helpers.bash tests/bash/verify_restores.sh   -> SHELLCHECK-CLEAN
wsl bats tests/bash/  -> ok 48 (1..48, all ok)
pwsh scripts/check.ps1 -Tier Full  (exit 0)
  -> "  PASS: 236   FAIL: 0   SKIP: 4"          (SKIP = G8 RealVolume x4 modes)
     "[PASS] Integration sweep (Full)"
     "================ check.ps1 (tier Full, gate G3) ================
      All steps passed." 
```

**Deviations from the work order (small, deliberate).**
- **The type checker is three module-private helpers, not an inline block.**
  `Test-ConfigValueJsonType` / `Test-IsJsonNumber` / `Get-ConfigValueJsonTypeName` are
  exported to nobody but appear in the generated module map (regenerated). The integral
  test avoids both `[math]::Floor` (ambiguous overload for the `BigInteger` a huge JSON
  number parses to) and culture-dependent string formatting.
- **`Secrets.Credential` in JSON keeps its own named error** rather than folding into
  the generic unknown-key message — it is the one key with a real remediation
  ("use CLIXML, or `-NoMail`").
- **SR-042/SR-043 stay `Verified`** (they were flipped in WP2 phase F): the new
  fixtures land green in the same commit, so there is no window where the claim is
  unbacked. SR-042/043's Requirement and AcceptanceCriteria cells were truthed up to
  state the full type rule, the missing-file case and the no-artifacts guarantee;
  LLR-042/043's Detail and TC-074..078's Parameters/Expected likewise.

**Next action (awaiting human):** batch ratification of WP1 **and WP2**
(implementation + independent review + these fixes); then the WP3
container/release pass.

### INDEPENDENT REVIEWER — WP1 re-verification — 2026-08-22
Verdict: **APPROVE** (upgraded from APPROVE-WITH-MINORS). All seven findings
re-verified as genuinely closed against a pristine export of `84674e3`:
unclassified errors route to exit 2 without swallowing the preserved throw
wordings (probed with a locked-manifest error: child exit 2, in-process still
throws the original message); SR-039/LLR-038..040 cells match the
implementation (trace integrity 0); verification is hoisted with the log
buffer flushing correctly (refusals leave a pre-existing target byte-empty of
new files); `.meta.tmp` allowlisted root-level-only (B6 intact all four
combinations); Rows-only mismatch defers to the digest in BOTH restorers
(doctored `Rows=42` restores with a warning; rows mismatch with no digest
still exits 3); `$Records.Count` edge cases hold (null/empty/single/list);
TC-067 compares real digests. Evidence (pristine export): unit 108/108,
integration 236/0/4, bats 48/48, shellcheck clean, trace 0/0/0. One optional
wording tighten (the late capacity/7-Zip code-2 preflights run after
target+log creation, identically in both restorers) applied by the driver in
`Reconstruct.ps1` `.NOTES` and AGENTS.md §3 in the same commit as this entry.

### DRIVER (Software + Test Engineer hats) — WP3 container release-verify + smoke depth — 2026-08-23
Executed [docs/plans/wp3-container-release-plan.md](plans/wp3-container-release-plan.md) §5 steps 1-4 and 7-8
(steps 5-6, the push and post-CI status flips, are the driver's — real CI
evidence has not landed yet). Grounded at `ba1ee48`; re-read current file
state before editing per the plan's own caution (WP2 review fixes had since
touched `Invoke-Container.ps1`'s smoke config area, `tests.yml`'s unit-job
7-Zip precondition and shellcheck list, and the unit count).

**Landed:**
- `scripts/Invoke-Container.ps1`: new `Load` action (`docker load`, symmetric
  with `Export`); the smoke kit check now lists all 8 real kit artifacts
  (added `RECONSTRUCT.paths.json`, the genuine gap the plan's grounding pass
  found — the "witness sidecar" disposition text was stale, `MANIFEST.csv.meta`
  was already checked since WP1); a second, source-mutating container run
  appended strictly after the existing single-run assertions, asserting
  exactly one `Snapshot_<date>` folder under `/changes`, re-running the
  8-artifact kit check against both `/backup` and the snapshot folder, and
  two more restore containers — one restoring `/backup` (latest) compared
  against the mutated source, one invoking `RECONSTRUCT.ps1` from *inside*
  the snapshot folder itself (per grounding note 4: the authority folder is
  wherever the invoked script physically lives) compared against a
  pre-mutation `source-gen1` copy taken before the mutation.
- `.github/workflows/tests.yml`: `container` job gains a `registry:2`
  service, an Export→`docker rmi`→Load→Test step and a Publish→`docker rmi`
  (both tags)→Pull→Test step, a bounded `curl --retry` registry-readiness
  check before Publish, a one-line localhost-trust comment, and
  `timeout-minutes: 20`→`25`.
- Registries: minted **SN-028, SR-044, LLR-044, TC-079, TC-080** (all
  `Draft`/`Phase=container-v1`) and reworded TC-060's `Expected` to describe
  the 8-artifact kit + load roundtrip + registry roundtrip CI now proves,
  per plan §1. `python scripts/trace.py --strict`: **SN=28 SR=44 LLR=43(of
  44; LLR-019 is a pre-existing gap) TC=79(of 80; TC-029 likewise) orphans=0
  integrity=0.**

**Ratchet NOT re-armed — deviation from plan §2/§4, per the work order's own
contingency clause.** Bumping `--phase` to `core,bash-v1,container-v1` in
both `check.ps1` and `tests.yml`'s traceability job makes
`--require-verified` report a real status-finding (`SR-034 is
Verification=Test but Status=Implemented`), because SR-034/TC-060 are still
pending a green CI run of the new container steps — this is expected
pre-CI, not a defect. Per instruction, **kept both files at `--phase
core,bash-v1`** and left a `TODO(WP3 ratchet)` comment at each site naming
the exact commit-time condition (driver flips `--phase` to
`core,bash-v1,container-v1` in the same commit that flips
SR-034/LLR-034/TC-060/SR-044/LLR-044/TC-079/TC-080 to `Verified`/`Pass`,
after real green CI). SR-034/LLR-034 Status columns and TC-060/079/080
Status columns are untouched (still `Implemented`/`Draft` as the plan
requires until CI proves it).

**Local verification — Docker unavailable on this host.** `docker version`
and `docker` on PATH both fail (`docker: command not found` / not
recognized); the only container tooling present is Podman
(`C:\Program Files\RedHat\Podman\podman.exe`) plus a **stopped** WSL
`podman-machine-default` distro — no running container engine. Per the work
order's contingency, did **not** fake a green `BuildAndTest` run. Static
verification performed instead:
- `Invoke-ScriptAnalyzer -Settings tests/PSScriptAnalyzerSettings.psd1` on
  `scripts/Invoke-Container.ps1` and `scripts/check.ps1`: **0 findings**
  (also swept by `check.ps1 -Tier Full`'s own lint step, see below).
- `[System.Management.Automation.Language.Parser]::ParseFile` on
  `Invoke-Container.ps1`: **no parse errors.**
- Manual code review of the new incremental/snapshot block: mount
  read/write modes match the existing pattern (`/backup`, `/changes`
  writable on the backup run, read-only on every restore run); the
  `source-gen1` copy happens before the host-side mutation and lives outside
  every bind-mounted directory; `$runArgs` is reused verbatim for the second
  `docker run` (same mounts, same image) as the plan specifies; the
  snapshot-restore invocation points at
  `/changes/<Snapshot_name>/RECONSTRUCT.ps1` with explicit
  `-BackupRootOverride /backup -ChangeRootOverride /changes`, matching
  grounding note 4 exactly.
- **In-container proof (BuildAndTest, Load, Publish/Pull, and the new
  incremental/snapshot smoke assertions actually executing) has NOT
  happened locally and awaits the first push's CI run of the `container`
  job**, per the work order.
- WSL shellcheck was not re-run: no `.sh` file was touched by this step (only
  `Invoke-Container.ps1`, `tests.yml`, `check.ps1`, and the registries).

**`pwsh scripts/check.ps1 -Tier Full` (Gate G3) — genuinely green, real
output:**
```
==== PSScriptAnalyzer ====
[PASS] PSScriptAnalyzer

==== Traceability (trace.py --strict) ====
Traceability: SN=28 SR=44 LLR=43 TC=79 orphans=0 integrity=0
status-findings=0 phase-deferred=3.

==== Doc navigability (check_docs.py) ====
[PASS] Doc navigability (check_docs.py)

==== Architecture map freshness ====
[PASS] Architecture map freshness

==== Pester unit ====
Tests Passed: 172, Failed: 0, Skipped: 0, Inconclusive: 0, NotRun: 0
[PASS] Pester unit

==== Integration sweep (Full) ====
TEST SUMMARY
  PASS: 236
  FAIL: 0
  SKIP: 4
[PASS] Integration sweep (Full)

================ check.ps1 (tier Full, gate G3) ================
All steps passed.
```
(`--phase core,bash-v1` still in force, so `status-findings=0` here —
`phase-deferred=3` now covers SR-033 (bash-v2) plus SR-034/SR-044
(container-v1); this is the expected pre-CI shape, not a regression.)

Commits (this session, `resync_v2`, no push — the driver pushes): container
script + smoke depth; CI Export/Load + Publish/Pull roundtrip (phase left at
`core,bash-v1` with TODO comments); registry mints + TC-060 reword.

**Awaiting:** the driver's push, a real green CI run of the `container` job
(BuildAndTest, Export/Load roundtrip, Publish/Pull roundtrip, incremental +
snapshot smoke all passing in-container), the ratchet re-arm to
`core,bash-v1,container-v1` alongside the SR-034/LLR-034/TC-060/SR-044/
LLR-044/TC-079/TC-080 status flips, independent review, and batch
ratification. Current State tallies below updated to SN=28 SR=44 LLR=44
TC=80 per plan §1 (registry *row* counts — trace.py's summary line counts
distinct ids present out of the numeric range, so it reports LLR=43/TC=79
because of the pre-existing LLR-019/TC-029 gaps, not because a row is
missing here).

### INDEPENDENT REVIEWER — WP2 re-verification — 2026-08-22
Verdict: **APPROVE** (upgraded from CHANGES-REQUESTED). All findings
re-probed on a pristine export of `b67cdcf` and confirmed closed: the
AllowEmptySource `"false"` delete-all repro now refuses with
`$.BackupSets[0].AllowEmptySource — must be a JSON boolean` and exit 2,
creating no directories; every other type coercion (SourcePath array, Name
number, HashRecalcFreq array, Tools/Secrets types, SmtpPort string,
BackupSets string) refused with the key named; the shared fixture corpus
(7 accepted / 27 rejected, the shipped example itself a fixture) drives
TC-074/075/077 with schema↔validator parity on all twelve probe rows
including the bare-set `anyOf` and integral-float ConfigVersion; missing
config exits 2 (pinned); a refused config appends to an existing log and
creates nothing in a fresh path (pinned); all minors closed (real
BackupSets index, ConfigVersion range guard, 7-Zip CI precondition,
entrypoint.sh in shellcheck scope, PS 7.0-floor Test-Json form, AGENTS.md
counts 172/48 match measurement). Deviation ruling: keeping SR-042/043 at
`Verified` was ACCEPTED — the fixes and fixtures land green in one commit,
so no commit exists where the row overclaims; the premature `ba1ee48` flip
stays on record in the CHANGES-REQUESTED audit entry. Evidence (pristine
export): unit 172/172, integration Mirror 59/0/1, trace 0/0/0, lint clean.
**WP1 and WP2 are now both implemented + independently review-APPROVED;
awaiting batch ratification.**

### DRIVER (Software + Test Engineer, Data-integrity hat) — WP4 snapshot retention — 2026-08-23
Executed [docs/plans/wp4-retention-plan.md](plans/wp4-retention-plan.md) §3 phases A→F in order, grounded at
`3ee8f5b`/`b4f108c`, one commit per green phase. The plan's §5 driver decisions
were treated as binding: the verb is **`Remove-BackupSnapshot`** (`Prune-` fails
approved-verbs lint), an **absent witness refuses by default**
(`-AllowUnverifiedIndex` overrides — the deliberate inverse of the restore
default), and **unreferenced bytes refuse by default**
(`-DiscardUnreferencedData` overrides).

**Phase A (highest care) — index extraction, zero behavior change.** TC-089
landed FIRST and was run green against the PRE-refactor code, then
`Get-BackupContentIndex` was lifted literally out of `Optimize-ChangeFolders`
(same key construction, same blank/missing guards, same folder ordering) and
Optimize refactored to consume it. Full tier re-run including TC-049.
Commit alone, as the plan requires.

**Phases B–E.** `Get-SnapshotPrunePlan` / `Get-BackupSnapshot` (pure,
read-only); `Assert-PrunePrecondition` / `Test-PoolResolves` (the rails);
then the transaction — `Copy-ReHomedDataFile`, `Publish-PruneManifest`,
`Complete-PruneDeletion`, `Invoke-PruneEntrySweep`, with
`Remove-BackupSnapshot` as a short ordered list of named steps; then the
adversarial and interrupt/resume tests. §4's regression risks were treated as
constraints: prune never copies `MANIFEST.csv.meta` between folders and every
rewrite goes through `Write-Manifest` (TC-085 pins both halves with an AST
guard); TC-084 re-stamps tampered witnesses so the intended failure is what is
observed; the store — `FileBackupState.json` included — is hash-compared
byte-for-byte after every refusal.

**Phase F — boundary.** `FileBackup.ps1 -Action Backup|Prune|Snapshots` +
`-Snapshot` (the Backup path is untouched); `container/entrypoint.sh` dispatches
on `FILEBACKUP_ACTION` or a leading positional word and leaves every
`-`-prefixed argument in `"$@"` exactly as before; README "Snapshot retention
(pruning)" + the container action block; IF-001 rewritten per §1.6 (SR-Refs
+= SR-045..048, the "planned `Prune-Snapshot` verb" wording replaced);
AGENTS.md §2 module map + entry-point row and a new §3 invariant ("a
`Snapshot_*` folder is removed only by `Remove-BackupSnapshot`"); arch map
regenerated; §6 totals refreshed.

**Deliberate deviations (both recorded in the registry cells):**
1. `Assert-PrunePrecondition` **returns** the full refusal set instead of
   throwing on the first one, so `Remove-BackupSnapshot` can apply the
   2 > 3 > 4 > 1 precedence over all of it and `-WhatIf` can report every
   refusal at once (LLR-046 states this).
2. TC-081 and TC-083 are declared `Tier=Smoke`, not `Full`: they live in the
   Pester suite, which every tier runs, and claiming Full would understate
   where they actually execute.

**Defects found while testing (both fixed here):**
- `@($empty.FullName)` yields `@($null)`, which fails a `[string[]]` binding —
  pruning the LAST remaining snapshot aborted with a spurious code 4. All three
  index call sites now project with `ForEach-Object`. (A close cousin of the
  PS 7.5 `@()`-over-a-List gotcha already in AGENTS.md §4.)
- The first draft of TC-082's "stored exactly once" assertion counted copies by
  hashing raw files, which is wrong in the two `+Compress` modes (the stored
  file is a `.7z` whose own bytes hash to something else). It now counts through
  `Get-BackupContentIndex`.

**Also fixed:** `-Action Snapshots` first emitted its JSON down the pipeline,
where the caller captured it as part of the status code — it now writes to
`[Console]::Out` (probed in a child process before and after).

**Evidence — real output, this host.**
```
pwsh scripts/check.ps1 -Tier Full        (gate G3, --phase core,bash-v1)
[PASS] PSScriptAnalyzer
Traceability: SN=29 SR=48 LLR=47 TC=89 orphans=0 integrity=0
              status-findings=0 phase-deferred=4.
[PASS] Doc navigability (check_docs.py)
[PASS] Architecture map freshness
Tests Passed: 223, Failed: 0, Skipped: 0
[PASS] Performance budgets (check_perf.py)
  PASS: 324   FAIL: 0   SKIP: 4
All steps passed.
```
```
WSL (podman-machine-default):
  bats tests/bash            -> 48 ok / 0 not ok
  shellcheck container/entrypoint.sh -> clean
```
Baseline before WP4 was unit 172, integration 236/0/4; the deltas are +51 unit
(TC-081..089 minus TC-088's container half) and +88 integration (G9's retention
half, 22 assertions × 4 modes).

**Status flips:** SR-045/046/047 → `Verified`, LLR-045/046/047 → `Verified`,
TC-081..087/089/090 → `Pass`. **SR-048 stays `Implemented`** (Phase
`container-v1`) with LLR-048 `Implemented` and **TC-088 `Draft`**: Docker is not
available on this host, so the in-container half was NOT run and is not claimed.
TC-088's locally runnable halves — the `-Action`/`-Snapshot` parameter contract,
the real child-process invocations of every action (inventory JSON, prune,
unknown name → 2, dry run, legacy flags-only), the entrypoint dispatch and
`-`-pass-through source assertions, and the guard proving `bash/reconstruct.sh`
carries no removal path — all run and pass in the Pester suite. The
`--phase core,bash-v1` ratchet and its `TODO(WP3 ratchet)` comment are
deliberately untouched.

**Open-items:** row **I** → *Implemented (WP4) — awaiting independent review +
batch ratification*; new row **C-form** records the §5.7 latent defect
(blank-`Compressed` vs the located file's form after a compression-mode flip),
dispositioned to WP5 with WP4's `Test-PoolResolves` as the detector/repro.

**For the independent reviewer, in priority order:** (1) the transaction
ordering in `Remove-BackupSnapshot` — specifically that nothing is deleted
before `Test-PoolResolves -ExcludeFolder` has passed, and that the
`Pruning_<name>` rename is a genuine single commit point for *all three*
consumers (both restorers and Optimize); (2) the TC-049 interaction — a prune
transiently creates a second copy, and the "stored exactly once" property is
asserted on quiescent states only (TC-082); (3) destination election and name
synthesis in `Get-SnapshotPrunePlan` (does the elected destination always
already demand the key? is the collision guard tight enough in Mirror mode?);
(4) the form-agreement rule in `Test-PoolResolves`, including the deliberate
`.7z`-RelativePath exemption; (5) whether refusing to prune *into* an
already-broken pool is the right default given `-RepairFromPruned` is deferred
to WP5.

### DRIVER (Software + Test + Data-integrity hats) — WP5 storage-form trust — 2026-08-23
Verdict: implemented and green on a Full tier — **awaiting independent review +
batch ratification**. Work order:
[plans/wp5-storage-trust-plan.md](plans/wp5-storage-trust-plan.md), phases A→H,
one commit per green phase. Ids minted: **SN-030, SR-049..052, LLR-049..052,
TC-091..102.** Closes HomeHub cross-check finding **C**, the WP4-surfaced
**C-form** latent defect, the planning-pass **C-refcount (G10)** data-loss
defect, the **ext-list merge**, and the **backup-side capacity** row.

**Phase A — one shared predicate (557b2b1).** `Test-StorageFormAgreement`
extracted from `Test-PoolResolves`' inline check so prune (SR-046) and verify
(SR-049) ask the same question and cannot drift, carrying the documented
C-form exemption (a row whose own RelativePath ends `.7z` is not a
disagreement). Behavior identical; WP4's TC-083/084/089 re-run green.

**Phase B — REPRO, RED (ba9b35d).** The evidence commit. Real red output, run
before any fix, from `tests/Unit/StorageForm.Tests.ps1`:

```
[+] leaves every malformed row byte-identical and still reports the set successful (SR-049)
[+] swallows a failed transformation of a Compressed=Yes-over-raw row into a log line (SR-049)
[-] reports one finding per malformed row with its class (SR-049)
    CommandNotFoundException: The term 'Test-BackupStorageForm' is not recognized...
[-] restores a snapshot byte-exact after compression is turned on (mode Mirror) (SR-050)
    Expected: '2A7B9B01C49B84B0D15E4048E13F1BA772FE68630DECFBB711E6BCF807B4EF0D'
    But was:  '540C3E48515CBABA6BBFCAAA3A9AE442A3C74447AF3A80BDC29D1969D588CEE6'
[-] restores a snapshot byte-exact after compression is turned off (mode Mirror) (SR-050)
    RuntimeException: Reconstruction INCOMPLETE: 1 file(s) could not be restored
    (0 content-missing, 1 host): a.txt.
[-] restores a snapshot byte-exact after compression is turned on (mode HashAddressed) (SR-050)
[-] restores a snapshot byte-exact after compression is turned off (mode HashAddressed) (SR-050)
Tests Passed: 2, Failed: 5
```

The two PASSES are the defect: four malformed shapes survive
`Sync-BackupStorageLayout` byte-identical and the set still reports success,
because `$needsTransform` compares manifest metadata with configuration and
never with the bytes. The five failures are the requirement. Note the two
directions of the WP4 §5.7 defect: flipping compression ON gives **exit 0 with
7z container bytes written under the original filename** (silent corruption);
flipping it OFF gives **exit 4 misfiled as a HOST problem**. Both reachable with
NO tampering.

*Masking defect fixed in the same commit (new, not in any disposition):*
`Initialize-Dependencies` set `$deps['7z'] = $null` whenever `CompressEnabled`
was false, so turning compression OFF made the SR-012 migration silently inert
("7-Zip not found. Skipping transformation") and a documented configuration
change was never applied. 7-Zip is now resolved opportunistically and silently
on that branch (no prompt — SR-016).

**Phase C — SR-050, the data-integrity commit (4127edb).** Both restorers now
decide whether to decompress from the form the LOCATOR PROVED, not from the
row's `Compressed` (which describes only a file in the row's own folder).
`Find-DataFileByHash` gains `Form`; `find_by_hash`'s Found tuple becomes
`Found\037<form>\037<path>`; an archive candidate that fails to expand is
re-tested as raw bytes before a CandidateError (Q4). `# KitRevision: 2` markers
in both restorers (no prior convention existed; 2 is the first stamped one).
TC-092 4/4 GREEN, TC-098 6/6, TC-099 6/6 under bats on real Linux.

**Phase D — SR-051, refcount-safe migration (ddf52ab).** Closes G10. Verified
RED against the pre-fix engine before landing:

```
[-] keeps every row of a shared-content pair resolvable ... (mode Mirror)
    Expected $true, because row 'same.jpg' must still resolve after the migration, but got $false.
[-] retains a superseded path that a surviving row still references
    Expected $true, because a still-referenced superseded path must never be deleted, but got $false.
[-] reports a failed transformation ... and FAILS the set   Expected 1, but got 0.
```

Green after, in all four modes. A (hash,length) group is decided together, a
shared file is transformed once, Phase 2 retains any path a surviving row still
references, and a failed transformation fails the set.

**Phase E — SR-049, verify + repair (3e170f0).** `Get-StoredFileForm` (7z magic,
no hashing) → `Get-StorageFormFinding` (exactly one finding per row) →
`Test-BackupStorageForm` (root + every snapshot, mutates nothing) →
`Repair-BackupStorageForm` (bytes are ground truth; rewrites `Compressed` and
renames; never re-packs, never touches the six logical columns, refuses a rename
onto a root-level infrastructure name, persists ONLY through `Write-Manifest`)
→ `-Action Verify` on WP4's one dispatch (+`-VerifyStorage` alias,
`-RepairStorage`, `-Deep`, `-BackupRootOnly`/`-IncludeSnapshots`,
`-RefreshKits`) → the entrypoint word `verify`. Findings as JSON via
`[Console]::Out`. `Get-BackupKitRevision` reports the kit a snapshot is stuck
with on every blank-row finding. Two more defects found while testing and fixed
here: `Get-BackupContentIndex` threw on an empty `-SnapshotFolder` arriving as
`$null` (AGENTS §4 hazard), and the C-form exemption was applied to the flag
check but not the NAME check, so `already.7z` stored raw was reported as
`NameLies` in all four modes.

**Phase F — SR-004 merge (b1aafb5).** `.jar .tgz .zst .gif .webm .ogg .sav
.pack` added to the ONE list (Q6; no Office extensions — SN-003's acceptance is
a stakeholder decision). README gains the table, and TC-096 asserts it equals
the live list and that the list has one definition site. TC-097 (suite case
`G4.2`, four modes) builds a genuine PRE-merge store and re-runs on the merged
list: the triggered migration leaves nothing dangling, verifies clean, and every
state — both snapshots and the latest — restores byte-exact with exit 0; run2 ≡
run3.

**Phase G — SR-052 capacity (d082cda).** `Get-FreeSpaceBytes` /
`Get-VolumeIdentity` in **Common** (the kit stays self-contained), measuring via
`System.IO.DriveInfo` with `Get-PSDrive` as the drive-qualified fallback, never
throwing. `Reconstruct.ps1` rewired: its `Split-Path -Qualifier` lookup **threw
on a rooted POSIX path and was swallowed by the adjacent catch, so SR-023's
restore capacity check has been silently inert on Linux and in the container
since it was written** while bash's `df` half worked (planning finding G9).
Backup side: two pure demand estimators + `Assert-BackupCapacity`, called at
step 5.5 (migration) and 9.4 (content); a refusal removes the staging folder
before throwing so it cannot orphan a `Temp` for the next run's SR-017 guard,
and fails the SET (status 1), not the invocation. No configuration key (Q8).

**Phase H — boundary, docs, registries (this commit).** TC-102 lands as
`Test-ContainerStorageForm` inside the container smoke test (clean verify exits
0 / emits parseable JSON / mutates nothing; a seeded malformed row exits 1;
repair then re-verify exits 0); README gains the `-Action Verify` section, the
finding-class table, the merged-extension table and the **old-kit exposure**
statement with both remedies; AGENTS §2/§3/§4/§6 updated (three new invariants:
the blank-row form rule, the one-predicate rule, and the kit-revision rule; a
new gotcha forbidding `Split-Path -Qualifier` for volumes); IF-001 amended
(SR-Refs += SR-049;SR-052, the `verify` word, the capacity refusal); LLR-004 /
LLR-012 / LLR-023 / TC-002 amended per the plan's §3 table.

**Evidence (real, local, 2026-08-23):**

- `Invoke-Pester -Path tests\Unit` → **294 passed / 0 failed / 0 skipped**.
- `tests\Run-All.ps1 -NonInteractive` → **372 PASS / 0 FAIL / 4 SKIP**
  (G8 RealVolume under Subst).
- `bats tests/bash` on real Linux (WSL Fedora 40) → **54/54**;
  `shellcheck -S warning bash/reconstruct.sh container/entrypoint.sh` clean.
- `python scripts/trace.py --strict` → `SN=30 SR=52 LLR=51 TC=101 orphans=0
  integrity=0`.
- PSScriptAnalyzer over the maintained surface: clean.

**Honest gaps — what is NOT proven here.**

1. **Docker was unavailable on this host.** TC-102 and **TC-101's Linux half**
   have never been executed. TC-101/TC-102 stay `Draft`, and **SR-052 stays
   `Implemented`, not `Verified`** — its acceptance requires the restore
   capacity check to demonstrably fire on Linux, which is exactly the thing the
   `Split-Path -Qualifier` bug prevented, and no local run can show it. This
   means `check.ps1 -Gate G3` reports **exactly one status-finding** until that
   CI run; a `TODO(WP5, same CI run)` in `scripts/check.ps1` names it beside the
   WP3 ratchet TODO, and both flip in the same commit once the container job is
   green. SR-049/SR-050/SR-051 ARE Verified — their acceptance is fully covered
   by locally-passing TCs.
2. **WP5 does not close F3 for pre-existing snapshots restored by their own
   kit**, and never claimed to. A snapshot written before revision 2 keeps the
   defective kit permanently, including copies moved off-volume. The remedies
   are documented in README (restore with the root's current kit, or
   `-RefreshKits`), and the verifier reports each snapshot's kit revision.

**Findings for the independent reviewer.**

- **[MEDIUM] `Test-PoolResolves`' blank-row `form-mismatch` refusal is now
  conservative.** WP4 made it a code-2 prune refusal because "the restorers
  branch on the ROW". SR-050 removed that premise, so prune now refuses to
  prune a store that a revision-2 kit restores correctly — reproducible by any
  compression flip. Left UNCHANGED deliberately (a pre-revision-2 snapshot
  restored by its OWN kit is still exposed, and relaxing a Verified prune rail
  is not WP5's call). New Open-items row; targeted WP6.
- **[MEDIUM] A dangling `DataPath` becomes a permanently unrestorable row.**
  Observed while building TC-094: a row whose data file is missing is dropped by
  `Test-BackupManifest`, re-copied from source only if the diff sees a change —
  and where the source file is unchanged, `Optimize-ChangeFolders` blanks the
  `DataPath` instead, leaving a row whose bytes are nowhere in the pool while
  the run reports success. `Test-PoolResolves` detects it (`broken-pool`); no
  backup run does, and SR-049's form audit deliberately does not (it is not a
  FORM finding). Pre-existing, not a WP5 regression. New Open-items row.
- **[MINOR] Manifest row ORDER is not stable between consecutive no-op runs**
  (the final manifest is enumerated from a hashtable). Row CONTENT is stable, so
  SR-024 holds; TC-094 and TC-097 therefore compare rows sorted by
  `RelativePath` rather than raw file bytes. G7-Determinism does not catch it.
- **Scrutinize most:** the SR-050 change in both restorers (4127edb) — it is the
  one place where a wrong decision silently writes wrong bytes; the Phase 2
  retention filter and the group-consistency gate in
  `Sync-BackupStorageLayout` (ddf52ab); and `Repair-BackupStorageForm`'s rename
  path, which is the only WP5 code that moves a data file.

**Deviations from the work order.**

- TC-092/TC-095/TC-098/TC-100 landed in `tests/Unit/StorageForm.Tests.ps1`
  (which drives real multi-run backups and real restores in-process, as WP4's
  TC-081..090 do) rather than in G9-Rollback; TC-097 landed as the planned
  `G4.2` suite case. The bash half of TC-097's "both restorers" is covered by
  TC-099/TC-054 under bats — the Windows integration suite cannot drive
  `reconstruct.sh`.
- `-IncludeSnapshots` and `-BackupRootOnly` are the same knob, exposed both ways
  (`-IncludeSnapshots:$false` ≡ `-BackupRootOnly`) so the plan's §4 wording and
  the disposition wording both resolve.
- TC-091's "the set still succeeds" assertion had to FLIP at phase D: SR-051
  makes a failed transformation fail the set. The phase-B commit is the record
  of the pre-fix behavior.

---

### DRIVER (Software + Test Engineer, Data-integrity hat) — WP4 review fixes — 2026-08-23

**Verdict received: CHANGES-REQUESTED** on the WP4 snapshot-retention mechanism,
with one confirmed byte-loss path. Every accepted finding is landed here; the
work sits on `resync_v2` at `aa796db` (code + tests) plus this documentation
commit.

**H1 — HIGH, confirmed byte loss (fixed).** `Invoke-PruneEntrySweep`'s
`*.fbprune.tmp` cleanup was a bare-suffix recursive filter over the whole pool.
In Mirror mode a genuine user file `notes.fbprune.tmp` is stored at its verbatim
path and carries a manifest row, so the reviewer's repro — a **REFUSED** prune
(a typo'd snapshot name) — permanently destroyed every copy of it across the
backup root and every snapshot, and then wedged the store: the resulting
`broken-pool` rail blocks all future prunes, and breakage in the backup root
never self-heals. Fix: the sweep deletes a `.fbprune.tmp` only when the folder's
OWN manifest does not reference it (a staged copy is unreferenced by
construction; real content is not), and it scans only pool folders — the only
re-home destinations. Pinned by new TC-083 cases: the user file, root-level AND
nested, survives a refused prune, a `-WhatIf`, and a successful prune of another
snapshot, restores byte-exact from every origin afterwards, and a genuine
unreferenced staged copy beside it is still swept.

**H2/M1 — the entry sweep ran outside the transaction (fixed, behaviorally).**
The sweep now runs INSIDE the per-name transaction, after
`Assert-PrunePrecondition` passes and the Temp lock is held, so (a) its failures
land in the existing code-4 catch instead of escaping unclassified as process
exit 1, (b) refusal paths (2/3) genuinely mutate nothing, and (c) `-WhatIf`
skips it entirely — no log lines, no inflated count. The one thing that still
runs before the rails is deliberately name-scoped: `Remove-CommittedPruneResidue`
completes an outstanding `Pruning_<the same name>` deletion, which is past the
commit point, invisible to every consumer, and occupies the very name the plan
needs; it is wrapped so a host failure is a code-4 record, and it is skipped
under `-WhatIf`. Residue for any other name is left alone. This is what keeps
TC-083's after-commit-rename resume case working (re-invoking sweeps the residue
and then refuses `bad-target` with 2, exactly as before). SR-046 and LLR-046 now
state this ordering, and AGENTS.md section 3 carries the H1 warning.

**M2 — self-fulfilling assertion (fixed).** `tests/Suites/G9-Rollback.ps1`'s
per-state prune check derived `$expectF` from the restore output it was
validating, so a lost `f.txt` passed vacuously. The expectation now comes from
that snapshot's own manifest, and the "must be absent" half is asserted too.

**M3 — three untested rails (fixed).** TC-084 gains `destination-collision`
(hand-verified by the reviewer, now pinned), `infrastructure-name`, and
`capacity`. The capacity rail was rebuilt: WP4 grouped destinations by
`Split-Path -Qualifier` inside a `Group-Object` key, which cannot parse a UNC or
rooted POSIX path — terminating under the entry point's
`$ErrorActionPreference='Stop'`, and otherwise yielding an empty drive name that
the `Get-PSDrive` fallback rejected into a swallowing `catch`. Either way the
rail did not exist on a UNC store. It is now `Get-PruneCapacityRefusal`, built
on Common's `Get-VolumeIdentity`/`Get-FreeSpaceBytes` (SR-052, WP5), summing per
volume, refusing with 2 when free space is short on drive-qualified AND UNC
destinations (probe stubbed in tests), and SKIPPING rather than refusing when a
volume cannot be measured.

**M4 — TOCTOU on the Temp lock (fixed).** `New-Item -Force` succeeds on an
existing directory, so two prunes could both pass the staging-busy rail.
`-Force` is dropped so creation is the atomic test; the already-exists failure is
classified as the staging-busy refusal (2), and the `finally` block no longer
deletes a lock this invocation did not create. Pinned by a test that makes the
folder appear *after* the rails pass (mocked precondition), plus an AST guard.

**L1 — `-Action Backup -WhatIf` (fixed).** It bound because prune needs
`SupportsShouldProcess`, and produced a half-run. It is now refused as a
precondition before anything is read or created: exit 2 under `-ExitCode`, a
terminating error otherwise, with a message saying dry-run is Prune-only.

**Reviewer caveats recorded (not fixed).**

- **README and the broken-pool refusal now say it plainly**: an unresolvable
  pool blocks *every* prune in the store, nothing self-heals, run
  `-Action Verify` to enumerate the damage, and recovering content from a
  partially removed snapshot (`-RepairFromPruned`) is a recorded future item.
  The refusal message itself carries the "run -Action Verify" pointer.
- **L2 accepted as-is**: the AST guard over the prune path is lint, not proof;
  the digest-uniqueness assertion is the real pin.
- **L3 accepted as-is, recorded as a perf follow-up**: `Get-BackupSnapshot` is
  O(n^2) — one `Get-SnapshotPrunePlan` per snapshot, each rebuilding the pool
  index, and the plan hashes candidate files during what is advertised as a
  read-only inventory. Threading a shared index through `Get-SnapshotPrunePlan`
  is not a trivial edit to a data-integrity function, so it was NOT attempted
  here.

**Evidence (real, this host, 2026-08-23).**

- `Invoke-Pester -Path tests\Unit` → **310 Passed / 0 Failed / 0 Skipped** in
  241.94s (was 294; +16 for H1/H2/M3/M4/L1).
- `pwsh scripts/check.ps1 -Tier Full` → integration **372 PASS / 0 FAIL /
  4 SKIP** (Subst, four modes, G1–G9), PSScriptAnalyzer clean, doc navigability
  clean, architecture-map freshness clean, Pester unit green. The run's ONE
  failing step is the pre-existing G3 status finding carried from WP5:
  `SR-052 is Verification=Test but Status=Implemented` (TC-101's Linux half
  needs the Docker CI job). `python scripts/trace.py --strict --phase
  core,bash-v1` → `SN=30 SR=52 LLR=51 TC=101 orphans=0 integrity=0`, exit 0;
  with `--require-verified` the same single SR-052 finding, exit 1 — unchanged
  by this work.
- `pwsh scripts/check.ps1 -Tier Smoke -Gate G1` → **All steps passed.**
- No shell file changed, so bats/shellcheck were not re-run (bats 54/54 stands
  from WP5).

**Registry.** SR-046 (requirement, acceptance, permutations), LLR-046 (code
symbols and detail) and TC-083/TC-084 (parameters and expected) updated to
describe the behavior as it now is. No status flips: SR-045..047 stay Verified,
TC-083/TC-084 stay Pass, and no TC changed so materially as to need re-minting.

**Deviations from the work order.** None on substance. Two notes: (1) the work
order's fallback ("keep a pre-loop sweep gated to provably-residue items") was
not needed — full relocation works, with the name-scoped committed-residue
completion described above as the one documented pre-rail action; (2) the
reviewer's wording said `Split-Path -Qualifier` *throws* on UNC — it emits
"does not have a qualifier specified", which is terminating only under
`$ErrorActionPreference='Stop'` (the entry point's setting). The conclusion is
unchanged, and the test pins the actual behavior on both UNC and POSIX-rooted
paths.
---

### DRIVER (Software + Test Engineer, Data-integrity hat) — WP5 review fixes — 2026-08-23

**Verdict received: CHANGES-REQUESTED** on WP5 (storage-form trust), with one
confirmed data-loss path in the *repair* action and one silent-unrecoverability
path in *both* restorers. Every accepted finding is landed here: code + tests in
`c1cbd4f`, registries and documentation in this commit. The **restore kit is now
revision 3** in both `Reconstruct.ps1` and `bash/reconstruct.sh`.

**H1 — HIGH, `Repair-BackupStorageForm` corrupted deduplicated stores (fixed).**
Findings are emitted per ROW; the repair renames a PHYSICAL file. Dedup points
several rows at one file (SR-003), so the first row's repair renamed the file and
the second row's repair then saw `Missing` at the old path and skipped it — the
store was left with a row pointing at a path that no longer existed. The reviewer
reproduced it: a repairable `FlagOverRaw` pair came out as one healed row and one
unrestorable one. Repairs are now grouped by `(Folder, DataPath)`: the rename
happens ONCE, EVERY row referencing the old path adopts the observed form, and
the folder is persisted once through `Write-Manifest` — the same lesson `ddf52ab`
taught `Sync-BackupStorageLayout`. A row exempted from the flag rewrite by the
`.7z`-`RelativePath` rule still follows the file through the rename but keeps its
own `Compressed` (rewriting it from the bytes would make the restorer expand the
user's own archive). New TC-094 case: two identical-content rows sharing one
DataPath in the `FlagOverRaw` shape — **both** healed, one physical copy still
serves both, re-verify clean, restore byte-exact.

**H2 — MEDIUM-HIGH, a blank row for a genuine `.7z` SOURCE file was
unrecoverable while every checker called the store clean (fixed).** In both
locators, an archive candidate that expanded SUCCESSFULLY but whose payload did
not match was dropped without its own bytes ever being tested — and a real `.7z`
source file, which SR-004 deliberately stores raw, is exactly that shape (it *is*
a valid archive; its payload is simply not that row's content). The row's own
`.7z` `RelativePath` is the deliberate `Test-StorageFormAgreement` exemption, so
`-Action Verify` reported the store clean. Both restorers now test every
non-matching `.7z` candidate as raw bytes before dropping it — symmetric with the
existing failed-expand fallback and free on the happy path. Reachable with **zero
tampering** (the reviewer's recipe, now the test): an ordinary two-run timeline
whose source holds a real `.7z`; run 2 supersedes an unrelated file, so
`Optimize-ChangeFolders` blanks the archive's row in the snapshot.

**M1 — Sync's "7-Zip not found" skip contradicted SR-051 verbatim (fixed).** The
arm in `Sync-BackupStorageLayout` logged WARN and continued *without* setting
`$OverallSuccess`, so a run reported success over a store the configuration no
longer describes. One line: it now logs ERROR and fails the set. Pinned by a new
TC-095 case (`OverallSuccess` false, nothing mutated).

**M2 — `Get-VolumeIdentity` had no Linux semantics, and capacity never summed
(fixed).** `[System.IO.DriveInfo]::new($path).Name` is the IDENTITY function on
Unix — it echoes the path handed to it — so `/backup` and `/backup/sub` read as
*different* volumes and every same-volume decision was wrong off Windows. The
identity now comes from `[System.IO.DriveInfo]::GetDrives()` (which reads the
real mount table on Linux): the longest mount point prefixing the resolved path
on a separator boundary, with the old constructor kept as the fallback and
Windows root normalization unchanged; it still never throws. Separately,
`Assert-BackupCapacity` checked the backup and change demands independently and
never their sum, so two demands competing for ONE volume's free space both
passed; demands are now grouped by volume identity and the group total is checked.
The `.DESCRIPTION`s of both functions say so honestly. **SR-052 stays
`Implemented`** — the true Linux confirmation is still the Docker CI job, and no
Windows run can substitute for it; the Windows-side tests pin the summing and
exercise the same longest-prefix matcher. WP4's prune capacity rail
(`Get-PruneCapacityRefusal`, built on these two Common functions) was re-run and
is green.

**Minors.** (m1) TC-100's "fails the SET (status 1)" case now **observes** the
child process exit code (`Should -Be 1`) against a *genuine* shortfall — an
inflated `Length` in the backup manifest makes step 5.5's migration demand exceed
any volume, so no stub is involved. (m2) `-Action Verify` now resolves its roots
through `Resolve-BackupSetPaths -ReadOnly` **inside the try**: it creates no
directory, does not require `SourcePath` (a verify is about the STORE; the source
may be offline), and a missing backup root is the documented code 2. Its
`.OUTPUTS` drops the code-4 claim, which it never produced. (m3) Recorded, not
rewritten: TC-097's Expected now notes that the case forces
`CompressEnabled=true` (its mode axis is effectively two configurations) and that
**TC-092 is the SR-050 integration proof**; TC-092's row says so too. (m4) Sync's
Phase 2 identifies a superseded path by the `(Full, Rel)` pair recorded in Phase 1
instead of slicing `$rootPrefix` off the full path, and the orphan warning uses
`[IO.Path]::GetRelativePath`. (m5) The step-9.4 comment no longer overclaims
"byte-identical": step 6's migration may already have re-formed existing rows, so
what 9.4 guarantees is that none of THIS RUN's content is written and no staging
folder is orphaned — which is precisely why 5.5 proves the migration's room
first. The same correction is in LLR-052.

**Registry truth-up.** SR-049 (repair acts on the physical file; dedup
acceptance; `sharing` permutation), SR-050 (the raw retest now covers a
successful-but-non-matching expand; `genuine-7z-source` permutation), SR-051
(missing-7-Zip named in the acceptance; `failure` permutation), SR-052
(mount-table identity + per-volume summing in requirement and acceptance),
LLR-049..052 and TC-092/093/094/095/097/098/099/100/101 updated to describe the
behavior as it now is. **No status flips:** SR-049/SR-050/SR-051 stay `Verified`
— their extended TCs genuinely pass — and **SR-052 stays `Implemented`**, so
`check.ps1 -Gate G3` still reports exactly one status-finding, the disclosed one.

**Evidence (real, this session).**

- `Invoke-Pester -Path tests\Unit` → **316 Passed, 0 Failed** (baseline 310; +6).
- `pwsh scripts/check.ps1 -Tier Full` → `[PASS]` PSScriptAnalyzer, doc
  navigability, architecture-map freshness, Pester unit, perf budgets, and
  **Integration sweep: PASS 372 / FAIL 0 / SKIP 4**. The single `[FAIL]` is
  `Traceability (trace.py --strict)` — `SN=30 SR=52 LLR=51 TC=101 orphans=0
  integrity=0 status-findings=1 phase-deferred=4`, i.e. the disclosed SR-052
  status finding and nothing else.
- WSL (real Linux): `bats tests/bash` → **55/55** (baseline 54; +1) and
  `shellcheck -S warning bash/reconstruct.sh` clean.
- **Repro-first evidence.** Each fix was first confirmed RED against `HEAD~`
  (60ebe6d) in a throwaway `git worktree` carrying only the new tests:
  H2 → `Reconstruction INCOMPLETE: 1 file(s) ... (1 content-missing, 0 host):
  real.7z`; H1 → `Expected 2 ... but got 1` (one row healed, one abandoned);
  M2 summing → `no exception was thrown`; M1 → `Expected $false ... but got
  $true`; m2 → the backup root was created by a verify that had nothing to
  verify. The bash half of H2 was confirmed the same way (`git stash` of
  `bash/reconstruct.sh`): `WARN: [ContentMissing] 'real.7z'`, exit 1.

**Deviations from the work order.** None on substance. Two notes: (1) the
repaired-finding COUNT is per repaired *finding*, so a shared-DataPath pair
reports `Repaired = 2` while TC-094's four-shape fixture still reports 3 — the
existing assertion is unchanged; (2) m3 was taken as the recorded-limitation
option (registry truth-up only, no test rewrite), as the work order allowed.

### INDEPENDENT REVIEWER — WP4 re-verification — 2026-08-23
Verdict: **APPROVE** (upgraded from CHANGES-REQUESTED). All six findings
re-verified closed against a pristine export of `60ebe6d` by re-running the
original repros: the H1 byte-loss sweep is dead (Mirror user files named
`*.fbprune.tmp` survive typo'd/dry-run/real prunes and restore byte-exact,
while genuine residue is still swept); the sweep is inside the transaction
with failures classified 4 and refusals mutating nothing; the name-scoped
pre-rail residue completion touches only `Pruning_<same name>`; the G9
assertion now derives expectations from the snapshot's own manifest; all
three missing rails have cases and the capacity rail exists on UNC paths
(unmeasurable volume = reasoned, documented fail-open skip); the Temp lock is
atomic; `-Action Backup -WhatIf` refuses cleanly. Baselines exact on the
export: unit 310/310, integration 372/0/4, trace SN=30 SR=52 LLR=51 TC=101
0/0. Recorded nit (no action): `Get-StoreFingerprint` excludes
`*.fbprune.tmp` wholesale — a future test combining `-SuffixNamedUserFiles`
with `Assert-StoreUnchanged` would be blind to the H1 class. The reviewer's
APPROVE covers WP4 + its fixes only; WP5 has its own review track.

### DRIVER (UX/Docs + System Engineer hats) — WP6 docs batch — 2026-08-23
Verdict: APPROVE (driver hats) — awaiting batch ratification with WP1-WP5.
Executed the three Open-items rows (release checklist, interfaces.md
boilerplate, doc drift) plus the accumulated housekeeping (plan-doc links,
Open-items truth-up, Current State rewrite). **Docs-only — no `Modules/`,
`Reconstruct.ps1`, `bash/`, `tests/`, `FileBackup.ps1`, or `container/` file
was touched.**

What changed:
- **Release checklist.** Regenerated `docs/release-checklist.md` via
  `python scripts/gen_release_checklist.py` — SN=30, human-SR=4, manual-TC=7,
  IF=1, PB=0; confirmed the generator survived the UN→SN rename intact and
  already includes the container SNs (SN-024/026/028) without any patch.
  Found and fixed one real generator bug in passing: its hardcoded release-
  hygiene line named a nonexistent `scripts/check.py` (a Python-stack
  leftover) — now `pwsh scripts/check.ps1 -Gate G3 -Tier Release`, matching
  this repo's actual harness entry point. Deleted the stale, already-
  untracked `docs/releases/checklist-vNEXT-dryrun.md`. Narrowed `.gitignore`
  so `docs/release-checklist.md` is tracked going forward (it is the current,
  regenerate-at-will checklist, kept navigable in the repo); `docs/releases/`
  stays generated/gitignored for future `--version`-stamped, signed copies.
- **`docs/interfaces.md`.** Replaced the unmodified kit boilerplate with a
  thin, project-specific page: what IF-001 is, a pointer to
  `requirements/interfaces.csv` as the machine source of truth, and a prose
  rendering of the current contract (mounts, config schema v1, one-set-per-
  invocation, the shared backup/restore/prune/verify exit-code table,
  retention policy/mechanism split, no-direct-snapshot-deletion,
  `Experimental` stability + the joint WP1/WP2 exit condition to leave it).
- **Doc drift.** Left the kit-version stamp untouched (re-stamp only on a
  real kit resync, not this batch). Read the current `bash/reconstruct.sh`
  and verified homehub-integration.md §5 item 8's claim: the false-parity
  comment is still present, unchanged, now at line 564 (source drifted from
  the finding's original :380/:381 coordinates). Its underlying claim is no
  longer false, though — cross-read against the current `Reconstruct.ps1`
  (~521-527) shows finding A's fix made the PowerShell restorer refuse with
  `EXIT_PRECONDITION` on the identical gate bash already used (`any_comp` and
  no usable 7-Zip), before writing anything. Both restorers now refuse
  identically; neither degrades. Closed the item with a dated verification
  note in place, without rewriting the original finding's history.
- **Plan-doc links.** `docs/plans/wp1-restore-trust-plan.md`,
  `wp2-config-contract-plan.md`, and `wp5-storage-trust-plan.md` were already
  linked (from Open-items or their own WP audit entries); `wp3-container-
  release-plan.md` and `wp4-retention-plan.md` were referenced only inside
  code spans (not real Markdown links, so `check_docs.py` still orphaned
  them) — converted both to real links from their WP3/WP4 audit-entry
  headers.
- **Open-items truth-up.** WP1/WP2/WP4/WP5 rows now read their actual review
  verdicts and landed-fix dates instead of a bare "awaiting independent
  review + batch ratification" (WP3 stays as-is — it genuinely has no CI
  evidence yet). Added a row for the WP4 reviewer's accepted
  `Get-StoreFingerprint`/`*.fbprune.tmp` nit. Confirmed and left `-RepairFrom
  Pruned` (Deferred → WP6-or-later), the dangling-DataPath defect, the
  `Get-BackupSnapshot`/snapshot-inventory-cost perf row, and the manifest-
  row-order row all present with a clear State. Per the work order: the
  dangling-DataPath row's State stays **Open**, its disposition now reads
  "awaiting human prioritization in the batch ratification" verbatim. The
  prune form-mismatch rail row is relabeled **WP6-or-later** and its
  disposition now says explicitly that relaxing a Verified prune rail is a
  code change and out of this docs-only batch's surface.
- **Current State header.** Rewritten: the WP1-WP6 scoreboard (WP1/WP2/WP4
  implemented + independently reviewed with accepted fixes landed; WP5
  implemented + fixes landed with re-review in flight; WP3 implemented,
  awaiting its own CI evidence on the first push of `resync_v2`; WP6 this
  batch, done); the CI-gated flip list (SR-034/SR-044 → Verified, ratchet
  → `core,bash-v1,container-v1`, SR-048/SR-052 → Verified once TC-088/101/102
  leave `Draft`); and the next human action (batch ratification, then the
  push).

**A concurrent, unrelated in-flight change was observed and deliberately left
alone.** `Modules/FileBackup.Engine.psm1` carries an uncommitted modification
to `Get-StorageFormFinding`'s `FlagOverArchive` exemption (payload-hash-keyed
instead of extension-keyed, citing a "WP5 re-review residual") that this
driver did not make and did not touch — consistent with the work order's note
that a read-only reviewer may be re-verifying WP5 concurrently. It is excluded
from every commit in this entry; whoever owns it should commit or discard it
separately.

Evidence (real output, local, this session):
- `python scripts/check_docs.py --root . --ignore 'docs/test/report.md'
  --ignore 'docs/releases/*'` → `check_docs: OK - 19 doc(s), 69 intra-repo
  link(s), 0 broken.` (0 orphans, 0 broken — was 4 orphan warnings before
  this batch: wp3-plan, wp4-plan, the newly-tracked release-checklist, and
  the gitignored report.md, the last of which stays excluded by `--ignore`
  and is expected.)
- `pwsh scripts/check.ps1 -Tier Smoke` (gate G3, from `docs/gate`): lint
  PASS; **Traceability FAILED** — `SN=30 SR=52 LLR=51 TC=101 orphans=0
  integrity=0 status-findings=1 phase-deferred=4`, the one pre-existing,
  disclosed SR-052 CI-gated finding from the WP5 baseline (Docker
  unavailable on this host; not a regression from this batch — no registry
  or code file changed here); doc navigability PASS (0 broken); generated-
  docs freshness PASS; Pester unit **316/316** PASS; performance budgets
  PASS (no budgets registered). `check.ps1`'s own summary: `FAILED:
  Traceability (trace.py --strict)` — the single known finding, unchanged
  by this batch.

Findings: none new. The generator bug (nonexistent `scripts/check.py`
reference) above is the only thing found broken.

### DRIVER (Data-integrity hat) — WP5 re-review residual fix (payload-keyed exemption) — 2026-08-23
Landed as `62fc702` (merged verbatim from the fix agent's audit note; the
note file docs/plans/wp5-residual-fix-note.md is removed in this commit):

# WP5 re-review residual (HIGH): the already-compressed exemption is keyed on the payload

*Audit note for the driver to merge into docs/status.md. Data-integrity hat,
branch `resync_v2`, 2026-08-23.*

## The defect

`Get-StorageFormFinding` granted the "already-compressed source file" exemption
only when the row's `RelativePath` ended in `.7z`, while `Get-StoredFileForm`
judges a stored file by its 7z magic bytes. The two never agreed for a source
file whose *content* is a 7z archive under any other name — `archive.7z.bak`,
a `.pack` file, an installer payload.

Consequences on an **untampered, correct** store:

1. Verify reported `FlagOverArchive` for that row and exited 1 across IF-001 —
   a false alarm on a store with nothing wrong with it.
2. `-RepairStorage` then took the bytes as ground truth and set
   `Compressed=Yes` (and renamed the data file to `*.7z`), after which the next
   restore **expanded the user's own archive** and wrote the inner payload under
   the original filename, exiting 0. Silent corruption of a previously correct
   store — the worst shape available in this product.
3. `-Deep` mislabelled the same case: it expanded the file and compared the
   inner file against the row, producing `PayloadMismatch`.

## The fix

The exemption is now keyed on the **payload**, not on the name. When the
observed form is `Archive` while the row says `Compressed=No`, the file's OWN
bytes are hashed against the row's `(xxH2Hash, Length)`:

- **match** → this is raw storage of archive-shaped content, which is correct
  (SR-004 declines to re-compress an already-compressed source). No finding,
  and no `NameLies` either.
- **mismatch** → a genuine `FlagOverArchive` (the classic legacy shape, where
  the *payload* and not the file reproduces the row). Found and repaired as
  before.

A `.7z` RelativePath is kept purely as a fast path. `-Deep` consults the same
answer, so it never expands a file whose own bytes already reproduce the row.
`Repair-BackupStorageForm` applies the identical payload-keyed rule to the
per-row `Compressed` rewrite inside its grouped path — it reads the bytes'
identity **before** the rename moves them — so a row exempted by payload follows
its file through a rename but keeps its own `Compressed`.

**Cost:** the confirming hash runs only for a file whose bytes are an archive
while its row says `No` — rare — so the default (non-Deep) scan is still a
six-byte read per row. Stated in the function help.

## Evidence

- Repro-first: with the engine change stashed, the new fixtures are RED —
  4 failures, all `FlagOverArchive` on `archive.7z.bak` in an untampered store
  (Mirror and HashAddressed; the two Compress modes are green because the
  engine compresses a `.bak` source anyway). Green with the fix: 82/82 in
  `tests/Unit/StorageForm.Tests.ps1`.
- `Invoke-Pester tests\Unit`: **321 passed, 0 failed** (baseline 316; +5).
- `python scripts/trace.py --strict`: `SN=30 SR=52 LLR=51 TC=101 orphans=0
  integrity=0`.
- `pwsh scripts/check.ps1 -Tier Smoke -Gate G1`: **All steps passed** (lint,
  traceability, doc navigability, architecture-map freshness, Pester unit).
  At the default gate G3 the run fails on exactly one step, Traceability, with
  `status-findings=1` — the pre-existing SR-052 / WP3-ratchet item that
  `scripts/check.ps1` documents at line 119. Verified identical on stashed
  HEAD (`baseline exit=1`, same counts), so it is untouched by this change.

## Test and registry changes

- **TC-093** fixture repaired: `already.7z` held the literal string
  `pretend-archive-source`, which `Get-StoredFileForm` classifies as `Raw` — so
  the clean-store assertion never reached the exemption and passed vacuously.
  Both it and the new `archive.7z.bak` now hold REAL 7z bytes produced by
  `Compress-FileWithSevenZip`.
- New TC-093 cases: (a) an untampered store with a 7z-magic source under a
  non-`.7z` name reports zero findings in all four modes with and without
  `-Deep`, exits 0, is left byte-identical by repair, and restores byte-exact
  before and after; (b) a genuine `FlagOverArchive` is still found and repaired.
- `TC-094`'s Parameters cell contained an unquoted comma
  (`sharing=set{unshared,shared-datapath}`), so the row parsed as 10 fields and
  every column after Parameters was off by one. Re-quoted.
- Registry text updated: `LLR-049` Detail, `TC-093` / `TC-094` Expected.

No restorer or kit file changed → **no KitRevision bump, no bats change**.

## Residual

Full tier not run for this change (narrow, engine-local, Smoke green); the
driver should run it once WP6's docs work merges.

---

### DRIVER (Software + Test Engineer, Data-integrity hat) — WP5 residual #2: empty JSON documents — 2026-08-23

**How it was found.** Podman 5.5 turns out to be installed on the driver's host
(the earlier "Docker unavailable" notes were literally true but incomplete), so
the container suite ran locally for the first time:
`scripts/Invoke-Container.ps1 -Action BuildAndTest -Runtime Podman`. The build
and the core smoke (compressed backup, restore kit, byte-exact restore,
snapshot, both restores) passed; the appended TC-102 storage-form check failed
on the **clean** store — the exact case the Docker CI job would have hit first.

**The defect (engine, two emission sites).** Piping ZERO objects into
`ConvertTo-Json` emits nothing at all — the cmdlet never runs — so
`-AsArray`'s promised `[]` was never printed. Both one-shot JSON documents had
the shape: the SR-049 findings document (`FileBackup.ps1`, `Invoke-VerifyAction`)
and the IF-001/SR-047 snapshots inventory (`Invoke-RetentionAction`). A clean
store's verify and an empty store's inventory printed NO document while every
exit code stayed correct — precisely the states HomeHub will see most. Fixed by
passing `-InputObject` (an empty array serializes to `[]`; note
`-InputObject @() -AsArray` double-wraps to `[[]]`, so `-AsArray` is dropped —
the argument is already the array).

**A second, harness-side defect the fix exposed.** TC-102's extraction in
`scripts/Invoke-Container.ps1` used a greedy `(?s)\[.*\]` over the container's
mixed stdout, which ran from the document into the `[INFO]` tag of a later log
line and handed `ConvertFrom-Json` trailing garbage. Replaced with line-based
extraction (the document opens with a line that IS `[` and closes with a line
that IS `]`, or is the single line `[]`) — the same convention the Pester
snapshots-JSON test already used.

**Tests (new pins, both at the process boundary where IF-001 consumes the
output).** StorageForm.Tests.ps1: 'prints the findings document as parseable
JSON, the literal [] when clean (SR-049)' — malformed store parses to a
non-empty array carrying `Class`; clean store prints the literal `[]`.
Coverage.Tests.ps1: 'prints the literal empty JSON document for a store with no
snapshots (-Action Snapshots)'. Registry: TC-093 and TC-088 Expected updated;
no id re-minted, no status flips (TC-102 stays `Draft` — the CI run remains the
promotion criterion; the local Podman pass is corroborating evidence only).

**Evidence (real, this host, 2026-08-23).**

- `Invoke-Pester tests/Unit/StorageForm.Tests.ps1 tests/Unit/Coverage.Tests.ps1`
  → **234 Passed / 0 Failed / 0 Skipped** in 279.55s (232 before; +2 pins).
- `python scripts/trace.py --strict --phase core,bash-v1` →
  `SN=30 SR=52 LLR=51 TC=101 orphans=0 integrity=0`, exit 0.
- `Invoke-ScriptAnalyzer scripts/Invoke-Container.ps1` (repo settings) → clean.
- `Invoke-Container.ps1 -Action BuildAndTest -Runtime Podman` after the fix →
  **exit 0**: "Container storage-form check passed (TC-102): clean verify exits
  0 and mutates nothing, a malformed row exits 1, repair makes it clean." and
  "Container smoke test passed…". Image 372 MB; export refreshed to
  `.artifacts/filebackup-dev-wp5fix.tar` (354.5 MiB), the pre-fix tar deleted.
- `gen_release_checklist.py` re-run → byte-identical (no drift).

**Scope note.** The restore kit is untouched (revision stays 3 — neither
restorer changed); no SR/LLR text changed; the `--phase` ratchet stays at
`core,bash-v1`. Rolled into WP5's batch-ratification package.

---

### DRIVER (Software + Test Engineer, Data-integrity hat) — Adversarial review round & hardening batch — 2026-08-23

**What ran.** At the human's direction, two independent fresh-context reviews
of the whole repository: a medium-effort general review and an adversarial
data-integrity review (crash windows, dedup refcounting, restore edge stores,
container boundary), both bound by the human's triage rule — *realistic
operational scenarios only; malicious-tampering-only scenarios out of scope by
design*. The adversarial reviewer validated claims with throwaway repro scripts
(scratchpad only); four findings were REPRODUCED, the rest traced to specific
code paths. 19 findings total; 12 fixed same-day, 5 recorded as Open items
(R5-widening, R6, R7, R10, F8), 1 dismissed as malicious-only (R11), 1 already
fixed earlier the same day (R#8's parse bug, WP5 residual #2).

**Fixed — engine (`FileBackup.Engine.psm1`, `FileBackup.ps1`).**

- **F2 (HIGH, reproduced): the backup pipeline never consulted the witness it
  makes everyone else check.** A torn (crash-truncated) root manifest was read
  unchecked, then step 12 re-stamped a FRESH witness over state derived from
  the truncated index — laundering the damage; with a source deletion in the
  window, content vanished with exit 0 and no snapshot. Now a
  Mismatch/Malformed witness refuses the set BEFORE staging or mutation, and
  the entry point maps the distinct ErrorId onto **exit 3** (IF-001's table
  applies to backup). Absent stays legal — a pre-SR-038 store still backs up.
- **R3: staging-lock take was look-then-create.** `Test-Path` + `New-Item
  -Force` let two overlapping scheduled runs both pass; the create (without
  `-Force`) is now itself the lock, the same discipline `Remove-BackupSnapshot`
  already had.
- **F1 (HIGH, reproduced) / R4: the stale-Temp story was destructive.**
  README's remediation ("remove the leftover Temp and re-run") permanently
  destroyed the only physical copy of snapshot-demanded bytes after a
  mid-window crash (reproduced: snapshot restore exit 0 before, exit 1
  `ContentMissing` forever after, with the intervening backup reporting 0).
  Guard message + README now prescribe the non-destructive recovery
  (move-aside → re-run → verify → discard-or-reintroduce, never delete). And a
  step-5/step-6 abort (e.g. a source file locked by AV — routine) now removes
  the still-empty Temp instead of wedging every later run on the SR-017 guard.
- **F7: `FileBackupState.json` torn-write wedge.** Written in place; a torn
  write threw on every later run, and deleting the file walked into the SR-035
  refusal with no documented way out. Now published by write-then-rename like
  the witness.
- **R2: Mirror-mode root infrastructure-name collision.** With an external
  `SourceStatePath` (the container default), a source file legitimately named
  `MANIFEST.csv` at the source root was copied to the backup root and then
  OVERWRITTEN by the real index in step 12 — the manifest row pointed at index
  bytes; default verify called it clean. Prune and repair already refused this
  collision; the copy path now refuses it too (set fails, store intact).
- **F3 (HIGH for container-v1, reproduced at function level): case-insensitive
  hashtables silently drop case-differing files on Linux.** Every
  RelativePath-keyed map was a literal `@{}` (always case-insensitive):
  `Readme.txt`/`readme.txt` — two ordinary distinct Linux files — merged to one
  row through diff, backup map, source cache, and the PS restorer dictionary
  (`Update-SourceManifest` could even reuse the WRONG file's cached hash on a
  length+mtime coincidence). New `New-RelativePathMap` in Common: `@{}` on
  Windows (a case-only rename must NOT be a new file there), Ordinal elsewhere.
  bash was already case-sensitive.

**Fixed — restorers (kit revision 3 → 4;** `Reconstruct.ps1`,
`bash/reconstruct.sh`**).**

- **F4 (both reviewers; reproduced): stale `RECONSTRUCT.paths.json` hijacked
  the PS restorer.** The sidecar's recorded absolute roots were adopted with no
  existence check: a copied/moved store (the flagship self-contained-kit
  scenario) failed against the dead path — or, same-machine, **silently
  restored from the still-live ORIGINAL with exit 0** (and the SR-009
  containment check evaluated against the stale roots). Both restorers now
  honor the sidecar only while the origin still lives INSIDE the recorded
  roots; a copied/moved store auto-detects. (Stronger than bash's previous
  resolvability-only guard, which the same-machine hijack passed.)
- **F5: Optimize's delete-before-blank crash window read as data loss.** A run
  killed between `Optimize-ChangeFolders`' duplicate deletion and its manifest
  rewrite left rows naming deleted files; both restorers treated the non-blank
  `DataPath` as authoritative and reported `MissingDataFile` ("your bytes are
  gone") though the keeper sat in the pool — at exactly the moment an operator
  reaches for the kit. A non-blank `DataPath` is now a locator HINT: on a miss,
  both restorers fall back to the (hash,length) pool recovery blank rows
  already use.
- **F6: `\` separators on a non-Windows restore host.** `Reconstruct.ps1` never
  mapped them, so a Windows-made HashAddressed backup restored with pwsh on
  Linux wrote each nested row as a root-level file literally named
  `sub\file.txt` — **exit 0, structurally wrong tree**. Now mapped exactly as
  bash's `to_posix` does.

**Fixed — docs.** README's prune-unblock recipe claimed `-Action Verify`
"repairs the findings that are unambiguous" — verification mutates nothing
without `-RepairStorage`; sentence fixed (R9). interfaces.md now documents the
JSON framing (line-based extraction from mixed stdout) that HomeHub's wrapper
must implement (R8).

**Evidence (real, this host, 2026-08-23).**

- New pins: Pester Describe *'Backup pipeline crash-window hardening
  (2026-08-23 review round)'* — 6 tests: witness-mismatch backup refuses with
  **exit 3** and mutates nothing; witness-Absent legacy store still backs up;
  locked source file fails the set WITHOUT stranding Temp and the next run
  exits 0; Mirror infra-name collision refused with the store intact; a COPIED
  backup folder restores from the copy (containment warning asserted); a row
  whose named data file is renamed away hash-recovers from the pool. Plus
  *'New-RelativePathMap keys compare like the local filesystem (SR-034)'* in
  Common.Tests. All pass.
- Full unit suite + lint: see the run pasted in the Current State bullet
  (recorded after this entry was drafted; the run includes these 7 new tests).
- bash: `shellcheck -S warning bash/reconstruct.sh` clean; **bats 55/55, 0
  failures** on real Linux (WSL Fedora) after the reconstruct.sh changes.
- Registry: TC-024, TC-033, TC-058, TC-060, TC-066 Expected extended; the
  dangling-DataPath Open row widened with R5's corroboration; 5 new Open-item
  rows + 1 fixed-batch row. No SR/LLR status flips (the new behaviors verify
  under their existing SRs; the Linux halves of F3/F6 ride the container job).
- Known cosmetic drift, accepted: LLR Detail line-number references into
  `Reconstruct.ps1` (e.g. LLR-050's `:225-238`) shifted by this batch; symbol
  references remain correct. Flagged for the ratification rather than
  hand-renumbering mid-batch.

**Kit-revision exposure (same story as revision 2→3).** Snapshots written
before today keep their revision-3 kits, which carry F4/F5/F6 until refreshed —
`-Action Verify -RefreshKits` upgrades every snapshot's kit in place; README's
revision note covers the exposure.

**Deviations / not fixed (with the human's triage rule applied).** R5
blank-DataPath healing needs its own SR (dedup-group selection is not a
rush-fix surface) — widened Open row awaits prioritization; R6 quoting and R10
no-7-Zip-raw-skip batch with the next kit revision; R7 newline rows are
bash-v2; F8 kit-less snapshot window recorded with a candidate cheap fix; R11
(sed JSON nit) dismissed as malicious-only per the rule.

---

### INDEPENDENT REVIEWER — WP5 fix-set re-verification + review of `11b2c46`/`83cc5f1` — 2026-08-23

**Why this entry exists.** The earlier WP5 re-review (in flight last session)
delivered its one HIGH residual — the payload-keyed exemption, fixed in
`62fc702` — but its closing verdict was never merged into this file before its
session ended, violating the durable-memory rule. This fresh read-only
re-verification against a **pristine clone of `83cc5f1`** (repo working tree
untouched) replaces it and also gives the two same-day unreviewed commits
their independent pass.

**Part A — WP5 fix set: APPROVE** (one doc minor, folded into the fixes
below). Independent probes with the reviewer's own fixtures, 25/25 PASS:
H1 dedup-pair repair heals BOTH rows sharing one physical file, re-verifies
clean, restores byte-exact via the standalone kit; the payload-keyed exemption
reports ZERO findings for real 7z bytes under a non-`.7z` name (Mirror and
HashAddressed, ±`-Deep`), repair mutates nothing, restores byte-exact before
and after, while a genuine `FlagOverArchive` is still found and repaired; the
`11b2c46` empty-document fix prints the literal `[]` for both `verify` and
`snapshots` at the process boundary. Pinned TC-094 Describe: 8/8.

**Part B — `11b2c46`: APPROVE.** `-InputObject` at both emission sites is
correct (dropping `-AsArray` avoids the `[[]]` double-wrap; a single finding
still serializes as a one-element array); the harness's line-based extraction
matches the framing now documented in interfaces.md.

**Part B — `83cc5f1`: CHANGES-REQUESTED.** Eleven of the twelve fixes check
out under scrutiny (witness gate truly pre-mutation with real exit 3 observed;
sidecar containment breaks no in-place or snapshot restore and bash's case
pattern is correctly quoted; the hash fallback keys on the row's own
`(xxH2Hash, Length)` — the store's dedup identity, identical to blank-row
recovery; the staging lock matches the prune precedent; the step-5/6 Temp
cleanup only ever removes a Temp that is empty by construction). Required:

1. **R1 (same severity class as F3 itself): `Save-SupersededData`'s
   `$backupByRel` was still a literal case-insensitive map.** On Linux, a
   case-differing pair — kept correctly distinct by the FIXED diff and backup
   maps — collapses here; the lookup returns the twin row, its content
   "survives", staging is skipped, and the copy step overwrites the superseded
   bytes: the snapshot row is permanently ContentMissing. Reproduced at
   function level on the pristine clone.
2. **R2 (minor): `Get-BackupCapacityDemand`'s `$byPath`** — same one-line
   conversion; consequence is capacity under-estimation only.
3. **R3 (docs): the batch's claim "README's revision note covers the
   exposure" was false** — README and AGENTS.md §3 both stopped at revision 3;
   and AGENTS.md still described the exemption as RelativePath-`.7z`-keyed,
   stale since `62fc702` (the Part A minor).

Reviewer's evidence (pristine clone): unit **330/330** (5:04), TC-094 Describe
8/8, hardening Describe 6/6, WSL `shellcheck` clean + **bats 55/55**, trace
0 orphans / 0 integrity, lint 0 findings. Two notes recorded, no action
required: a store that loses both witness integrity AND `FileBackupState.json`
exits 1 (SR-035 fires before the gate), not 3 — still a pre-mutation refusal;
and `New-Item` narrows rather than provably eliminates the lock race — fine
for scheduled-run overlap.

---

### DRIVER (Data-integrity hat) — Landing the `83cc5f1` review's required changes — 2026-08-23

All three required changes landed, exactly as specified:

- **R1:** `Save-SupersededData`'s `$backupByRel` → `New-RelativePathMap`, with
  a why-comment naming the failure. **R2:** `Get-BackupCapacityDemand`'s
  `$byPath` likewise. New CLASS pin in the hardening Describe: a literal
  `@{}` whose fill is keyed by `.RelativePath` anywhere in the four code files
  fails the suite — the exact shape the review caught can't regress silently.
- **R3:** AGENTS.md §3 exemption sentence rewritten payload-keyed (the Part A
  minor); AGENTS.md §3 and README's kit-revision notes extended to
  **revision 4** with the F4/F5/F6 exposure spelled out.
- **Noted for a container-v1 sweep, not converted here (outside the review's
  required scope):** the DataPath-keyed membership maps
  (`$referencedPaths`/`$ownReferenced`/`$existingPaths`) are also literal
  case-insensitive hashtables; their failure modes are orphan-warning
  suppression / missing-file classification, not byte loss. Worth one look
  when container-v1 verifies.

Evidence: see the run pasted in the Current State bullet (full unit suite
including the new class pin, lint, trace, container re-run — all after these
edits).

---

### HUMAN — Batch ratification — 2026-08-23

The human reviewed the ratification worksheet (artifact `d48d6e78`, built from
this file's Current State and Open items) and ratified the batch: **WP1, WP2,
WP4, WP6; WP5 including both residuals, on the recorded re-review APPROVE;
WP3's implementation pending its own CI evidence; and the adversarial-review
hardening batch `83cc5f1` together with its review-fix landing `31a55f2`, on
the recorded CHANGES-REQUESTED→landed trail.** ("I've reviewed and ratified",
2026-08-23.)

Consequences: the push of `resync_v2` is unblocked (first run of the container
and bash-interop CI jobs); on green CI the pre-authorized registry flips
execute (SR-034/044/048/052 → Verified, TC-088/101(TC-101 Linux half)/102 →
Pass, ratchet → `core,bash-v1,container-v1`), clearing the one standing G3
status finding.

**Deliberately not decided here:** the dangling/blank-DataPath prioritization
and the parked-findings acceptance (R6/R7/R10/F8 + the form-mismatch rail).
The human asked for a realism verification of those before deciding; two
read-only investigations (blank-DataPath reachability end-to-end, and the
prune form-mismatch rail's real-world trigger) are in flight and their
findings will be recorded here when they land.

---

### INVESTIGATIONS (read-only, scratchpad repros) — realism verification of the two undecided Open items — 2026-08-23

Both run at the human's request before deciding the dispositions; both
escalate their item. Full facts folded into the Open-items rows; summary:

**Blank-DataPath (verdict: worth its own WP now; NOT parkable behind "verify
detects it").** Reproduced end-to-end on HEAD: delete one file inside the
backup root (dominant realistic class — AV quarantine, cloud-sync
dehydration, operator tidying; README never warns against it; the engine's
own deletion paths are closed on current code) → next run WARNs once and
exits 0, blanks the row, never re-copies although the diff proves the source
still holds the bytes → all later runs silent → **`-Action Verify`/-`Deep`
exit 0 "no disagreements" on the broken store** → restore exits 1
content-missing. R5 adoption confirmed live: a NEW same-content file adopts
the blank row with zero warnings and no bytes ever written. Kit-4 fallback
rescues only content that survives elsewhere in the pool — unique content is
lost. Cheap fix class verified viable: never adopt a blank DataPath
(simultaneously kills the spread and heals from source), re-copy on blanking
when the source matches, call `Test-PoolResolves` from Verify, README
warning.

**Prune form-mismatch rail (verdict: promote WP6-or-later → scheduled).**
Reproduced: after a `CompressEnabled` flip, prune refuses the whole store
(exit 2 form-mismatch) while the refused snapshot restores byte-exact with
its own revision-4 kit; `-RepairStorage` says unrepairable, `-RefreshKits`
doesn't clear it, the precondition doesn't exclude even the snapshot being
pruned. NEW beyond the row: a store with snapshots from both regimes is
**permanently wedged under either setting** (no unblock short of hand-editing
manifests, which breaks witnesses); and the WP5 phase-F extension merge is
itself a form flip for 8 types, so an existing compressed store that merely
upgrades walks into the wedge with no operator action. README's promise that
the flip is safe was true for restore and false for prune — a Known-
limitation caveat with the single-flip workaround is landed in README in
this commit (docs-only). Data safety never at risk; the refusal is
conservative.

---

### HUMAN — Open-item rulings + WP7/WP8 minted — 2026-08-23

After the investigations below, the human ruled ("Yes, please build out WP7
and WP8 … I will push when those are completed"):

- **WP7 minted (storage self-healing + retention unblock):** the verified-HIGH
  blank-DataPath item (never adopt a blank DataPath; heal from source on
  blanking; wire `Test-PoolResolves` into `-Action Verify`; README
  backup-root warning) plus the form-mismatch prune-rail relaxation, as one
  WP — shared `Test-PoolResolves`/verify surface.
- **WP8 minted (portable names + raw-candidate recovery):** R6/R7 are
  dispositioned by ruling — **a source filename invalid on either platform is
  skipped LOUDLY at backup time** (reported per file, set fails); no
  special-case handling of quote/newline names. Plus R10's no-7-Zip
  raw-candidate test (a kit-revision bump, batched here).
- **F8** understood and stays parked (sub-second window, `-RefreshKits`
  recovers). **Snapshot inventory cost** accepted: real cadence is one backup
  per day, so O(n²) is a non-issue at practical scale.
- **The push waits for WP7+WP8** — "No reason to push especially with WP7
  still unfixed."

---

### DRIVER (Software + Test Engineer, Data-integrity hat) — WP7: storage self-healing + retention unblock — 2026-08-23

Plan: [plans/wp7-self-healing-plan.md](plans/wp7-self-healing-plan.md). All
four scoped changes landed; every acceptance ran green.

**Healing (SR-053).** `Compare-SourceToBackup` gains a third NewOrChanged arm:
metadata-equal but blank `DataPath` — a blanked row re-enters the diff, so the
run after a data-file loss re-copies from the still-matching source (or
re-points at a surviving dedup copy). `Invoke-BackupFileGroup`'s dedup
candidate filter now requires a non-blank `DataPath`, so a new same-content
file can never adopt a row that points nowhere (the R5 spread). The heal run
mints its snapshot like any other manifest-changing run.

**Verify sees the pool (SR-054).** `Invoke-VerifyAction` appends
`Test-PoolResolves`' `broken-pool` problems to the findings document as
`Class=PoolUnresolvable` (six-field shape preserved; findings drive exit 1) —
closing the investigation's decisive blind spot: a store with permanently
unrestorable rows no longer verifies clean. Pool audit is always pool-wide;
`-RootOnly` scopes only the form audit. Report-only by design — bytes cannot
be conjured; the heal is the next backup run or restoring content into the
pool.

**Rail relaxation (SR-046 as amended).** `Test-PoolResolves`' blank-row form
check is now gated on the ROW'S OWN folder's kit revision (cached
`Get-BackupKitRevision`): revision ≥ 2 kits decide form from the located file
(SR-050), so the disagreement restores correctly and no longer blocks
retention — the compression-flip wedge (including the two-regime permanent
wedge and the phase-F upgrade trigger) is gone. A folder with a pre-revision-2
kit (or none) still refuses, and the refusal now names the kit revision and
the `-RefreshKits` remedy. Non-blank-DataPath form mismatches still refuse —
the restorers still trust `Compressed` for a file present at its named path.
Problem objects gain `Folder`/`RelativePath`/`DataPath` fields (additive).

**Latent defect found and fixed while landing the rail gate:**
`Get-BackupKitRevision` read the kit header with the LAZY
`[IO.File]::ReadLines` and returned from inside the loop — PowerShell does not
dispose the enumerator on an early return, so the open handle on a snapshot's
`RECONSTRUCT.ps1` lingered until garbage collection. Harmless for every
pre-WP7 caller (verify paths never rename afterwards), but the rail gate made
PRUNE a caller, and the leaked handle intermittently blocked the commit rename
with access-denied (4 flaky suite failures, reproduced with the refusal
message in hand). Fixed with the eager `ReadAllLines`; the flakiness is gone.

**Two pre-WP7 pins updated to the new semantics (not weakened):** TC-091's
"leaves every malformed row byte-identical" now exempts exactly the DANGLING
shape — the run heals it from source, which is SR-053's whole point — and
asserts the heal while still proving the three FORM-malformed rows stay
byte-identical; Engine.Tests' pure-diff "ignores unchanged" now models the
backup row with its DataPath column populated (as every real manifest row is)
and pins the blank-DataPath arm explicitly.

**Docs.** README: the backup-root "never tidy this folder" warning with the
AV/cloud-sync culprits and the new healing/verify behavior; the prune
Known-limitation box replaced by the kit-revision-gated behavior.

**Registries.** SN-031 minted; SR-053/SR-054 minted `Verified`; SR-046
Requirement/Acceptance/Permutations amended (kit-revision gate); LLR-053/054;
TC-103..105 `Pass`. `trace.py --strict` → `SN=31 SR=54 LLR=53 TC=104,
0 orphans / 0 integrity`; `--require-verified` still exactly the one
pre-existing SR-052 CI-gated finding.

**Evidence (real, this host, 2026-08-23).** New WP7 Describe — 5/5: pure-diff
blank-row pin; end-to-end heal + adoption ban (external deletion + new
same-content file → exit 0, both rows resolve, restore byte-exact); Verify
exits 1 with `PoolUnresolvable` in the JSON document when every copy of a
content is deleted; compression-flipped store **prunes with exit 0** and the
surviving snapshot restores byte-exact across the flip; the same store with
one kit regressed to revision 1 **refuses with exit 2** naming form-mismatch
and RefreshKits. Full-suite + lint run recorded in the WP7+WP8 wrap-up entry.
Existing TC-084 rail cases (non-blank mismatches) unchanged and green.

---

### DRIVER (Software + Test Engineer) — WP8: portable names + raw-candidate recovery — 2026-08-23

Plan: [plans/wp8-portable-names-plan.md](plans/wp8-portable-names-plan.md).
Both scoped items landed.

**Portable-name guard (SR-055, the human's R6/R7 ruling).**
`Test-PortableRelativePath` classifies per component (Windows-forbidden
characters incl. control/newline, trailing dot/space, backslash-in-name on
non-Windows). The skip happens INSIDE `Update-SourceManifest`'s scan, before
any open/hash attempt — a trailing-dot name Windows cannot even open would
otherwise abort the whole set on a read error instead of being named as the
problem. Step 5.1 logs one ERROR per skip and fails the set; step 8 filters
skipped names out of `RemovedFromSource`, so a previously stored row under a
bad name is FROZEN, never evicted. This retires R6 (7-Zip quote mis-split) and
R7 (bash newline rows) at the source for every newly written store.

**Raw-candidate recovery without 7-Zip (R10; kit revision 4 → 5).** Both
locators now test a `.7z`-named candidate's OWN bytes even when 7-Zip is
absent (raw needs none); only a candidate whose raw bytes do not match still
records DependencyMissing. A restore requiring no actual decompression no
longer exits 4 demanding 7-Zip. Two bats fixtures whose no-7z candidate
happened to BE the row's raw bytes renamed `.7z` — exactly the shape that now
recovers — were updated to genuinely non-matching bytes, and a new bats case
pins the recovery; the PS process-level exit-4 pin needed the same fixture
update (its candidate was also the row's bytes renamed), while the PS
function-level DependencyMissing pin already used non-matching bytes and
stands unchanged.

**Registries.** SN-032 minted (deferred from the WP7 commit so it never sat
orphaned); SR-055 `Verified`, LLR-055, TC-106 `Pass`; TC-107 `Pass` under the
SR-050 family for the revision-5 behavior. `trace.py --strict` →
`SN=32 SR=55 LLR=54 TC=106, 0 orphans / 0 integrity`. AGENTS.md §3 and
README's kit-revision notes extended to revision 5.

**Evidence (real, this host, 2026-08-23).** WP8 Describe 3/3 (classification
matrix; trailing-dot end-to-end via `\\?\` — exit 1, one Skipping ERROR, rest
backed up, prior row frozen with its data file intact; raw-`.7z` recovery with
a bogus `-SevenZipPath`). WSL: `shellcheck` clean, **bats 56/56** (55 + the
new revision-5 pin). Full-suite + container runs recorded in the wrap-up
below.

---

### INDEPENDENT REVIEWER — WP7 (`1acbbbf`) + WP8 (`8e5e925`) — 2026-08-23

Read-only review against a pristine clone at `8e5e925`; every hard case probed
(heal-picks-wrong-bytes, Save-SupersededData interaction, snapshot minting,
kit-gate folder semantics, ExcludeFolder, no other lazy-enumerator leaks in
the module, post-repair re-verify includes the pool audit, JSON shape,
frozen-row interactions, zero behavior change when 7-Zip is present).
Reviewer's suite runs: WP7+WP8+SR-046 refusal Describes 30/30, all remaining
prune/retention Describes 39/39, Engine+StorageForm 148/148, **bats 56/56**,
trace 0 orphans / 0 integrity.

**WP7: CHANGES-REQUESTED.**
1. *(Required)* `Get-BackupCapacityDemand` counted a blank-DataPath row's key
   as "already held", so a heal's copies were budgeted ZERO — the flagship
   cloud-dehydration scenario would fail mid-copy on a full volume instead of
   refusing before mutation (SR-052 violated in the heal case; reviewer
   reproduced: 500-byte blanked row → demand 0).
2. *(Required)* Verify stamped EVERY broken-pool problem
   `PoolUnresolvable — no bytes anywhere in the pool` without checking the
   pool: a row whose named file is gone while the content survives elsewhere
   (restorable by the revision-4+ fallback, healed next run) was reported as
   data loss — a false escalation for the wrapper.
3. *(Minors)* the cited "wrap-up entry" did not yet exist (it is the entry
   after next); the WP8/WP7 audit entries were inserted out of the
   newest-last order (now reordered); cross-volume ChangeBytes over-estimates
   a blank prior row (conservative, noted).

**WP8: APPROVE-WITH-MINORS.** R10 verified clean (raw-first inside the
no-7-Zip branch only; kit revision 5 truthfully stamped both sides; all three
fixture updates justified). Minors: (1) SR-055's `backslash-on-linux`
permutation had NO covering test while TC-106 claimed one — the
registry-accuracy point; (2) Windows reserved device names pass as portable —
SR-design observation, recorded as an Open note; (3) an unreadable `.7z`
candidate under no-7-Zip double-records CandidateError + DependencyMissing —
cosmetic, accepted.

---

### DRIVER (Data-integrity hat) — Landing the WP7/WP8 review's required changes — 2026-08-23

- **R1:** `Get-BackupCapacityDemand` now excludes blank-DataPath rows from its
  already-held set (mirroring the SR-053 adoption filter) — heal copies are
  budgeted and the SR-052 preflight refuses before mutation. Pinned: unit case
  `budgets heal copies in the capacity preflight` (500-byte blanked row →
  demand 500; non-blank → 0). SR-052 acceptance text extended.
- **R2:** `Test-PoolResolves` broken-pool problems now carry `BytesSurvive`,
  proven on DISK against the content index (excluding the missing path
  itself — this very branch proves rows can lie); `Invoke-VerifyAction` maps
  survivors onto the honest new class **`PoolDataPathMissing`** and only a
  genuinely byte-less row onto `PoolUnresolvable`. Pinned: `verify tells a
  missing named file with surviving bytes apart from true loss` — spare copy
  present → `PoolDataPathMissing`, no `PoolUnresolvable`; spare deleted →
  `PoolUnresolvable`. SR-054 acceptance, LLR-054, TC-104 updated.
- **WP8 minor 1:** `Test-PortableRelativePath` gains a `-TreatAsPosix` test
  seam (defaults to the real platform); the Windows unit suite now asserts
  the POSIX backslash arm and the separator difference explicitly. TC-106 and
  LLR-055 now tell the truth about where that arm runs.
- **WP8 minors 2/3:** recorded as Open-item rows (reserved device names;
  accepted cosmetic double-record).
- **Minor (b):** the status.md tail re-ordered to newest-last (the
  investigation bodies re-joined to their header; WP7/WP8 entries moved after
  the rulings they implement).

---

### DRIVER — WP7+WP8 wrap-up: the full battery + first-CI post-mortem — 2026-08-23

Recorded after the review fixes landed (the evidence the earlier entries
point at). All output real, this host, 2026-08-23:

- **Unit: 341/341** (Pester, 5 files; includes the 10 WP7/WP8 pins, the two
  review-fix pins, and three pre-existing fixtures updated to carry a real
  `DataPath` — a held row without one now honestly reads as blank/heal-due).
- **Integration (the exact CI command, `Run-All.ps1 -Backend Subst
  -EmitJUnit -NonInteractive`): 372 PASS / 0 FAIL / 4 SKIP** (G8 real-USB
  skips, by design) — the Full-tier run the WP4-era residual asked for.
- **bash: shellcheck clean; bats 56/56** (WSL Fedora).
- **bash-interop replicated end-to-end locally:** fresh Windows-made fixtures
  (all 4 modes) restored through `tests/bash/verify_restores.sh` on Linux —
  **verified 12 origins, 0 failing**.
- **Container job replicated on REAL Docker** (Ubuntu WSL, docker 29.6.1 —
  the runner's engine, not Podman): BuildAndTest incl. TC-102, then the CI
  job's Export → `docker rmi` → Load → re-Test sequence — all pass.
- **Podman side unchanged and green**; export tar refreshed
  (`.artifacts/filebackup-dev-wp5fix.tar`, revision-5 kit inside).
- Lint clean on every changed file; `trace.py --strict` →
  `SN=32 SR=55 LLR=54 TC=106, 0 orphans / 0 integrity`;
  `check.ps1 -Gate G3` footer recorded below at commit time — expected state:
  exactly the one CI-gated SR-052 status finding.

**Post-mortem of the first real CI run (push of `83cc5f1`, run 32661497480,
3 ✓ / 5 ✗ / 1 skipped).** Diagnosed from the public API + local replication
(job logs need auth):

1. **Traceability — EXPECTED failure by design.** The job runs
   `trace.py --strict --require-verified` and the standing SR-052
   `Implemented` status is a finding until the post-CI registry flips land;
   the job's own `TODO(WP3 ratchet)` comment records this ordering. It stays
   red on the next push too, and clears with the flip commit.
2. **Unit + Integration (Subst) — attributed to the `Get-BackupKitRevision`
   handle leak** (present since WP5, fixed in `1acbbbf`): both jobs died
   without writing their result files, the signature of a teardown crash from
   a leaked handle inside a test store; both suites pass fully at HEAD
   locally (341/341 and 372/0/4 with the CI commands verbatim).
3. **Container — REPRODUCED and fixed.** On real Docker/Ubuntu the build and
   smoke passed and then TC-102's malformed-row seeding re-stamped the
   witness via the HOST's `FileBackup.Common` → `System.IO.Hashing` is not on
   ubuntu-latest → the module PROMPTED INTERACTIVELY and aborted. Never seen
   locally because this Windows host has the DLL. Fixed in
   `scripts/Invoke-Container.ps1`: the witness re-stamp now runs INSIDE the
   image (`--entrypoint pwsh`, the DLL is baked in); the full job sequence
   then passes on real Docker.
4. **bash-interop restore — no code defect found.** The full flow replicated
   locally passes 12/12 at HEAD, and the job failed in ~28 s (barely its
   apt-get step); treated as environmental/early-step until the next push's
   log says otherwise.

`check.ps1 -Tier Smoke -Gate G3` at commit time: every step PASS; footer
`FAILED: Traceability (trace.py --strict)` — the one pre-existing, disclosed
SR-052 CI-gated finding, unchanged.

**Expected result of the next push:** everything green except Traceability
(and the skipped self-hosted VHDX job); then the pre-authorized registry
flips + ratchet re-arm land as their own commit, and the push after that is
fully green.

**Addendum — second CI run (push of `fa6a894`, run 32671723151), diagnosed
from step-level API data.** Same five jobs red, but the step conclusions
rewrite the story:

- **Unit and Integration (Subst): the TEST steps PASSED on CI** (`Run
  Pester`: success; `Run integration tests (Subst)`: success). Only their
  reporter steps failed: dorny/test-reporter's glob treats the backslashes in
  a `${{ runner.temp }}` path as escape characters and matches nothing
  ("No file matches path `D:\a\_temp/pester.xml`"). So the earlier
  handle-leak attribution was unnecessary for this run — the suites are
  genuinely green on the runners. **Fixed in `tests.yml`:** results now write
  to workspace-relative, forward-slash paths (`pester-results/pester.xml`,
  `fbtest/**`), and the interop upload gets the same treatment plus
  `if-no-files-found: error` so an empty artifact can never pass silently.
- **Traceability:** first step fails with the SR-052 finding as designed;
  unchanged.
- **Container:** still fails, ~40 s into the BuildAndTest step — mid-build
  territory, same profile both runs, NOT reproducible locally (the full job
  sequence passes on real Docker 29 in Ubuntu WSL and on Podman). Needs the
  step log, which the API serves only with auth.
- **bash-interop restore:** still fails after ~12 s of real work; NOT
  reproducible locally even replicating the artifact zip round-trip onto
  native ext4 (12/12 origins pass). Needs the step log.

Diagnosis is blocked on the two failing step logs (the human can open the
jobs' Details pages; unauthenticated API serves conclusions and annotations
but not logs).

**Addendum 2 — third CI run (push of `d4922b5`, run 32672263476), diagnosed
from the human-provided log archive. Every remaining failure is now
root-caused:**

- **Integration (Subst): GREEN** — 372 PASS / 0 FAIL / 4 SKIP on the runner
  and the JUnit report parsed (the glob fix worked).
- **Unit: tests 341/341 GREEN on the runner; only the reporter failed** — the
  glob fix found the file, but dorny's `dotnet-nunit` parser crashes on
  Pester's NUnit-2.5 schema (`TypeError: cannot read properties of
  undefined`). **Fixed:** Pester now emits `JUnitXml` and the reporter uses
  `java-junit` — the exact parser the Subst job proved working.
- **Container: root-caused from the log.** The build, both smoke passes and
  both restores all PASSED on the runner; the TC-102 seeding then died with
  ACCESS-DENIED writing the malformed bytes — the data file belongs to the
  image's uid 65532 and the runner user cannot overwrite it. (The earlier
  Ubuntu-WSL "pass" was a false green: that shell is root.) **Fixed:** the
  entire seeding — data-file rewrite, manifest row flip, witness re-stamp —
  now runs INSIDE the image via one `--entrypoint pwsh` command with the
  target row passed by env var; the host only reads. Validated locally as a
  NON-root docker-group user (uid 1001), the faithful runner replica.
- **bash-interop restore: root-caused.** HashAddressed short-names can BEGIN
  WITH A DOT (e.g. `.nArDBFwE!yq[FFf !!!!!!!!#..bin` in the committed
  fixtures) and `upload-artifact@v4` EXCLUDES HIDDEN FILES BY DEFAULT — the
  Linux job's pool silently lacked exactly those data files, which is why
  precisely the two snapshot origins that hash-recover through them failed
  while every Mirror origin passed. **Fixed:** `include-hidden-files: true`
  on the fixture upload (alongside the earlier `if-no-files-found: error`).
- **Traceability:** the designed SR-052 failure, unchanged; clears with the
  registry flips.

**Expected fourth run: fully green except Traceability (+ skipped VHDX).**

---

### DRIVER — container-v1 SHIPPED: registry flips + ratchet re-arm — 2026-08-23

The fourth CI run (push of `08a1743`, **run 32673687758**) came back exactly
as predicted: **every job green except the by-design Traceability failure**
(VHDX skipped) — including the **container job's first-ever green run**:
build, byte-exact restore, TC-102 storage-form check, Export → `docker load`
roundtrip, and Publish/Pull through the throwaway registry, all on real CI.
That run is the promotion evidence the WP3 plan (§5 steps 5–6) and every
`Implemented`-pending row have been waiting for. In this commit, as
pre-authorized by the 2026-08-23 batch ratification:

- **SR-034, SR-044, SR-048, SR-052 → `Verified`**; **LLR-044 →
  `Implemented`**; **TC-060, TC-079, TC-080, TC-088, TC-101, TC-102 →
  `Pass`.**
- **Phase ratchet re-armed to `core,bash-v1,container-v1`** in both
  `scripts/check.ps1` (G3/all) and the CI traceability job; both TODO blocks
  retired with a note citing the evidence run.
- Verification after the flips: `trace.py --strict --require-verified
  --phase core,bash-v1,container-v1` → `SN=32 SR=55 LLR=54 TC=106,
  0 orphans / 0 integrity / 0 status-findings / 1 phase-deferred` (SR-033,
  bash-v2 — by design). The G3 gate's mechanized criteria are now fully
  clean for the first time since the retrofit began.
- Open-items rows *container release-verify* and *container smoke depth*
  close as Done (evidence: run 32673687758).

**Next:** push this commit — expected fully green — then advance G3 →
G-Release (human attestation per the gate-advance procedure), and optionally
move IF-001 Experimental → Stable jointly with HomeHub.

---

### VERIFICATION (3 agents: Opus on D-1/D-5, Sonnet on D-2/3/4, Sonnet on the drill inventory) — 2026-08-24 HomeHub defect review CONFIRMED — 2026-08-24

The consumer-side defect review
([defect-review-2026-08-24-mirror-dedup.md](defect-review-2026-08-24-mirror-dedup.md),
committed `f2bcf11`) was independently verified against HEAD by three agents
with local reproductions (scratchpad only; repo untouched). **All five
defects CONFIRMED**; both of the review's "not proven" items settled:

- **D-1 (data loss, Mirror ± Compress) — CONFIRMED and mechanism SETTLED:
  it is the review's option (a), with the fatal reasoning in
  `Save-SupersededData`, not `Optimize-ChangeFolders`.** `$survivingContent`
  is built FROM THE SOURCE (`Engine.psm1:2996`) and the skip at `:3003`
  infers the BACKUP keeps the bytes — false in exactly the borrower shape,
  where the only backup row claiming the content points at the very file the
  copy branch (`:2847`) then overwrites in place. The stale borrower row is
  what AUTHORIZES destroying the last copy. Repro: three runs (A stored; B
  adopts A's DataPath; A edited) → old bytes NOWHERE in the store, latest
  restore exit 0 with WRONG bytes for B, both snapshot restores exit 1.
- **Blind spot total:** default `-Action Verify` exits 0 "no disagreements";
  `Test-BackupManifest` and the SR-053 heal never fire (the row is non-blank
  and its file exists); only `-Deep` reports it (`PayloadMismatch`,
  `Repairable: false` — a post-mortem, the bytes are already gone).
- **Hash-addressed mode PROVEN immune by repro** (not just code-reading):
  changed content lands at a new content-derived name; every historical
  restore stays byte-exact; the eviction path refcounts correctly through a
  4-run owner-change-then-delete-borrower sequence. **D-5 is also
  Mirror-only** — in hash-addressed mode both copy-branch writes land on one
  content-derived filename.
- **D-2 (silent restore corruption) — CONFIRMED IN BOTH RESTORERS** (settles
  the parity question): a resolvable `DataPath` is expanded/copied with no
  hash comparison — wrong-payload archive, same-length bit-flip, and even a
  LENGTH-CHANGED truncation all restore with exit 0 in `Reconstruct.ps1` and
  `reconstruct.sh`. `xxH2Hash` is confirmed to be the ORIGINAL-content hash,
  so verify-after-write + fall-through to the existing pool recovery is
  sound. Fix shape: small, both restorers, kit-revision bump.
- **D-3 — CONFIRMED** (repro: one unrelated garbage `.7z` flips
  ContentMissing/exit 1 into CandidateError/exit 4). Key simplification:
  `Find-DataFileByHash`/`find_by_hash` are only ever called when the row's
  own file is blank or missing, so EVERY CandidateError they raise is by
  construction from an unrelated candidate — the reorder needs no new state.
  Fix shape: trivial precedence reorder in both locators.
- **D-4 — CONFIRMED on Windows** (Hidden-attribute file in no manifest, run
  reports success, zero disclosure) and code-confirmed for Linux dot-files.
  **NEW, beyond the review: the gap is SYSTEMIC — no `Get-ChildItem`
  anywhere in Engine/Common/Reconstruct uses `-Force`**, including the
  restore-side pool scan and the prune residue scan; bash's `find` does not
  skip dot-files, so the twin restorers even disagree. Fix shape: small
  (`-Force` + a disclosed skip count), with one design question (per-set
  configurability / Windows Hidden semantics).
- **Minimal violated invariant (for the design decision):** no write may
  change the bytes at a `DataPath` while any row anywhere claims a different
  `(hash, length)` for it. Mirror addresses data files by PATH ("whatever
  this source file holds now"); dedup hands that address to rows that mean
  "these exact bytes". Hash-addressing satisfies the invariant structurally.

**Drill inventory (HomeHub
`scripts/verify/library-permutation-drill.sh`):** the assertion that caught
D-1 — a second pass proving every blank-DataPath row's hash exists among the
hashes actually verified this cycle — has NO FileBackup equivalent; and the
one dedup-shape assertion FileBackup has (`G2.8 Dedup_singleDataPath`,
`Count -le 2`) is VACUOUS — it passes under D-5's bug. Six-item prioritized
import list and eight additional permutations (edit-the-borrower, multiple
borrowers, nested dot-directories, Windows Hidden, same-length corruption,
all-four-modes owner-edit, same-run vs prior-run duplicates, owner deleted
while borrower lives) recorded in the verification transcripts and proposed
for the fix WPs' test scope. MiniPC-Deployer's independent restore documents
a "three witnesses must agree" verification pattern — prior art for D-2.

### DRIVER + subagents (sonnet catalog, opus design analysis) — D-1/D-5 design drill: two-registry proposal — 2026-08-24

Human floated a fourth D-1/D-5 design shape: split the persisted model into a
source registry {path,hash,length,mtime}, a backup LOGICAL registry (same
shape + archive flag), and a CONTENT registry mapping {hash,length} → physical
file, so the storage label stops mattering. Two subagents drilled in
(persisted-artifact catalog; adversarial design evaluation vs options 1–3).

**Verdict: correct diagnosis, but ORTHOGONAL to D-1 — a schema normalization,
not a fourth option.** `DataPath`/`Compressed`/`StoredAsHashSize` are indeed
properties of `(hash,length)`, not of the row (`Invoke-BackupFileGroup` copies
all three verbatim into the borrower, Engine.psm1:2829-2835; Sync's
form-conflict apparatus exists to keep the replicas consistent). But content
entries are immutable-by-construction only via the NAMING function
(`Get-HashSizeFileName`) — with Mirror path-derived labels kept, the run-N+1
edit produces a label collision whose every resolution IS option 1, 2, or 3.
The split converts D-1 from silent overwrite into a detectable collision
(real honesty win), not into immunity. It does kill D-5, deletes the
overloaded blank-DataPath sentinel (strongest structural win), collapses
prune to per-key, trivializes mode migration — maintainability wins, ~10×
option 1's blast radius, and the naming decision still open at the end.
Trilemma: path-derived labels + cross-path dedup + no rewrite machinery —
pick two. Persisting today's derived `Get-BackupContentIndex` also converts
a cannot-be-stale view into stored state that can lie — D-1's own bug class.
Smallest honest version, if ever adopted (separately from the D-1 ruling):
store the three storage columns once per `(hash,length)`, drop `Duplicate`
as derived, keep `{hash,length}` on every logical row (never an opaque id),
content registry stays an accelerator over the pool scan, never authority.

**New facts settled by code reading (closes two "What was not proven" items
in the 2026-08-24 defect review):**
- **D-1 mechanism = (a), settled without the bench box.**
  `Save-SupersededData` builds `$survivingContent` from the SOURCE manifest
  (Engine.psm1:2996): B still holds hash H in the source, so the old bytes
  are declared surviving and never staged; the Mirror in-place overwrite
  (:2867) then destroys the last copy. The source-based survival test
  AUTHORIZES the loss; `Optimize-ChangeFolders` is aggravation, not cause.
- **`Reconstruct.ps1` shares D-2's gap** (Reconstruct.ps1:673-691 — expand/
  copy from a resolvable DataPath, no post-write hash check), matching
  `reconstruct.sh:645-698`. Restorer parity confirmed defect-for-defect.
- **Registry catalog confirmed: no persisted hash→file map exists** — the
  only content index is in-memory `Get-BackupContentIndex`
  (Engine.psm1:785-868), rebuilt from pool manifests + `Test-Path` per call;
  restorers resolve blanks by physical pool scan.

**Analysis note for the pending ruling (opus reviewer, disagreeing with the
driver's option-1 recommendation):** option 3's browsability cost is largely
fictional in production — under dedup the borrower's path has no file at all,
and under `CompressEnabled: true` (the bench config) the Mirror tree is a
tree of `.7z` archives; an optional regenerable materialized view restores
browsability under any option. Option 3 is mostly deletion (net-negative
LOC) and retires the dual addressing semantics that produced the defect;
option 1 stays defensible on blast radius. Emergency fix valid under ALL
options: survival test asks "does a live BACKUP row still demand this
content" instead of "is it still in the source", plus refuse to overwrite a
Mirror DataPath another live row references. **Decision remains with the
human (D-1 row above unchanged).**

### HUMAN direction (tentative) + DRIVER — D-1 leaning option 3 + materialized view; restorer parity approved — 2026-08-24

- **Restorer TargetRoot parity: APPROVED** ("yes it would be good to align
  the behavior") — recorded in the parked table; folds into the D-2/D-3 kit
  bump.
- **D-1 direction (NOT yet a ruling):** the human leans toward **option 3 —
  content-address all storage — with Mirror browsability recovered by a
  symlink-or-similar materialized view** ("keeps the actual data
  configuration consistent... best browsability out of the gate"), accepting
  that compressed content browses as `.7z` ("still where it was expected,
  just in a compressed form"). Open questions the human raised: does the
  view need reconstruction each run, and does it leak complexity into other
  paths. An opus design drill on the view mechanism (link tech per
  filesystem — NTFS privileges, exFAT's no-links problem on the actual
  HomeHub bench drives, ext4; lifecycle; pool-scan/restorer/prune/snapshot
  interactions; config surface) is in progress; final D-1 ruling to follow
  its report.

### HUMAN RULING — D-1/D-5 design: OPTION 3 — 2026-08-24

**Content-address all storage.** Mirror browsability becomes a best-effort
materialized view: links where the drive's filesystem supports them; where
it does not (exFAT), the user refers to the manifest — accepted explicitly.
Compressed content browsing as `.7z` links accepted explicitly. Rationale
(human's words): backup database consistency, prevents duplication, gives
readability where it can, deletes corner-case machinery. D-5 resolves with
it (content registry/live index makes intra-run dedup natural). The D-1/D-5
Open-items row updated to RULED. Scope details (view mechanism, config
surface, test-matrix reshape) come from the in-flight opus view-design
report; implementation runs as gated fix WPs with independent review
(engine + restore surface).

**Follow-on question opened by the human — infrastructure-filename
collisions.** Verified current handling: (a) source side — the hash cache
defaults INTO the source root (`Update-SourceManifest`,
Engine.psm1:416-417,432-438): with the in-source default, a genuine user
file named `MANIFEST.csv` at source root is silently treated as the tool's
cache (never backed up, overwritten by the cache) — only an external
`ManifestFolderPath` makes every source file data; (b) backup side, Mirror —
a Mirror DataPath landing on a root-level infra name is refused loudly
(SR-022, Engine.psm1:2861-2865; same guard on rename/re-home paths
:1143-1145, :1791-1792); (c) nested infra-named files are data everywhere
(B6, root-level-only skip). Under option 3 the backup-side collision class
DISSOLVES (hash-names — `<16 glyphs> <10 glyphs>.ext` — can never equal an
infra name; the SR-022 refusal and the B6 recovery hazard on the pool go
away), and can be made structural by giving the pool a dedicated subfolder.
The source-side cache collision does NOT dissolve — it is independent of
storage mode; candidate fix under no-backward-compat: stop defaulting the
cache into the source tree. Restore-target `RECONSTRUCT.log` name collision
noted as a residual nit. Decisions on pool subfolder + source-cache default
location: pending, to be packaged with the option-3 design WP.

### INDEPENDENT DESIGN REVIEW (opus subagent) — option-3 materialized view — 2026-08-24

Verdict: option 3 sound; **recommends shipping it with a generated INDEX
(single root-level INDEX.html + INDEX.tsv), NOT links initially** — a
measured partial pushback on the "links where supported" mechanism.
Grounds (all measured on real NTFS + real Linux this session):
- **Links don't exist on the deployment filesystem** (exFAT bench/production
  stand-ins), and NTFS symlinks need Developer Mode or elevation
  (`SeCreateSymbolicLinkPrivilege` not granted to Users by default) — so the
  fallback chain is needed on NTFS too. NTFS symlinks are unreadable from
  Linux; exFAT stub-file fallbacks waste ~61 GiB at 500k files (128 KiB
  clusters); rejected.
- **Full link-view regeneration doesn't scale:** 2,514 links/s measured ⇒
  ~5 min/run at 500k files on local SSD, 25–90 min on USB — which forces
  incremental maintenance, i.e. a FIFTH diff-driven bookkeeping site of the
  exact shape that produced D-1. Deciding argument. The index is one file,
  one pass, free to regenerate.
- **Hardlinks rejected three ways** (indistinguishable from real files to
  every scanner — creating one even flips the pool file's own LinkType;
  false candidates at every length in the restore pool scan; prune
  PhysicalBytes/reclaim accounting lies). Junctions can't express per-file.
Key design points settled: view lives OUTSIDE both roots as a same-volume
sibling (`<BackupPath>_View`, volume match enforced via Get-VolumeIdentity)
— zero exclusion edits across the six filesystem scans, both restorers keep
a zero-line diff (bash `find` without `-L` is already link-immune — pin as
intent; PS scan's symlink exposure is 0-byte-rows-only and benign); view is
purely manifest-derived (9-column contract untouched), rebuilt as new
pipeline step 16 (after Optimize), staleness via the existing manifest
witness stamped into the view root, explicit `-Action View`; snapshots get
NO view (prune accounting, staging rename, self-containment); view naming
driven by the row's `Compressed` column, not set config (Test-ShouldCompress
is per-file ⇒ mixed trees — likely implementation bug, pin in a test);
`PreserveFolderTree` deleted ⇒ ConfigVersion 2, `BrowseView: off|index`
(+`link` later) enum; **test matrix halves** (4 modes → ±Compress) + one
focused G10-View suite — freed budget goes to the test-battery import.
Browsability framing: today's Mirror OMITS the borrower's path entirely;
any view lists all N paths — strictly more faithful than Mirror ever was.
**Question for the human before the WP lands: what filesystem are the
production 12 TB disks?** ext4/NTFS makes `link` feasible later; ≲50k files
also voids the scaling objection. Enum grows without breakage either way.

**NEW FINDING (critical-at-scale, unrelated to the view):**
`Test-BackupManifest`'s unreferenced-file warning is **O(N²)** — `$db`
re-piped per on-disk file (Engine.psm1:566), called on EVERY backup via
Sync-BackupStorageLayout step 6 (Engine.psm1:618). At 500k files ≈ 2.5e11
pipeline comparisons — plausibly stops a real library from backing up at
all. Fix: one hashtable of referenced DataPaths (pattern already at
:761,:772,:1571). Fold into the option-3 WP.

### HUMAN RULING (final) — D-1/D-5 view mechanism: INDEX — 2026-08-24

The human confirmed the reviewer's index recommendation ("agreed with the
html index, that also gives searchability") and supplied the deployment
fact: **production disks are NTFS** — 4 TB library source, 6-or-8 TB backup.
NTFS keeps a later `link` enum value feasible; the ruled v1 is
`BrowseView: off|index`, index default. Ruling recorded in the D-1/D-5
Open-items row (now complete) and consolidated — together with the storage
design, config v2, deletions, emergency predicates, test reshape, and folded
items — into
**[plans/option3-content-addressed-storage-plan.md](plans/option3-content-addressed-storage-plan.md)**,
the pre-WP design record. AGENTS.md §3 gained a forward-pointer note (per
the 2026-06-05 precedent: §3 keeps documenting current code until the WP's
G3 rewrites it with the implementation). Next action: draft the option-3
WP's G1 requirements pass when the human says go.


### HUMAN — D-2/D-3 go, D-4 ruling, test-battery approval — 2026-08-24

Delivered in one message ("Spin up opus / sonnet agents as appropriate"):

- **D-2: GO** ("Sounds good") — verify-after-write in both restorers, kit
  revision 6.
- **D-3: GO** ("Agreed") — precedence reorder, batched with D-2.
- **D-4 RULED: hidden and dot files ARE backed up by default** ("Yes ideally
  hidden and dot files are backed up"), with the follow-up question "how does
  that affect the design?" — answered in the driver entry below.
- **Test-battery import: APPROVED and EXPANDED** ("Yes definitely, and expand
  it applicable to cover a larger test area"). The HomeHub drill script
  (`scripts/verify/library-permutation-drill.sh`, on another machine) was
  offered for local pull if the port needs the original.

### DRIVER (System Engineer + Data-integrity hats) — D-4 design impact of the include-by-default ruling — 2026-08-24

The ruling collapses D-4 to its simplest design — the decision REMOVES
machinery rather than adding it:

1. **No new config surface in v1.** Include-by-default means `-Force` on every
   `Get-ChildItem` in Engine/Common/Reconstruct (source walks, restore pool
   scan, prune residue scan) and nothing else. No `IncludeHidden` knob, no
   per-set policy, no skipped-by-policy accounting for hiddenness. Deliberate
   exclusion stays where it already lives (`ExcludeFolder` machinery — works
   for `.git`, `$RECYCLE.BIN` etc. if a user wants them out).
2. **The disclosure requirement narrows.** The proposed "skipped-by-policy
   count" now covers only the one remaining skip class: SR-055 portable-name
   skips, which already fail the set loudly. Nothing is silently skipped.
3. **Restorer parity converges for free.** bash `find` never skipped
   dot-files; PowerShell moving to `-Force` makes the twins agree with a
   zero-line bash diff on the walk itself.
4. **It closes an adjacent latent hazard beyond the source walk:**
   hash-addressed short names can BEGIN WITH A DOT (the exact shape that broke
   CI artifact upload on 2026-08-23), and any pool file carrying a Hidden
   attribute is invisible to today's PS pool scan — a dot/hidden data file in
   the pool is unrecoverable by hash until `-Force` lands on the restore side
   too. The ruling fixes backup and restore blind spots symmetrically.
5. **New backup content classes, accepted:** Windows noise files
   (`desktop.ini`, `Thumbs.db`) and macOS `.DS_Store` now enter backups by
   default — data-safety bias, README note + ExcludeFolder pointer. System-
   attribute files also surface; reparse-point/symlink traversal semantics are
   NOT changed by `-Force` (existing behavior stands; pin as intent).
6. **Interactions:** root-level infra files are excluded by NAME allowlist,
   not attribute — unaffected. Option-3 WP: no conflict; the `-Force` walk
   survives content-addressing unchanged. Windows-reserved-device-names parked
   item folds into the same walk change as planned.

Session note: this session runs on macOS (no pwsh/bats/shellcheck) — per
"never report a green you didn't run", this session delivers the kit-bump WP
plan + G1/G2 registry passes (trace.py-verified here); G3 implementation and
the full battery are staged for a Windows host session, per the bash-variant
executing-agent precedent.

### DRIVER (System + Test Engineer hats; opus plan subagent + sonnet registry subagent) — kit-bump WP: plan + G1/G2 registry pass — 2026-08-24

Executed on macOS (docs/registries only — no code, no test runs possible here).

**Plan (opus subagent, driver-reviewed):**
[plans/kitbump-rev6-plan.md](plans/kitbump-rev6-plan.md) — pinned D-2 verify
contract (Length+xxH2Hash after every write, one pool-recovery retry, new
`ContentMismatch` cause into SR-029 accounting); D-3 implemented as an honest
RECLASSIFICATION (the locators' `CandidateError` becomes unreachable once
ContentMissing outranks it, so the return set shrinks: expand-failures are
data damage ⇒ ContentMissing, read-failures ⇒ new `StorageUnreadable` host
class; the restore loop's own-file CandidateError stays exit 4 — the "both
locators" phrasing must NOT be applied there); all NINE `Get-ChildItem`
sites enumerated for the `-Force` sweep; TargetRoot `-NonInteractive` guard
(exit 2 + usage); kit revision 6 stamping; 10 commit-ordered work items;
Windows-host baseline preamble + acceptance checklist. Driver ratifies the
agent's two judgment calls: reserved-device-names IN (deferrable, open
question), manifest-row-order OUT (option-3 plan owns Write-Manifest).
Two knowingly-red-test traps caught and re-scoped: G2.8 becomes a MODE-AWARE
exact assertion (a strict single-DataPath assert would be red on Mirror until
option-3 lands — D-5 is option-3's fix); floor item 1's Mirror owner-edit
arms (the D-1 shape) likewise belong to the option-3 WP — this WP lands the
HashAddressed regression-guard arms.

**G1/G2 registry pass (sonnet subagent, driver-verified):** minted SN-033,
SR-056 (restore verifies bytes written), SR-057 (hidden/dot/system captured
at every enumeration site), LLR-056/057, TC-108..116; dated amendments to
SR-040/016/029/001/007, LLR-040/050/016, TC-019 (statuses unchanged — the
flips happen with the code at the Windows G3). Deviation from plan §5,
recorded: SR-056/057 carry **Phase=kitbump-v6** (bash-v1 precedent) so the
G3 ratchet stays clean pre-implementation. TC-117 + the SR-055 reserved-name
amendment NOT landed (open question). Evidence (real, this host):
`trace.py --strict` → SN=33 SR=57 LLR=56 TC=115, 0 orphans / 0 integrity;
`--require-verified --phase core,bash-v1,container-v1` → 0 status-findings,
phase-deferred=3 (SR-033 + SR-056/057, as designed).

**Registry-hygiene defects found (pre-existing) and repaired, driver-verified
by field-level dump before touching:** SR-040's row was MISSING its
AcceptanceCriteria field entirely — every later column sat one slot left
(true Status slot blank, `Verified` in Verification, `Test` in Priority);
field restored with a written acceptance criterion and the shift note.
TC-024 carried three unquoted commas in Expected (12 fields against the
9-column header); re-quoted, `Yes,Pass` back in their columns. All three
CSVs now length-validate row-for-row; trailing newline preserved.

**Open questions for the human (plan §11, needed before/during the Windows
G3 — none block the option-3 WP):**
1. SN-033 minted (driver call) — veto if you'd rather SR-056 hang off
   SN-005/006/026 alone.
2. Reserved device names (CON/NUL/COM1…) into SR-055's refusal in this WP —
   currently IN per plan; costs: a Linux source holding `NUL.txt` starts
   failing the set loudly. Confirm or defer.
3. Verify-after-write ships with NO opt-out (it roughly doubles restore read
   volume). Driver recommends: no opt-out — restores are rare, this is the
   data-safety product's core promise. Confirm.
4. G2.8's Mirror arm asserts today's duplicate-copy truth as a labelled
   change-detector until option-3 deletes it. Confirm.
5. Restored files come back WITHOUT Hidden/System attributes (the 9-column
   schema has nowhere to record them; adding a column breaks the §3
   invariant). Driver recommends: accept + document in README. Confirm.

**Next:** Windows-host session executes the plan §4 work order (G3 +
independent review); registry flips (SR-056/057 → Verified, ratchet gains
`kitbump-v6`) land with the real green battery.

### DRIVER (Software + Test + Data-integrity hats) — kit-bump WP G3 — 2026-08-24 (Windows host)

Verdict: implemented + validated end-to-end on this Windows host; independent
review to follow (mandatory, restore surface). Executed
[plans/kitbump-rev6-plan.md](plans/kitbump-rev6-plan.md) §4 work items 2–9 as
eight commits, one green commit each (37af918 D-3; 0670c9b D-2 PS; 018dff8
D-2 bash; b4d8eff TargetRoot parity; 3c83bd5 D-4; 9f082e7 test battery;
763b46c kit revision 6; registry closure with this entry).

**Baseline reproduced first** (plan §7): unit 341/341 · integration 372/0/4 ·
bats 56/56 · shellcheck clean · trace 0/0/0 (phase-deferred=3) — exactly the
2026-08-23 floor.

What shipped (all per the pinned plan; no storage-path file touched):
- **D-3 (reclassification, §2.1a):** both locators' return set is now
  `Found | DependencyMissing | StorageUnreadable | ContentMissing`; an
  unexpandable pool candidate travels inside ContentMissing's detail (exit 1,
  candidate named); an unreadable candidate is StorageUnreadable (exit 4);
  the no-7z double record collapsed to one cause (§2.1b). The restore loop's
  own-file CandidateError stays exit 4. Two WP5-era pins asserting the old
  host classification updated (Pester + bats), as the ruling requires.
- **D-2 (verify-after-write):** one write+verify implementation per restorer
  (`Restore-OneRow` / `restore_one`) — Length first then xxH2Hash of the
  DESTINATION, every row including hash-recovered ones; on mismatch the bad
  file is deleted and the (hash,length) recovery runs at most once, verified
  again; final failure = content-class `ContentMismatch` into the SR-029
  accounting. Recovery-time DependencyMissing/StorageUnreadable pass through
  as host class (driver refinement, recorded: truthful and SR-040-consistent).
- **TargetRoot parity:** `-NonInteractive` (+ redirected-stdin defense) →
  `Show-ReconstructUsage` + exit 2, mirroring `reconstruct.sh` usage
  parameter-for-parameter; interactive prompt kept.
- **D-4:** `-Force` at all nine enumerated sites with per-site why-comments;
  AST anti-regression guard (no `Get-ChildItem` without `-Force` in
  Engine/Common/Reconstruct/FileBackup.ps1); bash `find` no-skip and no `-L`
  pinned as intent; README disclosure incl. attributes-not-preserved.
- **Test battery (floor + expansion):** TC-108/109 damage matrix both
  restorers; TC-110 damaged-store interop (heal=0 / gone=1 verdict + byte
  parity, proven locally Windows→WSL; CI cross-artifact proof lands on push);
  TC-111/112 exit-code honesty; TC-113 G5.8 hidden/dot end-to-end ×4 modes;
  TC-114 site probes; TC-115 parity; TC-116 `tests/Common/PoolAudit.ps1` —
  the byte-verified orphan second pass (the assertion that caught D-1) wired
  into G2/G3/G9/G9Prune; G2.8 de-vacuumed mode-aware-exact (Mirror arm = the
  labelled D-5 change-detector, per §6.4).
- **Kit revision 6** stamped in both restorers together; README + AGENTS.md
  §3 updated; D-1/D-5 forward-pointer intact.

Evidence (real output, this host): `check.ps1 -Tier Full` → lint PASS ·
trace PASS · docs PASS · map PASS · Pester unit **357/357** · integration
**412 PASS / 0 FAIL / 4 SKIP** → "All steps passed" (the one lint failure
along the way — two empty-catch diagnostics in new PoolAudit.ps1 — was fixed
and re-proven in 763b46c). WSL Fedora: `shellcheck` clean, `bats tests/bash/`
**64/64** with an explicit exit-code check. `trace.py --strict
--require-verified --phase core,bash-v1,container-v1,kitbump-v6` →
`SN=33 SR=57 LLR=56 TC=115, 0 orphans / 0 integrity / 0 status-findings /
1 phase-deferred` (SR-033 only). Registry closure: SR-056/057 → Verified,
LLR-056/057 → Implemented, TC-108..116 + TC-019 → Pass; ratchet re-armed
with `kitbump-v6` in check.ps1 + CI.

Findings recorded along the way (honesty items):
- [PROCESS] My first "bats 58/58" claim after the D-3 commit was wrong — a
  `| tail` pipe masked bats' exit code and hid the flipped TC-099 pin; fixed
  the pin in 018dff8 and every later bats invocation checks the exit
  explicitly. Lesson recorded here per "never report a green you didn't run."
- [DOC] **The `ExcludeFolder` "deliberate exclusion machinery" named in the
  D-4 ruling entry does not exist as user configuration** — it is a
  prune-internal parameter. No exclusion key exists at all. README now states
  the truth (exclusion = scoping `SourcePath`); SR-057's wording corrected at
  closure (dated). If the human wants a real exclusion setting, that is new
  scope for a future WP.
- [TRANSIENT] One full-sweep run crashed Mirror/G9 with a
  `Backup_Global.log` file-lock collision; did not reproduce across three
  later full sweeps (results.csv detail preserved in the D-4 commit message).
- [SCOPE] **Reserved device names (plan open question 2) DEFERRED**, not
  implemented: the plan author leaned IN, but the registry pass withheld
  SR-055/TC-117 pending the human's answer and it adds a new refusal class
  (a Linux source holding `NUL.txt` starts failing loudly) — under the HIGH
  dial that ships only with an explicit ruling. Cheap either way; still open.
- [SCOPE] Committed bats fixtures NOT regenerated: the fixture sources hold
  no hidden/dot files, so the D-4 walk change cannot alter them; regeneration
  stays deterministic and untouched.

Plan §11 open questions, status after this G3: (1) SN-033 minted — veto still
possible; (2) reserved names — **still needs the ruling** (deferred, above);
(3) verify-after-write shipped with NO opt-out as recommended — confirm;
(4) G2.8 Mirror change-detector arm shipped as recommended — confirm;
(5) restored files come back without Hidden/System attributes — shipped +
README-documented as recommended — confirm.

**Next:** independent reviewer pass (fresh context, adversarial, restore
surface — plan §4 item 10), then human ratification of this G3.

### INDEPENDENT REVIEWER (opus subagent) — kit-bump WP G3 — 2026-08-24

Verdict: **CHANGES-REQUESTED** (2 BLOCKER, 3 MAJOR, 5 MINOR) — while
confirming the WP does what it claims (all shipped greens re-ran and
reproduced: unit 357/357, bats 64/64, targeted Run-All G2/G3/G5/G9 272/0
incl. every new audit assert; storage path verified untouched by
`git diff 4ec589c..HEAD`; no in-process caller can reach the prompt).
Findings, all with real repros:
- [BLOCKER 1] `-Force` on the source walk turned an unlistable hidden/system
  directory (Deny ACE — the `System Volume Information` shape) from
  silently-invisible into a WHOLE-SET abort with **no manifest written** —
  worse than rev 5 for a drive-root source.
- [BLOCKER 2] The D-3 locator folded EVERY expand failure into
  ContentMissing — including a broken/unrunnable 7-Zip, where the same store
  restores fine once 7-Zip works: "your bytes are gone" (exit 1) asserted
  falsely for a host fault rev 5 classified correctly (exit 4).
- [MAJOR 3] A mismatch on a locator-HASH-PROVEN source was content-class
  exit 1, though the pool demonstrably holds the bytes (a write problem →
  host class). [MAJOR 4] bash `restore_one` treated a destination READ-BACK
  failure as a mismatch — false data-loss verdict AND deleted the restored
  file, diverging from the PS twin. [MAJOR 5] the SR-056/LLR-056 text
  ("recovery attempted once for any mismatch") did not match the implemented
  zero-recovery-for-locator-resolved-rows refinement, and only part of the
  deviation was recorded.
- [MINOR 6..10] TC-116 named a function that does not exist
  (`Assert-BlankRowsBackedByVerifiedHashes` vs the shipped
  `Get-BlankRowPoolViolations`); malformed `Length` handled differently by
  the twins (PS refuses class 2, bash restored unverified exit 0);
  `-NonInteractive` without `-ExitCode` delivered the usage failure as
  process exit 1 (the data-loss code); `scripts/Invoke-Container.ps1`
  enumerations lacked `-Force` and sat outside the AST guard;
  `verify_damage_interop.sh` did not assert the absence of extra files.

### DRIVER — kit-bump WP G3 round 2: all review findings fixed — 2026-08-24

Verdict: all 10 findings addressed; full battery re-run green. Fixes:
- **B1:** `Get-DataFile`/`Update-SourceManifest` gained `-EnumerationErrorOut`
  / `-UnreadableOut` (the SR-055 pattern): an unlistable directory is
  reported, the SET FAILS LOUDLY (exit 1) with a per-directory ERROR naming
  the remediation, everything reachable is still backed up, the manifest is
  written, and rows under the unreadable path are FROZEN (not evicted — the
  walk saw nothing there, which is not evidence of deletion). Pool walks
  (no sink passed) stay strict. Test: Deny-ACE hidden+system dir → exit 1 +
  manifest written + reachable row present + "Cannot enumerate" logged.
- **B2:** `Test-SevenZipUsable` / `sevenzip_usable` — a cached compress+
  expand self-test. An expand failure is data damage (ContentMissing detail,
  exit 1) only when 7-Zip PROVES usable; an unusable 7-Zip is
  DependencyMissing (exit 4) with the candidate named as untested. The
  "data damage, not a host problem" detail wording replaced with the honest
  self-test statement. Tests: fake-7z stores exit 4 with "not usable on this
  host", both restorers.
- **M3:** new HOST-class cause **WriteMismatch** (both restorers, exit-code
  docs updated): a mismatch whose source was hash-proven by the locator —
  first-attempt on a recovered row, or the post-recovery verify — reports
  the write problem it is, not data loss.
- **M4:** bash `restore_one` rc=22 — read-back failure is host-class
  (CandidateError log) and KEEPS the file, matching `Restore-OneRow`.
  White-box bats test (broken `hash_file` → rc 22, file present).
- **M5 + minor 6:** SR-056/SR-040/LLR-056/LLR-040 amended (dated) to the
  implemented semantics incl. WriteMismatch and the self-test; TC-116
  renamed to the shipped `Get-BlankRowPoolViolations`.
- **Minor 7:** bash refuses a non-empty non-numeric `Length` as a
  PRECONDITION (exit 2) before writing anything, matching the PS class;
  bats test. **Minor 8:** `-NonInteractive` without `-ExitCode` now exits
  the process with 2 (documented: `-NonInteractive` declares a scripted
  caller); test. **Minor 9:** `scripts/Invoke-Container.ps1` enumerations
  gained `-Force` and the file joined the AST guard list. **Minor 10:**
  `verify_damage_interop.sh` asserts file-count parity (no extras).

Evidence (real output, this host, post-fix): RestoreVerify.Tests
**19/19**; WSL bats **67/67** (+3), shellcheck clean incl. the interop
verifier; `check.ps1 -Tier Full` → unit **360/360**, integration
**412 PASS / 0 FAIL / 4 SKIP**, all steps green after regenerating the
architecture map (the only red was map staleness from the Get-DataFile
signature); `trace.py --strict --require-verified --phase
core,bash-v1,container-v1,kitbump-v6` → 0 orphans / 0 integrity /
0 status-findings / 1 phase-deferred. Not automatable: a true
WriteMismatch repro (write-side corruption of a proven source) — the
classification logic is covered by code path review; recorded as a
residual for any future harness with fault injection.

**Awaiting human ratification of this G3** (with the reviewer's
CHANGES-REQUESTED now answered) — plus the standing plan §11 items:
Q2 reserved-device-names ruling; confirmations for Q1/Q3/Q4/Q5.

### SECOND INDEPENDENT REVIEW (OpenAI gpt-5.6-terra, medium effort, via codex exec, human-directed) — kit-bump WP — 2026-08-25

Verdict as delivered: **3 findings, all P1, no P0** (adversarial charter over
`git diff kitbump-base...HEAD`, the whole 10-commit batch):
- **T1 (VALID, fixed):** bash `find_by_hash` silently treated an UNREADABLE
  raw pool candidate as absent — `hash_file` failure fell through to
  non-match, so a blank row whose only copy is unreadable reported
  ContentMissing/exit 1 ("your bytes are gone") for a host problem;
  Reconstruct.ps1 already said StorageUnreadable/exit 4. Fixed at all three
  raw-hash sites (single-record, PS parity); the "recorded asymmetry" note
  in the locator header and LLR-040 replaced with the implemented arm.
- **T2 (VALID, fixed):** BOTH restorers suppressed a snapshot-TREE listing
  failure (`-ErrorAction SilentlyContinue` / `2>/dev/null`) — an unlistable
  change root silently shrank the recovery pool to the backup root, turning
  "host cannot list the snapshots" into exit 1. Fixed: the unlistable root
  itself joins the search list, so the locator's own readability check
  surfaces StorageUnreadable/exit 4, both restorers.
- **T3 (DECLINED, recorded):** a TOCTOU — pool file replaced between the
  locator's hash-proof and the copy is classified WriteMismatch/exit 4
  without a second search, though on a then-quiescent store the truthful
  verdict might be exit 1. Declined: the store carries no concurrent-writer
  guarantee, nothing wrong is left on disk (the mismatched destination is
  deleted), and exit 4's retry semantics CONVERGE to the truthful verdict on
  a quiescent store — while a second search would reopen the ambiguity the
  first independent review's major 3 closed. Revisit only if a
  concurrent-access guarantee is ever added.

Evidence (real, this host): bats **69/69** (+2: unreadable candidate ⇒ 4;
unlistable snapshot tree ⇒ 4 with a listable-tree heal sanity arm),
shellcheck clean; RestoreVerify.Tests **20/20** (+1 PS unlistable-tree
test via Deny ACE); trace 0/0/0 (phase-deferred=1). Full tier below.

### HUMAN — kit-bump WP G3 RATIFIED + full-solution directive — 2026-08-25

Verdict: **APPROVE / RATIFIED** ("I will give you my blessing to consider
ratification done"). Standing directive recorded verbatim in intent:
- **No more ratification pauses for the queued work.** "Everything that is
  queued to be addressed and fixed should be fixed, without any arbitrary
  ratification bars, so that a full solution can be implemented, tested,
  and handed off to HomeHub for actual hardware-in-the-loop testing."
- **HomeHub HOLDS until the full solution is ready** — it must not build an
  incomplete FileBackup.
- Driver reading of scope, recorded: the option-3 WP (D-1/D-5
  content-addressed storage, Mirror/PreserveFolderTree removal, INDEX view,
  config v2) plus its folded items (O(N²) unreferenced-file scan, manifest
  row order, DataPath-keyed map sweep) and the previously-deferred plan §11
  Q2 (reserved device names — now IN); the blanket ratification also covers
  Q1/Q3/Q4/Q5 as shipped. The independent-review step is retained (it is a
  quality bar, not a ratification bar, and it caught real blockers twice);
  gate EVIDENCE keeps being recorded here as always.

### DRIVER — WP9 (D-1/D-5 content-addressed storage) work order — 2026-08-25

Verdict: **plan drafted, no code touched.**
[plans/wp9-content-addressed-storage-workorder.md](plans/wp9-content-addressed-storage-workorder.md)
turns the ruled option-3 design into an executable work order, pinned and
line-verified at `553638c` (18-row grounding table). Ids allocated: SN-034,
SR-058..SR-064, LLR-058..LLR-064, TC-118..TC-134, plus TC-117 and the
SR-055/LLR-055 amendment for the reserved-device-names item this session's
ratification moved IN.

Three things the design record did not have, all from reading the code this pass:
- **The view does not scale as ruled.** One `INDEX.html` over ~500k rows is
  ~100 MB of markup, regenerated every run. Proposed: `INDEX.tsv` always +
  per-folder HTML pages + root search under a 50k-row threshold — the ruling's
  intent (browse + search, no links) at library scale. **Veto-flagged: it
  refines a mechanism the human chose personally.**
- **Migration must verify before it names.** An existing Mirror store may
  already hold D-1 damage; renaming those bytes to a content-addressed name
  would poison the pool permanently (every future hash recovery finds a file
  whose name lies). Migration hashes first, blanks + reports a mismatch, and so
  doubles as the first honest audit of the damage already on disk.
- **Migration must rename, not copy.** B7's copy-then-delete demands a second
  full copy, so `Get-MigrationCapacityDemand` + `Assert-BackupCapacity` would
  (correctly) refuse to convert a 4 TB store on a 6 TB disk. A same-volume
  rename costs ~0 and is crash-safe by construction — the renamed file is
  self-identifying.

Driver decisions recorded (§9, each open to veto under the standing directive):
flat pool root (no `pool/` subfolder — hash-name grammar already kills the
collision family); 9-column manifest untouched with `StoredAsHashSize` frozen at
`'Hash'`; owner-election replaces Sync's form-conflict skip;
`Save-SupersededData` moves after the copy/evict steps so its survival test is
exact; `BrowseView` defaults `off` with `index` in the shipped examples;
`PreserveFolderTree` refused **by name in CLIXML too** (it is exempt from the
closed schema, so it would otherwise be silently ignored); source-side manifest
cache default stays out of this WP.

**Next:** WP9 G1 (registry rows + SN-008 rewrite), then G2, then the ordered G3
steps — all on a Windows host.

### HUMAN — WP9 design rulings — 2026-08-25

Two rulings on the WP9 work order's §9:
- **Q1 view shape: APPROVED.** "Agreed, I did not think of file expansion, your
  recommendation sounds much more reasonable." WP9 ships `INDEX.tsv` always +
  **per-folder** `INDEX.html` pages + root search under a 50 000-row threshold,
  instead of one flat ~100 MB page. The 2026-08-24 HTML-index ruling stands;
  this is its scaling shape.
- **Q4 migration: MOOT.** "No storage exists currently here that must be
  maintained." The `Original → Hash` conversion is **deleted, not kept**;
  `Sync-BackupStorageLayout` keeps only its compression-flip axis; a manifest
  row carrying `StoredAsHashSize = 'Original'` fails the backup set before any
  mutation, naming the fresh-`BackupPath` remedy, while `-Action Verify` still
  reports it as a finding (an audit that cannot audit is useless). Both
  restorers still read a legacy store unchanged.

Consequences recorded in the work order: the verify-before-name and
rename-not-copy requirements disappear with the migration they protected, WP9
step 3 shrinks to a deletion plus one refusal, `Get-MigrationCapacityDemand`
keeps only its compression term, risks R1/R2 are replaced, SR-061 and TC-124 are
rewritten, and `tests/fixtures/bash-restore/Mirror*` is regenerated or deleted at
step 5 (`scripts/gen_bash_fixtures.ps1`).

### DRIVER — WP9 priming + surface-doc sweep — 2026-08-25

Verdict: **the WP9 test/requirement rows are now in the machine source of truth;
no code touched.** The human asked how to make sure the not-yet-ported drill
permutations cannot get lost. The repo already had the mechanism — the same one
`bash-v2` has used since 2026-07 — so it was used rather than invented:

- **SN-034, SR-058..SR-064, LLR-058..LLR-064, TC-117..TC-135 are committed**,
  with the SRs tagged `Phase=ca-v1` (`Status=Draft`), LLRs `Planned`, TCs
  `Draft`. `trace.py`'s **orphan rules are phase-blind**, so every one of those
  SRs already carries its LLR and TC rows and cannot be dropped silently; the
  G3 ratchet (`--require-verified --phase core,bash-v1,container-v1,kitbump-v6`)
  reports them as phase-deferred instead of demanding Verified. **When `ca-v1`
  is appended to the ratchet in `scripts/check.ps1`, every one of these rows
  must be Verified/Pass or the gate fails** — that is the anti-loss guarantee.
- Evidence (real output, this host): `trace.py --strict` →
  **SN=34 SR=64 LLR=63 TC=134 orphans=0 integrity=0**; with the ratchet →
  **status-findings=0 phase-deferred=8** (SR-033 bash-v2 + the seven `ca-v1`
  rows). `check_docs.py` → 0 broken links.
- The three drill permutations with no FileBackup equivalent are now
  **TC-118** (owner-edit / edit-the-borrower / multiple-borrowers, run as one
  timeline), **TC-119** (same-run duplicates) and **TC-135**
  (owner-deleted-while-borrower-lives — B9's eviction refcount, which has no
  named test today; only the migration-side SR-051 refcount is covered).
  TC-117 carries the reserved-device-names rule ruled IN on 2026-08-25.

Surface-document sweep (the second half of the request):
- **`docs/release-checklist.md` was STALE** — generated 2026-08-23, so it was
  missing SN-031, SN-032 and SN-033 entirely. Regenerated; now SN=34.
- Open items: the D-1/D-5 row and the test-battery row rewritten to the current
  state; the **D-2/D-3/D-4 rows** (ratified, closed) plus the parked
  `no-7z double host record` and `restorer TargetRoot parity` rows moved to
  [resolved-items.md](resolved-items.md); the decisions table retitled, since
  under the standing directive nothing in it awaits a human answer.
- **F8 (kit-less snapshot window) FOLDED into WP9** step 8 (driver call under
  the standing full-solution directive): copy the kit into staging before the
  `Temp`→`Snapshot_*` rename. It is a real, if narrow, integrity gap and WP9
  already opens that neighbourhood.
- `START_HERE.md`'s brief no longer promises "the four storage modes" without
  qualification. `AGENTS.md` / `README.md` deliberately still describe Mirror:
  they document shipped behavior and change at WP9 G3, per the option-3 record.

**Remaining queue after this pass:** WP9 (with the folded items) → IF-001
Experimental→Stable jointly with HomeHub → G-Release (attestation + the
regenerated checklist + version bump) → G-Final. Phase-deferred by design:
SR-033 (bash-v2). Still deliberately parked: `-RepairFromPruned`, the
source-side manifest cache default, the two-registry normalization, the `link`
view.

### HUMAN — S2 ruling: no retroactive re-forming, either direction — 2026-08-25

Verdict: **GO, and it folds into WP9.** "Retroactive space reclamation is not
necessary, that could be housed as a separate script that can sit deferred.
Similarly, retroactive decompression is also not necessary."

Consequence: `Sync-BackupStorageLayout` (210 lines) and
`Get-MigrationCapacityDemand` (50) are deleted **whole** in WP9 step 3, with the
step-5.5 migration capacity preflight and the SR-051 refcount apparatus that
existed only to make a migration safe. `CompressEnabled` becomes a rule for NEW
content only.

Driver note recorded at the ruling: **S2 does not depend on S1.** A mixed-form
store is already normal today — compression is per-file (`Test-ShouldCompress`
keys on extension, SR-004), so a store built under one config already holds both
`.7z` and raw objects, and every row's `Compressed` column describes its OWN
object. Both restorers branch per row, Verify audits per row, and prune's
re-home carries the form with the bytes. Nothing reads a store-wide form, so
nothing needs re-forming. WP9 therefore gets SMALLER, not bigger: step 3 turns
from "delete one axis, keep the other" into a straight deletion, and deleting
`Sync` also collapses two overlapping orphan scans (its own and
`Test-BackupManifest`'s) into the single one SR-064 makes linear.

Registry: SR-061 widened to carry the no-migration contract; LLR-060 retargeted
from `Sync-BackupStorageLayout` to `Test-BackupManifest`/`Invoke-BackupSet`;
TC-124 now pins that a `CompressEnabled` flip re-forms nothing and that the
resulting mixed-form store audits CLEAN. SR-012/SR-013/SR-051 are superseded by
SR-061 — their amend-vs-retire disposition is settled at WP9 G1 and recorded, so
no Verified SR is silently dropped. Trace after the edits: orphans=0 integrity=0
status-findings=0 phase-deferred=8.

### DRIVER — WP9 step 1: D-1/D-5 repros land (TC-118, TC-119) — 2026-08-25

Verdict: **step 1 complete, suite green.** No engine code touched yet.

Landed:
- **`Get-ClaimedRowViolations`** in `tests/Common/PoolAudit.ps1` — the detector
  D-1 actually needed. Every existing check asks whether a row's file is
  PRESENT; D-1 leaves it present and changes its BYTES, so `Test-Path`,
  `Test-PoolResolves` and a non-`-Deep` Verify all sail past it. The new helper
  proves every non-blank row's own DataPath reproduces that row's
  `(hash,length)`, deriving form from the bytes (hash raw first, expand only on
  failure) rather than trusting the `Compressed` column — S1's rule, applied
  early where it is free.
- **Two contract Describes** (content-addressed modes) plus a **change-detector
  Describe** asserting that both defects reproduce under Mirror, following the
  `G2.8` convention so the suite stays green per commit rather than carrying a
  known-red test through four steps. The change-detector block is deleted whole
  with the mode at step 5.

**Finding, recorded in TC-118 and in the helper's `.NOTES`: a second same-run
copy MASKS D-1.** The first repro used two identical files in run 1 and a third
borrowing later — and the defect did not fire. With more than one prior copy the
borrower's adopted DataPath may name the untouched sibling, and even when it
names the edited file the surviving sibling keeps the content alive. **D-1
requires the borrowed-from file to be the ONLY prior holder of the content** —
i.e. a duplicate PAIR where one member is edited, which is exactly the review's
real-world examples (a photo in two folders, a document and its pre-edit copy,
an installer kept in two places). Three-or-more copies are self-protecting by
accident. This is why the bench drill only saw it at cycle 10. The two timelines
are therefore kept SEPARATE (`New-BorrowTimeline` for D-1,
`New-SameRunDuplicateStore` for D-5); folding them back together silently
destroys the repro.

Evidence (real output, this host): `Invoke-Pester tests\Unit\Coverage.Tests.ps1`
→ **176 passed / 0 failed**, with the asymmetry that makes the tests meaningful:
borrower survives the owner edit on HashAddressed ±Compress and is LOST on
Mirror ±Compress; one physical object same-run on HashAddressed, two on Mirror.

### DRIVER — WP9 steps 2 and 3 — 2026-08-25

Verdict: **both committed green.** Full reasoning is in the commit messages
(`9a1da7d`, `3ac3338`); recorded here so a fresh session sees progress without
reading the log.

**Step 2 — owner election + intra-run memo (`9a1da7d`, SR-060, TC-120).** A
`(hash,length)` group elects an OWNER (shortest RelativePath, **ordinal**
tie-break so the stored object cannot depend on host locale) whose extension and
compression answer define the single stored object; the first member writes it
and the rest adopt it from an in-process memo. Two restraints worth keeping in
view: the memo is deliberately **NOT** applied to Mirror — there each member's
DataPath is its own RelativePath, so pointing several rows at one member's path
is exactly the cross-path borrow that produces D-1, and applying it would
manufacture fresh D-1 hazard in a mode about to be deleted; and `ChangedCount`
still counts logical files, so the run's "changed files" figure keeps its
meaning. Evidence: unit **371/371**.

**Step 3 — migration deleted whole (`3ac3338`, SR-061).**
`Sync-BackupStorageLayout` (210 lines) + `Get-MigrationCapacityDemand` (50) +
the step-5.5 migration preflight + the SR-051 refcount apparatus. Step 6 calls
`Test-BackupManifest` directly, collapsing two overlapping orphan scans into the
one SR-064 will make linear. Evidence: `-Tier Full` all steps passed, unit
**364/364**, integration **416/0**.

**The finding worth carrying forward.** Deleting the migration broke NO
guarantee — it broke four *fixtures* that had been quietly depending on
migration to do something for them: `New-FlipTimeline` (the only "no-tampering"
way to make a form disagreement), two SR-046 prune-rail tests, the SR-052
status-1 capacity test, and G4.2's pre-merge store. The last is the sharpest:
that fixture called itself "genuinely well-formed" while converting only the
backup root, leaving snapshot blank rows claiming `Compressed=No` for content
whose pool copy was now `.7z`. `-Action Verify` was right to report
`BlankRowFormDisagreement`; the migration had been re-aligning the fixture's own
inconsistency on the next run, so nobody ever saw it. And one test —
`prunes a compression-flipped store` — had already gone **VACUOUS** and was
passing while asserting nothing. **This is D-1's own shape at the test layer: a
derived fact quietly re-aligned behind your back, so the underlying
inconsistency stays invisible.** Every fixture was re-plumbed to construct its
state directly rather than deleted, so no assertion was lost, and each carries a
`.NOTES` saying the construction is deliberate.

Also proven incidentally, and reassuring: every restore stayed byte-exact
THROUGH that disagreement, because SR-050 makes both restorers trust the located
file's proven form over the row's `Compressed` claim. The audit reports the
inconsistency; the restore is immune to it. (That is S1's thesis, demonstrated
without S1 being implemented.)

### DRIVER (Software + Test + Data-integrity hats) — WP9 G3 COMPLETE: content-addressed storage — 2026-08-25 (Windows host)

Verdict: **WP9 is done, all nine steps committed green on `New_Fix_Batch`.**
D-1 and D-5 are fixed by **deleting their hazard class**, exactly as the
2026-08-24 human ruling (option 3) directed. Per-step reasoning lives in the
commit messages; this entry is the WP-level record, following the kit-bump
precedent of one G3 entry with the detail in the commits.

| Step | Commit + what landed | SRs |
|---|---|---|
| 1 | `e302593` — D-1/D-5 repros + `Get-ClaimedRowViolations` — the detector D-1 needed: every row's own DataPath must reproduce that row's `(hash,length)` FROM BYTES. D-1 leaves the file PRESENT and changes its bytes, so `Test-Path`, `Test-PoolResolves` and a non-`-Deep` Verify all sail past it. | SR-059, SR-060 |
| 2 | `9a1da7d` — owner election + intra-run memo in `Invoke-BackupFileGroup` | SR-060, SR-003 |
| 3 | `3ac3338` — `Sync-BackupStorageLayout` + `Get-MigrationCapacityDemand` deleted whole (~260 lines); step 6 calls `Test-BackupManifest` directly | SR-061 |
| 4 | `b6077b8` — `Save-SupersededData` reordered after copy/evict; survival tested against the FINAL manifest | SR-059, SR-051 |
| 5 | `44deeb5` / `cce8855` / `891e8ad` — **Mirror deleted** — `PreserveFolderTree` out of the engine, config, schema, docs and fixtures; hash naming unconditional; `StoredAsHashSize` pinned `'Hash'`; the SR-061 legacy-store refusal + the `LegacyStoredForm` Verify finding implemented | SR-058, SR-061 |
| 6 | `78d6ddb` — config **v2**: `ConfigVersion` 2, a named refusal for `PreserveFolderTree` in BOTH formats, `BrowseView`/`ViewPath` with placement rails | SR-063 |
| 7 | `65cbc07` — the browse view: `New-BrowseViewIndex`, pipeline step 16, `-Action View`, `Resolve-ViewRootPath` rails | SR-062 |
| 8 / 8b | `9f2931a` — linear unreferenced-data audit; canonical manifest writes; **F8** (kit copied into staging before the publish rename); the n6 directory-destination guard; reserved device names | SR-064, SR-055 |
| 9 | `6184471` — this step: the remaining TC-118/TC-122/TC-135 arms, the registry reconciliation, AGENTS.md §2/§3/§6, README, IF-001, and the `ca-v1` ratchet | — |

**Step 9's test work — the arms that were impossible while Mirror existed.**
TC-118 now runs its full matrix: `edit={owner,borrower} × copies={2,3} ×
compress={on,off}`, eight arms over a `New-BorrowTimeline` that takes both axes.
The `copies=3` arms matter in the *opposite* direction from the original repro:
with two survivors the edited row is no longer the last claim on the object,
which is where an over-eager "is anyone still using this" check would evict too
much. TC-135 gained the same `copies=3` axis on the removal side (B9's eviction
refcount). **TC-122 was still `Draft` and is now implemented**: a 3-run and a
5-run timeline whose per-run census records the PROVEN CONTENT at every claimed
DataPath — raw bytes where they match the row's hash, the expanded payload
otherwise — and requires it never to change while the path persists.

**A finding from writing TC-122, worth carrying.** The census failed first time
in Compress mode, and it was the TEST that was wrong: a `.7z` re-created for
identical content is **not byte-identical** (7-Zip stores the member name and
time), and re-creating an evicted object is legitimate. Censusing raw bytes was
therefore testing 7-Zip determinism, not SR-059. The honest invariant is about
CONTENT under a live claim, and that is what the test now asserts. The same work
added `Get-UnjustifiedPoolNames` — the pool-side half of SR-059's "name-proven":
every object's name must encode the `(hash,length)` its own content produces, so
an object **no live row happens to claim** is still held to the contract that
hash recovery (SR-050) depends on. It carries a non-vacuity arm that tampers a
COPY of a real store and requires the audit to go red.

**Registry reconciliation — the list step 5 deferred to here.**

- The **mode axis is gone from every cell** (23 SR + 37 TC rows). `mode=4-modes`
  and `mode=set{Mirror,…}` collapse to `compress=set{on,off}`: the tree axis
  ceased to exist, so the surviving axis is the one the harness actually sweeps.
- **SR-012 RETIRED**, not amended. The earlier note said "amend", but that was
  written while the compression-flip migration was still expected to survive;
  the S2 ruling deleted that too, so SR-012's entire subject — layout selection
  and migration — is now stated by SR-058 + SR-061, and amending it would only
  have produced a duplicate requirement. LLR-012 and TC-023 went with it: their
  code and their test are deleted.
- **SR-013 AMENDED** to "`StoredAsHashSize` is the constant `'Hash'`". The column
  stays in the 9-column contract — both restorers and every existing store read
  it — but it is no longer a mode indicator, and `'Original'` is now purely the
  legacy-store trigger SR-061 refuses. LLR-013 was deleted and SR-013 folded into
  LLR-058, which is where the pinning actually happens (TC-121).
- **SR-051 RETARGETED, not retired** (driver decision, open to veto). The
  deferred note said retire, but only its *migration framing* died: the
  never-delete-a-still-referenced-data-file half is real, implemented and tested
  — it moved from `Sync-BackupStorageLayout` to the two sites that still delete,
  `Move-RemovedFilesToStaging` and `Save-SupersededData`. Retiring it would have
  dropped a Verified SN-030 invariant that the code still enforces and that
  TC-118/TC-135 still prove. LLR-051 was retargeted to those two symbols. SR-059
  (no OVERWRITE) and SR-051 (no DELETE) are complementary, not duplicates.
- **TC-095 retired** with the migration-refcount test it named. **TC-097** and
  **TC-100** re-pointed: TC-097's assertion inverts from "the triggered migration
  leaves nothing dangling" to "nothing already stored is re-formed at all", and
  TC-100 loses its migration term. The **vacuous `StorageForm`
  capacity-estimate `It`** — flagged in-file at step 5 as asserting nothing — was
  deleted rather than left inert; the dedup-counted-once behaviour it once
  covered is pinned by the adjacent `counts only NEW deduplicated content` case.
- Every `ca-v1` row is now Verified/Pass, and **`ca-v1` joined the ratchet** in
  `scripts/check.ps1` and `.github/workflows/tests.yml`, so nothing in the phase
  can be quietly dropped from here on.

**Kit revision stays at 6 (driver decision, open to veto).** WP9 changed no kit
byte. Content addressing is entirely engine-side, and both restorers already
resolve a row through its `DataPath` or by `(hash,length)` without caring how the
name was chosen. `Reconstruct.ps1:259` still mentions the Mirror-era shape and
that is CORRECT: the kit must go on restoring legacy path-addressed stores
(SR-061 refuses only *writing* to one), and bumping to revision 7 for a comment
would invalidate every existing snapshot's kit against TC-105 and `-RefreshKits`
for zero behavioural gain.

**IF-001 updated, and the container-view question answered.** The contract text
still carried `ConfigVersion` "currently 1" and JSON booleans for
`CompressEnabled`/`PreserveFolderTree`; it now states v2, the named removal
refusal, and unconditional content addressing, with `SR-058;SR-063` added to its
`SR-Refs`. The step-6 question is RULED by the driver: **`view` is not a
container action word.** A container's separate `/backup` bind mount can never
satisfy the same-volume rule, so `BrowseView: index` is native-host functionality
until a later IF-001 revision rules on a view mount; the container's action words
stay `{backup, prune, snapshots, verify}`, and both `docs/interfaces.md` and the
IF-001 row now say so.

**Docs.** AGENTS.md §2 (module table, and the pipeline rewritten to the real
1→16 shape including 1.5 / 5.1 / 5.2 / 9.4 / 11.5 / 16), §3 (the defect banner
now records all five 2026-08-24 defects CLOSED, and the invariant list gained
content addressing, immutability-and-name-proof, no-re-forming, and the view's
cosmetic status), §4 and §6 (the axis is Compression; G4 is the legacy-refusal
suite; G10-View added). README gained a "Browsing the backup without restoring"
section for `BrowseView` / `-Action View`. Three stale engine comments — the 5.5
"migration component" header, the SR-012 7-Zip note and the prune-sweep Mirror
aside — were corrected in place.

**Evidence (real output).**

```
==== PSScriptAnalyzer ====
[PASS] PSScriptAnalyzer

==== Traceability (trace.py --strict) ====
Traceability: SN=34 SR=63 LLR=61 TC=132 orphans=0 integrity=0 status-findings=0 phase-deferred=1.
[PASS] Traceability (trace.py --strict)

==== Doc navigability (check_docs.py) ====
check_docs: OK - 26 doc(s), 94 intra-repo link(s), 0 broken.
[PASS] Doc navigability (check_docs.py)

==== Architecture map freshness ====
[OK]  Generated regions current in docs\architecture.md
[OK]  Generated regions current in AGENTS.md
[PASS] Architecture map freshness

==== Pester unit ====
Tests Passed: 405, Failed: 0, Skipped: 0, Inconclusive: 0, NotRun: 0
[PASS] Pester unit

==== Performance budgets (check_perf.py) ====
[PASS] Performance budgets (check_perf.py)

==== Integration sweep (Full) ====
  PASS: 236
  FAIL: 0
  SKIP: 2
[PASS] Integration sweep (Full)

================ check.ps1 (tier Full, gate G3) ================
All steps passed.
```

Plus the restore twin, WSL Fedora (`bash/` was untouched by step 9 — this is the
regression check, not a change proof):

```
$ shellcheck -S warning bash/reconstruct.sh
SHELLCHECK_CLEAN
$ bats tests/bash
1..68        (68 ok, 0 not ok)
```

Unit went **391 → 405**: TC-118 grew from 2 arms to 8, TC-135 from 4 to 8,
TC-122 arrived with 4 census arms plus its non-vacuity guard, and the vacuous
`StorageForm` capacity-estimate `It` was deleted. Integration is unchanged at
**236 / 0 FAIL / 2 SKIP** — step 9's test work is all unit-level. `phase-deferred
= 1` is SR-033 (`bash-v2`), the one row still deferred by design; `ca-v1` is now
inside the ratchet, so every WP9 row is held to Verified/Pass from here on.

**Next:** the WP9 independent review — a Claude subagent, then the OpenAI
adversarial pass via `codex exec`. Both found real defects on the kit-bump WP,
and under the standing directive review is retained as a quality bar even though
ratification no longer pauses the work.

### INDEPENDENT REVIEW of WP9 (Claude subagent, whole-WP audit) — 2026-08-25

Verdict: **REQUEST-CHANGES.** One reproduced **data-loss** defect and one
reproduced vacuous-test hole in the very mechanism WP9 exists to add. The core
of the WP survived a determined attack: the reviewer independently re-derived
`Save-SupersededData`'s exactness across eight timelines, proved the SR-051
retarget honest (disabling the refcount turns all eight TC-135 arms red;
neutralising the preservation guard turns twelve TC-118 arms red), confirmed
owner election is locale-independent and cannot hand a row another content's
`DataPath`, confirmed the sanitize half survived the migration deletion, and
confirmed **no kit byte changed** (`git diff 553638c..HEAD` over the five kit
artifacts is empty), so revision 6 is honest. It also reproduced the driver's
numbers exactly: unit 405/405, integration 236/0/2, trace 0/0/0.

**MAJ-1 — the browse view could delete the store, or the user's source, on a run
that reported success. REPRODUCED, then re-reproduced independently before any
fix.** `Resolve-ViewRootPath`'s containment rail tested only ONE direction (view
*inside* an owned path) and never considered the source paths at all, while
`New-BrowseViewIndex` wipes the view root unconditionally. Two shapes therefore
passed validation and then deleted user data:

- `ViewPath` an **ancestor** of `BackupPath`/`ChangePath` — the run backed
  everything up and step 16 then deleted the backup root, the change root, every
  `Snapshot_*` and `backup.log`. Verified here: `backup root exists? False /
  MANIFEST exists? False / change root exists? False`, with only `INDEX.tsv`
  left standing.
- `ViewPath` **equal to `SourcePath`** — the source tree was destroyed and the
  entry point exited 0. Verified here with an external `SourceStatePath`:
  `source a.txt still exists? False`.

The volume rail cannot help, because in an ordinary local deployment the source
IS on the backup volume. This violated SR-051 as written and contradicted both
AGENTS.md §3's "a failure to generate it is a warning, never a failed backup"
and the docstring calling the root-level-`MANIFEST.csv` check "the
never-delete-user-data guard" — it guarded exactly one shape.

**Fixed with two independent guards, deliberately not one.** (1) The rail is now
bidirectional and covers `SourcePath`/`SourceStatePath` as well as both storage
roots: inside, equal-to, or *containing* any of them is refused by name, and the
comparison is by path COMPONENT so a `src-sibling` folder is still accepted.
(2) `New-BrowseViewIndex` now requires **positive ownership** before it deletes
anything: a non-empty view root must already carry `.viewstamp`, `INDEX.tsv` or
`INDEX.html`, or the wipe is refused. The second guard holds even when a caller
bypasses the rails — that is the point of having it. Path resolution also moved
BEFORE the wipe, so a mis-pointed root fails at its cause rather than somewhere
downstream. Both repro shapes now refuse with the store and the source intact.
Pinned by a new TC-128 arm (contains-a-root, contains-both-roots, IS-SourcePath,
IS-SourceStatePath, plus the prefix-sibling that must still pass) and a new
`View.Tests.ps1` Describe that calls the generator directly past the rails with
a `tax-return.pdf` in the way, and drives the store-swallowing shape end to end
through the entry point.

**MAJ-2 — TC-119 was VACUOUS with respect to the intra-run memo. REPRODUCED, and
the fix re-verified by re-breaking it.** The reviewer disabled the memo outright
and the entire 405-test suite stayed green. The cause is structural: under
content addressing the second member writes to the *same* filename with the
*same* bytes, so every assertion that measures the RESULT — one pool file, one
distinct `DataPath` — passes identically whether one write happened or two.
SR-060's own acceptance criterion says "one copy/compress **operation**", and
nothing asserted it; D-5's cost defect could have returned silently, at 50 full
copies for a file duplicated 50 times in one run.

Fixed by making the behaviour **observable** rather than by asserting harder:
`Invoke-BackupFileGroup` now logs one line per PHYSICAL write (`Stored object
'<name>' for hash=… len=… from '<source>' (group of N)`), which is worth having
operationally in its own right, and TC-119 counts those lines. Re-verified: with
the memo disabled the assertion reports `Expected 1 … but got 2` in **both**
modes; with it restored, green.

**MIN-1 — one unreadable file failed its whole content group.** The elected
owner's file was the SOLE copy source, so a locked or vanished owner left every
one of its content twins unbacked-up — and the error named the twin rather than
the file that could not be read. Pre-WP9 each member copied its own file, so
this was a WP9 regression. Fixed: the copy now falls through the group's other
members (identical bytes by the dedup key, and the destination name derives from
the content and the owner's FORM, so it does not move), clearing a partial
destination between attempts, and the WARN names the file that actually failed.

**A further defect the MIN-1 test surfaced, not in the review: `Copy-Item`'s
failure could be non-terminating, and `Copy-SourceFileToBackup` then returned
success with no file written** — a manifest row naming a file that was never
copied. Latent in production because `FileBackup.ps1` sets
`$ErrorActionPreference = 'Stop'`, but correctness must not depend on a caller's
preference, and it also disarmed the MIN-1 fallback (the first attempt
"succeeded"). Now `-ErrorAction Stop` at the call site. The Plain arm of the new
MIN-1 test was red until this was fixed.

**MIN-2 — the bash half of "both restorers still restore a legacy store" lost its
guard.** Step 5b deleted the Mirror fixtures, and no remaining bats fixture has a
`DataPath` containing a path separator, so `reconstruct.sh`'s path-addressed
branch is correct-by-reading but uncovered. **AGENTS.md §3 now says exactly
that** rather than claiming a proof that no longer exists; a constructed legacy
bats fixture is recorded as a live item rather than pretended.

**MIN-3 / nits — the step-9 registry sweep missed seven places.** All corrected:
SR-052 no longer requires sizing migration copies; LLR-052's migration component
and its "step 9.5" are now step 11.5; LLR-059's Mirror arm is gone; LLR-061,
SR-062 and TC-131 now say the `.viewstamp` is keyed on a SHA-256 of canonical
manifest ROWS, not the manifest witness (the code was right, the registry was
wrong); the step-9.4 comment no longer describes step 6 re-forming rows;
`Get-ReHomedDataPathName`'s "collapses at step 8" became the measurement that
actually happened; and `Resolve-BackupSetPaths`' `-ReadOnly` docstring no longer
claims the view is unvalidated. SR-064's criterion now states its one deliberate
difference from the quadratic audit (nit-1: existence is decided from the
enumerated data-file set, which skips root-level infrastructure names —
unreachable, but no longer overclaimed). nit-2: the embedded search index is
escaped for `<`/`>` before it lands in a `<script>` block. nit-3:
`Get-UnjustifiedPoolNames` now recurses. nit-5: G9's `Prune_last_succeeds`
surfaces the mechanism's own refusal Message instead of "Condition returned
false". SR-063's requirement and TC-128's expectation now describe the
bidirectional rail and the ownership guard.

**nit-4 NOT taken (recorded).** `Compress-FileWithSevenZip` uses `7z a`, which
merges into an existing archive rather than replacing it. The reviewer could not
weaponise it and neither could I — every member of a group has identical bytes,
so a duplicate archive member carries the same payload, and rev-6's
write-verification would catch a mismatch. The clean fix lives in **Common**,
which is kit-bundled, so it costs a kit revision bump; the MIN-1 retry path
clears its destination Engine-side instead. Left as a live item so the kit-rev
decision is made deliberately rather than as a side effect.

**Driver note on the review itself.** Both MAJ findings are things the driver's
own self-review missed, and both are in step 7's work — the one step that added
a NEW filesystem-writing surface. The lesson recorded for future WPs: when a
step starts writing outside the storage roots, the containment rail needs an
adversarial pass of its own, and a "cosmetic" component that holds a recursive
delete is not cosmetic.

**Evidence after the fixes (real output).**

```
==== PSScriptAnalyzer ====                       [PASS]
Traceability: SN=34 SR=63 LLR=61 TC=132 orphans=0 integrity=0 status-findings=0 phase-deferred=1
check_docs: OK - 26 doc(s), 94 intra-repo link(s), 0 broken.
[OK]  Generated regions current in docsrchitecture.md / AGENTS.md
Tests Passed: 411, Failed: 0, Skipped: 0, Inconclusive: 0, NotRun: 0
  PASS: 236   FAIL: 0   SKIP: 2                  (integration, 2-mode matrix)
================ check.ps1 (tier Full, gate G3) ================
All steps passed.

$ shellcheck -S warning bash/reconstruct.sh   -> SHELLCHECK_CLEAN
$ bats tests/bash                             -> 68 ok, 0 not ok
```

Unit went **405 -> 411**: the TC-128 containment arm, three `View.Tests.ps1`
ownership-guard cases, and the two MIN-1 arms. Integration is unchanged at
**236 / 0 / 2**.

**Not yet closed, and recorded as live items rather than quietly dropped:**
MIN-2 (a constructed legacy bats fixture) and nit-4 (the `7z a` replace, which
costs a kit-revision bump). Both are in the Open-items table above.

---

### DRIVER (System Engineer + Data-integrity hats) — WP12 raised and planned: the stored-object name grammar — 2026-08-27

**Raised by the human**, from a live pool, not from the backlog: the data files
are named ``lii`7EXH@[hgD!I= !!!!!!=X&K.7z`` and the question was whether the run
of exclamation marks and the punctuation soup were expected.

**They were, exactly** — and the driver decoded that name to prove it rather
than assert it: hash `4E0F14958D71156767A1880F94`, length `8388608` (8 MiB), a
16-char base-85 field, a space, a 10-char base-85 field. `!` is `Alphabet[0]`,
the ZERO DIGIT, so the six-`!` run is left-padding of a fixed-width length
field, not a special character at all.

Answering it surfaced three things the registries did not know:

1. **The name grammar has no owning requirement.** SR-003 owns dedup by
   `(hash, Length)` and says nothing about filenames; SR-021 owns
   `-LiteralPath`. The format is written down in exactly one place —
   **TC-004's `Expected`** — a test case describing behaviour no requirement
   states. That is a real traceability finding, independent of any redesign.
2. **The name's hash is not the manifest's hash.** 16 base-85 chars hold ~102.5
   bits, so `Convert-HexToShortName` silently truncates the 128-bit xxHash128
   to its low 26 hex digits. No audit can compare a pool name to `xxH2Hash`
   without reproducing that truncation.
3. **The alphabet manufactures the hostile shapes we keep tripping over.** `.`
   and `-` are both in it, which is the root of the 2026-08-23 CI
   hidden-files break and of the doubled dot in the committed fixture
   `.nArDBFwE!yq[FFf !!!!!!!!#..bin`.

**Human ruling, same session:** move to **base-57** (the 62 alphanumerics less
`0 O I l 1`), a **`_` separator**, the **full 128-bit hash padded to 22**, and an
**unpadded length**. Offered and declined: base-58 (Bitcoin's set, which keeps
`1`); the human chose the whole-confusion-family cut. The choice is free —
57, 58 and 62 all encode 128 bits in 22 characters, verified — so it is a
legibility decision, not a density one. A sample name is 30 characters, exactly
as long as today's, while carrying 26 more bits of hash and no padding run.

Plan filed: **[plans/wp12-name-grammar-plan.md](../plans/wp12-name-grammar-plan.md)**.

**Scope findings worth recording before implementation:**

- **`bash/reconstruct.sh` needs no logic change.** It never decodes a name — it
  walks with `find -print0` and hashes candidates. The POSIX twin is
  grammar-agnostic by construction; the plan pins that as a property rather
  than leaving it a happy accident.
- **Blast radius in the engine is two lines** (`Common.psm1:391-393`), plus the
  alphabet and the two encoder functions. Three test sites, and the bash
  fixtures regenerate mechanically via `scripts/gen_bash_fixtures.ps1`.
- **`Move-Item -Destination` was checked, not assumed.** `Engine:3247` passes a
  short name containing `[` to a NON-literal `-Destination`. Driver ran it
  against a real unmatched-bracket name: it moves correctly, because a
  non-matching wildcard destination is treated as a literal. Not a defect —
  recorded so nobody has to re-derive it.

**One genuine latent hole found and deliberately NOT folded in:** the
PowerShell 7-Zip calls (`Common.psm1:444` and `:478`) hand-build their argument
string with no `--` end-of-options guard, while the bash twin guards every
`rm`/`cp`/`mv`/`stat`/`touch`/`mkdir`/7z call. A leading `-` or `@` (7-Zip's
response-file sigil) would be misread as a switch; unreachable today only
because every path passed is absolute. Base-57 removes the reachability but not
the hole. **Carried as its own live item** — folding it into WP12 would blur
what WP12's evidence proves.

**AWAITING HUMAN RATIFICATION — three decisions, none taken autonomously:**

- **D-1** how a rev-9 restorer refuses a rev-8 store. Driver recommends the
  **shape test** (an old `DataPath` contains a space; a new one cannot),
  extending SR-061's existing predicate — over a positive `StoredAsHashSize`
  marker, which would reintroduce exactly the claim-stored-apart-from-the-bytes
  defect class WP11 Part B removed.
- **D-2** make `Convert-HexToShortName`'s over-length case **throw** instead of
  silently truncating. Unreachable at 22 chars, but it is the one change that
  could turn a currently-silent situation loud.
- **D-3** accept the **loss of the leading-dot regression fixture** (no base-57
  name can start with a dot, so it cannot be regenerated), keeping
  `include-hidden-files: true` in CI with a comment naming WP12 as the reason.

No code, registry, or fixture has been touched. Ids reserved against the
registries for the implementing commit: **SR-069, LLR-069, TC-142…TC-146**,
phase tag **`name-v1`** (held OUT of the `check.ps1` ratchet until the evidence
run lands, so it reports phase-deferred rather than failing G3 while open).

---

### DRIVER — WP12 SHIPPED: the base-57 stored-object name grammar (kit revision 9) — 2026-08-27

Ratified, reviewed, repaired twice, implemented, and green on real output.

**What shipped.** Stored objects are now named `<hash22>_<len><ext>` over a
57-glyph alphabet (the 62 alphanumerics less `0 O I l 1`; `'2'` is the zero
digit). The hash field is the COMPLETE 128-bit xxH2Hash — the old 16-char
base-85 field held ~102.5 bits and silently truncated — and the length field is
UNPADDED, which is what removes the run of zero-digits the human raised this
from. A name is the same 30 characters as before while carrying 26 more bits of
hash. Witness format version 1 → 2; kit revision 9.

**The human's ruling and its one carve-out.** "Nothing here needs to be backward
compatible" was ratified and applied. D-1 was kept regardless, and the reasoning
is recorded because it will come up again: refusing an old store is not
backward compatibility, it is the guarantee that a grammar this build cannot
read is never MISread.

**Evidence (real output, this host, on the committed tree):**

```
==== PSScriptAnalyzer ====                         [PASS]
Traceability: SN=34 SR=69 LLR=67 TC=146 orphans=0 integrity=0
              status-findings=0 phase-deferred=1
check_docs: OK - 27 doc(s), 100 intra-repo link(s), 0 broken.
[OK]  Generated regions current in docs/architecture.md / AGENTS.md
Tests Passed: 444, Failed: 0, Skipped: 0
  PASS: 274   FAIL: 0   SKIP: 2                    (integration, 2-mode matrix)
================ check.ps1 (tier Full, gate G3) ================
All steps passed.

Ubuntu WSL:  shellcheck -S warning bash/reconstruct.sh  -> SHELLCHECK_CLEAN
             bats tests/bash                            -> ok=79  not ok=0
```

Unit 437 → **444**, integration 240 → **274**. Ratchet armed to
`core,bash-v1,container-v1,kitbump-v6,ca-v1,fidelity-v1,robust-v1,form-v1,name-v1`
in both `scripts/check.ps1` and the CI traceability job.

**Registry:** SR-069 (name grammar) and SR-070 (opaque, possibly-empty
extension) added — **the grammar had no owning requirement before**, it was
stated only in TC-004's `Expected`, which is the traceability finding that
outlives the redesign. SR-061 amended; LLR-069/LLR-070; TC-004 amended;
TC-142…TC-149 added.

**Three defects were found that no one set out to look for.** All are recorded
in full in [plans/wp12-name-grammar-plan.md](../plans/wp12-name-grammar-plan.md)
§9; the short version:

- **T6 — a LIVE PRODUCTION BUG, unrelated to the redesign.**
  `Get-HashSizeFileName`'s `-Extension` was `[Parameter(Mandatory)]`, which in
  PowerShell REJECTS the empty string, so **any extensionless source file**
  (`README`, `LICENSE`, `Makefile`) in a set with `CompressEnabled=false`
  **failed the entire backup set**, exit 1, nothing stored. Invisible in
  Compress mode because an empty extension is not in
  `NonCompressibleExtensions`, so the name became `.7z` before reaching the
  encoder — which is exactly why the matrix never caught it. Found by probing
  the review's extension question, reproduced end to end, fixed, and pinned by
  TC-148 in BOTH modes.
- **T2 — the RATIFIED D-1 mechanism would have broken real backups.** "An old
  DataPath contains a space; a new one cannot" is false: the stored name ends in
  the OWNER'S SOURCE extension, `Test-PortableRelativePath` permits
  `signed.foo bar`, and a live pool duly contained
  `f7(#5C=v.uYfdGbp !!!!!!!!!%.foo bar`. A brand-new store would have been
  refused as legacy by the engine and both restorers. Caught by the independent
  review; SR-070 now pins the extension as opaque so no future guard can
  reintroduce a character blacklist.
- **T7 — the review-repaired plan was STILL wrong, and only the suite caught
  it.** D-1's structural test was specified as "every non-blank DataPath must
  parse under SR-069; anything else is refused." Five unit tests and six
  integration assertions failed on it, correctly: **"not the current grammar"
  and "a retired grammar" are different predicates.** A merely DAMAGED DataPath
  (the `DanglingDataPath` class) parses under neither, and SR-049/SR-053/SR-056
  exist to audit, heal and verify those PER ROW — the negative test refused the
  whole store, turning one repairable row into an unrestorable backup and
  locking out `-RepairStorage`. Inverted to a POSITIVE test
  (`Test-LegacyStoredObjectName` / `is_legacy_stored_name`): a path separator,
  or the base-85 form's space at index 16. **Refuse the old FORMAT; repair
  damaged ROWS.** Worth keeping in mind: the strict version LOOKED stronger, and
  both the driver and a review specifically hunting D-1 defects read past it.

**Independent review:** OpenAI gpt-5.6-terra, medium effort, via `codex exec`,
read-only, adversarial charter — 5 findings (1 P0, 2 P1, 2 P2). T2 and T3 were
valid and changed the design (T3 replaced the shape test with the witness
version as the authoritative marker). T1's arithmetic was accepted and its
severity reduced: base-57 folds to 34 case-insensitive classes = 111.92 bits on
NTFS, not 128 — but base-85 folded to 59 over 16 chars = **94.12**, so WP12
IMPROVES the flagged property by +17.8 bits. The review did not make that
comparison. Its recommendation to change the codec was declined; the real gap
underneath it was recorded (see live items).

**Housekeeping worth knowing about:** the bats suites carried FIVE
byte-identical copies of `restamp_witness`, each with the version hard-coded, so
the witness bump broke 30 tests at once. Now one definition in `helpers.bash`
with the version as a constant. `restore_fidelity.bats` had drifted to CRLF
despite `.gitattributes` mandating LF — normalised. A transient
`Access to the path 'V:\Snapshot_...' is denied` failed G9 prune on one run:
the tool REFUSED correctly (exit 4, "no data was lost") and it did not
reproduce — environmental, recorded rather than dismissed.

**LIVE ITEMS (two, both pre-existing, neither introduced here):**

1. **No collision rail on the content-addressed write path** (WP12 plan R-4).
   `Invoke-BackupFileGroup` writes to the derived name without proving that an
   object already there is the same content. Pre-existing, and WP12 makes it
   17.8 bits less likely, but the fix is an SR-029 verify-or-fail conversation,
   not a naming one.
2. **No `--` end-of-options guard on the PowerShell 7-Zip calls**
   (`Common.psm1:444`, `:478`), where the bash twin guards every external call.
   Base-57 removes the REACHABILITY of a leading `-` or `@`, not the hole.

**G-Release and G-Final remain the outstanding gates.** SR-033 (`bash-v2`) is
still phase-deferred by design.

---

### DRIVER — WP12 follow-up: regression tests for every failure mode the WP surfaced — 2026-08-27

Human asked for coverage around the defects found and patched during WP12, so
they cannot resurface quietly. Five new cases, chosen by asking which modes were
only INCIDENTALLY covered — T6 and T2 already had TC-146/TC-148, but T7, the
cross-implementation drift, and the version-agreement invariant had nothing.

- **TC-150 — the T7 pin.** Asserts directly that "not the current grammar" and
  "a retired grammar" remain DIFFERENT predicates: a damaged or foreign
  `DataPath` is not legacy, both retired grammars are, blank never is, and the
  "neither" class is non-empty with nothing ever both. If anyone re-derives one
  predicate from the other, that class collapses and this fails.
- **TC-151 — cross-implementation parity.** New committed corpus
  `tests/fixtures/name-grammar/cases.tsv` (21 cases, PowerShell as ORACLE);
  bats holds `is_legacy_stored_name` to it case for case, and the Pester twin
  re-derives the file so it cannot rot. Same pattern as TC-053's hash goldens.
  Also asserts no shipped fixture object reads as a retired grammar — the engine
  must never emit a name its own gate refuses, checked by the OTHER implementation.
- **TC-152 — witness version agreement** across all three files that declare it.
  The WP12 bump left `helpers.bash` behind and broke 30 bats tests at once; a
  mismatch between `Common.psm1` and `reconstruct.sh` would be far worse — the
  POSIX restorer would refuse every store the Windows engine writes.
- **TC-153 — the alphabet's case-fold arithmetic** (34 folded classes, 111.92
  bits, still 128 bits in 22 chars). Pins the reasoning the review's T1 was
  answered with so a later alphabet change cannot quietly erode it.
- **TC-154 — proves T3's residual gap BENIGN instead of arguing it.** Builds the
  worst case the gap admits (every object renamed into the retired grammar,
  every `DataPath` blanked, no witness) and requires a byte-exact restore.

The POSIX fixtures also gained `README`, `signed.foo bar` and `archive.a_b`, so
the bash restorer now exercises the SR-070 shapes end to end, not just the
PowerShell one.

**Two defects the new tests caught on their first run:**

1. **`is_hash_size_name` was DEAD CODE in the shipped kit.** The parity test
   found bash and PowerShell disagreeing on two corpus cases — and tracing it
   showed the diverging function had become uncalled when the SR-061 gate was
   narrowed to the positive legacy test. Deleted rather than repaired: a kit
   bundled into every backup must not carry code it never runs, and the locator
   matches CONTENT, so the only naming question a restore ever asks is whether
   the store is one it must refuse. `IsLegacy` is now checked by both
   implementations, `IsCurrent` by the engine's alone.
2. **`manifest_parse.bats` hard-coded `rows -eq 10`**, which went stale the
   moment the fixture timeline gained files. Replaced with a check against the
   WITNESS's own `Rows=` — so it now cross-checks the bash parser against the
   count the PowerShell engine recorded, instead of a magic number that rots.

**Evidence (real output):**

```
check.ps1 -Tier Full -Gate G3:
  PSScriptAnalyzer                                 [PASS]
  Traceability: SN=34 SR=69 LLR=67 TC=151 orphans=0 integrity=0
                status-findings=0 phase-deferred=1
  check_docs: OK - 27 doc(s), 100 intra-repo link(s), 0 broken.
  Architecture map freshness                       [PASS]
  Performance budgets                              [PASS]
    PASS: 274   FAIL: 0   SKIP: 2                  (integration, 2-mode matrix)
  Pester unit: 452 passed, 1 failed  <-- see the transient below

Isolated unit re-run (same tree, no other load):
  Tests Passed: 453, Failed: 0, Skipped: 0

Ubuntu WSL: shellcheck -S warning bash/reconstruct.sh -> SHELLCHECK_CLEAN
            bats tests/bash                          -> ok=87  not ok=0
```

**AN HONEST TRANSIENT, RECORDED RATHER THAN RE-RUN AWAY.** Two prune failures
occurred today on code that was not changed between runs, and NEITHER
reproduced on an isolated re-run:

- `G9.6 Prune_oldest_succeeds` — `Access to the path
  'V:\Snapshot_2025_01_01_00_00_01' is denied`, and
- `Coverage.Tests.ps1:2922` (WP7 compression-flipped prune) — expected 0, got 4.

Both are exit **4** — "Removal aborted before the commit point; no data was
lost" — i.e. the safety rail behaving CORRECTLY against a file lock, not a
correctness defect. Both have the signature of a lingering handle (this host
also runs a test that deliberately holds a file open, TC-084).

**This means WP11 Part A's intermittent cannot be declared dead.** Part A fixed
one real cause (`Reset-TestEnvironment` ignoring a failed delete) and the
diagnostics it added are what made today's two sightings legible in one line
instead of an opaque `Condition returned false` several steps downstream. But
two sightings in one day is a pattern, not noise. Recorded as a live item rather
than dismissed, and deliberately NOT papered over by re-running until green.

**LIVE ITEMS (now three):** the two carried from WP12 (no collision rail on the
write path; no `--` guard on the PowerShell 7-Zip calls) plus the prune
transient above.

---

### DRIVER — CORRECTION: the prune exit-4 sightings, investigated properly — 2026-08-27

The human challenged the previous entry's claim ("both have the signature of a
lingering handle... a HARNESS/host question, not a correctness one") and asked
how long the failure took to surface. The challenge was right on both counts and
this entry supersedes that wording.

**What the previous entry got wrong.**

1. **It asserted a cause for a failure whose cause was never captured.** `G9.6`
   printed its reason - `Access to the path 'V:\Snapshot_2025_01_01_00_00_01' is
   denied`. `Coverage.Tests.ps1:2922` printed only `Expected 0 ... but got 4`.
   The "lingering handle" signature was read off the exit code alone. The
   refusal payload existed in `$run.Output` and the assertion discarded it.
2. **It called a coin-flip a transient.** The real rate across completed full
   batteries is **2 failures in 3 runs** (full2: G9.6 + G9.9, integration;
   full3: clean; full4: Coverage:2922, unit), hitting two different runners.
   "Not reproducing in isolation" is evidence about CONTEXT, not about rarity,
   and was reported as though it were the latter.
3. **It blamed the harness without evidence.** "Harness" was an assumption; a
   host-io exception can come from outside the process entirely.

**What is now ESTABLISHED, by reading the taxonomy rather than inferring.**

Prune's exit **4 has exactly two sources in the whole engine** - the `host-io`
catch blocks at `Engine:2563` and `Engine:2638`. EVERY policy refusal is code
**2** (`capacity`, `run-state`, `staging-busy`, `broken-pool`, `form-mismatch`,
`bad-target`, `destination-collision`, `infrastructure-name`,
`unreferenced-data`, `witness-absent`, `witness-mismatch`), and `$worst` sorts 2
ahead of 4. **So a code-4 prune result is always a caught filesystem exception,
never the product deciding to refuse.** That part of the original claim was
correct - it just had not been checked when it was made.

**What is NOT established: the cause. Four hypotheses tested, all negative.**

| Hypothesis | Test | Result |
|---|---|---|
| Fails standalone | 12 isolated runs of the `It` | **0 failures** |
| Concurrent WSL/`bats` load (driver's leading theory) | 14 isolated runs under sustained WSL load | **0 failures** |
| Cross-test interference inside `Coverage.Tests.ps1` | 3 whole-file runs, 208 tests each | **0 failures** |
| Rare flake | 2 of 3 full batteries | **contradicted - it is frequent** |

**29 targeted runs and 3 whole-file runs produced zero reproductions.** It has
only ever appeared inside a full `check.ps1 -Tier Full` battery. The failing
`It` itself takes **5.1s**; finding it takes a ~15-minute battery.

**Mitigation shipped rather than a conclusion asserted.** All **11** prune
assertions in `Coverage.Tests.ps1` that tested only an exit code now carry
`$run.Output` in their `-Because`, and `Invoke-FBAction` carries a note saying
why. This is WP11 Part A's lesson applied to the one place it had not been: the
cause must appear with the consequence. The next sighting will name its own
filesystem error instead of costing another hour and still being unexplainable.

**Status: OPEN, cause unknown, correctness not implicated.** The engine refuses
at the safety rail and reports "no data was lost", which is the designed
behaviour when the filesystem denies a removal. Whether the denial comes from
the harness, Defender, the indexer, or a stray working directory is unresolved -
and it will stay unresolved until the improved diagnostics catch one.

---

### DRIVER — WP12 validated in the OCI container (the surface HomeHub consumes) — 2026-08-27

The one platform WP12 had not been exercised on. `Invoke-Container.ps1
-Action BuildAndTest` on Ubuntu WSL + Docker 29.6.1 — the same command CI's
container job runs — **all three checks passed**:

- build, compressed backup, restore kit deposited, **byte-exact restore**;
- **TC-102** storage-form check: clean verify exits 0 and mutates nothing, a
  malformed row exits 1, repair makes it clean;
- incremental run produces a **restorable dated snapshot** alongside a
  byte-exact latest-state restore.

Base-57 names are being written and read inside the image, e.g.
`7aZ9f5jSkKVrE88v8w4VqB_3wY.7z`, `mgSTtg8oupaMwP8Eci95Ef_P.7z`.

**IF-001 needs no revision.** The contract covers the config schema, bind
mounts, action words and the exit-code table; it says nothing about the
stored-object name grammar, which is entirely below that line. WP12 is
invisible to HomeHub's interface — the integration is a deploy, not a
negotiation.

**The one caution for HomeHub: point it at a FRESH `BackupPath`.** Any store a
previous build wrote is refused by kit revision 9 (exit 2 on restore; the
backup set fails with the fresh-BackupPath remedy). That is SR-061 working as
ruled, but HomeHub is a SEPARATE deployment from this repo's "not in use"
statement and has its own `/backup` volume. Anything wanted from an existing
HomeHub store must be restored with the kit bundled inside that folder, before
a rev-9 build is pointed at it.

**Still unvalidated: the CI-only jobs** — `bash-interop-make`,
`bash-interop-restore`, `integration-vhdx`, and the export/registry half of the
container job. The bash-interop pair matter most: they are where the
2026-08-23 dot-leading-name break surfaced, and WP12 changes every name in the
pool. Not pushed yet (5 commits ahead on `New_Fix_Batch`); CI is the next step
and will also give an independent data point on the open prune exit-4.
