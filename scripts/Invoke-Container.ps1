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
        ConfigVersion = 2
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
    foreach ($file in @(Get-ChildItem -LiteralPath $Backup, $Changes -File -Recurse -Force)) {
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
    foreach ($file in @(Get-ChildItem -LiteralPath $Backup, $Changes -File -Recurse -Force)) {
        $now = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        if ($before[$file.FullName] -ne $now) { throw "verify modified '$($file.FullName)'; it must mutate nothing." }
    }

    # --- seed one malformed row: Compressed=Yes over raw bytes ---
    # Selection reads on the HOST (world-readable); every WRITE runs INSIDE
    # the image. Two first-real-CI lessons (runs 32661497480 / 32672263476):
    # the host has no System.IO.Hashing (the witness stamp prompted
    # interactively and aborted), and the store's files belong to the image's
    # uid 65532 — a host-side WriteAllText onto a data file is access-denied
    # on the runner. Write-Manifest also re-stamps the witness, so one
    # in-container command does data file + manifest + witness together.
    $manifestPath = Join-Path $Backup 'MANIFEST.csv'
    $rows = @(Import-Csv -LiteralPath $manifestPath)
    $target = @($rows | Where-Object Compressed -eq 'No')[0]
    if (-not $target) { $target = $rows[0] }
    $seedArgs = [System.Collections.Generic.List[string]]::new()
    $seedArgs.AddRange([string[]]@('run', '--rm', '--entrypoint', 'pwsh'))
    Add-BindMountArguments -Arguments $seedArgs -Source $Backup -Target '/backup'
    $seedArgs.AddRange([string[]]@('--env', "FILEBACKUP_SEED_REL=$($target.RelativePath)"))
    $seedArgs.Add($Image)
    $seedArgs.AddRange([string[]]@('-NoProfile', '-Command', @'
$ErrorActionPreference = 'Stop'
Import-Module /opt/filebackup/Modules/FileBackup.Common.psm1
$rows = @(Read-Manifest -FolderPath /backup)
$t = @($rows | Where-Object RelativePath -eq $env:FILEBACKUP_SEED_REL)[0]
if (-not $t) { throw "seed target '$env:FILEBACKUP_SEED_REL' not found in /backup manifest" }
[System.IO.File]::WriteAllText("/backup/$($t.DataPath)", 'raw bytes that are not an archive')
$t.Compressed = 'Yes'
Write-Manifest -FolderPath /backup -Records $rows
'@))
    Invoke-ContainerCommand -Arguments $seedArgs.ToArray()

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

function New-ProbeFixtureContent {
    <#
    .SYNOPSIS
        Deterministic fixture bytes of one compressibility class, matching the
        TC-225 unit recipes (tests/Unit/CompressProbeWiring.Tests.ps1).
    .DESCRIPTION
        Seeded so the measured ratios are reproducible: random ~1.000, text
        ~0.000, mixed-head ~0.917 (raw, above the 0.90 threshold), mixed-third
        ~0.667 (compress). The seed also rides in the repeated text unit, so two
        text fixtures with different seeds are DIFFERENT content and never
        collapse into one (hash,length) group.
    .PARAMETER Kind
        random | text | mixed-head | mixed-third.
    .PARAMETER Seed
        Fixture seed; distinct per file so every fixture is its own group.
    .PARAMETER Size
        Content length in bytes. Defaults to 1 MiB, comfortably above the
        256 KiB probe floor (SR-081).
    .OUTPUTS
        [byte[]]
    #>
    # Implements: SR-081, LLR-086
    param(
        [Parameter(Mandatory)][ValidateSet('random','text','mixed-head','mixed-third')][string]$Kind,
        [Parameter(Mandatory)][int]$Seed,
        [int]$Size = 1048576
    )
    $rand = { param([int]$n) $bytes = [byte[]]::new($n); [System.Random]::new($Seed).NextBytes($bytes); , $bytes }
    $text = {
        param([int]$n)
        $unit = "The quick brown fox jumps over the lazy dog. COMPRESSIBLE TEXT PAYLOAD $Seed. "
        $builder = [System.Text.StringBuilder]::new()
        while ($builder.Length -lt $n) { [void]$builder.Append($unit) }
        , [System.Text.Encoding]::ASCII.GetBytes($builder.ToString().Substring(0, $n))
    }
    switch ($Kind) {
        'random'      { return (& $rand $Size) }
        'text'        { return (& $text $Size) }
        # 64 KiB of text at the head of an otherwise random file: an ANY-sample
        # rule would send this to -mx=9 whole. Aggregate 0.917 -> raw.
        'mixed-head'  { return ([byte[]]@((& $text 65536)  + (& $rand ($Size - 65536)))) }
        # A third of the file compresses: aggregate 0.667 -> compress.
        'mixed-third' { return ([byte[]]@((& $text 393216) + (& $rand ($Size - 393216)))) }
    }
}

function Test-ContainerCompressProbe {
    <#
    .SYNOPSIS
        TC-230: TC-225's compressibility-probe arms re-run INSIDE the image on
        the Linux stack, mode always (the shipped default), with the SR-081 set
        summary and the wall-clock cost of the first run captured.
    .DESCRIPTION
        Linux is where the defect was measured, so the fix is proven there. Ten
        fixtures of known content classes are backed up by the container's own
        backup action; the manifest must show the bytes overruling the extension
        list in both directions (an unlisted .qqq of random bytes stored RAW, a
        LISTED .zip of text bytes stored .7z), the storage-form agreement
        (I-1: a .7z filename extension iff Compressed=Yes) must hold for EVERY
        row, and the three per-set counter lines must account for exactly the
        probe-decided objects. The first-run cost is REPORTED, not asserted
        against a budget: 'Probe reads' bytes plus the wall clock of the run,
        the operator's cost figure (plan section 2.5). Finally the store is
        restored in a second container with the bundled RECONSTRUCT.ps1 and
        every fixture compared byte-for-byte, so both stored forms are proven
        restorable on Linux.

        This check owns its OWN store: it must not disturb the smoke store's
        row-count and snapshot expectations.
    .PARAMETER Image
        Local image reference to run.
    .PARAMETER Root
        Scratch root (the smoke root); this check builds its own tree beneath it.
    .OUTPUTS
        None. Throws on any failed assertion.
    #>
    # Implements: SR-081, LLR-086
    param(
        [Parameter(Mandatory)][string]$Image,
        [Parameter(Mandatory)][string]$Root
    )
    $probeRoot = Join-Path $Root 'probe'
    $source    = Join-Path $probeRoot 'source'
    $config    = Join-Path $probeRoot 'config'
    $state     = Join-Path $probeRoot 'state'
    $backup    = Join-Path $probeRoot 'backup'
    $changes   = Join-Path $probeRoot 'changes'
    $logs      = Join-Path $probeRoot 'logs'
    $restore   = Join-Path $probeRoot 'restore'
    $folders   = @($probeRoot,$source,$config,$state,$backup,$changes,$logs,$restore)
    New-Item -ItemType Directory -Path $folders -Force | Out-Null
    if ($IsLinux -or $IsMacOS) {
        & chmod 0777 @folders
        if ($LASTEXITCODE -ne 0) { throw 'Could not make the TC-230 bind directories writable.' }
    }

    # The TC-225 matrix as files. Probed = above the 256 KiB floor, so the probe
    # (not the extension list) decides and the object lands in the counters.
    $fixtures = @(
        [pscustomobject]@{ Name = 'random.qqq';     Kind = 'random';      Seed = 101; Size = 1048576; Ext = '.qqq';  Compressed = 'No';  Probed = $true }
        [pscustomobject]@{ Name = 'text.qqq';       Kind = 'text';        Seed = 102; Size = 1048576; Ext = '.7z';   Compressed = 'Yes'; Probed = $true }
        [pscustomobject]@{ Name = 'noext';          Kind = 'text';        Seed = 103; Size = 1048576; Ext = '.7z';   Compressed = 'Yes'; Probed = $true }
        [pscustomobject]@{ Name = 'mixedhead.qqq';  Kind = 'mixed-head';  Seed = 104; Size = 1048576; Ext = '.qqq';  Compressed = 'No';  Probed = $true }
        [pscustomobject]@{ Name = 'mixedthird.qqq'; Kind = 'mixed-third'; Seed = 105; Size = 1048576; Ext = '.7z';   Compressed = 'Yes'; Probed = $true }
        # LISTED extensions: above the floor under 'always' the list is not
        # consulted at all, so the bytes decide in BOTH directions.
        [pscustomobject]@{ Name = 'textzip.zip';    Kind = 'text';        Seed = 106; Size = 1048576; Ext = '.7z';   Compressed = 'Yes'; Probed = $true }
        [pscustomobject]@{ Name = 'randomzip.zip';  Kind = 'random';      Seed = 107; Size = 1048576; Ext = '.zip';  Compressed = 'No';  Probed = $true }
        # The Q7 pins: no name-based override survives the measurement.
        [pscustomobject]@{ Name = 'paper.docx';     Kind = 'random';      Seed = 108; Size = 1048576; Ext = '.docx'; Compressed = 'No';  Probed = $true }
        [pscustomobject]@{ Name = 'photo.jpg';      Kind = 'text';        Seed = 109; Size = 1048576; Ext = '.7z';   Compressed = 'Yes'; Probed = $true }
        # Below the floor: BelowFloor, decided by the list, counted in neither
        # of the two object counters.
        [pscustomobject]@{ Name = 'small.txt';      Kind = 'text';        Seed = 110; Size = 4096;    Ext = '.7z';   Compressed = 'Yes'; Probed = $false }
    )
    foreach ($fixture in $fixtures) {
        [System.IO.File]::WriteAllBytes((Join-Path $source $fixture.Name),
            (New-ProbeFixtureContent -Kind $fixture.Kind -Seed $fixture.Seed -Size $fixture.Size))
    }

    # CompressProbe is ABSENT: this run proves the SHIPPED DEFAULT is 'always'.
    $set = [ordered]@{
        Name = 'ContainerProbe'
        SourcePath = '/source'
        SourceStatePath = '/state'
        BackupPath = '/backup'
        ChangePath = '/changes'
        HashRecalcFreq = 'N'
        CompressEnabled = $true
        AllowEmptySource = $false
    }
    $configFile = Join-Path $config 'FileBackup.json'
    [ordered]@{ ConfigVersion = 2; Tools = [ordered]@{ SevenZipPath = '/usr/bin/7z' }; BackupSets = @($set) } |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $configFile -Encoding UTF8

    # The explicit spelling of that same default must be schema-valid too.
    $schemaPath = Join-Path $repo 'container/FileBackup.schema.json'
    $explicitSet = [ordered]@{}
    foreach ($key in $set.Keys) { $explicitSet[$key] = $set[$key] }
    $explicitSet['CompressProbe'] = 'always'
    $explicit = [ordered]@{ ConfigVersion = 2; Tools = [ordered]@{ SevenZipPath = '/usr/bin/7z' }
                            BackupSets = @($explicitSet) } | ConvertTo-Json -Depth 5
    # The verdict is computed inside the try and JUDGED outside it: a `throw`
    # in the try would be caught by its own catch and downgraded to "skipped".
    $schemaValid = $null
    if (Test-Path -LiteralPath $schemaPath -PathType Leaf) {
        try {
            $schemaValid = [bool](Test-Json -Json $explicit -Schema (Get-Content -LiteralPath $schemaPath -Raw) -ErrorAction SilentlyContinue)
        } catch {
            $schemaValid = $null
            Write-Host "TC-230: schema validation of the explicit mode skipped ($($_.Exception.Message))."
        }
    }
    if ($null -ne $schemaValid -and -not $schemaValid) {
        throw 'TC-230: an explicit "CompressProbe": "always" configuration failed the published schema.'
    }
    $schemaChecked = ($schemaValid -eq $true)

    # --- the run itself, wall-clock timed: the operator's first-run cost ---
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $run = Invoke-ContainerAction -Image $Image -Word 'backup' -ConfigPath $configFile `
        -Source $source -State $state -Backup $backup -Changes $changes -Logs $logs
    $stopwatch.Stop()
    if ($run.Code -ne 0) { throw "TC-230 backup exited $($run.Code); expected 0.`n$($run.Output)" }

    # --- manifest: the per-fixture stored form, then I-1 over every row ---
    $rows = @(Import-Csv -LiteralPath (Join-Path $backup 'MANIFEST.csv'))
    if ($rows.Count -ne $fixtures.Count) {
        throw "TC-230 expected $($fixtures.Count) manifest rows; found $($rows.Count)."
    }
    $byPath = @{}
    foreach ($row in $rows) { $byPath[$row.RelativePath] = $row }
    foreach ($fixture in $fixtures) {
        $row = $byPath[$fixture.Name]
        if (-not $row) { throw "TC-230: '$($fixture.Name)' has no manifest row." }
        $actualExt = [System.IO.Path]::GetExtension($row.DataPath)
        if ($actualExt -ne $fixture.Ext) {
            throw "TC-230: '$($fixture.Name)' ($($fixture.Kind)) stored as '$($row.DataPath)'; expected extension '$($fixture.Ext)'."
        }
        if ($row.Compressed -ne $fixture.Compressed) {
            throw "TC-230: '$($fixture.Name)' ($($fixture.Kind)) has Compressed=$($row.Compressed); expected $($fixture.Compressed)."
        }
    }
    foreach ($row in $rows) {
        $isArchive = ([System.IO.Path]::GetExtension($row.DataPath) -eq '.7z')
        if ($isArchive -ne ($row.Compressed -eq 'Yes')) {
            throw "TC-230: storage-form disagreement (I-1) on '$($row.RelativePath)': DataPath '$($row.DataPath)' vs Compressed=$($row.Compressed)."
        }
    }

    # --- telemetry: the three SR-081 counter lines from the set's own log ---
    # The set logger (New-Logger, over <ChangePath>/backup.log) both appends to
    # that file and echoes to stdout, so the log file is the primary source and
    # the captured run output the fallback.
    $setLog = Join-Path $changes 'backup.log'
    $globalLog = Join-Path $logs 'Backup_Global.log'
    $telemetryPath = $null
    $text = $null
    foreach ($candidate in @($setLog, $globalLog)) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $content = Get-Content -LiteralPath $candidate -Raw
            if ($content -match 'Probe reads:') {
                $telemetryPath = $candidate
                $text = $content
                break
            }
        }
    }
    if (-not $text) { $telemetryPath = '<container stdout>'; $text = $run.Output }

    $rawMatch        = [regex]::Match($text, 'Probe stored raw: (\d+) objects, (\d+) bytes')
    $compressedMatch = [regex]::Match($text, 'Probe compressed: (\d+)')
    $readsMatch      = [regex]::Match($text, 'Probe reads: (\d+) bytes')
    foreach ($pair in @(@('Probe stored raw', $rawMatch), @('Probe compressed', $compressedMatch), @('Probe reads', $readsMatch))) {
        if (-not $pair[1].Success) { throw "TC-230: the set summary line '$($pair[0])' was not found in $telemetryPath." }
    }
    $rawObjects        = [long]$rawMatch.Groups[1].Value
    $rawBytes          = [long]$rawMatch.Groups[2].Value
    $compressedObjects = [long]$compressedMatch.Groups[1].Value
    $readBytes         = [long]$readsMatch.Groups[1].Value

    $probedCount = @($fixtures | Where-Object Probed).Count
    $expectedRaw = @($fixtures | Where-Object { $_.Probed -and $_.Compressed -eq 'No' }).Count
    $expectedCompressed = $probedCount - $expectedRaw
    if ($rawObjects -ne $expectedRaw) {
        throw "TC-230: 'Probe stored raw' counted $rawObjects objects; the expected decisions give $expectedRaw."
    }
    if ($compressedObjects -ne $expectedCompressed) {
        throw "TC-230: 'Probe compressed' counted $compressedObjects; the expected decisions give $expectedCompressed."
    }
    if (($rawObjects + $compressedObjects) -ne $probedCount) {
        throw "TC-230: the counters account for $($rawObjects + $compressedObjects) objects; $probedCount fixtures are above the floor."
    }
    # At most three 256 KiB windows per probed group, and the probe really ran.
    $readCeiling = $probedCount * 786432
    if ($readBytes -le 0) { throw "TC-230: 'Probe reads' is $readBytes bytes; the probe must have read something." }
    if ($readBytes -gt $readCeiling) {
        throw "TC-230: 'Probe reads' is $readBytes bytes, above the $readCeiling-byte ceiling of $probedCount groups x 3 x 256 KiB."
    }

    # One compress-decision line per WRITTEN group, none of them a fallback.
    $decisionLines = @(($text -split "\r?\n") | Where-Object { $_ -match 'compress-decision:' })
    if ($decisionLines.Count -ne $fixtures.Count) {
        throw "TC-230: found $($decisionLines.Count) compress-decision lines; expected one per written group ($($fixtures.Count))."
    }
    $unavailable = @($decisionLines | Where-Object { $_ -match 'ProbeUnavailable' })
    if ($unavailable.Count -ne 0) {
        throw "TC-230: $($unavailable.Count) compress-decision line(s) report ProbeUnavailable; every fixture is readable."
    }

    # --- both stored forms restore byte-exact, in a second container ---
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
    foreach ($fixture in $fixtures) {
        $expected = Join-Path $source $fixture.Name
        $actual = Join-Path $restore $fixture.Name
        if (-not (Test-Path -LiteralPath $actual -PathType Leaf)) {
            throw "TC-230: restored file '$($fixture.Name)' is missing."
        }
        if ((Get-FileHash -LiteralPath $expected -Algorithm SHA256).Hash -ne
            (Get-FileHash -LiteralPath $actual -Algorithm SHA256).Hash) {
            throw "TC-230: restored file '$($fixture.Name)' differs from its source."
        }
    }

    $runtimeVersion = (& $script:ContainerRuntime 'version' '--format' '{{.Server.Version}}' 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $runtimeVersion) { $runtimeVersion = 'unknown' }
    $schemaNote = if ($schemaChecked) { 'explicit mode schema-valid' } else { 'explicit-mode schema check skipped' }
    Write-Host ("Container compressibility-probe check passed (TC-230): $($rows.Count) rows, $probedCount probed; " +
        "Probe stored raw: $rawObjects objects, $rawBytes bytes; Probe compressed: $compressedObjects; " +
        "Probe reads: $readBytes bytes; backup wall time: $([math]::Round($stopwatch.Elapsed.TotalSeconds, 2)) s; " +
        "restored byte-exact: $($fixtures.Count)/$($fixtures.Count); telemetry from $telemetryPath; $schemaNote; " +
        "image: $Image; runtime: $script:ContainerRuntime $runtimeVersion.")
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
        foreach ($artifact in 'MANIFEST.csv','MANIFEST.csv.meta','RECONSTRUCT.cmd','RECONSTRUCT.command','RECONSTRUCT.ps1','reconstruct.sh','FileBackup.Common.psm1','System.IO.Hashing.dll','RECONSTRUCT.paths.json') {
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

        # -Force (SR-057): a hidden snapshot folder must not escape this count.
        $snapshotDirs = @(Get-ChildItem -LiteralPath $changes -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object Name -match '^Snapshot_\d')
        if ($snapshotDirs.Count -ne 1) {
            throw "Expected exactly one Snapshot_<date> folder under changes after the incremental run; found $($snapshotDirs.Count)."
        }
        $snapshotName = $snapshotDirs[0].Name
        $snapshotPath = $snapshotDirs[0].FullName

        foreach ($kitRoot in @($backup, $snapshotPath)) {
            foreach ($artifact in 'MANIFEST.csv','MANIFEST.csv.meta','RECONSTRUCT.cmd','RECONSTRUCT.command','RECONSTRUCT.ps1','reconstruct.sh','FileBackup.Common.psm1','System.IO.Hashing.dll','RECONSTRUCT.paths.json') {
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

        Test-ContainerCompressProbe -Image $Image -Root $smokeRoot
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
