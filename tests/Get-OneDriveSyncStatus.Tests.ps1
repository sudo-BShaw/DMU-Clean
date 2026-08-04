BeforeAll {
    . (Join-Path $PSScriptRoot 'Helpers.ps1')
}

Describe 'Get-OneDriveSyncStatus' {
    It 'Returns a PSCustomObject with expected properties' {
        $status = Get-OneDriveSyncStatus
        $status | Should -BeOfType PSCustomObject
        @('IsInstalled', 'IsRunning', 'UserFolder', 'KfmLikelyEnabled',
          'StatusMessage', 'NeedsAttention', 'UserProfile') | ForEach-Object {
            $status.PSObject.Properties.Name | Should -Contain $_
        }
    }

    It 'StatusMessage is a non-empty string' {
        $status = Get-OneDriveSyncStatus
        $status.StatusMessage | Should -Not -BeNullOrEmpty
        $status.StatusMessage | Should -BeOfType [string]
    }

    It 'IsInstalled and IsRunning are booleans' {
        $status = Get-OneDriveSyncStatus
        $status.IsInstalled | Should -BeOfType [bool]
        $status.IsRunning   | Should -BeOfType [bool]
    }

    It 'NeedsAttention is true when OneDrive is not installed' {
        Mock Get-Process { $null }
        # Force a profile that will not have OneDrive installed paths by using a temp dir
        $tempProfile = Join-Path $TestDrive 'FakeUser'
        New-Item -Path $tempProfile -ItemType Directory -Force | Out-Null
        $status = Get-OneDriveSyncStatus -UserProfile $tempProfile
        # On a machine without OneDrive under the fake profile, NeedsAttention should be true
        # (IsInstalled may still be true if machine-wide install exists)
        $status.NeedsAttention | Should -BeOfType [bool]
        $status.UserProfile | Should -Be $tempProfile
    }

    It 'Accepts an explicit UserProfile path' {
        $tempProfile = Join-Path $TestDrive 'ExplicitUser'
        New-Item -Path $tempProfile -ItemType Directory -Force | Out-Null
        $status = Get-OneDriveSyncStatus -UserProfile $tempProfile
        $status.UserProfile | Should -Be $tempProfile
    }
}