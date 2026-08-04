BeforeAll {
    . (Join-Path $PSScriptRoot 'Helpers.ps1')
}

Describe 'Remove-MigrationArtifacts' {
    It 'Is available as a function' {
        Get-Command Remove-MigrationArtifacts | Should -Not -BeNullOrEmpty
    }

    It 'Supports -WhatIf' {
        $cmd = Get-Command Remove-MigrationArtifacts
        $cmd.Parameters.Keys | Should -Contain 'WhatIf'
    }

    It 'Accepts MigrationPath, LogsPath, TempUserName parameters' {
        $cmd = Get-Command Remove-MigrationArtifacts
        $cmd.Parameters.Keys | Should -Contain 'MigrationPath'
        $cmd.Parameters.Keys | Should -Contain 'LogsPath'
        $cmd.Parameters.Keys | Should -Contain 'TempUserName'
        $cmd.Parameters.Keys | Should -Contain 'JobName'
    }

    It 'Does not throw under -WhatIf with isolated paths' {
        $mig = Join-Path $TestDrive 'AADMigration'
        $logs = Join-Path $TestDrive 'Logs'
        New-Item -Path $mig -ItemType Directory -Force | Out-Null
        New-Item -Path $logs -ItemType Directory -Force | Out-Null

        {
            Remove-MigrationArtifacts `
                -MigrationPath $mig `
                -LogsPath $logs `
                -TempPath (Join-Path $TestDrive 'temp') `
                -JobName 'PesterJob' `
                -TempUserName 'PesterTempUserThatShouldNotExist' `
                -WhatIf
        } | Should -Not -Throw
    }

    It 'Removes an isolated migration path when not using -WhatIf' {
        $mig = Join-Path $TestDrive 'AADMigration-Real'
        New-Item -Path $mig -ItemType Directory -Force | Out-Null
        'test' | Set-Content (Join-Path $mig 'marker.txt')

        Remove-MigrationArtifacts `
            -MigrationPath $mig `
            -LogsPath (Join-Path $TestDrive 'Logs-Real-Keep') `
            -TempPath (Join-Path $TestDrive 'temp-real') `
            -JobName 'PesterJob2' `
            -TempUserName 'PesterTempUserThatShouldNotExist'

        Test-Path $mig | Should -BeFalse
    }
}