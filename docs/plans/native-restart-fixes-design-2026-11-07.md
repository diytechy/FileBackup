# Design, 2026-11-07: two small fixes for a clean restart

**Status:** revision 2, reviewed; **built and merged** into `Rust-Rewrite` (`a223f5a`, 2026-11-07). Two review rounds by Sonnet at medium effort; the final verdict was approve. The Owner approved making both fixes in the same release as the
[native probe fix](native-probe-fix-design-2026-11-07.md), as separate small changes (that design's
§9 decision 7, ruled 2026-11-07). The approach below is the driver's, under that approval.

- Revision 1 was reviewed by an independent Sonnet reviewer at medium effort: "approve with
  changes". Its twelve findings are applied (§4).
- The result is reported to the Owner before merging.

Background: the [defect audit](../defect-audit-2026-11-07.md), §7.1 and §7.2.

**Order.** This change lands after the probe fix, on its own branch cut from it. It adds new
functions rather than changing `tools::compress`'s signature, so the two cannot collide.

## 1. The 7-Zip compression deadline

**Today.** `tools::deadline(length) = 300 s + 1 s per MiB` (`rust/src/tools.rs:349-351`). It has
three callers:

- compression (`:328`);
- the archive listing, `7z l` (`:398`);
- the expand, `7z e -so` (`:430`), used by the read-back check, the dedup check and deep verify.

Running past it is a host stop: the whole run ends with exit 4. For compression, the allowance
implies a floor of about 1 MiB/s, only 2.4 times below the hub's measured 2.4 MiB/s. A less
compressible file or a busier night can end the run on a healthy, merely slow file.

**Why keep a deadline at all.** It is the only bound on a 7-Zip process that has genuinely hung.
While it waits, the run holds the store lock, and every later scheduled run refuses. Nothing in the
store ages out a held lock. That is by design: the OS lock is released only when its holder exits.

**Change: compression only.** The listing and the expand are fast (expand runs at roughly
50-200 MiB/s), so they keep today's allowance; loosening them would only lengthen a real hang.
Compression gets two bounds, and whichever trips first is the host stop, as today:

1. **A ceiling of `300 s + 4 s per MiB`.**
   - That is a floor of about 0.25 MiB/s, ten times below the hub's measured rate.
   - A 21 GB file (20,027 MiB) gets 80,408 s, about 22.3 h. The multiplication is saturating.
2. **A stall bound: no growth of the archive for 60 minutes.**
   - The archive's size is already polled once a second for the progress line (§2).
   - Highly compressible input grows the archive slowly, but it also compresses fast: the sparse
     ESB file's zeros run at many times the media rate. Text at 10:1 grows the archive about every
     few seconds through 7-Zip's buffers.
   - An hour of no growth is far outside any healthy case on record. It bounds a true hang at about
     an hour instead of most of a day.

`tools::deadline` itself is unchanged, so the listing and the expand behave exactly as today. A new
`compress_deadline` holds the ceiling.

**Alternative considered and rejected:** storing the file raw when compression times out. The
measurement said compress, and SR-081 then requires compressed storage. Storing it raw silently is
a requirement change, not a timeout policy.

**Tests.**

- A unit test pins `compress_deadline` at 1 MiB, 1 GiB and 21,000,000,000 bytes, and pins that
  `deadline` is unchanged.
- A test-hooks test drives the stall bound, with a short injected stall window and an archive that
  stops growing, and expects a host stop that names the stall.
- The existing tool-deadline tests stay green.

## 2. The progress line during compression and archive checks

**Today.** The byte count moves only while the source is copied into `Incoming`:

- compression adds nothing;
- every archive check runs `verify_form_counted` with an empty counter (`tools.rs:373-378`);
- the phase still reads `capturing`.

So a 20 GB video, or a moved 20 GB folder (dedup check at `engine.rs:511`, destination check at
`:539`), shows one unchanged line for hours (audit §7.2). On 2026-11-07 that looked exactly like a
hang.

**Change: two new phases**, in this exact order after the existing seven:

- the `Phase` enum and `PHASES` array (length 9) gain `Compressing` / `"compressing"` and
  `ChecksArchive` / `"checking archive"`;
- `Counters::line` gains two match arms:

  - `Progress: set '<set>', compressing: <done> of <total> file(s), <X> of a <Y> file written, <s> s`
  - `Progress: set '<set>', checking archive: <done> of <total> file(s), <X> of <Y> expanded, <s> s`

  The file counts keep SR-159's known total. `<X>`/`<Y>` use the existing byte formatter. There is
  no path, file name, `archive-*` or `content.7z` in either line.
- **New counters**, kept apart from `bytes`, so "bytes read" and "a file's bytes count once"
  (LLR-191) are untouched:
  - `step_done`: archive bytes written, or bytes expanded;
  - `step_total`: the file's length.
- **Publish first.** On entering a phase, `step_total` and a zero `step_done` are stored before the
  phase, following `enter_counted`'s rule (`progress.rs:62-66`), so no line shows the previous
  file's figures.
- **Restoration is a drop guard.** `capture` returns early on every error (`?`), so a plain
  "enter capturing" afterwards would be skipped. A guard object restores `Capturing` and clears the
  step counters when it drops, on success or failure, as the reporter's own drop-based stop does.
- **The compression poll** lives in a new `tools::compress_counted(input, archive, counters)`,
  through an optional progress callback on `invoke`. Other callers of `invoke` are untouched.
  - The callback runs at most once a second, timed with `Instant`, not a loop count. It stats the
    archive: `NotFound` counts as 0, and any other error is ignored. A poll never fails a run.
  - The same size feeds the stall bound in §1.
  - The probe fix's `tools::compress` caller is untouched.
- **The archive check** gets a counting variant whose expanded bytes, and the raw branch's hash
  bytes, go to `step_done`, never to `bytes`.
  - It keeps the `FILEBACKUP_TEST_READ_HOLD_MS` hook.
  - `capture`'s three checks use it: the read-back after compression, the dedup check of an existing
    object, and the destination check. Deep verify keeps today's counting, which already counts
    into `bytes` by design.

**Requirement changes.**

- **LLR-191 `detail`:**
  - add the two phases, their lines and the step counters;
  - change "with no lock, stat or extra read" to allow "one archive stat a second during
    compression, outside the read loop";
  - state the drop-guard restoration.
- **TC-302:**
  - `parameters` gains `hold=compress` and `hold=check`;
  - `expected` gains the moving step count and the no-path rule for both new lines.
- **SR-159 is not edited.** Its permutations name phase kinds, and the new phases are the "counted"
  kind. SR-125 is already met, because the reporter is timer-driven. This change is diagnosability,
  not a conformance gap.

**Tests** (with the existing short injected interval):

- **A held archive check** (the read-hold hook) shows `checking archive` with a count that rises
  between lines.
- **A held compression** uses a new test hook that stands in a scripted archive-size source,
  because a real hold does not grow the archive. The count must rise between lines, and a
  non-growing source must trip the stall bound.
- **Every line:** no line holds a path or `archive-`/`content.7z`.
- **After the phase:** "bytes read" equals the fixture's source bytes. The phase returns to
  `capturing`, with cleared step counters, both after success and after a forced failure.
- **Not exercised:** the real-time growth of an archive on Windows.

## 3. What this does not change

The report, `backup.log`, stored bytes, the manifest, the restore kits, `tools::deadline`, and the
listing and expand allowances.

## 4. Review record (revision 1 → 2)

| # | Finding | How it was taken |
|---|---|---|
| 1 | The deadline should be set per use | Compression only (§1) |
| 2 | Cost of a hang; a stall bound is possible | Added, at 60 min (§1) |
| 3 | Phase restoration on errors | Drop guard |
| 4 | Stale step values | Publish first, cleared on drop |
| 5 | Exact line text and SR-159 | Exact lines (§2); SR-159 kept unedited, with the reason |
| 6 | LLR-191 wording; double-counting | Separate step counters; LLR text amended |
| 7 | Poll safety and scope | Only in `compress_counted`; errors ignored; `Instant` throttle |
| 8 | Dedup and destination checks were left frozen | Included |
| 9 | Signature conflict with the probe fix | New functions; lands after the probe fix |
| 10 | Test hooks | Scripted size-source hook; no-path assertions |
| 11 | Arithmetic | 21 GB is about 22.3 h, with a saturating multiply |
| 12 | TC-302 parameters | Amended |
