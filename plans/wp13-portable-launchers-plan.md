# WP13 — Portable POSIX restore, double-clickable launchers, and a folder picker

**Status:** PLAN, REVISION 2 — reviewed and repaired. No code written yet.
**Base commit:** `680136b`
**Kit revision:** 9 → **10** (both restorers; see F-1 — the marker never
actually reached 9)
**Gate:** G3. **Decision dial:** HIGH — §3 lists what needs a human ruling.

> **Revision 2 (2026-08-28)** folds in an independent adversarial review
> (§9: OpenAI gpt-5.6-terra, medium effort, via `codex exec`) and a driver-run
> sweep of every external command the POSIX restorer invokes. The review's
> verdict on revision 1 was **"not safe to implement as written"** and it was
> right: **T2 found that the proposed SR-009 guard could be walked straight
> through into the backup root.** Three portability defects the review did not
> find were caught by the sweep. §2.1 A3, §2.2 and §2.3 are materially
> different as a result.

---

## 0. Why this WP exists

Raised by the human as four questions about the restore entry points:

1. `RECONSTRUCT.cmd` instead of `RECONSTRUCT.bat`?
2. Can the restore open a **folder picker** on a desktop machine, and keep
   today's typed prompt when headless?
3. Can the `.sh` do that too?
4. Should there be a `.command` so macOS works?

Answering (4) honestly turned up something bigger: **`reconstruct.sh` produces
false verdicts on any BSD userland**, which today includes macOS-with-Homebrew
and FreeBSD/TrueNAS CORE — a NAS platform the script's own header claims as an
audience ([bash/reconstruct.sh:6](../bash/reconstruct.sh#L6)). That defect
(§1.1) is the load-bearing part of this WP; the launchers are the part the human
asked for; they ship together because the `.command` cannot honestly delegate to
a `.sh` that is wrong on macOS.

A fifth item was added mid-plan: **read-only stored objects** (§2.5). Only the
half that must ship first is in scope; the rest is WP14 (§8.1).

**The user-visible outcome:** double-click `RECONSTRUCT.cmd` on Windows or
`RECONSTRUCT.command` on a Mac, pick a folder in a normal file dialog, watch the
restore run, read the result before the window closes. No arguments, no recalled
incantation, no PowerShell required on the Mac.

---

## 1. What is wrong today

### 1.1 `reconstruct.sh` assumes GNU coreutils, and fails *wrongly* when it is missing

The script has a well-built fail-loudly floor — three gates at
[reconstruct.sh:724-726](../bash/reconstruct.sh#L724) refuse bash < 4, a missing
`gawk`, and a missing `xxhsum`, each with remediation text and exit 2. On a
**stock** Mac (bash 3.2) it stops there, correctly.

The defect is what happens to a user who **follows that advice**. After
`brew install bash gawk xxhash` all three gates pass — and seven GNU-specific
assumptions remain, each wrapped in a `2>/dev/null` fallback written for *"the
tool is absent"*, not *"the tool behaves differently here"*:

| # | Site | On a BSD userland | Consequence |
|---|---|---|---|
| P1 | `stat -c '%s'` — [:642](../bash/reconstruct.sh#L642) and 6 more | `-c` invalid → `-1` | **Witnessed store: `expected 41231, found -1` → `die_code 3`, "The index is damaged; nothing was restored"** on an intact backup. **Unwitnessed store:** the run proceeds and *every* row returns 22 from `restore_one` ([:244](../bash/reconstruct.sh#L244)) → **exit 4**. Two different false verdicts, one root cause. |
| P2 | `find … -printf '%f\n'` — [:913](../bash/reconstruct.sh#L913) | no `-printf` → empty | Snapshot pool silently collapses to the backup root; blank-`DataPath` rows → exit 1 "content unrecoverable" |
| P3 | `realpath -m` — [:551](../bash/reconstruct.sh#L551) | no `-m`, and the target does not exist yet at [:805](../bash/reconstruct.sh#L805) | `canon()` falls through to the raw string → the SR-009 "target inside the backup" guard compares uncanonicalised paths |
| P4 | `df -P -B1` — [:899](../bash/reconstruct.sh#L899) | no `-B` → empty | Capacity precheck silently skipped; SR-040's "insufficient capacity → 2" never fires |
| **P5** | `mktemp -d` — [:184](../bash/reconstruct.sh#L184), [:204](../bash/reconstruct.sh#L204) | GNU defaults the template; **BSD requires one** | `sevenzip_to_file` returns 1 → `restore_one` returns 20 → **every compressed row fails, reported as a 7-Zip host problem (exit 4)**, sending the operator to fix a tool that is not broken. **[:204](../bash/reconstruct.sh#L204) does not check the result at all** — `$w` is empty, so `printf > "$w/p.txt"` writes to the filesystem **root** and `rm -rf "$w"` cleans up nothing. That half is a latent defect on **every** platform whenever `mktemp` fails. |
| **P6** | `touch -d` — [:383](../bash/reconstruct.sh#L383) | BSD `-d` wants strict ISO-8601 | Both attempts fail → a WARN, and every restored file silently carries the **restore** time. A quiet **SR-066 contract violation** ("each file keeps its OWN mtime"). |
| **P7** | `date --iso-8601=seconds` — [:125](../bash/reconstruct.sh#L125) | GNU-only; falls back to bare `date` | `RECONSTRUCT.log` timestamps change format on BSD. Cosmetic, but the fix is exact. |

P1 matters most: it is the **first** thing that runs after the gates, and exit 3
means *"the index itself is untrustworthy"*. A recovery tool telling an operator
their manifest is damaged when it is byte-perfect is the worst wrong answer in
the exit-code table.

P2 is the most insidious, because it is silent: it re-creates exactly the failure
mode the adjacent comment was written to prevent (T2 of the 2026-08-25 review —
"silently shrinking the pool would let a blank row whose only copy lives in a
snapshot report 'your bytes are gone' for a host problem").

**Not defects, checked and cleared:** `${f,,}` at
[:459](../bash/reconstruct.sh#L459) — the bash-4 gate guarantees it. The `--`
end-of-options guards on `head`/`od`/`grep`/`basename`/`dirname`/`cp`/`df`
(cited by review finding T1) — `--` is POSIX Utility Syntax Guideline 10 and BSD
utilities honour it via `getopt(3)`; these guards are a deliberate safety
property this repo's status.md records as something the bash twin does *right*.
They stay (§9, T1).

### 1.2 There is no double-clickable restore

`RECONSTRUCT.bat` exists but is not usable by double-click: it passes `%*` to a
script that, with no arguments, prompts on stdin — and the window closes the
instant the run ends, so the operator never reads the outcome. `reconstruct.sh`
*requires* `--target-root`, so a double-click is guaranteed to print usage and
exit 2. macOS has no entry point at all.

This is not cosmetic. [docs/process-options.md:192](../docs/process-options.md#L192)
states the principle the kit already applies to `run.cmd`: *"the launch command
may be obvious, and it may be documented in the README, but recall is still the
enemy."* The moment an operator needs a restore is the worst possible moment to
ask them to remember a parameter name.

### 1.3 `.bat` is the odd one out

The repo's own convention is `run.{cmd,sh,command}` ([process-options.md:192](../docs/process-options.md#L192));
[run.cmd](../run.cmd) exists with no `run.bat`. `RECONSTRUCT.bat` predates it.
The two extensions differ only in `ERRORLEVEL` handling around a few built-ins
(`SET`, `PATH`, `ASSOC`), none of which the generated file uses, so the change is
free at the cmd.exe level and costs only contract churn (§5).

### 1.4 Incidental findings — pre-existing, not caused by this WP

**F-1 — the kit revision marker never reached 9.** `Get-BackupKitRevision`
([FileBackup.Engine.psm1:1693](../Modules/FileBackup.Engine.psm1#L1693)) reads one
source of truth: the `# KitRevision:` line in the bundled `RECONSTRUCT.ps1`. It
reads **8** ([Reconstruct.ps1:59](../Reconstruct.ps1#L59)). The bash twin reads
**6** ([reconstruct.sh:77](../bash/reconstruct.sh#L77)). status.md, README and
AGENTS.md all state WP12 shipped revision **9**, and both files' *prose*
describes revision 9 behaviour. So every SR-049 finding and every `-RefreshKits`
result names the wrong kit. Nothing catches it: the only assertion is
`Should -BeGreaterOrEqual 2` ([StorageForm.Tests.ps1:768](../tests/Unit/StorageForm.Tests.ps1#L768)).
Confirmed by the review. Fixed here (§2.6).

**F-2 — `SN-031` is assigned to two distinct needs**
([stakeholder-needs.md:39](../docs/requirements/stakeholder-needs.md#L39) restore
fidelity; [:40](../docs/requirements/stakeholder-needs.md#L40) self-healing).
`trace.py` does not check SN id uniqueness. **Not fixed here** (D-5).

**F-3 — the twins already disagree about symlinks** (review finding T3).
`canon()` uses `realpath -m`, which resolves symlinks; PowerShell's
`Test-PathIsInside` uses `GetFullPath`, which is purely lexical and never
resolves a reparse point ([Reconstruct.ps1:549](../Reconstruct.ps1#L549)). For a
junction pointing into the backup, bash refuses and PowerShell allows. **This
predates the WP** — but D-7 rules on it, because §2.1 A3 must not make it worse.

---

## 2. The design

### 2.1 Part A — POSIX portability of `reconstruct.sh`

Eight changes. **No restore logic is touched.** Each is a platform shim behind an
existing call shape.

**A1 — `stat_size()` replaces seven `stat -c '%s'` sites.** Probe once, against a
**known regular file**, and require **numeric output** — the probe validates
itself rather than trusting an exit status:

```bash
_stat_probe() {                # $1 = style, $2 = a regular file
    local out
    case "$1" in
        gnu) out="$(stat -c '%s' -- "$2" 2>/dev/null)" ;;
        bsd) out="$(stat -f '%z' -- "$2" 2>/dev/null)" ;;
    esac
    [[ "$out" =~ ^[0-9]+$ ]]
}
_STAT_STYLE=wc
_stat_probe gnu "${BASH_SOURCE[0]}" && _STAT_STYLE=gnu
[[ "$_STAT_STYLE" == wc ]] && _stat_probe bsd "${BASH_SOURCE[0]}" && _STAT_STYLE=bsd

stat_size() {                  # -> one integer, or -1
    local n
    case "$_STAT_STYLE" in
        gnu) n="$(stat -c '%s' -- "$1" 2>/dev/null)" ;;
        bsd) n="$(stat -f '%z' -- "$1" 2>/dev/null)" ;;
        *)   n="$(wc -c < "$1" 2>/dev/null | tr -d ' ')" ;;
    esac
    [[ "$n" =~ ^[0-9]+$ ]] && printf '%s' "$n" || printf '%s' -1
}
```

Revision 1 probed `stat -f '%z' -- /` and argued the order was unambiguous
because GNU would fail. **Review finding T4 disproved that:** on GNU, `-f` is
"filesystem status" and `%z` becomes a file *operand*, so the probe **succeeds**
whenever a file named `%z` exists in the working directory — silently selecting
the BSD branch on a GNU host and returning `-1` for every size. Requiring numeric
output for a file we know exists removes the dependency on cwd contents entirely.

**A2 — `list_snapshot_dirs()` replaces `find -printf '%f\n'`.** BSD `find` has
`-mindepth`/`-maxdepth` but not `-printf`; strip the basename with `sed`:

```bash
find "$change_root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
  | sed 's#.*/##' | grep -E "$SNAPSHOT_RE" | sort -r | sed "s#^#$change_root/#"
```

The review positively cleared this: ordering is preserved and the T2
unlistable-change-root branch at [:909-923](../bash/reconstruct.sh#L909) is
untouched. Safe against newlines because snapshot names are engine-generated and
already filtered by `$SNAPSHOT_RE`.

**A3 — `canon()` gains a fallback that REFUSES what it cannot resolve.**
*(Redesigned — revision 1's algorithm was unsafe.)*

Revision 1 proposed: normalise `..` textually, then resolve the deepest existing
ancestor with `cd -P`. **Review finding T2 (P0) showed that walks a target
straight into the backup root.** With `/outside/link -> /backup` and an ordinary
`/outside/backup/` also present:

```
--target-root /outside/link/../backup/victim
   kernel semantics : link -> /backup, then '..' -> /, then backup/victim
                      = /backup/victim          ** INSIDE the backup **
   revision 1 step 3: lexical '..' cancels 'link' before it is resolved
                      = /outside/backup/victim  ** judged outside, ALLOWED **
```

Lexical `..` reduction across an unresolved symlink is simply not path
resolution, and no ordering of the revision-1 steps fixes it. Reimplementing
`realpath` in shell to do it properly is not something this WP should attempt on
the SR-009 guard.

**The fallback therefore refuses rather than guesses:**

```
canon(path):
  1. realpath -m -- path            -> return it (GNU fast path, unchanged)
  2. otherwise (no realpath -m):
     a. if path contains a '..' component  -> REFUSE: exit 2, precondition,
        "cannot safely canonicalise a target containing '..' on this host;
         pass an absolute path with no '..'."
     b. make absolute against $PWD; strip '.' components and duplicate '/'
     c. resolve the deepest EXISTING ancestor with `cd -P … && pwd -P`
     d. re-append the non-existent tail  (a path that does not exist cannot
        contain a symlink, and by (a) contains no '..')
     e. on any failure -> REFUSE, exit 2 (never silently return the input)
```

Step (a) is what makes (d) sound. An operator never needs `..` in a restore
target, so refusing costs nothing real and turns a silent bypass into a loud,
testable precondition. Step (e) also closes a pre-existing weakness: today
`canon()` silently returns its input when `realpath` fails
([:551](../bash/reconstruct.sh#L551)), which is how P3 degrades the guard.

**A4 — capacity: portable fallback, integer-safe, and no longer silent.**

```bash
avail="$(df -P -B1 -- "$TARGET_ROOT" 2>/dev/null | awk 'NR==2{print $4}')"
if ! [[ "$avail" =~ ^[0-9]+$ ]]; then
    kb="$(df -Pk -- "$TARGET_ROOT" 2>/dev/null | awk 'NR==2{print $4}')"
    [[ "$kb" =~ ^[0-9]+$ ]] && avail=$(( kb * 1024 )) || avail=''
fi
[[ -n "$avail" ]] || log "WARN: capacity precheck skipped ($TARGET_ROOT): df returned no usable free-space figure."
```

`-P` is POSIX and exists precisely to stop long device names wrapping the row.
The multiplication moves into bash's 64-bit integer arithmetic rather than awk's
doubles (review T5). The `--` guards stay (§9, T5/T1). The `WARN` answers the
valid half of T5: today the precheck skips **silently**, so SR-040's capacity →
exit 2 quietly never fires.

**A5 — the three gate messages** gain macOS remediation and the PowerShell
alternative (§2.4).

**A6 — `touch -d` gains a POSIX `-t` fallback.** Convert the manifest's ISO-8601
stamp to `[[CC]YY]MMDDhhmm[.SS]` and retry with `touch -t` before warning. Today
a BSD host silently loses SR-066 (P6).

**A7 — `date --iso-8601=seconds` → `date +%Y-%m-%dT%H:%M:%S%z`.** Identical shape,
POSIX everywhere, removes the log-format divergence (P7).

**A8 — every `mktemp -d` gets an explicit template and a checked result.**

```bash
tmpd="$(mktemp -d "${TMPDIR:-/tmp}/reconstruct.XXXXXX")" || return 1
```

Correct on GNU and BSD alike, so it is the right change whichever way the BSD
default-template question lands. At [:204](../bash/reconstruct.sh#L204) the
result is **unchecked today**, so a failed `mktemp` yields an empty `$w` and
writes the self-test probe to the filesystem root; that gets a `|| { SEVENZIP_USABLE=1; return 1; }`
guard. This half is a defect on every platform, not only BSD.

**Deliberately NOT changed:** `gawk` and `xxhsum` stay **hard requirements**. The
manifest parser uses gawk's `FPAT` ([:271](../bash/reconstruct.sh#L271),
[:299](../bash/reconstruct.sh#L299)), which BSD awk and mawk lack; replacing it is
a new RFC-4180 parser needing its own SR-032 conformance campaign, not a shim
(§8.2). The `--` end-of-options guards stay (§1.1).

### 2.2 Part B — `RECONSTRUCT.cmd` replaces `RECONSTRUCT.bat`

*(Simplified — revision 1 put a `pause` in the batch file.)*

```bat
@echo off
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0RECONSTRUCT.ps1" -ExitCode %*
```

Identical to today's `.bat` but for the extension. **The window-holding moved out
of the shell and into the restorer** (§2.4): the restorer holds at the end *only
when it obtained its target interactively*, which is the one case where a human
is provably watching.

Revision 1 used `if "%~1"=="" pause` and claimed it could not hang automation. I
verified the redirected-stdin case (pause returns immediately, exit code
preserved) — but **review finding T6 is right that the claim was too strong**: a
console-attached caller invoking `cmd /c RECONSTRUCT.cmd` with no arguments and
no redirection blocks on the keypress and never delivers its exit code. Moving
the decision into the restorer removes the failure mode entirely rather than
narrowing it, and makes it Pester-testable instead of resting on batch
heuristics.

`RECONSTRUCT.bat` stops being written. It **stays in the infrastructure-skip list
forever** ([FileBackup.Engine.psm1:50](../Modules/FileBackup.Engine.psm1#L50)) —
omitting it would make the leftover file in every pre-rev-10 store an orphan and
produce a false not-in-DB WARN every run, the exact SR-022 regression recorded at
[:57](../Modules/FileBackup.Engine.psm1#L57). Completeness assertions become "the
current kit's artifacts", so a refreshed store holding both names still passes.

### 2.3 Part C — `RECONSTRUCT.command` for macOS

New repo file `bash/reconstruct.command`, copied into the backup root and every
snapshot, LF endings, delegating to the `.sh`:

```bash
#!/usr/bin/env bash
# Double-clickable macOS restore launcher. Finder opens this in Terminal with
# the working directory set to $HOME, so it must locate its own folder first.
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 2
[ $# -eq 0 ] && set -- --pick-target      # a double-click has no arguments
exec bash -- ./reconstruct.sh "$@"
```

Invoking `bash -- ./reconstruct.sh` rather than `./reconstruct.sh` means the
`.sh` **does not need its executable bit** — which matters, because that bit does
not survive being written by Windows. The end-of-run hold is the restorer's job
(§2.4), so the launcher stays a two-line delegation.

**Honest limitation (review finding T9), and the acceptance claim is narrowed to
match.** The `.command` itself *does* need its executable bit, and the kit is
written by Windows `Copy-Item` ([FileBackup.Engine.psm1:2713](../Modules/FileBackup.Engine.psm1#L2713)),
which cannot set a POSIX mode. It works where macOS synthesises permissions —
FAT/exFAT/NTFS volumes, i.e. the USB-stick case — and fails after a zip
round-trip onto APFS, where Finder refuses to launch it until `chmod +x`. So:

- SR-072's acceptance criterion names the volume classes where double-click is
  claimed, and no others.
- The **documented** macOS path stays `bash reconstruct.sh --pick-target`, which
  needs no executable bit at all. The `.command` is a convenience on top.
- README states the `chmod +x RECONSTRUCT.command` remediation explicitly rather
  than leaving an operator to discover it mid-recovery.

### 2.4 Part D — graphical target selection, and one strengthened guard

*PowerShell.* Split per the repo's pure-core/I-O-shell convention, because a
modal dialog can never appear in a test:

- `Test-ShouldPromptGraphically` — **pure**, every signal a parameter
  (`NonInteractive`, `NoGui`, `InputRedirected`, `UserInteractive`, `Platform`,
  `EnvNoGui`). Pester covers the whole matrix.
- `Select-FolderInteractively` — the I/O shell, with an injectable `-Picker`
  scriptblock so cancel-and-throw fallbacks are provable without a dialog.
  Windows → WinForms `FolderBrowserDialog`; macOS → `osascript -e 'POSIX path of
  (choose folder …)'`; Linux → `zenity --file-selection --directory`, then
  `kdialog --getexistingdirectory`.

**Apartment state.** Verified on this host: pwsh 7.6.5 runs **STA** by default and
`FolderBrowserDialog` loads clean. pwsh 7.0–7.2 defaulted to **MTA**, and this kit
lands on unknown machines, so `ShowDialog` is marshalled onto a dedicated STA
thread when `[Threading.Thread]::CurrentThread.GetApartmentState()` is not `STA`.

**The strengthened guard (D-6, from review finding T7).** Revision 1 said the
picker "cannot introduce a new blocking path". That is true — but T7 correctly
points out it leaves a **pre-existing** hole open: a Task Scheduler job running
"whether user is logged on or not", a service, WinRM, SSH or Server Core can
reach [Reconstruct.ps1:543](../Reconstruct.ps1#L543) with neither
`-NonInteractive` nor redirected stdin, and hang on `Read-Host` forever. That
directly violates SN-011 / SR-016, which this repo already ratified.

Since this WP is rewriting exactly that block, it closes the hole:

```
no -TargetRoot:
  -NonInteractive OR stdin redirected      -> usage + exit 2   (today)
  NOT UserInteractive (no console/desktop) -> usage + exit 2   (NEW, D-6)
  desktop available and GUI permitted      -> picker; cancel -> Read-Host
  otherwise                                -> Read-Host        (today)
```

The end-of-run **hold** (§2.2/§2.3) fires only on the last two branches — the
branches that already proved a human is present.

*Bash.* **`--target-root` stays required. A missing `--target-root` still prints
usage and exits 2, unchanged** — [exit_codes.bats:38](../tests/bash/exit_codes.bats#L38)
must stay green **without being edited**. That test is the twin-contract with
`-NonInteractive` under SR-016.

The picker is reached only through an explicit **`--pick-target`**: making a
missing flag open a picker would break that twin contract and create a path CI
can never exercise. With a flag it is testable — bats sets `FILEBACKUP_PICKER` to
a stub. If `--pick-target` is given and no picker is available or the user
cancels, `TARGET_ROOT` stays empty and the existing required-argument check
fires: usage, exit 2. Never a hang, never a silent default.

### 2.5 Part E — restores must not inherit a read-only pool (the half that has to ship first)

Requested mid-plan: mark stored objects read-only to blunt accidental deletion.
Confirmed with the human 2026-08-28: **the backup store is what should be
read-only; a reconstructed tree must be ordinary writable files.**

The write-side half is **WP14** (§8.1). What must ship *here* is the restore-side
half, for a sequencing reason that cannot be retrofitted: **a snapshot keeps the
kit it was written with, forever** (AGENTS.md §3). Both restorers propagate the
attribute today. Verified on this host:

```
src ReadOnly : True      # Copy-Item -Force  (Reconstruct.ps1:885)
dst ReadOnly : True      # -> a restored tree comes back read-only
Remove-Item -Force on read-only: OK
Remove-Item WITHOUT -Force on read-only: BLOCKED - IOException
```

`cp -f` ([reconstruct.sh:241](../bash/reconstruct.sh#L241)) gives a newly created
destination the source's mode bits, so POSIX behaves the same way. If the
write-side flag ever ships first, every already-deployed kit restores read-only
trees out of the protected pool, and no fix can reach them.

Change: after a successful write, both restorers clear the attribute on the
destination — `IsReadOnly = $false` on Windows, `chmod u+w` on POSIX — **before**
the existing verify-and-stamp steps, so SR-056 verification and SR-066 stamping
both operate on a writable file. Today this is a **no-op**, since nothing marks
the pool read-only; it exists so revision-10 kits are already correct when WP14
arrives. The 7-Zip extraction path gets the same treatment: `7z` sets the
destination's mode from the archive entry, not from the pool object, but the
clear is applied uniformly at the single write-and-verify choke point
(`restore_one` / `Restore-OneRow`) so no path can miss it.

It also closes a latent defect independent of WP14: a source file that was itself
read-only at backup time is stored read-only, and its restored copy is read-only
today — while WP10 explicitly ruled file attributes out of contract.

Prune, eviction and repair need **no** change: all 15 engine `Remove-Item` sites
already pass `-Force` (confirmed by the review). The same test shows the
protection is real: without `-Force`, deletion is blocked with `IOException`.

### 2.6 Part F — F-1, the kit revision marker

Both markers go to **10**, both files gain a revision-10 prose paragraph, and a
new test pins the markers to a single constant so they can never drift again
(D-4).

---

## 3. Decisions needing a human ruling

**D-1 — `.bat` disposition.** *Recommended:* stop writing it; keep the name in the
infra-skip list permanently; assert on the new name. *Alternative:* write both
names for one release as a deprecation window.

**D-2 — IF-001 is a ratified cross-project contract naming `RECONSTRUCT.bat`.**
Needs an amendment agreed with the HomeHub counterparty, not a unilateral edit.
**This can block the WP's release, not its implementation.**

**D-3 — does the picker belong in `Reconstruct.ps1`, or only in the launchers?**
*Recommended:* in the script — the script is what a human runs by hand.

**D-4 — where the kit revision constant lives.** *Recommended:* one
`$script:KitRevision` in `FileBackup.Common.psm1`, asserted equal to both markers.

**D-5 — F-2, the duplicate `SN-031`.** *Recommended:* renumber the self-healing
need to `SN-036` and add id-uniqueness checking to `trace.py`, as a **separate
commit before this WP**.

**D-6 — NEW (review T7): no console/desktop becomes a usage failure.** A restore
invoked with no `-TargetRoot` from a service, scheduled task, WinRM or SSH
session today blocks on `Read-Host` forever. *Recommended:* exit 2 with usage
instead. This **changes the behaviour of an existing path** — but toward
conformance with SR-016/SN-011, which the current behaviour violates. Flagged
prominently rather than slipped in.

**D-7 — NEW (review T3 / F-3): do the twins resolve symlinks the same way?**
Today bash resolves them (`realpath -m`) and PowerShell does not (`GetFullPath`),
so a junction into the backup is refused by one restorer and allowed by the
other. Pre-existing. *Recommended:* record the divergence as a live item and
rule on it separately; A3 as redesigned does not widen it. *Alternative:* make
`Test-PathIsInside` resolve reparse points in this WP.

---

## 4. Changes

### 4.1 Code

| File | Change |
|---|---|
| [bash/reconstruct.sh](../bash/reconstruct.sh) | A1–A8; `--pick-target` + `pick_target_dir()`; end-of-run hold; usage text; `chmod u+w` after write; KitRevision 10 |
| [bash/reconstruct.command](../bash/reconstruct.command) | **new** — §2.3 |
| [Reconstruct.ps1](../Reconstruct.ps1) | `Test-ShouldPromptGraphically`, `Select-FolderInteractively`, `-NoGui`, D-6 guard, end-of-run hold; usage text; clear read-only in `Restore-OneRow`; KitRevision 10 |
| [Modules/FileBackup.Common.psm1](../Modules/FileBackup.Common.psm1) | `ReconstructCmdName`, `ReconstructCommandName`, `ReconstructLegacyBatName`; `KitRevision` constant (D-4) |
| [Modules/FileBackup.Engine.psm1](../Modules/FileBackup.Engine.psm1) | `New-ReconstructScript` writes `.cmd`, copies `.command`; artifact lists [:1999](../Modules/FileBackup.Engine.psm1#L1999), [:3427](../Modules/FileBackup.Engine.psm1#L3427); infra-skip list keeps `.bat`, gains both new names |
| [tests/Unit/Coverage.Tests.ps1](../tests/Unit/Coverage.Tests.ps1) | artifact assertions [:392](../tests/Unit/Coverage.Tests.ps1#L392), [:1346](../tests/Unit/Coverage.Tests.ps1#L1346), [:3419](../tests/Unit/Coverage.Tests.ps1#L3419) *(added in rev 2 — review T8)* |
| [scripts/Invoke-Container.ps1](../scripts/Invoke-Container.ps1) | artifact assertions [:283](../scripts/Invoke-Container.ps1#L283), [:354](../scripts/Invoke-Container.ps1#L354) |
| [scripts/gen_bash_fixtures.ps1](../scripts/gen_bash_fixtures.ps1) | `$KitArtifacts` [:171](../scripts/gen_bash_fixtures.ps1#L171) |
| [.gitattributes](../.gitattributes) | `*.command text eol=lf` |

### 4.2 Tests

*Pester.* `Test-ShouldPromptGraphically` decision matrix incl. the D-6 branch;
`Select-FolderInteractively` with an injected picker (path / cancel / throw);
a read-only source restores writable; artifact list is the new seven; `.cmd`
content shape and exit-code passthrough; `RECONSTRUCT.bat` still treated as
infrastructure (no orphan WARN); kit revision marker equals the constant.

*bats.* A `stat`/`find`/`df`/`realpath`/`mktemp`/`touch`/`date` **BSD stub layer
on `PATH`** so the whole BSD branch runs from Linux CI. Then: witness
verification passes under BSD `stat`; the snapshot pool is complete under BSD
`find`; **`canon()` refuses `..` and refuses rather than degrades when it cannot
resolve — including the exact T2 case `/outside/link/../backup/victim` with
`link -> /backup`**; capacity precheck warns rather than silently skipping;
compressed rows extract with BSD-style `mktemp`; a failed `mktemp` never writes
to `/`; `touch -t` fallback preserves SR-066; `--pick-target` with a stub picker;
cancelled picker → usage + exit 2; **`exit_codes.bats:38` unchanged and green.**

*Container.* Artifact-list assertions gain `.cmd`/`.command`.

### 4.3 Docs

README (restore section, launchers, `chmod +x`, the macOS floor and its honest
limits), AGENTS.md §3 (artifact count 7, kit revision 10), docs/interfaces.md,
docs/homehub-integration.md, docs/architecture.md if the generated map moves.

---

## 5. Registry amendments

*(Expanded in revision 2 — review finding T8 showed revision 1 missed five active
rows that name `.bat`.)*

**New SN-035** — *"Start a restore without recalling a command, and restore on a
Mac."* Extends SN-022 (Linux) and SN-012 (discoverability).

**Amended, because they name `RECONSTRUCT.bat` today:**

| Row | Where | Change |
|---|---|---|
| SR-007 | system-requirements.csv | artifact list → seven; `.bat` recognised-legacy; kit revision 10 |
| SR-016 | system-requirements.csv | picker inside the never-block rule; D-6 guard |
| SR-040 | system-requirements.csv:40 | exit-code table names `.cmd` |
| LLR-007 | low-level-requirements.csv:8 | kit generator emits `.cmd` + `.command` |
| LLR-016 | low-level-requirements.csv:15 | non-interactive guard, D-6 branch |
| TC-032 | test-cases.csv:31 | entry-point name |
| TC-059 | test-cases.csv:58 | entry-point name |
| IF-001 | interfaces.csv | D-2, with the counterparty |

**New SR-071** — POSIX portability: no GNU-specific behaviour on any path a
restore takes; a BSD userland meeting the declared floor restores identically,
and any shortfall is a loud exit 2 with remediation, never a false 1, 3 or 4.
**New SR-072** — double-click launchers, no-argument-safe, exit code preserved;
acceptance names the volume classes where the executable bit survives (§2.3).
**New SR-073** — graphical target selection where a desktop is present; typed
prompt where a console is present; **usage failure where neither is** (D-6).

**New LLR-071…LLR-080**, **new TC-155…TC-178** (after LLR-070 / TC-154). Phase
tag **`portable-v1`**, added to the `check.ps1` ratchet
([scripts/check.ps1:122](../scripts/check.ps1#L122)) in the same commit that flips
these rows Verified — the discipline every prior phase followed.

---

## 6. Verification

1. `pwsh scripts/check.ps1 -Tier Full -Gate G3` — real output into status.md.
2. Ubuntu WSL: full bats suite incl. the BSD-stub layer + `shellcheck` clean on
   both shell files.
3. Container acceptance for the artifact list.
4. **macOS acceptance — requires the human's Mac; I cannot run it.** This is the
   only evidence for real BSD behaviour: the stubs test *our* branch selection,
   not Apple's `stat`/`mktemp`. It is also what settles the open BSD `mktemp`
   default-template question (A8 is the correct change either way).
5. Windows manual: double-click `RECONSTRUCT.cmd`, pick a folder, confirm the
   restore and the hold; confirm a scripted call with `-TargetRoot` neither holds
   nor pauses and returns the SR-040 code; confirm a `cmd /c` no-arg call from a
   console **returns instead of blocking** (review T6).

**No green is reported that was not run** (CLAUDE.md). Step 4 depends on a
machine I do not have.

---

## 7. Risks

- **R1 — the `.bat` rename reaches a counterparty.** D-2; `.bat` stays recognised
  infrastructure forever.
- **R2 — a GUI dialog hangs an unattended run.** Structurally mitigated: the
  picker is reachable only where a prompt is already reachable, and D-6 removes
  the pre-existing no-console hang underneath it. The pure decision core is
  exhaustively tested.
- **R3 — the BSD stubs do not match real BSD.** The honest residual; step 4 is the
  only real evidence. The `wc -c` floor in A1 is correct on any POSIX userland.
- **R4 — `canon()` and SR-009.** *Reduced in revision 2.* Revision 1's algorithm
  was unsafe (T2); the redesign refuses instead of guessing, so the failure mode
  is a loud exit 2 rather than a write into the backup. The T2 case is a required
  test.
- **R5 — scope.** Six parts, one kit revision. §2.5's sequencing is why Part E
  cannot wait.
- **R6 — D-6 changes an existing path's behaviour.** A scheduled job that today
  hangs will tomorrow exit 2. That is the point, but it is a behaviour change and
  is called out rather than buried.

---

## 8. Out of scope

- **8.1 — WP14: read-only stored objects (the write side).** Set the attribute
  after a stored object is written; a `-ReadOnlyStore` opt-in; deploy revision-10
  kits first. Read-only is friction against an accidental `del` — verified above
  that a non-`-Force` delete is blocked — not protection against ransomware or
  `-Recurse -Force`. Real protection is ACLs or filesystem snapshots.
- **8.2 — a non-gawk manifest parser.** `FPAT` is gawk-only.
- **8.3 — `bash-v2` / SR-033.** Unchanged, still phase-deferred.
- **8.4 — a snapshot chooser.** The picker selects the restore *target*.
- **8.5 — F-2's renumber (D-5)** and **F-3's twin divergence (D-7)**.

---

## 9. Independent review — OpenAI gpt-5.6-terra, medium effort, via `codex exec` — 2026-08-28

Human-directed, adversarial charter, read-only sandbox, run against revision 1 at
commit `680136b`. **9 findings: 2 P0, 6 P1, 1 P2.** Verdict as delivered:
**"not safe to implement as written."** That verdict was correct — T2 alone would
have shipped a hole in the SR-009 guard. Every finding was checked against the
code before disposition.

### T1 (P0 as filed) — "restore-critical GNU options remain" — **SPLIT: the `--` half DECLINED, the `touch -d` half ACCEPTED**

T1's central claim is that BSD rejects the `--` end-of-options delimiter on
`head`, `od`, `grep`, `df` and others, so an intact manifest could fail its header
check. **That is wrong.** `--` is POSIX Utility Syntax Guideline 10 and BSD
utilities honour it through `getopt(3)`. Acting on the recommendation would be
actively harmful: those guards are what stop a leading-dash or `@`-prefixed
filename being read as an option, and this repo's own status.md live-items list
records their **absence** on the PowerShell 7-Zip calls as an open gap "where the
bash twin guards every external call". Removing them would regress a deliberate
safety property to fix a problem that does not exist.

What T1 gets right is `touch -d` and, more importantly, the *method*: audit every
external invocation, not four. That audit was run independently by the driver and
found three defects — **P5 `mktemp`, P6 `touch`, P7 `date`** — of which T1 named
only `touch`. All three are now in §1.1 and A6–A8. Severity as filed (P0) applied
to the `--` claim and does not survive; the real content is P1.

### T2 (P0) — `canon()` walks a symlinked `..` into the backup — **VALID, ACCEPTED, DESIGN REPLACED**

The best finding of the review. Revision 1 reduced `..` lexically *before*
resolving symlinks, which is not path resolution; with `/outside/link -> /backup`,
`--target-root /outside/link/../backup/victim` resolves to `/backup/victim` by
kernel semantics but to `/outside/backup/victim` lexically, and `is_inside` would
have allowed a restore to write into the backup root. No reordering of the
revision-1 steps fixes it.

§2.1 A3 is rewritten: the fallback **refuses** a `..` component and refuses when
it cannot resolve, instead of guessing. The exact T2 path is a required bats case.

### T3 (P1) — the twins disagree about symlinks — **VALID AS AN OBSERVATION, SEVERITY REDUCED, NOT INTRODUCED HERE**

Correct that bash (`realpath -m`) resolves symlinks and PowerShell
(`GetFullPath`) does not. But this divergence **already exists in shipped code** —
it is not created by A3, which leaves the GNU path untouched. Recorded as F-3 and
ruled on by D-7 rather than absorbed silently into this WP.

### T4 (P1) — the `stat` probe can misidentify GNU — **VALID, ACCEPTED**

Precise and correct: `stat -f '%z' -- /` succeeds on GNU when a file named `%z`
exists in the working directory, because `-f` takes no argument and `%z` becomes
an operand. Revision 1's "unambiguous" claim was wrong. A1 now probes a known
regular file and requires **numeric** output, so the result cannot depend on cwd
contents.

### T5 (P1) — capacity fallback — **SPLIT: `--` half DECLINED, silent-skip and arithmetic halves ACCEPTED**

The `--` half fails with T1. The rest is right and is now in A4: the
multiplication moves into bash 64-bit integers rather than awk doubles, and a
`df` that yields no usable figure now **warns** instead of skipping the SR-040
capacity precheck in silence — a pre-existing weakness T5 spotted correctly.

### T6 (P1) — `.cmd` can block a no-arg console caller — **VALID, ACCEPTED, MECHANISM CHANGED**

I had verified only the redirected-stdin case, where `pause` returns immediately
and the exit code survives. T6 is right that a console-attached `cmd /c` caller
with no arguments blocks. Rather than a better batch heuristic, §2.2 removes the
pause from the shell entirely: the **restorer** holds at the end, only when it
obtained its target interactively. The failure mode is deleted rather than
narrowed, and the decision becomes Pester-testable.

### T7 (P1) — the headless-Windows claim — **RECOMMENDATION ACCEPTED, ATTRIBUTION CORRECTED**

Revision 1's claim ("cannot introduce a new blocking path") is literally true, and
T7 does not refute it. But T7 is right about something more useful: the path it
*doesn't* fix already hangs. A scheduled task with neither `-NonInteractive` nor
redirected stdin reaches `Read-Host` and waits forever, violating SR-016/SN-011
in shipped code. Since this WP rewrites that block, D-6 closes it: no console or
desktop → usage + exit 2. Recorded as a deliberate behaviour change (R6).

### T8 (P1) — rename scope incomplete — **VALID, ACCEPTED IN FULL**

Revision 1's §5 named SR-007, SR-016 and IF-001 and missed **LLR-007, LLR-016,
SR-040, TC-032 and TC-059**, all of which name `.bat`; §4.1 omitted
`Coverage.Tests.ps1` despite its three assertions. Both tables are corrected, and
§5 now classifies every reference as amended contract, updated test, or retained
history.

### T9 (P2) — the `.command` is not double-click-ready everywhere — **VALID, ACCEPTED, CLAIM NARROWED**

Fair. Windows cannot write a POSIX mode, so the executable bit exists only where
macOS synthesises it. §2.3 now names the volume classes in the acceptance
criterion, keeps `bash reconstruct.sh --pick-target` as the documented macOS path
that needs no bit at all, and documents the `chmod +x` remediation instead of
leaving it to be discovered mid-recovery.

### Found by the driver's own sweep, NOT reported by the review

- **P5 — `mktemp -d`** at [:184](../bash/reconstruct.sh#L184) and
  [:204](../bash/reconstruct.sh#L204). GNU defaults the template, BSD does not;
  and [:204](../bash/reconstruct.sh#L204) never checks the result, so a failed
  `mktemp` writes the 7-Zip self-test probe to the **filesystem root** and
  misreports 7-Zip as unusable. Latent on every platform.
- **P6 — `touch -d`** silently costing SR-066 on BSD.
- **P7 — `date --iso-8601=seconds`** changing the log timestamp format on BSD.

### Positively cleared by the review

P1–P4 confirmed real in current code. A2's `find | sed | grep | sort` preserves
snapshot ordering and leaves the unlistable-change-root branch intact. `wc -c` is
a valid size fallback for the regular files `stat_size` inspects. The PowerShell
prompt sits exactly where §2.4 says, after the existing guard. All 15 engine
`Remove-Item` sites pass `-Force`. F-1 is real, and advancing to revision 10 is
the right correction.

### Disposition summary

| Finding | Filed | Disposition |
|---|---|---|
| T1 | P0 | Split — `--` **declined** (premise wrong, recommendation harmful); `touch -d` accepted as P6 |
| T2 | P0 | **Accepted** — design replaced (A3) |
| T3 | P1 | Valid, **pre-existing** — recorded F-3, ruled by D-7 |
| T4 | P1 | **Accepted** — probe rewritten (A1) |
| T5 | P1 | Split — `--` declined; silent-skip + arithmetic **accepted** (A4) |
| T6 | P1 | **Accepted** — pause removed from the shell (§2.2) |
| T7 | P1 | Recommendation **accepted** as D-6; attribution corrected |
| T8 | P1 | **Accepted in full** (§4.1, §5) |
| T9 | P2 | **Accepted** — claim narrowed (§2.3) |
