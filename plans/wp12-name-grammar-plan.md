# WP12 — The stored-object name grammar: base-57, separated, unpadded, whole-hash

Plan owner: driver. Raised by the human 2026-08-27 after inspecting a live pool
and finding names of the shape:

```
lii`7EXH@[hgD!I= !!!!!!=X&K.7z
```

The human's question was "was this expected?" — it was, exactly — followed by a
design ruling. **The ruling is already taken** and this plan implements it; §2
is the record of what was decided and why, not a menu.

This is a **read-breaking storage format change**. It is affordable only because
no store is in production use (human, 2026-08-27) — the same standing fact that
let WP10 withdraw legacy read support outright under SR-061.

---

## 1. What is wrong with the current grammar

`Get-HashSizeFileName` ([Modules/FileBackup.Common.psm1:379](../Modules/FileBackup.Common.psm1#L379))
emits `"<hash16> <len10><ext>"` over an 85-glyph alphabet
([:56](../Modules/FileBackup.Common.psm1#L56)) chosen for density: every
punctuation mark legal on both NTFS and POSIX, plus the alphanumerics.

Four distinct defects, only the first of which the human noticed:

1. **A screaming run of padding.** The length field is padded to a fixed 10
   digits and `!` is `Alphabet[0]` — the *zero digit*. 10 base-85 digits hold
   ~1.9e19, so every file under ~4 GB carries at least five leading `!`. The
   decoded example: hash `4E0F14958D71156767A1880F94`, length `8388608`
   (exactly 8 MiB) — six of its ten length digits are zeroes.
2. **The hash in the name is not the hash in the manifest.** 16 base-85 chars
   hold ~102.5 bits, so `Convert-HexToShortName` silently truncates the 128-bit
   xxHash128 to its low 26 hex digits (the `Substring` at
   [:355](../Modules/FileBackup.Common.psm1#L355)). Nothing can check a pool
   name against `MANIFEST.csv` without reproducing that truncation, and
   `Convert-ShortNameToHex` cannot round-trip to a comparable value at all
   because `BigInteger.ToString('X')` drops leading zeros and may prepend a
   sign nibble.
3. **The alphabet manufactures hostile leading and trailing characters.** `.`
   is in it, so a name can begin with a dot — which is what broke the CI
   fixture upload on 2026-08-23 ([status.md:3346](../docs/status.md#L3346)) —
   and a length field can *end* with a dot, producing the committed fixture
   `.nArDBFwE!yq[FFf !!!!!!!!#..bin` with its doubled dot. `-` is in it too, so
   a leading `-` is reachable in principle; the only reason it has never bitten
   is that every path handed to 7-Zip is absolute (see §7, R-2).
4. **The separator is a space, and space is not in the alphabet.** That works,
   but it forces quoting on every shell that ever touches the pool and it makes
   the field boundary invisible to the eye.

**The padding, not the alphabet, is what produced the run of `!`.** Both are
being fixed, but they are independent, and it is worth being clear that a
separator alone would have killed the exclamation marks.

---

## 2. The ruling

**Base-57, alphanumeric only, `_` separator, full 128-bit hash padded to 22, length unpadded.**

### 2.1 The alphabet

All 62 alphanumerics minus the visual-ambiguity class **`0` `O` `I` `l` `1`**:

```
23456789
ABCDEFGHJKLMNPQRSTUVWXYZ      (A-Z less I, O)
abcdefghijkmnopqrstuvwxyz     (a-z less l)
```

8 + 24 + 25 = **57**. `2` is `Alphabet[0]`, the zero digit.

Both confusion pairs die: `0/O` and `1/I/l`. Bitcoin's base58 keeps `1` on the
argument that once `I` and `l` are gone `1` is unambiguous — sound, and 58 was
offered — but the human chose the whole-family cut. **The choice is free**: 57,
58 and 62 all encode a 128-bit hash in 22 characters. Density is not a reason
to prefer any of them.

### 2.2 The grammar

```
<hash>_<len><ext>
  │      │     └── source extension when stored raw, '.7z' when we compressed it (unchanged)
  │      └─────── the Length, base-57, UNPADDED, no fixed width
  └────────────── the full 128-bit xxH2Hash, base-57, LEFT-PADDED to exactly 22
```

Worked example. The length is the real one decoded from the name at the top of
this plan (8388608); the hash is **illustrative, not the same object's** — the
old name truncated away the top 26 bits, so the original's full hash is not
recoverable from it, which is defect 2 demonstrating itself:

```
FteCEpB8GJDEajEtAtRE2L_oJua.7z    ← proposed grammar
lii`7EXH@[hgD!I= !!!!!!=X&K.7z    ← today
```

Both are 30 characters. The new one carries **26 more bits of hash** and no
padding run. A 1 TB object's length field is 7 characters; 8 MiB is 4.

### 2.3 Why the hash is padded but the length is not

Asymmetric on purpose. The **hash** is fixed at 22 so the field is stable,
sortable, greppable (`^[2-9A-HJ-NP-Za-km-z]{22}_`) and validatable without
parsing — and because a hash with leading zero bits is rare, its pad character
`2` is an ordinary-looking glyph rather than a visible defect. The **length** is
the field whose natural magnitude varies over ten orders, so fixed width there
is what produced the `!!!!!!` in the first place. The separator makes both
unambiguously parseable regardless.

### 2.4 What this buys beyond legibility

- **The name becomes checkable against the manifest.** With the whole hash and
  an exact round-trip, `PoolAudit` can assert name-equals-`xxH2Hash` outright
  instead of reproducing a truncation.
- **On a case-INSENSITIVE volume the name is worth ~112 bits, not 128** — the
  57 glyphs fold to 34 classes (23 two-case letter classes + 3 singleton
  letters + 8 digits), and `34^22` is 111.92 bits. Say 128 only of a
  case-sensitive filesystem. This is still a large IMPROVEMENT on today, where
  85 glyphs fold to 59 and `59^16` is **94.12** bits: +17.8 bits. See §9/T1.
- **SR-055's hostile-name classes become unreachable by construction.** A
  base-57 name cannot begin with `.` or `-`, cannot end in `.` or a space,
  cannot contain a space, a glob metacharacter, or a 7-Zip `@` response-file
  sigil. Defect 3 above is not fixed, it is *dissolved*.
- **The `Move-Item -Destination` wildcard question goes away.** Today
  [Engine:3247](../Modules/FileBackup.Engine.psm1#L3247) passes a short name
  containing `[` to a non-literal `-Destination`. I tested it — it behaves
  correctly, because a non-matching wildcard destination is treated as a
  literal — but it is a correctness argument that has to be re-made every time
  someone reads that line. Base-57 removes the premise.

---

## 3. Decisions — ALL THREE RATIFIED 2026-08-27

The human ratified the driver's recommendation on each, and added a standing
ruling that supersedes any compatibility argument below:

> **Nothing here needs to be backward compatible with older versions of this
> tool.** (human, 2026-08-27)

That ruling does **not** remove D-1. Refusing an old store is not backward
compatibility — it is the opposite: the guarantee that a grammar this build
cannot read is never *mis*read. SR-061's existing posture (refuse, exit 2,
write nothing, never convert) is exactly right and is extended, not relaxed.

### D-1 — how a rev-9 restorer refuses a rev-8 store — **RATIFIED: shape test**

A store written under the old grammar must be refused, not misread. SR-061
already establishes the pattern and the exit code (2, nothing written) for
`StoredAsHashSize='Original'` — but note that a base-85 content-addressed store
carries `StoredAsHashSize='Hash'`, so that column CANNOT tell rev-8 from rev-9.
The discriminator has to be something else.

**As ratified, the mechanism was "an old `DataPath` contains a space; a new one
cannot". The independent review (§9) destroyed that on two counts, and the
mechanism below is the repaired version.** The *decision* — refuse loudly,
exit 2, write nothing, never convert — is unchanged; only its implementation is.

**Two discriminators, both required:**

1. **Witness format version (authoritative).** `$script:WitnessFormatVersion`
   goes **1 → 2**. Every manifest write stamps it into `MANIFEST.csv.meta`, and
   both restorers already parse and range-check that line — today only for
   "newer than I understand". Add the other half: a witness declaring a version
   **below** 2 is a pre-WP12 store and is refused. This is present on EVERY
   store, whatever its rows look like, which is what fixes T3: a shape test over
   `DataPath` cannot classify a manifest whose `DataPath` values are all blank
   ("recover by hash" is a supported state), and a format version can.
2. **Structural name test (belt-and-braces).** A NON-BLANK `DataPath` in a
   **retired** grammar is refused: one containing a path separator (the pre-WP9
   path-addressed form), or one carrying the base-85 form's **space at index
   16**. That index is decisive — a WP12 name's first 22 characters are its
   hash field and are always alphanumeric. Catches a store whose witness was
   lost or rewritten.

   **This is a POSITIVE test for the old grammars, NOT "does not parse under
   SR-069".** The plan originally specified the negation and the suite caught
   it during implementation: those two are not complements. A merely DAMAGED
   `DataPath` — the `DanglingDataPath` class, a name something outside the tool
   rewrote — parses under neither grammar, and SR-049/SR-053/SR-056 require the
   per-row audit, heal and verify machinery to answer for it. The negative test
   refused the whole store instead, turning one repairable row into an
   unrestorable backup. **Refuse the old FORMAT; repair damaged ROWS.** See
   §9/T7.

**The test is structural, never a character blacklist.** T2's counter-example is
real and was reproduced on this host: `Test-PortableRelativePath` permits a
source file named `signed.foo bar`, `GetExtension()` returns `.foo bar`, and a
genuine rev-9 object is therefore named

```
<hash22>_<len>.foo bar
```

— which the ratified "contains a space ⇒ legacy" rule would have refused as a
legacy store. **That rule would have broken real backups.** The extension is
whatever the source carried; it is data, not part of the encoded grammar, and
only the hash and length fields are alphabet-constrained.

Rejected, unchanged: a positive `StoredAsHashSize='HashSize2'` row marker. The
witness version does the same job at the level format versions belong at, and
does not add a per-row claim that can drift from its object.

### D-2 — over-length input becomes an error, not a truncation — **RATIFIED**

`Convert-HexToShortName` currently truncates from the right when the encoding
exceeds `-OutputLength`. At 22 chars a 128-bit hash can never overflow, so the
branch becomes unreachable — and leaving a silent-truncation branch alive on the
function that names content-addressed objects is a trap. **Ratified: throw.**
This is the one change here that could turn a currently-silent situation into a
loud failure, so it is called out rather than folded in.

### D-3 — the leading-dot regression fixture is retired — **RATIFIED**

`tests/fixtures/bash-restore/*/.nArDBFwE!yq[FFf !!!!!!!!#..bin` is currently the
only committed artefact exercising a dot-leading pool name — the exact shape
that caught the `upload-artifact` hidden-files bug. After this WP no generated
name can start with a dot, so the fixture cannot be regenerated in the new
grammar and that regression coverage lapses.

**Ratified: accept the lapse, and keep `include-hidden-files: true` in CI with a
comment naming this plan as the reason it must stay.** The alternative — a
hand-maintained hostile-name fixture the generator can no longer produce — is a
fixture testing a shape the product can no longer emit. Recorded as a deliberate
coverage reduction rather than an oversight.

---

## 4. Changes

### 4.1 Code — smaller than it looks

`bash/reconstruct.sh` **needs no change to its logic at all**. It never decodes
a name: it walks the pool with `find -print0` and hashes candidates
([:527](../bash/reconstruct.sh#L527)), and only ever pattern-matches `*.7z`. The
POSIX twin is grammar-agnostic by construction. That is worth pinning as an
explicit property, not just enjoying once.

| File | Change |
|---|---|
| `Modules/FileBackup.Common.psm1` [:56](../Modules/FileBackup.Common.psm1#L56) | Replace `$script:Alphabet` with the 57-glyph set. Add `$script:NameSeparator = '_'`. |
| `Modules/FileBackup.Common.psm1` [:336](../Modules/FileBackup.Common.psm1#L336) | `Convert-HexToShortName`: `-OutputLength` becomes optional (omit ⇒ variable width, no padding); over-length throws (D-2). |
| `Modules/FileBackup.Common.psm1` [:365](../Modules/FileBackup.Common.psm1#L365) | `Convert-ShortNameToHex`: return exactly 32 hex digits, zero-padded, sign nibble stripped, so it compares equal to `xxH2Hash` directly. |
| `Modules/FileBackup.Common.psm1` [:379](../Modules/FileBackup.Common.psm1#L379) | `Get-HashSizeFileName`: `"<hash22>_<lenVar><ext>"`; hash at `-OutputLength 22`, length unpadded. |
| `Modules/FileBackup.Engine.psm1` [:845](../Modules/FileBackup.Engine.psm1#L845), [:1772](../Modules/FileBackup.Engine.psm1#L1772) | Extend the SR-061 legacy predicate per D-1. |
| `Reconstruct.ps1` [:664](../Reconstruct.ps1#L664) | Same predicate, same exit 2, message names the new cause. |
| `bash/reconstruct.sh` [:807](../bash/reconstruct.sh#L807) | Same predicate in the `die` path. Kit revision → **9**; header comment block updated. |

Two production call sites carry the widths today —
[:391-393](../Modules/FileBackup.Common.psm1#L391-L393) — and that is the whole
blast radius in the engine.

### 4.2 Tests and fixtures

| File | Change |
|---|---|
| `tests/Common/PoolAudit.ps1` [:150-151](../tests/Common/PoolAudit.ps1#L150-L151) | `Substring(0,16)`/`Substring(17,10)` → split on `_`. **Add the assertion the whole-hash change unlocks:** the decoded hash must equal the row's `xxH2Hash` exactly. |
| `tests/Common/PoolAudit.ps1` [:254-255](../tests/Common/PoolAudit.ps1#L254-L255) | Name reconstruction follows the new grammar. |
| `tests/Unit/Common.Tests.ps1` [:12](../tests/Unit/Common.Tests.ps1#L12) | Round-trip asserts *exactness* over 32 hex digits, including a hash with leading zero bits and one with the high bit set (the sign-nibble case). |
| `scripts/gen_bash_fixtures.ps1` | Rerun; both `bash-restore` trees regenerate. Mechanized — no hand-editing. |
| `tests/fixtures/hash-conformance/` | Untouched: it pins xxHash values, not names. |

**One canonical parser, `ConvertFrom-HashSizeFileName`, and nothing else may
parse a name** (T4: "split on `_`" is wrong — a legitimate extension may contain
`_`, as `x.a_b` does). It takes exactly the first 22 characters as the hash
field, requires `_` at index 22, consumes base-57 digits up to the first `.` or
end as the length, and keeps the remainder verbatim as the extension. It
rejects a decoded hash `>= 2^128`: `57^22` is 128.324 bits, so some
syntactically valid 22-char fields are out of range and must not be silently
truncated into a 32-hex string.

New unit cases (TC ids in §5): the alphabet has exactly 57 distinct glyphs and
excludes `0 O I l 1`; a generated name matches
`^[2-9A-HJ-NP-Za-km-z]{22}_[2-9A-HJ-NP-Za-km-z]+(\..*)?$`; a zero-length object
encodes as `2`; **an extension containing a space, `_`, a bracket or a non-ASCII
character round-trips** (T2); **an extensionless source stores and restores**
(T6); a 22-char field decoding to `>= 2^128` is rejected (T4); the legacy
refusal fires on a v1 witness AND on a structurally invalid `DataPath`.

### 4.3 Docs

- `README.md` [:485](../README.md#L485) — the `<hashShort> <sizeShort>.<ext>`
  sentence, with a worked example and one line on why base-57.
- `README.md` [:723](../README.md#L723) — **the Manifest-columns table's
  `DataPath` row, which states `"<hash16> <len10><ext>"` as the contract** (T5).
  This is the authoritative user-facing recovery-format text and the plan
  originally missed it.
- `AGENTS.md` §3 — the name grammar joins the invariant list; it is currently
  absent, which is how it came to be specified only in TC-004's `Expected`.
- `docs/status.md` — Current State + audit entry.

---

## 5. Registry amendments

**The grammar has no owning requirement today.** SR-003 specifies *dedup by
(hash, Length)* and says nothing about filenames; SR-021 is about
`-LiteralPath`. `Get-HashSizeFileName` back-links to both, and the only place
the format is actually written down is TC-004's `Expected` — a test case
describing behaviour no requirement states. That is the real traceability
finding here, and it is fixed by adding a requirement rather than by widening
SR-003's prose.

| Id | Action |
|---|---|
| **SR-069** *(new)* | *Stored-object name grammar.* Owns the alphabet, the separator, the padded-hash/unpadded-length asymmetry, and the property that a generated name is a legal, quote-free, non-hidden filename on both platforms. Phase `name-v1`, Verification `Test`, Priority `M`, Status `Planned`. |
| **SR-061** | Amend: refusal predicate extended per D-1 — witness version `< 2`, or any non-blank `DataPath` that does not parse under SR-069's grammar. Acceptance line for a constructed base-85 store refused by BOTH restorers with exit 2 and nothing written, including a variant whose `DataPath` values are all blank (T3). |
| **SR-070** *(new)* | *Stored-object names carry an opaque extension.* The stored name's extension is the owner's source extension verbatim (or `.7z`), is NOT alphabet-constrained, and MAY be empty. Fixes the T6 crash and pins T2's property so no future guard reintroduces a character blacklist. Phase `name-v1`. |
| **SR-003** | Unchanged in substance. Rationale gains one sentence: the name grammar moved to SR-069. |
| **SR-055** | Rationale note: the classes it refuses at *source* scan are now unreachable in *generated* names by construction. No normative change. |
| **LLR-070** *(new)* | `FileBackup.Common;FileBackup.Engine` / `Get-HashSizeFileName;Invoke-BackupFileGroup` — `-Extension` accepts the empty string; the owner's extension flows through untouched. |
| **LLR-069** *(new)* | `FileBackup.Common` / `Convert-HexToShortName;Convert-ShortNameToHex;Get-HashSizeFileName` — the encoder pair and the name builder; exact 32-hex round-trip; over-length throws. |
| **LLR-003, LLR-021** | `CodeSymbol` and `Detail` follow the new grammar; both are `Status: Planned` today and stay so. |
| **TC-004** | Amend `Expected` to the new grammar and the exactness assertion. |
| **TC-142…TC-149** *(new)* | Alphabet composition; name shape regex; zero-length encoding; sign-nibble/leading-zero round-trip; out-of-range 22-char field rejected; **hostile-extension round-trip (space, `_`, bracket, non-ASCII)**; **extensionless source end-to-end in Plain AND Compress (T6 regression)**; legacy refusal by witness version and by structure, all three paths. |

Next free ids confirmed against the registries: **SR-069/SR-070, LLR-069/LLR-070, TC-142…TC-149**.

Phase tag **`name-v1`**, deliberately *not* added to the ratchet in
[scripts/check.ps1:121](../scripts/check.ps1#L121) until the evidence run lands
— so SR-069 reports as phase-deferred (as SR-033 does today) instead of failing
G3 while the work is open. The ratchet arms in the shipping commit.

---

## 6. Verification

Nothing here is reportable without the real output.

1. `pwsh scripts/check.ps1 -Tier Full -Gate G3` — lint, trace, unit,
   integration, doc freshness. Baseline to beat: unit **437/437**, integration
   **240 PASS / 0 FAIL / 2 SKIP** (2026-08-26).
2. `python scripts/trace.py --strict --require-verified --phase <ratchet>,name-v1`
   — 0 orphans / 0 integrity / 0 status-findings.
3. Ubuntu WSL: `bats` (baseline **79/79**) + `shellcheck` clean. The bash half
   changes only its refusal message and header, but the fixtures it reads are
   entirely regenerated — this is the run that proves the regeneration.
4. **A byte-exactness check that does not rely on the suite:** back up a tree
   under the new grammar, restore through *both* restorers, compare hashes.
5. **A deliberate negative:** construct an old-grammar store, confirm all three
   paths (engine backup, `Reconstruct.ps1`, `reconstruct.sh`) refuse it with
   exit 2 and write nothing.

---

## 7. Risks

- **R-1 — a regeneration that silently produces a wrong store.** The fixtures
  are the oracle for the bash suite, and this WP rewrites all of them. §6 step 3
  plus the new PoolAudit name-equals-hash assertion are the guard: an
  incorrectly regenerated pool now fails on the *name*, not only on content.
- **R-2 — the missing `--` guard on the PowerShell 7-Zip calls survives this
  WP.** [Common.psm1:444](../Modules/FileBackup.Common.psm1#L444) and
  [:478](../Modules/FileBackup.Common.psm1#L478) hand-build the argument string
  with no end-of-options guard; base-57 removes the *reachability* of a leading
  `-` or `@`, but not the latent hole. **Out of scope here by choice** — it is a
  separate one-line hardening with its own test, and folding it in would blur
  what this WP's evidence proves. Carried as a live item.
- **R-3 — coverage lapse from D-3**, recorded above rather than discovered
  later.
- **R-4 — there is no collision rail on the content-addressed write path.**
  `Invoke-BackupFileGroup` ([Engine:3100](../Modules/FileBackup.Engine.psm1#L3100))
  writes to the derived name without proving that an object already at that
  name is the same content. A hash collision — or a case-fold collision on
  NTFS — would silently overwrite the only stored copy while both manifest rows
  survive. **Pre-existing, not introduced here, and WP12 makes it 17.8 bits less
  likely** (§9/T1). Out of scope, carried as its own live item: the fix is a
  verify-or-fail rail on the write path, which is an SR-029 conversation, not a
  naming one.

## 8. Out of scope

Re-forming or migrating any existing store (SR-061 stands: refuse, never
convert). The `--` guard (R-2). Any change to the hash function, the manifest's
9-column schema, or the `Compressed` column's fate (the S1 follow-up is still
recorded and unstarted).

---

## 9. Independent review — OpenAI gpt-5.6-terra, medium effort, via `codex exec` — 2026-08-27

Human-directed, adversarial charter, read-only sandbox, run against the plan at
commit `220f301`. **5 findings: 1 P0, 2 P1, 2 P2.** Every one was checked
against the code before disposition; two were reproduced on this host. Verdict:
**two findings would have shipped a defect, and one of them would have broken
real backups.** Dispositions below; all in-body sections above are already
amended.

### T1 (P0 as filed) — mixed-case base-57 is not injective on NTFS — **ARITHMETIC ACCEPTED, SEVERITY REDUCED, RECOMMENDATION DECLINED**

Terra's arithmetic is right and I had waved this away earlier as negligible
without doing it. The 57 glyphs fold to **34** case-insensitive classes (23
two-case letter classes, 3 singleton letters `i`/`o`/`l`, 8 digits), so a
22-char field is worth `34^22` = **111.92 bits** on a case-insensitive volume,
not 128.

**What Terra did not do is compare against the baseline.** Today's 85 glyphs
fold to 59 classes over 16 chars = **94.12 bits**. So WP12 *improves* the exact
property T1 flags by **+17.8 bits**. At a billion stored objects the birthday
probability moves from ~`2^-35` to ~`2^-53`. It is not a P0 and it is not
introduced here.

Declined: making the codec case-insensitive-injective. That means lowercase-only
or base-36, which contradicts a ratified human decision and buys nothing at
these probabilities. **Accepted:** the plan no longer claims "the full 128 bits"
without qualification (§2.4 now states both figures), and the genuine gap Terra
found underneath — that there is no collision rail on the write path at all —
is recorded as **R-4** and carried as a live item rather than folded in.

### T2 (P1) — the D-1 space test rejects VALID new stores — **VALID, REPRODUCED, FIXED**

The most valuable finding in the set. The stored name ends in the OWNER'S SOURCE
EXTENSION when stored raw ([Engine:3052](../Modules/FileBackup.Engine.psm1#L3052),
[:3099](../Modules/FileBackup.Engine.psm1#L3099)), and `Test-PortableRelativePath`
permits spaces mid-name. Reproduced with a real backup on this host — the pool
contained:

```
f7(#5C=v.uYfdGbp !!!!!!!!!%.foo bar
```

A rev-9 store would name that object `<hash22>_<len>.foo bar`, and the ratified
"a `DataPath` containing a space is legacy" rule would have refused a
**brand-new store** — in the engine and in both restorers, exit 2. That is a
break of normal backups, shipped by a plan that had already been ratified. The
same applies to `.a-b`, `.[x]`, `.你好`.

Fixed: D-1 is now a **structural parse**, never a character blacklist, and the
extension is explicitly opaque and unconstrained (new **SR-070** pins that so no
future guard reintroduces the blacklist).

### T3 (P1) — the shape test cannot classify a blank `DataPath` — **VALID, FIXED, MECHANISM CHANGED**

Blank `DataPath` means "recover by content hash" and is a supported state, so a
test over `DataPath` values cannot classify a manifest whose values are all
blank. Confirmed adjacent fact that makes this worse: a base-85
content-addressed store carries `StoredAsHashSize='Hash'`, so the existing
column cannot tell rev-8 from rev-9 either.

Terra's recommendation — a versioned, witnessed format marker — is better than
the ratified shape test and is **adopted**: `$script:WitnessFormatVersion`
1 → 2, present on every store, with the restorers' existing version range-check
extended downward. The structural test is kept as the second line for a store
whose witness was lost. Verified against the review's own objection to a
positive marker: a *format version in the witness* is not a per-row claim that
can drift from its object, which is what D-1(b) was rejected for.

Terra rated the impact higher than it is — the locators are content-addressed,
so an unrefused old store would in fact still restore correctly — but the plan's
stated property ("old stores are refused loudly") was genuinely not met.

### T4 (P2) — parser underspecified, and `57^22 > 2^128` — **VALID, FIXED**

Both halves right. "Split on `_`" breaks on a legitimate extension containing
`_` (`x.a_b`), and `57^22` = 128.324 bits means some syntactically valid 22-char
fields decode above `2^128` and must be rejected rather than truncated. §4.2 now
specifies one canonical parser, `ConvertFrom-HashSizeFileName`, with
first-separator-only parsing and an explicit range check.

### T5 (P2) — documentation inventory incomplete — **VALID, FIXED**

[README.md:723](../README.md#L723) — the Manifest-columns table's `DataPath` row
— states `"<hash16> <len10><ext>"` as the user-facing recovery contract, and the
plan updated only line 485. SR-058's `Rationale` carries the grammar too. Both
added to §4.3 / §5.

### T6 — found by the driver while reproducing T2, NOT reported by the review — **LIVE PRODUCTION BUG, P0, FIXED HERE**

Probing T2's extension question turned up a defect in shipped code that has
nothing to do with the redesign:

> `Get-HashSizeFileName`'s `-Extension` is `[Parameter(Mandatory)]`, which in
> PowerShell **rejects the empty string**. An extensionless source file
> (`README`, `LICENSE`, `Makefile`, `Dockerfile`) in a set with
> `CompressEnabled: false` therefore takes `$dataExt = $ownerExt = ''` at
> [Engine:3099](../Modules/FileBackup.Engine.psm1#L3099) and **fails the entire
> backup set**.

Reproduced end-to-end on this host, real output:

```
[INFO]  New or changed files: 3
[ERROR] Backup set 'Probe' failed: Cannot bind argument to parameter
        'Extension' because it is an empty string.
EXIT=1
```

Nothing was stored; the set aborted. It is invisible in Compress mode, because
an empty extension is not in `NonCompressibleExtensions` so
`Test-ShouldCompress` returns true and `$dataExt` becomes `.7z` — which is
exactly why no suite caught it. **No test in the matrix backs up an
extensionless file in Plain mode.**

Folded into WP12 because it lives in the one function this WP rewrites and
leaving a known set-killing crash in it would be indefensible. Carried as
**SR-070 / LLR-070 / TC-148**, with the Plain-mode extensionless case added to
the matrix so it cannot regress.

### Non-findings the review positively cleared

- `57^22 > 2^128` — the field genuinely has the capacity.
- `BigInteger.Parse("0"+hex, AllowHexSpecifier)` is correct and non-negative for
  all 32-hex inputs (zero, leading-zero, high-bit-set, all-`F` checked); the
  normalize-to-32 approach is sound for in-range values.
- The full hash in the name is a real improvement over the ~102-bit truncation.
- **`bash/reconstruct.sh` does not decode stored-object names** — the plan's
  central scope claim, independently confirmed by reading the locator.

### T7 — found by the SUITE during implementation, not by any reviewer — **PLAN DEFECT, FIXED**

The ratified-and-repaired D-1 was still wrong, in a way neither the driver nor
the review caught by reading: it specified the structural test as *"every
non-blank `DataPath` must parse under SR-069; anything else is refused."*

Five unit tests and six integration assertions failed on it, and they were
right. **"Not the current grammar" and "a retired grammar" are not the same
predicate.** A `DataPath` that is merely DAMAGED — the `DanglingDataPath` class,
or a name something outside the tool rewrote — parses under neither, and
SR-049/SR-053/SR-056 exist precisely to audit, heal and verify those per row.
The negative test refused the **whole store** instead, so one repairable row
became an unrestorable backup and `-RepairStorage` could never run on it.

That is a regression against three shipped requirements, introduced by a gate
meant to protect data. Fixed by inverting the test: `Test-LegacyStoredObjectName`
(and bash's `is_legacy_stored_name`) answer *"is this one of the two RETIRED
grammars?"* — a path separator, or the base-85 form's space at index 16 — and
nothing else is treated as a format marker. **Refuse the old FORMAT; repair
damaged ROWS.**

Worth recording as its own finding: the strict version *looked* stronger, and
both the driver and a review that was specifically hunting D-1 defects read past
it. What caught it was running the suite.
