function Start-DeviceMigration {
    <#
    .SYNOPSIS
        Main orchestrator for the Device Migration Utility (DMU).

    .DESCRIPTION
        Coordinates the high-level steps required to migrate a Windows device
        from Workgroup / Domain Join / Hybrid Join to Entra ID Join + Intune
        while preserving user data.

        This is the cleaned, modular entry point. It:
        - Loads configuration
        - Initializes consistent logging
        - Verifies the device still needs migration
        - Optionally cleans previous artifacts
        - Creates a temporary local admin with a strong random password
        - Prepares the migration working directory
        - Sets up phase placeholders / scheduled-task scaffolding
        - Provides clear extension points for the remaining phase scripts

    .PARAMETER ConfigPath
        Full path to MigrationConfig.psd1. Defaults to .\config\MigrationConfig.psd1
        relative to the repository root.

    .PARAMETER ForceCleanup
        Remove previous migration artifacts before starting.

    .PARAMETER SkipStatusCheck
        Skip the dsregcmd-based status check (useful for testing).

    .PARAMETER WhatIf
        Show what would happen without making changes.

    .EXAMPLE
        Start-DeviceMigration -ForceCleanup

    .EXAMPLE
        Start-DeviceMigration -ConfigPath 'C:\DMU\config\MigrationConfig.psd1'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$ConfigPath,

        [switch]$ForceCleanup,

        [switch]$SkipStatusCheck
    )

    $ErrorActionPreference = 'Stop'
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    if (-not $repoRoot) { $repoRoot = $PWD.Path }

    # ------------------------------------------------------------------
    # 1. Configuration
    # ------------------------------------------------------------------
    if (-not $ConfigPath) {
        $ConfigPath = Join-Path $repoRoot 'config\MigrationConfig.psd1'
    }

    if (-not (Test-Path -Path $ConfigPath)) {
        $example = Join-Path $repoRoot 'config\MigrationConfig.example.psd1'
        throw @"
Configuration file not found: $ConfigPath

Copy the example and fill in real values (never commit secrets):
    Copy-Item '$example' '$ConfigPath'
"@
    }

    $config = Import-PowerShellDataFile -Path $ConfigPath

    $MigrationPath       = if ($config.MigrationPath)       { $config.MigrationPath }       else { 'C:\ProgramData\AADMigration' }
    $LogsPath            = if ($config.LogsPath)            { $config.LogsPath }            else { 'C:\Logs' }
    $JobName             = if ($config.JobName)             { $config.JobName }             else { 'AAD_Migration' }
    $TempUserName        = if ($config.TempUser)            { $config.TempUser }            else { 'MigrationInProgress' }
    $TenantID            = $config.TenantID
    $UseOneDriveKFM      = [bool]$config.UseOneDriveKFM
    $InstallOneDrive     = [bool]$config.InstallOneDrive
    $ProvisioningPack    = $config.ProvisioningPack
    $ProvisioningPackName = $config.ProvisioningPackName

    if (-not $TenantID -or $TenantID -eq '00000000-0000-0000-0000-000000000000') {
        throw "TenantID is missing or still set to the example placeholder. Edit $ConfigPath"
    }

    # ------------------------------------------------------------------
    # 2. Logging
    # ------------------------------------------------------------------
    $logInfo = Initialize-Logging -JobName $JobName -LogsPath $LogsPath -ParentScriptName 'Start-DeviceMigration' -UsePSFramework

    function Write-DMU {
        param([string]$Message, [string]$Level = 'INFO')
        if (Get-Command Write-DMULog -ErrorAction SilentlyContinue) {
            Write-DMULog -Message $Message -Level $Level
        }
        else {
            $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            Write-Host "[$ts] [$Level] $Message"
        }
    }

    Write-DMU "=== Device Migration Utility (Clean Edition) started ===" -Level 'NOTICE'
    Write-DMU "Config      : $ConfigPath"
    Write-DMU "TenantID    : $TenantID"
    Write-DMU "MigrationPath: $MigrationPath"
    Write-DMU "JobName     : $JobName"

    try {
        # --------------------------------------------------------------
        # 3. Optional cleanup of previous run
        # --------------------------------------------------------------
        if ($ForceCleanup) {
            Write-DMU "ForceCleanup requested – removing previous artifacts..." -Level 'NOTICE'
            if ($PSCmdlet.ShouldProcess('Migration artifacts', 'Remove')) {
                Remove-MigrationArtifacts `
                    -MigrationPath $MigrationPath `
                    -LogsPath $LogsPath `
                    -JobName $JobName `
                    -TempUserName $TempUserName `
                    -Verbose
            }
        }

        # --------------------------------------------------------------
        # 4. Device status check
        # --------------------------------------------------------------
        if (-not $SkipStatusCheck) {
            Write-DMU "Checking current device join / enrollment status..."
            $status = Get-DeviceJoinStatus
            Write-DMU "Join type: $($status.JoinType) | MDM: $($status.IsMDMEnrolled) | NeedsMigration: $($status.NeedsMigration)"

            if (-not $status.NeedsMigration) {
                Write-DMU "Device is already fully Entra-joined and Intune-enrolled. Exiting." -Level 'NOTICE'
                return
            }
        }

        # --------------------------------------------------------------
        # 5. Prepare working directories
        # --------------------------------------------------------------
        $dirs = @(
            $MigrationPath,
            (Join-Path $MigrationPath 'Files'),
            (Join-Path $MigrationPath 'Scripts'),
            (Join-Path $MigrationPath 'Logs'),
            $LogsPath
        )
        foreach ($dir in $dirs) {
            if (-not (Test-Path $dir)) {
                if ($PSCmdlet.ShouldProcess($dir, 'Create directory')) {
                    New-Item -Path $dir -ItemType Directory -Force | Out-Null
                    Write-DMU "Created directory: $dir"
                }
            }
        }

        # --------------------------------------------------------------
        # 6. Temporary local admin account (strong random password)
        # --------------------------------------------------------------
        Write-DMU "Ensuring temporary local account '$TempUserName' exists with a strong password..."

        $securePass = New-StrongPassword -Length 24

        $existingUser = Get-LocalUser -Name $TempUserName -ErrorAction SilentlyContinue
        if ($existingUser) {
            if ($PSCmdlet.ShouldProcess($TempUserName, 'Reset password')) {
                $existingUser | Set-LocalUser -Password $securePass
                Write-DMU "Password reset for existing account $TempUserName"
            }
        }
        else {
            if ($PSCmdlet.ShouldProcess($TempUserName, 'Create local user')) {
                New-LocalUser -Name $TempUserName `
                              -Password $securePass `
                              -FullName 'DMU Migration Account' `
                              -Description 'Temporary account used by Device Migration Utility' `
                              -PasswordNeverExpires `
                              -UserMayNotChangePassword | Out-Null

                Add-LocalGroupMember -Group 'Administrators' -Member $TempUserName -ErrorAction SilentlyContinue
                Write-DMU "Created local administrator account: $TempUserName"
            }
        }

        # Note: the clear-text password is never written to disk or logs.
        # Callers that need the password for autologon should receive the SecureString.

        # --------------------------------------------------------------
        # 7. Copy / validate provisioning package path
        # --------------------------------------------------------------
        if ($ProvisioningPack) {
            if (Test-Path -Path $ProvisioningPack) {
                Write-DMU "Provisioning package found: $ProvisioningPack"
            }
            else {
                Write-DMU "Provisioning package not found at '$ProvisioningPack'. Phase 1 will fail until it is present." -Level 'WARNING'
            }
        }
        else {
            Write-DMU "No ProvisioningPack path defined in config. You must supply a PPKG for Entra Join." -Level 'WARNING'
        }

        # --------------------------------------------------------------
        # 8. High-level phase scaffolding
        #    (actual phase scripts will be migrated next)
        # --------------------------------------------------------------
        Write-DMU "=== Migration phases (scaffolding) ===" -Level 'NOTICE'

        $phases = @(
            @{ Name = 'Phase0-Prep';           Description = 'Prepare directories, temp user, config' },
            @{ Name = 'Phase1-EntraJoin';      Description = 'Apply PPKG / Entra Join + RunOnce hand-off' },
            @{ Name = 'Phase2-EscrowBitlocker'; Description = 'Escrow BitLocker recovery key to new tenant' },
            @{ Name = 'Phase3-OneDrive';        Description = 'OneDrive KFM / sync status / user file backup' },
            @{ Name = 'Phase4-Cleanup';        Description = 'Remove temp user, scheduled tasks, artifacts' }
        )

        foreach ($phase in $phases) {
            Write-DMU "  • $($phase.Name) – $($phase.Description)"
        }

        Write-DMU "Phase scripts live under src/Scripts/ and will be invoked by scheduled tasks / RunOnce." -Level 'NOTICE'

        # Placeholder for future scheduled-task creation
        # Create-MigrationScheduledTasks -MigrationPath $MigrationPath -JobName $JobName ...

        # --------------------------------------------------------------
        # 9. Summary
        # --------------------------------------------------------------
        Write-DMU "=== Start-DeviceMigration completed successfully ===" -Level 'NOTICE'
        Write-DMU "Next actions:"
        Write-DMU "  1. Ensure a valid PPKG is available at the configured path."
        Write-DMU "  2. Implement / migrate the Phase* scripts under src/Scripts/."
        Write-DMU "  3. Create the interactive / SYSTEM scheduled tasks that call those phases."
        Write-DMU "  4. Prefer Windows LAPS for ongoing local admin password management."

        # Return useful information for callers / testing
        [PSCustomObject]@{
            Success            = $true
            TenantID           = $TenantID
            MigrationPath      = $MigrationPath
            TempUserName       = $TempUserName
            LogsPath           = $LogsPath
            ProvisioningPack   = $ProvisioningPack
            Timestamp          = Get-Date
        }
    }
    catch {
        Write-DMU "Fatal error in Start-DeviceMigration: $($_.Exception.Message)" -Level 'ERROR'
        throw
    }
    finally {
        if ($logInfo) {
            Stop-Logging -TranscriptPath $logInfo.TranscriptPath `
                         -InstanceName $logInfo.InstanceName `
                         -PSFEnabled:$logInfo.PSFEnabled
        }
    }
}