<#
.SYNOPSIS
    Runs the DMU Pester test suite.

.DESCRIPTION
    Ensures Pester 5+ is available, then invokes all *.Tests.ps1 files under tests/.

.EXAMPLE
    .\tests\Run-Tests.ps1

.EXAMPLE
    .\tests\Run-Tests.ps1 -Detailed
#>

[CmdletBinding()]
param(
    [switch]$Detailed
)

$ErrorActionPreference = 'Stop'
$testsRoot = $PSScriptRoot

# Prefer Pester 5
$pester = Get-Module -ListAvailable -Name Pester |
    Where-Object { $_.Version.Major -ge 5 } |
    Sort-Object Version -Descending |
    Select-Object -First 1

if (-not $pester) {
    Write-Host 'Pester 5+ not found. Installing for CurrentUser...' -ForegroundColor Yellow
    Install-Module -Name Pester -MinimumVersion 5.0.0 -Scope CurrentUser -Force -SkipPublisherCheck
    $pester = Get-Module -ListAvailable -Name Pester |
        Where-Object { $_.Version.Major -ge 5 } |
        Sort-Object Version -Descending |
        Select-Object -First 1
}

Import-Module Pester -RequiredVersion $pester.Version -Force
Write-Host "Using Pester $($pester.Version)" -ForegroundColor Cyan

$config = New-PesterConfiguration
$config.Run.Path = $testsRoot
$config.Run.Exit = $true
$config.Output.Verbosity = if ($Detailed) { 'Detailed' } else { 'Normal' }
$config.TestResult.Enabled = $true
$config.TestResult.OutputPath = Join-Path $testsRoot 'TestResults.xml'
$config.TestResult.OutputFormat = 'NUnitXml'

Invoke-Pester -Configuration $config
