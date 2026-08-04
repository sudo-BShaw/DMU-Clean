BeforeAll {
    . (Join-Path $PSScriptRoot 'Helpers.ps1')
}

Describe 'Enable-OneDriveKFM' {
    It 'Is a command that supports -WhatIf' {
        $cmd = Get-Command Enable-OneDriveKFM
        $cmd.Parameters.Keys | Should -Contain 'WhatIf'
    }

    It 'Supports TenantID, Desktop, Documents, Pictures parameters' {
        $cmd = Get-Command Enable-OneDriveKFM
        $cmd.Parameters.Keys | Should -Contain 'TenantID'
        $cmd.Parameters.Keys | Should -Contain 'Desktop'
        $cmd.Parameters.Keys | Should -Contain 'Documents'
        $cmd.Parameters.Keys | Should -Contain 'Pictures'
    }

    It 'Does not throw when called with -WhatIf' {
        { Enable-OneDriveKFM -TenantID '00000000-0000-0000-0000-000000000001' -WhatIf } |
            Should -Not -Throw
    }

    It 'Returns $false under -WhatIf (ShouldProcess declines write)' {
        # With -WhatIf, ShouldProcess returns false in non-confirm context for the write path
        $result = Enable-OneDriveKFM -WhatIf
        # Function returns $true only when ShouldProcess allows the write; under WhatIf it returns $false
        $result | Should -BeFalse
    }
}