function New-StrongPassword {
    <#
    .SYNOPSIS
        Generates a cryptographically strong random password.

    .DESCRIPTION
        Replaces the original hardcoded weak password ("Default1234").
        Uses RNGCryptoServiceProvider for secure randomness.

    .PARAMETER Length
        Desired password length (default 24, minimum 16).

    .PARAMETER IncludeSpecial
        Include special characters (default $true).

    .OUTPUTS
        System.Security.SecureString
    #>
    [CmdletBinding()]
    [OutputType([System.Security.SecureString])]
    param(
        [ValidateRange(16, 128)]
        [int]$Length = 24,

        [bool]$IncludeSpecial = $true
    )

    $lower   = 'abcdefghijklmnopqrstuvwxyz'
    $upper   = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    $digits  = '0123456789'
    $special = '!@#$%^&*()-_=+[]{}'

    $charSet = $lower + $upper + $digits
    if ($IncludeSpecial) { $charSet += $special }

    $bytes = New-Object byte[] $Length
    $rng   = [System.Security.Cryptography.RNGCryptoServiceProvider]::Create()
    $rng.GetBytes($bytes)

    $passwordChars = for ($i = 0; $i -lt $Length; $i++) {
        $charSet[$bytes[$i] % $charSet.Length]
    }

    # Guarantee at least one of each required class
    $passwordChars[0] = $lower[(Get-Random -Maximum $lower.Length)]
    $passwordChars[1] = $upper[(Get-Random -Maximum $upper.Length)]
    $passwordChars[2] = $digits[(Get-Random -Maximum $digits.Length)]
    if ($IncludeSpecial) {
        $passwordChars[3] = $special[(Get-Random -Maximum $special.Length)]
    }

    # Shuffle
    $passwordChars = $passwordChars | Get-Random -Count $passwordChars.Count

    $secure = New-Object System.Security.SecureString
    foreach ($c in $passwordChars) {
        $secure.AppendChar($c)
    }
    $secure.MakeReadOnly()

    return $secure
}