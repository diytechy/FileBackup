# Native transition validation — 2026-11-06

The Rust engine and independent PowerShell/Bash recovery kits are executable
development previews. This record distinguishes observed results from the
remaining release qualification. Drafted LLRs, interfaces and test cases retain
their review statuses; implementation does not imply acceptance or verification
of every obligation. See the [bindings](implementation-map.md),
[review dispositions](implementation-reviews.md) and
[host support limits](../../native-support.md).

The subsequent [performance validation](performance-validation.md) records real
million-file allocation work, process-tree RSS sampling, history/restore timings
and additional regressions. It supersedes the resource-probe limitations below
only where explicitly measured. macOS validation is now deferred by the owner.

## Executed checks

| Check | Observed result |
|---|---|
| Rust 1.96.0, Windows x64/MSVC | 43 tests passed; Clippy with warnings denied and formatting passed. |
| Rust 1.96.0, Ubuntu WSL/Linux x64 | 44 tests passed; Clippy with warnings denied passed. |
| Final carried-script changes | Contract and recovery suites rerun on Windows and Linux; shared PowerShell/Bash Unicode, duplicate, directory and relative-link fixtures passed. Recovery totals distinguish missing/damaged file content from required metadata findings. |
| Script/document checks | ShellCheck and repository-configured PSScriptAnalyzer passed. Generated architecture/interface maps are current; 459 documents and 755 links checked with zero broken links (29 historical orphan warnings). |
| Native OCI image | Built locally; compressed backup and independent Bash restore passed offline as UID 65532, with read-only image/source, dropped capabilities and no-new-privileges. |
| Existing PowerShell engine | Full harness: 997 Pester tests passed, 3 skipped; 274 integration assertions passed, 2 skipped; no test failures. |
| Existing Bash recovery | All 154 Bats tests passed as the existing non-root Linux account on the Linux filesystem. |

Native cases include seven forced writer termination stages, prune restart both
before journal publication and after deletion, retention cutoff semantics,
previous-definition protection, damaged-object healing, case-only rename failure,
folder-only history, compressed rehoming, bounded subprocess descendants,
mixed-kit refusal and previous-kit recovery, oversized archive output, target
containment, missing prerequisites before writes, and multiple independent sets.
Tests use private fixtures. They do not alter production stores or contact mail
relays/use real credentials. The old PowerShell implementation is unchanged.

The first non-root container fixture on the Windows-mounted scratch drive failed
with EPERM because the mount did not provide the intended Unix ownership behavior.
The Linux-filesystem fixture passed; this does not qualify all bind-mount types.
An initial legacy Bats run on that mount also could not exercise its case-sensitive
shard fixture. The complete rerun on Linux as a non-root user passed without skips.

Representative commands, with Cargo caches/targets and ordinary scratch redirected
to `D:/FileBackupBuild` (or `/mnt/d/FileBackupBuild` under WSL):

```text
cargo fmt --manifest-path rust/Cargo.toml -- --check
cargo clippy --locked --manifest-path rust/Cargo.toml --all-targets --features test-hooks -- -D warnings
cargo test --locked --manifest-path rust/Cargo.toml --features test-hooks
cargo test --locked --manifest-path rust/Cargo.toml --features test-hooks --test contracts --test recovery
pwsh -NoProfile -File scripts/Test-NativeRecovery.ps1 -WithWsl
shellcheck recovery/reconstruct.sh recovery/RECONSTRUCT.command scripts/test_native_container.sh
docker build -f container/native.Dockerfile -t filebackup-native:rust-preview .
bash scripts/test_native_container.sh filebackup-native:rust-preview /tmp
bats tests/bash
cargo build --locked --release --manifest-path rust/Cargo.toml
```

Release builds omit `test-hooks`. Windows and Linux packages include exact
third-party notices, a dependency inventory and SHA-256 checksums; artifacts stay
on D:. Both packaged executables report version 0.1.0. All 204 Windows and 336
Linux file checksums, ZIP integrity and ZIP/file byte agreement passed. The private
archives are `D:/FileBackupBuild/packages/filebackup-native-windows-x64-20261106.zip`
and `D:/FileBackupBuild/packages/filebackup-native-linux-x64-20261106.zip`.
No package or image has been published. The three-platform CI workflow is
prepared but has not run remotely. macOS has not been compiled or exercised here.
Rust/Linux caches were installed on D:; Docker uses the existing WSL installation.
C: remained above 30 GiB free at the final local checks. No unrelated caches or
user files were deleted to make room.

## Resource probes, not envelope qualification

These release-build measurements sample the main process RSS. They use synthetic
metadata, one small physical content object, uncontrolled warm caches and the
available workstation, not the designated 4-core/2 GB/100 MiB/s reference host.

| Probe | Elapsed | Peak RSS | Result |
|---|---:|---:|---|
| Latest manifest with 1,000,000 rows, deep verify | 7.609 s | 489,893,888 bytes | Exit 0 |
| Backup replacing 1,000,000 prior logical paths with one source path | 33.469 s | 1,088,376,832 bytes | Exit 0 |
| 365 historical states plus latest, 100,000 rows each; deep verify of 36.6 million rows | 161.375 s | 64,204,800 bytes | Exit 0 |

The history probe hard-links its identical manifests to save disk space. These
results show exercised metadata behavior; they do not establish full pool
cardinality, combined subprocess RSS, the 2 TiB restore budget, or cold-storage
performance. No 2 TiB fixture fits the available scratch capacity.

## Outstanding work before release designation

- Hard deadlines for blocked source filesystem operations remain implementation
  work. Tool subprocess deadlines are implemented and exercised, but cannot make
  a stalled OS filesystem call bounded.
- Full 1M-file/2 TiB/365-state reference tests, combined 2 GB RSS qualification,
  restore/check timing, and any indexing/spill changes demanded by those results.
- macOS/APFS execution, Windows link privilege profiles, real removable/network
  filesystems, disconnect/suspend/power-loss tests, and broader path-alias cases.
- Live credential/TLS relay and desktop launcher/UI qualification; designated
  legacy migration support remains empty. Existing stores keep their old kits.
- Remaining permutations recorded beside each drafted TC/LLR in the bindings.

Spine validation has zero orphan, integrity and interface findings. Strict trace
checking still reports 18 pre-existing approved-SR form findings, so the overall
legacy check harness is not wholly green. Those normative requirements have not
been rewritten merely to silence the checker; hooks remain disabled. Raw local
logs and measurement JSON are in the ignored `.artifacts/native-transition/`
directory; this checked-in record preserves their outcomes for reviewers.
