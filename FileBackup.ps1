<#
.SYNOPSIS
    Periodic content-aware backup with change tracking and reconstruct scripts.

.DESCRIPTION
    Thin entry point. All logic lives in the modules under .\Modules:
        * FileBackup.Common.psm1  - restore-safe primitives (hashing, manifest I/O,
                                     7-Zip, short-name encoding, logging). This file
                                     is bundled into every backup folder.
        * FileBackup.Engine.psm1  - the backup engine (source walk, diff, dedup copy,
                                     storage-layout migration, change folders,
                                     reconstruct generation, Invoke-BackupSet).

    For each backup set, per run, the engine:
        * Updates the source MANIFEST.csv (hashing new/changed/scheduled files).
        * Migrates backup storage to the current compress / tree-mode config.
        * Diffs source vs backup, copies new data (deduped by xxHash128 + length),
          and evicts removed files' previous data into a staging folder.
        * Renames staging to a dated  Snapshot_<date>  point-in-time folder (only
          when something was superseded; the latest state is the live backup) and drops a
          self-contained RECONSTRUCT.ps1 / .bat and reconstruct.sh (plus the Common module + xxHash
          DLL) into the backup and change folders.
        * Optionally emails success/failure.

.PARAMETER ConfigPath
    CLIXML or JSON config (default: $HOME\BackupConfig.xml). The format is
    selected from the .xml/.json extension and loaded/validated by
    Import-BackupConfiguration (SR-042).

    JSON is the documented, VERSIONED contract (container/FileBackup.schema.json
    is the published, documentation-only mirror) -- a required integer
    ConfigVersion (currently 1), a closed schema (any key it doesn't recognize
    aborts the run naming that key and its JSON path), JSON-typed booleans for
    CompressEnabled/PreserveFolderTree (a quoted "false" is rejected, never
    coerced true), and no Secrets.Credential (JSON cannot carry a
    PSCredential; use CLIXML, or run with -NoMail as containers do):

        {
          "ConfigVersion": 1,
          "Tools": { "SevenZipPath": "/usr/bin/7z" },
          "BackupSets": [{
            "Name": "MainData",
            "SourcePath": "/source",
            "SourceStatePath": "/state",
            "BackupPath": "/backup",
            "ChangePath": "/changes",
            "HashRecalcFreq": "W",
            "CompressEnabled": true,
            "PreserveFolderTree": false
          }]
        }

    CLIXML is the unversioned LEGACY native-Windows form -- exempt from
    ConfigVersion, the closed schema, and the Credential ban (it is the only
    format that can carry a real PSCredential):

        @{
            Secrets = @{
                ToEmail    = 'you@example.com'
                FromEmail  = 'backup@example.com'
                SmtpServer = 'smtp.server'
                SmtpPort   = 587
                Credential = <PSCredential>
            }
            BackupSets = @(
                [pscustomobject]@{
                    Name               = 'MainData'
                    SourcePath         = 'D:\Data'
                    SourceStatePath    = 'E:\Backups\SourceState' # optional; required for read-only container sources
                    BackupPath         = 'E:\Backups\DataStore'
                    ChangePath         = 'E:\Backups\DataChanges'
                    HashRecalcFreq     = 'W'      # A/E/D/W/M/Y/N
                    CompressEnabled    = $true
                    PreserveFolderTree = $false   # $true mirrors the tree; $false uses <hash> <size> names
                    AllowEmptySource   = $false   # opt in to an intentional delete-all
                }
            )
        } | Export-Clixml -LiteralPath "$HOME\BackupConfig.xml"

    Both formats accept multiple BackupSets and process every one; IF-001
    rules ONE BackupSet per container invocation (HomeHub deploys one
    service/directory), so a JSON config with more than one set logs a WARN
    naming the count instead of failing -- it is a legitimate native-Windows
    use, just outside the container contract.

.PARAMETER Action
    Backup (default), Prune or Snapshots (SR-048).

        Backup     — the normal run described above; unchanged.
        Snapshots  — print the read-only snapshot inventory as JSON: Name, Date,
                     Rows, PhysicalBytes, BytesReclaimed, BytesReHomed. The
                     reclaim figures are dedup-aware, so they are what removing
                     that snapshot would ACTUALLY free.
        Prune      — remove the snapshot(s) named by -Snapshot, re-homing any
                     content whose only physical copy they hold into the
                     surviving pool first. Add -WhatIf for a dry run that
                     reports exactly what the real run would achieve.

    Retention POLICY (what to keep) belongs to the caller — IF-001 rules that
    HomeHub decides and FileBackup removes; there is deliberately no
    -KeepLast/-OlderThan and no wildcard.

.PARAMETER Snapshot
    Snapshot folder name(s) for -Action Prune, e.g.
    Snapshot_2026_01_02_03_04_05. Several may be given, or one
    comma-separated string (what the container passes). Each is an independent
    transaction; the process status is the worst by the SR-040 precedence
    2 > 3 > 4 > 1.

.PARAMETER GlobalLogPath
    Optional path for dependency and cross-set messages. Defaults to
    FILEBACKUP_LOG_PATH when set, otherwise Backup_Global.log beside the config.
    Containers should mount a writable log directory and pass this explicitly.

.PARAMETER NoMail
    Skip the success/failure email even if SMTP details are present.

.PARAMETER NonInteractive
    Never prompt — for scheduled/unattended runs. Missing optional tools degrade
    silently; a missing required hashing package fails loudly (non-zero exit)
    unless -AutoInstallDeps is set. Implements: SR-016.

.PARAMETER AutoInstallDeps
    With -NonInteractive, install the missing System.IO.Hashing package
    automatically instead of failing.

.PARAMETER ExitCode
    Report outcome through a process exit code (SR-043) instead of only a
    terminating error: 0 complete, 1 one or more backup sets failed, 2 the
    configuration could not be loaded or violates SR-042 -- the same
    usage/precondition class the restorers use (README "Restore exit codes").
    Only process entry points should pass this (container/entrypoint.sh does);
    an in-process caller that passes it will terminate its own session on
    `exit`, so leave it off for interactive/scripted in-process use.

.NOTES
    Requires PowerShell 7+ (pwsh). Dependencies:
        - System.IO.Hashing (NuGet) for xxHash128  - installed on first use / by tests\Setup.ps1.
        - 7-Zip on PATH, at %ProgramFiles%\7-Zip\7z.exe, or configured through
          Tools.SevenZipPath / FILEBACKUP_7ZIP_PATH when compression is enabled.
        - ffprobe on PATH or configured through Tools.FfprobePath /
          FILEBACKUP_FFPROBE_PATH for media metrics (optional).

    Entry-point status codes (SR-043; container/entrypoint.sh passes -ExitCode):

        0  Complete — every backup set succeeded.
        1  One or more backup sets failed.
        2  The configuration could not be loaded -- the file is missing or
           unreadable, or it violates the SR-042 schema (missing/unrecognized
           ConfigVersion, unknown key, wrong JSON type, Secrets.Credential in
           JSON, etc.). Nothing was attempted and NOTHING was created: a
           refused run makes no log directory and never truncates the previous
           run's global log.

    Under -Action Prune / -Action Snapshots the status is the SR-040 restore
    table instead (README "Restore exit codes"): 0 pruned, 1 batch incomplete
    but NO DATA LOST, 2 usage or precondition (nothing mutated), 3 manifest
    witness verification failed (nothing mutated), 4 host I/O, retriable and
    aborted before the commit point — precedence 2 > 3 > 4 > 1.

    Without -ExitCode, a configuration failure is a terminating error (throw)
    and a failed set still yields a non-zero exit via the normal PowerShell
    unhandled-error path — unchanged from before SR-042/SR-043.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ConfigPath = "$HOME\BackupConfig.xml",
    # What this invocation does (SR-048). Backup is the default and is unchanged
    # by WP4; Prune removes named snapshots through the retention mechanism and
    # Snapshots prints the read-only inventory as JSON. Retention POLICY belongs
    # to the wrapper (IF-001) -- this entry point only takes explicit names.
    [ValidateSet('Backup', 'Prune', 'Snapshots')][string]$Action = 'Backup',
    # Snapshot folder name(s) for -Action Prune. A single comma-separated value
    # is split, because `pwsh -File` passes every argument as one literal string.
    [string[]]$Snapshot,
    [string]$GlobalLogPath = $env:FILEBACKUP_LOG_PATH,
    [switch]$NoMail,
    [switch]$NonInteractive,
    [switch]$AutoInstallDeps,
    # Testing/automation seam (SR-005): pins this run's completion date, which dates
    # the NEXT run's snapshot. Omit in normal use to date by the real clock.
    [datetime]$BackupTime,
    # Report outcome as a process exit code (SR-043): 0 complete, 1 a backup set
    # failed, 2 the configuration could not be loaded / violates SR-042 -- the
    # same usage/precondition class the restorers use. Only process entry points
    # (container/entrypoint.sh) should pass this; in-process callers keep the
    # terminating-error behavior below.
    [switch]$ExitCode
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Modules\FileBackup.Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Modules\FileBackup.Engine.psm1') -Force

# Where the global log WILL live. Computing the path needs no filesystem
# mutation, and none happens here: a refused configuration must leave the disk
# exactly as it found it (SR-042/SR-043), so neither the directory nor the log
# file is created until the configuration has passed validation. New-Logger
# truncates (New-Item -Force), so creating it any earlier would destroy the
# previous run's log on a config typo.
$globalLogPath = if ($GlobalLogPath) {
    $GlobalLogPath
} else {
    Join-Path ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($ConfigPath))) 'Backup_Global.log'
}

# Config-time messages are buffered and flushed once the log file exists (the
# same pattern Reconstruct.ps1 uses for its pre-target lines).
$pendingLogLines = New-Object System.Collections.Generic.List[object]
$bufferLog = {
    param([string]$Message, [string]$Level = 'INFO')
    $pendingLogLines.Add([pscustomobject]@{ Message = $Message; Level = $Level })
}.GetNewClosure()

function Exit-ConfigFailure {
    <#
    .SYNOPSIS
        Reports a configuration failure at the FileBackup.ps1 process boundary.
    .DESCRIPTION
        Covers every way the configuration can be unusable -- the file being
        missing (the likeliest container misconfiguration) as well as an
        SR-042 schema violation. Writes the failure to stderr, then either
        exits the process with 2 (SR-043's usage/precondition class, so
        NagLight can tell "retrying will not help" from "the backup failed")
        when -ExitCode was passed, or rethrows -- preserving the
        terminating-error behavior that tests/Unit/Engine.Tests.ps1 and the
        test harness rely on.

        Creates NO artifacts: the message is appended to the global log only if
        that file already exists, so a refused run never creates a log
        directory and never truncates the previous run's log.
    .PARAMETER Message
        The operator-facing reason. SR-042's loader already names the
        offending key/JSON path; wording is otherwise unchanged from before
        WP2 for the checks it preserves verbatim.
    #>
    # Implements: SR-043, LLR-043
    param([Parameter(Mandatory)][string]$Message)
    [Console]::Error.WriteLine("FileBackup: $Message")
    if (Test-Path -LiteralPath $globalLogPath -PathType Leaf) {
        Add-Content -LiteralPath $globalLogPath -Value ("{0} [ERROR] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Message)
    }
    if ($ExitCode) {
        exit 2
    }
    throw $Message
}

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    Exit-ConfigFailure -Message "Config file '$ConfigPath' not found."
}
$ConfigPath = (Resolve-Path -LiteralPath $ConfigPath).Path

try {
    $cfgResult = Import-BackupConfiguration -Path $ConfigPath -Log $bufferLog
} catch {
    Exit-ConfigFailure -Message $_.Exception.Message
}
$Secrets = $cfgResult.Secrets
$Sets    = $cfgResult.Sets

# The configuration is good: now the run may create artifacts.
$globalLogDirectory = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($globalLogPath))
if (-not (Test-Path -LiteralPath $globalLogDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $globalLogDirectory -Force | Out-Null
}
$globalLog = New-Logger -LogFile $globalLogPath
foreach ($line in $pendingLogLines) { & $globalLog $line.Message $line.Level }

$anyCompress = $false
$anyMedia    = $false
foreach ($s in $Sets) {
    if ($s.CompressEnabled) { $anyCompress = $true }
    # Set $anyMedia = $true here if you want ffprobe metrics for every set.
}

$dependencyParams = @{
    AnyCompressionNeeded  = $anyCompress
    AnyMediaMetricsNeeded = $anyMedia
    Log                   = $globalLog
    NonInteractive        = $NonInteractive
    AutoInstall           = $AutoInstallDeps
}
if ($cfgResult.Tools -and $null -ne $cfgResult.Tools.SevenZipPath) {
    $dependencyParams['SevenZipPath'] = [string]$cfgResult.Tools.SevenZipPath
}
if ($cfgResult.Tools -and $null -ne $cfgResult.Tools.FfprobePath) {
    $dependencyParams['FfprobePath'] = [string]$cfgResult.Tools.FfprobePath
}
$deps = Initialize-Dependencies @dependencyParams

function Invoke-RetentionAction {
    <#
    .SYNOPSIS
        Runs the -Action Prune / -Action Snapshots half of the entry point and
        returns its SR-040 process code (SR-048).
    .DESCRIPTION
        Retention is a one-shot invocation against ONE configured set (IF-001's
        one-set-per-invocation ruling), so the set is resolved here rather than
        looped. Prune passes -WhatIf straight through, so a dry run reports what
        the real run would achieve without mutating anything.
    .PARAMETER Set
        The single backup set to act on.
    .PARAMETER Name
        Snapshot names for Prune; see SR-046 for the containment rules.
    .OUTPUTS
        [int] 0/1/2/3/4 per the SR-040 table, precedence 2 > 3 > 4 > 1.
    #>
    # Implements: SR-048, SR-040, LLR-048
    param(
        [Parameter(Mandatory)][pscustomobject]$Set,
        [Parameter(Mandatory)][ValidateSet('Prune', 'Snapshots')][string]$Mode,
        [AllowNull()][string[]]$Name,
        [Parameter(Mandatory)][hashtable]$Deps,
        [Parameter(Mandatory)][scriptblock]$Log,
        [switch]$DryRun
    )
    $paths = Resolve-BackupSetPaths -Set $Set

    if ($Mode -eq 'Snapshots') {
        # Straight to the console stream, NOT down the pipeline: this function's
        # output is its status code, and a JSON document mixed into that would
        # be captured by the caller instead of reaching stdout.
        $document = Get-BackupSnapshot -BackupRoot $paths.BkpPath -ChangeRoot $paths.ChgPath |
            ConvertTo-Json -Depth 4 -AsArray
        [Console]::Out.WriteLine($document)
        return 0
    }

    # `pwsh -File` hands every argument over as one literal string, so a
    # container passing "A,B" arrives as a single element.
    $names = @($Name | Where-Object { $_ } | ForEach-Object { $_ -split ',' } |
               ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($names.Count -eq 0) {
        & $Log '-Action Prune requires -Snapshot <name>[,<name>] (retention policy belongs to the caller; this entry point takes explicit names only).' 'ERROR'
        return 2
    }

    $result = @(Remove-BackupSnapshot -BackupRoot $paths.BkpPath -ChangeRoot $paths.ChgPath `
                    -Name $names -SevenZipPath $Deps['7z'] -Log $Log `
                    -NonInteractive:$NonInteractive -WhatIf:$DryRun)
    return (Get-PruneBatchExitCode -Result $result)
}

if ($Action -ne 'Backup') {
    if (@($Sets).Count -ne 1) {
        & $globalLog ("Retention acts on ONE backup set per invocation (IF-001); this configuration declares $(@($Sets).Count). Using the first: '$($Sets[0].Name)'.") 'WARN'
    }
    $retentionCode = Invoke-RetentionAction -Set $Sets[0] -Mode $Action -Name $Snapshot `
                        -Deps $deps -Log $globalLog -DryRun:$WhatIfPreference
    if ($ExitCode) { exit $retentionCode }
    if ($retentionCode -ne 0) { throw "FileBackup -Action $Action finished with status $retentionCode (see README 'Restore exit codes')." }
    return
}

$overallSuccess = $true
$logPaths = New-Object System.Collections.Generic.List[string]

# SR-014: process each set independently — one set's failure marks the run failed
# but must not abort the remaining sets.
$setExtra = @{}
if ($PSBoundParameters.ContainsKey('BackupTime')) { $setExtra['BackupTime'] = $BackupTime }
foreach ($set in $Sets) {
    try {
        Invoke-BackupSet -Set $set -Deps $deps -OverallSuccess ([ref]$overallSuccess) -LogPaths $logPaths @setExtra
    } catch {
        & $globalLog ("Backup set '{0}' failed: {1}" -f $set.Name, $_.Exception.Message) 'ERROR'
        $overallSuccess = $false
    }
}

# region Notification (B15: optional; Send-MailMessage only when configured)

$haveMailConfig = $Secrets -and $Secrets.SmtpServer -and $Secrets.ToEmail -and $Secrets.FromEmail
if ($NoMail -or -not $haveMailConfig) {
    & $globalLog ("Skipping email notification ({0})." -f $(if ($NoMail) { '-NoMail' } else { 'SMTP not configured' }))
} else {
    $subject = if ($overallSuccess) { 'Automatic Backup Successful' } else { 'Automatic Backup Failed' }
    $body = if ($overallSuccess) {
        "All backup sets completed successfully.`r`n`r`nLogs:`r`n"   + ($logPaths -join "`r`n")
    } else {
        "One or more backup sets encountered errors.`r`n`r`nCheck logs:`r`n" + ($logPaths -join "`r`n")
    }

    $sendParams = @{
        To = $Secrets.ToEmail; From = $Secrets.FromEmail
        SmtpServer = $Secrets.SmtpServer; Port = $Secrets.SmtpPort
        Subject = $subject; Body = $body; UseSsl = $true
    }
    if ($Secrets.Credential) { $sendParams['Credential'] = $Secrets.Credential }

    try {
        # Send-MailMessage is obsolete but still functional; acceptable for a local backup notifier.
        Send-MailMessage @sendParams
    } catch {
        & $globalLog "Failed to send notification email: $($_.Exception.Message)" 'WARN'
    }
}

# endregion

if (-not $overallSuccess) { exit 1 }
