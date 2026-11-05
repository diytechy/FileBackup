# DeepSeek assumptions cross-review

Date: 2026-11-05 (America/Chicago). Advisory review, not approval.

Provider/model: `opencode-go/deepseek-v4.1-flash`, OpenCode CLI 1.19.4,
`--variant low`. The reviewed assumption text is the draft committed as
`8346411`; the needs and active frame are approved. Five complete documents
were attached separately under 50 KB, each with an end marker: stakeholder
needs, external frame, assumptions, hats and owner-review-01. The reviewer
confirmed complete receipt and counts below. It received no implementation
code. Tools and external plugins were disabled, with a fresh temporary working
directory; global OpenCode instructions may still influence its context.

The request was to inspect every assumption and surrogate, identify at most
six material defects without forcing a count, and distinguish an environmental
limit from a waiver of approved behavior or a later design/test decision.
An initial default-effort attempt exhausted its reasoning budget without a
report; it is not evidence. The completed low-effort rerun below is the one
used. The prompt, marked inputs and event streams remain locally under ignored
`.artifacts/assumptions-review/`.

See the [assumptions review guide](assumptions-review.md) for the disposition
of every finding and the corrections applied after this response. The reviewer
has not reviewed those later corrections. No row was approved by this review.

## Reviewer response (verbatim wording)

Trailing whitespace and line endings are normalized.

Receipt confirmed. All five END OF COMPLETE INPUT markers are present. Counts match: stakeholder-needs 49 needs; external 18 entities, 24 crossings including inactive B-24, 5 relationships; assumptions 22 DA + 2 SUR; hats 9; owner-review-01 complete. No truncation.

## Material findings

**1. DA-17 + SUR-01 — unsupported fixture generalization.**
SUR-01 is "temporary folders mapped to drive letters," but DA-17 says it represents Windows local-filesystem operations "on their actual backing filesystem" and lists B-03 (capacity/volume identity) and B-04 (coordination/ownership) among its effects. A drive-letter mapping layer is not the backing volume: it need not exercise real volume identity, allocatable capacity, removable-volume events, or cross-process ownership/lock-release behavior. The falsifier's "matching real volume under equivalent conditions" is undefined because the mapping layer itself is not equivalent to a local volume.
*Smallest correction:* narrow SUR-01/DA-17 to file, name and rename behavior actually exercised through the mapping; explicitly exclude B-03 capacity/volume identity and B-04 ownership from its evidence unless separately exercised on a real local NTFS volume; record that no network, removable, Linux/macOS or power-loss evidence is supplied.

**2. DA-03 — product validation placed inside an environmental holding condition.**
DA-03 holds only when "the configuration assigns each backup set a unique resolved backup root." That is the product admission/refusal obligation in SN-039, not an environmental premise. The header's rule that a failed premise does not erase refusal mitigates this, but the row is still category-confused and can be cited as "coordination not promised" when duplicate roots exist.
*Smallest correction:* state that unique-root validation and refusal are required independently; DA-03 should assume only that a configuration already validated to unique resolved roots uses interoperable exclusion.

**3. DA-16 — dated state identity is left exposed.**
DA-16's `holds_when` says "Product handling of equal dates, rollback and state selection does not depend on assuming that timestamps are unique," which is product behavior, not an environmental condition. Combined with "displayed date order alone does not establish state identity," it leaves equal or rolled-back dates unresolved while SN-004/SN-006 use date to identify and select states. A restorer may not be able to select "exactly that state by its date."
*Smallest correction:* limit DA-16 to clock accuracy and timezone; move product handling to design/requirements; require equal or rolled-back dates to be disambiguated and reported—or a stable non-clock selection key—without reopening the date-based need.

**4. DA-19 — "complete-store handoff" is narrower than the approved frame.**
B-13/EXT-14 define the complete store as including carried guidance and required redistribution notices; SN-054 requires notices to travel with each recovery route. DA-19 lists only records, scripts and shared content. A handoff missing notices or guidance could still satisfy DA-19 and be called complete.
*Smallest correction:* add carried guidance and required redistribution notices to DA-19's preserved set and cross-reference B-13/SN-054.

**5. DA-10 + SUR-02 — offline recovery and cross-host coverage are broadened by the surrogate set.**
DA-10 allows tools "obtainable through an allowed online or offline installation path." If the only carried-script route relies on online provisioning, clean-machine recovery becomes network-dependent, contrary to SN-005's offline premise and SN-022's three-host route. SUR-02 is explicitly Linux-only, and no Windows or macOS restore-host surrogate is declared; the surrogate set cannot support the three-host recovery claim. SUR-02's own limits are honestly stated, so this is a coverage/broadening risk rather than a defect in its description.
*Smallest correction:* in DA-10, distinguish pre-disaster provisioning from recovery-time availability and require at least one documented route to work offline with present or bundled tools. Add an explicit coverage statement or surrogate for Windows/macOS recovery; do not let SUR-02's Linux results stand for them.

## Reasonable limits, not findings

DA-04 stable-file limits, DA-05 collision risk, DA-06 capacity estimates, DA-09 operator observation, DA-11 record provenance, DA-15 power-loss bound, and DA-22 host scheduling are reasonable stated limits or later design/test choices. They do not, as written, waive approved refusal, reporting or recovery behavior.

## Readiness

Not ready for approval as drafted. Ready for owner assumption review after the five localized corrections above. No implementation compliance is inferred; no implementation code was supplied. B-24 is noted as inactive debt and was not treated as an active crossing.
