function Get-OneDriveSyncStatus {
    <#
    .SYNOPSIS
        Best-effort check of OneDrive client presence and basic sync health.

    .DESCRIPTION
        Does not depend on third-party ODSyncUtil binaries. Uses process state,
        known folder paths, and the OneDrive settings registry to report a
        practical status suitable for migration gating.

    .PARAMETER UserProfile
        Profile path to inspect. Defaults to the currently loaded user profile
        or the most recently used interactive profile when running as SYSTEM.

    .OUTPUTS
        PSCustomObject with IsInstalled, IsRunning, UserFolder, KfmLikelyEnabled,
        StatusMessage, and NeedsAttention.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [string]$UserProfile
    )

    if (-not $UserProfile) {
        if ($env:USERPROFILE -and $env:USERPROFILE -notmatch 'systemprofile') {
            $UserProfile = $env:USERPROFILE
        }
        else {
            # Under SYSTEM, pick the most recently modified profile under C:\Users
            $candidate = Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notin @('Public', 'Default', 'Default User', 'All Users') } |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
            $UserProfile = if ($candidate) { $candidate.FullName } else { $null }
        }
    }

    $result = [PSCustomObject]@{
        IsInstalled      = $false
        IsRunning        = $false
        UserFolder       = $null
        KfmLikelyEnabled = $false
        StatusMessage    = ''
        NeedsAttention   = $true
        UserProfile      = $UserProfile
    }

    # Installation paths
    $installPaths = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDrive.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft OneDrive\OneDrive.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft OneDrive\OneDrive.exe')
    )
    foreach ($p in $installPaths) {
        if ($p -and (Test-Path $p)) {
            $result.IsInstalled = $true
            break
        }
    }

    $result.IsRunning = [bool](Get-Process -Name 'OneDrive' -ErrorAction SilentlyContinue)

    # Typical OneDrive business / personal folder under the profile
    if ($UserProfile) {
        $odRoots = Get-ChildItem -Path $UserProfile -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^OneDrive' }
        if ($odRoots) {
            $result.UserFolder = ($odRoots | Select-Object -First 1).FullName
        }
    }

    # KFM indicators in HKCU (best-effort; may be empty under SYSTEM)
    try {
        $kfmKey = 'HKCU:\Software\Microsoft\OneDrive\Accounts'
        if (Test-Path $kfmKey) {
            $accounts = Get-ChildItem $kfmKey -ErrorAction SilentlyContinue
            foreach ($acc in $accounts) {
                $props = Get-ItemProperty -Path $acc.PSPath -ErrorAction SilentlyContinue
                if ($props.PSObject.Properties.Name -contains 'KfmFoldersProtected' -or
                    $props.PSObject.Properties.Name -contains 'KfmFoldersBackupDone') {
                    $result.KfmLikelyEnabled = $true
                    break
                }
            }
        }
    }
    catch {
        # Registry may be inaccessible under SYSTEM for a specific user hive
    }

    # Compose status
    if (-not $result.IsInstalled) {
        $result.StatusMessage  = 'OneDrive client does not appear to be installed.'
        $result.NeedsAttention = $true
    }
    elseif (-not $result.IsRunning) {
        $result.StatusMessage  = 'OneDrive is installed but not currently running.'
        $result.NeedsAttention = $true
    }
    elseif (-not $result.UserFolder) {
        $result.StatusMessage  = 'OneDrive is running but no user OneDrive folder was detected yet.'
        $result.NeedsAttention = $true
    }
    else {
        $result.StatusMessage  = "OneDrive appears active. Folder: $($result.UserFolder)"
        $result.NeedsAttention = $false
    }

    return $result
}