<#
.SYNOPSIS
    Phase 3 – OneDrive Known Folder Move, sync health check, and user-data prep.

.DESCRIPTION
    Runs after Phase 2 (BitLocker escrow). Focuses on making sure user files are
    protected by OneDrive before final cleanup.

    Steps:
    1. Load config + logging
    2. Apply KFM policy settings when enabled in config
    3. Attempt to start the OneDrive client if installed
    4. Report OneDrive sync / folder status (best-effort)
    5. Optionally copy key user folders (Desktop/Documents/Pictures/Downloads)
       into the detected OneDrive folder as a safety net
    6. Register Phase 4 (cleanup) via RunOnce
    7. Optionally reboot

.PARAMETER ConfigPath
    Path to MigrationConfig.psd1.

.PARAMETER SkipKFM
    Do not write KFM policy registry values.

.PARAMETER SkipUserFileCopy
    Do not copy user folders into OneDrive as a safety net.

.PARAMETER SkipReboot
    Do not reboot at the end of the phase.

.PARAMETER WhatIf
    Show actions without executing them.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ConfigPath,

    [switch]$SkipKFM,

    [switch]$SkipUserFileCopy,

    [switch]$SkipReboot
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Bootstrap helpers
# ---------------------------------------------------------------------------
$scriptRoot     = $PSScriptRoot
$migrationRoot  = 'C:\ProgramData\AADMigration'

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
    if (Get-Command Get-OneDriveSyncStatus -ErrorAction SilentlyContinue) { break }
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
    Write-DMULog -Message "[Phase3] $Message" -Level $Level
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

$MigrationPath   = if ($config.MigrationPath)   { $config.MigrationPath }   else { $migrationRoot }
$LogsPath        = if ($config.LogsPath)        { $config.LogsPath }        else { 'C:\Logs' }
$JobName         = if ($config.JobName)         { $config.JobName }         else { 'AAD_Migration' }
$TenantID        = $config.TenantID
$UseOneDriveKFM  = if ($null -ne $config.UseOneDriveKFM)  { [bool]$config.UseOneDriveKFM }  else { $true }
$InstallOneDrive = if ($null -ne $config.InstallOneDrive) { [bool]$config.InstallOneDrive } else { $true }

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
$logInfo = $null
if (Get-Command Initialize-Logging -ErrorAction SilentlyContinue) {
    $logInfo = Initialize-Logging -JobName $JobName -LogsPath $LogsPath -ParentScriptName 'Phase3-OneDrive' -UsePSFramework
}

Write-PhaseLog "=== Phase 3 – OneDrive started ===" -Level 'NOTICE'
Write-PhaseLog "UseOneDriveKFM=$UseOneDriveKFM  InstallOneDrive=$InstallOneDrive"

try {
    # -----------------------------------------------------------------------
    # 1. Known Folder Move policy
    # -----------------------------------------------------------------------
    if ($UseOneDriveKFM -and -not $SkipKFM) {
        Write-PhaseLog "Applying OneDrive Known Folder Move policy settings..." -Level 'NOTICE'
        if (Get-Command Enable-OneDriveKFM -ErrorAction SilentlyContinue) {
            if ($PSCmdlet.ShouldProcess('OneDrive KFM policies', 'Enable')) {
                Enable-OneDriveKFM -TenantID $TenantID | Out-Null
                Write-PhaseLog "KFM policy values written under HKLM:\SOFTWARE\Policies\Microsoft\OneDrive"
            }
        }
        else {
            Write-PhaseLog "Enable-OneDriveKFM helper not loaded – skipping KFM registry writes." -Level 'WARNING'
        }
    }
    else {
        Write-PhaseLog "Skipping KFM policy (UseOneDriveKFM=$UseOneDriveKFM, SkipKFM=$SkipKFM)."
    }

    # -----------------------------------------------------------------------
    # 2. Ensure OneDrive client is running (best-effort)
    # -----------------------------------------------------------------------
    $odExeCandidates = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDrive.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft OneDrive\OneDrive.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft OneDrive\OneDrive.exe')
    ) | Where-Object { $_ -and (Test-Path $_) }

    if ($odExeCandidates) {
        if (-not (Get-Process -Name 'OneDrive' -ErrorAction SilentlyContinue)) {
            Write-PhaseLog "Starting OneDrive client..."
            if ($PSCmdlet.ShouldProcess($odExeCandidates[0], 'Start OneDrive')) {
                Start-Process -FilePath $odExeCandidates[0] -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 5
            }
        }
        else {
            Write-PhaseLog "OneDrive process is already running."
        }
    }
    elseif ($InstallOneDrive) {
        Write-PhaseLog "OneDrive executable not found. InstallOneDrive is true – consider deploying the OneDrive bootstrapper via Intune before or during migration." -Level 'WARNING'
    }
    else {
        Write-PhaseLog "OneDrive not found and InstallOneDrive is false." -Level 'WARNING'
    }

    # -----------------------------------------------------------------------
    # 3. Sync / folder status
    # -----------------------------------------------------------------------
    $status = $null
    if (Get-Command Get-OneDriveSyncStatus -ErrorAction SilentlyContinue) {
        $status = Get-OneDriveSyncStatus
        Write-PhaseLog $status.StatusMessage -Level $(if ($status.NeedsAttention) { 'WARNING' } else { 'INFO' })
        if ($status.UserFolder) {
            Write-PhaseLog "Detected OneDrive folder: $($status.UserFolder)"
        }
        if ($status.KfmLikelyEnabled) {
            Write-PhaseLog "KFM appears to be active for this user."
        }
    }
    else {
        Write-PhaseLog "Get-OneDriveSyncStatus helper not available." -Level 'WARNING'
    }

    # -----------------------------------------------------------------------
    # 4. Safety-net copy of key user folders into OneDrive
    # -----------------------------------------------------------------------
    if (-not $SkipUserFileCopy -and $status -and $status.UserFolder -and (Test-Path $status.UserFolder)) {
        Write-PhaseLog "Copying key user folders into OneDrive as a safety net..." -Level 'NOTICE'

        $profileRoot = $status.UserProfile
        if (-not $profileRoot) { $profileRoot = $env:USERPROFILE }

        $foldersToCopy = @('Desktop', 'Documents', 'Pictures', 'Downloads')
        $destRoot = Join-Path $status.UserFolder 'DMU-Backup'

        if ($PSCmdlet.ShouldProcess($destRoot, 'Create safety-net backup folder')) {
            New-Item -Path $destRoot -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
        }

        foreach ($folder in $foldersToCopy) {
            $src = Join-Path $profileRoot $folder
            if (-not (Test-Path $src)) { continue }

            $dest = Join-Path $destRoot $folder
            Write-PhaseLog "  $folder  →  $dest"

            if ($PSCmdlet.ShouldProcess($src, "Robocopy to $dest")) {
                # /E copy subdirs including empty, /XO exclude older, /R:1 /W:1 quick retry,
                # /NFL /NDL /NJH /NJS quieter output
                $rcArgs = @($src, $dest, '/E', '/XO', '/R:1', '/W:1', '/NFL', '/NDL', '/NJH', '/NJS', '/NP')
                $p = Start-Process -FilePath 'robocopy.exe' -ArgumentList $rcArgs -Wait -PassThru -WindowStyle Hidden
                # Robocopy exit codes 0–7 are success / partial success
                if ($p.ExitCode -ge 8) {
                    Write-PhaseLog "  Robocopy warning for $folder (exit $($p.ExitCode))" -Level 'WARNING'
                }
            }
        }

        Write-PhaseLog "Safety-net copy complete under $destRoot"
    }
    elseif ($SkipUserFileCopy) {
        Write-PhaseLog "SkipUserFileCopy specified – not copying user folders."
    }
    else {
        Write-PhaseLog "No OneDrive folder detected – skipping safety-net file copy." -Level 'WARNING'
    }

    # -----------------------------------------------------------------------
    # 5. Register Phase 4 (cleanup) via RunOnce
    # -----------------------------------------------------------------------
    $phase4Name   = 'Phase4-Cleanup.ps1'
    $phase4Script = Join-Path $MigrationPath "Scripts\$phase4Name"
    if (-not (Test-Path $phase4Script)) {
        $alt = Join-Path $scriptRoot $phase4Name
        if (Test-Path $alt) { $phase4Script = $alt }
    }

    $runOnceKey  = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
    $runOnceName = 'DMU-Phase4-Cleanup'
    $psExe       = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

    if (Test-Path $phase4Script) {
        $runOnceCmd = "`"$psExe`" -NoProfile -ExecutionPolicy Bypass -File `"$phase4Script`""
        Write-PhaseLog "Registering RunOnce for Phase 4: $phase4Script"

        if ($PSCmdlet.ShouldProcess($runOnceName, 'Set RunOnce')) {
            if (-not (Test-Path $runOnceKey)) { New-Item -Path $runOnceKey -Force | Out-Null }
            Set-ItemProperty -Path $runOnceKey -Name $runOnceName -Value $runOnceCmd -Force
            Write-PhaseLog "RunOnce entry created: $runOnceName"
        }
    }
    else {
        Write-PhaseLog "Phase 4 script not found yet – registering inline cleanup fallback." -Level 'WARNING'
        $cleanupCmd = "`"$psExe`" -NoProfile -ExecutionPolicy Bypass -Command `"if (Get-Command Remove-MigrationArtifacts -ErrorAction SilentlyContinue) { Remove-MigrationArtifacts -Verbose } else { Write-Host 'Remove-MigrationArtifacts not available' }`""
        if ($PSCmdlet.ShouldProcess('DMU-Phase4-Cleanup', 'Set fallback RunOnce')) {
            if (-not (Test-Path $runOnceKey)) { New-Item -Path $runOnceKey -Force | Out-Null }
            Set-ItemProperty -Path $runOnceKey -Name $runOnceName -Value $cleanupCmd -Force
        }
    }

    # -----------------------------------------------------------------------
    # 6. Summary
    # -----------------------------------------------------------------------
    Write-PhaseLog "=== Phase 3 completed ===" -Level 'NOTICE'
    Write-PhaseLog "OneDrive KFM policies and safety-net copy (if applicable) are done."
    Write-PhaseLog "User should sign in with their Entra ID account so OneDrive can finish syncing."

    if (-not $SkipReboot) {
        Write-PhaseLog "Rebooting in 60 seconds to continue toward cleanup..." -Level 'NOTICE'
        if ($PSCmdlet.ShouldProcess('Computer', 'Restart')) {
            Start-Process -FilePath 'shutdown.exe' -ArgumentList '/r', '/t', '60', '/c', 'DMU Phase 3 complete – finalizing migration' -WindowStyle Hidden
        }
    }
    else {
        Write-PhaseLog "SkipReboot specified – reboot manually when ready." -Level 'WARNING'
    }

    [PSCustomObject]@{
        Success         = $true
        Phase           = 'Phase3-OneDrive'
        OneDriveStatus  = $status
        KfmApplied      = ($UseOneDriveKFM -and -not $SkipKFM)
        RebootScheduled = -not $SkipReboot
        Timestamp       = Get-Date
    }
}
catch {
    Write-PhaseLog "Phase 3 failed: $($_.Exception.Message)" -Level 'ERROR'
    throw
}
finally {
    if ($logInfo -and (Get-Command Stop-Logging -ErrorAction SilentlyContinue)) {
        Stop-Logging -TranscriptPath $logInfo.TranscriptPath `
                     -InstanceName $logInfo.InstanceName `
                     -PSFEnabled:$logInfo.PSFEnabled
    }
}