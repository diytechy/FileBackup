# Packaged official 7-Zip — 2026-11-06

The owner selected shipping the official console executable after the
[embedded-codec comparison](embedded-codec-2026-11-06.md) showed substantially
higher memory and slower compression at similar settings. Native operations now
invoke a pinned helper shipped with FileBackup. The Rust codec dependency, its
transitive codec dependencies and the internal `__codec_worker` entry point were
removed. PowerShell/Bash recovery remains independent.

## Deployment and dependency identity

Extract the entire deployment ZIP. FileBackup resolves `tools/7zip/7za.exe` on
Windows or `tools/7zip/7zz` on Linux/macOS relative to its executable. There is
one compression implementation, with no system/PATH fallback, runtime unpacking,
runtime download or codec-selection setting. The legacy `SevenZipPath` key is
still type-checked but unused. Optional configured `ffprobe` is unchanged.

`scripts/prepare_native_sevenzip.py` pins **7-Zip 26.05** and the SHA-256 digests
published in the [official release metadata](https://github.com/ip7z/7zip/releases/tag/26.05).
Windows uses the standalone `7za.exe` member of the official Extra archive;
Linux uses static `7zzs`, deployed as `7zz`; macOS provisioning uses the official
universal `7zz`, with runtime validation still deferred. Platform provisioning
does not designate untested ARM/macOS hosts as supported.

Only the selected binary member is read from a verified archive. The build script
also supplies the binary's `License.txt`, `Source-License.txt`, the full LGPL text, the additional unRAR terms,
attribution and the exact corresponding source archive alongside the helper.
These follow the project's [redistribution guidance](https://www.7-zip.org/faq.html)
and the licenses in the pinned source. Windows provisioning needs a build-time
extractor for the Extra archive; deployment does not. Cache integrity and offline
missing-dependency refusal are unit-tested. `--offline` packaging uses cached
Cargo metadata/dependencies and cached pinned helper/source archives.

The PowerShell build helper, CI workflow and native container packaging provision
the same helper. `package_native.py` records its source, target and binary/archive
digests in `components.json`; helper, licenses and source are covered by package
checksums. The container retains separate recovery tools for standalone Bash use.

## Runtime behavior

Compression retains `-t7z -mx=5 -mmt=2`, the official default dictionary and
literal input names. `-sae` fixes the exact output path; inputs are already closed
staging copies. Compression outputs live in disposable staging directories;
probe outputs are explicitly removed. No additional staging layer was added.
The completed archive is flushed and content-verified before publication.

One process runner owns deadlines, process groups/Windows jobs and output pipes
for optional media queries and 7-Zip operations. Standard output is bounded text
or a streaming hash, depending on the operation. Diagnostics retain at most
8 KiB while draining excess output, so a noisy tool cannot block or grow memory
without limit. A standard-output limit violation kills the process promptly.

Verification first accepts matching raw bytes. Archive candidates must describe
one expected-size file, then their decoded stream must match the recorded length
and XXH3-128. No archive-supplied path is extracted to disk. Oversized/multi-file
listings and oversized decoded content are content mismatches. Unknown failures,
password requirements and unsupported methods remain unavailable verdicts;
recognized corruption diagnostics establish damage. Compression-enabled backup
preflights the helper before creating/mutating the store.

## Exact-helper measurement

Private fixture and sampler records:
`D:/FileBackupBuild/tmp/bundled-sevenzip-20261106`. This reuses the earlier
1 GiB compressible input on D:, with affinity to logical CPUs 0–3 and nominal
50 ms process-tree RSS sampling. Cache state is uncontrolled; the input was read
for SHA-256 before the compression series. Measurements characterize this input
and host, not the complete HDD/2 TiB/million-file envelope.

| Operation | Seconds | Peak RSS bytes |
|---|---:|---:|
| Official 26.05 helper, run 1 | 5.047 | 401,465,344 |
| Official 26.05 helper, run 2 | 4.891 | 401,440,768 |
| Official 26.05 helper, run 3 | 4.891 | 401,436,672 |
| Full native backup, parent plus helper | 19.469 | 408,784,896 |
| Full native deep verification, parent plus helper | 0.875 | 47,849,472 |

All runs exited 0 without sampler errors or resource stops. The three archives
were 156,573 bytes each and extracted through the independently installed
7-Zip 24.09 to the source SHA-256 digest. Median helper compression time was
4.891 seconds. The prior Rust level-5/two-worker baseline measured 20.328 seconds
median and 1,182,126,080 bytes peak codec RSS on the same input; these are separate
series, not simultaneous controlled host trials. No new million-file memory or
2 GB host qualification is claimed.

## Review and validation

Opus 5.5 low sessions `ef33d0f8-c88f-45a2-815d-112dc197db67` and
`30b399f0-b378-4b23-92c7-c33714e9db7b` reviewed `tools.rs`. Adopted corrections cover literal paths,
removal of an unnecessary locale override, bounded diagnostic draining,
recognized corruption forms and large-listing content verdicts. The proposed
extra output staging layer was declined because the engine already owns unique
disposable staging directories and passes closed files. Packaging scripts and
integration wiring were inspected and exercised locally, outside the supplied
review source scope.

The output-limit regression also exposed an existing limitation in host-error
classification: typed `anyhow` context is not necessarily a separate standard
error source. `is_host_stop` now checks that typed context as well as the source
chain, preserving host-stop classification while the archive verifier can still
recognize and handle its specific output-limit marker as a content mismatch.

Regression coverage includes empty-PATH compressed backup/deep verification,
missing-helper refusal before store creation, independent PowerShell/Bash
recovery, older external archives, empty and Unicode files, literal Unix wildcard
paths, CRC/truncation/large-listing damage, multi-member rejection, encrypted
archive unavailability, valid raw encrypted archives, inherited-pipe deadlines
and verbose diagnostic draining.

Final native suites passed **55 tests on Windows and 59 on Ubuntu WSL**;
Clippy with warnings denied, Rust formatting, release builds and four Python
packaging/sampler tests passed. The interface map is current and documentation
checks found no broken links (29 existing orphan warnings). Strict trace checking
found no orphan, integrity or interface errors; its 18 requirement-form findings
and 43 optional strict-schema findings remain in unchanged requirement/test
registries. This implementation change does not close those baseline findings.

Both release packages completed compressed backup and deep verification with an
empty PATH. Every packaged file checksum and every ZIP member was checked against
the assembled directory: 211 checksummed files in the Windows package and 343 in
Linux, with the helper, binary/source license texts and source archive included.
The removed Rust codec crates are absent from both component inventories.

Private artifacts (not published):

- `D:/FileBackupBuild/packages/filebackup-native-windows-x64-bundled-7z-2605-20261106.zip`
  — 4,671,397 bytes.
- `D:/FileBackupBuild/packages/filebackup-native-linux-x64-bundled-7z-2605-20261106.zip`
  — 7,120,085 bytes.

The final image `filebackup-native:bundled-7z-20261106` passed compressed backup
and byte-exact independent Bash restoration as UID 65532, without network access,
with a read-only image/source and all capabilities dropped. The fixture on WSL's
Windows-mounted D: scratch returned a host permission error; repeating on Linux
`/tmp` passed. This does not qualify Windows-mounted container store permissions.
macOS remains deferred by the owner.
