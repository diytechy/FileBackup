# Native implementation review record

The owner authorized Gemini Argon design review followed by DeepSeek 4.1 Flash
and Claude Opus low code reviews. Reviews are advisory inputs, not acceptance or
executed test evidence. The [workorder](implementation-workorder.md) records scope
and the [support matrix](../../native-support.md) records qualification limits.

## Design readiness

OpenCode Go `gemini-4-argon`, low, session
`ses_e506c19bfffeUs2sJiMTE5xOHH`, reviewed the accepted needs/SRs, boundary,
assumptions, draft LLR/TC/interfaces, store contracts and implementation workorder.
It returned READY FOR IMPLEMENTATION and no high-risk findings. Raw local output
is `.artifacts/native-transition/design-review.jsonl`.

## Foundation review

DeepSeek `opencode-go/deepseek-v4.1-flash`, low, session
`ses_e5058d16dffeYXbVueZIbfkB1w`, identified non-directory root admission,
ambiguous executable-path settings and missing cross-table validation. The first
two are corrected at admission; combined record validation runs before final
publication and during inspection. Interrupted file checkpoints can still recover
independently when older supplemental records conflict.

An earlier DeepSeek attempt hit its reasoning/output limit with no review text;
it is not counted as a completed review. The OpenCode Opus route returned account
HTTP 402, so subsequent Opus reviews used the installed Claude subscription CLI,
`--model opus --effort low`, with tools/hooks disabled and no session persistence.
This was a provider billing limitation, not a user permission rejection.

Opus session `8ed83cf9-0386-4a6f-a3a3-8c914b30a7a3` identified root aliases,
missing-tail ambiguity, Unicode comparison, redirected locks and publication
durability handling. Fixes include physical ancestor resolution, conservative
portable keys, no-follow lock acquisition, synced publication, Windows write-through
replacement and Unix directory sync. These mechanisms do not assert untested
network-filesystem or power-loss guarantees.

## Implementation review 01

Opus session `a884a1cf-859e-436a-8958-1238276e3562`, low, statically reviewed the
native core, maintenance and recovery code. It did not execute repros.

| Finding | Disposition |
|---|---|
| Older unselected states lose borrowed content after prune | Rejected as a policy change: accepted SN/SR cutoff semantics allow this. A regression now demonstrates both the protected latest state and the retained-but-invalidated older state. |
| Previous copies could be mixed after interrupted cleanup | Existing partial copies are left intact; a new member is never filled from another generation. Explicit previous recovery reports a missing companion. Valid previous file demand is conservatively protected by native prune. |
| Windows compressor sync/share handling; timeout mistaken for damage | Use a writable sync handle, close staged writers before 7-Zip, distinguish unavailable verdicts, scale deadlines and verify bounded extracted bytes before publication. |
| Retained rows collide with newly captured paths | Captured replacements remove conflicting old paths before checkpoints. Final pairs are validated; failed paths retain their prior spelling through normalized identity. |
| External aliases can reach stores; invalid/self-resolving folder links | Protect all configured store/view roots, validate captured destinations and treat self-resolving Windows reparse directories as ordinary directories. |
| Prune resumption and preserved-kit directories | Retain the explicit batch selection across deletion; permit only known ordinary prior-kit members during exact-file cleanup. |
| Damaged latest content blocks valid source/history replacement | Preserve damaged bytes in Verify after establishing usable replacement supply; publish the verified content and report the finding. |
| Recovery link failure and unbounded archive extraction | Missing required links produce incomplete results; extraction has byte/deadline bounds and target publication follows verification. |

## Implementation review 02

The source snapshot was saved locally as
`.artifacts/native-transition/review-02.txt` with SHA-256 file hashes in
`review-02-hashes.json`. Opus session
`679f566b-1cb3-4761-acaf-00e160612ddb`, low, reported no high-severity defects and
five medium findings. Its 16 supplied code/test files were read in full; the
unchanged carried Common/bash helper sources were not supplied in this round.

| Finding | Resolution |
|---|---|
| Compressed prune rehome still had an open writer | Close the staging write handle before extractor verification. |
| Failed capture after case-only rename drops the prior row | Compare removal eligibility using portable identity; add a Windows exclusive-file-lock regression. |
| Incomplete directory-to-link change retains stale descendants | Filter supplemental rows beneath the recorded link; add a Unix incomplete-walk fixture. |
| Compression disabled prevents discovery of an existing archive extractor | Resolve the local extractor on demand for existing compressed supply; new compression remains disabled. |
| Bash locale uppercase rejects valid dotless-I paths | Carry generated Unicode key data and independent PS/awk adapters matching Rust; test the affected names through both scripts. |

DeepSeek session `ses_e5030631dffeQ2DLGOC05KKqKV`, low, first exhausted its response
on reasoning. A follow-up requested its existing verdict. It then identified the
probe-mode inversion against the accepted SR-081 skip-listed-types policy. This
was corrected and regression-tested alongside the 256 KiB boundary and reuse of
compressed history with new compression disabled. Its attachment was truncated:
only config/engine and part of format were reviewed. It is **not** full-core
coverage; subsequent focused reviews must keep attachments below the CLI reader
limit. Raw local artifacts record both the length stop and the follow-up verdict.

## Implementation reviews 03–06

Opus review 03, session `a8f0b7bb-ab56-4c76-92db-027351366f0c`, covered
maintenance, subprocesses, kits, both readers, notifications and packaging.
Its concrete findings led to bounded count-only notification summaries,
per-state verification continuation, explicit unverified verdicts, default Windows
7-Zip discovery, removal of Bash's redundant pool scan and umask-derived output
permissions. Existing `.sh`/`.command` LF rules were supplemented for `.awk` and
the generated `.tsv`, with a carried-byte regression. Formatting was run.
The alleged preserved-kit overwrite did not apply: `platform::preserve` refuses
replacement. A mixed-live-kit regression now proves the previous route still
recovers and survives another refresh. TextFieldParser is available in the
exercised PowerShell 7 runtime; standalone tests executed successfully.

DeepSeek review 03 used a 587-line notification/configuration bundle, session
`ses_e4ff4c5efffeoHUatGDL7ksrGJ`. Its first response exhausted reasoning; the
follow-up delivered two findings. Neither proposed change was adopted:

- The hidden worker does not elevate privilege. The same invoking account already
  controls configuration and credential access; a caller token would not create
  a new security boundary or stop that account supplying another relay config.
- Ignoring a failure to disable macOS Keychain interaction could permit prompts.
  Keep the adapter unavailable on that failure; macOS/live credentials remain
  unqualified. Do not claim that a deprecated API necessarily fails on a host
  without an executed reproduction.

DeepSeek review 04, session `ses_e4fe7df6affexr2Xm7XNIe4ZTE`, reviewed a
1,217-line maintenance/tools/platform bundle. Its follow-up verdict reported no
provable high-severity loss and four medium issues. The code now distinguishes
unavailable and damaged supply in shallow inspection, labels that mode explicitly,
renders vanished view objects unavailable, and owns native tool process trees
with Windows jobs/Unix process groups plus bounded result-channel waits. A
pipe-holding descendant fixture checks the deadline. The alleged unjournalled
rehome failure was rejected: a retry indexes the already verified surviving copy.
A forced-kill regression before journal creation demonstrates that resumption,
alongside the existing post-deletion journal test.

Opus review 04, session `de59bc4d-08a2-4926-a536-82d56536272b`, found four
remaining reader defects. All were corrected and exercised: occupied directory
targets cannot masquerade as restored files; a verified raw alternate avoids an
unnecessary extractor prerequisite; links can target directories implied by file
paths in both readers; relative recovery roots are refused.

Opus review 05, session `23442211-89e6-49ec-844f-af1900dd76b3`, found two further
reader issues and no native tool-lifetime defect. Readers now reject containment
in both directions for detached records and the executing kit. PowerShell checks
its extraction deadline every read iteration, bounds post-kill waits and does not
wait indefinitely for descendant-pipe EOF. Bash bounds the entire extraction
pipeline with a forced-kill backstop and reports deadline status separately from
content damage. Detached-record/kit regressions preserve sentinel definitions.

Final focused Opus review 06, session
`43ad47f5-c502-405d-bf80-207fcfbf8a74`, returned **no remaining high-risk finding**
in those corrected containment, extraction and publication paths. This is scoped
static review, not proof of the entire program. It notes that unusual host path
aliases and platform pipe behavior need further qualification. The unchanged
carried helper source was not supplied in that final narrow round; its existing
regression suite is exercised separately.

Raw local artifacts are `review-03-*` through `review-06-*` under
`.artifacts/native-transition/`. Length-stopped DeepSeek responses are not counted
as delivered reviews; their follow-up verdicts and limited supplied scope are
recorded above. Neither reviewers nor test execution changed approval statuses.
