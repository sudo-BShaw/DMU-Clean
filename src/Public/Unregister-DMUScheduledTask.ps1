function Unregister-DMUScheduledTask {
    <#
    .SYNOPSIS
        Removes one or all DMU scheduled tasks.

    .PARAMETER TaskName
        Specific task to remove. If omitted, all tasks under TaskPath are removed.

    .PARAMETER TaskPath
        Task Scheduler folder. Default: \DMU\

    .PARAMETER IncludeLegacy
        Also remove tasks under the original \AAD Migration\ folder.

    .PARAMETER RemoveFolder
        After removing tasks, delete the empty task folder.

    .EXAMPLE
        Unregister-DMUScheduledTask -TaskName 'Phase2-EscrowBitlocker'

    .EXAMPLE
        Unregister-DMUScheduledTask -IncludeLegacy -RemoveFolder
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [string]$TaskName,

        [string]$TaskPath = '\DMU\',

        [switch]$IncludeLegacy,

        [switch]$RemoveFolder
    )

    if (-not $TaskPath.StartsWith('\')) { $TaskPath = '\' + $TaskPath }
    if (-not $TaskPath.EndsWith('\'))   { $TaskPath = $TaskPath + '\' }

    $paths = @($TaskPath)
    if ($IncludeLegacy) { $paths += '\AAD Migration\' }

    foreach ($path in $paths) {
        $filter = @{ TaskPath = $path; ErrorAction = 'SilentlyContinue' }
        if ($TaskName) { $filter['TaskName'] = $TaskName }

        $tasks = @(Get-ScheduledTask @filter)
        foreach ($t in $tasks) {
            if ($PSCmdlet.ShouldProcess("$($t.TaskPath)$($t.TaskName)", 'Unregister scheduled task')) {
                Unregister-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -Confirm:$false
                Write-Verbose "Unregistered $($t.TaskPath)$($t.TaskName)"
            }
        }

        if ($RemoveFolder -and -not $TaskName) {
            $folderName = $path.Trim('\')
            try {
                $service = New-Object -ComObject 'Schedule.Service'
                $service.Connect()
                $root = $service.GetFolder('\')
                $null = $root.GetFolder($folderName)  # throws if missing
                if ($PSCmdlet.ShouldProcess($folderName, 'Delete scheduled-task folder')) {
                    $root.DeleteFolder($folderName, 0)
                    Write-Verbose "Deleted task folder \$folderName\"
                }
            }
            catch {
                Write-Verbose "Task folder \$folderName\ not present or not empty: $($_.Exception.Message)"
            }
        }
    }
}