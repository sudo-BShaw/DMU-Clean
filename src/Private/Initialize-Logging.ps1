function Initialize-Logging {
    <#
    .SYNOPSIS
        Sets up consistent logging for DMU scripts (transcript + optional PSFramework).

    .DESCRIPTION
        Centralizes the logging bootstrap that was previously duplicated across
        DeviceMigration.ps1 and every phase script. Creates log directories,
        starts a transcript, and (if PSFramework is available) configures a
        modern CSV logfile provider.

    .PARAMETER JobName
        Logical job name used in log file names (default: AAD_Migration).

    .PARAMETER LogsPath
        Root path for logs (default: C:\Logs).

    .PARAMETER ParentScriptName
        Name of the calling script (used for unique instance naming).

    .PARAMETER UsePSFramework
        Attempt to configure PSFramework logging if the module is present.

    .OUTPUTS
        Hashtable containing TranscriptPath, InstanceName, and whether PSF was enabled.
    #>
    [CmdletBinding()]
    param(
        [string]$JobName          = 'AAD_Migration',
        [string]$LogsPath         = 'C:\Logs',
        [string]$ParentScriptName = $MyInvocation.ScriptName,
        [switch]$UsePSFramework
    )

    # Ensure directories exist
    $transcriptDir = Join-Path $LogsPath 'Transcript'
    $psfDir        = Join-Path $LogsPath 'PSF'
    foreach ($dir in @($LogsPath, $transcriptDir, $psfDir)) {
        if (-not (Test-Path -Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }
    }

    # Build a unique transcript path
    $timestamp      = Get-Date -Format 'yyyyMMdd-HHmmss'
    $scriptLeaf     = if ($ParentScriptName) { [System.IO.Path]::GetFileNameWithoutExtension($ParentScriptName) } else { 'DMU' }
    $transcriptPath = Join-Path $transcriptDir "$JobName-$scriptLeaf-$timestamp.log"

    try {
        Start-Transcript -Path $transcriptPath -Force -ErrorAction Stop
        Write-Verbose "Transcript started: $transcriptPath"
    }
    catch {
        Write-Warning "Could not start transcript: $($_.Exception.Message)"
        $transcriptPath = $null
    }

    $instanceName = "$scriptLeaf-$timestamp"
    $psfEnabled   = $false

    if ($UsePSFramework -and (Get-Module -ListAvailable -Name PSFramework)) {
        try {
            Import-Module PSFramework -ErrorAction Stop

            $csvLogFilePath = Join-Path $psfDir "$JobName-$scriptLeaf-$timestamp.csv"

            $paramSetPSFLoggingProvider = @{
                Name            = 'logfile'
                InstanceName    = $instanceName
                FilePath        = $csvLogFilePath
                Enabled         = $true
                FileType        = 'CSV'
                EnableException = $true
            }
            Set-PSFLoggingProvider @paramSetPSFLoggingProvider
            $psfEnabled = $true
            Write-Verbose "PSFramework logging enabled: $csvLogFilePath"
        }
        catch {
            Write-Warning "PSFramework logging could not be configured: $($_.Exception.Message)"
        }
    }

    # Simple host logger that works even without PSFramework
    function script:Write-DMULog {
        param(
            [Parameter(Mandatory)]
            [string]$Message,
            [ValidateSet('DEBUG','INFO','NOTICE','WARNING','ERROR','CRITICAL')]
            [string]$Level = 'INFO'
        )

        $formatted = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"

        $color = switch ($Level) {
            'DEBUG'    { 'DarkGray' }
            'INFO'     { 'Green' }
            'NOTICE'   { 'Cyan' }
            'WARNING'  { 'Yellow' }
            'ERROR'    { 'Red' }
            'CRITICAL' { 'Magenta' }
            default    { 'White' }
        }
        Write-Host $formatted -ForegroundColor $color

        if ($psfEnabled -and (Get-Command Write-PSFMessage -ErrorAction SilentlyContinue)) {
            Write-PSFMessage -Level $Level -Message $Message
        }
    }

    return @{
        TranscriptPath = $transcriptPath
        InstanceName   = $instanceName
        PSFEnabled     = $psfEnabled
        LogsPath       = $LogsPath
        JobName        = $JobName
    }
}

function Stop-Logging {
    <#
    .SYNOPSIS
        Cleanly stops transcript and PSFramework logging providers.
    #>
    [CmdletBinding()]
    param(
        [string]$TranscriptPath,
        [string]$InstanceName,
        [switch]$PSFEnabled
    )

    if ($TranscriptPath) {
        try { Stop-Transcript -ErrorAction SilentlyContinue } catch { }
    }

    if ($PSFEnabled -and $InstanceName -and (Get-Command Set-PSFLoggingProvider -ErrorAction SilentlyContinue)) {
        try {
            Set-PSFLoggingProvider -Name 'logfile' -InstanceName $InstanceName -Enabled $false -ErrorAction SilentlyContinue
            if (Get-Command Wait-PSFMessage -ErrorAction SilentlyContinue) {
                Wait-PSFMessage
            }
        }
        catch { }
    }
}