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

function Invoke-ContainerAction {
    <#
    .SYNOPSIS
        Runs one entrypoint ACTION word against the smoke store and returns its
        exit status and stdout, WITHOUT throwing on a non-zero code — verify
        reports findings as status 1, which is an expected outcome (SR-040).
    .PARAMETER Word
        The entrypoint's positional action word (backup, prune, snapshots, verify).
    .PARAMETER Environment
        Extra 'NAME=value' pairs passed with -e.
    .OUTPUTS
        [pscustomobject] Code, Output.
    #>
    # Implements: SR-049, SR-048, SR-043, LLR-049
    param(
        [Parameter(Mandatory)][string]$Image,
        [Parameter(Mandatory)][string]$Word,
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$State,
        [Parameter(Mandatory)][string]$Backup,
        [Parameter(Mandatory)][string]$Changes,
        [Parameter(Mandatory)][string]$Logs,
        [string[]]$Environment = @()
    )
    $runArgs = [System.Collections.Generic.List[string]]@(
        'run','--rm','--network','none','--read-only',
        '--security-opt','no-new-privileges','--cap-drop','ALL',
        '--tmpfs','/tmp:rw,noexec,nosuid,nodev'
    )
    foreach ($pair in $Environment) { $runArgs.Add('-e'); $runArgs.Add($pair) }
    Add-BindMountArguments -Arguments $runArgs -Source $ConfigPath -Target '/config/FileBackup.json' -ReadOnly
    Add-BindMountArguments -Arguments $runArgs -Source $Source  -Target '/source' -ReadOnly
    Add-BindMountArguments -Arguments $runArgs -Source $State   -Target '/state'
    Add-BindMountArguments -Arguments $runArgs -Source $Backup  -Target '/backup'
    Add-BindMountArguments -Arguments $runArgs -Source $Changes -Target '/changes'
    Add-BindMountArguments -Arguments $runArgs -Source $Logs    -Target '/logs'
    $runArgs.Add($Image)
    $runArgs.Add($Word)
    $output = & $script:ContainerRuntime @($runArgs.ToArray()) 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Output = $output }
}

function Test-ContainerStorageForm {
    <#
    .SYNOPSIS
        TC-102: the storage-form verification action, exercised in-container
        against the smoke store (SR-049, SR-048).
    .DESCRIPTION
        Proves, on a real Linux container: a clean backup verifies with exit 0,
        emits parseable JSON and modifies nothing; a seeded malformed row is
        reported with a non-zero status per the SR-040 table; repair mode fixes
        it and a re-verify exits 0. The default backup action and flags-only
        invocations are unaffected (they are exercised by the steps above).
    #>
    # Implements: SR-049, SR-048, SR-043, LLR-049
    param(
        [Parameter(Mandatory)][string]$Image,
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$State,
        [Parameter(Mandatory)][string]$Backup,
        [Parameter(Mandatory)][string]$Changes,
        [Parameter(Mandatory)][string]$Logs
    )
    $common = @{ Image = $Image; ConfigPath = $ConfigPath; Source = $Source; State = $State
                 Backup = $Backup; Changes = $Changes; Logs = $Logs }

    # --- clean store: exit 0, parseable JSON, nothing modified ---
    $before = @{}
    foreach ($file in @(Get-ChildItem -LiteralPath $Backup, $Changes -File -Recurse)) {
        $before[$file.FullName] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
    $clean = Invoke-ContainerAction @common -Word 'verify'
    if ($clean.Code -ne 0) { throw "verify on a clean store exited $($clean.Code); expected 0.`n$($clean.Output)" }
    # The document shares stdout with timestamped log lines, so take it by
    # LINE: ConvertTo-Json opens with a line that IS '[' and closes with one
    # that IS ']', or the whole clean-store document is the single line '[]'.
    # A greedy '\[.*\]' here ran from the document into the '[INFO]' tag of a
    # later log line and handed ConvertFrom-Json trailing garbage.
    $lines = $clean.Output -split "\r?\n"
    $json = if ($lines -contains '[]') { '[]' } else {
        $start = [array]::IndexOf($lines, '[')
        $end   = [array]::IndexOf($lines, ']')
        if ($start -ge 0 -and $end -gt $start) { $lines[$start..$end] -join "`n" } else { '' }
    }
    if (-not $json) { throw "verify did not emit a JSON findings document.`n$($clean.Output)" }
    try { ConvertFrom-Json $json | Out-Null } catch { throw "verify's findings document is not parseable JSON: $($_.Exception.Message)" }
    foreach ($file in @(Get-ChildItem -LiteralPath $Backup, $Changes -File -Recurse)) {
        $now = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        if ($before[$file.FullName] -ne $now) { throw "verify modified '$($file.FullName)'; it must mutate nothing." }
    }

    # --- seed one malformed row: Compressed=Yes over raw bytes ---
    $manifestPath = Join-Path $Backup 'MANIFEST.csv'
    $rows = @(Import-Csv -LiteralPath $manifestPath)
    $target = @($rows | Where-Object Compressed -eq 'No')[0]
    if (-not $target) { $target = $rows[0] }
    $dataFile = Join-Path $Backup $target.DataPath
    [System.IO.File]::WriteAllText($dataFile, 'raw bytes that are not an archive')
    $target.Compressed = 'Yes'
    $rows | Export-Csv -LiteralPath $manifestPath -NoTypeInformation
    # Re-stamp the witness INSIDE the image, never on the host: the image
    # bakes System.IO.Hashing; ubuntu-latest does not, and the host-side
    # Import-Module route prompted interactively for the DLL and aborted the
    # first real CI run of this job (2026-08-23, run 32661497480).
    $stampArgs = [System.Collections.Generic.List[string]]::new()
    $stampArgs.AddRange([string[]]@('run', '--rm', '--entrypoint', 'pwsh'))
    Add-BindMountArguments -Arguments $stampArgs -Source $Backup -Target '/backup'
    $stampArgs.Add($Image)
    $stampArgs.AddRange([string[]]@('-NoProfile', '-Command',
        'Import-Module /opt/filebackup/Modules/FileBackup.Common.psm1; Write-ManifestWitness -FolderPath /backup | Out-Null'))
    Invoke-ContainerCommand -Arguments $stampArgs.ToArray()

    $dirty = Invoke-ContainerAction @common -Word 'verify'
    if ($dirty.Code -eq 0) { throw "verify reported a seeded malformed row as clean.`n$($dirty.Output)" }
    if ($dirty.Code -ne 1) { throw "verify exited $($dirty.Code) for a findings outcome; the SR-040 table says 1.`n$($dirty.Output)" }

    # --- repair, then re-verify clean ---
    $repair = Invoke-ContainerAction @common -Word 'verify' -Environment @('FILEBACKUP_REPAIR=1')
    if ($repair.Code -ne 0) { throw "verify --repair exited $($repair.Code); expected 0 after repairing.`n$($repair.Output)" }
    $again = Invoke-ContainerAction @common -Word 'verify'
    if ($again.Code -ne 0) { throw "re-verify after repair exited $($again.Code); expected 0.`n$($again.Output)" }

    Write-Host 'Container storage-form check passed (TC-102): clean verify exits 0 and mutates nothing, a malformed row exits 1, repair makes it clean.'
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

        Test-ContainerStorageForm -Image $Image -ConfigPath (Join-Path $config 'FileBackup.json') `
            -Source $source -State $state -Backup $backup -Changes $changes -Logs $logs

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
