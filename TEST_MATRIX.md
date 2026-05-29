# Test matrix

The full permutation of what FileBackup is tested against, and **where** each cell runs:
GitHub-hosted CI, a self-hosted virtual-disk lane, or a manual hardware runbook.

## Axes

| Axis | Values |
|---|---|
| PowerShell edition | **pwsh 7+** (only supported edition; 5.1 is out of scope) |
| Storage mode       | `Mirror`, `HashAddressed` |
| Compression        | off, on → 4 mode combos (Mirror, Mirror+Compress, HashAddressed, HashAddressed+Compress) |
| Hash-recalc freq   | `A E D W M Y N` (unit-covered in G6 / `Engine.Tests.ps1`) |
| Backend (volumes)  | `Subst` (CI), `VHDX` (virtual disks), `RealUSB` (hardware) |
| Suite group        | G1–G8 (see [tests/README.md](tests/README.md)) |
| Filesystem (HW)    | NTFS, exFAT, FAT32 |

## Coverage map

Legend: ✅ automated in CI · 🟡 self-hosted/manual runbook · ⛔ N/A.

| Backend → | Subst (hosted CI) | VHDX (self-hosted) | RealUSB (hardware) |
|---|:---:|:---:|:---:|
| Lint (PSScriptAnalyzer)            | ✅ | — | — |
| Unit (Pester, pure functions)      | ✅ | — | — |
| G1 InitialBackup × 4 modes         | ✅ | 🟡 | 🟡 |
| G2 Incremental × 4 modes           | ✅ | 🟡 | 🟡 |
| G3 Reconstruction × 4 modes        | ✅ | 🟡 | 🟡 |
| G4 Sanitization (mode migration)   | ✅ | 🟡 | 🟡 |
| G5 EdgeCases                       | ✅ | 🟡 | 🟡 |
| G6 HashFrequency (7 codes)         | ✅ | ✅ | ✅ |
| G7 Determinism                     | ✅ | 🟡 | 🟡 |
| G8 RealVolume                      | ⛔ (SKIP) | ⛔ (SKIP) | 🟡 |
| Real NTFS semantics / free space   | — | 🟡 | 🟡 |
| exFAT / FAT32 + >4 GB file limit   | — | — | 🟡 |
| Standalone restore (no repo)       | ✅¹ | 🟡 | 🟡 |

¹ Exercised implicitly: `RECONSTRUCT.ps1` runs from the backup folder using only the
bundled module + DLL. A dedicated "copy backup elsewhere, restore, byte-compare" check is
part of the manual runbook below.

**Current automated total:** 160 integration assertions (4 modes × G1–G7, G8 SKIP) + 27
Pester unit tests, all green; lint clean.

## Environments

### GitHub-hosted (`windows-latest`, pwsh) — `.github/workflows/tests.yml`
1. **lint** — PSScriptAnalyzer over scripts + modules with `tests/PSScriptAnalyzerSettings.psd1`.
2. **unit** — `Invoke-Pester tests/Unit`, results published.
3. **integration** — `Run-All.ps1 -Backend Subst` over all 4 modes, JUnit published.

7-Zip ships on the runner; `System.IO.Hashing` is installed by `tests/Setup.ps1` and
cached.

### Self-hosted VHDX (virtual devices)
Gated by repo variable `HAS_SELF_HOSTED_HYPERV == 'true'` on a `[self-hosted, windows,
hyper-v]` runner. Provides real NTFS semantics, capacity/free-space behavior, and
differencing-disk scenarios that subst can't model.
```powershell
.\RunAllTests.bat VHDX
```

### Hardware (RealUSB) — manual runbook
1. `Setup-USB.bat` (elevates) → wipes a chosen USB device, creates four GPT/NTFS
   partitions labeled `FBTEST-SRC/BKP/CHG/RCN`, copies `real-volumes.json.example` →
   `real-volumes.json`.
2. `RunAllTests.bat RealUSB`.
3. Filesystem variations: reformat the backup partition exFAT / FAT32 and re-run; on FAT32
   verify the >4 GB single-file limit is surfaced cleanly (G5-class edge).
4. Standalone-restore check: copy a produced backup folder to a machine without this repo,
   run `RECONSTRUCT.bat`, and byte-compare the restored tree to the source.

## Gaps / future automation

- exFAT/FAT32 and the FAT32 4 GB boundary are hardware/manual today; could be added to the
  VHDX lane by formatting VHDX volumes with those filesystems.
- The "restore on a clean machine" check is manual; a CI job could stage a backup into a
  fresh runner workspace to automate it.
