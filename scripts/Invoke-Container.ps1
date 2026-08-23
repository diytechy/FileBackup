<#
.SYNOPSIS
    Builds, smoke-tests, exports, publishes, or pulls the FileBackup container.

.DESCRIPTION
    Keeps the local and registry workflows behind one checked-in command. The
    smoke test runs a real compressed backup in the image, reconstructs it with
    the bundled PowerShell kit in a second container, and compares every source
    file byte-for-byte. Registry credentials are never accepted by this script;
    authenticate separately with `docker login` so secrets do not enter process
    arguments or logs.

.PARAMETER Action
    Build | Test | BuildAndTest | Export | Publish | Pull | Load.

.PARAMETER Image
    Local image reference. Defaults to filebackup:local.

.PARAMETER RegistryImage
    Fully-qualified registry reference used by Publish/Pull, for example
    docker.repsy.io/USER/REPOSITORY/filebackup:VERSION.

.PARAMETER OutputPath
    Tar path written by Export. Defaults to .artifacts/filebackup-image.tar.
#>
[CmdletBinding()]
param(
    [ValidateSet('Build','Test','BuildAndTest','Export','Publish','Pull','Load')]
    [string]$Action = 'BuildAndTest',
    [ValidateSet('Auto','Docker','Podman')]
    [string]$Runtime = 'Auto',
    [string]$Image = 'filebackup:local',
    [string]$RegistryImage,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$repo = [System.IO.Path]::GetDirectoryName($PSScriptRoot)
$script:ContainerRuntime = $null

function Invoke-ContainerCommand {
    param([Parameter(Mandatory)][string[]]$Arguments)
    & $script:ContainerRuntime @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$script:ContainerRuntime $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
}

function Initialize-ContainerRuntime {
    $candidates = switch ($Runtime) {
        'Docker' { @('docker') }
        'Podman' { @('podman') }
        default { @('docker','podman') }
    }
    foreach ($candidate in $candidates) {
        if (Get-Command $candidate -ErrorAction SilentlyContinue) {
            $script:ContainerRuntime = $candidate
            break
        }
    }
    if (-not $script:ContainerRuntime) {
        throw 'No container CLI was found on PATH. Install Docker Desktop/Engine or Podman.'
    }
    Write-Host "Using container runtime: $script:ContainerRuntime"
    Invoke-ContainerCommand -Arguments @('version')
}

function Invoke-ImageBuild {
    Write-Host "Building $Image"
    Invoke-ContainerCommand -Arguments @('build','--tag',$Image,$repo)
}

function New-SmokeConfiguration {
    param([Parameter(Mandatory)][string]$Path)
    [ordered]@{
        ConfigVersion = 1
        Tools = [ordered]@{ SevenZipPath = '/usr/bin/7z' }
        BackupSets = @(
            [ordered]@{
                Name = 'ContainerSmoke'
                SourcePath = '/source'
                SourceStatePath = '/state'
                BackupPath = '/backup'
                ChangePath = '/changes'
                HashRecalcFreq = 'N'
                CompressEnabled = $true
                PreserveFolderTree = $false
                AllowEmptySource = $false
            }
        )
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Add-BindMountArguments {
    param(
        [Parameter(Mandatory)][System.Collections.Generic.List[string]]$Arguments,
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Target,
        [switch]$ReadOnly
    )
    $spec = "type=bind,source=$([System.IO.Path]::GetFullPath($Source)),target=$Target"
    if ($ReadOnly) { $spec += ',readonly' }
    $Arguments.Add('--mount')
    $Arguments.Add($spec)
}

function Invoke-ContainerSmokeTest {
    Write-Host "Smoke-testing $Image"
    Invoke-ContainerCommand -Arguments @('image','inspect',$Image)

    $smokeRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("FileBackupContainerSmoke_" + [guid]::NewGuid().ToString('N'))
    $source = Join-Path $smokeRoot 'source'
    $config = Join-Path $smokeRoot 'config'
    $state = Join-Path $smokeRoot 'state'
    $backup = Join-Path $smokeRoot 'backup'
    $changes = Join-Path $smokeRoot 'changes'
    $logs = Join-Path $smokeRoot 'logs'
    $restore = Join-Path $smokeRoot 'restore'
    $folders = @($source,$config,$state,$backup,$changes,$logs,$restore)

    try {
        New-Item -ItemType Directory -Path $folders -Force | Out-Null
        if ($IsLinux -or $IsMacOS) {
            & chmod 0777 @folders
            if ($LASTEXITCODE -ne 0) { throw 'Could not make smoke-test bind directories writable.' }
        }

        [System.IO.File]::WriteAllText((Join-Path $source 'alpha.txt'), ('compressible payload ' * 300))
        [System.IO.File]::WriteAllBytes((Join-Path $source 'binary.dat'), [byte[]](0..255))
        New-SmokeConfiguration -Path (Join-Path $config 'FileBackup.json')

        $runArgs = [System.Collections.Generic.List[string]]@(
            'run','--rm','--network','none','--read-only',
            '--security-opt','no-new-privileges','--cap-drop','ALL',
            '--tmpfs','/tmp:rw,noexec,nosuid,nodev'
        )
        Add-BindMountArguments -Arguments $runArgs -Source (Join-Path $config 'FileBackup.json') -Target '/config/FileBackup.json' -ReadOnly
        Add-BindMountArguments -Arguments $runArgs -Source $source -Target '/source' -ReadOnly
        Add-BindMountArguments -Arguments $runArgs -Source $state -Target '/state'
        Add-BindMountArguments -Arguments $runArgs -Source $backup -Target '/backup'
        Add-BindMountArguments -Arguments $runArgs -Source $changes -Target '/changes'
        Add-BindMountArguments -Arguments $runArgs -Source $logs -Target '/logs'
        $runArgs.Add($Image)
        Invoke-ContainerCommand -Arguments $runArgs.ToArray()

        # MANIFEST.csv.meta is the SR-038 witness, written beside every manifest by
        # Write-Manifest — not a copied kit artifact, but it must be present in a
        # backup the container produced, or a restore would report an unverified index.
        foreach ($artifact in 'MANIFEST.csv','MANIFEST.csv.meta','RECONSTRUCT.bat','RECONSTRUCT.ps1','reconstruct.sh','FileBackup.Common.psm1','System.IO.Hashing.dll','RECONSTRUCT.paths.json') {
            if (-not (Test-Path -LiteralPath (Join-Path $backup $artifact) -PathType Leaf)) {
                throw "Container smoke test did not produce restore-kit artifact '$artifact'."
            }
        }
        $rows = @(Import-Csv -LiteralPath (Join-Path $backup 'MANIFEST.csv'))
        if ($rows.Count -ne 2) { throw "Expected 2 manifest rows; found $($rows.Count)." }
        if (@($rows | Where-Object Compressed -eq 'Yes').Count -eq 0) {
            throw 'Compression was requested but the smoke manifest has no compressed row.'
        }

        $restoreArgs = [System.Collections.Generic.List[string]]@(
            'run','--rm','--network','none','--read-only',
            '--security-opt','no-new-privileges','--cap-drop','ALL',
            '--tmpfs','/tmp:rw,noexec,nosuid,nodev',
            '--entrypoint','pwsh'
        )
        Add-BindMountArguments -Arguments $restoreArgs -Source $backup -Target '/backup' -ReadOnly
        Add-BindMountArguments -Arguments $restoreArgs -Source $changes -Target '/changes' -ReadOnly
        Add-BindMountArguments -Arguments $restoreArgs -Source $restore -Target '/restore'
        $restoreArgs.Add($Image)
        foreach ($arg in '-NoLogo','-NoProfile','-NonInteractive','-File','/backup/RECONSTRUCT.ps1','-TargetRoot','/restore','-BackupRootOverride','/backup','-ChangeRootOverride','/changes','-SevenZipPath','/usr/bin/7z') {
            $restoreArgs.Add($arg)
        }
        Invoke-ContainerCommand -Arguments $restoreArgs.ToArray()

        foreach ($relativePath in 'alpha.txt','binary.dat') {
            $expected = Join-Path $source $relativePath
            $actual = Join-Path $restore $relativePath
            if (-not (Test-Path -LiteralPath $actual -PathType Leaf)) {
                throw "Restored file '$relativePath' is missing."
            }
            if ((Get-FileHash -LiteralPath $expected -Algorithm SHA256).Hash -ne
                (Get-FileHash -LiteralPath $actual -Algorithm SHA256).Hash) {
                throw "Restored file '$relativePath' differs from its source."
            }
        }
        Write-Host 'Container smoke test passed: compressed backup, restore kit, and byte-exact restore verified.'

        # ---- Incremental run + dated-snapshot restore (SR-005/SR-010, LLR-044) ----
        # Strictly appended after the single-run assertions above so a regression in
        # this block can never mask under an already-passing earlier assertion.
        $sourceGen1 = Join-Path $smokeRoot 'source-gen1'
        $restoreLatest = Join-Path $smokeRoot 'restore-latest'
        $restoreSnapshot = Join-Path $smokeRoot 'restore-snapshot'
        New-Item -ItemType Directory -Path $sourceGen1, $restoreLatest, $restoreSnapshot -Force | Out-Null
        if ($IsLinux -or $IsMacOS) {
            & chmod 0777 $restoreLatest $restoreSnapshot
            if ($LASTEXITCODE -ne 0) { throw 'Could not make incremental smoke-test restore directories writable.' }
        }
        Copy-Item -Path (Join-Path $source '*') -Destination $sourceGen1 -Recurse -Force

        # Mutate the source (change + remove + add) so both NewOrChanged and
        # RemovedFromSource fire and the SR-005 supersession path is exercised.
        [System.IO.File]::WriteAllText((Join-Path $source 'alpha.txt'), ('mutated payload ' * 300))
        Remove-Item -LiteralPath (Join-Path $source 'binary.dat') -Force
        [System.IO.File]::WriteAllText((Join-Path $source 'gamma.txt'), 'added in generation 2')

        # Incremental run: same mounts, same image -- the second container invocation.
        Invoke-ContainerCommand -Arguments $runArgs.ToArray()

        $snapshotDirs = @(Get-ChildItem -LiteralPath $changes -Directory -ErrorAction SilentlyContinue |
            Where-Object Name -match '^Snapshot_\d')
        if ($snapshotDirs.Count -ne 1) {
            throw "Expected exactly one Snapshot_<date> folder under changes after the incremental run; found $($snapshotDirs.Count)."
        }
        $snapshotName = $snapshotDirs[0].Name
        $snapshotPath = $snapshotDirs[0].FullName

        foreach ($kitRoot in @($backup, $snapshotPath)) {
            foreach ($artifact in 'MANIFEST.csv','MANIFEST.csv.meta','RECONSTRUCT.bat','RECONSTRUCT.ps1','reconstruct.sh','FileBackup.Common.psm1','System.IO.Hashing.dll','RECONSTRUCT.paths.json') {
                if (-not (Test-Path -LiteralPath (Join-Path $kitRoot $artifact) -PathType Leaf)) {
                    throw "Incremental smoke test did not produce restore-kit artifact '$artifact' under '$kitRoot'."
                }
            }
        }

        # Restore #1: latest state (/backup), compared against the mutated source.
        $restoreLatestArgs = [System.Collections.Generic.List[string]]@(
            'run','--rm','--network','none','--read-only',
            '--security-opt','no-new-privileges','--cap-drop','ALL',
            '--tmpfs','/tmp:rw,noexec,nosuid,nodev',
            '--entrypoint','pwsh'
        )
        Add-BindMountArguments -Arguments $restoreLatestArgs -Source $backup -Target '/backup' -ReadOnly
        Add-BindMountArguments -Arguments $restoreLatestArgs -Source $changes -Target '/changes' -ReadOnly
        Add-BindMountArguments -Arguments $restoreLatestArgs -Source $restoreLatest -Target '/restore-latest'
        $restoreLatestArgs.Add($Image)
        foreach ($arg in '-NoLogo','-NoProfile','-NonInteractive','-File','/backup/RECONSTRUCT.ps1','-TargetRoot','/restore-latest','-BackupRootOverride','/backup','-ChangeRootOverride','/changes','-SevenZipPath','/usr/bin/7z') {
            $restoreLatestArgs.Add($arg)
        }
        Invoke-ContainerCommand -Arguments $restoreLatestArgs.ToArray()

        foreach ($relativePath in 'alpha.txt','gamma.txt') {
            $expected = Join-Path $source $relativePath
            $actual = Join-Path $restoreLatest $relativePath
            if (-not (Test-Path -LiteralPath $actual -PathType Leaf)) {
                throw "Restored latest-state file '$relativePath' is missing."
            }
            if ((Get-FileHash -LiteralPath $expected -Algorithm SHA256).Hash -ne
                (Get-FileHash -LiteralPath $actual -Algorithm SHA256).Hash) {
                throw "Restored latest-state file '$relativePath' differs from the mutated source."
            }
        }
        if (Test-Path -LiteralPath (Join-Path $restoreLatest 'binary.dat') -PathType Leaf) {
            throw "Restored latest state still contains 'binary.dat', which was removed from the source before the incremental run."
        }

        # Restore #2: the pre-mutation snapshot, restored by invoking RECONSTRUCT.ps1
        # from INSIDE the snapshot folder itself -- the authority folder is wherever the
        # invoked script physically lives, the concrete SR-010 point-in-time proof.
        $restoreSnapshotArgs = [System.Collections.Generic.List[string]]@(
            'run','--rm','--network','none','--read-only',
            '--security-opt','no-new-privileges','--cap-drop','ALL',
            '--tmpfs','/tmp:rw,noexec,nosuid,nodev',
            '--entrypoint','pwsh'
        )
        Add-BindMountArguments -Arguments $restoreSnapshotArgs -Source $backup -Target '/backup' -ReadOnly
        Add-BindMountArguments -Arguments $restoreSnapshotArgs -Source $changes -Target '/changes' -ReadOnly
        Add-BindMountArguments -Arguments $restoreSnapshotArgs -Source $restoreSnapshot -Target '/restore-snapshot'
        $restoreSnapshotArgs.Add($Image)
        foreach ($arg in '-NoLogo','-NoProfile','-NonInteractive','-File',"/changes/$snapshotName/RECONSTRUCT.ps1",'-TargetRoot','/restore-snapshot','-BackupRootOverride','/backup','-ChangeRootOverride','/changes','-SevenZipPath','/usr/bin/7z') {
            $restoreSnapshotArgs.Add($arg)
        }
        Invoke-ContainerCommand -Arguments $restoreSnapshotArgs.ToArray()

        foreach ($relativePath in 'alpha.txt','binary.dat') {
            $expected = Join-Path $sourceGen1 $relativePath
            $actual = Join-Path $restoreSnapshot $relativePath
            if (-not (Test-Path -LiteralPath $actual -PathType Leaf)) {
                throw "Restored snapshot file '$relativePath' is missing."
            }
            if ((Get-FileHash -LiteralPath $expected -Algorithm SHA256).Hash -ne
                (Get-FileHash -LiteralPath $actual -Algorithm SHA256).Hash) {
                throw "Restored snapshot file '$relativePath' differs from the pre-mutation source."
            }
        }
        if (Test-Path -LiteralPath (Join-Path $restoreSnapshot 'gamma.txt') -PathType Leaf) {
            throw "Restored snapshot unexpectedly contains 'gamma.txt', which did not exist at snapshot time."
        }

        Write-Host 'Container smoke test passed: incremental run produced a restorable dated snapshot alongside a byte-exact latest-state restore.'
    }
    finally {
        if (Test-Path -LiteralPath $smokeRoot) {
            Remove-Item -LiteralPath $smokeRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Initialize-ContainerRuntime

switch ($Action) {
    'Build' { Invoke-ImageBuild }
    'Test' { Invoke-ContainerSmokeTest }
    'BuildAndTest' { Invoke-ImageBuild; Invoke-ContainerSmokeTest }
    'Export' {
        if (-not $OutputPath) { $OutputPath = Join-Path $repo '.artifacts\filebackup-image.tar' }
        $OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
        $outputDirectory = [System.IO.Path]::GetDirectoryName($OutputPath)
        if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
        }
        Invoke-ContainerCommand -Arguments @('image','save','--output',$OutputPath,$Image)
        Write-Host "Exported $Image to $OutputPath"
    }
    'Publish' {
        if ([string]::IsNullOrWhiteSpace($RegistryImage)) {
            throw '-RegistryImage is required for Publish.'
        }
        Invoke-ContainerCommand -Arguments @('image','tag',$Image,$RegistryImage)
        Invoke-ContainerCommand -Arguments @('image','push',$RegistryImage)
        Write-Host "Published $RegistryImage"
    }
    'Pull' {
        if ([string]::IsNullOrWhiteSpace($RegistryImage)) {
            throw '-RegistryImage is required for Pull.'
        }
        Invoke-ContainerCommand -Arguments @('image','pull',$RegistryImage)
        Invoke-ContainerCommand -Arguments @('image','tag',$RegistryImage,$Image)
        Write-Host "Pulled $RegistryImage and tagged it locally as $Image"
    }
    'Load' {
        if (-not $OutputPath) { $OutputPath = Join-Path $repo '.artifacts\filebackup-image.tar' }
        $OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
        Invoke-ContainerCommand -Arguments @('load','--input',$OutputPath)
        Write-Host "Loaded image from $OutputPath"
    }
}
