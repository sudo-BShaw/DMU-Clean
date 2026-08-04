# Function Reference

Functions are loaded by dot-sourcing `src/Public` and `src/Private` (via `Setup.ps1` or `tests/Helpers.ps1`). They are also listed in `src/DMU.psd1` for module use.

## Public

### Start-DeviceMigration

Main orchestrator: config validation, logging, optional cleanup, status check, temp admin, stage scripts, optional scheduled tasks, optional Phase 1 launch.

```powershell
Start-DeviceMigration [-ConfigPath <path>] [-ForceCleanup] [-SkipStatusCheck] `
    [-LaunchPhase1] [-SkipReboot] [-UseScheduledTasks] [-WhatIf]
```

### Get-DeviceJoinStatus / Show-DeviceJoinStatus

Parse `dsregcmd /status`. Returns join flags, `JoinType`, `NeedsMigration`. `Show-DeviceJoinStatus` prints a summary and returns exit code 0 (done) or 1 (needs migration).

### Remove-MigrationArtifacts

Removes migration directories, legacy scheduled tasks under `\AAD Migration\`, temp user, and resets common registry keys. Used by `-ForceCleanup` and as a lighter alternative to full Phase 4.

### Register-DMUScheduledTask

Creates a SYSTEM task under `\DMU\` (configurable path) pointing at a phase script.

### Get-DMUScheduledTask

Lists tasks with state, last run, and action summary.

### Unregister-DMUScheduledTask

Removes one or all DMU tasks; `-IncludeLegacy` also targets `\AAD Migration\`; `-RemoveFolder` deletes the task folder when empty.

### Register-MigrationPhaseTasks

Registers Phase 1–4 scripts that exist under `MigrationPath\Scripts` as scheduled tasks.

### New-StrongPassword

```powershell
New-StrongPassword [-Length 24] [-IncludeSpecial $true]  # → SecureString
```

Cryptographic RNG; minimum length 16; guarantees mixed character classes.

### Initialize-Logging / Stop-Logging

Shared transcript + optional PSFramework CSV provider. Returns a hashtable consumed by `Stop-Logging` in `finally` blocks.

### Invoke-BitLockerEscrow

```powershell
Invoke-BitLockerEscrow [-MountPoint C:] [-CreateProtectorIfMissing] [-WhatIf]
```

Returns per-drive objects: `Success`, `KeyProtectorIds`, `Message`.

### Get-OneDriveSyncStatus

Best-effort status without third-party binaries: installed, running, user folder, KFM hints, `NeedsAttention`.

### Enable-OneDriveKFM

Writes `HKLM\SOFTWARE\Policies\Microsoft\OneDrive` silent KFM values (`KFMSilentOptIn` + per-folder flags).

---

## Private

| Function | Role |
|----------|------|
| `Initialize-Logging` | Also exported for convenience |
| `New-StrongPassword` | Also exported |
| `Invoke-BitLockerEscrow` | Also exported |
| `Get-OneDriveSyncStatus` | Also exported |
| `Enable-OneDriveKFM` | Also exported |

Phase scripts may redefine a minimal `Write-DMULog` if helpers are not yet on the path.

---

## Phase scripts (not module functions)

| Script | Entry |
|--------|-------|
| `src/Scripts/Phase1-EntraJoin.ps1` | Executable phase |
| `src/Scripts/Phase2-EscrowBitlocker.ps1` | Executable phase |
| `src/Scripts/Phase3-OneDrive.ps1` | Executable phase |
| `src/Scripts/Phase4-Cleanup.ps1` | Executable phase |
