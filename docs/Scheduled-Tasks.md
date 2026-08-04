# Scheduled Tasks

## Why both RunOnce and tasks?

| | RunOnce | Scheduled tasks (`\DMU\`) |
|--|---------|---------------------------|
| Visibility | Registry only | Task Scheduler UI / `Get-ScheduledTask` |
| Context | Runs at next interactive logon path | SYSTEM, Highest, configurable trigger |
| Resilience | Single-shot; easy to clear | Can restart on failure; StartWhenAvailable |
| Cleanup | Phase 4 clears values | `Unregister-DMUScheduledTask` / Phase 4 |

Default phase scripts still write **RunOnce**. Use scheduled tasks when you want a more operable, auditable chain.

## Enabling from the orchestrator

```powershell
.\Setup.ps1 -ForceCleanup -UseScheduledTasks -LaunchPhase1
# or
Start-DeviceMigration -UseScheduledTasks -ForceCleanup
```

This stages scripts, then calls `Register-MigrationPhaseTasks` for phases **2, 3, 4**:

- Lowest phase number in the set → trigger **AtStartup** (90s delay)
- Remaining phases → **OnDemand** (previous phase or an admin can start them)

## Low-level API

### Register one task

```powershell
Register-DMUScheduledTask `
    -TaskName 'Phase2-EscrowBitlocker' `
    -ScriptPath 'C:\ProgramData\AADMigration\Scripts\Phase2-EscrowBitlocker.ps1' `
    -Arguments '-ConfigPath "C:\ProgramData\AADMigration\MigrationConfig.psd1"' `
    -Trigger AtStartup `
    -DelaySeconds 90 `
    -Force
```

**Triggers:** `AtStartup` | `AtLogon` | `Once` | `OnDemand`

### List

```powershell
Get-DMUScheduledTask
Get-DMUScheduledTask -TaskName 'Phase3-OneDrive'
```

Also returns legacy tasks under `\AAD Migration\` when querying the default `\DMU\` path.

### Remove

```powershell
Unregister-DMUScheduledTask -TaskName 'Phase2-EscrowBitlocker'
Unregister-DMUScheduledTask -IncludeLegacy -RemoveFolder
```

### Register the phase set

```powershell
Register-MigrationPhaseTasks -Phases 2,3,4 -Trigger AtStartup -Force
Register-MigrationPhaseTasks -Phases 2 -Trigger Once -Force
```

## Task defaults

- **Principal:** SYSTEM, ServiceAccount, RunLevel Highest  
- **Settings:** allow on battery, start when available, 2-hour limit, 2 restarts  
- **Action:** `powershell.exe -NoProfile -ExecutionPolicy Bypass -File <script>`

## Operational tips

1. After a failed phase, open Task Scheduler → `DMU` folder → check **Last Run Result**.  
2. Re-run a phase: `Start-ScheduledTask -TaskName 'Phase2-EscrowBitlocker' -TaskPath '\DMU\'`.  
3. Always run Phase 4 or `Unregister-DMUScheduledTask -IncludeLegacy -RemoveFolder` when migration is finished so devices do not keep stale tasks.
