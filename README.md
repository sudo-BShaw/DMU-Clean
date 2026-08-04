# Device Migration Utility (DMU) - Clean Edition

**Clean, modular rewrite** of the Device Migration Utility for migrating Windows devices from Workgroup / Domain Join / Hybrid Join to **Entra ID Join + Intune** while preserving user data.

Based on the excellent original work by [aollivierre/IntuneDeviceMigration](https://github.com/aollivierre/IntuneDeviceMigration).

> **Status**: Active development. Phases 1–3 are implemented (Entra Join → BitLocker escrow → OneDrive).

## Architecture

```
DMU-Clean/
├── Setup.ps1
├── config/MigrationConfig.example.psd1
└── src/
    ├── DMU.psd1 / DMU.psm1          # v0.4.0
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
        └── Phase3-OneDrive.ps1
```

## Quick Start

```powershell
git clone https://github.com/sudo-BShaw/DMU-Clean.git
cd DMU-Clean

Copy-Item .\config\MigrationConfig.example.psd1 .\config\MigrationConfig.psd1
# Edit TenantID and ProvisioningPack path

.\Setup.ps1 -ForceCleanup -LaunchPhase1          # full prep + Phase 1
.\Setup.ps1 -LaunchPhase1 -SkipReboot            # no auto-reboot
```

## Migration Phases

### Phase 1 – Entra Join
1. Validate PPKG  
2. Optional migration wallpaper  
3. Apply PPKG (`Install-ProvisioningPackage` / `provtool.exe`)  
4. Register Phase 2 via RunOnce  
5. Reboot

### Phase 2 – BitLocker Escrow
1. Escrow recovery keys to Entra ID (`BackupToAAD-BitLockerKeyProtector`)  
2. Post-migration registry (legal notice, disable AutoAdminLogon)  
3. Register Phase 3 via RunOnce  
4. Reboot  

Standalone: `Invoke-BitLockerEscrow -MountPoint C: -CreateProtectorIfMissing`

### Phase 3 – OneDrive
1. Apply Known Folder Move policy settings (`Enable-OneDriveKFM`) when `UseOneDriveKFM = $true`  
2. Start the OneDrive client if installed  
3. Report sync / folder status (`Get-OneDriveSyncStatus`)  
4. Safety-net copy of Desktop / Documents / Pictures / Downloads into `OneDrive\DMU-Backup`  
5. Register Phase 4 (cleanup) via RunOnce  
6. Reboot  

Standalone helpers:

```powershell
Get-OneDriveSyncStatus
Enable-OneDriveKFM -TenantID 'your-tenant-guid'
```

**Note:** Full OneDrive sync still requires the end user to sign in with their Entra ID account. Phase 3 prepares policy and a local safety-net copy; it does not replace user sign-in.

## What `Start-DeviceMigration` does

1. Validates config (rejects placeholder TenantID)  
2. Logging  
3. Optional cleanup  
4. Device status check  
5. Working directories + strong-password temp admin  
6. Stages all `Phase*.ps1` scripts + config into `C:\ProgramData\AADMigration`  
7. Optionally launches Phase 1 (`-LaunchPhase1`)

## Prerequisites

- Windows 10 / 11, PowerShell 5.1, admin rights  
- Entra ID P1 + Intune P1  
- Valid PPKG  
- BitLocker cmdlets (Phase 2)  
- OneDrive client recommended (Phase 3)

## Security Notes

- Never commit real secrets.  
- Temp admin uses a cryptographically strong random password.  
- Prefer Windows LAPS long-term.  
- Verify BitLocker keys in Entra ID after Phase 2.

## Roadmap

- [x] Structure, config, logging, orchestrator  
- [x] Phase1-EntraJoin  
- [x] Phase2-EscrowBitlocker  
- [x] **Phase3-OneDrive**  
- [ ] Phase4-Cleanup  
- [ ] Scheduled-task helpers  
- [ ] Pester tests  
- [ ] docs/

## Credits

- Original concept: [aollivierre](https://github.com/aollivierre)  
- BitLocker escrow pattern: Michael Mardahl / MSEndpointMgr  
- Community migration approaches (Modern Endpoint, Mauvtek, etc.)

## License

MIT
