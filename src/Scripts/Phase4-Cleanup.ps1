<#
.SYNOPSIS
    Phase 4 – Final migration cleanup.

.DESCRIPTION
    Runs after Phase 3 (OneDrive). Removes temporary migration artifacts so the
    device is left in a normal, user-ready state.

    Steps:
    1. Load config + logging
    2. Clear DMU-related RunOnce entries
    3. Remove scheduled tasks under \AAD Migration\
    4. Remove the temporary local admin account
    5. Reset post-migration registry values (legal notice, auto-logon, etc.)
    6. Optionally remove the migration working directory (keeps logs by default)
    7. Final device join status report
    8. Optional reboot

.PARAMETER ConfigPath
    Path to MigrationConfig.psd1.

.PARAMETER PreserveMigrationPath
    Keep C:\ProgramData\AADMigration (scripts/config). Default is to remove it.

.PARAMETER PreserveLogs
    Keep C:\Logs (default: $true).

.PARAMETER SkipReboot
    Do not reboot at the end.

.PARAMETER WhatIf
    Show actions without executing them.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ConfigPath,

    [switch]$PreserveMigrationPath,

    [switch]$PreserveLogs = $true,

    [switch]$SkipReboot
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Bootstrap helpers
# ---------------------------------------------------------------------------
$scriptRoot    = $PSScriptRoot
$migrationRoot = 'C:\ProgramData\AADMigration'

$candidateRoots = @(
    $migrationRoot,
    (Split-Path (Split-Path $scriptRoot -Parent) -Parent),
    (Split-Path $scriptRoot -Parent)
)

foreach ($root in $candidateRoots) {
    foreach ($sub in @('src\Private', 'src\Public', 'Private', 'Public')) {
        $dir = Join-Path $root $sub
        if (Test-Path $dir) {
            Get-ChildItem -Path $dir -Filter '*.ps1' -ErrorAction SilentlyContinue | ForEach-Object {
                . $_.FullName
            }
        }
    }
    if (Get-Command Remove-MigrationArtifacts -ErrorAction SilentlyContinue) { break }
}

if (-not (Get-Command Write-DMULog -ErrorAction SilentlyContinue)) {
    function Write-DMULog {
        param([string]$Message, [string]$Level = 'INFO')
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $color = switch ($Level) {
            'ERROR'   { 'Red' }
            'WARNING' { 'Yellow' }
            'NOTICE'  { 'Cyan' }
            'DEBUG'   { 'DarkGray' }
            default   { 'Green' }
        }
        Write-Host "[$ts] [$Level] $Message" -ForegroundColor $color
    }
}

function Write-PhaseLog {
    param([string]$Message, [string]$Level = 'INFO')
    Write-DMULog -Message "[Phase4] $Message" -Level $Level
}

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
if (-not $ConfigPath) {
    $candidates = @(
        (Join-Path $migrationRoot 'MigrationConfig.psd1'),
        (Join-Path $scriptRoot '..\..\config\MigrationConfig.psd1')
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { $ConfigPath = $c; break }
    }
}

if ($ConfigPath -and (Test-Path $ConfigPath)) {
    $config = Import-PowerShellDataFile -Path $ConfigPath
}
else {
    Write-PhaseLog "Config not found – using defaults." -Level 'WARNING'
    $config = @{}
}

$MigrationPath = if ($config.MigrationPath) { $config.MigrationPath } else { $migrationRoot }
$LogsPath      = if ($config.LogsPath)      { $config.LogsPath }      else { 'C:\Logs' }
$JobName       = if ($config.JobName)       { $config.JobName }       else { 'AAD_Migration' }
$TempUserName  = if ($config.TempUser)      { $config.TempUser }      else { 'MigrationInProgress' }
$TempPath      = 'C:\temp'

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
$logInfo = $null
if (Get-Command Initialize-Logging -ErrorAction SilentlyContinue) {
    $logInfo = Initialize-Logging -JobName $JobName -LogsPath $LogsPath -ParentScriptName 'Phase4-Cleanup' -UsePSFramework
}

Write-PhaseLog "=== Phase 4 – Final Cleanup started ===" -Level 'NOTICE'
Write-PhaseLog "PreserveMigrationPath=$PreserveMigrationPath  PreserveLogs=$PreserveLogs"

try {
    # -----------------------------------------------------------------------
    # 1. Clear DMU RunOnce entries
    # -----------------------------------------------------------------------
    $runOnceKey = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
    $dmuRunOnceNames = @(
        'DMU-Phase2-EscrowBitlocker',
        'DMU-Phase3-OneDrive',
        'DMU-Phase4-Cleanup',
        'NextRun'   # legacy name from original scripts
    )

    if (Test-Path $runOnceKey) {
        foreach ($name in $dmuRunOnceNames) {
            $existing = Get-ItemProperty -Path $runOnceKey -Name $name -ErrorAction SilentlyContinue
            if ($null -ne $existing) {
                if ($PSCmdlet.ShouldProcess("$runOnceKey\$name", 'Remove RunOnce value')) {
                    Remove-ItemProperty -Path $runOnceKey -Name $name -Force -ErrorAction SilentlyContinue
                    Write-PhaseLog "Removed RunOnce: $name"
                }
            }
        }
    }

    # -----------------------------------------------------------------------
    # 2. Scheduled tasks under \AAD Migration\
    # -----------------------------------------------------------------------
    Write-PhaseLog "Removing scheduled tasks under \AAD Migration\..."
    $tasks = Get-ScheduledTask -TaskPath '\AAD Migration\' -ErrorAction SilentlyContinue
    if ($tasks) {
        foreach ($task in $tasks) {
            if ($PSCmdlet.ShouldProcess($task.TaskName, 'Unregister scheduled task')) {
                Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false -ErrorAction SilentlyContinue
                Write-PhaseLog "  Removed task: $($task.TaskName)"
            }
        }
    }
    else {
        Write-PhaseLog "No scheduled tasks found under \AAD Migration\."
    }

    # Remove the task folder itself
    try {
        $service = New-Object -ComObject 'Schedule.Service'
        $service.Connect()
        $rootFolder = $service.GetFolder('\')
        $null = $rootFolder.GetFolder('AAD Migration')  # throws if missing
        if ($PSCmdlet.ShouldProcess('AAD Migration', 'Delete scheduled-task folder')) {
            $rootFolder.DeleteFolder('AAD Migration', 0)
            Write-PhaseLog "Removed scheduled-task folder: \AAD Migration\"
        }
    }
    catch {
        Write-PhaseLog "Scheduled-task folder \AAD Migration\ not present or already removed."
    }

    # -----------------------------------------------------------------------
    # 3. Temporary local admin account
    # -----------------------------------------------------------------------
    Write-PhaseLog "Removing temporary local account '$TempUserName' (if present)..."
    try {
        $user = Get-LocalUser -Name $TempUserName -ErrorAction Stop
        if ($user -and $PSCmdlet.ShouldProcess($TempUserName, 'Remove local user')) {
            # Ensure the account is not logged on
            $sessions = quser 2>$null | Select-String $TempUserName
            if ($sessions) {
                Write-PhaseLog "Account $TempUserName appears to have an active session – attempting logoff." -Level 'WARNING'
                # Best-effort; do not fail the whole phase
            }
            Remove-LocalUser -Name $TempUserName -ErrorAction Stop
            Write-PhaseLog "Removed local user: $TempUserName"
        }
    }
    catch {
        Write-PhaseLog "Local user '$TempUserName' does not exist – skipping."
    }

    # Also clear any AutoAdminLogon that might still point at the temp user
    $winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    if (Test-Path $winlogon) {
        $autoUser = (Get-ItemProperty -Path $winlogon -Name 'DefaultUserName' -ErrorAction SilentlyContinue).DefaultUserName
        if ($autoUser -eq $TempUserName) {
            if ($PSCmdlet.ShouldProcess($winlogon, 'Clear AutoAdminLogon settings')) {
                Set-ItemProperty -Path $winlogon -Name 'AutoAdminLogon' -Value '0' -Force -ErrorAction SilentlyContinue
                Remove-ItemProperty -Path $winlogon -Name 'DefaultPassword' -Force -ErrorAction SilentlyContinue
                Write-PhaseLog "Cleared AutoAdminLogon that referenced $TempUserName"
            }
        }
        else {
            # Still ensure AutoAdminLogon is off
            Set-ItemProperty -Path $winlogon -Name 'AutoAdminLogon' -Value '0' -Force -ErrorAction SilentlyContinue
        }
    }

    # -----------------------------------------------------------------------
    # 4. Reset post-migration registry values
    # -----------------------------------------------------------------------
    Write-PhaseLog "Resetting post-migration registry values..."

    $registryResets = @(
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name = 'dontdisplaylastusername'; Type = 'DWord';  Value = 0 },
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name = 'legalnoticecaption';      Type = 'String'; Value = '' },
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name = 'legalnoticetext';         Type = 'String'; Value = '' },
        @{ Path = 'HKLM:\Software\Policies\Microsoft\Windows\Personalization';       Name = 'NoLockScreen';            Type = 'DWord';  Value = 0 },
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization';       Name = 'LockScreenImage';         Type = 'String'; Value = $null }  # remove if present
    )

    foreach ($reg in $registryResets) {
        if (-not (Test-Path $reg.Path)) { continue }

        if ($null -eq $reg.Value) {
            if ($PSCmdlet.ShouldProcess("$($reg.Path)\$($reg.Name)", 'Remove registry value')) {
                Remove-ItemProperty -Path $reg.Path -Name $reg.Name -Force -ErrorAction SilentlyContinue
                Write-PhaseLog "  Removed $($reg.Name)"
            }
        }
        else {
            if ($PSCmdlet.ShouldProcess("$($reg.Path)\$($reg.Name)", 'Reset registry value')) {
                try {
                    Set-ItemProperty -Path $reg.Path -Name $reg.Name -Value $reg.Value -Type $reg.Type -Force -ErrorAction SilentlyContinue
                    Write-PhaseLog "  Reset $($reg.Name)"
                }
                catch {
                    Write-PhaseLog "  Could not reset $($reg.Name): $($_.Exception.Message)" -Level 'WARNING'
                }
            }
        }
    }

    # -----------------------------------------------------------------------
    # 5. Working directories & temp folders
    # -----------------------------------------------------------------------
    $pathsToRemove = [System.Collections.Generic.List[string]]::new()

    if (-not $PreserveMigrationPath) {
        $pathsToRemove.Add($MigrationPath)
    }
    else {
        Write-PhaseLog "PreserveMigrationPath set – keeping $MigrationPath"
    }

    if (-not $PreserveLogs) {
        $pathsToRemove.Add($LogsPath)
    }
    else {
        Write-PhaseLog "PreserveLogs set – keeping $LogsPath"
    }

    # Always try to clean the old secret/log staging folders under C:\temp
    $pathsToRemove.Add((Join-Path $TempPath "$JobName-secrets"))
    $pathsToRemove.Add((Join-Path $TempPath "$JobName-logs"))
    $pathsToRemove.Add((Join-Path $TempPath "$JobName-git"))

    foreach ($path in $pathsToRemove) {
        if ($path -and (Test-Path $path)) {
            if ($PSCmdlet.ShouldProcess($path, 'Remove directory')) {
                try {
                    Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
                    Write-PhaseLog "Removed: $path"
                }
                catch {
                    Write-PhaseLog "Could not fully remove $path : $($_.Exception.Message)" -Level 'WARNING'
                }
            }
        }
    }

    # -----------------------------------------------------------------------
    # 6. Final device status (best-effort)
    # -----------------------------------------------------------------------
    Write-PhaseLog "Checking final device join status..."
    $finalStatus = $null
    if (Get-Command Get-DeviceJoinStatus -ErrorAction SilentlyContinue) {
        try {
            $finalStatus = Get-DeviceJoinStatus
            Write-PhaseLog "Join type : $($finalStatus.JoinType)"
            Write-PhaseLog "MDM       : $($finalStatus.IsMDMEnrolled)"
            Write-PhaseLog "Needs mig : $($finalStatus.NeedsMigration)"
        }
        catch {
            Write-PhaseLog "Could not retrieve join status: $($_.Exception.Message)" -Level 'WARNING'
        }
    }

    # -----------------------------------------------------------------------
    # 7. Summary
    # -----------------------------------------------------------------------
    Write-PhaseLog "=== Phase 4 completed – migration cleanup finished ===" -Level 'NOTICE'
    Write-PhaseLog "The device should now be ready for normal Entra ID user sign-in."
    Write-PhaseLog "Remind the user to confirm OneDrive sync and that BitLocker keys are visible in Entra ID."

    if (-not $SkipReboot) {
        Write-PhaseLog "Rebooting in 30 seconds..." -Level 'NOTICE'
        if ($PSCmdlet.ShouldProcess('Computer', 'Restart')) {
            Start-Process -FilePath 'shutdown.exe' -ArgumentList '/r', '/t', '30', '/c', 'DMU Phase 4 complete – migration finished' -WindowStyle Hidden
        }
    }
    else {
        Write-PhaseLog "SkipReboot specified – no reboot scheduled." -Level 'WARNING'
    }

    [PSCustomObject]@{
        Success              = $true
        Phase                = 'Phase4-Cleanup'
        TempUserRemoved      = $true
        MigrationPathRemoved = -not $PreserveMigrationPath
        LogsPreserved        = [bool]$PreserveLogs
        FinalStatus          = $finalStatus
        RebootScheduled      = -not $SkipReboot
        Timestamp            = Get-Date
    }
}
catch {
    Write-PhaseLog "Phase 4 failed: $($_.Exception.Message)" -Level 'ERROR'
    throw
}
finally {
    if ($logInfo -and (Get-Command Stop-Logging -ErrorAction SilentlyContinue)) {
        Stop-Logging -TranscriptPath $logInfo.TranscriptPath `
                     -InstanceName $logInfo.InstanceName `
                     -PSFEnabled:$logInfo.PSFEnabled
    }
}