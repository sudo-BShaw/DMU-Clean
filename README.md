# Device Migration Utility (DMU) - Clean Edition

**Clean, modular rewrite** of the Device Migration Utility for migrating Windows devices from Workgroup / Domain Join / Hybrid Join to **Entra ID Join + Intune** while preserving user data.

Based on the excellent original work by [aollivierre/IntuneDeviceMigration](https://github.com/aollivierre/IntuneDeviceMigration).

> **Status**: v0.6.1 – Core phases, scheduled-task helpers, Pester tests, and expanded documentation.

## Documentation

Full docs live under **[docs/](docs/README.md)**:

| Guide | Topic |
|-------|--------|
| [Architecture](docs/Architecture.md) | Design, layout, phase flow |
| [Getting Started](docs/Getting-Started.md) | Clone, configure, first run |
| [Configuration](docs/Configuration.md) | Config keys and validation |
| [Phases](docs/Phases.md) | Phase 1–4 detail |
| [Scheduled Tasks](docs/Scheduled-Tasks.md) | RunOnce vs `\DMU\` tasks |
| [Functions](docs/Functions.md) | API reference |
| [Security](docs/Security.md) | Secrets, temp admin, BitLocker |
| [Testing](docs/Testing.md) | Pester suite |
| [Troubleshooting](docs/Troubleshooting.md) | Common failures |

## Quick Start

```powershell
git clone https://github.com/sudo-BShaw/DMU-Clean.git
cd DMU-Clean

Copy-Item .\config\MigrationConfig.example.psd1 .\config\MigrationConfig.psd1
# Edit TenantID and ProvisioningPack path

.\Setup.ps1 -ForceCleanup -LaunchPhase1
.\Setup.ps1 -ForceCleanup -UseScheduledTasks -LaunchPhase1   # also register \DMU\ tasks
```

## Architecture (summary)

```
Setup.ps1 → Start-DeviceMigration
  → Phase1 Entra Join (PPKG)
  → Phase2 BitLocker escrow
  → Phase3 OneDrive KFM + safety-net copy
  → Phase4 Cleanup
```

Helpers: `Get-DeviceJoinStatus`, `Invoke-BitLockerEscrow`, `Get-OneDriveSyncStatus`, `Enable-OneDriveKFM`, `Register-DMUScheduledTask`, `New-StrongPassword`, and more — see [Functions](docs/Functions.md).

## Tests

```powershell
.\tests\Run-Tests.ps1
```

## Security

Never commit real TenantIDs or PPKGs. Temp admin passwords are generated at runtime. Verify BitLocker keys in Entra ID after Phase 2. Details: [Security](docs/Security.md).

## Roadmap

- [x] Modular structure + orchestrator  
- [x] Phases 1–4  
- [x] Pester tests  
- [x] Scheduled-task helpers  
- [x] Expanded docs  

## Credits

- Original concept: [aollivierre](https://github.com/aollivierre)  
- BitLocker escrow pattern: Michael Mardahl / MSEndpointMgr  

## License

MIT
