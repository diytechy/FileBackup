# WP11 — Diagnosability, and retiring the `Compressed` claim

Plan owner: driver. Raised by the human 2026-08-26 after WP10, covering the two
remaining live items in [status.md](../status.md): the unreproduced Full-tier
intermittent, and **S1 — retire the `Compressed` claim; derive form from bytes**.

Two independent parts. **Part A ships first and alone** — it is what makes the
next occurrence of the intermittent evidence rather than a guess, and it must
not be entangled with a kit change.

---

## Part A — make the intermittent diagnosable

### A.0 What we actually know

Across six `-Tier Full` runs on 2026-08-26 the integration suite failed twice
and passed four times **on identical code**, while `tests/Run-All.ps1` run
standalone passed `240 PASS / 0 FAIL / 2 SKIP` three times in a row.

| Run | Integration | Note |
|---|---|---|
| full1 | 240 / 0 / 2 | |
| full2 | 217 / **4** / 2 | driver error: two Pester suites running concurrently |
| full3 | 240 / 0 / 2 | one unrelated unit failure (SR-057 Deny-ACE, empty manifest) |
| full4 | 229 / **7** / 2 | ran alone; Plain **and** Compress; no known cause |
| full5 | 240 / 0 / 2 | |
| full7 | 240 / 0 / 2 | |

Every failure lands in **G9 prune**, and every one reports the same thing:
`Condition returned false`. Two hypotheses have already been raised and
disproven (walk abandonment on a Deny ACE; SR-067's retry). A third guess is
not what this needs.

### A.1 The lead: the fixture builder ignores whether the backup worked

`tests/Common/Harness.ps1:160` — `Invoke-Backup` runs the entry point, tees the
output, and **never inspects `$LASTEXITCODE`**. `FileBackup.ps1` signals a failed
set with `exit 1`, so a fixture backup can fail and the suite proceeds to build
assertions on a store that is missing a snapshot, a row, or a stored object.

That converts a *diagnosable* failure ("the third backup run failed") into an
*undiagnosable* one ("the timeline does not have four snapshots"), which is
precisely the shape of every observed failure:

- `Prune_timeline_has_four_snapshots` — one of the five runs made no snapshot.
- `Cycle_one_copy_before_prune` — a run failed, so the copy count differs.
- `Prune_oldest_succeeds` — the prune rails correctly refuse an inconsistent store.

**This is a hypothesis, not a conclusion.** It is worth doing regardless of
whether it is *the* cause: a fixture builder that silently tolerates failure is a
harness defect on its own terms.

### A.2 Changes

| # | Change | Why |
|---|---|---|
| A1 | `Invoke-Backup` captures `$LASTEXITCODE` and **always** records a visible diagnostic line when it is non-zero, plus an opt-in `-ExpectSuccess` that turns an unexpected non-zero into a recorded FAIL naming the code and the tail of the run output | Many suites drive failing backups deliberately (G4 refusals, capacity refusals), so this must not throw. The always-on line means any later opaque failure is preceded by the real cause |
| A2 | G9's fixture-building `Invoke-Backup` calls take `-ExpectSuccess` | These build the timeline every later assertion depends on |
| A3 | Convert G9's opaque prune assertions to the Status/Message pattern the suite already uses at `G9-Rollback.ps1:200` (`Prune_last_succeeds`) | A refused prune already carries `Status` and `Message` explaining exactly which rail tripped; the assertion currently throws it away |
| A4 | Count-style assertions report the OBSERVED value (`expected 4, saw 3`) | `Condition returned false` is not evidence |
| A5 | On any G9 failure, copy `backup.log` and every pool `MANIFEST.csv` into the run's artifacts directory before the next `Reset-TestEnvironment` destroys them | Post-mortem currently impossible: the env is reused and wiped between sections |

### A.3 Acceptance

- A deliberately failed fixture backup (injected) produces a named FAIL that
  identifies the failing RUN, not a downstream assertion.
- A refused prune reports its `Status` and `Message`.
- A count mismatch reports both numbers.
- Artifacts for a failed G9 section survive the run.
- Full tier stays green; no product code changes in Part A.

### A.4 What Part A deliberately does NOT do

No retry, no tolerance, no quarantine. If the intermittent is real, the next
occurrence must be *louder*, not softer. Making a flaky test pass is the failure
mode to avoid here.

---

## Part B — S1: the restorers stop trusting `Compressed`

### B.0 The finding that resizes this work

S1 as filed estimates "a ~10-line 7z-magic sniffer in Common plus a bash twin"
for a payoff of "≈200 lines of audit/repair logic". Reading the code first
changes both halves of that.

**The byte-derived rule already exists and is already correct**, in
`Get-StorageFormFinding` (`Engine.psm1:1463-1666`). Its own contract documents
the exemption the human asked about: an already-compressed SOURCE file is stored
raw, so its stored bytes ARE a 7z archive while its row correctly says
`Compressed='No'`. It resolves that by **hashing the file's own bytes against the
row's `(xxH2Hash, Length)`** — a match is correct raw storage, only a mismatch is
a genuine `FlagOverArchive`. It explicitly rejects keying on a `.7z` extension,
because an already-compressed source can be called anything.

So the question "how do you tell an object we compressed from an object that was
already compressed at source?" is already answered, and answered correctly:
**not by sniffing, but by asking whether the bytes already reproduce the row.**

What is missing is only that the **restorers do not use it** for a row resolved
through its own `DataPath`. SR-050 made the located file's PROVEN form outrank
the column — but only for hash-recovered rows.

### B.1 The rule to implement

For a row resolved through its own `DataPath`:

1. Read the first six bytes. **No 7-Zip signature → Raw. Done.** The engine
   never writes a compressed object without it, so this is conclusive and covers
   the overwhelming majority at the cost of one six-byte read.
2. Signature present — the object is *either* one we created *or* a raw-stored
   source archive:
   - **file length ≠ `row.Length` → Archive.** Raw storage stores the original
     bytes, so the lengths would match. A `stat`, no hashing.
   - **lengths equal → hash the file.** `hash == row.xxH2Hash` → **Raw** (it is
     the user's own archive); otherwise → **Archive**.

Deterministic, no 7-Zip needed to decide, and the expensive branch is reached
only by an archive-shaped object whose length equals the row's.

`Compressed` is then **not consulted for any correctness decision** in either
restorer.

### B.2 Scope decisions, stated rather than assumed

**B.2.1 The column is retained, its authority is not.** Removing the column is an
8-column schema break for every existing store, both restorers' parsers and eight
bats header fixtures — a large bill for a field that becomes harmless. It stays
in the 9-column schema alongside `StoredAsHashSize`, documented as advisory.

**B.2.2 The restore capacity pre-check keeps reading it.** That check sums
uncompressed row lengths *before opening anything*, and already warns that its
estimate is low when compressed rows exist. An estimate is the one honest use of
an advisory field. Deriving there would mean opening every data file before the
restore starts, for a number that is already caveated.

**B.2.3 The audit classes are NOT deleted — this is a deviation from S1 as filed,
and the driver recommends it.** S1 assumes the four "the column lies" classes
become dead once nothing reads the column. They become *non-fatal*, which is not
the same as *worthless*: a manifest that disagrees with its bytes is still
evidence that something wrote a wrong index, and this is a data-safety tool.
Deleting a detector to save lines is the wrong trade. The proposal is to
**reclassify them as informational** (they no longer imply a restore is at risk)
and keep them reporting. Expected line saving therefore ≈ 0, and the real payoff
is the correctness one: the last path by which a lying column can produce a wrong
restore is closed. **If the human wants the deletion anyway, it is a separate,
reversible follow-up.**

**B.2.4 `Repair-BackupStorageForm`'s form arm becomes cosmetic.** It mutates a
manifest and re-stamps a witness to correct a field nothing reads. Recommend
keeping the code but making the repair a no-op-with-explanation for form-only
findings, rather than writing to a store for cosmetic reasons.

### B.3 Changes

| # | Change | Where |
|---|---|---|
| B1 | `Get-StoredObjectForm` — the B.1 rule, taking the row's hash+length | **Common** (kit-bundled; Engine is not) |
| B2 | Use it for DataPath-resolved rows instead of `$row.Compressed` | `Reconstruct.ps1` |
| B3 | bash twin (`stored_object_form`) and the same substitution | `bash/reconstruct.sh` |
| B4 | Kit revision **8** + revision note | both restorers |
| B5 | Reclassify form findings as informational; form repair explains rather than writes | `Engine.psm1` |
| B6 | SR-068 / LLR-068 / TC-141, phase `form-v1`; amend SR-049 and SR-050 | registries |
| B7 | README (`Compressed` column note), AGENTS.md §3 invariant | docs |

### B.4 Acceptance

- A store whose `Compressed` column is deliberately flipped on every row still
  restores byte-exact through BOTH restorers, in Plain and Compress.
- A genuine already-compressed SOURCE file (a real `.7z` in the source, stored
  raw) restores byte-exact — and is NOT expanded — with the column flipped to
  `Yes` and with it correct.
- A `.txt` stored as `.7z` restores byte-exact with the column flipped to `No`.
- An object that is neither (damage) still fails loudly as `ContentMismatch`.
- Kit revision 8 is reported; TC-105 and `-RefreshKits` still pass.
- Full tier green; bats green; shellcheck clean.

### B.5 Risk

This touches the restore decision path — the highest-consequence code in the
repo. Mitigations: the rule is already proven in `Get-StorageFormFinding`; SR-056
verifies every restored file after writing, so a wrong decision fails loudly
rather than silently; and B.4's first acceptance case (every row's column
flipped) is the direct regression test for the whole change.

---

## Order

1. **Part A**, committed and green on its own.
2. **B1–B4** (the restore rule + kit rev 8), with B.4's cases.
3. **B5–B7** (reclassification, registries, docs).

Part A must not wait on Part B: if the intermittent recurs while Part B is in
flight, Part A is what tells us whether Part B caused it.
