# Code and test attachment audit

Snapshot of lexical evidence after carrier conversion. **No row is certified implemented or tested by this table.** A symbol definition or TC mention is a navigation aid; compare its behavior and execute the appropriate tests before approving an attachment. Current contract text and parent IDs still require reconciliation.

All 87 LLR rows are included. Missing definitions and missing parents remain visible. A removed symbol is not repaired by renaming its trace field to the nearest surviving function.

| LLR | Parent SR gaps | Declared symbols found / named | Missing declarations | Existing test mentions / cited TCs |
|---|---|---|---|---|
| LLR-001 | — | 0/2 | `Update-SourceManifest`, `Compare-SourceToBackup` | 0/5 |
| LLR-002 | SR-002 | 2/2 | — | 0/2 |
| LLR-003 | — | 1/2 | `Invoke-BackupFileGroup` | 2/3 |
| LLR-004 | SR-004 | 2/2 | — | 5/6 |
| LLR-005 | — | 0/2 | `Complete-ChangeFolder`, `Initialize-StagingFolder` | 0/3 |
| LLR-006 | SR-006 | 0/1 | `Move-RemovedFilesToStaging` | 0/1 |
| LLR-007 | — | 1/1 | — | 0/3 |
| LLR-008 | — | 1/2 | `Reconstruct.ps1` | 0/2 |
| LLR-009 | — | 0/1 | `Reconstruct.ps1` | 0/2 |
| LLR-010 | — | 0/1 | `Reconstruct.ps1` | 1/2 |
| LLR-011 | — | 3/3 | — | 0/2 |
| LLR-014 | — | 1/1 | — | 1/1 |
| LLR-015 | — | 0/1 | `FileBackup.ps1` | 0/1 |
| LLR-016 | — | 3/4 | `FileBackup.ps1` | 1/2 |
| LLR-017 | — | 3/14 | `Initialize-StagingFolder`, `Get-StagingLockState`, `Read-StagingOwnerRecord`, `Write-StagingOwnerRecord`, `Invoke-StagingLockReclaim`, `Clear-ReclaimedStagingFolder`, `Remove-OwnStagingFolder`, `Assert-StagingLockOwned`, `Get-StagingConfirmationWait`, `Get-StagingLockIdentity`, `Compare-StagingLockIdentity` | 2/19 |
| LLR-018 | — | 0/1 | `FileBackup.ps1` | 0/1 |
| LLR-020 | SR-020 | 3/3 | — | 0/1 |
| LLR-021 | — | 1/2 | `Update-SourceManifest` | 0/2 |
| LLR-022 | SR-022 | 1/1 | — | 0/3 |
| LLR-023 | — | 1/2 | `Reconstruct.ps1` | 1/2 |
| LLR-024 | — | 1/2 | `Update-SourceManifest` | 0/3 |
| LLR-025 | SR-025 | 2/2 | — | 1/3 |
| LLR-026 | SR-026 | 0/1 | `Optimize-ChangeFolders` | 1/2 |
| LLR-028 | SR-028 | 4/5 | `Optimize-ChangeFolders` | 0/4 |
| LLR-027 | — | 0/1 | `CredSetEx.ps1` | 0/1 |
| LLR-029 | — | 0/1 | `Reconstruct.ps1` | 0/1 |
| LLR-030 | SR-030 | 1/1 | — | 1/1 |
| LLR-031 | — | 0/1 | `reconstruct.sh` | 2/2 |
| LLR-032 | SR-032 | 1/2 | `to_posix_path` | 1/1 |
| LLR-033 | — | 0/1 | `backup.sh` | 0/1 |
| LLR-035 | — | 2/2 | — | 0/1 |
| LLR-036 | — | 1/1 | — | 0/1 |
| LLR-037 | SR-037 | 2/2 | — | 1/2 |
| LLR-038 | SR-022 | 4/4 | — | 4/4 |
| LLR-039 | — | 1/2 | `verify_manifest_witness` | 2/2 |
| LLR-040 | — | 3/3 | — | 4/4 |
| LLR-041 | — | 1/3 | `Move-RemovedFilesToStaging`, `Save-SupersededData` | 1/1 |
| LLR-042 | — | 7/7 | — | 5/5 |
| LLR-043 | — | 0/2 | `FileBackup.ps1`, `entrypoint.sh` | 0/1 |
| LLR-045 | — | 4/4 | — | 5/6 |
| LLR-046 | — | 7/7 | — | 3/4 |
| LLR-047 | SR-026 | 4/5 | `Optimize-ChangeFolders` | 4/5 |
| LLR-048 | — | 0/2 | `FileBackup.ps1`, `entrypoint.sh` | 1/1 |
| LLR-049 | — | 4/4 | — | 5/5 |
| LLR-050 | SR-050 | 2/2 | — | 3/3 |
| LLR-051 | SR-051, SR-006 | 0/2 | `Save-SupersededData`, `Move-RemovedFilesToStaging` | 2/2 |
| LLR-052 | — | 3/4 | `Assert-BackupCapacity` | 2/2 |
| LLR-053 | — | 0/2 | `Compare-SourceToBackup`, `Invoke-BackupFileGroup` | 0/1 |
| LLR-054 | SR-054 | 2/2 | — | 0/2 |
| LLR-055 | — | 2/3 | `Update-SourceManifest` | 1/2 |
| LLR-056 | — | 2/2 | — | 3/3 |
| LLR-057 | SR-057 | 6/8 | `Update-SourceManifest`, `Optimize-ChangeFolders` | 2/2 |
| LLR-058 | SR-058, SR-060, SR-013 | 1/2 | `Invoke-BackupFileGroup` | 4/4 |
| LLR-059 | SR-028 | 0/1 | `Save-SupersededData` | 3/3 |
| LLR-060 | — | 1/4 | `Test-BackupManifest`, `Reconstruct.ps1`, `reconstruct.sh` | 2/2 |
| LLR-061 | — | 1/1 | — | 3/3 |
| LLR-062 | — | 0/1 | `Test-BackupManifest` | 0/1 |
| LLR-063 | — | 1/1 | — | 5/5 |
| LLR-064 | — | 1/1 | — | 1/1 |
| LLR-065 | — | 7/7 | — | 1/1 |
| LLR-066 | — | 2/2 | — | 1/1 |
| LLR-067 | — | 0/3 | `Invoke-BackupFileGroup`, `Get-CopyRetryDelayMs`, `Test-CopyFailureIsTransient` | 1/1 |
| LLR-068 | — | 2/2 | — | 1/1 |
| LLR-069 | SR-069 | 6/6 | — | 11/11 |
| LLR-070 | SR-070 | 1/2 | `Invoke-BackupFileGroup` | 2/2 |
| LLR-071 | — | 0/1 | `stat_size / make_tempdir / iso_now / stamp_mtime_posix` | 1/6 |
| LLR-072 | — | 0/1 | `canon / is_inside` | 0/2 |
| LLR-073 | — | 0/1 | `Test-ShouldPromptGraphically / Select-FolderInteractively / pick_target_dir` | 4/8 |
| LLR-074 | — | 0/1 | `New-ReconstructScript / Wait-BeforeClosing` | 1/3 |
| LLR-075 | SR-022 | 0/1 | `ReconstructCmdName / ReconstructCommandName / ReconstructLegacyBatName / Get-IsInfrastructureFile` | 2/2 |
| LLR-076 | — | 0/1 | `KitRevision marker / Get-BackupKitRevision` | 1/1 |
| LLR-077 | — | 0/1 | `Restore-OneRow / restore_one` | 1/1 |
| LLR-078 | SR-057, SR-022 | 0/1 | `Test-IsVolumeRootPseudoPath / Get-DataFile / Find-DataFileByHash / volume_root_skip` | 5/5 |
| LLR-079 | — | 0/1 | `Resolve-PathPhysically / Test-PathIsInside` | 1/1 |
| LLR-080 | — | 0/7 | `Write-StagingOwnerRecord`, `Read-StagingOwnerRecord`, `Read-StagingMarkerText`, `Get-StagingLockState`, `Start-StagingHeartbeat`, `Stop-StagingHeartbeat`, `StagingHeartbeat` | 0/9 |
| LLR-086 | — | 5/6 | `Invoke-BackupFileGroup` | 7/8 |
| LLR-087 | SR-025 | 2/2 | — | 3/3 |
| LLR-088 | SR-083, SR-022 | 2/5 | `Get-StagingLockState`, `Clear-ReclaimedStagingFolder`, `Remove-OwnStagingFolder` | 2/2 |
| LLR-090 | SR-087 | 3/3 | — | 3/3 |
| LLR-091 | — | 1/3 | `Initialize-StagingFolder`, `Invoke-StagingLockReclaim` | 4/6 |
| LLR-092 | — | 1/1 | — | 5/5 |
| LLR-093 | SR-087 | 3/4 | `Optimize-ChangeFolders` | 2/2 |
| LLR-094 | — | 3/3 | — | 4/4 |
| LLR-095 | — | 9/9 | — | 0/1 |
| LLR-096 | SR-069, SR-058 | 8/8 | — | 0/2 |
| LLR-097 | — | 4/4 | — | 0/1 |
| LLR-098 | — | 3/3 | — | 0/2 |

## Current definitions and trace leads

| LLR | Definition / code-backlink locations |
|---|---|
| LLR-001 | `Modules/FileBackup.Engine.psm1:5286` |
| LLR-002 | `Modules/FileBackup.Common.psm1:449`; `Modules/FileBackup.Common.psm1:339`; `Modules/FileBackup.Common.psm1:356`; `Modules/FileBackup.Common.psm1:455`; `Modules/FileBackup.Engine.psm1:5360` |
| LLR-003 | `Modules/FileBackup.Common.psm1:613`; `Modules/FileBackup.Common.psm1:525`; `Modules/FileBackup.Common.psm1:582`; `Modules/FileBackup.Common.psm1:641`; `Modules/FileBackup.Engine.psm1:5480` |
| LLR-004 | `Modules/FileBackup.Common.psm1:896`; `Modules/FileBackup.Common.psm1:913`; `Modules/FileBackup.Common.psm1:230`; `Modules/FileBackup.Common.psm1:902`; `Modules/FileBackup.Common.psm1:914` |
| LLR-005 | `Modules/FileBackup.Engine.psm1:396`; `Modules/FileBackup.Engine.psm1:410`; `Modules/FileBackup.Engine.psm1:5990`; `Modules/FileBackup.Engine.psm1:6234`; `Modules/FileBackup.Engine.psm1:7131`; `Modules/FileBackup.Engine.psm1:7170` |
| LLR-006 | None found |
| LLR-007 | `Modules/FileBackup.Engine.psm1:3506`; `Modules/FileBackup.Common.psm1:429`; `Modules/FileBackup.Engine.psm1:3476`; `Modules/FileBackup.Engine.psm1:3527` |
| LLR-008 | `Modules/FileBackup.Common.psm1:958`; `Modules/FileBackup.Common.psm1:969` |
| LLR-009 | `Reconstruct.ps1:1454` |
| LLR-010 | None found |
| LLR-011 | `Modules/FileBackup.Engine.psm1:541`; `Modules/FileBackup.Engine.psm1:362`; `Modules/FileBackup.Engine.psm1:376`; `Modules/FileBackup.Engine.psm1:309`; `Modules/FileBackup.Engine.psm1:368`; `Modules/FileBackup.Engine.psm1:381`; `Modules/FileBackup.Engine.psm1:549` |
| LLR-014 | `Modules/FileBackup.Engine.psm1:7191`; `Reconstruct.ps1:679`; `Modules/FileBackup.Engine.psm1:4370`; `Modules/FileBackup.Engine.psm1:4405`; `Modules/FileBackup.Engine.psm1:4436`; `Modules/FileBackup.Engine.psm1:4507`; `Modules/FileBackup.Engine.psm1:4566`; `Modules/FileBackup.Engine.psm1:6512`; `Modules/FileBackup.Engine.psm1:6541`; `Modules/FileBackup.Engine.psm1:6570`; `Modules/FileBackup.Engine.psm1:6606`; `Modules/FileBackup.Engine.psm1:6638`; `Modules/FileBackup.Engine.psm1:6669`; `Modules/FileBackup.Engine.psm1:6741`; `Modules/FileBackup.Engine.psm1:6802`; `Modules/FileBackup.Engine.psm1:7220` |
| LLR-015 | None found |
| LLR-016 | `Modules/FileBackup.Engine.psm1:455`; `Modules/FileBackup.Engine.psm1:423`; `Modules/FileBackup.Common.psm1:339`; `Reconstruct.ps1:710` |
| LLR-017 | `Modules/FileBackup.Engine.psm1:7191`; `Modules/FileBackup.Engine.psm1:3668`; `Modules/FileBackup.Engine.psm1:3764`; `Modules/FileBackup.Engine.psm1:3638` |
| LLR-018 | None found |
| LLR-020 | `Modules/FileBackup.Engine.psm1:455`; `Modules/FileBackup.Engine.psm1:423`; `Modules/FileBackup.Engine.psm1:503`; `Modules/FileBackup.Engine.psm1:504` |
| LLR-021 | `Modules/FileBackup.Common.psm1:613`; `Modules/FileBackup.Common.psm1:641` |
| LLR-022 | `Modules/FileBackup.Engine.psm1:30`; `Modules/FileBackup.Engine.psm1:38` |
| LLR-023 | `Modules/FileBackup.Common.psm1:1202`; `Modules/FileBackup.Common.psm1:1232` |
| LLR-024 | `Modules/FileBackup.Common.psm1:1476` |
| LLR-025 | `Modules/FileBackup.Common.psm1:1318`; `Modules/FileBackup.Common.psm1:1476`; `Modules/FileBackup.Common.psm1:483`; `Modules/FileBackup.Common.psm1:1324`; `Modules/FileBackup.Common.psm1:1362`; `Modules/FileBackup.Common.psm1:1514` |
| LLR-026 | None found |
| LLR-028 | `Modules/FileBackup.Engine.psm1:7191`; `Modules/FileBackup.Engine.psm1:390`; `Modules/FileBackup.Engine.psm1:404`; `Modules/FileBackup.Common.psm1:258`; `Modules/FileBackup.Engine.psm1:309`; `Modules/FileBackup.Engine.psm1:396`; `Modules/FileBackup.Engine.psm1:410` |
| LLR-027 | None found |
| LLR-029 | `Reconstruct.ps1:1454` |
| LLR-030 | `bash/reconstruct.sh:268`; `bash/reconstruct.sh:87`; `bash/reconstruct.sh:267` |
| LLR-031 | `bash/reconstruct.sh:87` |
| LLR-032 | `bash/reconstruct.sh:434`; `bash/reconstruct.sh:433` |
| LLR-033 | None found |
| LLR-035 | `Modules/FileBackup.Engine.psm1:7191`; `Modules/FileBackup.Engine.psm1:390`; `Modules/FileBackup.Engine.psm1:6234` |
| LLR-036 | `Modules/FileBackup.Engine.psm1:7191`; `Modules/FileBackup.Engine.psm1:6853`; `Modules/FileBackup.Engine.psm1:6886` |
| LLR-037 | `Modules/FileBackup.Engine.psm1:423`; `Modules/FileBackup.Engine.psm1:455`; `Modules/FileBackup.Common.psm1:184`; `Modules/FileBackup.Common.psm1:230` |
| LLR-038 | `Modules/FileBackup.Common.psm1:1476`; `Modules/FileBackup.Common.psm1:1626`; `Modules/FileBackup.Common.psm1:1606`; `Modules/FileBackup.Engine.psm1:30`; `Modules/FileBackup.Common.psm1:1618`; `Modules/FileBackup.Common.psm1:1666`; `Modules/FileBackup.Engine.psm1:38` |
| LLR-039 | `Modules/FileBackup.Common.psm1:1701`; `Modules/FileBackup.Common.psm1:1734` |
| LLR-040 | `Reconstruct.ps1:336`; `Reconstruct.ps1:247`; `bash/reconstruct.sh:251`; `Reconstruct.ps1:191`; `Reconstruct.ps1:265`; `Reconstruct.ps1:315`; `Reconstruct.ps1:395`; `Reconstruct.ps1:1086`; `Reconstruct.ps1:1140`; `Reconstruct.ps1:1384`; `Reconstruct.ps1:1454`; `Reconstruct.ps1:1462`; `bash/reconstruct.sh:335`; `bash/reconstruct.sh:472` |
| LLR-041 | `Modules/FileBackup.Engine.psm1:7191` |
| LLR-042 | `Modules/FileBackup.Engine.psm1:7754`; `Modules/FileBackup.Engine.psm1:7517`; `Modules/FileBackup.Engine.psm1:7371`; `Modules/FileBackup.Engine.psm1:7686`; `Modules/FileBackup.Engine.psm1:7433`; `Modules/FileBackup.Engine.psm1:7475`; `Modules/FileBackup.Engine.psm1:7496`; `Modules/FileBackup.Engine.psm1:7379`; `Modules/FileBackup.Engine.psm1:7444`; `Modules/FileBackup.Engine.psm1:7483`; `Modules/FileBackup.Engine.psm1:7504`; `Modules/FileBackup.Engine.psm1:7536`; `Modules/FileBackup.Engine.psm1:7701`; `Modules/FileBackup.Engine.psm1:7785` |
| LLR-043 | `FileBackup.ps1:325` |
| LLR-045 | `Modules/FileBackup.Engine.psm1:3225`; `Modules/FileBackup.Engine.psm1:990`; `Modules/FileBackup.Engine.psm1:3024`; `Modules/FileBackup.Engine.psm1:3107`; `Modules/FileBackup.Engine.psm1:944`; `Modules/FileBackup.Engine.psm1:969`; `Modules/FileBackup.Engine.psm1:1043`; `Modules/FileBackup.Engine.psm1:3052`; `Modules/FileBackup.Engine.psm1:3133`; `Modules/FileBackup.Engine.psm1:3284` |
| LLR-046 | `Modules/FileBackup.Engine.psm1:3225`; `Modules/FileBackup.Engine.psm1:2727`; `Modules/FileBackup.Engine.psm1:1255`; `Modules/FileBackup.Engine.psm1:3180`; `Modules/FileBackup.Engine.psm1:2956`; `Modules/FileBackup.Engine.psm1:2889`; `Modules/FileBackup.Engine.psm1:2659`; `Modules/FileBackup.Engine.psm1:1242`; `Modules/FileBackup.Engine.psm1:1294`; `Modules/FileBackup.Engine.psm1:2690`; `Modules/FileBackup.Engine.psm1:2759`; `Modules/FileBackup.Engine.psm1:2926`; `Modules/FileBackup.Engine.psm1:2990`; `Modules/FileBackup.Engine.psm1:3204`; `Modules/FileBackup.Engine.psm1:3284`; `Modules/FileBackup.Engine.psm1:3430` |
| LLR-047 | `Modules/FileBackup.Engine.psm1:836`; `Modules/FileBackup.Engine.psm1:2846`; `Modules/FileBackup.Engine.psm1:975`; `Modules/FileBackup.Engine.psm1:937`; `Modules/FileBackup.Engine.psm1:873`; `Modules/FileBackup.Engine.psm1:982`; `Modules/FileBackup.Engine.psm1:1043`; `Modules/FileBackup.Engine.psm1:2870` |
| LLR-048 | `FileBackup.ps1:440`; `Modules/FileBackup.Engine.psm1:3430`; `Modules/FileBackup.Engine.psm1:4405` |
| LLR-049 | `Modules/FileBackup.Engine.psm1:1754`; `Modules/FileBackup.Engine.psm1:1451`; `Modules/FileBackup.Engine.psm1:2413`; `Modules/FileBackup.Engine.psm1:1389`; `FileBackup.ps1:520`; `Modules/FileBackup.Engine.psm1:1242`; `Modules/FileBackup.Engine.psm1:1407`; `Modules/FileBackup.Engine.psm1:1546`; `Modules/FileBackup.Engine.psm1:1739`; `Modules/FileBackup.Engine.psm1:1789`; `Modules/FileBackup.Engine.psm1:1886`; `Modules/FileBackup.Engine.psm1:1973`; `Modules/FileBackup.Engine.psm1:2108`; `Modules/FileBackup.Engine.psm1:2368`; `Modules/FileBackup.Engine.psm1:2400`; `Modules/FileBackup.Engine.psm1:2462`; `Modules/FileBackup.Engine.psm1:2612` |
| LLR-050 | `Reconstruct.ps1:336`; `bash/reconstruct.sh:722`; `Reconstruct.ps1:395`; `Reconstruct.ps1:1384` |
| LLR-051 | None found |
| LLR-052 | `Modules/FileBackup.Common.psm1:1202`; `Modules/FileBackup.Common.psm1:1258`; `Modules/FileBackup.Engine.psm1:7191`; `Modules/FileBackup.Common.psm1:1189`; `Modules/FileBackup.Common.psm1:1232`; `Modules/FileBackup.Common.psm1:1287`; `Modules/FileBackup.Engine.psm1:5409` |
| LLR-053 | None found |
| LLR-054 | `FileBackup.ps1:492`; `Modules/FileBackup.Engine.psm1:1255`; `FileBackup.ps1:520` |
| LLR-055 | `Modules/FileBackup.Engine.psm1:119`; `Modules/FileBackup.Engine.psm1:7191`; `Modules/FileBackup.Engine.psm1:111`; `Modules/FileBackup.Engine.psm1:129`; `Modules/FileBackup.Engine.psm1:208`; `Modules/FileBackup.Engine.psm1:5286` |
| LLR-056 | `Reconstruct.ps1:1483`; `bash/reconstruct.sh:382`; `Reconstruct.ps1:1514`; `bash/reconstruct.sh:380` |
| LLR-057 | `Modules/FileBackup.Engine.psm1:246`; `Modules/FileBackup.Engine.psm1:937`; `Modules/FileBackup.Engine.psm1:990`; `Modules/FileBackup.Engine.psm1:2956`; `Modules/FileBackup.Common.psm1:958`; `Reconstruct.ps1:336`; `Modules/FileBackup.Engine.psm1:259`; `Modules/FileBackup.Engine.psm1:5286` |
| LLR-058 | `Modules/FileBackup.Engine.psm1:4192`; `Modules/FileBackup.Engine.psm1:4242`; `Modules/FileBackup.Engine.psm1:5480` |
| LLR-059 | `Modules/FileBackup.Engine.psm1:6128` |
| LLR-060 | `Modules/FileBackup.Engine.psm1:7191`; `Modules/FileBackup.Engine.psm1:1789`; `Modules/FileBackup.Engine.psm1:5228` |
| LLR-061 | `Modules/FileBackup.Engine.psm1:6263`; `Modules/FileBackup.Engine.psm1:6315` |
| LLR-062 | `Modules/FileBackup.Engine.psm1:782`; `Modules/FileBackup.Engine.psm1:824` |
| LLR-063 | `Modules/FileBackup.Engine.psm1:7371`; `Modules/FileBackup.Engine.psm1:4566`; `Modules/FileBackup.Engine.psm1:4687` |
| LLR-064 | `FileBackup.ps1:615`; `FileBackup.ps1:632` |
| LLR-065 | `Modules/FileBackup.Engine.psm1:580`; `Modules/FileBackup.Engine.psm1:703`; `Modules/FileBackup.Common.psm1:1120`; `Modules/FileBackup.Common.psm1:1142`; `Reconstruct.ps1:1628`; `bash/reconstruct.sh:488`; `bash/reconstruct.sh:512`; `Reconstruct.ps1:1658`; `Modules/FileBackup.Common.psm1:1133`; `Modules/FileBackup.Common.psm1:1160`; `Modules/FileBackup.Engine.psm1:630`; `Modules/FileBackup.Engine.psm1:722` |
| LLR-066 | `Reconstruct.ps1:1584`; `bash/reconstruct.sh:573`; `Reconstruct.ps1:1613` |
| LLR-067 | None found |
| LLR-068 | `Modules/FileBackup.Common.psm1:1014`; `bash/reconstruct.sh:553`; `Modules/FileBackup.Common.psm1:1061`; `Modules/FileBackup.Engine.psm1:5092` |
| LLR-069 | `Modules/FileBackup.Common.psm1:499`; `Modules/FileBackup.Common.psm1:556`; `Modules/FileBackup.Common.psm1:613`; `Modules/FileBackup.Common.psm1:653`; `Modules/FileBackup.Common.psm1:767`; `Modules/FileBackup.Common.psm1:724`; `Reconstruct.ps1:585`; `Reconstruct.ps1:637`; `Modules/FileBackup.Common.psm1:525`; `Modules/FileBackup.Common.psm1:582`; `Modules/FileBackup.Common.psm1:641`; `Modules/FileBackup.Common.psm1:678`; `Modules/FileBackup.Common.psm1:753`; `Modules/FileBackup.Common.psm1:784`; `Modules/FileBackup.Common.psm1:803`; `Modules/FileBackup.Common.psm1:836`; `Modules/FileBackup.Common.psm1:872`; `Modules/FileBackup.Engine.psm1:4788`; `Modules/FileBackup.Engine.psm1:4824`; `bash/reconstruct.sh:871` |
| LLR-070 | `Modules/FileBackup.Common.psm1:613`; `Modules/FileBackup.Common.psm1:641` |
| LLR-071 | None found |
| LLR-072 | `Reconstruct.ps1:233` |
| LLR-073 | `Reconstruct.ps1:766`; `Reconstruct.ps1:812`; `Reconstruct.ps1:850`; `Reconstruct.ps1:899` |
| LLR-074 | None found |
| LLR-075 | None found |
| LLR-076 | None found |
| LLR-077 | None found |
| LLR-078 | `Modules/FileBackup.Common.psm1:1920`; `Modules/FileBackup.Engine.psm1:259` |
| LLR-079 | `Reconstruct.ps1:1005`; `Reconstruct.ps1:1048` |
| LLR-080 | None found |
| LLR-086 | `Modules/FileBackup.Engine.psm1:3886`; `Modules/FileBackup.Engine.psm1:4074`; `Modules/FileBackup.Engine.psm1:4192`; `Modules/FileBackup.Engine.psm1:4300`; `Modules/FileBackup.Engine.psm1:4321`; `Modules/FileBackup.Engine.psm1:3954`; `Modules/FileBackup.Engine.psm1:4142`; `Modules/FileBackup.Engine.psm1:4242`; `Modules/FileBackup.Engine.psm1:4315`; `Modules/FileBackup.Engine.psm1:4336`; `Modules/FileBackup.Engine.psm1:5480` |
| LLR-087 | `Modules/FileBackup.Common.psm1:1476`; `Modules/FileBackup.Common.psm1:1626`; `Modules/FileBackup.Common.psm1:1514` |
| LLR-088 | `Modules/FileBackup.Engine.psm1:30`; `Modules/FileBackup.Common.psm1:258` |
| LLR-090 | `Modules/FileBackup.Engine.psm1:3649`; `Modules/FileBackup.Engine.psm1:3668`; `Modules/FileBackup.Engine.psm1:3764`; `Modules/FileBackup.Engine.psm1:3661`; `Modules/FileBackup.Engine.psm1:3717`; `Modules/FileBackup.Engine.psm1:3787` |
| LLR-091 | `Modules/FileBackup.Engine.psm1:7191`; `Modules/FileBackup.Engine.psm1:6938`; `Modules/FileBackup.Engine.psm1:7220` |
| LLR-092 | `Modules/FileBackup.Engine.psm1:3225`; `Modules/FileBackup.Engine.psm1:3284` |
| LLR-093 | `Modules/FileBackup.Engine.psm1:3764`; `Modules/FileBackup.Engine.psm1:3649`; `Modules/FileBackup.Engine.psm1:937`; `Modules/FileBackup.Engine.psm1:3661`; `Modules/FileBackup.Engine.psm1:3787` |
| LLR-094 | `Modules/FileBackup.Engine.psm1:3806`; `Modules/FileBackup.Engine.psm1:2413`; `Modules/FileBackup.Engine.psm1:2576`; `Modules/FileBackup.Engine.psm1:2462`; `Modules/FileBackup.Engine.psm1:2612`; `Modules/FileBackup.Engine.psm1:3840` |
| LLR-095 | `Modules/FileBackup.Engine.psm1:7686`; `Modules/FileBackup.Engine.psm1:4521`; `Modules/FileBackup.Engine.psm1:4416`; `Modules/FileBackup.Engine.psm1:4489`; `Modules/FileBackup.Engine.psm1:956`; `Modules/FileBackup.Engine.psm1:4646`; `Modules/FileBackup.Engine.psm1:5105`; `Modules/FileBackup.Engine.psm1:7517`; `Modules/FileBackup.Engine.psm1:7371` |
| LLR-096 | `Modules/FileBackup.Common.psm1:790`; `Modules/FileBackup.Common.psm1:811`; `Modules/FileBackup.Common.psm1:848`; `Modules/FileBackup.Engine.psm1:4927`; `Modules/FileBackup.Engine.psm1:4973`; `Modules/FileBackup.Engine.psm1:5423`; `Modules/FileBackup.Engine.psm1:5749`; `Reconstruct.ps1:536` |
| LLR-097 | `Modules/FileBackup.Engine.psm1:93`; `Modules/FileBackup.Engine.psm1:5256`; `Modules/FileBackup.Engine.psm1:580`; `Modules/FileBackup.Engine.psm1:7191` |
| LLR-098 | `Modules/FileBackup.Engine.psm1:3506`; `Reconstruct.ps1:536`; `Reconstruct.ps1:1357` |

## Unresolved source references

The production `Implements:` lines name these IDs absent from the current live registries:

`LLR-034`, `LLR-150`, `SR-002`, `SR-004`, `SR-020`, `SR-022`, `SR-025`, `SR-026`, `SR-028`, `SR-030`, `SR-032`, `SR-037`, `SR-050`, `SR-054`, `SR-057`, `SR-058`, `SR-069`, `SR-070`, `SR-087`.

Restore these obligations under reviewed surviving contracts or explicitly retire/repoint the references. Do not mint empty rows just to make a checker pass.

## Reattachment order

1. Reconcile the parent system obligation against accepted needs and the fresh derivation.
2. Rewrite the design contract in input/outcome/refusal terms; preserve its useful dimensions and negative controls.
3. Inspect the current symbol and identify exact uncovered clauses. Retain a missing implementation as work, not a fabricated binding.
4. Attach executable test blocks and result evidence, separating desired behavior from historical Pass text.
5. Update code `Implements:` annotations and regenerate the PowerShell architecture map only once the ID mapping is settled.
