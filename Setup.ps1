<#
.SYNOPSIS
    Thin entry point for the Device Migration Utility (DMU) - Clean Edition.

.DESCRIPTION
    - Ensures elevation
    - Sets process execution policy
    - Loads the DMU module from the local src/ folder
    - Performs a quick device status check
    - Hands off to Start-DeviceMigration (when implemented)

    Unlike the original Setup.ps1, this version does NOT re-download the entire
    repository on every run. It expects you to have cloned or extracted the repo.
#>

[CmdletBinding()]
param(
    [switch]$ForceCleanup,
    [switch]$SkipStatusCheck
)

$ErrorActionPreference = 'Stop'

#region Helpers
function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-SetupLog {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $color = switch ($Level) {
        'ERROR'   { 'Red' }
        'WARNING' { 'Yellow' }
        'NOTICE'  { 'Cyan' }
        default   { 'Green' }
    }
    Write-Host "[$ts] [$Level] $Message" -ForegroundColor $color
}
#endregion

# Require PowerShell 5.1 for maximum module compatibility
if ($PSVersionTable.PSVersion.Major -ne 5) {
    Write-SetupLog "This tool currently requires Windows PowerShell 5.1. Current version: $($PSVersionTable.PSVersion)" -Level 'ERROR'
    exit 1
}

# Elevate if needed
if (-not (Test-IsAdmin)) {
    Write-SetupLog 'Not running as administrator. Relaunching elevated...' -Level 'NOTICE'
    $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    if ($ForceCleanup)   { $args += '-ForceCleanup' }
    if ($SkipStatusCheck){ $args += '-SkipStatusCheck' }
    Start-Process -FilePath 'powershell.exe' -ArgumentList $args -Verb RunAs
    exit
}

# Process-scoped execution policy
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

$repoRoot = $PSScriptRoot
Write-SetupLog "Repository root: $repoRoot"

# Dot-source public functions (simple approach until full module is ready)
$publicPath  = Join-Path $repoRoot 'src\Public'
$privatePath = Join-Path $repoRoot 'src\Private'

if (Test-Path $publicPath) {
    Get-ChildItem -Path $publicPath -Filter '*.ps1' | ForEach-Object {
        . $_.FullName
        Write-SetupLog "Loaded $($_.Name)"
    }
}
if (Test-Path $privatePath) {
    Get-ChildItem -Path $privatePath -Filter '*.ps1' | ForEach-Object {
        . $_.FullName
        Write-SetupLog "Loaded $($_.Name)"
    }
}

# Optional cleanup
if ($ForceCleanup) {
    Write-SetupLog 'ForceCleanup requested – removing previous migration artifacts...' -Level 'NOTICE'
    if (Get-Command Remove-MigrationArtifacts -ErrorAction SilentlyContinue) {
        Remove-MigrationArtifacts -Verbose
    }
}

# Status check
if (-not $SkipStatusCheck -and (Get-Command Get-DeviceJoinStatus -ErrorAction SilentlyContinue)) {
    Write-SetupLog 'Checking current device join / enrollment status...'
    $status = Get-DeviceJoinStatus
    Write-SetupLog "Join type: $($status.JoinType) | MDM enrolled: $($status.IsMDMEnrolled) | Needs migration: $($status.NeedsMigration)"

    if (-not $status.NeedsMigration) {
        Write-SetupLog 'Device is already fully Entra-joined and Intune-enrolled. Nothing to do.' -Level 'NOTICE'
        exit 0
    }
}

Write-SetupLog 'DMU Clean Edition bootstrap complete.' -Level 'NOTICE'
Write-SetupLog 'Next steps: implement / call Start-DeviceMigration once the remaining modules are migrated.' -Level 'NOTICE'

# Future hand-off point
# if (Get-Command Start-DeviceMigration -ErrorAction SilentlyContinue) {
#     Start-DeviceMigration
# }
