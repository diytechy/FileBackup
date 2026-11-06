# Embedded 7z codec — 2026-11-06

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
streams one file with LZMA2 fast preset 1, one thread, and a dictionary rounded up
to a power of two between 4 KiB and 8 MiB. The writer flushes the finished archive
to disk. Capture still verifies its content before publishing the object.

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

## Codec-only measurement

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
| Embedded selected fast preset 1 | 7.438 | 52,305,920 | 161,141 |
| Embedded verification of initial embedded archive | 0.313 | 14,929,920 | — |
| Embedded verification of external archive | 0.344 | 40,083,456 | — |

Both verification results produced the same recorded length and XXH3-128 digest.
The selected encoder was slower than external 7-Zip on this input but still
processed about 138 MiB/s, with about 87% lower sampled codec RSS. Its archive
was about 3% larger on this highly compressible fixture. These are individual
observations, not general compression-ratio, throughput, million-file memory or
2 GB host claims. Prior full-workload measurements used external 7-Zip and remain
identified as such in the [support record](../../native-support.md).

The final Windows release also completed an end-to-end backup of that one-file
1 GiB input to a new private store: 21.609 seconds, 61,165,568 bytes simultaneous
parent/worker RSS, exit 0. Deep verification completed in 0.359 seconds at
21,766,144 bytes, exit 0. These include staging, hashing, probe, compression,
archive verification and publication as applicable. They confirm the integrated
worker path; they do not substitute for a million-row measurement. Sampler
records are `full-backup.json` and `full-verify.json` in the same fixture folder.

## Review and validation

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
