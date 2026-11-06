# DeepSeek fresh SR coverage review

Advisory, not approval. Date: 2026-11-05. Inputs were the approved needs,
external frame and assumptions at `7b4dcc8`, plus the nine review hats. No
legacy SRs, code, LLRs or tests were supplied. Four complete files under 50 KB
were attached separately with end markers. Provider/model:
`opencode-go/deepseek-v4.1-flash`, OpenCode 1.19.4, `--variant low`, `--pure`,
plan agent, denied tools and a fresh temporary directory. Global OpenCode
instructions may still affect context. The stream ended with `reason: stop`.
Prompts, marked inputs and raw event streams are local ignored artifacts under
`.artifacts/sr-generation/`.

The response below is preserved verbatim except normalized trailing whitespace
and line endings. Author dispositions and mapping are in
[the SR review guide](sr-generation-review.md). This proposal does not replace
the approved source documents; in particular item 7's “no action defaults to
backup” is incorrect: SN-024 requires a backup when no action is named.

## Response

**Input confirmation.** All four END OF COMPLETE INPUT markers are present: `assumptions.toml` (line 240), `external.toml` (337), `hats.toml` (70), `stakeholder-needs.toml` (495). Counts match the brief: 49 approved needs; 22 approved active assumptions plus SUR-01/SUR-02; 9 hats; active B-01…B-23 and REL-01…REL-05, with B-24 inactive debt. This is an input-restricted coverage proposal, not approval or an authoritative SR set.

Hat key: IR=Integrity-Recoverability, SEC=Security, SC=Shared-Content, SFC=Store-Format, FS=Filesystem, UA=Unattended, XP=Cross-Platform, PERF=Performance, LEG=Legal.

## Lifecycle coverage checklist

### A. Delivery, provision, startup
1. **Native delivery and notices** — SN-055, SN-054. Each declared OS/CPU ships an executable; redistributed components carry required notices in native/kit/container, with separately installed tools distinguished. {LEG,SFC,XP}
2. **Guidance and prerequisites** — SN-012, SN-015. Quickstart alone yields a first backup; a missing required tool refuses before mutation and names acquisition; skipped optional extras are recorded. {UA,SFC}
3. **Configuration contract** — SN-050, SN-027. Shipped example accepted unchanged but locations; unknown key, wrong type, missing setting or unsupported version is configuration-refused with the setting named and nothing created. {SFC}
4. **No unattended prompts** — SN-011. Scheduled backup, removal, check or restore completes or fails without reading stdin; a would-be question becomes failure with reason. {UA}
5. **Credential secrecy** — SN-049. Configuration, backup and run record yield no plaintext notification credentials; readable credentials are refused or never produced. {SEC}
6. **Notification behavior** — SN-010. Configured runs send success/failure; send failure records a warning without changing the operation outcome; disabled sends none. {UA}
7. **Container operation** — SN-024. An unprivileged container with read-only source and writable store performs backup, removal and saved-state report with the same outcomes; no action defaults to backup. {SEC,FS}
8. **Version and interchange boundary** — SN-040, SN-041, SN-023. Unsupported stores refused before mutation with old-store/kit guidance; the release explicitly designates older support (possibly none); cross-OS stores continue and restore the same bytes. {SFC,XP}

### B. Capture
9. **Whole-tree completeness** — SN-001. Every in-scope file restores or is named with a non-success outcome; hidden, system, dot-named and infrastructure-like nested names remain in scope. {FS}
10. **Unreadable-file handling** — SN-052. A brief lock is captured this run; a persistent unreadable file is named, the run fails, the earlier saved copy restores, and extra wait is bounded. {FS,UA,IR}
11. **Source non-mutation** — SN-037. A read-only source completes; no FileBackup state, byte, mtime, attribute or structure change occurs, excluding host-managed read effects. {FS,SEC}
12. **Missing or empty source** — SN-038. A previously populated source that vanishes or appears empty stops with non-success while prior content stays recoverable; a first-run empty source is accepted; retirement is explicit. {UA,FS}
13. **Multi-root isolation** — SN-009. One root failing does not stop others; the run reports overall failure. {UA}
14. **Re-read policy and unchanged runs** — SN-007, SN-021. The setting decides re-read deterministically; a same-size/time edit is caught on the first re-read; an unchanged run adds no saved state or changes. {FS,UA,PERF}
15. **Name representability** — SN-032. Unicode, brackets, parentheses and spaces restore unchanged where representable; invalid, case and normalization collisions are reported without overwrite or silent merge. {XP,FS}

### C. Store, space, interruption
16. **Content deduplication** — SN-002. Identical bytes across names, runs or states occupy one stored copy, and both restore byte-exact. {SC}
17. **Compression policy** — SN-003, SN-048. Savings policy applies only when measured; disabled means uncompressed; toggling never rewrites existing content or returns wrong bytes. {SC,SFC}
18. **Space insufficiency** — SN-019. Known shortfall is reported before unsafe work; mid-write exhaustion yields non-success, preserves completed content and prior states, and permits retry after space returns. {FS,UA,IR}
19. **Interruption and resume** — SN-013. A kill leaves prior states recoverable and every published record pointing at complete content; the next run repairs disposable state or reports the blocker. {IR,FS,UA}
20. **External content-loss self-heal** — SN-031. An externally deleted blob is re-stored by the next run; the affected file restores; an identical new file is stored for real. {SC,UA}
21. **Space/media report** — SN-051. Enabled lists files by size and media encoding measure; disabled or unmeasurable leaves backup behavior identical and records that the measure was not taken. {PERF}

### D. History, retention, integrity
22. **Saved states** — SN-004. Each content-changing run adds a dated state; an unchanged run adds none; the latest state is always listed. {SC,SFC}
23. **Cross-operation preservation** — SN-034. After edit, remove, rename or re-add within the window, all in-window states restore recorded bytes and the latest reflects changes. {SC}
24. **Retention cutoff** — SN-029. Removal at a date preserves the latest and later retained states; that date and earlier fall outside the promise even if folders remain; no relocation is required; documentation says so. {SC,FS,PERF}
25. **Retention estimate** — SN-046. A non-mutating report names the history, estimate basis and limits, cutoff implications, and is machine-readable; it does not change the store or promise exact future gain. {SC,PERF}
26. **Check coverage** — SN-030. Deleted, altered or misrecorded content is reported per file across the latest and every saved state, including damaged or out-of-window folders that remain; the store is byte-identical afterward; discrepancy yields failure. {SFC,IR,PERF}
27. **Repair** — SN-047. Certain defects disappear from a later check; uncertain defects remain reported; states that restored before still restore byte-exact. {SC,SFC,IR}
28. **Record validity and assurance** — SN-025, SN-033. Invalid or truncated records are refused or their invalid entries named without unsafe writes; every successful file passed documented checks; documentation states collision, substituted-record and out-of-observation limits. {IR,SFC}

### E. Coordination
29. **Single-configuration coordination** — SN-039. Duplicate resolved roots are refused before mutation with entries named; a competing mutation using the same valid configuration returns busy without changing protected data; the claim releases on holder death; independent configurations and external writers are out of scope. {FS,IR}

### F. Recovery and reporting
30. **Offline, state-selective recovery** — SN-005, SN-006, SN-022. A clean Windows, Linux or macOS host with the complete store and documented PowerShell/bash tools restores latest and dated states offline; missing tools are named before affected work; no engine, repository or network is required. {XP,SFC,IR}
31. **Restore containment** — SN-042. A target inside the backup or linked into it is refused before writes; an escaping path is not written, is named, and the restore fails; an ordinary external target is unaffected. {SEC,FS}
32. **Metadata and link fidelity** — SN-036. Identical twins keep their own mtimes; nested empty folders are recreated; Windows hidden/system folders restore or unsupported attributes are reported; an in-tree link restores as a link and unsupported links are reported. {FS,XP}
33. **Partial restore and result classes** — SN-053, SN-026. With a corrupt subset, every other file is byte-exact, each failure is named with cause and count, and failure is reported; the documented classes behave consistently across routes. {UA,XP,IR}
34. **Reporting, views, interaction** — SN-044, SN-045, SN-008, SN-035. Run records name added/changed/removed/failed files with causes and show progress at least every few minutes; outcomes are documented kinds; browse lists every path including duplicates and searches by name; double-click asks for a target and holds the outcome, while scripted starts do not prompt. {UA,XP}
35. **Scale budgets** — SN-043. At the documented scale and host class, a few-change run, a check and a full restore meet documented time and memory budgets; doubling history without source change does not double a few-change run. {PERF,IR}

## Easy-to-miss obligations and reconciliations

- **B-24 must stay retired.** No source-side change-detection state; SN-037 and the active frame forbid it.
- **Retention has two truths.** SN-034 preserves in-window states; SN-029 makes the cutoff authoritative; SN-030 still checks every remaining state, including damaged out-of-window folders, without promising their recoverability.
- **Do not overclaim integrity.** DA-05 and DA-11 limit content identity and record provenance; SN-033 success means required checks passed, not proof against collision or substituted records.
- **Coordination is deliberately narrow.** DA-02, DA-03 and SN-039 cover one validated configuration and unique roots only; broad locking language from SEC/FS hats must not expand it.
- **Surrogate evidence is bounded.** DA-17/SUR-01 exercise file, name and rename cases through mapped drives; they do not evidence capacity, volume identity, ownership or owner-death release.
- **External action is not guaranteed.** DA-09 and DA-22 mean notifications and progress are unambiguous signals; ignored mail or host suspension is not an SR failure.
- **Optional features must stay optional.** SN-051 off or unmeasurable, and SN-015 optional-tool absence, must not change backup behavior and must be visibly recorded.
- **Recovery independence is strict.** SN-055 native operation and SN-005/SN-022 carried-script recovery are separate; recovery must not require the engine, its repository or network.
- **No older version is supported merely by existing.** SN-041 permits designating none; SN-040 refusal must protect the independent recovery route.

## Open policy questions

1. What bounded retry/wait budget and schedule does SN-052 require for briefly locked files?
2. What exact library scale, host class, time budgets and memory bounds does SN-043 declare, and under what measurement conditions?
3. What compression savings threshold and measurement basis does SN-003 use, and is it per-file or aggregate?
4. What default re-read cadence does SN-007 ship, and what precisely does “decides the same way every time” guarantee?
5. Which content-integrity algorithm and check depth do SN-030/SN-033 require—full re-hash, sampled, or record-selective—given DA-18’s external-tool contract?
6. What estimate basis does SN-046 use for shared content and remaining out-of-window folders, given that exact future free-space gain is disclaimed?
7. What is the declared support matrix for SN-055/SN-024/SN-022: native OS/CPU combinations, container platforms, and restore-tool floors?
8. Which host credential facility does SN-049/DA-20 use on each platform, and what cross-host portability limit is documented?
