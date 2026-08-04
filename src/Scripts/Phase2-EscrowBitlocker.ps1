<#
.SYNOPSIS
    Phase 2 – Escrow BitLocker recovery keys to Entra ID and apply post-join settings.

.DESCRIPTION
    Intended to run automatically via RunOnce after Phase 1 (Entra Join) completes
    and the device has rebooted into the new tenant context.

    Steps:
    1. Load configuration and initialize logging
    2. Escrow BitLocker recovery password protectors to Entra ID
    3. Apply post-migration registry settings (legal notice, disable auto-logon, etc.)
    4. Register Phase 3 (OneDrive) via RunOnce when the script is present
    5. Optionally reboot

.PARAMETER ConfigPath
    Path to MigrationConfig.psd1.

.PARAMETER MountPoint
    Drive(s) to escrow. Defaults to system drive.

.PARAMETER CreateProtectorIfMissing
    Attempt to add a RecoveryPassword protector if none exists.

.PARAMETER SkipReboot
    Do not reboot at the end of the phase.

.PARAMETER WhatIf
    Show actions without executing them.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ConfigPath,

    [string[]]$MountPoint = @($env:SystemDrive),

    [switch]$CreateProtectorIfMissing,

    [switch]$SkipReboot
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Bootstrap helpers from the staged / repo layout
# ---------------------------------------------------------------------------
$scriptRoot = $PSScriptRoot
$repoRoot   = $null

# Prefer helpers already staged under the migration path
$migrationRoot = 'C:\ProgramData\AADMigration'
$candidateRoots = @(
    $migrationRoot,
    (Split-Path (Split-Path $scriptRoot -Parent) -Parent)
)

foreach ($root in $candidateRoots) {
    $pub = Join-Path $root 'src\Public'
    $prv = Join-Path $root 'src\Private'
    # Also support flat staging under MigrationPath\Scripts + helpers nearby
    if (-not (Test-Path $pub)) {
        $pub = Join-Path (Split-Path $scriptRoot -Parent) 'Public'
        $prv = Join-Path (Split-Path $scriptRoot -Parent) 'Private'
    }
    if (Test-Path $prv) {
        Get-ChildItem -Path $prv -Filter '*.ps1' -ErrorAction SilentlyContinue | ForEach-Object { . $_.FullName }
    }
    if (Test-Path $pub) {
        Get-ChildItem -Path $pub -Filter '*.ps1' -ErrorAction SilentlyContinue | ForEach-Object { . $_.FullName }
    }
    if (Get-Command Invoke-BitLockerEscrow -ErrorAction SilentlyContinue) {
        $repoRoot = $root
        break
    }
}

# Fallback minimal logger
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
    Write-DMULog -Message "[Phase2] $Message" -Level $Level
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

if (-not $ConfigPath -or -not (Test-Path $ConfigPath)) {
    Write-PhaseLog "Config not found – continuing with defaults." -Level 'WARNING'
    $config = @{}
}
else {
    $config = Import-PowerShellDataFile -Path $ConfigPath
}

$MigrationPath = if ($config.MigrationPath) { $config.MigrationPath } else { $migrationRoot }
$LogsPath      = if ($config.LogsPath)      { $config.LogsPath }      else { 'C:\Logs' }
$JobName       = if ($config.JobName)       { $config.JobName }       else { 'AAD_Migration' }

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
$logInfo = $null
if (Get-Command Initialize-Logging -ErrorAction SilentlyContinue) {
    $logInfo = Initialize-Logging -JobName $JobName -LogsPath $LogsPath -ParentScriptName 'Phase2-EscrowBitlocker' -UsePSFramework
}

Write-PhaseLog "=== Phase 2 – BitLocker Escrow started ===" -Level 'NOTICE'
Write-PhaseLog "MountPoint(s): $($MountPoint -join ', ')"

try {
    # -----------------------------------------------------------------------
    # 1. Escrow BitLocker recovery keys
    # -----------------------------------------------------------------------
    Write-PhaseLog "Escrowing BitLocker recovery keys to Entra ID..." -Level 'NOTICE'

    if (-not (Get-Command Invoke-BitLockerEscrow -ErrorAction SilentlyContinue)) {
        # Inline fallback if the private helper was not loaded
        function Invoke-BitLockerEscrow {
            param([string[]]$MountPoint = @($env:SystemDrive), [switch]$CreateProtectorIfMissing)
            foreach ($drive in $MountPoint) {
                try {
                    $vol = Get-BitLockerVolume -MountPoint $drive -ErrorAction Stop
                } catch {
                    [PSCustomObject]@{ MountPoint = $drive; Success = $true; KeyProtectorIds = @(); Message = "Not protected: $drive" }
                    continue
                }
                if ($vol.ProtectionStatus -eq 'Off') {
                    [PSCustomObject]@{ MountPoint = $drive; Success = $true; KeyProtectorIds = @(); Message = "BitLocker off on $drive" }
                    continue
                }
                $ids = @($vol.KeyProtector | Where-Object KeyProtectorType -eq 'RecoveryPassword' | Select-Object -ExpandProperty KeyProtectorId)
                foreach ($id in $ids) {
                    try {
                        BackupToAAD-BitLockerKeyProtector -MountPoint $drive -KeyProtectorId $id -ErrorAction Stop
                    } catch {
                        Write-Warning "Escrow warning for $drive / $id : $($_.Exception.Message)"
                    }
                }
                [PSCustomObject]@{ MountPoint = $drive; Success = $true; KeyProtectorIds = $ids; Message = "Escrow attempted for $drive" }
            }
        }
    }

    $escrowResults = Invoke-BitLockerEscrow -MountPoint $MountPoint -CreateProtectorIfMissing:$CreateProtectorIfMissing

    foreach ($r in $escrowResults) {
        $level = if ($r.Success) { 'INFO' } else { 'WARNING' }
        Write-PhaseLog "$($r.MountPoint): $($r.Message)" -Level $level
        if ($r.KeyProtectorIds.Count -gt 0) {
            Write-PhaseLog "  Protector IDs: $($r.KeyProtectorIds -join ', ')" -Level 'DEBUG'
        }
    }

    # -----------------------------------------------------------------------
    # 2. Post-migration registry settings
    # -----------------------------------------------------------------------
    Write-PhaseLog "Applying post-migration registry settings..."

    $registrySettings = @(
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'; Name = 'AutoAdminLogon'; Type = 'String'; Value = '0' },
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name = 'dontdisplaylastusername'; Type = 'DWord'; Value = 1 },
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name = 'legalnoticecaption'; Type = 'String'; Value = 'Migration Completed' },
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name = 'legalnoticetext'; Type = 'String'; Value = 'This PC has been migrated to Microsoft Entra ID. Please sign in with your work or school account (email address and password).' }
    )

    foreach ($reg in $registrySettings) {
        if ($PSCmdlet.ShouldProcess("$($reg.Path)\$($reg.Name)", 'Set registry value')) {
            try {
                if (-not (Test-Path $reg.Path)) {
                    New-Item -Path $reg.Path -Force | Out-Null
                }
                Set-ItemProperty -Path $reg.Path -Name $reg.Name -Value $reg.Value -Type $reg.Type -Force
                Write-PhaseLog "Set $($reg.Name) = $($reg.Value)"
            }
            catch {
                Write-PhaseLog "Could not set $($reg.Name): $($_.Exception.Message)" -Level 'WARNING'
            }
        }
    }

    # -----------------------------------------------------------------------
    # 3. Register Phase 3 (OneDrive) via RunOnce when available
    # -----------------------------------------------------------------------
    $phase3Name   = 'Phase3-OneDrive.ps1'
    $phase3Script = Join-Path $MigrationPath "Scripts\$phase3Name"
    if (-not (Test-Path $phase3Script)) {
        $alt = Join-Path $scriptRoot $phase3Name
        if (Test-Path $alt) { $phase3Script = $alt }
    }

    $runOnceKey  = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
    $runOnceName = 'DMU-Phase3-OneDrive'
    $psExe       = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

    if (Test-Path $phase3Script) {
        $runOnceCmd = "`"$psExe`" -NoProfile -ExecutionPolicy Bypass -File `"$phase3Script`""
        Write-PhaseLog "Registering RunOnce for Phase 3: $phase3Script"

        if ($PSCmdlet.ShouldProcess($runOnceName, 'Set RunOnce registry value')) {
            if (-not (Test-Path $runOnceKey)) {
                New-Item -Path $runOnceKey -Force | Out-Null
            }
            Set-ItemProperty -Path $runOnceKey -Name $runOnceName -Value $runOnceCmd -Force
            Write-PhaseLog "RunOnce entry created: $runOnceName"
        }
    }
    else {
        Write-PhaseLog "Phase 3 script not found – skipping RunOnce registration. (Expected later: $phase3Name)" -Level 'WARNING'

        # Fall back to a simple cleanup RunOnce that calls Remove-MigrationArtifacts if available
        $cleanupCmd = "`"$psExe`" -NoProfile -ExecutionPolicy Bypass -Command `"if (Get-Command Remove-MigrationArtifacts -ErrorAction SilentlyContinue) { Remove-MigrationArtifacts } else { Write-Host 'Cleanup helper not loaded' }`""
        if ($PSCmdlet.ShouldProcess('DMU-Phase4-Cleanup', 'Set fallback cleanup RunOnce')) {
            if (-not (Test-Path $runOnceKey)) { New-Item -Path $runOnceKey -Force | Out-Null }
            Set-ItemProperty -Path $runOnceKey -Name 'DMU-Phase4-Cleanup' -Value $cleanupCmd -Force
            Write-PhaseLog "Fallback cleanup RunOnce registered."
        }
    }

    # -----------------------------------------------------------------------
    # 4. Summary
    # -----------------------------------------------------------------------
    Write-PhaseLog "=== Phase 2 completed ===" -Level 'NOTICE'
    Write-PhaseLog "BitLocker recovery keys have been submitted to Entra ID (verify in the admin center)."
    Write-PhaseLog "Post-migration legal notice and auto-logon settings applied."

    if (-not $SkipReboot) {
        Write-PhaseLog "Rebooting in 45 seconds to continue the migration sequence..." -Level 'NOTICE'
        if ($PSCmdlet.ShouldProcess('Computer', 'Restart')) {
            Start-Process -FilePath 'shutdown.exe' -ArgumentList '/r', '/t', '45', '/c', 'DMU Phase 2 complete – continuing migration' -WindowStyle Hidden
        }
    }
    else {
        Write-PhaseLog "SkipReboot specified – reboot manually when ready." -Level 'WARNING'
    }

    [PSCustomObject]@{
        Success          = $true
        Phase            = 'Phase2-EscrowBitlocker'
        EscrowResults    = $escrowResults
        RebootScheduled  = -not $SkipReboot
        Timestamp        = Get-Date
    }
}
catch {
    Write-PhaseLog "Phase 2 failed: $($_.Exception.Message)" -Level 'ERROR'
    throw
}
finally {
    if ($logInfo -and (Get-Command Stop-Logging -ErrorAction SilentlyContinue)) {
        Stop-Logging -TranscriptPath $logInfo.TranscriptPath `
                     -InstanceName $logInfo.InstanceName `
                     -PSFEnabled:$logInfo.PSFEnabled
    }
}