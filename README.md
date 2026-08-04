# Device Migration Utility (DMU) - Clean Edition

**Clean, modular rewrite** of the Device Migration Utility for migrating Windows devices from Workgroup / Domain Join / Hybrid Join to **Entra ID Join + Intune** while preserving user data.

Based on the excellent original work by [aollivierre/IntuneDeviceMigration](https://github.com/aollivierre/IntuneDeviceMigration).

> **Status**: Core migration phases complete + Pester unit tests (v0.5.1).

## Architecture

```
DMU-Clean/
├── Setup.ps1
├── config/MigrationConfig.example.psd1
├── tests/
│   ├── Helpers.ps1
│   ├── Run-Tests.ps1
│   ├── New-StrongPassword.Tests.ps1
│   ├── Get-DeviceJoinStatus.Tests.ps1
│   ├── Get-OneDriveSyncStatus.Tests.ps1
│   ├── Enable-OneDriveKFM.Tests.ps1
│   ├── Invoke-BitLockerEscrow.Tests.ps1
│   ├── Remove-MigrationArtifacts.Tests.ps1
│   └── Start-DeviceMigration.Tests.ps1
└── src/
    ├── DMU.psd1 / DMU.psm1          # v0.5.1
    ├── Public/
    │   ├── Start-DeviceMigration.ps1
    │   ├── Get-DeviceJoinStatus.ps1
    │   └── Remove-MigrationArtifacts.ps1
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

.\Setup.ps1 -ForceCleanup -LaunchPhase1          # prep + Phase 1 → automatic chain
.\Setup.ps1 -LaunchPhase1 -SkipReboot            # no auto-reboot
```

After Phase 1, RunOnce drives Phase 2 → 3 → 4 across reboots.

## Running tests

Requires **Pester 5+** (the runner installs it for CurrentUser if missing).

```powershell
# From the repo root
.\tests\Run-Tests.ps1

# Verbose output
.\tests\Run-Tests.ps1 -Detailed
```

Coverage includes:

| Area | What is asserted |
|------|------------------|
| `New-StrongPassword` | SecureString output, length, charset, uniqueness, read-only |
| `Get-DeviceJoinStatus` | Object shape, JoinType values, NeedsMigration decision matrix |
| `Get-OneDriveSyncStatus` | Property surface, explicit UserProfile |
| `Enable-OneDriveKFM` | Parameters, `-WhatIf` safety |
| `Invoke-BitLockerEscrow` | Parameters, `-WhatIf` when BitLocker cmdlets exist |
| `Remove-MigrationArtifacts` | Parameter surface, isolated path cleanup |
| `Start-DeviceMigration` | Parameters, missing config / placeholder TenantID errors |

## Migration Phases

| Phase | Script | Main actions |
|-------|--------|--------------|
| **1 – Entra Join** | `Phase1-EntraJoin.ps1` | Validate & apply PPKG, optional wallpaper, register Phase 2, reboot |
| **2 – BitLocker** | `Phase2-EscrowBitlocker.ps1` | Escrow recovery keys to Entra ID, legal notice / auto-logon registry, register Phase 3 |
| **3 – OneDrive** | `Phase3-OneDrive.ps1` | KFM policy, start OneDrive, safety-net file copy, register Phase 4 |
| **4 – Cleanup** | `Phase4-Cleanup.ps1` | Remove RunOnce entries, scheduled tasks, temp admin, reset registry, remove working dir (logs kept by default) |

## Helpers (callable standalone)

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
- Valid provisioning package (PPKG)  
- BitLocker cmdlets (Phase 2)  
- OneDrive client recommended (Phase 3)  
- Pester 5+ (for tests only)

## Security Notes

- Never commit real secrets.  
- Temp admin uses a cryptographically strong random password.  
- Prefer Windows LAPS long-term.  
- Verify BitLocker keys in Entra ID after Phase 2.  
- Confirm OneDrive sync after the user signs in.

## Roadmap

- [x] Structure, config, logging, orchestrator  
- [x] Phase1–Phase4  
- [x] **Pester unit tests**  
- [ ] Scheduled-task creation helpers (optional alternative to RunOnce)  
- [ ] Expanded docs/

## Credits

- Original concept: [aollivierre](https://github.com/aollivierre)  
- BitLocker escrow pattern: Michael Mardahl / MSEndpointMgr  
- Community migration approaches (Modern Endpoint, Mauvtek, etc.)

## License

MIT
