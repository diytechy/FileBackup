# Verification approach per external interface (round 3s, item 8)

**Draft for the Owner's review; a round-4 prerequisite.** For each interface
owned by a party outside FileBackup, this says how a test case will drive or
observe it. Round 4's test cases name these interfaces as where they observe,
which is also how the rows that constrain them get placed.

"Today" comes from a survey of `tests/` at `850f8a6`: Pester under
`tests/Unit` and the integration suites under `tests/Suites`, the bats suites
under `tests/bash`, the container job and CI. The approach words are: **real**
(the real external thing, in a fixture), **surrogate** (a stand-in the test
builds, such as a stub executable or a PATH shim), **mock** (a Pester mock of
the code that touches the external), and **attest** (a person confirms; no
automated test).

**Where the suites run today.** Pester runs on Windows only; CI uses
`windows-latest`. The bats suites and the container job run on
`ubuntu-latest`. The VHDX lane needs a self-hosted Hyper-V runner, and G8
(real USB) is manual. No lane runs Pester on Linux.

| IF | External | Today | Proposed for round 4 | Gap to close, or the Owner's call |
|---|---|---|---|---|
| IF-028 | Source tree view | **Real** fixtures on Windows: hidden, system, dot and read-only entries; a Deny ACE making a folder unenumerable, checked to have taken effect; a locked file held `FileShare.None`; a file deleted mid-run; one real trailing-dot name; volume-root pseudo-folders on subst roots. | **Real**, on both hosts the backup supports: Windows (Pester) and Linux (the container). | No test puts a link or junction inside the source (SR-137, SR-150, SR-151 are new behaviour, gap M18 and others). No backup-side walk edge case runs on Linux. No long-path case. |
| IF-031 | Volume space and identity | **Real** measurement on `$TestDrive` and a subst drive. **Mock** of the free-space and volume-identity functions for low-space and unmeasurable cases. Shortfalls also induced by inflating recorded lengths. | **Real** for measurement and identity, including a real UNC share (on the CI runner's own `\\localhost\` admin share or a created share) and a folder mount point. **Mock** stays only for "cannot be measured" on a mount type CI can't create. | **Owner's call:** a real `\\localhost\` share in CI exercises the new UNC measurement (M96) properly; it needs admin rights on the runner. Folder mount points (M66) are untested. The restorers' unmeasurable and bash refusal branches never run. |
| IF-035 | Archive tool (7-Zip) | **Real** 7-Zip (CI fails without it). **Surrogates**: a fake `7z.cmd` recording arguments, a non-executable `7z.exe`, a bogus path, and a bats `fake7z` exiting 2. The container uses real p7zip. | Keep **real** for content, **surrogate** for failure and absence. | The `FILEBACKUP_7ZIP_PATH` override and PATH discovery (`7z`, `7zz`, `7za`) are untested. No full backup runs with compression on and 7-Zip absent. |
| IF-036 | Media probe (ffprobe) | Only the **absent** case is tested; every other test passes no ffprobe. The entry point disables media measurement, so the probe is never called. | **Surrogate**: a stub ffprobe that prints a fixed duration (and one that fails), so the space view's rate (LLR-133) and its "not measured" path (LLR-134) are tested without shipping ffmpeg. | The media rate is not built (CMP-015's note; the space view is a design gap). The approach is ready when it is. |
| IF-037 | Package source (System.IO.Hashing) | **Real** NuGet install in setup, cached in CI; the image bakes the DLL with a sha256 check. Tests only assert the DLL is copied into the kit. | **Surrogate**: a local folder posing as the package source, with good, corrupt and missing packages; offline is the empty source. | **Nothing tests obtaining the component today** (LLR-105, SR-132, gap M15). This is the largest untested external besides the credential. |
| IF-046 | Backup runtime and tool floor | Missing optional tools are tested as unit tests and as the prune refusal. No product script checks the PowerShell version. | **Real** for "tools present". **Surrogate** for missing or old tools (a bogus path, a shim). The runtime version check is a unit test with an injected version. | The product has no runtime version check today (LLR-020 is new behaviour). Testing on a real old runtime is **attest** at most. |
| IF-024 | Restore tool floor | **Real** GNU tools, xxhash, p7zip and gawk on Ubuntu. BSD and busybox imitated by **surrogate** PATH shims. Version gates checked by grepping messages, which the suite says is deliberate. Launchers checked statically. | Keep **real** GNU plus **surrogate** BSD/busybox shims. **Attest** a real macOS run per release. | No real macOS or busybox run; no bash 3.2; the `xxhsum -H128` fallback never runs. **Owner's call:** whether a macOS release attest is worth adding to the release checklist. |
| IF-025 | Restore target probe | **Real**: a junction into the backup, `..` normalisation, a target that is a file, a space shortfall by inflated lengths, attributes on NTFS, attributes reported inapplicable on Linux. | **Real**, adding a target filesystem that cannot hold attributes or exact times, and a read-only target. | No FAT or exFAT restore target. **Owner's call:** an exFAT target needs a VHDX or USB lane (self-hosted or manual G8), or it stays **attest**. |
| IF-026 | Restore host session | The session decision is a pure function tested as a full matrix; bats tests "no desktop" by unsetting the display variables. | **Mock** at the session decision (pure function). Add one end-to-end run with input redirected, to tie the script body's wiring to it. | The script body's wiring (redirected input, non-interactive, no-dialog variable) is never checked end to end. |
| IF-027 | Folder choice dialog | **Surrogate**: an injected picker scriptblock on Windows; a picker stub via `FILEBACKUP_PICKER` in bats, including a path with spaces and a cancel. | Keep the **surrogate**. **Attest** the real dialogs (WinForms, macOS, zenity, kdialog) per release. | The real toolkits never run in a test; they can only be attested. |
| IF-012 | Protected notification credential | **Not tested.** Every fixture has no secrets and every run passes `-NoMail`. | **Real** on Windows: the credential helper writes a protected credential, the run reads it and hands it to a mail send replaced by a **mock**. **Attest** the real mail relay. | **Nothing tests the credential round trip today** (LLR-106, SR-128). Decrypting under another user, and the Linux form, are untested. |

## What this asks of round 4 and of the Owner

1. **The approach column is the round-4 default.** Each test case of a row
   constraining one of these interfaces names it as where it observes, and
   uses the approach given.
2. **Four calls for the Owner,** marked above:
   - a real `\\localhost\` share in CI, for the UNC measurement;
   - a macOS restore attest on the release checklist;
   - an exFAT restore target lane, or attest;
   - real mail as attest only.
3. **Three externals are effectively untested today:** the credential, the
   package source and the media probe. Their LLRs are new behaviour or
   unbuilt, so round 4 writes their first tests rather than re-tagging old
   ones.
4. **No lane runs Pester on Linux,** although the backup engine is meant to
   run there (the container, SR-034, SR-136). Today the container job is the
   only Linux backup coverage. **Owner's call:** add a Linux Pester lane in CI,
   or keep the container job as the Linux evidence.
