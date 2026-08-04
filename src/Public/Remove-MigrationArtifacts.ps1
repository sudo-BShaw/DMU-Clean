function Remove-MigrationArtifacts {
    <#
    .SYNOPSIS
        Removes leftover artifacts from a previous DMU / AAD migration run.

    .DESCRIPTION
        Cleans directories, scheduled tasks under the AAD Migration folder,
        the temporary local user, and common registry settings that were
        modified during migration.

        This is a cleaned, parameterized version of the original cleanup logic.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$MigrationPath = 'C:\ProgramData\AADMigration',
        [string]$LogsPath      = 'C:\Logs',
        [string]$TempPath      = 'C:\temp',
        [string]$JobName       = 'AAD_Migration',
        [string]$TempUserName  = 'MigrationInProgress'
    )

    Write-Verbose "Starting migration artifact cleanup..."

    $pathsToClean = @(
        @{ Path = $LogsPath;                              Name = 'Logs Path' },
        @{ Path = $MigrationPath;                         Name = 'Migration Path' },
        @{ Path = (Join-Path $TempPath "$JobName-secrets"); Name = 'Secrets Path' },
        @{ Path = (Join-Path $TempPath "$JobName-logs");    Name = 'Temp Logs Path' },
        @{ Path = (Join-Path $TempPath "$JobName-git");     Name = 'Temp Git Path' }
    )

    foreach ($item in $pathsToClean) {
        if (Test-Path -Path $item.Path) {
            if ($PSCmdlet.ShouldProcess($item.Path, "Remove $($item.Name)")) {
                Remove-Item -Path $item.Path -Recurse -Force -ErrorAction SilentlyContinue
                Write-Verbose "Removed $($item.Name): $($item.Path)"
            }
        }
        else {
            Write-Verbose "$($item.Name) does not exist – skipping."
        }
    }

    # Scheduled tasks under \AAD Migration\
    $scheduledTasks = Get-ScheduledTask -TaskPath '\AAD Migration\' -ErrorAction SilentlyContinue
    if ($scheduledTasks) {
        foreach ($task in $scheduledTasks) {
            if ($PSCmdlet.ShouldProcess($task.TaskName, 'Unregister scheduled task')) {
                Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false
                Write-Verbose "Removed scheduled task: $($task.TaskName)"
            }
        }
    }

    # Remove the task folder itself
    try {
        $service = New-Object -ComObject 'Schedule.Service'
        $service.Connect()
        $root = $service.GetFolder('\')
        $folder = $root.GetFolder('AAD Migration')
        if ($PSCmdlet.ShouldProcess('AAD Migration', 'Delete scheduled task folder')) {
            $folder.DeleteFolder('', 0)
            Write-Verbose 'Scheduled task folder AAD Migration removed.'
        }
    }
    catch {
        Write-Verbose 'Scheduled task folder AAD Migration not present or could not be removed.'
    }

    # Temporary local user
    try {
        $user = Get-LocalUser -Name $TempUserName -ErrorAction Stop
        if ($user -and $PSCmdlet.ShouldProcess($TempUserName, 'Remove local user')) {
            Remove-LocalUser -Name $TempUserName -ErrorAction Stop
            Write-Verbose "Removed local user: $TempUserName"
        }
    }
    catch {
        Write-Verbose "Local user $TempUserName does not exist – skipping."
    }

    # Reset common registry keys that migration may have changed
    $registryResets = @(
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name = 'dontdisplaylastusername'; Type = 'DWord'; Value = 0 },
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name = 'legalnoticecaption';      Type = 'String'; Value = '' },
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Name = 'legalnoticetext';         Type = 'String'; Value = '' },
        @{ Path = 'HKLM:\Software\Policies\Microsoft\Windows\Personalization';       Name = 'NoLockScreen';            Type = 'DWord'; Value = 0 }
    )

    foreach ($reg in $registryResets) {
        if (Test-Path $reg.Path) {
            if ($PSCmdlet.ShouldProcess("$($reg.Path)\$($reg.Name)", 'Reset registry value')) {
                try {
                    Set-ItemProperty -Path $reg.Path -Name $reg.Name -Value $reg.Value -Type $reg.Type -Force -ErrorAction SilentlyContinue
                }
                catch {
                    Write-Verbose "Could not reset $($reg.Name): $($_.Exception.Message)"
                }
            }
        }
    }

    Write-Verbose 'Migration artifact cleanup completed.'
}