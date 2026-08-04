BeforeAll {
    . (Join-Path $PSScriptRoot 'Helpers.ps1')
}

Describe 'New-StrongPassword' {
    It 'Returns a SecureString' {
        $result = New-StrongPassword
        $result | Should -BeOfType System.Security.SecureString
    }

    It 'Honors the requested length (default 24)' {
        $secure = New-StrongPassword -Length 24
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try {
            $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            $plain.Length | Should -Be 24
        }
        finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }

    It 'Honors a custom length of 32' {
        $secure = New-StrongPassword -Length 32
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try {
            $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            $plain.Length | Should -Be 32
        }
        finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }

    It 'Rejects lengths below 16' {
        { New-StrongPassword -Length 8 } | Should -Throw
    }

    It 'Produces different passwords on successive calls' {
        $a = New-StrongPassword -Length 20
        $b = New-StrongPassword -Length 20
        $bstrA = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($a)
        $bstrB = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($b)
        try {
            $plainA = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstrA)
            $plainB = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstrB)
            $plainA | Should -Not -Be $plainB
        }
        finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstrA)
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstrB)
        }
    }

    It 'Includes at least one digit when special chars are enabled' {
        $secure = New-StrongPassword -Length 24 -IncludeSpecial $true
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try {
            $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            $plain | Should -Match '\d'
        }
        finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }

    It 'Is marked read-only' {
        $secure = New-StrongPassword
        $secure.IsReadOnly() | Should -BeTrue
    }
}