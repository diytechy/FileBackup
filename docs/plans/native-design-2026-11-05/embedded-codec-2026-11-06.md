# Embedded 7z codec — 2026-11-06

Historical experiment: the owner subsequently selected a packaged official
7-Zip helper. The embedded codec and its worker were removed; current behavior
and evidence are in [the bundled helper record](bundled-sevenzip-2026-11-06.md).

The owner requested a native package that does not require an installed 7-Zip.
Native backup, deep verification and retention now use the embedded
`sevenz-rust2` 0.24.2 library. Only its `compress` feature is enabled; the locked
dependency additions are `lzma-rust2` 0.23.0 and `crc32fast` 1.5.4. The compiler
floor is Rust 1.93; local builds use 1.96. Package generation includes the new
components' license texts and inventory.

## Design and recovery compatibility

The existing bounded process runner starts the same executable with an internal
codec operation. This preserves a killable deadline and releases codec memory
after each operation without distributing another executable or DLL. Compression
encodes one file with LZMA2 level 5 and a 32 MiB default dictionary, rounded up
to a power of two between 4 KiB and 32 MiB for smaller inputs. Files over 128 MiB
use up to two encoder workers on independent 128 MiB chunks; smaller files stream
through one encoder. The writer flushes the finished archive to disk. Capture
still verifies its content before publishing the object. This owner-requested
baseline supersedes the initial fast preset measured below.

Verification hashes the decoded stream, bounded by the expected length plus one,
and checks the recorded content key. It never extracts archive-supplied paths.
The supported object is exactly one file; LZMA/LZMA2/COPY and the library's BCJ
filters cover the standard objects emitted by FileBackup. Unsupported methods or
password requirements report verification unavailability, not damaged content.
CRC or truncated-content failures are damage. No external fallback or automatic
download path was added.

`SevenZipPath` remains accepted and type-checked for configuration continuity but
is unused by native operations. Optional media measurement still uses `ffprobe`;
it is not required for backup. OS facilities used for optional notifications are
unchanged. PowerShell and Bash recovery still use their own documented tools,
including external 7-Zip for compressed content, without needing FileBackup.
The container's recovery tools therefore remain appropriate image dependencies.

## Initial codec-only measurement (superseded settings)

Private fixture: the existing 1 GiB compressible input at
`D:/FileBackupBuild/tmp/performance-compressed-gib-02/source/large-00000.bin`.
Outputs and sampler records are under
`D:/FileBackupBuild/tmp/embedded-codec-20261106`.
`scripts/measure_native.py` sampled process RSS at nominal 50 ms intervals with
affinity to logical CPUs 0–3. Source and output are on D: rotational storage;
cache state is uncontrolled. The embedded worker was invoked directly here, so
these numbers exclude the main engine's manifest and object indexes.

| Operation | Seconds | Peak RSS bytes | Archive bytes |
|---|---:|---:|---:|
| External 7-Zip, `-mx=5 -mmt=2` | 4.718 | 401,653,760 | 156,573 |
| Embedded initial preset 5, rejected for speed | 29.125 | 86,065,152 | 156,429 |
| Embedded initial selection, fast preset 1 | 7.438 | 52,305,920 | 161,141 |
| Embedded verification of initial embedded archive | 0.313 | 14,929,920 | — |
| Embedded verification of external archive | 0.344 | 40,083,456 | — |

Both verification results produced the same recorded length and XXH3-128 digest.
The selected encoder was slower than external 7-Zip on this input but still
processed about 138 MiB/s, with about 87% lower sampled codec RSS. Its archive
was about 3% larger on this highly compressible fixture. These are individual
observations, not general compression-ratio, throughput, million-file memory or
2 GB host claims. Prior full-workload measurements used external 7-Zip and remain
identified as such in the [support record](../../native-support.md).

The initial Windows release also completed an end-to-end backup of that one-file
1 GiB input to a new private store: 21.609 seconds, 61,165,568 bytes simultaneous
parent/worker RSS, exit 0. Deep verification completed in 0.359 seconds at
21,766,144 bytes, exit 0. These include staging, hashing, probe, compression,
archive verification and publication as applicable. They confirm the integrated
worker path; they do not substitute for a million-row measurement. Sampler
records are `full-backup.json` and `full-verify.json` in the same fixture folder.

## Owner-requested level-5 comparison baseline

After the initial integration, the owner requested matching `-mx=5`, up to two
threads and the executable's default dictionary before further tuning. The
installed Windows executable is **7-Zip 24.09**. Its 1 GiB archive reports
`LZMA2:25`, a 32 MiB dictionary. The Rust library's preset 5 instead defaults to
8 MiB, so the writer explicitly selects 32 MiB (reduced for small inputs).
Both use normal mode, BT4, a nice length of 32, and lc/lp/pb of 3/0/2.
The version-pinned [7-Zip LZMA settings](https://github.com/ip7z/7zip/blob/24.09/C/LzmaEnc.c)
and the locally locked Rust encoder source were checked for this mapping.

Threading cannot be matched exactly through this library's API. The executable
uses two cooperating threads within one LZMA encoder. The Rust library uses
separate encoder workers and buffers independent chunks. The selected 128 MiB
chunk size is four times the default dictionary, following 7-Zip's automatic
block-size rule when block parallelism is used; the actual `-mmt=2` executable
route uses a single solid block. See the version-pinned
[7-Zip block/thread normalization](https://github.com/ip7z/7zip/blob/24.09/C/Lzma2Enc.c).
Files of at most one chunk use a single streaming encoder. This is the closest
exposed level/dictionary/worker-limit baseline, not identical execution or an
isolated test of threading alone. No further speed/memory tuning was applied.

Private records: `D:/FileBackupBuild/tmp/embedded-codec-mx5-20261106/results.json`
and its per-run JSON/stdout/stderr files. Same 1 GiB input, D: drive, four-logical-CPU
affinity and 50 ms sampler as above. Three runs alternated ordering:
external/embedded, embedded/external, external/embedded. Cache state and host
activity were uncontrolled; the first pair overlapped the tail of Linux build
validation. All runs exited 0 with no sampler errors or resource-limit stops.

| Encoder | Times (s) | Median (s) | Maximum codec RSS (bytes) | Archive bytes |
|---|---|---:|---:|---:|
| 7-Zip 24.09 `-mx=5 -mmt=2` | 5.125, 5.079, 5.047 | 5.079 | 401,670,144 | 156,573 |
| Embedded level 5 / 32 MiB / two workers | 24.563, 19.735, 20.328 | 20.328 | 1,182,126,080 | 157,261 |

Every archive reported the 32 MiB dictionary, extracted through external 7-Zip
to the source SHA-256 digest, and passed native length/XXH3-128 verification.
The embedded archive is about 0.44% larger on this highly compressible input.
The 128 MiB-plus-one-byte boundary also passed native verification and independent
extraction on both Windows and Linux release builds, exercising a second chunk
containing only one byte.

These measurements expose a materially larger codec working set and slower
compression at the requested baseline. The library holds multiple chunk buffers
and separate encoder states. The measured 1.18 GB is codec-only: it excludes the
parent's manifest/object indexes and does not establish the 2 GB full-workload
limit. Existing million-file memory results must not be attributed to this
configuration. Future tuning or codec selection should start from this recorded
baseline, rather than silently comparing it with the initial fast preset.

Opus 5.5 low session `a7d12201-7d5d-445e-8aaf-0dff6df62352` reviewed the updated
`tools.rs` and found no concrete high/medium issue. Its resource and chunk-boundary
coverage suggestions were checked with the measurements above. Windows and Linux
full suites passed 48 and 51 tests, respectively; strict Clippy and release builds
also passed. macOS remains deferred.

The matching private packages are
`D:/FileBackupBuild/packages/filebackup-native-windows-x64-embedded-7z-mx5-20261106.zip`
and `D:/FileBackupBuild/packages/filebackup-native-linux-x64-embedded-7z-mx5-20261106.zip`.
All 208 Windows and 340 Linux checksum entries and ZIP contents were verified.
The packaged Linux executable also passed compressed backup/deep verification
with an empty PATH. The earlier packages below retain the initial fast preset.

## Initial integration review and validation

Opus 5.5 low review `8a94c829-07f0-49a1-ae3e-d3095e3041f8` inspected
the supplied tools, engine and maintenance source. Its dictionary representability
and wrapped-CRC-error findings were confirmed in the pinned library source and
fixed. Its unsupported-method concern was handled by preserving an unavailable
verdict; extra decoders and fallback processes were unnecessary. Tests exercise
external default executable archives as well as explicit LZMA, LZMA2 and COPY.
The first review attempt returned unexecuted tool-call text and is not counted
as a completed review.

Validation covers native backup/deep verification with an empty PATH and an
invalid legacy `SevenZipPath`, extraction of native archives by external 7-Zip,
independent PowerShell/Bash recovery, empty content, long-distance repetitions
at a noncanonical dictionary size, wrong recorded lengths, truncated archives,
CRC payload damage, multiple-member rejection and unsupported-method handling.
Follow-up `a3416af8-ae15-4520-b4ce-6c9c8ca14e90` found no high issue and two
medium classification concerns. The LZMA2 `InvalidInput` case was confirmed in
the decoder source, classified as damage and covered by an invalid-control-byte
fixture. Its proposal to infer damage from equal physical/recorded lengths when
a raw encrypted archive cannot be decoded was rejected: stored form is advisory,
and a real archive can have that same length. An unavailable verdict preserves
uncertain bytes and avoids adding a conflicting form-selection path for this
ambiguous case. These were static reviews, not executed tests.

macOS validation remains deferred by the owner.

The full native suites passed 48 Windows and 51 Linux tests, including independent
script restoration and interruption recovery. After the final LZMA2 classification
adjustment, all seven focused codec tests and strict Clippy passed on both
platforms. Release packages omit `test-hooks`. Documentation validation reports
zero broken links; the interface trace map is current. Strict trace retains the
18 existing approved-SR wording findings, with no orphan, integrity or interface
error; this change does not rewrite those approved statements.

Private release artifacts are
`D:/FileBackupBuild/packages/filebackup-native-windows-x64-embedded-7z-20261106.zip`
and `D:/FileBackupBuild/packages/filebackup-native-linux-x64-embedded-7z-20261106.zip`.
All 208 Windows and 340 Linux checksum entries and ZIP contents were checked.
The packaged Linux executable completed compressed backup/deep verification with
an empty PATH; the packaged Windows executable likewise deep-verified the private
1 GiB store with an empty PATH. No artifacts were published.
