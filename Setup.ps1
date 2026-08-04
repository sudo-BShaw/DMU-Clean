<#
.SYNOPSIS
    Thin entry point for the Device Migration Utility (DMU) - Clean Edition.

.DESCRIPTION
    - Ensures elevation
    - Sets process execution policy
    - Loads the DMU functions from the local src/ folder
    - Hands off to Start-DeviceMigration

    Unlike the original Setup.ps1, this version does NOT re-download the entire
    repository on every run. It expects you to have cloned or extracted the repo.
#>

[CmdletBinding()]
param(
    [string]$ConfigPath,

    [switch]$ForceCleanup,

    [switch]$SkipStatusCheck,

    [switch]$LaunchPhase1,

    [switch]$SkipReboot
)

$ErrorActionPreference = 'Stop'

#region Helpers
function Test-IsAdmin {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
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
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    if ($ConfigPath)       { $argList += '-ConfigPath'; $ConfigPath }
    if ($ForceCleanup)     { $argList += '-ForceCleanup' }
    if ($SkipStatusCheck)  { $argList += '-SkipStatusCheck' }
    if ($LaunchPhase1)     { $argList += '-LaunchPhase1' }
    if ($SkipReboot)       { $argList += '-SkipReboot' }
    Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs
    exit
}

# Process-scoped execution policy
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

$repoRoot = $PSScriptRoot
Write-SetupLog "Repository root: $repoRoot"

# Dot-source Public and Private functions
$publicPath  = Join-Path $repoRoot 'src\Public'
$privatePath = Join-Path $repoRoot 'src\Private'

foreach ($path in @($publicPath, $privatePath)) {
    if (Test-Path $path) {
        Get-ChildItem -Path $path -Filter '*.ps1' | ForEach-Object {
            . $_.FullName
            Write-SetupLog "Loaded $($_.Name)"
        }
    }
}

if (-not (Get-Command Start-DeviceMigration -ErrorAction SilentlyContinue)) {
    Write-SetupLog 'Start-DeviceMigration function not found. Ensure src/Public/Start-DeviceMigration.ps1 exists.' -Level 'ERROR'
    exit 1
}

# Hand off to the orchestrator
$params = @{}
if ($ConfigPath)      { $params['ConfigPath']      = $ConfigPath }
if ($ForceCleanup)    { $params['ForceCleanup']    = $true }
if ($SkipStatusCheck) { $params['SkipStatusCheck'] = $true }
if ($LaunchPhase1)    { $params['LaunchPhase1']    = $true }
if ($SkipReboot)      { $params['SkipReboot']      = $true }

Write-SetupLog 'Calling Start-DeviceMigration...' -Level 'NOTICE'
Start-DeviceMigration @params
