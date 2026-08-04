<#
.SYNOPSIS
    Phase 1 – Apply provisioning package for Entra Join and schedule Phase 2.

.DESCRIPTION
    This script is intended to run elevated (ideally as SYSTEM via scheduled task
    or during an interactive migration session).

    Steps:
    1. Load migration configuration
    2. Initialize logging
    3. Validate the provisioning package (PPKG)
    4. Optionally set a "Migration in Progress" desktop/lock-screen image
    5. Install the provisioning package (Entra Join)
    6. Register Phase 2 (BitLocker escrow) via RunOnce
    7. Optionally reboot the device

.PARAMETER ConfigPath
    Path to MigrationConfig.psd1. Defaults to the standard location under
    C:\ProgramData\AADMigration or the repo config folder.

.PARAMETER SkipWallpaper
    Do not attempt to set a migration-in-progress image.

.PARAMETER SkipReboot
    Do not reboot after applying the PPKG / setting RunOnce.

.PARAMETER WhatIf
    Show actions without executing them.

.NOTES
    Requires administrative rights.
    Install-ProvisioningPackage is part of Windows (Provisioning module).
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ConfigPath,

    [switch]$SkipWallpaper,

    [switch]$SkipReboot
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Bootstrap – locate repo helpers if available, otherwise use local fallbacks
# ---------------------------------------------------------------------------
$scriptRoot = $PSScriptRoot
$repoRoot   = Split-Path (Split-Path $scriptRoot -Parent) -Parent

$publicPath  = Join-Path $repoRoot 'src\Public'
$privatePath = Join-Path $repoRoot 'src\Private'

foreach ($path in @($publicPath, $privatePath)) {
    if (Test-Path $path) {
        Get-ChildItem -Path $path -Filter '*.ps1' -ErrorAction SilentlyContinue | ForEach-Object {
            . $_.FullName
        }
    }
}

# Fallback logger if shared helpers are not present
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
    Write-DMULog -Message "[Phase1] $Message" -Level $Level
}

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
if (-not $ConfigPath) {
    $candidates = @(
        'C:\ProgramData\AADMigration\MigrationConfig.psd1',
        (Join-Path $repoRoot 'config\MigrationConfig.psd1')
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { $ConfigPath = $c; break }
    }
}

if (-not $ConfigPath -or -not (Test-Path $ConfigPath)) {
    throw "MigrationConfig.psd1 not found. Provide -ConfigPath or place the file under C:\ProgramData\AADMigration\"
}

$config = Import-PowerShellDataFile -Path $ConfigPath

$MigrationPath        = if ($config.MigrationPath)        { $config.MigrationPath }        else { 'C:\ProgramData\AADMigration' }
$LogsPath             = if ($config.LogsPath)             { $config.LogsPath }             else { 'C:\Logs' }
$JobName              = if ($config.JobName)              { $config.JobName }              else { 'AAD_Migration' }
$ProvisioningPack     = $config.ProvisioningPack
$ProvisioningPackName = $config.ProvisioningPackName
$WallpaperPath        = Join-Path $MigrationPath 'Files\MigrationInProgress.bmp'

# Resolve relative pack paths against MigrationPath
if ($ProvisioningPack -and -not [System.IO.Path]::IsPathRooted($ProvisioningPack)) {
    $ProvisioningPack = Join-Path $MigrationPath $ProvisioningPack
}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
$logInfo = $null
if (Get-Command Initialize-Logging -ErrorAction SilentlyContinue) {
    $logInfo = Initialize-Logging -JobName $JobName -LogsPath $LogsPath -ParentScriptName 'Phase1-EntraJoin' -UsePSFramework
}

Write-PhaseLog "=== Phase 1 – Entra Join started ===" -Level 'NOTICE'
Write-PhaseLog "Config           : $ConfigPath"
Write-PhaseLog "MigrationPath    : $MigrationPath"
Write-PhaseLog "ProvisioningPack : $ProvisioningPack"

try {
    # -----------------------------------------------------------------------
    # 1. Validate provisioning package
    # -----------------------------------------------------------------------
    if (-not $ProvisioningPack) {
        throw "ProvisioningPack is not defined in the configuration."
    }
    if (-not (Test-Path -Path $ProvisioningPack)) {
        throw "Provisioning package not found: $ProvisioningPack"
    }

    $packItem = Get-Item -Path $ProvisioningPack
    Write-PhaseLog "PPKG found – Size: $([math]::Round($packItem.Length / 1KB, 1)) KB, LastWrite: $($packItem.LastWriteTime)"

    # -----------------------------------------------------------------------
    # 2. Optional wallpaper / lock-screen image
    # -----------------------------------------------------------------------
    if (-not $SkipWallpaper -and (Test-Path -Path $WallpaperPath)) {
        Write-PhaseLog "Setting migration-in-progress image: $WallpaperPath"

        if ($PSCmdlet.ShouldProcess($WallpaperPath, 'Set desktop and lock-screen image')) {
            try {
                # Desktop wallpaper (current user – limited effect under SYSTEM)
                $deskKey = 'HKCU:\Control Panel\Desktop'
                if (Test-Path $deskKey) {
                    Set-ItemProperty -Path $deskKey -Name Wallpaper -Value $WallpaperPath -Force -ErrorAction SilentlyContinue
                    Set-ItemProperty -Path $deskKey -Name WallpaperStyle -Value 10 -Force -ErrorAction SilentlyContinue  # Fill
                }

                # Lock screen (machine-wide where possible)
                $lockKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization'
                if (-not (Test-Path $lockKey)) {
                    New-Item -Path $lockKey -Force | Out-Null
                }
                Set-ItemProperty -Path $lockKey -Name LockScreenImage -Value $WallpaperPath -Force -ErrorAction SilentlyContinue

                # Force refresh for interactive sessions
                if (Get-Command rundll32.exe -ErrorAction SilentlyContinue) {
                    Start-Process -FilePath 'rundll32.exe' -ArgumentList 'user32.dll,UpdatePerUserSystemParameters' -WindowStyle Hidden -ErrorAction SilentlyContinue
                }

                Write-PhaseLog "Migration image applied (best-effort)."
            }
            catch {
                Write-PhaseLog "Could not set migration image: $($_.Exception.Message)" -Level 'WARNING'
            }
        }
    }
    else {
        Write-PhaseLog "Skipping wallpaper (SkipWallpaper=$SkipWallpaper or image missing)."
    }

    # -----------------------------------------------------------------------
    # 3. Apply provisioning package (Entra Join)
    # -----------------------------------------------------------------------
    Write-PhaseLog "Installing provisioning package..." -Level 'NOTICE'

    if ($PSCmdlet.ShouldProcess($ProvisioningPack, 'Install-ProvisioningPackage')) {
        # Prefer the native PowerShell cmdlet (Windows 10 1809+)
        if (Get-Command Install-ProvisioningPackage -ErrorAction SilentlyContinue) {
            $installParams = @{
                PackagePath  = $ProvisioningPack
                ForceInstall = $true
                QuietInstall = $true
                ErrorAction  = 'Stop'
            }
            $result = Install-ProvisioningPackage @installParams
            Write-PhaseLog "Install-ProvisioningPackage completed. Result: $($result | Out-String)"
        }
        else {
            # Fallback to provtool.exe if the cmdlet is unavailable
            $provtool = Join-Path $env:SystemRoot 'System32\provtool.exe'
            if (-not (Test-Path $provtool)) {
                throw "Neither Install-ProvisioningPackage nor provtool.exe is available on this system."
            }

            Write-PhaseLog "Using provtool.exe fallback..."
            $p = Start-Process -FilePath $provtool `
                               -ArgumentList @("`"$ProvisioningPack`"", '/quiet', '/force') `
                               -Wait -PassThru -NoNewWindow
            if ($p.ExitCode -ne 0) {
                throw "provtool.exe exited with code $($p.ExitCode)"
            }
            Write-PhaseLog "provtool.exe completed successfully."
        }
    }

    # -----------------------------------------------------------------------
    # 4. Register Phase 2 via RunOnce
    # -----------------------------------------------------------------------
    $phase2Script = Join-Path $MigrationPath 'Scripts\Phase2-EscrowBitlocker.ps1'
    # Also accept the repo location during development
    if (-not (Test-Path $phase2Script)) {
        $alt = Join-Path $repoRoot 'src\Scripts\Phase2-EscrowBitlocker.ps1'
        if (Test-Path $alt) { $phase2Script = $alt }
    }

    $runOnceKey  = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
    $runOnceName = 'DMU-Phase2-EscrowBitlocker'
    $psExe       = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $runOnceCmd  = "`"$psExe`" -NoProfile -ExecutionPolicy Bypass -File `"$phase2Script`""

    Write-PhaseLog "Registering RunOnce for Phase 2: $phase2Script"

    if ($PSCmdlet.ShouldProcess($runOnceName, 'Set RunOnce registry value')) {
        if (-not (Test-Path $runOnceKey)) {
            New-Item -Path $runOnceKey -Force | Out-Null
        }
        Set-ItemProperty -Path $runOnceKey -Name $runOnceName -Value $runOnceCmd -Force
        Write-PhaseLog "RunOnce entry created: $runOnceName"
    }

    # Copy the phase script into the migration working directory so it survives
    # even if the original repo folder is cleaned up later.
    $destScripts = Join-Path $MigrationPath 'Scripts'
    if (-not (Test-Path $destScripts)) {
        New-Item -Path $destScripts -ItemType Directory -Force | Out-Null
    }
    if ((Test-Path $phase2Script) -and $phase2Script -ne (Join-Path $destScripts 'Phase2-EscrowBitlocker.ps1')) {
        Copy-Item -Path $phase2Script -Destination (Join-Path $destScripts 'Phase2-EscrowBitlocker.ps1') -Force -ErrorAction SilentlyContinue
        Write-PhaseLog "Phase 2 script copied to $destScripts"
    }

    # -----------------------------------------------------------------------
    # 5. Summary & optional reboot
    # -----------------------------------------------------------------------
    Write-PhaseLog "=== Phase 1 completed successfully ===" -Level 'NOTICE'
    Write-PhaseLog "Provisioning package applied. Device should join Entra ID on next reboot / after processing."
    Write-PhaseLog "Phase 2 (BitLocker escrow) is registered via RunOnce."

    if (-not $SkipReboot) {
        Write-PhaseLog "Rebooting in 30 seconds to complete Entra Join and trigger Phase 2..." -Level 'NOTICE'
        if ($PSCmdlet.ShouldProcess('Computer', 'Restart')) {
            Start-Process -FilePath 'shutdown.exe' -ArgumentList '/r', '/t', '30', '/c', 'DMU Phase 1 complete – rebooting to finish Entra Join' -WindowStyle Hidden
        }
    }
    else {
        Write-PhaseLog "SkipReboot specified – please reboot manually to complete the join and run Phase 2." -Level 'WARNING'
    }

    [PSCustomObject]@{
        Success           = $true
        Phase             = 'Phase1-EntraJoin'
        ProvisioningPack  = $ProvisioningPack
        RunOnceRegistered = $true
        RebootScheduled   = -not $SkipReboot
        Timestamp         = Get-Date
    }
}
catch {
    Write-PhaseLog "Phase 1 failed: $($_.Exception.Message)" -Level 'ERROR'
    throw
}
finally {
    if ($logInfo -and (Get-Command Stop-Logging -ErrorAction SilentlyContinue)) {
        Stop-Logging -TranscriptPath $logInfo.TranscriptPath `
                     -InstanceName $logInfo.InstanceName `
                     -PSFEnabled:$logInfo.PSFEnabled
    }
}