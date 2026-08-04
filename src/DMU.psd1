@{
    RootModule        = 'DMU.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author            = 'Brandon Shaw / Community'
    CompanyName       = 'Community'
    Copyright         = '(c) 2026. MIT License.'
    Description       = 'Device Migration Utility (DMU) - Clean modular edition for Workgroup/Domain/Hybrid to Entra Join + Intune migration.'
    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        'Get-DeviceJoinStatus',
        'Show-DeviceJoinStatus',
        'Remove-MigrationArtifacts',
        'New-StrongPassword',
        'Initialize-Logging',
        'Stop-Logging'
        # 'Start-DeviceMigration'   # coming soon
    )

    PrivateData = @{
        PSData = @{
            Tags         = @('Intune', 'EntraID', 'AzureAD', 'Migration', 'DeviceManagement')
            LicenseUri   = 'https://opensource.org/licenses/MIT'
            ProjectUri   = 'https://github.com/sudo-BShaw/DMU-Clean'
            ReleaseNotes = 'Initial clean structure and core helpers.'
        }
    }
}