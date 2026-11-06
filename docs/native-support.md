# Native preview support and evidence

This is a development status, not a release qualification claim. The PowerShell
implementation remains available while the native transition is exercised.

| Combination | Current evidence |
|---|---|
| Windows x64 / Rust 1.96 / local NTFS | Native codec, backup, compression, history, retention, view and forced-termination fixtures executed locally. |
| Ubuntu WSL / Rust 1.96 / Linux temporary filesystem and mounted NTFS | Native fixtures and independent Bash compressed restoration executed locally. Million-file RAM-filesystem probes measure application memory; full disk/network qualification remains open. |
| PowerShell 7 recovery | Shared-content, Unicode/bracketed paths, empty directory, relative link, compressed content and missing-required-metadata fixtures executed. |
| Bash 4+ recovery | Same basic carried-kit fixtures, plus native compressed-output fixture, executed under Ubuntu WSL. |
| macOS / APFS | Planned CI build/test lane; validation deferred by the owner on 2026-11-06, not designated supported. |
| Linux OCI container / local Docker under WSL | Image built; compressed backup and independent Bash restore passed with no network, a read-only image/source, dropped capabilities and a non-root user. |
| Network filesystems, removable exFAT/FAT32, ARM CPUs | Require their declared build/runtime/hardware evidence before support designation. |

The [owner-corrected reference](plans/native-design-2026-11-05/owner-hdd-reference.md)
uses local rotational hard-disk (platter) storage sustaining 100 MiB/s sequential
transfers, four cores and 2 GB available RAM. D: is the candidate test drive.
SSD and RAM measurements characterize those environments; their timings do not
qualify the HDD reference.

Pending qualification includes the 1M-file/2 TiB/365-state envelope, combined
2 GB resident-memory limit, restore/check elapsed-time budgets, suspend/resume,
network disconnects, physical power loss and the full target-host metadata matrix.
Small fixtures and process termination do not establish those claims.

Notification adapters, optional media reporting, interactive desktop launchers,
inspection/repair and retention estimates are implemented. Live mail/credential
access and desktop UI are not yet qualified. The latest release-build corpus with one
million real source files and independent stored objects completed unchanged
backup at 0.973 GB peak application RSS and deep check at 0.920 GB. This used a
RAM filesystem, whose kernel memory is outside application RSS; it does not
establish operation on a 2 GB host or disk throughput. Adding a new compressed
1 GiB file to a million-file corpus completed at 1.144 GB simultaneous engine/tool
RSS with two 7-Zip workers. See the
[memory optimization results](plans/native-design-2026-11-05/memory-optimization-2026-11-06.md)
for matched iterations and scope. The process-tree sampler has 50 ms
sampling limitations. Small SSD PowerShell restoration improved from 76.6 to 30.3
seconds; Bash on WSL's Linux filesystem improved from 215.4 to 148.8 seconds.
Every restored path and SHA-256 digest matched. See the
[performance validation](plans/native-design-2026-11-05/performance-validation.md)
for real-file/history/compression measurements, exclusions and reproducible
commands. Hard deadlines for blocked source filesystem I/O, full reference
resource measurements and remaining permutations are still open. See the
[implementation bindings](plans/native-design-2026-11-05/implementation-map.md).
Recovery targets must be supplied in their ordinary, fully expanded absolute
spelling; DOS short-name aliases and case aliases on unqualified hosts are not
covered by the current script qualification. Use exclusively controlled targets.
Old-version continuation/migration support remains an empty set;
the supported transition is a new empty native store while preserving old stores
with their own recovery kits.

For exact review/test progression and limitations, see the repository's
[implementation workorder](plans/native-design-2026-11-05/implementation-workorder.md).
