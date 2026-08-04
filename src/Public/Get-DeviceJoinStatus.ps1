function Get-DeviceJoinStatus {
    <#
    .SYNOPSIS
        Retrieves the current device join and MDM enrollment status.

    .DESCRIPTION
        Parses the output of `dsregcmd /status` to determine whether the device is
        Workgroup, Azure AD (Entra) Joined, Hybrid Joined, or On-premises Domain Joined,
        and whether it is enrolled in Intune (MDM).

    .OUTPUTS
        PSCustomObject with the following properties:
        - IsWorkgroup      [bool]
        - IsAzureADJoined  [bool]
        - IsHybridJoined   [bool]
        - IsOnPremJoined   [bool]
        - IsMDMEnrolled    [bool]
        - JoinType         [string]  (Workgroup | AzureAD | Hybrid | OnPrem)
        - NeedsMigration   [bool]    (true when not fully Entra-joined + Intune enrolled)

    .EXAMPLE
        $status = Get-DeviceJoinStatus
        if (-not $status.NeedsMigration) {
            Write-Host "Device is already fully cloud-joined and enrolled."
        }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $dsregcmdOutput = & dsregcmd.exe /status 2>$null

    $isAzureADJoined = $dsregcmdOutput -match '.*AzureAdJoined\s*:\s*YES'
    $isDomainJoined  = $dsregcmdOutput -match '.*DomainJoined\s*:\s*YES'
    $isHybridJoined  = $isDomainJoined -and $isAzureADJoined
    $isOnPremJoined  = $isDomainJoined -and -not $isAzureADJoined
    $isWorkgroup     = -not ($isAzureADJoined -or $isHybridJoined -or $isOnPremJoined)

    # Common Intune / MDM enrollment URLs
    $isMDMEnrolled = $dsregcmdOutput -match '.*MDMUrl\s*:\s*(https://manage\.microsoft\.com|https://enrollment\.manage\.microsoft\.com)'

    $joinType = switch ($true) {
        $isHybridJoined { 'Hybrid' }
        $isAzureADJoined { 'AzureAD' }
        $isOnPremJoined { 'OnPrem' }
        default { 'Workgroup' }
    }

    # Fully migrated = pure Entra Join + Intune enrolled
    $needsMigration = -not ($isAzureADJoined -and -not $isHybridJoined -and $isMDMEnrolled)

    [PSCustomObject]@{
        IsWorkgroup     = $isWorkgroup
        IsAzureADJoined = $isAzureADJoined
        IsHybridJoined  = $isHybridJoined
        IsOnPremJoined  = $isOnPremJoined
        IsMDMEnrolled   = $isMDMEnrolled
        JoinType        = $joinType
        NeedsMigration  = $needsMigration
    }
}

# Convenience wrapper that prints a human-readable summary (useful for detection scripts)
function Show-DeviceJoinStatus {
    [CmdletBinding()]
    param()

    $status = Get-DeviceJoinStatus

    switch ($status.JoinType) {
        'Workgroup' { Write-Output "Device is Workgroup joined (not Azure AD, Hybrid, or On-prem Joined)." }
        'AzureAD'   { Write-Output "Device is Azure AD (Entra) Joined." }
        'Hybrid'    { Write-Output "Device is Hybrid Joined (both On-prem and Azure AD Joined)." }
        'OnPrem'    { Write-Output "Device is On-premises Domain Joined only." }
    }

    if ($status.IsMDMEnrolled) {
        Write-Output "Device is Intune Enrolled."
    }
    else {
        Write-Output "Device is NOT Intune Enrolled."
    }

    if (-not $status.NeedsMigration) {
        Write-Output "Device is Azure AD Joined and Intune Enrolled. No migration needed."
        return 0
    }
    else {
        Write-Output "Migration is recommended / required."
        return 1
    }
}