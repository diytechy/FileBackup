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

## 3. Decisions needing ratification before code

Three. The dial is HIGH and this is the data-integrity surface.

### D-1 — how a rev-9 restorer refuses a rev-8 store *(recommendation: shape test)*

A store written under the old grammar must be refused, not misread. SR-061
already establishes the pattern and the exit code (2, nothing written) for
`StoredAsHashSize='Original'`. Two ways to extend it:

- **(a) Shape test — recommended.** The grammars are disjoint in a decidable
  way: an old `DataPath` **contains a space**; a new one cannot. Extend
  SR-061's refusal predicate to "a `DataPath` containing a path separator, a
  space, or any character outside the base-57 alphabet plus `_` and `.`". No
  schema change, no new column, and it is self-enforcing — a store cannot lie
  about its own grammar the way a column can. This is precisely SR-068's
  lesson: derive from the bytes, do not trust a claim stored beside them.
- **(b) Positive marker.** Write `StoredAsHashSize='HashSize2'` on new rows and
  refuse anything else. Rejected as *primary*: it reintroduces the
  claim-apart-from-the-thing-it-describes defect class that WP11 spent its Part
  B removing, and a blank column (today's normal value, set at
  [Engine:545](../Modules/FileBackup.Engine.psm1#L545)) would have to be treated
  as legacy — a second, weaker shape test wearing a column's clothes.

I recommend (a) alone. Say so if you want (b) added as belt-and-braces.

### D-2 — over-length input becomes an error, not a truncation

`Convert-HexToShortName` currently truncates from the right when the encoding
exceeds `-OutputLength`. At 22 chars a 128-bit hash can never overflow, so the
branch becomes unreachable — and leaving a silent-truncation branch alive on the
function that names content-addressed objects is a trap. **Proposal: throw.**
This is the one change here that could turn a currently-silent situation into a
loud failure, so it is called out rather than folded in.

### D-3 — the leading-dot regression fixture is retired

`tests/fixtures/bash-restore/*/.nArDBFwE!yq[FFf !!!!!!!!#..bin` is currently the
only committed artefact exercising a dot-leading pool name — the exact shape
that caught the `upload-artifact` hidden-files bug. After this WP no generated
name can start with a dot, so the fixture cannot be regenerated in the new
grammar and that regression coverage lapses.

**Proposal: accept the lapse, and keep `include-hidden-files: true` in CI with a
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

New unit cases (TC ids in §5): the alphabet has exactly 57 distinct glyphs and
excludes `0 O I l 1`; a generated name matches
`^[2-9A-HJ-NP-Za-km-z]{22}_[2-9A-HJ-NP-Za-km-z]+(\.[^.]+)?$`; a zero-length
object encodes as `2`; the legacy refusal fires on a space-bearing `DataPath` in
all three restore paths.

### 4.3 Docs

- `README.md` [:485](../README.md#L485) — the `<hashShort> <sizeShort>.<ext>`
  sentence, with a worked example and one line on why base-57.
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
| **SR-061** | Amend: refusal predicate extended per D-1; add the acceptance line for a constructed base-85 store refused by both restorers with exit 2 and nothing written. |
| **SR-003** | Unchanged in substance. Rationale gains one sentence: the name grammar moved to SR-069. |
| **SR-055** | Rationale note: the classes it refuses at *source* scan are now unreachable in *generated* names by construction. No normative change. |
| **LLR-069** *(new)* | `FileBackup.Common` / `Convert-HexToShortName;Convert-ShortNameToHex;Get-HashSizeFileName` — the encoder pair and the name builder; exact 32-hex round-trip; over-length throws. |
| **LLR-003, LLR-021** | `CodeSymbol` and `Detail` follow the new grammar; both are `Status: Planned` today and stay so. |
| **TC-004** | Amend `Expected` to the new grammar and the exactness assertion. |
| **TC-142…TC-146** *(new)* | Alphabet composition; name shape regex; zero-length encoding; sign-nibble/leading-zero round-trip; three-path legacy refusal. |

Next free ids confirmed against the registries: **SR-069, LLR-069, TC-142**.

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

## 8. Out of scope

Re-forming or migrating any existing store (SR-061 stands: refuse, never
convert). The `--` guard (R-2). Any change to the hash function, the manifest's
9-column schema, or the `Compressed` column's fate (the S1 follow-up is still
recorded and unstarted).
