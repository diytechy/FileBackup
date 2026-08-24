# WP2 — Config contract: work order (G1→G2 package)

Drafted 2026-08-22 by an independent Opus planning agent (read-only pass at
`4c71451`), adopted by the driver under the human's 2026-08-22 grind
authorization (batch ratification — see status.md audit log). Covers
Open-items rows **"config contract"** and **"multi-set mounts"**. Registry ids
allocated: **SN-027, SR-042..043, LLR-042..043, TC-074..078** (WP1 holds
SN-025..026, SR-038..041, LLR-038..041, TC-066..073).
**Sequenced after WP1's code lands** — SR-043 reuses WP1's
"2 = usage/precondition" exit-code meaning.

## 0. Grounding — what the config path actually is today

| Fact | Where |
|---|---|
| Format chosen by extension; `.json` → bare `ConvertFrom-Json`, `.xml` → `Import-Clixml`, anything else throws | `FileBackup.ps1:100-105` |
| All validation that exists: ≥1 `BackupSets`; per set, 5 non-empty strings (`Name`,`SourcePath`,`BackupPath`,`ChangePath`,`HashRecalcFreq`); presence (not type) of `CompressEnabled`/`PreserveFolderTree`; `HashRecalcFreq` in the 7-code set (case-insensitive) | `FileBackup.ps1:106-125` |
| `Tools.SevenZipPath` / `Tools.FfprobePath` read only if non-null, cast `[string]` | `FileBackup.ps1:153-158` |
| `Secrets.{SmtpServer,ToEmail,FromEmail,SmtpPort,Credential}` read at the mail step | `FileBackup.ps1:179-195` |
| `SourceStatePath` optional; defaults to `SourcePath`; refused if inside source/backup/change | `Modules\FileBackup.Engine.psm1:822-851` |
| `AllowEmptySource` read as `[bool]$Set.AllowEmptySource` — **absent ⇒ `$false`**, never validated | `Engine.psm1:1258` |
| `PreserveFolderTree` / `CompressEnabled` cast `[bool]` at use | `Engine.psm1:1266, 1297` |
| `HashRecalcFreq` normalized `ToUpperInvariant()` at use | `Engine.psm1:309` |
| Example file is a 7-key single set + `Tools.SevenZipPath`; **no test ever executes it** | `container\FileBackup.example.json` |
| TC-060 builds its own config in code instead (adds `AllowEmptySource`) | `scripts\Invoke-Container.ps1:73-91` |
| The only JSON that any test executes is generated inline in Pester | `tests\Unit\Engine.Tests.ps1:152-181` |
| Every other test config is CLIXML | `tests\Common\Harness.ps1:135-158`, `Coverage.Tests.ps1:19,78`, `Safety.Tests.ps1:23` |
| Image copies `FileBackup.ps1`, `Modules/`, `bash/`, `container/entrypoint.sh` only — **no schema file is in the image** | `Dockerfile:13-19` |
| IF-001 already carries the one-set ruling text; it does **not** name a config schema version | `docs\requirements\interfaces.csv:2` |

### Key-by-key reconciliation (code ↔ example)

| Key | Read by code | In example | Verdict |
|---|---|---|---|
| `ConfigVersion` | — | — | **Does not exist. WP2 introduces it.** |
| `Tools.SevenZipPath` | yes | yes | ok |
| `Tools.FfprobePath` | yes | **no** | code key the example lacks (optional) |
| `Secrets.*` | yes | **no** | deliberate — container runs `-NoMail`; JSON cannot carry a `PSCredential` at all |
| `BackupSets[].Name/SourcePath/BackupPath/ChangePath/HashRecalcFreq` | yes | yes | ok |
| `BackupSets[].SourceStatePath` | yes | yes | ok |
| `BackupSets[].CompressEnabled/PreserveFolderTree` | yes | yes | ok |
| `BackupSets[].AllowEmptySource` | yes (`[bool]`, silent default `$false`) | **no** | the one genuinely dangerous silent default |
| any other key | ignored silently | — | **the typo hole** |

Two live traps the loader must close:

1. **`[bool]'false'` is `$true` in PowerShell.** `"CompressEnabled": "false"`
   (a string, not a JSON boolean) today passes the presence check and silently
   *enables* compression at `Engine.psm1:1266`. A type check is not cosmetic.
2. **Unknown keys are swallowed.** `"AllowEmptySources"` (plural typo)
   validates fine and leaves the delete-all refusal armed by accident, not by
   intent.

## 1. The schema — FileBackup JSON config, `ConfigVersion: 1`

Canonical, documented contract. Types below are **JSON types**; a value of the
wrong JSON type is a hard error, never a coercion.

### Top level

| Key | Type | Req | Default | Notes |
|---|---|:--:|---|---|
| `ConfigVersion` | integer | **yes** | — | Currently `1`. Must be a JSON number with no fractional part. |
| `BackupSets` | array of objects | **yes** | — | ≥1 entry. A single bare object is accepted and wrapped (matches today's `@(...)` behavior). |
| `Tools` | object | no | `{}` | |
| `Secrets` | object | no | absent ⇒ no mail | |

### `BackupSets[]`

| Key | Type | Req | Default | Constraint |
|---|---|:--:|---|---|
| `Name` | string | **yes** | — | non-empty, non-whitespace; unique across sets |
| `SourcePath` | string | **yes** | — | non-empty (existence is checked later by `Resolve-BackupSetPaths`, SR-014 — not by the loader) |
| `BackupPath` | string | **yes** | — | non-empty |
| `ChangePath` | string | **yes** | — | non-empty |
| `HashRecalcFreq` | string | **yes** | — | one of `A E D W M Y N`, case-insensitive, normalized to upper |
| `CompressEnabled` | boolean | **yes** | — | true JSON boolean only |
| `PreserveFolderTree` | boolean | **yes** | — | true JSON boolean only |
| `SourceStatePath` | string | no | `SourcePath` | required in practice for a read-only container source; the loader cannot detect that, so it stays optional and documented |
| `AllowEmptySource` | boolean | no | `false` | promoted from "silently absent" to "explicitly optional with a documented default" |

### `Tools`

| Key | Type | Req | Default |
|---|---|:--:|---|
| `SevenZipPath` | string | no | `FILEBACKUP_7ZIP_PATH` → platform discovery |
| `FfprobePath` | string | no | `FILEBACKUP_FFPROBE_PATH` → platform discovery |

### `Secrets`

| Key | Type | Req | Notes |
|---|---|:--:|---|
| `ToEmail`,`FromEmail`,`SmtpServer` | string | no | mail is sent only when all three are present |
| `SmtpPort` | integer | no | |
| `Credential` | — | **forbidden in JSON** | named error: JSON cannot carry a `PSCredential`; CLIXML/DPAPI only, and the container path is `-NoMail` by design (homehub-integration §4.2) |

### Version and unknown-field policy (normative)

- **Unknown fields are rejected**, at every level, naming the offending key
  and its JSON path (`BackupSets[0].AllowEmptySources`). This is a data-safety
  product; a typo that silently disarms `AllowEmptySource` or
  `CompressEnabled` is exactly the class of failure the gate exists to
  prevent. Additive-and-ignore is the wrong default here.
- **`ConfigVersion` missing ⇒ hard error**, not an assumed `1`.
- **`ConfigVersion` > highest supported ⇒ hard error** naming both numbers
  ("config declares version 2; this build supports up to 1 — upgrade
  FileBackup").
- **`ConfigVersion` < 1, non-integer, or unparseable ⇒ hard error.**
- Compatibility rule: **a new optional key with a safe default is a minor
  addition keeping the same `ConfigVersion`; a new required key, a removed
  key, or a changed default bumps `ConfigVersion`.** With unknown-key
  rejection, an old build reading a newer minor config still fails loudly.
- **CLIXML is legacy and unversioned.** Keeps exactly today's checks (shared
  shape validation); exempt from `ConfigVersion`, unknown-key rejection, and
  the `Credential` ban. Documented as "native-Windows legacy; JSON is the
  contract."

### The schema artifact

Ship `container/FileBackup.schema.json` (JSON Schema draft-07: `required`,
`additionalProperties: false`, `enum` for `HashRecalcFreq`, `const: 1` for
`ConfigVersion`) as **documentation and editor support**; keep the
**hand-rolled PowerShell validator as the runtime authority** (`Test-Json
-Schema` message text and NJsonSchema behavior vary across PS 7.x minors, and
a runtime dependency would force a Dockerfile COPY and a "schema missing from
image" failure mode). TC-077 pins the two against one fixture corpus so the
published schema cannot drift from the validator.

## 2. Loader design

**Home:** `Modules/FileBackup.Engine.psm1` — config loading is backup-only, so
it must not enter Common (AGENTS.md §3). No new module.

**Public surface (one exported function, comment-based help first, then the
`# Implements:` line):**

```
Import-BackupConfiguration -Path <string> [-Log <scriptblock>]
```

Returns a normalized `[pscustomobject]` with `ConfigVersion`, `Sets` (every
optional key materialized to its default, `HashRecalcFreq` upper-cased,
booleans real `[bool]`), `Tools`, `Secrets`. `FileBackup.ps1` then reads only
that object — lines 100-125 collapse to one call ("entry points orchestrate,
they don't compute").

**Internal helpers (not exported):** `Test-BackupConfigurationShape` (per-set
required keys/types/enum — runs for **both** branches, preserving today's
message wording verbatim so existing tests keep passing),
`Assert-NoUnknownConfigKey` (JSON only, recursive, path-naming),
`Resolve-BackupSetDefaults`.

**Fail-loudly behavior**

- Every rejection is a single terminating error, before any dependency init,
  any logger creation, and any filesystem mutation. Message shape:
  `Config '<path>' is invalid: <JSON path> — <what was wrong> (expected
  <what>).` Report the **first** failure in document order (deterministic,
  testable), with the total count appended when >1.
- Interactive/in-process invocation keeps **throwing** — this is what
  `tests/Unit/Engine.Tests.ps1:146-181` and the harness rely on.
- At the process boundary, mirroring WP1's `Exit-Reconstruct` pattern: new
  `[switch]$ExitCode` on `FileBackup.ps1`. With it set, a config-contract
  failure writes the message to stderr and the global log and **exits 2**
  (WP1's usage/precondition class); a set failure still exits 1; clean run
  exits 0. `container/entrypoint.sh` passes `-ExitCode`. Without the switch
  nothing changes, so `Coverage.Tests.ps1:89`'s `$code | Should -Be 1` and
  every other current expectation hold.
- **No prompting anywhere** — the loader has no interactive path at all.

**One-set-per-invocation:** the engine keeps its N-set capability (SN-009,
TC-034). A **JSON** config declaring more than one `BackupSets` entry logs a
`WARN` naming the count and pointing at IF-001; it is not an error — a
native-Windows user may legitimately hand-write a multi-set JSON. The ruling
is enforced by contract text and HomeHub's one-service-per-directory
deployment, not by a refusal that would strand a valid local use.

**CLIXML branch:** untouched apart from routing through the shared shape
check. Marked legacy in `FileBackup.ps1`'s help, README, and IF-001.

## 3. Registry rows (CSV-ready, real headers)

### 3.1 `docs/requirements/stakeholder-needs.md` — append to **Edge-case expectations**

```
| SN-027 | The configuration file is wrong — a mistyped key, a quoted `"false"` where a boolean belongs, a missing required field, or a file written for a different version of FileBackup | The run refuses to start and says exactly which key is wrong and what was expected, before touching any backup data; it never guesses a default for a key it does not recognize, and a config written for a newer FileBackup is refused by name rather than half-understood. The JSON form is the documented, versioned contract and the shipped example is the same file the tests execute; the older CLIXML form keeps working as a native-Windows convenience. |
```

### 3.2 `docs/requirements/system-requirements.csv`

Header: `SR-ID,Title,SN-Refs,Requirement,Rationale,AcceptanceCriteria,Permutations,Priority,Verification,Status,Phase`

```
SR-042,Versioned JSON configuration contract,SN-027;SN-014;SN-024;SN-012,"The JSON configuration shall be a versioned, closed schema validated before any dependency initialization or backup mutation: a required integer ConfigVersion (currently 1); a BackupSets array of at least one object each requiring non-empty Name, SourcePath, BackupPath, ChangePath, a HashRecalcFreq in {A,E,D,W,M,Y,N} (case-insensitive), and JSON-boolean CompressEnabled and PreserveFolderTree, with optional SourceStatePath (default SourcePath) and AllowEmptySource (default false); optional Tools.SevenZipPath / Tools.FfprobePath and optional Secrets.{ToEmail,FromEmail,SmtpServer,SmtpPort}. Any key not in the schema, any value of the wrong JSON type, a missing or unparseable ConfigVersion, a ConfigVersion above the highest supported, or a Secrets.Credential key shall abort the run with a terminating error naming the offending key by its JSON path and the expected type or value set. A JSON config declaring more than one BackupSets entry shall log a warning naming the count and referencing IF-001's one-set-per-invocation ruling. The CLIXML configuration shall remain supported as the unversioned legacy native-Windows form, subject to the same per-set shape checks but exempt from the version, closed-schema, and credential rules.","IF-001's import half was under-specified: the JSON branch was a bare ConvertFrom-Json with no schema, no version field and no test, so a mistyped key was silently ignored (AllowEmptySource defaults to false when absent, disarming the delete-all refusal by accident) and a quoted \"false\" was coerced true by [bool], enabling compression against the operator's intent. This is the remaining blocker to IF-001 leaving Experimental.","container/FileBackup.example.json validates unmodified and, with only its five path fields and Tools.SevenZipPath retargeted, drives a real backup that restores byte-exact; each of missing ConfigVersion, ConfigVersion=2, unknown top-level key, unknown per-set key, string \"false\" for CompressEnabled, HashRecalcFreq='Q', empty BackupSets, non-integer SmtpPort, and Secrets.Credential is refused before any file is created, with the offending key named in the message; an omitted AllowEmptySource yields false and an omitted SourceStatePath yields SourcePath; the same CLIXML configs used by the existing suites still load unchanged.","format=set{json,clixml}; defect=set{missing-version,future-version,unknown-key-top,unknown-key-set,wrong-type,bad-enum,empty-sets,json-credential}; sets=set{1,2}",M,Test,Draft,
SR-043,Configuration failure is distinguishable at the process boundary,SN-027;SN-011;SN-026,"FileBackup.ps1 shall accept an -ExitCode switch that makes it report through the documented status table when run as a process entry point: 0 for a complete run, 1 when one or more backup sets failed, and 2 when the configuration could not be loaded or violates SR-042 — the same usage/precondition class the restorers use. Without the switch the entry point shall keep its current behavior (terminating error for configuration problems, exit 1 for a failed set) so in-process callers and the existing suites are unaffected. container/entrypoint.sh shall pass -ExitCode so a containerized run's exit status distinguishes a bad configuration from a failed backup.","IF-001 promises HomeHub a translatable exit status, and NagLight must distinguish 'your config is wrong, retrying will not help' from 'the backup failed'; today both surface as exit 1. Complements WP1's restore exit-code table with the same 2 = usage/precondition meaning.","Run as a child process with -ExitCode: a schema-violating config returns 2 having created no backup artifacts; a config whose one set fails returns 1; a clean run returns 0; the same invocations without -ExitCode return the pre-change codes and the in-process invocation still throws.","invocation=set{in-process,child-process}; switch=set{present,absent}; outcome=set{clean,set-failure,config-failure}",S,Test,Draft,
```

### 3.3 `docs/requirements/low-level-requirements.csv`

Header: `LLR-ID,SR-Refs,Title,Module,CodeSymbol,Detail,TestRefs,Status`

```
LLR-042,SR-042,Validating configuration loader,FileBackup.Engine;FileBackup.ps1;container/FileBackup.schema.json,Import-BackupConfiguration;Test-BackupConfigurationShape;Assert-NoUnknownConfigKey;Resolve-BackupSetDefaults,"Import-BackupConfiguration (exported from Engine, not Common — config loading is backup-only and Common must stay restore-safe) dispatches on the file extension, replacing FileBackup.ps1:100-125. The JSON branch parses with ConvertFrom-Json, requires an integer ConfigVersion within [1,$script:ConfigSchemaVersion], runs Assert-NoUnknownConfigKey over the top level, Tools, Secrets and each set (rejecting Secrets.Credential explicitly), then Test-BackupConfigurationShape; the CLIXML branch runs Test-BackupConfigurationShape only, preserving today's message wording so existing expectations hold. Type checks read the parsed JSON node's actual type — a quoted \"false\" is rejected rather than passed to [bool], which would coerce it true. Resolve-BackupSetDefaults materializes SourceStatePath=SourcePath and AllowEmptySource=$false and upper-cases HashRecalcFreq, so the engine's [bool] and ToUpperInvariant casts become belt-and-braces. Errors are terminating, single, first-in-document-order, and name the JSON path. container/FileBackup.schema.json is the published draft-07 mirror (additionalProperties:false) used for documentation and TC-077, not at runtime — keeping it out of the image and off the Dockerfile COPY list (SR-042).",TC-074;TC-075;TC-076;TC-077,Draft
LLR-043,SR-043,Entry-point status codes,FileBackup.ps1;container/entrypoint.sh,FileBackup.ps1;entrypoint.sh,"FileBackup.ps1 gains [switch]$ExitCode and wraps the Import-BackupConfiguration call: on failure it writes the message to stderr and, when the switch is set, to the global log path before 'exit 2'; without the switch it rethrows so & $entry keeps throwing for tests/Unit/Engine.Tests.ps1 and the harness. The trailing 'if (-not $overallSuccess) { exit 1 }' is unchanged, so Coverage.Tests' exit-1 expectation (TC-034) holds in both modes. container/entrypoint.sh adds -ExitCode to the exec argument list ahead of \"$@\". The code meanings match WP1's restore table (0 complete / 1 incomplete / 2 usage-precondition) so one vocabulary covers both halves of IF-001 (SR-043).",TC-078,Draft
```

### 3.4 `docs/test/test-cases.csv`

Header: `TC-ID,Verifies,Level,Method,Tier,Parameters,Expected,Automated,Status`

```
TC-074,SR-042;LLR-042,Unit,Test,Smoke,"format=set{json,clixml}; optional=set{present,absent}","Import-BackupConfiguration accepts container/FileBackup.example.json verbatim (no path substitution, no filesystem access) returning ConfigVersion 1 and one set; a minimal JSON config omitting SourceStatePath and AllowEmptySource yields SourceStatePath equal to SourcePath and AllowEmptySource false; a lowercase HashRecalcFreq is normalized to upper; the CLIXML configs written by tests/Common/Harness.ps1 still load with identical field values (SR-042). Pester: Describe 'Configuration loader accepts the documented contract (SR-042)'.",Yes,Draft
TC-075,SR-042;LLR-042,Unit,Test,Smoke,"defect=set{missing-version,future-version,unknown-key-top,unknown-key-set,string-boolean,bad-enum,empty-sets,non-integer-port,json-credential,not-json}","Each defective JSON config is refused by a terminating error naming the offending key by its JSON path and the expected type or value set — in particular \"CompressEnabled\": \"false\" is rejected as a string rather than coerced true, and \"AllowEmptySources\" is rejected as an unknown key rather than silently ignored — while the existing wordings 'at least one BackupSets entry', 'must define a non-empty', and 'invalid HashRecalcFreq' are preserved; no backup, change, state or log artifact is created by any refused run (SR-042). Pester: Describe 'Configuration loader fails loudly and names the key (SR-042)'.",Yes,Draft
TC-076,SR-042;SR-034;LLR-042,Integration,Test,Smoke,"substitution=set{paths,seven-zip}; mode=set{Mirror,HashAddressed}","The shipped container/FileBackup.example.json is loaded, has ONLY its SourcePath/SourceStatePath/BackupPath/ChangePath and Tools.SevenZipPath retargeted to the test drive and host 7-Zip (every other key kept verbatim), and drives a real FileBackup.ps1 run that produces MANIFEST.csv plus the restore kit and restores byte-exact; a keys-only diff proves the executed document is key-identical to the checked-in example, so the example can no longer drift from the contract (SR-042/SR-034). Pester: Describe 'The shipped example config is executable (SR-042)'.",Yes,Draft
TC-077,SR-042;LLR-042,Unit,Test,Smoke,"artifact=set{schema,example,readme,smoke-config}","container/FileBackup.schema.json accepts (via Test-Json -Schema) every fixture TC-074 accepts and rejects every fixture TC-075 rejects, so the published schema and the runtime validator cannot drift; container/FileBackup.example.json, the README JSON block, and Invoke-Container.ps1's New-SmokeConfiguration all declare ConfigVersion equal to the loader's supported maximum (SR-042). Pester: Describe 'Published JSON schema matches the validator (SR-042)'.",Yes,Draft
TC-078,SR-043;LLR-043,Unit,Test,Smoke,"invocation=set{in-process,child-process}; switch=set{present,absent}; outcome=set{clean,set-failure,config-failure}","Run as a child process with -ExitCode, a schema-violating config returns 2 with no backup artifacts created, a config whose only set fails returns 1, and a clean single-set run returns 0; the same invocations without -ExitCode return the pre-change codes and the in-process '& $entry' call still throws for a bad config; a two-set JSON config logs the IF-001 one-set-per-invocation warning naming the count while still processing both sets (SR-043). Pester: Describe 'Entry-point status codes (SR-043)'.",Yes,Draft
```

**Post-WP1+WP2 trace expectation:** `SN=27 SR=43 LLR=42 TC=77`, 0 orphans,
phase-deferred unchanged (bash-v2, container-v1). Both SRs carry an empty
`Phase` (core), so the `--require-verified --phase core,bash-v1` ratchet will
demand them Verified — intended.

### 3.5 `docs/requirements/interfaces.csv` — IF-001 amendment

Append to the `Contract` cell:

> "The configuration contract is the versioned JSON document specified by
> SR-042 and published as `container/FileBackup.schema.json`: a required
> integer `ConfigVersion` (currently **1**), a closed schema (any unrecognized
> key aborts the run naming that key), JSON booleans for
> `CompressEnabled`/`PreserveFolderTree`, optional `SourceStatePath` (default
> `SourcePath`) and `AllowEmptySource` (default `false`), and no
> `Secrets.Credential` (JSON cannot carry a PSCredential — containerized runs
> are `-NoMail`). CLIXML remains the unversioned legacy native-Windows form.
> Reaffirming the 2026-08-21 ruling: **one BackupSet per container
> invocation** — HomeHub runs one service/invocation per directory; a JSON
> config with more than one set is accepted for native-Windows use but logs a
> warning and is outside this contract. With `-ExitCode` (set by
> `container/entrypoint.sh`) the run reports 0 complete / 1 a backup set
> failed / 2 configuration or usage error, the same usage-precondition class
> as the restore table (SR-042/SR-043)."

Add `SR-042;SR-043` to `SR-Refs`. Keep `Version=v1` — the interface has never
left `Experimental`, so requiring `ConfigVersion` breaks no released promise.
**Once WP1's and WP2's SRs are Verified, `Stability` moves `Experimental` →
`Stable`** — the joint exit condition the two work packages exist to satisfy.

## 4. Ordered implementation plan

- **Phase A — registries + docs (no code).** Append SN-027, SR-042/043,
  LLR-042/043, TC-074..078; amend IF-001. `python scripts/trace.py --strict`
  must show 0 orphans before any code. Commit.
- **Phase B — the loader.** Add `Import-BackupConfiguration` + the three
  private helpers to `Engine.psm1` (help block first, then `# Implements:
  SR-042, LLR-042`), export it, add `$script:ConfigSchemaVersion = 1`. Do
  **not** change `FileBackup.ps1` yet. Write TC-074/TC-075 against the
  function directly — they are pure and fast. Regenerate the arch map
  (`scripts/gen_arch_map.ps1`). Commit green.
- **Phase C — wire the entry point.** Replace `FileBackup.ps1:100-125` with
  the single call; keep the throw. Run the full unit suite plus one
  integration mode — this is the moment the existing CLIXML expectations
  either hold or don't. Commit green.
- **Phase D — versionize the artifacts.** Add `"ConfigVersion": 1` to
  `container/FileBackup.example.json`, the README JSON block,
  `Invoke-Container.ps1:75` `New-SmokeConfiguration`, and both JSON fixtures
  in `Engine.Tests.ps1`. Publish `container/FileBackup.schema.json`. Add
  TC-076 (executes the example) and TC-077 (schema/validator agreement).
  Commit green.
- **Phase E — exit codes.** Add `-ExitCode` to `FileBackup.ps1`, `-ExitCode`
  to `container/entrypoint.sh`, TC-078. Update `FileBackup.ps1`'s
  `.PARAMETER`/`.NOTES` help and README's config section (JSON =
  canonical/versioned, CLIXML = legacy, status codes, one-set ruling). Commit
  green.
- **Phase F — close.** `pwsh scripts/check.ps1 -Tier Full` (paste the real
  output), flip SR-042/043 → `Verified`, LLR/TC → `Implemented`/`Pass`,
  record the driver verdict in `docs/status.md`, move the "config contract"
  and "multi-set mounts" rows to resolved. IF-001 `Stability` flips only once
  WP1's SRs are also Verified.

## 5. Regression risks

| Risk | Where | Mitigation |
|---|---|---|
| Existing message wordings are asserted | `Engine.Tests.ps1:149` (`*not found*`), `:180` (`*at least one BackupSets entry*`), `Coverage.Tests.ps1` | Shared `Test-BackupConfigurationShape` must emit the **identical strings**; treat them as a pinned contract, not free text |
| In-process `& $entry` must keep throwing | `Engine.Tests.ps1:148,168,179`, `Safety.Tests.ps1:28`, `Harness.ps1:169` | `exit 2` only under `-ExitCode`; default path rethrows |
| Exit code 1 for a failed set is asserted | `Coverage.Tests.ps1:89` (TC-034) — a **CLIXML two-set** config, child process, no `-ExitCode` | Never change the trailing `exit 1`; the one-set warning is JSON-only, so this test also can't start emitting it |
| All 236 integration assertions load CLIXML | `Harness.ps1:135-158` → every `tests/Suites/G*.ps1` | CLIXML branch is version-exempt and unknown-key-tolerant; `Secrets.Credential = $null` must keep loading |
| The two inline JSON fixtures become invalid the moment `ConfigVersion` is required | `Engine.Tests.ps1:161-166` (valid case) and `:177` (`'{}'`, expects the empty-sets message) | Add `ConfigVersion` to the first; the `'{}'` case must fail on the *version* check first — either reorder so `BackupSets` is checked first, or update that expectation deliberately and record it |
| TC-060's generated smoke config would be rejected in the container | `Invoke-Container.ps1:75-91` | Phase D updates it in the same commit as the schema; the Docker CI job is the canary |
| WP3 (container release-verify) will re-read the example and the smoke config | Open-items rows "container release-verify"/"smoke depth" | TC-076/TC-077 give WP3 a pinned example to build on rather than a second hand-rolled config |
| Concurrent WP1 edits | `Modules/`, `tests/`, `bash/`, registry CSVs | Phase A appends only at the allocated ids; Phase B adds a new region at the end of `Engine.psm1`; `container/entrypoint.sh` (WP2) and `bash/reconstruct.sh` (WP1) are different files |
| Generated docs go stale | `AGENTS.md` module map, `docs/architecture.md` | Run `gen_arch_map.ps1` in Phase B; `check.ps1` fails otherwise |

## 6. Design decisions on the planner's open questions (driver, 2026-08-22 — flagged for batch ratification)

1. **Missing `ConfigVersion` is fatal** (not assumed `1`): IF-001 is
   Experimental, only three in-repo producers exist, and an assumed version
   makes the field decorative.
2. **Unknown keys are rejected**, not warn-and-ignore: the concrete harm is
   proven (`AllowEmptySources` silently disarms the delete-all refusal).
3. **Multi-set JSON warns**, does not fail: the ruling is about how HomeHub
   deploys; a refusal would break a legitimate native-Windows use (SN-009).
4. **IF-001 `Version` stays v1**: never left Experimental, no consumer
   promise broken; the config schema carries its own version.
5. **Runtime validation is hand-rolled; the published JSON Schema is
   documentation**, with TC-077 pinning their equivalence.
