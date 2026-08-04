BeforeAll {
    . (Join-Path $PSScriptRoot 'Helpers.ps1')
}

Describe 'Register-DMUScheduledTask' {
    It 'Is available as a function' {
        Get-Command Register-DMUScheduledTask | Should -Not -BeNullOrEmpty
    }

    It 'Supports expected parameters' {
        $cmd = Get-Command Register-DMUScheduledTask
        @('TaskName', 'ScriptPath', 'Arguments', 'TaskPath', 'Trigger', 'DelaySeconds', 'Force', 'WhatIf') |
            ForEach-Object { $cmd.Parameters.Keys | Should -Contain $_ }
    }

    It 'Trigger validates allowed values' {
        $cmd = Get-Command Register-DMUScheduledTask
        $attr = $cmd.Parameters['Trigger'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        $attr.ValidValues | Should -Contain 'AtStartup'
        $attr.ValidValues | Should -Contain 'AtLogon'
        $attr.ValidValues | Should -Contain 'Once'
        $attr.ValidValues | Should -Contain 'OnDemand'
    }

    It 'Does not throw under -WhatIf when script exists' {
        $scriptFile = Join-Path $TestDrive 'Phase2-EscrowBitlocker.ps1'
        "# placeholder" | Set-Content -Path $scriptFile

        {
            Register-DMUScheduledTask `
                -TaskName 'Pester-Phase2' `
                -ScriptPath $scriptFile `
                -Trigger OnDemand `
                -WhatIf
        } | Should -Not -Throw
    }
}

Describe 'Get-DMUScheduledTask' {
    It 'Is available and returns objects or nothing without error' {
        { Get-DMUScheduledTask } | Should -Not -Throw
    }
}

Describe 'Unregister-DMUScheduledTask' {
    It 'Supports -WhatIf and -IncludeLegacy' {
        $cmd = Get-Command Unregister-DMUScheduledTask
        $cmd.Parameters.Keys | Should -Contain 'WhatIf'
        $cmd.Parameters.Keys | Should -Contain 'IncludeLegacy'
        $cmd.Parameters.Keys | Should -Contain 'RemoveFolder'
    }

    It 'Does not throw under -WhatIf' {
        { Unregister-DMUScheduledTask -WhatIf } | Should -Not -Throw
    }
}

Describe 'Register-MigrationPhaseTasks' {
    It 'Is available as a function' {
        Get-Command Register-MigrationPhaseTasks | Should -Not -BeNullOrEmpty
    }

    It 'Supports Phases, Trigger, Force parameters' {
        $cmd = Get-Command Register-MigrationPhaseTasks
        @('MigrationPath', 'ConfigPath', 'Phases', 'Trigger', 'Force') |
            ForEach-Object { $cmd.Parameters.Keys | Should -Contain $_ }
    }

    It 'Skips missing phase scripts without throwing' {
        $emptyRoot = Join-Path $TestDrive 'EmptyMigration'
        New-Item -Path (Join-Path $emptyRoot 'Scripts') -ItemType Directory -Force | Out-Null

        {
            Register-MigrationPhaseTasks -MigrationPath $emptyRoot -Phases 2 -WhatIf
        } | Should -Not -Throw
    }
}

Describe 'Start-DeviceMigration scheduled-task parameter' {
    It 'Exposes -UseScheduledTasks' {
        $cmd = Get-Command Start-DeviceMigration
        $cmd.Parameters.Keys | Should -Contain 'UseScheduledTasks'
    }
}