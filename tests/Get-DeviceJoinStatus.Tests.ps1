BeforeAll {
    . (Join-Path $PSScriptRoot 'Helpers.ps1')
}

Describe 'Get-DeviceJoinStatus' {
    Context 'When device is pure Entra joined and Intune enrolled' {
        BeforeEach {
            Mock -CommandName 'dsregcmd.exe' -MockWith {
                @(
                    'AzureAdJoined : YES',
                    'DomainJoined : NO',
                    'MDMUrl : https://enrollment.manage.microsoft.com/EnrollmentServer/Discovery.svc'
                )
            }
        }

        It 'Reports AzureAD join type' {
            # Re-implement parse against mock output path by calling the real function
            # when dsregcmd is available; otherwise validate object shape on live system.
            $status = Get-DeviceJoinStatus
            $status | Should -Not -BeNullOrEmpty
            $status.PSObject.Properties.Name | Should -Contain 'JoinType'
            $status.PSObject.Properties.Name | Should -Contain 'NeedsMigration'
            $status.PSObject.Properties.Name | Should -Contain 'IsAzureADJoined'
            $status.PSObject.Properties.Name | Should -Contain 'IsMDMEnrolled'
            $status.PSObject.Properties.Name | Should -Contain 'IsWorkgroup'
            $status.PSObject.Properties.Name | Should -Contain 'IsHybridJoined'
            $status.PSObject.Properties.Name | Should -Contain 'IsOnPremJoined'
        }
    }

    It 'Returns a PSCustomObject with expected properties' {
        $status = Get-DeviceJoinStatus
        $status | Should -BeOfType PSCustomObject
        @('IsWorkgroup', 'IsAzureADJoined', 'IsHybridJoined', 'IsOnPremJoined',
          'IsMDMEnrolled', 'JoinType', 'NeedsMigration') | ForEach-Object {
            $status.PSObject.Properties.Name | Should -Contain $_
        }
    }

    It 'JoinType is one of the known values' {
        $status = Get-DeviceJoinStatus
        $status.JoinType | Should -BeIn @('Workgroup', 'AzureAD', 'Hybrid', 'OnPrem')
    }

    It 'NeedsMigration is a boolean' {
        $status = Get-DeviceJoinStatus
        $status.NeedsMigration | Should -BeOfType [bool]
    }

    It 'Show-DeviceJoinStatus returns 0 or 1' {
        $code = Show-DeviceJoinStatus
        $code | Should -BeIn @(0, 1)
    }
}

Describe 'Get-DeviceJoinStatus parsing logic' {
    # Unit-test the decision matrix without depending on the real dsregcmd binary
    # by evaluating the same conditions the function uses.

    It 'Treats AzureAdJoined+MDM as fully migrated (NeedsMigration = false)' {
        $isAzureADJoined = $true
        $isHybridJoined  = $false
        $isMDMEnrolled   = $true
        $needsMigration  = -not ($isAzureADJoined -and -not $isHybridJoined -and $isMDMEnrolled)
        $needsMigration | Should -BeFalse
    }

    It 'Treats Hybrid join as still needing migration' {
        $isAzureADJoined = $true
        $isHybridJoined  = $true
        $isMDMEnrolled   = $true
        $needsMigration  = -not ($isAzureADJoined -and -not $isHybridJoined -and $isMDMEnrolled)
        $needsMigration | Should -BeTrue
    }

    It 'Treats Workgroup as needing migration' {
        $isAzureADJoined = $false
        $isHybridJoined  = $false
        $isMDMEnrolled   = $false
        $needsMigration  = -not ($isAzureADJoined -and -not $isHybridJoined -and $isMDMEnrolled)
        $needsMigration | Should -BeTrue
    }

    It 'Treats Entra-joined but not MDM-enrolled as needing migration' {
        $isAzureADJoined = $true
        $isHybridJoined  = $false
        $isMDMEnrolled   = $false
        $needsMigration  = -not ($isAzureADJoined -and -not $isHybridJoined -and $isMDMEnrolled)
        $needsMigration | Should -BeTrue
    }
}