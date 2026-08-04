# Getting Started

## Prerequisites

- Windows 10 or 11 (client OS)
- Windows PowerShell **5.1** (orchestrator enforces this)
- Local administrator rights
- Entra ID P1 + Intune P1 (for automatic MDM enrollment after join)
- A valid **Windows Provisioning Package (PPKG)** that joins devices to your tenant
- Network access to Entra / Intune endpoints

## Install / clone

```powershell
git clone https://github.com/sudo-BShaw/DMU-Clean.git
cd DMU-Clean
```

There is no installer. `Setup.ps1` dot-sources `src\Public` and `src\Private` in-process.

## Configure

```powershell
Copy-Item .\config\MigrationConfig.example.psd1 .\config\MigrationConfig.psd1
notepad .\config\MigrationConfig.psd1
```

**Required edits:**

1. `TenantID` – your real Entra tenant GUID (not the all-zero placeholder)
2. `ProvisioningPack` – full path to the `.ppkg` file

Optional: `MigrationPath`, `LogsPath`, `TempUser`, `UseOneDriveKFM`, `InstallOneDrive`.

See [Configuration](Configuration.md) for the full reference.

> **Never commit** `MigrationConfig.psd1`. It is gitignored.

## First run (prepare only)

```powershell
.\Setup.ps1 -ForceCleanup
```

This will:

- Elevate if needed
- Load functions
- Validate config and device status
- Create the strong-password temporary local admin
- Stage phase scripts + config under `C:\ProgramData\AADMigration`

It will **not** apply the PPKG unless you also pass `-LaunchPhase1`.

## Full migration (Phase 1 and chain)

```powershell
# RunOnce-based chain (default phase behavior)
.\Setup.ps1 -ForceCleanup -LaunchPhase1

# Also register Phase 2–4 as \DMU\ scheduled tasks
.\Setup.ps1 -ForceCleanup -UseScheduledTasks -LaunchPhase1

# Test without reboot
.\Setup.ps1 -LaunchPhase1 -SkipReboot
```

After Phase 1 succeeds, the device reboots (unless `-SkipReboot`). Subsequent phases run via RunOnce and/or scheduled tasks.

## Verify status anytime

```powershell
# After loading functions (or from an elevated session that dot-sourced src)
Get-DeviceJoinStatus | Format-List
Show-DeviceJoinStatus
```

## Manual phase execution

```powershell
& 'C:\ProgramData\AADMigration\Scripts\Phase2-EscrowBitlocker.ps1' `
    -ConfigPath 'C:\ProgramData\AADMigration\MigrationConfig.psd1' `
    -SkipReboot
```

## Cleanup only

```powershell
& 'C:\ProgramData\AADMigration\Scripts\Phase4-Cleanup.ps1' -SkipReboot
# or
Remove-MigrationArtifacts -Verbose
Unregister-DMUScheduledTask -IncludeLegacy -RemoveFolder
```
