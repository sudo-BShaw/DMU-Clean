function Register-DMUScheduledTask {
    <#
    .SYNOPSIS
        Registers a scheduled task that runs a DMU phase script elevated as SYSTEM.

    .DESCRIPTION
        Preferred alternative (or complement) to RunOnce for chaining migration phases.
        Tasks are created under the folder \DMU\ (configurable) and can be triggered
        at startup, at logon, or on a short delay after registration.

    .PARAMETER TaskName
        Name of the task (e.g. 'Phase2-EscrowBitlocker').

    .PARAMETER ScriptPath
        Full path to the .ps1 file to execute.

    .PARAMETER Arguments
        Extra arguments appended after -File ScriptPath.

    .PARAMETER TaskPath
        Task Scheduler folder. Default: \DMU\

    .PARAMETER Trigger
        When the task should run:
        - AtStartup  (default) – after the next boot
        - AtLogon    – when any user logs on
        - Once       – a single run after DelaySeconds
        - OnDemand   – no trigger; run later with Start-ScheduledTask

    .PARAMETER DelaySeconds
        Delay before a Once trigger fires (default 60).

    .PARAMETER Description
        Optional task description.

    .PARAMETER Force
        Overwrite an existing task with the same name.

    .EXAMPLE
        Register-DMUScheduledTask `
            -TaskName 'Phase2-EscrowBitlocker' `
            -ScriptPath 'C:\ProgramData\AADMigration\Scripts\Phase2-EscrowBitlocker.ps1' `
            -Trigger AtStartup `
            -Force
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$TaskName,

        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$ScriptPath,

        [string]$Arguments = '',

        [string]$TaskPath = '\DMU\',

        [ValidateSet('AtStartup', 'AtLogon', 'Once', 'OnDemand')]
        [string]$Trigger = 'AtStartup',

        [ValidateRange(0, 86400)]
        [int]$DelaySeconds = 60,

        [string]$Description = 'Device Migration Utility (DMU) phase task',

        [switch]$Force
    )

    # Normalize task path
    if (-not $TaskPath.StartsWith('\')) { $TaskPath = '\' + $TaskPath }
    if (-not $TaskPath.EndsWith('\'))   { $TaskPath = $TaskPath + '\' }

    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $argString = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
    if ($Arguments) { $argString += " $Arguments" }

    $action = New-ScheduledTaskAction -Execute $psExe -Argument $argString

    $taskTrigger = switch ($Trigger) {
        'AtStartup' {
            $t = New-ScheduledTaskTrigger -AtStartup
            if ($DelaySeconds -gt 0) {
                $t.Delay = "PT$($DelaySeconds)S"
            }
            $t
        }
        'AtLogon' {
            $t = New-ScheduledTaskTrigger -AtLogOn
            if ($DelaySeconds -gt 0) {
                $t.Delay = "PT$($DelaySeconds)S"
            }
            $t
        }
        'Once' {
            $start = (Get-Date).AddSeconds([Math]::Max($DelaySeconds, 5))
            New-ScheduledTaskTrigger -Once -At $start
        }
        'OnDemand' { $null }
    }

    $principal = New-ScheduledTaskPrincipal `
        -UserId 'SYSTEM' `
        -LogonType ServiceAccount `
        -RunLevel Highest

    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -ExecutionTimeLimit (New-TimeSpan -Hours 2) `
        -RestartCount 2 `
        -RestartInterval (New-TimeSpan -Minutes 1)

    # OnDemand / Once tasks should not keep running forever on a schedule
    if ($Trigger -in @('Once', 'OnDemand')) {
        $settings.DeleteExpiredTaskAfter = 'PT1H'
    }

    $existing = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue
    if ($existing) {
        if (-not $Force) {
            throw "Scheduled task '$TaskPath$TaskName' already exists. Use -Force to replace it."
        }
        if ($PSCmdlet.ShouldProcess("$TaskPath$TaskName", 'Unregister existing task')) {
            Unregister-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Confirm:$false
        }
    }

    $registerParams = @{
        TaskName    = $TaskName
        TaskPath    = $TaskPath
        Action      = $action
        Principal   = $principal
        Settings    = $settings
        Description = $Description
        Force       = $true
    }
    if ($taskTrigger) {
        $registerParams['Trigger'] = $taskTrigger
    }

    if ($PSCmdlet.ShouldProcess("$TaskPath$TaskName", "Register scheduled task ($Trigger)")) {
        $task = Register-ScheduledTask @registerParams
        Write-Verbose "Registered $TaskPath$TaskName → $ScriptPath ($Trigger)"
        return $task
    }
}