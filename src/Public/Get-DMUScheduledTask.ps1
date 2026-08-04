function Get-DMUScheduledTask {
    <#
    .SYNOPSIS
        Lists DMU scheduled tasks.

    .PARAMETER TaskPath
        Task Scheduler folder to search. Default: \DMU\

    .PARAMETER TaskName
        Optional specific task name filter.

    .EXAMPLE
        Get-DMUScheduledTask

    .EXAMPLE
        Get-DMUScheduledTask -TaskName 'Phase2-EscrowBitlocker'
    #>
    [CmdletBinding()]
    param(
        [string]$TaskPath = '\DMU\',

        [string]$TaskName
    )

    if (-not $TaskPath.StartsWith('\')) { $TaskPath = '\' + $TaskPath }
    if (-not $TaskPath.EndsWith('\'))   { $TaskPath = $TaskPath + '\' }

    $params = @{ TaskPath = $TaskPath; ErrorAction = 'SilentlyContinue' }
    if ($TaskName) { $params['TaskName'] = $TaskName }

    $tasks = @(Get-ScheduledTask @params)

    # Also surface legacy \AAD Migration\ tasks from the original toolkit
    if ($TaskPath -eq '\DMU\') {
        $legacy = @(Get-ScheduledTask -TaskPath '\AAD Migration\' -ErrorAction SilentlyContinue)
        if ($TaskName) {
            $legacy = $legacy | Where-Object { $_.TaskName -eq $TaskName }
        }
        $tasks += $legacy
    }

    foreach ($t in $tasks) {
        $info = $t | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
        [PSCustomObject]@{
            TaskName      = $t.TaskName
            TaskPath      = $t.TaskPath
            State         = $t.State
            LastRunTime   = if ($info) { $info.LastRunTime } else { $null }
            LastTaskResult= if ($info) { $info.LastTaskResult } else { $null }
            NextRunTime   = if ($info) { $info.NextRunTime } else { $null }
            Actions       = ($t.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join '; '
        }
    }
}