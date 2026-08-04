function Register-MigrationPhaseTasks {
    <#
    .SYNOPSIS
        Registers scheduled tasks for the remaining DMU migration phases.

    .DESCRIPTION
        Higher-level helper used by the orchestrator (or called manually) to
        wire Phase 2–4 as SYSTEM tasks under \DMU\ instead of (or in addition to)
        RunOnce registry entries.

        Phase 1 is typically launched interactively or via Setup.ps1; this
        function focuses on the post-reboot chain.

    .PARAMETER MigrationPath
        Working directory where phase scripts were staged.
        Default: C:\ProgramData\AADMigration

    .PARAMETER ConfigPath
        Config path passed to each phase script.

    .PARAMETER Phases
        Which phases to register. Default: 2, 3, 4.

    .PARAMETER Trigger
        Trigger type for the first registered phase. Subsequent phases are
        normally chained by the phase scripts themselves (RunOnce or by
        registering the next task). Default: AtStartup.

    .PARAMETER UseScheduledTasksOnly
        When set, phase scripts are still free to register RunOnce; this switch
        is informational for callers. Prefer calling phases with logic that
        uses Register-DMUScheduledTask for the next hop.

    .PARAMETER Force
        Overwrite existing tasks.

    .EXAMPLE
        Register-MigrationPhaseTasks -Force

    .EXAMPLE
        Register-MigrationPhaseTasks -Phases 2,3 -Trigger Once -Force
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$MigrationPath = 'C:\ProgramData\AADMigration',

        [string]$ConfigPath,

        [ValidateSet(1, 2, 3, 4)]
        [int[]]$Phases = @(2, 3, 4),

        [ValidateSet('AtStartup', 'AtLogon', 'Once', 'OnDemand')]
        [string]$Trigger = 'AtStartup',

        [switch]$Force
    )

    if (-not $ConfigPath) {
        $ConfigPath = Join-Path $MigrationPath 'MigrationConfig.psd1'
    }

    $phaseMap = @{
        1 = @{ Name = 'Phase1-EntraJoin';       File = 'Phase1-EntraJoin.ps1' }
        2 = @{ Name = 'Phase2-EscrowBitlocker'; File = 'Phase2-EscrowBitlocker.ps1' }
        3 = @{ Name = 'Phase3-OneDrive';        File = 'Phase3-OneDrive.ps1' }
        4 = @{ Name = 'Phase4-Cleanup';        File = 'Phase4-Cleanup.ps1' }
    }

    $registered = @()

    foreach ($n in ($Phases | Sort-Object)) {
        $meta = $phaseMap[$n]
        $scriptPath = Join-Path $MigrationPath "Scripts\$($meta.File)"

        if (-not (Test-Path $scriptPath)) {
            Write-Warning "Phase $n script not found: $scriptPath – skipping."
            continue
        }

        $args = ''
        if (Test-Path $ConfigPath) {
            $args = "-ConfigPath `"$ConfigPath`""
        }

        # Only the earliest phase gets an active trigger; later ones can be
        # OnDemand and started by the previous phase, or also AtStartup if the
        # caller registered multiple.
        $thisTrigger = if ($n -eq ($Phases | Measure-Object -Minimum).Minimum) {
            $Trigger
        } else {
            'OnDemand'
        }

        Write-Verbose "Registering $($meta.Name) ($thisTrigger) → $scriptPath"

        $task = Register-DMUScheduledTask `
            -TaskName $meta.Name `
            -ScriptPath $scriptPath `
            -Arguments $args `
            -Trigger $thisTrigger `
            -Description "DMU $($meta.Name)" `
            -Force:$Force `
            -DelaySeconds 90

        if ($task) {
            $registered += [PSCustomObject]@{
                Phase      = $n
                TaskName   = $meta.Name
                ScriptPath = $scriptPath
                Trigger    = $thisTrigger
            }
        }
    }

    return $registered
}