# Device Migration Utility (DMU) - Clean Edition

**Clean, modular rewrite** of the Device Migration Utility for migrating Windows devices from Workgroup / Domain Join / Hybrid Join to **Entra ID Join + Intune** while preserving user data.

Based on the excellent original work by [aollivierre/IntuneDeviceMigration](https://github.com/aollivierre/IntuneDeviceMigration), this edition focuses on:

- **Security first** – no hardcoded secrets or weak passwords
- **Modular design** – small, testable functions instead of monolithic scripts
- **Reduced duplication** – shared logging, bootstrap, and error handling
- **Clear configuration** – example-only config files
- **Maintainability** – consistent naming, modern PowerShell practices, and documentation

> **Status**: Active development. Orchestrator + Phase 1 (Entra Join) + Phase 2 (BitLocker escrow) are implemented.

## Key Improvements Over Original

| Area | Original | This Edition |
|------|----------|--------------|
| Secrets | Hardcoded TenantID + weak `Default1234` password | Example config only; random strong temp password generated at runtime |
| Structure | Large monolithic scripts + Archive bloat | Modular `src/` layout with Public/Private functions |
| Logging | Duplicated bootstrap in every script | Single shared `Initialize-Logging` + consistent helpers |
| Variables | Mixed `$Mode` / `$global:mode`, casing issues | Consistent naming and parameterization |
| Entry point | Heavy Setup.ps1 that re-downloads everything | Thin entry point that calls `Start-DeviceMigration` |
| Documentation | Duplicate README files | Single clear README |

## Architecture

```
DMU-Clean/
├── README.md
├── LICENSE
├── Setup.ps1
├── config/
│   └── MigrationConfig.example.psd1
├── src/
│   ├── DMU.psd1 / DMU.psm1          # v0.3.0
│   ├── Public/
│   │   ├── Start-DeviceMigration.ps1
│   │   ├── Get-DeviceJoinStatus.ps1
│   │   └── Remove-MigrationArtifacts.ps1
│   ├── Private/
│   │   ├── Initialize-Logging.ps1
│   │   ├── New-StrongPassword.ps1
│   │   └── Invoke-BitLockerEscrow.ps1
│   └── Scripts/
│       ├── Phase1-EntraJoin.ps1
│       └── Phase2-EscrowBitlocker.ps1
├── tests/
└── docs/
```

## Quick Start

```powershell
git clone https://github.com/sudo-BShaw/DMU-Clean.git
cd DMU-Clean

Copy-Item .\config\MigrationConfig.example.psd1 .\config\MigrationConfig.psd1
# Edit TenantID and ProvisioningPack path

# Prepare only
.\Setup.ps1 -ForceCleanup

# Prepare + run Phase 1 (PPKG → RunOnce Phase 2 → reboot)
.\Setup.ps1 -ForceCleanup -LaunchPhase1

# Skip automatic reboot
.\Setup.ps1 -LaunchPhase1 -SkipReboot
```

## Migration Phases

### Phase 1 – Entra Join (`Phase1-EntraJoin.ps1`)
1. Validate PPKG  
2. Optional migration wallpaper  
3. `Install-ProvisioningPackage` (or `provtool.exe`)  
4. Register Phase 2 via RunOnce  
5. Reboot (unless `-SkipReboot`)

### Phase 2 – BitLocker Escrow (`Phase2-EscrowBitlocker.ps1`)
1. Escrow recovery password protectors to Entra ID via `BackupToAAD-BitLockerKeyProtector`  
2. Apply post-migration registry settings (legal notice, disable AutoAdminLogon, hide last username)  
3. Register Phase 3 (OneDrive) via RunOnce when available, otherwise a cleanup fallback  
4. Reboot (unless `-SkipReboot`)

You can also run the escrow helper standalone:

```powershell
Invoke-BitLockerEscrow -MountPoint C: -CreateProtectorIfMissing
```

**Important:** Always verify the recovery key appears in the Entra ID / Intune admin center after escrow. Policy mismatches can cause the cmdlet to report success while the key is not yet visible.

## What `Start-DeviceMigration` does

1. Loads and validates configuration  
2. Initializes logging  
3. Optional cleanup (`-ForceCleanup`)  
4. Device join / enrollment status check  
5. Creates working directories  
6. Creates / resets temporary local admin with a strong random password  
7. Validates PPKG path  
8. Stages all `Phase*.ps1` scripts + config into `C:\ProgramData\AADMigration`  
9. Optionally launches Phase 1 (`-LaunchPhase1`)

## Prerequisites

- Windows 10 / 11  
- PowerShell 5.1  
- Administrative rights  
- Entra ID P1 + Intune P1  
- Valid Windows Provisioning Package (PPKG)  
- BitLocker cmdlets available (for Phase 2)

## Security Notes

- Never commit real TenantIDs, PATs, or passwords.  
- Temporary accounts use a cryptographically strong random password.  
- Prefer Windows LAPS for ongoing local admin management.  
- Verify BitLocker keys in Entra ID after Phase 2.

## Roadmap

- [x] Clean structure, example config, shared logging  
- [x] `Start-DeviceMigration` orchestrator  
- [x] Strong random temp password  
- [x] Phase1-EntraJoin  
- [x] **Phase2-EscrowBitlocker**  
- [ ] Phase3-OneDrive helpers  
- [ ] Phase4-Cleanup  
- [ ] Scheduled-task helpers  
- [ ] Pester tests  
- [ ] Full documentation in `docs/`

## Credits

- Original concept: [aollivierre](https://github.com/aollivierre)  
- BitLocker escrow pattern: Michael Mardahl / MSEndpointMgr  
- Community migration approaches (Modern Endpoint, Mauvtek, etc.)

## License

MIT
