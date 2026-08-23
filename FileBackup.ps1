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
        2  The configuration could not be loaded, or violates the SR-042
           schema (missing/unrecognized ConfigVersion, unknown key, wrong
           JSON type, Secrets.Credential in JSON, etc.) — nothing was
           attempted.

    Without -ExitCode, a configuration failure is a terminating error (throw)
    and a failed set still yields a non-zero exit via the normal PowerShell
    unhandled-error path — unchanged from before SR-042/SR-043.
#>

[CmdletBinding()]
param(
    [string]$ConfigPath = "$HOME\BackupConfig.xml",
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

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "Config file '$ConfigPath' not found."
}

$ConfigPath = (Resolve-Path -LiteralPath $ConfigPath).Path

# Temporary logger for configuration and dependency messages. Built before the
# config is loaded (it needs only $ConfigPath/$GlobalLogPath) so a config-load
# failure can still be logged (SR-043).
$globalLogPath = if ($GlobalLogPath) {
    $GlobalLogPath
} else {
    Join-Path ([IO.Path]::GetDirectoryName($ConfigPath)) 'Backup_Global.log'
}
$globalLogDirectory = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($globalLogPath))
if (-not (Test-Path -LiteralPath $globalLogDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $globalLogDirectory -Force | Out-Null
}
$globalLog     = New-Logger -LogFile $globalLogPath

function Exit-ConfigFailure {
    <#
    .SYNOPSIS
        Reports an Import-BackupConfiguration failure at the FileBackup.ps1
        process boundary.
    .DESCRIPTION
        Writes the failure message to stderr and to the global log, then either
        exits the process with 2 (SR-043's usage/precondition class) when
        -ExitCode was passed, or rethrows -- preserving the terminating-error
        behavior that tests/Unit/Engine.Tests.ps1 and the test harness rely on.
    .PARAMETER Message
        The operator-facing reason. SR-042's loader already names the
        offending key/JSON path; wording is otherwise unchanged from before
        WP2 for the checks it preserves verbatim.
    #>
    # Implements: SR-043, LLR-043
    param([Parameter(Mandatory)][string]$Message)
    [Console]::Error.WriteLine("FileBackup: $Message")
    & $globalLog $Message 'ERROR'
    if ($ExitCode) {
        exit 2
    }
    throw $Message
}

try {
    $cfgResult = Import-BackupConfiguration -Path $ConfigPath -Log $globalLog
} catch {
    Exit-ConfigFailure -Message $_.Exception.Message
}
$Secrets = $cfgResult.Secrets
$Sets    = $cfgResult.Sets

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
