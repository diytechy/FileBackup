# Native preview support and evidence

This is a development status, not a release qualification claim. The PowerShell
implementation remains available while the native transition is exercised.

| Combination | Current evidence |
|---|---|
| Windows x64 / Rust 1.96 / local NTFS | Native codec, backup, compression, history, retention, view and forced-termination fixtures executed locally. |
| Ubuntu WSL / Rust 1.96 / mounted local NTFS | Native fixtures and independent bash compressed restoration executed locally. This is not an ext4/network-filesystem qualification. |
| PowerShell 7 recovery | Shared-content, Unicode/bracketed paths, empty directory, relative link, compressed content and missing-required-metadata fixtures executed. |
| Bash 4+ recovery | Same basic carried-kit fixtures, plus native compressed-output fixture, executed under Ubuntu WSL. |
| macOS / APFS | Planned CI build/test lane; not yet executed here and not designated supported. |
| Linux OCI container / local Docker under WSL | Image built; compressed backup and independent Bash restore passed with no network, a read-only image/source, dropped capabilities and a non-root user. |
| Network filesystems, removable exFAT/FAT32, ARM CPUs | Require their declared build/runtime/hardware evidence before support designation. |

Pending qualification includes the 1M-file/2 TiB/365-state envelope, combined
2 GB resident-memory limit, restore/check elapsed-time budgets, suspend/resume,
network disconnects, physical power loss and the full target-host metadata matrix.
Small fixtures and process termination do not establish those claims.

Notification adapters, optional media reporting, interactive desktop launchers,
inspection/repair and retention estimates are implemented. Live mail/credential
access and desktop UI are not yet qualified. A one-million-row, single-object
release-build deep-check probe completed in 7.6 seconds at about 490 MB peak RSS.
A synthetic backup replacing one million prior paths with one source path used
about 1.09 GB peak RSS and 33.5 seconds. These are single-process measurements;
this synthetic warm metadata probe does not establish full-volume or combined
process memory compliance. A separate 100,000-row-per-state probe with 365
historical states plus latest checked 36.6 million rows in 161.4 seconds at about
64 MB peak RSS; its historical manifests were hard-linked to limit fixture disk
use, and the entire pool held one small object. Hard deadlines for blocked source filesystem I/O,
full resource measurements and the remaining requirement/test permutations are
still open. See the [implementation bindings](plans/native-design-2026-11-05/implementation-map.md).
Recovery targets must be supplied in their ordinary, fully expanded absolute
spelling; DOS short-name aliases and case aliases on unqualified hosts are not
covered by the current script qualification. Use exclusively controlled targets.
Old-version continuation/migration support remains an empty set;
the supported transition is a new empty native store while preserving old stores
with their own recovery kits.

For exact review/test progression and limitations, see the repository's
[implementation workorder](plans/native-design-2026-11-05/implementation-workorder.md).
