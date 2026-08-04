@{
    RootModule        = 'DMU.psm1'
    ModuleVersion     = '0.6.0'
    GUID              = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author            = 'Brandon Shaw / Community'
    CompanyName       = 'Community'
    Copyright         = '(c) 2026. MIT License.'
    Description       = 'Device Migration Utility (DMU) - Clean modular edition for Workgroup/Domain/Hybrid to Entra Join + Intune migration.'
    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        'Start-DeviceMigration',
        'Get-DeviceJoinStatus',
        'Show-DeviceJoinStatus',
        'Remove-MigrationArtifacts',
        'New-StrongPassword',
        'Initialize-Logging',
        'Stop-Logging',
        'Invoke-BitLockerEscrow',
        'Get-OneDriveSyncStatus',
        'Enable-OneDriveKFM',
        'Register-DMUScheduledTask',
        'Get-DMUScheduledTask',
        'Unregister-DMUScheduledTask',
        'Register-MigrationPhaseTasks'
    )

    PrivateData = @{
        PSData = @{
            Tags         = @('Intune', 'EntraID', 'AzureAD', 'Migration', 'DeviceManagement', 'BitLocker', 'OneDrive')
            LicenseUri   = 'https://opensource.org/licenses/MIT'
            ProjectUri   = 'https://github.com/sudo-BShaw/DMU-Clean'
            ReleaseNotes = 'v0.6.0 – Scheduled-task helpers (Register/Get/Unregister-DMUScheduledTask, Register-MigrationPhaseTasks) and -UseScheduledTasks on the orchestrator.'
        }
    }
}