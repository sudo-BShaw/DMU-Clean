function Enable-OneDriveKFM {
    <#
    .SYNOPSIS
        Applies registry settings that encourage OneDrive Known Folder Move (KFM).

    .DESCRIPTION
        Sets the common machine-wide policy values used by Intune / Group Policy
        to silently move Desktop, Documents, and Pictures into OneDrive.

        These settings take full effect once the OneDrive client runs in the
        user context and the tenant policies allow KFM. They are safe no-ops
        when KFM is already enforced by Intune.

    .PARAMETER TenantID
        Optional Entra tenant ID. When supplied, the "KFMOptInWithWizard" /
        silent-opt-in style values are scoped more tightly.

    .PARAMETER Desktop
    .PARAMETER Documents
    .PARAMETER Pictures
        Include or exclude specific known folders (default: all three on).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$TenantID,

        [bool]$Desktop   = $true,
        [bool]$Documents = $true,
        [bool]$Pictures  = $true
    )

    $policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\OneDrive'

    if ($PSCmdlet.ShouldProcess($policyPath, 'Ensure OneDrive KFM policy keys')) {
        if (-not (Test-Path $policyPath)) {
            New-Item -Path $policyPath -Force | Out-Null
        }

        # Silently move known folders to OneDrive
        # 0 = disabled, 1 = enabled (prompt), 2 = enabled (no prompt) – values vary by Windows build;
        # the widely used combination is KFMSilentOptIn = TenantID + per-folder flags.
        if ($TenantID -and $TenantID -ne '00000000-0000-0000-0000-000000000000') {
            Set-ItemProperty -Path $policyPath -Name 'KFMSilentOptIn' -Value $TenantID -Type String -Force
            Write-Verbose "KFMSilentOptIn set to tenant $TenantID"
        }

        $folderMap = @{
            'KFMSilentOptInDesktop'   = [int]$Desktop
            'KFMSilentOptInDocuments' = [int]$Documents
            'KFMSilentOptInPictures'  = [int]$Pictures
        }

        foreach ($name in $folderMap.Keys) {
            Set-ItemProperty -Path $policyPath -Name $name -Value $folderMap[$name] -Type DWord -Force
            Write-Verbose "$name = $($folderMap[$name])"
        }

        # Prevent users from redirecting folders back offline (optional hardening)
        Set-ItemProperty -Path $policyPath -Name 'KFMBlockOptOut' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

        return $true
    }

    return $false
}