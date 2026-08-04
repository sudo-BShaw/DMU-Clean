BeforeAll {
    . (Join-Path $PSScriptRoot 'Helpers.ps1')
}

Describe 'Start-DeviceMigration' {
    It 'Is available as a function' {
        Get-Command Start-DeviceMigration | Should -Not -BeNullOrEmpty
    }

    It 'Supports expected parameters' {
        $cmd = Get-Command Start-DeviceMigration
        @('ConfigPath', 'ForceCleanup', 'SkipStatusCheck', 'LaunchPhase1', 'SkipReboot', 'WhatIf') | ForEach-Object {
            $cmd.Parameters.Keys | Should -Contain $_
        }
    }

    It 'Throws when config file is missing' {
        $missing = Join-Path $TestDrive 'does-not-exist.psd1'
        { Start-DeviceMigration -ConfigPath $missing -SkipStatusCheck -WhatIf } | Should -Throw
    }

    It 'Throws when TenantID is still the placeholder' {
        $cfgPath = Join-Path $TestDrive 'MigrationConfig.psd1'
        @'
@{
    TenantID         = '00000000-0000-0000-0000-000000000000'
    MigrationPath    = 'C:\ProgramData\AADMigration'
    LogsPath         = 'C:\Logs'
    JobName          = 'AAD_Migration'
    TempUser         = 'MigrationInProgress'
    UseOneDriveKFM   = $true
    InstallOneDrive  = $true
    ProvisioningPack = ''
}
'@ | Set-Content -Path $cfgPath -Encoding UTF8

        { Start-DeviceMigration -ConfigPath $cfgPath -SkipStatusCheck -WhatIf } | Should -Throw
    }
}