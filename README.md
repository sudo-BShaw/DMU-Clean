# Device Migration Utility (DMU) - Clean Edition

**Clean, modular rewrite** of the Device Migration Utility for migrating Windows devices from Workgroup / Domain Join / Hybrid Join to **Entra ID Join + Intune** while preserving user data.

Based on the excellent original work by [aollivierre/IntuneDeviceMigration](https://github.com/aollivierre/IntuneDeviceMigration).

> **Status**: v0.6.0 – Core phases + Pester tests + scheduled-task helpers.

## Architecture

```
DMU-Clean/
├── Setup.ps1
├── config/MigrationConfig.example.psd1
├── tests/                    # Pester 5 suite + Run-Tests.ps1
└── src/
    ├── DMU.psd1 / DMU.psm1   # v0.6.0
    ├── Public/
    │   ├── Start-DeviceMigration.ps1
    │   ├── Get-DeviceJoinStatus.ps1
    │   ├── Remove-MigrationArtifacts.ps1
    │   ├── Register-DMUScheduledTask.ps1
    │   ├── Get-DMUScheduledTask.ps1
    │   ├── Unregister-DMUScheduledTask.ps1
    │   └── Register-MigrationPhaseTasks.ps1
    ├── Private/
    │   ├── Initialize-Logging.ps1
    │   ├── New-StrongPassword.ps1
    │   ├── Invoke-BitLockerEscrow.ps1
    │   ├── Get-OneDriveSyncStatus.ps1
    │   └── Enable-OneDriveKFM.ps1
    └── Scripts/
        ├── Phase1-EntraJoin.ps1
        ├── Phase2-EscrowBitlocker.ps1
        ├── Phase3-OneDrive.ps1
        └── Phase4-Cleanup.ps1
```

## Quick Start

```powershell
git clone https://github.com/sudo-BShaw/DMU-Clean.git
cd DMU-Clean

Copy-Item .\config\MigrationConfig.example.psd1 .\config\MigrationConfig.psd1
# Edit TenantID and ProvisioningPack path

# Classic RunOnce chain
.\Setup.ps1 -ForceCleanup -LaunchPhase1

# Register Phase 2–4 as SYSTEM scheduled tasks under \DMU\ (AtStartup)
.\Setup.ps1 -ForceCleanup -UseScheduledTasks -LaunchPhase1
```

## Scheduled-task helpers

Phase scripts still register **RunOnce** by default. For a more durable hand-off (survives some logon paths better, visible in Task Scheduler), use the helpers under `\DMU\`:

| Function | Purpose |
|----------|---------|
| `Register-DMUScheduledTask` | Create one SYSTEM task (AtStartup / AtLogon / Once / OnDemand) |
| `Get-DMUScheduledTask` | List DMU tasks (also surfaces legacy `\AAD Migration\`) |
| `Unregister-DMUScheduledTask` | Remove one or all; optional `-IncludeLegacy -RemoveFolder` |
| `Register-MigrationPhaseTasks` | Wire Phase 2–4 in one call |

```powershell
# After staging scripts via Start-DeviceMigration
Register-MigrationPhaseTasks -Force

# Inspect
Get-DMUScheduledTask

# Tear down
Unregister-DMUScheduledTask -IncludeLegacy -RemoveFolder
```

Orchestrator switch: **`-UseScheduledTasks`** (also on `Setup.ps1`).

## Migration Phases

| Phase | Script | Main actions |
|-------|--------|--------------|
| **1 – Entra Join** | `Phase1-EntraJoin.ps1` | Apply PPKG, register next hop, reboot |
| **2 – BitLocker** | `Phase2-EscrowBitlocker.ps1` | Escrow keys to Entra ID, post-join registry |
| **3 – OneDrive** | `Phase3-OneDrive.ps1` | KFM policy, safety-net file copy |
| **4 – Cleanup** | `Phase4-Cleanup.ps1` | Remove tasks/temp user/artifacts, reset registry |

## Tests

```powershell
.\tests\Run-Tests.ps1
.\tests\Run-Tests.ps1 -Detailed
```

## Helpers

```powershell
Get-DeviceJoinStatus
Invoke-BitLockerEscrow -MountPoint C: -CreateProtectorIfMissing
Get-OneDriveSyncStatus
Enable-OneDriveKFM -TenantID 'your-tenant-guid'
New-StrongPassword -Length 24
Remove-MigrationArtifacts -Verbose
```

## Prerequisites

- Windows 10 / 11, PowerShell 5.1, admin rights  
- Entra ID P1 + Intune P1  
- Valid PPKG  
- Pester 5+ (tests only)

## Security Notes

- Never commit real secrets.  
- Temp admin uses a strong random password.  
- Prefer Windows LAPS long-term.  
- Verify BitLocker keys in Entra ID after Phase 2.

## Roadmap

- [x] Structure, config, logging, orchestrator  
- [x] Phase1–Phase4  
- [x] Pester unit tests  
- [x] **Scheduled-task helpers**  
- [ ] Expanded docs/

## Credits

- Original concept: [aollivierre](https://github.com/aollivierre)  
- BitLocker escrow pattern: Michael Mardahl / MSEndpointMgr  

## License

MIT
